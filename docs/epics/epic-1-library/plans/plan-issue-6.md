# Issue 6 實作計劃：排序 + 檢視模式記憶

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 在 `LibraryScreen` 新增排序下拉選單（`最後閱讀` 預設／`建立時間`／`作者`／`書名`）與書架⇄列表切換鈕的持久化，兩者選擇存 `SharedPreferences`，App 重啟後記住使用者上次選擇。

**架構：** 新增 `LibraryPreferences`（`app/lib/library/library_preferences.dart`）包裝 `shared_preferences`，提供 `loadSortBy()`/`saveSortBy()`/`loadViewMode()`/`saveViewMode()` 四個方法；不另外設計抽象介面或注入到 `LibraryScreen` 建構子，直接在 `_LibraryScreenState` 內部建立實例即可——測試改用 `shared_preferences` 官方支援的 `SharedPreferences.setMockInitialValues({})`（等同這個套件本身的測試替身機制），不需要額外的假實作類別。`LibraryScreen` 在 `initState` 時非同步載入上次儲存的排序/檢視模式，套用後才呼叫既有的 `_loadBooks()`；使用者變更排序/檢視模式時立即 `setState` 並非同步寫回 `SharedPreferences`。`LibraryRepository.listBooks({sortBy, groupFilter})` 的排序邏輯已在 Issue 1（`SqliteLibraryRepository._orderByClause`）完整實作，本工單只需要在 UI 層正確傳入 `sortBy` 參數，不需異動 repository 層。

**技術棧：** Flutter（Dart）、`shared_preferences`（新增依賴，透過 `flutter pub add shared_preferences` 解析版本，不手動釘選猜測的版本號）、`flutter_test`（widget test 全部使用假的 `LibraryRepository`/`BookImportService` 搭配 `SharedPreferences.setMockInitialValues`，不需真實裝置）。

## Global Constraints（全域限制條件）

- `LibrarySortBy`/`LibraryViewMode` 這兩個列舉已存在於 `app/lib/library/models/library_enums.dart`（`enum LibrarySortBy { lastRead, createTime, author, title }`、`enum LibraryViewMode { grid, list }`），本工單**不得**修改它們的定義，只能沿用。
- `LibraryRepository.listBooks({LibrarySortBy sortBy = LibrarySortBy.lastRead, String? groupFilter})` 的排序邏輯已在 Issue 1 完整實作（`app/lib/library/sqlite_library_repository.dart` 的 `_orderByClause`：`lastRead` → `lastReadTime DESC`、`createTime` → `createTime DESC`、`author` → `author ASC`、`title` → `title ASC`）——本工單只需要把 UI 選到的 `sortBy` 值傳給既有的 `listBooks()` 呼叫，**不得**修改 `sqlite_library_repository.dart`。
- `LibraryScreen` 既有的公開建構子 `LibraryScreen({required LibraryRepository repository, required BookImportService importService})` **不得**變更（Issue 5 已確立的契約）——排序/檢視模式的持久化屬於內部實作細節，不透過建構參數注入。
- 既有的所有 Key（`library_view_mode_toggle`、`library_import_button`、`library_empty_import_button`、`library_grid_view`、`library_list_view`、`book_item_<id>`）**不得**改名或改變語意。
- 預設排序為 `LibrarySortBy.lastRead`、預設檢視模式為 `LibraryViewMode.grid`——當 `SharedPreferences` 尚未儲存過任何值時（例如首次啟動），必須回退到這兩個預設值，與 Issue 5 既有行為一致。
- 所有既有會 `pumpWidget(... LibraryScreen ...)` 的**純 Dart widget test**（`app/test/navigation_test.dart`、`app/test/screens/library_screen_test.dart`）都必須在 `setUp()` 加上 `SharedPreferences.setMockInitialValues({})`——因為 `LibraryScreen.initState()` 現在會呼叫 `SharedPreferences.getInstance()`，沒有這行會在純 Dart 測試環境中拋出 `MissingPluginException`。真實裝置的 `integration_test`（`app/integration_test/library_screen_test.dart`、`smoke_test.dart`）**不需要**加這行，因為裝置上有真正的原生 `shared_preferences` 實作可用。
- 所有 UI 文字、tooltip 與程式註解維持正體中文。

---

### Task 1：`LibraryPreferences` 持久化層 + 檢視模式記憶

**Files:**
- Create: `app/lib/library/library_preferences.dart`
- Create: `app/test/library/library_preferences_test.dart`
- Modify: `app/lib/screens/library_screen.dart`（整檔改寫）
- Modify: `app/test/screens/library_screen_test.dart`
- Modify: `app/test/navigation_test.dart`
- Modify: `app/pubspec.yaml`（新增 `shared_preferences` 依賴）

