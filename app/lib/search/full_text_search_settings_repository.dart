// app/lib/search/full_text_search_settings_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../library/models/book.dart';
import '../library/models/library_enums.dart';

/// 「啟用全文檢索」的兩個獨立分類（epic-10-search Issue 3，見 spec.md
/// §4）：PDF 走純 Dart/FFI 但可能因掃描件缺乏文字層而索引無效；其餘格式
/// （Foliate：epub/txt/azw3/md，**不含 cbz**——見下方 `_formatFilterFor`
/// 說明）走 Headless WebView 資源較重但幾乎必有文字層，兩者關切點互補，
/// 故拆成兩個獨立開關。
enum ContentIndexCategory { pdf, foliate }

/// 「啟用全文檢索」設定模型（spec.md §4）：兩個分類各自的持久化開關，
/// 開啟時批次回填既有書庫（寫入 pending，交給建構子注入的
/// `requestProcessing` 喚醒排程器），關閉時立即清除該分類已建立的索引
/// 資料，兩個分類互不影響；[rebuildIndex] 供使用者手動重建（issues.md
/// Issue 3 單元測試要求／驗收標準明訂，review-plan-issue-3.md I-1）。
abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
  Future<void> rebuildIndex(ContentIndexCategory category);

  /// 把 [bookId] 標記為 `content_index_status.status = 'unsupported'`
  /// （epic-10-search Issue 2，見 spec.md §7）：CBZ 匯入當下呼叫，天生被
  /// 排程器的 pending 查詢排除（`status != 'pending'/'indexing'`）。已有
  /// 資料列時不覆蓋。
  Future<void> markUnsupported(String bookId);

  /// [book] 剛變成本機可用（首次匯入完成，或既有書籍重新下載完成）時
  /// 呼叫（epic-10-search Issue 2，見 spec.md §7）：CBZ 一律標記
  /// `unsupported`；其餘格式依 `book.format` 對應的 [ContentIndexCategory]
  /// 是否已啟用，已啟用才補插入一筆 `status='pending'` 並喚醒排程器，未
  /// 啟用則不插入。`book.isDownloaded` 必須為 `true`——`false` 時直接不做
  /// 任何事（spec.md §7：未下載書籍不建立 `content_index_status` 列），
  /// 呼叫端不需要自行檢查（review-plan-issue-2.md I-1）。已有資料列時
  /// 不覆蓋。
  Future<void> handleBookAvailable(Book book);

  /// 移除 [bookId] 本機快取（`is_downloaded` 轉回 0）時呼叫（epic-10-search
  /// Issue 2，見 spec.md §7）：清除該書的 `book_content_index`／
  /// `content_index_status` 資料列，比照「重建索引」同一段清除邏輯但只
  /// 針對單一書籍。
  Future<void> clearBookIndex(String bookId);
}

