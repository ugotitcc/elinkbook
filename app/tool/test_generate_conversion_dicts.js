#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const { parseCharTable } = require('./generate_conversion_dicts.js');

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
  // epubcfi.js:266 `const { length } = n.nodeValue`），這種配對會讓
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

testBasicOneToOneMapping();
testMultiCandidateTakesFirst();
testCommentAndEmptyLinesSkipped();
testMultiCharacterCandidateThrows();
testMultiCharacterKeyThrows();
testBmpToSipPairSkipped();
testSipToBmpPairSkipped();

console.log('[test_generate_conversion_dicts] 7 項情境全數通過。');
