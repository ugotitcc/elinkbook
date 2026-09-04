# Epic 35 Issue 7 — 最終整分支審查報告

**審查範圍：** commit `150727dd..cfb4c82b`（`fccd62ae`／`bb5a0624`／`cfb4c82b` 三個 commit，對應 Task 1／2／3）
**審查者：** Claude Opus（subagent-driven-development 最終整分支審查）
**審查日期：** 2026-09-04

## Strengths

- 範圍紀律極佳：`pdf_crop_frame_overlay.dart`、`reader_option_tile.dart` 及其三個呼叫端（`reader_settings_sheet.dart`／`pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`）完全沒有出現在檔案清單中，`app/lib/theme/` 目錄零 commit。`issues.md` 明文授權的兩項排除確實維持不動。
- Task 3「一併遷移」決策三處全數落地，無漏改：`_buildDragIndicator()`、`_buildDecorationWidget()`、`_buildSearchHighlightWidget()` 逐一核實皆已改讀 `ColorScheme`／`ElinkTokens`。
- 驗收標準「兩檔內無寫死顏色殘留」已達成：`grep` 掃描剩餘命中全部落在中文註解裡（描述沿革），程式碼路徑零殘留。
- 顏色角色白名單全程遵守：跨三個 commit 掃描 `tertiary|secondary` 零命中；實際使用的 `primary`／`onSurface` 四套主題皆明確賦值，不會落回 M3 種子色。
- `ElinkTokens` 欄位數確實不變（仍 11 欄位，該檔案本分支零 commit）。
- 透明度數值忠實對應原字面值（`Colors.white24`≈0.24、`Colors.white70`=0.7）。
- `Theme.of(context).extension<ElinkTokens>()!` 寫法符合既有慣例（專案內另有 7 處同寫法），崩潰面已由測試腳手架補丁完整封堵。
- 三個 commit message 格式一致、trailer 齊備；工作樹乾淨。

## Issues

### Critical (Must Fix)
無。

### Important (Should Fix)

**I1. 計劃書「全部 Task 完成後」的文件收尾項尚未落地，`plan-issue-7.md` 本身也未進版控。**
`issues.md` Issue 7 Status 仍是 `ready-for-agent`；`docs/epics.md` 未補開發記錄；「原草案曾主張排除 3 處、經審查與人類確認後改為一併遷移」的決策沿革尚未寫進 `issues.md`；兩項人工待辦尚無正式落點；`plan-issue-7.md` 與 `reviews/` 目錄皆未進版控（與前 6 份計劃書慣例不一致）。

**處理：** 已於本次收尾一併補上（見下方「處理結果」）。

### Minor (Nice to Have)

**M1.** `_buildSearchHighlightWidget()` 的 dartdoc（`pdf_reader_view.dart:1116-1121` 一帶）仍寫「半透明橙色／黃色」，與現行 `highlightGreen`／`highlightYellow` 字面用詞脫節，設計原則本身未變，僅描述用詞需更新。**處理：** 已一併修正。

**M2.** 新增測試的主題腳手架寫法不一致（Task 3 搜尋高亮測試用 `resolveThemeData`，其餘用裸 `MaterialApp`），且沒有任何測試直接證明同一顏色在不同主題下確實會換值。不影響正確性，留待本 Epic 收尾時統一處理，不為此另開一輪 TDD。

**M3.** E-Ink／Sepia 主題下搜尋高亮的視覺後果（E-Ink 純黑灰罩、Sepia `highlightGreen` 比 `highlightYellow` 更淡造成顯著度反轉）建議併入真機驗證待辦清單。已併入下方待辦清單。

**M4.** PDF 端除錯疊層在 Dark 主題下對比仍偏低（PDF 頁面恆為白紙、不隨主題變色）——相對原本「四套主題下全都看不見」是嚴格改善，非回歸；預設關閉的除錯功能，實務影響低，供真機驗證清單參考。已併入下方待辦清單。

## Recommendations

1. 合併前補一個 docs commit：更新 `issues.md` Issue 7 Status＋決策沿革、`docs/epics.md` 開發記錄，並把 `plan-issue-7.md` 與本審查報告一併納入版控。（已完成）
2. 順手修 M1 過時 dartdoc。（已完成）
3. M3／M4 不在本 Issue 展開修復，寫進真機驗證待辦（比照 Issue 6 先例）。（已完成）
4. M2 留到本 Epic 收尾時統一處理。

## Assessment

**Ready to merge?** With fixes（I1 文件收尾＋M1 dartdoc 已於本次收尾一併處理，處理後視為 Ready to merge）

**Reasoning：** 程式碼面完全乾淨——範圍零外洩、白名單零違規、Task 3 三處全數落地、`ElinkTokens` 11 欄位未動、`!` 崩潰面已由主題腳手架完整封堵，配合 1908/1908 測試通過與 `flutter analyze` 乾淨。唯一待補的是文件收尾動作，不影響程式碼正確性。
