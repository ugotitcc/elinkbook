# Epic 30 Issue 1：站點管理與遠端書庫入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者能新增/編輯/刪除多個 Calibre／OPDS 遠端書庫站點（含測試連線、匿名/帳密、自簽憑證/純 HTTP），並從 `LibraryScreen` 有一個獨立常駐入口進去管理。同時交付本 Epic 後續所有切片共用的 `OpdsClient` 完整契約（`testConnection`／`fetchFeed`／`downloadBook`），Issue 2 的目錄瀏覽畫面將直接沿用，不需要再擴充介面。

**Architecture:** 新增 `app/lib/remote/` 模組（比照既有 `app/lib/sync/` 的目錄慣例），內含資料模型、`RemoteServerRepository`（SQLite `remote_servers` 表 + `flutter_secure_storage` 密碼，比照 `LayoutPresetRepository` 共用 `Database` 連線＋`SyncAccountRepository` 密碼安全存取兩者的既有模式合成）、`OpdsClient`（`OpdsFeedParser` 純 Dart 解析＋`OpdsHttpClient` 真實 HTTP 實作）。UI 兩個新畫面放 `app/lib/screens/`（比照 `sync_settings_screen.dart` 的既有慣例）。`books` 表的存取權責邊界（`LibraryRepository` 是「books/groups 兩張表的唯一存取入口」，見 `library_repository.dart:11`）必須維持——`RemoteServerRepository` 的刪除防護邏輯不直接查 `books` 表，而是透過新增的 `LibraryRepository.listUndownloadedBooksForRemoteServer()` 方法。

**Tech Stack:** Flutter/Dart、`sqflite`、`flutter_secure_storage`（既有依賴）、`xml`／`http`（`epic-30` Issue 0 已提升至正式 `dependencies`）、`uuid`（既有依賴，站點 id 產生）。

**Spec:** `docs/epics/epic-30-calibre-remote-library/spec.md`（「站點管理：`RemoteServerRepository`」「OPDS 瀏覽與下載：`OpdsClient`」「UI 落地位置」章節為本計畫的唯一事實來源），另參 `docs/epics/epic-30-calibre-remote-library/design.md`（Discovery 決策）與 `issues.md`（Issue 1 條目）。

## Global Constraints

- `books` 表僅能透過 `LibraryRepository` 存取，`RemoteServerRepository` 不得直接對 `books` 表下 SQL（見上方 Architecture）。
- 自簽憑證放行（`allowInsecure`）**僅能作用於單次連線物件**，不得全域關閉憑證驗證（`spec.md`「OPDS 瀏覽與下載」，`review-design.md` Important #3 已核實的既定原則）。
- 分頁循環防護（已造訪 URL Set）是 **`OpdsClient` 實例層級的狀態**，語意上對應「一次瀏覽路徑」；本 Issue 只用得到 `testConnection()`（單次 `fetchFeed`，不涉及分頁鏈），Issue 2 建構 `RemoteCatalogScreen` 時**必須為每次進入某個站點的瀏覽 session 建構一個全新的 `OpdsHttpClient` 實例**，不可重用 `main.dart` 注入的全域共用實例——否則會把「已造訪過」的判定錯誤地累積到跨 session、跨站點，見 Task 6 程式碼註解。
- 所有新增/修改的程式碼註解使用正體中文，比照既有風格。
- `flutter analyze` 全程保持乾淨；每個 Task 結束時既有測試套件零回歸。
- `LibraryScreen` 新增的建構參數必須為**可選（nullable）**，比照既有 `syncAccountRepository`/`syncClient` 等既有模式——`app/test/screens/library_screen_test.dart` 有 73 處個別建構 `LibraryScreen(...)` 且未使用共用 helper 函式，新增必填參數會導致大量既有測試編譯失敗，不可行。

---

### Task 1: `RemoteServerProfile` 模型

**Files:**
- Create: `app/lib/remote/remote_server_profile.dart`
- Test: `app/test/remote/remote_server_profile_test.dart`

**Interfaces:**
- Produces: `RemoteServerType` enum（`opds`/`calibreServer`/`calibreWeb`）、`RemoteServerProfile` 類別（`id`/`name`/`baseUrl`/`type`/`username`/`allowInsecure`/`createdAt`/`lastAccessedAt`，`toMap()`/`fromMap()`/`==`/`hashCode`）。後續 Task 3（`SqliteRemoteServerRepository`）、Task 6（`OpdsHttpClient`）、Task 7-8（UI）皆依賴這個型別。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

