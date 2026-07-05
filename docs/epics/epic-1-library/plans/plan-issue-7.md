# Issue 7 實作計劃：書籍分類群組管理

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 在 `LibraryScreen` 新增分類群組列（橫向可捲動 tab：「全部」+ 各群組 + 「管理分類」入口），點擊 tab 依 `groupFilter` 篩選書架/列表顯示的書籍；新增管理分類對話框，支援新增/重新命名/刪除群組（刪除需二次確認對話框），「未分類」為系統保留群組、UI 層面不可觸發重新命名或刪除。

**架構：** `LibraryRepository` 的群組 CRUD 業務規則（保護「未分類」、拒絕重複名稱、刪除時書籍歸位）已在 Issue 1（`SqliteLibraryRepository`）完整實作，本工單只需要在 UI 層呼叫既有方法。分類管理對話框拆到獨立檔案 `app/lib/screens/library_group_management_dialog.dart`（`LibraryGroupManagementDialog`，一個 `StatefulWidget`），避免 `library_screen.dart` 過度膨脹；`LibraryScreen` 只負責開啟對話框、關閉後重新載入群組與書籍。`_loadBooks()` 延續 Issue 6 建立的競態守衛模式，把 `groupFilter` 也納入守衛條件。

**技術棧：** Flutter（Dart）、既有的 `LibraryRepository.listGroups()`/`upsertGroup()`/`renameGroup()`/`deleteGroup()`（Issue 1，不異動）、`flutter_test`（widget test，全部使用假的 `LibraryRepository`/`BookImportService`，不需真實裝置）。

## Global Constraints（全域限制條件）

- `LibraryRepository`（`app/lib/library/library_repository.dart`）與 `SqliteLibraryRepository`（`app/lib/library/sqlite_library_repository.dart`）**不得修改**——群組 CRUD 的業務規則（`deleteGroup('未分類')`/`renameGroup('未分類', ...)` 拋出 `LibraryRepositoryException`、`renameGroup` 目標名稱重複時拋出例外、刪除群組時該群組下書籍 `groupName` 一併改為「未分類」）已在 Issue 1 完整實作且經審查通過，本工單只呼叫既有方法。
- 「未分類」（`BookGroup.uncategorized`）的重新命名/刪除按鈕**不得出現**在管理分類對話框中（驗收標準明確要求「UI 層面不可觸發」，不是「觸發後顯示錯誤訊息」）。
- 刪除分類前**必須**先彈出確認對話框，取消不執行刪除。
- `LibraryScreen` 既有的公開建構子 `LibraryScreen({required LibraryRepository repository, required BookImportService importService})` 與所有既有 Key（`library_view_mode_toggle`、`library_sort_button`、`library_sort_option_<name>`、`library_import_button`、`library_empty_import_button`、`library_grid_view`、`library_list_view`、`book_item_<id>`）**不得**變更語意。
- `_loadBooks()` 的競態守衛（Issue 6 建立：擷取呼叫當下的排序條件，回應時若條件已變更則不覆蓋畫面）須擴充為同時涵蓋 `groupFilter`，不得只顧排序而漏掉分類篩選這個新的可變條件。
- 新增的 Key 格式：`Key('library_group_tabs')`（整列容器）、`Key('library_group_tab_all')`（「全部」）、`Key('library_group_tab_<group.name>')`（各群組，例如 `library_group_tab_奇幻`）、`Key('library_group_manage_button')`（開啟管理對話框）、`Key('library_group_manage_list')`（對話框內清單）、`Key('library_group_manage_item_<group.name>')`（清單每一列）、`Key('library_group_rename_button_<group.name>')`／`Key('library_group_delete_button_<group.name>')`（每列的操作按鈕，「未分類」那一列**不得**存在這兩個 Key）、`Key('library_group_add_field')`／`Key('library_group_add_button')`（新增）、`Key('library_group_rename_field')`／`Key('library_group_rename_confirm')`（重新命名子對話框）、`Key('library_group_delete_confirm')`（刪除確認子對話框）。
- 所有 UI 文字、對話框文字與程式註解維持正體中文。

---

