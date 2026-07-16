import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const bookmark = Bookmark(
      bookId: 'b1',
      name: '第二章 (35%)',
      epubLocatorJson: '{"href":"/c2.xhtml"}',
      progression: 0.35,
    );
    final map = bookmark.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['name'], '第二章 (35%)');
    expect(map['epub_locator_json'], '{"href":"/c2.xhtml"}');
    expect(map['progression'], 0.35);
    expect(map['pdf_page_index'], isNull);
  });

  test('fromMap 正確還原 id（模擬資料庫查詢結果）', () {
    final restored = Bookmark.fromMap({
      'id': 7,
      'book_id': 'b1',
      'name': '第 12 頁',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': 11,
    });
    expect(restored.id, 7);
    expect(restored.bookId, 'b1');
    expect(restored.name, '第 12 頁');
    expect(restored.pdfPageIndex, 11);
  });

  test('copyWith 只更新 name，其餘欄位保留原值', () {
    const original = Bookmark(
      id: 3,
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    );
    final renamed = original.copyWith(name: '新名稱');
    expect(renamed.id, 3);
    expect(renamed.bookId, 'b1');
    expect(renamed.name, '新名稱');
    expect(renamed.pdfPageIndex, 5);
  });

  test('defaultName：PDF 用「第 N 頁」（1-indexed 顯示）', () {
    const context = BookmarkPositionContext(pdfPageIndex: 11);
    expect(Bookmark.defaultName(context), '第 12 頁');
  });

  test(
      'defaultName：FXL（固定版面漫畫）沒有 pdfPageIndex 可用，回退為進度百分比'
      '（審查修正 1.1，見 tmp/epic-6/reviews/plan_issue_1_review.md）——'
      'FXL 副檔名是 .epub，ReaderScreen._openNotesSheet 只在'
      'format == BookFormat.pdf 時才填入 pdfPageIndex，FXL 永遠落在'
      'BookFormat.epub 分支、pdfPageIndex 恆為 null，且 FXL 通常無章節'
      '結構（_tocEntries 對固定版面永遠不預取），故實際只會走 progression'
      '這條路徑', () {
    const context = BookmarkPositionContext(progression: 0.42);
    expect(Bookmark.defaultName(context), '42% 處');
  });

  test('defaultName：EPUB 有章節名稱與進度時，組合成「章節 (百分比%)」', () {
    const context = BookmarkPositionContext(
      chapterTitle: '第二章',
      progression: 0.353,
    );
    expect(Bookmark.defaultName(context), '第二章 (35%)');
  });

  test('defaultName：EPUB 只有章節名稱、無進度時，僅顯示章節名稱', () {
    const context = BookmarkPositionContext(chapterTitle: '第二章');
    expect(Bookmark.defaultName(context), '第二章');
  });

  test('defaultName：EPUB 只有進度、無章節名稱時，顯示「百分比% 處」', () {
    const context = BookmarkPositionContext(progression: 0.5);
    expect(Bookmark.defaultName(context), '50% 處');
  });

  test('defaultName：章節名稱與進度皆無法取得時，回退為「書籤」', () {
    const context = BookmarkPositionContext();
    expect(Bookmark.defaultName(context), '書籤');
  });

  test('兩個欄位值完全相同的 Bookmark 視為相等', () {
    const a = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 1, bookId: 'b1', name: 'Y', pdfPageIndex: 5);
    expect(a, isNot(b));
  });
}
