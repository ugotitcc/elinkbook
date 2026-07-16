import 'package:sqflite/sqflite.dart';

import 'reading_position.dart';

/// `books` 表 `epubLocator`/`pdfPageIndex`/`progress` 3 個欄位的存取層
/// （見 `SqliteLibraryRepository` 的 schema 定義）。與 [SqliteLibraryRepository]
/// 共用同一個 [Database] 連線，比照 [BookReaderPrefsRepository] 的既有模式。
/// 刻意不透過 `LibraryRepository.updateBook(Book)` 寫入——那是整列覆寫，
/// 呼叫端（見 ReaderPrefsManagerImpl）手上沒有完整 Book 物件的其餘欄位
/// （title/author/coverPath 等），partial UPDATE 才能安全地只更新這 3 欄。
class ReadingPositionRepository {
  final Database _db;

  const ReadingPositionRepository(this._db);

  /// 無對應書籍列時回傳預設值（等同尚無記錄）。
  Future<ReadingPosition> load(String bookId) async {
    final rows = await _db.query(
      'books',
      columns: ['epubLocator', 'pdfPageIndex', 'progress'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return const ReadingPosition();
    final row = rows.single;
    return ReadingPosition(
      epubLocatorJson: row['epubLocator'] as String?,
      pdfPageIndex: row['pdfPageIndex'] as int?,
      // SQLite 對無小數部分的 REAL 欄位可能讀回 int（見 Book.fromMap 既有
      // 處理方式），故用 num? 轉換，不可直接 `as double?`。
      progress: (row['progress'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Partial update：只更新這 3 個欄位，不影響書籍的其餘欄位。若
  /// [bookId] 對應的書籍列不存在（理論上不應發生——呼叫端一定是先從
  /// 圖書庫開啟既有書籍才會進到 ReaderScreen），SQLite 的 UPDATE 會影響
  /// 0 列，靜默無效果，不拋出例外。
  Future<void> save(String bookId, ReadingPosition position) async {
    await _db.update(
      'books',
      {
        'epubLocator': position.epubLocatorJson,
        'pdfPageIndex': position.pdfPageIndex,
        'progress': position.progress,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
}
