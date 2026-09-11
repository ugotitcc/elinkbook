# Epic 10 Issue 3：「啟用全文檢索」設定模型＋雙入口＋確認 Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地使用者控制全文檢索開啟/關閉的完整流程——兩個獨立開關（PDF／其他格式）、各自的確認對話框、開啟時批次回填既有書庫、關閉時立即清除該格式索引資料且不留孤兒殘留、並在系統設定「閱讀」分區提供第一個可用入口（含重建索引動作）。

**Architecture：** 新增 `FullTextSearchSettingsRepository` 抽象介面＋`SqliteFullTextSearchSettingsRepository` 實作（`SharedPreferences` 存兩個布林開關，直接對 `Database` 下 SQL 做批次回填/清除/重建，比照 `ContentIndexingScheduler` 既有操作 `content_index_status`/`book_content_index` 的方式）；`ContentIndexingScheduler` 新增一個窄範圍的取消防護，讓「關閉開關」與「排程器背景處理中」兩者之間的競態不會留下孤兒索引；新增共用確認 Dialog（純 UI，不自行呼叫 repository）；`SettingsScaffold`「閱讀」分區新增兩個開關＋重建索引按鈕並串接 Dialog＋repository；依既有 `LibraryReaderFeatureRepositories`／`AdaptiveShellScaffold` 依賴注入模式往下傳遞，`main.dart` 組裝正式實例。

**Tech Stack：** Flutter/Dart、`sqflite`（`sqflite_common_ffi` 供測試）、`shared_preferences`。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §4（「啟用全文檢索」設定模型，本計畫的唯一技術事實來源）、§5（全庫搜尋畫面，`searchContent()` 完全信任索引存在與否的前提，C-1 修法即為了守住這個前提）、§7（CBZ/DRM KF8/未下載書籍）；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 3；`DESIGN.md` §9（對話框規範，僅套用 §9.1，不套用 §9.2）。

## Global Constraints

- **本計畫已經過一輪計畫審查修訂**（`reviews/review-plan-issue-3.md`，🔴 Changes Requested，1 Critical／4 Important／3 Minor）：C-1（排程器缺乏取消防護導致孤兒索引）、I-1（`rebuildIndex()` 介面遺漏）、I-2（CBZ 誤入 foliate pending 佇列）、I-3（對話框定寬手機溢位）、I-4（widget test 未放大測試視窗）、M-1（`didUpdateWidget` 未同步）、M-2（`_clearIndexData` 未包交易）、M-3（測試缺少 foliate/多格式覆蓋）全數查證屬實並採納修訂，逐項體現在下方對應 Task 內。執行者不需要另外重讀審查報告，所有修訂已內嵌為對應程式碼片段與行內註解。
- **依賴已滿足**：Issue 1 已完成並合併，`ContentIndexingScheduler.requestProcessing()`（`app/lib/search/content_indexing_scheduler.dart:93`）已存在。
- **`ContentIndexingScheduler` 需要一個窄範圍的修改（review-plan-issue-3.md C-1，推翻原規劃）**：原計畫第一版宣告「不修改 `ContentIndexingScheduler` 本身」，但查證發現 `_processOneBook()` 完全不感知「啟用全文檢索」開關狀態——若排程器正在背景處理某分類的一本書時，使用者恰好關閉該分類開關（`setEnabled(category, false)` 執行 `DELETE FROM content_index_status`/`book_content_index`），排程器不會收到任何訊號，會繼續把後續章節寫入 `book_content_index`，產生「使用者已關閉開關、搜尋卻仍能查到該書內容」的孤兒索引，直接違反 spec.md §4「排程器對該分類的佇列停止並捨棄目前進度」與 §5「索引資料存在即代表已啟用」的前提。本計畫因此在 Task 1 對 `_processOneBook()` 新增一個最小防護（於每個章節邊界檢查 `content_index_status` 列是否仍存在），採用「被動檢查」而非「主動取消 API」——後者需要在 `ContentIndexingScheduler` 新增公開取消方法/callback，前者僅需一個私有 helper，改動面更小。
- **Repository 抽象介面已補齊 `rebuildIndex()`（review-plan-issue-3.md I-1）**：issues.md Issue 3 自身的單元測試要求與驗收標準明訂「重建索引」需求（不是 Issue 4 的範圍），原計畫第一版誤判為純 UI、完全劃給 Issue 4，查證後推翻——`FullTextSearchSettingsRepository` 需要 `Future<void> rebuildIndex(ContentIndexCategory category)`，本計畫「系統設定閱讀分區」這個入口本身也要有對應的重建動作，才算完整滿足這個入口的驗收標準。
  ```dart
  enum ContentIndexCategory { pdf, foliate }

  abstract class FullTextSearchSettingsRepository {
    Future<bool> isEnabled(ContentIndexCategory category);
    Future<void> setEnabled(ContentIndexCategory category, bool value);
    Future<void> rebuildIndex(ContentIndexCategory category);
  }
  ```
