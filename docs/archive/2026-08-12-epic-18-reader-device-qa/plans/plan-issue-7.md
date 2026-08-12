# Issue 7 實作計畫：流式 EPUB Chrome 重構（浮動選單列＋頁眉/進度資訊分離）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把流式 EPUB（`FoliateEpubReaderView`，`_dispatchedIsFixedLayout == false`）的 chrome（頁眉、TOC/設定/筆記按鈕、進度/跳頁）從目前的 in-flow `AppBar`+`ReaderFooter` 改成跟 FXL（`EpubReaderView`）同款的 `Positioned` 浮動疊加層，解掉「頁尾顯示/隱藏會改變 body 高度、觸發 WebView 整本重新分頁」的既有已知問題，並把「資訊顯示」（頁眉章節名稱、進度文字）與「功能操作」（TOC／設定／書籤／筆記／跳頁）徹底分離。

**Architecture:** `build()` 新增一個條件，讓 `format == BookFormat.epub && _dispatchedIsFixedLayout == false` 時 `Scaffold.appBar` 恆為 `null`；`_buildBody()` 的 `Stack` 在既有 FXL 浮動按鈕區塊之後，新增一組結構對稱的浮動按鈕（返回／TOC／設定／書籤 toggle／筆記／進度-跳頁）與兩個純顯示疊加層（頁眉章節名稱、進度文字，直排時進度文字用 `RotatedBox` 轉向置於左下角）。舊的 in-flow `_buildFoliateEpubFooter()` 呼叫整段移除，其換算邏輯改由新增的「進度/跳頁」浮動按鈕開啟的 `showModalBottomSheet` 呼叫端沿用。`_toggleFxlBookmark`/`_fxlBookmarkAtCurrentPosition` 這兩個目前隱含「FXL 專屬」語意的私有成員泛用化改名，供兩種 EPUB 引擎共用同一份書籤 toggle 邏輯。

**Tech Stack:** Flutter/Dart（`app/lib/screens/reader_screen.dart`），既有 `flutter_test` widget test（`app/test/screens/reader_screen_test.dart`），既有 `FakeInAppWebViewPlatform`（`app/test/support/fake_inappwebview_platform.dart`，Issue 10 已建立，讓 `InAppWebView`／`FoliateEpubReaderView` 可在純 `flutter_test` 環境下 pump）。真機驗收另見 Task 4。

## Global Constraints

- 所有文件與程式碼註解使用正體中文（zh-TW）。
- `flutter analyze` 必須維持 `No issues found!`（提交前必須乾淨）。
- `flutter test` 全數通過，不得引入回歸（提交前基準為 634 項全數通過，見 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 10 現況記錄）。
- 本 Issue **不修改** `readest/foliate-js` 釘定版本（`main.js`／`view.js`／`paginator.js` 等）——純 Dart 端 UI 重構，不涉及 JS 橋接或 `setAttribute` 呼叫。
- 本 Issue **不新增**任何 `BookReaderPrefs` 持久化欄位——`showHeader`/`showFooter` 既有欄位語意不變，只是 UI 呈現方式（in-flow → 浮動疊加層）調整。
- PDF 分支與 FXL（`_isFixedLayout == true`）既有行為必須維持零回歸，本 Issue 只影響 `format == BookFormat.epub && _dispatchedIsFixedLayout == false` 這一個分支。
- 只涉及 `app/lib/screens/reader_screen.dart` 與 `app/test/screens/reader_screen_test.dart` 兩個檔案；不涉及原生（Kotlin/JS）程式碼。

---

