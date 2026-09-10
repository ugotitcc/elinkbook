# Epic 25 Issue 4 — 換頁點擊位置與相鄰頁畫線重疊時誤跳出刪除確認對話框 時序驗證計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 這**不是**修復計畫——`issues.md` Issue 4 目前狀態是 `needs-triage`：根因只是原始碼層級的假說，尚未用 headless CDP 或真機驗證過實際時序，且明確建議「先建立 headless 重現迴圈驗證時序後再定案修法，避免像 Epic 18 Issue 47 一樣在計畫審查階段才發現時序假設有誤」（人類已確認採用此方向，非直接寫修法）。本計畫的目標是用 Puppeteer + headless Chromium + CDP `Input.dispatchTouchEvent` 建立可重跑的時序驗證迴圈，量測「換頁動作」與「瀏覽器對同一次觸控合成的原生 `click` 事件」之間的競速關係，並把量測結果誠實記錄回 `issues.md`。下一輪（拿到本輪資料後）才依實測時序另立計畫定案修法方向。

**Architecture:** 規劃階段已查證一個修正 `issues.md` 原始假說的關鍵事實：`paginator.js` 本身**沒有任何** tap-to-turn-page 的 `click`／短按處理（只有 `touchmove` 驅動的拖曳換頁邏輯，見下方 Global Constraints）。本專案「點擊換頁」功能完全由 Flutter 端 `_NavZoneTapDetector` 收到觸控後呼叫 `FoliateEpubReaderView.nextPage()` → `evaluateJavascript('window.nextPage()')` 實現（`app/lib/reader/foliate_epub_reader_view.dart:421-426`）。使用者截圖檔名「點擊此畫面左邊...的位置時」「點擊換頁位置重疊」明確描述的是離散點擊（nav-zone 熱區點擊），不是滑動手勢。故本計畫的 harness 模擬的競速是：CDP 觸控注入 touchstart/touchend（模擬使用者手指觸控，這一路訊號同時會被 Flutter 的 `_NavZoneTapDetector`「與」WebView 自己獨立接收，見 Epic 25 Issue 1 已確立的「兩者是平行路徑，互不阻擋」事實）＋緊接著呼叫 `page.evaluate(() => window.nextPage())`（模擬 Flutter 呼叫 `evaluateJavascript` 的效果）——量測瀏覽器對同一次觸控合成的原生 `click` 事件，究竟會在「頁面內容已換到新頁」之前還是之後觸發。

**Tech Stack:** Puppeteer + headless Chromium（CDP `Input.dispatchTouchEvent`），比照 `tmp/epic-18-issue-47-harness/`／`tmp/epic-25-issue-1-harness/` 既有慣例，harness 本身不進版控（`tmp/` 已在 `.gitignore`）。

## Global Constraints

