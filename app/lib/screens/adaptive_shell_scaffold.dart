import 'package:flutter/material.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen.dart';
import 'library_screen_dependencies.dart';
import 'settings_screen.dart';
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
///
/// **過渡期型別標注**：`SettingsScreen`→`SettingsScaffold` 更名排在 Issue
/// 5，本類別第三個子畫面暫時掛載既有 `SettingsScreen`（見
/// `reviews/review-issues.md` M-1）。
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
  final LibraryThemeDependencies themeDependencies;

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
    this.themeDependencies = const LibraryThemeDependencies(),
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
    // 後，SettingsScreen/SourcesHomeScreen 拿到的仍是最初舊值）。
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
              isEinkMode: widget.themeDependencies.isEinkMode,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SettingsScreen(
              prefsManager: widget.prefsManager,
              currentTheme: widget.themeDependencies.currentTheme,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onThemeChanged: widget.themeDependencies.onThemeChanged,
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              syncAccountRepository: widget.syncDependencies.syncAccountRepository,
              syncClient: widget.syncDependencies.syncClient,
              cloudAccountRepository:
                  widget.cloudAccountDependencies.cloudAccountRepository,
              googleDriveOAuthClient:
                  widget.cloudAccountDependencies.googleDriveOAuthClient,
              oneDriveOAuthClient:
                  widget.cloudAccountDependencies.oneDriveOAuthClient,
            ),
          ],
        ),
      ),
    );
  }
}