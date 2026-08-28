import 'dart:async';

import 'package:elinkbook/reader/tts_audio_focus_source.dart';

/// 測試用 Fake，比照 [FakeTtsAudioPlayer] 模式。[emit] 讓測試主動送出
/// 合成的焦點事件，不依賴真實系統廣播（epic-34-tts-readalong Issue 7，
/// 審查 `review-issues.md` Important #2「測試分流」自動化層）。
class FakeTtsAudioFocusSource implements TtsAudioFocusSource {
  final StreamController<TtsAudioFocusEvent> _controller =
      StreamController<TtsAudioFocusEvent>.broadcast(sync: true);
  bool disposed = false;

  @override
  Stream<TtsAudioFocusEvent> get events => _controller.stream;

  void emit(TtsAudioFocusEvent event) => _controller.add(event);

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}
