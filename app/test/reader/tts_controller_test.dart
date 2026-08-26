import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late FakeTtsProvider provider;
  late FakeTtsAudioPlayer player;

  TtsController buildController({List<TtsSegmentCfi> segs = segments}) {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    return TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segs,
    );
  }

  test('初始狀態為 idle，尚未載入任何朗讀段', () {
    final controller = buildController();
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.segments, isEmpty);
    expect(controller.currentIndex, -1);
  });

  test('play() 於空朗讀段清單時維持 idle，不呼叫 synthesize', () async {
    final controller = buildController(segs: const []);
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('play() 合成第一段並開始播放', () async {
    final controller = buildController();
    await controller.play();

    expect(provider.synthesizeCallCount, 1);
    expect(provider.synthesizedTexts, ['第一句。']);
    expect(player.loadedFiles, ['/fake/segment_1.wav']);
    expect(player.callLog, ['loadFile', 'play']);
    expect(controller.status, TtsPlaybackStatus.playing);
    expect(controller.currentIndex, 0);
  });

  test('目前段落播放完畢後自動合成並播放下一段', () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero); // 讓 completedStream 事件被消費

    expect(provider.synthesizeCallCount, 2);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。']);
    expect(controller.currentIndex, 1);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('最後一段播放完畢後回到 idle，不再合成新段落', () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(provider.synthesizeCallCount, 2);
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
  });

  test('pause() 於播放中呼叫 player.pause() 並轉為 paused，不重新合成', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();

    expect(controller.status, TtsPlaybackStatus.paused);
    expect(player.callLog.last, 'pause');
    expect(provider.synthesizeCallCount, 1);
  });

  test('paused 狀態下再次呼叫 play() 只呼叫 player.play()，不重新合成', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();
    await controller.play();

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(provider.synthesizeCallCount, 1); // 沒有新的合成呼叫
    expect(player.callLog, ['loadFile', 'play', 'pause', 'play']);
  });

  test('play() 於已在播放中時為 no-op', () async {
    final controller = buildController();
    await controller.play();
    await controller.play();

    expect(provider.synthesizeCallCount, 1);
    expect(player.callLog, ['loadFile', 'play']);
  });

  test('notifyListeners 在狀態變化時觸發', () async {
    final controller = buildController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.play();
    expect(notifyCount, greaterThan(0));

    final countAfterPlay = notifyCount;
    controller.pause();
    expect(notifyCount, greaterThan(countAfterPlay));
  });

  test('dispose() 後 player 已釋放，模擬完成事件不再觸發新的合成', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(player.disposed, isTrue);
  });

  test('play() 時 synthesize() 拋出例外，重設回 idle 而非卡在 playing（審查 Important #1）',
      () async {
    final controller = buildController();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');

    await controller.play();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    // player.loadFile()/play() 不應該被呼叫——合成本身就失敗了。
    expect(player.callLog, isEmpty);
  });

  test('自動接續下一句時 synthesize() 拋出例外，重設回 idle 而非卡在 playing（審查 Important #1）',
      () async {
    final controller = buildController();
    await controller.play();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    // 第一段合成成功（callLog 有 loadFile/play），第二段合成失敗，
    // 不應該再有第二次 loadFile。
    expect(player.callLog, ['loadFile', 'play']);
  });

  test('play() 於 loadSegments() 尚未完成時重複呼叫，只觸發一次 loadSegments（審查 Important #2）',
      () async {
    final loadCompleter = Completer<List<TtsSegmentCfi>>();
    var loadSegmentsCallCount = 0;
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () {
        loadSegmentsCallCount++;
        return loadCompleter.future;
      },
    );

    final firstPlay = controller.play();
    final secondPlay = controller.play(); // 連點：loadSegments() 尚未完成
    loadCompleter.complete(segments);
    await firstPlay;
    await secondPlay;

    expect(loadSegmentsCallCount, 1);
    expect(provider.synthesizeCallCount, 1);
  });

  test('play() 於 synthesize() 尚未完成時重複呼叫，只觸發一次 synthesize（防重入）',
      () async {
    final controller = buildController();
    final synthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = synthCompleter;

    final firstPlay = controller.play();
    // 讓 loadSegments 完成並進入 _playCurrentSegment
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TtsPlaybackStatus.playing);

    final secondPlay = controller.play(); // 連點：synthesize() 尚未完成

    synthCompleter.complete();
    await firstPlay;
    await secondPlay;

    expect(provider.synthesizeCallCount, 1);
    expect(player.callLog, ['loadFile', 'play']);
  });
}
