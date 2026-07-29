# Epic 19 Issue 3 — 分類 2×2 拼貼格取代分類 Chip 列 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 拆除書架頂端水平分類 Chip 列，改為每個非空分類顯示成一格 2×2 封面拼貼（列表檢視為橫向 4 縮圖列），固定排在書籍清單最前面；點擊拼貼格推入同一個 `LibraryScreen`（新增 `groupFilter` 建構參數）以單一分類篩選瀏覽；「管理分類」入口搬到 AppBar。

**Architecture:** 純 UI 層工單，`LibraryRepository` 介面不變。`LibraryScreen` 新增可選建構參數 `groupFilter`（`null`＝頂層書架模式，非 `null`＝單一分類篩選模式），`_groupFilter` 內部欄位改為 `initState()` 一次性初始化、畫面生命週期內不再變動（切換分類一律靠 `Navigator.push` 開新畫面＋返回鍵，不再是同畫面內部 mutate 狀態）。新增純畫面呈現用的 `_GroupTile` 資料類別與 `_buildGroupTiles()`（依 `_groups` 排序、「未分類」強制排最後、只保留非空分類、對 `_groups` 快照可能落後於 `_books` 的孤兒 `groupName` 提供兜底桶），以及 `_GroupGridTile`／`_GroupListTile` 兩個純顯示 widget（重用既有 `_BookCover`）。`_buildBookList()` 把拼貼格與書籍合併進同一個 `itemBuilder` 的 index 空間（拼貼格固定在前）。此變動屬於「移除舊 UI／新增拼貼格／新增導覽／管理分類入口搬遷」四者因果耦合、不可分批上線的**單次原子切換**——Task 1 完成生產程式碼與既有測試改寫的完整切換，Task 2 補齊測試決策要求的額外覆蓋率。

**Tech Stack:** Flutter/Dart（`app/lib/screens/library_screen.dart`、`app/test/screens/library_screen_test.dart`）。不涉及 SQLite schema、不涉及原生程式碼。

## Global Constraints

- **語言**：所有程式碼註解、commit 訊息、計畫文件皆用正體中文（`CLAUDE.md`）。
- **不修改 `LibraryRepository` 介面**——`listGroups()`（`name ASC`）／`listBooks({groupFilter})` 已存在，本工單純粹是 UI 層接線（`spec.md`「功能 ③ 分類 2×2 拼貼格」）。
- **不修改 `library_group_management_dialog.dart`**——「管理分類」對話框本身的新增/刪除/重新命名邏輯與其內部 Key（`library_group_add_field`／`library_group_delete_button_*`／`library_group_rename_*`／`library_group_manage_item_*`）完全不受影響，只有「誰來開啟這個對話框、開啟後如何收尾」這件事（`_openManageGroupsDialog()`）在本工單範圍內。
- **分類格排除在既有長按多選機制之外**——不能被勾選、不參與批次刪除/移動；選取模式進行中時，拼貼格 `onTap` 必須為 `null`（比照舊版 `_buildGroupTabs()` 在 `_inSelectionMode` 時停用 Chip 互動的既有慣例）。
- **不新增分類本身的長按操作選單**——改名/刪除分類仍統一走「管理分類」對話框，拼貼格上不做快捷操作（`design.md` 範圍界定）。
- **本工單四項變動（移除 Chip 列／新增拼貼格／新增 `groupFilter` 導覽／管理分類入口搬遷）因果耦合，不可分批上線**——Task 1 必須一次到位完成生產程式碼切換與所有直接受影響的既有測試改寫，中途不可能存在「半套」的可合併狀態。
- **參考文件**：`docs/epics/epic-19-shelf-reading-enhance/design.md`「決策」③分類 2×2 拼貼格；`docs/epics/epic-19-shelf-reading-enhance/spec.md`「功能 ③ 分類 2×2 拼貼格」；`docs/epics/epic-19-shelf-reading-enhance/issues.md`「Issue 3」。

---

### Task 1: 核心切換——拆除分類 Chip 列，換上分類拼貼格＋單一分類篩選導覽

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（範圍最大，見下方逐段說明）
- Modify: `app/test/screens/library_screen_test.dart`（改寫/移除 9 個既有測試、新增 1 個核心導覽測試、新增 1 個返回重載回歸測試、新增 1 個 `_loadGroups()` 回歸測試〔審查修正後補上〕、新增 1 個測試輔助函式）

**Interfaces:**
- Consumes: `LibraryRepository.listGroups()`（`name ASC`，既有介面）／`listBooks({groupFilter})`（既有介面）／既有 `_BookCover` widget。
- Produces: `LibraryScreen.groupFilter`（`final String?`，新建構參數，non-required）、`_GroupTile`（`{name, previewBooks, totalCount}`）、`_buildGroupTiles(List<Book> books) -> List<_GroupTile>`、`_GroupGridTile`/`_GroupListTile`（`{tile, onTap}`，`onTap` 為 `VoidCallback?`）、`_openGroupFilteredView(String groupName)`、`Key('group_tile_${name}')`、`Key('library_manage_groups_button')`——Task 2 只新增測試，不改變這些簽章。

