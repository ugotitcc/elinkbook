// epic-54 Issue 34：直排欄間隔與頁高不一致（舊 WebView）補償邏輯的純邏輯驗證腳本。
// column-pitch.js 零 DOM 依賴，可直接用 Node.js 執行，不需要 npm install 或任何測試框架
// （比照 test_tts_safe_window.mjs 的既有慣例，見 app/tool/README.md）。
//
// 用法：node app/tool/test_column_pitch.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。

import assert from 'node:assert/strict'
import {
  PITCH_TOLERANCE,
  MAX_COMPENSATION_ITERATIONS,
  measureColumnPitch,
  isValidMaxHeight,
  nextMaxHeight,
  compensateColumnPitch,
} from '../android/app/src/main/assets/foliate/column-pitch.js'

assert.equal(PITCH_TOLERANCE, 1.5)
assert.equal(MAX_COMPENSATION_ITERATIONS, 4)

// 案例 a：單頁章節——measure 回 null → status === 'skipped'、setMaxHeight 呼叫 0 次、resetMaxHeight 呼叫 0 次。
{
  let setCalls = 0
  let resetCalls = 0
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => null,
    getBoxHeight: () => 999.5,
    setMaxHeight: () => { setCalls++ },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(result, { status: 'skipped', iterations: 0 })
  assert.equal(setCalls, 0)
  assert.equal(resetCalls, 0)
}

// 案例 b：新版引擎——measure 回 {pitch: 999.5, columnLength: 927.5}、target = 999.5 → status === 'ok'、iterations === 0、setMaxHeight 0 次。
{
  let setCalls = 0
  let resetCalls = 0
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => ({ pitch: 999.5, columnLength: 927.5 }),
    getBoxHeight: () => 999.5,
    setMaxHeight: () => { setCalls++ },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(result, { status: 'ok', iterations: 0 })
  assert.equal(setCalls, 0)
  assert.equal(resetCalls, 0)
}

// 案例 c：單欄舊引擎一步收斂——target = 999.5、getBoxHeight() = 999.5；measure 第 1 次回 {pitch: 1071.5, columnLength: 999.5}，
// setMaxHeight 被呼叫後改回 {pitch: 999.5, columnLength: 927.5} → setMaxHeight 收到 927.5、status === 'compensated'、iterations === 1。
{
  const received = []
  let resetCalls = 0
  let current = { pitch: 1071.5, columnLength: 999.5 }
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => current,
    getBoxHeight: () => 999.5,
    setMaxHeight: (px) => {
      received.push(px)
      current = { pitch: 999.5, columnLength: 927.5 }
    },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(received, [927.5])
  assert.deepEqual(result, { status: 'compensated', iterations: 1 })
  assert.equal(resetCalls, 0)
}

