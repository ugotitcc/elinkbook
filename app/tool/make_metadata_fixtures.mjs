// 產生 metadata 測試專用 EPUB fixture（epic-66 Issue 2 Task 1）。
// 輸出目錄：app/test/fixtures/metadata/
// 執行方式：$env:PATH = "$env:PNPM_HOME;$env:PATH"; node tool/make_metadata_fixtures.mjs

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildStoredZip } from './foliate_touch_harness/lib/harness.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const OUTPUT_DIR = path.resolve(__dirname, '../test/fixtures/metadata')

const ONE_PIXEL_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64'
)

function buildEpub({
  packageAttrs = 'unique-identifier="pub-id"',
  metadataXml = '',
  manifestExtra = '',
  coverBytes = null,
}) {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`

  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" ${packageAttrs}>
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
${metadataXml}
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
${manifestExtra}
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>
`

  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol>
  <li><a href="c1.xhtml">第一章</a></li>
</ol></nav></body>
</html>
`

  const chapterXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title></head>
<body><p>內文段落</p></body>
</html>
`

  const files = [
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/c1.xhtml', data: Buffer.from(chapterXhtml) },
  ]

  if (coverBytes) {
    files.push({ name: 'OEBPS/cover.png', data: coverBytes })
  }

  return buildStoredZip(files)
}

const FIXTURES = [
  {
    fileName: 'meta_basic.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-basic</dc:identifier>
    <dc:title>基本書名</dc:title>
    <dc:language>zh-TW</dc:language>
    <dc:creator>王小明</dc:creator>`,
    manifestExtra: '    <item id="cover-img" href="cover.png" media-type="image/png" properties="cover-image"/>',
    coverBytes: ONE_PIXEL_PNG,
  },
  {
    fileName: 'meta_multi_identifier.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="isbn">9789860000001</dc:identifier>
    <dc:identifier id="pub-id">urn:uuid:meta-multi-second</dc:identifier>
    <dc:title>多識別碼</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_lang_titles_two_creators.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-lang</dc:identifier>
    <dc:title xml:lang="zh-TW">繁中書名</dc:title>
    <dc:title xml:lang="en">English Title</dc:title>
    <dc:language>zh-TW</dc:language>
    <dc:creator>王小明</dc:creator>
    <dc:creator>李小華</dc:creator>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_creator_role.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-role</dc:identifier>
    <dc:title>角色作者</dc:title>
    <dc:language>zh-TW</dc:language>
    <dc:creator id="c1">張三</dc:creator>
    <meta refines="#c1" property="role" scheme="marc:relators">aut</meta>
    <dc:creator id="c2">李四</dc:creator>
    <meta refines="#c2" property="role" scheme="marc:relators">trl</meta>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_epub2_cover.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-epub2</dc:identifier>
    <dc:title>EPUB2 封面</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta name="cover" content="cover-img"/>`,
    manifestExtra: '    <item id="cover-img" href="cover.png" media-type="image/png"/>',
    coverBytes: ONE_PIXEL_PNG,
  },
  {
    fileName: 'meta_no_cover.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-nocover</dc:identifier>
    <dc:title>無封面</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_fixed_layout.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">urn:uuid:meta-fxl</dc:identifier>
    <dc:title>固定版面</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="rendition:layout">pre-paginated</meta>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_no_identifier.epub',
    packageAttrs: '',
    metadataXml: `    <dc:title>無識別碼</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
  // ——邊界案例（review-issue-2.md Important 5）：真實書籍常見、但 Readium 與 foliate-js
  // 取值規則可能不同的 identifier 形態。期望值由實測對比決定，見 issue-2-report.md。
  {
    fileName: 'meta_unique_id_dangling.epub',
    packageAttrs: 'unique-identifier="missing-id"',
    metadataXml: `    <dc:identifier id="isbn">9789860000009</dc:identifier>
    <dc:identifier id="pub-id">urn:uuid:meta-dangling-second</dc:identifier>
    <dc:title>識別碼懸空</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_identifier_whitespace.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier id="pub-id">
      urn:uuid:meta-ws  
    </dc:identifier>
    <dc:title>識別碼含空白</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
  {
    fileName: 'meta_identifier_opf_scheme.epub',
    packageAttrs: 'unique-identifier="pub-id"',
    metadataXml: `    <dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" id="pub-id" opf:scheme="UUID">urn:uuid:meta-scheme</dc:identifier>
    <dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" id="isbn" opf:scheme="ISBN">9789860000010</dc:identifier>
    <dc:title>識別碼含 opf:scheme</dc:title>
    <dc:language>zh-TW</dc:language>`,
    manifestExtra: '',
    coverBytes: null,
  },
]

fs.mkdirSync(OUTPUT_DIR, { recursive: true })

for (const f of FIXTURES) {
  const epubBuf = buildEpub(f)
  const targetPath = path.join(OUTPUT_DIR, f.fileName)
  fs.writeFileSync(targetPath, epubBuf)
  console.log(`Generated: ${f.fileName} (${epubBuf.length} bytes)`)
}
