# Epic 42 Issue 5 — TTS 朗讀文字轉換整合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 TTS 朗讀出的語音內容依目前生效的簡繁顯示轉換模式呈現（例如全域/單書設定為「轉換為繁體」時，朗讀簡體原文書要唸出繁體讀音對應的文字），同時保證朗讀同步高亮所依賴的 CFI 錨點與全文檢索索引寫入邏輯完全不受影響——兩者皆恆對應原文。

**Architecture:** `main.js` 的 `extractSegmentsForSection()`（`window.buildTtsSegments()`／`window.buildSegmentsForSection()` 共用的核心邏輯，見該函式文件註解）本身不修改，繼續回傳原文 `segments[].text` 與依原文計算的 `cfi`。新增一個零 DOM 依賴的純函式 `convertTtsSegments(segments, mode)`（`text-conversion.js`，直接重用 Issue 0b 已交付的 `applyTextConversionToString()`），只轉換 `text` 欄位、原樣保留 `segmentId`／`cfi`。只有 `window.buildTtsSegments()`（TTS 播放專用）在回傳前呼叫這個函式，套用 `currentTextConversion`（main.js 模組層級變數，Issue 2 已維護為該書「單書情境」生效值，見 `window.applyPreferences()` 既有邏輯）；`window.buildSegmentsForSection()`（epic-10-search 全文檢索背景索引專用）刻意維持原樣不動，索引永遠寫入原文（Issue 4 既有不變量）。全程不需要修改 Dart 端任何程式碼——`FoliateReaderView.loadTtsSegments()`／`TtsController`／`TtsSegmentCfi` 收到的 JSON 已經是轉換後的最終顯示文字，對它們而言與轉換前的資料形狀完全相同，無感知差異。

**Tech Stack:** JavaScript（`readest/foliate-js` 釘定 vendor 目錄下的專案自有模組，ADR 0011 允許新增/修改專案自有檔案，禁止修改釘定上游檔案）、Node.js（`.mjs` 腳本，`node:assert/strict`，比照 `app/tool/test_text_conversion.mjs`／`test_apply_text_conversion.mjs` 既有慣例）、Dart（`flutter_test` 的 main.js 原始碼字串斷言 regression guard，比照 `app/test/reader/foliate_reader_view_test.dart` 既有「main.js 安全視窗跟隨翻頁」「main.js 朗讀段長段落次要邊界切分」兩組既有 regression guard 慣例）。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 5（另見 `spec.md`「TTS 整合」段落，`design.md` 第 11 點 I-2 修正——明文授權「具體轉換發生在 JS 端回傳前一併處理，還是 Dart 端接收後處理，留待實作階段依現有呼叫鏈的既有分工決定」，本計畫選擇 JS 端回傳前處理，理由見上方 Architecture）。

## Global Constraints

