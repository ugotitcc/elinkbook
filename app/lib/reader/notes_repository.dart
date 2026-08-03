import 'package:sqflite/sqflite.dart';

import 'note.dart';

/// `notes` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線與備註
/// 模組」）。`deleted_at IS NULL` 過濾已內建於 [listByBook]，供 UI
/// 隱藏已（軟）刪除的紀錄；雲端同步引擎直接用 `_db.rawQuery` 讀取
/// 所有列（含已刪除），不經過本 repository（見 Task 7/8）。
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
  /// `COALESCE` 慣例（Issue 3 新增）。`deleted_at IS NULL` 排除已（軟）
  /// 刪除的紀錄（epic-8-sync Issue 4）。
  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ? AND deleted_at IS NULL',
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
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'notes',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllForBook(String bookId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'notes',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
}