- [x] **Step 1: 改寫既有測試、移除失效測試、新增核心導覽測試**

在 `app/test/screens/library_screen_test.dart` 頂部（`main()` 函式外、`_testBook` 函式之前或之後皆可，這裡放在檔案最後、`_testBook` 之後）新增一個測試輔助函式：

```dart
/// 找出目前 widget 樹中 `groupFilter` 等於 [groupName] 的那個 LibraryScreen
/// 實例（即 _openGroupFilteredView 推入的篩選畫面）。MaterialPageRoute
/// 預設 `maintainState: true`，背景畫面（groupFilter == null 的頂層畫面）
/// 推入新畫面後仍留在 widget 樹中，兩個 LibraryScreen 實例的書籍/拼貼格
/// key 會同時存在——後續斷言一律搭配 find.descendant(of: 這個 finder, ...)
/// 限定搜尋範圍在篩選畫面本身，避免誤判到背景畫面的同名 widget。
Finder _filteredLibraryScreenFinder(String groupName) => find.byWidgetPredicate(
      (widget) => widget is LibraryScreen && widget.groupFilter == groupName,
    );
```

**（1）修正 `選擇「書名」排序後，書架清單依書名字母順序重新排列`（第 363-420 行）**——兩本書皆為預設「未分類」，切到列表檢視後會多一個「未分類」拼貼格 `ListTile`，恆排最前面，需要 `.skip(1)` 跳過它：

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
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 兩本書皆為預設「未分類」，書架會多顯示 1 個「未分類」拼貼格
    // ListTile，恆排在書籍之前（見 _buildBookList 合併 index 空間的規則）
    // ——用 .skip(1) 跳過它，只比較書籍本身的順序。
    var titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .skip(1)
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['B書', 'A書']);

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .skip(1)
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['A書', 'B書']);
  });
```

**（2）改寫 `點擊分類 tab 後，畫面只顯示該群組的書籍；點擊「全部」顯示所有書籍`（第 461-492 行）**——不再有「全部」chip，改為點擊拼貼格推入篩選畫面、返回鍵回到頂層（頂層畫面本身從未被 mutate，永遠顯示全部書籍）：

```dart
  testWidgets('點擊分類拼貼格後只顯示該分類書籍；返回後恢復書架顯示全部書籍',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsNothing,
    );

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

**（3）改寫 `管理分類對話框：新增分類後，新分類出現在 tab 列`（第 494-523 行）**——新分類尚無書籍歸屬，`_buildGroupTiles()` 只保留非空分類，書架上不會出現對應拼貼格（這是設計決策，不是缺陷）：

```dart
  testWidgets('管理分類對話框：新增分類後，因無書籍歸屬，書架不會顯示該分類的拼貼格',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
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

    // 新分類目前沒有任何書籍歸屬，_buildGroupTiles() 只保留非空分類，故
    // 書架上不會出現「奇幻」拼貼格（design.md 決策：拼貼格只代表非空分類）。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });
```

**（4）改寫 `管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於「未分類」篩選`（第 525-563 行）**：

```dart
  testWidgets(
      '管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於「未分類」拼貼格',
      (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);

    await tester.tap(find.byKey(Key('group_tile_${BookGroup.uncategorized}')));
    await tester.pumpAndSettle();

    final filteredScreenFinder =
        _filteredLibraryScreenFinder(BookGroup.uncategorized);
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
  });
```

**（5）改寫 `管理分類對話框：刪除確認對話框按下取消，分類與所屬書籍皆不受影響`（第 565-600 行）**：

```dart
  testWidgets('管理分類對話框：刪除確認對話框按下取消，分類與所屬書籍皆不受影響', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
  });
```

**（6）保留不變：`管理分類對話框：嘗試刪除「未分類」時操作被禁止（找不到刪除/重新命名按鈕）`（第 602-631 行）**——純粹在管理分類對話框內操作，與拼貼格無關，不需要改動。

**（7）改寫 `管理分類對話框：重新命名分類後，tab 列顯示新名稱`（第 633-668 行）**：

```dart
  testWidgets('管理分類對話框：重新命名分類後，拼貼格顯示新名稱', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
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

    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });
```

**（8）整段刪除 `刪除目前篩選中的分類後，畫面自動退回「全部」篩選（不留在已不存在的分類）`（第 670-702 行）**——這個情境在新設計下已經不可能發生：「管理分類」入口只出現在 `groupFilter == null` 的頂層畫面 AppBar，分類篩選畫面（`groupFilter != null`）內完全沒有「管理分類」按鈕可點，使用者不可能在檢視某個分類時把該分類自己刪掉。把整個 `testWidgets(...)` 區塊（含其結尾的 `});`）直接刪除，不需要替代測試——這個「不可能發生」的保證改由下方 Step 1（10）新增的核心導覽測試裡「篩選畫面不顯示管理分類按鈕」這條斷言把關。

