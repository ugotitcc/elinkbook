# Epic 18 Issue 47 — 流式 EPUB 劃線拖曳選取時頁面亂跳：診斷用重現迴圈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `issues.md` Issue 47 目前狀態是 `needs-triage`，明載「根因為靜態程式碼推論，下一步：真機或 headless Chromium 重現『長按開始選取的前幾個 touchmove 事件』，確認 `#onTouchMove` 的選取狀態守衛是否真的在此期間放行了 `scrollBy`/`#dragBy`」——本計畫的交付物**不是程式碼修復**，而是這個量測用重現迴圈本身，加上依量測結果產出的診斷報告與 `issues.md` 狀態更新。真正的程式碼修復（若確認重現）留待另一份 `plan-issue-47.md` 覆寫或新工單接手。

**Architecture:** 沿用 Epic 18 Issue 45 已驗證穩定的 Puppeteer + headless Chromium 診斷手法（`plan-issue-45.md`／`reviews/bugfix-repro-issue-45.md`）——透過 Puppeteer request interception 直接伺服真實的 vendored 資源目錄與既有測試 fixture EPUB，完整驅動真正的 `main.js`／`paginator.js`／`view.js`。與 Issue 45 不同之處：本計畫不測 `nextPage()`/`previousPage()`，而是直接在書本內文的 iframe 文件上 `dispatchEvent()` 真實的 `TouchEvent`（`touchstart`/`touchmove`/`touchend`），繞過 Puppeteer 高階觸控模擬與作業系統手勢辨識的不確定性，直接測試 `paginator.js` 已註冊的 `'touchmove'` 事件監聽器本身邏輯——量測「選取尚未建立」與「選取已確立」兩種情境下，同樣的小幅位移是否分別觸發／不觸發內容位移。

**Tech Stack:** Node.js（已安裝 v24）、Puppeteer（headless Chromium，`npm install` 安裝於 `tmp/` 內、不進版控，沿用 Issue 45 已確認可用的 `puppeteer@^25.5.0`）。不涉及任何 Dart/Flutter 程式碼異動。

## Global Constraints

- **不可修改任何 vendored 檔案**：`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`／`progress.js`／`text-walker.js`／`construct-style-sheets-polyfill.js`／`vendor/zip.js` 全部原樣，只能透過這些檔案已公開的介面（`window.applyPreferences`／`window.flutter_inappwebview.callHandler`／`Paginator` 的公開 getter `containerPosition`／DOM `dispatchEvent()`）驅動與觀察（比照 ADR 0011）。
- **不可修改 `main.js`／`index.html`**：正式產品程式碼，本計畫純粹是外部觀察者，所有攔截/量測邏輯都在獨立的 harness 腳本內完成。
- **harness 腳本與其產物一律放在 `tmp/epic-18-issue-47-harness/`**：`tmp/` 已於根目錄 `.gitignore` 排除，不進版控；Task 1/2 完全不含 git commit 步驟（比照 Issue 8 Spike／Issue 45 既有慣例）。
- **本計畫不修改任何 Dart/Flutter 程式碼、不新增/修改 `flutter test`、不影響 `flutter analyze` 基準**——純 JS 診斷任務，比照 Issue 34/38/45 既有先例。
- **量測指標選用 `Paginator.containerPosition`（橫排）與主要 view 元素的 `computed transform`（直排）**：兩者皆是 `paginator.js` 已公開或可從外部合法觀察的狀態——`containerPosition` 是明確的 public getter/setter（`paginator.js:1977/2005`），直排模式的手指追蹤（`#dragBy`）改變的是 `#container` 直接子元素（`View` 的包裹 `<div>`）的 CSS `transform`（`paginator.js:2160-2166` 已示範這個讀法），透過 `getComputedStyle()` 讀取屬於合法的外部觀察，不需要碰任何私有欄位。
- **已完成的原始碼追蹤（本計畫撰寫時的靜態分析，供 harness 設計參考，非量測結論）**：`#onTouchStart`（`paginator.js:2137`）完全不檢查選取狀態；`#onTouchMove`（`paginator.js:2177`）唯一的選取守衛在第 2191-2195 行（`const selection = doc?.getSelection(); if (selection && selection.rangeCount > 0 && !selection.isCollapsed) return`），這段守衛之後才是位移邏輯（第 2229-2237 行：橫排呼叫 `this.scrollBy(dx, 0)`、直排呼叫 `this.#dragBy(dx)`），且位移邏輯本身沒有任何最小位移量（slop）門檻——若守衛檢查當下 `selection` 為空或塌縮（`isCollapsed === true`），會直接放行到位移邏輯執行。`paginator.js:1467-1491` 的 `checkPointerSelection`「選取延伸超出可視範圍自動翻頁」功能因呼叫條件恆假（`!isPointerSelecting && isPointerSelecting`，上游原始碼行內註解確認為刻意停用）已排除為本次症狀成因，不在本計畫測試範圍內。
- **合法的 DOM 結構依據（供 harness 撰寫時定位元素）**：`Paginator` 的 Shadow DOM 內容器元素為 `<div id="container" part="container">`（`paginator.js:1356`，`this.#root.getElementById('container')`）；每個 `View` 是一個 `<div>`（無 id/class）包裹 `<iframe part="filter">`（`paginator.js:570-587`），直接作為 `#container` 的子元素插入。`Paginator` 對 `doc.addEventListener('touchstart'/'touchmove'/'touchend', ...)` 是在每個 section 的 `'load'` 事件內註冊（`paginator.js:1451-1456`），代表任何已載入 section 的 iframe 文件都能接收並觸發這些監聽器。

