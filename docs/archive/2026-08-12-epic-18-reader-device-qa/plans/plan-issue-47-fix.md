# Epic 18 Issue 47 — 流式 EPUB 劃線拖曳選取時頁面亂跳：修復 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `issues.md` Issue 47 狀態已是 `ready-for-agent`（分支 `issue-47-diag` 已用 CDP `Input.dispatchTouchEvent`＋真機驗證確認根因，見 `reviews/bugfix-repro-issue-47.md`）——本計畫實作實際修復：在長按候選期間（`touchstart` 到瀏覽器原生選取真正建立之間）攔截 `touchmove`，避免 `paginator.js` 的 `#onTouchMove` 選取守衛在這段空窗期誤判為滑動換頁而位移內容。

**Architecture:** 不修改 `paginator.js`（ADR 0011）。改在 `main.js`（本專案自有檔案）既有的 `view.addEventListener('load', (e) => {...})` 區塊內（`main.js:593`，已經是逐 section iframe 綁定監聽器的既有 hook 點），新增一組 **capture 階段**的 `touchstart`/`touchmove`/`touchend`/`touchcancel` 監聽器。`paginator.js` 自己的同名監聽器是 bubble 階段（`{passive:false}`，`paginator.js:1452-1455`）——依 DOM 事件規格，capture 階段監聽器一定搶在同一個節點的 bubble 階段監聽器之前執行，不受註冊順序影響。本計畫的監聽器在判定「目前仍處於長按候選期間（時間短、位移小、平均速度低、選取尚未確立）」時呼叫 `event.stopImmediatePropagation()`，讓事件完全不會傳到 `paginator.js` 的處理常式（包含其 `e.preventDefault()` 呼叫與後續所有分支），真正的滑動換頁手勢（快速或大幅位移）與選取已確立後的 `touchmove` 則立即放行、不受影響——逃逸條件用「距離死區＋平均速度」雙門檻，避免單純距離門檻在放行第一個 touchmove 時因 `paginator.js` 內部觸控狀態已經累積誤差而暴跳（見 Global Constraints 審查修正段落）。

**Tech Stack:** 純 JS（`main.js`）。驗證沿用 `issue-47-diag` 分支已證實可行的 Puppeteer + CDP `Input.dispatchTouchEvent` 診斷手法（`tmp/epic-18-issue-47-harness/repro.mjs`）——**注意**：synthetic `new TouchEvent()` + `dispatchEvent()` 在 headless Chromium 中無法觸發 `paginator.js` 的 handler（診斷報告已記錄的既有結論），必須用 CDP `Input.dispatchTouchEvent` 走真正的瀏覽器 input pipeline。不涉及 Dart/Flutter 程式碼異動、不影響 `flutter test`/`flutter analyze`。

## Global Constraints

