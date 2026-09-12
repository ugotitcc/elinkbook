// app/test/screens/book_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';

Book _testBook({
  String id = 'b1',
  String title = '測試書',
  String? author = '作者',
  BookFileFormat format = BookFileFormat.epub,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: child,
    );

BookSearchDetailResult _makeResult({
  Book? book,
  int matchCount = 5,
  int totalMatches = 5,
  bool isTruncated = false,
  int startChapter = 1,
}) {
  final b = book ?? _testBook();
  return BookSearchDetailResult(
    book: b,
    matches: [
      for (var i = 0; i < matchCount; i++)
        ContentMatchSnippet(
          snippet: '第${startChapter + i}章含有搜尋關鍵字的文本片段',
          locator: b.format == BookFileFormat.pdf
              ? '{"page":${startChapter + i},"rect":{"left":0.1,"top":0.2,"right":0.3,"bottom":0.4}}'
              : 'epubcfi(/6/${(startChapter + i) * 2})',
          chapterIndex: startChapter + i,
        ),
    ],
    totalMatches: totalMatches,
    isTruncated: isTruncated,
  );
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (_) async => null,
    );
  });

  testWidgets('初始查詢帶入後自動觸發搜尋並顯示結果', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    // 搜尋框帶入初始關鍵字
    final field = tester.widget<TextField>(
      find.byKey(const Key('book_search_screen_field')),
    );
    expect(field.controller!.text, '關鍵字');

    // 結果項目顯示
    expect(find.byKey(const Key('book_search_snippet_0')), findsOneWidget);
  });

  testWidgets('修改搜尋框文字後 300ms debounce 觸發重搜', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    searchRepo.searchContentInBookCalls.clear();

    await tester.enterText(
      find.byKey(const Key('book_search_screen_field')),
      '新關鍵字',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(searchRepo.searchContentInBookCalls, isEmpty,
        reason: '100ms 內不應觸發查詢');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(searchRepo.searchContentInBookCalls, ['新關鍵字']);
  });

  testWidgets('清空輸入框時立即註銷在途請求，避免非同步查詢回傳覆蓋清空狀態（review-plan-issue-7.md I-1）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '初始詞',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    // 輸入新關鍵字後在 debounce 期間清空
    await tester.enterText(
      find.byKey(const Key('book_search_screen_field')),
      '即將被清空',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
      find.byKey(const Key('book_search_screen_field')),
      '',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_search_snippet_0')), findsNothing);
  });

  testWidgets('排序切換按鈕在「依書中順序」與「依相關度排序」間切換並傳遞 sortByBookOrder（review-plan-issue-7.md I-2）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    // 預設顯示「依書中順序」
    expect(find.text('依書中順序'), findsOneWidget);

    // 點擊切換
    await tester.tap(find.byKey(const Key('book_search_sort_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('依相關度排序'), findsOneWidget);
    expect(searchRepo.searchContentInBookSortCalls.last, isFalse,
        reason: '切換為依相關度排序時 sortByBookOrder 應為 false');
  });

  testWidgets('EPUB 格式片段顯示「第 X 章」位置標籤', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(
        matchCount: 1,
        totalMatches: 1,
        startChapter: 5,
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(format: BookFileFormat.epub),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('第 6 章'), findsOneWidget);
  });

  testWidgets('PDF 格式片段顯示「第 X 頁」位置標籤', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(
        book: _testBook(format: BookFileFormat.pdf),
        matchCount: 1,
        totalMatches: 1,
        startChapter: 10,
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(format: BookFileFormat.pdf),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('第 11 頁'), findsOneWidget);
  });

  testWidgets('isTruncated 為 true 時顯示「僅顯示前 N 筆」提示', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(
        matchCount: 3,
        totalMatches: 500,
        isTruncated: true,
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('僅顯示前'), findsOneWidget);
  });

  testWidgets('fromReader=false 時點擊片段推入 ReaderScreen', (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(matchCount: 1, totalMatches: 1),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_search_snippet_0')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('fromReader=true 時點擊片段透過 Navigator.pop 回傳 ReaderJumpTarget（review-plan-issue-7.md I-2）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(matchCount: 1, totalMatches: 1),
    );

    ReaderJumpTarget? poppedTarget;
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => ElevatedButton(
        key: const Key('open_search'),
        onPressed: () async {
          poppedTarget = await Navigator.of(context).push<ReaderJumpTarget>(
            MaterialPageRoute(
              builder: (_) => BookSearchScreen(
                book: _testBook(),
                initialQuery: '關鍵字',
                searchRepository: searchRepo,
                prefsManager: FakeReaderPrefsManager(),
                libraryRepository: FakeLibraryRepository(),
                fromReader: true,
              ),
            ),
          );
        },
        child: const Text('Open'),
      ),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_search')));
    await tester.pumpAndSettle();

    expect(find.byType(BookSearchScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_search_snippet_0')));
    await tester.pumpAndSettle();

    expect(find.byType(BookSearchScreen), findsNothing);
    expect(poppedTarget, isNotNull);
    expect(poppedTarget?.cfi, 'epubcfi(/6/2)');
  });

  testWidgets('E-Ink 模式顯示 PagingBar 離散分頁，點擊換頁更新內容（review-plan-issue-7.md I-2）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(matchCount: 15, totalMatches: 15),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
      isEinkMode: true,
    )));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('book_search_paging_bar')),
      findsOneWidget,
    );
    // 15 筆 / 每頁 10 筆 = 2 頁
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const Key('book_search_snippet_0')), findsOneWidget);
    expect(find.byKey(const Key('book_search_snippet_10')), findsNothing);

    // 點擊下一頁
    await tester.tap(find.byKey(const Key('book_search_paging_bar_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('book_search_snippet_0')), findsNothing);
    expect(find.byKey(const Key('book_search_snippet_10')), findsOneWidget);
  });

  testWidgets('isFullTextSearchAvailable 為 false 時顯示「本裝置不支援全文檢索」提示（review-plan-issue-7.md I-3）',
      (tester) async {
    final searchRepo = FakeSearchRepository();

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
      readerFeatureRepositories: const LibraryReaderFeatureRepositories(
        isFullTextSearchAvailable: false,
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('本裝置不支援全文檢索'), findsOneWidget);
    expect(searchRepo.searchContentInBookCalls, isEmpty);
  });
}