---

### Task 1: 建立觸控模擬 harness，驗證橫排模式下「選取前」與「選取後」的位移差異

**Files:**
- Create: `tmp/epic-18-issue-47-harness/package.json`
- Create: `tmp/epic-18-issue-47-harness/repro.mjs`
- Create: `tmp/epic-18-issue-47-harness/result.json`（腳本執行後自動產生）

**Interfaces:**
- Consumes: 無（獨立診斷腳本）
- Produces: `result.json` 結構 `{ scenarioA_noSelection: {...}, scenarioB_withSelection: {...}, reproduced: boolean, guardWorksWhenSelected: boolean }`——Task 2 直接讀取這份檔案的欄位進行判讀。`scenarioA_noSelection`/`scenarioB_withSelection` 各自的結構為 `{ containerPositionBefore: number, containerPositionAfter: number, containerPositionMoved: boolean, transformBefore: string|null, transformAfter: string|null, transformChanged: boolean, selectionIsCollapsedAfter: boolean, selectionRangeCountAfter: number } | { error: string }`——`error` 欄位存在時代表 harness 本身未能建立有效的量測條件（找不到文字節點，或 Important #1 的零尺寸 rect 防護觸發），屬於腳本問題需要修正重跑，不是量測結果，Task 2 判讀時需先排除這種情況（見 Task 1 Step 3 Expected 段落）。

- [ ] **Step 1: 建立 harness 目錄與 npm 環境**

```bash
mkdir -p tmp/epic-18-issue-47-harness
cd tmp/epic-18-issue-47-harness
npm init -y
npm install puppeteer
cd ../..
```

Expected: `tmp/epic-18-issue-47-harness/node_modules/puppeteer` 存在，`package.json` 的 `dependencies` 含 `puppeteer` 版本字串，`npm install` 無錯誤結束。

- [ ] **Step 2: 撰寫 `repro.mjs`**

