// epic-42-text-conversion Issue 0b：TextOffsetMap 雙向偏移映射純邏輯
// 驗證腳本。零 DOM 依賴，可直接用 Node.js 執行（比照
// test_tts_safe_window.mjs 既有慣例），測試向量與
// app/test/reader/text_offset_map_test.dart 保持一致。
//
// 用法：node app/tool/test_text_offset_map.mjs

import assert from 'node:assert/strict'
import {
  createOffsetMapBuilder,
  origToDisplay,
  displayToOrig,
} from '../android/app/src/main/assets/foliate/text-offset-map.js'

// 零開銷路徑
assert.equal(origToDisplay(null, 5), 5)
assert.equal(displayToOrig(null, 5), 5)
assert.equal(origToDisplay({ entries: [] }, 5), 5)
assert.equal(displayToOrig({ entries: [] }, 5), 5)
{
  const builder = createOffsetMapBuilder()
  assert.equal(builder.build(), null)
}

// 單一區段：模擬「abc內存def」轉換為「abc記憶體def」
// 內存@origOffset=3,origLen=2 -> 記憶體@dispOffset=3,dispLen=3，delta=+1。
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(3, 2, 3, 3)
  const map = builder.build()

  assert.equal(origToDisplay(map, 0), 0)
  assert.equal(origToDisplay(map, 2), 2)
  assert.equal(origToDisplay(map, 3), 3)
  assert.equal(origToDisplay(map, 4), 4)
  assert.equal(origToDisplay(map, 5), 6)

  assert.equal(displayToOrig(map, 2), 2)
  assert.equal(displayToOrig(map, 4, 'floor'), 3)
  assert.equal(displayToOrig(map, 5, 'floor'), 3)
  assert.equal(displayToOrig(map, 4, 'ceil'), 5)
  assert.equal(displayToOrig(map, 3, 'ceil'), 5)
  assert.equal(displayToOrig(map, 6), 5)
}

// 多區段：驗證 accumDelta 正確累加
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(0, 2, 0, 3)
  builder.addSegment(10, 3, 11, 2)
  const map = builder.build()

  assert.equal(map.entries[1].accumDelta, 1)
  assert.equal(origToDisplay(map, 13), 13)
  assert.equal(displayToOrig(map, 13), 13)
}

// 縮短區段：模擬「公共汽車」(4) 轉換為「公車」(2)（審查修正 C-2）。
// origOffset=0,origLen=4 -> dispOffset=0,dispLen=2，delta=-2。
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(0, 4, 0, 2)
  const map = builder.build()

  assert.equal(origToDisplay(map, 0), 0)
  assert.equal(origToDisplay(map, 1), 1)
  // 修正前會回傳 2、3，超出顯示文字「公車」實際長度 2 的有效範圍，
  // 在 live DOM 對長度僅 2 的文字節點呼叫 range.setEnd(node, 3) 會直接
  // 拋出 IndexSizeError。修正後皆夾住在 dispLen=2。
  assert.equal(origToDisplay(map, 2), 2)
  assert.equal(origToDisplay(map, 3), 2)
  // 弱單調遞增：區段邊界前後不應數值倒退（修正前 3->3、4->2 會倒退）。
  const beforeBoundary = origToDisplay(map, 3)
  const afterBoundary = origToDisplay(map, 4)
  assert.ok(afterBoundary >= beforeBoundary)
  assert.equal(afterBoundary, 2)

  assert.equal(displayToOrig(map, 1, 'floor'), 0)
  assert.equal(displayToOrig(map, 1, 'ceil'), 4)
  assert.equal(displayToOrig(map, 2), 4)
}

console.log('text-offset-map.js 雙向偏移映射驗證：全數通過')