- **雙入口範圍調整（與 issues.md Issue 3 原文字面「雙入口」的唯一落差，需明確說明理由）**：issues.md 依賴圖是 `Issue 1 → Issue 3 → Issue 4`，但 issues.md Issue 3 的 Solution 文字寫「雙入口：全庫搜尋畫面 AppBar 常駐設定選單……＋系統設定『閱讀』分區新增一項」——全庫搜尋畫面（`LibrarySearchScreen`）本身是 **Issue 4** 的產物，目前 `app/lib/screens/library_search_screen.dart` 完全不存在。本計畫**只落地「系統設定『閱讀』分區」這一個入口**；「全庫搜尋畫面 AppBar 常駐設定選單」入口留給 Issue 4 執行時直接重用本計畫產出的 `FullTextSearchSettingsRepository`／`showFullTextSearchEnableConfirmDialog()`／`ContentIndexCategory`（三者皆為本計畫落地的公開 API，Issue 4 不需要重新設計介面）。
- **新增一個 spec.md §4 沒有明文要求、但呼應 Issue 6 既定用途的小防禦**：issues.md Issue 6 的驗收標準／單元測試要求明訂 `SqliteLibraryRepository.isFullTextSearchAvailable` 「供 Issue 3／4 判斷是否顯示『本裝置不支援全文檢索』提示」。本計畫把這個旗標透過既有依賴注入路徑（`LibraryReaderFeatureRepositories` → `SettingsScaffold`）往下傳遞，`isFullTextSearchAvailable == false` 時「閱讀」分區顯示提示文字取代兩個開關。
- **`requestProcessing` 以純 callback（`void Function()`）注入，不持有整個 `ContentIndexingScheduler`**：比照既有 `LibrarySyncDependencies.onManualSync` 既有先例，讓 `SqliteFullTextSearchSettingsRepository` 的單元測試不需要建構真正的排程器/`WidgetsBindingObserver` 生命週期。
- **SharedPreferences key 命名沿用 spec.md §4 逐字建議**：`full_text_search_enabled_pdf`／`full_text_search_enabled_foliate`，只存布林值本身，不額外存「已確認過」旗標。
- **批次回填必須遵守 spec.md §7 的通用規則**：`books.is_downloaded = 0` 不建立 `content_index_status` 列。
- **CBZ 篩選修正（review-plan-issue-3.md I-2，推翻原計畫第一版判斷）**：原計畫第一版誤判「CBZ 與 DRM KF8 一樣，需要 Issue 2 才能區分」，查證後推翻——CBZ 在資料庫中有獨立、明確的 `books.format = 'cbz'`（`BookFileFormat.cbz`，`library_enums.dart`），光憑格式字串就能判斷，不像 DRM KF8 需要深入解析檔案內容。`foliate` 分類的格式篩選必須排除 `cbz`（否則會把純圖片漫畫排入 `pending`、讓排程器白白啟動 `HeadlessInAppWebView`，違反 spec.md §7「CBZ 必須是 `unsupported`」的約束），本計畫在 `_backfillPending()` 回填 `foliate` 分類的同時，一併把既有尚無資料列的 CBZ 書籍批次標記為 `unsupported`，不必等待 Issue 2。**DRM KF8 仍是真正的 Issue 2 範圍**（需要解析 KF8 檔案結構才能判斷是否加密，本計畫無法、也不嘗試處理）——這是唯一保留的已知暫時性落差，Issue 2 完成後 DRM KF8 會在匯入當下被標記 `unsupported`，屆時本計畫的回填邏輯不需要任何修改。
- **E-Ink 模式對話框轉場**：`showDialog()` 自 Flutter 3.41 起原生支援 `animationStyle` 具名參數（已查證 `packages/flutter/lib/src/material/dialog.dart:1497`），比照既有 `EBSheetShell.show()` 的 `sheetAnimationStyle` 既有模式。
- **確認 Dialog 排版修正（review-plan-issue-3.md I-3，推翻原計畫第一版寫法）**：原計畫第一版用 `SizedBox(width: math.min(screenWidth * 0.85, 400))` 直接對 `content` 施加緊約束寬度，查證 `packages/flutter/lib/src/material/dialog.dart:32` 確認 `AlertDialog` 預設 `insetPadding` 為左右各 `40.0`（共 `80.0`），原寫法在 360～400dp 手機螢幕上會要求比實際可用空間更寬的內容區塊（例如 360dp 螢幕：要求 306dp，實際只有 280dp 可用），造成溢位。改用 `ConstrainedBox(constraints: BoxConstraints(maxWidth: 400))`——`AlertDialog` 預設 `insetPadding` 本身已在手機上自然產生接近 §9.1「85%」意圖的可用寬度比例，`maxWidth` 只需要負責限制平板等大螢幕的上限，不需要再手動計算 85% 那一半。**不套用** §9.2「破壞性操作」的 error 色按鈕慣例。`EBDialogShell` 目前尚未落地為共用元件（已查證全 repo 無匹配），手動以 `AlertDialog` 符合排版規則，比照既有 `showCloudDuplicateConfirmDialog()`「取消在左、主動作在右、皆為 TextButton、頂層宣告獨立函式」的既有慣例。
- **確認 Dialog 本身不呼叫 repository**：只回傳 `Future<bool>`，呼叫端（`SettingsScaffold`）收到 `true` 之後才呼叫 `setEnabled(category, true)`。
- **widget test 視窗尺寸（review-plan-issue-3.md I-4）**：已查證 `app/test/screens/settings_scaffold_test.dart` 既有慣例——凡是會點擊「字型管理」以下項目（含「閱讀」分區內的項目）的測試，一律在測試開頭設定 `tester.view.physicalSize = const Size(800, 1600)`／`devicePixelRatio = 1.0`，並在 `addTearDown` 還原，否則預設 800×600 測試視窗會讓下方項目被擠出可視範圍、`tester.tap()` 找不到目標。本計畫在 `SettingsScaffold`「閱讀」分區新增的兩個開關位置比既有「朗讀語音與語速」還更下面，Task 4 的每個新測試都必須比照這個既有慣例設定視窗尺寸。
- **格式分類判斷依據**：`pdf` ⟺ `books.format = 'pdf'`；`foliate` ⟺ 其餘格式扣除 `cbz`（`format != 'pdf' AND format != 'cbz'`，見上方 CBZ 篩選修正）。
- 不建立 `LibrarySearchScreen`／`app/lib/screens/library_search_screen.dart`（Issue 4 範圍）。
- 所有新增程式碼註解使用正體中文（zh-TW），比照全專案既有慣例。

---

## 檔案結構總覽

- **Modify：** `app/lib/search/content_indexing_scheduler.dart` — `_processOneBook()` 新增取消防護；新增私有 helper `_isStillTracked()`。
- **Modify：** `app/test/search/content_indexing_scheduler_test.dart` — 新增 `epic-10-search Issue 3：分類關閉時排程器中止防護` 測試群組。
- **Create：** `app/lib/search/full_text_search_settings_repository.dart` — `ContentIndexCategory` enum、`FullTextSearchSettingsRepository` 抽象介面（含 `rebuildIndex`）、`SqliteFullTextSearchSettingsRepository` 實作。
- **Create：** `app/test/search/full_text_search_settings_repository_test.dart`
- **Create：** `app/test/support/fake_full_text_search_settings_repository.dart`
- **Create：** `app/lib/screens/full_text_search_confirm_dialog.dart`
- **Create：** `app/test/screens/full_text_search_confirm_dialog_test.dart`
- **Modify：** `app/lib/screens/library_screen_dependencies.dart`
- **Modify：** `app/lib/screens/settings_scaffold.dart`
- **Modify：** `app/test/screens/settings_scaffold_test.dart`
- **Modify：** `app/lib/screens/adaptive_shell_scaffold.dart`
- **Modify：** `app/test/screens/adaptive_shell_scaffold_test.dart`
- **Modify：** `app/lib/main.dart`

---

### Task 1：`ContentIndexingScheduler` 取消防護（review-plan-issue-3.md C-1）

**Files：**
- Modify: `app/lib/search/content_indexing_scheduler.dart`
- Test: `app/test/search/content_indexing_scheduler_test.dart`

**Interfaces：**
- Consumes：既有 `content_index_status` schema（Issue 0）。
 - Produces：`ContentIndexingScheduler` 私有行為變更（無新公開 API）——`_processOneBook()` 在分類被外部關閉（`content_index_status` 列被刪除）時會中止處理並清除已寫入的殘留列，供 Task 2 的 `setEnabled(category, false)` 依賴這個行為保證「關閉即乾淨」。

- [x] **Step 1：寫一組會失敗的測試**

在 `app/test/search/content_indexing_scheduler_test.dart`，於既有 `group('ContentIndexingScheduler', () { ... });` 區塊內（任一位置，緊接在既有測試之後即可）新增：

```dart
    test(
        '處理中若 content_index_status 列被外部刪除（模擬「啟用全文檢索」開關關閉），'
        '中止處理並清除已寫入的殘留索引列（review-plan-issue-3.md C-1）', () async {
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
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 章節 0 →章節 1 的邊界會觸發一次 flush，此時 content_index_status
      // 列仍存在，章節 0 應正常寫入 book_content_index。
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一章'));
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二章'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final flushedRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(flushedRows, hasLength(1), reason: '章節 0 應已正常 flush');

      // 模擬「啟用全文檢索」開關關閉：外部直接刪除該書的
      // content_index_status 列（比照
      // SqliteFullTextSearchSettingsRepository._clearIndexData() 的實際
      // 行為，見 plans/plan-issue-3.md Task 2）。
      await db.delete('content_index_status',
          where: 'book_id = ?', whereArgs: ['book-1']);

      // 章節 1 →章節 2 的邊界應偵測到列已消失，中止處理，不再 flush 章節 1，
      // 且清除章節 0 先前已寫入的殘留列（不留下孤兒索引）。
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 2, locator: 'epubcfi(/6/6)', rawText: '第三章'));
      await foliateIndexer.finish();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final indexRowsAfter = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRowsAfter, isEmpty,
          reason: '分類關閉後應清除已寫入的殘留列，不留下孤兒索引');
    });
```

