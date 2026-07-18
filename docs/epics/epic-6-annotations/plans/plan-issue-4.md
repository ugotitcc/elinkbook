# Epic 6 Issue 4：FXL（固定版面）書籤支援 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。步驟使用核取方塊（`- [ ]`）語法追蹤進度。

**Goal:** 讓正在讀 FXL（固定版面漫畫）EPUB 的使用者，能透過懸浮控制按鈕群組新增/移除目前頁書籤，並開啟與非 FXL 相同的 `NotesBottomSheet` 查看/管理書籤清單（「劃線與備註」分頁維持空狀態、不可互動）。

**Architecture:** 純 `ReaderScreen` 層的接線工作——`bookmarks` 資料表、`Bookmark` 模型、`BookmarksRepository`、`NotesBottomSheet` 皆已於 Issue 1 完整實作並通過審查/測試，且已原生支援 FXL（`Bookmark.defaultName`／`BookmarkPositionContext` 的 FXL 分支、`NotesBottomSheet` 在未提供 `highlightsRepository`/`notesRepository` 時自動顯示空狀態佔位符）。本工單只在 `_ReaderScreenState` 既有的 FXL 懸浮控制按鈕群組（`_isFixedLayout && _fixedLayoutControlsVisible` 既有 Stack，`epic-16-dual-page` Issue 9 建立）之外新增兩顆按鈕、一小段狀態管理，以及一個以既有 `onFixedLayoutPageTurn` 慣例為本的收合行為擴充。**不新增／不修改任何資料層或 `NotesBottomSheet` 程式碼**。

**Tech Stack:** Flutter/Dart（`StatefulWidget` 既有狀態管理模式），無新增套件依賴。

## Global Constraints

- **零資料層異動**：`bookmarks` 表 schema、`Bookmark` 模型、`BookmarksRepository`、`BookmarkPositionContext` 皆已於 Issue 1 完成並經審查，本工單不修改上述任一檔案，也不新增資料庫 migration。
- **FXL 定位機制**：FXL 副檔名為 `.epub`，Dart 端透過既有 EPUB 定位機制（`epubLocatorJson`／`progression`，來自 `EpubReaderView.onLocatorChanged` 回報、快取於 `_ReaderScreenState._epubPositionInfo`）追蹤位置，**不使用** `pdfPageIndex`——比照 `BookmarkPositionContext` 既有欄位語意與 `_openNotesSheet` 現有的 `format == BookFormat.epub` 分支（FXL 的 `detectBookFormat()` 結果本就是 `BookFormat.epub`，`_isFixedLayout` 是另一個獨立旗標）。
- **預設命名行為**：`Bookmark.defaultName()` 對 FXL 的既有行為是「進度百分比」（例如「35% 處」），因為 FXL 永遠不預取目錄（`_tocEntries` 恆空，`chapterTitle` 恆為 `null`）——這是 Issue 1 審查修正後已定案且已測試的既有行為（見 `bookmark.dart` 該方法的既有 KDoc），**不是**「第 N 頁」（`spec.md`/`design.md`/`issues.md` 部分文字描述沿用了尚未同步審查修正的舊字面敘述，以本檔案查證過、已審查通過的程式碼行為為準；本工單不修改 `bookmark.dart`，沿用其既有行為即可）。
- **三欄熱區收合邏輯**：新增的兩顆懸浮按鈕須與既有 `reader_fixed_layout_back_button`／`reader_fixed_layout_settings_button` 一樣，包在 `if (_isFixedLayout && _fixedLayoutControlsVisible)` 條件內，跟隨中間熱區 `onToggleFixedLayoutControls` 的既有顯示/隱藏切換。
- **零回歸 gating**：兩顆新按鈕僅在 `widget.bookmarksRepository != null` 時顯示，比照既有 `reader_notes_button` 的既有慣例，確保未提供 `bookmarksRepository` 的既有呼叫端（測試、尚未升級的呼叫路徑）不受影響。
- **避免競速寫入壞書籤**：兩顆新按鈕在 `_epubPositionInfo == null`（`onLocatorChanged` 尚未觸發過任何一次）期間必須停用（`onPressed: null`）——比照 `reader_notes_button` 既有的 `_epubPositionInfo == null` 防呆審查修正（見 `reader_screen.dart` 既有註解），避免在定位資料未就緒的極短窗口內寫入一筆 `epubLocatorJson`/`progression` 皆為 `null` 的壞書籤。
- **跳轉後收合懸浮控制項**：從 `NotesBottomSheet` 的書籤清單點選跳轉後，若目前為 FXL，須把 `_fixedLayoutControlsVisible` 強制設為 `false`（非 toggle 語意）——比照既有 `EpubReaderView.onFixedLayoutPageTurn` 換頁後強制收合的既定沉浸式閱讀慣例，書籤跳轉概念上等同換頁，不是另立新規則。
- **「劃線與備註」分頁維持空狀態**：`NotesBottomSheet` 現有邏輯（`highlightsRepository`/`notesRepository` 未同時提供時顯示 `notes_sheet_annotations_placeholder` 佔位符、不含任何互動元件）已完整滿足此需求——`ReaderScreen._openNotesSheet` 現有的 `highlightsRepository`/`notesRepository` 傳遞條件（`(format == BookFormat.epub && !_isFixedLayout) || format == BookFormat.pdf`）在 `_isFixedLayout == true` 時已正確解析為 `null`，本工單呼叫 `_openNotesSheet(BookFormat.epub)` 時**不需要**額外修改這段既有邏輯。

