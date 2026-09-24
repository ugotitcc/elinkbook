# Epic 42 Issue 3 — Dart 端跨畫面顯示轉換 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Issue 0／Issue 0b 已交付的 `convertText()`／`TextOffsetMap` 與 Issue 1 已交付的 `resolveTextConversion()`／`ReadingDefaults.textConversion` 接到 Dart 端所有「純文字渲染」畫面——目錄面板、書籤清單、`ReaderScreen` 頁首/底部工具列/單書搜尋標題、書架書名/作者——讓簡繁顯示轉換偏好在這些畫面上實際生效（純文字轉換，不涉及 CFI／DOM，Issue 2 的 WebView DOM Walker 與座標保護已獨立完成，本 Issue 不重複）。

**Architecture:** 「單書情境」（目錄／書籤清單／`ReaderScreen` 頁首/底部工具列/單書搜尋標題）一律呼叫 `resolveTextConversion(BookReaderPrefs, ReadingDefaults)` 取得該書生效值；「跨書情境」（`LibraryScreen` 書架）一律直接採 `GlobalReaderPrefs.reading.textConversion`，不做任何單書覆寫（比照 spec.md「Dart 端字元轉換模組」呼叫點清單分流規則）。`TocBottomSheet`／`NotesBottomSheet` 新增 `textConversion` 建構參數（比照 Issue 1 `FxlSettingsSheet.showTextConversion` 先例，給預設值、不設 `required`，避免動到既有測試呼叫點）；`ReaderScreen` 新增 `_textConversionMode`／`_displayBookTitle`／`_displayBookAuthor` 三個私有 getter 作為所有「單書情境」渲染點的單一計算來源（審查修正 M-1 建議的收斂做法）；`LibraryScreen` 新增 `_textConversion` State 欄位，透過既有 `refreshSignal`（`_onExternalRefreshRequested()`）在使用者從「設定」分頁切回書架時重新載入，因為 `AdaptiveShellScaffold` 用 `IndexedStack` 讓 `LibraryScreen` 全程掛載、不會自動重新 build()。

**Tech Stack:** Flutter/Dart（`flutter_test`）。不涉及 SQLite migration、JS/WebView（Issue 0/0b/1/2 已完成）。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 3（另見 `docs/epics/epic-42-text-conversion/spec.md`「Dart 端字元轉換模組」、`docs/epics/epic-42-text-conversion/design.md` 第 8-9 點）。

## Global Constraints

- `convertText(String input, TextConversionMode mode)`（`app/lib/reader/text_conversion.dart`）與 `resolveTextConversion(BookReaderPrefs book, ReadingDefaults global)`（`app/lib/reader/resolve_text_conversion.dart`）簽章是 Issue 0/1 定案、Issue 2 已消費的穩定介面，本 Issue 不得更動參數順序或型別。
- 備註文字（`Note.text`）在任何情境下皆**不轉換**，維持使用者輸入原樣（spec.md「Dart 端字元轉換模組」單書情境條列明文排除）。
- **已知落差（已與使用者確認，見下方 Self-Review）**：issues.md Issue 3「範圍」提到「劃線清單摘要片段（僅摘要片段，不含備註文字本身）」需轉換，但本專案 `Highlight` model（`app/lib/reader/highlight.dart`）從未儲存劃線框住的原文片段——`markdown_export.dart:10-13` 的既有文件註解明確記載這是刻意設計決策（劃線清單只顯示「樣式標籤＋位置標籤」，不引用原文）。目前程式碼沒有對應的「劃線摘要片段」渲染點可以修改，本計畫**不新增**此項程式碼，僅在 Task 2 補一則說明性註解，不算遺漏。
- `TocBottomSheet.textConversion`／`NotesBottomSheet.textConversion` 新增建構參數一律給 `TextConversionMode.original` 預設值、**不設為 `required`**——比照 `FxlSettingsSheet.showTextConversion` 既有先例（`docs/epics/epic-42-text-conversion/plans/plan-issue-1.md` Task 8：「省略 showTextConversion 參數時，預設顯示簡繁轉換覆寫選項（向後相容）」），避免動到 `test/screens/toc_bottom_sheet_test.dart`（6 處）、`test/screens/toc_bottom_sheet_pdf_test.dart`（9 處）、`test/screens/notes_bottom_sheet_test.dart`（經由共用 `_pumpSheet()` helper）既有呼叫點。
- `LibraryScreen`「跨書情境」一律採 `GlobalReaderPrefs.reading.textConversion`，不做任何單書覆寫（spec.md「Dart 端字元轉換模組」「跨書情境」條列明文）。
- **已與使用者確認的範圍界線**：`BookSearchScreen` 的 AppBar 書名/作者轉換只處理 `ReaderScreen._buildSearchableBook()`（從閱讀器「搜尋內文」按鈕開單書搜尋，明確單書情境）這一個入口；`LibrarySearchScreen._openBookSearch()` 全庫搜尋結果下鑽進單書搜尋的另一個入口維持現狀不轉換（傳入的 `Book` 來自 library 查詢，非 `ReaderScreen._prefs`，留給後續 Issue 或另立工單處理一致性）。
- `PdfSettingsSheet` 不新增文字轉換 UI（Issue 1 既定範圍不變），但 PDF 書籍的目錄／單書搜尋標題列／底部工具列仍會依 `resolveTextConversion()` 解析出的**全域預設值**轉換——因為 `resolveTextConversion()` 對任何格式書籍皆成立，PDF 書籍只是沒有 UI 讓使用者設定單書覆寫（`book.textConversionOverride` 恆為 `null`），不影響轉換本身生效。
- 所有新增 widget test 一律使用既有 `convertText()` 測試已驗證過的已知字元對「国电脑」→ toTraditional →「國電腦」（`test/reader/text_conversion_test.dart` 既有測試向量），不自行發明未經驗證的字元映射。

---

## File Structure

