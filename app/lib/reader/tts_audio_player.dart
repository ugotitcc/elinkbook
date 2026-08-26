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
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _completedController.close();
    await _player.dispose();
  }
}