- **已查證：`paginator.js` 沒有自己的 tap-to-turn-page 邏輯**——`grep -n "#onTouchStart\|#onClick\|addEventListener('click'\|tap" paginator.js` 只找到 `#onTouchStart`（touchmove 拖曳用）與 `#onTouchEnd` 內的註解提及「tap」，沒有任何獨立的 click/短按換頁處理。這推翻了 `issues.md` 原始假說「`paginator.js` 的換頁是自己的 touchstart/touchmove/touchend 手勢邏輯驅動」對「點擊換頁」情境的適用性——那段描述精確地說是滑動換頁的機制，離散點擊換頁走的是完全不同的 Flutter→JS 橋接路徑（見上方 Architecture）。本計畫據此把 harness 設計為模擬 nav-zone 點擊路徑，而非模擬滑動手勢。
- **已查證：分頁機制把整個 iframe 元素撐大到「多頁疊合」的總高度，換頁時位移 iframe 自身在外層容器內的位置**（規劃階段用獨立診斷腳本實測確認，非理論推算）：例如 2 頁內容在 800×1200 viewport 下，iframe 本身會撐高到 2400px，換頁時 iframe 的 `getBoundingClientRect().y` 從 `0` 變成 `-1200`。這代表任何要判斷「一段文字目前是否在可視頁」的程式碼，都**不能**用 `iframe.contentDocument.defaultView.innerHeight/innerWidth`（那反映的是撐大後的內部總尺寸），必須把文字的 `Range.getClientRects()` 換算成「page-level」座標（加上 `iframe.getBoundingClientRect()` 的位移）後，再與最外層 `window.innerWidth/innerHeight` 比較。Task 1 的 harness 已依此設計並實測驗證正確。
- **已查證：`window.nextPage()`/`window.previousPage()` 在頁面剛完成初次排版（`onPageRendered` 事件、body 文字已渲染）的極短時間窗口內呼叫會靜默無效**（規劃階段實測踩到的真實 bug，非理論假設）：`paginator.js` 內部分頁計算（`#renderedPages` 等）有一段 `onPageRendered`/文字可見「之後」才完成的非同步初始化，過早呼叫 `next()`/`prev()` 呼叫前後 `atStart`/`atEnd` 完全不變、不拋錯也不輸出任何訊號，容易被誤判為「換頁功能本身壞了」。Task 1 的 harness 在文字可見判定後補了 1000ms 安全等待，之後 `nextPage()` 才穩定生效——任何後續要在 headless 環境操作 `window.nextPage()` 的程式碼都必須留意這個既有陷阱。
- Harness 不進版控（`tmp/epic-25-issue-4-harness/`，`.gitignore` 已涵蓋 `tmp/`），比照既有 harness 慣例。
- 本計畫的「PASS」只代表 harness 基礎設施本身正確運作（控制組成立、`previousPage()` 可靠還原起始狀態、無 JS 例外）——實際量測到的重現率數字才是本輪要蒐集、寫回 `issues.md` 的資料，不是拿來當作 PASS/FAIL 判定用。
- 本計畫**不包含**修法設計——`issues.md` Issue 4「下一步」步驟 2（依實測時序定案修法方向）明確排除在本計畫範圍外，留給下一輪。

---

### Task 1：建立 headless CDP 時序驗證迴圈，實測「nav-zone 點擊觸發換頁」與原生 `click` 合成事件的競速關係

**Files:**
- Create: `tmp/epic-25-issue-4-harness/repro.mjs`（新建，Puppeteer 腳本，不進版控；`package.json`/`node_modules` 可比照既有 `tmp/epic-18-issue-47-harness/` 複製沿用，或另跑 `npm init -y && npm install puppeteer`）

**Interfaces:**
- Consumes：`app/android/app/src/main/assets/foliate/main.js` 既有的 `window.nextPage()`／`window.previousPage()`／`window.setDecorations()`（皆為既有已實作、Dart 端已在用的橋接函式，harness 直接呼叫，不新增/修改任何 `main.js` 程式碼）、`app/test/fixtures/sample_long_chinese_vertical.epub`（既有 fixture，直排長文本，2887 字在本 harness 的版面設定下剛好切成 2 頁，適合本測試）。
- Produces：無新增可供其他 Task 呼叫的函式——本計畫只有這一個 Task，產出是 harness 腳本本體與其執行結果（記錄於 Step 4 的 Expected 區塊與 Task 2 寫回 `issues.md` 的內容）。

- [x] **Step 1：建立 harness 目錄與依賴套件**

Run:
```bash
mkdir -p tmp/epic-25-issue-4-harness
cp -r tmp/epic-18-issue-47-harness/node_modules tmp/epic-25-issue-4-harness/node_modules
cp tmp/epic-18-issue-47-harness/package.json tmp/epic-25-issue-4-harness/package.json
cp tmp/epic-18-issue-47-harness/package-lock.json tmp/epic-25-issue-4-harness/package-lock.json
```
Expected: `tmp/epic-25-issue-4-harness/` 內有 `node_modules/puppeteer`；若該既有目錄不存在，改用 `cd tmp/epic-25-issue-4-harness && npm init -y && npm install puppeteer`。

- [x] **Step 2：撰寫 `repro.mjs`**

建立 `tmp/epic-25-issue-4-harness/repro.mjs`：

