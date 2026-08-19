# Epic 29 Issue 0：擴充既有匯入/查詢管線（Prefactor）實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 在不影響任何既有呼叫端行為的前提下，為 `books` 表新增 `cloud_file_id` 欄位、為 `LibraryRepository` 新增 `findByCloudFileId()` 查詢方法、為 `BookImportService.importFiles()` 擴充 `cloudFileIds` 參數——三者皆是後續 Issue 3（Google Drive 瀏覽＋匯入）、Issue 4（OneDrive）、Issue 5（重複匯入偵測）共用的資料層基礎設施。

**Architecture：** 完全比照 `epic-30-calibre-remote-library` Issue 0 已驗證過的既有落地模式（`remote_server_id`／`remote_book_id`／`remote_download_url`／`is_downloaded` 四個欄位＋`findByRemoteBookId()`／`listUndownloadedBooksForRemoteServer()` 兩個查詢方法＋`importFiles()` 的 `remoteServerId`／`remoteBookIds`／`remoteDownloadUrls` 可選參數）——本 Issue 是同一套「擴充既有介面、不新增平行路徑」手法的第二次套用，只是服務對象換成 Google Drive／OneDrive 這類「雲端匯入來源帳號」（一次性搬入本機圖書庫），語意上與「遠端書庫」（Calibre／OPDS，書籍持續留在遠端、可重新下載）完全獨立，因此是全新欄位／方法，不與既有 `remote_*` 欄位合併。

**Tech Stack：** Flutter／Dart、`sqflite`（`sqflite_common_ffi` 供測試用記憶體內資料庫）。

**Spec：** `docs/epics/epic-29-cloud-import/spec.md`（Architecting 階段產出，本 Issue 對應「資料模型與 Schema」「既有匯入管線擴充」兩節，已通過 `reviews/review-spec.md` 審查修訂）。

## Global Constraints

- `findByContentFingerprint(String fingerprint)` 已存在（`epic-30-calibre-remote-library` Issue 0 建置），本計劃**不重複實作**，僅重複使用。
- `BookImportService.importFiles()` 目前簽章已含 `source`／`remoteServerId`／`remoteBookIds`／`remoteDownloadUrls`（`epic-30` 建置）——本計劃只新增 `cloudFileIds` 一個參數，**既有呼叫端（本機匯入與 Calibre／OPDS 匯入）完全不需要修改**，零回歸風險。
- `cloud_file_id` 欄位與 `remote_server_id`／`remote_book_id`／`remote_download_url`／`is_downloaded` 是概念上完全獨立的兩組欄位，不合併、不共用查詢方法（見 `CONTEXT.md`「雲端匯入來源帳號」／「遠端書庫」的既定區分）。
- `cloud_file_id` 不需要額外的 `cloud_provider` 欄位——`books.source`（既有 `BookSource` enum）已經區分 `googleDrive`／`oneDrive`，`findByCloudFileId()` 以 `(BookSource provider, String cloudFileId)` 複合鍵查詢。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`Book` 模型新增 `cloudFileId` 欄位

**Files：**
- Modify: `app/lib/library/models/book.dart`
- Modify: `app/test/support/fake_library_repository.dart`（`_withGroupName` 必須原樣帶入新欄位，否則 `renameGroup`／`deleteGroup` 會靜默清空它——`positionUpdatedAt`／`remoteServerId` 等既有欄位皆已踩過這個坑，見該檔案 `copyWith`／`_withGroupName` 既有註解）
- Test: `app/test/library/models/book_test.dart`
- Test: `app/test/support/fake_library_repository_test.dart`

**Interfaces：**
- Produces：`Book.cloudFileId`（`String?`，新欄位）供 Task 3（`findByCloudFileId()` 查詢）、Task 4（`importFiles()` 落地）使用。

- [ ] **Step 1：在 `book_test.dart` 寫入失敗的往返測試**

在 `app/test/library/models/book_test.dart` 檔案末尾（`}` 之前）新增：

