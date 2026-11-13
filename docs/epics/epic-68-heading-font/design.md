# `epic-68-heading-font` Design：標題字型

Discovery 由 `/grill-with-docs` 定案（2026-11-14）。詞彙已寫入 `CONTEXT.md`（「主字型」「標題字型」）。

## 決策

1. **新 Epic**：這是新功能，三個開發中 Epic（`epic-54`、`epic-62`、`epic-66`）皆不相關；不併入。
2. **用語**：「主字型（Body Font）」與「標題字型（Heading Font）」。「輔助字型」列為 _Avoid_，因為容易被理解成「缺字時的備援字型」。
3. **標題範圍**：只套 `h1`–`h6`（**含其後代元素**：selector 為 `h1, h1 *, … h6, h6 *`，因為主字型規則直接指定在 `span`／`a` 上，標題內層的 `<span>` 會蓋掉外層標題字型），不用啟發式猜章名（許多書的章名寫在 `p`／`div`＋自訂 class，不會被認成標題）。TXT／MD 由匯入時合成，章節標題本來就是 `h*`，自然適用。
4. **適用格式**：EPUB／KF8／TXT／MD；PDF、FXL、CBZ 不適用（比照現有字型設定）。
5. **預設**：「跟隨主字型」，儲存為 `NULL`；舊書行為與現在完全相同，不需回填。
6. **作用範圍**：只有單書偏好，不新增全域預設（現有主字型本來就沒有）。
7. **版面預設集**：快照包含標題字型。舊預設集 `prefs_json` 讀不到此欄位時視為 `NULL`（比照 `epic-65` 的作法）。
8. **不可用時的退回**：標題字型不在「可用字型」中時，退回**主字型實際生效的字型**（不是書本字型），且不改寫偏好；字型之後變成可用就自然恢復。實作上只在標題字型「可用」時才輸出標題規則，否則不輸出（沿用主字型規則）；因此主字型為「使用書本字型」時，標題退回的也是書本字型。
9. **字重**：沿用同一個字重滑桿（現行 selector 本來就含 `h1`–`h6`），不新增標題字重。
10. **UI**：在 `ReaderSettingsSheet` 現有「字型」卡片內，主字型下拉選單下方新增「標題字型」下拉選單；選項清單與主字型共用（內建、自訂、下載提示）；第一項為「跟隨主字型」（主字型的第一項仍是「使用書本字型」）。
11. **刪除自訂字型**：`deleteAndResetUsage` 同時把 `font_family` 與 `heading_font_family` 重置為 `NULL`；`countBooksUsing` 改數「主字型或標題字型用到該字型的書」，每本只算一次。
12. **資料表**：`book_reader_prefs` 新增可為空 `heading_font_family TEXT`；主庫 `version` 29→30，遷移只做 `ADD COLUMN`。新欄位須同時加進 `_createBookReaderPrefsTable`（新裝置建表路徑），遷移區塊放在 `oldVersion >= 2` 分支內並先檢查表存在（比照 `_addFirstLineIndentColumn`）。
13. **ADR**：不開。新增可為空欄位，可逆、不意外，不符合 ADR 三條件。
14. **legacy 降級副本**：修改 `foliate/main.js` 後須在 `app/tool/foliate_legacy` 跑 `pnpm build` 重新產生 `foliate/legacy/` 並一併 commit（ADR 0043），並確認降級輸出含標題規則。
15. **整列重建守衛**：`BookReaderPrefs` 整列重建處不得漏帶新欄位（`epic-57` 前車之鑑），範圍：`toMap`／`fromMap`／`==`／`hashCode`／`copyWith`／`reflowableEpubFields()`、`library_screen.dart` 書架版面覆寫儲存、`fxl_settings_sheet.dart`、`reader_settings_sheet.dart` 草稿與重置、測試種子 `full_book_reader_prefs.dart` 與欄位計數斷言。
16. **刪除字型 SQL**：重置用兩條條件式 UPDATE（各自只清命中欄位），不可一條同時清兩欄；計數用 `WHERE font_family = ? OR heading_font_family = ?`。
17. **流程**：計畫與實作同分支同 PR，不另開文件 PR。

## 預計 Issue 切分（待 Scrum Master 階段定稿）

1. 資料層：遷移 29→30（含建表路徑、跳級測試）、`BookReaderPrefs` 全部整列重建處與守衛測試、`ResolvedPreferences`／`reader_prefs_manager_impl`。
2. 渲染層：`foliate_reader_view.dart`（map、`foliatePreferencesChanged`、欄位與建構子）、`reader_screen.dart` 傳遞、`main.js` 標題規則（含後代）、重生 `legacy/`。
3. UI 與連動：設定面板下拉（只在流式 Foliate 面板顯示，FXL／PDF 不顯示）、刪除自訂字型的重置與計數（含 fake repository）、l10n 三語系。

## 已由 Design 審查答覆（原「留待實作時確認」）

- 停用書本 CSS（`*`，特異度 0）敗給 `h1`（0,0,1），標題規則勝出，不需額外處理。
- 版面預設集 `prefs_json` 走 `toMap/fromMap`，舊資料缺欄位天然為 `NULL`，只需補測試，無 schema 版本、不需遷移。
- 設定面板下拉目前值沿用 `effectiveFamily(_headingFontFamily)`，不可用時顯示「跟隨主字型」。
- 測試：`h1>span`、`h1>a`、`h2>a>span` 以 `foliate_touch_harness` 場景驗證；刪除字型連動、遷移 30、跳級遷移、不可用字型退回。
