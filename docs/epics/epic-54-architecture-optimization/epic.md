# `epic-54-architecture-optimization` 架構優化

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-54-architecture-optimization/`
**關聯 PRD 章節：** 無（純內部架構重構，不改變使用者可見功能，除 Issue 1 的一處刻意行為調整）
**關聯 ADR：** 0007、0035

## 背景

2026-09-30 `/improve-codebase-architecture` 檢視 epic-45／48／49／50／52／15 產出 7 個深化候選（報告 HTML 存於暫存目錄，不進版控）。候選 1 已由 `epic-53-sync-checkpoint-result` 完成並合併。使用者要求後續架構優化不要每一項各開一個 Epic，**集中在本 Epic，每個候選當作一張 Issue**（見 `issues.md`）。

## Issue 1 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| module 範圍 | `AvailableFonts` 只做純推導，不做 I/O，不含 `@font-face` CSS |
| 不認得的名稱、沒有 store | 統一為 `effectiveFamily() == null`（行為調整：原本渲染端照原值傳，與下拉選單不一致） |
| `ReaderScreen` 狀態 | 4 個欄位換成單一 `AvailableFonts?`，`null` 代表載入中 |
| 命名 | 類別 `AvailableFonts`，檔案 `app/lib/reader/available_fonts.dart`，`CONTEXT.md` 詞條「可用字型」 |
| 既有 interface | `ReaderSettingsSheet` 改吃 `AvailableFonts`；`FoliateReaderView`／`buildFontFaceCss` 不改 |
| 測試 | 規則類搬到純測試；接線類留在 widget 層 |
| 載入失敗 | 任一邊失敗該邊視為空集合，仍組出 `AvailableFonts` |

## Issue 5 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 命名 | 類別 `OpenBookFlow`，檔案 `app/lib/reader/open_book_flow.dart`，`CONTEXT.md` 詞條「開書流程」 |
| 範圍 | 控制器：持有狀態並編排探測與 relink；`l10n`、SnackBar、選檔器、引擎分派（`_resolveEpubEngineDispatch` 重跑）留在 `ReaderScreen` |
| 狀態 | 密封類別 `Loading`／`Probing`／`Rendered`／`Failed(message, probeResult)`／`Relinking`；`Relinking` 期間的視圖錯誤與逾時一律忽略 |
| 通知方式 | 繼承 `ChangeNotifier`，Widget 加 listener 並 `setState`；`dispose()` 取消計時器、捨棄之後才回來的探測結果 |
| 逾時 | module 持有 30 秒計時器，計時來源注入；成功、失敗取消，重開重啟 |
| 注入的依賴 | 探測函式、relink 函式、計時來源；不直接 import `foliate_native_bridge`，與 Issue 4 互不依賴 |
| `relink(picked)` 回傳 | `reopened(newPath)`／`failed(reason)`／`cancelled`；例外一律轉 `failed` |
| 行為調整（唯一一處） | `content://` 書籍開書逾時也做存取探測，與「視圖回報錯誤」路徑一致 |
| 範圍排除 | `font_management_screen` 的探測與重新連結屬 Issue 3；`_pickAndRelink` 在 `importService == null` 回傳 `null` 的到不了路徑不處理 |
| 測試 | 狀態轉移與競態 guard 搬到純測試 `open_book_flow_test.dart`（計時用替身）；`reader_screen_test` 只留接線類，重疊舊測試遷移後刪除並於記錄列出對應；補「relink 後再失敗會重新探測」 |

## 開發記錄

**2026-09-30 登錄 Epic**，分支 `epic-54/issue-1-available-fonts`。實作計畫見 `plans/plan-issue-1.md`。

**2026-09-30 Issue 1 實作完成**：新增 `AvailableFonts` 純值物件（`app/lib/reader/available_fonts.dart`）；`ReaderSettingsSheet` 參數 2→1（`customFonts`／`installedFonts`→`availableFonts`）；`ReaderScreen` 4 個欄位→單一 `AvailableFonts?`（`null`＝載入中），刪除 `_renderedFontFamily`，載入改為 record `.wait` 並行、各自 catch（任一邊失敗視為空集合）。行為調整：偏好為不認得的名稱或沒有 store 時，渲染端改傳 `null`，與設定面板顯示一致（偏好本身不改寫）。測試：純測試 11 個（`available_fonts_test.dart`）；`reader_screen_test` 翻轉 2、刪除 3、新增 2（「一邊載入失敗」「載入中離開畫面」）。驗證：`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS；7 個相關測試檔 622/622 通過（`available_fonts_test` 11、`foliate_native_bridge_test` 28、`foliate_reader_view_test` 117、`reader_settings_sheet_test` 95、`font_management_screen_test` 49、`downloadable_font_store_test` 35、`reader_screen_test` 287；尚未跑完整 `flutter test`）。

**2026-09-30 程式審查與修訂**

- 審查報告：`reviews/review-code-issue-1.md`（不進版控），0 Critical／0 Important／4 Minor，結論 With fixes。
- M-1：`ReaderScreen` 兩個建構參數（`customFontsRepository`、`downloadableFontStore`）的 doc comment 改為符合新行為（沒有 store 時內建字型偏好退回書本字型）。
- M-2：`reader_screen_test.dart` 字型區塊刪除 2 處多餘空行；`reader_settings_sheet_test.dart` 過長自訂字型名稱測試的 `CustomFont(...)` 縮排修正。
- M-3：上方驗證數字補上 7 個檔名與各自數量；reviewer 只得 587 是因為被指定的清單少了第 7 個檔 `downloadable_font_store_test.dart`（35 個），622 可重現。
- M-4：不需動作。
- 「未評判」5 項：均維持不處理；「`FontManagementScreen` 自己持有 `_installedFonts`」是否列為後續待辦由使用者決定。
- 驗證：`flutter analyze` No issues found；上述 7 個檔修訂後重跑 622/622 通過。
- 全套 `flutter test`：3221 個通過（1 個略過）；`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` PASS。準備發 PR。

**2026-09-30 PR 合併**

- PR #302（`epic-54/issue-1-available-fonts` → `main`）已合併。Issue 1 完成。Issue 2～6 尚未設計，動手前各自須先 `/grill-with-docs`；本 Epic 維持開發中，待所有 Issue 完成或決定收尾後再歸檔。
