/// 單一備註（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 自由文字內容，可獨立於劃線存在。[highlightId] 為 null 代表純備註
/// （無劃線），非 null 代表依附於某一筆 [Highlight]（見 spec.md「資料
/// 模型關聯」——`notes.highlight_id REFERENCES highlights(id) ON DELETE
/// SET NULL`，批次刪除劃線後此欄位由資料庫自動退化為 null）。
class Note {
  final int? id;
  final String bookId;
  final String text;
  final String? epubLocatorJson;
  final double? progression;
  final int? highlightId;

  const Note({
    this.id,
    required this.bookId,
    required this.text,
    this.epubLocatorJson,
    this.progression,
    this.highlightId,
  });

  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'text': text,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'highlight_id': highlightId,
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      text: map['text'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      highlightId: map['highlight_id'] as int?,
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
      other.highlightId == highlightId;

  @override
  int get hashCode =>
      Object.hash(id, bookId, text, epubLocatorJson, progression, highlightId);

  @override
  String toString() =>
      'Note(id: $id, bookId: $bookId, text: $text, epubLocatorJson: $epubLocatorJson, progression: $progression, highlightId: $highlightId)';
}
