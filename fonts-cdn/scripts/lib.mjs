// epic-49 Issue 1：fonts-cdn 腳本共用函式。只用 Node 內建模組。
import { createHash } from 'node:crypto'
import { createReadStream } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

// 讀取字型清單。baseDir 是清單所在目錄，清單內的 file 欄位相對於它。
export async function readManifest(manifestPath) {
  const absolute = resolve(manifestPath)
  const json = JSON.parse(await readFile(absolute, 'utf8'))
  if (!Array.isArray(json.fonts) || json.fonts.length === 0) {
    throw new Error(`字型清單格式錯誤：${absolute} 缺少 fonts 陣列`)
  }
  return { fonts: json.fonts, baseDir: dirname(absolute) }
}

// 以串流計算檔案的 SHA-256（字型最大約 57MB，不整個讀進記憶體）。
export function sha256OfFile(filePath) {
  return new Promise((resolvePromise, reject) => {
    const hash = createHash('sha256')
    createReadStream(filePath)
      .on('data', (chunk) => hash.update(chunk))
      .on('error', reject)
      .on('end', () => resolvePromise(hash.digest('hex')))
  })
}

// 讀取 --name value 形式的命令列參數；找不到時回傳 fallback。
export function argValue(args, name, fallback = undefined) {
  const index = args.indexOf(name)
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback
}
