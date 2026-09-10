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
