import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 記錄最近一次 [BookImportService.importFiles] 的呼叫參數，供測試斷言
/// 遠端下載落地時帶入的 source/remoteServerId/remoteBookIds/remoteDownloadUrls
/// 以及雲端匯入時帶入的 cloudFileIds。
class ImportCallRecord {
  final List<String> uris;
  final BookSource source;
  final String? remoteServerId;
  final Map<String, String>? remoteBookIds;
  final Map<String, String>? remoteDownloadUrls;
  final Map<String, String>? cloudFileIds;

  const ImportCallRecord({
    required this.uris,
    required this.source,
    this.remoteServerId,
    this.remoteBookIds,
    this.remoteDownloadUrls,
    this.cloudFileIds,
  });
}

/// 供 widget test 使用的 [BookImportService] 假實作。預設立即回傳空清單；
/// 若設定 [pendingCompleter]，`importFiles`/`importFolder` 改為等待該
/// completer 完成才回傳（或拋出例外，取決於呼叫 `complete`/`completeError`），
/// 讓測試能控制「匯入尚未完成」的時間點（見 Issue 11：匯入處理中狀態回饋）。
///
/// [lastImportCall] 記錄最近一次 `importFiles` 的完整參數，供測試驗證
/// 遠端書籍下載落地時是否正確傳入 metadata。
class FakeBookImportService implements BookImportService {
  Completer<ImportResult>? pendingCompleter;

  /// 最近一次 [importFiles] 的呼叫參數；首次呼叫前為 `null`。
  ImportCallRecord? lastImportCall;

  /// 最近一次 [importFolder] 的呼叫參數；首次呼叫前為 `null`。
  String? lastImportFolderUri;
  bool? lastAutoGroupByFolderName;

  @override
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
    Map<String, String>? cloudFileIds,
  }) {
    lastImportCall = ImportCallRecord(
      uris: uris,
      source: source,
      remoteServerId: remoteServerId,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
      cloudFileIds: cloudFileIds,
    );
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const ImportResult(importedBooks: []));
  }

  @override
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    lastImportFolderUri = folderUri;
    lastAutoGroupByFolderName = autoGroupByFolderName;
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const ImportResult(importedBooks: []));
  }
}
