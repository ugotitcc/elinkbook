# Epic 25 Issue 4 — 換頁點擊位置與相鄰頁畫線重疊時誤跳出刪除確認對話框 修復計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復真機資料已確認的誤觸發——3×3 換頁熱區點擊與畫線點擊共用同一組觸控手勢、同一螢幕座標，點擊座標若剛好落在既有畫線位置上，會誤跳出「是否刪除畫線」確認對話框。採用人類確認的產品方向：以按壓時長作為判斷依據，快速點擊（≤700ms）視為換頁意圖、攔截原生 click 傳給畫線點擊監聽器的機會；按壓夠久（>700ms）視為使用者確實想操作畫線，正常放行。同時清除 `plan-issue-4-realdevice-diagnostics.md` 留下的 `[DEBUG-e25i4]` 暫時性診斷插樁。

**Architecture:** 真機資料（`tmp/epic-25/log-issue4/`，六份 log）證實：誤觸發時 `click` 事件相對 `window.nextPage() called` 的時序**不固定**（有時 click 先、有時 nextPage() 先），兩種順序都會誤觸發同一筆畫線——純時序競速修法（例如仿照 Issue 47 的「攔截+補呼叫」）無法涵蓋這個情況，因為兩種情境的觸控事件本身完全相同，差別只在於「那個座標底下剛好有沒有畫線」，這是產品層級的手勢語意衝突，不是單純的競速 bug。修法在 `main.js`（本專案自有整合層，非 vendored）既有的 `view.addEventListener('load', ...)` hook 內，新增一組 capture 階段 `touchstart`/`click` 監聽器：`touchstart` 記錄時間戳，`click` 觸發時計算與對應 `touchstart` 的時間差，若 ≤700ms（比照既有 `_NavZoneTapDetector._tapMaxDurationMs`，維持 Dart／JS 兩側一致的「多短算快速點擊」心智模型）就呼叫 `stopImmediatePropagation()`，攔截這次 click 傳到 vendored `view.js` `#createOverlayer`（`view.js:440`）註冊的畫線點擊 hitTest 監聽器；同一 `doc` 節點上還有 `#handleLinks`（`view.js:356`）的超連結點擊監聽器，兩者皆為 bubble 階段、會被同一次 `stopImmediatePropagation()` 一併攔截，故明確排除 `evt.target.closest('a[href]')` 的情況、一律放行，避免快速點擊書本內文超連結被連帶攔截（規劃階段已用原始碼交叉核對＋headless 實測確認此風險與修法有效性）。

**Tech Stack:** `main.js`（vendored foliate-js 整合層，ADR 0011 允許修改）＋ Flutter/Dart（`reader_screen.dart` 清除插樁）。

## Global Constraints