**（9）修正 `點擊「選擇資料夾」，確認自動分類開關後，匯入資料夾內書籍並依資料夾名稱建立分類`（第 704-756 行）**——只需把第 755 行的 key 改名：

```dart
    expect(find.byKey(const Key('group_tile_歷史小說')), findsOneWidget);
```

（原本是 `find.byKey(const Key('library_group_tab_歷史小說'))`，其餘程式碼不變。）

**（10）改寫 `選取多本書後點擊「移動到分類」，選擇目的分類後所有已勾選書籍的分類皆更新`（第 874-914 行）**：

```dart
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
          prefsManager: prefsManager,
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

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsOneWidget,
    );
  });
```

**（11）改寫 `書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動`（第 916-962 行）**：

```dart
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
          prefsManager: prefsManager,
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

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsOneWidget,
    );
  });
```

**（12）新增核心導覽測試**——放在（11）之後（原「選取模式下 AppBar 顯示刪除按鈕...」測試之前）：

```dart
  testWidgets(
      '點擊分類拼貼格會推入新的 LibraryScreen 並以該分類篩選；篩選畫面不顯示拼貼格區塊與管理分類按鈕',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(filteredScreenFinder, findsOneWidget);

    // AppBar 標題顯示分類名稱，不是「書架」（此文字在整棵樹中唯一——背景
    // 畫面的拼貼格文字是「奇幻 (1)」而非單獨的「奇幻」，不會誤判）。
    expect(find.text('奇幻'), findsOneWidget);

    // 篩選畫面本身不顯示拼貼格區塊、不顯示「管理分類」按鈕（用 descendant
    // 限定搜尋範圍在篩選畫面內，避免誤判到背景仍掛載的頂層畫面自己的拼貼
    // 格／管理分類按鈕——MaterialPageRoute 預設 maintainState: true，背景
    // 畫面推入新畫面後仍留在 widget 樹中）。
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('group_tile_奇幻')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('library_manage_groups_button')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsNothing,
    );
  });
```

**（13）新增返回重載回歸測試**——`_openGroupFilteredView` 推入的畫面是獨立的 `LibraryScreen` State 實例，在裡面移動/刪除書籍只會更新該實例自己的 `_books`，不會touch 背景頂層畫面的狀態；若 `_openGroupFilteredView` 沒有在返回時重新載入頂層資料，頂層拼貼格與書籍清單會停留在使用者離開當下的舊快照（比照既有 `_openBook()` 的 `.then()` 修正所防範的同類問題，見 `library_screen.dart:369-378`）。本測試守護 Step 3(d) 新增的 `.then()` 重載邏輯：

```dart
  testWidgets(
      '從分類篩選畫面把書移到其他分類後返回書架，頂層拼貼格與書籍清單即時反映最新狀態',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '科幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (1)'), findsOneWidget);
    expect(find.text('科幻 (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    await tester.longPress(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_科幻')));
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    // bookA 已被移出「奇幻」——「奇幻」拼貼格應消失（剩 0 本，
    // _buildGroupTiles 只保留非空分類），「科幻」拼貼格應顯示 2 本。若
    // _openGroupFilteredView 沒有在返回時呼叫 _loadBooks()，這裡會錯誤地
    // 仍顯示「奇幻 (1)」／「科幻 (1)」的舊快照。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
    expect(find.text('科幻 (2)'), findsOneWidget);
  });
```

**（14）新增 `_loadGroups()` 回歸測試——實作完成後程式碼審查發現，見 `tmp/epic-19/plan-issue-3-code-review.md` Important 項目**：篩選畫面的「匯入書籍」按鈕沒有比照「管理分類」用 `groupFilter == null` 隱藏，「選擇資料夾＋自動分類」仍可在篩選畫面內建立新分類（`BookImportServiceImpl.importFolder()` 內部呼叫 `repository.upsertGroup()`）。此測試驗證：在篩選畫面內建立新分類、返回頂層後，新分類拼貼格排在「未分類」之前（而非落入孤兒兜底桶排到最後），守護 (13) 之後補上的 `_loadGroups()` 呼叫：

