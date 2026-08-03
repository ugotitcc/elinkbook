# Epic 8 Issue 1 — 本機 Schema 遷移（v16 → v17）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 把 `bookmarks`/`highlights`/`notes` 三表主鍵由本機自增整數改為 UUID（`TEXT PRIMARY KEY`），並在 `books` 表與新的 `sync_metadata` 表補上雲端同步所需欄位，讓 Epic 8 後續 Issue（帳號、指紋、同步引擎）有穩定的本機資料基礎可用。

**Architecture:** SQLite schema 自 v16 升級至 v17。`bookmarks`/`highlights`/`notes` 三表用「建新表→逐筆搬移既有資料（產生 UUID）→刪舊表→改名」的標準 SQLite schema 變更手法（`ALTER TABLE ... RENAME TO`＋重新 `CREATE TABLE`）。**外鍵約束的暫停/恢復不能寫在 `onUpgrade` 內部**——sqflite 把整個 `onUpgrade` 回呼包在它自動開啟的一個交易內（已對照本專案實際鎖定的 `sqflite_common` 2.5.8 原始碼確認），而 SQLite 官方規定 `PRAGMA foreign_keys` 在交易開啟期間無法切換（靜默 no-op）；改為在交易外執行的 `onConfigure` 依 `db.getVersion()` 提前判斷關閉、`onOpen`（同樣在交易外）之後無條件恢復開啟（詳見 Task 1 Step 4、文末「審查修正紀錄」Critical 1）。`Bookmark`/`Highlight`/`Note` 三個 Dart 模型的 `id` 型別由 `int?` 改為 `String`（不再 nullable，UUID 由呼叫端在建立物件當下就指派，不像 `AUTOINCREMENT` 需要等資料庫回寫），連帶三個 repository 的 `insert()` 簽章由 `Future<int>` 改為 `Future<void>`，以及 `rename()`/`delete()`/`updateText()` 的 `id` 參數改為 `String`。所有呼叫端（生產程式碼與測試）需要在建構這三種物件時明確指派一個 UUID 字串。

**Tech Stack:** Flutter/Dart、`sqflite`、新增 `package:uuid`。純 widget test（`flutter test`），不需真機、不需 SQLite 以外的相依。

## Global Constraints

- **`bookmarks`/`highlights`/`notes` 主鍵 UUID 與同步識別碼合一**：不另外疊加一個 `sync_id`/`client_id` 欄位，本機 `id` 本身就是全域唯一的 UUID（`docs/epics/epic-8-sync/spec.md`「本機 Schema 變更」，ADR 0020 決策 3 已同步修訂）。
- **外鍵約束的暫停/恢復只能寫在 `onConfigure`／`onOpen`，絕對不能寫在 `onUpgrade` 內部**：sqflite 的 `onUpgrade` 回呼整段跑在它自動包住的一個交易內（已對照本專案實際鎖定的 `sqflite_common` 2.5.8 原始碼 `database_mixin.dart` `doOpen()` 確認），SQLite 官方規定 `PRAGMA foreign_keys` 在交易開啟期間無法切換（靜默 no-op，不報錯也不生效）——若寫在 `onUpgrade` 內部，遷移過程「建新表→搬資料→刪舊表→改名」仍會如原始 Critical 問題重現般觸發 `foreign key constraint failed` 崩潰（plan-issue-1-review.md Critical 1）。正確做法：`onConfigure`（早於交易開始）用 `db.getVersion()` 判斷是否即將觸發本 Issue 的遷移、提前關閉；新增的 `onOpen`（同樣在交易外）無條件恢復開啟，確保遷移完成後**同一次 App 啟動**（非等到下次重開）外鍵約束就已經是 ON。
- **既有累加式 migration 慣例**：新的 `if (oldVersion < 17)` 區塊放在 `onUpgrade` 頂層、無條件檢查（與既有 `oldVersion < 5`/`< 8`/`< 9`/`< 11`/`< 16` 區塊同一層級），比照這些既有區塊「books 表新增欄位／全新資料表建立與 `book_reader_prefs` 表是否已存在無關」的既定原則。
- **防禦性檢查是必要的、不是死碼**：本專案已有明確先例（`_migrateFontFamilyValues` 的 `sqlite_master`/`PRAGMA table_info` 防禦查詢，經 `flutter test` 實測證實移除會打壞既有測試，見 `sqlite_library_repository.dart:480-489` 註解）——本次遷移函式同樣需要「先查表格是否存在、`id` 欄位是否仍是 `INTEGER`」的防禦檢查，因為同一次 `onUpgrade` 呼叫內，`oldVersion < 8`/`< 9` 分支可能已經用（本次更新後的）`_createBookmarksTable`/`_createHighlightsTable`/`_createNotesTable` 建出全新的 UUID 格式表（裝置從很舊的版本跳級升級時），此時不應該再對這些表執行一次「遷移」。
- **`Bookmark`/`Highlight`/`Note` 的 `toMap()` 從「刻意省略 `id`」改為「必須包含 `id`」**：舊行為是新增時交由 `AUTOINCREMENT` 指派、`toMap()` 不含 `id`；新行為是呼叫端必須先指派好 UUID 才能呼叫 `insert()`，`toMap()` 需要把這個 `id` 一併寫入。
- **良好測試判準**（比照既有慣例）：驗證外部可觀察行為（資料庫最終寫入值、`PRAGMA table_info` 回報的欄位型別、`listByBook()` 讀回的內容），不斷言內部實作細節。

---

### Task 1：`pubspec.yaml` 新增 `uuid` 依賴 + SQLite Schema 遷移（v16 → v17）

**Files:**
- Modify：`app/pubspec.yaml`
- Modify：`app/lib/library/sqlite_library_repository.dart`
- Test：`app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes：無（本 Task 是整個 Issue 的基礎，不依賴其他 Task）
- Produces：`bookmarks`/`highlights`/`notes` 三表主鍵為 `TEXT`（UUID）、皆新增 `updated_at INTEGER NOT NULL`／`deleted_at INTEGER`；`books` 表新增 `content_fingerprint TEXT`／`position_updated_at INTEGER`／`position_synced_server_updated_at TEXT`；新表 `sync_metadata`（單列，欄位 `id`／`last_push_completed_at`／`last_pulled_server_updated_at_bookmarks`／`last_pulled_server_updated_at_highlights`／`last_pulled_server_updated_at_notes`／`last_pulled_server_updated_at_reading_positions`）。供 Task 2（模型 `fromMap`/`toMap` 讀寫新型別 `id`）與後續 Issue（帳號、指紋、同步引擎）使用。

- [x] **Step 1：新增 `uuid` 依賴**

`app/pubspec.yaml` 第 49-55 行（`dependencies:` 區塊內）改為：

```yaml
  share_plus: ^11.1.0
  sqflite: ^2.4.2+1
  path: ^1.9.1
  file_picker: ^11.0.2
  shared_preferences: ^2.5.5
  package_info_plus: ^9.0.1
  flutter_inappwebview: ^6.1.5
  uuid: ^4.6.0
