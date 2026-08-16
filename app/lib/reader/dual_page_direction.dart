/// 雙頁顯示時的頁面配對閱讀方向（FR-41／FR-43）；PDF／CBZ 皆適用（CBZ 由
/// epic-11-multi-format-reader Issue 3 起擴大適用範圍——`FxlSettingsSheet`
/// 提供對應設定入口）；EPUB 固定版面由 `epub.js` 依書本 OPF
/// `page-progression-direction` metadata 自動處理，不透過本欄位覆寫（見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右；
/// [rtl] 右到左（日漫慣例，亦為 elinkBook 全域固定預設值——本專案核心
/// 差異化為直排繁體中文排版支援，見 issues.md Issue 4 的決策記錄）。
enum DualPageDirection { ltr, rtl }
