# Epic 10 — 全文檢索：Architecting Spec

本文件是 `epic-10-search` 的唯一技術事實來源，落地 `design.md`（Discovery）與 [ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md)（tokenization／Headless Foliate 擷取）的產品/架構決策為具體介面。Scrum Master 拆 `issues.md` 時以本文件的分節為切割依據。

## 0. 依賴與既有慣例

- 資料庫：`sqflite`（Android 系統內建 SQLite），現行 `sqlite_library_repository.dart` schema `version: 23`，本 Epic 新增遷移至 `24`。
- 級聯清除：比照 `book_reader_prefs`／`bookmarks`／`highlights`／`notes` 既有慣例（`REFERENCES books(id) ON DELETE CASCADE`＋`PRAGMA foreign_keys = ON` 已開啟），FK 本身足以清掉 `book_content_index`／`content_index_status` 的資料列；但 `book_content_fts` 是 external-content 虛擬表，同步全靠 trigger，而 SQLite 級聯刪除預設不觸發子表 trigger（需 `PRAGMA recursive_triggers = ON`，本專案 `onConfigure` 目前未開，見第 1 節修正）。
- Headless WebView：`flutter_inappwebview`（`^6.1.5`，既有依賴）的 `HeadlessInAppWebView`，載入與 `FoliateReaderView` 相同的 `assets/foliate/index.html`（ADR 0018 `WebViewAssetLoader` 串流機制）——**這條路徑要求先把書籍複製到每實例專屬的快取子目錄、並設定 `webViewAssetLoader` 指向該目錄**（比照 `foliate_reader_view.dart` 既有 `_cacheBook()`/`cacheBookForServing()`/`InternalStoragePathHandler` 三件套，見第 3.2 節），並非單純帶一個 URL query 就能讀到書籍內容。
- PDF 文字擷取：直接使用 `pdfrx` 的 `PdfDocument.openFile()` ＋ `PdfPage.loadStructuredText()`（與 `PdfSearchPanel`／`pdf_reader_view.dart` 既有邏輯同源），純 Dart/FFI，不需建構任何 Widget。
- PDF 座標語意：沿用既有 `PercentRect`（`percent_rect.dart`，0-1 相對頁面尺寸、左上角原點）與 `pdfRectToPercentRect()` 轉換函式，與 `PdfSearchMatch`／`PdfAnnotationDecoration.rect` 同一套座標慣例。

## 1. 資料庫 Schema（DB version 23 → 24）

```sql
-- 每本書的索引進度狀態（含背景排程的續跑游標）
CREATE TABLE content_index_status (
  book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',
    -- pending | indexing | done | unsupported | error
  last_chapter_index INTEGER,
    -- 續跑游標：Foliate 為 spine index，PDF 為 page index
  updated_at INTEGER NOT NULL,
  error_message TEXT
);

-- 內容索引明細（一列 = 一個可跳轉的精確定位片段）
CREATE TABLE book_content_index (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  locator TEXT NOT NULL,
    -- Foliate：CFI 字串；PDF：JSON `{"page":int,"rect":PercentRect}`
  raw_text TEXT NOT NULL,      -- 原始句子文字，UI 顯示片段用，不分詞
  token_text TEXT NOT NULL,    -- 逐字層級 token 化後的可搜尋文字（見第 2 節）
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_book_content_index_book_id ON book_content_index(book_id);

-- FTS5 外部內容虛擬表：只索引 token_text，實際文字仍以 book_content_index 為準
CREATE VIRTUAL TABLE book_content_fts USING fts5(
  token_text,
  content='book_content_index',
  content_rowid='rowid'
);

-- 同步 triggers：book_content_index 的異動即時反映到 book_content_fts。
-- 【修正】SQLite 官方規範：外鍵 ON DELETE CASCADE 動作預設「不會」觸發
-- 子表的 AFTER DELETE trigger，只有 PRAGMA recursive_triggers = ON 時才
-- 會觸發（見 https://www.sqlite.org/foreignkeys.html#fk_actions）。本專案
-- `onConfigure`（sqlite_library_repository.dart:44）目前只開了
-- `PRAGMA foreign_keys = ON`，未開 `recursive_triggers`——四張既有表
-- （book_reader_prefs/bookmarks/highlights/notes）從未依賴級聯觸發任何
-- trigger，所以這個落差過去不曾暴露；本 Epic 是本專案第一個「級聯刪除
-- 必須連動觸發 trigger」的情境（FTS5 external-content 表本身沒有外鍵，
-- 完全靠 trigger 保持同步），因此 `onConfigure` 必須新增
-- `PRAGMA recursive_triggers = ON;`（與既有 `PRAGMA foreign_keys = ON`
-- 同一處設定），否則書籍刪除時 book_content_index 的列會被級聯刪除，但
-- book_content_fts 不會同步、殘留指向不存在 rowid 的孤兒索引。
CREATE TRIGGER book_content_index_ai AFTER INSERT ON book_content_index BEGIN
  INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
END;
CREATE TRIGGER book_content_index_ad AFTER DELETE ON book_content_index BEGIN
  INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
END;
CREATE TRIGGER book_content_index_au AFTER UPDATE ON book_content_index BEGIN
  INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
  INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
END;
```

