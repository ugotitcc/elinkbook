import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:pdfrx/pdfrx.dart';

import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/onedrive_storage_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'downloads/download_queue_controller.dart';
import 'library/book_content_fingerprint.dart';
import 'library/book_import_service_impl.dart';
import 'library/sqlite_library_repository.dart';
import 'licenses/third_party_licenses.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/bookmarks_repository.dart';
import 'reader/custom_fonts_repository.dart';
import 'reader/downloadable_font_store.dart';
import 'reader/highlights_repository.dart';
import 'reader/layout_preset_repository.dart';
import 'reader/notes_repository.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'reader/reading_position_repository.dart';
import 'reader/system_tts_provider.dart';
import 'reader/tts_audio_focus_source.dart';
import 'reader/tts_audio_handler.dart';
import 'reader/tts_audio_handler_startup.dart';
import 'reader/webview_font_support.dart';
import 'remote/opds_http_client.dart';
import 'wifi_transfer/network_availability.dart';
import 'screens/source_dependencies.dart';
import 'remote/remote_thumbnail_cache.dart';
import 'remote/sqlite_remote_server_repository.dart';
import 'screens/adaptive_shell_scaffold.dart';
import 'screens/appearance_dependencies.dart';
import 'screens/cloud_duplicate_confirm_dialog.dart';
import 'screens/reader_feature_dependencies.dart';
import 'screens/reading_position_conflict_dialog.dart';
import 'screens/sync_dependencies.dart';
import 'sync/sync_account_repository.dart';
import 'sync/sync_checkpoint_trigger.dart';
import 'sync/sync_client.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_metadata_repository.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_data.dart';
import 'reader/reader_activity_tracker.dart';
import 'search/content_indexing_scheduler.dart';
import 'search/foliate_content_indexer.dart';
import 'search/full_text_search_settings_repository.dart';
import 'search/pdf_content_indexer.dart';
import 'search/search_repository.dart';
import 'stats/sqlite_reading_stats_repository.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_locale_preferences.dart';
import 'l10n/app_localizations.dart';
import 'l10n/startup_localizations.dart';
import 'theme/app_theme_preferences.dart';

