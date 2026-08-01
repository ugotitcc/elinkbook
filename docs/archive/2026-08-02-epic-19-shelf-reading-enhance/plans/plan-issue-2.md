# Epic 19 Issue 2 — 刪除書籍 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `LibraryScreen` 的選取模式 AppBar 新增「刪除」按鈕，讓使用者可以批次刪除已選取的書籍（含確認對話框、對應的本機複本檔案清理），補上目前完全無 UI 可觸達的 `LibraryRepository.deleteBook()`。

**Architecture:** 純 UI 層工單，不新增/不修改 `LibraryRepository` 介面——`deleteBook(String id)` 已存在（`library_repository.dart:10`，實作於 `sqlite_library_repository.dart:459`，內部已處理連動的書籤/劃線/備註刪除）。`library_screen.dart` 新增 `_confirmDeleteBooks(int count)`（`showDialog` 確認對話框，比照既有 `_confirmAutoGroupByFolderName()`）與 `_deleteSelectedBooks()`（比照既有 `_moveSelectedBooksToGroup()`：確認→立即退出選取模式→逐筆呼叫 `deleteBook()`→用 `existsSync()` 防護清理 `filePath`/`coverPath` 對應的本機檔案→`_loadBooks()` 重新整理列表）。分兩個 Task 拆解：Task 1 先做「刪除書籍本身」（不含檔案清理），Task 2 再疊加「檔案清理」邏輯，兩者各自有獨立可驗證的紅-綠循環。

**Tech Stack:** Flutter/Dart（`library_screen.dart`）、`dart:io`（`File.existsSync()`/`File.deleteSync()`）、既有 `LibraryRepository`/`FakeLibraryRepository` 測試替身。

## Global Constraints

- **語言**：所有程式碼註解、commit 訊息、計畫文件皆用正體中文（`CLAUDE.md`）。
- **不修改 `LibraryRepository` 介面**——`deleteBook(String id)` 已存在且已包含連動刪除，本工單純粹是 UI 層接線（`spec.md`「功能 ② 刪除書籍」）。
- **`filePath` 不一定是本機複本**——只有持久化 URI 權限授權失敗、或原始 URI 無可辨識副檔名時才會落地成本機複本（`book_import_service_impl.dart:190-194`），其餘情況維持原始 `content://` URI；`coverPath` 則永遠是本機複本。`existsSync()` 防護對兩種來源都安全（`content://` 字串用 `dart:io File` 判斷永遠不存在，會被安全跳過），實作時不需要分辨檔案來源。
- **`_deleteSelectedBooks()` 一律先呼叫 `_exitSelectionMode()` 再進入刪除迴圈**，比照既有 `_moveSelectedBooksToGroup()` 慣例，避免刪除迴圈執行期間使用者重複點擊觸發本方法。
- **參考文件**：`docs/epics/epic-19-shelf-reading-enhance/design.md`；`docs/epics/epic-19-shelf-reading-enhance/spec.md`「功能 ② 刪除書籍」；`docs/epics/epic-19-shelf-reading-enhance/issues.md`「Issue 2」。

---

### Task 1: 刪除確認對話框與 `_deleteSelectedBooks()`（不含檔案清理）＋ AppBar 按鈕

**Files:**
- Modify: `app/test/support/fake_library_repository.dart`（新增 `deleteBookCalls` 呼叫紀錄，供測試驗證）
- Modify: `app/test/screens/library_screen_test.dart`（新增 widget test）
- Modify: `app/lib/screens/library_screen.dart`（`_buildSelectionAppBar()`：`library_screen.dart:498-518`；緊鄰 `_moveSelectedBooksToGroup()`：`library_screen.dart:262-280`，新增 `_confirmDeleteBooks`/`_deleteSelectedBooks`）

**Interfaces:**
- Consumes: `LibraryRepository.deleteBook(String id)`（既有介面，`library_repository.dart:10`）；`_selectedBookIds`／`_exitSelectionMode()`／`_loadBooks()`（既有 `_LibraryScreenState` 成員）。
- Produces: `_confirmDeleteBooks(int count) -> Future<bool?>`、`_deleteSelectedBooks() -> Future<void>`，`Key('library_delete_books_button')`、`Key('library_delete_confirm_button')`——Task 2 會修改 `_deleteSelectedBooks()` 迴圈內部（疊加檔案清理），不改變這兩個方法簽章。

