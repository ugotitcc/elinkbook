# Epic 18 Issue 45 — EPUB 直排／橫排切換後翻頁跳多頁：診斷用重現迴圈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `issues.md` Issue 45 目前狀態是 `needs-triage`，明載「根因為靜態程式碼推論，下一步：建立 headless Chromium 或 widget test 重現迴圈，量測『切換直排/橫排』前後 `view.next()` 實際位移的欄位數是否符合預期的 1 欄，確認後才可轉 `ready-for-agent`」——本計畫的交付物**不是程式碼修復**，而是這個量測用重現迴圈本身，加上依量測結果產出的診斷報告與 `issues.md` 狀態更新。真正的程式碼修復留待量測結果出爐後的另一份 `plan-issue-45.md`（若本計畫確認重現）覆寫或新工單接手。

**Architecture:** 一支獨立、不進版控的 Node.js + Puppeteer（headless Chromium）診斷腳本，透過 Puppeteer 的 request interception 直接伺服真實的 vendored 資源目錄（`app/android/app/src/main/assets/foliate/`）與一份既有測試 fixture EPUB，在無 Flutter/Android 環境下完整驅動真正的 `main.js`／`paginator.js`／`view.js`（比照生產環境 `WebViewAssetLoader` 的虛擬 origin 機制，見 Issue 8 Spike 驗證過的等效手法），透過與正式產品完全相同的橋接契約（`window.flutter_inappwebview.callHandler(...)`）攔截 `onLocatorChanged`／`onPageRendered` 事件，量測「連續呼叫 `window.nextPage()`」在切換排版方向前後，每次呼叫造成的 `fraction`（全書進度比例）位移量是否有異常放大。

**Tech Stack:** Node.js（已安裝 v24）、Puppeteer（headless Chromium，本計畫透過 `npm install` 安裝於 `tmp/` 內、不進版控）。不涉及任何 Dart/Flutter 程式碼異動。

## Global Constraints

