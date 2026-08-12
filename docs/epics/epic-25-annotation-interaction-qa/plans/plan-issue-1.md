# Epic 25 Issue 1 — 畫線選取已確立仍跳頁（裝置相關）診斷資料蒐集計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 這**不是**修復計畫——Issue 1 目前狀態是 `needs-info`：只有排序過的根因假說，沒有已知修法，且無法用 headless Chromium 建立可靠重現迴圈（真機 WebView 選取控點拖曳行為的裝置差異，CDP 模擬不具代表性）。本計畫的目標是在 `main.js` 加入暫時性除錯插樁，讓使用者能在 Air Reader Pro C（會重現）與 TCL 14 吋（不會重現）兩台真機上，透過本專案既有的「閱讀器 Console Log」診斷畫面（`epic-18-reader-device-qa` Issue 33 已建置，不需要 USB/ADB 連線）擷取拖曳控點期間的選取狀態與內容位置時序資料。拿到兩台裝置的比對資料後，才能在**下一輪**另立計畫鎖定真正根因並設計修法。

**Architecture:** 在 `main.js` 既有的 `view.addEventListener('load', (e) => { const doc = e.detail.doc; ... })` hook 內（`epic-18` Issue 47 修復程式碼所在的同一個 hook），新增一組**純觀察**的 capture 階段 `touchstart`/`touchmove` 監聽器——不呼叫 `preventDefault()`/`stopPropagation()`，不影響任何既有行為，只用 `console.log()` 記錄每個 touchmove 當下的 `selection.rangeCount`/`isCollapsed`、觸控座標、與 `view.renderer.containerPosition`（比照 `epic-18` Issue 45/47 診斷時使用的同一個公開 getter）。`console.log` 輸出已透過既有的 `InAppWebView.onConsoleMessage` → `handleFoliateConsoleMessage` → `ReaderConsoleLog` 管線，自動出現在「設定」→「閱讀器 Console Log」畫面，使用者可直接點「複製全部」取得文字回報，不需另外連接電腦除錯。

**Tech Stack:** vendored `foliate-js` 整合層 `main.js`（純 JS，ADR 0011 無侵入原則——完全不修改 `paginator.js`/`view.js` 等 vendored 檔案本體）；Puppeteer + headless Chromium（CDP `Input.dispatchTouchEvent`）僅用於驗證插樁本身不出錯、不影響既有行為，**不**用於重現 Issue 1 本身的裝置差異症狀（headless 環境無法代表真機 WebView 差異，比照 `epic-18` Issue 1／`epic-25` design.md 已記錄的限制）。

## Global Constraints

- 完全不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js` 等）——只在 `main.js` 既有的整合層 hook 內新增程式碼（ADR 0011）。
- 新增的插樁監聽器**必須是純觀察**：不得呼叫 `evt.preventDefault()`／`evt.stopPropagation()`／`evt.stopImmediatePropagation()`，也不得修改任何 DOM/選取狀態——目的是觀察既有行為（含 bug 本身），不能因插樁本身改變症狀是否出現。
- 插樁訊息一律用唯一標籤 `[DEBUG-e25i1]` 開頭（比照 `/diagnose` 技能 Phase 4「Tag every debug log with a unique prefix」慣例），方便日後用 `grep` 一次性清除。
- `touchmove` 事件頻率極高（每秒 60-120 次），插樁**不得**無條件記錄每一影格——`ReaderConsoleLog` 只保留最新 500 筆（`reader_console_log.dart` 的 `_maxEntries`），超過會捨棄最舊的紀錄；單次 2-3 秒的拖曳手勢若每影格都記錄可能產生上百條 log，Task 2 手冊又要求同一手勢至少重複 2 次，未節流會有洗掉早期關鍵紀錄的風險。插樁只在「內容真的位移」「選取狀態改變」「手勢的第一個 touchmove（基準線）」三種情況才輸出。
- 本計畫**不會**移除插樁——插樁的移除必須排在「已取得兩台真機資料、鎖定根因」之後的下一輪計畫，因為移除前必須先確認資料已經蒐集完成，不能在還沒拿到真機資料前就自行清理掉還在使用中的診斷工具。
- 本計畫的分支/worktree 建立、真機資料回報後的下一輪根因確認與修復計畫撰寫，皆不在本計畫範圍內。

---

### Task 1：`main.js` 新增暫時性除錯插樁，並用 headless 驗證不影響既有行為

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:642-643`（在 `doc.addEventListener('pointercancel', () => reportSelection())` 之後、`epic-18` Issue 47 修復程式碼區塊的註解與 `LONG_PRESS_GATE_MS` 宣告之前插入——**必須在 Issue 47 攔截器之前**，見下方 Step 1 說明與實作審查 Critical #1）
- Test: `tmp/epic-25-issue-1-harness/smoke.mjs`（新建，Puppeteer 腳本，不進版控——比照 `tmp/epic-18-issue-47-harness/` 既有慣例，`tmp/` 已在 `.gitignore`）

