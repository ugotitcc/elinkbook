import 'dart:async';

import 'package:clock/clock.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:fake_async/fake_async.dart';

/// 一次寫入回呼的紀錄。
class FlushCall {
  const FlushCall(this.date, this.bookId, this.bookTitle, this.seconds);

  final String date;
  final String bookId;
  final String bookTitle;
  final int seconds;

  @override
  String toString() => '$date/$bookId/$bookTitle/$seconds 秒';
}

/// tracker 測試共用工具：
/// - 時鐘 = 起始時間 + fakeAsync 已經過時間 + 可手動設定的偏移（模擬倒撥／快轉）。
/// - 寫入回呼把成功的寫入記在 [writes]；可注入失敗（[flushError]）或延遲（[flushGate]）。
class TrackerHarness {
  TrackerHarness(this.async, {DateTime? startTime})
      : start = startTime ?? DateTime(2026, 9, 29, 10) {
    tracker = ReadingStatsTracker(
      bookId: 'book-1',
      bookTitle: '測試書',
      onFlush: _onFlush,
      onCleared: cleared.stream,
      clock: Clock(_now),
    );
  }

  final FakeAsync async;
  final DateTime start;

  /// 手動時鐘偏移；正值為快轉，負值為倒撥。
  Duration skew = Duration.zero;

  final List<FlushCall> writes = [];

  /// 寫入回呼被呼叫的次數（含失敗）。
  int flushAttempts = 0;

  /// 非 null 時，寫入回呼拋出它。
  Object? flushError;

  /// 為 true 時，下一次寫入回呼失敗一次後自動恢復（模擬資料庫暫時性錯誤）。
  bool failNextFlush = false;

  /// 非 null 時，寫入回呼會先等它完成（模擬很慢的資料庫）。
  Completer<void>? flushGate;

  final StreamController<void> cleared = StreamController<void>.broadcast(sync: true);

  late final ReadingStatsTracker tracker;

  DateTime _now() => start.add(async.elapsed).add(skew);

  /// 目前（含偏移）的假時鐘時間。
  DateTime get now => _now();

  /// 把時鐘直接撥到指定時間（不推進 fakeAsync 的計時器）。
  void jumpTo(DateTime target) {
    skew = target.difference(start.add(async.elapsed));
  }

  Future<void> _onFlush(String date, String bookId, String bookTitle, int seconds) async {
    flushAttempts++;
    final gate = flushGate;
    if (gate != null) await gate.future;
    if (failNextFlush) {
      failNextFlush = false;
      throw StateError('暫時性寫入失敗');
    }
    final error = flushError;
    if (error != null) throw error;
    writes.add(FlushCall(date, bookId, bookTitle, seconds));
  }

  /// 推進時間並讓所有微任務（含非同步寫入）跑完。
  void elapse(Duration duration) {
    async.elapse(duration);
    async.flushMicrotasks();
  }

  void elapseSeconds(int seconds) => elapse(Duration(seconds: seconds));

  /// 指定日期（省略則全部）已成功寫入的總秒數。
  int total([String? date]) => writes
      .where((w) => date == null || w.date == date)
      .fold(0, (sum, w) => sum + w.seconds);

  /// 呼叫 flushAndClose 並跑完微任務；回傳它是否已完成。
  bool closeAndSettle() {
    var done = false;
    tracker.flushAndClose().then((_) => done = true);
    async.flushMicrotasks();
    return done;
  }

  void dispose() {
    tracker.dispose();
    cleared.close();
  }
}