- **不可修改任何 vendored 檔案**：`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`／`progress.js`／`text-walker.js`／`construct-style-sheets-polyfill.js`／`vendor/zip.js` 全部原樣，只能透過這些檔案已公開的 `window.applyPreferences`／`window.nextPage`／`window.previousPage`／`window.flutter_inappwebview.callHandler` 既有介面驅動與觀察（比照 ADR 0011「不修改 vendored 檔案」的既有慣例）。
- **不可修改 `main.js`／`index.html`**：這兩份是正式產品程式碼，本計畫純粹是外部觀察者，所有需要的攔截/量測邏輯都在獨立的 harness 腳本內完成（透過 Puppeteer request interception 與 `page.evaluateOnNewDocument()` 於文件執行最開頭注入橋接 stub），不落地修改這兩份檔案。
- **harness 腳本與其產物一律放在 `tmp/epic-18-issue-45-harness/`**：`tmp/` 已於根目錄 `.gitignore`（第 15 行）排除，不進版控；Task 1 完全不含 git commit 步驟（比照 Issue 8 Spike「過程中產生的 throwaway harness 程式碼與素材……不進版控」的既有慣例）。
- **本計畫不修改任何 Dart/Flutter 程式碼、不新增/修改 `flutter test`、不影響 `flutter analyze` 基準**——這是純 JS 診斷任務，比照 Issue 34/38 既有先例「main.js 為純 JS vendor 檔案，本專案未安裝任何 JS 測試框架……無自動化測試 seam 可用，驗證改以 headless browser 最小重現案例取代」的既有記錄慣例。
- **本計畫的「測試」即 harness 腳本本身的量測輸出**（`result.json` 的 `reproduced` 欄位與各項 `delta` 數值），不是傳統紅-綠 TDD 循環——這與本計畫的診斷性質一致，比照 Issue 34 headless Chromium 最小重現案例的既有作法。
- **量測指標選用 `fraction`（全書進度比例）而非「欄位數」**：`issues.md` 原文要求量測「欄位數」，但 `this.#vertical`／欄位數等內部狀態是 Paginator 的私有欄位（`#` 開頭），JS 私有欄位語法上無法從外部（含 `page.evaluate()` 注入的腳本）存取。改用 `onLocatorChanged` 橋接事件既有公開回傳的 `fraction`（`progress.js` `SectionProgress.getProgress()` 輸出，`main.js:497-513` 已透傳為 `onLocatorChanged` 第 2 個參數）作為等效可觀察量——連續 `nextPage()` 呼叫若每次位移的書本進度比例基本一致，代表「每次翻頁移動一個欄位」；若切換方向後第一次 `nextPage()` 的 `fraction` 位移明顯放大（數倍於切換前的平均值），即是「一次跳好幾頁」症狀的量化證據，效果等同於「欄位數」量測目標，但走的是私有欄位語法允許的公開介面路徑。
- **已完成的原始碼追蹤（本計畫撰寫時的靜態分析，供 harness 設計與後續診斷報告參考，非量測結論）**：追蹤 `paginator.js` 原始碼確認 `this.#vertical`（Paginator 內部欄位，決定分欄/捲動軸方向）只在兩個路徑更新：(a) `View.load()` 的 iframe `load` 事件處理常式（`paginator.js:618-695`，每個 section **第一次載入**時呼叫 `getDirection(doc)`〔`paginator.js:449-479`，讀取該 iframe 文件目前的 computed `writing-mode`〕並透過 `beforeRender?.({vertical, rtl})` 回呼寫回 Paginator）；(b) `Paginator.render()`（`paginator.js:1903-1918`）呼叫 `#beforeRender({vertical: this.#vertical, ...})`——**這裡傳入的是 `this.#vertical` 自己目前的值**，屬自我參照、並非重新從 DOM 推導。而 `main.js` 切換 `writingMode` 偏好的實際手段是 `Paginator.setStyles()`（`paginator.js:3445-3466`）注入新的 `writing-mode: vertical-rl !important` 覆蓋 CSS 文字——**`setStyles()` 只更新已載入 iframe 內 `<style>` 元素的 `textContent`，完全不呼叫 `getDirection()` 或 `#beforeRender()`**，代表對「書本已經開啟、只是切換方向」這個情境，`this.#vertical` 沒有任何路徑會被重新推導；而緊接著 `main.js` 呼叫的 `setAttribute('max-column-count', ...)` 等屬性變更會觸發 `attributeChangedCallback()`（`paginator.js:1545-1573`）呼叫 `this.render()`，但這個 `render()` 使用的仍是（a）(b) 兩條路徑之外、從未真正更新過的**舊值** `this.#vertical`。這與 `issues.md` 原本「信心不足」的假設方向一致，且已定位到具體、可驗證的分歧點（`setStyles()` 與 `render()`/`#beforeRender()` 之間缺乏重新推導方向的呼叫路徑），但仍需 harness 實際量測確認「這個內部狀態分歧確實會表現為外部可觀察的翻頁位移異常」，而非僅止於靜態推論——這正是本計畫存在的理由。

## 審查修正（Round 2，見 `tmp/epic-18/review-plan-issue-45-round2.md`）

Task 1 執行完成後的獨立審查發現：`repro.mjs` 的 `waitForSettle()` 原本要求「`relocate` 次數增加」與「`stabilized` 次數增加」同時成立才算完成一次量測；連續重跑兩次，逾時（`null`）出現的索引位置每次不同，證實這是量測機制本身的非決定性瑕疵（`'stabilized'` 事件只在 `paginator.js` 觸發 `render()`/`#fill()` 時才 dispatch，`nextPage()` 若走不需要重建 view 的輕量捲動路徑則可能完全不觸發，導致雙條件 AND 卡死到逾時），**不是**原本假設的「書本翻到結尾」。已修正為 `waitForRelocateSettle()`：只依賴 `relocate`（量測目標本身的直接來源），等到新的 `relocate` 之後再等待連續 300ms 內次數不再變動（debounce）才視為穩定，不再要求 `'stabilized'` 同時發生；`switchWritingMode()` 因為 `applyPreferences()` 的 `setAttribute()` 呼叫必定同步觸發 `render()`，`'stabilized'` 訊號在那個呼叫點仍然可靠，維持不變。另把「切換後第一次量測」的判讀邏輯從硬取索引 `[0]` 改為「三筆量測中第一筆非 `null` 的值」（實際採用的索引一併記錄進 `result.json` 的 `firstPostSwitchDeltaIndex`／`firstPostSwitchToHorizontalDeltaIndex`）。修正後連續重跑 3 次，`result.json` 逐位元組完全一致、無任何 `null`，`reproduced`／`reproducedReverse` 皆確認為 `false`（詳見 `reviews/bugfix-repro-issue-45.md`）。