**Interfaces:**
- Consumes：`view`（`main.js:4` 頂層 `const view = document.getElementById('view')`，於整份檔案作用域內皆可存取）、`view.renderer.containerPosition`（`paginator.js:1977` 公開 getter，`epic-18` Issue 45/47 診斷已驗證用法）。
- Produces：無新增可供其他 Task 呼叫的函式（本計畫僅此一組插樁監聽器，Task 2 是文件產出，不依賴程式介面）。

- [x] **Step 1：在 `main.js` 插入除錯插樁**

修改 `app/android/app/src/main/assets/foliate/main.js`，在 `doc.addEventListener('pointercancel', () => reportSelection())` 之後、`epic-18` Issue 47 修復程式碼區塊（`// Epic 18 Issue 47 修復：...` 註解起）之前，插入：

**【實作審查修正 Critical #1，見 `tmp/epic-25/review-issue-1-implementation.md`】必須註冊在 Issue 47 攔截器之前，不能之後**：兩者是同一個 `doc` 節點、同一個事件類型、同一個 `capture` 階段的監聽器，同節點同階段的監聽器按註冊順序依序執行；`stopImmediatePropagation()` 一旦被呼叫，會讓「呼叫當下尚未執行」的其餘監聽器整個不會被呼叫（不論哪個階段），已執行過的監聽器不受影響。真機測試已證實：插樁若註冊在 Issue 47 攔截器之後，長按候選期間（Issue 47 攔截器判定為候選、呼叫 `stopImmediatePropagation()` 的那些 `touchmove`）插樁會完全收不到事件、整段靜音——這正是使用者真機回報「任何畫線都沒有其他 LOG」的根因之一。

