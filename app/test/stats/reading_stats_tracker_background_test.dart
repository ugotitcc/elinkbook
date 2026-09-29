import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reading_stats_tracker_harness.dart';

void main() {
  group('進入背景（TTS 非播放中）', () {
    test('立即結算並寫入，計時器釋放', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 尾段 20 秒確認並寫入
        async.flushMicrotasks();
        expect(h.total(), 50);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('回前景後第一次活動不回溯，也不重複結算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 共 50 秒
        h.elapseSeconds(5);
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 進背景前後的空檔一律不計
        h.elapseSeconds(10);
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('背景中的雜散活動事件不採計：回前景後的第一次活動也不回溯背景空檔', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 共 50 秒
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 暫停後才到達的雜散事件（例如頁面遲報的捲動結束）
        h.elapseSeconds(100);
        h.tracker.onReturnedToForeground();
        h.tracker.recordActivity(); // 使用者回來翻頁：背景的 110 秒不能算進去
        h.elapseSeconds(10);
        h.closeAndSettle();
        expect(h.total(), 60);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('背景中開始播放 TTS（通知欄、耳機）仍算活動並持續計時', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 20 秒
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(true); // 從這裡起算，不回溯前 10 秒
        h.elapseSeconds(30);
        h.tracker.onTtsPlayingChanged(false);
        async.flushMicrotasks();
        expect(h.total(), 50);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('開書後尚無活動就進背景：不採計任何時間', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 開書當下的回溯已作廢
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });
  });

  group('背景 TTS', () {
    test('TTS 播放中進背景：持續計時，TTS 結束時結算並寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.elapseSeconds(290); // 第 300 秒；遠超過閒置門檻，仍持續計時
        expect(h.total(), 300);
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(false); // 睡眠定時器到期、耳機暫停等
        async.flushMicrotasks();
        expect(h.total(), 310);
        expect(async.pendingTimers, isEmpty);
        h.elapseSeconds(600);
        expect(h.total(), 310);
        h.dispose();
      });
    });

    test('resumed 且 TTS 仍在播放：無縫延續，不重複結算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.elapseSeconds(40);
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(50);
        h.tracker.onTtsPlayingChanged(false); // 前景停止
        h.closeAndSettle();
        expect(h.total(), 100);
        h.dispose();
      });
    });
  });

  group('回到前景後的 TTS', () {
    test('背景播放後回前景再停止：不會被當成背景停止而轉為閒置，之後的尾段仍計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.elapseSeconds(40);
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(false); // 前景停止：確認 60 秒，仍在計時中
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 停止後 60 秒的閱讀被這次活動確認
        h.closeAndSettle();
        expect(h.total(), 120);
        h.dispose();
      });
    });
  });

  group('前景 TTS', () {
    test('TTS 播放中沒有活動事件，30 秒定時器仍持續確認並寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(95);
        expect(h.total(), 90); // 第 30、60、90 秒各寫 30 秒
        h.closeAndSettle();
        expect(h.total(), 95); // 退出時尾段 5 秒也計入
        h.dispose();
      });
    });

    test('TTS 播放 10 分鐘不會被閒置看門狗切掉', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(600);
        expect(h.total(), 600);
        expect(async.pendingTimers, isNotEmpty);
        h.tracker.onTtsPlayingChanged(false);
        h.closeAndSettle();
        expect(h.total(), 600);
        h.dispose();
      });
    });

    test('TTS 開始播放本身算活動：開書 10 秒後開始朗讀，回溯採計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(true); // 回溯 10 秒
        h.elapseSeconds(20);
        h.tracker.onTtsPlayingChanged(false); // 再 20 秒
        h.closeAndSettle();
        expect(h.total(), 30);
        h.dispose();
      });
    });

    test('重複回報 playing=true：不重複啟動計時或多算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(20);
        h.tracker.onTtsPlayingChanged(false);
        h.tracker.onTtsPlayingChanged(false);
        h.closeAndSettle();
        expect(h.total(), 20);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('TTS 播放中退出：尾段計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(45);
        h.closeAndSettle();
        expect(h.total(), 45);
        h.dispose();
      });
    });

    test('TTS 播放中時鐘快轉一天：單次計量不超過閒置門檻', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.skew = const Duration(days: 1);
        h.elapseSeconds(30); // 第 30 秒的定時器觸發，計量被鉗位
        expect(h.writes.first.seconds, 120);
        expect(h.writes.every((w) => w.seconds <= 120), isTrue);
        h.dispose();
      });
    });

    test('TTS 停止後回到一般閒置規則：之後沒有活動就轉為閒置、計時器取消', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(60);
        h.tracker.onTtsPlayingChanged(false);
        h.elapseSeconds(300);
        expect(h.total(), 60);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });
  });
}
