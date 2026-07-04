# Issue 1 實作計劃：LibraryRepository 資料層（sqflite CRUD）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 建立圖書庫的本機 sqflite 資料庫（`books`/`groups` 兩張表），並實作 `LibraryRepository` 介面，提供書籍與分類群組的完整 CRUD、排序查詢、分類篩選——供後續 Issue 4（`BookImportService`）、Issue 5（`LibraryScreen`）等工單使用。

**架構：** 純 Dart 資料層，不涉及原生程式碼或 UI。`Book`/`BookGroup` 為不可變的值物件，各自有 `toMap()`/`fromMap()` 與 sqflite 的 `Map<String, Object?>` 列資料互轉。`SqliteLibraryRepository` 是 `LibraryRepository` 介面的唯一實作，內部持有一個 `Database`（來自 `package:sqflite`）。正式執行時資料庫檔案路徑由 `defaultLibraryDatabasePath()`（用 `path_provider`）決定；單元測試改用 `sqflite_common_ffi` 的 `databaseFactoryFfi` 搭配 `inMemoryDatabasePath`，讓整個資料層可以在不啟動模擬器/裝置的情況下用 `flutter test` 驗證（`sqflite` 套件的 `openDatabase()` 一律委派給全域的 `databaseFactory`，測試只需在啟動時覆寫這個全域變數）。

**技術棧：** Flutter（Dart）、`sqflite`、`sqflite_common_ffi`（僅供測試）、`path`、`path_provider`（僅供正式執行時決定資料庫路徑）。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`（epic-0 已建立）。
- 資料模型欄位與 `LibraryRepository` 介面簽章須與 `docs/epics/epic-1-library/spec.md`「資料模型」「介面」章節完全一致。
- `Book.format` 使用本工單新增的 `BookFileFormat`（`epub`/`pdf`/`txt`）——**不可**修改既有的 `app/lib/reader/book_format.dart` 的 `BookFormat`（`epub`/`pdf`/`unknown`）。那個列舉服務 `ReaderScreen` 的原生渲染分派，目前只有 EPUB/PDF 有對應原生視圖，TXT 渲染引擎（`epic-11-txt-engine`）尚未開始；圖書庫資料層需要完整表達 FR-01 的三種格式，因此另外定義獨立的列舉，兩者刻意不共用、互不影響。
- `未分類`（`BookGroup.uncategorized`）為系統保留群組：不可重新命名、不可刪除。
- 所有例外訊息（`LibraryRepositoryException.message`）須為正體中文。
- 本工單**不得**新增任何 UI 畫面、原生程式碼或 `file_picker`/原生 MethodChannel 呼叫——那些屬於 Issue 2、3、4、5 的範圍。

---

### Task 1：資料模型（`Book`/`BookGroup`/列舉）

**Files:**
- Create: `app/lib/library/models/library_enums.dart`
- Create: `app/lib/library/models/book_group.dart`
- Create: `app/lib/library/models/book.dart`
- Test: `app/test/library/models/book_test.dart`

**Interfaces:**
- Consumes: 無（獨立於既有程式碼，`BookFileFormat` 刻意不依賴 `app/lib/reader/book_format.dart` 的 `BookFormat`）
- Produces: `enum BookFileFormat { epub, pdf, txt }`、`enum BookSource { local, googleDrive, oneDrive }`、`enum LibrarySortBy { lastRead, createTime, author, title }`、`class BookGroup { static const uncategorized = '未分類'; final String name; }`、`class Book { ... toMap()/fromMap() ... }`（完整欄位見下方程式碼）——供 Task 2-4 與後續 Issue 4/5 使用。

- [ ] **Step 1：撰寫 `Book.toMap()`/`fromMap()` 往返測試（先寫測試，此時 import 的檔案還不存在）**

建立 `app/test/library/models/book_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  test('Book toMap/fromMap 往返後所有欄位值不變', () {
    final book = Book(
      id: 'b1',
      title: '測試書名',
      author: '測試作者',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      coverPath: '/data/covers/b1.png',
      progress: 42.5,
      groupName: '經典名著',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.id, book.id);
    expect(restored.title, book.title);
    expect(restored.author, book.author);
    expect(restored.format, book.format);
    expect(restored.filePath, book.filePath);
    expect(restored.source, book.source);
    expect(restored.coverPath, book.coverPath);
    expect(restored.progress, book.progress);
    expect(restored.groupName, book.groupName);
    expect(restored.createTime, book.createTime);
    expect(restored.lastReadTime, book.lastReadTime);
  });

  test('author/coverPath 為 null、其餘欄位使用預設值時往返仍正確', () {
    final book = Book(
      id: 'b2',
      title: 'PDF 書籍',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.author, isNull);
    expect(restored.coverPath, isNull);
    expect(restored.progress, 0);
    expect(restored.groupName, '未分類');
  });

  test('TXT 格式與雲端來源列舉值可正確往返', () {
    final book = Book(
      id: 'b3',
      title: 'TXT 書籍',
      format: BookFileFormat.txt,
      filePath: '/storage/emulated/0/book.txt',
      source: BookSource.googleDrive,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.format, BookFileFormat.txt);
    expect(restored.source, BookSource.googleDrive);
  });
}
```

- [ ] **Step 2：執行測試確認失敗（找不到 library 套件檔案）**

Run（於 `app/` 目錄下）：
```bash
flutter test test/library/models/book_test.dart
```
Expected: 編譯錯誤，訊息包含 `Target of URI doesn't exist: 'package:elinkbook/library/models/book.dart'`（或等效的「找不到檔案」錯誤）。

