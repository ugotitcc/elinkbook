# Epic 10 Issue 2：CBZ／DRM KF8／未下載與移除快取書籍的索引狀態處理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 讓 Issue 1 的排程器正確跳過本來就不該索引的書籍（CBZ），並讓「新書匯入」「重新下載完成」「移除本機快取」三個既有事件流程正確連動索引資料的建立/清除/喚醒，避免排程器浪費資源嘗試索引不存在或不支援的內容、也避免使用者已啟用全文檢索後新書/重新下載的書永遠不會被索引。

**Architecture：** 在 `FullTextSearchSettingsRepository`（Issue 3 產物）新增三個單書等級方法（`markUnsupported`／`handleBookAvailable`／`clearBookIndex`），延續該類別既有「直接對 `Database` 下 SQL 操作 `content_index_status`/`book_content_index`」的既定慣例；三個既有事件觸發點（`_importSingleFile()` 匯入收斂點、重新下載完成、移除本機快取）各自呼叫對應方法，不重複實作 SQL。`handleBookAvailable()` 是全部新書/重新下載共用的單一入口——不只是「重新下載」場景專用。

**Tech Stack：** Flutter/Dart、`sqflite`（`sqflite_common_ffi` 供測試）。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §7（CBZ／DRM KF8／未下載書籍，本計畫的唯一技術事實來源）；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 2；`FullTextSearchSettingsRepository` 既有實作 [`app/lib/search/full_text_search_settings_repository.dart`](../../../../app/lib/search/full_text_search_settings_repository.dart)（Issue 3 產物，本計畫延續其既有慣例，不重新設計）。

## Global Constraints

- **本計畫已經過一輪計畫審查修訂**（`reviews/review-plan-issue-2.md`，🔴 Changes Requested，2 Critical／2 Important／2 Minor）：C-1（`handleBookAvailable` 遺漏喚醒排程器）、C-2（原計畫只處理 CBZ，遺漏所有新匯入/下載書籍的索引回填——**這是本次修訂影響範圍最大的一項，把方法從「重新下載專用」升級為「所有新書共用的單一入口」，並改名 `handleDownloadCompleted` → `handleBookAvailable` 反映這個更廣泛的語意**）、I-1（缺少 `isDownloaded` 防禦檢查）、I-2（`clearBookIndex` 測試遺漏驗證 `book_content_fts`）、M-1（`try/catch` 防禦性包裹）、M-2（`didUpdateWidget` 未同步 `_batchActions`）全數查證屬實並採納修訂，逐項體現在下方對應 Task 內。執行者不需要另外重讀審查報告，所有修訂已內嵌為對應程式碼片段與行內註解。
- **依賴已滿足**：Issue 1、Issue 3 皆已完成並合併，`FullTextSearchSettingsRepository`／`ContentIndexCategory`／`SqliteFullTextSearchSettingsRepository` 已存在，本計畫在其上擴充三個新方法。
- **DRM KF8 標記為 `unsupported`——查證後確認現行架構下無事可做，本計畫刻意不實作任何 DRM 相關程式碼**：查證 `app/lib/library/book_import_service_impl.dart:296-317`（azw3 分支）發現，偵測到 `DrmProtectedException` 時目前是 `return null`——**完全中止匯入，連 `Book` 記錄都不會建立**（註解明確引用「spec.md『KF8 (AZW3) 支援』」，是另一個 Epic 已落地的既定決策，非本 Epic 範圍）。這代表現行架構下 DRM KF8 書籍永遠不會出現在圖書庫裡，也就永遠不會有 `content_index_status` 列需要標記為 `unsupported`——epic-10-search spec.md §7 假設「DRM KF8 書籍會被匯入、只是標記為 unsupported」與現行匯入行為矛盾。**人類已拍板**：不追翻既有匯入拒絕行為（那是另一個 Epic 的明確決策，改動風險與範圍皆超出本工單），本計畫只文件化這個落差，不實作任何 DRM 偵測/標記程式碼；若未來某個 Epic 決定改變 DRM KF8 的匯入拒絕政策，屆時再視需要重新評估是否要標記 `unsupported`（`FullTextSearchSettingsRepository.markUnsupported(bookId)`，本計畫 Task 1 產出的方法，屆時可直接重用，不需要新增）。
- **`handleBookAvailable(Book book)` 是「新書內容首次可被索引」的統一事件，涵蓋兩種現存觸發時機（review-plan-issue-2.md C-2 修訂重點）**：
  1. **任何格式的新書首次匯入完成**——`app/lib/library/book_import_service_impl.dart` 的 `_importSingleFile()` 是全專案所有新書匯入與雲端/遠端首次下載的**唯一收斂點**（本機檔案/資料夾選取、Google Drive、OneDrive、Calibre/OPDS 皆經由 `BookImportService.importFiles()` 呼叫到這裡，`Book(...)` 建構時固定 `isDownloaded: true`）。**原計畫第一版只在 CBZ 分支呼叫 `markUnsupported()`，完全遺漏其餘格式（EPUB/PDF/TXT/MD）——這代表使用者若已經在設定中啟用全文檢索，之後匯入的任何新書都不會有 `content_index_status` 列被建立，排程器永遠不會知道有這本新書存在，全文檢索永遠查不到它**（因為目前唯一會建立 `pending` 列的地方是 Issue 3 的 `setEnabled(true)`/`rebuildIndex()`，只在使用者切換開關/點擊重建當下執行一次批次回填，不會持續監看新書）。查證後推翻原計畫判斷，`_importSingleFile()` 插入 `Book` 記錄後改為統一呼叫 `handleBookAvailable(insertedBook)`（不再只在 CBZ 分支呼叫 `markUnsupported()`——CBZ 的特判邏輯完全移到 `handleBookAvailable()` 內部，`book_import_service_impl.dart` 本身不再需要判斷格式）。
  2. **既有 Calibre/OPDS 書籍「移除本機快取」後又「重新下載」完成**——`app/lib/screens/library_screen.dart` 的 `_handleRedownload()`，這是現行架構下唯一會發生「`is_downloaded` 從 0 轉為 1」的既有 code path（`DownloadQueueController`／`RemoteDownloadJob`／`CloudDownloadJob` 皆屬於情境 1，一律走 `isDownloaded` 從一開始就是 `true` 的新匯入路徑，不屬於這個情境）。
