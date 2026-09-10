# Epic 10 Issue 6：FTS5 模組可用性偵測＋全文檢索優雅降級（真機相容性缺陷）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `SqliteLibraryRepository.open()` 在系統 SQLite 沒有編譯 FTS5 模組的裝置上也能成功回傳（不再讓 `main()` 在 `runApp()` 之前就被未接住的例外炸穿、App 永遠卡在啟動畫面），並提供一個可查詢的 `isFullTextSearchAvailable` 旗標，供後續 Issue（3／4）判斷是否要在 UI 上顯示「本裝置不支援全文檢索」。

**Architecture：** 現有 `_createBookContentFtsTable(db)`（Issue 0 既有程式碼）改為透過一個可被測試覆寫的頂層函式變數 `createBookContentFtsTable` 呼叫，外面包一層新的私有 helper `_createBookContentFtsTableIfSupported(db)`：成功就照舊；若失敗訊息符合「FTS5 模組不存在」這個特定情境（比對訊息文字，不比對例外型別），靜默跳過（不建立 `book_content_fts` 虛擬表與其三個同步 trigger），讓 `onCreate`／`onUpgrade` 的其餘語句（含 `content_index_status`／`book_content_index` 兩張一般表）正常跑完；其他未預期的例外原樣重新拋出，不可靜默吞掉真正的 bug。`open()` 在 `openDatabase()` 完成後，改用查詢 `sqlite_master` 是否存在 `book_content_fts` 這張表來決定 `isFullTextSearchAvailable`（而不是在 `onCreate`/`onUpgrade` closure 內用一個被捕捉的區域變數記錄）——因為一般開啟既有裝置（沒有觸發任何遷移）時 `onCreate`／`onUpgrade` 兩者都不會被呼叫，只有查 `sqlite_master` 能對「這一次開啟」正確反映目前的實際狀態，不論是全新安裝、既有裝置升級、還是單純重新開啟都適用同一條判斷邏輯。

**Tech Stack：** Flutter/Dart、`sqflite`（Android 系統內建 SQLite，本工單修的正是這條路徑的相容性）、`sqflite_common_ffi`（測試環境，一律有 FTS5，需要函式覆寫才能測到「不可用」路徑）。

**Spec：** 工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 6（含完整真機根因記錄／因果鏈／方向草案）；[`docs/adr/0027-search-index-tokenization-and-headless-foliate-extraction.md`](../../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md)「技術限制」1（本工單修的風險與此同源但更嚴重：ADR 0027 原本只討論過 FTS5 `trigram` tokenizer 需要 SQLite 3.34+，沒有涵蓋「FTS5 模組本身完全不存在」）。

> **本計畫檔案存放路徑覆寫說明**：比照 `plan-issue-0.md`／`plan-issue-1.md` 先例，`superpowers:writing-plans` 技能預設把計畫存到 `docs/superpowers/plans/`，本專案 SDD 工作流程（`docs/agents/issue-tracker.md`）明訂存放於 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，本計畫依專案慣例存放於此。

## Global Constraints

