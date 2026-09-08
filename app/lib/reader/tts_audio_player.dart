import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 朗讀音訊播放器抽象（epic-34-tts-readalong Issue 2）。存在的唯一理由
/// 是讓 [TtsController] 可在純 Dart 單元測試中注入 Fake 實作——
/// `just_audio` 的 `AudioPlayer` 依賴平台 channel，`flutter test`
/// 環境下無法真的播放音訊（無官方測試替身套件，比照本專案 WebView/
/// PlatformView 相關元件「flutter_test 測不到，真機才能驗證」的既有
/// 限制），故不直接讓 [TtsController] 持有具體的 `AudioPlayer`。
abstract class TtsAudioPlayer {
  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();

  /// 執行期變速（epic-34-tts-readalong Issue 5，spec.md「語速調整的生效
  /// 時機」契約）：只影響「目前已載入、可能正在播放/暫停中」的音訊，不
  /// 重新合成、不中斷播放。[speed] 為 `just_audio` 慣例的倍率語意
  /// （`1.0`＝正常速度），與 [TtsProvider.synthesize] 的 `speed` 參數
  /// （`flutter_tts` 慣例的 `0.0`（最慢）～`1.0`（最快）語意）刻度不同——
  /// [TtsController] 目前刻意把同一個數值直接轉發給兩邊 API，未做刻度
  /// 換算（見 `tts_controller.dart` 對應註解），真機實際聽感落差待真機
  /// 測試後再校準。
  Future<void> setSpeed(double speed);

  /// 真正停止播放並釋放底層音訊焦點（epic-38-reader-chrome-tts-redesign
  /// Issue 2）。相對於 [pause]（保留音訊焦點以便快速恢復），`just_audio`
  /// 的 `AudioPlayer.stop()` 會釋放平台音訊資源／音訊焦點——這正是「暫停」
  /// 與「真正停止」在音訊焦點語意上的既有官方區別。
  Future<void> stop();

  /// 目前載入的音訊播放完畢時發出一個事件（不攜帶資料）。
  Stream<void> get completedStream;

  Future<void> dispose();
}

/// [TtsAudioPlayer] 的正式實作，包一層 `just_audio` 的 [AudioPlayer]。
class JustAudioTtsPlayer implements TtsAudioPlayer {
  final AudioPlayer _player;
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  StreamSubscription<PlayerState>? _stateSub;

  JustAudioTtsPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!_completedController.isClosed) {
          _completedController.add(null);
        }
      }
    });
  }

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> loadFile(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _completedController.close();
    await _player.dispose();
  }
}
