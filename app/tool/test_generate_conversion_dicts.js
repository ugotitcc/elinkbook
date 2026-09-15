#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const { parseCharTable, parsePhraseTable, assertMaxPhraseKeyLength } =
  require('./generate_conversion_dicts.js');

function testBasicOneToOneMapping() {
  const result = parseCharTable('国\t國\n电\t電\n');
  assert.deepEqual(result, { 国: '國', 电: '電' });
}

function testMultiCandidateTakesFirst() {
  // 真實 OpenCC STCharacters.txt 資料（2026-09-15 查證）：
  // 后\t後 后    （簡化字「后」合併了「後」與「后」兩個繁體字）
  // 干\t幹 乾 干 榦（「幹」「乾」「干」「榦」皆簡化為「干」）
  const result = parseCharTable('后\t後 后\n干\t幹 乾 干 榦\n');
  assert.deepEqual(result, { 后: '後', 干: '幹' });
}

function testCommentAndEmptyLinesSkipped() {
  const input = [
    '# Open Chinese Convert (OpenCC) Dictionary',
    '# File: STCharacters.txt',
    '',
    '国\t國',
    '',
  ].join('\n');
  const result = parseCharTable(input);
  assert.deepEqual(result, { 国: '國' });
}

function testMultiCharacterCandidateThrows() {
  assert.throws(
    () => parseCharTable('坏\t異常值\n'),
    /字典項 code point 數不為 1/,
  );
}

function testMultiCharacterKeyThrows() {
  assert.throws(
    () => parseCharTable('異常鍵\t值\n'),
    /字典項 code point 數不為 1/,
  );
}

function testBmpToSipPairSkipped() {
  // 審查修正 C-1：Array.from().length 算的是 Unicode code point，對
  // BMP（UTF-16 長度 1）↔ 輔助平面/SIP（代理對，UTF-16 長度 2）字元對
  // 兩邊都算「1 個 code point」會被誤判為合法——但 epubcfi.js 的 Range
  // offset 計算用的是原生 String.length（UTF-16 code unit 數，見
  // epubcfi.js 的 `const { length } = n.nodeValue`；行號會隨釘定版本
  // 升級漂移，不在此寫死），這種配對會讓
  // node.nodeValue.length 在轉換後改變，打破 ADR 0030 的 ΔL=0。
  // 㓆（U+34C6，BMP，length===1）-> 𠗣（U+205E3，輔助平面，代理對，
  // length===2）：code point 數皆為 1，但 UTF-16 長度不同，應被跳過。
  const result = parseCharTable('㓆\t𠗣\n国\t國\n');
  assert.deepEqual(result, { 国: '國' });
}

function testSipToBmpPairSkipped() {
  // 同上，反方向（key 為輔助平面、value 為 BMP）同樣應被跳過。
  const result = parseCharTable('𠗣\t㓆\n国\t國\n');
  assert.deepEqual(result, { 国: '國' });
}

function testParsePhraseTableAllowsMultiCharKeyValue() {
  const result = parsePhraseTable('內存\t記憶體\n');
  assert.deepEqual(result, { 內存: '記憶體' });
}

function testParsePhraseTableTakesFirstCandidate() {
  // 真實 OpenCC TWPhrases.txt 資料：代碼\t程式碼 代碼（多候選字，取首個）。
  const result = parsePhraseTable('代碼\t程式碼 代碼\n');
  assert.deepEqual(result, { 代碼: '程式碼' });
}

function testParsePhraseTableCommentAndEmptyLinesSkipped() {
  const input = [
    '# Open Chinese Convert (OpenCC) Dictionary',
    '# File: TWPhrases.txt',
    '',
    '內存\t記憶體',
    '',
  ].join('\n');
  const result = parsePhraseTable(input);
  assert.deepEqual(result, { 內存: '記憶體' });
}

function testParsePhraseTableAllowsSingleCharEntry() {
  // TWPhrases.txt 實際含 12 條單字詞條（如「硅\t矽」）：parsePhraseTable
  // 不像 parseCharTable 那樣限制長度必須為 1，但也不排斥單字元鍵值——
  // 片語字典裡的單字詞條照樣要能正確解析。
  const result = parsePhraseTable('硅\t矽\n');
  assert.deepEqual(result, { 硅: '矽' });
}

function testParsePhraseTableAllowsLengthChangingEntry() {
  // 片語表跟字元表不同，長度本來就可能改變（TextOffsetMap 存在的理由），
  // parsePhraseTable 不應該對長度做任何檢查或跳過。
  const result = parsePhraseTable('內存\t記憶體\n方便麵\t泡麵\n');
  assert.deepEqual(result, { 內存: '記憶體', 方便麵: '泡麵' });
}

function testAssertMaxPhraseKeyLengthPassesUnderLimit() {
  assertMaxPhraseKeyLength({ 內存: '記憶體' }, 'TestDict');
  // 未拋例外即為通過。
}

function testAssertMaxPhraseKeyLengthThrowsOverLimit() {
  const longKey = '一'.repeat(17);
  assert.throws(
    () => assertMaxPhraseKeyLength({ [longKey]: '二' }, 'TestDict'),
    /超過 MAX_PHRASE_KEY_LENGTH/,
  );
}

function testParsePhraseTableThrowsOnDuplicateKey() {
  // 審查修正 I-3：issues.md 明訂「同一鍵不得重複」，靜默覆蓋會隱蔽上游
  // 資料的格式異常或鍵值衝突。
  assert.throws(
    () => parsePhraseTable('內存\t記憶體\n內存\t記憶體模組\n'),
    /片語字典鍵重複/,
  );
}

function testParsePhraseTableThrowsOnEmptyValue() {
  // 審查修正 I-3：issues.md 明訂「值不得為空字串」。
  assert.throws(
    () => parsePhraseTable('內存\t\n'),
    /片語字典值為空字串/,
  );
}

testBasicOneToOneMapping();
testMultiCandidateTakesFirst();
testCommentAndEmptyLinesSkipped();
testMultiCharacterCandidateThrows();
testMultiCharacterKeyThrows();
testBmpToSipPairSkipped();
testSipToBmpPairSkipped();
testParsePhraseTableAllowsMultiCharKeyValue();
testParsePhraseTableTakesFirstCandidate();
testParsePhraseTableCommentAndEmptyLinesSkipped();
testParsePhraseTableAllowsSingleCharEntry();
testParsePhraseTableAllowsLengthChangingEntry();
testAssertMaxPhraseKeyLengthPassesUnderLimit();
testAssertMaxPhraseKeyLengthThrowsOverLimit();
testParsePhraseTableThrowsOnDuplicateKey();
testParsePhraseTableThrowsOnEmptyValue();

console.log('[test_generate_conversion_dicts] 16 項情境全數通過。');
