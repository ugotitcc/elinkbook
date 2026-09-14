# Epic 41 — 全文檢索模組架構深化：工單清單 (Issues)

依 `/improve-codebase-architecture`（2026-09-13，範圍 `epic-10-search` 開發後的程式碼，6 個候選深化機會）逐項評估，並用 `/grilling` 敲定實作細節後拆案。Issue 1/3 為一條鏈，其餘互相獨立，詳見 `epic.md` 依賴圖。

---

## Issue 1：收斂 ReaderScreen 組裝為一個工廠函式（`buildReaderScreen()`）

**Status:** ready-for-agent

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 1（Worth exploring）。`/grilling` 已敲定介面形狀（Q3）。

**背景／目標：** 開一本書要建構 `ReaderScreen` 時，三個呼叫點——`library_screen.dart:431-469`（`_openBook()`）、`library_search_screen.dart:146-192`（`_openBook()`）、`book_search_screen.dart:146-185`（推入 `ReaderScreen` 那段）——各自手動列出約 20 個具名參數，三份幾乎逐字相同，只有下列 4 處不同：

- `filePath`/`bookId`/`bookTitle`/`bookAuthor`/`bookProgress`/`isFixedLayout`：`library_screen.dart` 用 `book.xxx`；另兩個畫面用 `widget.book.xxx`（欄位來源相同，只是變數名不同）。
- `libraryRepository`：`library_screen.dart` 傳 `widget.repository`；另兩個畫面傳 `widget.libraryRepository`。
- `isEinkMode`：`library_screen.dart` 傳 `widget.themeDependencies.isEinkMode`；另兩個畫面傳 `widget.isEinkMode`。
- `initialJumpTarget`：只有 `library_search_screen.dart`／`book_search_screen.dart` 有帶（`library_screen.dart` 沒有這個概念，永遠是一般開書路徑）。

`epic-26-architecture-hardening` Issue 7/8 已把散落欄位收斂成 `LibraryReaderFeatureRepositories`／`LibrarySyncDependencies` 兩個 bundle（`library_screen_dependencies.dart`），三個呼叫點目前都已經在用這兩個 bundle 取值——但「組裝 `ReaderScreen` widget 本身」這一步從未收斂，`epic-10-search` 這次又新增兩份幾乎逐字重複的呼叫點，複本從 1 份變 3 份。往後任何新增給 `ReaderScreen` 的欄位都要記得同步改三處，漏改其中一處不會有編譯期或型別系統的提示。

**Solution（依 `reviews/review-epic-and-issues.md` I-3 修訂：回傳具體型別 `ReaderScreen`、函式改名 `buildReaderScreen`，不叫 `...Route` 以免與 Flutter `Route<T>` 命名慣例衝突且弱化測試型別檢查）：**

- 新增 `app/lib/screens/reader_screen_route.dart`，頂層函式：
  ```dart
  ReaderScreen buildReaderScreen({
    required Book book,
    required ReaderPrefsManager prefsManager,
    required LibraryReaderFeatureRepositories features,
    required LibrarySyncDependencies sync,
    required LibraryRepository libraryRepository,
    required bool isEinkMode,
    ReaderJumpTarget? initialJumpTarget,
  })
  ```
  內部展開 `features.xxx`／`sync.xxx` 填入 `ReaderScreen` 現有的 20 個具名參數，回傳型別直接是 `ReaderScreen`（不是抽象 `Widget`），單元測試才能不轉型直接存取欄位。實作者動手前先讀 `library_screen.dart:435-468` 核對目前 `ReaderScreen` 建構子的完整欄位清單，逐一對帳，不可遺漏。
- 三個呼叫點改為：
  ```dart
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => buildReaderScreen(
      book: book,
      prefsManager: widget.prefsManager,
      features: widget.readerFeatureRepositories,
      sync: widget.syncDependencies,
      libraryRepository: /* 各自現有的 repository 來源 */,
      isEinkMode: /* 各自現有的 isEinkMode 來源 */,
      initialJumpTarget: /* 僅兩個搜尋畫面帶入 */,
    ),
  ));
  ```
  `MaterialPageRoute(builder: ...)` 這層維持留在呼叫端，本 Issue 只收斂「組裝 `ReaderScreen`」這一步，不吃掉導覽這層。
