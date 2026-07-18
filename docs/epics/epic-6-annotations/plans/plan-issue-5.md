# Epic 6 Issue 5：Markdown 導出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。步驟使用核取方塊（`- [x]`）語法追蹤進度。

**Goal:** 讓使用者在「📚 筆記」Bottom Sheet 內一鍵把目前這本書的書籤清單、劃線與個人備註匯出成一份 `.md` 檔案，並透過 Android 系統分享面板送出。

**Architecture:** 新增一個純函式模組（`generateMarkdownExport`）產生 Markdown 內容字串，完全複用 Issue 1/2/3 已建立的 `Bookmark`／`AnnotationListItem`／`mergeAnnotations`／`Bookmark.defaultName` 資料與純函式，不重新發明定位標籤邏輯。`NotesBottomSheet` 新增一顆「導出為 Markdown」按鈕，觸發後寫入 App 私有暫存目錄（`path_provider`）並透過新增的 `share_plus` 套件呼叫系統分享。`ReaderScreen`／`LibraryScreen` 各自新增一組唯讀的書名/作者/進度參數，沿既有的可選具名參數模式逐層貫穿到 `NotesBottomSheet`。

**Tech Stack:** Flutter/Dart（`path_provider`〔既有依賴〕、新增 `share_plus: ^13.2.1`），純 Dart 邏輯為主，**不涉及任何原生 Kotlin 程式碼變更**。

## Global Constraints

