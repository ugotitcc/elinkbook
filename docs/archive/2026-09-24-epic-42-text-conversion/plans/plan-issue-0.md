# Epic 42 Issue 0 — 前置修復＋雙端字典生成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 修復既有 `check_foliate_es_compat.js` 的常數引用漂移 bug，並從 OpenCC 原始字元表產生 JS（WebView）與 Dart（Flutter）兩份同源簡繁字元查找表，供後續 Issue 1-5 的 `TextConversionMode`／`convertText()` 消費。

**Architecture:** 一支純 Node.js 腳本（`app/tool/generate_conversion_dicts.js`，比照 `check_foliate_es_compat.js` 既有風格，無 npm 依賴）讀取 vendor 進版控的 OpenCC 原始 TSV 字元表，解析後輸出兩份格式不同但資料同源的查找表常數檔案：一份給 WebView 內的 `main.js`（ES module），一份給 Flutter Dart 端。`TextConversionMode` enum 與 `convertText()` 純函式是本 Epic 後續所有工單共用的核心型別/介面。

**Tech Stack:** Node.js（內建 `fs`/`path`/`node:assert`，無 npm 依賴）、Dart（`flutter_test`）。

**Spec:** `docs/epics/epic-42-text-conversion/spec.md`（另見 `docs/adr/0030-text-conversion-character-level-for-cfi-safety.md`、`docs/adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md`、`docs/epics/epic-42-text-conversion/issues.md` Issue 0）

## Global Constraints

- 逐字元 1:1 轉換，任何字典項的 key／value 皆恆為單一字元，不做多字元 pattern 比對或長度改變的替換（ADR 0030 決策 4，ΔL=0 是後續 Issue 2 CFI 安全性的前提，本 Issue 的字典生成邏輯是第一道防線）。
- 不 vendor `opencc-js` 套件本身；JS 與 Dart 兩端由**同一份**生成邏輯、同一份原始 OpenCC 資料獨立輸出各自格式的查找表（ADR 0031），不得手動維護兩份不同來源的字典。
- OpenCC 原始資料授權為 Apache-2.0，寬鬆授權可直接 vendor 進版控。
- JS 產出檔案不經 npm 建置，直接以生成腳本寫出純文字檔案複製進版控，比照 `readest/foliate-js` 既有 vendoring 慣例。
- `TextConversionMode`／`convertText()`／`kS2tDict`／`kT2sDict` 的型別與函式簽章是後續 Issue 1-5 直接依賴消費的介面，不得在本 Issue 完成後才隨意改名。

---

## File Structure

- Create: `app/tool/opencc_data/STCharacters.txt` — vendor 進版控的 OpenCC 簡體→繁體字元原始表（Apache-2.0）。
- Create: `app/tool/opencc_data/TSCharacters.txt` — vendor 進版控的 OpenCC 繁體→簡體字元原始表（Apache-2.0）。
- Create: `app/tool/opencc_data/README.md` — 記錄資料來源網址、授權、下載日期，供未來重新整理版本時查證。
- Create: `app/tool/generate_conversion_dicts.js` — 解析原始表、輸出 JS＋Dart 兩份查找表的生成腳本；匯出 `parseCharTable()` 供測試呼叫。
- Create: `app/tool/test_generate_conversion_dicts.js` — `parseCharTable()` 的 fixture 單元測試（Node 內建 `node:assert/strict`，比照 `test_section_progress_density.mjs` 風格）。
- Modify: `app/tool/check_foliate_es_compat.js` — 修正 `POLYFILL_SOURCE_FILE` 路徑與 `extractPolyfillSource()` 的常數名稱正則、錯誤訊息文字。
- Modify: `app/tool/README.md` — 同步修正文中對 `foliate_epub_reader_view.dart`／`_esCompatPolyfillJs` 的既有過時引用。
- Create: `app/android/app/src/main/assets/foliate/text_conversion_dict.js` — 生成腳本輸出的 JS 查找表（ES module，`export const s2tDict`／`t2sDict`）。
- Create: `app/lib/reader/text_conversion_dict.dart` — 生成腳本輸出的 Dart 查找表（`const Map<String, String> kS2tDict`／`kT2sDict`）。
- Create: `app/lib/reader/text_conversion_mode.dart` — `TextConversionMode` enum。
- Create: `app/lib/reader/text_conversion.dart` — `convertText()` 純函式。
- Create: `app/test/reader/text_conversion_test.dart` — `convertText()` 單元測試。

