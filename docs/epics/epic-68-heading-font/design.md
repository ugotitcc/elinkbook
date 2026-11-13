# `epic-68-heading-font` Design：標題字型

Discovery 由 `/grill-with-docs` 定案（2026-11-14）。詞彙已寫入 `CONTEXT.md`（「主字型」「標題字型」）。

## 決策

1. **新 Epic**：這是新功能，三個開發中 Epic（`epic-54`、`epic-62`、`epic-66`）皆不相關；不併入。
2. **用語**：「主字型（Body Font）」與「標題字型（Heading Font）」。「輔助字型」列為 _Avoid_，因為容易被理解成「缺字時的備援字型」。
3. **標題範圍**：只套 `h1`–`h6`，不用啟發式猜章名（許多書的章名寫在 `p`／`div`＋自訂 class，不會被認成標題）。TXT／MD 由匯入時合成，章節標題本來就是 `h*`，自然適用。
4. **適用格式**：EPUB／KF8／TXT／MD；PDF、FXL、CBZ 不適用（比照現有字型設定）。
5. **預設**：「跟隨主字型」，儲存為 `NULL`；舊書行為與現在完全相同，不需回填。
6. **作用範圍**：只有單書偏好，不新增全域預設（現有主字型本來就沒有）。
7. **版面預設集**：快照包含標題字型。舊預設集 `prefs_json` 讀不到此欄位時視為 `NULL`（比照 `epic-65` 的作法）。
8. **不可用時的退回**：標題字型不在「可用字型」中時，退回**主字型實際生效的字型**（不是書本字型），且不改寫偏好；字型之後變成可用就自然恢復。
9. **字重**：沿用同一個字重滑桿（現行 selector 本來就含 `h1`–`h6`），不新增標題字重。
10. **UI**：在 `ReaderSettingsSheet` 現有「字型」卡片內，主字型下拉選單下方新增「標題字型」下拉選單；選項清單與主字型共用（內建、自訂、下載提示）；第一項為「跟隨主字型」（主字型的第一項仍是「使用書本字型」）。
11. **刪除自訂字型**：`deleteAndResetUsage` 同時把 `font_family` 與 `heading_font_family` 重置為 `NULL`；`countBooksUsing` 改數「主字型或標題字型用到該字型的書」，每本只算一次。
12. **資料表**：`book_reader_prefs` 新增可為空 `heading_font_family TEXT`；主庫 `version` 29→30，遷移只做 `ADD COLUMN`。
13. **ADR**：不開。新增可為空欄位，可逆、不意外，不符合 ADR 三條件。
14. **流程**：計畫與實作同分支同 PR，不另開文件 PR。

## 預計 Issue 切分（待 Scrum Master 階段定稿）

1. 資料層：版本 29→30 遷移、`BookReaderPrefs`／`ResolvedPreferences` 欄位、版面預設集快照帶欄位。
2. 渲染層：`foliate_reader_view.dart` 傳遞、`main.js` `buildOverrideCss` 加 `h1–h6` 字型規則、退回邏輯（`effectiveFamily` 的標題版）。
3. UI 與連動：設定面板下拉選單、刪除自訂字型的重置與計數、l10n 字串（三語系）。

## 留待實作時確認（不需再問使用者）

- 「停用書本 CSS」開關下（selector 為 `*`），標題字型規則的優先序是否勝過 `*` 規則。
- 版面預設集 `prefs_json` 的實際讀寫位置與舊資料相容測試。
- 測試範圍：遷移 30、刪除字型連動、不可用字型退回、`h1–h6` 實際套用（headless Chromium 驗證，比照既有 `foliate_touch_harness` 作法）。
