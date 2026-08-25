# Epic 31 Issue 2：main.js 觸控意圖分類器重構（TouchIntentClassifier）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `app/android/app/src/main/assets/foliate/main.js` 內 5 個各自獨立宣告狀態的觸控/選取機制（Epic 18 Issue 47／Epic 25 Issue 4／epic-27 Issue 9/10/11），收斂進一個新的 `TouchIntentClassifier` class，統一管理共用狀態，行為規則（門檻值、判斷邏輯）完全不變。

**Architecture:** 每次 `view.addEventListener('load', ...)` 觸發（含 look-ahead 預讀章節）建立一個 `TouchIntentClassifier` 實例，內部維持 3 個彼此獨立的欄位——`gesture`（長按候選子狀態機）、`lastTouchStartTime`（供快速點擊判斷用的持久時間戳）、`lastNonCollapsedSelectionAtMs`（供選取收尾保護用的持久時間戳）。5 個既有機制的判斷邏輯本身不改寫，只把原本散落的 `let`/`const` 區域變數改成讀寫這個 class 實例的欄位。**這是一個「行為不可變」的重構任務**，不是新功能開發：Issue 1 已建立的 `app/tool/foliate_touch_harness/` 回歸測試套件是重寫前就已存在、目前全數 PASS 的基準線，因此本計畫每個 Task 不走「先寫失敗測試」的古典 TDD，而是「異動前執行回歸測試確認基準線→異動→異動後重新執行回歸測試確認仍全數 PASS，沒有引入回歸」的重構驗證模式。

**Tech Stack:** 純 Vanilla JavaScript（ES2015+ class 語法，`app/android/app/src/main/assets/foliate/main.js` 本身非 vendored 檔案，屬本專案整合層，可自由修改，見 ADR 0011）；驗證用 Node.js Puppeteer 回歸測試（`app/tool/foliate_touch_harness/`，Issue 1 產出）。

**Spec:** `docs/epics/epic-31-touch-intent-unification/design.md`（「整體機制」> main.js 觸控意圖狀態機、「測試策略」、「已知風險」）；工單描述見 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 2。

## Global Constraints

- 不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`），只修改 `main.js`，符合 ADR 0011。
- 不新增 JS↔Dart 橋接資料（不新增 `callHandler` 呼叫、不新增 URL 參數）。
- 5 個門檻值的數字本身不可變動：`LONG_PRESS_GATE_MS=500`／`ANNOTATION_CLICK_TAP_MAX_MS=700`／`SELECTION_RELEASE_GUARD_MS=150`／`SWIPE_DISTANCE_DEADZONE_PX=15`／`SWIPE_VELOCITY_ESCAPE_PX_PER_MS=0.3`，只收斂宣告位置。
- 5 個機制各自的判斷邏輯本身不可變動，只收斂「誰來管理共用狀態」（讀寫從獨立變數改成讀寫 `TouchIntentClassifier` 實例欄位）。
- 每個 Task 完成後，`app/tool/foliate_touch_harness/` 的 `node run-all.mjs` 必須全數 PASS（4 個情境），才能進到下一個 Task。
- 本計畫**不處理** Dart 端 `TapZoneDetector`（那是 Epic 31 Issue 3，獨立平行工單，不在本計畫範圍）。
- 本計畫**不包含**真機重測本身的執行——那需要實體 Android 裝置，無法由本計畫的自動化 Task 完成。完成本計畫全部 Task 後，須由人類在真機上執行 `issues.md` Issue 2 列出的 5 項重測（Issue 47／Epic 25 Issue 1/4／Issue 10／Issue 11／長按候選期間選取突然確立），記錄於 `docs/epics/epic-31-touch-intent-unification/reviews/review-issue-2.md`，Issue 2 才能真正標記為完成／合併。
- 建議在獨立 git worktree 中執行本計畫（比照 Issue 1 慣例，見 `superpowers:using-git-worktrees`），分支名稱 `epic-31-issue-2`。

---

### Task 1：模組層級門檻值與 `TouchIntentClassifier` 骨架＋遷移長按候選攔截機制（Epic 18 Issue 47）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Produces（供 Task 2-4 使用）：
  - 模組層級常數：`LONG_PRESS_GATE_MS`／`ANNOTATION_CLICK_TAP_MAX_MS`／`SELECTION_RELEASE_GUARD_MS`／`SWIPE_DISTANCE_DEADZONE_PX`／`SWIPE_VELOCITY_ESCAPE_PX_PER_MS`（宣告在 `async function openBook()` 之前）。
  - `class TouchIntentClassifier`，欄位：`this.gesture = { state, startX, startY, startTime }`（`state` 為 `'idle'`／`'longPressCandidate'`／`'swiping'` 三選一字串）、`this.lastTouchStartTime`（`number | null`）、`this.lastNonCollapsedSelectionAtMs`（`number | null`）。
  - `view.addEventListener('load', ...)` 監聽器內、`const doc =`/`const index =` 之後宣告的區域變數 `classifier`（`new TouchIntentClassifier()` 實例），供該次 `load` 觸發內所有子監聽器的閉包讀取。

- [x] **Step 1: 執行既有回歸測試，確認基準線**

先確認 Issue 1 建立的回歸套件目前全數 PASS（重構前基準線）：

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 依序看到 4 個 `=== scenario-*.mjs ===` 區塊全部 `[PASS]`，結尾印出「整體結果：全部 PASS」。若非全數 PASS，先排除環境問題（例如 `npm install` 是否已執行），不可在基準線本身就是紅燈的狀態下開始本計畫。

- [x] **Step 2: 在 `async function openBook()` 之前插入模組層級狀態機骨架**

用 Read 工具開啟 `app/android/app/src/main/assets/foliate/main.js`，找到以下區塊（`window.getTableOfContents` 結尾與 `async function openBook() {` 之間）：

```js
window.getTableOfContents = async function () {
  try {
    const items = view.book?.toc ?? []
    const entries = []
    for (const item of items) {
      entries.push(await buildTocEntry(item))
    }
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify(entries))
  } catch (e) {
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify([]))
  }
}

