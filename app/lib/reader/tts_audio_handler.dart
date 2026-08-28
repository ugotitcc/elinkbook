import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'tts_controller.dart';

/// 系統通知欄/鎖定畫面/耳機線控與 [TtsController] 之間的橋接
/// （epic-34-tts-readalong Issue 7，spec.md「Android 平台整合
/// （`audio_service`）」）。`main.dart` 以 `AudioService.init(builder: () =>
/// TtsAudioHandler())` 建構**單一 App 生命週期長駐實例**（`audio_service`
/// 套件限制 `AudioService.init()` 全程式只能呼叫一次），透過
/// [attachController]／[detachController] 綁定/解綁「目前開啟的書」對應
/// 的 [TtsController]——[ReaderScreen] 每次開書都會建構一個新的
/// [TtsController]，但只有一個 [TtsAudioHandler]。
///
/// 只轉發播放/暫停/上一句/下一句（[play]／[pause]／[skipToNext]／
/// [skipToPrevious]），[BaseAudioHandler.click] 的預設實作已依
/// `playbackState.playing` 把單次媒體按鍵點擊（藍牙/有線耳機線控最常見
/// 的形式）分派成 [play]／[pause]，本類別不需要另外覆寫。
class TtsAudioHandler extends BaseAudioHandler {
  TtsController? _controller;
  VoidCallback? _statusListener;

  void attachController(TtsController controller, {required String bookTitle}) {
    detachController();
    _controller = controller;
    mediaItem.add(MediaItem(id: 'elinkbook-tts', title: bookTitle));
    _statusListener = _syncPlaybackState;
    controller.addListener(_statusListener!);
    _syncPlaybackState();
  }

  void detachController() {
    final controller = _controller;
    final listener = _statusListener;
    if (controller != null && listener != null) {
      controller.removeListener(listener);
    }
    _controller = null;
    _statusListener = null;
    mediaItem.add(null);
    playbackState.add(PlaybackState());
  }

  void _syncPlaybackState() {
    final controller = _controller;
    if (controller == null) return;
    final playing = controller.status == TtsPlaybackStatus.playing;
    playbackState.add(PlaybackState(
      controls: playing
          ? const [
              MediaControl.skipToPrevious,
              MediaControl.pause,
              MediaControl.skipToNext,
            ]
          : const [
              MediaControl.skipToPrevious,
              MediaControl.play,
              MediaControl.skipToNext,
            ],
      androidCompactActionIndices: const [0, 1, 2],
      playing: playing,
      processingState: controller.status == TtsPlaybackStatus.idle
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      speed: controller.speed,
    ));
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> skipToNext() async => _controller?.nextSegment();

  @override
  Future<void> skipToPrevious() async => _controller?.previousSegment();

  @override
  Future<void> stop() async {
    _controller?.pause();
    await super.stop();
  }
}
