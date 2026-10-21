// app/test/support/fake_dictionary_settings_repository.dart
import 'package:elinkbook/dictionary/dictionary_settings_repository.dart';

/// 記憶體版的 [DictionarySettingsRepository]，供 service 與畫面測試使用。
class FakeDictionarySettingsRepository
    implements DictionarySettingsRepository {
  FakeDictionarySettingsRepository({this.consentAt});

  /// 目前同意時刻；`null` 代表未同意／已關閉。測試可直接改動。
  DateTime? consentAt;

  int loadCount = 0;
  int saveCount = 0;

  /// 為真時 [saveOnlineConsentAt] 丟 [StateError]，模擬寫入失敗。
  bool failOnSave = false;

  @override
  Future<DateTime?> loadOnlineConsentAt() async {
    loadCount++;
    return consentAt;
  }

  @override
  Future<void> saveOnlineConsentAt(DateTime? at) async {
    saveCount++;
    if (failOnSave) throw StateError('儲存失敗');
    consentAt = at;
  }
}