### Task 1：分類群組列（Tab）+ 篩選書架/列表

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（整檔改寫）
- Modify: `app/test/support/fake_library_repository.dart`（補上真正的群組狀態追蹤，不再是寫死的回傳值）
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：既有 `LibraryRepository.listGroups()`/`listBooks({sortBy, groupFilter})`（`app/lib/library/library_repository.dart`，不異動）。
- Produces：`_LibraryScreenState` 新增的 `_groups`（`List<BookGroup>`）、`_groupFilter`（`String?`）欄位與 `_loadGroups()`、`_changeGroupFilter(String?)` 方法——Task 2 會呼叫 `_loadGroups()` 在管理對話框關閉後重新整理群組清單，並讀取/重設 `_groupFilter`，因此 Task 2 的實作者需要知道這幾個方法/欄位目前的確切簽章（見下方 Step 4 的完整程式碼）。`Key('library_group_tabs')`／`Key('library_group_tab_all')`／`Key('library_group_tab_<name>')`／`Key('library_group_manage_button')`——Task 2 沿用這組 Key，只會在 `_openManageGroupsDialog()`（Task 2 新增）中把 `library_group_manage_button` 的 `onPressed` 接上真正的對話框。

- [ ] **Step 1：`FakeLibraryRepository` 補上真正的群組狀態追蹤**

修改 `app/test/support/fake_library_repository.dart`，把整個類別改為：

```dart
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的記憶體內 [LibraryRepository] 假實作，避免 widget
/// test 依賴真實 sqflite（見 docs/epics/epic-1-library/spec.md「測試決策」）。
/// 群組 CRUD 的業務規則（保護「未分類」、拒絕重複名稱、刪除時書籍歸位）
/// 與 `SqliteLibraryRepository`（Issue 1）語意一致，供 Issue 7 的分類群組
/// 管理 widget test 驅動真實可觀察的行為。
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    List<Book> initialBooks = const [],
    this.throwOnListBooks = false,
  })  : _books = List.of(initialBooks),
        _groups = {
          BookGroup.uncategorized,
          for (final book in initialBooks) book.groupName,
        };

  final bool throwOnListBooks;
  final List<Book> _books;
  final Set<String> _groups;

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

  @override
  Future<List<BookGroup>> listGroups() async {
    final names = _groups.toList()..sort();
    return names.map(BookGroup.new).toList();
  }

  @override
  Future<void> upsertGroup(String name) async {
    _groups.add(name);
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    if (_groups.contains(newName)) {
      throw LibraryRepositoryException('分類「$newName」已存在');
    }
    _groups
      ..remove(oldName)
      ..add(newName);
    for (var i = 0; i < _books.length; i++) {
      if (_books[i].groupName == oldName) {
        _books[i] = _withGroupName(_books[i], newName);
      }
    }
  }

  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
    _groups.remove(name);
    for (var i = 0; i < _books.length; i++) {
      if (_books[i].groupName == name) {
        _books[i] = _withGroupName(_books[i], BookGroup.uncategorized);
      }
    }
  }

  Book _withGroupName(Book book, String groupName) => Book(
        id: book.id,
        title: book.title,
        author: book.author,
        format: book.format,
        filePath: book.filePath,
        source: book.source,
        coverPath: book.coverPath,
        progress: book.progress,
        groupName: groupName,
        createTime: book.createTime,
        lastReadTime: book.lastReadTime,
      );
}
```

- [ ] **Step 2：`_testBook` 輔助函式補上 `groupName` 參數**

在 `app/test/screens/library_screen_test.dart` 檔案最上方的 `import` 區塊補上：

```dart
import 'package:elinkbook/library/models/book_group.dart';
```

