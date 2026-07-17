import 'highlight.dart';
import 'note.dart';

/// 「劃線與備註」側邊欄清單的單一顯示項目（epic-6-annotations Issue 2，
/// spec.md「資料模型關聯」：同一選取範圍若同時有 highlight 與指向它的
/// note，清單以一筆呈現）。[highlight]／[note] 至少一個非 null——三種
/// 合法組合：純劃線（note 為 null）、純備註（highlight 為 null）、
/// 劃線+依附備註（兩者皆非 null）。
class AnnotationListItem {
  final Highlight? highlight;
  final Note? note;

  const AnnotationListItem({this.highlight, this.note})
      : assert(highlight != null || note != null,
            'AnnotationListItem 的 highlight／note 至少須有一個非 null');

  /// 供 UI 當作 Widget Key／比對用的穩定識別字串，組合 highlight/note
  /// 各自的資料庫 id（其中一個可能為 null）。
  String get key => 'h${highlight?.id}_n${note?.id}';

  double get _position => highlight?.progression ?? note?.progression ?? 0;
}

/// 合併 [highlights]／[notes] 兩份清單成單一依書中位置排序的顯示清單
/// （spec.md「資料模型關聯」／「側邊欄清單合併顯示」）。演算法：先以
/// `note.highlightId` 建立索引，能對應到 highlight 的 note 與該
/// highlight 合併成一筆；`highlightId == null` 的 note 各自獨立成一筆
/// （純備註，見 `highlight_id IS NULL` 即為純備註的既定判斷依據）；最後
/// 依 [Highlight.progression]／[Note.progression] 由小到大排序。
List<AnnotationListItem> mergeAnnotations(
  List<Highlight> highlights,
  List<Note> notes,
) {
  final noteByHighlightId = <int, Note>{};
  final pureNotes = <Note>[];
  for (final note in notes) {
    final highlightId = note.highlightId;
    if (highlightId != null) {
      noteByHighlightId[highlightId] = note;
    } else {
      pureNotes.add(note);
    }
  }

  final items = <AnnotationListItem>[
    for (final highlight in highlights)
      AnnotationListItem(highlight: highlight, note: noteByHighlightId[highlight.id]),
    for (final note in pureNotes) AnnotationListItem(note: note),
  ];
  items.sort((a, b) => a._position.compareTo(b._position));
  return items;
}
