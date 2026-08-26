import 'dart:async';

import 'package:elinkbook/reader/tts_audio_player.dart';

/// 測試用 Fake，比照 [FakeHighlightsRepository] 模式。記錄呼叫順序供
/// 測試斷言，[simulateCompleted] 讓測試主動觸發「目前段落播放完畢」。
class FakeTtsAudioPlayer implements TtsAudioPlayer {
  final List<String> loadedFiles = [];
  final List<String> callLog = [];
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  bool disposed = false;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> loadFile(String path) async {
    loadedFiles.add(path);
    callLog.add('loadFile');
  }

  @override
  Future<void> play() async {
    callLog.add('play');
  }

  @override
  Future<void> pause() async {
    callLog.add('pause');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completedController.close();
  }

  void simulateCompleted() => _completedController.add(null);
}
