# Epic 5 Issue 2：本機閱讀位置記憶（EPUB + PDF）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 開啟書籍時自動接續上次閱讀位置（EPUB 用 Readium Locator 序列化字串、PDF 用頁索引），並在使用者離開閱讀畫面或 App 進入背景時各觸發一次本機寫入；同時活化既有恆為 0 的 `Book.progress` 欄位。

**Architecture:** 位置資料存放於 `books` 表新增的 2 個欄位（`epubLocator`/`pdfPageIndex`）+ 既有 `progress` 欄位，透過新的窄範圍 `ReadingPositionRepository` 存取——不重用 `LibraryRepository.updateBook()`（會整列覆寫 `books`，而 `ReaderScreen` 手上並沒有完整 `Book` 物件的其餘欄位如 `title`/`author`）。`ReaderPrefsManager`/`ReaderPrefsManagerImpl` 是既有的「載入/持久化深模組」，比照 ADR 0007 的窄範圍 repository 注入模式擴大職責涵蓋位置讀寫，讓 `ReaderScreen` 的公開建構子維持 `filePath`/`bookId`/`prefsManager` 三個參數不變（`ReaderScreen(...)` 目前有 58 處呼叫點，新增必要建構參數的變更半徑過大，見下方 Global Constraints）。原生端：PDF 端 `currentPageIndex` 初始化改為讀取 `initialPageIndex`；EPUB 端把既有、從未被呼叫過的 `PaginationListener.onPageChanged(pageIndex, totalPages, locator)` 死程式碼填入實作，透過既有的 `EpubNavigatorFactory.createFragmentFactory(initialLocator = ...)` 參數讀取起始定位。

**Tech Stack:** Flutter/Dart（`sqflite`）、Kotlin（Readium `kotlin-toolkit` 3.3.0 `org.readium.r2.shared.publication.Locator`／`android.graphics.pdf.PdfRenderer`）。

## Global Constraints

- 所有文件/註解/測試描述文字使用正體中文（zh-TW），程式碼識別字沿用既有英文慣例。
- `ReaderScreen` 公開建構子（`filePath`/`bookId`/`prefsManager`）**不得新增必要參數**——目前有 58 處呼叫點（`app/test` 22 處、`app/integration_test` 36 處），新增必要參數等同對全部呼叫點造成破壞性變更。所有新讀寫路徑一律透過既有的 `prefsManager` 注入點擴充。
- 位置資料的資料庫存取一律透過新的 `ReadingPositionRepository`（partial `UPDATE`），**不得**透過 `LibraryRepository.updateBook(Book)`（會整列覆寫，`ReaderScreen` 手上沒有完整 `Book` 物件）。
- Schema migration 比照 `book_reader_prefs` 既有的累加式升級模式：`onUpgrade` 內一律用獨立的 `if (oldVersion < N)`，不得改成 `else if`（見 `sqlite_library_repository.dart` 既有註解與 `docs/epics/epic-5-toc-pagination/spec.md`「Schema Migration（審查修正）」）。
- 寫入時機只有兩個：`ReaderScreen.dispose()` 與 `AppLifecycleState.paused`（App 進入背景）——不得在翻頁/捲動時即時寫入（spec.md「本機閱讀位置記憶」決策，人類已明確拒絕防抖節流的中間方案）。
- `initialLocatorJson`（EPUB）／`initialPageIndex`（PDF）是一次性的開書起始值，透過 `openBook` method channel 呼叫的獨立頂層 key 傳遞，**不得**併入 `_buildPreferencesMap()`／`_preferencesChanged()` 的偏好設定 diff 邏輯——那組邏輯是給會隨使用者互動重複送出的顯示偏好設定用的，起始定位只在開書當下送一次。
- 外部呼叫 `PdfReaderView` 私有 State 方法一律透過既有的強型別 static helper 模式（見 `PdfReaderView.jumpToPage`），不得新增 `as dynamic` 呼叫。
- `LibraryScreen` 從 `ReaderScreen` 返回後**必須**重新載入書籍清單（見 Task 7）——否則記憶體內的舊 `Book` 快照會在後續任何整列 `updateBook()` 操作（例如分類移動）時，把 `ReaderScreen` 剛寫入的最新 `progress`/`epubLocator`/`pdfPageIndex` 覆蓋回舊值（審查修正，見文末「審查修正紀錄」）。

---

## Task 1：`books` 表新增位置欄位 + Schema Migration（version 4 → 5）

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces：`Book.epubLocator` (`String?`)、`Book.pdfPageIndex` (`int?`)——`Book.progress` (`double`) 欄位語意不變，仍是既有欄位，本 Task 只新增另外 2 個欄位；`books` 表新增欄位 `epubLocator TEXT`、`pdfPageIndex INTEGER`（與既有 `filePath`/`coverPath`/`groupName` 一致採用 camelCase，非 `book_reader_prefs` 表的 snake_case）。

- [ ] **Step 1：修改 `Book` model，新增 2 個欄位與更新 `toMap`/`fromMap`/`copyWith`**

`app/lib/library/models/book.dart` 全檔內容：

