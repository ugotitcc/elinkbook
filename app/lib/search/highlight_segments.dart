// app/lib/search/highlight_segments.dart
import 'package:flutter/foundation.dart';

/// 高亮切分後的其中一段文字（epic-41-search-architecture-hardening
/// Issue 4）：[isMatch] 為 `true` 代表這段文字是命中 query 的部分，
/// 呼叫端依此決定是否套用高亮樣式。純資料物件，不含任何樣式資訊。
@immutable
class HighlightSegment {
  final String text;
  final bool isMatch;

  const HighlightSegment(this.text, this.isMatch);

  @override
  bool operator ==(Object other) =>
      other is HighlightSegment &&
      other.text == text &&
      other.isMatch == isMatch;

  @override
  int get hashCode => Object.hash(text, isMatch);

  @override
  String toString() => 'HighlightSegment($text, isMatch: $isMatch)';
}

/// 在 [text] 中找出 [query] 出現的所有位置（case-insensitive），依命中與否
/// 切成一連串片段。純函式，不依賴 `BuildContext`／樣式——原本混在
/// `BookSearchScreen._buildHighlightedText()` 裡的字串演算法（見
/// epic-41-search-architecture-hardening Issue 4），抽出後可獨立單元測試。
///
/// [query] 為空字串，或在 [text] 中找不到任何命中時，回傳單一非命中片段
/// （內容為整段 [text]，可能是空字串）——呼叫端可用這個特徵判斷「完全沒有
/// 需要高亮的內容」。
List<HighlightSegment> splitHighlightSegments(String text, String query) {
  if (query.isEmpty || text.isEmpty) return [HighlightSegment(text, false)];

  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final segments = <HighlightSegment>[];
  var start = 0;

  while (start < text.length) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);
    if (matchIndex < 0) {
      segments.add(HighlightSegment(text.substring(start), false));
      break;
    }
    if (matchIndex > start) {
      segments.add(HighlightSegment(text.substring(start, matchIndex), false));
    }
    // matchIndex 是在 lowerText 中對 lowerQuery 搜尋得到的結果，這裡改用
    // query.length（而非 lowerQuery.length）取出原始大小寫的命中片段；
    // toLowerCase() 對兩者的長度轉換同源、恆等，故長度可互換使用。
    final matchEnd = matchIndex + query.length;
    segments.add(HighlightSegment(text.substring(matchIndex, matchEnd), true));
    start = matchEnd;
  }

  if (segments.isEmpty) return [HighlightSegment(text, false)];
  return segments;
}
