# Epic 8 Issue 4 — 同步引擎核心：劃線/備註/書籤同步 + 墓碑清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking。

**Goal:** 新增 `SyncEngine.runCheckpoint()`，實作劃線/備註/書籤三種標註跨裝置同步（PocketBase Batch API 推送＋游標式下載合併）與本機墓碑清理，供 Issue 6（觸發機制）串接呼叫。

**Architecture:** `SyncEngine` 是唯一的不純（impure）協調層，持有共用 `Database` 連線、`SyncAccountRepository`（讀憑證）、`SyncMetadataRepository`（讀寫游標/暫存表）、`PocketBaseClientFactory`（比照 Issue 2 `SyncClient` 既有測試接縫）。核心決策邏輯（dirty 判定、推送批次組裝、下載合併判定、墓碑篩選）皆抽成純函式（輸入輸出皆為 plain data，不摸 DB／網路），比照 spec.md「Testing Decisions」與既有 `resolveZoneActions()`/`resolveCustomFontUri()` 慣例。三張本機標註表（`bookmarks`/`highlights`/`notes`）欄位結構高度相似但不完全相同，用一個 `SyncTableSpec`（每個 collection 一份、內含推送/下載欄位轉換的純函式）取代三份幾乎重複的程式碼，避免過度抽象成通用反射框架。

**Tech Stack:** Flutter/Dart、`package:pocketbase` ^0.24.0（Issue 2 已引入）、`package:sqflite`。純 widget/unit test（`flutter test`）供純函式與 DB 存取層邏輯；`SyncEngine` 端到端行為由 `integration_test`（真機，連線 Issue 7 已架好的 `http://pbdev.jigong.org` 測試實例）驗證。

## Global Constraints

- **時間戳記單位**：本機 `updated_at`/`deleted_at` 一律毫秒（`DateTime.now().millisecondsSinceEpoch`），與既有 `createTime`/`lastReadTime` 同單位（spec.md 審查修正紀錄已定案，非本計畫新決策）。
- **PocketBase Batch 分批上限**：每批最多 100 筆（spec.md「同步引擎」步驟 2）。
- **任一批推送失敗即整個 checkpoint 失敗**：不更新任何 `sync_metadata` 游標（含已成功的部分），下次重試整批重來（spec.md「同步引擎」步驟 7）。
- **每筆 create/update payload 必須明確帶 `user` 欄位**（spec.md 審查修正，PocketBase API rule 不會自動代入，見 `docker/pb_migrations/1785715200_create_sync_collections.js` 第 24-27 行註解）。
- **PocketBase number 欄位的「未設值」預設為 `0`，不是真正的 SQL NULL**——這是 Issue 7 `pb_hooks` 墓碑清理腳本審查時已發現並修正的同一個特性（`deleted_at != null` 對 PocketBase number 欄位無效，改為 `deleted_at > 0`，見 `plan-issue-7.md`「實作結果審查修正紀錄」）。本計畫的下載端同樣受影響，且範圍比 Issue 7 當時發現的更廣——不只 `deleted_at`，`pdf_page_index`/`progression` 等可空 number 欄位、以及可空 text 欄位（未設值預設為空字串 `""`，非 `null`）皆有同樣的「零值 ≠ 未設定」問題，見 Task 3「與 spec.md／Issue 7 的落差說明」。
- **本 Issue 不含 Checkpoint 觸發來源與併發鎖**（App 生命週期/書籍切換/閒置計時器、`_isSyncing` 執行鎖）——`runCheckpoint()` 本 Issue 僅需可被手動/測試呼叫，觸發機制與併發防護見 Issue 6（issues.md 已明確如此分工）。
- **本 Issue 不實作閱讀位置同步**（`books.position_updated_at`/`position_synced_server_updated_at` 的推送/下載/衝突彈窗）——留給 Issue 5 擴充同一個 `runCheckpoint()`（issues.md 已明確如此分工），本計畫的推送/下載流程只處理 `bookmarks`/`highlights`/`notes` 三個 collection。

## 與 issues.md／spec.md 的落差說明

依既有專案慣例（比照 `plan-issue-3.md`「與 issues.md 的落差說明」），查證程式碼庫現況後發現本計畫需要處理 3 項 issues.md／spec.md 皆未明確規劃、但邏輯上必要的缺口：

1. **`bookmarks`/`highlights`/`notes` 的 `delete()`/`deleteAllForBook()` 目前仍是真正的 `DELETE FROM`**（見 `bookmarks_repository.dart`/`highlights_repository.dart`/`notes_repository.dart` 現行程式碼與其註解「軟刪除轉換是 Issue 4 的範圍」）——spec.md「本機 Schema 變更」／design.md 決策 8 早已定案「刪除操作改為 `UPDATE ... SET deleted_at = ?`」，但實際轉換動作明確標記留給本 Issue。若不轉換，墓碑清理（本 Issue 的驗收標準之一）將永遠無墓碑可清（見 Task 2）。
2. **`HighlightsRepository.delete()`／`deleteAllForBook()` 轉為軟刪除後，會遺失既有 FK `ON DELETE SET NULL` 的自動退化行為**——`notes.highlight_id REFERENCES highlights(id) ON DELETE SET NULL` 只在**真正的** `DELETE FROM highlights` 時觸發，改成 `UPDATE` 後 SQLite 不會再自動把依附備註的 `highlight_id` 退化為 `NULL`。現有測試 `notes_repository_test.dart`「FK 退化行為」兩則測試直接依賴這個 FK 副作用，若不手動複製這段邏輯會直接迴歸（見 Task 2）。
3. **既有書籍升級後 `content_fingerprint` 為 `NULL` 的補算回填時機，`plan-issue-3.md` 已明確載明「留待實作時依 Issue 4 的介面決定」**——本計畫將其設計為：僅在某本書被牽涉進本次 checkpoint 的 dirty 標註列（即這本書有劃線/備註/書籤異動待推送）、且該書 `content_fingerprint` 仍為 `NULL` 時，即時呼叫既有 `computeBookContentFingerprint()` 補算並寫回，而非在每次 checkpoint 對全圖書庫掃描補算（YAGNI——沒有待推送異動的書籍，指紋在本 Issue 範圍內不影響任何行為，見 Task 7）。
4. **spec.md 未定義「`book_fingerprint` 查無對應本機書籍時的待處理佇列」精確 schema**（僅描述行為，未定 schema）——本計畫新增 `sync_pending_records` 表（Task 1）承接此需求，並新增 `sync_remote_ids` 表（同一個 Task）記錄本機 `client_id` 對應的 PocketBase 內部 `id`，供推送時判斷 create 或 update（PocketBase 官方 `id` 系統欄位不接受本專案的 UUID 格式當自訂 id，見 Task 1 說明）。

---

### Task 1：Migration v17→v18——`sync_remote_ids` + `sync_pending_records` 表

**Files:**
- Modify：`app/lib/library/sqlite_library_repository.dart`
- Test：`app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes：無（獨立的 schema 變更，不依賴本 Epic 其他 Task）。
- Produces：新表 `sync_remote_ids`（`collection TEXT, client_id TEXT, remote_id TEXT`，複合主鍵 `(collection, client_id)`）與 `sync_pending_records`（`collection TEXT, client_id TEXT, book_fingerprint TEXT, payload_json TEXT`，複合主鍵 `(collection, client_id)`）。供 Task 6（`SyncMetadataRepository`）存取。

**為什麼需要 `sync_remote_ids`**：PocketBase 每個 collection 內建的 `id` 系統欄位有自己的格式限制，本專案的標註 UUID（含連字號，如 `a1b2c3d4-...`）不保證能直接當作 PocketBase 自訂 `id` 使用（且 spec.md 明訂「App 端完全不讀取/比對它」）。因此本機需要自己維護一份「`client_id` → PocketBase 該筆紀錄真正的 `id`」對照表，才能在推送時正確判斷該送 `create`（尚無對照）還是 `update`（已有對照，帶入該 `id`）——這張表在「推送新建成功」與「下載合併」兩個時機都會寫入（見 Task 7/8）。

**為什麼需要 `sync_pending_records`**：spec.md「跨裝置參照設計」明訂 `book_fingerprint` 查無對應本機書籍時「暫緩合併、留在待處理佇列」。由於下載游標（`sync_metadata.lastPulledServerUpdatedAt_<collection>`）在該筆紀錄被下載當下就會前進（spec.md「同步引擎」步驟 5：「若這次沒查到任何新紀錄則維持原值不變」——隱含「查到就更新」，不論該筆紀錄有沒有被成功合併），該筆遠端紀錄之後不會再被下載到，若不落地保存，之後即使使用者匯入了對應的書，這筆同步紀錄也永遠遺失。

- [x] **Step 1：撰寫失敗測試——新鮮安裝與升級兩種情境皆應建立新表**

在 `app/test/library/sqlite_library_repository_test.dart` 找到既有「既有 version 16 裝置...升級到 version 17」測試（`group` 內最後一個 `test(...)`）之後，新增：

```dart
  test('新鮮安裝（version 18）時，sync_remote_ids／sync_pending_records 兩張表皆已建立', () async {
    final syncRemoteIdsColumns =
        await repository.database.rawQuery('PRAGMA table_info(sync_remote_ids)');
    expect(
      syncRemoteIdsColumns.map((c) => c['name'] as String).toSet(),
      {'collection', 'client_id', 'remote_id'},
    );

    final syncPendingColumns = await repository.database
        .rawQuery('PRAGMA table_info(sync_pending_records)');
    expect(
      syncPendingColumns.map((c) => c['name'] as String).toSet(),
      {'collection', 'client_id', 'book_fingerprint', 'payload_json'},
    );
  });

  test('既有 version 17 裝置升級到 version 18，正確新增 sync_remote_ids／sync_pending_records 兩張表',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v17_to_v18_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已在 version 17、兩張新表皆不存在」的資料庫：直接開一個空的
    // version 17 資料庫（本次遷移新增的兩張表彼此獨立、不依賴 books 等
    // 既有表，不需要比照 v16→v17 測試重刻完整歷史 schema）。刻意**不**用
    // 「先用目前版本開一次、再把 version 手動改回 17」的手法——那樣兩張
    // 新表會在第一次 open() 時就已經被 onCreate 建立，之後的「升級」測試
    // 只是對已存在的表重複執行 CREATE TABLE IF NOT EXISTS，不會真的驗證
    // 到 onUpgrade 分支本身是否存在/正確。
    final v17Db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 17, onCreate: (db, version) async {}),
    );
    await v17Db.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final syncRemoteIdsColumns =
        await upgraded.database.rawQuery('PRAGMA table_info(sync_remote_ids)');
    expect(syncRemoteIdsColumns, isNotEmpty);

    final syncPendingColumns = await upgraded.database
        .rawQuery('PRAGMA table_info(sync_pending_records)');
    expect(syncPendingColumns, isNotEmpty);
  });
```

- [x] **Step 2：執行測試，確認因表不存在而失敗**

Run：

```bash
cd app
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：FAIL，`no such table: sync_remote_ids`（或等效訊息）。

- [x] **Step 3：新增建表函式，`onCreate`／`onUpgrade` 皆呼叫，版本號改為 18**

`sqlite_library_repository.dart` 第 28 行 `version: 17,` 改為：

```dart
      version: 18,
```

`onCreate` 內、第 88 行 `await _createSyncMetadataTable(db);` 之後新增：

```dart
        await _createSyncRemoteIdsTable(db);
        await _createSyncPendingRecordsTable(db);
```

`onUpgrade` 內、第 234-254 行 `if (oldVersion < 17) { ... }` 區塊**之後**（`}` 之後、`onOpen` 之前）新增：

```dart
        if (oldVersion < 18) {
          // epic-8-sync Issue 4：推送 create/update 判斷所需的本機 remote id
          // 對照表，以及 book_fingerprint 查無對應本機書籍時的待處理佇列
          // （見 spec.md「跨裝置參照設計」／plan-issue-4.md「與 issues.md／
          // spec.md 的落差說明」）。兩者皆是全新的獨立表（非既有表新增
          // 欄位），比照 oldVersion < 8/9/16 既有原則，同一層級、無條件
          // 檢查即可。
          await _createSyncRemoteIdsTable(db);
          await _createSyncPendingRecordsTable(db);
        }
```

在 `_createSyncMetadataTable`（第 591-618 行）之後新增兩個私有方法：

```dart
  static Future<void> _createSyncRemoteIdsTable(Database db) async {
    // client_id -> PocketBase 該筆紀錄真正 id 的對照表（epic-8-sync
    // Issue 4，spec.md「跨裝置參照設計」；精確理由見
    // docs/epics/epic-8-sync/plans/plan-issue-4.md Task 1）：PocketBase
    // 自己的 id 系統欄位不接受本專案 UUID（含連字號）格式，且 App 端
    // 完全不比對它，因此需要本機自己維護這份對照，供推送時判斷該送
    // create（查無對照）還是 update（查到對照，帶入該 id）。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_remote_ids (
        collection TEXT NOT NULL,
        client_id TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        PRIMARY KEY (collection, client_id)
      )
    ''');
  }

  static Future<void> _createSyncPendingRecordsTable(Database db) async {
    // 下載時 book_fingerprint 查無對應本機書籍的待處理佇列（epic-8-sync
    // Issue 4，spec.md「跨裝置參照設計」：「該筆同步紀錄暫緩合併、留在
    // 待處理佇列」；精確理由見 plan-issue-4.md Task 1）。payload_json
    // 存放該筆遠端紀錄的原始欄位（未經格式判斷正規化，見
    // sync_table_specs.dart），待對應書籍匯入後才正規化並落地。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_pending_records (
        collection TEXT NOT NULL,
        client_id TEXT NOT NULL,
        book_fingerprint TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (collection, client_id)
      )
    ''');
  }
```

- [x] **Step 4：執行測試，確認通過**