---

### Task 1: 修復 `check_foliate_es_compat.js` 既有常數引用漂移

**Files:**
- Modify: `app/tool/check_foliate_es_compat.js:3-6, 37-40, 195-209, 262-264, 274-278`
- Modify: `app/tool/README.md:5-11, 41`

**Interfaces:**
- Consumes: 無（純既有腳本的獨立 bugfix，不依賴本 Issue 其餘任務）。
- Produces: `check_foliate_es_compat.js` 可正常執行完畢並回傳結束碼 0，供後續 Task 4 新增 vendor 檔案（`text_conversion_dict.js`）時的 ES 相容性檢查使用（本 Issue 新增的檔案不含任何較新 ES 內建方法用法，跑這支腳本應仍是結束碼 0）。

- [x] **Step 1: 執行既有腳本，確認目前確實會拋出例外**

Run: `node app/tool/check_foliate_es_compat.js`
Expected: 拋出未捕捉例外並印出堆疊，訊息包含「在 foliate_reader_view.dart 找不到 _esCompatPolyfillJs 常數」。

- [x] **Step 2: 修正 `POLYFILL_SOURCE_FILE` 路徑**

編輯 `app/tool/check_foliate_es_compat.js` 第 37-40 行：

```javascript
const POLYFILL_SOURCE_FILE = path.join(
  REPO_ROOT,
  'app', 'lib', 'reader', 'foliate_native_bridge.dart',
);
```

- [x] **Step 3: 修正 `extractPolyfillSource()` 的正則與錯誤訊息**

編輯 `app/tool/check_foliate_es_compat.js` 第 195-209 行：

```javascript
function extractPolyfillSource(dartSource) {
  // esCompatPolyfillJs 是一個 Dart 三引號字串常數（'''...'''），直接抓
  // 這個常數宣告與它後面第一個 ''' 之間的內容，不需要完整解析 Dart 語法。
  const match = dartSource.match(
    /const esCompatPolyfillJs = '''([\s\S]*?)''';/,
  );
  if (!match) {
    throw new Error(
      '在 foliate_native_bridge.dart 找不到 esCompatPolyfillJs 常數' +
      '——是不是被改名或搬移了？請同步更新這支腳本的 POLYFILL_SOURCE_FILE' +
      '/extractPolyfillSource() 邏輯。',
    );
  }
  return match[1];
}
```

- [x] **Step 4: 修正檔案頂端文件註解與兩處錯誤提示訊息文字**

編輯 `app/tool/check_foliate_es_compat.js` 第 3-6 行文件註解：

```javascript
/**
 * 靜態掃描 app/android/app/src/main/assets/foliate/（readest/foliate-js
 * 釘定版本，見 ADR 0011「不修改釘定版本」）是否使用了較新的 ES 內建方法，
 * 而目前 lib/reader/foliate_native_bridge.dart 的 esCompatPolyfillJs
 * 還沒有對應的 polyfill。
```

編輯第 262-264 行（`findings.length` 分支的錯誤標題）：

```javascript
  console.error(
    `[check_foliate_es_compat] 發現 ${findings.length} 處較新 ES 內建方法` +
    '用法，esCompatPolyfillJs 目前沒有對應防護：\n',
  );
```

編輯第 274-278 行（結尾修復建議）：