async function openBook() {
```

改為（在兩者之間插入新區塊）：

```js
window.getTableOfContents = async function () {
  try {
    const items = view.book?.toc ?? []
    const entries = []
    for (const item of items) {
      entries.push(await buildTocEntry(item))
    }
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify(entries))
  } catch (e) {
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify([]))
  }
}

// ------------------------------------------------------------------
// 觸控意圖狀態機（TouchIntentClassifier，epic-31-touch-intent-unification
// Issue 2）：收斂下方 view.addEventListener('load', ...) 內原本各自獨立
// 宣告的觸控/選取共用狀態，讓 5 個既有機制（Epic 18 Issue 47 長按候選
// 攔截／Epic 25 Issue 4 快速點擊判斷／epic-27 Issue 9 no-swipe／Issue 10
// 選取收尾保護／Issue 11 hitTest 命中判斷）改讀寫這裡的 3 個欄位，不再
// 各自宣告獨立變數。行為規則（門檻值、判斷邏輯）與重構前完全相同，只
// 收斂「誰來管理共用狀態」，見
// docs/epics/epic-31-touch-intent-unification/design.md「整體機制」。
//
// 長按候選門檻對齊 Android ViewConfiguration.getLongPressTimeout() 預設
// 值；累積位移死區＋平均速度雙門檻（而非純距離單一門檻）的理由，見下方
// touchmove 監聽器內的完整說明——純距離門檻在 paginator.js 內部
// #touchState.x/y 只在真正放行的 touchmove 才更新的前提下，會讓第一個
// 放行的 touchmove 算出「手勢一開始到現在」的全部累積位移而非單影格
// 增量，造成畫面暴跳（docs/epics/epic-18-reader-device-qa/reviews/
// bugfix-repro-issue-47.md）。
const LONG_PRESS_GATE_MS = 500
const SWIPE_DISTANCE_DEADZONE_PX = 15
const SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3
// 快速點擊 vs. 刻意點擊畫線的判斷門檻（epic-25-annotation-interaction-qa
// Issue 4，真機多輪校準值），與 Dart 端
// _NavZoneTapDetector._tapMaxDurationMs（foliate_epub_reader_view.dart）
// 維持同一個數值心智模型，兩側各自獨立判斷、不透過橋接同步。
const ANNOTATION_CLICK_TAP_MAX_MS = 700
// 選取收尾保護期門檻（epic-27-reader-device-compat Issue 10），取自
// issue-10-11-12-analysis.md「Issue 10」建議解法方向區間（100～150ms）
// 上緣，尚未經真機校準，比照 epic-25 Issue 1／epic-26 Issue 3 先例，後續
// 若真機回報需要調整，另立工單處理。
const SELECTION_RELEASE_GUARD_MS = 150

