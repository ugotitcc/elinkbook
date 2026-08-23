# Epic 30 Issue 0：擴充既有匯入/查詢管線與新增站點表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建好本 Epic（Calibre 遠端書架整合）後續所有切片共用的資料層基礎設施：新增 `remote_servers` 表、`books` 表新增 4 個欄位與 1 個索引、`Book` 模型同步擴充、`BookImportService.importFiles()` 簽章擴充、`LibraryRepository` 新增兩個查詢方法、`pubspec.yaml` 依賴提升。本 Issue 完成後不含任何使用者可見的新功能（無 UI），純粹是讓後續切片（Issue 1-5）能直接動工的地基。

**Architecture:** 延伸既有 `SqliteLibraryRepository` 的 schema migration 慣例（`onCreate`/`onUpgrade` 累加式 `if (oldVersion < N)` 區塊）、`Book` 模型的欄位+`toMap`/`fromMap`+`copyWith`/`==`/`hashCode` 五處同步慣例、`BookImportService.importFiles()` 的既有可選參數擴充慣例（比照 `epic-1-library` 定案介面）。與尚未實作的 `epic-29-cloud-import` 有三個共用觸點，本計畫每個相關 Task 都先檢查現況、避免重複宣告。

**Tech Stack:** Flutter/Dart、`sqflite`（含 `sqflite_common_ffi` 測試用記憶體資料庫）、既有 `xml`/`http` 套件（本 Issue 由 `dev_dependencies` 提升至 `dependencies`）。

**Spec:** `docs/epics/epic-30-calibre-remote-library/spec.md`（「與 `epic-29-cloud-import` 的順序無關性」「資料模型與 Schema」「既有匯入管線擴充」章節為本計畫的唯一事實來源），另參 `docs/epics/epic-30-calibre-remote-library/design.md`（Discovery 決策）與 `docs/epics/epic-30-calibre-remote-library/issues.md`（Issue 0 條目）。

## Global Constraints

- **順序無關性**（`spec.md`「與 `epic-29-cloud-import` 的順序無關性」）：`BookImportService.importFiles()` 的 `source` 參數、`LibraryRepository.findByContentFingerprint()`——若因 `epic-29-cloud-import` 先落地而已存在，直接沿用、不重複宣告，只疊加本 Epic 專屬的新參數/方法。
- **schema 版本號不寫死**：目前最新版本為 21（`sqlite_library_repository.dart:42`，`open()` 的 `version:` 參數），本 Issue 執行前**務必先重新確認這個數字**（若 `epic-29-cloud-import` 已先落地並取走 22，本 Issue 改用 23），以下所有程式碼與註解中的版本號皆以「執行當下核實的最新版本 +1」為準，本文件以 22 為例。
- 所有新增/修改的程式碼註解使用正體中文，比照本檔案既有風格。
- `flutter analyze` 全程保持乾淨；每個 Task 結束時既有測試套件零回歸。

---

### Task 1: Schema migration — `remote_servers` 表與 `books` 表新增欄位

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: 新表 `remote_servers`（欄位：`id TEXT PRIMARY KEY`／`name TEXT NOT NULL`／`base_url TEXT NOT NULL`／`type TEXT NOT NULL`／`username TEXT`／`allow_insecure INTEGER NOT NULL DEFAULT 0`／`created_at INTEGER NOT NULL`／`last_accessed_at INTEGER`）；`books` 表新增 `remote_server_id TEXT`／`remote_book_id TEXT`／`remote_download_url TEXT`／`is_downloaded INTEGER NOT NULL DEFAULT 1`；新索引 `idx_books_remote_lookup ON books(remote_server_id, remote_book_id)`。後續 Task 2（`Book` 模型）依賴這些欄位名稱與型別。

本 Task 同時要**實測**`remote_server_id` 是否能以 `ALTER TABLE ADD COLUMN` 內聯宣告 `REFERENCES remote_servers(id) ON DELETE SET NULL`（`spec.md`「資料模型與 Schema」列為技術風險，需要實測確認）——用 TDD 的紅燈階段直接驗證，不用另外寫實驗腳本。

- [x] **Step 1: 核對目前最新 schema 版本號**

Run: 在 `app/lib/library/sqlite_library_repository.dart` 搜尋 `version:`（`open()` 方法內）。

Expected: 確認目前值（撰寫本計畫時為 `21`）。若已不是 21（代表 `epic-29-cloud-import` 已先落地取走 22），後續所有步驟中的 `22` 一律替換為「該值 +1」，`if (oldVersion < 22)` 一併替換版本號。以下步驟皆以 22 為例。

- [x] **Step 2: 寫失敗測試——全新安裝可寫入/讀取 `remote_servers` 表**

在 `app/test/library/sqlite_library_repository_test.dart` 找到既有的 `test('全新安裝的 layout_preset 表可用（version 21 起 onCreate 已含括）', ...)` 測試（緊鄰 `listReflowableEpubBooks` 的 `group(...)` 之前），在它之後新增：

```dart
test('全新安裝的 remote_servers 表可用（version 22 起 onCreate 已含括）', () async {
  await repository.database.insert('remote_servers', {
    'id': 'srv1',
    'name': '家用 NAS',
    'base_url': 'http://192.168.1.100:8080/opds',
    'type': 'opds',
    'username': null,
    'allow_insecure': 0,
    'created_at': 1000,
    'last_accessed_at': null,
  });
  final rows = await repository.database.query('remote_servers');
  expect(rows, hasLength(1));
  expect(rows.single['name'], '家用 NAS');
});
```

- [x] **Step 3: 寫失敗測試——既有 version 21 裝置升級到 version 22**

