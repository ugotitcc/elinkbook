import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late TtsController controller;
  late FakeTtsAudioPlayer player;

  TtsController buildRealController() {
    player = FakeTtsAudioPlayer();
    return TtsController(
      provider: FakeTtsProvider(),
      player: player,
      loadSegments: () async => segments,
    );
  }

  test('尚未 attachController 時，playbackState 維持初始 idle 狀態', () {
    final handler = TtsAudioHandler();
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('attachController 後，mediaItem 帶入書名，playbackState 反映 idle', () {
    final handler = TtsAudioHandler();
    controller = buildRealController();

    handler.attachController(controller, bookTitle: '紅樓夢');

    expect(handler.mediaItem.value?.title, '紅樓夢');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('controller 開始播放後，playbackState.playing 同步變為 true', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');

    await controller.play();

    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
  });

  test('handler.play()／pause() 轉發給目前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');

    await controller.play();
    await handler.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    await handler.play();
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('handler.skipToNext()／skipToPrevious() 轉發給目前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');
    await controller.play();
    expect(controller.currentIndex, 0);

    await handler.skipToNext();
    expect(controller.currentIndex, 1);

    await handler.skipToPrevious();
    expect(controller.currentIndex, 0);
  });

  test('detachController 後，handler.play() 不再影響先前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');
    handler.detachController();

    await handler.play();

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: 'detach 後 handler 不應再持有對舊 controller 的參照');
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('attachController 兩次（換書），第二次會先解綁第一個 controller 的監聽', () async {
    final handler = TtsAudioHandler();
    final firstController = buildRealController();
    handler.attachController(firstController, bookTitle: '第一本書');

    final secondPlayer = FakeTtsAudioPlayer();
    final secondController = TtsController(
      provider: FakeTtsProvider(),
      player: secondPlayer,
      loadSegments: () async => segments,
    );
    handler.attachController(secondController, bookTitle: '第二本書');

    await firstController.play(); // 舊 controller 狀態變化不應再影響 handler
    expect(handler.mediaItem.value?.title, '第二本書');
    expect(handler.playbackState.value.playing, isFalse);
  });
}