- **本工單只解決「App 能不能開機」與「能否查詢到本裝置是否支援全文檢索」這兩件事，不做以下事情（刻意排除，避免範圍蔓延）：**
  - **不修改 `ContentIndexingScheduler`／`main.dart`**：`isFullTextSearchAvailable` 為 `false` 的裝置上，Issue 1 的背景排程器目前仍會正常嘗試索引 `content_index_status` 裡的 `pending` 書籍、寫入 `book_content_index`（只是沒有 FTS5 觸發器同步到 `book_content_fts`，等於白工——不會出錯，但也不會有全文檢索效果）。是否要在排程器層級也判斷 `isFullTextSearchAvailable` 而完全跳過處理，屬於 Issue 3（「啟用全文檢索」設定模型）的開關語意範圍，留給該工單一併考慮，不在本工單處理。
  - **不修改 `docs/adr/0027-search-index-tokenization-and-headless-foliate-extraction.md`**：Issue 6 的 issues.md 條目已建議「需要重新檢視 ADR 0027 決策 1 是否要補充或修訂」，但這是文件層級的後續工作，不阻擋本工單的程式碼修復，執行者完成本計畫後可另行提出 ADR 修訂，不包含在本計畫的 Task 範圍內。
  - **不新增/修改任何 UI**：`isFullTextSearchAvailable` 只是一個公開唯讀欄位，供 Issue 3／4 未來查詢使用，本工單不消費它。
  - **`isFullTextSearchAvailable` 刻意只放在 `SqliteLibraryRepository`，不下放到抽象介面 `LibraryRepository` 或 `FakeLibraryRepository`（review-plan-issue-6.md I-1，已推翻）**：`issues.md` Issue 3 已規劃新增獨立的 `FullTextSearchSettingsRepository` 專門管理全文檢索啟用狀態，這才是「本裝置是否支援/啟用全文檢索」未來該落腳的地方——本工單若現在就把這個欄位焊進 `LibraryRepository` 抽象介面，等於在 Issue 3 還沒設計之前先幫它決定好介面形狀，範圍蔓延。比照既有 `.database` getter 先例（`docs/adr/0007-reader-screen-book-id-contract.md`：`main.dart` 在 repository 尚未收窄為 `LibraryRepository` 介面前，先用具體類別 `SqliteLibraryRepository` 取值，再視需要往下傳，不強迫下游持有具體類別）——本工單只負責在具體類別上把值算出來、放著，往下游怎麼傳遞留給實際消費它的 Issue 3／4 決定。
- **不需要 DB 版本號變更（維持 `version: 24`）**：這不是新的 schema 變更，是讓既有 version 24 遷移步驟對「FTS5 不存在」這個情境有防禦性處理，`onCreate`／`onUpgrade` 呼叫的表結構本身完全不變。
- **偵測策略是「直接嘗試、失敗才降級」，不是「動手前先探測」**：不額外建立一張一次性探測用的虛擬表再刪除——直接嘗試真正的 `CREATE VIRTUAL TABLE book_content_fts USING fts5(...)`，失敗時捕捉例外；這樣「探測」與「實際建表」永遠是同一段程式碼、同一次呼叫，不會有「探測說可用，但實際建表時又用不同路徑失敗」的落差風險。
- **例外比對用訊息文字，不用例外型別**：正式環境丟出的是 `sqflite_common` 內部的 `SqfliteDatabaseException`（`package:sqflite/sqflite.dart` 未公開匯出這個具體型別，只公開匯出抽象的 `DatabaseException`），測試環境的假實作可以丟任何型別的例外——兩者唯一保證共通的是 `.toString()` 內含 `'no such module: fts5'` 這段文字（真機 logcat 實測訊息：`DatabaseException(no such module: fts5 (code 1 SQLITE_ERROR)) sql '...' during open, closing...`），故一律用 `e.toString().toLowerCase().contains('no such module: fts5')` 判斷（`.toLowerCase()` 防禦大小寫變異，review-plan-issue-6.md M-1），`catch (e)`（不宣告型別）而非 `on DatabaseException catch (e)`。
- 測試環境一律用 `sqflite_common_ffi`（`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`），比照 `app/test/library/sqlite_library_repository_test.dart` 既有慣例；`sqflite_common_ffi` 底層一律有 FTS5，無法自然重現「不可用」情境，必須靠函式覆寫（見下方 Task 1）。
- 涉及「既有裝置升級」的測試改用真實暫存檔（`Directory.systemTemp.createTemp(...)`），因為 `onUpgrade` 只在重新開啟既有檔案時觸發，`inMemoryDatabasePath` 每次開啟都是全新資料庫、永遠只會走 `onCreate`（比照 `plan-issue-0.md` 既有慣例與 `sqlite_library_repository_test.dart` 既有「既有 version 23 裝置升級到 version 24」測試寫法）。
- 涉及 `inMemoryDatabasePath` 且需要獨立於 `setUp()` 共用 `repository` 的測試，一律傳入 `singleInstance: false`（`SqliteLibraryRepository.open()` 既有 doc comment 已記錄的既知陷阱：對同一個 `':memory:'` 字面路徑重複呼叫預設會拿回同一條快取連線）。
- 所有新增程式碼註解使用正體中文（zh-TW），比照全專案既有慣例。
- **本計畫已經過一輪計畫審查修訂**（`reviews/review-plan-issue-6.md`，🔴 Changes Requested，1 Critical／2 Important／3 Minor）：C-1（`createBookContentFtsTable` 頂層變數的插入位置原始指示自相矛盾，已改為明確指向檔案最尾端）、M-1（例外訊息比對加 `.toLowerCase()`）、M-2（Step 1 插入位置文字歧義已改寫）、M-3（`sqlite_master` 查詢加 `limit: 1`）四項全數採納並修訂；I-2（缺少「已遷移至 v24 但無 FTS5 之資料庫重新開啟」的測試）已採納，補在 Step 1 測試 3 尾端。**I-1（建議把 `isFullTextSearchAvailable` 同步下放到 `LibraryRepository`／`FakeLibraryRepository`）已查證推翻，不採納**——理由見上方「`isFullTextSearchAvailable` 刻意只放在 `SqliteLibraryRepository`」一條。執行者不需要另外重讀審查報告，所有修訂已內嵌為對應程式碼片段與行內註解。

