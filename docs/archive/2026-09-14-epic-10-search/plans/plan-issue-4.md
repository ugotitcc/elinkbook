# Epic 10 Issue 4：全庫搜尋畫面（`LibrarySearchScreen`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付使用者實際操作全文檢索的畫面本身——書架快速過濾欄位下方的入口、`LibrarySearchScreen` 獨立搜尋輸入框（300ms debounce）、「書名/作者匹配」與「內容匹配」兩區呈現、依兩個「啟用全文檢索」開關狀態顯示精確引導文案，以及 AppBar 常駐設定選單（雙入口之二，與 Issue 3 的系統設定入口共用同一個 `FullTextSearchSettingsRepository` 實例）。

**Architecture：** 新增 `SearchRepository` 抽象介面＋`SqliteSearchRepository` 實作（直接對 `Database` 下 SQL，比照 `SqliteFullTextSearchSettingsRepository` 既有慣例，不經 `LibraryRepository`）；新增 `app/lib/screens/library_search_screen.dart`，內含 `LibrarySearchScreen`（StatefulWidget，搜尋欄＋debounce＋結果呈現＋點擊開書）與私有的 `_FullTextSearchQuickSettingsPanel`（AppBar 常駐設定選單內容，獨立實作、不重用 `SettingsScaffold` 內部私有元件，避免 `AdaptiveShellScaffold` 的 `IndexedStack` 讓兩者同時掛載時 `Key` 衝突）；`library_screen.dart` 新增一個固定黏著於快速過濾欄位下方的入口 banner；依既有 `LibraryReaderFeatureRepositories` 依賴注入模式新增 `searchRepository` 欄位，`main.dart` 組裝正式實例。

**Tech Stack：** Flutter/Dart、`sqflite`（`sqflite_common_ffi` 供測試）。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §5（全庫搜尋畫面，本計畫的唯一技術事實來源）、§4（`FullTextSearchSettingsRepository`／`ContentIndexCategory`，Issue 3 已交付，本計畫只消費不修改）；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 4；`DESIGN.md` §18（E-Ink 適配指引，離散分頁／零轉場）。

## Global Constraints

**本計畫已經過一輪計畫審查修訂**（`reviews/review-plan-issue-4.md`，🔴 Changes Requested，1 Critical／5 Important／4 Minor）：C-1（`_buildResults` 全空短路判斷讓引導卡片與 Task 2 四個測試永遠無法命中）、I-1（Task 2 測試 `wrap` 缺少 `resolveThemeData` 導致 `BookCover` 強制解包 `ElinkTokens` 拋例外）、I-2（`searchContent()` 二次查詢 `books WHERE id IN (?)` 在 Android 11 系統 SQLite 3.28.0 下有 999 變數上限崩潰風險）、I-3（快速設定選單關閉後未重新查詢，畫面殘留過期結果）、I-4（片段截斷固定取前 80 字元，關鍵字可能落在片段外）、I-5（計畫原版單方面剔除 spec.md §5／issues.md 明定的 E-Ink 離散分頁要求）、M-1（`_openLibrarySearchScreen` 未於返回時重新整理書籍清單）、M-2（多選模式下入口未停用）、M-3（`searchTitleAuthor` 未跳脫 LIKE 萬用字元）、M-4（`searchContent` 缺少 SQLite 例外防禦）全數查證屬實並採納修訂，逐項體現在下方對應 Task 內。執行者不需要另外重讀審查報告，所有修訂已內嵌為對應程式碼片段與行內註解。

