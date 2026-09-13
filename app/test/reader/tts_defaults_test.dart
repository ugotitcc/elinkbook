import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_defaults.dart';

void main() {
  test('TtsDefaults.initial() 的 ttsVoiceId 為 null（系統預設語音）、defaultTtsSpeed 為 1.0',
      () {
    const prefs = TtsDefaults.initial();
    expect(prefs.ttsVoiceId, isNull);
    expect(prefs.defaultTtsSpeed, 1.0);
  });

  test('copyWith 可個別更新 ttsVoiceId／defaultTtsSpeed，不影響另一欄位', () {
    const original = TtsDefaults.initial();
    final updated = original.copyWith(defaultTtsSpeed: 1.5);
    expect(updated.defaultTtsSpeed, 1.5);
    expect(updated.ttsVoiceId, isNull);

    final withVoice = original.copyWith(ttsVoiceId: 'voice-1');
    expect(withVoice.ttsVoiceId, 'voice-1');
    expect(withVoice.defaultTtsSpeed, 1.0);
  });

  test('兩個欄位值皆相同的 TtsDefaults 視為相等（含 ttsVoiceId 皆為 null）', () {
    const a = TtsDefaults.initial();
    const b = TtsDefaults.initial();
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('ttsVoiceId 或 defaultTtsSpeed 不同時視為不相等', () {
    const a = TtsDefaults.initial();
    final b = a.copyWith(ttsVoiceId: 'voice-1');
    expect(a == b, isFalse);
    final c = a.copyWith(defaultTtsSpeed: 1.25);
    expect(a == c, isFalse);
  });
}
