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

  /// 排序鍵：PDF 用 `pdfPageIndex`、EPUB 用 `progression`，兩者互斥（Issue 3
  /// 修正——原本只讀 `progression`，PDF 項目的 `progression` 恆為 null，
  /// 會導致所有 PDF 劃線/備註排序鍵皆為 0、清單順序失去意義）。
  double get _position =>
      (highlight?.pdfPageIndex ?? note?.pdfPageIndex)?.toDouble() ??
      highlight?.progression ??
      note?.progression ??
      0;
}

/// 合併 [highlights]／[notes] 兩份清單成單一依書中位置排序的顯示清單
/// （spec.md「資料模型關聯」／「側邊欄清單合併顯示」）。演算法：先以
/// `note.highlightId` 建立索引，能對應到 [highlights] 清單內某筆
/// highlight 的 note 與該 highlight 合併成一筆；其餘 note（`highlightId
/// == null` 的純備註，見 `highlight_id IS NULL` 即為純備註的既定判斷
/// 依據，**或** `highlightId` 未對應到 [highlights] 清單中任何一筆——
/// 審查修正：正常呼叫路徑下不會發生，因為呼叫端一律同時查詢同一本書的
/// 完整 highlights/notes 兩份清單，FK `ON DELETE SET NULL` 也保證真正
/// 刪除劃線後 `highlightId` 會被資料庫清成 null；但本函式作為可獨立測試
/// 的純函式，仍防禦性地把這種輸入不一致的情況視同純備註顯示，而非讓該筆
/// note 完全消失在清單外）各自獨立成一筆；最後依 [Highlight.progression]／
/// [Note.progression] 由小到大排序。
List<AnnotationListItem> mergeAnnotations(
  List<Highlight> highlights,
  List<Note> notes,
) {
  final highlightIds = highlights.map((h) => h.id).whereType<int>().toSet();
  final noteByHighlightId = <int, Note>{};
  final standaloneNotes = <Note>[];
  for (final note in notes) {
    final highlightId = note.highlightId;
    if (highlightId != null && highlightIds.contains(highlightId)) {
      noteByHighlightId[highlightId] = note;
    } else {
      standaloneNotes.add(note);
    }
  }

  final items = <AnnotationListItem>[
    for (final highlight in highlights)
      AnnotationListItem(highlight: highlight, note: noteByHighlightId[highlight.id]),
    for (final note in standaloneNotes) AnnotationListItem(note: note),
  ];
  items.sort((a, b) => a._position.compareTo(b._position));
  return items;
}
