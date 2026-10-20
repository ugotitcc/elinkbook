// app/lib/dictionary/storage/dictionary_store_provider.dart
import 'dictionary_store.dart';

/// 共用的延遲開啟 [DictionaryStore]：查詢服務與管理服務拿同一個 provider，
/// `dictionary.db` 只會開一次。
///
/// 第一次 [call] 才呼叫 `open` 並記住；開啟失敗不記住，下一次 [call] 重試。
/// 字典是邊緣功能，開檔失敗不應擋住 App 啟動。
class DictionaryStoreProvider {
  DictionaryStoreProvider(this._open);

  final Future<DictionaryStore> Function() _open;
  Future<DictionaryStore>? _opening;

  Future<DictionaryStore> call() async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      // 失敗不快取，讓下一次呼叫重試。
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }
}
