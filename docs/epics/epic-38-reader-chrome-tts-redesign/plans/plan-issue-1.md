# Epic 38 Issue 1：ReaderChromeBar 統一＋沉浸模式雙觸發＋死碼清除 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `ReaderChromeTopBar`（56dp，永遠顯示）與 `ReaderChromeBottomBar`（三列，受 `_chromeVisible` 控制）兩個格式無關的共用 widget，取代流式 EPUB／FXL 共用的 7 顆與 PDF 獨立的 6 顆 `Positioned` 浮動圓鈕，以及已死亡的 `Scaffold.appBar`／`_buildAppBarTitle()`／`_buildAppBarActions()`，並把 `_chromeVisible` 的作用範圍收斂為「只控制底部區塊」。

**Architecture：** 兩個新 widget 皆為純 `StatelessWidget`（格式無關、不持有 `TtsController`/repository 等狀態，比照本專案既有 `TtsMiniPlayer`／`PagingBar` 的既定慣例），由 `ReaderScreen` 依 `format` 算好所有具名參數後餵入。`ReaderChromeTopBar` 插入 `_buildBody()` 的 `Stack` 時**不受 `_chromeVisible` 閘控**（只受 `!_cropEditModeActive` 閘控，PDF 裁切編輯模式進行中仍需隱藏全部 Chrome）；`ReaderChromeBottomBar` 受 `_chromeVisible` 閘控，並在 Issue 1 這個過渡期額外加上 `!_ttsMiniPlayerVisible` 的互斥條件（詳見「計劃範圍澄清」第 2 點），避免與舊 `TtsMiniPlayer` 膠囊同時貼底顯示。本 Issue **不觸碰 TTS 系統內部**——底部選單列的「◗ 朗讀」圖示只是把既有 `reader_foliate_tts_toggle_button` 的開關動作換個位置承載，Issue 2 才會把整個 TTS 顯示邏輯換成 `TtsPanel`。

**Tech Stack：** Flutter 3.41.9、既有 `flutter_test` widget test 慣例（`pumpWidget(MaterialApp(home: X(...)))` + `Key` 斷言）。`reader_screen_test.dart` 現有 8966 行、對舊按鈕 Key 的斷言數量龐大（見 Task 4／5 的遷移清單），本計劃對這類「同一種轉換規則、套用在數十個既有測試案例」的遷移工作，採用「規則＋完整範例＋grep 驗證」的方式交代，不逐一內嵌每個既有測試案例的完整程式碼（那會讓本文件膨脹到不可維護，且每個案例的轉換規則完全相同）。

**Spec：** `docs/epics/epic-38-reader-chrome-tts-redesign/spec.md` §功能①②、`docs/epics/epic-38-reader-chrome-tts-redesign/issues.md` Issue 1

## Global Constraints

- 本 Epic 僅合併 Chrome（按鈕列）這一層；`PdfReaderView`／`FoliateReaderView` 底層渲染路徑不合併，`CLAUDE.md` 已有明文架構限制。
- `ReaderChromeTopBar`／`ReaderChromeBottomBar` 皆為純 `StatelessWidget`，不持有任何 `TtsController`／repository 參照，所有互動一律透過建構參數（`bool`／`String`／`VoidCallback?`）注入。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔；全套 `flutter test`（不帶路徑）留到 Task 5（本計劃最後一個 Task）收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）——本 Issue 會刪除多個方法／欄位，任何殘留的孤兒 import／未使用私有成員都必須一併清除。
- 任何 Task 的收尾 Commit 前，該 Task 實際觸及的測試檔必須 100% PASS，不得把已知失敗留到下一個 Task 才修。

## 計劃範圍澄清（撰寫本計劃時發現並解決的落差）

1. **`_buildAppBarActions()`／`Scaffold.appBar` 在「未提供 `libraryRepository`」的測試情境下並非真的無法觸及**——`_resolveEpubEngineDispatch()`（`reader_screen.dart:468-541`）明文記載：EPUB 格式若 `widget.isFixedLayout == null` 且 `widget.libraryRepository == null`（本檔案內大量既有測試的既定寫法，只傳 `filePath`/`bookId`/`prefsManager`），`_dispatchedIsFixedLayout` 會**同步且永久**被設為 `true`（`:527-533`，明文註解「既有測試/呼叫端未提供 libraryRepository 時，退回...既有行為」）。`Scaffold.appBar` 的隱藏條件要求 `_dispatchedIsFixedLayout == false` 才會對 Foliate 格式判定為「隱藏」，`true` 不滿足這個條件；測試接著呼叫 `epubView.onLayoutResolved?.call(EpubLayoutInfo(isFixedLayout: false, ...))` 只會設定另一個欄位 `_isFixedLayout`（`_handleFoliateLayoutResolved`，`:1498-1514`），不會動到 `_dispatchedIsFixedLayout`。兩個欄位皆為 `false`／`true` 而非 `true`／`_`，四個 OR 條件全部為 `false`，`AppBar(...)` 因此**真的在這類既有測試裡渲染出來**，這正是為什麼 `reader_toc_button`／`reader_layout_settings_button`／`reader_notes_button`／`reader_appbar_chapter_title` 等 Key 目前在 `reader_screen_test.dart` 裡各有 6～8 處非零的斷言且會通過。**這在正式產品環境中確實是死碼**（`library_screen.dart:387-388` 同時提供 `isFixedLayout: book.isFixedLayout`＋`libraryRepository: widget.repository`，真實書籍幾乎不會落入這個回退分支），但在測試環境下是被明文設計成「刻意觸發」的回退路徑。Task 4 因此要把這批測試**遷移**到新的 `reader_chrome_*` Key（驗證「點目錄開 TocBottomSheet」這件事本身，本 Issue 之後也還是真的），而不是當作「反正是死碼、刪掉測試就好」直接砍掉。
2. **`ReaderChromeTopBar` 需要 `!_cropEditModeActive` 閘控**——舊的 PDF 返回/目錄 FAB 皆有 `!_cropEditModeActive` 條件（裁切編輯全螢幕疊層進行中隱藏所有 Chrome）；`spec.md` 原文「頂部列永遠顯示」沒有考慮這個 PDF 專屬狀態。`_cropEditModeActive` 對 Foliate 格式恆為 `false`（只有 PDF 裁切互動會設為 `true`），故 `if (!_cropEditModeActive) ReaderChromeTopBar(...)` 可以套用在所有格式而不影響 Foliate 既有行為。
3. **`ReaderChromeBottomBar` 的跳頁列改接收已建好的 `Widget footer`，不接收 `currentPage`/`totalPages`/`onPageChanged` 原始值**——`spec.md`／`issues.md` 原文把這三個原始值列為個別建構參數，但實際上流式 EPUB 既有 `_buildFoliateEpubFooter(EpubPositionInfo info)`（`reader_screen.dart:2702-2717`）已經完整處理了「`totalPages<=0` 時不渲染」「`displayPageIndex`/`displayTotalPages` 換算 1-indexed」的邏輯，PDF 也有對應的既有內嵌寫法（`_openPdfProgressSheet`，`reader_screen.dart:2675-2691`）。若照原文拆成三個原始參數，等於要在 `ReaderChromeBottomBar` 內部重新實作一次同樣的換算與空狀態判斷，造成兩份重複邏輯。改為 `final Widget footer;`（呼叫端直接把 `_buildFoliateEpubFooter(info)` 或等價的 PDF `ReaderFooter(...)` 建好傳入，`_epubPositionInfo`/`_pdfPageInfo` 為 `null` 時傳 `const SizedBox.shrink()`），`ReaderChromeBottomBar` 本身只負責把它放進固定 56dp 高的容器裡。
4. **選單列 4 顆圖示的「停用」與「不渲染」語意分成兩種，且圖示恆定 4 個位置**：⚑書籤／✎劃線筆記／Aa版面 三顆改為**永遠渲染**、`onXxxTap` 為 `null` 時顯示為停用狀態（灰階不可點）——涵蓋舊碼原本「`bookmarksRepository` 缺席」（舊碼整個 icon 不渲染）與「`_epubPositionInfo`/`_autoDetectedWritingMode` 尚未就緒」（舊碼 icon 存在但 `onPressed: null`）兩種情境，統一收斂成「停用」，讓選單列版面在任何情況下都是固定 3～4 個等寬格子、不會因為某個 repository 缺席而讓其餘圖示變寬變窄（比照 `prototype` 固定四等分版面）。◗朗讀維持**`onTtsTap == null` 時整格不渲染**——這是 PDF 目前結構性完全沒有 TTS 底層能力（非暫時未就緒、非可選 repository 缺席），比照既有 PDF FAB 群組本來就不含朗讀按鈕的既有事實，讓格數在 PDF 上就是 3 格、Foliate 上是 4 格。

