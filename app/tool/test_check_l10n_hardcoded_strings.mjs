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

const { findViolations, scanLibDir, findBareMaterialApps, scanTestDir } = checker
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
// 夾在中間的註解即使含有逗號、括號，也不可截斷參數邊界
assert.deepEqual(lines(dart("Foo(label: // 說明, a) b (", "  '中');")), [2])
assert.deepEqual(lines(dart("Foo(label: c ? /* x, y */ '中' : '文');")), [1, 1])

// 字串插值內含同種引號的巢狀字串，不可讓後續解析錯位
assert.deepEqual(lines(dart("Text('${m['x']}確定');")), [1])
assert.deepEqual(lines(dart("final s = '${m['x']}';", "Text('確定');")), [2])

// 三元運算式、字串串接：字面值不必「直接緊接」關鍵字，只要仍在同一個參數運算式內
// （review-issue-10.md I-1：repo 內 `deleteButtonLabel: x == null ? null : l10n.y` 這類
// 三元寫法很常見，日後若改成硬編碼中文不可靜默通過）
assert.deepEqual(lines(dart("IconButton(tooltip: isB ? '已收藏' : '收藏');")), [1, 1])
assert.deepEqual(lines(dart("Text(c ? '中' : '文');")), [1, 1])
assert.deepEqual(lines(dart("Foo(label: c ? l10n.a : '文');")), [1])
assert.deepEqual(lines(dart("Foo(label: a ? null : '中');")), [1])
assert.deepEqual(lines(dart("Foo(label: (a && b) ? '中' : '文');")), [1, 1])
assert.deepEqual(lines(dart("Text('a' + '中');")), [1])
assert.deepEqual(lines(dart("Text(x + '中');")), [1])
assert.deepEqual(lines(dart("Foo(title: cond ? 'a' : '中');")), [1])
// 字串內的逗號、括號不是參數邊界
assert.deepEqual(lines(dart("Foo(label: 'a, b' + '中');")), [1])
assert.deepEqual(lines(dart("Foo(label: 'a)' + '中');")), [1])

// 插值內的巢狀字面值由外層字面值涵蓋，同一行不可重複回報
assert.deepEqual(lines(dart("Text('${c ? '中' : '文'}');")), [1])

// 自訂 Widget 的文字參數：名稱以 Label／Title／Text／Tooltip／Message／Hint／Subtitle 結尾
// （review-issue-10.md I-2：`AnnotationToolbar(deleteButtonLabel: …)` 不在原本的關鍵字清單內）
assert.deepEqual(lines(dart("AnnotationToolbar(deleteButtonLabel: '刪除');")), [1])
assert.deepEqual(lines(dart("Foo(deleteButtonLabel: existing == null ? null : '刪除');")), [1])
assert.deepEqual(lines(dart("Foo(emptyStateMessage: '尚無資料');")), [1])
assert.deepEqual(lines(dart("Foo(sectionTitle: '設定');")), [1])
// 每個內建的完整參數名各一個案例
for (const kw of [
  'label', 'title', 'subtitle', 'text', 'tooltip', 'message', 'content', 'hint',
  'labelText', 'hintText', 'helperText', 'errorText', 'counterText',
  'prefixText', 'suffixText', 'semanticLabel', 'semanticsLabel',
]) {
  assert.deepEqual(lines(dart(`Foo(${kw}: '中文');`)), [1], `參數名 ${kw} 應被判定為 UI 位置`)
}

// 行號：三引號、多行插值、區塊註解、反斜線續行之後都要正確
// （review-issue-10.md M-1／M-2）
assert.deepEqual(lines(dart("final s = '''", "a", "b''';", "Text('中');")), [4])
assert.deepEqual(lines(dart("final s = '${", "  a", "}';", "Text('中');")), [4])
assert.deepEqual(lines(dart("/* a", "b */", "Text('中');")), [3])
assert.deepEqual(lines(dart("final s = '''a\\", "b\\", "c''';", "Text('中');")), [4])

// 跳脫的引號不結束字串：解析一旦錯位，後面同一行的真違規就會被吞掉
assert.deepEqual(lines(dart("Text('a\\'b'); Text('中');")), [1])
assert.deepEqual(lines(dart("Text('\\\\'); Text('中');")), [1])

