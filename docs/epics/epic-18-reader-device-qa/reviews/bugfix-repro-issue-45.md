# Bugfix Repro：Issue 45 — EPUB 直排／橫排切換後翻頁跳多頁

## 症狀

使用者回報：EPUB 切換直排/橫排後，若不退出書籍重新進入，上下頁換頁都會一次跳好幾頁；退出重進後恢復正常。

## 重現方式

`tmp/epic-18-issue-45-harness/repro.mjs`（Puppeteer + headless Chromium，未進版控），
透過 request interception 直接伺服 `app/android/app/src/main/assets/foliate/`
真實 vendored 資源與既有測試 fixture `issue9_vertical_pagejump.epub`，完整驅動
`main.js`／`paginator.js`／`view.js`，經由與正式產品相同的
`window.flutter_inappwebview.callHandler(...)` 橋接契約攔截
`onLocatorChanged` 事件，量測連續 `nextPage()` 呼叫的 `fraction`
（全書進度比例）位移量。

## 審查修正（Round 2）：harness 穩定性問題

首輪執行（`tmp/epic-18/review-plan-issue-45-round2.md` 審查發現）的
`waitForSettle()` 要求「`relocate` 次數增加」與「`stabilized` 次數增加」
同時成立才算完成一次量測；連續重跑兩次，逾時（`null`）出現的索引位置
每次不同，證實這是量測機制本身的非決定性瑕疵（`'stabilized'` 事件只在
`paginator.js` 觸發 `render()`/`#fill()` 時才會 dispatch，`nextPage()`
若走不需要重建 view 的輕量捲動路徑則可能完全不觸發，導致雙條件 AND
卡死到逾時），不是「書本翻到結尾」。已修正為只依賴 `relocate`
本身（`waitForRelocateSettle()`：等到新的 `relocate` 之後，再等待
連續 300ms 內次數不再變動才視為穩定），並把「切換後第一次量測」的
判讀邏輯從硬取索引 `[0]` 改為「三筆量測中第一筆非 `null` 的值」
（`firstPostSwitchDeltaIndex`／`firstPostSwitchToHorizontalDeltaIndex`
一併記錄進 `result.json`，供之後複查）。修正後連續重跑 3 次，結果
逐位元組完全一致，無任何 `null`。

## 量測數據（修正後，連續 3 次重跑結果一致）

- 橫排 baseline（切換前，3 次 `nextPage()`）：`[0, 0.01017, 0.02862]`，平均 `0.01293`
  （第 1 筆 `nextPage()` 的位移量穩定為 `0`，三次重跑皆相同，非量測異常——推測是這份 fixture 的第一個邏輯段落在目前版面參數下對應到同一個欄位邊界，不影響後續判讀，因為判讀依據是 baseline 平均值而非單筆）
- 切換為直排後（3 次 `nextPage()`）：`[0.01377, 0.01561, 0.03168]`，取第 1 筆 `0.01377`（索引 0，即切換後緊接著的下一次翻頁）
- 再切回橫排後（3 次 `nextPage()`）：`[0.01584, 0.01710, 0.01710]`，取第 1 筆 `0.01584`（索引 0）
- 判讀：`reproduced = false`（`0.01377` 未超過 baseline 平均 `0.01293` 的 2 倍門檻 `0.02586`）、`reproducedReverse = false`（`0.01584` 同樣未超過門檻）

## 結論

harness 穩定性問題修正後，連續 3 次重跑結果完全一致、且切換前後兩個
方向的「第一次量測」皆為真實量測值（不再有 `null` 造成的短路判讀）——
在本次重現條件下（`issue9_vertical_pagejump.epub` fixture、800×1200
viewport、預設版面參數），確認**未觀察到**使用者回報的「切換排版方向後
翻頁一次跳好幾頁」的位移異常。

可能原因：(a) fixture EPUB 內容/結構與使用者實際遭遇問題的書籍差異過大，
未觸發相同的分欄/方向邊界條件；(b) 症狀與真機特定的 WebView 版本/渲染
時序有關，headless Chromium 環境無法重現；(c) 原始碼追蹤的根因假設
（`plan-issue-45.md` Global Constraints 段落：`setStyles()` 不會觸發
`getDirection()`／`#beforeRender()` 重新推導方向）本身有誤，需要重新
排查。建議下一步：改用真機搭配 `chrome://inspect` 遠端除錯直接觀察
`this.#vertical`（可在 DevTools console 內對
`document.querySelector('foliate-view').renderer` 物件展開檢視，雖為
私有欄位但 DevTools 可繞過語法限制直接檢視），或請使用者提供螢幕錄影
搭配操作步驟時間戳記，以取得更精確的重現條件。

---

## `/diagnose` 續作：實際重現、根因鎖定與修復（2026-08-11）

