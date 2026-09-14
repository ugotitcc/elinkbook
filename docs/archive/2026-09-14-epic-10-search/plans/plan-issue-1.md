# Epic 10 Issue 1：背景索引排程器＋PDF／Foliate 內容擷取（端到端）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓一本書（PDF 或 Foliate 格式）從 `content_index_status.status='pending'` 自動變成 `'done'`，全程在背景執行，且與使用者正在閱讀互斥——這是全文檢索的核心索引建置引擎。

**Architecture：** 新目錄 `app/lib/search/` 底下建立 `ContentIndexer` 抽象介面＋兩個具體實作（`PdfContentIndexer` 純 Dart/FFI；`FoliateContentIndexer` 驅動 `HeadlessInAppWebView` 跑 `readest/foliate-js`），與一個 `ContentIndexingScheduler` 純 Dart 排程器（`WidgetsBindingObserver` 監聽 App 前後台狀態＋監聽新增的 `ReaderActivityTracker` 得知是否有閱讀畫面開啟，兩者皆滿足時才處理 `content_index_status` 佇列）。`FoliateContentIndexer` 重用既有 `cacheBookForServing()`／`InternalStoragePathHandler`／`JsBridgeGateway` 三件套（`FoliateReaderView` 既有模式），`main.js` 新增 `mode=index` 旗標與兩個新橋接函式（`window.getSectionCount()`／`window.buildSegmentsForSection()`，後者從既有 `window.buildTtsSegments()` 抽出共用核心邏輯，避免重複維護句子切分/CFI 換算這段複雜邏輯）。排程器寫入索引資料時呼叫 Issue 0 的 `tokenizeForIndex()`，觸發 Issue 0 已建立的 FTS5 同步 trigger。

**Tech Stack：** Flutter/Dart、`pdfrx`（PDFium FFI，既有依賴）、`flutter_inappwebview`（`^6.1.5`，`HeadlessInAppWebView`，既有依賴、非新增套件）、`sqflite`。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §3（索引建置管線，含 3.1 抽象介面、3.2 兩個實作、3.3 排程器）；[`docs/adr/0027-search-index-tokenization-and-headless-foliate-extraction.md`](../../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md)；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 1。

> **本計畫檔案存放路徑覆寫說明**：比照 `plan-issue-0.md` 先例，`superpowers:writing-plans` 技能預設把計畫存到 `docs/superpowers/plans/`，本專案 SDD 工作流程（`docs/agents/issue-tracker.md`）明訂存放於 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，本計畫依專案慣例存放於此。

## Global Constraints

- **本工單完成前的地基**（Issue 0 已交付，直接沿用不重複建立）：`content_index_status`／`book_content_index`／`book_content_fts` 三張表（DB version 24）＋ `app/lib/search/cjk_tokenizer.dart` 的 `tokenizeForIndex()`／`tokenizeForQuery()`。`SqliteLibraryRepository.database`（既有 public getter，`app/lib/library/sqlite_library_repository.dart:1009`）供本工單直接下 raw SQL 查詢這三張表，不新建獨立 repository 類別（比照 `plan-issue-0.md` 先例）。
- **規劃階段查證（覆寫 `spec.md` §3.3 一處措辭矛盾）**：`spec.md` §3.3 開頭寫「排程器依賴：`FullTextSearchSettingsRepository`（第 4 節）」，但同一節稍後又寫「排程器本身不需感知 `category`」，且 `issues.md` 依賴圖明訂 `Issue 0 → Issue 1 → Issue 3`（Issue 1 在 Issue 3 之前，不可能依賴尚不存在的 `FullTextSearchSettingsRepository`），`issues.md` Issue 1 的 Solution 段落本身也完全沒有提到這個型別，Issue 3 的 Solution 則明確寫「交給 Issue 1 的排程器處理（排程器本身不需感知 category）」。三份文件交叉比對後確認：**`ContentIndexingScheduler` 本工單不接受 `FullTextSearchSettingsRepository` 依賴**，純粹處理 `content_index_status` 裡已經存在的 `pending`/`indexing` 列，不管這些列是誰、何時插入的——這是 Issue 2／Issue 3 的職責。本工單的端到端驗收測試（Task 7）直接對 `content_index_status` 插入測試用的 `pending` 列，不透過任何「啟用開關」流程。
- **一次僅處理一本書、一個 `HeadlessInAppWebView`／PDF 文件實例**（ADR 0027 決策 3），不做記憶體閾值偵測。
- **暫停粒度為「章節邊界」，非逐筆 segment**：排程器在每完成一個章節（`IndexedSegment.chapterIndex` 變動時）才檢查是否需要暫停，這與 `content_index_status.last_chapter_index`（章節級游標）的續跑語意直接對應（`spec.md` §3.3）——暫停時，尚未寫入的當前章節資料直接捨棄，下次從該章節重新擷取，不做章節內部的半成品續傳（避免不必要的複雜度，`spec.md` §3.3 已明訂此設計）。
- **PDF 逐頁的切片粒度是 `PdfPageTextFragment`（`pdfrx_engine` 既有型別，`page.loadStructuredText().fragments`），非整頁一筆**：每個 fragment 各自有 `.text`／`.bounds`（PDF points 座標），提供比整頁更精確的頁內定位精度，符合 `design.md`「精確位置級跳轉」目標；空白/純空格 fragment 略過不寫入。
- **JS→Dart 橋接一律透過 `window.flutter_inappwebview.callHandler(...)` 回呼**（`JsBridgeGateway` 既有樣板），不直接依賴 `evaluateJavascript()` 的回傳值——本專案現有慣例對所有橋接（含同步性質的查詢）一律如此，`getSectionCount()` 亦比照辦理，不引入第二套機制。
- **`buildSegmentsForSection()` 與既有 `buildTtsSegments()` 共用同一套句子切分／CFI 核心邏輯**（抽成 `extractSegmentsForSection()`），兩者回傳格式相同（`[{segmentId, cfi, text}]`），Dart 端直接重用既有 `parseTtsSegments()`／`TtsSegmentCfi`（`app/lib/reader/foliate_bridge_codec.dart`／`app/lib/reader/tts_segment_cfi.dart`），不另寫一份解析器。
- **`mode=index` 的跳過範圍精確限定**：本工單查證過 `main.js` 現有結構後，唯一需要跳過的初始化是 `view.addEventListener('load', (e) => {...})`（觸控意圖狀態機＋選取/劃線手勢橋接，`main.js:951` 起，涵蓋整個 `TouchIntentClassifier` 相關邏輯）——headless webview 永遠不會有真實觸控事件，讓這段邏輯掛著雖不會出錯但純屬浪費；guard 寫法是在該 listener callback **開頭插入一行 `if (isIndexMode) return`**，不嘗試去找/搬動這個 350 行左右 closure 的結尾大括號（風險不必要，插入單一提早 return 行為完全等價且不需要知道區塊終點）。`draw-annotation` 監聽器（`main.js:889`）與 `window.buildTtsSegments` 等函式定義本身不需要 guard——前者只在 Dart 呼叫 `view.addAnnotation()` 時才會觸發、索引模式下 Dart 端從不呼叫；後者只是函式宣告，不執行任何動作直到被呼叫。
- **`HeadlessInAppWebView` 建構時必須明確指定非退化 `initialSize`**（例如 `Size(800, 1280)`，一般手機內容區域量級的邏輯像素）——套件預設值 `Size(-1, -1)` 語意不明確，`foliate-js` 的 `Paginator`／`view.init()` 需要一個有意義的版面尺寸才能正確完成內部初始化流程；`buildSegmentsForSection()`／`getSectionCount()` 本身雖不依賴實際分頁結果，但沿用既有「等 `onPageRendered` 才視為書籍就緒」訊號（見下方 Task 3），而 `onPageRendered` 只在 `view.init()` 成功完成後才觸發，故 `view.init()` 必須先能正常跑完。
- **`ContentIndexer.indexBook()` 的 `Book` 參數一律用 `Book.fromMap()`（`app/lib/library/models/book.dart:158`）從 `content_index_status JOIN books` 的原始 row 還原**，不透過 `LibraryRepository.listBooks()` 撈整個書庫（避免每次排程 tick 都載入全庫），比照 `spec.md` §3.3 效能查詢一節本身已示範的「直接 JOIN `books`」寫法。
- 所有新增程式碼註解使用正體中文（zh-TW），比照全專案既有慣例。
- **本計畫已經過一輪計畫審查修訂**（`reviews/review-plan-issue-1.md`，🔴 Changes Requested，1 Critical／4 Important／2 Minor，全數已修訂並驗證，逐項標註於對應 Task 內：C-1 `PdfContentIndexer` 的 `content://` URI 處理〔Task 1〕、I-1 headless webview 缺少 ES 相容性/錯誤捕捉腳本〔Task 3 Step 0〕、I-2 `JsBridgeGateway` 循序章節請求逾時可能跨章節錯位污染〔Task 3 Step 1〕、I-3 續跑佇列排序造成排程飢餓〔Task 5〕、I-4 缺乏公開喚醒方法供 Issue 2／3 事件驅動〔Task 5〕、M-1 `pubspec.yaml` 缺少 asset 宣告〔Task 7 Step 0〕、M-2 `stop()`/`dispose()` 未阻擋繼續處理〔Task 5，**修法與審查原始建議不同**——見 `ContentIndexingScheduler._disposed` 欄位註解，原建議會破壞 Task 5 測試套件刻意不呼叫 `start()` 的可測試性設計）。執行者不需要另外重讀審查報告，所有修訂已內嵌為對應程式碼片段與行內註解。

---

## 檔案結構總覽

- **Create：** `app/lib/search/content_indexer.dart` — `ContentIndexer` 抽象介面＋`IndexedSegment`。
- **Create：** `app/lib/search/pdf_content_indexer.dart` — `PdfContentIndexer`。
- **Create：** `app/test/search/pdf_content_indexer_test.dart`。
- **Modify：** `app/android/app/src/main/assets/foliate/main.js` — `mode=index` 旗標、`window.getSectionCount()`、`window.buildSegmentsForSection()`（從 `buildTtsSegments()` 抽出共用核心）、觸控/選取手勢初始化加上 `isIndexMode` guard。
- **Modify：** `app/lib/reader/foliate_native_bridge.dart` — 新增公開常數 `esCompatPolyfillJs`／`globalErrorCaptureJs`（自 `foliate_reader_view.dart` 搬移，review-plan-issue-1.md I-1）。
- **Modify：** `app/lib/reader/foliate_reader_view.dart` — 改用上述搬移後的公開常數，移除本地私有版本。
- **Create：** `app/lib/search/foliate_content_indexer.dart` — `FoliateContentIndexer`。
- **Create：** `app/integration_test/foliate_content_indexer_test.dart`（真機/模擬器）。
- **Create：** `app/lib/reader/reader_activity_tracker.dart` — `ReaderActivityTracker`。
- **Modify：** `app/lib/screens/reader_screen.dart` — 新增可選參數 `readerActivityTracker`，`initState()`/`dispose()` 呼叫。
- **Modify：** `app/test/screens/reader_screen_test.dart` — 新增一則驗證上述呼叫的 widget test。
- **Create：** `app/lib/search/content_indexing_scheduler.dart` — `ContentIndexingScheduler`。
- **Create：** `app/test/search/content_indexing_scheduler_test.dart`。
- **Modify：** `app/lib/main.dart` — 建構 `ReaderActivityTracker`／`ContentIndexingScheduler`，呼叫 `scheduler.start()`。
- **Modify：** `app/lib/screens/library_screen_dependencies.dart` — `LibraryReaderFeatureRepositories` 新增 `readerActivityTracker` 欄位。
- **Modify：** `app/lib/screens/library_screen.dart` — `_openBook()` 貫穿傳入 `readerActivityTracker`。
- **Create：** `app/integration_test/content_indexing_end_to_end_test.dart`（真機/模擬器，本工單「demoable」驗收標準）。
- **Modify：** `app/pubspec.yaml` — 補上缺少的 `test/fixtures/sample_multi_page.pdf` asset 宣告（review-plan-issue-1.md M-1）。