- **不可修改任何 vendored 檔案**：`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`／`progress.js`／`text-walker.js`／`construct-style-sheets-polyfill.js`／`vendor/zip.js` 全部原樣（ADR 0011）。本計畫所有程式碼變更都在 `main.js`。
- **修改點鎖定在既有 hook**：`main.js:593` 的 `view.addEventListener('load', (e) => { const doc = e.detail.doc; ... })` 是既有的、每個 section iframe 載入時都會執行一次的區塊（目前已用於 `selectionchange`/`contextmenu`/`pointercancel` 三個既有監聽器）。本計畫新增的監聽器插入這個區塊內、緊接在既有的 `doc.addEventListener('pointercancel', () => reportSelection())`（`main.js:642`）之後、區塊結尾 `})`（`main.js:643`）之前——不新增新的 hook 點，沿用既有慣例。
- **已查證但診斷報告未涵蓋的重要細節**：`paginator.js:2212` 的 `#onTouchMove`（`if (!this.hasAttribute('animated') || this.hasAttribute('eink')) return`）是 `scrollBy()`/`#dragBy()`（2229-2237 行）之前的一道早退閘門；已用 `grep` 確認全專案（`main.js`／`index.html`／`foliate_epub_reader_view.dart`）**從未設定過 `animated` 這個 attribute**。`issue-47-diag` 分支的 harness（`repro.mjs:95-101`）明確靠 `renderer.setAttribute('animated', '')` 才讓 `#onTouchMove` 走到 `scrollBy` 分支，但這個 workaround 是否反映真實正式環境的行為未經查證。**本計畫的修法不依賴解開這個疑點**：capture 階段攔截發生在 `paginator.js` 的 `#onTouchMove` 執行**之前**，不論真正的位移是透過 `scrollBy()`/`#dragBy()`（`animated` 有設定時）還是透過 `e.preventDefault()` 干擾瀏覽器原生選取拖曳（`animated` 未設定、但 `e.preventDefault()` 在 2198 行仍會對非 stylus 觸控無條件執行）造成，`stopPropagation()` 都會讓 `paginator.js` 的整個 handler 不執行，兩種可能成因都會被同時擋下。
- **量測指標維持 `issue-47-diag` 分支已驗證的作法**：monkey-patch `view.renderer.scrollBy`（公開方法）記錄呼叫次數與是否真的位移，是判斷「touchmove 期間有沒有觸發內容位移」最直接的信號，比 `containerPosition`/`transform` 前後比較更精確（不受 `touchend` 後 `snap()`/`#settleDrag()` 復原影響，見 `bugfix-repro-issue-47.md`「觸控事件注入方式」段）。
- **本計畫的「測試」是 harness 腳本本身的量測輸出**，不是 `flutter test`——比照 Issue 34/38/45/47 診斷階段既有慣例，`main.js`／`paginator.js` 無 JS 測試框架可用。harness 腳本與其產物一律放在 `tmp/epic-18-issue-47-harness/`（`tmp/` 已於 `.gitignore` 排除，不進版控）。
- **審查修正（Critical #1，見 `tmp/epic-18/review-plan-issue-47-fix.md`）——單純的距離逃逸門檻會造成一次性暴跳**：原設計只用 `SWIPE_DISTANCE_ESCAPE_PX = 60` 判斷，審查用實際的 `paginator.js` 原始碼精確推演出一個真實缺陷：`#touchState.x`/`state.y`（`paginator.js` 內部，`#onTouchMove` 每次執行才會更新，見 2203-2204 行）只要事件被本計畫的攔截器擋下，就完全不會更新，停留在 `#onTouchStart` 當下記下的初始值；一旦累積位移終於超過門檻、放行第一個 touchmove 給 `paginator.js`，`paginator.js:2201` 算出的 `dx = state.x - x` 會是「從手勢一開始到現在」的全部累積位移，而不是這一影格的增量——對照審查報告的具體算例（15px→40px→65px，每影格約 16ms），第 3 影格放行時會讓 `scrollBy(-65, 0)` 一次到位，畫面呈現「前段凍結、之後暴跳」，在 E-Ink 裝置上尤其明顯。已查證 `state.x`/`state.y` 的更新時機（`paginator.js:2203-2204`，只在 `#onTouchMove` 內部賦值）確認這個推演成立。**修法**：改用「距離死區（大幅調降）＋平均速度」雙門檻——`LONG_PRESS_GATE_MS = 500`（對齊 Android `ViewConfiguration.getLongPressTimeout()` 標準預設值，作為時間上限保底）、`SWIPE_DISTANCE_DEADZONE_PX = 15`（審查建議範圍 15-20px 的下限，累積位移一旦超過就放行，把「卡死才暴跳」的最大暴跳量壓低到跟正常單影格位移同量級，不再是 60px 那種明顯量級）、`SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3`（審查建議值；平均速度 = 累積位移 ÷ 累積時間，真正的滑動手勢從第一影格就有夠高的速度，通常在 15px 門檻生效前就已經被速度條件放行——例如審查算例的第 1 影格 15px/16ms ≈ 0.94px/ms，遠超 0.3，會在 `state.x` 完全沒機會累積誤差之前就放行，徹底避開暴跳；長按選字時手指的自然微幅晃動速度遠低於此）。三者皆為本計畫刻意選定的內部實作常數，不對使用者開放設定（YAGNI）。
- **審查修正（Important #2）**：`evt.stopPropagation()` 改為 `evt.stopImmediatePropagation()`——就目前程式碼而言兩者行為等價（`doc` 上沒有其他 capture 階段的 touchmove 監聽器需要一併擋下，`stopPropagation()` 本身已足以讓事件在到達 `paginator.js` 的 bubble 階段監聽器之前就停止傳遞），但 `stopImmediatePropagation()` 對未來若有人在同一個 capture 階段加掛其他監聽器時更穩健，零成本採納。

---