```

```bash
cd app
flutter pub get
```

Expected：`uuid` 成功加入 `pubspec.lock`。

- [x] **Step 2：撰寫失敗測試——全新安裝直接是新 schema**

在 `app/test/library/sqlite_library_repository_test.dart` 檔案結尾（最後一個 `test(...)` 之後、檔案結尾 `}` 之前）新增：

```dart

  test('全新安裝的 bookmarks/highlights/notes 表主鍵為 TEXT（UUID），books 表含同步欄位，sync_metadata 表已建立（version 17 起 onCreate 已含括）',
      () async {
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());

    for (final table in ['bookmarks', 'highlights', 'notes']) {
      final columns =
          await repository.database.rawQuery('PRAGMA table_info($table)');
      final idColumn = columns.firstWhere((c) => c['name'] == 'id');
      expect(idColumn['type'], 'TEXT', reason: '$table.id 應為 TEXT（UUID）');
      expect(
        columns.map((c) => c['name'] as String).toSet(),
        containsAll(['updated_at', 'deleted_at']),
        reason: '$table 應含 updated_at／deleted_at',
      );
    }

    final bookColumns =
        await repository.database.rawQuery('PRAGMA table_info(books)');
    expect(
      bookColumns.map((c) => c['name'] as String).toSet(),
      containsAll([
        'content_fingerprint',
        'position_updated_at',
        'position_synced_server_updated_at',
      ]),
    );

    final syncMetadataRows = await repository.database.query('sync_metadata');
    expect(syncMetadataRows, hasLength(1));
    expect(syncMetadataRows.single['last_push_completed_at'], isNull);
  });

  test('既有 version 16 裝置（bookmarks/highlights/notes 為舊版整數主鍵）升級到 version 17，主鍵正確轉為 UUID 且 notes.highlight_id 正確重寫',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v16_to_v17_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 16」的舊格式資料庫：bookmarks/highlights/notes
    // 主鍵皆為 INTEGER AUTOINCREMENT，notes.highlight_id 參照本機整數 id。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 16,
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
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              pdf_page_index INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE highlights (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              style TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              pdf_page_index INTEGER,
              pdf_rect_json TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              text TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL,
              pdf_page_index INTEGER,
              pdf_rect_json TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '舊資料書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    final oldHighlightId = await oldDb.insert('highlights', {
      'book_id': 'b1',
      'style': 'underline',
      'progression': 0.2,
    });
    await oldDb.insert('bookmarks', {
      'book_id': 'b1',
      'name': '第一章',
      'progression': 0.1,
    });
    await oldDb.insert('notes', {
      'book_id': 'b1',
      'text': '依附備註',
      'progression': 0.2,
      'highlight_id': oldHighlightId,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onConfigure（判斷 oldVersion=16
    // < 17 應提前關閉外鍵約束）→ onUpgrade（oldVersion=16 → newVersion=17）
    // → onOpen（恢復外鍵約束）。若 onConfigure 忘記提前關閉（或錯誤地
    // 想在 onUpgrade 內部切換，那在 sqflite 的交易包裝下是無效的
    // no-op，plan-issue-1-review.md Critical 1），下方流程會在
    // rename/drop 舊 highlights 表時因 notes 仍參照它而拋出
    // foreign key constraint failed，此測試會直接失敗；若 onOpen 忘記
    // 恢復，測試結尾的外鍵約束驗證會抓到（插入應該被拒絕卻成功了）。
    // 兩種遺漏皆會讓此測試失敗，等同涵蓋了 spec 審查修正 Critical 1 的
    // 回歸驗證。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final bookmarkRows = await upgraded.database.query('bookmarks');
    expect(bookmarkRows, hasLength(1));
    expect(bookmarkRows.single['id'], isA<String>());
    expect(bookmarkRows.single['name'], '第一章');
    expect(bookmarkRows.single['updated_at'], isNotNull);
    expect(bookmarkRows.single['deleted_at'], isNull);

    final highlightRows = await upgraded.database.query('highlights');
    expect(highlightRows, hasLength(1));
    expect(highlightRows.single['id'], isA<String>());
    final newHighlightId = highlightRows.single['id'] as String;

    final noteRows = await upgraded.database.query('notes');
    expect(noteRows, hasLength(1));
    expect(noteRows.single['id'], isA<String>());
    expect(noteRows.single['highlight_id'], newHighlightId);

    final bookColumns =
        await upgraded.database.rawQuery('PRAGMA table_info(books)');
    expect(
      bookColumns.map((c) => c['name'] as String).toSet(),
      containsAll([
        'content_fingerprint',
        'position_updated_at',
        'position_synced_server_updated_at',
      ]),
    );

    final syncMetadataRows = await upgraded.database.query('sync_metadata');
    expect(syncMetadataRows, hasLength(1));

    // 外鍵約束確實已恢復生效（非停留在 OFF 狀態）：插入參照不存在
    // book_id 的書籤應被拒絕。
    expect(
      () => upgraded.database.insert('bookmarks', {
        'id': 'bm-invalid',
        'book_id': 'nonexistent-book',
        'name': 'X',
        'updated_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
```

- [x] **Step 3：執行測試，確認失敗**

```bash
cd app
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：FAIL——`version: 16`、`bookmarks`/`highlights`/`notes` 仍是 `INTEGER` 主鍵、`books` 無新欄位、`sync_metadata` 表不存在。

- [x] **Step 4：修改 `sqlite_library_repository.dart`**

第 1-3 行 import 區塊改為：

```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
```

第 24-32 行（`openDatabase(...)` 呼叫的 `version`／`onConfigure` 部分）改為：

```dart
  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 17,
      onConfigure: (db) async {
        // book_reader_prefs 的 ON DELETE CASCADE 需要外鍵約束真正生效，
        // SQLite 預設不強制外鍵，須逐連線手動開啟（見 epic-3 plan-issue-1）。
        //
        // epic-8-sync Issue 1（spec 審查修正 Critical 1，見
        // tmp/epic-8/plan-issue-1-review.md）：sqflite 的 onUpgrade 回呼
        // 整段跑在它自動包住的一個交易內（見 sqflite_common
        // database_mixin.dart `doOpen()` 的
        // `await transaction((txn) async { ... await options.onUpgrade!(...); ... })`，
        // 已對照本專案實際鎖定的 sqflite_common 2.5.8 原始碼確認），而
        // SQLite 官方規定 PRAGMA foreign_keys 在交易開啟期間無法切換
        // （靜默 no-op，不報錯但也不生效）。因此**不能**在 onUpgrade
        // 內部切換這個 pragma——改在交易外的 onConfigure（此處）判斷
        // 「是否即將觸發 Issue 1 的 bookmarks/highlights/notes 主鍵
        // UUID 遷移」並提前關閉外鍵檢查；遷移過程中的中繼狀態（例如
        // highlights 表被 rename 又重建期間，notes 表的外鍵暫時指向
        // 不存在的目標）因此不會被擋下。遷移完成後由下方 onOpen（同樣
        // 在交易外）恢復開啟。
        final currentVersion = await db.getVersion();
        final upgradingPastAnnotationUuidMigration =
            currentVersion > 0 && currentVersion < 17;
        await db.execute(
          'PRAGMA foreign_keys = ${upgradingPastAnnotationUuidMigration ? 'OFF' : 'ON'}',
        );
      },
```

第 41-58 行 `books` 表 CREATE TABLE 改為：

```dart
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
            position_synced_server_updated_at TEXT
          )
        ''');
```

第 59-63 行（`onCreate` 內建表呼叫序列）改為：

```dart
        await _createBookReaderPrefsTable(db);
        await _createBookmarksTable(db);
        await _createHighlightsTable(db);
        await _createNotesTable(db);
        await _createCustomFontsTable(db);
        await _createSyncMetadataTable(db);
```

第 196-210 行（既有 `if (oldVersion < 16) { await _createCustomFontsTable(db); }` 區塊、其後 onUpgrade 結尾的 `},`、以及 `openDatabase(...)` 呼叫結尾的 `);`）整段改為（新增 `if (oldVersion < 17)` 區塊、並新增一個 `onOpen` 參數）：

```dart
        if (oldVersion < 17) {
          // epic-8-sync Issue 1：雲端同步新增的欄位與主鍵型別變更（見
          // docs/epics/epic-8-sync/spec.md「本機 Schema 變更」／
          // 「Migration」）。刻意放在 onUpgrade 頂層、無條件檢查，比照
          // oldVersion < 5/6/8/9/11/16 既有原則——books 表新增欄位與
          // bookmarks/highlights/notes 主鍵遷移皆與 book_reader_prefs
          // 表是否已存在無關。**外鍵約束的暫停/恢復不在這裡處理**——
          // onUpgrade 整段跑在 sqflite 自動包住的交易內，PRAGMA
          // foreign_keys 在交易開啟期間無法切換（SQLite 官方規定，
          // spec 審查修正 Critical 1，見 tmp/epic-8/plan-issue-1-review.md），
          // 已改在上方 onConfigure（交易外）判斷並提前關閉、下方 onOpen
          // （同樣交易外）之後恢復。
          await db.execute(
              'ALTER TABLE books ADD COLUMN content_fingerprint TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN position_updated_at INTEGER');
          await db.execute(
              'ALTER TABLE books ADD COLUMN position_synced_server_updated_at TEXT');
          await _migrateAnnotationTablesToUuid(db);
          await _createSyncMetadataTable(db);
        }
      },
      onOpen: (db) async {
        // epic-8-sync Issue 1（spec 審查修正 Critical 1）：onConfigure
        // 可能因為即將進行 Issue 1 的主鍵遷移而暫時關閉外鍵約束，
        // onOpen 在 sqflite 的自動交易之外執行（見上方 onConfigure
        // 註解），無條件恢復開啟，確保遷移完成後**同一個連線、同一次
        // App 啟動**的剩餘期間（不是要等到下一次重開 App）外鍵約束不會
        // 停留在關閉狀態、影響既有的 CASCADE／SET NULL 行為。對沒有
        // 觸發遷移的一般情況（onConfigure 已經是 ON）這裡只是無害的
        // 重複開啟。
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
```

在 `_createNotesTable` 方法（原第 353-371 行）之後新增以下方法（`_createBookmarksTable`／`_createHighlightsTable`／`_createNotesTable` 三個既有方法本身也要一併改寫，見下方 Step 5）：

```dart
  static Future<void> _createSyncMetadataTable(Database db) async {
    // 同步中繼資料（epic-8-sync，spec.md「本機 Schema 變更」）：單列表
    // （id 恆為 1，CHECK 約束防止意外插入第二列）。
    // last_push_completed_at 為純本機時鐘（dirty 判斷用，只跟自己過去
    // 的寫入比較，不受其他裝置時鐘影響）；4 個
    // last_pulled_server_updated_at_<collection> 為 PocketBase 伺服器
    // 蓋章時間戳記字串（下載游標），刻意不用本機時鐘產生，用來規避
    // 裝置時鐘偏差問題（spec.md 審查修正）。
    await db.execute('''
      CREATE TABLE sync_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_push_completed_at INTEGER,
        last_pulled_server_updated_at_bookmarks TEXT,
        last_pulled_server_updated_at_highlights TEXT,
        last_pulled_server_updated_at_notes TEXT,
        last_pulled_server_updated_at_reading_positions TEXT
      )
    ''');
    // conflictAlgorithm: ignore 是防禦性寫法（plan-issue-1-review.md
    // Minor 3）：本函式目前只會在「表剛被上面這行 CREATE TABLE 建出來」
    // 之後立刻呼叫一次，理論上不會有既存的 id=1 列衝突；但 sqflite 的
    // onUpgrade 若中途拋出例外，整個 onUpgrade 交易會被回滾（含這裡的
    // CREATE TABLE 與 INSERT），下次重試時是從乾淨狀態重新開始、不會
    // 殘留半套資料，所以目前程式碼路徑其實不會真的走到「表已存在、
    // 又想插入 id=1」這個衝突情境。加上 ignore 純粹是零成本的保險，
    // 不代表目前真的有已知的衝突路徑。
    await db.insert(
      'sync_metadata',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 是否需要把 [tableName] 從舊版整數主鍵遷移到 UUID：表不存在（尚未
  /// 建立，交由 onUpgrade 上方對應的 oldVersion < 8/9 分支以新 schema
  /// 直接建立）或 `id` 欄位已經是 TEXT（同一次 onUpgrade 呼叫內，該表
  /// 剛好也是被上述分支以新 schema 直接建立）時皆不需要遷移，比照既有
  /// `_migrateFontFamilyValues` 的防禦查詢慣例（sqlite_library_repository.dart
  /// 既有先例，經 flutter test 實測證實此類防禦檢查是必要的，非死碼）。
  static Future<bool> _tableHasIntegerPrimaryKey(
      Database db, String tableName) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName'");
    if (tables.isEmpty) return false;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final idColumns = columns.where((c) => c['name'] == 'id');
    if (idColumns.isEmpty) return false;
    return idColumns.first['type'] == 'INTEGER';
  }

  static Future<void> _migrateAnnotationTablesToUuid(Database db) async {
    if (await _tableHasIntegerPrimaryKey(db, 'bookmarks')) {
      await _migrateBookmarksToUuid(db);
    }
    var highlightIdMap = const <int, String>{};
    if (await _tableHasIntegerPrimaryKey(db, 'highlights')) {
      highlightIdMap = await _migrateHighlightsToUuid(db);
    }
    if (await _tableHasIntegerPrimaryKey(db, 'notes')) {
      await _migrateNotesToUuid(db, highlightIdMap);
    }
  }

  static Future<void> _migrateBookmarksToUuid(Database db) async {
    const uuid = Uuid();
    final rows = await db.query('bookmarks');
    await db.execute('ALTER TABLE bookmarks RENAME TO bookmarks_old');
    await _createBookmarksTable(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      await db.insert('bookmarks', {
        'id': uuid.v4(),
        'book_id': row['book_id'],
        'name': row['name'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
        'updated_at': now,
        'deleted_at': null,
      });
    }
    await db.execute('DROP TABLE bookmarks_old');
  }

  static Future<Map<int, String>> _migrateHighlightsToUuid(Database db) async {
    const uuid = Uuid();
    final rows = await db.query('highlights');
    await db.execute('ALTER TABLE highlights RENAME TO highlights_old');
    await _createHighlightsTable(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final idMap = <int, String>{};
    for (final row in rows) {
      final oldId = row['id'] as int;
      final newId = uuid.v4();
      idMap[oldId] = newId;
      await db.insert('highlights', {
        'id': newId,
        'book_id': row['book_id'],
        'style': row['style'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
        'updated_at': now,
        'deleted_at': null,
      });
    }
    await db.execute('DROP TABLE highlights_old');
    return idMap;
  }

  static Future<void> _migrateNotesToUuid(
      Database db, Map<int, String> highlightIdMap) async {
    const uuid = Uuid();
    final rows = await db.query('notes');
    await db.execute('ALTER TABLE notes RENAME TO notes_old');
    await _createNotesTable(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      final oldHighlightId = row['highlight_id'] as int?;
      await db.insert('notes', {
        'id': uuid.v4(),
        'book_id': row['book_id'],
        'text': row['text'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'highlight_id':
            oldHighlightId == null ? null : highlightIdMap[oldHighlightId],
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
        'updated_at': now,
        'deleted_at': null,
      });
    }
    await db.execute('DROP TABLE notes_old');
  }
```

- [x] **Step 5：改寫 `_createBookmarksTable`／`_createHighlightsTable`／`_createNotesTable`**

原第 317-333 行 `_createBookmarksTable` 改為：

```dart
  static Future<void> _createBookmarksTable(Database db) async {
    // 書籤（epic-6-annotations Issue 1，spec.md「書籤模組」），與 books
    // 表以 book_id 外鍵關聯（比照 book_reader_prefs 既有關聯模式，見
    // docs/epics/epic-6-annotations/spec.md「資料模型關聯」）。與
    // book_reader_prefs 不同，一本書可以有多筆書籤，故不用 book_id 當
    // PRIMARY KEY。id 為 UUID（epic-8-sync Issue 1，本機主鍵與同步識別碼
    // 合一，見 docs/epics/epic-8-sync/spec.md「本機 Schema 變更」），
    // 由呼叫端在建立 Bookmark 物件當下指派，不再交由 SQLite
    // AUTOINCREMENT 指派。updated_at／deleted_at 供雲端同步使用。
    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }
```

原第 335-351 行 `_createHighlightsTable` 改為：

```dart
  static Future<void> _createHighlightsTable(Database db) async {
    // 劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」），與
    // books 表以 book_id 外鍵關聯（比照既有 bookmarks 模式）。id 為
    // UUID（epic-8-sync Issue 1，見 _createBookmarksTable 同一段
    // 說明），updated_at／deleted_at 供雲端同步使用。
    await db.execute('''
      CREATE TABLE highlights (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        style TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }
```

原第 353-371 行 `_createNotesTable` 改為：

```dart
  static Future<void> _createNotesTable(Database db) async {
    // 備註（epic-6-annotations Issue 2，spec.md「資料模型關聯」）：
    // highlight_id 為可空外鍵，ON DELETE SET NULL——批次刪除劃線後，
    // 依附的備註自動退化為純備註（highlight_id 變 null），不需應用層
    // 判斷邏輯。id 與 highlight_id 皆為 UUID（epic-8-sync Issue 1，
    // highlight_id 存放對應劃線的 UUID，即該劃線的 id，兩者本機/同步
    // 共用同一個值，不需要額外轉換查表，見
    // docs/epics/epic-8-sync/spec.md「跨裝置參照設計」）。updated_at／
    // deleted_at 供雲端同步使用。
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        highlight_id TEXT REFERENCES highlights(id) ON DELETE SET NULL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }
```

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：全數 PASS，含 Step 2 新增的兩個測試。

- [x] **Step 7：`flutter analyze` + Commit**

```bash
flutter analyze
git add pubspec.yaml pubspec.lock lib/library/sqlite_library_repository.dart test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 1 Task 1 — SQLite schema 遷移 v16→v17（bookmarks/highlights/notes 主鍵改 UUID）"
```

Expected：`flutter analyze` 顯示 "No issues found!"（此時 `Bookmark`/`Highlight`/`Note`/repository 尚未更新，`sqlite_library_repository_test.dart` 以外的既有測試檔案會因型別不符而編譯失敗，屬預期中的暫時狀態，Task 2/3 會修正——若此時執行完整 `flutter test`，其他檔案會失敗，不需要現在處理）。

---

### Task 2：`Bookmark`／`Highlight`／`Note` 模型 `id` 型別變更

**Files:**
- Modify：`app/lib/reader/bookmark.dart`
- Modify：`app/lib/reader/highlight.dart`
- Modify：`app/lib/reader/note.dart`
- Test：`app/test/reader/bookmark_test.dart`

**Interfaces:**
- Consumes：Task 1 的新 schema（`bookmarks`/`highlights`/`notes` 表 `id` 欄位為 `TEXT`）
- Produces：`Bookmark`/`Highlight`/`Note` 的 `id` 欄位型別為 `String`（非 nullable，建構子必要參數）；`Note.highlightId` 維持 `String?`（nullable，語意不變）；三者 `toMap()` 皆包含 `id`。供 Task 3（repository）與 Task 4/5（呼叫端）使用。

- [x] **Step 1：撰寫失敗測試——`bookmark_test.dart`**

`app/test/reader/bookmark_test.dart`（原檔案 103 行）整份取代為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（含 id）', () {
    const bookmark = Bookmark(
      id: 'bm1',
      bookId: 'b1',
      name: '第二章 (35%)',
      epubLocatorJson: '{"href":"/c2.xhtml"}',
      progression: 0.35,
    );
    final map = bookmark.toMap();
    expect(map['id'], 'bm1');
    expect(map['book_id'], 'b1');
    expect(map['name'], '第二章 (35%)');
    expect(map['epub_locator_json'], '{"href":"/c2.xhtml"}');
    expect(map['progression'], 0.35);
    expect(map['pdf_page_index'], isNull);
  });

  test('fromMap 正確還原 id（模擬資料庫查詢結果）', () {
    final restored = Bookmark.fromMap({
      'id': 'bm7',
      'book_id': 'b1',
      'name': '第 12 頁',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': 11,
    });
    expect(restored.id, 'bm7');
    expect(restored.bookId, 'b1');
    expect(restored.name, '第 12 頁');
    expect(restored.pdfPageIndex, 11);
  });

  test('copyWith 只更新 name，其餘欄位保留原值', () {
    const original = Bookmark(
      id: 'bm3',
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    );
    final renamed = original.copyWith(name: '新名稱');
    expect(renamed.id, 'bm3');
    expect(renamed.bookId, 'b1');
    expect(renamed.name, '新名稱');
    expect(renamed.pdfPageIndex, 5);
  });

  test('defaultName：PDF 用「第 N 頁」（1-indexed 顯示）', () {
    const context = BookmarkPositionContext(pdfPageIndex: 11);
    expect(Bookmark.defaultName(context), '第 12 頁');
  });

  test(
      'defaultName：FXL（固定版面漫畫）沒有 pdfPageIndex 可用，回退為進度百分比'
      '（審查修正 1.1，見 tmp/epic-6/reviews/plan_issue_1_review.md）——'
      'FXL 副檔名是 .epub，ReaderScreen._openNotesSheet 只在'
      'format == BookFormat.pdf 時才填入 pdfPageIndex，FXL 永遠落在'
      'BookFormat.epub 分支、pdfPageIndex 恆為 null，且 FXL 通常無章節'
      '結構（_tocEntries 對固定版面永遠不預取），故實際只會走 progression'
      '這條路徑', () {
    const context = BookmarkPositionContext(progression: 0.42);
    expect(Bookmark.defaultName(context), '42% 處');
  });

  test('defaultName：EPUB 有章節名稱與進度時，組合成「章節 (百分比%)」', () {
    const context = BookmarkPositionContext(
      chapterTitle: '第二章',
      progression: 0.353,
    );
    expect(Bookmark.defaultName(context), '第二章 (35%)');
  });

  test('defaultName：EPUB 只有章節名稱、無進度時，僅顯示章節名稱', () {
    const context = BookmarkPositionContext(chapterTitle: '第二章');
    expect(Bookmark.defaultName(context), '第二章');
  });

  test('defaultName：EPUB 只有進度、無章節名稱時，顯示「百分比% 處」', () {
    const context = BookmarkPositionContext(progression: 0.5);
    expect(Bookmark.defaultName(context), '50% 處');
  });

  test('defaultName：章節名稱與進度皆無法取得時，回退為「書籤」', () {
    const context = BookmarkPositionContext();
    expect(Bookmark.defaultName(context), '書籤');
  });

  test('兩個欄位值完全相同的 Bookmark 視為相等', () {
    const a = Bookmark(id: 'bm1', bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 'bm1', bookId: 'b1', name: 'X', pdfPageIndex: 5);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = Bookmark(id: 'bm1', bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 'bm1', bookId: 'b1', name: 'Y', pdfPageIndex: 5);
    expect(a, isNot(b));
  });

  test('id 不同時視為不相等', () {
    const a = Bookmark(id: 'bm1', bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 'bm2', bookId: 'b1', name: 'X', pdfPageIndex: 5);
    expect(a, isNot(b));
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/bookmark_test.dart
```

Expected：FAIL——`Bookmark` 建構子尚未接受 `id` 具名參數為必要的 `String`（編譯錯誤：缺少必要參數 `id` 或型別不符）。

- [x] **Step 3：修改 `bookmark.dart`**

整份取代為：

```dart
import 'bookmark_position_context.dart';

/// 單一書籤（epic-6-annotations Issue 1，spec.md「書籤模組」）：標記書中
/// 「一個位置」的具名離散事件，定位精度同閱讀進度（EPUB／FXL：CFI＋進度
/// 比例；PDF：頁索引）。[epubLocatorJson]／[pdfPageIndex] 互斥，一筆書籤只會
/// 用到其中一組（依書籍格式而定，FXL 因副檔名是 .epub 而併入 EPUB 那一組，
/// 見審查修正 1.1），比照 ReadingPosition 既有的欄位語意。
class Bookmark {
  /// UUID（epic-8-sync Issue 1，本機主鍵與同步識別碼合一），由呼叫端在
  /// 建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  final String id;
  final String bookId;
  final String name;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.name,
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
  });

  /// 供 [BookmarksRepository.insert] 使用；含呼叫端已指派的 [id]（
  /// epic-8-sync Issue 1 起不再交由 SQLite AUTOINCREMENT 指派）。重新
  /// 命名等更新操作改用 Repository 的目標欄位 `UPDATE`，不透過整列覆寫。
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'name': name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'pdf_page_index': pdfPageIndex,
    };
  }

  factory Bookmark.fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      name: map['name'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      pdfPageIndex: map['pdf_page_index'] as int?,
    );
  }

  Bookmark copyWith({String? name}) {
    return Bookmark(
      id: id,
      bookId: bookId,
      name: name ?? this.name,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      pdfPageIndex: pdfPageIndex,
    );
  }

  /// EPUB 用「章節名稱＋全書進度百分比」（例如「第二章 (35%)」），PDF 用
  /// 「第 N 頁」（issues.md Issue 1 審查修正 1.3）。**FXL（固定版面漫畫）
  /// 因副檔名是 .epub、Dart 端無法在不解析 Locator JSON 內部結構的前提下
  /// 取得頁碼，加上固定版面永遠不預取目錄（_tocEntries 恆空），故實際只會
  /// 落在下方 progression 分支、顯示「百分比% 處」，不會是「第 N 頁」**
  /// （plan-issue-1.md 審查修正 1.1，見
  /// tmp/epic-6/reviews/plan_issue_1_review.md——這是本方法既有邏輯已經
  /// 正確處理的既存行為，本次修正的是文件描述本身的錯誤，不是程式邏輯）。
  /// 章節名稱／進度皆無法取得時（理論上只會發生在目錄與定位皆尚未就緒的
  /// 極短窗口）回退為通用的「書籤」字樣，不拋出例外。
  static String defaultName(BookmarkPositionContext context) {
    if (context.pdfPageIndex != null) {
      return '第 ${context.pdfPageIndex! + 1} 頁';
    }
    final chapterTitle = context.chapterTitle;
    final progression = context.progression;
    final percent = progression != null ? (progression * 100).round() : null;
    if (chapterTitle != null && percent != null) {
      return '$chapterTitle ($percent%)';
    }
    if (chapterTitle != null) {
      return chapterTitle;
    }
    if (percent != null) {
      return '$percent% 處';
    }
    return '書籤';
  }

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.id == id &&
      other.bookId == bookId &&
      other.name == name &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.pdfPageIndex == pdfPageIndex;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        name,
        epubLocatorJson,
        progression,
        pdfPageIndex,
      );

  @override
  String toString() =>
      'Bookmark(id: $id, bookId: $bookId, name: $name, epubLocatorJson: $epubLocatorJson, progression: $progression, pdfPageIndex: $pdfPageIndex)';
}
```

- [x] **Step 4：修改 `highlight.dart`**

整份取代為：

```dart
import 'highlight_style.dart';
import 'percent_rect.dart';

