# `epic-57-layout-override-save-drops-fields` （缺陷）書架「版面覆寫」儲存時整列重建漏帶 `textConversionOverride`，會清掉該書的簡繁轉換覆寫

**狀態：** 🟡 開發中 (Active)（尚未開始處理）
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