## 檔案異動總覽

只異動一個既有原始碼檔案與一個既有測試檔案，並新增一個 integration_test 檔案：

- **修改** `app/lib/screens/reader_screen.dart`：新增 `Bookmark` import、`_fxlBookmarks` 狀態欄位、`_loadFxlBookmarks()`／`_fxlBookmarkAtCurrentPosition`／`_toggleFxlBookmark()` 三個方法、`_handleLayoutResolved()` 內一段載入呼叫、`_openNotesSheet()` 內兩處小擴充（跳轉後收合＋關閉後重新整理）、`_buildBody()` 的 FXL 懸浮按鈕 Stack 內新增兩個 `Positioned` 元件。
- **修改** `app/test/screens/reader_screen_test.dart`：新增 6 個 widget test（Task 1 三個、Task 2 三個）。
- **新增** `app/integration_test/fxl_bookmarks_test.dart`：真機端到端整合測試。

不修改：`bookmark.dart`、`bookmark_position_context.dart`、`bookmarks_repository.dart`、`notes_bottom_sheet.dart`、`sqlite_library_repository.dart`（資料層與既有 Bottom Sheet UI 完全複用，零異動）。

---

### Task 1: FXL 懸浮「🔖 書籤 toggle」按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`Bookmark`（`bookId`／`name`／`epubLocatorJson`／`progression`／`pdfPageIndex` 建構參數，`id` 唯讀欄位）、`Bookmark.defaultName(BookmarkPositionContext)`、`BookmarksRepository.listByBook(String)`／`.insert(Bookmark)`／`.delete(int)`、`_ReaderScreenState._epubPositionInfo`（`EpubPositionInfo?`，欄位 `locatorJson`／`progression`）、`_isFixedLayout`、`_fixedLayoutControlsVisible`、`widget.bookmarksRepository`（`BookmarksRepository?`）。
- Produces（供 Task 2／Task 3 使用）：
  - `List<Bookmark> _fxlBookmarks` 狀態欄位
  - `Future<void> _loadFxlBookmarks()` 方法
  - `Bookmark? get _fxlBookmarkAtCurrentPosition`
  - `Future<void> _toggleFxlBookmark()` 方法
  - Key `reader_fixed_layout_bookmark_toggle_button`（`IconButton`，`onPressed` 於 `_epubPositionInfo == null` 時為 `null`）

- [ ] **Step 1: 在 `reader_screen_test.dart` 新增 3 個失敗測試**

在檔案最末的 `// --- Epic 6 Issue 2：EPUB 劃線/備註 ---` 區段結尾（`main()` 函式的最後一個 `});` 之前，也就是既有最後一個測試「PDF 書籍未提供 highlightsRepository／notesRepository 時建構不受影響（既有呼叫端零回歸）」的 `});` 之後、`}` 之前，新增以下區段與 3 個測試：