---

## 檔案結構總覽

- **Modify：** `app/lib/library/sqlite_library_repository.dart` — 新增 `isFullTextSearchAvailable` 欄位、頂層可覆寫函式變數 `createBookContentFtsTable`、私有 helper `_createBookContentFtsTableIfSupported()`；`onCreate`／`onUpgrade` 兩處呼叫點改用新 helper；`open()` 回傳前改查 `sqlite_master` 決定旗標值。
- **Modify：** `app/test/library/sqlite_library_repository_test.dart` — 新增 `epic-10-search Issue 6：FTS5 模組可用性偵測與優雅降級` 測試群組（沿用既有檔案，不新開檔案，比照這個檔案裡「epic-10-search Issue 0」既有測試群組的寫法慣例）。

---

### Task 1：FTS5 可用性偵測＋優雅降級

**Files：**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces：**
- Consumes：既有 `SqliteLibraryRepository.open(String path, {bool singleInstance = true})`（僅內部實作改動，對外公開簽章不變，不影響任何既有呼叫端如 `main.dart:82`）。
- Produces：`SqliteLibraryRepository` 新增公開唯讀欄位 `final bool isFullTextSearchAvailable`；頂層可覆寫函式變數 `Future<void> Function(Database db) createBookContentFtsTable`（供 Issue 3／4 未來若需要模擬同等情境時可比照本工單測試方式覆寫，也供本工單測試使用；正式執行路徑不需任何人手動賦值，已預設指向真正實作）。

- [x] **Step 1：寫一組會失敗（編譯錯誤）的測試——FTS5 可用／不可用（全新安裝＋既有裝置升級）／非 FTS5 例外不可靜默吞掉**

在 `app/test/library/sqlite_library_repository_test.dart`，找到既有的 `group('epic-10-search Issue 0：全文檢索資料表', () { ... });` 區塊**結束的大括號**（`});`）——這是全檔案目前最後一個 `group`，其後緊接的就是 `main()` 函式本身的收尾 `});`。在這兩個 `});` 之間插入新的測試群組（也就是整份檔案的新結尾，緊接在 Issue 0 群組之後、`main()` 收尾之前）：

