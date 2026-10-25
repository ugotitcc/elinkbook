// epic-65 Issue 3（縮排排除置中與無文字段落）：main.js markNoIndentParagraphs() 的回歸情境。
//
// 以記憶體組出的 EPUB 重現：書本自己有全域 `p { text-indent: 2em }`，內含一般段落、
// 三種置中（書本 class、行內 style、align 屬性）、靠右段落、三種無文字段落（空、只有 <br>、
// 只有圖片）。依序用 window.applyPreferences() 切換偏好，斷言每個段落實際的
// computed text-indent 與 data-elink-no-indent 標記：
//   1. 縮排 2 字：一般與靠右段落縮排；置中與無文字段落為 0 並被標記。
//   2. 使用者選了「文字對齊」：置中段落改為縮排（不再排除）；無文字段落仍排除。
//   3. 取消「文字對齊」：置中段落再次被排除（呼叫順序：必須在 setStyles 之後標記）。
//   4. 縮排 0：全部 computed 為 0px（0 與「關閉」語意不同）。
//   5. 縮排關閉（null）：不留任何標記，段落退回書本自己的 2em。
//   6. 再次開啟：重新標記。
import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'

// 1x1 透明 GIF，供「只有圖片」的段落使用
const TINY_GIF = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=='

// 段落索引（兩個章節內容相同）
const P = {
  normal1: 0, centerClass: 1, centerInline: 2, centerAlign: 3,
  empty: 4, brOnly: 5, imgOnly: 6, right: 7, normal2: 8,
}
const CENTERED = [P.centerClass, P.centerInline, P.centerAlign]
const NO_TEXT = [P.empty, P.brOnly, P.imgOnly]
const INDENTED = [P.normal1, P.right, P.normal2]

function buildFixtureEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000065</dc:identifier>
    <dc:title>縮排排除探針書</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="chapter1"/><itemref idref="chapter2"/></spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">一</a></li><li><a href="chapter2.xhtml">二</a></li></ol></nav></body>
</html>
`
  const css = 'p { text-indent: 2em; margin: 0.5em 0; } .c { text-align: center; } .r { text-align: right; }'
  const long = '書本自己有全域段落縮排，這段是一般段落，要照使用者設定的縮排顯示，字數要夠多才會換行。'
  const body = (title) => `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${title}</title><link rel="stylesheet" href="style.css"/></head>
<body>
  <p>${long}</p>
  <p class="c">置中段落（書本 class）</p>
  <p style="text-align:center">置中段落（行內 style）</p>
  <p align="center">置中段落（align 屬性）</p>
  <p></p>
  <p><br/></p>
  <p><img src="${TINY_GIF}" alt=""/></p>
  <p class="r">靠右段落，不屬於排除範圍</p>
  <p>${long}</p>
</body>
</html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/chapter1.xhtml', data: Buffer.from(body('第一章')) },
    { name: 'OEBPS/chapter2.xhtml', data: Buffer.from(body('第二章')) },
    { name: 'OEBPS/style.css', data: Buffer.from(css) },
  ])
}

// 與 launchHarnessPage 內預設 initialPrefs 相同的完整偏好；applyPreferences 需要完整物件。
const BASE_PREFS = {
  writingMode: 'horizontal', fontSize: 1.0, lineHeight: 1.0,
  paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16,
  marginLeft: 24, marginRight: 24,
  pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
}

// 讀出所有已載入章節裡每個 p 的 computed text-indent（換算成 em）與標記
function readParagraphs(page) {
  return page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    return view.renderer.getContents().map(({ doc, index }) => ({
      index,
      paragraphs: [...doc.querySelectorAll('p')].map((p) => {
        const cs = doc.defaultView.getComputedStyle(p)
        return {
          em: parseFloat(cs.textIndent) / parseFloat(cs.fontSize),
          marked: p.hasAttribute('data-elink-no-indent'),
        }
      }),
    }))
  })
}

async function applyPrefs(page, prefs) {
  await page.evaluate((p) => { window.applyPreferences(p) }, prefs)
  // setAttribute 觸發的重新排版是非同步的，等它穩定
  await new Promise((r) => setTimeout(r, 600))
}

const near = (a, b) => Math.abs(a - b) < 0.05