```dart
  // --- Epic 6 Issue 4：FXL 書籤支援 ---

  testWidgets(
      'FXL：未提供 bookmarksRepository 時，懸浮書籤/筆記按鈕皆不存在（既有呼叫端零回歸）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_no_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button')),
      findsNothing,
    );
  });

  testWidgets(
      'FXL：提供 bookmarksRepository 後，懸浮書籤按鈕存在，onLocatorChanged 前為停用狀態',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_disabled',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLocatorChanged，_epubPositionInfo 仍為 null，比照 '
          'reader_notes_button 既有防呆邏輯',
    );
  });

  testWidgets(
      'FXL：收到 onLocatorChanged 後，點擊懸浮書籤按鈕可新增/移除目前頁書籤，圖示正確切換並持久化',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_toggle',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    view.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/page1.xhtml"}', progression: 0.2),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
    expect(
      (tester.widget<IconButton>(finder).icon as Icon).icon,
      Icons.star_border,
    );

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect((tester.widget<IconButton>(finder).icon as Icon).icon, Icons.star);
    final afterAdd = await bookmarksRepository.listByBook('b_fxl_bookmark_toggle');
    expect(afterAdd, hasLength(1));
    expect(afterAdd.single.epubLocatorJson, '{"href":"/page1.xhtml"}');
    expect(afterAdd.single.progression, 0.2);
    expect(afterAdd.single.pdfPageIndex, isNull);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect((tester.widget<IconButton>(finder).icon as Icon).icon, Icons.star_border);
    final afterRemove = await bookmarksRepository.listByBook('b_fxl_bookmark_toggle');
    expect(afterRemove, isEmpty);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: FAIL — 找不到 `Key('reader_fixed_layout_bookmark_toggle_button')`（`reader_screen.dart` 尚未實作此按鈕）。

- [ ] **Step 3: 實作 `reader_screen.dart`**

**3a. 新增 import。** 在既有 import 區塊（`reader_screen.dart` 第 6 行）之前插入：

```dart
import '../reader/bookmark.dart';
```

使該區塊變為：

```dart
import '../reader/annotation_list_item.dart';
import '../reader/book_format.dart';
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';
```

**3b. 新增狀態欄位。** 在 `_fixedLayoutControlsVisible` 欄位宣告（第 99-101 行）之後插入：

```dart
  // FXL 懸浮「🔖 書籤 toggle」按鈕圖示所需的最小狀態快取
  // （epic-6-annotations Issue 4）：與 NotesBottomSheet 內部「🔖 書籤」
  // 分頁各自獨立載入自己的清單（比照既有分頁按鈕 toggle 與 Bottom Sheet
  // 清單各自管理狀態的既定模式），只負責懸浮按鈕圖示的二態顯示。載入
  // 時機見 _handleLayoutResolved（初次開書）／_openNotesSheet（Bottom
  // Sheet 關閉後重新整理，使用者可能在分頁裡新增/刪除書籤）。
  List<Bookmark> _fxlBookmarks = [];
```

**3c. 新增三個方法。** 在 `_openFxlSettings()` 方法（原第 439-448 行）之後、`_openToc()` 方法之前插入：

```dart
  Future<void> _loadFxlBookmarks() async {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final list = await repository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() => _fxlBookmarks = list);
  }

  /// 目前頁是否已有書籤——比較 epubLocatorJson 完全相同字串，比照
  /// NotesBottomSheet._matchesCurrentPosition 既有邏輯（FXL 副檔名為
  /// .epub，恆用 epubLocatorJson，不使用 pdfPageIndex，見 Global
  /// Constraints）。
  Bookmark? get _fxlBookmarkAtCurrentPosition {
    final locatorJson = _epubPositionInfo?.locatorJson;
    if (locatorJson == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.epubLocatorJson == locatorJson) return bookmark;
    }
    return null;
  }

  Future<void> _toggleFxlBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    final existing = _fxlBookmarkAtCurrentPosition;
    if (existing != null) {
      await repository.delete(existing.id!);
    } else {
      await repository.insert(Bookmark(
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ));
    }
    await _loadFxlBookmarks();
  }