```dart
import 'book_group.dart';
import 'library_enums.dart';

/// 圖書庫中一本書籍的詮釋資料，對應 sqflite `books` 表的一列（見
/// docs/epics/epic-1-library/spec.md「資料模型」章節）。
class Book {
  final String id;
  final String title;
  final String? author;
  final BookFileFormat format;

  /// 檔案系統路徑或 `content://`/`file://` URI 字串（見
  /// docs/adr/0002-content-uri-reader-contract.md）。
  final String filePath;
  final BookSource source;

  /// 產生後封面圖檔的本機路徑（PNG）；`null` 表示尚未產生或產生失敗。
  final String? coverPath;

  /// 閱讀進度百分比（0.0-1.0），由 epic-5-toc-pagination Issue 2 起正式
  /// 活化——EPUB 用 Readium `Locator.locations.totalProgression`，PDF 用
  /// `(pdfPageIndex + 1) / 總頁數`，寫入時機見 [epubLocator]/[pdfPageIndex]。
  final double progress;

  /// EPUB 序列化後的 Readium `Locator`（`Locator.toJSON().toString()`），
  /// `null` 代表尚無記錄（例如書籍從未被開啟過，或本書為 PDF 格式）。與
  /// [pdfPageIndex] 互斥（一本書只會用到其中之一），但兩欄位皆可能同時
  /// 為 null（見 docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置
  /// 記憶」——位置資料是系統追蹤的狀態，故放在 Book 而非
  /// BookReaderPrefs）。
  final String? epubLocator;

  /// PDF 頁索引（0-indexed），`null` 代表尚無記錄。與 [epubLocator] 互斥。
  final int? pdfPageIndex;

  final String groupName;
  final DateTime createTime;
  final DateTime lastReadTime;

  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.filePath,
    required this.source,
    this.coverPath,
    this.progress = 0,
    this.epubLocator,
    this.pdfPageIndex,
    this.groupName = BookGroup.uncategorized,
    required this.createTime,
    required this.lastReadTime,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format.name,
      'filePath': filePath,
      'source': source.name,
      'coverPath': coverPath,
      'progress': progress,
      'epubLocator': epubLocator,
      'pdfPageIndex': pdfPageIndex,
      'groupName': groupName,
      'createTime': createTime.millisecondsSinceEpoch,
      'lastReadTime': lastReadTime.millisecondsSinceEpoch,
    };
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      format: BookFileFormat.values.byName(map['format'] as String),
      filePath: map['filePath'] as String,
      source: BookSource.values.byName(map['source'] as String),
      coverPath: map['coverPath'] as String?,
      progress: (map['progress'] as num).toDouble(),
      epubLocator: map['epubLocator'] as String?,
      pdfPageIndex: map['pdfPageIndex'] as int?,
      groupName: map['groupName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int),
      lastReadTime:
          DateTime.fromMillisecondsSinceEpoch(map['lastReadTime'] as int),
    );
  }

  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數（目前只需要
  /// 覆寫 [groupName]——供 Issue 10 的批次分類異動使用）。
  Book copyWith({String? groupName}) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
}
```

（`copyWith` 刻意不新增 `progress`/`epubLocator`/`pdfPageIndex` 的覆寫參數——本 Issue 全部的位置寫入皆透過新的 `ReadingPositionRepository` partial update，不經過 `Book.copyWith()`/`LibraryRepository.updateBook()` 這條路徑，比照 Global Constraints 說明。)

- [ ] **Step 2：`sqlite_library_repository.dart` 新增 version 5 migration**

在 `open()` 內把 `version: 4` 改為 `version: 5`，`onCreate` 的 `CREATE TABLE books` 加入 2 個新欄位，`onUpgrade` 補上 `if (oldVersion < 5)` 區塊：

```dart
  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT,
            format TEXT NOT NULL,
            filePath TEXT NOT NULL,
            source TEXT NOT NULL,
            coverPath TEXT,
            progress REAL NOT NULL DEFAULT 0,
            epubLocator TEXT,
            pdfPageIndex INTEGER,
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
        await _createBookReaderPrefsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 舊裝置從未有過 book_reader_prefs 表，_createBookReaderPrefsTable
          // 目前的 CREATE TABLE 已包含全部欄位（含 PDF、雙頁），一步到位，
          // 不需要再跑後續的 ALTER TABLE（該表在這之前根本不存在）。
          await _createBookReaderPrefsTable(db);
        } else {
          // 【審查修正】原本此處用「if (oldVersion < 2) { ...; return; }」
          // 提前結束整個 onUpgrade，這對 book_reader_prefs 表本身是對的
          // （表剛建好、不需要再 ALTER），但會連帶跳過下方 books 表的
          // oldVersion < 5 遷移——version 1 裝置跳級升級到 version 5 時，
          // books 表會缺少 epubLocator/pdfPageIndex 欄位，實際讀寫時拋出
          // `no such column` 崩潰（`/superpowers:requesting-code-review`
          // 審查報告 Critical 1 發現）。改為 if/else：只有當
          // book_reader_prefs 表已存在（oldVersion >= 2）時，才需要用
          // ALTER TABLE 逐步補上該表後續版本新增的欄位；books 表的遷移
          // 移到 if/else 區塊外、不受此分支影響，確保任何 oldVersion 都會
          // 執行到。
          if (oldVersion < 3) {
            await _addPdfReaderPrefsColumns(db);
          }
          if (oldVersion < 4) {
            await _addDualPageColumns(db);
          }
        }
        if (oldVersion < 5) {
          // epic-5-toc-pagination Issue 2：本機閱讀位置記憶新增的 2 個
          // 欄位，補追加到既有（version 1 起已存在）的 books 表。刻意放在
          // 上方 if/else 之外、無條件檢查——books 表與 book_reader_prefs
          // 是兩張獨立的表，此欄位遷移不論裝置目前處於哪個舊版本，只要
          // oldVersion < 5 就必須執行，不能被 book_reader_prefs 表的建立
          // /升級分支影響。
          await _addReadingPositionColumns(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }
```

在 `_addDualPageColumns` 之後新增：

```dart
  static Future<void> _addReadingPositionColumns(Database db) async {
    // 本機閱讀位置記憶（epic-5-toc-pagination Issue 2）新增的 2 個欄位，
    // 補追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置記憶」。
    await db.execute('ALTER TABLE books ADD COLUMN epubLocator TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN pdfPageIndex INTEGER');
  }
```

- [ ] **Step 3：撰寫 round-trip 測試（`sqlite_library_repository_test.dart`）**

在既有的 `_book()` helper 之後、`void main()` 內任一位置新增：

```dart
  test('insertBook/updateBook 正確保存 epubLocator／pdfPageIndex，listBooks 讀回相同值',
      () async {
    await repository.insertBook(_book('b1'));

    await repository.updateBook(_book('b1').copyWith());
    // Book.copyWith 不支援覆寫 epubLocator/pdfPageIndex（見 Task 1 Step 1
    // 說明），改用完整建構子組出待寫入的 Book。
    final withPosition = Book(
      id: 'b1',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/b1',
      source: BookSource.local,
      progress: 0.42,
      epubLocator: '{"href":"/chap1.xhtml","locations":{"totalProgression":0.42}}',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await repository.updateBook(withPosition);

    final books = await repository.listBooks();
    expect(books.single.progress, 0.42);
    expect(books.single.epubLocator,
        '{"href":"/chap1.xhtml","locations":{"totalProgression":0.42}}');
    expect(books.single.pdfPageIndex, isNull);
  });
```

- [ ] **Step 4：撰寫 migration 回歸測試（version 4 → 5，比照既有 v2→v3/v3→v4 測試風格）**

在既有的「既有 version 3 裝置升級後...」測試之後新增：

```dart
  test('既有 version 4 裝置升級後，books 表新增位置欄位且既有書籍資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v4_to_v5_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 4」的舊資料庫：手動以 version 4 當時的
    // schema（books 表不含 epubLocator/pdfPageIndex）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 5 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_size REAL,
              pdf_fit_mode TEXT,
              dual_page_mode TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=4 →
    // newVersion=5），驗證既有書籍資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍'); // 既有資料不受影響
    expect(books.single.epubLocator, isNull); // 新欄位存在且預設 NULL
    expect(books.single.pdfPageIndex, isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'epubLocator': '{"href":"/c1.xhtml"}'},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.epubLocator, '{"href":"/c1.xhtml"}');
  });
```

- [ ] **Step 5：撰寫 migration 回歸測試（version 1 → 5 跳級升級，審查修正）**

`/superpowers:requesting-code-review` 審查報告 Important 1 指出：只測 v4→v5 無法偵測到 Critical 1 那類「跳級升級被中途 `return`/分支結構意外跳過」的缺陷，須額外覆蓋最早、最危險的 v1→v5 路徑（模擬完全沒有 `book_reader_prefs` 表、且 `books` 表也不含新欄位的最原始 schema）。在既有的「既有 version 2 裝置升級後...」測試之前（或任一位置）新增：

```dart
  test('既有 version 1 裝置（無 book_reader_prefs 表）跳級升級到 version 5，兩張表皆正確補齊',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v5_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 1」的最原始資料庫：只有 groups/books 兩張
    // 表，完全沒有 book_reader_prefs 表，books 表也不含
    // epubLocator/pdfPageIndex 欄位。這是 onUpgrade 分支結構最容易出錯
    // 的起點（見 Critical 1 審查修正）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '最早期書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=1 →
    // newVersion=5）。若 Critical 1 的 `return` 缺陷仍存在，
    // _addReadingPositionColumns 不會被執行，下方對 epubLocator 的
    // UPDATE 會直接拋出 `no such column` 例外，測試失敗。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    // book_reader_prefs 表須存在且已是最終版 schema（一步到位）。
    final prefsColumns = await upgraded.database
        .rawQuery('PRAGMA table_info(book_reader_prefs)');
    expect(
      prefsColumns.map((c) => c['name'] as String).toSet(),
      containsAll(['pdf_fit_mode', 'dual_page_mode']),
    );

    // books 表須正確補上位置欄位，且既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '最早期書籍');
    expect(books.single.epubLocator, isNull);
    expect(books.single.pdfPageIndex, isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'epubLocator': '{"href":"/c1.xhtml"}'},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.epubLocator, '{"href":"/c1.xhtml"}');
  });
```

- [ ] **Step 6：執行測試確認通過**

```bash
cd app && flutter test test/library/sqlite_library_repository_test.dart
```

Expected: 全數 PASS（含新增的 3 個測試——round-trip、v4→v5、v1→v5）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/models/book.dart app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-5): books 表新增 epubLocator/pdfPageIndex 欄位（schema v5）"
```

---

