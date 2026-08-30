// /diagnose（2026-08-24，真機回報 3 項問題，見
// docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
// 「Issue 10」）：Phase 1 可執行、可判讀的回歸迴圈。比照
// epic-25-annotation-interaction-qa/epic-18-issue-47-harness 既有手法——
// 用 CDP Input.dispatchTouchEvent 走真正的瀏覽器 input pipeline，載入
// 本 repo 真實的 main.js/paginator.js/view.js/epub.js，差分比較
// fixtures/main.base.js（Issue 9 之前）與 fixtures/main.fixed.js
// （Issue 9 之後，含 no-swipe）兩個版本在同一組觸控序列下的行為差異。
//
// 【已查證的環境限制，非本次獨有的失敗，寫下來避免下一個人重踩】
// 本腳本原本還有另外 3 個情境：短按/長按是否觸發原生 click、點擊已建立
// 的劃線是否觸發 onAnnotationActivated。已用三項獨立證據確認 headless
// Chromium 透過 CDP（不論是本腳本手寫的 Input.dispatchTouchEvent，還是
// Puppeteer 官方的 page.touchscreen.tap()）**不會**從 touchstart/touchend
// 序列合成原生 click 事件（改用 page.mouse.click() 驗證同一個監聽器本身
// 正常運作，排除是監聽器寫錯的可能）；也**不會**觸發原生長按選字（按住
// 700ms 不移動，document.getSelection().isCollapsed 全程維持 true）。這是
// headless Chromium 對 CDP 合成觸控輸入的既有限制，不是本 App 的行為，
// 這兩類情境已移除，不留在本腳本內避免误導——只保留下方情境 1（選取
// 「已經存在」之後，touchmove/touchend 是否會讓它消失），這是唯一能在
// 本環境穩定量測、且訊號可信的部分。Issue 2／Issue 3 的根因判斷改回退
// 為程式碼交叉核對＋真機圈選 console log 驗證，見 bugfix-repro.md。

import puppeteer from 'puppeteer'
import { readFile, writeFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const FOLIATE_DIR = path.resolve(
  __dirname,
  '../../../../../app/android/app/src/main/assets/foliate',
)
const FIXTURE_EPUB = path.resolve(
  __dirname,
  '../../../../../app/test/fixtures/sample_horizontal.epub',
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

async function runVariant(variantName, mainJsOverridePath, fixtureBuf) {
  const relFiles = await listFilesRecursive(FOLIATE_DIR)
  const fileMap = new Map()
  for (const rel of relFiles) {
    fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)))
  }
  fileMap.set('main.js', await readFile(mainJsOverridePath))

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
    page.on('pageerror', (err) => console.error(`[${variantName}][pageerror]`, err))

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
    await page.waitForFunction(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      const container = renderer?.shadowRoot?.getElementById('container')
      for (const iframe of container?.querySelectorAll('iframe') ?? []) {
        const text = iframe.contentDocument?.body?.textContent?.trim() ?? ''
        if (text.length > 40) return true
      }
      return false
    }, { timeout: 10000 })

    function selState() {
      return page.evaluate(() => {
        const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
        const doc = container?.querySelector('iframe')?.contentDocument
        const sel = doc.getSelection()
        return { rangeCount: sel.rangeCount, collapsed: sel.isCollapsed, text: sel.toString() }
      })
    }

    const point = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const doc = iframe?.contentDocument
      const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
      let node = null
      while (walker.nextNode()) {
        if ((walker.currentNode.nodeValue || '').trim().length > 20) { node = walker.currentNode; break }
      }
      const range = doc.createRange()
      range.setStart(node, 0)
      range.setEnd(node, 8)
      const rect = range.getClientRects()[0]
      const iframeRect = iframe.getBoundingClientRect()
      return {
        x: iframeRect.left + rect.left + rect.width / 2,
        y: iframeRect.top + rect.top + rect.height / 2,
      }
    })

    // 情境 1：用 execCommand 建立一段選取（模擬選字已完成），接著模擬
    // 使用者放開前常見的「微調控點」小幅拖曳＋放開，觀察選取是否在
    // touchend 之後仍然存在（對應使用者回報症狀 1：滑動選完之後選取
    // 常常整個不見——只涵蓋「選取已存在後的維持」，不涵蓋「長按建立選取」
    // 這一段，理由見檔案開頭「已查證的環境限制」）。
    await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const doc = container?.querySelector('iframe')?.contentDocument
      const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
      let node = null
      while (walker.nextNode()) {
        if ((walker.currentNode.nodeValue || '').trim().length > 20) { node = walker.currentNode; break }
      }
      const sel = doc.getSelection()
      sel.removeAllRanges()
      const range = doc.createRange()
      range.setStart(node, 0)
      range.setEnd(node, 8)
      sel.addRange(range)
    })
    const selectionBeforeDrag = await selState()

    const client = page._client()
    const touchId = 1
    let x = point.x
    let y = point.y
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x, y, id: touchId, radiusX: 5, radiusY: 5, force: 0.5 }],
    })
    for (const [dx, dy] of [[3, 1], [4, 0], [3, -1]]) {
      x += dx
      y += dy
      await client.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [{ x, y, id: touchId, radiusX: 5, radiusY: 5, force: 0.5 }],
      })
      await new Promise((r) => setTimeout(r, 50))
    }
    await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    await new Promise((r) => setTimeout(r, 200))
    const selectionAfterDrag = await selState()

    return {
      variantName,
      scenario1_selectionBeforeDrag: selectionBeforeDrag,
      scenario1_selectionAfterSmallDragRelease: selectionAfterDrag,
    }
  } finally {
    await browser.close()
  }
}

async function main() {
  const fixtureBuf = await readFile(FIXTURE_EPUB)
  const baseResult = await runVariant(
    'BASE(pre-Issue9,no no-swipe)',
    path.join(__dirname, 'fixtures/main.base.js'),
    fixtureBuf,
  )
  const fixedResult = await runVariant(
    'FIXED(post-Issue9,no-swipe)',
    path.join(__dirname, 'fixtures/main.fixed.js'),
    fixtureBuf,
  )
  const result = { baseResult, fixedResult }
  console.log(JSON.stringify(result, null, 2))
  await writeFile(path.join(__dirname, 'result.json'), JSON.stringify(result, null, 2))
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