- **零 Kotlin／原生變更**：本工單完全是 Dart 層級的功能（純函式 + Flutter widget + 兩個官方支援可替換測試替身的聯邦式套件），不修改 `app/android/` 下任何檔案。
- **不重新發明定位標籤**：`prototype/index.html` 的 `exportMarkdown()` 原型格式骨架假設每筆劃線都存有「被劃線的原文文字」（`a.text`）與書籤的「章節＋CFI」；但本專案實際的 `Highlight`／`Note` 資料模型（`app/lib/reader/highlight.dart`／`note.dart`）**從未儲存被選取的原文內容**，只存定位資訊（EPUB：`epubLocatorJson`／`progression`；PDF：`pdfPageIndex`／`pdfRect`）。本計劃改為：劃線/備註條目一律顯示「樣式標籤＋位置標籤」，位置標籤直接複用已審查、已測試的 `Bookmark.defaultName(BookmarkPositionContext(...))`（`chapterTitle` 留空，天然回退為「NN% 處」／「第 N 頁」，與 Issue 1 既有行為一致，不需額外邏輯）；若該筆有依附的 `Note`，其 `text` 以引言區塊呈現。書籤清單直接顯示 `bookmark.name`（已是最終顯示名稱），不嘗試印出原始 Locator JSON 當作 CFI。
- **`Share.shareXFiles` 已於目前穩定版 `share_plus`（13.x）淘汰**（已查證，見 pub.dev 範例與原始碼），現行建議寫法是 `SharePlus.instance.share(ShareParams(files: [...], ...))`，回傳 `Future<ShareResult>`。本計劃採用此非淘汰 API，與 `issues.md` 原文字面提及的 `Share.shareXFiles` 用意相同（呼叫 `share_plus` 觸發系統分享），僅 API 名稱因套件版本演進而不同，屬技術更新非範疇偏離。
- **`FileProvider` 授權不衝突（已查證，見 `issues.md` 審查修正風險項）**：`share_plus` 的 Android 實作在自己的套件 Manifest 內註冊**另一個獨立的** `FileProvider`，authority 固定為 `${applicationId}.flutter.share_provider`——與本專案既有 `AndroidManifest.xml` 已宣告的 `${applicationId}.fileprovider`（`app/android/app/src/main/AndroidManifest.xml:33-41`）是兩個不同的 authority 字串，Android Manifest Merger 只在**同一個 authority 值**被兩個 `<provider>`宣告時才會衝突報錯，故不會衝突。`share_plus` 自己的 provider 內部已設定好能涵蓋任意合法應用程式路徑（含 `getTemporaryDirectory()`）的 `provider_paths`，這正是該套件存在的目的，不需要本專案自行新增或修改 `file_paths.xml`。本計劃以 Task 2 最後「`flutter build apk --debug` 建置成功」作為此結論的建置期驗證（Manifest Merger 若真的衝突會直接讓建置失敗），不修改任何 `.xml` 檔案。
- **`SharePlatform`／`PathProviderPlatform` 是官方支援可替換的聯邦式套件測試介面，不受本專案「不 mock 原生 method channel」既有慣例限制**（`issues.md` 已明文放行，見 Task 2）：`path_provider`（`path_provider_platform_interface`）與 `share_plus`（`share_plus_platform_interface`）皆採用 Flutter 官方「聯邦式套件」架構，各自的 `XxxPlatform.instance` 是可在測試中直接賦值替換的靜態欄位（`PlatformInterface` 基底類別的既定設計），不透過 `TestDefaultBinaryMessengerBinding` 模擬 method channel。這與本專案自行手刻的 `EpubReaderView`／`PdfReaderView` method channel（無此聯邦式介面層，才有「不 mock」的既有限制）是完全不同的機制，故可放心在 `flutter test`（無裝置）環境下驗證「按鈕觸發後正確寫入檔案並呼叫分享」全流程。
- **真實 Android Share Intent 會阻塞等待使用者操作**（已查證：`SharePlus.instance.share()` 在 Android 端透過 `startActivityForResult` 實作，回傳的 `Future` 要等到使用者在系統分享面板做出選擇或取消後才會 resolve）。**因此 `integration_test`（真機）一律不得實際點擊「導出為 Markdown」按鈕觸發真實分享**——`WidgetTester` 無法操作 Flutter 畫面以外的原生系統 UI，貿然點擊會讓自動化測試流程永久卡住等待人工介入、或讓遺留在畫面上的系統分享面板干擾同檔案後續測試。Task 3 的真機整合測試僅驗證按鈕在真機上正確渲染/可點擊（不實際點擊觸發分享），實際分享面板喚起與跨 App 讀取驗證另列入「真機人工驗證清單」，與 Issue 2/3 對原生手勢/渲染保留人工驗證項目的既有先例一致。
- **`ReaderScreen`/`NotesBottomSheet` 新參數的必填/可選設計**：`ReaderScreen` 新增的 `bookTitle`／`bookAuthor`／`bookProgress` 皆為**可選具名參數並附預設值**（比照 `bookmarksRepository` 等既有慣例），避免專案內已存在的六十餘處 `ReaderScreen(...)` 測試呼叫端需要逐一補參數；`NotesBottomSheet` 新增的同名三個參數則為**必填**，因為其唯一正式呼叫端 `ReaderScreen._openNotesSheet` 一定會提供值（不論是真實值或 `ReaderScreen` 自己的預設值），刻意不讓「忘記傳書名」這種情境被靜默吞掉成一個容易被忽略的「未知書籍」文字。
- **`bookProgress` 必須是即時值，不是開書當下的舊快照（審查修正 I-1）**：`widget.bookProgress` 只在 `ReaderScreen` 建構當下由 `LibraryScreen._openBook` 賦值一次，之後即使使用者在同一次閱讀 session 內持續翻頁，這個欄位本身**不會**自動更新（`Book.progress` 是持久化資料表欄位，非即時追蹤狀態）。若 `_openNotesSheet()` 直接透傳 `widget.bookProgress` 給 `NotesBottomSheet`，使用者翻到書的後段才匯出時，Markdown 內容的「閱讀進度」會顯示開書當下的舊值而非目前實際位置。修正做法：`_openNotesSheet()` 內改為即時計算——EPUB／FXL 用 `_epubPositionInfo?.progression`（此欄位由 `EpubReaderView.onLocatorChanged` 即時回報，`ReaderScreen` 既有其他功能，例如書籤定位上下文，本就已經在用這個欄位而非 `widget.bookProgress`，此處只是延續同一既有模式）；PDF 用 `_pdfPageInfo`（由 `onPageChanged` 即時回報）換算 `(pageIndex + 1) / totalPages`；兩者在對應欄位尚為 `null`（例如畫面剛渲染、回呼尚未觸發過）時才回退使用 `widget.bookProgress` 這個初始快照值，作為安全預設。見 Task 2 Step 6。
- **已知既有缺口（本工單範疇外，僅記錄不修正）**：查證後發現 `LibraryScreen._openBook()`（`app/lib/screens/library_screen.dart:276-289`）目前只把 `bookmarksRepository` 貫穿給 `ReaderScreen`，從未貫穿 `highlightsRepository`／`notesRepository`——這代表 Issue 2/3 建立的 EPUB/PDF 劃線備註功能，在正式圖書庫流程（而非測試或直接建構 `ReaderScreen`）中目前實際上是停用狀態。這是先於本工單即存在的既有缺口，與 Markdown 導出無關，本計劃**不修正**（避免範疇蔓延），僅在此記錄供人類後續決定是否另開工單修正。

---

## 檔案異動總覽

- **新增** `app/lib/reader/markdown_export.dart`：`generateMarkdownExport()` 純函式 + `sanitizeMarkdownFileName()` 純函式。
- **新增** `app/test/reader/markdown_export_test.dart`：涵蓋 issue 要求的 5 種組合＋檔名清理測試。
- **新增** `app/test/support/fake_path_provider_platform.dart`：`PathProviderPlatform` 測試替身。
- **新增** `app/test/support/fake_share_platform.dart`：`SharePlatform` 測試替身。
- **新增** `app/integration_test/markdown_export_test.dart`：真機整合測試（按鈕渲染/可點擊驗證，不觸發真實分享，見 Global Constraints）。
- **修改** `app/pubspec.yaml`：新增 `share_plus: ^13.2.1` 依賴。
- **修改** `app/lib/screens/notes_bottom_sheet.dart`：新增 `bookTitle`／`bookAuthor`／`bookProgress` 參數、「導出為 Markdown」按鈕與 `_exportMarkdown()` 處理方法。
- **修改** `app/test/screens/notes_bottom_sheet_test.dart`：`_pumpSheet` 輔助函式新增對應可選參數（預設值，既有 19 個呼叫端不需改動）、新增匯出按鈕的測試。
- **修改** `app/lib/screens/reader_screen.dart`：新增 `bookTitle`／`bookAuthor`／`bookProgress` 可選具名參數，`_openNotesSheet()` 貫穿給 `NotesBottomSheet`。
- **修改** `app/lib/screens/library_screen.dart`：`_openBook()` 貫穿 `book.title`／`book.author`／`book.progress`。

