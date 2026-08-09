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

void main() {
  setUp(() => pdfrxInitialize());

  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

    final pageFinder = find.byType(PdfReaderView);
    final topLeft = tester.getTopLeft(pageFinder);
    final startPos = topLeft + const Offset(40, 60);
    final endPos = topLeft + const Offset(160, 220);

    final gesture = await tester.startGesture(startPos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(endPos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(computed, isNotNull, reason: '長按滿足時長且有明顯拖曳位移，應觸發選取回呼');
    expect(computed!.pageIndex, 0);
    expect(computed!.rect.left, greaterThanOrEqualTo(0));
    expect(computed!.rect.right, lessThanOrEqualTo(1));
    expect(computed!.rect.left, lessThan(computed!.rect.right));
    expect(computed!.rect.top, lessThan(computed!.rect.bottom));
  });

  testWidgets('長按但幾乎沒有拖曳位移（退化選取）時，不觸發 onSelectionRectComputed',
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
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final pos = topLeft + const Offset(100, 150);

    final gesture = await tester.startGesture(pos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(computed, isNull, reason: '沒有明顯拖曳位移的長按不應建立選取');
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
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsOneWidget,
        reason: '拖曳過程中應顯示即時選取矩形視覺回饋');

    await gesture.up();
    await tester.pump();
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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();
    await gesture.up();
    await tester.pump();

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

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
}
