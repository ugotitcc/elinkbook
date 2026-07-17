import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const note = Note(
      bookId: 'b1',
      text: '這段很重要',
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      highlightId: 7,
    );
    final map = note.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['text'], '這段很重要');
    expect(map['highlight_id'], 7);
  });

  test('fromMap 正確還原 highlight_id 為 null（純備註）', () {
    final restored = Note.fromMap({
      'id': 3,
      'book_id': 'b1',
      'text': '純備註內容',
      'epub_locator_json': '{"href":"/c2.xhtml"}',
      'progression': 0.5,
      'highlight_id': null,
    });
    expect(restored.highlightId, isNull);
    expect(restored.text, '純備註內容');
  });

  test('copyWith 只更新 text，其餘欄位保留原值', () {
    const original = Note(id: 1, bookId: 'b1', text: '舊文字', highlightId: 2);
    final updated = original.copyWith(text: '新文字');
    expect(updated.id, 1);
    expect(updated.highlightId, 2);
    expect(updated.text, '新文字');
  });

  test('兩個欄位值完全相同的 Note 視為相等', () {
    const a = Note(id: 1, bookId: 'b1', text: 'X', highlightId: null);
    const b = Note(id: 1, bookId: 'b1', text: 'X', highlightId: null);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