```dart
  test('cloudFileId 欄位可正確往返（epic-29-cloud-import Issue 0）', () {
    final book = Book(
      id: 'b20',
      title: '雲端匯入的書',
      format: BookFileFormat.epub,
      filePath: '/storage/imported_books/b20.epub',
      source: BookSource.googleDrive,
      cloudFileId: 'gdrive-file-abc123',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.cloudFileId, 'gdrive-file-abc123');
  });

  test('cloudFileId 未設定時，往返後仍為 null（代表非雲端匯入）', () {
    final book = Book(
      id: 'b21',
      title: '本機書',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.cloudFileId, isNull);
  });

  test('copyWith 保留 cloudFileId（欄位未開放為具名參數，但不可被 copyWith 清空）', () {
    final book = Book(
      id: 'b22',
      title: '雲端匯入的書',
      format: BookFileFormat.epub,
      filePath: '/storage/imported_books/b22.epub',
      source: BookSource.oneDrive,
      cloudFileId: 'onedrive-file-xyz789',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final copied = book.copyWith(groupName: '新分類');

    expect(copied.cloudFileId, 'onedrive-file-xyz789');
    expect(copied.groupName, '新分類');
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/library/models/book_test.dart`
預期：編譯失敗（`Book` 建構子沒有 `cloudFileId` 具名參數）。

- [ ] **Step 3：修改 `Book` 模型加入 `cloudFileId` 欄位**

在 `app/lib/library/models/book.dart` 找到以下區塊（`isDownloaded` 欄位宣告與其後的 `groupName` 之間）：

```dart
  /// 本地檔案是否已下載就緒（預設 `true`；遠端僅有詮釋資料尚未下載時為 `false`）。
  final bool isDownloaded;

  final String groupName;
```

改為：

```dart
  /// 本地檔案是否已下載就緒（預設 `true`；遠端僅有詮釋資料尚未下載時為 `false`）。
  final bool isDownloaded;

  /// 雲端匯入來源（Google Drive／OneDrive）的原始檔案 ID（epic-29-cloud-import
  /// Issue 0，spec.md「資料模型與 Schema」）：在 [source] 範圍內唯一，供選檔
  /// 前置重複偵測查詢使用（見 `LibraryRepository.findByCloudFileId`）。與
  /// [remoteBookId] 是概念上完全獨立的兩個欄位——[remoteBookId] 對應
  /// `CONTEXT.md`「遠端書庫」（Calibre／OPDS，書籍持續留在遠端伺服器、可
  /// 重新下載），本欄位對應 `CONTEXT.md`「雲端匯入來源帳號」（Google
  /// Drive／OneDrive，一次性搬入本機圖書庫、匯入後即與雲端來源無持續
  /// 關聯）。`null` 代表非雲端匯入或本機/其他來源匯入。
  final String? cloudFileId;

  final String groupName;
```

再找到建構子（`this.isDownloaded = true,` 與 `this.groupName = BookGroup.uncategorized,` 之間）：

```dart
    this.isDownloaded = true,
    this.groupName = BookGroup.uncategorized,
```

改為：

```dart
    this.isDownloaded = true,
    this.cloudFileId,
    this.groupName = BookGroup.uncategorized,
```

再找到 `toMap()` 內：

```dart
      'is_downloaded': isDownloaded ? 1 : 0,
      'groupName': groupName,
```

改為：

```dart
      'is_downloaded': isDownloaded ? 1 : 0,
      'cloud_file_id': cloudFileId,
      'groupName': groupName,
```

再找到 `fromMap()` 內：

```dart
      isDownloaded: (map['is_downloaded'] as int) == 1,
      groupName: map['groupName'] as String,
```

改為：

```dart
      isDownloaded: (map['is_downloaded'] as int) == 1,
      cloudFileId: map['cloud_file_id'] as String?,
      groupName: map['groupName'] as String,
```

再找到 `copyWith()` 的文件註解（`⚠️` 開頭那段）：

```dart
  /// **⚠️ `remoteServerId`／`remoteBookId`／`remoteDownloadUrl` 仍不開放
  /// 為具名參數（本 Issue的兩個流程皆不需要異動這三者），但必須原樣帶入
  /// 新物件以避免靜默清空**。
```