---

### Task 1: 建立 Puppeteer 診斷 harness，量測切換排版方向前後的 `nextPage()` 位移量

**Files:**
- Create: `tmp/epic-18-issue-45-harness/package.json`（`npm init`／`npm install` 產生，記錄 `puppeteer` 相依版本）
- Create: `tmp/epic-18-issue-45-harness/repro.mjs`
- Create: `tmp/epic-18-issue-45-harness/result.json`（腳本執行後自動產生，非手動撰寫）

**Interfaces:**
- Consumes: 無（獨立診斷腳本，不依賴專案內任何 Dart/Flutter 程式碼）
- Produces: `result.json` 結構 `{ baselineDeltas: (number|null)[3], baselineAvg: number|null, postSwitchDeltas: (number|null)[3], postSwitchToHorizontalDeltas: (number|null)[3], firstPostSwitchDelta: number|null, firstPostSwitchToHorizontalDelta: number|null, reproduced: boolean, reproducedReverse: boolean }`——`null` 代表該次 `nextPage()` 逾時未收到新事件（最可能是書本已翻到結尾，見 Step 2 `stepAndMeasure()` 的逾時處理），不是崩潰；`baselineAvg` 在 `baselineDeltas` 三筆皆為 `null` 時也會是 `null`。Task 2 直接讀取這份檔案的欄位進行判讀，不重新執行 harness。

- [ ] **Step 1: 建立 harness 目錄與 npm 環境**

```bash
mkdir -p tmp/epic-18-issue-45-harness
cd tmp/epic-18-issue-45-harness
npm init -y
npm install puppeteer
cd ../..
```

Expected: `tmp/epic-18-issue-45-harness/node_modules/puppeteer` 存在，`npm install` 無錯誤結束（`tmp/` 已於 `.gitignore` 排除，這些檔案不會被 git 追蹤）。

- [ ] **Step 2: 撰寫 `repro.mjs`**

