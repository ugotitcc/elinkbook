# Epic 10 Issue 0：資料庫 Schema＋中文 Tokenizer＋效能驗證 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立全文檢索所需的資料庫 schema（`content_index_status`／`book_content_index`／`book_content_fts`，DB version 23→24）與中文字元層級 tokenizer 純函式，並以近真實規模的合成資料量化驗證 FTS5 查詢是否符合 NFR-2（1,000 本書規模、500ms 內回應）。

**Architecture：** 三張新表全部加進既有的 `SqliteLibraryRepository`（`app/lib/library/sqlite_library_repository.dart`），比照專案既有「所有子系統的表都在同一個 repository 檔案裡，各自一個 `_createXTable` 靜態 helper」慣例，不新建獨立的 repository 類別。`book_content_fts` 是 FTS5 **external-content** 虛擬表（只索引 `token_text`，實際文字仍以 `book_content_index` 為準），靠三個 `AFTER INSERT/UPDATE/DELETE` trigger 保持同步；書籍刪除時的級聯清除完全依賴 SQLite 引擎（`ON DELETE CASCADE` ＋ `PRAGMA recursive_triggers = ON`），App 端不寫任何額外清理程式碼。中文 tokenizer 是全新的純 Dart 檔案 `app/lib/search/cjk_tokenizer.dart`，兩個函式都是無副作用的字串轉換，不觸碰資料庫。效能驗證是一支獨立的 benchmark 測試，直接串接前兩塊（schema＋tokenizer）跑一次近真實規模的合成資料。

**Tech Stack：** Flutter/Dart、`sqflite`（Android 系統內建 SQLite）、`sqflite_common_ffi`（測試環境）、SQLite FTS5（`unicode61` 內建 tokenizer，**不使用** `trigram`——見 Global Constraints）。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §1（資料庫 Schema）、§2（中文 Token 化規則）、§8（效能驗證）；[`docs/adr/0027-search-index-tokenization-and-headless-foliate-extraction.md`](../../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md)；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 0。

