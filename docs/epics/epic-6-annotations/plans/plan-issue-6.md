# Epic 6 — Issue 6：正式圖書庫流程貫穿 highlightsRepository／notesRepository 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 `LibraryScreen._openBook()` 未貫穿 `highlightsRepository`／`notesRepository` 給 `ReaderScreen` 的既有缺口，讓一般使用者透過書架開書時，Issue 2/3 建立的劃線/備註功能（含 Issue 5 的 Markdown 導出）在正式流程中確實生效。

**Architecture:** 這不是新功能，是既有貫穿鏈路（`main.dart` → `ElinkBookApp` → `LibraryScreen` → `ReaderScreen`）缺一段的補齊。`ReaderScreen` 本身早已支援可選的 `highlightsRepository`／`notesRepository` 建構參數（Issue 2/3 已完成），`main.dart` 也已示範過同一套「建構真實 Repository → 逐層以可選具名參數往下傳」的模式（`bookmarksRepository`，Issue 1）。本工單只需在 `LibraryScreen`／`ElinkBookApp`／`main.dart` 三層依樣新增這兩個欄位並貫穿，不改動任何既有行為。

**Tech Stack:** Flutter/Dart，`sqflite`（`HighlightsRepository`／`NotesRepository` 底層），既有 `flutter_test` widget test 架構（`sqflite_common_ffi` 供純 Dart 測試環境使用）。

## Global Constraints

- 所有指令皆在 `app/` 目錄下執行（`flutter test`／`flutter analyze`）。
- `flutter analyze` 完成後必須輸出「No issues found!」，不得殘留警告或錯誤。
- 新增的 `highlightsRepository`／`notesRepository` 欄位，在 `LibraryScreen`／`ElinkBookApp` 兩層皆須為**可選具名參數**（`HighlightsRepository?`／`NotesRepository?`，預設 `null`），比照既有 `bookmarksRepository` 的既有注入模式——確保既有測試呼叫端（未提供此參數）不因新增 `required` 參數而編譯失敗。
- 不新增 Method Channel Mock 基礎設施（`spec.md`「Testing Decisions」明定的既有慣例）：`app/test/` 環境下 `EpubReaderView`／`PdfReaderView` 的 `_channel` 恆為 `null`，所有原生呼叫皆以 `_channel?.invokeMethod(...)` null-safe 寫法安全 no-op。
- `ReaderScreen` 是唯一的閱讀器 seam（`CLAUDE.md` 明訂），本工單不新增測試接縫，一律透過 `LibraryScreen` → `ReaderScreen` 的既有公開行為斷言。
- 程式碼註解與測試描述文字一律使用正體中文（`CLAUDE.md` 專案慣例）。
- 本工單純粹是貫穿缺口的修正，不得順手更動 `ReaderScreen`／`NotesBottomSheet`／`HighlightsRepository`／`NotesRepository` 既有行為或簽章。

---

## 檔案結構總覽

| 檔案 | 異動類型 | 責任 |
|---|---|---|
| `app/lib/screens/library_screen.dart` | 修改 | 新增 `highlightsRepository`／`notesRepository` 欄位，`_openBook()` 貫穿給 `ReaderScreen` |
| `app/lib/main.dart` | 修改 | 建構真實 `HighlightsRepository`／`NotesRepository`，經 `ElinkBookApp` 貫穿到 `LibraryScreen` |
| `app/test/screens/library_screen_test.dart` | 修改（新增測試） | 驗證貫穿正確性（建構參數）＋端到端資料顯示＋ Markdown 導出回歸 |

---

### Task 1: `LibraryScreen` 新增 `highlightsRepository`／`notesRepository` 欄位並貫穿至 `ReaderScreen`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：既有 `HighlightsRepository`（`app/lib/reader/highlights_repository.dart`）、`NotesRepository`（`app/lib/reader/notes_repository.dart`）、既有 `ReaderScreen` 建構參數 `highlightsRepository`／`notesRepository`（`HighlightsRepository?`／`NotesRepository?`，已存在，Issue 2/3 建立）。
- Produces：`LibraryScreen` 新增兩個可選具名建構參數 `highlightsRepository`（`HighlightsRepository?`）、`notesRepository`（`NotesRepository?`），供 Task 2（端到端測試）與 Task 3（`main.dart` 接線）使用。