```javascript
// tmp/epic-18-issue-45-harness/repro.mjs
//
// Epic 18 Issue 45 診斷用重現迴圈：量測 EPUB 切換直排/橫排前後，
// window.nextPage() 造成的書本進度（fraction）位移量是否異常放大。
// 透過 Puppeteer request interception 直接伺服真實 vendored 資源，
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
// index.html/*.js（見下方 listFilesRecursive 掃到的 11 個檔案，目前
// 全部只有這兩種副檔名，含 vendor/zip.js）；(b) book/current.epub
// （另有專屬分支處理，不查這個表）。EPUB 書本內部資源（xhtml/css/svg/
// 字型等）由 epub.js 透過 URL.createObjectURL() 轉成 blob: URL 在瀏覽器
// 記憶體內解析，從未經過這裡的 request interception（已查證
// epub.js:554/860/922/1082/1279），故不需要也不應該為這些副檔名預先加
// MIME 對應——加了也永遠不會被用到，屬於未經驗證的臆測風險。
const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
}

// 遞迴列出 foliate/ 目錄下所有檔案的相對路徑（含 vendor/ 子目錄）。
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

  // browser 變數宣告在 try 外、close() 放在 finally——puppeteer.launch()
  // 本身失敗時不會進入 try，不需要清理；一旦成功啟動，無論 try 內任何一步
  // 拋出例外（導覽逾時、waitForFunction 逾時等），都保證 browser.close()
  // 會被執行，避免 headless Chromium 殭屍處理程序洩漏（審查意見 Critical #1）。
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
      // 根路徑降級為 index.html（審查意見 Important #2）：本 harness
      // 唯一的 page.goto() 目標一律明確帶完整檔名（見下方 openUrl），
      // 但保守比照正式 WebViewAssetLoader virtual origin 同樣的降級
      // 規則，避免瀏覽器對裸 origin 根路徑發出請求時得到非預期的 404。
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

    page.on('console', (msg) => console.log('[page]', msg.text()))
    page.on('pageerror', (err) => console.error('[pageerror]', err))

    // 在 main.js 執行之前注入橋接 stub，捕捉既有的
    // window.flutter_inappwebview.callHandler(...) 呼叫——重用正式產品
    // 既有的橋接契約（main.js 對應呼叫端未變動一行），不是新增介面。
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
    await page.setViewport({ width: 800, height: 1200 })
    await page.goto(openUrl, { waitUntil: 'load' })

    await page.waitForFunction(
      () => window.__harnessEvents.some((e) => e.name === 'onPageRendered'),
      { timeout: 15000 },
    )

    // Paginator（view.renderer）在每次 render()/#fill() 結束時都會同步
    // dispatch 一個 'stabilized' 事件（已查證 paginator.js:1920（render()
    // 結尾）、2967（#fill() 的 finally）、3081／3211（導覽/preload
    // 穩定後）），代表「內部版面模型已重新計算完成」——這是函式庫自己
    // 公開的穩定訊號，比猜測固定影格數更精確。用它取代原本「等待 N 個
    // requestAnimationFrame」的猜測值，同時解決 next()/prev()
    // 換頁動畫過程可能連續發出多個中間態 relocate 事件，導致取樣到
    // 過渡值而非最終穩定值的問題（審查意見 Important #3/#4）。
    await page.evaluate(() => {
      window.__harnessStabilizedCount = 0
      document
        .querySelector('foliate-view').renderer
        .addEventListener('stabilized', () => { window.__harnessStabilizedCount++ })
    })

    // main.js 的 onLocatorChanged 呼叫簽章：
    // callHandler('onLocatorChanged', locatorJsonStr, fraction, locationCurrent, totalPages)
    const readLastFraction = () =>
      page.evaluate(() => {
        const events = window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged')
        const last = events[events.length - 1]
        return last ? last.args[1] : null
      })

    async function waitForSettle(relocateCountBefore, stabilizedCountBefore, timeout = 5000) {
      await page.waitForFunction(
        (relocateBefore, stabilizedBefore) =>
          window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged').length > relocateBefore
          && window.__harnessStabilizedCount > stabilizedBefore,
        { timeout },
        relocateCountBefore,
        stabilizedCountBefore,
      )
    }

    async function stepAndMeasure(label) {
      const before = await readLastFraction()
      const relocateCountBefore = await page.evaluate(
        () => window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged').length,
      )
      const stabilizedCountBefore = await page.evaluate(() => window.__harnessStabilizedCount)
      await page.evaluate(() => window.nextPage())
      try {
        await waitForSettle(relocateCountBefore, stabilizedCountBefore)
      } catch (err) {
        // 逾時最可能的原因是書本內容不夠長、nextPage() 已到全書結尾，
        // 不再產生新的 relocate/stabilized 事件（審查意見 Minor #1）。
        // 不讓整支腳本崩潰（exit code 2），改記錄為 null，供 Task 2
        // 判讀時排除這類「已到結尾」的樣本，而非誤判為量測異常。
        console.warn(`[${label}] 逾時未收到新事件，可能已翻到全書結尾：${err.message}`)
        return null
      }
      const after = await readLastFraction()
      const delta = after - before
      console.log(`[${label}] fraction ${before.toFixed(5)} -> ${after.toFixed(5)} (delta ${delta.toFixed(5)})`)
      return delta
    }

    async function switchWritingMode(mode) {
      const stabilizedCountBefore = await page.evaluate(() => window.__harnessStabilizedCount)
      await page.evaluate((prefs) => window.applyPreferences(prefs), {
        ...initialPrefs,
        writingMode: mode,
      })
      await page.waitForFunction(
        (before) => window.__harnessStabilizedCount > before,
        { timeout: 5000 },
        stabilizedCountBefore,
      )
    }

    const baselineDeltas = []
    for (let i = 0; i < 3; i++) baselineDeltas.push(await stepAndMeasure(`橫排 next() #${i + 1}`))
    const validBaseline = baselineDeltas.filter((d) => d !== null)
    const baselineAvg = validBaseline.length
      ? validBaseline.reduce((a, b) => a + b, 0) / validBaseline.length
      : null

    await switchWritingMode('vertical')
    const postSwitchDeltas = []
    for (let i = 0; i < 3; i++)
      postSwitchDeltas.push(await stepAndMeasure(`切換直排後 next() #${i + 1}`))

    await switchWritingMode('horizontal')
    const postSwitchToHorizontalDeltas = []
    for (let i = 0; i < 3; i++)
      postSwitchToHorizontalDeltas.push(await stepAndMeasure(`切回橫排後 next() #${i + 1}`))

    const firstPostSwitchDelta = postSwitchDeltas[0]
    const firstPostSwitchToHorizontalDelta = postSwitchToHorizontalDeltas[0]
    const result = {
      baselineDeltas,
      baselineAvg,
      postSwitchDeltas,
      postSwitchToHorizontalDeltas,
      firstPostSwitchDelta,
      firstPostSwitchToHorizontalDelta,
      reproduced: baselineAvg !== null && firstPostSwitchDelta !== null
        && firstPostSwitchDelta > baselineAvg * 2,
      reproducedReverse: baselineAvg !== null && firstPostSwitchToHorizontalDelta !== null
        && firstPostSwitchToHorizontalDelta > baselineAvg * 2,
    }
    console.log(JSON.stringify(result, null, 2))
    await writeFile(path.join(__dirname, 'result.json'), JSON.stringify(result, null, 2))

    // 用 process.exitCode（而非 process.exit()）讓 Node 在事件迴圈自然
    // 清空後才結束——若這裡直接呼叫 process.exit()，會立即終止行程、
    // 跳過下面 finally 區塊裡尚未 await 完成的 browser.close()，等於
    // 繞過了本 Step 一開始就要修的殭屍處理程序問題（審查意見
    // Critical #1 的完整修法，不只是「包一層 try/finally」而已，呼叫
    // process.exit() 的位置本身也必須避開）。
    process.exitCode = result.reproduced || result.reproducedReverse ? 1 : 0
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
cd tmp/epic-18-issue-45-harness
node repro.mjs
echo "exit code: $?"
cd ../..
```

Expected: stdout 依序印出最多 9 行 `[label] fraction X -> Y (delta Z)`（3 筆橫排 baseline + 3 筆切直排後 + 3 筆切回橫排後；若某次 `nextPage()` 逾時未收到新事件會改印一行 `[label] 逾時未收到新事件……` warning，不算失敗，見下方 Step 4），接著印出完整 `result.json` 內容，最後印出 `exit code: 0` 或 `exit code: 1`（兩者皆代表腳本本身執行成功，1 只代表「量測結果顯示重現」，不是失敗；`exit code: 2` 或任何未攔截的例外堆疊才代表 harness 本身有問題，需要修正腳本後重跑，不得直接跳到 Task 2）。

- [ ] **Step 4: 檢查 `result.json` 資料完整性**

```bash
cat tmp/epic-18-issue-45-harness/result.json
```

Expected: `baselineDeltas`／`postSwitchDeltas`／`postSwitchToHorizontalDeltas` 三個陣列理想上皆為 3 個正浮點數（`fraction` 只會隨 `nextPage()` 遞增，非負數、非 `NaN`）；若其中零星幾筆是 `null`（書本翻到結尾提早耗盡內容），視為正常的逾時降級結果，不需重跑。**但若 `baselineDeltas` 三筆「全部」為 `null`（`baselineAvg` 因此也是 `null`）**，代表 fixture 內容長度連 3 次橫排翻頁都撐不住，量測基準本身不成立，需改用 `app/test/fixtures/sample_long_chinese_vertical.epub` 等其他既有 fixture 重跑本 Step（改法：修改 `repro.mjs` 開頭的 `FIXTURE_EPUB` 常數，重新執行 Step 3），不得手動竄改 `result.json` 數值。

---

### Task 2: 判讀量測結果，產出診斷報告並更新 issue tracker

**Files:**
- Create: `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-45.md`
- Modify: `docs/epics/epic-18-reader-device-qa/issues.md`（Issue 45 段落，約第 1161-1169 行）

**Interfaces:**
- Consumes: Task 1 產出的 `tmp/epic-18-issue-45-harness/result.json`
- Produces: 無（本 Task 為文件產出，不影響任何程式碼介面）

- [ ] **Step 1: 讀取 `result.json`，依規則判讀是否重現**

判讀規則（已於 Task 1 harness 內建為 `reproduced`／`reproducedReverse` 布林欄位，這裡是人工複核，不是重新計算）：
- `reproduced === true`：切換為直排後的第一次 `nextPage()` 位移量，超過切換前橫排 baseline 平均值的 2 倍——量化確認「切換方向後翻頁跳過量異常放大」，對應使用者回報症狀。
- `reproducedReverse === true`：切回橫排後同樣觀察到異常放大——代表症狀不限於「橫→直」單一方向，任何一次切換都會觸發，加強根因指向「setStyles() 之後 render() 使用舊值 `this.#vertical`」這個與切換方向本身無關、只與「是否曾經切換過」有關的機制假設。
- 兩者皆為 `false` 且 `baselineAvg !== null`：本次 harness 未能重現使用者回報的症狀，需在報告中如實記錄，不得為了呼應原假設而曲解數據。
- `baselineAvg === null`：量測基準本身未成立（Task 1 Step 4 應已攔下這個情況要求換 fixture 重跑），不屬於「未重現」，若仍出現代表 Task 1 未確實完成 Step 4 的檢查，需回頭補做，不得直接當作「未重現」寫進報告。