- **`handleBookAvailable()` 必須呼叫 `_requestProcessing()`（review-plan-issue-2.md C-1，推翻原計畫第一版遺漏）**：原計畫第一版插入 `pending` 列後沒有喚醒排程器，若排程器當下處於閒置狀態（例如書庫先前的書籍都已索引完畢），新書會卡死在 `pending`，直到使用者恰好切換 App 前後台或開關閱讀畫面才會被動觸發——`content_indexing_scheduler.dart:85-93` 的 `requestProcessing()` doc comment 本身就明文寫「供新書匯入、下載完成（Issue 2）……時主動呼叫」，比照 Issue 3 `setEnabled(true)`/`rebuildIndex()` 插入 `pending` 後呼叫 `_requestProcessing()` 的既有慣例。
- **`handleBookAvailable()` 必須檢查 `book.isDownloaded`（review-plan-issue-2.md I-1）**：`if (!book.isDownloaded) return;` 作為方法開頭的第一道防線，把 spec.md §7「未下載書籍不建立 content_index_status 列」這個不變量收斂進方法本身、不依賴每個呼叫端自行遵守。本計畫目前兩個呼叫端（`_importSingleFile()`／`_handleRedownload()`）在呼叫當下都已經確保 `isDownloaded == true`，這道檢查是面向未來呼叫端的防禦性設計。
- **`markUnsupported()`／`handleBookAvailable()` 的 INSERT 皆採用 `ConflictAlgorithm.ignore`**：已有資料列的書籍一律不覆蓋，比照 Issue 3 `_backfillPending()` 既有的「已有資料列的書籍一律跳過」原則。
- **CBZ 在 `handleBookAvailable()` 內的特殊處理**：一本 Calibre/OPDS 來源的 CBZ 書籍理論上也可能被移除快取後又重新下載——`clearBookIndex()` 會把它的 `unsupported` 列一併清掉，此時 `handleBookAvailable()` 必須重新把它標記回 `unsupported`（而不是略過或誤判成走一般 `pending` 流程），因此內部邏輯是「CBZ 一律呼叫 `markUnsupported()`，其餘格式才檢查 `isEnabled(category)` 決定是否插入 `pending`」，不是 spec.md §7 逐字描述的原始版本（該段落只描述了非 CBZ 情境），本計畫視為對既有規則的必要延伸，理由如上。
- **`clearBookIndex()` 測試必須驗證 `book_content_fts` 同步清空（review-plan-issue-2.md I-2）**：比照 Issue 3 既有 `setEnabled(pdf, false)` 測試的 `db.rawQuery("SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH ...")` 既有斷言手法，`issues.md` Issue 2 單元測試要求逐字列出「`book_content_index`/`content_index_status`/`book_content_fts` 資料列皆清空」三張表，缺一不可。
- **搜尋索引是衍生性資料，其寫入/清除失敗不應阻斷或誤判主流程失敗（review-plan-issue-2.md M-1）**：比照 `library_batch_actions.dart` 既有「檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作」的既定慣例，`_importSingleFile()`／`_handleRedownload()`／`removeLocalCache()` 呼叫 `handleBookAvailable()`/`clearBookIndex()` 一律包在 `try/catch` 內靜默略過例外，不讓索引維護的失敗連帶讓使用者看到「匯入失敗」/「重新下載失敗」，也不讓批次移除快取迴圈因單一書籍的索引清除異常而中斷後續書籍。
- **`LibraryScreen.didUpdateWidget()` 需同步更新 `_batchActions`（review-plan-issue-2.md M-2）**：`_batchActions` 在 `initState()` 建構時捕捉了當下的 `repository`/`fullTextSearchSettingsRepository` 參考，若上層 `readerFeatureRepositories`／`repository` 之後被替換（例如測試情境），需要在 `didUpdateWidget()` 重新建構，避免繼續持有過期參考。
- 不修改 `ContentIndexingScheduler`（Issue 1／Issue 3 已完成，不感知本工單新增的三個方法，純粹是消費既有 `content_index_status` 佇列）。
- 不新增 DB migration，`content_index_status`/`book_content_index` schema 沿用 Issue 0 既有版本（`version: 24`）不變。
- 所有新增程式碼註解使用正體中文（zh-TW），比照全專案既有慣例。

---

## 檔案結構總覽