```dart
  testWidgets(
      '【審查修正】從分類篩選畫面內用「選擇資料夾＋自動分類」建立新分類後返回書架，'
      '新分類拼貼格排在「未分類」之前，而非落入孤兒兜底桶排到最後',
      (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    const metadataChannel = MethodChannel('elinkbook/book_metadata');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadataChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(metadataChannel, (call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '武俠小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    // 另備一本「未分類」書籍，確保頂層書架本來就有一個「未分類」拼貼格
    // 可以拿來比較相對順序（若沒有任何書籍留在未分類，就沒有基準點可比）。
    final uncategorizedBook =
        _testBook(id: '2', title: '一般書', groupName: BookGroup.uncategorized);
    final repository =
        FakeLibraryRepository(initialBooks: [book, uncategorizedBook]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: BookImportServiceImpl(repository: repository),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    // 篩選畫面內的「匯入書籍」入口沒有比照「管理分類」用 groupFilter ==
    // null 隱藏，故仍可在此觸發「選擇資料夾＋自動分類」，建立一個頂層
    // _groups 快照原本不知道的新分類。
    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    await tester.tap(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('library_import_button')),
      ),
    );
    await tester.pumpAndSettle();
    // PopupMenuButton 的選單項目透過 Overlay 路由渲染，不是觸發它的
    // LibraryScreen 的 descendant，故這裡不能比照上面用 find.descendant
    // 限定範圍——但這個選單同一時間只會有一份，不會有背景/前景重複的問
    // 題，直接用未限定範圍的 find.byKey 即可（比照既有「點擊「選擇資料
    // 夾」...」測試的既有寫法）。
    await tester.tap(find.byKey(const Key('library_import_folder_option')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    // Navigator.pop 會把被彈出的篩選畫面從 widget 樹移除（跟 push 不同，
    // 不會留下背景重複實例），故此時切到列表檢視只會影響剩下的頂層畫面，
    // library_view_mode_toggle 這個 key 在樹中唯一。切到列表檢視是為了用
    // _GroupListTile 的 ListTile.title（純分類名稱，不含數量）方便比對順
    // 序——格狀檢視的 _GroupGridTile 是 InkWell，不是 ListTile。
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 若 _openGroupFilteredView() 的 .then() 沒有一併呼叫 _loadGroups()，
    // 「武俠小說」不在頂層 _groups 快照中，會被 _buildGroupTiles() 的孤兒
    // 兜底桶排到「未分類」之後；正確行為應是「武俠小說」（name ASC 排序
    // 上在「奇幻」與「未分類」之間）出現在「未分類」之前。
    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .where((title) =>
            title == '奇幻' ||
            title == '武俠小說' ||
            title == BookGroup.uncategorized)
        .toList();
    expect(tileTitles.indexOf('武俠小說'),
        lessThan(tileTitles.indexOf(BookGroup.uncategorized)));
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: FAIL——大量測試因 `find.byKey(const Key('group_tile_...'))`／`find.byKey(const Key('library_manage_groups_button'))` 找不到任何 widget（生產程式碼尚未新增拼貼格與 AppBar 按鈕，仍是舊的 `_buildGroupTabs()` Chip 列）而失敗；`LibraryScreen` 建構子也還沒有 `groupFilter` 具名參數，若 Dart 分析器先跑會直接報編譯錯誤（`groupFilter` 未定義）——這是預期中的紅燈狀態。

- [x] **Step 3: 實作生產程式碼（一次到位）**

修改 `app/lib/screens/library_screen.dart`，依序完成以下段落（因四項變動因果耦合，需一次改完才能編譯通過）：

**(a) `LibraryScreen` 建構參數新增 `groupFilter`**（原第 28-56 行）：

```dart
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
  final String? groupFilter;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.groupFilter,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
```

**(b) `initState()` 由 `widget.groupFilter` 一次性初始化 `_groupFilter`**（原第 69-73 行）：

```dart
  @override
  void initState() {
    super.initState();
    _groupFilter = widget.groupFilter;
    _initialize();
  }
```

**(c) 移除 `_changeGroupFilter()`**（原第 221-224 行）——直接刪除這個方法，不再被任何 UI 呼叫：

```dart
  Future<void> _changeGroupFilter(String? groupFilter) async {
    setState(() => _groupFilter = groupFilter);
    await _loadBooks();
  }
```

**(d) `_openManageGroupsDialog()` 移除「篩選中分類被刪除時重置」安全網**（原第 381-400 行）：

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
    await _loadBooks();
  }
```

緊接著在 `_openManageGroupsDialog()` 之後新增 `_openGroupFilteredView()`：

```dart
  void _openGroupFilteredView(String groupName) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LibraryScreen(
              repository: widget.repository,
              importService: widget.importService,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              currentTheme: widget.currentTheme,
              isEinkMode: widget.isEinkMode,
              onThemeChanged: widget.onThemeChanged,
              onEinkModeChanged: widget.onEinkModeChanged,
              groupFilter: groupName,
            ),
          ),
        )
        .then((_) {
      // 【審查修正】推入的畫面是獨立的 LibraryScreen State 實例，在裡面
      // 移動/刪除書籍只會更新該實例自己的 _books/_groups，不會 touch 這裡
      // （背景頂層畫面）的狀態；返回時若不重新載入，頂層拼貼格與書籍清單
      // 會停留在使用者離開當下的舊快照（比照既有 _openBook() 的 .then()
      // 修正所防範的同類問題）。
      //
      // 【審查修正——實作完成後程式碼審查發現，見
      // tmp/epic-19/plan-issue-3-code-review.md Important 項目】原本只呼
      // 叫 _loadBooks()，理由是「管理分類」入口在 groupFilter != null 的
      // 篩選畫面上不顯示，篩選畫面內無法變動分類名稱集合——但這個假設不
      // 成立：篩選畫面的 AppBar 仍保留「匯入書籍」按鈕（未比照「管理分
      // 類」用 groupFilter == null 隱藏），而「選擇資料夾＋依資料夾名稱
      // 自動建立分類」會呼叫 BookImportServiceImpl.importFolder() 內部的
      // repository.upsertGroup()，確實可以在篩選畫面內建立新分類。若不一
      // 併呼叫 _loadGroups()，頂層的 _groups 快照就不包含新分類，
      // _buildGroupTiles() 的孤兒兜底桶會把新分類排到「未分類」之後，違
      // 反「未分類固定排最後」的不變量，故改為與 _loadBooks() 一起重新
      // 載入。
      if (!mounted) return;
      _loadGroups();
      _loadBooks();
    });
  }
```