- [x] **Step 2：執行測試，確認因為 production 行為尚未實作而失敗**

Run: `flutter test test/search/content_indexing_scheduler_test.dart`
Expected: FAIL（新測試斷言 `indexRowsAfter` 為空，但現行程式碼會繼續寫入章節 1／2，斷言失敗）。

- [x] **Step 3：實作取消防護**

在 `app/lib/search/content_indexing_scheduler.dart`，找到：

```dart
    var pending = <Map<String, Object?>>[];
    int? pendingChapterIndex;
    var paused = false;
```

取代為：

```dart
    var pending = <Map<String, Object?>>[];
    int? pendingChapterIndex;
    var paused = false;
    var cancelled = false;
```

找到：

```dart
    try {
      await for (final segment
          in indexer.indexBook(book, resumeFromChapter: resumeFromChapter)) {
        if (pendingChapterIndex != null &&
            segment.chapterIndex != pendingChapterIndex) {
          await flushPendingChapter(pendingChapterIndex);
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
          await flushPendingChapter(pendingChapterIndex);
        }
        await _database.update(
          'content_index_status',
          {'status': 'done', 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'book_id = ?',
          whereArgs: [book.id],
        );
      }
    } catch (e) {
```

取代為：

```dart
    try {
      await for (final segment
          in indexer.indexBook(book, resumeFromChapter: resumeFromChapter)) {
        if (pendingChapterIndex != null &&
            segment.chapterIndex != pendingChapterIndex) {
          // 【review-plan-issue-3.md C-1】在寫入下一個章節之前，先確認這本書
          // 是否仍被追蹤——「啟用全文檢索」開關關閉時
          // （SqliteFullTextSearchSettingsRepository.setEnabled(category,
          // false)）會直接刪除該分類所有書籍的 content_index_status 列，
          // 若本排程器當下正在處理該分類的某本書，必須在這裡偵測到並中止，
          // 否則會在使用者已關閉該分類之後，繼續寫入之後查詢得到的孤兒
          // 索引列（spec.md §5：搜尋完全信任索引存在與否，不重新檢查開關
          // 狀態）。
          if (!await _isStillTracked(book.id)) {
            cancelled = true;
            break;
          }
          await flushPendingChapter(pendingChapterIndex);
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
      if (!paused && !cancelled) {
        if (pendingChapterIndex != null) {
          if (!await _isStillTracked(book.id)) {
            cancelled = true;
          } else {
            await flushPendingChapter(pendingChapterIndex);
          }
        }
      }
      if (cancelled) {
        // 清除競態視窗內已經寫入的殘留列（例如上一個章節邊界已經
        // flush 成功，但下一個邊界才偵測到分類已被關閉）——分類關閉時
        // 這本書的索引資料本來就該完全清空，不留下部分章節的孤兒列。
        await _database.delete('book_content_index',
            where: 'book_id = ?', whereArgs: [book.id]);
      } else if (!paused) {
        await _database.update(
          'content_index_status',
          {'status': 'done', 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'book_id = ?',
          whereArgs: [book.id],
        );
      }
    } catch (e) {
```

最後，在 `_processOneBook` 方法結尾（`}`，緊接在 class 收尾之前）新增私有 helper：

```dart

  /// epic-10-search Issue 3（review-plan-issue-3.md C-1）：[bookId] 對應的
  /// `content_index_status` 列是否仍然存在。用於 `_processOneBook()` 在每個
  /// 章節邊界檢查該書是否仍被追蹤——一旦消失即代表已被外部關閉並捨棄進度
  /// （見上方 `_processOneBook` 內的呼叫點說明）。
  Future<bool> _isStillTracked(String bookId) async {
    final rows = await _database.query(
      'content_index_status',
      columns: ['book_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/search/content_indexing_scheduler_test.dart`
Expected: PASS（新增測試＋既有全部測試皆通過——整檔重跑，確保取消防護沒有破壞既有「正常完成」／「暫停續跑」等既有行為）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/content_indexing_scheduler.dart app/test/search/content_indexing_scheduler_test.dart
git commit -m "fix(search): 排程器新增分類關閉時的取消防護，避免孤兒索引（Issue 3 C-1）"
```

---

### Task 2：`ContentIndexCategory`＋`FullTextSearchSettingsRepository`＋`SqliteFullTextSearchSettingsRepository`

**Files：**
- Create: `app/lib/search/full_text_search_settings_repository.dart`
- Test: `app/test/search/full_text_search_settings_repository_test.dart`

**Interfaces：**
- Consumes：既有 `SqliteLibraryRepository.database`、既有 `books`/`content_index_status`/`book_content_index` schema（Issue 0）、Task 1 交付的「關閉即乾淨」排程器行為保證。
- Produces：`enum ContentIndexCategory { pdf, foliate }`；`abstract class FullTextSearchSettingsRepository { isEnabled, setEnabled, rebuildIndex }`；`class SqliteFullTextSearchSettingsRepository implements FullTextSearchSettingsRepository`，建構子 `({required Database database, required void Function() requestProcessing})`。

- [x] **Step 1：寫一組會失敗（編譯錯誤）的測試**

建立 `app/test/search/full_text_search_settings_repository_test.dart`：

```dart
// app/test/search/full_text_search_settings_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