- 完全不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js` 等）——只在 `main.js` 既有整合層新增程式碼（ADR 0011）。
- 門檻值固定 **700ms**，比照 `foliate_epub_reader_view.dart` 既有 `_NavZoneTapDetector._tapMaxDurationMs`（Epic 25 Issue 1 真機多輪校準得出的值）——兩側各自獨立判斷，不透過橋接同步，純粹數值上取一致，避免額外跨執行緒往返延遲；若未來 Issue 1 的 `_tapMaxDurationMs` 再次調整，本處門檻值需一併檢視是否同步調整（非自動連動，需人工比對）。
- **明確排除超連結點擊**（`evt.target.closest('a[href]')` 為真時一律不攔截）——已用原始碼交叉核對確認 `#handleLinks`（`view.js:356`）與 `#createOverlayer`（`view.js:440`）是同一個 `doc` 節點上兩個獨立的 bubble 階段 `click` 監聽器，`stopImmediatePropagation()` 若不排除超連結情境會連帶攔截超連結點擊，此為規劃階段用原始碼查證＋headless 實測確認的真實風險，不是臆測。
- **排除選擇器刻意維持 `a[href]`，不擴充到 `role="link"`／`role="button"`／`button`／`input`／`select`／`textarea`**（獨立審查報告 `tmp/epic-25/plan-issue-4-fix-review-report.md` Important #1 曾建議擴充，已查證後駁回，記錄於此避免下一位讀者重新查證一次）：`grep -rn "addEventListener(['\"]click" *.js` 對整個 vendored＋整合層（`paginator.js`／`view.js`／`epub.js`／`main.js`）逐一核對，確認全檔只有 3 個 `doc` 層級 `click` 監聽器——本監聽器（`main.js:679`）、`#handleLinks`（`view.js:356`，選擇器就是 `a[href]`，與本監聽器排除條件逐字相同）、`#createOverlayer`（`view.js:440`，本修法要攔截的目標）。沒有任何監聽器處理 `role="button"`／`button`／`input`／`select`／`textarea`——擴充排除範圍不會保護任何現存功能，只會讓這些元素若與畫線重疊時，重新出現本次要修的誤觸發（與修法目標相反）。審查報告另提及 SVG `xlink:href` 連結技術上不會被 `a[href]` 匹配（無命名空間前綴的屬性選擇器不比對 `xlink:href`）——查證屬實，但 `#handleLinks` 自己也用同一個 `a[href]` 選擇器，代表這類連結在本 App 裡本來就不會被判定成可導覽連結，本修法排不排除都不影響其可點性，只影響「疊到畫線時要不要跳出對話框」，沒有真正的功能利害關係，故不處理。
- **`touchcancel` 需重置 `annotationClickTouchStartTime`**（獨立審查報告 Minor #1，查證後接受）——若觸控過程中被系統手勢／多點觸控中斷發出 `touchcancel` 而未重置，時間戳變數會殘留上一次觸控的值；雖然下一次真正的 `touchstart`會覆蓋掉這個殘留值（自我修復，不會造成永久性錯誤判定），但比照 Issue 47 既有 `longPressGateState` 在類似事件上主動重置狀態的既有模式，補上這個監聽器讓狀態機沒有殘留死角，成本極低。
- **已知殘留限制（誠實記錄，非聲稱 100% 解決）**：「長按後仍會合成 click 事件」這件事只在 headless Chromium 驗證過（見 Task 1 Step 5，情境 B 通過）——真機 Android WebView 對「原地不動的長按後放開」是否一律仍合成 `click`、抑或某些情況下改觸發原生選取/context menu UI 而完全不產生 `click`，規劃階段**未經真機驗證**，屬於已知的 headless-vs-真機落差類別（比照本 Epic 已多次記錄的既有限制）。若真機驗證後發現長按放開不會產生 click，代表「長按查看/編輯既有畫線」這條路徑在真機上可能完全失效，需要另立 Issue 補一個不依賴 click 事件的替代互動方式（例如側邊欄劃線清單），不在本計畫範圍內搶先設計。
- 本計畫的 Task 2（移除插樁）必須確認 `grep -rn "DEBUG-e25i4"` 在 `app/lib`／`app/android/app/src/main/assets/foliate` 底下完全乾淨，比照 `plan-issue-4-realdevice-diagnostics.md` 已承諾的收尾動作。

---

