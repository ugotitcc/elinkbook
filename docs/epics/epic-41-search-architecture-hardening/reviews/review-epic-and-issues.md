# Epic 41 全文檢索模組架構深化：Epic 與工單審查報告 (Epic & Issues Review Report)

**審查對象：**
- [`docs/epics/epic-41-search-architecture-hardening/epic.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/epic.md)（Epic 看板與依賴圖）
- [`docs/epics/epic-41-search-architecture-hardening/issues.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md)（工單清單 Issue 1-6）

**關聯前置 Epic 與基準程式碼：**
- [`docs/epics/epic-10-search/epic.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-10-search/epic.md)（全文檢索母功能）
- [`app/lib/screens/reader_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/reader_screen.dart)（閱讀器入口與跳轉高亮）
- [`app/lib/screens/library_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/library_screen.dart)（書庫開書呼叫端）
- [`app/lib/screens/library_search_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/library_search_screen.dart)（全庫搜尋開書與開關面板）
- [`app/lib/screens/book_search_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/book_search_screen.dart)（單書搜尋跳轉與文字高亮）
- [`app/lib/reader/reader_jump_target.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/reader/reader_jump_target.dart)（搜尋跳轉目標模型）
- [`app/lib/reader/pdf_reader_view.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/reader/pdf_reader_view.dart) 與 [`app/lib/reader/foliate_reader_view.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/reader/foliate_reader_view.dart)（PDF / Foliate 視圖與 Static Helper）
- [`app/lib/search/content_indexing_scheduler.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/search/content_indexing_scheduler.dart)（背景索引排程器）
- [`app/lib/search/full_text_search_settings_repository.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/search/full_text_search_settings_repository.dart)（全文檢索設定與索引生命週期）
- [`app/lib/library/sqlite_library_repository.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/library/sqlite_library_repository.dart)（`content_index_status` Schema 定義）

**審查專家：** 系統架構師 & 靜態型別代碼審查員  
**審查日期：** 2026-09-14  
**審查結論：** **🟡 Changes Requested（建議修訂 3 項 Important 與 3 項 Minor 後推進實作計畫）**

---

## 摘要統計 (Findings Summary)

| 嚴重度層級 (Severity) | 數量 | 說明 |
|---|:---:|---|
| **Critical（阻斷性缺陷）** | **0** | **無阻斷性架構錯誤**（各候選重構切角精準，邊界防守嚴謹，克制投機抽象） |
| **Important（重要介面與型別缺口）** | **3** | 1. **Issue 3 型別與非同步簽章錯誤**：使用不存在的私有 State 型別（`PdfReaderViewState` / `FoliateReaderViewState`）且無謂非同步化，並遺漏暫態高亮顯示判定以協調自動清除計時器；<br>2. **Issue 2 資料庫 Schema 脫節與批次操作缺漏**：`ContentIndexStatusStore` 盲目將不存在的 `category` 欄位帶入所有方法，且未納入 `_backfillPending` / `_clearIndexData` 等批次 SQL；<br>3. **Issue 1 函式命名與回傳型別弱化**：`buildReaderScreenRoute` 回傳 `Widget` 產生命名矛盾，且回傳抽象 `Widget` 弱化單元測試欄位對帳的強型別斷言。 |
| **Minor（次要優化與細節校正）** | **3** | 1. **Issue 4 值物件相等性與檔案可測試性**：`HighlightSegment` 未定義 `operator ==` 會導致單元測試清單比對失敗，且抽為私有函式將無法獨立測試；<br>2. **Issue 5 依賴可空性與狀態響應機制**：未明定 `repository` 為 `null` 時之處置，且需釐清與 Widget 刷新機制（`ChangeNotifier` 或 `setState`）；<br>3. **`epic.md` 檔案路徑精準度**：部分畫面檔案實際位於 `app/lib/screens/`，建議於路徑描述補齊。 |
| **總計 (Total)** | **6** | **修訂 3 項 Important 後即可依序撰寫實作計畫（Plans）** |

---

## 1. 總結評估 (Executive Summary)

Epic 41 是針對 `epic-10-search` 全文檢索模組在開發完成後，透過架構盤點（`/improve-codebase-architecture`）與詰問（`/grilling`）產出的架構深化重構專案。

整份 `epic.md` 與 `issues.md` 展現了優秀的架構成熟度與紀律：
1. **重構邊界克制明確**：如 Issue 4 明確切除 `LibrarySearchScreen` 的高亮擴充，嚴守「不夾帶未定義產品需求」原則；Issue 6 明確將只有單一使用者的 `JsBridgeGateway` 暫緩至 `needs-info`，拒絕過度設計與投機抽象（Speculative Generality）。
2. **重構脈絡清晰、痛點真實**：針對 `ReaderScreen` 20 個具名參數重複組裝（Issue 1）、狀態表手寫 SQL 散落（Issue 2）、跳轉格式分派穿透至 Screen（Issue 3）、關鍵字切分演算法與 BuildContext 耦合（Issue 4）、開關狀態重複（Issue 5），皆直指先前 commit 與測試中曾踩過的真實坑洞。
3. **刪除測試思考周全**：每個 Issue 均詳細闡述「拿掉該結構會發生什麼事」，論證了重構的必要性。

然而，經對照現行程式碼庫（`app/lib/`），在**具體方法簽章、靜態型別定義、SQLite Schema 一致性**方面發現 3 項重要架構漏洞（Important）與 3 項次要細節（Minor）。若未在撰寫實作計畫前修正，實作者將會遭遇編譯錯誤、SQL 執行期例外或測試邏輯無法對齊的問題。

---

## 2. 優點與架構亮點 (Strengths)

1. **Issue 6 展現高度自制力，避免「過早抽象」**：
   - 面對 `FoliateContentIndexer` 繞過 `JsBridgeGateway` 的問題，敏銳洞察到目前僅此一處真實需求，堅守「一個轉接器只是假設性接縫」原則，將其列入 `needs-info` 記錄觸發條件，避免增加無用抽象層。
2. **Issue 4 演算法與 UI 渲染明確解耦**：
   - 將文字切分純演算法 `splitHighlightSegments` 自私有 State 與 `BuildContext` 抽離，根絕因 `MaterialApp` 錯誤警示字級導致的字級膨脹 bug，讓演算法能獨立於 widget tree 下純 Dart 單元測試。
3. **Issue 1 與 Issue 3 依賴順序精確切分**：
   - `epic.md` 精確安排 Issue 1（外部組裝工廠收斂）先於 Issue 3（內部 `applyTo()` 收斂），避免同一個 `ReaderScreen` 發生多重巨幅 diff 衝突。
4. **Issue 2 邊界劃分得當**：
   - `/grilling` Q4 敲定 `ContentIndexStatusStore` 僅收「狀態資料存取」，排程器的「中途是否繼續處理」決策仍留於 `ContentIndexingScheduler`，職責不越界。

---

## 3. 發現與修訂建議 (Findings & Recommendations)

### Critical（阻斷性缺陷）

*(無阻斷性缺陷)*

---

### Important（重要介面與型別缺口，應於實作前修正）

> [!WARNING]
> **I-1. Issue 3 簽章引述不存在的私有 State 類別，無謂非同步化，且未回傳暫態高亮套用狀態以致計時器誤觸**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/issues.md:111-120`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md#L111-L120)
>
> **問題描述與證據：**
> 1. `issues.md` 規劃的 `ReaderJumpTarget.applyTo()` 簽章如下：
>    ```dart
>    Future<void> applyTo({
>      required BookFormat format,
>      required GlobalKey<PdfReaderViewState> pdfKey,
>      required GlobalKey<FoliateReaderViewState> foliateKey,
>      required bool shouldNavigate,
>    });
>    ```
> 2. **編譯期錯誤**：
>    - 查閱 [`app/lib/reader/pdf_reader_view.dart:287`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/reader/pdf_reader_view.dart#L287) 與 [`app/lib/reader/foliate_reader_view.dart:386`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/reader/foliate_reader_view.dart#L386)，其實體 State 類別皆為私有（`_PdfReaderViewState` 與 `_FoliateReaderViewState`）。
>    - 程式碼庫中所有公開 API 與 `ReaderScreen` 內部定義（見 [`reader_screen.dart:455, 461`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/reader_screen.dart#L455)）均統一使用：
>      - `GlobalKey<State<PdfReaderView>>`
>      - `GlobalKey<State<FoliateReaderView>>`
>    - 宣告 `GlobalKey<PdfReaderViewState>` 將直接觸發編譯錯誤：`Undefined class 'PdfReaderViewState'`。
> 3. **無謂的非同步傳播 (`Future<void>`)**：
>    - 查閱靜態 Helper 方法：`PdfReaderView.jumpToPage`、`PdfReaderView.showTemporaryHighlight`、`FoliateReaderView.jumpToLocator`、`FoliateReaderView.showSearchHighlight`，**全部皆為同步 `void` 方法**（內部透過 JS evaluate 或 Controller 同步發送）。
>    - `applyTo()` 本身無任何 await 操作，若宣告為 `Future<void>` 會迫使呼叫端 `_maybeShowSearchJumpHighlight` 與 `_handleReaderSearchJumpTarget` 變成非同步，並給 `testWidgets` 帶來不必要的 fake-async 推進複雜度。
> 4. **暫態高亮判定與 3 秒自動清除計時器脫節**：
>    - `issues.md` 規定：`applyTo(...)` 呼叫後由呼叫端各自觸發 `_startSearchJumpHighlightAutoClearTimer()`。
>    - 查閱 [`reader_screen.dart:1586, 1649`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/reader_screen.dart#L1586)：在 PDF 命中片段解析降級（只有 `pageIndex`、`rect == null`）時，只執行跳頁，**不顯示高亮**，亦**不啟動 3 秒計時器**。
>    - 若 `applyTo()` 回傳 `void`，呼叫端無法得知本次是否真正繪製了高亮框，若無條件呼叫 `_startSearchJumpHighlightAutoClearTimer()`，將導致在無高亮時啟動虛假計時器。
>
> **修訂建議：**
> 1. 將 Key 型別修正為專案既有公開型別：`GlobalKey<State<PdfReaderView>>` 與 `GlobalKey<State<FoliateReaderView>>`。
> 2. 將回傳值由 `Future<void>` 改為同步 `bool`（或 `bool appliedHighlight`），代表是否成功套用了暫態高亮：
>    ```dart
>    bool applyTo({
>      required BookFormat format,
>      required GlobalKey<State<PdfReaderView>> pdfKey,
>      required GlobalKey<State<FoliateReaderView>> foliateKey,
>      required bool shouldNavigate,
>    });
>    ```
> 3. 呼叫端（`_maybeShowSearchJumpHighlight` / `_handleReaderSearchJumpTarget`）依據回傳值決定是否啟動計時器：
>    ```dart
>    final highlightShown = jumpTarget.applyTo(...);
>    if (highlightShown) {
>      _startSearchJumpHighlightAutoClearTimer();
>    }
>    ```

---

> [!WARNING]
> **I-2. Issue 2 介面設計與資料庫 Schema 脫節（重複帶入不存在的 category 參數），且遺漏既有批次 SQL 封裝**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/issues.md:70-79, 89`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md#L70-L79)
>
> **問題描述與證據：**
> 1. **Schema 脫節**：
>    - 查閱 [`app/lib/library/sqlite_library_repository.dart:880-887`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/library/sqlite_library_repository.dart#L880-L887)，`content_index_status` 表 Schema 如下：
>      ```sql
>      CREATE TABLE content_index_status (
>        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
>        status TEXT NOT NULL DEFAULT 'pending',
>        last_chapter_index INTEGER,
>        updated_at INTEGER NOT NULL,
>        error_message TEXT
>      )
>      ```
>      該表 Primary Key 為 `book_id`，**完全沒有 `category` 欄位**。
>    - 但 `issues.md` 擬定的介面中，`markPending`、`markDone`、`markError`、`markUnsupported`、`isTracked` 全數要求傳入 `ContentIndexCategory category`。
>    - 在單書操作中，`bookId` 已是全域唯一鍵；`ContentIndexingScheduler._isStillTracked(bookId)`（見 [`content_indexing_scheduler.dart:270`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/search/content_indexing_scheduler.dart#L270)）僅憑 `bookId` 查詢。強制要求傳入 `category` 不僅無用，更強迫排程器額外由 `book.format` 推導 category，造成反向耦合。
> 2. **進度更新行為混淆**：
>    - `markIndexing` 簽章帶有 `{required int lastChapterIndex}`。
>    - 然而在 [`content_indexing_scheduler.dart:158-163`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/search/content_indexing_scheduler.dart#L158)，排程器一開始進入 `_processOneBook` 時，是將 status 改為 `indexing`（此時章節尚未處理完畢，維持原本游標）；每完成一個章節 `flushPendingChapter`（line 185）時才更新 `last_chapter_index`。兩者應拆分為 `markIndexing(bookId)` 與 `updateProgress(bookId, chapterIndex)`，或使 `lastChapterIndex` 為選填。
> 3. **批次操作 SQL 遺漏**：
>    - 驗收標準宣稱「兩個檔案內不再出現手寫的 `content_index_status` UPDATE/INSERT/DELETE SQL」。
>    - 但 [`full_text_search_settings_repository.dart:174-218`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/search/full_text_search_settings_repository.dart#L174) 中包含兩組關鍵的批次 SQL：
>      - `_backfillPending(category)`：透過 `INSERT INTO content_index_status ... SELECT ... FROM books LEFT JOIN content_index_status ...` 高效回填。
>      - `_clearIndexData(category)`：透過 `DELETE FROM content_index_status WHERE book_id IN (SELECT id FROM books WHERE ...)` 批次清除。
>    - `issues.md` 僅規劃了 `clearForBooks(Iterable<String> bookIds, ContentIndexCategory category)`，若無 category 層級的批次方法，`SqliteFullTextSearchSettingsRepository` 必須先將所有書本 ID 查出至記憶體，嚴重違反效能與既有交易設計。
>
> **修訂建議：**
> 1. 精簡單書操作簽章，移除無意義的 `category` 參數；拆分章節進度更新：
>    ```dart
>    class ContentIndexStatusStore {
>      ContentIndexStatusStore(DatabaseExecutor db); // 支援 Database 或 Transaction
>      Future<void> markPending(String bookId);
>      Future<void> markIndexing(String bookId);
>      Future<void> updateProgress(String bookId, int lastChapterIndex);
>      Future<void> markDone(String bookId);
>      Future<void> markError(String bookId, {required String error});
>      Future<void> markUnsupported(String bookId);
>      Future<bool> isTracked(String bookId);
>      Future<void> deleteForBook(String bookId);
>      Future<void> clearByCategory(ContentIndexCategory category);
>      Future<void> backfillPending(ContentIndexCategory category);
>    }
>    ```
> 2. 支援 `DatabaseExecutor`，讓 `SqliteFullTextSearchSettingsRepository` 的雙表交易（`book_content_index` + `content_index_status`）能無縫整合。

---

> [!WARNING]
> **I-3. Issue 1 函式命名與回傳型別弱化：名為 Route 卻回傳 Widget，且失去 ReaderScreen 強型別**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/issues.md:28-44`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md#L28-L44)
>
> **問題描述與證據：**
> 1. `issues.md` 定義函式簽章為：
>    ```dart
>    Widget buildReaderScreenRoute({ ... })
>    ```
> 2. **Flutter 語意與命名不一致**：
>    - 在 Flutter 命名慣例中，結尾為 `...Route` 的工廠或建構子（例如 `MaterialPageRoute`）應回傳 `Route<T>`。
>    - 此函式內部實質是建構 `ReaderScreen` widget，回傳型別卻寫 `Widget`。呼叫端（`library_screen.dart:434`、`library_search_screen.dart:153`、`book_search_screen.dart:148`）依然要手寫重複的 `MaterialPageRoute(builder: (_) => ...)`。
> 3. **弱化單元測試型別檢查**：
>    - 單元測試要求「斷言回傳的 `ReaderScreen` 實例上每一個欄位都正確帶入」。
>    - 若簽章回傳抽象 `Widget`，測試案例必須手動執行 `as ReaderScreen` 向下轉型才能存取 `widget.bookTitle` 等欄位。
>
> **修訂建議：**
> - **方案 A（推薦，最貼合原意）**：直接回傳具體類別 `ReaderScreen`，並更名為 `buildReaderScreen`：
>   ```dart
>   ReaderScreen buildReaderScreen({
>     required Book book,
>     required ReaderPrefsManager prefsManager,
>     required LibraryReaderFeatureRepositories features,
>     required LibrarySyncDependencies sync,
>     required LibraryRepository libraryRepository,
>     required bool isEinkMode,
>     ReaderJumpTarget? initialJumpTarget,
>   })
>   ```
>   單元測試可直接享有編譯期強型別檢查；呼叫端寫法為 `MaterialPageRoute(builder: (_) => buildReaderScreen(...))`。
> - **方案 B（若真要收斂 Route）**：函式回傳 `Route<void>`（即封裝 `MaterialPageRoute`），另行提供 `buildReaderScreen` 供測試對帳。

---

### Minor（次要優化與細節校正）

> [!NOTE]
> **M-1. Issue 4 `HighlightSegment` 需補齊值物件相等性 (`operator ==`)，且純函式不可作為私有函式**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/issues.md:145-159`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md#L145-L159)
>
> **問題描述與建議：**
> 1. `HighlightSegment` 若宣告為普通 class 且未覆寫 `operator ==` 與 `hashCode`，則在 `test/search/highlight_segments_test.dart` 執行清單斷言 `expect(segments, [HighlightSegment('a', true)])` 時，會因記憶體參照不同而失敗。
> 2. `issues.md` 提到「新增純函式（放 `book_search_screen.dart` 同檔案內私有函式，或抽到 `app/lib/search/highlight_segments.dart`）」。若設為私有函式（`_splitHighlightSegments`），外部獨立單元測試將無法引用。
> 3. **建議**：明確規定抽取至 `app/lib/search/highlight_segments.dart`，宣告為公開頂層函式，並為 `HighlightSegment` 實作 `@immutable` 與 `operator ==` / `hashCode`（或 Dart 3 Record `({String text, bool isMatch})`）。

---

> [!NOTE]
> **M-2. Issue 5 `FullTextSearchTogglesController` 需明確規範可空依賴處置與狀態響應方式**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/issues.md:185-195`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md#L185-L195)
>
> **問題描述與建議：**
> 1. 查閱 [`library_search_screen.dart:497`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/library_search_screen.dart#L497) 與 [`settings_scaffold.dart:67`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/settings_scaffold.dart#L67)，呼叫端的 `repository` 均為可空型別（`FullTextSearchSettingsRepository?`）。
> 2. Issue 5 建構子宣告為 `FullTextSearchTogglesController(FullTextSearchSettingsRepository repository)`（非空），需在 Solution 明確指引：是 controller 接收可空 repository（為 null 時 `load()`/`toggle()` 自動 no-op），抑或由 Widget 於 `repository != null` 時才建構。
> 3. 建議釐清 controller 是單純資料載體（呼叫端手動 `setState`），還是繼承 `ChangeNotifier`。考量確認 Dialog 留在 Widget 端且改動量極小，維持純資料物件搭配 `await controller.toggle(); if (mounted) setState((){});` 是最乾淨的做法，宜於工單載明。

---

> [!NOTE]
> **M-3. `epic.md` 檔案目錄路徑宜精準標註**
>
> **文件位置：**
> - [`docs/epics/epic-41-search-architecture-hardening/epic.md:9`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/epic.md#L9)
>
> **問題描述與建議：**
> `epic.md` line 9 列出範圍「`app/lib/search/*`、`library_search_screen.dart`、`book_search_screen.dart`、`reader_jump_target.dart`」。其中後三者實際路徑分別位於 `app/lib/screens/` 與 `app/lib/reader/`，標註完整路徑更有助於未參與過 epic-10 的代理人快速定位。

---

## 4. 後續建議與行動指南 (Next Steps)

1. **依據本報告修訂 `issues.md`**：
   - **I-1**：修正 `ReaderJumpTarget.applyTo()` 為同步方法、使用正確公開 Key 型別、回傳 `bool` 旗標以串接高亮清除計時器。
   - **I-2**：清理 `ContentIndexStatusStore` 的無效 `category` 參數，補齊 `backfillPending` 與 `clearByCategory` 批次方法，支援 `DatabaseExecutor`。
   - **I-3**：將 `buildReaderScreenRoute` 命名與型別收斂為 `ReaderScreen buildReaderScreen({ ... })`。
   - **M-1 ~ M-3**：補強 `HighlightSegment` 相等性說明與檔案配置。
2. **推進實作流程**：
   - 完成修訂後，即可依依賴圖開始認領工單：
     - **第一條線**：撰寫 `plans/plan-issue-1.md` → 實作 Issue 1 → 接著推進 Issue 3。
     - **平行線**：Issue 2、Issue 4、Issue 5 可隨時平行開工。
     - **維持暫緩**：Issue 6 維持 `needs-info`。
