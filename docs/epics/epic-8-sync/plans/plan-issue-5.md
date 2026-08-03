# Epic 8 Issue 5 — 同步引擎：閱讀位置同步與衝突彈窗（FR-19）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking。

**Goal:** 擴充 Issue 4 已完成的 `SyncEngine.runCheckpoint()`，在推送標註異動之前新增「閱讀位置衝突預檢」：偵測到本機與雲端都變動過同一本書的閱讀位置時彈窗詢問使用者要保留哪一邊，無衝突時直接推送。

**Architecture:** `sync_reading_positions` collection（`user`／`book_fingerprint`／`epub_locator`／`pdf_page_index`／`progress`，無 `client_id`、無 `deleted_at`）與 Issue 4 既有的 `sync_bookmarks`/`sync_highlights`/`sync_notes` 三個 collection 的資料形狀本質不同（每本書至多一筆，而非多筆 UUID 標註），因此**不**併入 `SyncCollection` enum／`syncTableSpecs` 那套通用機制，改為在 `SyncEngine` 內新增一段獨立、專用的閱讀位置同步邏輯（`_syncReadingPositions()`），推送階段呼叫時機在既有標註推送**之前**（符合 spec.md「同步引擎」步驟 1 的順序），仍在同一個 `try`／`on ClientException` 邊界內，確保原子性失敗語意與 Issue 4 一致。衝突判定本身抽成純函式（`resolveReadingPositionAction()`），UI 彈窗透過建構子注入的可選非同步回呼觸發（`SyncEngine` 本身沒有 `BuildContext`，也不假設呼叫端一定能顯示 UI——背景觸發等情境可以不提供回呼，衝突就單純延後到下次 checkpoint）。

**Tech Stack:** Flutter/Dart、`package:pocketbase`（Issue 2/4 已引入）、`package:sqflite`。純函式 widget/unit test（`flutter test`）；`SyncEngine` 整合測試比照 Issue 4 用 `MockClient` 假 PocketBase；雙裝置衝突情境由 `integration_test`（真機，連線 Issue 7 的 `pbdev.jigong.org` 測試實例）驗證。

## Global Constraints

- **`books.position_updated_at`／`books.position_synced_server_updated_at` 兩個 SQL 欄位已存在**（epic-8-sync Issue 1，v16→v17 migration），本 Issue **不需要新的 schema migration**——只需要把 `Book` Dart 模型補上對應欄位、並讓寫入閱讀位置的既有程式碼真正去維護 `position_updated_at`。
- **`sync_reading_positions` 沒有 `client_id`／`deleted_at` 欄位**（見 `docker/pb_migrations/1785715200_create_sync_collections.js`），每個使用者對每本書（`book_fingerprint`）至多一筆紀錄——本 Issue 的推送/衝突判定邏輯必須反映這個「以書籍為單位、非以標註列為單位」的身份模型，不可比照 Issue 4 的 UUID 聯集模式。
- **每次 create/update payload 必須明確帶入 `user` 欄位**（與 Issue 4 同一條 PocketBase API rule 限制）。
- **時間戳記單位**：本機 `position_updated_at` 為毫秒（`DateTime.now().millisecondsSinceEpoch`，與 Issue 1/4 既有 `updated_at`/`lastPushCompletedAt` 同單位）；`position_synced_server_updated_at` 為 PocketBase 伺服器蓋章的 `updated` 系統欄位原始字串（與 Issue 4 `lastPulledServerUpdatedAt_<collection>` 同性質），不做任何格式轉換，原樣存取。
- **游標寫入原子性**（沿用 Issue 4 計畫審查／實作審查兩輪修正確立的原則，見 `plan-issue-4.md`「審查修正紀錄」）：`books.position_synced_server_updated_at` 的實際持久化，必須延後到整個 checkpoint（推送＋下載）皆成功後，與 `lastPushCompletedAt`／各 collection 下載游標同一時機才一次寫入，不可在推送階段一成功就立刻寫入。
- **本 Issue 不含 Checkpoint 觸發來源與併發鎖**（App 生命週期/書籍切換/閒置計時器、`_isSyncing` 執行鎖）——見 Issue 6；本 Issue 也**不**把 `SyncEngine` real instance 接進 `main.dart`／`ReaderScreen`（比照 Issue 4「本 Issue 不含 Checkpoint 觸發來源...`runCheckpoint()` 本 Issue 僅需可被手動/測試呼叫」的既有先例）——`onReadingPositionConflict` 回呼與真正呼叫 `showReadingPositionConflictDialog()` 的實際串接，留給 Issue 6（Issue 5／6 依賴圖為「皆依賴 Issue 4、彼此互不依賴可平行」，見 issues.md）。

## 與 spec.md 的落差說明（實作決策）

依既有專案慣例（比照 `plan-issue-3.md`／`plan-issue-4.md`「與 issues.md／spec.md 的落差說明」），本計畫需要對 spec.md 未明確定義精確簽章的部分做出具體決策，記錄如下：

1. **推送方式**：spec.md「同步引擎」步驟 2 字面描述「加上步驟 1 判定可推送的閱讀位置，組成 PocketBase Batch API 請求」，字面上暗示與標註異動合併成同一個實體 HTTP 請求。但 `sync_reading_positions` 缺乏 `client_id`，無法套用 Issue 4 既有 `PushOperation`／`buildPushOperations()`／`_sendPushBatch()` 那套以 `client_id` 為基礎判斷 create/update 並回填 `sync_remote_ids` 的機制（該機制假設每筆推送都對應一個本機 UUID，閱讀位置沒有）。本計畫改為：閱讀位置用**獨立的一個** `pb.createBatch()` 呼叫（同樣是 PocketBase Batch API，只是與標註異動分開兩個實體 HTTP 請求），程式碼複雜度大幅降低、且不需要異動 Issue 4 已審查通過的既有機制。兩者仍在同一個 `try`／`on ClientException` 邊界內，任一個失敗都會讓整個 checkpoint 視為失敗，原子性保證不受影響。
2. **是否需要一張新的 `sync_remote_ids` 風格對照表**：不需要。閱讀位置的推送/衝突判定天生就需要在每次 checkpoint 時即時查詢 PocketBase 目前的 `updated` 值（衝突判定的核心依據），這次查詢本身「順便」就能取得該筆紀錄是否存在、以及其 PocketBase 內部 `id`（決定 create 或 update），不需要另外快取。
3. **`sync_metadata.last_pulled_server_updated_at_reading_positions` 欄位維持不使用**：這個 SQL 欄位自 Issue 1（v16→v17）就存在，但 spec.md「同步引擎」步驟 4 明確排除閱讀位置：「閱讀位置的下載端結果已在步驟 1 處理過，此步驟不重複處理閱讀位置」。本 Issue 的閱讀位置同步是「即時查詢單一書籍目前的伺服器狀態」而非「下載自上次游標以來所有變動」，天生不需要一個游標。這是刻意維持不用的死欄位，非本 Issue 遺漏。
4. **`ReaderScreen` 目前找不到書名時的顯示需求**：衝突彈窗需要顯示書名供使用者辨識是哪一本書，直接讀取 `books.title`（已存在的欄位），不需要額外處理。

---

### Task 1：`Book` 模型新增 `positionUpdatedAt`／`positionSyncedServerUpdatedAt` 欄位

**Files:**
- Modify：`app/lib/library/models/book.dart`
- Test：`app/test/library/models/book_test.dart`