// 原始字串內的 $ 與反斜線不是插值／跳脫；插值內的雙引號與大括號要正確配對
assert.deepEqual(lines(dart('Text("${m["}"]}中");', "Text('文');")), [1, 2])
assert.deepEqual(lines(dart("Foo(other: '${ {1: 2}['a'] }', label: '中');")), [1])
// 插值內的 map 字面值 `{…}` 要計入大括號深度：深度算錯會讓後面的引號配對錯位，
// 使 `label: '中'` 被吞進前一個字串而漏報
assert.deepEqual(lines(dart("Foo(a: '${ {1: 2}[\"'\"] }', label: '中');")), [1])
assert.deepEqual(lines(dart("Text(r'${'); Text('中');")), [1])
assert.deepEqual(lines(dart("Text(r'\\'); Text('中');")), [1])
assert.deepEqual(lines(dart('Text("${m["x"]}中");', "Text('文');")), [1, 2])
assert.deepEqual(lines(dart("Text('${ {'a': 1}['a'] } 中');", "Text('文');")), [1, 2])

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

// 參數運算式的邊界：巢狀呼叫的引數、函式主體、相鄰的其他參數，都不屬於該參數
assert.deepEqual(lines(dart("Foo(label: bar('中'));")), [])
assert.deepEqual(lines(dart("Foo(label: () { return '中'; });")), [])
assert.deepEqual(lines(dart("Foo(other: '中', label: l10n.x);")), [])
assert.deepEqual(lines(dart("Foo(label: l10n.x, other: '中');")), [])
assert.deepEqual(lines(dart("Foo(label: c ? l10n.a : l10n.b);")), [])
// `?? '中文'` 是刻意保留的 fallback 逃逸口（例如 eb_sheet_shell 無 AppLocalizations 時的「關閉」）
assert.deepEqual(lines(dart("Foo(label: x ?? '無');")), [])
assert.deepEqual(lines(dart("Text(l10n?.x ?? '無');")), [])
// 名稱不是「文字參數」：Style／Padding 等結尾，或 context 這類只是碰巧以 text 結尾
assert.deepEqual(lines(dart("Foo(labelStyle: '中');")), [])
assert.deepEqual(lines(dart("Foo(titleTextStyle: '中');")), [])
assert.deepEqual(lines(dart("Foo(contentPadding: '中');")), [])

// 專有名詞（內建字型品牌名）
assert.deepEqual(lines(dart("Text(r'思源黑體');")), [])
assert.deepEqual(lines(dart("Text('思源黑體');")), [])
assert.deepEqual(lines(dart("Text('思源黑體 Bold');")), [1]) // 只有「完全等於」品牌名才放行

// ---- 行內例外標記 ----
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore: 測試用")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "Text('確定');")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "a();", "Text('確定');")), [3]) // 只涵蓋下一行
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore:")), [1]) // 沒寫理由不算數

// ---- 測試端：MaterialApp 必須帶 locale／localizationsDelegates／supportedLocales ----
// （Issue 9 審查 M-3：缺 `locale:` 時 flutter_test 預設為 en_US，日後若在該測試加中文斷言會靜默失敗）
const apps = (src) => findBareMaterialApps(src).map((v) => `${v.line}:${v.missing.join('+')}`)
const ALL3 = 'locale+localizationsDelegates+supportedLocales'

// 應該觸發：缺哪些就報哪些
assert.deepEqual(apps(dart("MaterialApp(home: X());")), [`1:${ALL3}`])
assert.deepEqual(apps(dart("const MaterialApp(home: SizedBox());")), [`1:${ALL3}`])
assert.deepEqual(apps(dart("MaterialApp.router(routerConfig: r);")), [`1:${ALL3}`])
assert.deepEqual(
  apps(dart("MaterialApp(", "  localizationsDelegates: d,", "  supportedLocales: s,", "  home: X(),", ");")),
  ['1:locale'],
)
assert.deepEqual(
  apps(dart("a();", "MaterialApp(locale: l, localizationsDelegates: d, home: X());")),
  ['2:supportedLocales'],
)
// 只有巢狀內層有這些參數不算：必須是 MaterialApp 自己的（最外層）參數
assert.deepEqual(
  apps(dart("MaterialApp(home: Foo(locale: l, localizationsDelegates: d, supportedLocales: s));")),
  [`1:${ALL3}`],
)
// 巢狀的 MaterialApp 各自獨立判斷
assert.deepEqual(
  apps(dart("MaterialApp(locale: l, localizationsDelegates: d, supportedLocales: s,", "  home: MaterialApp(home: X()));")),
  [`2:${ALL3}`],
)
// 多個呼叫點、CRLF 行尾的行號
assert.deepEqual(apps(crlf("MaterialApp(home: A());", "MaterialApp(home: B());")), [`1:${ALL3}`, `2:${ALL3}`])