- 不改動 `ReaderScreen` 建構子本身的簽章／既有測試——本 Issue 純粹是「呼叫端怎麼組裝」這一層，`ReaderScreen` 對外介面不變。

**單元測試要求：**

- `buildReaderScreen()` 的欄位對帳測試（比照 `epic-26` Issue 9 精神）：建構一組假 `LibraryReaderFeatureRepositories`／`LibrarySyncDependencies`，斷言回傳的 `ReaderScreen` 實例（強型別，無需 `as ReaderScreen` 轉型）上每一個欄位都正確帶入，`initialJumpTarget` 為 `null`／有值時皆要各自斷言到。
- 三個既有呼叫點（`library_screen_test.dart`／`library_search_screen_test.dart`／`book_search_screen_test.dart`）既有的「點擊書籍開啟閱讀器」測試必須零回歸——這是驗證「改用工廠函式後行為不變」的關鍵回歸測試，不需要新增測試案例，跑過即可。

**驗收標準：** 三處呼叫點程式碼中不再各自列出 20 個具名參數；`flutter analyze` 乾淨；`flutter test` 全數通過，三個既有畫面的開書測試零回歸。

---

## Issue 2：抽出 ContentIndexStatusStore 收斂 content_index_status 狀態轉換

**Status:** ready-for-agent

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 2（Worth exploring）。`/grilling` 已敲定職責邊界（Q4）。

**背景／目標：** `content_index_status` 資料表有 5 種狀態值（`pending`／`indexing`／`done`／`error`／`unsupported`），轉換規則分散在兩個檔案各自手寫 SQL：

- `ContentIndexingScheduler._processOneBook()`（`content_indexing_scheduler.dart:157-279`）：負責 `indexing→done/error`，並在偵測到「已被外部關閉」時整批 `DELETE`。
- `SqliteFullTextSearchSettingsRepository`（`full_text_search_settings_repository.dart:105-218`）：負責 `→pending`（`_backfillPending`／`handleBookAvailable`）、`→unsupported`（`markUnsupported`）、整批清除（`_clearIndexData`/`clearBookIndex`）。

兩邊都各自寫 `WHERE book_id = ?` 的原始 SQL，都要各自知道欄位名稱（`last_chapter_index`、`updated_at`……）與合法值字串，拼字錯誤不會被型別系統攔到。`full_text_search_settings_repository.dart:50-54` 的既有註解也承認這個耦合是刻意留下的——兩個模組互相依賴對方「當下的實作行為」而非依賴一個共同介面的約定。**刪除測試：** 拿掉其中一個模組，狀態機完整性直接壞掉（例如少了排程器的章節邊界檢查，關閉開關後會留孤兒索引列）——複雜度真實存在，只是沒人扛。

**Solution（依 `reviews/review-epic-and-issues.md` I-2 修訂：`content_index_status` 表以 `book_id` 為 Primary Key、**沒有 `category` 欄位**〔見 `sqlite_library_repository.dart:880-887`〕，單書操作不該要求呼叫端提供 category；`markIndexing` 拆分「轉態」與「更新章節游標」；補齊既有的 category 層級批次 SQL）：**

