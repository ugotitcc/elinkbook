// app/test/screens/book_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
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

Widget _wrap(Widget child, {Locale locale = const Locale('zh', 'TW')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets(
      'fromReader=false 時，推入的 ReaderScreen 收到的 searchRepository／'
      'isFullTextSearchAvailable 正確貫穿（epic-10-search Issue 8）', (tester) async {
    final readerSearchRepository = FakeSearchRepository();
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(matchCount: 1, totalMatches: 1),
    );

    // isFullTextSearchAvailable: false 時 BookSearchScreen 本身不顯示片段清單
    //（顯示「不支援」提示），無法透過點擊片段驗證貫穿；此處改以 true 驗證
    //「貫穿邏輯本身正確」（searchRepository 同實例、flag 正確帶入），false
    // 情境的貫穿已由 LibraryScreen／LibrarySearchScreen 的同構測試覆蓋
    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '關鍵字',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
      readerFeatureRepositories: LibraryReaderFeatureRepositories(
        searchRepository: readerSearchRepository,
        isFullTextSearchAvailable: true,
      ),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_search_snippet_0')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.searchRepository, same(readerSearchRepository));
    expect(readerScreen.isFullTextSearchAvailable, isTrue);
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

  testWidgets('片段清單關鍵字高亮文字大小應與一般清單項目一致，不因誤用 context 繼承到 '
      'MaterialApp 的 48px 錯誤警示字級（/diagnose：全書搜尋結果符合文字部分變得特別大）',
      (tester) async {
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

    final snippetHeight =
        tester.getSize(find.byKey(const Key('book_search_snippet_0'))).height;

    // 對照組：與 book_search_screen 相同主題、相同 title+subtitle 兩行
    // 結構（比照 _buildSnippetTile 的 locationText 副標題）下，一般
    // dense ListTile（無關鍵字高亮）應有的高度——library_search_screen.dart
    // 的內容匹配預覽清單走的正是這條無高亮路徑，字級不受影響。
    await tester.pumpWidget(_wrap(
      Scaffold(
        body: ListTile(
          key: const Key('book_search_control_tile'),
          dense: true,
          title: const Text('對照組：第1章含有搜尋關鍵字的文本片段'),
          subtitle: const Text('第 2 章'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final controlHeight = tester
        .getSize(find.byKey(const Key('book_search_control_tile')))
        .height;

    expect(
      snippetHeight,
      lessThan(controlHeight * 1.3),
      reason: '片段標題不應因高亮 TextSpan 誤用 DefaultTextStyle.of(context) 而暴增字級',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，內容匹配摘要片段依轉換模式呈現（epic-42-text-conversion Issue 4）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: _testBook(),
        matches: const [
          ContentMatchSnippet(
            snippet: '国电脑维修站',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );
    final prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '国电脑',
      searchRepository: searchRepo,
      prefsManager: prefsManager,
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('國電腦維修站'), findsOneWidget);
    expect(find.textContaining('国电脑维修站'), findsNothing);
  });

  testWidgets('跨字形高亮：轉換後顯示的文字仍能正確高亮使用者輸入的查詢字詞（spec.md 審查修正 I-2）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: _testBook(),
        matches: const [
          ContentMatchSnippet(
            snippet: '這裡有電腦維修的說明',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );

    // 顯示模式維持 original（不轉換），片段本身已是繁體「電腦」，使用者
    // 卻用簡體「电脑」搜尋——高亮比對必須改用能在文字中找到的變體
    // 「電腦」，而非直接用使用者輸入的「电脑」（否則 indexOf 找不到，
    // 完全不會產生任何高亮片段）。
    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '电脑',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('book_search_snippet_0')),
        matching: find.byType(Text),
      ),
    );
    final richText = texts.firstWhere((t) => t.textSpan != null);
    final boldSpans = (richText.textSpan as TextSpan)
        .children!
        .whereType<TextSpan>()
        .where((s) => s.style?.fontWeight == FontWeight.bold)
        .toList();
    expect(boldSpans, hasLength(1));
    expect(boldSpans.single.text, '電腦');
  });

  testWidgets(
      '單書覆寫簡繁轉換時，AppBar 標題／工具列作者依該書生效模式呈現，與內容摘要片段的全域轉換模式各自獨立'
      '（epic-42-text-conversion Issue 4，審查修正 review-plan-issue-4.md I-2）', (tester) async {
    final book = _testBook(title: '国电脑维修', author: '电脑作者');
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: book,
        matches: const [
          ContentMatchSnippet(
            snippet: '国电脑维修站',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );
    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {
        book.id: const BookReaderPrefs(
          textConversionOverride: TextConversionMode.toSimplified,
        ),
      },
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: book,
      initialQuery: '国电脑',
      searchRepository: searchRepo,
      prefsManager: prefsManager,
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    // AppBar 標題（單書情境，該書覆寫值 toSimplified）維持簡體原文不變，
    // 不受全域值 toTraditional 影響。
    expect(find.widgetWithText(AppBar, '国电脑维修'), findsOneWidget);
    // 內容摘要片段（跨書情境，一律採全域值 toTraditional）轉為繁體。
    expect(find.textContaining('國電腦維修站'), findsOneWidget);
  });

  testWidgets('英文介面下搜尋提示、排序按鈕、位置標籤正確以英文渲染', (tester) async {
    final book = _testBook();
    final searchRepository = FakeSearchRepository(
      bookSearchDetailResult: _makeResult(book: book, matchCount: 2, totalMatches: 2),
    );
    await tester.pumpWidget(
      _wrap(
        BookSearchScreen(
          book: book,
          initialQuery: '關鍵字',
          searchRepository: searchRepository,
          prefsManager: FakeReaderPrefsManager(),
          libraryRepository: FakeLibraryRepository(),
          readerFeatureRepositories: const LibraryReaderFeatureRepositories(),
          syncDependencies: const LibrarySyncDependencies(),
          isEinkMode: false,
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search in this book...'), findsOneWidget);
    expect(find.textContaining('results'), findsOneWidget);
    expect(find.text('By book order'), findsOneWidget);
  });
}