console.assert(LONG_PRESS_GATE_MS <= ANNOTATION_CLICK_TAP_MAX_MS,
  '長按候選門檻必須 <= 快速點擊門檻，否則兩個機制的優先順序假設會被破壞')

/**
 * 每次 view.addEventListener('load', ...) 觸發（含 look-ahead 預讀章節）
 * 各自產生一個實例，維持 3 個彼此獨立的欄位（見上方模組註解）：
 * - gesture：只服務長按候選攔截（Epic 18 Issue 47），touchend/touchcancel
 *   會重置它為 idle。
 * - lastTouchStartTime：供快速點擊判斷（Epic 25 Issue 4）讀取，touchstart
 *   寫入、touchcancel 或 click 消耗時才清空，touchend 刻意不清空（供
 *   click 事件之後才判斷用）。
 * - lastNonCollapsedSelectionAtMs：供選取收尾保護（Issue 10）讀取，由
 *   selectionchange（經 reportSelection()）寫入/清空，與手勢子狀態完全
 *   無關。
 */
class TouchIntentClassifier {
  constructor() {
    this.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
    this.lastTouchStartTime = null
    this.lastNonCollapsedSelectionAtMs = null
  }
}

async function openBook() {
```

- [x] **Step 3: 在 `load` 監聽器內建立 classifier 實例**

找到：

```js
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index

      // 選取收尾保護期（Selection Release Guard，
```

改為：

```js
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index
      const classifier = new TouchIntentClassifier()

      // 選取收尾保護期（Selection Release Guard，
```

（本 Step 只新增這一行，緊接著的 `SELECTION_RELEASE_GUARD_MS`／`lastNonCollapsedSelectionAtMs` 區塊留到 Task 3 才動。）

- [x] **Step 4: 遷移長按候選攔截機制（Epic 18 Issue 47）讀寫 `classifier.gesture`**

找到（`ANNOTATION_CLICK_TAP_MAX_MS` 宣告之前的完整長按候選攔截區塊）：

```js
      const LONG_PRESS_GATE_MS = 500 // 對齊 Android ViewConfiguration.getLongPressTimeout() 預設值
      const SWIPE_DISTANCE_DEADZONE_PX = 15 // 累積位移死區：超過就放行，把最大暴跳量壓到跟正常單影格位移同量級
      const SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3 // 平均速度（累積位移/累積時間）門檻：真正滑動手勢通常第一影格就超過
      let longPressGateState = null
      doc.addEventListener('touchstart', (evt) => {
        const touch = evt.touches[0]
        if (!touch || evt.touches.length > 1) {
          longPressGateState = null
          return
        }
        longPressGateState = { x: touch.screenX, y: touch.screenY, t: evt.timeStamp }
      }, { capture: true })
      doc.addEventListener('touchmove', (evt) => {
        if (!longPressGateState) return
        if (evt.touches.length > 1) {
          longPressGateState = null
          return
        }
        const selection = doc.getSelection()
        if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
          // 選取已經確立，paginator.js 既有守衛從這裡開始會正確接手。
          longPressGateState = null
          return
        }
        const touch = evt.touches[0]
        if (!touch) return
        const elapsed = evt.timeStamp - longPressGateState.t
        const dx = touch.screenX - longPressGateState.x
        const dy = touch.screenY - longPressGateState.y
        const distance = Math.hypot(dx, dy)
        const avgVelocity = elapsed > 0 ? distance / elapsed : Infinity
        if (elapsed >= LONG_PRESS_GATE_MS
          || distance > SWIPE_DISTANCE_DEADZONE_PX
          || avgVelocity > SWIPE_VELOCITY_ESCAPE_PX_PER_MS) {
          // 超過長按辨識時間、或位移/平均速度已經大到明顯是滑動手勢——
          // 放行給 paginator.js 正常處理，不再攔截這個手勢剩餘的
          // touchmove。
          longPressGateState = null
          return
        }
        // 仍在長按候選期間（時間短、位移小、速度低、尚未確立選取）：攔截。
        //
        // 【Epic 25 Issue 1，見
        // docs/epics/epic-25-annotation-interaction-qa/issues.md】
        // stopImmediatePropagation() 會讓 paginator.js 的 #onTouchMove 整個
        // 不執行，連帶它在 paginator.js:2198 無條件呼叫的
        // e.preventDefault() 也不會被呼叫，所以本攔截器自己必須先呼叫
        // preventDefault()，讓瀏覽器一開始就看到有人取消了這個
        // touchmove——否則 Chromium 會判定「沒人要攔」而自行接管為原生
        // 捲動，一旦接管，該手勢剩餘所有 touchmove 都會被標記為不可取消，
        // 之後不論攔截器還是 paginator.js 再呼叫 preventDefault() 都會被
        // 忽略，畫面位移改由瀏覽器合成器直接控制，完全繞過 paginator.js
        // 自己的 #touchState/containerPosition 追蹤（真機重現症狀：選取
        // 是否已確立無關，任何落入候選窗口且沒被成功取消的手勢皆會誘發）。
        //
        // 本監聽器必須明確加上 { passive: false }（見下方註冊）：Chromium
        // 對直接掛在 Document 物件（doc 正是 iframe 的 contentDocument）
        // 上、沒有明確指定 passive 的 touchstart/touchmove 監聽器，預設
        // 會當成 passive 處理，passive 監聽器內呼叫 preventDefault() 會被
        // 靜默忽略（只印警告，不拋例外）——若漏了這個選項，上面的
        // preventDefault() 呼叫形同虛設。
        evt.preventDefault()
        evt.stopImmediatePropagation()
      }, { capture: true, passive: false })
      doc.addEventListener('touchend', () => { longPressGateState = null }, { capture: true })
      doc.addEventListener('touchcancel', () => { longPressGateState = null }, { capture: true })
