// epic-54 後續項目：build_summary.js（打包收尾摘要與簽章身分判定）的單元測試。
// 零外部依賴，用 Node.js 內建的 node:test 執行。
//
// 用法：node app/tool/test_build_summary.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const {
  parseApksignerOutput,
  parseKeytoolOutput,
  classifyIdentity,
  evaluateSigning,
  expectedIdentityOf,
  readPubspecVersion,
  findApksigner,
  formatSummary,
  keytoolArgs,
  parseKeyProperties,
  keystoreListArgs,
  formatPreflight,
} = require('./build_summary.js')

const REL = 'a'.repeat(64)
const UPL = 'b'.repeat(64)
const fingerprints = { release: REL, upload: UPL, playSigning: '' }

const APKSIGNER_DEBUG = `Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
Signer #1 certificate SHA-256 digest: b0653dd079aa346d11d19fe3a18fc83d7dac7f7225ecc24b6d2093d8def43f14
Signer #1 certificate SHA-1 digest: e0361dc1c3bb281645d229daf1686a0b2226b6e0`

test('parseApksignerOutput 取出憑證 DN 與 SHA-256', () => {
  const r = parseApksignerOutput(APKSIGNER_DEBUG)
  assert.equal(r.dn, 'C=US, O=Android, CN=Android Debug')
  assert.equal(r.sha256, 'b0653dd079aa346d11d19fe3a18fc83d7dac7f7225ecc24b6d2093d8def43f14')
})

test('parseApksignerOutput 沒有簽章資訊時回傳 null', () => {
  assert.equal(parseApksignerOutput('DOES NOT VERIFY'), null)
})

test('parseKeytoolOutput 取出 Owner 與去冒號的小寫 SHA256', () => {
  const r = parseKeytoolOutput(`Certificate[1]:
Owner: CN=elinkbook upload, O=Ugotit
Issuer: CN=elinkbook upload, O=Ugotit
Certificate fingerprints:
\t SHA1: AA:BB
\t SHA256: AB:CD:EF:01`)
  assert.equal(r.dn, 'CN=elinkbook upload, O=Ugotit')
  assert.equal(r.sha256, 'abcdef01')
})

test('classifyIdentity：CN=Android Debug 判為 debug，指紋對得上判為對應金鑰', () => {
  assert.equal(classifyIdentity({ dn: 'CN=Android Debug', sha256: 'x' }, fingerprints), 'debug')
  assert.equal(classifyIdentity({ dn: 'CN=a', sha256: REL }, fingerprints), 'release')
  assert.equal(classifyIdentity({ dn: 'CN=a', sha256: UPL }, fingerprints), 'upload')
  assert.equal(classifyIdentity({ dn: 'CN=a', sha256: 'c'.repeat(64) }, fingerprints), 'unknown')
})

test('classifyIdentity：空白指紋不會誤判（空字串不等於任何指紋）', () => {
  assert.equal(
    classifyIdentity({ dn: 'CN=a', sha256: '' }, { release: '', upload: '', playSigning: '' }),
    'unknown',
  )
})

test('expectedIdentityOf：apk=release、aab=upload、debug=debug', () => {
  assert.equal(expectedIdentityOf('apk'), 'release')
  assert.equal(expectedIdentityOf('aab'), 'upload')
  assert.equal(expectedIdentityOf('debug'), 'debug')
})

test('evaluateSigning：符合預期 → ok', () => {
  assert.equal(evaluateSigning('release', 'release', fingerprints), 'ok')
})

test('evaluateSigning：簽成 debug 但預期發佈金鑰 → mismatch', () => {
  assert.equal(evaluateSigning('debug', 'release', fingerprints), 'mismatch')
})

test('evaluateSigning：預期金鑰指紋未登錄、實際是未知金鑰 → unregistered（只警告）', () => {
  assert.equal(
    evaluateSigning('unknown', 'release', { release: '', upload: UPL, playSigning: '' }),
    'unregistered',
  )
})

test('evaluateSigning：預期金鑰指紋已登錄、實際是未知金鑰 → mismatch', () => {
  assert.equal(evaluateSigning('unknown', 'release', fingerprints), 'mismatch')
})

test('readPubspecVersion 取出 version 行', () => {
  assert.equal(readPubspecVersion('name: x\nversion: 1.1.0+3\n'), '1.1.0+3')
  assert.equal(readPubspecVersion('name: x\n'), null)
})

test('findApksigner 挑最新的 build-tools 版本', () => {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-'))
  for (const v of ['35.0.0', '36.0.0', '9.0.0']) {
    fs.mkdirSync(path.join(sdk, 'build-tools', v), { recursive: true })
    fs.writeFileSync(path.join(sdk, 'build-tools', v, 'apksigner.bat'), '')
    fs.writeFileSync(path.join(sdk, 'build-tools', v, 'apksigner'), '')
  }
  const found = findApksigner(sdk)
  assert.ok(found.includes('36.0.0'), found)
  assert.equal(findApksigner(path.join(sdk, 'nope')), null)
})

