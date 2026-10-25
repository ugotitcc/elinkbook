// epic-54 Issue 34：直排欄間隔與頁高不一致（舊 WebView）補償測試台情境。
//
// 背景（決策 8）：電腦端 Chromium 156 直排多欄已會把上下內距扣進欄長，無法重現
// Chrome 91（Mobiscribe WAVE）把欄長排成頁高、忽略上下內距所造成的 72px 欄間隔誤差。
// 因此本情境在 Chromium 156 上改以將根元素 `column-gap` 由 72px 加大為 144px（+72px）
// 模擬同樣的欄間隔誤差，驗證：
// 1. 未模擬誤差時，新版引擎不動作（max-height 維持 none）。
// 2. 注入 column-gap 誤差後，MutationObserver 觸發補償，欄間隔收斂回頁高（renderer.size）。
// 3. applyPreferences 重排後（paginator 重設 max-height 為 none）再次注入誤差，仍可重新補償。
// 4. 補償完成後不會造成 style MutationObserver 無窮迴圈。
// 5. 全程無未捕捉例外。

import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'

const PREFS = {
  fontSize: 1.75,
  marginTop: 32,
  marginBottom: 16,
  marginLeft: 24,
  marginRight: 24,
  columnMode: 'single',
}

function buildVerticalFixtureEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000034</dc:identifier>
    <dc:title>直排欄間隔補償診斷用EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine page-progression-direction="rtl"><itemref idref="chapter1"/></spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">第一章</a></li></ol></nav></body>
</html>
`
  const paragraphs = Array.from(
    { length: 160 },
    (_, i) => `<p>第${i + 1}段：天地玄黃宇宙洪荒日月盈昃辰宿列張寒來暑往秋收冬藏閏餘成歲律呂調陽。</p>`,
  ).join('\n  ')

  const chapter1Xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>第一章</title>
  <style>html { writing-mode: vertical-rl; }</style>
</head>
<body>
  ${paragraphs}
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

async function readPitchMetrics(page) {
  return page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    const renderer = view?.renderer
    const contents = renderer?.getContents?.() ?? []
    const doc = contents[0]?.doc
    if (!doc?.body || !doc?.documentElement) return null
    const rects = Array.from(doc.body.getClientRects())
    if (rects.length < 2) return null
    const pitch = Math.abs(rects[1].top - rects[0].top)
    const size = renderer.size
    const maxHeight = doc.documentElement.style.getPropertyValue('max-height')
    return {
      pitch,
      size,
      diff: Math.abs(pitch - size),
      maxHeight,
      rectCount: rects.length,
    }
  })
}

async function injectColumnGapError(page) {
  await page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    const doc = view?.renderer?.getContents?.()?.[0]?.doc
    doc?.documentElement?.style.setProperty('column-gap', '144px', 'important')
  })
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureBuffer: buildVerticalFixtureEpub(),
    writingMode: 'vertical',
    viewport: { width: 749, height: 999 },
    prefs: PREFS,
  })
  try {
    // 檢查項 1：前提（新版引擎未模擬誤差時不動作）
    const m1 = await readPitchMetrics(page)
    report(
      '前提：未模擬誤差時欄間隔與頁高相差 < 1.5 且 max-height 為 none',
      m1 !== null && m1.diff < 1.5 && m1.maxHeight === 'none',
      JSON.stringify(m1),
    )

    // 檢查項 2：模擬舊引擎（注入 column-gap: 144px）
    await injectColumnGapError(page)
    await new Promise((r) => setTimeout(r, 800))
    const m2 = await readPitchMetrics(page)
    const m2MaxHeightPx = m2 ? parseFloat(m2.maxHeight) : NaN
    report(
      '模擬舊引擎：注入 column-gap 誤差後欄間隔收斂回頁高且 max-height 小於頁高',
      m2 !== null &&
        m2.diff < 1.5 &&
        m2.maxHeight.endsWith('px') &&
        Number.isFinite(m2MaxHeightPx) &&
        m2MaxHeightPx < m2.size,
      JSON.stringify(m2),
    )

    // 檢查項 3：重排後可再次補償
    await page.evaluate((prefs) => {
      window.applyPreferences({ ...prefs, writingMode: 'vertical', fontSize: 2.0 })
    }, PREFS)
    await new Promise((r) => setTimeout(r, 800))
    const m3AfterReflow = await readPitchMetrics(page)
    await injectColumnGapError(page)
    await new Promise((r) => setTimeout(r, 800))
    const m3Recompensated = await readPitchMetrics(page)
    report(
      '重排後可再次補償：applyPreferences 重排後與再次注入誤差後欄間隔皆等於頁高',
      m3AfterReflow !== null &&
        m3AfterReflow.diff < 1.5 &&
        m3Recompensated !== null &&
        m3Recompensated.diff < 1.5,
      `重排後=${JSON.stringify(m3AfterReflow)} 再次補償後=${JSON.stringify(m3Recompensated)}`,
    )

    // 檢查項 4：無窮迴圈防護（觀察 1500 ms 內 style 屬性變動次數 < 10）
    const styleMutationCount = await page.evaluate(async () => {
      const view = document.querySelector('foliate-view')
      const doc = view?.renderer?.getContents?.()?.[0]?.doc
      if (!doc?.documentElement) return -1
      let count = 0
      const obs = new MutationObserver(() => { count++ })
      obs.observe(doc.documentElement, { attributes: true, attributeFilter: ['style'] })
      await new Promise((r) => setTimeout(r, 1500))
      obs.disconnect()
      return count
    })
    report(
      '無窮迴圈防護：補償完成後 1500 ms 內根元素 style 變動次數小於 10',
      styleMutationCount >= 0 && styleMutationCount < 10,
      `變動次數=${styleMutationCount}`,
    )

    // 檢查項 5：無未捕捉例外
    report(
      '無未捕捉例外：pageErrors 為空',
      pageErrors.length === 0,
      JSON.stringify(pageErrors),
    )
  } finally {
    await browser.close()
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
