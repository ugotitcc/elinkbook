/// 閱讀畫面的簡繁顯示切換（FR-48）：[original] 原文／[toTraditional] 轉換
/// 為繁體／[toSimplified] 轉換為簡體。純顯示層轉換，不修改原始檔案內容，
/// 亦不影響 CFI 定位（見 ADR 0030：轉換為逐字元 1:1、不做詞彙/慣用詞
/// 轉換，保證 ΔL=0）。
enum TextConversionMode { original, toTraditional, toSimplified }
