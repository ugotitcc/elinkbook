import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_search_state.dart';
import 'package:elinkbook/screens/pdf_search_panel.dart';

void main() {
  testWidgets('輸入文字後 500ms 內未再變動才觸發 onQueryChanged（防手震延遲）', (tester) async {
    final queries = <String>[];
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: queries.add,
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'ab');
    await tester.pump(const Duration(milliseconds: 100));
    expect(queries, isEmpty, reason: '連續輸入期間不應觸發，防止每個字元都各自查詢一次');

    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['ab']);
  });

  testWidgets('清空輸入框時立即觸發 onQueryChanged("")，不等待防手震延遲', (tester) async {
    final queries = <String>[];
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: queries.add,
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'a');
    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['a']);

    await tester.enterText(find.byKey(const Key('pdf_search_field')), '');
    await tester.pump();
    expect(queries, ['a', '']);
  });

  testWidgets('query 為空時不顯示計數器/導覽按鈕/空結果訊息', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_counter')), findsNothing);
    expect(find.byKey(const Key('pdf_search_empty')), findsNothing);
    expect(find.byKey(const Key('pdf_search_loading')), findsNothing);
  });

  testWidgets('isSearching 為 true 時顯示載入中指示', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'abc', isSearching: true, matchCount: 0, currentIndex: null),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_loading')), findsOneWidget);
  });

  testWidgets('搜尋完成但 matchCount 為 0 時顯示「找不到符合的文字」', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'xyz', isSearching: false, matchCount: 0, currentIndex: null),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_empty')), findsOneWidget);
    expect(find.text('找不到符合的文字'), findsOneWidget);
  });

  testWidgets('有符合結果時顯示「目前/共 N」計數器，點擊上一個/下一個觸發對應回呼',
      (tester) async {
    var nextCount = 0;
    var prevCount = 0;
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'abc', isSearching: false, matchCount: 5, currentIndex: 1),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () => nextCount++,
          onPrevious: () => prevCount++,
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_counter')), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_search_next_button')));
    expect(nextCount, 1);
    await tester.tap(find.byKey(const Key('pdf_search_prev_button')));
    expect(prevCount, 1);
  });

  testWidgets('initialQuery 非空時，文字輸入框預先填入該查詢字串', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
          initialQuery: '既有查詢',
        ),
      ),
    ));

    expect(find.text('既有查詢'), findsOneWidget);
  });
}