## Task 2：`ReadingPosition` 值物件 + `ReadingPositionRepository`

**Files:**
- Create: `app/lib/reader/reading_position.dart`
- Create: `app/lib/reader/reading_position_repository.dart`
- Create: `app/test/support/fake_reading_position_repository.dart`
- Test: `app/test/reader/reading_position_repository_test.dart`

**Interfaces:**
- Consumes：`Database`（sqflite，來自 `SqliteLibraryRepository.database` getter，Task 1 已存在）。
- Produces：`ReadingPosition({epubLocatorJson, pdfPageIndex, progress = 0})`；`ReadingPositionRepository(Database).load(bookId) → Future<ReadingPosition>`／`.save(bookId, ReadingPosition) → Future<void>`——供 Task 3 的 `ReaderPrefsManagerImpl` 注入使用。

- [ ] **Step 1：建立 `ReadingPosition` 值物件**

`app/lib/reader/reading_position.dart`：

```dart
/// 單一書籍的本機閱讀位置（epic-5-toc-pagination Issue 2），對應 `books`
/// 表的 `epubLocator`/`pdfPageIndex`/`progress` 3 個欄位。一本書只會用到
/// [epubLocatorJson] 或 [pdfPageIndex] 其中之一（依格式而定），兩者可能
/// 同時為 null（尚無記錄）。
class ReadingPosition {
  /// 序列化後的 Readium `Locator`（`Locator.toJSON().toString()`）。
  final String? epubLocatorJson;

  /// PDF 頁索引（0-indexed）。
  final int? pdfPageIndex;

  /// 閱讀進度百分比（0.0-1.0）。
  final double progress;

  const ReadingPosition({
    this.epubLocatorJson,
    this.pdfPageIndex,
    this.progress = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.epubLocatorJson == epubLocatorJson &&
      other.pdfPageIndex == pdfPageIndex &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(epubLocatorJson, pdfPageIndex, progress);

  @override
  String toString() =>
      'ReadingPosition(epubLocatorJson: $epubLocatorJson, pdfPageIndex: $pdfPageIndex, progress: $progress)';
}
```

- [ ] **Step 2：建立 `ReadingPositionRepository`**

`app/lib/reader/reading_position_repository.dart`：

```dart
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
```

- [ ] **Step 3：建立測試用 Fake（比照 `FakeBookReaderPrefsRepository`）**

`app/test/support/fake_reading_position_repository.dart`：

```dart
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';

class FakeReadingPositionRepository implements ReadingPositionRepository {
  final Map<String, ReadingPosition> _storage = {};

  @override
  Future<ReadingPosition> load(String bookId) async {
    return _storage[bookId] ?? const ReadingPosition();
  }

  @override
  Future<void> save(String bookId, ReadingPosition position) async {
    _storage[bookId] = position;
  }
}
```

- [ ] **Step 4：撰寫 `ReadingPositionRepository` 測試（比照 `book_reader_prefs_repository_test.dart` 風格）**

`app/test/reader/reading_position_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepository;
  late ReadingPositionRepository repository;

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = ReadingPositionRepository(libraryRepository.database);
    await libraryRepository.insertBook(Book(
      id: 'b1',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/b1',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('尚未儲存過位置時，load 回傳預設值（皆為 null／progress=0）', () async {
    final position = await repository.load('b1');
    expect(position, const ReadingPosition());
  });

  test('save 寫入 EPUB 定位後，load 讀回相同的值', () async {
    const position = ReadingPosition(
      epubLocatorJson: '{"href":"/chap1.xhtml","locations":{"totalProgression":0.3}}',
      progress: 0.3,
    );

    await repository.save('b1', position);

    expect(await repository.load('b1'), position);
  });

  test('save 寫入 PDF 頁索引後，load 讀回相同的值', () async {
    const position = ReadingPosition(pdfPageIndex: 4, progress: 0.67);

    await repository.save('b1', position);

    expect(await repository.load('b1'), position);
  });

  test('save 覆寫既有位置（同一本書再次呼叫 save）', () async {
    await repository.save('b1', const ReadingPosition(pdfPageIndex: 1, progress: 0.1));
    await repository.save('b1', const ReadingPosition(pdfPageIndex: 5, progress: 0.5));

    final position = await repository.load('b1');
    expect(position.pdfPageIndex, 5);
    expect(position.progress, 0.5);
  });

  test('save 不影響書籍的其餘欄位（partial update，非整列覆寫）', () async {
    await repository.save('b1', const ReadingPosition(pdfPageIndex: 2, progress: 0.2));

    final books = await libraryRepository.listBooks();
    expect(books.single.title, '書名'); // 未被覆寫成任何預設值
  });

  test('對應書籍列不存在時，save 靜默無效果、不拋出例外', () async {
    await expectLater(
      repository.save('不存在的書', const ReadingPosition(pdfPageIndex: 1)),
      completes,
    );
  });
}
```

- [ ] **Step 5：執行測試確認通過**

```bash
cd app && flutter test test/reader/reading_position_repository_test.dart
```

Expected: 全數 PASS。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/reading_position.dart app/lib/reader/reading_position_repository.dart app/test/support/fake_reading_position_repository.dart app/test/reader/reading_position_repository_test.dart
git commit -m "feat(epic-5): 新增 ReadingPosition/ReadingPositionRepository"
```

---

## Task 3：擴大 `ReaderPrefsManager`/`ReaderPrefsManagerImpl`，更新全部呼叫點

**Files:**
- Modify: `app/lib/reader/reader_prefs_manager.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/fake_reader_prefs_manager.dart`
- Modify: `app/test/reader/reader_prefs_manager_test.dart`
- Modify: `app/integration_test/smoke_test.dart`
- Modify: `app/integration_test/reader_screen_test.dart`
- Modify: `app/integration_test/orientation_repagination_test.dart`
- Modify: `app/integration_test/library_screen_test.dart`
- Modify: `app/integration_test/reader_footer_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `ReadingPosition`/`ReadingPositionRepository`。
- Produces：`LoadedPrefs.readingPosition`（`ReadingPosition`，non-null，`load()` 一併回傳）；`ReaderPrefsManager.saveReadingPosition(String bookId, ReadingPosition position) → Future<void>`——供 Task 6 的 `ReaderScreen` 呼叫。

- [ ] **Step 1：`reader_prefs_manager.dart` 擴大 `LoadedPrefs` 與介面**

```dart
import 'book_reader_prefs.dart';
import 'global_reader_prefs.dart';
import 'reading_position.dart';
import 'resolved_preferences.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager.load] 回傳的「尚未解析」原始資料：單書覆寫值
/// （[BookReaderPrefs]，可能大部分欄位是 null）、全域預設值（
/// [GlobalReaderPrefs]，non-nullable）與本機閱讀位置（[readingPosition]，
/// epic-5-toc-pagination Issue 2 新增，non-nullable——無記錄時為
/// `ReadingPosition()` 預設值）。呼叫端把這個物件連同（若有）自動偵測到
/// 的排版方向一起交給 [ReaderPrefsManager.resolve]（純同步函式）求出最終
/// 生效值，兩者刻意分離：`load` 是唯一需要 async 的地方，`resolve` 可在
/// 任何時機（含原生 layout 解析完成的同步回呼內）重複呼叫而不必再等一次
/// 儲存層 I/O。
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;
  final ReadingPosition readingPosition;

  const LoadedPrefs({
    required this.bookPrefs,
    required this.globalPrefs,
    this.readingPosition = const ReadingPosition(),
  });
}

/// 偏好設定與本機閱讀位置的載入／持久化／解析深模組，取代 `ReaderScreen`
/// 原本直接依賴 `BookReaderPrefsRepository`（SQLite）與 `GlobalReaderDefaults`
/// （SharedPreferences）兩條路徑的做法。
abstract class ReaderPrefsManager {
  /// 一次載入單書覆寫值、全域預設值與本機閱讀位置（原本 `ReaderScreen.initState`
  /// 裡 3 個平行 Future 中的 2 個，見 Task 3；epic-5-toc-pagination Issue 2
  /// 新增第 3 個平行讀取）。
  Future<LoadedPrefs> load(String bookId);

  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs);
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs);

  /// 寫入本機閱讀位置（epic-5-toc-pagination Issue 2）。呼叫時機固定為
  /// `ReaderScreen.dispose()` 與 App 進入背景時各一次，不逐次翻頁/捲動
  /// 呼叫（見 docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置
  /// 記憶」）。
  Future<void> saveReadingPosition(String bookId, ReadingPosition position);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
  /// I/O，可在同一個 `setState` 內依需要重複呼叫（例如原生 layout 解析
  /// 完成後才拿到 [autoDetectedWritingMode]，需要重新求值）。
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  });
}
```