void main() {
  RemoteServerProfile _profile({String? username, DateTime? lastAccessedAt}) {
    return RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: username,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      lastAccessedAt: lastAccessedAt,
    );
  }

  test('toMap()/fromMap() 往返保留全部欄位', () {
    final profile = _profile(
      username: 'admin',
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final restored = RemoteServerProfile.fromMap(profile.toMap());
    expect(restored, profile);
  });

  test('username／lastAccessedAt 皆為 null 時（匿名連線、尚未存取過）toMap()/fromMap() 往返正確', () {
    final profile = _profile();
    final restored = RemoteServerProfile.fromMap(profile.toMap());
    expect(restored.username, isNull);
    expect(restored.lastAccessedAt, isNull);
    expect(restored, profile);
  });

  test('三種 RemoteServerType 皆能正確往返', () {
    for (final type in RemoteServerType.values) {
      final profile = RemoteServerProfile(
        id: 'srv1',
        name: '測試',
        baseUrl: 'http://example.com/opds',
        type: type,
        allowInsecure: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(RemoteServerProfile.fromMap(profile.toMap()).type, type);
    }
  });

  test('allowInsecure=true 時 toMap()/fromMap() 往返正確', () {
    final profile = RemoteServerProfile(
      id: 'srv1',
      name: '自簽憑證站點',
      baseUrl: 'https://192.168.1.100:8443/opds',
      type: RemoteServerType.calibreServer,
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(RemoteServerProfile.fromMap(profile.toMap()).allowInsecure, true);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/remote/remote_server_profile_test.dart`
Expected: FAIL——`app/lib/remote/remote_server_profile.dart` 尚不存在。

- [x] **Step 3: 實作**

```dart
/// Calibre／OPDS 遠端書庫站點型別（epic-30-calibre-remote-library
/// Issue 1，spec.md「站點管理：RemoteServerRepository」）。v1 三種類型
/// 目前無行為差異，`type` 純粹是使用者填寫時的分類標記／UI 顯示用途，
/// 為後續 Calibre 專屬 REST API 加強 Issue 預留擴充位（spec.md
/// 「Further Notes」）。
enum RemoteServerType { opds, calibreServer, calibreWeb }

/// 對應 `remote_servers` 表一列（epic-30-calibre-remote-library Issue 0
/// 已建表）。密碼**不**存放於本類別——獨立存 `flutter_secure_storage`，
/// 由 `RemoteServerRepository` 另外管理（見 spec.md「站點管理」）。
class RemoteServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final RemoteServerType type;

  /// `null` 代表匿名連線（不需要帳密）。
  final String? username;

  /// 是否允許自簽憑證／憑證錯誤（僅作用於單次連線物件，見 Global
  /// Constraints）。
  final bool allowInsecure;

  final DateTime createdAt;

  /// `null` 代表尚未成功瀏覽過這個站點（Issue 1 範圍內恆為 `null`，
  /// Issue 2 建構 `RemoteCatalogScreen` 時才會在瀏覽成功後更新）。
  final DateTime? lastAccessedAt;

  const RemoteServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    this.username,
    required this.allowInsecure,
    required this.createdAt,
    this.lastAccessedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'type': type.name,
      'username': username,
      'allow_insecure': allowInsecure ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_accessed_at': lastAccessedAt?.millisecondsSinceEpoch,
    };
  }

  factory RemoteServerProfile.fromMap(Map<String, Object?> map) {
    return RemoteServerProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      type: RemoteServerType.values.byName(map['type'] as String),
      username: map['username'] as String?,
      allowInsecure: (map['allow_insecure'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastAccessedAt: map['last_accessed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['last_accessed_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteServerProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          baseUrl == other.baseUrl &&
          type == other.type &&
          username == other.username &&
          allowInsecure == other.allowInsecure &&
          createdAt == other.createdAt &&
          lastAccessedAt == other.lastAccessedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        type,
        username,
        allowInsecure,
        createdAt,
        lastAccessedAt,
      );
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/remote/remote_server_profile_test.dart`
Expected: PASS，4 項測試全數通過。

- [x] **Step 5: Commit**

```bash
git add app/lib/remote/remote_server_profile.dart app/test/remote/remote_server_profile_test.dart
git commit -m "feat(epic-30): 新增 RemoteServerProfile 模型"
```

---

### Task 2: `LibraryRepository.listUndownloadedBooksForRemoteServer()`

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Issue 0 的 `books.remote_server_id`／`books.is_downloaded` 欄位。
- Produces: `Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId)`。Task 3 的 `SqliteRemoteServerRepository.deleteServer()` 依賴這個方法維持「不直接查 `books` 表」的邊界（見 Global Constraints）。

- [x] **Step 1: 寫失敗測試**

在 `app/test/library/sqlite_library_repository_test.dart` 新增（放在既有 `findByRemoteBookId`/`findByContentFingerprint` 兩個 `group` 之後）：

```dart
group('listUndownloadedBooksForRemoteServer', () {
  test('回傳指定站點中 isDownloaded=false 的書籍，排除已下載與其他站點', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());

    await repo.insertBook(Book(
      id: 'book1',
      title: '僅雲端紀錄',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
      isDownloaded: false,
    ));
    await repo.insertBook(Book(
      id: 'book2',
      title: '已下載',
      format: BookFileFormat.epub,
      filePath: '/books/book2.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-2',
      isDownloaded: true,
    ));
    await repo.insertBook(Book(
      id: 'book3',
      title: '不同站點',
      format: BookFileFormat.epub,
      filePath: '/books/book3.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv2',
      remoteBookId: 'remote-book-3',
      isDownloaded: false,
    ));

    final result = await repo.listUndownloadedBooksForRemoteServer('srv1');
    expect(result.map((b) => b.id), ['book1']);
  });

  test('沒有符合條件的書籍時回傳空清單', () async {
    final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repo.close());
    expect(await repo.listUndownloadedBooksForRemoteServer('srv1'), isEmpty);
  });
});
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL——`LibraryRepository`／`SqliteLibraryRepository` 尚無這個方法，編譯錯誤。

- [x] **Step 3: 實作**

在 `app/lib/library/library_repository.dart` 的 `abstract class LibraryRepository` 內，緊接在既有 `findByContentFingerprint` 之後新增：

```dart
  /// 供遠端書庫刪除站點前的示警防護使用（epic-30-calibre-remote-library
  /// Issue 1，spec.md「站點管理」）：回傳指定站點中「僅雲端紀錄、無本機
  /// 檔案」（`isDownloaded == false`）的書籍清單。`RemoteServerRepository`
  /// 透過這個方法間接查詢，維持「`books`／`groups` 兩張表唯一存取入口」
  /// 的既有邊界（見本類別文件），不直接對 `books` 表下 SQL。
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId);
```

在 `app/lib/library/sqlite_library_repository.dart` 的 `SqliteLibraryRepository` 類別內，緊接在既有 `findByContentFingerprint` 實作之後新增：

```dart
  @override
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId) async {
    final rows = await _db.query(
      'books',
      where: 'remote_server_id = ? AND is_downloaded = 0',
      whereArgs: [serverId],
    );
    return rows.map(Book.fromMap).toList();
  }
```

在 `app/test/support/fake_library_repository.dart` 的 `FakeLibraryRepository` 類別內，緊接在既有 `findByContentFingerprint` 實作之後新增：

```dart
  @override
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId) async {
    return _books
        .where((b) => b.remoteServerId == serverId && !b.isDownloaded)
        .toList();
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart && flutter test`
Expected: 新增 2 項測試通過；全專案零回歸。

- [x] **Step 5: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/support/fake_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-30): LibraryRepository 新增 listUndownloadedBooksForRemoteServer"
```

---

### Task 3: `RemoteServerRepository`（介面／SQLite 實作／Fake）

**Files:**
- Create: `app/lib/remote/remote_server_repository.dart`
- Create: `app/lib/remote/sqlite_remote_server_repository.dart`
- Create: `app/test/support/fake_remote_server_repository.dart`
- Test: `app/test/remote/sqlite_remote_server_repository_test.dart`

**Interfaces:**
- Consumes: Task 1（`RemoteServerProfile`）、Task 2（`LibraryRepository.listUndownloadedBooksForRemoteServer`）。
- Produces:
  ```dart
  abstract class RemoteServerRepository {
    Future<List<RemoteServerProfile>> listServers();
    Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password});
    Future<void> updateServer(RemoteServerProfile profile, {String? password});
    Future<void> deleteServer(String serverId);
    Future<String?> loadPassword(String serverId);
  }
  class RemoteServerDeletionBlockedException implements Exception {
    final List<Book> blockingBooks;
  }
  ```
  Task 7-9（UI／`main.dart` 接線）依賴這個介面與例外型別。

**密碼語意（供 Task 8 表單畫面參照）**：`addServer`/`updateServer` 的 `password` 參數即「這次呼叫後密碼應該是什麼狀態」——傳 `null` 代表清空/不使用密碼（匿名連線），傳非 `null` 字串代表寫入/覆蓋。兩個方法語意對稱，不做「留空＝不變更」這種第三種狀態（YAGNI，避免表單畫面需要額外 UI 表達「不變更」）。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';
import 'package:elinkbook/remote/sqlite_remote_server_repository.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepo;
  late SqliteRemoteServerRepository repo;
  late FlutterSecureStoragePlatform originalPlatform;

  setUp(() async {
    libraryRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    repo = SqliteRemoteServerRepository(
      database: libraryRepo.database,
      libraryRepository: libraryRepo,
    );
  });

  tearDown(() async {
    await libraryRepo.close();
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  RemoteServerProfile profile(String id, {String? username, bool allowInsecure = false}) {
    return RemoteServerProfile(
      id: id,
      name: '測試站點',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: username,
      allowInsecure: allowInsecure,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('addServer 後 listServers 可以查到，密碼可透過 loadPassword 讀回', () async {
    await repo.addServer(profile('srv1', username: 'admin'), password: 'secret');

    final servers = await repo.listServers();
    expect(servers, hasLength(1));
    expect(servers.single.id, 'srv1');
    expect(servers.single.username, 'admin');
    expect(await repo.loadPassword('srv1'), 'secret');
  });

  test('addServer 未帶密碼時，loadPassword 回傳 null（匿名連線）', () async {
    await repo.addServer(profile('srv1'));
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('updateServer 帶新密碼時覆蓋舊密碼', () async {
    await repo.addServer(profile('srv1'), password: 'old-secret');
    await repo.updateServer(profile('srv1', username: 'admin'), password: 'new-secret');
    expect(await repo.loadPassword('srv1'), 'new-secret');
  });

  test('updateServer 未帶密碼時清除既有密碼（退回匿名）', () async {
    await repo.addServer(profile('srv1'), password: 'old-secret');
    await repo.updateServer(profile('srv1'));
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('updateServer 更新 allowInsecure／baseUrl 等欄位後 listServers 反映最新值', () async {
    await repo.addServer(profile('srv1'));
    await repo.updateServer(RemoteServerProfile(
      id: 'srv1',
      name: '改名後',
      baseUrl: 'https://192.168.1.100:8443/opds',
      type: RemoteServerType.opds,
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
    final updated = (await repo.listServers()).single;
    expect(updated.name, '改名後');
    expect(updated.allowInsecure, true);
  });

  test('deleteServer：沒有僅雲端紀錄書籍時，成功刪除站點與密碼', () async {
    await repo.addServer(profile('srv1'), password: 'secret');
    await repo.deleteServer('srv1');
    expect(await repo.listServers(), isEmpty);
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('deleteServer：有僅雲端紀錄（isDownloaded=false）書籍時，拋出例外並保留站點', () async {
    await repo.addServer(profile('srv1'));
    await libraryRepo.insertBook(Book(
      id: 'book1',
      title: '待下載的書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
      isDownloaded: false,
    ));

    await expectLater(
      () => repo.deleteServer('srv1'),
      throwsA(isA<RemoteServerDeletionBlockedException>().having(
        (e) => e.blockingBooks.map((b) => b.id),
        'blockingBooks',
        ['book1'],
      )),
    );
    expect(await repo.listServers(), hasLength(1));
  });

  test('deleteServer：已下載完成的書籍不阻擋刪除，其 remoteServerId 隨站點刪除自動變為 NULL', () async {
    await repo.addServer(profile('srv1'));
    await libraryRepo.insertBook(Book(
      id: 'book1',
      title: '已下載的書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
      isDownloaded: true,
    ));

    await repo.deleteServer('srv1');

    expect(await repo.listServers(), isEmpty);
    final books = await libraryRepo.listBooks();
    expect(books.single.remoteServerId, isNull);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/remote/sqlite_remote_server_repository_test.dart`
Expected: FAIL——`app/lib/remote/remote_server_repository.dart`／`sqlite_remote_server_repository.dart` 尚不存在。

- [x] **Step 3: 實作介面與例外型別**

Create `app/lib/remote/remote_server_repository.dart`：

```dart
import '../library/models/book.dart';
import 'remote_server_profile.dart';

/// 遠端書庫站點的存取介面（epic-30-calibre-remote-library Issue 1，
/// spec.md「站點管理：RemoteServerRepository」）。密碼獨立於
/// `RemoteServerProfile` 之外管理（見 [addServer]/[updateServer] 文件），
/// 不落地明文於 SQLite。
abstract class RemoteServerRepository {
  Future<List<RemoteServerProfile>> listServers();

  /// [password] 為 `null` 代表匿名連線（不使用密碼）。
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password});

  /// [password] 語意與 [addServer] 對稱：傳 `null` 清空既有密碼（退回
  /// 匿名），傳非 `null` 字串覆蓋既有密碼。沒有「留空＝不變更」這種
  /// 第三種狀態（YAGNI）。
  Future<void> updateServer(RemoteServerProfile profile, {String? password});

  /// 若該站點仍有 [Book.isDownloaded] 為 `false`（僅雲端紀錄、無本機
  /// 檔案）的書籍，拋出 [RemoteServerDeletionBlockedException] 並保留
  /// 站點不刪除；成功刪除時，已下載完成的書籍不受影響（`remoteServerId`
  /// 由資料庫外鍵自動清為 `null`，見 epic-30 Issue 0）。
  Future<void> deleteServer(String serverId);

  Future<String?> loadPassword(String serverId);
}

/// [RemoteServerRepository.deleteServer] 偵測到該站點仍有僅雲端紀錄書籍
/// 時拋出，[blockingBooks] 供呼叫端（UI）顯示示警清單。
class RemoteServerDeletionBlockedException implements Exception {
  final List<Book> blockingBooks;
  const RemoteServerDeletionBlockedException(this.blockingBooks);

  @override
  String toString() =>
      'RemoteServerDeletionBlockedException: ${blockingBooks.length} 本書僅有雲端紀錄，無法刪除此站點';
}
```

Create `app/lib/remote/sqlite_remote_server_repository.dart`：

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../library/library_repository.dart';
import 'remote_server_profile.dart';
import 'remote_server_repository.dart';

/// [RemoteServerRepository] 的 SQLite＋`flutter_secure_storage` 實作。
/// 與 `SqliteLibraryRepository` 共用同一個 [Database] 連線（比照
/// `LayoutPresetRepository`／`BookReaderPrefsRepository` 既有模式，
/// `main.dart` 建構時注入）。**刻意不直接查詢 `books` 表**——
/// `LibraryRepository` 是該表的唯一存取入口（見
/// `library_repository.dart` 類別文件），[deleteServer] 的刪除防護透過
/// 注入的 [LibraryRepository] 查詢。
class SqliteRemoteServerRepository implements RemoteServerRepository {
  SqliteRemoteServerRepository({
    required Database database,
    required LibraryRepository libraryRepository,
    FlutterSecureStorage? secureStorage,
  })  : _db = database,
        _libraryRepository = libraryRepository,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final Database _db;
  final LibraryRepository _libraryRepository;
  final FlutterSecureStorage _secureStorage;

  static String _passwordKey(String serverId) => 'remote_server_password_$serverId';

  @override
  Future<List<RemoteServerProfile>> listServers() async {
    final rows = await _db.query('remote_servers', orderBy: 'created_at ASC');
    return rows.map(RemoteServerProfile.fromMap).toList();
  }

