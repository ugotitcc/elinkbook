// epic-45-interface-i18n Issue 10：防遺漏稽核腳本。
//
// 兩項檢查（規則契約見 docs/epics/epic-45-interface-i18n/spec.md §9）：
//   1. 掃描 app/lib/**/*.dart，找出「Widget 字串參數位置」上未經 AppLocalizations
//      包裝、含中文字元的字串字面值，避免既有畫面遺漏、以及日後新增畫面忘記包裝。
//   2. 掃描 app/test/**/*.dart，確認每個 MaterialApp 都帶 locale／localizationsDelegates／
//      supportedLocales（Issue 9 審查 M-3；使用者裁定併入 Issue 10）。
// 執行方式與慣例比照 check_foliate_es_compat.js（純 Node 內建模組、免 npm install）。
//
// 用法：
//   node app/tool/check_l10n_hardcoded_strings.js                    # 兩項檢查
//   node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>   # 只做檢查 1（測試／驗收用）
//   node app/tool/check_l10n_hardcoded_strings.js --test-dir <目錄>  # 只做檢查 2
//   兩個旗標都給時兩項都做。
//
// 結束碼 0：乾淨；1：找到至少一處未包裝的硬編碼中文字串；
//        2：設定錯誤（--lib-dir 缺參數／目錄不存在／目錄內沒有任何可掃描的 .dart 檔），
//           此時不代表「乾淨」，避免把掃錯目錄誤當成通過。

const fs = require('fs');
const path = require('path');

// CJK Unified Ideographs（spec §9：U+4E00–U+9FFF）
const CJK = /[一-鿿]/;

// 「接收顯示文字」的具名參數（review-issue-10.md I-2）：
//   - 完整名稱：label／title／subtitle／text／tooltip／message／content／hint
//   - 自訂 Widget 常見的複合名稱：以 Label／Title／Text／Tooltip／Message／Hint／
//     Subtitle 結尾，且前一個字元是小寫或數字（deleteButtonLabel、hintText、
//     semanticsLabel…）。labelStyle／contentPadding／titleTextStyle 這類「非文字」
//     參數，以及 context 這種只是碰巧以 text 結尾的名稱，都不會被誤判。
// 名稱清單依 app/lib 內實際接收 l10n 字串的參數統計（tooltip／label／title／text／
// labelText／hintText／message／subtitle）；此規則對 app/lib 的假警報為 0。
const UI_PARAM_EXACT = new Set([
  'label', 'title', 'subtitle', 'text', 'tooltip', 'message', 'content', 'hint',
]);
const UI_PARAM_SUFFIX = /[a-z0-9](?:Label|Title|Text|Tooltip|Message|Hint|Subtitle)$/;

function isUiParamName(name) {
  return UI_PARAM_EXACT.has(name) || UI_PARAM_SUFFIX.test(name);
}

// 整檔略過（相對 app/lib，以 / 分隔）。每一項都要寫明理由。
const SKIP_FILES = new Map([
  ['reader/text_conversion_dict.dart', 'epic-42 簡繁轉換字典資料檔，全檔皆為刻意的中文資料'],
  ['library/models/book_group.dart', '系統保留分類 Sentinel（「未分類」／「未分类」），見 spec §6'],
]);

// 字面值本身就是專有名詞、不翻譯（design.md：內建字型品牌名）。
const ALLOWED_LITERAL_VALUES = new Set([
  '思源黑體', '思源宋體', '原俠正楷', '台灣圓體', '源流明體',
]);

// 行內例外標記：`// l10n-ignore: <理由>`，涵蓋標記所在行與下一行。
const IGNORE_MARKER = /\/\/\s*l10n-ignore:\s*\S/;

const BACKSLASH = String.fromCharCode(92);