### Task 1：泛用化 FXL 書籤方法命名

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_fxlBookmarkAtCurrentPosition` getter 定義處、`_toggleFxlBookmark` 方法定義處、既有 FXL 浮動按鈕區塊內的 3 處呼叫）

**Interfaces:**
- Consumes: 無（純重構，不改變任何外部可觀察行為）
- Produces: `_bookmarkAtCurrentPosition`（原 `_fxlBookmarkAtCurrentPosition`）、`_toggleBookmark()`（原 `_toggleFxlBookmark()`）——供 Task 2 的流式 EPUB 浮動書籤按鈕共用。兩者皆為 `_ReaderScreenState` 私有成員，`app/test/screens/reader_screen_test.dart` 是不同檔案、無法直接參照，因此本次改名不影響任何既有測試斷言。

這是純粹的識別字重新命名，行為完全不變，只是拿掉「FXL 專屬」的命名暗示，為 Task 2 新增的流式 EPUB 書籤按鈕鋪路。

- [x] **Step 1：確認目前這兩個識別字的所有出現位置**

Run: `grep -n "_toggleFxlBookmark\|_fxlBookmarkAtCurrentPosition" app/lib/screens/reader_screen.dart`
Expected: 6 行結果——`_fxlBookmarkAtCurrentPosition` 的 getter 定義（約第 571 行）、`_toggleFxlBookmark` 的方法定義與其內部呼叫（約第 580/584 行）、FXL 浮動按鈕區塊內的 3 處使用（約第 1459/1464/1468 行）。

- [x] **Step 2：改名 getter 定義**

把：

```dart
  /// 目前頁是否已有書籤——比較 epubLocatorJson 完全相同字串，比照
  /// NotesBottomSheet._matchesCurrentPosition 既有邏輯（FXL 副檔名為
  /// .epub，恆用 epubLocatorJson，不使用 pdfPageIndex，見 Global
  /// Constraints）。
  Bookmark? get _fxlBookmarkAtCurrentPosition {
```

改為：

```dart
  /// 目前頁是否已有書籤——比較 epubLocatorJson 完全相同字串，比照
  /// NotesBottomSheet._matchesCurrentPosition 既有邏輯（FXL／流式 EPUB
  /// 副檔名皆為 .epub，恆用 epubLocatorJson，不使用 pdfPageIndex，見
  /// Global Constraints）。epic-18 Issue 7 泛用化改名（原
  /// _fxlBookmarkAtCurrentPosition），供 FXL 與流式 EPUB 共用。
  Bookmark? get _bookmarkAtCurrentPosition {
```

- [x] **Step 3：改名方法定義與內部呼叫**

把：

```dart
  Future<void> _toggleFxlBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    final existing = _fxlBookmarkAtCurrentPosition;
```

改為：

```dart
  Future<void> _toggleBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    final existing = _bookmarkAtCurrentPosition;
```

- [x] **Step 4：改名 FXL 浮動按鈕區塊內的 3 處使用**

把（既有 FXL 書籤 toggle 浮動按鈕區塊）：

```dart
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
```

改為：

```dart
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                      ),
                      tooltip: _bookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleBookmark,
```

- [x] **Step 5：靜態分析 + 執行既有 FXL 書籤測試，確認零行為變動**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "FXL"`
Expected: 所有名稱含「FXL」的既有測試（含 3 個書籤 toggle 相關測試）全數 PASS，無任何斷言改動。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(epic-18): 泛用化 FXL 書籤 toggle 方法命名，供流式 EPUB 共用（Issue 7 準備）"
```

---

### Task 2：Streaming EPUB Chrome 重構——抑制 AppBar、新增浮動按鈕與頁眉/進度疊加層、移除舊頁尾

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`build()` 的 `Scaffold.appBar` 條件、`_buildBody()` 的 `Stack` 內容、新增 2 個私有 helper 方法、新增 1 個開啟 Bottom Sheet 的方法）
- Test: `app/test/screens/reader_screen_test.dart`（新增測試，插入於檔案最末端最後一個 `testWidgets` 之後、收尾 `}` 之前）

**Interfaces:**
- Consumes: Task 1 產出的 `_bookmarkAtCurrentPosition`／`_toggleBookmark()`；既有 `_openToc()`／`_openLayoutSettings()`／`_openNotesSheet(BookFormat)`／`_buildFoliateEpubFooter(EpubPositionInfo)`（不修改本體，僅改變呼叫端）；`ResolvedPreferences.showHeader`／`showFooter`／`writingMode`（`app/lib/reader/resolved_preferences.dart`）；`EpubPositionInfo.pageIndex`／`totalPages`／`progression`（`app/lib/reader/epub_position_info.dart`）。
- Produces：8 個新 `Key`——`reader_foliate_back_button`／`reader_foliate_toc_button`／`reader_foliate_settings_button`／`reader_foliate_bookmark_toggle_button`／`reader_foliate_notes_button`／`reader_foliate_progress_button`／`reader_foliate_header_text`／`reader_foliate_progress_text`；2 個新私有方法 `Widget _buildFoliateHeaderText()`／`Widget _buildFoliateProgressText()`；1 個新私有方法 `void _openFoliateProgressSheet()`。

#### 版面配置（起始建議值，真機測試後可依 Task 4 視覺效果調整，比照 Issue 2/3 既有慣例）

| 元件 | 位置 |
|---|---|
| 返回鈕 | `top: 16, left: 16` |
| TOC 鈕 | `top: 16, right: 16` |
| 版面設定鈕 | `top: 72, right: 16` |
| 書籤 toggle 鈕 | `top: 128, right: 16` |
| 筆記鈕 | `top: 184, right: 16` |
| 進度/跳頁鈕（第 6 顆） | `top: 240, right: 16` |
| 頁眉文字 | `top: 16, left: 72, right: 72`（置中，避開左右兩側按鈕） |
| 進度文字（橫排） | `bottom: 16`，水平置中 |
| 進度文字（直排） | `left: 16, bottom: 16`，`RotatedBox(quarterTurns: 1)` |

- [x] **Step 1：撰寫失敗測試——AppBar 消失、6 顆浮動按鈕存在且可點擊**

在 `app/test/screens/reader_screen_test.dart` 檔案最末端（最後一個 `testWidgets` 區塊之後、收尾的 `}` 之前）新增：

```dart
  // ─────────────────────────────────────────────────────────────────────
  // epic-18-reader-device-qa Issue 7：流式 EPUB Chrome 重構（浮動選單列＋
  // 頁眉/進度資訊分離）。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets('流式 EPUB：AppBar 不顯示，6 顆浮動按鈕存在且可點擊（Issue 7）', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_chrome',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // _tocLoaded 由 loadTableOfContents() 的 .then() 設定，需多一次 pump。
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 0,
        totalPages: 10,
      ),
    );
    await tester.pump();

    for (final key in [
      'reader_foliate_back_button',
      'reader_foliate_toc_button',
      'reader_foliate_settings_button',
      'reader_foliate_bookmark_toggle_button',
      'reader_foliate_notes_button',
      'reader_foliate_progress_button',
    ]) {
      final finder = find.byKey(Key(key));
      expect(finder, findsOneWidget, reason: '$key 應存在');
      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNotNull,
        reason: '$key 應為可點擊狀態',
      );
    }
  });

  testWidgets('流式 EPUB：點擊浮動版面設定按鈕開啟 ReaderSettingsSheet（Issue 7）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_settings_btn',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
  });

  testWidgets(
    '流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤，圖示正確切換（複用泛用化後的 _toggleBookmark，Issue 7）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_bookmark_btn',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      final finder = find.byKey(
        const Key('reader_foliate_bookmark_toggle_button'),
      );
      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star,
      );

      final afterAdd = await bookmarksRepository.listByBook(
        'b_foliate_bookmark_btn',
      );
      expect(afterAdd, hasLength(1));
    },
  );

  testWidgets('流式 EPUB：點擊浮動筆記按鈕開啟 NotesBottomSheet（Issue 7）', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_notes_btn',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
  });

  testWidgets('流式 EPUB：頁眉純顯示章節名稱、不可點擊，showHeader=false 時不顯示（Issue 7）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final headerFinder = find.byKey(const Key('reader_foliate_header_text'));
    expect(headerFinder, findsOneWidget);
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(InkWell)),
      findsNothing,
      reason: '頁眉須為純顯示，不可點擊開啟目錄',
    );
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });

  testWidgets('流式 EPUB：showHeader=false 時頁眉不顯示（Issue 7）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_off',
      const BookReaderPrefs(showHeader: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_off',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_header_text')), findsNothing);
  });

  testWidgets(
    '流式 EPUB：進度為純顯示、橫排時置於下方置中且不含手勢 widget（Issue 7）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_h',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 167,
          totalPages: 197,
        ),
      );
      await tester.pump();

      final progressFinder = find.byKey(
        const Key('reader_foliate_progress_text'),
      );
      expect(progressFinder, findsOneWidget);
      expect(find.text('168/197'), findsOneWidget);
      expect(find.byType(RotatedBox), findsNothing);
      expect(
        find.ancestor(
          of: progressFinder,
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('流式 EPUB：直排時進度以 RotatedBox 顯示於左下角（Issue 7）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_progress_v',
      const BookReaderPrefs(writingModeOverride: WritingMode.vertical),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_v',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 167,
        totalPages: 197,
      ),
    );
    await tester.pump();

    final rotatedFinder = find.ancestor(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(RotatedBox),
    );
    expect(rotatedFinder, findsOneWidget);
    expect(tester.widget<RotatedBox>(rotatedFinder).quarterTurns, isNot(0));
  });

  testWidgets('流式 EPUB：showFooter=false 時進度文字與進度/跳頁按鈕皆不顯示（Issue 7）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_progress_off',
      const BookReaderPrefs(showFooter: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_off',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 0,
        totalPages: 10,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_progress_text')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_foliate_progress_button')),
      findsNothing,
    );
  });

  testWidgets(
    '流式 EPUB：點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter 的 Bottom Sheet，舊 in-flow 頁尾不再存在（Issue 7）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_sheet',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 9,
          totalPages: 100,
        ),
      );
      await tester.pump();

      // Bottom Sheet 開啟前，舊 in-flow ReaderFooter 應已不存在（見 Task 2
      // 「移除舊路徑」），畫面上只有浮動進度文字顯示同樣的頁碼。
      expect(find.byKey(const Key('reader_footer')), findsNothing);
      expect(find.text('10/100'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader_footer')), findsOneWidget);
      expect(
        find.byKey(const Key('reader_footer_progress_text')),
        findsOneWidget,
      );
      // 浮動疊加層（Bottom Sheet 開啟後仍在背景可見）與 Bottom Sheet 內的
      // ReaderFooter 各自顯示一份相同頁碼文字。
      expect(find.text('10/100'), findsNWidgets(2));
    },
  );