- 新增 `app/lib/search/content_index_status_store.dart`，`ContentIndexStatusStore` 類別，介面只收「純狀態資料存取」，**不收**排程迴圈「中途要不要繼續處理」這個決策（`/grilling` Q4 已敲定，該決策留在 `ContentIndexingScheduler` 內，只是改呼叫 `store.isTracked()` 取得資料再自行判斷）：
  ```dart
  class ContentIndexStatusStore {
    ContentIndexStatusStore(DatabaseExecutor db); // 接受 Database 或 Transaction，供交易情境使用

    // 單書操作：book_id 已是全域唯一鍵，不需要（也不該要求）呼叫端額外帶 category。
    Future<void> markPending(String bookId);
    Future<void> markIndexing(String bookId); // 轉態為 indexing，不動 last_chapter_index
    Future<void> updateProgress(String bookId, int lastChapterIndex); // 每完成一個章節呼叫一次
    Future<void> markDone(String bookId);
    Future<void> markError(String bookId, {required String error});
    Future<void> markUnsupported(String bookId);
    Future<bool> isTracked(String bookId);
    Future<void> deleteForBook(String bookId); // 取代現有 clearBookIndex()：同一交易內刪除 book_content_index + content_index_status 兩張表

    // category 層級批次操作：對應現有 _backfillPending()／_clearIndexData()，
    // 直接依格式篩選 books 表操作，不透過記憶體中的 bookId 清單。
    Future<void> backfillPending(ContentIndexCategory category);
    Future<void> clearByCategory(ContentIndexCategory category);
  }
  ```
  `markIndexing`／`updateProgress` 拆分理由：`ContentIndexingScheduler._processOneBook()`（`content_indexing_scheduler.dart:157-163`）一進入時只轉態為 `indexing`（此時尚未處理任何章節，游標維持原值)；`flushPendingChapter()`（同檔 `:185` 起）每完成一個章節才更新 `last_chapter_index`——原規劃把兩者綁在同一個帶 `lastChapterIndex` 參數的 `markIndexing()` 裡會混淆這兩個時機點。`backfillPending`/`clearByCategory` 對應現有 `_backfillPending(category)`/`_clearIndexData(category)`（`full_text_search_settings_repository.dart:174-218`）：兩者皆是直接對 `books` 表依格式篩選、`INSERT ... SELECT`／`DELETE ... WHERE book_id IN (SELECT id FROM books WHERE ...)` 的批次 SQL，不是先在 Dart 端查出一批 `bookId` 再逐筆處理，改用 `store` 後仍須維持同一種「整段交給 SQL」的寫法，不可退化成迴圈呼叫單書方法（會嚴重變慢）。
  確切欄位名稱／`ContentIndexCategory` 列舉、`_formatFilterFor()` 等既有 private helper 以實際程式碼為準，實作者動手前先讀 `full_text_search_settings_repository.dart` 全檔核對。
- `ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 皆改為持有一個 `ContentIndexStatusStore` 實例，刪除各自原本手寫的 SQL 語句，改呼叫上述方法。`markUnsupported`／`handleBookAvailable`／`clearBookIndex` 等現有公開方法簽章維持不變，內部改為委派給 `store`。

**單元測試要求：**

- `ContentIndexStatusStore` 獨立單元測試：`markPending`/`markIndexing`/`updateProgress`/`markDone`/`markError`/`markUnsupported` 各自驗證寫入正確的欄位值；`deleteForBook` 驗證兩張表皆被刪除；`backfillPending`/`clearByCategory` 驗證依格式篩選正確（比照現有 `full_text_search_settings_repository_test.dart` 的既有測試資料建置方式）。
- `ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 既有測試（`content_indexing_scheduler_test.dart`／`full_text_search_settings_repository_test.dart`）改用新 store 後必須零回歸（比照刪除測試精神：換掉底層實作，行為不變）。

