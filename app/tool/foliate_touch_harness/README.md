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