---

## Task 1：`NotesBottomSheet.initialTabIndex`

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Produces：`NotesBottomSheet` 新增具名建構參數 `final int initialTabIndex;`（預設 `0`）。

- [ ] **Step 1: 確認既有測試檔的 `_pumpSheet` helper 簽章**

Run: `grep -n "_pumpSheet\|notes_sheet_tab_annotations\|notes_sheet_annotations_placeholder" app/test/screens/notes_bottom_sheet_test.dart | head -10`
Expected: 找到 `Future<void> _pumpSheet(WidgetTester tester, {required FakeBookmarksRepository repository, ...})` 既有 helper（`notes_bottom_sheet_test.dart:22-57`），以及分頁籤 Key `notes_sheet_tab_bookmarks`／`notes_sheet_tab_annotations`、空狀態 Key `notes_sheet_annotations_placeholder`（`:64-82`）。本 Task 直接沿用這個既有 helper，不新建重複的 `pumpWidget` 呼叫。

- [ ] **Step 2: 寫失敗測試**

`_pumpSheet` 目前沒有 `initialTabIndex` 參數，Step 4 會補上；先在 `app/test/screens/notes_bottom_sheet_test.dart` 現有 `main()` 內（緊接在既有「切至『劃線與備註』分頁顯示空狀態佔位符」測試之後）新增：

```dart
  testWidgets('initialTabIndex: 1 時，開啟後預設停在「劃線與備註」分頁', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository, initialTabIndex: 1);

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('不傳 initialTabIndex 時，維持既有預設分頁 0（書籤）', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsNothing,
    );
    expect(find.byKey(const Key('notes_sheet_bookmark_list')), findsOneWidget);
  });
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`_pumpSheet` 沒有 `initialTabIndex` 具名參數，編譯錯誤）

- [ ] **Step 4: 補上 `_pumpSheet` 的 `initialTabIndex` 轉發**

編輯 `app/test/screens/notes_bottom_sheet_test.dart` 的 `_pumpSheet` helper：

Before：
```dart
Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  String bookTitle = '測試書籍',
  String? bookAuthor,
  double bookProgress = 0.0,
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
  FakeHighlightsRepository? highlightsRepository,
  FakeNotesRepository? notesRepository,
  ValueChanged<AnnotationListItem>? onAnnotationSelected,
  VoidCallback? onAnnotationsChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: Scaffold(
        body: NotesBottomSheet(
          bookId: bookId,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          bookProgress: bookProgress,
          bookmarksRepository: repository,
          currentPosition: currentPosition,
          onBookmarkSelected: onBookmarkSelected ?? (_) {},
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
          onAnnotationSelected: onAnnotationSelected,
          onAnnotationsChanged: onAnnotationsChanged,
        ),
      ),
    ),
  );
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}
```

After：
```dart
Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  String bookTitle = '測試書籍',
  String? bookAuthor,
  double bookProgress = 0.0,
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
  FakeHighlightsRepository? highlightsRepository,
  FakeNotesRepository? notesRepository,
  ValueChanged<AnnotationListItem>? onAnnotationSelected,
  VoidCallback? onAnnotationsChanged,
  int initialTabIndex = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: Scaffold(
        body: NotesBottomSheet(
          bookId: bookId,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          bookProgress: bookProgress,
          bookmarksRepository: repository,
          currentPosition: currentPosition,
          onBookmarkSelected: onBookmarkSelected ?? (_) {},
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
          onAnnotationSelected: onAnnotationSelected,
          onAnnotationsChanged: onAnnotationsChanged,
          initialTabIndex: initialTabIndex,
        ),
      ),
    ),
  );
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}
```

- [ ] **Step 5: 執行測試確認仍然失敗（`_pumpSheet` 已接受 `initialTabIndex`，但 `NotesBottomSheet` 本身還沒有這個參數）**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`NotesBottomSheet` 沒有 `initialTabIndex` 具名參數，編譯錯誤）

- [ ] **Step 6: 實作**

編輯 `app/lib/screens/notes_bottom_sheet.dart`：

Before（`class NotesBottomSheet` 建構參數與建構子）：
```dart
  final VoidCallback? onAnnotationsChanged;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    required this.bookProgress,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
    this.highlightsRepository,
    this.notesRepository,
    this.onAnnotationSelected,
    this.onAnnotationsChanged,
  });
```

After：
```dart
  final VoidCallback? onAnnotationsChanged;

  /// 開啟後預設停在哪個分頁（0＝🔖書籤、1＝✏️劃線與備註）。
  /// `epic-38-reader-chrome-tts-redesign` Issue 1：底部「✎ 劃線筆記」按鈕
  /// 傳入 `1`，預設停在劃線分頁；既有呼叫端不傳則維持既有分頁 0。
  final int initialTabIndex;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    required this.bookProgress,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
    this.highlightsRepository,
    this.notesRepository,
    this.onAnnotationSelected,
    this.onAnnotationsChanged,
    this.initialTabIndex = 0,
  });
```

Before（`initState()`）：
```dart
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookmarks();
    _loadAnnotations();
  }
```

After：
```dart
  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadBookmarks();
    _loadAnnotations();
  }
```

- [ ] **Step 7: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（全部案例，含既有測試與本次新增兩則）

- [ ] **Step 8: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-38): NotesBottomSheet 新增 initialTabIndex 支援預設停在指定分頁" -m "TabController 原生支援 initialIndex 參數，供 Issue 1 的統一底部選單列「劃線筆記」按鈕使用（預設停在劃線與備註分頁）。既有呼叫端不受影響。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VFdTEkegztPHy1dq9fwY1j"
```

---

## Task 2：`ReaderChromeTopBar`（新 widget＋widget test）

**Files:**
- Create: `app/lib/screens/reader_chrome_top_bar.dart`
- Test: `app/test/screens/reader_chrome_top_bar_test.dart`

**Interfaces:**
- Produces：
  ```dart
  class ReaderChromeTopBar extends StatelessWidget {
    final VoidCallback onBack;
    final String chapterTitle;
    final VoidCallback onSearchTap;
    final bool isBottomChromeVisible;
    final VoidCallback onToggleBottomChrome;
    final VoidCallback? onTocTap;
    final bool showTtsIndicator;
    final Color backgroundColor;
    final Color iconColor;
    final bool isEinkMode; // 預設 false
  }
  ```
  Key：`reader_chrome_back_button`／`reader_chrome_title`／`reader_chrome_search_button`／`reader_chrome_immersive_toggle_button`／`reader_chrome_toc_button`／`reader_chrome_tts_indicator_icon`（`showTtsIndicator == false` 時不存在於 widget 樹）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/reader_chrome_top_bar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_top_bar.dart';