  @override
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password}) async {
    await _db.insert('remote_servers', profile.toMap());
    await _writePassword(profile.id, password);
    return profile;
  }

  @override
  Future<void> updateServer(RemoteServerProfile profile, {String? password}) async {
    await _db.update(
      'remote_servers',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
    await _writePassword(profile.id, password);
  }

  Future<void> _writePassword(String serverId, String? password) async {
    if (password == null) {
      await _secureStorage.delete(key: _passwordKey(serverId));
    } else {
      await _secureStorage.write(key: _passwordKey(serverId), value: password);
    }
  }

  @override
  Future<String?> loadPassword(String serverId) async {
    // Keystore 損毀等已知環境因素讀取失敗時安全退回 null（視同匿名連線），
    // 比照 SyncAccountRepository 既有先例，不拋例外、不卡住畫面。
    try {
      return await _secureStorage.read(key: _passwordKey(serverId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    final blocking =
        await _libraryRepository.listUndownloadedBooksForRemoteServer(serverId);
    if (blocking.isNotEmpty) {
      throw RemoteServerDeletionBlockedException(blocking);
    }
    await _db.delete('remote_servers', where: 'id = ?', whereArgs: [serverId]);
    await _secureStorage.delete(key: _passwordKey(serverId));
  }
}
```

- [x] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/remote/sqlite_remote_server_repository_test.dart`
Expected: PASS，8 項測試全數通過。

- [x] **Step 5: 新增 `FakeRemoteServerRepository`**

Create `app/test/support/fake_remote_server_repository.dart`：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';

/// 供 widget test 使用的記憶體內 [RemoteServerRepository] 假實作
/// （比照 `FakeLibraryRepository` 既有模式）。[blockedDeletions] 供測試
/// 預先設定「刪除這個站點 id 時該回傳哪些擋下的書籍」，空清單或未設定
/// 代表允許刪除。
class FakeRemoteServerRepository implements RemoteServerRepository {
  FakeRemoteServerRepository({
    List<RemoteServerProfile> initialServers = const [],
    this.blockedDeletions = const {},
  }) : _servers = List.of(initialServers);

  final List<RemoteServerProfile> _servers;
  final Map<String, List<Book>> blockedDeletions;
  final Map<String, String> _passwords = {};

  final List<String> deleteServerCalls = [];

  @override
  Future<List<RemoteServerProfile>> listServers() async => List.of(_servers);

  @override
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password}) async {
    _servers.add(profile);
    if (password != null) {
      _passwords[profile.id] = password;
    }
    return profile;
  }

  @override
  Future<void> updateServer(RemoteServerProfile profile, {String? password}) async {
    final index = _servers.indexWhere((s) => s.id == profile.id);
    if (index != -1) _servers[index] = profile;
    if (password != null) {
      _passwords[profile.id] = password;
    } else {
      _passwords.remove(profile.id);
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    deleteServerCalls.add(serverId);
    final blocking = blockedDeletions[serverId];
    if (blocking != null && blocking.isNotEmpty) {
      throw RemoteServerDeletionBlockedException(blocking);
    }
    _servers.removeWhere((s) => s.id == serverId);
    _passwords.remove(serverId);
  }

  @override
  Future<String?> loadPassword(String serverId) async => _passwords[serverId];
}
```

- [x] **Step 6: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過（`FakeRemoteServerRepository` 此時尚無呼叫端，純粹編譯檢查）。

- [x] **Step 7: Commit**

```bash
git add app/lib/remote/remote_server_repository.dart app/lib/remote/sqlite_remote_server_repository.dart app/test/support/fake_remote_server_repository.dart app/test/remote/sqlite_remote_server_repository_test.dart
git commit -m "feat(epic-30): 新增 RemoteServerRepository（SQLite 實作＋Fake）"
```

---

### Task 4: OPDS 資料模型與 `OpdsFeedParser`

**Files:**
- Create: `app/lib/remote/opds_types.dart`
- Create: `app/lib/remote/opds_feed_parser.dart`
- Test: `app/test/remote/opds_feed_parser_test.dart`

**Interfaces:**
- Produces: `OpdsFeed`/`OpdsNavigationLink`/`OpdsEntry`/`OpdsAcquisition`（皆含 `==`/`hashCode`，純資料類別）、`OpdsFeedParser.parse(String xmlString, Uri feedUri) → OpdsFeed`。Task 5（`OpdsClient` 介面）、Task 6（`OpdsHttpClient`）依賴這些型別。

**這是唯一會做自動化測試的網路解析相關程式碼**（spec.md「Testing Decisions」：`OpdsFeedParser` 是純 Dart、不涉及網路，其餘 `OpdsHttpClient` 的實際 HTTP/憑證行為不做自動化測試）。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_feed_parser.dart';
import 'package:elinkbook/remote/opds_types.dart';

const _sampleFeedXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>家用 NAS 書庫</title>
  <link rel="next" href="/opds/page2"/>
  <entry>
    <title>作者分類</title>
    <link rel="subsection" href="/opds/by-author"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </entry>
  <entry>
    <id>urn:calibre:book-1</id>
    <title>紅樓夢</title>
    <author><name>曹雪芹</name></author>
    <link rel="http://opds-spec.org/image/thumbnail" href="/opds/cover/1.jpg"/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/1.epub" length="123456"/>
    <link rel="http://opds-spec.org/acquisition" type="application/pdf"
          href="http://192.168.1.100:8080/opds/download/1.pdf" length="654321"/>
  </entry>
  <entry>
    <id>urn:calibre:book-2</id>
    <title>不支援格式的書</title>
    <link rel="http://opds-spec.org/acquisition" type="application/vnd.ms-word"
          href="download/2.doc"/>
  </entry>
  <entry>
    <id>urn:calibre:book-3</id>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="download/3.epub"/>
  </entry>
</feed>''';

void main() {
  late OpdsFeedParser parser;
  final feedUri = Uri.parse('http://192.168.1.100:8080/opds/root');

  setUp(() {
    parser = const OpdsFeedParser();
  });

  test('解析 feed 標題與分頁 next 連結，相對路徑轉為絕對 URL', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    expect(feed.title, '家用 NAS 書庫');
    expect(feed.nextUrl, 'http://192.168.1.100:8080/opds/page2');
    expect(feed.prevUrl, isNull);
  });

  test('分類導覽條目（subsection）被歸類到 navigationLinks，href 轉為絕對 URL', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    expect(feed.navigationLinks, [
      const OpdsNavigationLink(
        title: '作者分類',
        href: 'http://192.168.1.100:8080/opds/by-author',
      ),
    ]);
  });

  test('書目條目正確解析 id/title/author/縮圖（相對路徑轉絕對）', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-1');
    expect(book.title, '紅樓夢');
    expect(book.author, '曹雪芹');
    expect(book.thumbnailUrl, 'http://192.168.1.100:8080/opds/cover/1.jpg');
  });

  test('同一書目多個 acquisition 連結皆被解析，相對與絕對路徑皆正確保留/轉換', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-1');
    expect(book.acquisitions, [
      const OpdsAcquisition(
        href: 'http://192.168.1.100:8080/opds/download/1.epub',
        format: BookFileFormat.epub,
        sizeBytes: 123456,
      ),
      const OpdsAcquisition(
        href: 'http://192.168.1.100:8080/opds/download/1.pdf',
        format: BookFileFormat.pdf,
        sizeBytes: 654321,
      ),
    ]);
  });

  test('不支援的 MIME type 時 format 為 null', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-2');
    expect(book.acquisitions.single.format, isNull);
  });

  test('〔審查 Finding 2〕MIME type 無法辨識時退回看 href 副檔名（含查詢字串，不誤判）', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>格式退回測試</title>
  <entry>
    <id>urn:calibre:book-4</id>
    <title>MIME 遺失但副檔名可辨識</title>
    <link rel="http://opds-spec.org/acquisition" type="application/octet-stream"
          href="download/4.epub?token=abc123"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    final book = feed.entries.single;
    expect(book.acquisitions.single.format, BookFileFormat.epub);
    expect(book.acquisitions.single.href,
        'http://192.168.1.100:8080/opds/download/4.epub?token=abc123');
  });

  test('〔審查 Finding 2〕MIME type 與副檔名皆無法辨識時 format 仍為 null', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>格式退回測試</title>
  <entry>
    <id>urn:calibre:book-5</id>
    <title>兩者皆無法辨識</title>
    <link rel="http://opds-spec.org/acquisition" type="application/octet-stream"
          href="download/5.mobi"/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    expect(feed.entries.single.acquisitions.single.format, isNull);
  });

  test('〔審查 Finding 4〕href 前後帶空白字元時 trim() 後仍正確解析為絕對 URL', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>空白字元測試</title>
  <entry>
    <id>urn:calibre:book-6</id>
    <title>href 帶空白</title>
    <link rel="http://opds-spec.org/image/thumbnail" href=" /opds/cover/6.jpg "/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href=" download/6.epub "/>
  </entry>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    final book = feed.entries.single;
    expect(book.thumbnailUrl, 'http://192.168.1.100:8080/opds/cover/6.jpg');
    expect(book.acquisitions.single.href, 'http://192.168.1.100:8080/opds/download/6.epub');
  });

  test('缺少 <title> 的書目條目容錯，退回顯示「未知書名」，不拋出例外', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-3');
    expect(book.title, '未知書名');
    expect(book.author, isNull);
  });

  test('缺少 length 屬性時 sizeBytes 為 null，不拋出例外', () {
    final feed = parser.parse(_sampleFeedXml, feedUri);
    final book = feed.entries.firstWhere((e) => e.remoteBookId == 'urn:calibre:book-3');
    expect(book.acquisitions.single.sizeBytes, isNull);
  });

  test('沒有 next 連結時 nextUrl 為 null', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>空書庫</title>
</feed>''';
    final feed = parser.parse(xml, feedUri);
    expect(feed.nextUrl, isNull);
    expect(feed.entries, isEmpty);
    expect(feed.navigationLinks, isEmpty);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/remote/opds_feed_parser_test.dart`
Expected: FAIL——`opds_types.dart`／`opds_feed_parser.dart` 尚不存在。

- [x] **Step 3: 實作資料模型**

Create `app/lib/remote/opds_types.dart`：

```dart
import '../library/models/library_enums.dart';

/// OPDS 目錄一頁的解析結果（epic-30-calibre-remote-library Issue 1，
/// spec.md「OPDS 瀏覽與下載：OpdsClient」）。[nextUrl]/[prevUrl] 若非
/// `null` 保證為絕對 URL（[OpdsFeedParser] 已用 `Uri.resolve()` 正規化）。
class OpdsFeed {
  final String title;
  final String? nextUrl;
  final String? prevUrl;
  final List<OpdsNavigationLink> navigationLinks;
  final List<OpdsEntry> entries;

  const OpdsFeed({
    required this.title,
    this.nextUrl,
    this.prevUrl,
    this.navigationLinks = const [],
    this.entries = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsFeed &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          nextUrl == other.nextUrl &&
          prevUrl == other.prevUrl &&
          _listEquals(navigationLinks, other.navigationLinks) &&
          _listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hash(
        title,
        nextUrl,
        prevUrl,
        Object.hashAll(navigationLinks),
        Object.hashAll(entries),
      );
}

/// 分類下鑽節點（例如依作者/系列/標籤），對應 OPDS Feed 內
/// `rel="subsection"` 的條目。
class OpdsNavigationLink {
  final String title;
  final String href;

  const OpdsNavigationLink({required this.title, required this.href});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsNavigationLink &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          href == other.href;

  @override
  int get hashCode => Object.hash(title, href);
}

/// 一本書目條目，[remoteBookId] 為 OPDS 條目層級 id（書本身，不分格式，
/// 見 design.md「資料模型」），[acquisitions] 為該書提供的各格式下載
/// 連結。
class OpdsEntry {
  final String remoteBookId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final List<OpdsAcquisition> acquisitions;

  const OpdsEntry({
    required this.remoteBookId,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.acquisitions = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsEntry &&
          runtimeType == other.runtimeType &&
          remoteBookId == other.remoteBookId &&
          title == other.title &&
          author == other.author &&
          thumbnailUrl == other.thumbnailUrl &&
          _listEquals(acquisitions, other.acquisitions);

  @override
  int get hashCode => Object.hash(
        remoteBookId,
        title,
        author,
        thumbnailUrl,
        Object.hashAll(acquisitions),
      );
}

/// 單一格式的下載連結。[format] 為 `null` 代表 elinkBook 不支援的格式，
/// UI 應置灰不可選（見 spec.md「瀏覽與匯入 UI」）。
class OpdsAcquisition {
  final String href;
  final BookFileFormat? format;
  final int? sizeBytes;

  const OpdsAcquisition({required this.href, this.format, this.sizeBytes});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpdsAcquisition &&
          runtimeType == other.runtimeType &&
          href == other.href &&
          format == other.format &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode => Object.hash(href, format, sizeBytes);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [x] **Step 4: 實作 `OpdsFeedParser`**

Create `app/lib/remote/opds_feed_parser.dart`：

```dart
import 'package:xml/xml.dart';

import '../library/models/library_enums.dart';
import 'opds_types.dart';

/// 純 Dart、無網路依賴的 OPDS Atom XML 解析器（epic-30-calibre-remote-library
/// Issue 1，spec.md「OPDS 瀏覽與下載：OpdsClient」）。所有 `href`
/// （Acquisition／縮圖／導覽／分頁）皆以 [feedUri] 為基準呼叫
/// `Uri.resolve()` 轉為絕對 URL，`review-spec.md` Important #1 已核實
/// 採納——標準 OPDS Feed 的 `href` 常為相對路徑，呼叫端拿到的 [OpdsFeed]
/// 保證不含相對路徑，不需要也不應該自行處理。
///
/// 解析失敗容錯：缺失 `<title>` 時退回「未知書名」／「未命名分類」，
/// 缺失作者時 `author` 為 `null`，格式不規範的欄位跳過不拋例外——維持
/// 既有匯入流程「降級但不中斷」的一貫風格（比照
/// `book_import_service_impl.dart` 對外部詮釋資料缺失的既有處理慣例）。
class OpdsFeedParser {
  const OpdsFeedParser();

  OpdsFeed parse(String xmlString, Uri feedUri) {
    final document = XmlDocument.parse(xmlString);
    final feed = document.rootElement;

    final title = _firstText(feed, 'title') ?? feedUri.toString();

    String? nextUrl;
    String? prevUrl;
    for (final link in feed.findElements('link')) {
      final rel = link.getAttribute('rel');
      final href = link.getAttribute('href');
      if (href == null) continue;
      if (rel == 'next') nextUrl = _resolve(feedUri, href);
      if (rel == 'previous' || rel == 'prev') prevUrl = _resolve(feedUri, href);
    }

    final navigationLinks = <OpdsNavigationLink>[];
    final entries = <OpdsEntry>[];

    for (final entry in feed.findElements('entry')) {
      final entryLinks = entry.findElements('link').toList();
      final acquisitionLinks = entryLinks
          .where((l) =>
              (l.getAttribute('rel') ?? '').startsWith('http://opds-spec.org/acquisition'))
          .toList();

      if (acquisitionLinks.isNotEmpty) {
        entries.add(_parseBookEntry(entry, entryLinks, acquisitionLinks, feedUri));
        continue;
      }

      final subsectionLink =
          _firstWhereOrNull(entryLinks, (l) => l.getAttribute('rel') == 'subsection');
      final subsectionHref = subsectionLink?.getAttribute('href');
      if (subsectionHref != null) {
        navigationLinks.add(OpdsNavigationLink(
          title: _firstText(entry, 'title') ?? '未命名分類',
          href: _resolve(feedUri, subsectionHref),
        ));
      }
    }

    return OpdsFeed(
      title: title,
      nextUrl: nextUrl,
      prevUrl: prevUrl,
      navigationLinks: navigationLinks,
      entries: entries,
    );
  }

  OpdsEntry _parseBookEntry(
    XmlElement entry,
    List<XmlElement> entryLinks,
    List<XmlElement> acquisitionLinks,
    Uri feedUri,
  ) {
    final entryTitle = _firstText(entry, 'title') ?? '未知書名';
    final authorElement = _firstWhereOrNull(entry.findElements('author'), (_) => true);
    final author = authorElement == null ? null : _firstText(authorElement, 'name');
    final remoteBookId = _firstText(entry, 'id') ?? entryTitle;

    final thumbnailLink = _firstWhereOrNull(entryLinks, (l) {
      final rel = l.getAttribute('rel') ?? '';
      return rel == 'http://opds-spec.org/image' ||
          rel == 'http://opds-spec.org/image/thumbnail';
    });
    final thumbnailHref = thumbnailLink?.getAttribute('href');

    final acquisitions = acquisitionLinks
        .map((l) {
          final href = l.getAttribute('href');
          if (href == null) return null;
          final resolvedHref = _resolve(feedUri, href);
          return OpdsAcquisition(
            href: resolvedHref,
            format: _detectFormat(l.getAttribute('type'), resolvedHref),
            sizeBytes: int.tryParse(l.getAttribute('length') ?? ''),
          );
        })
        .whereType<OpdsAcquisition>()
        .toList();

    return OpdsEntry(
      remoteBookId: remoteBookId,
      title: entryTitle,
      author: author,
      thumbnailUrl: thumbnailHref == null ? null : _resolve(feedUri, thumbnailHref),
      acquisitions: acquisitions,
    );
  }

  String? _firstText(XmlElement parent, String name) {
    final elements = parent.findElements(name);
    if (elements.isEmpty) return null;
    final text = elements.first.innerText.trim();
    return text.isEmpty ? null : text;
  }

  XmlElement? _firstWhereOrNull(
    Iterable<XmlElement> elements,
    bool Function(XmlElement) test,
  ) {
    for (final element in elements) {
      if (test(element)) return element;
    }
    return null;
  }

  /// **〔`review-plan-issue-1.md` Finding 4 採納〕** 部分不規範伺服器的
  /// XML `href` 屬性值可能帶有前後空白字元，`trim()` 後再交給
  /// `Uri.resolve()`，避免產生非預期的 URL 編碼或解析例外。
  String _resolve(Uri base, String href) => base.resolve(href.trim()).toString();

  /// **〔`review-plan-issue-1.md` Finding 2 採納〕** 依 `spec.md:138`
  /// 「格式過濾」規範：先比對 MIME type，比對不到已知 MIME type 時退回
  /// 看 `href` 副檔名；皆無法判斷才回傳 `null`（MOBI 等真正不支援的
  /// 格式落在這裡）。[href] 傳入時已經過 [_resolve] 正規化為絕對 URL，
  /// 用 `Uri.tryParse(href)?.path` 只取路徑部分再判斷副檔名——不能直接
  /// 對整個 URL 字串做 `endsWith()`，OPDS 下載連結常帶簽章/權杖查詢
  /// 字串（例如 `download/1.epub?token=abc`），直接比對整串會誤判。
  BookFileFormat? _detectFormat(String? mimeType, String href) {
    final fromMime = _formatFromMimeType(mimeType);
    if (fromMime != null) return fromMime;
    final path = Uri.tryParse(href)?.path ?? href;
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.epub')) return BookFileFormat.epub;
    if (lowerPath.endsWith('.pdf')) return BookFileFormat.pdf;
    if (lowerPath.endsWith('.txt')) return BookFileFormat.txt;
    if (lowerPath.endsWith('.azw3')) return BookFileFormat.azw3;
    if (lowerPath.endsWith('.cbz')) return BookFileFormat.cbz;
    if (lowerPath.endsWith('.md')) return BookFileFormat.md;
    return null;
  }

  BookFileFormat? _formatFromMimeType(String? mimeType) {
    switch (mimeType) {
      case 'application/epub+zip':
        return BookFileFormat.epub;
      case 'application/pdf':
        return BookFileFormat.pdf;
      case 'text/plain':
        return BookFileFormat.txt;
      case 'application/x-mobipocket-ebook':
      case 'application/vnd.amazon.ebook':
        return BookFileFormat.azw3;
      case 'application/vnd.comicbook+zip':
      case 'application/x-cbz':
        return BookFileFormat.cbz;
      case 'text/markdown':
        return BookFileFormat.md;
      default:
        return null;
    }
  }
}
```

- [x] **Step 5: 執行測試確認全數通過**

Run: `flutter test test/remote/opds_feed_parser_test.dart`
Expected: PASS，13 項測試全數通過。

- [x] **Step 6: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: 乾淨、全數通過。

- [x] **Step 7: Commit**

```bash
git add app/lib/remote/opds_types.dart app/lib/remote/opds_feed_parser.dart app/test/remote/opds_feed_parser_test.dart
git commit -m "feat(epic-30): 新增 OPDS 資料模型與 OpdsFeedParser"
```

---

### Task 5: `OpdsClient` 介面與 `FakeOpdsClient`

**Files:**
- Create: `app/lib/remote/opds_client.dart`
- Create: `app/test/support/fake_opds_client.dart`

**Interfaces:**
- Consumes: Task 1（`RemoteServerProfile`）、Task 4（`OpdsFeed`／`OpdsAcquisition`）。
- Produces:
  ```dart
  abstract class OpdsClient {
    Future<bool> testConnection(RemoteServerProfile server, {String? password});
    Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl});
    Future<File> downloadBook(RemoteServerProfile server, OpdsAcquisition acquisition,
        String destinationPath, {String? password, void Function(int, int)? onProgress,
        OpdsDownloadCancellationToken? cancellationToken});
  }
  class OpdsDownloadCancellationToken { void cancel(); bool get isCancelled; }
  ```
  Task 6（`OpdsHttpClient`）、Task 8（`RemoteServerFormScreen`）、Issue 2 皆依賴這個介面。

本 Task 沒有獨立的紅燈/綠燈測試——`OpdsClient` 是純介面宣告，`FakeOpdsClient` 的正確性由 Task 8 消費它的 widget test 間接驗證（比照 `FakeLibraryRepository` 等既有測試替身「無獨立測試檔，由消費端測試驗證」的慣例，見 `epic-30` Issue 0 的 `fake_library_repository_test.dart` 是例外而非常態——本 Task 的 Fake 邏輯足夠單純，不需要重複這個例外）。

- [x] **Step 1: 實作介面**

Create `app/lib/remote/opds_client.dart`：

```dart
import 'dart:io';