```javascript
// tmp/epic-18-issue-47-harness/repro.mjs
//
// Epic 18 Issue 47 診斷用重現迴圈：驗證 #onTouchMove 在「長按已開始、
// 但瀏覽器原生選取尚未建立」這段空窗期，是否真的會呼叫 scrollBy()/
// #dragBy() 位移內容——這是 issues.md Issue 47 根因假設的直接可證偽
// 預測。透過 Puppeteer request interception 直接伺服真實 vendored 資源，
// 完全不修改 main.js/paginator.js/view.js 任何一行。

import puppeteer from 'puppeteer'
import { readFile, writeFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const FOLIATE_DIR = path.resolve(
  __dirname,
  '../../app/android/app/src/main/assets/foliate',
)
const FIXTURE_EPUB = path.resolve(
  __dirname,
  '../../app/test/fixtures/issue9_vertical_pagejump.epub',
)
const ORIGIN = 'https://appassets.androidplatform.net'

// 本 harness 的請求攔截實際只會命中兩類請求：(a) foliate 引擎本身的
// index.html/*.js；(b) book/current.epub（另有專屬分支處理）。EPUB 書本
// 內部資源由 epub.js 透過 URL.createObjectURL() 轉成 blob: URL 在瀏覽器
// 記憶體內解析，從未經過這裡的 request interception（已於 Issue 45
// 診斷時查證，見 epub.js:554/860/922/1082/1279），故只需要這兩種 MIME。
const MIME = { '.html': 'text/html', '.js': 'text/javascript' }

async function listFilesRecursive(dir, base = dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) files.push(...(await listFilesRecursive(full, base)))
    else files.push(path.relative(base, full).split(path.sep).join('/'))
  }
  return files
}

async function main() {
  const relFiles = await listFilesRecursive(FOLIATE_DIR)
  const fileMap = new Map()
  for (const rel of relFiles) {
    fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)))
  }
  const fixtureBuf = await readFile(FIXTURE_EPUB)

  const browser = await puppeteer.launch({ headless: true })
  try {
    const page = await browser.newPage()
    await page.setRequestInterception(true)

    page.on('request', (req) => {
      const url = new URL(req.url())
      if (url.origin !== ORIGIN) {
        req.continue()
        return
      }
      if (url.pathname === '/book/current.epub') {
        req.respond({ status: 200, contentType: 'application/epub+zip', body: fixtureBuf })
        return
      }
      const pathname = url.pathname === '/' ? '/index.html' : url.pathname
      const rel = pathname.replace(/^\//, '')
      const buf = fileMap.get(rel)
      if (!buf) {
        req.respond({ status: 404, body: '' })
        return
      }
      const ext = path.extname(rel)
      req.respond({ status: 200, contentType: MIME[ext] || 'application/octet-stream', body: buf })
    })
    page.on('pageerror', (err) => console.error('[pageerror]', err))

    await page.evaluateOnNewDocument(() => {
      window.__harnessEvents = []
      window.flutter_inappwebview = {
        callHandler: async (name, ...args) => {
          window.__harnessEvents.push({ name, args, t: performance.now() })
        },
      }
    })

    const initialPrefs = {
      writingMode: 'horizontal',
      fontSize: 1.0,
      lineHeight: 1.0,
      paragraphSpacing: 1.0,
      marginTop: 32,
      marginBottom: 16,
      marginLeft: 24,
      marginRight: 24,
      pageTurnMode: 'paginated',
      columnMode: 'auto',
      columnSize: 720,
    }
    const openUrl =
      `${ORIGIN}/index.html?prefs=${encodeURIComponent(JSON.stringify(initialPrefs))}` +
      `&fontFaceCss=&initialCfi=`
    await page.setViewport({ width: 800, height: 1200, hasTouch: true })
    await page.goto(openUrl, { waitUntil: 'load' })
    await page.waitForFunction(
      () => window.__harnessEvents.some((e) => e.name === 'onPageRendered'),
      { timeout: 15000 },
    )

    // 在頁面內部直接 dispatch 真實 TouchEvent（而非透過 Puppeteer 的高階
    // 觸控模擬 API），確保測的是 paginator.js 真正註冊的 'touchstart'/
    // 'touchmove' 監聽器邏輯本身，不受瀏覽器 OS 層級手勢辨識（例如真的
    // 長按選字 UI）的不確定性影響——這正是本測試要驗證的東西：「選取
    // 尚未建立」這個狀態本身，不需要真的觸發瀏覽器原生選字。
    async function simulateTouchDrag({ deltas, preEstablishSelection }) {
      return page.evaluate(({ deltas, preEstablishSelection }) => {
        const paginator = document.querySelector('foliate-view').renderer
        const container = paginator.shadowRoot.getElementById('container')
        const iframe = container.querySelector('iframe')
        const doc = iframe.contentDocument
        const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
        let textNode = null
        while (walker.nextNode()) {
          if (walker.currentNode.nodeValue?.trim().length > 10) {
            textNode = walker.currentNode
            break
          }
        }
        if (!textNode) return { error: 'no text node found' }
        const range = doc.createRange()
        range.setStart(textNode, 0)
        range.setEnd(textNode, Math.min(5, textNode.nodeValue.length))
        const rect = range.getBoundingClientRect()
        // 審查意見 Important #1：若字型尚未載入完成（View.load() 的
        // fontReady 只是賦值、並未在渲染前 await，見 view.js/paginator.js
        // 既有行為），這裡量到的 rect 可能是 0×0，會讓後續觸控座標全部
        // 落在 (0,0)、量測失去意義。
        if (!rect || (rect.width === 0 && rect.height === 0)) {
          return { error: 'range bounding rect is zero-sized or invalid' }
        }
        const startX = rect.left + rect.width / 2
        const startY = rect.top + rect.height / 2

        if (preEstablishSelection) {
          const sel = doc.getSelection()
          sel.removeAllRanges()
          const selRange = doc.createRange()
          selRange.setStart(textNode, 0)
          selRange.setEnd(textNode, Math.min(8, textNode.nodeValue.length))
          sel.addRange(selRange)
        } else {
          doc.getSelection()?.removeAllRanges()
        }

        const makeTouch = (x, y) => new Touch({
          identifier: 1,
          target: doc.body,
          clientX: x, clientY: y,
          screenX: x, screenY: y,
          pageX: x, pageY: y,
        })

        const containerPositionBefore = paginator.containerPosition
        const primaryEl = container.children[0]
        const transformBefore = primaryEl ? getComputedStyle(primaryEl).transform : null

        let t = performance.now()
        const dispatch = (type, x, y) => {
          const touch = makeTouch(x, y)
          const ev = new TouchEvent(type, {
            touches: type === 'touchend' ? [] : [touch],
            changedTouches: [touch],
            targetTouches: type === 'touchend' ? [] : [touch],
            bubbles: true,
            cancelable: true,
            composed: true,
          })
          Object.defineProperty(ev, 'timeStamp', { value: (t += 16) })
          doc.body.dispatchEvent(ev)
        }

        dispatch('touchstart', startX, startY)
        let x = startX
        let y = startY
        for (const [dx, dy] of deltas) {
          x += dx
          y += dy
          dispatch('touchmove', x, y)
        }

        // 審查意見 Critical #1：量測點刻意放在 touchmove 迴圈結束、
        // dispatch('touchend', ...) **之前**——本測試要證明/推翻的是
        // 「touchmove 期間內容有沒有位移」，不是「手勢結束後最終停在
        // 哪裡」。#onTouchEnd() 觸發的 snap()（paginator.js:2533，透過
        // requestAnimationFrame 延遲呼叫）與 #settleDrag() 都可能把
        // 位移復原；即使本函式目前是同步呼叫、touchend 之後緊接著讀值
        // 理論上還搶在那個延遲的 rAF 回呼之前，把量測點放在 touchend
        // 之前仍然是更穩健、語意也更正確的作法——不依賴「同步讀取剛好
        // 搶先於 rAF」這個容易被未來改動破壞的時序巧合。
        const containerPositionAfter = paginator.containerPosition
        const transformAfter = primaryEl ? getComputedStyle(primaryEl).transform : null
        const selectionAfter = doc.getSelection()

        // touchend 仍要照常送出，讓 #touchScrolled/#touchState 等內部
        // 手勢狀態正確收尾，避免污染到同一支腳本內下一次
        // simulateTouchDrag() 呼叫的 #onTouchStart() 判斷。
        dispatch('touchend', x, y)

        return {
          containerPositionBefore,
          containerPositionAfter,
          containerPositionMoved: containerPositionBefore !== containerPositionAfter,
          transformBefore,
          transformAfter,
          transformChanged: transformBefore !== transformAfter,
          selectionIsCollapsedAfter: selectionAfter?.isCollapsed,
          selectionRangeCountAfter: selectionAfter?.rangeCount,
        }
      }, { deltas, preEstablishSelection })
    }

    // 情境 A：長按候選期間（尚未建立選取，doc.getSelection() 為空/塌縮）
    // 就開始小幅位移——對應根因假設描述的「空窗期」，模擬手指長按時的
    // 自然微幅晃動（5 個累加位移，每次 3~5px）。
    const deltasSmall = [[3, 0], [5, 0], [8, 0], [12, 0], [15, 0]]
    const scenarioA_noSelection = await simulateTouchDrag({
      deltas: deltasSmall,
      preEstablishSelection: false,
    })
    console.log('情境 A（無選取，模擬長按候選期間位移）:', JSON.stringify(scenarioA_noSelection, null, 2))

    // 情境 B（對照組）：選取已經確立（non-collapsed）之後才發生同樣的
    // touchmove 位移——驗證既有守衛（selection.isCollapsed 檢查）在選取
    // 已確立時確實生效，藉此把「差異純粹來自選取尚未建立的時機」與
    // 「守衛整體失效」兩種可能性區分開來。
    const scenarioB_withSelection = await simulateTouchDrag({
      deltas: deltasSmall,
      preEstablishSelection: true,
    })
    console.log('情境 B（已有選取，對照組）:', JSON.stringify(scenarioB_withSelection, null, 2))

    const result = {
      scenarioA_noSelection,
      scenarioB_withSelection,
      // 核心判讀：情境 A 應該要位移（重現根因假設），情境 B 不應該位移
      // （既有守衛正常運作）。兩者同時成立才是完整、可信的重現證據。
      reproduced: scenarioA_noSelection.containerPositionMoved === true,
      guardWorksWhenSelected: scenarioB_withSelection.containerPositionMoved === false,
    }
    console.log(JSON.stringify(result, null, 2))
    await writeFile(path.join(__dirname, 'result.json'), JSON.stringify(result, null, 2))

    process.exitCode = result.reproduced && result.guardWorksWhenSelected ? 1 : 0
  } finally {
    await browser.close()
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
```