- `content_index_status` 沒有 `book_content_index`/`book_content_fts` 的外部內容關聯，是獨立的進度追蹤表；一本書刪除時同樣靠 `ON DELETE CASCADE` 自動清除，不需要額外程式碼。
- 「重建索引」＝對指定 `book_id` 執行 `DELETE FROM book_content_index WHERE book_id = ?`（`recursive_triggers = ON` 前提下 trigger 自動同步 FTS）＋ `UPDATE content_index_status SET status='pending', last_chapter_index=NULL WHERE book_id = ?`，交回排程佇列即可，不需要特殊清除邏輯。
- CBZ／偵測到 DRM 的 KF8：`content_index_status.status` 直接寫入 `'unsupported'`，排程略過，不進入 `book_content_index`。

## 2. 中文 Token 化規則

新檔案 `app/lib/search/cjk_tokenizer.dart`（純 Dart，無外部依賴）：

```dart
/// 供寫入索引使用：CJK 表意文字逐字以空白分隔，其餘字元（ASCII 字母/
/// 數字、既有標點）維持原樣不拆，讓 FTS5 標準 unicode61 tokenizer 把每個
/// CJK 字元視為獨立 token，同時仍保留英文單字的既有詞級比對能力。
String tokenizeForIndex(String text);

/// 供查詢使用：對使用者輸入做相同的字元切分，再包成 FTS5 phrase query
/// （雙引號包住、內部雙引號跳脫為 `""`），要求 token 依序相鄰，達成等效
/// 子字串比對。空字串輸入回傳空字串，呼叫端須自行判斷是否要送出查詢。
String tokenizeForQuery(String query);
```

- CJK 判定範圍：Unicode Han 表意文字（`U+4E00`–`U+9FFF` 基本區，[ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md) 範圍內即可，暫不含擴充區 B 以上的罕用字，命中率影響可忽略，之後有需要再擴充不影響既有索引資料）。
- 純函式、無 I/O，TDD 階段可直接以字串輸入/輸出斷言覆蓋，不需要 mock 資料庫或 WebView。

## 3. 索引建置管線

### 3.1 抽象介面

新目錄 `app/lib/search/`：

```dart
/// 單一格式的內容擷取器，把一本書轉換成一連串可索引的精確定位片段。
abstract class ContentIndexer {
  /// [resumeFromChapter] 非 null 時從該章節（含）開始擷取，用於背景排程
  /// 暫停後的續跑（見 3.3 節排程器）。yield 順序即寫入順序，呼叫端逐筆
  /// 寫入 `book_content_index` 並可隨時中斷（例如排程被要求暫停）。
  Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter});
}

class IndexedSegment {
  final int chapterIndex;
  final String locator;   // CFI 字串 或 JSON `{"page":int,"rect":PercentRect}`
  final String rawText;
  const IndexedSegment({
    required this.chapterIndex,
    required this.locator,
    required this.rawText,
  });
}
```

### 3.2 兩個實作

