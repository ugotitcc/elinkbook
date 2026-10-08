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

import 'support/fake_book_import_service.dart';
import 'support/fake_source_dependencies.dart';
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
        sources: sources,
        initialTheme: AppTheme.dark,
        initialEinkMode: true,
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

  testWidgets('ElinkBookApp 把同一個閱讀器組與同步組原樣傳到外殼、書架與設定', (tester) async {
    final trigger = fakeSyncDependencies().syncCheckpointTrigger;
    final readerFeatures = fakeReaderFeatureDependencies(
      syncCheckpointTrigger: trigger,
    );
    final sync = fakeSyncDependencies(syncCheckpointTrigger: trigger);
    final sources = fakeSourceDependencies();

    await tester.pumpWidget(
      ElinkBookApp(
        readerFeatures: readerFeatures,
        sync: sync,
        sources: sources,
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<AdaptiveShellScaffold>(
      find.byType(AdaptiveShellScaffold),
    );
    expect(shell.readerFeatures, same(readerFeatures));
    expect(shell.sync, same(sync));
    expect(shell.sources, same(sources));
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).dependencies,
      same(readerFeatures),
    );
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).sources,
      same(sources),
    );
    expect(
      tester
          .widget<SourcesHomeScreen>(
            find.byType(SourcesHomeScreen, skipOffstage: false),
          )
          .sources,
      same(sources),
    );
    final settings = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    expect(settings.readerFeatures, same(readerFeatures));
    expect(settings.sync, same(sync));
    expect(settings.sources, same(sources));
    // 同一個 syncCheckpointTrigger 實例同時屬於兩個組（ADR 0037 §1）。
    expect(
      readerFeatures.syncCheckpointTrigger,
      same(sync.syncCheckpointTrigger),
    );
  });

  testWidgets('主題切換使 ElinkBookApp 重建後，依賴組仍是同一實例（不是 build 內新建）', (tester) async {
    final readerFeatures = fakeReaderFeatureDependencies();
    final sync = fakeSyncDependencies();

    await tester.pumpWidget(
      ElinkBookApp(
        readerFeatures: readerFeatures,
        sync: sync,
        sources: fakeSourceDependencies(),
      ),
    );
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
    expect(libraryScreen.dependencies, same(readerFeatures));
    final settingsAfter = tester.widget<SettingsScaffold>(
      find.byType(SettingsScaffold, skipOffstage: false),
    );
    expect(settingsAfter.readerFeatures, same(readerFeatures));
    expect(settingsAfter.sync, same(sync));
  });

  testWidgets('切換主題後，三個畫面看到同一份新的外觀快照，其餘三組仍是原實例', (tester) async {
    final rf = fakeReaderFeatureDependencies(
      libraryRepository: FakeLibraryRepository(),
      bookImportService: FakeBookImportService(),
      prefsManager: FakeReaderPrefsManager(),
    );
    final sync = fakeSyncDependencies();
    final sources = fakeSourceDependencies();

    await tester.pumpWidget(
      ElinkBookApp(readerFeatures: rf, sync: sync, sources: sources),
    );
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
    expect(library.dependencies, same(rf));
    expect(library.sources, same(sources));
    expect(settings.sync, same(sync));
  });

  testWidgets('開啟 E-Ink 後，書架、來源頁、設定頁都拿到 isEinkMode == true', (tester) async {
    final rf = fakeReaderFeatureDependencies(
      libraryRepository: FakeLibraryRepository(),
      bookImportService: FakeBookImportService(),
      prefsManager: FakeReaderPrefsManager(),
    );
    final sync = fakeSyncDependencies();
    final sources = fakeSourceDependencies();

    await tester.pumpWidget(
      ElinkBookApp(readerFeatures: rf, sync: sync, sources: sources),
    );
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
    final rf = fakeReaderFeatureDependencies(
      libraryRepository: FakeLibraryRepository(),
      bookImportService: FakeBookImportService(),
      prefsManager: FakeReaderPrefsManager(),
    );
    final sync = fakeSyncDependencies();
    final sources = fakeSourceDependencies();

    await tester.pumpWidget(
      ElinkBookApp(readerFeatures: rf, sync: sync, sources: sources),
    );
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
}