- [ ] **Step 1: 在測試替身 `FakeLibraryRepository` 新增 `deleteBook()` 呼叫紀錄**

修改 `app/test/support/fake_library_repository.dart`，在既有 `deleteBook()` 實作（第 48-51 行）前新增紀錄欄位，並在方法內記錄呼叫：

```dart
  /// 記錄每次 [deleteBook] 呼叫的 id，供測試驗證「每個已選取 id 各被呼叫
  /// 一次」（epic-19 Issue 2，比照既有 detectAndCacheEpubLayoutCalls 的
  /// 呼叫紀錄慣例）。
  final List<String> deleteBookCalls = [];

  @override
  Future<void> deleteBook(String id) async {
    deleteBookCalls.add(id);
    _books.removeWhere((b) => b.id == id);
  }
```

- [ ] **Step 2: 撰寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 內，緊接既有「書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動」測試（第 915-966 行左右）之後，新增：

```dart
  testWidgets('選取模式下 AppBar 顯示刪除按鈕，取消刪除確認對話框不會呼叫 deleteBook',
      (tester) async {
    final book = _testBook(id: '1', title: '測試書');
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

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_delete_books_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();

    expect(find.text('刪除書籍'), findsOneWidget);
    expect(
      find.text('將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, isEmpty);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('選取多本書後點擊刪除並確認，每個已選取 id 各被呼叫一次 deleteBook，書籍從列表消失',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書');
    final bookB = _testBook(id: '2', title: 'B書');
    final bookC = _testBook(id: '3', title: 'C書');
    final repository =
        FakeLibraryRepository(initialBooks: [bookA, bookB, bookC]);

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

    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('將刪除已選取的 2 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, unorderedEquals(['1', '2']));
    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsNothing);
    expect(find.byKey(const Key('book_item_3')), findsOneWidget);
  });
```

- [x] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart -n "選取模式下 AppBar 顯示刪除按鈕|選取多本書後點擊刪除並確認"`
Expected: FAIL——`find.byKey(const Key('library_delete_books_button'))` 找不到任何 widget（`library_screen.dart` 尚未新增此按鈕）。

- [x] **Step 4: 實作 `_confirmDeleteBooks`／`_deleteSelectedBooks`／AppBar 按鈕**

在 `app/lib/screens/library_screen.dart` 中，緊接既有 `_moveSelectedBooksToGroup()` 方法（第 262-280 行）之後新增：

```dart
  Future<bool?> _confirmDeleteBooks(int count) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除書籍'),
        content: Text(
          '將刪除已選取的 $count 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_delete_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（見
    // library_screen.dart:322，同檔案內多數 await-dialog 後的路徑皆有此
    // 檢查，_moveSelectedBooksToGroup() 缺這道檢查屬既有缺口，不在本工單
    // 範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
    }
    await _loadBooks();
  }
```

接著修改 `_buildSelectionAppBar()`（第 498-518 行），在既有「移動到分類」`IconButton` 之後新增第二個按鈕：

```dart
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
        IconButton(
          key: const Key('library_delete_books_button'),
          icon: const Icon(Icons.delete),
          tooltip: '刪除',
          onPressed: count == 0 ? null : _deleteSelectedBooks,
        ),
      ],
    );
  }
```

- [x] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部測試通過，含既有測試無回歸）。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart app/test/support/fake_library_repository.dart
git commit -m "feat(epic-19): Issue 2 Task 1 新增刪除書籍確認對話框與 AppBar 按鈕"
```

---

### Task 2: 檔案清理邏輯（`existsSync()` 防護）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_deleteSelectedBooks()`，Task 1 新增的方法，疊加檔案清理邏輯）
- Modify: `app/test/screens/library_screen_test.dart`（`_testBook` 輔助函式新增 `coverPath` 參數；新增檔案清理相關 widget test）

**Interfaces:**
- Consumes: Task 1 產出的 `_deleteSelectedBooks()`（本 Task 只修改其迴圈內部，不改變外部行為契約：確認→退出選取模式→逐筆刪除→`_loadBooks()`）。
- Produces: 無新的對外符號——`_deleteSelectedBooks()` 迴圈內對 `book.filePath`／`book.coverPath` 各自用 `File(path).existsSync()` 判斷後才刪除。

- [x] **Step 1: 為 `_testBook` 測試輔助函式新增 `coverPath` 參數，並新增 `dart:convert` import**