- **`FoliateContentIndexer`**（新檔案 `app/lib/search/foliate_content_indexer.dart`）：
  1. **快取書籍**（比照 `foliate_reader_view.dart` 既有 `_cacheBook()` 流程，直接重用 `cacheBookForServing(book.filePath, instanceId)`——這支既有函式已封裝原生端有界記憶體分塊複製，回傳快取後的檔案路徑）；本實例的 `instanceId` 另外產生（例如 `'index-${book.id}'`），與正常閱讀開書的 `FoliateReaderView` 實例互不共用快取子目錄。
  2. 建立 `HeadlessInAppWebView`，`initialSettings.webViewAssetLoader` 設定 `InternalStoragePathHandler(path: '/book/', directory: <cacheBookForServing 回傳路徑的所在目錄>)`（與 `foliate_reader_view.dart:893-897` 現行設定同一套機制），URL 比照 `_buildIndexUri()` 現有參數組（`bookFileName`／`prefs`／`fontFaceCss`），新增 `mode=index` 旗標。
  3. `main.js` 新增：
     - `mode=index` 時跳過既有的 TTS/劃線/書籤/音量鍵橋接初始化（那些初始化目前都掛在一般開書流程，索引模式不需要）。
     - `window.getSectionCount()`：書籍載入完成（既有 `openBook`/`onReady` 流程之後）回傳 `view.book.sections.length`，供 Dart 端知道要呼叫幾次、判斷何時結束——現行 JS↔Dart 橋接尚未暴露這個值（`buildTtsSegments()` 只在使用者朗讀到某一章節時針對該章節呼叫，從未需要知道全書總章節數）。
     - `window.buildSegmentsForSection(sectionIndex)`：從 `buildTtsSegments()`（`main.js`，`epic-34-tts-readalong`）抽出「句子切分＋`view.getCFI(index, range)`」的共用核心邏輯，改成不依賴「目前朗讀章節」的獨立版本，回傳格式與既有 `buildTtsSegments()` 相同的 `[{segmentId, cfi, text}]`。
  4. Dart 端書籍載入完成後先呼叫 `getSectionCount()`，再依 `0 <= sectionIndex < totalSections` 依序呼叫 `buildSegmentsForSection()`，每章節取得結果後立即透過既有 JS↔Dart 橋接（比照 `foliate_bridge_codec.dart` 現有模式）傳回，逐章節 `yield`。
  5. 一本書處理完畢、被排程要求暫停、或發生例外時，**無條件**執行：`headlessWebView.dispose()` ＋ `Directory(cacheDir).deleteSync(recursive: true)`（比照 `foliate_reader_view.dart:862-869` 現行 `dispose()` 的快取清理邏輯，避免遺漏導致快取子目錄累積佔用磁碟空間——連續索引上千本書若漏刪，會是數 GB 等級的洩漏）；下一本書重新建立全新實例與快取子目錄（ADR 0027 決策 3，不做記憶體閾值偵測）。
- **`PdfContentIndexer`**（新檔案 `app/lib/search/pdf_content_indexer.dart`）：直接 `PdfDocument.openFile(book.filePath)`，逐頁呼叫 `page.loadStructuredText()`（沿用 `pdf_reader_view.dart` 既有擷取模式），每頁的文字範圍轉換為 `IndexedSegment`（`locator` 為 `jsonEncode({'page': pageIndex, 'rect': percentRect.toJson()})`，`chapterIndex` 直接等於 `pageIndex`）。不需要 Isolate（`pdfrx` 底層 `loadStructuredText()` 已透過 `BackgroundWorker` 背景執行，比照既有「縮圖不需額外 Isolate」的既有結論）。

### 3.3 排程器

新類別 `ContentIndexingScheduler`（`app/lib/search/content_indexing_scheduler.dart`）：