- [ ] **Step 3：建立列舉檔**

建立 `app/lib/library/models/library_enums.dart`：

```dart
/// 圖書庫書籍的檔案格式。獨立於 `reader/book_format.dart` 的 `BookFormat`——
/// 後者只服務 `ReaderScreen` 的原生渲染分派（目前僅 epub/pdf 有對應原生
/// 視圖）；圖書庫資料層需要完整表達 FR-01 的三種支援格式（含尚未有渲染
/// 引擎的 TXT，由 epic-11-txt-engine 補上），因此另外定義、不與其共用。
enum BookFileFormat { epub, pdf, txt }

/// 書籍的匯入來源。本 epic（epic-1-library）僅會產生 [local]；
/// [googleDrive]/[oneDrive] 為後續雲端匯入 Epic 預留的欄位。
enum BookSource { local, googleDrive, oneDrive }

/// 書架排序方式（FR-26）。
enum LibrarySortBy { lastRead, createTime, author, title }
```

- [ ] **Step 4：建立 `BookGroup`**

建立 `app/lib/library/models/book_group.dart`：

```dart
/// 書籍分類群組（FR-33）。[uncategorized]（「未分類」）為系統保留群組，
/// 不可重新命名或刪除——書籍未歸類、或原群組被刪除時皆歸入此群組。
class BookGroup {
  static const String uncategorized = '未分類';

  final String name;

  const BookGroup(this.name);

  Map<String, Object?> toMap() => {'name': name};

  factory BookGroup.fromMap(Map<String, Object?> map) =>
      BookGroup(map['name'] as String);
}
```

- [ ] **Step 5：建立 `Book`**

建立 `app/lib/library/models/book.dart`：

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

  /// 本 epic 固定為 `0`（真實閱讀進度回寫屬於 epic-8-sync，見 design.md）。
  final double progress;

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
      groupName: map['groupName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int),
      lastReadTime:
          DateTime.fromMillisecondsSinceEpoch(map['lastReadTime'] as int),
    );
  }
}
```

- [ ] **Step 6：執行測試確認通過**

Run：
```bash
flutter test test/library/models/book_test.dart
```
Expected: `00:0X +3: All tests passed!`（3 項測試皆通過）。

- [ ] **Step 7：靜態分析確認無警告**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/models/library_enums.dart app/lib/library/models/book_group.dart app/lib/library/models/book.dart app/test/library/models/book_test.dart
git commit -m "Add Book/BookGroup data models for library repository"
```

---

### Task 2：加入 sqflite 依賴，建立 `SqliteLibraryRepository`（schema + 基本 CRUD）

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/library/library_repository.dart`
- Create: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: `Book`/`BookGroup`/`BookFileFormat`/`BookSource`/`LibrarySortBy`（Task 1 產出）
- Produces: `abstract class LibraryRepository`（含本工單完整簽章，Task 3、4 陸續補上實作與測試）、`class LibraryRepositoryException implements Exception`、`class SqliteLibraryRepository implements LibraryRepository`，其中 `static Future<SqliteLibraryRepository> open(String path)` 與 `Future<void> close()` 供後續 Issue 4/5 建立/釋放資料庫連線使用；`Future<String> defaultLibraryDatabasePath()`（頂層函式）供正式環境決定 `library.db` 實際存放路徑。

- [ ] **Step 1：新增 sqflite 相關依賴**

Run（於 `app/` 目錄下）：
```bash
flutter pub add sqflite path
flutter pub add sqflite_common_ffi --dev
```
Expected: 終端機顯示三個套件皆已成功解析並加入 `pubspec.yaml`（`sqflite`、`path` 加入 `dependencies`；`sqflite_common_ffi` 加入 `dev_dependencies`）。

- [ ] **Step 2：撰寫 `LibraryRepository` 介面與例外類別（先定義介面，尚無實作）**

建立 `app/lib/library/library_repository.dart`：

```dart
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';

