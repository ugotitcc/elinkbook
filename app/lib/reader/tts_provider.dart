/// 語音朗讀（TTS）的語音來源抽象（epic-34-tts-readalong Issue 2，
/// spec.md「Implementation Decisions」）。三種實作對應不同 Phase：
/// [SystemTtsProvider]（Phase 1，本 Issue）、雲端 API（Phase 2）、端側
/// 神經語音（Phase 3，stretch goal，皆未實作於本 Issue）。
abstract class TtsProvider {
  Future<List<TtsVoice>> getAvailableVoices();

  /// 合成 [text] 為音訊檔並回傳結果。音訊管線統一走檔案合成（見
  /// design.md 決策 9），不支援直接輸出喇叭的即時朗讀。
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  });
}

/// 單一可用語音。Phase 1 僅有系統預設語音，[id]/[displayName] 皆為固定值
/// （見 [TtsVoice.systemDefault]），Phase 2 起雲端 Provider 會回傳多筆。
class TtsVoice {
  final String id;
  final String displayName;

  const TtsVoice({required this.id, required this.displayName});

  static const systemDefault = TtsVoice(
    id: 'system-default',
    displayName: '系統預設語音',
  );

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.id == id && other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, displayName);
}

/// [TtsProvider.synthesize] 的合成結果。[wordTimings] 為字級時間戳記，
/// Phase 1 系統語音不提供，恆為空清單（見 [TtsWordTiming]）。
class TtsSynthesisResult {
  final String audioFilePath;
  final List<TtsWordTiming> wordTimings;

  const TtsSynthesisResult({
    required this.audioFilePath,
    this.wordTimings = const [],
  });
}

/// 字級時間戳記（Phase 1 未使用，保留供未來字級高亮擴充，見
/// spec.md Out of Scope「單詞級高亮」）。
class TtsWordTiming {
  final String text;
  final int startMs;
  final int endMs;

  const TtsWordTiming({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}

/// [TtsProvider.synthesize] 合成失敗時拋出。
class TtsSynthesisException implements Exception {
  final String message;
  const TtsSynthesisException(this.message);

  @override
  String toString() => 'TtsSynthesisException: $message';
}