- **依賴已滿足**：Issue 1（`content_index_status`/`book_content_index`/`book_content_fts` 索引資料管線）與 Issue 3（`FullTextSearchSettingsRepository`／`ContentIndexCategory`／`showFullTextSearchEnableConfirmDialog()`）皆已完成並合併。本計畫**不依賴** Issue 2（CBZ/DRM/下載邊界情況不影響本畫面能否運作，見 issues.md 依賴圖說明）。
- **不建立 `ReaderScreen.initialJumpTarget`／暫態高亮（Issue 5 範圍）**：本計畫「點擊搜尋結果開書」一律走 `ReaderScreen` 既有一般開書路徑（無精確定位、無暫態高亮），`ContentMatchSnippet.locator` 欄位本身仍會回傳，供 Issue 5 之後接手時直接讀取，不需要重新設計介面。
- **不修改 `settings_scaffold.dart`／`full_text_search_confirm_dialog.dart`**：AppBar 常駐設定選單是**獨立**的私有 widget（`_FullTextSearchQuickSettingsPanel`，位於 `library_search_screen.dart` 內），與 `SettingsScaffold`「閱讀」分區的兩個開關 UI **各自獨立實作、獨立的 `Key` 前綴**（`library_search_full_text_search_*` vs. `settings_full_text_search_*`）。原因：`AdaptiveShellScaffold` 用 `IndexedStack` 讓 `SettingsScaffold` 全程保持掛載（不會因為切到書架分頁而被銷毀），若兩個入口共用相同的 `Key`，`LibrarySearchScreen` 以 `Navigator.push` 疊加在最上層時，`find.byKey()`／`tester.tap()` 會因為畫面樹中同時存在兩個相同 `Key` 的 widget 而產生歧義甚至測試失敗。兩者共用的是**同一個 `FullTextSearchSettingsRepository` 執行期實例**與**同一個 `showFullTextSearchEnableConfirmDialog()` 純函式**（真正的狀態持久化與確認對話框皆為單一事實來源，不重複實作），只有 UI 呈現本身是兩份獨立、精簡的程式碼——這是唯一的重複，且刻意如此（詳見上一段理由），不是疏漏。
- **`SearchRepository.searchContent()` 對 FTS5 不可用裝置的防呆責任在呼叫端，不在 repository 本身**：Issue 6 的 `isFullTextSearchAvailable == false` 代表該裝置系統 SQLite 沒有 FTS5 模組、`book_content_fts` 虛擬表根本不存在；若直接對它下 `MATCH` 查詢會拋出 `no such table` 例外。`LibrarySearchScreen._runSearch()` 在呼叫 `searchContent()` 前先檢查 `readerFeatureRepositories.isFullTextSearchAvailable`，為 `false` 時直接以 `const []` 代替、完全不呼叫 repository 方法——比照 `SqliteFullTextSearchSettingsRepository` 本身也不在內部檢查這面旗標的既有分工方式（該旗標的检查責任已經統一收斂在 UI 呼叫端）。
- **`searchContent()` 改為單一 JOIN 查詢，不再分兩次查詢（`review-plan-issue-4.md` I-2，推翻原計畫第一版設計）**：原計畫第一版先查 `book_content_fts`/`book_content_index` 取得命中的 `book_id` 集合，再對 `books` 下第二次 `WHERE id IN (?, ?, ...)` 查詢——Android 11 系統 SQLite 3.28.0（低於 3.32.0）的 `SQLITE_MAX_VARIABLE_NUMBER` 硬性上限為 999，本專案明訂支援 1,000 本書規模，一個高頻詞在全庫命中超過 999 個相異 `book_id` 時會直接拋出 `too many SQL variables` 例外，讓搜尋功能在真實大型書庫上崩潰；且兩次查詢之間並非同一交易，理論上存在「內容匹配查到某 `book_id`、隨後查 `books` 時該書已被刪除」的競態。修訂為單一查詢直接 `JOIN books`（見 Task 1），徹底消除變數上限與競態兩個問題，`SqliteSearchRepository` 因此不再需要「防禦性跳過查不到書籍的 book_id」這段程式碼（單一查詢下這個情境不可能發生）。
- **`searchContent()` 內容匹配片段改為「以查詢字串為中心」截斷，不再固定從頭截斷（`review-plan-issue-4.md` I-4）**：原計畫第一版 `_truncate(text)` 固定取 `raw_text` 前 80 個 rune，若命中的關鍵字出現在句子中後段（EPUB/PDF 段落超過 80 字相當常見），使用者在結果卡片看到的片段將完全不含其輸入的關鍵字，破壞可用性。修訂為 `_truncate(text, query)`：用 `String.indexOf()` 定位（未經 `tokenizeForQuery()` 轉換的）原始查詢字串在 `raw_text` 中的位置，以此為中心取前 20、後 60（總長仍是 80）個 rune 的視窗，找不到時（理論上不會發生，`token_text`/`raw_text` 字元序列一致，但輸入型態多樣不假設一定找得到）才退回從頭截斷的保底邏輯。
- **`searchTitleAuthor()` 跳脫 LIKE 萬用字元（`review-plan-issue-4.md` M-3）**：使用者輸入若包含 `%` 或 `_`，SQLite 預設會將其視為 LIKE 萬用字元（例如輸入單一 `%` 會比對到全部書籍），與「搜尋一段書名/作者文字」的直覺不符。修訂為跳脫查詢字串中的 `\`、`%`、`_` 三個字元並加上 `ESCAPE '\'` 子句。
- **`searchContent()` 加上 SQLite 例外的最小防禦（`review-plan-issue-4.md` M-4）**：`tokenizeForQuery()` 已用雙引號包裝並跳脫內部雙引號，正常輸入下不會產生語法無效的 FTS5 `MATCH` 字串，但無法窮舉所有邊界輸入；`rawQuery()` 呼叫外包一層 `try { } on DatabaseException { return const []; }`，避免底層真的拋出語法例外時讓整個搜尋畫面閃退——這是唯一一處例外處理，不是全面性的防禦性程式設計（`CLAUDE.md`「不要為不可能發生的情境寫防禦」——這裡是「無法窮舉但確實可能」而非「不可能」，見上方說明）。這段 catch 分支目前沒有對應的單元測試——`tokenizeForQuery()` 的公開行為保證輸出恆為合法的 FTS5 phrase 語法，找不到能透過公開 API 觸發語法例外的合法輸入，強行構造測試等於測試一段目前無法從外部觸發的程式碼路徑，因此本計畫誠實標記為「無測試覆蓋的防禦性程式碼」，不假造一個測試。
- **分組聚合（`searchContent()` 依 `book_id` 分組）不引入 `package:collection`**：`pubspec.yaml` 目前只透過遞移依賴取得 `collection` 套件（非直接宣告），不為了一個 `groupBy()` 呼叫新增直接依賴；改用一般 `Map<String, List<ContentMatchSnippet>>` 手動分組（見 Task 1）。SQL 端額外加一個 `ORDER BY rn, score`（spec.md §5 原文範例只到 `WHERE rn <= :perBookLimit` 為止，本計畫在其基礎上補上外層排序，讓 Dart 端依「第一次出現的 `book_id` 順序」直接反映跨書相關性排序，不需要额外二次排序）。
- **`LibrarySearchScreen` 開書一律使用它自己內部的 `_openBook()`，不與 `library_screen.dart._openBook()` 共用程式碼**：兩處各自建構 `ReaderScreen` 的 15 個具名參數，是本計畫唯一的一處小型重複；刻意不抽出共用 helper——`library_screen.dart._openBook()` 是既有、已上線、已有完整測試覆蓋的程式碼，Issue 5 明確只會修改 `LibrarySearchScreen` 自己的開書呼叫點（加上 `initialJumpTarget`，見 issues.md Issue 5 Solution「`LibrarySearchScreen`（Issue 4）點擊內容匹配片段時，帶 `ReaderJumpTarget` 開啟 `ReaderScreen`」，並未提到 `library_screen.dart`），沒有未來需要同步修改兩處的理由；抽出共用 helper 反而會讓本計畫的變更面擴大到不需要碰的既有檔案（`CLAUDE.md`「Surgical Changes：Touch only what you must」）。
- **`_buildResults` 不得對「兩區皆空」提前短路（`review-plan-issue-4.md` C-1，推翻原計畫第一版設計）**：原計畫第一版在 `titleAuthorResults.isEmpty && contentResults.isEmpty` 時直接 `return` 一段「找不到符合的書籍或內容」純文字，導致預設情境（全文檢索未啟用、使用者搜尋內文詞彙時兩區皆空）下，負責顯示「請啟用全文檢索」引導卡片的 `_buildContentGuidanceCard()` 永遠沒有機會執行，直接違反 spec.md §5 與 issues.md Issue 4 單元測試要求的四種引導文案組合。修訂為：「內容匹配」分區**一律**渲染（`contentResults.isEmpty` 時交給 `_buildContentGuidanceCard()` 處理，其內部已完整涵蓋「裝置不支援」／「兩者皆開啟但無結果」／「四種開關組合引導」三層情境，見 Task 2），「書名/作者匹配」分區只在有結果時才顯示標題與清單；不再有「兩區皆空」的全域短路分支，`library_search_empty_state` 這個 Key 隨之移除（新結構下必為死碼——內容匹配區永遠會渲染某種內容）。
- **E-Ink 模式比照 spec.md §5／issues.md Issue 4 明訂要求，改用離散分頁，不得以「資料量有限」為由自行豁免（`review-plan-issue-4.md` I-5，推翻原計畫第一版判斷）**：原計畫第一版主張「本畫面資料量有限、不需要分頁」，審查指出這是計畫作者單方面剔除規格明文規定的既有需求，不是計畫階段可以自行拍板的技術決策。修訂為：`isEinkMode == true` 時，「書名/作者匹配」與「內容匹配」兩個分區**各自獨立**採用固定每頁筆數（`_kEinkResultsPerPage = 5`）＋`widgets/paging_bar.dart` 的 `PagingBar` 離散換頁，重用 `library_paging.dart` 的 `LibraryPagingCursor`（純序數管理，`clamp()`/`goToNextPage()`/`goToPreviousPage()`）；`isEinkMode == false` 時維持原設計的連續 `ListView` 捲動，不受影響。**明確標記為已知簡化，非最終定案**：`library_screen.dart._buildBookList()` 對 Grid/List 兩種檢視是用 `LayoutBuilder` 動態量測可用高度換算精確 `pageSize`（`libraryRowsForHeight()`），但那個算法假設同一區塊內所有列高度一致；本畫面「內容匹配」區塊每張卡片的高度隨命中片段筆數（1-3 筆）而異，要比照那套算法做到「每頁精確填滿可用高度、不多不少」需要更大的工程量，超出本次計畫範圍。改採固定值 `5`（保守估計，正常情況下該筆數的內容能在多數手機螢幕上完整顯示，不強制保證零溢位），若之後真機測試發現特定螢幕尺寸下仍有溢位，應另開工單比照 `library_screen.dart` 的動態量測方案補強——這是本計畫**唯一**保留的已知技術債，不是對規格要求的迴避（與原計畫第一版「不需要分頁」的定性不同：這次是「用簡化但確實存在的方式滿足需求」，不是「不做」）。
- **引導卡片文案的四種組合（issues.md Issue 4 單元測試要求逐字列出）**：兩者皆關閉 → 通用引導；只開 PDF → 「已啟用『PDF』全文檢索，其他格式尚未啟用」；只開其他格式 → 「已啟用『其他格式』全文檢索，PDF 內容尚未啟用」（spec.md §5 原文字面範例）；兩者皆開啟 → 不顯示引導卡片，`_contentResults` 為空時顯示中性的「查無符合的書內內容」純文字（無關設定，屬於真的沒有命中，spec.md 未要求特殊文案，取一個中性用語）。
- **`isFullTextSearchAvailable == false`（Issue 6 裝置不支援 FTS5）時的引導卡片**優先於上述四組合判斷，固定顯示「本裝置不支援全文檢索」，不再顯示兩個開關相關文案。
- **請求世代（generation）防呆**：`_runSearch()` 為非同步（兩次 repository 呼叫皆為 `Future`），使用者可能在前一次查詢的 `Future` resolve 前就修改了輸入框內容並觸發下一次查詢；用遞增的 `_searchRequestId` 比對，避免較早送出、較晚 resolve 的查詢結果覆蓋掉使用者已經看到的新結果。
- **快速設定選單關閉後，若目前有查詢字串需重新查詢一次（`review-plan-issue-4.md` I-3）**：使用者可能在 AppBar 常駐設定選單裡切換了開關（依 spec.md §4 立即清除/回填該分類索引資料）或按下「重建索引」，`_openQuickSettingsSheet()` 原本只在選單關閉後重新載入兩個布林值供引導卡片判斷，未連帶重新執行 `_runSearch()`，會讓畫面殘留切換前查到的過期內容匹配結果。修訂為：選單關閉後，若 `_controller.text.trim()` 非空，額外呼叫一次 `_runSearch()`（見 Task 3）。
- **`_openLibrarySearchScreen()` 返回時重新整理書籍清單（`review-plan-issue-4.md` M-1）**：比照 `library_screen.dart._openBook()` 既有 `.then((_) => _bookListController.loadBooks())` 慣例——使用者可能從全庫搜尋畫面點進 `ReaderScreen` 閱讀後才返回書架，若不重新整理，`_bookListController` 持有的書籍清單快照會殘留舊的閱讀進度/排序（見 Task 4）。
- **多選模式下「搜尋書本內容」入口停用（`review-plan-issue-4.md` M-2）**：`_inSelectionMode == true` 時（使用者長按書籍進入批次選取），入口點擊會意外中斷選取操作並跳轉畫面，比照既有 `_ContinueReadingRow`／`_GroupGridTile` 等元件在選取模式下一律停用互動的既有慣例，`available` 判斷新增 `&& !_inSelectionMode`（見 Task 4）。
- **所有新增程式碼註解使用正體中文（zh-TW）**，比照全專案既有慣例。

---

## 檔案結構總覽

- **Create：** `app/lib/search/search_repository.dart` — `ContentMatchSnippet`／`BookContentMatches`／`SearchRepository`（抽象介面）／`SqliteSearchRepository`（實作）。
- **Create：** `app/test/search/search_repository_test.dart`
- **Create：** `app/test/support/fake_search_repository.dart`
- **Create：** `app/lib/screens/library_search_screen.dart` — `LibrarySearchScreen`＋私有 `_FullTextSearchQuickSettingsPanel`。
- **Create：** `app/test/screens/library_search_screen_test.dart`
- **Modify：** `app/lib/screens/library_screen_dependencies.dart` — `LibraryReaderFeatureRepositories` 新增 `searchRepository` 欄位。
- **Modify：** `app/lib/screens/library_screen.dart` — 新增「搜尋書本內容」入口 banner。
- **Modify：** `app/test/screens/library_screen_test.dart` — 新增入口連結測試。
- **Modify：** `app/lib/main.dart` — 組裝 `SqliteSearchRepository` 正式實例並貫穿依賴注入鏈。

