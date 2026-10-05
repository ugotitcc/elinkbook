import 'dart:async';

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

  group('TtsAudioHandlerHolder（啟動階段 holder，取代 TtsDegradedNotice）', () {
    test('ready 建構：狀態為 ready、有 handler、永不提示', () {
      final handler = TtsAudioHandler();
      final holder = TtsAudioHandlerHolder.ready(handler);

      expect(holder.status, TtsAudioHandlerStatus.ready);
      expect(holder.handler, same(handler));
      expect(holder.consumeDegradedNotice(), isFalse);
      expect(holder.consumeDegradedNotice(), isFalse);
    });

    test('degraded 建構：狀態為 failed、無 handler、只提示一次', () {
      final holder = TtsAudioHandlerHolder.degraded();

      expect(holder.status, TtsAudioHandlerStatus.failed);
      expect(holder.handler, isNull);
      expect(holder.consumeDegradedNotice(), isTrue);
      expect(holder.consumeDegradedNotice(), isFalse);
      expect(holder.consumeDegradedNotice(), isFalse);
    });

    test('unavailable 建構：狀態為 pending、無 handler、永不提示', () {
      final holder = TtsAudioHandlerHolder.unavailable();

      expect(holder.status, TtsAudioHandlerStatus.pending);
      expect(holder.handler, isNull);
      expect(holder.consumeDegradedNotice(), isFalse);
      expect(holder.consumeDegradedNotice(), isFalse);
    });
  });

  group('startTtsAudioHandlerInBackground', () {
    test('init 尚未完成時就同步回傳 pending holder，不阻塞', () {
      final completer = Completer<TtsAudioHandler>();
      var notified = false;

      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);
      holder.addListener(() => notified = true);

      expect(holder.status, TtsAudioHandlerStatus.pending);
      expect(holder.handler, isNull);
      expect(holder.consumeDegradedNotice(), isFalse);
      expect(notified, isFalse);
      // 收尾：讓背景工作有對象可完成，避免懸空 future；不 await，
      // 若實作阻塞在此，測試本身就會逾時失敗。
      completer.complete(TtsAudioHandler());
    });

    test('init 成功時 holder 變 ready、有 handler、通知一次、不提示', () async {
      final handler = TtsAudioHandler();
      var notifyCount = 0;

      final holder = startTtsAudioHandlerInBackground(() async => handler);
      holder.addListener(() => notifyCount++);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(holder.status, TtsAudioHandlerStatus.ready);
      expect(holder.handler, same(handler));
      expect(notifyCount, 1);
      expect(holder.consumeDegradedNotice(), isFalse);
    });

    test('init 丟例外時 holder 變 failed、無 handler、通知一次、待提示', () async {
      var notifyCount = 0;

      final holder = startTtsAudioHandlerInBackground(
        () async => throw StateError('綁定逾時'),
      );
      holder.addListener(() => notifyCount++);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(holder.status, TtsAudioHandlerStatus.failed);
      expect(holder.handler, isNull);
      expect(notifyCount, 1);
      expect(holder.consumeDegradedNotice(), isTrue);
      expect(holder.consumeDegradedNotice(), isFalse);
    });

    test('init 永遠不完成時不丟例外、不通知、不提示', () async {
      var notified = false;

      final holder = startTtsAudioHandlerInBackground(
        () => Completer<TtsAudioHandler>().future,
      );
      holder.addListener(() => notified = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(holder.status, TtsAudioHandlerStatus.pending);
      expect(holder.handler, isNull);
      expect(notified, isFalse);
      expect(holder.consumeDegradedNotice(), isFalse);
    });
  });
}