- `extractSegmentsForSection(sectionIndex)`（`main.js`，目前實際位於 779-834 行——`spec.md`／`issues.md` 記載的 683-738/678-682 行號是 Issue 2 合併前的舊行號，已隨 Issue 2 新增程式碼位移，行號以本計畫查證的當下版本為準）**本身不得修改**：`window.buildTtsSegments()`（TTS 播放）與 `window.buildSegmentsForSection()`（epic-10-search 全文檢索背景索引，`foliate_content_indexer.dart` 呼叫）共用同一份邏輯，回傳原文 `text` 與依原文計算的 `cfi`。
- **索引寫入端不變（呼應 Issue 4 既有不變量）**：`window.buildSegmentsForSection()` 絕不能套用 `convertTtsSegments()` 或任何簡繁轉換——`book_content_fts` 必須永遠索引原文，否則會讓全文檢索在某些顯示模式下對已轉換文字建索引，破壞 Issue 4 交付的「查詢端一律正向產生三個變體」設計前提。
- **cfi 欄位不受影響**：`extractSegmentsForSection()` 建立朗讀段 Range 所用的 `doc` 來自 `view.book.sections[sectionIndex].createDocument()`——一份獨立、從未被 `applyTextConversion()`（Issue 2）走訪過的新文件，其文字節點沒有 `_elinkOffsetMap`；`view.getCFI()` 的全域方法遮蔽（Issue 2，`main.js:38-39`）對這類節點是恆等變換。`cfi` 因此天生恆對應原文，`convertTtsSegments()` 不得也不需要處理 `cfi`／`segmentId`，只轉換 `text`。
- `applyTextConversionToString(text, mode)`（`text-conversion.js`，Issue 0b）簽章與行為不得更動，本計畫直接消費、不重新實作轉換演算法。
- `currentTextConversion`（`main.js:131` 模組層級變數，Issue 2 交付）已由 `initialPrefs.textConversion`（開書當下）與 `window.applyPreferences()`（閱讀中即時切換，`main.js:281-284`）正確維護為該書「單書情境」生效值（`reader_screen.dart` 傳入 `resolveTextConversion()` 解析結果，經 `FoliateReaderView.textConversion` 建構參數／`buildFoliatePreferencesMap()` 流入）。本計畫直接讀取這個既有變數，不重新設計偏好解析或注入管線，也不新增任何 Dart 端程式碼。
- `showTtsHighlight`／`clearTtsHighlight` 等同步高亮方法的定位錨點維持使用 `cfi` 欄位（原文），完全不受本計畫影響，本計畫不觸碰這兩個函式。
- **不新增獨立 JS 檔案**：`convertTtsSegments()` 是對既有 `applyTextConversionToString()` 的薄封裝（陣列 map，不到 10 行程式碼），直接加進同一個 `text-conversion.js`，不比照 `tts-safe-window.js` 的「main.js 專屬邏輯獨立成檔」模式另開新檔——那個模式是為了讓「原本焊在 main.js 裡、main.js 又因模組頂層副作用無法被 Node 匯入」的邏輯變得可測試；`convertTtsSegments()` 從一開始就只依賴零 DOM 依賴的 `text-conversion.js`，沒有這個限制，另開檔案是不必要的切分。
- **真機驗證不納入本計畫的自動化任務**：`issues.md`／`spec.md` 驗收標準要求「真機驗證朗讀語音文字與畫面顯示模式一致」，但比照 Issue 2／Issue 3／Issue 4 三次先例（皆在審查報告中明確記錄「真機 `app/integration_test` 驗證待執行，非實作缺口」，且截至 Issue 4 為止 `app/integration_test/` 目錄下沒有任何 epic-42 專屬測試檔），本計畫兩個 Task 皆為 JS 純函式單元測試＋main.js 接線的 Dart regression guard，不新增 `app/integration_test/` 檔案；真機語音實際播放內容留待人類 QA 執行。

---

## File Structure

- Modify: `app/android/app/src/main/assets/foliate/text-conversion.js` — 新增 `convertTtsSegments(segments, mode)` 純函式。
- Create: `app/tool/test_tts_segment_conversion.mjs` — 對應 Node 單元測試。
- Modify: `app/android/app/src/main/assets/foliate/main.js` — `window.buildTtsSegments()` 接上 `convertTtsSegments()`，`window.buildSegmentsForSection()` 維持原樣不動。
- Modify: `app/test/reader/foliate_reader_view_test.dart` — 新增 main.js 接線 regression guard（比照既有「main.js 安全視窗跟隨翻頁」測試群組慣例）。

---