```javascript
// Epic 25 Issue 4 — 換頁點擊位置與相鄰頁畫線重疊時誤跳出刪除確認對話框
// 時序驗證迴圈（Puppeteer + headless Chromium + CDP Input.dispatchTouchEvent）
//
// 目的：驗證/量測根因假說——nav-zone 點擊觸發的 window.nextPage()（模擬
// Flutter _NavZoneTapDetector 收到 touchend 後透過 evaluateJavascript 呼叫
// 'window.nextPage()'）與瀏覽器對同一次 touchstart/touchend 合成的原生
// click 事件之間的競速：若 click 在頁面內容已經換到下一頁「之後」才觸發，
// 其 hitTest 座標會打中新頁內容，重現使用者回報的誤跳出刪除確認對話框。
//
// 已查證 paginator.js 本身沒有任何 tap-to-turn-page 的 click/短按處理
// （只有 touchmove 驅動的拖曳換頁），本專案「點擊換頁」功能完全由 Flutter
// 端 _NavZoneTapDetector 呼叫 window.nextPage() 實現（CLAUDE.md 架構描述、
// app/lib/reader/foliate_epub_reader_view.dart 的 nextPage() static
// helper），故本 harness 用 page.evaluate(() => window.nextPage()) 模擬
// 這條路徑，而非模擬 paginator.js 自己的滑動手勢。

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
  '../../app/test/fixtures/sample_long_chinese_vertical.epub',
)
const ORIGIN = 'https://appassets.androidplatform.net'
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }
const ITERATIONS = 20

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

    await page.evaluateOnNewDocument(() => {
      window.__harnessEvents = []
      window.flutter_inappwebview = {
        callHandler: async (name, ...args) => {
          window.__harnessEvents.push({ name, args })
        },
      }
    })

    const initialPrefs = {
      writingMode: 'vertical', fontSize: 1.0, lineHeight: 1.0,
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

    // 【規劃階段實測發現】onPageRendered／文字已渲染只代表初次排版完成，
    // paginator.js 內部的分頁計算（#renderedPages 等）仍有一段非同步初始化
    // 尚未完成——此時立刻呼叫 window.nextPage() 會靜默無效（atStart/atEnd
    // 呼叫前後完全不變，不拋錯也不輸出任何訊號）。補一段安全等待，讓分頁
    // 初始化確實完成，之後 nextPage()/previousPage() 才會穩定生效。
    await new Promise((r) => setTimeout(r, 1000))

    // 取得目前可視頁面上一段文字的 CFI 與 page-level 螢幕座標（供 CDP
    // 觸控注入使用）。用 TreeWalker 找文字節點、Range.getClientRects()
    // 取矩形（比照 epic-25-issue-1-harness 既有手法，不用
    // caretRangeFromPoint——直排文字下的相容性未知）。
    //
    // 【規劃階段實測發現】分頁機制是把整個 iframe 元素本身撐大到「多頁
    // 疊在一起」的總高度（例如 2 頁 × 1200px viewport = 2400px），換頁時
    // 位移 iframe 自己在外層容器內的位置（而非位移 iframe 內部 body 的
    // scroll/transform）——iframe.contentDocument 的
    // innerWidth/innerHeight 反映的是「整個撐大後的內部尺寸」，不是目前
    // 實際可視的那一頁範圍，用它判斷「文字是否在目前可視頁」必然誤判
    // （TreeWalker 永遠選到 doc.body 第一段文字，不論換頁與否）。正確做法
    // 是把文字 rect 換算成 page-level 座標（加上
    // iframe.getBoundingClientRect() 的位移），再用最外層瀏覽器視窗的
    // window.innerWidth/innerHeight 判斷是否落在目前實際可視範圍內。
    async function locateTextRect() {
      return page.evaluate(() => {
        const fv = document.querySelector('foliate-view')
        const container = fv?.renderer?.shadowRoot?.getElementById('container')
        const iframes = Array.from(container?.querySelectorAll('iframe') ?? [])
        for (const iframe of iframes) {
          const doc = iframe.contentDocument
          if (!doc?.body) continue
          const iframeRect = iframe.getBoundingClientRect()
          const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
          while (walker.nextNode()) {
            const node = walker.currentNode
            if ((node.nodeValue ?? '').trim().length <= 10) continue
            const range = doc.createRange()
            range.setStart(node, 0)
            range.setEnd(node, Math.min(6, node.nodeValue.length))
            const rect = range.getClientRects()[0]
            if (!rect) continue
            const pageX = iframeRect.left + rect.left + rect.width / 2
            const pageY = iframeRect.top + rect.top + rect.height / 2
            const visible = pageX >= 0 && pageX < window.innerWidth
              && pageY >= 0 && pageY < window.innerHeight
            if (!visible) continue
            const index = fv.renderer.getContents().find((c) => c.doc === doc)?.index
            const cfi = fv.getCFI(index, range)
            return { cfi, text: node.nodeValue.slice(0, 6), pageX, pageY }
          }
        }
        return null
      })
    }

    const before = await locateTextRect()
    if (!before) {
      console.log('FAIL: 無法定位換頁前的文字節點')
      process.exitCode = 1
      return
    }

    await page.evaluate(() => window.nextPage())
    await new Promise((r) => setTimeout(r, 1000))

    const after = await locateTextRect()
    if (!after) {
      console.log('FAIL: 無法定位換頁後的文字節點')
      process.exitCode = 1
      return
    }

    await page.evaluate(() => window.previousPage())
    await new Promise((r) => setTimeout(r, 1000))

    const backToBefore = await locateTextRect()
    const restored = backToBefore?.cfi === before.cfi
    console.log(`before: text="${before.text}" cfi=${before.cfi} x=${before.pageX.toFixed(1)} y=${before.pageY.toFixed(1)}`)
    console.log(`after:  text="${after.text}" cfi=${after.cfi} x=${after.pageX.toFixed(1)} y=${after.pageY.toFixed(1)}`)
    console.log(`previousPage() 後成功還原到起始頁：${restored}`)
    if (!restored) {
      console.log('FAIL: previousPage() 未能還原到起始頁，後續迴圈狀態不可靠')
      process.exitCode = 1
      return
    }

    // 在 before/after 兩個 CFI 上各建立一筆劃線（比照 Dart 端
    // buildDecorationEntries() 產生的 {id, cfi, color, isUnderline} 格式，
    // window.setDecorations() 既有實作直接消費，與正式產品路徑一致）。
    await page.evaluate((beforeCfi, afterCfi) => {
      window.setDecorations([
        { id: 'before', cfi: beforeCfi, color: 'yellow', isUnderline: false },
        { id: 'after', cfi: afterCfi, color: 'magenta', isUnderline: false },
      ])
    }, before.cfi, after.cfi)
    await new Promise((r) => setTimeout(r, 200))

    // 控制組：目前（換頁前狀態）畫面上點擊 before 座標，應正確觸發
    // onAnnotationActivated('before')——證實兩筆劃線與座標本身沒有寫錯，
    // 後面的競速測試結果才可信。
    await page.evaluate(() => { window.__harnessEvents = [] })
    const client = page._client()
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x: before.pageX, y: before.pageY, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
    })
    await new Promise((r) => setTimeout(r, 30))
    await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    await new Promise((r) => setTimeout(r, 500))
    const controlEvents = await page.evaluate(() => window.__harnessEvents)
    const controlHit = controlEvents.find((e) => e.name === 'onAnnotationActivated')
    console.log(`控制組（無換頁介入，單純點擊 before 座標）：${controlHit ? `命中 id=${controlHit.args[0]}` : '未觸發任何 onAnnotationActivated'}`)
    if (controlHit?.args?.[0] !== 'before') {
      console.log('FAIL: 控制組未能正確命中 before 劃線，座標/CFI 設置有誤，後續競速測試結果不可信')
      process.exitCode = 1
      return
    }

    // 正式競速測試：在 before 座標點擊，touchend 後不加人工延遲、緊接著
    // 呼叫 window.nextPage()——模擬 Flutter _NavZoneTapDetector 收到同一次
    // touchend 後立刻透過 evaluateJavascript('window.nextPage()') 呼叫。
    // 重複多次量測重現率（比照 /diagnose 技能「非決定性 bug 目標是提高
    // 重現率，非單次乾淨重現」）。click 相對 touchend 的實際延遲改用
    // 瀏覽器端同一個 performance.now() 時鐘量測（doc 上同時掛 touchend／
    // click 監聽器），避免 Node 端 Date.now() 與瀏覽器端 performance.now()
    // 基準不同、無法直接相減比較的問題。
    let misfireOnAfter = 0
    let misfireOnBefore = 0
    let noEvent = 0
    const clickDelaysMs = []

    for (let i = 0; i < ITERATIONS; i++) {
      await page.evaluate(() => {
        window.__harnessEvents = []
        window.__touchEndAt = null
        window.__clickAt = null
        const fv = document.querySelector('foliate-view')
        for (const { doc } of fv.renderer.getContents()) {
          doc.addEventListener('touchend', () => {
            if (window.__touchEndAt === null) window.__touchEndAt = performance.now()
          }, { capture: true, once: true })
          doc.addEventListener('click', () => {
            if (window.__clickAt === null) window.__clickAt = performance.now()
          }, { capture: true, once: true })
        }
      })

      await client.send('Input.dispatchTouchEvent', {
        type: 'touchStart',
        touchPoints: [{ x: before.pageX, y: before.pageY, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
      })
      await new Promise((r) => setTimeout(r, 80))
      await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
      // 不加人工延遲，緊接著呼叫 nextPage()，模擬原生橋接呼叫幾乎與
      // touchend 同時抵達 JS 引擎（headless CDP 下的 page.evaluate()
      // 往返延遲即代表這條路徑能達到的最快速度，見計畫 Task 1 的已知
      // 限制說明——真機 Flutter 橋接延遲只會更高，不會更低）。
      await page.evaluate(() => window.nextPage())

      await new Promise((r) => setTimeout(r, 800))

      const events = await page.evaluate(() => window.__harnessEvents)
      const hit = events.find((e) => e.name === 'onAnnotationActivated')
      const timing = await page.evaluate(() => ({ touchEndAt: window.__touchEndAt, clickAt: window.__clickAt }))

      if (hit?.args?.[0] === 'after') misfireOnAfter++
      else if (hit?.args?.[0] === 'before') misfireOnBefore++
      else noEvent++

      const delayMs = (typeof timing.clickAt === 'number' && typeof timing.touchEndAt === 'number')
        ? timing.clickAt - timing.touchEndAt
        : null
      if (delayMs !== null) clickDelaysMs.push(delayMs)

      console.log(`iteration ${i}: hit=${hit?.args?.[0] ?? 'none'} click-touchend delay=${delayMs === null ? 'N/A' : delayMs.toFixed(2) + 'ms'}`)

      // 還原到起始頁，準備下一輪。
      await page.evaluate(() => window.previousPage())
      await new Promise((r) => setTimeout(r, 800))
    }

    const avgDelay = clickDelaysMs.length
      ? (clickDelaysMs.reduce((a, b) => a + b, 0) / clickDelaysMs.length)
      : null

    console.log(`\n=== 結果彙總（共 ${ITERATIONS} 次） ===`)
    console.log(`誤觸發於新頁（misfireOnAfter，即重現 Issue 4 症狀）：${misfireOnAfter}`)
    console.log(`正確觸發於舊頁（misfireOnBefore）：${misfireOnBefore}`)
    console.log(`未觸發任何 onAnnotationActivated（noEvent）：${noEvent}`)
    console.log(`click 相對 touchend 平均延遲：${avgDelay === null ? 'N/A' : avgDelay.toFixed(2) + 'ms'}（樣本數 ${clickDelaysMs.length}）`)
    console.log(`pageErrors: ${pageErrors.length}`)
    pageErrors.forEach((e) => console.log('  ' + e))

    // 本 harness 的「PASS」只代表基礎設施本身正確運作（控制組成立、
    // previousPage() 可靠還原、無 JS 例外）——misfireOnAfter 的實際數字
    // 才是本輪要蒐集、寫回 issues.md 的資料，不是這裡的判定依據。
    const ok = pageErrors.length === 0 && restored && controlHit?.args?.[0] === 'before'
    console.log(`\n${ok ? 'PASS（harness 基礎設施運作正常）' : 'FAIL'}`)
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

- [x] **Step 3：執行 harness**

Run: `cd tmp/epic-25-issue-4-harness && node repro.mjs`

Expected（本計畫規劃階段已實際執行過，以下為真實輸出，非預測）：
```
before: text="清晨的薄霧籠" cfi=epubcfi(/6/2!/4/2,/1:0,/1:6) x=746.5 y=163.2
after:  text="山村的未來充" cfi=epubcfi(/6/2!/4/30,/1:0,/1:6) x=708.1 y=163.2
previousPage() 後成功還原到起始頁：true
控制組（無換頁介入，單純點擊 before 座標）：命中 id=before
iteration 0: hit=before click-touchend delay=1.60ms
...（iteration 1-19，delay 皆落在 1.1-2.2ms 區間）...