/// [LibraryScreen.isMobileDataConnection] 生產環境實作
/// （epic-30-calibre-remote-library Issue 4）：`connectivity_plus` 6.x
/// 起 `checkConnectivity()` 回傳 `List<ConnectivityResult>`（支援同時
/// 存在多種連線，例如 VPN 疊加 Wi-Fi），只要清單內含
/// [ConnectivityResult.mobile] 即視為「目前為行動數據連線」，即使同時
/// 也有 Wi-Fi——寧可誤判為需要提示，也不要漏掉真正的行動數據情境。
Future<bool> _isMobileDataConnection() async {
  final results = await Connectivity().checkConnectivity();
  return results.contains(ConnectivityResult.mobile);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // epic-55：登錄非 Dart 套件元件（foliate-js 等）的授權，授權頁才會列出。
  registerThirdPartyLicenses();
  // epic-49 Issue 7：讀 WebView 版本需要初始化 WebView（首次約數十～數百毫秒），
  // 先起跑、和下方資料庫等初始化並行，建構字型 store 時才 await（程式審查 M-2）。
  // Issue 8 真機發現：剛安裝完第一次開時可能逾時，讀不到就用上次記住的版本。
  final webViewMajorVersionFuture = readWebViewMajorVersionWithCache();
  // epic-40-bundled-sqlite（ADR 0028）：改用 sqlite3 Native Assets 建置
  // 掛鉤自帶編譯、保證含 FTS5 的 sqlite3，取代依賴 Android 系統內建
  // SQLite（部分裝置系統版本缺 FTS5 模組，見 epic-10-search Issue 6）。
  // 必須在任何 openDatabase() 呼叫（下方 SqliteLibraryRepository.open()）
  // 之前完成。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // pdfrx（PDFium FFI）初始化，epic-24-pdf-engine-rebuild：Flutter App
  // 執行期一律呼叫 pdfrxFlutterInitialize()（而非 pdfrxInitialize()，後者
  // 用於純 Dart、無 Flutter 環境），須在任何 PDF 開書呼叫之前完成。
  await pdfrxFlutterInitialize();

  final themePreferences = AppThemePreferences();
  final initialTheme = await themePreferences.loadTheme();
  final initialEinkMode = await themePreferences.loadEinkMode();

  final localePreferences = AppLocalePreferences();
  final initialLocaleOverride = await localePreferences.loadLocaleOverride();

  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  // epic-49：內建字型改為可下載字型，存在 App 支援目錄（非使用者可見、清除快取不會被刪）。
  // prepare() 建立存放目錄並清掉上次被系統終止時殘留的 .part 暫存檔；
  // 失敗只影響字型下載功能，不能擋住 App 啟動。
  // epic-49 Issue 7：Chromium 106 以前的系統 WebView 拒絕超過 30MB 的網頁字型，
  // store 依版本只公開載得動的字型。讀不到版本時（最多等 3 秒）改用上次記住的值；
  // 從沒讀到過才是 null，視同支援。
  final webViewMajorVersion = await webViewMajorVersionFuture;
  final downloadableFontStore = DownloadableFontStore(
    httpClient: http.Client(),
    directory: Directory(
      p.join((await getApplicationSupportDirectory()).path, 'downloaded-fonts'),
    ),
    webViewMajorVersion: webViewMajorVersion,
  );
  try {
    await downloadableFontStore.prepare();
  } catch (e) {
    debugPrint('Failed to prepare downloaded fonts directory: $e');
  }
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-10-search Issue 1：背景全文檢索索引引擎。本工單只負責讓引擎
  // 能運作，「啟用全文檢索」開關與批次回填既有書庫是 Issue 3 的範圍——
  // 目前 content_index_status 裡不會有任何 pending 列，排程器啟動後
  // 純粹閒置等待，直到 Issue 3 落地才會有實際工作可做。
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
  // epic-10-search Issue 3：「啟用全文檢索」設定模型。requestProcessing
  // 以 callback 注入（而非直接持有整個 contentIndexingScheduler），見
  // plans/plan-issue-3.md Global Constraints。
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: contentIndexingScheduler.requestProcessing,
      );
  // epic-10-search Issue 4：全庫搜尋資料存取層，直接對同一個 Database
  // 連線下 SQL（比照 fullTextSearchSettingsRepository 既有慣例）。
  final searchRepository = SqliteSearchRepository(
    database: repository.database,
  );
  // epic-9-stats Issue 4：每日閱讀統計，同一個 Database 連線（不設外鍵，
  // 見 Issue 2）；經 ReaderFeatureDependencies 貫穿所有開書路徑。
  final readingStatsRepository = SqliteReadingStatsRepository(
    database: repository.database,
  );
  // epic-10-search Issue 2：新書匯入（含 CBZ 標記 unsupported）需要
  // fullTextSearchSettingsRepository（見 plans/plan-issue-2.md），因此
  // importService 的建構挪到這裡（在它之後），不再是 repository 開啟後
  // 立刻建構。
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
    fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
  );
  // epic-34-tts-readalong Issue 9：SystemTtsProvider 預設建構子內部會自行
  // 建立 FlutterTts()，App 層級不需要另外管理其生命週期或提供假物件。
  final ttsProvider = SystemTtsProvider();
  // epic-34-tts-readalong Issue 7：AudioSession 設定一次即為 App 全程式
  // 共用（audio_session 套件內部本身即單例，見該套件 AudioSession.instance
  // 文件），朗讀內容一律視為 speech（語音），並要求「降低音量」型的暫時
  // 失焦（AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK）也一律當成需要暫停處理
  // （androidWillPauseWhenDucked: true）——降低音量的人聲朗讀無法辨識，
  // 與音樂/Podcast 那種可以被降低音量、繼續播放的內容性質不同。
  final ttsAudioSession = await AudioSession.instance;
  await ttsAudioSession.configure(
    const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ),
  );
  final ttsAudioFocusSource = AudioSessionFocusSource(ttsAudioSession);
  // AudioService.init() 全程式生命週期只能呼叫一次（見
  // plans/plan-issue-7.md Global Constraints），失敗後也不可重試
  // （見 initTtsAudioHandlerSafely 說明），建構出的單一 handler
  // 由 ReaderScreen 於每次開書時呼叫 attachController()／
  // detachController() 綁定/解綁目前的 TtsController。
  // 通知頻道名稱（顯示於系統的通知設定）：此時尚無 BuildContext，改用啟動階段解析的
  // AppLocalizations（使用者覆寫語言優先，否則跟隨裝置語言）。頻道只在此處建立一次，
  // 語言以啟動當下為準（epic-45-interface-i18n Issue 10）。
  final startupL10n = resolveStartupLocalizations(
    localeOverride: initialLocaleOverride,
    deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
  );
  // epic-61 Issue 2（F1）：AudioService.init 在 service 綁定逾時時約 10 秒
  // 才丟例外，不可再阻塞啟動。同步取得 pending 狀態的 holder 後直接往下走、
  // 先 runApp；init 在背景跑，完成後 holder 變成 ready 或 failed 並通知，
  // ReaderScreen 監聽 holder 做晚到注入（handler 補 attachController、降級
  // 補提示一次）。AudioService.init 全程式只呼叫一次、失敗後不可重試的限制
  // 不變（見 startTtsAudioHandlerInBackground 說明）。
  final ttsAudio = startTtsAudioHandlerInBackground(
    () => AudioService.init(
      builder: () => TtsAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'cc.ugotit.elinkbook.tts_channel',
        androidNotificationChannelName: startupL10n.ttsNotificationChannelName,
        // Android 12 起背景重啟前景服務有限制（見 audio_service 官方
        // README「Android setup」段落說明），保持 false（暫停時服務維持
        // 前景狀態，不釋放通知），避免使用者暫停朗讀後、App 進一步被系統
        // 節流時無法重新啟動前景服務。
        androidStopForegroundOnPause: false,
      ),
    ),
  );
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
  // epic-8-sync Issue 6：Issue 4/5 只在測試中建構過 SyncEngine，這裡是
  // App 正式啟動流程第一次真正組裝一個會運作的實例（見
  // plan-issue-6.md Task 6「與 issues.md 的落差說明」）。navigatorKey
  // 用來在 SyncEngine 的閱讀位置衝突回呼中取得 BuildContext 顯示對話框
  // ——SyncEngine 本身刻意不依賴 Flutter widget 樹（見 sync_engine.dart
  // 既有設計，保持可離線單元測試），衝突對話框的顯示改由這裡的回呼
  // 橋接。
  final navigatorKey = GlobalKey<NavigatorState>();
  final syncMetadataRepository = SyncMetadataRepository(repository.database);
  final syncEngine = SyncEngine(
    db: repository.database,
    accountRepository: syncAccountRepository,
    metadataRepository: syncMetadataRepository,
    onReadingPositionConflict: (conflict) async {
      final context = navigatorKey.currentContext;
      // App 啟動極早期（尚未渲染出第一個畫面）理論上呼叫不到這裡——
      // checkpoint 觸發來源（Task 3-5）都發生在畫面已經渲染之後；仍防禦
      // 性處理 context 為 null 的情況，回傳 null 等同使用者關閉對話框
      // 未決定，SyncEngine 會照既有邏輯留待下次 checkpoint 重試，不會
      // 拋出例外或靜默覆蓋任一邊（FR-19）。
      if (context == null) return null;
      return showReadingPositionConflictDialog(context, conflict);
    },
  );
  final syncCheckpointTrigger = SyncCheckpointTrigger(
    runCheckpoint: syncEngine.runCheckpoint,
    // epic-50-sync-token-refresh：自動同步時登入過期，比照上方衝突對話框
    // 透過 navigatorKey 取得目前畫面的 context，顯示一次性 Toast。
    onSessionExpired: () {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.syncSessionExpiredToast),
        ),
      );
    },
  );
  final remoteServerRepository = SqliteRemoteServerRepository(
    database: repository.database,
    libraryRepository: repository,
  );
  final thumbnailCacheDir = await getApplicationCacheDirectory();
  final thumbnailCache = RemoteThumbnailCacheImpl(
    cacheDir: Directory(p.join(thumbnailCacheDir.path, 'remote_thumbnails')),
  );
  // epic-29-cloud-import Issue 1/2：雲端匯入帳號模組
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient = GoogleDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  final oneDriveOAuthClient = OneDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  // epic-29-cloud-import Issue 3/4：Google Drive／OneDrive 瀏覽＋下載。
  // 皆無內部可變的 session 狀態（不像 OpdsHttpClient 的
  // _visitedFeedUrls），單一共用實例即可，不需要比照 createOpdsClient
  // 那樣的工廠函式。
  final CloudStorageClient googleDriveStorageClient = GoogleDriveStorageClient(
    oauthClient: googleDriveOAuthClient,
  );
  final CloudStorageClient oneDriveStorageClient = OneDriveStorageClient(
    oauthClient: oneDriveOAuthClient,
  );
  // 視覺還原（Visual Accuracy Mode）：常駐下載佇列控制器，比照上方
  // SyncEngine.onReadingPositionConflict 的既有橋接原則——控制器本身
  // 不依賴 Flutter widget 樹，需要彈出「重複匯入」確認對話框時透過
  // navigatorKey 取得目前可用的 BuildContext，不綁定觸發下載當下所在的
  // 那個畫面（使用者可能已經離開）。
  final downloadQueueController = DownloadQueueController(
    onDuplicateConfirm: (name) async {
      final context = navigatorKey.currentContext;
      if (context == null) return false;
      final l10n = AppLocalizations.of(context)!;
      return showCloudDuplicateConfirmDialog(
        context,
        l10n.downloadQueueDuplicateConfirmMessage(name),
      );
    },
  );
  // ADR 0037：依賴組由 main() 建構一次，ElinkBookApp 原樣往下傳（主題／語言切換
  // 重建 App 時不會變成新實例）。syncCheckpointTrigger 同一實例放進兩組。
  final readerFeatures = ReaderFeatureDependencies(
    prefsManager: prefsManager,
    libraryRepository: repository,
    bookImportService: importService,
    bookmarksRepository: bookmarksRepository,
    highlightsRepository: highlightsRepository,
    notesRepository: notesRepository,
    customFontsRepository: customFontsRepository,
    downloadableFontStore: downloadableFontStore,
    layoutPresetRepository: layoutPresetRepository,
    bookReaderPrefsRepository: prefsRepository,
    searchRepository: searchRepository,
    isFullTextSearchAvailable: repository.isFullTextSearchAvailable,
    fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
    readingStatsRepository: readingStatsRepository,
    readerActivityTracker: readerActivityTracker,
    syncCheckpointTrigger: syncCheckpointTrigger,
    ttsProvider: ttsProvider,
    ttsAudio: ttsAudio,
    ttsAudioFocusSource: ttsAudioFocusSource,
  );
  final sync = SyncDependencies(
    syncAccountRepository: syncAccountRepository,
    syncClient: syncClient,
    syncCheckpointTrigger: syncCheckpointTrigger,
    onManualSync: syncEngine.runCheckpoint,
    loadLastSyncedAt: syncMetadataRepository.loadLastPushCompletedAt,
  );
  // ADR 0037：來源依賴組由 main() 建構一次，ElinkBookApp 原樣往下傳。
  final sources = SourceDependencies(
    cloudAccountRepository: cloudAccountRepository,
    googleDriveOAuthClient: googleDriveOAuthClient,
    oneDriveOAuthClient: oneDriveOAuthClient,
    googleDriveStorageClient: googleDriveStorageClient,
    oneDriveStorageClient: oneDriveStorageClient,
    remoteServerRepository: remoteServerRepository,
    createOpdsClient: () => OpdsHttpClient(),
    thumbnailCache: thumbnailCache,
    computeFingerprint: computeBookContentFingerprint,
    isMobileDataConnection: _isMobileDataConnection,
    checkNetworkAvailability: checkNetworkAvailability,
    downloadQueueController: downloadQueueController,
  );
  runApp(
    ElinkBookApp(
      readerFeatures: readerFeatures,
      sync: sync,
      sources: sources,
      navigatorKey: navigatorKey,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
      localePreferences: localePreferences,
      initialLocaleOverride: initialLocaleOverride,
    ),
  );
}

