import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的 [BookImportService] 假實作。預設立即回傳空清單；
/// 若設定 [pendingCompleter]，`importFiles`/`importFolder` 改為等待該
/// completer 完成才回傳（或拋出例外，取決於呼叫 `complete`/`completeError`），
/// 讓測試能控制「匯入尚未完成」的時間點（見 Issue 11：匯入處理中狀態回饋）。
class FakeBookImportService implements BookImportService {
  Completer<ImportResult>? pendingCompleter;

  @override
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const ImportResult(importedBooks: []));
  }

  @override
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const ImportResult(importedBooks: []));
  }
}
