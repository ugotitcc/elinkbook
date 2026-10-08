import 'package:flutter/material.dart';

import 'appearance_dependencies.dart';
import 'library_screen.dart';
import 'reader_feature_dependencies.dart';
import 'settings_scaffold.dart';
import 'source_dependencies.dart';
import 'sources_home_screen.dart';
import 'sync_dependencies.dart';

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
/// `late final` 欄位，上層 `appearance` 等參數之後的變更（例如
/// 使用者在「設定」切換主題／E-Ink 模式回呼到 `main.dart` 觸發
/// `setState()`）永遠不會被子畫面收到（審查報告 review-plan-issue-1.md
/// C-1，本計劃已依此修正為 `build()` 內直接建構）。
class AdaptiveShellScaffold extends StatefulWidget {
  /// 閱讀器功能依賴組（ADR 0037）：整組轉傳給書架與設定頁；書架／匯入用的
  /// libraryRepository、bookImportService、prefsManager 皆取自這一組（單一來源）。
  final ReaderFeatureDependencies readerFeatures;

  /// 同步依賴組（ADR 0037）：只有設定頁的「同步」入口使用。
  final SyncDependencies sync;

  /// 來源依賴組（ADR 0037）：原樣往下傳給書架、來源頁與設定頁。
  final SourceDependencies sources;

  /// 外觀快照（ADR 0037）：由 `ElinkBookApp` 每次 build 現組，原樣往下傳給
  /// 三個子畫面——三處看到的是同一份快照。
  final AppearanceDependencies appearance;

  const AdaptiveShellScaffold({
    super.key,
    required this.readerFeatures,
    required this.sync,
    required this.sources,
    required this.appearance,
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
    // 反之若快取在 initState()，widget.appearance 等參數之後的
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
              dependencies: widget.readerFeatures,
              sources: widget.sources,
              appearance: widget.appearance,
              refreshSignal: _libraryRefreshSignal,
              onNavigateToSource: () => _navigateTo(1),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SourcesHomeScreen(
              readerFeatures: widget.readerFeatures,
              sources: widget.sources,
              appearance: widget.appearance,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SettingsScaffold(
              readerFeatures: widget.readerFeatures,
              sync: widget.sync,
              sources: widget.sources,
              appearance: widget.appearance,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSource: () => _navigateTo(1),
            ),
          ],
        ),
      ),
    );
  }
}
