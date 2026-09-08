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

  /// 測試設定後，[getMaxInputLength] 回傳這個值（預設 `null`，代表未
  /// 設定任何上限，等同引擎未回報——既有測試不需要修改即可維持原行為，
  /// 因為 [TtsController] 在 `null` 時不套用硬性長度上限防線，見
  /// epic-34-tts-readalong Issue 11）。
  int? maxInputLength;

  @override
  Future<int?> getMaxInputLength() async => maxInputLength;

  @override
  Future<List<TtsVoice>> getAvailableVoices() async => const [TtsVoice.systemDefault];

  /// 記錄每次 [synthesize] 呼叫實際收到的 `speed` 參數（epic-34-tts-readalong
  /// Issue 5），供測試驗證「下一段」合成確實套用了呼叫當下的最新語速。
  final List<double> synthesizeSpeeds = [];

  /// 記錄每次 [synthesize] 呼叫實際收到的 `voice` 參數（epic-38-reader-
  /// chrome-tts-redesign Issue 2），供測試驗證 `TtsController.setVoice()`
  /// 後「下一段」合成確實套用了新語音，而不是依然寫死
  /// `TtsVoice.systemDefault`。
  final List<TtsVoice> synthesizeVoices = [];

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    synthesizeSpeeds.add(speed);
    synthesizeVoices.add(voice);
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