```javascript
  console.error(
    '請至 app/lib/reader/foliate_native_bridge.dart 的 ' +
    'esCompatPolyfillJs 補上對應的 polyfill（僅在缺席時才定義，比照既有' +
    '寫法），並用 Node.js + @xmldom/xmldom 對照未經修改的實際 epub.js 驗證' +
    '過缺席時會拋出例外、補上後可修復，再重新執行這支腳本確認乾淨。',
  );
```

- [x] **Step 5: 重新執行腳本，確認結束碼為 0**

Run: `node app/tool/check_foliate_es_compat.js`
Expected: 印出「乾淨——目前已知的較新 ES 內建方法用法都已有對應 polyfill 防護。」，結束碼 0。

- [x] **Step 6: 同步修正 `app/tool/README.md` 的既有過時引用**

`app/tool/README.md` 第 10 行、第 41 行目前仍寫著已改名的 `app/lib/reader/foliate_epub_reader_view.dart`／`_esCompatPolyfillJs`（ADR 0017 泛化重構後的既有遺留文字，與本次修復同一類問題，一併修正）。將這兩處出現的 `app/lib/reader/foliate_epub_reader_view.dart` 改為 `app/lib/reader/foliate_native_bridge.dart`，`_esCompatPolyfillJs` 改為 `esCompatPolyfillJs`（無底線前綴）。**（審查修正 M-1，補上遺漏的第 47 行）**：第 47 行「補上/更新 `app/test/reader/foliate_epub_reader_view_test.dart` 裡驗證 `initialUserScripts` 內容的既有測試」同樣引用了已改名的測試檔案——目前實際檔名為 `app/test/reader/foliate_reader_view_test.dart`（`Glob app/test/reader/*.dart` 確認無 `foliate_epub_reader_view_test.dart` 這個檔案），一併修正為正確檔名。

- [x] **Step 7: Commit**

```bash
git add app/tool/check_foliate_es_compat.js app/tool/README.md
git commit -m "fix(tool): check_foliate_es_compat.js 常數引用漂移修復"
```

---

### Task 2: 新增 `TextConversionMode` enum

**Files:**
- Create: `app/lib/reader/text_conversion_mode.dart`
- Test: `app/test/reader/text_conversion_mode_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `enum TextConversionMode { original, toTraditional, toSimplified }`，供 Task 5（本 Issue）與 Issue 1-5 的 `BookReaderPrefs.textConversionOverride`／`ReadingDefaults.textConversion`／`resolveTextConversion()` 消費。

- [x] **Step 1: 寫失敗測試**

建立 `app/test/reader/text_conversion_mode_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  test('TextConversionMode 有三個值：original／toTraditional／toSimplified',
      () {
    expect(TextConversionMode.values, hasLength(3));
    expect(TextConversionMode.values, contains(TextConversionMode.original));
    expect(
        TextConversionMode.values, contains(TextConversionMode.toTraditional));
    expect(
        TextConversionMode.values, contains(TextConversionMode.toSimplified));
  });

  test('enum 名稱字串穩定（供 SharedPreferences／SQLite 序列化）', () {
    expect(TextConversionMode.original.name, 'original');
    expect(TextConversionMode.toTraditional.name, 'toTraditional');
    expect(TextConversionMode.toSimplified.name, 'toSimplified');
  });
}
```

- [x] **Step 2: 執行測試，確認失敗（找不到檔案）**

Run: `flutter test test/reader/text_conversion_mode_test.dart`
Expected: FAIL，錯誤訊息為找不到 `package:elinkbook/reader/text_conversion_mode.dart`。

- [x] **Step 3: 寫最小實作**

建立 `app/lib/reader/text_conversion_mode.dart`：

```dart
/// 閱讀畫面的簡繁顯示切換（FR-48）：[original] 原文／[toTraditional] 轉換
/// 為繁體／[toSimplified] 轉換為簡體。純顯示層轉換，不修改原始檔案內容，
/// 亦不影響 CFI 定位（見 ADR 0030：轉換為逐字元 1:1、不做詞彙/慣用詞
/// 轉換，保證 ΔL=0）。
enum TextConversionMode { original, toTraditional, toSimplified }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/text_conversion_mode_test.dart`
Expected: PASS，2/2。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/text_conversion_mode.dart app/test/reader/text_conversion_mode_test.dart
git commit -m "feat(reader): 新增 TextConversionMode enum"
```

