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

import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/onedrive_storage_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'downloads/download_queue_controller.dart';
import 'library/book_content_fingerprint.dart';
import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'licenses/third_party_licenses.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/bookmarks_repository.dart';
import 'reader/custom_fonts_repository.dart';
import 'reader/downloadable_font_store.dart';
import 'reader/highlights_repository.dart';
import 'reader/layout_preset_repository.dart';
import 'reader/notes_repository.dart';
import 'reader/reader_prefs_manager.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'reader/reading_position_repository.dart';
import 'reader/system_tts_provider.dart';
import 'reader/tts_audio_focus_source.dart';
import 'reader/tts_audio_handler.dart';
import 'reader/tts_provider.dart';
import 'reader/webview_font_support.dart';
import 'remote/opds_client.dart';
import 'remote/opds_http_client.dart';
import 'remote/remote_server_repository.dart';
import 'wifi_transfer/network_availability.dart';
import 'wifi_transfer/wifi_transfer_dependencies.dart';
import 'remote/remote_thumbnail_cache.dart';
import 'remote/sqlite_remote_server_repository.dart';
import 'screens/adaptive_shell_scaffold.dart';
import 'screens/cloud_duplicate_confirm_dialog.dart';
import 'screens/library_screen_dependencies.dart';
import 'screens/reading_position_conflict_dialog.dart';
import 'sync/sync_account_repository.dart';
import 'sync/sync_checkpoint_result.dart';
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
import 'stats/reading_stats_repository.dart';
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
        p.join((await getApplicationSupportDirectory()).path, 'downloaded-fonts')),
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
  // 見 Issue 2）；經 LibraryReaderFeatureRepositories 貫穿所有開書路徑。
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
  // plans/plan-issue-7.md Global Constraints），建構出的單一 handler
  // 由 ReaderScreen 於每次開書時呼叫 attachController()／
  // detachController() 綁定/解綁目前的 TtsController。
  // 通知頻道名稱（顯示於系統的通知設定）：此時尚無 BuildContext，改用啟動階段解析的
  // AppLocalizations（使用者覆寫語言優先，否則跟隨裝置語言）。頻道只在此處建立一次，
  // 語言以啟動當下為準（epic-45-interface-i18n Issue 10）。
  final startupL10n = resolveStartupLocalizations(
    localeOverride: initialLocaleOverride,
    deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
  );
  final ttsAudioHandler = await AudioService.init(
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
        SnackBar(content: Text(AppLocalizations.of(context)!.syncSessionExpiredToast)),
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
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsManager: prefsManager,
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      customFontsRepository: customFontsRepository,
      downloadableFontStore: downloadableFontStore,
      layoutPresetRepository: layoutPresetRepository,
      bookReaderPrefsRepository: prefsRepository,
      ttsProvider: ttsProvider,
      ttsAudioHandler: ttsAudioHandler,
      ttsAudioFocusSource: ttsAudioFocusSource,
      readerActivityTracker: readerActivityTracker,
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
      onManualSync: syncEngine.runCheckpoint,
      loadLastSyncedAt: syncMetadataRepository.loadLastPushCompletedAt,
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
      oneDriveStorageClient: oneDriveStorageClient,
      remoteServerRepository: remoteServerRepository,
      createOpdsClient: () => OpdsHttpClient(),
      computeFingerprint: computeBookContentFingerprint,
      thumbnailCache: thumbnailCache,
      isMobileDataConnection: _isMobileDataConnection,
      checkNetworkAvailability: checkNetworkAvailability,
      downloadQueueController: downloadQueueController,
      navigatorKey: navigatorKey,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
      localePreferences: localePreferences,
      initialLocaleOverride: initialLocaleOverride,
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      isFullTextSearchAvailable: repository.isFullTextSearchAvailable,
      searchRepository: searchRepository,
      readingStatsRepository: readingStatsRepository,
    ),
  );
}