/// [FullTextSearchSettingsRepository] 正式實作：開關本身存 `SharedPreferences`
/// （比照 `AppThemePreferences`／`LibraryPreferences` 既有慣例），批次回填/
/// 清除/重建索引資料直接對 [Database] 下 SQL（`ContentIndexingScheduler`
/// 本身也是這樣操作 `content_index_status`/`book_content_index`，本類別
/// 不重複實作排程邏輯；「關閉即乾淨」的競態防護落在
/// `ContentIndexingScheduler._processOneBook()`，見 plans/plan-issue-3.md
/// Task 1，review-plan-issue-3.md C-1）。
///
/// [requestProcessing] 刻意收窄成單一 callback 而非直接持有整個
/// `ContentIndexingScheduler`（比照 `LibrarySyncDependencies.onManualSync`
/// 既有先例），正式執行路徑由 `main.dart` 傳入
/// `contentIndexingScheduler.requestProcessing`。
class SqliteFullTextSearchSettingsRepository
    implements FullTextSearchSettingsRepository {
  SqliteFullTextSearchSettingsRepository({
    required Database database,
    required void Function() requestProcessing,
  })  : _database = database,
        _requestProcessing = requestProcessing;

  final Database _database;
  final void Function() _requestProcessing;

  static String _prefsKeyFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? 'full_text_search_enabled_pdf'
          : 'full_text_search_enabled_foliate';

  /// 回傳的字串片段假設呼叫端已在 SQL 中定位到 `books` 表（或其別名）的
  /// `format` 欄位。`pdf` → `format = 'pdf'`；`foliate` → 其餘格式扣除
  /// `cbz`（review-plan-issue-3.md I-2：CBZ 無文字層，spec.md §7 規定必須
  /// 是 `unsupported`，天生被排程器排除，光憑 `format` 字串本身就能判斷，
  /// 不像 DRM KF8 需要深入解析檔案內容——那仍是 Issue 2 的範圍）。
  static String _formatFilterFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? "format = 'pdf'"
          : "format != 'pdf' AND format != 'cbz'";

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyFor(category)) ?? false;
  }

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyFor(category), value);
    if (value) {
      await _backfillPending(category);
      _requestProcessing();
    } else {
      await _clearIndexData(category);
    }
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _clearIndexData(category);
    await _backfillPending(category);
    _requestProcessing();
  }

  @override
  Future<void> markUnsupported(String bookId) async {
    await _database.insert(
      'content_index_status',
      {
        'book_id': bookId,
        'status': 'unsupported',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    // 【review-plan-issue-2.md I-1】把 spec.md §7 的不變量收斂進方法本身，
    // 不依賴每個呼叫端自行檢查。
    if (!book.isDownloaded) return;
    if (book.format == BookFileFormat.cbz) {
      // 【規劃階段查證】一本 Calibre/OPDS 來源的 CBZ 書籍可能因移除快取
      // 而先被 clearBookIndex() 清掉既有的 unsupported 列，重新下載完成
      // 時必須重新標記回 unsupported，不可誤判成走一般 pending 流程。
      await markUnsupported(book.id);
      return;
    }
    final category = book.format == BookFileFormat.pdf
        ? ContentIndexCategory.pdf
        : ContentIndexCategory.foliate;
    if (!await isEnabled(category)) return;
    await _database.insert(
      'content_index_status',
      {
        'book_id': book.id,
        'status': 'pending',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // 【review-plan-issue-2.md C-1】遺漏這行會讓新書卡死在 pending，直到
    // 使用者恰好切換 App 前後台或開關閱讀畫面才會被動喚醒——比照既有
    // setEnabled(true)/rebuildIndex() 既有慣例，插入 pending 後必須主動
    // 喚醒排程器。
    _requestProcessing();
  }

  @override
  Future<void> clearBookIndex(String bookId) async {
    await _database.transaction((txn) async {
      await txn.delete('book_content_index',
          where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete('content_index_status',
          where: 'book_id = ?', whereArgs: [bookId]);
    });
  }

  /// 把 `content_index_status` 中尚無資料列、且格式符合 [category]、且已
  /// 下載的既有書籍批次插入 `pending`（spec.md §4／§7：未下載的雲端書籍
  /// 不建立列）。已有資料列的書籍一律跳過，不重複插入也不覆蓋既有
  /// status。**`foliate` 分類額外**把既有尚無資料列、且已下載的 `cbz`
  /// 書籍批次標記為 `unsupported`（review-plan-issue-3.md I-2，同樣套用
  /// `is_downloaded = 1` 篩選以維持與 spec.md §7「未下載書籍不建立
  /// content_index_status 列」規則一致，未下載的 CBZ 留給 Issue 2 下載
  /// 完成事件處理），不進入 `pending` 佇列。
  Future<void> _backfillPending(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.rawInsert('''
      INSERT INTO content_index_status (book_id, status, updated_at)
      SELECT b.id, 'pending', ?
      FROM books b
      LEFT JOIN content_index_status cis ON cis.book_id = b.id
      WHERE cis.book_id IS NULL
        AND b.is_downloaded = 1
        AND b.$formatFilter
    ''', [now]);
    if (category == ContentIndexCategory.foliate) {
      await _database.rawInsert('''
        INSERT INTO content_index_status (book_id, status, updated_at)
        SELECT b.id, 'unsupported', ?
        FROM books b
        LEFT JOIN content_index_status cis ON cis.book_id = b.id
        WHERE cis.book_id IS NULL
          AND b.is_downloaded = 1
          AND b.format = 'cbz'
      ''', [now]);
    }
  }

  /// 刪除 [category] 對應格式書籍的索引資料（`book_content_index`／
  /// `content_index_status`），trigger 同步清空對應 FTS 列。兩句 `DELETE`
  /// 包在同一交易內（review-plan-issue-3.md M-2）——若中途斷電/crash，
  /// 避免兩張表各自只刪一半造成資料不一致（例如 `book_content_index` 已
  /// 清空但 `content_index_status` 殘留舊 `status`，導致下次 `_backfillPending`
  /// 的 `LEFT JOIN` 誤判「已有資料列」而永遠不再回填該書）。不影響另一
  /// 分類已建立的索引。
  Future<void> _clearIndexData(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    await _database.transaction((txn) async {
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