=== 結果彙總（共 20 次） ===
誤觸發於新頁（misfireOnAfter，即重現 Issue 4 症狀）：0
正確觸發於舊頁（misfireOnBefore）：20
未觸發任何 onAnnotationActivated（noEvent）：0
click 相對 touchend 平均延遲：1.52ms（樣本數 20）
pageErrors: 0

PASS（harness 基礎設施運作正常）
```

`exitCode` 為 `0`。控制組正確命中 `before`（證實劃線/座標設置無誤），但**正式競速測試 20 次全數命中 `before`，0 次重現 Issue 4 症狀**——headless Chromium 下，原生 `click` 合成事件平均只比 `touchend` 晚約 1.5ms 觸發，遠快於 `page.evaluate(() => window.nextPage())` 這個往返呼叫本身的延遲，導致 `click` 的 hitTest 判定時，`window.nextPage()` 觸發的換頁動作根本還沒生效，永遠打中舊頁內容。

- [x] **Step 4：確認 harness 本身無誤（`node --check` 語法檢查＋重跑一次交叉確認結果穩定）**

Run: `node --check tmp/epic-25-issue-4-harness/repro.mjs`
Expected: 無輸出、exit code 0。

Run: `cd tmp/epic-25-issue-4-harness && node repro.mjs`（第二次執行）
Expected: 結果彙總數字與 Step 3 一致或相近（`misfireOnAfter` 仍為 0 或極低個位數——若第二次出現與第一次顯著不同的非零 `misfireOnAfter`，代表該時序有一定機率性，Task 2 寫回 `issues.md` 時需誠實記錄兩次結果而非只取一次）。

---

### Task 2：把量測結果寫回 `issues.md` Issue 4 區塊

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 4 區塊，新增規劃階段查證與量測結果小節）

**Interfaces:**
- Consumes：Task 1 的實際執行輸出（`misfireOnAfter`／`misfireOnBefore`／`noEvent`／平均延遲數字）。
- Produces：無程式介面——本 Task 的產出是文件更新，供下一輪判斷是否需要真機插樁或改變根因假說方向。

- [x] **Step 1：在 `issues.md` Issue 4 區塊新增查證與量測結果**

在 `docs/epics/epic-25-annotation-interaction-qa/issues.md` 的「## Issue 4」區塊，「**根因假說**」段落之後、「**下一步**」段落之前，新增：

```markdown
**規劃階段查證（`plan-issue-4.md`，修正原始假說對「點擊換頁」情境的適用範圍）：**

