# Issue 15：漫畫 EPUB 誤判為流式，新增「人工版面覆蓋」選項 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓使用者可以在 `LibraryScreen` 多選模式下，對誤判為流式（實際應為固定版面 FXL，例如漫畫）的 EPUB 書籍手動修正：新增「強制 FXL」／「恢復自動判斷」兩顆工具列按鈕，分別覆寫／重新解析 `Book.isFixedLayout`（見 `CONTEXT.md`「引擎分派判斷」「人工版面覆蓋」詞條）。

**架構：** 不新增任何資料欄位、不需要 SQLite migration。完全重用既有 `LibraryRepository` 介面：「強制 FXL」呼叫既有 `updateBook(book.copyWith(isFixedLayout: true))`；「恢復自動判斷」呼叫既有 `detectAndCacheEpubLayout(bookId, filePath)`（本來就會重新偵測並覆寫資料庫）。UI 沿用 `LibraryScreen` 現有多選模式（`_enterSelectionMode`/`_selectedBookIds`），在既有選取工具列（`_buildSelectionAppBar()`）新增兩顆獨立按鈕，行為比照既有 `_moveSelectedBooksToGroup()`（無確認對話框、無完成後 SnackBar、執行後立即退出選取模式並重新整理書架）。`ReaderScreen` 不需要任何改動——`_resolveEpubEngineDispatch()` 本來就是每次開書時才解析引擎，下次開啟該書時自然套用新值。

**Tech Stack：** Flutter/Dart，`flutter_test` widget test（純 Dart，不需裝置）。

## Global Constraints

- **範圍僅限 `LibraryScreen`**。不修改 `Book`/`BookReaderPrefs`/SQLite schema/`ReaderScreen`/`FoliateEpubReaderView`/`EpubReaderView`——`Book.copyWith()` 已支援 `isFixedLayout` 具名參數（epic-17 Issue 2 新增，見 `book.dart:123`），`LibraryRepository.updateBook()`/`detectAndCacheEpubLayout()` 已是既有介面，不需要新增任何 repository 方法。
- 兩顆按鈕批次套用於 `_selectedBookIds` 中所有 `format == BookFileFormat.epub` 的書籍；選取集合中若含 PDF/TXT，**自動跳過**、不報錯、不中斷迴圈（比照 `_deleteSelectedBooks()` 迴圈內單筆失敗不中斷整批的既有慣例，但這裡是「格式不符」而非「操作失敗」）。
- 兩顆按鈕在選取模式下**永遠顯示**（比照既有「移動到分類」「刪除」按鈕：只要 `count == 0` 才停用/不可點擊，不因選取內容的格式組成而隱藏按鈕本身）。
- 點擊後**不**彈確認對話框（比照 `_moveSelectedBooksToGroup()` 而非 `_confirmDeleteBooks()`）；執行完畢**不**額外顯示 SnackBar；行為模式：立即 `_exitSelectionMode()` → 逐筆呼叫對應 repository 方法 → `_loadBooks()` 重新整理。
- 書架封面/列表**不**新增任何視覺標記（badge）表示「已人工覆蓋」——經 grilling 確認的刻意精簡。
- **不**調查/修正 `extractMetadata`/`detectEpubLayout` 原生 channel 本身的誤判邏輯——本 Issue 只提供人工救濟手段，範圍已於 `design.md`「Issue 15 根因重新診斷與人工版面覆蓋功能」明確排除。
- 按鈕圖示（`Icons.menu_book`／`Icons.restore`）與文字（「強制 FXL」／「恢復自動判斷」）為起始建議值，非最終規格，實作階段可視真機視覺效果微調（比照 Issue 2/3 既有慣例），但兩個 `Key`（`library_force_fxl_button`／`library_restore_auto_layout_button`）與 tooltip 文字須與 `issues.md` Issue 15 條目一致。
- 真機驗收裝置固定為 `3CEF42ECD491687`；驗收需要一本已知會被誤判為流式的漫畫 EPUB（若手邊沒有現成 fixture，可用任一 metadata 不完整的漫畫 EPUB，或以現有 `sample.epub` 搭配暫時偽造誤判情境驗證「強制 FXL 後改走 Readium 路徑」這件事本身，實際漫畫渲染效果非本 Issue 驗收重點——本 Issue 只保證「引擎確實切換」，不保證「切換後漫畫排版完美」）。