import 'opds_types.dart';
import 'remote_server_profile.dart';

/// 下載中途取消的輕量信號（epic-30-calibre-remote-library Issue 1，
/// spec.md「OPDS 瀏覽與下載」）：本專案僅有 `http` 套件、無 `dio`，故不
/// 採用 `dio` 的 `CancelToken` 型別，自訂一個語意等價的輕量取消信號。
class OpdsDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 單一共用介面，涵蓋測試連線／目錄瀏覽／下載，是整個遠端書庫瀏覽＋
/// 下載＋站點管理 UX 唯一依賴的邊界（spec.md「OPDS 瀏覽與下載：
/// OpdsClient」，seam 已與使用者確認）。
abstract class OpdsClient {
  /// 內部實作應直接嘗試 [fetchFeed] 該站點根目錄並捕捉例外，成功回傳
  /// `true`、任何網路/認證/解析錯誤回傳 `false`（不需要細分錯誤類型，
  /// UI 統一顯示「連線失敗，請檢查網址/帳密/憑證設定」）。
  Future<bool> testConnection(RemoteServerProfile server, {String? password});

  /// [feedUrl] 為 `null` 時載入 [server.baseUrl]（站點根目錄）；非 `null`
  /// 時載入指定的分類/分頁 Feed（通常來自前一次呼叫回傳的
  /// [OpdsFeed.nextUrl]/[OpdsNavigationLink.href]）。回傳的
  /// [OpdsFeed] 內所有 URL 皆保證為絕對路徑。
  Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl});

  /// 下載 [acquisition] 指定的檔案到 [destinationPath]。[onProgress] 於
  /// 每個資料區塊到達時回呼 `(received, total)`，`total` 為 0 代表伺服器
  /// 未提供 Content-Length。[cancellationToken] 於下載中途被
  /// `cancel()` 時中斷連線並清除已寫入的部分檔案。
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  });
}
```

- [x] **Step 2: 實作 `FakeOpdsClient`**

Create `app/test/support/fake_opds_client.dart`：

```dart
import 'dart:io';

