import 'package:fake_async/fake_async.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_session.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';

/// 把所有互動記進同一份 log，才能驗證跨物件的先後順序。
class _FakeStatsTracker extends ReadingStatsTracker {
  _FakeStatsTracker(this.log)
      : super(
          bookId: 'b1',
          bookTitle: '書',
          onFlush: (date, bookId, bookTitle, seconds) async {},
        );
  final List<String> log;

  @override
  void recordActivity() => log.add('activity');
  @override
  void onEnteredBackground() => log.add('background');
  @override
  void onReturnedToForeground() => log.add('foreground');
  @override
  void onTtsPlayingChanged(bool isPlaying) => log.add('tts:$isPlaying');
  @override
  Future<void> flushAndClose() async => log.add('flush');
}

class _LoggingPrefs extends FakeReaderPrefsManager {
  _LoggingPrefs(this.log);
  final List<String> log;

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) {
    log.add('save');
    return super.saveReadingPosition(bookId, position);
  }
}

/// 在 fakeAsync 內同步取得 Future 的結果（先 flushMicrotasks 再讀）。
T _resolve<T>(FakeAsync async, Future<T> future) {
  late T value;
  future.then((v) => value = v);
  async.flushMicrotasks();
  return value;
}

EpubPositionInfo _loc(String cfi, {int index = 0, double fraction = 0.1}) =>
    EpubPositionInfo(
      locatorJson: '{"cfi":"$cfi","index":$index,"fraction":$fraction}',
      progression: fraction,
    );

