# Issue 5 實作計劃：`LibraryScreen` 串接真實圖書庫

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 把 `LibraryScreen` 從固定範例書籍清單（`sample_books.dart`）改為讀取 `LibraryRepository`（Issue 1）的真實資料：新增匯入按鈕（觸發 Issue 4 的 `BookImportService`）、書架 grid（每列 6 本）與列表兩種呈現、空清單狀態，並讓點擊書籍項目能導航至既有 `ReaderScreen(filePath: ...)`。

**架構：** `LibraryScreen` 改為 `StatefulWidget`，建構參數新增 `LibraryRepository repository`／`BookImportService importService`（直接建構子注入，不引入 DI 套件，與既有 `ReaderScreen`/`EpubReaderView` 的建構參數風格一致）。畫面狀態機為「載入中 → 空清單 / 有書清單（grid 或 list，依內部 `LibraryViewMode` 狀態）」；匯入按鈕呼叫 `file_picker` 選檔（`allowMultiple: true`）取得 `content://` URI 清單，交給 `BookImportService.importFiles()`，完成後重新載入清單。`main.dart` 改為非同步 `main()`，於啟動時建立真實的 `SqliteLibraryRepository`/`BookImportServiceImpl` 並注入 `ElinkBookApp`。排序下拉選單與檢視模式的 `SharedPreferences` 持久化屬於 Issue 6，本工單的檢視模式切換只是畫面內部狀態（不持久化）。分類群組 tab 屬於 Issue 7，本工單 `listBooks()` 一律取全部（`groupFilter: null`）。

**技術棧：** Flutter（Dart）、`file_picker`（已釘選 `^11.0.2`，靜態 API `FilePicker.pickFiles(...)`，無 `.platform` 存取器）、`sqflite`（透過已完成的 `SqliteLibraryRepository`）、`flutter_test`（widget test，全部使用假的 `LibraryRepository`/`BookImportService`，不需真實裝置）、`integration_test`（Task 3，需真實裝置/模擬器）。

## ⚠️ 執行前環境確認事項

Task 1、2 為純 Dart widget test，不需裝置。Task 3 的 `integration_test` 須在真實 Android 模擬器/裝置上執行——執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器。

## 全域限制條件

- `LibraryScreen` 建構參數為 `LibraryScreen({required LibraryRepository repository, required BookImportService importService})`——與 `docs/epics/epic-1-library/spec.md` 的 `LibraryRepository`/`BookImportService` 介面簽章保持一致，不得另外新增與資料存取相關的公開建構參數。
- 書架模式：`GridView` 每列固定 6 本封面（`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, ...)`）。列表模式：封面縮圖 + 標題/作者 + 進度百分比（固定顯示 `0%`，因為 `Book.progress` 本 epic 固定為 `0`）+ 來源圖示（本 epic 只會出現本地圖示）。
- 空清單狀態文字須為「尚未匯入書籍」，並提供匯入按鈕。
- 點擊書籍項目導航至既有 `ReaderScreen(filePath: book.filePath)`——`filePath` 直接取資料庫欄位（URI 或路徑字串），不做任何轉換。
- 匯入按鈕呼叫 `FilePicker.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['epub', 'pdf', 'txt'])`，取出 `picked.files.map((f) => f.identifier).whereType<String>()` 交給 `BookImportService.importFiles()`；**不得**呼叫尚未實作的 `importFolder()`（Issue 8 範圍，呼叫會拋出 `UnimplementedError`）。
- `sample_books.dart`／`stageSampleBookFile()` 須從程式碼庫**完全移除**；`test/fixtures/sample.epub`/`sample.pdf` 這兩個 asset 檔案本身**保留**，供 widget/integration test 繼續使用。
- Widget test 一律用假的 `LibraryRepository`/`BookImportService` 實作驅動（見 `docs/epics/epic-1-library/spec.md`「測試決策」：「皆可用假的 LibraryRepository 實作驅動，不需真實裝置」），**不得**在 widget test 中觸發真正的 `file_picker` 原生呼叫。
- `integration_test` 須使用真正的 `content://` URI（透過 Issue 4 已新增的原生測試專用方法 `createTestContentUri`，而非 `Uri.file(...)` 產生的 `file://`），並透過真正的 `BookImportServiceImpl.importFiles()` 匯入後才能在畫面上驗證點擊渲染，理由與 Issue 4 相同：`file://`/`content://` 內部走不同程式碼路徑，不可讓其中一種替代測試被無聲繼承。
- 排序下拉選單、檢視模式持久化（`SharedPreferences`）、分類群組 tab **不在本工單範圍**（分別是 Issue 6、Issue 7），`listBooks()` 呼叫一律不帶 `groupFilter`（等同全部），排序沿用 `LibraryRepository.listBooks()` 的預設值（`LibrarySortBy.lastRead`）。
- 所有 UI 文字、錯誤訊息與程式註解維持正體中文。

