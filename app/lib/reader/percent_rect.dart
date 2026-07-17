import 'dart:convert';

/// 相對容器寬高的百分比矩形（0.0-1.0），比照 design.md 決策 #15 對 PDF
/// 框選座標的既有百分比慣例。目前供 [EpubSelectionInfo] 使用；Issue 3
/// （PDF 長按框選，見 issues.md）預期會有結構相同的座標傳遞需求，屆時可
/// 直接複用本類別，不需再各自宣告一組同義欄位（審查修正：原本
/// `leftPct`/`topPct`/`rightPct`/`bottomPct` 四個高度相關欄位直接散落
/// 宣告在 `EpubSelectionInfo` 內，屬於「總是同時出現、應封裝為單一物件」
/// 的資料泥團，收斂為獨立值物件）。
class PercentRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PercentRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// 序列化為 JSON 字串，供 `highlights.pdf_rect_json`／`notes.pdf_rect_json`
  /// （TEXT 欄位）儲存使用，比照既有 `PdfCropRect.toJson()` 慣例。
  String toJson() => jsonEncode({
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      });

  /// 對應 [toJson] 的還原方法。
  factory PercentRect.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PercentRect(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      right: (map['right'] as num).toDouble(),
      bottom: (map['bottom'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PercentRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'PercentRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}
