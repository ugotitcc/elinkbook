// epic-68 Issue 2（標題字型）：main.js buildOverrideCss() 標題字型規則的回歸情境。
//
// 以記憶體組出的 EPUB 重現：書本自己在標題後代指定字型（`h1 span`、`h2 a`），
// 內含 h1–h6、標題內的 span／a（含 h2 > a > span 巢狀），以及一般段落與 div。
// 只比對 computed font-family 字串（不載入真實字型），斷言：
//   A. 開書：h1–h6 與其後代全為標題字型；p、p 內 span／a、div 仍為主字型。
//      （A2 同時是「規則順序」守衛：標題規則排在主字型規則之前時，標題內層
//        span／a 會被主字型蓋回去。）
//   B. 停用書本 CSS（publisherStyles: false）：標題仍為標題字型、內文仍為主字型。
//   C. 取消標題字型（不帶 headingFontFamily）：標題全退回主字型，不留殘餘規則；再帶上又生效。
//   D. 沒有主字型、只有標題字型：標題為標題字型，內文沿用書本／瀏覽器字型。
import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'

const HEADINGS = ['t-h1', 't-h1-span', 't-h1-a', 't-h2-a-span', 't-h3', 't-h4', 't-h5', 't-h6']
const BODIES = ['b-p', 'b-p-span', 'b-p-a', 'b-div']

function buildFixtureEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000068</dc:identifier>
    <dc:title>標題字型探針書</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="chapter1"/></spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">一</a></li></ol></nav></body>
</html>
`
  // 書本自己在標題後代指定字型，證明標題字型規則會蓋過它
  const css = "h1 span { font-family: 'BookSpan'; } h2 a { font-family: 'BookLink'; }"
  const chapter = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title><link rel="stylesheet" href="style.css"/></head>
<body>
  <h1 id="t-h1">純標題</h1>
  <h1><span id="t-h1-span">標題內的 span</span></h1>
  <h1><a id="t-h1-a" href="#x">標題內的連結</a></h1>
  <h2><a href="#x"><span id="t-h2-a-span">巢狀 a 與 span</span></a></h2>
  <h3 id="t-h3">三</h3> <h4 id="t-h4">四</h4> <h5 id="t-h5">五</h5> <h6 id="t-h6">六</h6>
  <p id="b-p">這是一般段落，字數要夠多，harness 才會認為內文已載入完成。<span id="b-p-span">段落內 span</span><a id="b-p-a" href="#x">段落內連結</a></p>
  <div id="b-div">一般 div 文字</div>
</body>
</html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/chapter1.xhtml', data: Buffer.from(chapter) },
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

// 讀出指定 id 元素的 computed font-family（去掉引號）
function readFamilies(page, ids) {
  return page.evaluate((list) => {
    const view = document.querySelector('foliate-view')
    const doc = view.renderer.getContents()[0].doc
    const out = {}
    for (const id of list) {
      const el = doc.getElementById(id)
      out[id] = el
        ? doc.defaultView.getComputedStyle(el).fontFamily.replace(/["']/g, '')
        : '(找不到元素)'
    }
    return out
  }, ids)
}

async function applyPrefs(page, prefs) {
  await page.evaluate((p) => { window.applyPreferences(p) }, prefs)
  // setStyles 觸發的重新排版是非同步的，等它穩定
  await new Promise((r) => setTimeout(r, 600))
}

// 回傳「不等於期望字型」的項目描述；空陣列代表全部符合
function mismatches(families, ids, expected) {
  return ids.filter((id) => families[id] !== expected).map((id) => `${id}=${families[id]}`)
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureBuffer: buildFixtureEpub(),
    writingMode: 'horizontal',
    viewport: { width: 800, height: 1200 },
    prefs: { fontFamily: 'BodyFont', headingFontFamily: 'HeadFont' },
  })
  try {
    report('A1 頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    // ---- A. 開書 ----
    let fam = await readFamilies(page, [...HEADINGS, ...BODIES])
    let bad = mismatches(fam, HEADINGS, 'HeadFont')
    report('A2 開書：h1–h6 與其後代（h1>span、h1>a、h2>a>span）全為 HeadFont',
      bad.length === 0, bad.join('; '))
    bad = mismatches(fam, BODIES, 'BodyFont')
    report('A3 開書：p、p>span、p>a、div 仍為 BodyFont', bad.length === 0, bad.join('; '))

    // ---- B. 停用書本 CSS ----
    await applyPrefs(page, {
      ...BASE_PREFS, fontFamily: 'BodyFont', headingFontFamily: 'HeadFont', publisherStyles: false,
    })
    fam = await readFamilies(page, [...HEADINGS, ...BODIES])
    bad = [...mismatches(fam, HEADINGS, 'HeadFont'), ...mismatches(fam, BODIES, 'BodyFont')]
    report('B 停用書本 CSS：標題仍 HeadFont、內文仍 BodyFont', bad.length === 0, bad.join('; '))

    // ---- C. 取消標題字型 ----
    await applyPrefs(page, { ...BASE_PREFS, fontFamily: 'BodyFont' })
    fam = await readFamilies(page, HEADINGS)
    bad = mismatches(fam, HEADINGS, 'BodyFont')
    report('C 取消標題字型：不留殘餘規則，8 個標題元素全部退回 BodyFont',
      bad.length === 0, bad.join('; '))
    await applyPrefs(page, { ...BASE_PREFS, fontFamily: 'BodyFont', headingFontFamily: 'HeadFont' })
    fam = await readFamilies(page, HEADINGS)
    bad = mismatches(fam, HEADINGS, 'HeadFont')
    report('C2 再次帶上標題字型：又全為 HeadFont', bad.length === 0, bad.join('; '))

    // ---- D. 沒有主字型、只有標題字型 ----
    await applyPrefs(page, { ...BASE_PREFS, headingFontFamily: 'HeadFont' })
    fam = await readFamilies(page, [...HEADINGS, 'b-p'])
    bad = mismatches(fam, HEADINGS, 'HeadFont')
    report('D 無主字型、只有標題字型：標題為 HeadFont', bad.length === 0, bad.join('; '))
    report('D2 無主字型：內文既不是 BodyFont 也不是 HeadFont',
      fam['b-p'] !== 'BodyFont' && fam['b-p'] !== 'HeadFont', `b-p=${fam['b-p']}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
