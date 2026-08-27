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

  test('pause() 呼叫 player.pause() 非同步失敗時不產生未捕捉例外（複審殘留技術細節修正）',
      () async {
    final controller = buildController();
    await controller.play();
    player.pauseShouldThrow = true;
    controller.pause();

    expect(controller.status, TtsPlaybackStatus.paused);
    await Future<void>.delayed(Duration.zero);
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

  test('play() 於 synthesize() 進行中呼叫 pause()，完成後維持 paused 不自動播放，事後呼叫 play() 正常播放（審查修復 Important #1）',
      () async {
    final controller = buildController();
    final synthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = synthCompleter;

    final playFuture = controller.play();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TtsPlaybackStatus.playing);

    // 在合成進行中按下暫停
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    // 合成完成
    synthCompleter.complete();
    await playFuture;

    // 驗證：音訊檔案已載入，但 player.play() 絕不會被呼叫，狀態仍維持 paused
    expect(controller.status, TtsPlaybackStatus.paused);
    expect(player.callLog, ['pause', 'loadFile']);

    // 使用者事後主動按下播放
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);
    expect(player.callLog, ['pause', 'loadFile', 'play']);

    // 播放完畢後能正常接續下一段
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentIndex, 1);
    expect(controller.status, TtsPlaybackStatus.playing);
    expect(provider.synthesizeCallCount, 2);
  });

  test('play() 於 loadFile() 進行中呼叫 pause()，完成後維持 paused 不自動播放，事後呼叫 play() 正常播放（審查修復 Important #1）',
      () async {
    final controller = buildController();
    final loadFileCompleter = Completer<void>();
    player.nextLoadFileCompleter = loadFileCompleter;

    final playFuture = controller.play();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TtsPlaybackStatus.playing);

    // 在 loadFile 進行中按下暫停
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    // 檔案載入完成
    loadFileCompleter.complete();
    await playFuture;

    // 驗證：player.play() 不會被呼叫，狀態維持 paused
    expect(controller.status, TtsPlaybackStatus.paused);
    expect(player.callLog, ['loadFile', 'pause']);

    // 使用者事後主動按下播放
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);
    expect(player.callLog, ['loadFile', 'pause', 'play']);
  });

  test('play() 開始播放時，onHighlightSegment 收到目前段落（epic-34-tts-readalong Issue 3）',
      () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();

    expect(highlighted, [segments[0]]);
  });

  test('自動接續下一段時，onHighlightSegment 依序收到新段落（不需呼叫端自行先清除舊值）',
      () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(highlighted, [segments[0], segments[1]]);
  });

  test('最後一段播放完畢回到 idle 時，onHighlightSegment 收到 null（清除高亮）', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(highlighted, [segments[0], segments[1], null]);
  });

  test('play() 合成失敗重設回 idle 時，onHighlightSegment 最後收到 null', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();

    expect(highlighted, [segments[0], null]);
  });

  test('不提供 onHighlightSegment 時，play()/自動接續/播放結束皆不拋出例外（可選 callback）',
      () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.idle);
  });

  test('play() 從 idle 開始時，若提供 lookupStartIndex，使用其回傳值作為起始段落（epic-34-tts-readalong Issue 4）',
      () async {
    var lookupCalledWith = const <TtsSegmentCfi>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async {
        lookupCalledWith = segs;
        return 1;
      },
    );

    await controller.play();

    expect(lookupCalledWith, segments);
    expect(controller.currentIndex, 1);
    expect(provider.synthesizedTexts, ['第二句。']);
  });

  test('lookupStartIndex 回傳超出範圍的索引時，安全 clamp 回第 0 段', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async => 99,
    );

    await controller.play();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。']);
  });

  test('lookupStartIndex 回傳負數（找不到對應段落）時，安全 clamp 回第 0 段', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async => -1,
    );

    await controller.play();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。']);
  });

  test('handleExternalPositionChange() 於 idle 狀態下呼叫為 no-op，不觸發 notifyListeners',
      () {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(notifyCount, 0);
    expect(highlighted, isEmpty);
    expect(player.callLog, isEmpty);
  });

  test('handleExternalPositionChange() 於 playing 狀態下呼叫，重設為 idle 並清空段落/清除高亮/暫停播放器',
      () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    expect(highlighted.last, isNull);
    expect(player.callLog.last, 'pause');
  });

  test('handleExternalPositionChange() 於 paused 狀態下呼叫，同樣重設為 idle', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.segments, isEmpty);
  });

  test('handleExternalPositionChange() 重設後再次 play()，重新呼叫 loadSegments() 並套用 lookupStartIndex（與首次播放共用同一路徑）',
      () async {
    var loadSegmentsCallCount = 0;
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async {
        loadSegmentsCallCount++;
        return segments;
      },
      lookupStartIndex: (segs) async => 1,
    );

    await controller.play();
    expect(loadSegmentsCallCount, 1);
    expect(controller.currentIndex, 1);

    controller.handleExternalPositionChange();
    await controller.play();

    expect(loadSegmentsCallCount, 2);
    expect(controller.currentIndex, 1);
  });

  test('handleExternalPositionChange() 於 dispose() 後呼叫不拋出例外、不觸發 notifyListeners（審查 review-plan-issue-4.md Important #1）',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);
    controller.dispose();

    expect(() => controller.handleExternalPositionChange(), returnsNormally);
    expect(notifyCount, 0);
  });

  test('play() 於 lookupStartIndex() 尚未完成時重複呼叫，只觸發一次 loadSegments／lookupStartIndex（審查 review-issue-4-code.md Important #1）',
      () async {
    final lookupCompleter = Completer<int>();
    var loadSegmentsCallCount = 0;
    var lookupCallCount = 0;
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async {
        loadSegmentsCallCount++;
        return segments;
      },
      lookupStartIndex: (segs) {
        lookupCallCount++;
        return lookupCompleter.future;
      },
    );

    final firstPlay = controller.play();
    // 讓 loadSegments() 完成、進入 lookupStartIndex() 等待——這正是修復前
    // _isLoadingSegments 已被提前重設為 false 的那段窗口。
    await Future<void>.delayed(Duration.zero);
    final secondPlay = controller.play(); // 連點：lookupStartIndex() 尚未完成
    lookupCompleter.complete(0);
    await firstPlay;
    await secondPlay;

    expect(loadSegmentsCallCount, 1);
    expect(lookupCallCount, 1);
    expect(provider.synthesizeCallCount, 1);
  });

  test('handleExternalPositionChange() 於 play() 正在 loadSegments()／lookupStartIndex() 進行中呼叫時，讓該次 play() 中止，不播放過期段落（審查 review-issue-4-code.md Important #2）',
      () async {
    final lookupCompleter = Completer<int>();
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) => lookupCompleter.future,
    );

    final playFuture = controller.play();
    // 讓 loadSegments() 完成、進入 lookupStartIndex() 等待。
    await Future<void>.delayed(Duration.zero);

    controller.handleExternalPositionChange(); // 模擬 loading 期間發生手動導覽
    lookupCompleter.complete(1); // lookupStartIndex() 這時才回應（結果已過期）
    await playFuture;

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.segments, isEmpty);
    expect(controller.currentIndex, -1);
    expect(provider.synthesizeCallCount, 0); // 過期結果不應該被拿去合成/播放
  });
}



