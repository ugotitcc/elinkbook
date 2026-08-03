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

  /// 新增一筆書籤。UUID 由呼叫端產生並寫入 [Bookmark.id]。`updated_at`
  /// （epic-8-sync Issue 1，供雲端同步 dirty 判定使用）由本層補上目前
  /// 時間戳記，不放進 [Bookmark] 模型本身——模型只承載本機語意欄位，
  /// `updated_at`／`deleted_at` 是同步子系統專用的資料庫欄位
  /// （`deleted_at` 目前恆為 NULL，軟刪除轉換留給 Issue 4）。
  Future<void> insert(Bookmark bookmark) {
    return _db.insert('bookmarks', {
      ...bookmark.toMap(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 依書中位置順序排序（EPUB／FXL 用 progression 比例、PDF 用頁索引，
  /// 兩者互斥、一本書只會用到其中一組，見 [Bookmark] 欄位語意）。
  /// `COALESCE` 取兩欄位中非 null 的那一個當排序鍵——同一本書的所有書籤
  /// 必然只填其中一組欄位，不會混用。
  Future<List<Bookmark>> listByBook(String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> rename(String id, String newName) {
    return _db.update(
      'bookmarks',
      {
        'name': newName,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'bookmarks',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllForBook(String bookId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'bookmarks',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
}
