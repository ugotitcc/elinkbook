/// 章節載入時建立的「句子 → CFI」對照表單一項目（epic-34-tts-readalong
/// Issue 2，spec.md「朗讀段擷取」），對應 `main.js window.buildTtsSegments()`
/// 回傳的 JSON 陣列單一元素。比照 [TocEntry.fromWire] 既有寬容解析慣例
/// （缺失欄位以空字串防呆，不拋出例外）。
class TtsSegmentCfi {
  final String segmentId;
  final String cfi;
  final String text;

  const TtsSegmentCfi({
    required this.segmentId,
    required this.cfi,
    required this.text,
  });

  factory TtsSegmentCfi.fromWire(Map<Object?, Object?> map) {
    return TtsSegmentCfi(
      segmentId: map['segmentId'] as String? ?? '',
      cfi: map['cfi'] as String? ?? '',
      text: map['text'] as String? ?? '',
    );
  }
}
