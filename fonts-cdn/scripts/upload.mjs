// epic-49 Issue 1：把字型上傳到 R2。已發布的 key 永遠不覆蓋（見 ADR 0035）。
// 用法：node fonts-cdn/scripts/upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]
// 流程：先檢查全部字型（本機雜湊與清單一致、遠端 key 都不存在），全部通過才開始上傳；
// 任何一項不通過就整批中止，不上傳任何檔案。
// 結束碼：0 = 完成（或 dry-run 列出指令）；1 = 前置檢查失敗或上傳失敗。
import { spawnSync } from 'node:child_process'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest, sha256OfFile } from './lib.mjs'

const args = process.argv
const bucket = argValue(args, '--bucket')
const baseUrl = argValue(args, '--base-url')
const dryRun = args.includes('--dry-run')
if (!bucket || !baseUrl) {
  console.error('用法：node upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]')
  process.exit(1)
}
const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts, baseDir } = await readManifest(argValue(args, '--manifest', defaultManifest))

// 前置檢查：收集所有問題後一次列出
const problems = []
for (const font of fonts) {
  const digest = await sha256OfFile(join(baseDir, font.file))
  if (digest !== font.sha256) {
    problems.push(`${font.id}：本機檔案 SHA-256 ${digest} 與清單 ${font.sha256} 不符`)
  }
  // 連不上（網址打錯、DNS 未生效、離線）時 fetch 會拋例外，也算前置檢查失敗，一起列出
  try {
    const head = await fetch(new URL(font.path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`), { method: 'HEAD' })
    if (head.status === 200) {
      problems.push(`${font.path} 已存在，已發布的檔案不可覆蓋；改版請使用新的版本路徑`)
    } else if (head.status !== 404) {
      problems.push(`${font.path}：無法確認是否已存在（HEAD 回應 ${head.status}）`)
    }
  } catch (error) {
    problems.push(`${font.path}：無法連線到下載服務（${error.cause?.code ?? error.message}）`)
  }
}
if (problems.length > 0) {
  for (const problem of problems) console.error(problem)
  console.error('前置檢查失敗，未上傳任何檔案')
  process.exit(1)
}

for (const font of fonts) {
  const command = ['wrangler@4', 'r2', 'object', 'put', `${bucket}/${font.path}`,
    '--file', join(baseDir, font.file), '--content-type', 'font/ttf', '--remote']
  console.log(`npx ${command.join(' ')}`)
  if (dryRun) continue
  const result = spawnSync('npx', command, { stdio: 'inherit', shell: process.platform === 'win32' })
  if (result.status !== 0) {
    console.error(`上傳 ${font.path} 失敗（結束碼 ${result.status}）`)
    process.exit(1)
  }
}
console.log(dryRun ? 'dry-run：以上為將執行的上傳指令' : `完成：已上傳 ${fonts.length} 個字型`)
