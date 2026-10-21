// app/lib/dictionary/dictionary_settings_repository.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 線上查詞的同意狀態（spec §3.4、§7）。
///
/// 只有一個值：有值＝已同意且已開啟；`null`＝關閉。關閉等於撤回同意，
/// 沒有「同意了但關著」這種需要保存的狀態，所以不另外存開關。
abstract class DictionarySettingsRepository {
  Future<DateTime?> loadOnlineConsentAt();

  /// 傳入 `null` 代表關閉並清除同意紀錄。
  Future<void> saveOnlineConsentAt(DateTime? at);
}

/// `shared_preferences` 實作；值為 UTC 的 ISO 8601 字串。
class SharedPreferencesDictionarySettingsRepository
    implements DictionarySettingsRepository {
  static const String onlineConsentKey = 'dictionary_online_consent_at';

  @override
  Future<DateTime?> loadOnlineConsentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(onlineConsentKey);
    if (raw == null) return null;
    // 壞字串（資料被污染、舊版格式）一律視為未同意，不當掉。
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> saveOnlineConsentAt(DateTime? at) async {
    final prefs = await SharedPreferences.getInstance();
    if (at == null) {
      await prefs.remove(onlineConsentKey);
    } else {
      await prefs.setString(onlineConsentKey, at.toUtc().toIso8601String());
    }
  }
}