緊接著 Step 2 的測試之後新增（比照緊鄰的 `test('既有 version 20 裝置升級到 version 21，新增 layout_preset 表，可正常寫入讀取', ...)` 既有模板，books 表 CREATE TABLE 字串需含 version 21 當下的完整欄位，即現有 `onCreate` 的 books 定義原樣照抄）：

```dart
test('既有 version 21 裝置升級到 version 22，新增 remote_servers 表與 books 新欄位',
    () async {
  final tempDir = await Directory.systemTemp
      .createTemp('elinkbook_migration_v21_to_v22_remote_library_test');
  addTearDown(() => tempDir.delete(recursive: true));
  final dbPath = p.join(tempDir.path, 'test.db');

  final oldDb = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 21,
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
            epubLocator TEXT,
            pdfPageIndex INTEGER,
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
            groupName TEXT NOT NULL DEFAULT '未分類',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL,
            content_fingerprint TEXT,
            position_updated_at INTEGER,
            position_synced_server_updated_at TEXT
          )
        ''');
        await db.insert('books', {
          'id': 'book1',
          'title': '舊書',
          'format': 'epub',
          'filePath': '/books/book1.epub',
          'source': 'local',
          'progress': 0,
          'groupName': '未分類',
          'createTime': 1000,
          'lastReadTime': 1000,
        });
      },
    ),
  );
  await oldDb.close();

  // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=21 →
  // newVersion=22）。
  final upgraded = await SqliteLibraryRepository.open(dbPath);
  addTearDown(() => upgraded.close());

  final rows = await upgraded.database.query('books');
  expect(rows, hasLength(1));
  expect(rows.single['remote_server_id'], isNull);
  expect(rows.single['remote_book_id'], isNull);
  expect(rows.single['remote_download_url'], isNull);
  expect(rows.single['is_downloaded'], 1);

  await upgraded.database.insert('remote_servers', {
    'id': 'srv1',
    'name': '家用 NAS',
    'base_url': 'http://192.168.1.100:8080/opds',
    'type': 'opds',
    'allow_insecure': 0,
    'created_at': 1000,
  });
  final serverRows = await upgraded.database.query('remote_servers');
  expect(serverRows, hasLength(1));
});
```

- [x] **Step 4: 寫失敗測試——刪除站點後，關聯書籍的 `remote_server_id` 自動變為 `NULL`**

緊接著 Step 3 的測試之後新增（這個測試同時驗證 `ON DELETE SET NULL` 外鍵約束是否真的生效——TDD 紅燈階段就是實測本身，不需要另外寫實驗腳本）：

```dart
test('刪除 remote_servers 該筆後，關聯 books 的 remote_server_id 自動變為 NULL',
    () async {
  final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  addTearDown(() => repo.close());

  await repo.database.insert('remote_servers', {
    'id': 'srv1',
    'name': '家用 NAS',
    'base_url': 'http://192.168.1.100:8080/opds',
    'type': 'opds',
    'allow_insecure': 0,
    'created_at': 1000,
  });
  await repo.insertBook(Book(
    id: 'book1',
    title: '雲端書',
    format: BookFileFormat.epub,
    filePath: '/books/book1.epub',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    remoteServerId: 'srv1',
    remoteBookId: 'remote-book-1',
  ));

  await repo.database.delete('remote_servers', where: 'id = ?', whereArgs: ['srv1']);

  final rows = await repo.database.query('books', where: 'id = ?', whereArgs: ['book1']);
  expect(rows.single['remote_server_id'], isNull);
});
```

**這個測試依賴 Task 2 才會新增的 `Book(remoteServerId:, remoteBookId:)` 具名參數**，Step 4 先寫測試碼、確認編譯會失敗（`Book` 建構子還沒有這兩個參數），屬預期中的紅燈——先繼續往下做 Step 5-6（先讓 Step 2/3 兩個不依賴 `Book` 模型的測試通過），Step 4 這個測試留到 Task 2 完成後才會真正跑到綠燈，在本 Task 結尾的 Step 7 一併確認。

- [x] **Step 5: 執行測試確認全部失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL——Step 2/3 因 `remote_servers` 表不存在／`books` 缺少新欄位失敗（`no such table: remote_servers` 或 `no such column`）；Step 4 因 `Book` 建構子不接受 `remoteServerId`/`remoteBookId` 參數而編譯失敗。

- [x] **Step 6: 實作 schema migration**

修改 `app/lib/library/sqlite_library_repository.dart`：

1. `open()` 方法的 `version: 21` 改為 `version: 22`（`sqlite_library_repository.dart:42`）。
2. 在 `onCreate` 內，`CREATE TABLE books` 之前新增 `remote_servers` 表建立呼叫，並在 `books` 表的 `CREATE TABLE` 欄位定義中新增 4 個欄位：

```dart
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
        await _createRemoteServersTable(db);
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
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL,
            content_fingerprint TEXT,
            position_updated_at INTEGER,
            position_synced_server_updated_at TEXT,
            remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
            remote_book_id TEXT,
            remote_download_url TEXT,
            is_downloaded INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
        await _createBookReaderPrefsTable(db);
        await _createBookmarksTable(db);
        await _createHighlightsTable(db);
        await _createNotesTable(db);
        await _createCustomFontsTable(db);
        await _createSyncMetadataTable(db);
        await _createSyncRemoteIdsTable(db);
        await _createSyncPendingRecordsTable(db);
        await _createLayoutPresetTable(db);
      },
```

3. 在 `onUpgrade` 最後一個 `if (oldVersion < 21)` 區塊之後（`sqlite_library_repository.dart:302-310` 附近，緊接在 `}` 之後、`onUpgrade` 大括號結束之前），新增：