改為：

```dart
  /// **⚠️ `remoteServerId`／`remoteBookId`／`remoteDownloadUrl`／
  /// `cloudFileId` 仍不開放為具名參數（目前沒有呼叫端需要異動這幾個
  /// 欄位），但必須原樣帶入新物件以避免靜默清空**。
```

再找到 `copyWith()` 方法本體內，`remoteDownloadUrl: remoteDownloadUrl,` 那一行：

```dart
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
```

改為：

```dart
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      cloudFileId: cloudFileId,
```

再找到 `operator ==` 內：

```dart
          isDownloaded == other.isDownloaded &&
          groupName == other.groupName &&
```

改為：

```dart
          isDownloaded == other.isDownloaded &&
          cloudFileId == other.cloudFileId &&
          groupName == other.groupName &&
```

最後找到 `hashCode` 內：

```dart
        isDownloaded,
        groupName,
```

改為：

```dart
        isDownloaded,
        cloudFileId,
        groupName,
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/library/models/book_test.dart`
預期：全數 PASS。

- [ ] **Step 5：在 `fake_library_repository_test.dart` 補上 `cloudFileId` 保留斷言**

在 `app/test/support/fake_library_repository_test.dart` 找到 `'FakeLibraryRepository._withGroupName 保留所有新欄位'` 這個 group 內的測試，`insertBook` 的 `Book(...)` 建構子呼叫中，`remoteDownloadUrl: 'http://example.com/1.epub',` 那一行之後新增：

```dart
        cloudFileId: 'gdrive-file-1',
```

同一個測試內，`expect(book.remoteDownloadUrl, 'http://example.com/1.epub');` 那一行之後新增：

```dart
      expect(book.cloudFileId, 'gdrive-file-1');
```

- [ ] **Step 6：執行測試確認失敗（`_withGroupName` 尚未帶入 `cloudFileId`）**

執行：`flutter test test/support/fake_library_repository_test.dart`
預期：新增的 `expect(book.cloudFileId, 'gdrive-file-1');` FAIL（實際值為 `null`）。

- [ ] **Step 7：修改 `FakeLibraryRepository._withGroupName` 帶入 `cloudFileId`**

在 `app/test/support/fake_library_repository.dart` 找到 `_withGroupName` 方法內：

```dart
        remoteDownloadUrl: book.remoteDownloadUrl,
        isDownloaded: book.isDownloaded,
        groupName: groupName,
```

改為：

```dart
        remoteDownloadUrl: book.remoteDownloadUrl,
        isDownloaded: book.isDownloaded,
        cloudFileId: book.cloudFileId,
        groupName: groupName,
```

- [ ] **Step 8：執行測試確認通過**

