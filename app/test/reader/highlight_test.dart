import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（含 id）', () {
    const highlight = Highlight(
      id: 'h1',
      bookId: 'b1',
      style: HighlightStyle.highlighterPink,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
    );
    final map = highlight.toMap();
    expect(map['id'], 'h1');
    expect(map['book_id'], 'b1');
    expect(map['style'], 'highlighterPink');
    expect(map['epub_locator_json'], '{"href":"/c1.xhtml"}');
    expect(map['progression'], 0.2);
  });

  test('fromMap 正確還原 id 與 style（模擬資料庫查詢結果）', () {
    final restored = Highlight.fromMap({
      'id': 'h5',
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c2.xhtml"}',
      'progression': 0.4,
    });
    expect(restored.id, 'h5');
    expect(restored.style, HighlightStyle.underline);
    expect(restored.progression, 0.4);
  });

  test('兩個欄位值完全相同的 Highlight 視為相等', () {
    const a = Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    const b = Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('toMap／fromMap round-trip 保留 PDF 欄位（pdfPageIndex／pdfRect）', () {
    const highlight = Highlight(
      id: 'h2',
      bookId: 'b1',
      style: HighlightStyle.underline,
      pdfPageIndex: 3,
      pdfRect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    final map = highlight.toMap();
    expect(map['pdf_page_index'], 3);
    expect(map['pdf_rect_json'], isNotNull);

    final restored = Highlight.fromMap({
      'id': 'h2',
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': map['pdf_page_index'],
      'pdf_rect_json': map['pdf_rect_json'],
    });
    expect(restored.pdfPageIndex, 3);
    expect(restored.pdfRect, const PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4));
  });

  test('fromMap 缺少 pdf_page_index／pdf_rect_json 鍵時（EPUB 既有資料列）視為 null', () {
    final restored = Highlight.fromMap({
      'id': 'h1',
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
    });
    expect(restored.pdfPageIndex, isNull);
    expect(restored.pdfRect, isNull);
  });
}
