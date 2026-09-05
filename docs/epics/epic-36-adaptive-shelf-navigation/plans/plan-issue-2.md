# Epic 36 Issue 2：書架原地下鑽重構＋管理分類入口搬遷 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `LibraryScreen._openGroupFilteredView()` 從「`Navigator.push` 推入一個全新獨立 `LibraryScreen` 實例模擬下鑽」改為「`setState` 切換內部狀態 `_activeGroupFilter` 的原地下鑽」，並把系統返回鍵（`PopScope`）的多選/下鑽兩種攔截邏輯合併成單一狀態機；「管理分類」選單項目維持掛在 Issue 1 已建立的 `library_sort_view_button` 選單裡，只是顯示條件從 `widget.groupFilter == null` 改讀 `_activeGroupFilter == null`。

**Architecture：** 三目的地導覽下 `LibraryScreen` 全程只會被 `AdaptiveShellScaffold` 建構一次（Issue 1 已交付），不再存在「篩選畫面是另一個獨立 `LibraryScreen` 實例」這回事——`LibraryScreen.groupFilter` 建構參數本身失去存在意義，予以移除。`_LibraryScreenState` 新增可變狀態 `String? _activeGroupFilter`，`_buildBookList()` 的分類拼貼格顯示/書籍清單過濾邏輯改讀這個狀態；由於 `LibraryBookListController` 不再以 `groupFilter` 對 `repository.listBooks()` 做伺服器端篩選（該欄位僅在建構時決定、之後不變，與現在「同一個 controller 實例、下鑽狀態隨時可變」的需求不相容），`_buildBookList()` 改為對 controller 已載入的**全部書籍**在畫面端依 `_activeGroupFilter` 做用戶端過濾（本計劃「計劃範圍澄清」第 2 點有詳細說明，這是本計劃在規劃階段發現、`spec.md` 字面指示未覆蓋到的必要修正，不是新增範圍）。系統返回鍵合併邏輯修改（非新增）Issue 1 沿用下來的最外層 `PopScope`。本 Issue 只改動 `app/lib/screens/library_screen.dart` 與其測試檔，不新增檔案。

**Tech Stack：** Flutter 3.41.9、既有 `flutter_test` widget test 慣例（`pumpWidget(MaterialApp(home: X(...)))` + `Key` 斷言）；系統返回鍵一律用 `tester.binding.handlePopRoute()` 模擬（比照 `app/test/screens/adaptive_shell_scaffold_test.dart:114` 已驗證可用的既有寫法，**不是**計劃撰寫前一版曾誤用的 `tester.pageBack()`——`pageBack()` 只會尋找 tooltip 為 `'Back'` 或 `CupertinoNavigationBarBackButton` 的按鈕並直接點擊它，選取模式的 AppBar `leading` 是 `Icons.close`〔`library_selection_cancel_button`〕不是返回按鈕，`pageBack()` 在多選情境下會直接找不到目標而拋出斷言錯誤，並非真正的系統返回鍵模擬）。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/spec.md` §功能②、`docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 2

## Global Constraints

- 本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目（`UI_DESIGN_RULES.md`）。
- 本 Issue **不**處理 `_currentPage`／分頁重置——那是 Issue 3（`PagingBar`）才會新增的欄位，目前程式碼裡不存在。`spec.md` §功能②程式碼範例裡出現的 `_currentPage = 0;` 一行**本計劃刻意不落地**，見下方「計劃範圍澄清」第 3 點。
- `onPopInvokedWithResult` 是目前 Flutter SDK 正確的回呼名稱（不是 `onPopInvokedWithDidPop`，該名稱不存在），比照 Issue 1 已使用的既有寫法。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔（`flutter test test/screens/library_screen_test.dart`），全套 `flutter test`（不帶路徑）留到最後一個 Task 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。

## 計劃範圍澄清（撰寫本計劃時發現並解決的 issues.md／spec.md 內部落差）