**(e) `build()` 移除 `_buildGroupTabs()` 呼叫**（原第 402-435 行，只移除 `_buildGroupTabs(),` 這一行，其餘結構不變）：

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
            : Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: books.isEmpty
                            ? _buildEmptyState()
                            : _buildBookList(books),
                      ),
                    ],
                  ),
                  if (_isImporting) _buildImportingOverlay(),
                ],
              ),
      ),
    );
  }
```

**(f) `_buildNormalAppBar()` 標題依 `groupFilter` 決定，「管理分類」搬進 `actions`**（原第 456-536 行，整段替換）：

```dart
  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      title: Text(widget.groupFilter ?? '書架'),
      actions: [
        _buildThemeDot(
            AppTheme.light, const Color(0xFFF5F5F5), 'library_theme_dot_light'),
        _buildThemeDot(
            AppTheme.dark, const Color(0xFF121212), 'library_theme_dot_dark'),
        _buildThemeDot(
            AppTheme.sepia, const Color(0xFFF4ECD8), 'library_theme_dot_sepia'),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('library_eink_toggle'),
          icon: Icon(
            widget.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
            color:
                widget.isEinkMode ? Theme.of(context).colorScheme.primary : null,
          ),
          tooltip: 'E-Ink 高對比模式',
          onPressed: () => widget.onEinkModeChanged?.call(!widget.isEinkMode),
        ),
        const VerticalDivider(width: 1, indent: 12, endIndent: 12),
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
          enabled: !_isImporting,
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
        if (widget.groupFilter == null)
          IconButton(
            key: const Key('library_manage_groups_button'),
            icon: const Icon(Icons.category),
            tooltip: '管理分類',
            onPressed: _openManageGroupsDialog,
          ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    SettingsScreen(prefsManager: widget.prefsManager),
              ),
            );
          },
        ),
      ],
    );
  }
```

**(g) 整段刪除 `_buildGroupTabs()`**（原第 594-636 行）：

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

**(h) 在 `_buildEmptyState()` 之後、`_buildBookList()` 之前新增 `_buildGroupTiles()`**：

```dart
  /// 依目前已載入的 [books]（已依 _sortBy 排序）與 [_groups]（name ASC，
  /// 「未分類」強制排最後）分組，只保留非空分類。
  ///
  /// `_groups` 是 `_loadGroups()` 讀取的記憶體快照，既有的 `_loadGroups()`
  /// 錯誤處理邏輯本身承認暫時性讀取失敗時會保留舊快照——故 `book.groupName`
  /// 理論上可能不在目前的 `_groups` 清單中、也不是 `BookGroup.uncategorized`
  /// （`_groups` 落後於 `_books` 的情境）。若只依 `_groups` 組出
  /// `orderedNames`，這些書籍會被整批漏掉、從書架上「消失」而非只是分類格
  /// 顯示不完整，後果比拼貼格排序錯誤嚴重得多，故補一個兜底桶收留所有未
  /// 被涵蓋的 `groupName`，確保 `byGroup` 裡的書一定會出現在某個拼貼格。
  ///
  /// 【審查意見，不要求改動】若同時存在多個孤兒 `groupName`，彼此之間的
  /// 順序取決於 `byGroup.keys`（`LinkedHashMap` 插入順序＝書籍依目前
  /// `_sortBy` 排序後被迭代到的順序），並非依名稱字母排序。`spec.md`／
  /// `design.md` 只要求孤兒不會讓書籍消失，沒有規範多個孤兒彼此的相對
  /// 順序，故此處維持現況，僅記錄此已知特性供日後參考。
  List<_GroupTile> _buildGroupTiles(List<Book> books) {
    final byGroup = <String, List<Book>>{};
    for (final book in books) {
      byGroup.putIfAbsent(book.groupName, () => []).add(book);
    }
    final orderedNames = [
      for (final group in _groups)
        if (group.name != BookGroup.uncategorized) group.name,
      BookGroup.uncategorized,
      for (final name in byGroup.keys)
        if (name != BookGroup.uncategorized &&
            !_groups.any((g) => g.name == name))
          name,
    ];
    return [
      for (final name in orderedNames)
        if (byGroup[name]?.isNotEmpty ?? false)
          _GroupTile(
            name: name,
            previewBooks: byGroup[name]!.take(4).toList(),
            totalCount: byGroup[name]!.length,
          ),
    ];
  }