Run：

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：PASS（全部既有＋新增 2 則測試）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/library/sqlite_library_repository.dart test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 1 — Migration v17->v18，新增 sync_remote_ids／sync_pending_records"
```

Expected：`flutter analyze` 顯示 "No issues found!"。

---

### Task 2：`bookmarks`/`highlights`/`notes` 軟刪除轉換 + FK 退化行為手動複製

**Files:**
- Modify：`app/lib/reader/bookmarks_repository.dart`
- Modify：`app/lib/reader/highlights_repository.dart`
- Modify：`app/lib/reader/notes_repository.dart`
- Test：`app/test/reader/bookmarks_repository_test.dart`
- Test：`app/test/reader/highlights_repository_test.dart`
- Test：`app/test/reader/notes_repository_test.dart`

**Interfaces:**
- Consumes：無。
- Produces：`delete()`/`deleteAllForBook()` 對外行為不變（呼叫端無感，`listByBook()` 依然看不到已刪除的紀錄），但內部改為 `UPDATE ... SET deleted_at = ?, updated_at = ?`，供 Task 7（推送 dirty 判定）／Task 8（墓碑清理）使用。

- [x] **Step 1：撰寫失敗測試——`bookmarks_repository_test.dart`**

在既有「delete 移除指定單筆書籤，其餘不受影響」測試之後新增：

```dart

  test('delete 為軟刪除：資料列仍實際存在，deleted_at／updated_at 皆已寫入', () async {
    await repository
        .insert(const Bookmark(id: 'bm15', bookId: 'b1', name: 'A', progression: 0.1));

    await repository.delete('bm15');

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm15']);
    expect(rawRows, hasLength(1));
    expect(rawRows.single['deleted_at'], isNotNull);
    expect(rawRows.single['updated_at'], isNotNull);
  });

  test('deleteAllForBook 為軟刪除：資料列仍實際存在，deleted_at 皆已寫入', () async {
    await repository
        .insert(const Bookmark(id: 'bm16', bookId: 'b1', name: 'A', progression: 0.1));

    await repository.deleteAllForBook('b1');

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm16']);
    expect(rawRows, hasLength(1));
    expect(rawRows.single['deleted_at'], isNotNull);
  });