```

在檔案最上方 import 區塊（既有 import 清單內，`import 'package:elinkbook/screens/pdf_settings_sheet.dart';` 附近）新增：

```dart
import 'package:elinkbook/screens/reader_settings_sheet.dart';
```

- [x] **Step 2：執行新測試，確認全數失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Issue 7"`
Expected: FAIL——`reader_foliate_back_button` 等 8 個新 Key 皆找不到（`find.byKey` 回傳 `findsNothing`），因為production code 尚未變更。

- [x] **Step 3：`build()` 新增 streaming EPUB 一律隱藏 `AppBar` 的條件**

把：

```dart
        appBar: (_isFixedLayout || !_chromeVisible)
            ? null // 固定版面（如漫畫）或沉浸模式已收起介面時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

改為：

```dart
        // epic-18-reader-device-qa Issue 7：流式 EPUB（_dispatchedIsFixedLayout
        // == false）一律不建構 AppBar，改用 _buildBody() 內對稱於 FXL 的
        // Positioned 浮動疊加層 chrome（見下方 _buildBody 的新增區塊）——不論
        // _chromeVisible 為何，讓 EpubReaderView（FXL）／FoliateEpubReaderView
        // （流式）兩條渲染路徑最終殊途同歸都是 appBar: null。
        appBar: (_isFixedLayout ||
                !_chromeVisible ||
                (format == BookFormat.epub && _dispatchedIsFixedLayout == false))
            ? null // 固定版面（如漫畫）、沉浸模式已收起介面、或流式 EPUB 時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