**實作備註（已於程式碼審查後確認接受，見 `tmp/epic-18/review-issue-15.md` Important #2／#3）**：Task 1／Task 2 完成後，真機驗收發現「範圍僅限 `LibraryScreen`」這項 Global Constraint 的前提不完全成立——`ReaderScreen._isFixedLayout`（驅動 FXL 懸浮 chrome 顯示，非引擎分派）仍會被 native view 異步回報覆蓋，導致「強制 FXL」後設定表單短暫顯示流式選項。追加 commit `97878c4` 修改 `app/lib/screens/reader_screen.dart` 三處（`_resolveEpubEngineDispatch()`／`_handleLayoutResolved()`／`_handleFoliateLayoutResolved()`）新增保護邏輯，此屬計畫範圍外的追加，已經人類於程式碼審查後確認接受，不需要回退；已補上對應回歸測試（`reader_screen_test.dart`，鎖住「強制 FXL 後 native 異步回報不應覆蓋」這個情境）。真機驗收同時發現「橫向雙頁模式退化成單頁」症狀，根因為 Kotlin 原生端 `EpubReaderView.kt` 的雙頁 spread 計算完全依賴 Readium 自己對書本 metadata 的獨立判讀、不受「強制 FXL」影響，已判斷超出本 Issue 範圍，另立新 Issue 追蹤（見 `issues.md`），不阻擋本 Issue 合併。

---

## 檔案結構

本計劃只修改兩個檔案：

- **修改：** `app/lib/screens/library_screen.dart`（新增 2 個方法 + `_buildSelectionAppBar()` 新增 2 顆按鈕）
- **修改：** `app/test/screens/library_screen_test.dart`（`_testBook()` 擴充 `format` 參數 + 新增測試）

---

### Task 1：「強制 FXL」按鈕與方法

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `LibraryRepository.updateBook()`、`Book.copyWith(isFixedLayout: ...)`、`Book.format`（`BookFileFormat`）。
- Produces: `_forceFixedLayoutForSelectedBooks()` 方法；`_buildSelectionAppBar()` 新增 `Key('library_force_fxl_button')`。

- [x] **Step 1: 確認現況**

- [x] **Step 2: 擴充 `_testBook()` 測試 helper，支援指定 `format`**

`_testBook()`（`app/test/screens/library_screen_test.dart:2159-2182`）目前寫死 `format: BookFileFormat.epub`，無法建構非 EPUB 測試書籍。修改：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  String? coverPath,
  bool? isFixedLayout,
  BookFileFormat format = BookFileFormat.epub,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: filePath ?? 'content://example/$id.epub',
    source: BookSource.local,
    coverPath: coverPath,
    groupName: groupName,
    isFixedLayout: isFixedLayout,
    createTime: now,
    lastReadTime: now,
  );
}
```

（新增參數有預設值，既有全部呼叫端零回歸，不需要另外跑一次測試確認——這一步本身不改變任何既有測試行為。）

- [x] **Step 3: 撰寫會失敗的測試——純 EPUB 選取，點擊「強制 FXL」**

在 `app/test/screens/library_screen_test.dart` 新增（緊接既有「選取多本書後點擊『移動到分類』」測試之後，`grep -n "選取多本書後點擊「移動到分類」" app/test/screens/library_screen_test.dart` 確認行號）：

```dart
  testWidgets('選取多本 EPUB 書籍後點擊「強制 FXL」，所有已選取書籍的 isFixedLayout 皆變為 true',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A漫畫');
    final bookB = _testBook(id: '2', title: 'B漫畫');
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
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_force_fxl_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing,
        reason: '執行後應立即退出選取模式（比照移動到分類既有行為）');

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isTrue);
  });

  testWidgets(
      '選取集合混雜 EPUB 與 PDF 時，點擊「強制 FXL」只影響 EPUB、PDF 不受影響也不拋錯',
      (tester) async {
    final epubBook = _testBook(id: '1', title: 'A漫畫');
    final pdfBook = _testBook(
      id: '2',
      title: 'B文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/2.pdf',
    );
    final repository =
        FakeLibraryRepository(initialBooks: [epubBook, pdfBook]);

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

    await tester.tap(find.byKey(const Key('library_force_fxl_button')));
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isNull,
        reason: 'PDF 不具備 isFixedLayout 語意，應完全不受影響');
  });

  testWidgets('選取集合全為非 EPUB 時，「強制 FXL」按鈕仍然顯示（不隱藏/不因格式停用）',
      (tester) async {
    final pdfBook = _testBook(
      id: '1',
      title: 'A文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/1.pdf',
    );
    final repository = FakeLibraryRepository(initialBooks: [pdfBook]);

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

    expect(find.byKey(const Key('library_force_fxl_button')), findsOneWidget);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('library_force_fxl_button')),
    );
    expect(button.onPressed, isNotNull,
        reason: 'count > 0 時按鈕應可點擊，不因選取內容全為非 EPUB 而停用');
  });
```

- [x] **Step 4: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "強制 FXL"
```
預期：FAIL——`Key('library_force_fxl_button')` 找不到（按鈕尚未存在）。

