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

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const METADATA_FIXTURES_DIR = path.resolve(__dirname, '../../test/fixtures/metadata')
const ROOT_FIXTURES_DIR = path.resolve(__dirname, '../../test/fixtures')

const TEST_CASES = [
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_basic.epub'),
    expected: {
      title: '基本書名',
      author: '王小明',
      identifier: 'urn:uuid:meta-basic',
      isFixedLayout: false,
      hasCover: true,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_multi_identifier.epub'),
    expected: {
      title: '多識別碼',
      author: null,
      identifier: 'urn:uuid:meta-multi-second',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_lang_titles_two_creators.epub'),
    expected: {
      title: '繁中書名',
      author: '王小明',
      identifier: 'urn:uuid:meta-lang',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_creator_role.epub'),
    expected: {
      title: '角色作者',
      author: '張三',
      identifier: 'urn:uuid:meta-role',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_epub2_cover.epub'),
    expected: {
      title: 'EPUB2 封面',
      author: null,
      identifier: 'urn:uuid:meta-epub2',
      isFixedLayout: false,
      hasCover: true,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_no_cover.epub'),
    expected: {
      title: '無封面',
      author: null,
      identifier: 'urn:uuid:meta-nocover',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_fixed_layout.epub'),
    expected: {
      title: '固定版面',
      author: null,
      identifier: 'urn:uuid:meta-fxl',
      isFixedLayout: true,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_no_identifier.epub'),
    expected: {
      title: '無識別碼',
      author: null,
      identifier: null,
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(ROOT_FIXTURES_DIR, 'sample.epub'),
    expected: {
      identifier: 'urn:uuid:00000000-0000-0000-0000-000000000001',
      hasCover: true,
      isFixedLayout: false,
    },
  },
  {
    filePath: path.join(ROOT_FIXTURES_DIR, 'sample_fxl_svg_cover.epub'),
    expected: {
      isFixedLayout: true,
      hasCover: true,
    },
  },
]

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

        let pass = true
        const mismatches = []

        if ('title' in expected && res.title !== expected.title) {
          pass = false
          mismatches.push(`title: expected '${expected.title}', got '${res.title}'`)
        }
        if ('author' in expected && res.author !== expected.author) {
          pass = false
          mismatches.push(`author: expected '${expected.author}', got '${res.author}'`)
        }
        if ('identifier' in expected && res.identifier !== expected.identifier) {
          pass = false
          mismatches.push(`identifier: expected '${expected.identifier}', got '${res.identifier}'`)
        }
        if ('isFixedLayout' in expected && res.isFixedLayout !== expected.isFixedLayout) {
          pass = false
          mismatches.push(`isFixedLayout: expected ${expected.isFixedLayout}, got ${res.isFixedLayout}`)
        }
        if ('hasCover' in expected) {
          const hasCover = res.coverBase64 !== null && typeof res.coverType === 'string' && res.coverType.startsWith('image/')
          if (hasCover !== expected.hasCover) {
            pass = false
            mismatches.push(`hasCover: expected ${expected.hasCover}, got ${hasCover} (type: ${res.coverType})`)
          }
        }

        report(fileName, pass, mismatches.join('; '))
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
