import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/reader/tts_audio_handler_startup.dart';

// epic-61 Issue 1（F3）：降級提示「每次啟動 App 只顯示一次」的狀態。
void main() {
  group('TtsDegradedNotice', () {
    test('降級時第一次 consume 回傳 true，之後回傳 false', () {
      final notice = TtsDegradedNotice(degraded: true);

      expect(notice.consume(), isTrue);
      expect(notice.consume(), isFalse);
      expect(notice.consume(), isFalse);
    });

    test('沒有降級時 consume 一律回傳 false', () {
      final notice = TtsDegradedNotice(degraded: false);

      expect(notice.consume(), isFalse);
    });
  });
}