### Task 1: 在 `main.js` 實作長按候選期間攔截，橫排模式驗證

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:593-643`
- Create: `tmp/epic-18-issue-47-harness/repro-fix.mjs`（`repro.mjs` 的聚焦驗證變體，未進版控）

**Interfaces:**
- Consumes: 無（`main.js` 內部新增邏輯，不依賴其他 Task 的產出）
- Produces: `main.js` 新增的 capture 階段監聽器不對外暴露任何新的公開函式/API，行為完全封裝在既有的 `view.addEventListener('load', ...)` 區塊內，`window.applyPreferences`/`window.nextPage`/`window.previousPage` 等既有全域函式簽章不變。

- [ ] **Step 1: 撰寫驗證腳本（先重現「未修復」狀態，作為失敗基準）**

```bash
mkdir -p tmp/epic-18-issue-47-harness
cp .worktrees/issue-47-diag/tmp/epic-18-issue-47-harness/repro.mjs tmp/epic-18-issue-47-harness/repro-fix.mjs 2>/dev/null \
  || echo "若上一版本已不在該路徑，改由下一步直接建立新檔"
```

若上一個指令找不到來源檔（該 worktree 可能已被清理），直接建立 `tmp/epic-18-issue-47-harness/repro-fix.mjs`，內容如下（沿用 `issue-47-diag` 分支已驗證可行的 CDP 觸控注入手法，聚焦成 3 個情境：A 無選取、B 已有選取、E 快速滑動對照組，橫排模式）：

```javascript
// tmp/epic-18-issue-47-harness/repro-fix.mjs
//
// Epic 18 Issue 47 修復驗證：確認長按候選期間的 touchmove 攔截生效
// （情境 A：無選取，修復後 scrollBy 呼叫次數應為 0）、既有選取守衛
// 不受影響（情境 B）、真正的滑動換頁手勢不受影響（情境 E：大幅快速
// 位移，scrollBy 仍應被呼叫）。用 CDP Input.dispatchTouchEvent 走真正
// 的瀏覽器 input pipeline——synthetic TouchEvent dispatch 在 headless
// Chromium 中無法觸發 paginator.js 的 handler（issue-47-diag 分支已
// 記錄的既有結論，見 bugfix-repro-issue-47.md）。

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
        req.respond({ status: 200, contentType: 'application/epub+zip', body: fixtureBuf })
        return
      }
      const pathname = url.pathname === '/' ? '/index.html' : url.pathname
      const rel = pathname.replace(/^\//, '')
      const buf = fileMap.get(rel)
      if (!buf) { req.respond({ status: 404, body: '' }); return }
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

    // 對齊 issue-47-diag 分支已查證的既有事實：#onTouchMove 的
    // scrollBy()/#dragBy() 分支前有 animated attribute 早退閘門
    // （paginator.js:2212），全專案從未設定過這個 attribute（見本計畫
    // Global Constraints）。這裡強制設定，讓驗證腳本能穩定命中
    // #onTouchMove 的完整邏輯路徑，不受這個未解決的環境差異影響。
    await page.evaluate(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      if (renderer && !renderer.hasAttribute('animated')) {
        renderer.setAttribute('animated', '')
      }
    })

    await page.evaluate(() => document.querySelector('foliate-view')?.renderer?.nextPage?.())
    await new Promise((r) => setTimeout(r, 1500))

    await page.waitForFunction(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      const container = renderer?.shadowRoot?.getElementById('container')
      for (const iframe of container?.querySelectorAll('iframe') ?? []) {
        const text = iframe.contentDocument?.body?.textContent?.trim() ?? ''
        if (text.length > 20) return true
      }
      return false
    }, { timeout: 10000 })

    await page.waitForFunction(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      if (!renderer) return false
      const pos = renderer.containerPosition
      renderer.scrollBy(1, 0)
      const changed = renderer.containerPosition !== pos
      if (changed) renderer.scrollBy(-1, 0)
      return changed
    }, { timeout: 15000 })

    await page.evaluate(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      window.__scrollByCalls = []
      const origScrollBy = renderer.scrollBy.bind(renderer)
      renderer.scrollBy = function (dx, dy) {
        const pos = renderer.containerPosition
        origScrollBy(dx, dy)
        const after = renderer.containerPosition
        window.__scrollByCalls.push({ dx, dy, moved: pos !== after, t: performance.now() })
      }
    })

    async function cdpTouchDrag({ startX, startY, deltas, preEstablishSelection, moveDelayMs = 30 }) {
      await page.evaluate(() => { window.__scrollByCalls = [] })
      const client = page._client()

      if (preEstablishSelection) {
        await page.evaluate(() => {
          const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
          const doc = container?.querySelector('iframe')?.contentDocument
          if (!doc) return
          doc.execCommand('selectAll', false, null)
          const sel = doc.getSelection()
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
        })
      } else {
        await page.evaluate(() => {
          const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
          container?.querySelector('iframe')?.contentDocument?.getSelection()?.removeAllRanges()
        })
      }

      const touchId = 1
      let x = startX
      let y = startY
      await client.send('Input.dispatchTouchEvent', {
        type: 'touchStart',
        touchPoints: [{ x, y, id: touchId, radiusX: 5, radiusY: 5, force: 0.5 }],
      })
      await new Promise((r) => setTimeout(r, 50))
      for (const [dx, dy] of deltas) {
        x += dx
        y += dy
        await client.send('Input.dispatchTouchEvent', {
          type: 'touchMove',
          touchPoints: [{ x, y, id: touchId, radiusX: 5, radiusY: 5, force: 0.5 }],
        })
        await new Promise((r) => setTimeout(r, moveDelayMs))
      }
      await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
      await new Promise((r) => setTimeout(r, 100))

      return await page.evaluate(() => window.__scrollByCalls)
    }

    const paginatorRect = await page.evaluate(() => {
      const rect = document.querySelector('foliate-view')?.renderer?.getBoundingClientRect()
      return { left: rect.left, top: rect.top, width: rect.width, height: rect.height }
    })
    const centerX = paginatorRect.left + paginatorRect.width / 2
    const centerY = paginatorRect.top + paginatorRect.height / 2

    // 情境 A：長按候選期間（無選取），小幅累積位移（合計 50px，30ms 間隔）
    const scenarioA = await cdpTouchDrag({
      startX: centerX, startY: centerY,
      deltas: [[5, 0], [8, 0], [10, 0], [12, 0], [15, 0]],
      preEstablishSelection: false,
    })

    await page.evaluate(() => document.querySelector('foliate-view')?.renderer?.scrollBy(50, 0))
    await new Promise((r) => setTimeout(r, 100))

    // 情境 B：選取已確立（對照組）
    const scenarioB = await cdpTouchDrag({
      startX: centerX, startY: centerY,
      deltas: [[5, 0], [8, 0], [10, 0], [12, 0], [15, 0]],
      preEstablishSelection: true,
    })

    await page.evaluate(() => document.querySelector('foliate-view')?.renderer?.scrollBy(50, 0))
    await new Promise((r) => setTimeout(r, 100))

    // 情境 E：真正的滑動換頁手勢（無選取）——修復後仍必須正常運作，
    // 不得被本次新增的攔截誤傷。【審查修正 Critical #2】原本用單次
    // [[100, 0]] 大跳躍，第一影格就直接跨過門檻放行，完全沒有測到
    // Critical #1 描述的「連續多影格累積、卡頓後暴跳」路徑，會讓有問題
    // 的版本也回報「一切正常」的假陽性。改用審查報告本身的具體算例
    // （15px/16ms → 25px/16ms → 25px/16ms，累積 15/40/65px，對應平均
    // 速度 0.94/1.25/1.35 px/ms，皆遠超 0.3 的速度門檻，理論上第一影格
    // 就該被放行），並額外斷言每一次 scrollBy 呼叫的 |dx| 都不超過
    // 30px（略高於本情境最大單影格位移 25px 的安全邊界）——若攔截器
    // 卡住太久才放行、造成 state.x/y 累積誤差，這裡會直接測出異常大的
    // 單次 dx。
    const scenarioE = await cdpTouchDrag({
      startX: centerX, startY: centerY,
      deltas: [[15, 0], [25, 0], [25, 0]],
      preEstablishSelection: false,
      moveDelayMs: 16,
    })

    const result = {
      scenarioA_scrollByCallCount: scenarioA.length,
      scenarioA_anyMoved: scenarioA.some((c) => c.moved),
      scenarioB_scrollByCallCount: scenarioB.length,
      scenarioE_scrollByCallCount: scenarioE.length,
      scenarioE_anyMoved: scenarioE.some((c) => c.moved),
      scenarioE_maxAbsDx: scenarioE.length ? Math.max(...scenarioE.map((c) => Math.abs(c.dx))) : null,
    }
    console.log(JSON.stringify({ scenarioA, scenarioB, scenarioE, result }, null, 2))
    await writeFile(path.join(__dirname, 'result-fix.json'), JSON.stringify(result, null, 2))

    // 判讀（修復後才應該全數成立）：情境 A 無 scrollBy 呼叫（攔截生效）、
    // 情境 B 維持無呼叫（既有守衛不受影響）、情境 E 仍有 scrollBy 呼叫
    // 且確實位移（真正滑動手勢不受影響），且沒有任何一次呼叫是異常
    // 大的一次性暴跳（Critical #1 的回歸檢查）。
    const fixWorks = result.scenarioA_scrollByCallCount === 0
      && result.scenarioB_scrollByCallCount === 0
      && result.scenarioE_scrollByCallCount > 0
      && result.scenarioE_anyMoved === true
      && result.scenarioE_maxAbsDx <= 30
    process.exitCode = fixWorks ? 0 : 1
  } finally {
    await browser.close()
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
```

- [ ] **Step 2: 安裝相依套件、修復前先跑一次確認基準行為**

```bash
mkdir -p tmp/epic-18-issue-47-harness
cd tmp/epic-18-issue-47-harness
npm init -y
npm install puppeteer
node repro-fix.mjs
echo "exit code: $?"
cd ../..
```

Expected（**修復前**）：stdout 印出的 `result` 應為 `{ scenarioA_scrollByCallCount: <大於 0>, scenarioA_anyMoved: true, scenarioB_scrollByCallCount: 0, scenarioE_scrollByCallCount: <大於 0>, scenarioE_anyMoved: true, scenarioE_maxAbsDx: <合理值，接近 15/25/25 這個量級> }`——情境 A 有位移（重現 bug）、情境 B 維持既有守衛正常（對照組）、情境 E 滑動手勢本來就正常（修復前 `main.js` 完全沒有攔截邏輯，`paginator.js` 從第一個 touchmove 就正常收到每一影格的真實增量，`scenarioE_maxAbsDx` 這時候本來就會是正常值，不會暴跳——暴跳只會發生在「有攔截、但門檻設計錯誤」的情況，見 Step 4）。`exit code: 1`（`fixWorks` 為 `false`，因為情境 A 還沒被攔截）。這一步是確認測試腳本本身有效、且修復前的行為符合預期的失敗基準，不是最終驗收標準。

- [ ] **Step 3: 在 `main.js` 實作攔截邏輯**

在 `app/android/app/src/main/assets/foliate/main.js` 找到：

```javascript
      doc.addEventListener('contextmenu', (evt) => {
        evt.preventDefault()
        reportSelection()
      })
      doc.addEventListener('pointercancel', () => reportSelection())
    })