- [x] **Step 4：`_buildBody()` 的 `Stack` 新增流式 EPUB 浮動按鈕與頁眉/進度疊加層**

在既有 FXL 浮動筆記按鈕區塊（`Key('reader_fixed_layout_notes_button')` 所在的 `Positioned` 區塊）結束、選取工具列（`if (selection != null) Positioned(...)`）開始之前，插入以下區塊。定位錨點：緊接在

```dart
            if (_isFixedLayout &&
                _chromeVisible &&
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

之後、`if (selection != null)` 之前，插入：

```dart
            // epic-18-reader-device-qa Issue 7：流式 EPUB 的 chrome，結構對稱
            // 於上方 FXL 浮動按鈕區塊——appBar 已在 build() 恆為 null（見上方
            // 註解），改用這組 Positioned 疊加層承載「功能操作」（返回／TOC／
            // 設定／書籤／筆記／進度-跳頁），另有 2 個純顯示元件（頁眉章節
            // 名稱／進度文字）承載「資訊顯示」，兩者刻意分離（design.md「第
            // 二輪真機使用回報」項目 2）。
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_toc_button'),
                      icon: const Icon(Icons.menu_book, color: Colors.white),
                      tooltip: '目錄',
                      onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                          ? null
                          : _openToc,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_settings_button'),
                      icon: const Icon(Icons.settings, color: Colors.white),
                      tooltip: '版面設定',
                      onPressed: _autoDetectedWritingMode == null
                          ? null
                          : _openLayoutSettings,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_bookmark_toggle_button'),
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                      ),
                      tooltip: _bookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleBookmark,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_notes_button'),
                      icon: const Icon(Icons.bookmarks, color: Colors.white),
                      tooltip: '筆記',
                      onPressed: (_autoDetectedWritingMode == null ||
                              _epubPositionInfo == null)
                          ? null
                          : () => _openNotesSheet(BookFormat.epub),
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showFooter ?? true))
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: const Icon(Icons.swap_vert, color: Colors.white),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showHeader ?? true))
              Positioned(
                top: 16,
                left: 72,
                right: 72,
                child: Center(child: _buildFoliateHeaderText()),
              ),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showFooter ?? true) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      left: 16,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFoliateProgressText(),
                      ),
                    )
                  : Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(child: _buildFoliateProgressText()),
                    ),
