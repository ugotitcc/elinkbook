# ADR 0004：`EpubReaderView` 契約擴充為換頁模式（分頁 vs 捲動）＋偏好設定合併修正

## 狀態

已採納

## 背景

Issue 3 的實機驗證與根因調查（見 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`）確認：直排（vertical-RL）閱讀模式下，Readium 內建的 `cjk-vertical` ReadiumCSS 把每一欄（頁）的高度設為 CSS `100vh`、未對齊行高整數倍，可能導致分頁模式下畫面上下緣文字被裁切，此為 Readium/CSS 多欄分頁機制在直排書寫模式下的已知上游限制（`readium/swift-toolkit#804`、`readium/readium-css#141`），並非本專案程式碼缺陷，因此無法透過本專案自行維護的 user stylesheet 覆寫徹底修復。Issue 3 Task 5 已驗證 `EpubPreferences(scroll = true)` 可行（改用連續捲動渲染，不涉及欄位高度概念，未觀察到裁切）。

同時，ADR 0003／Issue 1 建立的 `setWritingMode` 實作有一個已知、當時刻意延後處理的技術債（見 `EpubReaderView.kt` 原始碼註解）：每次呼叫都建構全新的 `EpubPreferences`，只有當時要設定的那個欄位有值，其餘欄位一律為預設 `null`。這在只有一種偏好維度（`verticalText`）時不會出問題，但本 issue 引入第二種偏好維度（`scroll`）後，若不修正，切換橫直排會把使用者已設定的捲動偏好重設回分頁（反之亦然），這是一個會實際發生的回歸缺陷，必須與換頁模式功能一併修正。

## 決策

- **Dart → 原生**：新增 `setPageTurnMode(mode: paginated | scroll)`，可在書本開啟後任何時間點呼叫，語意與 ADR 0003 的 `setWritingMode` 完全對稱。
- **原生端**：`EpubReaderView.kt` 新增 `currentPreferences: EpubPreferences` 欄位（初始為 `EpubPreferences()` 全預設值），`setWritingMode`／`setPageTurnMode` 皆改為「用 `EpubPreferences.plus()` 把新的單一欄位設定合併進 `currentPreferences`，再送出合併後的完整物件」，而不是各自建構獨立物件覆蓋。
- **初次開書**：不主動設定 `scroll`（保持 `null`），沿用 Readium 預設值（分頁），對應「不改變既有使用者預設體驗」的產品決策；`setPageTurnMode` 只在使用者手動切換時才會覆寫。
- `openBook`/`onPageRendered`/`onError`/`setWritingMode`（對外行為）既有契約簽章不變。

【未來注意，供 `epic-3-fonts-layout` 設計持久化時參考】`ReaderScreen` 的 `_pageTurnMode` 目前永遠從 `PageTurnMode.paginated` 開始，與原生端 `currentPreferences` 的預設值一致，因此 `didUpdateWidget` 的「值改變才呼叫」邏輯不會漏發送。但若未來持久化功能改成「App 啟動時直接把 `_pageTurnMode` 初始化為使用者上次選擇的值」，且該值恰好也是 `PageTurnMode.paginated`（例如使用者上次就是選分頁），仍然不會有問題；唯有當持久化值與目前寫死的初始值"剛好在某次重建間不變化"時才可能發生「初始值正確但從未真正送達原生端」的情況——這種情況目前的 `didUpdateWidget`-only 設計無法涵蓋，需要屆時額外設計「開書當下就帶入已持久化偏好」的機制（例如擴充 `openBook` 契約或在 `attachNavigator` 時代入 `initialPreferences`）。本 issue 範圍內沒有持久化功能，不需要現在解決，僅記錄於此避免日後被遺忘。

## 後果

- `EpubReaderView.kt` 的 `setWritingMode` 實作方式改變（改為合併而非覆蓋），但對外行為不變（單獨呼叫 `setWritingMode` 的效果與修正前相同）。
- 修正後，`setWritingMode` 與 `setPageTurnMode` 可以任意順序、任意次數交錯呼叫，彼此不會互相重設對方已生效的偏好——這是本次修正要達成的核心後果。
- Dart 端 `EpubReaderView` widget 新增對稱的 `pageTurnMode` 參數與 `didUpdateWidget` 檢查邏輯。
- `ReaderScreen` 新增第二顆 AppBar 切換按鈕，與橫直排切換按鈕共用同一個啟用條件（`_writingMode != null`，代表書本已成功開啟、`navigatorFragment` 已存在）。
- `PdfReaderView` 不受影響。
- 換頁模式切換**不持久化**，比照 Issue 2 的既有決定，維持在本 issue 範圍內的最小變動；持久化與三態覆寫 UI 仍留給 `epic-3-fonts-layout`（FR-10）。

## 曾考慮的替代方案

- **不修正偏好合併問題，只新增 `setPageTurnMode`**：實作最簡單，但會讓「切換橫直排」與「切換換頁模式」互相覆蓋對方的設定，是一個會實際發生、使用者可感知的回歸缺陷（例如使用者先切成捲動模式，再切橫直排，捲動設定會無預警消失），予以排除。
- **兩個偏好各自獨立呼叫 `submitPreferences()`，不合併**：`submitPreferences()` 本身是否會自動與「目前已生效的偏好」合併，取決於 Readium 內部實作，反編譯確認 `EpubPreferences` 建構子本身各欄位皆為獨立傳入、不會自動繼承先前呼叫的值，因此若不在呼叫端自行合併，效果等同上一個被排除的方案，予以排除。
