# `epic-35-design-system-tokens` 設計系統 Token 落地

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-35-design-system-tokens/`
**關聯 PRD 章節：** 無新增 FR，屬於 `DESIGN.md` 規範落地（色彩系統補齊、`ElinkTokens` 語意色 Token 化）
**依循規則：** `UI_DESIGN_RULES.md`（本 Epic 全程只碰 Theme／Design tokens，不碰任何列在「核心架構」下的業務邏輯）

## 開發記錄

2026-09-02 由 `/grill-with-docs`（沿用 `docs/research/uiux/eink-redesign-rebuild-plan.md` 階段 A／B 已定案的 `DESIGN.md` 更新）規劃為獨立 Epic，作為 `epic-36-adaptive-shelf-navigation` 的地基先行完成、獨立驗收。查現有程式碼確認範圍：`app/lib/theme/app_theme_data.dart`（152 行）、`app_theme_preferences.dart`、`settings_screen.dart` 的主題切換 UI／持久化／E-Ink 鎖定視覺**已經存在且可運作**，缺的只是（1）四套 `ColorScheme` 的實際色值不符 `DESIGN.md` §1.1 表格（現行 Light 主色為紫色 `#8B5CF6`，非 `DESIGN.md` 指定的天空藍 `#0284c7`，即 `DESIGN.md` 開頭所述「淡紫外洩」問題本體）、（2）沒有 `ElinkTokens`（`ThemeExtension`）類別承載螢光筆黃/綠/藍、底線色、進度條、封面佔位色、徽章罩、TTS 高亮等語意色，（3）8 個檔案（`book_cover.dart`／`foliate_reader_view.dart`／`pdf_reader_view.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`nav_zone_settings_screen.dart`／`reader_screen.dart`／`settings_screen.dart`）仍有 `Colors.grey`／`Colors.black45`／`Colors.white70` 等寫死顏色。Discovery 見 `design.md`。下一步：Architecting（`spec.md` 定義 `ElinkTokens` 精確欄位與 `resolveThemeData()` 銜接方式），再進 Scrum Master 階段拆 `issues.md`。

2026-09-02 `design.md` 經 `/superpowers:requesting-code-review` 審查（`reviews/review-design.md`），逐條核對原始碼後確認 2 項 Critical、5 項 Important、4 項 Minor 皆屬實，已全數修訂：補上 Dark 主題 `outline`／`surfaceContainerHighest` 兩色跟 `DESIGN.md` 表格值直接衝突的既有真機電子紙硬體實測值＋既有測試斷言（新增「已知風險」段落，留給 Architecting 定論，不在 Discovery 階段先下結論）；寫死顏色清單從 8 個補到至少 13 個檔案（含 `highlight_style.dart` 螢光色、`notes_bottom_sheet.dart`／`library_group_management_dialog.dart` 的 `Colors.red`、`pdf_crop_frame_overlay.dart`、候選排除的 `txt_cover_generator.dart`）；修正 `_buildDarkTheme()` 角色數描述錯誤（5 個非 4 個）；補上 `scaffoldBackgroundColor`／`_buildEinkTheme()` 的 `splashFactory`/`hoverColor`/`highlightColor`／`secondary`/`onSecondary`／`cardColor`/`dividerColor` 等原本遺漏的既有客製；`settings_screen.dart` 的 E-Ink 鎖定視覺手法（`Opacity(0.4)`）從「建議改」訂正為「已違反 `DESIGN.md` §17.2 明文規則，必須改」。