### Task 1：`main.js` 實作按壓時長判斷修法，headless 驗證三種情境

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:667-681`（取代既有 `[DEBUG-e25i4]` 純觀察 `touchend`/`click` 診斷監聽器為正式修法）

**Interfaces:**
- Consumes：既有 `doc`（`view.addEventListener('load', (e) => {...})` hook 的區域變數閉包，`main.js:614` 附近）。
- Produces：無新增可供其他 Task 呼叫的函式——修法本體是純觀察轉攔截的 capture 階段監聽器，不對外暴露介面。

- [ ] **Step 1：取代診斷監聽器為正式修法**

修改 `app/android/app/src/main/assets/foliate/main.js`，把既有的 `[DEBUG-e25i4]` 診斷區塊（第 667-681 行，`doc.addEventListener('touchend', ...)` 與 `doc.addEventListener('click', ...)` 兩段純觀察 log）整段取代為：

```javascript
      // Epic 25 Issue 4 修法：nav-zone 熱區點擊與畫線點擊共用同一組觸控
      // 手勢、同一螢幕座標，兩者天生無法用純技術訊號區分意圖（真機資料已
      // 證實：click 事件命中畫線的時序有時早於、有時晚於
      // window.nextPage() 實際執行，純時序競速修法無法涵蓋兩種情況，見
      // docs/epics/epic-25-annotation-interaction-qa/issues.md Issue 4）。
      // 採用人類確認的產品方向：按壓時長作為判斷依據——快速點擊視為換頁
      // 意圖，攔截合成 click 事件、不讓它傳到 view.js #createOverlayer
      // 註冊的畫線點擊 hitTest 監聽器（view.js:440，bubble 階段）；按壓
      // 夠久則視為使用者確實想操作畫線，不攔截，讓 click 正常傳遞。門檻
      // 值 700ms 比照既有 _NavZoneTapDetector._tapMaxDurationMs
      // （foliate_epub_reader_view.dart，Epic 25 Issue 1 真機多輪校準得出
      // 的同一個值），維持 Dart／JS 兩側一致的「多短算快速點擊」心智模型
      // （兩者各自獨立判斷，不透過橋接同步，純粹數值上取一致，避免額外
      // 跨執行緒往返）。
      //
      // 【明確排除超連結點擊，真實回歸非假設性風險】#handleLinks
      // （view.js:353-380）的超連結點擊監聽器與 #createOverlayer 的畫線
      // 點擊監聽器是同一個 doc 節點上兩個獨立的 bubble 階段 click 監聽器，
      // stopImmediatePropagation() 會讓「呼叫當下尚未執行」的其餘監聽器
      // 整個收不到事件（不分是否與畫線相關）——若不排除超連結，快速點擊
      // 書本內文超連結會連帶失效，已用原始碼交叉核對排除此風險。排除條件
      // 選用與 #handleLinks 完全相同的 a[href] 選擇器（非更寬的
      // role="link"/button/input 等）：已用 grep 逐一核對整個 vendored＋
      // 整合層（paginator.js/view.js/epub.js/main.js）只有 main.js:679（本
      // 監聽器）、view.js:356（#handleLinks）、view.js:440
      // （#createOverlayer）三個 doc 層級 click 監聽器，沒有任何監聽器處理
      // role="button"/button/input/select/textarea——擴大排除範圍不會保護
      // 任何現存功能，只會讓這些元素若與畫線重疊時重新出現本次要修的誤觸
      // 發，故刻意不擴充（獨立審查報告 `tmp/epic-25/
      // plan-issue-4-fix-review-report.md` 建議擴充，已查證後維持現狀，
      // 詳見 Global Constraints）。
      const ANNOTATION_CLICK_TAP_MAX_MS = 700
      let annotationClickTouchStartTime = null
      doc.addEventListener('touchstart', (evt) => {
        annotationClickTouchStartTime = evt.touches.length === 1 ? evt.timeStamp : null
      }, { capture: true })
      doc.addEventListener('touchcancel', () => {
        annotationClickTouchStartTime = null
      }, { capture: true })
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

- [ ] **Step 2：語法檢查**

Run: `node --check app/android/app/src/main/assets/foliate/main.js`
Expected: 無輸出、exit code 0。

- [ ] **Step 3：建立 headless 驗證腳本**

建立 `tmp/epic-25-issue-4-harness/fix-verify.mjs`（比照既有 `tmp/epic-25-issue-4-harness/repro.mjs` 慣例，`node_modules` 已存在可直接重用）：