---

### Task 1：`SearchRepository`＋`SqliteSearchRepository`

**Files：**
- Create: `app/lib/search/search_repository.dart`
- Test: `app/test/search/search_repository_test.dart`

**Interfaces：**
- Consumes：既有 `books`／`book_content_index`／`book_content_fts` schema（Issue 0）、`cjk_tokenizer.dart` 的 `tokenizeForQuery()`、`Book.fromMap()`。
- Produces：
  ```dart
  class ContentMatchSnippet {
    final String snippet;
    final String locator;
    const ContentMatchSnippet({required this.snippet, required this.locator});
  }

  class BookContentMatches {
    final Book book;
    final List<ContentMatchSnippet> matches;
    const BookContentMatches({required this.book, required this.matches});
  }

  abstract class SearchRepository {
    Future<List<Book>> searchTitleAuthor(String query);
    Future<List<BookContentMatches>> searchContent(String query, {int perBookLimit = 3});
  }
  ```
  供 Task 2 的 `LibrarySearchScreen` 與 Task 4 的 `main.dart`/`LibraryReaderFeatureRepositories` 使用。

- [ ] **Step 1：寫一組會失敗的測試**

建立 `app/test/search/search_repository_test.dart`：

```dart
// app/test/search/search_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';
import 'package:elinkbook/search/search_repository.dart';

Book _book(
  String id, {
  String title = '測試書',
  String? author,
  DateTime? lastReadTime,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: lastReadTime ?? DateTime(2026, 1, 1),
  );
}

void main() {
  late SqliteLibraryRepository repository;
  late SqliteSearchRepository searchRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    searchRepository = SqliteSearchRepository(database: repository.database);
  });

  tearDown(() async {
    await repository.close();
  });

  Future<void> insertContentRow(
    String bookId,
    String rawText, {
    int chapterIndex = 0,
    String locator = 'epubcfi(/6/2)',
  }) async {
    await repository.database.insert('book_content_index', {
      'id': const Uuid().v4(),
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'locator': locator,
      'raw_text': rawText,
      'token_text': tokenizeForIndex(rawText),
      'created_at': 1000,
    });
  }

  group('searchTitleAuthor', () {
    test('空字串（或僅空白）回傳空陣列，不下 SQL 查詢', () async {
      final results = await searchRepository.searchTitleAuthor('   ');
      expect(results, isEmpty);
    });

    test('比對書名或作者（不分大小寫），依 lastReadTime 新到舊排序', () async {
      await repository.insertBook(
        _book('b1', title: '龍族', lastReadTime: DateTime(2026, 1, 1)),
      );
      await repository.insertBook(
        _book(
          'b2',
          title: 'Dune',
          author: 'Frank Herbert',
          lastReadTime: DateTime(2026, 3, 1),
        ),
      );
      await repository.insertBook(
        _book(
          'b3',
          title: '三體',
          author: '劉慈欣',
          lastReadTime: DateTime(2026, 2, 1),
        ),
      );

      final byTitle = await searchRepository.searchTitleAuthor('dune');
      expect(byTitle.map((b) => b.id).toList(), ['b2']);

      final byAuthor = await searchRepository.searchTitleAuthor('劉慈欣');
      expect(byAuthor.map((b) => b.id).toList(), ['b3']);
    });

    test('查詢字串含 % 或 _ 時視為一般字元比對，不當作 LIKE 萬用字元（review-plan-issue-4.md M-3）',
        () async {
      await repository.insertBook(_book('b1', title: '完全不相關的書名'));
      await repository.insertBook(_book('b2', title: '100%達成'));

      final results = await searchRepository.searchTitleAuthor('100%');

      expect(results.map((b) => b.id).toList(), ['b2']);
    });
  });

  group('searchContent', () {
    test('空字串（token 化後為空）回傳空陣列，不下 MATCH 查詢', () async {
      final results = await searchRepository.searchContent('   ');
      expect(results, isEmpty);
    });

    test('依 book_id 分組，每本書最多回傳 perBookLimit 筆，未命中的書不出現在結果中', () async {
      await repository.insertBook(_book('b1', title: '書一'));
      await repository.insertBook(_book('b2', title: '書二'));
      await insertContentRow('b1', '第一段落含關鍵詞測試');
      await insertContentRow('b1', '第二段落也含關鍵詞測試');
      await insertContentRow('b1', '第三段落一樣含關鍵詞測試');
      await insertContentRow('b1', '第四段落又出現關鍵詞測試');
      await insertContentRow('b2', '完全不相關的內容');

      final results = await searchRepository.searchContent(
        '關鍵詞測試',
        perBookLimit: 3,
      );

      expect(results, hasLength(1));
      expect(results.single.book.id, 'b1');
      expect(results.single.matches, hasLength(3));
    });

    test('顯示片段回傳原始文字（未逐字加空白，token_text 只用於索引比對）', () async {
      await repository.insertBook(_book('b1'));
      await insertContentRow('b1', '這是一句包含搜尋關鍵字的句子');

      final results = await searchRepository.searchContent('搜尋關鍵字');

      expect(results.single.matches.single.snippet, '這是一句包含搜尋關鍵字的句子');
      expect(results.single.matches.single.locator, 'epubcfi(/6/2)');
    });

    test('查無命中時回傳空陣列', () async {
      await repository.insertBook(_book('b1'));
      await insertContentRow('b1', '完全不相關的內容');

      final results = await searchRepository.searchContent('不存在的詞彙');

      expect(results, isEmpty);
    });
  });
}
```

- [ ] **Step 2：執行測試，確認因 `search_repository.dart` 不存在而失敗**

Run: `flutter test test/search/search_repository_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/search/search_repository.dart'`）

- [ ] **Step 3：實作 `search_repository.dart`**