```

- [x] **Step 2：撰寫失敗測試——`highlights_repository_test.dart`（含 FK 退化行為手動複製）**

先讀取該檔案既有的 import／`setUp` 區塊確認 `notesRepository` 變數名稱（`notes_repository_test.dart` 既有「FK 退化行為」測試已在同一個檔案的 `setUp` 內建構 `NotesRepository`；若 `highlights_repository_test.dart` 目前沒有建構 `NotesRepository`，比照該檔案既有的 `setUp` 模式新增），在既有「delete 移除...其餘不受影響」測試之後新增：

```dart

  test('delete 為軟刪除：資料列仍實際存在，deleted_at 已寫入', () async {
    await repository.insert(
      const Highlight(id: 'h10', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );

    await repository.delete('h10');

    final rawRows = await libraryRepository.database
        .query('highlights', where: 'id = ?', whereArgs: ['h10']);
    expect(rawRows, hasLength(1));
    expect(rawRows.single['deleted_at'], isNotNull);
  });

  test('delete 手動複製既有 FK ON DELETE SET NULL 行為：依附備註的 highlight_id 正確退化為 null',
      () async {
    final notesRepository = NotesRepository(libraryRepository.database);
    await repository.insert(
      const Highlight(id: 'h11', bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    );
    await notesRepository.insert(
      const Note(id: 'n20', bookId: 'b1', text: '依附備註', progression: 0.2, highlightId: 'h11'),
    );

    await repository.delete('h11');

    final note = (await notesRepository.listByBook('b1')).single;
    expect(note.highlightId, isNull);
    expect(note.text, '依附備註');
  });

  test('deleteAllForBook 手動複製既有 FK ON DELETE SET NULL 行為：所有依附備註皆退化為純備註',
      () async {
    final notesRepository = NotesRepository(libraryRepository.database);
    await repository.insert(
      const Highlight(id: 'h12', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    await repository.insert(
      const Highlight(id: 'h13', bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    );
    await notesRepository.insert(
      const Note(id: 'n21', bookId: 'b1', text: 'N1', progression: 0.1, highlightId: 'h12'),
    );
    await notesRepository.insert(
      const Note(id: 'n22', bookId: 'b1', text: 'N2', progression: 0.2, highlightId: 'h13'),
    );

    await repository.deleteAllForBook('b1');

    final notes = await notesRepository.listByBook('b1');
    expect(notes, hasLength(2));
    expect(notes.every((n) => n.highlightId == null), isTrue);
  });
```

- [x] **Step 3：撰寫失敗測試——`notes_repository_test.dart`**

在既有「delete 移除...其餘不受影響」測試之後新增：

```dart

  test('delete 為軟刪除：資料列仍實際存在，deleted_at 已寫入', () async {
    await notesRepository.insert(const Note(id: 'n23', bookId: 'b1', text: 'A', progression: 0.1));

    await notesRepository.delete('n23');

    final rawRows = await libraryRepository.database
        .query('notes', where: 'id = ?', whereArgs: ['n23']);
    expect(rawRows, hasLength(1));
    expect(rawRows.single['deleted_at'], isNotNull);
  });
```

- [x] **Step 4：執行測試，確認因仍是真實 DELETE 而失敗**

Run：

```bash
flutter test test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
```

Expected：FAIL——新增的「軟刪除」測試會失敗（`rawRows` 為空，因為目前仍是真正 `DELETE FROM`）。

- [x] **Step 5：`BookmarksRepository`／`NotesRepository` 改為軟刪除（無 FK 退化顧慮）**

`bookmarks_repository.dart` 的 `delete()`/`deleteAllForBook()`（第 53-59 行）改為：

```dart
  Future<void> delete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'bookmarks',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllForBook(String bookId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'bookmarks',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
```

`listByBook()`（第 31-39 行）的 `where:` 改為包含軟刪除過濾（同步同步引擎需要看到已刪除列，見 Task 7/8 直接用 `_db.rawQuery` 讀取，不經過本 repository，故本方法只需服務既有的「UI 看不到已刪除項目」需求）：

```dart
  Future<List<Bookmark>> listByBook(String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }
```

`notes_repository.dart` 比照同樣改法（`delete()`/`deleteAllForBook()`/`listByBook()`），欄位/表名換成 `notes`/`book_id`：

```dart
  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> delete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'notes',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllForBook(String bookId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update(
      'notes',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
```

- [x] **Step 6：`HighlightsRepository` 改為軟刪除，並手動複製 FK `ON DELETE SET NULL` 行為**

`highlights_repository.dart` 整份改為：

```dart
import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  /// `updated_at`（epic-8-sync Issue 1，供雲端同步 dirty 判定使用，見
  /// `sqlite_library_repository.dart` `_createHighlightsTable`）由本層
  /// 補上目前時間戳記，不放進 [Highlight] 模型本身。
  Future<void> insert(Highlight highlight) {
    return _db.insert('highlights', {
      ...highlight.toMap(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 依書中位置順序排序：EPUB 用 `progression` 比例、PDF 用
  /// `pdf_page_index`（Issue 3 新增），兩者互斥、一本書只會用到其中一組
  /// （比照 `BookmarksRepository.listByBook` 既有的 `COALESCE` 慣例）。
  /// `deleted_at IS NULL` 排除已（軟）刪除的紀錄（epic-8-sync Issue 4）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  /// epic-8-sync Issue 4：改為軟刪除（`UPDATE ... SET deleted_at = ?`），
  /// 供雲端同步的墓碑清理使用（見 spec.md「墓碑清理」）。原本
  /// `notes.highlight_id REFERENCES highlights(id) ON DELETE SET NULL`
  /// 這條外鍵約束只在**真正的** `DELETE FROM` 時觸發，改為軟刪除後不會
  /// 再自動生效，因此這裡手動複製同一段退化邏輯——依附這筆劃線的備註
  /// 一併退化為純備註（`highlight_id` 設為 `null`），行為與改動前完全
  /// 一致（見 plan-issue-4.md「與 issues.md／spec.md 的落差說明」第 2 點）。
  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'highlight_id': null, 'updated_at': now},
      where: 'highlight_id = ?',
      whereArgs: [id],
    );
    await _db.update(
      'highlights',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批次版本，同樣手動複製 FK 退化邏輯（見 [delete]）。**改用子查詢**
  /// 而非「先查出全部 id 清單、再組 `IN (?,?,?...)` 佔位符」——後者對單本
  /// 書籍持有大量劃線（超過 SQLite 單一陳述式的變數上限）時會拋出
  /// `too many SQL variables` 而崩潰（審查意見 Important #1，2026-08-04
  /// `/superpowers:requesting-code-review` 發現，見文末「審查修正
  /// 紀錄」）；子查詢完全不受此限制，且不需要先做一次額外的 `SELECT`。
  Future<void> deleteAllForBook(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'highlight_id': null, 'updated_at': now},
      where: 'highlight_id IN '
          '(SELECT id FROM highlights WHERE book_id = ? AND deleted_at IS NULL)',
      whereArgs: [bookId],
    );
    await _db.update(
      'highlights',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
}
```

- [x] **Step 7：執行測試，確認全數通過（含既有的 FK 退化行為測試，現在改由手動邏輯達成同樣效果）**

Run：

```bash
flutter test test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
```

Expected：PASS，包含 `notes_repository_test.dart` 既有兩則「FK 退化行為」測試（現在是手動邏輯而非真正 FK 觸發，但對外行為不變）。

- [x] **Step 8：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（確認無 regression，尤其是任何依賴 `listByBook()` 筆數的既有測試）。

```bash
git add lib/reader/bookmarks_repository.dart lib/reader/highlights_repository.dart lib/reader/notes_repository.dart test/reader/bookmarks_repository_test.dart test/reader/highlights_repository_test.dart test/reader/notes_repository_test.dart
git commit -m "fix(epic-8-sync): Issue 4 Task 2 — bookmarks/highlights/notes 改為軟刪除，手動複製 FK 退化行為"
```

---

### Task 3：純資料模型 + 資料表對照設定

**Files:**
- Create：`app/lib/sync/sync_models.dart`
- Create：`app/lib/sync/sync_table_specs.dart`
- Test：`app/test/sync/sync_table_specs_test.dart`

**Interfaces:**
- Consumes：`BookFileFormat`（`app/lib/library/models/library_enums.dart`）、`RecordModel`（`package:pocketbase/pocketbase.dart`）。
- Produces：`SyncCollection` enum（`bookmarks`/`highlights`/`notes`，各自帶 `localTable`/`remoteCollection` getter）、`PushOperation`、`RemoteRecordMergeInput`、`MergeDecision`、`BookLookup`（`sync_models.dart`）；`SyncTableSpec` 與三個具體實例 `bookmarksSyncSpec`/`highlightsSyncSpec`/`notesSyncSpec`、`syncTableSpecs`（`Map<SyncCollection, SyncTableSpec>`，`sync_table_specs.dart`）。供 Task 4（推送）／Task 5（合併）／Task 7/8（`SyncEngine`）使用。

**與 spec.md／Issue 7 的落差說明（PocketBase 零值問題，見 Global Constraints）**：PocketBase 的 `number`／`text` 型別欄位在建立紀錄時若未帶入該欄位，儲存的是該型別的零值（`number` → `0`、`text` → `""`），**不是** SQL NULL。這代表：

- `deleted_at`（number，可空）：未刪除的紀錄下載回來會是 `0`，必須正規化為 `null`（`normalizeDeletedAt()`，見 Task 5，與 Issue 7 `pb_hooks` 的 `deleted_at > 0` 修正是同一個特性的兩種應對方式）。
- `pdf_page_index`/`progression`（number，可空，兩者互斥）：PDF 格式的書籤缺少 `progression` 時會下載回來 `0.0`，反之亦然——`0` 是合法的真實頁碼/進度值，無法單純用「是不是 0」判斷是否真的有設定。本 Task 的 `buildLocalFields` 因此改用**書籍格式**（`BookFileFormat`，由呼叫端於實際解析時查得，見 Task 8）判斷該取用哪一欄，另一欄一律視為不適用、寫回 `null`，而非依賴欄位值本身判斷。
- `epub_locator_json`/`pdf_rect_json`（text，可空）：未設定會下載回來 `""`（空字串），必須正規化為 `null`——空字串本身不是合法的 JSON 內容，視同「未設定」不會誤傷真實資料。

- [x] **Step 1：撰寫失敗測試**

Create `app/test/sync/sync_table_specs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('bookmarksSyncSpec', () {
    test('buildPushFields 從本機列取出對應的推送欄位', () {
      final result = bookmarksSyncSpec.buildPushFields({
        'id': 'bm1',
        'book_id': 'b1',
        'name': '第一章',
        'epub_locator_json': '{"href":"/c1.xhtml"}',
        'progression': 0.1,
        'pdf_page_index': null,
        'updated_at': 1000,
        'deleted_at': null,
      });

      expect(result, {
        'name': '第一章',
        'epub_locator_json': '{"href":"/c1.xhtml"}',
        'progression': 0.1,
        'pdf_page_index': null,
      });
    });

    test('extractRawFields 從 RecordModel 取出原始欄位（未正規化）', () {
      final remote = RecordModel({
        'name': '第一章',
        'epub_locator_json': '',
        'progression': 0,
        'pdf_page_index': 5,
      });

      final result = bookmarksSyncSpec.extractRawFields(remote);

      expect(result['name'], '第一章');
      expect(result['epub_locator_json'], '');
      expect(result['progression'], 0);
      expect(result['pdf_page_index'], 5);
    });

    test('buildLocalFields 對 EPUB 格式：採用 progression，pdf_page_index 一律 null', () {
      final result = bookmarksSyncSpec.buildLocalFields({
        'name': '第一章',
        'epub_locator_json': '',
        'progression': 0,
        'pdf_page_index': 5,
      }, BookFileFormat.epub);

      expect(result['name'], '第一章');
      expect(result['epub_locator_json'], isNull, reason: '空字串正規化為 null');
      expect(result['progression'], 0.0, reason: '真正的 0.0 進度值，不因為是 0 就被丟棄');
      expect(result['pdf_page_index'], isNull, reason: 'PDF 專屬欄位，EPUB 一律 null');
    });

    test('buildLocalFields 對 PDF 格式：採用 pdf_page_index，progression 一律 null', () {
      final result = bookmarksSyncSpec.buildLocalFields({
        'name': '封面',
        'epub_locator_json': null,
        'progression': 0,
        'pdf_page_index': 0,
      }, BookFileFormat.pdf);

      expect(result['pdf_page_index'], 0, reason: '真正的第 0 頁，不因為是 0 就被丟棄');
      expect(result['progression'], isNull, reason: 'EPUB 專屬欄位，PDF 一律 null');
    });
  });

  group('notesSyncSpec', () {
    test('buildPushFields 把本機 highlight_id 對應到 highlight_client_id', () {
      final result = notesSyncSpec.buildPushFields({
        'id': 'n1',
        'book_id': 'b1',
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_id': 'h1',
        'pdf_page_index': null,
        'pdf_rect_json': null,
        'updated_at': 1000,
        'deleted_at': null,
      });

      expect(result['highlight_client_id'], 'h1');
    });

    test('buildLocalFields 把遠端 highlight_client_id 對應回本機 highlight_id', () {
      final result = notesSyncSpec.buildLocalFields({
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_client_id': 'h1',
        'pdf_page_index': null,
        'pdf_rect_json': null,
      }, BookFileFormat.epub);

      expect(result['highlight_id'], 'h1');
    });

    test('buildLocalFields 的 highlight_id 為空字串時正規化為 null（不依賴書籍格式）', () {
      final result = notesSyncSpec.buildLocalFields({
        'text': '備註內容',
        'epub_locator_json': null,
        'progression': 0.2,
        'highlight_client_id': '',
        'pdf_page_index': null,
        'pdf_rect_json': null,
      }, BookFileFormat.epub);

      expect(result['highlight_id'], isNull);
    });
  });

  group('highlightsSyncSpec', () {
    test('buildLocalFields 對 PDF 格式：pdf_rect_json 空字串正規化為 null', () {
      final result = highlightsSyncSpec.buildLocalFields({
        'style': 'underline',
        'epub_locator_json': null,
        'progression': 0,
        'pdf_page_index': 3,
        'pdf_rect_json': '',
      }, BookFileFormat.pdf);

      expect(result['style'], 'underline');
      expect(result['pdf_rect_json'], isNull);
      expect(result['pdf_page_index'], 3);
    });
  });
}
```

- [x] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_table_specs_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_table_specs.dart`。

- [x] **Step 3：實作 `sync_models.dart`**

Create `app/lib/sync/sync_models.dart`：

```dart
/// 三種可同步的本機標註 collection（epic-8-sync Issue 4，spec.md「本機
/// Schema 變更」／「PocketBase Collection Schema」）。閱讀位置
/// （`sync_reading_positions`）不在此列——由 Issue 5 另外處理，不共用
/// 本檔案的推送/合併純函式（見 plan-issue-4.md Global Constraints）。
enum SyncCollection {
  bookmarks,
  highlights,
  notes;

  String get localTable => switch (this) {
        SyncCollection.bookmarks => 'bookmarks',
        SyncCollection.highlights => 'highlights',
        SyncCollection.notes => 'notes',
      };

  String get remoteCollection => switch (this) {
        SyncCollection.bookmarks => 'sync_bookmarks',
        SyncCollection.highlights => 'sync_highlights',
        SyncCollection.notes => 'sync_notes',
      };
}

/// 一筆待送出的推送操作（純資料，見 sync_push_planner.dart）。
/// [remoteId] 為 `null` 代表本機從未推送過此紀錄（走 PocketBase create），
/// 非 `null` 代表已知對應的 PocketBase 記錄 id（走 update）。
class PushOperation {
  final SyncCollection collection;
  final String? remoteId;
  final Map<String, Object?> body;

  const PushOperation({
    required this.collection,
    required this.remoteId,
    required this.body,
  });
}

/// 一筆下載回來、待合併判定的遠端紀錄（純資料，見 sync_merge.dart）。
/// [deletedAt] 已正規化（PocketBase 的 0 視為未刪除、已轉為 null，見
/// sync_merge.dart `normalizeDeletedAt`）；[rawFields] 為**尚未**依書籍
/// 格式正規化的原始欄位（見 sync_table_specs.dart「與 spec.md／Issue 7
/// 的落差說明」），實際正規化延後到書籍格式已知的合併/佇列解析當下才
/// 執行（見 SyncEngine）。
class RemoteRecordMergeInput {
  final String remoteId;
  final String clientId;
  final String? bookFingerprint;
  final int? deletedAt;
  final Map<String, Object?> rawFields;

  const RemoteRecordMergeInput({
    required this.remoteId,
    required this.clientId,
    required this.bookFingerprint,
    required this.deletedAt,
    required this.rawFields,
  });
}

/// 本機書籍查找結果（依 content_fingerprint 查得），供合併判定需要知道
/// 書籍格式才能正確解析 [RemoteRecordMergeInput.rawFields]（見上方）。
class BookLookup {
  final String id;
  final BookFileFormat format;

  const BookLookup({required this.id, required this.format});
}

/// 合併判定結果（純資料）：[resolved] 為 false 代表 book_fingerprint 查無
/// 對應本機書籍，應暫緩合併（寫入 sync_pending_records）；true 代表
/// [localRow] 是可直接寫入本機資料表的完整一列（含 id/book_id/deleted_at/
/// updated_at）。
class MergeDecision {
  final bool resolved;
  final Map<String, Object?>? localRow;

  const MergeDecision({required this.resolved, this.localRow});
}
```

修正 import：檔案開頭需要 `BookFileFormat`，加入：

```dart
import 'package:elinkbook/library/models/library_enums.dart';
```

（放在檔案最上方，`enum SyncCollection` 定義之前。）

- [x] **Step 4：實作 `sync_table_specs.dart`**

Create `app/lib/sync/sync_table_specs.dart`：

```dart
import 'package:pocketbase/pocketbase.dart';

import '../library/models/library_enums.dart';
import 'sync_models.dart';

typedef PushFieldsBuilder = Map<String, Object?> Function(
    Map<String, Object?> localRow);
typedef RawFieldsExtractor = Map<String, Object?> Function(
    RecordModel remote);
typedef LocalFieldsBuilder = Map<String, Object?> Function(
    Map<String, Object?> rawFields, BookFileFormat format);

/// 單一 collection 的推送/下載欄位轉換設定（epic-8-sync Issue 4）。三張
/// 本機標註表欄位結構高度相似但不完全相同（見 spec.md「PocketBase
/// Collection Schema」），用這個設定物件取代三份幾乎重複的程式碼，避免
/// 過度抽象成通用反射框架。
class SyncTableSpec {
  final SyncCollection collection;
  final PushFieldsBuilder buildPushFields;
  final RawFieldsExtractor extractRawFields;
  final LocalFieldsBuilder buildLocalFields;

  const SyncTableSpec({
    required this.collection,
    required this.buildPushFields,
    required this.extractRawFields,
    required this.buildLocalFields,
  });
}

/// 空字串正規化為 null（PocketBase text 欄位未設值的零值是 `""`，見
/// plan-issue-4.md「與 spec.md／Issue 7 的落差說明」）。
String? _normalizeText(Object? raw) {
  if (raw == null || raw == '') return null;
  return raw as String;
}

final SyncTableSpec bookmarksSyncSpec = SyncTableSpec(
  collection: SyncCollection.bookmarks,
  buildPushFields: (row) => {
    'name': row['name'],
    'epub_locator_json': row['epub_locator_json'],
    'progression': row['progression'],
    'pdf_page_index': row['pdf_page_index'],
  },
  extractRawFields: (remote) => {
    'name': remote.data['name'],
    'epub_locator_json': remote.data['epub_locator_json'],
    'progression': remote.data['progression'],
    'pdf_page_index': remote.data['pdf_page_index'],
  },
  buildLocalFields: (raw, format) => {
    'name': raw['name'] as String,
    'epub_locator_json':
        format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
    'progression': format == BookFileFormat.pdf
        ? null
        : (raw['progression'] as num?)?.toDouble(),
    'pdf_page_index': format == BookFileFormat.pdf
        ? (raw['pdf_page_index'] as num?)?.toInt()
        : null,
  },
);

final SyncTableSpec highlightsSyncSpec = SyncTableSpec(
  collection: SyncCollection.highlights,
  buildPushFields: (row) => {
    'style': row['style'],
    'epub_locator_json': row['epub_locator_json'],
    'progression': row['progression'],
    'pdf_page_index': row['pdf_page_index'],
    'pdf_rect_json': row['pdf_rect_json'],
  },
  extractRawFields: (remote) => {
    'style': remote.data['style'],
    'epub_locator_json': remote.data['epub_locator_json'],
    'progression': remote.data['progression'],
    'pdf_page_index': remote.data['pdf_page_index'],
    'pdf_rect_json': remote.data['pdf_rect_json'],
  },
  buildLocalFields: (raw, format) => {
    'style': raw['style'] as String,
    'epub_locator_json':
        format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
    'progression': format == BookFileFormat.pdf
        ? null
        : (raw['progression'] as num?)?.toDouble(),
    'pdf_page_index': format == BookFileFormat.pdf
        ? (raw['pdf_page_index'] as num?)?.toInt()
        : null,
    'pdf_rect_json':
        format == BookFileFormat.pdf ? _normalizeText(raw['pdf_rect_json']) : null,
  },
);

final SyncTableSpec notesSyncSpec = SyncTableSpec(
  collection: SyncCollection.notes,
  buildPushFields: (row) => {
    'text': row['text'],
    'epub_locator_json': row['epub_locator_json'],
    'progression': row['progression'],
    'highlight_client_id': row['highlight_id'],
    'pdf_page_index': row['pdf_page_index'],
    'pdf_rect_json': row['pdf_rect_json'],
  },
  extractRawFields: (remote) => {
    'text': remote.data['text'],
    'epub_locator_json': remote.data['epub_locator_json'],
    'progression': remote.data['progression'],
    'highlight_client_id': remote.data['highlight_client_id'],
    'pdf_page_index': remote.data['pdf_page_index'],
    'pdf_rect_json': remote.data['pdf_rect_json'],
  },
  buildLocalFields: (raw, format) => {
    'text': raw['text'] as String,
    'epub_locator_json':
        format == BookFileFormat.pdf ? null : _normalizeText(raw['epub_locator_json']),
    'progression': format == BookFileFormat.pdf
        ? null
        : (raw['progression'] as num?)?.toDouble(),
    // 劃線的本機 id 現在就是全域唯一的 UUID，同步/本機共用同一個值，不需
    // 要額外轉換查表（見 spec.md「跨裝置參照設計」）；與書籍格式無關，
    // 一律嘗試正規化空字串。
    'highlight_id': _normalizeText(raw['highlight_client_id']),
    'pdf_page_index': format == BookFileFormat.pdf
        ? (raw['pdf_page_index'] as num?)?.toInt()
        : null,
    'pdf_rect_json':
        format == BookFileFormat.pdf ? _normalizeText(raw['pdf_rect_json']) : null,
  },
);

final Map<SyncCollection, SyncTableSpec> syncTableSpecs = {
  SyncCollection.bookmarks: bookmarksSyncSpec,
  SyncCollection.highlights: highlightsSyncSpec,
  SyncCollection.notes: notesSyncSpec,
};
```

- [x] **Step 5：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_table_specs_test.dart
```

Expected：PASS（8 個測試全數通過）。

- [x] **Step 6：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_models.dart lib/sync/sync_table_specs.dart test/sync/sync_table_specs_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 3 — 純資料模型與資料表對照設定"
```

---

### Task 4：推送批次組裝純函式

**Files:**
- Create：`app/lib/sync/sync_push_planner.dart`
- Test：`app/test/sync/sync_push_planner_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `SyncTableSpec`/`PushOperation`。
- Produces：`bool isDirtyRow(int updatedAt, int? lastPushCompletedAt)`、`List<PushOperation> buildPushOperations({required SyncTableSpec spec, required List<Map<String, Object?>> joinedRows, required Map<String, String> remoteIdsByClientId, required String userId})`、`List<List<PushOperation>> planPushBatches(List<PushOperation> operations, {int batchLimit = 100})`。供 Task 7（`SyncEngine` 推送階段）使用。

- [x] **Step 1：撰寫失敗測試**

Create `app/test/sync/sync_push_planner_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_models.dart';
import 'package:elinkbook/sync/sync_push_planner.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('isDirtyRow', () {
    test('updatedAt 晚於 lastPushCompletedAt 時為 dirty', () {
      expect(isDirtyRow(200, 100), isTrue);
    });

    test('updatedAt 早於或等於 lastPushCompletedAt 時非 dirty', () {
      expect(isDirtyRow(100, 100), isFalse);
      expect(isDirtyRow(50, 100), isFalse);
    });

    test('lastPushCompletedAt 為 null（從未推送過）時，任何 updatedAt 皆為 dirty', () {
      expect(isDirtyRow(1, null), isTrue);
    });
  });

  group('buildPushOperations', () {
    test('每筆操作皆帶 user／client_id／book_fingerprint／deleted_at 與 collection 專屬欄位',
        () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '第一章',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': 'fp-1',
          },
        ],
        remoteIdsByClientId: {},
        userId: 'user-1',
      );

      expect(ops, hasLength(1));
      expect(ops.single.collection, SyncCollection.bookmarks);
      expect(ops.single.remoteId, isNull, reason: '從未推送過，走 create');
      expect(ops.single.body['user'], 'user-1');
      expect(ops.single.body['client_id'], 'bm1');
      expect(ops.single.body['book_fingerprint'], 'fp-1');
      expect(ops.single.body['deleted_at'], isNull);
      expect(ops.single.body['name'], '第一章');
    });

    test('remoteIdsByClientId 已有對照時，remoteId 帶入該值（走 update）', () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '改名後',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': 'fp-1',
          },
        ],
        remoteIdsByClientId: {'bm1': 'pb-record-abc'},
        userId: 'user-1',
      );

      expect(ops.single.remoteId, 'pb-record-abc');
    });

    test('book_fingerprint 為 null 的列被排除，不產生推送操作', () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '第一章',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': null,
          },
        ],
        remoteIdsByClientId: {},
        userId: 'user-1',
      );

      expect(ops, isEmpty);
    });
  });

  group('planPushBatches', () {
    test('筆數未超過上限時只產生一個批次', () {
      final ops = List.generate(
        50,
        (i) => PushOperation(collection: SyncCollection.bookmarks, remoteId: null, body: {'i': i}),
      );

      final batches = planPushBatches(ops, batchLimit: 100);

      expect(batches, hasLength(1));
      expect(batches.single, hasLength(50));
    });

    test('筆數超過上限（101 筆，上限 100）時正確拆成兩個批次', () {
      final ops = List.generate(
        101,
        (i) => PushOperation(collection: SyncCollection.bookmarks, remoteId: null, body: {'i': i}),
      );

      final batches = planPushBatches(ops, batchLimit: 100);

      expect(batches, hasLength(2));
      expect(batches[0], hasLength(100));
      expect(batches[1], hasLength(1));
    });

    test('操作清單為空時回傳空的批次清單', () {
      expect(planPushBatches(const []), isEmpty);
    });
  });
}
```

- [x] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_push_planner_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_push_planner.dart`。

