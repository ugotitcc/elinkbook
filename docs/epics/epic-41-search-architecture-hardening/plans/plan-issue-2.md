# Epic 41 Issue 2：抽出 ContentIndexStatusStore 收斂 content_index_status 狀態轉換 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `ContentIndexStatusStore`，收斂 `content_index_status`／`book_content_index` 兩張表所有的手寫 SQL，取代目前分散在 `ContentIndexingScheduler`（單書狀態轉換）與 `SqliteFullTextSearchSettingsRepository`（分類批次回填/清除）兩個檔案各自手寫的重複邏輯。兩個既有類別對外公開介面完全不變。

**Architecture:** 新增純資料存取模組 `app/lib/search/content_index_status_store.dart`，介面只收「純狀態資料存取」——單書狀態轉換（`markPending`/`markIndexing`/`updateProgress`/`markDone`/`markError`/`markUnsupported`/`isTracked`/`deleteForBook`）與分類批次操作（`backfillPending`/`clearByCategory`）。**不收**排程迴圈「中途要不要繼續處理」這個決策——那仍是 `ContentIndexingScheduler` 自己的職責，只是改呼叫 `isTracked()` 取得資料再自行判斷。`ContentIndexCategory` enum 原定義於 `full_text_search_settings_repository.dart`，隨批次操作一併搬到新檔案，原檔案改用 `export` 重新導出，維持所有既有匯入者零改動。

**Tech Stack:** Flutter/Dart，`sqflite`（`Database.transaction()`/`Database.rawInsert()`/`Database.rawDelete()`），`flutter_test` + `sqflite_common_ffi`（in-memory SQLite 單元測試，比照 `full_text_search_settings_repository_test.dart` 既有慣例）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 2 段落，已依 `reviews/review-epic-and-issues.md` I-2 修訂——移除不存在的 `category` 單書參數、拆分 `markIndexing`/`updateProgress`、補齊 `backfillPending`/`clearByCategory` 批次方法）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- **建構子型別修正（查證後修正，偏離 `issues.md` 原文字）**：`issues.md` Issue 2 原寫 `ContentIndexStatusStore(DatabaseExecutor db)`，理由是「接受 Database 或 Transaction，供交易情境使用」。查證 `package:sqflite` 實際 API 後發現不可行：`deleteForBook`／`backfillPending`／`clearByCategory` 三個方法內部都需要呼叫 `.transaction()`，而 `.transaction()` 只定義在 `Database` 上，不存在於 `DatabaseExecutor` 介面（`Transaction` 雖然實作 `DatabaseExecutor`，但不支援巢狀交易，本身沒有 `.transaction()` 方法）。若依原文字把建構子參數型別宣告為 `DatabaseExecutor`，這三個方法會直接編譯失敗。**本計畫改為建構子接受具體型別 `Database`**，與 `ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 現有的 `database` 建構參數型別一致，不需要任何轉接。
- `ContentIndexStatusStore` 只負責純資料存取，**不得**加入任何「是否要繼續處理下一本書」「排程佇列邏輯」相關的方法或判斷——這些留在 `ContentIndexingScheduler._runLoop()`/`_fetchNextPendingBook()`，本 Issue 完全不動它們。
- `ContentIndexCategory` enum 定義搬到 `content_index_status_store.dart`；`full_text_search_settings_repository.dart` 改用 `export 'content_index_status_store.dart' show ContentIndexCategory;` 重新導出——專案內另外 9 個既有檔案（`lib/screens/full_text_search_confirm_dialog.dart`、`lib/screens/library_search_screen.dart`、`lib/screens/settings_scaffold.dart` 等，見規劃階段查證的完整清單）目前都是 `import 'package:elinkbook/search/full_text_search_settings_repository.dart';` 後直接使用 `ContentIndexCategory`，重新導出後這些檔案的 import 路徑不需要任何修改，本 Issue **不觸碰**這些檔案。
- `ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 的公開建構子簽章與所有 public 方法簽章維持完全不變——`main.dart` 的既有組裝呼叫（`lib/main.dart:113`／`:124`）不需要任何修改，本 Issue 完全不觸碰 `main.dart`。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只在**最後一個 Task**（Task 3）跑一次完整 `flutter analyze`／`flutter test` 作最終確認（專案 `CLAUDE.md`「測試執行範圍」既有慣例）。
- Git commit 訊息結尾需附加下列兩行（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
  ```

---

### Task 1: 新增 `ContentIndexStatusStore`（含 `ContentIndexCategory` 搬遷）

**Files:**
- Create: `app/lib/search/content_index_status_store.dart`
- Test: `app/test/search/content_index_status_store_test.dart`

**Interfaces:**
- Consumes：`package:sqflite`（`Database`／`ConflictAlgorithm`）。
- Produces（供 Task 2/3 呼叫）：
  ```dart
  enum ContentIndexCategory { pdf, foliate }

  class ContentIndexStatusStore {
    const ContentIndexStatusStore(Database db);
    Future<void> markPending(String bookId);
    Future<void> markIndexing(String bookId);
    Future<void> updateProgress(String bookId, int lastChapterIndex);
    Future<void> markDone(String bookId);
    Future<void> markError(String bookId, {required String error});
    Future<void> markUnsupported(String bookId);
    Future<bool> isTracked(String bookId);
    Future<void> deleteForBook(String bookId);
    Future<void> backfillPending(ContentIndexCategory category);
    Future<void> clearByCategory(ContentIndexCategory category);
  }
  ```

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/search/content_index_status_store_test.dart`：