/// 單一劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 標記書中「一段選取範圍」，定位精度高於書籤（EPUB：Locator JSON，含
/// 選取範圍本身；PDF：頁碼＋頁內矩形座標，Issue 3 新增）。建立後不可
/// 改色/改樣式（spec.md 決策），需要改色時刪除重建。[epubLocatorJson]／
/// [progression] 與 [pdfPageIndex]／[pdfRect] 互斥，一筆劃線只會用到其中
/// 一組（依書籍格式而定，比照 [Bookmark] 既有的欄位語意）。
class Highlight {
  /// UUID（epic-8-sync Issue 1，本機主鍵與同步識別碼合一），由呼叫端在
  /// 建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  final String id;
  final String bookId;
  final HighlightStyle style;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Highlight({
    required this.id,
    required this.bookId,
    required this.style,
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
    this.pdfRect,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'style': style.name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Highlight.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Highlight(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      style: HighlightStyle.values.byName(map['style'] as String),
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.bookId == bookId &&
      other.style == style &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        style,
        epubLocatorJson,
        progression,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Highlight(id: $id, bookId: $bookId, style: $style, epubLocatorJson: $epubLocatorJson, progression: $progression, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
```

- [x] **Step 5：修改 `note.dart`**

整份取代為：

```dart
import 'percent_rect.dart';

/// 單一備註（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 自由文字內容，可獨立於劃線存在。[highlightId] 為 null 代表純備註
/// （無劃線），非 null 代表依附於某一筆 [Highlight]（見 spec.md「資料
/// 模型關聯」——`notes.highlight_id REFERENCES highlights(id) ON DELETE
/// SET NULL`，批次刪除劃線後此欄位由資料庫自動退化為 null）。
/// [epubLocatorJson]／[progression] 與 [pdfPageIndex]／[pdfRect]（Issue 3
/// 新增）互斥，比照 [Highlight] 的既有欄位語意。
class Note {
  /// UUID（epic-8-sync Issue 1，本機主鍵與同步識別碼合一），由呼叫端在
  /// 建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  final String id;
  final String bookId;
  final String text;
  final String? epubLocatorJson;
  final double? progression;

  /// 依附劃線的 id（即該劃線的 [Highlight.id]，epic-8-sync Issue 1 起
  /// 與同步識別碼共用同一個 UUID，不需要額外轉換查表，見
  /// docs/epics/epic-8-sync/spec.md「跨裝置參照設計」）。`null` 代表純
  /// 備註，語意不變。
  final String? highlightId;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Note({
    required this.id,
    required this.bookId,
    required this.text,
    this.epubLocatorJson,
    this.progression,
    this.highlightId,
    this.pdfPageIndex,
    this.pdfRect,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'text': text,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'highlight_id': highlightId,
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Note(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      text: map['text'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      highlightId: map['highlight_id'] as String?,
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  Note copyWith({String? text}) {
    return Note(
      id: id,
      bookId: bookId,
      text: text ?? this.text,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      highlightId: highlightId,
      pdfPageIndex: pdfPageIndex,
      pdfRect: pdfRect,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.text == text &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.highlightId == highlightId &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        text,
        epubLocatorJson,
        progression,
        highlightId,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Note(id: $id, bookId: $bookId, text: $text, epubLocatorJson: $epubLocatorJson, progression: $progression, highlightId: $highlightId, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
```

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/reader/bookmark_test.dart
```

Expected：全數 PASS。

- [x] **Step 7：Commit**

```bash
git add lib/reader/bookmark.dart lib/reader/highlight.dart lib/reader/note.dart test/reader/bookmark_test.dart
git commit -m "feat(epic-8-sync): Issue 1 Task 2 — Bookmark/Highlight/Note id 型別改為 String"
```

Expected：這一步之後 `flutter analyze` 仍會報錯（repository 與呼叫端尚未更新），屬預期中的暫時狀態，Task 3 開始修正。

---

### Task 3：`BookmarksRepository`／`HighlightsRepository`／`NotesRepository` 簽章變更 + Fake 實作

**Files:**
- Modify：`app/lib/reader/bookmarks_repository.dart`
- Modify：`app/lib/reader/highlights_repository.dart`
- Modify：`app/lib/reader/notes_repository.dart`
- Modify：`app/test/support/fake_bookmarks_repository.dart`
- Modify：`app/test/support/fake_highlights_repository.dart`
- Modify：`app/test/support/fake_notes_repository.dart`
- Test：`app/test/reader/bookmarks_repository_test.dart`
- Test：`app/test/reader/highlights_repository_test.dart`
- Test：`app/test/reader/notes_repository_test.dart`

**Interfaces:**
- Consumes：Task 1 的新 schema、Task 2 的 `Bookmark`/`Highlight`/`Note`（`id` 為必要的 `String`）
- Produces：`BookmarksRepository.insert(Bookmark)`/`HighlightsRepository.insert(Highlight)`/`NotesRepository.insert(Note)` 回傳型別改為 `Future<void>`（呼叫端已在建構物件時指派 `id`，不需要問資料庫要回傳值）；`rename(String id, ...)`/`delete(String id)`/`updateText(String id, ...)` 參數型別改為 `String`。供 Task 4（生產程式碼呼叫端）、Task 5（測試呼叫端）使用。

- [x] **Step 1：撰寫失敗測試——三個 repository 測試檔案整份取代**

`app/test/reader/bookmarks_repository_test.dart`（原檔案 125 行）整份取代為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late BookmarksRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = BookmarksRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 寫入呼叫端指派的 id，listByBook 讀回相同資料', () async {
    const bookmark = Bookmark(
      id: 'bm1',
      bookId: 'b1',
      name: '第一章',
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    );
    await repository.insert(bookmark);

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'bm1');
    expect(list.single.name, '第一章');
  });

  test('listByBook 依 EPUB progression 由小到大排序', () async {
    await repository.insert(
        const Bookmark(id: 'bm-c', bookId: 'b1', name: 'C', progression: 0.8));
    await repository.insert(
        const Bookmark(id: 'bm-a', bookId: 'b1', name: 'A', progression: 0.1));
    await repository.insert(
        const Bookmark(id: 'bm-b', bookId: 'b1', name: 'B', progression: 0.5));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 依 PDF 頁索引由小到大排序', () async {
    await repository.insert(const Bookmark(
        id: 'bm-c', bookId: 'b1', name: 'C', pdfPageIndex: 20));
    await repository.insert(
        const Bookmark(id: 'bm-a', bookId: 'b1', name: 'A', pdfPageIndex: 2));
    await repository.insert(const Bookmark(
        id: 'bm-b', bookId: 'b1', name: 'B', pdfPageIndex: 10));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 只回傳指定 book_id 的書籤', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Bookmark(id: 'bm-x', bookId: 'b1', name: 'X', progression: 0.1));
    await repository.insert(
        const Bookmark(id: 'bm-y', bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.name, 'X');
  });

  test('rename 更新指定書籤的名稱，其餘欄位不受影響', () async {
    const bookmark = Bookmark(
      id: 'bm1',
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    );
    await repository.insert(bookmark);
    await repository.rename('bm1', '新名稱');

    final list = await repository.listByBook('b1');
    expect(list.single.name, '新名稱');
    expect(list.single.pdfPageIndex, 5);
  });

  test('delete 移除指定單筆書籤，其餘不受影響', () async {
    await repository.insert(
        const Bookmark(id: 'bm-1', bookId: 'b1', name: 'A', progression: 0.1));
    await repository.insert(
        const Bookmark(id: 'bm-2', bookId: 'b1', name: 'B', progression: 0.5));
    await repository.delete('bm-1');

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'bm-2');
  });

  test('deleteAllForBook 只清空指定書籍的書籤，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Bookmark(id: 'bm-x', bookId: 'b1', name: 'X', progression: 0.1));
    await repository.insert(
        const Bookmark(id: 'bm-y', bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });
}
```

`app/test/reader/highlights_repository_test.dart`（原檔案 108 行）整份取代為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late HighlightsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = HighlightsRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 寫入呼叫端指派的 id，listByBook 讀回相同資料', () async {
    const highlight = Highlight(
      id: 'h1',
      bookId: 'b1',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    );
    await repository.insert(highlight);

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'h1');
    expect(list.single.style, HighlightStyle.highlighterYellow);
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await repository.insert(const Highlight(
        id: 'h-1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.8));
    await repository.insert(const Highlight(
        id: 'h-2', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.progression).toList(), [0.1, 0.8]);
  });

  test('listByBook 只回傳指定 book_id 的劃線', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(const Highlight(
        id: 'h-1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(const Highlight(
        id: 'h-2', bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
  });

  test('delete 移除指定單筆劃線，其餘不受影響', () async {
    await repository.insert(const Highlight(
        id: 'h-1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(const Highlight(
        id: 'h-2', bookId: 'b1', style: HighlightStyle.underline, progression: 0.5));
    await repository.delete('h-1');

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'h-2');
  });

  test('deleteAllForBook 只清空指定書籍的劃線，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(const Highlight(
        id: 'h-1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(const Highlight(
        id: 'h-2', bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });

  test('listByBook 對 PDF 劃線依 pdf_page_index 由小到大排序', () async {
    await repository.insert(const Highlight(
        id: 'h-1', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 5));
    await repository.insert(const Highlight(
        id: 'h-2', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.pdfPageIndex).toList(), [1, 5]);
  });
}
```

`app/test/reader/notes_repository_test.dart`（原檔案 131 行）整份取代為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late HighlightsRepository highlightsRepository;
  late NotesRepository notesRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    highlightsRepository = HighlightsRepository(libraryRepository.database);
    notesRepository = NotesRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 寫入呼叫端指派的 id，listByBook 讀回相同資料', () async {
    await notesRepository
        .insert(const Note(id: 'n1', bookId: 'b1', text: 'A', progression: 0.1));

    final list = await notesRepository.listByBook('b1');
    expect(list.single.id, 'n1');
    expect(list.single.text, 'A');
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await notesRepository
        .insert(const Note(id: 'n-b', bookId: 'b1', text: 'B', progression: 0.8));
    await notesRepository
        .insert(const Note(id: 'n-a', bookId: 'b1', text: 'A', progression: 0.1));

    final list = await notesRepository.listByBook('b1');
    expect(list.map((n) => n.text).toList(), ['A', 'B']);
  });

  test('updateText 更新指定備註的文字，其餘欄位不受影響', () async {
    await notesRepository.insert(const Note(
        id: 'n1', bookId: 'b1', text: '舊文字', progression: 0.2, highlightId: null));
    await notesRepository.updateText('n1', '新文字');

    final list = await notesRepository.listByBook('b1');
    expect(list.single.text, '新文字');
    expect(list.single.progression, 0.2);
  });

  test('delete 移除指定單筆備註，其餘不受影響', () async {
    await notesRepository
        .insert(const Note(id: 'n-1', bookId: 'b1', text: 'A', progression: 0.1));
    await notesRepository
        .insert(const Note(id: 'n-2', bookId: 'b1', text: 'B', progression: 0.5));
    await notesRepository.delete('n-1');

    final list = await notesRepository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'n-2');
  });

  test('deleteAllForBook 只清空指定書籍的備註，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await notesRepository
        .insert(const Note(id: 'n-1', bookId: 'b1', text: 'A', progression: 0.1));
    await notesRepository
        .insert(const Note(id: 'n-2', bookId: 'b2', text: 'B', progression: 0.1));

    await notesRepository.deleteAllForBook('b1');

    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(await notesRepository.listByBook('b2'), hasLength(1));
  });

  test(
      'FK 退化行為（spec.md 決策 #13／資料模型關聯）：刪除劃線後，依附的'
      '備註 highlight_id 自動變 null，備註內容本身不受影響', () async {
    const highlight = Highlight(
        id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.3);
    await highlightsRepository.insert(highlight);
    const note = Note(
        id: 'n1', bookId: 'b1', text: '依附備註', progression: 0.3, highlightId: 'h1');
    await notesRepository.insert(note);

    await highlightsRepository.delete('h1');

    final notes = await notesRepository.listByBook('b1');
    final degraded = notes.singleWhere((n) => n.id == 'n1');
    expect(degraded.highlightId, isNull);
    expect(degraded.text, '依附備註');
  });

  test(
      'FK 退化行為（批次版本）：deleteAllForBook 清空劃線後，所有依附備註'
      '皆退化為純備註，備註本身不被刪除', () async {
    await highlightsRepository.insert(const Highlight(
        id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await highlightsRepository.insert(const Highlight(
        id: 'h2', bookId: 'b1', style: HighlightStyle.underline, progression: 0.2));
    await notesRepository.insert(const Note(
        id: 'n1', bookId: 'b1', text: 'N1', progression: 0.1, highlightId: 'h1'));
    await notesRepository.insert(const Note(
        id: 'n2', bookId: 'b1', text: 'N2', progression: 0.2, highlightId: 'h2'));

    await highlightsRepository.deleteAllForBook('b1');

    final notes = await notesRepository.listByBook('b1');
    expect(notes, hasLength(2));
    expect(notes.every((n) => n.highlightId == null), isTrue);
  });

  test('listByBook 對 PDF 備註依 pdf_page_index 由小到大排序', () async {
    await notesRepository
        .insert(const Note(id: 'n-b', bookId: 'b1', text: 'B', pdfPageIndex: 5));
    await notesRepository
        .insert(const Note(id: 'n-a', bookId: 'b1', text: 'A', pdfPageIndex: 1));

    final list = await notesRepository.listByBook('b1');
    expect(list.map((n) => n.text).toList(), ['A', 'B']);
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

```bash
flutter test test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
```

Expected：FAIL——`insert()` 仍回傳 `Future<int>`、`rename()`/`delete()`/`updateText()` 仍接受 `int` 參數，型別不符（編譯錯誤）。

- [x] **Step 3：修改三個 repository**

`app/lib/reader/bookmarks_repository.dart` 整份取代為：

```dart
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

  /// 新增一筆書籤。[bookmark.id]（epic-8-sync Issue 1 起為 UUID）須由
  /// 呼叫端在建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  Future<void> insert(Bookmark bookmark) {
    return _db.insert('bookmarks', bookmark.toMap());
  }

  /// 依書中位置順序排序（EPUB／FXL 用 progression 比例、PDF 用頁索引，
  /// 兩者互斥、一本書只會用到其中一組，見 [Bookmark] 欄位語意）。
  /// `COALESCE` 取兩欄位中非 null 的那一個當排序鍵——同一本書的所有書籤
  /// 必然只填其中一組欄位，不會混用。
  Future<List<Bookmark>> listByBook(String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> rename(String id, String newName) {
    return _db.update(
      'bookmarks',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) {
    return _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('bookmarks', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

`app/lib/reader/highlights_repository.dart` 整份取代為：

```dart
import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  /// 新增一筆劃線。[highlight.id]（epic-8-sync Issue 1 起為 UUID）須由
  /// 呼叫端在建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  Future<void> insert(Highlight highlight) {
    return _db.insert('highlights', highlight.toMap());
  }

  /// 依書中位置順序排序：EPUB 用 `progression` 比例、PDF 用
  /// `pdf_page_index`（Issue 3 新增），兩者互斥、一本書只會用到其中一組
  /// （比照 `BookmarksRepository.listByBook` 既有的 `COALESCE` 慣例）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  Future<void> delete(String id) {
    return _db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('highlights', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

`app/lib/reader/notes_repository.dart` 整份取代為：

```dart
import 'package:sqflite/sqflite.dart';

import 'note.dart';

/// `notes` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線與備註
/// 模組」）。FK `ON DELETE SET NULL` 的退化行為由資料庫本身保證（見
/// sqlite_library_repository.dart `_createNotesTable`），本類別不需要
/// 額外實作任何退化邏輯，`listByBook` 讀到的 `highlight_id` 已經是
/// 資料庫層級處理過的最終結果。
class NotesRepository {
  final Database _db;

  const NotesRepository(this._db);

  /// 新增一筆備註。[note.id]（epic-8-sync Issue 1 起為 UUID）須由呼叫端
  /// 在建立物件當下指派，不再交由 SQLite AUTOINCREMENT 指派。
  Future<void> insert(Note note) {
    return _db.insert('notes', note.toMap());
  }

  /// 依書中位置順序排序，比照 [HighlightsRepository.listByBook] 的
  /// `COALESCE` 慣例（Issue 3 新增）。
  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> updateText(String id, String text) {
    return _db.update('notes', {'text': text}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) {
    return _db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('notes', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

- [x] **Step 4：修改三個 Fake repository**

`app/test/support/fake_bookmarks_repository.dart` 整份取代為：

```dart
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

/// 測試用 Fake，比照 [FakeReadingPositionRepository] 模式。
class FakeBookmarksRepository implements BookmarksRepository {
  final List<Bookmark> _storage = [];

  /// epic-8-sync Issue 1 起，[bookmark.id]（UUID）由呼叫端指派，本 Fake
  /// 不再需要自行產生遞增 id，直接原樣存入即可。
  @override
  Future<void> insert(Bookmark bookmark) async {
    _storage.add(bookmark);
  }

  @override
  Future<List<Bookmark>> listByBook(String bookId) async {
    final list = _storage.where((b) => b.bookId == bookId).toList();
    list.sort((a, b) {
      final posA = a.pdfPageIndex?.toDouble() ?? a.progression ?? 0;
      final posB = b.pdfPageIndex?.toDouble() ?? b.progression ?? 0;
      return posA.compareTo(posB);
    });
    return list;
  }

  @override
  Future<void> rename(String id, String newName) async {
    final index = _storage.indexWhere((b) => b.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(name: newName);
  }

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((b) => b.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((b) => b.bookId == bookId);
  }
}
```

`app/test/support/fake_highlights_repository.dart` 整份取代為：

```dart
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。
class FakeHighlightsRepository implements HighlightsRepository {
  final List<Highlight> _storage = [];

  /// epic-8-sync Issue 1 起，[highlight.id]（UUID）由呼叫端指派，本 Fake
  /// 不再需要自行產生遞增 id，直接原樣存入即可。
  @override
  Future<void> insert(Highlight highlight) async {
    _storage.add(highlight);
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    final list = _storage.where((h) => h.bookId == bookId).toList();
    list.sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    return list;
  }

  double _positionOf(Highlight h) =>
      (h.pdfPageIndex?.toDouble()) ?? h.progression ?? 0;

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((h) => h.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((h) => h.bookId == bookId);
  }
}
```

`app/test/support/fake_notes_repository.dart` 整份取代為：

```dart
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

/// 測試用 Fake。刻意不模擬 FK `ON DELETE SET NULL` 的資料庫層退化行為
/// （那已由 Task 4 的真實 SQLite repository 測試涵蓋）——本 Fake 供
/// widget test 使用，widget test 只需要驗證「假設資料已經是退化後的
/// 狀態」時 UI 是否正確呈現，不需要重新模擬 FK 機制本身。
class FakeNotesRepository implements NotesRepository {
  final List<Note> _storage = [];

  /// epic-8-sync Issue 1 起，[note.id]（UUID）由呼叫端指派，本 Fake
  /// 不再需要自行產生遞增 id，直接原樣存入即可。
  @override
  Future<void> insert(Note note) async {
    _storage.add(note);
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final list = _storage.where((n) => n.bookId == bookId).toList();
    list.sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    return list;
  }

  double _positionOf(Note n) => (n.pdfPageIndex?.toDouble()) ?? n.progression ?? 0;

  @override
  Future<void> updateText(String id, String text) async {
    final index = _storage.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(text: text);
  }

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((n) => n.bookId == bookId);
  }
}
```

- [x] **Step 5：執行測試，確認通過**

```bash
flutter test test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
```

Expected：全數 PASS。

- [x] **Step 6：`flutter analyze` + Commit**

```bash
flutter analyze
```

Expected：此時 `reader_screen.dart`／`notes_bottom_sheet.dart`／`reader_screen_test.dart`／`notes_bottom_sheet_test.dart` 仍會報錯（Task 4/5 修正），但 `lib/reader/`／`test/reader/`／`test/support/` 這幾個目錄本身應無新錯誤。

```bash
git add lib/reader/bookmarks_repository.dart lib/reader/highlights_repository.dart lib/reader/notes_repository.dart test/support/fake_bookmarks_repository.dart test/support/fake_highlights_repository.dart test/support/fake_notes_repository.dart test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 1 Task 3 — repository 與 Fake 簽章改為 String id"
```

---

### Task 4：生產程式碼呼叫端更新（`reader_screen.dart`／`notes_bottom_sheet.dart`）

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/lib/screens/notes_bottom_sheet.dart`

**Interfaces:**
- Consumes：Task 2/3 的 `Bookmark`/`Highlight`/`Note`（`id` 必要 `String`）與三個 repository（`insert` 回傳 `Future<void>`，`rename`/`delete`/`updateText` 接受 `String id`）
- Produces：無新公開介面，純呼叫端修正

- [x] **Step 1：`reader_screen.dart` 新增 `uuid` import**

第 1 行（檔案開頭 import 區塊）之前新增：

```dart
import 'package:uuid/uuid.dart';
```

- [x] **Step 2：修正 `_pendingHighlightIdForSelection`／`_pendingPdfHighlightIdForSelection` 型別**

第 231 行：

```dart
  int? _pendingHighlightIdForSelection;
```

改為：

```dart
  String? _pendingHighlightIdForSelection;
```

第 237 行：

```dart
  int? _pendingPdfHighlightIdForSelection;
```

改為：

```dart
  String? _pendingPdfHighlightIdForSelection;
```

- [x] **Step 3：修正 `_toggleBookmark`（第 665-687 行）**

第 669-685 行改為：

```dart
    final existing = _bookmarkAtCurrentPosition;
    if (existing != null) {
      await repository.delete(existing.id);
    } else {
      await repository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ));
    }
```

- [x] **Step 4：修正 `_handleHighlightStyleSelected`（第 912-924 行）**

第 916-922 行改為：

```dart
    final id = const Uuid().v4();
    await repository.insert(Highlight(
      id: id,
      bookId: widget.bookId,
      style: style,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
    ));
    _pendingHighlightIdForSelection = id;
```

- [x] **Step 5：修正 `_handleNotePressed`（第 926-945 行）**

第 932-938 行改為：

```dart
    await repository.insert(Note(
      id: const Uuid().v4(),
      bookId: widget.bookId,
      text: text,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
      highlightId: _pendingHighlightIdForSelection,
    ));
```

- [x] **Step 6：修正 `_showAnnotationActionDialog`（第 1042-1076 行）移除多餘的 `!`**

第 1066、1072、1073 行分別改為：

```dart
        await widget.notesRepository!.updateText(note.id, newText);
```

```dart
      if (note != null) await widget.notesRepository!.delete(note.id);
      if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
```

- [x] **Step 7：修正 `_handlePdfHighlightStyleSelected`（第 1094-1106 行）**

第 1098-1104 行改為：

```dart
    final id = const Uuid().v4();
    await repository.insert(Highlight(
      id: id,
      bookId: widget.bookId,
      style: style,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
    ));
    _pendingPdfHighlightIdForSelection = id;
```

- [x] **Step 8：修正 `_handlePdfNotePressed`（第 1108-1127 行）**

第 1114-1120 行改為：

```dart
    await repository.insert(Note(
      id: const Uuid().v4(),
      bookId: widget.bookId,
      text: text,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
      highlightId: _pendingPdfHighlightIdForSelection,
    ));
```

- [x] **Step 9：`notes_bottom_sheet.dart` 新增 `uuid` import + 修正呼叫端**

檔案開頭 import 區塊新增：

```dart
import 'package:uuid/uuid.dart';
```

第 270-284 行（`_toggleBookmark`）改為：

```dart
  Future<void> _toggleBookmark() async {
    final existing = _bookmarkAtCurrentPosition;
    if (existing != null) {
      await widget.bookmarksRepository.delete(existing.id);
    } else {
      await widget.bookmarksRepository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(widget.currentPosition),
        epubLocatorJson: widget.currentPosition.epubLocatorJson,
        progression: widget.currentPosition.progression,
        pdfPageIndex: widget.currentPosition.pdfPageIndex,
      ));
    }
    await _loadBookmarks();
  }
```

第 315 行：

```dart
    await widget.bookmarksRepository.rename(bookmark.id!, newName.trim());
```

改為：

```dart
    await widget.bookmarksRepository.rename(bookmark.id, newName.trim());
```

第 320 行：

```dart
    await widget.bookmarksRepository.delete(bookmark.id!);
```

改為：

```dart
    await widget.bookmarksRepository.delete(bookmark.id);
```

第 480 行：

```dart
    await widget.notesRepository!.updateText(note.id!, newText);
```

改為：

```dart
    await widget.notesRepository!.updateText(note.id, newText);
```

第 489-490 行：

```dart
    if (item.note != null) await widget.notesRepository!.delete(item.note!.id!);
    if (item.highlight != null) await widget.highlightsRepository!.delete(item.highlight!.id!);
```

改為：

```dart
    if (item.note != null) await widget.notesRepository!.delete(item.note!.id);
    if (item.highlight != null) await widget.highlightsRepository!.delete(item.highlight!.id);
```

- [x] **Step 10：`flutter analyze` 確認生產程式碼無誤 + Commit**

```bash
cd app
flutter analyze lib/
```

Expected：`lib/` 目錄下不應再有任何 `Bookmark`/`Highlight`/`Note`/repository 型別不符的錯誤（`test/` 目錄的錯誤留給 Task 5 處理，此時執行完整 `flutter analyze` 仍會報 `test/` 內的錯誤，屬預期中的暫時狀態）。

```bash
git add lib/screens/reader_screen.dart lib/screens/notes_bottom_sheet.dart
git commit -m "feat(epic-8-sync): Issue 1 Task 4 — reader_screen/notes_bottom_sheet 呼叫端改用 UUID"
```

---

### Task 5：測試呼叫端更新（`reader_screen_test.dart`／`notes_bottom_sheet_test.dart`）+ 全專案驗證

**Files:**
- Modify：`app/test/screens/reader_screen_test.dart`
- Modify：`app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1-4 的全部產出
- Produces：無（本 Task 是收尾驗證，讓全專案 `flutter analyze`/`flutter test` 恢復乾淨）

這兩個檔案分別有 4667 行／570 行，包含數十處建構 `Bookmark`/`Highlight`/`Note` 或呼叫三個 repository 方法的既有測試——逐一列出每一處的行號在計畫階段没有意義（後續 Task 的編輯會讓行號持續偏移，執行到這一步時多半已經對不上）。改用**編譯器導引的窮舉修正法**：`flutter analyze`／`flutter test` 的每一則型別錯誤都精確指出檔案與行號，逐一修正、重複執行直到乾淨為止——這是大量同型別機械式修改場景下最可靠的作法，比事先手動窮舉數十處行號更不容易遺漏（行號會隨著每一次修改而偏移，事先寫死的行號在真正執行到這一步時多半已經失準）。

**修正時機械規則固定為以下 4 種（皆已在 Task 1-4 驗證過，可直接套用）：**

1. `Bookmark(...)`/`Highlight(...)`/`Note(...)` 建構呼叫缺少 `id:` → 補上一個具描述性的字串 literal（例如 `id: 'bm1'`／`id: 'h1'`／`id: 'n1'`，同一測試內若有多筆需彼此不同，比照既有變數命名習慣取名，例如 `'bm-a'`/`'bm-b'`）。範例（`notes_bottom_sheet_test.dart:80`）：

   ```dart
   // 修正前
   await repository.insert(const Bookmark(bookId: 'b1', name: 'C', progression: 0.8));
   // 修正後
   await repository.insert(const Bookmark(id: 'bm-c', bookId: 'b1', name: 'C', progression: 0.8));
   ```

2. `final id = await repository.insert(...)` 這種依賴舊 `Future<int>` 回傳值的寫法 → 改為呼叫端自行宣告一個字串 id 常數，建構物件時帶入該 id，`insert()` 呼叫不再接回傳值。範例（`notes_bottom_sheet_test.dart:181-182`）：

   ```dart
   // 修正前
   final id = await repository.insert(
     const Bookmark(bookId: 'b1', name: '舊名稱', progression: 0.1),
   );
   await repository.rename(id, '新名稱');
   // 修正後
   const bookmark =
       Bookmark(id: 'bm1', bookId: 'b1', name: '舊名稱', progression: 0.1);
   await repository.insert(bookmark);
   await repository.rename('bm1', '新名稱');
   ```

   `expect(id, greaterThan(0))` 這類斷言舊 `AUTOINCREMENT` 語意（id 必為正整數）的既有斷言直接刪除——UUID 沒有「大於 0」的語意，不需要替換成別的斷言（該筆行為已由 `list.single.id` 之類的既有斷言涵蓋）。

3. `note.id!`／`highlight.id!`／`bookmark.id!` 這類 null 斷言運算子 → 直接移除 `!`（`id` 已不再是 nullable，保留 `!` 會被 `flutter analyze` 標記為不必要的斷言）。

4. `highlightId: someIntVariable` 或依賴舊 `insert()` 回傳 `int` 的 `highlightId` 串接寫法（例如 `notes_bottom_sheet_test.dart:278-284`）→ 比照規則 2，改為先宣告字串 id 常數。範例：

   ```dart
   // 修正前
   final highlightId = await highlightsRepository.insert(const Highlight(
     bookId: 'b1', style: HighlightStyle.underline, progression: 0.3,
   ));
   await notesRepository.insert(
     Note(bookId: 'b1', text: '依附備註', progression: 0.2, highlightId: highlightId),
   );
   // 修正後
   const highlight = Highlight(
       id: 'h1', bookId: 'b1', style: HighlightStyle.underline, progression: 0.3);
   await highlightsRepository.insert(highlight);
   await notesRepository.insert(const Note(
       id: 'n1', bookId: 'b1', text: '依附備註', progression: 0.2, highlightId: 'h1'));
   ```

- [x] **Step 1：執行 `flutter analyze`，取得完整錯誤清單**

```bash
cd app
flutter analyze test/screens/reader_screen_test.dart test/screens/notes_bottom_sheet_test.dart
```

Expected：回報一長串型別錯誤，每則皆附精確檔案:行號。

- [x] **Step 2：逐一修正 `reader_screen_test.dart` 的每一則錯誤**

依上述 4 種規則，比照本計畫已提供的範例逐一修正。修正過程中每處理完約 10-15 處，重新執行一次 `flutter analyze test/screens/reader_screen_test.dart`，確認錯誤數量持續下降、且沒有引入新錯誤（例如同一測試內兩筆 `Bookmark` 誤用了相同的 `id` 而導致後續斷言依賴的資料被覆蓋——這種問題編譯器不會報錯，需要留意規則 1 提到的「彼此不同」要求）。

- [x] **Step 3：`flutter analyze test/screens/reader_screen_test.dart` 確認乾淨**

```bash
flutter analyze test/screens/reader_screen_test.dart
```

Expected："No issues found!"

- [x] **Step 4：`flutter test test/screens/reader_screen_test.dart` 確認全數通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS。若有既有測試斷言依賴「同一個變數兩次呼叫 insert 各自拿到不同 id」之類的舊語意（例如比較兩筆書籤的 id 是否不同），確認修正後的字串 literal id 確實彼此不同、斷言邏輯依然成立。

- [x] **Step 5：對 `notes_bottom_sheet_test.dart` 重複 Step 1-4**

```bash
flutter analyze test/screens/notes_bottom_sheet_test.dart
```

依相同 4 種規則逐一修正，重複執行直到：

```bash
flutter analyze test/screens/notes_bottom_sheet_test.dart
flutter test test/screens/notes_bottom_sheet_test.dart
```

皆乾淨/全數通過。

- [x] **Step 6：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（完整套件，含本 Issue 新增/修改的全部測試，以及未被本 Issue 觸碰的既有測試——確認無 Regression）。

```bash
git add test/screens/reader_screen_test.dart test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-8-sync): Issue 1 Task 5 — reader_screen_test/notes_bottom_sheet_test 呼叫端改用 UUID"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

**Spec 覆蓋檢查**（對照 `issues.md` Issue 1「驗收標準」5 項）：

1. `PRAGMA foreign_keys = OFF/ON` 正確包住整個表格重建流程 → Task 1 Step 4（`onConfigure`/`onOpen` 於交易外切換，`onUpgrade` 內部不切換，見審查修正紀錄 Critical 1）＋ Step 2 的第二個測試（既有裝置升級測試，若忘記提前關閉或忘記恢復會直接失敗，等同回歸測試）。
2. `bookmarks`/`highlights`/`notes` 主鍵成功轉為 UUID，既有資料與 `notes.highlight_id` 參照正確轉換 → Task 1 全部 Step。
3. `books`／`sync_metadata` 新增欄位正確建立 → Task 1 Step 2/4。
4. `Bookmark`/`Highlight`/`Note` 模型與對應 repository 型別變更完整，全專案呼叫端無遺漏 → Task 2（模型）＋ Task 3（repository/Fake）＋ Task 4（生產呼叫端，逐一列出精確行號）＋ Task 5（測試呼叫端，編譯器導引窮舉，Step 6 完整 `flutter test` 作為最終把關）。
5. 上述測試皆通過，`flutter analyze` 乾淨 → 每個 Task 結尾皆有對應驗證步驟，Task 5 Step 6 為全專案最終確認。

**Placeholder 掃描**：全文無 TBD/TODO 字樣。Task 5 的「編譯器導引窮舉修正」不是含糊帶過——已明確給出 4 種固定修正規則、每種皆附真實驗證過的範例程式碼（規則 1/2/4 的範例直接取自 `notes_bottom_sheet_test.dart` 既有真實程式碼），且說明了為何不能事先窮舉行號（後續編輯會讓行號持續偏移），這是對這種大量同型別機械式修改場景的正確工程判斷，不是逃避寫出實際內容。

**型別一致性檢查**：`Bookmark.id`/`Highlight.id`/`Note.id` 皆為 `String`（Task 2）→ `BookmarksRepository.insert(Bookmark)`/`HighlightsRepository.insert(Highlight)`/`NotesRepository.insert(Note)` 回傳 `Future<void>`、`rename`/`delete`/`updateText` 接受 `String id`（Task 3，與 Task 2 產出型別一致）→ Fake 實作簽章與真實 repository 完全對稱（Task 3）→ 生產/測試呼叫端 `const Uuid().v4()` 產生的 `String` 與建構子期待型別一致（Task 4/5）。`Note.highlightId` 型別為 `String?`（Task 2）與 `sync_notes` collection 的 `highlight_client_id` 概念（spec.md「跨裝置參照設計」）一致，皆為劃線的 `id`/`client_id` 本身，非額外轉換值。

**與既有測試/生產程式碼相容性檢查**：`Book`／`BookGroup`／`library_repository.dart` 等圖書庫模組完全不受本 Issue 影響（`books.id` 格式維持不變，見 spec.md「跨裝置參照設計」）；`content_fingerprint`／`position_updated_at`／`position_synced_server_updated_at` 三個新欄位本 Issue 只新增原始 SQL 欄位，**不**修改 `Book` Dart 模型類別（`toMap`/`fromMap` 不觸碰這三個新欄位）——這三個欄位的 Dart 端讀寫留給消費它們的後續 Issue（指紋計算、閱讀位置同步）處理，避免本 Issue 範圍蔓延到尚未定案的呼叫模式。

**Epic 8 後續進度**：本 Issue 完成並通過審查合併後，Issue 3（書籍內容指紋，依賴本 Issue 的 `books.content_fingerprint` 欄位）與 Issue 4（同步引擎核心，依賴本 Issue 的 UUID 主鍵與 `sync_metadata` 表）可以開始。

## 審查修正紀錄（`tmp/epic-8/plan-issue-1-review.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-03）結論「需修訂後執行」，1 項 Critical、2 項 Important/Minor 主要意見。逐項核對（含直接查看本專案實際鎖定的 `sqflite_common-2.5.8` 套件原始碼、查證 SQLite 官方 `PRAGMA foreign_keys` 文件行為）後結論如下：

- **Critical（確認屬實，已採納，屬真實可重現的架構缺陷）**：`sqflite_common-2.5.8` 的 `database_mixin.dart` `doOpen()` 第 1134 行 `await transaction((txn) async { ... await options.onUpgrade!(...); ... }, exclusive: true);` 證實 `onUpgrade` 整段確實跑在 sqflite 自動包住的一個交易內；SQLite 官方文件規定 `PRAGMA foreign_keys` 在交易開啟期間無法切換（靜默 no-op）。原計畫在 `onUpgrade` 內部呼叫 `PRAGMA foreign_keys = OFF/ON` 因此完全無效，`highlights`/`notes` 表的 rename/drop 流程會如原始 Critical 問題重現般拋出 `foreign key constraint failed`。已改為：`onConfigure`（sqflite 呼叫時機早於交易開始，見同一份原始碼第 1124-1134 行）判斷 `db.getVersion()` 是否落在 `(0, 17)` 區間、據此提前關閉外鍵約束；新增 `onOpen`（同樣在交易外，第 1178-1180 行）無條件恢復開啟，確保遷移完成後**同一次 App 啟動**（非等到下次重開）外鍵約束就已經是 ON，不影響既有 CASCADE／SET NULL 行為。原本在 `onUpgrade` 內的 `PRAGMA` 呼叫已移除。Task 1 Step 2 既有測試（升級情境測試）的驗證邏輯本身不需要改變（黑箱驗證：升級不拋例外＋升級後外鍵確實生效兩項斷言，在新舊兩種機制下皆是正確的判準），已更新測試內註解說明新的失敗途徑。
- **Important（查證後判定基於對計畫實際內容的誤讀，不成立，未採納，已在此記錄推回理由）**：審查報告假設 Task 3 把 `HighlightsRepository.delete()` 改成軟刪除（`UPDATE ... SET deleted_at = ?`），因此推論 SQLite 原生 `ON DELETE SET NULL` 不會觸發、需要額外手動級聯 `UPDATE notes SET highlight_id = NULL`。**核對計畫實際文字**（Task 3 Step 3 的 `highlights_repository.dart` 完整取代內容）：`delete(String id)` 方法本體是 `return _db.delete('highlights', where: 'id = ?', whereArgs: [id]);`——**仍是真正的 `DELETE FROM`，本 Issue 完全沒有把它改成軟刪除**（`deleted_at` 欄位本 Issue 只新增欄位、新資料一律 `NULL`，見 `issues.md` Issue 1「What to build」第 3 點「新資料一律 `NULL`」）。既然是真正的硬刪除，SQLite 原生 `highlights.id` 的 `ON DELETE SET NULL` 外鍵行為與改版前完全一致地繼續運作，不需要任何額外級聯邏輯；Task 3 沿用的既有測試「FK 退化行為（spec.md 決策 #13...）」正是驗證這件事。**軟刪除轉換是刻意留給後續 Issue 4（同步引擎核心）的範圍**（spec.md「本機 Schema 變更」原文「刪除操作改為 `UPDATE ... SET deleted_at = ?`」描述的是 Issue 4 要做的事，不是 Issue 1），屆時 Issue 4 才需要重新設計「軟刪除的劃線如何讓依附備註退化」這個問題（屬於一個獨立、值得屆時認真設計的問題，不適合現在提前塞進 Issue 1）。
- **Minor（確認屬實，已採納，但特別記錄查證結果）**：`_createSyncMetadataTable` 的種子列插入已加上 `conflictAlgorithm: ConflictAlgorithm.ignore` 防禦。查證後發現審查報告描述的具體失敗情境（遷移中途失敗、重試時撞見已存在的 `id=1` 列）**在本專案目前的交易語意下實際上不會發生**——`onUpgrade` 整段（含 `_createSyncMetadataTable` 的 `CREATE TABLE`＋`INSERT`）都在同一個 sqflite 自動交易內，任何一步拋出例外都會讓整個交易（含版本號更新）一併回滾，下次重試永遠是從乾淨的舊 schema 狀態重新開始，不會有「表已存在、id=1 已存在」的中間態殘留。加上 `ignore` 是零成本的防禦保險，不代表真的驗證到一個目前會發生的 bug——已在程式碼註解中如實記錄這個查證結論，避免未來的人誤以為這是修過一個真實發生過的 bug。
- **Minor（查證後判定不適用於本計畫實際內容，未採納）**：審查報告建議在測試輔助檔統一宣告 `const testUuid = Uuid();` 避免測試中重複建立 `Uuid()` 物件。核對計畫實際內容：Task 5（測試呼叫端修正規則）全程使用**字串字面值**（例如 `id: 'bm1'`）指派測試用 id，不曾在測試程式碼中呼叫 `Uuid()`；`Uuid()` 只出現在 Task 1 的 3 個遷移函式（`_migrateBookmarksToUuid` 等）與 Task 4 的生產程式碼呼叫端，且皆已是「函式範圍內宣告一次 `const uuid = Uuid();`／`const Uuid().v4()` 單次呼叫」的低頻率用法，不存在迴圈內重複建構的效能疑慮，這項建議沒有對應到計畫裡任何實際會發生的程式碼路徑。
- **Minor（純讚許，無需動作）**：`renameBookmark`／`updateNoteText` 皆正確維護 `updated_at` 的讚許，維持原樣不變。

## 實作結果第二輪審查修正紀錄（`tmp/epic-8/plan-issue-1-implementation-review-v2.md`）

第一輪實作結果審查（`tmp/epic-8/plan-issue-1-implementation-review.md`）發現 Task 1 完全缺席（`flutter test` 崩潰 22 個測試）；補上 schema 遷移本體後的第二輪複審（2026-08-03）確認崩潰已消除，但發現 4 項新 Critical——與 `issues.md` Issue 1 明文驗收標準逐項核對後，皆確認屬實並已修正：

- **Critical（確認屬實，已採納）**：`bookmarks`／`highlights`／`notes` 三表原本缺少 `updated_at`／`deleted_at` 欄位。已補進 `_createBookmarksTable`／`_createHighlightsTable`／`_createNotesTable` 與 `_migrateAnnotationTablesToUuid` 的三段搬遷邏輯（`updated_at` 回填為遷移當下時間戳記、`deleted_at` 為 `NULL`），並讓遷移函式改為直接呼叫 `_createXTable()` 而非各自重複內嵌 `CREATE TABLE` SQL（DRY，避免兩處 schema 定義日後各自漂移）。
- **Critical（確認屬實，已採納）**：`sync_metadata` 實際 schema（`table_name TEXT PRIMARY KEY, last_synced_at TEXT NOT NULL`）與本文件明訂的設計（單列 `id=1`＋`last_push_completed_at`＋4 個 `last_pulled_server_updated_at_<collection>`）完全不同。已依 Task 1 Step 4 的精確設計重寫。
- **Critical（確認屬實，已採納）**：`_createSyncMetadataTable(db)` 原本只在 `onUpgrade` 的 `if (oldVersion < 17)` 分支被呼叫，`onCreate`（全新安裝）完全沒呼叫，導致新裝置沒有這張表。已在 `onCreate` 的建表序列補上這個呼叫。
- **Critical（確認屬實，已採納）**：`issues.md` 明文要求的兩則遷移測試（全新安裝 schema 正確性、既有 v16 裝置升級正確性＋FK 暫停/恢復回歸驗證）完全未加入。已依 Task 1 Step 2 原文把兩則測試整段加入 `app/test/library/sqlite_library_repository_test.dart`（`sync_metadata` 相關斷言欄位名稱同步改為 `last_push_completed_at`，配合上面第 2 點的 schema 修正）。

補齊上述 4 項後執行 `flutter test`，另外發現並修正兩個連帶問題（非審查報告直接列出，但補齊 Critical 1 後必然浮現）：

- **新發現（補齊 `updated_at NOT NULL` 後才會觸發）**：`BookmarksRepository.insert()`／`rename()`、`HighlightsRepository.insert()`、`NotesRepository.insert()`／`updateText()` 呼叫 `_db.insert()`／`_db.update()` 時都沒有帶入 `updated_at`——本文件 Task 3 的原始程式碼片段本身就有這個遺漏（非實作者偏離計畫，是計畫本身這段程式碼在字面上就會導致 `NOT NULL constraint failed: bookmarks.updated_at`，因為 `Bookmark`/`Highlight`/`Note` 模型刻意不含這個欄位，見 Task 2 Self-Review Notes「模型只承載本機語意欄位」的既定設計）。修正方式：在 repository 層插入/更新時額外補上 `'updated_at': DateTime.now().millisecondsSinceEpoch`，不修改模型本身（`toMap()` 維持不變），維持「同步專用欄位不進模型」的既定切分。`delete()` 系列方法維持不動（`deleted_at` 目前恆為 `NULL`，軟刪除轉換仍是 Issue 4 範圍，與前次審查「Important 推回」的結論一致）。
- **新發現（既有測試因新增的 `NOT NULL` 約束而失敗，非本 Issue 邏輯錯誤）**：`sqlite_library_repository_test.dart` 內 5 則既有（epic-6-annotations 時期、與本 Issue 無關的）舊測試手動 `db.insert('bookmarks'/'highlights'/'notes', {...})` 未帶 `updated_at`，在新 schema 下失敗。已於這些既有測試的 insert map 補上 `'updated_at': 1000`（測試不關心實際數值，比照該檔案既有 `createTime: 1000`／`lastReadTime: 1000` 的字面時間戳記慣例）。

另修正 2 項 Minor（承接前次審查記錄）：`reader_screen.dart` PDF 劃線／備註 id 移除不一致的 `_pdf` 後綴（改為與其餘 4 處呼叫點一致的純 `const Uuid().v4()`）；`bookmark.dart` 文件註解移除對不存在函式 `_generateUuid()` 的引用。

修正後 `flutter analyze`「No issues found!」，`flutter test` 796 個測試全數通過（含新增的 2 則遷移測試）。Task 1 全部 7 個 Step 核取方塊已依真實狀態改回 `- [x]`。
