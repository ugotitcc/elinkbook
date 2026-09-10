// app/test/reader/reader_activity_tracker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';

void main() {
  group('ReaderActivityTracker', () {
    test('初始狀態為未開啟', () {
      final tracker = ReaderActivityTracker();
      expect(tracker.isReaderOpen, isFalse);
    });

    test('markReaderOpened() 後 isReaderOpen 為 true 且通知監聽者', () {
      final tracker = ReaderActivityTracker();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderOpened();

      expect(tracker.isReaderOpen, isTrue);
      expect(notifyCount, 1);
    });

    test('markReaderClosed() 後 isReaderOpen 為 false 且通知監聽者', () {
      final tracker = ReaderActivityTracker();
      tracker.markReaderOpened();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderClosed();

      expect(tracker.isReaderOpen, isFalse);
      expect(notifyCount, 1);
    });

    test('重複呼叫同一狀態不重複通知（idempotent）', () {
      final tracker = ReaderActivityTracker();
      var notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.markReaderClosed(); // 已經是 false，不應通知
      expect(notifyCount, 0);

      tracker.markReaderOpened();
      tracker.markReaderOpened(); // 已經是 true，不應重複通知
      expect(notifyCount, 1);
    });
  });
}