/// 圖書庫資料的存取介面；`books`/`groups` 兩張表的唯一存取入口（見
/// docs/epics/epic-1-library/spec.md「介面」章節）。
abstract class LibraryRepository {
  Future<Book> insertBook(Book book);
  Future<void> updateBook(Book book);
  Future<void> deleteBook(String id);
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  });

  Future<List<BookGroup>> listGroups();
  Future<void> upsertGroup(String name);
  Future<void> renameGroup(String oldName, String newName);
  Future<void> deleteGroup(String name);
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
```

- [ ] **Step 3：撰寫基本 CRUD 的失敗測試**

建立 `app/test/library/sqlite_library_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

Book _book(
  String id, {
  String title = '書名',
  String? author,
  BookFileFormat format = BookFileFormat.epub,
  double progress = 0,
  String groupName = '未分類',
  int createTime = 1000,
  int lastReadTime = 1000,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: progress,
    groupName: groupName,
    createTime: DateTime.fromMillisecondsSinceEpoch(createTime),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(lastReadTime),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  });

  tearDown(() async {
    await repository.close();
  });

  test('insertBook 後可用 listBooks 取回', () async {
    await repository.insertBook(_book('b1', title: '紅樓夢'));

    final books = await repository.listBooks();

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
  });

  test('updateBook 更新既有書籍的欄位', () async {
    await repository.insertBook(_book('b1', title: '舊書名'));

    await repository.updateBook(_book('b1', title: '新書名'));

    final books = await repository.listBooks();
    expect(books.single.title, '新書名');
  });

  test('deleteBook 移除指定書籍', () async {
    await repository.insertBook(_book('b1'));
    await repository.insertBook(_book('b2'));

    await repository.deleteBook('b1');

    final books = await repository.listBooks();
    expect(books.map((b) => b.id), ['b2']);
  });
}
```

- [ ] **Step 4：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected: 編譯錯誤，找不到 `package:elinkbook/library/sqlite_library_repository.dart`。

- [ ] **Step 5：實作 `SqliteLibraryRepository`（schema + `insertBook`/`updateBook`/`deleteBook`/`listBooks`，排序/篩選先給最小可行實作）**

建立 `app/lib/library/sqlite_library_repository.dart`：

```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'library_repository.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';

/// 圖書庫在真實裝置上資料庫檔案的預設路徑（App 文件目錄下的
/// `library.db`）。僅供正式執行時使用；單元測試改用
/// `sqflite_common_ffi` 的 `inMemoryDatabasePath`，不會呼叫到這個函式
/// （`path_provider` 需要平台 channel，無法在純 Dart 測試環境執行）。
Future<String> defaultLibraryDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'library.db');
}

class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  SqliteLibraryRepository._(this._db);

  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
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
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
      },
    );
    return SqliteLibraryRepository._(db);
  }

  Future<void> close() => _db.close();

  @override
  Future<Book> insertBook(Book book) async {
    await _db.insert('books', book.toMap());
    return book;
  }

  @override
  Future<void> updateBook(Book book) async {
    await _db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  @override
  Future<void> deleteBook(String id) async {
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) async {
    final rows = await _db.query(
      'books',
      where: groupFilter != null ? 'groupName = ?' : null,
      whereArgs: groupFilter != null ? [groupFilter] : null,
      orderBy: _orderByClause(sortBy),
    );
    return rows.map(Book.fromMap).toList();
  }

  String _orderByClause(LibrarySortBy sortBy) {
    switch (sortBy) {
      case LibrarySortBy.lastRead:
        return 'lastReadTime DESC';
      case LibrarySortBy.createTime:
        return 'createTime DESC';
      case LibrarySortBy.author:
        return 'author ASC';
      case LibrarySortBy.title:
        return 'title ASC';
    }
  }

  @override
  Future<List<BookGroup>> listGroups() async {
    final rows = await _db.query('groups', orderBy: 'name ASC');
    return rows.map(BookGroup.fromMap).toList();
  }

  @override
  Future<void> upsertGroup(String name) async {
    await _db.insert(
      'groups',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    final existing =
        await _db.query('groups', where: 'name = ?', whereArgs: [newName]);
    if (existing.isNotEmpty) {
      throw LibraryRepositoryException('分類「$newName」已存在');
    }
    await _db.transaction((txn) async {
      await txn.insert('groups', {'name': newName});
      await txn.update(
        'books',
        {'groupName': newName},
        where: 'groupName = ?',
        whereArgs: [oldName],
      );
      await txn.delete('groups', where: 'name = ?', whereArgs: [oldName]);
    });
  }

  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
    await _db.transaction((txn) async {
      await txn.update(
        'books',
        {'groupName': BookGroup.uncategorized},
        where: 'groupName = ?',
        whereArgs: [name],
      );
      await txn.delete('groups', where: 'name = ?', whereArgs: [name]);
    });
  }
}
```

（`renameGroup`/`deleteGroup`/`listGroups`/`upsertGroup` 的完整測試留給 Task 4；本步驟先把整個類別實作完整，Task 3、4 只需新增測試即可，避免中途再回頭改介面。）

- [ ] **Step 6：執行測試確認通過**

Run：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 7：靜態分析確認無警告**

Run：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "Add SqliteLibraryRepository with schema and basic book CRUD"
```