- [x] **Step 5: 實作**

修改 `app/lib/screens/library_screen.dart`：

1. 在 `_moveSelectedBooksToGroup()`（第 272-290 行）之後、`_confirmDeleteBooks()`（第 292 行）之前新增：
```dart
  /// 對選取集合中所有 EPUB 書籍手動覆寫「引擎分派判斷」結果為固定版面
  /// （FXL）——救濟部分漫畫 EPUB 因來源檔案 metadata 不完整/不規範，被
  /// 「引擎分派判斷」誤判為流式的情況（見 CONTEXT.md「人工版面覆蓋」）。
  /// 非 EPUB 書籍（PDF/TXT）自動跳過，不影響、不拋錯。行為比照
  /// _moveSelectedBooksToGroup()：無確認對話框、無完成後 SnackBar，立即
  /// 退出選取模式後才逐筆寫入，避免寫入期間使用者重複點擊觸發本方法。
  /// **`selectedIds` 在 `_exitSelectionMode()` 之前捕捉是安全的**：
  /// `_exitSelectionMode()` 只把 `_selectedBookIds` 欄位重新賦值為
  /// `null`，不會 mutate 這裡捕捉到的 Set 物件本身，比照
  /// `_moveSelectedBooksToGroup()`/`_deleteSelectedBooks()` 既有慣例
  /// （已於 plan-issue-15.md 審查階段確認，見 `reviews/` 對應報告）。
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.updateBook(book.copyWith(isFixedLayout: true));
    }
    await _loadBooks();
  }
```

2. `_buildSelectionAppBar()`（第 616-642 行）的 `actions` 列表，在 `library_move_to_group_button` 之後、`library_delete_books_button` 之前新增：
```dart
        IconButton(
          key: const Key('library_force_fxl_button'),
          icon: const Icon(Icons.menu_book),
          tooltip: '強制 FXL',
          onPressed: count == 0 ? null : _forceFixedLayoutForSelectedBooks,
        ),
```

- [x] **Step 6: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "強制 FXL"
```
預期：PASS，3 個測試全數通過。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-18): Issue 15 Task 1 LibraryScreen 新增「強制 FXL」按鈕"
```

---

### Task 2：「恢復自動判斷」按鈕與方法

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `LibraryRepository.detectAndCacheEpubLayout(bookId, filePath)`、`Book.format`。
- Produces: `_restoreAutoLayoutForSelectedBooks()` 方法；`_buildSelectionAppBar()` 新增 `Key('library_restore_auto_layout_button')`。

- [x] **Step 1: 撰寫會失敗的測試**

**前置說明**：以下測試斷言用到的 `repository.detectAndCacheEpubLayoutCalls` 是 `FakeLibraryRepository`（`app/test/support/fake_library_repository.dart:31,133`）既有的既存 fixture（供 epic-17 既有測試使用），本 Task **不需要**額外擴充 `FakeLibraryRepository`，直接沿用即可。

在 `app/test/screens/library_screen_test.dart` 新增（緊接 Task 1 新增的 3 個測試之後）：

```dart
  testWidgets(
      '選取多本 EPUB 書籍後點擊「恢復自動判斷」，對每本已選取書籍呼叫 detectAndCacheEpubLayout',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A漫畫', isFixedLayout: true);
    final bookB = _testBook(id: '2', title: 'B漫畫', isFixedLayout: true);
    final repository = FakeLibraryRepository(
      initialBooks: [bookA, bookB],
      detectedIsFixedLayout: false,
    );

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

    await tester.tap(find.byKey(const Key('library_restore_auto_layout_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(
      repository.detectAndCacheEpubLayoutCalls,
      containsAll(['1', '2']),
    );
    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isFalse);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isFalse);
  });

  testWidgets(
      '選取集合混雜 EPUB 與 TXT 時，點擊「恢復自動判斷」只影響 EPUB、TXT 不受影響也不拋錯',
      (tester) async {
    final epubBook = _testBook(id: '1', title: 'A漫畫', isFixedLayout: true);
    final txtBook = _testBook(
      id: '2',
      title: 'B文字書',
      format: BookFileFormat.txt,
      filePath: 'content://example/2.txt',
    );
    final repository = FakeLibraryRepository(
      initialBooks: [epubBook, txtBook],
      detectedIsFixedLayout: false,
    );

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

    await tester.tap(find.byKey(const Key('library_restore_auto_layout_button')));
    await tester.pumpAndSettle();

    expect(repository.detectAndCacheEpubLayoutCalls, ['1']);
  });

  testWidgets('選取集合全為非 EPUB 時，「恢復自動判斷」按鈕仍然顯示（不隱藏/不因格式停用）',
      (tester) async {
    final txtBook = _testBook(
      id: '1',
      title: 'A文字書',
      format: BookFileFormat.txt,
      filePath: 'content://example/1.txt',
    );
    final repository = FakeLibraryRepository(initialBooks: [txtBook]);

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

    final button = tester.widget<IconButton>(
      find.byKey(const Key('library_restore_auto_layout_button')),
    );
    expect(button.onPressed, isNotNull);
  });
```

