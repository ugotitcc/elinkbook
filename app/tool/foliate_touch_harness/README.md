# foliate_touch_harness

`app/android/app/src/main/assets/foliate/main.js` 觸控/選取行為的
Puppeteer 回歸測試（epic-31 Issue 1）。走 CDP
`Input.dispatchTouchEvent` 送真正的觸控 input pipeline，載入本 repo
真實的 `main.js`/`paginator.js`/`view.js`/`epub.js` 與
`app/test/fixtures/` 下既有的 fixture EPUB。

## 已知範圍限制

只涵蓋 `touchStart`/`touchEnd`（不含中途 `touchmove`）的場景。目前
環境 Chromium 版本下，CDP `touchmove` 事件送達 iframe 不可靠，依賴
`touchmove` 的場景（長按候選攔截、長按候選期間選取確立）不在這裡，
改由對應 Issue 的真機重測把關，細節見
`docs/epics/epic-31-touch-intent-unification/design.md`「已知風險」。

## 執行方式

```bash
cd app/tool/foliate_touch_harness
npm install   # 第一次執行需要，會自動下載 Chromium
node run-all.mjs
```

單獨執行某一個場景：`node scenario-<name>.mjs`。

`smoke-test.mjs` 是 `lib/harness.mjs` 函式庫本身的健檢，不算正式回歸
場景，`run-all.mjs` 不會執行它。

## 場景清單

- `scenario-epic25-issue4-fast-tap.mjs`：快速點擊 vs. 刻意點擊畫線。
- `scenario-issue10-selection-release-guard.mjs`：選取收尾保護。
- `scenario-issue11-hittest-existing-highlight.mjs`：`hitTest` 命中判斷。
- `scenario-cross-mechanism-tap-boundary.mjs`：選取保護與快速點擊分類
  的跨機制邊界情境。
- `scenario-disable-publisher-styles.mjs`：「停用書本 CSS」開關對書本自帶版面 CSS 的清除。
- `scenario-preload-stale-layout.mjs`：預讀章節套用過時排版（時序競爭）。直排單欄下，翻到下一章偶爾變成
  上下兩半的雙欄（真機 AiPaper Reader C 回報）的回歸場景：以記憶體組出的 5 章 EPUB，精準延遲「下一個建立的
  iframe」的 load，並在延遲期間改變欄數，斷言所有章節文件的 `column-width` 一致。移除 `main.js` 的
  「章節載入後比對 column-width、不一致就 `renderer.render()`」防護時本場景會 FAIL（已驗證 6/6）。
  這個場景涵蓋的是「時序競爭」本身；真機上的實際觸發來源是開書時 `applyPreferences()` 於首章尚未載完就執行。
- `scenario-writing-mode-autodetect.mjs`：排版方向自動偵測全書預掃（epic-46）。「採用書籍排版」模式下開書前預掃全書（OPF `primary-writing-mode`、外部 CSS、XHTML 內嵌樣式）判定直橫排，10 案例涵蓋 `-webkit-` 前綴、`tb-rl` 舊式別名、內嵌 `style` 屬性（含單引號）、manifest 缺檔 CSS，以及註解／正文文字／非法值 `tb-lr` 反例；全書任一處宣告直排即為直排。
- `scenario-resize-observer-false-error.mjs`：全域 JS 錯誤捕捉不得把 Chromium 良性的「ResizeObserver loop」警告誤報為 `onError`（epic-47）。直接從 `foliate_native_bridge.dart` 抽出 `globalErrorCaptureJs` 注入頁面，於開書流程早期（DOMContentLoaded，尚未收到 `onPageRendered`）與開書後各觸發一次真實的 ResizeObserver loop，斷言沒有 `onError`；另以頁面內真正的未捕捉例外、未處理的 Promise rejection，以及訊息以「ResizeObserver loop」開頭的真正例外作為正向對照，確認仍會回報。移除過濾時 A、B 會 FAIL；過濾條件放寬為任意位置比對時 E 會 FAIL。
- `scenario-vertical-paragraph-spacing.mjs`：直排下「段落間距」不得縮短行長。`buildOverrideCss()` 原輸出物理屬性 `p { margin-bottom }`，直排（vertical-rl）下 bottom 是行的結尾端，段距調大會讓每行少幾個字、內文下方出現大片留白（蘇東坡新傳，真機 AiPaper Reader C）。以記憶體 EPUB、段距 2.9em 斷言最長一行用滿頁高、且 `margin-bottom` 為 0；改回 `margin-bottom` 時兩項皆 FAIL。

