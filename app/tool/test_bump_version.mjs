// epic-52-play-release Issue 3：bump_version.js 行為驗證。
// 零外部依賴，用 Node.js 內建的 node:test 執行。
//
// 用法：node app/tool/test_bump_version.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import bump from './bump_version.js'

const {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
  maxLogEntry,
  isValidVersionName,
  nextVersionCode,
  checkVersionCode,
  formatDate,
  getHeadCommit,
  appendLogEntry,
} = bump

// 對照表範本：說明文字、表頭、分隔線，沒有資料列
const LOG_HEADER = [
  '# Google Play 版本對照表',
  '',
  '- 說明文字 | 裡面有直線符號也不能被當成資料列',
  '',
  '| versionName | versionCode | 日期 | 軌道 | commit | 說明 |',
  '|---|---|---|---|---|---|',
  '',
].join('\n')

const LOG_TWO_ROWS =
  LOG_HEADER +
  '| 1.0.0 | 1 | 2026-10-01 | 內部測試 | e1a12ed6 | 第一次上傳 |\n' +
  '| 1.0.0 | 1 | 2026-10-03 | 正式版 | e1a12ed6 |  |\n'

test('parsePubspecVersion：解析 name 與 code', () => {
  const text = 'name: app\nversion: 1.0.1+5\nenvironment:\n'
  assert.deepEqual(parsePubspecVersion(text), { name: '1.0.1', code: 5 })
})

test('parsePubspecVersion：不理會註解裡的 version 字樣', () => {
  const text = '# Read more about iOS versioning\n# version: 9.9.9+99\nversion: 1.0.0+1\n'
  assert.deepEqual(parsePubspecVersion(text), { name: '1.0.0', code: 1 })
})

test('parsePubspecVersion：找不到或格式錯誤時丟出錯誤', () => {
  assert.throws(() => parsePubspecVersion('name: app\n'), /找不到 version:/)
  assert.throws(() => parsePubspecVersion('version: 1.0.0\n'), /格式不對/)
  assert.throws(() => parsePubspecVersion('version: 1.0+3\n'), /格式不對/)
})

test('replacePubspecVersion：LF 檔案只改 version 那一行', () => {
  const before = 'name: app\n\n# 註解\nversion: 1.0.1+5\ndependencies:\n'
  const after = 'name: app\n\n# 註解\nversion: 1.0.2+6\ndependencies:\n'
  assert.equal(replacePubspecVersion(before, '1.0.2', 6), after)
})

test('replacePubspecVersion：CRLF 檔案保留 \\r\\n，其餘位元組不變', () => {
  const before = 'name: app\r\n\r\nversion: 1.0.1+5\r\n# 註解\r\n'
  const after = 'name: app\r\n\r\nversion: 1.0.1+6\r\n# 註解\r\n'
  assert.equal(replacePubspecVersion(before, '1.0.1', 6), after)
})

test('parseLogEntries／lastLogEntry：只有表頭時沒有紀錄', () => {
  assert.deepEqual(parseLogEntries(LOG_HEADER), [])
  assert.equal(lastLogEntry(LOG_HEADER), null)
})

test('lastLogEntry：回傳最後一筆資料列', () => {
  assert.deepEqual(lastLogEntry(LOG_TWO_ROWS), {
    name: '1.0.0',
    code: 1,
    date: '2026-10-03',
    track: '正式版',
    commit: 'e1a12ed6',
    note: '',
  })
})

test('lastLogEntry：CRLF 對照表也能解析', () => {
  const crlf = LOG_TWO_ROWS.replace(/\n/g, '\r\n')
  assert.equal(lastLogEntry(crlf).track, '正式版')
})

test('parseLogEntries：說明欄裡有 | 時不截斷', () => {
  const text = LOG_HEADER + '| 1.0.2 | 3 | 2026-10-12 | 內部測試 | abc1234 | 修正 A | B 問題 |\n'
  assert.equal(lastLogEntry(text).note, '修正 A | B 問題')
})

test('isValidVersionName：只接受 數字.數字.數字', () => {
  for (const ok of ['1.0.0', '10.20.30', '0.0.1']) assert.equal(isValidVersionName(ok), true, ok)
  for (const bad of ['1.0', '1.0.0.1', 'a.b.c', '1.0.0+1', ' 1.0.0', '']) {
    assert.equal(isValidVersionName(bad), false, bad)
  }
})

test('nextVersionCode：取 pubspec 與最後一筆較大者再加 1', () => {
  assert.equal(nextVersionCode(5, null), 6)
  assert.equal(nextVersionCode(5, { code: 5 }), 6)
  assert.equal(nextVersionCode(7, { code: 5 }), 8)
  // Review Focus 1：pubspec 落後對照表
  assert.equal(nextVersionCode(3, { code: 5 }), 6)
})