```

改為（新增內容插入 `pointercancel` 監聽器之後、區塊結尾 `})` 之前）：

```javascript
      doc.addEventListener('contextmenu', (evt) => {
        evt.preventDefault()
        reportSelection()
      })
      doc.addEventListener('pointercancel', () => reportSelection())

      // Epic 18 Issue 47 修復：長按候選期間（touchstart 到瀏覽器原生
      // 選取真正建立之間）攔截 touchmove，避免 paginator.js 的
      // #onTouchMove 選取守衛（paginator.js:2191-2195，只在
      // selection.rangeCount > 0 && !selection.isCollapsed 才擋下）在
      // 這段空窗期誤判為滑動換頁而位移內容（已用 CDP 觸控注入＋真機
      // 驗證確認橫排/直排皆會重現，見
      // docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md）。
      //
      // 用 capture 階段監聽器搶在 paginator.js 自己註冊在同一個 doc 上
      // 的 bubble 階段監聽器（paginator.js:1452-1455）之前執行，呼叫
      // stopImmediatePropagation() 讓事件完全不會傳到 paginator 的處理
      // 常式（含其 e.preventDefault() 呼叫與後續所有分支）——不修改
      // paginator.js 任何一行（ADR 0011）。只攔截「看起來像長按候選」
      // 的 touchmove（時間短、位移小、平均速度低、選取尚未確立），真正
      // 的滑動換頁手勢與選取已確立後的 touchmove 都會立即放行。
      //
      // 【審查修正 Critical #1，見 tmp/epic-18/review-plan-issue-47-fix.md】
      // 逃逸條件必須同時看「距離」與「平均速度」，不能只看距離：
      // paginator.js 的 #touchState.x/y（2203-2204 行）只在 #onTouchMove
      // 真正執行到那裡才會更新——若前幾個 touchmove 一路被本攔截器擋下，
      // state.x/y 會停留在 touchstart 當下的初始值；等累積位移終於超過
      // 純距離門檻、放行第一個 touchmove 給 paginator.js 時，它算出的
      // dx = state.x - x 會是「手勢一開始到現在」的全部累積位移，而不是
      // 這一影格的增量，造成 scrollBy() 一次性暴跳（審查報告已用具體
      // 影格算例驗證：15px→40px→65px，第 3 影格單次跳 65px）。改用
      // 「距離死區（調降到 15px）＋平均速度」雙門檻：真正的滑動手勢
      // 通常在第一影格就有夠高的平均速度，會在距離門檻生效、state.x/y
      // 累積誤差之前就先被速度條件放行，state.x/y 這時仍是準確值，不會
      // 暴跳；長按選字的手指自然微幅晃動速度遠低於門檻，會正確停留在
      // 攔截狀態。
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
        evt.stopImmediatePropagation()
      }, { capture: true })
      doc.addEventListener('touchend', () => { longPressGateState = null }, { capture: true })
      doc.addEventListener('touchcancel', () => { longPressGateState = null }, { capture: true })
    })