把檔案末尾的 `_testBook` 函式改為：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: groupName,
    createTime: now,
    lastReadTime: now,
  );
}
```

（新增的 `groupName` 參數有預設值，既有呼叫端不需修改。）

- [ ] **Step 3：寫失敗測試（分類 tab 篩選）**

在 `app/test/screens/library_screen_test.dart` 的 `void main() { ... }` 內、既有測試之後，新增：

```dart
  testWidgets('點擊分類 tab 後，畫面只顯示該群組的書籍；點擊「全部」顯示所有書籍',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);

    await tester.tap(find.byKey(const Key('library_group_tab_all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

- [ ] **Step 4：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（`library_group_tab_奇幻`／`library_group_tab_all` 這些 Key 尚不存在）

- [ ] **Step 5：改寫 `LibraryScreen`（分類 tab 列 + 篩選）**

整檔改寫 `app/lib/screens/library_screen.dart`：

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
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
  List<BookGroup> _groups = const [];
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  LibrarySortBy _sortBy = LibrarySortBy.lastRead;
  String? _groupFilter;

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
    await Future.wait([_loadGroups(), _loadBooks()]);
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.repository.listGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (_) {
      if (!mounted) return;
      setState(() => _groups = const [BookGroup(BookGroup.uncategorized)]);
    }
  }

  Future<void> _loadBooks() async {
    // 擷取呼叫當下的排序/分類篩選條件；若使用者在這次非同步查詢完成前又
    // 切換了排序或分類 tab，較晚回應但較早發出的查詢結果會對應到舊條件，
    // 此時不應覆蓋畫面（避免顯示內容與目前選定的條件不一致）。
    final requestedSortBy = _sortBy;
    final requestedGroupFilter = _groupFilter;
    try {
      final books = await widget.repository.listBooks(
        sortBy: requestedSortBy,
        groupFilter: requestedGroupFilter,
      );
      if (!mounted) return;
      if (_sortBy != requestedSortBy || _groupFilter != requestedGroupFilter) {
        return;
      }
      setState(() => _books = books);
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (!mounted) return;
      if (_sortBy != requestedSortBy || _groupFilter != requestedGroupFilter) {
        return;
      }
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

  Future<void> _changeGroupFilter(String? groupFilter) async {
    setState(() => _groupFilter = groupFilter);
    await _loadBooks();
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
  }

  void _openManageGroupsDialog() {
    // Task 2 會把這個方法改為真正開啟 LibraryGroupManagementDialog。
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
          : Column(
              children: [
                _buildGroupTabs(),
                Expanded(
                  child: books.isEmpty
                      ? _buildEmptyState()
                      : _buildBookList(books),
                ),
              ],
            ),
    );
  }

  Widget _buildGroupTabs() {
    return SizedBox(
      key: const Key('library_group_tabs'),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              key: const Key('library_group_tab_all'),
              label: const Text('全部'),
              selected: _groupFilter == null,
              onSelected: (_) => _changeGroupFilter(null),
            ),
          ),
          for (final group in _groups)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                key: Key('library_group_tab_${group.name}'),
                label: Text(group.name),
                selected: _groupFilter == group.name,
                onSelected: (_) => _changeGroupFilter(group.name),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              key: const Key('library_group_manage_button'),
              avatar: const Icon(Icons.settings, size: 16),
              label: const Text('管理分類'),
              onPressed: _openManageGroupsDialog,
            ),
          ),
        ],
      ),
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

（`_openManageGroupsDialog()` 在本 Task 只是一個空殼方法；Task 2 會把它改為真正開啟 `LibraryGroupManagementDialog`。`ChoiceChip`/`ActionChip` 皆為 Flutter Material 內建元件，不需額外套件。）

- [ ] **Step 6：執行測試，確認通過**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 7：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/support/fake_library_repository.dart app/test/screens/library_screen_test.dart
git commit -m "feat: add group tab filtering to LibraryScreen"
```

---

### Task 2：分類管理對話框（新增/重新命名/刪除）

**Files:**
- Create: `app/lib/screens/library_group_management_dialog.dart`
- Modify: `app/lib/screens/library_screen.dart`（把 `_openManageGroupsDialog()` 從空殼改為真正開啟對話框）
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `_groups`（`List<BookGroup>`）、`_groupFilter`（`String?`）、`_loadGroups()`、`Key('library_group_manage_button')`。既有 `LibraryRepository.upsertGroup()`/`renameGroup()`/`deleteGroup()`（拋出 `LibraryRepositoryException`，見 `app/lib/library/library_repository.dart`）。
- Produces：`class LibraryGroupManagementDialog extends StatefulWidget { const LibraryGroupManagementDialog({required LibraryRepository repository, required List<BookGroup> initialGroups}); }`——本工單為 Issue 7 最後一個任務，無後續工單依賴此類別的內部細節。

- [ ] **Step 1：新增 `LibraryGroupManagementDialog`**

建立 `app/lib/screens/library_group_management_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/library_repository.dart';
import '../library/models/book_group.dart';

/// 分類群組管理對話框（FR-33）：支援新增/重新命名/刪除群組。「未分類」
/// 為系統保留群組，UI 層面不提供重新命名/刪除按鈕（見
/// docs/epics/epic-1-library/issues.md Issue 7 驗收標準）。刪除前必須經過
/// 二次確認對話框。呼叫端（LibraryScreen）於對話框關閉後一律重新載入群組
/// 與書籍清單，不論使用者實際上是否做了任何變更。
class LibraryGroupManagementDialog extends StatefulWidget {
  final LibraryRepository repository;
  final List<BookGroup> initialGroups;

  const LibraryGroupManagementDialog({
    super.key,
    required this.repository,
    required this.initialGroups,
  });

  @override
  State<LibraryGroupManagementDialog> createState() =>
      _LibraryGroupManagementDialogState();
}