不修改：`bookmark.dart`、`highlight.dart`、`note.dart`、`annotation_list_item.dart`（含 `mergeAnnotations`）、`bookmarks_repository.dart`、`highlights_repository.dart`、`notes_repository.dart`、任何 `app/android/` 檔案、`sqlite_library_repository.dart`（無新表/新欄位）。

---

### Task 1：Markdown 內容產生純函式

**Files:**
- Create: `app/lib/reader/markdown_export.dart`
- Test: `app/test/reader/markdown_export_test.dart`

**Interfaces:**
- Consumes：`Bookmark`（`name` 欄位）、`AnnotationListItem`（`highlight`／`note` 欄位，來自 `app/lib/reader/annotation_list_item.dart`）、`Highlight`（`style`／`progression`／`pdfPageIndex`，來自 `app/lib/reader/highlight.dart`）、`Note`（`text`／`progression`／`pdfPageIndex`，來自 `app/lib/reader/note.dart`）、`HighlightStyle`（來自 `app/lib/reader/highlight_style.dart`）、`Bookmark.defaultName(BookmarkPositionContext)`（來自 `app/lib/reader/bookmark.dart`）、`BookmarkPositionContext`（來自 `app/lib/reader/bookmark_position_context.dart`）。
- Produces（供 Task 2 使用）：
  - `String generateMarkdownExport({required String bookTitle, String? bookAuthor, required double progress, required DateTime exportTime, required List<Bookmark> bookmarks, required List<AnnotationListItem> annotations})`
  - `String sanitizeMarkdownFileName(String title)`

- [x] **Step 1: 寫入失敗測試**

建立 `app/test/reader/markdown_export_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/markdown_export.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  group('generateMarkdownExport', () {
    test('有書籤、有劃線、有依附備註時，輸出格式包含三個段落與正確筆數', () {
      final result = generateMarkdownExport(
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
            note: const Note(
              bookId: 'b1',
              text: '黛玉名句',
              epubLocatorJson: '{}',
              progression: 0.2,
              highlightId: 1,
            ),
          ),
        ],
      );

      expect(result, contains('# 閱讀筆記：《紅樓夢》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**閱讀進度**：35%'));
      expect(result, contains('**導出時間**：2026-07-18'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 劃線與個人備註 (1)'));
      expect(result, contains('### 📌 螢光筆（黃）（位置：20% 處）'));
      expect(result, contains('> 黛玉名句'));
    });

    test('只有書籤時，劃線與備註段落顯示空狀態文字，作者缺省時顯示「未知作者」', () {
      final result = generateMarkdownExport(
        bookTitle: '書籤書',
        progress: 0.5,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [
          Bookmark(bookId: 'b1', name: '第 3 頁', pdfPageIndex: 2),
        ],
        annotations: const [],
      );

      expect(result, contains('**作者**：未知作者'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第 3 頁'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });

    test('只有劃線、無依附備註時，該筆項目不含引言區塊', () {
      final result = generateMarkdownExport(
        bookTitle: '劃線書',
        progress: 0.1,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              bookId: 'b1',
              style: HighlightStyle.underline,
              pdfPageIndex: 4,
            ),
          ),
        ],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('### 📌 底線（位置：第 5 頁）'));
      expect(result, isNot(contains('> ')));
    });

    test('只有純備註（無劃線）時，標籤顯示「備註」', () {
      final result = generateMarkdownExport(
        bookTitle: '備註書',
        progress: 0.6,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            note: const Note(bookId: 'b1', text: '單純心得', progression: 0.6),
          ),
        ],
      );

      expect(result, contains('### 📌 備註（位置：60% 處）'));
      expect(result, contains('> 單純心得'));
    });

    test('書籤與劃線備註皆為空時，兩段落皆顯示空狀態文字', () {
      final result = generateMarkdownExport(
        bookTitle: '空書',
        progress: 0.0,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: const [],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });
  });

  group('sanitizeMarkdownFileName', () {
    test('移除檔案系統不安全字元', () {
      expect(sanitizeMarkdownFileName('紅樓夢/夢?'), '紅樓夢_夢_');
    });

    test('清理後為空字串時回退為 book', () {
      expect(sanitizeMarkdownFileName('///'), 'book');
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/markdown_export_test.dart`
Expected: FAIL — `Error: Error when reading 'lib/reader/markdown_export.dart': No such file or directory.`