test('checkVersionCode：對照表沒有紀錄時，正整數都接受', () => {
  assert.equal(checkVersionCode(1, null), null)
  assert.match(checkVersionCode(0, null), /正整數/)
})

test('checkVersionCode：必須大於對照表最大的 versionCode', () => {
  const max = { name: '1.0.1', code: 5, date: '2026-10-10' }
  assert.equal(checkVersionCode(6, max), null)
  assert.match(checkVersionCode(5, max), /最大的 versionCode 是 5/)
  assert.match(checkVersionCode(4, max), /最大的 versionCode 是 5/)
})

// review-issue-3.md I-1：把較舊的版本推到正式版後，最後一列不是最大的 versionCode
const LOG_OLDER_PROMOTED =
  LOG_HEADER +
  '| 1.0.1 | 5 | 2026-10-10 | 內部測試 | aaa1111 |  |\n' +
  '| 1.0.0 | 4 | 2026-10-11 | 正式版 | bbb2222 |  |\n'

test('maxLogEntry：回傳 versionCode 最大的一列，不一定是最後一列', () => {
  assert.equal(maxLogEntry(LOG_HEADER), null)
  assert.equal(lastLogEntry(LOG_OLDER_PROMOTED).code, 4)
  assert.deepEqual(maxLogEntry(LOG_OLDER_PROMOTED), {
    name: '1.0.1',
    code: 5,
    date: '2026-10-10',
    track: '內部測試',
    commit: 'aaa1111',
    note: '',
  })
})

test('maxLogEntry：同一個 versionCode 有兩列時，回傳後面那列', () => {
  assert.equal(maxLogEntry(LOG_TWO_ROWS).track, '正式版')
})

test('formatDate：本地時間 YYYY-MM-DD，月和日補零', () => {
  assert.equal(formatDate(new Date(2026, 0, 5, 23, 59)), '2026-01-05')
  assert.match(formatDate(new Date()), /^\d{4}-\d{2}-\d{2}$/)
})

test('getHeadCommit：成功時回傳去掉換行的結果', () => {
  assert.equal(getHeadCommit(() => Buffer.from('abc1234\n')), 'abc1234')
})

test('getHeadCommit：git 失敗時回傳 unknown，不丟出例外', () => {
  const fail = () => {
    throw new Error('git: command not found')
  }
  assert.equal(getHeadCommit(fail), 'unknown')
  assert.equal(getHeadCommit(() => ''), 'unknown')
})

test('appendLogEntry：新增一筆，舊內容不變', () => {
  const entry = { name: '1.0.1', code: 2, date: '2026-10-10', track: '內部測試', commit: 'abc1234', note: '' }
  const result = appendLogEntry(LOG_TWO_ROWS, entry)
  assert.ok(result.startsWith(LOG_TWO_ROWS))
  assert.equal(result.slice(LOG_TWO_ROWS.length), '| 1.0.1 | 2 | 2026-10-10 | 內部測試 | abc1234 |  |\n')
  assert.deepEqual(lastLogEntry(result), entry)
})

test('appendLogEntry：CRLF 檔案用 CRLF；檔尾沒有換行時先補一個', () => {
  const entry = { name: '1.0.0', code: 1, date: '2026-10-01', track: '內部測試', commit: 'unknown', note: '' }
  const crlf = LOG_HEADER.replace(/\n/g, '\r\n')
  assert.ok(appendLogEntry(crlf, entry).endsWith('|  |\r\n'))
  const noTrailing = LOG_HEADER.trimEnd()
  assert.equal(appendLogEntry(noTrailing, entry), noTrailing + '\n| 1.0.0 | 1 | 2026-10-01 | 內部測試 | unknown |  |\n')
})

// ---- 端到端：在暫存資料夾實際執行腳本 ----
// 暫存資料夾不是 git repo，所以 commit 欄位會是 unknown（Review Focus 3）。

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'bump_version.js')

// GIT_CEILING_DIRECTORIES 讓 git 不會往暫存資料夾的上層找 repo，
// 即使系統暫存資料夾剛好在某個 git repo 底下，commit 欄位也固定是 unknown。
// t.after 在每個測試結束後刪除暫存資料夾。
function setup(t, pubspec, log) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bump-version-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const pubspecPath = path.join(dir, 'pubspec.yaml')
  const logPath = path.join(dir, 'release-log.md')
  fs.writeFileSync(pubspecPath, pubspec)
  if (log !== undefined) fs.writeFileSync(logPath, log)
  const run = (args, input = '') =>
    spawnSync(process.execPath, [SCRIPT, '--pubspec', pubspecPath, '--log', logPath, ...args], {
      input,
      encoding: 'utf8',
      cwd: dir,
      env: { ...process.env, GIT_CEILING_DIRECTORIES: os.tmpdir() },
    })
  const read = () => ({
    pubspec: fs.readFileSync(pubspecPath, 'utf8'),
    log: fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : null,
  })
  return { dir, run, read }
}