- 依賴：`FullTextSearchSettingsRepository`（第 4 節）、`ContentIndexer` 兩個實作、`LibraryRepository`（查詢 pending 書籍）、一個新的 `ReaderActivityTracker`（見下）。
- **`ReaderActivityTracker`**（新檔案 `app/lib/reader/reader_activity_tracker.dart`，簡單 `ChangeNotifier`，全域單例經既有依賴注入慣例傳入）：`ReaderScreen.initState()`/`dispose()` 呼叫 `markReaderOpened()`/`markReaderClosed()`。排程器監聽這個 tracker，加上既有 `WidgetsBindingObserver`（比照 `main.dart`/`reader_screen.dart` 既有 `AppLifecycleState.paused`/`resumed` 慣例）監聽 App 前後台狀態；只有「App 為 `resumed` 且 `ReaderActivityTracker` 顯示沒有任何閱讀畫面開啟」時才處理佇列，其餘情況（`paused`，或有閱讀畫面開啟）立即暫停目前正在處理的書籍。
- 暫停時：`FoliateContentIndexer` 目前的 `HeadlessInAppWebView` 直接 dispose（不保留半成品章節的暫存狀態，該章節下次重新擷取即可，避免額外設計章節內部續傳）；`PdfContentIndexer` 因逐頁同步處理、中斷點自然落在頁與頁之間，無額外清理。兩者皆把已完成的最後一個 `chapterIndex` 寫入 `content_index_status.last_chapter_index`，`status` 維持 `'indexing'`。
- 恢復時：`SELECT book_id, last_chapter_index FROM content_index_status WHERE status IN ('pending','indexing') ORDER BY updated_at ASC`，取第一筆繼續（`resumeFromChapter: last_chapter_index == null ? null : last_chapter_index + 1`）。
- 全庫搜尋畫面顯示進度：**依 `ContentIndexCategory` 各自查一次**（`WHERE b.format = 'pdf'` 或 `WHERE b.format != 'pdf'`），得到「PDF：已索引/總可索引本數」與「其他格式：已索引/總可索引本數」兩組獨立數字。**聚合條件用 `COUNT(CASE WHEN ... THEN 1 END)`，不用 `COUNT(*) FILTER (WHERE ...)`**——`FILTER` 子句是 SQLite 3.30.0（2019-10-04）才加入的語法，Android 11（NFR-6 最低支援版本）系統 SQLite 是 3.28.0，用 `FILTER` 會直接拋 `near "FILTER": syntax error`（與第 1 節排除 `trigram` tokenizer 是同一種「系統 SQLite 版本落後」風險，這裡沒有一併套用是本次修訂前的疏漏）：
  ```sql
  SELECT
    COUNT(CASE WHEN status = 'done' THEN 1 END) AS done_count,
    COUNT(CASE WHEN status != 'unsupported' THEN 1 END) AS total_count
  FROM content_index_status cis
  JOIN books b ON b.id = cis.book_id
  WHERE b.format = 'pdf' -- 或 b.format != 'pdf'，依查詢的 category 決定
  ```

## 4. 「啟用全文檢索」設定模型

新介面 `FullTextSearchSettingsRepository`（`app/lib/search/full_text_search_settings_repository.dart`），`SharedPreferences` 實作，比照專案既有「單一全域布林值」慣例（不塞進 `GlobalReaderPrefs`——那是「閱讀體驗」偏好設定的聚合物件，本開關語意上屬於圖書庫/搜尋子系統，且開啟/關閉需要連動觸發資料庫層的排程與清除，混進 `GlobalReaderPrefs` 會讓那個類別多一種完全不同的副作用型別，見 `design.md`「明確排除於本 Epic 之外」）。**依 `design.md` 決策拆為兩個獨立布林值**（PDF／Foliate 各自的索引成本與效果特性不同——PDF 走純 Dart/FFI 資源較輕但可能因掃描件缺乏文字層而索引無效，Foliate 走 Headless WebView 資源較重但幾乎必有文字層，兩者關切點互補，見 `design.md` 決策 3 的完整理由）：

```dart
enum ContentIndexCategory { pdf, foliate }

abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
}
```