- **Modify：** `app/lib/search/full_text_search_settings_repository.dart` — 抽象介面與實作新增 `markUnsupported`／`handleBookAvailable`／`clearBookIndex` 三個方法。
- **Modify：** `app/test/search/full_text_search_settings_repository_test.dart`
- **Modify：** `app/test/support/fake_full_text_search_settings_repository.dart` — 新增三個方法的假實作＋呼叫記錄清單。
- **Modify：** `app/lib/library/book_import_service_impl.dart` — 建構子新增可選 `fullTextSearchSettingsRepository`；`_importSingleFile()` 統一呼叫 `handleBookAvailable()`（不限 CBZ）。
- **Modify：** `app/test/library/book_import_service_test.dart`
- **Modify：** `app/lib/screens/library_screen.dart` — `_handleRedownload()` 完成後呼叫 `handleBookAvailable()`；`didUpdateWidget()` 同步 `_batchActions`。
- **Modify：** `app/test/screens/library_screen_test.dart`
- **Modify：** `app/lib/screens/library_batch_actions.dart` — 建構子新增可選 `fullTextSearchSettingsRepository`；`removeLocalCache()` 呼叫 `clearBookIndex()`。
- **Modify：** `app/test/screens/library_batch_actions_test.dart`
- **Modify：** `app/lib/main.dart` — 重新排序建構順序，讓 `fullTextSearchSettingsRepository` 在 `importService` 之前就緒，並傳入 `BookImportServiceImpl`。

---

### Task 1：`FullTextSearchSettingsRepository` 新增單書等級方法

**Files：**
- Modify: `app/lib/search/full_text_search_settings_repository.dart`
- Modify: `app/test/support/fake_full_text_search_settings_repository.dart`
- Test: `app/test/search/full_text_search_settings_repository_test.dart`

**Interfaces：**
- Consumes：既有 `SqliteFullTextSearchSettingsRepository` 的 `_database`／`isEnabled()`／`_requestProcessing` 等既有私有成員與方法。
- Produces：`FullTextSearchSettingsRepository` 新增 `Future<void> markUnsupported(String bookId)`／`Future<void> handleBookAvailable(Book book)`／`Future<void> clearBookIndex(String bookId)` 三個方法——供 Task 2／3／4 呼叫。`FakeFullTextSearchSettingsRepository` 新增對應的 `markUnsupportedCalls`／`handleBookAvailableCalls`／`clearBookIndexCalls` 記錄清單——供 Task 3／4 的 widget/unit test 斷言使用。

- [x] **Step 1：寫一組會失敗（編譯錯誤）的測試**

在 `app/test/search/full_text_search_settings_repository_test.dart`，找到既有 `group('epic-10-search Issue 3：FullTextSearchSettingsRepository', () { ... });` 區塊內最後一個測試（`rebuildIndex(category)` 那則）之後、區塊收尾 `});` 之前，新增：

```dart
    test('markUnsupported() 寫入 unsupported 狀態（epic-10-search Issue 2）',
        () async {
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await repository.markUnsupported('cbz-1');

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
    });

    test('markUnsupported() 不覆蓋已存在的資料列', () async {
      await libraryRepository.insertBook(_book('book-1'));
      await db.insert('content_index_status',
          {'book_id': 'book-1', 'status': 'done', 'updated_at': 1000});

      await repository.markUnsupported('book-1');

      final status = await statusOf('book-1');
      expect(status!['status'], 'done');
    });

    test(
        'handleBookAvailable() 對 CBZ 書籍一律標記 unsupported，不呼叫 requestProcessing',
        () async {
      final book = _book('cbz-1', format: BookFileFormat.cbz);
      await libraryRepository.insertBook(book);

      await repository.handleBookAvailable(book);

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
      expect(requestProcessingCallCount, 0);
    });

    test(
        'handleBookAvailable() 依格式對應分類是否啟用決定是否插入 pending，'
        '插入時喚醒排程器（review-plan-issue-2.md C-1）', () async {
      final pdfBook = _book('pdf-1', format: BookFileFormat.pdf);
      final epubBook = _book('epub-1');
      await libraryRepository.insertBook(pdfBook);
      await libraryRepository.insertBook(epubBook);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      // setEnabled(true) 本身的批次回填也會呼叫一次 requestProcessing，
      // 重置計數只驗證 handleBookAvailable() 這一步的行為。
      requestProcessingCallCount = 0;

      await repository.handleBookAvailable(pdfBook);
      await repository.handleBookAvailable(epubBook);

      final pdfStatus = await statusOf('pdf-1');
      expect(pdfStatus, isNotNull);
      expect(pdfStatus!['status'], 'pending');
      // foliate 分類未啟用，epub-1 不應被插入任何資料列。
      expect(await statusOf('epub-1'), isNull);
      // 只有 pdf-1 真的插入 pending，只喚醒排程器一次。
      expect(requestProcessingCallCount, 1);
    });

    test('handleBookAvailable() 不覆蓋已存在的資料列', () async {
      final book = _book('pdf-1', format: BookFileFormat.pdf);
      await libraryRepository.insertBook(book);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      await db.update('content_index_status', {'status': 'done'},
          where: 'book_id = ?', whereArgs: ['pdf-1']);

      await repository.handleBookAvailable(book);

      final status = await statusOf('pdf-1');
      expect(status!['status'], 'done');
    });

    test(
        'handleBookAvailable() 對 isDownloaded == false 的書籍不做任何事'
        '（review-plan-issue-2.md I-1）', () async {
      final book = _book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      );
      await libraryRepository.insertBook(book);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      requestProcessingCallCount = 0;

      await repository.handleBookAvailable(book);

      expect(await statusOf('pdf-not-downloaded'), isNull);
      expect(requestProcessingCallCount, 0);
    });

    test(
        'clearBookIndex() 清除單一書籍的索引資料（含 book_content_fts），'
        '不影響其他書籍（review-plan-issue-2.md I-2）', () async {
      await libraryRepository.insertBook(_book('book-1'));
      await libraryRepository.insertBook(_book('book-2'));
      await db.insert('content_index_status',
          {'book_id': 'book-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'book-2', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-1',
        'book_id': 'book-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': '書一內容',
        'token_text': '書一內容',
        'created_at': 1000,
      });
      await db.insert('book_content_index', {
        'id': 'seg-2',
        'book_id': 'book-2',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': '書二內容',
        'token_text': '書二內容',
        'created_at': 1000,
      });

      await repository.clearBookIndex('book-1');

      expect(await statusOf('book-1'), isNull);
      expect(await statusOf('book-2'), isNotNull);
      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRows, isEmpty);
      final ftsRowsBook1 = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '書一'");
      expect(ftsRowsBook1, isEmpty,
          reason: 'FTS5 trigger 應同步清空已刪除的 book-1 索引列');
      final ftsRowsBook2 = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '書二'");
      expect(ftsRowsBook2, isNotEmpty,
          reason: 'book-2 的索引不應受 book-1 的 clearBookIndex 影響');
    });
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: FAIL（編譯錯誤：`FullTextSearchSettingsRepository`／`SqliteFullTextSearchSettingsRepository` 沒有 `markUnsupported`/`handleBookAvailable`/`clearBookIndex` 方法）。

- [x] **Step 3：實作三個新方法**

在 `app/lib/search/full_text_search_settings_repository.dart`，於檔案頂端 import 區塊新增：

```dart
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
```

找到：

```dart
abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
  Future<void> rebuildIndex(ContentIndexCategory category);
}
```

取代為：

```dart
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
```

找到 `SqliteFullTextSearchSettingsRepository` 類別內的 `rebuildIndex()` 方法：

```dart
  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _clearIndexData(category);
    await _backfillPending(category);
    _requestProcessing();
  }