```dart
// app/test/search/content_index_status_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/content_index_status_store.dart';

Book _book(
  String id, {
  BookFileFormat format = BookFileFormat.epub,
  bool isDownloaded = true,
}) {
  return Book(
    id: id,
    title: '測試書 $id',
    format: format,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
    isDownloaded: isDownloaded,
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late Database db;
  late ContentIndexStatusStore store;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = libraryRepository.database;
    store = ContentIndexStatusStore(db);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  Future<Map<String, Object?>?> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> contentRowsOf(String bookId) async {
    return db.query('book_content_index',
        where: 'book_id = ?', whereArgs: [bookId]);
  }

  Future<void> insertContentRow(String bookId, int chapterIndex) async {
    await db.insert('book_content_index', {
      'id': '$bookId-$chapterIndex',
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'locator': 'epubcfi(/6/4!/4/$chapterIndex)',
      'raw_text': '第 $chapterIndex 章內容',
      'token_text': '第 $chapterIndex 章 內 容',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  group('markPending', () {
    test('尚無資料列時插入 pending', () async {
      await libraryRepository.insertBook(_book('b1'));

      await store.markPending('b1');

      final status = await statusOf('b1');
      expect(status, isNotNull);
      expect(status!['status'], 'pending');
    });

    test('已有資料列時不覆蓋既有 status（ConflictAlgorithm.ignore）', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await store.markDone('b1');

      await store.markPending('b1');

      final status = await statusOf('b1');
      expect(status!['status'], 'done');
    });
  });

  group('markIndexing', () {
    test('轉態為 indexing，不動 last_chapter_index', () async {
      await libraryRepository.insertBook(_book('b1'));
      await db.insert('content_index_status', {
        'book_id': 'b1',
        'status': 'pending',
        'last_chapter_index': 3,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await store.markIndexing('b1');

      final status = await statusOf('b1');
      expect(status!['status'], 'indexing');
      expect(status['last_chapter_index'], 3);
    });
  });

  group('updateProgress', () {
    test('更新 last_chapter_index，不改變 status', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await store.markIndexing('b1');

      await store.updateProgress('b1', 5);

      final status = await statusOf('b1');
      expect(status!['status'], 'indexing');
      expect(status['last_chapter_index'], 5);
    });
  });

  group('markDone', () {
    test('轉態為 done', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');

      await store.markDone('b1');

      expect((await statusOf('b1'))!['status'], 'done');
    });
  });

  group('markError', () {
    test('轉態為 error 並記錄 error_message', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');

      await store.markError('b1', error: 'boom');

      final status = await statusOf('b1');
      expect(status!['status'], 'error');
      expect(status['error_message'], 'boom');
    });
  });

  group('markUnsupported', () {
    test('尚無資料列時插入 unsupported', () async {
      await libraryRepository
          .insertBook(_book('b1', format: BookFileFormat.cbz));

      await store.markUnsupported('b1');

      expect((await statusOf('b1'))!['status'], 'unsupported');
    });

    test('已有資料列時不覆蓋', () async {
      await libraryRepository
          .insertBook(_book('b1', format: BookFileFormat.cbz));
      await store.markPending('b1');

      await store.markUnsupported('b1');

      expect((await statusOf('b1'))!['status'], 'pending');
    });
  });

  group('isTracked', () {
    test('資料列存在時回傳 true，不存在時回傳 false', () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      await store.markPending('b1');

      expect(await store.isTracked('b1'), isTrue);
      expect(await store.isTracked('b2'), isFalse);
    });
  });

  group('deleteForBook', () {
    test('同一交易內刪除 book_content_index 與 content_index_status 兩張表',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await insertContentRow('b1', 0);
      await insertContentRow('b1', 1);

      await store.deleteForBook('b1');

      expect(await statusOf('b1'), isNull);
      expect(await contentRowsOf('b1'), isEmpty);
    });

    test('兩張表皆已無資料列時呼叫仍安全（冪等，不拋例外）', () async {
      await libraryRepository.insertBook(_book('b1'));

      await store.deleteForBook('b1');

      expect(await statusOf('b1'), isNull);
    });
  });

  group('backfillPending', () {
    test('只回填「格式符合分類且已下載」且尚無資料列的書籍', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository.insertBook(_book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      ));

      await store.backfillPending(ContentIndexCategory.pdf);

      expect((await statusOf('pdf-1'))!['status'], 'pending');
      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-not-downloaded'), isNull);
    });

    test('foliate 分類額外把已下載的 cbz 書籍標記為 unsupported', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await store.backfillPending(ContentIndexCategory.foliate);

      expect((await statusOf('epub-1'))!['status'], 'pending');
      expect((await statusOf('cbz-1'))!['status'], 'unsupported');
    });

    test('已有資料列的書籍一律跳過，不覆蓋既有 status', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await store.markDone('epub-1');

      await store.backfillPending(ContentIndexCategory.foliate);

      expect((await statusOf('epub-1'))!['status'], 'done');
    });
  });

  group('clearByCategory', () {
    test('pdf 分類：刪除該分類格式書籍的索引資料，不影響另一分類', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await store.markPending('pdf-1');
      await store.markPending('epub-1');
      await insertContentRow('pdf-1', 0);
      await insertContentRow('epub-1', 0);

      await store.clearByCategory(ContentIndexCategory.pdf);

      expect(await statusOf('pdf-1'), isNull);
      expect(await contentRowsOf('pdf-1'), isEmpty);
      expect((await statusOf('epub-1'))!['status'], 'pending');
      expect(await contentRowsOf('epub-1'), isNotEmpty);
    });

    test('foliate 分類：刪除該分類格式書籍的索引資料，不影響 pdf 分類與 cbz',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));
      await store.markPending('pdf-1');
      await store.markPending('epub-1');
      await store.markUnsupported('cbz-1');
      await insertContentRow('pdf-1', 0);
      await insertContentRow('epub-1', 0);

      await store.clearByCategory(ContentIndexCategory.foliate);

      expect(await statusOf('epub-1'), isNull);
      expect(await contentRowsOf('epub-1'), isEmpty);
      expect((await statusOf('pdf-1'))!['status'], 'pending');
      expect(await contentRowsOf('pdf-1'), isNotEmpty);
      // 【審查修正 I-2】驗證 `format != 'pdf' AND format != 'cbz'` 篩選
      // 確實排除 CBZ——foliate 分類的清除不該波及 CBZ 既有的 unsupported 列。
      expect((await statusOf('cbz-1'))!['status'], 'unsupported');
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/search/content_index_status_store_test.dart`
Expected: FAIL（編譯錯誤，`package:elinkbook/search/content_index_status_store.dart` 不存在）

