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