---

### Task 3: `parseCharTable()` 純函式（字典生成腳本核心解析邏輯）

**Files:**
- Create: `app/tool/generate_conversion_dicts.js`
- Test: `app/tool/test_generate_conversion_dicts.js`

**Interfaces:**
- Consumes: 無（純字串解析函式，不依賴檔案系統）。
- Produces: `parseCharTable(tsvContent: string): Record<string, string>`（CommonJS `module.exports`），供 Task 4 的 `main()` 呼叫；`toMapLiteral(dict: Record<string,string>): string`，供 Task 4 產生 JS/Dart 輸出檔案內容共用。

- [x] **Step 1: 寫失敗測試**

建立 `app/tool/test_generate_conversion_dicts.js`：

```javascript
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
    /字典項字元數不為 1/,
  );
}

function testMultiCharacterKeyThrows() {
  assert.throws(
    () => parseCharTable('異常鍵\t值\n'),
    /字典項字元數不為 1/,
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
```

- [x] **Step 2: 執行測試，確認失敗（找不到 `generate_conversion_dicts.js`）**

Run: `node app/tool/test_generate_conversion_dicts.js`
Expected: 拋出 `Error: Cannot find module './generate_conversion_dicts.js'`。

- [x] **Step 3: 寫最小實作**

建立 `app/tool/generate_conversion_dicts.js`：

```javascript
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
```

- [x] **Step 4: 執行測試，確認通過**

Run: `node app/tool/test_generate_conversion_dicts.js`
Expected: 印出「[test_generate_conversion_dicts] 7 項情境全數通過。」，結束碼 0。

- [x] **Step 5: Commit**

```bash
git add app/tool/generate_conversion_dicts.js app/tool/test_generate_conversion_dicts.js
git commit -m "feat(tool): 新增 parseCharTable() 字典解析純函式與測試"
```

---

### Task 4: 下載 OpenCC 原始字元表、產生雙端字典檔案

**Files:**
- Create: `app/tool/opencc_data/STCharacters.txt`
- Create: `app/tool/opencc_data/TSCharacters.txt`
- Create: `app/tool/opencc_data/README.md`
- Create（由腳本產生）: `app/android/app/src/main/assets/foliate/text_conversion_dict.js`
- Create（由腳本產生）: `app/lib/reader/text_conversion_dict.dart`

**Interfaces:**
- Consumes: Task 3 的 `parseCharTable()`／`toMapLiteral()`（透過 `generate_conversion_dicts.js` 的 `main()` 呼叫，非直接依賴）。
- Produces: `app/lib/reader/text_conversion_dict.dart` 匯出 `const Map<String, String> kS2tDict`／`kT2sDict`，供 Task 5 的 `convertText()` 消費；`app/android/app/src/main/assets/foliate/text_conversion_dict.js` 匯出 `s2tDict`／`t2sDict`，供 Issue 2 的 JS DOM Walker 消費（`import { s2tDict, t2sDict } from './text_conversion_dict.js'`）。

- [x] **Step 1: 建立資料目錄並下載原始字元表**

```bash
mkdir -p app/tool/opencc_data
curl -fsSL -o app/tool/opencc_data/STCharacters.txt https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt
curl -fsSL -o app/tool/opencc_data/TSCharacters.txt https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSCharacters.txt
```

Expected: 兩個檔案下載成功（`curl -f` 遇到 HTTP 錯誤會直接失敗並回傳非 0 結束碼，不會把錯誤頁面內容寫成檔案）。若 URL 已失效（上游倉庫改了路徑/檔名），到 `https://github.com/BYVoid/OpenCC/tree/master/data/dictionary` 查證目前正確路徑後調整上述指令，不要假設此網址永久不變。