```

- [x] **Step 5：新增 2 個 helper 方法與 1 個 Bottom Sheet 開啟方法，移除舊 in-flow 頁尾**

在 `_buildFoliateEpubFooter()` 方法定義之前（緊接其上方文件註解之前），新增：

```dart
  /// 流式 EPUB 頁眉（epic-18-reader-device-qa Issue 7）：純顯示章節名稱、
  /// 不可點擊（點擊開 TOC 這個功能已交給獨立的 reader_foliate_toc_button，
  /// 見 design.md「第二輪真機使用回報」項目 2 的「資訊與功能分離」原則）。
  /// 章節名稱推導邏輯與既有 _buildAppBarTitle() 相同，故不重複抽象成共用
  /// 函式——兩者一個要包 InkWell/onTap、一個刻意不包，硬拆共用反而增加
  /// 兩個呼叫端之間不必要的耦合。
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return Container(
      key: const Key('reader_foliate_header_text'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  /// 流式 EPUB 進度純顯示（epic-18-reader-device-qa Issue 7）：內容換算邏輯
  /// 與 _buildFoliateEpubFooter() 相同（pageIndex/totalPages 皆為 0-indexed/
  /// 近似頁碼，+1 換算為人類慣用的 1-indexed），呼叫端已保證
  /// totalPages > 0 才會建構本 widget。跳頁互動已獨立到
  /// reader_foliate_progress_button 開啟的 Bottom Sheet，本 widget 不含任何
  /// 手勢 widget。
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_foliate_progress_text'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$currentPage/$totalPages',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  /// 流式 EPUB「進度/跳頁」浮動按鈕開啟的 Bottom Sheet（epic-18-
  /// reader-device-qa Issue 7）：內容直接沿用既有 _buildFoliateEpubFooter()
  /// 回傳的 ReaderFooter widget 實例（含既有 currentPage/totalPages
  /// 換算與 onPageChanged 跳頁邏輯），只是把承載它的容器從 in-flow Column
  /// 子項改為 Bottom Sheet——ReaderFooter 本身不需要任何修改。
  /// _epubPositionInfo 為 null（onLocatorChanged 尚未觸發過）時顯示空白
  /// Sheet，比照 reader_foliate_progress_button 本身只依 showFooter
  /// gating、不額外等待 _epubPositionInfo 的簡化決策（見 issues.md Issue 7
  /// 「進度/跳頁鈕」段落）。
  void _openFoliateProgressSheet() {
    final positionInfo = _epubPositionInfo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => positionInfo == null
          ? const SizedBox.shrink()
          : _buildFoliateEpubFooter(positionInfo),
    );
  }

```

接著移除舊的 in-flow 流式 EPUB 頁尾呼叫。把（`_buildBody()` 內 `Column` 的最後一個 `if` 子項）：

```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _epubPositionInfo?.totalPages != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildFoliateEpubFooter(_epubPositionInfo!),
          ],
        ),
      ),
    );
  }
