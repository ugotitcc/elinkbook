// [DEBUG-bb01] 拋棄式診斷：蘇東坡新傳直排時，內文下方留白（疑似被工具列佔據）
import { readFile } from 'node:fs/promises'
import { launchHarnessPage } from './lib/harness.mjs'

const EPUB = process.env.EPUB_PATH
const buf = await readFile(EPUB)
const { browser, page } = await launchHarnessPage({
  fixtureBuffer: buf,
  writingMode: 'vertical',
  prefs: { fontSize: Number(process.env.FS ?? 1.0), columnMode: process.env.CM ?? 'auto' },
  viewport: (([w, h]) => ({ width: w, height: h }))((process.env.INIT ?? '412x824').split('x').map(Number)),
})

async function measure() {
  return page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    const r = view.renderer
    const host = r.getBoundingClientRect()
    const container = r.shadowRoot.getElementById('container')
    const top = r.shadowRoot.getElementById('top')
    const cs = getComputedStyle(top)
    const out = { host: [host.width, host.height], rows: cs.gridTemplateRows, maxInline: cs.getPropertyValue('--_max-inline-size'), maxH: cs.getPropertyValue('--_max-height') }
    const cr = container.getBoundingClientRect()
    out.container = [cr.top, cr.height]
    for (const iframe of container.querySelectorAll('iframe')) {
      const doc = iframe.contentDocument
      if (!doc?.body) continue
      const ir = iframe.getBoundingClientRect()
      if (ir.right < 0 || ir.left > host.width) continue
      out.iframe = [ir.left, ir.top, ir.width, ir.height]
      // 可視頁內所有文字 rect 的最高/最低 y（相對 host）
      let minY = 1e9, maxY = -1
      const rects = []
      const tw = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
      while (tw.nextNode()) {
        if (!tw.currentNode.textContent.trim()) continue
        const rng = doc.createRange(); rng.selectNodeContents(tw.currentNode)
        for (const rc of rng.getClientRects()) rects.push(rc)
      }
      for (const rc of rects) {
        const t = rc.top + ir.top, b = rc.bottom + ir.top
        if (rc.height < 2 || rc.width < 2) continue
        if (t >= host.height || b <= 0 || rc.left + ir.left > host.width || rc.right + ir.left < 0) continue
        minY = Math.min(minY, Math.max(t, 0)); maxY = Math.max(maxY, Math.min(b, host.height))
      }
      out.textY = [Math.round(minY), Math.round(maxY)]
      const vis = rects.filter((rc) => rc.top + ir.top >= 0 && rc.top + ir.top < host.height && rc.right + ir.left > 0 && rc.left + ir.left < host.width)
      out.nVisibleRects = vis.length
      const de = doc.documentElement, ds = doc.defaultView.getComputedStyle(de)
      out.docStyle = { colW: ds.columnWidth, gap: ds.columnGap, h: ds.height, pt: ds.paddingTop, pb: ds.paddingBottom, sh: de.scrollHeight }
      const needle = window.__needle
      if (needle) {
        const tw2 = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
        while (tw2.nextNode()) {
          const k = tw2.currentNode.textContent.indexOf(needle)
          if (k < 0) continue
          const r2 = doc.createRange(); r2.setStart(tw2.currentNode, k); r2.setEnd(tw2.currentNode, k + 8)
          const b = r2.getBoundingClientRect()
          out.needleRect = [Math.round(b.left), Math.round(b.top), Math.round(b.width), Math.round(b.height)]
          // 該頁（以 column 整頁高度切）內所有文字最高/最低 y
          const stride = parseFloat(ds.height) + parseFloat(ds.columnGap) || 0
          out.stride = stride
          break
        }
      }
      out.scroll = [container.scrollLeft, container.scrollTop]
      const main = doc.querySelector('.main')
      if (main) { const m = getComputedStyle(main); out.mainMargin = m.margin; out.fontSize = m.fontSize }
    }
    return out
  })
}

await page.evaluate((n) => { window.__needle = n }, process.env.NEEDLE ?? '')
page.on('console', (m) => { if (m.text().includes('DEBUG-bb01')) console.log('CONSOLE', m.text().slice(0, 700)) })
const sections = await page.evaluate(() => document.querySelector('foliate-view').book.sections.length)
const idxs = (process.env.IDX ?? '22,150,5').split(',').map(Number)
for (const i of idxs) {
  await page.evaluate((i, needle) => {
    const view = document.querySelector('foliate-view')
    if (!needle) return view.goTo(i)
    // 跳到含指定文字的那一頁
    return view.renderer.goTo({ index: i, anchor: (doc) => {
      const tw = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
      while (tw.nextNode()) {
        const k = tw.currentNode.textContent.indexOf(needle)
        if (k >= 0) { const r = doc.createRange(); r.setStart(tw.currentNode, k); r.setEnd(tw.currentNode, k + needle.length); return r }
      }
      return 0
    } })
  }, i, process.env.NEEDLE ?? '')
  await new Promise((r) => setTimeout(r, 600))
  console.log('[DEBUG-bb01] section', i, '/', sections, JSON.stringify(await measure()))
}
for (let p = 0; p < Number(process.env.PAGES ?? 0); p++) {
  await page.evaluate(() => document.querySelector('foliate-view').next())
  await new Promise((r) => setTimeout(r, 250))
  const m = await measure()
  console.log('[DEBUG-bb01] page+', p + 1, 'top', m.iframe?.[1], 'textY', JSON.stringify(m.textY), 'n', m.nVisibleRects)
}
if (process.env.RESIZE_TO) {
  const [w, h] = process.env.RESIZE_TO.split('x').map(Number)
  await page.setViewport({ width: w, height: h, hasTouch: true })
  await new Promise((r) => setTimeout(r, 1500))
  console.log('[DEBUG-bb01] after resize', process.env.RESIZE_TO, JSON.stringify(await measure()))
}
await browser.close()