- [x] **Step 3：實作 `sync_push_planner.dart`**

Create `app/lib/sync/sync_push_planner.dart`：

```dart
import 'sync_models.dart';
import 'sync_table_specs.dart';

/// 判斷一筆本機紀錄自上次成功推送後是否有新異動（純本機時鐘比較，見
/// spec.md「同步引擎」：只跟自己過去的 lastPushCompletedAt 比較，不跨
/// 裝置比較）。[lastPushCompletedAt] 為 `null` 代表從未推送過，任何
/// [updatedAt] 皆視為 dirty。
bool isDirtyRow(int updatedAt, int? lastPushCompletedAt) {
  return updatedAt > (lastPushCompletedAt ?? 0);
}

/// 組裝單一 collection 的推送操作清單（純函式，spec.md「Testing
/// Decisions」）。[joinedRows] 為已與 `books` 表 JOIN 取得
/// `book_fingerprint` 的本機異動列（見 SyncEngine 呼叫端 `_queryDirtyRows`）；
/// [remoteIdsByClientId] 為本機 `sync_remote_ids` 快取（有對照代表已知
/// PocketBase 記錄 id，走 update；查無對照代表尚未推送過，走 create）。
/// `book_fingerprint` 仍為 `null`（該書尚未有指紋，補算失敗或跳過）的列
/// 會被排除，等待下次 checkpoint 重試。
List<PushOperation> buildPushOperations({
  required SyncTableSpec spec,
  required List<Map<String, Object?>> joinedRows,
  required Map<String, String> remoteIdsByClientId,
  required String userId,
}) {
  final operations = <PushOperation>[];
  for (final row in joinedRows) {
    final bookFingerprint = row['book_fingerprint'] as String?;
    if (bookFingerprint == null) continue;
    final clientId = row['id'] as String;
    final body = <String, Object?>{
      'user': userId,
      'client_id': clientId,
      'book_fingerprint': bookFingerprint,
      'deleted_at': row['deleted_at'],
      ...spec.buildPushFields(row),
    };
    operations.add(PushOperation(
      collection: spec.collection,
      remoteId: remoteIdsByClientId[clientId],
      body: body,
    ));
  }
  return operations;
}

/// 依固定上限（預設 100 筆/批，spec.md「同步引擎」）把推送操作拆成多個
/// 依序送出的批次。
List<List<PushOperation>> planPushBatches(
  List<PushOperation> operations, {
  int batchLimit = 100,
}) {
  final batches = <List<PushOperation>>[];
  for (var i = 0; i < operations.length; i += batchLimit) {
    final end = (i + batchLimit < operations.length) ? i + batchLimit : operations.length;
    batches.add(operations.sublist(i, end));
  }
  return batches;
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_push_planner_test.dart
```

Expected：PASS（9 個測試全數通過）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_push_planner.dart test/sync/sync_push_planner_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 4 — 推送批次組裝純函式"
```

---

### Task 5：下載合併判定 + 墓碑清理純函式

**Files:**
- Create：`app/lib/sync/sync_merge.dart`
- Test：`app/test/sync/sync_merge_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `RemoteRecordMergeInput`/`BookLookup`/`MergeDecision`/`SyncTableSpec`。
- Produces：`int? normalizeDeletedAt(Object? raw)`、`MergeDecision resolveMergeDecision({required SyncTableSpec spec, required RemoteRecordMergeInput input, required Map<String, BookLookup> booksByFingerprint, required int notDirtyUpdatedAt})`、`List<String> idsPastTombstoneRetention({required List<Map<String, Object?>> rows, required DateTime now, Duration retention = const Duration(days: 30)})`、`String? maxUpdatedCursor(List<String> updatedValues, String? current)`。供 Task 8（`SyncEngine` 下載階段）使用。

- [x] **Step 1：撰寫失敗測試**

Create `app/test/sync/sync_merge_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_merge.dart';
import 'package:elinkbook/sync/sync_models.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('normalizeDeletedAt', () {
    test('null 視為未刪除', () {
      expect(normalizeDeletedAt(null), isNull);
    });

    test('0（PocketBase number 欄位未設值的零值）視為未刪除', () {
      expect(normalizeDeletedAt(0), isNull);
    });

    test('非 0 的真實時間戳記正確保留', () {
      expect(normalizeDeletedAt(1735689600000), 1735689600000);
    });
  });

  group('resolveMergeDecision', () {
    test('book_fingerprint 查得到對應本機書籍時，回傳可直接寫入的完整本機列', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-1',
        clientId: 'bm1',
        bookFingerprint: 'fp-1',
        deletedAt: null,
        rawFields: {
          'name': '第一章',
          'epub_locator_json': '',
          'progression': 0.1,
          'pdf_page_index': 0,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {
          'fp-1': const BookLookup(id: 'b1', format: BookFileFormat.epub),
        },
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isTrue);
      expect(decision.localRow!['id'], 'bm1');
      expect(decision.localRow!['book_id'], 'b1');
      expect(decision.localRow!['deleted_at'], isNull);
      expect(decision.localRow!['updated_at'], 5000);
      expect(decision.localRow!['name'], '第一章');
      expect(decision.localRow!['progression'], 0.1);
      expect(decision.localRow!['pdf_page_index'], isNull,
          reason: 'EPUB 格式，pdf_page_index 一律 null');
    });

    test('book_fingerprint 查無對應本機書籍時，回傳暫緩合併決定', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-2',
        clientId: 'bm2',
        bookFingerprint: 'fp-unknown',
        deletedAt: null,
        rawFields: {
          'name': '未匯入書籍的書籤',
          'epub_locator_json': null,
          'progression': 0.2,
          'pdf_page_index': null,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {},
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isFalse);
      expect(decision.localRow, isNull);
    });

    test('bookFingerprint 為 null 時，同樣回傳暫緩合併決定（防禦性情境）', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-3',
        clientId: 'bm3',
        bookFingerprint: null,
        deletedAt: null,
        rawFields: {
          'name': 'X',
          'epub_locator_json': null,
          'progression': 0.1,
          'pdf_page_index': null,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {'fp-1': const BookLookup(id: 'b1', format: BookFileFormat.epub)},
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isFalse);
    });
  });

  group('idsPastTombstoneRetention', () {
    test('deleted_at 早於 30 天前的紀錄被選中', () {
      final now = DateTime.fromMillisecondsSinceEpoch(40 * 24 * 60 * 60 * 1000);
      final rows = [
        {'id': 'a', 'deleted_at': 1 * 24 * 60 * 60 * 1000}, // 遠早於 30 天前
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), ['a']);
    });

    test('deleted_at 晚於 30 天前（保留期限內）的紀錄不被選中', () {
      final now = DateTime.fromMillisecondsSinceEpoch(40 * 24 * 60 * 60 * 1000);
      final rows = [
        {'id': 'a', 'deleted_at': 39 * 24 * 60 * 60 * 1000}, // 僅 1 天前
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), isEmpty);
    });

    test('deleted_at 為 null（未刪除）的紀錄不受影響', () {
      final now = DateTime.now();
      final rows = [
        {'id': 'a', 'deleted_at': null},
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), isEmpty);
    });
  });

  group('maxUpdatedCursor', () {
    test('回傳字串比較後最大的值', () {
      final result = maxUpdatedCursor(
        ['2026-08-01 00:00:00.000Z', '2026-08-03 00:00:00.000Z', '2026-08-02 00:00:00.000Z'],
        null,
      );

      expect(result, '2026-08-03 00:00:00.000Z');
    });

    test('清單為空時維持目前的游標值', () {
      expect(maxUpdatedCursor([], '2026-08-01 00:00:00.000Z'), '2026-08-01 00:00:00.000Z');
    });

    test('新值皆小於等於目前游標時，維持目前游標（不倒退）', () {
      final result = maxUpdatedCursor(
        ['2026-08-01 00:00:00.000Z'],
        '2026-08-02 00:00:00.000Z',
      );

      expect(result, '2026-08-02 00:00:00.000Z');
    });
  });
}
```

- [x] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_merge_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_merge.dart`。

- [x] **Step 3：實作 `sync_merge.dart`**

Create `app/lib/sync/sync_merge.dart`：

```dart
import 'sync_models.dart';
import 'sync_table_specs.dart';

/// PocketBase 的 number 欄位在未設值時預設為 0，而非真正的 SQL NULL
/// （Issue 7 的 pb_hooks 墓碑清理腳本審查時已發現並修正的同一個特性，
/// 見 plan-issue-7.md「實作結果審查修正紀錄」）。下載端讀取 deleted_at
/// 時必須把 0 視同未刪除（null），不能直接轉型。
int? normalizeDeletedAt(Object? raw) {
  if (raw == null) return null;
  final value = (raw as num).toInt();
  return value == 0 ? null : value;
}

/// 下載合併判定純函式（spec.md「跨裝置參照設計」／「Testing
/// Decisions」）：[booksByFingerprint] 為目前本機所有
/// `books.content_fingerprint` -> (id, format) 的對照表（呼叫端一次查詢、
/// 供本次 checkpoint 下載的所有紀錄共用）；[notDirtyUpdatedAt] 是合併寫入
/// 本機時要填入的 `updated_at` 值——刻意不用 `DateTime.now()`，而是使用
/// 本次 checkpoint 剛寫入的 `lastPushCompletedAt` 值，確保剛合併進來的
/// 遠端紀錄不會在下一次 checkpoint 被誤判為本機 dirty、造成不必要的
/// 重複推送。
MergeDecision resolveMergeDecision({
  required SyncTableSpec spec,
  required RemoteRecordMergeInput input,
  required Map<String, BookLookup> booksByFingerprint,
  required int notDirtyUpdatedAt,
}) {
  final book =
      input.bookFingerprint == null ? null : booksByFingerprint[input.bookFingerprint];
  if (book == null) {
    return const MergeDecision(resolved: false);
  }
  return MergeDecision(resolved: true, localRow: {
    'id': input.clientId,
    'book_id': book.id,
    'deleted_at': input.deletedAt,
    'updated_at': notDirtyUpdatedAt,
    ...spec.buildLocalFields(input.rawFields, book.format),
  });
}

/// 墓碑清理篩選純函式（spec.md「墓碑清理」）：回傳應真正 DELETE 的 id
/// 清單——`deleted_at` 非空且早於 [now] 減去 [retention]（預設 30 天）。
List<String> idsPastTombstoneRetention({
  required List<Map<String, Object?>> rows,
  required DateTime now,
  Duration retention = const Duration(days: 30),
}) {
  final cutoff = now.subtract(retention).millisecondsSinceEpoch;
  return rows
      .where((row) => row['deleted_at'] != null && (row['deleted_at'] as int) < cutoff)
      .map((row) => row['id'] as String)
      .toList();
}

