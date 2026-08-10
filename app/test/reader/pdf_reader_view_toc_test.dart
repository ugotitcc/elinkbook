import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';

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

  testWidgets('正確解析巢狀大綱，保留階層與頁碼（0-indexed）', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final items = await tester.runAsync(
      () => PdfReaderView.loadTableOfContents(key),
    );

    expect(items, isNotNull);
    expect(items!.length, 3);
    expect(items[0].title, 'Part One');
    expect(items[0].pageIndex, 0);
    expect(items[0].children.length, 2);
    expect(items[0].children[0].title, 'Chapter 1');
    expect(items[0].children[0].pageIndex, 0);
    expect(items[0].children[1].title, 'Chapter 2');
    expect(items[0].children[1].pageIndex, 1);
    expect(items[1].title, 'Part Two');
    expect(items[1].children.length, 2);
    expect(items[1].children[0].pageIndex, 2);
    expect(items[1].children[1].pageIndex, 3);
    expect(items[2].title, 'Chapter 5');
    expect(items[2].pageIndex, 4);
    expect(items[2].children, isEmpty);

    final ids = <String>{};
    void collect(List<PdfTocItem> nodes) {
      for (final n in nodes) {
        expect(ids.add(n.stableId), isTrue, reason: 'stableId 須全域唯一');
        collect(n.children);
      }
    }

    collect(items);
  });

  testWidgets('無大綱的 PDF（sample.pdf）回傳空清單，不拋出例外', (tester) async {
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

    final items = await tester.runAsync(
      () => PdfReaderView.loadTableOfContents(key),
    );

    expect(items, isEmpty);
  });

  testWidgets('State 尚未掛載（key 未對應任何 widget）時回傳空清單', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    final items = await PdfReaderView.loadTableOfContents(orphanKey);
    expect(items, isEmpty);
  });
}
