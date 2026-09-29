import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reading_stats_tracker_harness.dart';

void main() {
  group('回溯採計與退出結算', () {
    test('開書後 90 秒才翻頁再讀 80 秒退出，共記 170 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(90);
        h.tracker.recordActivity();
        h.elapseSeconds(80);
        expect(h.closeAndSettle(), isTrue);
        expect(h.total(), 170);
        h.dispose();
      });
    });

    test('開書後從未有活動就退出，記 0 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(60);
        expect(h.closeAndSettle(), isTrue);
        expect(h.writes, isEmpty);
        h.dispose();
      });
    });

    test('首次活動距開書超過門檻：不回溯，從該次活動起算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(300);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('首次活動剛好在門檻上（120 秒）仍回溯採計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(120);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.total(), 120);
        h.dispose();
      });
    });

    test('退出時距最後一次活動仍在門檻內：尾段計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(100);
        h.closeAndSettle();
        expect(h.total(), 100);
        h.dispose();
      });
    });

    test('退出時距最後一次活動剛好 120 秒：尾段仍計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 確認 10 秒
        h.elapseSeconds(120); // 第 130 秒（第 120 秒的看門狗觸發時只距 110 秒）
        h.closeAndSettle();
        expect(h.total(), 130);
        h.dispose();
      });
    });

    test('退出時距最後一次活動已超過門檻：尾段整段丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(200);
        h.closeAndSettle();
        expect(h.total(), 30);
        h.dispose();
      });
    });
  });

  group('閒置與暫態時間', () {
    test('放下手機發呆：寫入總量為 0、計時器已取消、之後不再寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(600);
        expect(h.total(), 0);
        expect(async.pendingTimers, isEmpty);
        final attempts = h.flushAttempts;
        h.elapseSeconds(600);
        expect(h.flushAttempts, attempts);
        h.dispose();
      });
    });

    test('看門狗在距最後一次活動剛好 120 秒時轉為閒置並取消計時器', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(90);
        expect(async.pendingTimers, isNotEmpty);
        h.elapseSeconds(30); // 第 120 秒：剛好達門檻
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('閒置前已被後續活動確認的部分保留，其後的空檔不寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 確認 60 秒
        h.elapseSeconds(600);
        expect(h.total(), 60);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('超過門檻的空檔整段丟棄，不是只截到門檻長度', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 確認 60 秒
        h.elapseSeconds(300); // 中途已轉為 idle
        h.tracker.recordActivity(); // 重新起算，這 300 秒不計
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('閒置後再次活動：回到計時中並重新建立計時器', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(600);
        expect(async.pendingTimers, isEmpty);
        h.tracker.recordActivity();
        expect(async.pendingTimers, isNotEmpty);
        h.elapseSeconds(20);
        h.closeAndSettle();
        expect(h.total(), 20);
        h.dispose();
      });
    });
  });

  group('寫入節流與計時器', () {
    test('每 30 秒把已確認的秒數寫入一次並歸零', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        h.elapseSeconds(10); // 第 30 秒：寫入 20
        expect(h.writes.map((w) => w.seconds), [20]);
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 30 秒（第 20～50 秒）
        h.elapseSeconds(10); // 第 60 秒：寫入 30
        expect(h.writes.map((w) => w.seconds), [20, 30]);
        expect(h.writes.first.bookId, 'book-1');
        expect(h.writes.first.bookTitle, '測試書');
        h.dispose();
      });
    });

    test('尚未被確認的暫態時間不會被 30 秒定時器寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(90); // 期間沒有任何活動：全是暫態
        expect(h.writes, isEmpty);
        h.tracker.recordActivity(); // 這時才確認 90 秒
        h.elapseSeconds(30);
        expect(h.total(), 90);
        h.dispose();
      });
    });

    test('計時器按需啟動：開書未活動時不存在，活動後才建立，結束即釋放', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        expect(async.pendingTimers, isEmpty);
        h.tracker.recordActivity();
        expect(async.pendingTimers, isNotEmpty);
        h.closeAndSettle();
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('寫入回呼失敗：秒數保留，下次成功時一併寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.flushError = StateError('database is locked');
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        h.elapseSeconds(10); // 第 30 秒：寫入失敗
        expect(h.flushAttempts, 1);
        expect(h.writes, isEmpty);
        h.flushError = null;
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 再確認 30 秒，合計 50
        h.elapseSeconds(10); // 第 60 秒：成功
        expect(h.writes.map((w) => w.seconds), [50]);
        h.dispose();
      });
    });

    test('寫入重疊時依序送出，不重複也不遺漏', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        final gate = Completer<void>();
        h.flushGate = gate;
        h.elapseSeconds(10); // 第 30 秒：送出 20 秒，卡在資料庫
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 再確認 30 秒
        h.elapseSeconds(10); // 第 60 秒：上一批還沒完成
        expect(h.flushAttempts, 1);
        h.flushGate = null;
        gate.complete();
        async.flushMicrotasks();
        expect(h.writes.map((w) => w.seconds), [20, 30]);
        h.dispose();
      });
    });
  });

  group('子秒精度', () {
    test('連續五次間隔 400 毫秒的活動，餘額累積後共 2 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        for (var i = 0; i < 5; i++) {
          h.elapse(const Duration(milliseconds: 400));
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 2);
        h.dispose();
      });
    });

    test('不滿整秒的餘額不寫入（1.2 秒只寫 1 秒）', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        for (var i = 0; i < 3; i++) {
          h.elapse(const Duration(milliseconds: 400));
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 1);
        h.dispose();
      });
    });

    test('同一時刻大量活動：不崩潰、不多算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        for (var i = 0; i < 100; i++) {
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });
  });

  group('時鐘防護', () {
    test('時鐘倒撥：不產生負值，之後從倒撥後的時間重新累計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(10);
        h.skew = const Duration(hours: -1); // 倒撥一小時
        h.tracker.recordActivity(); // 倒撥：這一段不計，重新起算
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.closeAndSettle();
        expect(h.total(), 30);
        expect(h.writes.every((w) => w.seconds > 0), isTrue);
        h.dispose();
      });
    });

    test('時鐘快轉一天：這一段整段丟棄，不產生巨量秒數', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.skew = const Duration(days: 1);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });

    test('倒撥跨日：只終止前段，不向過去的日期寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59));
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 9/29 確認 30 秒
        h.jumpTo(DateTime(2026, 9, 28, 12)); // 倒撥到前一天
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 落在 9/28：不寫
        h.closeAndSettle();
        expect(h.total('2026-09-28'), 0);
        expect(h.total('2026-09-29'), 30);
        h.dispose();
      });
    });
  });

  group('跨午夜', () {
    test('確認區間跨越午夜：以本地午夜切成前後兩天', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59, 30));
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 23:59:30 → 00:00:30
        h.closeAndSettle();
        expect(h.total('2026-09-29'), 30);
        expect(h.total('2026-09-30'), 30);
        expect(h.writes.every((w) => w.bookId == 'book-1'), isTrue);
        h.dispose();
      });
    });

    test('間隔超過門檻的跨午夜：不切分，直接丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 58));
        h.tracker.recordActivity();
        h.elapseSeconds(300);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.writes, isEmpty);
        h.dispose();
      });
    });

    test('退出的尾段跨越午夜：一樣切成兩天', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59, 50));
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.closeAndSettle();
        expect(h.total('2026-09-29'), 10);
        expect(h.total('2026-09-30'), 10);
        h.dispose();
      });
    });
  });

  group('清除統計', () {
    test('收到 onCleared 後，清除前的確認與暫態秒數全部丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒（尚未被 30 秒定時器寫入）
        h.cleared.add(null);
        h.elapseSeconds(10); // 清除後才讀的 10 秒
        h.closeAndSettle();
        expect(h.total(), 10);
        h.dispose();
      });
    });

    test('清除當下有寫入在途：在途批次完成後不會扣到清除後新累積的秒數', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        final gate = Completer<void>();
        h.flushGate = gate;
        h.elapseSeconds(10); // 第 30 秒：送出 20 秒，卡在資料庫
        h.elapseSeconds(5);
        h.cleared.add(null); // 清除：緩衝丟棄
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 清除後確認 10 秒
        h.flushGate = null;
        gate.complete(); // 在途的舊批次（已在資料庫佇列，已知限制）完成
        async.flushMicrotasks();
        h.closeAndSettle();
        expect(h.writes.last.seconds, 10);
        expect(h.writes.every((w) => w.seconds > 0), isTrue);
        h.dispose();
      });
    });

    test('多日期緩衝：在途批次失敗又遇清除，清除後的秒數不會被寫兩次', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59, 50));
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認：9/29 10 秒、9/30 10 秒
        final gate = Completer<void>();
        h.flushGate = gate;
        h.elapseSeconds(10); // 第 30 秒：開始寫 9/29，卡在資料庫
        h.cleared.add(null); // 清除：緩衝丟棄
        h.elapseSeconds(5);
        h.tracker.recordActivity(); // 清除後在 9/30 確認 5 秒
        h.flushGate = null;
        h.failNextFlush = true; // 在途的 9/29 寫入失敗
        gate.complete();
        async.flushMicrotasks();
        h.closeAndSettle();
        expect(h.total('2026-09-30'), 5);
        expect(h.writes.length, 1);
        h.dispose();
      });
    });
  });

  group('生命週期', () {
    test('flushAndClose 完成後尾段已寫入、計時器已釋放；其後 dispose 與再次活動都不會寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity();
        expect(h.closeAndSettle(), isTrue);
        expect(h.total(), 20);
        expect(async.pendingTimers, isEmpty);
        final count = h.writes.length;
        h.tracker.dispose();
        h.tracker.recordActivity();
        expect(async.pendingTimers, isEmpty); // 關閉後的活動不得重新建立計時器
        expect(h.closeAndSettle(), isTrue); // 重複呼叫也安全
        h.elapseSeconds(600);
        expect(h.writes.length, count);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('dispose 是同步的，且不會把未寫入的秒數寫出去', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒，尚未寫入
        h.tracker.dispose();
        expect(async.pendingTimers, isEmpty);
        h.elapseSeconds(600);
        expect(h.flushAttempts, 0);
        h.dispose();
      });
    });

    test('dispose 取消 onCleared 訂閱，不再持有監聽', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        expect(h.cleared.hasListener, isTrue);
        h.tracker.dispose();
        expect(h.cleared.hasListener, isFalse);
        h.dispose();
      });
    });

    test('flushAndClose 也會取消 onCleared 訂閱', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        expect(h.closeAndSettle(), isTrue);
        expect(h.cleared.hasListener, isFalse);
        h.dispose();
      });
    });
  });
}
