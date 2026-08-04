# Epic 8 — 雲端同步 Issue 10：`LibraryScreen._openGroupFilteredView()` 未貫穿同步相關欄位 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `LibraryScreen._openGroupFilteredView()`（依分類篩選後再次推入 `LibraryScreen` 的既有遞迴路徑）建構下一層 `LibraryScreen` 時，補上目前遺漏的 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger` 三個同步相關欄位，讓使用者從「書架 → 點分類拼貼格 → 開書」這條路徑閱讀時，`syncCheckpointTrigger` 能正確一路貫穿到 `ReaderScreen`（離開閱讀畫面／閱讀中 5 分鐘計時器兩種 checkpoint 觸發來源才會生效）。

**Architecture：** 單一、純粹的追加式修正——`_openGroupFilteredView()` 建構下一層 `LibraryScreen` 的參數列，比照該方法目前已經正確貫穿的其餘既有欄位（`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`currentTheme` 等）的既定寫法，追加三行 `widget.<field>: widget.<field>,`。不涉及任何新型別、新類別或架構決策。

**Tech Stack：** Flutter／Dart，既有 `SyncAccountRepository`／`SyncClient`／`SyncCheckpointTrigger`（epic-8-sync Issue 2／6，皆已合併至 `main`）。

## Global Constraints

- 所有新增/修改的程式碼註解、文件、commit message 一律使用正體中文（專案 `CLAUDE.md` 規定）。
- Task 完成後 `flutter analyze`（於 `app/` 目錄下執行）必須維持乾淨（"No issues found!"）。
- **只修正 `_openGroupFilteredView()` 這一個遞迴建構點**，不擴大範圍修改其餘既有欄位或其他呼叫 `LibraryScreen(...)` 的地方（例如 `main.dart` 的頂層建構、`_openBook()` 建構的是 `ReaderScreen` 不是 `LibraryScreen`，皆與本 Issue 無關）——比照本專案「Surgical Changes」原則。
- 一次處理全部三個欄位（`syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`），不要只修其中一兩個——issues.md Issue 10「建議做法」明確要求一次處理，避免這個既有缺口下次又漏掉其中一個欄位再開一次追蹤工單。

---

### Task 1：`_openGroupFilteredView()` 貫穿三個同步相關欄位

**Files：**
- Modify: `app/lib/screens/library_screen.dart:470-489`（`_openGroupFilteredView()` 方法內建構 `LibraryScreen(...)` 的參數列）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：無（`LibraryScreen` 既有建構子欄位 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger` 皆已存在，本 Task 純粹補上遺漏的傳遞，不新增任何介面）。
- Produces：無新增公開介面。

現況：`app/lib/screens/library_screen.dart` 第 470-489 行，`_openGroupFilteredView(String groupName)` 呼叫 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => LibraryScreen(...)))` 時，參數列（第 475-486 行）已正確貫穿 `repository`／`importService`／`prefsManager`／`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`／`groupFilter` 共 12 個欄位，唯獨遺漏 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger` 三個欄位。

- [ ] **Step 1：在 `library_screen_test.dart` 寫一個會失敗的測試**

在 `app/test/screens/library_screen_test.dart` 檔案最後一個 `testWidgets(...)` 區塊（「LibraryScreen 點開一本書後，ReaderScreen 收到的 syncCheckpointTrigger 正確貫穿」，第 2567-2600 行）結束的 `});` 之後、`main()` 收尾的 `}`（第 2601 行）之前插入：

