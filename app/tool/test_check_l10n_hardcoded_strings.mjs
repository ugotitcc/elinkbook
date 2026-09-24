// epic-45-interface-i18n Issue 10：check_l10n_hardcoded_strings.js 行為驗證。
// 零外部依賴，可直接用 Node.js 執行（比照 test_text_offset_map.mjs 既有慣例）。
//
// 用法：node app/tool/test_check_l10n_hardcoded_strings.mjs

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import checker from './check_l10n_hardcoded_strings.js'

const { findViolations, scanLibDir } = checker
const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check_l10n_hardcoded_strings.js')

// 以「行」組合 Dart 片段（JS 字串用雙引號，Dart 的單引號與 ${} 才不必跳脫）
const dart = (...lines) => lines.join('\n')
const lines = (src) => findViolations(src).map((v) => v.line)

// ---- 應該觸發 ----

// Text 位置參數
assert.deepEqual(lines(dart("Text('確定');")), [1])
assert.deepEqual(lines(dart("const Text('確定');")), [1])
assert.deepEqual(lines(dart("SelectableText('內文');")), [1])
assert.deepEqual(lines(dart("child: const Text(", "  '確定',", ");")), [2])

// 具名參數關鍵字（含換行、const）
assert.deepEqual(lines(dart("AppBar(title: '設定');")), [1])
assert.deepEqual(lines(dart("IconButton(tooltip: '關閉');")), [1])
assert.deepEqual(lines(dart("InputDecoration(hintText: '搜尋', labelText: '書名');")), [1, 1])
assert.deepEqual(lines(dart("ListTile(", "  subtitle:", "    '說明',", ");")), [3])
assert.deepEqual(lines(dart("SnackBar(content: const Text('已儲存'));")), [1])
assert.deepEqual(lines(dart("Foo(label: const '標籤');")), [1])

// 含插值、含跳脫引號、三引號
assert.deepEqual(lines(dart("Text('第 $n 頁');")), [1])
assert.deepEqual(lines(dart("Text('不要\\'中\\'');")), [1])
assert.deepEqual(lines(dart("Text('''第一行", "第二行''');")), [1])

// Dart 原始字串（r 前綴）：前綴不可讓位置判斷失效
assert.deepEqual(lines(dart("Text(r'原始中文字串');")), [1])
assert.deepEqual(lines(dart('Text(r"原始中文字串");')), [1])
assert.deepEqual(lines(dart("Text(const r'原始中文字串');")), [1])
assert.deepEqual(lines(dart("AppBar(title: r'原始中文字串');")), [1])

// 相鄰字串串接：後段含中文，沿用前段的位置判斷
assert.deepEqual(lines(dart("Text('abc'", "  '中文');")), [2])

// 關鍵字與字串之間夾著註解，仍屬 Widget 字串參數位置
assert.deepEqual(lines(dart("AppBar(title: // 標題", "  '設定');")), [2])

// 字串插值內含同種引號的巢狀字串，不可讓後續解析錯位
assert.deepEqual(lines(dart("Text('${m['x']}確定');")), [1])
assert.deepEqual(lines(dart("final s = '${m['x']}';", "Text('確定');")), [2])

// CRLF 行尾（Windows 工作樹）
const crlf = (...ls) => ls.join('\r\n')
assert.deepEqual(lines(crlf("Text('中');", "Text('文');")), [1, 2])
assert.deepEqual(lines(crlf("AppBar(title:", "  '設定');")), [2])
assert.deepEqual(lines(crlf("// Text('註解') 按鈕", "Text('確定');")), [2])

// 行號正確（多行來源）
assert.deepEqual(lines(dart("a();", "b();", "Text('中');", "c();", "Text('文');")), [3, 5])

// ---- 不應該觸發 ----

// 已在地化 / 無中文
assert.deepEqual(lines(dart("Text(l10n.confirm);")), [])
assert.deepEqual(lines(dart("Text('OK');")), [])
assert.deepEqual(lines(dart("AppBar(title: Text(l10n.settingsTitle));")), [])

// 註解（本專案註解一律為中文，是最大宗誤報來源）
assert.deepEqual(lines(dart("// Text('確定') 按鈕")), [])
assert.deepEqual(lines(dart("/* title: '設定' */")), [])
assert.deepEqual(lines(dart("/* 外層 /* 巢狀 Text('確定') */ 仍在註解內 Text('確定') */")), [])
assert.deepEqual(lines(dart("/// 文件註解 tooltip: '關閉'")), [])
assert.deepEqual(lines(dart("final s = '${m['x']}'; // Text('註解中文')")), [])

// 字串內的 // 不是註解：其後同一行的真違規仍要抓到
assert.deepEqual(lines(dart("final u = 'http://x.com'; Text('確定');")), [1])

// 非 Widget 字串參數位置：例外 / 診斷 / assert / 資料 / fallback
assert.deepEqual(lines(dart("throw Exception('下載失敗');")), [])
assert.deepEqual(lines(dart("debugPrint('載入失敗');")), [])
assert.deepEqual(lines(dart("assert(x > 0, '必須為正整數');")), [])
assert.deepEqual(lines(dart("const kName = '未分類';")), [])
assert.deepEqual(lines(dart("final t = l10n?.close ?? '關閉';")), [])
assert.deepEqual(lines(dart("final r = RegExp(r'^第[章回]');")), [])
// 關鍵字必須是完整識別字，context: 不是 text:
assert.deepEqual(lines(dart("Foo(context: '中文');")), [])

// 專有名詞（內建字型品牌名）
assert.deepEqual(lines(dart("Text('思源黑體');")), [])
assert.deepEqual(lines(dart("Text('思源黑體 Bold');")), [1]) // 只有「完全等於」品牌名才放行

// ---- 行內例外標記 ----
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore: 測試用")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "Text('確定');")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "a();", "Text('確定');")), [3]) // 只涵蓋下一行
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore:")), [1]) // 沒寫理由不算數

// ---- 目錄掃描與 CLI ----
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'l10n-audit-'))
try {
  const write = (rel, content) => {
    const full = path.join(tmp, rel)
    fs.mkdirSync(path.dirname(full), { recursive: true })
    fs.writeFileSync(full, content)
  }
  write('screens/clean.dart', "Text('OK'); Text(l10n.x);")
  write('l10n/app_localizations_zh.dart', "Text('確定');") // gen-l10n 產生檔，須略過
  write('library/models/book_group.dart', "Foo(title: '未分類');") // SKIP_FILES
  write('reader/text_conversion_dict.dart', "Foo(text: '內存');") // SKIP_FILES

  assert.deepEqual(scanLibDir(tmp), [])
  assert.equal(spawnSync('node', [SCRIPT, '--lib-dir', tmp]).status, 0)

  // 人為植入一個硬編碼字串：必須被抓到，且結束碼為 1、輸出含檔案與行號
  write('screens/planted.dart', dart('a();', "Text('植入的硬編碼');"))
  const found = scanLibDir(tmp)
  assert.equal(found.length, 1)
  assert.equal(found[0].file, 'screens/planted.dart')
  assert.equal(found[0].line, 2)
  const run = spawnSync('node', [SCRIPT, '--lib-dir', tmp], { encoding: 'utf8' })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /lib\/screens\/planted\.dart:2/)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log('check_l10n_hardcoded_strings：全部測試通過')