- [ ] **Step 2：`reader_prefs_manager_impl.dart` 注入 `ReadingPositionRepository`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'global_reader_prefs.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_fit_mode.dart';
import 'reader_prefs_manager.dart';
import 'reading_position.dart';
import 'reading_position_repository.dart';
import 'resolved_preferences.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager] 的正式實作。直接內建全域預設值的 SharedPreferences
/// 讀寫邏輯（吸收原 `GlobalReaderDefaults` 的職責，鍵名沿用不變以保留既有
/// 使用者資料），不把它當成注入依賴——這樣 `global_reader_defaults.dart`
/// 才能在完成遷移後被真正刪除，不會卡在「還有人依賴它」的狀態。
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;
  final ReadingPositionRepository _positionRepository;

  const ReaderPrefsManagerImpl(this._sqliteRepository, this._positionRepository);

  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';

  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      _loadGlobalPrefs(),
      _positionRepository.load(bookId),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
    );
  }

  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
    );
  }

  T? _readEnum<T extends Enum>(
    SharedPreferences sp,
    String key,
    List<T> values,
  ) {
    final raw = sp.getString(key);
    if (raw == null) return null;
    try {
      return values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) =>
      _sqliteRepository.save(bookId, prefs);

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) =>
      _positionRepository.save(bookId, position);

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) {
    final book = loaded.bookPrefs;
    final global = loaded.globalPrefs;
    return ResolvedPreferences(
      writingMode: book.writingModeOverride ?? autoDetectedWritingMode,
      fontFamily: book.fontFamily,
      fontSize: book.fontSize,
      fontWeight: book.fontWeight,
      lineHeight: book.lineHeight,
      paragraphSpacing: book.paragraphSpacing,
      pageMargins: book.pageMargins,
      textAlign: book.textAlign,
      publisherStyles: book.publisherStyles,
      pageTurnMode: book.pageTurnModeOverride ?? global.pageTurnMode,
      screenOrientation:
          book.screenOrientationOverride ?? global.screenOrientation,
      pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit,
      pdfContrast: book.pdfContrast ?? 0,
      pdfBrightness: book.pdfBrightness ?? 0,
      pdfBoldStrength: book.pdfBoldStrength ?? 0,
      pdfCropMode: book.pdfCropMode ?? PdfCropMode.none,
      pdfCropRect: book.pdfCropRect,
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
    );
  }
}
```

- [ ] **Step 3：更新 `main.dart` 唯一的正式建構呼叫點**

`app/lib/main.dart` 修改：

```dart
import 'reader/reading_position_repository.dart';
```

（加在既有 `import 'reader/reader_prefs_manager_impl.dart';` 之後）並把：

```dart
  final prefsManager = ReaderPrefsManagerImpl(prefsRepository);
```

改為：

```dart
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
```

- [ ] **Step 4：更新 `fake_reader_prefs_manager.dart`**

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'fake_book_reader_prefs_repository.dart';
import 'fake_reading_position_repository.dart';

/// 供 `reader_screen_test.dart` 使用的假 [ReaderPrefsManager]：`load`／
/// `save*` 皆為純記憶體內操作；`resolve` 直接委派給
/// [ReaderPrefsManagerImpl.resolve]（純函式、無 I/O，不需要另外假造）以
/// 確保測試驗證的合併邏輯與正式實作完全一致。
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  final Map<String, ReadingPosition> readingPositionByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];
  final List<MapEntry<String, ReadingPosition>> savedReadingPositionCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    Map<String, ReadingPosition>? readingPositionByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  })  : bookPrefsByBookId = bookPrefsByBookId ?? {},
        readingPositionByBookId = readingPositionByBookId ?? {};

  final _delegate = ReaderPrefsManagerImpl(
    FakeBookReaderPrefsRepository(),
    FakeReadingPositionRepository(),
  );

  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? BookReaderPrefs.empty,
      globalPrefs: globalPrefs,
      readingPosition:
          readingPositionByBookId[bookId] ?? const ReadingPosition(),
    );
  }

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) async {
    bookPrefsByBookId[bookId] = prefs;
    savedBookPrefsCalls.add(bookId);
  }

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    globalPrefs = prefs;
    savedGlobalPrefsCalls.add(prefs);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) async {
    readingPositionByBookId[bookId] = position;
    savedReadingPositionCalls.add(MapEntry(bookId, position));
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) =>
      _delegate.resolve(loaded, autoDetectedWritingMode: autoDetectedWritingMode);
}
```

- [ ] **Step 5：更新 `reader_prefs_manager_test.dart` 的 2 個建構呼叫點 + 新增位置讀寫測試**

第一個 `setUp`（純同步 `resolve()` 測試群組）：

```dart
    setUp(() {
      manager = ReaderPrefsManagerImpl(
        FakeBookReaderPrefsRepository(),
        FakeReadingPositionRepository(),
      );
    });
```

（檔案頂部 import 區塊新增 `import '../support/fake_reading_position_repository.dart';`）

第二個 `setUp`（`load()` async 測試群組）：

```dart
      manager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
```

（檔案頂部 import 區塊新增 `import 'package:elinkbook/reader/reading_position.dart';` 與 `import 'package:elinkbook/reader/reading_position_repository.dart';`）

在 `load()` group 最後新增 2 個測試：

```dart
    test('尚未儲存過位置時，load 回傳 ReadingPosition() 預設值', () async {
      final loaded = await manager.load('b1');
      expect(loaded.readingPosition, const ReadingPosition());
    });

    test('saveReadingPosition 寫入後，load 讀回相同的位置', () async {
      const position = ReadingPosition(pdfPageIndex: 3, progress: 0.5);
      await manager.saveReadingPosition('b1', position);
      final loaded = await manager.load('b1');
      expect(loaded.readingPosition, position);
    });
```

- [ ] **Step 6：更新 5 個 integration_test 呼叫點（機械式，皆為同一種修改）**

以下 5 個檔案內，把：

```dart
    prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
    );
```

（或 `library_screen_test.dart` 內對應的 `repository.database` 版本）改為：

```dart
    prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
```

並在檔案頂部新增 `import 'package:elinkbook/reader/reading_position_repository.dart';`：

1. `app/integration_test/smoke_test.dart:28-30`
2. `app/integration_test/reader_screen_test.dart:97-99`
3. `app/integration_test/orientation_repagination_test.dart:68-70`
4. `app/integration_test/reader_footer_test.dart:31-33`（注意此處是 `final prefsManager = ReaderPrefsManagerImpl(...)`，非賦值給既有變數）
5. `app/integration_test/library_screen_test.dart:94-96`（此處是內嵌在 `prefsManager: ReaderPrefsManagerImpl(...)` 的具名參數位置，改為 `prefsManager: ReaderPrefsManagerImpl(BookReaderPrefsRepository(repository.database), ReadingPositionRepository(repository.database))`）

- [ ] **Step 7：執行純 Dart 測試確認通過（integration_test 留待 Task 8 真機驗證）**

```bash
cd app && flutter test
```