> **本計畫檔案存放路徑覆寫說明**：`superpowers:writing-plans` 技能預設把計畫存到 `docs/superpowers/plans/`，但本專案的 SDD 工作流程（`docs/agents/issue-tracker.md`）明訂每個工單的實作計畫存放於 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`——這是專案既有慣例對技能預設值的覆寫，本計畫依專案慣例存放於此。

## Global Constraints

- DB schema 版本從 `23` 升級到 `24`（`sqlite_library_repository.dart:42` 的 `version:` 參數）。
- **必須**在 `onConfigure` 新增 `PRAGMA recursive_triggers = ON;`（與既有 `PRAGMA foreign_keys = ON` 同一處），否則書籍刪除的外鍵級聯不會觸發 `book_content_fts` 的同步 trigger，殘留孤兒索引（`spec.md` §1 已記錄的 review-spec.md C-1 修正）。
- **排除 SQLite FTS5 `trigram` tokenizer**：Android 11（PRD NFR-6 最低支援版本）系統 SQLite 為 3.28.0，早於 `trigram` 所需的 3.34+。`CREATE VIRTUAL TABLE ... USING fts5(token_text, ...)` **不加** `tokenize=` 參數，使用 FTS5 預設的 `unicode61`（ADR 0027 決策 1）。
- **排除 SQLite `FILTER (WHERE ...)` 聚合語法**：該語法是 SQLite 3.30.0 才加入，Android 11 系統 SQLite 3.28.0 不支援（`spec.md` §3.3 已記錄的 review-spec.md I-1 修正）。本計畫的所有 SQL 一律不使用 `FILTER`。
- NFR-2：全庫搜尋在 1,000 本書規模下，查詢回應須在 500ms 內。
- 測試環境一律用 `sqflite_common_ffi`（`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`），比照 `app/test/library/sqlite_library_repository_test.dart` 既有慣例；牽涉「既有裝置升級」的 migration 測試改用真實暫存檔（`Directory.systemTemp.createTemp(...)`），因為 sqflite 的 `onUpgrade` 只在重新開啟既有檔案時觸發，`inMemoryDatabasePath` 每次開啟都是全新資料庫、永遠只會走 `onCreate`。
- `books.format` 欄位存的是 `BookFileFormat.name` 字串（例如 `'epub'`／`'pdf'`），見 `app/lib/library/models/book.dart:133`。

---

## 檔案結構總覽

- **Modify:** `app/lib/library/sqlite_library_repository.dart` — 新增三個 `_createXTable` 靜態 helper、`onConfigure` 新增 PRAGMA、`onCreate`／`onUpgrade` 各自呼叫、版本號 23→24。
- **Modify:** `app/test/library/sqlite_library_repository_test.dart` — 新增本工單的 schema／migration／級聯刪除測試（沿用既有檔案，不新開檔案，比照這個檔案裡其他子系統表的測試慣例）。
- **Create:** `app/lib/search/cjk_tokenizer.dart` — `tokenizeForIndex()`／`tokenizeForQuery()` 兩個純函式。
- **Create:** `app/test/search/cjk_tokenizer_test.dart` — 對應單元測試。
- **Create:** `app/test/search/content_search_performance_benchmark_test.dart` — 效能驗證 Spike，串接前兩塊。

---

### Task 1：資料庫 Schema 遷移（DB version 23→24）＋級聯刪除回歸測試

**Files：**
- Modify: `app/lib/library/sqlite_library_repository.dart:36-125`（`open()` 方法的 `onConfigure`／`onCreate`），`app/lib/library/sqlite_library_repository.dart:358-372`（`onUpgrade` 最後一段 `if (oldVersion < 23)` 之後新增 `if (oldVersion < 24)`），檔案尾端新增三個 `_createXTable` 靜態方法（比照 `_createLayoutPresetTable`／`_createRemoteServersTable` 既有位置，加在它們附近）。
- Test: `app/test/library/sqlite_library_repository_test.dart`（在檔案尾端新增一個新的 `group`）。

**Interfaces：**
- Consumes：無（本工單是全新地基）。
- Produces：三張資料表供 Task 3（效能驗證）與後續 Issue 1-5 直接使用——`content_index_status(book_id, status, last_chapter_index, updated_at, error_message)`、`book_content_index(id, book_id, chapter_index, locator, raw_text, token_text, created_at)`、`book_content_fts(token_text)`（FTS5 external-content，`content_rowid='rowid'` 對應 `book_content_index.rowid`）。`SqliteLibraryRepository.database`（既有 public getter）供後續工單直接下 raw SQL 查詢這三張表（本 Epic 不新建獨立的 `SearchRepository` 之前，都先用這個既有 getter）。

- [x] **Step 1：寫一個會失敗的測試——全新安裝的資料庫包含三張全文檢索資料表**

在 `app/test/library/sqlite_library_repository_test.dart` 檔案尾端（最後一個 `test(...)` 之後、`main()` 的結尾 `});` 之前）新增：

```dart
  group('epic-10-search Issue 0：全文檢索資料表', () {
    test('全新安裝的資料庫包含 content_index_status／book_content_index／book_content_fts 三張表',
        () async {
      final tableNames = await repository.database.query(
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
        {'content_index_status', 'book_content_index', 'book_content_fts'},
      );
    });
  });
```

（沿用檔案頂部既有的 `repository`／`setUp`／`tearDown`，不需要另外建構。）

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "全新安裝的資料庫包含"`
Expected: FAIL（`tableNames` 為空集合，斷言不通過——三張表還不存在）。

- [x] **Step 3：實作三張表的 `_createXTable` 靜態方法**

在 `app/lib/library/sqlite_library_repository.dart` 找到 `_createLayoutPresetTable`（約第 798 行）附近，於其後新增：

