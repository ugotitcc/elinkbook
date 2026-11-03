// metadata-probe.js 區段讀取測試（epic-66 Issue 2，審查 Important 2、3 的修正）。
//
// 背景：Windows 上讓 224 MB 的書整本走 shouldInterceptRequest，App 程序每次永久多出約兩份
// 書檔大小的記憶體（原生端洩漏，量大小與傳輸位元組成正比），尖峰也高達 2.5～5 GB。
// 改成只抓「ZIP 中央目錄、OPF、封面」所在的區段，傳輸量降到約 MB 級。
//
// 驗證 readBookMetadataByRange(size, fetchRange, name)：
//   1. 與整檔讀取的期望值完全一致（共用 lib/metadata-cases.mjs）。
//   2. 8 MB 填充書只請求少量位元組（遠小於檔案大小），且請求次數有上限。
//   3. fetchRange 失敗或檔案損毀時 reject。
//
// 執行方式：$env:PATH = "$env:PNPM_HOME;$env:PATH"; node scenario-metadata-probe-range.mjs

import { readFile } from 'node:fs/promises'
import crypto from 'node:crypto'
import path from 'node:path'
import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'
import { TEST_CASES, compareMetadata } from './lib/metadata-cases.mjs'

const PADDING_BYTES = 8 * 1024 * 1024
const MAX_BYTES_SERVED = 2 * 1024 * 1024
const MAX_REQUESTS = 40

/** 組一本含 8 MB 未使用填充檔的最小 EPUB：用來證明填充內容不會被讀取。 */
function buildPaddedEpub() {
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:big-padding</dc:identifier>
    <dc:title>大型填充書</dc:title>
    <dc:language>zh-TW</dc:language>
    <dc:creator>填充作者</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>
`
  const nav = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">第一章</a></li></ol></nav></body></html>
`
  const chapter = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body><p>內文</p></body></html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(nav) },
    { name: 'OEBPS/c1.xhtml', data: Buffer.from(chapter) },
    // 隨機內容：不可壓縮，也不會被 metadata 解析用到。
    { name: 'OEBPS/padding.bin', data: crypto.randomBytes(PADDING_BYTES) },
  ])
}

async function run() {
  const { browser, page } = await launchHarnessPage({ fixtureFileName: 'sample.epub' })

  try {
    // 在頁面內注入輔助函式：fetchRange 由記憶體中的位元組提供，並計算請求次數與傳輸量。
    await page.evaluate(() => {
      const decode = (b64) => {
        const bin = atob(b64)
        const bytes = new Uint8Array(bin.length)
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
        return bytes
      }
      window.testProbeRange = async (b64, name, failAfter) => {
        const { readBookMetadataByRange } = await import('/metadata-probe.js')
        const bytes = decode(b64)
        const stats = { requests: 0, bytesServed: 0, size: bytes.length }
        const fetchRange = async (start, end) => {
          stats.requests++
          if (failAfter !== undefined && stats.requests > failAfter) {
            throw new Error('模擬 fetchRange 失敗')
          }
          stats.bytesServed += end - start
          return bytes.slice(start, end).buffer
        }
        const res = await readBookMetadataByRange(bytes.length, fetchRange, name)
        return { res, stats }
      }
    })

    // 1) 與整檔讀取的期望值一致
    for (const { filePath, expected } of TEST_CASES) {
      const fileName = path.basename(filePath)
      const b64 = (await readFile(filePath)).toString('base64')
      try {
        const { res } = await page.evaluate((x, n) => window.testProbeRange(x, n), b64, fileName)
        const mismatches = compareMetadata(res, expected)
        report(`區段讀取 ${fileName}`, mismatches.length === 0, mismatches.join('; '))
      } catch (err) {
        report(`區段讀取 ${fileName}`, false, `拋出非預期例外：${err.message}`)
      }
    }

    // 2) 8 MB 填充書：只讀少量位元組
    try {
      const epub = buildPaddedEpub()
      const { res, stats } = await page.evaluate(
        (x, n) => window.testProbeRange(x, n),
        epub.toString('base64'),
        'padded.epub',
      )
      const mismatches = compareMetadata(res, {
        title: '大型填充書',
        author: '填充作者',
        identifier: 'urn:uuid:big-padding',
        isFixedLayout: false,
      })
      report('填充書 metadata 正確', mismatches.length === 0, mismatches.join('; '))
      report(
        `填充書只傳少量位元組（< ${MAX_BYTES_SERVED / 1024 / 1024} MB）`,
        stats.bytesServed < MAX_BYTES_SERVED,
        `檔案 ${stats.size} 位元組，實際傳輸 ${stats.bytesServed} 位元組（${stats.requests} 次請求）`,
      )
      report(
        `填充書請求次數有上限（<= ${MAX_REQUESTS}）`,
        stats.requests <= MAX_REQUESTS,
        `${stats.requests} 次請求`,
      )
    } catch (err) {
      report('填充書區段讀取', false, `拋出非預期例外：${err.message}`)
    }

    // 3) fetchRange 失敗必須 reject
    try {
      const b64 = (await readFile(TEST_CASES[0].filePath)).toString('base64')
      await page.evaluate((x, n) => window.testProbeRange(x, n, 0), b64, 'fail.epub')
      report('fetchRange 失敗時 reject', false, '應 reject 但成功返回')
    } catch (_) {
      report('fetchRange 失敗時 reject', true)
    }

    // 4) 損毀檔案必須 reject
    try {
      await page.evaluate(
        (x, n) => window.testProbeRange(x, n),
        Buffer.alloc(1024, 42).toString('base64'),
        'corrupt.epub',
      )
      report('區段讀取：隨機 1 KB 損毀檔案 reject', false, '應 reject 但成功返回')
    } catch (_) {
      report('區段讀取：隨機 1 KB 損毀檔案 reject', true)
    }
  } finally {
    await browser.close()
  }
}

run().catch((err) => {
  console.error(err)
  process.exit(1)
})
