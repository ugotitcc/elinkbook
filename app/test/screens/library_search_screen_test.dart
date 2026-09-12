// app/test/screens/library_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
// ignore: unused_import
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/reader/percent_rect.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';

Book _testBook({
  required String id,
  String title = '測試書',
  String? author,
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

  testWidgets('輸入框有文字時右側顯示清除按鈕，無文字時不顯示', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_screen_clear_button')),
      findsNothing,
      reason: '輸入框尚未輸入任何文字時，不應顯示清除按鈕',
    );

    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      'a',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('library_search_screen_clear_button')),
      findsOneWidget,
    );
  });

  testWidgets('點擊清除按鈕清空輸入框文字與搜尋結果', (tester) async {
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

    await tester.tap(
      find.byKey(const Key('library_search_screen_clear_button')),
    );
    await tester.pump();

    final controllerText = tester
        .widget<TextField>(find.byKey(const Key('library_search_screen_field')))
        .controller!
        .text;
    expect(controllerText, isEmpty);
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('library_search_screen_clear_button')),
      findsNothing,
      reason: '清空後應立即隱藏清除按鈕本身',
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
      '點擊內容匹配片段開書時，帶入依 locator 解析出的 ReaderJumpTarget（epic-10-search Issue 5）',
      (tester) async {
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

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget?.cfi, 'epubcfi(/6/2)');
  });

  testWidgets(
      '內容匹配為 PDF 書籍時，帶入依 JSON locator 解析出的頁碼與座標（epic-10-search Issue 5）',
      (tester) async {
    final book = _testBook(id: 'b1', title: 'PDF 書', format: BookFileFormat.pdf);
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
                  locator:
                      '{"page":2,"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
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

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget?.pdfPageIndex, 2);
    expect(
      readerScreen.initialJumpTarget?.pdfRect,
      const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
    );
  });

  testWidgets('點擊書名/作者匹配結果開書時，不帶 initialJumpTarget（一般開書路徑，零回歸）',
      (tester) async {
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

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget, isNull);
  });

  testWidgets('點擊搜尋結果開書時，收起搜尋輸入框焦點以避免 IME 與開書旋轉交互影響', (tester) async {
    final book = _testBook(id: 'b1', title: '書名');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書名',
        searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(
      find.byKey(const Key('library_search_screen_field')),
    );
    expect(searchField.focusNode?.hasFocus, isTrue);

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    expect(searchField.focusNode?.hasFocus, isFalse);
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

    await tester.tap(find.byKey(
      const Key('library_search_title_author_paging_bar_next_button'),
    ));
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

  testWidgets('AppBar 設定按鈕開啟全文檢索設定選單，顯示兩個開關與重建索引按鈕',
      (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
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

    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const Key('library_search_full_text_search_foliate_switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('設定選單內從關閉切成開啟，先跳出確認對話框，取消則不呼叫 setEnabled',
      (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository: repository,
        ),
      )),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_cancel')),
    );
    await tester.pumpAndSettle();

    expect(repository.setEnabledCalls, isEmpty);
    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('確認後呼叫 setEnabled(true)，重建索引按鈕由停用變為可用', (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository: repository,
        ),
      )),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key(
              'library_search_full_text_search_pdf_rebuild_button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('關閉設定選單時，若目前有查詢字串則重新查詢一次，避免殘留過期結果（審查修正 I-3）',
      (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(),
        ),
      )),
    );
    await tester.pumpAndSettle();
    expect(searchRepository.searchTitleAuthorCalls, ['關鍵字']);

    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
    await tester.pumpAndSettle();

    expect(searchRepository.searchTitleAuthorCalls, ['關鍵字', '關鍵字']);
  });

  testWidgets(
      '雙入口一致性：SettingsScaffold 切換開關後，LibrarySearchScreen 的設定選單重新開啟時反映最新狀態',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeFullTextSearchSettingsRepository();

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        fullTextSearchSettingsRepository: repository,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('settings_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_confirm')),
    );
    await tester.pumpAndSettle();
    expect(await repository.isEnabled(ContentIndexCategory.pdf), isTrue);

    await tester.pumpWidget(wrap(LibrarySearchScreen(
      searchRepository: FakeSearchRepository(),
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
      readerFeatureRepositories: LibraryReaderFeatureRepositories(
        fullTextSearchSettingsRepository: repository,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isTrue,
    );
  });
}
