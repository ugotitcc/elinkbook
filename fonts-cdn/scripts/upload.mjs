// epic-49 Issue 1：把字型上傳到 R2。已發布的 key 永遠不覆蓋（見 ADR 0035）。
// 用法：node fonts-cdn/scripts/upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]
// 流程：先檢查全部字型（本機雜湊與清單一致；遠端 key 不存在，或已存在且內容與清單完全一致），
// 全部通過才開始上傳；任何一項不通過就整批中止，不上傳任何檔案。
// 遠端已有且內容一致的字型會略過，所以上傳到一半中斷後，重跑本腳本就能補傳剩下的字型。
// 結束碼：0 = 完成（或 dry-run 列出指令）；1 = 前置檢查失敗或上傳失敗。
import { spawnSync } from 'node:child_process'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { argValue, digestOfResponse, readManifest, sha256OfFile } from './lib.mjs'

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
const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`

// 前置檢查：收集所有問題後一次列出
const problems = []
const pending = []  // 需要上傳的字型；遠端已有且內容一致的不列入
for (const font of fonts) {
  try {
    const digest = await sha256OfFile(join(baseDir, font.file))
    if (digest !== font.sha256) {
      problems.push(`${font.id}：本機檔案 SHA-256 ${digest} 與清單 ${font.sha256} 不符`)
    }
  } catch (error) {
    problems.push(`${font.id}：無法讀取本機檔案 ${font.file}（${error.code ?? error.message}）`)
  }
  // 連不上（網址打錯、DNS 未生效、離線）時 fetch 會拋例外，也算前置檢查失敗，一起列出
  try {
    const url = new URL(font.path, base)
    const head = await fetch(url, { method: 'HEAD' })
    if (head.status === 404) {
      pending.push(font)
    } else if (head.status === 200) {
      // 已存在：下載比對內容。一致代表上次已上傳成功，略過；不一致就不可覆蓋，整批中止
      const response = await fetch(url)
      const remote = response.status === 200 ? await digestOfResponse(response) : null
      if (remote && remote.size === font.bytes && remote.sha256 === font.sha256) {
        console.log(`${font.path} 已發布且內容一致，略過`)
      } else {
        problems.push(`${font.path} 已存在但內容與清單不符；已發布的檔案不可覆蓋，改版請使用新的版本路徑`)
      }
    } else {
      problems.push(`${font.path}：無法確認是否已存在（HEAD 回應 ${head.status}）`)
    }
  } catch (error) {
    problems.push(`${font.path}：無法連線到下載服務（${error.cause?.code ?? error.message}）`)
  }
}
// 結束時一律設定 process.exitCode、讓程式自然結束，不呼叫 process.exit()：
// Windows 上 fetch 的連線還在關閉時強制結束，會觸發 libuv 斷言而崩潰
if (problems.length > 0) {
  for (const problem of problems) console.error(problem)
  console.error('前置檢查失敗，未上傳任何檔案')
  process.exitCode = 1
} else if (pending.length === 0) {
  console.log('全部字型都已發布且內容一致，不需要上傳')
} else {
  await uploadAll(pending)
}

async function uploadAll(pending) {
  for (const font of pending) {
    // --file 用相對於清單目錄的路徑（並以清單目錄為 cwd）：repo 放在含空白的目錄下時，
    // Windows 的 shell 不會把路徑拆成兩個參數
    const command = ['wrangler@4', 'r2', 'object', 'put', `${bucket}/${font.path}`,
      '--file', font.file, '--content-type', 'font/ttf', '--remote']
    const commandLine = `npx ${command.join(' ')}`
    console.log(commandLine)
    if (dryRun) continue
    // Windows 的 npx 是 .cmd，必須經過 shell；傳整行字串而不是參數陣列，避免 Node 的 DEP0190 警告
    const result = process.platform === 'win32'
      ? spawnSync(commandLine, { stdio: 'inherit', shell: true, cwd: baseDir })
      : spawnSync('npx', command, { stdio: 'inherit', cwd: baseDir })
    if (result.status !== 0) {
      console.error(`上傳 ${font.path} 失敗（結束碼 ${result.status}）。確認問題後重跑即可，已上傳的字型會自動略過`)
      process.exitCode = 1
      return
    }
  }
  console.log(dryRun ? 'dry-run：以上為將執行的上傳指令' : `完成：已上傳 ${pending.length} 個字型`)
}