```

**(i) `_buildBookList()` 整段替換為合併分類格與書籍的版本**（原第 655-696 行）：

```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    final groupTiles = widget.groupFilter == null
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    final itemCount = groupTiles.length + books.length;
    Widget itemBuilder(BuildContext context, int index, {required bool isGrid}) {
      if (index < groupTiles.length) {
        final tile = groupTiles[index];
        // 選取模式進行中時，分類格不可觸發導覽（onTap 傳 null），比照舊版
        // _buildGroupTabs() 對 Chip 在 _inSelectionMode 時一律停用互動的
        // 既有慣例——否則使用者長按多選書籍時誤觸分類格，會帶著選取狀態
        // 被推入另一個 LibraryScreen 實例，選取列顯示與計數會與使用者預
        // 期不符。
        final onTap =
            _inSelectionMode ? null : () => _openGroupFilteredView(tile.name);
        return isGrid
            ? _GroupGridTile(tile: tile, onTap: onTap)
            : _GroupListTile(tile: tile, onTap: onTap);
      }
      final book = books[index - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
            );
    }
    if (_viewMode == LibraryViewMode.grid) {
      final orientation = MediaQuery.orientationOf(context);
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) =>
            itemBuilder(context, index, isGrid: true),
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemBuilder(context, index, isGrid: false),
    );
  }
```

**(j) 在 `_LibraryScreenState` 類別結尾（原第 697 行 `}` 之後）、`_sortLabel()` 之前，新增 `_GroupTile`／`_GroupGridTile`／`_GroupListTile` 三個 private 類別**：

```dart
/// 單一分類在書架分類拼貼格上的顯示資料，純畫面呈現用途，不持久化、不
/// 跨檔案共用，故不建成 library/models 底下的公開模型。
class _GroupTile {
  final String name;
  final List<Book> previewBooks; // 最多 4 本，依目前排序結果順序截取前 4 筆
  final int totalCount;
  const _GroupTile({
    required this.name,
    required this.previewBooks,
    required this.totalCount,
  });
}