```

改為：

```js
      doc.addEventListener('touchstart', (evt) => {
        const touch = evt.touches[0]
        if (!touch || evt.touches.length > 1) {
          classifier.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
          return
        }
        classifier.gesture = {
          state: 'longPressCandidate', startX: touch.screenX, startY: touch.screenY, startTime: evt.timeStamp,
        }
      }, { capture: true })
      doc.addEventListener('touchmove', (evt) => {
        if (classifier.gesture.state !== 'longPressCandidate') return
        if (evt.touches.length > 1) {
          classifier.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
          return
        }
        const selection = doc.getSelection()
        if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
          // 選取已經確立，paginator.js 既有守衛從這裡開始會正確接手。
          classifier.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
          return
        }
        const touch = evt.touches[0]
        if (!touch) return
        const elapsed = evt.timeStamp - classifier.gesture.startTime
        const dx = touch.screenX - classifier.gesture.startX
        const dy = touch.screenY - classifier.gesture.startY
        const distance = Math.hypot(dx, dy)
        const avgVelocity = elapsed > 0 ? distance / elapsed : Infinity
        if (elapsed >= LONG_PRESS_GATE_MS
          || distance > SWIPE_DISTANCE_DEADZONE_PX
          || avgVelocity > SWIPE_VELOCITY_ESCAPE_PX_PER_MS) {
          // 超過長按辨識時間、或位移/平均速度已經大到明顯是滑動手勢——
          // 放行給 paginator.js 正常處理，不再攔截這個手勢剩餘的
          // touchmove。轉入 swiping（而非 idle）：語意上是「這個手勢已經
          // 確定不是長按候選」，直到下次 touchstart 前都不會再回到
          // longPressCandidate（見 design.md 狀態轉換圖）。
          classifier.gesture.state = 'swiping'
          return
        }
        // 仍在長按候選期間（時間短、位移小、速度低、尚未確立選取）：攔截。
        //
        // 【Epic 25 Issue 1，見
        // docs/epics/epic-25-annotation-interaction-qa/issues.md】
        // stopImmediatePropagation() 會讓 paginator.js 的 #onTouchMove 整個
        // 不執行，連帶它在 paginator.js:2198 無條件呼叫的
        // e.preventDefault() 也不會被呼叫，所以本攔截器自己必須先呼叫
        // preventDefault()，讓瀏覽器一開始就看到有人取消了這個
        // touchmove——否則 Chromium 會判定「沒人要攔」而自行接管為原生
        // 捲動，一旦接管，該手勢剩餘所有 touchmove 都會被標記為不可取消，
        // 之後不論攔截器還是 paginator.js 再呼叫 preventDefault() 都會被
        // 忽略，畫面位移改由瀏覽器合成器直接控制，完全繞過 paginator.js
        // 自己的 #touchState/containerPosition 追蹤（真機重現症狀：選取
        // 是否已確立無關，任何落入候選窗口且沒被成功取消的手勢皆會誘發）。
        //
        // 本監聽器必須明確加上 { passive: false }（見下方註冊）：Chromium
        // 對直接掛在 Document 物件（doc 正是 iframe 的 contentDocument）
        // 上、沒有明確指定 passive 的 touchstart/touchmove 監聽器，預設
        // 會當成 passive 處理，passive 監聽器內呼叫 preventDefault() 會被
        // 靜默忽略（只印警告，不拋例外）——若漏了這個選項，上面的
        // preventDefault() 呼叫形同虛設。
        evt.preventDefault()
        evt.stopImmediatePropagation()
      }, { capture: true, passive: false })
      doc.addEventListener('touchend', () => {
        classifier.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
      }, { capture: true })
      doc.addEventListener('touchcancel', () => {
        classifier.gesture = { state: 'idle', startX: 0, startY: 0, startTime: 0 }
      }, { capture: true })
