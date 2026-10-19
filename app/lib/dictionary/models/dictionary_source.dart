// app/lib/dictionary/models/dictionary_source.dart

/// 字典來源的格式。stardict 之後再加。
enum DictionaryFormat { jsonCsv, cedict, mdx }

/// 一本已匯入的字典（對應 `dictionary_sources` 表的一列）。
class DictionarySource {
  const DictionarySource({
    required this.id,
    required this.name,
    required this.format,
    required this.sourceLang,
    required this.targetLang,
    required this.priority,
    required this.enabled,
    required this.storagePath,
    required this.entryCount,
    required this.licenseNote,
    required this.importedAt,
  });

  final String id;
  final String name;
  final DictionaryFormat format;

  /// 來源語言，例：`en`、`zh`。
  final String sourceLang;

  /// 目標語言，例：`zh-Hant`、`en`。
  final String targetLang;

  /// 數字小者先查。
  final int priority;
  final bool enabled;

  /// MDX 原檔路徑；JSON/CSV 為空字串。
  final String storagePath;
  final int entryCount;

  /// 使用者匯入時可填，顯示用。
  final String licenseNote;
  final DateTime importedAt;
}