```

在其後（`_backfillPending()` 方法定義之前）插入三個新方法：

```dart
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

```

在 `app/test/support/fake_full_text_search_settings_repository.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/library/models/book.dart';
```

找到：

```dart
  /// 記錄每次 [rebuildIndex] 呼叫的 `category`（review-plan-issue-3.md
  /// I-1）。
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }
}
```

取代為：

```dart
  /// 記錄每次 [rebuildIndex] 呼叫的 `category`（review-plan-issue-3.md
  /// I-1）。
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  /// 記錄每次 [markUnsupported]／[handleBookAvailable]／[clearBookIndex]
  /// 呼叫（epic-10-search Issue 2）。
  final List<String> markUnsupportedCalls = [];
  final List<Book> handleBookAvailableCalls = [];
  final List<String> clearBookIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }

  @override
  Future<void> markUnsupported(String bookId) async {
    markUnsupportedCalls.add(bookId);
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    handleBookAvailableCalls.add(book);
  }

  @override
  Future<void> clearBookIndex(String bookId) async {
    clearBookIndexCalls.add(bookId);
  }
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: PASS（18 項測試全過：既有 11 項＋本次新增 7 項）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/full_text_search_settings_repository.dart app/test/support/fake_full_text_search_settings_repository.dart app/test/search/full_text_search_settings_repository_test.dart
git commit -m "feat(search): FullTextSearchSettingsRepository 新增單書索引狀態方法（Issue 2）"
```

---

### Task 2：新匯入書籍統一連動全文檢索索引狀態

**Files：**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `FullTextSearchSettingsRepository.handleBookAvailable(Book book)`。
- Produces：`BookImportServiceImpl` 建構子新增可選具名參數 `FullTextSearchSettingsRepository? fullTextSearchSettingsRepository`（`null` 時行為與現行完全一致，不寫入任何 `content_index_status` 列）——供 Task 5（`main.dart`）注入正式實例。

- [x] **Step 1：寫一組會失敗的測試**

在 `app/test/library/book_import_service_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
```

在 `group('CBZ 匯入', () { ... });` 區塊內，找到最後一個既有測試（`contentFingerprint 對原始 content:// URI 計算...`）結尾與區塊收尾 `});` 之間（`makeValidCbz()`／`makeEmptyCbz()` 這兩個區塊內函式在此範圍內仍在作用域中），新增：

```dart
    test(
        'CBZ 匯入成功後，content_index_status 標記為 unsupported'
        '（epic-10-search Issue 2）', () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/unsupported_comics.cbz'],
        displayNames: ['unsupported_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'unsupported');
    });

    test(
        '未提供 fullTextSearchSettingsRepository（null）時，CBZ 匯入結果不受影響，'
        '也不寫入 content_index_status', () async {
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/no_search_comics.cbz'],
        displayNames: ['no_search_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
```

