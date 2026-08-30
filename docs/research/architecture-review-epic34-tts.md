# 語音朗讀（TTS）— 架構檢視（Epic 34 完成後回顧）

> 產出方式：`/improve-codebase-architecture` 技能，聚焦範圍由使用者指定：「針對 EPIC 34 TTS 特別分析可以改善優化的地方」。
> 涵蓋範圍：`epic-34-tts-readalong`（語音朗讀與同步高亮）相關模組，Issue 1-11 全數完成並合併回 `main` 之後的回顧，不涉及其他 Epic。
> 產出日期：2026-08-29。

## 核心問題

Epic 34 的 Issue 11（長段落無標點朗讀失敗）真機除錯過程中，安全視窗（Safe Viewport）翻頁判斷邏輯繞了兩次誤診斷才定位到真正問題——原因是這段邏輯完全焊在 `main.js` 的 DOM 事件監聽器裡，沒有獨立介面，只能靠「改程式碼→編 APK→真機測試→看 log」這個緩慢的回饋迴圈驗證假設。本次檢視盤點 Epic 34 範圍內類似的架構摩擦點。

---

## 候選 1 · 把安全視窗判斷抽成純函式，讓它真正可測試

**建議強度**：Strong（純介面重構，不改變任何現有行為，風險低）

**檔案**：
- `app/android/app/src/main/assets/foliate/main.js:898-950`（`draw-annotation` 監聽器內的安全視窗判斷）
- `app/test/reader/foliate_reader_view_test.dart:1559-1725`（兩組 regression guard，全數用 `mainJsSource.contains(...)` 字串比對）

**Problem**：`needNext`/`needPrev` 的判斷邏輯（從 `range.getClientRects()` 取頭尾矩形、正規化座標、依排版方向判斷是否超出安全視窗）沒有獨立介面，只焊死在約 55 行的 DOM 事件監聽器裡。Issue 11 真機除錯時，這段邏輯的行為完全無法在裝置外驗證——兩次誤診斷（依比例挑矩形、同一 CFI 只檢查一次）都是因為只能靠加 log、重編 APK、真機測試才能驗證假設，沒有更快的回饋迴圈。既有 Dart 測試也只能對著原始碼字串做 `contains()` 比對，測不到真正的行為（邊界值、多矩形情境等）。

**Solution**：新增零 DOM 依賴的獨立檔案 `tts-safe-window.js`（比照同目錄 `progress.js` 的既有先例），把 `TTS_SAFE_WINDOW_MIN`/`MAX` 常數與判斷邏輯一併搬過去，`export function resolveTtsSafeWindowDirection(firstRect, lastRect, iframeRect, viewportRect, isVertical)`，內含原本的座標正規化＋`needNext`/`needPrev`判斷＋「next 優先於 prev」的順序邏輯，直接回傳 `'next' | 'prev' | null`。`main.js` 改為 `import` 這個函式，監聽器縮成「取 rects → 呼叫函式 → 有結果才 callHandler」三行。新增 `app/tool/test_tts_safe_window.mjs`（比照既有 `test_section_progress_density.mjs`，Node 內建 `assert` 執行、無需框架），涵蓋橫排/直排、頭尾矩形不同、邊界值等情境。

**Wins**：
- locality：判斷邏輯集中一處，下次真機回報異常不必再靠測不到的字串比對測試除錯，回饋迴圈從幾分鐘縮到幾毫秒
- 介面收斂：5 個輸入、1 個字串輸出，測試斷言真正的回傳值而非原始碼文字
- leverage：同一個純函式，`main.js` 呼叫一次、測試呼叫任意次

**ADR 衝突**：無。`main.js` 是「非 vendored、可自由修改的橋接腳本」（CLAUDE.md 明文），與完全禁止修改的 `paginator.js`／`view.js` 不同，不牴觸 ADR 0011。

**後續處理**：`/grilling` 已敲定實作細節，拆為 `epic-26-architecture-hardening` Issue 12。

---

## 候選 2 · 收斂重複三次的 JS 請求／回應樣板

**建議強度**：Strong

**檔案**：`app/lib/reader/foliate_reader_view.dart:609-611`（三個 Completer 欄位）／`688-727`（`_requestTableOfContents`／`_requestTtsSegments`／`_requestTtsSegmentIndex`）／`760-786`（三組 handler 註冊）

**Problem**：「送一個 JS 請求、等 handler 回呼、完成 Completer」這個模式被複製三次（TOC、TTS 朗讀段、TTS 段落索引），其中兩個 TTS 版本連 5 秒逾時的樣板都是複製貼上的。要新增下一個一次性 JS→Dart 查詢，得再複製一次整組樣板。