/// elinkBook App 根元件。啟動時接受從 main 傳入之 [initialTheme] 與
/// [initialEinkMode]（解決開機閃白屏與狀態競爭問題，見 review 意見）。
class ElinkBookApp extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final DownloadableFontStore? downloadableFontStore;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final TtsProvider? ttsProvider;
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;
  final ReaderActivityTracker? readerActivityTracker;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;

  /// 「立即同步」按鈕與最後同步時間顯示（2026-09-08 `/grill-with-docs`
  /// 使用者需求），見 `SyncSettingsScreen`／`LibrarySyncDependencies` 的
  /// 欄位說明。
  final Future<SyncCheckpointResult> Function()? onManualSync;
  final Future<int?> Function()? loadLastSyncedAt;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient Function()? createOpdsClient;
  final ComputeRemoteFingerprint? computeFingerprint;
  final RemoteThumbnailCache? thumbnailCache;
  final Future<bool> Function()? isMobileDataConnection;
  final DownloadQueueController? downloadQueueController;
  final GlobalKey<NavigatorState>? navigatorKey;
  final AppLocalePreferences localePreferences;
  final AppLocale? initialLocaleOverride;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;

  /// epic-9-stats Issue 4：每日閱讀統計的存取層，放進
  /// `LibraryReaderFeatureRepositories` 轉交給閱讀器。
  final ReadingStatsRepository? readingStatsRepository;

  /// WiFi 傳書入口的網路先決條件偵測（epic-44-wifi-book-transfer
  /// Issue 1），生產環境傳入 `checkNetworkAvailability`（`network_availability.dart`
  /// 頂層函式）。
  final CheckNetworkAvailability? checkNetworkAvailability;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.downloadableFontStore,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.readerActivityTracker,
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.onManualSync,
    this.loadLastSyncedAt,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
    this.remoteServerRepository,
    this.createOpdsClient,
    this.computeFingerprint,
    this.thumbnailCache,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.navigatorKey,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    this.searchRepository,
    this.readingStatsRepository,
    this.checkNetworkAvailability,
    this.initialLocaleOverride,
    AppLocalePreferences? localePreferences,
    AppThemePreferences? themePreferences,
  })  : themePreferences = themePreferences ?? AppThemePreferences(),
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
      widget.syncCheckpointTrigger?.trigger();
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
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: widget.bookmarksRepository,
          highlightsRepository: widget.highlightsRepository,
          notesRepository: widget.notesRepository,
          customFontsRepository: widget.customFontsRepository,
          downloadableFontStore: widget.downloadableFontStore,
          layoutPresetRepository: widget.layoutPresetRepository,
          bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
          ttsProvider: widget.ttsProvider,
          ttsAudioHandler: widget.ttsAudioHandler,
          ttsAudioFocusSource: widget.ttsAudioFocusSource,
          readerActivityTracker: widget.readerActivityTracker,
          fullTextSearchSettingsRepository:
              widget.fullTextSearchSettingsRepository,
          isFullTextSearchAvailable: widget.isFullTextSearchAvailable,
          searchRepository: widget.searchRepository,
          readingStatsRepository: widget.readingStatsRepository,
          // epic-15-storage-permission Issue 0：閱讀器在檔案存取失效時
          // 重新連結書籍需要匯入服務（Issue 2 使用），與上方
          // importService 參數是同一個實例。
          bookImportService: widget.importService,
        ),
        syncDependencies: LibrarySyncDependencies(
          syncAccountRepository: widget.syncAccountRepository,
          syncClient: widget.syncClient,
          syncCheckpointTrigger: widget.syncCheckpointTrigger,
          onManualSync: widget.onManualSync,
          loadLastSyncedAt: widget.loadLastSyncedAt,
        ),
        cloudAccountDependencies: LibraryCloudAccountDependencies(
          cloudAccountRepository: widget.cloudAccountRepository,
          googleDriveOAuthClient: widget.googleDriveOAuthClient,
          oneDriveOAuthClient: widget.oneDriveOAuthClient,
          googleDriveStorageClient: widget.googleDriveStorageClient,
          oneDriveStorageClient: widget.oneDriveStorageClient,
        ),
        remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
          remoteServerRepository: widget.remoteServerRepository,
          createOpdsClient: widget.createOpdsClient,
          thumbnailCache: widget.thumbnailCache,
        ),
        computeFingerprint: widget.computeFingerprint,
        isMobileDataConnection: widget.isMobileDataConnection,
        downloadQueueController: widget.downloadQueueController,
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
        localeDependencies: LibraryLocaleDependencies(
          currentLocaleOverride: _localeOverride,
          onLocaleChanged: _handleLocaleChanged,
        ),
        wifiTransferDependencies: WifiTransferDependencies(
          libraryRepository: widget.repository,
          importService: widget.importService,
          computeFingerprint: widget.computeFingerprint,
          checkNetworkAvailability: widget.checkNetworkAvailability,
        ),
      ),
    );
  }
}
