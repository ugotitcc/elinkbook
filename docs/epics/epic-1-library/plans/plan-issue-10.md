# Issue 10：已匯入書籍批次變更分類歸屬 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `LibraryScreen` 新增「長按書籍卡片進入多選模式，批次移動到分類」的功能，讓已匯入的書籍可以事後變更分類歸屬（原本只能在匯入當下依資料夾名稱自動分類，或透過 Issue 7 的「管理分類」對話框整批處理，缺乏針對個別已匯入書籍的變更入口）。

**Architecture:** 純 Flutter/Dart UI 層變更，不涉及原生程式碼、不新增 MethodChannel、不修改 `LibraryRepository`/`SqliteLibraryRepository`——資料層的 `updateBook(Book)` 早在 Issue 1 就已完整支援寫入 `groupName` 欄位。三個獨立可測試的交付物：(1) `Book` 模型新增 `copyWith` 輔助方法；(2) 新增獨立的「移動到分類」目的地選擇對話框；(3) 在 `LibraryScreen` 中接上長按進入多選模式、App Bar 狀態切換、批次呼叫 `updateBook()` 的完整互動流程。

**Tech Stack:** Flutter/Dart（`flutter_test` widget test）、既有的 `LibraryRepository`/`Book`/`BookGroup` 型別（Issue 1/7）。

## Global Constraints

- 長按書籍卡片進入選取模式，書架（grid）與列表兩種檢視皆須支援；長按當下的那本書自動成為已選取狀態。
- 選取模式下，點擊其他書籍卡片＝加選/取消選（不導覽進閱讀器）；點擊已進入選取模式的觸發卡片本身也遵循同一套加選/取消選規則。
- 選取模式下 App Bar 改為顯示「已選取 N 本」＋左側「✕ 取消」圖示按鈕；點擊取消或選取模式解除後，卡片點擊行為恢復為導覽進閱讀器。
- 系統返回鍵（`PopScope`）在選取模式下等同「取消」——退出選取模式，不會真的離開 `LibraryScreen`。
- 選取模式下停用分類 tab 列的點擊（含「全部」／各分類／「管理分類」），避免使用者中途切換可見書籍集合，讓選取狀態與畫面顯示的書籍不一致。
- 「移動到分類」動作沿用既有的分類清單（`LibraryRepository.listGroups()`，含「未分類」），不重新實作分類的新增/重新命名/刪除——那是 Issue 7 `LibraryGroupManagementDialog` 的職責。
- 移動動作對每一本已選取的書籍呼叫既有的 `LibraryRepository.updateBook(book.copyWith(groupName: ...))`；完成後自動退出選取模式並重新載入書架清單（`_loadBooks()`）。
- **範圍明確排除批次刪除書籍**——那是已記錄在 `docs/epics/epic-1-library/issues.md` Issue 10 段落「已知後續需求」的後續工單，本次不做。
- 不得新增/修改任何 MethodChannel、不得修改 `SqliteLibraryRepository`/`LibraryRepository` 介面本身（`updateBook` 簽章不變）。
- 所有 UI 文字與程式碼註解維持正體中文。
- 套件名稱為 `elinkbook`；所有測試 import 使用 `package:elinkbook/...`。

---

### Task 1: `Book.copyWith` 輔助方法

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Test: `app/test/library/models/book_test.dart`

**Interfaces:**
- Consumes: 無（`Book` 既有所有欄位）。
- Produces: `Book copyWith({String? groupName})` —— Task 3 會用它來建構「改變 `groupName`、其餘欄位不變」的新 `Book` 物件，再傳給 `LibraryRepository.updateBook()`。

- [ ] **Step 1: 寫失敗的測試**

在 `app/test/library/models/book_test.dart` 檔案結尾（`main()` 的最後一個 `test(...)` 之後、結尾的 `});` 之前）新增以下兩個測試：