/// 分類拼貼格（格狀檢視）：2×2 拼貼＋分類名稱/數量，重用既有 _BookCover。
/// onTap 為 null 時（選取模式進行中）InkWell 自動停用點擊反饋，比照
/// Flutter 既有「null 停用互動」慣例。
class _GroupGridTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap;
  const _GroupGridTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('group_tile_${tile.name}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              // GridView 是 BoxScrollView 的子類，padding 為 null 時會自動
              // 吃進 MediaQuery.of(context).padding（垂直捲動吃 top/bottom
              // safe area）；這個巢狀在拼貼格內的小型 GridView 若不明講
              // padding: EdgeInsets.zero，會意外套上裝置狀態列/導覽列高度
              // 的內距，把 2×2 封面擠壓變形。
              padding: EdgeInsets.zero,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(
                4,
                (i) => i < tile.previewBooks.length
                    ? _BookCover(book: tile.previewBooks[i])
                    : ColoredBox(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${tile.name} (${tile.totalCount})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 分類拼貼格（列表檢視）：橫向 4 張小縮圖＋名稱＋數量，不強行套用 2×2
/// 方形拼貼於列表列。
class _GroupListTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap; // null＝選取模式進行中，停用點擊（同 _GroupGridTile）
  const _GroupListTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('group_tile_${tile.name}'),
      leading: SizedBox(
        width: 4 * 32,
        height: 48,
        child: Row(
          children: List.generate(
            4,
            (i) => SizedBox(
              width: 32,
              height: 48,
              child: i < tile.previewBooks.length
                  ? _BookCover(book: tile.previewBooks[i])
                  : ColoredBox(color: Colors.grey.shade200),
            ),
          ),
        ),
      ),
      title: Text(tile.name),
      subtitle: Text('${tile.totalCount} 本'),
      onTap: onTap,
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部測試通過，含既有測試無回歸）。

- [x] **Step 5: 執行靜態分析確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-19): Issue 3 Task 1 拆除分類 Chip 列，換上分類 2x2 拼貼格與單一分類篩選導覽"
```

---

### Task 2: 補齊測試決策要求的細節覆蓋

**Files:**
- Modify: `app/test/screens/library_screen_test.dart`（新增 6 個測試，皆不需要修改 Task 1 已完成的生產程式碼）

**Interfaces:**
- Consumes: Task 1 產出的 `_buildGroupTiles()`／`_GroupGridTile`／`_GroupListTile`／`_openGroupFilteredView()`／`Key('group_tile_...')`（全部透過既有 widget 樹間接驗證，測試檔案本身不能直接引用這些 private 符號）。
- Produces: 無新的對外符號，純測試覆蓋率補強。

- [x] **Step 1: 撰寫測試**

在 `app/test/screens/library_screen_test.dart` 內，緊接 Task 1 新增的「點擊分類拼貼格會推入新的 LibraryScreen...」測試之後，新增以下 6 個測試：

**（1）分組排序正確性——`name ASC`，「未分類」強制排最後：**

```dart
  testWidgets('分類拼貼格依名稱 A-Z 排序，「未分類」強制排在所有具名分類之後',
      (tester) async {
    final bookSci = _testBook(id: '1', title: '科幻書', groupName: '科幻');
    final bookFan = _testBook(id: '2', title: '奇幻書', groupName: '奇幻');
    final bookNone = _testBook(id: '3', title: '未分類書');
    final repository =
        FakeLibraryRepository(initialBooks: [bookSci, bookFan, bookNone]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 列表檢視下拼貼格是 ListTile（_GroupListTile.title 只顯示分類名稱，
    // 不含數量），用它的 title 文字順序驗證排序（name ASC：奇幻 < 科幻，
    // 依 Dart String 預設 UTF-16 碼點比較；未分類固定排最後）。
    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .take(3)
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(tileTitles, ['奇幻', '科幻', BookGroup.uncategorized]);
  });
```

**（2）孤兒 `groupName` 兜底桶——`_groups` 快照落後於 `_books` 時仍會被收留：**

```dart
  testWidgets('_groups 快照落後於 _books 時，孤兒 groupName 仍會被兜底桶收留，不會讓書籍消失',
      (tester) async {
    final book = _testBook(id: '1', title: '懸疑小說', groupName: '懸疑');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 直接繞過 UI 呼叫 repository.updateBook()，模擬「_groups 快照落後於
    // _books」的情境（例如另一裝置端已新增分類，但本機 _groups 尚未重新
    // 整理）——FakeLibraryRepository.updateBook() 不會同步更新 _groups
    // （比照 SqliteLibraryRepository 的既有分工，_groups 是獨立載入的快
    // 照，見 _loadGroups()）。
    await repository.updateBook(book.copyWith(groupName: '科幻'));
    // 觸發 _loadBooks()（不觸發 _loadGroups()）：_changeSortBy() 只重讀
    // _books，不重讀 _groups，正好模擬「_groups 落後」情境。
    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    // '科幻' 不在 _groups 快照中（快照仍是建構時的 {未分類, 懸疑}），書籍
    // 仍應被兜底桶收留、出現在某個拼貼格，而不是從書架上「消失」。
    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.text('科幻 (1)'), findsOneWidget);
  });
```

**（3）`previewBooks` 只截取前 4 筆且保留原排序：**

```dart
  testWidgets('分類拼貼格的封面預覽只取該分類前 4 本書，且保留目前排序結果的順序',
      (tester) async {
    final now = DateTime.now();
    final books = [
      for (var i = 0; i < 4; i++)
        Book(
          id: '${i + 1}',
          title: '奇幻書${i + 1}',
          author: null,
          format: BookFileFormat.epub,
          filePath: 'content://example/${i + 1}.epub',
          source: BookSource.local,
          groupName: '奇幻',
          createTime: now,
          lastReadTime: now.subtract(Duration(minutes: i)),
        ),
      // 第 5 本書刻意用不同格式（txt → Icons.article）且 lastReadTime 最
      // 舊（預設「最後閱讀」排序下排最後），用來驗證 previewBooks.take(4)
      // 確實把它排除在封面預覽之外——若截取邏輯錯誤（例如順序顛倒），這
      // 裡會多出一個 Icons.article。
      Book(
        id: '5',
        title: '奇幻書5',
        author: null,
        format: BookFileFormat.txt,
        filePath: 'content://example/5.txt',
        source: BookSource.local,
        groupName: '奇幻',
        createTime: now,
        lastReadTime: now.subtract(const Duration(minutes: 10)),
      ),
    ];
    final repository = FakeLibraryRepository(initialBooks: books);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (5)'), findsOneWidget);

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(
      find.descendant(
        of: tileFinder,
        matching:
            find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.menu_book),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching:
            find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.article),
      ),
      findsNothing,
    );
  });
```

**（4）不足 4 本時的空格佔位——格狀檢視：**

```dart
  testWidgets('分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻 (2)'), findsOneWidget);

    // 2 本書皆無 coverPath，_BookCover 各自退回格式圖示佔位（Icon），故拼
    // 貼格內應有 2 個 Icon（書封佔位）＋ 2 個中性灰色塊（拼貼格本身「不
    // 足 4 本」的空格佔位，色階 grey.shade200，與 _BookCover 內部佔位的
    // shade300 不同，可用色階區分兩者，不需要存取 private widget 型別）。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(2),
    );
  });