```javascript
      // Epic 25 Issue 1 暫時性除錯插樁 [DEBUG-e25i1]：觀察選取已確立（拖曳
      // 控點期間）是否仍會位移內容，鎖定「Air Reader Pro C 會跳頁、TCL 14吋
      // 不會」的裝置相關根因（見
      // docs/epics/epic-25-annotation-interaction-qa/issues.md Issue 1）。
      // 純觀察用 capture 階段監聽器，不呼叫 preventDefault()/
      // stopPropagation()，不修改任何 DOM/選取狀態，不影響既有行為——目的
      // 是觀察症狀本身，不能因插樁改變症狀是否出現。透過既有「閱讀器
      // Console Log」診斷畫面（epic-18 Issue 33）在真機上擷取，不需要
      // USB/ADB 連線。確認根因、產出修復計劃後需整段移除（見
      // plan-issue-1.md Task 2 的真機資料回報流程，移除排在下一輪計畫）。
      //
      // 節流（審查報告 Issue 2）：touchmove 每秒可達 60-120 次，若每一
      // 影格都記錄，2-3 秒的拖曳手勢就會產生上百條 log，可能洗掉
      // ReaderConsoleLog 500 筆上限內較早的紀錄。只在「內容真的位移」
      // （moved）、「選取狀態改變」（selectionKey 變動）、或「這次手勢的
      // 第一個 touchmove」（debugE25I1LastLoggedKey === null，確保每次
      // 手勢至少留下一筆基準線）時才輸出。
      //
      // 【審查修正 Critical #1，見 tmp/epic-25/review-issue-1-implementation.md】
      // 必須註冊在 Epic 18 Issue 47 攔截器之前：兩者是同一個 doc 節點、
      // 同一個事件類型、同一個 capture 階段的監聽器，同節點同階段的監聽器
      // 按註冊順序依序執行；stopImmediatePropagation() 一旦被呼叫，會讓
      // 「呼叫當下尚未執行」的其餘監聽器整個不會被呼叫（不論哪個階段），
      // 已執行過的監聽器不受影響。若插樁註冊在 Issue 47 攔截器之後，長按
      // 候選期間（Issue 47 攔截器判定為候選、呼叫 stopImmediatePropagation
      // 的那些 touchmove）插樁會完全收不到事件、整段靜音。
      let debugE25I1LastPosition = null
      let debugE25I1LastLoggedKey = null
      doc.addEventListener('touchstart', () => {
        debugE25I1LastPosition = null
        debugE25I1LastLoggedKey = null
      }, { capture: true })
      doc.addEventListener('touchmove', (evt) => {
        const touch = evt.touches[0]
        if (!touch) return
        const selection = doc.getSelection()
        const rangeCount = selection?.rangeCount ?? 0
        const isCollapsed = selection?.isCollapsed
        const position = view.renderer.containerPosition
        const moved = debugE25I1LastPosition !== null && position !== debugE25I1LastPosition
        debugE25I1LastPosition = position
        const selectionKey = `${rangeCount}:${isCollapsed}`
        const isFirstLog = debugE25I1LastLoggedKey === null
        if (!moved && !isFirstLog && selectionKey === debugE25I1LastLoggedKey) return
        debugE25I1LastLoggedKey = selectionKey
        console.log(
          `[DEBUG-e25i1] t=${evt.timeStamp.toFixed(0)} ` +
          `rangeCount=${rangeCount} isCollapsed=${isCollapsed} ` +
          `x=${touch.screenX.toFixed(1)} y=${touch.screenY.toFixed(1)} ` +
          `containerPosition=${position} moved=${moved}`
        )
      }, { capture: true })
```

- [x] **Step 2：建立 headless 驗證腳本**

新建 `tmp/epic-25-issue-1-harness/smoke.mjs`（若 `tmp/epic-25-issue-1-harness/` 目錄不存在需先建立；`package.json`/`node_modules` 可比照 `tmp/epic-18-issue-47-harness/` 既有安裝，或在此目錄下另跑 `npm init -y && npm install puppeteer`）：