`_BookCover` 會用 `Image.file()` 解碼 `coverPath` 指向的檔案（`library_screen.dart:664-679`）；本 Task 的測試需要一個「真實存在、且能被成功解碼」的封面檔案，才不會在 `pumpAndSettle()` 階段因為 `Image.file` 解碼失敗而讓 `FlutterError` 被回報、拖垮測試。故準備一個最小合法 PNG 的 base64 常數，寫入真實暫存檔。

在 `app/test/screens/library_screen_test.dart` 檔案頂部新增 import（緊接既有 `import 'dart:async';`）：

```dart
import 'dart:convert';
```

修改檔案末尾的 `_testBook`（第 1394-1415 行）：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  String? coverPath,
  bool? isFixedLayout,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
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

- [x] **Step 2: 撰寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 內，緊接 Task 1 新增的兩個刪除測試之後，新增：

```dart
  testWidgets('確認刪除後，書籍檔案與封面檔案（本機複本）從裝置上被刪除', (tester) async {
    // 【根因說明，比照既有 Markdown 匯出測試先例】真實 Directory.createTemp／
    // File I/O 需要真正的作業系統事件迴圈，AutomatedTestWidgetsFlutterBinding
    // 的 fake Zone 無法完成，須用 tester.runAsync() 包住真實 I/O。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_screen_delete_book_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final bookFile = File('${tempDir.path}/book.epub');
    final coverFile = File('${tempDir.path}/cover.png');
    await tester.runAsync(() async {
      await bookFile.writeAsBytes([0]);
      // 最小合法 1x1 PNG（可被 Image.file 成功解碼），避免 _BookCover 在
      // pumpAndSettle() 階段因無效圖片內容觸發 FlutterError.reportError
      // 而讓測試失敗（bookFile 的內容不受此限——filePath 從未被當成圖片
      // 解碼，只有 coverPath 會經過 Image.file）。
      await coverFile.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
        '42YAAAAASUVORK5CYII=',
      ));
    });

    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: bookFile.path,
      coverPath: coverFile.path,
    );
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

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();

    // 確認刪除的 tap 在框架 zone 內執行，讓 Navigator.pop 觸發的 microtask
    // 正常 flush。_deleteSelectedBooks 使用 deleteSync()（同步系統呼叫），不
    // 需 runAsync 即可在 fake zone 內完成（見下方 Step 4 的實作變更說明）。
    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, ['1']);
    expect(bookFile.existsSync(), isFalse);
    expect(coverFile.existsSync(), isFalse);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
  });

  testWidgets('書籍 filePath 為外部 content:// 參照時，刪除書籍不會嘗試刪除原始檔案也不拋例外',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: 'content://com.android.externalstorage.documents/document/1234',
    );
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

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, ['1']);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
  });
```

- [x] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart -n "確認刪除後，書籍檔案與封面檔案"`
Expected: FAIL——`bookFile.existsSync()` 仍為 `true`（`_deleteSelectedBooks()` 目前只呼叫 `deleteBook()`，尚未刪除本機檔案），`expect(bookFile.existsSync(), isFalse)` 斷言失敗。

（`書籍 filePath 為外部 content:// 參照時...` 這個測試在此步驟已會通過——Task 1 的實作本來就不會去碰檔案系統，不需要特別驗證它「失敗」，本步驟只需確認前一個測試如預期失敗即可。）

- [x] **Step 4: 實作檔案清理邏輯**

修改 `app/lib/screens/library_screen.dart` 內 `_deleteSelectedBooks()`（Task 1 新增）的迴圈本體：

```dart
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
      // existsSync() 防護對 content:// 來源的 filePath 安全（design.md
      // 調查結論——content:// 字串永遠不會判定為存在的本機路徑，故此處
      // 不需要分辨 filePath 是本機複本還是原始外部檔案參照）。比照既有
      // _pickAndImportFiles()/_pickAndImportFolder() 的既有慣例，用
      // try-catch 包住檔案系統操作：單一檔案刪除失敗（例如被其他程序鎖
      // 定、權限異常）不應中斷整個批次刪除迴圈——deleteBook()（資料庫紀
      // 錄，使用者最關心的「書從書架消失」）已在上一行完成，迴圈仍要繼
      // 續處理其餘已選取的書籍並跑到最後的 _loadBooks()。
      try {
        // 使用 deleteSync()（同步系統呼叫）而非 await delete()：widget test
        // 的 fake zone 無法完成真實 I/O 的 Future，deleteSync() 不受此限制。
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    }
```