- [x] **Step 2: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "恢復自動判斷"
```
預期：FAIL——`Key('library_restore_auto_layout_button')` 找不到。

- [x] **Step 3: 實作**

修改 `app/lib/screens/library_screen.dart`：

1. 在 `_forceFixedLayoutForSelectedBooks()`（Task 1 新增）之後新增：
```dart
  /// 對選取集合中所有 EPUB 書籍重新呼叫既有 detectAndCacheEpubLayout()，
  /// 回到系統原始的「引擎分派判斷」結果——用於復原誤按/誤判後想撤銷人工
  /// 覆蓋的情況（見 CONTEXT.md「人工版面覆蓋」）。非 EPUB 書籍自動跳過。
  /// 行為比照 _forceFixedLayoutForSelectedBooks()，含其「捕捉 selectedIds
  /// 參考早於 _exitSelectionMode() 是安全的」註記。
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.detectAndCacheEpubLayout(book.id, book.filePath);
    }
    await _loadBooks();
  }
```

2. `_buildSelectionAppBar()` 的 `actions` 列表，在 `library_force_fxl_button` 之後、`library_delete_books_button` 之前新增：
```dart
        IconButton(
          key: const Key('library_restore_auto_layout_button'),
          icon: const Icon(Icons.restore),
          tooltip: '恢復自動判斷',
          onPressed: count == 0 ? null : _restoreAutoLayoutForSelectedBooks,
        ),
```

- [x] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/library_screen_test.dart --plain-name "恢復自動判斷"
```
預期：PASS，3 個測試全數通過。

- [x] **Step 5: 全專案回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（含 Task 1 新增的 3 個測試與本 Task 新增的 3 個測試，無回歸）。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-18): Issue 15 Task 2 LibraryScreen 新增「恢復自動判斷」按鈕"
```

---

### Task 3：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1-2 完成後的完整實作。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 15 狀態更新引用）。

- [x] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 驗證「強制 FXL」實際切換引擎**

1. 匯入一本已知被誤判為流式的漫畫 EPUB（若無現成素材，任一 EPUB 皆可用於驗證「引擎確實切換」這個機制本身，不要求驗證漫畫排版效果）。
2. 開啟該書，確認目前走 `FoliateEpubReaderView`（流式）路徑（例如觀察是否出現流式專屬的浮動按鈕組）。
3. 回到書架，長按進入多選模式選取該書，點擊「強制 FXL」。
4. 重新開啟該書，確認改走 `EpubReaderView`（Readium／FXL）路徑（例如觀察是否出現 FXL 專屬的浮動控制項/雙頁行為）。
5. 記錄：Pass/Fail + 截圖佐證。

- [ ] **Step 3: 驗證「恢復自動判斷」還原**

1. 承上，選取同一本書，點擊「恢復自動判斷」。
2. 重新開啟該書，**觀察開書後呈現的 UI 是否恢復為流式 EPUB 專屬的浮動按鈕組與排版行為**（真機黑箱測試無法直接讀取 `Book.isFixedLayout` 記憶體值，故以可觀察的 UI 特徵間接驗證已恢復系統原始判斷，若原始判斷本來就是流式）。
3. 記錄：Pass/Fail。

- [ ] **Step 4: 驗證混合選取情境**

1. 多選模式下同時選取 1 本 EPUB 與 1 本 PDF/TXT。
2. 點擊「強制 FXL」／「恢復自動判斷」，確認兩顆按鈕皆可點擊、僅 EPUB 書籍受影響，PDF/TXT 開啟時行為不受影響（不因本次操作出錯或改變）。
3. 記錄：Pass/Fail。

- [ ] **Step 5: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15 狀態更新引用。

---

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 15 根因重新診斷與人工版面覆蓋功能」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15
- `CONTEXT.md`「固定版面（FXL）」「引擎分派判斷」「人工版面覆蓋」詞彙定義
- `app/lib/library/models/book.dart:41-50,123`（`Book.isFixedLayout`／`copyWith()`）
- `app/lib/library/library_repository.dart:21-26`（`detectAndCacheEpubLayout()` 介面定義）
- `app/lib/screens/reader_screen.dart:282-309`（`_resolveEpubEngineDispatch()`，本 Issue 不需修改，僅供理解生效時機）