// 對每個已載入章節斷言：指定索引的段落「缺口」em 值與標記
function expectAll(chapters, indexes, { em, marked }) {
  const bad = []
  for (const ch of chapters) {
    for (const i of indexes) {
      const p = ch.paragraphs[i]
      if (!p || !near(p.em, em) || (marked !== undefined && p.marked !== marked)) {
        bad.push(`章${ch.index} p${i}: em=${p?.em?.toFixed(2)} marked=${p?.marked}`)
      }
    }
  }
  return bad
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureBuffer: buildFixtureEpub(),
    writingMode: 'horizontal',
    viewport: { width: 800, height: 1200 },
    prefs: { firstLineIndent: 2 },
  })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    // ---- 1. 縮排 2 字（開書當下由 load 事件標記）----
    let chapters = await readParagraphs(page)
    report('至少載入一個章節', chapters.length >= 1, `已載入章節數=${chapters.length}`)
    report('1a 一般與靠右段落縮排 2em 且未標記',
      expectAll(chapters, INDENTED, { em: 2, marked: false }).length === 0,
      expectAll(chapters, INDENTED, { em: 2, marked: false }).join('; '))
    report('1b 三種置中段落為 0 且已標記',
      expectAll(chapters, CENTERED, { em: 0, marked: true }).length === 0,
      expectAll(chapters, CENTERED, { em: 0, marked: true }).join('; '))
    report('1c 空／只有 br／只有圖片的段落為 0 且已標記',
      expectAll(chapters, NO_TEXT, { em: 0, marked: true }).length === 0,
      expectAll(chapters, NO_TEXT, { em: 0, marked: true }).join('; '))

    // ---- 2. 使用者選了「文字對齊」----
    await applyPrefs(page, { ...BASE_PREFS, firstLineIndent: 2, textAlign: 'justify' })
    chapters = await readParagraphs(page)
    report('2a 選了文字對齊：置中段落改為縮排 2em 且未標記',
      expectAll(chapters, CENTERED, { em: 2, marked: false }).length === 0,
      expectAll(chapters, CENTERED, { em: 2, marked: false }).join('; '))
    report('2b 選了文字對齊：無文字段落仍排除',
      expectAll(chapters, NO_TEXT, { em: 0, marked: true }).length === 0,
      expectAll(chapters, NO_TEXT, { em: 0, marked: true }).join('; '))

    // ---- 3. 取消「文字對齊」：置中段落再次被排除 ----
    await applyPrefs(page, { ...BASE_PREFS, firstLineIndent: 2 })
    chapters = await readParagraphs(page)
    report('3 取消文字對齊：置中段落再次排除（0 且已標記）',
      expectAll(chapters, CENTERED, { em: 0, marked: true }).length === 0,
      expectAll(chapters, CENTERED, { em: 0, marked: true }).join('; '))

    // ---- 4. 縮排 0：全部 0px（0 不等於關閉）----
    await applyPrefs(page, { ...BASE_PREFS, firstLineIndent: 0 })
    chapters = await readParagraphs(page)
    const all = [0, 1, 2, 3, 4, 5, 6, 7, 8]
    report('4 縮排 0：所有段落 computed 為 0（清掉書本的 2em）',
      expectAll(chapters, all, { em: 0 }).length === 0,
      expectAll(chapters, all, { em: 0 }).join('; '))

    // ---- 5. 縮排關閉：不留標記，退回書本自己的 2em ----
    await applyPrefs(page, { ...BASE_PREFS })
    chapters = await readParagraphs(page)
    report('5a 縮排關閉：沒有任何標記殘留',
      chapters.every((ch) => ch.paragraphs.every((p) => !p.marked)),
      JSON.stringify(chapters.map((ch) => ch.paragraphs.filter((p) => p.marked).length)))
    report('5b 縮排關閉：所有段落退回書本的 2em',
      expectAll(chapters, all, { em: 2, marked: false }).length === 0,
      expectAll(chapters, all, { em: 2, marked: false }).join('; '))

    // ---- 6. 再次開啟：重新標記 ----
    await applyPrefs(page, { ...BASE_PREFS, firstLineIndent: 2 })
    chapters = await readParagraphs(page)
    report('6 再次開啟：置中與無文字段落重新標記為 0',
      expectAll(chapters, [...CENTERED, ...NO_TEXT], { em: 0, marked: true }).length === 0,
      expectAll(chapters, [...CENTERED, ...NO_TEXT], { em: 0, marked: true }).join('; '))
    report('6 再次開啟：一般段落縮排 2em',
      expectAll(chapters, INDENTED, { em: 2, marked: false }).length === 0,
      expectAll(chapters, INDENTED, { em: 2, marked: false }).join('; '))
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