```dart
  /// 每本書的全文檢索索引進度狀態，含背景排程的續跑游標
  /// （epic-10-search Issue 0，見 spec.md §1）。
  static Future<void> _createContentIndexStatusTable(Database db) async {
    await db.execute('''
      CREATE TABLE content_index_status (
        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
        status TEXT NOT NULL DEFAULT 'pending',
        last_chapter_index INTEGER,
        updated_at INTEGER NOT NULL,
        error_message TEXT
      )
    ''');
  }

  /// 內容索引明細——一列 = 一個可跳轉的精確定位片段（epic-10-search
  /// Issue 0，見 spec.md §1）。[locator] 是 Foliate 的 CFI 字串或 PDF 的
  /// JSON `{"page":int,"rect":PercentRect}`；[token_text] 是 [raw_text]
  /// 逐字層級 token 化後的可搜尋文字（見 `cjk_tokenizer.dart`）。
  static Future<void> _createBookContentIndexTable(Database db) async {
    await db.execute('''
      CREATE TABLE book_content_index (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        locator TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        token_text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_book_content_index_book_id ON book_content_index(book_id)');
  }

  /// FTS5 external-content 虛擬表＋同步 trigger（epic-10-search Issue 0，
  /// 見 spec.md §1）。只索引 `token_text`，實際文字以 [book_content_index]
  /// 為準。**務必**搭配 `onConfigure` 的 `PRAGMA recursive_triggers = ON`
  /// ——書籍刪除時 [book_content_index] 的列會被外鍵 `ON DELETE CASCADE`
  /// 級聯刪除，但依 SQLite 官方規範，級聯刪除預設「不會」觸發子表的
  /// `AFTER DELETE` trigger（需 `recursive_triggers = ON` 才會），少了這個
  /// PRAGMA，下面這三個 trigger 對級聯刪除完全不會執行，
  /// `book_content_fts` 將殘留指向不存在 rowid 的孤兒索引
  /// （review-spec.md C-1，本檔案 Task 1 Step 8-11 有專門的回歸測試鎖住
  /// 這個行為）。不加 `tokenize=` 參數，使用 FTS5 預設的 `unicode61`
  /// （ADR 0027：排除 `trigram`，Android 11 系統 SQLite 3.28.0 不支援）。
  static Future<void> _createBookContentFtsTable(Database db) async {
    await db.execute('''
      CREATE VIRTUAL TABLE book_content_fts USING fts5(
        token_text,
        content='book_content_index',
        content_rowid='rowid'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_ai AFTER INSERT ON book_content_index BEGIN
        INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_ad AFTER DELETE ON book_content_index BEGIN
        INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_au AFTER UPDATE ON book_content_index BEGIN
        INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
        INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
      END
    ''');
  }
```

在 `onCreate` 內（`app/lib/library/sqlite_library_repository.dart:123`，`await _createLayoutPresetTable(db);` 之後）新增：

```dart
        await _createLayoutPresetTable(db);
        await _createContentIndexStatusTable(db);
        await _createBookContentIndexTable(db);
        await _createBookContentFtsTable(db);
```

把 `open()` 的 `version: 23,`（第 42 行）改為 `version: 24,`。

**這一步刻意先不加 `PRAGMA recursive_triggers = ON`**（留到 Step 10 才加），目的是讓 Step 8-9 的級聯刪除測試先真的紅一次，證明這個 bug 不是純理論、測試本身有偵測能力。

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "全新安裝的資料庫包含"`
Expected: PASS

- [x] **Step 5：寫一個會失敗的測試——既有 version 23 裝置升級到 version 24**

比照檔案裡既有的「既有 version 22 裝置升級到 version 23」測試（約第 3260 行），在同一個新 `group` 裡新增：

```dart
    test('既有 version 23 裝置升級到 version 24，新增三張全文檢索資料表', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('elinkbook_migration_v23_to_v24_search_test');
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
            await db.insert('books', {
              'id': 'book1',
              'title': '既有的書',
              'format': 'epub',
              'filePath': '/books/book1.epub',
              'source': 'local',
              'progress': 0,
              'groupName': '未分類',
              'createTime': 1000,
              'lastReadTime': 1000,
              'is_downloaded': 1,
            });
          },
        ),
      );
      await oldDb.close();

      // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=23 →
      // newVersion=24）。
      final upgraded = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => upgraded.close());

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
        {'content_index_status', 'book_content_index', 'book_content_fts'},
      );

      // 既有書籍不受影響。
      final books = await upgraded.database.query('books');
      expect(books, hasLength(1));
      expect(books.single['id'], 'book1');
    });
```

- [x] **Step 6：執行測試，確認失敗**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "既有 version 23 裝置升級"`
Expected: FAIL（`onUpgrade` 還沒有 `oldVersion < 24` 分支，三張表不存在）。

- [x] **Step 7：實作 `onUpgrade` 的 `oldVersion < 24` 分支**

在 `app/lib/library/sqlite_library_repository.dart` 的 `onUpgrade` 內，`if (oldVersion < 23) { ... }` 區塊（約第 358-372 行）之後新增：

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