Expected: 全數 PASS（不含 integration_test，那些需要真機/模擬器，此步驟只驗證編譯與純 Dart 測試邏輯正確）。

```bash
cd app && flutter analyze
```

Expected: `No issues found!`（含 integration_test 目錄的靜態分析，確認 Step 6 的機械式修改沒有型別錯誤）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/reader_prefs_manager.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/main.dart app/test/support/fake_reader_prefs_manager.dart app/test/reader/reader_prefs_manager_test.dart app/integration_test/smoke_test.dart app/integration_test/reader_screen_test.dart app/integration_test/orientation_repagination_test.dart app/integration_test/library_screen_test.dart app/integration_test/reader_footer_test.dart
git commit -m "feat(epic-5): ReaderPrefsManager 擴大涵蓋本機閱讀位置讀寫"
```

---

## Task 4：PDF 原生端 + Dart 端：開書時讀取起始頁索引

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：無新依賴。
- Produces：`PdfReaderView(initialPageIndex: int?)`——供 Task 6 的 `ReaderScreen` 傳入。

- [ ] **Step 1：`PdfReaderView.kt` 的 `onMethodCall`／`openBook` 讀取 `initialPageIndex`**

`onMethodCall` 的 `"openBook"` 分支（約第 286-292 行）改為：

```kotlin
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                    call.argument<Int>("initialPageIndex"),
                )
                result.success(null)
            }
```

`openBook()` 簽章與內部初始化（約第 421-457 行）改為：

```kotlin
    private fun openBook(
        path: String?,
        initialPreferences: Map<String, Any?>?,
        initialPageIndex: Int?,
    ) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = PdfCropMode.fromWireValue(it) }
        parseCropRect(initialPreferences?.get("cropRect"))?.let { cropRect = it }
        if (initialPreferences != null) applyDualPagePreferences(initialPreferences)
        var pfd: ParcelFileDescriptor? = null
        try {
            pfd = openParcelFileDescriptor(path)
            if (pfd == null) {
                channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                return
            }
            renderer = PdfRenderer(pfd)
            totalPages = renderer!!.pageCount
            // epic-5-toc-pagination Issue 2：若有既有位置記錄且落在有效範圍
            // 內，以此為起始頁；否則（首次開書、記錄超出範圍）固定從頭開始，
            // 比照既有 jumpToPage() 的邊界檢查風格。
            currentPageIndex =
                if (initialPageIndex != null && initialPageIndex in 0 until totalPages) {
                    initialPageIndex
                } else {
                    0
                }
            renderCurrentSpread()
            channel.invokeMethod("onPageRendered", null)
            // Epic 5 Issue 1：開書完成當下立即回報一次初始頁碼狀態，讓
            // Dart 端（ReaderFooter）不需要等到第一次翻頁才知道總頁數。
            notifyPageChanged()
        } catch (e: OutOfMemoryError) {
            channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
        } catch (e: Exception) {
            channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
        } finally {
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }
```

- [ ] **Step 2：`pdf_reader_view.dart` 新增 `initialPageIndex` 建構參數**

`PdfReaderView` class 新增欄位（緊接 `final bool isLandscape;` 之後）：

```dart
  final bool isLandscape;

  /// 開書起始頁索引（0-indexed，epic-5-toc-pagination Issue 2）。`null`
  /// 代表無既有位置記錄，固定從頭開始——與其餘偏好參數不同，這是「一次性
  /// 開書起始值」，只在 `openBook` 當下送出一次，不參與
  /// [didUpdateWidget] 的偏好設定 diff 邏輯（見 Global Constraints）。
  final int? initialPageIndex;
```

建構子新增對應具名參數：

```dart
  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
    this.onCropRectSelected,
    this.dualPageMode = DualPageMode.auto,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.rtl,
    this.isLandscape = false,
    this.initialPageIndex,
  });
```

`_onPlatformViewCreated` 改為：

```dart
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
      if (widget.initialPageIndex != null)
        'initialPageIndex': widget.initialPageIndex,
    });
  }
```

- [ ] **Step 3：撰寫 widget test（比照既有 `_pumpPdfReaderView` 模式）**

在 `pdf_reader_view_test.dart` 的最後一個 `testWidgets`（`jumpToPage` 測試）之後新增：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPageIndex 非 null 時正確帶入',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        initialPageIndex: 4,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPageIndex'], 4);
  });

  testWidgets('initialPageIndex 為 null 時，openBook 的 arguments 不包含該 key',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments as Map<Object?, Object?>)
          .containsKey('initialPageIndex'),
      isFalse,
    );
  });
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd app && flutter test test/reader/pdf_reader_view_test.dart
```

Expected: 全數 PASS。

- [ ] **Step 5：Kotlin 端編譯確認（無自動化測試框架，僅確認建置成功）**

```bash
cd app && flutter build apk --debug
```

Expected: BUILD SUCCESSFUL。

- [ ] **Step 6：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-5): PdfReaderView 支援 initialPageIndex 開書起始頁"
```

---

## Task 5：EPUB 原生端 + Dart 端：位置追蹤（`onPageChanged` 死程式碼填入實作）+ 開書起始定位

**Files:**
- Create: `app/lib/reader/epub_position_info.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Modify: `app/lib/reader/epub_reader_view.dart`
- Test: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes：Readium `Locator.toJSON(): JSONObject`／`Locator.Companion.fromJSON(JSONObject, WarningLogger?): Locator?`（已透過 javap 反編譯 `readium-shared-3.3.0-runtime.jar` 確認存在，`Locator implements JSONable`）；`Locator.locations.totalProgression: Double?`（已確認存在於 `Locator.Locations`）。
- Produces：`EpubPositionInfo(locatorJson: String, progression: double?)`；`EpubReaderView(initialLocatorJson: String?, onLocatorChanged: ValueChanged<EpubPositionInfo>?)`——供 Task 6 的 `ReaderScreen` 使用。

- [ ] **Step 1：建立 `EpubPositionInfo` 值物件（比照 `PdfPageInfo` 風格）**

`app/lib/reader/epub_position_info.dart`：

```dart
/// [EpubReaderView] 目前定位變動時（開書完成、翻頁、跳轉）一次性回報的
/// 位置資訊（epic-5-toc-pagination Issue 2）。[locatorJson] 是原生端
/// `Locator.toJSON().toString()` 的原樣字串，Dart 端不解析其內部結構、
/// 只負責持久化與之後原樣傳回原生端還原（`Locator.fromJSON`）；
/// [progression] 是原生端額外拆出的 `Locator.locations.totalProgression`
/// 平面數值，供 Dart 端直接用於 `Book.progress` 而不需要自行解析
/// [locatorJson] 的巢狀 JSON 結構。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(locatorJson, progression);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression)';
}
```

- [ ] **Step 2：`EpubReaderView.kt` 新增 `org.json.JSONObject` import**

在既有 import 區塊（第 34 行 `import org.readium.r2.shared.publication.Locator` 之後）新增：

```kotlin
import org.json.JSONObject
```

- [ ] **Step 3：`onMethodCall`／`openBook`／`attachNavigator` 讀取並套用 `initialLocatorJson`**

`onMethodCall` 的 `"openBook"` 分支（約第 154-161 行）改為：

```kotlin
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                    call.argument<String>("initialLocatorJson"),
                )
                result.success(null)
            }
```

`openBook()` 簽章（約第 591 行）改為：

```kotlin
    private fun openBook(
        path: String?,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
    ) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val resolvedUrl = resolveAbsoluteUrl(path)
                if (resolvedUrl == null) {
                    channel.invokeMethod("onError", "無法解析檔案路徑或 URI：$path")
                    return@launch
                }
                val asset = assetRetriever.retrieve(resolvedUrl).getOrElse {
                    channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val openedPublication = publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                    channel.invokeMethod("onError", "無法解析 EPUB 檔案：${it.message}")
                    return@launch
                }
                if (isDisposed) {
                    openedPublication.close()
                    return@launch
                }
                attachNavigator(openedPublication, initialPreferences, initialLocatorJson)
            } catch (e: Exception) {
                channel.invokeMethod("onError", "開啟 EPUB 檔案時發生未預期的錯誤：${e.message}")
            }
        }
    }
```