```javascript
// Epic 25 Issue 4 修法驗證：短按（<=700ms）應攔截畫線點擊，長按（>700ms）
// 與超連結點擊應正常放行。

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
  for (const rel of relFiles) fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)))
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
        callHandler: async (name, ...args) => { window.__harnessEvents.push({ name, args }) },
      }
    })

    const initialPrefs = {
      writingMode: 'vertical', fontSize: 1.0, lineHeight: 1.0,
      paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16,
      marginLeft: 24, marginRight: 24,
      pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
    }
    const openUrl = `${ORIGIN}/index.html?prefs=${encodeURIComponent(JSON.stringify(initialPrefs))}&fontFaceCss=&initialCfi=`
    await page.setViewport({ width: 800, height: 1200, hasTouch: true })
    await page.goto(openUrl, { waitUntil: 'load' })
    await page.waitForFunction(() => window.__harnessEvents.some((e) => e.name === 'onPageRendered'), { timeout: 15000 })
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
    await new Promise((r) => setTimeout(r, 1000))

    // 取得一段文字的 CFI + page-level 座標（比照既有 repro.mjs 手法）。
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
            const visible = pageX >= 0 && pageX < window.innerWidth && pageY >= 0 && pageY < window.innerHeight
            if (!visible) continue
            const index = fv.renderer.getContents().find((c) => c.doc === doc)?.index
            const cfi = fv.getCFI(index, range)
            return { cfi, pageX, pageY, docHandle: doc }
          }
        }
        return null
      })
    }

    const target = await locateTextRect()
    if (!target) { console.log('FAIL: 找不到可視文字節點'); process.exitCode = 1; return }

    await page.evaluate((cfi) => {
      window.setDecorations([{ id: 'target', cfi, color: 'yellow', isUnderline: false }])
    }, target.cfi)
    await new Promise((r) => setTimeout(r, 200))

    const client = page._client()
    async function tap(x, y, holdMs) {
      await client.send('Input.dispatchTouchEvent', {
        type: 'touchStart', touchPoints: [{ x, y, id: 1, radiusX: 5, radiusY: 5, force: 0.5 }],
      })
      await new Promise((r) => setTimeout(r, holdMs))
      await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
      await new Promise((r) => setTimeout(r, 300))
    }

    // 情境 A：短按（80ms）直接點在畫線上 → 應被攔截，不觸發 onAnnotationActivated。
    await page.evaluate(() => { window.__harnessEvents = [] })
    await tap(target.pageX, target.pageY, 80)
    const shortTapEvents = await page.evaluate(() => window.__harnessEvents)
    const shortTapHit = shortTapEvents.find((e) => e.name === 'onAnnotationActivated')
    console.log(`情境 A（短按 80ms 直接點在畫線上）：${shortTapHit ? `FAIL，仍觸發 id=${shortTapHit.args[0]}` : 'PASS，已攔截'}`)

    // 情境 B：長按（900ms，原地不動）直接點在畫線上 → 應正常觸發 onAnnotationActivated。
    await page.evaluate(() => { window.__harnessEvents = [] })
    await tap(target.pageX, target.pageY, 900)
    const longPressEvents = await page.evaluate(() => window.__harnessEvents)
    const longPressHit = longPressEvents.find((e) => e.name === 'onAnnotationActivated')
    console.log(`情境 B（長按 900ms 直接點在畫線上）：${longPressHit ? `PASS，正確觸發 id=${longPressHit.args[0]}` : 'FAIL/INCONCLUSIVE，click 未觸發或未命中 show-annotation'}`)

    // 情境 C：短按（80ms）點在超連結上 → 連結點擊仍應正常運作（不被攔截）。
    // 由於 fixture 不保證含有真實超連結，動態插入一個 <a> 到目前可視 doc
    // 內、與畫線相同座標附近，純粹測試「target.closest('a[href]')
    // 排除邏輯」是否生效，不依賴真實書本內容。
    const linkSetup = await page.evaluate(() => {
      const fv = document.querySelector('foliate-view')
      const container = fv?.renderer?.shadowRoot?.getElementById('container')
      const iframes = Array.from(container?.querySelectorAll('iframe') ?? [])
      for (const iframe of iframes) {
        const doc = iframe.contentDocument
        if (!doc?.body) continue
        const a = doc.createElement('a')
        a.href = '#test-link'
        a.textContent = 'LINK'
        a.style.position = 'absolute'
        a.style.left = '40px'
        a.style.top = '40px'
        a.style.zIndex = '9999'
        doc.body.appendChild(a)
        const rect = a.getBoundingClientRect()
        const iframeRect = iframe.getBoundingClientRect()
        window.__linkClicked = false
        a.addEventListener('click', (e) => { e.preventDefault(); window.__linkClicked = true })
        return {
          pageX: iframeRect.left + rect.left + rect.width / 2,
          pageY: iframeRect.top + rect.top + rect.height / 2,
        }
      }
      return null
    })
    if (linkSetup) {
      await tap(linkSetup.pageX, linkSetup.pageY, 80)
      const linkClicked = await page.evaluate(() => window.__linkClicked === true)
      console.log(`情境 C（短按 80ms 點在超連結上）：${linkClicked ? 'PASS，連結點擊仍正常運作' : 'FAIL，連結點擊被誤攔截'}`)
    } else {
      console.log('情境 C：SKIP，無法插入測試用連結元素')
    }

    console.log(`\npageErrors: ${pageErrors.length}`)
    pageErrors.forEach((e) => console.log('  ' + e))
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [ ] **Step 4：執行驗證腳本**

Run: `cd tmp/epic-25-issue-4-harness && node fix-verify.mjs`

Expected（本計畫規劃階段已實際執行過，以下為真實輸出，非預測）：
```
情境 A（短按 80ms 直接點在畫線上）：PASS，已攔截
情境 B（長按 900ms 直接點在畫線上）：PASS，正確觸發 id=target
情境 C（短按 80ms 點在超連結上）：PASS，連結點擊仍正常運作