```dart
  group('epic-10-search Issue 6：FTS5 模組可用性偵測與優雅降級', () {
    test('FTS5 可用（一般情況，測試環境 sqflite_common_ffi 一律有 FTS5）：'
        'isFullTextSearchAvailable 為 true', () async {
      expect(repository.isFullTextSearchAvailable, isTrue);
    });

    test(
        '全新安裝時 FTS5 不可用：open() 仍成功回傳，isFullTextSearchAvailable 為 false，'
        'content_index_status／book_content_index 仍建立，book_content_fts 不存在',
        () async {
      final original = createBookContentFtsTable;
      addTearDown(() => createBookContentFtsTable = original);
      createBookContentFtsTable = (db) async {
        throw Exception('no such module: fts5 (code 1 SQLITE_ERROR)');
      };

      final repo = await SqliteLibraryRepository.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(() => repo.close());

      expect(repo.isFullTextSearchAvailable, isFalse);

      final tableNames = await repo.database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table' AND name IN (?, ?, ?)",
        whereArgs: [
          'content_index_status',
          'book_content_index',
          'book_content_fts',
        ],
      );
      expect(
        tableNames.map((row) => row['name']).toSet(),
        {'content_index_status', 'book_content_index'},
        reason: 'book_content_fts 不應存在，另兩張一般表不受 FTS5 缺陷影響',
      );
    });

    test(
        '既有 version 23 裝置升級時 FTS5 不可用：升級仍成功完成，'
        'isFullTextSearchAvailable 為 false，book_content_fts 不存在；'
        '關閉後單純重新開啟（不觸發 onCreate/onUpgrade）仍正確反映 false'
        '（review-plan-issue-6.md I-2）', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('elinkbook_migration_v23_to_v24_fts5_unavailable_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'test.db');

      final oldDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 23,
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
                position_synced_server_updated_at TEXT,
                remote_server_id TEXT,
                remote_book_id TEXT,
                remote_download_url TEXT,
                is_downloaded INTEGER NOT NULL DEFAULT 1,
                cloud_file_id TEXT
              )
            ''');
          },
        ),
      );
      await oldDb.close();

      final original = createBookContentFtsTable;
      addTearDown(() => createBookContentFtsTable = original);
      createBookContentFtsTable = (db) async {
        throw Exception('no such module: fts5 (code 1 SQLITE_ERROR)');
      };

      final upgraded = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => upgraded.close());

      expect(upgraded.isFullTextSearchAvailable, isFalse);

      final tableNames = await upgraded.database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table' AND name IN (?, ?, ?)",
        whereArgs: [
          'content_index_status',
          'book_content_index',
          'book_content_fts',
        ],
      );
      expect(
        tableNames.map((row) => row['name']).toSet(),
        {'content_index_status', 'book_content_index'},
      );

      // 【review-plan-issue-6.md I-2】關閉後單純重新開啟：此時 db 已是
      // version 24，openDatabase() 不會呼叫 onCreate 也不會呼叫
      // onUpgrade（oldVersion == newVersion == 24）。這是本計畫
      // Architecture 段落宣稱「查 sqlite_master 對三種開啟路徑都適用」
      // 的核心論點，若不驗證這條路徑，日後若有人把判斷邏輯改回
      // onCreate/onUpgrade closure 內的區域變數，既有測試仍會全數
      // 通過、卻悄悄破壞了重開情境（真正的迴歸來源）。
      await upgraded.close();
      final reopened = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => reopened.close());
      expect(reopened.isFullTextSearchAvailable, isFalse,
          reason: '已遷移至 v24 但缺 FTS5 之資料庫重開時，'
              'isFullTextSearchAvailable 仍須為 false');
    });

    test('非 FTS5 相關的其他例外原樣拋出，不可靜默吞掉（回歸防護）', () async {
      final original = createBookContentFtsTable;
      addTearDown(() => createBookContentFtsTable = original);
      createBookContentFtsTable = (db) async {
        throw Exception('near "GARBAGE": syntax error');
      };

      expect(
        () => SqliteLibraryRepository.open(
          inMemoryDatabasePath,
          singleInstance: false,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
```