---

### Task 1：`LibraryScreen` 資料層串接骨架 + 空清單狀態 + 移除範例書籍佔位邏輯

**Files:**
- Create: `app/test/support/fake_library_repository.dart`
- Create: `app/test/support/fake_book_import_service.dart`
- Modify: `app/lib/screens/library_screen.dart`（整檔改寫）
- Modify: `app/lib/main.dart`（整檔改寫）
- Modify: `app/test/screens/library_screen_test.dart`（整檔改寫）
- Modify: `app/test/navigation_test.dart`
- Delete: `app/lib/screens/sample_books.dart`

**Interfaces:**
- Consumes：`LibraryRepository`（`app/lib/library/library_repository.dart`）、`BookImportService`（`app/lib/library/book_import_service.dart`）、`Book`（`app/lib/library/models/book.dart`）、`SqliteLibraryRepository.open()`/`defaultLibraryDatabasePath()`（`app/lib/library/sqlite_library_repository.dart`）、`BookImportServiceImpl`（`app/lib/library/book_import_service_impl.dart`）、`ReaderScreen(filePath: String)`（既有，不異動）。
- Produces：`LibraryScreen({required LibraryRepository repository, required BookImportService importService})`；`Key('library_import_button')`、`Key('library_empty_import_button')`、`Key('book_item_<book.id>')`——Task 2、3 沿用這組 Key，Task 2 只會改寫 `_buildBookList()` 內部渲染方式（Grid/List 雙重呈現），不會更動這些既有 Key 的語意。`FakeLibraryRepository`/`FakeBookImportService`——Task 2 沿用同一組假實作驅動 widget test。

- [ ] **Step 1：建立假的 `LibraryRepository`/`BookImportService` 測試替身**

`app/test/support/fake_library_repository.dart`：

```dart
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的記憶體內 [LibraryRepository] 假實作，避免 widget
/// test 依賴真實 sqflite（見 docs/epics/epic-1-library/spec.md「測試決策」）。
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({List<Book> initialBooks = const []})
      : _books = List.of(initialBooks);

  final List<Book> _books;

  @override
  Future<Book> insertBook(Book book) async {
    _books.add(book);
    return book;
  }

  @override
  Future<void> updateBook(Book book) async {
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index != -1) _books[index] = book;
  }

  @override
  Future<void> deleteBook(String id) async {
    _books.removeWhere((b) => b.id == id);
  }

  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) async {
    if (groupFilter == null) return List.of(_books);
    return _books.where((b) => b.groupName == groupFilter).toList();
  }

  @override
  Future<List<BookGroup>> listGroups() async =>
      const [BookGroup(BookGroup.uncategorized)];

  @override
  Future<void> upsertGroup(String name) async {}

  @override
  Future<void> renameGroup(String oldName, String newName) async {}

  @override
  Future<void> deleteGroup(String name) async {}
}
```

`app/test/support/fake_book_import_service.dart`：

```dart
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';

/// 供 widget test 使用的 [BookImportService] 假實作。Widget test 只驗證匯入
/// 按鈕存在（見 docs/epics/epic-1-library/spec.md「測試決策」：widget test
/// 不需真實裝置），不會實際呼叫這兩個方法，因此回傳空清單即可。
class FakeBookImportService implements BookImportService {
  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    String? folderName,
  }) async =>
      [];

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) async =>
      [];
}
```

- [ ] **Step 2：寫失敗測試（空清單狀態）**

