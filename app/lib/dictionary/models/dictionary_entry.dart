// app/lib/dictionary/models/dictionary_entry.dart

/// 詞條內容的格式：純文字，或需要 WebView 顯示的 HTML。
enum EntryBodyKind { plainText, html }

/// 一筆詞條（對應 `dictionary_entries` 表的一列）。
class DictionaryEntry {
  const DictionaryEntry({
    required this.sourceId,
    required this.headword,
    required this.body,
    required this.bodyKind,
    this.pronunciation,
    this.partOfSpeech,
  });

  final String sourceId;
  final String headword;
  final String? pronunciation;
  final String? partOfSpeech;
  final String body;
  final EntryBodyKind bodyKind;
}

/// 詞頭的比對用正規化（對應 `headword_norm` 欄位，spec §4）。
///
/// 寫入與查詢都呼叫這一個函式，公式只存在這裡。
/// 刻意不做 Unicode 正規化（spec §3.4）。
String headwordNorm(String headword) => headword.trim().toLowerCase();