- [x] **Step 3: 實作 `markdown_export.dart`**

建立 `app/lib/reader/markdown_export.dart`：

```dart
import 'annotation_list_item.dart';
import 'bookmark.dart';
import 'bookmark_position_context.dart';
import 'highlight_style.dart';

/// 產生本書的 Markdown 筆記匯出內容（epic-6-annotations Issue 5，
/// spec.md／`prototype/index.html` `exportMarkdown()` 格式骨架）。純函式，
/// 不涉及檔案 I/O——呼叫端（`NotesBottomSheet`）負責寫檔與觸發分享。
///
/// 與原型格式的刻意差異：本專案 [Highlight]／[Note] 從未儲存被選取的
/// 原文文字，劃線/備註條目改顯示「樣式標籤＋位置標籤」而非引用原文；
/// 位置標籤直接複用 [Bookmark.defaultName]（`chapterTitle` 留空，天然
/// 回退為進度百分比／頁碼），見 plan-issue-5.md Global Constraints。
String generateMarkdownExport({
  required String bookTitle,
  String? bookAuthor,
  required double progress,
  required DateTime exportTime,
  required List<Bookmark> bookmarks,
  required List<AnnotationListItem> annotations,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# 閱讀筆記：《$bookTitle》');
  buffer.writeln('*   **作者**：${bookAuthor ?? '未知作者'}');
  buffer.writeln('*   **閱讀進度**：${(progress * 100).round()}%');
  buffer.writeln('*   **導出時間**：${_formatDate(exportTime)}');
  buffer.writeln();

  buffer.writeln('## 🔖 書籤清單 (${bookmarks.length})');
  if (bookmarks.isEmpty) {
    buffer.writeln('*(尚未加入書籤)*');
    buffer.writeln();
  } else {
    for (final bookmark in bookmarks) {
      buffer.writeln('*   ${bookmark.name}');
    }
    buffer.writeln();
  }

  buffer.writeln('## ✏️ 劃線與個人備註 (${annotations.length})');
  if (annotations.isEmpty) {
    buffer.writeln('*(尚未加入任何劃線或備註)*');
  } else {
    for (final item in annotations) {
      final highlight = item.highlight;
      final label =
          highlight != null ? _highlightStyleLabel(highlight.style) : '備註';
      buffer.writeln('### 📌 $label（位置：${_positionLabel(item)}）');
      final note = item.note;
      if (note != null) {
        buffer.writeln('> ${note.text}');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

/// 供匯出檔名使用，移除 Android 檔案系統不接受的字元；清理後為空字串時
/// 回退為 `book`，避免產生副檔名前無主檔名的檔案（例如 `.md`）。
String sanitizeMarkdownFileName(String title) {
  final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'book' : sanitized;
}

/// 【私有，本檔案唯一消費端】劃線樣式的中文顯示標籤。刻意與
/// `notes_bottom_sheet.dart` 內部同名私有函式重複，而非抽出共用——兩者
/// 皆為各自檔案的唯一消費端，且 `notes_bottom_sheet.dart` 的既有 KDoc
/// 已明確記載「純 UI 顯示標籤不放在領域模型檔案、收斂在消費端自己的私有
/// 函式」設計原則（見該檔案 Task 7 說明），本檔案延續同一原則、對稱處理，
/// 不回頭修改已審查穩定的既有檔案。
String _highlightStyleLabel(HighlightStyle style) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return '螢光筆（黃）';
    case HighlightStyle.highlighterPink:
      return '螢光筆（粉）';
    case HighlightStyle.highlighterBlue:
      return '螢光筆（藍）';
    case HighlightStyle.underline:
      return '底線';
  }
}

/// 複用 [Bookmark.defaultName] 換算劃線/備註的位置標籤——`pdfPageIndex`／
/// `progression` 與 [Bookmark]／[Highlight]／[Note] 三者欄位語意/命名完全
/// 一致，直接透傳即可，不重新實作換算邏輯。`chapterTitle` 刻意留空：
/// 逐筆劃線/備註即時反查所在章節需要額外貫穿 `TocEntry` 清單，超出本工單
/// 範疇，`Bookmark.defaultName` 對 `chapterTitle == null` 已有既定、已測試
/// 的百分比／頁碼回退行為（見 `bookmark.dart`）。
String _positionLabel(AnnotationListItem item) {
  final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
  final progression = item.highlight?.progression ?? item.note?.progression;
  return Bookmark.defaultName(BookmarkPositionContext(
    pdfPageIndex: pdfPageIndex,
    progression: progression,
  ));
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/markdown_export_test.dart`
Expected: `All tests passed!`

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/markdown_export.dart app/test/reader/markdown_export_test.dart
git commit -m "feat(epic-6): 新增 Markdown 匯出內容產生純函式"
```

---

### Task 2：`NotesBottomSheet` 匯出按鈕與檔案寫入/分享接線

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Create: `app/test/support/fake_path_provider_platform.dart`
- Create: `app/test/support/fake_share_platform.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes（Task 1 產物）：`generateMarkdownExport(...)`／`sanitizeMarkdownFileName(...)`（來自 `app/lib/reader/markdown_export.dart`）。
- Consumes（既有）：`NotesBottomSheet` 既有 `_bookmarks`／`_highlights`／`_notes` State 欄位與既有 `mergeAnnotations` import；`ReaderScreen._openNotesSheet(BookFormat format)`；`ReaderScreen._epubPositionInfo`（`EpubPositionInfo?`，欄位 `progression`）／`_pdfPageInfo`（`PdfPageInfo?`，欄位 `pageIndex`／`totalPages`）；`LibraryScreen._openBook(Book book)`；`Book.title`／`Book.author`／`Book.progress`（來自 `app/lib/library/models/book.dart`）。
- Produces：`NotesBottomSheet` 新增 Key `notes_sheet_export_markdown`（`TextButton.icon`）；`ReaderScreen`／`NotesBottomSheet` 新增 `bookTitle`／`bookAuthor`／`bookProgress` 具名參數（供 Task 3 直接建構使用）。**審查修正（I-1）**：`ReaderScreen._openNotesSheet()` 傳給 `NotesBottomSheet` 的 `bookProgress` 改為即時計算的目前進度，不再是 `widget.bookProgress` 這個開書當下的舊快照值（見 Step 6）。