- [x] **Step 8：執行測試，確認通過**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "既有 version 23 裝置升級"`
Expected: PASS

- [x] **Step 9：寫一個會失敗的測試——級聯刪除書籍時，`book_content_fts` 必須同步清空（本工單最重要的回歸測試）**

在同一個 `group` 裡新增：

```dart
    test('刪除書籍時，book_content_index 與 book_content_fts 皆同步清空（驗證外鍵級聯+trigger，見 review-spec.md C-1）',
        () async {
      await repository.insertBook(_book('cascade-book'));
      await repository.database.insert('book_content_index', {
        'id': 'seg-1',
        'book_id': 'cascade-book',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2!/4/2/1:0)',
        'raw_text': '這是一句測試內容',
        'token_text': '這 是 一 句 測 試 內 容',
        'created_at': 1000,
      });

      // 插入當下應該已經透過 AFTER INSERT trigger 同步進 book_content_fts。
      final beforeDelete = await repository.database
          .rawQuery("SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '測 試'");
      expect(beforeDelete, hasLength(1));

      await repository.deleteBook('cascade-book');

      final indexRowsAfterDelete = await repository.database
          .query('book_content_index', where: 'book_id = ?', whereArgs: ['cascade-book']);
      expect(indexRowsAfterDelete, isEmpty,
          reason: 'book_content_index 應被外鍵 ON DELETE CASCADE 清空');

      final ftsRowsAfterDelete = await repository.database
          .rawQuery("SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '測 試'");
      expect(ftsRowsAfterDelete, isEmpty,
          reason:
              'book_content_fts 必須同步清空，若這裡不是空的代表 recursive_triggers 未開啟，'
              '級聯刪除沒有觸發 AFTER DELETE trigger，留下孤兒索引（review-spec.md C-1）');
    });
```

- [x] **Step 10：執行測試，確認失敗（證明 bug 是真的）**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "刪除書籍時"`
Expected: FAIL——`ftsRowsAfterDelete` 不是空的（`book_content_index` 那筆已經被級聯刪除，但 `book_content_fts` 因為 `recursive_triggers` 還沒開，AFTER DELETE trigger 沒有被觸發，孤兒索引留在原地）。這一步務必實際執行、親眼看到這個失敗，不要跳過——這是整個 Issue 0 最重要的一次驗證。

- [x] **Step 11：在 `onConfigure` 新增 `PRAGMA recursive_triggers = ON`**

在 `app/lib/library/sqlite_library_repository.dart` 的 `onConfigure` 內（約第 65-67 行，既有 `PRAGMA foreign_keys` 那行之後）新增：

```dart
        await db.execute(
          'PRAGMA foreign_keys = ${upgradingPastAnnotationUuidMigration ? 'OFF' : 'ON'}',
        );
        await db.execute('PRAGMA recursive_triggers = ON');
```

- [x] **Step 12：執行測試，確認通過**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart --plain-name "刪除書籍時"`
Expected: PASS

- [x] **Step 13：執行整個測試檔，確認沒有破壞既有測試**

Run: `flutter test app/test/library/sqlite_library_repository_test.dart`
Expected: 全數通過（這個檔案已有 3800+ 行既有測試，本次改動 `onConfigure`／`onCreate`／`onUpgrade`／版本號是高影響範圍的變更，務必跑一次全檔案，不要只跑新增的測試）。

- [x] **Step 14：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 15：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(search): 新增全文檢索資料表 schema（DB v23→v24）與級聯刪除修正"
```

---

### Task 2：中文 Tokenizer 純函式

**Files：**
- Create: `app/lib/search/cjk_tokenizer.dart`
- Test: `app/test/search/cjk_tokenizer_test.dart`

**Interfaces：**
- Consumes：無。
- Produces：`String tokenizeForIndex(String text)`、`String tokenizeForQuery(String query)`——Task 3（效能驗證）與後續 Issue 1（索引建置管線）、Issue 4（`SearchRepository.searchContent()`）直接呼叫這兩個函式，簽章與行為以本工單為準，不得更動。

- [x] **Step 1：寫失敗的測試——`tokenizeForIndex`**

新增 `app/test/search/cjk_tokenizer_test.dart`：

```dart
// app/test/search/cjk_tokenizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';

void main() {
  group('tokenizeForIndex', () {
    test('純中文逐字以空白分隔', () {
      expect(tokenizeForIndex('我喜歡貓'), '我 喜 歡 貓');
    });

    test('純英文維持原樣（不逐字拆）', () {
      expect(tokenizeForIndex('hello world'), 'hello world');
    });

    test('中英混合：中文逐字拆、英文單字維持完整', () {
      expect(tokenizeForIndex('我愛Flutter'), '我 愛 Flutter');
    });

    test('空字串回傳空字串', () {
      expect(tokenizeForIndex(''), '');
    });

    test('連續中文與數字混合：數字視為非 CJK 維持原樣', () {
      expect(tokenizeForIndex('第123章節'), '第 123 章 節');
    });
  });

  group('tokenizeForQuery', () {
    test('包裝為 FTS5 phrase query（雙引號包住轉換後字串）', () {
      expect(tokenizeForQuery('我愛貓'), '"我 愛 貓"');
    });

    test('空字串輸入回傳空字串（呼叫端不應送出查詢）', () {
      expect(tokenizeForQuery(''), '');
    });

    test('內部雙引號跳脫為兩個雙引號', () {
      expect(tokenizeForQuery('a"b'), '"a""b"');
    });
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test app/test/search/cjk_tokenizer_test.dart`
Expected: FAIL（`package:elinkbook/search/cjk_tokenizer.dart` 不存在，編譯錯誤）。

