import 'package:sqflite/sqflite.dart';

import 'reading_position.dart';

/// `books` 表 `epubLocator`/`pdfPageIndex`/`progress`/`lastReadTime` 4 個
/// 欄位的存取層（見 `SqliteLibraryRepository` 的 schema 定義）。與
/// [SqliteLibraryRepository] 共用同一個 [Database] 連線，比照
/// [BookReaderPrefsRepository] 的既有模式。刻意不透過
/// `LibraryRepository.updateBook(Book)` 寫入——那是整列覆寫，呼叫端（見
/// ReaderPrefsManagerImpl）手上沒有完整 Book 物件的其餘欄位
/// （title/author/coverPath 等），partial UPDATE 才能安全地只更新這幾欄。
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

  /// Partial update：只更新這 4 個欄位（及 epic-8-sync Issue 5 新增的
  /// `position_updated_at`），不影響書籍的其餘欄位。若 [bookId] 對應的
  /// 書籍列不存在（理論上不應發生——呼叫端一定是先從圖書庫開啟既有
  /// 書籍才會進到 ReaderScreen），SQLite 的 UPDATE 會影響 0 列，靜默無
  /// 效果，不拋出例外。
  ///
  /// `position_updated_at` 由本方法統一維護（而非呼叫端），確保「使用者
  /// 讀過這本書、位置有異動」與「同步引擎判斷這本書的位置需要推送」
  /// 兩者永遠同步、不會遺漏（epic-8-sync Issue 5，spec.md「本機 Schema
  /// 變更」／「同步引擎」）。
  ///
  /// 【診斷修正，epic-18-reader-device-qa Issue 29】`lastReadTime` 也在
  /// 這裡統一維護：這是「使用者真的讀了這本書、位置有異動」發生的當下，
  /// 語意上正是「最後閱讀時間」該更新的時機。修正前 `lastReadTime` 只在
  /// `BookImportServiceImpl` 匯入當下寫一次值，之後永遠不再更新——導致
  /// 「啟動時開啟最後閱讀的那本書」與圖書庫「最後閱讀」排序，兩者的判斷
  /// 依據其實是「最後匯入時間」，剛匯入、從未打開過的書會被誤判為「最後
  /// 閱讀」蓋過真正最近在讀的書。
  Future<void> save(String bookId, ReadingPosition position) async {
    await _db.update(
      'books',
      {
        'epubLocator': position.epubLocatorJson,
        'pdfPageIndex': position.pdfPageIndex,
        'progress': position.progress,
        'position_updated_at': DateTime.now().millisecondsSinceEpoch,
        'lastReadTime': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
}
