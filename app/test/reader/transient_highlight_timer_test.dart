import 'dart:async';

import 'package:elinkbook/reader/transient_highlight_timer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransientHighlightTimer', () {
    test('滿 3 秒後呼叫一次 onExpire，且呼叫當下 isActive 已為 false', () {
      fakeAsync((async) {
        final timer = TransientHighlightTimer();
        var expired = 0;
        bool? activeDuringExpire;
        timer.start(() {
          expired++;
          activeDuringExpire = timer.isActive;
        });
        expect(timer.isActive, isTrue);

        async.elapse(const Duration(seconds: 3));

        expect(expired, 1);
        expect(
          activeDuringExpire,
          isFalse,
          reason: '到期路徑不能再被 isActive 擋掉，否則高亮清不掉',
        );
        expect(timer.isActive, isFalse);
      });
    });

    test('未滿 3 秒時不呼叫 onExpire，isActive 仍為 true', () {
      fakeAsync((async) {
        final timer = TransientHighlightTimer();
        var expired = 0;
        timer.start(() => expired++);

        async.elapse(const Duration(milliseconds: 2999));

        expect(expired, 0);
        expect(timer.isActive, isTrue);
      });
    });

    test('重新啟動：取消舊計時器，從第二次 start 起重新計 3 秒', () {
      fakeAsync((async) {
        final timer = TransientHighlightTimer();
        final expired = <String>[];
        timer.start(() => expired.add('第一次'));
        async.elapse(const Duration(seconds: 2));

        timer.start(() => expired.add('第二次'));
        async.elapse(const Duration(seconds: 2));
        expect(expired, isEmpty, reason: '第一次的計時器已被取消，第二次還沒滿 3 秒');

        async.elapse(const Duration(seconds: 1));
        expect(expired, ['第二次']);
      });
    });

    test('cancel() 後不呼叫 onExpire，isActive 為 false', () {
      fakeAsync((async) {
        final timer = TransientHighlightTimer();
        var expired = 0;
        timer.start(() => expired++);

        timer.cancel();
        async.elapse(const Duration(seconds: 5));

        expect(expired, 0);
        expect(timer.isActive, isFalse);
      });
    });

    test('沒有啟動時 cancel() 是安全的無動作', () {
      final timer = TransientHighlightTimer();

      timer.cancel();

      expect(timer.isActive, isFalse);
    });

    test('預設時長為 3 秒', () {
      fakeAsync((async) {
        Duration? received;
        final timer = TransientHighlightTimer(
          timerFactory: (duration, callback) {
            received = duration;
            return Timer(duration, callback);
          },
        );

        timer.start(() {});

        expect(received, const Duration(seconds: 3));
      });
    });

    test('在另一個 Zone 呼叫 start，計時器仍建在建構時的 Zone 並可被推進', () {
      fakeAsync((async) {
        final timer = TransientHighlightTimer();
        var expired = 0;

        // 模擬 tester.runAsync：離開 fake-async Zone 後才呼叫 start。
        Zone.root.run(() => timer.start(() => expired++));
        async.elapse(const Duration(seconds: 3));

        expect(expired, 1);
      });
    });
  });
}