在同一個檔案內，`main()` 內任一位置（例如緊接在 `group('CBZ 匯入', ...)` 區塊之後）新增一個新的 `group`，涵蓋 CBZ 以外格式的連動（**review-plan-issue-2.md C-2**：驗證原計畫第一版遺漏的「一般格式新書匯入」情境）：

```dart
  group('epic-10-search Issue 2：新匯入書籍全文檢索狀態連動（非 CBZ 格式）', () {
    test('EPUB 匯入時若 foliate 分類已啟用，寫入 pending 並喚醒排程器',
        () async {
      var requestProcessingCallCount = 0;
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () => requestProcessingCallCount++,
      );
      await fullTextSearchSettingsRepository.setEnabled(
        ContentIndexCategory.foliate,
        true,
      );
      // setEnabled(true) 本身的批次回填也會呼叫一次，重置計數只驗證匯入
      // 這一步觸發的喚醒次數。
      requestProcessingCallCount = 0;
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '測試書'};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'pending');
      expect(requestProcessingCallCount, 1);
    });

    test('EPUB 匯入時若 foliate 分類未啟用，不寫入 content_index_status',
        () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '測試書'};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book_disabled.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
  });
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: FAIL（編譯錯誤：`BookImportServiceImpl` 沒有 `fullTextSearchSettingsRepository` 具名參數）。

- [x] **Step 3：實作**

在 `app/lib/library/book_import_service_impl.dart`，於 import 區塊新增：

```dart
import '../search/full_text_search_settings_repository.dart';
```

找到：

```dart
class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    AppThemePreferences? themePreferences,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences();

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final AppThemePreferences _themePreferences;
```

取代為：

```dart
class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    AppThemePreferences? themePreferences,
    FullTextSearchSettingsRepository? fullTextSearchSettingsRepository,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences(),
        _fullTextSearchSettingsRepository = fullTextSearchSettingsRepository;

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final AppThemePreferences _themePreferences;

  /// epic-10-search Issue 2（spec.md §7）：新書匯入成功後連動全文檢索
  /// 索引狀態（CBZ 標記 unsupported；其餘格式依開關狀態決定是否插入
  /// pending）。`null` 時（例如既有測試未提供）完全略過，行為與本工單
  /// 之前完全一致。
  final FullTextSearchSettingsRepository? _fullTextSearchSettingsRepository;
```

找到 `_importSingleFile()` 方法結尾：

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: source,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      // 【診斷修正，epic-18-reader-device-qa Issue 29】剛匯入、從未打開過
      // 的書不該視為「剛讀過」——用 epoch 0 表示「尚未讀過」的哨兵值，
      // 讓「最後閱讀」排序／自動開書永遠把它排在任何真正被讀過的書之後。
      // `lastReadTime` 欄位為 `NOT NULL`，改回 nullable 需要 schema
      // migration，用哨兵值比新增可為 null 的欄位改動範圍更小。真正的
      // 「最後閱讀時間」由 ReadingPositionRepository.save() 於使用者實際
      // 閱讀、位置有異動時統一維護。
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    return _repository.insertBook(book);
  }
```

取代為：

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: source,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      // 【診斷修正，epic-18-reader-device-qa Issue 29】剛匯入、從未打開過
      // 的書不該視為「剛讀過」——用 epoch 0 表示「尚未讀過」的哨兵值，
      // 讓「最後閱讀」排序／自動開書永遠把它排在任何真正被讀過的書之後。
      // `lastReadTime` 欄位為 `NOT NULL`，改回 nullable 需要 schema
      // migration，用哨兵值比新增可為 null 的欄位改動範圍更小。真正的
      // 「最後閱讀時間」由 ReadingPositionRepository.save() 於使用者實際
      // 閱讀、位置有異動時統一維護。
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final insertedBook = await _repository.insertBook(book);
    // epic-10-search Issue 2（spec.md §7，review-plan-issue-2.md C-2）：
    // _importSingleFile() 是全專案所有新書匯入與雲端/遠端首次下載的唯一
    // 收斂點（本機檔案/資料夾選取、Google Drive、OneDrive、Calibre/OPDS
    // 皆經由 BookImportService.importFiles() 呼叫到這裡）。統一呼叫
    // handleBookAvailable()（不只 CBZ）讓所有格式都能在已啟用全文檢索的
    // 情況下正確被排入 pending 佇列並喚醒排程器。search-index 只是衍生
    // 資料，寫入失敗不應讓原本已成功的書籍匯入被判定失敗
    // （review-plan-issue-2.md M-1）。
    try {
      await _fullTextSearchSettingsRepository?.handleBookAvailable(
        insertedBook,
      );
    } catch (_) {
      // 靜默略過——書籍記錄已成功建立，全文檢索索引狀態可日後透過
      // 「重建索引」補上，不應讓整筆匯入被視為失敗。
    }
    return insertedBook;
  }
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: PASS（新增 4 項測試＋既有全部測試皆通過——這個檔案測試量大，整檔重跑確保沒有破壞既有匯入行為）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(search): 新匯入書籍統一連動全文檢索索引狀態（Issue 2）"
```

---

### Task 3：重新下載完成事件連動

**Files：**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `FullTextSearchSettingsRepository.handleBookAvailable(Book book)`（透過既有 `widget.readerFeatureRepositories.fullTextSearchSettingsRepository` 依賴注入路徑，Issue 3 已建立，本工單不需要新增任何依賴注入 wiring）。

- [x] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/library_screen_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

import '../support/fake_full_text_search_settings_repository.dart';
```