1. **`_filteredLibraryScreenFinder` 呼叫點目前實際為 10 處，不是 `issues.md`／`review-issues.md` I-2 記載的 11 處**：`issues.md` 撰寫當下引用的行號是 Issue 1 開發、測試遷移（`library_import_button` 等 12＋處刪除、`library_eink_toggle` 2 處刪除等）**之前**的舊行號快照；Issue 1 合併後檔案已經歷大量既有測試刪除，目前用 `grep -n "_filteredLibraryScreenFinder("` 實測只有 10 個呼叫點（587、796、1042、1336、1379、1446、2705、2776、2842、2908 行）＋ 1 處定義（3738 行）。本計劃以**實測結果**為準逐一列出，不沿用 `issues.md` 的舊行號清單。
2. **關鍵修正：`_buildBookList()` 不能只是把 `widget.groupFilter` 逐字換成 `_activeGroupFilter`**——`spec.md` §功能②原文只寫「`_buildBookList()` 內所有 `widget.groupFilter` 改讀 `_activeGroupFilter`」，但現行 `visibleBooks` 邏輯（`library_screen.dart:752-754`）：
   ```dart
   final visibleBooks = widget.groupFilter == null
       ? books.where((b) => b.groupName == BookGroup.uncategorized).toList()
       : books; // ← 非 null 分支直接假設 books 已經是「只含該分類」的清單
   ```
   這個 `: books`（非 null 分支直接沿用 `books` 不做任何過濾）能成立，完全是因為現行架構下 `books` 來自 `LibraryBookListController(groupFilter: widget.groupFilter)`——**該 controller 實例本身已經對 `repository.listBooks(groupFilter: ...)` 做了伺服器端篩選**，`books` 從一開始就只含該分類的書籍。Issue 2 之後三目的地下 `LibraryScreen` 只建構一次、`_bookListController` 只在 `initState()` 建立一次，`_activeGroupFilter` 卻是使用者點擊分類拼貼格時才動態變動的執行期狀態——**不可能讓 `initState()` 建立時就決定的 controller 跟著之後變動的 `_activeGroupFilter` 動態改變它的伺服器端查詢條件**（`LibraryBookListController.groupFilter` 是 `final`，其文件明載「於建構時決定、之後不再變動」，見 `library_book_list_controller.dart:20-23`；這是既有、有獨立單元測試覆蓋的既定設計，本 Issue 不動它，也不應該為了這個目的改成可變）。因此 `_bookListController` 改為固定以 `groupFilter: null` 建構（見 Task 2，一律載入全部書籍），`_buildBookList()` 的 `visibleBooks` 在 `_activeGroupFilter != null` 分支必須**自行依 `groupFilter == _activeGroupFilter` 過濾**（用戶端過濾，比照既有「未分類」分支的既定手法），否則下鑽某分類時畫面會錯誤地顯示全部書籍而非只顯示該分類——這是若逐字套用 spec.md 字面指示會直接引入的一個回歸缺陷，本計劃 Task 1 已修正。
3. **`spec.md` §功能②程式碼範例的 `_currentPage = 0` 不在本 Issue 落地**：`_openGroupFilteredView`/`_exitGroupFilteredView` 的 spec 程式碼範例裡各自多了一行 `_currentPage = 0;`，但 `_currentPage` 欄位屬於 Issue 3（`PagingBar`）才會新增，目前程式碼裡完全不存在這個欄位。本計劃的 `_openGroupFilteredView`/`_exitGroupFilteredView` 只做 `_activeGroupFilter` 的切換，不引用任何 Issue 3 才存在的欄位；Issue 3 的計劃撰寫者屆時需要在這兩個方法裡各自補上一行 `_currentPage = 0;`。
4. **`_LibraryScreenState` 初始化 `_activeGroupFilter` 的方式跨 Task 1/2 有暫時性差異，屬刻意設計**：`spec.md` 原文一方面說「`initState()` 由 `widget.groupFilter` 初始化一次」，另一方面又說「`LibraryScreen.groupFilter` 建構參數移除」——兩句話字面上互斥（參數都移除了要如何從它初始化？）。本計劃拆解為兩步：Task 1 保留 `widget.groupFilter` 欄位本身（仍是既有建構參數）僅作為 `_activeGroupFilter` 的一次性初始值來源（`_activeGroupFilter = widget.groupFilter;`），讓 `L3031-3067`（見下方第 6 點，本計劃已決定於 Task 1 內刪除，不留到 Task 2）等舊測試在這段過渡期間仍可編譯；Task 2 才真正移除 `LibraryScreen.groupFilter` 欄位／建構參數本身，`_activeGroupFilter` 改為單純預設 `null`（不再讀 `widget.groupFilter`，該欄位已不存在）。**（`review-plan-issue-2.md` I-1 修正）**：既有測試遷移（改寫 6 處＋刪除 5 處＋輔助函式移除）已整段併入 Task 1（Task 1 Step 5），使 Task 1 收尾 Commit 時 `library_screen_test.dart` 達到 100% PASS，不會出現「已知 10 個測試失敗的狀態下 Commit」這種破壞 `git bisect`／CI 綠燈保證的中繼狀態；Task 2 因此收斂為單純的 `groupFilter` 欄位/建構參數移除（不再涉及任何既有測試遷移），Commit 時同樣保持全綠。
5. **「篩選中的分類已被刪除時重置為全部」安全網邏輯經查證為結構上不可能觸發，不需新增程式碼**：`spec.md` 原文提到「`_openManageGroupsDialog()` 內既有...安全網邏輯（若存在）保留」，但實際查證 `_openManageGroupsDialog()`（`library_screen.dart:469-480`）目前完全不含任何與 `groupFilter`/`_activeGroupFilter` 相關的邏輯，也**不存在**這種安全網。深入分析後確認不需要新增：「管理分類」選單項目（`library_manage_groups_option`）只在 `_activeGroupFilter == null` 時才顯示（Issue 1 已建立此條件，Issue 2 只是把判斷式的變數來源換掉），也就是使用者在下鑽某分類的畫面裡**結構上不可能**開啟「管理分類」對話框去刪除自己正在檢視的分類——這個情境在 UI 層級就被阻斷了，不存在「篩選中的分類被刪除」這種執行期狀態組合，故不需要任何額外的重置程式碼。
6. **`app/test/screens/library_screen_test.dart:3031-3067`（「透過分類篩選路徑進入不會自動開書」測試）予以刪除，不強行改寫**：這則測試原本的驗證方式是直接用 `groupFilter: '奇幻'` 建構一個「篩選畫面」實例，驗證它建構時不會觸發 `_maybeOpenLastBookOnLaunch()` 的自動開書。`groupFilter` 建構參數最終會被移除後，已經沒有任何公開 API 可以在建構當下就處於「已下鑽」狀態——`_activeGroupFilter` 只能透過使用者點擊分類拼貼格在 `initState()`／`_initialize()` 完成、畫面已渲染出拼貼格**之後**才變動，而 `_maybeOpenLastBookOnLaunch()` 是 `_initialize()` 內比拼貼格渲染更早執行的一次性檢查（見 `_initialize()` 呼叫順序：`_bookListController.initialLoad()` 完成後才呼叫 `_maybeOpenLastBookOnLaunch()`，此時使用者根本還沒有機會點擊任何分類拼貼格）。也就是說 `_maybeOpenLastBookOnLaunch()` 裡 `if (_activeGroupFilter != null) return;` 這個 guard 在真實執行時序下永遠不可能為真——保留這一行是比照 `spec.md` 明文指示維持語意對稱與未來防禦性（例如日後這個初始化順序被改動時仍有保護），但已經沒有任何透過目前公開 widget API 能夠真正命中這個分支的執行路徑，勉強寫一個依賴 pump 時序競態的測試只會是脆弱且會誤導後續維護者的假測試。本計劃選擇誠實刪除這則測試（見 Task 2），並在 production code 該行 guard 旁補一句簡短註解說明這個決策，而不是產出一個看似驗證了什麼、實際上驗證不了任何事的測試。