整檔改寫 `app/test/screens/library_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  testWidgets('圖書庫為空時顯示「尚未匯入書籍」提示與匯入按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(
      find.byKey(const Key('library_empty_import_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library_import_button')), findsOneWidget);
  });
}
```

- [ ] **Step 3：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（編譯錯誤——`LibraryScreen()` 目前是無參數的 `const` 建構子，缺少 `repository`/`importService` 必要參數）

- [ ] **Step 4：改寫 `LibraryScreen`（骨架版：載入、空清單、匯入動作、最簡清單渲染）**

整檔改寫 `app/lib/screens/library_screen.dart`：

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。書架/列表雙重呈現與書籍卡片渲染由
/// Issue 5 Task 2 補上；本檔案先建立資料載入、空清單狀態與匯入動作骨架。
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book>? _books;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await widget.repository.listBooks();
    if (!mounted) return;
    setState(() => _books = books);
  }

  Future<void> _pickAndImportFiles() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final uris =
        picked.files.map((f) => f.identifier).whereType<String>().toList();
    if (uris.isEmpty) return;
    await widget.importService.importFiles(uris);
    await _loadBooks();
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            key: const Key('library_import_button'),
            icon: const Icon(Icons.add),
            tooltip: '匯入書籍',
            onPressed: _pickAndImportFiles,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(books),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: _pickAndImportFiles,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(List<Book> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return ListTile(
          key: Key('book_item_${book.id}'),
          title: Text(book.title),
          subtitle: Text(book.author ?? ''),
          onTap: () => _openBook(book),
        );
      },
    );
  }
}
```

（`_buildBookList` 這個最簡版本會在 Task 2 被 Grid/List 雙重呈現取代；`book_item_<id>` 這個 Key 維持不變。）

- [ ] **Step 5：改寫 `main.dart`（非同步啟動、真實依賴注入）**

整檔改寫 `app/lib/main.dart`：

```dart
import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  runApp(
    ElinkBookApp(repository: repository, importService: importService),
  );
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(repository: repository, importService: importService),
    );
  }
}
```

- [ ] **Step 6：刪除範例書籍佔位邏輯，修正既有導航測試**

刪除 `app/lib/screens/sample_books.dart`。

整檔改寫 `app/test/navigation_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';

void main() {
  testWidgets('點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);

    // 點擊 AppBar 的返回按鈕以代替 tester.pageBack()，增加測試強健度
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
```

- [ ] **Step 7：執行測試，確認通過**

Run: `flutter test`
Expected: 全數 PASS（含新的空清單測試、修正後的 navigation_test.dart；`sample_books.dart` 相關的舊測試已被取代，不應再有任何檔案引用它）

- [ ] **Step 8：靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart app/test/navigation_test.dart app/test/support/fake_library_repository.dart app/test/support/fake_book_import_service.dart
git rm app/lib/screens/sample_books.dart
git commit -m "feat: wire LibraryScreen to real LibraryRepository/BookImportService"
```

---

### Task 2：書架 Grid（每列 6 本）與列表雙重呈現 + 書籍卡片渲染

**Files:**
- Modify: `app/lib/library/models/library_enums.dart`（新增 `LibraryViewMode`）
- Modify: `app/lib/screens/library_screen.dart`（取代 Task 1 的最簡 `_buildBookList`，新增檢視模式切換鈕與書籍卡片 widget）
- Modify: `app/test/screens/library_screen_test.dart`（新增測試）

**Interfaces:**
- Consumes：Task 1 的 `LibraryScreen({required repository, required importService})`、`Key('book_item_<id>')`、`FakeLibraryRepository`/`FakeBookImportService`。
- Produces：`enum LibraryViewMode { grid, list }`（`app/lib/library/models/library_enums.dart`，對應 `spec.md` 資料模型章節）——Issue 6 會沿用此列舉做 `SharedPreferences` 持久化，本工單只使用畫面內部 state，不做持久化。`Key('library_view_mode_toggle')`、`Key('library_grid_view')`、`Key('library_list_view')`。

- [ ] **Step 1：新增 `LibraryViewMode` 列舉**

在 `app/lib/library/models/library_enums.dart` 檔案末尾新增：

```dart

/// 書架檢視模式（FR-03）。切換按鈕與畫面渲染分支屬於本 issue（Issue 5）；
/// 選擇的持久化（`SharedPreferences`，App 重啟後記住上次選擇）屬於 Issue 6。
enum LibraryViewMode { grid, list }
```

- [ ] **Step 2：寫失敗測試（grid 渲染 + 切換為列表）**

在 `app/test/screens/library_screen_test.dart` 的 `import` 區塊補上：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
```

在 `void main() { ... }` 內、既有的空清單測試之後，新增兩個測試與一個檔案末尾的輔助函式：

```dart
  testWidgets('有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('切換檢視模式按鈕後，書架從 grid 切換為列表呈現', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('library_list_view')), findsNothing);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsNothing);
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });
```

在檔案最末尾（`main()` 函式結束的 `}` 之後）新增輔助函式：

```dart

