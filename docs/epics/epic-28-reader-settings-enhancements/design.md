# Epic 28 — 閱讀器設定強化：Discovery

## 背景

2026-08-13 使用者提出三項與「版面設定」相關的功能需求，經 `/brainstorming` 分類後拆為 3 個 Issue：

1. **字距（letter-spacing）選項**——流式 EPUB 版面設定新增一項排版數值控制。
2. **Console Log 可手動關閉**——「閱讀器 Console Log」目前無條件攔截 WebView console 訊息，需要一個開關。
3. **版面設定預設集**——可儲存最多 3 組具名版面設定，並可套用到目前書籍或跨書套用。

Issue 1、2 屬 **bounded**（既有流程加欄位/開關，已在對話中定案，見下方，不另外走 Architecting）；Issue 3 屬 **architectural**（新資料表＋新 Repository＋跨書套用 UI），走完整 Discovery → Architecting 流程，架構細節見 `spec.md`。

三者皆先確認一個關鍵事實：`ReaderSettingsSheet`（流式 EPUB）、`PdfSettingsSheet`（PDF）、`FxlSettingsSheet`（固定版面 EPUB）是三個完全獨立的版面設定畫面（`reader_screen.dart:653/664/674`），不是共用元件。本 Epic 三項需求皆只涉及 `ReaderSettingsSheet`，不影響 PDF／FXL。

## `/grilling` 決策紀錄

### Issue 1：字距選項

- 數值範圍 `-0.05em ~ 1em`，預設 `0`（不覆蓋書本原生字距），step `0.01em`，UI 沿用現有 `_buildSliderRow`（含 +/- 微調按鈕）。
- 橫排／直排（`vertical-rl`）皆套用同一份 CSS 規則，不特別排除——`letter-spacing` 作用於 inline 軸方向，直排下 inline 軸為垂直方向，語意依然合法。
- 完全比照現有 `lineHeight`/`paragraphSpacing` 欄位模式：`BookReaderPrefs`＋`ResolvedPreferences`＋SQLite migration＋`main.js` 的 `buildOverrideCss()` 新增一條 `letter-spacing` CSS 規則，複用既有的廣選擇器。

### Issue 2：Console Log 開關

- 位置：`SettingsScreen`（與「閱讀器 Console Log」入口同一頁）新增一個 `SwitchListTile`。
- 預設**關閉**。
- 開關只控制一般等級（`onConsoleMessage` 回報的 `[LOG]`/`[WARNING]` 等非 ERROR 等級）訊息是否寫入 `ReaderConsoleLog`；**`[ERROR]` 等級（含 WebView 自動鏡射的未捕捉例外）永遠強制記錄，不受開關影響**，保留崩潰診斷能力（`epic-27-reader-device-compat` 的崩潰診斷正是靠這條線索）。
- 關閉當下不清空既有紀錄，只是停止新增一般等級訊息——`ReaderConsoleLog`（`app/lib/reader/reader_console_log.dart`）本來就是純記憶體 `ValueNotifier`，不落地持久化資料庫、App 重啟即清空，且**已有**既有的 500 筆上限與 `ReaderConsoleLogScreen` 的「清空」按鈕（2026-08-14 審查一度誤以為需要新增資料庫成長上限與清除按鈕，經核實現況後澄清不需要新增，見 `spec.md`「審查回應」）。
- 與 `_globalErrorCaptureJs`（`window.onerror`/`window.onunhandledrejection` → `onError` bridge → `reader_screen.dart` 的 `_handleError()`）是完全獨立的另一條管線，本開關不影響它——那是驅動閱讀器錯誤畫面狀態的核心錯誤處理機制，不是「log 功能」。

### Issue 3：版面設定預設集 ＋ 書籍設定複製