**Interfaces:**
- Consumes：`LibrarySortBy`/`LibraryViewMode`（`app/lib/library/models/library_enums.dart`，既有、不異動）。
- Produces：`class LibraryPreferences { Future<LibrarySortBy> loadSortBy(); Future<void> saveSortBy(LibrarySortBy); Future<LibraryViewMode> loadViewMode(); Future<void> saveViewMode(LibraryViewMode); }`——Task 2 會直接沿用 `loadSortBy()`/`saveSortBy()` 這兩個方法，簽章不變。`LibraryScreen._LibraryScreenState` 新增的 `_preferences` 欄位與 `_initialize()` 方法——Task 2 會在 `_initialize()` 內追加載入排序，並在 `_loadBooks()` 傳入 `sortBy` 參數，因此 Task 2 的實作者需要知道 `_initialize()` 目前的確切內容（見下方 Step 6 的完整程式碼）。

- [ ] **Step 1：新增 `shared_preferences` 依賴**

Run: `flutter pub add shared_preferences`（在 `app/` 目錄下執行；讓 `pub` 自動解析目前相容的最新版本，不手動猜測版本號寫入 `pubspec.yaml`）
Expected: 指令成功結束，`app/pubspec.yaml` 的 `dependencies` 區塊新增一行 `shared_preferences: ^X.Y.Z`，`app/pubspec.lock` 同步更新。

- [ ] **Step 2：寫失敗測試（`LibraryPreferences` 讀寫）**

建立 `app/test/library/library_preferences_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/library/library_preferences.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過排序方式時，loadSortBy 回傳預設值 lastRead', () async {
    final prefs = LibraryPreferences();
    expect(await prefs.loadSortBy(), LibrarySortBy.lastRead);
  });

  test('saveSortBy 寫入後，loadSortBy 讀回相同的值', () async {
    final prefs = LibraryPreferences();
    await prefs.saveSortBy(LibrarySortBy.title);
    expect(await prefs.loadSortBy(), LibrarySortBy.title);
  });

  test('尚未儲存過檢視模式時，loadViewMode 回傳預設值 grid', () async {
    final prefs = LibraryPreferences();
    expect(await prefs.loadViewMode(), LibraryViewMode.grid);
  });

  test('saveViewMode 寫入後，loadViewMode 讀回相同的值', () async {
    final prefs = LibraryPreferences();
    await prefs.saveViewMode(LibraryViewMode.list);
    expect(await prefs.loadViewMode(), LibraryViewMode.list);
  });

  test('重新建立 LibraryPreferences 實例後（模擬 App 重啟），仍讀回先前儲存的值',
      () async {
    final prefs1 = LibraryPreferences();
    await prefs1.saveViewMode(LibraryViewMode.list);
    await prefs1.saveSortBy(LibrarySortBy.author);

    final prefs2 = LibraryPreferences();
    expect(await prefs2.loadViewMode(), LibraryViewMode.list);
    expect(await prefs2.loadSortBy(), LibrarySortBy.author);
  });
}
```

- [ ] **Step 3：執行測試，確認失敗**

Run: `flutter test test/library/library_preferences_test.dart -v`
Expected: FAIL（`package:elinkbook/library/library_preferences.dart` 不存在，編譯錯誤）

- [ ] **Step 4：實作 `LibraryPreferences`**

建立 `app/lib/library/library_preferences.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'models/library_enums.dart';

/// 圖書庫排序方式與檢視模式選擇的持久化（FR-03/FR-26）。直接使用
/// `shared_preferences` 官方支援的測試方式
/// （`SharedPreferences.setMockInitialValues`）驅動測試，不另外設計抽象介面
/// （見 docs/epics/epic-1-library/spec.md）。
class LibraryPreferences {
  static const _sortByKey = 'library_sort_by';
  static const _viewModeKey = 'library_view_mode';

  Future<LibrarySortBy> loadSortBy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sortByKey);
    if (raw == null) return LibrarySortBy.lastRead;
    return LibrarySortBy.values.byName(raw);
  }

  Future<void> saveSortBy(LibrarySortBy sortBy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortByKey, sortBy.name);
  }

  Future<LibraryViewMode> loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_viewModeKey);
    if (raw == null) return LibraryViewMode.grid;
    return LibraryViewMode.values.byName(raw);
  }

  Future<void> saveViewMode(LibraryViewMode viewMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModeKey, viewMode.name);
  }
}
```

- [ ] **Step 5：執行測試，確認通過**

Run: `flutter test test/library/library_preferences_test.dart -v`
Expected: 全數 PASS（5 個測試）

- [ ] **Step 6：改寫 `LibraryScreen`（載入/儲存檢視模式）**

