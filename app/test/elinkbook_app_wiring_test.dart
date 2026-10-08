import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/app_dependencies.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/screens/source_dependencies.dart';
import 'package:elinkbook/screens/sources_home_screen.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/theme/app_theme.dart';

import 'support/fake_app_dependencies.dart';
import 'support/fake_book_import_service.dart';
import 'support/fake_book_reader_prefs_repository.dart';
import 'support/fake_bookmarks_repository.dart';
import 'support/fake_cloud_account_repository.dart';
import 'support/fake_cloud_storage_client.dart';
import 'support/fake_custom_fonts_repository.dart';
import 'support/fake_fingerprint_computer.dart';
import 'support/fake_highlights_repository.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_notes_repository.dart';
import 'support/fake_opds_client.dart';
import 'support/fake_reader_prefs_manager.dart';
import 'support/fake_reading_stats_repository.dart';
import 'support/fake_remote_server_repository.dart';
import 'support/fake_remote_thumbnail_cache.dart';
import 'support/fake_tts_provider.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'support/fake_reader_feature_dependencies.dart';
import 'support/fake_sync_dependencies.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';

import 'screens/reader_screen_stats_harness.dart';
import 'support/fake_search_repository.dart';

/// epic-26-architecture-hardening Issue 7 審查修正（review-issue-7.md
/// Important #1）：Issue 7 把 `LibraryScreen` 27 個具名參數收斂為 5 個
/// bundle 後，`main.dart`（`ElinkBookApp.build()`）是唯一把
/// `ElinkBookApp` 自身欄位轉發／包裝進這些 bundle 的組裝根，先前完全沒有
/// 測試涵蓋這條路徑——導致 Task 5 把 `computeFingerprint` 漏轉發的
/// Critical 問題一路通過 `flutter analyze`／`flutter test` 都沒被攔截
/// （見 review-issue-7.md Critical #1）。本檔案鎖定「`ElinkBookApp` 組裝
/// 出的 `LibraryScreen`，每個欄位都與傳入 `ElinkBookApp` 的值同一實例」，
/// 讓未來任何一次搬移/新增 `LibraryScreen` 建構參數的重構都能被自動化
/// 攔截，不必再依賴人工逐行核對 `main.dart`。
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // db 必須在 setUp()（FakeAsync 虛擬時間之外）開啟——sqflite ffi 的
    // openDatabase() 是真實 I/O，若改在 testWidgets 主體內開啟，會落在
    // AutomatedTestWidgetsFlutterBinding 包住測試主體的 FakeAsync zone
    // 內，無法完成、導致整個測試 timeout 卡死（比照
    // library_screen_test.dart 既有慣例：libraryRepository 一律在
    // setUp() 內以 await 開啟，testWidgets 內只重複使用既有連線）。
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('ElinkBookApp 組裝出的 LibraryScreen，每個 bundle 欄位與獨立參數皆與傳入值同一實例', (
    tester,
  ) async {
    final repository = FakeLibraryRepository();
    final importService = FakeBookImportService();
    final prefsManager = FakeReaderPrefsManager();
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final customFontsRepository = FakeCustomFontsRepository();
    final layoutPresetRepository = LayoutPresetRepository(db);
    final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
    final syncAccountRepository = SyncAccountRepository();
    final syncClient = SyncClient(accountRepository: syncAccountRepository);
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
    );
    final cloudAccountRepository = FakeCloudAccountRepository();
    final googleDriveOAuthClient = GoogleDriveOAuthClient(
      accountRepository: cloudAccountRepository,
    );
    final oneDriveOAuthClient = OneDriveOAuthClient(
      accountRepository: cloudAccountRepository,
    );
    final googleDriveStorageClient = FakeCloudStorageClient();
    final oneDriveStorageClient = FakeCloudStorageClient();
    final remoteServerRepository = FakeRemoteServerRepository();
    OpdsClient createOpdsClient() => FakeOpdsClient();
    final computeFingerprint = FakeFingerprintComputer().call;
    final thumbnailCache = FakeRemoteThumbnailCache();
    Future<bool> isMobileDataConnection() async => false;
    final downloadQueueController = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final sources = SourceDependencies(
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
      oneDriveStorageClient: oneDriveStorageClient,
      remoteServerRepository: remoteServerRepository,
      createOpdsClient: createOpdsClient,
      thumbnailCache: thumbnailCache,
      computeFingerprint: computeFingerprint,
      isMobileDataConnection: isMobileDataConnection,
      checkNetworkAvailability: checkNetworkAvailability,
      downloadQueueController: downloadQueueController,
    );
    final ttsProvider = FakeTtsProvider();
    final readingStatsRepository = FakeReadingStatsRepository();
    final ttsAudio = TtsAudioHandlerHolder.degraded();

    await tester.pumpWidget(
      ElinkBookApp(
        dependencies: AppDependencies(
          readerFeatures: fakeReaderFeatureDependencies(
            libraryRepository: repository,
            bookImportService: importService,
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
            customFontsRepository: customFontsRepository,
            layoutPresetRepository: layoutPresetRepository,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
            ttsProvider: ttsProvider,
            ttsAudio: ttsAudio,
            readingStatsRepository: readingStatsRepository,
            syncCheckpointTrigger: syncCheckpointTrigger,
          ),
          sync: fakeSyncDependencies(
            syncAccountRepository: syncAccountRepository,
            syncClient: syncClient,
            syncCheckpointTrigger: syncCheckpointTrigger,
          ),
          sources: sources,
        ),
        initialTheme: AppTheme.dark,
        initialEinkMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final libraryScreen = tester.widget<LibraryScreen>(
      find.byType(LibraryScreen),
    );
    final shell = tester.widget<AdaptiveShellScaffold>(
      find.byType(AdaptiveShellScaffold),
    );

    expect(libraryScreen.dependencies.libraryRepository, same(repository));
    expect(libraryScreen.dependencies.bookImportService, same(importService));
    expect(libraryScreen.dependencies.prefsManager, same(prefsManager));

    expect(
      libraryScreen.dependencies.bookmarksRepository,
      same(bookmarksRepository),
    );
    expect(
      libraryScreen.dependencies.highlightsRepository,
      same(highlightsRepository),
    );
    expect(libraryScreen.dependencies.notesRepository, same(notesRepository));
    expect(
      libraryScreen.dependencies.customFontsRepository,
      same(customFontsRepository),
    );
    expect(
      libraryScreen.dependencies.layoutPresetRepository,
      same(layoutPresetRepository),
    );
    expect(
      libraryScreen.dependencies.bookReaderPrefsRepository,
      same(bookReaderPrefsRepository),
    );
    expect(libraryScreen.dependencies.ttsProvider, same(ttsProvider));
    expect(libraryScreen.dependencies.ttsAudio, same(ttsAudio));
    expect(
      libraryScreen.dependencies.readingStatsRepository,
      same(readingStatsRepository),
    );

    expect(shell.sync.syncAccountRepository, same(syncAccountRepository));
    expect(shell.sync.syncClient, same(syncClient));
    expect(shell.sync.syncCheckpointTrigger, same(syncCheckpointTrigger));

    expect(libraryScreen.sources, same(sources));
    expect(
      tester
          .widget<SourcesHomeScreen>(
            find.byType(SourcesHomeScreen, skipOffstage: false),
          )
          .sources,
      same(sources),
    );
    expect(
      tester
          .widget<SettingsScaffold>(
            find.byType(SettingsScaffold, skipOffstage: false),
          )
          .sources,
      same(sources),
    );

    // computeFingerprint 同時服務雲端匯入、OPDS 下載與 WiFi 傳書，
    // 只有 SourceDependencies 這一個來源（Issue 7 曾漏轉發）。
    expect(libraryScreen.sources.computeFingerprint, same(computeFingerprint));
    expect(
      libraryScreen.sources.downloadQueueController,
      same(downloadQueueController),
    );

    expect(libraryScreen.appearance.currentTheme, AppTheme.dark);
    expect(libraryScreen.appearance.isEinkMode, isTrue);
    expect(libraryScreen.appearance.onThemeChanged, isNotNull);
    expect(libraryScreen.appearance.onEinkModeChanged, isNotNull);
  });

  testWidgets('ElinkBookApp 把 AppDependencies 的三組原樣傳到書架、來源頁與設定頁', (
    tester,
  ) async {
    final deps = fakeAppDependencies();
    await tester.pumpWidget(ElinkBookApp(dependencies: deps));
    await tester.pumpAndSettle();
    final shell = tester.widget<AdaptiveShellScaffold>(
      find.byType(AdaptiveShellScaffold),
    );
    expect(shell.readerFeatures, same(deps.readerFeatures));
    expect(shell.sync, same(deps.sync));
    expect(shell.sources, same(deps.sources));
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).dependencies,
      same(deps.readerFeatures),
    );
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).sources,
      same(deps.sources),
    );
    expect(
      tester
          .widget<SourcesHomeScreen>(
            find.byType(SourcesHomeScreen, skipOffstage: false),
          )
          .sources,
      same(deps.sources),
    );
    expect(
      tester
          .widget<SettingsScaffold>(
            find.byType(SettingsScaffold, skipOffstage: false),
          )
          .sources,
      same(deps.sources),
    );
    expect(
      deps.readerFeatures.syncCheckpointTrigger,
      same(deps.sync.syncCheckpointTrigger),
    );
  });

  testWidgets('主題切換使 ElinkBookApp 重建後，依賴組仍是同一實例（不是 build 內新建）', (tester) async {
    final deps = fakeAppDependencies();

    await tester.pumpWidget(ElinkBookApp(dependencies: deps));
    await tester.pumpAndSettle();

    final settingsBefore = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    settingsBefore.appearance.onThemeChanged(AppTheme.dark);
    await tester.pumpAndSettle();

    final libraryScreen = tester.widget<LibraryScreen>(
      find.byType(LibraryScreen),
    );
    expect(libraryScreen.appearance.currentTheme, AppTheme.dark);
    expect(libraryScreen.dependencies, same(deps.readerFeatures));
    final settingsAfter = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    expect(settingsAfter.readerFeatures, same(deps.readerFeatures));
    expect(settingsAfter.sync, same(deps.sync));
  });

  testWidgets('切換主題後，三個畫面看到同一份新的外觀快照，其餘三組仍是原實例', (tester) async {
    final deps = fakeAppDependencies();

    await tester.pumpWidget(ElinkBookApp(dependencies: deps));
    await tester.pumpAndSettle();

    final before = tester
        .widget<LibraryScreen>(find.byType(LibraryScreen))
        .appearance;

    // 以 theme_test.dart 既有手法點選深色主題圓點，觸發 _ElinkBookAppState.setState。
    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_theme_dot_dark')));
    await tester.pumpAndSettle();

    final library = tester.widget<LibraryScreen>(
      find.byType(LibraryScreen, skipOffstage: false),
    );
    final sourcesHome = tester.widget<SourcesHomeScreen>(
      find.byType(SourcesHomeScreen, skipOffstage: false),
    );
    final settings = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    expect(library.appearance, isNot(same(before)));
    expect(sourcesHome.appearance, same(library.appearance));
    expect(settings.appearance, same(library.appearance));
    expect(library.appearance.currentTheme, AppTheme.dark);
    expect(library.dependencies, same(deps.readerFeatures));
    expect(library.sources, same(deps.sources));
    expect(settings.sync, same(deps.sync));
  });

  testWidgets('開啟 E-Ink 後，書架、來源頁、設定頁都拿到 isEinkMode == true', (tester) async {
    final deps = fakeAppDependencies();

    await tester.pumpWidget(ElinkBookApp(dependencies: deps));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
    await tester.pumpAndSettle();

    final library = tester.widget<LibraryScreen>(
      find.byType(LibraryScreen, skipOffstage: false),
    );
    final sourcesHome = tester.widget<SourcesHomeScreen>(
      find.byType(SourcesHomeScreen, skipOffstage: false),
    );
    final settings = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    expect(library.appearance.isEinkMode, isTrue);
    expect(sourcesHome.appearance.isEinkMode, isTrue);
    expect(settings.appearance.isEinkMode, isTrue);

    // 從來源頁開遠端書庫，isEinkMode 貫穿到底層畫面。
    await tester.tap(find.byKey(const Key('settings_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_remote_library_tile')));
    await tester.pumpAndSettle();

    final remoteList = tester.widget<RemoteServerListScreen>(
      find.byType(RemoteServerListScreen),
    );
    expect(remoteList.isEinkMode, isTrue);
  });

  testWidgets('切換介面語言後，AdaptiveShellScaffold 子畫面 State 保留（書架捲動／搜尋狀態不重置）', (
    tester,
  ) async {
    final deps = fakeAppDependencies();

    await tester.pumpWidget(ElinkBookApp(dependencies: deps));
    await tester.pumpAndSettle();

    final stateBefore = tester.state(find.byType(LibraryScreen));
    final appearanceBefore = tester
        .widget<LibraryScreen>(find.byType(LibraryScreen))
        .appearance;

    // 沿用 elinkbook_app_locale_test.dart 既有切語言手法。
    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_option_en')));
    await tester.pumpAndSettle();

    final library = tester.widget<LibraryScreen>(
      find.byType(LibraryScreen, skipOffstage: false),
    );
    expect(library.appearance.currentLocaleOverride, AppLocale.en);
    expect(library.appearance, isNot(same(appearanceBefore)));
    expect(
      tester.state(find.byType(LibraryScreen, skipOffstage: false)),
      same(stateBefore),
      reason: 'IndexedStack 不重建子畫面：切語言只換外觀快照，不重置書架狀態',
    );
  });
  _openBookWiringTests();
}

