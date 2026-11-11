// /diagnose（2026-11-11，馬斯克寶典字級調到 80 仍與 24 幾乎一樣小）：
// 書本 CSS 以 `:root{--font-size-base:16px} body{font-size:var(--font-size-base)}`
// 把 body 字級釘成絕對 px，而 main.js buildOverrideCss() 只覆蓋
// `html { font-size: N% !important }`——body 自己有宣告，不會繼承 html 字級，
// 滑桿因此對這類書無效。本情境用最小 EPUB 重現該 pattern，
// 斷言 fontSize 由 1.0 調到 3.0 後，段落 computed font-size 要跟著變大。
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
    <dc:title>書本 body 字級診斷用 EPUB</dc:title>
    <dc:language>zh-Hant</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
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
  // 與《馬斯克寶典》style.css 相同的 pattern（原值逐字）。
  const styleCss = `:root { --font-size-base: 16px; --max-width: 720px; }
body { font-size: var(--font-size-base); margin: 0 auto; max-width: var(--max-width); padding: 2rem 1.5rem; }
h3 { font-size: 1.15em; }
p { margin: 0 0 1em; text-indent: 2em; }`
  const chapter1Xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
  <h3>當個有用的人</h3>
  <p>我衡量人生是否成功的標準是：「我能搞定多少有用的事？」每天早上醒來，我都會問自己：「今天要怎麼當個有用的人？」</p>
</body>
</html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/style.css', data: Buffer.from(styleCss) },
    { name: 'OEBPS/chapter1.xhtml', data: Buffer.from(chapter1Xhtml) },
  ])
}

async function readFontSizes(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    for (const iframe of container?.querySelectorAll('iframe') ?? []) {
      const doc = iframe.contentDocument
      const p = doc?.querySelector('p')
      if (!p) continue
      const win = doc.defaultView
      return {
        html: win.getComputedStyle(doc.documentElement).fontSize,
        body: win.getComputedStyle(doc.body).fontSize,
        p: win.getComputedStyle(p).fontSize,
      }
    }
    return null
  })
}

const basePrefs = {
  writingMode: 'horizontal', lineHeight: 1.0, paragraphSpacing: 1.0,
  marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0,
  pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({ fixtureBuffer: buildFixtureEpub(), writingMode: 'horizontal' })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    await page.evaluate((p) => window.applyPreferences({ ...p, fontSize: 1.0 }), basePrefs)
    await new Promise((r) => setTimeout(r, 400))
    const small = await readFontSizes(page)
    console.log('[fontSize=1.0]', JSON.stringify(small))

    await page.evaluate((p) => window.applyPreferences({ ...p, fontSize: 3.0 }), basePrefs)
    await new Promise((r) => setTimeout(r, 400))
    const big = await readFontSizes(page)
    console.log('[fontSize=3.0]', JSON.stringify(big))

    const smallPx = parseFloat(small?.p)
    const bigPx = parseFloat(big?.p)
    report(
      '字級 1.0→3.0 後，段落 computed font-size 應約為 3 倍（書本 body 宣告 16px 不應讓滑桿失效）',
      Number.isFinite(smallPx) && Number.isFinite(bigPx) && bigPx >= smallPx * 2.9,
      `小=${small?.p} 大=${big?.p}`,
    )

    // 調回 1.0 必須復原（inline 樣式不得殘留）。
    await page.evaluate((p) => window.applyPreferences({ ...p, fontSize: 1.0 }), basePrefs)
    await new Promise((r) => setTimeout(r, 400))
    const back = await readFontSizes(page)
    report('字級調回 1.0 後復原為 16px', back?.p === '16px', `實際值＝${back?.p}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
