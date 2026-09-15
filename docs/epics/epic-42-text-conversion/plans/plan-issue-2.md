# Epic 42 Issue 2 — JS 端 DOM Walker 與雙向分段偏移映射（CFI 保護）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 WebView 內顯示的文字（EPUB／KF8／TXT／MD 流式與 FXL 章節）依使用者選擇的簡繁模式即時轉換，同時保證所有既有的 EPUB CFI（劃線、書籤、目前閱讀位置、TTS 朗讀段）永遠對應「未轉換的原始文本」，不因顯示層轉換而位移或拋出例外。

**Architecture:** 新增一個零 DOM 依賴、可用純 Node.js 單元測試的模組 `text-conversion-walker.js`，內含「DOM Walker 逐文字節點套用轉換＋建立雙向偏移映射」與「CFI 座標保護（Range↔offset 調整）」兩組函式，由 `main.js` 匯入使用。CFI 保護的實作手法是在 `main.js`（非 vendor 檔案）對 `view`（`readest/foliate-js` 釘定 `View` 自訂元素實例）的兩個公開方法 `getCFI()`／`resolveCFI()` 做**實例層級**的方法遮蔽（monkey-patch，標準 JS own-property shadowing，不修改 `view.js` 原始碼本身，符合 ADR 0011）——這兩個方法是全專案（`main.js` 自身的選取建立劃線、目錄、TTS 段落 CFI 計算，以及 `view.js` 內部 `#onRelocate()` 算「目前閱讀位置」CFI）**唯一**的 Range↔CFI 轉換入口，遮蔽一次即可讓所有既有呼叫點自動獲得保護，不需要逐一修改呼叫端。DOM Walker 的觸發點有二：`view.addEventListener('load', ...)`（新章節載入/look-ahead 預讀）與 `window.applyPreferences()`（閱讀中即時切換）。Dart 端新增 `FoliateReaderView.textConversion` 建構參數，透過既有的 `buildFoliatePreferencesMap()`/`window.applyPreferences()` 管線把 Issue 1 的 `resolveTextConversion()` 解析結果送進 JS。

**Tech Stack:** JavaScript（ES module，`readest/foliate-js` 執行環境，零建置工具鏈）、Node.js（`.mjs` 單元測試腳本，零 npm 依賴）、Flutter/Dart（`flutter_test`／`integration_test`）。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 2、`docs/epics/epic-42-text-conversion/spec.md`「JS 端轉換與偏移映射模組」、`docs/epics/epic-42-text-conversion/offset-mapping-spec.md`（雙向分段偏移映射演算法規格，本計畫逐條對應實作）、[ADR 0032](../../adr/0032-text-conversion-taiwan-phrases-with-piecewise-offset-map.md)、[ADR 0011](../../adr/0011-foliate-js-vendored-pinned-not-npm.md)（vendor 檔案不可修改）。

## Global Constraints

- `app/android/app/src/main/assets/foliate/` 下的 `view.js`／`epubcfi.js`／`paginator.js`／`fixed-layout.js`／`overlayer.js`／`epub.js`／`comic-book.js`／`mobi.js` 是 `readest/foliate-js` 釘定版本（ADR 0011），本計畫**不修改**這些檔案任何一行；`main.js`／`text-conversion.js`／`text-offset-map.js`／`text_conversion_dict.js` 是本專案自己的整合/vendor-data 檔案，可自由修改/新增。
- CFI 保護的攔截點固定為 `view.getCFI`／`view.resolveCFI`（`view.js` 第 493-507 行，已查證為全部 Range↔CFI 轉換的唯一入口，見 Architecture）。**不得**改為修改 `book.resolveCFI`（epub.js 每種格式各自定義，需要逐格式處理，且 mobi.js/comic-book.js 未定義，行為不一致）或逐一修改 `main.js` 各呼叫點（`reportSelection()`／`buildTocEntry()`／`extractSegmentsForSection()`，會遺漏 `view.js` 內部 `#onRelocate()` 這個沒有對應 main.js 呼叫點、直接影響「目前閱讀位置」CFI 正確性的內部呼叫）。
- `extractSegmentsForSection()`（TTS 段落，`main.js:683-738`）與 `buildTocEntry()`（目錄，`main.js:586-624`）皆透過 `view.book.sections[index].createDocument()` 產生**獨立、從未被 `applyTextConversion()` 觸碰過**的新 Document 計算 Range/CFI（已查證，非目前渲染中的 live DOM）——這兩處的文字節點永遠沒有 `_elinkOffsetMap`，`adjustOffsetForCfi()` 對它們是恆等變換，故 `view.getCFI`／`view.resolveCFI` 全域攔截不會、也不需要對它們做任何特殊處理，不得誤判為「需要排除的呼叫點」而加上額外分支。
- **`view.resolveCFI` 的攔截不得只是「事後調整 `anchor(doc)` 的回傳值」**（2026-09-15 審查修正 C-2）：`anchor(doc)` 內部呼叫真正的 `CFI.toRange(doc, parts)`，其 `range.setEnd(end.node, end.offset)` 直接對「目前顯示中（可能已轉換、長度較短）」的 live 文字節點以**原文 offset** 呼叫瀏覽器原生 Range API——縮短詞（如「公共汽車」(4)→「公車」(2)）情境下該 offset 超出目前顯示文字長度，瀏覽器會在 `CFI.toRange()` 內部就拋出 `IndexSizeError`，被其自身的 `try/catch` 吞掉回傳 `null`，事後調整完全沒有機會執行。正確做法（見 Task 1 `resolveDisplayRange()`）：呼叫 `anchor(doc)` **之前**，先把 `doc` 內所有曾被轉換過的文字節點（`_elinkOffsetMap` 非 null）暫時復原成 `_elinkOrigText`，讓 `CFI.toRange()` 內部比對的 offset 與暫時還原後的文字長度一致、保證不拋例外；取得結果後立即讀出邊界節點/offset，復原回顯示文字，最後用 `adjustOffsetForCfi('origToDisplay')` 算出安全（已夾在目前顯示文字長度內）的顯示座標，建立一個全新的 `Range` 回傳——不得重用/事後修改 `anchor(doc)` 已經失敗或已經在錯誤座標系下建立的 Range 物件。
- **`view.getCFI` 的攔截（`toOriginalRange()`）絕對不能呼叫真實 DOM `Range` 的 `cloneRange()`/`setStart()`/`setEnd()`**（2026-09-15 審查修正 C-1）：同樣的縮短詞情境下，對 live DOM 文字節點（目前顯示長度已縮短）呼叫 `setEnd(node, 原文 offset)` 一樣會拋出 `IndexSizeError`。已查證 `epubcfi.js:302-308` 的 `fromRange()` 只解構讀取 `startContainer`/`startOffset`/`endContainer`/`endOffset`/`collapsed` 五個屬性，從未呼叫任何 DOM Range 方法——故 `toOriginalRange()` 必須回傳純資料物件（鴨子定型），不得建構真實 `Range`。
- `text-conversion-walker.js` 的四個匯出函式（`applyTextConversion`／`adjustOffsetForCfi`／`toOriginalRange`／`resolveDisplayRange`）與其鴨子定型介面（Range/Node 只需具備函式實際讀寫的屬性/方法）是本 Issue 內部使用的實作細節，不是 Issue 3-5 的既定介面；本計畫不承諾這些名稱/簽章對外穩定。
- 文字節點是否為文字節點的判斷，比照 `epubcfi.js:188` 既有 `isTextNode = node => node?.nodeType === 3 || node?.nodeType === 4` 的寫法慣例，直接比較數字字面量 `3`（不使用瀏覽器全域 `Node.TEXT_NODE`）——`text-conversion-walker.js` 需要在 Node.js 環境下零依賴可測試，`Node` 全域在 Node.js 下不存在。
- DOM Walker 排除清單固定為 `RT`／`SCRIPT`／`STYLE`（父元素 tagName，大寫比較），沿用 `extractSegmentsForSection()` 既有的 `RT`／`SCRIPT` 排除並比照 spec.md 指示新增 `STYLE`。
- `applyTextConversion()` 每個文字節點只在 `node._elinkOrigText === undefined` 時快取一次原文；任何模式轉換的輸入皆以這份快取為準，不得以目前 `node.nodeValue`（可能已是轉換後文字）作為輸入，否則多次模式切換會發生轉換結果污染（例如 toTraditional 轉換後的文字被誤當作原文再做 toSimplified 轉換）。
- **DOM Walker／CFI 座標保護的走訪根節點一律用 `doc.body ?? doc.documentElement ?? doc`**（2026-09-15 審查修正 I-2），不得只寫 `doc.body`——FXL／漫畫章節可能是以 `<svg>` 為根、無 `<body>` 的 XHTML 頁面，`doc.body` 為 `null`/`undefined` 時直接傳入 `doc.createTreeWalker(null, ...)` 會拋出 `TypeError`。此為 `readest/foliate-js` 釘定版本自己既有的既定模式（見 `text-walker.js:31` `x.commonAncestorContainer ?? x.body ?? x`），非本計畫新創。
- `currentTextConversion` 的即時切換觸發（`window.applyPreferences()` 內）必須在 `if (view.isFixedLayout) { ... return }` 分支（`main.js:214`）**之前**執行，讓 FXL EPUB/KF8（非 CBZ）章節同樣套用；`isIndexMode`（headless 索引 webview）下略過整段重新走訪。
- **即時切換簡繁模式後，必須重新觸發現有劃線/備註/搜尋高亮的重新解析與重繪**（2026-09-15 審查修正 I-1）：`applyTextConversion()` 只更新文字節點內容，不會通知 `Overlayer` 既有 `<rect>` 已經因文字重排而錯位；且若只呼叫 `Overlayer.redraw()`（重用舊 Range 物件），連續兩次不同長度的模式切換會讓舊 Range 的 offset 被瀏覽器依「文字內容變動時既有 Range 邊界點如何調整」這個規格上不夠明確的行為自動夾住，位置未必精確。正確做法是重新呼叫 `window.setDecorations()`（強制對每筆既有標記重新走一次 `resolveCFI()`），見 Task 3。