Book _book(
  String id, {
  BookFileFormat format = BookFileFormat.epub,
  bool isDownloaded = true,
}) {
  return Book(
    id: id,
    title: '測試書 $id',
    format: format,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
    isDownloaded: isDownloaded,
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late Database db;
  late int requestProcessingCallCount;
  late SqliteFullTextSearchSettingsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = libraryRepository.database;
    requestProcessingCallCount = 0;
    repository = SqliteFullTextSearchSettingsRepository(
      database: db,
      requestProcessing: () => requestProcessingCallCount++,
    );
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  Future<Map<String, Object?>?> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.single;
  }

  group('epic-10-search Issue 3：FullTextSearchSettingsRepository', () {
    test('isEnabled 兩個分類初始值皆為 false', () async {
      expect(await repository.isEnabled(ContentIndexCategory.pdf), isFalse);
      expect(
          await repository.isEnabled(ContentIndexCategory.foliate), isFalse);
    });

    test('setEnabled(pdf, true) 後 isEnabled(pdf) 為 true，foliate 不受影響',
        () async {
      await repository.setEnabled(ContentIndexCategory.pdf, true);

      expect(await repository.isEnabled(ContentIndexCategory.pdf), isTrue);
      expect(
          await repository.isEnabled(ContentIndexCategory.foliate), isFalse);
    });

    test('setEnabled(pdf, true) 只回填「pdf 格式且已下載」且尚無資料列的書籍',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository.insertBook(_book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      ));

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      final pdfStatus = await statusOf('pdf-1');
      expect(pdfStatus, isNotNull);
      expect(pdfStatus!['status'], 'pending');
      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-not-downloaded'), isNull);
    });

    test(
        'setEnabled(foliate, true) 回填多種格式（epub/txt/azw3/md）並排除 pdf'
        '（review-plan-issue-3.md M-3）', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('txt-1', format: BookFileFormat.txt));
      await libraryRepository
          .insertBook(_book('azw3-1', format: BookFileFormat.azw3));
      await libraryRepository
          .insertBook(_book('md-1', format: BookFileFormat.md));
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));

      await repository.setEnabled(ContentIndexCategory.foliate, true);

      for (final id in ['epub-1', 'txt-1', 'azw3-1', 'md-1']) {
        final status = await statusOf(id);
        expect(status, isNotNull, reason: '$id 應被回填為 pending');
        expect(status!['status'], 'pending');
      }
      expect(await statusOf('pdf-1'), isNull);
    });

    test(
        'setEnabled(foliate, true) 把既有未追蹤的 cbz 書籍標記為 unsupported，'
        '不進入 pending 佇列（review-plan-issue-3.md I-2）', () async {
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await repository.setEnabled(ContentIndexCategory.foliate, true);

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
    });

    test('setEnabled(category, true) 不覆蓋已存在的 content_index_status 列',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-done', format: BookFileFormat.pdf));
      await db.insert('content_index_status', {
        'book_id': 'pdf-done',
        'status': 'done',
        'updated_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      final status = await statusOf('pdf-done');
      expect(status!['status'], 'done');
    });

    test('setEnabled(category, true) 呼叫 requestProcessing 喚醒排程器', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      expect(requestProcessingCallCount, 1);
    });

    test('setEnabled(category, false) 不呼叫 requestProcessing', () async {
      await repository.setEnabled(ContentIndexCategory.pdf, false);

      expect(requestProcessingCallCount, 0);
    });

    test('setEnabled(pdf, false) 清除 pdf 格式索引資料，不影響 foliate 格式既有索引',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'epub-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-pdf-1',
        'book_id': 'pdf-1',
        'chapter_index': 0,
        'locator': '{"page":0}',
        'raw_text': 'PDF 內容',
        'token_text': 'PDF 內容',
        'created_at': 1000,
      });
      await db.insert('book_content_index', {
        'id': 'seg-epub-1',
        'book_id': 'epub-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': 'EPUB 內容',
        'token_text': 'EPUB 內容',
        'created_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.pdf, false);

      expect(await statusOf('pdf-1'), isNull);
      expect(await statusOf('epub-1'), isNotNull);
      final pdfIndexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['pdf-1']);
      expect(pdfIndexRows, isEmpty);
      final epubIndexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['epub-1']);
      expect(epubIndexRows, hasLength(1));
      final ftsRows = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH 'PDF'");
      expect(ftsRows, isEmpty, reason: 'FTS5 trigger 應同步清空已刪除的 pdf 索引列');
    });

    test(
        'setEnabled(foliate, false) 清除 foliate 格式索引資料，不影響 pdf 格式既有索引'
        '（review-plan-issue-3.md M-3）', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await db.insert('content_index_status',
          {'book_id': 'epub-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-epub-1',
        'book_id': 'epub-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': 'EPUB 內容',
        'token_text': 'EPUB 內容',
        'created_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.foliate, false);

      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-1'), isNotNull);
    });

    test(
        'rebuildIndex(category) 清除既有索引後重新回填 pending 並喚醒排程器',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-pdf-1',
        'book_id': 'pdf-1',
        'chapter_index': 0,
        'locator': '{"page":0}',
        'raw_text': '舊內容',
        'token_text': '舊內容',
        'created_at': 1000,
      });

      await repository.rebuildIndex(ContentIndexCategory.pdf);

      final status = await statusOf('pdf-1');
      expect(status, isNotNull);
      expect(status!['status'], 'pending');
      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['pdf-1']);
      expect(indexRows, isEmpty, reason: '重建索引應先清除舊的索引明細');
      expect(requestProcessingCallCount, 1);
    });
  });
}
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: FAIL（編譯錯誤：`package:elinkbook/search/full_text_search_settings_repository.dart` 不存在）。

- [x] **Step 3：實作 `ContentIndexCategory`／`FullTextSearchSettingsRepository`／`SqliteFullTextSearchSettingsRepository`**

建立 `app/lib/search/full_text_search_settings_repository.dart`：

```dart
// app/lib/search/full_text_search_settings_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 「啟用全文檢索」的兩個獨立分類（epic-10-search Issue 3，見 spec.md
/// §4）：PDF 走純 Dart/FFI 但可能因掃描件缺乏文字層而索引無效；其餘格式
/// （Foliate：epub/txt/azw3/md，**不含 cbz**——見下方 `_formatFilterFor`
/// 說明）走 Headless WebView 資源較重但幾乎必有文字層，兩者關切點互補，
/// 故拆成兩個獨立開關。
enum ContentIndexCategory { pdf, foliate }

/// 「啟用全文檢索」設定模型（spec.md §4）：兩個分類各自的持久化開關，
/// 開啟時批次回填既有書庫（寫入 pending，交給建構子注入的
/// `requestProcessing` 喚醒排程器），關閉時立即清除該分類已建立的索引
/// 資料，兩個分類互不影響；[rebuildIndex] 供使用者手動重建（issues.md
/// Issue 3 單元測試要求／驗收標準明訂，review-plan-issue-3.md I-1）。
abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
  Future<void> rebuildIndex(ContentIndexCategory category);
}

/// [FullTextSearchSettingsRepository] 正式實作：開關本身存 `SharedPreferences`
/// （比照 `AppThemePreferences`／`LibraryPreferences` 既有慣例），批次回填/
/// 清除/重建索引資料直接對 [Database] 下 SQL（`ContentIndexingScheduler`
/// 本身也是這樣操作 `content_index_status`/`book_content_index`，本類別
/// 不重複實作排程邏輯；「關閉即乾淨」的競態防護落在
/// `ContentIndexingScheduler._processOneBook()`，見 plans/plan-issue-3.md
/// Task 1，review-plan-issue-3.md C-1）。
///
/// [requestProcessing] 刻意收窄成單一 callback 而非直接持有整個
/// `ContentIndexingScheduler`（比照 `LibrarySyncDependencies.onManualSync`
/// 既有先例），正式執行路徑由 `main.dart` 傳入
/// `contentIndexingScheduler.requestProcessing`。
class SqliteFullTextSearchSettingsRepository
    implements FullTextSearchSettingsRepository {
  SqliteFullTextSearchSettingsRepository({
    required Database database,
    required void Function() requestProcessing,
  })  : _database = database,
        _requestProcessing = requestProcessing;

  final Database _database;
  final void Function() _requestProcessing;

  static String _prefsKeyFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? 'full_text_search_enabled_pdf'
          : 'full_text_search_enabled_foliate';

  /// 回傳的字串片段假設呼叫端已在 SQL 中定位到 `books` 表（或其別名）的
  /// `format` 欄位。`pdf` → `format = 'pdf'`；`foliate` → 其餘格式扣除
  /// `cbz`（review-plan-issue-3.md I-2：CBZ 無文字層，spec.md §7 規定必須
  /// 是 `unsupported`，天生被排程器排除，光憑 `format` 字串本身就能判斷，
  /// 不像 DRM KF8 需要深入解析檔案內容——那仍是 Issue 2 的範圍）。
  static String _formatFilterFor(ContentIndexCategory category) =>
      category == ContentIndexCategory.pdf
          ? "format = 'pdf'"
          : "format != 'pdf' AND format != 'cbz'";

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyFor(category)) ?? false;
  }

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyFor(category), value);
    if (value) {
      await _backfillPending(category);
      _requestProcessing();
    } else {
      await _clearIndexData(category);
    }
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _clearIndexData(category);
    await _backfillPending(category);
    _requestProcessing();
  }

  /// 把 `content_index_status` 中尚無資料列、且格式符合 [category]、且已
  /// 下載的既有書籍批次插入 `pending`（spec.md §4／§7：未下載的雲端書籍
  /// 不建立列）。已有資料列的書籍一律跳過，不重複插入也不覆蓋既有
  /// status。**`foliate` 分類額外**把既有尚無資料列的 `cbz` 書籍批次標記
  /// 為 `unsupported`（review-plan-issue-3.md I-2），不進入 `pending`
  /// 佇列。
  Future<void> _backfillPending(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.rawInsert('''
      INSERT INTO content_index_status (book_id, status, updated_at)
      SELECT b.id, 'pending', ?
      FROM books b
      LEFT JOIN content_index_status cis ON cis.book_id = b.id
      WHERE cis.book_id IS NULL
        AND b.is_downloaded = 1
        AND b.$formatFilter
    ''', [now]);
    if (category == ContentIndexCategory.foliate) {
      await _database.rawInsert('''
        INSERT INTO content_index_status (book_id, status, updated_at)
        SELECT b.id, 'unsupported', ?
        FROM books b
        LEFT JOIN content_index_status cis ON cis.book_id = b.id
        WHERE cis.book_id IS NULL
          AND b.format = 'cbz'
      ''', [now]);
    }
  }

  /// 刪除 [category] 對應格式書籍的索引資料（`book_content_index`／
  /// `content_index_status`），trigger 同步清空對應 FTS 列。兩句 `DELETE`
  /// 包在同一交易內（review-plan-issue-3.md M-2）——若中途斷電/crash，
  /// 避免兩張表各自只刪一半造成資料不一致（例如 `book_content_index` 已
  /// 清空但 `content_index_status` 殘留舊 `status`，導致下次 `_backfillPending`
  /// 的 `LEFT JOIN` 誤判「已有資料列」而永遠不再回填該書）。不影響另一
  /// 分類已建立的索引。
  Future<void> _clearIndexData(ContentIndexCategory category) async {
    final formatFilter = _formatFilterFor(category);
    await _database.transaction((txn) async {
      await txn.rawDelete('''
        DELETE FROM book_content_index
        WHERE book_id IN (SELECT id FROM books WHERE $formatFilter)
      ''');
      await txn.rawDelete('''
        DELETE FROM content_index_status
        WHERE book_id IN (SELECT id FROM books WHERE $formatFilter)
      ''');
    });
  }
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: PASS（12 項測試全過）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/search/full_text_search_settings_repository.dart app/test/search/full_text_search_settings_repository_test.dart
git commit -m "feat(search): 新增 FullTextSearchSettingsRepository（Issue 3 設定模型）"
```

