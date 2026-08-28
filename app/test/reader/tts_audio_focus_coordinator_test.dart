import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_audio_focus_coordinator.dart';
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_focus_source.dart';
import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late FakeTtsAudioFocusSource source;
  late TtsController controller;
  late FakeTtsAudioPlayer player;

  TtsAudioFocusCoordinator buildCoordinator() {
    source = FakeTtsAudioFocusSource();
    player = FakeTtsAudioPlayer();
    controller = TtsController(
      provider: FakeTtsProvider(),
      player: player,
      loadSegments: () async => segments,
    );
    return TtsAudioFocusCoordinator(source: source, controller: controller);
  }

  test('暫時失焦（transientLoss）時，播放中的 controller 會被暫停', () async {
    buildCoordinator();
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    source.emit(TtsAudioFocusEvent.transientLoss);

    expect(controller.status, TtsPlaybackStatus.paused);
  });

  test('暫時失焦後焦點恢復（focusGained），因暫停係本協調器造成，自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.transientLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(player.callLog.last, 'play');
  });

  test('使用者手動暫停後才發生焦點恢復事件，不會被誤觸自動播放', () async {
    buildCoordinator();
    await controller.play();
    controller.pause(); // 使用者手動暫停，非本協調器造成
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '使用者手動暫停不應被焦點恢復事件自動喚醒播放');
  });

  test('暫時失焦期間使用者手動翻頁（狀態被重設為 idle），焦點恢復後不會自動開始播放新內容'
      '（審查 review-plan-issue-7.md 4.2）', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.transientLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    // 使用者在失焦期間手動翻頁/跳章，ReaderScreen 的 onLocatorChanged 會
    // 呼叫本方法，把狀態完全重設為 idle（見 TtsController 既有文件：
    // 手動導覽視為「舊朗讀段清單已不適用」，不是「暫停中待恢復」）。
    controller.handleExternalPositionChange();
    expect(controller.status, TtsPlaybackStatus.idle);
    final callLogLengthBeforeFocusGained = player.callLog.length;

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: '狀態已因手動導覽變成 idle，不應被焦點恢復事件誤觸自動播放'
            '（那會變成沒被要求就從新頁面開始朗讀）');
    expect(player.callLog.length, callLogLengthBeforeFocusGained,
        reason: 'player 不應在使用者未主動按下播放鍵的情況下收到任何新呼叫'
            '（idle 狀態下 controller.play() 會走 loadSegments()/'
            'lookupStartIndex() 全新流程，不該被觸發）');
  });

  test('永久失焦（permanentLoss）時暫停，且焦點恢復後不自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.permanentLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '永久失焦造成的暫停，等同使用者手動暫停，不應自動恢復');
  });

  test('耳機拔出（becomingNoisy）時暫停，且不會自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.becomingNoisy);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '耳機拔出的暫停不應自動恢復，避免拔出耳機後突然透過喇叭外放');
  });

  test('尚未開始播放（idle）時發生暫時失焦事件，不會產生任何動作', () async {
    buildCoordinator();
    expect(controller.status, TtsPlaybackStatus.idle);

    source.emit(TtsAudioFocusEvent.transientLoss);

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(player.callLog, isEmpty);
  });

  test('dispose() 後不再回應事件', () async {
    final coordinator = buildCoordinator();
    await controller.play();
    coordinator.dispose();

    source.emit(TtsAudioFocusEvent.transientLoss);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.playing,
        reason: 'dispose() 後協調器不應再訂閱事件、不應再操作 controller');
  });
}
