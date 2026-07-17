import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  Future<int> insert(Highlight highlight) {
    return _db.insert('highlights', highlight.toMap());
  }

  /// 依書中位置順序排序（本 Issue 只有 EPUB，故直接用 progression；PDF
  /// 欄位由 Issue 3 補上時，這裡的 ORDER BY 需要改回 bookmarks 既有的
  /// `COALESCE(...)` 寫法，屬 Issue 3 範圍）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'progression ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  Future<void> delete(int id) {
    return _db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('highlights', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