```

改為（整個 `if` 子項移除，`Column` 的 `children` 列表提早結束於 PDF／`_buildEpubFooter` 兩個既有分支之後）：

```dart
          ],
        ),
      ),
    );
  }
```

- [x] **Step 6：靜態分析 + 執行 Task 2 新增測試，確認全數通過**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Issue 7"`
Expected: 全數 PASS。

- [x] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-18): 流式 EPUB Chrome 改為浮動疊加層，抑制 AppBar 並分離資訊/功能（Issue 7）"
```

---

### Task 3：既有測試回歸修正（沉浸模式測試改寫 + Key 遷移）

**Files:**
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 產出的 `reader_foliate_back_button`／`reader_foliate_toc_button`／`reader_foliate_progress_text` 等 Key。
- Produces: 無新介面，純測試斷言更新。

Task 2 的變更會讓以下 9 個既有測試失敗，原因分三類：(a) 2 個測試直接斷言流式 EPUB 情境下 `find.byType(AppBar)` 的存在/消失，AppBar 已恆為 `null`，斷言本身失去意義，需改成斷言浮動按鈕的存在/消失；(b) 5 個測試使用了現在只存在於 PDF/FXL-legacy 路徑的 Key（`reader_toc_button`／`reader_footer`），流式 EPUB 情境下這些 Key 已被 Task 2 的新 Key 取代；(c) 2 個測試斷言了 `reader_layout_settings_button`——本 Issue 之前，流式 EPUB 走 AppBar actions 路徑時「⚙️版面設定」按鈕的既有 Key，Task 2 的 AppBar 抑制同樣讓它在流式 EPUB 情境下失效，需改為 `reader_foliate_settings_button`。**審查修正**（見 `reviews/review-issue-7.md` Important #2）：原文只列出 (a)(b) 共 7 個，遺漏了 (c) 這 2 個——實際修正已包含在下方 Step 2-5 與 commit `d088412` 中，此處為事後補正的正確計數，詳細條列見 Step 7 之後的「審查修正記錄」。

先確認斷言修正範圍無遺漏：

- [x] **Step 1：執行完整測試檔，收集 Task 2 造成的既有測試失敗清單**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 除 Task 2 新增的測試外，另外有 9 個既有測試 FAIL（審查修正：原文誤寫為 7 個，見上方段落與 Step 7 之後的「審查修正記錄」），測試名稱應與下方 Step 2/3/「審查修正記錄」列出的 9 個一致（若數量或名稱不同，先 `git diff` 確認 Task 2 是否有超出計畫範圍的意外改動，再繼續）。

- [x] **Step 2：改寫「點擊選單熱區觸發沉浸模式切換」測試（AppBar → 浮動按鈕）**

把：

```dart
  testWidgets('EPUB 流式（isFixedLayout: false）：點擊選單熱區觸發沉浸模式切換', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
    // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
  });
```

改為：

```dart
  testWidgets(
    'EPUB 流式（isFixedLayout: false）：點擊選單熱區觸發沉浸模式切換（Issue 7：AppBar 恆為 null，改斷言浮動按鈕）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsOneWidget,
      );

      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsNothing,
      );
    },
  );