import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

/// 供 widget test 使用的 [OpdsClient] 假實作（比照
/// `FakeCloudStorageClient`／`FakeLibraryRepository` 命名與設計慣例）。
class FakeOpdsClient implements OpdsClient {
  FakeOpdsClient({
    this.testConnectionResult = true,
    Map<String, OpdsFeed> feeds = const {},
    this.downloadError,
  }) : _feeds = Map.of(feeds);

  /// [testConnection] 的固定回傳值，測試可依情境覆寫為 `false` 模擬
  /// 連線失敗。
  bool testConnectionResult;

  /// key 為 `fetchFeed` 的 `feedUrl` 參數（`null` 代表根目錄，以
  /// `server.baseUrl` 為 key）。
  final Map<String, OpdsFeed> _feeds;

  /// 非 `null` 時 [downloadBook] 拋出這個例外，模擬下載失敗。
  Object? downloadError;

  final List<String> testConnectionCalls = [];
  // 〔審查 review-plan-issue-1.md Finding 1 採納〕與 testConnectionCalls
  // 同索引對應，供 Task 8 的測試驗證「編輯模式密碼欄位留空時，測試連線
  // 是否正確沿用既有密碼」。
  final List<String?> testConnectionPasswords = [];
  final List<String?> fetchFeedCalls = [];
  final List<String> downloadBookCalls = [];

  @override
  Future<bool> testConnection(RemoteServerProfile server, {String? password}) async {
    testConnectionCalls.add(server.id);
    testConnectionPasswords.add(password);
    return testConnectionResult;
  }

  @override
  Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl}) async {
    fetchFeedCalls.add(feedUrl);
    final key = feedUrl ?? server.baseUrl;
    final feed = _feeds[key];
    if (feed == null) {
      throw StateError('FakeOpdsClient: 沒有預先設定 $key 的 OpdsFeed');
    }
    return feed;
  }

  @override
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  }) async {
    downloadBookCalls.add(acquisition.href);
    if (downloadError != null) throw downloadError!;
    onProgress?.call(100, 100);
    final file = File(destinationPath);
    await file.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }
}
```

- [x] **Step 3: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: 乾淨、全數通過（兩個新檔案此時尚無呼叫端，純粹編譯檢查）。

- [x] **Step 4: Commit**

```bash
git add app/lib/remote/opds_client.dart app/test/support/fake_opds_client.dart
git commit -m "feat(epic-30): 新增 OpdsClient 介面與 FakeOpdsClient"
```

---

### Task 6: `OpdsHttpClient` 真實實作

**Files:**
- Create: `app/lib/remote/opds_http_client.dart`

**Interfaces:**
- Consumes: Task 1、Task 4、Task 5 的全部型別。
- Produces: `OpdsHttpClient implements OpdsClient`。Task 9（`main.dart` 接線）依賴這個類別建構全域實例（僅供 `testConnection` 使用，見 Global Constraints）。

**本 Task 不做自動化測試**（spec.md「Testing Decisions」：真實 HTTP 呼叫、Basic Auth header、自簽憑證放行、分頁循環防護的實際觸發皆不做自動化測試，比照 `epic-29` 對 `GoogleDriveStorageClient` 的既有慣例），僅需 `flutter analyze` 乾淨與能成功編譯。

- [x] **Step 1: 實作**

Create `app/lib/remote/opds_http_client.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'opds_client.dart';
import 'opds_feed_parser.dart';
import 'opds_types.dart';
import 'remote_server_profile.dart';

/// [OpdsClient] 的真實 HTTP 實作（epic-30-calibre-remote-library
/// Issue 1，spec.md「OPDS 瀏覽與下載：OpdsClient」）。
///
/// **生命週期警告**：[_visitedFeedUrls] 是這個實例的內部狀態，語意上
/// 對應「一次瀏覽路徑」（spec.md「review-design.md Minor #1 採納」）。
/// 本 Issue 只透過 [testConnection] 使用（單次 `fetchFeed`，不涉及分頁
/// 鏈），所以 `main.dart` 建構一個全域共用實例是安全的；**Issue 2
/// 建構 `RemoteCatalogScreen` 時，每次使用者進入某個站點的瀏覽 session
/// 都必須建構一個全新的 `OpdsHttpClient()`，用完即捨棄**，不可沿用
/// `main.dart` 注入的全域實例——否則「已造訪過」的判定會錯誤地累積到
/// 跨 session、跨站點，導致合法的重新造訪被誤判為循環而提前結束分頁。
class OpdsHttpClient implements OpdsClient {
  OpdsHttpClient({OpdsFeedParser? parser}) : _parser = parser ?? const OpdsFeedParser();

  final OpdsFeedParser _parser;
  final Set<String> _visitedFeedUrls = {};

  static const _timeout = Duration(seconds: 10);

  /// [server.allowInsecure] 為 `true` 時，回傳的 [http.Client] 透過
  /// `badCertificateCallback` 放行憑證錯誤——**僅這一次呼叫端持有的
  /// client 物件生效**（呼叫端用畢即 `close()`），不會影響其他連線，
  /// 符合「不得全域關閉憑證驗證」的既定原則（Global Constraints）。
  http.Client _clientFor(RemoteServerProfile server) {
    if (!server.allowInsecure) return http.Client();
    final rawClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(rawClient);
  }

  Map<String, String> _authHeaders(RemoteServerProfile server, String? password) {
    if (server.username == null) return {};
    final credentials = base64Encode(utf8.encode('${server.username}:${password ?? ''}'));
    return {'Authorization': 'Basic $credentials'};
  }

