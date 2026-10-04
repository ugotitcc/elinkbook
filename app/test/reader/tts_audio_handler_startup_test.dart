import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';

// epic-61：啟動黑屏回歸測試。
// 真機實測：AudioService 綁定逾時（約 10 秒）時 AudioService.init 丟出
// PlatformException，main() 沒有接住，runApp 未執行，整個 App 黑屏。

void main() {
  group('initTtsAudioHandlerSafely', () {
    test('init 成功時回傳 handler', () async {
      final handler = TtsAudioHandler();

      final result = await initTtsAudioHandlerSafely(() async => handler);

      expect(result, same(handler));
    });

    test('init 丟出 PlatformException（綁定逾時）時回傳 null，不丟例外', () async {
      final result = await initTtsAudioHandlerSafely(
        () async => throw PlatformException(
          code:
              'Unable to bind to AudioService. Please ensure you have declared a <service> element as described in the README.',
        ),
      );

      expect(result, isNull, reason: '朗讀降級為不可用，App 仍須能啟動');
    });

    test('init 丟出任何其他例外也回傳 null', () async {
      final result = await initTtsAudioHandlerSafely(
        () async => throw StateError('boom'),
      );

      expect(result, isNull);
    });

    test('init 同步丟例外（建構階段）也回傳 null', () async {
      final result = await initTtsAudioHandlerSafely(
        () => throw StateError('sync boom'),
      );

      expect(result, isNull);
    });
  });
}