```javascript
// Epic 25 Issue 1 — 除錯插樁 smoke test（Puppeteer + headless Chromium）
//
// 目的：驗證新增的 [DEBUG-e25i1] 插樁本身（1）不會拋出例外、（2）不會
// 改變既有行為——headless 環境下「選取已確立」情境本應由 paginator.js
// 既有守衛正確擋下位移（比照 epic-18 Issue 47 診斷報告 Scenario B），插樁
// 前後這個基準行為必須維持一致；（3）log 格式正確、可被解析。
//
// 明確不做的事：不嘗試重現 Issue 1 本身的裝置差異症狀——headless Chromium
// 無法代表真機 WebView 差異，重現與否需要真機（見 Task 2）。

import puppeteer from 'puppeteer'
import { readFile, readdir } from 'node:fs/promises'
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
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }

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

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] })
  try {
    const page = await browser.newPage()
    await page.setRequestInterception(true)

    page.on('request', (req) => {
      const url = new URL(req.url())
      if (url.origin !== ORIGIN) { req.continue(); return }
      if (url.pathname === '/book/current.epub') {
        req.respond({ status: 200, contentType: 'application/epub+zip', body: fixtureBuf }); return
      }
      const pathname = url.pathname === '/' ? '/index.html' : url.pathname
      const rel = pathname.replace(/^\//, '')
      const buf = fileMap.get(rel)
      if (!buf) { req.respond({ status: 404, body: '' }); return }
      const ext = path.extname(rel)
      req.respond({ status: 200, contentType: MIME[ext] || 'application/octet-stream', body: buf })
    })

    const pageErrors = []
    page.on('pageerror', (err) => pageErrors.push(String(err)))

    const debugLogs = []
    page.on('console', (msg) => {
      const text = msg.text()
      if (text.includes('[DEBUG-e25i1]')) debugLogs.push(text)
    })

    await page.evaluateOnNewDocument(() => {
      window.__harnessEvents = []
      window.flutter_inappwebview = {
        callHandler: async (name, ...args) => {
          window.__harnessEvents.push({ name, args, t: performance.now() })
        },
      }
    })

    const initialPrefs = {
      writingMode: 'horizontal', fontSize: 1.0, lineHeight: 1.0,
      paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16,
      marginLeft: 24, marginRight: 24,
      pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
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

    await page.evaluate(() => {
      const fv = document.querySelector('foliate-view')
      fv?.renderer?.nextPage?.()
    })
    await new Promise((r) => setTimeout(r, 1500))

    await page.waitForFunction(() => {
      const fv = document.querySelector('foliate-view')
      const container = fv?.renderer?.shadowRoot?.getElementById('container')
      const iframes = container?.querySelectorAll('iframe') ?? []
      for (const iframe of iframes) {
        const doc = iframe.contentDocument
        if (!doc?.body) continue
        if ((doc.body.textContent?.trim() ?? '').length > 20) return true
      }
      return false
    }, { timeout: 10000 })

    await page.waitForFunction(() => {
      const fv = document.querySelector('foliate-view')
      const renderer = fv?.renderer
      if (!renderer) return false
      const pos = renderer.containerPosition
      renderer.scrollBy(1, 0)
      const changed = renderer.containerPosition !== pos
      if (changed) renderer.scrollBy(-1, 0)
      return changed
    }, { timeout: 15000 })

    // 建立選取（比照 epic-18 Issue 47 harness 的 Scenario B 手法），並回傳
    // 選取文字的頁面座標。
    //
    // 【審查修正 Important #4，見 tmp/epic-25/review-issue-1-implementation.md】
    // 觸控落點原本用整個 paginator 容器的正中央，不在選取文字範圍內；實測
    // 發現 CDP 一送出 touchStart，選取立刻被清掉（原生行為：點擊選取範圍
    // 以外的地方會清除選取），導致後續整段拖曳其實是在「沒有選取」的狀態
    // 下進行的，`before === after` 驗證到的並非文件宣稱的「選取已確立時
    // 既有守衛正確擋下位移」，而是「沒有選取、也沒有其他機制讓內容移動」。
    // 改為對準選取文字的邊界框中心，才是真正的「手指按在已選取文字/控點
    // 上」控制組情境。
    const selectionRect = await page.evaluate(() => {
      const fv = document.querySelector('foliate-view')
      const container = fv?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const doc = iframe?.contentDocument
      if (!doc) return null
      doc.execCommand('selectAll', false, null)
      let sel = doc.getSelection()
      if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
        const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
        let textNode = null
        while (walker.nextNode()) {
          if (walker.currentNode.nodeValue?.trim().length > 10) { textNode = walker.currentNode; break }
        }
        if (textNode) {
          sel.removeAllRanges()
          const range = doc.createRange()
          range.setStart(textNode, 0)
          range.setEnd(textNode, Math.min(8, textNode.nodeValue.length))
          sel.addRange(range)
        }
      }
      sel = doc.getSelection()
      if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null
      const rect = sel.getRangeAt(0).getClientRects()[0]
      if (!rect) return null
      const iframeRect = iframe.getBoundingClientRect()
      return {
        x: iframeRect.left + rect.left + rect.width / 2,
        y: iframeRect.top + rect.top + rect.height / 2,
      }
    })
    if (!selectionRect) {
      console.log('FAIL: 選取未成功建立或無法讀取其邊界框，無法進行控制組測試')
      process.exitCode = 1
      return
    }

    const before = await page.evaluate(() => {
      const fv = document.querySelector('foliate-view')
      return fv?.renderer?.containerPosition
    })

    // CDP 觸控注入模擬拖曳，起點對準已選取文字的中心（而非容器正中央，
    // 見上方 Important #4 說明），比照 epic-18 Issue 47 harness 手法。
    const client = page._client()
    let x = selectionRect.x, y = selectionRect.y
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x, y, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
    })
    await new Promise((r) => setTimeout(r, 50))
    for (const [dx, dy] of [[5, 0], [8, 0], [10, 0], [12, 0], [15, 0]]) {
      x += dx; y += dy
      await client.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [{ x, y, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
      })
      await new Promise((r) => setTimeout(r, 30))
    }
    await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    await new Promise((r) => setTimeout(r, 100))

    const after = await page.evaluate(() => {
      const fv = document.querySelector('foliate-view')
      return fv?.renderer?.containerPosition
    })

    console.log(`pageErrors: ${pageErrors.length}`)
    console.log(`selectionRect: x=${selectionRect.x.toFixed(1)} y=${selectionRect.y.toFixed(1)}`)
    console.log(`debugLogs captured: ${debugLogs.length}`)
    console.log(`containerPosition before=${before} after=${after}`)
    debugLogs.forEach((l) => console.log('  ' + l))

    const formatOk = debugLogs.every((l) =>
      /\[DEBUG-e25i1\] t=\d+ rangeCount=\d+ isCollapsed=(true|false|undefined) x=-?\d+(\.\d+)? y=-?\d+(\.\d+)? containerPosition=-?\d+(\.\d+)? moved=(true|false)/.test(l)
    )

    // 審查修正 Important #4：不能只看格式，還要確認控制組的前提真的成立
    // ——第一筆（基準線）log 必須顯示選取仍然是已確立狀態（rangeCount>0
    // 且 isCollapsed=false），否則代表觸控落點沒有真的對準選取範圍，選取
    // 在觸控當下已經被清掉，整個控制組情境形同虛設。
    const firstLogSelectionEstablished = debugLogs.length > 0
      && /rangeCount=[1-9]\d* isCollapsed=false/.test(debugLogs[0])

    // 節流後，headless 控制組（選取已確立、既有守衛全程擋下位移、選取狀態
    // 不變）預期只留下「第一個 touchmove」的基準線 1 筆；上限 10
    // 則是防止節流邏輯失效導致重新洗版的迴歸守門（審查報告 Issue 2）。
    const ok = pageErrors.length === 0
      && debugLogs.length >= 1
      && debugLogs.length <= 10
      && formatOk
      && firstLogSelectionEstablished
      && before === after // 選取已確立情境，headless 環境下既有守衛應正確擋下位移

    console.log(`\n${ok ? 'PASS' : 'FAIL'}`)
    process.exitCode = ok ? 0 : 1
  } finally {
    await browser.close()
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
```