void main() {
  Widget buildTopBar({
    VoidCallback? onBack,
    String chapterTitle = '第七章',
    VoidCallback? onSearchTap,
    bool isBottomChromeVisible = true,
    VoidCallback? onToggleBottomChrome,
    VoidCallback? onTocTap,
    bool showTtsIndicator = false,
    bool isEinkMode = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderChromeTopBar(
          onBack: onBack ?? () {},
          chapterTitle: chapterTitle,
          onSearchTap: onSearchTap ?? () {},
          isBottomChromeVisible: isBottomChromeVisible,
          onToggleBottomChrome: onToggleBottomChrome ?? () {},
          onTocTap: onTocTap,
          showTtsIndicator: showTtsIndicator,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  testWidgets('顯示章節標題文字', (tester) async {
    await tester.pumpWidget(buildTopBar(chapterTitle: '第七章 · 弦外之音'));
    expect(find.text('第七章 · 弦外之音'), findsOneWidget);
  });

  testWidgets('點擊返回按鈕觸發 onBack', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onBack: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_back_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊搜尋按鈕觸發 onSearchTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onSearchTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊 ⬓ 按鈕觸發 onToggleBottomChrome', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildTopBar(onToggleBottomChrome: () => called = true),
    );
    await tester.tap(
      find.byKey(const Key('reader_chrome_immersive_toggle_button')),
    );
    expect(called, isTrue);
  });

  testWidgets('onTocTap 為 null 時，目錄按鈕為停用狀態', (tester) async {
    await tester.pumpWidget(buildTopBar(onTocTap: null));
    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_toc_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('onTocTap 非 null 時，點擊目錄按鈕觸發它', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onTocTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    expect(called, isTrue);
  });

  testWidgets('showTtsIndicator: false 時，小喇叭圖示不存在', (tester) async {
    await tester.pumpWidget(buildTopBar(showTtsIndicator: false));
    expect(
      find.byKey(const Key('reader_chrome_tts_indicator_icon')),
      findsNothing,
    );
  });

  testWidgets('showTtsIndicator: true 時，小喇叭圖示存在', (tester) async {
    await tester.pumpWidget(buildTopBar(showTtsIndicator: true));
    expect(
      find.byKey(const Key('reader_chrome_tts_indicator_icon')),
      findsOneWidget,
    );
  });

  testWidgets('isEinkMode: true 時，觸控目標實際渲染尺寸為 56dp', (tester) async {
    await tester.pumpWidget(buildTopBar(isEinkMode: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_back_button')),
    );
    expect(size.width, greaterThanOrEqualTo(56));
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，觸控目標為一般 48dp', (tester) async {
    await tester.pumpWidget(buildTopBar(isEinkMode: false));
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_back_button')),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.width, lessThan(56));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_chrome_top_bar_test.dart`
Expected: FAIL（`reader_chrome_top_bar.dart` 不存在，import 錯誤）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/reader_chrome_top_bar.dart`：

```dart
import 'package:flutter/material.dart';

/// 閱讀器頂部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1，
/// spec.md §功能①）：格式無關，取代流式 EPUB／FXL／PDF 三格式各自獨立的
/// 頂部按鈕（返回／目錄）與已死亡的 `Scaffold.appBar`／`_buildAppBarActions()`。
///
/// **在閱讀畫面內永遠渲染，只受 PDF 裁切編輯模式（`!_cropEditModeActive`，
/// 呼叫端閘控，本 widget 不知道這個狀態）影響，不受 `_chromeVisible`
/// 影響**（查證 `prototype/eink_redesign_prototype.html:909-926` 確認頂部
/// 列從未被 `toggleReaderChrome()` 收合過，見 `spec.md`「已解決的規格矛盾
/// （新增）」第 2 項）——這樣使用者收起底部工具列後，仍能透過 ⬓ 按鈕本身
/// 把底部叫回來，不需要精確點中畫面正中央熱區。
///
/// [chapterTitle] 由呼叫端算好完整文字（含找不到章節時的「閱讀器」回退
/// 值）；[onTocTap] 為 `null` 時目錄按鈕顯示為停用狀態（呼叫端既有的
/// `_tocLoaded`／`_pdfTocLoaded` 防呆條件）；[showTtsIndicator] 為 `true`
/// 時在標題右側顯示一個小喇叭圖示（本 Issue 固定傳 `false`，真實邏輯留給
/// Issue 2 的 `TtsPanel` 重構）。
class ReaderChromeTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final String chapterTitle;
  final VoidCallback onSearchTap;
  final bool isBottomChromeVisible;
  final VoidCallback onToggleBottomChrome;
  final VoidCallback? onTocTap;
  final bool showTtsIndicator;
  final Color backgroundColor;
  final Color iconColor;
  final bool isEinkMode;

  const ReaderChromeTopBar({
    super.key,
    required this.onBack,
    required this.chapterTitle,
    required this.onSearchTap,
    required this.isBottomChromeVisible,
    required this.onToggleBottomChrome,
    required this.onTocTap,
    required this.showTtsIndicator,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    // DESIGN.md §7.2：一般模式最小觸控目標 48dp、E-Ink 模式 56dp。
    final minSize = isEinkMode ? 56.0 : 48.0;
    final buttonStyle =
        IconButton.styleFrom(minimumSize: Size(minSize, minSize));
    return Material(
      color: backgroundColor,
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            IconButton(
              key: const Key('reader_chrome_back_button'),
              icon: Icon(Icons.arrow_back, color: iconColor),
              tooltip: '返回',
              style: buttonStyle,
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                key: const Key('reader_chrome_title'),
                chapterTitle,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(color: iconColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (showTtsIndicator)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.volume_up,
                  key: const Key('reader_chrome_tts_indicator_icon'),
                  color: iconColor,
                ),
              ),
            IconButton(
              key: const Key('reader_chrome_search_button'),
              icon: Icon(Icons.search, color: iconColor),
              tooltip: '搜尋內文',
              style: buttonStyle,
              onPressed: onSearchTap,
            ),
            IconButton(
              key: const Key('reader_chrome_immersive_toggle_button'),
              icon: Icon(
                isBottomChromeVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: iconColor,
              ),
              tooltip: isBottomChromeVisible ? '隱藏工具列' : '顯示工具列',
              style: buttonStyle,
              onPressed: onToggleBottomChrome,
            ),
            IconButton(
              key: const Key('reader_chrome_toc_button'),
              icon: Icon(Icons.menu_book, color: iconColor),
              tooltip: '目錄',
              style: buttonStyle,
              onPressed: onTocTap,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_chrome_top_bar_test.dart`
Expected: PASS（全部 10 則案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_chrome_top_bar.dart app/test/screens/reader_chrome_top_bar_test.dart
git commit -m "feat(epic-38): 新增 ReaderChromeTopBar 統一頂部 Chrome 列元件" -m "格式無關的頂部列（返回/標題/搜尋/沉浸模式切換/目錄），永遠渲染不受 _chromeVisible 影響。尚未接入 reader_screen.dart（下個 Task 處理）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VFdTEkegztPHy1dq9fwY1j"
```

---

## Task 3：`ReaderChromeBottomBar`（新 widget＋widget test）

**Files:**
- Create: `app/lib/screens/reader_chrome_bottom_bar.dart`
- Test: `app/test/screens/reader_chrome_bottom_bar_test.dart`

**Interfaces:**
- Consumes：無（不依賴 Task 2 的 `ReaderChromeTopBar`，兩者互相獨立）。
- Produces：
  ```dart
  class ReaderChromeBottomBar extends StatelessWidget {
    final String bookTitle;
    final String pageProgressText; // 例如「184 / 468 · 39%」，空字串代表尚無位置資訊
    final Widget footer; // 呼叫端已建好的跳頁列內容（通常是 ReaderFooter 或 SizedBox.shrink()）
    final bool isBookmarked;
    final VoidCallback? onBookmarkTap; // null＝停用（不論原因是 repository 缺席或尚未就緒）
    final VoidCallback? onAnnotationsTap;
    final VoidCallback? onLayoutTap;
    final VoidCallback? onTtsTap; // null＝整格不渲染（格式結構性不支援 TTS）
    final Color backgroundColor;
    final Color iconColor;
    final bool isEinkMode; // 預設 false
  }
  ```
  Key：`reader_chrome_page_info_text`（頁碼列文字）／`reader_chrome_bookmark_button`／`reader_chrome_annotations_button`／`reader_chrome_layout_button`／`reader_chrome_tts_button`（`onTtsTap == null` 時 `findsNothing`）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/reader_chrome_bottom_bar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_bottom_bar.dart';

void main() {
  Widget buildBottomBar({
    String bookTitle = '一弦定音',
    String pageProgressText = '184 / 468 · 39%',
    Widget? footer,
    bool isBookmarked = false,
    VoidCallback? onBookmarkTap,
    VoidCallback? onAnnotationsTap,
    VoidCallback? onLayoutTap,
    VoidCallback? onTtsTap,
    bool isEinkMode = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderChromeBottomBar(
          bookTitle: bookTitle,
          pageProgressText: pageProgressText,
          footer: footer ?? const SizedBox.shrink(),
          isBookmarked: isBookmarked,
          onBookmarkTap: onBookmarkTap,
          onAnnotationsTap: onAnnotationsTap,
          onLayoutTap: onLayoutTap,
          onTtsTap: onTtsTap,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  testWidgets('顯示書名與頁碼進度文字', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(bookTitle: '一弦定音', pageProgressText: '184 / 468 · 39%'),
    );
    expect(find.text('一弦定音'), findsOneWidget);
    expect(find.text('184 / 468 · 39%'), findsOneWidget);
  });

  testWidgets('顯示呼叫端傳入的 footer widget', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(footer: const Text('假跳頁列內容')),
    );
    expect(find.text('假跳頁列內容'), findsOneWidget);
  });

  testWidgets('onBookmarkTap 為 null 時，書籤按鈕為停用狀態（仍渲染）', (tester) async {
    await tester.pumpWidget(buildBottomBar(onBookmarkTap: null));
    expect(find.byKey(const Key('reader_chrome_bookmark_button')), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_bookmark_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('點擊書籤按鈕觸發 onBookmarkTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onBookmarkTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_bookmark_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊劃線筆記按鈕觸發 onAnnotationsTap', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildBottomBar(onAnnotationsTap: () => called = true),
    );
    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊版面按鈕觸發 onLayoutTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onLayoutTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    expect(called, isTrue);
  });

  testWidgets('onTtsTap 為 null 時，朗讀按鈕整項不渲染', (tester) async {
    await tester.pumpWidget(buildBottomBar(onTtsTap: null));
    expect(find.byKey(const Key('reader_chrome_tts_button')), findsNothing);
  });

  testWidgets('onTtsTap 非 null 時，點擊朗讀按鈕觸發它', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onTtsTap: () => called = true));
    expect(find.byKey(const Key('reader_chrome_tts_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
    expect(called, isTrue);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_chrome_bottom_bar_test.dart`
Expected: FAIL（`reader_chrome_bottom_bar.dart` 不存在，import 錯誤）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/reader_chrome_bottom_bar.dart`：

```dart
import 'package:flutter/material.dart';

/// 閱讀器底部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1，
/// spec.md §功能①②）：格式無關，三列固定結構——頁碼列（34dp，純顯示書名
/// ＋頁數/百分比）／跳頁列（56dp，內容由呼叫端建好傳入，見 [footer]）／
/// 選單列（64dp，書籤/劃線筆記/版面 3 顆恆常渲染、`onXxxTap` 為 `null`
/// 時顯示停用狀態；朗讀 1 顆 `onTtsTap` 為 `null` 時整格不渲染，因為 PDF
/// 目前結構性沒有 TTS 底層能力）。取代流式 EPUB／FXL 共用的 5 顆與 PDF
/// 獨立的 4 顆 `Positioned` 浮動圓鈕。
///
/// [footer] 由呼叫端已經算好（例如既有 `_buildFoliateEpubFooter()`
/// 回傳的 `ReaderFooter`，或 PDF 對應的等價寫法；尚無位置資訊時傳
/// `const SizedBox.shrink()`）——本 widget 不重新實作頁碼換算與空狀態
/// 判斷，避免與既有邏輯重複（見 `plans/plan-issue-1.md`「計劃範圍澄清」
/// 第 3 點）。
class ReaderChromeBottomBar extends StatelessWidget {
  final String bookTitle;
  final String pageProgressText;
  final Widget footer;
  final bool isBookmarked;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onAnnotationsTap;
  final VoidCallback? onLayoutTap;
  final VoidCallback? onTtsTap;
  final Color backgroundColor;
  final Color iconColor;
  final bool isEinkMode;

  const ReaderChromeBottomBar({
    super.key,
    required this.bookTitle,
    required this.pageProgressText,
    required this.footer,
    required this.isBookmarked,
    required this.onBookmarkTap,
    required this.onAnnotationsTap,
    required this.onLayoutTap,
    required this.onTtsTap,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final minSize = isEinkMode ? 56.0 : 48.0;
    final buttonStyle =
        IconButton.styleFrom(minimumSize: Size(minSize, minSize));
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    bookTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style:
                        TextStyle(color: iconColor, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  pageProgressText,
                  key: const Key('reader_chrome_page_info_text'),
                  style: TextStyle(color: iconColor),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          SizedBox(height: 56, child: footer),
          SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_bookmark_button'),
                    icon: Icon(
                      isBookmarked ? Icons.star : Icons.star_border,
                      color: iconColor,
                    ),
                    tooltip: isBookmarked ? '已加入此頁書籤' : '加入此頁書籤',
                    style: buttonStyle,
                    onPressed: onBookmarkTap,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_annotations_button'),
                    icon: Icon(Icons.edit_note, color: iconColor),
                    tooltip: '劃線筆記',
                    style: buttonStyle,
                    onPressed: onAnnotationsTap,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_layout_button'),
                    icon: Icon(Icons.format_size, color: iconColor),
                    tooltip: '版面',
                    style: buttonStyle,
                    onPressed: onLayoutTap,
                  ),
                ),
                if (onTtsTap != null)
                  Expanded(
                    child: IconButton(
                      key: const Key('reader_chrome_tts_button'),
                      icon: Icon(Icons.record_voice_over, color: iconColor),
                      tooltip: '朗讀',
                      style: buttonStyle,
                      onPressed: onTtsTap,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_chrome_bottom_bar_test.dart`
Expected: PASS（全部 8 則案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_chrome_bottom_bar.dart app/test/screens/reader_chrome_bottom_bar_test.dart
git commit -m "feat(epic-38): 新增 ReaderChromeBottomBar 統一底部 Chrome 列元件" -m "格式無關的底部三列結構（頁碼列/跳頁列/選單列），書籤/劃線筆記/版面恆常渲染並依 onXxxTap 是否為 null 顯示停用狀態，朗讀依 onTtsTap 是否為 null 決定整格渲染與否。尚未接入 reader_screen.dart（下個 Task 處理）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VFdTEkegztPHy1dq9fwY1j"
```

---

## Task 4：`ReaderChromeTopBar` 接線＋死碼清除（`Scaffold.appBar`／`_buildAppBarTitle`／`_buildAppBarActions`）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `ReaderChromeTopBar`。
- Produces：`ReaderScreen` 新增私有方法 `String _currentChapterTitle(BookFormat format)`；`Scaffold.appBar` 恆為 `null`；`_buildAppBarTitle()`／`_buildAppBarActions()`／`_appBarToolbarHeight`／`_appBarButtonMinWidth`／`_appBarIconSize`／`_appBarTitleFontSize` 全數刪除（`_pdfThumbnailMaxWidth` 保留，`_openPdfToc()` 仍在用）。

本 Task 是「新增新程式碼路徑＋刪除舊程式碼路徑」的重構，既有 widget test 本身就是回歸安全網，不走「先寫新失敗測試」的標準 TDD 開頭；改為「先確認要遷移的既有測試清單與其目前狀態 → 實作 → 逐一遷移既有測試 → 確認全綠」。

- [ ] **Step 1: 盤點需要遷移的既有測試（本 Task 完成後其斷言方式必須改變的 Key）**

Run 以下指令逐一確認出現次數（作為遷移完整性的檢查清單，數字為目前狀態，遷移完成後應全部歸零，改為對應的新 Key）：

```bash
cd app
grep -c "reader_appbar_chapter_title\|reader_appbar_static_title" test/screens/reader_screen_test.dart   # 現況 8，遷移目標：reader_chrome_title
grep -c "reader_toc_button\b" test/screens/reader_screen_test.dart                                       # 現況 6，遷移目標：reader_chrome_toc_button
grep -c "reader_layout_settings_button" test/screens/reader_screen_test.dart                             # 現況 7，本 Task 遷移目標：確認測試改為驗證新的 reader_chrome_layout_button（Task 5 才會真正接上，若這批測試同時斷言目錄行為以外的版面設定行為，暫時保留待 Task 5 一併處理，見 Step 4 說明）
grep -c "reader_notes_button" test/screens/reader_screen_test.dart                                       # 現況 6，同上，主要行為屬於 Task 5 範圍
grep -c "reader_foliate_back_button" test/screens/reader_screen_test.dart                                # 現況 23，遷移目標：reader_chrome_back_button
grep -c "reader_pdf_back_button" test/screens/reader_screen_test.dart                                    # 現況 10，遷移目標：reader_chrome_back_button（同一顆共用按鈕）
grep -c "reader_foliate_toc_button" test/screens/reader_screen_test.dart                                 # 現況 3，遷移目標：reader_chrome_toc_button
grep -c "reader_pdf_toc_button" test/screens/reader_screen_test.dart                                     # 現況 0
```

**重要澄清（見上方「計劃範圍澄清」第 1 點）**：`reader_appbar_chapter_title`／`reader_toc_button`／`reader_layout_settings_button`／`reader_notes_button` 這批測試目前會通過，是因為它們建構 `ReaderScreen` 時沒有提供 `libraryRepository`，觸發 `_resolveEpubEngineDispatch()` 的測試回退分支（`_dispatchedIsFixedLayout` 永遠 `true`），讓已死亡的 `Scaffold.appBar` 意外在測試環境下渲染——這不是「刪掉測試就好的死碼測試」，而是「測試對象即將被移除、但驗證的行為本身（返回/點目錄開 TocBottomSheet）仍然需要，須遷移到新 Key」。

- [ ] **Step 2: 實作——`_currentChapterTitle()` 新增與死碼刪除**

編輯 `app/lib/screens/reader_screen.dart`：

**2a. `Scaffold.appBar` 恆為 `null`**

Before（`reader_screen.dart:1899-1922`）：
```dart
      child: Scaffold(
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造（審查修正），讓 body 版面約束不受 AppBar 顯示/隱藏
        // 影響，AppBar 只是視覺疊加、不觸發 body 底下 PlatformView 的
        // 流式 EPUB（FoliateReaderView）的頁尾已改為浮動疊加層，resize
        // 問題對此路徑已解決。
        extendBodyBehindAppBar: true,
        // epic-18-reader-device-qa Issue 7：流式 EPUB（_dispatchedIsFixedLayout
        // == false）一律不建構 AppBar，改用 _buildBody() 內對稱於 FXL 的
        // Positioned 浮動疊加層 chrome（見下方 _buildBody 的新增區塊）——不論
        // _chromeVisible 為何，讓 EpubReaderView（FXL）／FoliateReaderView
        // （流式）兩條渲染路徑最終殊途同歸都是 appBar: null。
        appBar: (_isFixedLayout ||
                !_chromeVisible ||
                format == BookFormat.pdf ||
                (isFoliateFormat(format) && _dispatchedIsFixedLayout == false))
            ? null // 固定版面（如漫畫）、沉浸模式已收起介面、PDF（epic-24 Issue 8 起改用 FAB）、或流式 Foliate 格式時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
```

After：
```dart
      child: Scaffold(
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造，讓 body 版面約束不受頂部 Chrome 疊加影響。
        extendBodyBehindAppBar: true,
        // epic-38-reader-chrome-tts-redesign Issue 1：三格式統一改用
        // ReaderChromeTopBar／ReaderChromeBottomBar 兩個 Positioned 疊加層
        // 承載 Chrome（見 _buildBody），Scaffold.appBar 恆為 null——原本依
        // _isFixedLayout/_chromeVisible/format/_dispatchedIsFixedLayout
        // 四個條件決定要不要建構 AppBar 的邏輯已確認沒有任何組合在正式
        // 產品環境下會實際觸及（見 plans/plan-issue-1.md「計劃範圍澄清」
        // 第 1 點），整段條件式與 AppBar(...) 建構、_buildAppBarTitle()／
        // _buildAppBarActions() 兩個方法一併刪除。
        appBar: null,
        body: _buildBody(format, isLandscape),
      ),
```

**2b. 刪除 `_buildAppBarTitle()`，新增 `_currentChapterTitle()`**

Before（`reader_screen.dart:1926-1957`，緊接在上面 `build()` 方法之後）：
```dart
  /// 頁首顯示切換（epic-5-toc-pagination Issue 5，spec.md「頁首/頁尾顯示
  /// 切換」）：`showHeader == false` 或非 EPUB 格式時維持既有的靜態標題；
  /// `showHeader == true`（含尚未載入完成前的安全預設值，見
  /// `ResolvedPreferences.showHeader`）時改用目前章節名稱，可點擊開啟目錄
  /// （沿用 Issue 4 的 `TocNavigator.findCurrentPath`／`_openToc`）。章節
  /// 名稱在目錄背景抓取完成（`_tocLoaded`）前一律回退顯示「閱讀器」佔位
  /// 文字，`onTap` 同步以 `_tocLoaded` 防呆，比照 `_buildAppBarActions` 的
  /// 目錄按鈕既有 gating 條件，避免點擊到空白 Bottom Sheet。
  Widget _buildAppBarTitle(BookFormat format) {
    final showHeader = isFoliateFormat(format) && (_resolved?.showHeader ?? false);
    if (!showHeader) {
      return const Text(
        '閱讀器',
        key: Key('reader_appbar_static_title'),
        style: TextStyle(fontSize: _appBarTitleFontSize),
      );
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _appBarTitleFontSize),
      ),
    );
  }
```

After：
```dart
  /// 頂部 Chrome 列標題文字（epic-38-reader-chrome-tts-redesign Issue 1，
  /// spec.md §功能①）：取代已刪除的 `_buildAppBarTitle()`。**與舊方法的
  /// 關鍵差異**：不再受 `_resolved.showHeader` 偏好門檻限制、一律顯示章節
  /// 名稱——`showHeader`／`showFooter` 偏好維持原本語意完全不動，只控制
  /// `_chromeVisible == false` 時螢幕邊角是否仍保留常駐頁首/頁尾文字
  /// （`_buildFoliateHeaderText()`／`_buildFoliateProgressText()` 那組邏輯，
  /// 完全不受本次改動影響）。標題本身不可點擊（prototype 的頂部列標題是
  /// 純文字，開目錄一律透過獨立的 ☰ 按鈕，見 `ReaderChromeTopBar`）。
  String _currentChapterTitle(BookFormat format) {
    if (format == BookFormat.pdf) {
      final currentPath =
          PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
      return currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    }
    final currentPath =
        TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);
    return currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
  }
```

**2c. 刪除 4 個 AppBar 專屬常數（保留 `_pdfThumbnailMaxWidth`）**

Before（`reader_screen.dart:1959-1979`）：
```dart
  // AppBar 瘦身（Epic 18 Issue 2，design.md 決策 #2：縮減至約現有高度
  // 1/3）：只設定 toolbarHeight 不夠——IconButton 預設觸控寬度 48dp、
  // 預設圖示 24dp，title 文字預設字級，在 20dp 高的 AppBar 內都會偏擠，
  // 故同步收斂三者。以下數值為起始建議值，真機測試（Task 3）後可再調整
  // （issues.md Issue 2 審查修正）。
  //
  // 【實測發現，記錄供未來維護者知悉】_buildAppBarActions() 的
  // IconButton 一律透過 `style: IconButton.styleFrom(...)` 收斂尺寸，
  // 不使用建構子的 `padding`/`constraints` 參數——Material 3 的
  // IconButton 在本專案 Flutter 版本（3.41.9）下，`padding`/`constraints`
  // 這兩個建構子參數對實際渲染尺寸完全無效（實測仍是 48dp 預設寬度），
  // 必須透過 `style` 才能真正生效。另外，AppBar.actions 內的按鈕實際
  // 渲染高度無論如何設定都會被鎖死在 toolbarHeight（本例為 20），故這裡
  // 只需要一個「最小寬度」常數，不需要（也無法生效）獨立的「最小高度」
  // 常數——`_appBarButtonMinWidth` 只控制寬度，高度直接沿用
  // `_appBarToolbarHeight`。
  static const _appBarToolbarHeight = 20.0;
  static const _appBarButtonMinWidth = 32.0;
  static const _appBarIconSize = 18.0;
  static const _appBarTitleFontSize = 13.0;
  static const double _pdfThumbnailMaxWidth = 120;
```

After：
```dart
  // reader_chrome_top_bar.dart/_openPdfToc() 分別接手了 AppBar 瘦身與縮圖
  // 尺寸兩件事——_appBarToolbarHeight/_appBarButtonMinWidth/_appBarIconSize/
  // _appBarTitleFontSize 四個常數隨 Scaffold.appBar／_buildAppBarActions()／
  // _buildAppBarTitle() 一併刪除（epic-38-reader-chrome-tts-redesign
  // Issue 1）；_pdfThumbnailMaxWidth 仍被 _openPdfToc() 使用，保留。
  static const double _pdfThumbnailMaxWidth = 120;
```

**2d. 刪除 `_buildAppBarActions()` 整段**（`reader_screen.dart:1981-2053`，見本檔案該範圍現有內容，方法簽章 `List<Widget>? _buildAppBarActions(BookFormat format) { ... }` 一直到對應的結尾 `}`——整段刪除，不保留任何片段）。

**2e. 頂部 `Positioned` 統一——刪除 Foliate／PDF 各自的返回/目錄按鈕，插入 `ReaderChromeTopBar`**

Before（`reader_screen.dart:2156-2195`，Foliate 頂部返回/目錄兩顆）：
```dart
            // epic-18-reader-device-qa Issue 7：流式 Foliate 格式的 chrome，結構對稱
            // 於上方 FXL 浮動按鈕區塊——appBar 已在 build() 恆為 null（見上方
            // 註解），改用這組 Positioned 疊加層承載「功能操作」（返回／TOC／
            // 設定／書籤／筆記／進度-跳頁），另有 2 個純顯示元件（頁眉章節
            // 名稱／進度文字）承載「資訊顯示」，兩者刻意分離（design.md「第
            // 二輪真機使用回報」項目 2）。
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                          ? null
                          : _openToc,
                    ),
                  ),
                ),
              ),
```

After（改為單一、格式無關的 `ReaderChromeTopBar` 插入點，`!_cropEditModeActive` 閘控涵蓋 PDF 裁切編輯模式，Foliate 恆為 `true`——見「計劃範圍澄清」第 2 點）：
```dart
            // epic-38-reader-chrome-tts-redesign Issue 1：三格式共用同一份
            // ReaderChromeTopBar，取代原本 Foliate／PDF 各自獨立的返回/目錄
            // Positioned（下方 PDF FAB 區塊對應的返回/目錄兩顆已一併刪除，
            // 見 plans/plan-issue-1.md Task 4 Step 2f）。永遠渲染、不受
            // _chromeVisible 影響，只受 PDF 裁切編輯模式閘控。
            if (!_cropEditModeActive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ReaderChromeTopBar(
                  onBack: () => Navigator.of(context).pop(),
                  chapterTitle: _currentChapterTitle(format),
                  onSearchTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('功能開發中')),
                  ),
                  isBottomChromeVisible: _chromeVisible,
                  onToggleBottomChrome: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                  onTocTap: format == BookFormat.pdf
                      ? (!_pdfTocLoaded ? null : _openPdfToc)
                      : (isFoliateFormat(format)
                          ? ((_autoDetectedWritingMode == null || !_tocLoaded)
                              ? null
                              : _openToc)
                          : null),
                  showTtsIndicator: false, // Issue 2 接上真實邏輯
                  backgroundColor: _themedFabBackgroundColor,
                  iconColor: _themedFabIconColor,
                  isEinkMode: widget.isEinkMode,
                ),
              ),
```

**2f. 刪除 PDF 頂部返回/目錄兩顆**（`reader_screen.dart:2360-2391`，位於「PDF FAB 區塊」註解與 `settings` 按鈕之間，不插入任何替代內容——已由上方 2e 的單一 `ReaderChromeTopBar` 涵蓋）：

Before：
```dart
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: !_pdfTocLoaded ? null : _openPdfToc,
                    ),
                  ),
                ),
              ),