---

## Task 1：`_activeGroupFilter` 原地下鑽核心邏輯＋新增回歸測試＋既有測試遷移

**（`review-plan-issue-2.md` I-1 修正）**：原規劃將既有測試遷移獨立放在 Task 2，會讓 Task 1 收尾 Commit 時 `library_screen_test.dart` 帶著 10 個已知失敗——違反「每次 Commit 保持測試綠燈」原則，破壞 `git bisect` 可追溯性。本 Task 現在合併「新行為實作＋新回歸測試＋既有測試遷移（改寫 6 處／刪除 5 處／輔助函式移除）」，收尾時 Commit 前必須是全綠；Task 2 收斂為單純的 `groupFilter` 建構參數移除（不再涉及任何測試遷移）。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`（新增 5 則回歸測試＋改寫 6 處既有測試＋刪除 5 則既有測試＋移除 1 個輔助函式，見 Step 1 與 Step 5）

**Interfaces:**
- Consumes: 無新依賴，沿用既有 `_bookListController`／`_inSelectionMode`／`_exitSelectionMode()`。
- Produces：`_LibraryScreenState` 新增可變欄位 `String? _activeGroupFilter`；新增 `Key('library_back_from_group_button')`（AppBar `leading` 的返回按鈕）。`LibraryScreen.groupFilter` 建構參數本 Task **暫時保留**（見「計劃範圍澄清」第 4 點，Task 2 才移除）。

- [x] **Step 1: 寫失敗測試——5 則新回歸測試**

在 `app/test/screens/library_screen_test.dart` 第 2481 行（`長按進入選取模式後，分類拼貼格的 onTap 停用，點擊不觸發導覽也不影響選取狀態` 測試的 `});` 結束之後）插入：

```dart
  testWidgets('點擊分類拼貼格為原地狀態切換，不產生新的 Navigator 路由（C-2 核心回歸測試）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigatorState.canPop(), isFalse);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      navigatorState.canPop(),
      isFalse,
      reason: '原地下鑽不應該推入新的 Navigator 路由（舊行為必須明確斷言「不會再發生」）',
    );
    expect(
      find.byType(LibraryScreen),
      findsOneWidget,
      reason: '畫面樹上永遠只有一個 LibraryScreen 實例',
    );
  });

  testWidgets('下鑽分類後 AppBar leading 顯示返回按鈕、title 顯示分類名稱；點擊返回按鈕回到頂層書架', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);
    expect(find.text('書架'), findsOneWidget);
  });

  testWidgets('頂層書架多選模式下系統返回鍵先解除多選，不退出畫面（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_selection_app_bar')), findsNothing,
      reason: '系統返回鍵應優先解除多選模式，而非直接關閉畫面',
    );
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('下鑽分類內多選模式下系統返回鍵先解除多選，不誤切回頂層（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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
    expect(find.text('奇幻'), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_selection_app_bar')), findsNothing,
      reason: '應先解除多選模式',
    );
    expect(
      find.text('奇幻'), findsOneWidget,
      reason: '解除多選後應仍停留在下鑽的分類畫面，不應該同一次系統返回鍵就直接跳回頂層書架',
    );
    expect(find.byKey(const Key('library_back_from_group_button')), findsOneWidget);
  });

  testWidgets('下鑽分類（非多選模式）下系統返回鍵切回頂層書架（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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
    expect(find.text('奇幻'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 上述 5 則新測試 FAIL（`library_back_from_group_button` 不存在、`PopScope` 尚未合併邏輯、`_openGroupFilteredView` 仍是 `Navigator.push`）；其餘既有測試維持原本的 PASS（本 Step 尚未修改任何 production code）。

- [x] **Step 3: 實作 `_activeGroupFilter` 原地下鑽**

編輯 `app/lib/screens/library_screen.dart`：

**3a. `_LibraryScreenState` 新增欄位＋`initState()` 初始化**（緊接在既有 `Set<String> _redownloadingBookIds = {};` 欄位之後）：

```dart
  // 〔比照 epic-30 Issue 3 既定的重入防護模式〕...
  final Set<String> _redownloadingBookIds = {};

  /// 三目的地導覽下 LibraryScreen 只建構一次、恆為頂層模式（epic-36
  /// Issue 1），原本靠「另一個獨立 LibraryScreen 實例＋groupFilter 建構參數」
  /// 模擬下鑽的做法在 Issue 2 改為這個可變狀態的原地切換。**過渡期**：本
  /// 欄位目前仍由 widget.groupFilter 初始化一次（該建構參數即將於 Issue 2
  /// Task 2 移除，屆時這裡改為單純預設 null）。
  String? _activeGroupFilter;
```

`initState()` 開頭新增一行（在 `super.initState();` 之後、`_bookListController = ...` 之前）：

```dart
  @override
  void initState() {
    super.initState();
    _activeGroupFilter = widget.groupFilter;
    _bookListController = LibraryBookListController(
      repository: widget.repository,
      groupFilter: widget.groupFilter,
    )..addListener(_onBookListChanged);
```

（`_bookListController` 建構呼叫本身暫不修改——`widget.groupFilter` 這個過渡期仍存在的欄位對 Task 1 唯一還在使用它的舊測試〔`library_screen_test.dart:3031-3067`〕維持相容，Task 2 才會一併調整。）

**3b. `_maybeOpenLastBookOnLaunch()` 的 guard 改讀 `_activeGroupFilter`**：

```dart
  Future<void> _maybeOpenLastBookOnLaunch() async {
    // 【epic-36 Issue 2】保留此 guard 是比照 spec.md 明文指示維持語意對稱與
    // 未來防禦性——目前透過公開 widget API 已經沒有任何執行路徑能讓
    // _activeGroupFilter 在這裡被呼叫到的當下已經非 null（它只能在畫面渲染
    // 完成、使用者點擊分類拼貼格後才變動，晚於這個方法的執行時機），見
    // plans/plan-issue-2.md「計劃範圍澄清」第 6 點。
    if (_activeGroupFilter != null) return;
```

（其餘方法內容不變。）

**3c. `_openGroupFilteredView`／新增 `_exitGroupFilteredView`——取代整段 `Navigator.push`**：

刪除現有的 `_openGroupFilteredView(String groupName)` 方法全文（`library_screen.dart:482-546`，從 `void _openGroupFilteredView(String groupName) {` 到對應的 `}` 結束，含整段 `Navigator.of(context).push(MaterialPageRoute(...)).then((_) {...})` 與其歷次審查修正註解），改為：

```dart
  void _openGroupFilteredView(String groupName) {
    setState(() => _activeGroupFilter = groupName);
  }

  void _exitGroupFilteredView() {
    setState(() => _activeGroupFilter = null);
  }
```

**3d. `build()` 的 `PopScope` 合併多選／下鑽兩種攔截條件**：

**（`review-plan-issue-2.md` M-1 記錄，非程式碼異動，純行為說明）**：`AdaptiveShellScaffold`（Issue 1）與這裡的 `LibraryScreen` 各自有一層 `PopScope`，但兩者位於同一個 `IndexedStack`、共享同一個 `ModalRoute`——當使用者已下鑽某分類（`_activeGroupFilter != null`）後切去「來源」／「設定」分頁，此時兩層 `PopScope` 的 `canPop` 皆為 `false`；使用者在非書架分頁按下系統返回鍵時，`onPopInvokedWithResult` 會同時觸發：`AdaptiveShellScaffold` 切回書架分頁（`_currentIndex = 0`），`LibraryScreen`（此時已重新可見）也會同時執行 `_exitGroupFilteredView()` 把 `_activeGroupFilter` 重置為 `null`。最終結果是「按一次返回鍵，同時退出目的地分頁與分類下鑽狀態，直接回到最頂層書架」——這是 `IndexedStack` 架構下兩層 `PopScope` 疊加的自然聯動結果，符合 `spec.md` §功能② 明文規範的使用者體驗，不是缺陷，本計劃不需要為此新增任何程式碼或測試，僅在此記錄供日後維護者理解。

```dart
  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
    return PopScope(
      canPop: !_inSelectionMode && _activeGroupFilter == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_inSelectionMode) {
          _exitSelectionMode();
        } else if (_activeGroupFilter != null) {
          _exitGroupFilteredView();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : (books.isEmpty ? _buildEmptyState() : _buildBookList(books)),
      ),
    );
  }
```

**3e. `_buildNormalAppBar()`——新增 `leading` 返回按鈕，`title`／選單顯示條件改讀 `_activeGroupFilter`**：

```dart
  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      leading: _activeGroupFilter == null
          ? null
          : IconButton(
              key: const Key('library_back_from_group_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回上層',
              onPressed: _exitGroupFilteredView,
            ),
      title: Text(_activeGroupFilter ?? '書架'),
      actions: [
        PopupMenuButton<void>(
          key: const Key('library_sort_view_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序與檢視',
          enabled: books != null,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;
            return [
              for (final sortBy in LibrarySortBy.values)
                PopupMenuItem<void>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  onTap: () => _bookListController.changeSortBy(sortBy),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: currentSort == sortBy
                            ? Icon(Icons.check, size: 20, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortLabel(sortBy),
                        style: TextStyle(
                          fontWeight: currentSort == sortBy
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: currentSort == sortBy ? primaryColor : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('library_sort_view_toggle_option'),
                onTap: _toggleViewMode,
                child: Text(
                  _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
                ),
              ),
              if (_activeGroupFilter == null)
                PopupMenuItem<void>(
                  key: const Key('library_manage_groups_option'),
                  onTap: _openManageGroupsDialog,
                  child: const Text('管理分類...'),
                ),
            ];
          },
        ),
        IconButton(
          key: const Key('library_source_button'),
          icon: const Icon(Icons.cloud_download),
          tooltip: '來源',
          onPressed: widget.onNavigateToSource,
        ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: widget.onNavigateToSettings,
        ),
      ],
    );
  }
```

（只有 `leading` 新增、`title` 與 `if (widget.groupFilter == null)` 兩處變數來源改變，選單其餘內容逐字不動。）

**3f. `_buildBookList()`——`groupTiles`／`visibleBooks` 改讀 `_activeGroupFilter`，並修正用戶端過濾（見「計劃範圍澄清」第 2 點）**：

```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    final groupTiles = _activeGroupFilter == null
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    // 【epic-36 Issue 2】visibleBooks 現在一律對 controller 已載入的全部書籍
    // 做用戶端過濾（見 plans/plan-issue-2.md「計劃範圍澄清」第 2 點）——
    // LibraryBookListController 不再對 repository 做以 _activeGroupFilter
    // 為條件的伺服器端篩選（該欄位只能在 initState 決定、之後不隨使用者
    // 點擊拼貼格而變動），下鑽分類時改為直接篩出 groupName 相符的書籍。
    final visibleBooks = _activeGroupFilter == null
        ? books.where((b) => b.groupName == BookGroup.uncategorized).toList()
        : books.where((b) => b.groupName == _activeGroupFilter).toList();
    final itemCount = groupTiles.length + visibleBooks.length;
```

（`itemBuilder`／`GridView`／`ListView` 其餘內容不變。）

- [x] **Step 4: 執行測試確認 5 則新測試通過（`review-plan-issue-2.md` M-3：用 `--name` 過濾取得乾淨訊號）**

Run:
```bash
flutter test test/screens/library_screen_test.dart --name "原地狀態切換|返回上層|PopScope 合併邏輯"
```
Expected: Step 1 新增的 5 則測試 100% PASS（過濾後只看得到這 5 則，不被接下來要處理的既有測試雜訊干擾）。

接著 Run（不過濾，取得完整既有測試現況）：
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: 除了上述 5 則新測試外，會有一批**預期中**的新增失敗——凡是依賴「`_openGroupFilteredView` 會 `Navigator.push` 出一個獨立 `LibraryScreen` 實例」這個舊行為的既有測試（`_filteredLibraryScreenFinder` 的 10 個呼叫點所在的測試、`navigatorState.maybePop()` 相關斷言）都會失敗。**驗證方式**：確認失敗清單裡的每一則都能對應到「計劃範圍澄清」第 1／6 點列出的既有測試名稱／行號，不能有本 Step 改動範圍外的意外失敗。這批失敗會在 Step 5-13 內於**同一個 Task**收斂為 0（`review-plan-issue-2.md` I-1：不得帶著已知失敗跨到下一個 Task 才修，也不得作為本 Task 的 Commit 點）。

- [x] **Step 5：讀懂要刪除/遷移的既有測試分佈（唯讀，不改檔案）**

對照下方清單逐一確認（本計劃規劃階段已逐一讀取每則測試完整內容，以下為分類結果，執行時不需要重新 grep 尋找）：

**(a) 整段刪除（4 處，測試的驗證意圖本身隨 `Navigator.push` 移除而消失，不是「換個方式驗證同一件事」）**：
- `library_screen_test.dart:2668-2745`（`'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，ReaderScreen 收到的 syncCheckpointTrigger 與外層一致...'`）
- `library_screen_test.dart:2747-2802`（`'...ReaderScreen 收到的 ttsProvider 與外層一致...'`）
- `library_screen_test.dart:2804-2871`（`'...ttsAudioHandler／ttsAudioFocusSource...layoutPresetRepository／bookReaderPrefsRepository...'`）
- `library_screen_test.dart:2873-2934`（`'...googleDriveStorageClient／computeFingerprint／isMobileDataConnection 皆與外層一致...'`）

這 4 則的共同前提是「`_openGroupFilteredView()` 的 `Navigator.push` 是否把所有依賴 bundle 正確轉送給下一層獨立 `LibraryScreen` 實例」——原地下鑽後全程只有一個 `LibraryScreen` 實例，`widget.xxx` 本來就是同一份，不存在「轉送」這件事，這 4 則測試連同其存在意義一併消失（不是遺留技術債，是驗證對象本身不再存在）。

**(b) 整段刪除（1 處，見「計劃範圍澄清」第 6 點）**：
- `library_screen_test.dart:3031-3067`（`'透過分類篩選路徑（groupFilter 非 null）進入的 LibraryScreen 不會自動開書...'`）

**(c) 改寫（6 處，篩選結果正確性驗證，改為在唯一畫面樹上直接查找，不再需要 `find.descendant(of: _filteredLibraryScreenFinder(...))` 限定範圍）**：
- `library_screen_test.dart:556-610`
- `library_screen_test.dart:755-804`
- `library_screen_test.dart:998-1057`
- `library_screen_test.dart:1284-1351`
- `library_screen_test.dart:1353-1421`
- `library_screen_test.dart:1423-1469`

**(d) 輔助函式定義移除（1 處）**：
- `library_screen_test.dart:3732-3740`（`_filteredLibraryScreenFinder` 函式本身）

**(e) 不需要改動（確認繼續通過即可，不在本 Task 動它們）**：
- 6 處 `library_manage_groups_option` 相關測試（`682-685`、`728-731`、`771-774`、`820-823` 附近，另有 `853`、`1404` 各一則同模式）——這些測試在 Issue 1 已經是「先開 `library_sort_view_button` 選單、再點 `library_manage_groups_option`」的路徑，Task 1 只是把判斷式的變數來源從 `widget.groupFilter` 換成 `_activeGroupFilter`，測試本身完全不需要修改。
- `library_screen_test.dart:2446-2481`（`'長按進入選取模式後，分類拼貼格的 onTap 停用...'`）——純粹驗證選取狀態不受影響，不依賴 `_filteredLibraryScreenFinder`／新路由。

### 測試遷移——(c) 類 6 處改寫

- [x] **Step 6**：改寫 `library_screen_test.dart:556-610`（測試名稱：`'點擊分類拼貼格後只顯示該分類書籍；返回書架後僅顯示未分類書籍與分類拼貼格（已分類書籍不重複列出）'`）。第 584 行起、原本用 `navigatorState.maybePop()` 返回的整段改為：

```dart
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

（測試名稱可視情況同步改為「...點擊返回按鈕後...」以符合新觸發方式，但非必要——`findsOneWidget`/`findsNothing` 這些斷言意圖本身不變。）

- [x] **Step 7**：改寫 `library_screen_test.dart:755-804`（測試名稱：`'管理分類對話框：刪除確認對話框按下取消，分類與所屬書籍皆不受影響'`）。第 792-804 行改為：

```dart
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });
```

- [x] **Step 8**：改寫 `library_screen_test.dart:998-1057`（測試名稱：`'選取多本書後點擊「移動到分類」，選擇目的分類後所有已勾選書籍的分類皆更新'`）。第 1039-1056 行改為：

```dart
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

- [x] **Step 9**：改寫 `library_screen_test.dart:1284-1351`（測試名稱：`'書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動'`）。第 1333-1350 行改為：

```dart
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });
```

- [x] **Step 10**：改寫 `library_screen_test.dart:1353-1421`（測試名稱：`'點擊分類拼貼格會推入新的 LibraryScreen 並以該分類篩選；篩選畫面不顯示拼貼格區塊與管理分類按鈕'`，同時把名稱改為符合新行為）。整則改為：

```dart
  testWidgets('點擊分類拼貼格為原地狀態切換；下鑽後不顯示拼貼格區塊與管理分類選單項目', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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

    // AppBar 標題顯示分類名稱，不是「書架」。
    expect(find.text('奇幻'), findsOneWidget);

    // 原地下鑽後畫面樹上只有一個 LibraryScreen——不再顯示拼貼格區塊。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_manage_groups_option')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);
  });
```

- [x] **Step 11**：改寫 `library_screen_test.dart:1423-1469`（測試名稱：`'從分類篩選畫面把書移到其他分類後返回書架，頂層拼貼格與書籍清單即時反映最新狀態'`，同時把名稱改為符合新觸發方式）。整則改為：

```dart
  testWidgets('在分類篩選畫面把書移到其他分類後點擊返回按鈕回到書架，頂層拼貼格即時反映最新狀態', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '科幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_科幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    // bookA 已被移出「奇幻」——「奇幻」拼貼格應消失（剩 0 本），「科幻」
    // 拼貼格應顯示 2 本。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
    expect(find.text('科幻 (2)'), findsOneWidget);
  });
```

### 整段刪除 5 則測試＋輔助函式定義

- [x] **Step 12**：刪除 `library_screen_test.dart` 內以下 5 個完整 `testWidgets(...)` 區塊（依「計劃範圍澄清」第 1、6 點與 Step 5 (a)(b) 分類，逐字比對測試名稱字串後刪除，不得誤刪相鄰測試）：
  1. `'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，ReaderScreen 收到的 syncCheckpointTrigger 與外層一致（epic-8-sync Issue 10）'`
  2. `'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，ReaderScreen 收到的 ttsProvider 與外層一致（Issue 9 缺口修正）'`
  3. `'透過分類篩選路徑開書，ReaderScreen 收到的 ttsAudioHandler／ttsAudioFocusSource 應與外層一致（epic-34-tts-readalong Issue 7）；...'`
  4. `'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）進入後，googleDriveStorageClient／computeFingerprint／isMobileDataConnection 皆與外層一致（review-issue-3.md Important #1、review-issue-5.md Important #1、Epic 29 Issue 6 一併補上 採納）'`
  5. `'透過分類篩選路徑（groupFilter 非 null）進入的 LibraryScreen 不會自動開書，即使 openLastBookOnLaunch=true（epic-18-reader-device-qa Issue 29）'`

- [x] **Step 13**：刪除 `_filteredLibraryScreenFinder` 輔助函式定義（檔案末端，緊接在 `_testBook()` helper 之後的完整函式＋其 dartdoc 註解）：

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

整段刪除（Step B 的 6 處改寫已移除所有呼叫點，Step C Step 8 的 5 處刪除也移除了其餘呼叫點，此時應已無任何呼叫點引用這個函式）。

- [x] **Step 14：執行全套 `library_screen_test.dart` 確認 100% PASS（`review-plan-issue-2.md` I-1：本 Task 收尾 Commit 前必須全綠）**

Run: `flutter test test/screens/library_screen_test.dart`

反覆執行、依失敗訊息修正，直到全數 PASS（Step 6-13 的遷移應已涵蓋 Step 4 列出的全部既有失敗；若仍有殘留失敗，逐一核對是否遺漏 Step 5 分類清單中的某一項）。

Expected: PASS（全部案例，0 失敗）

- [x] **Step 15：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`（`widget.groupFilter` 欄位本身尚未移除、仍在使用中，Task 2 才會移除）

- [x] **Step 16：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): LibraryScreen 書架分類改為原地下鑽，PopScope 合併多選與下鑽返回邏輯"
```

---

## Task 2：`groupFilter` 建構參數移除（死碼清理收尾）

**（`review-plan-issue-2.md` I-1 修正）**：既有測試遷移已全數併入 Task 1（Task 1 結束時 `library_screen_test.dart` 已 100% PASS）。本 Task 純粹是移除過渡期橋接用的 `LibraryScreen.groupFilter` 建構參數／欄位，不再涉及任何測試遷移。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces:**
- Produces: `LibraryScreen` 移除 `groupFilter` 建構參數／欄位（`Interfaces` 契約異動：任何仍呼叫 `LibraryScreen(groupFilter: ...)` 的呼叫端會編譯失敗——已確認全專案除 Task 1 已遷移完畢的測試檔外無其他呼叫端，見規劃階段查證）。

- [x] **Step 1**：編輯 `app/lib/screens/library_screen.dart`：

刪除 `LibraryScreen` 類別的欄位宣告：

```diff
-  final String? groupFilter;
   final Listenable? refreshSignal;
```

刪除建構子對應具名參數：

```diff
     this.themeDependencies = const LibraryThemeDependencies(),
-    this.groupFilter,
     this.refreshSignal,
```

`_LibraryScreenState.initState()`：移除過渡期的橋接賦值（`_activeGroupFilter` 欄位宣告本身保留，只是不再有初始值來源，預設即為 `null`），並移除 controller 建構呼叫裡的 `groupFilter:` 具名引數：

```diff
   @override
   void initState() {
     super.initState();
-    _activeGroupFilter = widget.groupFilter;
     _bookListController = LibraryBookListController(
       repository: widget.repository,
-      groupFilter: widget.groupFilter,
     )..addListener(_onBookListChanged);
```

`_activeGroupFilter` 欄位的過渡期 dartdoc 註解同步更新（移除「本欄位目前仍由 widget.groupFilter 初始化一次...」這段已經過時的說明，改為單純說明用途）：

```dart
  /// 三目的地導覽下 LibraryScreen 只建構一次、恆為頂層模式（epic-36
  /// Issue 1），原本靠「另一個獨立 LibraryScreen 實例＋groupFilter 建構參數」
  /// 模擬下鑽的做法在 Issue 2 改為這個可變狀態的原地切換，透過
  /// _openGroupFilteredView()／_exitGroupFilteredView() 以 setState 變動。
  String? _activeGroupFilter;
```

- [x] **Step 2**：Run `flutter analyze`，確認沒有殘留對已移除的 `groupFilter` 欄位的引用（`_maybeOpenLastBookOnLaunch()`／`_buildBookList()`／`_buildNormalAppBar()` 皆已在 Task 1 改讀 `_activeGroupFilter`，理論上不應該有殘留）。

Expected: `No issues found!`

- [x] **Step 3**：Run `flutter test test/screens/library_screen_test.dart`，確認移除 `groupFilter` 沒有牽連任何未預期的呼叫點（規劃階段查證未發現除 Task 1 已處理的測試外還有其他呼叫端，此 Step 純粹是最終確認）。

Expected: PASS（全部案例，維持 Task 1 結尾時的 100% 通過狀態）

- [x] **Step 4**：Commit

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-36): 移除 LibraryScreen.groupFilter 建構參數（三目的地導覽下已無獨立篩選畫面實例）"
```

---

## Task 3：全套驗證與收尾

**Files:** 無新增/修改，純驗證。

- [x] **Step 1: 執行全套 `flutter test`（不帶檔案路徑）**

Run: `flutter test`
Expected: 全數通過（比照 `CLAUDE.md`「測試執行範圍」，這是整份計劃收尾的唯一一次全套執行）。若有失敗，比對是否為本計劃改動觸及的檔案；非本計劃觸及範圍的既有不穩定測試（若有）記錄下來，不在本 Issue 修復範圍內。

- [x] **Step 2: 執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3: 逐條核對 `issues.md` Issue 2 驗收標準**

- [x] 點擊分類拼貼格為原地狀態切換，不推入新路由
- [x] 系統返回鍵在多選/下鑽兩種情境下行為皆正確、不會誤關閉畫面或狀態混亂
- [x] 「管理分類」功能不變、僅入口位置改變（Issue 1 已完成入口搬遷，本 Issue 只改判斷條件的變數來源）
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過

- [x] **Step 4: 更新 `docs/epics.md` 備註欄位**

將 Epic 36 該列備註改為「Issue 2 已完成，待認領 Issue 3/4/5」（Issue 5 依賴僅為 Issue 1，可能已被認領/完成，執行時以 `issues.md` 實際狀態為準調整措辭）。

- [x] **Step 5: 依 `superpowers:requesting-code-review` 發起本 Issue 的程式碼審查**

審查者先產出報告至 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-2.md`，不得直接修改程式碼（比照專案 SDD 工作流程第 6 步）。審查請求內容須包含以下決策備註（`review-plan-issue-2.md` M-2）：`app/test/screens/library_screen_test.dart:3031-3067`（`issues.md` 原描述應改寫為「點擊分類拼貼格下鑽後確認不會觸發 `_maybeOpenLastBookOnLaunch`」）在 Task 1 Step 12 實際處理方式是**整段刪除**而非改寫——原因是 `_maybeOpenLastBookOnLaunch()` 在 `_initialize()` 中早於任何分類拼貼格渲染完成前就已執行過一次，使用者不可能在它執行的當下就點擊拼貼格觸發下鑽，這個 guard 分支在目前的公開 widget API 下已無法透過真實互動觸發，勉強寫一則依賴 pump 時序競態的測試只會是脆弱的假測試，故選擇誠實刪除，保留 production code 裡的等效 guard 語句與其簡短說明註解（見「計劃範圍澄清」第 6 點、Task 1 Step 3b）。