```dart
// app/lib/search/search_repository.dart
import 'package:sqflite/sqflite.dart';

import '../library/models/book.dart';
import 'cjk_tokenizer.dart';

/// 全庫搜尋「內容匹配」單一可跳轉片段（epic-10-search Issue 4，見
/// spec.md §5）。[snippet] 為 `raw_text` 的顯示片段（可能截斷加省略號，
/// 不做關鍵字加粗以外的處理）；[locator] 原樣透傳
/// `book_content_index.locator`，開書跳轉用（本工單只保留欄位本身，真正
/// 用於精確定位是 Issue 5 的範圍）。
class ContentMatchSnippet {
  final String snippet;
  final String locator;

  const ContentMatchSnippet({required this.snippet, required this.locator});
}

/// 一本書底下的內容匹配結果（spec.md §5），[matches] 長度不超過查詢時傳入
/// 的 `perBookLimit`。不重複攜帶 [book] 多份。
class BookContentMatches {
  final Book book;
  final List<ContentMatchSnippet> matches;

  const BookContentMatches({required this.book, required this.matches});
}

/// 全庫搜尋的資料存取層（epic-10-search Issue 4，spec.md §5）：書名/作者
/// 匹配與書內內容匹配是兩條完全獨立的查詢路徑——前者永遠可用（不經
/// FTS5，不受「啟用全文檢索」開關影響），後者依賴 Issue 0/1 建立的
/// `book_content_index`/`book_content_fts` 索引資料是否存在。
abstract class SearchRepository {
  Future<List<Book>> searchTitleAuthor(String query);

  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  });
}

/// [SearchRepository] 正式實作：直接對 [Database] 下 SQL（比照
/// `SqliteFullTextSearchSettingsRepository` 既有慣例，不經
/// `LibraryRepository` 介面）。
class SqliteSearchRepository implements SearchRepository {
  const SqliteSearchRepository({required Database database})
      : _database = database;

  final Database _database;

  /// 顯示片段的最大字元數（依 rune 計算，CJK 安全），超過則截斷並加上刪
  /// 節號（spec.md §5：「可能截斷加省略號」，未指定確切長度，取一個能在
  /// 手機寬度下顯示約 2-3 行的實用值）。
  static const _maxSnippetRunes = 80;

  /// 【審查修正 I-4】片段視窗中，命中關鍵字前方保留的字元數——關鍵字
  /// 置中而非固定從頭截斷，避免關鍵字出現在句子後段時完全落在片段外。
  static const _snippetContextBeforeRunes = 20;

  @override
  Future<List<Book>> searchTitleAuthor(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // 【審查修正 M-3】跳脫 LIKE 萬用字元 `%`／`_`（先跳脫反斜線本身，避免
    // 跳脫序列彼此汙染），否則使用者輸入的 `%` 會被當成萬用字元比對到
    // 全部書籍。
    final escaped = trimmed
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await _database.query(
      'books',
      where: "title LIKE ? ESCAPE '\\' OR author LIKE ? ESCAPE '\\'",
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: 'lastReadTime DESC',
    );
    return rows.map(Book.fromMap).toList();
  }

  @override
  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  }) async {
    final trimmedQuery = query.trim();
    final tokenized = tokenizeForQuery(trimmedQuery);
    if (tokenized.isEmpty) return const [];

    // 【審查修正 I-2，推翻原計畫第一版「分兩次查詢」設計】單一查詢直接
    // JOIN books 表帶出完整欄位，不再另外對 `books WHERE id IN (?, ?, ...)`
    // 下第二次查詢——Android 11 系統 SQLite 3.28.0 的
    // SQLITE_MAX_VARIABLE_NUMBER 上限是 999，千本書規模下一個高頻詞可能
    // 命中超過 999 個相異 book_id，分兩次查詢會在第二次查詢直接拋出
    // 「too many SQL variables」例外；單一查詢從根本上消除這個上限風險，
    // 也不再需要處理「兩次查詢之間書籍被刪除」的競態。外層額外加
    // `ORDER BY sub.rn, sub.score`（spec.md §5 原文範例沒有這行）——rn=1
    // 的列（每本書最佳匹配）依 bm25 分數排序，讓「第一次出現的 book_id
    // 順序」直接反映跨書相關性排序，分組本身在下方 Dart 端用一般 Map
    // 手動完成（不引入 package:collection，見本計畫 Global Constraints）。
    List<Map<String, Object?>> rows;
    try {
      rows = await _database.rawQuery('''
        SELECT b.*, sub.locator, sub.raw_text, sub.rn, sub.score
        FROM (
          SELECT bci.book_id, bci.locator, bci.raw_text,
                 bm25(book_content_fts) AS score,
                 ROW_NUMBER() OVER (
                   PARTITION BY bci.book_id
                   ORDER BY bm25(book_content_fts)
                 ) AS rn
          FROM book_content_fts
          JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
          WHERE book_content_fts MATCH ?
        ) sub
        JOIN books b ON b.id = sub.book_id
        WHERE sub.rn <= ?
        ORDER BY sub.rn, sub.score
      ''', [tokenized, perBookLimit]);
    } on DatabaseException {
      // 【審查修正 M-4】tokenizeForQuery() 保證輸出恆為合法的 FTS5 phrase
      // 語法，正常情況下不會走到這裡；無法窮舉所有邊界輸入，保留這層
      // 防禦讓極端情況下安全退回空結果，而非讓整個搜尋畫面閃退。
      return const [];
    }

    if (rows.isEmpty) return const [];

    // `b.*` 帶出 books 表全部欄位（含 `id`），`Book.fromMap()` 只讀取它
    // 需要的欄位名稱，多出的 `locator`/`raw_text`/`rn`/`score` 欄位會被
    // 忽略，不影響解析。
    final snippetsByBookId = <String, List<ContentMatchSnippet>>{};
    final booksById = <String, Book>{};
    for (final row in rows) {
      final bookId = row['id'] as String;
      booksById.putIfAbsent(bookId, () => Book.fromMap(row));
      snippetsByBookId.putIfAbsent(bookId, () => []).add(
            ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, trimmedQuery),
              locator: row['locator'] as String,
            ),
          );
    }

    return [
      for (final entry in snippetsByBookId.entries)
        BookContentMatches(book: booksById[entry.key]!, matches: entry.value),
    ];
  }

  /// 【審查修正 I-4，推翻原計畫第一版「固定從頭截斷」設計】以 [query]
  /// （未經 `tokenizeForQuery()` 轉換的原始查詢字串）在 [text] 中的位置
  /// 為中心截斷，而非固定取前 [_maxSnippetRunes] 個字元——CJK 統一表意
  /// 文字（U+4E00-U+9FFF）皆落在 UTF-16 基本多文種平面（BMP）內，
  /// `String.indexOf()` 回傳的 UTF-16 code unit 索引與 rune 索引一致，
  /// 可直接當作 rune 索引使用；`token_text` 只用於索引比對，`raw_text`
  /// 保留原始未加空白的文字序列，[query] 理論上會以連續子字串的形式
  /// 出現在 [text] 中。
  static String _truncate(String text, String query) {
    final runes = text.runes.toList();
    if (runes.length <= _maxSnippetRunes) return text;

    final matchIndex = text.toLowerCase().indexOf(query.toLowerCase());
    if (matchIndex < 0) {
      // 找不到（理論上不會發生，見上方說明，但輸入型態多樣不假設一定
      // 找得到）：退回從頭截斷的保底邏輯。
      return '${String.fromCharCodes(runes.take(_maxSnippetRunes))}…';
    }

    final windowStart =
        (matchIndex - _snippetContextBeforeRunes).clamp(0, runes.length);
    final windowEnd = (windowStart + _maxSnippetRunes).clamp(0, runes.length);
    final buffer = StringBuffer();
    if (windowStart > 0) buffer.write('…');
    buffer.write(String.fromCharCodes(runes.sublist(windowStart, windowEnd)));
    if (windowEnd < runes.length) buffer.write('…');
    return buffer.toString();
  }
}
```

- [ ] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/search/search_repository_test.dart`
Expected: PASS（全部 7 個測試）

- [ ] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/search/search_repository.dart app/test/search/search_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 SearchRepository 全庫搜尋資料存取層（Issue 4）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 2：`LibrarySearchScreen` 核心畫面（搜尋欄＋兩區結果＋點擊開書）

**Files：**
- Create: `app/lib/screens/library_search_screen.dart`
- Create: `app/test/support/fake_search_repository.dart`
- Test: `app/test/screens/library_search_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `SearchRepository`／`BookContentMatches`／`ContentMatchSnippet`；既有 `FullTextSearchSettingsRepository`／`ContentIndexCategory`（Issue 3）；既有 `LibraryReaderFeatureRepositories`／`LibrarySyncDependencies`（`library_screen_dependencies.dart`）；既有 `ReaderScreen`／`BookCover`／`EBFieldCard`／`EBSectionHeader`。
- Produces：
  ```dart
  class LibrarySearchScreen extends StatefulWidget {
    const LibrarySearchScreen({
      super.key,
      this.initialQuery = '',
      required this.searchRepository,
      required this.prefsManager,
      required this.libraryRepository,
      this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
      this.syncDependencies = const LibrarySyncDependencies(),
      this.isEinkMode = false,
    });
  }
  ```
  供 Task 3（同檔案內擴充 AppBar 設定選單）與 Task 4（`library_screen.dart` 入口 banner）建構。本 Task 交付的 AppBar 只有標題，**尚未**有設定選單按鈕（見 Task 3）。

- [ ] **Step 1：建立測試用 `FakeSearchRepository`**

```dart
// app/test/support/fake_search_repository.dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/search/search_repository.dart';

/// 供 widget test 使用的記憶體內 [SearchRepository] 假實作
/// （epic-10-search Issue 4），避免 widget test 依賴真實 sqflite（比照
/// `test/support/fake_library_repository.dart` 既有慣例）。
class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    List<Book> titleAuthorResults = const [],
    List<BookContentMatches> contentResults = const [],
  })  : _titleAuthorResults = titleAuthorResults,
        _contentResults = contentResults;

  List<Book> _titleAuthorResults;
  List<BookContentMatches> _contentResults;

  /// 記錄每次呼叫的查詢字串，供測試驗證 debounce 行為（只在延遲後觸發
  /// 一次）。
  final List<String> searchTitleAuthorCalls = [];
  final List<String> searchContentCalls = [];

  @override
  Future<List<Book>> searchTitleAuthor(String query) async {
    searchTitleAuthorCalls.add(query);
    return _titleAuthorResults;
  }

  @override
  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  }) async {
    searchContentCalls.add(query);
    return _contentResults;
  }
}
```

- [ ] **Step 2：寫一組會失敗的測試**

建立 `app/test/screens/library_search_screen_test.dart`：