**驗收標準：** 兩個檔案內不再出現手寫的 `content_index_status` UPDATE/INSERT/DELETE SQL；`flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

---

## Issue 3：ReaderJumpTarget 收下「套用到 View」的行為（`applyTo()`）

**Status:** ready-for-agent

**依賴：** Issue 1（`ReaderScreen` 開書/跳轉組裝路徑先穩定，避免與本 Issue 的 diff 互相干擾；`applyTo()` 是給 `ReaderScreen` State 內部呼叫，非 Issue 1 新增的工廠函式直接呼叫）

**來源：** `/improve-codebase-architecture` 候選 3（Worth exploring）。`/grilling` 已敲定單一方法＋`shouldNavigate` 旗標（Q5）。

**背景／目標：** `ReaderJumpTarget`（`reader/reader_jump_target.dart`，全檔 75 行）只負責「從 locator 字串解析出 cfi/pdfPageIndex/pdfRect」（`fromContentLocator()`），不知道「怎麼把自己套用到一個活著的閱讀器 View」。`ReaderScreen` 裡有兩段幾乎相同的 if-else 各自做格式分派：

- `_maybeShowSearchJumpHighlight()`（`reader_screen.dart:1577-1596`）：開書當下只需疊加高亮。
- `_handleReaderSearchJumpTarget()`（`reader_screen.dart:1642-1660`）：session 內需要先跳頁（`jumpToPage`/`jumpToLocator`）再疊加高亮。

兩者的格式判斷、欄位存取（`jumpTarget.pdfPageIndex`/`jumpTarget.pdfRect`/`jumpTarget.cfi`）完全重複，只有「要不要先跳頁」這一個變數不同——`reader_screen.dart:1632-1641` 的既有註解本身也點出兩者差異，但沒有收斂共同部分。**刪除測試：** 拿掉 `ReaderJumpTarget` 類別，`ReaderScreen` 兩處分派邏輯幾乎不用改，代表真正的行為複雜度已經冒到呼叫端，且冒了兩次。

**Solution（依 `reviews/review-epic-and-issues.md` I-1 修訂：`PdfReaderViewState`/`FoliateReaderViewState` 是不存在的私有型別，`reader_screen.dart` 現有慣例一律用 `GlobalKey<State<PdfReaderView>>`/`GlobalKey<State<FoliateReaderView>>`；靜態 helper 皆為同步方法，`applyTo()` 不應無謂非同步化；且需要回傳「是否真的套用了暫態高亮」，呼叫端才知道要不要啟動自動清除計時器）：**

- 在 `ReaderJumpTarget` 新增方法（`/grilling` 已敲定的旗標設計，型別依審查修正為專案既有公開型別、同步、回傳 `bool`）：
  ```dart
  bool applyTo({
    required BookFormat format,
    required GlobalKey<State<PdfReaderView>> pdfKey,
    required GlobalKey<State<FoliateReaderView>> foliateKey,
    required bool shouldNavigate,
  });
  ```
  內部依 `format` 分派到 PDF／Foliate 分支，`shouldNavigate == true` 時先呼叫 `jumpToPage`/`jumpToLocator`，接著兩種情況都嘗試疊加暫態高亮（PDF 需要 `pdfRect` 才顯示；Foliate 需要 `cfi`；`pdfPageIndex`/`cfi` 缺失時優雅跳出，沿用既有 `ReaderJumpTarget.fromContentLocator()` 文件註解的語意，不拋例外）。**回傳值即「本次是否真的疊加了暫態高亮」**（PDF 端對應 `pdfPageIndex != null && pdfRect != null`；Foliate 端對應 `cfi != null`），供呼叫端決定要不要啟動計時器——比照現行 `reader_screen.dart:1583-1594`／`1644-1656` 的既有降級語意：PDF 只有 `pageIndex`、`rect == null` 時只跳頁不顯示高亮，此時應回傳 `false`。方法本身**不含**「啟動/清除 3 秒自動計時器」（`_startSearchJumpHighlightAutoClearTimer`/`_clearSearchJumpHighlight`）——這是 `ReaderScreen` 自己的計時器生命週期狀態，維持留在 `ReaderScreen`。
- `_maybeShowSearchJumpHighlight()`／`_handleReaderSearchJumpTarget()` 改為：
  ```dart
  final highlightShown = jumpTarget.applyTo(
    format: format,
    pdfKey: _pdfReaderViewKey,
    foliateKey: _foliateEpubReaderViewKey,
    shouldNavigate: /* false：開書當下已在目標位置；true：session 內跳轉 */,
  );
  if (highlightShown) {
    _startSearchJumpHighlightAutoClearTimer();
  }
  ```
  取代原本兩處各自展開的 if-else 格式分派。

**單元測試要求：**

- `applyTo()` 獨立單元測試：PDF／Foliate 兩種格式、`shouldNavigate` 兩種值的組合皆正確呼叫對應方法（用假 `GlobalKey`／既有測試慣例的 fake View state）；`pdfRect`/`cfi` 缺失時的優雅降級行為需各自驗證，並斷言此時回傳值為 `false`。
- `reader_screen_test.dart` 既有 Issue 5／Issue 8 搜尋跳轉測試零回歸，含 PDF `rect == null` 只跳頁不顯示高亮、且不誤啟動自動清除計時器的既有行為。

**驗收標準：** `reader_screen.dart` 內兩段格式分派 if-else 合併為呼叫同一個 `applyTo()`；`flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