**Solution**：收斂成一個深模組（例如 `JsBridgeGateway.request<T>()`），統一管理 Completer 生命週期、逾時、handler 註冊；三個 `_requestXxx` 方法各自縮成一行呼叫。

**Wins**：
- leverage：一個介面，3 個呼叫點（未來新增查詢時免再複製樣板）
- 介面收斂：呼叫端不再各自宣告、清空 Completer 欄位
- 刪除測試：拿掉個別 `_requestXxx` 方法，「送請求等回呼」這件事還是得做——複雜度只是被迫搬回呼叫端，不會消失，代表現在的重複正是該收斂的訊號

**ADR 衝突**：無。

---

## 候選 3 · 把 400ms 翻頁節流從 ReaderScreen 搬進 TtsController

**建議強度**：Worth exploring

**檔案**：
- `app/lib/screens/reader_screen.dart:320-328`（`_lastTtsPageTurnAt` 欄位）／`2902-2920`（`onTtsHighlightOutOfSafeWindow` 節流判斷）
- `app/test/screens/reader_screen_test.dart:8300-8349`（僅斷言「不崩潰」，未斷言節流行為本身）

**Problem**：400ms 節流是 Issue 11 真機除錯撞出來的修復（過程中兩次誤診斷才定位到），現在的家是 `ReaderScreen`（近 3000 行）裡一個孤立的 `DateTime?` 欄位＋一段行內判斷，跟上百個無關欄位混在一起；既有測試只斷言 callback 不拋例外，完全沒斷言「冷卻時間內第二次呼叫真的被跳過」這個節流行為。

**Solution**：`TtsController` 已經有 `suppressNextExternalPositionChange()` 這個時間窗抑制的先例（純 Dart、可用 FakeAsync 測）——把翻頁節流也收進同一個類別，介面是「呼叫這個方法，內部自己決定要不要真的翻頁」。

**Wins**：
- locality：下次同類「事件疊加」bug 不必再靠真機加 log 除錯兩輪
- 測試從「不崩潰」升級到「行為正確」（真的斷言節流生效）
- 介面收斂：`ReaderScreen` 少一個獨立管理的計時狀態欄位

**ADR 衝突**：無，但會牽動 Issue 8／Issue 11 審查已定案的 `onTtsHighlightOutOfSafeWindow` callback 邊界，建議候選 1（Issue 12）完成、真機驗證安全視窗判斷本身穩定後再評估是否立案。

---

## 候選 4 · 三個獨立 callback 建構參數收斂成一個 Bridge 介面

**建議強度**：Speculative

**檔案**：
- `app/lib/reader/tts_controller.dart:28-52`（`loadSegments`／`onHighlightSegment`／`lookupStartIndex`，各自附長篇文件註解）
- `app/lib/screens/reader_screen.dart:2757-2814`（`_ttsControllerOrNull` 內對應三段 closure 實作）

**Problem**：介面用 3 個各自獨立的 function 參數表達「`TtsController` 需要跟畫面世界溝通的 3 件事」，每個都要一段長文件註解說明其存在理由——這是介面複雜度接近實作複雜度的訊號。

**Solution**：收斂成一個具名介面 `TtsReaderBridge`（`loadSegments()`／`onSegmentChanged()`／`lookupStartIndex()`），`ReaderScreen` 實作一次、`TtsController` 建構子只收一個 `bridge`。

**Wins**：
- 介面收斂：3 個鬆散參數 → 1 個具名介面
- 測試：一個 Fake 類別，不用三個 closure 各自組裝

**ADR 衝突**：無直接牴觸既有 ADR，但重新打開 Issue 2／Issue 4 審查已定案的解耦設計（文件註解本身就是刻意決策的紀錄，非疏忽）——「callback 各自替換」在測試上比「單一介面整包 mock」更靈活，兩種設計互有取捨，值得跟人類討論再定，不是明顯淨勝，故標為 Speculative，暫不立案。

---

## 處理順序建議

優先做候選 1——唯一直接對應「Issue 11 真機除錯兩次誤診斷」這個真實痛點，改動範圍小（只搬既有數學運算，不改行為），成本最低、報酬最直接。候選 2 次之（同樣 Strong、風險低，但不對應已知真實事故，優先序略低）。候選 3 建議待候選 1 落地並經過一段時間真機驗證後再評估。候選 4 暫不立案，留待未來需要時再與人類討論設計取捨。