- [x] **Step 1: 於 `library_screen_test.dart` 撰寫失敗測試——驗證 `LibraryScreen` 建構參數正確貫穿給 `ReaderScreen`**

先在檔案頂部新增必要 import（`package:elinkbook/screens/reader_screen.dart`、`../support/fake_highlights_repository.dart`、`../support/fake_notes_repository.dart`），置於既有 import 區塊最後（`import '../support/fake_reader_prefs_manager.dart';` 之後）：

```dart
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
```

於 `main()` 內、`}` 結尾（`_testBook` 輔助函式之前，即現有最後一個 `testWidgets` 區塊之後）新增：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 highlightsRepository／notesRepository 正確貫穿（Issue 6 缺口修正）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView，比照既有「從閱讀器返回書架」測試的既有
    // 做法）——本測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.highlightsRepository, same(highlightsRepository),
        reason: 'LibraryScreen._openBook() 修正前，highlightsRepository 從未'
            '貫穿給 ReaderScreen，一律為 null（見 issues.md Issue 6 背景）');
    expect(readerScreen.notesRepository, same(notesRepository));
  });
```

- [x] **Step 2: 執行測試，確認因編譯錯誤而失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: 編譯失敗，錯誤訊息類似 `The named parameter 'highlightsRepository' isn't defined`（`LibraryScreen` 建構子尚未接受此參數）。

- [x] **Step 3: 於 `library_screen.dart` 新增欄位並貫穿至 `ReaderScreen`**

於檔案頂部 import 區塊新增（置於既有 `import '../reader/bookmarks_repository.dart';` 之後）：

```dart
import '../reader/bookmarks_repository.dart';
import '../reader/highlights_repository.dart';
import '../reader/notes_repository.dart';
import '../reader/reader_prefs_manager.dart';
```

於 `class LibraryScreen extends StatefulWidget` 的欄位宣告區，`final BookmarksRepository? bookmarksRepository;` 之後新增：

```dart
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final AppTheme currentTheme;
```

於建構子 `this.bookmarksRepository,` 之後新增：

```dart
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
  });
```