- [x] **Step 1：新增 `share_plus` 依賴**

編輯 `app/pubspec.yaml`，在既有 `path_provider: ^2.1.6`（第 39 行）之後新增：

```yaml
  path_provider: ^2.1.6
  share_plus: ^13.2.1
```

Run: `cd app && flutter pub get`
Expected: `Got dependencies!`（新增 `share_plus`／`share_plus_platform_interface`／`cross_file` 等套件）

- [x] **Step 2：新增測試替身**

建立 `app/test/support/fake_path_provider_platform.dart`：

```dart
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 測試用 [PathProviderPlatform] 替身：`flutter test`（無真實裝置）無法
/// 觸發 path_provider 的原生實作，直接回傳呼叫端指定的真實可寫入目錄
/// （例如 `Directory.systemTemp` 底下的暫存子目錄），讓
/// `getTemporaryDirectory()` 在純 widget test 環境下也能正常運作、寫出
/// 可驗證的真實檔案。比照本專案既有 `test/support/fake_*.dart` 命名慣例。
class FakePathProviderPlatform extends PathProviderPlatform {
  final String path;

  FakePathProviderPlatform(this.path);

  @override
  Future<String?> getTemporaryPath() async => path;
}
```

建立 `app/test/support/fake_share_platform.dart`：

```dart
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// 測試用 [SharePlatform] 替身：攔截 [share] 呼叫並記錄傳入的
/// [ShareParams]，不觸發真實系統分享面板（見 plan-issue-5.md Global
/// Constraints「真實 Android Share Intent 會阻塞等待使用者操作」——真正
/// 呼叫原生分享會讓 `flutter test` 卡住等待人工介入）。
class FakeSharePlatform extends SharePlatform {
  ShareParams? lastParams;

  @override
  Future<ShareResult> share(ShareParams params) async {
    lastParams = params;
    return ShareResult('', ShareResultStatus.success);
  }
}
```

- [x] **Step 3：在 `notes_bottom_sheet_test.dart` 新增失敗測試**

在檔案頂部 import 區塊（第 1-12 行）新增：

```dart
import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';
import '../support/fake_share_platform.dart';
```

使頂部 import 區塊變為：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_share_platform.dart';
```

修改既有 `_pumpSheet` 輔助函式（第 14-40 行），新增三個具預設值的可選參數並透傳：

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
  await tester.pumpWidget(MaterialApp(
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
  ));
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}
```

在檔案最末（最後一個 `testWidgets` 區塊之後、`}` 之前）新增：

```dart
  testWidgets('顯示「導出為 Markdown」按鈕', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(find.byKey(const Key('notes_sheet_export_markdown')), findsOneWidget);
  });

  testWidgets(
      '點擊導出為 Markdown 按鈕後，正確寫入暫存檔案並呼叫 SharePlatform.share',
      (tester) async {
    final tempDir =
        await Directory.systemTemp.createTemp('markdown_export_test');
    addTearDown(() => tempDir.delete(recursive: true));

    final originalPathProvider = PathProviderPlatform.instance;
    final originalSharePlatform = SharePlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final fakeShare = FakeSharePlatform();
    SharePlatform.instance = fakeShare;
    addTearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      SharePlatform.instance = originalSharePlatform;
    });

    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(bookId: 'b1', name: '第一章', progression: 0.1),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      bookTitle: '測試書籍',
      bookAuthor: '測試作者',
      bookProgress: 0.42,
    );

    await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
    await tester.pumpAndSettle();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    expect(await exportedFile.exists(), isTrue);
    final content = await exportedFile.readAsString();
    expect(content, contains('# 閱讀筆記：《測試書籍》'));
    expect(content, contains('**作者**：測試作者'));
    expect(content, contains('**閱讀進度**：42%'));
    expect(content, contains('*   第一章'));
  });
```