```

After：（整段刪除，不留任何內容——緊接著的 `settings` `Positioned` 區塊維持不動，留給 Task 5 處理）

**2g. 新增 import**

在 `reader_screen.dart` 既有 import 區塊新增：
```dart
import 'reader_chrome_top_bar.dart';
```

- [ ] **Step 3: 遷移既有測試——「舊 AppBar 路徑」測試（`reader_appbar_chapter_title`／`reader_toc_button`）**

依 Step 1 的盤點結果，逐一找到每個引用這兩個 Key 的既有測試案例，改為斷言新的 `reader_chrome_title`／`reader_chrome_toc_button`。**轉換規則**：
1. 原本用來讓舊 `AppBar` 意外渲染的「不提供 `libraryRepository`」寫法不需要改變（`ReaderChromeTopBar` 不看 `_dispatchedIsFixedLayout`，任何情況下都會渲染），但如果測試原本是刻意利用這個回退分支才能讓斷言目標存在，遷移後這個顧慮就不存在了——可以視情況簡化，但**不強制**簡化，維持既有的 `onLayoutResolved` 呼叫序列一樣能通過（`_tocLoaded` 依然要等 `.then()` callback，這個機制不受本次改動影響）。
2. `find.byKey(const Key('reader_toc_button'))` → `find.byKey(const Key('reader_chrome_toc_button'))`。
3. `find.byKey(const Key('reader_appbar_chapter_title'))`／`find.byKey(const Key('reader_appbar_static_title'))` → `find.byKey(const Key('reader_chrome_title'))`（新版不分 `showHeader` 狀態，一律是同一個 `Text`，兩個舊 Key 收斂成一個）。
4. 若測試原本斷言 `InkWell`／`onTap` 相關行為（舊標題可點擊開目錄），該斷言**移除**——新標題是純文字，不可點擊（見 Step 2b 說明），改由測試 `reader_chrome_toc_button` 涵蓋「點目錄開 TocBottomSheet」這件事。

**工作範例**（依 Step 1 找到的 `reader_toc_button` 六處之一，對應本檔案 1518-1529 行的既有測試片段）：

Before：
```dart
      final finder = find.byKey(const Key('reader_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
```

After：
```dart
      final finder = find.byKey(const Key('reader_chrome_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
```

依此規則完成 Step 1 盤點清單中 `reader_appbar_chapter_title`／`reader_appbar_static_title`／`reader_toc_button` 全部出現處的遷移。

- [ ] **Step 4: 遷移既有測試——「新 Positioned 返回/目錄」測試（`reader_foliate_back_button`／`reader_pdf_back_button`／`reader_foliate_toc_button`）**

**轉換規則**：這批既有測試驗證的是 `epic-18`／`epic-24` 已經正確存在的行為（返回鍵 pop、目錄鍵開 TocBottomSheet），只是 Key 跟渲染路徑改變——一律改為 `find.byKey(const Key('reader_chrome_back_button'))`／`find.byKey(const Key('reader_chrome_toc_button'))`（Foliate 與 PDF 現在共用同一顆，兩邊原本各自的 `reader_foliate_back_button`／`reader_pdf_back_button` 收斂成一個）。若某個既有測試同時對兩種格式（Foliate 與 PDF）各自建構一次 `ReaderScreen` 個別驗證返回鍵，遷移後兩者都改用同一個新 Key，斷言邏輯本身不變。

`reader_layout_settings_button`／`reader_notes_button` 這兩組（來自已刪除的 `_buildAppBarActions()`）在本 Task **暫不遷移**——它們驗證的是「版面設定」「筆記」按鈕的存在與可點擊性，這兩個按鈕的正式新家是 Task 5 的 `reader_chrome_layout_button`／`reader_chrome_annotations_button`（選單列），本 Task 只处理頂部返回/目錄與死碼清除，若在本 Step 4 提前處理這兩組，Task 5 還要再改一次同一批測試造成重工。**暫時作法**：這兩組測試在本 Task 完成後會編譯失敗或斷言落空（因為 `_buildAppBarActions()` 已刪除、`reader_chrome_layout_button`/`reader_chrome_annotations_button` 尚未接線），先用 `// TODO(epic-38-issue1): 遷移至 Task 5 的 reader_chrome_layout_button/reader_chrome_annotations_button` 註解整段包住並 `skip: true` 暫時跳過（`testWidgets('...', skip: true, (tester) async {...})`），Task 5 完成時解除 skip 並正式遷移。

- [ ] **Step 5: 執行測試確認遷移後全數 PASS**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（除了 Step 4 標記 `skip: true` 的 `reader_layout_settings_button`／`reader_notes_button` 兩組，其餘全數通過；`skip: true` 的案例會顯示為 SKIPPED，不算失敗）

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`（確認 `_buildAppBarTitle`／`_buildAppBarActions`／4 個 AppBar 常數刪除後沒有任何殘留引用造成的未定義符號錯誤，也沒有新增的未使用 import／變數）

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/screens/reader_chrome_top_bar.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-38): 接上 ReaderChromeTopBar，刪除 Scaffold.appBar/_buildAppBarActions 死碼" -m "三格式共用同一份頂部 Chrome 列，永遠渲染不受 _chromeVisible 影響（只受 PDF 裁切編輯模式閘控）。既有依賴舊 AppBar 路徑與舊 Positioned 返回/目錄按鈕的測試已遷移至新 Key；reader_layout_settings_button/reader_notes_button 暫時 skip，Task 5 接上底部選單列後解除。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VFdTEkegztPHy1dq9fwY1j"
```

---

## Task 5：`ReaderChromeBottomBar` 接線＋過渡期 TTS 互斥＋收尾

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `ReaderChromeBottomBar`。
- Produces：`ReaderScreen` 新增私有方法 `String _pageProgressText(BookFormat format)`；`_openFoliateProgressSheet()`／`_openPdfProgressSheet()` 刪除（其唯一呼叫端——舊的「進度/跳頁」`Positioned` 按鈕——已在本 Task 移除）。

- [ ] **Step 1: 解除 Task 4 標記的 `skip: true`**

把 Task 4 Step 4 標記 `skip: true` 的 `reader_layout_settings_button`／`reader_notes_button` 相關測試改回不帶 `skip` 參數，並把斷言的 Key 改為 `reader_chrome_layout_button`／`reader_chrome_annotations_button`（此時尚未接線，預期本步驟結束後這批測試仍是 FAIL，等 Step 3 接線完成後才會轉綠——這是為了讓遷移意圖在版本歷史中清楚可追蹤，不需要額外驗證動作）。

- [ ] **Step 2: 新增 `_pageProgressText()` 輔助方法，並補上 `_openNotesSheet()` 的 `initialTabIndex` 接線**

編輯 `app/lib/screens/reader_screen.dart`，在 `_currentChapterTitle()`（Task 4 新增）之後新增：

```dart
  /// 頁碼列（`ReaderChromeBottomBar` 頂端 34dp 那一列）顯示的「當前頁 /
  /// 總頁數 · 百分比」文字（epic-38-reader-chrome-tts-redesign Issue 1，
  /// spec.md §功能①②）。位置資訊尚未載入完成（`_epubPositionInfo`／
  /// `_pdfPageInfo` 為 `null`，或總頁數 <= 0）時回傳空字串，呼叫端直接
  /// 顯示空白，不額外處理 loading 狀態文字。
  String _pageProgressText(BookFormat format) {
    if (format == BookFormat.pdf) {
      final info = _pdfPageInfo;
      if (info == null || info.totalPages <= 0) return '';
      final current = info.pageIndex + 1;
      final percent = (current / info.totalPages * 100).round();
      return '$current / ${info.totalPages} · $percent%';
    }
    final info = _epubPositionInfo;
    final totalPages = info?.displayTotalPages ?? 0;
    if (totalPages <= 0) return '';
    final current = ((info?.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
    final percent = (current / totalPages * 100).round();
    return '$current / $totalPages · $percent%';
  }
```

**接上 Task 1 建立的 `NotesBottomSheet.initialTabIndex`（審查修正 `review-plan-issue-1.md` C1）**：`_openNotesSheet()` 目前的簽章沒有轉發這個參數，若不修改，底部選單列的「✎ 劃線筆記」按鈕點下去仍然會停在預設的「🔖 書籤」分頁，Task 1 做的事就變成沒有任何呼叫端在用的死碼。

Before（`reader_screen.dart:1322`／`:1343-1349`）：
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
          isFoliateFormat(format) ? _epubPositionInfo?.locatorJson : null,
      progression:
          isFoliateFormat(format) ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    final latestProgress = isFoliateFormat(format)
        ? (_epubPositionInfo?.progression ?? widget.bookProgress)
        : (_pdfPageInfo != null && _pdfPageInfo!.totalPages > 0
            ? (_pdfPageInfo!.pageIndex + 1) / _pdfPageInfo!.totalPages
            : widget.bookProgress);
    _showThemedModalBottomSheet<void>(
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
        currentPosition: positionContext,
```

After：
```dart
  /// [initialTabIndex] 預設 `0`（🔖書籤，既有呼叫端不受影響）——底部
  /// 選單列「✎ 劃線筆記」按鈕（Step 3a／3b）傳入 `1`，預設停在「✏️劃線與
  /// 備註」分頁（epic-38-reader-chrome-tts-redesign Issue 1，接上 Task 1
  /// 建立的 `NotesBottomSheet.initialTabIndex`）。
  void _openNotesSheet(BookFormat format, {int initialTabIndex = 0}) {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final positionContext = BookmarkPositionContext(
      epubLocatorJson:
          isFoliateFormat(format) ? _epubPositionInfo?.locatorJson : null,
      progression:
          isFoliateFormat(format) ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    final latestProgress = isFoliateFormat(format)
        ? (_epubPositionInfo?.progression ?? widget.bookProgress)
        : (_pdfPageInfo != null && _pdfPageInfo!.totalPages > 0
            ? (_pdfPageInfo!.pageIndex + 1) / _pdfPageInfo!.totalPages
            : widget.bookProgress);
    _showThemedModalBottomSheet<void>(
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        initialTabIndex: initialTabIndex,
```

（`NotesBottomSheet(...)` 建構呼叫的其餘既有具名參數——`highlightsRepository`／`notesRepository`／`onAnnotationSelected`／`onAnnotationsChanged`／`onBookmarkSelected`——原樣保留不動，只在既有參數清單裡插入這一行。）

- [ ] **Step 3: 底部 `Positioned` 統一——刪除 Foliate／PDF 各自的功能按鈕群，插入 `ReaderChromeBottomBar`**

**3a. 刪除 Foliate 底部 5 顆（版面/書籤/筆記/進度/朗讀開關），插入 `ReaderChromeBottomBar`**

Before（`reader_screen.dart:2196-2296`，緊接在 Task 4 已刪除的 Foliate 返回/目錄之後）：
```dart
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed: _isFixedLayout
                          ? _openFxlSettings
                          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_bookmark_toggle_button'),
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
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
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: (_autoDetectedWritingMode == null ||
                              _epubPositionInfo == null)
                          ? null
                          : () => _openNotesSheet(format),
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null)
              Positioned(
                top: 296,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_tts_toggle_button'),
                      icon: Icon(Icons.record_voice_over,
                          color: _themedFabIconColor),
                      tooltip:
                          _ttsMiniPlayerVisible ? '隱藏朗讀控制列' : '顯示朗讀控制列',
                      onPressed: () => setState(
                          () => _ttsMiniPlayerVisible = !_ttsMiniPlayerVisible),
                    ),
                  ),
                ),
              ),
```

After：
```dart
            // epic-38-reader-chrome-tts-redesign Issue 1：三格式共用同一份
            // ReaderChromeBottomBar，取代原本 Foliate 5 顆／PDF 4 顆各自
            // 獨立的 Positioned（見下方 PDF FAB 區塊對應段落，Step 3b 一併
            // 刪除）。`!_ttsMiniPlayerVisible` 是本 Issue 過渡期的互斥條件
            // ——舊 TtsMiniPlayer 膠囊固定貼底 12/40dp，新底部列三列合計
            // 154dp 也貼底，兩者同時渲染會互相遮擋，Issue 2 接上 TtsPanel
            // 後這個條件會被 AnimatedBuilder 依 TtsController.status 的
            // 正式衍生切換取代（見 issues.md Issue 2）。
            if (isFoliateFormat(format) && _chromeVisible && !_ttsMiniPlayerVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReaderChromeBottomBar(
                  bookTitle: widget.bookTitle,
                  pageProgressText: _pageProgressText(format),
                  footer: _epubPositionInfo == null
                      ? const SizedBox.shrink()
                      : _buildFoliateEpubFooter(_epubPositionInfo!),
                  isBookmarked: _bookmarkAtCurrentPosition != null,
                  onBookmarkTap: widget.bookmarksRepository == null ||
                          _epubPositionInfo == null
                      ? null
                      : _toggleBookmark,
                  onAnnotationsTap: widget.bookmarksRepository == null ||
                          _autoDetectedWritingMode == null ||
                          _epubPositionInfo == null
                      ? null
                      : () => _openNotesSheet(format, initialTabIndex: 1),
                  onLayoutTap: _isFixedLayout
                      ? _openFxlSettings
                      : (_autoDetectedWritingMode == null
                          ? null
                          : _openLayoutSettings),
                  onTtsTap: widget.ttsProvider == null
                      ? null
                      : () => setState(
                          () => _ttsMiniPlayerVisible = !_ttsMiniPlayerVisible),
                  backgroundColor: _themedFabBackgroundColor,
                  iconColor: _themedFabIconColor,
                  isEinkMode: widget.isEinkMode,
                ),
              ),
```

**3b. 刪除 PDF 底部 4 顆（版面/書籤/筆記/進度），插入 `ReaderChromeBottomBar`**

Before（`reader_screen.dart:2392-2472`，位於 Task 4 已刪除的 PDF 返回/目錄之後）：
```dart
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed:
                          _state == _RenderState.rendered ? _openPdfSettings : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_bookmark_toggle_button'),
                      icon: Icon(
                        _pdfBookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
                      ),
                      tooltip: _pdfBookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _pdfPageInfo == null ? null : _togglePdfBookmark,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: _state == _RenderState.rendered
                          ? () => _openNotesSheet(BookFormat.pdf)
                          : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openPdfProgressSheet,
                    ),
                  ),
                ),
              ),
