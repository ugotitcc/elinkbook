/// 一次 `SyncEngine.runCheckpoint()` 的結果（epic-53-sync-checkpoint-result）。
///
/// 只描述「這一次 checkpoint 剛發生什麼」；「先前是否已過期」這種持久狀態
/// 由 `SyncAccountRepository.isSessionExpired()` 判定（開啟設定畫面時使用）。
enum SyncCheckpointResult {
  /// 推送＋下載整輪成功。
  synced,

  /// 另一次 checkpoint 仍在執行中（併發鎖），本次直接放棄，不算失敗。
  alreadyRunning,

  /// 未登入（沒有 token），或續期期間帳號已變動（使用者登出／重新登入）。
  notLoggedIn,

  /// 登入過期：續期收到 401，token 已被清除（保留 email，見 CONTEXT.md
  /// 「登入過期」）。需請使用者重新登入。
  sessionExpired,

  /// 網路或伺服器錯誤，或有 token 但 userId／伺服器網址缺失（憑證不完整，
  /// 屬異常）；維持登入，下次 checkpoint 自然重試。
  failed,
}
