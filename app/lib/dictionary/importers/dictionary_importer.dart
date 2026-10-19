// app/lib/dictionary/importers/dictionary_importer.dart

/// 取消匯入的信號。呼叫端 `cancel()` 後，匯入器在下一批寫入前檢查
/// `isCancelled` 並中止。
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 一次匯入的輸入。Issue 3 需要時再擴充欄位。
class ImportRequest {
  const ImportRequest({
    required this.filePath,
    required this.fileName,
    required this.sourceLang,
    required this.targetLang,
  });

  final String filePath;
  final String fileName;
  final String sourceLang;
  final String targetLang;
}

/// 匯入進度。
class ImportProgress {
  const ImportProgress({required this.processed, required this.total});

  final int processed;
  final int total;
}

abstract class DictionaryImporter {
  bool canHandle(String fileName);

  Stream<ImportProgress> import(
    ImportRequest request, {
    required CancelToken cancel,
  });
}