### Task 1: `convertTtsSegments()` 純函式

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/text-conversion.js`
- Test: `app/tool/test_tts_segment_conversion.mjs`

**Interfaces:**
- Consumes: `applyTextConversionToString(text, mode)`（同檔案既有函式，Issue 0b 交付，簽章 `(text: string, mode: 'original' | 'toTraditional' | 'toSimplified') => { text: string, offsetMap: object | null }`）。
- Produces: `convertTtsSegments(segments, mode)`，簽章 `(segments: {segmentId: string, cfi: string, text: string}[], mode: 'original' | 'toTraditional' | 'toSimplified') => {segmentId: string, cfi: string, text: string}[]`，供 Task 2 `main.js` 消費。

- [x] **Step 1: 新增失敗測試**

建立 `app/tool/test_tts_segment_conversion.mjs`：

```js
// epic-42-text-conversion Issue 5：convertTtsSegments() 朗讀段文字轉換
// 驗證腳本。零 DOM 依賴，直接複用 Issue 0b 已驗證過的
// applyTextConversionToString()（見 test_text_conversion.mjs 既有測試
// 向量），只需驗證 segmentId／cfi 保持不變、text 依 mode 正確轉換。
//
// 用法：node app/tool/test_tts_segment_conversion.mjs

import assert from 'node:assert/strict'
import { convertTtsSegments } from '../android/app/src/main/assets/foliate/text-conversion.js'

// 基本轉換：text 依 mode 轉換（台灣慣用詞，沿用 test_text_conversion.mjs
// 已驗證過的「内存」→「記憶體」向量），segmentId／cfi 原樣保留不動。
{
  const segments = [
    { segmentId: '0', cfi: 'epubcfi(/6/2!/4/2,/1:0,/1:2)', text: '内存' },
    { segmentId: '1', cfi: 'epubcfi(/6/2!/4/4,/1:0,/1:2)', text: '软件' },
  ]
  const result = convertTtsSegments(segments, 'toTraditional')
  assert.equal(result[0].text, '記憶體')
  assert.equal(result[0].cfi, segments[0].cfi)
  assert.equal(result[0].segmentId, segments[0].segmentId)
  assert.equal(result[1].text, '軟體')
  assert.equal(result[1].cfi, segments[1].cfi)
  assert.equal(result[1].segmentId, segments[1].segmentId)
}

// original 模式：文字原樣不變（applyTextConversionToString 對 'original'
// 的既有恆等行為，見 text-conversion.js 該函式開頭）。
{
  const segments = [{ segmentId: '0', cfi: 'epubcfi(/6/2)', text: '内存清空' }]
  const result = convertTtsSegments(segments, 'original')
  assert.equal(result[0].text, '内存清空')
  assert.equal(result[0].cfi, segments[0].cfi)
}

// toSimplified：忠實保留原著文風，不套用大陸用語替換（延續 Issue 0b
// 「妥瑞氏症」ADR 0032 靈魂驗證案例，test_text_conversion.mjs 已驗證過的
// 向量）。
{
  const segments = [{ segmentId: '0', cfi: 'epubcfi(/6/2)', text: '妥瑞氏症' }]
  const result = convertTtsSegments(segments, 'toSimplified')
  assert.equal(result[0].text, '妥瑞氏症')
}

// 多筆朗讀段：每筆各自獨立轉換，互不影響。
{
  const segments = [
    { segmentId: '0', cfi: 'epubcfi(/6/2!/4/2)', text: '内存' },
    { segmentId: '1', cfi: 'epubcfi(/6/2!/4/4)', text: 'ABC123' },
  ]
  const result = convertTtsSegments(segments, 'toTraditional')
  assert.equal(result.length, 2)
  assert.equal(result[0].text, '記憶體')
  assert.equal(result[1].text, 'ABC123')
}

// 空陣列：回傳空陣列，不拋出例外（章節無可朗讀文字的既有邊界情況）。
{
  const result = convertTtsSegments([], 'toTraditional')
  assert.deepEqual(result, [])
}

