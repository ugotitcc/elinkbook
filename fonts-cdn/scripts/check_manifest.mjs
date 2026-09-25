// epic-49 Issue 1：比對 fonts/ 內實際檔案的大小與 SHA-256 是否和 fonts.json 一致。
// 用法：node fonts-cdn/scripts/check_manifest.mjs [--manifest <路徑>]
// 結束碼：0 = 全部一致；1 = 有不一致或檔案缺漏。
import { stat } from 'node:fs/promises'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest, sha256OfFile } from './lib.mjs'

const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts, baseDir } = await readManifest(argValue(process.argv, '--manifest', defaultManifest))

let failed = 0
for (const font of fonts) {
  const filePath = join(baseDir, font.file)
  try {
    const { size } = await stat(filePath)
    const digest = await sha256OfFile(filePath)
    if (size !== font.bytes || digest !== font.sha256) {
      failed++
      console.error(`FAIL ${font.id}：大小 ${size}（應為 ${font.bytes}），SHA-256 ${digest}（應為 ${font.sha256}）`)
    } else {
      console.log(`OK   ${font.id}  ${font.path}`)
    }
  } catch (error) {
    failed++
    console.error(`FAIL ${font.id}：無法讀取 ${filePath}（${error.message}）`)
  }
}
if (failed > 0) {
  console.error(`${failed} 個字型與清單不一致`)
  process.exit(1)
}
console.log(`PASS：${fonts.length} 個字型與清單一致`)