- [ ] **Step 3: 寫最小實作**

建立 `app/lib/search/content_index_status_store.dart`：

```dart
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
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/search/content_index_status_store_test.dart`
Expected: PASS（16 個測試案例全數通過）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/search/content_index_status_store.dart test/search/content_index_status_store_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/search/content_index_status_store.dart app/test/search/content_index_status_store_test.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 ContentIndexStatusStore 收斂 content_index_status 狀態存取（epic-41 Issue 2 Task 1）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 2: `ContentIndexingScheduler` 改用 `ContentIndexStatusStore`

**Files:**
- Modify: `app/lib/search/content_indexing_scheduler.dart`
- Test: `app/test/search/content_indexing_scheduler_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `ContentIndexStatusStore`。

- [ ] **Step 1: 新增 import 與 `_store` 欄位**

在 `app/lib/search/content_indexing_scheduler.dart` 頂部 import 區塊，加入：

```dart
import 'content_index_status_store.dart';
```

（放在既有 `import 'content_indexer.dart';` 之後，維持字母序。）

把建構子與欄位宣告：

```dart
class ContentIndexingScheduler with WidgetsBindingObserver {
  ContentIndexingScheduler({
    required Database database,
    required ReaderActivityTracker activityTracker,
    required ContentIndexer pdfIndexer,
    required ContentIndexer foliateIndexer,
  })  : _database = database,
        _activityTracker = activityTracker,
        _pdfIndexer = pdfIndexer,
        _foliateIndexer = foliateIndexer {
    _activityTracker.addListener(_handleActivityChanged);
  }

