# Epic 27 Issue 8：書架排序選單加入當前模式選中指示 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解決書架排序選單無法辨識目前生效排序模式的問題，在各選項前方加入打勾指示圖示（Checkmark）與選中文字粗體高亮。

**Architecture:**
- 修改 `LibraryScreen._buildNormalAppBar` 中的 `PopupMenuButton<LibrarySortBy>`。
- 每個 `PopupMenuItem<LibrarySortBy>` 內部改為 `Row` 佈局：
  - 前方放置固定 24dp 寬度的圖示容器，若為當前選中的排序方式則顯示 `Icons.check`，否則為空佔位（確保所有選項文字左對齊一致）。
  - 選項文字在選中時使用 `FontWeight.bold` 與主題色/高對比色。
  - 【審查修正 Minor】「主題色/高對比色」在 E-Ink 主題下實際上不構成辨識度貢獻：`_buildEinkTheme()`（`app_theme_data.dart:127-138`）的 `colorScheme.primary` 與 `colorScheme.onSurface` 皆為 `Colors.black`，選中/未選中文字在 E-Ink 模式下會是完全相同的黑色。這不影響驗收標準（`Icons.check` 的有無本身已是無歧義的強指示），但顏色的實際生效範圍僅限一般主題（Light/Dark/Sepia），特此記錄避免後續維護者誤以為顏色也在 E-Ink 下起了作用。

**Tech Stack:** Flutter 3, Material 3, Dart

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 8」

## Global Constraints

- **Language**: 程式碼註解與說明一律使用正體中文 (Traditional Chinese, zh-TW)。
- **Flutter Analyze**: 靜態分析必須保持 0 warning / 0 error。
- **Keys**: 嚴格保留 `library_sort_button` 與各選項 `library_sort_option_${sortBy.name}`。
- **測試 fixture**（【審查修正】見 `reviews/review-plan-issue-5-8.md` Recommendations #2）：新增至 `app/test/screens/library_screen_test.dart` 的測試須遵循該檔案既有的 fixture 建構模式（`FakeLibraryRepository()`／`FakeBookImportService()`／檔案共用 `prefsManager`）——Issue 5 的計畫也會修改同一份測試檔案，兩者須一致。

---

### Task 1: 改造書架排序 PopupMenuItem 顯示選中 Checkmark

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: `_bookListController.sortBy`
- Produces: 含有 `Icons.check` 與粗體標記之 `PopupMenuItem<LibrarySortBy>`

- [ ] **Step 1: Write the failing test**

在 `app/test/screens/library_screen_test.dart` 中追加測試（【審查修正 Critical】原片段 `LibraryScreen()` 完全沒有提供任何建構參數，而 `repository`／`importService`／`prefsManager` 三個參數皆為 `required`、無預設值，會直接編譯失敗；改用檔案既有 `setUp()` 已建立的 `FakeLibraryRepository()`／`FakeBookImportService()`／共用 `prefsManager` fixture 模式，比照同檔案第 100-105 行既有寫法——Issue 5 的計畫也會修改同一份測試檔案，兩者須採用同一套 fixture 模式）：

```dart
testWidgets('LibraryScreen 點擊排序按鈕，彈出選單中當前選中的排序項目顯示 Checkmark 圖示', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: LibraryScreen(
      repository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      prefsManager: prefsManager,
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('library_sort_button')));
  await tester.pumpAndSettle();

  // 預設排序為最近閱讀（lastRead）
  final lastReadItemFinder = find.byKey(const Key('library_sort_option_lastRead'));
  expect(lastReadItemFinder, findsOneWidget);

  // 驗證該項目包含 check 圖示
  expect(
    find.descendant(of: lastReadItemFinder, matching: find.byIcon(Icons.check)),
    findsOneWidget,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/library_screen_test.dart --plain-name "LibraryScreen 點擊排序按鈕，彈出選單中當前選中的排序項目顯示 Checkmark"`
預期：FAIL（因既有選單項目內無 `Icons.check`）。

- [ ] **Step 3: Write minimal implementation**

在 `app/lib/screens/library_screen.dart` 的 `_buildNormalAppBar` 中：
```dart
PopupMenuButton<LibrarySortBy>(
  key: const Key('library_sort_button'),
  icon: const Icon(Icons.sort),
  tooltip: '排序：${_sortLabel(_bookListController.sortBy)}',
  enabled: books != null,
  onSelected: _bookListController.changeSortBy,
  itemBuilder: (context) {
    final currentSort = _bookListController.sortBy;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LibrarySortBy.values.map(
      (sortBy) {
        final isSelected = currentSort == sortBy;
        return PopupMenuItem<LibrarySortBy>(
          key: Key('library_sort_option_${sortBy.name}'),
          value: sortBy,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: isSelected
                    ? Icon(Icons.check, size: 20, color: primaryColor)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                _sortLabel(sortBy),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? primaryColor : null,
                ),
              ),
            ],
          ),
        );
      },
    ).toList();
  },
),
```

- [ ] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/screens/library_screen_test.dart --plain-name "LibraryScreen 點擊排序按鈕，彈出選單中當前選中的排序項目顯示 Checkmark"`
預期：PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-27): Issue 8——書架排序選單加入選中 Checkmark 與粗體指示"
```