- [x] **Step 3：實作 `cjk_tokenizer.dart`**

新增 `app/lib/search/cjk_tokenizer.dart`：

```dart
// app/lib/search/cjk_tokenizer.dart

/// CJK 表意文字判定（Unicode Han 基本區 U+4E00–U+9FFF，`epic-10-search`
/// ADR 0027 範圍）。用整數區間比較而非 RegExp——`plan-issue-0.md` 審查
/// 實測：逐字元呼叫 `RegExp.hasMatch()` 比整數比較慢兩個數量級，且本函式
/// 會在 Issue 1 用於背景逐句掃描整本書、在 Task 3 效能驗證掃描 800 萬句
/// 合成資料，這個差距會被放大到分鐘等級，不是次要細節。
bool _isHanRune(int rune) => rune >= 0x4e00 && rune <= 0x9fff;

/// 供寫入索引使用：CJK 表意文字逐字以空白分隔，其餘字元（ASCII 字母/
/// 數字、既有標點）維持原樣不拆，讓 FTS5 標準 `unicode61` tokenizer 把
/// 每個 CJK 字元視為獨立 token，同時仍保留英文單字的既有詞級比對能力
/// （見 `docs/epics/epic-10-search/spec.md` §2、ADR 0027 決策 1）。
///
/// 實作刻意避開兩個效能陷阱（`plan-issue-0.md` 審查實測 100,000 次呼叫，
/// 換成本寫法後從每秒 15,420 次提升到每秒 135,685 次，約 9 倍）：
/// 1. **不在迴圈內呼叫 `buffer.toString()`**——那會把目前已累積的全部
///    內容複製成一個新字串，對含多個中文字的句子等於 O(N²) 的字串複製，
///    改用 [endsWithSpace] 布林變數追蹤「上一個字元是不是空白」。
/// 2. **不在函式內建立新的 `RegExp` 物件**——原本結尾的
///    `replaceAll(RegExp(r' +'), ' ')` 每次呼叫都會重新編譯一次正則，
///    改成在寫入當下就避免產生多餘空白，不需要事後再跑一次正則清理。
String tokenizeForIndex(String text) {
  if (text.isEmpty) return '';
  final buffer = StringBuffer();
  var endsWithSpace = false;

  for (final rune in text.runes) {
    if (_isHanRune(rune)) {
      if (buffer.isNotEmpty && !endsWithSpace) {
        buffer.write(' ');
      }
      buffer.writeCharCode(rune);
      buffer.write(' ');
      endsWithSpace = true;
    } else if (rune == 0x20) {
      // 一般空白字元：只在「目前不是緊接在空白之後、且已經有內容」時才
      // 寫入，達成跟 CJK 逐字空白分隔相容的「連續空白收斂成一個」效果。
      if (!endsWithSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        endsWithSpace = true;
      }
    } else {
      buffer.writeCharCode(rune);
      endsWithSpace = false;
    }
  }

  final result = buffer.toString();
  return endsWithSpace ? result.substring(0, result.length - 1) : result;
}

/// 供查詢使用：對使用者輸入做相同的字元切分，再包成 FTS5 phrase query
/// （雙引號包住、內部雙引號跳脫為 `""`），要求 token 依序相鄰，達成等效
/// 子字串比對。空字串輸入回傳空字串，呼叫端須自行判斷是否要送出查詢
/// （不應對 SQLite 送出 `MATCH '""'`）。
String tokenizeForQuery(String query) {
  final tokenized = tokenizeForIndex(query);
  if (tokenized.isEmpty) return '';
  final escaped = tokenized.replaceAll('"', '""');
  return '"$escaped"';
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test app/test/search/cjk_tokenizer_test.dart`
Expected: PASS（全部 8 個 test）

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/cjk_tokenizer.dart app/test/search/cjk_tokenizer_test.dart
git commit -m "feat(search): 新增中文字元層級 tokenizer 純函式"
```

---

### Task 3：全庫規模效能驗證 Benchmark（NFR-2 量化結論）

**Files：**
- Create: `app/test/search/content_search_performance_benchmark_test.dart`

**Interfaces：**
- Consumes：Task 1 的三張表（透過 `SqliteLibraryRepository.open()` ＋ `.database` getter）、Task 2 的 `tokenizeForIndex()`／`tokenizeForQuery()`。
- Produces：一個量化結論（PASS/FAIL 對 NFR-2），寫入 `docs/epics/epic-10-search/epic.md`，供 Scrum Master／後續 Issue 判斷是否需要兩層式索引備案（`spec.md` §8／ADR 0027 決策 4）。**這個結論本身就是本工單的產出之一，不是可以跳過的附加動作。**

> 這支測試**不是**routine `flutter test` 套件的一部分（`docs/epics/epic-10-search/issues.md` Issue 0 已明訂），單次執行時間可能長達數分鐘（合成資料量體是 1,000 本書 × 8,000 句 = 800 萬列），只在本工單驗收時與之後若修改 schema/tokenizer 時手動執行，不需要每次 `flutter test` 全套件都跑。

- [x] **Step 1：寫效能驗證測試**

新增 `app/test/search/content_search_performance_benchmark_test.dart`：

```dart
// app/test/search/content_search_performance_benchmark_test.dart
//
// epic-10-search Issue 0 效能驗證 Spike（見 spec.md §8、ADR 0027 決策 4）：
// 量化驗證單層 FTS5 索引設計在近真實規模（1,000 本書）下是否符合
// NFR-2（500ms 內回應）。不是 routine flutter test 套件的一部分，單次
// 執行可能長達數分鐘，只在驗收本工單／之後修改 schema 或 tokenizer 時
// 手動執行：
//   flutter test app/test/search/content_search_performance_benchmark_test.dart
//
// 若這裡的結論是「不符合 NFR-2」，依 spec.md §8／ADR 0027 決策 4，應在
// epic.md 記錄結論後另開一張 Issue 補建兩層式索引（書籍/章節級粗篩 FTS
// ＋ 命中後才查句級明細），不修改本工單已交付的 schema。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';