```dart
// app/test/screens/library_search_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';

Book _testBook({required String id, String title = '測試書', String? author}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

void main() {
  setUpAll(() {
    // ReaderScreen.dispose() 會無條件呼叫 elinkbook/fullscreen
    // setEnabled(false)（比照 library_screen_test.dart 既有慣例）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (_) async => null,
    );
  });

  // 【審查修正 I-1】原版 `MaterialApp(home: child)` 未套用
  // `resolveThemeData()`，`ElinkTokens` 主題擴充不會被註冊，
  // `BookCover.build()` 對 `Theme.of(context).extension<ElinkTokens>()!`
  // 強制解包會直接拋出 `Null check operator used on a null value`——任何
  // 渲染出真實書籍項目（含 `BookCover`）的測試都會炸掉。比照
  // `library_screen_test.dart` 既有標準寫法補上主題。
  Widget wrap(Widget child) => MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: child,
      );

  testWidgets('輸入文字後 300ms 內未再變動才觸發搜尋查詢（防手震延遲）', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      'a',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      'ab',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      searchRepository.searchTitleAuthorCalls,
      isEmpty,
      reason: '連續輸入期間不應觸發查詢',
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(searchRepository.searchTitleAuthorCalls, ['ab']);
  });

  testWidgets('清空輸入框時立即清空結果，不等待防手震延遲', (tester) async {
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [_testBook(id: 'b1', title: '書一')],
    );
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('library_search_screen_field')),
      '',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsNothing,
    );
  });

  testWidgets('結果分「書名/作者匹配」與「內容匹配」兩區呈現', (tester) async {
    final matchedBook = _testBook(id: 'b1', title: '書一');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [matchedBook],
      contentResults: [
        BookContentMatches(
          book: matchedBook,
          matches: const [
            ContentMatchSnippet(
              snippet: '含有關鍵字的句子',
              locator: 'epubcfi(/6/2)',
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('書名/作者匹配'), findsOneWidget);
    expect(find.text('內容匹配'), findsOneWidget);
    expect(
      find.byKey(const Key('library_search_title_author_result_b1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('library_search_content_group_b1')),
      findsOneWidget,
    );
    expect(find.text('含有關鍵字的句子'), findsOneWidget);
  });

  testWidgets('兩個開關皆關閉時，內容匹配區顯示通用引導卡片', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_content_guidance_card')),
      findsOneWidget,
    );
    expect(find.text('尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）'),
        findsOneWidget);
  });

  testWidgets('只開 PDF 時，顯示「PDF 已啟用/其他格式尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「PDF」全文檢索，其他格式尚未啟用'), findsOneWidget);
  });

  testWidgets('只開其他格式時，顯示「其他格式已啟用/PDF 尚未啟用」文案', (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('已啟用「其他格式」全文檢索，PDF 內容尚未啟用'), findsOneWidget);
  });

  testWidgets('兩者皆開啟且有內容匹配結果時，顯示真實結果而非引導卡片', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_content_guidance_card')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('library_search_content_group_b1')),
      findsOneWidget,
    );
  });

  testWidgets('本裝置不支援全文檢索時，固定顯示不支援提示，不呼叫 searchContent', (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: const LibraryReaderFeatureRepositories(
          isFullTextSearchAvailable: false,
        ),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('本裝置不支援全文檢索'), findsOneWidget);
    expect(searchRepository.searchContentCalls, isEmpty);
  });

  testWidgets('點擊書名/作者匹配結果會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('點擊內容匹配片段會開啟 ReaderScreen', (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_content_snippet_b1_0')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets(
      'E-Ink 模式下，結果超過每頁固定筆數時顯示離散分頁 PagingBar（審查修正 I-5）',
      (tester) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書',
        searchRepository: FakeSearchRepository(titleAuthorResults: books),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: true,
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_title_author_paging_bar')),
      findsOneWidget,
    );
    final pagingBar = tester.widget<PagingBar>(
      find.byKey(const Key('library_search_title_author_paging_bar')),
    );
    expect(pagingBar.currentPage, 0);
    expect(pagingBar.pageCount, 2);
    expect(
      find.byKey(const Key('library_search_title_author_result_b4')),
      findsOneWidget,
      reason: '每頁固定 5 筆，第 1 頁應顯示 b0-b4',
    );
    expect(
      find.byKey(const Key('library_search_title_author_result_b5')),
      findsNothing,
      reason: '第 6 筆 (b5) 應該在第 2 頁，第 1 頁不應顯示',
    );

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    final pagingBarAfterNext = tester.widget<PagingBar>(
      find.byKey(const Key('library_search_title_author_paging_bar')),
    );
    expect(pagingBarAfterNext.currentPage, 1);
    expect(
      find.byKey(const Key('library_search_title_author_result_b5')),
      findsOneWidget,
      reason: '換頁後第 2 頁應顯示 b5-b6',
    );
  });

  testWidgets('非 E-Ink 模式（預設）結果超過分頁筆數時，不顯示 PagingBar，維持連續捲動',
      (tester) async {
    final books = [
      for (var i = 0; i < 7; i++) _testBook(id: 'b$i', title: '書$i'),
    ];
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書',
        searchRepository: FakeSearchRepository(titleAuthorResults: books),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_title_author_paging_bar')),
      findsNothing,
    );
  });
}
```

- [ ] **Step 3：執行測試，確認因 `library_search_screen.dart` 不存在而失敗**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/screens/library_search_screen.dart'`）

- [ ] **Step 4：實作 `library_search_screen.dart`（本 Task 版本，AppBar 尚無設定按鈕）**