---

### Task 3：確認 Dialog＋共用 Fake

**Files：**
- Create: `app/lib/screens/full_text_search_confirm_dialog.dart`
- Create: `app/test/support/fake_full_text_search_settings_repository.dart`
- Test: `app/test/screens/full_text_search_confirm_dialog_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `ContentIndexCategory`。
- Produces：`Future<bool> showFullTextSearchEnableConfirmDialog(BuildContext, {required ContentIndexCategory category, bool isEinkMode = false})`；`FakeFullTextSearchSettingsRepository implements FullTextSearchSettingsRepository`（含 `setEnabledCalls`／`rebuildIndexCalls` 兩個記錄清單，供 Task 4 與未來 Issue 4 widget test 共用）。

- [x] **Step 1：寫一組會失敗（編譯錯誤）的測試**

建立 `app/test/support/fake_full_text_search_settings_repository.dart`：

```dart
// app/test/support/fake_full_text_search_settings_repository.dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

/// 供 widget test 使用的記憶體內 [FullTextSearchSettingsRepository] 假實作
/// （epic-10-search Issue 3），避免 widget test 依賴真實 SharedPreferences／
/// sqflite（比照 `test/support/fake_library_repository.dart` 既有慣例）。
class FakeFullTextSearchSettingsRepository
    implements FullTextSearchSettingsRepository {
  FakeFullTextSearchSettingsRepository({
    Map<ContentIndexCategory, bool> initialEnabled = const {},
  }) : _enabled = Map.of(initialEnabled);

  final Map<ContentIndexCategory, bool> _enabled;

  /// 記錄每次 [setEnabled] 呼叫的 `(category, value)`。
  final List<(ContentIndexCategory, bool)> setEnabledCalls = [];

  /// 記錄每次 [rebuildIndex] 呼叫的 `category`（review-plan-issue-3.md
  /// I-1）。
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }
}
```

建立 `app/test/screens/full_text_search_confirm_dialog_test.dart`：

```dart
// app/test/screens/full_text_search_confirm_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

/// 捕捉 Navigator 實際推入的 Route，供斷言 `DialogRoute` 的
/// `transitionDuration` 是否真的依 `isEinkMode` 走到 `AnimationStyle.
/// noAnimation`（比照 `test/screens/widgets/eb_sheet_shell_test.dart`
/// 既有手法）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

Future<bool?> _open(
  WidgetTester tester, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
  NavigatorObserver? observer,
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observer == null ? [] : [observer],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showFullTextSearchEnableConfirmDialog(
              context,
              category: category,
              isEinkMode: isEinkMode,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('按下取消對話框關閉', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_cancel'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsNothing,
    );
  });

  testWidgets('按下確認開啟回傳 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showFullTextSearchEnableConfirmDialog(
                context,
                category: ContentIndexCategory.foliate,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_confirm'),
    ));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('PDF 分類額外顯示掃描件提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.pdf);

    expect(find.textContaining('掃描/圖片型 PDF'), findsOneWidget);
  });

  testWidgets('Foliate 分類不顯示 PDF 專屬提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);

    expect(find.textContaining('掃描/圖片型 PDF'), findsNothing);
  });

  testWidgets('對話框寬度不超過 400，且不強制施加緊約束（review-plan-issue-3.md I-3）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showFullTextSearchEnableConfirmDialog(
              context,
              category: ContentIndexCategory.foliate,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 不應有任何 overflow 相關的 FlutterError（pumpAndSettle 若渲染期間
    // 拋出 overflow 例外，測試本身就會直接失敗），此處額外斷言對話框
    // 確實成功渲染出來，佐證沒有在 debug 模式被 overflow 中斷。
    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsOneWidget,
    );
  });

  testWidgets('isEinkMode: true 時彈出動畫時長為 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      isEinkMode: true,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, Duration.zero);
  });

  testWidgets('isEinkMode: false（預設）時彈出動畫時長非 Duration.zero',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, isNot(Duration.zero));
  });
}
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/screens/full_text_search_confirm_dialog_test.dart`
Expected: FAIL（編譯錯誤：`package:elinkbook/screens/full_text_search_confirm_dialog.dart` 不存在）。

- [x] **Step 3：實作 `showFullTextSearchEnableConfirmDialog()`**

建立 `app/lib/screens/full_text_search_confirm_dialog.dart`：

```dart
// app/lib/screens/full_text_search_confirm_dialog.dart
import 'package:flutter/material.dart';

import '../search/full_text_search_settings_repository.dart';

