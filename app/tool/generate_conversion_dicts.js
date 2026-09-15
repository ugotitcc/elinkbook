#!/usr/bin/env node
/**
 * 從 OpenCC 原始字元對照表（app/tool/opencc_data/STCharacters.txt／
 * TSCharacters.txt，Apache-2.0）產生 JS（WebView）與 Dart（Flutter）
 * 兩份同源查找表，供 epic-42-text-conversion 使用。
 *
 * 背景（ADR 0030／ADR 0031）：簡繁轉換定案為逐字元 1:1 轉換，不做詞彙/
 * 慣用詞轉換——每一組字典項的 key／value 皆必須恆為單一字元，這是保護
 * CFI 座標系不受轉換影響（ΔL=0）的前提。OpenCC 原始表的右欄可能有多個
 * 以半形空格分隔的候選字（例如簡化字「后」對應「後」與「后」兩個繁體字），
 * 本腳本只取第一個候選字。長度防護分兩層：(1) code point 數必須為 1，
 * 不滿足直接拋例外中止（防多字詞條誤入）；(2) UTF-16 `.length` 必須相等，
 * 不滿足則跳過該筆不列入字典（防 BMP↔輔助平面代理對配對打破 epubcfi.js
 * 賴以計算 Range offset 的 UTF-16 長度，見 parseCharTable() 內詳細說明）。
 *
 * 用法：node app/tool/generate_conversion_dicts.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const DATA_DIR = path.join(REPO_ROOT, 'app', 'tool', 'opencc_data');
const S2T_INPUT = path.join(DATA_DIR, 'STCharacters.txt');
const T2S_INPUT = path.join(DATA_DIR, 'TSCharacters.txt');
const JS_OUTPUT = path.join(
  REPO_ROOT,
  'app', 'android', 'app', 'src', 'main', 'assets', 'foliate',
  'text_conversion_dict.js',
);
const DART_OUTPUT = path.join(
  REPO_ROOT, 'app', 'lib', 'reader', 'text_conversion_dict.dart',
);

const GENERATED_FILE_HEADER =
  '// GENERATED FILE — 由 app/tool/generate_conversion_dicts.js 產生，' +
  '請勿手動編輯。\n' +
  '// 資料來源：BYVoid/OpenCC（Apache-2.0），見 ' +
  'app/tool/opencc_data/README.md。\n';

/**
 * 解析 OpenCC 字元對照表（TSV：key\tvalue1 value2 ...，'#' 開頭為註解行）。
 * 右欄若有多個以半形空格分隔的候選字，只取第一個。
 *
 * 兩層長度防護（審查修正 C-1）：
 * 1. **Code point 數必須為 1**（用 `Array.from(str).length` 判斷）：防止
 *    多字詞條（例如異常資料列右欄整串詞彙而非單字）誤入字典，不符合直接
 *    拋例外中止生成——這類異常視為資料格式錯誤，不應該靜默處理。
 * 2. **UTF-16 `.length`（code unit 數）必須相等**：`Array.from().length`
 *    算的是 Unicode code point，但 `epubcfi.js` 的 Range offset 計算
 *    （`epubcfi.js:266`：`const { length } = n.nodeValue`）用的是原生
 *    JS 字串 `.length`，即 UTF-16 code unit 數。OpenCC 原始表中存在
 *    BMP（`.length===1`）↔ 輔助平面/SIP 代理對字元（`.length===2`）的
 *    配對，兩者 code point 數都是 1、會通過第 1 層防護，但 UTF-16
 *    `.length` 不同，若進入字典會讓 DOM 文字節點轉換後長度改變，打破
 *    ADR 0030 的 ΔL=0 前提。這類配對**跳過（`continue`）不列入字典**
 *    （而非拋例外中止）——因為這是真實資料中會出現的合法字元、只是
 *    不適合本專案的轉換機制，跳過後這些字元在 `convertText()` 維持
 *    原樣（查找表找不到的既有 fallback 行為），而非讓整個生成腳本
 *    對真實 OpenCC 檔案無法執行完畢。
 * @param {string} tsvContent
 * @returns {Record<string, string>}
 */
function parseCharTable(tsvContent) {
  const dict = {};
  const lines = tsvContent.split('\n');
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const tabIndex = line.indexOf('\t');
    if (tabIndex < 0) continue;
    const key = line.slice(0, tabIndex);
    const candidates = line.slice(tabIndex + 1).trim();
    if (!key || !candidates) continue;
    const value = candidates.split(' ')[0];
    const keyCodepoints = Array.from(key).length;
    const valueCodepoints = Array.from(value).length;
    if (keyCodepoints !== 1 || valueCodepoints !== 1) {
      throw new Error(
        `字典項 code point 數不為 1：` +
        `"${key}"(${keyCodepoints}) -> "${value}"(${valueCodepoints})，` +
        `原始行：${rawLine}`,
      );
    }
    // UTF-16 code unit 數不相等（BMP ↔ 輔助平面配對）：跳過，不進字典。
    if (key.length !== value.length) continue;
    dict[key] = value;
  }
  return dict;
}

/** 產生 JS 物件字面量／Dart Map 字面量共用的字串（單字元字串在兩種語言
 * 語法下皆合法，JSON.stringify 的雙引號跳脫規則與 JS/Dart 字串字面量
 * 相容），確保雙端輸出永遠來自同一份格式化邏輯，不會各自實作漂移。 */
function toMapLiteral(dict) {
  const entries = Object.entries(dict)
    .map(([k, v]) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)},`)
    .join('\n');
  return `{\n${entries}\n}`;
}

function main() {
  const s2tSource = fs.readFileSync(S2T_INPUT, 'utf8');
  const t2sSource = fs.readFileSync(T2S_INPUT, 'utf8');

  const s2tDict = parseCharTable(s2tSource);
  const t2sDict = parseCharTable(t2sSource);

  const jsContent =
    GENERATED_FILE_HEADER +
    `export const s2tDict = ${toMapLiteral(s2tDict)};\n\n` +
    `export const t2sDict = ${toMapLiteral(t2sDict)};\n`;
  fs.writeFileSync(JS_OUTPUT, jsContent, 'utf8');

  const dartContent =
    GENERATED_FILE_HEADER +
    // 審查修正 M-3：巨大的靜態常數 Map 字面量會稀釋覆蓋率報告，標記
    // 排除在覆蓋率統計外（JS 端沒有對應的覆蓋率工具慣例，故只加在此處）。
    '// coverage:ignore-file\n' +
    '\n' +
    `const Map<String, String> kS2tDict = ${toMapLiteral(s2tDict)};\n\n` +
    `const Map<String, String> kT2sDict = ${toMapLiteral(t2sDict)};\n`;
  fs.writeFileSync(DART_OUTPUT, dartContent, 'utf8');

  console.log(
    `[generate_conversion_dicts] 完成：s2t ${Object.keys(s2tDict).length} ` +
    `筆、t2s ${Object.keys(t2sDict).length} 筆。`,
  );
}

module.exports = { parseCharTable, toMapLiteral };

if (require.main === module) {
  main();
}
