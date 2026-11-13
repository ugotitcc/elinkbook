# `epic-68-heading-font` Issues

| Issue | 內容 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 資料層：欄位、遷移、整列重建守衛 | — | 完成（待 PR） | — |
| 2 | 渲染層：標題字型套用（含 legacy） | 1 | 完成（待 PR） | — |
| 3 | 設定面板下拉與 l10n | 1、2 | 完成（待 PR；目視確認未完成） | — |
| 4 | 刪除自訂字型連動 | 1 | 完成（待 PR） | — |

四張並非嚴格垂直切片：Issue 1、2 對使用者不可見，Issue 3 起才可操作；各自單獨合併後 App 皆可編譯、既有行為不變。Issue 4 只依賴 Issue 1，可與 2、3 並行，但本 Epic 依序執行。每張 Issue 一個 commit 系列，同分支 `feat/epic-68-heading-font`、最後同一個 PR；計畫存 `plans/plan-issue-N.md`。標籤：`ready-for-agent`。四張皆完成，Epic 全數完成，待歸檔（Issue 3 目視確認未完成，PR 前須人工補）。

## Issue 1：資料層——`heading_font_family` 欄位與整列重建守衛

**範圍**（spec §1、§6）：主庫 `version` 29→30；`_createBookReaderPrefsTable` 含新欄位；`_addHeadingFontFamilyColumn` 遷移（`oldVersion >= 2` 分支內）；`BookReaderPrefs.headingFontFamily`（建構子／`toMap`／`fromMap`／`==`／`hashCode`／`copyWith`／`reflowableEpubFields()`）；`ResolvedPreferences.headingFontFamily` 與 `reader_prefs_manager_impl.dart` 直取 `book.headingFontFamily`；整列重建處（`library_screen.dart` 書架版面覆寫、`fxl_settings_sheet.dart`）帶入既有值；`reader_settings_sheet.dart` 的 `_currentDraft`／`initState`／`didUpdateWidget` 先把欄位帶進草稿（不加 UI）。

**驗收與單元測試要求**：
- `test/library/sqlite_library_repository_test.dart` 與 `test/stats/daily_reading_stats_schema_test.dart`（約 36、109 行）：全部硬編 29 改 30（以 `grep -rn "29" test/` 搜尋 version 斷言避免遺漏）；新增 28→30、1→30、29→30 遷移案例；新裝置建表含欄位；舊列讀回 `NULL`。
- `book_reader_prefs_test.dart`：`toMap`／`fromMap` 往返、缺 key 讀為 null、`==`／`hashCode`、`copyWith` 保留值、`reflowableEpubFields()` 含新欄位（計數 22→23、12 個過濾斷言同步）；`test/support/full_book_reader_prefs.dart` 種子補欄位。
- 版面預設集：舊 `prefs_json` 缺 key 讀為 null；存／套用往返保留標題字型。
- 整列重建守衛：`library_screen`（書架版面覆寫儲存）、`fxl_settings_sheet`、`reader_settings_sheet` 儲存各一個「標題字型不被清空」測試。
- `resolved_preferences_test`／`reader_prefs_manager_test`：標題字型直取單書值、無全域預設。
- `flutter analyze` 乾淨；只跑觸及的測試檔。

## Issue 2：渲染層——標題字型套用到閱讀器

**範圍**（spec §2、§3）：`FoliateReaderView.headingFontFamily`、`buildFoliatePreferencesMap`、`foliatePreferencesChanged`；`reader_screen.dart` 傳遞（流式才傳，排除 FXL／CBZ，含舊資料 CBZ）；`foliate/main.js` `buildOverrideCss` 標題規則（含後代、排在主字型規則之後）；於 `app/tool/foliate_legacy` 跑 `pnpm build` 重新產生 `foliate/legacy/` 並一併 commit。