- 兩個 UI 入口（全庫搜尋畫面 AppBar 常駐設定選單、系統設定「閱讀」分區新增項）皆呈現**兩個獨立開關**（PDF／其他格式），共用同一個 repository 實例，經既有依賴注入模式（比照 `library_screen_dependencies.dart`）往下傳遞，不重複實作。
- `setEnabled(category, true)` 前置 UI 流程：兩個入口點擊任一開關**從關閉切成開啟時**，一律先彈出確認對話框（**每次**「開啟」動作都問，不是「終身只問一次」——因為「關閉時立即清除索引」已經是既定決策，使用者關掉又重開會重新產生一次背景索引成本，每次開啟都提示才正確；因此**不需要**額外的「是否已確認過」持久化旗標，`FullTextSearchSettingsRepository` 只需要儲存兩個分類各自的 `enabled` 布林值本身，例如 `full_text_search_enabled_pdf`／`full_text_search_enabled_foliate` 這兩個 key，不必再多存「已確認」狀態）（比照 `DESIGN.md` §9.1 一般對話框排版慣例——手機寬度 85%／平板上限 400dp、主動作靠右、E-Ink 模式下 Scrim 即時切換不淡入淡出；**不套用** §9.2「破壞性操作」的 error 色按鈕慣例，因為啟用全文檢索不會刪除/遺失任何資料，語意上是效能/電量提示而非破壞性操作警示）。**兩個分類共用同一個 Dialog widget，依 `category` 帶入不同文案**：`ContentIndexCategory.foliate` 顯示「將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？」；`ContentIndexCategory.pdf` 額外加一句「部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況」。使用者按「確認開啟」才呼叫 `setEnabled(category, true)`，按「取消」該開關維持/彈回關閉狀態。`EBDialogShell` 在目前程式碼庫尚未實際落地為共用元件（`DESIGN.md` §9 是規劃中的規範，非既有可 import 的類別）——實作時若該共用元件屆時已由其他 Epic 落地就直接沿用，尚未落地則用一般 `AlertDialog` 手動符合上述排版/E-Ink 規則即可，不阻塞本 Epic 進度。
- `setEnabled(category, true)`：使用者確認後寫入偏好值，把 `content_index_status` 中尚無資料列、且 `books.format` 屬於該 `category`（`pdf` → `format == 'pdf'`；`foliate` → 其餘所有格式）的既有書籍批次插入 `status='pending'`（含既有書庫舊書回填），排程器開始運作。**排程器本身不需要感知 `category`**——它只單純處理 `content_index_status` 裡的 `pending`/`indexing` 佇列，依 `books.format` 分派給 `PdfContentIndexer`/`FoliateContentIndexer`（見 §3.1），格式篩選的責任完全落在「插入 pending 列」這一步，維持排程器邏輯單純。
- `setEnabled(category, false)`：立即刪除**該 `category` 對應格式書籍**的索引資料（`DELETE FROM book_content_index WHERE book_id IN (SELECT id FROM books WHERE format ...)`，trigger 同步清空對應 FTS 列；`content_index_status` 比照刪除），排程器對該分類的佇列停止並捨棄目前進度；**不影響另一個 `category` 已建立的索引**（比照 `design.md`「關閉任一開關時只清除該格式」決定）。

## 5. 全庫搜尋畫面

新畫面 `app/lib/screens/library_search_screen.dart`。

```dart
class ContentMatchSnippet {
  final String snippet;   // rawText 的顯示片段（可能截斷加省略號，不做關鍵字加粗以外的處理）
  final String locator;   // 原樣透傳 book_content_index.locator，開書跳轉用
}

/// 一本書底下的內容匹配結果，[matches] 長度不超過查詢時傳入的
/// `perBookLimit`。不重複攜帶 [book] 多份（避免一本書 3 筆命中就重複帶
/// 3 份完整 Book 物件），UI 依此結構直接渲染「一本書一個區塊、底下最多
/// 3 個可點擊片段」，不需要在畫面層自己依 book_id 分組。
class BookContentMatches {
  final Book book;
  final List<ContentMatchSnippet> matches;
}

abstract class SearchRepository {
  Future<List<Book>> searchTitleAuthor(String query);
  Future<List<BookContentMatches>> searchContent(String query, {int perBookLimit = 3});
}
```