---

## Issue 4：抽出 splitHighlightSegments 純函式，BookSearchScreen 高亮邏輯脫離 BuildContext

**Status:** ready-for-agent

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 4（Worth exploring）。`/grilling` 已敲定範圍邊界（Q6：不觸碰 `LibrarySearchScreen`）。

**背景／目標：** `BookSearchScreen._buildHighlightedText()`（`book_search_screen.dart:372-419`）同時做兩件事：(1) 純演算法——在字串中找出所有 case-insensitive 命中位置、切成片段；(2) 依 E-Ink 模式決定樣式。兩者混在一起、又是私有 State 方法，介面幾乎和實作一樣複雜——這正是最近一次字級 bug（commit `b6cd0b7f`）的根因所在：呼叫端誤用 `DefaultTextStyle.of(context)` 拿到 `MaterialApp` 的 48px 錯誤警示字級。目前的回歸測試（`test/screens/book_search_screen_test.dart:402-443`）只能透過整個 widget 樹 pump 後量測 render 出來的文字大小間接驗證，沒辦法針對「切分是否正確」單獨下單元測試。**刪除測試：** 刪掉這個方法，複雜度（找命中位置、切片、依模式套樣式）會原封不動冒到任何未來想加高亮的呼叫端——是真實行為，只是被鎖在一個綁死 context 的私有方法裡。

**範圍邊界（`/grilling` Q6 已確認）：** `spec.md` §9.2 當初刻意決定 `LibrarySearchScreen` 的內容匹配片段**不做**高亮，本 Issue **不**改動 `LibrarySearchScreen` 既有行為（維持 `_buildContentGroupCard` 純 `Text(snippet)`），只做「抽出純函式＋`BookSearchScreen` 改用它」。日後若要讓兩個畫面都高亮，是另一張獨立的產品需求 Issue，不與本次重構混為一談。

**Solution（依 `reviews/review-epic-and-issues.md` M-1 修訂：須為公開頂層函式才能被獨立測試檔引用；`HighlightSegment` 須有值相等性，否則清單斷言 `expect(segments, [HighlightSegment(...)])` 會因參照不同而失敗）：**

- 新增 `app/lib/search/highlight_segments.dart`（**公開頂層函式，不可設為 `book_search_screen.dart` 內的私有函式**——私有函式外部測試檔無法直接引用）：
  ```dart
  @immutable
  class HighlightSegment {
    final String text;
    final bool isMatch;
    const HighlightSegment(this.text, this.isMatch);

    @override
    bool operator ==(Object other) =>
        other is HighlightSegment && other.text == text && other.isMatch == isMatch;

    @override
    int get hashCode => Object.hash(text, isMatch);
  }

  List<HighlightSegment> splitHighlightSegments(String text, String query);
  ```
  （亦可改用 Dart 3 Record `({String text, bool isMatch})` 取代具名類別——Record 天生有值相等性，實作者可自行選擇，兩者皆滿足本 Issue 要求。）不依賴 `BuildContext`／`Theme`／E-Ink 模式；純粹回傳「這段文字要不要標記為命中」的序列。空 `query` 時回傳單一 `isMatch: false` 的完整字串片段。