---

## File Structure

- Create: `app/android/app/src/main/assets/foliate/text-conversion-walker.js` — DOM Walker（`applyTextConversion`）＋ CFI 座標保護（`adjustOffsetForCfi`／`toOriginalRange`／`resolveDisplayRange`）。
- Create: `app/tool/test_apply_text_conversion.mjs` — `applyTextConversion()` Node 單元測試（手動最小化假 DOM）。
- Create: `app/tool/test_cfi_range_adjustment.mjs` — `adjustOffsetForCfi()`／`toOriginalRange()`／`resolveDisplayRange()` Node 單元測試（手動最小化假 DOM/Range）。
- Modify: `app/android/app/src/main/assets/foliate/main.js` — 匯入新模組、`view.getCFI`／`view.resolveCFI` 方法遮蔽、`currentTextConversion` 模組變數、`'load'` 監聽器與 `window.applyPreferences()` 觸發點接線。
- Modify: `app/lib/reader/foliate_reader_view.dart` — 新增 `textConversion` 建構參數，`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 更新。
- Modify: `app/test/reader/foliate_reader_view_test.dart` — 對應測試。
- Modify: `app/lib/screens/reader_screen.dart` — `_buildNativeView()` 傳入 `resolveTextConversion(_prefs, _loaded!.globalPrefs.reading)`。
- Modify: `app/test/screens/reader_screen_test.dart` — 對應 widget test。
- Modify: `app/integration_test/foliate_highlights_notes_test.dart` — CFI 穩定性回歸測試（模式切換後既有劃線仍正確解析）。

---

### Task 1: `text-conversion-walker.js`——DOM Walker ＋ CFI 座標保護純函式

**Files:**
- Create: `app/android/app/src/main/assets/foliate/text-conversion-walker.js`
- Create: `app/tool/test_apply_text_conversion.mjs`
- Create: `app/tool/test_cfi_range_adjustment.mjs`

**Interfaces:**
- Consumes: `app/android/app/src/main/assets/foliate/text-conversion.js` 的 `applyTextConversionToString(text, mode)`（Issue 0b）；`text-offset-map.js` 的 `origToDisplay(offsetMap, offset)`／`displayToOrig(offsetMap, offset, snapPolicy)`（Issue 0b）。
- Produces：`applyTextConversion(doc, mode)`、`adjustOffsetForCfi(node, offset, direction)`、`toOriginalRange(liveRange)`、`resolveDisplayRange(doc, anchor)`，供 Task 2/3 的 `main.js` 消費。

- [ ] **Step 1: 寫失敗測試（`applyTextConversion`）**

建立 `app/tool/test_apply_text_conversion.mjs`：

```js
// epic-42-text-conversion Issue 2：applyTextConversion() DOM Walker 驗證
// 腳本。零 npm 依賴，只用最小化手動 DOM stub（不含真實 TreeWalker/Node
// 實作，只實作本函式實際用到的子集），比照 app/tool 既有 .mjs 測試腳本
// 慣例。
//
// 用法：node app/tool/test_apply_text_conversion.mjs

import assert from 'node:assert/strict'
import { applyTextConversion } from '../android/app/src/main/assets/foliate/text-conversion-walker.js'

// applyTextConversion() 依賴標準瀏覽器全域 NodeFilter；main.js 實際執行
// 時由 WebView 提供，這裡補上等效常數，不需要完整 DOM 函式庫。
globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 }

class FakeTextNode {
  constructor(text, parentTagName) {
    this.nodeValue = text
    this.parentElement = { tagName: parentTagName }
  }
}

function makeFakeDoc(nodes, { body = {}, documentElement = {} } = {}) {
  return {
    body,
    documentElement,
    createTreeWalker(root, _whatToShow, { acceptNode }) {
      // 記錄實際傳入的 root，供下方「SVG/無 <body> 文件」測試斷言走訪
      // 根節點正確 fallback 到 documentElement（審查修正 I-2）。
      lastCreateTreeWalkerRoot = root
      let i = -1
      return {
        nextNode() {
          while (++i < nodes.length) {
            if (acceptNode(nodes[i]) === NodeFilter.FILTER_ACCEPT) return nodes[i]
          }
          return null
        },
      }
    },
  }
}

let lastCreateTreeWalkerRoot = null

// 基本轉換：多個文字節點皆套用轉換，各自快取 _elinkOrigText，非等長
// 詞彙替換節點建立 _elinkOffsetMap。
{
  const n1 = new FakeTextNode('内存', 'P')
  const n2 = new FakeTextNode('测试', 'P')
  const doc = makeFakeDoc([n1, n2])
  applyTextConversion(doc, 'toTraditional')
  assert.equal(n1.nodeValue, '記憶體')
  assert.equal(n1._elinkOrigText, '内存')
  assert.ok(n1._elinkOffsetMap)
  assert.equal(n2.nodeValue, '測試')
  assert.equal(n2._elinkOrigText, '测试')
}

// 排除 <rt>／<script>／<style> 底下的文字節點：acceptNode 回傳
// FILTER_REJECT，nextNode() 略過，完全不觸碰（連 _elinkOrigText 都不
// 快取）。
{
  const rt = new FakeTextNode('注音', 'RT')
  const script = new FakeTextNode('内存', 'SCRIPT')
  const style = new FakeTextNode('内存', 'STYLE')
  const doc = makeFakeDoc([rt, script, style])
  applyTextConversion(doc, 'toTraditional')
  assert.equal(rt.nodeValue, '注音')
  assert.equal(rt._elinkOrigText, undefined)
  assert.equal(script.nodeValue, '内存')
  assert.equal(style.nodeValue, '内存')
}

// SVG 為根、無 <body> 之 FXL 章節（審查修正 I-2）：doc.body 為 null 時
// 走訪根節點須 fallback 到 doc.documentElement，不得直接把 null 傳給
// createTreeWalker()（否則瀏覽器會拋 TypeError）。
{
  const n = new FakeTextNode('内存', 'P')
  const docElement = {}
  const doc = makeFakeDoc([n], { body: null, documentElement: docElement })
  applyTextConversion(doc, 'toTraditional')
  assert.equal(n.nodeValue, '記憶體')
  assert.equal(lastCreateTreeWalkerRoot, docElement)
}

// 原文還原（spec.md Testing Decisions 明訂）：含併字字元的文本，走過
// original -> toSimplified -> original 循環後，須與初始原文 100% 一致；
// _elinkOrigText 只在首次走訪快取一次，不會被中途轉換後的文字覆蓋。
{
  const n = new FakeTextNode('後乾坤', 'P')
  const doc = makeFakeDoc([n])
  applyTextConversion(doc, 'original')
  assert.equal(n.nodeValue, '後乾坤')
  assert.equal(n._elinkOffsetMap, null)

  applyTextConversion(doc, 'toSimplified')
  assert.notEqual(n.nodeValue, '後乾坤')
  assert.equal(n._elinkOrigText, '後乾坤')

  applyTextConversion(doc, 'original')
  assert.equal(n.nodeValue, '後乾坤')
  assert.equal(n._elinkOffsetMap, null)
}

console.log('[test_apply_text_conversion] 全部通過')
```

Run: `node app/tool/test_apply_text_conversion.mjs`
Expected: 錯誤（找不到 `../android/app/src/main/assets/foliate/text-conversion-walker.js`）。

- [ ] **Step 2: 寫失敗測試（`adjustOffsetForCfi`／`toOriginalRange`／`resolveDisplayRange`）**

建立 `app/tool/test_cfi_range_adjustment.mjs`：

```js
// epic-42-text-conversion Issue 2：CFI 座標保護純函式驗證腳本（見
// docs/epics/epic-42-text-conversion/offset-mapping-spec.md 第 3.2 節，
// 2026-09-15 依 reviews/review-plan-issue-2.md Issue C-1／C-2 修訂）。
// 零 npm 依賴，只用最小化手動 DOM/Range stub。
//
// 用法：node app/tool/test_cfi_range_adjustment.mjs