test('formatSummary 含版本、簽章結論、產物與 SHA-256', () => {
  const text = formatSummary({
    label: 'GitHub APK',
    mode: 'release',
    version: '1.1.0+3',
    identity: 'release',
    sha256: REL,
    status: 'ok',
    oauthPrefix: '606617',
    artifacts: [{ name: 'app-release.apk', sizeBytes: 25 * 1024 * 1024, sha256: 'f'.repeat(64) }],
    nextSteps: ['adb install -r x.apk'],
  })
  assert.match(text, /GitHub APK/)
  assert.match(text, /1\.1\.0\+3/)
  assert.match(text, /發佈金鑰/)
  assert.match(text, /606617/)
  assert.match(text, /25\.0 MB/)
  assert.match(text, /f{64}/)
  assert.match(text, /adb install -r x\.apk/)
})

test('formatSummary：mismatch 時有醒目的「不要發佈」', () => {
  const text = formatSummary({
    label: 'GitHub APK', mode: 'release', version: '1', identity: 'debug', sha256: 'z',
    status: 'mismatch', oauthPrefix: 'x', artifacts: [], nextSteps: [],
  })
  assert.match(text, /不要發佈/)
})

test('formatSummary：unverified 標示「未驗證」', () => {
  const text = formatSummary({
    label: 'GitHub APK', mode: 'release', version: '1', identity: null, sha256: null,
    status: 'unverified', oauthPrefix: 'x', artifacts: [], nextSteps: [],
  })
  assert.match(text, /未驗證/)
})

// 審查 Important 1：中文 JDK 的 keytool 預設輸出在地化欄位（「擁有者:」），
// parseKeytoolOutput 只認英文標籤，所以呼叫時必須鎖定英文。
test('keytoolArgs 鎖定英文輸出並帶上 -printcert -jarfile', () => {
  const args = keytoolArgs('"x.aab"')
  assert.ok(args.includes('-J-Duser.language=en'))
  assert.ok(args.includes('-J-Duser.country=US'))
  assert.deepEqual(args.slice(-3), ['-printcert', '-jarfile', '"x.aab"'])
  // -J 選項必須在子命令之前
  assert.ok(args.indexOf('-J-Duser.language=en') < args.indexOf('-printcert'))
})

test('parseKeyProperties 取出金鑰庫路徑、別名與密碼', () => {
  const text = ['storePassword=pw1', 'keyPassword=pw2', 'keyAlias=release', 'storeFile=C:/k/a.jks'].join('\n')
  const r = parseKeyProperties(text)
  assert.deepEqual(r, { storeFile: 'C:/k/a.jks', keyAlias: 'release', storePassword: 'pw1' })
  assert.deepEqual(parseKeyProperties(''), { storeFile: '', keyAlias: '', storePassword: '' })
})

test('keystoreListArgs 鎖定英文、密碼走環境變數而不是明文', () => {
  const args = keystoreListArgs('"a.jks"', '"release"', 'PWVAR')
  assert.ok(args.indexOf('-J-Duser.language=en') < args.indexOf('-list'))
  assert.deepEqual(args.slice(-2), ['-storepass:env', 'PWVAR'])
})

const PREFLIGHT_BASE = {
  label: 'GitHub APK', mode: 'release', version: '1.1.0+3',
  oauthFile: 'config/cloud_oauth.release.json', oauthPrefix: '606617',
  commands: ['flutter build apk --release'],
}

test('formatPreflight：金鑰相符 → 顯示 ✔ 與完整指紋、OAuth 前 6 碼', () => {
  const text = formatPreflight({
    ...PREFLIGHT_BASE,
    keyCheck: { alias: 'release', storeName: 'r.jks', expected: 'release', sha256: REL, identity: 'release', status: 'ok' },
  })
  assert.match(text, /✔ 這是「發佈金鑰」/)
  assert.match(text, /a{64}/)
  assert.match(text, /前 6 碼 606617/)
})

test('formatPreflight：金鑰是上傳金鑰但目標要發佈金鑰 → 顯示 ✘ 與兩邊名稱', () => {
  const text = formatPreflight({
    ...PREFLIGHT_BASE,
    keyCheck: { alias: 'upload', storeName: 'u.jks', expected: 'release', sha256: UPL, identity: 'upload', status: 'mismatch' },
  })
  assert.match(text, /✘ 這是「上傳金鑰」，但此目標需要「發佈金鑰」/)
})

test('formatPreflight：未登錄與讀不到都有 ⚠；debug 不換金鑰', () => {
  const base = { alias: 'a', storeName: 'x.jks', expected: 'release', sha256: 'c'.repeat(64), identity: 'unknown' }
  assert.match(formatPreflight({ ...PREFLIGHT_BASE, keyCheck: { ...base, status: 'unregistered' } }), /⚠ 指紋未登錄/)
  assert.match(formatPreflight({ ...PREFLIGHT_BASE, keyCheck: { ...base, sha256: null, status: 'unreadable' } }), /⚠ 讀不到金鑰庫指紋/)
  assert.match(formatPreflight({ ...PREFLIGHT_BASE, keyCheck: null }), /不換金鑰/)
})