/// elinkBook App 根元件。啟動時接受從 main 傳入之 [initialTheme] 與
/// [initialEinkMode]（解決開機閃白屏與狀態競爭問題，見 review 意見）。
class ElinkBookApp extends StatefulWidget {
  /// 閱讀器功能、同步與來源依賴組（ADR 0037）：由 `main()` 建構一次，原樣往下傳。
  final ReaderFeatureDependencies readerFeatures;
  final SyncDependencies sync;
  final SourceDependencies sources;
  final GlobalKey<NavigatorState>? navigatorKey;
  final AppLocalePreferences localePreferences;
  final AppLocale? initialLocaleOverride;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.readerFeatures,
    required this.sync,
    required this.sources,
    this.navigatorKey,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    this.initialLocaleOverride,
    AppLocalePreferences? localePreferences,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences(),
       localePreferences = localePreferences ?? AppLocalePreferences();

  @override
  State<ElinkBookApp> createState() => _ElinkBookAppState();
}

class _ElinkBookAppState extends State<ElinkBookApp>
    with WidgetsBindingObserver {
  late AppTheme _theme;
  late bool _isEinkMode;
  AppLocale? _localeOverride;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme = widget.initialTheme;
    _isEinkMode = widget.initialEinkMode;
    _localeOverride = widget.initialLocaleOverride;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// epic-8-sync Issue 6（spec.md「同步引擎」checkpoint 觸發來源之
  /// 「App 生命週期監聽」）：只在 [AppLifecycleState.paused]（真正進入
  /// 背景）觸發，不含 [AppLifecycleState.inactive]（系統對話框短暫遮蓋等
  /// 過渡狀態）——比照 `reader_screen.dart` 既有
  /// `didChangeAppLifecycleState` 對 `ReadingPositionSaver.save` 的同一條
  /// 判斷準則。不 await，理由同 `reader_screen.dart` 既有慣例。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      widget.sync.syncCheckpointTrigger.trigger();
    }
  }

  void _handleThemeChanged(AppTheme theme) {
    setState(() => _theme = theme);
    widget.themePreferences.saveTheme(theme);
  }

  void _handleEinkModeChanged(bool enabled) {
    setState(() => _isEinkMode = enabled);
    widget.themePreferences.saveEinkMode(enabled);
  }

  void _handleLocaleChanged(AppLocale? locale) {
    setState(() => _localeOverride = locale);
    widget.localePreferences.saveLocaleOverride(locale);
  }

  @override
  Widget build(BuildContext context) {
    final themeData = resolveThemeData(theme: _theme, isEinkMode: _isEinkMode);
    // 外觀快照（ADR 0037 Task 0 Q1-A）：可變狀態的擁有者是這個 State，
    // 每次 build 依目前值現組一份往下傳；三個子畫面看到同一份。其他三組
    // （readerFeatures／sync／sources）仍是 main() 建的同一實例。
    final appearance = AppearanceDependencies(
      currentTheme: _theme,
      isEinkMode: _isEinkMode,
      currentLocaleOverride: _localeOverride,
      onThemeChanged: _handleThemeChanged,
      onEinkModeChanged: _handleEinkModeChanged,
      onLocaleChanged: _handleLocaleChanged,
    );
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'elinkBook',
      theme: themeData,
      themeAnimationDuration: Duration.zero,
      locale: _localeOverride?.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (deviceLocales, supportedLocales) =>
          resolveMaterialAppLocale(deviceLocales),
      home: AdaptiveShellScaffold(
        readerFeatures: widget.readerFeatures,
        sync: widget.sync,
        sources: widget.sources,
        appearance: appearance,
      ),
    );
  }
}
