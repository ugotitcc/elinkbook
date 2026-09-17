// /diagnose（2026-09-17，「停用書本 CSS」開關沒有效果）：main.js 的
// buildOverrideCss() 在 publisherStyles===false 時只把既有覆蓋規則
// （font-family/font-weight/line-height/letter-spacing/text-align/
// 文字色/背景色）的 selector 從固定標籤清單換成 `*`，從未處理書本自訂
// 的 margin/padding 等版面配置屬性，導致開關對這類屬性完全無效——這正
// 是使用者回報「蘇東坡新傳」上下留白怎麼調 marginTop/marginBottom 滑桿
// 都調不掉的根因（該書 `.p-text .main { margin: 3em 1em 1em 1em; }`
// 完全不受影響）。
//
// 本情境不依賴使用者自己的版權書籍，改用記憶體中即時組出的最小合法
// EPUB（沿用 app/test/fixtures/sample.epub 的既有最小結構），內文用
// 一個帶有明顯 margin-top/padding 的 `.content` 容器包裹段落文字，
// 精確重現「書本自帶版面配置 CSS」這個 bug pattern，不需要另外提交一份
// 二進位 fixture 檔案。
import { launchHarnessPage, report } from './lib/harness.mjs'
import zlib from 'node:zlib'

// ---- 最小 STORE-only ZIP 產生器（僅供測試 fixture 使用，不需要任何
// 額外套件；EPUB 的 mimetype 依規範必須用 STORE 不壓縮，其餘檔案圖
// 方便一併用 STORE，合法且足夠小）。----
function buildStoredZip(files) {
  const localParts = []
  const centralParts = []
  let offset = 0
  for (const { name, data } of files) {
    const nameBuf = Buffer.from(name, 'utf8')
    const crc = zlib.crc32(data) >>> 0
    const local = Buffer.alloc(30)
    local.writeUInt32LE(0x04034b50, 0)
    local.writeUInt16LE(20, 4)
    local.writeUInt16LE(0, 6)
    local.writeUInt16LE(0, 8)
    local.writeUInt16LE(0, 10)
    local.writeUInt16LE(0, 12)
    local.writeUInt32LE(crc, 14)
    local.writeUInt32LE(data.length, 18)
    local.writeUInt32LE(data.length, 22)
    local.writeUInt16LE(nameBuf.length, 26)
    local.writeUInt16LE(0, 28)
    localParts.push(local, nameBuf, data)

    const central = Buffer.alloc(46)
    central.writeUInt32LE(0x02014b50, 0)
    central.writeUInt16LE(20, 4)
    central.writeUInt16LE(20, 6)
    central.writeUInt16LE(0, 8)
    central.writeUInt16LE(0, 10)
    central.writeUInt16LE(0, 12)
    central.writeUInt16LE(0, 14)
    central.writeUInt32LE(crc, 16)
    central.writeUInt32LE(data.length, 20)
    central.writeUInt32LE(data.length, 24)
    central.writeUInt16LE(nameBuf.length, 28)
    central.writeUInt16LE(0, 30)
    central.writeUInt16LE(0, 32)
    central.writeUInt16LE(0, 34)
    central.writeUInt16LE(0, 36)
    central.writeUInt32LE(0, 38)
    central.writeUInt32LE(offset, 42)
    centralParts.push(central, nameBuf)

    offset += local.length + nameBuf.length + data.length
  }
  const centralBuf = Buffer.concat(centralParts)
  const eocd = Buffer.alloc(22)
  eocd.writeUInt32LE(0x06054b50, 0)
  eocd.writeUInt16LE(files.length, 8)
  eocd.writeUInt16LE(files.length, 10)
  eocd.writeUInt32LE(centralBuf.length, 12)
  eocd.writeUInt32LE(offset, 16)
  return Buffer.concat([...localParts, centralBuf, eocd])
}

function buildFixtureEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000099</dc:identifier>
    <dc:title>停用書本CSS診斷用EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol><li><a href="chapter1.xhtml">第一章</a></li></ol>
  </nav>
</body>
</html>
`
  // 刻意比照真實回報書籍「蘇東坡新傳」的既有 bug pattern：內容容器自帶
  // margin-top（換算 px 需與 3em @ 預設 16px 字級一致，供斷言比對）。
  // `ul { padding-left: 0; }` 模擬常見的書本自帶 CSS reset（許多出版
  // 排版模板會先整體歸零再自行排版）——用來驗證「停用書本 CSS」修好
  // margin/padding 之餘，沒有連帶清掉 ul/ol 賴以呈現縮排的瀏覽器預設
  // padding-left，而是要主動復原成瀏覽器慣例縮排值。
  const styleCss = `.content { margin-top: 3em; padding: 20px 0 0 0; }
ul { padding-left: 0; }`
  const chapter1Xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
  <div class="content">
    <p>這是用來驗證「停用書本 CSS」開關是否能清除書本自訂 margin/padding 的診斷段落文字，長度需超過門檻。</p>
    <ul><li>項目一</li><li>項目二</li></ul>
  </div>
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

async function readContentMarginTop(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    for (const iframe of container?.querySelectorAll('iframe') ?? []) {
      const doc = iframe.contentDocument
      const content = doc?.querySelector('.content')
      if (!content) continue
      return doc.defaultView.getComputedStyle(content).marginTop
    }
    return null
  })
}

async function readListPaddingLeft(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    for (const iframe of container?.querySelectorAll('iframe') ?? []) {
      const doc = iframe.contentDocument
      const ul = doc?.querySelector('ul')
      if (!ul) continue
      return doc.defaultView.getComputedStyle(ul).paddingLeft
    }
    return null
  })
}

async function main() {
  const fixtureBuffer = buildFixtureEpub()
  const { browser, page, pageErrors } = await launchHarnessPage({ fixtureBuffer, writingMode: 'horizontal' })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    const marginBeforeToggle = await readContentMarginTop(page)
    report(
      '基準情境：書本自帶的 .content margin-top 為 3em(=48px)',
      marginBeforeToggle === '48px',
      `實際值＝${marginBeforeToggle}`,
    )

    const listPaddingBeforeToggle = await readListPaddingLeft(page)
    report(
      '基準情境：書本自帶 CSS 把 ul 縮排歸零（padding-left: 0px）',
      listPaddingBeforeToggle === '0px',
      `實際值＝${listPaddingBeforeToggle}`,
    )

    // 模擬使用者在版面設定開啟「停用書本 CSS」（ReaderSettingsSheet
    // 的 _publisherStyles = false，見 reader_settings_sheet.dart:429-432）。
    await page.evaluate(() => window.applyPreferences({
      writingMode: 'horizontal', fontSize: 1.0, lineHeight: 1.0,
      paragraphSpacing: 1.0, marginTop: 0, marginBottom: 0,
      marginLeft: 0, marginRight: 0, pageTurnMode: 'paginated',
      columnMode: 'auto', columnSize: 720, publisherStyles: false,
    }))
    await new Promise((r) => setTimeout(r, 400))

    const marginAfterToggle = await readContentMarginTop(page)
    report(
      '停用書本 CSS 後，.content margin-top 應被清為 0px',
      marginAfterToggle === '0px',
      `實際值＝${marginAfterToggle}`,
    )

    const listPaddingAfterToggle = await readListPaddingLeft(page)
    report(
      '停用書本 CSS 後，ul 縮排應復原為瀏覽器慣例值（40px），不應維持書本歸零的 0px',
      listPaddingAfterToggle === '40px',
      `實際值＝${listPaddingAfterToggle}`,
    )
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