整檔改寫 `app/lib/screens/library_screen.dart`：

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_preferences.dart';
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
  final _preferences = LibraryPreferences();

  List<Book>? _books;
  LibraryViewMode _viewMode = LibraryViewMode.grid;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _loadBooks();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await widget.repository.listBooks();
      if (!mounted) return;
      setState(() => _books = books);
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (!mounted) return;
      setState(() => _books = []);
    }
  }

  Future<void> _pickAndImportFiles() async {
    try {
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
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    }
  }

  void _toggleViewMode() {
    final newMode = _viewMode == LibraryViewMode.grid
        ? LibraryViewMode.list
        : LibraryViewMode.grid;
    setState(() => _viewMode = newMode);
    _preferences.saveViewMode(newMode);
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

（與目前 `main` 上的版本相比，本步驟只新增了 `_preferences` 欄位、把 `initState()` 改呼叫新的 `_initialize()`、`_toggleViewMode()` 內新增 `_preferences.saveViewMode(newMode)` 這一行；`_loadBooks()`／`_pickAndImportFiles()`／其餘所有 widget 皆逐字不變。）

- [ ] **Step 7：既有 widget test 補上 `SharedPreferences.setMockInitialValues`，並新增檢視模式持久化測試**

整檔改寫 `app/test/screens/library_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  setUp(() {
    // LibraryScreen.initState() 現在會呼叫 SharedPreferences.getInstance()，
    // 純 Dart widget test 環境沒有真正的原生實作，須用官方支援的測試替身。
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('圖書庫載入資料失敗時，畫面降級顯示空清單狀態而非永遠卡在載入中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(throwOnListBooks: true),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

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

  testWidgets('切換檢視模式後，重新建立 LibraryScreen 仍維持上次選擇（模擬 App 重啟）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    // 模擬 App 重啟：SharedPreferences.setMockInitialValues 的模擬儲存體會
    // 延續到同一個測試行程內建立的新 LibraryScreen 實例，等同於重啟後讀到
    // 上次寫入的值。
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('library_grid_view')), findsNothing);
  });
}

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

整檔改寫 `app/test/navigation_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/library_screen.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

- [ ] **Step 8：執行測試，確認通過**

Run: `flutter test`
Expected: 全數 PASS

- [ ] **Step 9：靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/library/library_preferences.dart app/test/library/library_preferences_test.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart app/test/navigation_test.dart
git commit -m "feat: persist library view mode via SharedPreferences"
```

---

### Task 2：排序下拉選單 UI + `listBooks(sortBy:)` 串接 + 排序持久化

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（整檔改寫）
- Modify: `app/test/support/fake_library_repository.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryPreferences.loadSortBy()`/`saveSortBy()`、`_LibraryScreenState._initialize()`（本任務會在其中追加載入排序）。
- Produces：`Key('library_sort_button')`（開啟排序選單的 `PopupMenuButton`）、`Key('library_sort_option_<LibrarySortBy.name>')`（每個排序選項，例如 `library_sort_option_title`）——本工單為 Issue 6 最後一個任務，無後續工單依賴這些 Key 的細節。

- [ ] **Step 1：`FakeLibraryRepository` 補上真正的排序邏輯**

修改 `app/test/support/fake_library_repository.dart`，把 `listBooks()` 方法改為：

```dart
  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) async {
    if (throwOnListBooks) {
      throw Exception('模擬資料庫錯誤');
    }
    final filtered = groupFilter == null
        ? List.of(_books)
        : _books.where((b) => b.groupName == groupFilter).toList();
    filtered.sort(_comparatorFor(sortBy));
    return filtered;
  }

  int Function(Book, Book) _comparatorFor(LibrarySortBy sortBy) {
    switch (sortBy) {
      case LibrarySortBy.lastRead:
        return (a, b) => b.lastReadTime.compareTo(a.lastReadTime);
      case LibrarySortBy.createTime:
        return (a, b) => b.createTime.compareTo(a.createTime);
      case LibrarySortBy.author:
        return (a, b) => (a.author ?? '').compareTo(b.author ?? '');
      case LibrarySortBy.title:
        return (a, b) => a.title.compareTo(b.title);
    }
  }
