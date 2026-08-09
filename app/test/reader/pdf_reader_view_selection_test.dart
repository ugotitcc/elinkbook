import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';

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
}