```dart
// app/lib/screens/library_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/widgets/book_cover.dart';
import '../reader/reader_prefs_manager.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/search_repository.dart';
import 'library_paging.dart';
import 'library_screen_dependencies.dart';
import 'reader_screen.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'widgets/paging_bar.dart';

/// 全庫搜尋畫面（epic-10-search Issue 4，spec.md §5）：從 `LibraryScreen`
/// 快速過濾欄位下方的入口進入，帶入前一步關鍵字（可再修改）；結果分「書名/
/// 作者匹配」（永遠可用）與「內容匹配」（依 `SearchRepository.searchContent()`
/// 是否有索引資料而定）兩區。開書一律走一般路徑，無精確定位／暫態高亮
/// （見 Issue 5）。
class LibrarySearchScreen extends StatefulWidget {
  final String initialQuery;
  final SearchRepository searchRepository;
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final bool isEinkMode;

  const LibrarySearchScreen({
    super.key,
    this.initialQuery = '',
    required this.searchRepository,
    required this.prefsManager,
    required this.libraryRepository,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.isEinkMode = false,
  });

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  int _searchRequestId = 0;

  List<Book>? _titleAuthorResults;
  List<BookContentMatches>? _contentResults;
  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  /// 【審查修正 I-5】E-Ink 模式下「書名/作者匹配」與「內容匹配」兩區各自
  /// 獨立的離散分頁游標（見本計畫 Global Constraints 對這個已知簡化的
  /// 完整說明）。非 E-Ink 模式不使用，維持連續捲動。
  final _titleAuthorPaging = LibraryPagingCursor();
  final _contentPaging = LibraryPagingCursor();

  /// E-Ink 模式下每個分區每頁固定顯示筆數（審查修正 I-5：固定值而非動態
  /// 量測可用高度，見 Global Constraints 對這個已知簡化的說明）。
  static const _kEinkResultsPerPage = 5;

  @override
  void initState() {
    super.initState();
    _loadFullTextSearchSettings();
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFullTextSearchSettings() async {
    final repository =
        widget.readerFeatureRepositories.fullTextSearchSettingsRepository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _pdfEnabled = pdfEnabled;
      _foliateEnabled = foliateEnabled;
    });
  }

  void _handleQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _titleAuthorResults = null;
        _contentResults = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String trimmedQuery) async {
    final requestId = ++_searchRequestId;
    final isFullTextSearchAvailable =
        widget.readerFeatureRepositories.isFullTextSearchAvailable;
    final titleAuthorResults =
        await widget.searchRepository.searchTitleAuthor(trimmedQuery);
    final contentResults = isFullTextSearchAvailable
        ? await widget.searchRepository.searchContent(trimmedQuery)
        : const <BookContentMatches>[];
    // 【防止過期回應覆蓋新結果】使用者可能在前一次查詢的 Future 尚未
    // resolve 前就輸入了新關鍵字觸發下一次查詢，若不比對 requestId，先
    // 送出、較晚 resolve 的查詢會用舊結果覆蓋掉使用者已經看到的新結果。
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _titleAuthorResults = titleAuthorResults;
      _contentResults = contentResults;
      // 新一輪查詢結果到達時重置分頁，避免使用者停留在前一次查詢的
      // 第 3 頁，而新結果剛好也有超過 3 頁時，畫面卻仍卡在第 3 頁而非
      // 從第 1 頁開始瀏覽。
      _titleAuthorPaging.resetToFirstPage();
      _contentPaging.resetToFirstPage();
    });
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          prefsManager: widget.prefsManager,
          bookmarksRepository:
              widget.readerFeatureRepositories.bookmarksRepository,
          highlightsRepository:
              widget.readerFeatureRepositories.highlightsRepository,
          notesRepository: widget.readerFeatureRepositories.notesRepository,
          bookTitle: book.title,
          bookAuthor: book.author,
          bookProgress: book.progress,
          isFixedLayout: book.isFixedLayout,
          libraryRepository: widget.libraryRepository,
          customFontsRepository:
              widget.readerFeatureRepositories.customFontsRepository,
          layoutPresetRepository:
              widget.readerFeatureRepositories.layoutPresetRepository,
          bookReaderPrefsRepository:
              widget.readerFeatureRepositories.bookReaderPrefsRepository,
          syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
          ttsProvider: widget.readerFeatureRepositories.ttsProvider,
          ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
          ttsAudioFocusSource:
              widget.readerFeatureRepositories.ttsAudioFocusSource,
          isEinkMode: widget.isEinkMode,
          readerActivityTracker:
              widget.readerFeatureRepositories.readerActivityTracker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜尋書內內容'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('library_search_screen_field'),
              controller: _controller,
              autofocus: true,
              onChanged: _handleQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜尋書名、作者或書本內容...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildResults(trimmedQuery)),
        ],
      ),
    );
  }

  /// 【審查修正 C-1，推翻原計畫第一版設計】原版在「書名/作者匹配」與
  /// 「內容匹配」皆為空時提前 `return` 一段全域「找不到符合的書籍或內容」
  /// 短路訊息，導致 `_buildContentGuidanceCard()` 永遠沒有機會執行——這是
  /// 預設情境（全文檢索未啟用、使用者搜尋內文詞彙）下的必經路徑，直接
  /// 違反 spec.md §5／issues.md Issue 4 的引導卡片要求。修訂為：「內容
  /// 匹配」分區一律渲染（空結果交給 `_buildContentGuidanceCard()`，其內部
  /// 已完整涵蓋三層情境），「書名/作者匹配」分區只在有結果時才顯示標題與
  /// 清單；不再有「兩區皆空」的全域短路分支，原本的 `library_search_
  /// empty_state` Key 隨之移除（新結構下必為死碼）。
  Widget _buildResults(String trimmedQuery) {
    if (trimmedQuery.isEmpty) return const SizedBox.shrink();
    final titleAuthorResults = _titleAuthorResults;
    final contentResults = _contentResults;
    if (titleAuthorResults == null || contentResults == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      children: [
        if (titleAuthorResults.isNotEmpty) ...[
          const EBSectionHeader(title: '書名/作者匹配'),
          ..._buildSection<Book>(
            items: titleAuthorResults,
            paging: _titleAuthorPaging,
            itemBuilder: _buildTitleAuthorTile,
            pagingBarKey: 'library_search_title_author_paging_bar',
          ),
        ],
        const EBSectionHeader(title: '內容匹配'),
        if (contentResults.isEmpty)
          _buildContentGuidanceCard()
        else
          ..._buildSection<BookContentMatches>(
            items: contentResults,
            paging: _contentPaging,
            itemBuilder: _buildContentGroupCard,
            pagingBarKey: 'library_search_content_paging_bar',
          ),
      ],
    );
  }

  Widget _buildTitleAuthorTile(Book book) {
    return ListTile(
      key: Key('library_search_title_author_result_${book.id}'),
      leading: SizedBox(width: 40, height: 56, child: BookCover(book: book)),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        book.author ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _openBook(book),
    );
  }

  Widget _buildContentGroupCard(BookContentMatches group) {
    return EBFieldCard(
      key: Key('library_search_content_group_${group.book.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 40,
              height: 56,
              child: BookCover(book: group.book),
            ),
            title: Text(
              group.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              group.book.author ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var i = 0; i < group.matches.length; i++)
            ListTile(
              key: Key(
                'library_search_content_snippet_${group.book.id}_$i',
              ),
              dense: true,
              title: Text(group.matches[i].snippet),
              onTap: () => _openBook(group.book),
            ),
        ],
      ),
    );
  }

  /// 【審查修正 I-5】通用「一組項目＋（E-Ink 模式下）離散分頁列」建構器，
  /// 供「書名/作者匹配」（`items` 為 `List<Book>`）與「內容匹配」（`items`
  /// 為 `List<BookContentMatches>`）兩區共用。非 E-Ink 模式下原樣列出全部
  /// 項目、無分頁列，維持既有連續捲動體驗；E-Ink 模式下依
  /// [_kEinkResultsPerPage] 只顯示當前頁項目＋一個 [PagingBar]（見本計畫
  /// Global Constraints 對這個已知簡化的完整說明）。
  List<Widget> _buildSection<T>({
    required List<T> items,
    required LibraryPagingCursor paging,
    required Widget Function(T) itemBuilder,
    required String pagingBarKey,
  }) {
    if (!widget.isEinkMode) {
      return [for (final item in items) itemBuilder(item)];
    }
    final pageCount = paging.clamp(
      itemCount: items.length,
      pageSize: _kEinkResultsPerPage,
    );
    final safePage = paging.currentPage;
    final pageStart = safePage * _kEinkResultsPerPage;
    final pageEnd = (pageStart + _kEinkResultsPerPage).clamp(0, items.length);
    return [
      for (final item in items.sublist(pageStart, pageEnd)) itemBuilder(item),
      PagingBar(
        key: Key(pagingBarKey),
        currentPage: safePage,
        pageCount: pageCount,
        onPrevious: safePage > 0
            ? () => setState(() => paging.goToPreviousPage())
            : null,
        onNext: safePage < pageCount - 1
            ? () => setState(() => paging.goToNextPage())
            : null,
        isEinkMode: widget.isEinkMode,
      ),
    ];
  }

  Widget _buildContentGuidanceCard() {
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    if (_pdfEnabled && _foliateEnabled) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('查無符合的書內內容'),
      );
    }
    return EBFieldCard(
      key: const Key('library_search_content_guidance_card'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(_guidanceMessage()),
    );
  }

  String _guidanceMessage() {
    if (!_pdfEnabled && !_foliateEnabled) {
      return '尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）';
    }
    if (_pdfEnabled) {
      return '已啟用「PDF」全文檢索，其他格式尚未啟用';
    }
    return '已啟用「其他格式」全文檢索，PDF 內容尚未啟用';
  }
}
```

**【規劃階段查證】**「本裝置不支援全文檢索」提示（`isFullTextSearchAvailable == false`）目前用 `Padding` 而非 `EBFieldCard`，且不帶 `library_search_content_guidance_card` 這個 Key——它與四種開關組合的引導卡片是互斥的不同狀態（優先判斷），刻意給不同的視覺層級（無 Key／無卡片外框）以免測試誤判兩種狀態的 Key 重疊；上方測試已改用 `find.text('本裝置不支援全文檢索')` 斷言，不依賴 Key。

- [ ] **Step 5：執行測試，確認全數通過**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: PASS（全部 12 個測試）

- [ ] **Step 6：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_search_screen.dart app/test/screens/library_search_screen_test.dart app/test/support/fake_search_repository.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 LibrarySearchScreen 核心搜尋畫面（Issue 4）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 3：AppBar 常駐設定選單（雙入口之二＋雙入口一致性驗證）

**Files：**
- Modify: `app/lib/screens/library_search_screen.dart`
- Test: `app/test/screens/library_search_screen_test.dart`

**Interfaces：**
- Consumes：既有 `FullTextSearchSettingsRepository`／`ContentIndexCategory`／`showFullTextSearchEnableConfirmDialog()`（Issue 3）；`widgets/eb_sheet_shell.dart` 的 `EBSheetShell.show()`。
- Produces：`LibrarySearchScreen` AppBar 新增設定按鈕（`Key('library_search_screen_settings_button')`），私有 `_FullTextSearchQuickSettingsPanel` 提供兩個開關＋重建索引按鈕，供本畫面內部使用（不對外匯出）。

- [ ] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/library_search_screen_test.dart` 檔案開頭新增 import：

```dart
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
```

在 `main()` 內既有測試之後（任一位置）新增：

```dart
  testWidgets('AppBar 設定按鈕開啟全文檢索設定選單，顯示兩個開關與重建索引按鈕',
      (tester) async {
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(),
        ),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const Key('library_search_full_text_search_foliate_switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('設定選單內從關閉切成開啟，先跳出確認對話框，取消則不呼叫 setEnabled',
      (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository: repository,
        ),
      )),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_cancel')),
    );
    await tester.pumpAndSettle();

    expect(repository.setEnabledCalls, isEmpty);
    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('確認後呼叫 setEnabled(true)，重建索引按鈕由停用變為可用', (tester) async {
    final repository = FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        searchRepository: FakeSearchRepository(),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository: repository,
        ),
      )),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key(
              'library_search_full_text_search_pdf_rebuild_button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('關閉設定選單時，若目前有查詢字串則重新查詢一次，避免殘留過期結果（審查修正 I-3）',
      (tester) async {
    final searchRepository = FakeSearchRepository();
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: searchRepository,
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(),
        ),
      )),
    );
    await tester.pumpAndSettle();
    expect(searchRepository.searchTitleAuthorCalls, ['關鍵字']);

    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
    await tester.pumpAndSettle();

    expect(searchRepository.searchTitleAuthorCalls, ['關鍵字', '關鍵字']);
  });

  testWidgets(
      '雙入口一致性：SettingsScaffold 切換開關後，LibrarySearchScreen 的設定選單重新開啟時反映最新狀態',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeFullTextSearchSettingsRepository();

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        fullTextSearchSettingsRepository: repository,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('settings_full_text_search_pdf_switch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('full_text_search_enable_confirm_dialog_confirm')),
    );
    await tester.pumpAndSettle();
    expect(await repository.isEnabled(ContentIndexCategory.pdf), isTrue);

    await tester.pumpWidget(wrap(LibrarySearchScreen(
      searchRepository: FakeSearchRepository(),
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
      readerFeatureRepositories: LibraryReaderFeatureRepositories(
        fullTextSearchSettingsRepository: repository,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Switch>(find.byKey(
              const Key('library_search_full_text_search_pdf_switch')))
          .value,
      isTrue,
    );
  });
```

- [ ] **Step 2：執行測試，確認因按鈕/選單不存在而失敗**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: FAIL（找不到 `Key('library_search_screen_settings_button')`）

- [ ] **Step 3：修改 `library_search_screen.dart`**

在 import 區塊新增：

```dart
import 'full_text_search_confirm_dialog.dart';
import 'widgets/eb_sheet_shell.dart';
```

找到：