console.log('[test_tts_segment_conversion] 全部通過')
```

- [x] **Step 2: 執行測試確認失敗**

Run: `node app/tool/test_tts_segment_conversion.mjs`
Expected: FAIL（`convertTtsSegments` 不是 `text-conversion.js` 已匯出的成員，import 解構得到 `undefined`，呼叫時拋出 `TypeError: convertTtsSegments is not a function`）。

- [x] **Step 3: 實作 `convertTtsSegments()`**

在 `app/android/app/src/main/assets/foliate/text-conversion.js` 檔案結尾（第 101-102 行）：

```js
  return { text: result, offsetMap: builder.build() }
}
```

之後新增：

```js

/**
 * 朗讀段清單依 [mode] 轉換顯示文字（epic-42-text-conversion Issue 5，
 * issues.md「範圍」：「回傳的 segments[].text 在傳給語音合成器前，經過
 * 一次 convertText(text, mode) 轉換」）。只轉換 [segments] 陣列中每個
 * 元素的 `text` 欄位供語音合成器朗讀，`segmentId`／`cfi` 原樣保留——
 * `cfi` 是 main.js `extractSegmentsForSection()` 對
 * `view.book.sections[i].createDocument()` 產生之獨立、從未被
 * `applyTextConversion()` 走訪過的文件計算得出，本就恆對應原文，轉換
 * 顯示文字不影響它，也不應該讓它跟著變動（見 main.js 頂層 `view.getCFI`
 * 全域遮蔽註解）。
 * @param {{segmentId: string, cfi: string, text: string}[]} segments
 * @param {'original' | 'toTraditional' | 'toSimplified'} mode
 * @returns {{segmentId: string, cfi: string, text: string}[]}
 */