**審查修正（I-1）**：`widget.bookProgress` 是 `LibraryScreen._openBook` 開書當下傳入的舊進度快照，使用者若在同一次閱讀 session 內翻閱到新位置才點擊匯出，`NotesBottomSheet` 收到的仍是這個過期值。`_openNotesSheet()` 必須改為即時計算目前進度（見 Step 6），故在 `app/test/screens/reader_screen_test.dart` 也新增對應測試——於檔案最末（最後一個 `testWidgets` 區塊之後、`}` 之前）新增：

```dart
  // --- Epic 6 Issue 5：Markdown 導出 ---

  testWidgets(
      'EPUB：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 反映目前即時進度，而非開書當下的舊 bookProgress',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_chapter.epub',
          bookId: 'b_progress_export_epub',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          bookProgress: 0.1,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/c3.xhtml"}', progression: 0.5),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet = tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet));
    expect(
      sheet.bookProgress,
      0.5,
      reason: '應反映 onLocatorChanged 回報的最新進度，而非建構時的舊 bookProgress: 0.1',
    );
  });

  testWidgets(
      'PDF：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 依 onPageChanged 回報的頁碼/總頁數即時換算',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_progress_export_pdf',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          bookProgress: 0.0,
        ),
      ),
    );
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 4, totalPages: 10));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet = tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet));
    expect(
      sheet.bookProgress,
      0.5,
      reason: '第 5 頁／共 10 頁應換算為 0.5，而非建構時的舊 bookProgress: 0.0',
    );
  });
```

- [x] **Step 4：執行測試確認失敗**

Run: `cd app && flutter test test/screens/notes_bottom_sheet_test.dart test/screens/reader_screen_test.dart`
Expected: FAIL —`notes_bottom_sheet_test.dart` 因 `The named parameter 'bookTitle' isn't defined`（`NotesBottomSheet` 建構子尚未有這些參數）編譯失敗；`reader_screen_test.dart` 同理因 `ReaderScreen`／`NotesBottomSheet` 尚未有 `bookProgress` 等新參數編譯失敗。

- [x] **Step 5：實作 `notes_bottom_sheet.dart`**

**5a. 新增 import。** 在既有 import 區塊（第 1-12 行）之後插入：

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../reader/markdown_export.dart';
```

**5b. 新增建構參數。** 在 `bookId`／`bookmarksRepository` 欄位宣告（第 22-23 行）之後插入：

```dart
  /// 供「導出為 Markdown」使用的書籍中繼資料（epic-6-annotations
  /// Issue 5）。皆為必填——唯一正式呼叫端 `ReaderScreen._openNotesSheet`
  /// 一定會提供值（見 plan-issue-5.md Global Constraints）。
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;
```

並在建構子（原本的 `const NotesBottomSheet({...})`）新增對應必填參數：

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
  });
```

**5c. 新增匯出方法。** 在 `_loadAnnotations()` 方法（原第 103-114 行）之後插入：

```dart
  /// 【審查修正 M-1】包在 try-catch 內——`getTemporaryDirectory()`／
  /// `writeAsString()`／`SharePlus.instance.share()` 皆涉及非同步 I/O 與
  /// 平台通道，極端環境（例如儲存空間不足、使用者中途取消系統分享面板
  /// 拋出例外）下不應讓整個 Bottom Sheet 崩潰，比照專案既有對外部 I/O
  /// 失敗的防禦性慣例（見 `_loadFxlBookmarks()` 既有寫法）。
  Future<void> _exportMarkdown() async {
    try {
      final markdown = generateMarkdownExport(
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        progress: widget.bookProgress,
        exportTime: DateTime.now(),
        bookmarks: _bookmarks,
        annotations: mergeAnnotations(_highlights, _notes),
      );
      final tempDir = await getTemporaryDirectory();
      final fileName = 'notes-${sanitizeMarkdownFileName(widget.bookTitle)}.md';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(markdown);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/markdown')]),
      );
    } catch (e) {
      debugPrint('Failed to export markdown: $e');
    }
  }
```

**5d. 新增匯出按鈕。** 在 `build()` 方法內，把原本的標題 `Padding`（原第 132-136 行）：

```dart
            const Padding(
              padding: EdgeInsets.all(16),
              child:
                  Text('📚 筆記', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
```

改為：

```dart
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('📚 筆記',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    key: const Key('notes_sheet_export_markdown'),
                    onPressed: _exportMarkdown,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('導出為 Markdown'),
                  ),
                ],
              ),
            ),
```

- [x] **Step 6：貫穿 `ReaderScreen` 新參數**