```

After：
```dart
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReaderChromeBottomBar(
                  bookTitle: widget.bookTitle,
                  pageProgressText: _pageProgressText(format),
                  footer: _pdfPageInfo == null
                      ? const SizedBox.shrink()
                      : ReaderFooter(
                          currentPage: _pdfPageInfo!.pageIndex + 1,
                          totalPages: _pdfPageInfo!.totalPages,
                          onPageChanged: (page1Indexed) => PdfReaderView.jumpToPage(
                              _pdfReaderViewKey, page1Indexed - 1),
                        ),
                  isBookmarked: _pdfBookmarkAtCurrentPosition != null,
                  onBookmarkTap: widget.bookmarksRepository == null ||
                          _pdfPageInfo == null
                      ? null
                      : _togglePdfBookmark,
                  onAnnotationsTap: widget.bookmarksRepository == null ||
                          _state != _RenderState.rendered
                      ? null
                      : () => _openNotesSheet(BookFormat.pdf, initialTabIndex: 1),
                  onLayoutTap:
                      _state == _RenderState.rendered ? _openPdfSettings : null,
                  onTtsTap: null, // PDF 目前結構性沒有 TTS 底層能力
                  backgroundColor: _themedFabBackgroundColor,
                  iconColor: _themedFabIconColor,
                  isEinkMode: widget.isEinkMode,
                ),
              ),