Book _testBook({required String id, required String title, String? author}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    createTime: now,
    lastReadTime: now,
  );
}
```

- [ ] **Step 3：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（`library_grid_view`/`library_view_mode_toggle` 這些 Key 尚不存在；`'0%'` 文字也還沒有渲染出來）

- [ ] **Step 4：改寫 `LibraryScreen`（Grid/List 雙重呈現 + 書籍卡片）**

整檔改寫 `app/lib/screens/library_screen.dart`：

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book>? _books;
  LibraryViewMode _viewMode = LibraryViewMode.grid;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await widget.repository.listBooks();
    if (!mounted) return;
    setState(() => _books = books);
  }

  Future<void> _pickAndImportFiles() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final uris =
        picked.files.map((f) => f.identifier).whereType<String>().toList();
    if (uris.isEmpty) return;
    await widget.importService.importFiles(uris);
    await _loadBooks();
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == LibraryViewMode.grid
          ? LibraryViewMode.list
          : LibraryViewMode.grid;
    });
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            key: const Key('library_view_mode_toggle'),
            icon: Icon(
              _viewMode == LibraryViewMode.grid
                  ? Icons.view_list
                  : Icons.grid_view,
            ),
            tooltip: _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
            onPressed: books == null ? null : _toggleViewMode,
          ),
          IconButton(
            key: const Key('library_import_button'),
            icon: const Icon(Icons.add),
            tooltip: '匯入書籍',
            onPressed: _pickAndImportFiles,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(books),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: _pickAndImportFiles,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(List<Book> books) {
    if (_viewMode == LibraryViewMode.grid) {
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.62,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) => _BookGridTile(
          book: books[index],
          onTap: () => _openBook(books[index]),
        ),
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: books.length,
      itemBuilder: (context, index) => _BookListTile(
        book: books[index],
        onTap: () => _openBook(books[index]),
      ),
    );
  }
}

IconData _formatIcon(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return Icons.menu_book;
    case BookFileFormat.pdf:
      return Icons.picture_as_pdf;
    case BookFileFormat.txt:
      return Icons.article;
  }
}

IconData _sourceIcon(BookSource source) {
  switch (source) {
    case BookSource.local:
      return Icons.smartphone;
    case BookSource.googleDrive:
      return Icons.cloud;
    case BookSource.oneDrive:
      return Icons.cloud_outlined;
  }
}

String _progressText(Book book) => '${(book.progress * 100).round()}%';

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以格式圖示佔位。
/// `existsSync()` 只是一次本機 stat 呼叫，成本低，不需要 FutureBuilder。
class _BookCover extends StatelessWidget {
  final Book book;
  const _BookCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Colors.grey.shade300,
      child: Center(child: Icon(_formatIcon(book.format), size: 32)),
    );
  }
}

class _BookGridTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookGridTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BookCover(book: book)),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            _progressText(book),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookListTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('book_item_${book.id}'),
      leading: SizedBox(
        width: 48,
        height: 64,
        child: _BookCover(book: book),
      ),
      title: Text(book.title),
      subtitle: Text(book.author ?? ''),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_sourceIcon(book.source), size: 16),
          Text(_progressText(book), style: const TextStyle(fontSize: 10)),
        ],
      ),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 5：執行測試，確認通過**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: 全數 PASS（3 個測試：空清單、grid 渲染、切換列表）

- [ ] **Step 6：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/models/library_enums.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat: render library books as grid/list with cover fallback and view toggle"
```

