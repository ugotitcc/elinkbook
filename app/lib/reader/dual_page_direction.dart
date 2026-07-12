/// PDF 雙頁顯示時的頁面配對閱讀方向（FR-41，僅 PDF 適用；EPUB 固定版面
/// 由 Readium 依 `page-progression-direction` metadata 自動處理，見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右
/// （預設）；[rtl] 右到左（日漫慣例）。
enum DualPageDirection { ltr, rtl }