在 `app/lib/screens/reader_screen.dart` 的 `ReaderScreen` 類別，`notesRepository` 欄位宣告（原第 74 行）之後插入：

```dart
  /// 供「導出為 Markdown」使用的書籍中繼資料（epic-6-annotations
  /// Issue 5）。刻意為可選具名參數並附預設值——比照 [bookmarksRepository]
  /// 既有慣例，避免既有大量測試呼叫端需要逐一補上這三個參數。
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;
```

原本的建構子（第 76-84 行）：

```dart
  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
  });
```

改為：

```dart
  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
  });
```

**審查修正（I-1）**：`widget.bookProgress` 是 `LibraryScreen._openBook` 開書當下傳入的舊進度快照——使用者開書後若已翻閱到新位置才點擊「📚 筆記」匯出，直接透傳 `widget.bookProgress` 會讓匯出內容顯示過期進度。改為在 `_openNotesSheet()` 內即時計算目前進度：EPUB／FXL 用 `_epubPositionInfo?.progression`（`_epubPositionInfo` 尚為 `null` 時，例如剛開書、`onLocatorChanged` 尚未觸發過，回退用 `widget.bookProgress`）；PDF 用 `_pdfPageInfo`（非 null 且 `totalPages > 0` 時換算 `(pageIndex + 1) / totalPages`，否則同樣回退 `widget.bookProgress`）。

`_openNotesSheet()` 方法內，`positionContext` 賦值（`final positionContext = BookmarkPositionContext(...);` 那個區塊）之後、`showModalBottomSheet<void>(` 呼叫之前，插入：

```dart
    final latestProgress = format == BookFormat.epub
        ? (_epubPositionInfo?.progression ?? widget.bookProgress)
        : (_pdfPageInfo != null && _pdfPageInfo!.totalPages > 0
            ? (_pdfPageInfo!.pageIndex + 1) / _pdfPageInfo!.totalPages
            : widget.bookProgress);
```

接著，`NotesBottomSheet(` 建構呼叫（`bookId: widget.bookId,` 那一行，位於現行 548 行附近）之後插入：

```dart
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        bookProgress: latestProgress,
        bookmarksRepository: repository,
```

（`bookProgress` 傳入的是上面新增的 `latestProgress` 區域變數，**不是** `widget.bookProgress`；`currentPosition` 以下其餘既有欄位與 `onAnnotationSelected`／`onAnnotationsChanged`／`onBookmarkSelected`／`.then(...)` 整段維持原樣不動。）

- [x] **Step 7：貫穿 `LibraryScreen` 新參數**

在 `app/lib/screens/library_screen.dart` 的 `_openBook(Book book)` 方法內，原本：

```dart
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
            ),
```

改為：

```dart
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
            ),
```

- [x] **Step 8：執行測試確認通過**

Run: `cd app && flutter test`
Expected: `All tests passed!`

- [x] **Step 9：建置驗證 `FileProvider` 無 Manifest 衝突**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`（建置成功即代表 `share_plus` 自帶的 `${applicationId}.flutter.share_provider` 與本專案既有 `${applicationId}.fileprovider` 未在 Manifest Merger 階段衝突，見 Global Constraints）。

- [x] **Step 10：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/screens/notes_bottom_sheet.dart app/lib/screens/reader_screen.dart app/lib/screens/library_screen.dart app/test/screens/notes_bottom_sheet_test.dart app/test/support/fake_path_provider_platform.dart app/test/support/fake_share_platform.dart
git commit -m "feat(epic-6): NotesBottomSheet 新增導出為 Markdown 按鈕，接上檔案寫入與系統分享"
```

---

### Task 3：真機整合測試（有限自動化）＋人工驗證清單

**Files:**
- Create: `app/integration_test/markdown_export_test.dart`

**Interfaces:**
- Consumes：Task 2 產物——`ReaderScreen` 的 `bookTitle`／`bookAuthor`／`bookProgress` 參數、`NotesBottomSheet` 的 Key `notes_sheet_export_markdown`。
- Produces：無（端到端驗證，不供後續任務消費）。

**範圍說明**：依 Global Constraints「真實 Android Share Intent 會阻塞等待使用者操作」，本測試**不點擊**匯出按鈕觸發真實分享——只驗證按鈕在真機上正確渲染、依既有 `_epubPositionInfo`／`onPageRendered` 就緒條件正確啟用/停用，比照既有 `reader_notes_button` 的既有測試模式。真正「點擊後系統分享面板喚起、其他 App 能正確讀取檔案」留給下方人工驗證清單。