/// 依 spec.md §8 的估算基準：一般中文小說 20-30 萬字、7,000-12,000 句，
/// 取 8,000 句／本作為代表值。[bookCount] 預設 1,000（NFR-2 明訂的規模）
/// ——若只是在本機反覆調整測試本身、想縮短單次執行時間，可以暫時調低
/// 這兩個常數，但正式記錄進 epic.md 的結論**必須**是用這兩個預設值跑出來
/// 的結果，不可用縮小規模的數據冒充。
const int _benchmarkBookCount = 1000;
const int _benchmarkSentencesPerBook = 8000;

/// 產生近真實規模的合成內容索引資料，直接寫入 Task 1 建立的
/// `book_content_index`（AFTER INSERT trigger 會自動同步進
/// `book_content_fts`，見 sqlite_library_repository.dart
/// `_createBookContentFtsTable`）。每本書每 5,000 句安插一句含
/// 「測試句子編號」關鍵詞的句子，確保之後的 MATCH 查詢有真實命中可算。
Future<void> _seedSyntheticContentIndex(
  Database db, {
  required int bookCount,
  required int sentencesPerBook,
}) async {
  const chunkSize = 2000;
  var batch = db.batch();
  var pendingInBatch = 0;

  Future<void> flushIfNeeded() async {
    if (pendingInBatch >= chunkSize) {
      await batch.commit(noResult: true);
      batch = db.batch();
      pendingInBatch = 0;
    }
  }

  for (var b = 0; b < bookCount; b++) {
    final bookId = 'bench-book-$b';
    await db.insert('books', {
      'id': bookId,
      'title': '效能測試書 $b',
      'format': 'epub',
      'filePath': 'content://bench/$b',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
      'is_downloaded': 1,
    });
    for (var s = 0; s < sentencesPerBook; s++) {
      final rawText = s % 5000 == 0
          ? '這是第 $b 本書測試句子編號 $s，包含可搜尋的關鍵詞。'
          : '這是第 $b 本書的普通內容第 $s 句，純粹填充資料量體不含特殊關鍵詞。';
      batch.insert('book_content_index', {
        'id': 'bench-$b-$s',
        'book_id': bookId,
        'chapter_index': s ~/ 100,
        'locator': 'epubcfi(/6/${(s % 20) * 2 + 2}!/4/2/1:0)',
        'raw_text': rawText,
        'token_text': tokenizeForIndex(rawText),
        'created_at': 1000,
      });
      pendingInBatch++;
      await flushIfNeeded();
    }
  }
  if (pendingInBatch > 0) {
    await batch.commit(noResult: true);
  }
}