- [ ] **Step 2: 撰寫診斷報告 `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-45.md`**

以下述模板為基礎撰寫，`{{ }}` 標記處填入 Task 1 `result.json` 的實際數值（模板本身的敘述文字直接沿用，不是待填佔位符）：

```markdown
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

## 量測數據

- 橫排 baseline（切換前，3 次 `nextPage()`）：`{{ baselineDeltas }}`，平均 `{{ baselineAvg }}`
- 切換為直排後（3 次 `nextPage()`）：`{{ postSwitchDeltas }}`
- 再切回橫排後（3 次 `nextPage()`）：`{{ postSwitchToHorizontalDeltas }}`
- 判讀：`reproduced = {{ reproduced }}`，`reproducedReverse = {{ reproducedReverse }}`

## 結論

`{{ 依 Step 1 判讀結果二選一填入以下其中一段 }}`

**若重現（`reproduced` 或 `reproducedReverse` 任一為 `true`）：**

量測數據確認使用者回報症狀——切換排版方向後，緊接著的第一次 `nextPage()`
位移量明顯超出正常單次翻頁的位移範圍。結合原始碼追蹤（見
`plan-issue-45.md` Global Constraints 段落）：`Paginator.setStyles()`
（`paginator.js:3445-3466`，`main.js` 切換 `writingMode` 時用來注入新
`writing-mode` CSS 覆蓋規則的實際手段）只更新已載入 iframe 內
`<style>` 元素文字內容，不呼叫 `getDirection()` 或 `#beforeRender()`；
Paginator 內部決定分欄/捲動軸方向的私有欄位 `this.#vertical` 只在
section **首次載入**時透過 iframe `load` 事件（`paginator.js:618-695`）
重新推導，此後的 `render()`（`paginator.js:1903-1918`，由
`attributeChangedCallback` 觸發）只會用 `this.#vertical` 自己目前的值
自我參照，形成「CSS 已經視覺翻轉、但 Paginator 內部方向狀態未同步」
的分歧，直到使用者退出重進、強制新的 section load 才會被修正——與
使用者回報「退出重進後恢復正常」完全吻合。

