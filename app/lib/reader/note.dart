import 'percent_rect.dart';

/// 單一備註（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 自由文字內容，可獨立於劃線存在。[highlightId] 為 null 代表純備註
/// （無劃線），非 null 代表依附於某一筆 [Highlight]（見 spec.md「資料
/// 模型關聯」——`notes.highlight_id REFERENCES highlights(id) ON DELETE
/// SET NULL`，批次刪除劃線後此欄位由資料庫自動退化為 null）。
/// [epubLocatorJson]／[progression] 與 [pdfPageIndex]／[pdfRect]（Issue 3
/// 新增）互斥，比照 [Highlight] 的既有欄位語意。
class Note {
  final int? id;
  final String bookId;
  final String text;
  final String? epubLocatorJson;
  final double? progression;
  final int? highlightId;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Note({
    this.id,
    required this.bookId,
    required this.text,
    this.epubLocatorJson,
    this.progression,
    this.highlightId,
    this.pdfPageIndex,
    this.pdfRect,
  });

  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'text': text,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'highlight_id': highlightId,
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Note(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      text: map['text'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      highlightId: map['highlight_id'] as int?,
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  Note copyWith({String? text}) {
    return Note(
      id: id,
      bookId: bookId,
      text: text ?? this.text,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      highlightId: highlightId,
      pdfPageIndex: pdfPageIndex,
      pdfRect: pdfRect,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.text == text &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.highlightId == highlightId &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        text,
        epubLocatorJson,
        progression,
        highlightId,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Note(id: $id, bookId: $bookId, text: $text, epubLocatorJson: $epubLocatorJson, progression: $progression, highlightId: $highlightId, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
