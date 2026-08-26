import 'dart:async';

import 'package:elinkbook/reader/tts_provider.dart';

/// 測試用 Fake，比照 [FakeHighlightsRepository] 模式。每次 [synthesize]
/// 回傳一個遞增編號的假路徑，不做真的檔案 I/O 或語音合成。
class FakeTtsProvider implements TtsProvider {
  int synthesizeCallCount = 0;
  final List<String> synthesizedTexts = [];

  /// 測試設定後，下一次 [synthesize] 呼叫會拋出這個例外（拋出後自動
  /// 清空，只影響下一次呼叫），供驗證 [TtsController] 的例外處理。
  Object? nextSynthesizeError;

  /// 測試設定後，下一次 [synthesize] 呼叫會等待此 [Completer] 完成，
  /// 供驗證非同步合成期間的狀態與防重入邏輯。
  Completer<void>? nextSynthesizeCompleter;

  @override
  Future<List<TtsVoice>> getAvailableVoices() async => const [TtsVoice.systemDefault];

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    final completer = nextSynthesizeCompleter;
    if (completer != null) {
      nextSynthesizeCompleter = null;
      await completer.future;
    }
    final error = nextSynthesizeError;
    if (error != null) {
      nextSynthesizeError = null;
      throw error;
    }
    return TtsSynthesisResult(audioFilePath: '/fake/segment_$synthesizeCallCount.wav');
  }
}
