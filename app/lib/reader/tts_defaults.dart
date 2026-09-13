/// 朗讀（TTS）預設值（epic-36-adaptive-shelf-navigation Issue 5），從
/// `GlobalReaderPrefs` 拆出（2026-09-13，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
class TtsDefaults {
  /// 預設語音 id。`null` 代表「使用系統預設語音」——語意上沒有一個放諸
  /// 四海皆準的安全非空預設值，是本類別唯一 nullable 的欄位。
  final String? ttsVoiceId;

  /// 預設語速，範圍 0.75x~2.0x（`DESIGN.md#L307` §13.2），預設 `1.0`。
  final double defaultTtsSpeed;

  const TtsDefaults({
    this.ttsVoiceId,
    this.defaultTtsSpeed = 1.0,
  });

  const TtsDefaults.initial() : this();

  TtsDefaults copyWith({
    String? ttsVoiceId,
    double? defaultTtsSpeed,
  }) {
    return TtsDefaults(
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      defaultTtsSpeed: defaultTtsSpeed ?? this.defaultTtsSpeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TtsDefaults &&
      other.ttsVoiceId == ttsVoiceId &&
      other.defaultTtsSpeed == defaultTtsSpeed;

  @override
  int get hashCode => Object.hash(ttsVoiceId, defaultTtsSpeed);
}