- `_buildHighlightedText()` 改為呼叫 `splitHighlightSegments()`，只保留「把 segments 轉成有樣式的 `TextSpan`」這一層 widget 相關邏輯（依 E-Ink 模式套用粗體/底線或粗體/背景色），並維持既有的 bug 修復（`Text.rich(TextSpan(children: spans))`，不手動指定 `style: DefaultTextStyle.of(context).style`）。

**單元測試要求：**

- 新增 `test/search/highlight_segments_test.dart`：`splitHighlightSegments()` 純函式單元測試，含空 query、大小寫不敏感比對、多個命中、命中位置在字串開頭/結尾/重疊邊界；斷言方式可直接 `expect(segments, [HighlightSegment(...), ...])` 清單比對（`operator ==` 已補齊）。
- 既有 `book_search_screen_test.dart` 高亮相關 widget test（含最近新增的字級回歸測試）零回歸。

**驗收標準：** 命中位置切分邏輯有獨立於 widget tree 的單元測試覆蓋；`flutter analyze` 乾淨；`flutter test` 全數通過，零回歸；`LibrarySearchScreen` 完全未變動。

---

## Issue 5：抽出 FullTextSearchTogglesController 收斂全文檢索開關重複邏輯

**Status:** ready-for-agent

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 5（Speculative）。`/grilling` Q7 確認仍拆為可執行 Issue（做法機械、風險低）。

**背景／目標：** 兩段程式碼逐行對應——都是「呼叫 `isEnabled()` 兩次填兩個布林值」＋「切換前彈確認 Dialog、確認後呼叫 `setEnabled` 再 setState」：

- `_FullTextSearchQuickSettingsPanelState._load()`/`_handleToggle()`（`library_search_screen.dart:513-556`）
- `SettingsScaffold._loadFullTextSearchSettings()`/`_handleFullTextSearchToggle()`（`settings_scaffold.dart:130-169`）

`library_search_screen.dart:492-495` 的既有註解只解釋了「為什麼 UI 要分開」（與 `SettingsScaffold` Key 命名空間衝突），沒解釋非 UI 邏輯為何也各自重寫。**刪除測試：** 刪掉任一份，另一份原封不動——兩份都是可獨立存在的完整複本，不是必要結構。

**Solution（依 `reviews/review-epic-and-issues.md` M-2 修訂：兩個呼叫端現有的 `repository` 皆為可空型別 `FullTextSearchSettingsRepository?`〔`library_search_screen.dart:497`／`settings_scaffold.dart:67`〕，需明訂 controller 怎麼處理；並明訂維持純資料物件、不繼承 `ChangeNotifier`）：**

- 新增 `app/lib/search/full_text_search_toggles_controller.dart`：
  ```dart
  class FullTextSearchTogglesController {
    FullTextSearchTogglesController(this._repository);
    final FullTextSearchSettingsRepository? _repository;
    bool pdfEnabled = false;
    bool foliateEnabled = false;

    // _repository == null（未組裝/測試替身缺省情境）時 no-op，
    // pdfEnabled/foliateEnabled 維持預設值 false，不拋例外。
    Future<void> load();
    Future<void> toggle(ContentIndexCategory category, bool newValue);
  }
  ```
  `_repository == null` 時 `load()`/`toggle()` 皆直接 no-op（不拋例外），呼叫端不需要先自行判斷 `repository != null` 才建構 controller——與現有兩個呼叫端「`repository` 可能尚未組裝完成」的既有可空語意一致。`toggle()` 只負責呼叫 `repository.setEnabled()` 並更新內部布林值；確認 Dialog 的彈出/取消判斷維持在各自 Widget 層呼叫 `toggle()` 前處理，不搬進 controller——避免 controller 依賴 `BuildContext`。**Controller 維持純資料物件、不繼承 `ChangeNotifier`**（`/grilling` 未展開過這個岔路，此處依審查建議定案：確認 Dialog 留在 Widget 端、改動量小，兩個 Widget 各自在呼叫 `await controller.toggle(...)` 後自行 `if (mounted) setState(() {})` 刷新畫面，比引入 `ChangeNotifier`／`AnimatedBuilder` 更貼合現有兩個 `StatefulWidget` 的既有寫法）。