import assert from 'node:assert/strict'
import {
  adjustOffsetForCfi,
  toOriginalRange,
  resolveDisplayRange,
} from '../android/app/src/main/assets/foliate/text-conversion-walker.js'
import { createOffsetMapBuilder } from '../android/app/src/main/assets/foliate/text-offset-map.js'

// resolveDisplayRange() 依賴標準瀏覽器全域 NodeFilter；main.js 實際執行
// 時由 WebView 提供，這裡補上等效常數。
globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 }

function buildMap(segments) {
  const builder = createOffsetMapBuilder()
  for (const s of segments) {
    builder.addSegment(s.origOffset, s.origLen, s.dispOffset, s.dispLen)
  }
  return builder.build()
}

const textNode = (nodeValue, offsetMap, origText) => (
  { nodeType: 3, nodeValue, _elinkOffsetMap: offsetMap, _elinkOrigText: origText ?? nodeValue }
)
const elementNode = () => ({ nodeType: 1 })

// ---------------------------------------------------------------------
// adjustOffsetForCfi
// ---------------------------------------------------------------------

// offsetMap 為 null 時原樣回傳（97.6% 零開銷路徑）。
{
  const node = textNode('一二三', null)
  assert.equal(adjustOffsetForCfi(node, 2, 'displayToOrig-floor'), 2)
  assert.equal(adjustOffsetForCfi(node, 2, 'origToDisplay'), 2)
}

// 「内存」(2) -> 「記憶體」(3)：置換詞中間的 floor/ceil 貼齊，詞尾之後
// 正確累加 delta。
{
  const map = buildMap([{ origOffset: 0, origLen: 2, dispOffset: 0, dispLen: 3 }])
  const node = textNode('記憶體', map)
  assert.equal(adjustOffsetForCfi(node, 2, 'displayToOrig-floor'), 0)
  assert.equal(adjustOffsetForCfi(node, 2, 'displayToOrig-ceil'), 2)
  assert.equal(adjustOffsetForCfi(node, 2, 'origToDisplay'), 3)
}

// 「公共汽車」(4) -> 「公車」(2)：縮短案例，origToDisplay 須夾在顯示
// 文字長度內，否則會指向 nodeValue 長度以外的位置。
{
  const map = buildMap([{ origOffset: 0, origLen: 4, dispOffset: 0, dispLen: 2 }])
  const node = textNode('公車', map)
  assert.equal(adjustOffsetForCfi(node, 3, 'origToDisplay'), 2)
}

// ---------------------------------------------------------------------
// toOriginalRange（審查修正 C-1：回傳純資料物件，不得建構真實 Range／
// 呼叫 cloneRange()／setStart()／setEnd()——縮短詞情境下對 live DOM
// 節點呼叫 setEnd(node, 原文 offset) 會直接拋出 IndexSizeError，見
// Global Constraints）。
// ---------------------------------------------------------------------

// 非文字節點邊界（例如 selectNodeContents(element) 產生的 Range）原樣
// 跳過，不嘗試存取不存在的 _elinkOffsetMap。
{
  const el = elementNode()
  const range = { startContainer: el, startOffset: 0, endContainer: el, endOffset: 1 }
  const result = toOriginalRange(range)
  assert.equal(result.startOffset, 0)
  assert.equal(result.endOffset, 1)
}

// 縮短詞核心回歸（審查修正 C-1 核心案例）：使用者選取顯示文字「公車」
// 全部 2 個字元（liveRange.endOffset = 2，恰為 live DOM 節點目前的實際
// 長度），換算為原文座標時必須能安全回傳 4（原文「公共汽車」長度），
// 即使 4 已超出目前顯示節點的長度——toOriginalRange() 回傳純資料物件，
// 不受 DOM Range 邊界長度限制，不會拋出 IndexSizeError。
{
  const map = buildMap([{ origOffset: 0, origLen: 4, dispOffset: 0, dispLen: 2 }])
  const node = textNode('公車', map, '公共汽車')
  const liveRange = { startContainer: node, startOffset: 0, endContainer: node, endOffset: 2 }
  const origRange = toOriginalRange(liveRange)
  assert.equal(origRange.startOffset, 0)
  assert.equal(origRange.endOffset, 4)
}

// 一般增長詞：selection 落在「記憶體」中間（displayOffset 2）到節點
// 結尾（displayOffset 3），換算成原文座標應為 [0, 2]（對應原文「内存」
// 整個範圍）。
{
  const map = buildMap([{ origOffset: 0, origLen: 2, dispOffset: 0, dispLen: 3 }])
  const node = textNode('記憶體', map, '内存')
  const liveRange = { startContainer: node, startOffset: 2, endContainer: node, endOffset: 3 }
  const origRange = toOriginalRange(liveRange)
  assert.equal(origRange.startOffset, 0)
  assert.equal(origRange.endOffset, 2)
}

// null Range 安全直接回傳。
{
  assert.equal(toOriginalRange(null), null)
}

// ---------------------------------------------------------------------
// resolveDisplayRange（審查修正 C-2：呼叫真正的 anchor(doc)/CFI.toRange()
// 之前，先把已轉換節點暫時復原成原文，讓其內部呼叫 Range.setStart/
// setEnd() 時比對的 offset 與暫時還原後的文字長度一致，不拋出
// IndexSizeError；取得結果後立即讀出邊界，復原顯示文字，最後才用
// adjustOffsetForCfi('origToDisplay') 算出安全座標建立全新 Range）。
// ---------------------------------------------------------------------

// 最小化手動 FakeRange／FakeDocument：只實作 resolveDisplayRange() 實際
// 用到的子集（doc.createTreeWalker／doc.createRange／Range.setStart／
// setEnd／四個邊界屬性），比照 test_apply_text_conversion.mjs 既有慣例，
// 不引入任何 npm 依賴。
class FakeRange {
  setStart(node, offset) {
    this.startContainer = node
    this.startOffset = offset
  }
  setEnd(node, offset) {
    this.endContainer = node
    this.endOffset = offset
  }
}

function makeFakeDoc(nodes) {
  return {
    body: {},
    createTreeWalker(_root, _whatToShow, { acceptNode }) {
      let i = -1
      return {
        nextNode() {
          while (++i < nodes.length) {
            if (acceptNode(nodes[i]) === NodeFilter.FILTER_ACCEPT) return nodes[i]
          }
          return null
        },
      }
    },
    createRange() {
      return new FakeRange()
    },
  }
}

// 縮短詞核心回歸（審查修正 C-2 核心案例）：CFI 記錄的原文 offset（5）
// 落在「公共汽車」縮短為「公車」之後（詞尾之後的位置，原文「公共汽車站」
// 長度 5）。[anchor] 模擬「未受保護的原始 CFI.toRange()」：直接對節點
// 目前的 nodeValue 長度呼叫等效 setEnd 邊界檢查，只有在節點暫時復原成
// 原文（長度 5）時才不會拋出，藉此驗證 resolveDisplayRange() 確實在
// 呼叫 anchor(doc) 之前就完成了暫時復原。
{
  const map = buildMap([{ origOffset: 0, origLen: 4, dispOffset: 0, dispLen: 2 }])
  const node = textNode('公車站', map, '公共汽車站')
  const doc = makeFakeDoc([node])
  const anchor = (d) => {
    if (5 > node.nodeValue.length) {
      throw new Error(`IndexSizeError: offset 5 超出節點長度 ${node.nodeValue.length}`)
    }
    const range = d.createRange()
    range.setStart(node, 0)
    range.setEnd(node, 5)
    return range
  }
  const result = resolveDisplayRange(doc, anchor)
  assert.ok(result)
  assert.equal(result.startOffset, 0)
  // 原文 offset 5（「公共汽車」詞尾之後）換算顯示座標：
  // 5 + accumDelta(0) + delta(-2) = 3，恰為「公車站」的顯示長度。
  assert.equal(result.endOffset, 3)
  // 呼叫結束後節點必須已復原回顯示文字，不停留在暫時還原用的原文狀態。
  assert.equal(node.nodeValue, '公車站')
}

// anchor(doc) 回傳 null（CFI 解析失敗，例如 epubcfi.js CFI.toRange()
// 內部例外被其自身 try/catch 吞掉）時，安全回傳 null，且已復原顯示
// 文字（不停留在暫時還原用的原文狀態）。
{
  const map = buildMap([{ origOffset: 0, origLen: 2, dispOffset: 0, dispLen: 3 }])
  const node = textNode('記憶體', map, '内存')
  const doc = makeFakeDoc([node])
  const result = resolveDisplayRange(doc, () => null)
  assert.equal(result, null)
  assert.equal(node.nodeValue, '記憶體')
}

// 未受影響的節點（_elinkOffsetMap 為 null，佔 97.6%）：resolveDisplayRange
// 完全不觸碰其 nodeValue，anchor(doc) 可直接安全解析，結果與原文/顯示
// 座標恆等。
{
  const doc = makeFakeDoc([])
  const range = new FakeRange()
  range.setStart({ nodeType: 3, nodeValue: '不變的文字', _elinkOffsetMap: null }, 1)
  range.setEnd(range.startContainer, 3)
  const result = resolveDisplayRange(doc, () => range)
  assert.equal(result.startOffset, 1)
  assert.equal(result.endOffset, 3)
}