- [x] **Step 3：安裝 harness 依賴套件（若尚未安裝）**

審查報告 Issue 1：Step 2 的程式碼假設 Puppeteer 已安裝，但新環境/全新目錄下直接執行會因找不到模組而失敗，須先明確安裝。

Run: `cd tmp/epic-25-issue-1-harness && npm init -y && npm install puppeteer`
Expected: 產生 `package.json`／`node_modules/puppeteer`；若目錄下已有 `tmp/epic-18-issue-47-harness/` 那份既有安裝可直接複用（複製 `node_modules`／`package.json`／`package-lock.json` 過來），跳過本步驟。

- [x] **Step 4：執行驗證腳本**

Run: `cd tmp/epic-25-issue-1-harness && node smoke.mjs`
Expected: 印出 `PASS`，exit code 0；`pageErrors: 0`；`debugLogs captured` 介於 1 到 10 之間（節流後，headless 控制組只留下手勢第一個 touchmove 的基準線 1 筆，上限 10 是防止節流邏輯失效的迴歸守門）；第一筆 log 顯示 `rangeCount=1 isCollapsed=false`（審查修正 Important #4：確認觸控落點真的對準已選取文字、控制組前提真的成立）；`containerPosition before=X after=X`（相同值，代表 headless 環境下選取已確立情境的既有守衛行為，加入插樁前後一致，插樁本身沒有引入回歸）。實際執行結果（審查修正後重跑）：`selectionRect: x=210.0 y=757.1`、`debugLogs captured: 1`、`[DEBUG-e25i1] t=1814 rangeCount=1 isCollapsed=false x=252.0 y=858.1 containerPosition=0 moved=false`、`PASS`。

