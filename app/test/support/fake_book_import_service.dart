import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';

/// 供 widget test 使用的 [BookImportService] 假實作。預設立即回傳空清單；
/// 若設定 [pendingCompleter]，`importFiles`/`importFolder` 改為等待該
/// completer 完成才回傳（或拋出例外，取決於呼叫 `complete`/`completeError`），
/// 讓測試能控制「匯入尚未完成」的時間點（見 Issue 11：匯入處理中狀態回饋）。
class FakeBookImportService implements BookImportService {
  Completer<List<Book>>? pendingCompleter;

  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const []);
  }

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const []);
  }
}
