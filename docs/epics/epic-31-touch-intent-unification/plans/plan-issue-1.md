# Epic 31 Issue 1：Puppeteer 回歸測試套件正式化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `app/tool/foliate_touch_harness/` 建立一套正式進版控的 Puppeteer 回歸測試，涵蓋 4 個不依賴 `touchmove` 的觸控/選取場景，作為 Issue 2（main.js 觸控意圖分類器重構）的重構前基準線。

**Architecture:** 每個場景一支獨立可執行的 `.mjs` 腳本，共用同一個 `lib/harness.mjs` 函式庫（負責啟動 headless Chromium、透過 request interception 提供本 repo 真實的 `main.js`/`paginator.js`/`view.js`/`epub.js` 與 fixture EPUB、走 CDP `Input.dispatchTouchEvent` 送真正的觸控 input pipeline）。每支腳本印出 `[PASS]`/`[FAIL]` 並設定 `process.exitCode`；`run-all.mjs` 依序執行全部場景、彙整結果。

**Tech Stack:** Node.js（ESM）、Puppeteer `^25.6.0`（CDP `Input.dispatchTouchEvent`）、headless Chromium。

**Spec:** `docs/epics/epic-31-touch-intent-unification/design.md`（「測試策略」段落，含 Issue 1 規劃階段的實測訂正）；工單描述見 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 1。

## Global Constraints

- Puppeteer 版本鎖定 `^25.6.0`，比照本 repo 既有 harness 慣例（`docs/epics/epic-25-annotation-interaction-qa/epic-18-issue-47-harness/package.json`）。
- 全部觸控序列只用 CDP `touchStart`/`touchEnd`，**不含中途 `touchmove`**——目前環境 Chromium 版本下 `touchmove` 事件送達 iframe 不可靠，已記錄於 `design.md`「已知風險」，Issue 47／長按候選期間選取確立這兩個依賴 `touchmove` 的情境不在本工單範圍內（改由 Issue 2 真機重測把關）。
- 全部腳本針對**現行（Issue 2 尚未重構）main.js** 撰寫與驗證，不得引用任何尚未存在的 Issue 2 產物（`TouchIntentClassifier` 等）。
- 不修改 `main.js`／任何 vendored 檔案（`paginator.js`/`view.js`/`epub.js`/`overlayer.js`/`fixed-layout.js`）／`app/lib` 任一 Dart 檔案——本工單純新增測試工具，符合 ADR 0011。
- fixture EPUB 一律使用已存在於 `app/test/fixtures/` 的檔案，不新增 fixture。
- 正式存放路徑 `app/tool/foliate_touch_harness/`，不是 `app/test/`（`app/test/` 是 `flutter test` 專用 Dart 測試目錄，見 CLAUDE.md 兩層測試架構）。

---

### Task 1: 套件骨架＋共用 harness 函式庫

**Files:**
- Create: `app/tool/foliate_touch_harness/package.json`
- Create: `app/tool/foliate_touch_harness/README.md`
- Create: `app/tool/foliate_touch_harness/lib/harness.mjs`
- Create: `app/tool/foliate_touch_harness/smoke-test.mjs`

**Interfaces:**
- Produces（供 Task 2-5 使用，之後任務只看得到自己的任務內容，這裡列出完整、穩定的函式簽章）：
  - `launchHarnessPage({ fixtureFileName, writingMode = 'horizontal' }) => Promise<{ browser, page, client, pageErrors }>`
  - `locateVisibleText(page, { minLength = 8 } = {}) => Promise<{ cfi, pageX, pageY, index } | null>`
  - `cdpTap(client, x, y, holdMs) => Promise<void>`
  - `injectSelectionAtVisibleText(page, { minLength = 8 } = {}) => Promise<boolean>`（在目前可視 iframe 用 Range API 直接建立一段選取，回傳是否成功）
  - `clearSelection(page) => Promise<void>`（清除目前可視 iframe 的選取範圍）
  - `selectionState(page) => Promise<{ rangeCount, isCollapsed, text }>`
  - `harnessEvents(page) => Promise<Array<{ name, args }>>`
  - `resetHarnessEvents(page) => Promise<void>`
  - `setDecorationsAt(page, decorations) => Promise<void>`（呼叫 `window.setDecorations(decorations)`）
  - `report(name, passed, detail = '') => void`（印出 `[PASS]`/`[FAIL]`，失敗時設定 `process.exitCode = 1`）

