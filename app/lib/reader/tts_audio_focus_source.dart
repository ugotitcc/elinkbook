import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// 音訊焦點事件（epic-34-tts-readalong Issue 7，spec.md「Audio Focus
/// 中斷處理」）。跨平台抽象——不直接暴露 Android
/// `AudioManager.OnAudioFocusChangeListener` 或 `audio_session` 套件的
/// [AudioInterruptionEvent] 型別，讓 [TtsAudioFocusCoordinator] 可用
/// Fake 事件源做純 Dart 單元測試（審查 `review-issues.md` Important #2
/// 「測試分流」自動化層）。
enum TtsAudioFocusEvent {
  /// 暫時失去焦點（Android `AUDIOFOCUS_LOSS_TRANSIENT`，例如來電、導航
  /// 語音、系統通知音）：應暫停播放，焦點恢復時自動恢復。
  transientLoss,

  /// 永久失去焦點（Android `AUDIOFOCUS_LOSS`，例如使用者開啟其他音樂/
  /// Podcast App）：應暫停播放，且不自動恢復。
  permanentLoss,

  /// 焦點恢復（Android `AUDIOFOCUS_GAIN`）。
  focusGained,

  /// 耳機/藍牙裝置拔出（`AudioSession.becomingNoisyEventStream`）：應
  /// 暫停播放，且不自動恢復（避免拔出耳機後突然透過喇叭外放）。
  becomingNoisy,
}

/// [TtsAudioFocusEvent] 事件來源抽象。存在的唯一理由同
/// [TtsAudioPlayer]（`tts_audio_player.dart`）——讓
/// [TtsAudioFocusCoordinator] 可在純 Dart 單元測試中注入 Fake 實作，
/// `audio_session` 依賴平台 channel，`flutter test` 環境下無法產生真實
/// 系統廣播。
abstract class TtsAudioFocusSource {
  Stream<TtsAudioFocusEvent> get events;

  void dispose();
}

/// [TtsAudioFocusSource] 的正式實作，包一層 `audio_session` 的
/// [AudioSession]。事件對應規則見 `plans/plan-issue-7.md` Task 3「規劃
/// 階段查證」：Android `AudioManager` 的
/// `loss`/`lossTransient`/`lossTransientCanDuck`/`gain` 四種焦點變化，
/// 經 `audio_session` 轉譯為 [AudioInterruptionEvent]（`begin`＋`type`
/// 兩個欄位），本類別再把這組二維組合收斂為 [TtsAudioFocusEvent] 這個
/// 一維列舉，供 [TtsAudioFocusCoordinator] 使用。
///
/// 合併後的事件流在**建構子內一次性**訂閱底層 `AudioSession` 的兩條
/// 串流並存成欄位（而非每次讀取 [events] 這個 getter 時才即時訂閱）——
/// 避免 [events] 被存取超過一次時（目前呼叫端 [TtsAudioFocusCoordinator]
/// 只會存取一次，但介面本身不應假設呼叫端只存取一次）產生重複訂閱，讓
/// [dispose] 能明確對應到唯一一組訂閱、確實可以取消。
class AudioSessionFocusSource implements TtsAudioFocusSource {
  final StreamController<TtsAudioFocusEvent> _controller =
      StreamController<TtsAudioFocusEvent>.broadcast(sync: true);
  late final StreamSubscription<AudioInterruptionEvent> _interruptionSub;
  late final StreamSubscription<void> _noisySub;

  AudioSessionFocusSource(AudioSession session) {
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (!event.begin) {
        _controller.add(TtsAudioFocusEvent.focusGained);
        return;
      }
      // AudioInterruptionType.unknown 對應 Android AUDIOFOCUS_LOSS
      // （永久失焦）；pause／duck（本專案設定 androidWillPauseWhenDucked:
      // true 後，duck 事件不會發生，一律以 pause 型別送達）皆對應
      // AUDIOFOCUS_LOSS_TRANSIENT（暫時失焦）。
      _controller.add(event.type == AudioInterruptionType.unknown
          ? TtsAudioFocusEvent.permanentLoss
          : TtsAudioFocusEvent.transientLoss);
    });
    _noisySub = session.becomingNoisyEventStream.listen(
      (_) => _controller.add(TtsAudioFocusEvent.becomingNoisy),
    );
  }

  @override
  Stream<TtsAudioFocusEvent> get events => _controller.stream;

  @override
  void dispose() {
    // AudioSession 本身為 main.dart 建構、App 全生命週期共用的單例，本
    // 類別不擁有其生命週期、不關閉它；只取消自己對它的兩條訂閱。
    // main.dart 目前不會呼叫本方法（App 行程存續期間持續有效，比照既有
    // syncEngine/repository 等 main.dart 層級單例從不顯式 dispose 的
    // 既有慣例），但方法本身要能正確運作，供未來需要時或測試使用。
    _interruptionSub.cancel();
    _noisySub.cancel();
    _controller.close();
  }
}