```dart
        if (oldVersion < 22) {
          // epic-30-calibre-remote-library Issue 0：Calibre／OPDS 遠端書架
          // 站點表，以及 books 表新增的 4 個欄位（見 spec.md「資料模型與
          // Schema」）。remote_servers 是全新獨立表，比照 bookmarks
          // （oldVersion < 8）／custom_fonts（oldVersion < 16）既有原則，
          // 無條件建立即可；books 表 4 個新欄位皆為 nullable 或有預設值，
          // 既有資料升級後自動補上預設值，不影響既有資料。
          //
          // remote_server_id 內聯宣告 REFERENCES remote_servers(id) ON
          // DELETE SET NULL：實測確認 sqflite 底層 SQLite 版本支援
          // ALTER TABLE ADD COLUMN 搭配 REFERENCES 子句（本欄位為
          // nullable、無 NOT NULL 約束，符合 SQLite 官方文件對 ADD
          // COLUMN 搭配 REFERENCES 的唯一限制）。若未來 sqflite/SQLite
          // 版本升級後這個假設不再成立，改為移除此處的 REFERENCES 子句、
          // 只留 `remote_server_id TEXT`，並在 Issue 1 的
          // `RemoteServerRepository.deleteServer()` 內改為應用層手動
          // `UPDATE books SET remote_server_id = NULL WHERE remote_server_id = ?`
          // 達成同等行為（見 spec.md「技術風險與備援方案」）。
          await _createRemoteServersTable(db);
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL');
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_book_id TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_download_url TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN is_downloaded INTEGER NOT NULL DEFAULT 1');
          await db.execute(
              'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
        }
```

4. 新增 `_createRemoteServersTable` 靜態方法（比照 `_createLayoutPresetTable` 的既有寫法，放在同一個私有 helper 群組區塊內，例如緊接在 `_createLayoutPresetTable` 定義之後）：

```dart
  static Future<void> _createRemoteServersTable(Database db) async {
    // Calibre／OPDS 遠端書架站點（epic-30-calibre-remote-library
    // Issue 0），見 spec.md「站點管理：RemoteServerRepository」。密碼
    // 獨立存 flutter_secure_storage（Issue 1），此表只存非敏感設定。
    await db.execute('''
      CREATE TABLE remote_servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        type TEXT NOT NULL,
        username TEXT,
        allow_insecure INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');
  }
```

- [x] **Step 7: 執行測試確認 Step 2/3 通過（Step 4 留待 Task 2 完成後）**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: Step 2、Step 3 兩個測試 PASS；Step 4 測試因 `Book` 尚無 `remoteServerId`/`remoteBookId` 具名參數，仍是編譯錯誤（預期中，等 Task 2 完成）。

- [x] **Step 8: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-30): 新增 remote_servers 表與 books 表遠端書架欄位（schema v22）"
```

---

### Task 2: `Book` 模型新增 4 個欄位

**Files:**
- Modify: `app/lib/library/models/book.dart`

**Interfaces:**
- Consumes: Task 1 新增的 `books` 表欄位 `remote_server_id`/`remote_book_id`/`remote_download_url`/`is_downloaded`。
- Produces: `Book` 新增具名建構參數 `remoteServerId`（`String?`）、`remoteBookId`（`String?`）、`remoteDownloadUrl`（`String?`）、`isDownloaded`（`bool`，預設 `true`）。後續 Task 4（`LibraryRepository` 新查詢方法）與 Task 5（`BookImportService` 擴充）會建構/讀取這些欄位。

**⚠️ 已知陷阱**：這個檔案的 `copyWith()` 方法**不是**把所有欄位都開放成具名參數——`positionUpdatedAt`/`positionSyncedServerUpdatedAt` 兩個既有欄位就刻意不開放（見 `book.dart:75-80` 既有註解「不開放為 copyWith() 的具名參數...但仍會原樣帶入 copyWith() 回傳的新物件，不能讓 copyWith() 把這兩個欄位清空」），2026-08-04 曾發生過忘記把既有欄位帶入 `copyWith()` 回傳值、被任何呼叫 `copyWith()` 的地方靜默清空成 `null` 的真實回歸。本 Task 新增的 4 個欄位比照同一原則處理：**不開放為 `copyWith()` 的具名參數**（目前沒有任何呼叫端需要透過 `copyWith()` 修改這 4 個欄位，YAGNI），但**必須**在 `copyWith()` 回傳的新物件中原樣帶入，否則任何既有呼叫（例如 `LibraryScreen` 批次分類異動時呼叫 `copyWith(groupName: ...)`）都會靜默把這本書的遠端書架關聯清空。

- [x] **Step 1: 補上 Task 1 的紅燈測試（`Book` 建構子）**

確認 Task 1 Step 4 寫的測試（`刪除 remote_servers 該筆後，關聯 books 的 remote_server_id 自動變為 NULL`）目前因缺少 `Book(remoteServerId:, remoteBookId:)` 具名參數而編譯失敗，這就是本 Task 要解決的紅燈，不需要另外重寫。

- [x] **Step 2: 寫失敗測試——`copyWith()` 不清空新欄位（回歸防護）**

在 `app/test/library/sqlite_library_repository_test.dart` 新增一個獨立測試（放在 Task 1 新增的 3 個測試之後）：

```dart
test('Book.copyWith() 不會清空 remoteServerId/remoteBookId/remoteDownloadUrl/isDownloaded',
    () async {
  final original = Book(
    id: 'book1',
    title: '雲端書',
    format: BookFileFormat.epub,
    filePath: '/books/book1.epub',
    source: BookSource.calibreOpds,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    remoteServerId: 'srv1',
    remoteBookId: 'remote-book-1',
    remoteDownloadUrl: 'http://192.168.1.100:8080/opds/download/1.epub',
    isDownloaded: false,
  );

  final copied = original.copyWith(groupName: '新分類');

  expect(copied.remoteServerId, 'srv1');
  expect(copied.remoteBookId, 'remote-book-1');
  expect(copied.remoteDownloadUrl,
      'http://192.168.1.100:8080/opds/download/1.epub');
  expect(copied.isDownloaded, false);
});
```

- [x] **Step 3: 寫失敗測試——`insertBook`/`listBooks` 往返保留新欄位（含 `BookSource.calibreOpds`）**

緊接著 Step 2 的測試之後新增：

```dart
test('insertBook/listBooks 往返保留 remoteServerId/remoteBookId/remoteDownloadUrl/isDownloaded',
    () async {
  final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  addTearDown(() => repo.close());

  await repo.insertBook(Book(
    id: 'book1',
    title: '雲端書',
    format: BookFileFormat.epub,
    filePath: '/books/book1.epub',
    source: BookSource.calibreOpds,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    remoteServerId: 'srv1',
    remoteBookId: 'remote-book-1',
    remoteDownloadUrl: 'http://192.168.1.100:8080/opds/download/1.epub',
    isDownloaded: false,
  ));

  final books = await repo.listBooks();
  final book = books.single;
  expect(book.source, BookSource.calibreOpds);
  expect(book.remoteServerId, 'srv1');
  expect(book.remoteBookId, 'remote-book-1');
  expect(book.remoteDownloadUrl,
      'http://192.168.1.100:8080/opds/download/1.epub');
  expect(book.isDownloaded, false);
});