在 `group('Issue 4：待下載書籍重新下載', () { ... });` 區塊內，找到既有測試 `'確認後成功重新下載，更新 filePath/isDownloaded，不建立新的 Book 記錄'` 結尾之後，新增：

```dart
    testWidgets(
        '重新下載完成後呼叫 fullTextSearchSettingsRepository.handleBookAvailable'
        '（epic-10-search Issue 2）', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      final fullTextSearchSettingsRepository =
          FakeFullTextSearchSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              fullTextSearchSettingsRepository:
                  fullTextSearchSettingsRepository,
            ),
            isMobileDataConnection: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_redownload_confirm_button')),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        fullTextSearchSettingsRepository.handleBookAvailableCalls,
        hasLength(1),
      );
      final calledWith =
          fullTextSearchSettingsRepository.handleBookAvailableCalls.single;
      expect(calledWith.id, 'b1');
      expect(calledWith.isDownloaded, isTrue);
    });
```

- [x] **Step 2：執行測試，確認因為 production 行為尚未實作而失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL（`fullTextSearchSettingsRepository.handleBookAvailableCalls` 為空，斷言 `hasLength(1)` 失敗）。

- [x] **Step 3：實作**

在 `app/lib/screens/library_screen.dart`，找到：

```dart
      final permanentPath = await promoteToPermanent(tempPath);

      await widget.repository.updateBook(
        book.copyWith(filePath: permanentPath, isDownloaded: true),
      );
      if (!mounted) return;
      await _bookListController.loadBooks();
```

取代為：

```dart
      final permanentPath = await promoteToPermanent(tempPath);

      final updatedBook = book.copyWith(
        filePath: permanentPath,
        isDownloaded: true,
      );
      await widget.repository.updateBook(updatedBook);
      // epic-10-search Issue 2（spec.md §7）：重新下載完成＝既有
      // content_index_status 列已因先前的「移除本機快取」被清空（見本
      // 計畫 Task 4），此處補上對應的 unsupported/pending 標記，讓這本
      // 書重新回到正確的索引狀態。search-index 只是衍生資料，寫入失敗
      // 不應讓使用者眼中「檔案已下載成功」被誤判為失敗
      // （review-plan-issue-2.md M-1）。
      try {
        await widget
            .readerFeatureRepositories.fullTextSearchSettingsRepository
            ?.handleBookAvailable(updatedBook);
      } catch (_) {
        // 靜默略過——檔案下載與資料庫標記更新才是核心操作，索引狀態可
        // 日後透過「重建索引」補上。
      }
      if (!mounted) return;
      await _bookListController.loadBooks();
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（新增測試＋既有全部測試皆通過——這是本專案最大的測試檔之一，整檔重跑確保沒有破壞既有重新下載/書架行為）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(search): 重新下載完成後連動全文檢索索引狀態（Issue 2）"
```

---

### Task 4：移除本機快取事件連動

**Files：**
- Modify: `app/lib/screens/library_batch_actions.dart`
- Test: `app/test/screens/library_batch_actions_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `FullTextSearchSettingsRepository.clearBookIndex(String bookId)`。
- Produces：`LibraryBatchActions` 建構子新增可選具名參數 `FullTextSearchSettingsRepository? fullTextSearchSettingsRepository`（`null` 時行為與現行完全一致）——供 Task 5 透過 `library_screen.dart` 既有 `_batchActions = LibraryBatchActions(...)` 建構點注入。

- [x] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/library_batch_actions_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

import '../support/fake_full_text_search_settings_repository.dart';
```

在既有 `'removeLocalCache() 只處理選取集合中……'` 測試之後、`main()` 收尾 `}` 之前，新增：

```dart
  test(
      'removeLocalCache() 對被處理的書籍呼叫 clearBookIndex 清除搜尋索引'
      '（epic-10-search Issue 2）', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', source: BookSource.calibreOpds, isDownloaded: true),
      _book(id: '2', source: BookSource.local, isDownloaded: true),
    ]);
    final fullTextSearchSettingsRepository =
        FakeFullTextSearchSettingsRepository();
    final actions = LibraryBatchActions(
      repository: repository,
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
    );
    final books = await repository.listBooks();

    await actions.removeLocalCache({'1', '2'}, books);

    // 書籍 2 是 local 來源，shouldInclude 過濾後不會被處理，只有書籍 1
    // 應該觸發 clearBookIndex。
    expect(fullTextSearchSettingsRepository.clearBookIndexCalls, ['1']);
  });
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/screens/library_batch_actions_test.dart`
Expected: FAIL（編譯錯誤：`LibraryBatchActions` 沒有 `fullTextSearchSettingsRepository` 具名參數）。

- [x] **Step 3：實作**

在 `app/lib/screens/library_batch_actions.dart`，於 import 區塊新增：

```dart
import '../search/full_text_search_settings_repository.dart';
```

找到：

```dart
class LibraryBatchActions {
  const LibraryBatchActions({required this.repository});

  final LibraryRepository repository;
```

取代為：

```dart
class LibraryBatchActions {
  const LibraryBatchActions({
    required this.repository,
    this.fullTextSearchSettingsRepository,
  });

  final LibraryRepository repository;

  /// epic-10-search Issue 2（spec.md §7）：移除本機快取時一併清除搜尋
  /// 索引資料。`null` 時（例如既有測試未提供）完全略過，行為與本工單
  /// 之前完全一致。
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
```

