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

  /// 測試設定後，下一次 [loadFile] 呼叫會等待此 [Completer] 完成，
  /// 供驗證檔案載入非同步期間的狀態機與暫停中斷邏輯。
  Completer<void>? nextLoadFileCompleter;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> loadFile(String path) async {
    loadedFiles.add(path);
    callLog.add('loadFile');
    final completer = nextLoadFileCompleter;
    if (completer != null) {
      nextLoadFileCompleter = null;
      await completer.future;
    }
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
