// epic-45-interface-i18n Issue 10：防遺漏稽核腳本。
//
// 掃描 app/lib/**/*.dart，找出「Widget 字串參數位置」上未經 AppLocalizations
// 包裝、含中文字元的字串字面值，避免既有畫面遺漏、以及日後新增畫面忘記包裝。
// 規則契約見 docs/epics/epic-45-interface-i18n/spec.md §9，
// 執行方式與慣例比照 check_foliate_es_compat.js（純 Node 內建模組、免 npm install）。
//
// 用法：
//   node app/tool/check_l10n_hardcoded_strings.js
//   node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>   # 測試／驗收用
//
// 結束碼 0：乾淨；1：找到至少一處未包裝的硬編碼中文字串。

const fs = require('fs');
const path = require('path');

// CJK Unified Ideographs（spec §9：U+4E00–U+9FFF）
const CJK = /[一-鿿]/;

// 「接收顯示文字」的具名參數。依 app/lib 內實際接收 l10n 字串的參數統計
// （tooltip／label／title／text／labelText／hintText／message／subtitle），
// 再補上 spec §9 列出的 content 與 Flutter 常見的同類參數。
const UI_KEYWORDS = [
  'tooltip', 'label', 'title', 'subtitle', 'text', 'labelText', 'hintText',
  'helperText', 'errorText', 'counterText', 'prefixText', 'suffixText',
  'content', 'message', 'semanticLabel', 'semanticsLabel',
];

// 「字串字面值緊接在這些位置之後」才視為 Widget 字串參數：
//   1. `<keyword>: [const] '...'`
//   2. `Text(` ／ `SelectableText(` 的第一個位置參數
// 結尾的 `r?` 是 Dart 原始字串前綴：字面值的起點是引號本身，前綴 `r` 會留在
// 「引號之前的程式碼」尾端，若不在此放行，`Text(r'中文')` 會整個逃逸稽核。
const UI_POSITION = new RegExp(
  '(?:\\b(?:' + UI_KEYWORDS.join('|') + ')\\s*:\\s*(?:const\\s+)?r?' +
    '|\\b(?:Text|SelectableText)\\s*\\(\\s*(?:const\\s+)?r?)$',
);

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
      if (!isRaw && c === BACKSLASH) { i += 2; continue; }
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

/** 字面值去掉引號後的內容（含 r 前綴與三引號）。 */
function innerText(raw) {
  const m = raw.match(/^r?('''|"""|'|")/);
  const q = m ? m[1] : '';
  return raw.slice(m ? m[0].length : 0, raw.length - (raw.endsWith(q) ? q.length : 0));
}

/**
 * 找出一份 Dart 原始碼中的違規：Widget 字串參數位置、含中文、未被例外。
 * @returns {{line:number, text:string}[]}
 */
function findViolations(src) {
  const { literals, code, ignoreLines } = tokenize(src);
  const violations = [];
  let prev = null; // 前一個字面值（相鄰字串串接時沿用其位置判斷）
  let prevPositional = false;
  for (const lit of literals) {
    // 巢狀（插值內）字面值已被外層字面值涵蓋，不獨立判斷
    if (prev && lit.start < prev.end) continue;
    const before = code.slice(Math.max(0, lit.start - 200), lit.start);
    let inUiPosition = UI_POSITION.test(before);
    // Dart 相鄰字串串接：'a' 'b中'，後段沿用前段的位置
    if (!inUiPosition && prev && /^\s*$/.test(code.slice(prev.end, lit.start))) {
      inUiPosition = prevPositional;
    }
    prev = lit;
    prevPositional = inUiPosition;
    if (!inUiPosition || !CJK.test(lit.raw)) continue;
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

/** 掃描整個 lib 目錄，回傳 {file, line, text}[]（file 為相對 libDir、以 / 分隔）。 */
function scanLibDir(libDir) {
  const files = [];
  walk(libDir, files);
  const results = [];
  for (const file of files) {
    const rel = path.relative(libDir, file).split(path.sep).join('/');
    if (rel.startsWith('l10n/')) continue; // gen-l10n 產生檔與 ARB 字典本身
    if (SKIP_FILES.has(rel)) continue;
    for (const v of findViolations(fs.readFileSync(file, 'utf8'))) {
      results.push({ file: rel, ...v });
    }
  }
  return results;
}

function main(argv) {
  const i = argv.indexOf('--lib-dir');
  const libDir = i >= 0 ? path.resolve(argv[i + 1]) : path.resolve(__dirname, '..', 'lib');
  const results = scanLibDir(libDir);
  if (results.length === 0) {
    console.log('PASS：未發現未經 AppLocalizations 包裝的硬編碼中文字串');
    return 0;
  }
  console.error(`發現 ${results.length} 處未經 AppLocalizations 包裝的硬編碼中文字串：`);
  for (const r of results) console.error(`  lib/${r.file}:${r.line}  ${r.text}`);
  console.error('\n修法：改用 AppLocalizations（ARB key）；若確屬合法例外，於該行或上一行加 `// l10n-ignore: <理由>`。');
  return 1;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findViolations, scanLibDir };