```

- [ ] **Step 4: 重新執行驗證腳本，確認修復生效**

```bash
cd tmp/epic-18-issue-47-harness
node repro-fix.mjs
echo "exit code: $?"
cd ../..
```

Expected（**修復後**）：`result.scenarioA_scrollByCallCount === 0`（攔截生效，長按候選期間不再位移）、`result.scenarioB_scrollByCallCount === 0`（既有守衛維持正常，不受影響）、`result.scenarioE_scrollByCallCount > 0` 且 `scenarioE_anyMoved === true` 且 `scenarioE_maxAbsDx <= 30`（真正的滑動換頁手勢仍正常運作、且每一影格都是正常增量，沒有 Critical #1 描述的一次性暴跳）。`exit code: 0`。若情境 E 的 `scrollByCallCount` 變成 `0`，代表 `SWIPE_VELOCITY_ESCAPE_PX_PER_MS`／`SWIPE_DISTANCE_DEADZONE_PX`／`LONG_PRESS_GATE_MS` 門檻設得過於保守，需要調整；若 `scenarioE_maxAbsDx > 30`，代表逃逸條件依然太晚才放行、`paginator.js` 的 `state.x`/`state.y` 已經累積了明顯誤差，需要進一步調降 `SWIPE_DISTANCE_DEADZONE_PX` 或提高 `SWIPE_VELOCITY_ESCAPE_PX_PER_MS` 的靈敏度——不得略過任一項回歸檢查。

- [ ] **Step 5: 連續重跑 3 次確認結果穩定**

```bash
cd tmp/epic-18-issue-47-harness
for i in 1 2 3; do node repro-fix.mjs 2>&1 | tail -10; done
cd ../..
```

Expected: 3 次執行的 `result` 內容逐位元組一致，`exit code` 皆為 `0`——比照 Issue 45 診斷時的教訓（`tmp/epic-18/review-plan-issue-45-round2.md`），不穩定的量測結果不能直接採信。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "fix(epic-18): 劃線拖曳長按候選期間攔截 touchmove 避免頁面亂跳（Issue 47）"
```