test('未指定 remoteServerId 等欄位時，新書預設 isDownloaded=true 且其餘欄位為 null',
    () async {
  final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  addTearDown(() => repo.close());

  await repo.insertBook(Book(
    id: 'book2',
    title: '本機書',
    format: BookFileFormat.epub,
    filePath: '/books/book2.epub',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  ));

  final book = (await repo.listBooks()).single;
  expect(book.isDownloaded, true);
  expect(book.remoteServerId, isNull);
  expect(book.remoteBookId, isNull);
  expect(book.remoteDownloadUrl, isNull);
});
```

- [x] **Step 4: 執行測試確認全部失敗（編譯錯誤）**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL——`Book` 建構子不接受 `remoteServerId`/`remoteBookId`/`remoteDownloadUrl`/`isDownloaded`，`BookSource.calibreOpds` 不存在（`library_enums.dart` 尚未新增，Task 3 才會補）。**本 Step 會同時暴露 Task 3 的紅燈，屬預期中——Task 3 會一併處理 `BookSource.calibreOpds`。**

- [x] **Step 5: 實作 `Book` 模型擴充**

修改 `app/lib/library/models/book.dart`，共 5 處：

1. 欄位宣告（緊接在既有 `positionSyncedServerUpdatedAt` 欄位之後、`groupName` 之前，即 `book.dart:81` 之後）：

```dart
  /// 遠端書架站點 id（`epic-30-calibre-remote-library` Issue 0），對應
  /// `remote_servers.id`；`null` 代表非遠端書架來源的書籍（本機／雲端
  /// 硬碟匯入）。
  final String? remoteServerId;

  /// 遠端書架來源的 OPDS 條目 id（書本層級，不分格式），`null` 代表非
  /// 遠端書架來源的書籍。
  final String? remoteBookId;

  /// 最近一次成功下載時使用的絕對 URL，供「重新下載」直接重用（見
  /// spec.md「下載與快取生命週期」策略 A）。`null` 代表非遠端書架來源，
  /// 或尚未有任何成功下載紀錄。
  final String? remoteDownloadUrl;

  /// 本機是否仍有可讀取的實體檔案。本機／雲端硬碟匯入的書恆為
  /// `true`；遠端書架來源的書在使用者「移除本機快取」後變為 `false`
  /// （書籍紀錄與劃線/書籤/進度資料原樣保留，`filePath` 保留最後一次
  /// 下載路徑但該路徑實體檔案已被刪除，不可信任其可讀取，見 spec.md
  /// 「下載與快取生命週期」）。
  final bool isDownloaded;
```

2. 建構子（緊接在既有 `this.positionSyncedServerUpdatedAt` 之後、`this.groupName = BookGroup.uncategorized` 之前，即 `book.dart:102` 之後）：

```dart
    this.remoteServerId,
    this.remoteBookId,
    this.remoteDownloadUrl,
    this.isDownloaded = true,
```

3. `toMap()`（緊接在既有 `'position_synced_server_updated_at': positionSyncedServerUpdatedAt,` 之後）：

```dart
      'remote_server_id': remoteServerId,
      'remote_book_id': remoteBookId,
      'remote_download_url': remoteDownloadUrl,
      'is_downloaded': isDownloaded ? 1 : 0,
```

4. `Book.fromMap()`（緊接在既有 `positionSyncedServerUpdatedAt: map['position_synced_server_updated_at'] as String?,` 之後）：

```dart
      remoteServerId: map['remote_server_id'] as String?,
      remoteBookId: map['remote_book_id'] as String?,
      remoteDownloadUrl: map['remote_download_url'] as String?,
      isDownloaded: (map['is_downloaded'] as int) == 1,
```

5. `copyWith()`——**不新增具名參數**，但在方法本體回傳的 `Book(...)` 中原樣帶入這 4 個欄位（緊接在既有 `positionSyncedServerUpdatedAt: positionSyncedServerUpdatedAt,` 之後，比照該欄位「原樣帶入、不開放具名參數」的既有處理方式）：

```dart
        remoteServerId: remoteServerId,
        remoteBookId: remoteBookId,
        remoteDownloadUrl: remoteDownloadUrl,
        isDownloaded: isDownloaded,
