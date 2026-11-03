// metadata 解析測試的共用期望值表與比對（epic-66 Issue 2）。
// 供 scenario-metadata-probe.mjs（整檔讀取）與 scenario-metadata-probe-range.mjs（區段讀取）共用。

import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
export const METADATA_FIXTURES_DIR = path.resolve(__dirname, '../../../test/fixtures/metadata')
export const ROOT_FIXTURES_DIR = path.resolve(__dirname, '../../../test/fixtures')

export const TEST_CASES = [
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
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_unique_id_dangling.epub'),
    expected: {
      title: '識別碼懸空',
      author: null,
      identifier: '9789860000009',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_identifier_whitespace.epub'),
    expected: {
      title: '識別碼含空白',
      author: null,
      identifier: 'urn:uuid:meta-ws',
      isFixedLayout: false,
      hasCover: false,
    },
  },
  {
    filePath: path.join(METADATA_FIXTURES_DIR, 'meta_identifier_opf_scheme.epub'),
    expected: {
      title: '識別碼含 opf:scheme',
      author: null,
      identifier: 'urn:uuid:meta-scheme',
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

/** 比對解析結果與期望值，回傳不一致說明的陣列（空陣列代表全部一致）。 */
export function compareMetadata(res, expected) {
  const mismatches = []
  if ('title' in expected && res.title !== expected.title) {
    mismatches.push(`title: expected '${expected.title}', got '${res.title}'`)
  }
  if ('author' in expected && res.author !== expected.author) {
    mismatches.push(`author: expected '${expected.author}', got '${res.author}'`)
  }
  if ('identifier' in expected && res.identifier !== expected.identifier) {
    mismatches.push(`identifier: expected '${expected.identifier}', got '${res.identifier}'`)
  }
  if ('isFixedLayout' in expected && res.isFixedLayout !== expected.isFixedLayout) {
    mismatches.push(`isFixedLayout: expected ${expected.isFixedLayout}, got ${res.isFixedLayout}`)
  }
  if ('hasCover' in expected) {
    const hasCover = res.coverBase64 !== null && typeof res.coverType === 'string' && res.coverType.startsWith('image/')
    if (hasCover !== expected.hasCover) {
      mismatches.push(`hasCover: expected ${expected.hasCover}, got ${hasCover} (type: ${res.coverType})`)
    }
  }
  return mismatches
}
