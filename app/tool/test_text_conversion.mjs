// epic-42-text-conversion Issue 0b：applyTextConversionToString() 片語
// 優先轉換驗證腳本（toTraditional 兩階段／toSimplified 單一階段）。零 DOM 依賴，測試向量與
// app/test/reader/text_conversion_test.dart 保持一致，驗證 JS／Dart
// 兩份獨立實作行為一致（見 ADR 0031：Dart AOT 無法呼叫 JS，兩邊各自
// 維護、不共用程式碼）。
//
// 用法：node app/tool/test_text_conversion.mjs

import assert from 'node:assert/strict'
import { applyTextConversionToString } from '../android/app/src/main/assets/foliate/text-conversion.js'

// original 模式／空字串：原樣回傳，offsetMap 為 null。
{
  const result = applyTextConversionToString('内存', 'original')
  assert.equal(result.text, '内存')
  assert.equal(result.offsetMap, null)
}
{
  const result = applyTextConversionToString('', 'toTraditional')
  assert.equal(result.text, '')
  assert.equal(result.offsetMap, null)
}

// 片語轉換：台灣常用詞優先於單字元查找表。
{
  const result = applyTextConversionToString('内存', 'toTraditional')
  assert.equal(result.text, '記憶體')
  assert.ok(result.offsetMap)
  assert.equal(result.offsetMap.entries.length, 1)
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 0)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 0)
  assert.equal(entry.dispLen, 3)
}

// 單字元長度的 TWPhrases 詞條。
{
  const result = applyTextConversionToString('硅', 'toTraditional')
  assert.equal(result.text, '矽')
}

// toSimplified：TSPhrases 直接對原文做最長匹配（審查修正 C-1）。
{
  const result = applyTextConversionToString('一目瞭然', 'toSimplified')
  assert.equal(result.text, '一目了然')
}

// toSimplified：TSPhrases 保護固定用語不被單字元規則誤轉（審查修正 C-1
// 核心回歸案例）。kT2sDict 對「乾」的單字元規則是「乾->干」，若先做
// 字元轉換再比對片語，「乾隆」會被誤轉成「干隆」，TSPhrases 的
// 「乾隆->乾隆」保護規則永遠比對不到。已用 opencc-js 實際輸出驗證：
// tw2s('乾隆皇帝') === '乾隆皇帝'。
{
  const result = applyTextConversionToString('乾隆皇帝', 'toSimplified')
  assert.equal(result.text, '乾隆皇帝')
}
{
  const result = applyTextConversionToString('乾坤大挪移', 'toSimplified')
  assert.equal(result.text, '乾坤大挪移')
}

// toSimplified：妥瑞氏症原樣保留，不套用大陸用語替換（審查修正 I-1，
// ADR 0032 靈魂驗證案例）。
{
  const result = applyTextConversionToString('妥瑞氏症', 'toSimplified')
  assert.equal(result.text, '妥瑞氏症')
}

// 代理對字元位於片語前時，offset 以 UTF-16 code unit 正確計量（審查
// 修正 I-2）。'𠮷'（U+20BB7）佔 2 個 UTF-16 code unit。
{
  const result = applyTextConversionToString('𠮷内存', 'toTraditional')
  assert.equal(result.text, '𠮷記憶體')
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 2)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 2)
  assert.equal(entry.dispLen, 3)
}

// 長度不變時，offsetMap 為 null（零開銷路徑）。
{
  const result = applyTextConversionToString('国电脑', 'toTraditional')
  assert.equal(result.text, '國電腦')
  assert.equal(result.offsetMap, null)
}

// 片語與前後文字混排時，offset 計算正確。
{
  const result = applyTextConversionToString('把内存清空', 'toTraditional')
  assert.equal(result.text, '把記憶體清空')
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 1)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 1)
  assert.equal(entry.dispLen, 3)
}

// 查找表與片語表都找不到的字元維持原樣。
{
  const result = applyTextConversionToString('ABC123', 'toTraditional')
  assert.equal(result.text, 'ABC123')
  assert.equal(result.offsetMap, null)
}

console.log('text-conversion.js 片語優先轉換驗證：全數通過')
