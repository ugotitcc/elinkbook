# `epic-68-heading-font` 標題字型：書籍可分別選定主字型（內文）與標題字型

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-68-heading-font/`
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
- 尚未拆 Issue（下一步：Scrum Master 階段寫 `issues.md`）。
- Issue 1 完成（待 PR）：`heading_font_family` 欄位、主庫遷移 29→30、`BookReaderPrefs.headingFontFamily`、`ResolvedPreferences` 直取單書值、書架版面覆寫／`FxlSettingsSheet`／`ReaderSettingsSheet` 整列重建守衛、版面預設集往返。同步更新的既有斷言：`book_reader_prefs_test` 欄位數（`toMap` 36、流式保留 23）、三個 `getVersion` 測試檔（`sqlite_library_repository_test`、`daily_reading_stats_schema_test`、`dictionary_database_test`）改 30。本張未觸及 Key／字串，未跑 `check_integration_keys`／`check_l10n_hardcoded_strings`。