（僅新增 `initialLocatorJson` 參數並在 `attachNavigator(...)` 呼叫處多傳一個引數，其餘內容逐字不變，故上方完整列出以避免與既有程式碼合併時漏改。）

`attachNavigator()`（約第 641 行）改為：

```kotlin
    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
    ) {
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            // epic-5-toc-pagination Issue 2：若有既有位置記錄，解析回
            // Locator 作為起始定位；解析失敗（理論上不應發生——這個字串
            // 只會是我們自己 onPageChanged() 寫出的 Locator.toJSON()
            // 結果）會拋出例外，交由下方既有的 catch (e: Exception) 統一
            // 攔截並回報 onError，不特別加防禦性 try/catch。
            val initialLocator = initialLocatorJson?.let {
                Locator.fromJSON(JSONObject(it))
            }
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = initialLocator,
                listener = this,
                paginationListener = this,
                configuration = buildFontFamiliesConfiguration(),
            )
            installedFragmentFactory = fragmentFactory
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
        } catch (e: Exception) {
            publication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }
```

- [ ] **Step 4：填入 `onPageChanged` 死程式碼實作，推送位置給 Dart**

把（約第 706 行）：

```kotlin
    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {}
```

改為：

```kotlin
    /**
     * epic-5-toc-pagination Issue 2：填入原本永遠不會被呼叫的死程式碼
     * （spec.md User Story 21）。Readium 每次目前定位變動（開書、翻頁、
     * 目錄跳轉）時呼叫本方法；這裡不直接寫資料庫（寫入時機固定為
     * ReaderScreen.dispose()／App 進入背景，見 spec.md「本機閱讀位置
     * 記憶」），只把目前定位推送給 Dart 端快取於記憶體中，等寫入時機到
     * 達時才由 Dart 端讀取快取值寫入資料庫。
     */
    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        channel.invokeMethod(
            "onLocatorChanged",
            mapOf(
                "locatorJson" to locator.toJSON().toString(),
                "progression" to locator.locations.totalProgression,
            ),
        )
    }
```

- [ ] **Step 5：`epub_reader_view.dart` 新增 `initialLocatorJson`／`onLocatorChanged`**

在 import 區塊新增：

```dart
import 'epub_position_info.dart';
```

`EpubReaderView` class 新增欄位（緊接 `final bool isLandscape;` 之後）：

```dart
  final bool isLandscape;

  /// 開書起始定位（序列化後的 Readium Locator，epic-5-toc-pagination
  /// Issue 2）。`null` 代表無既有位置記錄，固定從書本開頭開始——與其餘
  /// 偏好參數不同，這是「一次性開書起始值」，只在 `openBook` 當下送出
  /// 一次，不參與 [didUpdateWidget] 的偏好設定 diff 邏輯（見 Global
  /// Constraints）。
  final String? initialLocatorJson;

  /// 目前定位變動時觸發（開書、翻頁、目錄跳轉），供呼叫端（ReaderScreen）
  /// 快取最新定位，於離開/背景時寫入資料庫。
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;
```

建構子新增對應具名參數：

```dart
  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.dualPageMode = DualPageMode.auto,
    this.isLandscape = false,
    this.onToggleFixedLayoutControls,
    this.onFixedLayoutPageTurn,
    this.initialLocatorJson,
    this.onLocatorChanged,
  });
```

`_onPlatformViewCreated` 改為：

```dart
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
      if (widget.initialLocatorJson != null)
        'initialLocatorJson': widget.initialLocatorJson,
    });
  }
```

`_handleMethodCall` 的 `switch` 新增一個 case（緊接既有 `'onLayoutResolved'` 分支之後）：

```dart
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
        ));
        break;
```

- [ ] **Step 6：撰寫 widget test（比照 `pdf_reader_view_test.dart` 的既有模式）**

先讀取 `epub_reader_view_test.dart` 既有的 `_pumpEpubReaderView` helper 簽章與 import，沿用同一支 helper（不重新定義）。在檔案最後新增：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialLocatorJson 非 null 時正確帶入',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        initialLocatorJson: '{"href":"/chap1.xhtml"}',
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialLocatorJson'], '{"href":"/chap1.xhtml"}');
  });

  testWidgets('initialLocatorJson 為 null 時，openBook 的 arguments 不包含該 key',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments as Map<Object?, Object?>)
          .containsKey('initialLocatorJson'),
      isFalse,
    );
  });

  testWidgets('收到原生端 onLocatorChanged 事件時正確解析 EpubPositionInfo',
      (tester) async {
    EpubPositionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onLocatorChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onLocatorChanged', {
      'locatorJson': '{"href":"/chap2.xhtml"}',
      'progression': 0.35,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(
      received,
      const EpubPositionInfo(
        locatorJson: '{"href":"/chap2.xhtml"}',
        progression: 0.35,
      ),
    );
  });
```

（已確認 `epub_reader_view_test.dart:19-22` 既有的 `_pumpEpubReaderView(WidgetTester tester, EpubReaderView widget) async → Future<List<MethodCall>>` 簽章與上方測試碼完全相容，可直接沿用。）

- [ ] **Step 7：執行測試確認通過**

```bash
cd app && flutter test test/reader/epub_reader_view_test.dart
```

Expected: 全數 PASS。

- [ ] **Step 8：Kotlin 端編譯確認**

```bash
cd app && flutter build apk --debug
```

Expected: BUILD SUCCESSFUL（確認 `org.json.JSONObject` import 與 `Locator.fromJSON`/`toJSON()` 呼叫皆能正確編譯連結）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/reader/epub_position_info.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-5): EpubReaderView 填入 onPageChanged 實作，支援位置追蹤與起始定位"
```

---

## Task 6：`ReaderScreen` 整合——初始位置傳入、持續追蹤、離開/背景寫入

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `LoadedPrefs.readingPosition`／`ReaderPrefsManager.saveReadingPosition`；Task 4 的 `PdfReaderView.initialPageIndex`；Task 5 的 `EpubReaderView.initialLocatorJson`／`onLocatorChanged`／`EpubPositionInfo`。
- Produces：無新公開介面（`ReaderScreen` 建構子不變，見 Global Constraints）。

- [ ] **Step 1：新增 import、`WidgetsBindingObserver` mixin 與新的 state 欄位**

`reader_screen.dart` 頂部新增 import：

```dart
import '../reader/epub_position_info.dart';
import '../reader/reading_position.dart';
```

`_ReaderScreenState` 宣告改為：

```dart
class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
```

在既有欄位區塊（`_pdfPageInfo` 之後）新增：

```dart
  // PDF 目前頁碼/總頁數狀態，由 PdfReaderView.onPageChanged 回報驅動頁尾
  // 顯示（Epic 5 Issue 1）。EPUB 讀取畫面本 issue 不使用此欄位。
  PdfPageInfo? _pdfPageInfo;
  // EPUB 目前定位狀態，由 EpubReaderView.onLocatorChanged 回報（Epic 5
  // Issue 2）。寫入本機資料庫時讀取此欄位的最新值，比照 _pdfPageInfo
  // 對 PDF 的既有作法。
  EpubPositionInfo? _epubPositionInfo;
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
  // 不變——僅用於 _buildNativeView() 建構 EpubReaderView/PdfReaderView
  // 時傳入 initialLocatorJson/initialPageIndex 這兩個一次性開書起始值。
  ReadingPosition? _initialPosition;
```

- [ ] **Step 2：`initState` 讀取 `readingPosition`、註冊 lifecycle observer**

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
      _applyScreenOrientation();
    });
  }