`paginator.js` 原始碼查證（`grep -n "#onTouchStart\|#onClick\|addEventListener('click'\|tap" paginator.js`）確認**沒有任何自己的 tap-to-turn-page click/短按處理**，只有 `touchmove` 驅動的拖曳換頁邏輯。原始假說引用的「`paginator.js` 的換頁是自己的 touchstart/touchmove/touchend 手勢邏輯驅動」精確地說只適用於**滑動換頁**，本專案「點擊換頁」（nav-zone 熱區點擊，即使用者截圖檔名描述的情境）完全是 Flutter 端 `_NavZoneTapDetector` 收到觸控後呼叫 `evaluateJavascript('window.nextPage()')` 實現，與 `paginator.js` 自己的觸控邏輯是兩條獨立路徑（比照 Epic 25 Issue 1 已確立的「Flutter Listener 與 WebView 平行接收同一組觸控、互不阻擋」事實）。

**headless CDP 時序驗證迴圈結果（`tmp/epic-25-issue-4-harness/repro.mjs`，20 次重複量測）：**

模擬「CDP 觸控注入 touchstart/touchend＋緊接著呼叫 `window.nextPage()`」這條路徑（代表 Flutter nav-zone 點擊觸發換頁的最快可能情境——headless `page.evaluate()` 往返延遲，理論上比真機 Flutter→原生橋接→WebView 的實際 IPC 鏈路更短，不會更長），控制組（無換頁介入，單純點擊）正確命中舊頁劃線，證實劃線/座標設置本身無誤；但正式競速測試 **20 次全數命中舊頁內容、0 次重現 Issue 4 症狀**（原生 `click` 合成事件平均只比 `touchend` 晚約 1.5ms 觸發，快於 `page.evaluate()` 往返本身的延遲）。

