import 'package:sqflite/sqflite.dart';

import 'bookmark.dart';

/// `bookmarks` 表的存取層（epic-6-annotations Issue 1，spec.md「書籤
/// 模組」）。與 [SqliteLibraryRepository] 共用同一個 [Database] 連線，
/// 比照既有 `BookReaderPrefsRepository`／`ReadingPositionRepository`
/// 模式（`bookmarks.book_id` 的外鍵約束要求與 `books` 表在同一個資料庫
/// 檔案內）。
class BookmarksRepository {
  final Database _db;

  const BookmarksRepository(this._db);

  /// 新增一筆書籤，回傳 SQLite 自動指派的 rowid。
  Future<int> insert(Bookmark bookmark) {
    return _db.insert('bookmarks', bookmark.toMap());
  }

  /// 依書中位置順序排序（EPUB／FXL 用 progression 比例、PDF 用頁索引，
  /// 兩者互斥、一本書只會用到其中一組，見 [Bookmark] 欄位語意）。
  /// `COALESCE` 取兩欄位中非 null 的那一個當排序鍵——同一本書的所有書籤
  /// 必然只填其中一組欄位，不會混用。
  Future<List<Bookmark>> listByBook(String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> rename(int id, String newName) {
    return _db.update(
      'bookmarks',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) {
    return _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('bookmarks', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
