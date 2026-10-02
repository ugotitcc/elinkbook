// /diagnose（2026-10-02，蘇東坡新傳直排內文下方出現大片留白，真機 AiPaper Reader C）：
// main.js buildOverrideCss() 輸出 `p { margin-bottom: Xem !important }`。margin-bottom
// 是「物理」方向屬性——橫排時它是段落間距沒錯，但直排（vertical-rl）下 bottom 位於
// 「行的結尾端」，反而把每一行的可用行長縮短 X em（段距設到約 3em 就少 3 個字），段落
// 間距（直排應為 margin-left）卻完全沒有套用。
//
// 本情境以記憶體組出的最小 EPUB（一個很長的段落、無書本 CSS）重現：直排、上下邊距 0、
// 段距 2.9em，斷言「可視頁內最長的一行」必須用滿 WebView 高度（只容許少於一個字的捨去）。
import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'

function buildFixtureEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000098</dc:identifier>
    <dc:title>直排段距診斷用EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="chapter1"/></spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">第一章</a></li></ol></nav></body>
</html>
`
  const long = '蘇軾堅決反對新法針對時事特別攻擊聚斂和法家兩端'.repeat(40)
  const chapter1Xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title></head>
<body>
  <p>${long}</p>
  <p>${long}</p>
</body>
</html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/chapter1.xhtml', data: Buffer.from(chapter1Xhtml) },
  ])
}

// 可視頁內所有文字 rect 的最低 y（相對 WebView 頂端）與字級
async function readTextExtent(page) {
  return page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    const host = view.renderer.getBoundingClientRect()
    const container = view.renderer.shadowRoot.getElementById('container')
    for (const iframe of container.querySelectorAll('iframe')) {
      const doc = iframe.contentDocument
      if (!doc?.body) continue
      const ir = iframe.getBoundingClientRect()
      if (ir.bottom < 0 || ir.top > host.height) continue
      let maxY = -1
      const tw = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
      while (tw.nextNode()) {
        if (!tw.currentNode.textContent.trim()) continue
        const rg = doc.createRange(); rg.selectNodeContents(tw.currentNode)
        for (const rc of rg.getClientRects()) {
          const t = rc.top + ir.top, b = rc.bottom + ir.top
          if (rc.height < 2 || t >= host.height || b <= 0) continue
          maxY = Math.max(maxY, Math.min(b, host.height))
        }
      }
      const p = doc.querySelector('p')
      const cs = doc.defaultView.getComputedStyle(p)
      return { hostHeight: host.height, maxY, fontSize: parseFloat(cs.fontSize), marginBottom: cs.marginBottom, marginLeft: cs.marginLeft }
    }
    return null
  })
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureBuffer: buildFixtureEpub(),
    writingMode: 'vertical',
    viewport: { width: 376, height: 715 },
    prefs: { marginTop: 0, marginBottom: 0, paragraphSpacing: 2.9, columnMode: 'single' },
  })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))
    const m = await readTextExtent(page)
    report('讀得到可視頁內文字範圍', m !== null)
    if (!m) return

    // 一行最長可容許的捨去量：不到一個字（字級）
    const shortfall = m.hostHeight - m.maxY
    report(
      '直排下段距不得縮短行長：最長一行應用滿頁面高度（差距 < 1 字）',
      shortfall < m.fontSize,
      `hostHeight=${m.hostHeight} 最低文字 y=${Math.round(m.maxY)} 差距=${Math.round(shortfall)}px 字級=${m.fontSize}px`,
    )
    report(
      '直排下 p 的 margin-bottom（行結尾端）必須為 0px',
      m.marginBottom === '0px',
      `margin-bottom=${m.marginBottom} margin-left=${m.marginLeft}`,
    )
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
