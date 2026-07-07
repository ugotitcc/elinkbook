/// 全域閱讀主題（FR-31），三選一，跨書籍一致。E-Ink 高對比模式為獨立的
/// 全域布林開關（見 `AppThemePreferences.loadEinkMode`），不是第 4 種
/// 主題選項——兩者可同時生效，但 E-Ink 開啟時畫面一律呈現固定的高對比
/// 黑白樣式，[AppTheme] 的選擇僅在 E-Ink 關閉時才影響實際呈現（見
/// docs/epics/epic-3-fonts-layout/design.md「FR-31」與 CONTEXT.md
/// 「E-Ink 高對比模式」詞條）。
enum AppTheme { light, dark, sepia }