- Modify: `app/lib/screens/toc_bottom_sheet.dart` — 新增 `textConversion` 建構參數，`node.title` 渲染前套用 `convertText()`。
- Modify: `app/test/screens/toc_bottom_sheet_test.dart` — 新增轉換行為測試。
- Modify: `app/test/screens/toc_bottom_sheet_pdf_test.dart` — 新增 PDF 目錄項目轉換行為測試。
- Modify: `app/lib/screens/notes_bottom_sheet.dart` — 新增 `textConversion` 建構參數，書籤清單 `bookmark.name` 渲染前套用 `convertText()`（備註文字不受影響）。
- Modify: `app/test/screens/notes_bottom_sheet_test.dart` — `_pumpSheet()` helper 新增 `textConversion` 參數，新增轉換行為測試與備註文字不受影響測試。
- Modify: `app/lib/screens/reader_screen.dart` — 新增 `_textConversionMode`／`_displayBookTitle`／`_displayBookAuthor` 私有 getter；`_buildFoliateHeaderText()`、`_buildFoliateChromeBottomBar()`、PDF `ReaderChromeBottomBar` 呼叫點、`_buildSearchableBook()`、`_openToc()`、`_openPdfToc()`、`_openNotesSheet()` 共 7 處接線；並同步更新待活化方法 `_currentChapterTitle()` 避免未來字形遺漏（審查修正 M-1）。
- Modify: `app/test/screens/reader_screen_test.dart` — 新增 6 則對應測試。
- Modify: `app/lib/screens/library_screen.dart` — 新增 `_textConversion` State 欄位＋ `_reloadTextConversion()`；`_BookGridTile`／`_BookListTile`／`_ContinueReadingRow`／`_BookDetailsDialog` 新增 `textConversion` 參數並套用轉換；`_openBookActionSheet()` 動作選單標題套用轉換；`_initialize()` 改為等待全域偏好載入完成後才進入書籍清單載入，避免啟動畫面文字閃爍（審查修正 I-1／I-2）。
- Modify: `app/lib/library/widgets/book_cover.dart` — 新增 `textConversion` 參數，`CoverPlaceholder` 書名縮略文字套用轉換，避免封面佔位圖與卡片標題文字字形不一致（審查修正 C-1）。
- Modify: `app/test/library/widgets/book_cover_test.dart` — 新增轉換行為測試。
- Modify: `app/test/screens/library_screen_test.dart` — 新增 6 則對應測試（含審查修正後的斷言數量）。

---

### Task 1: `TocBottomSheet` 新增 `textConversion` 參數

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Test: `app/test/screens/toc_bottom_sheet_test.dart`
- Test: `app/test/screens/toc_bottom_sheet_pdf_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/text_conversion.dart` 的 `convertText(String, TextConversionMode)`（Issue 0）；`app/lib/reader/text_conversion_mode.dart` 的 `TextConversionMode`（Issue 0）。
- Produces: `TocBottomSheet.textConversion`（`TextConversionMode`，預設 `TextConversionMode.original`），供 Task 3 `reader_screen.dart` 的 `_openToc()`／`_openPdfToc()` 呼叫點消費。

- [x] **Step 1: 新增失敗測試**

在 `app/test/screens/toc_bottom_sheet_test.dart` 第 1 行之後新增 import：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 142-152 行「點擊右上角 X 取消按鈕後」測試結尾的 `});`，在其後、`main()` 結尾的 `}`（第 153 行）之前新增：

```dart

  testWidgets(
      'textConversion: toTraditional 時，目錄標題套用簡繁轉換（epic-42-text-conversion Issue 3）',
      (tester) async {
    final tocEntries = [
      const TocEntry(title: '电脑', locatorJson: 'l1', progression: 0.0),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: tocEntries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    ));

    expect(find.text('電腦'), findsOneWidget);
    expect(find.text('电脑'), findsNothing);
  });

  testWidgets('省略 textConversion 參數時，目錄標題維持原文（向後相容，epic-42-text-conversion Issue 3）',
      (tester) async {
    final tocEntries = [
      const TocEntry(title: '电脑', locatorJson: 'l1', progression: 0.0),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: tocEntries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.text('电脑'), findsOneWidget);
  });
```

在 `app/test/screens/toc_bottom_sheet_pdf_test.dart` 第 1 行之後新增 import：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到檔案結尾「未傳入 thumbnailTabContent 時」測試結尾的 `});`（第 207 行），在其後、`main()` 結尾的 `}`（第 208 行）之前新增：

```dart

  testWidgets(
      'textConversion: toSimplified 時，PDF 目錄標題套用簡繁轉換（epic-42-text-conversion Issue 3）',
      (tester) async {
    const node = PdfTocItem(title: '電腦', pageIndex: 0, stableId: 'p_tc');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [node],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
          textConversion: TextConversionMode.toSimplified,
        ),
      ),
    ));

    expect(find.text('电脑'), findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart test/screens/toc_bottom_sheet_pdf_test.dart`
Expected: 新增的 3 個測試皆 FAIL（`textConversion` 不是 `TocBottomSheet` 已知的具名參數，編譯錯誤）。

- [x] **Step 3: 實作 `textConversion` 參數**

在 `app/lib/screens/toc_bottom_sheet.dart` 第 6 行（`import '../reader/toc_entry.dart';`）之後新增：

```dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 54 行 `final Widget? searchTabContent;` 之後、第 56 行 `const TocBottomSheet({` 之前新增：

```dart

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 3）：套用在
  /// [BookTocItem.title] 上，格式無關（EPUB／PDF 目錄項目共用同一套轉換
  /// 邏輯）。預設 `TextConversionMode.original`（不轉換，向後相容既有
  /// 呼叫端／測試，比照 `FxlSettingsSheet.showTextConversion` 既有先例，
  /// 見 plan-issue-1.md Task 8）。
  final TextConversionMode textConversion;
```

修改第 56-65 行的建構子，在 `this.searchTabContent,` 之後新增一行：

```dart
  const TocBottomSheet({
    super.key,
    this.format,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.onEntrySelected,
    this.thumbnailTabContent,
    this.searchTabContent,
    this.textConversion = TextConversionMode.original,
  });
```

修改第 194-208 行的 `_buildEntryRow()`，把：

```dart
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
```

改為：

```dart
        title: Text(
          convertText(node.title, widget.textConversion),
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart test/screens/toc_bottom_sheet_pdf_test.dart`
Expected: 全數 PASS（既有 15 個測試零回歸＋新增 3 個測試通過）。

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_test.dart app/test/screens/toc_bottom_sheet_pdf_test.dart
git commit -m "feat(reader): TocBottomSheet 新增簡繁轉換 textConversion 參數"
```

---

### Task 2: `NotesBottomSheet` 新增 `textConversion` 參數（書籤清單）

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: `convertText(String, TextConversionMode)`（Issue 0）。
- Produces: `NotesBottomSheet.textConversion`（`TextConversionMode`，預設 `TextConversionMode.original`），供 Task 3 `reader_screen.dart` 的 `_openNotesSheet()` 呼叫點消費。

- [x] **Step 1: 新增失敗測試**

在 `app/test/screens/notes_bottom_sheet_test.dart` 第 13 行（`import 'package:elinkbook/screens/notes_bottom_sheet.dart';`）之後新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

修改第 22-58 行的 `_pumpSheet()` helper，在具名參數列的 `int initialTabIndex = 0,`（第 34 行）之後新增一個參數，並在建構 `NotesBottomSheet` 時傳入：

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
  TextConversionMode textConversion = TextConversionMode.original,
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
          textConversion: textConversion,
        ),
      ),
    ),
  );
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}
```

找到第 108-124 行「書籤分頁正確依位置順序顯示清單」測試結尾的 `});`，在其後新增：

```dart

  testWidgets('textConversion: toTraditional 時，書籤清單名稱套用簡繁轉換（epic-42-text-conversion Issue 3）',
      (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm_tc', bookId: 'b1', name: '电脑 (10%)', progression: 0.1),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      textConversion: TextConversionMode.toTraditional,
    );

    expect(find.text('電腦 (10%)'), findsOneWidget);
    expect(find.text('电脑 (10%)'), findsNothing);
  });

  testWidgets('備註文字不受 textConversion 影響，維持使用者輸入原樣（epic-42-text-conversion Issue 3）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(const Highlight(
      id: 'h_tc',
      bookId: 'b1',
      style: HighlightStyle.highlighterYellow,
      progression: 0.1,
    ));
    await notesRepository.insert(const Note(
      id: 'n_tc',
      bookId: 'b1',
      text: '电脑笔记',
      highlightId: 'h_tc',
      progression: 0.1,
    ));
    await _pumpSheet(
      tester,
      repository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      textConversion: TextConversionMode.toTraditional,
    );

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.text('电脑笔记'), findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: 新增的 2 個測試皆 FAIL（`textConversion` 不是 `NotesBottomSheet` 已知的具名參數，編譯錯誤）。

- [x] **Step 3: 實作 `textConversion` 參數**

在 `app/lib/screens/notes_bottom_sheet.dart` 第 17 行（`import '../reader/notes_repository.dart';`）之後新增：

```dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 66 行 `final int initialTabIndex;` 之後、第 68 行 `const NotesBottomSheet({` 之前新增：

```dart

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 3）：套用在
  /// 書籤清單的 [Bookmark.name] 上。**不套用**在備註文字（[Note.text]）
  /// 上——備註是使用者輸入的自由文字，恆維持原樣。issues.md Issue 3
  /// 提及的「劃線清單摘要片段」轉換在目前程式碼中無對應渲染點可修改：
  /// 本專案 `Highlight` model 從未儲存劃線框住的原文片段，劃線清單只
  /// 顯示樣式標籤（見 `markdown_export.dart` 開頭文件註解的既有設計
  /// 決策），此為刻意留白、非遺漏（詳見 plan-issue-3.md Global
  /// Constraints）。預設 `TextConversionMode.original`（向後相容既有
  /// 呼叫端／測試）。
  final TextConversionMode textConversion;
```

修改建構子，在 `this.initialTabIndex = 0,` 之後新增一行：

```dart
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
    this.textConversion = TextConversionMode.original,
  });
```

修改 `_buildBookmarkRow()`（第 358-374 行），把：

```dart
        title: Text(bookmark.name),
```

改為：

```dart
        title: Text(convertText(bookmark.name, widget.textConversion)),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增 2 個測試通過）。

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(reader): NotesBottomSheet 新增簡繁轉換 textConversion 參數（書籤清單）"
```

---

### Task 3: `ReaderScreen` 單書情境接線（頁首／底部工具列／單書搜尋／目錄／筆記）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `resolveTextConversion(BookReaderPrefs, ReadingDefaults)`（Issue 1）、`convertText(String, TextConversionMode)`（Issue 0）、`TocBottomSheet.textConversion`／`NotesBottomSheet.textConversion`（Task 1／Task 2）。
- Produces: `_ReaderScreenState._textConversionMode`／`_displayBookTitle`／`_displayBookAuthor` 三個私有 getter（本 Issue 內部使用，不對外公開）。

- [x] **Step 1: 新增失敗測試**

在 `app/test/screens/reader_screen_test.dart` 找到第 4806-4856 行「流式 EPUB：目錄尚未載入時，頁首顯示書名而非「閱讀器」」測試結尾的 `});`，在其後新增：

```dart

  testWidgets('流式 EPUB：單書覆寫簡繁轉換時，頁首書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_text_conversion',
      const BookReaderPrefs(
        showHeader: true,
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_text_conversion',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.data, '國電腦');
  });

  testWidgets('流式 EPUB：ReaderChromeBottomBar 的 bookTitle 依單書簡繁轉換呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_bottom_bar_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_bottom_bar_text_conversion',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final bar = tester.widget<ReaderChromeBottomBar>(
      find.byType(ReaderChromeBottomBar),
    );
    expect(bar.bookTitle, '國電腦');
  });

  testWidgets('PDF：ReaderChromeBottomBar 的 bookTitle 依單書簡繁轉換呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_pdf_bottom_bar_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_bottom_bar_text_conversion',
          prefsManager: prefsManager,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final bar = tester.widget<ReaderChromeBottomBar>(
      find.byType(ReaderChromeBottomBar),
    );
    expect(bar.bookTitle, '國電腦');
  });

  testWidgets('目錄按鈕開啟的 TocBottomSheet 帶入該書已解析的簡繁轉換模式（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_toc_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_text_conversion',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    expect(sheet.textConversion, TextConversionMode.toTraditional);
  });

  testWidgets('筆記按鈕開啟的 NotesBottomSheet 帶入該書已解析的簡繁轉換模式（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_notes_text_conversion',
      const BookReaderPrefs(
        showHeader: true,
        showFooter: true,
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_text_conversion',
          prefsManager: prefsManager,
          bookmarksRepository: FakeBookmarksRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onPageRendered();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet =
        tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet));
    expect(sheet.textConversion, TextConversionMode.toTraditional);
  });