```

**（5）不足 4 本時的空格佔位——列表檢視：**

```dart
  testWidgets('分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位', (tester) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(1),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(3),
    );
  });
```

**（6）選取模式下拼貼格 `onTap` 停用＋`_buildBookList` 合併 index 空間（拼貼格恆排最前）：**

```dart
  testWidgets('長按進入選取模式後，分類拼貼格的 onTap 停用，點擊不觸發導覽也不影響選取狀態',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    // 選取狀態不受影響、沒有觸發 Navigator.push（沒有跳轉離開，選取列仍
    // 顯示在同一個畫面上）。
    expect(find.text('已選取 1 本'), findsOneWidget);
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);
  });

  testWidgets('_buildBookList 合併分類格與書籍的 index 空間，分類格恆排在書籍之前',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 2 本書分屬 2 個不同分類 → 2 個拼貼格（ListTile）+ 2 本書（也是
    // ListTile，見 _BookListTile）。驗證拼貼格恆排最前面：前 2 個
    // ListTile 的 title 應為分類名稱，之後才是書名。
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['奇幻', BookGroup.uncategorized, 'A書', 'B書']);
  });
```

- [x] **Step 2: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS——這 6 個測試驗證的行為皆已在 Task 1 的生產程式碼中實作完成（`_buildGroupTiles()`／`_GroupGridTile`／`_GroupListTile`／選取模式停用 `onTap`／合併 index 空間皆已到位），故應直接通過，不需要額外的生產程式碼異動。若任何一個失敗，代表 Task 1 的實作有缺漏，須回頭修正 Task 1 的程式碼而非放寬這裡的斷言。

- [x] **Step 3: 回歸確認既有 grid 欄數測試不受影響**

Run: `cd app && flutter test test/screens/library_screen_test.dart -n "封面格數為|封面欄數即時|封面格狀檢視含欄格間距"`
Expected: PASS——這 4 個測試（epic-18 Issue 3 新增）只檢查 `GridView` 的 `SliverGridDelegateWithFixedCrossAxisCount.crossAxisCount`／`crossAxisSpacing`／`mainAxisSpacing` 屬性值，與 `itemCount`（拼貼格+書籍的合併總數）或個別 item 的索引位置無關，故不受本工單影響；此步驟只是依 `spec.md`「已知測試影響」章節的提醒，明確重跑一次確認。

- [x] **Step 4: 執行全專案測試與靜態分析確認無回歸**

Run: `cd app && flutter test`
Expected: PASS。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/test/screens/library_screen_test.dart
git commit -m "feat(epic-19): Issue 3 Task 2 補齊分類拼貼格排序/兜底桶/空格佔位/選取模式互動測試覆蓋"
```

---

### Task 3: 真機驗收

**Files:** 無程式碼異動，僅驗收記錄。

- [ ] **Step 1: 建置並安裝 debug APK**

Run: `cd app && flutter clean && flutter build apk --debug`

安裝到既有測試裝置。

- [ ] **Step 2: 驗收拼貼格顯示（格狀＋列表兩種檢視）**

匯入數本書並分別歸入至少 2 個具名分類＋部分維持「未分類」。分別在格狀與列表檢視下確認：每個非空分類各顯示一格（2×2 封面拼貼／橫向 4 縮圖），名稱＋本數正確；不足 4 本時空格為中性灰色佔位，不拉伸/不重複封面；分類格依名稱排序，「未分類」固定排最後、且恆排在所有書籍項目之前。

- [ ] **Step 3: 驗收點擊拼貼格進入篩選畫面**

點擊任一分類拼貼格，確認 AppBar 標題顯示分類名稱、不顯示拼貼格區塊、不顯示「管理分類」按鈕；畫面內排序切換、格狀/列表檢視切換、長按進入選取模式並執行刪除（見 Issue 2）皆正常運作；按返回鍵可退回書架頂層，書架仍正確顯示全部書籍與所有分類拼貼格。

- [ ] **Step 4: 驗收「管理分類」入口搬遷**

書架頂層 AppBar 的「管理分類」圖示按鈕功能與原本一致（新增/刪除/重新命名分類）；確認分類篩選畫面內找不到「管理分類」入口。

- [ ] **Step 5: 驗收選取模式下拼貼格停用**

長按任一本書進入選取模式後，點擊任一分類拼貼格確認無反應（不會跳轉離開、選取狀態與計數不受影響）。

- [ ] **Step 6: 回歸確認既有功能**

確認排序（最後閱讀/建立時間/作者/書名）、格狀/列表檢視記憶上次選擇、匯入（檔案/資料夾）、批次移動到分類、批次刪除書籍（Issue 2）等既有功能皆不受本次變動影響。

- [ ] **Step 7: 更新 `issues.md`**

將 `docs/epics/epic-19-shelf-reading-enhance/issues.md` Issue 3 的 `Status:` 改為 `✅ 已完成`，並記錄上述真機驗收結果。