```dart
  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜尋書內內容'),
      ),
```

取代為：

```dart
  Future<void> _openQuickSettingsSheet() async {
    await EBSheetShell.show<void>(
      context,
      title: '全文檢索設定',
      isEinkMode: widget.isEinkMode,
      builder: (context) => _FullTextSearchQuickSettingsPanel(
        repository:
            widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
        isFullTextSearchAvailable:
            widget.readerFeatureRepositories.isFullTextSearchAvailable,
        isEinkMode: widget.isEinkMode,
      ),
    );
    // 使用者可能在選單裡切換了開關（依 spec.md §4 立即清除/回填該分類
    // 索引資料）或按下「重建索引」，回到搜尋畫面後不能只更新引導卡片
    // 依據的兩個布林值（審查修正 I-3）——若目前輸入框已有查詢字串且正在
    // 顯示結果，必須連帶重新查詢一次，避免畫面殘留切換前查到的過期內容
    // 匹配結果（例如使用者剛關閉 PDF 全文檢索，畫面卻還顯示著幾秒前查到
    // 的 PDF 內容片段）。
    await _loadFullTextSearchSettings();
    final trimmedQuery = _controller.text.trim();
    if (trimmedQuery.isNotEmpty) {
      await _runSearch(trimmedQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜尋書內內容'),
        actions: [
          IconButton(
            key: const Key('library_search_screen_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '全文檢索設定',
            onPressed: _openQuickSettingsSheet,
          ),
        ],
      ),
```

在檔案最末（`_LibrarySearchScreenState` 類別結束的 `}` 之後）新增：

```dart

/// AppBar「全文檢索設定」入口的面板內容（epic-10-search Issue 4，spec.md
/// §4 雙入口之二）：與 `SettingsScaffold`「閱讀」分區的兩個開關語意完全
/// 相同、共用同一個 [FullTextSearchSettingsRepository] 執行期實例，但獨立
/// 實作一份精簡版 UI、獨立的 `Key` 前綴——`AdaptiveShellScaffold` 用
/// `IndexedStack` 讓 `SettingsScaffold` 全程保持掛載，若共用 `Key`，本畫面
/// 以 `Navigator.push` 疊加在最上層時會與仍掛載中的 `SettingsScaffold`
/// 產生 `Key` 歧義（見本計畫 Global Constraints）。
class _FullTextSearchQuickSettingsPanel extends StatefulWidget {
  final FullTextSearchSettingsRepository? repository;
  final bool isFullTextSearchAvailable;
  final bool isEinkMode;

  const _FullTextSearchQuickSettingsPanel({
    required this.repository,
    required this.isFullTextSearchAvailable,
    required this.isEinkMode,
  });

  @override
  State<_FullTextSearchQuickSettingsPanel> createState() =>
      _FullTextSearchQuickSettingsPanelState();
}

class _FullTextSearchQuickSettingsPanelState
    extends State<_FullTextSearchQuickSettingsPanel> {
  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _pdfEnabled = pdfEnabled;
      _foliateEnabled = foliateEnabled;
    });
  }

  Future<void> _handleToggle(ContentIndexCategory category, bool value) async {
    final repository = widget.repository;
    if (repository == null) return;
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await repository.setEnabled(category, value);
    if (!mounted) return;
    setState(() {
      if (category == ContentIndexCategory.pdf) {
        _pdfEnabled = value;
      } else {
        _foliateEnabled = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFullTextSearchAvailable) {
      return const Padding(
        key: Key('library_search_full_text_search_unavailable_hint'),
        padding: EdgeInsets.all(16),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('PDF 全文檢索'),
            subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_pdf_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed: !_pdfEnabled || widget.repository == null
                      ? null
                      : () => widget.repository!
                          .rebuildIndex(ContentIndexCategory.pdf),
                ),
                Switch(
                  key: const Key('library_search_full_text_search_pdf_switch'),
                  value: _pdfEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.pdf, value),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('其他格式全文檢索'),
            subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_foliate_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed: !_foliateEnabled || widget.repository == null
                      ? null
                      : () => widget.repository!
                          .rebuildIndex(ContentIndexCategory.foliate),
                ),
                Switch(
                  key: const Key(
                      'library_search_full_text_search_foliate_switch'),
                  value: _foliateEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.foliate, value),
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

- [ ] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: PASS（全部 17 個測試）

- [ ] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/library_search_screen.dart app/test/screens/library_search_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(search): LibrarySearchScreen 新增 AppBar 全文檢索設定選單（Issue 4 雙入口之二）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 4：`library_screen.dart` 入口 banner＋依賴注入貫穿＋`main.dart` 組裝

**Files：**
- Modify: `app/lib/screens/library_screen_dependencies.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`
- Modify: `app/lib/main.dart`

**Interfaces：**
- Consumes：Task 1 的 `SearchRepository`／`SqliteSearchRepository`；Task 2/3 的 `LibrarySearchScreen`。
- Produces：`LibraryReaderFeatureRepositories.searchRepository`（新欄位）；`LibraryScreen` 新增 `Key('library_content_search_entry_button')` 入口。

- [ ] **Step 1：`LibraryReaderFeatureRepositories` 新增 `searchRepository` 欄位**

在 `app/lib/screens/library_screen_dependencies.dart`，於 import 區塊新增：

```dart
import '../search/search_repository.dart';
```

找到：

```dart
  /// epic-10-search Issue 6：本裝置系統 SQLite 是否有 FTS5 模組可用。
  /// `false` 時 `SettingsScaffold`「閱讀」分區顯示「本裝置不支援全文檢索」
  /// 提示取代兩個開關。預設 `true`，維持既有呼叫端的行為不變。
  final bool isFullTextSearchAvailable;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.readerActivityTracker,
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
  });
}
```

取代為：

```dart
  /// epic-10-search Issue 6：本裝置系統 SQLite 是否有 FTS5 模組可用。
  /// `false` 時 `SettingsScaffold`「閱讀」分區顯示「本裝置不支援全文檢索」
  /// 提示取代兩個開關。預設 `true`，維持既有呼叫端的行為不變。
  final bool isFullTextSearchAvailable;

  /// epic-10-search Issue 4：全庫搜尋（書名/作者 LIKE 查詢＋書內內容 FTS5
  /// 查詢）的資料存取層。`null` 時 `LibraryScreen`「搜尋書本內容」入口停用
  /// （不導覽至 `LibrarySearchScreen`）。
  final SearchRepository? searchRepository;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.readerActivityTracker,
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    this.searchRepository,
  });
}
```

- [ ] **Step 2：寫一組會失敗的測試（`library_screen.dart` 入口 banner）**

在 `app/test/screens/library_screen_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/screens/library_search_screen.dart';
import '../support/fake_search_repository.dart';
```

在 `main()` 內既有測試之後（任一位置）新增：

```dart
  testWidgets(
      '點擊「搜尋書本內容」入口，帶同一組關鍵字導航至 LibrarySearchScreen（epic-10-search Issue 4）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: FakeSearchRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_search_field')),
      '紅樓',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_content_search_entry_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
              find.byKey(const Key('library_search_screen_field')))
          .controller!
          .text,
      '紅樓',
    );
  });

  testWidgets('searchRepository 為 null 時，「搜尋書本內容」入口停用（點擊無反應）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_content_search_entry_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchScreen), findsNothing);
  });

  testWidgets('多選模式下，「搜尋書本內容」入口停用（審查修正 M-2）', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: FakeSearchRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_content_search_entry_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchScreen), findsNothing);
  });
```

- [ ] **Step 3：執行測試，確認因入口不存在而失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL（找不到 `Key('library_content_search_entry_button')`）

- [ ] **Step 4：修改 `library_screen.dart`**

在 import 區塊新增：

```dart
import 'library_search_screen.dart';
```

找到：

```dart
  void _onSearchCleared() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
