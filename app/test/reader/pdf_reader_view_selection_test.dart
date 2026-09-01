import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('不傳選取回呼時，行為與 Issue 1/2/3 完全相同（零回歸基準）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '翻頁行為不受本工單新增邏輯影響');
  });

  testWidgets('長按拖曳後放開，觸發 onSelectionRectComputed 且矩形座標在合理範圍內',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final pageFinder = find.byType(PdfReaderView);
    final topLeft = tester.getTopLeft(pageFinder);
    final startPos = topLeft + const Offset(40, 60);
    final endPos = topLeft + const Offset(160, 220);

    final gesture = await tester.startGesture(startPos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(endPos);
    await tester.pump();
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull, reason: '長按滿足時長且有明顯拖曳位移，應觸發選取回呼');
    expect(computed!.pageIndex, 0);
    expect(computed!.rect.left, greaterThanOrEqualTo(0));
    expect(computed!.rect.right, lessThanOrEqualTo(1));
    expect(computed!.rect.left, lessThan(computed!.rect.right));
    expect(computed!.rect.top, lessThan(computed!.rect.bottom));
  });

  testWidgets(
      '重現真機彈跳雜訊（tmp/epic-25/log-issue5/device-2.txt 前 21 行）'
      '仍能觸發 onSelectionRectComputed（Epic 25 Issue 5 回歸測試——'
      '修復前，同樣的彈跳序列會讓 GestureDetector 的內建長按計時器不斷'
      '被新的 down 打斷，onLongPressStart 永遠不會觸發，選取完全無法啟動）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final pageFinder = find.byType(PdfReaderView);
    final topLeft = tester.getTopLeft(pageFinder);
    // 真實裝置 2 彈跳序列的相對位移量（毫米級微幅飄移，非憑空編造，
    // 換算自 device-2.txt 前 21 行的實際座標差值），疊加在頁面上一個
    // 固定基準點之上。
    Offset at(double dx, double dy) => topLeft + Offset(60 + dx, 80 + dy);

    final downTimes = [0, 69, 183, 196, 253, 257, 313, 399, 413];
    final downOffsets = [
      const Offset(0, 0),
      const Offset(0, 0),
      const Offset(-1.4, 2.0),
      const Offset(-1.4, 2.0),
      const Offset(-1.0, 2.0),
      const Offset(2.5, 5.4),
      const Offset(3.5, 5.9),
      const Offset(11.8, 13.8),
      const Offset(11.8, 13.8),
    ];
    final upTimes = [49, 134, 190, 251, 255, 302, 322, 409, 538];

    var lastEventTime = 0;
    for (var i = 0; i < downTimes.length; i++) {
      await tester.pump(Duration(milliseconds: downTimes[i] - lastEventTime));
      final gesture = await tester.startGesture(at(
        downOffsets[i].dx,
        downOffsets[i].dy,
      ));
      lastEventTime = downTimes[i];
      await tester.pump(Duration(milliseconds: upTimes[i] - lastEventTime));
      await gesture.up();
      lastEventTime = upTimes[i];
    }

    // 明顯的拖曳，確保不是退化選取。
    final finalGesture = await tester.startGesture(at(11.8, 13.8));
    await tester.pump(const Duration(milliseconds: 40));
    await finalGesture.moveTo(at(160, 160));
    await tester.pump();
    await finalGesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull,
        reason: '修復前這段彈跳序列會讓長按永遠無法啟動，selection 回呼'
            '永遠不會觸發；修復後應正確判定為一次連續長按並完成選取');
  });

  testWidgets('框選拖曳進行中，PdfViewer 的 panEnabled/scaleEnabled 應暫時關閉；放開後恢復',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfViewerParams paramsOf() =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

    expect(paramsOf().panEnabled, isTrue, reason: '拖曳開始前應維持預設可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '拖曳開始前應維持預設可縮放');

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

    expect(paramsOf().panEnabled, isFalse, reason: '框選拖曳進行中應關閉底層平移，避免與長按框選手勢衝突');
    expect(paramsOf().scaleEnabled, isFalse, reason: '框選拖曳進行中應關閉底層縮放');

    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(paramsOf().panEnabled, isFalse, reason: '拖曳移動過程中仍應維持關閉');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(paramsOf().panEnabled, isTrue, reason: '放開手指、選取完成後應恢復可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '放開手指、選取完成後應恢復可縮放');
  });

  testWidgets('框選拖曳被第二指觸控取消後，PdfViewer 的 panEnabled/scaleEnabled 應恢復',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfViewerParams paramsOf() =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger =
        await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();

    expect(paramsOf().panEnabled, isFalse, reason: '框選拖曳進行中應關閉底層平移');

    final secondFinger =
        await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(paramsOf().panEnabled, isTrue, reason: '第二指觸控取消框選後應恢復可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '第二指觸控取消框選後應恢復可縮放');

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
      '長按但幾乎沒有拖曳位移（退化選取）時，仍觸發 onSelectionRectComputed，'
      '矩形為長按落點本身的零面積點（epic-25 Issue 6，是否顯示工具列的判斷'
      '交給 ReaderScreen，見 reader_screen_test.dart）', (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final pos = topLeft + const Offset(100, 150);

    final gesture = await tester.startGesture(pos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull,
        reason: '退化選取（長按無明顯拖曳）不應再被整個吞掉，須送出落點本身');
    expect(computed!.rect.left, computed!.rect.right,
        reason: '退化選取換算出的矩形須是零面積的點（left==right）');
    expect(computed!.rect.top, computed!.rect.bottom,
        reason: '退化選取換算出的矩形須是零面積的點（top==bottom）');
  });

  testWidgets(
      '長按有些微拖曳但仍小於 minFraction 門檻時，一樣視為退化選取，'
      '送出的落點固定用長按起點、不隨拖曳終點飄移', (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final areaSize = tester.getSize(find.byType(PdfReaderView));
    final start = topLeft + const Offset(100, 150);
    // 位移只有頁面寬度的 0.3%，遠小於 minFraction（1%），仍應視為退化選取。
    final end = start + Offset(areaSize.width * 0.003, 0);

    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull);
    expect(computed!.rect.left, computed!.rect.right,
        reason: '仍在 minFraction 門檻內的微小移動，一樣視為退化選取的點');
    expect(computed!.rect.top, computed!.rect.bottom,
        reason: '退化選取換算出的矩形須是零面積的點（top==bottom）');
    // 落點須在 [0,1] 百分比範圍內（退化選取的點矩形）。
    expect(computed!.rect.left, inInclusiveRange(0.0, 1.0));
    expect(computed!.rect.top, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('長按拖曳過程中即時顯示選取矩形視覺回饋', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsOneWidget,
        reason: '拖曳過程中應顯示即時選取矩形視覺回饋');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing,
        reason: '放開後即時回饋應消失（改由呼叫端決定是否顯示 AnnotationToolbar）');
  });

  testWidgets('框選進行中第二指觸控介入時，取消選取並觸發 onSelectionCanceled',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    var canceled = false;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
          onSelectionCanceled: () => canceled = true,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsOneWidget);

    final secondFinger = await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(canceled, isTrue, reason: '第二指觸控應取消進行中的框選');
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing);

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    // 等待 DoubleTapGestureRecognizer 的逾時計時器結束。
    await tester.pump(const Duration(milliseconds: 300));
    expect(computed, isNull, reason: '被取消的選取不應觸發 onSelectionRectComputed');
  });

  testWidgets('cropEditModeActive=true 時，長按拖曳不觸發框選（與裁切互斥）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          cropEditModeActive: true,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing,
        reason: '裁切編輯模式下不應顯示框選視覺回饋');

    await gesture.up();
    await tester.pump();
    expect(computed, isNull);
  });

  testWidgets('widgetRect 相對整個 PdfReaderView 尺寸，而非單一頁面（多頁情境下 top 應反映頁面在文件中的位置）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 2000,
          child: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onSelectionRectComputed: (info) => computed = info,
          ),
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull);
    // widgetRect 與 rect 皆為 0-1 範圍內的有效值；在夠高的可視區域內，
    // 第一頁通常從畫面最頂端開始，widgetRect.top 應是一個很小的值。
    expect(computed!.widgetRect.top, greaterThanOrEqualTo(0));
    expect(computed!.widgetRect.top, lessThanOrEqualTo(1));
  });

  testWidgets('refreshAnnotations 呼叫後，對應頁面顯示標記疊圖', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget,
        reason: 'refreshAnnotations 應觸發重繪並顯示對應頁面的標記');
  });

  testWidgets('同一頁有多筆標記時，逐筆使用不同 key 渲染，不觸發 Duplicate Key 例外',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.3, right: 0.5, bottom: 0.4),
        tint: 0x73F472B6,
      ),
    ]);
    await tester.pump();

    // 兩筆標記都在 page 0，若 key 只用 pageIndex 組成會彼此相同，
    // Flutter 會在 pumpWidget/pump 期間擲出「Multiple widgets used the
    // same key」例外，tester.pump() 之後 takeException() 會抓到；本測試
    // 先確認沒有例外，再確認兩個 key 都各自渲染出一個 widget。
    expect(tester.takeException(), isNull,
        reason: '同頁多筆標記不應觸發 Duplicate Key 例外');
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget);
    expect(find.byKey(const Key('pdf_reader_decoration_0_1')), findsOneWidget);
  });

  testWidgets('再次呼叫 refreshAnnotations 傳入空清單時，既有標記全部移除',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget);

    PdfReaderView.refreshAnnotations(key, const []);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing,
        reason: '整批送出語意（非增量 diff）：空清單代表本書已無任何標記');
  });

  testWidgets('裁切啟用時，完全落在裁切範圍外的標記不渲染', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: PdfCropMode.manual,
          pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0, top: 0, right: 0.05, bottom: 0.05), // 完全在裁切範圍外。
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing,
        reason: '標記完全落在裁切可視範圍外時不應渲染');
  });

  testWidgets('雙頁模式下，在右頁長按拖曳，選取結果歸屬右頁而非左頁',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    // 封面獨立顯示，第一個雙頁 spread 是 [1,2]（0-indexed page 1、2）。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 找到右頁（page 2）的疊加層：以其手勢偵測層的 Positioned.fill 所在
    // RenderBox 中心點觸發長按拖曳。由於 LTR 排版下 spread [1,2] 內
    // page 2 在右側，直接對整個 PdfReaderView 右半部觸發手勢即可命中。
    final box = tester.getRect(find.byType(PdfReaderView));
    final rightHalfStart = Offset(box.left + box.width * 0.75, box.top + box.height * 0.3);
    final rightHalfEnd = Offset(box.left + box.width * 0.9, box.top + box.height * 0.5);

    final gesture = await tester.startGesture(rightHalfStart);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(rightHalfEnd);
    await tester.pump();
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull);
    expect(computed!.pageIndex, 2,
        reason: 'spread [1,2] 內觸控畫面右半部應命中 page 2（0-indexed），'
            '不是 page 1');
  });

  testWidgets('框選涵蓋整頁時，onSelectionRectComputed 回報的 text 內含頁面文字',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final box = tester.getRect(find.byType(PdfReaderView));
    final startPos = Offset(box.left + 20, box.top + 20);
    final endPos = Offset(box.right - 20, box.bottom - 20);

    final gesture = await tester.startGesture(startPos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(endPos);
    await tester.pump();
    await gesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull);
    expect(computed!.text.toLowerCase(), contains('page'),
        reason: '框選涵蓋整頁時應萃取出頁面上的文字內容（例如 "Page 1"，'
            '見 pdf_reader_view_search_test.dart 已驗證此 fixture 每頁'
            '皆含 "Page" 字樣）。');
  });

  testWidgets('框選完成後文字萃取尚未完成前又開始下一次框選，只有最後一次結果生效（競速防護）',
      (tester) async {
    var renderedCount = 0;
    final results = <PdfSelectionInfo>[];
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => results.add(info),
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final box = tester.getRect(find.byType(PdfReaderView));

    // 第一次框選：放開手指、觸發文字萃取，但刻意不用 tester.runAsync 讓它
    // 有機會真正推進（沒有 runAsync 包住，真實 FFI 呼叫不會實際完成），
    // 模擬「文字萃取還卡在半路」的狀態。
    final firstGesture = await tester.startGesture(
      Offset(box.left + 20, box.top + 20),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstGesture.moveTo(Offset(box.left + 100, box.top + 100));
    await tester.pump();
    await firstGesture.up();
    await tester.pump();

    // 第二次框選：在第一次的文字萃取還沒完成前就開始，正常完整跑完。
    final secondGesture = await tester.startGesture(
      Offset(box.left + 20, box.top + 20),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await secondGesture.moveTo(Offset(box.right - 20, box.bottom - 20));
    await tester.pump();
    await secondGesture.up();
    await pumpUntilPdfReady(tester, condition: () => results.isNotEmpty);

    // 讓第一次可能還卡著的文字萃取有機會跑完——若世代編號防護失效，
    // 這裡才會補上一筆過期結果。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(results.length, 1,
        reason: '第一次框選的過期文字萃取結果應被世代編號防護擋下，不應'
            '呼叫 onSelectionRectComputed；只有第二次（最新一次）框選的'
            '結果應該送達，否則使用者新一次框選的狀態會被過期結果覆蓋'
            '（見審查報告 Important #2）。');
  });
}
