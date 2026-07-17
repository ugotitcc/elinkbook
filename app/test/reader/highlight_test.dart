import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const highlight = Highlight(
      bookId: 'b1',
      style: HighlightStyle.highlighterPink,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
    );
    final map = highlight.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['style'], 'highlighterPink');
    expect(map['epub_locator_json'], '{"href":"/c1.xhtml"}');
    expect(map['progression'], 0.2);
  });

  test('fromMap 正確還原 id 與 style（模擬資料庫查詢結果）', () {
    final restored = Highlight.fromMap({
      'id': 5,
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c2.xhtml"}',
      'progression': 0.4,
    });
    expect(restored.id, 5);
    expect(restored.style, HighlightStyle.underline);
    expect(restored.progression, 0.4);
  });

  test('兩個欄位值完全相同的 Highlight 視為相等', () {
    const a = Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    const b = Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
