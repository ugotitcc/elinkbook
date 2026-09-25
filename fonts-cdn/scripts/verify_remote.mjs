// epic-49 Issue 1：逐一下載線上字型，比對大小與 SHA-256 是否和清單一致。
// 用法：node fonts-cdn/scripts/verify_remote.mjs --base-url <Worker 網址> [--manifest <路徑>]
// 結束碼：0 = 全部一致；1 = 有不一致、缺檔或連線失敗。
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest } from './lib.mjs'

const baseUrl = argValue(process.argv, '--base-url')
if (!baseUrl) {
  console.error('用法：node verify_remote.mjs --base-url <Worker 網址> [--manifest <路徑>]')
  process.exit(1)
}
const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts } = await readManifest(argValue(process.argv, '--manifest', defaultManifest))
const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`

let failed = 0
for (const font of fonts) {
  try {
    const response = await fetch(new URL(font.path, base))
    if (response.status !== 200) {
      failed++
      console.error(`FAIL ${font.id}：HTTP ${response.status}`)
      continue
    }
    // 串流計算雜湊，不把 57MB 整個讀進記憶體
    const hash = createHash('sha256')
    let size = 0
    for await (const chunk of response.body) {
      hash.update(chunk)
      size += chunk.length
    }
    const digest = hash.digest('hex')
    if (size !== font.bytes || digest !== font.sha256) {
      failed++
      console.error(`FAIL ${font.id}：大小 ${size}（應為 ${font.bytes}），SHA-256 ${digest}（應為 ${font.sha256}）`)
    } else {
      console.log(`OK   ${font.id}  ${font.path}`)
    }
  } catch (error) {
    failed++
    console.error(`FAIL ${font.id}：${error.message}`)
  }
}
if (failed > 0) {
  console.error(`${failed} 個字型驗證失敗`)
  process.exit(1)
}
console.log(`PASS：${fonts.length} 個字型線上內容與清單一致`)