- [x] **Step 5：`flutter analyze` 確認未觸及 Dart 程式碼**

本次修改僅涉及 `main.js`（vendored EPUB 整合層 JS），不涉及任何 Dart 檔案。

Run: `cd app && flutter analyze`
Expected: `No issues found!`（確認本次變更沒有意外觸及 Dart 端）。

- [x] **Step 6：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "debug(epic-25): Issue 1 新增暫時性除錯插樁，觀察拖曳期間選取狀態與內容位置"
```

---

### Task 2：撰寫真機資料蒐集操作手冊，更新 issues.md

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 1 區塊，新增「真機資料蒐集步驟」小節）

**Interfaces:**
- Consumes：Task 1 產出的 `[DEBUG-e25i1]` 插樁（已隨 debug build 部署到裝置）。
- Produces：無程式介面——本 Task 的產出是給人類操作的文字步驟，供人類在兩台真機上實際執行後，將擷取到的 log 文字回報回來，供下一輪根因確認使用。

- [x] **Step 1：在 `issues.md` Issue 1 區塊新增操作手冊**

在 `docs/epics/epic-25-annotation-interaction-qa/issues.md` 的「## Issue 1」區塊內，「**下一步（Planning 前需先完成）**」段落之後，新增：

```markdown
**真機資料蒐集步驟（`plan-issue-1.md` Task 1 完成後可執行）：**

1. 用含 `[DEBUG-e25i1]` 插樁的 debug build（`flutter build apk --debug`）分別安裝到
   Air Reader Pro C 與 TCL 14 吋兩台裝置。
2. 兩台裝置分別開啟同一本流式 EPUB（建議用同一本書、同一個章節位置，降低
   非裝置因素造成的差異）。
3. 長按選取一段文字（例如 5-10 個字），確認選取控點已顯示於左右兩側
   （即選取已確立的狀態）。
4. 用手指拖曳其中一個控點，同時留意畫面是否出現跳頁/位移。**請至少各嘗試
   一次「緩慢」與「明顯較快」兩種拖曳速度**（實作審查
   `tmp/epic-25/review-issue-1-implementation.md` 發現：headless 環境下
   緩慢小幅度的 touchmove 序列，有機率完全不被瀏覽器派發到 JS 層級，只測
   單一慢速手勢可能系統性地採不到任何資料），並在回報時註記每次操作的
   拖曳速度主觀感受。
5. 完成拖曳後，進入「設定」→「閱讀器 Console Log」，點擊右上角「複製全部」
   按鈕，將剪貼簿內容貼到文字檔或直接回報；同步註記該次測試使用的版面
   設定（直排/橫排、單頁/雙頁），以利後續交叉分析是否為版面相關變因。
6. 兩台裝置各重複步驟 3-5 至少 2 次（同一手勢多測幾次，避免單次操作的
   偶然性），並记錄「當下是否有觀察到跳頁」對應到哪一次操作。
7. 將兩台裝置的 log 檔案／文字回報回來，交叉比對 `rangeCount`／
   `isCollapsed`／`containerPosition`／`moved` 欄位在兩台裝置上的差異
   （特別留意 `moved=true` 但 `rangeCount>0 && isCollapsed=false`
   同時成立的行——這代表「選取明明已確立，內容卻仍位移」，是本 Issue
   要鎖定的確切症狀）。