```

- [ ] **Step 3：`dispose()` 移除 observer 並觸發寫入；新增 `didChangeAppLifecycleState`**

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 離開閱讀畫面時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
    // 時機之一）。不 await——dispose() 是同步方法，且這是離開畫面前的
    // 最後一次呼叫，不需要等待其完成，比照既有 _handlePrefsChanged 不
    // await saveBookPrefs 的既有慣例。
    _writeCurrentPosition();
    // 還原系統預設（允許自由旋轉），不論進入閱讀器時鎖定了哪個角度，比照
    // 音量鍵離開閱讀介面後恢復正常系統音量控制的既有處理原則，避免鎖定
    // 狀態外溢到書架等其他畫面。
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// App 進入背景時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
  /// 時機之二）。只在 [AppLifecycleState.paused]（真正進入背景）觸發，
  /// 不含 [AppLifecycleState.inactive]（如系統對話框短暫遮蓋等過渡狀態）
  /// ——避免非真正離開情境也觸發資料庫寫入。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _writeCurrentPosition();
    }
  }

  /// 依目前格式讀取對應的持續追蹤狀態（PDF: [_pdfPageInfo]，EPUB:
  /// [_epubPositionInfo]），組成 [ReadingPosition] 後透過 prefsManager
  /// 寫入。尚未收到任何位置回報（例如書籍尚未成功開啟）時靜默不寫入，
  /// 避免用「無資料」覆蓋掉資料庫中既有的正確記錄。
  void _writeCurrentPosition() {
    final format = detectBookFormat(widget.filePath);
    switch (format) {
      case BookFormat.pdf:
        final info = _pdfPageInfo;
        if (info == null) return;
        widget.prefsManager.saveReadingPosition(
          widget.bookId,
          ReadingPosition(
            pdfPageIndex: info.pageIndex,
            progress: info.totalPages > 0
                ? (info.pageIndex + 1) / info.totalPages
                : 0,
          ),
        );
        break;
      case BookFormat.epub:
        final info = _epubPositionInfo;
        if (info == null) return;
        widget.prefsManager.saveReadingPosition(
          widget.bookId,
          ReadingPosition(
            epubLocatorJson: info.locatorJson,
            progress: info.progression ?? 0,
          ),
        );
        break;
      case BookFormat.unknown:
        return;
    }
  }
```

- [ ] **Step 4：`_buildNativeView()` 傳入起始位置、接上持續追蹤 callback**

`EpubReaderView(...)` 建構呼叫新增 2 個具名參數（緊接既有 `onFixedLayoutPageTurn` 之後）：

```dart
          onFixedLayoutPageTurn: () =>
              setState(() => _fixedLayoutControlsVisible = false),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            _epubPositionInfo = info;
          },
        );
```

（`onLocatorChanged` 刻意不呼叫 `setState`——與 `_pdfPageInfo` 的既有寫法不同：`_pdfPageInfo` 需要 `setState` 是因為它會驅動頁尾 UI 重繪顯示頁碼；`_epubPositionInfo` 目前只作為寫入時的內部快取，EPUB 分支本 issue 不接頁尾（Issue 5 才處理頁尾），沒有任何畫面需要因此重繪，用 `setState` 只會造成不必要的 rebuild。）

`PdfReaderView(...)` 建構呼叫新增 1 個具名參數（緊接既有 `key: _pdfReaderViewKey` 之後）：

```dart
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
```

- [ ] **Step 5：撰寫 widget test——驗證 dispose 時呼叫 `saveReadingPosition`（PDF 分支，唯一可在純 widget test 環境驗證的路徑）**

在 `reader_screen_test.dart` 新增（檔案頂部需要的 import：`package:flutter/services.dart` 已存在；新增 `package:elinkbook/reader/reading_position.dart`）：

```dart
  testWidgets('PDF 收到 onPageChanged 後離開畫面（dispose），正確寫入 ReadingPosition',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;
    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_dispose_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 模擬原生端回報 onPageChanged（比照既有 pdf_reader_view_test.dart
    // 對 onPageChanged 的模擬方式）。
    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onPageChanged', {
      'pageIndex': 3,
      'totalPages': 10,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});
    await tester.pump();

    // 導覽離開 ReaderScreen，觸發 dispose()。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(prefsManager.savedReadingPositionCalls, hasLength(1));
    final saved = prefsManager.savedReadingPositionCalls.single;
    expect(saved.key, 'b_dispose_test');
    expect(saved.value.pdfPageIndex, 3);
    expect(saved.value.progress, 0.4); // (3+1)/10
  });

  testWidgets('尚未收到任何 onPageChanged 時，dispose 不呼叫 saveReadingPosition（避免覆寫既有記錄）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_no_position',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(prefsManager.savedReadingPositionCalls, isEmpty);
  });
```

（EPUB 分支與「App 進入背景」路徑因涉及真實 `AndroidView` 渲染或 `WidgetsBinding` 全域生命週期事件，比照 Issue 1 已記錄的既有限制，改由 Task 8 的真機 `integration_test` 驗證，此處不勉強寫會員誤導性斷言的假測試。）

- [ ] **Step 6：執行測試確認通過**

```bash
cd app && flutter test test/screens/reader_screen_test.dart
```

Expected: 全數 PASS（含新增的 2 個測試）。

```bash
cd app && flutter test
```

Expected: 全數 PASS。

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-5): ReaderScreen 整合本機閱讀位置記憶（開書起始位置、離開/背景寫入）"
```

---

## Task 7：`LibraryScreen` 返回時重新載入書籍清單（審查修正——防止過期資料覆寫最新進度）

**背景（`/superpowers:requesting-code-review` 審查報告 Critical 2）：** `LibraryScreen._openBook()` 目前用 `Navigator.of(context).push(...)`（未 `await`／未接 `.then()`）導覽至 `ReaderScreen`，回到書架後 `_books` 仍是進入閱讀器「之前」載入的舊 `Book` 物件快照（`progress`/`epubLocator`/`pdfPageIndex` 皆為進入前的舊值）。若使用者接著在書架上執行「移動到分類」（`_moveSelectedBooksToGroup()`），該方法對這個舊 `Book` 物件呼叫 `book.copyWith(groupName: destination)` 後整列 `updateBook()`——`Book.copyWith()` 對未明確覆寫的欄位一律沿用舊值，因此剛剛在 `ReaderScreen.dispose()`/背景寫入時透過 `ReadingPositionRepository` partial update 寫入的最新 `progress`/`epubLocator`/`pdfPageIndex` 會被這個整列 `UPDATE` 直接覆蓋回舊值，造成資料遺失。已透過直接閱讀 `library_screen.dart:253-283` 確認此路徑真實存在、`_openBook()` 目前確實未在返回後呼叫 `_loadBooks()`。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1-6 完成後，`ReadingPositionRepository`/`ReaderPrefsManager.saveReadingPosition` 已會在 `ReaderScreen.dispose()` 時寫入 `books` 表。
- Produces：無新公開介面，純內部行為修正。

- [ ] **Step 1：`_openBook()` 於返回後重新載入書籍清單**

`app/lib/screens/library_screen.dart` 的 `_openBook()`（約第 273-283 行）改為：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
            ),
          ),
        )
        .then((_) {
      // 【審查修正】ReaderScreen 內離開/背景時會把最新閱讀進度與定位寫入
      // 資料庫（見 Task 6），但 _books 這份記憶體快照不會自動跟著更新。
      // 若不在此重新載入，_books 仍持有進入閱讀器前的舊 Book 物件；之後
      // 任何以 _books 為來源的整列 updateBook()（例如
      // _moveSelectedBooksToGroup()）會用舊值覆蓋掉剛剛寫入的最新進度，
      // 造成資料遺失（`/superpowers:requesting-code-review` Critical 2）。
      // 這裡不檢查 mounted——_loadBooks() 內部已有等效保護（見其既有實作）。
      _loadBooks();
    });
  }
```

- [ ] **Step 2：撰寫 widget test，驗證返回書架後清單確實重新載入**