不需要新增 import——`dart:io`（`Directory`）、`package:path/path.dart as p`、`package:sqflite_common_ffi/sqflite_ffi.dart`（`databaseFactory`／`OpenDatabaseOptions`／`inMemoryDatabasePath`）、`package:elinkbook/library/sqlite_library_repository.dart`（將提供新的頂層變數 `createBookContentFtsTable` 與新欄位 `isFullTextSearchAvailable`）皆已是檔案既有 import。

- [x] **Step 2：執行測試，確認因為production API尚不存在而編譯失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（編譯錯誤：`createBookContentFtsTable` 未定義、`SqliteLibraryRepository.isFullTextSearchAvailable` 未定義）。

- [x] **Step 3：實作 `isFullTextSearchAvailable`＋可覆寫的 `createBookContentFtsTable`＋降級 helper**

在 `app/lib/library/sqlite_library_repository.dart`，找到：

```dart
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  SqliteLibraryRepository._(this._db);
```

整段取代為：

```dart
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  /// 本機這份資料庫在 [open] 當下，底層 SQLite build 是否有 FTS5 模組
  /// 可用（epic-10-search Issue 6）。部分裝置（例如客製化韌體的 Android
  /// 系統內建 SQLite）完全沒有編譯 FTS5，`book_content_fts` 虛擬表因而
  /// 無法建立；此欄位為 `false` 時，全文檢索功能不可用，但其餘既有功能
  /// 不受影響——供 Issue 3／4 的搜尋設定／搜尋畫面查詢後顯示「本裝置
  /// 不支援全文檢索」提示，本工單只負責讓 App 能正常開機並提供這個
  /// 查詢點，不實作任何 UI（見 docs/epics/epic-10-search/issues.md
  /// Issue 6）。
  final bool isFullTextSearchAvailable;

  SqliteLibraryRepository._(
    this._db, {
    required this.isFullTextSearchAvailable,
  });
```

再找到（`open()` 方法內，`onUpgrade` 分支的版本 24 判斷）：

```dart
        if (oldVersion < 24) {
          // epic-10-search Issue 0：全文檢索三張新表，皆為全新獨立表
          // （非既有表新增欄位），比照 bookmarks（oldVersion < 8）／
          // custom_fonts（oldVersion < 16）等既有原則，無條件建立即可。
          await _createContentIndexStatusTable(db);
          await _createBookContentIndexTable(db);
          await _createBookContentFtsTable(db);
        }
```

取代為：

```dart
        if (oldVersion < 24) {
          // epic-10-search Issue 0：全文檢索三張新表，皆為全新獨立表
          // （非既有表新增欄位），比照 bookmarks（oldVersion < 8）／
          // custom_fonts（oldVersion < 16）等既有原則，無條件建立即可。
          await _createContentIndexStatusTable(db);
          await _createBookContentIndexTable(db);
          // 【epic-10-search Issue 6】book_content_fts 改用會優雅降級的
          // 版本，見 _createBookContentFtsTableIfSupported 說明。
          await _createBookContentFtsTableIfSupported(db);
        }
```

同一個檔案內，`onCreate` 分支也有同樣一行呼叫，找到（緊接在 `_createLayoutPresetTable(db)` 之後）：

```dart
        await _createContentIndexStatusTable(db);
        await _createBookContentIndexTable(db);
        await _createBookContentFtsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
```

取代為：

```dart
        await _createContentIndexStatusTable(db);
        await _createBookContentIndexTable(db);
        // 【epic-10-search Issue 6】同上，改用會優雅降級的版本。
        await _createBookContentFtsTableIfSupported(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
```

再找到 `open()` 方法的尾端：

```dart
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return SqliteLibraryRepository._(db);
  }
```

