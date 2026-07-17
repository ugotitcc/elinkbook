import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  test('只有劃線、無備註：每筆各自成一個項目', () {
    final highlights = [
      const Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
      const Highlight(id: 2, bookId: 'b1', style: HighlightStyle.highlighterYellow, progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, const []);
    expect(items, hasLength(2));
    expect(items[0].highlight?.id, 1);
    expect(items[0].note, isNull);
  });

  test('只有純備註（highlightId 為 null）：每筆各自成一個項目', () {
    final notes = [
      const Note(id: 9, bookId: 'b1', text: '純備註', progression: 0.3),
    ];
    final items = mergeAnnotations(const [], notes);
    expect(items, hasLength(1));
    expect(items.single.highlight, isNull);
    expect(items.single.note?.id, 9);
  });

  test('劃線＋依附備註（highlightId 指向該劃線）：合併成一個項目', () {
    final highlights = [
      const Highlight(id: 4, bookId: 'b1', style: HighlightStyle.highlighterPink, progression: 0.2),
    ];
    final notes = [
      const Note(id: 10, bookId: 'b1', text: '心得', progression: 0.2, highlightId: 4),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items, hasLength(1));
    expect(items.single.highlight?.id, 4);
    expect(items.single.note?.id, 10);
  });

  test('依 progression 由小到大排序，合併項目與純備註/純劃線混合排序', () {
    final highlights = [
      const Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.8),
      const Highlight(id: 2, bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    ];
    final notes = [
      const Note(id: 5, bookId: 'b1', text: '純備註', progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items.map((i) => i.highlight?.id ?? -i.note!.id!).toList(), [2, -5, 1]);
  });

  test('AnnotationListItem.key 對相同 highlight/note 組合回傳相同值', () {
    const a = AnnotationListItem(
      highlight: Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline),
    );
    const b = AnnotationListItem(
      highlight: Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline),
    );
    expect(a.key, b.key);
  });
}