- `searchTitleAuthor()`：直接查 `books` 表 `title LIKE '%?%' OR author LIKE '%?%'`（不經 FTS5，不受「啟用全文檢索」影響，永遠可用——比照 `design.md` 決策）。
- `searchContent()`：`query.trim()` 為空，或 `tokenizeForQuery(query)` 轉換後為空字串時，**直接在 Dart 端回傳 `const []`**，不送出查詢——避免對 SQLite 下 `LIKE '%%'` 或語法無效的 `MATCH '""'`。非空時對 `book_content_fts MATCH ?` 查詢，依 `bm25(book_content_fts)` 排序取分數，SQL 概念（Android 11 系統 SQLite 3.28 已支援 `ROW_NUMBER() OVER`）：
  ```sql
  SELECT book_id, locator, raw_text, rn FROM (
    SELECT bci.book_id, bci.locator, bci.raw_text,
           ROW_NUMBER() OVER (
             PARTITION BY bci.book_id
             ORDER BY bm25(book_content_fts)
           ) AS rn
    FROM book_content_fts
    JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
    WHERE book_content_fts MATCH :tokenizedQuery
  ) WHERE rn <= :perBookLimit
  ```
  查詢結果依 `book_id` 分組組成 `BookContentMatches`（分組本身在 Dart 端做一次 `groupBy`，SQL 只負責限制每本書筆數與排序，不做二次窮舉）。**`searchContent()` 介面本身不需要 `ContentIndexCategory` 參數**——`book_content_index` 天生只會有已啟用該格式分類的書籍資料，兩個開關的狀態已經完全反映在索引資料的存在與否上，查詢邏輯不需要另外感知分類。兩個開關皆關閉、或索引皆為空時回傳空陣列，UI 依此顯示「啟用全文檢索」引導卡片；**只有一個開關開啟時**，引導卡片改顯示「已啟用『其他格式』全文檢索，PDF 內容尚未啟用」（或反之）之類的精確提示，而非籠統的「請啟用全文檢索」（第 4 節已提供兩個獨立 `isEnabled(category)` 查詢供畫面判斷分別顯示哪種提示）。
- UI 行為：搜尋框帶入書架快速過濾欄位的關鍵字作初始值，可修改後重新查詢；輸入採 300ms debounce（`Timer`，無需新依賴）；固定黏著於搜尋框下方的提示列（`banner`）常駐顯示「搜尋書內內容」入口，不受結果清單捲動/分頁影響（比照 `design.md` 決策）；AppBar 常駐設定選單承接兩個「啟用全文檢索」開關與各自的「重建索引」（第 4 節）。
- **E-Ink 模式**：畫面切換與結果清單捲動比照 `DESIGN.md` §18 既有慣例——`Duration.zero` 零時長轉場、結果清單啟用離散分頁（整頁刷新，不做平滑滾動動畫），避免電子紙殘影；本畫面沒有需要另外設計的例外，直接沿用既有 E-Ink 適配基礎設施（比照書架/設定畫面既有做法），不需要重新發明。

## 6. `ReaderScreen` Seam 擴充

`reader_screen.dart` 建構子新增一個可選具名參數：

```dart
class ReaderJumpTarget {
  final String? cfi;           // Foliate
  final int? pdfPageIndex;     // PDF
  final PercentRect? pdfRect;  // PDF 精確座標，暫態高亮疊加用
  const ReaderJumpTarget({this.cfi, this.pdfPageIndex, this.pdfRect});
}

const ReaderScreen({
  ...
  this.initialJumpTarget,
});
final ReaderJumpTarget? initialJumpTarget;
```

