/// PDF 翻頁模式（epic-56-pdf-paginated-reading）。[paginated]（逐頁）一次只顯示
/// 一頁（開雙頁時為一個 spread）、換頁瞬間切換；[scroll]（連續捲動）頁面上下
/// 相連，即現況。偏好為 `null` 時一律解讀為 [paginated]（見 `CONTEXT.md`
/// 「翻頁模式」）。與 EPUB 的 `PageTurnMode`（分頁／捲動）是不同型別。
enum PdfPageTurnMode { paginated, scroll }
