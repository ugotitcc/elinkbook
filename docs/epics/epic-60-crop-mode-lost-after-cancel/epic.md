# `epic-60-crop-mode-lost-after-cancel` （缺陷）PDF 手動裁切按 ✕ 取消後，裁切模式按鈕全部沒有反白

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-60-crop-mode-lost-after-cancel/`
**關聯 PRD 章節：** PDF 裁切（手動選區裁切）；來源：`epic-58-pdf-crop-drag-select` 電子紙真機驗證的附帶觀察

## 背景

2026-10-04 在電子紙（Mobiscribe WAVE，debug 版）驗證 Epic 58 時發現：進入「版面設定 → 裁切 → 手動」後，在框選畫面按 ✕ 取消，再打開「版面設定 → 裁切」，「不裁／智慧／手動」三個按鈕**都沒有反白**；再點任一按鈕才恢復。預期應回到進入手動裁切前的模式。

## 已知事實

- 在已有裁切的書上進入手動裁切、按 ✕ 取消後出現（本次觀察的書原本為手動裁切）。
- 點「不裁」後按鈕正常反白，之後也能正常切換雙頁。
- **尚未確認**：取消前是「不裁」時是否也會發生；是否為 UI 狀態未還原，或實際 `pdfCropMode` 已被改成其他值；Epic 58 之前是否就有。

## 診斷結果（2026-10-04，讀程式＋既有測試，未改任何程式）

**與 ✕ 取消無關。** 只要書目前的裁切模式已是「手動」，裁切分頁的三個按鈕就一定全不反白：

- `pdf_settings_sheet.dart:502-509`：「手動」按鈕用 `EBOptionChipItem.onTap` 承載（它是「進入框選互動」的動作鈕，不是可選值）。
- `eb_option_chip_group.dart:92`：`forceUnselected: isAction`，動作鈕恆為未選中。
- 「不裁」「智慧」的 `value` 與 `groupValue`（`_cropMode == manual`）不相等，也不反白。
- 既有測試 `pdf_settings_sheet_test.dart:1090-1111`「情境二」**刻意**斷言：`pdfCropMode == manual` 時，「手動」按鈕仍須維持未選中（當時是為了防止誤用 `value == groupValue`）。

對照真機經過：Epic 58 驗證時，我已先套用過一次手動裁切（模式存成 manual），之後才打開裁切分頁，看到全不反白；點「不裁」後模式變 none，「不裁」才反白。✕ 只是剛好在中間，並非原因。

**所以這是一個設計取捨造成的使用者體驗缺口，不是回歸**：使用者在已套用手動裁切的書上，看不出目前是「手動」模式。

## 待決定（需要人類）

要不要讓「手動」在目前模式為 manual 時顯示反白？這會推翻既有測試「情境二」的設計意圖，需明確同意：

1. **A：模式為 manual 時，「手動」反白；點擊仍是進入重新框選。** 反白代表「目前模式」，點擊代表「重新框選」，語意略重疊。
2. **B：不反白，但在按鈕旁或下方顯示「目前：手動裁切」文字提示。** 不碰既有測試，多一行字串（4 個 arb）。
3. **C：維持現狀，關閉此 Epic。**

## 決定（2026-10-04，人類選 A）

模式為 manual 時「手動」按鈕反白；點擊仍是進入重新框選（仍只呼叫 `onRequestManualCrop`，不呼叫 `onChanged`）。

## 處理方式

缺陷修復，先以 `/diagnose` 建立可重現的回饋迴圈（widget test 優先），再直接 TDD，不寫 `plan-issue-N.md`；保留程式審查（報告存 `reviews/`，不進版控）。

## 開發記錄

**2026-10-04** 登錄 Epic，根因尚未查。

**2026-10-04 實作（直接 TDD）**

- 紅燈：改寫 `app/test/screens/pdf_settings_sheet_test.dart`「裁切模式群組選中態機制」情境二，期望 `pdfCropMode == manual` 時「手動」為 primary 色、「不裁」「智慧」為 surface 色；新增「已是手動時再點仍觸發 `onRequestManualCrop` 且不呼叫 `onChanged`」。實跑：期望 primary、實際 surface。
- 實作：`EBOptionChipItem` 新增 `highlightWhenCurrent`（預設 false，只對動作型項目有效）；`EBOptionChipGroup` 的 `forceUnselected` 改為 `isAction && !item.highlightWhenCurrent`；`PdfSettingsSheet` 的「手動」項目傳 `highlightWhenCurrent: true`。其他使用者不受影響（目前只有裁切分頁有動作型項目）。
- 新增 `eb_option_chip_group_test.dart` 元件層案例。
- **發現舊測試缺陷**：原情境二連續兩次 `pumpWidget` 同型別 widget，Flutter 重用舊 State，`_cropMode` 只在 `initState` 讀取而停在情境一的 autoDetect，所以舊情境二其實沒測到 manual（「手動」恆未選中，兩種情況都通過）。改為兩次之間先 `pumpWidget(SizedBox())` 清空。
- 變異檢查：把 `highlightWhenCurrent: true` 改回 false → 1 個案例失敗；還原後全過。
- 驗證：`flutter analyze` 乾淨；`eb_option_chip_group_test`＋`pdf_settings_sheet_test`＋`reader_screen_test` 共 358 項通過；l10n 雙檢查 PASS。全套 `flutter test` 與程式審查尚未執行（發 PR 前補）。

**2026-10-04 電子紙真機驗證**（WAVE，`一本萬利`，已套用手動裁切）

- 開「版面設定 → 裁切」：「手動」反白、「不裁」「智慧」未反白（修復前為三顆全不反白）。
- 再點「手動」→ 進入框選（有提示、✓ 灰色）；按 ✕ 取消 → 重開裁切分頁，「手動」仍反白（按鈕底色取樣：不裁 255／智慧 255／手動 0）。

**2026-10-04 程式審查修訂**（`reviews/review-code.md`：0 Critical／0 Important／4 Minor，結論可合併）

- **M-1 成立，已修**：`pdf_settings_sheet.dart` 區塊註解「天生強制」改為「預設強制」並註明 epic-60 例外；`EBOptionChipItem` class doc「恆為未選中」改為「預設為未選中（例外見 `highlightWhenCurrent`）」。
- **M-2 成立，已補**：新增「manual 時點『不裁』→ 反白移轉、`onChanged` 帶 `pdfCropMode=none`、`pdfCropRect` 保留」案例。
- **M-3 成立，已補**：新增 E-Ink 主題下「手動」黑底、其餘兩顆白底案例。
- **M-4 不改程式，只記錄**：反白正確的前提是「點『手動』一定先 `Navigator.pop` 關閉面板」（`reader_screen.dart:848-851`），所以 `_cropMode` 只在 `initState` 讀取不會與畫面不同步。**日後若面板改成點擊後不關閉，反白會失準**，屆時需改為在 `didUpdateWidget` 同步 `_cropMode`。
- 變異檢查：把 `highlightWhenCurrent: true` 改為 false → 3 個案例失敗（情境二、M-2、M-3）；還原後全過。
- 驗證：`flutter analyze` 乾淨；`eb_option_chip_group_test`＋`pdf_settings_sheet_test`＋`reader_screen_test` 共 360 項通過；l10n 雙檢查 PASS。全套 `flutter test` 於審查前已跑（3639 通過、1 略過、0 失敗）；審查修訂只動註解與測試。

**2026-10-04 PR 合併**

- PR #322（`epic-60/crop-manual-highlight` → `main`）已合併，合併 commit `d4cc8e15`。實作、電子紙真機驗證與程式審查全數完成，待歸檔。