  @override
  Future<bool> testConnection(RemoteServerProfile server, {String? password}) async {
    try {
      await fetchFeed(server, password: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<OpdsFeed> fetchFeed(
    RemoteServerProfile server, {
    String? password,
    String? feedUrl,
  }) async {
    final url = feedUrl ?? server.baseUrl;
    _visitedFeedUrls.add(url);
    final client = _clientFor(server);
    try {
      final response = await client
          .get(Uri.parse(url), headers: _authHeaders(server, password))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('OPDS 伺服器回應 ${response.statusCode}', uri: Uri.parse(url));
      }
      final parsed = _parser.parse(response.body, Uri.parse(url));
      // 分頁循環防護：若 nextUrl 指回已造訪過的 URL（部分不規範伺服器的
      // 已知行為），視為分頁結束，不繼續請求，避免無限遞迴。
      final nextUrl = parsed.nextUrl != null && _visitedFeedUrls.contains(parsed.nextUrl)
          ? null
          : parsed.nextUrl;
      return OpdsFeed(
        title: parsed.title,
        nextUrl: nextUrl,
        prevUrl: parsed.prevUrl,
        navigationLinks: parsed.navigationLinks,
        entries: parsed.entries,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  }) async {
    final client = _clientFor(server);
    try {
      final request = http.Request('GET', Uri.parse(acquisition.href))
        ..headers.addAll(_authHeaders(server, password));
      final streamedResponse = await client.send(request).timeout(_timeout);
      if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
        throw HttpException(
          '下載失敗，伺服器回應 ${streamedResponse.statusCode}',
          uri: Uri.parse(acquisition.href),
        );
      }
      final total = streamedResponse.contentLength ?? acquisition.sizeBytes ?? 0;
      final file = File(destinationPath);
      await file.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      var cancelled = false;
      // 〔審查 review-plan-issue-1.md Finding 3 採納〕內層 try/finally
      // 確保 sink 在正常完成／使用者取消（break，非例外）／串流中途拋出
      // 例外（例如網路中斷 SocketException）三種情況下都會被關閉；外層
      // try/catch 專門處理「例外」這條路徑——串流寫入中途失敗時，內層
      // finally 已關閉 sink，這裡刪除殘留的不完整暫存檔後原樣重拋，避免
      // 留下孤兒檔案（spec.md「OPDS 瀏覽與下載」：「使用者取消...或下載
      // 失敗時立即清除暫存檔，不留孤兒檔案」，原設計僅涵蓋取消，未涵蓋
      // 網路中斷等真實下載失敗情境）。
      try {
        try {
          await for (final chunk in streamedResponse.stream) {
            if (cancellationToken?.isCancelled ?? false) {
              cancelled = true;
              break;
            }
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
        } finally {
          await sink.close();
        }
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      if (cancelled) {
        if (await file.exists()) await file.delete();
        throw const _DownloadCancelledException();
      }
      return file;
    } finally {
      client.close();
    }
  }
}

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();
  @override
  String toString() => '下載已取消';
}
```

- [x] **Step 2: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3: 執行全專案測試確認零回歸**

Run: `flutter test`
Expected: 全數通過（本檔案尚無呼叫端，純粹編譯檢查）。

- [x] **Step 4: Commit**

```bash
git add app/lib/remote/opds_http_client.dart
git commit -m "feat(epic-30): 新增 OpdsHttpClient 真實實作"
```

---

### Task 7: `RemoteServerListScreen`

**Files:**
- Create: `app/lib/screens/remote_server_list_screen.dart`
- Test: `app/test/screens/remote_server_list_screen_test.dart`

**Interfaces:**
- Consumes: Task 3（`RemoteServerRepository`／`RemoteServerDeletionBlockedException`）、Task 5（`OpdsClient`，向下傳給 Task 8 的表單畫面）。
- Produces: `RemoteServerListScreen({required RemoteServerRepository repository, required OpdsClient opdsClient})`。Task 9（`LibraryScreen` 進入點）依賴這個建構子。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/remote_server_form_screen.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

void main() {
  RemoteServerProfile profile(String id, {String name = '家用 NAS'}) {
    return RemoteServerProfile(
      id: id,
      name: name,
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        opdsClient: FakeOpdsClient(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('沒有任何站點時顯示空狀態文字', (tester) async {
    await pumpScreen(tester, repository: FakeRemoteServerRepository());
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsOneWidget);
  });

  testWidgets('已有站點時顯示名稱與網址', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [profile('srv1')]),
    );
    expect(find.text('家用 NAS'), findsOneWidget);
    expect(find.text('http://192.168.1.100:8080/opds'), findsOneWidget);
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsNothing);
  });

  testWidgets('點擊新增按鈕導向 RemoteServerFormScreen（新增模式）', (tester) async {
    await pumpScreen(tester, repository: FakeRemoteServerRepository());
    await tester.tap(find.byKey(const Key('remote_server_list_add_button')));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteServerFormScreen), findsOneWidget);
    expect(find.text('新增站點'), findsOneWidget);
  });

  testWidgets('點擊編輯按鈕導向 RemoteServerFormScreen（編輯模式）', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [profile('srv1')]),
    );
    await tester.tap(find.byKey(const Key('remote_server_item_edit_srv1')));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteServerFormScreen), findsOneWidget);
    expect(find.text('編輯站點'), findsOneWidget);
  });

  testWidgets('刪除沒有阻擋的站點後，該站點從清單消失', (tester) async {
    final repository = FakeRemoteServerRepository(initialServers: [profile('srv1')]);
    await pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('remote_server_item_delete_srv1')));
    await tester.pumpAndSettle();

    expect(repository.deleteServerCalls, ['srv1']);
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsOneWidget);
  });

  testWidgets('刪除被擋下的站點時顯示示警對話框，站點仍留在清單', (tester) async {
    final blockingBook = _fakeBook('book1', '待下載的書');
    final repository = FakeRemoteServerRepository(
      initialServers: [profile('srv1')],
      blockedDeletions: {'srv1': [blockingBook]},
    );
    await pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('remote_server_item_delete_srv1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote_server_delete_blocked_dialog')), findsOneWidget);
    expect(find.textContaining('待下載的書'), findsOneWidget);
    expect(find.text('家用 NAS'), findsOneWidget);
  });
}
```

**Step 1 附註**：測試需要一個最小可用的 `Book` fixture。在同一個測試檔案內新增一個小型 helper（比照 `sqlite_library_repository_test.dart` 頂層 `_book()` helper 的既有慣例）：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

Book _fakeBook(String id, String title) {
  return Book(
    id: id,
    title: title,
    format: BookFileFormat.epub,
    filePath: '/books/$id.epub',
    source: BookSource.calibreOpds,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    isDownloaded: false,
  );
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/remote_server_list_screen_test.dart`
Expected: FAIL——`remote_server_list_screen.dart`／`remote_server_form_screen.dart` 尚不存在（後者在 Task 8 才建立；本 Task 先用一個最小可編譯的 `RemoteServerFormScreen` stub 讓測試能編譯，Task 8 再補上完整表單邏輯——見下方 Step 3 的實作已包含最小可用版本，不需要額外 stub 檔）。

- [x] **Step 3: 實作 `RemoteServerListScreen`**（同時建立 Task 8 將完整化的 `RemoteServerFormScreen` 最小版本，見 Task 8）

先建立 `app/lib/screens/remote_server_form_screen.dart` 的最小可編譯版本（僅供本 Task 的測試通過，Task 8 會補齊完整表單邏輯）：

```dart
import 'package:flutter/material.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// 新增/編輯遠端書庫站點表單（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）。完整實作見 Task 8；本檔案由 Task 7 建立
/// 最小可編譯版本，Task 8 逐步補齊欄位與測試連線邏輯。
class RemoteServerFormScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient opdsClient;
  final RemoteServerProfile? existingProfile;

  const RemoteServerFormScreen({
    super.key,
    required this.repository,
    required this.opdsClient,
    this.existingProfile,
  });

  @override
  State<RemoteServerFormScreen> createState() => _RemoteServerFormScreenState();
}

class _RemoteServerFormScreenState extends State<RemoteServerFormScreen> {
  bool get _isEditing => widget.existingProfile != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯站點' : '新增站點')),
      body: const SizedBox.shrink(),
    );
  }
}
```

Create `app/lib/screens/remote_server_list_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';
import 'remote_server_form_screen.dart';

/// 遠端書庫站點清單畫面（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）：新增/編輯/刪除 Calibre／OPDS 站點，刪除時
/// 若該站點仍有僅雲端紀錄（尚未下載）的書籍會被拒絕並顯示示警清單。
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient opdsClient;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.opdsClient,
  });

  @override
  State<RemoteServerListScreen> createState() => _RemoteServerListScreenState();
}