取代為：

```dart
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    // 【epic-10-search Issue 6】onCreate／onUpgrade 兩處都可能因為 FTS5
    // 模組不存在而略過建立 book_content_fts（見
    // _createBookContentFtsTableIfSupported 說明）；且一般開啟既有裝置
    // （沒有觸發任何遷移，version 已經是 24）時，onCreate／onUpgrade
    // 兩者皆不會被呼叫。查詢 sqlite_master 是唯一能對「這一次開啟」
    // 正確反映目前實際狀態的作法，不論是全新安裝、既有裝置升級、還是
    // 單純重新開啟都適用同一條判斷邏輯。
    final ftsTableRows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = 'book_content_fts'",
      limit: 1,
    );
    return SqliteLibraryRepository._(
      db,
      isFullTextSearchAvailable: ftsTableRows.isNotEmpty,
    );
  }
```

接著，找到既有的 `_createBookContentFtsTable` 方法本體結束的 `}`（第 894 行，即上方三個 `CREATE TRIGGER` 語句之後、緊接著 `static Future<void> _createRemoteServersTable(Database db) async {` 之前的那個 `}`）。**在這裡插入的是類別內部的 `static` 方法，維持在 `class SqliteLibraryRepository { ... }` 大括號內**，新增：

```dart

  /// 呼叫 [createBookContentFtsTable]；若失敗訊息符合「FTS5 模組不存在」
  /// 這個特定情境（比對訊息文字而非例外型別——正式環境丟出
  /// `SqfliteDatabaseException`，測試假實作可能丟出任意型別的例外，
  /// 兩者唯一保證共通的是訊息文字，見上方 [createBookContentFtsTable]
  /// 說明），靜默跳過，不建立 book_content_fts 虛擬表與其三個同步
  /// trigger；`content_index_status`／`book_content_index` 兩張一般表
  /// 在呼叫這個方法之前就已建立完成，不受影響，讓 App 能正常開機
  /// （epic-10-search Issue 6）。其餘未預期的例外原樣重新拋出，不可
  /// 靜默吞掉真正的錯誤。
  static Future<void> _createBookContentFtsTableIfSupported(
    Database db,
  ) async {
    try {
      await createBookContentFtsTable(db);
    } catch (e) {
      // 【review-plan-issue-6.md M-1】.toLowerCase() 防禦大小寫變異：
      // 目前實測到的真機訊息固定小寫，但不同客製化 ROM／sqlite3 driver
      // wrapper 無法百分之百保證不出現大小寫差異，這裡零成本加防禦。
      if (!e.toString().toLowerCase().contains('no such module: fts5')) {
        rethrow;
      }
    }
  }
```

**最後**（review-plan-issue-6.md C-1 修正）：查證確認 `app/lib/library/sqlite_library_repository.dart` 全檔共 1195 行，`class SqliteLibraryRepository implements LibraryRepository { ... }` 從第 20 行開始，收尾大括號 `}` 正是檔案的最後一行（第 1195 行）。`createBookContentFtsTable` 是**頂層**函式變數，必須寫在這個 `}` 之外——**在檔案最尾端（第 1195 行的 `}` 之後）新增以下內容，作為整個檔案的新結尾**（不要插在第 870 行 `_createBookContentFtsTable` 方法定義前面，那個位置仍在類別大括號內，插在那裡會變成 instance field，`createBookContentFtsTable` 這個名字在其他檔案裡會解析不到）：