```

6. `operator ==`（緊接在既有 `positionSyncedServerUpdatedAt == other.positionSyncedServerUpdatedAt &&` 之後）：

```dart
          remoteServerId == other.remoteServerId &&
          remoteBookId == other.remoteBookId &&
          remoteDownloadUrl == other.remoteDownloadUrl &&
          isDownloaded == other.isDownloaded &&
```

7. `hashCode`（緊接在既有 `positionSyncedServerUpdatedAt,` 之後）：

```dart
        remoteServerId,
        remoteBookId,
        remoteDownloadUrl,
        isDownloaded,
```

- [x] **Step 6: 執行測試確認 Task 1 與 Task 2 的測試全數通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: 仍會因 `BookSource.calibreOpds` 不存在而 FAIL（Task 3 待辦）；除此之外的斷言邏輯應可編譯（`Book` 相關部分已完整）。若此時錯誤訊息只剩下 `BookSource.calibreOpds` 未定義，代表 Task 2 本身已正確完成，繼續往下做 Task 3。

- [x] **Step 7: Commit**

```bash
git add app/lib/library/models/book.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-30): Book 模型新增遠端書架 4 個欄位，copyWith 原樣帶入避免回歸"
```

---

### Task 3: `BookSource` enum 新增 `calibreOpds`

**Files:**
- Modify: `app/lib/library/models/library_enums.dart`

**Interfaces:**
- Produces: `BookSource.calibreOpds`。`Book.toMap()`/`Book.fromMap()`（Task 2 已完成）透過 `.name`/`BookSource.values.byName()` 序列化，不需要為新 enum 值另外修改。

- [x] **Step 1: 執行測試確認目前因 `BookSource.calibreOpds` 未定義而失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL，錯誤訊息指出 `calibreOpds` 不是 `BookSource` 的成員（Task 2 Step 6 已確認的紅燈）。

- [x] **Step 2: 新增 enum 值**

修改 `app/lib/library/models/library_enums.dart:8`：

```dart
enum BookSource { local, googleDrive, oneDrive, calibreOpds }
```

- [x] **Step 3: 執行測試確認全數通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS——本檔案內 Task 1（3 個測試）＋ Task 2（3 個測試）共 6 個新測試全數通過，既有測試（`listReflowableEpubBooks` 等）零回歸。

- [x] **Step 4: Commit**

```bash
git add app/lib/library/models/library_enums.dart
git commit -m "feat(epic-30): BookSource 新增 calibreOpds"
```

---

### Task 4: `pubspec.yaml` 依賴提升（`xml`／`http`）

**Files:**
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Produces: `xml`／`http` 由 `dev_dependencies` 移至正式 `dependencies`，供後續 Issue 1 的 `OpdsClient`／`OpdsFeedParser` 實作使用。本 Task 不涉及任何程式邏輯改動，純設定檔異動。

- [x] **Step 1: 修改 `pubspec.yaml`**

在 `app/pubspec.yaml` 的 `dependencies:` 區塊（`html: ^0.15.6` 之後，`dev_dependencies:` 之前）新增：

```yaml
  # OPDS Atom XML 解析（epic-30-calibre-remote-library Issue 1 起使用，
  # 本 Issue 先提升依賴層級）：原僅供測試驗證合成 EPUB 結構的 XML 格式，
  # 現升級為正式匯入管線的執行期依賴。
  xml: ^6.6.1
  # 遠端書庫 HTTP 通訊（epic-30-calibre-remote-library Issue 1 起使用，
  # 本 Issue 先提升依賴層級）：原僅供測試以 MockClient 取代真實網路請求，
  # 現升級為正式匯入管線的執行期依賴。
  http: ^1.6.0
```

從 `app/pubspec.yaml` 的 `dev_dependencies:` 區塊移除原本的 `http: ^1.6.0` 與 `xml: ^6.6.1` 兩行（含各自緊鄰的說明註解一併移除，避免與上方新註解重複）。

- [x] **Step 2: 執行 `flutter pub get` 確認無版本衝突**

Run: `cd app && flutter pub get`
Expected: 成功完成，無版本解析錯誤（`pubspec.yaml` 現有註解已記錄 `win32` 相依鏈的既有歷史糾葛，若這步驟出現衝突訊息，需要對照該註解排查，但 `xml`/`http` 本身不涉及 `win32`，預期不會觸發）。

- [x] **Step 3: 執行既有全專案測試確認零回歸**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨（`No issues found!`）；`flutter test` 全數通過。

- [x] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "feat(epic-30): xml/http 由 dev_dependencies 提升至正式 dependencies"
```

---

### Task 5: `LibraryRepository` 新增兩個查詢方法

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 1（`books` 表 `remote_server_id`/`remote_book_id`/`content_fingerprint` 欄位，後者為既有欄位）、Task 2（`Book.remoteServerId`/`remoteBookId`）。
- Produces: `findByRemoteBookId(String serverId, String remoteBookId) → Future<Book?>`、`findByContentFingerprint(String fingerprint) → Future<Book?>`（**先查現況**，見下方 Step 0）。Issue 3（雙層重複匯入偵測）依賴這兩個方法的確切簽章。

**⚠️ 順序無關性檢查（`spec.md`「與 `epic-29-cloud-import` 的順序無關性」）**：`findByContentFingerprint()` 這個方法 `epic-29-cloud-import` 的 `spec.md` 也規劃要新增。執行本 Task 前，先確認 `LibraryRepository`（`app/lib/library/library_repository.dart`）目前是否已經有這個方法——若 `epic-29-cloud-import` 已先落地並新增過，直接沿用既有簽章，本 Task 只需要新增 `findByRemoteBookId()`；若尚未存在（撰寫本計畫時核實為尚未存在），本 Task 兩個方法都新增。以下步驟以「兩者皆尚未存在」為例撰寫，若執行時發現 `findByContentFingerprint()` 已存在，略過該方法相關的程式碼片段，只保留 `findByRemoteBookId()` 的部分。