// ---------------------------------------------------------------------------
// Issue 14：開書路徑身分守衛的共同起手式。
// ---------------------------------------------------------------------------

const _kWiringBookId = 'wiring-book';

/// 書架上唯一的一本書。檔案用 `test/fixtures/sample.epub`，讓 `ReaderScreen`
/// 走假 WebView 平台（見 [registerReaderStatsTestEnvironment]）正常開啟。
Book _wiringBook() => Book(
  id: _kWiringBookId,
  title: '守衛測試書',
  format: BookFileFormat.epub,
  filePath: 'test/fixtures/sample.epub',
  source: BookSource.local,
  groupName: BookGroup.uncategorized,
  createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);

/// 以完整 `ElinkBookApp` 為起點：容器由 `fakeAppDependencies` 組成，
/// `readerFeatures` 內的 `libraryRepository` 放一本 [_wiringBook]。
/// 只傳 `readerFeatures` 給 `fakeAppDependencies`，所以 `sync` 會沿用同一個
/// `syncCheckpointTrigger`（與 `main()` 的組裝方式一致）。
Future<AppDependencies> _pumpWiringApp(
  WidgetTester tester, {
  FakeSearchRepository? searchRepository,
  bool isEinkMode = true,
}) async {
  // Issue 29 的啟動自動開書預設為 true，會在 pump 後自動推入 ReaderScreen、
  // 把書架藏到路由後方導致 `book_item_*` 找不到；本守衛驗證的是手動開書路徑，
  // 故在此明確關閉（比照 `library_screen_test.dart` 共用 fixture 做法）。
  final deps = fakeAppDependencies(
    readerFeatures: fakeReaderFeatureDependencies(
      libraryRepository: FakeLibraryRepository(initialBooks: [_wiringBook()]),
      searchRepository: searchRepository,
      prefsManager: FakeReaderPrefsManager(
        globalPrefs: const GlobalReaderPrefs.initial().copyWith(
          reading: ReadingDefaults(openLastBookOnLaunch: false),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    ElinkBookApp(dependencies: deps, initialEinkMode: isEinkMode),
  );
  await tester.pumpAndSettle();
  return deps;
}

/// 書架 → 全庫搜尋（P2）：展開書架搜尋框、輸入關鍵字、點「搜尋書本內容」入口。
Future<void> _openLibraryContentSearch(WidgetTester tester) async {
  if (find.byKey(const Key('library_search_field')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('library_search_toggle_button')));
    await tester.pumpAndSettle();
  }
  // 關鍵字「守衛」對應 [_wiringBook] 的書名「守衛測試書」；FakeSearchRepository
  // 不過濾、直接回傳建構時給的結果，所以結果必然包含該書。
  await tester.enterText(find.byKey(const Key('library_search_field')), '守衛');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library_content_search_entry_button')));
  await tester.pumpAndSettle();
}

/// 通到 `ReaderScreen` 的每條路徑終點共用的斷言：整組同一實例、
/// `syncCheckpointTrigger` 與同步組是同一實例、E-Ink 狀態、書本身分。
void _expectReaderWired(
  WidgetTester tester,
  AppDependencies deps, {
  required bool isEinkMode,
}) {
  expect(find.byType(ReaderScreen), findsOneWidget);
  final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
  expect(reader.dependencies, same(deps.readerFeatures));
  expect(
    reader.dependencies.syncCheckpointTrigger,
    same(deps.sync.syncCheckpointTrigger),
  );
  expect(reader.isEinkMode, isEinkMode);
  expect(reader.bookId, _kWiringBookId);
}

/// 換掉整棵樹讓 `ReaderScreen` dispose（取消 30 秒開書逾時計時器）。
Future<void> _disposeWiringApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void _openBookWiringTests() {
  group('Issue 14：開書路徑身分守衛（容器 → 每條開書路徑）', () {
    registerReaderStatsTestEnvironment();

    testWidgets('P1 書架點書 → ReaderScreen：整組依賴、同步 trigger、E-Ink 皆原樣', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(tester);

      await tester.tap(find.byKey(Key('book_item_$_kWiringBookId')));
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });

    testWidgets('P2 書架 → LibrarySearchScreen：整組依賴與 E-Ink 原樣', (tester) async {
      final deps = await _pumpWiringApp(tester);

      await _openLibraryContentSearch(tester);

      expect(find.byType(LibrarySearchScreen), findsOneWidget);
      final search = tester.widget<LibrarySearchScreen>(
        find.byType(LibrarySearchScreen),
      );
      expect(search.dependencies, same(deps.readerFeatures));
      expect(search.isEinkMode, isTrue);
      await _disposeWiringApp(tester);
    });

    testWidgets('切換 E-Ink 後再開書：ReaderScreen 看到新的 E-Ink 值，依賴組仍是容器原實例', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(tester, isEinkMode: false);
      tester
          .widget<LibraryScreen>(find.byType(LibraryScreen))
          .appearance
          .onEinkModeChanged(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('book_item_$_kWiringBookId')));
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });

    testWidgets('P3a 書架 → 全庫搜尋 → 點書名結果 → ReaderScreen：整組依賴原樣', (tester) async {
      final deps = await _pumpWiringApp(
        tester,
        searchRepository: FakeSearchRepository(
          titleAuthorResults: [_wiringBook()],
        ),
      );
      await _openLibraryContentSearch(tester);

      await tester.tap(
        find.byKey(Key('library_search_title_author_result_$_kWiringBookId')),
      );
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });

    testWidgets('P3b 書架 → 全庫搜尋 → 點內容片段 → ReaderScreen：整組依賴原樣且帶跳轉目標', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(
        tester,
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: _wiringBook(),
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有守衛關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
      );
      await _openLibraryContentSearch(tester);

      await tester.tap(
        find.byKey(Key('library_search_content_snippet_${_kWiringBookId}_0')),
      );
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).initialJumpTarget,
        isNotNull,
        reason: '內容片段點擊須帶跳轉目標，書名結果則不帶（P3a）',
      );
      await _disposeWiringApp(tester);
    });
  });
}