Expected: `git status` 顯示只有 `main.js` 被修改並已 commit，`tmp/` 內容不在版控範圍內。

---

### Task 2: 延伸驗證直排模式，更新診斷報告與 issue tracker

**Files:**
- Modify: `tmp/epic-18-issue-47-harness/repro-fix.mjs`（新增直排情境）
- Modify: `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md`（附加「修復確認」段落）
- Modify: `docs/epics/epic-18-reader-device-qa/issues.md`（Issue 47 段落狀態更新）

**Interfaces:**
- Consumes: Task 1 已修復的 `main.js`（本 Task 不再修改程式邏輯，只延伸驗證範圍）
- Produces: 無（本 Task 為驗證延伸與文件產出）

- [ ] **Step 1: 在 `repro-fix.mjs` 新增直排情境**

在 `main()` 內、`await writeFile(...)` 之前插入（比照 Task 1 情境 A/B/E 的邏輯，但使用垂直方向的 delta；`writingMode` 切換沿用 Issue 45 已修復的 `view.goTo()` 路徑，等待方式沿用 Issue 45/47 診斷階段已驗證的 `onLocatorChanged` 次數增加判斷法，不使用只會觸發一次的 `onPageRendered`）：

```javascript
    // 直排模式：情境 C（無選取）、情境 D（已有選取，對照組）、
    // 情境 F（快速滑動，對照組）——邏輯與橫排情境 A/B/E 完全對應，
    // 只是 delta 方向從 (dx, 0) 換成 (0, dy)。本專案的攔截邏輯
    // （Task 1 新增的程式碼）完全不區分書寫方向，理論上直排應與橫排
    // 行為一致；若直排在 headless 環境下 #scrollBounds 無法穩定填入
    // （issue-47-diag 分支診斷階段已記錄的既有限制，見
    // bugfix-repro-issue-47.md「直排模式真機驗證」段），改為在 Step 2
    // 記錄為「需要真機覆核」，不得略過或動手腳讓判讀通過。
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

    let verticalBoundsReady = true
    try {
      await page.waitForFunction(() => {
        const renderer = document.querySelector('foliate-view')?.renderer
        if (!renderer) return false
        const pos = renderer.containerPosition
        renderer.scrollBy(0, 50)
        if (renderer.containerPosition !== pos) { renderer.scrollBy(0, -50); return true }
        renderer.scrollBy(50, 0)
        if (renderer.containerPosition !== pos) { renderer.scrollBy(-50, 0); return true }
        return false
      }, { timeout: 10000 })
    } catch {
      verticalBoundsReady = false
    }

    let scenarioC = null
    let scenarioD = null
    let scenarioF = null
    if (verticalBoundsReady) {
      scenarioC = await cdpTouchDrag({
        startX: centerX, startY: centerY,
        deltas: [[0, 5], [0, 8], [0, 10], [0, 12], [0, 15]],
        preEstablishSelection: false,
      })
      await page.evaluate(() => document.querySelector('foliate-view')?.renderer?.scrollBy(0, 50))
      await new Promise((r) => setTimeout(r, 100))
      scenarioD = await cdpTouchDrag({
        startX: centerX, startY: centerY,
        deltas: [[0, 5], [0, 8], [0, 10], [0, 12], [0, 15]],
        preEstablishSelection: true,
      })
      await page.evaluate(() => document.querySelector('foliate-view')?.renderer?.scrollBy(0, 50))
      await new Promise((r) => setTimeout(r, 100))
      // 比照橫排情境 E 的審查修正（Critical #2）：用連續多影格的漸增
      // delta，而不是單次大跳躍，才會真的測到「攔截放行太晚、
      // state.x/y 累積誤差」這條路徑。
      scenarioF = await cdpTouchDrag({
        startX: centerX, startY: centerY,
        deltas: [[0, 15], [0, 25], [0, 25]],
        preEstablishSelection: false,
        moveDelayMs: 16,
      })
    }

    result.verticalBoundsReady = verticalBoundsReady
    result.scenarioC_scrollByCallCount = scenarioC?.length ?? null
    result.scenarioD_scrollByCallCount = scenarioD?.length ?? null
    result.scenarioF_scrollByCallCount = scenarioF?.length ?? null
    result.scenarioF_anyMoved = scenarioF?.some((c) => c.moved) ?? null
    result.scenarioF_maxAbsDy = scenarioF?.length ? Math.max(...scenarioF.map((c) => Math.abs(c.dy))) : null
```