---

### Task 1：`ContentIndexer` 抽象介面＋`PdfContentIndexer`

**Files：**
- Create: `app/lib/search/content_indexer.dart`
- Create: `app/lib/search/pdf_content_indexer.dart`
- Test: `app/test/search/pdf_content_indexer_test.dart`

**Interfaces：**
- Consumes：`app/lib/reader/pdf_search_geometry.dart` 既有 `pdfRectToPercentRect()`；`app/lib/library/models/book.dart` 的 `Book`。
- Produces：`abstract class ContentIndexer { Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter}); }`、`class IndexedSegment { final int chapterIndex; final String locator; final String rawText; }`、`class PdfContentIndexer implements ContentIndexer`、頂層可覆寫函式變數 `Future<String?> Function(String uri) readContentUriAll`（`content://` URI 解析，見 review-plan-issue-1.md C-1）——Task 3（`FoliateContentIndexer`）、Task 5（`ContentIndexingScheduler`）直接 import 使用，簽章與行為以本工單為準。

- [x] **Step 1：寫一個會失敗的測試——PDF 逐頁擷取為 `IndexedSegment`**

新增 `app/test/search/pdf_content_indexer_test.dart`：

```dart
// app/test/search/pdf_content_indexer_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/pdf_content_indexer.dart';

/// 測試用最小 [Book]，只有 [PdfContentIndexer] 實際用到的 [filePath] 有意義，
/// 其餘欄位填入合法但無意義的預設值（比照專案既有測試慣例）。
Book _pdfBook({required String filePath}) {
  return Book(
    id: 'pdf-book-1',
    title: '測試 PDF',
    format: BookFileFormat.pdf,
    filePath: filePath,
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

void main() {
  setUp(() => pdfrxInitialize());

  group('PdfContentIndexer.indexBook', () {
    test(
        '對 5 頁 PDF（test/fixtures/sample_multi_page.pdf，見 pdf_reader_view_search_test.dart 既有驗證：每頁皆含 "Page" 字樣）逐頁擷取為 IndexedSegment',
        () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments = await indexer.indexBook(book).toList();

      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2, 3, 4},
          reason: 'chapterIndex 即頁碼（0-indexed），5 頁應涵蓋 0-4 全部頁碼');

      // 每頁至少一個 fragment 的文字包含 "Page"（大小寫不敏感，比照
      // pdf_reader_view_search_test.dart 對同一份 fixture 已驗證過的內容）。
      final textByPage = <int, StringBuffer>{};
      for (final segment in segments) {
        textByPage
            .putIfAbsent(segment.chapterIndex, () => StringBuffer())
            .write(segment.rawText);
      }
      for (var page = 0; page < 5; page++) {
        expect(textByPage[page].toString().toLowerCase(), contains('page'),
            reason: '第 $page 頁組合文字應包含 "Page" 字樣');
      }

      final first = segments.first;
      expect(first.rawText.trim(), isNotEmpty);
      final locator = jsonDecode(first.locator) as Map<String, dynamic>;
      expect(locator['page'], 0);
      final rect = locator['rect'] as Map<String, dynamic>;
      final left = (rect['left'] as num).toDouble();
      final top = (rect['top'] as num).toDouble();
      final right = (rect['right'] as num).toDouble();
      final bottom = (rect['bottom'] as num).toDouble();
      expect(left, inInclusiveRange(0.0, 1.0));
      expect(right, inInclusiveRange(0.0, 1.0));
      expect(top, lessThan(bottom), reason: '比照 PercentRect 慣例，top<=bottom（左上角原點）');
    });

    test('resumeFromChapter 只從指定頁碼（含）開始擷取', () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments =
          await indexer.indexBook(book, resumeFromChapter: 3).toList();

      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {3, 4});
    });

    test('空白/純空格文字片段不產生 IndexedSegment', () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments = await indexer.indexBook(book).toList();

      for (final segment in segments) {
        expect(segment.rawText.trim(), isNotEmpty);
      }
    });

    // 【review-plan-issue-1.md C-1】content:// URI 書籍必須先串流複製為
    // 本機暫存檔才能被 PdfDocument.openFile() 開啟，覆寫 readContentUriAll
    // 頂層函式變數繞過真正的原生 MethodChannel 呼叫（測試環境無法呼叫
    // 原生端），驗證：(1) filePath 含 "://" 時確實呼叫這個 resolver 而非
    // 直接把 content:// 字串傳給 PdfDocument.openFile()；(2) 解析出的暫存
    // 檔路徑正確被拿去開啟；(3) 處理完畢後暫存檔被刪除。
    test('content:// URI 書籍透過 readContentUriAll 解析為暫存檔後開啟，處理完畢後刪除暫存檔',
        () async {
      final original = readContentUriAll;
      addTearDown(() => readContentUriAll = original);

      var resolvedUri = '';
      readContentUriAll = (uri) async {
        resolvedUri = uri;
        return 'test/fixtures/sample_multi_page.pdf';
      };

      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'content://com.example.provider/doc123');

      final segments = await indexer.indexBook(book).toList();

      expect(resolvedUri, 'content://com.example.provider/doc123');
      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2, 3, 4});
    });

    test('readContentUriAll 回傳 null 時拋出明確例外（而非讓 PdfDocument.openFile 收到 null）',
        () async {
      final original = readContentUriAll;
      addTearDown(() => readContentUriAll = original);
      readContentUriAll = (uri) async => null;

      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'content://com.example.provider/missing');

      expect(
        () => indexer.indexBook(book).toList(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/search/pdf_content_indexer_test.dart`
Expected: FAIL（`package:elinkbook/search/content_indexer.dart`／`package:elinkbook/search/pdf_content_indexer.dart` 不存在，編譯錯誤）。

- [x] **Step 3：實作 `ContentIndexer`／`IndexedSegment`**

新增 `app/lib/search/content_indexer.dart`：

```dart
// app/lib/search/content_indexer.dart
import '../library/models/book.dart';

/// 單一格式的內容擷取器，把一本書轉換成一連串可索引的精確定位片段
/// （epic-10-search Issue 1，見 spec.md §3.1）。
///
/// [PdfContentIndexer]（純 Dart/FFI）與 [FoliateContentIndexer]（驅動
/// HeadlessInAppWebView）是目前僅有的兩個實作，由 `ContentIndexingScheduler`
/// 依 `book.format` 分派。
abstract class ContentIndexer {
  /// [resumeFromChapter] 非 null 時從該章節（含）開始擷取，用於背景排程
  /// 暫停後的續跑（見 `content_indexing_scheduler.dart`）。yield 順序即寫入
  /// 順序，呼叫端逐筆寫入 `book_content_index` 並可隨時中斷（例如排程被
  /// 要求暫停）——中斷後尚未被呼叫端消費的 segment 會隨 Stream 一併捨棄，
  /// 這是刻意的簡化設計（見 plan-issue-1.md Global Constraints「暫停粒度」）。
  Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter});
}

/// 一個可索引、可精確跳轉的內容片段。
class IndexedSegment {
  /// Foliate：spine section index；PDF：頁碼（0-indexed）。
  final int chapterIndex;

  /// Foliate：CFI 字串；PDF：`jsonEncode({"page":int,"rect":{...}})`
  /// （`rect` 為 [PercentRect] 的欄位，見 `pdf_content_indexer.dart`）。
  final String locator;

  /// 原始文字（未經 `tokenizeForIndex()` 處理），供 UI 顯示片段用。
  final String rawText;

  const IndexedSegment({
    required this.chapterIndex,
    required this.locator,
    required this.rawText,
  });
}
```

新增 `app/lib/search/pdf_content_indexer.dart`：

```dart
// app/lib/search/pdf_content_indexer.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../library/models/book.dart';
import '../reader/pdf_search_geometry.dart';
import 'content_indexer.dart';

/// PDF 格式的內容擷取器（epic-10-search Issue 1，見 spec.md §3.2）。直接
/// `PdfDocument.openFile()`＋逐頁 `page.loadStructuredText()`（與
/// `pdf_reader_view.dart` 既有 `_search()` 邏輯同源），不需要 Widget、不需要
/// 額外 Isolate（`pdfrx` 底層已透過 `BackgroundWorker` 背景執行，比照既有
/// 「縮圖不需額外 Isolate」結論）。
///
/// 切片粒度為 [PdfPageTextFragment]（`pdfrx_engine` 既有型別，通常對應
/// PDF 內部一個連續文字排版區塊，例如一行），而非整頁一筆——比整頁粗略
/// 位置更精確，符合 design.md「精確位置級跳轉」目標。
///
/// 【review-plan-issue-1.md C-1 修正】`book.filePath` 依 ADR 0002 可能是
/// `content://` URI（SAF 匯入/資料夾匯入書籍）——PDFium FFI 的
/// `PdfDocument.openFile()` 底層是 C 標準檔案系統呼叫，完全無法解析
/// `content://`，必須先比照既有 `PdfReaderView._openContentUriDocument()`
/// （`pdf_reader_view.dart:470-483`）串流複製成本機暫存檔再開啟，並在處理
/// 完畢後刪除暫存檔。[readContentUriAll] 頂層函式變數（非固定函式宣告）
/// 比照 `foliate_native_bridge.dart` 的 `cacheBookForServing` 既有慣例，
/// 讓測試環境可以覆寫此變數完全繞過原生 MethodChannel 呼叫。
class PdfContentIndexer implements ContentIndexer {
  const PdfContentIndexer();

  @override
  Stream<IndexedSegment> indexBook(
    Book book, {
    int? resumeFromChapter,
  }) async* {
    final isContentUri = book.filePath.contains('://');
    final openPath = isContentUri
        ? await readContentUriAll(book.filePath)
        : book.filePath;
    if (openPath == null) {
      throw StateError('無法讀取 PDF 檔案：${book.filePath}');
    }

    final document = await PdfDocument.openFile(openPath);
    try {
      final startPage = resumeFromChapter ?? 0;
      for (var pageIndex = startPage;
          pageIndex < document.pages.length;
          pageIndex++) {
        final page = document.pages[pageIndex];
        final pageText = await page.loadStructuredText();
        for (final fragment in pageText.fragments) {
          final text = fragment.text.trim();
          if (text.isEmpty) continue;
          final rect = pdfRectToPercentRect(
            rect: fragment.bounds,
            pageWidth: page.width,
            pageHeight: page.height,
          );
          yield IndexedSegment(
            chapterIndex: pageIndex,
            locator: jsonEncode({
              'page': pageIndex,
              'rect': {
                'left': rect.left,
                'top': rect.top,
                'right': rect.right,
                'bottom': rect.bottom,
              },
            }),
            rawText: text,
          );
        }
      }
    } finally {
      await document.dispose();
      if (isContentUri) {
        final tmpFile = File(openPath);
        if (tmpFile.existsSync()) {
          try {
            tmpFile.deleteSync();
          } catch (_) {
            // 比照 pdf_reader_view.dart 既有 _cleanupTmpFile() 慣例：刪除
            // 失敗（例如檔案已被其他流程清空目錄）不應讓索引流程整體失敗。
          }
        }
      }
    }
  }
}

const _resourceChannel = MethodChannel('elinkbook/reader_resources');