執行：`flutter test test/support/fake_library_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 9：Commit**

```bash
git add app/lib/library/models/book.dart app/test/library/models/book_test.dart app/test/support/fake_library_repository.dart app/test/support/fake_library_repository_test.dart
git commit -m "feat(epic-29): Issue 0——Book 模型新增 cloudFileId 欄位"
```

---

## Task 2：SQLite Schema Migration（`cloud_file_id` 欄位＋索引，version 22 → 23）

**Files：**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `Book.cloudFileId`。
- Produces：`books` 表 `cloud_file_id TEXT` 欄位＋`idx_books_cloud_file_id` 索引；額外補上先前一直缺漏的 `idx_books_content_fingerprint` 索引（spec.md 審查 Important #3：`content_fingerprint` 欄位自 `epic-8-sync` Issue 3 引入以來從未建過索引，雲端匯入的下載後指紋比對／既有同步引擎指紋比對皆是高頻查詢，藉這次 migration 一併補上）。供 Task 3 的 `findByCloudFileId()` 使用。

- [ ] **Step 1：在 `sqlite_library_repository_test.dart` 寫入失敗的 migration 測試**

在 `app/test/library/sqlite_library_repository_test.dart` 找到 `'既有 version 21 裝置升級到 version 22，新增 remote_servers 表與 books 新欄位'` 這個測試所在的位置，在該測試所屬的整個 `test(...)` 區塊之後（下一個 `test('既有 version 21 裝置升級到 version 22 後...` 之前的空行處）插入以下新測試：

```dart
  test('既有 version 22 裝置升級到 version 23，新增 books.cloud_file_id 欄位與索引',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v22_to_v23_cloud_import_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 22,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
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
              remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
              remote_book_id TEXT,
              remote_download_url TEXT,
              is_downloaded INTEGER NOT NULL DEFAULT 1
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

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=22 →
    // newVersion=23）。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final rows = await upgraded.database.query('books');
    expect(rows, hasLength(1));
    expect(rows.single['cloud_file_id'], isNull);

    // cloud_file_id 欄位可正常寫入與查詢。
    await upgraded.database.update(
      'books',
      {'cloud_file_id': 'gdrive-file-1'},
      where: 'id = ?',
      whereArgs: ['book1'],
    );
    final updated = await upgraded.database
        .query('books', where: 'id = ?', whereArgs: ['book1']);
    expect(updated.single['cloud_file_id'], 'gdrive-file-1');

    // 兩個索引皆已建立（idx_books_cloud_file_id 為本次新增；
    // idx_books_content_fingerprint 為藉本次 migration 補上的既有缺漏）。
    final indexNames = await upgraded.database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'index' AND name IN (?, ?)",
      whereArgs: ['idx_books_cloud_file_id', 'idx_books_content_fingerprint'],
    );
    expect(
      indexNames.map((r) => r['name']).toSet(),
      {'idx_books_cloud_file_id', 'idx_books_content_fingerprint'},
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/library/sqlite_library_repository_test.dart --plain-name "既有 version 22 裝置升級到 version 23"`
預期：FAIL（`cloud_file_id` 欄位不存在，或版本號未變動導致 `onUpgrade` 未觸發）。

- [ ] **Step 3：修改 `SqliteLibraryRepository` 加入 migration**

在 `app/lib/library/sqlite_library_repository.dart` 找到：

```dart
    final db = await openDatabase(
      path,
      version: 22,
```

改為：

```dart
    final db = await openDatabase(
      path,
      version: 23,
```

找到 `onCreate` 內的 `books` 表定義：

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
            position_synced_server_updated_at TEXT,
            remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
            remote_book_id TEXT,
            remote_download_url TEXT,
            is_downloaded INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
```

改為：

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
            position_synced_server_updated_at TEXT,
            remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
            remote_book_id TEXT,
            remote_download_url TEXT,
            is_downloaded INTEGER NOT NULL DEFAULT 1,
            cloud_file_id TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
        await db.execute(
            'CREATE INDEX idx_books_content_fingerprint ON books(content_fingerprint)');
        await db.execute(
            'CREATE INDEX idx_books_cloud_file_id ON books(cloud_file_id)');
```

找到 `onUpgrade` 內 `if (oldVersion < 22) { ... }` 區塊的結尾（緊接在 `'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');` 那行與其後的 `}` 之間），在該區塊的 `}` 之後新增：

```dart
        if (oldVersion < 23) {
          // epic-29-cloud-import Issue 0：雲端匯入（Google Drive／OneDrive）
          // 選檔前置重複偵測所需的 books 表新增欄位，見 spec.md「資料模型與
          // Schema」。cloud_file_id 為 nullable，既有資料升級後自動為
          // NULL，不影響既有資料。同一次 migration 一併補上
          // content_fingerprint 的索引——經核對此欄位自 epic-8-sync Issue 3
          // 引入以來從未建過索引，雲端匯入的下載後指紋比對（Issue 5）與
          // 既有同步引擎的指紋比對皆是高頻查詢，值得藉這次 migration 一併
          // 補上，避免書籍量大時全表掃描（spec.md 審查 Important #3）。
          await db.execute('ALTER TABLE books ADD COLUMN cloud_file_id TEXT');
          await db.execute(
              'CREATE INDEX idx_books_cloud_file_id ON books(cloud_file_id)');
          await db.execute(
              'CREATE INDEX idx_books_content_fingerprint ON books(content_fingerprint)');
        }
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS（含既有的 version 21→22 系列測試，零回歸）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-29): Issue 0——books 表新增 cloud_file_id 欄位與索引（schema v22→v23）"
```

---

## Task 3：`LibraryRepository.findByCloudFileId()`

**Files：**
- Modify: `app/lib/library/library_repository.dart`（介面）
- Modify: `app/lib/library/sqlite_library_repository.dart`（實作）
- Modify: `app/test/support/fake_library_repository.dart`（假實作）
- Test: `app/test/library/sqlite_library_repository_test.dart`
- Test: `app/test/support/fake_library_repository_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `Book.cloudFileId`，Task 2 的 `cloud_file_id` 欄位／索引。
- Produces：`LibraryRepository.findByCloudFileId(BookSource provider, String cloudFileId) → Future<Book?>`，供後續 Issue 3／Issue 5 的選檔前置重複偵測使用。

- [ ] **Step 1：在 `sqlite_library_repository_test.dart` 寫入失敗的測試**

在該檔案的 `group('findByContentFingerprint', ...)` 區塊之後（`group('listUndownloadedBooksForRemoteServer', ...)` 之前）插入：

```dart
  group('findByCloudFileId', () {
    test('命中：回傳對應書籍', () async {
      final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => repo.close());

      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found =
          await repo.findByCloudFileId(BookSource.googleDrive, 'gdrive-file-1');
      expect(found?.id, 'book1');
    });

    test('未命中：不同 provider 或不同 cloudFileId 皆回傳 null', () async {
      final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => repo.close());

      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      // 同一個 cloudFileId 字串值出現在另一個 provider 底下不算命中——
      // cloud_file_id 只在 source 範圍內唯一（spec.md「資料模型與
      // Schema」），不是全域唯一。
      expect(
        await repo.findByCloudFileId(BookSource.oneDrive, 'gdrive-file-1'),
        isNull,
      );
      expect(
        await repo.findByCloudFileId(BookSource.googleDrive, 'other-file'),
        isNull,
      );
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/library/sqlite_library_repository_test.dart --plain-name findByCloudFileId`
預期：編譯失敗（`findByCloudFileId` 尚未定義）。

- [ ] **Step 3：在 `LibraryRepository` 介面新增方法**

在 `app/lib/library/library_repository.dart` 找到：

```dart
  /// 依 `content_fingerprint` 精確比對，供雲端/遠端書架匯入的下載後重複
  /// 匯入偵測使用（`epic-29-cloud-import`／`epic-30-calibre-remote-library`
  /// 共用，見 `CONTEXT.md`「書籍內容指紋」）。命中回傳該本書，未命中回傳
  /// `null`。
  Future<Book?> findByContentFingerprint(String fingerprint);
```

在其後新增：

```dart

  /// 依 `(source, cloud_file_id)` 精確比對，供雲端匯入（Google Drive／
  /// OneDrive）選檔前置重複偵測使用（`epic-29-cloud-import` Issue 0，
  /// spec.md「重複匯入偵測」）。`cloud_file_id` 只在 [provider] 範圍內
  /// 唯一，故必須合併比對兩者，不能只比對 `cloud_file_id`。命中回傳該本
  /// 書，未命中回傳 `null`。
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId);
```

- [ ] **Step 4：在 `SqliteLibraryRepository` 實作**

在 `app/lib/library/sqlite_library_repository.dart` 找到 `findByContentFingerprint` 方法本體結尾：

```dart
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

在其後新增：

```dart

  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    final rows = await _db.query(
      'books',
      where: 'source = ? AND cloud_file_id = ?',
      whereArgs: [provider.name, cloudFileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }
```

- [ ] **Step 5：執行測試確認通過**

執行：`flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS（`FakeLibraryRepository` 尚未實作，`fake_library_repository_test.dart` 的新測試會在下一步才加入，此處先只驗證 Sqlite 實作）。

- [ ] **Step 6：在 `fake_library_repository_test.dart` 寫入失敗的測試**

在該檔案的 `group('FakeLibraryRepository.findByContentFingerprint', ...)` 區塊之後（`group('FakeLibraryRepository._withGroupName 保留所有新欄位', ...)` 之前）插入：

```dart
  group('FakeLibraryRepository.findByCloudFileId', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found =
          await repo.findByCloudFileId(BookSource.googleDrive, 'gdrive-file-1');
      expect(found?.id, 'book1');
    });

    test('未命中：不同 provider 或不同 cloudFileId 皆回傳 null', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      expect(
        await repo.findByCloudFileId(BookSource.oneDrive, 'gdrive-file-1'),
        isNull,
      );
      expect(
        await repo.findByCloudFileId(BookSource.googleDrive, 'other-file'),
        isNull,
      );
    });
  });
