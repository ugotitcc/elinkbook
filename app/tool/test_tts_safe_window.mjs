// epic-26-architecture-hardening Issue 12：TTS 安全視窗（Safe Viewport）
// 判斷邏輯的純邏輯驗證腳本。tts-safe-window.js 零 DOM 依賴，可直接用
// Node.js 執行，不需要 npm install 或任何測試框架（比照
// test_section_progress_density.mjs 的既有慣例，見 app/tool/README.md）。
//
// 用法：node app/tool/test_tts_safe_window.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。

import assert from 'node:assert/strict'
import { resolveTtsSafeWindowDirection } from '../android/app/src/main/assets/foliate/tts-safe-window.js'

// 測試用固定 iframeRect／viewportRect：iframeRect 左上角對齊 (0,0)，
// viewportRect 為 100x100 的正方形，left/top 皆為 0——因此
// normOf(rect).x = rect.left/100、normOf(rect).y = rect.top/100
// （呼叫端傳入的 rect 皆用 left===right、top===bottom 的「點矩形」，
// 讓正規化座標可直接由 left/top 除以 100 推算，方便寫斷言）。
const IFRAME_RECT = { left: 0, top: 0 }
const VIEWPORT_RECT = { left: 0, top: 0, width: 100, height: 100 }

function point(x, y) {
  return { left: x, right: x, top: y, bottom: y }
}

const SAFE = point(50, 50) // 正規化座標 (0.5, 0.5)，橫排/直排皆不觸發

// 測試 1：橫排 needNext——last.y > 0.8 觸發，first 安全時回傳 'next'。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 85), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 2：橫排 needPrev——first.y < 0.0 觸發，last 安全時回傳 'prev'。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, -10), SAFE, IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'prev')
}

// 測試 3：直排 needNext——last.x < 0.2 觸發。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(10, 50), IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'next')
}

// 測試 4：直排 needPrev——first.x > 1.0 觸發。
{
  const direction = resolveTtsSafeWindowDirection(
    point(150, 50), SAFE, IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'prev')
}

// 測試 5：直排邊界——last.x 恰好等於 0.2（軟門檻）不觸發 next（條件是
// `<`，非 `<=`）。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(20, 50), IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, null)
}

// 測試 6：直排邊界——last.x 略低於 0.2（19.9/100）觸發 next。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(19.9, 50), IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'next')
}

// 測試 7：直排邊界——first.x 恰好等於 1.0（硬邊界）不觸發 prev（條件是
// `>`，非 `>=`）。
{
  const direction = resolveTtsSafeWindowDirection(
    point(100, 50), SAFE, IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, null)
}

// 測試 8：直排邊界——first.x 略高於 1.0（100.1/100）觸發 prev。
{
  const direction = resolveTtsSafeWindowDirection(
    point(100.1, 50), SAFE, IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'prev')
}

// 測試 9：橫排邊界——last.y 恰好等於 0.8（軟門檻）不觸發 next（條件是
// `>`，非 `>=`）。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 80), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, null)
}

// 測試 10：橫排邊界——last.y 略高於 0.8（80.1/100）觸發 next。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 80.1), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 11：橫排邊界——first.y 恰好等於 0.0（硬邊界）不觸發 prev（條件是
// `< 0.0`，非 `<= 0.0`）。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, 0), SAFE, IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, null)
}

// 測試 12：needNext 與 needPrev 同時成立時，next 優先（沿用原本焊在
// main.js 呼叫端的 if/else if 順序規則，收進函式內部）。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, -10), point(50, 85), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 13：firstRect／lastRect／iframeRect／viewportRect 任一缺席時回傳
// null（對應 main.js 原本 `if (firstRect && lastRect && frameEl)` 防呆，
// 行為與搬移前一致）。
{
  assert.equal(
    resolveTtsSafeWindowDirection(null, SAFE, IFRAME_RECT, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, undefined, IFRAME_RECT, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, SAFE, null, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, SAFE, IFRAME_RECT, null, false),
    null,
  )
}

console.log('resolveTtsSafeWindowDirection 安全視窗判斷驗證：13 項全數通過')