**建議修復方向（未經驗證，留待下一份 `plan-issue-45.md` 實作前確認）**：
`Paginator`／`View`（`view.js`，`foliate-view` custom element，`main.js`
既有呼叫的 `view.next()`/`view.prev()`/`view.applyPreferences()` 所在的
公開介面層）是否有可以強制重新載入目前 section（重新走一次
`View.load()` 的 iframe `load` 事件路徑）的公開方法（例如
`view.goTo()` 重新導覽至目前位置）——`#createView()`
（`paginator.js:1589-1607`）在目標 index 已有現存 view 時會先
`existing.destroy()` 再建立全新 `View`，理論上會重新觸發
`getDirection()`。需要實測確認：(a) 這個公開 API 是否真的存在且行為
如預期；(b) 強制重新載入是否會造成可見的畫面閃爍或捲動位置跳動等
新的副作用，需要與「跳好幾頁」的現有症狀權衡。**不可修改
`paginator.js`／`view.js` 內部私有邏輯，只能透過既有公開 API 驅動**
（ADR 0011）。

**若未重現（`reproduced` 與 `reproducedReverse` 皆為 `false`）：**

本次 harness 未能重現使用者回報的症狀，`fraction` 位移量在切換排版
方向前後無顯著差異。可能原因：(a) fixture EPUB 內容/結構與使用者實際
遭遇問題的書籍差異過大，未觸發相同的分欄/方向邊界條件；(b) 症狀與真機
特定的 WebView 版本/渲染時序有關，headless Chromium 環境無法重現；
(c) 原始碼追蹤的根因假設本身有誤，需要重新排查。建議下一步：改用真機
搭配 `chrome://inspect` 遠端除錯直接觀察 `this.#vertical`（可在
DevTools console 內對 `document.querySelector('foliate-view').renderer`
物件展開檢視，雖為私有欄位但 DevTools 可繞過語法限制直接檢視），或請
使用者提供螢幕錄影搭配操作步驟時間戳記，以取得更精確的重現條件。
```

- [ ] **Step 3: 更新 `issues.md` Issue 45 段落**

依 Step 1 判讀結果，於 `docs/epics/epic-18-reader-device-qa/issues.md` 第 1163 行（`### Issue 45` 標題後的 `**Status:**` 那一行）與其後的根因假設段落，二選一更新：