**驗收與單元測試要求**：
- `foliate_reader_view` 相關測試：map 含／不含 `headingFontFamily`；`foliatePreferencesChanged` 在僅標題字型變動時為 true。
- `reader_screen` 測試：流式書傳 `effectiveFamily` 結果；標題字型不可用傳 null；FXL、CBZ（含 `isFixedLayout` 宣告為 null 的舊資料）傳 null。
- `foliate_touch_harness` 場景（headless Chromium）：`h1`、`h1>span`、`h1>a`、`h2>a>span` 皆套用標題字型；`p`、`span`（非標題）仍為主字型；停用書本 CSS 開啟時標題字型仍勝出；標題字型為空時不輸出規則。
- `foliate_legacy_assets_test.dart` 通過（legacy 與重新產生結果一致）；`node app/tool/check_foliate_es_compat.js` 通過。
- harness 場景新增 `app/tool/foliate_touch_harness/scenario-heading-font.mjs`（命名比照既有 `scenario-*.mjs`，`run-all.mjs` 自動收集）：自製含 `h1>span`、`h1>a`、`h2>a>span` 的最小 EPUB fixture；harness 只比對 computed `font-family`，不載入真實字型；以指令 `node app/tool/foliate_touch_harness/run-all.mjs`（或單跑該場景）執行。
- 環境：Windows 須先將 pnpm 內建 Node 24 前置於 PATH（見 memory `reference_windows-node-via-pnpm`）；`app/tool/foliate_legacy` 無 `node_modules`，先 `pnpm install` 再 `pnpm build`；須在 `main.js` 定稿後才重建 legacy。
- 本 Issue 無 UI，真實 EPUB 目視確認移到 Issue 3。

## Issue 3：UI——設定面板標題字型下拉與 l10n

**範圍**（spec §4）：`ReaderSettingsSheet` 字型卡片新增標題字型下拉（`Key('reader_settings_heading_font_family')`，第一項「跟隨主字型」，目前值 `effectiveFamily(_headingFontFamily)`）；主字型標籤改「主字型」；`FxlSettingsSheet`／`PdfSettingsSheet` 不顯示；l10n：`readerSettingsFollowBodyFontLabel`、`readerSettingsHeadingFontFamilyLabel` 新 key，四份 arb（`app_zh_TW`（樣板）／`app_zh`／`app_zh_CN`／`app_en`），以 `flutter gen-l10n` 重新產生 `app_localizations*.dart`。

**驗收與單元測試要求**：
- `test/screens/reader_settings_sheet_test.dart`：下拉顯示、選擇後 `onChanged` 帶出新值、選「跟隨主字型」回傳 null；標題字型不可用時顯示「跟隨主字型」且不改寫偏好；既有「字型」標籤斷言（以字串 `readerSettingsFontFamilyLabel` 對應文案定位，不依賴行號）依新文案更新；下載提示行為不變。
- `test/l10n/arb_consistency_test.dart` 通過；`node tool/check_l10n_hardcoded_strings.js` 通過；`flutter analyze` 乾淨。
- **真機／桌面目視確認**（Issue 2 移來）：至少一個環境以真實 EPUB 確認選標題字型後章名字型變化、改回「跟隨主字型」恢復、PDF／FXL 面板不出現下拉；回報寫入 `issue-3-report.md`。若 Node 不可用導致 harness 無法執行，須在報告明載並以目視補足。

## Issue 4：刪除自訂字型連動

**範圍**（spec §5）：`CustomFontsRepository.countBooksUsing`／`deleteAndResetUsage` 連動兩欄（兩條條件式 UPDATE）；`FakeCustomFontsRepository`（`test/support/fake_custom_fonts_repository.dart`）同步；刪除確認對話框使用中書籍數。

**驗收與單元測試要求**：
- `test/reader/custom_fonts_repository_test.dart`（實際路徑以 grep 確認）：計數涵蓋主／標題任一使用且同書只算一次；刪除只清命中欄位（標題用該字型、主字型用另一字型 → 主字型不被清）；兩欄都命中同時清；fake 同語意。
- `test/screens/font_management_screen_test.dart`：刪除確認對話框顯示的書數涵蓋標題字型使用者。
- `flutter analyze` 乾淨。
- **全部 Issue 完成後**（本張為最後一張）跑一次完整 `flutter test`；PR 前再確認一次。