```

**3c. 刪除已無呼叫端的 `_openFoliateProgressSheet()`／`_openPdfProgressSheet()`**（兩者原本的唯一呼叫端——「進度/跳頁」`Positioned` 按鈕——已在 3a／3b 移除；`_buildFoliateEpubFooter()` 保留，改由 3a 直接呼叫）。

**3d. 新增 import**

```dart
import 'reader_chrome_bottom_bar.dart';
```

- [ ] **Step 4: 遷移剩餘既有測試**

依同一套規則（見 Task 4 Step 4）逐一遷移：

| 舊 Key | 新 Key | 出現次數（遷移前） |
|---|---|---|
| `reader_foliate_settings_button`／`reader_pdf_settings_button` | `reader_chrome_layout_button` | 29／5 |
| `reader_foliate_bookmark_toggle_button`／`reader_pdf_bookmark_toggle_button` | `reader_chrome_bookmark_button` | 8／0 |
| `reader_foliate_notes_button`／`reader_pdf_notes_button` | `reader_chrome_annotations_button` | 6／2 |
| `reader_foliate_progress_button`／`reader_pdf_progress_button` | 內嵌 `ReaderFooter`（無獨立觸發按鈕，直接斷言 `find.byType(ReaderFooter)`／`find.byKey(const Key('reader_footer'))` 已存在於畫面上，不需要「先點按鈕再等 Bottom Sheet」這道手續） | 8／3 |
| `reader_foliate_tts_toggle_button` | `reader_chrome_tts_button`（互動語意不變：點擊切換 `_ttsMiniPlayerVisible`，只是位置與 Key 改變） | 16 |
| `reader_layout_settings_button`／`reader_notes_button`（Task 4 標記 `skip: true`） | `reader_chrome_layout_button`／`reader_chrome_annotations_button`（解除 skip，見 Step 1） | 7／6 |

**工作範例一**（跳頁按鈕類，取 `reader_foliate_progress_button` 既有測試典型寫法）：

Before：
```dart
      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReaderFooter), findsOneWidget);