**Interfaces:**
- Consumes：無（獨立的模型欄位新增，`books` 表的對應 SQL 欄位已由 Issue 1 建立，本 Task 只需要讓 Dart 模型讀寫得到）。
- Produces：`Book.positionUpdatedAt`（`int?`，SQL 欄位 `position_updated_at`）／`Book.positionSyncedServerUpdatedAt`（`String?`，SQL 欄位 `position_synced_server_updated_at`）。**刻意不新增到 `copyWith()`**（比照 `contentFingerprint` 既有先例，見 `book.dart` 現有註解「若 Issue 4 的補算回填流程需要，屆時再新增」——本 Issue 對這兩個欄位的所有寫入皆透過 Task 2（`ReadingPositionRepository`，partial update）與 Task 5（`SyncEngine`，raw `_db.update`）繞過 `Book` 模型完成，沒有任何呼叫端需要透過 `copyWith()` 修改這兩個欄位，YAGNI）。供 Task 2／Task 5 的測試建構 `Book` 物件時使用；供 Task 5 讀取既有書籍的 `position_synced_server_updated_at` 快取值使用。

- [ ] **Step 1：撰寫失敗測試**

在 `app/test/library/models/book_test.dart` 檔案結尾（最後一個 `test(...)` 之後、檔案結尾 `}` 之前）新增：

```dart

  test('positionUpdatedAt／positionSyncedServerUpdatedAt 欄位可正確往返（epic-8-sync Issue 5）',
      () {
    final book = Book(
      id: 'b15',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      positionUpdatedAt: 1735689600000,
      positionSyncedServerUpdatedAt: '2026-08-04 12:00:00.000Z',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.positionUpdatedAt, 1735689600000);
    expect(restored.positionSyncedServerUpdatedAt, '2026-08-04 12:00:00.000Z');
  });

  test('positionUpdatedAt／positionSyncedServerUpdatedAt 未設定時，往返後仍為 null（代表尚未同步過閱讀位置）',
      () {
    final book = Book(
      id: 'b16',
      title: '書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.positionUpdatedAt, isNull);
    expect(restored.positionSyncedServerUpdatedAt, isNull);
  });
```

- [ ] **Step 2：執行測試，確認因欄位不存在而失敗**

Run（於 `app/` 目錄下）：

```bash
flutter test test/library/models/book_test.dart
```

Expected：FAIL，編譯錯誤指出 `Book` 建構子沒有 `positionUpdatedAt`／`positionSyncedServerUpdatedAt` 具名參數。

- [ ] **Step 3：`Book` 模型新增欄位**

`app/lib/library/models/book.dart` 的 `contentFingerprint` 欄位宣告（`final String? contentFingerprint;`）之後新增：

```dart
  /// 閱讀位置最後一次本機異動時間（epic-8-sync Issue 5，spec.md「本機
  /// Schema 變更」／「同步引擎」）：純本機時鐘，供同步引擎判斷「這本書
  /// 的閱讀位置自上次推送後是否有新異動」，只跟自己過去的
  /// `sync_metadata.lastPushCompletedAt` 比較，不跨裝置比較（與
  /// `bookmarks`/`highlights`/`notes` 的 `updated_at` 同一性質）。`null`
  /// 代表這本書的閱讀位置從未變動過（或此裝置尚未升級到本 Issue 之前
  /// 就已存在的既有記錄）。由 `ReadingPositionRepository.save()` 在每次
  /// 寫入閱讀位置時一併維護，不放在本模型的 `copyWith()`（見下方）。
  final int? positionUpdatedAt;

  /// 快取上次成功同步時，PocketBase `sync_reading_positions` 該筆紀錄的
  /// 伺服器時間戳記字串（epic-8-sync Issue 5，spec.md「本機 Schema
  /// 變更」）：供同步引擎偵測「其他裝置是否在此之後又推送過」用——與
  /// 本機快取值不同即代表衝突。`null` 代表這本書的閱讀位置從未成功同步
  /// 過。**刻意不新增到 `copyWith()`**（比照 [contentFingerprint] 既有
  /// 先例）：本 Issue 對這兩個欄位的所有寫入皆透過 partial update
  /// （`ReadingPositionRepository`／`SyncEngine` 的 raw SQL）完成，沒有
  /// 呼叫端需要透過 `copyWith()` 修改，YAGNI。
  final String? positionSyncedServerUpdatedAt;
```

建構子（`const Book({...})`）內、`this.contentFingerprint,` 那一行之後新增：

```dart
    this.positionUpdatedAt,
    this.positionSyncedServerUpdatedAt,
```

`toMap()` 的 `'content_fingerprint': contentFingerprint,` 那一行之後新增：

```dart
      'position_updated_at': positionUpdatedAt,
      'position_synced_server_updated_at': positionSyncedServerUpdatedAt,
```

`Book.fromMap()` 的 `contentFingerprint: map['content_fingerprint'] as String?,` 那一行之後新增：

```dart
      positionUpdatedAt: map['position_updated_at'] as int?,
      positionSyncedServerUpdatedAt:
          map['position_synced_server_updated_at'] as String?,
```

`operator ==` 的 `contentFingerprint == other.contentFingerprint &&` 那一行之後新增：

```dart
          contentFingerprint == other.contentFingerprint &&
          positionUpdatedAt == other.positionUpdatedAt &&
          positionSyncedServerUpdatedAt == other.positionSyncedServerUpdatedAt &&
```

（注意：上面第一行 `contentFingerprint == other.contentFingerprint &&` 是既有程式碼，僅用來標示插入位置，實作時不要重複貼上這一行。）

`hashCode` 的 `contentFingerprint,` 那一行之後新增：

```dart
        contentFingerprint,
        positionUpdatedAt,
        positionSyncedServerUpdatedAt,
```

（同樣，第一行 `contentFingerprint,` 是既有程式碼，僅標示插入位置。）

- [ ] **Step 4：執行測試，確認通過**

Run：

```bash
flutter test test/library/models/book_test.dart
```

Expected：PASS（全部既有＋新增 2 則測試）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/library/models/book.dart test/library/models/book_test.dart
git commit -m "feat(epic-8-sync): Issue 5 Task 1 — Book 模型新增 positionUpdatedAt／positionSyncedServerUpdatedAt"
```

Expected：`flutter analyze` 顯示 "No issues found!"。

---

### Task 2：`ReadingPositionRepository.save()` 維護 `position_updated_at`

**Files:**
- Modify：`app/lib/reader/reading_position_repository.dart`
- Test：`app/test/reader/reading_position_repository_test.dart`

**Interfaces:**
- Consumes：無。
- Produces：`ReadingPositionRepository.save()` 對外簽章不變（`Future<void> save(String bookId, ReadingPosition position)`），但每次成功寫入時，一併把 `books.position_updated_at` 設為目前時間戳記——這是 Issue 5 判斷「這本書的閱讀位置是否需要推送」的唯一觸發點（`ReaderScreen._writeCurrentPosition()` 是目前這個方法唯一的呼叫端，見 plan 開頭調查，`dispose()`／App 背景化各觸發一次，不逐頁呼叫）。供 Task 5（`SyncEngine._syncReadingPositions()`）的 dirty 判定使用。

- [ ] **Step 1：撰寫失敗測試**

在 `app/test/reader/reading_position_repository_test.dart` 檔案結尾（最後一個 `test(...)` 之後、檔案結尾 `}` 之前）新增：

```dart

  test('save 寫入後，position_updated_at 被設為目前時間戳記（epic-8-sync Issue 5）', () async {
    final before = DateTime.now().millisecondsSinceEpoch;

    await repository.save('b1', const ReadingPosition(pdfPageIndex: 3, progress: 0.3));

    final after = DateTime.now().millisecondsSinceEpoch;
    final rows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final updatedAt = rows.single['position_updated_at'] as int;
    expect(updatedAt, greaterThanOrEqualTo(before));
    expect(updatedAt, lessThanOrEqualTo(after));
  });

  test('save 兩次呼叫，第二次的 position_updated_at 不早於第一次', () async {
    await repository.save('b1', const ReadingPosition(pdfPageIndex: 1, progress: 0.1));
    final firstRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final firstUpdatedAt = firstRows.single['position_updated_at'] as int;

    await repository.save('b1', const ReadingPosition(pdfPageIndex: 2, progress: 0.2));
    final secondRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final secondUpdatedAt = secondRows.single['position_updated_at'] as int;

    expect(secondUpdatedAt, greaterThanOrEqualTo(firstUpdatedAt));
  });
