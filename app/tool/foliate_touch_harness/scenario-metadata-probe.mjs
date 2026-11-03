// metadata-probe.js 輕量解析測試（epic-66 Issue 2 Task 2）。
//
// 驗證 readBookMetadata(file) 能在瀏覽器環境正確解析 EPUB metadata，
// 涵蓋多種作者形態、語系物件、多識別碼、固定版面、封面擷取與損毀檔案 reject。
//
// 執行方式：$env:PATH = "$env:PNPM_HOME;$env:PATH"; node scenario-metadata-probe.mjs

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { launchHarnessPage, report } from './lib/harness.mjs'
import { TEST_CASES, compareMetadata } from './lib/metadata-cases.mjs'



async function run() {
  const { browser, page } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
  })

  try {
    // 注入 probe 呼叫輔助函式
    await page.evaluate(() => {
      window.testProbeFile = async (base64, fileName) => {
        const { readBookMetadata } = await import('/metadata-probe.js')
        const bin = atob(base64)
        const bytes = new Uint8Array(bin.length)
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
        const file = new File([bytes], fileName, { type: 'application/epub+zip' })
        return await readBookMetadata(file)
      }
    })

    for (const { filePath, expected } of TEST_CASES) {
      const fileName = path.basename(filePath)
      const buf = await readFile(filePath)
      const base64 = buf.toString('base64')

      try {
        const res = await page.evaluate(
          (b64, name) => window.testProbeFile(b64, name),
          base64,
          fileName
        )

        const mismatches = compareMetadata(res, expected)
        report(fileName, mismatches.length === 0, mismatches.join('; '))
      } catch (err) {
        report(fileName, false, `拋出非預期例外：${err.message}`)
      }
    }

    // 隨機 1 KB 位元組組成的 File：readBookMetadata 必須 reject
    try {
      const randBuf = Buffer.alloc(1024, 42)
      await page.evaluate(
        (b64) => window.testProbeFile(b64, 'corrupt.epub'),
        randBuf.toString('base64')
      )
      report('隨機 1 KB 損毀檔案 reject', false, '應 reject 但成功返回')
    } catch (_) {
      report('隨機 1 KB 損毀檔案 reject', true)
    }
  } finally {
    await browser.close()
  }
}

run().catch((err) => {
  console.error(err)
  process.exit(1)
})
