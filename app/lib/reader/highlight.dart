import 'highlight_style.dart';
import 'percent_rect.dart';

/// 單一劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 標記書中「一段選取範圍」，定位精度高於書籤（EPUB：Locator JSON，含
/// 選取範圍本身；PDF：頁碼＋頁內矩形座標，Issue 3 新增）。建立後不可
/// 改色/改樣式（spec.md 決策），需要改色時刪除重建。[epubLocatorJson]／
/// [progression] 與 [pdfPageIndex]／[pdfRect] 互斥，一筆劃線只會用到其中
/// 一組（依書籍格式而定，比照 [Bookmark] 既有的欄位語意）。
class Highlight {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String bookId;
  final HighlightStyle style;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Highlight({
    this.id,
    required this.bookId,
    required this.style,
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
    this.pdfRect,
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
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Highlight.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Highlight(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      style: HighlightStyle.values.byName(map['style'] as String),
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.bookId == bookId &&
      other.style == style &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        style,
        epubLocatorJson,
        progression,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Highlight(id: $id, bookId: $bookId, style: $style, epubLocatorJson: $epubLocatorJson, progression: $progression, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