```dart

  testWidgets(
      'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，'
      'ReaderScreen 收到的 syncCheckpointTrigger 與外層一致'
      '（epic-8-sync Issue 10）', (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      groupName: '奇幻',
      filePath: 'content://example/1.txt',
    );
    final syncAccountRepository = SyncAccountRepository();
    final syncClient = SyncClient(accountRepository: syncAccountRepository);
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncAccountRepository: syncAccountRepository,
          syncClient: syncClient,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    final filteredScreen = tester.widget<LibraryScreen>(filteredScreenFinder);
    expect(filteredScreen.syncAccountRepository, same(syncAccountRepository),
        reason: '_openGroupFilteredView() 未把 syncAccountRepository 貫穿給下一層 '
            'LibraryScreen');
    expect(filteredScreen.syncClient, same(syncClient),
        reason: '_openGroupFilteredView() 未把 syncClient 貫穿給下一層 LibraryScreen');
    expect(filteredScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '_openGroupFilteredView() 未把 syncCheckpointTrigger 貫穿給下一層 '
            'LibraryScreen');

    await tester.tap(find.descendant(
      of: filteredScreenFinder,
      matching: find.byKey(const Key('book_item_1')),
    ));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '透過分類篩選路徑開書，ReaderScreen 收到的 syncCheckpointTrigger 應與'
            '外層一致，離開閱讀畫面／閱讀中 5 分鐘計時器兩種來源才會正確觸發 '
            'checkpoint');
  });
```

在檔案頂部 import 區塊（第 36 行 `import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';` 之後）新增：

```dart
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
```

- [ ] **Step 2：執行測試，確認目前會失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "Issue 10"`

Expected: FAIL——`filteredScreen.syncAccountRepository`／`.syncClient`／`.syncCheckpointTrigger`皆為 `null`（`_openGroupFilteredView()` 目前沒有傳遞這三個欄位），三個 `expect(..., same(...))` 斷言中至少第一個會先失敗。

- [ ] **Step 3：實作**

修改 `app/lib/screens/library_screen.dart` 第 470-489 行，原本：

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
              customFontsRepository: widget.customFontsRepository,
              currentTheme: widget.currentTheme,
              isEinkMode: widget.isEinkMode,
              onThemeChanged: widget.onThemeChanged,
              onEinkModeChanged: widget.onEinkModeChanged,
              groupFilter: groupName,
            ),
          ),
        )
```

改為：

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
              customFontsRepository: widget.customFontsRepository,
              // epic-8-sync Issue 10：先前遺漏這三個同步相關欄位，導致從這條
              // 分類篩選路徑開書時 syncCheckpointTrigger 無法貫穿到
              // ReaderScreen，「離開畫面」／「閱讀中 5 分鐘計時器」兩種
              // checkpoint 觸發來源會靜默失效（見 plans/plan-issue-10.md）。
              syncAccountRepository: widget.syncAccountRepository,
              syncClient: widget.syncClient,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
              currentTheme: widget.currentTheme,
              isEinkMode: widget.isEinkMode,
              onThemeChanged: widget.onThemeChanged,
              onEinkModeChanged: widget.onEinkModeChanged,
              groupFilter: groupName,
            ),
          ),
        )
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "Issue 10"`

Expected: PASS。

- [ ] **Step 5：執行整份 `library_screen_test.dart`，確認無回歸**

Run: `cd app && flutter test test/screens/library_screen_test.dart`

Expected: 全數 PASS。

- [ ] **Step 6：執行 `flutter test`（全專案），確認無回歸**

Run: `cd app && flutter test`

Expected: 全數 PASS。

- [ ] **Step 7：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "fix(epic-8-sync): Issue 10 — _openGroupFilteredView() 貫穿 syncAccountRepository/syncClient/syncCheckpointTrigger"
```

---

## 與 issues.md 的落差說明

無——本計畫完全依照 issues.md Issue 10 的「建議做法」與驗收標準執行，一次處理全部三個欄位，測試設計直接對應驗收標準第二點「新增測試驗證『透過分類篩選路徑開書後，ReaderScreen 收到的 syncCheckpointTrigger 與外層一致』」，並額外在 `LibraryScreen` 層級直接驗證 `syncAccountRepository`／`syncClient` 兩個欄位的貫穿（驗收標準第一點），沒有偏離。