```

- [ ] **Step 7：執行測試確認失敗**

執行：`flutter test test/support/fake_library_repository_test.dart --plain-name findByCloudFileId`
預期：編譯失敗（`FakeLibraryRepository` 未實作 `findByCloudFileId`，介面不完整）。

- [ ] **Step 8：在 `FakeLibraryRepository` 實作**

在 `app/test/support/fake_library_repository.dart` 找到 `findByContentFingerprint` 方法本體結尾：

```dart
  @override
  Future<Book?> findByContentFingerprint(String fingerprint) async {
    for (final book in _books) {
      if (book.contentFingerprint == fingerprint) return book;
    }
    return null;
  }
```

在其後新增：

```dart

  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    for (final book in _books) {
      if (book.source == provider && book.cloudFileId == cloudFileId) {
        return book;
      }
    }
    return null;
  }
```

- [ ] **Step 9：執行測試確認通過**

執行：`flutter test test/support/fake_library_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 10：執行完整測試套件確認零回歸**

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 11：Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/support/fake_library_repository.dart app/test/library/sqlite_library_repository_test.dart app/test/support/fake_library_repository_test.dart
git commit -m "feat(epic-29): Issue 0——LibraryRepository 新增 findByCloudFileId 查詢方法"
```

---

## Task 4：`BookImportService.importFiles()` 擴充 `cloudFileIds` 參數

**Files：**
- Modify: `app/lib/library/book_import_service.dart`（介面）
- Modify: `app/lib/library/book_import_service_impl.dart`（實作）
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `Book.cloudFileId`。
- Produces：`BookImportService.importFiles(..., {Map<String, String>? cloudFileIds})`，供後續 Issue 3（Google Drive 瀏覽＋匯入）／Issue 4（OneDrive）下載完成後呼叫。

- [ ] **Step 1：在 `book_import_service_test.dart` 寫入失敗的測試**

在該檔案的 `group('遠端書架參數擴充（epic-30）', ...)` 區塊之後（該 group 的結尾 `});` 之後、檔案最終的 `}` 之前）插入新的 group：

```dart

  group('雲端匯入參數擴充（epic-29 Issue 0）', () {
    test('傳入 source/cloudFileIds 時正確落地', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '雲端書'};
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/cloud_book.epub'],
        source: BookSource.googleDrive,
        cloudFileIds: {'content://example/cloud_book.epub': 'gdrive-file-1'},
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.googleDrive);
      expect(book.cloudFileId, 'gdrive-file-1');
    });

    test('未傳入 cloudFileIds 時（既有本機/OPDS 匯入情境），行為與現行完全一致', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '本機書'};
        }
        return null;
      });

      final result =
          await service.importFiles(['content://example/local_book2.epub']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.local);
      expect(book.cloudFileId, isNull);
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/library/book_import_service_test.dart --plain-name "雲端匯入參數擴充"`
預期：編譯失敗（`importFiles` 沒有 `cloudFileIds` 具名參數）。

- [ ] **Step 3：修改 `BookImportService` 介面**

在 `app/lib/library/book_import_service.dart` 找到：

```dart
  /// [source]、[remoteServerId]、[remoteBookIds] 與 [remoteDownloadUrls] 供遠端
  /// 書架（如 Calibre OPDS）下載落地時寫入對應的伺服器與遠端書籍參照資料。
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