/// 串流複製 `content://` URI 為本機暫存檔，回傳暫存檔路徑（失敗回傳
/// null）。與 `PdfReaderView._openContentUriDocument()` 呼叫同一條既有原生
/// 通道／方法（`elinkbook/reader_resources` 的 `readContentUriAll`），不
/// 新增原生端程式碼。頂層函式變數寫法（非固定函式宣告）比照
/// `foliate_native_bridge.dart` 的 `cacheBookForServing`，供測試覆寫。
Future<String?> Function(String uri) readContentUriAll =
    _defaultReadContentUriAll;

Future<String?> _defaultReadContentUriAll(String uri) {
  return _resourceChannel.invokeMethod<String>('readContentUriAll', {'uri': uri});
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/search/pdf_content_indexer_test.dart`
Expected: PASS（5 個 test）

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/content_indexer.dart app/lib/search/pdf_content_indexer.dart app/test/search/pdf_content_indexer_test.dart
git commit -m "feat(search): 新增 ContentIndexer 抽象介面與 PdfContentIndexer"
```

---

### Task 2：`main.js` 新增索引模式（`mode=index`／`getSectionCount`／`buildSegmentsForSection`）

**Files：**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces：**
- Consumes：既有 `window.buildTtsSegments()` 的句子切分/CFI 核心邏輯（原地重構抽出，不改變既有行為）。
- Produces：`window.getSectionCount()`（回呼 `onSectionCountReady`，參數為 `int`）、`window.buildSegmentsForSection(sectionIndex)`（回呼 `onSegmentsForSectionReady`，參數為 `(sectionIndex, jsonString)`，`jsonString` 格式與既有 `onTtsSegmentsReady` 完全相同：`[{segmentId, cfi, text}]`）——Task 3（`FoliateContentIndexer`）直接呼叫這兩個函式。

本 Task 沒有 Dart 測試可跑（純 JS 變更，且依賴 `view.book` 的真實 foliate-js 執行期狀態，無法脫離 WebView 單元測試）；正確性由 Task 3 的真機/模擬器 `integration_test` 驗證，本 Task 只要求語法正確。

- [x] **Step 1：新增 `isIndexMode` 旗標**

在 `app/android/app/src/main/assets/foliate/main.js` 找到：

```js
const initialCfi = params.get('initialCfi') || ''
```

（第 48 行）之後新增：

```js

// epic-10-search Issue 1：索引模式旗標（ADR 0027 決策 2）。true 時
// window.getSectionCount()/window.buildSegmentsForSection() 可用，且下方
// view.addEventListener('load', ...) 內的觸控/選取/劃線手勢初始化整段跳過
// （headless webview 永遠不會有真實觸控事件，該段邏輯掛著純屬浪費，非
// 錯誤來源，見 plan-issue-1.md Global Constraints）。
const isIndexMode = params.get('mode') === 'index'
```

- [x] **Step 2：抽出 `buildTtsSegments()` 共用核心，新增 `buildSegmentsForSection()`**

找到現有的 `window.buildTtsSegments = async function (sectionIndex) { ... }`（第 629-724 行，完整內容如下，含開頭/結尾的 doc comment）：

```js
window.buildTtsSegments = async function (sectionIndex) {
  try {
    const doc = await view.book.sections[sectionIndex].createDocument()
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        // 不分大小寫比對（審查 review-plan-issue-2.md Minor #1）：EPUB
        // 章節是 XHTML，走 XML 解析器而非 HTML 解析器，tagName 不會被
        // 自動正規化為大寫，不能保證所有書都乖乖用小寫標籤。
        const tag = node.parentElement
          ? node.parentElement.tagName.toUpperCase()
          : ''
        return (tag === 'RT' || tag === 'SCRIPT')
          ? NodeFilter.FILTER_REJECT
          : NodeFilter.FILTER_ACCEPT
      },
    })

    let fullText = ''
    const offsetMap = []
    let node = walker.nextNode()
    while (node) {
      const text = node.textContent || ''
      for (let i = 0; i < text.length; i++) {
        offsetMap.push({ node, offset: i })
      }
      fullText += text
      node = walker.nextNode()
    }

    const terminators = /[。！？；.!?;]/
    const TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200
    const secondaryBoundary = /\s/
    const segments = []
    let start = 0
    let segmentIndex = 0
    for (let i = 0; i < fullText.length; i++) {
      const isLast = i === fullText.length - 1
      const isPrimaryBoundary = terminators.test(fullText[i])
      const isSecondaryBoundary = !isPrimaryBoundary &&
        (i - start) >= TTS_SECONDARY_BOUNDARY_MIN_LENGTH &&
        secondaryBoundary.test(fullText[i])
      if (isPrimaryBoundary || isSecondaryBoundary || isLast) {
        let rangeStart = start
        while (rangeStart < i && /\s/.test(fullText[rangeStart])) rangeStart++
        const trimmed = fullText.slice(start, i + 1).trim()
        if (trimmed.length > 0) {
          const startMap = offsetMap[rangeStart]
          const endMap = offsetMap[i]
          const range = doc.createRange()
          range.setStart(startMap.node, startMap.offset)
          range.setEnd(endMap.node, endMap.offset + 1)
          const cfi = view.getCFI(sectionIndex, range)
          segments.push({ segmentId: String(segmentIndex), cfi, text: trimmed })
          segmentIndex++
        }
        start = i + 1
      }
    }

    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify(segments),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify([]),
    )
  }
}
```

整段取代為（保留完全相同的既有內文說明 doc comment，此處省略未變動的 doc comment 本文，實作時原封不動保留 Step 2 標的區塊上方既有的整段 doc comment，只替換程式碼本體）：

```js
/**
 * 建立指定章節（section）的「句子 → CFI」對照表核心邏輯（epic-34-tts-readalong
 * Issue 2；epic-10-search Issue 1 抽出共用，供 window.buildTtsSegments()／
 * window.buildSegmentsForSection() 共用，避免同一段複雜邏輯維護兩份）。
 * 回傳純陣列（不呼叫 callHandler），呼叫端各自決定要回呼哪個 handler
 * name。邏輯本身與抽出前完全相同、零行為變更。
 */
async function extractSegmentsForSection(sectionIndex) {
  const doc = await view.book.sections[sectionIndex].createDocument()
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => {
      const tag = node.parentElement
        ? node.parentElement.tagName.toUpperCase()
        : ''
      return (tag === 'RT' || tag === 'SCRIPT')
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT
    },
  })

  let fullText = ''
  const offsetMap = []
  let node = walker.nextNode()
  while (node) {
    const text = node.textContent || ''
    for (let i = 0; i < text.length; i++) {
      offsetMap.push({ node, offset: i })
    }
    fullText += text
    node = walker.nextNode()
  }

  const terminators = /[。！？；.!?;]/
  const TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200
  const secondaryBoundary = /\s/
  const segments = []
  let start = 0
  let segmentIndex = 0
  for (let i = 0; i < fullText.length; i++) {
    const isLast = i === fullText.length - 1
    const isPrimaryBoundary = terminators.test(fullText[i])
    const isSecondaryBoundary = !isPrimaryBoundary &&
      (i - start) >= TTS_SECONDARY_BOUNDARY_MIN_LENGTH &&
      secondaryBoundary.test(fullText[i])
    if (isPrimaryBoundary || isSecondaryBoundary || isLast) {
      let rangeStart = start
      while (rangeStart < i && /\s/.test(fullText[rangeStart])) rangeStart++
      const trimmed = fullText.slice(start, i + 1).trim()
      if (trimmed.length > 0) {
        const startMap = offsetMap[rangeStart]
        const endMap = offsetMap[i]
        const range = doc.createRange()
        range.setStart(startMap.node, startMap.offset)
        range.setEnd(endMap.node, endMap.offset + 1)
        const cfi = view.getCFI(sectionIndex, range)
        segments.push({ segmentId: String(segmentIndex), cfi, text: trimmed })
        segmentIndex++
      }
      start = i + 1
    }
  }
  return segments
}

/**
 * 供 Dart 端 FoliateReaderView.loadTtsSegments()（透過
 * InAppWebViewController.evaluateJavascript）呼叫；非同步計算完成後主動
 * 透過 window.flutter_inappwebview.callHandler('onTtsSegmentsReady', ...)
 * 回呼 Dart 端（evaluateJavascript 不會等待內部 Promise resolve）。
 */
window.buildTtsSegments = async function (sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex)
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify(segments),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify([]),
    )
  }
}

/**
 * epic-10-search Issue 1：背景批次索引專用——與 window.buildTtsSegments()
 * 呼叫完全相同的核心邏輯（見 extractSegmentsForSection()），差異只在回呼
 * 的 handler name，讓 Dart 端 FoliateContentIndexer 可以用獨立於 TTS 播放
 * 路徑的 handler 註冊，避免兩條呼叫路徑共用同一個 handler 名稱造成混淆。
 * 供 Dart 端 FoliateContentIndexer（透過 InAppWebViewController.evaluateJavascript）
 * 依序對每個 section 呼叫。
 */
window.buildSegmentsForSection = async function (sectionIndex) {
  try {
    const segments = await extractSegmentsForSection(sectionIndex)
    window.flutter_inappwebview.callHandler(
      'onSegmentsForSectionReady', sectionIndex, JSON.stringify(segments),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onSegmentsForSectionReady', sectionIndex, JSON.stringify([]),
    )
  }
}

/**
 * epic-10-search Issue 1：回報書籍總章節（spine section）數，供 Dart 端
 * FoliateContentIndexer 決定要呼叫幾次 window.buildSegmentsForSection()。
 * 呼叫時機須在書籍載入完成之後（既有 onPageRendered 訊號，見
 * foliate_content_indexer.dart 說明）。
 */
window.getSectionCount = function () {
  try {
    const count = view.book && view.book.sections ? view.book.sections.length : 0
    window.flutter_inappwebview.callHandler('onSectionCountReady', count)
  } catch (e) {
    window.flutter_inappwebview.callHandler('onSectionCountReady', 0)
  }
}
```

- [x] **Step 3：`view.addEventListener('load', ...)` 加上 `isIndexMode` guard**

找到：

```js
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index
      const classifier = new TouchIntentClassifier()
```

（第 951-954 行）取代為：

```js
    view.addEventListener('load', (e) => {
      // epic-10-search Issue 1：索引模式下不需要任何觸控/選取/劃線手勢
      // 初始化（headless webview 不會有真實觸控事件），提早 return 跳過
      // 這整段（見上方 isIndexMode 宣告處的說明）。
      if (isIndexMode) return
      const doc = e.detail.doc
      const index = e.detail.index
      const classifier = new TouchIntentClassifier()
```

- [x] **Step 4：語法檢查**

Run: `node --check app/android/app/src/main/assets/foliate/main.js`
Expected: 無輸出（exit code 0，代表語法合法）。

- [x] **Step 5：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(search): main.js 新增索引模式（mode=index/getSectionCount/buildSegmentsForSection）"
```

---

### Task 3：`FoliateContentIndexer`（驅動 `HeadlessInAppWebView`）

**Files：**
- Create: `app/lib/search/foliate_content_indexer.dart`
- Modify: `app/lib/reader/foliate_native_bridge.dart`（Step 0：新增公開常數 `esCompatPolyfillJs`／`globalErrorCaptureJs`）
- Modify: `app/lib/reader/foliate_reader_view.dart:29-152,172-198`（Step 0：移除本地私有常數，改用上述公開常數）
- Test: `app/integration_test/foliate_content_indexer_test.dart`（真機/模擬器，比照專案既有「牽涉 WebView 渲染的行為一律在 `integration_test/` 驗證」慣例）

**Interfaces：**
- Consumes：Task 1 的 `ContentIndexer`／`IndexedSegment`；既有 `app/lib/reader/foliate_native_bridge.dart` 的 `cacheBookForServing`／`loadAndroidAsset`／`cacheFileExtension`（Step 0 起也含新搬移進來的 `esCompatPolyfillJs`／`globalErrorCaptureJs`）；既有 `app/lib/reader/js_bridge_gateway.dart` 的 `JsBridgeGateway`；既有 `app/lib/reader/tts_segment_cfi.dart`／`app/lib/reader/foliate_bridge_codec.dart` 的 `TtsSegmentCfi`／`parseTtsSegments()`；Task 2 的 `window.getSectionCount()`／`window.buildSegmentsForSection()`。
- Produces：`class FoliateContentIndexer implements ContentIndexer`——Task 5（`ContentIndexingScheduler`）直接使用；`foliate_native_bridge.dart` 新增公開常數 `esCompatPolyfillJs`／`globalErrorCaptureJs`（`FoliateReaderView` 同步改為 import 使用，見 Step 0）。

- [x] **Step 0：抽出共用 ES 相容性 polyfill／全域錯誤捕捉腳本（`review-plan-issue-1.md` I-1）**

`HeadlessInAppWebView` 載入的是與 `FoliateReaderView` 完全相同的 `assets/foliate/main.js`／`view.js`／`epub.js`（`readest/foliate-js` 釘定版本），在較舊 Android System WebView（例如 `AGENTS.md` 記錄的 iReader Ocean 4 Plus，Chromium 83）上會遇到完全相同的 ES2021+ API 缺席問題（`Object.groupBy`／`Array.prototype.at`／`WeakRef` 等）；`FoliateReaderView` 目前透過 `_esCompatPolyfillJs`（`foliate_reader_view.dart:70-152`）／`_globalErrorCaptureJs`（`foliate_reader_view.dart:185-198`）兩個檔案私有 `const` 字串，以 `initialUserScripts` 在 `AT_DOCUMENT_START` 注入解決，但 `FoliateContentIndexer` 目前完全沒有注入這兩段腳本——舊裝置上 headless webview 會直接卡死，且缺少 `globalErrorCaptureJs` 轉送 `window.onerror`/`onunhandledrejection` 到既有 `onError` handler，Dart 端只能乾等滿 30 秒逾時，不會提早得知真正原因。

把這兩個常數**逐字搬移**（doc comment 一併搬移，內容不變，只改可見度：拿掉開頭底線變成公開常數）到 `app/lib/reader/foliate_native_bridge.dart`，讓兩個檔案都能 import 使用，不重複維護兩份：

- 從 `app/lib/reader/foliate_reader_view.dart` 剪下第 29-152 行（`_esCompatPolyfillJs` 完整 doc comment ＋ 常數本體）與第 172-198 行（`_globalErrorCaptureJs` 完整 doc comment ＋ 常數本體），貼到 `app/lib/reader/foliate_native_bridge.dart` 檔案尾端，兩處常數名稱各自拿掉開頭底線：`_esCompatPolyfillJs` → `esCompatPolyfillJs`，`_globalErrorCaptureJs` → `globalErrorCaptureJs`。
- 在 `app/lib/reader/foliate_reader_view.dart` 原本兩段的位置留白處，把 `initialUserScripts` 清單裡的兩處引用（`_esCompatPolyfillJs`／`_globalErrorCaptureJs`，約在 `build()` 方法的 `UnmodifiableListView<UserScript>([...])` 內）改為不帶底線的 `esCompatPolyfillJs`／`globalErrorCaptureJs`（既有 import `foliate_native_bridge.dart` 已存在，不需新增 import）。
- `app/lib/reader/foliate_native_bridge.dart` 頂部若尚未 import，本次搬移的兩段純字串常數不需要額外 import（字串常值不依賴其他型別）。

Run: `flutter analyze`
Expected: `No issues found!`（純搬移，`FoliateReaderView` 既有測試零回歸——不需要另外執行測試，Step 4 會與 Task 3 其餘變更一併驗證）。

- [x] **Step 1：實作 `FoliateContentIndexer`**

新增 `app/lib/search/foliate_content_indexer.dart`：

```dart
// app/lib/search/foliate_content_indexer.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../library/models/book.dart';
import '../reader/foliate_bridge_codec.dart';
import '../reader/foliate_native_bridge.dart';
import '../reader/js_bridge_gateway.dart';
import '../reader/tts_segment_cfi.dart';
import 'content_indexer.dart';

/// Foliate 格式（EPUB／KF8／CBZ／TXT／MD，皆經 readest/foliate-js 單引擎）
/// 的內容擷取器（epic-10-search Issue 1，見 spec.md §3.2、ADR 0027 決策 2）。
///
/// 驅動一個獨立於一般閱讀畫面之外的 `HeadlessInAppWebView`，載入與
/// `FoliateReaderView` 相同的 `assets/foliate/index.html` 資源，帶
/// `mode=index` 旗標進入索引模式。重用既有
/// `cacheBookForServing()`／`InternalStoragePathHandler` 三件套讓 headless
/// webview 能讀到書籍內容（不是單純帶 URL query 就能運作，見 spec.md §3.2）。
///
/// 單書處理完畢、被中斷或例外時**無條件**執行 dispose + 刪除快取子目錄
/// （比照 `foliate_reader_view.dart` 既有 `dispose()` 清理邏輯），避免磁碟
/// 空間洩漏；下一本書重新建立全新實例與快取子目錄（ADR 0027 決策 3）。
class FoliateContentIndexer implements ContentIndexer {
  const FoliateContentIndexer();

  @override
  Stream<IndexedSegment> indexBook(
    Book book, {
    int? resumeFromChapter,
  }) async* {
    final instanceId = 'index-${book.id}';
    String? cacheDir;
    HeadlessInAppWebView? headlessWebView;
    InAppWebViewController? controller;

    try {
      final cachedPath = await cacheBookForServing(book.filePath, instanceId);
      if (cachedPath == null) {
        throw StateError('無法快取書籍檔案：${book.filePath}');
      }
      cacheDir = File(cachedPath).parent.path;

      final readyCompleter = Completer<void>();
      late final JsBridgeGateway gateway;

      // 【review-plan-issue-1.md I-2】章節擷取專用的獨立完成狀態——刻意不
      // 透過 JsBridgeGateway._pending（以 handler name 為單一插槽鍵）處理
      // 這個會在同一次 indexBook() 呼叫內對同一個 handler name 循環發出
      // 多次請求的場景：若某一章逾時後 Dart 端已提早發出下一章請求，稍後
      // 遲到抵達的舊章節回應會被 gateway 誤判成「下一章的回應」而完成
      // 錯誤的 completer，造成章節資料互相錯位污染（審查已用具體時序
      // 證實這個競態可重現，不是理論疑慮）。改由本類別自行維護「目前
      // 預期的章節索引」與對應 completer，callback 內比對章節索引，不符
      // 就直接捨棄，不透過 gateway 的通用配對機制。
      int? expectedSectionIndex;
      Completer<List<TtsSegmentCfi>>? sectionCompleter;

      void evaluate(String js) => controller?.evaluateJavascript(source: js);

      headlessWebView = HeadlessInAppWebView(
        // 明確指定非退化尺寸，見 plan-issue-1.md Global Constraints——
        // 套件預設值 Size(-1,-1) 對 foliate-js 的版面初始化語意不明確。
        initialSize: const Size(800, 1280),
        initialUrlRequest: URLRequest(url: WebUri.uri(_buildIndexUri(book))),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldInterceptRequest: true,
          webViewAssetLoader: WebViewAssetLoader(
            pathHandlers: [
              InternalStoragePathHandler(path: '/book/', directory: cacheDir),
            ],
          ),
        ),
        // 【review-plan-issue-1.md I-1】與 FoliateReaderView 共用同一套
        // ES 相容性 polyfill／全域錯誤捕捉腳本（見 Step 0）——headless
        // webview 載入的是同一份 main.js／view.js／epub.js，在較舊 Android
        // System WebView 上會遇到完全相同的 ES2021+ API 缺席風險；缺少
        // globalErrorCaptureJs 時，vendor 腳本在文件載入極早期拋出的例外
        // 不會回報 onError，readyCompleter 會乾等滿 30 秒逾時才失敗，而非
        // 立即得知真正原因。
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: esCompatPolyfillJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          UserScript(
            source: globalErrorCaptureJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        shouldInterceptRequest: _shouldInterceptIndexRequest,
        onWebViewCreated: (c) {
          controller = c;
          gateway = JsBridgeGateway(
            evaluate: evaluate,
            registerHandler: (name, callback) =>
                c.addJavaScriptHandler(handlerName: name, callback: callback),
          );
          gateway.register<int>(
            handlerName: 'onSectionCountReady',
            parse: (args) =>
                args.isNotEmpty ? (args[0] as num).toInt() : 0,
            fallback: 0,
          );
          // 【review-plan-issue-1.md I-2】onSegmentsForSectionReady 刻意
          // 不透過 gateway.register()，改直接註冊原生 handler 自行比對
          // 章節索引（見上方 expectedSectionIndex 註解）。
          c.addJavaScriptHandler(
            handlerName: 'onSegmentsForSectionReady',
            callback: (args) {
              final receivedIndex =
                  args.isNotEmpty ? (args[0] as num).toInt() : -1;
              if (receivedIndex != expectedSectionIndex) {
                // 過期或不相關的回呼（例如上一章逾時後才遲到抵達），直接
                // 捨棄，不完成任何 completer。
                return null;
              }
              final completer = sectionCompleter;
              sectionCompleter = null;
              completer?.complete(
                parseTtsSegments(args.length > 1 ? args[1] as String : '[]'),
              );
              return null;
            },
          );
          c.addJavaScriptHandler(
            handlerName: 'onPageRendered',
            callback: (args) {
              if (!readyCompleter.isCompleted) readyCompleter.complete();
            },
          );
          c.addJavaScriptHandler(
            handlerName: 'onError',
            callback: (args) {
              if (!readyCompleter.isCompleted) {
                readyCompleter.completeError(
                  StateError(args.isNotEmpty ? args[0] as String : '未知錯誤'),
                );
              }
            },
          );
        },
      );

      await headlessWebView.run();
      await readyCompleter.future.timeout(const Duration(seconds: 30));

      // 【review-plan-issue-1.md I-4 延伸，同一種「靜默吞掉錯誤」風險】
      // 若沿用 JsBridgeGateway.request() 內建的 timeout 參數，逾時後會
      // 靜默回退 fallback（0），讓下方 for 迴圈直接跑 0 次、整本書被誤判
      // 為「已完成」寫入 0 筆資料且永遠不會重試。改為不傳 gateway 的
      // timeout 參數，外層用 .timeout()＋onTimeout 主動 throw，取代靜默
      // 回退的既有行為。
      final sectionCount = await gateway
          .request<int>(
            jsCall: 'window.getSectionCount()',
            handlerName: 'onSectionCountReady',
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('window.getSectionCount() 逾時'),
          );

      final startSection = resumeFromChapter ?? 0;
      for (var sectionIndex = startSection;
          sectionIndex < sectionCount;
          sectionIndex++) {
        expectedSectionIndex = sectionIndex;
        final completer = Completer<List<TtsSegmentCfi>>();
        sectionCompleter = completer;
        evaluate('window.buildSegmentsForSection($sectionIndex)');
        // 【review-plan-issue-1.md I-2】逾時直接拋例外中斷整本書的處理
        // （由 ContentIndexingScheduler 既有的 catch 區塊標記
        // status='error'，下次排程可重新嘗試整本書），不可靜默回退空
        // 清單——那會讓這個章節的內容永久性、無聲地漏索引，且不會有任何
        // 錯誤訊號可供排查。逾時視窗放寬到 30 秒（原 15 秒對低階電子紙
        // 裝置的 headless WebView 解析大型章節可能過於嚴苛，見審查建議）。
        final segments = await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            sectionCompleter = null;
            throw TimeoutException(
                'window.buildSegmentsForSection($sectionIndex) 逾時');
          },
        );
        for (final segment in segments) {
          if (segment.cfi.isEmpty || segment.text.trim().isEmpty) continue;
          yield IndexedSegment(
            chapterIndex: sectionIndex,
            locator: segment.cfi,
            rawText: segment.text,
          );
        }
      }
    } finally {
      await headlessWebView?.dispose();
      if (cacheDir != null) {
        final dir = Directory(cacheDir);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      }
    }
  }

  Uri _buildIndexUri(Book book) {
    return Uri.https(
      'appassets.androidplatform.net',
      '/assets/foliate/index.html',
      {
        'bookFileName': 'current.${cacheFileExtension(book.filePath)}',
        'mode': 'index',
      },
    );
  }

  /// 索引模式只需要能載入 `assets/foliate/` 底下的靜態檔案（`index.html`／
  /// `main.js`／`view.js` 等），不需要字型攔截（索引模式不渲染任何可視文字，
  /// `prefs`/`fontFaceCss` 查詢參數皆未帶入，預設空值不會觸發字型請求）——
  /// 比照 `foliate_reader_view.dart` `_shouldInterceptRequest()` 精簡版。
  static Future<WebResourceResponse?> _shouldInterceptIndexRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final path = request.url.path;
    const foliateAssetsPrefix = '/assets/foliate/';
    if (path.startsWith(foliateAssetsPrefix)) {
      final relative = 'foliate/${path.substring(foliateAssetsPrefix.length)}';
      final bytes = await loadAndroidAsset(relative);
      if (bytes == null) return null;
      final contentType =
          path.endsWith('.js') ? 'text/javascript' : 'text/html';
      return WebResourceResponse(contentType: contentType, data: bytes);
    }
    return null;
  }
}
```

> **I-2 修法的測試覆蓋範圍說明**：`expectedSectionIndex`／`sectionCompleter` 是 `indexBook()` 內的區域變數，無法脫離真實 `HeadlessInAppWebView` 獨立單元測試；要用自動化測試**可靠重現**「某章逾時後下一章請求緊接發出、舊章節遲到回應」這個精確時序，需要能刻意讓 JS 端延遲回應的假 WebView 測試替身，目前專案的 `fake_inappwebview_platform.dart`（`foliate_reader_view_test.dart` 既有慣例）不支援模擬 JS handler 逾時時序，投入這類測試替身的成本與本工單其餘範圍不成比例。本修法的正確性由上方程式碼的邏輯推理與審查報告已重現的具體時序保證（見 `review-plan-issue-1.md` I-2），實作階段若發現有更低成本的驗證方式，可另外補上，非本計畫的阻斷項。

- [x] **Step 2：`flutter analyze`＋確認 Step 0 搬移零回歸（先確認編譯通過，本 Task 主要驗證留給 Step 3 的真機測試）**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數通過（Step 0 純粹搬移 `_esCompatPolyfillJs`／`_globalErrorCaptureJs` 到 `foliate_native_bridge.dart` 並改名去底線，`FoliateReaderView` 的 `initialUserScripts` 清單內容不變，這個既有測試檔案應零回歸）。

- [x] **Step 3：寫真機/模擬器整合測試**

新增 `app/integration_test/foliate_content_indexer_test.dart`：

```dart
// app/integration_test/foliate_content_indexer_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FoliateContentIndexer 對 3 章節 EPUB fixture 正確擷取每章句子與 CFI',
      (tester) async {
    // test/fixtures/sample_multi_chapter.epub：3 個 spine section
    // （chapter1/2/3.xhtml），內容已知（見 plan-issue-1.md 規劃階段查證）：
    // 第 1 章 8 段、第 2 章 16 段（含第一節/第二節）、第 3 章 8 段，各段
    // 皆含「這是第 N 章第 M 段內容」字樣，三章內容彼此明顯不同。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_indexer_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final book = Book(
      id: 'foliate-indexer-test-book',
      title: '索引器整合測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    const indexer = FoliateContentIndexer();
    final segments = await indexer.indexBook(book).toList();

    expect(segments, isNotEmpty);
    expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2},
        reason: '3 個 spine section，chapterIndex 應涵蓋 0-2');

    for (final segment in segments) {
      expect(segment.locator, startsWith('epubcfi('),
          reason: 'Foliate 格式 locator 必須是合法 CFI 字串');
      expect(segment.rawText.trim(), isNotEmpty);
    }

    final textBySection = <int, String>{};
    for (final segment in segments) {
      textBySection[segment.chapterIndex] =
          (textBySection[segment.chapterIndex] ?? '') + segment.rawText;
    }
    expect(textBySection[0], contains('第 1 章'));
    expect(textBySection[1], contains('第 2 章'));
    expect(textBySection[2], contains('第 3 章'));
  });

  testWidgets('FoliateContentIndexer resumeFromChapter 只從指定 section（含）開始擷取',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_indexer_resume.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final book = Book(
      id: 'foliate-indexer-resume-book',
      title: '索引器續跑測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    const indexer = FoliateContentIndexer();
    final segments =
        await indexer.indexBook(book, resumeFromChapter: 2).toList();

    expect(segments, isNotEmpty);
    expect(segments.map((s) => s.chapterIndex).toSet(), {2});
    expect(
      segments.map((s) => s.rawText).join(),
      contains('第 3 章'),
    );
  });
}
```

Run: `flutter test integration_test/foliate_content_indexer_test.dart -d <device-id>`
Expected: PASS（2 個 test；需要真實 Android 裝置/模擬器，一般 `flutter test` 無法執行這個檔案）。

- [x] **Step 4：Commit**

```bash
git add app/lib/search/foliate_content_indexer.dart app/lib/reader/foliate_native_bridge.dart app/lib/reader/foliate_reader_view.dart app/integration_test/foliate_content_indexer_test.dart
git commit -m "feat(search): 新增 FoliateContentIndexer（HeadlessInAppWebView 驅動批次擷取）"
```

---

### Task 4：`ReaderActivityTracker`＋`ReaderScreen` 整合

**Files：**
- Create: `app/lib/reader/reader_activity_tracker.dart`
- Modify: `app/lib/screens/reader_screen.dart:187-`（建構子）、`initState()`（約第 449 行）、`dispose()`（約第 570 行）
- Test: `app/test/reader/reader_activity_tracker_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`（新增一則測試）

**Interfaces：**
- Produces：`class ReaderActivityTracker extends ChangeNotifier { bool get isReaderOpen; void markReaderOpened(); void markReaderClosed(); }`——Task 5（`ContentIndexingScheduler`）與 Task 6（`main.dart`／`library_screen.dart` 貫穿）使用。`ReaderScreen` 新增可選具名參數 `readerActivityTracker`（比照 `bookmarksRepository` 等既有可選參數慣例，未提供時零回歸）。

- [x] **Step 1：寫一個會失敗的測試——`ReaderActivityTracker` 基本行為**

新增 `app/test/reader/reader_activity_tracker_test.dart`：

```dart
// app/test/reader/reader_activity_tracker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';