```

- [x] **Step 3：改寫「previousPage/nextPage 熱區不影響沉浸模式狀態」測試**

把：

```dart
  testWidgets('EPUB 流式：previousPage/nextPage 熱區觸發 FoliateEpubReaderView '
      '換頁，且不影響沉浸模式狀態（design.md 決策 #14）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // rightFlip 模板：index 2（右欄）＝ nextPage。
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget, reason: '換頁動作不應影響沉浸模式狀態');

    // rightFlip 模板：index 0（左欄）＝ previousPage。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(
      find.byType(AppBar),
      findsOneWidget,
      reason: 'previousPage 同樣不應影響沉浸模式狀態',
    );
  });
```

改為：

```dart
  testWidgets('EPUB 流式：previousPage/nextPage 熱區觸發 FoliateEpubReaderView '
      '換頁，且不影響沉浸模式狀態（design.md 決策 #14；Issue 7 改斷言浮動按鈕）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_back_button')), findsOneWidget);

    // rightFlip 模板：index 2（右欄）＝ nextPage。
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
      reason: '換頁動作不應影響沉浸模式狀態',
    );

    // rightFlip 模板：index 0（左欄）＝ previousPage。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
      reason: 'previousPage 同樣不應影響沉浸模式狀態',
    );
  });
```

- [x] **Step 4：TOC 按鈕 Key 遷移（2 處）**

在測試「流式 EPUB（isFixedLayout: false）收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet」內，把：

```dart
      final finder = find.byKey(const Key('reader_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：點選目錄項目呼叫 FoliateEpubReaderView.jumpToLocator（非 EpubReaderView）',
```

改為：

```dart
      final finder = find.byKey(const Key('reader_foliate_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：點選目錄項目呼叫 FoliateEpubReaderView.jumpToLocator（非 EpubReaderView）',
```

在緊接的下一個測試「流式 EPUB：點選目錄項目呼叫 FoliateEpubReaderView.jumpToLocator」內，把：

```dart
      await tester.tap(find.byKey(const Key('reader_toc_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TocBottomSheet), findsOneWidget);
```

改為：

```dart
      await tester.tap(find.byKey(const Key('reader_foliate_toc_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TocBottomSheet), findsOneWidget);
```

- [x] **Step 5：頁尾 Key 遷移（3 個測試）——`reader_footer` → `reader_foliate_progress_text`**

在測試「流式 EPUB：onLocatorChanged 回報 pageIndex/totalPages 後，頁尾顯示對應頁碼」內，把：

```dart
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('10/100'), findsOneWidget);
  });
```

改為：

```dart
    expect(find.byKey(const Key('reader_foliate_progress_text')), findsOneWidget);
    expect(find.text('10/100'), findsOneWidget);
  });
```

在測試「流式 EPUB：onLocatorChanged 未觸發前（pageIndex/totalPages 皆為 null），頁尾不顯示」內，把：

```dart
      foliateView.onPageRendered();
      await tester.pump();

      expect(find.byKey(const Key('reader_footer')), findsNothing);
    },
  );
```

改為：

```dart
      foliateView.onPageRendered();
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsNothing,
      );
    },
  );
```

在測試「流式 EPUB：onLocatorChanged 回報 totalPages=0 時，頁尾不顯示且不崩潰」內，把：

```dart
    // totalPages=0 應被 _buildFoliateEpubFooter 內部防呆攔截
    // （info.totalPages ?? 0 → 0 <= 0 → return SizedBox.shrink），
    // 不會走到 clamp(1, 0) 也不會建構 ReaderFooter。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });
```

改為：

```dart
    // totalPages=0 應被 Issue 7 新增的疊加層條件
    // （(_epubPositionInfo?.totalPages ?? 0) > 0）攔截，不會建構
    // _buildFoliateProgressText()。
    expect(
      find.byKey(const Key('reader_foliate_progress_text')),
      findsNothing,
    );
  });