// 案例 c2：雙欄舊引擎一步收斂——target = 499.7、getBoxHeight() = 999.5、第 1 次 {pitch: 571.7, columnLength: 499.7}
// → setMaxHeight 收到 427.7（用 min(999.5, 499.7) 當 base，不是 927.5）；之後模擬 measure 回 pitch: 499.7 → status === 'compensated'、iterations === 1。
{
  const received = []
  let resetCalls = 0
  let current = { pitch: 571.7, columnLength: 499.7 }
  const result = compensateColumnPitch({
    target: 499.7,
    measure: () => current,
    getBoxHeight: () => 999.5,
    setMaxHeight: (px) => {
      received.push(Number(px.toFixed(4)))
      current = { pitch: 499.7, columnLength: 427.7 }
    },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(received, [427.7])
  assert.deepEqual(result, { status: 'compensated', iterations: 1 })
  assert.equal(resetCalls, 0)
}

// 案例 c3：新版引擎被模擬成誤差（需兩次）——target = 999.5、getBoxHeight() = 999.5、第 1 次 {pitch: 1071.5, columnLength: 927.5}
// → 第 1 次 setMaxHeight 收到 855.5；模擬量測改回 pitch: 927.5（斜率 1：pitch = max-height + 72）
// → 第 2 次 setMaxHeight 收到 927.5（base 是上一次設定的 855.5，不是欄長）；再量 pitch: 999.5 → status === 'compensated'、iterations === 2。
{
  const received = []
  let resetCalls = 0
  let current = { pitch: 1071.5, columnLength: 927.5 }
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => current,
    getBoxHeight: () => 999.5,
    setMaxHeight: (px) => {
      received.push(Number(px.toFixed(4)))
      current = { pitch: px + 72, columnLength: px - 72 }
    },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(received, [855.5, 927.5])
  assert.deepEqual(result, { status: 'compensated', iterations: 2 })
  assert.equal(resetCalls, 0)
}

// 案例 d：無法收斂——measure 永遠回 {pitch: 1071.5, columnLength: 999.5} → setMaxHeight 恰好 4 次、resetMaxHeight 恰好 1 次、status === 'gave-up'。
{
  let setCalls = 0
  let resetCalls = 0
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => ({ pitch: 1071.5, columnLength: 999.5 }),
    getBoxHeight: () => 999.5,
    setMaxHeight: () => { setCalls++ },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(result, { status: 'gave-up', iterations: 4 })
  assert.equal(setCalls, 4)
  assert.equal(resetCalls, 1)
}

// 案例 e：調整後無法再量測——第 1 次回 pitch = 1071.5，setMaxHeight 之後 measure 回 null → resetMaxHeight 1 次、status === 'gave-up'。
{
  let setCalls = 0
  let resetCalls = 0
  let current = { pitch: 1071.5, columnLength: 999.5 }
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => current,
    getBoxHeight: () => 999.5,
    setMaxHeight: () => {
      setCalls++
      current = null
    },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(result, { status: 'gave-up', iterations: 1 })
  assert.equal(setCalls, 1)
  assert.equal(resetCalls, 1)
}

// 案例 f：量測函式——直排兩矩形 top 為 0、1071.5，height 為 999.5 → {pitch: 1071.5, columnLength: 999.5}；橫排改用 left／width；只有 1 個矩形 → null。
{
  assert.deepEqual(
    measureColumnPitch(
      [
        { top: 0, left: 0, height: 999.5, width: 700 },
        { top: 1071.5, left: 0, height: 999.5, width: 700 },
      ],
      true,
    ),
    { pitch: 1071.5, columnLength: 999.5 },
  )
  assert.deepEqual(
    measureColumnPitch(
      [
        { top: 0, left: 0, height: 900, width: 356 },
        { top: 0, left: 356, height: 900, width: 356 },
      ],
      false,
    ),
    { pitch: 356, columnLength: 356 },
  )
  assert.equal(
    measureColumnPitch([{ top: 0, left: 0, height: 999.5, width: 700 }], true),
    null,
  )
  assert.equal(measureColumnPitch([], true), null)
}

// 案例 f2：量測的邊界——橫排 RTL，兩矩形 left 為 1000、500（遞減）→ pitch === 500（取絕對值）；兩矩形 top 相同 → null（pitch 為 0）。
{
  assert.deepEqual(
    measureColumnPitch(
      [
        { top: 0, left: 1000, height: 900, width: 450 },
        { top: 0, left: 500, height: 900, width: 450 },
      ],
      false,
    ),
    { pitch: 500, columnLength: 450 },
  )
  assert.equal(
    measureColumnPitch(
      [
        { top: 100, left: 0, height: 999.5, width: 700 },
        { top: 100, left: 0, height: 999.5, width: 700 },
      ],
      true,
    ),
    null,
  )
}

// 案例 g：nextMaxHeight——{pitch: 1000, target: 999.5, base: 999.5}（誤差 0.5）→ null；誤差正好 1.5 → 回數值（容許邊界不含）。
{
  assert.equal(nextMaxHeight({ pitch: 1000, target: 999.5, base: 999.5 }), null)
  assert.equal(nextMaxHeight({ pitch: 1001, target: 999.5, base: 999.5 }), 998)
}

// 案例 h：算出非正數的高度——target = 999.5、getBoxHeight() = 50、measure 回 {pitch: 1071.5, columnLength: 50}（算得 50 − 72 = −22）
// → setMaxHeight 0 次、resetMaxHeight 恰好 1 次、status === 'gave-up'。
// 另測 isValidMaxHeight(0)、isValidMaxHeight(-22)、isValidMaxHeight(NaN) 為 false，isValidMaxHeight(927.5) 為 true。
{
  let setCalls = 0
  let resetCalls = 0
  const result = compensateColumnPitch({
    target: 999.5,
    measure: () => ({ pitch: 1071.5, columnLength: 50 }),
    getBoxHeight: () => 50,
    setMaxHeight: () => { setCalls++ },
    resetMaxHeight: () => { resetCalls++ },
  })
  assert.deepEqual(result, { status: 'gave-up', iterations: 0 })
  assert.equal(setCalls, 0)
  assert.equal(resetCalls, 1)

  assert.equal(isValidMaxHeight(0), false)
  assert.equal(isValidMaxHeight(-22), false)
  assert.equal(isValidMaxHeight(NaN), false)
  assert.equal(isValidMaxHeight(Infinity), false)
  assert.equal(isValidMaxHeight(927.5), true)
}

console.log('全數通過')