```

**行為確認要點**（不是新規則，只是確認遷移沒有改變語意）：`classifier.gesture.state !== 'longPressCandidate'` 涵蓋原本 `!longPressGateState`（`idle` 與 `swiping` 都會使這個條件成立，效果與原本 `null` 完全相同——touchmove 一律不攔截）；`elapsed`/`dx`/`dy` 改讀 `classifier.gesture.startTime`/`.startX`/`.startY`，數值來源與原本 `longPressGateState.t`/`.x`/`.y` 相同（都是 `touchstart` 當下寫入、期間不變）。

- [x] **Step 5: 重新執行回歸測試，確認未引入回歸**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 4 個情境全數 PASS（本 Task 遷移的長按候選攔截機制本身不在 Issue 1 自動化範圍內，見 `design.md`「測試策略」，這裡驗證的是「沒有破壞其餘 3 個機制」；長按候選攔截本身的正確性由本計畫最後的真機重測把關）。

- [x] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "refactor(epic-31): 建立 TouchIntentClassifier 骨架並遷移長按候選攔截機制"
```

---

### Task 2：遷移快速點擊判斷機制（Epic 25 Issue 4）讀寫 `classifier.lastTouchStartTime`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 `classifier`（`TouchIntentClassifier` 實例，`load` 監聽器內區域變數）、模組層級常數 `ANNOTATION_CLICK_TAP_MAX_MS`。
- Produces: 無新增（`classifier.lastTouchStartTime` 欄位本身已由 Task 1 的 constructor 建立，本 Task 只是接上讀寫的呼叫端）。

- [ ] **Step 1: 執行回歸測試，確認 Task 1 完成後的基準線**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 4 個情境全數 PASS。

- [ ] **Step 2: 遷移 touchstart／touchcancel 寫入端，移除本機重複宣告的門檻常數**

找到（緊接在 Task 1 剛遷移完的長按候選攔截區塊之後）：

```js
      const ANNOTATION_CLICK_TAP_MAX_MS = 700
      let annotationClickTouchStartTime = null
      doc.addEventListener('touchstart', (evt) => {
        annotationClickTouchStartTime = evt.touches.length === 1 ? evt.timeStamp : null
      }, { capture: true })
      doc.addEventListener('touchcancel', () => {
        annotationClickTouchStartTime = null
      }, { capture: true })
```

改為：

```js
      doc.addEventListener('touchstart', (evt) => {
        classifier.lastTouchStartTime = evt.touches.length === 1 ? evt.timeStamp : null
      }, { capture: true })
      doc.addEventListener('touchcancel', () => {
        classifier.lastTouchStartTime = null
      }, { capture: true })
```

（`ANNOTATION_CLICK_TAP_MAX_MS` 已在 Task 1 移到模組層級，這裡的區域宣告直接刪除，不留 shadow。緊接這個區塊之前的大段說明註解——超連結排除理由、Dart/JS 門檻心智模型一致性、click 監聽器清查記錄——維持原地不動，不隨這次搬遷刪除，它描述的是下面 click 監聽器的行為理由，不是這個常數宣告本身。）