console.log('[test_cfi_range_adjustment] 全部通過')
```

Run: `node app/tool/test_cfi_range_adjustment.mjs`
Expected: 錯誤（找不到 `text-conversion-walker.js`）。

- [ ] **Step 3: 執行兩支測試腳本，確認皆失敗**

Run: `node app/tool/test_apply_text_conversion.mjs && node app/tool/test_cfi_range_adjustment.mjs`
Expected: 兩者皆因找不到模組而失敗（`ERR_MODULE_NOT_FOUND`）。

- [ ] **Step 4: 建立 `text-conversion-walker.js`**

建立 `app/android/app/src/main/assets/foliate/text-conversion-walker.js`：

```js
// epic-42-text-conversion Issue 2：main.js 消費的 DOM Walker 與 CFI 座標
// 保護邏輯（見 docs/epics/epic-42-text-conversion/offset-mapping-spec.md
// 第 3 節；2026-09-15 依 reviews/review-plan-issue-2.md Issue C-1／C-2
// 修訂）。抽成獨立模組（而非直接寫在 main.js）：main.js 頂層會呼叫
// document.getElementById()／openBook()（模組級副作用，無法在 Node.js
// 環境下 import），這裡只依賴標準 DOM API 的極小鴨子定型子集（TreeWalker
// 的 acceptNode 回呼；`resolveDisplayRange()` 是唯一需要建構真實 Range
// 的函式，`toOriginalRange()` 只讀取屬性、不呼叫任何 Range 方法，見其
// 文件註解），比照同目錄 text-conversion.js／text-offset-map.js 既有
// 「零 DOM 依賴，可用 Node.js 完整單元測試」慣例，見
// app/tool/test_apply_text_conversion.mjs／test_cfi_range_adjustment.mjs。

import { applyTextConversionToString } from './text-conversion.js'
import { origToDisplay, displayToOrig } from './text-offset-map.js'

const EXCLUDED_TAGS = new Set(['RT', 'SCRIPT', 'STYLE'])

/**
 * 走訪 [doc]（章節 Document）內的可見文字節點，依 [mode] 套用簡繁轉換
 * （issues.md Issue 2「範圍」）。排除清單沿用 main.js
 * extractSegmentsForSection() 既有的 RT／SCRIPT，另加 STYLE。
 *
 * 每個文字節點首次走訪時把原文快取至 `_elinkOrigText`；之後任何模式
 * 切換皆以這份快取為轉換輸入基準（而非目前已轉換過的 `nodeValue`），
 * 保證 original → toTraditional → toSimplified → original 循環後文字
 * 100% 還原（Global Constraints）。
 * @param {Document} doc
 * @param {'original' | 'toTraditional' | 'toSimplified'} mode
 */
export function applyTextConversion(doc, mode) {
  // 審查修正 I-2：FXL／漫畫章節可能是以 <svg> 為根、無 <body> 的 XHTML
  // 頁面，doc.body 為 null 時不得直接傳給 createTreeWalker()（會拋
  // TypeError）。比照 readest/foliate-js 釘定版本自己既有的
  // text-walker.js:31（`x.commonAncestorContainer ?? x.body ?? x`）。
  const root = doc.body ?? doc.documentElement ?? doc
  const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => {
      const tag = node.parentElement
        ? node.parentElement.tagName.toUpperCase()
        : ''
      return EXCLUDED_TAGS.has(tag)
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT
    },
  })
  let node = walker.nextNode()
  while (node) {
    if (node._elinkOrigText === undefined) node._elinkOrigText = node.nodeValue
    const { text, offsetMap } = applyTextConversionToString(node._elinkOrigText, mode)
    node._elinkOffsetMap = offsetMap
    if (node.nodeValue !== text) node.nodeValue = text
    node = walker.nextNode()
  }
}

/**
 * 依（可能為 null 的）`_elinkOffsetMap` 調整單一邊界 offset。[node] 只需
 * 鴨子定型具備 `nodeValue`／`_elinkOffsetMap` 兩個屬性，不要求是真實 DOM
 * 節點——讓本函式可離開瀏覽器環境以純資料物件單元測試。
 *
 * [direction]：
 * - `'displayToOrig-floor'`：選取起點（顯示座標 → 原文座標，貼齊置換詞
 *   起點）。
 * - `'displayToOrig-ceil'`：選取終點（貼齊置換詞終點）。
 * - `'origToDisplay'`：CFI 還原（原文座標 → 顯示座標），夾在目前
 *   `nodeValue` 長度內，避免 `Range.setStart/setEnd()` 拋出
 *   `IndexSizeError`。
 * @param {{ nodeValue: string, _elinkOffsetMap?: object | null } | null} node
 * @param {number} offset
 * @param {'displayToOrig-floor' | 'displayToOrig-ceil' | 'origToDisplay'} direction
 * @returns {number}
 */
export function adjustOffsetForCfi(node, offset, direction) {
  const map = node ? node._elinkOffsetMap : null
  if (direction === 'origToDisplay') {
    const dispOffset = origToDisplay(map, offset)
    return node && typeof node.nodeValue === 'string'
      ? Math.min(dispOffset, node.nodeValue.length)
      : dispOffset
  }
  return displayToOrig(map, offset, direction === 'displayToOrig-ceil' ? 'ceil' : 'floor')
}

// 文字節點型別判斷比照 epubcfi.js:188 既有 isTextNode 寫法（直接比較數字
// 字面量 3，不用瀏覽器全域 Node.TEXT_NODE——本模組需要在 Node.js 環境下
// 零依賴可測試，Node 全域在 Node.js 下不存在）。
const isTextNode = (node) => node && node.nodeType === 3

/**
 * 使用者在畫面選取文字建立劃線時（`view.getCFI()` 呼叫
 * `epubcfi.fromRange()` 之前），把即時選取範圍（座標基於目前顯示/已轉換
 * 的文字）換算為原文座標，保證存入的 CFI 恆對應原始 EPUB 文本
 * （offset-mapping-spec.md 3.2.1 節）。
 *
 * **審查修正 C-1：回傳純資料物件，絕不建構真實 DOM `Range`（不呼叫
 * `cloneRange()`/`setStart()`/`setEnd()`）**——已查證 `epubcfi.js:302-308`
 * 的 `fromRange()` 只解構讀取 `startContainer`/`startOffset`/
 * `endContainer`/`endOffset`/`collapsed` 五個屬性，從未呼叫任何 DOM
 * Range 方法。若對 live DOM 文字節點（目前顯示長度可能已縮短，例如
 * 「公共汽車」(4)→「公車」(2)）呼叫 `Range.setEnd(node, 原文 offset)`，
 * 原文 offset 極可能超出目前顯示長度，瀏覽器會依 W3C 規範立即拋出
 * `IndexSizeError`。[liveRange] 只需鴨子定型具備 `startContainer`／
 * `startOffset`／`endContainer`／`endOffset`——正式環境直接傳入真實
 * `Range` 即可（只讀取屬性，不呼叫其方法）。
 * @param {object | null} liveRange
 */
export function toOriginalRange(liveRange) {
  if (!liveRange) return liveRange
  const startOffset = isTextNode(liveRange.startContainer)
    ? adjustOffsetForCfi(liveRange.startContainer, liveRange.startOffset, 'displayToOrig-floor')
    : liveRange.startOffset
  const endOffset = isTextNode(liveRange.endContainer)
    ? adjustOffsetForCfi(liveRange.endContainer, liveRange.endOffset, 'displayToOrig-ceil')
    : liveRange.endOffset
  return {
    startContainer: liveRange.startContainer,
    startOffset,
    endContainer: liveRange.endContainer,
    endOffset,
    collapsed: liveRange.startContainer === liveRange.endContainer && startOffset === endOffset,
  }
}

/**
 * CFI 還原劃線時（`view.resolveCFI()` 內）：安全地把 [anchor]（真正的
 * vendored `doc => CFI.toRange(doc, parts)` 閉包，未經修改）解析出的
 * Range 從原文座標調整為顯示座標（offset-mapping-spec.md 3.2.2 節）。
 *
 * **審查修正 C-2：不對 `anchor(doc)` 的回傳值做事後調整**——
 * `CFI.toRange()` 內部用 CFI 儲存的原文 offset 直接對「目前顯示中（可能
 * 已轉換、長度較短）」的 live 文字節點呼叫 `Range.setStart/setEnd()`，
 * 縮短詞情境下該 offset 可能超出目前顯示文字長度，瀏覽器會在
 * `CFI.toRange()` 內部就拋出 `IndexSizeError`，被其自身的
 * `try { ... } catch { return null }` 吞掉回傳 `null`——事後調整根本
 * 沒有機會執行。
 *
 * 改為：呼叫 [anchor] 之前，把 [doc] 內所有曾被轉換過的文字節點
 * （`_elinkOffsetMap` 非 null）暫時復原成 `_elinkOrigText`，讓
 * `CFI.toRange()` 內部比對的 offset 與暫時還原後的文字長度一致，保證
 * 不拋例外；取得結果後立即讀出邊界節點/offset（此時文字仍是原文，
 * offset 與 CFI 儲存值一致），再復原回顯示文字，最後用
 * `adjustOffsetForCfi('origToDisplay')` 算出安全的顯示座標，建立一個
 * 全新的 `Range` 回傳（不重用/事後修改舊 Range 物件，避免依賴瀏覽器對
 * 「文字內容變動時既有 Range 邊界點如何調整」這個規格上不夠明確、跨
 * 引擎可能有差異的行為）。全程沒有重新實作 `epubcfi.js` 的 CFI 解析
 * 演算法（id-based 查找／cfi-skip／cfi-inert／相鄰文字節點合併等既有
 * 複雜邏輯皆原封不動由真正的 vendored `CFI.toRange()` 處理，只是暫時
 * 改變它「看到」的文字內容）。
 * @param {Document} doc
 * @param {(doc: Document) => object | null} anchor
 * @returns {object | null}
 */
