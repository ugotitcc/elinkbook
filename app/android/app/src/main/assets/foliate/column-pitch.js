// epic-54 Issue 34：直排欄間隔（Column Pitch）與頁高（Page Size）不一致的補償純函式模組。
//
// 零 DOM 依賴，可直接由 Node.js 單元測試腳本（app/tool/test_column_pitch.mjs）匯入驗證，
// 並由 main.js 於 WebView 內掛接至章節文件。
//
// 背景與領域詞彙（見 CONTEXT.md「頁高」「欄間隔」與 epic.md「Issue 34 設計決策」）：
// - 頁高（Page Size）：分頁模式下翻一頁移動的距離（renderer.size）；多欄時每欄目標間隔為
//   renderer.size / renderer.columnCount。
// - 欄間隔（Column Pitch）：相鄰兩欄起點之間的實際距離。正常情況應等於「頁高 ÷ 欄數」；
//   但 Chrome 91 等舊版 WebView 在直排多欄下會忽略根元素上下內距、把欄長直接排成頁高，
//   使欄間隔變成「頁高 + column-gap」，每翻一頁多累積一個 column-gap 的偏移。
// - 補償做法：透過量測實際欄間隔與目標值的誤差，迭代調整根元素 max-height（斜率為 1），
//   使欄間隔收斂回目標頁高；若 4 次內無法收斂或算出無效高度，立即還原為 none。

// 容許誤差（CSS px）：|欄間隔 - 目標值| < PITCH_TOLERANCE 視為已對齊，不動作。
export const PITCH_TOLERANCE = 1.5

// 最大補償迭代次數：超過仍未收斂即放棄並還原。
export const MAX_COMPENSATION_ITERATIONS = 4

/**
 * 從 getClientRects() 矩形陣列量測相鄰兩欄的欄間隔（pitch）與第一欄的欄長（columnLength）。
 *
 * @param {Array<{top:number, left:number, height:number, width:number}>} rects
 * @param {boolean} vertical - true 為直排（取 top 差與 height），false 為橫排（取 left 差與 width）
 * @returns {{ pitch: number, columnLength: number } | null} 少於 2 個矩形或 pitch <= 0 時回 null
 */
export function measureColumnPitch(rects, vertical) {
  if (!rects || rects.length < 2) return null
  const r0 = rects[0]
  const r1 = rects[1]
  const pitch = Math.abs(vertical ? r1.top - r0.top : r1.left - r0.left)
  if (!(pitch > 0)) return null
  const columnLength = vertical ? r0.height : r0.width
  return { pitch, columnLength }
}

/**
 * 檢查計算出的 max-height 像素值是否為合法的正有限數。
 *
 * @param {number} px
 * @returns {boolean}
 */
export function isValidMaxHeight(px) {
  return Number.isFinite(px) && px > 0
}

/**
 * 計算下一輪要設定的根元素 max-height（CSS px）。
 *
 * @param {{ pitch: number, target: number, base: number }} args
 * @returns {number | null} 誤差在容許範圍內時回 null（代表不需再調整）；否則回 base - (pitch - target)
 */
export function nextMaxHeight(args) {
  const pitch = args.pitch
  const target = args.target
  const base = args.base
  const error = pitch - target
  if (Math.abs(error) < PITCH_TOLERANCE) return null
  return base - error
}

/**
 * 驅動欄間隔迭代補償。
 *
 * @param {{
 *   target: number,
 *   measure: () => ({ pitch: number, columnLength: number } | null),
 *   getBoxHeight: () => number,
 *   setMaxHeight: (px: number) => void,
 *   resetMaxHeight: () => void,
 * }} args
 * @returns {{ status: 'skipped' | 'ok' | 'compensated' | 'gave-up', iterations: number }}
 */
export function compensateColumnPitch(args) {
  const target = args.target
  const measure = args.measure
  const getBoxHeight = args.getBoxHeight
  const setMaxHeight = args.setMaxHeight
  const resetMaxHeight = args.resetMaxHeight

  let iterations = 0
  let lastSetMaxHeight = null

  for (let i = 0; i < MAX_COMPENSATION_ITERATIONS; i++) {
    const measured = measure()
    if (!measured) {
      if (i === 0) {
        return { status: 'skipped', iterations: 0 }
      }
      resetMaxHeight()
      return { status: 'gave-up', iterations }
    }

    const base = lastSetMaxHeight !== null
      ? lastSetMaxHeight
      : Math.min(getBoxHeight(), measured.columnLength)

    const next = nextMaxHeight({
      pitch: measured.pitch,
      target,
      base,
    })

    if (next === null) {
      return {
        status: iterations === 0 ? 'ok' : 'compensated',
        iterations,
      }
    }

    if (!isValidMaxHeight(next)) {
      resetMaxHeight()
      return { status: 'gave-up', iterations }
    }

    setMaxHeight(next)
    lastSetMaxHeight = next
    iterations++
  }

  // 已調整滿 MAX_COMPENSATION_ITERATIONS 次，最後量測一次確認是否已收斂
  const finalMeasured = measure()
  if (
    finalMeasured &&
    Math.abs(finalMeasured.pitch - target) < PITCH_TOLERANCE
  ) {
    return { status: 'compensated', iterations }
  }

  resetMaxHeight()
  return { status: 'gave-up', iterations }
}
