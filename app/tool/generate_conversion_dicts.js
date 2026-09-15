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
 * 解析 OpenCC 字典表（TSV：key\tvalue1 value2 ...，'#' 開頭為註解行），
 * 不限字元數，右欄若有多個以半形空格分隔的候選字，只取第一個。片語表
 * （TWPhrases.txt／TSPhrases.txt）與字元表（STCharacters.txt／
 * TSCharacters.txt）共用同一套基礎解析規則——parseCharTable() 的長度
 * 限制／BMP↔輔助平面過濾是疊加在這個共用邏輯之上的額外約束（見下）。
 *
 * 同一鍵不得重複、值不得為空字串（`issues.md` 明訂的正規化約束，審查
 * 修正 I-3）——上游 OpenCC 資料若出現格式異常或鍵值衝突，直接拋例外
 * 中止生成，不靜默覆蓋/跳過（已用實際下載的 TWPhrases.txt／TSPhrases.txt
 * 與既有 STCharacters.txt／TSCharacters.txt 驗證過皆無重複鍵，此防護
 * 不影響既有生成流程）。
 * @param {string} tsvContent
 * @returns {Record<string, string>}
 */
function parsePhraseTable(tsvContent) {
  const dict = {};
  const lines = tsvContent.split('\n');
  for (const rawLine of lines) {
    // 審查修正 I-3 複審發現的邏輯短路：不可先對整行 rawLine.trim() 再找
    // tab 位置——'內存\t'.trim() 會把結尾的 '\t' 一併削掉（tab 是
    // trim() 認定的空白字元），導致值為空的行被誤判成「找不到 tab」而
    // 提前 continue，永遠到不了下面的空值拋例外檢查。改為：只用
    // rawLine（未 trim）找 tab 位置，trim 動作限定在切出來的 key／
    // candidates 各自身上。
    const trimmedForBlankCheck = rawLine.trim();
    if (!trimmedForBlankCheck || trimmedForBlankCheck.startsWith('#')) {
      continue;
    }
    const tabIndex = rawLine.indexOf('\t');
    if (tabIndex < 0) continue;
    const key = rawLine.slice(0, tabIndex).trim();
    if (!key) continue;
    const candidates = rawLine.slice(tabIndex + 1).trim();
    const value = candidates ? candidates.split(' ')[0] : '';
    if (!value) {
      throw new Error(`片語字典值為空字串："${key}"，原始行：${rawLine}`);
    }
    if (Object.prototype.hasOwnProperty.call(dict, key)) {
      throw new Error(
        `片語字典鍵重複："${key}"（舊值 "${dict[key]}" vs 新值 "${value}"）`,
      );
    }
    dict[key] = value;
  }
  return dict;
}

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
 *    （搜尋 `const { length } = n.nodeValue`；行號會隨釘定版本升級漂移，
 *    不在此寫死）用的是原生 JS 字串 `.length`，即 UTF-16 code unit 數。
 *    OpenCC 原始表中存在 BMP（`.length===1`）↔ 輔助平面/SIP 代理對字元
 *    （`.length===2`）的配對，兩者 code point 數都是 1、會通過第 1 層防護，
 *    但 UTF-16 `.length` 不同，若進入字典會讓 DOM 文字節點轉換後長度改變，打破
 *    ADR 0030 的 ΔL=0 前提。這類配對**跳過（`continue`）不列入字典**
 *    （而非拋例外中止）——因為這是真實資料中會出現的合法字元、只是
 *    不適合本專案的轉換機制，跳過後這些字元在 `convertText()` 維持
 *    原樣（查找表找不到的既有 fallback 行為），而非讓整個生成腳本
 *    對真實 OpenCC 檔案無法執行完畢。
 * @param {string} tsvContent
 * @returns {Record<string, string>}
 */
function parseCharTable(tsvContent) {
  const raw = parsePhraseTable(tsvContent);
  const dict = {};
  for (const [key, value] of Object.entries(raw)) {
    const keyCodepoints = Array.from(key).length;
    const valueCodepoints = Array.from(value).length;
    if (keyCodepoints !== 1 || valueCodepoints !== 1) {
      throw new Error(
        `字典項 code point 數不為 1：` +
        `"${key}"(${keyCodepoints}) -> "${value}"(${valueCodepoints})`,
      );
    }
    // UTF-16 code unit 數不相等（BMP ↔ 輔助平面配對）：跳過，不進字典。
    if (key.length !== value.length) continue;
    dict[key] = value;
  }
  return dict;
}

// 片語比對時，單一詞條 code point 數的安全上限——必須與
// app/lib/reader/text_conversion.dart 的 kMaxPhraseKeyLength、
// app/android/app/src/main/assets/foliate/text-conversion.js 的
// MAX_PHRASE_KEY_LENGTH 保持一致，三處數值目前皆為 16。
const MAX_PHRASE_KEY_LENGTH = 16;

/**
 * 確保 dict 內每一個鍵的 code point 數不超過 MAX_PHRASE_KEY_LENGTH——
 * 執行期演算法的最長匹配只會嘗試到這個長度，超過的詞條會被靜默漏未
 * 比對，必須在生成階段擋下來（見上方常數說明）。
 * @param {Record<string,string>} dict
 * @param {string} label
 */
function assertMaxPhraseKeyLength(dict, label) {
  for (const key of Object.keys(dict)) {
    const len = Array.from(key).length;
    if (len > MAX_PHRASE_KEY_LENGTH) {
      throw new Error(
        `${label} 詞條 "${key}" 長度 ${len} 超過 MAX_PHRASE_KEY_LENGTH=` +
        `${MAX_PHRASE_KEY_LENGTH}，需同步調高 text_conversion.dart 的 ` +
        'kMaxPhraseKeyLength 與 text-conversion.js 的 MAX_PHRASE_KEY_LENGTH。',
      );
    }
  }
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

module.exports = {
  parseCharTable,
  parsePhraseTable,
  toMapLiteral,
  assertMaxPhraseKeyLength,
};

if (require.main === module) {
  main();
}
