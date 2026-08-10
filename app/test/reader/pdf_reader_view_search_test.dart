import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

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

  testWidgets('搜尋 "Page" 正確找出每頁各一筆符合結果，座標落在合理範圍內', (tester) async {
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));

    expect(matches, isNotNull);
    expect(matches!.length, 5);
    for (var i = 0; i < 5; i++) {
      expect(matches[i].pageIndex, i);
      expect(matches[i].text.toLowerCase(), contains('page'));
      expect(matches[i].rect.left, greaterThanOrEqualTo(0));
      expect(matches[i].rect.right, lessThanOrEqualTo(1));
      expect(matches[i].rect.top, lessThan(matches[i].rect.bottom));
    }
  });

  testWidgets('搜尋 "ELINKBOOK"（大小寫不敏感）仍能找到符合結果', (tester) async {
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'elinkbook'));

    expect(matches, isNotNull);
    expect(matches!.length, 5);
  });

  testWidgets('查無符合結果時回傳空清單，不拋出例外', (tester) async {
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'nonexistent_xyz'));

    expect(matches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('無文字層的 PDF（sample.pdf）搜尋回傳空清單，不拋出例外', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'anything'));

    expect(matches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setSearchHighlights 後畫面渲染出對應的高亮 widget，含目前符合結果的獨立 Key',
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));
    expect(matches, isNotNull);

    PdfReaderView.setSearchHighlights(key, matches!, currentIndex: 0);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_search_highlight_0_0')), findsOneWidget);
  });

  testWidgets('目前符合結果（isCurrent）額外疊加外框，其餘符合結果無外框（審查修正 Minor #3）',
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));
    expect(matches, isNotNull);

    PdfReaderView.setSearchHighlights(key, matches!, currentIndex: 0);
    await tester.pump();

    final currentContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_0_0')),
        matching: find.byType(Container),
      ),
    );
    final currentDecoration = currentContainer.decoration as BoxDecoration;
    expect(currentDecoration.border, isNotNull);

    // 頁碼 1（index 1）的符合結果不是目前選取項，不應有外框。
    PdfReaderView.jumpToPage(key, 1);
    await tester.pump(const Duration(milliseconds: 300));
    final otherContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_1_1')),
        matching: find.byType(Container),
      ),
    );
    final otherDecoration = otherContainer.decoration as BoxDecoration;
    expect(otherDecoration.border, isNull);
  });

  testWidgets('State 尚未掛載時，search／setSearchHighlights 皆靜默忽略', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    final matches = await PdfReaderView.search(orphanKey, 'x');
    expect(matches, isEmpty);
    expect(
      () => PdfReaderView.setSearchHighlights(orphanKey, const [], currentIndex: null),
      returnsNormally,
    );
  });
}