```

- [x] **Step 6：靜態分析 + 執行完整測試檔，確認全數通過且無回歸**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS（Task 2 新增 10 項 + Task 3 修正 9 項既有測試 = 全專案總數較 Issue 10 完成時的 634 項增加 10 項，無 FAIL）。

- [x] **Step 7：Commit**

```bash
git add app/test/screens/reader_screen_test.dart
git commit -m "test(epic-18): 修正 Issue 7 導致失效的既有沉浸模式/目錄/頁尾測試"
```

#### 審查修正記錄（`reviews/review-issue-7.md` Important #2，實作已於 commit `d088412` 內完成，僅補上此處遺漏的文件記錄）

除 Step 2-5 列出的 7 個既有測試外，`d088412` 這個 commit 額外正確修正了以下 2 個既有測試（原計畫撰寫階段漏算，程式碼修正本身沒有問題）：

- 「流式 EPUB（isFixedLayout: false）開書後，onLayoutResolved 回報結果驅動「版面設定」按鈕從停用轉為可用」
- 「流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView」

兩者原本斷言 `find.byKey(const Key('reader_layout_settings_button'))`——該 Key 在本 Issue之前是流式 EPUB 走 AppBar actions 路徑時「⚙️版面設定」按鈕的既有 Key，因 Task 2 的 AppBar 抑制而永久消失，正確修正為 `find.byKey(const Key('reader_foliate_settings_button'))`（`reader_screen_test.dart` 第 178、242 行附近，`git show d088412` 的兩個 hunk）。

---

### Task 4：真機驗收（非自動化，人工執行）

**Files:** 無程式碼變更，本 Task 為驗收 checklist。

- [x] **Step 1：安裝最新 debug build 到既有測試裝置**

Run: `cd app && flutter build apk --debug && adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk`

- [x] **Step 2：開啟一本流式 EPUB，確認 6 顆浮動按鈕存在、行為與重構前一致**

依序點擊返回、TOC、版面設定、書籤 toggle、筆記、進度/跳頁 6 顆浮動按鈕，確認皆可點擊且行為正確（返回離開閱讀器、TOC 開目錄、版面設定開 `ReaderSettingsSheet`、書籤 toggle 圖示切換、筆記開 `NotesBottomSheet`、進度/跳頁開含 `ReaderFooter` 的 Bottom Sheet 且可正確跳頁）。

- [x] **Step 3：確認頁眉/進度為純資訊、點擊無反應**

點擊頁眉章節名稱文字與進度文字，確認畫面無任何反應（不開啟 TOC、不開啟跳頁 Bottom Sheet）。

- [x] **Step 4：切換沉浸模式，確認 6 顆按鈕＋頁眉＋進度一起顯示/收合**

點擊畫面中央熱區（沉浸模式切換），確認全部 8 個浮動元件（6 按鈕＋頁眉＋進度文字）同步顯示/收合，無任何元件不同步。

- [x] **Step 5：切換「顯示頁眉」／「顯示進度」開關，確認對應元件正確顯示/隱藏且不觸發整本重新分頁**

在版面設定內切換「顯示頁眉」「顯示進度」兩個開關，確認：(a) 對應浮動元件正確顯示/隱藏；(b) 肉眼觀察翻頁動畫/目前捲動位置未被打斷（即既有「頁尾顯示/隱藏觸發 WebView 整本重新分頁」問題已解決）。

- [x] **Step 6：直排模式下確認進度顯示位置與格式**

切換為直排模式，確認進度資訊以旋轉文字顯示於左下角，格式為「168/197」這類阿拉伯數字格式（參考 `tmp/image/reading_process.jpg`）。

- [x] **Step 7：FXL 與 PDF 既有行為回歸確認**

分別開啟一本 FXL EPUB 與一本 PDF，確認既有懸浮按鈕（FXL）與 AppBar（PDF）行為完全不受本次變更影響。

- [x] **Step 8：更新 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 7 狀態**

真機驗收全數通過後，把 Issue 7 的 `**Status:**` 從 `ready-for-agent` 更新為完成狀態，並記錄本次 Task 1-3 的 commit hash，比照本文件其餘 Issue 的既有記錄格式。
