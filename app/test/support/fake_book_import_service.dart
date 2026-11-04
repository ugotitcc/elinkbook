import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 記錄最近一次 [BookImportService.importFiles] 的呼叫參數，供測試斷言
/// 遠端下載落地時帶入的 source/remoteServerId/remoteBookIds/remoteDownloadUrls
/// 以及雲端匯入時帶入的 cloudFileIds。
class ImportCallRecord {
  final List<String> uris;
  final List<String?>? displayNames;
  final String? folderName;
  final BookSource source;
  final String? remoteServerId;
  final Map<String, String>? remoteBookIds;
  final Map<String, String>? remoteDownloadUrls;
  final Map<String, String>? cloudFileIds;

  const ImportCallRecord({
    required this.uris,
    this.displayNames,
    this.folderName,
    required this.source,
    this.remoteServerId,
    this.remoteBookIds,
    this.remoteDownloadUrls,
    this.cloudFileIds,
  });
}

/// 記錄一次 [BookImportService.relinkBook] 的呼叫參數
/// （epic-15-storage-permission Issue 2）。
class RelinkCallRecord {
  final String bookId;
  final String newUri;
  final String? displayName;

  const RelinkCallRecord({
    required this.bookId,
    required this.newUri,
    this.displayName,
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

  /// [importFiles] 的回傳結果，預設為空結果。
  ImportResult importFilesResult = const ImportResult(importedBooks: []);

  /// [importFolder] 的回傳結果，預設為空結果。
  ImportResult importFolderResult = const ImportResult(importedBooks: []);

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
      displayNames: displayNames,
      folderName: folderName,
      source: source,
      remoteServerId: remoteServerId,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
      cloudFileIds: cloudFileIds,
    );
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(importFilesResult);
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
    return Future.value(importFolderResult);
  }

  /// epic-15-storage-permission Issue 2：[relinkBook] 的回傳值，預設為
  /// `failed`。測試可改成 [BookRelinkSuccess] 或其他失敗原因。
  BookRelinkResult relinkResult =
      const BookRelinkFailure(BookRelinkFailureReason.failed);

  /// 設定時 [relinkBook] 改為等待此 completer，讓測試控制「處理中」的時間點。
  Completer<BookRelinkResult>? relinkCompleter;

  /// 設定時 [relinkBook] 回傳 `Future.error(relinkError)`，模擬服務拋出例外。
  Object? relinkError;

  /// 每次 [relinkBook] 的呼叫參數，依呼叫順序排列。
  final List<RelinkCallRecord> relinkCalls = [];

  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) {
    relinkCalls.add(RelinkCallRecord(
      bookId: bookId,
      newUri: newUri,
      displayName: displayName,
    ));
    final error = relinkError;
    if (error != null) return Future.error(error);
    final completer = relinkCompleter;
    if (completer != null) return completer.future;
    return Future.value(relinkResult);
  }

  /// epic-67 Issue 1 Task 3：更新版偵測預設回傳新書。
  BookDetectionResult detectResult = const DetectedNewBook();

  @override
  Future<BookDetectionResult> detectBookUpdate(
    String uri, {
    String? displayName,
  }) =>
      Future.value(detectResult);

  final List<BookUpdateCandidate> discardedCandidates = [];

  @override
  Future<void> discardUpdateCandidate(BookUpdateCandidate candidate) {
    discardedCandidates.add(candidate);
    return Future.value();
  }

  BookReplaceResult replaceResult =
      const BookReplaceFailure(BookReplaceFailureReason.bookNotFound);

  /// 依 [bookId] 設定指定書籍的取代結果；優先於 [replaceResult]。
  final Map<String, BookReplaceResult> replaceResultsByBookId = {};

  /// 設定時 [replaceBook] 拋出此例外。
  Object? replaceThrows;

  final List<(String, String)> replaceCalls = [];

  @override
  Future<BookReplaceResult> replaceBook(
    String bookId,
    String newUri, {
    String? displayName,
    BookUpdateCandidate? candidate,
    BookSourceRefs? sourceRefs,
  }) {
    replaceCalls.add((bookId, newUri));
    final error = replaceThrows;
    if (error != null) return Future.error(error);
    final result = replaceResultsByBookId[bookId] ?? replaceResult;
    return Future.value(result);
  }

  Book? importCandidateResult;
  final List<BookUpdateCandidate> importCandidateCalls = [];

  @override
  Future<Book?> importCandidateAsNewBook(
    BookUpdateCandidate candidate, {
    String? folderName,
    BookSourceRefs? sourceRefs,
  }) {
    importCandidateCalls.add(candidate);
    return Future.value(importCandidateResult);
  }
}