- [ ] **Step 1: 建立目錄與 `package.json`**

先確認父目錄存在：

```bash
ls app/tool/
```

建立目錄：

```bash
mkdir -p app/tool/foliate_touch_harness/lib
```

寫入 `app/tool/foliate_touch_harness/package.json`：

```json
{
  "name": "foliate_touch_harness",
  "version": "1.0.0",
  "private": true,
  "description": "elinkBook main.js 觸控/選取行為 Puppeteer 回歸測試（epic-31 Issue 1）",
  "type": "module",
  "scripts": {
    "test": "node run-all.mjs"
  },
  "dependencies": {
    "puppeteer": "^25.6.0"
  }
}
```

- [ ] **Step 2: 安裝依賴**

```bash
cd app/tool/foliate_touch_harness && npm install
```

Expected: 產生 `node_modules/`／`package-lock.json`，`puppeteer` 安裝完成（含自動下載的 Chromium）。

- [ ] **Step 3: 撰寫共用 harness 函式庫**

寫入 `app/tool/foliate_touch_harness/lib/harness.mjs`：

```js
// 共用 Puppeteer harness 設施：serve 本 repo 真實 foliate/ 資產＋fixture
// EPUB，走 CDP Input.dispatchTouchEvent 真正的瀏覽器 input pipeline。
// 供 app/tool/foliate_touch_harness/ 下每支情境腳本 import 使用。
//
// 【重要】只用 touchStart/touchEnd（cdpTap），不提供 touchmove 相關
// helper——目前環境 Chromium 版本下 CDP touchmove 事件送達 iframe 不
// 可靠（見 docs/epics/epic-31-touch-intent-unification/design.md
// 「已知風險」），依賴 touchmove 的場景不在本套件範圍內。

import puppeteer from 'puppeteer'
import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
export const FOLIATE_DIR = path.resolve(__dirname, '../../../android/app/src/main/assets/foliate')
export const FIXTURES_DIR = path.resolve(__dirname, '../../../test/fixtures')
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

/**
 * 啟動一個載入本 repo 真實 main.js/paginator.js/view.js/epub.js 與指定
 * fixture EPUB 的 headless 頁面。呼叫端用完須自行
 * `await browser.close()`。
 */
export async function launchHarnessPage({ fixtureFileName, writingMode = 'horizontal' }) {
  const relFiles = await listFilesRecursive(FOLIATE_DIR)
  const fileMap = new Map()
  for (const rel of relFiles) fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)))
  const fixtureBuf = await readFile(path.join(FIXTURES_DIR, fixtureFileName))

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] })
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
  const pageErrors = []
  page.on('pageerror', (err) => pageErrors.push(String(err)))

  await page.evaluateOnNewDocument(() => {
    window.__harnessEvents = []
    window.flutter_inappwebview = {
      callHandler: async (name, ...args) => { window.__harnessEvents.push({ name, args }) },
    }
  })

  const initialPrefs = {
    writingMode, fontSize: 1.0, lineHeight: 1.0,
    paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16,
    marginLeft: 24, marginRight: 24,
    pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
  }
  const openUrl = `${ORIGIN}/index.html?prefs=${encodeURIComponent(JSON.stringify(initialPrefs))}&fontFaceCss=&initialCfi=`
  await page.setViewport({ width: 800, height: 1200, hasTouch: true })
  await page.goto(openUrl, { waitUntil: 'load' })
  await page.waitForFunction(
    () => window.__harnessEvents.some((e) => e.name === 'onPageRendered'),
    { timeout: 15000 },
  )
  await page.waitForFunction(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    for (const iframe of container?.querySelectorAll('iframe') ?? []) {
      const text = iframe.contentDocument?.body?.textContent?.trim() ?? ''
      if (text.length > 20) return true
    }
    return false
  }, { timeout: 10000 })
  await new Promise((r) => setTimeout(r, 300))

  const client = page._client()
  return { browser, page, client, pageErrors }
}

/** 找目前可視 iframe 內第一段長度 > minLength 的文字節點，回傳其 CFI、
 * 畫面座標（page 座標系）與所屬 index。找不到回傳 null。 */
export async function locateVisibleText(page, { minLength = 8 } = {}) {
  return page.evaluate((minLength) => {
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
        if ((node.nodeValue ?? '').trim().length <= minLength) continue
        const range = doc.createRange()
        range.setStart(node, 0)
        range.setEnd(node, Math.min(minLength, node.nodeValue.length))
        const rect = range.getClientRects()[0]
        if (!rect) continue
        const pageX = iframeRect.left + rect.left + rect.width / 2
        const pageY = iframeRect.top + rect.top + rect.height / 2
        const visible = pageX >= 0 && pageX < window.innerWidth && pageY >= 0 && pageY < window.innerHeight
        if (!visible) continue
        const index = fv.renderer.getContents().find((c) => c.doc === doc)?.index
        const cfi = fv.getCFI(index, range)
        return { cfi, pageX, pageY, index }
      }
    }
    return null
  }, minLength)
}

/** 用 CDP 走真正的觸控 input pipeline 做一次「按下→等待→放開」
 * （不含中途 touchmove，見本檔案頂部說明）。 */
export async function cdpTap(client, x, y, holdMs) {
  await client.send('Input.dispatchTouchEvent', {
    type: 'touchStart', touchPoints: [{ x, y, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
  })
  await new Promise((r) => setTimeout(r, holdMs))
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
}

/** 在目前可視 iframe 上，用 Range API 直接注入一段選取（模擬「選取已
 * 存在」，不經過真實長按手勢——CDP 觸控無法建立原生選取，見
 * design.md「測試策略」）。回傳是否成功找到可注入的文字節點。 */
export async function injectSelectionAtVisibleText(page, { minLength = 8 } = {}) {
  return page.evaluate((minLength) => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    const doc = container?.querySelector('iframe')?.contentDocument
    if (!doc) return false
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let node = null
    while (walker.nextNode()) {
      if ((walker.currentNode.nodeValue || '').trim().length > minLength) { node = walker.currentNode; break }
    }
    if (!node) return false
    const sel = doc.getSelection()
    sel.removeAllRanges()
    const range = doc.createRange()
    range.setStart(node, 0)
    range.setEnd(node, Math.min(minLength, node.nodeValue.length))
    sel.addRange(range)
    return true
  }, minLength)
}

/** 清除目前可視 iframe 的選取範圍。 */
export function clearSelection(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    container?.querySelector('iframe')?.contentDocument?.getSelection()?.removeAllRanges()
  })
}

/** 讀目前可視 iframe 的選取狀態。 */
export function selectionState(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    const doc = container?.querySelector('iframe')?.contentDocument
    const sel = doc.getSelection()
    return { rangeCount: sel.rangeCount, isCollapsed: sel.isCollapsed, text: sel.toString() }
  })
}

export function harnessEvents(page) {
  return page.evaluate(() => window.__harnessEvents)
}

export function resetHarnessEvents(page) {
  return page.evaluate(() => { window.__harnessEvents = [] })
}

export function setDecorationsAt(page, decorations) {
  return page.evaluate((decorations) => { window.setDecorations(decorations) }, decorations)
}

/** 印出「[PASS] name」/「[FAIL] name — detail」，失敗時設定
 * process.exitCode = 1（不會覆蓋已經是非 0 的值）。 */
export function report(name, passed, detail = '') {
  const status = passed ? 'PASS' : 'FAIL'
  console.log(`[${status}] ${name}${detail ? ' — ' + detail : ''}`)
  if (!passed) process.exitCode = 1
}
```

