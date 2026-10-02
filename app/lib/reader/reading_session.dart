import 'dart:async';

import '../stats/reading_stats_repository.dart';
import '../stats/reading_stats_tracker.dart';
import '../sync/sync_checkpoint_trigger.dart';
import 'book_format.dart';
import 'epub_position_info.dart';
import 'pdf_page_info.dart';
import 'reader_activity_tracker.dart';
import 'reader_prefs_manager.dart';
import 'reading_position_saver.dart';

/// 一次閱讀會話（見 `CONTEXT.md`「閱讀會話」，`epic-54-architecture-optimization`
/// Issue 8）：從閱讀畫面開啟到離開，一個畫面對應一本書。
///
/// 負責與「這次閱讀的資料」有關的事：閱讀統計的起訖、閱讀活動判定、進入
/// 背景與回到前景的處置、離開與定期觸發的 Checkpoint 同步、離開時儲存閱讀
/// 位置。與裝置畫面狀態有關的事（音量鍵、螢幕方向、全螢幕、朗讀播放）不屬於
/// 會話。呼叫端在 `initState` 建立並呼叫 [start]，之後只轉發事件。
///
/// 不等待任何儲存或統計寫入完成；沒趕上的位置由下一次 Checkpoint 補送。
class ReadingSession {
  ReadingSession({
    required this.bookId,
    required this.prefsManager,
    required this.hasJumpTarget,
    this.bookTitle,
    ReadingStatsTracker? statsTracker,
    ReadingStatsRepository? statsRepository,
    this.syncCheckpointTrigger,
    this.readerActivityTracker,
    this.checkpointInterval = const Duration(minutes: 5),
  }) : _stats = statsTracker ??
            _statsTrackerFor(bookId, bookTitle ?? bookId, statsRepository);

  final String bookId;
  final ReaderPrefsManager prefsManager;

  /// 開書時是否帶有跳轉目標（例如從搜尋結果、書籤開啟）。
  final bool hasJumpTarget;

  /// 統計用的書名快照（原始書名，不經簡繁轉換）；未提供時退回 [bookId]。
  final String? bookTitle;

  final SyncCheckpointTrigger? syncCheckpointTrigger;
  final ReaderActivityTracker? readerActivityTracker;
  final Duration checkpointInterval;

  /// 兩個統計來源皆未提供時為 null（完全不計時，所有統計呼叫為無動作）。
  final ReadingStatsTracker? _stats;

  /// 偏好載入完成後（取得開書時既有的進度）才建立，見 [onPrefsLoaded]。
  ReadingPositionSaver? _positionSaver;

  Timer? _checkpointTimer;

  /// 上一次 Foliate／PDF 位置回報，只用來判斷「這次算不算閱讀活動」。
  EpubPositionInfo? _lastEpubInfo;
  bool _hasPdfInfo = false;

  /// 標記閱讀畫面已開啟，並在有 [syncCheckpointTrigger] 時建立週期性 Checkpoint
  /// Timer。單純的週期性 Timer，不判斷使用者是否真的有互動；未提供 trigger
  /// 時完全不建立。
  void start() {
    readerActivityTracker?.markReaderOpened();
    final trigger = syncCheckpointTrigger;
    if (trigger != null) {
      _checkpointTimer =
          Timer.periodic(checkpointInterval, (_) => trigger.trigger());
    }
  }

  /// 偏好載入完成：以開書時既有位置的進度建立位置儲存器。
  void onPrefsLoaded({required double initialProgress}) {
    _positionSaver = ReadingPositionSaver(
      bookId: bookId,
      prefsManager: prefsManager,
      hasJumpTarget: hasJumpTarget,
      initialProgress: initialProgress,
    );
  }

  /// Foliate 格式的位置回報。位置真正改變（cfi 或 index 不同）才算閱讀活動：
  /// 開書後第一次回報是初始定位；位置相同的重複回報是 Foliate 開書後套用樣式
  /// 重排、或圖片／字型載入後重新對齊錨點所派發的，不是使用者操作。只比 cfi
  /// 與 index、忽略 fraction——真機日誌實證重排時同一 cfi 的 fraction 會來回
  /// 微幅抖動（比較規則見 `EpubPositionInfo.positionKey`，與位置儲存器共用）。
  void onEpubLocated(EpubPositionInfo info) {
    _positionSaver?.onEpubLocated(info);
    final previous = _lastEpubInfo;
    if (previous != null && previous.positionKey != info.positionKey) {
      _stats?.recordActivity();
    }
    _lastEpubInfo = info;
  }

  /// PDF 的頁碼回報。開書後第一次回報是初始定位，第二次起才算閱讀活動。
  void onPdfPageChanged(PdfPageInfo info) {
    _positionSaver?.onPdfPageChanged(info);
    if (_hasPdfInfo) _stats?.recordActivity();
    _hasPdfInfo = true;
  }

  /// 回報一次閱讀活動（長按劃線、翻頁熱區等）。單純點擊叫出工具列不呼叫。
  void recordActivity() => _stats?.recordActivity();

  /// 回報朗讀（TTS）是否正在播放。統計對重複回報相同狀態是冪等的。
  void onTtsPlayingChanged(bool isPlaying) =>
      _stats?.onTtsPlayingChanged(isPlaying);

  /// App 進入背景（`AppLifecycleState.paused`，不含 `inactive`）：先通知統計，
  /// 再儲存閱讀位置。**不觸發 Checkpoint。**
  void onAppPaused(BookFormat format) {
    _stats?.onEnteredBackground();
    _positionSaver?.save(format);
  }

  /// App 回到前景。
  void onAppResumed() => _stats?.onReturnedToForeground();

  /// 離開閱讀畫面。順序固定：標記關閉 → 統計 flush → 取消 Timer → 儲存位置 →
  /// 觸發 Checkpoint。儲存位置排在觸發 Checkpoint 之前，讓剛寫入的最新位置有
  /// 較高機率被這次 Checkpoint 判定為待推送；但兩者皆不 await，並不保證
  /// SQLite 寫入已落地，沒趕上的會延到下一次 Checkpoint 才推送，不會遺失。
  /// 未登入或已有 Checkpoint 執行中時 `trigger()` 內部會直接放棄，不拋例外。
  void close(BookFormat format) {
    readerActivityTracker?.markReaderClosed();
    final stats = _stats;
    if (stats != null) unawaited(stats.flushAndClose());
    _checkpointTimer?.cancel();
    _positionSaver?.save(format);
    syncCheckpointTrigger?.trigger();
  }

  /// 有注入的 tracker 直接使用（呼叫端已處理）；否則有 repository 就以本書 id、
  /// 書名與 repository 的寫入方法、`onCleared` 建立；兩者皆無回傳 null。
  static ReadingStatsTracker? _statsTrackerFor(
    String bookId,
    String bookTitle,
    ReadingStatsRepository? repository,
  ) {
    if (repository == null) return null;
    return ReadingStatsTracker(
      bookId: bookId,
      bookTitle: bookTitle,
      onFlush: (date, id, title, seconds) => repository.addReadingSeconds(
        date: date,
        bookId: id,
        bookTitle: title,
        seconds: seconds,
      ),
      onCleared: repository.onCleared,
    );
  }
}