```

After：
```dart
      // ReaderChromeBottomBar 的跳頁列直接內嵌 ReaderFooter，不需要先點擊
      // 一顆獨立按鈕才彈出 Bottom Sheet（epic-38-reader-chrome-tts-redesign
      // Issue 1）。
      expect(find.byType(ReaderFooter), findsOneWidget);
```

**工作範例二**（TTS 開關類，取 `reader_foliate_tts_toggle_button` 既有測試典型寫法）：

Before：
```dart
      expect(find.byType(TtsMiniPlayer), findsNothing);
      await tester.tap(find.byKey(const Key('reader_foliate_tts_toggle_button')));
      await tester.pump();
      expect(find.byType(TtsMiniPlayer), findsOneWidget);
```

After：
```dart
      expect(find.byType(TtsMiniPlayer), findsNothing);
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();
      expect(find.byType(TtsMiniPlayer), findsOneWidget);
      // 過渡期互斥（review-issues.md I1 訂正）：TtsMiniPlayer 顯示時，新的
      // ReaderChromeBottomBar 不應同時渲染，避免兩者視覺重疊。
      expect(find.byType(ReaderChromeBottomBar), findsNothing);
```

依此規則完成上表全部出現處的遷移。**每完成一組（例如先完成全部 `settings_button` 相關的遷移）就跑一次** `flutter test test/screens/reader_screen_test.dart --name "<關鍵字>"`（用測試名稱關鍵字篩選該組），確認轉綠後再處理下一組，不要一次改完全部 100+ 處才第一次執行測試——那樣任何一處筆誤都要在龐大輸出裡大海撈針。

**新增 `reader_chrome_annotations_button` 的 `initialTabIndex` 接線回歸測試（審查修正 `review-plan-issue-1.md` C1）**——`reader_foliate_notes_button`／`reader_pdf_notes_button` 既有測試只驗證「點擊後 `NotesBottomSheet` 出現」，沒有驗證停在哪個分頁；Step 2 新增的 `initialTabIndex` 接線若日後被意外改掉，這批既有測試不會發現。找既有一則會點擊 `reader_foliate_notes_button`（遷移後為 `reader_chrome_annotations_button`）的測試，在 `expect(find.byType(NotesBottomSheet), findsOneWidget)` 之後追加：
```dart
      expect(
        tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet)).initialTabIndex,
        1,
      );