此 `try-catch` 屬防禦性寫法（對應 code review Minor 建議 2），涵蓋的是「檔案被鎖定/權限異常」這類難以在 widget test 環境下跨平台穩定重現的情境（`File.existsSync()` 對目錄一律回傳 `false`，無法用「拿目錄路徑冒充檔案路徑」這種手法可靠觸發 `FileSystemException`），不額外新增對應的自動化測試——比照 `_pickAndImportFiles()` 的既有 try-catch 同樣沒有針對「真實檔案系統失敗」的專屬測試（`FakeLibraryRepository(throwOnListBooks: true)` 測的是 repository 層的模擬失敗，不是 `dart:io` 真實檔案系統例外）。Step 2 既有的兩個測試（真實檔案存在且被刪除／`content://` 安全跳過）已涵蓋這段程式碼的正常路徑，不受這裡新增的 `try-catch` 影響。

**【決策紀錄——`delete()` → `deleteSync()`，實作完成後 `/superpowers:requesting-code-review` 審查發現並經作者確認保留】**上方程式碼與本計畫原始草稿（撰寫時）相比，把 `await File(path).delete()` 改成了 `File(path).deleteSync()`。原因：`AutomatedTestWidgetsFlutterBinding` 的 fake zone 無法讓真實 `dart:io` 非同步 `Future` 完成，若維持 `await delete()`，Step 2 的兩個測試都必須用 `tester.runAsync()` 包住確認刪除的 tap 動作、並搭配輪詢等待逾時；`deleteSync()` 是同步系統呼叫（底層即 `unlink`，屬中繼資料操作，不受檔案大小影響，效能風險低），可直接在 fake zone 內完成，測試因此不需要額外的 `runAsync`/輪詢（見上方 Step 2 已同步更新的測試程式碼，及 Step 3 對應調整過的失敗描述）。這項偏離已於 `tmp/epic-19/plan-issue-2-code-review.md`（Important 項目）記錄，作者確認保留 `deleteSync()`，並回頭同步更新了 `spec.md`「功能 ② 刪除書籍」介面章節與本檔案。

- [x] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部測試通過，含既有測試無回歸）。

- [x] **Step 6: 執行全專案測試與靜態分析確認無回歸**

Run: `cd app && flutter test`
Expected: PASS。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-19): Issue 2 Task 2 刪除書籍時清理本機複本檔案"
```

---

### Task 3: 真機驗收

**Files:** 無程式碼異動，僅驗收記錄。

- [ ] **Step 1: 建置並安裝 debug APK**

Run: `cd app && flutter clean && flutter build apk --debug`

安裝到既有測試裝置。

- [ ] **Step 2: 驗收單本刪除**

書架畫面長按 1 本書進入選取模式，點擊刪除按鈕，確認對話框正確顯示「將刪除已選取的 1 本書籍...」文案；點擊「刪除」後該書從書架消失，若該書先前有加註書籤/劃線/備註，重新開啟其他書籍後確認這些註記已一併清除（透過 `deleteBook()` 既有的連動刪除，見 `sqlite_library_repository.dart:459`）；若 `filePath`/`coverPath` 為本機複本，確認裝置上對應檔案已被刪除（可用檔案總管或 `adb shell` 檢查 App 私有目錄）。

- [ ] **Step 3: 驗收多本刪除**

長按進入選取模式後再勾選第 2、3 本書，確認對話框文案正確顯示選取本數；確認後所有已選取書籍皆從書架消失，未選取的書籍不受影響。

- [ ] **Step 4: 驗收取消刪除**

進入選取模式並點擊刪除按鈕開啟確認對話框後，點擊「取消」，確認沒有任何書籍被刪除、選取模式維持原狀（未自動退出）。

- [ ] **Step 5: 回歸確認既有功能**

確認「移動到分類」批次操作、長按進入/退出選取模式、格狀/列表檢視切換等既有功能皆不受本次變動影響。

- [ ] **Step 6: 更新 `issues.md`**

將 `docs/epics/epic-19-shelf-reading-enhance/issues.md` Issue 2 的 `Status:` 改為 `✅ 已完成`，並記錄上述真機驗收結果。