- [ ] **Step 3: 執行腳本，確認完整跑完不崩潰**

```bash
cd tmp/epic-18-issue-47-harness
node repro.mjs
echo "exit code: $?"
cd ../..
```

Expected: stdout 印出情境 A／B 兩組完整 JSON（`containerPositionBefore`/`containerPositionAfter`/`containerPositionMoved` 等欄位皆為具體數值/布林值，非 `undefined`；若看到 `{"error": "range bounding rect is zero-sized or invalid"}` 代表 Important #1 的防護觸發，需要調整 Step 3 的等待時機或改選其他文字節點，同樣視為 harness 問題不得帶著這種結果判讀），接著印出完整 `result.json` 內容。`exit code: 1` 代表兩項判讀（`reproduced`＋`guardWorksWhenSelected`）皆成立（即完整重現根因假設）；`exit code: 0` 代表至少一項不成立；`exit code: 2` 或任何未攔截的例外堆疊代表 harness 本身有問題（例如找不到文字節點、`Touch`/`TouchEvent` 建構失敗），需要修正腳本後重跑，不得直接跳到 Task 2。

- [ ] **Step 4: 連續重跑 3 次確認結果穩定**

```bash
cd tmp/epic-18-issue-47-harness
for i in 1 2 3; do node repro.mjs 2>&1 | tail -20; done
cd ../..
```

