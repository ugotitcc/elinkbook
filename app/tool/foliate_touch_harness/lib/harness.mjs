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

  const client = await page.createCDPSession()
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
