// app/test/screens/library_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_appearance_dependencies.dart';
import '../support/fake_source_dependencies.dart';
// ignore: unused_import
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_sync_dependencies.dart';

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
  Widget wrap(Widget child, {Locale locale = const Locale('zh', 'TW')}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: child,
      );

  testWidgets('輸入文字後 300ms 內未再變動才觸發搜尋查詢（防手震延遲）', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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
      wrap(
        LibrarySearchScreen(
          initialQuery: '書一',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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
      wrap(
        LibrarySearchScreen(
          initialQuery: '書一',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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
            ContentMatchSnippet(snippet: '含有關鍵字的句子', locator: 'epubcfi(/6/2)'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '書一',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(
                  initialEnabled: {
                    ContentIndexCategory.pdf: true,
                    ContentIndexCategory.foliate: true,
                  },
                ),
          ),
        ),
      ),
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

  testWidgets('全域簡繁轉換為繁體時，書名/作者匹配區、內容匹配區書籍標頭與摘要片段皆依轉換模式呈現'
      '（epic-42-text-conversion Issue 4）', (tester) async {
    final matchedBook = _testBook(id: 'b1', title: '国电脑维修', author: '电脑作者');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [matchedBook],
      contentResults: [
        BookContentMatches(
          book: matchedBook,
          matches: const [
            ContentMatchSnippet(
              snippet: '含有电脑维修关键字的句子',
              locator: 'epubcfi(/6/2)',
            ),
          ],
        ),
      ],
    );
    final prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '国电脑',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: prefsManager,
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(
                  initialEnabled: {
                    ContentIndexCategory.pdf: true,
                    ContentIndexCategory.foliate: true,
                  },
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 審查修正 C-1：BookCover 無封面圖時會退回 CoverPlaceholder 渲染書名
    // 縮略文字（本畫面兩處 BookCover 皆為 40×56 尺寸，已達 CoverPlaceholder
    // 顯示文字的門檻——見 app/lib/library/widgets/book_cover.dart
    // _titleRowMinHeight/_titleRowMinWidth），與 ListTile.title／書籍標頭
    // 各顯示一次已轉換文字，兩處合計 2 個 widget；比照
    // library_screen_test.dart 既有測試慣例。
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('國電腦維修'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與 ListTile.title 各顯示一次',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('国电脑维修'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('電腦作者'),
      ),
      findsOneWidget,
      reason: '作者僅顯示於列表副標題，CoverPlaceholder 不含作者欄位',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_content_group_b1')),
        matching: find.text('國電腦維修'),
      ),
      findsNWidgets(2),
      reason: '內容匹配卡片的 CoverPlaceholder 縮略與書籍標頭各顯示一次，皆需要轉換',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_content_group_b1')),
        matching: find.text('国电脑维修'),
      ),
      findsNothing,
    );
    expect(find.text('含有電腦維修關鍵字的句子'), findsOneWidget);
    expect(find.text('含有电脑维修关键字的句子'), findsNothing);
  });

  testWidgets('兩個開關皆關閉時，內容匹配區顯示通用引導卡片', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_content_guidance_card')),
      findsOneWidget,
    );
    expect(find.text('尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）'), findsOneWidget);
  });

  testWidgets('只開 PDF 時，顯示「PDF 已啟用/其他格式尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(
                  initialEnabled: {ContentIndexCategory.pdf: true},
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「PDF」全文檢索，其他格式尚未啟用'), findsOneWidget);
  });

  testWidgets('只開其他格式時，顯示「其他格式已啟用/PDF 尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(
                  initialEnabled: {ContentIndexCategory.foliate: true},
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「其他格式」全文檢索，PDF 內容尚未啟用'), findsOneWidget);
  });

  testWidgets('兩者皆開啟且有內容匹配結果時，顯示真實結果而非引導卡片', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
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
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(
                  initialEnabled: {
                    ContentIndexCategory.pdf: true,
                    ContentIndexCategory.foliate: true,
                  },
                ),
          ),
        ),
      ),
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
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            isFullTextSearchAvailable: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本裝置不支援全文檢索'), findsOneWidget);
    expect(searchRepository.searchContentCalls, isEmpty);
  });

  testWidgets('點擊書名/作者匹配結果會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '書一',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('點選書籍進入閱讀器時，ReaderScreen 拿到的是 LibrarySearchScreen 的同一個依賴組', (
    tester,
  ) async {
    final book = _testBook(id: 'b1', title: '書一');
    final deps = fakeReaderFeatureDependencies(
      searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
    );
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(initialQuery: '書一', dependencies: deps)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.dependencies, same(deps));
  });

  testWidgets('點擊內容匹配片段會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
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
          ),
        ),
      ),
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
        wrap(
          LibrarySearchScreen(
            initialQuery: '關鍵字',
            dependencies: fakeReaderFeatureDependencies(
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('library_search_content_snippet_b1_0')),
      );
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(readerScreen.initialJumpTarget?.cfi, 'epubcfi(/6/2)');
    },
  );

  testWidgets(
    '點擊搜尋結果開書時，ReaderScreen 收到的 searchRepository／isFullTextSearchAvailable '
    '正確貫穿（epic-10-search Issue 8）',
    (tester) async {
      final book = _testBook(id: 'b1', title: '書一');

      await tester.pumpWidget(
        wrap(
          LibrarySearchScreen(
            initialQuery: '關鍵字',
            dependencies: fakeReaderFeatureDependencies(
              searchRepository: FakeSearchRepository(
                titleAuthorResults: [book],
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
              isFullTextSearchAvailable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // isFullTextSearchAvailable: false 時 contentResults 會被清空為空清單，
      // 內容匹配片段不存在，改為點擊書名/作者匹配結果（永遠可用）驗證貫穿
      await tester.tap(
        find.byKey(const Key('library_search_title_author_result_b1')),
      );
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.dependencies.searchRepository,
        same(
          tester
              .widget<LibrarySearchScreen>(
                find.byType(LibrarySearchScreen, skipOffstage: false),
              )
              .dependencies
              .searchRepository,
        ),
      );
      expect(readerScreen.dependencies.isFullTextSearchAvailable, isFalse);
    },
  );

  testWidgets(
    '內容匹配為 PDF 書籍時，帶入依 JSON locator 解析出的頁碼與座標（epic-10-search Issue 5）',
    (tester) async {
      final book = _testBook(
        id: 'b1',
        title: 'PDF 書',
        format: BookFileFormat.pdf,
      );
      await tester.pumpWidget(
        wrap(
          LibrarySearchScreen(
            initialQuery: '關鍵字',
            dependencies: fakeReaderFeatureDependencies(
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('library_search_content_snippet_b1_0')),
      );
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(readerScreen.initialJumpTarget?.pdfPageIndex, 2);
      expect(
        readerScreen.initialJumpTarget?.pdfRect,
        const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
      );
    },
  );

  testWidgets('點擊書名/作者匹配結果開書時，不帶 initialJumpTarget（一般開書路徑，零回歸）', (
    tester,
  ) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '書一',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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
      wrap(
        LibrarySearchScreen(
          initialQuery: '書名',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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

  testWidgets('E-Ink 模式下，結果超過每頁固定筆數時顯示離散分頁 PagingBar（審查修正 I-5）', (
    tester,
  ) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '書',
          isEinkMode: true,
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(titleAuthorResults: books),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
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

    await tester.tap(
      find.byKey(
        const Key('library_search_title_author_paging_bar_next_button'),
      ),
    );
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

  testWidgets('非 E-Ink 模式（預設）結果超過分頁筆數時，不顯示 PagingBar，維持連續捲動', (tester) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '書',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(titleAuthorResults: books),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_title_author_paging_bar')),
      findsNothing,
    );
  });

  testWidgets('AppBar 設定按鈕開啟全文檢索設定選單，顯示兩個開關與重建索引按鈕', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
          ),
        ),
      ),
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
      find.byKey(const Key('library_search_full_text_search_foliate_switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('library_search_full_text_search_pdf_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('設定選單內從關閉切成開啟，先跳出確認對話框，取消則不呼叫 setEnabled', (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      ),
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
          .widget<Switch>(
            find.byKey(const Key('library_search_full_text_search_pdf_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('確認後呼叫 setEnabled(true)，重建索引按鈕由停用變為可用', (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      ),
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
          .widget<IconButton>(
            find.byKey(
              const Key('library_search_full_text_search_pdf_rebuild_button'),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('關閉設定選單時，若目前有查詢字串則重新查詢一次，避免殘留過期結果（審查修正 I-3）', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '關鍵字',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
          ),
        ),
      ),
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

      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          appearance: fakeAppearanceDependencies(),
          sources: fakeSourceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
          sync: fakeSyncDependencies(),
        ),
      );
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

      await tester.pumpWidget(
        wrap(
          LibrarySearchScreen(
            dependencies: fakeReaderFeatureDependencies(
              searchRepository: FakeSearchRepository(),
              prefsManager: FakeReaderPrefsManager(),
              libraryRepository: FakeLibraryRepository(),
              fullTextSearchSettingsRepository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_search_screen_settings_button')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
              find.byKey(
                const Key('library_search_full_text_search_pdf_switch'),
              ),
            )
            .value,
        isTrue,
      );
    },
  );

  testWidgets('內容匹配卡片：totalMatches > 3 時顯示「查看全部」按鈕，<= 3 時不顯示', (tester) async {
    final book5Hits = _testBook(id: 'b1', title: '五筆命中');
    final book2Hits = _testBook(id: 'b2', title: '兩筆命中');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: const [],
      contentResults: [
        BookContentMatches(
          book: book5Hits,
          matches: [
            for (var i = 0; i < 3; i++)
              ContentMatchSnippet(snippet: '片段$i', locator: 'epubcfi(/6/$i)'),
          ],
          totalMatches: 5,
        ),
        BookContentMatches(
          book: book2Hits,
          matches: [
            for (var i = 0; i < 2; i++)
              ContentMatchSnippet(snippet: '片段$i', locator: 'epubcfi(/6/$i)'),
          ],
          totalMatches: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '測試',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            isFullTextSearchAvailable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // b1 有 5 筆命中但只顯示 3 筆，應顯示「查看全部」按鈕
    expect(
      find.byKey(const Key('library_search_drill_down_b1')),
      findsOneWidget,
    );
    // b2 只有 2 筆命中，全數顯示，不需要「查看全部」按鈕
    expect(find.byKey(const Key('library_search_drill_down_b2')), findsNothing);
  });

  testWidgets('點擊「查看全部」按鈕推入 BookSearchScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '測試書');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: const [],
      contentResults: [
        BookContentMatches(
          book: book,
          matches: [
            for (var i = 0; i < 3; i++)
              ContentMatchSnippet(snippet: '片段$i', locator: 'epubcfi(/6/$i)'),
          ],
          totalMatches: 10,
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: '測試',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: searchRepository,
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
            isFullTextSearchAvailable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_search_drill_down_b1')));
    await tester.pumpAndSettle();

    // BookSearchScreen 被推入導覽堆疊
    expect(find.byType(BookSearchScreen), findsOneWidget);
  });

  testWidgets('英文介面下 AppBar 標題、搜尋提示、分區標題正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          initialQuery: 'fantasy',
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(
              titleAuthorResults: [_testBook(id: 'b1', title: 'Fantasy Book')],
            ),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search Book Content'), findsOneWidget);
    expect(find.text('Title/Author Matches'), findsOneWidget);
    expect(find.text('Content Matches'), findsOneWidget);
  });

  testWidgets('簡體中文介面下全文檢索設定面板文字正確以簡體渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          dependencies: fakeReaderFeatureDependencies(
            searchRepository: FakeSearchRepository(),
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
        locale: const Locale('zh', 'CN'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('PDF 全文检索'), findsOneWidget);
    expect(find.text('其他格式全文检索'), findsOneWidget);
  });
}