```

**3d. 於 `_handleLayoutResolved()` 內載入初始清單。** 該方法目前結尾為（原第 597-604 行）：

```dart
    if (!info.isFixedLayout &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
  }
```

改為（新增最後一個 `if` 區塊）：

```dart
    if (!info.isFixedLayout &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
    if (info.isFixedLayout && widget.bookmarksRepository != null) {
      _loadFxlBookmarks();
    }
  }
```

**3e. 新增懸浮按鈕。** 在 `_buildBody()` 的 `Stack` 中，既有右上角「⚙️版面設定」`Positioned`（原第 1097-1112 行，以 `reader_fixed_layout_settings_button` 結尾）之後、`if (selection != null)`（原第 1113 行）之前插入：

```dart
            if (_isFixedLayout &&
                _fixedLayoutControlsVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_bookmark_toggle_button'),
                      icon: Icon(
                        _fxlBookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                      ),
                      tooltip: _fxlBookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleFxlBookmark,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-6): FXL 新增懸浮書籤 toggle 按鈕"
```

---

### Task 2: FXL 懸浮「📚 筆記」按鈕 + 跳轉後收合 + 狀態同步

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes（Task 1 產物）：`_fxlBookmarks`、`_loadFxlBookmarks()`、`_fxlBookmarkAtCurrentPosition`、Key `reader_fixed_layout_bookmark_toggle_button`。
- Consumes（既有）：`_openNotesSheet(BookFormat format)`、`_isFixedLayout`、`_fixedLayoutControlsVisible`、`_epubPositionInfo`、`widget.bookmarksRepository`、`NotesBottomSheet`（`onBookmarkSelected`／`onAnnotationSelected` 等既有具名參數不變）。
- Produces：Key `reader_fixed_layout_notes_button`（`IconButton`，`onPressed` 於 `_epubPositionInfo == null` 時為 `null`，點擊呼叫 `_openNotesSheet(BookFormat.epub)`）。

- [ ] **Step 1: 在 `reader_screen_test.dart` 新增 3 個失敗測試**

在 Task 1 新增的 `// --- Epic 6 Issue 4：FXL 書籤支援 ---` 區段內，緊接 Task 1 新增的最後一個測試（「FXL：收到 onLocatorChanged 後...」）之後插入：

```dart
  testWidgets(
      'FXL：懸浮筆記按鈕開啟 Bottom Sheet，「🔖 書籤」分頁可用、「✏️ 劃線與備註」分頁顯示空狀態且不可互動',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_notes_sheet',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    final notesButtonFinder = find.byKey(const Key('reader_fixed_layout_notes_button'));
    expect(notesButtonFinder, findsOneWidget);
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNull);

    view.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/page1.xhtml"}', progression: 0.2),
    );
    await tester.pump();
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNotNull);

    await tester.tap(notesButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_tab_bookmarks')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_bookmark_toggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pump();

    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_delete_all_highlights')), findsNothing);
    expect(find.byKey(const Key('notes_sheet_delete_all_notes')), findsNothing);
  });

  testWidgets(
      'FXL：於 Bottom Sheet 的書籤分頁新增書籤後關閉，懸浮書籤按鈕圖示同步更新',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_sync',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    view.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/page1.xhtml"}', progression: 0.2),
    );
    await tester.pump();

    final bookmarkToggleFinder =
        find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button'));
    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star_border,
    );

    await tester.tap(find.byKey(const Key('reader_fixed_layout_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pumpAndSettle();

    // 關閉 Bottom Sheet（點擊外側遮罩）。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star,
      reason: 'Bottom Sheet 內新增書籤後關閉，懸浮按鈕應重新載入並反映最新狀態',
    );
  });

  testWidgets('FXL：從書籤清單點選跳轉後，Bottom Sheet 關閉且懸浮控制項收合',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_jump_collapse',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    view.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/page1.xhtml"}', progression: 0.2),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_fixed_layout_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
      reason: '書籤跳轉比照既有換頁慣例，強制收合懸浮控制項',
    );
    expect(find.byKey(const Key('reader_fixed_layout_notes_button')), findsNothing);
    expect(
      find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button')),
      findsNothing,
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: FAIL — 找不到 `Key('reader_fixed_layout_notes_button')`；「跳轉後收合」測試因按鈕不存在同樣失敗。

- [ ] **Step 3: 實作 `reader_screen.dart`**

**3a. 擴充 `_openNotesSheet()`。** 目前完整方法（原第 472-528 行）為：

```dart
  void _openNotesSheet(BookFormat format) {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final positionContext = BookmarkPositionContext(
      epubLocatorJson:
          format == BookFormat.epub ? _epubPositionInfo?.locatorJson : null,
      progression:
          format == BookFormat.epub ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.highlightsRepository
            : null,
        notesRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.notesRepository
            : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
        },
      ),
    );
  }
