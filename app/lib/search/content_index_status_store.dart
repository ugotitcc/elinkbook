// app/lib/search/content_index_status_store.dart
import 'package:sqflite/sqflite.dart';

/// 「啟用全文檢索」的兩個獨立分類（epic-10-search Issue 3，見 spec.md
/// §4）：PDF 走純 Dart/FFI 但可能因掃描件缺乏文字層而索引無效；其餘格式
/// （Foliate：epub/txt/azw3/md，**不含 cbz**——見 [ContentIndexStatusStore]
/// 內 `_formatFilterFor` 說明）走 Headless WebView 資源較重但幾乎必有
/// 文字層，兩者關切點互補，故拆成兩個獨立開關。
///
/// 【epic-41-search-architecture-hardening Issue 2】原定義於
/// `full_text_search_settings_repository.dart`，隨 `content_index_status`
/// 狀態存取邏輯一併收斂到本檔案；該檔案改用
/// `export 'content_index_status_store.dart' show ContentIndexCategory;`
/// 重新導出，既有匯入 `full_text_search_settings_repository.dart` 的呼叫端
/// 不需要修改任何 import 路徑。
enum ContentIndexCategory { pdf, foliate }

/// 收斂 `content_index_status`／`book_content_index` 兩張表所有寫入/查詢
/// 邏輯的模組（epic-41-search-architecture-hardening Issue 2）。原本這些
/// SQL 分散在 `ContentIndexingScheduler`（單書狀態轉換）與
/// `SqliteFullTextSearchSettingsRepository`（分類批次回填/清除）兩個檔案
/// 各自手寫，兩邊都要各自知道欄位名稱與合法狀態字串，拼字錯誤不會被型別
/// 系統攔到。本類別只收「純狀態資料存取」，**不收**排程迴圈「中途要不要
/// 繼續處理」這個決策——那仍是 `ContentIndexingScheduler` 自己的職責，只是
/// 改呼叫 [isTracked] 取得資料再自行判斷（`/grilling` Q4；見
/// `docs/epics/epic-41-search-architecture-hardening/issues.md` Issue 2）。
///
/// 建構子接受具體型別 [Database]（非 `DatabaseExecutor`）——[deleteForBook]／
/// [backfillPending]／[clearByCategory] 內部皆需要 `Database.transaction()`，
/// 這支方法不存在於 `DatabaseExecutor` 介面，查證 sqflite 實際 API 後
/// 修正（見 `plans/plan-issue-2.md` Global Constraints）。
class ContentIndexStatusStore {
  const ContentIndexStatusStore(this._db);

  final Database _db;

  /// 回傳的字串片段假設呼叫端已在 SQL 中定位到 `books` 表（或其別名）的
  /// `format` 欄位。`pdf` → `format = 'pdf'`；`foliate` → 其餘格式扣除
  /// `cbz`（CBZ 無文字層，天生被排除，光憑 `format` 字串本身就能判斷）。
  static String _formatFilterFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? "format = 'pdf'"
          : "format != 'pdf' AND format != 'cbz'";