同步調整 Step 4 的 exit code 判讀，加入直排情境（僅在 `verticalBoundsReady` 為 `true` 時要求直排三項也成立，否則只看橫排三項並在 `result` 內用 `verticalBoundsReady: false` 標記需要真機覆核）：

```javascript
    const verticalOk = !result.verticalBoundsReady || (
      result.scenarioC_scrollByCallCount === 0
      && result.scenarioD_scrollByCallCount === 0
      && result.scenarioF_scrollByCallCount > 0
      && result.scenarioF_anyMoved === true
      && result.scenarioF_maxAbsDy <= 30
    )
    const fixWorks = result.scenarioA_scrollByCallCount === 0
      && result.scenarioB_scrollByCallCount === 0
      && result.scenarioE_scrollByCallCount > 0
      && result.scenarioE_anyMoved === true
      && result.scenarioE_maxAbsDx <= 30
      && verticalOk
    process.exitCode = fixWorks ? 0 : 1
```

- [ ] **Step 2: 執行並記錄結果**

```bash
cd tmp/epic-18-issue-47-harness
node repro-fix.mjs 2>&1 | tail -30
cd ../..
```

Expected: 若 `verticalBoundsReady === true`，直排三項情境判讀邏輯與橫排完全對應（情境 C/D 無 `scrollBy` 呼叫、情境 F 有）。若 `verticalBoundsReady === false`，在後續文件中如實記錄「直排模式修復效果需真機覆核，headless 環境下 `#scrollBounds` 未能穩定填入」，比照診斷階段（`bugfix-repro-issue-47.md`「直排模式真機驗證」段）已有的既有處理方式，不得虛構直排量測數據。