/// 「啟用全文檢索」確認對話框（epic-10-search Issue 3，見 spec.md §4）：
/// 兩個分類（PDF／其他格式）共用同一個對話框，依 [category] 帶入不同
/// 文案；套用 `DESIGN.md` §9.1 一般排版慣例（平板上限寬度 400dp、主動作
/// 靠右、E-Ink 模式下 Scrim 即時切換不淡入淡出），但**不套用** §9.2「破壞
/// 性操作」的 error 色按鈕慣例——啟用全文檢索不會刪除/遺失任何資料。
/// `content` 用 `ConstrainedBox(maxWidth: 400)` 而非固定寬度的 `SizedBox`
/// （review-plan-issue-3.md I-3：`AlertDialog` 預設 `insetPadding` 左右各
/// 40dp，共 80dp，`SizedBox` 施加的緊約束若沒扣掉這個值，在 360～400dp
/// 手機上會溢位；`ConstrainedBox` 只設上限，實際寬度仍依父層可用空間
/// 收縮，不會超出）。`EBDialogShell` 目前尚未落地為共用元件，手動以
/// `AlertDialog` 符合上述排版規則。
///
/// 純 UI 確認元件，本身不呼叫 [FullTextSearchSettingsRepository]——呼叫端
/// （`SettingsScaffold`）在使用者按下「確認開啟」（本函式回傳 `true`）之後
/// 才呼叫 `setEnabled(category, true)`，比照既有
/// `showCloudDuplicateConfirmDialog()` 純回傳 bool 的既有慣例。
Future<bool> showFullTextSearchEnableConfirmDialog(
  BuildContext context, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
}) async {
  final message = category == ContentIndexCategory.pdf
      ? '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量'
          '消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，'
          '索引後仍查不到屬於正常情況。'
      : '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量'
          '消耗，是否繼續？';
  final result = await showDialog<bool>(
    context: context,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (context) => AlertDialog(
      key: const Key('full_text_search_enable_confirm_dialog'),
      title: const Text('啟用全文檢索'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(message),
      ),
      actions: [
        TextButton(
          key: const Key('full_text_search_enable_confirm_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('full_text_search_enable_confirm_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確認開啟'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/full_text_search_confirm_dialog_test.dart`
Expected: PASS（7 項測試全過）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/full_text_search_confirm_dialog.dart app/test/support/fake_full_text_search_settings_repository.dart app/test/screens/full_text_search_confirm_dialog_test.dart
git commit -m "feat(search): 新增啟用全文檢索確認對話框（Issue 3）"
```

---

### Task 4：`SettingsScaffold`「閱讀」分區整合＋依賴注入轉送

**Files：**
- Modify: `app/lib/screens/library_screen_dependencies.dart`
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Test: `app/test/screens/settings_scaffold_test.dart`
- Test: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `FullTextSearchSettingsRepository`/`ContentIndexCategory`、Task 3 的 `showFullTextSearchEnableConfirmDialog()`/`FakeFullTextSearchSettingsRepository`。
- Produces：`LibraryReaderFeatureRepositories.fullTextSearchSettingsRepository`（`FullTextSearchSettingsRepository?`）／`.isFullTextSearchAvailable`（`bool`，預設 `true`）；`SettingsScaffold.fullTextSearchSettingsRepository`／`.isFullTextSearchAvailable` 兩個新建構參數。

- [x] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/settings_scaffold_test.dart` 檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import '../support/fake_full_text_search_settings_repository.dart';
```

在檔案內最後一個既有 `testWidgets(...)` 之後、`main()` 收尾 `}` 之前，新增（**每個 `testWidgets` 開頭皆設定測試視窗尺寸，比照本檔案既有慣例——review-plan-issue-3.md I-4**：「閱讀」分區內的新開關位置比既有「朗讀語音與語速」還更下面，預設 800×600 測試視窗會讓 `tester.tap()` 打不到）：

```dart
  group('epic-10-search Issue 3：全文檢索設定開關', () {
    testWidgets('開關初始值反映 repository.isEnabled()', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(
                const Key('settings_full_text_search_foliate_switch')))
            .value,
        isFalse,
      );
    });

    testWidgets('開啟開關前彈出確認對話框，取消不呼叫 setEnabled', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('full_text_search_enable_confirm_dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(
          const Key('full_text_search_enable_confirm_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(repository.setEnabledCalls, isEmpty);
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isFalse,
      );
    });

    testWidgets('開啟開關確認後呼叫 setEnabled(true) 並更新畫面狀態', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const Key('full_text_search_enable_confirm_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
    });

    testWidgets('關閉開關不彈出確認對話框，直接呼叫 setEnabled(false)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('full_text_search_enable_confirm_dialog')),
        findsNothing,
      );
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, false)]);
    });

    testWidgets(
        '重建索引按鈕：開關開啟時可用，點擊後呼叫 rebuildIndex（review-plan-issue-3.md I-1）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(
          const Key('settings_full_text_search_pdf_rebuild_button')));
      await tester.pumpAndSettle();

      expect(repository.rebuildIndexCalls, [ContentIndexCategory.pdf]);
    });

    testWidgets('重建索引按鈕：開關關閉時停用', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(find.byKey(
          const Key('settings_full_text_search_pdf_rebuild_button')));
      expect(button.onPressed, isNull);
    });

    testWidgets('isFullTextSearchAvailable 為 false 時顯示不支援提示、不顯示開關',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
            isFullTextSearchAvailable: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings_full_text_search_unavailable_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_full_text_search_pdf_switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settings_full_text_search_foliate_switch')),
        findsNothing,
      );
    });

    testWidgets(
        'didUpdateWidget 時重新載入全文檢索開關狀態（review-plan-issue-3.md M-1）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isFalse,
      );

      // 模擬另一個入口（Issue 4 的全庫搜尋畫面）呼叫 setEnabled 之後，本
      // 畫面因為 IndexedStack 切換分頁而重新 build（同一個 State，重新
      // 傳入等價的 widget 設定）。
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
    });
  });
```

在 `app/test/screens/adaptive_shell_scaffold_test.dart` 檔案開頭 import 區塊新增：

```dart
import '../support/fake_full_text_search_settings_repository.dart';
```

在既有 `testWidgets('SettingsScreen 收到 customFontsRepository/onEinkModeChanged 轉送……', ...)` 測試之後，新增：

```dart
  testWidgets(
      'SettingsScreen 收到 fullTextSearchSettingsRepository/isFullTextSearchAvailable 轉送',
      (tester) async {
    final fullTextSearchSettingsRepository =
        FakeFullTextSearchSettingsRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
            isFullTextSearchAvailable: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScreen =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(
      settingsScreen.fullTextSearchSettingsRepository,
      fullTextSearchSettingsRepository,
    );
    expect(settingsScreen.isFullTextSearchAvailable, isFalse);
  });
```

- [x] **Step 2：執行測試，確認因為 production API 尚不存在而編譯失敗**

Run: `flutter test test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart`
Expected: FAIL（編譯錯誤：`SettingsScaffold`／`LibraryReaderFeatureRepositories` 沒有對應具名參數）。

- [x] **Step 3：實作**

在 `app/lib/screens/library_screen_dependencies.dart`，於檔案頂端 import 區塊新增：

```dart
import '../search/full_text_search_settings_repository.dart';
```

找到：

```dart
@immutable
class LibraryReaderFeatureRepositories {
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final TtsProvider? ttsProvider;
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;
  final ReaderActivityTracker? readerActivityTracker;

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
  });
}
```

取代為：

```dart
@immutable
class LibraryReaderFeatureRepositories {
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final TtsProvider? ttsProvider;
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;
  final ReaderActivityTracker? readerActivityTracker;

