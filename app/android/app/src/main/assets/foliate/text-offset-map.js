// epic-42-text-conversion Issue 0b：雙向分段偏移映射（Piecewise Offset
// Mapping，見 docs/epics/epic-42-text-conversion/offset-mapping-spec.md
// 第 2 節）。零 DOM 依賴，可直接用 Node.js 執行（比照同目錄
// tts-safe-window.js 既有慣例），供 main.js 的 DOM Walker（Issue 2）
// 攔截 epubcfi.js 的 fromRange／toRange 呼叫點時使用.

/**
 * 累加建構偏移映射：呼叫端在掃描/替換文字的過程中，每遇到一個長度改變
 * 的置換區段就呼叫一次 addSegment，全部處理完後呼叫 build()——沒有任何
 * 區段時回傳 null，代表這個節點可以走零開銷路徑。
 */
export function createOffsetMapBuilder() {
  const entries = []
  let accumDelta = 0
  return {
    /**
     * @param {number} origOffset 原文中此區段的起始 offset（UTF-16）。
     * @param {number} origLen 原文中此區段的長度（UTF-16）。
     * @param {number} dispOffset 顯示文字中此區段的起始 offset（UTF-16）。
     * @param {number} dispLen 顯示文字中此區段的長度（UTF-16）。
     */
    addSegment(origOffset, origLen, dispOffset, dispLen) {
      const delta = dispLen - origLen
      entries.push({ origOffset, origLen, dispOffset, dispLen, delta, accumDelta })
      accumDelta += delta
    },
    /** @returns {{ entries: object[] } | null} 沒有任何區段時回傳 null。 */
    build() {
      return entries.length === 0 ? null : { entries }
    },
  }
}

/**
 * 原文 offset → 顯示文字 offset。用於 CFI 還原劃線（toRange）、搜尋結果
 * 高亮、TTS 朗讀進度定位。offsetMap 為 null（或沒有任何區段）時直接
 * 原樣回傳（零開銷路徑）。
 * @param {{ entries: object[] } | null | undefined} offsetMap
 * @param {number} origOffset
 * @returns {number}
 */
export function origToDisplay(offsetMap, origOffset) {
  if (!offsetMap || offsetMap.entries.length === 0) return origOffset

  const entries = offsetMap.entries
  let low = 0
  let high = entries.length - 1
  let matchedIndex = -1
  while (low <= high) {
    const mid = (low + high) >> 1
    const entry = entries[mid]
    if (entry.origOffset <= origOffset) {
      matchedIndex = mid
      low = mid + 1
    } else {
      high = mid - 1
    }
  }

  if (matchedIndex === -1) return origOffset

  const entry = entries[matchedIndex]
  if (origOffset < entry.origOffset + entry.origLen) {
    const intraOffset = origOffset - entry.origOffset
    // 審查修正 C-2：片語「縮短」時（dispLen < origLen，例如「公共汽車」
    // (4) -> 「公車」(2)，TWPhrases.txt 實際存在 237 條此類詞彙），
    // intraOffset 可能超出顯示詞的實際長度。必須夾在 [0, dispLen] 內，
    // 否則回傳值會指向顯示文字節點長度以外的位置，live DOM 呼叫
    // range.setEnd() 時直接拋出 IndexSizeError；夾住同時修復了單調性
    // 破壞。
    const clampedIntra = Math.min(intraOffset, entry.dispLen)
    return entry.dispOffset + clampedIntra
  }

  return origOffset + entry.accumDelta + entry.delta
}

/**
 * 顯示文字 offset → 原文 offset。用於使用者在畫面選取文字建立劃線
 * （fromRange）時，換算出應存入 CFI 的原文 offset。snapPolicy
 * （'floor'／'ceil'）決定 offset 落在置換詞中間時要貼齊詞首還是詞尾——
 * 選取起點用 'floor'、選取終點用 'ceil'。
 * @param {{ entries: object[] } | null | undefined} offsetMap
 * @param {number} dispOffset
 * @param {'floor' | 'ceil'} [snapPolicy]
 * @returns {number}
 */
export function displayToOrig(offsetMap, dispOffset, snapPolicy = 'floor') {
  if (!offsetMap || offsetMap.entries.length === 0) return dispOffset

  const entries = offsetMap.entries
  let low = 0
  let high = entries.length - 1
  let matchedIndex = -1
  while (low <= high) {
    const mid = (low + high) >> 1
    const entry = entries[mid]
    if (entry.dispOffset <= dispOffset) {
      matchedIndex = mid
      low = mid + 1
    } else {
      high = mid - 1
    }
  }

  if (matchedIndex === -1) return dispOffset

  const entry = entries[matchedIndex]
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    return snapPolicy === 'ceil'
      ? entry.origOffset + entry.origLen
      : entry.origOffset
  }

  return dispOffset - (entry.accumDelta + entry.delta)
}