```

- [ ] **Step 5: 新增過渡期互斥回歸測試**

在 `app/test/screens/reader_screen_test.dart` 新增（找一個既有的 EPUB 流式格式測試作為樣板，補齊 `pumpWidget`／`onLayoutResolved` 既有慣例）：

```dart
  testWidgets(
    '開啟舊 TtsMiniPlayer 膠囊時，新的 ReaderChromeBottomBar 不會同時顯示'
    '（review-issues.md I1 過渡期互斥回歸測試）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_bottombar_exclusion',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsMiniPlayer), findsNothing);

      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      expect(find.byType(ReaderChromeBottomBar), findsNothing);
      expect(find.byType(TtsMiniPlayer), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader_tts_mini_player_close_button')));
      await tester.pump();

      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsMiniPlayer), findsNothing);
    },
  );
```

（動手前先讀本檔案既有 `FakeTtsProvider` 建構方式與 `resolveThemeData` 既有呼叫慣例，確認參數與本範例一致；若 `TtsMiniPlayer` 的關閉按鈕 Key 與範例不同，以既有程式碼實際值為準。）

- [ ] **Step 6: 執行 `reader_screen_test.dart` 全數確認 PASS**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部案例，0 失敗、0 SKIPPED——所有 Task 4 標記的 `skip: true` 案例都已在 Step 1 解除並遷移完成）

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`（確認 `_openFoliateProgressSheet`／`_openPdfProgressSheet` 刪除後沒有殘留呼叫端造成的未定義符號錯誤）

- [ ] **Step 8: 執行整份 Epic Issue 1 收尾要求的完整測試套件**

Run: `flutter test`
Expected: PASS（全部案例——本 Task 是本計劃最後一個 Task，比照 `CLAUDE.md`「測試執行範圍」規範跑一次完整套件確認無全域回歸）

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/screens/reader_chrome_bottom_bar.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-38): 接上 ReaderChromeBottomBar，過渡期與舊 TtsMiniPlayer 互斥顯示" -m "三格式共用同一份底部三列 Chrome（頁碼列/跳頁列/選單列），取代 Foliate 5 顆/PDF 4 顆各自獨立的 Positioned 浮動圓鈕。底部選單列朗讀按鈕過渡期仍呼叫既有 _ttsMiniPlayerVisible 開關，並與新底部列互斥顯示避免視覺重疊（review-issues.md I1）；Issue 2 會把整個 TTS 顯示邏輯換成正式的 TtsPanel。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VFdTEkegztPHy1dq9fwY1j"
```

---

## 收尾提醒

- Task 5 完成即代表 Issue 1 完成。完成後把 `issues.md` Issue 1 的 `Status:` 從 `ready-for-agent` 改為 `completed`，`epic.md` 補一則完成記錄，`docs/epics.md` 該列備註同步更新為「Issue 1 已完成」。
- 依 `CLAUDE.md`「審查一律先產出報告，嚴禁直接修改」規則，完成後應發起 `/superpowers:requesting-code-review`，審查報告存於 `docs/epics/epic-38-reader-chrome-tts-redesign/reviews/review-issue-1.md`，交由人類決定是否合併。
- Issue 2（`TtsPanel` 重構＋`TtsController.stop()`＋睡眠定時器）依賴本 Issue 建立的 `ReaderChromeTopBar`（新增 `showTtsIndicator` 真實邏輯）／`ReaderChromeBottomBar`（移除過渡期 `!_ttsMiniPlayerVisible` 互斥條件，改用 `AnimatedBuilder` 依 `TtsController.status` 衍生切換），見 `issues.md` Issue 2。