- [x] **Step 1：新增 `app/integration_test/markdown_export_test.dart`**

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

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真機：開啟 Bottom Sheet 後「導出為 Markdown」按鈕正確渲染（不點擊觸發真實分享，見 plan-issue-5.md）',
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
      'test/fixtures/sample_multi_chapter.epub',
      'markdown_export.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_markdown_export',
      title: '匯出測試書',
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
          bookId: 'b_markdown_export',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          bookTitle: '匯出測試書',
          bookAuthor: '測試作者',
          bookProgress: 0.5,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsOneWidget);

    final exportButtonFinder =
        find.byKey(const Key('notes_sheet_export_markdown'));
    expect(exportButtonFinder, findsOneWidget);
    expect(
      tester.widget<TextButton>(exportButtonFinder).onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [x] **Step 2：於真實裝置/模擬器執行整合測試**

Run: `cd app && flutter test integration_test/markdown_export_test.dart -d <device-id>`（`<device-id>` 以 `flutter devices` 查得的實際 id 取代）
Expected: `All tests passed!`

- [x] **Step 3：執行全專案回歸驗證**

Run: `cd app && flutter test`
Expected: `All tests passed!`（無既有測試回歸）

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 4：Commit**

```bash
git add app/integration_test/markdown_export_test.dart
git commit -m "test(epic-6): 新增 Markdown 導出真機整合測試"
```

---

## 真機人工驗證清單（Task 3 自動化範圍之外）

依 Global Constraints「真實 Android Share Intent 會阻塞等待使用者操作」，以下項目無法透過 `flutter test integration_test/...` 自動化，需人工於真機操作驗證：

1. 開啟一本有書籤/劃線/備註的書，點擊「📚 筆記」→「導出為 Markdown」，確認 Android 系統分享面板確實喚起。
2. 選擇一個能接收 `.md`／`text/markdown` 檔案的目標 App（例如檔案管理員、雲端硬碟、另一個筆記 App），確認對方能成功接收檔案且無「無權限讀取」錯誤（驗證 `share_plus` 自身 `FileProvider` 的 `content://` URI 授權正確涵蓋 `getTemporaryDirectory()` 路徑）。
3. 打開接收到的檔案，確認內容與書籍實際的書籤/劃線/備註一致、Markdown 格式（標題/清單/引言）在常見檢視器中正確渲染。
4. 書名含特殊字元（例如「測試：書籍？」）時，確認匯出檔名被正確清理（不因非法字元導致寫檔失敗）。

---

## Self-Review 紀錄

**Spec coverage：** 對照 `issues.md` Issue 5 的 7 條驗收標準逐一核對：
- Markdown 內容涵蓋書籤+劃線/備註、格式符合骨架 → Task 1（含刻意記錄的骨架調整理由）
- 導出範圍固定為目前這本書 → `generateMarkdownExport` 只接受呼叫端已篩選好的單書清單，無跨書查詢能力
- 存於 App 私有暫存目錄、不需額外儲存權限 → Task 2 使用既有 `path_provider` 依賴的 `getTemporaryDirectory()`
- 透過 `share_plus` 觸發系統分享 → Task 2（API 因套件版本演進調整，已於 Global Constraints說明並查證）
- `share_plus` 與既有 `FileProvider` 無 Manifest 衝突 → Global Constraints 查證 + Task 2 Step 9 建置驗證
- 測試皆通過、`flutter analyze` 乾淨 → Task 2 Step 8、Task 3 Step 3
- 真機整合測試涵蓋導出→存檔→分享端到端流程 → Task 3（自動化涵蓋渲染/啟用狀態，分享面板本身列入人工驗證清單並說明原因）

**Placeholder scan：** 全文無 TBD／implement later／模糊描述，所有程式碼步驟皆含完整可執行程式碼。

**Type consistency：** `generateMarkdownExport` 的具名參數（`bookTitle`／`bookAuthor`／`progress`／`exportTime`／`bookmarks`／`annotations`）在 Task 1（定義＋測試）與 Task 2（`_exportMarkdown()` 呼叫端）用法一致；`NotesBottomSheet`／`ReaderScreen` 的 `bookTitle`／`bookAuthor`／`bookProgress` 三個欄位名稱在 Task 2 的兩層貫穿（`LibraryScreen` → `ReaderScreen` → `NotesBottomSheet`）與 Task 3 的直接建構中完全一致。

**審查修訂紀錄（`tmp/epic-6/reviews/review-plan-issue-5.md`）：**
- **I-1（Important，已修正）**：`_openNotesSheet()` 原本直接透傳 `widget.bookProgress`（開書當下的舊快照），會讓匯出內容顯示過期進度。改為即時計算（EPUB／FXL 用 `_epubPositionInfo?.progression`，PDF 用 `_pdfPageInfo` 換算頁碼比例，皆在對應欄位為 `null` 時回退 `widget.bookProgress`），見 Global Constraints 新增條目與 Task 2 Step 6；並在 `reader_screen_test.dart` 新增 EPUB／PDF 兩個對應測試（Task 2 Step 3）。
- **M-1（Minor，已修正）**：`_exportMarkdown()` 包上 `try-catch`，例外時 `debugPrint` 而不向上冒泡，比照既有 `_loadFxlBookmarks()` 的既定防禦寫法（見 Task 2 Step 5c）。