```

- [ ] **Step 2：執行測試，確認因 `position_updated_at` 仍為 `null` 而失敗**

Run：

```bash
flutter test test/reader/reading_position_repository_test.dart
```

Expected：FAIL，`updatedAt` 讀到 `null`，`as int` 轉型例外。

- [ ] **Step 3：`save()` 新增 `position_updated_at` 寫入**

`app/lib/reader/reading_position_repository.dart` 的 `save()` 方法改為：

```dart
  /// Partial update：只更新這 3 個欄位（及 epic-8-sync Issue 5 新增的
  /// `position_updated_at`），不影響書籍的其餘欄位。若 [bookId] 對應的
  /// 書籍列不存在（理論上不應發生——呼叫端一定是先從圖書庫開啟既有
  /// 書籍才會進到 ReaderScreen），SQLite 的 UPDATE 會影響 0 列，靜默無
  /// 效果，不拋出例外。
  ///
  /// `position_updated_at` 由本方法統一維護（而非呼叫端），確保「使用者
  /// 讀過這本書、位置有異動」與「同步引擎判斷這本書的位置需要推送」
  /// 兩者永遠同步、不會遺漏（epic-8-sync Issue 5，spec.md「本機 Schema
  /// 變更」／「同步引擎」）。
  Future<void> save(String bookId, ReadingPosition position) async {
    await _db.update(
      'books',
      {
        'epubLocator': position.epubLocatorJson,
        'pdfPageIndex': position.pdfPageIndex,
        'progress': position.progress,
        'position_updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
```

- [ ] **Step 4：執行測試，確認通過**

Run：

```bash
flutter test test/reader/reading_position_repository_test.dart
```

Expected：PASS（全部既有＋新增 2 則測試）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/reader/reading_position_repository.dart test/reader/reading_position_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 5 Task 2 — ReadingPositionRepository.save() 維護 position_updated_at"
```

---

### Task 3：純函式——閱讀位置衝突判定 + 資料模型

**Files:**
- Create：`app/lib/sync/sync_reading_position.dart`
- Test：`app/test/sync/sync_reading_position_test.dart`

**Interfaces:**
- Consumes：`BookFileFormat`（`app/lib/library/models/library_enums.dart`）。
- Produces：`ReadingPositionSnapshot`（純資料：`epubLocatorJson`/`pdfPageIndex`/`progress`）、`ReadingPositionChoice` enum（`keepLocal`/`keepCloud`）、`ReadingPositionConflict`（純資料：`bookId`/`bookTitle`/`format`/`local`/`remote`）、`ReadingPositionConflictResolver` typedef（`Future<ReadingPositionChoice?> Function(ReadingPositionConflict conflict)`）、`ReadingPositionSyncAction` enum（`noAction`/`pushLocalDirectly`/`needsUserDecision`）、`ReadingPositionSyncAction resolveReadingPositionAction({required int? positionUpdatedAt, required int? lastPushCompletedAt, required String? positionSyncedServerUpdatedAt, required String? remoteServerUpdated})`。供 Task 4（對話框 UI 使用 `ReadingPositionConflict`/`ReadingPositionChoice`）／Task 5（`SyncEngine` 使用全部型別）使用。

- [ ] **Step 1：撰寫失敗測試**

Create `app/test/sync/sync_reading_position_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

void main() {
  group('resolveReadingPositionAction', () {
    test('本機不 dirty（positionUpdatedAt 為 null）時，回傳不需要動作', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: null,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-01 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.noAction);
    });

    test('本機不 dirty（positionUpdatedAt 未晚於 lastPushCompletedAt）時，回傳不需要動作', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 1000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.noAction);
    });

    test('本機 dirty 且遠端沒有既有紀錄（remoteServerUpdated 為 null）時，直接套用本機', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });

    test('本機 dirty 且伺服器 updated 與本機快取值相同時，直接套用本機', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-01 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });

    test('本機 dirty 且伺服器 updated 與本機快取值不同時，回傳需要詢問使用者', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-02 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.needsUserDecision);
    });

    test('本機 dirty、本機從未同步過（快取為 null）但遠端已有紀錄時，視為衝突（無法確定沒有其他裝置動過）',
        () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: '2026-08-02 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.needsUserDecision);
    });

    test('lastPushCompletedAt 為 null（從未推送過）時，任何非 null 的 positionUpdatedAt 皆視為 dirty',
        () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 1,
        lastPushCompletedAt: null,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });
  });

  group('ReadingPositionConflict', () {
    test('可正確建構並讀取本機/雲端兩個版本的快照', () {
      const conflict = ReadingPositionConflict(
        bookId: 'b1',
        bookTitle: '測試書',
        format: BookFileFormat.pdf,
        local: ReadingPositionSnapshot(pdfPageIndex: 10, progress: 0.5),
        remote: ReadingPositionSnapshot(pdfPageIndex: 20, progress: 0.8),
      );

      expect(conflict.local.pdfPageIndex, 10);
      expect(conflict.remote.pdfPageIndex, 20);
    });
  });
}
```

- [ ] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/sync/sync_reading_position_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/sync/sync_reading_position.dart`。

- [ ] **Step 3：實作 `sync_reading_position.dart`**

Create `app/lib/sync/sync_reading_position.dart`：

```dart
import '../library/models/library_enums.dart';

/// 單一書籍在某一端（本機或雲端）的閱讀位置快照（epic-8-sync Issue 5，
/// spec.md「同步引擎」）：與 [ReadingPosition]（`reader/reading_position.dart`）
/// 語意相同，此處獨立定義避免 `sync/` 模組反向依賴 `reader/`。
class ReadingPositionSnapshot {
  final String? epubLocatorJson;
  final int? pdfPageIndex;
  final double progress;

  const ReadingPositionSnapshot({
    this.epubLocatorJson,
    this.pdfPageIndex,
    this.progress = 0,
  });
}

/// 使用者對閱讀位置衝突的選擇。
enum ReadingPositionChoice { keepLocal, keepCloud }

/// 一次閱讀位置衝突（FR-19）：本機與雲端都變動過同一本書的位置。
class ReadingPositionConflict {
  final String bookId;
  final String bookTitle;
  final BookFileFormat format;
  final ReadingPositionSnapshot local;
  final ReadingPositionSnapshot remote;

  const ReadingPositionConflict({
    required this.bookId,
    required this.bookTitle,
    required this.format,
    required this.local,
    required this.remote,
  });
}

/// 供 [SyncEngine]（`sync_engine.dart`）注入的衝突解決回呼——`null` 代表
/// 呼叫端沒有可用的 UI（例如背景觸發的 checkpoint），此時偵測到衝突會
/// 直接跳過該本書，留待下次 checkpoint 重試；回呼本身回傳 `null` 代表
/// 使用者關閉對話框、尚未決定，同樣跳過、下次重試。
typedef ReadingPositionConflictResolver = Future<ReadingPositionChoice?>
    Function(ReadingPositionConflict conflict);

/// 閱讀位置同步判定結果三選一（spec.md「同步引擎」步驟 1／issues.md
/// Issue 5 單元測試要求逐字對應：`noAction`＝「不需要動作」、
/// `pushLocalDirectly`＝「直接套用本機」、`needsUserDecision`＝「需要
/// 詢問使用者」）。
enum ReadingPositionSyncAction { noAction, pushLocalDirectly, needsUserDecision }

/// 閱讀位置衝突判定純函式（spec.md「同步引擎」步驟 1／「Testing
/// Decisions」）。[positionUpdatedAt] 為 `null` 或未晚於 [lastPushCompletedAt]
/// 時代表本機沒有待推送的位置異動；[remoteServerUpdated] 為 `null` 代表
/// PocketBase 目前沒有這本書的既有紀錄（第一次同步，不可能衝突）；
/// [positionSyncedServerUpdatedAt] 為本機快取的「上次成功同步時的伺服器
/// 時間戳記」，與 [remoteServerUpdated] 不同（含本機快取為 `null` 但遠端
/// 已有紀錄的情況——代表本機從未確認過遠端現況，無法排除衝突）即視為
/// 衝突。
ReadingPositionSyncAction resolveReadingPositionAction({
  required int? positionUpdatedAt,
  required int? lastPushCompletedAt,
  required String? positionSyncedServerUpdatedAt,
  required String? remoteServerUpdated,
}) {
  final isDirty =
      positionUpdatedAt != null && positionUpdatedAt > (lastPushCompletedAt ?? 0);
  if (!isDirty) return ReadingPositionSyncAction.noAction;
  if (remoteServerUpdated == null) return ReadingPositionSyncAction.pushLocalDirectly;
  if (remoteServerUpdated == positionSyncedServerUpdatedAt) {
    return ReadingPositionSyncAction.pushLocalDirectly;
  }
  return ReadingPositionSyncAction.needsUserDecision;
}
```

- [ ] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_reading_position_test.dart
```

Expected：PASS（8 個測試全數通過）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_reading_position.dart test/sync/sync_reading_position_test.dart
git commit -m "feat(epic-8-sync): Issue 5 Task 3 — 閱讀位置衝突判定純函式與資料模型"
```

---

### Task 4：閱讀位置衝突對話框

**Files:**
- Create：`app/lib/screens/reading_position_conflict_dialog.dart`
- Test：`app/test/screens/reading_position_conflict_dialog_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `ReadingPositionConflict`／`ReadingPositionChoice`／`ReadingPositionSnapshot`。
- Produces：`Future<ReadingPositionChoice?> showReadingPositionConflictDialog(BuildContext context, ReadingPositionConflict conflict)`——符合 Task 3 的 `ReadingPositionConflictResolver` typedef 簽章，供 Issue 6 實際串接進 `SyncEngine` 建構子時使用（本 Issue 只交付這個函式本身並完整測試，比照 plan-issue-5.md Global Constraints 說明，不做 `main.dart`/`ReaderScreen` 的實際接線）。

- [ ] **Step 1：撰寫失敗測試**

Create `app/test/screens/reading_position_conflict_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/reading_position_conflict_dialog.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

void main() {
  const conflict = ReadingPositionConflict(
    bookId: 'b1',
    bookTitle: '測試書名',
    format: BookFileFormat.pdf,
    local: ReadingPositionSnapshot(pdfPageIndex: 9, progress: 0.5),
    remote: ReadingPositionSnapshot(pdfPageIndex: 19, progress: 0.8),
  );

  Future<void> pumpTrigger(
    WidgetTester tester,
    ValueSetter<ReadingPositionChoice?> onResult,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final choice = await showReadingPositionConflictDialog(context, conflict);
            onResult(choice);
          },
          child: const Text('trigger'),
        ),
      ),
    ));
  }

  testWidgets('顯示書名，以及本機／雲端兩個版本的進度描述', (tester) async {
    await pumpTrigger(tester, (_) {});
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.textContaining('測試書名'), findsOneWidget);
    expect(find.textContaining('第 10 頁'), findsOneWidget); // pdfPageIndex 9 -> 顯示第 10 頁
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('第 20 頁'), findsOneWidget);
    expect(find.textContaining('80%'), findsOneWidget);
  });

  testWidgets('點擊「保留本機」，回傳 ReadingPositionChoice.keepLocal', (tester) async {
    ReadingPositionChoice? result;
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading_position_conflict_keep_local')));
    await tester.pumpAndSettle();

    expect(result, ReadingPositionChoice.keepLocal);
  });

  testWidgets('點擊「保留雲端」，回傳 ReadingPositionChoice.keepCloud', (tester) async {
    ReadingPositionChoice? result;
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading_position_conflict_keep_cloud')));
    await tester.pumpAndSettle();

    expect(result, ReadingPositionChoice.keepCloud);
  });

  testWidgets('點擊對話框外部關閉（未決定）時，回傳 null，不視為任何選擇', (tester) async {
    ReadingPositionChoice? result = ReadingPositionChoice.keepLocal; // 給一個非 null 初始值，確保下方真的被覆寫成 null
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // 點擊 barrier（對話框外部區域）觸發預設的 dismiss 行為。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2：執行測試，確認因檔案不存在而失敗**

Run：

```bash
flutter test test/screens/reading_position_conflict_dialog_test.dart
```

Expected：FAIL，找不到 `package:elinkbook/screens/reading_position_conflict_dialog.dart`。

- [ ] **Step 3：實作對話框**

Create `app/lib/screens/reading_position_conflict_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/models/library_enums.dart';
import '../sync/sync_reading_position.dart';

/// 把單一版本的閱讀位置快照轉成人類可讀的描述，供 [showReadingPositionConflictDialog]
/// 顯示——PDF 額外顯示頁碼（1-indexed，[ReadingPositionSnapshot.pdfPageIndex]
/// 本身是 0-indexed），EPUB 僅顯示進度百分比（CFI 定位字串本身無法簡單
/// 轉成人類可讀文字）。
String _describeReadingPosition(
  ReadingPositionSnapshot snapshot,
  BookFileFormat format,
) {
  final percent = (snapshot.progress * 100).round();
  if (format == BookFileFormat.pdf && snapshot.pdfPageIndex != null) {
    return '第 ${snapshot.pdfPageIndex! + 1} 頁（進度 $percent%）';
  }
  return '進度 $percent%';
}

/// 閱讀位置衝突對話框（epic-8-sync Issue 5，FR-19：「若開啟書籍時雲端
/// 同步的位置與本機位置不一致，須先詢問使用者確認才跳轉——絕不可靜默
/// 覆蓋」）。回傳使用者的選擇；使用者關閉對話框（例如點擊外部區域）
/// 未做選擇時回傳 `null`，符合 `ReadingPositionConflictResolver` 的
/// 契約（`SyncEngine` 收到 `null` 時會跳過這本書、留待下次 checkpoint
/// 重試，不靜默覆蓋任一邊）。
Future<ReadingPositionChoice?> showReadingPositionConflictDialog(
  BuildContext context,
  ReadingPositionConflict conflict,
) {
  return showDialog<ReadingPositionChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('「${conflict.bookTitle}」的閱讀進度不一致'),
      content: Text(
        '偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n'
        '本機：${_describeReadingPosition(conflict.local, conflict.format)}\n'
        '雲端：${_describeReadingPosition(conflict.remote, conflict.format)}',
      ),
      actions: [
        TextButton(
          key: const Key('reading_position_conflict_keep_cloud'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(ReadingPositionChoice.keepCloud),
          child: const Text('保留雲端'),
        ),
        TextButton(
          key: const Key('reading_position_conflict_keep_local'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(ReadingPositionChoice.keepLocal),
          child: const Text('保留本機'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4：執行測試，確認全數通過**

Run：

```bash
flutter test test/screens/reading_position_conflict_dialog_test.dart
```

Expected：PASS（4 個測試全數通過）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/screens/reading_position_conflict_dialog.dart test/screens/reading_position_conflict_dialog_test.dart
git commit -m "feat(epic-8-sync): Issue 5 Task 4 — 閱讀位置衝突對話框"
```

---

### Task 5：`SyncEngine` 擴充——閱讀位置衝突預檢 + 推送

**Files:**
- Modify：`app/lib/sync/sync_engine.dart`
- Test：`app/test/sync/sync_engine_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `ReadingPositionSnapshot`／`ReadingPositionConflict`／`ReadingPositionChoice`／`ReadingPositionConflictResolver`／`ReadingPositionSyncAction`／`resolveReadingPositionAction()`。
- Produces：`SyncEngine` 建構子新增可選具名參數 `ReadingPositionConflictResolver? onReadingPositionConflict`（預設 `null`）；`runCheckpoint()` 於既有標註推送之前新增閱讀位置衝突預檢＋推送，`books.position_synced_server_updated_at` 延後到整個 checkpoint 成功後才與 `lastPushCompletedAt`／下載游標一起寫入。

- [ ] **Step 1：Refactor——抽出可重用的單一書籍指紋補算方法（不改變既有行為，先確保既有測試仍通過）**

`app/lib/sync/sync_engine.dart` 的 `_backfillMissingFingerprints()` 方法（Issue 4 既有程式碼）改為：

```dart
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
      final fingerprint = await _backfillFingerprintForBook(bookId);
      if (fingerprint != null) {
        fingerprintByBookId[bookId] = fingerprint;
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

  /// 對單一書籍計算並回填 `content_fingerprint`（epic-8-sync Issue 3；
  /// 抽出為獨立方法供 [_backfillMissingFingerprints]〔標註異動觸發〕與
  /// `_syncReadingPositions`〔閱讀位置異動觸發，epic-8-sync Issue 5〕
  /// 共用，避免重複 EPUB identifier 擷取與 SHA-256 計算邏輯）。計算失敗
  /// （原生端例外／檔案讀取失敗）時回傳 `null`，呼叫端決定如何降級
  /// （比照既有慣例，這本書這次跳過，下次 checkpoint 重新嘗試）。
  Future<String?> _backfillFingerprintForBook(String bookId) async {
    final bookRows = await _db.query('books', where: 'id = ?', whereArgs: [bookId]);
    if (bookRows.isEmpty) return null;
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
      return fingerprint;
    } catch (_) {
      return null;
    }
  }
```

（這是純粹的抽取重構——原本內嵌在 `_backfillMissingFingerprints()` 迴圈內的計算邏輯，原封不動搬到新方法 `_backfillFingerprintForBook()`，呼叫端行為完全不變。）

- [ ] **Step 2：執行 Issue 4 既有測試，確認 refactor 沒有破壞任何行為**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：PASS（Issue 4 既有全部測試通過，尚未新增本 Task 的測試）。

- [ ] **Step 3：Commit（refactor 獨立一個 commit，方便之後追蹤）**

```bash
flutter analyze
git add lib/sync/sync_engine.dart
git commit -m "refactor(epic-8-sync): Issue 5 Task 5 Step 1 — 抽出 _backfillFingerprintForBook 供閱讀位置同步共用"
```

Expected：`flutter analyze` "No issues found!"。

- [ ] **Step 4：撰寫失敗測試——閱讀位置同步情境**

`app/test/sync/sync_engine_test.dart` 的 `_testBook()` 輔助函式改為：

```dart
Book _testBook(
  String id, {
  String? contentFingerprint,
  BookFileFormat format = BookFileFormat.epub,
  int? positionUpdatedAt,
  String? positionSyncedServerUpdatedAt,
  String? epubLocator,
  int? pdfPageIndex,
  double progress = 0,
}) {
  return Book(
    id: id,
    title: '測試書',
    format: format,
    filePath: 'content://example/$id',
    source: BookSource.local,
    contentFingerprint: contentFingerprint,
    positionUpdatedAt: positionUpdatedAt,
    positionSyncedServerUpdatedAt: positionSyncedServerUpdatedAt,
    epubLocator: epubLocator,
    pdfPageIndex: pdfPageIndex,
    progress: progress,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}
```

在檔案結尾（最後一個 `test(...)` 之後、`main()` 結尾 `}` 之前）新增：

```dart

  group('閱讀位置同步（epic-8-sync Issue 5）', () {
    test('本機閱讀位置有異動、遠端無既有紀錄時，直接推送（create），成功後回填 position_synced_server_updated_at',
        () async {
      await libraryRepository.insertBook(_testBook(
        'b20',
        contentFingerprint: 'fp-20',
        positionUpdatedAt: 5000,
        epubLocator: '{"href":"/c1.xhtml"}',
        progress: 0.4,
      ));

      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/collections/sync_reading_positions/records') {
          return http.Response(
            jsonEncode({'items': [], 'page': 1, 'perPage': 1, 'totalItems': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/batch') {
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          final subRequests = decoded['requests'] as List;
          final readingPositionRequest = subRequests.firstWhere(
            (r) => (r['url'] as String).contains('sync_reading_positions'),
            orElse: () => null,
          );
          if (readingPositionRequest != null) {
            capturedBody = readingPositionRequest['body'] as Map<String, dynamic>;
            return http.Response(
              jsonEncode([
                {
                  'status': 200,
                  'body': {
                    'id': 'pb-position-1',
                    'book_fingerprint': 'fp-20',
                    'updated': '2026-08-04 00:00:00.000Z',
                  },
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
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

      expect(capturedBody?['user'], 'user-1');
      expect(capturedBody?['book_fingerprint'], 'fp-20');
      expect(capturedBody?['epub_locator'], '{"href":"/c1.xhtml"}');
      expect(capturedBody?['progress'], 0.4);

      final bookRows = await libraryRepository.database
          .query('books', where: 'id = ?', whereArgs: ['b20']);
      expect(
        bookRows.single['position_synced_server_updated_at'],
        '2026-08-04 00:00:00.000Z',
      );
    });

    test('本機無待推送的閱讀位置異動時，完全不查詢 sync_reading_positions', () async {
      await libraryRepository.insertBook(_testBook('b21', contentFingerprint: 'fp-21'));

      var readingPositionQueried = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/collections/sync_reading_positions/records') {
          readingPositionQueried = true;
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

      expect(readingPositionQueried, isFalse);
    });

    test('偵測到衝突、未提供 onReadingPositionConflict 回呼時，跳過該本書、不推送、position_updated_at 維持待重試',
        () async {
      await libraryRepository.insertBook(_testBook(
        'b22',
        contentFingerprint: 'fp-22',
        positionUpdatedAt: 5000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        progress: 0.3,
      ));

      var readingPositionPushed = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/collections/sync_reading_positions/records') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'pb-position-existing',
                  'book_fingerprint': 'fp-22',
                  'epub_locator': null,
                  'pdf_page_index': null,
                  'progress': 0.9,
                  'updated': '2026-08-03 00:00:00.000Z', // 與本機快取不同 -> 衝突
                },
              ],
              'page': 1,
              'perPage': 1,
              'totalItems': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/batch') {
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          final subRequests = decoded['requests'] as List;
          if (subRequests.any((r) => (r['url'] as String).contains('sync_reading_positions'))) {
            readingPositionPushed = true;
          }
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
        // onReadingPositionConflict 未提供（null）。
      );

      await engine.runCheckpoint();

      expect(readingPositionPushed, isFalse);
      final bookRows = await libraryRepository.database
          .query('books', where: 'id = ?', whereArgs: ['b22']);
      expect(bookRows.single['progress'], 0.3, reason: '本機資料不受影響，未被靜默覆蓋');
      expect(
        bookRows.single['position_synced_server_updated_at'],
        '2026-08-01 00:00:00.000Z',
        reason: '未成功同步，快取值不應變動',
      );
    });

    test('偵測到衝突、使用者選擇保留本機時，推送本機值（update，remoteId 已知）', () async {
      await libraryRepository.insertBook(_testBook(
        'b23',
        contentFingerprint: 'fp-23',
        format: BookFileFormat.pdf,
        positionUpdatedAt: 5000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        pdfPageIndex: 10,
        progress: 0.5,
      ));

      Map<String, dynamic>? capturedBody;
      String? capturedUrl;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/collections/sync_reading_positions/records') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'pb-position-existing-2',
                  'book_fingerprint': 'fp-23',
                  'pdf_page_index': 30,
                  'progress': 0.9,
                  'updated': '2026-08-03 00:00:00.000Z',
                },
              ],
              'page': 1,
              'perPage': 1,
              'totalItems': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/batch') {
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          final subRequests = decoded['requests'] as List;
          final readingPositionRequest = subRequests.firstWhere(
            (r) => (r['url'] as String).contains('sync_reading_positions'),
            orElse: () => null,
          );
          if (readingPositionRequest != null) {
            capturedBody = readingPositionRequest['body'] as Map<String, dynamic>;
            capturedUrl = readingPositionRequest['url'] as String;
          }
          return http.Response(
            jsonEncode([
              {
                'status': 200,
                'body': {'updated': '2026-08-04 00:00:00.000Z'},
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
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
        onReadingPositionConflict: (conflict) async {
          expect(conflict.bookId, 'b23');
          expect(conflict.local.pdfPageIndex, 10);
          expect(conflict.remote.pdfPageIndex, 30);
          return ReadingPositionChoice.keepLocal;
        },
      );

      await engine.runCheckpoint();

      expect(capturedBody?['pdf_page_index'], 10, reason: '推送的是本機值');
      expect(capturedUrl, contains('pb-position-existing-2'), reason: '走 update（PATCH），不是 create');

      final bookRows = await libraryRepository.database
          .query('books', where: 'id = ?', whereArgs: ['b23']);
      expect(
        bookRows.single['position_synced_server_updated_at'],
        '2026-08-04 00:00:00.000Z',
      );
    });

    test('偵測到衝突、使用者選擇保留雲端時，立即覆寫本機位置，不推送任何值', () async {
      await libraryRepository.insertBook(_testBook(
        'b24',
        contentFingerprint: 'fp-24',
        format: BookFileFormat.pdf,
        positionUpdatedAt: 5000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        pdfPageIndex: 10,
        progress: 0.5,
      ));

      var readingPositionPushed = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/collections/sync_reading_positions/records') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'pb-position-existing-3',
                  'book_fingerprint': 'fp-24',
                  'pdf_page_index': 30,
                  'progress': 0.9,
                  'updated': '2026-08-03 00:00:00.000Z',
                },
              ],
              'page': 1,
              'perPage': 1,
              'totalItems': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/batch') {
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          final subRequests = decoded['requests'] as List;
          if (subRequests.any((r) => (r['url'] as String).contains('sync_reading_positions'))) {
            readingPositionPushed = true;
          }
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
        onReadingPositionConflict: (conflict) async => ReadingPositionChoice.keepCloud,
      );

      await engine.runCheckpoint();

      expect(readingPositionPushed, isFalse);
      final bookRows = await libraryRepository.database
          .query('books', where: 'id = ?', whereArgs: ['b24']);
      expect(bookRows.single['pdfPageIndex'], 30, reason: '本機已被覆寫為雲端版本');
      expect(bookRows.single['progress'], 0.9);
      expect(
        bookRows.single['position_synced_server_updated_at'],
        '2026-08-03 00:00:00.000Z',
        reason: '雲端版本已是本機認可的版本，快取值同步更新，避免下次誤判為衝突',
      );
    });

    test('推送階段失敗（HTTP 錯誤）時，即使閱讀位置查詢成功，也不寫入 position_synced_server_updated_at',
        () async {
      await libraryRepository.insertBook(_testBook(
        'b25',
        contentFingerprint: 'fp-25',
        positionUpdatedAt: 5000,
        progress: 0.3,
      ));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/collections/sync_reading_positions/records') {
          return http.Response(
            jsonEncode({'items': [], 'page': 1, 'perPage': 1, 'totalItems': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // 批次推送一律失敗。
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

      final bookRows = await libraryRepository.database
          .query('books', where: 'id = ?', whereArgs: ['b25']);
      expect(bookRows.single['position_synced_server_updated_at'], isNull);
      expect(await metadataRepository.loadLastPushCompletedAt(), isNull);
    });
  });
```

- [ ] **Step 5：執行測試，確認因閱讀位置同步尚未實作而失敗**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：FAIL——新增的 6 個閱讀位置同步測試失敗（`runCheckpoint()` 目前完全不處理閱讀位置）。

- [ ] **Step 6：擴充 `sync_engine.dart`——閱讀位置衝突預檢＋推送**

`sync_engine.dart` 檔案開頭的 import 區塊新增：

```dart
import 'sync_reading_position.dart';
```

`SyncEngine` 類別欄位與建構子改為：

```dart
class SyncEngine {
  final Database _db;
  final SyncAccountRepository _accountRepository;
  final SyncMetadataRepository _metadataRepository;
  final PocketBaseClientFactory _clientFactory;
  final ReadingPositionConflictResolver? _onReadingPositionConflict;

  SyncEngine({
    required Database db,
    required SyncAccountRepository accountRepository,
    required SyncMetadataRepository metadataRepository,
    PocketBaseClientFactory? clientFactory,
    ReadingPositionConflictResolver? onReadingPositionConflict,
  })  : _db = db,
        _accountRepository = accountRepository,
        _metadataRepository = metadataRepository,
        _clientFactory = clientFactory ?? PocketBase.new,
        _onReadingPositionConflict = onReadingPositionConflict;
```

`runCheckpoint()` 方法整個改為：

```dart
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

    Map<String, String> positionsToConfirm;
    try {
      // epic-8-sync Issue 5：閱讀位置衝突預檢＋推送，須在其餘標註推送之前
      // 完成（spec.md「同步引擎」步驟 1），仍在同一個 try 區塊內——任一
      // 環節的網路例外都應讓整個 checkpoint 視為失敗（見 plan-issue-5.md
      // 「與 spec.md 的落差說明」第 1 點：獨立的 Batch 請求，非與標註
      // 異動合併成同一個實體 HTTP 請求）。
      positionsToConfirm =
          await _syncReadingPositions(pb, headers, lastPushCompletedAt, userId);

      for (final batch in planPushBatches(allOperations)) {
        await _sendPushBatch(pb, headers, batch);
      }
    } on ClientException {
      return;
    }

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
      return;
    }

    await _metadataRepository.saveLastPushCompletedAt(notDirtyUpdatedAt);
    for (final entry in pulledCursors.entries) {
      final cursor = entry.value;
      if (cursor != null) {
        await _metadataRepository.savePulledCursor(entry.key, cursor);
      }
    }
    // epic-8-sync Issue 5：與 lastPushCompletedAt／下載游標同一時機才
    // 寫入，理由同上——確保推送+下載整個 checkpoint 皆成功後才一次寫
    // 入，維持 Issue 4 已確立的原子性保證（見 plan-issue-4.md「審查修正
    // 紀錄」）。
    for (final entry in positionsToConfirm.entries) {
      await _db.update(
        'books',
        {'position_synced_server_updated_at': entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }

    await _purgeTombstones();
  }
```

在 `_sendPushBatch()` 方法之後新增以下私有類別與方法：

```dart
  /// 一筆待推送的閱讀位置（epic-8-sync Issue 5）。[remoteId] 為 `null`
  /// 代表 PocketBase 目前沒有這本書的既有紀錄，走 create；非 `null` 代表
  /// 已查得既有紀錄的 PocketBase 內部 id，走 update。
  Future<Map<String, String>> _syncReadingPositions(
    PocketBase pb,
    Map<String, String> headers,
    int? lastPushCompletedAt,
    String userId,
  ) async {
    final dirtyRows = await _db.query(
      'books',
      columns: [
        'id',
        'title',
        'format',
        'content_fingerprint',
        'epubLocator',
        'pdfPageIndex',
        'progress',
        'position_updated_at',
        'position_synced_server_updated_at',
      ],
      where: 'position_updated_at > ?',
      whereArgs: [lastPushCompletedAt ?? 0],
    );
    if (dirtyRows.isEmpty) return {};

    final toPush = <_ReadingPositionPushItem>[];
    for (final row in dirtyRows) {
      final bookId = row['id'] as String;
      var fingerprint = row['content_fingerprint'] as String?;
      fingerprint ??= await _backfillFingerprintForBook(bookId);
      if (fingerprint == null) continue; // 補算失敗：這本書這次跳過，下次 checkpoint 重試

      final format = BookFileFormat.values.byName(row['format'] as String);
      final local = ReadingPositionSnapshot(
        epubLocatorJson: row['epubLocator'] as String?,
        pdfPageIndex: row['pdfPageIndex'] as int?,
        progress: (row['progress'] as num).toDouble(),
      );
      final syncedServerUpdatedAt = row['position_synced_server_updated_at'] as String?;

      final result = await pb.collection('sync_reading_positions').getList(
            filter: 'book_fingerprint = "$fingerprint"',
            perPage: 1,
            headers: headers,
          );
      final existing = result.items.isEmpty ? null : result.items.first;
      final remoteServerUpdated = existing?.data['updated'] as String?;

      final action = resolveReadingPositionAction(
        positionUpdatedAt: row['position_updated_at'] as int?,
        lastPushCompletedAt: lastPushCompletedAt,
        positionSyncedServerUpdatedAt: syncedServerUpdatedAt,
        remoteServerUpdated: remoteServerUpdated,
      );

      switch (action) {
        case ReadingPositionSyncAction.noAction:
          break;
        case ReadingPositionSyncAction.pushLocalDirectly:
          toPush.add(_ReadingPositionPushItem(
            bookId: bookId,
            fingerprint: fingerprint,
            remoteId: existing?.data['id'] as String?,
            local: local,
          ));
          break;
        case ReadingPositionSyncAction.needsUserDecision:
          final resolver = _onReadingPositionConflict;
          if (resolver == null) break; // 無可用 UI（例如背景觸發）：本輪跳過，下次重試
          final remote = ReadingPositionSnapshot(
            epubLocatorJson: existing!.data['epub_locator'] as String?,
            pdfPageIndex: (existing.data['pdf_page_index'] as num?)?.toInt(),
            progress: (existing.data['progress'] as num).toDouble(),
          );
          final choice = await resolver(ReadingPositionConflict(
            bookId: bookId,
            bookTitle: row['title'] as String,
            format: format,
            local: local,
            remote: remote,
          ));
          if (choice == ReadingPositionChoice.keepLocal) {
            toPush.add(_ReadingPositionPushItem(
              bookId: bookId,
              fingerprint: fingerprint,
              remoteId: existing.data['id'] as String?,
              local: local,
            ));
          } else if (choice == ReadingPositionChoice.keepCloud) {
            // 使用者已明確決定採用雲端版本：立即覆寫本機（比照 Issue 4
            // 下載合併寫入既有慣例——這是已確定的資料寫入，非游標
            // bookkeeping，不需要延後到 checkpoint 結束，見
            // plan-issue-4.md「審查修正紀錄」對兩者的區分）；
            // position_updated_at 設為不大於 lastPushCompletedAt 的值，
            // 避免下次 checkpoint 又被誤判為待推送的本機異動。
            await _db.update(
              'books',
              {
                'epubLocator': remote.epubLocatorJson,
                'pdfPageIndex': remote.pdfPageIndex,
                'progress': remote.progress,
                'position_updated_at': lastPushCompletedAt ?? 0,
                'position_synced_server_updated_at': remoteServerUpdated,
              },
              where: 'id = ?',
              whereArgs: [bookId],
            );
          }
          // choice 為 null（使用者關閉對話框未決定）：本輪跳過，下次重試。
          break;
      }
    }

    if (toPush.isEmpty) return {};

    final request = pb.createBatch();
    for (final item in toPush) {
      final body = <String, Object?>{
        'user': userId,
        'book_fingerprint': item.fingerprint,
        'epub_locator': item.local.epubLocatorJson,
        'pdf_page_index': item.local.pdfPageIndex,
        'progress': item.local.progress,
      };
      if (item.remoteId == null) {
        request.collection('sync_reading_positions').create(body: body);
      } else {
        request.collection('sync_reading_positions').update(item.remoteId!, body: body);
      }
    }
    final results = await request.send(headers: headers);

    final positionsToConfirm = <String, String>{};
    for (var i = 0; i < toPush.length; i++) {
      final body = results[i].body;
      if (body is Map) {
        final updated = body['updated'] as String?;
        if (updated != null) {
          positionsToConfirm[toPush[i].bookId] = updated;
        }
      }
    }
    return positionsToConfirm;
  }
```

在整個 `sync_engine.dart` 檔案的最後——也就是 `class SyncEngine { ... }` 的收尾 `}` **之後**（Dart 不支援巢狀 class 定義，這個小型資料類別必須是頂層宣告，與 `SyncEngine` 平行，不是寫在它內部）——新增：

```dart
class _ReadingPositionPushItem {
  final String bookId;
  final String fingerprint;
  final String? remoteId;
  final ReadingPositionSnapshot local;

  const _ReadingPositionPushItem({
    required this.bookId,
    required this.fingerprint,
    required this.remoteId,
    required this.local,
  });
}
```

- [ ] **Step 7：執行測試，確認全數通過**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：PASS（Issue 4 既有測試＋本 Task 新增 6 則，全數通過）。

- [ ] **Step 8：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（確認無 regression）。

```bash
git add lib/sync/sync_engine.dart test/sync/sync_engine_test.dart
git commit -m "feat(epic-8-sync): Issue 5 Task 5 — SyncEngine 閱讀位置衝突預檢與推送"
```

---

### Task 6：`integration_test`——雙裝置閱讀位置衝突真機驗證

**Files:**
- Modify：`app/integration_test/sync_engine_test.dart`

**Interfaces:**
- Consumes：Task 5 的 `SyncEngine`（`onReadingPositionConflict` 參數）；Issue 7 已架好的測試用 PocketBase 實例（`http://pbdev.jigong.org`）。

**注意**：比照 Issue 4 `integration_test/sync_engine_test.dart` 既有慣例，執行前裝置需先連上 Tailscale；使用同一個測試帳號 `epic8-issue2-test@example.com`；測試開頭／結尾清空該帳號在 `sync_reading_positions` collection 下的紀錄。

- [ ] **Step 1：撰寫真機測試**

`app/integration_test/sync_engine_test.dart` 檔案開頭的 import 區塊新增：

```dart
import 'package:elinkbook/sync/sync_reading_position.dart';
```

`clearRemoteData()` 輔助函式的 `testCollections` 清單改為包含閱讀位置：

```dart
  const testCollections = [
    'sync_bookmarks',
    'sync_highlights',
    'sync_notes',
    'sync_reading_positions',
  ];
```

在既有 `testWidgets(...)` 測試之後、檔案結尾 `}` 之前新增：

```dart

  testWidgets(
      '雙裝置閱讀位置衝突：裝置 A 推送位置後，裝置 B 也異動同一本書位置並嘗試推送，'
      '正確觸發衝突回呼且不靜默覆蓋任一邊', (tester) async {
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

    final sharedFingerprint =
        'integration-test-position-fingerprint-${DateTime.now().microsecondsSinceEpoch}';

    // 裝置 A：開這本書、讀到第 10 頁，checkpoint 推送。
    final deviceA = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceA.close());
    final bookA = Book(
      id: 'book-position-a',
      title: '雙裝置位置測試書',
      format: BookFileFormat.pdf,
      filePath: 'content://example/book-position-a',
      source: BookSource.local,
      contentFingerprint: sharedFingerprint,
      pdfPageIndex: 9,
      progress: 0.3,
      positionUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceA.insertBook(bookA);
    final engineA = SyncEngine(
      db: deviceA.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceA.database),
    );
    await engineA.runCheckpoint();

    final remoteAfterA = await pb.collection('sync_reading_positions').getList(
          filter: 'book_fingerprint = "$sharedFingerprint"',
          perPage: 1,
        );
    expect(remoteAfterA.items, hasLength(1));
    expect((remoteAfterA.items.single.data['pdf_page_index'] as num).toInt(), 9);

    // 裝置 B：獨立的本機資料庫，同一本書（相同指紋），但本機從未同步過
    // 這本書的位置（position_synced_server_updated_at 為 null）——先讀到
    // 第 20 頁、本機異動待推送，checkpoint 時應偵測到衝突（遠端已有裝置
    // A 剛推送的紀錄，本機快取為 null，依 resolveReadingPositionAction()
    // 的定義視為衝突，見 plan-issue-5.md Task 3）。
    final deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceB.close());
    final bookB = Book(
      id: 'book-position-b',
      title: '雙裝置位置測試書',
      format: BookFileFormat.pdf,
      filePath: 'content://example/book-position-b',
      source: BookSource.local,
      contentFingerprint: sharedFingerprint,
      pdfPageIndex: 19,
      progress: 0.6,
      positionUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceB.insertBook(bookB);

    ReadingPositionConflict? capturedConflict;
    final engineB = SyncEngine(
      db: deviceB.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceB.database),
      onReadingPositionConflict: (conflict) async {
        capturedConflict = conflict;
        return ReadingPositionChoice.keepLocal;
      },
    );
    await engineB.runCheckpoint();

    expect(capturedConflict, isNotNull, reason: '應正確偵測到衝突並觸發回呼');
    expect(capturedConflict!.local.pdfPageIndex, 19);
    expect(capturedConflict!.remote.pdfPageIndex, 9);

    // 裝置 B 選擇保留本機，雲端最終應是裝置 B 的版本（第 20 頁）。
    final remoteAfterB = await pb.collection('sync_reading_positions').getList(
          filter: 'book_fingerprint = "$sharedFingerprint"',
          perPage: 1,
        );
    expect((remoteAfterB.items.single.data['pdf_page_index'] as num).toInt(), 19);

    await client.logout();
  });
```

- [ ] **Step 2：確認裝置已連上 Tailscale，於真實裝置/模擬器上執行**

Run：

```bash
flutter devices
flutter test integration_test/sync_engine_test.dart -d <device-id>
```

Expected：PASS（Issue 4 既有整合測試＋本 Task 新增的雙裝置衝突測試皆通過）——代表閱讀位置衝突偵測、回呼觸發、使用者選擇後的推送流程在真實網路環境下皆行為正確。

- [ ] **Step 3：Commit**

```bash
git add integration_test/sync_engine_test.dart
git commit -m "test(epic-8-sync): Issue 5 Task 6 — 雙裝置閱讀位置衝突真機驗證"
```

---

## Self-Review Notes

- **issues.md 驗收標準覆蓋檢查**：「閱讀位置衝突偵測正確（僅雙方皆變動過才視為衝突）」→ Task 3（`resolveReadingPositionAction` 7 則測試涵蓋不 dirty／無遠端紀錄／時間戳記相同／不同／快取為 null 但遠端有紀錄／從未推送過等情境）。「偵測到衝突時彈窗詢問使用者，使用者選擇前不靜默覆蓋任一邊」→ Task 4（對話框回傳 `null`／`keepLocal`／`keepCloud` 三態）＋ Task 5（`_syncReadingPositions` 對 `null` 回呼／`null` 選擇皆為「跳過、不覆蓋」）。「無衝突時直接套用變動的一邊」→ Task 5「本機閱讀位置有異動、遠端無既有紀錄時，直接推送」測試。「`position_synced_server_updated_at` 正確維護」→ Task 5 全部 6 則測試皆有對應斷言（含推送失敗時不寫入的原子性驗證）。「上述測試皆通過，`flutter analyze` 乾淨」→ 每個 Task 結尾皆有驗證步驟。
- **與 spec.md 的一致性檢查**：「僅當本機 position_updated_at > lastPushCompletedAt 才執行」→ Task 5 `_syncReadingPositions()` 的 SQL `WHERE position_updated_at > ?`，並有「本機無待推送異動時完全不查詢」的專門測試。「於推送步驟之前」→ Task 5 `runCheckpoint()` 內 `_syncReadingPositions()` 呼叫順序在標註推送迴圈之前。「使用者選擇前不納入本次推送批次」→ 衝突分支只有 `choice == keepLocal` 才會被加進 `toPush`。「推送成功後用 Batch API 回應中該筆紀錄的 updated 值回填」→ `positionsToConfirm` 的 `body['updated']` 解析，且延後到 checkpoint 全部成功後才實際寫入（沿用 Issue 4 已確立的原子性原則，而非 spec.md 字面上「推送成功後」的較早時機——與 Issue 4 對 `lastPushCompletedAt` 的處理同一邏輯，理由已在 plan-issue-4.md 說明過，此處不重複）。
- **型別一致性檢查**：`ReadingPositionConflictResolver`（Task 3 定義：`Future<ReadingPositionChoice?> Function(ReadingPositionConflict conflict)`）→ Task 4 `showReadingPositionConflictDialog()` 簽章完全符合（可直接當作這個 typedef 的實例使用，供 Issue 6 之後串接）；Task 5 `SyncEngine` 建構子 `onReadingPositionConflict` 參數型別一致。`ReadingPositionSnapshot`（Task 3 定義）→ Task 4／Task 5 建構時欄位名稱一致。
- **與既有慣例的差異說明彙總**（呼應文件開頭「與 spec.md 的落差說明」）：(1) 閱讀位置推送改用獨立的 Batch 請求，不與標註異動合併成同一個實體 HTTP 請求；(2) 不新增類似 `sync_remote_ids` 的對照表，每次即時查詢；(3) `sync_metadata.last_pulled_server_updated_at_reading_positions` 維持不使用（spec.md 本身已明確排除）。以上皆非範圍蔓延，是查證 `sync_reading_positions` 實際 PocketBase schema（無 `client_id`／`deleted_at`）後的必要修正，比照 `plan-issue-3.md`／`plan-issue-4.md` 先例的誠實記錄慣例。
- **本 Issue 刻意不做的事**（呼應 Global Constraints）：不新增 SQL migration（欄位已存在）；不修改 `copyWith()`（YAGNI，比照 `contentFingerprint` 先例）；不把 `SyncEngine`／`showReadingPositionConflictDialog` 實際接進 `main.dart`／`ReaderScreen`（留給 Issue 6，兩者依賴圖上互不依賴）。
- **Placeholder 掃描**：全文無 TBD/TODO；Task 5 Step 6 因程式碼分散在 `runCheckpoint()` 改寫與新增的 `_syncReadingPositions()`/`_ReadingPositionPushItem`，已列出全部異動的完整程式碼（非「比照 Task N」的省略寫法），並明確標註 `_ReadingPositionPushItem` 為頂層類別、實際插入位置在檔案最底部（`class SyncEngine { ... }` 之後），非巢狀類別。