class _LibraryGroupManagementDialogState
    extends State<LibraryGroupManagementDialog> {
  late List<BookGroup> _groups;
  final _addController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _groups = List.of(widget.initialGroups);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _reloadGroups() async {
    final groups = await widget.repository.listGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  Future<void> _addGroup() async {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    try {
      await widget.repository.upsertGroup(name);
      _addController.clear();
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _renameGroup(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新命名分類'),
        content: TextField(
          key: const Key('library_group_rename_field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_group_rename_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == oldName) return;
    try {
      await widget.repository.renameGroup(oldName, newName);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _confirmDeleteGroup(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除分類'),
        content: Text(
          '確定要刪除分類「$name」嗎？該分類下的書籍將改列為'
          '「${BookGroup.uncategorized}」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_group_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteGroup(name);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理分類'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                key: const Key('library_group_manage_list'),
                shrinkWrap: true,
                itemCount: _groups.length,
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  final isProtected = group.name == BookGroup.uncategorized;
                  return ListTile(
                    key: Key('library_group_manage_item_${group.name}'),
                    title: Text(group.name),
                    trailing: isProtected
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key(
                                  'library_group_rename_button_${group.name}',
                                ),
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _renameGroup(group.name),
                              ),
                              IconButton(
                                key: Key(
                                  'library_group_delete_button_${group.name}',
                                ),
                                icon: const Icon(Icons.delete, size: 20),
                                onPressed: () =>
                                    _confirmDeleteGroup(group.name),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('library_group_add_field'),
              controller: _addController,
              decoration: const InputDecoration(labelText: '新增分類名稱'),
              onSubmitted: (_) => _addGroup(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('library_group_add_button'),
          onPressed: _addGroup,
          child: const Text('新增'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2：`_openManageGroupsDialog()` 接上真正的對話框**

在 `app/lib/screens/library_screen.dart` 的 `import` 區塊補上：

```dart
import 'library_group_management_dialog.dart';
```

把 `_openManageGroupsDialog()` 這個空殼方法改為：

```dart
  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.repository,
        initialGroups: _groups,
      ),
    );
    await _loadGroups();
    if (!mounted) return;
    // 若目前篩選中的分類已在對話框內被刪除，退回「全部」篩選，避免畫面
    // 停留在一個已不存在的分類上（listBooks 對不存在的 groupFilter 只會
    // 回傳空清單，容易誤以為「這個分類沒有書」而非「這個分類已被刪除」）。
    final filterStillExists =
        _groupFilter == null || _groups.any((g) => g.name == _groupFilter);
    if (!filterStillExists) {
      setState(() => _groupFilter = null);
    }
    await _loadBooks();
  }
```

- [ ] **Step 3：寫失敗測試（新增/刪除確認/刪除保護/重新命名/篩選自動退回）**

在 `app/test/screens/library_screen_test.dart` 的 `void main() { ... }` 內、Task 1 新增的測試之後，新增五個測試：

```dart
  testWidgets('管理分類對話框：新增分類後，新分類出現在 tab 列', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_add_field')),
      '奇幻',
    );
    await tester.tap(find.byKey(const Key('library_group_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_奇幻')), findsOneWidget);
  });

  testWidgets('管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於「未分類」篩選',
      (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_奇幻')), findsNothing);

    await tester.tap(
      find.byKey(Key('library_group_tab_${BookGroup.uncategorized}')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('管理分類對話框：嘗試刪除「未分類」時操作被禁止（找不到刪除/重新命名按鈕）',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        Key('library_group_delete_button_${BookGroup.uncategorized}'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        Key('library_group_rename_button_${BookGroup.uncategorized}'),
      ),
      findsNothing,
    );
  });

  testWidgets('管理分類對話框：重新命名分類後，tab 列顯示新名稱', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_奇幻')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_rename_field')),
      '科幻',
    );
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_科幻')), findsOneWidget);
    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsNothing);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_科幻')), findsOneWidget);
  });

  testWidgets('刪除目前篩選中的分類後，畫面自動退回「全部」篩選（不留在已不存在的分類）',
      (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
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

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    // 該書已改列「未分類」；篩選應已自動退回「全部」，故仍可見
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });
```

- [ ] **Step 4：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（`library_group_management_dialog.dart` 不存在，編譯錯誤）

- [ ] **Step 5：執行測試，確認通過**

（Step 1、2 的程式碼已經是完整實作，此處直接驗證。）

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 6：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_group_management_dialog.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat: add group management dialog (add/rename/delete)"
```