pageErrors: 0
```

三項情境皆 PASS。情境 B 的結果同時解答了規劃階段原本不確定的問題——headless Chromium 下，原地不動的長按（900ms）放開後確實仍會合成 `click` 事件並正確觸發 `show-annotation`（見 Global Constraints「已知殘留限制」，真機行為仍待驗證）。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "fix(epic-25): Issue 4——按壓時長判斷換頁與畫線點擊意圖，攔截快速點擊誤觸發刪除確認"
```

---

### Task 2：清除 `[DEBUG-e25i4]` 診斷插樁

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:333-341`（`window.nextPage`／`window.previousPage` 移除呼叫時間戳 log）、`:598-602`（`show-annotation` handler 移除誤觸發偵測 log）
- Modify: `app/lib/screens/reader_screen.dart:38`（移除已無用的 `reader_console_log.dart` import）、`:2390-2417`（`_handleZoneAction()` 移除兩處 `ReaderConsoleLog.add(...)` 呼叫）

**Interfaces:**
- Consumes：無新介面依賴，純刪除既有暫時性程式碼。
- Produces：無。

- [ ] **Step 1：`main.js` 移除 `window.nextPage`／`window.previousPage` 的診斷 log**

修改 `app/android/app/src/main/assets/foliate/main.js:333-341`，從：

```javascript
window.nextPage = function () {
  console.log(`[DEBUG-e25i4] window.nextPage() called t=${Date.now()}`)
  view.next()
}

window.previousPage = function () {
  console.log(`[DEBUG-e25i4] window.previousPage() called t=${Date.now()}`)
  view.prev()
}
```

改為：

```javascript
window.nextPage = function () {
  view.next()
}

window.previousPage = function () {
  view.prev()
}
```

- [ ] **Step 2：`main.js` 移除 `show-annotation` handler 的診斷 log**

修改 `app/android/app/src/main/assets/foliate/main.js:598-602`，從：

```javascript
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      console.log(`[DEBUG-e25i4] show-annotation t=${Date.now()} value=${e.detail.value} id=${id ?? 'null'}`)
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
    })
```

改為：

```javascript
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
    })
```

- [ ] **Step 3：語法檢查**

Run: `node --check app/android/app/src/main/assets/foliate/main.js`
Expected: 無輸出、exit code 0。

- [ ] **Step 4：`reader_screen.dart` 移除 `_handleZoneAction()` 的診斷 log**

修改 `app/lib/screens/reader_screen.dart`，`_handleZoneAction()` 的 `ZoneAction.previousPage`／`ZoneAction.nextPage` 分支，從：

```dart
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 25 Issue 4 暫時性除錯插樁 [DEBUG-e25i4]：量測 nav-zone
          // 熱區收到觸控到呼叫 FoliateEpubReaderView.previousPage()（進而
          // evaluateJavascript('window.previousPage()')）之間的真機時序，
          // 供與 main.js 同標籤插樁交叉比對。確認根因、產出修復計劃後需
          // 整段移除。
          ReaderConsoleLog.add(
            '[DEBUG-e25i4] _handleZoneAction(previousPage) t=${DateTime.now().millisecondsSinceEpoch}',
          );
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 25 Issue 4 暫時性除錯插樁 [DEBUG-e25i4]：見上方
          // previousPage 分支註解，同理。
          ReaderConsoleLog.add(
            '[DEBUG-e25i4] _handleZoneAction(nextPage) t=${DateTime.now().millisecondsSinceEpoch}',
          );
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
```

改為：

```dart
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
```

- [ ] **Step 5：移除已無用的 import**

修改 `app/lib/screens/reader_screen.dart:38`，移除（`ReaderConsoleLog` 在本檔案已無其他呼叫點）：

```dart
import '../reader/reader_console_log.dart';
```

- [ ] **Step 6：確認插樁清除乾淨**

Run: `grep -rn "DEBUG-e25i4" app/lib app/android/app/src/main/assets/foliate`
Expected: 無任何輸出（exit code 1）。

- [ ] **Step 7：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（本計畫規劃階段已實際執行確認，含確認移除 import 後未產生 unused-import 或其他告警）。

- [ ] **Step 8：執行既有測試套件，確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過（本計畫規劃階段已實際執行確認，147 項全數通過）。

Run: `cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: 全數通過（本計畫規劃階段已實際執行確認，64 項全數通過，含既有 3×3 導航熱區測試確認未回歸）。

