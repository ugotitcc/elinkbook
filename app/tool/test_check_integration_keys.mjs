// epic-54 Issue 17：check_integration_keys.js 行為驗證。
// 零外部依賴，可直接用 Node.js 執行（比照 test_check_l10n_hardcoded_strings.mjs 既有慣例）。
//
// 用法：node app/tool/test_check_integration_keys.mjs

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import checker from './check_integration_keys.js'

const { findStaleKeys } = checker
const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check_integration_keys.js')

const stale = (lib, tests) =>
  findStaleKeys(lib, tests.map((src, i) => ({ file: `t${i}.dart`, src }))).map((v) => v.key)

// ---- 存在的 key：不報 ----
assert.deepEqual(stale(["const Key('reader_chrome_back_button')"], ["find.byKey(const Key('reader_chrome_back_button'))"]), [])

// 動態範本：$index 與 ${...} 都視為萬用（Key 建構子內的範本）
assert.deepEqual(stale(["Key('nav_zone_$index')"], ["find.byKey(const Key('nav_zone_3'))"]), [])
assert.deepEqual(stale(["Key('notes_sheet_annotation_delete_${item.key}')"], ["Key('notes_sheet_annotation_delete_hh_1_n1')"]), [])
assert.deepEqual(stale(["itemKey: Key('reader_settings_column_mode_$keySuffix'),"], ["Key('reader_settings_column_mode_single')"]), [])

// keyPrefix：前綴＋底線
assert.deepEqual(stale(["keyPrefix: 'reader_settings_font_size',"], ["Key('reader_settings_font_size_increment')"]), [])

// 測試自己建立的 widget key
assert.deepEqual(stale([], ["ElevatedButton(key: const Key('manual_import_button'), onPressed: null)"]), [])
assert.deepEqual(stale([], ["ElevatedButton(key: Key('manual_import_button'))"]), [])

// 雙引號（Key("x")、ValueKey("x")）
assert.deepEqual(stale([`const Key("dq_present_key")`], [`find.byKey(const Key("dq_present_key"))`]), [])
assert.deepEqual(stale([`const Key('x_present_key')`], [`find.byKey(const Key("dq_gone_key"))`, `find.byKey(ValueKey("dq_gone_key2"))`]), ['dq_gone_key', 'dq_gone_key2'])

// 測試端含 $ 的 key（迴圈變數）無法靜態解析，跳過，不當成過期
assert.deepEqual(stale(["const Key('pdf_settings_tab_filters')"], ["tester.tap(find.byKey(Key('pdf_settings_$keySuffix')))"]), [])

// ---- 過期 key：要報 ----
assert.deepEqual(stale(["const Key('reader_chrome_toc_button')"], ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])

// 前綴相同但不是「前綴＋底線」不算存在
assert.deepEqual(stale(["keyPrefix: 'reader_settings_font_size',"], ["Key('reader_settings_font_sizeX')"]), ['reader_settings_font_sizeX'])

// ValueKey 也檢查；同一個 key 出現多次要各報一次，附正確行號
const result = findStaleKeys(
  ["const Key('a_present')"],
  [{ file: 'x.dart', src: ["find.byKey(const Key('a_present'));", "tap(find.byKey(ValueKey('gone_1')));", "tap(find.byKey(const Key('gone_1')));"].join('\n') }],
)
assert.deepEqual(result.map((v) => [v.file, v.line, v.key]), [['x.dart', 2, 'gone_1'], ['x.dart', 3, 'gone_1']])

// ---- 守衛不能被 lib/ 內的非 Key 字串範本癱瘓（Issue 17 計畫審查 C-1）----
// 多語系產生檔的 "$_temp0"、'${x}%'、'h${a}_n${b}' 轉成正規表示式會是萬用；不是 Key 建構子的參數，必須忽略。
const wildcardLib = [
  `return "$_temp0";`,
  `final s = '\${(progress * 100).round()}%';`,
  `String get key => 'h\${highlight?.id}_n\${note?.id}';`,
]
assert.deepEqual(stale(wildcardLib, ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])

// Key 範本若第一個 $ 之前固定字元太少（過寬），也不採用
assert.deepEqual(stale(["Key('${prefix}_x')"], ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])
assert.deepEqual(stale(["Key('ab$c')"], ["find.byKey(const Key('abzzz'))"]), ['abzzz'])

// ---- CLI ----
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'chk-int-keys-'))
try {
  const libDir = path.join(tmp, 'lib')
  const itDir = path.join(tmp, 'it')
  const emptyDir = path.join(tmp, 'empty')
  fs.mkdirSync(libDir); fs.mkdirSync(itDir); fs.mkdirSync(emptyDir)
  fs.writeFileSync(path.join(libDir, 'a.dart'), "const Key('present_key');\n")
  fs.writeFileSync(path.join(itDir, 'ok_test.dart'), "find.byKey(const Key('present_key'));\n")
  const cli = (...args) => spawnSync('node', [SCRIPT, ...args], { encoding: 'utf8' })

  assert.equal(cli('--lib-dir', libDir, '--integration-dir', itDir).status, 0)

  fs.writeFileSync(path.join(itDir, 'bad_test.dart'), "line1;\nfind.byKey(const Key('gone_key'));\n")
  const bad = cli('--lib-dir', libDir, '--integration-dir', itDir)
  assert.equal(bad.status, 1)
  assert.match(bad.stdout + bad.stderr, /bad_test\.dart:2/)
  assert.match(bad.stdout + bad.stderr, /gone_key/)

  // lib/l10n/ 是產生檔，不參與 key 比對：就算裡面有同名字串也不能讓過期 key 變成存在
  fs.mkdirSync(path.join(libDir, 'l10n'))
  fs.writeFileSync(path.join(libDir, 'l10n', 'app_localizations_zh.dart'), `String get x => 'gone_key';\nreturn "$_temp0";\n`)
  assert.equal(cli('--lib-dir', libDir, '--integration-dir', itDir).status, 1)

  // 掃到 0 個檔案必須失敗，不能當成乾淨
  assert.equal(cli('--lib-dir', libDir, '--integration-dir', emptyDir).status, 2)
  assert.equal(cli('--lib-dir', emptyDir, '--integration-dir', itDir).status, 2)
  assert.equal(cli('--lib-dir', path.join(tmp, 'nope'), '--integration-dir', itDir).status, 2)
  assert.equal(cli('--bogus').status, 2)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log('全部測試通過')