// 不應該觸發
assert.deepEqual(apps(dart("MaterialApp(locale: l, localizationsDelegates: d, supportedLocales: s, home: X());")), [])
assert.deepEqual(apps(dart("MaterialApp(", "  home: X(),", "  supportedLocales: s,", "  locale: l,", "  localizationsDelegates: d,", ");")), [])
assert.deepEqual(apps(dart("// MaterialApp(home: X()) 是舊寫法")), []) // 註解
assert.deepEqual(apps(dart("final s = 'MaterialApp(home: X())';")), []) // 字串內
assert.deepEqual(apps(dart("MyMaterialApp(home: X());")), []) // 只是名稱碰巧包含
// 字串內的括號不可干擾配對
assert.deepEqual(apps(dart("MaterialApp(title: ')', locale: l, localizationsDelegates: d, supportedLocales: s);")), [])

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

  // scanned 只計「實際掃描」的檔案：l10n/ 與 SKIP_FILES 不算
  const clean = scanLibDir(tmp)
  assert.deepEqual(clean.violations, [])
  assert.equal(clean.scanned, 1)
  const cleanRun = spawnSync('node', [SCRIPT, '--lib-dir', tmp], { encoding: 'utf8' })
  assert.equal(cleanRun.status, 0)
  assert.match(cleanRun.stdout, /掃描 1 個檔案/)

  // 人為植入一個硬編碼字串：必須被抓到，且結束碼為 1、輸出含檔案與行號
  write('screens/planted.dart', dart('a();', "Text('植入的硬編碼');"))
  const found = scanLibDir(tmp)
  assert.equal(found.scanned, 2)
  assert.equal(found.violations.length, 1)
  assert.equal(found.violations[0].file, 'screens/planted.dart')
  assert.equal(found.violations[0].line, 2)
  const run = spawnSync('node', [SCRIPT, '--lib-dir', tmp], { encoding: 'utf8' })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /lib\/screens\/planted\.dart:2/)

  // CLI 邊界（review-issue-10.md M-3）：設定錯誤一律結束碼 2，且不可被當成「乾淨」
  const cli = (...args) => spawnSync('node', [SCRIPT, ...args], { encoding: 'utf8' })
  const missing = cli('--lib-dir', path.join(tmp, 'nope'))
  assert.equal(missing.status, 2)
  assert.match(missing.stderr, /不存在/)
  const noArg = cli('--lib-dir')
  assert.equal(noArg.status, 2)
  assert.match(noArg.stderr, /--lib-dir/)
  const emptyDir = path.join(tmp, 'empty')
  fs.mkdirSync(emptyDir)
  const empty = cli('--lib-dir', emptyDir)
  assert.equal(empty.status, 2)
  assert.match(empty.stderr, /沒有找到任何 \.dart/)

  // 測試端目錄掃描：白名單以「檔案＋數量」放行，數量不符（多出未經審視的裸 MaterialApp）必須報
  const testDir = path.join(tmp, 'testdir')
  const writeT = (rel, content) => {
    const full = path.join(testDir, rel)
    fs.mkdirSync(path.dirname(full), { recursive: true })
    fs.writeFileSync(full, content)
  }
  const FULL = 'MaterialApp(locale: l, localizationsDelegates: d, supportedLocales: s, home: X());'
  writeT('a_test.dart', FULL)
  writeT('screens/widgets/eb_sheet_shell_test.dart', 'MaterialApp(home: A());') // 白名單：恰好 1 個
  const okT = scanTestDir(testDir)
  assert.equal(okT.scanned, 2)
  assert.deepEqual(okT.violations, [])
  const okRun = cli('--test-dir', testDir)
  assert.equal(okRun.status, 0)
  assert.match(okRun.stdout, /掃描 2 個測試檔/)
  // 只給 --test-dir 時不可順便掃預設的 lib（否則會混入與這次驗證無關的結果）
  assert.doesNotMatch(okRun.stdout, /個檔案，未發現/)

  writeT('screens/widgets/eb_sheet_shell_test.dart', dart('MaterialApp(home: A());', 'MaterialApp(home: B());'))
  const over = scanTestDir(testDir)
  assert.equal(over.violations.length, 1)
  assert.equal(over.violations[0].file, 'screens/widgets/eb_sheet_shell_test.dart')
  writeT('screens/widgets/eb_sheet_shell_test.dart', 'MaterialApp(home: A());')

  writeT('b_test.dart', dart('a();', 'MaterialApp(localizationsDelegates: d, supportedLocales: s, home: X());'))
  const badT = scanTestDir(testDir)
  assert.equal(badT.violations.length, 1)
  assert.equal(badT.violations[0].file, 'b_test.dart')
  assert.equal(badT.violations[0].line, 2)
  assert.deepEqual(badT.violations[0].missing, ['locale'])
  const badRun = cli('--test-dir', testDir)
  assert.equal(badRun.status, 1)
  assert.match(badRun.stderr, /test\/b_test\.dart:2/)
  assert.match(badRun.stderr, /locale/)

  // 兩個旗標都給時兩邊都檢查（lib 端有 planted.dart 違規、測試端有 b_test.dart 違規）
  const both = cli('--lib-dir', tmp, '--test-dir', testDir)
  assert.equal(both.status, 1)
  assert.match(both.stderr, /lib\/screens\/planted\.dart:2/)
  assert.match(both.stderr, /test\/b_test\.dart:2/)

  // 只給 --lib-dir 時不檢查測試端；--test-dir 缺參數或目錄不存在為設定錯誤
  const libOnly = cli('--lib-dir', tmp)
  assert.equal(libOnly.status, 1)
  assert.doesNotMatch(libOnly.stderr, /test\/b_test/)
  assert.doesNotMatch(libOnly.stdout + libOnly.stderr, /測試檔|測試的 MaterialApp/)
  assert.equal(cli('--test-dir').status, 2)
  assert.equal(cli('--test-dir', path.join(tmp, 'nope')).status, 2)
  // 測試端同樣不可把「掃 0 個檔案」當成乾淨
  const emptyTest = cli('--test-dir', emptyDir)
  assert.equal(emptyTest.status, 2)
  assert.match(emptyTest.stderr, /沒有找到任何 \.dart/)
  // 兩項檢查的結果取最嚴重者：設定錯誤（2）優先於違規（1）
  assert.equal(cli('--lib-dir', emptyDir, '--test-dir', testDir).status, 2)

  // ---- integration_test 掃描（epic-54 Issue 15）：同一套規則，但不套用 app/test 專屬白名單 ----
  const itDir = path.join(tmp, 'itdir')
  const writeIt = (rel, content) => {
    const full = path.join(itDir, rel)
    fs.mkdirSync(path.dirname(full), { recursive: true })
    fs.writeFileSync(full, content)
  }
  writeIt('ok_test.dart', FULL)
  const okIt = cli('--integration-dir', itDir)
  assert.equal(okIt.status, 0)
  assert.match(okIt.stdout, /掃描 1 個 integration 測試檔/)
  // 只給 --integration-dir 時不可順便掃預設的 lib／test
  assert.doesNotMatch(okIt.stdout, /個檔案，未發現/)
  assert.doesNotMatch(okIt.stdout, /個測試檔，所有/)

  // 植入一個缺 locale 的裸 MaterialApp：必須被抓到，輸出帶 integration_test/ 前綴與行號
  writeIt('bad_test.dart', dart('a();', 'tester.pumpWidget(MaterialApp(home: X()));'))
  const badIt = cli('--integration-dir', itDir)
  assert.equal(badIt.status, 1)
  assert.match(badIt.stderr, /integration_test\/bad_test\.dart:2/)
  assert.match(badIt.stderr, /locale/)
  // integration_test 不設白名單：提示不可指向 TEST_BARE_APP_ALLOW；app/test 端仍保留白名單提示
  assert.doesNotMatch(badIt.stderr, /TEST_BARE_APP_ALLOW/)
  assert.match(badIt.stderr, /不設白名單/)
  assert.match(cli('--test-dir', testDir).stderr, /TEST_BARE_APP_ALLOW/)
  // scanTestDir 傳入空白名單時，與 app/test 同名的白名單檔案不得被放行
  writeIt('screens/widgets/eb_sheet_shell_test.dart', 'MaterialApp(home: A());')
  const noAllow = scanTestDir(itDir, new Map())
  assert.ok(noAllow.violations.some((v) => v.file === 'screens/widgets/eb_sheet_shell_test.dart'))

  // 設定錯誤：缺參數、目錄不存在、掃 0 個檔案都不可被當成乾淨
  assert.equal(cli('--integration-dir').status, 2)
  assert.equal(cli('--integration-dir', path.join(tmp, 'nope')).status, 2)
  const emptyIt = cli('--integration-dir', emptyDir)
  assert.equal(emptyIt.status, 2)
  assert.match(emptyIt.stderr, /沒有找到任何 \.dart/)
  // 多個旗標一起給時各自檢查，結束碼取最嚴重者
  assert.equal(cli('--test-dir', testDir, '--integration-dir', itDir).status, 1)
  assert.equal(cli('--integration-dir', itDir, '--lib-dir', emptyDir).status, 2)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

// ---- 無旗標預設：lib、test、integration_test 三項都檢查（epic-54 Issue 15）----
const defaultRun = spawnSync('node', [SCRIPT], { encoding: 'utf8' })
assert.equal(defaultRun.status, 0, defaultRun.stderr)
assert.match(defaultRun.stdout, /個檔案，未發現/)
assert.match(defaultRun.stdout, /個測試檔，所有/)
assert.match(defaultRun.stdout, /個 integration 測試檔，所有/)

console.log('check_l10n_hardcoded_strings：全部測試通過')