  /// 單書標記為 `pending`（已存在資料列時不覆蓋既有 status）。
  Future<void> markPending(String bookId) => _db.insert(
        'content_index_status',
        {
          'book_id': bookId,
          'status': 'pending',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// 轉態為 `indexing`，不動 `last_chapter_index`（該書資料列已存在，用
  /// `update` 而非 `insert`）。
  Future<void> markIndexing(String bookId) => _db.update(
        'content_index_status',
        {
          'status': 'indexing',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

  /// 每完成一個章節呼叫一次，更新續跑游標，不改變 `status`。
  Future<void> updateProgress(String bookId, int lastChapterIndex) =>
      _db.update(
        'content_index_status',
        {
          'last_chapter_index': lastChapterIndex,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

  Future<void> markDone(String bookId) => _db.update(
        'content_index_status',
        {'status': 'done', 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

  Future<void> markError(String bookId, {required String error}) => _db.update(
        'content_index_status',
        {
          'status': 'error',
          'error_message': error,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

  /// 單書標記為 `unsupported`（已存在資料列時不覆蓋）。CBZ 匯入當下呼叫，
  /// 天生被排程器的 pending 查詢排除。
  Future<void> markUnsupported(String bookId) => _db.insert(
        'content_index_status',
        {
          'book_id': bookId,
          'status': 'unsupported',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// [bookId] 對應的 `content_index_status` 列是否仍然存在——用於排程器在
  /// 每個章節邊界檢查該書是否仍被追蹤，一旦消失即代表已被外部關閉並捨棄
  /// 進度。
  Future<bool> isTracked(String bookId) async {
    final rows = await _db.query(
      'content_index_status',
      columns: ['book_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 刪除單一書籍的索引資料（`book_content_index`／`content_index_status`
  /// 兩張表，同一交易內），trigger 同步清空對應 FTS 列。取代原本
  /// `SqliteFullTextSearchSettingsRepository.clearBookIndex()`，也供
  /// `ContentIndexingScheduler` 在偵測到中途被取消時清除殘留列——兩種呼叫
  /// 情境皆是「不論目前是否還有資料列，統統刪乾淨」，方法本身天生冪等
  /// （`DELETE ... WHERE book_id = ?` 對已空的表是 no-op）。
  Future<void> deleteForBook(String bookId) => _db.transaction((txn) async {
        await txn.delete('book_content_index',
            where: 'book_id = ?', whereArgs: [bookId]);
        await txn.delete('content_index_status',
            where: 'book_id = ?', whereArgs: [bookId]);
      });

  /// 把 `content_index_status` 中尚無資料列、且格式符合 [category]、且已
  /// 下載的既有書籍批次插入 `pending`。已有資料列的書籍一律跳過，不重複
  /// 插入也不覆蓋既有 status。**`foliate` 分類額外**把既有尚無資料列、且
  /// 已下載的 `cbz` 書籍批次標記為 `unsupported`，不進入 `pending` 佇列。
  Future<void> backfillPending(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    final now = DateTime.now().millisecondsSinceEpoch;
    // 【審查修正 I-1】兩句 INSERT 包在同一交易內——與本類別 doc comment／
    // plan-issue-2.md Global Constraints 已宣稱的「backfillPending 需要
    // .transaction()」保持一致，避免 foliate 分類執行到一半中斷造成部分
    // 書籍已插入 pending、部分尚未插入 unsupported 的不一致狀態。
    await _db.transaction((txn) async {
      await txn.rawInsert('''
        INSERT INTO content_index_status (book_id, status, updated_at)
        SELECT b.id, 'pending', ?
        FROM books b
        LEFT JOIN content_index_status cis ON cis.book_id = b.id
        WHERE cis.book_id IS NULL
          AND b.is_downloaded = 1
          AND b.$formatFilter
      ''', [now]);
      if (category == ContentIndexCategory.foliate) {
        await txn.rawInsert('''
          INSERT INTO content_index_status (book_id, status, updated_at)
          SELECT b.id, 'unsupported', ?
          FROM books b
          LEFT JOIN content_index_status cis ON cis.book_id = b.id
          WHERE cis.book_id IS NULL
            AND b.is_downloaded = 1
            AND b.format = 'cbz'
        ''', [now]);
      }
    });
  }

  /// 刪除 [category] 對應格式書籍的索引資料（`book_content_index`／
  /// `content_index_status`），trigger 同步清空對應 FTS 列。兩句 `DELETE`
  /// 包在同一交易內，避免中途斷電/crash 造成兩張表資料不一致。不影響另
  /// 一分類已建立的索引。
  Future<void> clearByCategory(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    await _db.transaction((txn) async {
      await txn.rawDelete('''
        DELETE FROM book_content_index
        WHERE book_id IN (SELECT id FROM books WHERE $formatFilter)
      ''');
      await txn.rawDelete('''
        DELETE FROM content_index_status
        WHERE book_id IN (SELECT id FROM books WHERE $formatFilter)
      ''');
    });
  }
}