---

### Task 3：真實裝置 `integration_test`——點擊已匯入書籍導航至 `ReaderScreen`

**Files:**
- Modify: `app/integration_test/library_screen_test.dart`（整檔改寫，取代舊的範例書籍版本）

**Interfaces:**
- Consumes：Task 1/2 的 `LibraryScreen({required repository, required importService})`、`Key('book_item_<id>')`；Issue 4 的 `BookImportServiceImpl`、`SqliteLibraryRepository.open()`；Issue 4 Task 1 新增的原生測試方法 `createTestContentUri(path: String) -> String`（`elinkbook/book_metadata` channel）；既有 `Key('reader_loading_indicator')`/`Key('reader_error_text')`（`ReaderScreen`，不異動）。
- Produces：（本工單最後一個 Task，無後續 Issue 依賴此檔案的內部細節）

- [ ] **Step 1：整檔改寫 `app/integration_test/library_screen_test.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/screens/library_screen.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

/// 持續 pump，直到 [condition] 成立或逾時。與 Issue 4/5 既有 integration_test
/// 採用相同手法：ReaderScreen 對外只有 filePath 一個建構參數，
/// onPageRendered/onError 為內部實作細節，用 Key 觀察渲染狀態是否轉換。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File(p.join(tempDir.path, fileName));
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '從書架點擊一本透過 BookImportService 匯入的真實書籍項目，導航至 ReaderScreen 且內容成功渲染',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final dbPath =
        p.join(tempDir.path, 'library_screen_test_$uniqueSuffix.db');
    final coversDir =
        Directory(p.join(tempDir.path, 'library_screen_test_covers_$uniqueSuffix'));
    await coversDir.create(recursive: true);
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'library_screen_test_sample.epub');

    final repository = await SqliteLibraryRepository.open(dbPath);
    final importService =
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);

    addTearDown(() async {
      await repository.close();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();
      if (await coversDir.exists()) await coversDir.delete(recursive: true);
      final sampleFile = File(samplePath);
      if (await sampleFile.exists()) await sampleFile.delete();
    });

    // 模擬真實匯入流程：createTestContentUri 透過 FileProvider 模擬 SAF 授權
    // 回傳的 content:// URI（與 Issue 4 的 content_uri_acceptance_test.dart
    // 相同手法），BookImportServiceImpl.importFiles() 內部會自行呼叫
    // takePersistableUriPermission，不需在測試中另外呼叫。
    final contentUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue,
        reason: '必須是真正的 content:// URI，而非 file://');

    final imported = await importService.importFiles([contentUri]);
    expect(imported, hasLength(1));
    final importedBook = imported.single;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器'), findsOneWidget);

    // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
    // 與 Issue 4/5 其餘 integration_test 採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），但畫面顯示了錯誤');
  });
}
```

- [ ] **Step 2：在真實裝置/模擬器上執行測試**

Run: `flutter test integration_test/library_screen_test.dart -d <device-id>`（`<device-id>` 由 `flutter devices` 取得）
Expected: `All tests passed!`

- [ ] **Step 3：執行完整回歸測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/library_screen_test.dart
git commit -m "test: verify tapping an imported book navigates to ReaderScreen and renders"
```

- [ ] **Step 5：手動驗證端到端流程（對應驗收標準）**

在真實裝置上執行 `flutter run`，確認：
1. 全新安裝（或清除資料）後開啟 App，書架顯示「尚未匯入書籍」+ 匯入按鈕。
2. 點擊匯入按鈕，透過系統檔案選擇器選取一本真實 EPUB/PDF/TXT 檔案。
3. 匯入完成後，該書出現在書架（grid 檢視，封面/標題可見）。
4. 點擊該書籍項目，能正常導航至 `ReaderScreen` 並看到內容渲染。
5. 點擊檢視模式切換鈕，畫面從 grid 切換為 list（且不需重啟即可切回）。

此步驟為手動驗證，不寫入自動化測試（與 Issue 4 Task 4 相同理由：Android Instrumentation 環境下的系統檔案選擇器互動不可靠，見 `docs/epics/epic-1-library/plans/plan-issue-4.md`「執行期發現」）。
