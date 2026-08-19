import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/onedrive_storage_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/bookmarks_repository.dart';
import 'reader/custom_fonts_repository.dart';
import 'reader/epub_character_count_repository.dart';
import 'reader/highlights_repository.dart';
import 'reader/layout_preset_repository.dart';
import 'reader/notes_repository.dart';
import 'reader/reader_prefs_manager.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'reader/reading_position_repository.dart';
import 'remote/opds_client.dart';
import 'remote/opds_http_client.dart';
import 'remote/remote_server_repository.dart';
import 'remote/remote_thumbnail_cache.dart';
import 'remote/sqlite_remote_server_repository.dart';
import 'screens/library_screen.dart';
import 'screens/reading_position_conflict_dialog.dart';
import 'sync/sync_account_repository.dart';
import 'sync/sync_checkpoint_trigger.dart';
import 'sync/sync_client.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_metadata_repository.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_data.dart';
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
  // pdfrx（PDFium FFI）初始化，epic-24-pdf-engine-rebuild：Flutter App
  // 執行期一律呼叫 pdfrxFlutterInitialize()（而非 pdfrxInitialize()，後者
  // 用於純 Dart、無 Flutter 環境），須在任何 PDF 開書呼叫之前完成。
  await pdfrxFlutterInitialize();

  final themePreferences = AppThemePreferences();
  final initialTheme = await themePreferences.loadTheme();
  final initialEinkMode = await themePreferences.loadEinkMode();

  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
    EpubCharacterCountRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
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
    isLoggedIn: syncAccountRepository.isLoggedIn,
    runCheckpoint: syncEngine.runCheckpoint,
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
  final CloudStorageClient googleDriveStorageClient =
      GoogleDriveStorageClient(oauthClient: googleDriveOAuthClient);
  final CloudStorageClient oneDriveStorageClient =
      OneDriveStorageClient(oauthClient: oneDriveOAuthClient);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsManager: prefsManager,
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      customFontsRepository: customFontsRepository,
      layoutPresetRepository: layoutPresetRepository,
      bookReaderPrefsRepository: prefsRepository,
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
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
      navigatorKey: navigatorKey,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
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
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
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
  final GlobalKey<NavigatorState>? navigatorKey;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
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
    this.navigatorKey,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();

  @override
  State<ElinkBookApp> createState() => _ElinkBookAppState();
}

class _ElinkBookAppState extends State<ElinkBookApp> with WidgetsBindingObserver {
  late AppTheme _theme;
  late bool _isEinkMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme = widget.initialTheme;
    _isEinkMode = widget.initialEinkMode;
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
  /// `didChangeAppLifecycleState` 對 `_writeCurrentPosition()` 的同一條
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

  @override
  Widget build(BuildContext context) {
    final themeData = resolveThemeData(
      theme: _theme,
      isEinkMode: _isEinkMode,
    );
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'elinkBook',
      theme: themeData,
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        bookmarksRepository: widget.bookmarksRepository,
        highlightsRepository: widget.highlightsRepository,
        notesRepository: widget.notesRepository,
        customFontsRepository: widget.customFontsRepository,
        layoutPresetRepository: widget.layoutPresetRepository,
        bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
        syncAccountRepository: widget.syncAccountRepository,
        syncClient: widget.syncClient,
        syncCheckpointTrigger: widget.syncCheckpointTrigger,
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        googleDriveStorageClient: widget.googleDriveStorageClient,
        oneDriveStorageClient: widget.oneDriveStorageClient,
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
        computeFingerprint: widget.computeFingerprint,
        thumbnailCache: widget.thumbnailCache,
        isMobileDataConnection: widget.isMobileDataConnection,
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
      ),
    );
  }
}