**上面「未觀察到」的結論，是因為既有 harness 只測過 `nextPage()`、只在書本前段（fraction ~0.05）切換方向——覆蓋範圍不足，不是症狀真的不存在。** 使用者原始回報是「上下頁換頁都會一次跳好幾頁」，`previousPage()` 從未被測過；使用者可能也不是永遠在書本最前段切換方向。

### Phase 1-2：補強重現迴圈，成功重現

`tmp/epic-18-issue-45-harness/repro-prev.mjs`（`repro.mjs` 的最小差異變體，`未進版控`）：先往前翻 13 次（10 次暖身 + 3 次 baseline）墊出足夠深度，切換為直排後改用 `previousPage()`（而非 `nextPage()`）量測。連續重跑 3 次結果逐位元組一致：

- 切換前 fraction：`0.20977`
- 切換完成當下（尚未呼叫任何 `prev()`/`next()`）：`0.28719`——**光是切換這個動作本身就跳動 +0.07742（約 4 頁份量）**
- 緊接著第一次 `previousPage()`：位移 `-0.09678`（baseline 平均的 5 倍以上，`reproduced = true`）

已排除「harness 判定穩定的時機太早、量測到過渡值」這個可能性：切換完成後額外多等 1000ms，relocate 次數與 fraction 完全沒有再變動，`0.28719` 確認是真正穩定下來的最終位置。

用 5 種 viewport（400×700／800×1200／1200×1600／1000×1000／600×1800）重跑，**全部重現**，只有跳動幅度不同——證實症狀與螢幕解析度無關。

### Phase 4：用除錯 log 鎖定確切機制

暫時對 `paginator.js` 的 throwaway 複本（`tmp/epic-18-issue-45-harness/paginator-debug.js`，**未修改 vendored 檔案本身**，僅本次診斷腳本內覆蓋伺服）加上 `[DEBUG-a4f2]` 標記的除錯 log，追蹤到：

1. `setStyles()`（`paginator.js:3454`，`main.js` 用來真正翻轉 `writing-mode` CSS 的呼叫）執行後，緊接著一次由字型載入回呼觸發的 `#scrollToAnchor` 顯示 `rect={x:632.2, y:56.0, w:27.0, h:61.4}`——窄寬、高的形狀，證實 DOM 這時候真的已經是直排排版。
2. 但這次呼叫（以及稍後由 `#container` 的 `ResizeObserver` 觸發的 `render()`）**全部仍然印出 `this.#vertical=false`**。
3. `#scrollToRect()` 因此用橫排座標軸假設（`rect.x`）去換算一個「已經是直排形狀」的定位框，算出錯誤的捲動頁碼——這就是位移異常的直接數學原因。

**確切根因**：`Paginator` 內部決定分欄/捲動軸方向的私有欄位 `this.#vertical`，只有在 section **第一次載入**（`View.load()` 的 iframe `load` 事件、呼叫 `getDirection(doc)`）時才會正確推導；書本已經開啟、只是切換方向的情境下，`setAttribute` 觸發的 `render()` 只會自我參照 `this.#vertical` 目前的值，`setStyles()` 本身也完全不會觸發任何重新推導——沒有任何路徑會修正這個過時的欄位，直到使用者退出重進、強制每個 section 走一次全新載入。

### Phase 5：修復

查證 `view.js` 的公開方法 `View.goTo(target)`（`view.js:509`）會呼叫到 `Paginator.goTo()`（`paginator.js:3337`）→ 私有 `#goTo()`（`paginator.js:3233`），這裡**已經內建**方向變更偵測：

```js
const { vertical } = getDirection(view.document)
directionChanged = vertical !== this.#vertical
```

`getDirection(view.document)` 讀取的是當下即時的 DOM 狀態（非自我參照），若 `directionChanged === true` 會 `this.#destroyAllViews()` 並透過 `this.sections[index].load()` 強制該 section 重新走一次完整載入，正確修正 `this.#vertical`。**這是 `paginator.js` 既有、未被使用過的公開行為**，不需要修改任何 vendored 檔案。

修法（`app/android/app/src/main/assets/foliate/main.js`，`window.applyPreferences()`）：`writingMode` 真的變動時（排除 Issue 9 裝置旋轉重新套用偏好等未變動的情境），在 `setStyles()` 之後呼叫 `view.goTo(view.lastLocation.cfi)`（用完整 CFI 保留原本閱讀位置，不用 index 導覽，否則會跳到 section 開頭）。

### 驗證

`repro-prev.mjs` 與 5 種 viewport 全數重跑，修復後皆為 `reproduced: false`／`reproducedReverse: false`，切換完成當下只剩一次正常量級（約一頁份量）的微幅調整，不再是 4 頁份量的跳動；原本 `repro.mjs`（`nextPage()` 情境）與新的 `repro-prev.mjs`（`previousPage()` 情境）皆連續重跑 3 次結果穩定一致。既有 `flutter test`／`flutter analyze` 不受影響（本次修復完全不涉及 Dart/Flutter 程式碼）。
