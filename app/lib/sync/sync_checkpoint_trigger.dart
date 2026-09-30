import 'sync_checkpoint_result.dart';

/// Checkpoint 觸發器（epic-8-sync Issue 6，spec.md「同步引擎」／
/// issues.md Issue 6）：包裝一次 `SyncEngine.runCheckpoint()` 呼叫，並把
/// 結果對應到「自動觸發」的提示策略。
///
/// 併發鎖與未登入判斷**不**由本類別負責——`SyncEngine.runCheckpoint()`
/// 本身已內建單一執行鎖與未登入的提早回傳（見 `sync_engine.dart`，分別
/// 回報 [SyncCheckpointResult.alreadyRunning]／[SyncCheckpointResult.notLoggedIn]），
/// 本類別只單純轉呼叫。
///
/// 刻意用函式注入（[runCheckpoint]）而非直接持有 `SyncEngine` 具體型別：
/// 三個實際觸發點（App 生命週期觀察者、`ReaderScreen.dispose()`、
/// `ReaderScreen` 內的週期性 `Timer`）都只需要「呼叫一次 checkpoint」這個
/// 動作，注入函式讓 widget test 可以用簡單的假 callback 驗證觸發時機，
/// 不需要牽動真實資料庫／PocketBase 用戶端。
///
/// 登入過期提示（epic-50-sync-token-refresh、epic-53-sync-checkpoint-result）：
/// checkpoint 回報 [SyncCheckpointResult.sessionExpired] 時呼叫
/// [onSessionExpired] 提示使用者重新登入，其餘結果一律靜默（沿用「失敗就
/// 靜默、下次觸發自然重試」精神）。只掛在這三個自動觸發點上——手動同步由
/// `SyncSettingsScreen` 自己在畫面內提示，不經過本類別，不會重複提示。
/// 過期後已是未登入，後續觸發只會得到 `notLoggedIn`，因此每次過期只會
/// 提示一次。
class SyncCheckpointTrigger {
  final Future<SyncCheckpointResult> Function() _runCheckpoint;
  final void Function()? _onSessionExpired;

  SyncCheckpointTrigger({
    required Future<SyncCheckpointResult> Function() runCheckpoint,
    void Function()? onSessionExpired,
  })  : _runCheckpoint = runCheckpoint,
        _onSessionExpired = onSessionExpired;

  Future<void> trigger() async {
    final result = await _runCheckpoint();
    if (result == SyncCheckpointResult.sessionExpired) {
      _onSessionExpired?.call();
    }
  }
}
