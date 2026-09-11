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
    var cancelled = false;

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
}
