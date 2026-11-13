# `epic-57-layout-override-save-drops-fields` （缺陷）書架「版面覆寫」儲存時整列重建漏帶 `textConversionOverride`，會清掉該書的簡繁轉換覆寫

**狀態：** 🟡 開發中 (Active)（已合併，待歸檔）
**存放路徑：** `docs/epics/epic-57-layout-override-save-drops-fields/`
**關聯 PRD 章節：** FR-48 簡繁轉換；關聯已歸檔 `epic-42-text-conversion`

## 背景

`epic-56` Issue 2 程式審查（`epic-56-pdf-paginated-reading/reviews/review-code-issue-2.md`）核對時發現：`app/lib/screens/library_screen.dart` 的版面覆寫對話框 `_save()`（約第 1969～2003 行）以 `BookReaderPrefs(...)` 逐欄位整列重建，**沒有帶 `textConversionOverride`**。使用者在書架對某本書儲存「版面覆寫」（書寫方向／翻頁模式）後，該書原本設定的簡繁轉換覆寫會被靜默清成 null（回到跟隨全域設定）。

此為既有缺陷，與 `epic-56` 無關，不在其範圍內處理。

## 重現（尚未寫成測試）

1. 對某本書設定 `textConversionOverride`（例如簡轉繁）。
2. 書架長按該書 → 版面覆寫 → 儲存。
3. 重新讀取該書的 `BookReaderPrefs`：`textConversionOverride` 變成 null。

## 待辦

- 先寫失敗測試（`test/screens/library_screen_test.dart`，比照 `epic-56` Issue 2 新增的「保留 pdfPageTurnMode」測試），再於 `_save()` 補上 `textConversionOverride: existing.textConversionOverride`。
- 評估是否加一個泛用測試：以欄位比對確認 `_save()`、`fxl_settings_sheet`、`pdf_settings_sheet` 的整列重建不會清空任何 `BookReaderPrefs` 欄位（`epic-56` 程式審查 Recommendations 亦建議），避免日後新增欄位再漏。
- 處理方式（直接 TDD 或走 SDD）待使用者決定。

## 開發記錄

**2026-10-03** 登錄工單。尚未診斷與修正。

**2026-10-03 修正（直接 TDD）**

- 處理方式：使用者選直接 TDD，不寫 `plan-issue-N.md`；保留程式審查。
- 紅燈：`library_screen_test.dart` 新增「版面覆寫：儲存後既有的簡繁轉換覆寫原樣保留（epic-57 回歸）」，修正前 FAIL（`textConversionOverride` 變 null）。
- 修正：`library_screen.dart` `_LayoutOverrideDialog._save()` 補 `textConversionOverride: existing.textConversionOverride`。
- 核對其他整列重建處：`fxl_settings_sheet` 已帶 `textConversionOverride`；`pdf_settings_sheet` 的 `_notifyChanged` 為局部更新（PDF 面板不含該欄位），不屬本缺陷，未更動。
- 驗證：全套 `flutter test` 3472 通過、1 略過、0 失敗；`flutter analyze` 乾淨；l10n 硬編碼字串雙檢查 PASS。
- 程式審查：完成獨立審查（`reviews/review-code.md`），結論 **Ready to merge**（Critical: 0, Important: 0, Minor: 1）。
- 未做：泛用「整列重建不得清空任何欄位」測試（`epic-56` 與 `epic-57` 審查建議），範圍較大，不在本缺陷內；若要做另立 Issue。

**2026-10-03 程式審查與 PR 合併**

- 程式審查：`reviews/review-code.md`，0 Critical／0 Important／1 Minor，結論可合併。M-1（單欄位抽測無法防止未來再漏欄位）不在本缺陷處理，已登錄為 `epic-54-architecture-optimization` Issue 10。
- PR #315（`epic-57/layout-override-save` → `main`）已合併，合併 commit `a8481f2c`。修正全數完成，待歸檔。