- **`initialJumpTarget` 的作用範圍精確限定為「決定建構子傳給底層 View 的初始定位參數」，不是一個貫穿整個閱讀 session 的「暫停進度儲存」旗標**：查證現行 `_writeCurrentPosition()`（`reader_screen.dart:630`）的既有機制，進度**不是**在每次 `onLocatorChanged` 觸發時逐筆寫入，而是只在特定 checkpoint（App 背景化 `didChangeAppLifecycleState`／`dispose()`）才讀取當下最新的 `_epubPositionInfo`/`_pdfPageInfo`（這兩者確實在每次 `onLocatorChanged` 時更新，但只是更新記憶體狀態，不代表寫入資料庫）寫入資料庫。這代表 `initialJumpTarget` 需要做的事情，跟現行「用資料庫存的 `lastPosition` 決定 `initialLocatorJson`/`initialPageIndex`」基本同構——只是多一個優先權更高的來源可選：開書當下，`initialLocatorJson`/`initialPageIndex` 改成「`initialJumpTarget` 存在則用它，否則沿用現行 `_initialPosition` 邏輯」。
- **【2026-09-11 修訂】checkpoint 寫入（`_writeCurrentPosition()`）需要額外一層「使用者是否已產生後續重定位」保護，推翻本節原始版本「不需要額外判斷」的結論**：原始版本主張「使用者從跳轉位置開始往後翻頁閱讀，`_epubPositionInfo` 自然更新為使用者實際所在位置，下次 checkpoint 觸發時就會正確存下使用者真正閱讀到的地方，不需要額外的『使用者是否已產生主動互動』判斷」，並記錄「審查意見 I-2 提議追蹤『第一次重定位事件』，經查證現行 checkpoint-only 寫入機制後，這層追蹤是不必要的複雜度，予以簡化」。`plans/plan-issue-5.md` 執行前的計畫審查（`reviews/review-plan-issue-5.md` I-2）重新提出同一個疑慮並具體指出後果：使用者若只是從全庫搜尋點進來查看一下搜尋結果、隨即在**尚未做任何翻頁/導覽**的情況下離開，`dispose()` 仍會無條件呼叫 `_writeCurrentPosition()`，把「畫面目前顯示的位置」（也就是搜尋跳轉目標本身）當成新進度寫入，覆蓋掉使用者跳轉前真正讀到的進度——這與 `issues.md` Issue 5 驗收標準「原本的閱讀進度不受影響」字面衝突，經人類決議此邊界情況值得修正，採納原本被簡化掉的追蹤機制：
  - 新增一個布林旗標（例如 `_hasRelocatedSinceOpen`），初始為 `false`，只在 `initialJumpTarget` 非 `null` 時才有意義。
  - `_pdfPageInfo`/`_epubPositionInfo` 這兩個既有欄位本身就是「開書後第一次賦值」與「後續每次重新賦值」的天然分界點（初始值皆為 `null`，只透過 `onPageChanged`/`onLocatorChanged` 回呼賦值）：**開書後第一次進入這兩個回呼時（賦值前欄位仍是 `null`），代表這正是 `initialJumpTarget` 套用後、書籍剛完成初始定位的回報，不算使用者主動導覽**；同一個回呼**第二次（或之後）**被呼叫時（賦值前欄位已非 `null`），不論觸發來源是翻頁熱區、音量鍵、目錄／書籤跳轉、或書內搜尋——這些管道最終都會走同一組 `onPageChanged`/`onLocatorChanged` 回呼報告新位置，故這個判斷天然涵蓋所有導覽方式，不需要逐一在每個導覽入口個別插樁——即可判定使用者確實已經離開了跳轉目標本身，把旗標設為 `true`。
  - `_writeCurrentPosition()` 開頭新增一行防呆：`initialJumpTarget` 非 `null` 且 `_hasRelocatedSinceOpen` 仍是 `false` 時直接 `return`，保留資料庫既有的 `lastPosition`、不覆寫；其餘情況（`initialJumpTarget` 為 `null`，或已有後續重定位）維持原有邏輯不變。
  - 這個旗標只在整個 `ReaderScreen` 生命週期內設定一次（`false → true` 單向轉換，不會再變回 `false`），實作成本是兩個既有回呼各加一行判斷＋一個新欄位＋`_writeCurrentPosition()` 開頭一行防呆，不需要建立新的事件系統或修改任何既有導覽呼叫端。
