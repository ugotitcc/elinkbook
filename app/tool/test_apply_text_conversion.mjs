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