在 `library_screen_test.dart` 新增（緊接既有「有書籍時，書架 grid 呈現正確渲染書籍項目」測試之後即可）：

```dart
  testWidgets('從閱讀器返回書架時，重新載入書籍清單，避免後續操作以過期資料覆寫最新進度',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // widget test 環境無法真正渲染原生 PlatformView 觸發 ReaderScreen 的
    // 位置寫入路徑，這裡直接呼叫 repository.updateBook 模擬「ReaderScreen
    // 已透過 ReadingPositionRepository 把最新進度寫入資料庫」這個結果
    // （見 Critical 2 審查意見的觸發情境）。
    await repository.updateBook(Book(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      format: BookFileFormat.epub,
      filePath: 'content://example/1.epub',
      source: BookSource.local,
      progress: 0.5,
      groupName: BookGroup.uncategorized,
      createTime: book.createTime,
      lastReadTime: book.lastReadTime,
    ));

    // 返回書架（點擊 ReaderScreen AppBar 的預設返回鍵，等同
    // Navigator.pop()）。
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget,
        reason: '返回書架後應重新載入書籍清單，顯示閱讀器寫入的最新進度，'
            '而非停留在舊快照的 0%');
  });
```

- [ ] **Step 3：執行測試確認通過**

```bash
cd app && flutter test test/screens/library_screen_test.dart
```

Expected: 全數 PASS（含新增的 1 個測試）。

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "fix(epic-5): LibraryScreen 返回閱讀器後重新載入書籍清單，避免舊快照覆寫最新進度"
```

---

## Task 8：真機整合測試——端到端「開書 → 翻頁 → 離開/背景 → 重開 → 驗證回到同一位置」

**Files:**
- Create: `app/integration_test/reading_position_test.dart`

**Interfaces:**
- Consumes：Task 1-7 全部完成後的完整功能。

- [ ] **Step 1：撰寫 PDF 端到端測試（開書→跳頁→pop 觸發 dispose→重開→驗證起始頁）**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDF：開書→跳頁→離開畫面→重開同一本書，自動回到離開前頁碼',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_dual_page.pdf', 'position_pdf_integration.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_position_pdf',
      title: '位置記憶測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 第一次開書，跳到第 4 頁。
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_position_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('進度 67% ｜ 第 4/6 頁'), findsOneWidget);

    // 離開閱讀畫面（觸發 dispose），驗證資料庫已寫入。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    final saved = await ReadingPositionRepository(libraryRepository.database)
        .load('b_position_pdf');
    expect(saved.pdfPageIndex, 3); // 0-indexed

    // 重新開啟同一本書，驗證自動回到第 4 頁（起始畫面即顯示，不需再跳頁）。
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_position_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.text('進度 67% ｜ 第 4/6 頁'), findsOneWidget,
        reason: '重新開啟同一本書應自動回到離開前的頁碼');
  });
}
```

- [ ] **Step 2：撰寫 EPUB 端到端測試（開書→實際翻頁→背景生命週期事件→重開→驗證非起始定位）**

在同一檔案 `main()` 內新增第二個 `testWidgets`：

```dart
  testWidgets('EPUB：開書→翻頁→App 進入背景→重開同一本書，自動回到離開前定位',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'position_epub_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_position_epub',
      title: '位置記憶測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_position_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    // 實際翻頁若干次，讓定位遠離書本開頭（比照既有測試以手勢滑動翻頁，
    // 見 orientation_repagination_test.dart 既有慣例）。
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(AndroidView), const Offset(-300, 0));
      await tester.pumpAndSettle();
    }

    // 模擬 App 進入背景（觸發 didChangeAppLifecycleState(paused)），驗證
    // 資料庫已寫入非空的 epubLocator。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final saved = await ReadingPositionRepository(libraryRepository.database)
        .load('b_position_epub');
    expect(saved.epubLocatorJson, isNotNull);
    final firstLocator = saved.epubLocatorJson!;

    // 回到前景、離開畫面，重新開啟同一本書。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_position_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    // 重開後、使用者尚未再翻頁時，資料庫中的定位應維持與離開前一致（尚未
    // 觸發任何新的 onLocatorChanged 覆寫舊值）。
    final afterReopen = await ReadingPositionRepository(libraryRepository.database)
        .load('b_position_epub');
    expect(afterReopen.epubLocatorJson, firstLocator);
  });
```

- [ ] **Step 3：真機執行確認通過**

```bash
cd app && flutter test integration_test/reading_position_test.dart -d <device-id>
```

Expected: `All tests passed!`（`<device-id>` 由 `flutter devices` 取得，實際執行由人類在真實裝置/模擬器上進行，比照 Issue 1 既有慣例——AI agent 無法直接操作實體裝置）。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/reading_position_test.dart
git commit -m "test(epic-5): 新增 Issue 2 端到端真機整合測試（PDF/EPUB 位置記憶）"
```

---

## 收尾：更新 `issues.md`

- [ ] **Step 1：實作完成、測試皆通過後，將 `docs/epics/epic-5-toc-pagination/issues.md` 的 Issue 2 狀態與驗收標準 checkbox 更新**

比照 Issue 1 的既有模式：`Status` 改為 `✅ 已完成`（若真機測試尚未實際執行，加註「待真機驗證」，等使用者確認執行結果後再拿掉這段措辭），並勾選對應完成的驗收標準 checkbox。此步驟依專案 SDD 工作流程，需等待人類確認測試實際執行結果後才進行，不在本計劃的自動化 Task 範圍內。

---

## 審查修正紀錄（`tmp/epic-5/reviews/plan-issue-2-review.md`）

- **Critical 1（確認屬實，已修正）**：Task 1 Step 2 的 `onUpgrade` 沿用既有程式碼裡「`oldVersion < 2` 分支建立 `book_reader_prefs` 後立即 `return`」的寫法，對既有的 `book_reader_prefs` 遷移而言無害，但會連帶跳過本 Issue 新增、作用於**另一張表**（`books`）的 `oldVersion < 5` 遷移——version 1 裝置跳級升級到 version 5 時會漏執行 `_addReadingPositionColumns`，實際讀寫 `epubLocator`/`pdfPageIndex` 時拋出 `no such column` 崩潰。已改為 `if (oldVersion < 2) {...} else { if (oldVersion < 3) {...}; if (oldVersion < 4) {...} }`，並把 `if (oldVersion < 5)` 移到 if/else 區塊外、無條件檢查，確保任何舊版本跳級升級都會執行到 `books` 表的遷移。
- **Critical 2（確認屬實，已修正）**：`LibraryScreen._openBook()` 原計劃未變動，但審查指出 `Navigator.push(...)` 未接返回後的重載，導致 `_books` 停留在進入閱讀器前的舊快照；若使用者返回後執行「移動到分類」等以 `_books` 為來源的整列 `updateBook()` 操作，會用舊值覆蓋掉 `ReaderScreen` 剛寫入的最新 `progress`/`epubLocator`/`pdfPageIndex`，造成資料遺失。已透過直接閱讀 `library_screen.dart:253-283`（`_openBook`／`_moveSelectedBooksToGroup`）確認此路徑真實存在，新增 **Task 7**（`_openBook()` 接上 `.then((_) => _loadBooks())` + 對應 widget test），原「Task 7 真機整合測試」順延為 **Task 8**，文中相關的 Task 編號交叉引用已同步更新。
- **Important 1（確認屬實，已修正）**：原 Task 1 的 migration 回歸測試只涵蓋 v4→v5，無法偵測 Critical 1 那類「跳級升級被分支結構跳過」的缺陷。已在 Task 1 新增 Step 5（v1→v5 跳級升級測試，模擬完全沒有 `book_reader_prefs` 表、`books` 表也不含新欄位的最原始 schema），驗證兩張表皆正確補齊、既有書籍資料不受影響；原 Step 5/6（執行測試／Commit）順延為 Step 6/7。