找到：

```dart
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
```

取代為：

```dart
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
        try {
          await fullTextSearchSettingsRepository?.clearBookIndex(book.id);
        } catch (_) {
          // 【review-plan-issue-2.md M-1】靜默略過——避免單一書籍的索引
          // 清除異常中斷整個批次迴圈，導致後面幾本書的實體檔案快取無法
          // 被刪除；索引資料為衍生性資料，維護失敗不應影響核心的快取
          // 移除操作。
        }
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/library_batch_actions_test.dart`
Expected: PASS（新增測試＋既有全部測試皆通過）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/library_batch_actions.dart app/test/screens/library_batch_actions_test.dart
git commit -m "feat(search): 移除本機快取時清除全文檢索索引資料（Issue 2）"
```

---

### Task 5：`library_screen.dart` 依賴注入轉送＋`didUpdateWidget` 同步＋`main.dart` 組裝

**Files：**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`

**Interfaces：**
- Consumes：Task 2 的 `BookImportServiceImpl.fullTextSearchSettingsRepository` 建構參數、Task 4 的 `LibraryBatchActions.fullTextSearchSettingsRepository` 建構參數、既有 `SqliteFullTextSearchSettingsRepository`。
- Produces：無新公開 API（純組裝），本 Task 完成後 CBZ 匯入標記／新書匯入回填／重新下載事件／移除快取事件在正式 App 中即可運作。

本 Task 是純組裝程式碼，不採用「先寫失敗測試」的 TDD 步驟，直接修改＋驗證（`library_screen.dart` 這一處改動已被 Task 3／Task 4 的既有測試間接覆蓋——`LibraryBatchActions` 建構點若忘記傳入新參數，Task 4 新增的測試不會因此失敗，因為那則測試直接建構 `LibraryBatchActions` 而不經過 `LibraryScreen`；因此本 Task Step 3 會額外手動驗證這一處 wiring，見下方）。

- [x] **Step 1：`library_screen.dart` 把 `fullTextSearchSettingsRepository` 轉送給 `LibraryBatchActions`，並在 `didUpdateWidget()` 同步（review-plan-issue-2.md M-2）**

在 `app/lib/screens/library_screen.dart`，找到：

```dart
    _batchActions = LibraryBatchActions(repository: widget.repository);
```

取代為：

```dart
    _batchActions = LibraryBatchActions(
      repository: widget.repository,
      fullTextSearchSettingsRepository:
          widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
    );
```

找到：

```dart
  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    }
  }
```

取代為：

```dart
  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    }
    // 【review-plan-issue-2.md M-2】_batchActions 在 initState() 建構時
    // 捕捉了當下的 repository/fullTextSearchSettingsRepository 參考；
    // LibraryReaderFeatureRepositories 沒有覆寫 ==（預設參考相等），上層
    // 每次 build() 重新建構這個 bundle 時這裡幾乎都會判定為「已變更」而
    // 重新建構 _batchActions——成本極低（純資料持有物件），不需要額外
    // 優化，重點是不遺漏真正的替換情境。
    if (widget.readerFeatureRepositories != oldWidget.readerFeatureRepositories ||
        widget.repository != oldWidget.repository) {
      _batchActions = LibraryBatchActions(
        repository: widget.repository,
        fullTextSearchSettingsRepository:
            widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
      );
    }
  }
```

- [x] **Step 2：`main.dart` 重新排序建構順序，並傳入 `BookImportServiceImpl`**

在 `app/lib/main.dart`，找到：

```dart
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
  );
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-10-search Issue 1：背景全文檢索索引引擎。本工單只負責讓引擎
  // 能運作，「啟用全文檢索」開關與批次回填既有書庫是 Issue 3 的範圍——
  // 目前 content_index_status 裡不會有任何 pending 列，排程器啟動後
  // 純粹閒置等待，直到 Issue 3 落地才會有實際工作可做。
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
  // epic-10-search Issue 3：「啟用全文檢索」設定模型。requestProcessing
  // 以 callback 注入（而非直接持有整個 contentIndexingScheduler），見
  // plans/plan-issue-3.md Global Constraints。
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
```

取代為：

```dart
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-10-search Issue 1：背景全文檢索索引引擎。本工單只負責讓引擎
  // 能運作，「啟用全文檢索」開關與批次回填既有書庫是 Issue 3 的範圍——
  // 目前 content_index_status 裡不會有任何 pending 列，排程器啟動後
  // 純粹閒置等待，直到 Issue 3 落地才會有實際工作可做。
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
  // epic-10-search Issue 3：「啟用全文檢索」設定模型。requestProcessing
  // 以 callback 注入（而非直接持有整個 contentIndexingScheduler），見
  // plans/plan-issue-3.md Global Constraints。
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
  // epic-10-search Issue 2：新書匯入（含 CBZ 標記 unsupported）需要
  // fullTextSearchSettingsRepository（見 plans/plan-issue-2.md），因此
  // importService 的建構挪到這裡（在它之後），不再是 repository 開啟後
  // 立刻建構。
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
    fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
  );
```

- [x] **Step 3：手動驗證 `library_screen.dart` 的 wiring（Task 4 測試無法覆蓋這一處）**

Run: `flutter analyze`（先確認型別正確、沒有遺漏的具名參數）
Expected: `No issues found!`

