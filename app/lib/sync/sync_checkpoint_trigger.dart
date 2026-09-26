/// Checkpoint 觸發器（epic-8-sync Issue 6，spec.md「同步引擎」／
/// issues.md Issue 6）：包裝一次 `SyncEngine.runCheckpoint()` 呼叫，
/// 加上「未登入（opt-in 尚未啟用同步）時完全不呼叫」的登入閘門。
///
/// 併發鎖**不**由本類別負責——`SyncEngine.runCheckpoint()` 本身已內建
/// 單一執行鎖（見 `sync_engine.dart` 的 `_isSyncing`，spec.md「同步
/// 引擎」明定併發鎖須內建於 `SyncEngine`），本類別只單純轉呼叫。
///
/// 刻意用函式注入（[isLoggedIn]／[runCheckpoint]）而非直接持有
/// `SyncAccountRepository`／`SyncEngine` 具體型別：三個實際觸發點
/// （App 生命週期觀察者、`ReaderScreen.dispose()`、`ReaderScreen` 內的
/// 週期性 `Timer`）都只需要「呼叫一次 checkpoint」這個動作，注入函式
/// 讓 widget test 可以用簡單的假 callback 驗證觸發時機，不需要牽動真實
/// 資料庫／PocketBase 用戶端。
///
/// 登入過期提示（epic-50-sync-token-refresh）：checkpoint 後若
/// [isSessionExpired] 成立（token 在這次 checkpoint 中因過期被清除），呼叫
/// [onSessionExpired] 提示使用者重新登入。只掛在這三個自動觸發點上——手動
/// 同步由 `SyncSettingsScreen` 自己在畫面內提示，不經過本類別，不會重複
/// 提示。過期後已是未登入，後續觸發在登入閘門就會略過，因此每次過期只會
/// 提示一次。
class SyncCheckpointTrigger {
  final Future<bool> Function() _isLoggedIn;
  final Future<void> Function() _runCheckpoint;
  final Future<bool> Function()? _isSessionExpired;
  final void Function()? _onSessionExpired;

  SyncCheckpointTrigger({
    required Future<bool> Function() isLoggedIn,
    required Future<void> Function() runCheckpoint,
    Future<bool> Function()? isSessionExpired,
    void Function()? onSessionExpired,
  })  : _isLoggedIn = isLoggedIn,
        _runCheckpoint = runCheckpoint,
        _isSessionExpired = isSessionExpired,
        _onSessionExpired = onSessionExpired;

  Future<void> trigger() async {
    if (!await _isLoggedIn()) return;
    await _runCheckpoint();
    final isSessionExpired = _isSessionExpired;
    final onSessionExpired = _onSessionExpired;
    if (isSessionExpired != null &&
        onSessionExpired != null &&
        await isSessionExpired()) {
      onSessionExpired();
    }
  }
}