Expected: 3 次執行的 `result.json`（或 stdout 印出的 JSON）內容逐位元組一致——比照 Issue 45 診斷時的教訓（`tmp/epic-18/review-plan-issue-45-round2.md`），不穩定的量測結果不能直接採信。若 3 次結果不一致，需要先排查原因（例如文字節點選取邏輯是否每次選到不同節點）才能進入 Task 2，不得帶著不穩定的數據做判讀。

---

### Task 2: 延伸至直排模式，判讀結果並產出診斷報告

**Files:**
- Modify: `tmp/epic-18-issue-47-harness/repro.mjs`（新增直排情境，複用 Task 1 的 `simulateTouchDrag()`）
- Create: `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md`
- Modify: `docs/epics/epic-18-reader-device-qa/issues.md`（Issue 47 段落）

**Interfaces:**
- Consumes: Task 1 的 `simulateTouchDrag()` 函式（簽章不變：`{deltas, preEstablishSelection} => Promise<{containerPositionBefore, containerPositionAfter, containerPositionMoved, transformBefore, transformAfter, transformChanged, selectionIsCollapsedAfter, selectionRangeCountAfter}>`）
- Produces: 無（本 Task 為文件產出，不影響任何程式碼介面）

- [ ] **Step 1: 在 `repro.mjs` 新增直排情境（切換 writingMode 後重跑同樣的兩組測試）**