```

（這段排序邏輯必須與 `app/lib/library/sqlite_library_repository.dart` 的 `_orderByClause` 語意一致：`lastRead`/`createTime` 為新到舊的 DESC，`author`/`title` 為 ASC，讓假實作在測試中的行為與真實資料庫一致。其餘方法——`insertBook`/`updateBook`/`deleteBook`/`listGroups`/`upsertGroup`/`renameGroup`/`deleteGroup`——維持不變。）

- [ ] **Step 2：寫失敗測試（排序切換 + 排序持久化）**

在 `app/test/screens/library_screen_test.dart` 的 `void main() { ... }` 內、既有的「切換檢視模式後，重新建立 LibraryScreen 仍維持上次選擇」測試之後，新增兩個測試：

```dart
  testWidgets('選擇「書名」排序後，書架清單依書名字母順序重新排列', (tester) async {
    final now = DateTime.now();
    final bookB = Book(
      id: '1',
      title: 'B書',
      author: null,
      format: BookFileFormat.epub,
      filePath: 'content://example/1.epub',
      source: BookSource.local,
      createTime: now,
      lastReadTime: now.add(const Duration(minutes: 1)),
    );
    final bookA = Book(
      id: '2',
      title: 'A書',
      author: null,
      format: BookFileFormat.epub,
      filePath: 'content://example/2.epub',
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookB, bookA]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 切到列表模式，方便用垂直位置比較先後順序
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 預設「最後閱讀」排序（新到舊）：lastReadTime 較晚的 B書應排在前面
    final initialBPos =
        tester.getTopLeft(find.byKey(const Key('book_item_1'))).dy;
    final initialAPos =
        tester.getTopLeft(find.byKey(const Key('book_item_2'))).dy;
    expect(initialBPos, lessThan(initialAPos));

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    final afterAPos =
        tester.getTopLeft(find.byKey(const Key('book_item_2'))).dy;
    final afterBPos =
        tester.getTopLeft(find.byKey(const Key('book_item_1'))).dy;
    expect(afterAPos, lessThan(afterBPos));
  });

  testWidgets('排序方式選擇會持久化，重新建立 LibraryScreen 後仍維持上次選擇',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_author')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('排序：作者'), findsOneWidget);

    // 模擬 App 重啟
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('排序：作者'), findsOneWidget);
  });
```

- [ ] **Step 3：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（`library_sort_button`/`library_sort_option_title`/`library_sort_option_author` 這些 Key 尚不存在；`FakeLibraryRepository` 尚未真正排序）

- [ ] **Step 4：改寫 `LibraryScreen`（排序下拉選單 + `sortBy` 串接）**

整檔改寫 `app/lib/screens/library_screen.dart`：

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_preferences.dart';
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
  final _preferences = LibraryPreferences();

  List<Book>? _books;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  LibrarySortBy _sortBy = LibrarySortBy.lastRead;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    final sortBy = await _preferences.loadSortBy();
    if (!mounted) return;
    setState(() {
      _viewMode = viewMode;
      _sortBy = sortBy;
    });
    await _loadBooks();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await widget.repository.listBooks(sortBy: _sortBy);
      if (!mounted) return;
      setState(() => _books = books);
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (!mounted) return;
      setState(() => _books = []);
    }
  }

  Future<void> _pickAndImportFiles() async {
    try {
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
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    }
  }

  void _toggleViewMode() {
    final newMode = _viewMode == LibraryViewMode.grid
        ? LibraryViewMode.list
        : LibraryViewMode.grid;
    setState(() => _viewMode = newMode);
    _preferences.saveViewMode(newMode);
  }

  Future<void> _changeSortBy(LibrarySortBy sortBy) async {
    setState(() => _sortBy = sortBy);
    await _preferences.saveSortBy(sortBy);
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
          PopupMenuButton<LibrarySortBy>(
            key: const Key('library_sort_button'),
            icon: const Icon(Icons.sort),
            tooltip: '排序：${_sortLabel(_sortBy)}',
            enabled: books != null,
            onSelected: _changeSortBy,
            itemBuilder: (context) => LibrarySortBy.values
                .map(
                  (sortBy) => PopupMenuItem<LibrarySortBy>(
                    key: Key('library_sort_option_${sortBy.name}'),
                    value: sortBy,
                    child: Text(_sortLabel(sortBy)),
                  ),
                )
                .toList(),
          ),
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

String _sortLabel(LibrarySortBy sortBy) {
  switch (sortBy) {
    case LibrarySortBy.lastRead:
      return '最後閱讀';
    case LibrarySortBy.createTime:
      return '建立時間';
    case LibrarySortBy.author:
      return '作者';
    case LibrarySortBy.title:
      return '書名';
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
Expected: 全數 PASS

- [ ] **Step 6：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/support/fake_library_repository.dart app/test/screens/library_screen_test.dart
git commit -m "feat: add sort dropdown to LibraryScreen with SharedPreferences persistence"
```

- [ ] **Step 8：手動驗證（對應驗收標準）**

在真實裝置上執行 `flutter run`，確認：
1. 匯入數本書籍後，點擊排序選單，選擇「書名」／「作者」／「建立時間」，畫面清單順序隨之改變。
2. 切換書架/列表檢視模式後，關閉並重新開啟 App，畫面維持上次選擇的檢視模式。
3. 選擇一種排序方式後，關閉並重新開啟 App，畫面維持上次選擇的排序方式（排序按鈕的 tooltip 文字可用於確認目前選擇）。

此步驟為手動驗證，不寫入自動化測試（沿用 Issue 4/5 對於需要真實裝置重啟才能驗證的行為的處理方式）。