export function convertTtsSegments(segments, mode) {
  return segments.map((segment) => ({
    ...segment,
    text: applyTextConversionToString(segment.text, mode).text,
  }))
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `node app/tool/test_tts_segment_conversion.mjs`
Expected: `[test_tts_segment_conversion] 全部通過`

- [x] **Step 5: Commit**

```bash
git add app/android/app/src/main/assets/foliate/text-conversion.js app/tool/test_tts_segment_conversion.mjs
git commit -m "feat(reader): 新增 convertTtsSegments() 朗讀段簡繁轉換純函式"
```

---

### Task 2: `main.js` 接線——`window.buildTtsSegments()` 套用轉換

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes: `convertTtsSegments(segments, mode)`（Task 1）、既有模組層級變數 `currentTextConversion`（`main.js:131`，Issue 2 交付）。
- Produces: 無新增對外介面——`window.buildTtsSegments()` 既有回傳格式（`callHandler('onTtsSegmentsReady', sectionIndex, JSON.stringify(...))`，陣列元素形狀 `{segmentId, cfi, text}`）完全不變，只有 `text` 欄位內容依模式改變；`Dart` 端 `TtsSegmentCfi.fromWire()`／`FoliateReaderView.loadTtsSegments()`／`TtsController` 皆不需要修改（本 Task 不涉及任何 Dart 檔案的實作程式碼異動，僅新增 Dart 端 regression guard 測試）。

- [ ] **Step 1: 新增失敗測試**

在 `app/test/reader/foliate_reader_view_test.dart` 找到「main.js 朗讀段長段落次要邊界切分 regression guard（epic-34-tts-readalong Issue 11）」測試群組結尾的 `});`，與下一個「main.js 安全視窗跟隨翻頁 + E-Ink 高對比 regression guard」群組開頭之間，新增：

```dart

  group(
      'main.js 朗讀段文字簡繁轉換 regression guard '
      '（epic-42-text-conversion Issue 5）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('main.js 從 text-conversion.js 匯入 convertTtsSegments()，不自行內嵌轉換邏輯',
        () {
      expect(
        mainJsSource.contains(
          "import { convertTtsSegments } from './text-conversion.js'",
        ),
        isTrue,
        reason: 'main.js 須從 text-conversion.js 匯入純函式，不可自行內嵌'
            '簡繁轉換邏輯（該邏輯已由 app/tool/test_tts_segment_conversion.mjs '
            '單元測試涵蓋，這裡只驗證 main.js 接線正確，不重複驗證轉換'
            '細節，比照既有 resolveTtsSafeWindowDirection 接線測試慣例）。',
      );
    });

    test('window.buildTtsSegments 呼叫 convertTtsSegments() 並回傳轉換後結果，而非原始 segments',
        () {
      expect(
        mainJsSource.contains(
          'const converted = convertTtsSegments(segments, currentTextConversion)',
        ),
        isTrue,
        reason: '朗讀段文字須依目前生效的簡繁轉換模式（currentTextConversion，'
            '該書單書情境生效值，見 Issue 2 既有維護邏輯）轉換後才送給語音'
            '合成器。',
      );
      expect(
        mainJsSource.contains(
          "'onTtsSegmentsReady', sectionIndex, JSON.stringify(converted),",
        ),
        isTrue,
        reason: '回呼 Dart 端的必須是轉換後的 converted，而非未轉換的原始 '
            'segments，否則轉換形同白做。',
      );
    });

    test(
        'window.buildSegmentsForSection（全文檢索索引專用）刻意不套用轉換，索引永遠寫入原文'
        '（epic-42-text-conversion Issue 4 Global Constraints「索引寫入端不變」）',
        () {
      final indexerStart = mainJsSource
          .indexOf('window.buildSegmentsForSection = async function');
      expect(indexerStart, greaterThan(-1),
          reason: '找不到 window.buildSegmentsForSection 定義。');
      final indexerBody = mainJsSource.substring(indexerStart);
      expect(
        indexerBody.contains('convertTtsSegments'),
        isFalse,
        reason: '全文檢索索引路徑若也套用顯示轉換，會讓 book_content_fts 索引'
            '到已轉換文字，違反 Issue 4 訂下的「索引寫入端不變，永遠索引'
            '原文」不變量，之後任何顯示模式下的原文搜尋都會漏檢。',
      );
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 新增的 3 個測試皆 FAIL（`main.js` 目前尚未 import `convertTtsSegments`，也沒有 `const converted = convertTtsSegments(...)`／`JSON.stringify(converted)` 字串；`window.buildSegmentsForSection` 目前確實不含 `convertTtsSegments` 字串，第 3 個測試在 Step 1 當下已是 PASS 而非 FAIL——這是刻意的：它是防止 Step 3 實作時「誤把轉換也接到 buildSegmentsForSection」的預防性 regression guard，本來就該在修改前後皆維持 PASS）。

- [ ] **Step 3: 實作 main.js 接線**

在 `app/android/app/src/main/assets/foliate/main.js` 第 4-9 行（import 區塊）：

```js
import { resolveTtsSafeWindowDirection } from './tts-safe-window.js'
import {
  applyTextConversion,
  toOriginalRange,
  resolveDisplayRange,
} from './text-conversion-walker.js'
```

之後新增一行：

```js
import { convertTtsSegments } from './text-conversion.js'
```

修改 `window.buildTtsSegments`（第 842-853 行），把：

```js
window.buildTtsSegments = async function (sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex)
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify(segments),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify([]),
    )
  }
}
```

改為：

```js
window.buildTtsSegments = async function (sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex)
    // epic-42-text-conversion Issue 5：只有語音朗讀路徑套用顯示轉換，
    // segmentId／cfi 兩欄位由 convertTtsSegments() 原樣保留不動——cfi 來自
    // extractSegmentsForSection() 對 view.book.sections[i].createDocument()
    // 產生之獨立未轉換文件計算，天生恆對應原文，不需要、也不應該跟著
    // 轉換（見上方 view.getCFI 全域遮蔽註解）。
    // window.buildSegmentsForSection()（全文檢索索引專用）刻意不套用這層
    // 轉換，索引永遠寫入原文（epic-42-text-conversion Issue 4 Global
    // Constraints「索引寫入端不變」）。
    const converted = convertTtsSegments(segments, currentTextConversion)
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify(converted),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify([]),
    )
  }
}
```

**`window.buildSegmentsForSection`（緊接在下方，第 863-874 行）維持完全不動**，繼續對未轉換的 `segments` 直接 `JSON.stringify`——這是本 Task 刻意不修改的部分，不要一併套用轉換。

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增 3 個測試通過）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 重新執行 Task 1 的 Node 測試，確認零回歸**

Run: `node app/tool/test_tts_segment_conversion.mjs`
Expected: `[test_tts_segment_conversion] 全部通過`（本 Task 未修改 `text-conversion.js`，純粹確認前一個 Task 的產出未被意外破壞）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(reader): window.buildTtsSegments 接上簡繁轉換 convertTtsSegments"
```