- [x] **Step 2: 建立來源說明文件**

建立 `app/tool/opencc_data/README.md`：

```markdown
# OpenCC 原始字元對照表

`STCharacters.txt`（簡體→繁體，key=簡體字）／`TSCharacters.txt`（繁體→簡體，
key=繁體字）直接取自 [BYVoid/OpenCC](https://github.com/BYVoid/OpenCC)
專案的 `data/dictionary/` 目錄，授權 Apache-2.0（見上游倉庫的 LICENSE），
不經修改、原樣 vendor 進本專案版控。

- 來源網址：
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSCharacters.txt
- 下載日期：2026-09-15
- 用途：`app/tool/generate_conversion_dicts.js` 讀取這兩個檔案，產生
  `app/android/app/src/main/assets/foliate/text_conversion_dict.js` 與
  `app/lib/reader/text_conversion_dict.dart` 兩份供 App 使用的查找表
  （見 `docs/adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md`）。
- 更新方式：重新執行上方下載指令覆蓋這兩個檔案，再重跑
  `node app/tool/generate_conversion_dicts.js` 重新產生雙端查找表。
```

- [x] **Step 3: 執行生成腳本，產生雙端字典檔案**

```bash
node app/tool/generate_conversion_dicts.js
```

Expected: 印出「[generate_conversion_dicts] 完成：s2t N 筆、t2s M 筆。」（`N`／`M` 為真實資料筆數，皆為正整數），結束碼 0；`app/android/app/src/main/assets/foliate/text_conversion_dict.js` 與 `app/lib/reader/text_conversion_dict.dart` 兩個檔案已產生。

- [x] **Step 4: 人工核對產出的查找表包含已知正確項目**

```bash
grep -o '"国": "國"' app/lib/reader/text_conversion_dict.dart
grep -o '"后": "後"' app/lib/reader/text_conversion_dict.dart
grep -o '"干": "幹"' app/lib/reader/text_conversion_dict.dart
grep -o '"國": "国"' app/lib/reader/text_conversion_dict.dart
grep -o 's2tDict' app/android/app/src/main/assets/foliate/text_conversion_dict.js
```

（審查修正 M-2：原稿最後一行寫成 `grep A || grep B` 的雙重備援，純屬多餘的猶豫寫法，已簡化為單一呼叫。本計畫全文的 shell 指令假設在 Git Bash／POSIX sh 環境下執行——比照本專案這個工作階段從頭到尾實際執行 git 指令的慣例（Bash 工具說明本身即明訂「runs Git Bash (POSIX sh)」）——不是原生 Windows `powershell.exe`／`pwsh`；`curl`／`grep`／`mkdir -p` 在此假設下皆為標準 GNU 工具行為，不會撞到 PowerShell 的 `curl`/`Invoke-WebRequest` 別名問題。）

Expected: 前四個 `grep` 皆有輸出（找到對應字串），確認多候選字案例（「后」「干」）確實只取了第一個候選字（「後」「幹」）且與已查證的真實 OpenCC 資料一致；最後一個確認 `s2tDict` 識別字出現在 JS 檔案中。

- [x] **Step 5: 驗證 JS 產出檔案語法正確**

```bash
node --check app/android/app/src/main/assets/foliate/text_conversion_dict.js
```

Expected: 無輸出、結束碼 0（語法正確；`--check` 只驗證語法不執行，`export const` 頂層語法在 `--check` 模式下對純腳本解析沒有 module 上下文疑慮，實際載入以 `<script type="module">` 為準，見 `index.html:14` 既有引用模式）。

- [x] **Step 6: 重新執行 ES 相容性檢查腳本，確認新增的 vendor 檔案沒有引入未防護的較新 API**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 0（`text_conversion_dict.js` 只含物件字面量常數，不呼叫任何 ES 內建方法，不會觸發任何 `RISKY_APIS` 規則）。