在 `main()` 內，緊接在 Task 1 Step 2 的 `const result = { scenarioA_noSelection, ... }` 這個區塊**之後**、`console.log(JSON.stringify(result, null, 2))` 這一行**之前**插入以下程式碼（`Global Constraints` 已說明直排模式的位移改讀 `transformChanged`，而非 `containerPositionMoved`——`#dragBy()` 平移的是 `#container` 的直接子元素，不是 `#container` 本身的捲動位置；插入點必須在 `console.log`/`writeFile` 之前，否則新增的四個欄位不會出現在最終印出與寫入的 `result.json` 內）：

**審查修正（Critical #2）**：原本用固定 `setTimeout(300)` 等待切換完成，審查報告正確指出這不可靠；但審查報告建議改等第二次 `onPageRendered` 事件**不可行**——`onPageRendered` 是 `main.js` 的 `{once:true}` 監聽器（`main.js:481` 附近，FR-06 那段），整個頁面生命週期只會 dispatch 一次，第二次切換後永遠不會再觸發，用它等待會直接卡到 15000ms 逾時。改為沿用 Issue 45 已驗證過的模式（`bugfix-repro-issue-45.md`／`repro-prev.mjs` 的 `waitForRelocateSettle` 概念）：`onLocatorChanged` 是持續性監聽器（無 `{once:true}`），`view.goTo()`（Issue 45 修法內建的自我修正路徑）不論走哪個分支最終都會產生至少一次新的 `relocate` 事件，等待這個次數增加即可正確判斷切換完成：

```javascript
    // 直排情境：先切換 writingMode 為 vertical（沿用 Issue 45 已修復的
    // view.goTo() 路徑，這裡不是本次測試對象，只是換一個乾淨的直排
    // 環境）。#dragBy() 平移的是 View 元素的 CSS transform，不是
    // containerPosition，故直排情境改用 transformChanged 判讀。
    const relocateCountBeforeSwitch = await page.evaluate(
      () => window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged').length,
    )
    await page.evaluate((prefs) => window.applyPreferences(prefs), {
      ...initialPrefs,
      writingMode: 'vertical',
    })
    await page.waitForFunction(
      (before) =>
        window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged').length > before,
      { timeout: 15000 },
      relocateCountBeforeSwitch,
    )

    const scenarioC_verticalNoSelection = await simulateTouchDrag({
      deltas: deltasSmall,
      preEstablishSelection: false,
    })
    console.log('情境 C（直排、無選取）:', JSON.stringify(scenarioC_verticalNoSelection, null, 2))

    const scenarioD_verticalWithSelection = await simulateTouchDrag({
      deltas: deltasSmall,
      preEstablishSelection: true,
    })
    console.log('情境 D（直排、已有選取，對照組）:', JSON.stringify(scenarioD_verticalWithSelection, null, 2))

    result.scenarioC_verticalNoSelection = scenarioC_verticalNoSelection
    result.scenarioD_verticalWithSelection = scenarioD_verticalWithSelection
    result.reproducedVertical = scenarioC_verticalNoSelection.transformChanged === true
    result.guardWorksWhenSelectedVertical = scenarioD_verticalWithSelection.transformChanged === false
```

同步修改 Step 3 的 exit code 判斷（Task 1 版本只看橫排兩項）：

```javascript
    process.exitCode = result.reproduced && result.guardWorksWhenSelected
      && result.reproducedVertical && result.guardWorksWhenSelectedVertical ? 1 : 0
```

- [ ] **Step 2: 重新執行並連續重跑 3 次確認四組情境結果皆穩定**

