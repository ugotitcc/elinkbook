import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/tts_provider.dart';

void main() {
  test('TtsVoice.systemDefault 有固定的 id/displayName', () {
    expect(TtsVoice.systemDefault.id, 'system-default');
    expect(TtsVoice.systemDefault.displayName, '系統預設語音');
  });

  test('localizeTtsVoiceName：內建系統預設語音依介面語言轉譯，其他語音原樣顯示', () {
    final tw = lookupAppLocalizations(const Locale('zh', 'TW'));
    final cn = lookupAppLocalizations(const Locale('zh', 'CN'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(localizeTtsVoiceName(TtsVoice.systemDefault, tw), '系統預設語音');
    expect(localizeTtsVoiceName(TtsVoice.systemDefault, cn), '系统默认语音');
    expect(localizeTtsVoiceName(TtsVoice.systemDefault, en), 'System default voice');

    // 其他語音（例如未來雲端 Provider 回傳的語音）名稱是供應商資料，不翻譯
    const cloud = TtsVoice(id: 'cloud-1', displayName: 'Xiaoxiao (Cloud)');
    expect(localizeTtsVoiceName(cloud, tw), 'Xiaoxiao (Cloud)');
    expect(localizeTtsVoiceName(cloud, en), 'Xiaoxiao (Cloud)');
  });

  test('localizeTtsVoiceName：以 id 判斷內建語音，displayName 被改動也不影響', () {
    final en = lookupAppLocalizations(const Locale('en'));
    const renamed = TtsVoice(id: 'system-default', displayName: '別的名字');
    expect(localizeTtsVoiceName(renamed, en), 'System default voice');
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
