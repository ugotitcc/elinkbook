// app/lib/dictionary/providers/online_dictionary_provider.dart
import 'dictionary_provider.dart';

/// 線上查詢來源。獨立成型別，讓 `DictionaryService` 能依「同意狀態」
/// 決定要不要呼叫它。
abstract class OnlineDictionaryProvider implements DictionaryProvider {
  /// 面板分段與設定畫面顯示的名稱（例：`萌典`）。不走 l10n：來源名稱是
  /// 專有名詞，各語系一致。
  String get displayName;
}