- [x] **Step 1: 核對 `findByContentFingerprint()` 現況**

Run: 在 `app/lib/library/library_repository.dart` 搜尋 `findByContentFingerprint`。

Expected: 若無結果（撰寫本計畫時的現況），繼續下方所有步驟；若已存在，記錄其確切簽章（應為 `Future<Book?> findByContentFingerprint(String fingerprint)`），並在後續步驟中略過重複新增的部分。

- [x] **Step 2: 寫失敗測試**

在 `app/test/library/sqlite_library_repository_test.dart` 新增（放在 Task 2 新增的測試之後）：

```dart
group('findByRemoteBookId', () {
  test('命中：回傳對應書籍', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());

    await repo.insertBook(Book(
      id: 'book1',
      title: '雲端書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
    ));

    final found = await repo.findByRemoteBookId('srv1', 'remote-book-1');
    expect(found?.id, 'book1');
  });

  test('未命中：不同站點或不同 remoteBookId 皆回傳 null', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());

    await repo.insertBook(Book(
      id: 'book1',
      title: '雲端書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
    ));

    expect(await repo.findByRemoteBookId('srv2', 'remote-book-1'), isNull);
    expect(await repo.findByRemoteBookId('srv1', 'other-book'), isNull);
  });
});

group('findByContentFingerprint', () {
  test('命中：回傳對應書籍', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());

    await repo.insertBook(Book(
      id: 'book1',
      title: '本機書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.local,
      contentFingerprint: 'fingerprint-abc',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    ));

    final found = await repo.findByContentFingerprint('fingerprint-abc');
    expect(found?.id, 'book1');
  });

  test('未命中：回傳 null', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());

    expect(await repo.findByContentFingerprint('does-not-exist'), isNull);
  });
});
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL——`LibraryRepository`／`SqliteLibraryRepository` 尚無這兩個方法，編譯錯誤。

- [x] **Step 4: 實作**

在 `app/lib/library/library_repository.dart` 的 `abstract class LibraryRepository` 內，緊接在既有 `listReflowableEpubBooks` 方法之後新增（若 `findByContentFingerprint` 已存在則略過該行）：

```dart
  /// 依 `(remoteServerId, remoteBookId)` 精確比對，供遠端書架選檔前置
  /// 重複匯入偵測使用（`epic-30-calibre-remote-library`，spec.md「重複
  /// 匯入偵測」）。命中回傳該本書，未命中回傳 `null`。
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId);

  /// 依 `content_fingerprint` 精確比對，供雲端/遠端書架匯入的下載後重複
  /// 匯入偵測使用（`epic-29-cloud-import`／`epic-30-calibre-remote-library`
  /// 共用，見 `CONTEXT.md`「書籍內容指紋」）。命中回傳該本書，未命中回傳
  /// `null`。
  Future<Book?> findByContentFingerprint(String fingerprint);