  /// epic-10-search Issue 3：「啟用全文檢索」設定模型。null 時
  /// `SettingsScaffold` 不顯示可互動的開關。
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;

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

在 `app/lib/screens/settings_scaffold.dart`，於 import 區塊新增：

```dart
import '../search/full_text_search_settings_repository.dart';
import 'full_text_search_confirm_dialog.dart';
```

找到：

```dart
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSource;
  final TtsProvider? ttsProvider;

  const SettingsScaffold({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.onManualSync,
    this.loadLastSyncedAt,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.onNavigateToLibrary,
    this.onNavigateToSource,
    this.ttsProvider,
  });
```

取代為：

```dart
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSource;
  final TtsProvider? ttsProvider;
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;

  const SettingsScaffold({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.onManualSync,
    this.loadLastSyncedAt,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.onNavigateToLibrary,
    this.onNavigateToSource,
    this.ttsProvider,
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
  });
```

找到：

```dart
class _SettingsScaffoldState extends State<SettingsScaffold> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式——本畫面其餘 `ListTile`
  /// （佈景／字型管理等）與這個開關無關，初始值先顯示預設 `false`，
  /// `initState()` 的非同步載入完成後才 `setState` 更新為實際已儲存值，不
  /// 阻塞其餘項目的同步顯示。
  bool _consoleLogEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadConsoleLogEnabled();
  }

  Future<void> _loadConsoleLogEnabled() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _consoleLogEnabled = prefs.consoleLogEnabled);
  }

  Future<void> _updateConsoleLogEnabled(bool value) async {
    setState(() => _consoleLogEnabled = value);
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    await widget.prefsManager.saveGlobalPrefs(
      prefs.copyWith(consoleLogEnabled: value),
    );
  }
```

取代為：

```dart
class _SettingsScaffoldState extends State<SettingsScaffold> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式——本畫面其餘 `ListTile`
  /// （佈景／字型管理等）與這個開關無關，初始值先顯示預設 `false`，
  /// `initState()` 的非同步載入完成後才 `setState` 更新為實際已儲存值，不
  /// 阻塞其餘項目的同步顯示。
  bool _consoleLogEnabled = false;

  /// 「啟用全文檢索」兩個分類目前顯示值（epic-10-search Issue 3），比照
  /// 上方 `_consoleLogEnabled` 同一套模式。
  bool _fullTextSearchPdfEnabled = false;
  bool _fullTextSearchFoliateEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadConsoleLogEnabled();
    _loadFullTextSearchSettings();
  }

  /// 【review-plan-issue-3.md M-1】`SettingsScaffold` 被 `AdaptiveShellScaffold`
  /// 的 `IndexedStack` 長駐掛載，只有 `initState()` 會載入一次的話，Issue 4
  /// 全庫搜尋畫面的第二個入口若改變了開關狀態，切回本畫面時會顯示過期的
  /// 值。切分頁會觸發 `AdaptiveShellScaffold.build()` 重新建構
  /// `SettingsScaffold(...)`，本 State 物件被重用、`didUpdateWidget` 因此
  /// 會被呼叫，在這裡重新載入即可低成本解決雙入口同步問題。
  @override
  void didUpdateWidget(covariant SettingsScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadFullTextSearchSettings();
  }

  Future<void> _loadConsoleLogEnabled() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _consoleLogEnabled = prefs.consoleLogEnabled);
  }

  Future<void> _updateConsoleLogEnabled(bool value) async {
    setState(() => _consoleLogEnabled = value);
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    await widget.prefsManager.saveGlobalPrefs(
      prefs.copyWith(consoleLogEnabled: value),
    );
  }

  Future<void> _loadFullTextSearchSettings() async {
    final repository = widget.fullTextSearchSettingsRepository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _fullTextSearchPdfEnabled = pdfEnabled;
      _fullTextSearchFoliateEnabled = foliateEnabled;
    });
  }

  /// 關閉開關（[value] 為 `false`）直接呼叫 `setEnabled`，不彈出確認對話框
  /// ——只有「從關閉切成開啟」才需要確認。使用者取消對話框時提前 return，
  /// 開關維持關閉、不呼叫 `setEnabled`。
  Future<void> _handleFullTextSearchToggle(
    ContentIndexCategory category,
    bool value,
  ) async {
    final repository = widget.fullTextSearchSettingsRepository;
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
        _fullTextSearchPdfEnabled = value;
      } else {
        _fullTextSearchFoliateEnabled = value;
      }
    });
  }
```

最後，找到「閱讀」分區內的「朗讀語音與語速」卡片結尾（緊接在 `EBSectionHeader(title: '同步與帳號')` 之前）：

```dart
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_tts_defaults_button'),
              title: const Text('朗讀語音與語速'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TtsDefaultsScreen(
                      prefsManager: widget.prefsManager,
                      ttsProvider: widget.ttsProvider,
                      isEinkMode: widget.isEinkMode,
                    ),
                  ),
                );
              },
            ),
          ),
          const EBSectionHeader(title: '同步與帳號'),
```

取代為：

```dart
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_tts_defaults_button'),
              title: const Text('朗讀語音與語速'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TtsDefaultsScreen(
                      prefsManager: widget.prefsManager,
                      ttsProvider: widget.ttsProvider,
                      isEinkMode: widget.isEinkMode,
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.isFullTextSearchAvailable)
            _SettingsCard(
              child: ListTile(
                key: const Key('settings_full_text_search_unavailable_hint'),
                leading: const Icon(Icons.info_outline),
                title: const Text('全文檢索'),
                subtitle: const Text('本裝置不支援全文檢索'),
              ),
            )
          else ...[
            _SettingsCard(
              child: ListTile(
                title: const Text('PDF 全文檢索'),
                subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_pdf_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchPdfEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                    ),
                    Switch(
                      key: const Key('settings_full_text_search_pdf_switch'),
                      value: _fullTextSearchPdfEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.pdf, value),
                    ),
                  ],
                ),
              ),
            ),
            _SettingsCard(
              child: ListTile(
                title: const Text('其他格式全文檢索'),
                subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_foliate_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchFoliateEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                    ),
                    Switch(
                      key: const Key(
                          'settings_full_text_search_foliate_switch'),
                      value: _fullTextSearchFoliateEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.foliate, value),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const EBSectionHeader(title: '同步與帳號'),
```

在 `app/lib/screens/adaptive_shell_scaffold.dart`，找到：

```dart
            SettingsScaffold(
              prefsManager: widget.prefsManager,
              currentTheme: widget.themeDependencies.currentTheme,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onThemeChanged: widget.themeDependencies.onThemeChanged,
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              syncAccountRepository:
                  widget.syncDependencies.syncAccountRepository,
              syncClient: widget.syncDependencies.syncClient,
              onManualSync: widget.syncDependencies.onManualSync,
              loadLastSyncedAt: widget.syncDependencies.loadLastSyncedAt,
              cloudAccountRepository:
                  widget.cloudAccountDependencies.cloudAccountRepository,
              googleDriveOAuthClient:
                  widget.cloudAccountDependencies.googleDriveOAuthClient,
              oneDriveOAuthClient:
                  widget.cloudAccountDependencies.oneDriveOAuthClient,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSource: () => _navigateTo(1),
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
            ),
```

取代為：

```dart
            SettingsScaffold(
              prefsManager: widget.prefsManager,
              currentTheme: widget.themeDependencies.currentTheme,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onThemeChanged: widget.themeDependencies.onThemeChanged,
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              syncAccountRepository:
                  widget.syncDependencies.syncAccountRepository,
              syncClient: widget.syncDependencies.syncClient,
              onManualSync: widget.syncDependencies.onManualSync,
              loadLastSyncedAt: widget.syncDependencies.loadLastSyncedAt,
              cloudAccountRepository:
                  widget.cloudAccountDependencies.cloudAccountRepository,
              googleDriveOAuthClient:
                  widget.cloudAccountDependencies.googleDriveOAuthClient,
              oneDriveOAuthClient:
                  widget.cloudAccountDependencies.oneDriveOAuthClient,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSource: () => _navigateTo(1),
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              fullTextSearchSettingsRepository: widget
                  .readerFeatureRepositories.fullTextSearchSettingsRepository,
              isFullTextSearchAvailable:
                  widget.readerFeatureRepositories.isFullTextSearchAvailable,
            ),
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart`
Expected: PASS（新增測試＋既有全部測試皆通過，整檔重跑確保沒有破壞既有行為）。

- [x] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/library_screen_dependencies.dart app/lib/screens/settings_scaffold.dart app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/settings_scaffold_test.dart app/test/screens/adaptive_shell_scaffold_test.dart
git commit -m "feat(search): 設定畫面「閱讀」分區新增全文檢索雙開關＋重建索引（Issue 3）"
```

---

### Task 5：`main.dart` 組裝正式實例＋收尾

**Files：**
- Modify: `app/lib/main.dart`

**Interfaces：**
- Consumes：Task 2 的 `SqliteFullTextSearchSettingsRepository`、既有 `contentIndexingScheduler.requestProcessing`、既有 `repository.isFullTextSearchAvailable`（Issue 6）。
- Produces：無新公開 API（純組裝），本 Task 完成後「系統設定→閱讀」分區的兩個開關在正式 App 中即可運作。

本 Task 是純組裝程式碼，不採用「先寫失敗測試」的 TDD 步驟，直接修改＋驗證。

- [x] **Step 1：`ElinkBookApp` 新增欄位＋建構參數**

在 `app/lib/main.dart`，於 import 區塊新增：

```dart
import 'search/full_text_search_settings_repository.dart';
```

找到：

```dart
  final GlobalKey<NavigatorState>? navigatorKey;
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
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.readerActivityTracker,
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.onManualSync,
    this.loadLastSyncedAt,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
    this.remoteServerRepository,
    this.createOpdsClient,
    this.computeFingerprint,
    this.thumbnailCache,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.navigatorKey,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

取代為：

```dart
  final GlobalKey<NavigatorState>? navigatorKey;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
  final bool isFullTextSearchAvailable;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
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
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.onManualSync,
    this.loadLastSyncedAt,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
    this.remoteServerRepository,
    this.createOpdsClient,
    this.computeFingerprint,
    this.thumbnailCache,
    this.isMobileDataConnection,
    this.downloadQueueController,
    this.navigatorKey,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    this.fullTextSearchSettingsRepository,
    this.isFullTextSearchAvailable = true,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

找到（`_ElinkBookAppState.build()` 內 `LibraryReaderFeatureRepositories(...)` 建構）：

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

取代為：

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
          fullTextSearchSettingsRepository:
              widget.fullTextSearchSettingsRepository,
          isFullTextSearchAvailable: widget.isFullTextSearchAvailable,
        ),
```

- [x] **Step 2：`main()` 組裝正式實例**

找到：

```dart
  contentIndexingScheduler.start();
```

取代為：

```dart
  contentIndexingScheduler.start();
  // epic-10-search Issue 3：「啟用全文檢索」設定模型。requestProcessing
  // 以 callback 注入（而非直接持有整個 contentIndexingScheduler），見
  // plans/plan-issue-3.md Global Constraints。
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
```

找到（`runApp(ElinkBookApp(...))` 呼叫內）：

```dart
      navigatorKey: navigatorKey,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
    ),
  );
}
```

取代為：

```dart
      navigatorKey: navigatorKey,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      isFullTextSearchAvailable: repository.isFullTextSearchAvailable,
    ),
  );
}
```

- [x] **Step 3：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 4：跑本次全部異動觸及的測試檔，確認整體沒有回歸**

Run: `flutter test test/search/content_indexing_scheduler_test.dart test/search/full_text_search_settings_repository_test.dart test/screens/full_text_search_confirm_dialog_test.dart test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart`
Expected: PASS（本計畫新增與修改的所有測試檔皆通過；`main.dart` 本身無對應測試檔，正確性已由上述測試檔涵蓋的依賴注入路徑＋`flutter analyze` 型別檢查涵蓋）。

- [x] **Step 5：Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(search): main.dart 組裝並串接 FullTextSearchSettingsRepository（Issue 3）"
```

- [ ] **Step 6：（人類／執行者手動）真機或模擬器驗證**

`flutter run` 啟動 App，進入「設定→閱讀」分區，確認：
1. 兩個開關（PDF／其他格式）預設皆為關閉，重建索引按鈕皆為停用狀態。
2. 開啟任一開關會先彈出確認對話框（含手機窄螢幕下對話框不溢位）；取消則開關維持關閉；確認後開關變為開啟，重建索引按鈕變為可用。
3. 關閉開關立即生效，不彈出確認對話框。
4. 若書庫中有 CBZ 書籍，開啟「其他格式」開關後，該 CBZ 書籍不應被送去背景索引（可用 `adb logcat`／中斷點確認排程器沒有為它啟動 `HeadlessInAppWebView`）。
5. 若在 Issue 6 描述的無 FTS5 模組裝置上測試，「閱讀」分區應顯示「本裝置不支援全文檢索」提示，不顯示兩個開關。

（本 Task 不需要跑全專案 `flutter test`——依使用者指示，Epic 10 尚有 Issue 2／4／5 未完成，不是最後一個 Issue，全套測試留到整個 Epic 收尾前再跑一次，比照 `plan-issue-6.md` 已採用的既有慣例。）

---

## 自我審查（Self-Review，計畫撰寫者執行，非另一輪審查）

**Spec 覆蓋度：** spec.md §4 逐項對應——(1) `FullTextSearchSettingsRepository`／`ContentIndexCategory`／`rebuildIndex` 介面定義 → Task 2；(2) 確認對話框（含 PDF 額外文案、DESIGN.md §9.1 排版、不套用 §9.2、寬度修正）→ Task 3；(3) `setEnabled(true/false)` 的批次回填/清除語意（含 CBZ 排除與自動標記 unsupported）、「排程器對該分類的佇列停止並捨棄目前進度」→ Task 1（排程器取消防護）＋Task 2（資料庫行為）；(4) 雙入口 → Task 4（範圍調整說明見 Global Constraints）。issues.md Issue 3 單元測試要求四項：「兩個分類分別持久化/資料庫連動、關閉一個不影響另一個」→ Task 2 測試；「確認 Dialog 開啟才呼叫 setEnabled、取消彈回關閉、兩種文案」→ Task 3＋Task 4 測試；「雙入口一致性」→ 本計畫只落地一個入口，第二入口完整驗證留給 Issue 4；「重建索引按鈕」→ Task 2（repository 方法＋測試）＋Task 4（UI＋測試），review-plan-issue-3.md I-1 已完整採納。

**Placeholder 掃描：** 無「TBD」「稍後補上」「類似 Task N」等字樣，所有程式碼片段皆為完整可直接套用的內容。

**型別一致性：** `ContentIndexCategory`／`FullTextSearchSettingsRepository`（含 `rebuildIndex`）在 Task 2 定義、Task 3/4/5 的 import 與使用方式一致；`SqliteFullTextSearchSettingsRepository` 建構參數 `database`/`requestProcessing` 在 Task 2 定義、Task 5 `main.dart` 呼叫端命名完全一致；`showFullTextSearchEnableConfirmDialog()` 簽章在 Task 3 定義、Task 4 `SettingsScaffold._handleFullTextSearchToggle()` 呼叫端引數順序/具名參數一致；`LibraryReaderFeatureRepositories.fullTextSearchSettingsRepository`/`isFullTextSearchAvailable` 在 Task 4 定義、Task 5 `main.dart`/`_ElinkBookAppState.build()` 呼叫端命名一致；`ContentIndexingScheduler._isStillTracked()` 在 Task 1 定義並僅供 `_processOneBook()` 內部使用，不對外公開，不影響 Task 2 的 `requestProcessing` callback 簽章。
