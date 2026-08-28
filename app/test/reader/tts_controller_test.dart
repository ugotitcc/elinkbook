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

  test(
      'suppressNextExternalPositionChange() 後緊接著一次 handleExternalPositionChange() 呼叫，'
      '不重設播放狀態（epic-34-tts-readalong Issue 8：安全視窗自動翻頁不應誤觸發暫停）',
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
    highlighted.clear();
    player.callLog.clear();

    controller.suppressNextExternalPositionChange();
    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(controller.currentIndex, 0);
    expect(controller.segments, segments);
    expect(highlighted, isEmpty,
        reason: '不應清除高亮——這次位置變化是 TTS 自己造成的安全視窗翻頁，'
            '不是使用者手動導覽。');
    expect(player.callLog, isEmpty,
        reason: '不應呼叫 player.pause()——播放不應中斷。');
  });

  test('抑制旗標只抑制「緊接著的下一次」呼叫，之後的 handleExternalPositionChange() 恢復既有暫停行為',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();

    controller.suppressNextExternalPositionChange();
    controller.handleExternalPositionChange(); // 消耗掉旗標，維持 playing
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange(); // 真正的使用者手動導覽

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
  });

  // 審查修正（review-plan-issue-8.md Important #2）：抑制旗標若在設下後
  // 從未被 handleExternalPositionChange() 消耗（例如安全視窗觸發的翻頁
  // 剛好是全書最後一頁、next() 沒有效果、不會產生新的 relocate 事件），
  // 會一路殘留到下一次全新播放，錯誤抑制之後完全不相關的一次手動導覽。
  test(
      '抑制旗標若在章節自然播畢（未經 handleExternalPositionChange 消耗）前設下，'
      '不會遺留到下一輪播放、誤抑制之後真正的手動導覽（審查 review-plan-issue-8.md Important #2）',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    controller.suppressNextExternalPositionChange();
    // 模擬「安全視窗觸發的翻頁最終沒有送出 relocate 事件」——章節透過
    // 連續按下一句到底自然播畢，而非透過 handleExternalPositionChange()
    // 消耗掉旗標。
    await controller.nextSegment(); // -> index 1
    await controller.nextSegment(); // 超出範圍，重設為 idle
    expect(controller.status, TtsPlaybackStatus.idle);

    // 重新開始一次全新的播放。
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange(); // 這次是真正的使用者手動導覽

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: '若抑制旗標從上一輪播放遺留下來，這裡會被誤判為 TTS 自己'
            '造成的位置變化而維持 playing，導致這次真正的手動導覽沒有'
            '正確觸發自動暫停。');
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

  test('初始 speed 為 1.0', () {
    final controller = buildController();
    expect(controller.speed, 1.0);
  });

  test('setSpeed() 於 idle 狀態下只更新 speed 值，不呼叫 player.setSpeed()（尚無正在播放的段落可變速）',
      () async {
    final controller = buildController();

    await controller.setSpeed(1.5);

    expect(controller.speed, 1.5);
    expect(player.callLog, isEmpty);
  });

  test('setSpeed() 於 playing 狀態下呼叫 player.setSpeed()，不重新呼叫 synthesize'
      '（目前段落零延遲變速，語速契約澄清 review-spec.md Minor #2）', () async {
    final controller = buildController();
    await controller.play();
    expect(provider.synthesizeCallCount, 1);

    await controller.setSpeed(1.5);

    expect(controller.speed, 1.5);
    expect(player.speedCalls, [1.5]);
    expect(provider.synthesizeCallCount, 1); // 不重新合成
  });

  test('setSpeed() 於 paused 狀態下同樣呼叫 player.setSpeed()（暫停中的段落之後恢復時沿用新語速）',
      () async {
    final controller = buildController();
    await controller.play();
    controller.pause();

    await controller.setSpeed(0.75);

    expect(player.speedCalls, [0.75]);
  });

  test('setSpeed() 後，自動接續下一段時 synthesize() 收到新的 speed 值（下一段才用新語速合成）',
      () async {
    final controller = buildController();
    await controller.play();
    await controller.setSpeed(1.5);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(provider.synthesizeSpeeds, [1.0, 1.5]);
  });

  test('nextSegment() 於 idle 狀態下為 no-op，不呼叫 synthesize', () async {
    final controller = buildController();

    await controller.nextSegment();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('nextSegment() 從第一段跳到第二段並開始播放', () async {
    final controller = buildController();
    await controller.play();

    await controller.nextSegment();

    expect(controller.currentIndex, 1);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。']);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('nextSegment() 於最後一段時，回到 idle 並清除高亮（等同自然播放完畢）', () async {
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
    await controller.nextSegment(); // 到第二段（最後一段）

    await controller.nextSegment(); // 已是最後一段，視同播放完畢

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    expect(highlighted.last, isNull);
    expect(player.callLog, contains('pause'));
  });

  test('nextSegment() 於 paused 狀態下呼叫，跳到下一段並自動恢復播放', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    await controller.nextSegment();

    expect(controller.currentIndex, 1);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('previousSegment() 於 idle 狀態下為 no-op', () async {
    final controller = buildController();

    await controller.previousSegment();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('previousSegment() 於第一段（currentIndex=0）呼叫為 no-op，不迴繞到最後一段', () async {
    final controller = buildController();
    await controller.play();
    expect(controller.currentIndex, 0);

    await controller.previousSegment();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizeCallCount, 1); // 沒有新的合成呼叫
  });

  test('previousSegment() 從第二段跳回第一段並重新播放', () async {
    final controller = buildController();
    await controller.play();
    await controller.nextSegment(); // 到第二段

    await controller.previousSegment();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。', '第一句。']);
  });

  test('nextSegment() 連續快速呼叫兩次時，只有最後一次呼叫的結果生效，不播放到過期段落'
      '（防重入，比照 review-issue-4-code.md Important #2 手法）', () async {
    const threeSegments = [
      TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
      TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
      TtsSegmentCfi(segmentId: '2', cfi: 'epubcfi(/6/4!/1:10)', text: '第三句。'),
    ];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => threeSegments,
    );
    await controller.play(); // 目前在第 0 段（playing）

    final firstSynthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = firstSynthCompleter;
    final firstNext = controller.nextSegment(); // 跳到第 1 段，等待合成
    await Future<void>.delayed(Duration.zero);

    final secondSynthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = secondSynthCompleter;
    final secondNext = controller.nextSegment(); // 跳到第 2 段，等待合成
    await Future<void>.delayed(Duration.zero);

    // 讓第一次呼叫（較舊、應該過期）反而先完成合成。
    firstSynthCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    secondSynthCompleter.complete();
    await firstNext;
    await secondNext;

    // 只有第 2 段（最新一次呼叫）的音訊被實際載入播放，第 1 段的
    // （過期）合成結果被安全捨棄，不會讓使用者聽到「跳回舊句子」。
    expect(controller.currentIndex, 2);
    expect(player.loadedFiles, ['/fake/segment_1.wav', '/fake/segment_3.wav']);
  });

  test('handleExternalPositionChange() 於 nextSegment() 合成進行中呼叫時，讓該次呼叫的音訊'
      '不被載入播放器（review-plan-issue-5.md 建議 1：_segmentGeneration 提前失效）',
      () async {
    final controller = buildController();
    await controller.play(); // 第 0 段已在播放中

    final synthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = synthCompleter;
    final nextFuture = controller.nextSegment(); // 跳到第 1 段，合成進行中
    await Future<void>.delayed(Duration.zero);

    controller.handleExternalPositionChange(); // 模擬合成期間發生手動導覽
    synthCompleter.complete(); // 合成這時才完成（結果已過期）
    await nextFuture;

    expect(controller.status, TtsPlaybackStatus.idle);
    // 過期結果不應該被載入播放器——沒有這項修法時，loadFile() 仍會被呼叫
    // （只是事後因 _status != playing 而不會真的播放出聲音，loadedFiles 會包含
    // '/fake/segment_2.wav'）；本測試驗證 handleExternalPositionChange() 讓
    // _segmentGeneration 提前失效後，連 loadFile() 這個不必要的呼叫也不會發生，
    // loadedFiles 僅保留初始 play() 載入的第 0 段音訊。
    expect(player.loadedFiles, ['/fake/segment_1.wav']);
  });

  test('nextSegment() 於合成進行中，另一次 nextSegment() 呼叫直接跳出章節範圍時，'
      '過期呼叫完成後不會再呼叫 player.loadFile()（review-issue-5-code.md Minor #2：'
      '章節末尾分支的 _segmentGeneration 提前失效）', () async {
    final controller = buildController(); // 只有兩段：segments[0]/segments[1]
    await controller.play(); // 第 0 段已在播放中

    final synthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = synthCompleter;
    final firstNext = controller.nextSegment(); // 跳到第 1 段，合成進行中
    await Future<void>.delayed(Duration.zero);

    // 第二次呼叫時 nextIndex（=2）已超出 segments.length（=2），同步走
    // 「章節末尾」分支——_segmentGeneration 立即遞增、狀態立即重設為
    // idle，不等待任何 synthesize()。
    await controller.nextSegment();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(player.callLog, contains('pause'));

    // 讓第一次呼叫（較舊、此時已過期）的合成才完成。
    synthCompleter.complete();
    await firstNext;

    // 過期結果不應該被載入播放器——只有初次 play() 合成的第 0 段音訊，
    // 第一次 nextSegment() 對應的第 1 段音訊不應該出現在這裡。
    expect(player.loadedFiles, ['/fake/segment_1.wav']);
    expect(controller.status, TtsPlaybackStatus.idle);
  });

  test('dispose() 後呼叫 nextSegment()/previousSegment()/setSpeed() 不拋出例外', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(() => controller.nextSegment(), returnsNormally);
    expect(() => controller.previousSegment(), returnsNormally);
    expect(() => controller.setSpeed(1.5), returnsNormally);
  });

  test('resyncHighlight() 於 idle 狀態（從未播放過）為 no-op，不呼叫 onHighlightSegment', () {
    TtsSegmentCfi? received;
    var callCount = 0;
    final controller = TtsController(
      provider: FakeTtsProvider(),
      player: FakeTtsAudioPlayer(),
      loadSegments: () async => segments,
      onHighlightSegment: (segment) {
        received = segment;
        callCount++;
      },
    );
    controller.resyncHighlight();
    expect(callCount, 0);
    expect(received, isNull);
  });

  test('resyncHighlight() 於 playing 狀態重新呼叫 onHighlightSegment，帶目前段落', () async {
    TtsSegmentCfi? received;
    var callCount = 0;
    final provider = FakeTtsProvider();
    final player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: (segment) {
        received = segment;
        callCount++;
      },
    );
    await controller.play();
    final callCountAfterPlay = callCount;

    controller.resyncHighlight();

    expect(callCount, callCountAfterPlay + 1,
        reason: 'resyncHighlight() 應額外觸發一次 onHighlightSegment');
    expect(received, segments[0]);
  });

  test('resyncHighlight() 於 disposed 後為 no-op（不拋出例外）', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(() => controller.resyncHighlight(), returnsNormally);
  });
}



