// app/test/screens/library_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';

Book _testBook({required String id, String title = '測試書', String? author}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

void main() {
  setUpAll(() {
    // ReaderScreen.dispose() 會無條件呼叫 elinkbook/fullscreen
    // setEnabled(false)（比照 library_screen_test.dart 既有慣例）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (_) async => null,
    );
  });

  // 【審查修正 I-1】原版 `MaterialApp(home: child)` 未套用
  // `resolveThemeData()`，`ElinkTokens` 主題擴充不會被註冊，
  // `BookCover.build()` 對 `Theme.of(context).extension<ElinkTokens>()!`
  // 強制解包會直接拋出 `Null check operator used on a null value`——任何
  // 渲染出真實書籍項目（含 `BookCover`）的測試都會炸掉。比照
  // `library_screen_test.dart` 既有標準寫法補上主題。
  Widget wrap(Widget child) => MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: child,
      );

  testWidgets('輸入文字後 300ms 內未再變動才觸發搜尋查詢（防手震延遲）', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      'a',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      'ab',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      searchRepository.searchTitleAuthorCalls,
      isEmpty,
      reason: '連續輸入期間不應觸發查詢',
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(searchRepository.searchTitleAuthorCalls, ['ab']);
  });

  testWidgets('清空輸入框時立即清空結果，不等待防手震延遲', (tester) async {
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [_testBook(id: 'b1', title: '書一')],
    );
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      '',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsNothing,
    );
  });

  testWidgets('結果分「書名/作者匹配」與「內容匹配」兩區呈現', (tester) async {
    final matchedBook = _testBook(id: 'b1', title: '書一');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [matchedBook],
      contentResults: [
        BookContentMatches(
          book: matchedBook,
          matches: const [
            ContentMatchSnippet(
              snippet: '含有關鍵字的句子',
              locator: 'epubcfi(/6/2)',
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('書名/作者匹配'), findsOneWidget);
    expect(find.text('內容匹配'), findsOneWidget);
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('library_search_content_group_b1')),
      findsOneWidget,
    );
    expect(find.text('含有關鍵字的句子'), findsOneWidget);
  });

  testWidgets('兩個開關皆關閉時，內容匹配區顯示通用引導卡片', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_content_guidance_card')),
      findsOneWidget,
    );
    expect(find.text('尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）'),
        findsOneWidget);
  });

  testWidgets('只開 PDF 時，顯示「PDF 已啟用/其他格式尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「PDF」全文檢索，其他格式尚未啟用'), findsOneWidget);
  });

  testWidgets('只開其他格式時，顯示「其他格式已啟用/PDF 尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「其他格式」全文檢索，PDF 內容尚未啟用'), findsOneWidget);
  });

  testWidgets('兩者皆開啟且有內容匹配結果時，顯示真實結果而非引導卡片', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_content_guidance_card')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('library_search_content_group_b1')),
      findsOneWidget,
    );
  });

  testWidgets('本裝置不支援全文檢索時，固定顯示不支援提示，不呼叫 searchContent', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: const LibraryReaderFeatureRepositories(
          isFullTextSearchAvailable: false,
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('本裝置不支援全文檢索'), findsOneWidget);
    expect(searchRepository.searchContentCalls, isEmpty);
  });

  testWidgets('點擊書名/作者匹配結果會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('點擊內容匹配片段會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_content_snippet_b1_0')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets(
      'E-Ink 模式下，結果超過每頁固定筆數時顯示離散分頁 PagingBar（審查修正 I-5）',
      (tester) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書',
        searchRepository: FakeSearchRepository(titleAuthorResults: books),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: true,
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_title_author_paging_bar')),
      findsOneWidget,
    );
    final pagingBar = tester.widget<PagingBar>(
      find.byKey(const Key('library_search_title_author_paging_bar')),
    );
    expect(pagingBar.currentPage, 0);
    expect(pagingBar.pageCount, 2);
    expect(
      find.byKey(const Key('library_search_title_author_result_b4')),
      findsOneWidget,
      reason: '每頁固定 5 筆，第 1 頁應顯示 b0-b4',
    );
    expect(
      find.byKey(const Key('library_search_title_author_result_b5')),
      findsNothing,
      reason: '第 6 筆 (b5) 應該在第 2 頁，第 1 頁不應顯示',
    );

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    final pagingBarAfterNext = tester.widget<PagingBar>(
      find.byKey(const Key('library_search_title_author_paging_bar')),
    );
    expect(pagingBarAfterNext.currentPage, 1);
    expect(
      find.byKey(const Key('library_search_title_author_result_b5')),
      findsOneWidget,
      reason: '換頁後第 2 頁應顯示 b5-b6',
    );
  });

  testWidgets('非 E-Ink 模式（預設）結果超過分頁筆數時，不顯示 PagingBar，維持連續捲動',
      (tester) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書',
        searchRepository: FakeSearchRepository(titleAuthorResults: books),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_title_author_paging_bar')),
      findsNothing,
    );
  });
}
