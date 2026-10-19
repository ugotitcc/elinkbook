// app/lib/dictionary/lemmatize/lemmatizer.dart
import 'english_lemmatizer.dart';

/// 輸入一個詞，回傳有序的詞元候選（可能為空），不含輸入本身。
typedef Lemmatizer = List<String> Function(String word);

/// 語言登錄表，鍵為主語言碼。目前只有英文；其他語言不套用英文規則。
const Map<String, Lemmatizer> _lemmatizers = {
  'en': lemmatizeEnglish,
};

/// 依 [lang] 的主語言碼（`en-US`→`en`，不分大小寫）查登錄表並還原 [word]。
/// 未登錄的語言回傳空清單。
List<String> lemmatize(String lang, String word) {
  final primary = lang.toLowerCase().split(RegExp(r'[-_]')).first;
  final lemmatizer = _lemmatizers[primary];
  return lemmatizer == null ? const [] : lemmatizer(word);
}