**解讀（誠實記錄，非下定論）**：此負向結果**不能排除**本假說在真機上成立——有兩種可能同時存在：(a) 若 headless `page.evaluate()` 的往返延遲已經是這條路徑能達到的下限，而真機 Flutter 原生橋接（Dart 事件迴圈→MethodChannel/JS 橋接→Android WebView `evaluateJavascript()`）的實際 IPC 鏈路必然更長，則競速只會更難獲勝，這條假說的可信度應該**下修**；(b) 但也可能是 headless Chromium 的原生 touch-to-click 合成時序特性，與真機 Android System WebView 本身有實質差異（不同瀏覽器引擎組建、不同原生事件合成管線）——這正是 Epic 25 Issue 1 已記錄過的同一類「headless CDP 無法代表真機 WebView 差異」既有限制（Issue 1 是「無法模擬選取控點拖曳」，本次是「觸控轉合成 click 的時序特性未必一致」）。兩者目前無法用 headless 環境本身區辨。
```

- [x] **Step 2：更新 Issue 4 的 `Status` 行**

修改 `issues.md` Issue 4 區塊開頭的 `Status` 行，從：

```markdown
**Status:** `needs-triage`——根因假說信心中高，但建議先建立 headless 重現迴圈驗證時序後再定案修法，避免像 Epic 18 Issue 47 一樣在計畫審查階段才發現時序假設有誤。
```

改為：

```markdown
**Status:** `needs-info`——已依建議建立 headless CDP 時序驗證迴圈（見下方「規劃階段查證」小節），結果為 20 次量測 0 次重現，headless 環境本身無法確認/否證此假說是否適用於真機。下一步需要真機診斷插樁（比照 Epic 25 Issue 1 的 `[DEBUG-e25iN]` 插樁手法）量測真實 Flutter→WebView 橋接延遲與原生 click 合成時序，才能進一步定案；在拿到真機資料前不建議直接動手修法。
```

- [x] **Step 3：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 4 補上 headless 時序驗證迴圈查證結果——paginator.js 無自有 tap 換頁邏輯、20 次量測 0 次重現"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 4「下一步」步驟 1（建立 headless 重現迴圈、量測 `show-annotation` 是否觸發、記錄 `click` 事件相對 `touchend` 的延遲時間）由 Task 1 完整覆蓋，且執行結果已寫回 `issues.md`（Task 2）。步驟 2（依實測時序定案修法方向）與步驟 3（確認修法不影響正常點擊畫線）刻意不在本計畫範圍內——`issues.md` 原文與人類已確認的方向都明確要求「先驗證時序再定案修法」，本計畫的負向結果（0/20 重現）代表尚不具備定案修法的資訊基礎，強行往下寫修法會重蹈 Epic 18 Issue 47 的覆轍。
- **No Placeholders 掃描**：Task 1 的 harness 完整程式碼、Task 2 要寫入 `issues.md` 的文字，皆為規劃階段實際執行/驗證過的內容（非理論推算），Step 3 的 Expected 區塊是真實執行輸出而非預測值。
- **型別/介面一致性**：harness 呼叫的 `window.nextPage()`／`window.previousPage()`／`window.setDecorations()`／`window.flutter_inappwebview.callHandler` 皆為 `main.js` 既有介面，未新增或修改任何簽章。
- **規劃階段實測發現並已修正的三個陷阱**（詳見 Global Constraints）：(1) `paginator.js` 沒有自己的 tap 換頁邏輯，糾正了原始假說對「點擊換頁」情境的錯誤套用；(2) 分頁機制撐大 iframe 本身、位移 iframe 位置（非位移 body scroll），影響任何「判斷文字是否在可視頁」的程式碼設計；(3) `window.nextPage()` 在文字剛渲染完成的極短窗口內呼叫會靜默無效。三者皆已在 harness 程式碼中修正並附上真實驗證依據的註解說明，不是留給執行者臨場踩雷的空白。
- **範圍誠實聲明**：本計畫刻意不對「headless 負向結果是否代表假說錯誤」下結論——明確列出兩種未區辨的可能性（真機橋接延遲確實更長 vs. headless 觸控合成時序與真機有實質差異），並誠實記錄「目前無法用 headless 環境本身區辨」，把判斷留給下一輪真機診斷資料。
