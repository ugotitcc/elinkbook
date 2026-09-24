// Epic 46 排版方向自動偵測全書預掃回歸場景
//
// 開書時「採用書籍排版」（writingMode: null）應依全書任一處直排宣告判定為 vertical，
// 而非僅看第一個 CSS。10 個案例涵蓋外部 CSS、內嵌樣式、OPF metadata、manifest 缺檔與反例。

import { launchHarnessPage, buildStoredZip, harnessEvents, report } from './lib/harness.mjs'

/**
 * 在記憶體中組一本最小合法 EPUB。
 * @param {Object} opts
 * @param {string|null} opts.opfMeta - 插入 <metadata> 內的原始 XML 字串（例如 <meta ...>），無則 null
 * @param {Array<{name:string, content:string}>} opts.cssFiles - 額外 CSS 檔案（放在 OEBPS/ 下）
 * @param {string[]} [opts.missingCssNames] - 只列在 manifest（排在 cssFiles 之前）、zip 內沒有實體檔案的 CSS
 * @param {Array<{title:string, headExtra:string, bodyInner:string, cssHrefs:string[]}>} opts.chapters
 */
function buildEpub({ opfMeta, cssFiles, missingCssNames = [], chapters }) {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const manifestCssItems = [
    ...missingCssNames.map((name, i) => `    <item id="missing${i}" href="${name}" media-type="text/css"/>`),
    ...cssFiles.map((f, i) => `    <item id="css${i}" href="${f.name}" media-type="text/css"/>`),
  ].join('\n')
  const chapterItems = chapters.map((_, i) => `    <item id="c${i + 1}" href="c${i + 1}.xhtml" media-type="application/xhtml+xml"/>`).join('\n')
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000099</dc:identifier>
    <dc:title>排版方向偵測回歸用EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
${opfMeta ? `    ${opfMeta}` : ''}
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
${manifestCssItems ? manifestCssItems + '\n' : ''}${chapterItems}
  </manifest>
  <spine>
${chapters.map((_, i) => `    <itemref idref="c${i + 1}"/>`).join('\n')}
  </spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol>
${chapters.map((c, i) => `<li><a href="c${i + 1}.xhtml">${c.title}</a></li>`).join('')}
</ol></nav></body>
</html>
`
  const chapterXhtml = (c) => {
    const links = c.cssHrefs.map((href) => `<link rel="stylesheet" type="text/css" href="${href}"/>`).join('')
    return `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${c.title}</title>${c.headExtra || ''}${links}</head>
<body>
${c.bodyInner}
</body>
</html>
`
  }

  const files = [
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
  ]
  for (const f of cssFiles) {
    files.push({ name: `OEBPS/${f.name}`, data: Buffer.from(f.content) })
  }
  chapters.forEach((c, i) => {
    files.push({ name: `OEBPS/c${i + 1}.xhtml`, data: Buffer.from(chapterXhtml(c)) })
  })
  return buildStoredZip(files)
}

async function getWritingModeForEpub(fixtureBuffer) {
  const { browser, page } = await launchHarnessPage({
    fixtureBuffer,
    writingMode: null,
  })
  try {
    const events = await harnessEvents(page)
    const first = events.find((e) => e.name === 'onPageRendered')
    return first ? first.args[0] : null
  } finally {
    await browser.close()
  }
}

async function getDiagnosticsForCaseA(fixtureBuffer) {
  const { browser, page } = await launchHarnessPage({
    fixtureBuffer,
    writingMode: null,
  })
  try {
    const diag = await page.evaluate(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      const contents = renderer?.getContents?.() ?? []
      const firstDoc = contents[0]?.doc
      if (!firstDoc) return null
      const dv = firstDoc.defaultView
      const htmlEl = firstDoc.documentElement
      const bodyEl = firstDoc.body
      const mainEl = firstDoc.querySelector('.main')
      return {
        htmlWritingMode: dv.getComputedStyle(htmlEl).writingMode,
        bodyWritingMode: dv.getComputedStyle(bodyEl).writingMode,
        mainWritingMode: mainEl ? dv.getComputedStyle(mainEl).writingMode : null,
        columnWidth: firstDoc.documentElement.style.columnWidth || null,
      }
    })
    return diag
  } finally {
    await browser.close()
  }
}

async function main() {
  // ---- 案例 A：第二個 CSS + -webkit- + 內層元素（對應《蘇東坡新傳》）----
  const epubA = buildEpub({
    opfMeta: null,
    cssFiles: [
      { name: 'base.css', content: 'body{margin:0}' },
      { name: 'vertical.css', content: '.main{-webkit-writing-mode:vertical-rl}' },
    ],
    chapters: [
      {
        title: '第1章',
        headExtra: '',
        cssHrefs: ['base.css', 'vertical.css'],
        bodyInner: '<div class="main"><p>這是第一章的測試內容，用來驗證直排偵測是否正確。</p></div>',
      },
      {
        title: '第2章',
        headExtra: '',
        cssHrefs: ['base.css', 'vertical.css'],
        bodyInner: '<div class="main"><p>這是第二章的測試內容，用來驗證直排偵測是否正確，長度超過門檻。</p></div>',
      },
    ],
  })

  // ---- 案例 B：直排 CSS 只被後面的章節引用 ----
  const epubB = buildEpub({
    opfMeta: null,
    cssFiles: [
      { name: 'base.css', content: 'body{margin:0}' },
      { name: 'v.css', content: 'html{writing-mode:vertical-rl}' },
    ],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>第一章橫排樣式的測試內容，用來讓文件有足夠文字可以排版與分頁，長度超過門檻。</p>' },
      { title: '第2章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>第二章橫排樣式的測試內容，同樣是為了讓章節有足夠文字，長度超過測試門檻。</p>' },
      { title: '第3章', headExtra: '', cssHrefs: ['v.css'], bodyInner: '<p>第三章直排樣式的測試內容，驗證全書預掃是否能偵測到後面章節才出現的直排宣告。</p>' },
    ],
  })

  // ---- 案例 C：XHTML 內嵌 <style> ----
  const epubC = buildEpub({
    opfMeta: null,
    cssFiles: [],
    chapters: [
      {
        title: '第1章',
        headExtra: '<style>body{-epub-writing-mode:vertical-rl}</style>',
        cssHrefs: [],
        bodyInner: '<p>內嵌 style 測試內容，用來驗證 XHTML 內部樣式是否能被偵測為直排，長度足夠。</p>',
      },
    ],
  })

  // ---- 案例 C-2：XHTML style="" 屬性（值內含單引號）----
  const epubC2 = buildEpub({
    opfMeta: null,
    cssFiles: [],
    chapters: [
      {
        title: '第1章',
        headExtra: '',
        cssHrefs: [],
        bodyInner: `<div style="font-family:'Noto Serif'; -webkit-writing-mode: vertical-rl"><p>內嵌 style 屬性測試內容，值內含單引號，驗證剖析是否正確，長度足夠。</p></div>`,
      },
    ],
  })

  // ---- 案例 D：OPF metadata（Kindle 慣例寫法 name+content）----
  const epubD = buildEpub({
    opfMeta: '<meta name="primary-writing-mode" content="vertical-rl"/>',
    cssFiles: [{ name: 'base.css', content: 'body{margin:0}' }],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>OPF metadata 測試內容，驗證 OPF 中繼資料直排宣告的偵測，長度超過門檻。</p>' },
    ],
  })

  // ---- 案例 D-2：OPF metadata（property 寫法，值在 textContent）----
  const epubD2 = buildEpub({
    opfMeta: '<meta property="primary-writing-mode">vertical-rl</meta>',
    cssFiles: [{ name: 'base.css', content: 'body{margin:0}' }],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>OPF property 測試內容，驗證 property 寫法的中繼資料直排宣告，長度足夠。</p>' },
    ],
  })

  // ---- 案例 E：反例 — 註解與橫排 ----
  const epubE = buildEpub({
    opfMeta: null,
    cssFiles: [{ name: 'base.css', content: '/* writing-mode: vertical-rl */\nbody{writing-mode:horizontal-tb}' }],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>反例測試內容，註解內的直排宣告不應被算作有效直排，橫排應保持橫排，長度足夠。</p>' },
    ],
  })

  // ---- 案例 F：manifest 列了但 zip 內缺檔的 CSS 排在直排 CSS 之前（程式審查 I-1）----
  // 缺檔時 book.loadText() 同步回傳 null；預掃須只跳過該項，而非整個中斷退回「第一個 CSS」。
  const epubF = buildEpub({
    opfMeta: null,
    missingCssNames: ['missing.css'],
    cssFiles: [
      { name: 'base.css', content: 'body{margin:0}' },
      { name: 'v.css', content: 'html{writing-mode:vertical-rl}' },
    ],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>第一章橫排樣式的測試內容，用來讓文件有足夠文字可以排版與分頁，長度超過門檻。</p>' },
      { title: '第2章', headExtra: '', cssHrefs: ['v.css'], bodyInner: '<p>第二章直排樣式的測試內容，驗證 manifest 缺檔時預掃仍能偵測到直排宣告。</p>' },
    ],
  })

  // ---- 案例 G：反例 — 正文文字「style = "…"」不算內嵌樣式（程式審查 M-3）----
  const epubG = buildEpub({
    opfMeta: null,
    cssFiles: [],
    chapters: [
      {
        title: '第1章',
        headExtra: '',
        cssHrefs: [],
        bodyInner: '<p>正文提到 CSS 寫法 style = "writing-mode:vertical-rl" 只是文字，不是樣式，應維持橫排，長度足夠。</p>',
      },
    ],
  })

  // ---- 案例 H：反例 — 非法值 tb-lr 不算直排（程式審查 M-4）----
  const epubH = buildEpub({
    opfMeta: null,
    cssFiles: [{ name: 'base.css', content: 'html{writing-mode:tb-lr}' }],
    chapters: [
      { title: '第1章', headExtra: '', cssHrefs: ['base.css'], bodyInner: '<p>非法值 tb-lr 測試內容，Chromium 不認這個值，書本實際呈現橫排，長度足夠。</p>' },
    ],
  })

  const cases = [
    { name: 'A 第二個CSS＋-webkit-＋內層元素', buffer: epubA, expected: 'vertical' },
    { name: 'B 直排CSS只被後面章節引用', buffer: epubB, expected: 'vertical' },
    { name: 'C XHTML內嵌<style>', buffer: epubC, expected: 'vertical' },
    { name: 'C-2 XHTML style="" 含單引號', buffer: epubC2, expected: 'vertical' },
    { name: 'D OPF name=primary-writing-mode', buffer: epubD, expected: 'vertical' },
    { name: 'D-2 OPF property=primary-writing-mode', buffer: epubD2, expected: 'vertical' },
    { name: 'E 反例：註解與橫排', buffer: epubE, expected: 'horizontal' },
    { name: 'F manifest缺檔CSS排在直排CSS之前', buffer: epubF, expected: 'vertical' },
    { name: 'G 反例：正文文字 style = "…"', buffer: epubG, expected: 'horizontal' },
    { name: 'H 反例：非法值 tb-lr', buffer: epubH, expected: 'horizontal' },
  ]

  for (const c of cases) {
    const got = await getWritingModeForEpub(c.buffer)
    report(`${c.name} 應為 ${c.expected}`, got === c.expected, `實際=${got} 預期=${c.expected}`)
  }

  // 案例 A 診斷數值
  const diag = await getDiagnosticsForCaseA(epubA)
  console.log(`\n[DIAG] 案例 A 診斷數值：html=${diag?.htmlWritingMode} body=${diag?.bodyWritingMode} .main=${diag?.mainWritingMode} columnWidth=${diag?.columnWidth}`)
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