---

### Task 3：`listBooks` 排序與分類篩選測試

**Files:**
- Modify: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: `SqliteLibraryRepository`（Task 2 產出，`listBooks(sortBy:, groupFilter:)` 實作已在 Task 2 完成，本工單只補測試）
- Produces: 無新公開介面；驗證 Task 2 已實作的排序/篩選行為符合 spec.md 要求，供 Issue 5（`LibraryScreen` 排序/分類 UI）放心依賴。

- [ ] **Step 1：新增排序與分類篩選測試**

在 `app/test/library/sqlite_library_repository_test.dart` 的 `main()` 函式內、既有三項 CRUD 測試之後，新增：

```dart
  group('listBooks 排序', () {
    setUp(() async {
      await repository.insertBook(_book(
        'b1',
        title: '西遊記',
        author: '吳承恩',
        createTime: 3000,
        lastReadTime: 1000,
      ));
      await repository.insertBook(_book(
        'b2',
        title: '三國演義',
        author: '羅貫中',
        createTime: 1000,
        lastReadTime: 3000,
      ));
      await repository.insertBook(_book(
        'b3',
        title: '水滸傳',
        author: '施耐庵',
        createTime: 2000,
        lastReadTime: 2000,
      ));
    });

    test('lastRead：最近閱讀優先', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.lastRead);
      expect(books.map((b) => b.id).toList(), ['b2', 'b3', 'b1']);
    });

    test('createTime：最近建立優先', () async {
      final books =
          await repository.listBooks(sortBy: LibrarySortBy.createTime);
      expect(books.map((b) => b.id).toList(), ['b1', 'b3', 'b2']);
    });

    test('author：依作者排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.author);
      expect(books.map((b) => b.author).toList(), ['吳承恩', '施耐庵', '羅貫中']);
    });

    test('title：依書名排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.title);
      expect(books.map((b) => b.title).toList(), ['三國演義', '水滸傳', '西遊記']);
    });
  });

  test('listBooks 依 groupFilter 篩選', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks(groupFilter: '經典名著');

    expect(books.map((b) => b.id).toList(), ['b1']);
  });

  test('listBooks 不指定 groupFilter 時回傳全部', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks();

    expect(books, hasLength(2));
  });
```

- [ ] **Step 2：執行測試確認通過**

Run：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected: `00:0X +9: All tests passed!`（3 項既有 CRUD 測試 + 6 項新增排序/篩選測試）。

若 `author`/`title` 排序測試失敗，檢查是否為 SQLite 預設 `BINARY` collation 對中文字採 Unicode code point 排序所致——本測試選用的作者/書名文字已依 code point 順序設計（吳 U+5433 < 施 U+65BD < 羅 U+7F85；三 U+4E09 < 水 U+6C34 < 西 U+897F），若替換測試資料需重新確認對應的 code point 順序。

- [ ] **Step 3：Commit**

```bash
git add app/test/library/sqlite_library_repository_test.dart
git commit -m "Add listBooks sort and group filter tests"
```

---

### Task 4：群組管理（`upsertGroup`/`renameGroup`/`deleteGroup`）測試