- [ ] **Step 3: 在 `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md` 附加「修復確認」段落**

在檔案結尾（「下一步」段落之後）附加：

```markdown

## 修復確認（2026-08-12）

`app/android/app/src/main/assets/foliate/main.js` 新增 capture 階段
`touchstart`/`touchmove`/`touchend`/`touchcancel` 攔截（見
`plan-issue-47-fix.md` Task 1 Step 3），在長按候選期間（時間 < 500ms
且累積位移 < 15px 且平均速度 < 0.3px/ms 且選取尚未確立）呼叫
`stopImmediatePropagation()`，讓事件不會傳到 `paginator.js` 的
`#onTouchMove`。完全未修改 `paginator.js`（ADR 0011）。距離死區＋
平均速度雙門檻是審查（`tmp/epic-18/review-plan-issue-47-fix.md`
Critical #1）發現「單純距離門檻會讓 `paginator.js` 內部觸控狀態
`state.x`/`state.y` 累積誤差、放行第一個 touchmove 時一次性暴跳」
之後的修正，已用 harness 情境 E/F 的 `maxAbsDx`/`maxAbsDy` 斷言驗證
不再暴跳。

修復前後對照（橫排，`tmp/epic-18-issue-47-harness/repro-fix.mjs`，
連續重跑 3 次結果一致）：

- 情境 A（無選取）：修復前 `scrollBy` 呼叫 `{{ N }}` 次（全部實際移動）；修復後 `0` 次
- 情境 B（已有選取，對照組）：修復前後皆 `0` 次（既有守衛不受影響）
- 情境 E（快速滑動，對照組）：修復前後皆 `1` 次且確實位移（正常翻頁手勢不受影響）

直排模式：`{{ 依 Task 2 Step 2 實際結果填入：若 verticalBoundsReady
為 true，附上情境 C/D/F 對照數據；若為 false，記錄「headless 環境下
#scrollBounds 未能穩定填入，修復效果待真機覆核」}}`

**已知限制**：`SWIPE_DISTANCE_DEADZONE_PX`（15px）、
`SWIPE_VELOCITY_ESCAPE_PX_PER_MS`（0.3px/ms）與 `LONG_PRESS_GATE_MS`
（500ms）為本次選定的起始值，未經真機大規模使用者測試調校；若真機
使用後發現「正常快速滑動偶爾仍被誤判為長按候選」或「長按選字偶爾
仍位移」，需要依真機實測數據調整這三個常數，非重新設計攔截機制本身。
```

- [ ] **Step 4: 更新 `issues.md` Issue 47 段落**

依 Task 2 Step 2 的實際結果，更新 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 47 的 `**Status:**` 那一行為：

```markdown
**Status:** ✅ 已修復（2026-08-12）。`main.js` 新增長按候選期間 touchmove 攔截（capture 階段 `stopImmediatePropagation()`，距離死區＋平均速度雙門檻，未修改 `paginator.js`，見 ADR 0011），修復前後對照見 `reviews/bugfix-repro-issue-47.md`「修復確認」段——橫排模式：無選取情境的 `scrollBy` 呼叫從 N 次降為 0 次，已有選取／快速滑動兩個對照組皆不受影響且無一次性暴跳；直排模式：{{ 依實際結果填入 }}。
```

- [ ] **Step 5: Commit（`issues.md` 與診斷報告更新，`main.js` 已於 Task 1 Step 6 commit）**

```bash
git add docs/epics/epic-18-reader-device-qa/issues.md
git add docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md
git status
```

Expected: `git status` 只顯示這兩個檔案為 staged（`main.js` 已在 Task 1 commit 過，此時應顯示為 clean），`tmp/epic-18-issue-47-harness/` 不出現在任何 git 狀態輸出中。確認無誤後由人類決定是否執行 `git commit`。