- [ ] **Step 4: 撰寫 smoke test，驗證函式庫本身可用**

寫入 `app/tool/foliate_touch_harness/smoke-test.mjs`：

```js
// 驗證 lib/harness.mjs 本身可用：能開頁、能找到可視文字、能注入選取、
// 能建立畫線並讀到 harness 事件。不測任何觸控攔截邏輯（那是其他情境
// 腳本的事），純粹是函式庫的健檢。

import {
  launchHarnessPage, locateVisibleText, injectSelectionAtVisibleText,
  selectionState, setDecorationsAt, harnessEvents, resetHarnessEvents, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    const target = await locateVisibleText(page, { minLength: 8 })
    report('找到可視文字節點並取得 CFI', !!target?.cfi, JSON.stringify(target))

    await setDecorationsAt(page, [{ id: 'smoke-highlight', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await resetHarnessEvents(page)

    const injected = await injectSelectionAtVisibleText(page, { minLength: 8 })
    report('成功注入選取範圍', injected === true)

    await new Promise((r) => setTimeout(r, 300))
    const state = await selectionState(page)
    report('選取狀態正確回報為非折疊', state.isCollapsed === false, JSON.stringify(state))

    const events = await harnessEvents(page)
    const hasSelChanged = events.some((e) => e.name === 'onSelectionChanged')
    report('onSelectionChanged bridge 事件有觸發', hasSelChanged, JSON.stringify(events.map((e) => e.name)))
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [ ] **Step 5: 執行 smoke test，確認全部 PASS**

```bash
cd app/tool/foliate_touch_harness && node smoke-test.mjs
```

Expected: 4 行 `[PASS] ...`，沒有任何 `[FAIL]`，`process.exitCode` 為 0（可用 `echo $?` 確認，PowerShell 用 `$LASTEXITCODE`）。

- [ ] **Step 6: Commit**

```bash
git add app/tool/foliate_touch_harness/package.json app/tool/foliate_touch_harness/package-lock.json app/tool/foliate_touch_harness/lib/harness.mjs app/tool/foliate_touch_harness/smoke-test.mjs
git commit -m "test(epic-31): 建立 foliate_touch_harness 共用函式庫與 smoke test"
```

（`node_modules/` 不要加入版控——確認 repo 根目錄 `.gitignore` 已有 `**/node_modules/`，見 `U:\MyDeveloper\AI\elinkBook\.gitignore` 第 20 行。）

---

### Task 2: Epic 25 Issue 4 情境（快速點擊 vs. 畫線點擊）

**Files:**
- Create: `app/tool/foliate_touch_harness/scenario-epic25-issue4-fast-tap.mjs`

**Interfaces:**
- Consumes: Task 1 的 `launchHarnessPage`／`locateVisibleText`／`setDecorationsAt`／`resetHarnessEvents`／`harnessEvents`／`cdpTap`／`report`（簽章見 Task 1）。
- Produces: 無（獨立可執行腳本，供 Task 6 的 `run-all.mjs` 呼叫）。

**背景**：main.js 的 `ANNOTATION_CLICK_TAP_MAX_MS = 700` 機制，按壓 ≤700ms 判定為快速點擊、攔截 `click` 不讓它傳到畫線的 `hitTest` 監聽器（`onAnnotationActivated` 不會觸發）；按壓 >700ms 判定為刻意操作、放行（`onAnnotationActivated` 正常觸發）；超連結一律排除，不受影響。

- [x] **Step 1: 撰寫情境腳本**

寫入 `app/tool/foliate_touch_harness/scenario-epic25-issue4-fast-tap.mjs`：

```js
import {
  launchHarnessPage, locateVisibleText, setDecorationsAt,
  cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample_long_chinese_vertical.epub',
    writingMode: 'vertical',
  })
  try {
    const target = await locateVisibleText(page, { minLength: 6 })
    if (!target) { report('找到可視文字節點', false); return }

    await setDecorationsAt(page, [{ id: 'target', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await new Promise((r) => setTimeout(r, 200))

    // 監聽 foliate-view 上的 show-annotation 事件（view.js 在 click 命中
    // 畫線且未被 main.js 攔截時發出），記錄觸發次數。
    await page.evaluate(() => {
      window.__showAnnotationFired = 0
      document.querySelector('foliate-view')?.addEventListener('show-annotation', () => {
        window.__showAnnotationFired++
      })
    })

    // 情境 A：短按（80ms）直接點在畫線上，應被攔截，不觸發
    // show-annotation。
    await page.evaluate(() => { window.__showAnnotationFired = 0 })
    await cdpTap(client, target.pageX, target.pageY, 80)
    await new Promise((r) => setTimeout(r, 300))
    const shortTapFired = await page.evaluate(() => window.__showAnnotationFired)
    report('短按 80ms 直接點在畫線上，click 被攔截', shortTapFired === 0)

    // 情境 B：長按（900ms，原地不動）直接點在畫線上，應正常觸發
    // show-annotation（900ms > ANNOTATION_CLICK_TAP_MAX_MS=700ms）。
    await page.evaluate(() => { window.__showAnnotationFired = 0 })
    await cdpTap(client, target.pageX, target.pageY, 900)
    await new Promise((r) => setTimeout(r, 300))
    const longPressFired = await page.evaluate(() => window.__showAnnotationFired)
    report('長按 900ms 直接點在畫線上，click 正常觸發', longPressFired > 0)

    // 情境 C：短按（80ms）點在超連結上，連結點擊不受畫線攔截邏輯影響
    // （main.js 明確排除 a[href]）。動態插入 <a> 到目前可視 doc，純測試
    // target.closest('a[href]') 排除邏輯，不依賴 fixture 本身含超連結。
    const linkSetup = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const doc = iframe?.contentDocument
      if (!doc?.body) return null
      const a = doc.createElement('a')
      a.href = '#test-link'
      a.textContent = 'LINK'
      a.style.position = 'absolute'
      a.style.left = '40px'
      a.style.top = '40px'
      a.style.zIndex = '9999'
      doc.body.appendChild(a)
      window.__linkClicked = false
      a.addEventListener('click', (e) => { e.preventDefault(); window.__linkClicked = true })
      const rect = a.getBoundingClientRect()
      const iframeRect = iframe.getBoundingClientRect()
      return { pageX: iframeRect.left + rect.left + rect.width / 2, pageY: iframeRect.top + rect.top + rect.height / 2 }
    })
    if (linkSetup) {
      await cdpTap(client, linkSetup.pageX, linkSetup.pageY, 80)
      await new Promise((r) => setTimeout(r, 300))
      const linkClicked = await page.evaluate(() => window.__linkClicked === true)
      report('短按 80ms 點在超連結上，連結點擊不受影響', linkClicked)
    } else {
      report('短按 80ms 點在超連結上，連結點擊不受影響', false, '無法插入測試用連結元素')
    }
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [x] **Step 2: 執行並確認全數 PASS**

```bash
cd app/tool/foliate_touch_harness && node scenario-epic25-issue4-fast-tap.mjs
```

Expected: 3 行 `[PASS] ...`。

- [x] **Step 3: Commit**

```bash
git add app/tool/foliate_touch_harness/scenario-epic25-issue4-fast-tap.mjs
git commit -m "test(epic-31): 新增 Epic 25 Issue 4 快速點擊攔截回歸測試"
```

---

### Task 3: Issue 10 情境（選取收尾保護）

**Files:**
- Create: `app/tool/foliate_touch_harness/scenario-issue10-selection-release-guard.mjs`

**Interfaces:**
- Consumes: Task 1 的 `launchHarnessPage`／`injectSelectionAtVisibleText`／`selectionState`／`cdpTap`／`report`。
- Produces: 無。

**背景**：main.js 的 `SELECTION_RELEASE_GUARD_MS = 150` 機制——選取剛確立（非折疊）之後 150ms 內若發生 `mousedown`，會被攔截（`preventDefault()`），避免使用者放開手指的收尾動作被誤判為新點擊而折疊既有選取。

**已知範圍限制（誠實記錄）**：原始 Issue 10 bug 是「拖曳選取控點後放開」的場景，本測試無法用 CDP 模擬真實拖曳控點手勢（`touchmove` 不可靠，見 Global Constraints），改為「選取剛確立後立刻做一次短按（`touchStart`/`touchEnd`，不含 `touchmove`）」，直接測試 `SELECTION_RELEASE_GUARD_MS` 這個實際的生產機制本身，不是重現原始拖曳手勢。

- [ ] **Step 1: 撰寫情境腳本**

寫入 `app/tool/foliate_touch_harness/scenario-issue10-selection-release-guard.mjs`：

```js
import {
  launchHarnessPage, injectSelectionAtVisibleText, clearSelection, selectionState, cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample_horizontal.epub',
    writingMode: 'horizontal',
  })
  try {
    // 情境 A：選取剛確立，立刻在選取本身位置做一次短按——保護期內，
    // 選取應維持存在。
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    const beforeA = await selectionState(page)
    const rectA = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const sel = iframe?.contentDocument?.getSelection()
      const r = sel?.getRangeAt(0)?.getClientRects()?.[0]
      const iframeRect = iframe?.getBoundingClientRect()
      if (!r || !iframeRect) return null
      return { x: iframeRect.left + r.left + r.width / 2, y: iframeRect.top + r.top + r.height / 2 }
    })
    if (!rectA) { report('取得選取範圍畫面座標（情境 A）', false); return }
    await cdpTap(client, rectA.x, rectA.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterA = await selectionState(page)
    report('選取剛確立、保護期內在選取本身位置短按，選取維持存在',
      !beforeA.isCollapsed && !afterA.isCollapsed,
      `before.isCollapsed=${beforeA.isCollapsed}, after.isCollapsed=${afterA.isCollapsed}`)

    // 情境 B（對照組）：選取確立後等待超過保護期（150ms），再點擊選取
    // 以外的位置——保護期已過，選取應正常被折疊（證明保護不是永久生效，
    // 只在收尾雜訊窗口內生效）。
    await clearSelection(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    const beforeB = await selectionState(page)
    const awayPoint = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const r = iframe?.getBoundingClientRect()
      if (!r) return null
      return { x: r.left + r.width * 0.9, y: r.top + r.height * 0.9 }
    })
    if (!awayPoint) { report('取得遠離選取範圍的座標（情境 B）', false); return }
    await new Promise((r) => setTimeout(r, 250))
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterB = await selectionState(page)
    report('選取收尾保護期已過後點擊別處，選取正常被折疊',
      !beforeB.isCollapsed && afterB.isCollapsed,
      `before.isCollapsed=${beforeB.isCollapsed}, after.isCollapsed=${afterB.isCollapsed}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [ ] **Step 2: 執行並確認全數 PASS**

```bash
cd app/tool/foliate_touch_harness && node scenario-issue10-selection-release-guard.mjs
```

Expected: 2 行 `[PASS] ...`。

- [ ] **Step 3: Commit**

```bash
git add app/tool/foliate_touch_harness/scenario-issue10-selection-release-guard.mjs
git commit -m "test(epic-31): 新增 Issue 10 選取收尾保護回歸測試"
```

---

### Task 4: Issue 11 情境（`hitTest` 命中判斷）

**Files:**
- Create: `app/tool/foliate_touch_harness/scenario-issue11-hittest-existing-highlight.mjs`

**Interfaces:**
- Consumes: Task 1 的 `launchHarnessPage`／`locateVisibleText`／`setDecorationsAt`／`resetHarnessEvents`／`harnessEvents`／`injectSelectionAtVisibleText`／`clearSelection`／`report`。
- Produces: 無。

**背景**：main.js 的 `reportSelection()` 在選取變動時，用 `overlayer.hitTest()` 查詢選取範圍中點是否命中既有畫線裝飾，命中則把該畫線的 id（`decorationIdByCfi.get(hitCfi)`）當作 `onSelectionChanged` bridge call 最後一個參數（`existingAnnotationId`）送給 Dart 端；沒命中則是 `null`。

- [ ] **Step 1: 撰寫情境腳本**

寫入 `app/tool/foliate_touch_harness/scenario-issue11-hittest-existing-highlight.mjs`：

```js
import {
  launchHarnessPage, locateVisibleText, setDecorationsAt,
  resetHarnessEvents, harnessEvents, injectSelectionAtVisibleText, clearSelection, report,
} from './lib/harness.mjs'

function lastExistingAnnotationId(events) {
  const lastSelChanged = [...events].reverse().find((e) => e.name === 'onSelectionChanged')
  if (!lastSelChanged) return undefined
  return lastSelChanged.args[lastSelChanged.args.length - 1]
}

async function main() {
  const { browser, page } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    const target = await locateVisibleText(page, { minLength: 8 })
    if (!target) { report('找到可視文字節點', false); return }

    // 情境 A：選取範圍命中既有畫線，existingAnnotationId 應等於該畫線
    // 的 id。
    await setDecorationsAt(page, [{ id: 'existing-highlight', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await new Promise((r) => setTimeout(r, 200))
    await resetHarnessEvents(page)
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    await new Promise((r) => setTimeout(r, 300))
    const eventsA = await harnessEvents(page)
    const hitIdA = lastExistingAnnotationId(eventsA)
    report('選取命中既有畫線，existingAnnotationId 正確回報',
      hitIdA === 'existing-highlight', `實際值=${JSON.stringify(hitIdA)}`)

    // 情境 B（對照組）：清掉畫線後，同一段選取不該再命中任何東西。
    await setDecorationsAt(page, [])
    await new Promise((r) => setTimeout(r, 200))
    await clearSelection(page)
    await resetHarnessEvents(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    await new Promise((r) => setTimeout(r, 300))
    const eventsB = await harnessEvents(page)
    const hitIdB = lastExistingAnnotationId(eventsB)
    report('畫線已刪除後，同段選取不再命中任何畫線',
      hitIdB === null, `實際值=${JSON.stringify(hitIdB)}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [ ] **Step 2: 執行並確認全數 PASS**

```bash
cd app/tool/foliate_touch_harness && node scenario-issue11-hittest-existing-highlight.mjs
```

Expected: 2 行 `[PASS] ...`。

- [ ] **Step 3: Commit**

```bash
git add app/tool/foliate_touch_harness/scenario-issue11-hittest-existing-highlight.mjs
git commit -m "test(epic-31): 新增 Issue 11 hitTest 命中判斷回歸測試"
```

---

### Task 5: 跨機制測試（快速點擊門檻邊界時選取狀態同時變動）

**Files:**
- Create: `app/tool/foliate_touch_harness/scenario-cross-mechanism-tap-boundary.mjs`

**Interfaces:**
- Consumes: Task 1 的 `launchHarnessPage`／`injectSelectionAtVisibleText`／`clearSelection`／`selectionState`／`cdpTap`／`report`。
- Produces: 無。

**背景**：這是本 Epic 新增的跨機制情境，驗證「選取收尾保護」（`SELECTION_RELEASE_GUARD_MS`）與「快速點擊分類」（`ANNOTATION_CLICK_TAP_MAX_MS`）這兩個獨立機制在**同一個觸控事件**上不會互相干擾——選取存在時，一次快速點擊別處，click 事件本身仍正常合成（不受選取保護機制影響），但選取要看時機是否還在保護期內決定要不要被折疊。與 Task 3 的差異：Task 3 測「點在選取本身位置」，本情境測「點在選取以外的位置＋保護期邊界時機」。

- [ ] **Step 1: 撰寫情境腳本**

寫入 `app/tool/foliate_touch_harness/scenario-cross-mechanism-tap-boundary.mjs`：

```js
import {
  launchHarnessPage, injectSelectionAtVisibleText, clearSelection, selectionState, cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    const awayPoint = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const r = iframe?.getBoundingClientRect()
      if (!r) return null
      return { x: r.left + r.width * 0.9, y: r.top + r.height * 0.9 }
    })
    if (!awayPoint) { report('取得遠離選取範圍的座標', false); return }

    // 情境 A：選取確立後立刻（保護期 150ms 內）快速點擊別處——click 本身
    // 正常合成（不受選取保護機制阻擋），且選取應該維持存在（mousedown
    // 被攔截）。
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    const beforeA = await selectionState(page)
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterA = await selectionState(page)
    report('選取收尾保護期內快速點擊別處，選取維持存在',
      !beforeA.isCollapsed && !afterA.isCollapsed,
      `before.isCollapsed=${beforeA.isCollapsed}, after.isCollapsed=${afterA.isCollapsed}`)

    // 情境 B（邊界對照組）：選取確立後等待超過保護期（250ms > 150ms）
    // 才點擊別處——選取這時應該正常被折疊，證明「快速點擊分類」機制
    // 本身仍正常運作、沒有被選取保護機制永久卡住。
    await clearSelection(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    const beforeB = await selectionState(page)
    await new Promise((r) => setTimeout(r, 250))
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterB = await selectionState(page)
    report('選取收尾保護期已過後快速點擊別處，選取正常被折疊',
      !beforeB.isCollapsed && afterB.isCollapsed,
      `before.isCollapsed=${beforeB.isCollapsed}, after.isCollapsed=${afterB.isCollapsed}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [ ] **Step 2: 執行並確認全數 PASS**

```bash
cd app/tool/foliate_touch_harness && node scenario-cross-mechanism-tap-boundary.mjs
```

Expected: 2 行 `[PASS] ...`。

- [ ] **Step 3: Commit**

```bash
git add app/tool/foliate_touch_harness/scenario-cross-mechanism-tap-boundary.mjs
git commit -m "test(epic-31): 新增選取保護與快速點擊分類的跨機制回歸測試"
```

---

### Task 6: 彙整執行腳本＋README＋全綠驗證

**Files:**
- Create: `app/tool/foliate_touch_harness/run-all.mjs`
- Modify: `app/tool/foliate_touch_harness/README.md`

**Interfaces:**
- Consumes: Task 2-5 產出的全部 `scenario-*.mjs` 檔名規律（`scenario-` 開頭、`.mjs` 結尾）。
- Produces: 無（本工單最終驗收用的彙整腳本）。

- [ ] **Step 1: 撰寫彙整執行腳本**

寫入 `app/tool/foliate_touch_harness/run-all.mjs`：

```js
// 依序執行本目錄下全部 scenario-*.mjs，彙整 PASS/FAIL 結果。
// smoke-test.mjs 不算在內（那是函式庫健檢，不是正式回歸場景）。

import { spawnSync } from 'node:child_process'
import { readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

async function main() {
  const files = (await readdir(__dirname))
    .filter((f) => f.startsWith('scenario-') && f.endsWith('.mjs'))
    .sort()

  if (files.length === 0) {
    console.error('找不到任何 scenario-*.mjs')
    process.exitCode = 2
    return
  }

  let anyFailed = false
  for (const file of files) {
    console.log(`\n=== ${file} ===`)
    const result = spawnSync('node', [path.join(__dirname, file)], { stdio: 'inherit' })
    if (result.status !== 0) anyFailed = true
  }

  console.log(anyFailed ? '\n整體結果：FAIL' : '\n整體結果：全部 PASS')
  process.exitCode = anyFailed ? 1 : 0
}

main()
```

- [ ] **Step 2: 執行彙整腳本，確認全數 PASS**

```bash
cd app/tool/foliate_touch_harness && node run-all.mjs
```

Expected: 依序看到 4 個 `=== scenario-*.mjs ===` 區塊，每個區塊內全是 `[PASS]`，結尾印出「整體結果：全部 PASS」。

- [ ] **Step 3: 撰寫 README**

寫入 `app/tool/foliate_touch_harness/README.md`：

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add app/tool/foliate_touch_harness/run-all.mjs app/tool/foliate_touch_harness/README.md
git commit -m "test(epic-31): 新增回歸測試彙整腳本與 README，Issue 1 完成"
```

- [ ] **Step 5: 更新工單狀態**

在 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 1 的 `**Status:**` 那一行，改為記錄已完成（PR 編號待實際發 PR 時補上），並在下方補一段簡短總結（4 個場景全過、Issue 47／長按候選跨機制情境已知不在自動化範圍內，交給 Issue 2 真機重測）。