- 範圍：僅流式 EPUB（`ReaderSettingsSheet`），PDF/FXL 不適用。
- 預設集內容：`ReaderSettingsSheet` 目前呈現的**全部項目**（含排版數值型欄位，也含方向/翻頁模式/螢幕方向覆寫等），非僅數值型欄位子集——見下方「欄位範圍」精確定義。
- 最多 3 組，使用者可自訂名稱（trim 後 1~20 字元，允許重複名稱，細節見 `spec.md`「命名驗證」）；存滿時跳出選單選擇覆蓋哪一組（顯示名稱＋最後更新時間），覆蓋前二次確認。
- 管理介面（新增/命名/刪除）內嵌在 `ReaderSettingsSheet` 底部新增區塊，不另開畫面。
- 套用來源二選一：
  - ①「從我的預設集」——選一組已存的具名預設集。
  - ②「從其他書籍複製」——直接讀某本來源書籍目前的單書版面偏好設定，不經預設集中介、不受 3 組數量上限限制，一次性書對書操作。兩個方向皆須實作（見下方可行性評估）。
- 套用目標二選一：
  - 「套用到目前書籍」——直接寫入，不需額外確認（比照其他版面設定變更的既有 UX，非破壞性、可隨時再調整）。
  - 「套用到其他書籍」——彈出批次選書清單＋「即將覆蓋 N 本書」確認對話框。
- 書籍選擇器（複製來源／套用目標皆共用）只列出**流式（非 FXL）EPUB** 書籍，排除 PDF/FXL/TXT——欄位語意不共通，避免誤選。

**方向 A（預設集）vs 方向 B（書籍複製）的可行性評估**（回應使用者提問）：兩者共用同一套「讀來源 `BookReaderPrefs` → 寫目標書籍」的底層邏輯，差別只在來源——方向 A 來源是新表的一列，方向 B 來源直接是 `BookReaderPrefsRepository.load(sourceBookId)`。方向 B 事實上比方向 A 更簡單（不需要「命名/3組上限/覆蓋管理」這些狀態），邊際成本低，建議兩者都做、共用同一套「套用到目前書籍/其他書籍」的寫入與選書 UI。

## 欄位範圍（Issue 3 精確定義）

`BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）目前 29 個欄位中，`ReaderSettingsSheet` 實際呈現的子集為：

`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`marginTop`／`marginBottom`／`marginLeft`／`marginRight`／`textAlign`／`publisherStyles`／`showHeader`／`showFooter`／`fullscreen`／`columnMode`／`columnSize`／`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`，加上本 Epic Issue 1 新增的 `letterSpacing`。

**不含**：`pageMargins`（EPUB 舊版單值邊距，僅 `EpubReaderView`/FXL 使用，已被 `marginTop/Bottom/Left/Right` 取代）、6 個 `pdf*` 欄位、3 個 `dualPage*` 欄位——這些欄位在一本流式 EPUB 的 `book_reader_prefs` 列上結構性恆為 `null`（`ReaderSettingsSheet` 從未寫入過），詳見 `spec.md`「儲存格式」對此如何簡化實作的說明。

## 依賴關係

Issue 3 的預設集欄位快照須包含 `letterSpacing`，因此**依賴 Issue 1 先完成**（`BookReaderPrefs` 需先有這個欄位）。Issue 2 與 Issue 1、3 互相獨立。

## 範圍界定

- 涵蓋：流式 EPUB 版面設定新增字距欄位；Console Log 攔截開關（一般等級可關閉、ERROR 等級強制保留）；版面設定預設集（最多 3 組，具名，可套用到目前/其他書籍）；書籍設定直接複製（跨書、無數量上限）。
- 不涵蓋：PDF／FXL 版面設定的字距或預設集（欄位語意不共通，留待未來需求另立 Issue）；Console Log 內容格式或等級分類邏輯本身的變更（僅新增「是否記錄非 ERROR 等級」的開關）；預設集/書籍複製套用到 PDF/FXL 書籍。

## 新詞彙（已記入 `CONTEXT.md`）

「版面設定預設集（Layout Preset）」、「書籍設定複製（Copy Layout From Book）」，與既有「單書版面偏好設定」「全域預設值」的區別已於 `CONTEXT.md` 明確註記，避免混淆。