```

在 `app/lib/library/sqlite_library_repository.dart` 的 `SqliteLibraryRepository` 類別內，緊接在既有 `listReflowableEpubBooks` 實作之後新增：

```dart
  @override
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId) async {
    final rows = await _db.query(
      'books',
      where: 'remote_server_id = ? AND remote_book_id = ?',
      whereArgs: [serverId, remoteBookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  @override
  Future<Book?> findByContentFingerprint(String fingerprint) async {
    final rows = await _db.query(
      'books',
      where: 'content_fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }
```

在 `app/test/support/fake_library_repository.dart` 的 `FakeLibraryRepository` 類別內，緊接在既有 `listReflowableEpubBooks` 實作之後新增：

```dart
  @override
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId) async {
    for (final book in _books) {
      if (book.remoteServerId == serverId && book.remoteBookId == remoteBookId) {
        return book;
      }
    }
    return null;
  }

  @override
  Future<Book?> findByContentFingerprint(String fingerprint) async {
    for (final book in _books) {
      if (book.contentFingerprint == fingerprint) return book;
    }
    return null;
  }
```

**同時修正 `FakeLibraryRepository._withGroupName()` 的既有陷阱**（`fake_library_repository.dart:153-166`）：這個方法手動組裝新 `Book` 物件（不是呼叫 `copyWith()`），目前沒有帶入 `remoteServerId`/`remoteBookId`/`remoteDownloadUrl`/`isDownloaded`（也沒有帶入既有的 `contentFingerprint`/`positionUpdatedAt` 等欄位——這是既有的既存缺口，本次一併修正，屬於 Task 2 已修正的 `copyWith()` 同一類問題，發生在 Fake 而非正式模型上）。修改為：

```dart
  Book _withGroupName(Book book, String groupName) => Book(
        id: book.id,
        title: book.title,
        author: book.author,
        format: book.format,
        filePath: book.filePath,
        source: book.source,
        coverPath: book.coverPath,
        progress: book.progress,
        epubLocator: book.epubLocator,
        pdfPageIndex: book.pdfPageIndex,
        totalCharacterCount: book.totalCharacterCount,
        isFixedLayout: book.isFixedLayout,
        contentFingerprint: book.contentFingerprint,
        positionUpdatedAt: book.positionUpdatedAt,
        positionSyncedServerUpdatedAt: book.positionSyncedServerUpdatedAt,
        remoteServerId: book.remoteServerId,
        remoteBookId: book.remoteBookId,
        remoteDownloadUrl: book.remoteDownloadUrl,
        isDownloaded: book.isDownloaded,
        groupName: groupName,
        createTime: book.createTime,
        lastReadTime: book.lastReadTime,
      );
```

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart && flutter test`
Expected: 全數通過，全專案零回歸（`FakeLibraryRepository` 是廣泛被其他既有 widget test 使用的測試替身，`_withGroupName` 的修正需要確認不會意外改變既有測試斷言的分類異動行為——既有測試只斷言 `groupName` 本身，新增的欄位帶入不影響既有斷言）。

- [x] **Step 6: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/support/fake_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-30): LibraryRepository 新增 findByRemoteBookId/findByContentFingerprint"
```

---

### Task 6: `BookImportService.importFiles()` 簽章擴充

**Files:**
- Modify: `app/lib/library/book_import_service.dart`
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes: Task 2（`Book.remoteServerId`/`remoteBookId`/`remoteDownloadUrl`/`isDownloaded`）、Task 3（`BookSource.calibreOpds`）。
- Produces: `importFiles()` 新簽章（見下方 Step 4），Issue 2（OPDS 目錄瀏覽＋批次下載＋匯入）依賴這個簽章把下載完成的檔案匯入圖書庫。

**⚠️ 順序無關性檢查（`spec.md`「與 `epic-29-cloud-import` 的順序無關性」）**：`source: BookSource source = BookSource.local` 這個參數 `epic-29-cloud-import` 也規劃要新增。執行本 Task 前，先確認 `BookImportService.importFiles()`（`app/lib/library/book_import_service.dart`）目前是否已經有 `source` 參數——若已存在（`epic-29-cloud-import` 已先落地），沿用既有參數與其在 `_importSingleFile()`／`Book(...)` 建構子內已經接好的既有邏輯，本 Task 只需要疊加 `remoteServerId`/`remoteBookIds`/`remoteDownloadUrls` 三個新參數；若尚未存在（撰寫本計畫時核實為尚未存在），本 Task 一併新增 `source` 參數。以下步驟以「`source` 尚未存在」為例撰寫。

- [x] **Step 1: 核對 `source` 參數現況**

Run: 在 `app/lib/library/book_import_service.dart` 搜尋 `source`；在 `app/lib/library/book_import_service_impl.dart` 搜尋 `BookSource.local`（目前硬編碼於 `_importSingleFile` 內組裝 `Book(...)` 處，撰寫本計畫時核實位置為 `book_import_service_impl.dart:388`）。

Expected: 若 `importFiles()` 尚無 `source` 參數、且 `book_import_service_impl.dart:388` 仍是硬編碼 `source: BookSource.local,`（撰寫本計畫時的現況），繼續下方所有步驟；若已存在，記錄其確切簽章與 `_importSingleFile` 內既有的接線方式，後續步驟中略過重複新增 `source` 相關的部分，只新增 `remoteServerId`/`remoteBookIds`/`remoteDownloadUrls`。

- [x] **Step 2: 寫失敗測試**

在 `app/test/library/book_import_service_test.dart` 新增（放在既有測試之後，可放在檔案末尾；沿用檔案既有的 `mockChannel`/`service`/`repository` setUp 慣例）：

```dart
  test('傳入 source/remoteServerId/remoteBookIds/remoteDownloadUrls 時正確落地',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {'title': '遠端書'};
      }
      return null;
    });

    final result = await service.importFiles(
      ['content://example/remote_book.epub'],
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookIds: {'content://example/remote_book.epub': 'remote-book-1'},
      remoteDownloadUrls: {
        'content://example/remote_book.epub':
            'http://192.168.1.100:8080/opds/download/1.epub',
      },
    );

    expect(result.importedBooks, hasLength(1));
    final book = result.importedBooks.single;
    expect(book.source, BookSource.calibreOpds);
    expect(book.remoteServerId, 'srv1');
    expect(book.remoteBookId, 'remote-book-1');
    expect(book.remoteDownloadUrl,
        'http://192.168.1.100:8080/opds/download/1.epub');
    expect(book.isDownloaded, true);
  });

  test('未傳入新參數時（既有本機匯入情境），行為與現行完全一致', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {'title': '本機書'};
      }
      return null;
    });

    final result =
        await service.importFiles(['content://example/local_book.epub']);

    expect(result.importedBooks, hasLength(1));
    final book = result.importedBooks.single;
    expect(book.source, BookSource.local);
    expect(book.remoteServerId, isNull);
    expect(book.remoteBookId, isNull);
    expect(book.remoteDownloadUrl, isNull);
    expect(book.isDownloaded, true);
  });
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: FAIL——`importFiles()` 不接受新參數，編譯錯誤。

- [x] **Step 4: 實作介面擴充**

修改 `app/lib/library/book_import_service.dart` 的 `importFiles()` 宣告（`book_import_service.dart:30-34`）：

```dart
  /// 匯入單一或多個已由呼叫端（例如 file_picker、遠端書架下載完成後的
  /// 暫存路徑）選取的檔案 URI；[displayNames] 為與 [uris] 一一對應（同
  /// 索引）的真實檔名，供格式偵測在 URI 本身不含可辨識副檔名時當退路
  /// （例如部分文件提供者的 URI 只帶不透明數字文件 ID，見
  /// book_import_service_impl.dart 的說明），長度可短於 [uris] 或為
  /// `null`（該索引/整體視為沒有檔名可用，退回只看 URI）；[folderName]
  /// 標記來源資料夾名稱供 FR-34 自動分類判斷，單檔/多檔匯入（非資料夾
  /// 匯入）時為 `null`。與圖書庫既有書籍來源 URI 相同的檔案會被跳過，
  /// 不會重複匯入（見 [ImportResult.skippedDuplicateCount]）。
  ///
  /// [source] 標記這批檔案的來源（預設 [BookSource.local]，既有呼叫端
  /// 不需要修改）。[remoteServerId] 為遠端書架來源時所屬的站點 id（本次
  /// 批次所屬站點，單一值，因為一次瀏覽/下載動作只會來自同一個站點）。
  /// [remoteBookIds]／[remoteDownloadUrls] 為 uri 對應的遠端書架條目
  /// id／下載當下使用的絕對 URL（皆可為 `null`，僅遠端書架匯入情境使用，
  /// 見 docs/epics/epic-30-calibre-remote-library/spec.md「既有匯入管線
  /// 擴充」）。
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
  });
```

