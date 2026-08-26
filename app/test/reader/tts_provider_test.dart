import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_provider.dart';

void main() {
  test('TtsVoice.systemDefault 有固定的 id/displayName', () {
    expect(TtsVoice.systemDefault.id, 'system-default');
    expect(TtsVoice.systemDefault.displayName, '系統預設語音');
  });

  test('TtsVoice 相等性依 id/displayName 判斷', () {
    const a = TtsVoice(id: 'x', displayName: 'X');
    const b = TtsVoice(id: 'x', displayName: 'X');
    const c = TtsVoice(id: 'y', displayName: 'Y');
    expect(a, equals(b));
    expect(a == c, isFalse);
  });

  test('TtsSynthesisResult 預設 wordTimings 為空清單', () {
    const result = TtsSynthesisResult(audioFilePath: '/tmp/a.wav');
    expect(result.wordTimings, isEmpty);
  });

  test('TtsSynthesisException.toString() 含錯誤訊息', () {
    const exception = TtsSynthesisException('合成失敗');
    expect(exception.toString(), contains('合成失敗'));
  });
}