const PUBSPEC_CRLF = 'name: app\r\n# version: 註解\r\nversion: 1.0.1+5\r\ndependencies:\r\n'
const LOG_LAST_5 = LOG_HEADER + '| 1.0.1 | 5 | 2026-10-10 | 內部測試 | abc1234 |  |\n'
const TODAY = formatDate(new Date())

test('端到端 --yes：versionCode 加 1，保留 CRLF，對照表加一筆', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, LOG_LAST_5)
  const r = run(['--yes'])
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, PUBSPEC_CRLF.replace('1.0.1+5', '1.0.1+6'))
  assert.equal(read().log, LOG_LAST_5 + `| 1.0.1 | 6 | ${TODAY} | 內部測試 | unknown |  |\n`)
  assert.match(r.stdout + r.stderr, /unknown/)
})

test('端到端 第一次上架：對照表沒有紀錄，回答 n 保留 1.0.0+1', (t) => {
  const pubspec = 'name: app\nversion: 1.0.0+1\n'
  const { run, read } = setup(t, pubspec, LOG_HEADER)
  const r = run([], 'n\n\n')
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, pubspec)
  assert.equal(lastLogEntry(read().log).code, 1)
  assert.equal(lastLogEntry(read().log).name, '1.0.0')
})

test('端到端 回答 n 但數字不夠大：印出原因並重問，改答 y 後成功', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run([], 'n\ny\n1.1.0\n')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /最大的 versionCode 是 5/)
  assert.equal(read().pubspec, 'version: 1.1.0+6\n')
  assert.equal(lastLogEntry(read().log).name, '1.1.0')
})

test('端到端 pubspec 落後對照表：回答 y 得到最後一筆加 1', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+3\n', LOG_LAST_5)
  const r = run([], 'y\n\n')
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, 'version: 1.0.1+6\n')
})

test('端到端 非預期輸入：大小寫、空白、錯誤格式都會重問', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run([], 'maybe\n  Y  \n1.0\n1.2.0\n')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /請輸入 y 或 n/)
  assert.match(r.stdout, /數字\.數字\.數字/)
  assert.equal(read().pubspec, 'version: 1.2.0+6\n')
})

test('端到端 EOF：輸入中斷時結束碼 1，兩個檔案都不變', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, LOG_LAST_5)
  const r = run([], '')
  assert.equal(r.status, 1)
  assert.equal(read().pubspec, PUBSPEC_CRLF)
  assert.equal(read().log, LOG_LAST_5)
})

test('端到端 找不到對照表：結束碼 2，pubspec 不變', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, undefined)
  const r = run(['--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /找不到/)
  assert.equal(read().pubspec, PUBSPEC_CRLF)
})

test('端到端 pubspec 版本格式錯誤：結束碼 2，檔案都不變', (t) => {
  const { run, read } = setup(t, 'version: 1.0\n', LOG_LAST_5)
  const r = run(['--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /格式不對/)
  assert.equal(read().pubspec, 'version: 1.0\n')
  assert.equal(read().log, LOG_LAST_5)
})

test('端到端 不認得的旗標：結束碼 2', (t) => {
  const { run } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run(['--force'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /--force/)
})

test('端到端 最後一列是較舊的正式版：回答 n 保留已用過的 5 會被擋下，改答 y 得到 6', (t) => {
  // review-issue-3.md I-1：5 已經上傳過，之後才把較舊的 4 推到正式版
  const { run, read } = setup(t, 'version: 1.0.1+5\n', LOG_OLDER_PROMOTED)
  const r = run([], 'n\ny\n\n')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /最大的 versionCode 是 5/)
  assert.equal(read().pubspec, 'version: 1.0.1+6\n')
  assert.equal(lastLogEntry(read().log).code, 6)
})

test('端到端 對照表路徑是資料夾：結束碼 2，中文錯誤訊息', (t) => {
  // review-issue-3.md M-2
  const { dir, run } = setup(t, 'version: 1.0.1+5\n', undefined)
  fs.mkdirSync(path.join(dir, 'release-log.md'))
  const r = run(['--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /不是檔案/)
  assert.doesNotMatch(r.stderr, /EISDIR/)
  // read() 會去讀對照表路徑（現在是資料夾），這裡只讀 pubspec
  assert.equal(fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8'), 'version: 1.0.1+5\n')
})

test('端到端 --pubspec 後面緊接另一個旗標：結束碼 2，提示要接檔案路徑', (t) => {
  // review-issue-3.md M-3
  const { run } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run(['--pubspec', '--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /--pubspec 後面要接檔案路徑/)
})