void main() {
  late List<String> log;
  late _LoggingPrefs prefs;

  setUp(() {
    log = [];
    prefs = _LoggingPrefs(log);
  });

  SyncCheckpointTrigger buildTrigger() => SyncCheckpointTrigger(
        runCheckpoint: () async {
          log.add('trigger');
          return SyncCheckpointResult.synced;
        },
      );

  ReadingSession build({
    bool hasJumpTarget = false,
    bool withStats = true,
    bool withTrigger = true,
    ReaderActivityTracker? activity,
  }) =>
      ReadingSession(
        bookId: 'b1',
        prefsManager: prefs,
        hasJumpTarget: hasJumpTarget,
        statsTracker: withStats ? _FakeStatsTracker(log) : null,
        syncCheckpointTrigger: withTrigger ? buildTrigger() : null,
        readerActivityTracker: activity,
      );

  group('離開（close）的收尾順序', () {
    test('markReaderClosed → 統計 flush → 儲存位置 → 觸發 Checkpoint', () {
      final activity = ReaderActivityTracker();
      activity.addListener(
          () => log.add(activity.isReaderOpen ? 'opened' : 'closed'));
      final session = build(activity: activity)..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 10));
      log.clear(); // 只看 close 之後的事件，並排除 start 的 'opened'

      session.close(BookFormat.pdf);

      expect(log, ['closed', 'flush', 'save', 'trigger']);
    });

    test('偏好尚未載入完成就離開：不儲存、不拋例外，仍結算統計並觸發 Checkpoint', () {
      final session = build()..start();
      log.clear();
      session.close(BookFormat.pdf);
      expect(log, ['flush', 'trigger']);
    });

    test('沒有統計與 trigger 也能安全離開', () {
      final session = build(withStats: false, withTrigger: false)..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      session.close(BookFormat.pdf);
      expect(log, ['save']);
    });

    test('readerActivityTracker：start 標記開啟、close 標記關閉', () {
      final activity = ReaderActivityTracker();
      final session = build(activity: activity);
      expect(activity.isReaderOpen, isFalse);
      session.start();
      expect(activity.isReaderOpen, isTrue);
      session.close(BookFormat.pdf);
      expect(activity.isReaderOpen, isFalse);
    });
  });

  group('前後景', () {
    test('paused：統計進背景 → 儲存位置，且不觸發 Checkpoint', () {
      final session = build()..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      log.clear();

      session.onAppPaused(BookFormat.pdf);

      expect(log, ['background', 'save']);
    });

    test('paused 時偏好尚未載入：只通知統計，不儲存、不拋例外', () {
      final session = build()..start();
      log.clear();
      session.onAppPaused(BookFormat.pdf);
      expect(log, ['background']);
    });

    test('resumed：通知統計回到前景', () {
      final session = build()..start();
      log.clear();
      session.onAppResumed();
      expect(log, ['foreground']);
    });
  });

  group('Checkpoint 週期 Timer', () {
    test('每 5 分鐘觸發一次，離開後不再觸發', () {
      fakeAsync((async) {
        final session = build()..start();
        async.elapse(const Duration(minutes: 5));
        expect(log.where((e) => e == 'trigger'), hasLength(1));
        async.elapse(const Duration(minutes: 5));
        expect(log.where((e) => e == 'trigger'), hasLength(2));

        session.close(BookFormat.pdf); // close 本身會再觸發一次
        final afterClose = log.where((e) => e == 'trigger').length;
        async.elapse(const Duration(minutes: 30));
        expect(log.where((e) => e == 'trigger').length, afterClose);
      });
    });

    test('未提供 trigger：不建立 Timer，經過任意時間也不拋例外', () {
      fakeAsync((async) {
        final session = build(withTrigger: false)..start();
        async.elapse(const Duration(minutes: 30));
        expect(log, isNot(contains('trigger')));
        session.close(BookFormat.pdf);
      });
    });
  });

  group('閱讀活動判定：Foliate', () {
    test('首次回報（初始定位）不算活動', () {
      final session = build()..start();
      log.clear();
      session.onEpubLocated(_loc('a'));
      expect(log, isNot(contains('activity')));
    });

    test('同 cfi 與 index 的重複回報不算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a'));
      log.clear();
      session.onEpubLocated(_loc('a'));
      expect(log, isNot(contains('activity')));
    });

    test('同 cfi 只有 fraction 抖動不算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a', fraction: 0.10));
      log.clear();
      session.onEpubLocated(_loc('a', fraction: 0.11));
      expect(log, isNot(contains('activity')));
    });

    test('cfi 改變才算活動；重複回報夾在中間不影響之後的判定', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a'));
      session.onEpubLocated(_loc('a', fraction: 0.2));
      log.clear();
      session.onEpubLocated(_loc('b'));
      expect(log, ['activity']);
    });

    test('index 改變也算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a', index: 0));
      log.clear();
      session.onEpubLocated(_loc('a', index: 1));
      expect(log, ['activity']);
    });

    test('locatorJson 無法解析時退回整段字串比較', () {
      final session = build()..start();
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-1'));
      log.clear();
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-1'));
      expect(log, isNot(contains('activity')));
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-2'));
      expect(log, ['activity']);
    });
  });

  group('閱讀活動判定：PDF', () {
    test('首次頁碼回報不算，第二次起算', () {
      final session = build()..start();
      log.clear();
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      expect(log, isNot(contains('activity')));
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      expect(log, ['activity']);
    });
  });

  group('位置回報轉發給位置儲存器', () {
    test('Foliate 回報在 paused 時被儲存', () {
      final session = build()..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onEpubLocated(_loc('a', fraction: 0.4));
      session.onAppPaused(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson,
          contains('"cfi":"a"'));
    });

    test('有跳轉目標：只有首次回報就離開，不儲存', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      session.close(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('有跳轉目標：Foliate 同位置重複回報（fraction 抖動）就離開，不儲存', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.onEpubLocated(_loc('j', fraction: 0.21));
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.close(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('有跳轉目標：Foliate cfi 真的改變後離開，儲存最新位置', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.onEpubLocated(_loc('k', fraction: 0.30));
      session.close(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson,
          contains('"cfi":"k"'));
    });

    test('偏好載入前收到的位置回報不會讓位置儲存器之後誤存', () {
      final session = build()..start();
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 4, totalPages: 5));
      session.onPrefsLoaded(initialProgress: 0);
      session.close(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('統計來源（正式環境只傳 statsRepository，由 session 建立 tracker）', () {
    // 計時語意比照 reader_screen_stats_activity_test：開書後 10 秒出現第一次
    // 活動（回溯採計 10 秒），再過 20 秒離開（尾段採計 20 秒），共 30 秒。
    test('僅提供 statsRepository：離開時把閱讀秒數與書名寫入 repository', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          bookTitle: '自訂書名',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        expect(_resolve(async, repository.getTotalReadingSeconds()), 30);
        final date = _resolve(
          async,
          repository.getDailyTotals(startDate: '0000-01-01', endDate: '9999-12-31'),
        ).keys.single;
        final stats = _resolve(async, repository.getBookStatsForDate(date));
        expect(stats.single.bookId, 'b1');
        expect(stats.single.bookTitle, '自訂書名');
      });
    });

    test('未提供書名：統計以 bookId 作為書名快照', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        final date = _resolve(
          async,
          repository.getDailyTotals(startDate: '0000-01-01', endDate: '9999-12-31'),
        ).keys.single;
        final stats = _resolve(async, repository.getBookStatsForDate(date));
        expect(stats.single.bookTitle, 'b1');
      });
    });

    test('同時提供 statsTracker 與 statsRepository：以注入的 tracker 為準，repository 不被寫入', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsTracker: _FakeStatsTracker(log),
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        // 注入的 tracker 收到全部事件（若 session 另外建了 repository 版 tracker
        // 而忽略注入者，這裡會缺事件）；repository 完全沒有被寫入。
        expect(log, ['activity', 'flush']);
        expect(_resolve(async, repository.getTotalReadingSeconds()), 0);
      });
    });
  });

  group('其他事件的轉發', () {
    test('recordActivity 與 onTtsPlayingChanged 轉給統計', () {
      final session = build()..start();
      log.clear();
      session.recordActivity();
      session.onTtsPlayingChanged(true);
      session.onTtsPlayingChanged(false);
      expect(log, ['activity', 'tts:true', 'tts:false']);
    });

    test('沒有統計 tracker 時所有統計事件皆為無動作', () {
      final session = build(withStats: false)..start();
      session.recordActivity();
      session.onTtsPlayingChanged(true);
      session.onAppPaused(BookFormat.pdf);
      session.onAppResumed();
      session.onEpubLocated(_loc('a'));
      session.onEpubLocated(_loc('b'));
      expect(log, isEmpty);
    });
  });
}