- 抵達目標位置後觸發暫態高亮：
  - Foliate：`main.js` 新增 `window.showSearchHighlight(cfi)`／`window.clearSearchHighlight()`，使用獨立的 `currentSearchHighlightValue` 變數，**不重用**現有 `showTtsHighlight()` 的 `currentTtsAnnotationValue`（該變數與 TTS 播放狀態機耦合，混用會互相汙染）。
  - PDF：複用既有 `pageOverlaysBuilder` 疊加機制（`pdf_reader_view.dart`），比照劃線/搜尋既有疊加繪製模式，畫一個對應 `pdfRect` 的暫態高亮矩形。
  - 生命週期由 **Dart 端 `Timer`** 控制（3 秒後呼叫清除，而非 JS `setTimeout`），比照專案既有「計時器一律由 Dart 端主導、`package:clock`／`FakeAsync` 可介入」的既有慣例（見 `CLAUDE.md`「不可逆的技術決策」小節）；使用者提前翻頁或點擊畫面時，既有的翻頁/點擊處理路徑一併呼叫清除，取兩者較早發生者。

## 7. CBZ／DRM KF8／未下載書籍

- `content_index_status.status = 'unsupported'`：CBZ（無文字層）、偵測到 DRM 加密的 KF8。排程器查詢 pending 佇列時天生排除（`status != 'pending'/'indexing'`）。
- 未下載的雲端/遠端書庫書籍（`books.is_downloaded = 0`）：不建立 `content_index_status` 列（書名/作者查詢不受影響）；下載完成（`is_downloaded` 轉為 `1`）時，由既有下載完成事件流程（`download_queue_controller.dart`／`remote_book_downloader.dart` 既有回呼點）依該書 `format` 對應的 `ContentIndexCategory` 是否已啟用，才補插入一筆 `status='pending'`（未啟用則不插入，比照一般匯入書籍同樣受開關管控，不特殊放寬）。
- 移除本機快取（`is_downloaded` 轉回 `0`）時，由既有移除快取的呼叫路徑一併執行 `DELETE FROM book_content_index WHERE book_id = ?`＋`DELETE FROM content_index_status WHERE book_id = ?`（比照「重建索引」同一段清除邏輯，可抽成共用函式）。

## 8. 效能驗證（進 Scrum Master 拆 Issue 前的前置任務）

[ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md) 決策 4 採單層索引設計，但**必須**在拆其餘 `issues.md` 工單前完成一次量化驗證，作為 Issue 0（**不是丟棄式的純 Spike**——Issue 0 本身就要落地第 1 節資料庫 schema 與第 2 節 tokenizer 純函式，兩者皆是產品程式碼、往後的 Foliate/PDF indexer 直接沿用，不是驗證完就丟掉重寫；Issue 0 的「Spike」性質僅限於「用合成資料驗證效能」這個結論本身，其餘產出正常保留）：

1. 依第 1 節／第 2 節實作資料庫 schema 與 tokenizer，並產生近似真實規模的合成測試資料：約 1,000 本書、每本 7,000-12,000 句（對應 20-30 萬字中文小說），寫入 `book_content_index`/`book_content_fts`。
2. 在中低階 Android 裝置或對應規格的模擬器上，實測 `searchContent()` 查詢延遲，確認是否符合 NFR-2「500ms 內回應」。
3. **若符合**：維持單層設計，Issue 0 結案，不再回頭處理。
4. **若不符合**：在 Issue 0 的結論中另外提出兩層式索引（書籍/章節級粗篩 FTS ＋ 命中後才查句級明細）的 schema 修訂，作為本 Epic 內追加的一個 Issue（新增彙總層，不影響既有 `book_content_index`/`book_content_fts` 資料，非砍掉重練）。

## 明確排除（沿用 `design.md`，此處重申以免實作時誤觸）

- 不處理「本書內搜尋」既有缺口（Foliate 格式 Chrome Bar「搜尋」按鈕 stub）。
- 不修改 `GlobalReaderPrefs` 既有欄位結構。
- 索引資料（`content_index_status`／`book_content_index`／`book_content_fts`）不參與 `epic-8-sync` 跨裝置同步，純本地衍生資料。
- 不在本 Epic 內建兩層式索引架構（僅在第 8 節效能驗證失敗時才追加）。

## 下一步

Scrum Master：拆 `docs/epics/epic-10-search/issues.md`，Issue 0 為第 8 節效能驗證 Spike，其後依本文件章節切分（Schema／Tokenizer／Foliate Indexer／PDF Indexer／Scheduler／設定模型／全庫搜尋畫面／`ReaderScreen` Seam）為垂直切片，每個 Issue 附對應單元測試要求。