  final Database _database;
  final ReaderActivityTracker _activityTracker;
  final ContentIndexer _pdfIndexer;
  final ContentIndexer _foliateIndexer;
```

改為（**審查修正 M-1：以下完整列出 `_activityTracker`／`_pdfIndexer`／`_foliateIndexer` 三個既有欄位，只新增 `_store` 一行，其餘三行原樣保留不可誤刪**）：

```dart
class ContentIndexingScheduler with WidgetsBindingObserver {
  ContentIndexingScheduler({
    required Database database,
    required ReaderActivityTracker activityTracker,
    required ContentIndexer pdfIndexer,
    required ContentIndexer foliateIndexer,
  })  : _database = database,
        _store = ContentIndexStatusStore(database),
        _activityTracker = activityTracker,
        _pdfIndexer = pdfIndexer,
        _foliateIndexer = foliateIndexer {
    _activityTracker.addListener(_handleActivityChanged);
  }

  final Database _database;
  final ContentIndexStatusStore _store;
  final ReaderActivityTracker _activityTracker;
  final ContentIndexer _pdfIndexer;
  final ContentIndexer _foliateIndexer;
```

`_database` 欄位維持保留——`_fetchNextPendingBook()` 仍需要它下 `JOIN books` 的複合查詢，這支方法本身不屬於「純狀態資料存取」，本 Issue 不動它（見 Global Constraints）。

- [ ] **Step 2: `_processOneBook()` 改用 `_store`**

原本（開頭轉態）：

```dart
  Future<void> _processOneBook(Book book, int? lastChapterIndex) async {
    await _database.update(
      'content_index_status',
      {'status': 'indexing', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'book_id = ?',
      whereArgs: [book.id],
    );
```

改為：

```dart
  Future<void> _processOneBook(Book book, int? lastChapterIndex) async {
    await _store.markIndexing(book.id);
```

`flushPendingChapter` 內原本：

```dart
      await _database.update(
        'content_index_status',
        {
          'last_chapter_index': chapterIndex,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [book.id],
      );
```

改為：

```dart
      await _store.updateProgress(book.id, chapterIndex);
```

主迴圈內兩處 `if (!await _isStillTracked(book.id))` 改為 `if (!await _store.isTracked(book.id))`（兩處呼叫點皆是如此，其餘邏輯不動）。

章節迴圈內原本清除殘留列：

```dart
        await _database.delete('book_content_index',
            where: 'book_id = ?', whereArgs: [book.id]);
```

改為：

```dart
        await _store.deleteForBook(book.id);
```

（`deleteForBook` 同時刪 `book_content_index`／`content_index_status` 兩張表，但此時 `content_index_status` 早已被外部刪除——`_store.isTracked()` 已回傳 `false` 才會走到這個分支，`deleteForBook` 對已空的 `content_index_status` 是 no-op，行為與原本只刪 `book_content_index` 完全等價。）

成功路徑原本：

```dart
      } else if (!paused) {
        await _database.update(
          'content_index_status',
          {'status': 'done', 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'book_id = ?',
          whereArgs: [book.id],
        );
      }
```

改為：

```dart
      } else if (!paused) {
        await _store.markDone(book.id);
      }
```

`catch` 區塊原本：

```dart
    } catch (e) {
      await _database.update(
        'content_index_status',
        {
          'status': 'error',
          'error_message': e.toString(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [book.id],
      );
    }
```

改為：

```dart
    } catch (e) {
      await _store.markError(book.id, error: e.toString());
    }
```

- [ ] **Step 3: 刪除 `_isStillTracked` 私有方法**

檔案最下方原本的：

```dart
  /// epic-10-search Issue 3（review-plan-issue-3.md C-1）：[bookId] 對應的
  /// `content_index_status` 列是否仍然存在。用於 `_processOneBook()` 在每個
  /// 章節邊界檢查該書是否仍被追蹤——一旦消失即代表已被外部關閉並捨棄進度
  /// （見上方 `_processOneBook` 內的呼叫點說明）。
  Future<bool> _isStillTracked(String bookId) async {
    final rows = await _database.query(
      'content_index_status',
      columns: ['book_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
```

整段刪除，改為單純：

```dart
}
```

（邏輯已完全搬進 `ContentIndexStatusStore.isTracked()`，Step 2 已把兩個呼叫點改指過去。）

- [ ] **Step 4: 執行既有回歸測試**

Run: `cd app && flutter test test/search/content_indexing_scheduler_test.dart`
Expected: PASS（全數通過，零回歸——這些測試直接查詢 `content_index_status`/`book_content_index` 資料列驗證最終狀態，底層 schema 與最終寫入結果不變，只是換了誰去寫）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/search/content_indexing_scheduler.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/search/content_indexing_scheduler.dart
git commit -m "$(cat <<'EOF'
refactor(search): ContentIndexingScheduler 改用 ContentIndexStatusStore（epic-41 Issue 2 Task 2）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 3: `SqliteFullTextSearchSettingsRepository` 改用 `ContentIndexStatusStore`，並跑全套驗證收尾

**Files:**
- Modify: `app/lib/search/full_text_search_settings_repository.dart`
- Test: `app/test/search/full_text_search_settings_repository_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `ContentIndexStatusStore`／`ContentIndexCategory`。

- [ ] **Step 1: 搬遷 `ContentIndexCategory`，改用 `export` 重新導出**

在 `app/lib/search/full_text_search_settings_repository.dart` 頂部，原本：

```dart
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
```

改為：

```dart
// app/lib/search/full_text_search_settings_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import 'content_index_status_store.dart';

export 'content_index_status_store.dart' show ContentIndexCategory;
```

（`ContentIndexCategory` enum 本體已搬到 `content_index_status_store.dart`——見 Task 1；這裡改用 `export` 重新導出，本檔案既有的 9 個外部匯入者〔`full_text_search_confirm_dialog.dart`／`library_search_screen.dart`／`settings_scaffold.dart` 等〕`import 'package:elinkbook/search/full_text_search_settings_repository.dart';` 後使用 `ContentIndexCategory` 的既有寫法，重新導出後不需要任何修改。）

- [ ] **Step 2: 移除 `_formatFilterFor`，改用 `_store`／欄位**

原本的類別欄位與建構子：

```dart
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
```

改為：

```dart
class SqliteFullTextSearchSettingsRepository
    implements FullTextSearchSettingsRepository {
  SqliteFullTextSearchSettingsRepository({
    required Database database,
    required void Function() requestProcessing,
  })  : _store = ContentIndexStatusStore(database),
        _requestProcessing = requestProcessing;

  final ContentIndexStatusStore _store;
  final void Function() _requestProcessing;

  static String _prefsKeyFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? 'full_text_search_enabled_pdf'
          : 'full_text_search_enabled_foliate';
```

（`_database` 欄位整個移除——移除後這個檔案裡不再有任何地方直接碰 `Database` 執行 SQL，全部委派給 `_store`；`_formatFilterFor` 整段移除，已搬進 `ContentIndexStatusStore`。`import 'package:sqflite/sqflite.dart';` 保留，因為建構子參數 `required Database database` 仍需要這個型別。）

- [ ] **Step 3: `setEnabled`／`rebuildIndex` 改呼叫 `_store`**

原本：

```dart
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
```

改為：

```dart
  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyFor(category), value);
    if (value) {
      await _store.backfillPending(category);
      _requestProcessing();
    } else {
      await _store.clearByCategory(category);
    }
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _store.clearByCategory(category);
    await _store.backfillPending(category);
    _requestProcessing();
  }
```

- [ ] **Step 4: `markUnsupported`／`handleBookAvailable`／`clearBookIndex` 改呼叫 `_store`，並刪除私有批次方法**

原本：

```dart
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
```

改為：

```dart
  @override
  Future<void> markUnsupported(String bookId) => _store.markUnsupported(bookId);

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
    await _store.markPending(book.id);
    // 【review-plan-issue-2.md C-1】遺漏這行會讓新書卡死在 pending，直到
    // 使用者恰好切換 App 前後台或開關閱讀畫面才會被動喚醒——比照既有
    // setEnabled(true)/rebuildIndex() 既有慣例，插入 pending 後必須主動
    // 喚醒排程器。
    _requestProcessing();
  }

  @override
  Future<void> clearBookIndex(String bookId) => _store.deleteForBook(bookId);
}
```

- [ ] **Step 5: 執行既有回歸測試**

Run: `cd app && flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: PASS（全數通過，零回歸）

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/search/full_text_search_settings_repository.dart`
Expected: `No issues found!`

- [ ] **Step 7: 確認 9 個既有外部匯入者零回歸**

`ContentIndexCategory` 搬遷後的 `export` 是否真的讓既有外部匯入者不需修改，直接跑一次它們的測試檔驗證：

Run: `cd app && flutter test test/screens/full_text_search_confirm_dialog_test.dart test/screens/library_search_screen_test.dart test/screens/settings_scaffold_test.dart test/screens/library_batch_actions_test.dart test/library/book_import_service_test.dart test/screens/adaptive_shell_scaffold_test.dart test/screens/library_screen_test.dart`
Expected: 全數通過（`adaptive_shell_scaffold_test.dart` 既有 2 個失敗案例除外——與 `epic-10-search`/`epic-41` 皆無關，見 `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md` 既有驗證紀錄）

- [ ] **Step 8: 跑完整 `flutter analyze`／`flutter test` 作最終確認**

本 Issue 三個 Task 皆完成，依專案慣例在最後一個 Task 跑一次全套驗證：

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過（新增 16 個 `content_index_status_store_test.dart` 測試案例後，總數應為 Issue 1 合併後的既有基準 +16，失敗數維持 2 且必須是同樣兩個 `adaptive_shell_scaffold_test.dart` 既有案例，不可出現新的失敗）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/search/full_text_search_settings_repository.dart
git commit -m "$(cat <<'EOF'
refactor(search): SqliteFullTextSearchSettingsRepository 改用 ContentIndexStatusStore（epic-41 Issue 2 Task 3）

ContentIndexCategory 搬到 content_index_status_store.dart，本檔案改用
export 重新導出，既有 9 個外部匯入者零改動。ContentIndexingScheduler／
SqliteFullTextSearchSettingsRepository 兩處手寫 content_index_status／
book_content_index SQL 皆已收斂進 ContentIndexStatusStore，全專案
flutter analyze/flutter test 零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

- [ ] **Step 10: 更新工單狀態**

在 `docs/epics/epic-41-search-architecture-hardening/issues.md` 的 Issue 2 段落，依專案既有看板慣例，把 `**Status:** ready-for-agent` 改為：

```
**Status:** completed（`plans/plan-issue-2.md` 3 個 Task 全數完成，新增 `ContentIndexStatusStore`，`ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 皆已改用，`ContentIndexCategory` 搬遷並以 `export` 維持既有匯入者零改動，`flutter analyze`/`flutter test` 全數通過零回歸）
```

同步在 `epic.md` 的開發記錄追加一句「Issue 2 已完成」。
