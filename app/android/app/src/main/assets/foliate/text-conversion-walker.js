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