```

取代為：

```dart
  void _onSearchCleared() {
    _searchController.clear();
    _onSearchChanged('');
  }

  /// 「搜尋書本內容」入口（epic-10-search Issue 4，spec.md §5）：帶入目前
  /// 書架快速過濾欄位的關鍵字，導航至 `LibrarySearchScreen`。
  /// `searchRepository` 為 `null` 時停用（`onTap: null`），比照
  /// `SettingsScaffold` 既有「功能未啟用時 onTap 傳 null」慣例
  /// （見 `settings_font_management_button`）。
  void _openLibrarySearchScreen() {
    final searchRepository = widget.readerFeatureRepositories.searchRepository;
    if (searchRepository == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LibrarySearchScreen(
              initialQuery: _searchQuery,
              searchRepository: searchRepository,
              prefsManager: widget.prefsManager,
              libraryRepository: widget.repository,
              readerFeatureRepositories: widget.readerFeatureRepositories,
              syncDependencies: widget.syncDependencies,
              isEinkMode: widget.themeDependencies.isEinkMode,
            ),
          ),
        )
        // 【審查修正 M-1】比照既有 _openBook() 慣例：使用者可能從全庫搜尋
        // 畫面點進 ReaderScreen 閱讀後才返回書架，若不重新整理，
        // _bookListController 持有的書籍清單快照會殘留舊的閱讀進度/排序。
        .then((_) => _bookListController.loadBooks());
  }

  Widget _buildContentSearchEntryBanner() {
    // 【審查修正 M-2】多選模式下停用入口——長按書籍進入批次選取後，點擊
    // 入口若仍會跳轉畫面，會意外中斷選取操作，比照 _ContinueReadingRow／
    // _GroupGridTile 等元件在選取模式下一律停用互動的既有慣例。
    final hasSearchRepository =
        widget.readerFeatureRepositories.searchRepository != null;
    final available = hasSearchRepository && !_inSelectionMode;
    return InkWell(
      key: const Key('library_content_search_entry_button'),
      onTap: available ? _openLibrarySearchScreen : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.travel_explore, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('搜尋書本內容')),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
```

找到：

```dart
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchField(),
                  Expanded(
```

取代為：

```dart
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchField(),
                  _buildContentSearchEntryBanner(),
                  Expanded(
```

- [ ] **Step 5：執行測試，確認全數通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（含既有測試與本 Task 新增的 3 個測試）

- [ ] **Step 6：`main.dart` 組裝正式實例（純組裝，不採 TDD 步驟）**

在 `app/lib/main.dart`，於 import 區塊新增：

```dart
import 'search/search_repository.dart';
```

找到：

```dart
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
```

取代為：

```dart
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
  // epic-10-search Issue 4：全庫搜尋資料存取層，直接對同一個 Database
  // 連線下 SQL（比照 fullTextSearchSettingsRepository 既有慣例）。
  final searchRepository = SqliteSearchRepository(
    database: repository.database,
  );
```

找到：

```dart
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      isFullTextSearchAvailable: repository.isFullTextSearchAvailable,
    ),
  );
}
```

取代為：

```dart
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      isFullTextSearchAvailable: repository.isFullTextSearchAvailable,
      searchRepository: searchRepository,
    ),
  );
}
```

找到（`ElinkBookApp` 欄位宣告）：

```dart
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;

  ElinkBookApp({
```

取代為：

```dart
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;

  ElinkBookApp({
```

找到（`ElinkBookApp` 建構子參數列）：

```dart
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

取代為：

```dart
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    this.searchRepository,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

找到（`_ElinkBookAppState.build()` 內 `LibraryReaderFeatureRepositories(...)` 建構）：

```dart
          fullTextSearchSettingsRepository:
              widget.fullTextSearchSettingsRepository,
          isFullTextSearchAvailable: widget.isFullTextSearchAvailable,
        ),
```

取代為：

```dart
          fullTextSearchSettingsRepository:
              widget.fullTextSearchSettingsRepository,
          isFullTextSearchAvailable: widget.isFullTextSearchAvailable,
          searchRepository: widget.searchRepository,
        ),
```

- [ ] **Step 7：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：跑本次全部異動觸及的測試檔，確認整體沒有回歸**

Run: `flutter test test/search/search_repository_test.dart test/screens/library_search_screen_test.dart test/screens/library_screen_test.dart`
Expected: PASS（`main.dart` 本身無對應測試檔，正確性已由上述測試檔涵蓋的依賴注入路徑＋`flutter analyze` 型別檢查涵蓋，比照 `plan-issue-3.md` Task 5 既有慣例）

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen_dependencies.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart app/lib/main.dart
git commit -m "$(cat <<'EOF'
feat(search): library_screen.dart 新增全庫搜尋入口，main.dart 組裝 SearchRepository（Issue 4）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

- [ ] **Step 10：（人類／執行者手動）真機或模擬器驗證**

`flutter run` 啟動 App，進入書架：
1. 快速過濾欄位下方應看到「搜尋書本內容」入口列，點擊後導航至全庫搜尋畫面，輸入框已帶入剛才在快速過濾欄位打的關鍵字。
2. 輸入書名/作者關鍵字（例如已匯入書籍的書名片段），應在「書名/作者匹配」區看到結果，點擊可正常開書。
3. 若已在 Issue 3 的設定畫面開啟過任一「啟用全文檢索」開關且背景索引已完成，輸入該書內容中確實存在的詞彙，應能在「內容匹配」區看到片段，點擊可正常開書。
4. 兩個開關皆關閉時，「內容匹配」區顯示引導卡片；點擊 AppBar 右上角設定圖示可直接在同一畫面切換開關（含確認對話框），不需要跳去系統設定。
5. 切到系統設定「閱讀」分區確認兩個開關狀態與剛才在全庫搜尋畫面看到的一致（雙入口同步）。

（本 Task 不需要跑全專案 `flutter test`——依專案既有慣例，Epic 10 尚有 Issue 5 未完成，不是本 Epic 最後一個 Issue，全套測試留到 Issue 5 收尾前再跑一次，比照 `plan-issue-3.md`／`plan-issue-6.md` 已採用的既有慣例。）

---

## 自我審查（Self-Review，計畫撰寫者執行，非另一輪審查）

**Spec 覆蓋度：** spec.md §5 逐項對應——(1) `SearchRepository`／`ContentMatchSnippet`／`BookContentMatches`／`searchTitleAuthor()`／`searchContent()`（含空查詢防呆、`bm25`/`ROW_NUMBER` 分頁限制、Dart 端分組、單一 JOIN 查詢避免 999 變數上限、關鍵字置中截斷）→ Task 1；(2) 畫面本身獨立輸入框＋300ms debounce＋帶入前一步關鍵字 → Task 2；(3) 兩區呈現（書名/作者匹配＋內容匹配，「內容匹配」分區一律渲染不再有全域短路）＋依兩個 `isEnabled(category)` 顯示精確引導文案 → Task 2；(4) AppBar 常駐設定選單（兩個開關＋各自重建索引＋關閉選單後重新查詢）→ Task 3；(5) E-Ink 模式（`Duration.zero`／零轉場透過既有 `EBSheetShell.show()`/`showFullTextSearchEnableConfirmDialog()` 繼承；結果清單離散分頁透過 `_buildSection()`＋`LibraryPagingCursor`／`PagingBar` 落實，已知簡化見 Global Constraints）→ Task 2；(6) 入口連結（`library_screen.dart` 快速過濾結果下方連結，帶同一組關鍵字，多選模式下停用）→ Task 4。issues.md Issue 4 單元測試要求三項：「`SearchRepository` 查詢正確性/空查詢邊界/每本書筆數上限」→ Task 1 測試（含 M-3 萬用字元跳脫回歸測試）；「`LibrarySearchScreen` debounce/兩區呈現/四種開關組合引導卡片」→ Task 2＋Task 3 測試（含 I-5 離散分頁、I-3 選單關閉重新查詢兩項新增測試）；「入口連結」→ Task 4 測試（含 M-2 多選模式停用回歸測試）。驗收標準「手動驗證確認搜尋一個已知存在於索引中的詞能在『內容匹配』區看到結果」→ Task 4 Step 10 人工驗證項目 3。

**Placeholder 掃描：** 無「TBD」「稍後補上」「類似 Task N」等字樣，所有程式碼片段皆為完整可直接套用的內容（含 `main.dart` 的逐段 find/replace 皆為實際既有文字，已於規劃階段逐一讀取原始檔案確認）。M-4 的 `DatabaseException` catch 分支例外——已於 Global Constraints 明確標記為「無法透過公開 API 觸發、因此無對應測試」的誠實限制，不是遺漏。

**型別一致性：** `SearchRepository`／`ContentMatchSnippet`／`BookContentMatches` 在 Task 1 定義，Task 2 的 `LibrarySearchScreen` 與 Task 4 的 `LibraryReaderFeatureRepositories`/`main.dart` 皆原樣引用，命名一致；`_truncate(text, query)` 簽章變更（審查修正 I-4）已同步反映在 Task 1 程式碼與呼叫端；`LibrarySearchScreen` 建構參數（`searchRepository`／`prefsManager`／`libraryRepository`／`readerFeatureRepositories`／`syncDependencies`／`isEinkMode`）在 Task 2 定義，Task 4 `library_screen.dart._openLibrarySearchScreen()` 呼叫端具名參數順序/型別一致；`_buildSection<T>()` 泛型輔助方法在 Task 2 定義，供「書名/作者匹配」（`T = Book`）與「內容匹配」（`T = BookContentMatches`）兩區共用，簽章一致；`_FullTextSearchQuickSettingsPanel` 建構參數在 Task 3 定義並只在同一檔案的 `_openQuickSettingsSheet()` 使用，不對外匯出；`LibraryReaderFeatureRepositories.searchRepository` 在 Task 4 Step 1 定義、Step 4／Step 6 的 `library_screen.dart`／`main.dart` 呼叫端命名一致。

**審查回應總結（`reviews/review-plan-issue-4.md`）：** C-1／I-1／I-2／I-3／I-4／I-5／M-1／M-2／M-3／M-4 共 10 項發現全數查證屬實並採納修訂，逐項體現在 Global Constraints 對應段落與 Task 1／2／3／4 的程式碼、測試、測試計數更新中，不需要另一輪計畫審查即可進入實作階段（若審查者仍希望對 I-5 的「固定值分頁」簡化方案再次確認，可在下一輪審查中針對該段落單獨覆核）。