修改 `app/lib/library/book_import_service_impl.dart`：

1. `importFiles()` 方法簽章與內部呼叫（`book_import_service_impl.dart:74-106`）：

```dart
  @override
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
  }) async {
    if (folderName != null) {
      await _repository.upsertGroup(folderName);
    }

    // 【診斷修正】見下方 _importSingleFile 前的重複偵測說明。
    final seenUris = await _existingFilePaths();
    final imported = <Book>[];
    var skippedDuplicateCount = 0;
    for (var i = 0; i < uris.length; i++) {
      final uri = uris[i];
      if (!seenUris.add(uri)) {
        skippedDuplicateCount++;
        continue;
      }
      final displayName =
          (displayNames != null && i < displayNames.length) ? displayNames[i] : null;
      final book = await _importSingleFile(
        uri,
        displayName: displayName,
        folderName: folderName,
        source: source,
        remoteServerId: remoteServerId,
        remoteBookId: remoteBookIds?[uri],
        remoteDownloadUrl: remoteDownloadUrls?[uri],
      );
      if (book != null) imported.add(book);
    }
    return ImportResult(
      importedBooks: imported,
      skippedDuplicateCount: skippedDuplicateCount,
    );
  }
```

2. `_importSingleFile` 方法簽章（`book_import_service_impl.dart:184-189`）新增參數：

```dart
  Future<Book?> _importSingleFile(
    String uri, {
    String? displayName,
    String? folderName,
    bool takePermission = true,
    BookSource source = BookSource.local,
    String? remoteServerId,
    String? remoteBookId,
    String? remoteDownloadUrl,
  }) async {
```

3. 方法末尾組裝 `Book(...)` 處（`book_import_service_impl.dart:382-402`），把硬編碼的 `source: BookSource.local,` 改為 `source: source,`，並新增 3 個欄位：

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
```

（`isDownloaded` 不需要在此顯式傳入——`Book` 建構子預設值 `true` 已符合「任何走完這條匯入管線的書都是已下載狀態」的語意，本機/雲端硬碟/遠端書架三種來源皆然。）

- [x] **Step 5: 執行測試確認全數通過**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: PASS——新增的 2 個測試通過，檔案內既有全部測試（本機匯入各格式情境）零回歸。

- [x] **Step 6: 執行全專案測試確認零回歸**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過（含 `importFolder()` 相關測試——`importFolder()` 本身未修改簽章，僅共用改動後的 `_importSingleFile`，其呼叫處未傳入新參數，全部使用預設值，行為不變）。

- [x] **Step 7: Commit**

```bash
git add app/lib/library/book_import_service.dart app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-30): BookImportService.importFiles() 擴充遠端書架參數"
```

---

## Self-Review（撰寫計畫後的檢查）

**1. Spec 覆蓋度**：對照 `spec.md`「資料模型與 Schema」（Task 1/2/3 涵蓋）、「既有匯入管線擴充」（Task 6 涵蓋）、「重複匯入偵測」所需的查詢方法（Task 5 涵蓋）、`issues.md` Issue 0 的 4 個條目（`remote_servers`/`books` 新欄位、`pubspec.yaml` 依賴提升、`importFiles()` 擴充、`LibraryRepository` 新方法）全數對應到任務，無缺漏。

**2. Placeholder 掃描**：全文無 TBD／「之後補上」／「適當的錯誤處理」等空話，所有程式碼片段皆為可直接貼上的完整 Dart/SQL 程式碼，測試皆有具體斷言。

**3. 型別一致性**：`Book(remoteServerId:, remoteBookId:, remoteDownloadUrl:, isDownloaded:)` 在 Task 2（定義）、Task 5（查詢方法讀取）、Task 6（`BookImportService` 組裝）三處用字一致；`findByRemoteBookId(String serverId, String remoteBookId)`／`findByContentFingerprint(String fingerprint)` 簽章在 Task 5 的介面／實作／Fake／測試四處一致；`importFiles()` 的 `remoteBookIds`/`remoteDownloadUrls` 皆為 `Map<String, String>?`（key 為 uri）在 Task 6 各處一致。

**4. 任務間依賴**：Task 1 的 Step 4 測試刻意設計為跨 Task（依賴 Task 2 的 `Book` 建構子），已在文中明確標註「先寫測試、確認編譯失敗、留到 Task 2 完成後才變綠燈」，避免被誤認為 Task 1 內部的錯誤。Task 3（`BookSource.calibreOpds`）雖然程式碼異動最小，但被 Task 2 的測試依賴（`source: BookSource.calibreOpds`），故排在 Task 2 之後、Task 5/6 之前，順序正確。

---

**Plan complete and saved to `docs/epics/epic-30-calibre-remote-library/plans/plan-issue-0.md`.** Two execution options:

**1. Subagent-Driven (recommended)** - 逐 Task 派遣新的 subagent 執行，每個 Task 完成後進行審查，快速迭代

**2. Inline Execution** - 在本次對話中直接依 Task 順序批次執行，每個 Task 結束設檢查點

**Which approach?**