於 `_openBook(Book book)` 方法內，`ReaderScreen(...)` 建構呼叫中，`bookmarksRepository: widget.bookmarksRepository,` 之後新增：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
            ),
          ),
        )
        .then((_) {
      _loadBooks();
    });
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部既有案例＋新增案例）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "fix(epic-6): LibraryScreen 貫穿 highlightsRepository／notesRepository 給 ReaderScreen"
```

---

### Task 2: 端到端測試——透過 `LibraryScreen` 開啟已有劃線/備註資料的 PDF 書籍，驗證「劃線與備註」分頁正確顯示既有資料

**Files:**
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 完成後的 `LibraryScreen.highlightsRepository`／`notesRepository`；既有 `NotesBottomSheet` 的 Key 契約（`reader_notes_button`、`notes_sheet_tab_annotations`、`notes_sheet_annotation_list`、`notes_sheet_annotations_placeholder`，Issue 1/2 已建立）；既有 `PdfReaderView.onPageRendered` 回呼（Issue 0 已建立）。
- Produces：無新增生產程式碼介面——本 Task 純粹是建立在 Task 1 之上的端到端覆蓋測試，驗證整條貫穿鏈路（`LibraryScreen` → `ReaderScreen` → `NotesBottomSheet`）在真實資料下確實生效，非空狀態。

本 Task 不需要修改任何 `app/lib/` 下的程式碼——Task 1 已完成貫穿本身，這裡只是加上先前 Issue 2/3/5 審查時發現、但直到 Task 1 才真正修正的那個「正式流程完全接觸不到」缺口的迴歸覆蓋測試。因此本 Task 的測試預期**撰寫後立即通過**（不會經歷紅燈），下方 Step 2 會明確驗證這一點並說明原因。

- [x] **Step 1: 於 `library_screen_test.dart` 新增 import 與端到端測試**

於檔案頂部新增（`import '../support/fake_notes_repository.dart';` 之後，注意 Task 1 已加入該行）：

```dart
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import '../support/fake_bookmarks_repository.dart';
```

於 `main()` 內、Task 1 新增的測試之後新增：

```dart
  testWidgets(
      '透過 LibraryScreen 開啟已有劃線/備註資料的 PDF 書籍後，'
      '「劃線與備註」分頁正確顯示既有資料而非空狀態（Issue 6 缺口修正）',
      (tester) async {
    final book = Book(
      id: '1',
      title: '測試 PDF',
      author: '測試作者',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(const Highlight(
      bookId: '1',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // PDF 的「📚 筆記」按鈕須等 onPageRendered 觸發後才可點擊（既有防呆
    // 邏輯，見 reader_screen_test.dart 既有先例）；app/test/ 環境下原生
    // _channel 恆為 null，改為直接呼叫 PdfReaderView 的公開回呼模擬。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    final notesButton = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(notesButton).onPressed, isNotNull);

    await tester.tap(notesButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget,
        reason: '修正前 highlightsRepository／notesRepository 永遠為 null，'
            '此分頁只會顯示空狀態佔位符（見 issues.md Issue 6 背景）');
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsNothing,
    );
  });
```

- [x] **Step 2: 執行測試，確認通過（本 Task 無新增生產程式碼，屬於 Task 1 的迴歸覆蓋）**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS。若失敗，代表 Task 1 的貫穿有誤（例如 `NotesBottomSheet` 收到的 `highlightsRepository`／`notesRepository` 仍為 `null`），須回頭檢查 Task 1 的 `_openBook()` 修改，而非在本 Task 新增額外生產程式碼。

- [x] **Step 3: 執行 `flutter analyze`，確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 4: Commit**

```bash
git add app/test/screens/library_screen_test.dart
git commit -m "test(epic-6): 端到端驗證 LibraryScreen 開書後劃線/備註資料正確顯示"
```

---

### Task 3: `main.dart`／`ElinkBookApp` 端到端接線——建構真實 `HighlightsRepository`／`NotesRepository` 並貫穿到 `LibraryScreen`

**Files:**
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes：Task 1 完成後的 `LibraryScreen.highlightsRepository`／`notesRepository`（`HighlightsRepository?`／`NotesRepository?`）；既有 `HighlightsRepository(Database)`／`NotesRepository(Database)` 建構子（Issue 2 已建立）；既有 `repository.database`（`SqliteLibraryRepository` 具象型別的 getter，`bookmarksRepository` 已示範的既有用法）。
- Produces：`ElinkBookApp` 新增兩個可選具名建構參數 `highlightsRepository`（`HighlightsRepository?`）、`notesRepository`（`NotesRepository?`），供真實 App 啟動時使用（本工單最後一段貫穿鏈路，之後不再有下一層需要消費此介面）。

`main.dart` 本身無對應的獨立測試檔（`app/test/` 目前無 `main_test.dart`，比照 Issue 1 `plan-issue-1.md` Task「接線 `LibraryScreen`／`ElinkBookApp`／`main.dart`」的既有先例，此層級的正確性由 `flutter analyze` 與全專案 `flutter test` 回歸驗證，不新增測試檔案）。

- [x] **Step 1: 於 `main.dart` 新增 import**

於檔案頂部 import 區塊新增（置於既有 `import 'reader/epub_character_count_repository.dart';` 之後，`import 'reader/reader_prefs_manager.dart';` 之前，維持既有字母序慣例）：

```dart
import 'reader/book_reader_prefs_repository.dart';
import 'reader/bookmarks_repository.dart';
import 'reader/epub_character_count_repository.dart';
import 'reader/highlights_repository.dart';
import 'reader/notes_repository.dart';
import 'reader/reader_prefs_manager.dart';
```

- [x] **Step 2: 於 `main()` 函式內建構真實 Repository 並貫穿至 `runApp(ElinkBookApp(...))`**

於 `final bookmarksRepository = BookmarksRepository(repository.database);` 之後新增：

```dart
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsManager: prefsManager,
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
    ),
  );
```

- [x] **Step 3: 於 `ElinkBookApp` 新增欄位並貫穿至 `LibraryScreen`**

於 `class ElinkBookApp extends StatefulWidget` 的欄位宣告區，`final BookmarksRepository? bookmarksRepository;` 之後新增：

```dart
class ElinkBookApp extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

於 `build()` 方法內 `LibraryScreen(...)` 建構呼叫中，`bookmarksRepository: widget.bookmarksRepository,` 之後新增：

```dart
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        bookmarksRepository: widget.bookmarksRepository,
        highlightsRepository: widget.highlightsRepository,
        notesRepository: widget.notesRepository,
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
      ),
```

- [x] **Step 4: 執行 `flutter analyze`，確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: 執行全專案測試，確認無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（既有 `ElinkBookApp(...)` 呼叫端因新欄位為可選具名參數，不受影響）。