**Files:**
- Modify: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: `SqliteLibraryRepository`（Task 2 產出，群組管理方法實作已在 Task 2 完成，本工單只補測試）
- Produces: 無新公開介面；驗證保留群組保護、刪除/重新命名時書籍歸位邏輯符合 spec.md 要求，供 Issue 7（分類群組管理 UI）放心依賴。

- [ ] **Step 1：新增群組管理測試**

在 `app/test/library/sqlite_library_repository_test.dart` 的 `main()` 函式內、Task 3 新增的測試之後，新增：

```dart
  group('群組管理', () {
    test('upsertGroup 新增群組後出現在 listGroups', () async {
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.map((g) => g.name), containsAll(['未分類', '古典奇幻']));
    });

    test('upsertGroup 對已存在的名稱不重複新增', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.where((g) => g.name == '古典奇幻'), hasLength(1));
    });

    test('deleteGroup 後，該群組下書籍改歸「未分類」', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.deleteGroup('古典奇幻');

      final books = await repository.listBooks();
      expect(books.single.groupName, '未分類');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('deleteGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.deleteGroup('未分類'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 成功後，書籍歸屬同步更新為新名稱', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.renameGroup('古典奇幻', '奇幻小說');

      final books = await repository.listBooks();
      expect(books.single.groupName, '奇幻小說');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), contains('奇幻小說'));
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('renameGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.renameGroup('未分類', '新名稱'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 目標名稱已存在時拋出例外', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('文言經典');

      expect(
        () => repository.renameGroup('古典奇幻', '文言經典'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
  });
```

記得在 `import 'package:elinkbook/library/library_repository.dart';`（若尚未 import）加入檔案開頭，供 `LibraryRepositoryException` 型別參考使用。

- [ ] **Step 2：執行測試確認通過**

Run：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected: `00:0X +16: All tests passed!`（Task 2 的 3 項 + Task 3 的 6 項 + 本工單新增的 7 項）。

- [ ] **Step 3：靜態分析確認無警告**

Run：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4：Commit**

```bash
git add app/test/library/sqlite_library_repository_test.dart
git commit -m "Add group management tests for SqliteLibraryRepository"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：`spec.md`「介面」章節定義的 `Book`/`BookGroup`/三個列舉/`LibraryRepository`/`LibraryRepositoryException` 均已對應到 Task 1、2；`issues.md` Issue 1 要求的全部單元測試（基本 CRUD、四種排序、groupFilter 篩選、`deleteGroup` 書籍歸位、`deleteGroup('未分類')` 拋例外、`renameGroup` 重複名稱與「未分類」重新命名行為）均已對應到 Task 2、3、4。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出，無 TBD/TODO。
- **型別/命名一致性**：`Book`/`BookGroup`/`BookFileFormat`/`BookSource`/`LibrarySortBy`/`LibraryRepository`/`LibraryRepositoryException`/`SqliteLibraryRepository` 在 Task 1-4 間欄位與方法簽章一致，且與 `spec.md`「介面」章節定義相符。
- **範圍邊界**：刻意不修改 `app/lib/reader/book_format.dart`（見「全域限制條件」說明原因），避免與既有 epic-0 契約及其測試（`test/reader/book_format_test.dart` 明確斷言 `.txt` 回傳 `unknown`）衝突。

## 文件審查回應紀錄（`review-plan-issue-1.md`）

- **Important #1（`Book.format` 型別與 `spec.md` 衝突）**：查證屬實——`spec.md` 原本寫 `Book.format` 沿用既有 `BookFormat`，與本計劃新增獨立 `BookFileFormat` 的決定不一致，是撰寫計劃時忘記回頭同步規格書。已採納，修正 `spec.md` 改為 `BookFileFormat` 並補充與 `reader/book_format.dart` 的關係說明。**未採用**審查建議新增的 `toBookFormat()` 轉接方法——查證 `app/lib/screens/reader_screen.dart:47` 的 `ReaderScreen.build()` 是自行呼叫 `detectBookFormat(widget.filePath)` 判斷格式，不吃外部傳入的格式參數，因此 `LibraryScreen` 導覽到 `ReaderScreen` 時不需要、也沒有呼叫端會用到這個轉接方法，屬於 YAGNI。
- **Minor #1（`BookSource` 序列化值命名不一致）**：查證屬實，`design.md` 寫 `google_drive`/`onedrive`（snake_case），與 `spec.md`/本計劃的 `googleDrive`/`oneDrive`（camelCase enum `.name`）不一致。已採納，修正 `design.md` 措辭以 `spec.md`（唯一事實來源）為準；本計劃程式碼原本就是對的，不需改動。