void main() {
  group('ReaderActivityTracker', () {
    test('初始狀態為未開啟', () {
      final tracker = ReaderActivityTracker();
      expect(tracker.isReaderOpen, isFalse);
    });

    test('markReaderOpened() 後 isReaderOpen 為 true 且通知監聽者', () {
      final tracker = ReaderActivityTracker();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderOpened();

      expect(tracker.isReaderOpen, isTrue);
      expect(notifyCount, 1);
    });

    test('markReaderClosed() 後 isReaderOpen 為 false 且通知監聽者', () {
      final tracker = ReaderActivityTracker();
      tracker.markReaderOpened();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderClosed();

      expect(tracker.isReaderOpen, isFalse);
      expect(notifyCount, 1);
    });

    test('重複呼叫同一狀態不重複通知（idempotent）', () {
      final tracker = ReaderActivityTracker();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderClosed(); // 已經是 false，不應通知
      expect(notifyCount, 0);

      tracker.markReaderOpened();
      tracker.markReaderOpened(); // 已經是 true，不應重複通知
      expect(notifyCount, 1);
    });
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/reader/reader_activity_tracker_test.dart`
Expected: FAIL（`package:elinkbook/reader/reader_activity_tracker.dart` 不存在，編譯錯誤）。

- [x] **Step 3：實作 `ReaderActivityTracker`**

新增 `app/lib/reader/reader_activity_tracker.dart`：

```dart
// app/lib/reader/reader_activity_tracker.dart
import 'package:flutter/foundation.dart';

/// 追蹤「目前是否有任何閱讀畫面（[ReaderScreen]）開啟」（epic-10-search
/// Issue 1，見 spec.md §3.3）。`ContentIndexingScheduler` 監聽本類別，只在
/// [isReaderOpen] 為 false 且 App 前台時才處理背景索引佇列——使用者一旦
/// 開啟任何一本書，排程器須立即暫停，避免背景索引與使用者正在閱讀互相
/// 搶資源。
///
/// 全域單例（由 `main.dart` 建構一次，經既有依賴注入模式往下傳遞），
/// 由每個 [ReaderScreen] 實例的 `initState()`/`dispose()` 呼叫
/// [markReaderOpened]/[markReaderClosed]。
class ReaderActivityTracker extends ChangeNotifier {
  bool _isReaderOpen = false;

  bool get isReaderOpen => _isReaderOpen;

  void markReaderOpened() {
    if (_isReaderOpen) return;
    _isReaderOpen = true;
    notifyListeners();
  }

  void markReaderClosed() {
    if (!_isReaderOpen) return;
    _isReaderOpen = false;
    notifyListeners();
  }
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/reader/reader_activity_tracker_test.dart`
Expected: PASS（4 個 test）

- [x] **Step 5：`ReaderScreen` 新增可選參數並於 `initState()`/`dispose()` 呼叫**

在 `app/lib/screens/reader_screen.dart` 頂部 import 區塊新增：

```dart
import '../reader/reader_activity_tracker.dart';
```

在 `class ReaderScreen` 欄位宣告區（`isEinkMode` 欄位之後，約第 185 行）新增：

```dart

  /// 供背景全文檢索排程器（epic-10-search Issue 1）得知「目前有閱讀畫面
  /// 開啟」而暫停處理，避免與使用者正在閱讀互搶資源。刻意為可選參數——
  /// 比照 [bookmarksRepository] 既有慣例，未提供時零回歸（單純不通知任何
  /// tracker，行為等同本 Issue 之前）。
  final ReaderActivityTracker? readerActivityTracker;
```

建構子（約第 187-208 行）的具名參數列新增一行：

```dart
    this.readerActivityTracker,
```

（放在既有 `this.isEinkMode = false,` 之後或任一位置皆可，具名可選參數順序不影響呼叫端。）

`_ReaderScreenState.initState()`（約第 449 行）於 `super.initState();` 之後新增：

```dart
    widget.readerActivityTracker?.markReaderOpened();
```

`_ReaderScreenState.dispose()`（約第 570 行）於方法開頭（`_syncCheckpointTimer?.cancel();` 之前或之後皆可，這裡選擇緊接在方法開頭）新增：

```dart
    widget.readerActivityTracker?.markReaderClosed();
```

- [x] **Step 6：寫一個會失敗的測試——`ReaderScreen` 呼叫 tracker**

在 `app/test/screens/reader_screen_test.dart` 找一個既有的、建構 `ReaderScreen` 後立即 `pumpWidget` 並可觸發 dispose（例如既有測試裡「切換到另一個畫面」或「pumpWidget 一個空 widget 取代」的既有慣例）的測試附近，新增：

```dart
  testWidgets('readerActivityTracker 提供時，開啟/離開閱讀畫面會呼叫 markReaderOpened/markReaderClosed',
      (tester) async {
    final tracker = ReaderActivityTracker();
    expect(tracker.isReaderOpen, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'reader-activity-tracker-test-book',
          prefsManager: FakeReaderPrefsManager(),
          readerActivityTracker: tracker,
        ),
      ),
    );
    await tester.pump();

    expect(tracker.isReaderOpen, isTrue, reason: '開啟閱讀畫面後應標記為已開啟');

    // 換掉整棵 widget 樹讓 ReaderScreen dispose。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(tracker.isReaderOpen, isFalse, reason: '離開閱讀畫面後應標記為已關閉');
  });
```

（`FakeReaderPrefsManager` 沿用檔案內既有的假物件；若既有慣例是不同名稱的假 `ReaderPrefsManager`，比照該檔案既有其他測試的實際建構方式調整，不需要另建新的假物件類別。同時在檔案頂部 import 區塊新增 `import 'package:elinkbook/reader/reader_activity_tracker.dart';`。）

- [x] **Step 7：執行測試，確認失敗然後實作後通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "readerActivityTracker"`
Expected: Step 5 完成前 FAIL（找不到具名參數），Step 5 完成後 PASS。

- [x] **Step 8：執行整個 `reader_screen_test.dart`，確認沒有破壞既有測試**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過（這個檔案改動的是建構子與 `initState`/`dispose`，屬高影響範圍變更，務必跑一次全檔案）。

- [x] **Step 9：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 10：Commit**

```bash
git add app/lib/reader/reader_activity_tracker.dart app/lib/screens/reader_screen.dart app/test/reader/reader_activity_tracker_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(search): 新增 ReaderActivityTracker 並整合進 ReaderScreen 生命週期"
```

---

### Task 5：`ContentIndexingScheduler`

**Files：**
- Create: `app/lib/search/content_indexing_scheduler.dart`
- Test: `app/test/search/content_indexing_scheduler_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `ContentIndexer`／`IndexedSegment`；Task 4 的 `ReaderActivityTracker`；Issue 0 的 `tokenizeForIndex()`（`app/lib/search/cjk_tokenizer.dart`）與三張資料表；`Book.fromMap()`（`app/lib/library/models/book.dart:158`）。
- Produces：`class ContentIndexingScheduler with WidgetsBindingObserver`——`start()`／`stop()`／`dispose()`／`handleAppLifecycleStateChanged(AppLifecycleState)`（測試可直接呼叫，不需要真正的 `WidgetsBindingObserver` 註冊）／`requestProcessing()`（review-plan-issue-1.md I-4，供 Issue 2／3 新插入 `pending` 列後主動喚醒排程器）。Task 6（`main.dart`）呼叫 `start()`；Issue 2／3（本工單範圍外）預期呼叫 `requestProcessing()`。

- [x] **Step 1：寫一個會失敗的測試——三種狀態轉換＋續跑游標**

新增 `app/test/search/content_indexing_scheduler_test.dart`：

```dart
// app/test/search/content_indexing_scheduler_test.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/search/content_indexer.dart';
import 'package:elinkbook/search/content_indexing_scheduler.dart';

/// 測試用假索引器：由測試逐一 `add()` segment 到 [_controller]，讓測試能
/// 精確控制「排程器在處理到哪個章節時，外部條件（App 背景化/開閱讀畫面）
/// 發生變化」，不需要真正的 PDF/WebView I/O。
class _FakeContentIndexer implements ContentIndexer {
  final _controller = StreamController<IndexedSegment>();
  int? lastResumeFromChapter;

  /// 【審查修正】`lastResumeFromChapter` 預設值本來就是 null，若
  /// `resumeFromChapter` 傳入剛好也是 null，單看 `lastResumeFromChapter`
  /// 無法區分「indexBook() 從未被呼叫」與「indexBook(resumeFromChapter:
  /// null) 確實被呼叫過」——用獨立布林旗標明確記錄「是否真的被呼叫過」，
  /// 避免測試在排程器根本沒有分派時也誤判通過。
  bool wasCalled = false;

  /// 【I-3 測試用】記錄最後一次 indexBook() 收到的 [Book]——同一個假索引器
  /// 實例可能先後服務多本同格式的書，單看 `wasCalled` 無法分辨「被呼叫過」
  /// 與「被呼叫時傳入的是哪一本書」，佇列排序測試需要後者才能斷言正確性。
  Book? lastBook;

  void addSegment(IndexedSegment segment) => _controller.add(segment);
  Future<void> finish() => _controller.close();

  @override
  Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter}) {
    wasCalled = true;
    lastBook = book;
    lastResumeFromChapter = resumeFromChapter;
    return _controller.stream;
  }
}