```

找到 `group('epic-10-search Issue 8：閱讀器 TopBar 搜尋接線', ...)`（第 9613 行起）內，第一個測試「searchRepository／libraryRepository 皆存在時，點擊搜尋按鈕推入 BookSearchScreen」結尾的 `});`（第 9652 行），在其後新增：

```dart

    testWidgets(
        '單書覆寫簡繁轉換時，推入的 BookSearchScreen 帶入已轉換的書名／作者（epic-42-text-conversion Issue 3）',
        (tester) async {
      final searchRepository = FakeSearchRepository();
      final libraryRepository = FakeLibraryRepository();
      final localPrefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_search_text_conversion': const BookReaderPrefs(
            textConversionOverride: TextConversionMode.toTraditional,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_text_conversion',
            bookTitle: '国电脑',
            bookAuthor: '电脑作者',
            prefsManager: localPrefsManager,
            searchRepository: searchRepository,
            libraryRepository: libraryRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      final pushed =
          tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.book.title, '國電腦');
      expect(pushed.book.author, '電腦作者');
    });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 新增的 6 個測試皆 FAIL（斷言值仍是未轉換的原文，例如 `headerText.data` 為 `'国电脑'` 而非 `'國電腦'`；`sheet.textConversion` 不存在等）。

- [x] **Step 3: 實作接線**

在 `app/lib/screens/reader_screen.dart` 第 56 行（`import '../reader/resolve_text_conversion.dart';`）之後新增：

```dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 2279 行（`_pageProgressText()` 方法結尾的 `}`）之後、第 2281 行既有註解之前新增：

```dart

  /// 本書「單書情境」下簡繁顯示轉換的目前生效值（FR-48，epic-42-text-
  /// conversion Issue 3）：`_loaded` 尚未載入完成時（載入中／錯誤等早退
  /// 分支）安全回退 `original`，比照 `_resolved?.showHeader ?? true`
  /// 既有「早退分支維持安全預設值」慣例——部分呼叫點（例如
  /// `_buildSearchableBook()` 供 `ReaderChromeTopBar` 搜尋按鈕使用）在
  /// `_loaded` 尚未賦值前就可能被觸發，不能沿用 `_buildNativeView()`
  /// 既有「`_resolved` 非 null 時 `_loaded` 恆非 null」的前提斷言。
  TextConversionMode get _textConversionMode {
    final loaded = _loaded;
    if (loaded == null) return TextConversionMode.original;
    return resolveTextConversion(_prefs, loaded.globalPrefs.reading);
  }

  /// 依 [_textConversionMode] 轉換後的書名，供頁首／底部工具列／單書
  /// 搜尋標題等「單書情境」渲染點統一取用（審查修正 M-1，見
  /// issues.md Issue 3：避免逐點各自呼叫 convertText() 造成遺漏）。
  String get _displayBookTitle =>
      convertText(widget.bookTitle, _textConversionMode);

  /// 同 [_displayBookTitle]，供 `_buildSearchableBook()` 的作者欄位使用；
  /// [widget.bookAuthor] 為 null 時原樣回傳 null。
  String? get _displayBookAuthor {
    final author = widget.bookAuthor;
    return author == null ? null : convertText(author, _textConversionMode);
  }
```

修改 `_buildSearchableBook()`（第 1689-1705 行），把：

```dart
    return Book(
      id: widget.bookId,
      title: widget.bookTitle,
      author: widget.bookAuthor,
```

改為：

```dart
    return Book(
      id: widget.bookId,
      title: _displayBookTitle,
      author: _displayBookAuthor,
```

修改 `_openToc()`（第 1327-1344 行），在 `onEntrySelected:` 之後新增一行：

```dart
  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        format: BookFormat.epub,
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
        textConversion: _textConversionMode,
      ),
    );
  }
```

修改 `_openPdfToc()`（第 1355-1395 行），在 `searchTabContent:` 區塊之後新增一行：

```dart
        searchTabContent: PdfSearchPanel(
          searchStateListenable: _pdfSearchStateNotifier,
          initialQuery: _pdfSearchStateNotifier.value.query,
          onQueryChanged: (query) => unawaited(_searchPdf(query)),
          onNext: () => _goToPdfSearchMatch(1),
          onPrevious: () => _goToPdfSearchMatch(-1),
        ),
        textConversion: _textConversionMode,
      ),
    );
  }
```

修改 `_openNotesSheet()`（第 1447-1500 行左右），在 `initialTabIndex: initialTabIndex,` 之後新增一行：

```dart
        initialTabIndex: initialTabIndex,
        textConversion: _textConversionMode,