- [x] **Step 6: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(epic-6): main.dart 建構真實 HighlightsRepository／NotesRepository 完成端到端接線"
```

---

### Task 4: Markdown 導出回歸測試——透過 `LibraryScreen` 開書的正式流程匯出，驗證內容包含實際劃線/備註

**Files:**
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1-3 完成後的完整貫穿鏈路；既有 `generateMarkdownExport`（`app/lib/reader/markdown_export.dart`，Issue 5 已建立，本 Task 不直接呼叫，透過 `NotesBottomSheet._exportMarkdown()` 間接觸發）；既有測試替身 `FakePathProviderPlatform`／`FakeSharePlatform`（`app/test/support/`，Issue 5 已建立）。
- Produces：無新增生產程式碼介面——本 Task 是 Issue 6 背景段落明確提到的既有 Bug（「目前正式圖書庫流程匯出的 Markdown 永遠只有書籤清單，劃線/備註段落固定顯示『尚未加入任何劃線或備註』」）的迴歸覆蓋測試，驗證該 Bug 經 Task 1-3 修正後不再重現。

- [x] **Step 1: 於 `library_screen_test.dart` 新增 import**

在檔案第一行 `import 'dart:async';` 之後新增 `dart:io`：

```dart
import 'dart:async';
import 'dart:io';
```

在既有 import 區塊最後（Task 2 新增的 `import '../support/fake_bookmarks_repository.dart';` 之後）新增：

```dart
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_share_platform.dart';
```

- [x] **Step 2: 新增端到端 Markdown 導出回歸測試**

於 `main()` 內、Task 2 新增的測試之後新增：

```dart
  testWidgets(
      '透過 LibraryScreen 開書的正式流程匯出 Markdown 後，內容包含該書實際的劃線/備註'
      '（Issue 6 缺口修正，回歸 Issue 5 審查發現的「永遠空狀態」問題）',
      (tester) async {
    // 【根因說明，比照 notes_bottom_sheet_test.dart 既有先例】真實
    // Directory.createTemp／File I/O 需要真正的作業系統事件迴圈，
    // AutomatedTestWidgetsFlutterBinding 的 fake Zone 無法完成，連
    // tester.tap() 本身也必須整個放進 tester.runAsync() 才能讓
    // _exportMarkdown() 從第一行就綁定真實 Zone。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_screen_markdown_export_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final originalPathProvider = PathProviderPlatform.instance;
    final originalSharePlatform = SharePlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final fakeShare = FakeSharePlatform();
    SharePlatform.instance = fakeShare;
    addTearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      SharePlatform.instance = originalSharePlatform;
    });

    final book = Book(
      id: '1',
      title: '測試 PDF',
      author: '測試作者',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(const Highlight(
      bookId: '1',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (fakeShare.lastParams == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    final content = await tester.runAsync(() => exportedFile.readAsString());
    expect(content, contains('### 📌 螢光筆（黃）（位置：第 1 頁）'),
        reason: '修正前 LibraryScreen 從未貫穿 highlightsRepository／'
            'notesRepository，匯出內容的劃線/備註段落永遠固定顯示'
            '「尚未加入任何劃線或備註」（見 issues.md Issue 6 背景）');
    expect(content, isNot(contains('*(尚未加入任何劃線或備註)*')));
  });
```

- [x] **Step 3: 執行測試，確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS

- [x] **Step 4: 執行全專案測試與 `flutter analyze`，確認無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（含既有 `library_screen_test.dart`／`reader_screen_test.dart` 全數案例）。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/test/screens/library_screen_test.dart
git commit -m "test(epic-6): 回歸驗證正式流程匯出 Markdown 確實包含實際劃線/備註"
```

---

## 完成後的驗收標準對應

- [x]（Task 1）`LibraryScreen._openBook()` 正確貫穿 `highlightsRepository`／`notesRepository` 給 `ReaderScreen`
- [x]（Task 2、Task 4）一般使用者透過書架開書後，劃線/備註功能（含 Issue 5 Markdown 導出）在正式流程中確實生效，不再固定顯示空狀態
- [x]（Task 1-4，每個 Task 皆執行全專案回歸）既有 `LibraryScreen`／`ReaderScreen` 相關測試維持全數通過，無回歸
- [x]（每個 Task 皆執行）上述測試皆通過，`flutter analyze` 乾淨
