// app/test/dictionary/dictionary_settings_repository_test.dart
import 'package:elinkbook/dictionary/dictionary_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('預設為 null', () async {
    final repository = SharedPreferencesDictionarySettingsRepository();

    expect(await repository.loadOnlineConsentAt(), isNull);
  });

  test('存入後讀回同一時刻', () async {
    final repository = SharedPreferencesDictionarySettingsRepository();
    final at = DateTime.utc(2026, 10, 21, 8);

    await repository.saveOnlineConsentAt(at);

    final loaded = await repository.loadOnlineConsentAt();
    expect(loaded, isNotNull);
    expect(loaded!.isAtSameMomentAs(at), isTrue);
  });

  test('存 null 會移除鍵', () async {
    final repository = SharedPreferencesDictionarySettingsRepository();
    await repository.saveOnlineConsentAt(DateTime.utc(2026, 10, 21, 8));

    await repository.saveOnlineConsentAt(null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('dictionary_online_consent_at'), isFalse);
    expect(await repository.loadOnlineConsentAt(), isNull);
  });

  test('壞字串視為 null', () async {
    SharedPreferences.setMockInitialValues({
      'dictionary_online_consent_at': 'not-a-date',
    });
    final repository = SharedPreferencesDictionarySettingsRepository();

    expect(await repository.loadOnlineConsentAt(), isNull);
  });
}
