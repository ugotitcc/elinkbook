// epic-42-text-conversion Issue 0b：片語優先、單字元其次的簡繁轉換，
// 並在替換過程中同步收集區段供建構 TextOffsetMap（見
// docs/epics/epic-42-text-conversion/offset-mapping-spec.md 第 3.1
// 節）。與 app/lib/reader/text_conversion.dart 的 convertTextDetailed()
// 是同一份演算法的兩份獨立實作，測試向量刻意保持一致（見
// app/tool/test_text_conversion.mjs），兩邊各自維護、不共用程式碼
// （Dart AOT 無法呼叫 JS，見 ADR 0031）。
//
// 零 DOM 依賴，可直接用 Node.js 執行（比照同目錄 tts-safe-window.js 的
// 既有慣例），供 Issue 2 的 DOM Walker（applyTextConversion）逐文字節點
// 呼叫——Issue 2 本身不重新實作這裡的最長匹配演算法.

import { s2tDict, t2sDict, s2twpPhraseDict, tw2sPhraseDict } from './text_conversion_dict.js'
import { createOffsetMapBuilder } from './text-offset-map.js'

// 片語比對時，單一詞條 code point 數的安全上限——必須與
// app/tool/generate_conversion_dicts.js 的 MAX_PHRASE_KEY_LENGTH、
// app/lib/reader/text_conversion.dart 的 kMaxPhraseKeyLength 保持一致。
const MAX_PHRASE_KEY_LENGTH = 16

/**
 * 依 mode 對 text 做簡繁字元/片語轉換，回傳顯示文字與（若有任何區段長度
 * 改變）對應的 offsetMap。
 *
 * **toTraditional 與 toSimplified 的片語比對基準不同，兩者不對稱**
 * （2026-09-15 依 reviews/review-plan-issue-0b.md Issue C-1 修訂，與
 * Dart 版 convertTextDetailed() 完全相同的設計，見其文件註解的完整
 * 技術驗證說明）：
 * - toTraditional（兩階段）：Stage 1 逐 code point 用 s2tDict 轉換出
 *   中繼文字，與 text 逐字元等長；Stage 2 在中繼文字上做
 *   s2twpPhraseDict（TWPhrases）最長匹配——TWPhrases 的鍵是「單字元
 *   轉換後」的繁體形態，必須先做 Stage 1 才能命中。
 * - toSimplified（單一階段）：直接對「原始輸入」做 tw2sPhraseDict
 *   （TSPhrases）最長匹配，找不到片語才逐 code point 退回 t2sDict
 *   單字元轉換——TSPhrases 的鍵是原始（未字元轉換）的繁體形態，常用來
 *   保護固定用語不被單字元規則誤轉（例如「乾隆」不被誤轉成「干隆」）。
 *   若先做字元轉換再比對片語，片語字典的鍵永遠比對不到。
 *
 * @param {string} text
 * @param {'original' | 'toTraditional' | 'toSimplified'} mode
 * @returns {{ text: string, offsetMap: { entries: object[] } | null }}
 */
export function applyTextConversionToString(text, mode) {
  if (mode === 'original' || text.length === 0) {
    return { text, offsetMap: null }
  }

  const units = Array.from(text)

  let matchUnits
  let charDict
  let phraseDict
  if (mode === 'toTraditional') {
    charDict = s2tDict
    phraseDict = s2twpPhraseDict
    // Stage 1：先逐字元轉換出中繼文字，片語比對對中繼文字做。
    matchUnits = units.map((ch) => charDict[ch] || ch)
  } else {
    charDict = t2sDict
    phraseDict = tw2sPhraseDict
    // toSimplified：片語比對直接對原始輸入做（審查修正 C-1）。
    matchUnits = units
  }

  let result = ''
  const builder = createOffsetMapBuilder()
  let origOffset = 0
  let dispOffset = 0
  let i = 0
  while (i < matchUnits.length) {
    const maxLen = Math.min(MAX_PHRASE_KEY_LENGTH, matchUnits.length - i)
    let matchedValue = null
    let matchedLen = 0
    for (let len = maxLen; len >= 1; len--) {
      const candidate = matchUnits.slice(i, i + len).join('')
      if (Object.prototype.hasOwnProperty.call(phraseDict, candidate)) {
        matchedValue = phraseDict[candidate]
        matchedLen = len
        break
      }
    }

    const consumedCount = matchedValue !== null ? matchedLen : 1
    const origSegment = matchUnits.slice(i, i + consumedCount).join('')
    // toTraditional：origSegment 已是 Stage 1 轉換後的中繼文字，找不到
    // 片語時直接沿用。toSimplified：origSegment 是原始未轉換文字，找不到
    // 片語時才在此對單一 code point 套用 charDict。
    const dispSegment = matchedValue !== null
      ? matchedValue
      : (mode === 'toTraditional' ? origSegment : (charDict[origSegment] || origSegment))

    result += dispSegment
    if (dispSegment.length !== origSegment.length) {
      builder.addSegment(origOffset, origSegment.length, dispOffset, dispSegment.length)
    }
    origOffset += origSegment.length
    dispOffset += dispSegment.length
    i += consumedCount
  }

  return { text: result, offsetMap: builder.build() }
}

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