**下一輪（拿到真機資料後）**：依比對結果撰寫 `bugfix-repro-issue-1.md`
確認根因，另立修復計畫；本插樁需在修復計畫的 Cleanup 階段整段移除
（`grep -rn "DEBUG-e25i1"` 確認清除乾淨）。
```

- [x] **Step 2：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 1 補上真機資料蒐集操作手冊"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 1 的「下一步」要求（真機插樁、差異比對）由 Task 1（插樁本體＋不影響既有行為的驗證）與 Task 2（操作手冊）完整涵蓋。
- **No Placeholders 掃描**：兩個 Task 的程式碼與文件內容皆為可直接套用的完整內容，無 TBD/待補。
- **型別/介面一致性**：僅本計畫單一組插樁程式碼，無跨 Task 介面落差疑慮。
- **範圍誠實聲明**：本計畫刻意不包含「鎖定根因」與「撰寫修復」——這兩步依賴 Task 2 蒐集回來的真機資料，屬於下一輪計畫的範圍，不在本計畫內用臆測方式提前完成。
- **審查修訂記錄**（`tmp/epic-25/plan-issue-1-review.md`）：Important #1 補上明確的 `npm install` 步驟（原 Step 3）；Important #2 插樁改為節流記錄（只在位移/選取狀態改變/手勢首個 touchmove 時輸出），避免洗掉 `ReaderConsoleLog` 500 筆上限內的早期紀錄，smoke test 斷言同步從「≥3」改為「1-10 之間」以符合節流後的預期行為並兼作迴歸守門；Minor 兩項（正則納入 `undefined`、操作手冊補記版面設定）皆已採納。
- **實作結果審查修訂記錄**（`tmp/epic-25/review-issue-1-implementation.md`，`/superpowers:requesting-code-review`）：計畫依原始 Step 1 執行、部署到真機（Air Reader Pro C／自報 UA 為 AiPaper Reader C）後，任何畫線動作皆完全零 `[DEBUG-e25i1]` log 輸出。審查以實測（非純理論）找到 **Critical #1**：插樁監聽器原本註冊在 `epic-18` Issue 47 攔截器**之後**，同一 `doc` 節點、同一 `capture` 階段的監聽器按註冊順序執行，Issue 47 攔截器在長按候選期間呼叫 `stopImmediatePropagation()` 會讓「呼叫當下尚未執行」的插樁監聽器整個收不到事件——已修正為插樁改註冊在 Issue 47 攔截器**之前**（Step 1 的 Files／程式碼區塊已同步更新，實際變更見 `git diff` 的 `main.js:642-643` 插入點）。**Important #4**：`smoke.mjs` 的「選取已確立」控制組情境實測並未真的成立——CDP 觸控落點原本在整個容器正中央（不在選取範圍內），一發送 `touchStart` 選取就被清掉，導致 `before === after` 驗證到的其實是「沒有選取」的情境；已修正為觸控落點對準選取文字的邊界框中心，並新增 `firstLogSelectionEstablished` 斷言確認控制組前提真的成立（第一筆 log 必須顯示 `rangeCount>0 isCollapsed=false`），重跑確認 `PASS`（見 Step 4 記錄的實際輸出）。審查另外提出兩項**尚未能單靠程式碼證實、留待下一輪真機資料佐證**的架構層級假說，已記入 `issues.md` Issue 1（根因假說第 4 點）與 Task 2 操作手冊（第 4 步新增測試不同拖曳速度的要求）：headless 環境下緩慢小幅度 touchmove 序列有機率完全不被瀏覽器派發（Critical #2）；原生選取控點拖曳很可能根本不經過 DOM `touchmove` 事件，若真機資料在修正後仍全程零輸出應優先懷疑此點（Critical #3）。Important #5（plan checkbox 未隨進度勾選）與 Minor 兩項（`containerPosition` 位數格式、`isCollapsed=undefined` 分支說明）已一併採納/勾選。