```

修改 `_buildFoliateChromeBottomBar()`（第 2372-2399 行），把：

```dart
    return ReaderChromeBottomBar(
      bookTitle: widget.bookTitle,
```

改為：

```dart
    return ReaderChromeBottomBar(
      bookTitle: _displayBookTitle,
```

修改 PDF 分支的 `ReaderChromeBottomBar`（第 2752-2785 行），把：

```dart
                child: ReaderChromeBottomBar(
                  bookTitle: widget.bookTitle,
```

改為：

```dart
                child: ReaderChromeBottomBar(
                  bookTitle: _displayBookTitle,
```

修改 `_buildFoliateHeaderText()`（第 2916-2937 行），把：

```dart
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle =
        currentPath.isEmpty ? widget.bookTitle : currentPath.first.title;
    return Container(
```

改為：

```dart
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty
        ? _displayBookTitle
        : convertText(currentPath.first.title, _textConversionMode);
    return Container(
```

修改 `_currentChapterTitle()`（第 2249-2258 行，目前無呼叫端、`// ignore: unused_element` 待活化方法——審查修正 M-1：避免未來重新啟用此方法時遺漏轉換），把：

```dart
  String _currentChapterTitle(BookFormat format) {
    if (format == BookFormat.pdf) {
      final currentPath =
          PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
      return currentPath.isEmpty ? widget.bookTitle : currentPath.last.title;
    }
    final currentPath =
        TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);
    return currentPath.isEmpty ? widget.bookTitle : currentPath.last.title;
  }
```

改為：

```dart
  String _currentChapterTitle(BookFormat format) {
    if (format == BookFormat.pdf) {
      final currentPath =
          PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
      return currentPath.isEmpty
          ? _displayBookTitle
          : convertText(currentPath.last.title, _textConversionMode);
    }
    final currentPath =
        TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);
    return currentPath.isEmpty
        ? _displayBookTitle
        : convertText(currentPath.last.title, _textConversionMode);
  }
```

此方法目前無呼叫端（私有方法且僅同檔案可存取），測試無法從外部驗證，故不新增對應測試——單純防止未來解註解啟用時產生字形遺漏。

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增 6 個測試通過）。

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(reader): ReaderScreen 頁首/底部工具列/單書搜尋/目錄/筆記接上簡繁顯示轉換"
```

---

### Task 4: `LibraryScreen` 跨書情境接線（書架書名/作者）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/library/widgets/book_cover.dart`
- Test: `app/test/screens/library_screen_test.dart`
- Test: `app/test/library/widgets/book_cover_test.dart`

**Interfaces:**
- Consumes: `GlobalReaderPrefs.reading.textConversion`（Issue 1）、`convertText(String, TextConversionMode)`（Issue 0）。
- Produces: `BookCover.textConversion`（`TextConversionMode`，預設 `TextConversionMode.original`，向後相容既有 8 處呼叫點），供本 Task 內 `_BookGridTile`／`_BookListTile`／`_ContinueReadingRow` 消費，其餘既有呼叫點（`layout_preset_book_picker_screen.dart`、`library_screen.dart` 的 `_GroupGridTile`／`_GroupListTile`、`library_search_screen.dart`）維持預設值不變，本 Task 不擴及。`_LibraryScreenState._textConversion` 為純內部狀態，不對外公開（本計畫最後一個 Task）。

- [x] **Step 1: 新增失敗測試**

**審查修正 C-1**：`BookCover` 在書籍無 `coverPath` 時會退回 `CoverPlaceholder` 繪製書名縮略文字（`app/lib/library/widgets/book_cover.dart:41-44`／`:122-157`，容器高度 ≥56dp 且寬度 ≥36dp 時顯示）——`_BookGridTile`／`_BookListTile`（48×64）／`_ContinueReadingRow`（40×56）三處的 `BookCover` 尺寸皆超過此門檻，因此測試環境下每個書籍項目同時存在「封面縮略文字」與「卡片/列標題文字」兩處書名渲染，需一併修改 `BookCover` 才能讓兩處轉換結果一致（否則會出現封面縮略仍是簡體、標題已是繁體的畫面不一致，且下方 Task 4 測試斷言在只改標題不改封面時必定矛盾失敗）。

在 `app/test/library/widgets/book_cover_test.dart` 第 4 行（`import 'package:elinkbook/library/widgets/book_cover.dart';`）之後新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

修改第 9-20 行的 `_book()` helper，新增可選的 `title` 參數（預設沿用既有硬編碼書名，向後相容既有 4 個測試）：

```dart
Book _book({required bool isDownloaded, String title = '測試書'}) {
  return Book(
    id: 'b1',
    title: title,
    format: BookFileFormat.epub,
    filePath: '/books/b1.epub',
    source: BookSource.calibreOpds,
    isDownloaded: isDownloaded,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}
```

找到第 51-64 行「E-Ink 模式開啟時」測試結尾的 `});`，在其後、`main()` 結尾的 `}`（第 65 行）之前新增：

```dart

  testWidgets(
      'textConversion: toTraditional 時，CoverPlaceholder 書名縮略套用簡繁轉換（epic-42-text-conversion Issue 3）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(
        book: _book(isDownloaded: true, title: '国电脑'),
        textConversion: TextConversionMode.toTraditional,
      ),
    ));

    expect(find.text('國電腦'), findsOneWidget);
    expect(find.text('国电脑'), findsNothing);
  });
```

在 `app/test/screens/library_screen_test.dart` 找到第 583-608 行「切換檢視模式按鈕後，書架從 grid 切換為列表呈現」測試之前，新增以下 6 個測試（作為新的一組，插在該測試之前；Test 1／Test 2 的書名斷言數量已依上方 `BookCover` 轉換一併修正為 `findsNWidgets(2)`，反映封面縮略文字與標題文字各顯示一次已轉換文字的既有畫面結構，比照 `library_screen_test.dart:160-168` 既有測試慣例）：

```dart
  testWidgets('全域簡繁轉換為繁體時，書架格狀視圖書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 書名縮略與卡片下方標題文字各顯示一次，比照既有測試慣例',
    );
    expect(find.text('国电脑'), findsNothing);
  });

  testWidgets('全域簡繁轉換為繁體時，書架列表視圖書名／作者依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑', author: '电脑作者');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 書名縮略與列標題文字各顯示一次，比照既有測試慣例',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('電腦作者'),
      ),
      findsOneWidget,
      reason: '作者僅顯示於列表副標題，CoverPlaceholder 不含作者欄位',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，繼續閱讀列書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '国电脑',
      lastReadTime: DateTime(2026, 1, 1),
    );
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('library_continue_reading_row')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'BookCover 退回文字縮略與 _ContinueReadingRow 標題文字各顯示一次，比照既有測試慣例',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，書籍詳細資料對話框書名／作者依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑', author: '电脑作者');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細資料'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_details_dialog')),
        matching: find.text('國電腦'),
      ),
      findsOneWidget,
    );
    expect(find.text('作者：電腦作者'), findsOneWidget);
  });

  testWidgets('外部刷新訊號觸發時，重新載入全域簡繁轉換預設值（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: false),
      ),
    );
    final refreshSignal = ChangeNotifier();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
          refreshSignal: refreshSignal,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('国电脑'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與卡片標題各顯示一次，比照既有測試慣例（轉換前，審查修正 C-1 落地後兩處皆顯示同一文字）',
    );

    localPrefsManager.globalPrefs = localPrefsManager.globalPrefs.copyWith(
      reading: const ReadingDefaults(
        openLastBookOnLaunch: false,
        textConversion: TextConversionMode.toTraditional,
      ),
    );
    refreshSignal.notifyListeners();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與卡片標題各顯示一次，比照既有測試慣例（轉換後）',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，單書動作選單頂部標題依轉換模式呈現（epic-42-text-conversion Issue 3，審查修正 I-1）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.text('國電腦'), findsWidgets,
        reason: '書架卡片（CoverPlaceholder 縮略＋標題）與動作選單頂部標題皆顯示已轉換文字');
    expect(find.text('国电脑'), findsNothing);
  });

```

在檔案頂部 import 區塊（`import 'package:elinkbook/reader/global_reader_prefs.dart';` 一行之後）新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/widgets/book_cover_test.dart test/screens/library_screen_test.dart`
Expected: `book_cover_test.dart` 新增的 1 個測試、`library_screen_test.dart` 新增的 6 個測試皆 FAIL（`BookCover`／`_BookGridTile`／`_BookListTile`／`_ContinueReadingRow`／`_BookDetailsDialog` 尚未接受 `textConversion` 參數，編譯錯誤；`_openBookActionSheet` 標題斷言值仍是未轉換的原文「国电脑」）。

- [x] **Step 3: 實作接線**

在 `app/lib/screens/library_screen.dart` 第 1 行（`import 'dart:io';`）之前新增：

```dart
import 'dart:async';

```

在第 24 行（`import '../reader/reader_prefs_manager.dart';`）之後新增：

```dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 145 行（`Book? _mostRecentBook;`）之後新增：

```dart

  /// 簡繁顯示轉換全域預設值（FR-48，「跨書情境」規則，epic-42-text-
  /// conversion Issue 3：書架畫面一律採全域預設，不做單書覆寫，見
  /// resolve_text_conversion.dart 文件註解）。載入完成前維持
  /// `TextConversionMode.original`（與 `ReadingDefaults` 硬編碼預設值
  /// 一致），避免短暫顯示原文後才套用轉換的畫面跳動。
  TextConversionMode _textConversion = TextConversionMode.original;
```

修改 `_onExternalRefreshRequested()`（第 166-169 行），把：

```dart
  void _onExternalRefreshRequested() {
    _bookListController.loadBooks();
    _bookListController.loadGroups();
  }
```

改為：

```dart
  void _onExternalRefreshRequested() {
    _bookListController.loadBooks();
    _bookListController.loadGroups();
    unawaited(_reloadTextConversion());
  }
```

修改 `_initialize()`（第 252-258 行），把：

```dart
  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }
```

改為（審查修正 I-2：`_initialize()` 原稿以 `unawaited(_reloadTextConversion())` 讓「讀全域偏好」與「讀書籍清單」並行，但 `_bookListController.initialLoad()` 完成時會觸發 `_onBookListChanged()` → `setState()` 先行重繪書架，此時 `_textConversion` 很可能仍是尚未載入完成的預設值 `original`，使用者會看到書架先以原文閃現、緊接著才跳變為轉換後文字——與本欄位文件註解「避免畫面跳動」的設計目的直接矛盾。改為 `await` 讓 `_reloadTextConversion()` 完整落地〔含其內部 `setState()`〕後才進入書籍清單載入，徹底消除這個競態與閃爍）：

```dart
  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _reloadTextConversion();
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }

  /// 重新載入全域簡繁顯示轉換預設值（epic-42-text-conversion Issue 3）：
  /// 初次啟動（`_initialize()`，`await` 等待完成後才載入書籍清單，避免
  /// 啟動畫面文字閃爍，審查修正 I-2）與「設定」分頁切回書架時（見
  /// `_onExternalRefreshRequested()`，`unawaited`——`AdaptiveShellScaffold`
  /// 用 `IndexedStack` 讓 `LibraryScreen` 全程保持掛載，使用者在「設定」
  /// 分頁變更全域預設值後切回書架不會自動重新 build()，需要這個訊號主動
  /// 重新整理；此處書架已完整渲染過，不存在「初次繪製前」的閃爍疑慮，故
  /// 沿用既有「來源」分頁匯入新書後的 `unawaited` 既定模式）各觸發一次。
  Future<void> _reloadTextConversion() async {
    final globalPrefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _textConversion = globalPrefs.reading.textConversion);
  }
```

修改 `_showBookDetails()`（第 660-672 行），把：

```dart
    showDialog<void>(
      context: context,
      builder: (context) => _BookDetailsDialog(book: book),
    );
```

改為：

```dart
    showDialog<void>(
      context: context,
      builder: (context) =>
          _BookDetailsDialog(book: book, textConversion: _textConversion),
    );
```

修改 `_openBookActionSheet()`（第 630-644 行，審查修正 I-1：原稿遺漏此處——使用者點擊書籍卡片「⋮」按鈕開啟的動作選單，其 `EBSheetShell.show` 頂部大標題若不轉換，會與下方已轉換的卡片標題字形割裂），把：

```dart
  Future<void> _openBookActionSheet(Book book) async {
    final showRemoveCache =
        book.source == BookSource.calibreOpds && book.isDownloaded;
    final bookReaderPrefsRepository =
        widget.readerFeatureRepositories.bookReaderPrefsRepository;
    final result = await EBSheetShell.show<BookAction>(
      context,
      title: book.title,
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache: showRemoveCache,
        showLayoutOverride: bookReaderPrefsRepository != null,
      ),
    );
```

改為：

```dart
  Future<void> _openBookActionSheet(Book book) async {
    final showRemoveCache =
        book.source == BookSource.calibreOpds && book.isDownloaded;
    final bookReaderPrefsRepository =
        widget.readerFeatureRepositories.bookReaderPrefsRepository;
    final result = await EBSheetShell.show<BookAction>(
      context,
      title: convertText(book.title, _textConversion),
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache: showRemoveCache,
        showLayoutOverride: bookReaderPrefsRepository != null,
      ),
    );
```

修改 `_buildBookList()` 內的 `itemBuilder`（第 1104-1121 行），把：

```dart
      final book = visibleBooks[globalIndex - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
            );
```

改為：

```dart
      final book = visibleBooks[globalIndex - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
              textConversion: _textConversion,
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
              textConversion: _textConversion,
            );
```

修改 `_ContinueReadingRow` 呼叫點（第 1129-1137 行），把：

```dart
          _ContinueReadingRow(
            book: _mostRecentBook!,
            // 多選模式進行中時停用點擊（`review-plan-issue-3.md` M-3）：
            // 本列沒有勾選指示器，若不停用，使用者在多選時點到它會在
            // 毫無視覺反饋的情況下切換 _mostRecentBook 的選取狀態，比照
            // `_GroupGridTile`／`_GroupListTile` 在 _inSelectionMode 時
            // 一律把 onTap 傳 null 的既有慣例。
            onTap: _inSelectionMode ? null : () => _onBookTap(_mostRecentBook!),
          ),
```

改為：

```dart
          _ContinueReadingRow(
            book: _mostRecentBook!,
            // 多選模式進行中時停用點擊（`review-plan-issue-3.md` M-3）：
            // 本列沒有勾選指示器，若不停用，使用者在多選時點到它會在
            // 毫無視覺反饋的情況下切換 _mostRecentBook 的選取狀態，比照
            // `_GroupGridTile`／`_GroupListTile` 在 _inSelectionMode 時
            // 一律把 onTap 傳 null 的既有慣例。
            onTap: _inSelectionMode ? null : () => _onBookTap(_mostRecentBook!),
            textConversion: _textConversion,
          ),
```

修改 `app/lib/library/widgets/book_cover.dart`（審查修正 C-1：`BookCover` 無 `coverPath` 時退回 `CoverPlaceholder` 繪製書名縮略文字，容器尺寸 ≥56×36dp 時就會顯示——`_BookGridTile`／`_BookListTile`（48×64）／`_ContinueReadingRow`（40×56）三處皆超過此門檻，若不一併轉換，封面縮略文字會與卡片/列標題文字顯示不同字形，本 Task 只轉換標題會造成畫面不一致）。在第 7 行（`import '../../theme/elink_tokens.dart';`）之後新增：

```dart
import '../../reader/text_conversion.dart';
import '../../reader/text_conversion_mode.dart';
```

修改 `BookCover` 類別（第 29-44 行），把：

```dart
class BookCover extends StatelessWidget {
  final Book book;

  const BookCover({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final coverPath = book.coverPath;
    final coverContent = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : CoverPlaceholder(
            icon: bookFormatIcon(book.format),
            title: book.title,
          );
```

改為：

```dart
class BookCover extends StatelessWidget {
  final Book book;

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 3）：套用在
  /// 無封面圖時 `CoverPlaceholder` 繪製的書名縮略文字上，避免與卡片/列
  /// 標題文字字形不一致。預設 `TextConversionMode.original`（不轉換，
  /// 向後相容既有呼叫端，例如 `layout_preset_book_picker_screen.dart`、
  /// `_GroupGridTile`／`_GroupListTile`、`library_search_screen.dart`）。
  final TextConversionMode textConversion;

  const BookCover({
    super.key,
    required this.book,
    this.textConversion = TextConversionMode.original,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final coverPath = book.coverPath;
    final coverContent = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : CoverPlaceholder(
            icon: bookFormatIcon(book.format),
            title: convertText(book.title, textConversion),
          );
```

修改 `_BookGridTile` 類別（第 1455-1470 行），把：

```dart
class _BookGridTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
  });
```

改為：

```dart
class _BookGridTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  final TextConversionMode textConversion;

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
    required this.textConversion,
  });
```

修改 `_BookGridTile.build()` 的 `BookCover`（原第 1487 行，審查修正 C-1），把：

```dart
                BookCover(book: book),
```

改為：

```dart
                BookCover(book: book, textConversion: textConversion),
```

修改 `_BookGridTile.build()` 的書名 `Text`（原第 1546-1552 行），把：

```dart
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
```

改為：

```dart
                Text(
                  convertText(book.title, textConversion),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
```

修改 `_BookListTile` 類別（原第 1570-1585 行），把：

```dart
class _BookListTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
  });
```

改為：

```dart
class _BookListTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  final TextConversionMode textConversion;

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
    required this.textConversion,
  });
```

修改 `_BookListTile.build()` 的 `BookCover`（原第 1611 行，審查修正 C-1），把：

```dart
            SizedBox(width: 48, height: 64, child: BookCover(book: book)),
```

改為：

```dart
            SizedBox(
              width: 48,
              height: 64,
              child: BookCover(book: book, textConversion: textConversion),
            ),
```

修改 `_BookListTile.build()` 的書名／作者 `Text`（原第 1618-1622 行），把：

```dart
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        book.author ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
```

改為：

```dart
      title: Text(convertText(book.title, textConversion),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        convertText(book.author ?? '', textConversion),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
```

修改 `_ContinueReadingRow` 類別（原第 1654-1658 行），把：

```dart
class _ContinueReadingRow extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap; // null＝多選模式進行中，停用點擊（見呼叫端註解）

  const _ContinueReadingRow({required this.book, required this.onTap});
```

改為：

```dart
class _ContinueReadingRow extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap; // null＝多選模式進行中，停用點擊（見呼叫端註解）
  final TextConversionMode textConversion;

  const _ContinueReadingRow({
    required this.book,
    required this.onTap,
    required this.textConversion,
  });
```

修改 `_ContinueReadingRow.build()` 的 `BookCover`（原第 1669 行，審查修正 C-1），把：

```dart
            SizedBox(width: 40, height: 56, child: BookCover(book: book)),
```

改為：

```dart
            SizedBox(
              width: 40,
              height: 56,
              child: BookCover(book: book, textConversion: textConversion),
            ),
```

修改 `_ContinueReadingRow.build()` 的書名 `Text`（原第 1677-1682 行），把：

```dart
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
```

改為：

```dart
                  Text(
                    convertText(book.title, textConversion),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
```

修改 `_BookDetailsDialog` 類別（原第 1701-1703 行），把：

```dart
class _BookDetailsDialog extends StatefulWidget {
  final Book book;
  const _BookDetailsDialog({required this.book});
```

改為：

```dart
class _BookDetailsDialog extends StatefulWidget {
  final Book book;
  final TextConversionMode textConversion;
  const _BookDetailsDialog({required this.book, required this.textConversion});
```

修改 `_BookDetailsDialogState.build()`（原第 1751-1756 行與 1771 行），把：

```dart
  Widget build(BuildContext context) {
    final book = widget.book;
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(book.title),
```

改為：

```dart
  Widget build(BuildContext context) {
    final book = widget.book;
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(convertText(book.title, widget.textConversion)),
```

再把（原第 1771 行）：

```dart
              Text('作者：${book.author ?? '未知'}'),
```

改為：

```dart
              Text(
                '作者：${book.author == null ? '未知' : convertText(book.author!, widget.textConversion)}',
              ),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/widgets/book_cover_test.dart test/screens/library_screen_test.dart`
Expected: 全數 PASS（既有測試零回歸＋ `book_cover_test.dart` 新增 1 個測試、`library_screen_test.dart` 新增 6 個測試通過）。

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: 執行完整 `flutter test`（本計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過（既有已知不穩定案例除外，例如 `adaptive_shell_scaffold_test.dart` 既有失敗案例，非本次異動引入）。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/library/widgets/book_cover.dart app/test/screens/library_screen_test.dart app/test/library/widgets/book_cover_test.dart
git commit -m "feat(library): LibraryScreen 書架書名/作者接上全域簡繁顯示轉換"
```

---

## Self-Review

**Spec 覆蓋度**：對照 `issues.md` Issue 3「範圍」逐項核對——(1) `BookTocItem.title`（目錄面板）→ Task 1；(2) 書籤清單章節名稱（`bookmark.name`）→ Task 2；(3) 劃線清單摘要片段 → **無對應程式碼可修改**（見下方「已知落差」，已與使用者確認略過並在 Global Constraints／Task 2 註記）；(4) `_buildFoliateHeaderText()`／`ReaderChromeBottomBar`（流式+PDF 共 2 處）→ Task 3；(5) 單書搜尋標題（`_buildSearchableBook()` → `BookSearchScreen` AppBar）→ Task 3（已與使用者確認範圍僅限 `ReaderScreen` 入口，`LibrarySearchScreen` 下鑽入口另計）；(6) 備註文字不受影響 → Task 2 測試明確覆蓋；(7) 書架書名/作者依全域預設值、不受單書覆寫影響 → Task 4（`LibraryScreen` 全程只讀 `GlobalReaderPrefs.reading.textConversion`，未讀取任何 `BookReaderPrefs`）。六項單元測試要求皆已對應到具體 Task 步驟。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼區塊，測試斷言使用既有已驗證字元對「国电脑」→「國電腦」（`test/reader/text_conversion_test.dart` 既有測試向量），未自行發明字元映射。

**型別一致性**：`TocBottomSheet.textConversion`／`NotesBottomSheet.textConversion`／`BookCover.textConversion`／`_BookGridTile.textConversion`／`_BookListTile.textConversion`／`_ContinueReadingRow.textConversion`／`_BookDetailsDialog.textConversion` 全部同為 `TextConversionMode` 型別、同一參數命名；`_ReaderScreenState._textConversionMode` getter 回傳型別亦為 `TextConversionMode`，命名刻意加 `Mode` 後綴以區別於（僅 `ReaderScreen` 內部使用的）`_displayBookTitle`／`_displayBookAuthor` 兩個衍生字串 getter，三者無互相覆蓋或型別不一致的風險。

**已知落差（與使用者確認的處理方式）**：issues.md Issue 3 原始範圍寫「劃線清單摘要片段（僅摘要片段，不含備註文字本身）」需轉換，但逐一查證 `Highlight` model 與所有讀取它的畫面（`notes_bottom_sheet.dart`／`markdown_export.dart`／`annotation_list_item.dart`）後，確認本專案從未儲存劃線框住的原文片段——這是 `markdown_export.dart:10-13` 記載的既有設計決策，劃線清單只顯示「樣式標籤＋位置標籤」。使用者確認的處理方式是「略過，計劃中註記此落差」（已於 Global Constraints 與 Task 2 程式碼註解落地），供之後校訂 `spec.md`／`design.md` 參考，不在本計畫新增對應程式碼。

**已與使用者確認的範圍界線**：`BookSearchScreen` 的 AppBar 書名/作者轉換只處理 `ReaderScreen._buildSearchableBook()`（單書搜尋，明確單書情境）這一個入口，`LibrarySearchScreen._openBookSearch()`（全庫搜尋下鑽單書搜尋）維持現狀不轉換，留給後續 Issue 4（全文檢索）或另立工單處理一致性；此為使用者明確選擇的處理方式，非遺漏。

**審查修訂記錄**（`reviews/review-plan-issue-3.md`）：C-1（`BookCover`／`CoverPlaceholder` 遺漏轉換導致 Task 4 測試斷言邏輯矛盾）與 I-1（`_openBookActionSheet` 動作選單標題漏轉）、I-2（`_initialize()` 的 `unawaited` 造成啟動畫面閃爍競態）、M-1（`_currentChapterTitle()` 待活化方法字形遺漏）均已採納並落地於 Task 3／Task 4。M-2（Task 4 Step 6 全套 `flutter test` 建議改為限定目標測試清單）**不採納**：專案 `CLAUDE.md`「測試執行範圍」明文規定完整 `flutter test` 僅在整張計畫最後一個 Task 執行一次，`plan-issue-1.md`／`plan-issue-2.md` 皆遵循同一慣例；且本計畫 Step 6 原稿已明確列出「既有已知不穩定案例除外」的例外條款，M-2 描述的風險已被既有寫法涵蓋，改為限定清單反而會弱化全套回歸驗證的覆蓋範圍，故維持原寫法。`BookCover` 新增的 `textConversion` 只接到本 Task 已修改的三個消費端（`_BookGridTile`／`_BookListTile`／`_ContinueReadingRow`），`layout_preset_book_picker_screen.dart`／`_GroupGridTile`／`_GroupListTile`／`library_search_screen.dart` 等既有呼叫點不在本 Issue 範圍內、維持預設值不變，避免未經審查確認的範圍擴張。

**Issue 3 程式審查修訂記錄**（`reviews/review-issue-3.md`，審查對象為 `feat/epic-42-issue-3` 分支 `906afb1b..4a0e5e8e` 的實作）：Important #1——`_buildTtsController()`（`reader_screen.dart:3145`）呼叫 `widget.ttsAudioHandler?.attachController()` 時仍傳入未轉換的 `widget.bookTitle`，寫入 `MediaItem.title` 後會讓 Android 系統通知欄/鎖定畫面顯示原文書名。此呼叫點從未列在 `issues.md` Issue 3「範圍」或本計畫的 File Structure／Task 列表中，是 issues.md 原始範圍本身的疏漏、非本計畫或實作對已核准計畫的偏離，已在後續 commit（`fix(reader): TTS 系統通知/鎖定畫面書名接上簡繁顯示轉換`）補上，改傳 `_displayBookTitle`，並於「背景播放與系統整合（epic-34-tts-readalong Issue 7）」測試群組新增對應測試。Minor #1——Task 4 Step 1 的「外部刷新訊號觸發時」與「單書動作選單頂部標題」兩則測試，本文件原稿的 `findsOneWidget` 斷言在 C-1 修正（`BookCover` 一併轉換）落地後會自相矛盾（畫面此時同時存在封面縮略與卡片/選單標題等多處已轉換文字），實作階段已正確訂正為 `findsNWidgets(2)`／`findsWidgets`，本文件上方兩則測試程式碼已同步更新以反映實際落地版本。
