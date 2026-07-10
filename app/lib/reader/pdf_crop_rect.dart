import 'dart:convert';

/// PDF 裁切矩形，四個座標皆為相對頁面尺寸的比例（0.0-1.0），與實際像素
/// /DPI/解析度無關，避免不同裝置渲染時跑位。見
/// docs/epics/epic-4-pdf-enhance/design.md「已知風險」。
class PdfCropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// 序列化為 JSON 字串，供 `book_reader_prefs.pdf_crop_rect`（TEXT 欄位）
  /// 儲存使用。
  String toJson() => jsonEncode({
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      });

  /// 對應 [toJson] 的還原方法。
  factory PdfCropRect.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PdfCropRect(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      right: (map['right'] as num).toDouble(),
      bottom: (map['bottom'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfCropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'PdfCropRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}
