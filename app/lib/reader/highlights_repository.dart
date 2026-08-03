import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  /// `updated_at`（epic-8-sync Issue 1，供雲端同步 dirty 判定使用，見
  /// `sqlite_library_repository.dart` `_createHighlightsTable`）由本層
  /// 補上目前時間戳記，不放進 [Highlight] 模型本身——模型只承載本機
  /// 語意欄位，`updated_at`／`deleted_at` 是同步子系統專用的資料庫欄位
  /// （`deleted_at` 目前恆為 NULL，軟刪除轉換留給 Issue 4）。
  Future<void> insert(Highlight highlight) {
    return _db.insert('highlights', {
      ...highlight.toMap(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 依書中位置順序排序：EPUB 用 `progression` 比例、PDF 用
  /// `pdf_page_index`（Issue 3 新增），兩者互斥、一本書只會用到其中一組
  /// （比照 `BookmarksRepository.listByBook` 既有的 `COALESCE` 慣例）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  Future<void> delete(String id) {
    return _db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('highlights', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