```

改為（`onBookmarkSelected` 內新增收合邏輯；`showModalBottomSheet` 呼叫結尾新增 `.then()` 重新整理）：

```dart
  void _openNotesSheet(BookFormat format) {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final positionContext = BookmarkPositionContext(
      epubLocatorJson:
          format == BookFormat.epub ? _epubPositionInfo?.locatorJson : null,
      progression:
          format == BookFormat.epub ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.highlightsRepository
            : null,
        notesRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.notesRepository
            : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
          // epic-6-annotations Issue 4：FXL 書籤跳轉概念上等同換頁，套用與
          // EpubReaderView.onFixedLayoutPageTurn（見本檔案下方
          // _buildNativeView）相同的既有沉浸式閱讀慣例——一律強制收合，非
          // toggle 語意，不是另立新規則。
          if (_isFixedLayout) {
            setState(() => _fixedLayoutControlsVisible = false);
          }
        },
      ),
    ).then((_) {
      // epic-6-annotations Issue 4：FXL 懸浮書籤按鈕的二態圖示快取
      // （_fxlBookmarks）與本 Bottom Sheet 內「🔖 書籤」分頁各自獨立載入
      // 自己的清單（見 _loadFxlBookmarks 說明），Bottom Sheet 關閉後主動
      // 重新整理一次，確保使用者在分頁裡新增/刪除書籤後，懸浮按鈕圖示不會
      // 停留在過期狀態。
      if (_isFixedLayout) _loadFxlBookmarks();
    });
  }