- [ ] **Step 3: 遷移 click 監聽器讀取端**

找到：

```js
      doc.addEventListener('click', (evt) => {
        const startTime = annotationClickTouchStartTime
        annotationClickTouchStartTime = null

        if (startTime === null) return // 非觸控手勢產生的 click（例如滑鼠），不受影響
        if (evt.target.closest('a[href]')) return // 超連結點擊一律放行
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation()
        }
      }, { capture: true })
```

改為：

```js
      doc.addEventListener('click', (evt) => {
        const startTime = classifier.lastTouchStartTime
        classifier.lastTouchStartTime = null

        if (startTime === null) return // 非觸控手勢產生的 click（例如滑鼠），不受影響
        if (evt.target.closest('a[href]')) return // 超連結點擊一律放行
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation()
        }
      }, { capture: true })
```

- [ ] **Step 4: 重新執行回歸測試，確認未引入回歸**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 4 個情境全數 PASS（`scenario-epic25-issue4-fast-tap.mjs` 直接驗證本 Task 遷移的機制本身：短按 80ms 攔截／長按 900ms 放行／超連結不受影響 3 項斷言皆須維持 PASS）。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "refactor(epic-31): 遷移快速點擊判斷機制至 TouchIntentClassifier"
```

---

### Task 3：遷移選取收尾保護機制（Issue 10）讀寫 `classifier.lastNonCollapsedSelectionAtMs`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 `classifier`、模組層級常數 `SELECTION_RELEASE_GUARD_MS`。
- Produces: 無新增。

- [ ] **Step 1: 執行回歸測試，確認 Task 2 完成後的基準線**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 4 個情境全數 PASS。

- [ ] **Step 2: 移除本機重複宣告的門檻常數與區域變數**

找到（`view.addEventListener('load', (e) => {` 開頭、Task 1 Step 3 新增的 `const classifier = new TouchIntentClassifier()` 之後）：

```js
      const classifier = new TouchIntentClassifier()

      // 選取收尾保護期（Selection Release Guard，
      // epic-27-reader-device-compat Issue 10）：見下方 click 監聽器內
      // 完整說明。這裡只負責記錄「選取上一次被判定為非折疊（真的有選到
      // 文字）」的時間點，供該監聽器判斷這次 click 是否可能是選字收尾
      // 動作本身觸發的雜訊。真機 log 佐證見
      // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
      // 「Issue 10」；門檻值 150ms 取自
      // issue-10-11-12-analysis.md「Issue 10」建議解法方向的區間
      // （100～150ms）上緣，尚未經真機校準，比照 epic-25 Issue 1／
      // epic-26 Issue 3 先例，後續若真機回報需要調整，另立工單處理。
      const SELECTION_RELEASE_GUARD_MS = 150
      let lastNonCollapsedSelectionAtMs = null

      // 選取範圍即時回報（epic-17 Issue 8）：抽成共用函式，供既有
```

改為：

```js
      const classifier = new TouchIntentClassifier()

      // 選取範圍即時回報（epic-17 Issue 8）：抽成共用函式，供既有
```

（`SELECTION_RELEASE_GUARD_MS` 的完整由來說明已在 Task 1 移到模組層級常數宣告處，這裡整段連同區域常數／變數一併刪除，不留重複說明。緊接在後面的 `reportSelection` 函式本身完全不動位置，只在下一步修改其內部兩處寫入點。）

- [ ] **Step 3: 遷移 `reportSelection()` 內的寫入端**

找到（`reportSelection` 函式開頭的提前返回分支）：

```js
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          lastNonCollapsedSelectionAtMs = null
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
```

改為：

```js
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          classifier.lastNonCollapsedSelectionAtMs = null
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
```

再找到（同一函式內、非折疊分支寫入時間戳的那一行，前後保留完整的時鐘來源說明註解不動）：

```js
        // 用 iframe 自己的時鐘（doc.defaultView.performance.now()），不用
        // 最外層頁面的 performance.now()——兩者的時間原點（timeOrigin）
        // 不同，iframe 通常比最外層頁面晚啟動，若混用會讓下方 mousedown
        // 監聽器內 evt.timeStamp（同樣是 iframe 自己的時鐘，因為事件目標
        // 落在 iframe 文件內）減去這裡記錄的值時，算出一個恆為負數的
        // 差值，導致保護期判斷「時間差 <= 門檻」永遠成立、門檻形同虛設
        // （已用 Puppeteer 差分測試＋跨 frame 時鐘診斷埋點親自驗證重現，
        // 見 verify-issue10-guard.mjs 執行紀錄：iframe 時鐘與最外層頁面
        // 時鐘相差近 850ms，且此差值在單一次頁面載入內固定不變）。
        lastNonCollapsedSelectionAtMs = doc.defaultView.performance.now()
```

改為：

```js
        // 用 iframe 自己的時鐘（doc.defaultView.performance.now()），不用
        // 最外層頁面的 performance.now()——兩者的時間原點（timeOrigin）
        // 不同，iframe 通常比最外層頁面晚啟動，若混用會讓下方 mousedown
        // 監聽器內 evt.timeStamp（同樣是 iframe 自己的時鐘，因為事件目標
        // 落在 iframe 文件內）減去這裡記錄的值時，算出一個恆為負數的
        // 差值，導致保護期判斷「時間差 <= 門檻」永遠成立、門檻形同虛設
        // （已用 Puppeteer 差分測試＋跨 frame 時鐘診斷埋點親自驗證重現，
        // 見 verify-issue10-guard.mjs 執行紀錄：iframe 時鐘與最外層頁面
        // 時鐘相差近 850ms，且此差值在單一次頁面載入內固定不變）。
        classifier.lastNonCollapsedSelectionAtMs = doc.defaultView.performance.now()
```

- [ ] **Step 4: 遷移 mousedown 監聽器讀取端**

找到：

```js
      doc.addEventListener('mousedown', (evt) => {
        if (
          !evt.target.closest('a[href]') &&
          lastNonCollapsedSelectionAtMs !== null &&
          evt.timeStamp - lastNonCollapsedSelectionAtMs <= SELECTION_RELEASE_GUARD_MS
        ) {
          evt.preventDefault()
        }
      }, { capture: true })
```

改為：

```js
      doc.addEventListener('mousedown', (evt) => {
        if (
          !evt.target.closest('a[href]') &&
          classifier.lastNonCollapsedSelectionAtMs !== null &&
          evt.timeStamp - classifier.lastNonCollapsedSelectionAtMs <= SELECTION_RELEASE_GUARD_MS
        ) {
          evt.preventDefault()
        }
      }, { capture: true })
```

- [ ] **Step 5: 重新執行回歸測試，確認未引入回歸**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 4 個情境全數 PASS，特別是 `scenario-issue10-selection-release-guard.mjs`（保護期內／期外兩個情境）與 `scenario-cross-mechanism-tap-boundary.mjs`（選取保護與快速點擊分類跨機制邊界）直接驗證本 Task 遷移的機制本身。若 `scenario-cross-mechanism-tap-boundary.mjs` 偶發 FAIL，先重跑一次排除 `reviews/review-code-issue-1.md` 已記錄的已知計時競態，再判斷是否為本次遷移引入的回歸。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "refactor(epic-31): 遷移選取收尾保護機制至 TouchIntentClassifier"
```

---

### Task 4：確認 Issue 11／Issue 9 無需異動＋清除殘留＋全域驗收＋更新工單狀態

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（僅可能的殘留死碼清理，預期本 Task 不再有既有機制程式碼異動）
- Modify: `docs/epics/epic-31-touch-intent-unification/issues.md`

**Interfaces:**
- Consumes: Task 1-3 完成後的 `main.js`（`TouchIntentClassifier` 已完整接管 3 個欄位，5 個機制皆已改讀寫這個 class）。
- Produces: 無（本 Task 是驗收與收尾）。

**背景**：design.md「整體機制」把 Issue 11（`hitTest` 命中判斷）與 Issue 9（`no-swipe` 屬性設定）也列為需要「改讀這個 class 的欄位」的機制，但實際比對程式碼後發現：

- **Issue 11**：`reportSelection()` 內的 `overlayer.hitTest()` 查詢邏輯（`overlayerEntry`/`hit`/`hitCfi`/`existingAnnotationId` 皆為函式內區域變數）本來就沒有使用任何跨機制共用的可變狀態，design.md 所指的「額外呼叫寫入 `lastNonCollapsedSelectionAtMs`」，正是 Task 3 Step 3 已經完成的兩處 `classifier.lastNonCollapsedSelectionAtMs =` 賦值——Issue 11 本身的 hitTest 邏輯不需要、也不會有額外程式碼異動。
- **Issue 9**：`view.renderer.setAttribute('no-swipe', '')`（`openBook()` 內、`await view.open(book)` 之後，不在 `view.addEventListener('load', ...)` 監聽器內）是一次性、無條件執行的屬性設定，從未讀取任何觸控/選取共用狀態變數，design.md「讀這個 class 的欄位而非原本獨立變數」的敘述在這裡對不上實際程式碼——**這是 design.md 本身的敘述誤差，不是實作缺漏**，本 Task 會在該行加一則簡短註解說明，不修改這行程式碼本身。

- [ ] **Step 1: 全文檢索確認舊變數名稱已無殘留**

```bash
grep -n "longPressGateState\|annotationClickTouchStartTime" app/android/app/src/main/assets/foliate/main.js
```

Expected: 無任何輸出（兩個舊變數名稱已在 Task 1／Task 2 完全移除，不應該有殘留引用；若有輸出，回頭檢查對應 Task 是否有漏改的分支）。

```bash
grep -n "let lastNonCollapsedSelectionAtMs" app/android/app/src/main/assets/foliate/main.js
```

Expected: 無任何輸出（該區域變數宣告已在 Task 3 移除，只剩 `classifier.lastNonCollapsedSelectionAtMs` 這個欄位存取寫法）。

- [ ] **Step 2: 在 `no-swipe` 屬性設定處加上說明性註解，記錄與 design.md 的敘述落差**

找到：

```js
    // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
    // Issue 9 根因 B）。`setAttribute` 對任何自訂元素皆安全（不像呼叫該
    // 元素不存在的方法會拋例外），故不需要依 view.isFixedLayout 另外判斷。
    view.renderer.setAttribute('no-swipe', '')
```

改為：

```js
    // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
    // Issue 9 根因 B）。`setAttribute` 對任何自訂元素皆安全（不像呼叫該
    // 元素不存在的方法會拋例外），故不需要依 view.isFixedLayout 另外判斷。
    //
    // 【epic-31-touch-intent-unification Issue 2】這行是一次性、無條件的
    // 屬性設定，從未讀取 TouchIntentClassifier 管理的任何欄位，維持原樣
    // 不動——design.md「整體機制」把它列為需要「改讀 class 欄位」的第 5
    // 個機制，經比對實際程式碼確認是設計文件本身的敘述誤差，非本次遺漏。
    view.renderer.setAttribute('no-swipe', '')
```

- [ ] **Step 3: 完整回歸測試，連續執行確認穩定（比照 Issue 1 審查已建立的驗收慣例）**

```bash
cd app/tool/foliate_touch_harness
for i in 1 2 3 4; do echo "===== run $i ====="; node run-all.mjs 2>&1 | grep -E "FAIL|整體結果"; done
```

Expected: 4 次執行皆印出「整體結果：全部 PASS」，無任何 `[FAIL]`。

- [ ] **Step 4: 跑 ES 相容性掃描，確認新增的 `class` 語法未引入無防護的較新 API**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 `0`（`class` 語法本身是 ES2015 基礎特性，不在該腳本掃描的較新 API 清單內，這裡只是既有慣例的免費健檢，預期乾淨）。

- [ ] **Step 5: 確認未修改任何 vendored 檔案**

```bash
git diff --stat main -- app/android/app/src/main/assets/foliate/
```

Expected: 只列出 `main.js` 一個檔案，`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js` 皆未出現在異動清單中。

- [ ] **Step 6: 更新工單狀態**

在 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 2 的 `**Status:**` 那一行，改為 `ready-for-human`，並在下方補一段簡短總結：main.js 5 個機制已收斂進 `TouchIntentClassifier`，`app/tool/foliate_touch_harness/` 4 個情境連續執行維持全數 PASS，`flutter analyze`／`flutter test` 未受影響（本工單未異動任何 Dart 檔案）；**仍待人工完成 5 項真機重測**（Issue 47／Epic 25 Issue 1/4／Issue 10／Issue 11／長按候選期間選取突然確立），記錄於 `reviews/review-issue-2.md` 後才能視為完成並合併。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js docs/epics/epic-31-touch-intent-unification/issues.md
git commit -m "refactor(epic-31): main.js 觸控機制收斂完成，待真機重測"
```