- [x] **Step 7: Commit**

```bash
git add app/tool/opencc_data/ app/android/app/src/main/assets/foliate/text_conversion_dict.js app/lib/reader/text_conversion_dict.dart
git commit -m "feat(reader): vendor OpenCC 原始字元表並產生雙端簡繁查找表"
```

---

### Task 5: `convertText()` 純函式與 Dart 單元測試

**Files:**
- Create: `app/lib/reader/text_conversion.dart`
- Test: `app/test/reader/text_conversion_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/text_conversion_mode.dart` 的 `TextConversionMode`（Task 2）；`app/lib/reader/text_conversion_dict.dart` 的 `kS2tDict`／`kT2sDict`（Task 4）。
- Produces: `String convertText(String input, TextConversionMode mode)`，供 Issue 1-5（`resolveTextConversion()` 呼叫端、目錄/書籤/劃線清單顯示、全文檢索查詢擴充、TTS 朗讀段轉換）消費——此簽章為本 Epic 後續所有 Issue 的固定依賴介面，不得更動參數順序或型別。

- [x] **Step 1: 寫失敗測試**

建立 `app/test/reader/text_conversion_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  group('convertText', () {
    test('original 模式原樣回傳', () {
      expect(convertText('国电脑', TextConversionMode.original), '国电脑');
    });

    test('toTraditional 轉換已知簡體字元', () {
      expect(convertText('国', TextConversionMode.toTraditional), '國');
      expect(convertText('电脑', TextConversionMode.toTraditional), '電腦');
    });

    test('toSimplified 轉換已知繁體字元', () {
      expect(convertText('國', TextConversionMode.toSimplified), '国');
      expect(convertText('電腦', TextConversionMode.toSimplified), '电脑');
    });

    test('多對一併字取首個候選字（真實 OpenCC 資料：「后」「干」案例）', () {
      // STCharacters.txt：后 -> 後 后（取「後」）；干 -> 幹 乾 干 榦（取「幹」）。
      expect(convertText('后', TextConversionMode.toTraditional), '後');
      expect(convertText('干', TextConversionMode.toTraditional), '幹');
    });

    test('查找表找不到的字元維持原樣', () {
      expect(
        convertText('ABC123', TextConversionMode.toTraditional),
        'ABC123',
      );
    });

    test('轉換不改變 UTF-16 長度與 code point 數量（ΔL=0，ADR 0030 核心不變量，審查修正 C-1）', () {
      const input = '国电脑后干发里';
      final converted =
          convertText(input, TextConversionMode.toTraditional);
      expect(converted.length, input.length,
          reason: 'UTF-16 code unit 長度不可改變（epubcfi.js Range offset 計算基準）');
      expect(converted.runes.length, input.runes.length,
          reason: 'Unicode code point 數量不可改變');
    });

    test('空字串原樣回傳（審查修正 I-1）', () {
      expect(convertText('', TextConversionMode.toTraditional), '');
      expect(convertText('', TextConversionMode.original), '');
    });

    test('英數/標點/中文混排字串只轉換中文部分（審查修正 I-1）', () {
      expect(
        convertText('Hello 电脑, 世界！123', TextConversionMode.toTraditional),
        'Hello 電腦, 世界！123',
      );
    });

    test('含代理對字元（輔助平面／emoji）的字串不拋例外、原樣保留（審查修正 I-1）', () {
      // '😀'（U+1F600）與 '𠗣'（U+205E3）皆需代理對編碼，兩者都不在查找表
      // 中（查找表已在生成階段排除 BMP↔輔助平面配對，見 Task 3），
      // convertText 走訪 runes 時須正確處理、不拋例外、原樣保留。
      const input = '国😀𠗣电';
      final converted = convertText(input, TextConversionMode.toTraditional);
      expect(converted, '國😀𠗣電');
      expect(converted.length, input.length);
    });
  });
}
```

