import 'package:flutter/material.dart';

import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../wifi_transfer/wifi_transfer_dependencies.dart';
import 'library_screen.dart';
import 'library_screen_dependencies.dart';
import 'settings_scaffold.dart';
import 'sources_home_screen.dart';

class _LibraryRefreshSignal extends ChangeNotifier {
  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}

/// 三目的地導覽外殼（epic-36-adaptive-shelf-navigation spec.md §功能①）：
/// 書架／來源／設定互相以圖示切換，`IndexedStack` 保留三個目的地畫面狀態，
/// 手機寬度不使用底部導覽列。三個子畫面的狀態保留完全由 `IndexedStack`
/// 本身負責（所有子項全程掛載、只是視覺上切換顯示），**不需要、也不應該**
/// 把子畫面 widget 快取成欄位——只要 `build()` 每次都建構「相同
/// `runtimeType`、相同清單位置」的 widget，Flutter reconciliation
/// （`Element.update`／`State.didUpdateWidget`）就會重用既有 `Element`／
/// `State`，`LibraryScreen` 的頁碼/搜尋/下鑽狀態不會遺失；反之若快取成
/// `late final` 欄位，上層 `themeDependencies` 等參數之後的變更（例如
/// 使用者在「設定」切換主題／E-Ink 模式回呼到 `main.dart` 觸發
/// `setState()`）永遠不會被子畫面收到（審查報告 review-plan-issue-1.md
/// C-1，本計劃已依此修正為 `build()` 內直接建構）。
class AdaptiveShellScaffold extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final LibraryCloudAccountDependencies cloudAccountDependencies;
  final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
  final ComputeRemoteFingerprint? computeFingerprint;
  final Future<bool> Function()? isMobileDataConnection;
  final DownloadQueueController? downloadQueueController;
  final LibraryThemeDependencies themeDependencies;

  /// 介面語言依賴（epic-45-interface-i18n Issue 1，`spec.md` §4）。
  final LibraryLocaleDependencies localeDependencies;

  /// WiFi 傳書入口依賴（epic-44-wifi-book-transfer Issue 1），原樣往下
  /// 傳給 `SourcesHomeScreen`。
  final WifiTransferDependencies? wifiTransferDependencies;

  const AdaptiveShellScaffold({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.themeDependencies = const LibraryThemeDependencies(),
    this.localeDependencies = const LibraryLocaleDependencies(),
    this.wifiTransferDependencies,
  });

  @override
  State<AdaptiveShellScaffold> createState() => _AdaptiveShellScaffoldState();
}

class _AdaptiveShellScaffoldState extends State<AdaptiveShellScaffold> {
  int _currentIndex = 0;
  final _libraryRefreshSignal = _LibraryRefreshSignal();

  @override
  void dispose() {
    _libraryRefreshSignal.dispose();
    super.dispose();
  }

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
    if (index == 0) _libraryRefreshSignal.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    // 【審查修正 review-plan-issue-1.md C-1】三個子畫面在此直接建構、不
    // 快取成欄位——IndexedStack 讓所有子項全程掛載，Flutter 依
    // runtimeType/清單位置比對重用既有 Element/State，狀態不會遺失；
    // 反之若快取在 initState()，widget.themeDependencies 等參數之後的
    // 變更就永遠傳不到已快取的子畫面（例如使用者在「設定」切主題/E-Ink
    // 後，SettingsScaffold/SourcesHomeScreen 拿到的仍是最初舊值）。
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigateTo(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            LibraryScreen(
              repository: widget.repository,
              importService: widget.importService,
              prefsManager: widget.prefsManager,
              readerFeatureRepositories: widget.readerFeatureRepositories,
              syncDependencies: widget.syncDependencies,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              themeDependencies: widget.themeDependencies,
              refreshSignal: _libraryRefreshSignal,
              onNavigateToSource: () => _navigateTo(1),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SourcesHomeScreen(
              repository: widget.repository,
              importService: widget.importService,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              downloadQueueController: widget.downloadQueueController,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
              wifiTransferDependencies: widget.wifiTransferDependencies,
            ),
            SettingsScaffold(
              prefsManager: widget.prefsManager,
              currentTheme: widget.themeDependencies.currentTheme,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onThemeChanged: widget.themeDependencies.onThemeChanged,
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              currentLocaleOverride:
                  widget.localeDependencies.currentLocaleOverride,
              onLocaleChanged: widget.localeDependencies.onLocaleChanged,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              downloadableFontStore:
                  widget.readerFeatureRepositories.downloadableFontStore,
              syncAccountRepository:
                  widget.syncDependencies.syncAccountRepository,
              syncClient: widget.syncDependencies.syncClient,
              onManualSync: widget.syncDependencies.onManualSync,
              loadLastSyncedAt: widget.syncDependencies.loadLastSyncedAt,
              cloudAccountRepository:
                  widget.cloudAccountDependencies.cloudAccountRepository,
              googleDriveOAuthClient:
                  widget.cloudAccountDependencies.googleDriveOAuthClient,
              oneDriveOAuthClient:
                  widget.cloudAccountDependencies.oneDriveOAuthClient,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSource: () => _navigateTo(1),
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              fullTextSearchSettingsRepository: widget
                  .readerFeatureRepositories.fullTextSearchSettingsRepository,
              isFullTextSearchAvailable:
                  widget.readerFeatureRepositories.isFullTextSearchAvailable,
            ),
          ],
        ),
      ),
    );
  }
}
