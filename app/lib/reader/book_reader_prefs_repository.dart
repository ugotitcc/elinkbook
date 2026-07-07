import 'package:sqflite/sqflite.dart';

import 'book_reader_prefs.dart';

/// `book_reader_prefs` 表的存取層（見 `SqliteLibraryRepository` 的 schema
/// 定義）。與 [SqliteLibraryRepository] 共用同一個 [Database] 連線，因為
/// `book_reader_prefs.book_id` 的外鍵約束要求與 `books` 表在同一個資料庫
/// 檔案內。
class BookReaderPrefsRepository {
  final Database _db;

  const BookReaderPrefsRepository(this._db);

  /// 無對應書籍列時回傳 [BookReaderPrefs.empty]（等同所有欄位皆未覆寫）。
  Future<BookReaderPrefs> load(String bookId) async {
    final rows = await _db.query(
      'book_reader_prefs',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return BookReaderPrefs.empty;
    return BookReaderPrefs.fromMap(rows.single);
  }

  /// Upsert：若該書已有偏好設定列，整列覆寫為 [prefs] 的內容。
  ///
  /// [ConflictAlgorithm.replace] 底層是 `INSERT OR REPLACE`，主鍵衝突時
  /// SQLite 會先 `DELETE` 舊列、再 `INSERT` 新列（先刪後增）。目前沒有其他
  /// 表以 `book_reader_prefs` 為外鍵，此行為是安全的；但若未來有其他表
  /// 關聯到本表，需重新評估這個「先刪後增」是否會意外觸發連鎖刪除。
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    await _db.insert(
      'book_reader_prefs',
      prefs.toMap(bookId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