export function resolveDisplayRange(doc, anchor) {
  const root = doc.body ?? doc.documentElement ?? doc
  const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (node._elinkOffsetMap ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT),
  })
  const swapped = []
  let node = walker.nextNode()
  while (node) {
    swapped.push({ node, displayValue: node.nodeValue })
    node.nodeValue = node._elinkOrigText
    node = walker.nextNode()
  }

  let captured = null
  try {
    const origRange = anchor(doc)
    if (origRange) {
      captured = {
        startContainer: origRange.startContainer,
        startOffset: origRange.startOffset,
        endContainer: origRange.endContainer,
        endOffset: origRange.endOffset,
      }
    }
  } finally {
    for (const { node: n, displayValue } of swapped) n.nodeValue = displayValue
  }
  if (!captured) return null

  const range = doc.createRange()
  range.setStart(
    captured.startContainer,
    isTextNode(captured.startContainer)
      ? adjustOffsetForCfi(captured.startContainer, captured.startOffset, 'origToDisplay')
      : captured.startOffset,
  )
  range.setEnd(
    captured.endContainer,
    isTextNode(captured.endContainer)
      ? adjustOffsetForCfi(captured.endContainer, captured.endOffset, 'origToDisplay')
      : captured.endOffset,
  )
  return range
}
```

- [ ] **Step 5: 執行測試，確認通過**

Run: `node app/tool/test_apply_text_conversion.mjs && node app/tool/test_cfi_range_adjustment.mjs`
Expected: 兩者皆印出「全部通過」，exit code 0。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/text-conversion-walker.js app/tool/test_apply_text_conversion.mjs app/tool/test_cfi_range_adjustment.mjs
git commit -m "feat(reader): 新增 text-conversion-walker.js（DOM Walker + CFI 座標保護）"
```

---

### Task 2: `main.js` CFI 座標保護接線（`view.getCFI`／`view.resolveCFI` 方法遮蔽）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 `toOriginalRange(liveRange)`／`resolveDisplayRange(doc, anchor)`。
- Produces：`view.getCFI`／`view.resolveCFI` 兩個實例方法皆已套用 CFI 座標保護，供 Task 3 的觸發點與既有呼叫點（`reportSelection()`／`buildTocEntry()`／`extractSegmentsForSection()`／`view.js` 內部 `#onRelocate()`）透明消費，無需個別修改。

本 Task 無法用 Node.js 單元測試驗證（`view` 是真實 WebView 自訂元素實例），正確性由 Task 6 的真機整合測試與本 Task 的 `check_foliate_es_compat.js` 靜態掃描把關。

- [ ] **Step 1: 修改 `main.js` 加入 import 與方法遮蔽**

在 `main.js` 第 1-4 行既有 import 陳述式之後新增：

```js
import { toOriginalRange, resolveDisplayRange } from './text-conversion-walker.js'
```

在第 6 行 `const view = document.getElementById('view')` 之後新增：

```js

// epic-42-text-conversion Issue 2：CFI 座標保護（見
// docs/epics/epic-42-text-conversion/offset-mapping-spec.md 第 3.2
// 節；2026-09-15 依 reviews/review-plan-issue-2.md Issue C-2 修訂）。
// view.getCFI()／view.resolveCFI() 是 view.js（釘定 vendor 檔案，
// ADR 0011 禁止修改）僅有的兩個 Range↔CFI 轉換入口，main.js 自己的
// reportSelection()／buildTocEntry()／extractSegmentsForSection()，以及
// view.js 內部 #onRelocate()（算「目前閱讀位置」CFI，main.js 完全沒有
// 對應呼叫點）全部流經這兩個公開方法。在實例上直接賦值會建立一個遮蔽
// 原型方法的自有屬性（標準 JS own-property shadowing），讓上述「全部
// 呼叫點」自動套用這層轉換，不需要逐一修改各呼叫點，也不修改 view.js
// 原始碼本身。buildTocEntry()／extractSegmentsForSection() 是對
// view.book.sections[i].createDocument() 產生的獨立、從未被
// applyTextConversion() 觸碰過的新文件操作，其文字節點沒有
// _elinkOffsetMap，toOriginalRange()／resolveDisplayRange() 對它們是
// 恆等變換，這個全域攔截不會影響 TTS／目錄既有的「CFI 永遠對應原文」
// 不變量（Global Constraints）。
//
// view.resolveCFI 刻意不寫成「事後調整 anchor(doc) 的回傳值」（例如
// (doc) => adjustXxx(anchor(doc))）——anchor(doc) 內部呼叫真正的
// CFI.toRange()，其 range.setEnd() 直接用原文 offset 對目前顯示中（可能
// 已轉換、長度較短）的 live 節點呼叫瀏覽器原生 Range API，縮短詞情境下
// 會在 anchor(doc) 內部就拋出 IndexSizeError 並被其自身 try/catch 吞成
// null，事後調整完全沒有機會執行（詳見 resolveDisplayRange() 文件註解與
// 審查報告 Issue C-2）。resolveDisplayRange(doc, anchor) 把 anchor 整個
// 閉包原封不動傳進去，由它自己負責在呼叫前後做暫時文字復原。
const originalGetCFI = view.getCFI.bind(view)
view.getCFI = (index, range) => originalGetCFI(index, toOriginalRange(range))

const originalResolveCFI = view.resolveCFI.bind(view)
view.resolveCFI = (cfi) => {
  const resolved = originalResolveCFI(cfi)
  if (!resolved) return resolved
  const { index, anchor } = resolved
  return { index, anchor: (doc) => resolveDisplayRange(doc, anchor) }
}
```

- [ ] **Step 2: 執行 `check_foliate_es_compat.js` 確認乾淨**

Run: `node app/tool/check_foliate_es_compat.js`
Expected: `[check_foliate_es_compat] 乾淨——目前已知的較新 ES 內建方法用法都已有對應 polyfill 防護。`（exit code 0）

- [ ] **Step 3: 人工核對（無法自動化的把關步驟）**

重新讀取修改後的 `main.js` 第 1-40 行左右，確認：
1. `import { toOriginalRange, resolveDisplayRange } from './text-conversion-walker.js'` 確實加入且路徑正確。
2. `view.getCFI`／`view.resolveCFI` 的賦值語句確實在 `const view = document.getElementById('view')`（第 6 行）之後、`openBook()` 實際呼叫（檔案最底部第 1385 行）之前——模組級程式碼由上而下依序執行，只要順序正確即保證修補在任何呼叫發生前就緒。
3. 沒有動到 `view.js`／`epubcfi.js` 等 vendor 檔案任何一行（`git status` 只應顯示 `main.js` 被修改）。

- [ ] **Step 4: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(reader): main.js 對 view.getCFI/resolveCFI 做 CFI 座標保護方法遮蔽"
```

---

### Task 3: `main.js` DOM Walker 觸發點接線

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 `applyTextConversion(doc, mode)`；Task 4 的 `FoliateReaderView.textConversion`（透過既有 `buildFoliatePreferencesMap()` 管線送入的 `prefs.textConversion` 欄位）。
- Produces：無（葉節點接線，DOM Walker 對使用者可觀察的行為由 Task 6 整合測試驗證）。

- [ ] **Step 1: 修改 `main.js` 匯入 `applyTextConversion` 並新增 `currentTextConversion` 模組變數**

把 Task 2 新增的 import 陳述式：

```js
import { toOriginalRange, resolveDisplayRange } from './text-conversion-walker.js'
```

改為：

```js
import {
  applyTextConversion,
  toOriginalRange,
  resolveDisplayRange,
} from './text-conversion-walker.js'
```

找到第 82 行 `let lastAppliedPrefs = initialPrefs`，在其後（第 83 行空行之後、`decorationIdByCfi` 宣告之前）新增：

```js