```bash
cd tmp/epic-18-issue-47-harness
for i in 1 2 3; do node repro.mjs 2>&1 | tail -40; done
cd ../..
```

Expected: 每次執行都印出情境 A／B／C／D 四組完整 JSON，3 次重跑逐位元組一致。

- [ ] **Step 3: 判讀結果**

判讀規則：
- `reproduced === true` 且 `guardWorksWhenSelected === true`（橫排）：量化確認「選取尚未建立的空窗期會位移內容、選取已確立後守衛正常擋下」，即根因假設成立。
- `reproducedVertical`／`guardWorksWhenSelectedVertical`（直排）比照橫排邏輯判讀，兩種模式若结果不一致（例如橫排重現但直排未重現），需在報告中如實記錄、不得合併成單一結論。
- 任一組 `reproduced*` 為 `false`：代表在本次測試條件下未觀察到該模式的位移異常，需在報告中列出可能原因（例如本 harness 用同步 `dispatchEvent()` 而非真正的非同步觸控序列，時序上與真機/瀏覽器原生手勢辨識可能有落差），不得為了呼應原假設而曲解數據。

- [ ] **Step 4: 撰寫診斷報告 `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md`**

以下述模板為基礎撰寫，`{{ }}` 標記處填入 Task 1/2 `result.json` 的實際數值：

```markdown
# Bugfix Repro：Issue 47 — 流式 EPUB 劃線拖曳選取時頁面亂跳

## 症狀

使用者回報：劃線拖曳選取時頁面亂跳（截圖 `tmp/images/畫線亂跳.jpg`），原判定為 PDF 專屬（`epic-24-pdf-engine-rebuild` Issue 9），追加確認流式 EPUB 也會發生同一症狀（與 PDF 版本根因不同）。

## 重現方式

`tmp/epic-18-issue-47-harness/repro.mjs`（Puppeteer + headless Chromium，未進版控），透過 request interception 直接伺服 `app/android/app/src/main/assets/foliate/` 真實 vendored 資源與既有測試 fixture `issue9_vertical_pagejump.epub`，在書本內文的 iframe 文件上直接 `dispatchEvent()` 真實 `TouchEvent`（touchstart/touchmove/touchend），測試 `paginator.js` 已註冊的 `'touchmove'` 監聽器邏輯本身，量測「選取尚未建立」與「選取已確立」兩種情境下同樣小幅位移是否分別造成內容位移。

## 量測數據（連續 3 次重跑結果一致）

- 情境 A（橫排、無選取）：`containerPositionBefore={{ }}`、`containerPositionAfter={{ }}`、`containerPositionMoved={{ }}`
- 情境 B（橫排、已有選取，對照組）：`containerPositionMoved={{ }}`
- 情境 C（直排、無選取）：`transformBefore={{ }}`、`transformAfter={{ }}`、`transformChanged={{ }}`
- 情境 D（直排、已有選取，對照組）：`transformChanged={{ }}`
- 判讀：`reproduced={{ }}`、`guardWorksWhenSelected={{ }}`、`reproducedVertical={{ }}`、`guardWorksWhenSelectedVertical={{ }}`

## 結論

`{{ 依 Step 3 判讀結果填入：完整重現／部分重現／未重現，並說明對應的下一步 }}`
```

- [ ] **Step 5: 更新 `issues.md` Issue 47 段落**

依 Step 3 判讀結果，更新 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 47 的 `**Status:**` 那一行（若完整重現，改為 `ready-for-agent` 並附量測證據摘要；若未重現或結果不一致，改為 `needs-info` 並說明下一步建議，例如改用真機或 Puppeteer 的 CDP `Input.dispatchTouchEvent` 搭配更貼近真實的非同步時序重測）。

- [ ] **Step 6: Commit（僅 `issues.md` 與新增的診斷報告，不含 `tmp/` 內容）**

```bash
git add docs/epics/epic-18-reader-device-qa/issues.md
git add docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md
git status
```

Expected: `git status` 只顯示上述兩個檔案為 staged，`tmp/epic-18-issue-47-harness/` 不出現在任何 git 狀態輸出中。確認無誤後由人類決定是否執行 `git commit`。
