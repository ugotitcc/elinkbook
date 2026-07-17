import 'highlight_style.dart';

/// 單一劃線（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 標記書中「一段選取範圍」，定位精度高於書籤（EPUB：Locator JSON，含
/// 選取範圍本身，非僅單點）。建立後不可改色/改樣式（spec.md 決策），
/// 需要改色時刪除重建。本 Issue 只涵蓋 EPUB 欄位；PDF 專屬欄位由
/// Issue 3 後續 migration 補上（見 Global Constraints）。
class Highlight {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String bookId;
  final HighlightStyle style;
  final String? epubLocatorJson;
  final double? progression;

  const Highlight({
    this.id,
    required this.bookId,
    required this.style,
    this.epubLocatorJson,
    this.progression,
  });

  /// 供 [HighlightsRepository.insert] 使用；刻意不含 `id`，比照
  /// `Bookmark.toMap()` 既有慣例（新增一律交由 SQLite `AUTOINCREMENT`
  /// 指派）。
  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'style': style.name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
    };
  }

  factory Highlight.fromMap(Map<String, Object?> map) {
    return Highlight(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      style: HighlightStyle.values.byName(map['style'] as String),
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.bookId == bookId &&
      other.style == style &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(id, bookId, style, epubLocatorJson, progression);

  @override
  String toString() =>
      'Highlight(id: $id, bookId: $bookId, style: $style, epubLocatorJson: $epubLocatorJson, progression: $progression)';
}