/// 找出多筆遠端紀錄的 `updated` 系統欄位字串中最大的一個（PocketBase 的
/// `updated` 為固定格式、可直接用字串比較排序的時間戳記，見 spec.md
/// 「PocketBase Collection Schema」），供更新 `sync_metadata` 的下載游標
/// 使用；[current] 為目前游標值，回傳結果不會比它舊。
String? maxUpdatedCursor(List<String> updatedValues, String? current) {
  var result = current;
  for (final value in updatedValues) {
    if (result == null || value.compareTo(result) > 0) {
      result = value;
    }
  }
  return result;
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_merge_test.dart
```

Expected：PASS（12 個測試全數通過）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_merge.dart test/sync/sync_merge_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 5 — 下載合併判定與墓碑清理純函式"
```

---

### Task 6：`SyncMetadataRepository`——`sync_metadata`／`sync_remote_ids`／`sync_pending_records` 存取層

**Files:**
- Create：`app/lib/sync/sync_metadata_repository.dart`
- Test：`app/test/sync/sync_metadata_repository_test.dart`

**Interfaces:**
- Consumes：Task 1 的三張表（`sync_metadata`／`sync_remote_ids`／`sync_pending_records`）、Task 3 的 `SyncCollection`。
- Produces：`SyncMetadataRepository`（建構子 `SyncMetadataRepository(Database db)`），方法：`loadLastPushCompletedAt()`／`saveLastPushCompletedAt(int)`／`loadPulledCursor(SyncCollection)`／`savePulledCursor(SyncCollection, String)`／`loadRemoteIds(SyncCollection)`／`saveRemoteId(SyncCollection, String, String)`／`listPendingRecords()`／`savePendingRecord(...)`／`deletePendingRecord(SyncCollection, String)`。供 Task 7/8（`SyncEngine`）使用。

- [x] **Step 1：撰寫失敗測試**

Create `app/test/sync/sync_metadata_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';
import 'package:elinkbook/sync/sync_models.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late SyncMetadataRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = SyncMetadataRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('loadLastPushCompletedAt 初始為 null，saveLastPushCompletedAt 後可讀回', () async {
    expect(await repository.loadLastPushCompletedAt(), isNull);

    await repository.saveLastPushCompletedAt(1000);

    expect(await repository.loadLastPushCompletedAt(), 1000);
  });

  test('loadPulledCursor 初始為 null，savePulledCursor 後可讀回，且各 collection 互不干擾',
      () async {
    expect(await repository.loadPulledCursor(SyncCollection.bookmarks), isNull);

    await repository.savePulledCursor(SyncCollection.bookmarks, '2026-08-01 00:00:00.000Z');

    expect(
      await repository.loadPulledCursor(SyncCollection.bookmarks),
      '2026-08-01 00:00:00.000Z',
    );
    expect(await repository.loadPulledCursor(SyncCollection.highlights), isNull);
  });

  test('loadRemoteIds 初始為空，saveRemoteId 後可讀回，且依 collection 區分', () async {
    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), isEmpty);

    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-abc');
    await repository.saveRemoteId(SyncCollection.highlights, 'bm1', 'pb-xyz');

    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), {'bm1': 'pb-abc'});
    expect(await repository.loadRemoteIds(SyncCollection.highlights), {'bm1': 'pb-xyz'});
  });

  test('saveRemoteId 對同一個 (collection, client_id) 重複寫入時覆蓋舊值', () async {
    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-old');
    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-new');

    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), {'bm1': 'pb-new'});
  });

  test('savePendingRecord 寫入後 listPendingRecords 可讀回完整內容', () async {
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm1',
      bookFingerprint: 'fp-1',
      remoteId: 'pb-1',
      deletedAt: null,
      fields: {'name': '第一章'},
    );

    final pending = await repository.listPendingRecords();

    expect(pending, hasLength(1));
    expect(pending.single.collection, SyncCollection.bookmarks);
    expect(pending.single.clientId, 'bm1');
    expect(pending.single.bookFingerprint, 'fp-1');
    expect(pending.single.remoteId, 'pb-1');
    expect(pending.single.deletedAt, isNull);
    expect(pending.single.fields, {'name': '第一章'});
  });

  test('deletePendingRecord 移除指定紀錄，其餘不受影響', () async {
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm1',
      bookFingerprint: 'fp-1',
      remoteId: 'pb-1',
      deletedAt: null,
      fields: const {},
    );
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm2',
      bookFingerprint: 'fp-2',
      remoteId: 'pb-2',
      deletedAt: null,
      fields: const {},
    );

    await repository.deletePendingRecord(SyncCollection.bookmarks, 'bm1');

    final pending = await repository.listPendingRecords();
    expect(pending, hasLength(1));
    expect(pending.single.clientId, 'bm2');
  });
}
```

- [x] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_metadata_repository_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_metadata_repository.dart`。

- [x] **Step 3：實作 `sync_metadata_repository.dart`**

Create `app/lib/sync/sync_metadata_repository.dart`：

```dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sync_models.dart';

/// 一筆待處理的同步紀錄（epic-8-sync Issue 4，spec.md「跨裝置參照
/// 設計」）：`book_fingerprint` 查無對應本機書籍時暫緩合併，落地於
/// `sync_pending_records`，等待使用者之後匯入同一本書。
class PendingSyncRecord {
  final SyncCollection collection;
  final String clientId;
  final String bookFingerprint;
  final String remoteId;
  final int? deletedAt;
  final Map<String, Object?> fields;

  const PendingSyncRecord({
    required this.collection,
    required this.clientId,
    required this.bookFingerprint,
    required this.remoteId,
    required this.deletedAt,
    required this.fields,
  });
}

/// 同步中繼資料存取層（epic-8-sync Issue 4，spec.md「本機 Schema
/// 變更」／「跨裝置參照設計」）：包裝 Issue 1 已建立的 `sync_metadata`
/// 表，以及本 Issue 新增的 `sync_remote_ids`／`sync_pending_records`
/// 兩張表（見 plan-issue-4.md Task 1）。`sync_metadata` 恆為單列
/// （`id = 1`，Issue 1 已保證存在）。
class SyncMetadataRepository {
  final Database _db;

  const SyncMetadataRepository(this._db);

  Future<int?> loadLastPushCompletedAt() async {
    final rows = await _db.query('sync_metadata', where: 'id = 1');
    return rows.single['last_push_completed_at'] as int?;
  }

  Future<void> saveLastPushCompletedAt(int value) {
    return _db.update(
      'sync_metadata',
      {'last_push_completed_at': value},
      where: 'id = 1',
    );
  }

  static const _cursorColumns = {
    SyncCollection.bookmarks: 'last_pulled_server_updated_at_bookmarks',
    SyncCollection.highlights: 'last_pulled_server_updated_at_highlights',
    SyncCollection.notes: 'last_pulled_server_updated_at_notes',
  };

  Future<String?> loadPulledCursor(SyncCollection collection) async {
    final rows = await _db.query('sync_metadata', where: 'id = 1');
    return rows.single[_cursorColumns[collection]] as String?;
  }

  Future<void> savePulledCursor(SyncCollection collection, String value) {
    return _db.update(
      'sync_metadata',
      {_cursorColumns[collection]!: value},
      where: 'id = 1',
    );
  }

  Future<Map<String, String>> loadRemoteIds(SyncCollection collection) async {
    final rows = await _db.query(
      'sync_remote_ids',
      where: 'collection = ?',
      whereArgs: [collection.name],
    );
    return {
      for (final row in rows) row['client_id'] as String: row['remote_id'] as String,
    };
  }

  Future<void> saveRemoteId(
    SyncCollection collection,
    String clientId,
    String remoteId,
  ) {
    return _db.insert(
      'sync_remote_ids',
      {'collection': collection.name, 'client_id': clientId, 'remote_id': remoteId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingSyncRecord>> listPendingRecords() async {
    final rows = await _db.query('sync_pending_records');
    return rows.map((row) {
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      return PendingSyncRecord(
        collection: SyncCollection.values.byName(row['collection'] as String),
        clientId: row['client_id'] as String,
        bookFingerprint: row['book_fingerprint'] as String,
        remoteId: payload['remoteId'] as String,
        deletedAt: payload['deletedAt'] as int?,
        fields: (payload['fields'] as Map).cast<String, Object?>(),
      );
    }).toList();
  }

  Future<void> savePendingRecord({
    required SyncCollection collection,
    required String clientId,
    required String bookFingerprint,
    required String remoteId,
    required int? deletedAt,
    required Map<String, Object?> fields,
  }) {
    return _db.insert(
      'sync_pending_records',
      {
        'collection': collection.name,
        'client_id': clientId,
        'book_fingerprint': bookFingerprint,
        'payload_json': jsonEncode({
          'remoteId': remoteId,
          'deletedAt': deletedAt,
          'fields': fields,
        }),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePendingRecord(SyncCollection collection, String clientId) {
    return _db.delete(
      'sync_pending_records',
      where: 'collection = ? AND client_id = ?',
      whereArgs: [collection.name, clientId],
    );
  }
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_metadata_repository_test.dart
```

Expected：PASS（7 個測試全數通過）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_metadata_repository.dart test/sync/sync_metadata_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 6 — SyncMetadataRepository 存取層"
```

---

### Task 7：`SyncEngine`——推送階段（含指紋補算回填）

**Files:**
- Create：`app/lib/sync/sync_engine.dart`
- Test：`app/test/sync/sync_engine_test.dart`

**Interfaces:**
- Consumes：Task 3-6 的所有純函式/資料層、Issue 2 的 `SyncAccountRepository`、`PocketBaseClientFactory`（`sync_client.dart`）、Issue 3 的 `computeBookContentFingerprint()`。
- Produces：`SyncEngine`（建構子 `SyncEngine({required Database db, required SyncAccountRepository accountRepository, required SyncMetadataRepository metadataRepository, PocketBaseClientFactory? clientFactory})`），本 Task 先實作 `runCheckpoint()` 的推送半段（未登入即早退、指紋補算回填、查詢 dirty 列、組裝並分批送出、推送失敗即整批放棄）。**`lastPushCompletedAt`／各 collection 下載游標的實際持久化，刻意延後到 Task 8 下載階段全部成功後才一併寫入**（2026-08-04 `/superpowers:requesting-code-review` 發現並修正的 Critical 問題，見文末「審查修正紀錄」：spec.md「同步引擎」步驟 7 明訂「不局部套用已完成的步驟」，若推送一成功就立刻寫入 `lastPushCompletedAt`，之後下載階段失敗時會違反這個原子性要求）。本 Task 只計算 `notDirtyUpdatedAt`（供 Task 8 的合併/游標寫入使用），不呼叫任何 `SyncMetadataRepository` 的寫入方法。下載/合併/墓碑清理見 Task 8（同一個方法接續擴充）。

- [x] **Step 1：撰寫失敗測試（僅涵蓋推送半段行為）**

Create `app/test/sync/sync_engine_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_engine.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';

Book _testBook(String id, {String? contentFingerprint}) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    contentFingerprint: contentFingerprint,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late FlutterSecureStoragePlatform originalPlatform;
  late SqliteLibraryRepository libraryRepository;
  late BookmarksRepository bookmarksRepository;
  late SyncAccountRepository accountRepository;
  late SyncMetadataRepository metadataRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    bookmarksRepository = BookmarksRepository(libraryRepository.database);
    metadataRepository = SyncMetadataRepository(libraryRepository.database);

    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    accountRepository = SyncAccountRepository();
    await accountRepository.saveBaseUrl('http://127.0.0.1:8090');
    await accountRepository.saveCredentials(
      authToken: 'test-token',
      userId: 'user-1',
      email: 'reader@example.com',
    );
  });

  tearDown(() async {
    await libraryRepository.close();
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('未登入時 runCheckpoint 直接早退，不發出任何網路請求', () async {
    await accountRepository.clearCredentials();
    var requestSent = false;
    final mockClient = MockClient((request) async {
      requestSent = true;
      return http.Response('{}', 200);
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    expect(requestSent, isFalse);
  });

  test('有指紋的書籍新增一筆書籤：推送 create（remoteId 未知），成功後寫入 sync_remote_ids',
      () async {
    await libraryRepository.insertBook(_testBook('b1', contentFingerprint: 'fp-1'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm1', bookId: 'b1', name: '第一章', progression: 0.1),
    );

    Map<String, dynamic>? capturedRequest;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        expect(request.headers['Authorization'], 'test-token');
        capturedRequest = jsonDecode(request.body) as Map<String, dynamic>;
        final subRequests = capturedRequest!['requests'] as List;
        expect(subRequests, hasLength(1));
        expect(subRequests.single['method'], 'POST');
        return http.Response(
          jsonEncode([
            {
              'status': 200,
              'body': {
                'id': 'pb-created-1',
                'client_id': 'bm1',
                'updated': '2026-08-03 00:00:00.000Z',
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Task 7 尚未實作下載，這個分支現階段不會被觸發；一旦 Task 8 幫
      // runCheckpoint() 接上下載呼叫，這裡讓任何 collection 的 GET 查詢
      // 都回傳空結果，避免本測試的 mock 因為多了下載請求而炸掉（見
      // plan-issue-4.md「審查修正紀錄」）。
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final pushBody =
        (capturedRequest!['requests'] as List).single['body'] as Map<String, dynamic>;
    expect(pushBody['user'], 'user-1');
    expect(pushBody['client_id'], 'bm1');
    expect(pushBody['book_fingerprint'], 'fp-1');
    expect(pushBody['name'], '第一章');

    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm1': 'pb-created-1'},
    );
    // `lastPushCompletedAt` 本 Task 尚未持久化（刻意延後到 Task 8 下載
    // 階段全部成功後才一併寫入，見上方 Interfaces 說明／文末「審查修正
    // 紀錄」），故本測試不斷言它，改由 Task 8 的測試驗證完整成功路徑。
  });

  test('書籍尚無指紋（content_fingerprint 為 null）時，即時補算並回填後才推送', () async {
    // 使用本機檔案路徑（而非 content://），讓 computeBookContentFingerprint
    // 走本機 SHA-256 串流路徑，不需要 mock 原生 MethodChannel。
    final book = Book(
      id: 'b2',
      title: '測試書',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await libraryRepository.insertBook(book);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    await highlightsRepository.insert(
      const Highlight(id: 'h1', bookId: 'b2', style: HighlightStyle.underline, pdfPageIndex: 3),
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(
          jsonEncode([
            {'status': 200, 'body': {'id': 'pb-h1'}},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 見上一個測試同樣的說明：Task 8 接上下載呼叫後，任何 collection
      // 的 GET 查詢一律回傳空結果。
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final bookRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b2']);
    expect(bookRows.single['content_fingerprint'], isNotNull);
  });

  test('推送批次失敗（HTTP 錯誤）時，不更新 lastPushCompletedAt，也不寫入 sync_remote_ids', () async {
    await libraryRepository.insertBook(_testBook('b3', contentFingerprint: 'fp-3'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm3', bookId: 'b3', name: 'X', progression: 0.1),
    );

    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Something went wrong.'}),
        500,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    expect(await metadataRepository.loadLastPushCompletedAt(), isNull);
    expect(await metadataRepository.loadRemoteIds(SyncCollection.bookmarks), isEmpty);
  });
}
```

（本 Task 的測試檔在 Task 8 會繼續擴充下載/合併/墓碑清理案例，Task 8 Step 1 承接同一份檔案。）

- [x] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_engine.dart`。

- [x] **Step 3：實作 `sync_engine.dart`（推送半段）**

Create `app/lib/sync/sync_engine.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqflite/sqflite.dart';

import '../library/book_content_fingerprint.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import 'sync_account_repository.dart';
import 'sync_client.dart';
import 'sync_merge.dart';
import 'sync_metadata_repository.dart';
import 'sync_models.dart';
import 'sync_push_planner.dart';
import 'sync_table_specs.dart';

/// 雲端同步引擎核心（epic-8-sync Issue 4，spec.md「同步引擎」）：本 Issue
/// 只實作劃線/備註/書籤的推送/下載/合併與本機墓碑清理；閱讀位置的衝突
/// 預檢由 Issue 5 擴充同一個 [runCheckpoint]；三種觸發來源與併發鎖由
/// Issue 6 負責，本 Issue 的 [runCheckpoint] 僅需可被手動/測試呼叫。
///
/// **給 Issue 6 實作者的例外處理提醒**（審查意見 Minor #1，2026-08-04
/// `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
/// [runCheckpoint] 只捕捉網路層的 `ClientException`（PocketBase SDK
/// 統一封裝的 HTTP 錯誤），**不**捕捉本機 SQLite 操作可能拋出的
/// `DatabaseException`（例如磁碟空間不足）——這是刻意的，本 Issue 不吞
/// 掉未預期的本機例外。Issue 6 規劃的 `_isSyncing` 執行鎖，呼叫
/// [runCheckpoint] 時**必須**用 `try { await runCheckpoint(); } finally
/// { _isSyncing = false; }` 包住，否則任何一次未預期的本機例外都會讓鎖
/// 永久卡住（需要重開 App 才能恢復），而不能假設 [runCheckpoint] 永遠
/// 不會拋出例外。
class SyncEngine {
  final Database _db;
  final SyncAccountRepository _accountRepository;
  final SyncMetadataRepository _metadataRepository;
  final PocketBaseClientFactory _clientFactory;

  SyncEngine({
    required Database db,
    required SyncAccountRepository accountRepository,
    required SyncMetadataRepository metadataRepository,
    PocketBaseClientFactory? clientFactory,
  })  : _db = db,
        _accountRepository = accountRepository,
        _metadataRepository = metadataRepository,
        _clientFactory = clientFactory ?? PocketBase.new;

  Future<void> runCheckpoint() async {
    final baseUrl = await _accountRepository.loadBaseUrl();
    final authToken = await _accountRepository.loadAuthToken();
    final userId = await _accountRepository.loadUserId();
    if (authToken == null || userId == null || baseUrl.isEmpty) return;

    final pb = _clientFactory(baseUrl);
    final headers = {'Authorization': authToken};
    final lastPushCompletedAt = await _metadataRepository.loadLastPushCompletedAt();

    final joinedRowsByCollection = <SyncCollection, List<Map<String, Object?>>>{};
    for (final spec in syncTableSpecs.values) {
      joinedRowsByCollection[spec.collection] =
          await _queryDirtyRows(spec.collection, lastPushCompletedAt);
    }

    await _backfillMissingFingerprints(joinedRowsByCollection);

    final allOperations = <PushOperation>[];
    for (final spec in syncTableSpecs.values) {
      final remoteIds = await _metadataRepository.loadRemoteIds(spec.collection);
      allOperations.addAll(buildPushOperations(
        spec: spec,
        joinedRows: joinedRowsByCollection[spec.collection]!,
        remoteIdsByClientId: remoteIds,
        userId: userId,
      ));
    }

    try {
      for (final batch in planPushBatches(allOperations)) {
        await _sendPushBatch(pb, headers, batch);
      }
    } on ClientException {
      return; // 同步失敗：整批放棄，不更新任何 sync_metadata 游標
    }

    // `lastPushCompletedAt` 刻意不在這裡寫入——spec.md「同步引擎」步驟 7
    // 要求「不局部套用已完成的步驟」，若推送一成功就立刻持久化，下載
    // 階段（Task 8）萬一失敗會違反這個原子性要求。實際持久化時機挪到
    // Task 8：整個 checkpoint（推送＋下載）皆成功後才一次寫入所有游標
    // （見文末「審查修正紀錄」）。下載/合併/墓碑清理見 Task 8（本方法
    // 於該 Task 接續擴充）。
  }

  /// 記憶體風險註記（審查意見 Important #2，與 `_downloadAndMerge()` 的
  /// `getFullList()` 是同一類風險，見 Task 8 該方法的說明／文末「審查
  /// 修正紀錄」）：一次性 `rawQuery` 載入該 collection 全部 dirty 列，
  /// 極端情況（單次 checkpoint 待推送異動筆數極多）可能有記憶體壓力，
  /// 目前評估暫不需要分頁讀取，先記錄於此供日後追蹤。
  Future<List<Map<String, Object?>>> _queryDirtyRows(
    SyncCollection collection,
    int? lastPushCompletedAt,
  ) async {
    final table = collection.localTable;
    final rows = await _db.rawQuery(
      'SELECT $table.*, books.content_fingerprint AS book_fingerprint '
      'FROM $table JOIN books ON $table.book_id = books.id '
      'WHERE $table.updated_at > ?',
      [lastPushCompletedAt ?? 0],
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  /// 對本次牽涉、但尚無指紋的書籍即時補算並回填（epic-8-sync Issue 3
  /// 「首次觸發同步時才補算回填」，回填時機由本 Issue 決定，見
  /// plan-issue-4.md「與 issues.md／spec.md 的落差說明」第 3 點）：只處理
  /// 「這次有 dirty 標註列、但所屬書籍還沒有指紋」的書籍，不對整個圖書庫
  /// 掃描補算（YAGNI——沒有待推送異動的書籍，指紋在本 Issue 範圍內不影響
  /// 任何行為）。
  Future<void> _backfillMissingFingerprints(
    Map<SyncCollection, List<Map<String, Object?>>> joinedRowsByCollection,
  ) async {
    final bookIdsNeedingFingerprint = <String>{
      for (final rows in joinedRowsByCollection.values)
        for (final row in rows)
          if (row['book_fingerprint'] == null) row['book_id'] as String,
    };
    if (bookIdsNeedingFingerprint.isEmpty) return;

    final fingerprintByBookId = <String, String>{};
    for (final bookId in bookIdsNeedingFingerprint) {
      final bookRows =
          await _db.query('books', where: 'id = ?', whereArgs: [bookId]);
      if (bookRows.isEmpty) continue;
      final filePath = bookRows.single['filePath'] as String;
      final format = BookFileFormat.values.byName(bookRows.single['format'] as String);
      String? epubIdentifier;
      if (format == BookFileFormat.epub) {
        try {
          final metadata = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
            'extractMetadata',
            {'uri': filePath, 'format': format.name},
          );
          epubIdentifier = metadata?['identifier'] as String?;
        } on PlatformException {
          // 取得 OPF identifier 失敗：忽略，退回 SHA-256（比照匯入流程既有慣例，
          // 見 book_import_service_impl.dart）。
        }
      }
      try {
        final fingerprint = await computeBookContentFingerprint(
          filePath,
          format,
          epubIdentifier: epubIdentifier,
        );
        await _db.update(
          'books',
          {'content_fingerprint': fingerprint},
          where: 'id = ?',
          whereArgs: [bookId],
        );
        fingerprintByBookId[bookId] = fingerprint;
      } catch (_) {
        // 補算失敗：這本書這次不參與推送，其 dirty 列在下方被跳過，下次
        // checkpoint 會重新嘗試（比照 epic-17 detectAndCacheEpubLayout()
        // 一次性補判斷模式的失敗容忍精神）。
      }
    }

    for (final rows in joinedRowsByCollection.values) {
      for (final row in rows) {
        if (row['book_fingerprint'] == null) {
          row['book_fingerprint'] = fingerprintByBookId[row['book_id']];
        }
      }
    }
  }

  Future<void> _sendPushBatch(
    PocketBase pb,
    Map<String, String> headers,
    List<PushOperation> batch,
  ) async {
    final request = pb.createBatch();
    for (final op in batch) {
      if (op.remoteId == null) {
        request.collection(op.collection.remoteCollection).create(body: op.body);
      } else {
        request.collection(op.collection.remoteCollection).update(op.remoteId!, body: op.body);
      }
    }
    final results = await request.send(headers: headers);
    for (var i = 0; i < batch.length; i++) {
      if (batch[i].remoteId == null) {
        final body = results[i].body;
        if (body is Map) {
          final createdId = body['id'] as String?;
          if (createdId != null) {
            await _metadataRepository.saveRemoteId(
              batch[i].collection,
              batch[i].body['client_id'] as String,
              createdId,
            );
          }
        }
      }
    }
  }
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：PASS（4 個測試全數通過）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_engine.dart test/sync/sync_engine_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 7 — SyncEngine 推送階段（含指紋補算回填）"
```

---

### Task 8：`SyncEngine`——下載/合併/墓碑清理階段

**Files:**
- Modify：`app/lib/sync/sync_engine.dart`
- Test：`app/test/sync/sync_engine_test.dart`（延續 Task 7 的檔案）

**Interfaces:**
- Consumes：Task 5 的 `resolveMergeDecision`/`idsPastTombstoneRetention`/`maxUpdatedCursor`/`normalizeDeletedAt`，Task 6 的 `SyncMetadataRepository` 待處理佇列方法。
- Produces：`runCheckpoint()` 完整行為（推送成功後接續下載、合併、待處理佇列重試、墓碑清理；下載階段失敗同樣整批放棄）。**`lastPushCompletedAt` 與各 collection 的下載游標，統一延後到推送＋下載全部成功後、`runCheckpoint()` 方法最後才一次寫入**（2026-08-04 `/superpowers:requesting-code-review` 發現並修正的 Critical 問題，見文末「審查修正紀錄」），取代 Task 7 原規劃「推送成功立刻寫入 `lastPushCompletedAt`」的做法。

- [x] **Step 1：撰寫失敗測試（延續 Task 7 的 `sync_engine_test.dart`，`main()` 內新增）**

在既有最後一個 `test(...)` 之後、`}` 之前新增：

```dart

  test('下載端把遠端新增的書籤正確合併進本機（書籍已匯入、指紋對得上）', () async {
    await libraryRepository.insertBook(_testBook('b4', contentFingerprint: 'fp-4'));

    final mockClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/collections/sync_bookmarks/records') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pb-remote-1',
                'client_id': 'bm-remote-1',
                'book_fingerprint': 'fp-4',
                'deleted_at': 0,
                'name': '遠端書籤',
                'epub_locator_json': '',
                'progression': 0.3,
                'pdf_page_index': 0,
                'updated': '2026-08-03 00:00:00.000Z',
              },
            ],
            'page': 1,
            'perPage': 1000,
            'totalItems': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 其餘 collection（sync_highlights／sync_notes）與批次推送皆回傳空結果。
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final bookmarks = await bookmarksRepository.listByBook('b4');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.id, 'bm-remote-1');
    expect(bookmarks.single.name, '遠端書籤');
    expect(
      await metadataRepository.loadPulledCursor(SyncCollection.bookmarks),
      '2026-08-03 00:00:00.000Z',
    );
    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm-remote-1': 'pb-remote-1'},
    );
    // 推送＋下載整個 checkpoint 皆成功，此時 lastPushCompletedAt 才應該
    // 被寫入（審查修正紀錄 Critical：驗證游標只在完全成功後才一次持久化）。
    expect(await metadataRepository.loadLastPushCompletedAt(), isNotNull);
  });

  test('下載端遇到 book_fingerprint 查無對應本機書籍時，暫緩合併、寫入待處理佇列，不建立空殼書籍',
      () async {
    final mockClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/collections/sync_bookmarks/records') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pb-remote-2',
                'client_id': 'bm-remote-2',
                'book_fingerprint': 'fp-unimported',
                'deleted_at': 0,
                'name': '尚未匯入書籍的書籤',
                'epub_locator_json': '',
                'progression': 0.1,
                'pdf_page_index': 0,
                'updated': '2026-08-03 00:00:00.000Z',
              },
            ],
            'page': 1,
            'perPage': 1000,
            'totalItems': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final booksCount =
        (await libraryRepository.database.query('books')).length;
    expect(booksCount, 0, reason: '不應為了承接同步資料而建立空殼書籍');

    final pending = await metadataRepository.listPendingRecords();
    expect(pending, hasLength(1));
    expect(pending.single.clientId, 'bm-remote-2');
    expect(pending.single.bookFingerprint, 'fp-unimported');
  });

  test('待處理佇列中的紀錄，在對應書籍匯入（指紋比對上）後的下一次 checkpoint 正確解析落地',
      () async {
    await metadataRepository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm-pending-1',
      bookFingerprint: 'fp-later',
      remoteId: 'pb-pending-1',
      deletedAt: null,
      fields: const {
        'name': '延遲解析的書籤',
        'epub_locator_json': null,
        'progression': 0.5,
        'pdf_page_index': null,
      },
    );
    // 模擬使用者之後匯入了這本書，指紋比對上了。
    await libraryRepository.insertBook(_testBook('b5', contentFingerprint: 'fp-later'));

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final bookmarks = await bookmarksRepository.listByBook('b5');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.id, 'bm-pending-1');
    expect(bookmarks.single.name, '延遲解析的書籤');
    expect(await metadataRepository.listPendingRecords(), isEmpty);
  });

  test('本機墓碑清理：checkpoint 成功完成後，超過 30 天的軟刪除紀錄被真正清除', () async {
    await libraryRepository.insertBook(_testBook('b6', contentFingerprint: 'fp-6'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm-old', bookId: 'b6', name: 'X', progression: 0.1),
    );
    await bookmarksRepository.delete('bm-old');
    // 手動把 deleted_at 改成 31 天前，模擬「早該被清理」的墓碑。
    final old31DaysAgo =
        DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
    await libraryRepository.database.update(
      'bookmarks',
      {'deleted_at': old31DaysAgo, 'updated_at': old31DaysAgo},
      where: 'id = ?',
      whereArgs: ['bm-old'],
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm-old']);
    expect(rawRows, isEmpty, reason: '超過 30 天的墓碑應被真正 DELETE');
  });

  test(
      '下載階段失敗（HTTP 錯誤）時，即使推送階段已成功，也不執行墓碑清理、'
      '不寫入 lastPushCompletedAt／任何下載游標（審查修正紀錄 Critical：'
      '游標寫入的原子性）', () async {
    await libraryRepository.insertBook(_testBook('b7', contentFingerprint: 'fp-7'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm-should-survive', bookId: 'b7', name: 'X', progression: 0.1),
    );
    await bookmarksRepository.delete('bm-should-survive');
    final old31DaysAgo =
        DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
    await libraryRepository.database.update(
      'bookmarks',
      {'deleted_at': old31DaysAgo, 'updated_at': old31DaysAgo},
      where: 'id = ?',
      whereArgs: ['bm-should-survive'],
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        // 本測試在呼叫 runCheckpoint() 前已軟刪除 bm-should-survive，
        // 該列 updated_at 雖是「31 天前」的時間戳記，但因為
        // lastPushCompletedAt 從未寫入過（null，等同門檻 0），仍然算
        // dirty，會被推送——回應陣列長度需與批次內操作筆數（1 筆）一致，
        // 否則 _sendPushBatch() 依索引讀取 results[i] 會擲出
        // RangeError，而非測試原本要驗證的下載失敗情境。
        return http.Response(
          jsonEncode([
            {
              'status': 200,
              'body': {'id': 'pb-should-survive', 'client_id': 'bm-should-survive'},
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 下載請求一律失敗。
      return http.Response(
        jsonEncode({'message': 'Something went wrong.'}),
        500,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm-should-survive']);
    expect(rawRows, hasLength(1), reason: '下載失敗時不應執行墓碑清理');

    // 審查修正紀錄 Critical 的核心回歸測試：推送階段已經成功（上方
    // sync_remote_ids 的寫入不受影響，仍然落地——那是逐筆冪等的中繼資料，
    // 見 plan-issue-4.md「與 issues.md／spec.md 的落差說明」），但下載
    // 階段失敗，因此代表「這次 checkpoint 整體成功」的兩個游標都不應該
    // 被寫入，即使推送那一半原本已經成功。
    expect(await metadataRepository.loadLastPushCompletedAt(), isNull);
    expect(await metadataRepository.loadPulledCursor(SyncCollection.bookmarks), isNull);
    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm-should-survive': 'pb-should-survive'},
    );
  });
```

（`highlight.dart`／`highlights_repository.dart` 已在 Task 7 Step 1 的 import 區塊加入，本 Step 新增的測試直接沿用即可，不需再補 import。）

- [x] **Step 2：執行測試，確認因下載/合併/墓碑清理尚未實作而失敗**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：FAIL——新增的 5 個下載/合併/墓碑清理測試失敗（目前 `runCheckpoint()` 推送成功後直接結束，未執行任何下載/清理動作）。

- [x] **Step 3：擴充 `sync_engine.dart`——下載/合併/墓碑清理**

**本 Step 修正審查意見 Critical「同步失敗時游標未維持原子性」**（2026-08-04 `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：`lastPushCompletedAt` 與各 collection 的下載游標（`lastPulledServerUpdatedAt_<collection>`）全部改為先算在記憶體裡，等推送＋下載整個 `try` 區塊皆成功執行完畢後，才在 `runCheckpoint()` 方法的最後統一一次寫入，不再由 `_downloadAndMerge` 每處理完一個 collection 就各自立刻寫入自己的游標——避免「已推送成功、但下載到一半失敗」時，第一個 collection 的下載游標已經落地、後面的卻沒有，造成 spec.md「同步引擎」步驟 7 明訂禁止的「局部套用已完成的步驟」。

`runCheckpoint()` 方法內，Task 7 Step 3 結尾那一段註解（從 `// lastPushCompletedAt 刻意不在這裡寫入...` 開始、到 `// 於該 Task 接續擴充）。` 結束，`}` 之前的全部內容）整段替換為：

```dart
    final notDirtyUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    final pulledCursors = <SyncCollection, String?>{};

    try {
      await _resolvePendingRecords(notDirtyUpdatedAt: notDirtyUpdatedAt);
      for (final spec in syncTableSpecs.values) {
        pulledCursors[spec.collection] = await _downloadAndMerge(
          pb,
          headers,
          spec,
          notDirtyUpdatedAt: notDirtyUpdatedAt,
        );
      }
    } on ClientException {
      return; // 下載階段失敗：本次 checkpoint 視為失敗，見 spec.md 步驟 7，
      // 不寫入任何游標（含推送階段已成功的部分）、不執行墓碑清理。
    }

    // 推送＋下載皆已成功，此刻才一次寫入全部游標（見上方本 Step 開頭的
    // 審查修正說明），確保不會發生「部分 collection 的游標已落地、其餘
    // 尚未」的中繼狀態。
    await _metadataRepository.saveLastPushCompletedAt(notDirtyUpdatedAt);
    for (final entry in pulledCursors.entries) {
      final cursor = entry.value;
      if (cursor != null) {
        await _metadataRepository.savePulledCursor(entry.key, cursor);
      }
    }

    await _purgeTombstones();
  }
```

在 `_sendPushBatch` 方法之後新增以下方法：

```dart
  Future<void> _resolvePendingRecords({required int notDirtyUpdatedAt}) async {
    for (final record in await _metadataRepository.listPendingRecords()) {
      final bookRows = await _db.query(
        'books',
        columns: ['id', 'format'],
        where: 'content_fingerprint = ?',
        whereArgs: [record.bookFingerprint],
      );
      if (bookRows.isEmpty) continue; // 仍未匯入這本書，留在待處理佇列
      final bookId = bookRows.single['id'] as String;
      final format = BookFileFormat.values.byName(bookRows.single['format'] as String);
      final spec = syncTableSpecs[record.collection]!;
      final localRow = {
        'id': record.clientId,
        'book_id': bookId,
        'deleted_at': record.deletedAt,
        'updated_at': notDirtyUpdatedAt,
        ...spec.buildLocalFields(record.fields, format),
      };
      await _db.insert(
        spec.collection.localTable,
        localRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _metadataRepository.saveRemoteId(record.collection, record.clientId, record.remoteId);
      await _metadataRepository.deletePendingRecord(record.collection, record.clientId);
    }
  }

  /// 下載並合併單一 collection 的遠端異動，回傳這次應該寫回
  /// `sync_metadata` 的下載游標值（`null` 代表沒有任何新紀錄、游標維持
  /// 原值）——**不**在這個方法內直接呼叫 `savePulledCursor()`：實際持久化
  /// 時機統一挪到 `runCheckpoint()` 最後、確認推送＋下載全部成功後才一次
  /// 寫入（見 Step 3 開頭「審查修正紀錄」說明）。
  ///
  /// 記憶體風險註記（審查意見 Important #2，2026-08-04
  /// `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
  /// `getFullList()` 會把該 collection 這次符合游標條件的紀錄一次性全部
  /// 載入記憶體（PocketBase Dart SDK 內部逐頁 `getList()` 累積，見
  /// `base_crud_service.dart`），極端情況（例如長時間離線後單一 collection
  /// 累積數千筆待下載異動）可能在受限記憶體的裝置（E-Ink 閱讀器等）上
  /// 造成 OOM 風險。目前評估暫不需要實作游標分頁式讀取（chunking），先
  /// 記錄於此供日後若真的遇到 OOM 時快速定位（本 Issue 不處理）。
  Future<String?> _downloadAndMerge(
    PocketBase pb,
    Map<String, String> headers,
    SyncTableSpec spec, {
    required int notDirtyUpdatedAt,
  }) async {
    final cursor = await _metadataRepository.loadPulledCursor(spec.collection);
    final filter = cursor == null ? null : 'updated > "$cursor"';
    final records = await pb.collection(spec.collection.remoteCollection).getFullList(
          filter: filter,
          sort: 'updated',
          headers: headers,
        );
    if (records.isEmpty) return cursor;

    final fingerprints = records
        .map((r) => r.data['book_fingerprint'] as String?)
        .whereType<String>()
        .toSet();
    final booksByFingerprint = await _loadBooksByFingerprint(fingerprints);

    for (final remote in records) {
      final input = RemoteRecordMergeInput(
        remoteId: remote.data['id'] as String,
        clientId: remote.data['client_id'] as String,
        bookFingerprint: remote.data['book_fingerprint'] as String?,
        deletedAt: normalizeDeletedAt(remote.data['deleted_at']),
        rawFields: spec.extractRawFields(remote),
      );
      final decision = resolveMergeDecision(
        spec: spec,
        input: input,
        booksByFingerprint: booksByFingerprint,
        notDirtyUpdatedAt: notDirtyUpdatedAt,
      );
      if (decision.resolved) {
        await _db.insert(
          spec.collection.localTable,
          decision.localRow!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _metadataRepository.saveRemoteId(spec.collection, input.clientId, input.remoteId);
      } else {
        await _metadataRepository.savePendingRecord(
          collection: spec.collection,
          clientId: input.clientId,
          bookFingerprint: input.bookFingerprint!,
          remoteId: input.remoteId,
          deletedAt: input.deletedAt,
          fields: input.rawFields,
        );
      }
    }

    return maxUpdatedCursor(
      records.map((r) => r.data['updated'] as String).toList(),
      cursor,
    );
  }

  Future<Map<String, BookLookup>> _loadBooksByFingerprint(Set<String> fingerprints) async {
    if (fingerprints.isEmpty) return {};
    final placeholders = List.filled(fingerprints.length, '?').join(',');
    final rows = await _db.query(
      'books',
      columns: ['id', 'format', 'content_fingerprint'],
      where: 'content_fingerprint IN ($placeholders)',
      whereArgs: fingerprints.toList(),
    );
    return {
      for (final row in rows)
        row['content_fingerprint'] as String: BookLookup(
          id: row['id'] as String,
          format: BookFileFormat.values.byName(row['format'] as String),
        ),
    };
  }

  /// 每次真正 `DELETE` 最多帶入的 id 數量——與 Task 2
  /// `HighlightsRepository.deleteAllForBook()` 同一類風險（審查意見
  /// Important #1）：單一 SQL 陳述式的佔位符數量若無上限，長期離線後
  /// 一次累積大量墓碑時可能觸發 SQLite 的變數上限例外。此處篩選邏輯
  /// （[idsPastTombstoneRetention]）刻意維持純函式（spec.md「Testing
  /// Decisions」要求），只在實際執行 DELETE 時分批，不影響篩選結果。
  static const _tombstonePurgeChunkSize = 500;

  Future<void> _purgeTombstones() async {
    final now = DateTime.now();
    for (final collection in SyncCollection.values) {
      final table = collection.localTable;
      final rows = await _db.query(
        table,
        columns: ['id', 'deleted_at'],
        where: 'deleted_at IS NOT NULL',
      );
      final idsToDelete = idsPastTombstoneRetention(rows: rows, now: now);
      for (var i = 0; i < idsToDelete.length; i += _tombstonePurgeChunkSize) {
        final end = (i + _tombstonePurgeChunkSize < idsToDelete.length)
            ? i + _tombstonePurgeChunkSize
            : idsToDelete.length;
        final chunk = idsToDelete.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await _db.delete(table, where: 'id IN ($placeholders)', whereArgs: chunk);
      }
    }
  }
```

- [x] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：PASS（9 個測試全數通過）。

- [x] **Step 5：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（確認無 regression）。

```bash
git add lib/sync/sync_engine.dart test/sync/sync_engine_test.dart
git commit -m "feat(epic-8-sync): Issue 4 Task 8 — SyncEngine 下載/合併/墓碑清理階段"
```

---

### Task 9：`integration_test`——真機端到端 checkpoint 驗證

**Files:**
- Create：`app/integration_test/sync_engine_test.dart`

**Interfaces:**
- Consumes：Task 7/8 的 `SyncEngine`，Issue 7 已架好、持續運作的測試用 PocketBase 實例（`http://pbdev.jigong.org`，見 `docs/epics/epic-8-sync/pocketbase-self-hosting.md`「已知部署細節」）。

**注意（比照 `integration_test/sync_account_test.dart` 既有慣例）**：執行前裝置需先連上 Tailscale（見該文件說明），否則連線會逾時。本測試使用與 Issue 2 `integration_test` 相同的測試帳號（`epic8-issue2-test@example.com`），每個測試開頭／結尾清空該帳號在 4 個 `sync_*` collection 下的紀錄，避免測試之間互相汙染（沒有專屬的「清空 collection」API，改用 `getFullList` 讀出全部紀錄後逐筆 `delete()`，成本可接受——真機整合測試資料量小）。

- [x] **Step 1：撰寫真機測試**

Create `app/integration_test/sync_engine_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/sync/sync_engine.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 與 integration_test/sync_account_test.dart 使用同一個持續運作的測試
  // 實例／帳號（見 pocketbase-self-hosting.md「已知部署細節」）。
  const testBaseUrl = 'http://pbdev.jigong.org';
  const testEmail = 'epic8-issue2-test@example.com';
  const testPassword = 'epic8-test-password-123';
  const testCollections = ['sync_bookmarks', 'sync_highlights', 'sync_notes'];

  Future<void> clearRemoteData(PocketBase pb) async {
    for (final name in testCollections) {
      final records = await pb.collection(name).getFullList();
      for (final record in records) {
        await pb.collection(name).delete(record.id);
      }
    }
  }

  testWidgets('端到端 checkpoint：推送本機新增的書籤，真的透過 PocketBase Batch API 寫入，並於下一次 checkpoint 下載回另一個模擬裝置',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final accountRepository = SyncAccountRepository();
    await accountRepository.clearCredentials();
    final client = SyncClient(accountRepository: accountRepository);
    final loginSuccess = await client.testConnection(testBaseUrl, testEmail, testPassword);
    expect(loginSuccess, isTrue);

    final pb = PocketBase(testBaseUrl);
    await pb.collection('users').authWithPassword(testEmail, testPassword);
    await clearRemoteData(pb);
    addTearDown(() => clearRemoteData(pb));

    // 裝置 A：新增一筆書籤並推送。
    final deviceA = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceA.close());
    final bookA = Book(
      id: 'book-a',
      title: '整合測試書',
      format: BookFileFormat.epub,
      filePath: 'content://example/book-a',
      source: BookSource.local,
      contentFingerprint: 'integration-test-fingerprint-${DateTime.now().microsecondsSinceEpoch}',
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceA.insertBook(bookA);
    final bookmarksA = BookmarksRepository(deviceA.database);
    await bookmarksA.insert(
      const Bookmark(id: 'integration-bm-1', bookId: 'book-a', name: '真機測試書籤', progression: 0.42),
    );
    final engineA = SyncEngine(
      db: deviceA.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceA.database),
    );

    await engineA.runCheckpoint();

    final remoteRecords = await pb.collection('sync_bookmarks').getFullList(
          filter: 'client_id = "integration-bm-1"',
        );
    expect(remoteRecords, hasLength(1));
    expect(remoteRecords.single.data['name'], '真機測試書籤');
    expect(remoteRecords.single.data['book_fingerprint'], bookA.contentFingerprint);

    // 裝置 B：同一個帳號、同一本書（指紋相同），執行 checkpoint 應下載到
    // 裝置 A 剛才推送的書籤。
    final deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceB.close());
    // 注意：`Book.copyWith()` 刻意不含 `contentFingerprint`（見 book.dart
    // 既有註解），若在這裡呼叫 `bookA.copyWith()` 會把指紋重置為 null、
    // 破壞本測試「兩個裝置算出相同指紋」的前提。改為直接把同一個
    // `bookA` 物件（含指紋）插入裝置 B 的資料庫，模擬「裝置 B 也匯入了
    // 同一本書、算出相同指紋」的情境——兩個裝置是各自獨立的記憶體內
    // 資料庫，用同一個 id/物件插入不會互相干擾。
    await deviceB.insertBook(bookA);
    final engineB = SyncEngine(
      db: deviceB.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceB.database),
    );

    await engineB.runCheckpoint();

    final bookmarksB = BookmarksRepository(deviceB.database);
    final downloaded = await bookmarksB.listByBook('book-a');
    expect(downloaded, hasLength(1));
    expect(downloaded.single.id, 'integration-bm-1');
    expect(downloaded.single.name, '真機測試書籤');

    await client.logout();
  });
}
```

- [x] **Step 2：確認裝置已連上 Tailscale，於真實裝置/模擬器上執行**

Run：

```bash
flutter devices
flutter test integration_test/sync_engine_test.dart -d <device-id>
```

Expected：PASS——這代表推送（真的透過 PocketBase Batch API 寫入）與下載合併（真的從 PocketBase 讀回、正確寫入另一個裝置的本機資料庫）在真實網路環境下皆行為正確。

- [x] **Step 3：Commit**

```bash
git add integration_test/sync_engine_test.dart
git commit -m "test(epic-8-sync): Issue 4 Task 9 — SyncEngine 真機端到端 checkpoint 驗證"
```

---

## Self-Review Notes

- **issues.md 驗收標準覆蓋檢查**：「推送正確分批（100 筆/批），payload 皆帶 user 欄位」→ Task 4（`planPushBatches`／`buildPushOperations` 測試）＋ Task 7（`_sendPushBatch`）。「下載正確合併...client_id／highlight_client_id／book_fingerprint 跨裝置參照皆正確解析」→ Task 5（`resolveMergeDecision`）＋ Task 3（`notesSyncSpec` 的 `highlight_client_id`↔`highlight_id` 對應）＋ Task 8（`_downloadAndMerge`）。「本機墓碑清理正確執行（僅推送成功後、僅 30 天以上的墓碑）」→ Task 2（軟刪除轉換）＋ Task 5（`idsPastTombstoneRetention`）＋ Task 8（`_purgeTombstones` 僅在下載成功後才呼叫）。「同步失敗時本機異動不受影響、`sync_metadata` 游標不更新、下次重試會整批重來」→ Task 7（推送階段 `on ClientException { return; }`，尚未計算/持久化任何游標）＋ Task 8（下載階段同樣 `on ClientException { return; }`；`lastPushCompletedAt`／各 collection 下載游標統一延後到推送＋下載整個 `try` 區塊皆成功後才於 `runCheckpoint()` 最後一次寫入，即使推送階段已成功、下載階段才失敗也不會有任何游標落地，見文末「審查修正紀錄」Critical 項）。
- **與 spec.md 的一致性檢查**：「先推送、後下載」順序（Task 7 先於 Task 8）；LWW／游標一律用 PocketBase 伺服器蓋章 `updated`（Task 5 `maxUpdatedCursor`／Task 8 `_downloadAndMerge` 皆只用 `remote.data['updated']`，未使用任何客端時間比較）；本機 `updated_at`/`deleted_at` 純本機用途（Task 4 `isDirtyRow`／Task 5 合併後 `updated_at` 設為 `notDirtyUpdatedAt` 而非 `DateTime.now()`，避免下載回來的紀錄被誤判為下次待推送的 dirty）。
- **型別一致性檢查**：`SyncTableSpec.buildLocalFields(Map<String,Object?>, BookFileFormat)`（Task 3 定義）→ Task 5 `resolveMergeDecision` 與 Task 8 `_resolvePendingRecords` 呼叫時引數型別一致；`PendingSyncRecord`（Task 6 定義，含 `remoteId`/`deletedAt`/`fields`）→ Task 8 `_resolvePendingRecords` 讀取欄位名稱與型別一致；`BookLookup(id, format)`（Task 3 定義）→ Task 5/8 皆以具名參數建構，欄位名稱一致。
- **與既有慣例的差異說明彙總**（呼應文件開頭「與 issues.md／spec.md 的落差說明」）：(1) `bookmarks`/`highlights`/`notes` 軟刪除轉換（Task 2）；(2) `HighlightsRepository` 手動複製 FK `ON DELETE SET NULL` 退化行為（Task 2）；(3) 指紋補算回填時機與範圍界定（Task 7）；(4) 新增 `sync_remote_ids`/`sync_pending_records` 兩張 spec.md 未定義精確 schema 的表（Task 1）；(5) PocketBase number/text 欄位零值問題的正規化處理（Task 3/5，呼應 Issue 7 已發現的同類問題）。以上 5 項皆非本計畫自創的範圍蔓延，而是查證程式碼庫／PocketBase 實際行為後發現的必要修正，比照 `plan-issue-3.md` 先例的誠實記錄慣例。
- **測試涵蓋範圍的誠實記錄**：「批次真的分批送出、每批一個獨立 HTTP 請求」這個屬性由 Task 4 `planPushBatches`（純函式、直接斷言批次筆數）與 Task 7 `_sendPushBatch`（逐批呼叫，每批一次 `request.send()`）共同保證，`sync_engine_test.dart` 未另外寫一個「101 筆異動觸發兩次 HTTP 請求」的整合案例（因為 `planPushBatches` 已被獨立單元測試充分覆蓋，重複在 `SyncEngine` 層級驗證屬過度測試，不划算）；`SyncEngine` 層級的測試聚焦在「跨層串接是否正確」（推送成功寫回 remote id、下載正確合併、失敗正確整批放棄），不重複驗證底層純函式已覆蓋的邊界情況，比照本 Epic 前幾個 Issue 計畫的既有分層測試慣例。
- **Placeholder 掃描**：全文無 TBD/TODO；Task 8 Step 3 因程式碼分散在多個新增方法，已列出全部方法的完整程式碼（非「比照 Task N」的省略寫法）。

## 審查修正紀錄（`tmp/epic-8/plan_review_report_issue_4.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-04）結論「請在修正 Critical 的游標寫入時機，並採納 Important 的 SQL 子查詢建議後，再進行實作」，1 項 Critical、2 項 Important、1 項 Minor，逐項核對程式碼庫現況與 spec.md 原文後，結論如下：

- **Critical「同步失敗時游標未維持原子性」，確認屬實，已採納**：原規劃在推送批次成功後立刻呼叫 `saveLastPushCompletedAt()`（Task 7），且 `_downloadAndMerge()` 每處理完一個 collection 就各自呼叫 `savePulledCursor()`（Task 8）——若下載階段中途失敗（例如處理完 `bookmarks` 後 `highlights` 才拋出 `ClientException`），`lastPushCompletedAt` 與 `bookmarks` 的下載游標已經落地，違反 spec.md「同步引擎」步驟 7「不局部套用已完成的步驟」的原子性要求。已改為：`_downloadAndMerge()` 只回傳這次應寫回的游標值（`String?`），不再自己呼叫 `savePulledCursor()`；`runCheckpoint()` 把所有 collection 的回傳值暫存於記憶體 `Map`，等推送＋下載整個流程皆成功後，才在方法最後一次寫入 `lastPushCompletedAt` 與全部下載游標。新增／修改對應測試：Task 8「下載階段失敗」測試補上 `loadLastPushCompletedAt()`／`loadPulledCursor()` 皆應為 `null` 的斷言（核心回歸測試），「下載端把遠端新增的書籤正確合併進本機」測試補上 `loadLastPushCompletedAt()` 應非 `null` 的斷言（驗證完全成功路徑仍會正確持久化）；Task 7 兩則測試對應移除/調整了不再成立的 `lastPushCompletedAt` 斷言，並修正其 `MockClient` 使其能正確處理 Task 8 加入的下載請求（否則 Task 8 完成後重跑 Task 7 的既有測試會因為 mock 過度嚴格斷言請求路徑、或以錯誤型別的 JSON 回應下載請求而失敗——這是修正 Critical 過程中一併發現、非審查報告原文提及的連帶問題）。
- **Important「手動 FK 退化邏輯恐觸發 SQLite 變數上限」，確認屬實，已採納**：`HighlightsRepository.deleteAllForBook()`（Task 2）原本「先 `SELECT` 出全部有效劃線 id、再組 `IN (?,?,?...)` 佔位符」的寫法，對持有大量劃線的書籍有觸發 SQLite 變數上限例外的風險。已改用子查詢 `highlight_id IN (SELECT id FROM highlights WHERE book_id = ? AND deleted_at IS NULL)`，完全不受此限制，程式碼也更精簡（不需要先做一次額外的 `SELECT`）。**額外查證發現同一類風險也存在於 Task 8 的 `_purgeTombstones()`**（同樣是「先在 Dart 端收集 id 清單、再組 `IN` 佔位符」的模式，審查報告未提及這個第二個實例）：因為墓碑篩選邏輯（`idsPastTombstoneRetention`）依 spec.md「Testing Decisions」要求必須維持純函式，無法比照上面改用子查詢，故改為以固定上限（500 筆／批）分批執行 `DELETE`，篩選邏輯本身不受影響。
- **Important「記憶體峰值風險（大檔案/大量異動）」，確認屬實，依審查報告建議「暫不實作、僅註記」採納**：已在 Task 7 `_queryDirtyRows()`／Task 8 `_downloadAndMerge()` 的方法文件註解中記錄此風險與觸發情境，供日後若真的遇到 OOM 時快速定位；未新增分頁式讀取（chunking）實作，符合審查報告本身「考量目前可能不會發生極端狀況，可以先不實作」的建議與本專案 YAGNI 原則。
- **Minor「例外捕獲範圍與 Issue 6 互鎖機制的潛在死鎖風險」，確認屬實，已採納**：已於 `SyncEngine` 類別層級的文件註解新增給 Issue 6 實作者的提醒——`runCheckpoint()` 刻意只捕捉 `ClientException`、不捕捉 `DatabaseException`，Issue 6 規劃的 `_isSyncing` 執行鎖必須用 `try/finally` 包住 `runCheckpoint()` 呼叫，否則未預期的本機例外會讓鎖永久卡住。本 Issue 本身不需要因此變更 `runCheckpoint()` 的例外處理範圍（審查報告本身也只要求留一筆備註，非要求本 Issue 修改捕獲行為）。

## 實作結果審查修正紀錄

九個 Task 全數實作完成、提交至 `feat/epic-8-issue-4-sync-engine-core` 分支後，依本專案慣例發起第二輪 `/superpowers:requesting-code-review`（2026-08-04，針對已提交的實作程式碼，非計畫文件本身），對照 `spec.md`／本計畫逐項核對，結論「Ready to merge：With fixes」，0 Critical、2 項 Important、1 項 Minor。逐項核對程式碼庫現況後，結論如下：

- **Important「`_loadBooksByFingerprint()` 未受保護的 `IN (?,?,...)` 佔位符清單」，確認屬實，已採納**：查證後發現這正是計畫本身（Task 8 程式碼區塊）遺漏的同一類風險——同一份計畫已在 `HighlightsRepository.deleteAllForBook()`（改用子查詢）與 `_purgeTombstones()`（分批 `DELETE`）兩處明確意識到並修正 SQLite 單一陳述式變數上限問題，但 `_loadBooksByFingerprint()` 卻用原始的未分批 `IN (...)` 寫法直接被實作出來，屬計畫遺漏被原封不動實作，非實作者偏離計畫。已於 `app/lib/sync/sync_engine.dart` 改為比照 `_purgeTombstones()` 的固定上限（500 筆／批）分批查詢、於記憶體合併結果，行為不變。此問題會在「全新裝置首次對一個已累積大量書籍/標註的既有帳號執行 checkpoint」這個核心情境下觸發（下載回來的紀錄可能橫跨遠超過變數上限的不同 `book_fingerprint`），不是罕見邊角案例。
- **Important「`_downloadAndMerge()` 對 `resolveMergeDecision()` 防禦分支的空指標風險」，確認屬實，已採納**：`resolveMergeDecision()`（`sync_merge.dart`）對「`book_fingerprint` 本身為 `null`」與「查無對應本機書籍」皆回傳 `resolved: false`（且 `sync_merge_test.dart` 已有專門測試涵蓋前者），但呼叫端 `_downloadAndMerge()` 原本在 `!decision.resolved` 分支無條件對 `input.bookFingerprint` 做 `!` 空斷言後才寫入待處理佇列，等於把這個防禦分支在呼叫端又打破。已改為只在 `input.bookFingerprint != null` 時才寫入待處理佇列（真正的「查無對應書籍」情境），`bookFingerprint` 本身缺漏的遠端紀錄直接跳過（沒有指紋可供之後比對，寫進待處理佇列也永遠不會被解析）。新增回歸測試 `'下載端遇到 book_fingerprint 本身缺漏（null）的遠端紀錄時，直接跳過該筆，不拋出例外、不寫入待處理佇列'`（`sync_engine_test.dart`），並確認下載游標仍正常前進（避免下次重複下載到同一筆）。
- **Minor「`_sendPushBatch()` 未檢查 batch 回應中個別子請求的 `status`」，確認屬實，記錄為已知限制，本輪不處理**：審查報告本身也僅列為 Minor 並建議「之後補一則單元測試釐清 PocketBase Batch API 在部分失敗時的真實回應格式」，屬於需要先查證 PocketBase Batch API 是否具交易性（atomic）才能決定處理方式的開放問題，非本輪可直接動手修的具體缺陷；記錄於此供後續 Issue（例如 Issue 6 併發鎖／重試機制實作時）視情況一併查證。

`app/lib/sync/sync_engine.dart`／`app/test/sync/sync_engine_test.dart` 修正後，`flutter analyze`（"No issues found!"）與完整 `flutter test`（885 個測試全數通過）皆重新確認通過。
