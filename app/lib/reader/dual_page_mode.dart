/// PDF 與 EPUB 固定版面橫向雙頁顯示的觸發模式（FR-41）。[auto]
/// 橫向自動啟用雙頁、直向恢復單頁（預設）；[always] 永遠雙頁；[never]
/// 永遠單頁。見 docs/epics/epic-16-dual-page/spec.md「資料模型」。
enum DualPageMode { auto, always, never }
