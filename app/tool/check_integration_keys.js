#!/usr/bin/env node
// epic-54 Issue 17：過期 key 守衛。
// integration_test/ 長期沒在真機執行，Epic 38 改了工具列 key 後，測試仍引用舊 key，
// 沒有任何機制發現。本腳本找出「integration 測試引用、但 lib/ 找不到」的 Key。
//
// 用法：node tool/check_integration_keys.js [--lib-dir <目錄>] [--integration-dir <目錄>]
// 結束碼：0 乾淨；1 有過期 key；2 設定錯誤或掃到 0 個檔案。

const fs = require('fs');
const path = require('path');

// 測試端：Key('x')／ValueKey('x')（單、雙引號皆可）
const KEY_RE = /(?:Value)?Key\(\s*(['"])([^'"\n]+)\1\s*\)/g;
// 測試檔自己建立的 widget：key: Key('x')
const SELF_KEY_RE = /\bkey:\s*(?:const\s+)?(?:Value)?Key\(\s*(['"])([^'"\n]+)\1\s*\)/g;
// lib 端的範本只從 Key 建構子取（含 $ 的字串）。不能對所有字串取範本：
// lib/ 內有大量 "$_temp0"、'${x}%'、'h${a}_n${b}' 這類與 Key 無關的字串，
// 轉成正規表示式會變成萬用（^.+$），讓守衛永遠 PASS。
const LIB_KEY_TEMPLATE_RE = /(?:Value)?Key\(\s*(['"])([^'"\n]*\$[^'"\n]*)\1\s*\)/g;
const PREFIX_RE = /keyPrefix:\s*(['"])([^'"\n]+)\1/g;
const STRING_RE = /'([^'\n]*)'|"([^"\n]*)"/g;
// 範本在第一個 $ 之前至少要有這麼多個固定字元，否則視為過寬而丟棄
const MIN_TEMPLATE_PREFIX = 4;

function collectDartFiles(dir, { skipDirs = [] } = {}) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (skipDirs.includes(entry.name)) continue;
      out.push(...collectDartFiles(full, { skipDirs }));
    } else if (entry.name.endsWith('.dart')) out.push(full);
  }
  return out;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// 把含 $ 的 Key 範本轉成正規表示式：${...} 與 $ident 皆視為 .+。
// 第一個 $ 之前的固定字元少於 MIN_TEMPLATE_PREFIX 個時回傳 null（太寬，不採用）。
function templateToRegExp(template) {
  const firstDollar = template.indexOf('$');
  if (firstDollar < MIN_TEMPLATE_PREFIX) return null;
  let pattern = '';
  let i = 0;
  while (i < template.length) {
    if (template[i] === '$') {
      if (template[i + 1] === '{') {
        const end = template.indexOf('}', i);
        i = end === -1 ? template.length : end + 1;
      } else {
        i += 1;
        while (i < template.length && /[A-Za-z0-9_]/.test(template[i])) i += 1;
      }
      pattern += '.+';
    } else {
      pattern += escapeRegExp(template[i]);
      i += 1;
    }
  }
  return new RegExp(`^${pattern}$`);
}

function buildLibIndex(libSources) {
  const literals = new Set();
  const templates = [];
  const prefixes = [];
  for (const src of libSources) {
    for (const m of src.matchAll(STRING_RE)) {
      const text = m[1] ?? m[2];
      if (text && !text.includes('$')) literals.add(text);
    }
    for (const m of src.matchAll(LIB_KEY_TEMPLATE_RE)) {
      const re = templateToRegExp(m[2]);
      if (re) templates.push(re);
    }
    for (const m of src.matchAll(PREFIX_RE)) prefixes.push(m[2]);
  }
  return { literals, templates, prefixes };
}

function isPresent(key, index, selfKeys) {
  if (selfKeys.has(key)) return true;
  if (index.literals.has(key)) return true;
  if (index.templates.some((re) => re.test(key))) return true;
  return index.prefixes.some((p) => key.startsWith(`${p}_`));
}

/**
 * @param {string[]} libSources lib/ 內各 .dart 檔的內容
 * @param {{file: string, src: string}[]} integrationFiles
 * @returns {{file: string, line: number, key: string}[]}
 */
function findStaleKeys(libSources, integrationFiles) {
  const index = buildLibIndex(libSources);
  const result = [];
  for (const { file, src } of integrationFiles) {
    const selfKeys = new Set([...src.matchAll(SELF_KEY_RE)].map((m) => m[2]));
    src.split('\n').forEach((text, i) => {
      for (const m of text.matchAll(KEY_RE)) {
        // 測試端含 $ 的 key（例如迴圈內的 Key('pdf_settings_$keySuffix')）無法靜態解析，跳過
        if (m[2].includes('$')) continue;
        if (!isPresent(m[2], index, selfKeys)) result.push({ file, line: i + 1, key: m[2] });
      }
    });
  }
  return result;
}

function parseArgs(argv) {
  const opts = {
    libDir: path.join(__dirname, '..', 'lib'),
    integrationDir: path.join(__dirname, '..', 'integration_test'),
  };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--lib-dir') opts.libDir = argv[++i];
    else if (argv[i] === '--integration-dir') opts.integrationDir = argv[++i];
    else return { error: `不認得的參數：${argv[i]}` };
  }
  return opts;
}

function main(argv) {
  const opts = parseArgs(argv);
  if (opts.error) {
    console.error(`錯誤：${opts.error}。可用參數：--lib-dir <目錄>、--integration-dir <目錄>。`);
    return 2;
  }
  // lib/l10n/ 是產生出來的多語系檔，只有翻譯字串，不含 Widget 的 Key
  const libFiles = collectDartFiles(opts.libDir, { skipDirs: ['l10n'] });
  const itFiles = collectDartFiles(opts.integrationDir);
  if (libFiles.length === 0 || itFiles.length === 0) {
    console.error(
      `錯誤：掃描範圍內沒有 .dart 檔（lib：${libFiles.length} 個、integration：${itFiles.length} 個）。` +
        '目錄可能指錯。請確認 --lib-dir／--integration-dir，或在 app/ 目錄下執行。',
    );
    return 2;
  }
  const stale = findStaleKeys(
    libFiles.map((f) => fs.readFileSync(f, 'utf8')),
    itFiles.map((f) => ({
      file: path.relative(path.join(opts.integrationDir, '..'), f).replace(/\\/g, '/'),
      src: fs.readFileSync(f, 'utf8'),
    })),
  );
  if (stale.length === 0) {
    console.log(`PASS：掃描 ${itFiles.length} 個 integration 測試檔，所有 Key 在 lib/ 都找得到對應`);
    return 0;
  }
  for (const v of stale) console.log(`${v.file}:${v.line}: lib/ 找不到 Key('${v.key}')`);
  console.error(
    `\nFAIL：${stale.length} 處 integration 測試引用的 Key 在 lib/ 已不存在。` +
      '請到 lib/ 找現行的對應 key（見 plans/plan-issue-17.md 的對照表），不要為了讓檢查通過而刪斷言。',
  );
  return 1;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findStaleKeys, collectDartFiles };