void main() {
  group('全庫搜尋效能驗證 Benchmark（Issue 0 Spike）', () {
    late SqliteLibraryRepository repository;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final tempDir =
          await Directory.systemTemp.createTemp('elinkbook_search_benchmark');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'benchmark.db');

      repository = await SqliteLibraryRepository.open(dbPath);
      // 這是拋棄式的合成資料 benchmark DB，不需要 durability 保證，換取
      // 寫入速度：預設的 fsync-on-commit 行為在 4,000 次 batch.commit()
      // 上會有明顯的磁碟同步開銷（`plan-issue-0.md` 審查 M-1）。
      await repository.database.execute('PRAGMA synchronous = OFF');

      // 資料建置本身不計入 NFR-2 的 500ms 預算（NFR-2 量測的是查詢延遲，
      // 不是索引建置耗時），但仍印出耗時供人工參考背景索引建置量級。
      final seedStopwatch = Stopwatch()..start();
      await _seedSyntheticContentIndex(
        repository.database,
        bookCount: _benchmarkBookCount,
        sentencesPerBook: _benchmarkSentencesPerBook,
      );
      seedStopwatch.stop();
      // ignore: avoid_print
      print(
          '[benchmark] 合成資料建置完成：$_benchmarkBookCount 本書 × $_benchmarkSentencesPerBook 句 '
          '= ${_benchmarkBookCount * _benchmarkSentencesPerBook} 列，耗時 ${seedStopwatch.elapsed}');
    });

    tearDownAll(() => repository.close());

    test('book_content_fts MATCH 查詢在 1,000 本書規模下於 500ms 內回應（NFR-2）',
        () async {
      final tokenizedQuery = tokenizeForQuery('測試句子編號');

      // 【審查修正 I-1】原本這裡量測的是不含 ROW_NUMBER()/bm25() 的簡化
      // 查詢，只因為加了 LIMIT 300 就能提早終止掃描、量出來的數字會失真
      // 偏快。正式產品（spec.md §5）的 searchContent() 查詢用了
      // `ROW_NUMBER() OVER (PARTITION BY book_id ORDER BY bm25(...))`
      // 依書籍分組排序——window function 依語意必須先算出每一筆符合列
      // 的 bm25 分數、確定每個分區內的完整排序，才能算出 rn，SQLite
      // 無法對這段套用「找到前 N 筆就提早結束」的最佳化。這裡量測的必須
      // 是這一段真正會執行的查詢，不能用簡化版本代替。
      const productionQuery = '''
        SELECT book_id, locator, raw_text FROM (
          SELECT bci.book_id, bci.locator, bci.raw_text,
                 ROW_NUMBER() OVER (
                   PARTITION BY bci.book_id
                   ORDER BY bm25(book_content_fts)
                 ) AS rn
          FROM book_content_fts
          JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
          WHERE book_content_fts MATCH ?
        ) WHERE rn <= ?
      ''';
      const perBookLimit = 3; // 比照 spec.md §5 的預設值。

      // 純 MATCH（不含分組排序）僅作為對照組印出，幫助判斷瓶頸在
      // FTS5 掃描本身還是 window function 排序，不參與 PASS/FAIL 判定。
      final matchOnlyStopwatch = Stopwatch()..start();
      final matchOnlyRows = await repository.database.rawQuery(
        'SELECT bci.book_id FROM book_content_fts '
        'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
        'WHERE book_content_fts MATCH ?',
        [tokenizedQuery],
      );
      matchOnlyStopwatch.stop();
      // ignore: avoid_print
      print('[benchmark] 對照組（純 MATCH，不分組排序）耗時：'
          '${matchOnlyStopwatch.elapsedMilliseconds}ms，命中 ${matchOnlyRows.length} 筆'
          '（僅供對照，不參與 NFR-2 判定）');

      // 【審查採納 M-2】第一次查詢是 cold cache（SQLite 尚未把相關頁面
      // 讀進 page cache），最貼近使用者在一個新 session 第一次搜尋的真實
      // 體驗，NFR-2 的 PASS/FAIL 判定以這一次為準；之後再跑 4 次 warm
      // cache 當作對照組，兩者都印出、都寫進 epic.md，不要只挑對結論
      //有利的那個數字。
      final coldStopwatch = Stopwatch()..start();
      final coldRows = await repository.database
          .rawQuery(productionQuery, [tokenizedQuery, perBookLimit]);
      coldStopwatch.stop();

      final warmDurations = <Duration>[];
      for (var i = 0; i < 4; i++) {
        final warmStopwatch = Stopwatch()..start();
        await repository.database
            .rawQuery(productionQuery, [tokenizedQuery, perBookLimit]);
        warmStopwatch.stop();
        warmDurations.add(warmStopwatch.elapsed);
      }
      final warmMillis = warmDurations.map((d) => d.inMilliseconds).toList()
        ..sort();
      final warmMedian = warmMillis[warmMillis.length ~/ 2];

      // ignore: avoid_print
      print('[benchmark] 正式查詢（含 ROW_NUMBER/bm25 分組排序）'
          'Cold：${coldStopwatch.elapsedMilliseconds}ms，命中 ${coldRows.length} 筆；'
          'Warm 4 次：$warmMillis ms，中位數 ${warmMedian}ms');

      expect(coldRows, isNotEmpty, reason: '合成資料應包含至少一筆命中，否則測試本身有誤');
      expect(
        coldStopwatch.elapsed,
        lessThan(const Duration(milliseconds: 500)),
        reason: 'NFR-2：全庫搜尋在 1,000 本書規模下應於 500ms 內回應（以 cold cache '
            '量測，最貼近使用者實際體驗）。若這裡失敗，依 spec.md §8／ADR 0027 決策 4，'
            '需另開 Issue 補建兩層式索引（書籍/章節級粗篩 FTS ＋ 命中後才查句級明細），'
            '不要放寬這個斷言。',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
```

- [x] **Step 2：執行測試，記錄實際結果**

Run: `flutter test app/test/search/content_search_performance_benchmark_test.dart`

這一步不是單純「Expected: PASS」——**無論通過或失敗，都要把 terminal 印出的全部 `[benchmark]` 行實際數字記下來**：合成資料建置耗時、對照組（純 MATCH）耗時與命中筆數、正式查詢（含 `ROW_NUMBER`/`bm25` 分組排序）的 Cold 耗時與命中筆數、Warm 4 次的個別耗時與中位數。下一步要把這些數字寫進 `epic.md`。

- [x] **Step 3：將結論寫入 `epic.md`**

編輯 `docs/epics/epic-10-search/epic.md`，在開發記錄最後新增一則條目，格式比照既有條目（含日期），內容包含：
- 實測環境（開發機或 CI，非真實 Android 裝置——若條件允許，備註「建議之後在真機/模擬器上覆核一次」）。
- Step 2 印出的實際數字，**分開列出**：對照組（純 MATCH）耗時／正式查詢 Cold 耗時／正式查詢 Warm 中位數，三者都要記錄，不要只挑對結論有利的那個數字（NFR-2 的 PASS/FAIL 判定以正式查詢 Cold 耗時為準，其餘兩組數字是輔助判斷瓶頸位置的對照資料）。
- 結論：符合 NFR-2 或不符合。
- 若不符合：註明「已規劃另開 Issue 補建兩層式索引，見 spec.md §8」，並告知人類這個 Spike 的判斷結果，不要自行決定是否要接著開新 Issue（依 SDD 工作流程，這屬於 Scrum Master 職責，需要人類確認）。

- [x] **Step 4：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5：Commit**

```bash
git add app/test/search/content_search_performance_benchmark_test.dart docs/epics/epic-10-search/epic.md
git commit -m "test(search): 新增全庫搜尋效能驗證 Benchmark，記錄 NFR-2 量化結論"
```

---

## Self-Review Checklist（供執行者/審查者核對，非新增步驟）

- **Spec 涵蓋**：`spec.md` §1（Task 1）、§2（Task 2）、§8（Task 3）皆有對應任務；`issues.md` Issue 0 列出的三項驗收標準（schema／tokenizer／效能驗證量化結論）三個 Task 各自對應一項。
- **無佔位符**：三個 Task 的每個 Step 都是可直接執行的具體程式碼/指令，沒有「TODO」「之後補上」字樣。
- **型別/命名一致性**：`tokenizeForIndex`／`tokenizeForQuery` 在 Task 2 定義、Task 3 直接 import 使用，簽章一致；`_createContentIndexStatusTable`／`_createBookContentIndexTable`／`_createBookContentFtsTable` 在 Task 1 定義並在同一個 Task 的 `onCreate`／`onUpgrade` 兩處呼叫，命名一致。