class _RemoteServerListScreenState extends State<RemoteServerListScreen> {
  bool _loading = true;
  List<RemoteServerProfile> _servers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final servers = await widget.repository.listServers();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _loading = false;
    });
  }

  Future<void> _openAddForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          opdsClient: widget.opdsClient,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditForm(RemoteServerProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          opdsClient: widget.opdsClient,
          existingProfile: profile,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(RemoteServerProfile profile) async {
    try {
      await widget.repository.deleteServer(profile.id);
      _load();
    } on RemoteServerDeletionBlockedException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('remote_server_delete_blocked_dialog'),
          title: const Text('無法刪除站點'),
          content: Text(
            '這個站點還有 ${e.blockingBooks.length} 本書僅有雲端紀錄、尚未下載：\n'
            '${e.blockingBooks.map((b) => '．${b.title}').join('\n')}\n\n'
            '請先於書架移除這些書籍，或重新下載後再刪除站點。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('了解'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('遠端書庫'),
        actions: [
          IconButton(
            key: const Key('remote_server_list_add_button'),
            icon: const Icon(Icons.add),
            tooltip: '新增站點',
            onPressed: _openAddForm,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('remote_server_list_loading_indicator'),
              ),
            )
          : _servers.isEmpty
              ? const Center(
                  child: Text(
                    '尚未新增任何遠端書庫站點',
                    key: Key('remote_server_list_empty_state'),
                  ),
                )
              : ListView.builder(
                  itemCount: _servers.length,
                  itemBuilder: (context, index) {
                    final profile = _servers[index];
                    return ListTile(
                      key: Key('remote_server_item_${profile.id}'),
                      title: Text(profile.name),
                      subtitle: Text(profile.baseUrl),
                      onTap: () => _openEditForm(profile),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('remote_server_item_edit_${profile.id}'),
                            icon: const Icon(Icons.edit),
                            tooltip: '編輯',
                            onPressed: () => _openEditForm(profile),
                          ),
                          IconButton(
                            key: Key('remote_server_item_delete_${profile.id}'),
                            icon: const Icon(Icons.delete),
                            tooltip: '刪除',
                            onPressed: () => _delete(profile),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
```

- [x] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/remote_server_list_screen_test.dart`
Expected: PASS，6 項測試全數通過。

- [x] **Step 5: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: 乾淨、全數通過。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/remote_server_list_screen.dart app/lib/screens/remote_server_form_screen.dart app/test/screens/remote_server_list_screen_test.dart
git commit -m "feat(epic-30): 新增 RemoteServerListScreen（含站點刪除防護對話框）"
```

---

### Task 8: `RemoteServerFormScreen` 完整表單邏輯

**Files:**
- Modify: `app/lib/screens/remote_server_form_screen.dart`（Task 7 已建立最小版本）
- Test: `app/test/screens/remote_server_form_screen_test.dart`

**Interfaces:**
- Consumes: Task 3（`RemoteServerRepository`）、Task 5（`OpdsClient`）。
- Produces: 完整的 `RemoteServerFormScreen`（欄位：名稱／網址／類型／帳號／密碼／允許不安全連線／測試連線／儲存）。

**密碼欄位安全慣例**：編輯模式下**不預填**既有密碼（比照 `sync_settings_screen.dart` 既有慣例，密碼欄位永遠留空由使用者自行決定要不要輸入新密碼）。

**〔`review-plan-issue-1.md` Finding 1 核實採納，修正密碼更新語意〕** 原計畫「留空並儲存＝清空既有密碼」會讓使用者只是想改站點名稱或切換「允許不安全連線」，儲存時就意外把已存密碼洗掉——密碼欄位基於安全考量從不預填，使用者根本看不出「留空」跟「原本就沒有密碼」的差別。修正為：
- **新增模式**：密碼欄位留空＝匿名連線，語意不變。
- **編輯模式**：密碼欄位輸入新值＝覆蓋既有密碼；密碼欄位留空但**帳號欄位仍有值**＝視為「不變更密碼」，讀回既有密碼沿用；密碼欄位留空且**帳號欄位也被清空**＝視為使用者主動宣告改用匿名連線，密碼一併清除（帳號清空這個動作本身已經清楚表達意圖，不需要額外的「清除密碼」核取方塊）。
- 「測試連線」比照相同邏輯解析密碼——編輯模式下密碼欄位留空、帳號未清空時，測試連線也要沿用既有密碼，否則對有密碼保護的站點測試連線必然收到 401 失敗，使用者會誤以為是自己設定錯誤。
- 這個解析邏輯**只存在於 `RemoteServerFormScreen`**，不修改 `RemoteServerRepository.updateServer()` 的既有契約（Task 3 已測試過的「`password` 參數即這次呼叫後應該有的密碼狀態」維持不變）——留空判斷屬於表單 UI 語意，不該滲透進資料層介面。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/remote_server_form_screen.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
    required FakeOpdsClient opdsClient,
    RemoteServerProfile? existingProfile,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerFormScreen(
        repository: repository,
        opdsClient: opdsClient,
        existingProfile: existingProfile,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('新增模式：欄位皆為空，類型預設標準 OPDS', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(),
    );
    expect(find.text('新增站點'), findsOneWidget);
    final nameField =
        tester.widget<TextField>(find.byKey(const Key('remote_server_form_name_field')));
    expect(nameField.controller!.text, isEmpty);
  });

  testWidgets('編輯模式：既有欄位預填，密碼欄位維持空白', (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.calibreServer,
      username: 'admin',
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [existing]),
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    expect(find.text('編輯站點'), findsOneWidget);
    final nameField =
        tester.widget<TextField>(find.byKey(const Key('remote_server_form_name_field')));
    expect(nameField.controller!.text, '家用 NAS');
    final urlField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_base_url_field')));
    expect(urlField.controller!.text, 'http://192.168.1.100:8080/opds');
    final usernameField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_username_field')));
    expect(usernameField.controller!.text, 'admin');
    final passwordField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_password_field')));
    expect(passwordField.controller!.text, isEmpty);
    final allowInsecureSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('remote_server_form_allow_insecure_switch')));
    expect(allowInsecureSwitch.value, true);
  });

  testWidgets('測試連線成功時顯示成功文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(testConnectionResult: true),
    );
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();
    expect(find.text('連線成功'), findsOneWidget);
  });

  testWidgets('測試連線失敗時顯示失敗文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(testConnectionResult: false),
    );
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('連線失敗'), findsOneWidget);
  });

  testWidgets('〔審查 Finding 1〕編輯模式測試連線：密碼欄位留空且帳號未清空時，沿用既有密碼發送請求',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository(initialServers: [existing]);
    await repository.addServer(existing, password: 'old-secret');
    final opdsClient = FakeOpdsClient(testConnectionResult: true);

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: opdsClient,
      existingProfile: existing,
    );
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();

    expect(opdsClient.testConnectionPasswords, ['old-secret']);
  });

  testWidgets('新增模式儲存：呼叫 addServer 並帶入輸入的密碼，儲存後關閉畫面', (tester) async {
    final repository = FakeRemoteServerRepository();
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => RemoteServerFormScreen(
            repository: repository,
            opdsClient: FakeOpdsClient(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '公開書庫');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_password_field')), 'secret');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers, hasLength(1));
    expect(servers.single.name, '公開書庫');
    expect(await repository.loadPassword(servers.single.id), 'secret');
  });

  testWidgets(
      '〔審查 Finding 1 修正〕編輯模式儲存：密碼欄位留空且帳號未清空時，保留既有密碼不被洗掉',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository(initialServers: [existing]);
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    // 只改站點名稱，密碼欄位全程不觸碰——這正是 Finding 1 指出的真實回歸
    // 情境：只做不相干的編輯，不該波及既有密碼。
    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '改名後');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers.single.name, '改名後');
    expect(await repository.loadPassword('srv1'), 'old-secret');
  });

  testWidgets('〔審查 Finding 1〕編輯模式儲存：帳號欄位被清空時，密碼隨之一併清除（退回匿名）',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository(initialServers: [existing]);
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    await tester.enterText(
        find.byKey(const Key('remote_server_form_username_field')), '');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers.single.username, isNull);
    expect(await repository.loadPassword('srv1'), isNull);
  });

  testWidgets('編輯模式儲存：密碼欄位輸入新值時覆蓋既有密碼', (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository(initialServers: [existing]);
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    await tester.enterText(
        find.byKey(const Key('remote_server_form_password_field')), 'new-secret');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    expect(await repository.loadPassword('srv1'), 'new-secret');
  });

  testWidgets('名稱或網址為空時儲存顯示驗證錯誤，不呼叫 addServer', (tester) async {
    final repository = FakeRemoteServerRepository();
    await pumpScreen(tester, repository: repository, opdsClient: FakeOpdsClient());

    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    expect(await repository.listServers(), isEmpty);
    expect(find.textContaining('請填寫'), findsOneWidget);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/remote_server_form_screen_test.dart`
Expected: FAIL——Task 7 建立的最小版本沒有任何欄位/按鈕，找不到對應 `Key`。

- [x] **Step 3: 補齊完整表單邏輯**

修改 `app/lib/screens/remote_server_form_screen.dart`（取代 Task 7 的最小版本）：

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// 新增/編輯遠端書庫站點表單（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）。密碼欄位刻意不預填既有密碼（比照
/// `sync_settings_screen.dart` 既有安全慣例）；留空並儲存＝清空既有密碼
/// （退回匿名），與 `RemoteServerRepository` 的密碼語意對稱（見
/// `remote_server_repository.dart` 文件）。
class RemoteServerFormScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient opdsClient;
  final RemoteServerProfile? existingProfile;

  const RemoteServerFormScreen({
    super.key,
    required this.repository,
    required this.opdsClient,
    this.existingProfile,
  });

  @override
  State<RemoteServerFormScreen> createState() => _RemoteServerFormScreenState();
}

class _RemoteServerFormScreenState extends State<RemoteServerFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  late RemoteServerType _type;
  late bool _allowInsecure;

  bool _testing = false;
  String? _testResultText;
  bool _saving = false;
  String? _validationError;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProfile;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _baseUrlController = TextEditingController(text: existing?.baseUrl ?? '');
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _type = existing?.type ?? RemoteServerType.opds;
    _allowInsecure = existing?.allowInsecure ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  RemoteServerProfile _buildProfile() {
    final username = _usernameController.text.trim();
    return RemoteServerProfile(
      id: widget.existingProfile?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      type: _type,
      username: username.isEmpty ? null : username,
      allowInsecure: _allowInsecure,
      createdAt: widget.existingProfile?.createdAt ?? DateTime.now(),
      lastAccessedAt: widget.existingProfile?.lastAccessedAt,
    );
  }

  /// **〔`review-plan-issue-1.md` Finding 1 採納〕** 解析「這次應該實際
  /// 送出的密碼」，供 [_testConnection] 與 [_save] 共用同一套邏輯：
  /// - 密碼欄位有輸入 → 用新輸入的密碼。
  /// - 新增模式且密碼欄位留空 → `null`（匿名連線，語意不變）。
  /// - 編輯模式、密碼欄位留空、帳號欄位已被清空 → `null`（使用者清空
  ///   帳號等同主動宣告改用匿名連線，密碼一併清除）。
  /// - 編輯模式、密碼欄位留空、帳號欄位仍有值 → 讀回既有密碼沿用，
  ///   視為「不變更密碼」——密碼欄位基於安全考量從不預填既有密碼
  ///   （見上方類別文件），若把「留空」直接當成「清空密碼」，使用者
  ///   只是想改個站點名稱就會意外把已儲存的密碼洗掉。
  Future<String?> _resolvePasswordToUse() async {
    if (_passwordController.text.isNotEmpty) return _passwordController.text;
    if (!_isEditing) return null;
    if (_usernameController.text.trim().isEmpty) return null;
    return widget.repository.loadPassword(widget.existingProfile!.id);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResultText = null;
    });
    final password = await _resolvePasswordToUse();
    final success = await widget.opdsClient.testConnection(_buildProfile(), password: password);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResultText = success ? '連線成功' : '連線失敗，請檢查網址/帳密/憑證設定';
    });
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _baseUrlController.text.trim().isEmpty) {
      setState(() => _validationError = '請填寫站點名稱與網址');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final profile = _buildProfile();
    final password = await _resolvePasswordToUse();
    if (_isEditing) {
      await widget.repository.updateServer(profile, password: password);
    } else {
      await widget.repository.addServer(profile, password: password);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯站點' : '新增站點')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('remote_server_form_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: '站點名稱'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_base_url_field'),
              controller: _baseUrlController,
              decoration: const InputDecoration(labelText: '伺服器網址'),
            ),
            const SizedBox(height: 8),
            DropdownButton<RemoteServerType>(
              key: const Key('remote_server_form_type_dropdown'),
              value: _type,
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
              items: const [
                DropdownMenuItem(
                  value: RemoteServerType.opds,
                  child: Text('標準 OPDS'),
                ),
                DropdownMenuItem(
                  value: RemoteServerType.calibreServer,
                  child: Text('原生 Calibre Content Server'),
                ),
                DropdownMenuItem(
                  value: RemoteServerType.calibreWeb,
                  child: Text('Calibre-Web'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_username_field'),
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '帳號（留空代表匿名連線）'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_password_field'),
              controller: _passwordController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _isEditing ? '密碼（留空代表清除既有密碼）' : '密碼',
              ),
            ),
            SwitchListTile(
              key: const Key('remote_server_form_allow_insecure_switch'),
              title: const Text('允許不安全連線（自簽憑證／純 HTTP）'),
              value: _allowInsecure,
              onChanged: (value) => setState(() => _allowInsecure = value),
            ),
            const SizedBox(height: 16),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _validationError!,
                  key: const Key('remote_server_form_validation_error_text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_testResultText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _testResultText!,
                  key: const Key('remote_server_form_test_result_text'),
                ),
              ),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('remote_server_form_test_connection_button'),
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('測試連線'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('remote_server_form_save_button'),
                  onPressed: _saving ? null : _save,
                  child: const Text('儲存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/remote_server_form_screen_test.dart`
Expected: PASS，10 項測試全數通過。

- [x] **Step 5: 執行 Task 7 測試與全專案測試確認零回歸**

Run: `flutter test test/screens/remote_server_list_screen_test.dart && flutter analyze && flutter test`
Expected: 全數通過、`flutter analyze` 乾淨。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/remote_server_form_screen.dart app/test/screens/remote_server_form_screen_test.dart
git commit -m "feat(epic-30): RemoteServerFormScreen 補齊完整表單與測試連線邏輯"
```

---

### Task 9: `LibraryScreen` 進入點與 `main.dart` 接線

**Files:**
- Modify: `app/lib/screens/library_screen.dart:7-27`（imports）、`:35-73`（欄位與建構子）、`:603-691`（`_buildNormalAppBar`）
- Modify: `app/lib/main.dart:1-109`（`main()`）、`:113-149`（`ElinkBookApp`）、`:196-225`（`build()`）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 3（`RemoteServerRepository`）、Task 5（`OpdsClient`）、Task 6（`OpdsHttpClient`）、Task 7（`RemoteServerListScreen`）。

- [x] **Step 1: 寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 新增（放在檔案末尾，`import` 區塊新增對應項目：`import 'package:elinkbook/screens/remote_server_list_screen.dart';`、`import '../support/fake_opds_client.dart';`、`import '../support/fake_remote_server_repository.dart';`）：

```dart
group('遠端書庫進入點', () {
  testWidgets('未提供 remoteServerRepository/opdsClient 時，AppBar 不顯示遠端書庫按鈕', (tester) async {
    final repository = FakeLibraryRepository();
    final importService = FakeBookImportService();
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: importService,
        prefsManager: FakeReaderPrefsManager(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_remote_library_button')), findsNothing);
  });

  testWidgets('提供 remoteServerRepository/opdsClient 時，AppBar 顯示遠端書庫按鈕，點擊後導向 RemoteServerListScreen',
      (tester) async {
    final repository = FakeLibraryRepository();
    final importService = FakeBookImportService();
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: importService,
        prefsManager: FakeReaderPrefsManager(),
        remoteServerRepository: FakeRemoteServerRepository(),
        opdsClient: FakeOpdsClient(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_remote_library_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_remote_library_button')));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteServerListScreen), findsOneWidget);
  });
});
```

**Step 1 附註**：上方測試沿用檔案既有的 `FakeLibraryRepository`／`FakeBookImportService`／`FakeReaderPrefsManager` 建構方式——實際撰寫時請對照檔案開頭既有測試的確切建構參數（例如是否需要額外必填參數），維持與既有測試風格一致，不要重新發明。

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL——`LibraryScreen` 尚無 `remoteServerRepository`/`opdsClient` 參數，編譯錯誤。

- [x] **Step 3: 修改 `LibraryScreen`**

在 `app/lib/screens/library_screen.dart` 的 import 區塊，`import '../reader/reader_prefs_manager.dart';` 之後（即 `library_screen.dart:14` 之後）新增：

```dart
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
```

在 `import 'reader_screen.dart';` 之後（即 `library_screen.dart:27` 之後）新增：

```dart
import 'remote_server_list_screen.dart';
```

在 `class LibraryScreen` 的欄位宣告，緊接在既有 `final SyncCheckpointTrigger? syncCheckpointTrigger;`（`library_screen.dart:47`）之後新增：

```dart
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient? opdsClient;
```

在建構子參數列，緊接在既有 `this.syncCheckpointTrigger,`（`library_screen.dart:67`）之後新增：

```dart
    this.remoteServerRepository,
    this.opdsClient,
```

在 `_buildNormalAppBar()`（`library_screen.dart:603-691`）內，`if (widget.groupFilter == null) IconButton(...)`（管理分類按鈕，`library_screen.dart:662-668`）之後、既有「設定」`IconButton`（`library_screen.dart:669`）之前，新增：

```dart
        if (widget.remoteServerRepository != null && widget.opdsClient != null)
          IconButton(
            key: const Key('library_remote_library_button'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: '遠端書庫',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RemoteServerListScreen(
                    repository: widget.remoteServerRepository!,
                    opdsClient: widget.opdsClient!,
                  ),
                ),
              );
            },
          ),
```

- [x] **Step 4: 執行測試確認 `LibraryScreen` 本身的測試通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS，新增的 2 項測試通過，既有測試零回歸。

- [x] **Step 5: 接線 `main.dart`**

在 `app/lib/main.dart` 開頭 import 區塊，`import 'library/sqlite_library_repository.dart';` 之後新增：

```dart
import 'remote/opds_http_client.dart';
import 'remote/sqlite_remote_server_repository.dart';
```

在 `main()` 函式內，緊接在既有 `final layoutPresetRepository = LayoutPresetRepository(repository.database);`（`main.dart:58`）之後新增：

```dart
  final opdsClient = OpdsHttpClient();
  final remoteServerRepository = SqliteRemoteServerRepository(
    database: repository.database,
    libraryRepository: repository,
  );
```

在 `runApp(ElinkBookApp(...))` 呼叫內，緊接在既有 `layoutPresetRepository: layoutPresetRepository,`（`main.dart:98`）之後新增：

```dart
      remoteServerRepository: remoteServerRepository,
      opdsClient: opdsClient,
```

在 `class ElinkBookApp` 的欄位宣告，緊接在既有 `final LayoutPresetRepository? layoutPresetRepository;`（`main.dart:121`）之後新增：

```dart
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient? opdsClient;
```

（需在檔案開頭新增對應 import：`import 'remote/opds_client.dart';`、`import 'remote/remote_server_repository.dart';`——放在 `import 'reader/...';` 系列之後、`import 'screens/library_screen.dart';` 之前，比照既有字母排序區塊慣例。）

在 `ElinkBookApp` 建構子參數列，緊接在既有 `this.layoutPresetRepository,`（`main.dart:140`）之後新增：

```dart
    this.remoteServerRepository,
    this.opdsClient,
```

在 `_ElinkBookAppState.build()` 內，`LibraryScreen(...)` 呼叫的參數列，緊接在既有 `layoutPresetRepository: widget.layoutPresetRepository,`（`main.dart:214`）之後新增：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        opdsClient: widget.opdsClient,
```

- [x] **Step 6: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-30): LibraryScreen 新增遠端書庫進入點，main.dart 完成接線"
```

---

## Self-Review（撰寫計畫後的檢查）

**1. Spec 覆蓋度**：對照 `spec.md`「站點管理：RemoteServerRepository」（Task 1/3 涵蓋，含刪除防護）、「OPDS 瀏覽與下載：OpdsClient」（Task 4-6 涵蓋，含 `Uri.resolve()`／自簽憑證單次作用域／分頁循環防護）、「UI 落地位置」（Task 7-9 涵蓋，含獨立常駐入口）皆對應到任務；`issues.md` Issue 1 的四項條目（`RemoteServerRepository`／完整 `OpdsClient`／兩個畫面／`LibraryScreen` 入口）全數覆蓋，無缺漏。

**2. Placeholder 掃描**：全文無 TBD／「之後補上」等空話，所有程式碼片段皆為可直接貼上的完整 Dart 程式碼，測試皆有具體斷言。Task 9 的 Step 3/5 因是對既有大檔案的精確定位修改，採用「緊接在既有某行之後」的描述方式（而非整段重寫），符合大型既有檔案的常見修改慣例。

**3. 型別一致性**：`RemoteServerProfile`／`RemoteServerType` 在 Task 1（定義）、Task 3（SQLite/Fake）、Task 6-9（消費端）用字一致；`OpdsFeed`/`OpdsNavigationLink`/`OpdsEntry`/`OpdsAcquisition` 在 Task 4（定義）、Task 5-6（介面/實作）、Task 7-8（Fake/UI）一致；`RemoteServerRepository`/`RemoteServerDeletionBlockedException`/`OpdsClient`/`OpdsDownloadCancellationToken` 各自的方法簽章在定義與所有消費處一致。

**4. 邊界原則落實**：`SqliteRemoteServerRepository` 全程未直接觸碰 `books` 表，一律透過注入的 `LibraryRepository`（Task 2 新增的 `listUndownloadedBooksForRemoteServer`），符合 Global Constraints 與既有「`books`/`groups` 兩張表唯一存取入口」原則。

**5. 任務間依賴**：Task 7 刻意先建立 `RemoteServerFormScreen` 的最小可編譯版本（讓 Task 7 的測試能通過而不依賴尚未寫的 Task 8），Task 8 再補齊完整邏輯並重新驗證 Task 7 的測試不受影響——這個「先最小可編譯、後補完整」的安排已在 Task 7/8 文字中明確說明，避免被誤認為 Task 7 本身有缺陷。

**6. `review-plan-issue-1.md` 審查修訂**（2026-08-18，核准並附帶建議，已全數採納並修訂本計畫）：Finding 2（`OpdsFeedParser` 缺 MIME→副檔名退回判定，核實違反 `spec.md:138`）與 Finding 3（`OpdsHttpClient.downloadBook` 串流中途例外未清暫存檔，核實違反 spec.md「下載失敗時立即清除暫存檔」）皆為真實缺漏，已修正 Task 4／Task 6 程式碼與測試。Finding 4（href `trim()`）為低風險防禦性修正，已採納。Finding 1（編輯模式密碼語意）核實問題成立，但**未採用**審查建議在 `RemoteServerRepository.updateServer()` 新增 `clearPassword` 參數——改在 `RemoteServerFormScreen` 這一層自行解析「這次要送出的密碼」，維持 Task 3 已測試過的簡單 Repository 契約不變，理由是「留空即不變更／帳號清空即退回匿名」屬於表單 UI 語意，不該滲透進資料層介面。

---

**Plan complete and saved to `docs/epics/epic-30-calibre-remote-library/plans/plan-issue-1.md`.** Two execution options:

**1. Subagent-Driven (recommended)** - 逐 Task 派遣新的 subagent 執行，每個 Task 完成後進行審查，快速迭代

**2. Inline Execution** - 在本次對話中直接依 Task 順序批次執行，每個 Task 結束設檢查點

**Which approach?**
