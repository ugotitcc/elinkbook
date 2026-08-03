import 'package:sqflite/sqflite.dart';

import 'note.dart';

/// `notes` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線與備註
/// 模組」）。FK `ON DELETE SET NULL` 的退化行為由資料庫本身保證（見
/// sqlite_library_repository.dart `_createNotesTable`），本類別不需要
/// 額外實作任何退化邏輯，`listByBook` 讀到的 `highlight_id` 已經是
/// 資料庫層級處理過的最終結果。
class NotesRepository {
  final Database _db;

  const NotesRepository(this._db);

  /// `updated_at`（epic-8-sync Issue 1，供雲端同步 dirty 判定使用，見
  /// `sqlite_library_repository.dart` `_createNotesTable`）由本層補上
  /// 目前時間戳記，不放進 [Note] 模型本身——模型只承載本機語意欄位，
  /// `updated_at`／`deleted_at` 是同步子系統專用的資料庫欄位
  /// （`deleted_at` 目前恆為 NULL，軟刪除轉換留給 Issue 4）。
  Future<void> insert(Note note) {
    return _db.insert('notes', {
      ...note.toMap(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 依書中位置順序排序，比照 [HighlightsRepository.listByBook] 的
  /// `COALESCE` 慣例（Issue 3 新增）。
  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> updateText(String id, String text) {
    return _db.update(
      'notes',
      {
        'text': text,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) {
    return _db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('notes', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
