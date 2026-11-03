// foliate-js 輕量 metadata 提取探針（epic-66 Issue 2 Task 2）。
// 供 Windows 端 HeadlessInAppWebView 背景解析 EPUB 詮釋資料使用。
// 規範：ES 保守語法（無 Object.groupBy、Array.prototype.at），嚴格使用相對路徑引用。

import { makeBook } from './view.js'

function firstText(v) {
  if (v == null) return null
  if (typeof v === 'string') {
    const s = v.trim()
    return s.length > 0 ? s : null
  }
  if (Array.isArray(v)) {
    return v.length > 0 ? firstText(v[0]) : null
  }
  if (typeof v === 'object') {
    if ('name' in v) {
      return firstText(v.name)
    }
    const values = Object.values(v)
    return values.length > 0 ? firstText(values[0]) : null
  }
  return null
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onloadend = () => {
      if (typeof reader.result === 'string') {
        const commaIdx = reader.result.indexOf(',')
        resolve(commaIdx >= 0 ? reader.result.slice(commaIdx + 1) : reader.result)
      } else {
        resolve(null)
      }
    }
    reader.onerror = reject
    reader.readAsDataURL(blob)
  })
}

export async function readBookMetadata(file) {
  let book = null
  try {
    book = await makeBook(file)
    const metadata = book.metadata || {}

    const title = firstText(metadata.title)
    const author = firstText(metadata.author)

    let identifier = null
    if (typeof metadata.identifier === 'string') {
      const trimmed = metadata.identifier.trim()
      if (trimmed.length > 0) identifier = trimmed
    }

    const isFixedLayout = book.rendition?.layout === 'pre-paginated'

    let coverBase64 = null
    let coverType = null
    try {
      const coverBlob = await book.getCover?.()
      if (coverBlob) {
        coverBase64 = await blobToBase64(coverBlob)
        coverType = coverBlob.type || null
      }
    } catch (_) {
      coverBase64 = null
      coverType = null
    }

    return {
      title,
      author,
      identifier,
      isFixedLayout,
      coverBase64,
      coverType,
    }
  } finally {
    try {
      book?.destroy?.()
    } catch (_) {}
  }
}

// ——區段讀取（審查 Important 2、3 的修正）——
// 大檔（224 MB）整本走 Windows 的 shouldInterceptRequest 會在 App 程序留下約兩份書檔大小的
// 原生記憶體（外掛／WebView2 端不釋放，量與傳輸位元組成正比），尖峰也高達數 GB。
// metadata 只需要 ZIP 中央目錄、OPF 與封面，所以提供一個「依需要才抓區段」的類 Blob 物件：
// makeBook／zip.js 只用到 size、name、type 與 slice(a, b).arrayBuffer()。
// 以固定大小的區塊快取，避免 zip.js 零碎的小讀取變成大量往返。
const RANGE_BLOCK_SIZE = 256 * 1024

class RangeFile {
  constructor(size, fetchRange, name) {
    this.size = size
    this.name = name
    this.type = 'application/epub+zip'
    this._fetchRange = fetchRange
    this._blocks = new Map()
  }

  _block(index) {
    let pending = this._blocks.get(index)
    if (!pending) {
      const start = index * RANGE_BLOCK_SIZE
      const end = Math.min(start + RANGE_BLOCK_SIZE, this.size)
      pending = Promise.resolve(this._fetchRange(start, end)).then((buf) => new Uint8Array(buf))
      this._blocks.set(index, pending)
    }
    return pending
  }

  // 語意比照 Blob.slice：省略或負值的邊界相對於結尾，超出範圍夾回 [0, size]。
  slice(start, end) {
    const size = this.size
    let from = start === undefined ? 0 : start
    let to = end === undefined ? size : end
    if (from < 0) from = Math.max(size + from, 0)
    if (to < 0) to = Math.max(size + to, 0)
    from = Math.min(from, size)
    to = Math.min(Math.max(to, from), size)
    const owner = this
    return {
      size: to - from,
      type: owner.type,
      async arrayBuffer() {
        const length = to - from
        const out = new Uint8Array(length)
        if (length === 0) return out.buffer
        const first = Math.floor(from / RANGE_BLOCK_SIZE)
        const last = Math.floor((to - 1) / RANGE_BLOCK_SIZE)
        const blocks = await Promise.all(
          Array.from({ length: last - first + 1 }, (_, i) => owner._block(first + i)),
        )
        let written = 0
        for (let i = 0; i < blocks.length; i++) {
          const blockStart = (first + i) * RANGE_BLOCK_SIZE
          const lo = Math.max(from, blockStart) - blockStart
          const hi = Math.min(to, blockStart + blocks[i].length) - blockStart
          out.set(blocks[i].subarray(lo, hi), written)
          written += hi - lo
        }
        return out.buffer
      },
    }
  }
}

/**
 * 以區段方式讀取 EPUB metadata，不需要把整本書載入。
 * @param {number} size 書檔位元組數
 * @param {(start: number, end: number) => Promise<ArrayBuffer>} fetchRange 取得 [start, end) 的位元組
 * @param {string} [name] 檔名（foliate 以副檔名判斷格式，預設 book.epub）
 */
export async function readBookMetadataByRange(size, fetchRange, name = 'book.epub') {
  return readBookMetadata(new RangeFile(size, fetchRange, name))
}