- [x] **Step 2: 執行測試，確認失敗（找不到 `text_conversion.dart`）**

Run: `flutter test test/reader/text_conversion_test.dart`
Expected: FAIL，錯誤訊息為找不到 `package:elinkbook/reader/text_conversion.dart`。

- [x] **Step 3: 寫最小實作**

建立 `app/lib/reader/text_conversion.dart`：

```dart
import 'text_conversion_dict.dart';
import 'text_conversion_mode.dart';

/// 依 [mode] 對 [input] 做簡繁字元轉換。[TextConversionMode.original] 原樣
/// 回傳；查找表（[kS2tDict]／[kT2sDict]，`app/tool/generate_conversion_
/// dicts.js` 產出）內找不到的字元維持原樣，不視為錯誤。逐字元查表替換，
/// 保證輸出與輸入的 UTF-16 長度與 code point 數量恆相同（ADR 0030：
/// ΔL=0，保護 CFI 座標系；查找表本身已在生成階段排除會破壞這個不變量的
/// BMP↔輔助平面字元配對，見 `generate_conversion_dicts.js` 的
/// `parseCharTable()`）。
String convertText(String input, TextConversionMode mode) {
  // 審查修正 I-1：空字串／original 模式提早返回，避免不必要的
  // StringBuffer 配置與 runes 走訪。
  if (mode == TextConversionMode.original || input.isEmpty) return input;
  final dict = mode == TextConversionMode.toTraditional ? kS2tDict : kT2sDict;
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(dict[ch] ?? ch);
  }
  return buffer.toString();
}
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/text_conversion_test.dart`
Expected: PASS，9/9。

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/text_conversion.dart app/test/reader/text_conversion_test.dart
git commit -m "feat(reader): 新增 convertText() 簡繁轉換純函式與測試"
```

---

## Self-Review

**（2026-09-15 依 `reviews/review-plan-issue-0.md` 審查修訂）**：Task 3 `parseCharTable()` 原僅用 code point 數檢查字典項長度，未區分 UTF-16 code unit 長度——OpenCC 原始表中存在 BMP↔輔助平面代理對字元配對，兩者 code point 數皆為 1 但 UTF-16 `.length` 不同，會通過原檢查卻仍打破 `epubcfi.js` Range offset 計算賴以成立的 ΔL=0 前提。已修正為兩層防護（code point 數不為 1 拋例外；UTF-16 長度不相等則跳過不進字典），並補上對應測試、`convertText()` 空字串/代理對測試、`app/tool/README.md` 第 47 行過時檔名、生成的 Dart 檔案 `// coverage:ignore-file` 標頭。

**Spec 覆蓋度**：對照 `issues.md` Issue 0 的「範圍」逐項核對——(1) `check_foliate_es_compat.js` 修復 → Task 1；(2) 字典生成腳本＋正規化約束（取首個候選字＋長度斷言）→ Task 3；(3) JS／Dart 兩份查找表 vendor → Task 4；(4) `TextConversionMode` enum → Task 2；(5) `convertText()` 純函式 → Task 5。Issue 0 列出的三項單元測試要求（`convertText()` 行為、字典生成腳本正規化、`check_foliate_es_compat.js` 回歸）與驗收標準（JS 字典可被 WebView 載入、`flutter analyze` 乾淨）皆已對應到具體 Task 步驟。無遺漏。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼，沒有省略號代表的未寫邏輯。

**型別一致性**：`TextConversionMode`（Task 2）→ `convertText(String, TextConversionMode)`（Task 5）參數型別一致；`kS2tDict`／`kT2sDict`（Task 4 產出）與 Task 5 `text_conversion.dart` 的 import／使用名稱一致；`parseCharTable`／`toMapLiteral`（Task 3 定義、`module.exports` 匯出）與 Task 4 `generate_conversion_dicts.js` 的 `main()` 內部呼叫名稱一致。三者之間無命名漂移。
