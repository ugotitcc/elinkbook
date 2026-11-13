# `epic-68-heading-font` 標題字型：書籍可分別選定主字型（內文）與標題字型

**狀態：** 🟢 已歸檔 (Archived)
**存放路徑：** `docs/archive/2026-11-14-epic-68-heading-font/`
**關聯 PRD 章節：** 版面與排版（內建字型／自訂字型、版面控制項）；關聯 `epic-3-fonts-layout`、`epic-49-downloadable-fonts`（可下載字型）、`epic-28-reader-settings-enhancements`（版面設定預設集）

## 背景

使用者提出（2026-11-14）：一本書可以選定兩種字型，一個是主字型（內容），一個是輔助字型（標題）。

事實盤點（已核對程式）：

- 字型目前只有一個欄位 `BookReaderPrefs.fontFamily`（單一字串，單書偏好，`book_reader_prefs` 表），**沒有全域預設**（`reader_prefs_manager_impl.dart` 直接取 `book.fontFamily`）。
- `main.js` 的 `buildOverrideCss` 以同一個 selector（`body, p, div, li, span, … h1–h6`；停用書本 CSS 時為 `*`）把字型套用到全部文字，標題與內文沒有區分。
- 字型清單（內建可下載字型＋自訂字型）、「可用字型」退回規則（`AvailableFonts.effectiveFamily`）、版面預設集（`prefs_json`）都已存在。
- 刪除自訂字型走 `CustomFontsRepository.deleteAndResetUsage`／`countBooksUsing`，目前只處理 `font_family`。
- 主庫 `version` 目前為 29。

Discovery 決策見同目錄 `design.md`。

## 進度

- Discovery 已定案（2026-11-14），`design.md` 已寫。
- 已拆 4 個 Issue（見 `issues.md`）。
- Issue 1 完成（待 PR）：`heading_font_family` 欄位、主庫遷移 29→30、`BookReaderPrefs.headingFontFamily`、`ResolvedPreferences` 直取單書值、書架版面覆寫／`FxlSettingsSheet`／`ReaderSettingsSheet` 整列重建守衛、版面預設集往返。同步更新的既有斷言：`book_reader_prefs_test` 欄位數（`toMap` 36、流式保留 23）、三個 `getVersion` 測試檔（`sqlite_library_repository_test`、`daily_reading_stats_schema_test`、`dictionary_database_test`）改 30。本張未觸及 Key／字串，未跑 `check_integration_keys`／`check_l10n_hardcoded_strings`。
- Issue 2 完成（待 PR）：`FoliateReaderView.headingFontFamily`、map／changed、`ReaderScreen` 傳遞（排除 FXL、CBZ 含舊資料、宣告 null 偵測為 FXL）、`main.js` 標題規則（含後代、排在主字型規則之後）、`legacy/` 重建與內容守衛、harness 場景 `scenario-heading-font.mjs`（無 `main.js` 修改時 A2／B／C2／D 失敗已驗證）。本張無 UI，真實 EPUB 目視確認在 Issue 3；既有 `firstLineIndent` 傳遞條件有同樣的舊資料 CBZ 缺口，未於本張處理（另案評估，依慣例併入相關未歸檔 Epic 的後續項目）。本機 pnpm 11 的 `pnpm install` 會因 esbuild build script 報 `ERR_PNPM_IGNORED_BUILDS` 並產生 `pnpm-workspace.yaml`，改以 `node build.mjs`（即 `pnpm build` 的實際指令）重建，並刪除該暫生檔。
- Issue 3 完成（待 PR）：`ReaderSettingsSheet` 標題字型下拉（`reader_settings_heading_font_family`，選項與主字型共用、第一項「跟隨主字型」＝null、不可用時顯示跟隨且不改寫偏好）、主字型標籤改「主字型」、四份 arb 與產生檔、FXL／PDF 負向測試、端到端測試、目視確認報告 `reports/issue-3-report.md`（因無法互動操作桌面 App，目視確認標「未完成」，以 harness 與 widget 測試為替代證據）；書架「版面覆寫」面板與版面預設集畫面無字型控制項，不需標題字型下拉。面板高度實測 988（新增前後不變）。
- Issue 4 完成（待 PR）：刪除自訂字型連動：`countBooksUsing` 數『主字型或標題字型用到該字型』的書（每本一次）、`deleteAndResetUsage` 兩條條件式 UPDATE 只清命中欄位（反向驗證：合併成一條會讓測試轉紅）、`FakeCustomFontsRepository` 只更新註解、對話框書數端到端測試（真實 SQLite）；對話框文案不改（『改用預設字型』對僅作標題字型的書略不精確，待人類確認是否調整）；可下載字型刪除（ADR 0035）不碰偏好、Windows 同一條路徑，皆無需處理。完整 `flutter test`（2026-11-14）：5253 個通過、2 個略過、0 失敗。
- Epic 全數完成，待歸檔。PR 前待辦：Issue 3 目視確認（見 `reports/issue-3-report.md`）。