---

## Self-Review

**Spec 覆蓋度**：對照 `issues.md` Issue 5「範圍」逐項核對——(1) `extractSegmentsForSection()` 本身不修改 → Global Constraints 明文禁止，Task 1／2 皆未觸碰該函式 → 已覆蓋；(2) `segments[].text` 在傳給語音合成器前經 `convertText`（本計畫用 JS 端同義的 `applyTextConversionToString`，Dart AOT 無法呼叫 JS，ADR 0031 既有分工，`mode` 為單書情境生效值）轉換 → Task 1（純函式）＋ Task 2（接線）→ 已覆蓋；(3) 具體轉換發生在 JS 端回傳前（依現有呼叫鏈分工決定，本計畫選擇這個方案）→ Task 2 →已覆蓋；(4) `showTtsHighlight` 定位錨點維持用 `cfi`（原文）、不受影響 → Global Constraints 說明其結構性保證（`extractSegmentsForSection` 對獨立未轉換文件計算 cfi），未修改任何相關函式 → 已覆蓋。單元測試要求兩項：「驗證朗讀段文字依目前顯示模式正確轉換，cfi 欄位不受影響」→ Task 1 `test_tts_segment_conversion.mjs`（含 cfi／segmentId 不變斷言）；「`app/integration_test/`（真機）」→ 依 Issue 2／3／4 既有先例列為 Global Constraints 說明的已知範圍外項目，非本計畫遺漏。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼區塊；`test_tts_segment_conversion.mjs` 測試向量（「内存」→「記憶體」、「软件」→「軟體」、「妥瑞氏症」原樣保留）皆複用 `test_text_conversion.mjs`／`test_apply_text_conversion.mjs` 已驗證過的既有字元對，未自行發明未經驗證的字元映射。

**型別一致性**：`convertTtsSegments(segments: {segmentId: string, cfi: string, text: string}[], mode: 'original' | 'toTraditional' | 'toSimplified') => {segmentId: string, cfi: string, text: string}[]` 在 Task 1 定案後，Task 2 `main.js` 呼叫端 `convertTtsSegments(segments, currentTextConversion)` 完全依此簽章使用（`segments` 型別與 `extractSegmentsForSection()` 既有回傳形狀一致，`currentTextConversion` 型別與既有 `TextConversionMode` 三個合法字串值一致）。`window.buildTtsSegments` 既有回傳格式（`{segmentId, cfi, text}` 陣列 JSON）不變，Dart 端 `TtsSegmentCfi.fromWire()` 無需修改，本計畫全程未新增或修改任何 Dart 實作檔案。

**已知限制**：真機語音實際播放內容與朗讀同步高亮定位不受影響兩項驗收標準，依 Global Constraints 說明留待人類 QA 於真機執行，非本計畫自動化測試範圍；`spec.md`／`issues.md` 記載的 `main.js` 行號（678-738 一帶）因 Issue 2 合併已產生位移，本計畫全程以查證後的當下實際行號（main.js 4-9、131、779-834、842-874 行）為準。