```

**3b. 新增懸浮筆記按鈕。** 在 Task 1 新增的 `reader_fixed_layout_bookmark_toggle_button` `Positioned` 區塊之後（仍在 `if (selection != null)` 之前）插入：

```dart
            if (_isFixedLayout &&
                _fixedLayoutControlsVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_notes_button'),
                      icon: const Icon(Icons.bookmarks, color: Colors.white),
                      tooltip: '筆記',
                      onPressed: _epubPositionInfo == null
                          ? null
                          : () => _openNotesSheet(BookFormat.epub),
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-6): FXL 新增懸浮筆記按鈕，書籤跳轉後收合懸浮控制項"
```

---

### Task 3: 真機整合測試 + 全專案回歸驗證

**Files:**
- Create: `app/integration_test/fxl_bookmarks_test.dart`

**Interfaces:**
- Consumes：Task 1／Task 2 產物（`reader_fixed_layout_bookmark_toggle_button`／`reader_fixed_layout_notes_button` 兩個 Key）、既有 `NotesBottomSheet` 的既有 Key（`notes_sheet_bookmark_list`／`notes_sheet_bookmark_rename_<id>`／`notes_sheet_rename_field`／`notes_sheet_rename_confirm`／`notes_sheet_tab_annotations`／`notes_sheet_annotations_placeholder`／`notes_sheet_delete_all_highlights`）、既有 `BookmarksRepository`／`SqliteLibraryRepository`／`ReaderPrefsManagerImpl` 建構模式（比照 `notes_bookmark_test.dart` 既有先例）、既有 test fixture `test/fixtures/sample_fixed_layout.epub`（已於 `pubspec.yaml` 宣告為 asset）。
- Produces：無（本 Task 為端到端驗證，不供後續 Task 消費）。

**與 Issue 2／Issue 3 的差異說明**：本工單的懸浮按鈕點擊、Bottom Sheet 分頁切換、清單項目點選皆是純 Flutter 側手勢（非原生 `PlatformView` 內部的 WebView 選字或長按框選手勢），`WidgetTester.tap` 可完整、可靠地驅動整條流程並斷言結果——不像 Issue 2／Issue 3 的原生選字/框選手勢那樣需要留一份「真機人工驗證清單」給人工事後補做。本 Task 的 integration_test 應能在真機/模擬器上真正跑通並通過。

- [ ] **Step 1: 新增 `app/integration_test/fxl_bookmarks_test.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilFxlBookmarkToggleEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：懸浮書籤按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FXL：懸浮書籤 toggle 新增、Bottom Sheet 清單查看/重新命名/跳轉、劃線與備註分頁維持空狀態的端到端流程',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_fixed_layout.epub',
      'fxl_bookmarks.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_fxl_bookmarks',
      title: 'FXL 書籤測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_fxl_bookmarks',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFxlBookmarkToggleEnabled(tester);

    // 懸浮書籤 toggle：新增目前頁書籤。
    await tester.tap(find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button')));
    await tester.pumpAndSettle();

    // 懸浮筆記按鈕：開啟 Bottom Sheet 確認書籤已持久化寫入資料庫。
    await tester.tap(find.byKey(const Key('reader_fixed_layout_notes_button')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsOneWidget);

    final bookmarks = await bookmarksRepository.listByBook('b_fxl_bookmarks');
    expect(bookmarks, hasLength(1));
    final bookmarkId = bookmarks.single.id;

    // 重新命名。
    await tester.tap(find.byKey(Key('notes_sheet_bookmark_rename_$bookmarkId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_sheet_rename_field')),
      '我的書籤',
    );
    await tester.tap(find.byKey(const Key('notes_sheet_rename_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('我的書籤'), findsOneWidget);

    // 「✏️ 劃線與備註」分頁：FXL 不支援，維持空狀態且無批次刪除按鈕。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_delete_all_highlights')), findsNothing);

    // 切回書籤分頁，點選跳轉：Bottom Sheet 關閉、懸浮控制項收合。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_fixed_layout_back_button')), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [ ] **Step 2: 於真實裝置/模擬器執行整合測試**

Run: `cd app && flutter test integration_test/fxl_bookmarks_test.dart -d <device-id>`（`<device-id>` 以 `flutter devices` 查得的實際 id 取代）
Expected: `All tests passed!`

- [ ] **Step 3: 執行全專案回歸驗證**

Run: `cd app && flutter test`
Expected: `All tests passed!`（不得有既有測試失敗，含既有 FXL 相關測試——`sample_fixed_layout.epub`／`_fixed_layout_back_button`／`_fixed_layout_settings_button` 相關案例）

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/fxl_bookmarks_test.dart
git commit -m "test(epic-6): 新增 FXL 書籤真機整合測試"
```

---

## Self-Review 紀錄

**Spec coverage：** 對照 `issues.md` Issue 4 的 8 條驗收標準逐一核對：
- 兩顆懸浮按鈕（🔖／📚）→ Task 1 + Task 2
- FXL 書籤複用 Issue 1 資料模型與清單 UI（零新增資料層）→ Global Constraints 明文禁止資料層異動
- 「劃線與備註」分頁空狀態不可互動 → 既有 `NotesBottomSheet` 行為已滿足，Task 2 測試驗證
- 新按鈕跟隨三欄熱區收合邏輯 → Task 1／Task 2 皆使用 `_fixedLayoutControlsVisible` gating
- 書籤跳轉後自動收合 → Task 2 `onBookmarkSelected` 擴充
- 既有 FXL 測試無回歸 → Task 3 Step 3 全專案 `flutter test`
- 測試通過＋`flutter analyze` 乾淨 → Task 3 Step 3
- 真機整合測試 → Task 3 Step 1／2

**Placeholder scan：** 全文無 TBD／implement later／模糊描述，所有程式碼步驟皆含完整可執行程式碼。

**Type consistency：** `_fxlBookmarkAtCurrentPosition`（Task 1 定義）在 Task 1／Task 2 的 Positioned 按鈕與測試中皆以相同名稱／型別（`Bookmark?`）使用；`_loadFxlBookmarks()`（`Future<void>`，無參數）在 Task 1（初始載入）與 Task 2（`.then()` 回呼）呼叫方式一致。
