import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

void main() {
  setUp(() => pdfrxInitialize());

  /// 等待 pdfrx 真正完成非同步載入（比照 pdf_reader_view_test.dart 既有
  /// 寫法），最多輪詢 30 次、每次 100ms。
  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('不傳雙頁參數時，行為與 Issue 1 完全相同（零回歸基準）',
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
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    PdfReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('dualPageMode: never 時，行為與不傳參數完全相同',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.never,
          isLandscape: true, // never 模式下方向不應影響結果。
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    expect(lastPageInfo?.pageIndex, 0);
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1); // 步進 1，非雙頁步進。
  });

  testWidgets('dualPageMode: always 時，開書後即套用雙頁版面（錨點頁仍為 0）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
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
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // 封面獨立時第 0 頁本身即為一個完整 spread，錨點頁仍是 0——
    // 與單頁模式的初始狀態在「開書即在第 0 頁」這件事上一致，
    // 差異要到 nextPage（Task 6）才會顯現。
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('雙頁模式下，跳到 spread 的右頁後，頁碼回報 spread 錨點頁',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
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
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // jumpToPage(2)：page 2 屬於 spread [1,2]，錨點頁為 1。
    PdfReaderView.jumpToPage(key, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '回報 spread 錨點頁，不是 2');
  });
}