---

## Self-Review 紀錄（撰寫本計劃時的覆核結果）

- **Spec 覆蓋**：`spec.md` §功能②／`issues.md` Issue 2 的 Solution 逐條對照——`_activeGroupFilter` 狀態＋原地切換（Task 1 Step 3c）、`_buildBookList()` 改讀（Task 1 Step 3f，並修正 spec 字面指示遺漏的用戶端過濾缺口）、返回引導列（Task 1 Step 3e）、系統返回鍵合併（Task 1 Step 3d）、`groupFilter` 建構參數移除（Task 2 Step 1）、「管理分類」入口顯示條件改讀（Task 1 Step 3e）皆有對應 Task，無遺漏。
- **`issues.md`「單元測試要求」四項逐條對照**：「不產生新的 Navigator 路由」負向測試（Task 1 新測試 1）、「AppBar 顯示返回列」（Task 1 新測試 2）、系統返回鍵合併三情境（Task 1 新測試 3/4/5）、`library_manage_groups_button` 6 處既有測試遷移（規劃階段查證後確認 Issue 1 已完成遷移，本 Issue 不需要動，見「計劃範圍澄清」第 1 點延伸查證）、選取模式分類格 `onTap` 為 `null` 的既有測試（規劃階段查證確認不需修改，見 Task 1 Step 5 (e)）、`library_screen_test.dart` 既有測試遷移（`review-issues.md` I-2，Task 1 Step 6-13，含發現實際為 10 處而非 11 處的落差說明）皆已納入。
- **型別一致性**：`_activeGroupFilter`／`_openGroupFilteredView`／`_exitGroupFilteredView`／`library_back_from_group_button` 在 Task 1 定義後，Task 2 的 production code 清理原樣沿用，命名一致，無 Task 間的簽章漂移。
- **範圍落差已於「計劃範圍澄清」段落明文記錄並解決**：`_filteredLibraryScreenFinder` 實測呼叫點數量落差（第 1 點）、`visibleBooks` 用戶端過濾缺口（第 2 點，屬於本計劃規劃階段發現、若未修正會直接導致下鑽顯示錯誤書籍清單的功能性缺陷）、`_currentPage` 範圍邊界（第 3 點）、`_activeGroupFilter` 初始化方式的跨 Task 暫時性設計（第 4 點）、「已刪除分類重置」安全網結構上不可達（第 5 點）、`3031-3067` 測試改為刪除而非改寫的理由（第 6 點）。
- **`review-plan-issue-2.md` 複審修訂紀錄**：**I-1（Important，已修正）**——既有測試遷移（原 Task 2 Step A/B/C）整段併入 Task 1，使 Task 1／Task 2 各自的 Commit 節點都維持 `library_screen_test.dart` 100% PASS，不再有「已知失敗狀態下 Commit」的中繼狀態，Task 2 收斂為單純的 `groupFilter` 參數移除。**M-1（Minor，已記錄）**——Task 1 Step 3d 新增 `IndexedStack` 下兩層 `PopScope` 聯動行為說明，供日後維護者理解這是預期行為而非缺陷。**M-2（Minor，已採納）**——Task 3 Step 5 的程式碼審查請求內容納入 `3031-3067` 測試刪除決策的明文備註。**M-3（Minor，已採納）**——Task 1 Step 4 改用 `--name` 過濾指令取得新測試的乾淨驗證訊號。