- 兩個 Widget（`_FullTextSearchQuickSettingsPanel`／`SettingsScaffold` 的對應段落）改為持有一個 controller 實例，刪除各自手寫的 `_load()`/`_handleToggle()` 邏輯本體，只保留 UI 排版、各自的 `Key`，以及呼叫 controller 方法後的 `setState(() {})`。

**單元測試要求：**

- `FullTextSearchTogglesController` 獨立單元測試：`load()` 正確讀回兩個布林值；`toggle()` 正確呼叫 `repository.setEnabled()`；`repository == null` 時 `load()`/`toggle()` 皆安全 no-op、不拋例外。
- 兩個 Widget 既有測試零回歸。

**驗收標準：** 兩處開關邏輯改用同一個 controller；`flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

---

## Issue 6：（記錄用，暫不動手）JsBridgeGateway 對「連續請求同一 handler、按序配對」場景介面太淺

**Status:** needs-info

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 6（Speculative）。`/grilling` Q8 已確認：不擴充 `JsBridgeGateway` 介面，先只記錄，等出現觸發條件再重新評估。

**背景：** `JsBridgeGateway`（`reader/js_bridge_gateway.dart:28-83`）設計是「每個 handler name 同時只能有一個 pending completer」。`FoliateContentIndexer.indexBook()` 需要在同一次呼叫內對 `onSegmentsForSectionReady` 這個 handler 連續呼叫 N 次（每章節一次）——`foliate_content_indexer.dart:50-59` 的既有註解明白指出：某章逾時後才遲到抵達的舊回應，會被 gateway 誤判成下一章的回應、造成資料錯位（已證實可重現的競態，非理論疑慮）。現行解法是**繞過 gateway**，在 `foliate_content_indexer.dart:110-193` 自己重新實作一套「記錄目前預期章節索引＋手動 completer＋手動 timeout」的邏輯——等於在呼叫端重新發明了 gateway 原本要收斂掉的「發請求→等回呼→逾時處理」樣板，只是多加了一層「章節序號比對，過期就丟棄」。

**為什麼現在不動手（`/grilling` Q8）：** 目前只有 `FoliateContentIndexer` 這一個呼叫端需要「連續呼叫同一 handler、按序配對、丟棄過期回應」這個模式——「一個轉接器只是假設性接縫」，現有繞過寫法行為正確、有明確註解說明競態原因，只是不夠深。貿然在 `JsBridgeGateway` 加一個目前只有一個真實用法的抽象，風險是「做了但用不到」。

**觸發重新評估的條件：** 出現第二個呼叫端需要同樣「連續對同一 handler 發出請求、需要按呼叫順序配對回應、且要丟棄過期回應」的模式時（例如未來格式擴充需要另一套逐章節/逐頁背景擷取），回頭評估是否在 `JsBridgeGateway` 增加一個帶關聯值（correlation id）的請求模式：

```dart
Future<T> requestCorrelated<T>({
  required void Function() jsCall,
  required String handlerName,
  required dynamic Function(dynamic) correlationExtractor,
  required dynamic expectedCorrelation,
  required T Function(dynamic) parse,
  required Duration timeout,
});
```

屆時把 `FoliateContentIndexer` 現有的手動 completer/timeout/序號比對邏輯一併收斂進去。

**驗收標準：** 無（本 Issue 純記錄，不產生程式碼異動）。若之後決定動手，需另外走一輪 `/grilling` 敲定 `requestCorrelated()` 的確切簽章與逾時語意，再拆新 Issue。