```dart
  test('copyWith(groupName: ...) 只改變 groupName，其餘欄位保持不變', () {
    final book = Book(
      id: 'b4',
      title: '測試書名',
      author: '測試作者',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      coverPath: '/data/covers/b4.png',
      progress: 30,
      groupName: '舊分類',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final moved = book.copyWith(groupName: '新分類');

    expect(moved.groupName, '新分類');
    expect(moved.id, book.id);
    expect(moved.title, book.title);
    expect(moved.author, book.author);
    expect(moved.format, book.format);
    expect(moved.filePath, book.filePath);
    expect(moved.source, book.source);
    expect(moved.coverPath, book.coverPath);
    expect(moved.progress, book.progress);
    expect(moved.createTime, book.createTime);
    expect(moved.lastReadTime, book.lastReadTime);
  });

  test('copyWith() 不傳入參數時，回傳與原本欄位值相同的新物件', () {
    final book = Book(
      id: 'b5',
      title: '測試書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final copy = book.copyWith();

    expect(copy.groupName, book.groupName);
    expect(copy.id, book.id);
    expect(copy.title, book.title);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/library/models/book_test.dart`
Expected: FAIL，錯誤訊息類似 `The method 'copyWith' isn't defined for the type 'Book'`

- [ ] **Step 3: 實作 `copyWith`**

在 `app/lib/library/models/book.dart` 的 `factory Book.fromMap(...)` 方法之後（檔案第 72 行 `}` 之後、第 73 行 `}` 類別結尾之前）新增：

```dart

  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數（目前只需要
  /// 覆寫 [groupName]——供 Issue 10 的批次分類異動使用）。
  Book copyWith({String? groupName}) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/library/models/book_test.dart`
Expected: PASS，全數測試通過（含新增的 2 項）

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/models/book.dart app/test/library/models/book_test.dart
git commit -m "feat: add Book.copyWith for group reassignment"
```

---

### Task 2: `LibraryMoveToGroupDialog` 目的地選擇對話框

**Files:**
- Create: `app/lib/screens/library_move_to_group_dialog.dart`
- Test: `app/test/screens/library_move_to_group_dialog_test.dart`

**Interfaces:**
- Consumes: `BookGroup`（`app/lib/library/models/book_group.dart`，Issue 1 既有型別，欄位 `name`）。
- Produces: `LibraryMoveToGroupDialog({required List<BookGroup> groups})`——透過 `showDialog<String>(...)` 開啟，使用者點選某個分類後以該分類的 `name`（`String`）呼叫 `Navigator.pop`；點擊「取消」則以 `null` 呼叫 `Navigator.pop`。Task 3 會用 `await showDialog<String>(context: context, builder: (_) => LibraryMoveToGroupDialog(groups: _groups))` 取得使用者選擇的目的分類名稱。

- [ ] **Step 1: 寫失敗的測試**

建立 `app/test/screens/library_move_to_group_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/screens/library_move_to_group_dialog.dart';

