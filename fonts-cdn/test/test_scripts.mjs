// epic-49 Issue 1：upload.mjs（--dry-run）與 verify_remote.mjs 的測試。
// 以本機 HTTP 伺服器模擬 Worker；用極小的假字型與暫存清單，不需要網路。
// 用法：node fonts-cdn/test/test_scripts.mjs
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptsDir = fileURLToPath(new URL('../scripts/', import.meta.url))
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex')

const FONT_A = Buffer.from('font-a-bytes')
const FONT_B = Buffer.from('font-b-bytes-longer')

// 建立暫存目錄：fonts/A.ttf、fonts/B.ttf 與清單；overrides 可改寫清單欄位
async function makeFixture(overrides = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'fonts-cdn-test-'))
  await mkdir(join(dir, 'fonts'))
  await writeFile(join(dir, 'fonts', 'A.ttf'), FONT_A)
  await writeFile(join(dir, 'fonts', 'B.ttf'), FONT_B)
  const fonts = [
    { id: 'a', file: 'fonts/A.ttf', path: 'v1/A.ttf', bytes: FONT_A.length, sha256: sha(FONT_A), ...overrides.a },
    { id: 'b', file: 'fonts/B.ttf', path: 'v1/B.ttf', bytes: FONT_B.length, sha256: sha(FONT_B), ...overrides.b },
  ]
  const manifest = join(dir, 'fonts.json')
  await writeFile(manifest, JSON.stringify({ fonts }))
  return manifest
}

// 啟動模擬 Worker：served 是 { 'v1/A.ttf': Buffer }，只回應 GET／HEAD
async function startServer(served) {
  const server = createServer((req, res) => {
    const key = req.url.replace(/^\//, '')
    if (!(key in served)) { res.writeHead(404); res.end(); return }
    res.writeHead(200, { 'Content-Type': 'font/ttf', 'Content-Length': served[key].length })
    res.end(req.method === 'HEAD' ? undefined : served[key])
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  return { server, baseUrl: `http://127.0.0.1:${server.address().port}` }
}

// 以非同步子行程執行腳本。不能用 spawnSync：它會卡住本行程的事件迴圈，
// 同一行程裡的模擬伺服器就無法回應子行程的請求。
function run(script, args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [join(scriptsDir, script), ...args])
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (d) => (stdout += d))
    child.stderr.on('data', (d) => (stderr += d))
    child.on('close', (code) => resolve({ code, stdout, stderr }))
  })
}

// upload --dry-run：遠端沒有任何 key → 列出兩條上傳指令、結束碼 0
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({})
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 0, result.stderr)
  assert.match(result.stdout, /r2 object put test-bucket\/v1\/A\.ttf/)
  assert.match(result.stdout, /r2 object put test-bucket\/v1\/B\.ttf/)
}

// upload：任一 key 已存在 → 結束碼 1，且不列出任何上傳指令（整批中止，不是略過）
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/B.ttf': FONT_B })
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /v1\/B\.ttf 已存在/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// upload：本機檔案雜湊與清單不符 → 結束碼 1，且不列出任何上傳指令
{
  const manifest = await makeFixture({ b: { sha256: '0'.repeat(64) } })
  const { server, baseUrl } = await startServer({})
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /b.*SHA-256/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// upload：連不上下載服務 → 結束碼 1、列出友善訊息，不是未捕獲例外的堆疊
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({})
  await new Promise((resolve) => server.close(resolve))  // 先關掉伺服器，讓 HEAD 連線被拒
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  assert.equal(result.code, 1)
  assert.match(result.stderr, /v1\/A\.ttf：無法連線到下載服務/)
  assert.match(result.stderr, /前置檢查失敗/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// verify_remote：遠端內容與清單一致 → 結束碼 0
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': FONT_A, 'v1/B.ttf': FONT_B })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 0, result.stderr)
  assert.match(result.stdout, /PASS/)
}

// verify_remote：內容被竄改但大小相同 → 以 SHA-256 判定失敗
{
  const manifest = await makeFixture()
  const tampered = Buffer.from(FONT_A)
  tampered[0] ^= 0xff
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': tampered, 'v1/B.ttf': FONT_B })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /FAIL a/)
}

// verify_remote：遠端缺檔 → 失敗
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': FONT_A })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /FAIL b.*404/)
}

console.log('PASS：test_scripts.mjs 全數通過')
