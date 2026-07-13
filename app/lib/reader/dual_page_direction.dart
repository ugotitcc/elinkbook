/// PDF 雙頁顯示時的頁面配對閱讀方向（FR-41，僅 PDF 適用；EPUB 固定版面
/// 由 Readium 依 `page-progression-direction` metadata 自動處理，見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右；
/// [rtl] 右到左（日漫慣例，亦為 elinkBook 全域固定預設值——本專案核心
/// 差異化為直排繁體中文排版支援，見 issues.md Issue 4 的決策記錄）。
enum DualPageDirection { ltr, rtl }