void main() {
  testWidgets('顯示所有分類選項，點擊後以該分類名稱關閉對話框', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const LibraryMoveToGroupDialog(
                  groups: [BookGroup('未分類'), BookGroup('奇幻')],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('移動到分類'), findsOneWidget);
    expect(
      find.byKey(const Key('library_move_to_group_option_未分類')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('library_move_to_group_option_奇幻')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    expect(result, '奇幻');
  });

  testWidgets('點擊取消後，對話框關閉且不回傳任何分類', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const LibraryMoveToGroupDialog(
                  groups: [BookGroup('未分類')],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_move_to_group_cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_move_to_group_dialog_test.dart`
Expected: FAIL，編譯錯誤（`library_move_to_group_dialog.dart` 不存在）

- [ ] **Step 3: 實作 `LibraryMoveToGroupDialog`**

建立 `app/lib/screens/library_move_to_group_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/models/book_group.dart';

/// 「移動到分類」目的地選擇對話框（Issue 10）：列出目前所有分類（含
/// 「未分類」），點擊即以該分類名稱關閉對話框。不提供新增/重新命名/刪除
/// ——群組本身的管理屬於 Issue 7 的 [LibraryGroupManagementDialog]，本對話
/// 框只負責「從既有分類中選一個」。
class LibraryMoveToGroupDialog extends StatelessWidget {
  final List<BookGroup> groups;

  const LibraryMoveToGroupDialog({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('移動到分類'),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            key: Key('library_move_to_group_option_${group.name}'),
            onPressed: () => Navigator.of(context).pop(group.name),
            child: Text(group.name),
          ),
        SimpleDialogOption(
          key: const Key('library_move_to_group_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_move_to_group_dialog_test.dart`
Expected: PASS，2 項測試皆通過

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_move_to_group_dialog.dart app/test/screens/library_move_to_group_dialog_test.dart
git commit -m "feat: add LibraryMoveToGroupDialog for group destination picking"
```

---

### Task 3: `LibraryScreen` 長按多選 + 批次移動分類

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: `Book.copyWith({String? groupName})`（Task 1）、`LibraryMoveToGroupDialog({required List<BookGroup> groups})`（Task 2）、既有的 `widget.repository.updateBook(Book)` / `widget.repository.listGroups()`（Issue 1）、既有的 `_books`／`_groups`／`_groupFilter` 狀態欄位。
- Produces: 無新公開介面——`LibraryScreen` 對外建構參數不變（仍是 `repository`/`importService`），本工單只新增內部選取模式狀態與其對應的 Key，供本檔案的 widget test 觀察：`Key('library_selection_app_bar')`、`Key('library_selection_cancel_button')`、`Key('library_move_to_group_button')`、`Key('book_selection_indicator_<bookId>')`（grid 為 `Icon`、list 為 `Checkbox`）、`Key('library_move_to_group_option_<groupName>')`（來自 Task 2）。

此任務改動集中在 `library_screen.dart` 單一檔案，因為所有新狀態（選取模式開關、已選取 ID 集合）都直接依附在既有的 `_LibraryScreenState` 上，且會影響既有的 `build()`／`_buildGroupTabs()`／`_buildBookList()`／`_BookGridTile`／`_BookListTile`。以下步驟採「先寫會失敗的整合測試、再一次補齊實作」的方式（多個 UI 元素環環相扣，拆成單一斷言的紅燈步驟意義不大），但每個測試仍各自獨立可讀、可個別執行。

- [ ] **Step 1: 寫失敗的測試——擴充 `_testBook` 輔助函式並新增選取模式相關測試**

打開 `app/test/screens/library_screen_test.dart`。先擴充檔案最底部的 `_testBook` 輔助函式，新增可選的 `filePath` 參數（預設行為不變，向後相容）：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: filePath ?? 'content://example/$id.epub',
    source: BookSource.local,
    groupName: groupName,
    createTime: now,
    lastReadTime: now,
  );
}
```

接著在 `void main() { ... }` 的最後一個 `testWidgets(...)`（`點擊「選擇資料夾」...`）之後、檔案結尾的 `}` 之前，新增以下 6 個測試：

```dart
  testWidgets('長按書籍卡片後進入選取模式，且該卡片顯示為已選取狀態', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);
    expect(find.text('已選取 1 本'), findsOneWidget);

    final icon = tester.widget<Icon>(
      find.byKey(const Key('book_selection_indicator_1')),
    );
    expect(icon.icon, Icons.check_circle);
  });

  testWidgets('選取模式下點擊其他卡片可加選/取消選；點擊卡片不再導覽進閱讀器', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書');
    final bookB = _testBook(id: '2', title: 'B書');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookA, bookB]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);
  });

  testWidgets('選取模式下點擊「✕ 取消」後恢復一般瀏覽狀態，且卡片點擊恢復導覽進閱讀器',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      filePath: 'content://example/1.txt',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_selection_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.byKey(const Key('library_sort_button')), findsOneWidget);
    expect(find.byKey(const Key('book_selection_indicator_1')), findsNothing);

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // 用 .txt 檔名讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
    // 不觸發 AndroidView；見 reader_screen_test.dart 既有模式），只用來證明
    // 「導覽確實發生」，不驗證實際閱讀渲染。
    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('選取模式下觸發系統返回鍵時退出選取模式，而非真的離開畫面', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.text('書架'), findsOneWidget);
  });

  testWidgets('選取多本書後點擊「移動到分類」，選擇目的分類後所有已勾選書籍的分類皆更新',
      (tester) async {
    final bookA =
        _testBook(id: '1', title: 'A書', groupName: BookGroup.uncategorized);
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    expect(find.text('移動到分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動',
      (tester) async {
    final bookA =
        _testBook(id: '1', title: 'A書', groupName: BookGroup.uncategorized);
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(
      find.byKey(const Key('book_selection_indicator_1')),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: FAIL——新增的 6 項測試因找不到 `Key('library_selection_app_bar')` 等元件而失敗（`findsOneWidget`/`findsNothing` 斷言落空，或找不到對應 Key 拋出例外）。

- [ ] **Step 3: 實作——匯入 `LibraryMoveToGroupDialog`，新增選取模式狀態與方法**

打開 `app/lib/screens/library_screen.dart`。在檔案開頭現有的 import 區塊（第 13 行 `import 'library_group_management_dialog.dart';` 之後）新增：

```dart
import 'library_move_to_group_dialog.dart';
```

在 `_LibraryScreenState` 類別現有的欄位宣告（第 36-43 行）之後新增一個欄位：

```dart
  Set<String>? _selectedBookIds;
```

在 `_openBook`（現有第 191-195 行）之前新增選取模式的 getter 與方法：

```dart
  bool get _inSelectionMode => _selectedBookIds != null;

  void _enterSelectionMode(String bookId) {
    setState(() => _selectedBookIds = {bookId});
  }

  void _exitSelectionMode() {
    setState(() => _selectedBookIds = null);
  }

  void _toggleBookSelection(String bookId) {
    final selected = _selectedBookIds;
    if (selected == null) return;
    setState(() {
      if (selected.contains(bookId)) {
        selected.remove(bookId);
      } else {
        selected.add(bookId);
      }
    });
  }

  void _onBookTap(Book book) {
    if (_inSelectionMode) {
      _toggleBookSelection(book.id);
    } else {
      _openBook(book);
    }
  }

  void _onBookLongPress(Book book) {
    if (!_inSelectionMode) {
      _enterSelectionMode(book.id);
    }
  }

  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => LibraryMoveToGroupDialog(groups: _groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.updateBook(book.copyWith(groupName: destination));
    }
    await _loadBooks();
  }
```

- [ ] **Step 4: 實作——`build()` 加上 `PopScope`，App Bar 拆成一般/選取模式兩個 builder**

把現有的 `build()` 方法（第 218-294 行）整段換成：

```dart
  @override
  Widget build(BuildContext context) {
    final books = _books;
    return PopScope(
      canPop: !_inSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _inSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
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
      ),
    );
  }

  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
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
        PopupMenuButton<void>(
          key: const Key('library_import_button'),
          icon: const Icon(Icons.add),
          tooltip: '匯入書籍',
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              key: const Key('library_import_files_option'),
              onTap: _pickAndImportFiles,
              child: const Text('選擇檔案（可多選）'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_folder_option'),
              onTap: _pickAndImportFolder,
              child: const Text('選擇資料夾'),
            ),
          ],
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
    );
  }

  AppBar _buildSelectionAppBar() {
    final count = _selectedBookIds?.length ?? 0;
    return AppBar(
      key: const Key('library_selection_app_bar'),
      leading: IconButton(
        key: const Key('library_selection_cancel_button'),
        icon: const Icon(Icons.close),
        tooltip: '取消選取',
        onPressed: _exitSelectionMode,
      ),
      title: Text('已選取 $count 本'),
      actions: [
        IconButton(
          key: const Key('library_move_to_group_button'),
          icon: const Icon(Icons.drive_file_move),
          tooltip: '移動到分類',
          onPressed: count == 0 ? null : _moveSelectedBooksToGroup,
        ),
      ],
    );
  }
```

- [ ] **Step 5: 實作——`_buildGroupTabs()` 在選取模式下停用點擊**

把現有的 `_buildGroupTabs()` 方法（原第 296-335 行）整段換成：

```dart
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
              onSelected:
                  _inSelectionMode ? null : (_) => _changeGroupFilter(null),
            ),
          ),
          for (final group in _groups)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                key: Key('library_group_tab_${group.name}'),
                label: Text(group.name),
                selected: _groupFilter == group.name,
                onSelected: _inSelectionMode
                    ? null
                    : (_) => _changeGroupFilter(group.name),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              key: const Key('library_group_manage_button'),
              avatar: const Icon(Icons.category, size: 16),
              label: const Text('管理分類'),
              onPressed: _inSelectionMode ? null : _openManageGroupsDialog,
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 6: 實作——`_buildBookList()` 與 `_BookGridTile`/`_BookListTile` 加上選取模式參數**

把現有的 `_buildBookList()` 方法（原第 354-378 行）整段換成：

```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    if (_viewMode == LibraryViewMode.grid) {
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.62,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return _BookGridTile(
            book: book,
            selectionMode: _inSelectionMode,
            selected: selectedIds?.contains(book.id) ?? false,
            onTap: () => _onBookTap(book),
            onLongPress: () => _onBookLongPress(book),
          );
        },
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return _BookListTile(
          book: book,
          selectionMode: _inSelectionMode,
          selected: selectedIds?.contains(book.id) ?? false,
          onTap: () => _onBookTap(book),
          onLongPress: () => _onBookLongPress(book),
        );
      },
    );
  }
```

把檔案結尾的 `_BookGridTile` 類別（原第 437-468 行）整段換成：

```dart
class _BookGridTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _BookCover(book: book),
                if (selectionMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        // 半透明黑底圓圈確保勾選圖示在任何封面底色下都有
                        // 足夠對比度（審查意見：白色圖示疊在淺色封面上會
                        // 無法辨識）。
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
```

把檔案結尾的 `_BookListTile` 類別（原第 470-497 行）整段換成：

```dart
class _BookListTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('book_item_${book.id}'),
      selected: selected,
      // 選取模式下把 Checkbox 與封面並列（而非直接取代封面）：使用者在
      // 列表批次選取時仍需要看得到封面才能分辨是哪一本書（例如同系列不同
      // 集數，書名文字可能高度相似），純 Checkbox 會讓列表失去辨識度
      // （審查意見）。
      leading: SizedBox(
        width: selectionMode ? 88 : 48,
        height: 64,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectionMode)
              Checkbox(
                key: Key('book_selection_indicator_${book.id}'),
                value: selected,
                onChanged: (_) => onTap(),
              ),
            SizedBox(
              width: 48,
              height: 64,
              child: _BookCover(book: book),
            ),
          ],
        ),
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
      onLongPress: onLongPress,
    );
  }
}
```

- [ ] **Step 7: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS，全部測試（既有 + 新增 6 項）皆通過

- [ ] **Step 8: 執行完整測試套件與靜態分析**

Run: `cd app && flutter test`
Expected: PASS，全數通過，無既有測試被本次變更破壞

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat: add long-press multi-select and batch group move to LibraryScreen"
```

---

## 手動驗證（合併前，需真實裝置）

三個 Task 皆為純 Dart widget test 可驗證，不需要真實裝置即可完成 TDD 循環。但依 Issue 10 驗收標準，合併前仍建議在真實 Android 裝置上手動走一遍：

1. 匯入至少 2 本書籍到書架。
2. 長按其中一本書籍卡片，確認進入選取模式（App Bar 顯示「已選取 1 本」與✕取消按鈕）。
3. 點擊另一本書籍，確認變成「已選取 2 本」。
4. 點擊「移動到分類」，選擇一個既有分類（或「未分類」）。
5. 確認回到一般瀏覽狀態，切換到該分類 tab 能看到這兩本書籍。
6. 重複步驟 2-3 進入選取模式後，按裝置的系統返回鍵，確認退出選取模式而非離開書架畫面。
7. 分別在書架（grid）與列表兩種檢視下重複步驟 2-4，確認兩種檢視皆正常運作。