改為：

```dart
  /// [source]、[remoteServerId]、[remoteBookIds] 與 [remoteDownloadUrls] 供遠端
  /// 書架（如 Calibre OPDS）下載落地時寫入對應的伺服器與遠端書籍參照資料。
  /// [cloudFileIds]（path 對應雲端原始檔案 ID）供雲端匯入（Google Drive／
  /// OneDrive）下載落地時寫入 [Book.cloudFileId]，與 [remoteBookIds] 是
  /// 概念上完全獨立的參數（見 `CONTEXT.md`「雲端匯入來源帳號」／「遠端
  /// 書庫」的既定區分），可與 [source]／[remoteServerId] 等既有參數並存
  /// 但實務上不會同時使用。
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
    Map<String, String>? cloudFileIds,
  });
```

- [ ] **Step 4：修改 `BookImportServiceImpl.importFiles()` 簽章與呼叫**

在 `app/lib/library/book_import_service_impl.dart` 找到：

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
```

改為：

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
    Map<String, String>? cloudFileIds,
  }) async {
```

同一方法內，找到 `_importSingleFile` 的呼叫：

```dart
      final book = await _importSingleFile(
        uri,
        displayName: displayName,
        folderName: folderName,
        source: source,
        remoteServerId: remoteServerId,
        remoteBookId: remoteBookIds?[uri],
        remoteDownloadUrl: remoteDownloadUrls?[uri],
      );
```