- [ ] **Step 9：重跑 Task 1 的 headless 修法驗證，確認清除插樁後修法仍正常運作**

Run: `cd tmp/epic-25-issue-4-harness && node fix-verify.mjs`
Expected: 三項情境皆 PASS（與 Task 1 Step 4 相同輸出，本計畫規劃階段已實際執行確認）。

- [ ] **Step 10：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/lib/screens/reader_screen.dart
git commit -m "chore(epic-25): Issue 4 清除 [DEBUG-e25i4] 診斷插樁"
```

---

### Task 3：更新 `issues.md`，記錄根因、修法與已知殘留限制

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 4 區塊）

**Interfaces:**
- Consumes：Task 1／Task 2 的實作結果、真機資料分析（`tmp/epic-25/log-issue4/`）。
- Produces：無程式介面——文件更新。

- [ ] **Step 1：更新 `Status` 行**

修改 `docs/epics/epic-25-annotation-interaction-qa/issues.md` Issue 4 區塊開頭的 `Status` 行，改為：

```markdown
**Status:** ✅ 已修復。真機資料（`tmp/epic-25/log-issue4/`，六份 log：`壓到-1/2/3.txt`／`沒壓到.txt`／`明顯不重疊-1/2.txt`）證實根因與原始假說不同——`click` 事件命中畫線的時序有時早於、有時晚於 `window.nextPage()` 實際執行，兩種順序都會誤觸發，純時序競速修法無法涵蓋；本質是「換頁點擊」與「畫線點擊」共用同一組觸控手勢、同一螢幕座標的產品層級語意衝突，不是單純的競速 bug。採用人類確認的產品方向（按壓時長判斷意圖，快速點擊優先視為換頁）修復，`main.js` 新增 capture 階段 `touchstart`/`click` 監聽器，700ms 內攔截 click 傳給畫線點擊監聽器的機會（明確排除超連結點擊，避免連帶回歸）。headless 驗證三種情境（短按攔截／長按放行／超連結不受影響）皆 PASS。**已知殘留限制**：真機上「長按原地放開是否仍合成 click 事件」未經驗證（headless 已確認會，真機 WebView 行為可能不同），需真機驗證「長按查看/編輯既有畫線」這條路徑是否如預期運作。
```

- [ ] **Step 2：在「根因假說」段落後新增「真機資料分析與修訂根因」小節**

在 `issues.md` Issue 4 區塊的「**根因假說**」段落（含 vendored `view.js:438-445` 程式碼片段）之後、「**規劃階段查證**」段落之前，新增：

```markdown
**真機資料分析與修訂根因（`tmp/epic-25/log-issue4/`，六份 log，`plan-issue-4-fix.md`）：**

真機插樁資料（`plan-issue-4-realdevice-diagnostics.md` 產出）交叉比對後，發現原始假說（`click` 恆常晚於換頁動作、命中新頁內容）**不成立**：

- `壓到-1.txt:15-19`：`show-annotation`（t=636932）發生在 `window.nextPage() called`（t=636933）**之前**——換頁動作根本還沒執行，click 已命中畫面上現有的畫線。
- `壓到-1.txt:56-64`：`window.nextPage() called`（t=653673）在 `click`（t=653678）**之前**，中間差 5ms——這次換頁動作先執行。

兩種相反的時序，皆誤觸發**同一筆畫線**（`highlight:10d0a3b5-5d4a-44ec-b1d5-1b4e9eaf5708`）。這代表問題不是「click 打中換頁後的新內容」這種時序競速，而是：**點擊座標剛好落在畫面上（換頁前或換頁後皆可能）某個位置的畫線，vendored `view.js` 的原生 `click` 監聽器就會 hitTest 命中、跳出對話框**，與換頁動作的執行時機無關。

`沒壓到.txt`（人類原始標記「重疊但沒跳出對話框」）交叉核對後，同樣有 2 次 `show-annotation` 正確觸發（`highlight:f31a9173-...`／`highlight:c34dcde0-...`）——人類確認這份 log 錄製時「點擊很快，可能沒注意到」，故此標記不可靠，予以排除，改採信 log 本身（視為真實誤觸發，與「壓到」系列一致）。`明顯不重疊-1.txt`／`明顯不重疊-2.txt` 則完全零 `show-annotation` 觸發，與「明顯不重疊、不會跳出對話框」的標記完全吻合，佐證插樁資料本身可信。

