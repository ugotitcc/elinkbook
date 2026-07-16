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

  testWidgets('尚未有書籤時，toggle 按鈕顯示「加入此頁書籤」', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('點擊 toggle 按鈕後新增書籤，清單即時反映', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsOneWidget);
    expect(find.text('已加入此頁書籤'), findsOneWidget);
  });

  testWidgets('已有書籤時再次點擊 toggle 按鈕，移除該筆書籤', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(bookId: 'b1', name: '第 5 頁', pdfPageIndex: 4),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('已加入此頁書籤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsNothing);
    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('EPUB 情境下 toggle 依 epubLocatorJson 精確比對', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '別處',
      epubLocatorJson: '{"href":"/other.xhtml"}',
    ));
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(
        epubLocatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.1,
      ),
    );

    expect(
      find.text('加入此頁書籤'),
      findsOneWidget,
      reason: '不同 locatorJson 不應視為同一位置',
    );
  });

  testWidgets('重新命名書籤後清單顯示新名稱', (tester) async {
    final repository = FakeBookmarksRepository();
    final id = await repository.insert(
      const Bookmark(bookId: 'b1', name: '舊名稱', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_rename_$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_sheet_rename_field')),
      '新名稱',
    );
    await tester.tap(find.byKey(const Key('notes_sheet_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱'), findsOneWidget);
    expect(find.text('舊名稱'), findsNothing);
  });

  testWidgets('單筆刪除書籤後清單即時消失，不需確認', (tester) async {
    final repository = FakeBookmarksRepository();
    final id = await repository.insert(
      const Bookmark(bookId: 'b1', name: '待刪除', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_delete_$id')));
    await tester.pump();

    expect(find.text('待刪除'), findsNothing);
  });

  testWidgets('批次刪除按鈕在無書籤時停用', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('批次刪除顯示確認對話框，取消不刪除', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await _pumpSheet(tester, repository: repository);

    await tester
        .tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 2 筆'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('批次刪除確認後清單清空', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await _pumpSheet(tester, repository: repository);

    await tester
        .tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks_confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
  });
}
