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

  Future<int> insert(Note note) {
    return _db.insert('notes', note.toMap());
  }

  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'progression ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> updateText(int id, String text) {
    return _db.update('notes', {'text': text}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) {
    return _db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('notes', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
