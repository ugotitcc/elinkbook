import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NotesBottomSheet(
        bookId: bookId,
        bookmarksRepository: repository,
        currentPosition: currentPosition,
        onBookmarkSelected: onBookmarkSelected ?? (_) {},
      ),
    ),
  ));
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}

void main() {
  testWidgets('開啟後顯示兩個分頁籤，預設在書籤分頁', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(find.byKey(const Key('notes_sheet_tab_bookmarks')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_tab_annotations')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_bookmark_list')), findsOneWidget);
  });

  testWidgets('切至「劃線與備註」分頁顯示空狀態佔位符', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('書籤分頁正確依位置順序顯示清單', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', progression: 0.8));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await _pumpSheet(tester, repository: repository);

    final listFinder = find.byKey(const Key('notes_sheet_bookmark_list'));
    final listTiles = tester.widgetList<ListTile>(
      find.descendant(of: listFinder, matching: find.byType(ListTile)),
    );
    final titles = listTiles.map((t) => (t.title as Text).data).toList();
    expect(titles, ['A', 'C']);
  });

  testWidgets('點選書籤項目觸發 onBookmarkSelected', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(bookId: 'b1', name: '第一章', progression: 0.1),
    );
    Bookmark? selected;
    await _pumpSheet(
      tester,
      repository: repository,
      onBookmarkSelected: (b) => selected = b,
    );

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected?.name, '第一章');
  });
}
