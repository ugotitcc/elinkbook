import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  test('只有劃線、無備註：每筆各自成一個項目', () {
    final highlights = [
      const Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
      const Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.highlighterYellow, progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, const []);
    expect(items, hasLength(2));
    expect(items[0].highlight?.id, 'h1');
    expect(items[0].note, isNull);
  });

  test('只有純備註（highlightId 為 null）：每筆各自成一個項目', () {
    final notes = [
      const Note(id: 'n9', bookId: 'b1', text: '純備註', progression: 0.3),
    ];
    final items = mergeAnnotations(const [], notes);
    expect(items, hasLength(1));
    expect(items.single.highlight, isNull);
    expect(items.single.note?.id, 'n9');
  });

  test('劃線＋依附備註（highlightId 指向該劃線）：合併成一個項目', () {
    final highlights = [
      const Highlight(id: 'h4', bookId: 'b1', style: HighlightStyle.highlighterPink, progression: 0.2),
    ];
    final notes = [
      const Note(id: 'n10', bookId: 'b1', text: '心得', progression: 0.2, highlightId: 'h4'),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items, hasLength(1));
    expect(items.single.highlight?.id, 'h4');
    expect(items.single.note?.id, 'n10');
  });

  test('依 progression 由小到大排序，合併項目與純備註/純劃線混合排序', () {
    final highlights = [
      const Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.8),
      const Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    ];
    final notes = [
      const Note(id: 'n5', bookId: 'b1', text: '純備註', progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items.map((i) => i.highlight?.id ?? '_note_${i.note!.id}').toList(), ['h2', '_note_n5', 'h1']);
  });

  test(
      '審查修正：note.highlightId 指向的 highlight 不在傳入的 highlights 清單中時，'
      '該筆備註仍以獨立項目顯示，不會從清單中完全消失', () {
    final notes = [
      const Note(id: 'n7', bookId: 'b1', text: '孤兒備註', progression: 0.4, highlightId: 'h999'),
    ];
    final items = mergeAnnotations(const [], notes);
    expect(items, hasLength(1));
    expect(items.single.highlight, isNull);
    expect(items.single.note?.id, 'n7');
  });

  test('AnnotationListItem.key 對相同 highlight/note 組合回傳相同值', () {
    const a = AnnotationListItem(
      highlight: Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline),
    );
    const b = AnnotationListItem(
      highlight: Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline),
    );
    expect(a.key, b.key);
  });

  test('PDF 項目依 pdfPageIndex 由小到大排序（修正 progression 恆為 null 時排序鍵失效的缺陷）',
      () {
    final highlights = [
      const Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 9),
      const Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 0),
    ];
    final notes = [
      const Note(id: 'n5', bookId: 'b1', text: '純備註', pdfPageIndex: 4),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items.map((i) => i.highlight?.id ?? '_note_${i.note!.id}').toList(), ['h2', '_note_n5', 'h1']);
  });
}