/**
 * 掃描 Dart 原始碼，回傳字串字面值清單與「註解已被抹除」的程式碼副本。
 *
 * 之所以不用單純的正則剝除註解：本專案註解一律是中文（例如 `// Text('確定') 按鈕`），
 * 而字串內也可能出現 `//`（例如 'http://…'），必須「邊掃邊分辨目前在字串還是註解」，
 * 才不會把註解誤判為字串、或把 URL 後半段誤當成註解。
 * 字串插值 `${ ... }` 內可再出現同種引號的巢狀字串，也在此一併處理。
 */
function tokenize(src) {
  const literals = [];
  const ignoreLines = new Set();
  const code = src.split(''); // 註解會被空白抹除（保留換行以維持行號）
  const n = src.length;
  let line = 1;

  function blank(from, to) {
    for (let k = from; k < to; k++) if (code[k] !== '\n') code[k] = ' ';
  }

  // i 位於開頭引號；回傳結束引號之後的索引。會遞迴處理 ${ ... } 內的巢狀字串。
  function readString(i) {
    const quote = src[i];
    const isRaw = i > 0 && src[i - 1] === 'r' && !/\w/.test(src[i - 2] || ' ');
    const triple = src.startsWith(quote.repeat(3), i);
    const q = triple ? quote.repeat(3) : quote;
    const start = i;
    const startLine = line;
    i += q.length;
    while (i < n) {
      const c = src[i];
      if (!isRaw && c === BACKSLASH) {
        // 反斜線接續換行（三引號字串的續行）：被跳過的換行仍要計入行號
        if (src[i + 1] === '\n') line++;
        i += 2;
        continue;
      }
      if (src.startsWith(q, i)) { i += q.length; break; }
      if (c === '\n') { line++; if (!triple) break; }
      if (!isRaw && c === '$' && src[i + 1] === '{') {
        i += 2;
        let depth = 1;
        while (i < n && depth > 0) {
          const d = src[i];
          if (d === '\n') line++;
          if (d === "'" || d === '"') { i = readString(i); continue; }
          if (d === '{') depth++;
          else if (d === '}') depth--;
          i++;
        }
        continue;
      }
      i++;
    }
    literals.push({ start, end: i, line: startLine, raw: src.slice(start, i) });
    return i;
  }

  let i = 0;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (c === '\n') { line++; i++; continue; }
    if (c === '/' && c2 === '/') {
      const s = i;
      while (i < n && src[i] !== '\n') i++;
      if (IGNORE_MARKER.test(src.slice(s, i))) { ignoreLines.add(line); ignoreLines.add(line + 1); }
      blank(s, i);
      continue;
    }
    if (c === '/' && c2 === '*') {
      const s = i;
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src[i] === '\n') line++;
        if (src[i] === '/' && src[i + 1] === '*') { depth++; i += 2; }
        else if (src[i] === '*' && src[i + 1] === '/') { depth--; i += 2; }
        else i++;
      }
      blank(s, i);
      continue;
    }
    if (c === "'" || c === '"') { i = readString(i); continue; }
    i++;
  }
  literals.sort((a, b) => a.start - b.start);
  return { literals, code: code.join(''), ignoreLines };
}

