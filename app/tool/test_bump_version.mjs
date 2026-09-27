// epic-52-play-release Issue 3：bump_version.js 行為驗證。
// 零外部依賴，用 Node.js 內建的 node:test 執行。
//
// 用法：node app/tool/test_bump_version.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import bump from './bump_version.js'

const {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
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

test('checkVersionCode：必須大於最後一筆', () => {
  const last = { name: '1.0.1', code: 5, date: '2026-10-10' }
  assert.equal(checkVersionCode(6, last), null)
  assert.match(checkVersionCode(5, last), /最後一筆是 5/)
  assert.match(checkVersionCode(4, last), /最後一筆是 5/)
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