若重現，改為：

```markdown
**Status:** ready-for-agent（已用 headless Chromium 量測確認重現，見 `reviews/bugfix-repro-issue-45.md`；量測數據：橫排 baseline 平均位移 {{ baselineAvg }}，切換直排後第一次位移 {{ firstPostSwitchDelta }}（{{ firstPostSwitchDelta / baselineAvg 的倍數 }} 倍）。根因與建議修復方向見診斷報告，實作前需先確認 `view.goTo()`（或等效公開 API）重新導覽是否為可行且無明顯副作用的修法）
```

若未重現，改為：

```markdown
**Status:** needs-info（已用 headless Chromium 嘗試重現未成功，見 `reviews/bugfix-repro-issue-45.md`；需要使用者提供真機錄影或更精確的重現步驟才能繼續排查）
```

- [ ] **Step 4: Commit（僅 `issues.md` 與新增的診斷報告，不含 `tmp/` 內容）**

```bash
git add docs/epics/epic-18-reader-device-qa/issues.md
git add docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-45.md
git status
```

Expected: `git status` 只顯示上述兩個檔案為 staged，`tmp/epic-18-issue-45-harness/` 不出現在任何 git 狀態輸出中（已被 `.gitignore` 排除）。確認無誤後由人類決定是否執行 `git commit`（依專案既有規則，commit 動作需經人類明確指示，本計畫本身不代為決定）。
