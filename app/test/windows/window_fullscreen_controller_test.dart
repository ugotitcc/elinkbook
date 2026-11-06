import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/windows/window_fullscreen_controller.dart';

class FakeWindowFullscreenController implements WindowFullscreenController {
  bool _fullscreen;
  Completer<void>? isFullscreenCompleter;
  Completer<void>? setFullscreenCompleter;
  bool shouldThrowOnSet = false;
  final List<bool> history = [];

  FakeWindowFullscreenController({
    bool initialFullscreen = false,
    this.isFullscreenCompleter,
    this.setFullscreenCompleter,
  }) : _fullscreen = initialFullscreen;

  @override
  bool get isFullscreenNow => _fullscreen;

  @override
  Future<bool> isFullscreen() async {
    if (isFullscreenCompleter != null) {
      await isFullscreenCompleter!.future;
    }
    return _fullscreen;
  }

  @override
  Future<void> setFullscreen(bool isFullscreen) async {
    if (setFullscreenCompleter != null) {
      await setFullscreenCompleter!.future;
    }
    if (shouldThrowOnSet) {
      throw StateError('Simulated setFullscreen failure');
    }
    _fullscreen = isFullscreen;
    history.add(isFullscreen);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('WindowFullscreenController 輔助函式', () {
    test('非全螢幕時 toggle 設為 true，全螢幕時 toggle 設為 false', () async {
      final fake = FakeWindowFullscreenController(initialFullscreen: false);

      await toggleWindowFullscreen(fake);
      expect(fake.isFullscreenNow, isTrue);
      expect(fake.history, [true]);

      await toggleWindowFullscreen(fake);
      expect(fake.isFullscreenNow, isFalse);
      expect(fake.history, [true, false]);
    });

    test('上一次 toggle 尚未完成時再呼叫會被忽略，只設定一次 (Review Focus 5)', () async {
      final isFullscreenCompleter = Completer<void>();
      final fake = FakeWindowFullscreenController(
        initialFullscreen: false,
        isFullscreenCompleter: isFullscreenCompleter,
      );

      final firstFuture = toggleWindowFullscreen(fake);
      final secondFuture = toggleWindowFullscreen(fake);
      final thirdFuture = toggleWindowFullscreen(fake);

      isFullscreenCompleter.complete();
      await Future.wait([firstFuture, secondFuture, thirdFuture]);

      // 只有第一次呼叫成功進入全螢幕，重入呼叫被防護旗標忽略
      expect(fake.history, [true]);
      expect(fake.isFullscreenNow, isTrue);
    });

    test('控制器丟例外時 toggle 不外洩，之後仍可再次 toggle', () async {
      final fake = FakeWindowFullscreenController(initialFullscreen: false);
      fake.shouldThrowOnSet = true;

      // 呼叫不拋出例外（內部已 debugPrint 吞掉）
      await expectLater(toggleWindowFullscreen(fake), completes);
      expect(fake.history, isEmpty);

      // 之後旗標已還原，可再次呼叫
      fake.shouldThrowOnSet = false;
      await toggleWindowFullscreen(fake);
      expect(fake.isFullscreenNow, isTrue);
      expect(fake.history, [true]);
    });

    test('exitWindowFullscreenIfActive：isFullscreenNow 為 true 時呼叫 setFullscreen(false) 並回傳 true；為 false 時回傳 false 且不呼叫', () async {
      final fakeActive = FakeWindowFullscreenController(initialFullscreen: true);
      final resultActive = await exitWindowFullscreenIfActive(fakeActive);
      expect(resultActive, isTrue);
      expect(fakeActive.isFullscreenNow, isFalse);
      expect(fakeActive.history, [false]);

      final fakeInactive = FakeWindowFullscreenController(initialFullscreen: false);
      final resultInactive = await exitWindowFullscreenIfActive(fakeInactive);
      expect(resultInactive, isFalse);
      expect(fakeInactive.isFullscreenNow, isFalse);
      expect(fakeInactive.history, isEmpty);
    });

    test('toggle 進行中呼叫 exitWindowFullscreenIfActive 會被忽略（共用旗標）', () async {
      final completer = Completer<void>();
      final fake = FakeWindowFullscreenController(
        initialFullscreen: false,
        isFullscreenCompleter: completer,
      );

      final toggleFuture = toggleWindowFullscreen(fake);
      final exitResult = await exitWindowFullscreenIfActive(fake);

      // exitWindowFullscreenIfActive 被防護旗標忽略並回傳 false
      expect(exitResult, isFalse);

      completer.complete();
      await toggleFuture;

      expect(fake.isFullscreenNow, isTrue);
      expect(fake.history, [true]);
    });
  });

  group('WindowManagerFullscreenController 快取與介面', () {
    test('預設 isFullscreenNow 為 false', () {
      final controller = WindowManagerFullscreenController();
      expect(controller.isFullscreenNow, isFalse);
    });
  });
}
