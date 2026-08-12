# Bugfix Repro：旋轉螢幕後畫面被錯誤文字取代，無法繼續閱讀

日期：2026-08-06
回報來源：真機使用回報（AiPaper Reader C），Android 16 / Chromium 150 WebView。

## 症狀

閱讀書籍時，不論是直屏轉橫屏或橫屏轉直屏，旋轉螢幕都會出現錯誤——畫面整個被一段錯誤文字取代，無法繼續閱讀。但開啟書籍剛進入時，不論直屏或橫屏都正常，只有「旋轉」這個動作本身會觸發。

真機截圖顯示畫面被以下文字整個取代：

```
JS Error: ResizeObserver loop completed with undelivered notifications. (https://appassets.androidplatform.net/assets/foliate/index.html?prefs=...)
```

伴隨的 console log：

```
[LOG] [UserAgent] Mozilla/5.0 (Linux; Android 16; AiPaper Reader C Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/150.0.7871.181 Mobile Safari/537.36
[ERROR] ResizeObserver loop completed with undelivered notifications.
```

## Feedback loop

不需要真機——這是純 Dart 端的狀態機邏輯缺陷，可以在 widget test 層級用既有測試慣例直接模擬：`FoliateEpubReaderView` 的 `onPageRendered`/`onLayoutResolved`/`onError` 皆是可從測試直接呼叫的 callback 屬性（`app/test/screens/reader_screen_test.dart` 既有多處測試採用同一模式），先模擬開書成功（呼叫 `onPageRendered()`+`onLayoutResolved()`），再模擬成功之後才發生的 `onError(...)`，斷言 `reader_error_text` 是否出現。

## 根因

`reader_screen.dart` 的 `_handleError(String message)`（PDF 與 EPUB 共用同一個 callback）完全沒有狀態守衛，任何時候被呼叫都無條件把 `_state` 覆寫為 `_RenderState.error`——不論書籍是否已經成功渲染。這與同檔案內的 `_handleOpenBookTimeout()`（`epic-18-reader-device-qa` Issue 33 既有程式碼）形成鮮明對比，後者明確寫了 `if (_state != _RenderState.loading) return;` 防止覆蓋已成功的畫面，`_handleError` 當初新增全域 JS 錯誤捕捉時漏了同一種防禦。

`epic-18-reader-device-qa` Issue 33 為了診斷「開書卡住」問題，在 `foliate_epub_reader_view.dart` 的 `_globalErrorCaptureJs` 注入了 `window.onerror`／`window.onunhandledrejection`，會把**任何**未被攔截的 JS 例外都透過既有 `onError` bridge 轉發到 Dart 端。這個機制原本設計來涵蓋「vendor 腳本在文件載入極早期拋出例外」（例如舊版 WebView 缺少 ES 內建方法），但它沒有分辨「書籍根本沒開成功」與「書籍已經開成功、之後才發生的某個不影響閱讀的 JS 事件」。

`foliate-js` 的 paginator 使用 `ResizeObserver` 監看內容尺寸以重新分頁。旋轉螢幕會觸發 viewport 尺寸變化 → `ResizeObserver` 的 callback 在同一個 frame 內處理不完 → Chromium 對此情境有一個廣為人知、通常視為良性的內建警告：`ResizeObserver loop completed with undelivered notifications`（並非真正的例外，是瀏覽器主動 dispatch 的一個 `error` 事件，用來提醒開發者可能有 resize 迴圈，但不代表任何功能真的壞掉，Chromium/WebKit 社群普遍建議直接忽略這則訊息）。這個警告被 `window.onerror` 捕捉、轉發、最終被 `_handleError` 無條件當成致命錯誤處理，整個已經成功渲染的閱讀畫面因此被錯誤文字取代。

完全符合回報的症狀：開書當下沒有觸發 resize（正常），旋轉的瞬間必然觸發 `ResizeObserver`（兩個方向都會壞），且是確定性的（每次旋轉都會重現，非偶發）。

## 修法

`_handleError()` 比照既有的 `_handleOpenBookTimeout()` 加上同一種狀態守衛：只在 `_state == _RenderState.loading`（書籍尚未成功開啟）時才轉為錯誤畫面。已成功渲染（`_state == _RenderState.rendered`）之後才發生的 `onError`（不論是 PDF 端還是 EPUB 端）不再覆蓋畫面。

診斷可視性不受影響：`window.onerror`/`onunhandledrejection` 轉發的訊息只是不再驅動 UI 狀態切換，`onConsoleMessage` → `handleFoliateConsoleMessage()` → `ReaderConsoleLog`（epic-18-reader-device-qa Issue 33「閱讀器 Console Log」診斷畫面）這條完全獨立的路徑仍會照常記錄同一則錯誤，供事後排查使用。

## 驗證結果

- 新增 widget test（`app/test/screens/reader_screen_test.dart`）：模擬「開書成功 → 之後才發生 onError（用實際回報的 ResizeObserver 錯誤文字）」，修法前 FAIL（`reader_error_text` 出現、書籍畫面消失），修法後 PASS。
- `flutter test test/screens/reader_screen_test.dart`：138/138 全數通過。
- 全專案 `flutter test`：1003/1003 全數通過，`flutter analyze` 乾淨。
- 無 `[DEBUG-...]` 暫時性插樁需要清理（本次診斷全程透過閱讀既有程式碼與撰寫 widget test 完成，未使用 log 插樁）。

## 這次診斷帶出的架構觀察

`_handleError` 與 `_handleOpenBookTimeout` 是同一個「開書診斷」子系統（epic-18-reader-device-qa Issue 33）裡處理相近情境（判斷書籍是否已成功開啟）的兩個 sibling method，但只有其中一個有狀態守衛。這類「兩個平行方法本該遵守同一條不變量、卻只有一個記得寫」的疏漏很難靠 code review 提前抓到，因為兩個方法本身各自看起來都合理。這次事後看，`_handleOpenBookTimeout` 的 guard 寫得很清楚（甚至註解直接點名「雙重防禦，避免任何未預期的競態把已經成功渲染或已經顯示其他錯誤訊息的畫面覆蓋掉」），但這條原則沒有被抽成一個共用的「_state 是否仍在 loading」檢查給兩個方法共用，導致新增 `_handleError` 時容易漏掉。後續若這個子系統再新增第三個「可能把畫面切回錯誤狀態」的入口，建議直接抽一個私有 helper（例如 `bool get _stillLoading => _state == _RenderState.loading`）明確宣告這條不變量，而不是各自複製貼上同一段 if 判斷。