Book _book(String id, {BookFileFormat format = BookFileFormat.epub}) {
  return Book(
    id: id,
    title: '測試書 $id',
    format: format,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

void main() {
  late SqliteLibraryRepository repository;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = repository.database;
  });

  tearDown(() => repository.close());

  Future<void> insertPendingBook(Book book, {int? lastChapterIndex}) async {
    await repository.insertBook(book);
    await db.insert('content_index_status', {
      'book_id': book.id,
      'status': 'pending',
      'last_chapter_index': lastChapterIndex,
      'updated_at': 1000,
    });
  }

  Future<Map<String, Object?>> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.single;
  }

  group('ContentIndexingScheduler', () {
    test('App 前台且無閱讀畫面開啟時，處理完一本書後狀態轉為 done', () async {
      final tracker = ReaderActivityTracker();
      final pdfIndexer = _FakeContentIndexer();
      final foliateIndexer = _FakeContentIndexer();
      final book = _book('book-1');
      await insertPendingBook(book);

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: pdfIndexer,
        foliateIndexer: foliateIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一段'));
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/4)', rawText: '第二段'));
      await foliateIndexer.finish();
      await Future<void>.delayed(Duration.zero);

      final status = await statusOf('book-1');
      expect(status['status'], 'done');

      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRows, hasLength(2));
      expect(indexRows.map((r) => r['token_text']), everyElement(isNotEmpty));

      final ftsRows = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '第 一'");
      expect(ftsRows, isNotEmpty, reason: '寫入應觸發 Issue 0 的 FTS5 同步 trigger');
    });

    test('PDF 格式書籍分派給 pdfIndexer，非 PDF 分派給 foliateIndexer', () async {
      final tracker = ReaderActivityTracker();
      final pdfIndexer = _FakeContentIndexer();
      final foliateIndexer = _FakeContentIndexer();
      await insertPendingBook(_book('pdf-book', format: BookFileFormat.pdf));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: pdfIndexer,
        foliateIndexer: foliateIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(pdfIndexer.wasCalled, isTrue,
          reason: 'PDF 格式書籍應分派給 pdfIndexer');
      expect(foliateIndexer.wasCalled, isFalse,
          reason: 'PDF 格式書籍不應分派給 foliateIndexer');
      await pdfIndexer.finish();
    });

    test('開啟閱讀畫面（ReaderActivityTracker）時，正在處理的書籍於下個章節邊界暫停，記錄游標',
        () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-2'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      // 完成第 0 章。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一章內容'));
      await Future<void>.delayed(Duration.zero);
      // 開始送出第 1 章第一筆，觸發章節邊界檢查（此時尚未呼叫
      // markReaderOpened，應正常繼續處理進入第 1 章）。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二章第一段'));
      await Future<void>.delayed(Duration.zero);

      // 使用者開啟閱讀畫面——排程器應在下一個章節邊界暫停。
      tracker.markReaderOpened();
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 2, locator: 'epubcfi(/6/6)', rawText: '第三章第一段'));
      await Future<void>.delayed(Duration.zero);

      final status = await statusOf('book-2');
      expect(status['status'], 'indexing',
          reason: '尚未處理完全書，應維持 indexing（非 done）');
      expect(status['last_chapter_index'], 1,
          reason: '第 1 章已完整寫入，游標應停在 1（第 2 章的資料被捨棄，未寫入）');

      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-2']);
      expect(indexRows.map((r) => r['chapter_index']).toSet(), {0, 1},
          reason: '第 2 章（chapterIndex=2）尚未完整走完章節邊界，不應寫入');
    });

    test('App 背景化後、回到前台時，從續跑游標繼續處理', () async {
      final tracker = ReaderActivityTracker();
      final firstRunIndexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-3'), lastChapterIndex: 4);

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: firstRunIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(firstRunIndexer.lastResumeFromChapter, 5,
          reason: '既有游標為 4（已完成），應從第 5 章開始續跑');
      await firstRunIndexer.finish();
    });

    test('App 背景化時，不會開始處理新的 pending 書籍', () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-4'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final status = await statusOf('book-4');
      expect(status['status'], 'pending', reason: 'App 背景化時排程器不應開始處理');
    });

    test('【I-3】indexing 狀態書籍優先於 pending 書籍被選中，不因剛暫停而被擠到佇列尾端',
        () async {
      final tracker = ReaderActivityTracker();
      // book-a／book-b 皆為 epub 格式，共用同一個 foliateIndexer 實例
      // （見下方建構子），故只需要一個假索引器，用 lastBook.id 判斷究竟
      // 是哪一本書被選中（見 _FakeContentIndexer.lastBook 註解）。
      final indexerA = _FakeContentIndexer();
      // 書 A：早先已開始處理、中途暫停過（updated_at 較新，模擬剛暫停）。
      await insertPendingBook(_book('book-a'), lastChapterIndex: 1);
      await db.update('content_index_status', {'status': 'indexing', 'updated_at': 9999},
          where: 'book_id = ?', whereArgs: ['book-a']);
      // 書 B：全新匯入、從未處理過（insertPendingBook 預設 updated_at:
      // 1000，比書 A 剛被設定的 9999 舊）。
      await insertPendingBook(_book('book-b'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        // book-a／book-b 皆為 epub 格式（_book() 預設值），共用同一個
        // foliateIndexer 實例——用 lastBook.id 而非 wasCalled 判斷究竟是
        // 哪一本書被選中，見 _FakeContentIndexer.lastBook 註解。
        foliateIndexer: indexerA,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(indexerA.wasCalled, isTrue);
      expect(indexerA.lastBook?.id, 'book-a',
          reason: 'updated_at 較新但 status=indexing 的書 A 應優先於 status=pending 的書 B 被選中');
      await indexerA.finish();
    });

    test('【I-4】requestProcessing() 可在排程器閒置時喚醒處理新插入的 pending 列', () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      // 排程器啟動當下佇列是空的，_runLoop() 應立即結束、回到閒置狀態。
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(indexer.wasCalled, isFalse);

      // 模擬 Issue 2／3 批次插入一筆新的 pending 列後主動呼叫
      // requestProcessing()（App 生命週期與 ReaderActivityTracker 皆未
      // 變動，若沒有這個公開方法，排程器沒有任何訊號會知道有新工作）。
      await insertPendingBook(_book('book-5'));
      scheduler.requestProcessing();
      await Future<void>.delayed(Duration.zero);

      expect(indexer.wasCalled, isTrue);
      await indexer.finish();
    });

    test('【M-2】dispose() 後，正在處理的書於下個章節邊界暫停（不會變成 done），也不會開始下一本書',
        () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-6'));
      await insertPendingBook(_book('book-7'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(indexer.wasCalled, isTrue, reason: 'book-6 應已開始處理');

      // 完成第 0 章。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一段'));
      await Future<void>.delayed(Duration.zero);

      scheduler.dispose();
      // dispose() 後模擬 App 生命週期事件仍可能因既有訂閱殘留而觸發一次
      // （例如 removeObserver 之前已排入佇列的事件），驗證 _disposed 旗標
      // 確實阻擋繼續處理，而不是僅僅移除了 observer——handleAppLifecycleStateChanged()
      // 是測試可直接呼叫的公開方法，不經過真正的 WidgetsBindingObserver。
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      // 送出第 1 章第一筆，觸發章節邊界檢查——此時應偵測到 dispose() 已
      // 發生而暫停，不繼續處理，book-6 應停在「已完成第 0 章」狀態。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二段'));
      await Future<void>.delayed(Duration.zero);

      final status6 = await statusOf('book-6');
      expect(status6['status'], 'indexing',
          reason: 'book-6 應在 dispose() 後的章節邊界暫停，不應變成 done');
      expect(status6['last_chapter_index'], 0);
      final status7 = await statusOf('book-7');
      expect(status7['status'], 'pending',
          reason: 'dispose() 後不應開始處理 book-7');
    });
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/search/content_indexing_scheduler_test.dart`
Expected: FAIL（`package:elinkbook/search/content_indexing_scheduler.dart` 不存在，編譯錯誤）。

- [x] **Step 3：實作 `ContentIndexingScheduler`**

新增 `app/lib/search/content_indexing_scheduler.dart`：

```dart
// app/lib/search/content_indexing_scheduler.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import '../reader/reader_activity_tracker.dart';
import 'cjk_tokenizer.dart';
import 'content_indexer.dart';

/// 背景索引排程器（epic-10-search Issue 1，見 spec.md §3.3）：只在「App
/// 前台（[AppLifecycleState.resumed]）且無任何閱讀畫面開啟」時處理
/// `content_index_status` 的 `pending`/`indexing` 佇列，一次僅處理一本書
/// （ADR 0027 決策 3），依 `books.format` 分派給 [pdfIndexer]／[foliateIndexer]
/// 之一。
///
/// **不感知 `ContentIndexCategory`／「啟用全文檢索」開關**（Issue 3 職責，
/// 見 plan-issue-1.md Global Constraints「規劃階段查證」）——純粹處理這張
/// 表裡已經存在的列，誰插入、何時插入不是本類別的責任。
class ContentIndexingScheduler with WidgetsBindingObserver {
  ContentIndexingScheduler({
    required Database database,
    required ReaderActivityTracker activityTracker,
    required ContentIndexer pdfIndexer,
    required ContentIndexer foliateIndexer,
  })  : _database = database,
        _activityTracker = activityTracker,
        _pdfIndexer = pdfIndexer,
        _foliateIndexer = foliateIndexer {
    _activityTracker.addListener(_handleActivityChanged);
  }

  final Database _database;
  final ReaderActivityTracker _activityTracker;
  final ContentIndexer _pdfIndexer;
  final ContentIndexer _foliateIndexer;

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _isProcessing = false;
  bool _started = false;

  /// 【review-plan-issue-1.md M-2，修法與審查建議不同，理由見下方】
  /// `stop()`／`dispose()` 呼叫後應停止繼續取下一本待處理書籍。審查原始
  /// 建議是把 `_started` 併入 `_canProcess()`，但 `_started` 只有
  /// `start()`（真正註冊 `WidgetsBindingObserver`）才會設為 true——Task 5
  /// 的全部單元測試依 issues.md 要求刻意「不呼叫 start()，直接呼叫
  /// handleAppLifecycleStateChanged() 注入生命週期訊號」，若把 `_started`
  /// 併入 `_canProcess()`，這些測試會全數失敗（`_canProcess()` 恆為
  /// false）。改用獨立旗標 `_disposed`（預設 false，只有 `stop()`／
  /// `dispose()` 才會設為 true），語意上與「是否已註冊 WidgetsBindingObserver」
  /// 徹底脫鉤，測試不受影響、`stop()`/`dispose()` 之後也能正確在下一個
  /// 章節邊界停止繼續處理新書籍。
  bool _disposed = false;

  /// 供 `main.dart` 呼叫：註冊為 [WidgetsBindingObserver]，並嘗試立即開始
  /// 處理（若當下條件已符合）。
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final currentState = WidgetsBinding.instance.lifecycleState;
    if (currentState != null) _lifecycleState = currentState;
    _maybeStartProcessing();
  }

  void stop() {
    _disposed = true;
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  void dispose() {
    stop();
    _activityTracker.removeListener(_handleActivityChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      handleAppLifecycleStateChanged(state);

  /// 【review-plan-issue-1.md I-4】供新書匯入、下載完成（Issue 2）或設定
  /// 開啟全文檢索開關（Issue 3）時主動呼叫——這兩個工單會在
  /// `content_index_status` 批次插入新的 `pending` 列，但若排程器當下已
  /// 處於閒置狀態（先前排入的書籍皆已處理完畢，`_runLoop()` 已結束），
  /// App 生命週期與 `ReaderActivityTracker` 狀態皆未變動，排程器沒有任何
  /// 訊號會知道有新工作，會卡死到使用者某天切換 App 前後台或開關一次
  /// 閱讀畫面才會被動醒來。`issues.md` Issue 3 明訂「依賴：Issue 1（需要
  /// 排程器 API 供開/關連動）」，本方法即為該 API。
  void requestProcessing() => _maybeStartProcessing();

  /// 測試可直接呼叫本方法注入生命週期訊號，不需要真正的
  /// [WidgetsBindingObserver] 註冊（見 issues.md Issue 1 單元測試要求）。
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    _lifecycleState = state;
    _maybeStartProcessing();
  }

  void _handleActivityChanged() => _maybeStartProcessing();

  bool _canProcess() =>
      !_disposed &&
      _lifecycleState == AppLifecycleState.resumed &&
      !_activityTracker.isReaderOpen;

  void _maybeStartProcessing() {
    if (_isProcessing || !_canProcess()) return;
    _isProcessing = true;
    unawaited(_runLoop());
  }

  Future<void> _runLoop() async {
    try {
      while (_canProcess()) {
        final next = await _fetchNextPendingBook();
        if (next == null) return;
        await _processOneBook(next.$1, next.$2);
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// 回傳 `(book, resumeFromChapter)`；查無待處理書籍時回傳 null。JOIN
  /// `books` 直接取得分派所需的 `format`／`filePath`，比照 spec.md §3.3
  /// 效能查詢一節已示範的寫法，不透過 `LibraryRepository.listBooks()`
  /// 撈整個書庫。
  ///
  /// 【review-plan-issue-1.md I-3】排序優先權：`status = 'indexing'`（已
  /// 開始、中途暫停過的書）排在 `status = 'pending'`（尚未開始）之前，
  /// 其次才依 `updated_at ASC`。原始寫法單純 `ORDER BY updated_at ASC`
  /// 會造成排程飢餓——`flushPendingChapter()` 每次暫停都會把該書
  /// `updated_at` 更新為當下時間（全表最新），若同時存在其他 `pending`
  /// 書籍（`updated_at` 是更早的匯入時間），下次查詢反而會優先選到那些
  /// 全新書籍、把做到一半的書擠到佇列尾端；使用者若經常短暫開關閱讀
  /// 畫面，最終可能所有書籍都卡在 `indexing` 半成品狀態、沒有一本真正
  /// 完成。改為優先做完手頭正在進行的書，才輪到未開始的書（其中同為
  /// `pending` 時仍依最早排入順序）。
  Future<(Book, int?)?> _fetchNextPendingBook() async {
    final rows = await _database.rawQuery('''
      SELECT cis.last_chapter_index AS last_chapter_index, b.*
      FROM content_index_status cis
      JOIN books b ON b.id = cis.book_id
      WHERE cis.status IN ('pending', 'indexing')
      ORDER BY CASE WHEN cis.status = 'indexing' THEN 0 ELSE 1 END, cis.updated_at ASC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final row = rows.first;
    final lastChapterIndex = row['last_chapter_index'] as int?;
    return (Book.fromMap(row), lastChapterIndex);
  }

  Future<void> _processOneBook(Book book, int? lastChapterIndex) async {
    await _database.update(
      'content_index_status',
      {'status': 'indexing', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'book_id = ?',
      whereArgs: [book.id],
    );

    final indexer =
        book.format == BookFileFormat.pdf ? _pdfIndexer : _foliateIndexer;
    final resumeFromChapter =
        lastChapterIndex == null ? null : lastChapterIndex + 1;

    var pending = <Map<String, Object?>>[];
    int? pendingChapterIndex;
    var paused = false;

    Future<void> flushPendingChapter(int chapterIndex) async {
      if (pending.isNotEmpty) {
        final batch = _database.batch();
        for (final row in pending) {
          batch.insert('book_content_index', row);
        }
        await batch.commit(noResult: true);
        pending = [];
      }
      await _database.update(
        'content_index_status',
        {
          'last_chapter_index': chapterIndex,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [book.id],
      );
    }

    try {
      await for (final segment
          in indexer.indexBook(book, resumeFromChapter: resumeFromChapter)) {
        if (pendingChapterIndex != null &&
            segment.chapterIndex != pendingChapterIndex) {
          await flushPendingChapter(pendingChapterIndex!);
          if (!_canProcess()) {
            paused = true;
            break;
          }
        }
        pendingChapterIndex = segment.chapterIndex;
        pending.add({
          'id': const Uuid().v4(),
          'book_id': book.id,
          'chapter_index': segment.chapterIndex,
          'locator': segment.locator,
          'raw_text': segment.rawText,
          'token_text': tokenizeForIndex(segment.rawText),
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      if (!paused) {
        if (pendingChapterIndex != null) {
          await flushPendingChapter(pendingChapterIndex!);
        }
        await _database.update(
          'content_index_status',
          {'status': 'done', 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'book_id = ?',
          whereArgs: [book.id],
        );
      }
    } catch (e) {
      await _database.update(
        'content_index_status',
        {
          'status': 'error',
          'error_message': e.toString(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [book.id],
      );
    }
  }
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/search/content_indexing_scheduler_test.dart`
Expected: PASS（8 個 test）

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/content_indexing_scheduler.dart app/test/search/content_indexing_scheduler_test.dart
git commit -m "feat(search): 新增 ContentIndexingScheduler（背景索引排程器）"
```

---

### Task 6：`main.dart`／`library_screen.dart` 整合貫穿

**Files：**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/library_screen_dependencies.dart:32-54`（`LibraryReaderFeatureRepositories`）
- Modify: `app/lib/screens/library_screen.dart:412-456`（`_openBook()`）

**Interfaces：**
- Consumes：Task 3 的 `FoliateContentIndexer`、Task 1 的 `PdfContentIndexer`、Task 4 的 `ReaderActivityTracker`、Task 5 的 `ContentIndexingScheduler`。
- Produces：App 正式啟動時背景索引引擎已就緒運作中（尚無任何 UI 讓使用者觸發 `pending` 列——那是 Issue 2／Issue 3 的範圍，本工單只交付「引擎能跑」）。

- [x] **Step 1：`LibraryReaderFeatureRepositories` 新增欄位**

在 `app/lib/screens/library_screen_dependencies.dart` 頂部 import 區塊新增：

```dart
import '../reader/reader_activity_tracker.dart';
```

`class LibraryReaderFeatureRepositories` 欄位宣告（約第 33-41 行）新增：

```dart
  final ReaderActivityTracker? readerActivityTracker;
```

建構子具名參數列（約第 43-53 行）新增：

```dart
    this.readerActivityTracker,
```

- [x] **Step 2：`library_screen.dart` 貫穿傳入**

在 `app/lib/screens/library_screen.dart` 的 `_openBook()`（約第 416-443 行）`ReaderScreen(...)` 呼叫的具名參數列新增：

```dart
              readerActivityTracker:
                  widget.readerFeatureRepositories.readerActivityTracker,
```

（放在既有任一參數之後皆可，例如緊接在 `isEinkMode: widget.themeDependencies.isEinkMode,` 之後。）

- [x] **Step 3：`main.dart` 建構單例、啟動排程器，並貫穿 `ElinkBookApp`**

`readerActivityTracker` 需要貫穿三處（比照 `bookmarksRepository` 等既有欄位已貫穿的相同三處寫法）：`main()` 建構 → `ElinkBookApp` 建構子接收 → `_ElinkBookAppState` 組裝 `LibraryReaderFeatureRepositories` 時傳入。

在 `app/lib/main.dart` 頂部 import 區塊新增：

```dart
import 'reader/reader_activity_tracker.dart';
import 'search/content_indexing_scheduler.dart';
import 'search/foliate_content_indexer.dart';
import 'search/pdf_content_indexer.dart';
```

在既有 `final layoutPresetRepository = LayoutPresetRepository(repository.database);`（約第 97 行）之後新增：

```dart
  // epic-10-search Issue 1：背景全文檢索索引引擎。本工單只負責讓引擎
  // 能運作，「啟用全文檢索」開關與批次回填既有書庫是 Issue 3 的範圍——
  // 目前 content_index_status 裡不會有任何 pending 列，排程器啟動後
  // 純粹閒置等待，直到 Issue 3 落地才會有實際工作可做。
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
```

在 `runApp(ElinkBookApp(...))` 呼叫（`app/lib/main.dart:204-237`）的具名參數列新增一行（例如緊接在 `prefsManager: prefsManager,` 之後）：

```dart
      readerActivityTracker: readerActivityTracker,
```

在 `class ElinkBookApp` 欄位宣告區（`app/lib/main.dart:246`，`final ReaderPrefsManager prefsManager;` 之後）新增：

```dart
  final ReaderActivityTracker? readerActivityTracker;
```

在 `ElinkBookApp` 建構子具名參數列（`app/lib/main.dart:285`，`required this.prefsManager,` 之後）新增：

```dart
    this.readerActivityTracker,
```

在 `_ElinkBookAppState` 組裝 `LibraryReaderFeatureRepositories(...)` 處（`app/lib/main.dart:375-385`）新增一行：

```dart
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: widget.bookmarksRepository,
          highlightsRepository: widget.highlightsRepository,
          notesRepository: widget.notesRepository,
          customFontsRepository: widget.customFontsRepository,
          layoutPresetRepository: widget.layoutPresetRepository,
          bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
          ttsProvider: widget.ttsProvider,
          ttsAudioHandler: widget.ttsAudioHandler,
          ttsAudioFocusSource: widget.ttsAudioFocusSource,
          readerActivityTracker: widget.readerActivityTracker,
        ),
```

（即在既有 `ttsAudioFocusSource: widget.ttsAudioFocusSource,` 之後新增 `readerActivityTracker: widget.readerActivityTracker,` 一行，其餘既有欄位原樣不動。）

- [x] **Step 4：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5：確認既有相關測試零回歸**

Run: `flutter test test/screens/library_screen_test.dart test/screens/reader_screen_test.dart`
Expected: 全數通過（本 Task 只新增可選參數傳遞，不改變既有行為）。

- [x] **Step 6：Commit**

```bash
git add app/lib/main.dart app/lib/screens/library_screen_dependencies.dart app/lib/screens/library_screen.dart
git commit -m "feat(search): main.dart 建構並啟動 ContentIndexingScheduler"
```

---

### Task 7：端到端驗證（真機/模擬器，本工單「demoable」驗收標準）

**Files：**
- Create: `app/integration_test/content_indexing_end_to_end_test.dart`
- Modify: `app/pubspec.yaml`（`assets:` 區塊新增 `test/fixtures/sample_multi_page.pdf`）

**Interfaces：**
- Consumes：Task 1（`PdfContentIndexer`）、Task 3（`FoliateContentIndexer`）、Task 5（`ContentIndexingScheduler`）、Task 4（`ReaderActivityTracker`）。
- Produces：無新程式碼介面，純驗證性測試——證明「一本 PDF 與一本 EPUB fixture 各自從 `content_index_status='pending'` 到背景排程完成後轉為 `'done'`，且 `book_content_fts` 能查到已知內容並取回正確 `locator`」（`issues.md` Issue 1 驗收標準原文）。

- [x] **Step 0：`pubspec.yaml` 補上缺少的 asset 宣告（`review-plan-issue-1.md` M-1）**

Step 1 的測試透過 `rootBundle.load()`（`_stageAssetAsFile()`）在真機/模擬器上載入 `test/fixtures/sample_multi_page.pdf`——與 Task 1 的純 Dart 單元測試不同（後者直接讀本機檔案系統相對路徑，不經 `rootBundle`），真機/模擬器環境的 `rootBundle.load()` 只能載入 `pubspec.yaml` `assets:` 清單裡已宣告的檔案。查證 `app/pubspec.yaml:157-169` 已宣告 `sample.pdf`／`sample_dual_page.pdf`／`sample_pdf_toc.pdf`／`sample_multi_chapter.epub`，但**獨缺 `sample_multi_page.pdf`**（Task 3 使用的 `sample_multi_chapter.epub` 已宣告，不受影響）。

在 `app/pubspec.yaml` 找到：

```yaml
    - test/fixtures/sample_dual_page.pdf
    - test/fixtures/sample_pdf_toc.pdf
```

之後新增一行：

```yaml
    - test/fixtures/sample_multi_page.pdf
```

- [x] **Step 1：寫端到端測試**

新增 `app/integration_test/content_indexing_end_to_end_test.dart`：

```dart
// app/integration_test/content_indexing_end_to_end_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/search/content_indexing_scheduler.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';
import 'package:elinkbook/search/pdf_content_indexer.dart';
import 'package:pdfrx/pdfrx.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _waitUntilStatus(
  Database db,
  String bookId,
  String expectedStatus, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    final status = rows.isNotEmpty ? rows.single['status'] as String? : null;
    if (status == expectedStatus) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：$bookId 狀態仍是 $status，預期 $expectedStatus');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'PDF 與 EPUB fixture 各自從 pending 背景索引完成轉為 done，且 book_content_fts 可查到已知內容',
      (tester) async {
    await pdfrxFlutterInitialize();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final db = repository.database;

    final pdfPath =
        await _stageAssetAsFile('test/fixtures/sample_multi_page.pdf', 'e2e.pdf');
    final epubPath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'e2e.epub');
    addTearDown(() async {
      for (final path in [pdfPath, epubPath]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    });

    final pdfBook = Book(
      id: 'e2e-pdf-book',
      title: '端到端測試 PDF',
      format: BookFileFormat.pdf,
      filePath: pdfPath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );
    final epubBook = Book(
      id: 'e2e-epub-book',
      title: '端到端測試 EPUB',
      format: BookFileFormat.epub,
      filePath: epubPath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    await repository.insertBook(pdfBook);
    await repository.insertBook(epubBook);
    for (final bookId in [pdfBook.id, epubBook.id]) {
      await db.insert('content_index_status', {
        'book_id': bookId,
        'status': 'pending',
        'last_chapter_index': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    final tracker = ReaderActivityTracker();
    final scheduler = ContentIndexingScheduler(
      database: db,
      activityTracker: tracker,
      pdfIndexer: const PdfContentIndexer(),
      foliateIndexer: const FoliateContentIndexer(),
    );
    addTearDown(() => scheduler.dispose());
    scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await _waitUntilStatus(db, pdfBook.id, 'done');
    await _waitUntilStatus(db, epubBook.id, 'done');

    // PDF：已知內容含 "Page" 字樣（見 pdf_reader_view_search_test.dart）。
    final pdfMatches = await db.rawQuery(
      'SELECT bci.locator, bci.raw_text FROM book_content_fts '
      'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
      "WHERE bci.book_id = ? AND book_content_fts MATCH 'Page'",
      [pdfBook.id],
    );
    expect(pdfMatches, isNotEmpty);
    final pdfLocator = pdfMatches.first['locator'] as String;
    expect(pdfLocator, contains('"page"'));

    // EPUB：已知內容含中文「第一章」（tokenizeForQuery 需求逐字空白分隔，
    // 這裡直接用已知已經過 tokenizeForIndex() 轉換的形式查詢，等效於
    // SearchRepository.searchContent() 未來會做的轉換，Issue 1 尚未交付
    // 該 repository，故此處直接組出 MATCH 用字串）。
    final epubMatches = await db.rawQuery(
      'SELECT bci.locator, bci.raw_text FROM book_content_fts '
      'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
      "WHERE bci.book_id = ? AND book_content_fts MATCH '\"第 一 章\"'",
      [epubBook.id],
    );
    expect(epubMatches, isNotEmpty);
    final epubLocator = epubMatches.first['locator'] as String;
    expect(epubLocator, startsWith('epubcfi('));
  });
}
```

- [x] **Step 2：執行測試**

Run: `flutter test integration_test/content_indexing_end_to_end_test.dart -d <device-id>`
Expected: PASS（需要真實 Android 裝置/模擬器）。

- [x] **Step 3：執行整個 `app/test/` 套件，確認沒有破壞既有測試（計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過。

- [x] **Step 4：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5：Commit**

```bash
git add app/integration_test/content_indexing_end_to_end_test.dart app/pubspec.yaml
git commit -m "test(search): 新增背景索引端到端驗證（PDF+EPUB pending→done）"
```

---

## Self-Review Checklist（供執行者/審查者核對，非新增步驟）

- **Spec 涵蓋**：`spec.md` §3.1（Task 1）、§3.2 Foliate（Task 2/3）、§3.2 PDF（Task 1）、§3.3（Task 4/5）皆有對應任務；`issues.md` Issue 1 列出的四項驗收要求（`PdfContentIndexer`／`FoliateContentIndexer`／`ContentIndexingScheduler` 三種狀態轉換／端到端）分別對應 Task 1、Task 3、Task 5、Task 7。
- **規劃階段查證留痕**：`spec.md` §3.3「排程器依賴 `FullTextSearchSettingsRepository`」與同節後段「排程器不需感知 category」的矛盾，已在 Global Constraints 明確記錄查證過程與最終決定（不依賴該型別），避免執行者依表面文字誤植依賴。
- **無佔位符**：七個 Task 的每個 Step 都是可直接執行的具體程式碼/指令。
- **型別/命名一致性**：`ContentIndexer`／`IndexedSegment`（Task 1 定義）被 Task 3／Task 5 直接 import 使用，簽章一致；`window.getSectionCount()`／`window.buildSegmentsForSection()`（Task 2 定義的 handler name `onSectionCountReady`／`onSegmentsForSectionReady`）與 Task 3 `FoliateContentIndexer` 註冊的 handler name 逐字相符；`ReaderActivityTracker`（Task 4 定義）在 Task 5／Task 6／Task 7 使用方式一致；`ContentIndexingScheduler` 建構參數名稱（`database`／`activityTracker`／`pdfIndexer`／`foliateIndexer`）在 Task 5 定義、Task 6／Task 7 呼叫端逐字相符；`readContentUriAll`（Task 1 定義的頂層函式變數）與 `esCompatPolyfillJs`／`globalErrorCaptureJs`（Task 3 Step 0 搬移到 `foliate_native_bridge.dart` 的公開常數）皆在定義處與唯一使用處名稱逐字相符。
- **審查修訂完整性**：`review-plan-issue-1.md` 7 項發現（C-1／I-1～I-4／M-1～M-2）逐項核對已全數落實於對應 Task 的程式碼片段中（見 Global Constraints 最後一條的逐項對照），且 Task 1／Task 5 的測試數量已同步更新（5 個／8 個），Task 3／Task 7 的 Files 清單已同步補上新增的 Modify 項目。
