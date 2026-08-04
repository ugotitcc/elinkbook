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
class SyncCheckpointTrigger {
  final Future<bool> Function() _isLoggedIn;
  final Future<void> Function() _runCheckpoint;

  SyncCheckpointTrigger({
    required Future<bool> Function() isLoggedIn,
    required Future<void> Function() runCheckpoint,
  })  : _isLoggedIn = isLoggedIn,
        _runCheckpoint = runCheckpoint;

  Future<void> trigger() async {
    if (!await _isLoggedIn()) return;
    await _runCheckpoint();
  }
}
