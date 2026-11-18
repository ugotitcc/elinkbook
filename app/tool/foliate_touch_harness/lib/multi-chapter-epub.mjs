// epic-67 Issue 5：3 章、每章夠長的最小合法 EPUB（記憶體組出，不進版控二進位檔）。
// 章節索引 0～2；CFI /6/2 = 第 0 章、/6/4 = 第 1 章、/6/6 = 第 2 章。
import { buildStoredZip } from './harness.mjs'

// verticalCss：書本 CSS 自己宣告直排（vertical-rl），用於「依書內 CSS 自動偵測直排」的情境。
function chapter(n, verticalCss) {
  const para = `第${n}章的內容段落，用來撐出足夠的文字長度以便分頁與驗證，重複多次。`.repeat(40)
  const paragraphs = Array.from({ length: 12 }, (_, i) => `<p>${para}${i}</p>`).join('')
  const style = verticalCss ? '<style>html,body{writing-mode:vertical-rl}</style>' : ''
  return `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第${n}章</title>${style}</head>
<body><h1>第${n}章</h1>${paragraphs}</body></html>`
}

export function buildMultiChapterEpub({ verticalCss = false } = {}) {
  const container = `<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`
  const opf = `<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="p"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="p">urn:uuid:epic67-degrade-1</dc:identifier><dc:title>降級測試</dc:title><dc:language>zh-TW</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/><item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine></package>`
  const nav = `<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目錄</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">一</a></li><li><a href="c2.xhtml">二</a></li><li><a href="c3.xhtml">三</a></li></ol></nav></body></html>`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(container) },
    { name: 'OEBPS/content.opf', data: Buffer.from(opf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(nav) },
    { name: 'OEBPS/c1.xhtml', data: Buffer.from(chapter(1, verticalCss)) },
    { name: 'OEBPS/c2.xhtml', data: Buffer.from(chapter(2, verticalCss)) },
    { name: 'OEBPS/c3.xhtml', data: Buffer.from(chapter(3, verticalCss)) },
  ])
}