/** 字面值去掉引號後的內容（含三引號；raw 從引號起算，原始字串的 r 前綴不在其中）。 */
function innerText(raw) {
  const m = raw.match(/^('''|"""|'|")/);
  const q = m ? m[1] : '';
  return raw.slice(m ? m[0].length : 0, raw.length - (raw.endsWith(q) ? q.length : 0));
}

/**
 * 把每個最外層字串字面值的內容換成占位字元（保留引號與換行），
 * 讓後續的括號／逗號掃描不會被字串內容干擾（例如 'a, b'、'a)'）。
 */
function maskStrings(code, literals) {
  const out = code.split('');
  let coveredTo = -1;
  for (const lit of literals) {
    if (lit.start < coveredTo) continue; // 插值內的巢狀字面值已被外層涵蓋
    for (let k = lit.start + 1; k < lit.end - 1; k++) if (out[k] !== '\n') out[k] = '_';
    coveredTo = lit.end;
  }
  return out.join('');
}

/**
 * 位於 litStart 的字面值，是否落在 Widget 字串參數的「參數運算式」內？
 *
 * 從字面值往回掃到本參數的起點（同一層的 `,`／`;`，或尚未配對的 `(`／`[`／`{`），
 * 取起點到字面值之間的文字 argText，再判斷：
 *   - 具名參數：argText 以 `<UI 參數名>:` 開頭，例如 `label: c ? l10n.a : `、`title: 'a' + `
 *   - `Text(`／`SelectableText(` 的第一個位置參數：參數起點之前緊接 `Text(`
 * 因此三元運算式、字串串接、相鄰字串串接內的字面值都算在內（review-issue-10.md I-1）；
 * 巢狀呼叫的引數（`label: bar('中')`）、函式主體、相鄰的其他參數則不算。
 * argText 含 `??` 視為刻意的 fallback 逃逸口（例如 eb_sheet_shell 無 AppLocalizations
 * 時的「關閉」），不判定為違規。
 */
function inUiArgument(masked, litStart) {
  let depth = 0;
  let argStart = 0;
  for (let k = litStart - 1; k >= 0; k--) {
    const ch = masked[k];
    if (ch === ')' || ch === ']' || ch === '}') {
      depth++;
    } else if (ch === '(' || ch === '[' || ch === '{') {
      if (depth === 0) { argStart = k + 1; break; }
      depth--;
    } else if ((ch === ',' || ch === ';') && depth === 0) {
      argStart = k + 1;
      break;
    }
  }
  const argText = masked.slice(argStart, litStart);
  if (argText.includes('??')) return false;
  const named = argText.match(/^\s*(\w+)\s*:/);
  if (named) return isUiParamName(named[1]);
  return /\b(?:Text|SelectableText)\s*\(\s*$/.test(masked.slice(Math.max(0, argStart - 40), argStart));
}

/**
 * 找出一份 Dart 原始碼中的違規：Widget 字串參數位置、含中文、未被例外。
 * @returns {{line:number, text:string}[]}
 */
function findViolations(src) {
  const { literals, code, ignoreLines } = tokenize(src);
  const masked = maskStrings(code, literals);
  const violations = [];
  let coveredTo = -1;
  for (const lit of literals) {
    // 巢狀（插值內）字面值已被外層字面值涵蓋，不獨立判斷
    if (lit.start < coveredTo) continue;
    coveredTo = lit.end;
    if (!CJK.test(lit.raw)) continue;
    if (!inUiArgument(masked, lit.start)) continue;
    if (ALLOWED_LITERAL_VALUES.has(innerText(lit.raw))) continue;
    if (ignoreLines.has(lit.line)) continue;
    violations.push({ line: lit.line, text: lit.raw.replace(/\s+/g, ' ').slice(0, 60) });
  }
  return violations;
}

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
}

/**
 * 掃描整個 lib 目錄。
 * @returns {{scanned:number, violations:{file:string, line:number, text:string}[]}}
 *   scanned 只計實際掃描的檔案（l10n/ 與 SKIP_FILES 不算）；
 *   violations.file 為相對 libDir、以 / 分隔的路徑。
 */
function scanLibDir(libDir) {
  const files = [];
  walk(libDir, files);
  const violations = [];
  let scanned = 0;
  for (const file of files) {
    const rel = path.relative(libDir, file).split(path.sep).join('/');
    if (rel.startsWith('l10n/')) continue; // gen-l10n 產生檔與 ARB 字典本身
    if (SKIP_FILES.has(rel)) continue;
    scanned++;
    for (const v of findViolations(fs.readFileSync(file, 'utf8'))) {
      violations.push({ file: rel, ...v });
    }
  }
  return { scanned, violations };
}

// ---- 測試端：MaterialApp 必須帶 locale／localizationsDelegates／supportedLocales ----
//
// Issue 9 審查 M-3：`app/test/` 內的 MaterialApp 若缺 `locale:`，flutter_test 預設為 en_US，
// 日後若有人在該測試加中文斷言會靜默失敗；缺 localizationsDelegates／supportedLocales 則會在
// `AppLocalizations.of(context)!` 觸發 Null check 崩潰。

const TEST_APP_REQUIRED_ARGS = ['locale', 'localizationsDelegates', 'supportedLocales'];

// 允許「缺參數」的測試檔（相對 app/test，以 / 分隔），以「檔案＋數量」放行：
// 數量不符（多出未經審視的裸 MaterialApp，或白名單案例已被移除）一律報警。
const TEST_BARE_APP_ALLOW = new Map([
  ['screens/widgets/eb_sheet_shell_test.dart', {
    count: 1,
    reason: '刻意保留裸 MaterialApp，驗證無 AppLocalizations 時 tooltip 回退為固定字面值「關閉」',
  }],
]);

/** 取出 open～close 括號之間「最外層」具名參數的名稱（巢狀 Widget 內的同名參數不算）。 */
function topLevelArgNames(masked, open, close) {
  const names = new Set();
  let depth = 0;
  let segStart = open + 1;
  const flush = (end) => {
    const m = masked.slice(segStart, end).match(/^\s*(\w+)\s*:/);
    if (m) names.add(m[1]);
  };
  for (let k = open + 1; k < close; k++) {
    const ch = masked[k];
    if (ch === '(' || ch === '[' || ch === '{') depth++;
    else if (ch === ')' || ch === ']' || ch === '}') depth--;
    else if (ch === ',' && depth === 0) { flush(k); segStart = k + 1; }
  }
  flush(close);
  return names;
}

/**
 * 找出一份 Dart 測試原始碼中缺少必要參數的 `MaterialApp(`／`MaterialApp.router(` 呼叫。
 * 與字串稽核共用同一套 tokenizer：註解與字串內容已被抹除，不會被註解／字串內的
 * `MaterialApp(` 字樣或括號干擾。
 * @returns {{line:number, missing:string[]}[]}
 */
function findBareMaterialApps(src) {
  const { literals, code } = tokenize(src);
  const masked = maskStrings(code, literals);
  const found = [];
  const re = /\bMaterialApp(?:\.router)?\s*\(/g;
  let m;
  while ((m = re.exec(masked)) !== null) {
    const open = m.index + m[0].length - 1;
    let depth = 0;
    let close = -1;
    for (let k = open; k < masked.length; k++) {
      if (masked[k] === '(') depth++;
      else if (masked[k] === ')') { depth--; if (depth === 0) { close = k; break; } }
    }
    if (close < 0) continue;
    const names = topLevelArgNames(masked, open, close);
    const missing = TEST_APP_REQUIRED_ARGS.filter((k) => !names.has(k));
    if (missing.length === 0) continue;
    found.push({ line: masked.slice(0, m.index).split('\n').length, missing });
  }
  return found;
}

/**
 * 掃描整個 test 目錄。
 * @returns {{scanned:number, violations:{file:string, line:number, missing:string[], note?:string}[]}}
 */
function scanTestDir(testDir) {
  const files = [];
  walk(testDir, files);
  const violations = [];
  let scanned = 0;
  for (const file of files) {
    const rel = path.relative(testDir, file).split(path.sep).join('/');
    scanned++;
    const bare = findBareMaterialApps(fs.readFileSync(file, 'utf8'));
    const allow = TEST_BARE_APP_ALLOW.get(rel);
    if (allow) {
      if (bare.length !== allow.count) {
        violations.push({
          file: rel,
          line: bare.length > 0 ? bare[0].line : 1,
          missing: [],
          note: `白名單預期恰好 ${allow.count} 個缺參數的 MaterialApp（${allow.reason}），實際 ${bare.length} 個`,
        });
      }
      continue;
    }
    for (const b of bare) violations.push({ file: rel, ...b });
  }
  return { scanned, violations };
}

// ---- CLI ----

/** 解析 `--xxx-dir <目錄>`：未給旗標回傳 undefined；缺參數回傳 null（已印出錯誤）。 */
function parseDirOption(argv, flag) {
  const i = argv.indexOf(flag);
  if (i < 0) return undefined;
  const value = argv[i + 1];
  if (!value || value.startsWith('--')) {
    console.error(`${flag} 需要指定要掃描的目錄`);
    return null;
  }
  return path.resolve(value);
}

function isDirectory(dir) {
  return fs.existsSync(dir) && fs.statSync(dir).isDirectory();
}

function checkLib(libDir) {
  if (!isDirectory(libDir)) {
    console.error(`掃描目錄不存在：${libDir}`);
    return 2;
  }
  const { scanned, violations } = scanLibDir(libDir);
  if (scanned === 0) {
    // 掃 0 個檔案不可回報 PASS，否則指錯目錄會被誤當成乾淨
    console.error(`在 ${libDir} 底下沒有找到任何 .dart 檔（l10n/ 與略過清單不計），無法稽核`);
    return 2;
  }
  if (violations.length === 0) {
    console.log(`PASS：掃描 ${scanned} 個檔案，未發現未經 AppLocalizations 包裝的硬編碼中文字串`);
    return 0;
  }
  console.error(`發現 ${violations.length} 處未經 AppLocalizations 包裝的硬編碼中文字串：`);
  for (const r of violations) console.error(`  lib/${r.file}:${r.line}  ${r.text}`);
  console.error('\n修法：改用 AppLocalizations（ARB key）；若確屬合法例外，於該行或上一行加 `// l10n-ignore: <理由>`。');
  return 1;
}

function checkTest(testDir) {
  if (!isDirectory(testDir)) {
    console.error(`掃描目錄不存在：${testDir}`);
    return 2;
  }
  const { scanned, violations } = scanTestDir(testDir);
  if (scanned === 0) {
    console.error(`在 ${testDir} 底下沒有找到任何 .dart 檔，無法稽核`);
    return 2;
  }
  if (violations.length === 0) {
    console.log(`PASS：掃描 ${scanned} 個測試檔，所有 MaterialApp 皆帶 locale／localizationsDelegates／supportedLocales`);
    return 0;
  }
  console.error(`發現 ${violations.length} 處測試的 MaterialApp 缺少必要參數：`);
  for (const v of violations) {
    console.error(`  test/${v.file}:${v.line}  ${v.note ?? `缺少 ${v.missing.join('／')}`}`);
  }
  console.error('\n修法：改用 pumpLocalizedWidget()，或補上 locale: const Locale(\'zh\', \'TW\')／localizationsDelegates／supportedLocales；');
  console.error('若確屬刻意的裸 MaterialApp（例如驗證無 AppLocalizations 的 fallback），加進腳本的 TEST_BARE_APP_ALLOW 並註明理由。');
  return 1;
}

/**
 * 沒給任何 --xxx-dir 時，兩項檢查都以預設目錄執行；
 * 只給其中一個旗標時，只執行該項檢查（測試／驗收用）。
 */
function main(argv) {
  const libOpt = parseDirOption(argv, '--lib-dir');
  const testOpt = parseDirOption(argv, '--test-dir');
  if (libOpt === null || testOpt === null) return 2;
  const runLib = libOpt !== undefined || testOpt === undefined;
  const runTest = testOpt !== undefined || libOpt === undefined;
  let exit = 0;
  // 結束碼取最大值：2（設定錯誤）優先於 1（有違規）優先於 0
  if (runLib) exit = Math.max(exit, checkLib(libOpt ?? path.resolve(__dirname, '..', 'lib')));
  if (runTest) exit = Math.max(exit, checkTest(testOpt ?? path.resolve(__dirname, '..', 'test')));
  return exit;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findViolations, scanLibDir, findBareMaterialApps, scanTestDir };
