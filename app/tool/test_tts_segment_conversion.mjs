// epic-42-text-conversion Issue 5：convertTtsSegments() 朗讀段文字轉換
// 驗證腳本。零 DOM 依賴，直接複用 Issue 0b 已驗證過的
// applyTextConversionToString()（見 test_text_conversion.mjs 既有測試
// 向量），只需驗證 segmentId／cfi 保持不變、text 依 mode 正確轉換。
//
// 用法：node app/tool/test_tts_segment_conversion.mjs

import assert from 'node:assert/strict'
import { convertTtsSegments } from '../android/app/src/main/assets/foliate/text-conversion.js'

// 基本轉換：text 依 mode 轉換（台灣慣用詞，沿用 test_text_conversion.mjs
// 已驗證過的「内存」→「記憶體」向量），segmentId／cfi 原樣保留不動。
{
  const segments = [
    { segmentId: '0', cfi: 'epubcfi(/6/2!/4/2,/1:0,/1:2)', text: '内存' },
    { segmentId: '1', cfi: 'epubcfi(/6/2!/4/4,/1:0,/1:2)', text: '软件' },
  ]
  const result = convertTtsSegments(segments, 'toTraditional')
  assert.equal(result[0].text, '記憶體')
  assert.equal(result[0].cfi, segments[0].cfi)
  assert.equal(result[0].segmentId, segments[0].segmentId)
  assert.equal(result[1].text, '軟體')
  assert.equal(result[1].cfi, segments[1].cfi)
  assert.equal(result[1].segmentId, segments[1].segmentId)
}

// original 模式：文字原樣不變（applyTextConversionToString 對 'original'
// 的既有恆等行為，見 text-conversion.js 該函式開頭）。
{
  const segments = [{ segmentId: '0', cfi: 'epubcfi(/6/2)', text: '内存清空' }]
  const result = convertTtsSegments(segments, 'original')
  assert.equal(result[0].text, '内存清空')
  assert.equal(result[0].cfi, segments[0].cfi)
}

// toSimplified：忠實保留原著文風，不套用大陸用語替換（延續 Issue 0b
// 「妥瑞氏症」ADR 0032 靈魂驗證案例，test_text_conversion.mjs 已驗證過的
// 向量）。
{
  const segments = [{ segmentId: '0', cfi: 'epubcfi(/6/2)', text: '妥瑞氏症' }]
  const result = convertTtsSegments(segments, 'toSimplified')
  assert.equal(result[0].text, '妥瑞氏症')
}

// 多筆朗讀段：每筆各自獨立轉換，互不影響。
{
  const segments = [
    { segmentId: '0', cfi: 'epubcfi(/6/2!/4/2)', text: '内存' },
    { segmentId: '1', cfi: 'epubcfi(/6/2!/4/4)', text: 'ABC123' },
  ]
  const result = convertTtsSegments(segments, 'toTraditional')
  assert.equal(result.length, 2)
  assert.equal(result[0].text, '記憶體')
  assert.equal(result[1].text, 'ABC123')
}

// 空陣列：回傳空陣列，不拋出例外（章節無可朗讀文字的既有邊界情況）。
{
  const result = convertTtsSegments([], 'toTraditional')
  assert.deepEqual(result, [])
}

console.log('[test_tts_segment_conversion] 全部通過')