```dart

/// [SqliteLibraryRepository] 建立 `book_content_fts` FTS5 虛擬表＋三個
/// 同步 trigger 的實際實作，抽成頂層函式變數（非固定方法呼叫）比照
/// `pdf_content_indexer.dart` 的 `readContentUriAll` 既有慣例（該函式
/// 同樣是頂層變數、寫在其所屬類別 `PdfContentIndexer` 之外、置於檔案
/// 尾端，不加任何額外標註），供測試覆寫成會丟出「no such module:
/// fts5」字樣例外的假實作，驗證 `SqliteLibraryRepository.open()` 對
/// 這個情境的降級處理邏輯（epic-10-search Issue 6，見
/// docs/epics/epic-10-search/issues.md Issue 6 真機根因記錄）——不需要
/// 真的找一顆缺 FTS5 模組的 SQLite build 才能測到「不可用」這條路徑
/// （`sqflite_common_ffi` 測試環境的 SQLite build 一律有 FTS5，無法
/// 自然重現）。正式執行路徑固定指向
/// [SqliteLibraryRepository._createBookContentFtsTable]。
Future<void> Function(Database db) createBookContentFtsTable =
    SqliteLibraryRepository._createBookContentFtsTable;
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（新增的 4 個測試＋既有全部測試，因為這個檔案裡有數千行既有測試，這裡刻意整檔重跑，不只跑新測試群組，確保沒有破壞既有行為）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "fix(search): FTS5 模組不存在時優雅降級，避免 App 卡在啟動畫面"
```

- [ ] **Step 7：（人類／執行者手動）真機驗證**

這是本工單的最終驗收標準（`issues.md` Issue 6「驗收標準」），無法自動化——需要一台系統 SQLite 缺 FTS5 模組的真實裝置（本工單根因記錄使用的裝置：`9491G`／`Hera_Vis_WIFI`，Android 15）：

1. 在該分支上 `flutter build apk --debug` 並用 `adb install -r` 安裝到該裝置（或 `flutter run -d <device-id>`）。
2. 確認 App 能正常開機、進入書架畫面（不再卡在啟動畫面）。
3. 可選：用 `adb logcat` 確認不再出現 `DatabaseException(no such module: fts5 ...)` 這則未接住例外（`main()`／`SqliteLibraryRepository.open()` 相關的 stack trace 不應再出現）。

若該裝置目前已安裝過舊版（例如卡在啟動畫面的那個版本），比照本工單根因記錄過程使用的方式安裝新版即可（`adb install -r` 對簽章不同的版本可能需要先解除安裝，見本 Epic 除錯過程紀錄）。

---

## 自我審查（Self-Review，計畫撰寫者執行，非另一輪審查）

**Spec 覆蓋度：** `issues.md` Issue 6 的三個 Solution 方向草案逐項對應——(1)「偵測 FTS5 可用性、不可用時跳過建表」→ Step 3 的 `_createBookContentFtsTableIfSupported`；(2)「需要一個機制讓『本裝置不支援』能被後續 Issue 查詢」→ Step 3 的 `isFullTextSearchAvailable` 公開欄位；(3)「影響範圍評估、是否搶修」→ 屬於人類/Scrum Master 決策，非程式碼任務，不需要對應 Task。單元測試要求三項（降級路徑／回歸測試／可查詢欄位）分別對應 Step 1 的第 2/3 個測試、第 1 個測試、以及所有測試共同驗證的 `isFullTextSearchAvailable`。驗收標準（App 能正常開機＋`flutter analyze` 乾淨＋不影響 Issue 0 既有測試套件）對應 Step 4／5／7。

**Placeholder 掃描：** 無「TBD」「稍後補上」「類似 Task N」等字樣，所有程式碼片段皆為完整可直接套用的內容，無「加上適當的錯誤處理」這類空話。

**型別一致性：** `createBookContentFtsTable` 的簽章 `Future<void> Function(Database db)` 與既有 `_createBookContentFtsTable(Database db)` 完全一致；`isFullTextSearchAvailable` 在建構子、欄位宣告、測試斷言三處皆為 `bool`／`required this.isFullTextSearchAvailable` 命名一致；`_createBookContentFtsTableIfSupported` 在兩個呼叫點（`onCreate`／`onUpgrade`）與定義處方法名稱、參數皆一致。
