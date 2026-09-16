// app/lib/search/search_query_variants.dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';

/// 依原始查詢字串 [q0] 產生簡繁三個變體（spec.md「全文檢索整合」
/// Multi-variant Query Expansion）：原文、轉換為繁體、轉換為簡體，去重後
/// 依序回傳（[q0] 恆為第一個元素）。**不假設任何反向關係**——簡化字存在
/// 多對一併字（「後」「后」皆簡化為「后」），沒有無損的反向字典，因此
/// 一律正向查三種可能字形，而非嘗試依目前顯示模式反推回原文（見
/// spec.md 對推翻原「查詢端反向字典轉換」方案的完整說明）。
List<String> queryVariants(String q0) {
  return <String>{
    q0,
    convertText(q0, TextConversionMode.toTraditional),
    convertText(q0, TextConversionMode.toSimplified),
  }.toList(growable: false);
}

/// 在 [variants] 中依序找出第一個能在 [text] 中以 [String.indexOf]（不分
/// 大小寫）找到的變體；全部找不到時回傳 `null`。供截斷視窗定位
/// （`SqliteSearchRepository._truncate()`）與關鍵字高亮
/// （`BookSearchScreen._buildHighlightedText()`）共用，讓「命中內容字形與
/// 使用者輸入字形不同」（跨字形命中）時仍能正確定位／高亮（spec.md 審查
/// 修正 I-2）。
String? findMatchingVariant(String text, List<String> variants) {
  final lowerText = text.toLowerCase();
  for (final variant in variants) {
    if (variant.isNotEmpty && lowerText.contains(variant.toLowerCase())) {
      return variant;
    }
  }
  return null;
}
