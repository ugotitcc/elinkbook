// app/lib/dictionary/importers/dictionary_importer.dart

/// 取消匯入的信號。呼叫端 `cancel()` 後，匯入器在下一批寫入前檢查
/// `isCancelled` 並中止。
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 一次匯入的輸入。
class ImportRequest {
  const ImportRequest({
    required this.filePath,
    required this.fileName,
    required this.sourceLang,
    required this.targetLang,
    this.name,
    this.licenseNote = '',
    this.replaceExisting = false,
  });

  final String filePath;
  final String fileName;
  final String sourceLang;
  final String targetLang;

  /// 使用者指定的字典名稱；`null` 時由檔案內容或檔名決定。
  final String? name;
  final String licenseNote;

  /// `true` 時，若已匯入同一內容的字典，在同一個交易內取代它。
  final bool replaceExisting;
}

/// 匯入進行到哪個階段。
enum ImportStage { parsing, writing, done, cancelled }

/// 被略過的一筆資料。[index] 為檔內第幾筆（從 1 起算）；[reason] 為
/// `missingHeadword`、`missingDefinition`、`definitionTooLong`、
/// `malformedLine` 之一。
class ImportSkip {
  const ImportSkip({required this.index, required this.reason});

  final int index;
  final String reason;
}

/// 匯入完成後的摘要。[skipSamples] 最多 5 筆。
class ImportSummary {
  const ImportSummary({
    required this.sourceId,
    required this.importedCount,
    required this.skippedCount,
    required this.skipSamples,
  });

  final String sourceId;
  final int importedCount;
  final int skippedCount;
  final List<ImportSkip> skipSamples;
}

/// 匯入進度。[summary] 只在 [ImportStage.done] 時有值。
class ImportProgress {
  const ImportProgress({
    required this.processed,
    required this.total,
    this.stage = ImportStage.writing,
    this.summary,
  });

  final int processed;
  final int total;
  final ImportStage stage;
  final ImportSummary? summary;
}

/// 選檔後預填匯入畫面用的資訊；檔案沒有的欄位為 `null`。
class ImportHints {
  const ImportHints({
    required this.name,
    this.sourceLang,
    this.targetLang,
    this.licenseNote,
  });

  final String name;
  final String? sourceLang;
  final String? targetLang;
  final String? licenseNote;
}

/// 匯入失敗。[code] 為 `unreadableFile`、`invalidEncoding`、`invalidFormat`、
/// `noValidEntries` 之一。
class DictionaryImportException implements Exception {
  const DictionaryImportException(this.code);

  final String code;

  @override
  String toString() => 'DictionaryImportException($code)';
}

/// 同一內容的字典已匯入過。[existingSourceId] 為既有來源的 id。
class DuplicateDictionaryException implements Exception {
  const DuplicateDictionaryException(this.existingSourceId);

  final String existingSourceId;

  @override
  String toString() => 'DuplicateDictionaryException($existingSourceId)';
}

abstract class DictionaryImporter {
  bool canHandle(String fileName);

  /// 讀檔頭的名稱、語言與授權，供匯入畫面預填。
  Future<ImportHints> readHints(String filePath, String fileName);

  Stream<ImportProgress> import(
    ImportRequest request, {
    required CancelToken cancel,
  });
}
