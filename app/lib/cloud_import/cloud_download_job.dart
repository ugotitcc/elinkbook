import 'dart:io';

import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/book_update_models.dart';
import '../library/book_update_settle.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import 'cloud_book_downloader.dart';
import 'cloud_storage_client.dart';

/// 雲端硬碟（Google Drive／OneDrive）下載工作，實作 [QueuedDownloadJob]，
/// 讓 [DownloadQueueController] 能在不認得 [CloudStorageClient]／
/// [CloudFileEntry] 的情況下驅動這筆下載。內部邏輯搬自原本
/// `CloudDownloadQueueDialog`（已刪除）的 `_downloadOne()`。
class CloudDownloadJob implements QueuedDownloadJob {
  final CloudFileEntry entry;
  final CloudStorageClient client;
  final BookImportService importService;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprintFn;
  final BookSource source;
  final String? folderName;

  final CloudDownloadCancellationToken _token =
      CloudDownloadCancellationToken();

  CloudDownloadJob({
    required this.entry,
    required this.client,
    required this.importService,
    required this.libraryRepository,
    required this.computeFingerprintFn,
    required this.source,
    this.folderName,
  });

  @override
  String get id => entry.id;

  @override
  String get name => entry.name;

  @override
  Future<String> download({
    required void Function(int received, int total) onProgress,
  }) {
    return downloadCloudFileToTempFile(
      client: client,
      entry: entry,
      cancellationToken: _token,
      onProgress: onProgress,
    );
  }

  @override
  void cancel() => _token.cancel();

  @override
  bool get isCancelled => _token.isCancelled;

  @override
  Future<String> computeFingerprint(String tempPath) {
    // entry.format 在此保證非 null：能被使用者勾選、進而進入下載佇列的
    // 檔案，其 format 必然已通過 detectBookFileFormatByNameAndMime() 驗證（見
    // CloudBrowserScreen 既有註解）。
    return computeFingerprintFn(tempPath, entry.format!);
  }

  @override
  Future<bool> hasDuplicate(String fingerprint) async {
    return await libraryRepository.findByContentFingerprint(fingerprint) !=
        null;
  }

  @override
  Future<String> promote(String tempPath) =>
      promoteCloudFileToPermanent(tempPath);

  @override
  Future<void> import(String permanentPath) async {
    final result = await importService.importFiles(
      [permanentPath],
      folderName: folderName,
      source: source,
      cloudFileIds: {permanentPath: entry.id},
    );
    if (result.updateCandidates.isNotEmpty) {
      final refs = BookSourceRefs(source: source, cloudFileId: entry.id);
      var anyImported = false;
      for (final candidate in result.updateCandidates) {
        try {
          final book = await importService.importCandidateAsNewBook(
            candidate,
            folderName: folderName,
            sourceRefs: refs,
          );
          if (book != null) anyImported = true;
        } catch (_) {}
      }
      try {
        final file = File(permanentPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      // 一本都沒成功並存：不得讓項目顯示「完成」（檔案已刪、書庫裡沒有這本書）。
      // 丟出例外使控制器標記為 failed，使用者可重試重新下載（審查 I-1）。
      if (!anyImported) {
        throw StateError('更新版保底並存匯入失敗');
      }
    }
  }

  @override
  bool isAuthFailure(Object error) => error is CloudAuthRequiredException;

  @override
  Future<BookUpdateCandidate?> detectUpdate(String tempPath) async {
    try {
      final result = await importService.detectBookUpdate(
        tempPath,
        displayName: entry.name,
      );
      if (result is DetectedUpdate && result.candidate.stagedPath != null) {
        return result.candidate;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BookUpdateSettleResult> settleUpdate(
    BookUpdateCandidate candidate,
    BookUpdateChoice choice,
  ) {
    return settleBookUpdate(
      importService,
      candidate,
      choice,
      sourceRefs: BookSourceRefs(
        source: source,
        cloudFileId: entry.id,
      ),
      folderName: folderName,
    );
  }
}