改為：

```dart
      final book = await _importSingleFile(
        uri,
        displayName: displayName,
        folderName: folderName,
        source: source,
        remoteServerId: remoteServerId,
        remoteBookId: remoteBookIds?[uri],
        remoteDownloadUrl: remoteDownloadUrls?[uri],
        cloudFileId: cloudFileIds?[uri],
      );
```

- [ ] **Step 5：修改 `_importSingleFile()` 簽章與 `Book` 建構**

找到：

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

改為：

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
    String? cloudFileId,
  }) async {
```

同一方法內，找到 `Book` 建構子呼叫：

```dart
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
```

改為：

```dart
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
```

- [ ] **Step 6：執行測試確認通過**

執行：`flutter test test/library/book_import_service_test.dart`
預期：全數 PASS（含既有的 `遠端書架參數擴充（epic-30）` 系列測試，零回歸）。

- [ ] **Step 7：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/book_import_service.dart app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-29): Issue 0——BookImportService.importFiles 擴充 cloudFileIds 參數"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `spec.md`「資料模型與 Schema」的 `cloud_file_id` 欄位＋索引 → Task 2 涵蓋。
- `spec.md`「資料模型與 Schema」的 `findByCloudFileId()` → Task 3 涵蓋。
- `spec.md`「資料模型與 Schema」的 `findByContentFingerprint()` → 已由 `epic-30-calibre-remote-library` Issue 0 建置完成，本計劃不重複實作（見 Global Constraints）。
- `spec.md`「既有匯入管線擴充」的 `importFiles()` 新增 `cloudFileIds` 參數 → Task 4 涵蓋。
- `issues.md` Issue 0 單元測試要求逐項對照：migration 測試（Task 2 Step 1）、`importFiles()` 落地與零回歸測試（Task 4 Step 1）、`findByCloudFileId()` 命中/未命中兩層測試（Task 3 Step 1／Step 6）——全數涵蓋。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼區塊，無 "TBD"／"實作細節略"／"比照上方" 等佔位敘述。

**3. 型別一致性檢查：** `cloudFileId`（`String?`）在 `Book`／`FakeLibraryRepository`／`SqliteLibraryRepository`／`LibraryRepository`／`BookImportService`／`BookImportServiceImpl` 六處的型別與具名參數命名全部一致；`findByCloudFileId(BookSource provider, String cloudFileId)` 的參數順序與 `findByRemoteBookId(String serverId, String remoteBookId)` 的既有慣例（先識別 scope、後識別 id）一致。
