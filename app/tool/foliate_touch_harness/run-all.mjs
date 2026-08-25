// 依序執行本目錄下全部 scenario-*.mjs，彙整 PASS/FAIL 結果。
// smoke-test.mjs 不算在內（那是函式庫健檢，不是正式回歸場景）。

import { spawnSync } from 'node:child_process'
import { readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

async function main() {
  const files = (await readdir(__dirname))
    .filter((f) => f.startsWith('scenario-') && f.endsWith('.mjs'))
    .sort()

  if (files.length === 0) {
    console.error('找不到任何 scenario-*.mjs')
    process.exitCode = 2
    return
  }

  let anyFailed = false
  for (const file of files) {
    console.log(`\n=== ${file} ===`)
    const result = spawnSync('node', [path.join(__dirname, file)], { stdio: 'inherit' })
    if (result.status !== 0) anyFailed = true
  }

  console.log(anyFailed ? '\n整體結果：FAIL' : '\n整體結果：全部 PASS')
  process.exitCode = anyFailed ? 1 : 0
}

main()