接著執行 `app/test/screens/library_screen_test.dart` 既有的移除快取相關測試，確認這些既有測試在 wiring 變更後仍然全數通過——不需要新增測試，因為 `LibraryBatchActions` 本身的 `clearBookIndex` 呼叫邏輯已由 Task 4 的單元測試鎖住，這裡只需要確認「透過 `LibraryScreen` 組裝時沒有忘記傳入新參數導致編譯錯誤或執行期例外」：

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全數通過，含既有移除快取相關測試）。

- [x] **Step 4：跑本次全部異動觸及的測試檔，確認整體沒有回歸**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart test/library/book_import_service_test.dart test/screens/library_screen_test.dart test/screens/library_batch_actions_test.dart`
Expected: PASS（本計畫新增與修改的所有測試檔皆通過；`main.dart` 本身無對應測試檔，正確性已由上述測試檔涵蓋的依賴注入路徑＋`flutter analyze` 型別檢查涵蓋）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart
git commit -m "feat(search): library_screen/main.dart 組裝 Issue 2 索引狀態連動（Issue 2）"
```

- [x] **Step 7：（人類／執行者手動）真機或模擬器驗證**

`flutter run` 啟動 App，確認：
1. 在「設定→閱讀」開啟「其他格式全文檢索」開關後，匯入一本新的 EPUB，確認該書很快出現一筆 `content_index_status.status='pending'` 並被排程器處理完成（不需要手動關開開關或重建索引）——這是本輪審查（C-2）修正的核心情境，務必實測驗證。
2. 匯入一本 CBZ 漫畫，確認該書 `content_index_status.status == 'unsupported'`，排程器不會嘗試處理它。
3. 若有已連結的 Calibre/OPDS 遠端書庫站點：對一本已下載的書執行「移除本機快取」，確認該書的 `content_index_status`／`book_content_index` 資料列被清空；接著「重新下載」，若對應分類（PDF／其他格式）目前已啟用，確認該書重新出現一筆 `status='pending'` 並最終被排程器處理完成，不需要額外手動觸發。

（本 Task 不需要跑全專案 `flutter test`——依使用者指示，Epic 10 尚有 Issue 4／5 未完成，不是最後一個 Issue，全套測試留到整個 Epic 收尾前再跑一次，比照 `plan-issue-3.md`／`plan-issue-6.md` 已採用的既有慣例。）

---

## 自我審查（Self-Review，計畫撰寫者執行，非另一輪審查）

**Spec 覆蓋度：** spec.md §7 三個段落逐項對應——(1)「CBZ／DRM KF8：`content_index_status.status = 'unsupported'`」→ CBZ 由 Task 1（`markUnsupported`，經 `handleBookAvailable` 統一入口）＋Task 2（匯入時呼叫）落地；DRM KF8 查證後確認現行架構下無 `Book` 記錄可標記，已在 Global Constraints 明確記錄查證過程與人類拍板的處理方式，不實作任何程式碼。(2)「下載完成→依分類啟用狀態決定是否插入 pending」→ Task 1（`handleBookAvailable`，已修正 C-1 喚醒排程器與 I-1 `isDownloaded` 防禦）＋Task 2（**新增**：所有格式的新匯入書籍統一連動，修正原計畫 C-2 遺漏）＋Task 3（`_handleRedownload` 呼叫既有重新下載場景）。(3)「移除快取→清除索引」→ Task 1（`clearBookIndex`，已修正 I-2 補齊 `book_content_fts` 驗證）＋Task 4（`removeLocalCache` 呼叫，已依 M-1 加上 try/catch）＋Task 5（`LibraryScreen` 轉送 wiring，已依 M-2 加上 `didUpdateWidget` 同步）。issues.md Issue 2 單元測試要求三項：「CBZ／DRM KF8 匯入後 unsupported 且排程器排除」→ Task 2 測試（CBZ 部分）＋既有 `_formatFilterFor()`（Issue 3 產物）本身已保證排程器排除；DRM KF8 部分因無 Book 記錄而無需測試。「下載完成事件觸發後出現 pending」→ Task 1／Task 2（新匯入場景）／Task 3（重新下載場景）測試，且皆已驗證 `requestProcessingCallCount` 確實遞增。「移除快取事件觸發後三張表資料列皆清空」→ Task 1（`clearBookIndex` 同時處理 `book_content_index`／`content_index_status`／`book_content_fts`，已依 I-2 補齊三張表驗證）。

**Placeholder 掃描：** 無「TBD」「稍後補上」「類似 Task N」等字樣，所有程式碼片段皆為完整可直接套用的內容。

**型別一致性：** `markUnsupported(String bookId)`／`handleBookAvailable(Book book)`／`clearBookIndex(String bookId)` 在 Task 1 定義（抽象介面＋實作＋Fake），Task 2／3／4 的呼叫端引數型別與具名方式完全一致（`handleBookAvailable` 命名已從原計畫第一版的 `handleDownloadCompleted` 全面改名，Task 1～3 與 Fake 的呼叫記錄清單 `handleBookAvailableCalls` 命名一致）；`BookImportServiceImpl.fullTextSearchSettingsRepository`／`LibraryBatchActions.fullTextSearchSettingsRepository` 兩個新建構參數在 Task 2／4 定義、Task 5 `main.dart`／`library_screen.dart` 呼叫端命名一致。