// epic-42-text-conversion Issue 2：目前生效的簡繁顯示轉換模式（issues.md
// Issue 2「觸發與即時切換」），比照 currentWritingMode 既有模式——模組
// 層級可變狀態，初始值來自開書當下的 initialPrefs（見上方
// buildFoliatePreferencesMap()／_buildIndexUri() 的既有查詢字串管線），
// window.applyPreferences() 每次呼叫時視 prefs.textConversion 是否存在
// 更新。
let currentTextConversion = initialPrefs.textConversion || 'original'
```

找到第 92 行 `let decorationIdByCfi = new Map()`，在其後新增（審查修正 I-1：即時切換簡繁模式後需要重新觸發現有劃線/備註重新解析與重繪，見 Step 3；本欄位記錄 `window.setDecorations()` 最後一次收到的完整清單，供 Step 3 重新呼叫）：

```js

// epic-42-text-conversion Issue 2（審查修正 I-1）：window.setDecorations()
// 最後一次收到的完整清單，供簡繁模式切換後重新呼叫 window.setDecorations()
// 使用——見 window.applyPreferences() 內對 currentTextConversion 變動的
// 處理（Step 3）。
let lastDecorations = []
```

找到既有 `window.setDecorations = function (decorations) {`（第 434 行）：

```js
window.setDecorations = function (decorations) {
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi })
  }
  decorationIdByCfi = new Map()
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id)
    view.addAnnotation({ value: cfi, color, isUnderline })
```

改為（在函式開頭新增一行記錄）：

```js
window.setDecorations = function (decorations) {
  // epic-42-text-conversion Issue 2（審查修正 I-1）：記錄最後一次收到的
  // 完整清單，供簡繁模式切換後重新呼叫本函式使用。
  lastDecorations = decorations
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi })
  }
  decorationIdByCfi = new Map()
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id)
    view.addAnnotation({ value: cfi, color, isUnderline })