綜合五次真實誤觸發（`壓到-1`×2、`壓到-2`×2、`沒壓到`×2，扣除重複計算後共 5 次不同時間點的觸發）與零假陽性（`明顯不重疊`×2）的資料，確認根因是**產品層級的手勢語意衝突**：3×3 換頁熱區點擊與「點擊既有畫線查看/編輯」共用同一種手勢（快速點擊）、可能落在同一螢幕座標，技術上沒有任何訊號能區分使用者意圖。

**人類確認的產品方向**：以按壓時長作為判斷依據——「通常要處理畫線手指都會壓比較久，如果是快速點擊就是要換頁」。快速點擊（≤700ms，比照既有 `_NavZoneTapDetector._tapMaxDurationMs`）優先視為換頁意圖，攔截畫線點擊對話框；按壓夠久則視為使用者確實想操作畫線，正常顯示對話框。修法內容見 `plan-issue-4-fix.md`。
```

- [ ] **Step 3：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 4 記錄真機資料分析、修訂根因與修法"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 4「下一步」步驟 2（依實測時序定案修法方向）、步驟 3（確認修法不影響「正常點擊畫線開啟編輯/刪除選單」既有核心功能）皆由 Task 1 覆蓋——headless 情境 B 直接驗證「長按仍能正常開啟編輯/刪除選單」未回歸；情境 C 額外驗證修法不影響超連結點擊（規劃階段原始碼查證發現的真實風險，非計畫要求但主動涵蓋）。`plan-issue-4-realdevice-diagnostics.md` 的插樁移除承諾由 Task 2 覆蓋。
- **No Placeholders 掃描**：三個 Task 的程式碼、headless 驗證腳本、真實執行輸出（Task 1 Step 4、Task 2 Step 9）皆為規劃階段實際套用到程式碼並執行驗證過的內容，非理論推算；`issues.md` 新增內容逐字取自本次真機 log 分析的實際數字（時間戳、highlight id）。
- **型別/介面一致性**：修法只新增 `main.js` 內部變數（`ANNOTATION_CLICK_TAP_MAX_MS`／`annotationClickTouchStartTime`），未變更任何既有函式簽章或跨檔案介面。
- **既有測試不回歸的具體論證**：修法只在既有 `view.addEventListener('load', ...)` hook 內新增獨立的 capture 階段監聽器，不修改 `window.nextPage`/`previousPage`（Task 2 移除的只是診斷 log，函式本體 `view.next()`/`view.prev()` 呼叫不變）、不修改 `show-annotation` handler 的核心邏輯（同樣只移除診斷 log）、不修改 `_handleZoneAction()` 的既有分派邏輯（只移除診斷 log）。Task 2 Step 8 仍安排執行完整既有測試套件作為實測佐證。
- **範圍誠實聲明**：本計畫刻意不處理「真機上長按原地放開是否仍合成 click 事件」這個未驗證問題（Global Constraints 已明確記錄為已知殘留限制，需要真機驗證，若證實有問題需另立 Issue 設計替代互動方式）——headless 驗證只能證明「假設 click 事件真的觸發時，本修法的攔截/放行邏輯是正確的」，不能證明「真機上長按放開一定會觸發 click」這個更底層的瀏覽器行為假設，兩者是不同層次的問題，不應混為一談。
- **獨立審查回應**（`tmp/epic-25/plan-issue-4-fix-review-report.md`，`/superpowers:receiving-code-review`）：Minor #1（`touchcancel` 重置狀態）查證後接受，已納入 Task 1 Step 1 程式碼並重新跑過三項 headless 情境確認無回歸。Important #1（超連結排除選擇器擴充到 `role="link"`／`button`／`input`／`select`／`textarea`）查證後駁回——`grep` 逐一核對整個 vendored＋整合層確認只有 3 個 `doc` 層級 `click` 監聽器，沒有任何監聽器處理這些元素，擴充範圍不會保護現存功能、只會讓這些元素與畫線重疊時重新出現本次要修的誤觸發；SVG `xlink:href` 連結子點技術上屬實，但 `#handleLinks` 自己也不處理這類連結，不存在功能利害關係，故不處理，理由已記錄於 Global Constraints。Minor #2（真機長按驗證提醒）審查報告本身建議「維持既有記錄」，未要求變更。
