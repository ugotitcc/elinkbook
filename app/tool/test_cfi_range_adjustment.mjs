// epic-42-text-conversion Issue 2：CFI 座標保護純函式驗證腳本（見
// docs/epics/epic-42-text-conversion/offset-mapping-spec.md 第 3.2 節，
// 2026-09-15 依 reviews/review-plan-issue-2.md Issue C-1／C-2 修訂）。
// 零 npm 依賴，只用最小化手動 DOM/Range stub.
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