```

- [ ] **Step 2: 在既有 `'load'` 監聽器內呼叫 `applyTextConversion`**

找到第 1020-1027 行左右：

```js
    view.addEventListener('load', (e) => {
      // epic-10-search Issue 1：索引模式下不需要任何觸控/選取/劃線手勢
      // 初始化（headless webview 不會有真實觸控事件），提早 return 跳過
      // 這整段（見上方 isIndexMode 宣告處的說明）。
      if (isIndexMode) return
      const doc = e.detail.doc
      const index = e.detail.index
      const classifier = new TouchIntentClassifier()
```

改為（在 `const index = e.detail.index` 之後插入呼叫）：

```js
    view.addEventListener('load', (e) => {
      // epic-10-search Issue 1：索引模式下不需要任何觸控/選取/劃線手勢
      // 初始化（headless webview 不會有真實觸控事件），提早 return 跳過
      // 這整段（見上方 isIndexMode 宣告處的說明）。
      if (isIndexMode) return
      const doc = e.detail.doc
      const index = e.detail.index
      // epic-42-text-conversion Issue 2：新章節載入／look-ahead 預讀章節
      // 時套用目前生效的簡繁轉換模式（issues.md Issue 2「開書當下與逐
      // section 觸發」）。currentTextConversion 此時已由上方模組層級宣告
      // 賦予 initialPrefs 的初始值，不依賴 window.applyPreferences() 是否
      // 已執行過。
      applyTextConversion(doc, currentTextConversion)
      const classifier = new TouchIntentClassifier()
```

- [ ] **Step 3: 在 `window.applyPreferences()` 內新增即時切換觸發**

找到第 194-214 行左右：

```js
window.applyPreferences = function (prefs) {
  // Issue 9：每次套用偏好都同步記錄下來，供 openBook() 內的
  // ResizeObserver debounce callback 在裝置旋轉/視窗尺寸變化後，能重新
  // 呼叫本函式並拿到「使用者最後一次實際設定的完整偏好」，而不是只拿到
  // 旋轉當下手邊剛好有的局部資料。
  lastAppliedPrefs = prefs

  // epic-26-architecture-hardening Issue 11：字級/行距/段落間距/邊距/
  // 單雙欄/螢幕方向/直橫排切換全部流經這個唯一入口，任一項改變都會讓
  // SectionProgress 已記錄的密度校正資料失真，整包清空重算（FXL 書籍
  // 沒有這筆資料，clearLocationDensity() 內部為 no-op，此處無條件呼叫
  // 不需要額外判斷 isFixedLayout，見 plans/plan-issue-11.md 規劃階段
  // 查證第 3 點）。
  view.clearLocationDensity()

  // Epic 20 Issue 2：FXL（定樣式）書籍不套用流式（reflowable） Paginator
  // 專屬的排版參數。`foliate-fxl` 的 observedAttributes 只有
  // ['zoom', 'scale-factor', 'spread', 'flow', 'scroll-gap']，其中只有
  // flow 共通；setStyles() 對 foliate-fxl 完全不存在（呼叫會拋 TypeError）。
  // FXL 書籍本質上是圖片頁，無 reflow 概念，不需要字級/行距/邊距/CSS 覆蓋。
  if (view.isFixedLayout) {
```

改為（在 `view.clearLocationDensity()` 之後、`if (view.isFixedLayout) {` 之前插入）：

```js
window.applyPreferences = function (prefs) {
  // Issue 9：每次套用偏好都同步記錄下來，供 openBook() 內的
  // ResizeObserver debounce callback 在裝置旋轉/視窗尺寸變化後，能重新
  // 呼叫本函式並拿到「使用者最後一次實際設定的完整偏好」，而不是只拿到
  // 旋轉當下手邊剛好有的局部資料。
  lastAppliedPrefs = prefs

  // epic-26-architecture-hardening Issue 11：字級/行距/段落間距/邊距/
  // 單雙欄/螢幕方向/直橫排切換全部流經這個唯一入口，任一項改變都會讓
  // SectionProgress 已記錄的密度校正資料失真，整包清空重算（FXL 書籍
  // 沒有這筆資料，clearLocationDensity() 內部為 no-op，此處無條件呼叫
  // 不需要額外判斷 isFixedLayout，見 plans/plan-issue-11.md 規劃階段
  // 查證第 3 點）。
  view.clearLocationDensity()

  // epic-42-text-conversion Issue 2：簡繁轉換閱讀中即時切換（issues.md
  // Issue 2「閱讀中即時切換」）。刻意放在下方 FXL isFixedLayout early
  // return 之前——FXL EPUB/KF8（非 CBZ）章節同樣是含真實文字的 XHTML
  // 文件，也需要套用（Global Constraints）；isIndexMode 下的 headless
  // webview 沒有實際渲染中的內容需要走訪，略過即可，全文檢索索引一律讀取
  // view.book.sections[i].createDocument() 產生的獨立未轉換文件（見
  // extractSegmentsForSection()），不受這裡影響。只在 textConversion 真的
  // 變動時才重新走訪，避免每次無關的偏好變更（字級/邊距等）都觸發一次
  // DOM 全文字節點掃描。
  const previousTextConversion = currentTextConversion
  if (prefs.textConversion) {
    currentTextConversion = prefs.textConversion
  }
  if (!isIndexMode && prefs.textConversion && prefs.textConversion !== previousTextConversion) {
    for (const { doc } of view.renderer.getContents()) {
      applyTextConversion(doc, currentTextConversion)
    }
    // 審查修正 I-1：applyTextConversion() 只更新文字節點內容，不會通知
    // Overlayer 既有 <rect> 已經因文字重排而錯位。重新呼叫
    // window.setDecorations() 強制對每筆既有標記重新走一次
    // view.resolveCFI()（Task 2 已修復其在縮短詞情境下的座標保護），
    // 依新的 _elinkOffsetMap 重新算出正確位置並重繪，而非只呼叫
    // Overlayer.redraw() 重用舊 Range——連續兩次不同長度的模式切換下，
    // 重用舊 Range 的 offset 會被瀏覽器依「文字內容變動時既有 Range
    // 邊界點如何調整」這個規格上不夠明確的行為自動夾住，位置未必精確。
    if (lastDecorations.length > 0) {
      window.setDecorations(lastDecorations)
    }
  }

  // Epic 20 Issue 2：FXL（定樣式）書籍不套用流式（reflowable） Paginator
  // 專屬的排版參數。`foliate-fxl` 的 observedAttributes 只有
  // ['zoom', 'scale-factor', 'spread', 'flow', 'scroll-gap']，其中只有
  // flow 共通；setStyles() 對 foliate-fxl 完全不存在（呼叫會拋 TypeError）。
  // FXL 書籍本質上是圖片頁，無 reflow 概念，不需要字級/行距/邊距/CSS 覆蓋。
  if (view.isFixedLayout) {
```

- [ ] **Step 4: 執行 `check_foliate_es_compat.js` 確認乾淨**

Run: `node app/tool/check_foliate_es_compat.js`
Expected: `[check_foliate_es_compat] 乾淨——目前已知的較新 ES 內建方法用法都已有對應 polyfill 防護。`（exit code 0）

- [ ] **Step 5: 執行 Task 1 的兩支 Node 測試腳本，確認零回歸**

Run: `node app/tool/test_apply_text_conversion.mjs && node app/tool/test_cfi_range_adjustment.mjs`
Expected: 兩者皆印出「全部通過」。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(reader): main.js 接線 DOM Walker 觸發點（載入/即時切換）"
```

---

### Task 4: Dart↔JS 偏好橋接——`FoliateReaderView.textConversion`

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/text_conversion_mode.dart` 的 `TextConversionMode`（Issue 0）。
- Produces：`FoliateReaderView.textConversion`（`TextConversionMode?`）建構參數，`buildFoliatePreferencesMap()` 送出 `prefs.textConversion` 欄位（`.name` 字串，與 Task 3 main.js 的 `mode` 字面值 `'original'`／`'toTraditional'`／`'toSimplified'` 一致），供 Task 5 `reader_screen.dart` 消費。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/reader/foliate_reader_view_test.dart` 頂部 import 區塊（`import 'package:elinkbook/reader/zone_action.dart';` 之後）新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

在 `group('buildFoliatePreferencesMap', ...)`（第 62 行起）內，找到第 73-84 行 `'columnMode: single 時 map 含 columnMode: single'` 測試之後，新增：

```dart

    test('textConversion 非 null 時 map 含 textConversion 字串', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textConversion: TextConversionMode.toTraditional,
      );
      expect(buildFoliatePreferencesMap(view), {
        'textConversion': 'toTraditional',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('textConversion 為 null 時 map 不含 textConversion 欄位', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view).containsKey('textConversion'), isFalse);
    });
```

在 `group('foliatePreferencesChanged', ...)`（第 338 行起）內，找到第 355-369 行 `'writingMode 變動回傳 true'` 測試之後，新增：

```dart

    test('textConversion 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textConversion: TextConversionMode.original,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textConversion: TextConversionMode.toTraditional,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 編譯錯誤（`textConversion` 不是 `FoliateReaderView` 已知的具名參數）。

- [ ] **Step 3: 修改 `foliate_reader_view.dart` 加入新欄位**

在 import 區塊（`import 'writing_mode.dart';` 之後、`import 'zone_action.dart';` 之前）新增：

```dart
import 'text_conversion_mode.dart';
```

在 `FoliateReaderView` 欄位宣告（第 238 行 `final DualPageMode? dualPageMode;` 之後）新增：

```dart

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 2）：呼叫端
  /// （[ReaderScreen]）傳入 `resolveTextConversion()` 解析後的該書生效值
  /// （[BookReaderPrefs.textConversionOverride] ?? 全域
  /// [ReadingDefaults.textConversion]）。`null` 時 main.js 端沿用
  /// `initialPrefs.textConversion` 的既有預設（`'original'`，見 main.js
  /// `currentTextConversion` 模組變數宣告）。
  final TextConversionMode? textConversion;
```

在建構子參數列（`this.dualPageMode,` 之後）新增：

```dart
    this.textConversion,
```

在 `buildFoliatePreferencesMap()` 的 return map 組裝（`if (view.dualPageMode != null) map['dualPageMode'] = view.dualPageMode!.name;` 之後）新增：

```dart
  if (view.textConversion != null) {
    map['textConversion'] = view.textConversion!.name;
  }
```

在 `foliatePreferencesChanged()` 的比較鏈（`oldView.dualPageMode != newView.dualPageMode ||` 之後）新增：

```dart
      oldView.textConversion != newView.textConversion ||
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(reader): FoliateReaderView 新增 textConversion 建構參數"
```

---

### Task 5: `reader_screen.dart` 呼叫端接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/resolve_text_conversion.dart` 的 `resolveTextConversion(BookReaderPrefs, ReadingDefaults)`（Issue 1）；Task 4 的 `FoliateReaderView.textConversion`。
- Produces：無（葉節點接線）。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 頂部 import 區塊新增（若尚未存在）：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到既有「`FoliateReaderView` 建構參數斷言」風格的測試（例如第 175-206 行 `'Foliate：initialJumpTarget.cfi 優先於資料庫既有 lastPosition'`），在同一個 `group`／檔案內新增：

```dart

    testWidgets('Foliate：FoliateReaderView.textConversion 反映 resolveTextConversion() 解析結果（單書覆寫優先）',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_text_conversion': const BookReaderPrefs(
            textConversionOverride: TextConversionMode.toTraditional,
          ),
        },
        globalPrefs: GlobalReaderPrefs.initial().copyWith(
          reading: const ReadingDefaults(
            textConversion: TextConversionMode.toSimplified,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_text_conversion',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.textConversion, TextConversionMode.toTraditional);
    });

    testWidgets('Foliate：FoliateReaderView.textConversion 未覆寫時回退全域預設值',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        globalPrefs: GlobalReaderPrefs.initial().copyWith(
          reading: const ReadingDefaults(
            textConversion: TextConversionMode.toSimplified,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_text_conversion_fallback',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.textConversion, TextConversionMode.toSimplified);
    });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`FoliateReaderView.textConversion` 未被設定，實際值為 `null`，或編譯錯誤視 Task 4 是否已合併而定）。

- [ ] **Step 3: 修改 `reader_screen.dart` 加入呼叫端接線**

在 import 區塊（`import '../reader/resolved_preferences.dart';` 之後）新增：

```dart
import '../reader/resolve_text_conversion.dart';
```

找到 `_buildNativeView()` 方法開頭：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
```

改為：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    // epic-42-text-conversion Issue 2：_resolved 非 null 時 _loaded 恆非
    // null（兩者在 initState()／_handlePrefsChanged() 內永遠同時賦值，見
    // resolve_text_conversion.dart 呼叫端查證）。
    final textConversionMode =
        resolveTextConversion(_prefs, _loaded!.globalPrefs.reading);
    switch (format) {
```

在 `FoliateReaderView(...)` 建構參數列（`dualPageMode: resolved.dualPageMode,` 之後）新增：

```dart
          textConversion: textConversionMode,
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(screens): reader_screen.dart 傳入 resolveTextConversion() 解析結果至 FoliateReaderView"
```

---

### Task 6: CFI 穩定性回歸整合測試（真機）＋ 收尾驗證

**Files:**
- Modify: `app/integration_test/foliate_highlights_notes_test.dart`

**Interfaces:**
- Consumes：Task 1-5 的完整管線（`ReaderSettingsSheet` 的 `Key('reader_settings_text_conversion_traditional')` 選擇器，Epic 42 Issue 1 既有交付）。
- Produces：無（本計畫最後一個 Task，收尾為完整驗證）。

**必須在真實 Android 裝置/模擬器上執行**（`-d <device-id>`），比照 `CLAUDE.md`「兩層測試架構」——本步驟無法在本機純 Dart 測試環境下驗證，也無法由本計畫的撰寫/執行過程自動確認通過，需人工在真機上執行後回報結果。

- [ ] **Step 1: 新增 CFI 穩定性回歸測試**

在 `app/integration_test/foliate_highlights_notes_test.dart` 的 `testWidgets('Foliate 流式 EPUB：預先寫入 CFI 劃線＋備註，NotesBottomSheet 正確顯示並可互動', ...)` 測試結尾（第 172 行 `});` 之後、`main()` 結尾的 `}` 之前）新增：

```dart

  // 審查修正 I-3：本測試使用的既有 fixture（sample_multi_chapter.epub）
  // 與下方插入的劃線 CFI（epubcfi(/6/4)）皆為元素層級／純占位繁體文字，
  // 未包含任何 TWPhrases 非等長詞彙（如「内存」→「記憶體」），也未落在
  // 任何文字節點的字元 offset 上——`isTextNode()` 守衛下，
  // `adjustOffsetForCfi()` 對這個 CFI 完全不會被觸發。本測試只驗證「切換
  // 簡繁模式時，既有標記不會導致例外/畫面崩潰」這個回歸保護網，**不**
  // 驗證非等長詞彙情境下的精確字元位置——那需要一個內容已知、且能被
  // 獨立驗證（例如透過真機或 Puppeteer 產生的真實 CFI）的 fixture，本次
  // 修訂未能在本環境下取得可執行的瀏覽器/Puppeteer 環境驗證出正確字串，
  // 為避免寫入未經驗證、可能誤導的 CFI 常數，改為在下方「真機人工驗證
  // 清單」新增對應項目，如實反映目前的驗證缺口。
  testWidgets(
      'Foliate 流式 EPUB：簡繁轉換模式切換後，既有標記不拋出例外（回歸保護網，epic-42-text-conversion Issue 2）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final highlightsRepository = HighlightsRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'foliate_text_conversion_cfi.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_text_conversion_cfi',
      title: '簡繁轉換 CFI 穩定性測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const highlightId = 'h_text_conversion_1';
    await highlightsRepository.insert(const Highlight(
      id: highlightId,
      bookId: 'b_text_conversion_cfi',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_text_conversion_cfi',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 開啟版面設定 Bottom Sheet（reader_chrome_layout_button 為既有 Key，
    // 見 app/lib/screens/reader_chrome_bottom_bar.dart），切換到「呈現」
    // 分頁，點選「轉換為繁體」（Key 由 epic-42-text-conversion Issue 1
    // 既有交付，見 plan-issue-1.md Task 7）。
    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '呈現'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_traditional')),
    );
    await tester.pumpAndSettle();

    // 切換後 WebView 沒有拋出例外，既有劃線仍可透過 NotesBottomSheet
    // 正常顯示——回歸保護網（元素層級 CFI，不涵蓋非等長詞彙字元位置，
    // 見上方測試名稱前的說明）。
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
  });
```

不需要新增 import——`package:flutter/material.dart`（檔案第 3 行既有 import）已完整匯出 `Tab`／`Icons`（審查修正 M-2：原步驟草稿的額外 `import 'package:flutter/widgets.dart' show Tab;` 屬冗餘，會被 `flutter analyze` 標記，故不加入）。

在檔案頂部「【真機人工驗證清單，本測試無法自動涵蓋】」註解區塊（第 59-66 行）的既有 4 個項目之後，新增第 5 項（審查修正 I-3，如實記錄目前驗證缺口）：

```dart
  //   5. 簡繁轉換模式切換時，「非等長詞彙」（如「内存」→「記憶體」、
  //      「公共汽車」→「公車」）的劃線/書籤精確字元位置——本檔案下方
  //      新增的測試只涵蓋元素層級 CFI 的例外保護網，未涵蓋字元 offset
  //      映射的精確度，需另外準備已知內容的 fixture 並用真機或
  //      Puppeteer（app/tool/foliate_touch_harness/ 既有依賴，本次
  //      環境未安裝 node_modules 無法當場產生已驗證 CFI）驗證。
```

- [ ] **Step 2: 真機執行，確認通過**

Run: `flutter test integration_test/foliate_highlights_notes_test.dart -d <device-id>`
Expected: 兩個 testWidgets 皆 PASS（既有測試零回歸＋新增測試通過）。**此步驟需要人工在真實 Android 裝置/模擬器上執行並回報結果，本計畫執行過程無法自動驗證。**

- [ ] **Step 3: 執行 Task 1-3 的 Node 測試腳本 + `check_foliate_es_compat.js`，確認全數通過**

Run: `node app/tool/test_apply_text_conversion.mjs && node app/tool/test_cfi_range_adjustment.mjs && node app/tool/check_foliate_es_compat.js`
Expected: 三者皆成功（exit code 0）。

- [ ] **Step 4: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 執行完整 `flutter test`（本計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過（既有已知不穩定案例除外，例如 `adaptive_shell_scaffold_test.dart` 既有 2 個失敗案例，非本次異動引入）。

- [ ] **Step 6: Commit**

```bash
git add app/integration_test/foliate_highlights_notes_test.dart
git commit -m "test(reader): 新增簡繁轉換模式切換後 CFI 穩定性回歸整合測試"
```

---

## Self-Review

**Spec 覆蓋度**：對照 `issues.md` Issue 2「範圍」逐項核對——(1) DOM Walker `applyTextConversion(root, mode)`，排除 `<rt>`／`<script>`／`<style>` → Task 1；(2) 原始文字快取 `_elinkOrigText` → Task 1；(3) 雙向分段偏移映射 `TextOffsetMap`（消費 Issue 0b 既有的 `text-offset-map.js`）→ Task 1；(4) `fromRange`／`toRange` 攔截 → Task 1（`toOriginalRange`/`resolveDisplayRange` 純函式）＋ Task 2（`view.getCFI`/`view.resolveCFI` 實際接線）；(5) 新章節載入觸發 → Task 3 Step 2；(6) 閱讀中即時切換觸發 → Task 3 Step 3（含審查修正 I-1 的劃線重繪）。三項單元測試要求（CFI 穩定性回歸、DOM Walker 原始文字還原、真機 WebView 驗證）分別對應 Task 1（原始文字還原＋縮短詞 CFI 座標保護之 Node 測試）、Task 6（真機整合測試，惟精確字元位置驗證仍有缺口，見下方與 Task 6 註記）。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼區塊。Task 2/6 明確標註「本 Task 無法自動化驗證，需人工/真機確認」，這是誠實反映真實限制（比照專案既有 `app/integration_test/` 慣例），不是遺漏。**Task 6 的整合測試明確承認一項已知驗證缺口**（見 Task 6 Step 1 說明與新增的人工驗證清單第 5 項）：非等長詞彙（如「内存」→「記憶體」）的精確字元 offset 映射，需要一個內容已知且其 CFI 已被獨立驗證過的 fixture 才能自動化測試，本次修訂環境下無可執行的瀏覽器/Puppeteer 環境能產生一個「保證正確」的 CFI 字串（`app/tool/foliate_touch_harness/` 雖列有 `puppeteer` 依賴，但 `node_modules` 未安裝）——寧可如實記錄這個缺口，也不寫入未經驗證、可能本身就是錯的 CFI 常數混充驗證力。

**型別一致性**：`TextConversionMode`（Issue 0 既有）→ `FoliateReaderView.textConversion`（Task 4）→ `buildFoliatePreferencesMap()` 的 `.name` 字串（Task 4）→ `main.js` `prefs.textConversion`／`currentTextConversion`（Task 3）→ `applyTextConversion(doc, mode)` 的 `mode` 參數（Task 1，字面值 `'original'`／`'toTraditional'`／`'toSimplified'` 與 `applyTextConversionToString()`〔Issue 0b 既有〕完全一致）全程對齊，無命名漂移。`text-conversion-walker.js` 的四個匯出函式名稱（`applyTextConversion`／`adjustOffsetForCfi`／`toOriginalRange`／`resolveDisplayRange`）在 Task 1 定義、Task 2/3 消費，簽章前後一致。

**架構風險點（本計畫已處理，執行時務必落實）**：CFI 座標保護採「monkey-patch `view.getCFI`/`view.resolveCFI` 兩個實例方法」而非「逐一修改各呼叫點」，是刻意的架構決策（見 Architecture／Global Constraints）——好處是自動涵蓋 `view.js` 內部 `#onRelocate()`（「目前閱讀位置」CFI，main.js 完全沒有對應呼叫點可修改）這個容易被忽略的路徑；風險是若未來 `readest/foliate-js` 升級版本改變了 `getCFI`/`resolveCFI` 的方法名稱或簽章，這個遮蔽會悄悄失效而不拋出任何錯誤（呼叫端仍會拿到未受保護的原始 CFI，但不會當場出錯，可能延遲到使用者切換顯示模式後才發現劃線位移）。**下次升級 `foliate/` 釘定版本時，除了既有的 `node app/tool/check_foliate_es_compat.js`，也要手動核對 `view.js` 的 `getCFI()`/`resolveCFI()` 方法簽章是否還存在且行為一致**，這點未被任何自動化腳本涵蓋，記錄於此供下次升級時參考。

**審查修訂記錄**：2026-09-15 `reviews/review-plan-issue-2.md`（2 Critical／3 Important／2 Minor）已全數處理，套用至本計畫——C-1（`toOriginalRange()` 改為回傳純資料物件，不得建構真實 `Range`／呼叫 `cloneRange()`/`setStart()`/`setEnd()`，避免縮短詞情境下對 live DOM 節點呼叫超出長度的 offset 拋出 `IndexSizeError`）、C-2（新增 `resolveDisplayRange(doc, anchor)` 取代原本「事後調整 `anchor(doc)` 回傳值」的設計——原設計會在 `anchor(doc)` 內部真正呼叫的 `CFI.toRange()` 已經拋出例外並被其自身 `try/catch` 吞成 `null` 之後才執行調整，根本來不及；改為呼叫 `anchor(doc)` 之前先暫時把已轉換節點復原成原文，取得結果後立即讀出邊界並復原顯示文字，最後才建立調整過座標的全新 `Range`）、I-1（`window.applyPreferences()` 即時切換簡繁模式後，新增 `lastDecorations` 追蹤＋重新呼叫 `window.setDecorations()`，修復既有劃線因 `Overlayer` 未重繪而與重排後文字錯位的問題）、I-2（`applyTextConversion()`／`resolveDisplayRange()` 的走訪根節點改為 `doc.body ?? doc.documentElement ?? doc`，修復 FXL／無 `<body>` 章節的 `TypeError`）、I-3（Task 6 測試誠實重新定位為「例外回歸保護網」，不再宣稱驗證了未經證實的字元 offset 精確度，並在人工驗證清單新增對應缺口項目，取代原本審查建議但本環境無法驗證的具體 CFI 字串）、M-1（`test_apply_text_conversion.mjs` 新增 `doc.body === null` SVG 頁面測試案例）、M-2（Task 6 移除冗餘 `import`）。**與審查報告的具體修復建議有一處刻意的技術性偏離**：C-2 未採用審查報告建議的「以 `CFI.toElement`／`collapse()` 重新實作 CFI 解析」方案，改採「暫時復原原文、呼叫真正未經修改的 `anchor()`、再復原顯示文字」的方案——後者完整重用 vendored `epubcfi.js` 的既有演算法（`id` 查找／`cfi-skip`／`cfi-inert`／相鄰文字節點合併等既有複雜邏輯），不需要在 `main.js` 重新實作一份等效但未經執行驗證的 CFI 解析邏輯，風險更低（詳見 Task 1 `resolveDisplayRange()` 文件註解）。
