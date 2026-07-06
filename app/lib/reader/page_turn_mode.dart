/// 換頁模式：分頁（paginated，Readium 預設）或連續捲動（scroll）。對應
/// Readium `EpubPreferences.scroll`（見
/// docs/adr/0004-epub-reader-page-turn-mode-contract.md）。捲動模式是
/// Issue 3 驗證過、用於規避直排分頁欄位裁切風險（`readium/swift-toolkit#804`）
/// 的暫行方案，供使用者選用，不是自動套用的預設行為。
enum PageTurnMode { paginated, scroll }
