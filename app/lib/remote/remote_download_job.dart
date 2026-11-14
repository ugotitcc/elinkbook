import 'dart:io';

import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/book_update_models.dart';
import '../library/book_file_format.dart';
import '../library/book_update_settle.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import 'opds_client.dart';
import 'opds_types.dart';
import 'remote_book_downloader.dart';
import 'remote_server_profile.dart';

/// OPDS／Calibre 遠端書庫下載工作，實作 [QueuedDownloadJob]，讓
/// [DownloadQueueController] 能在不認得 [OpdsClient]／[OpdsEntry] 的情況
/// 下驅動這筆下載。內部邏輯搬自原本 `RemoteCatalogScreen._DownloadQueueDialog`
/// （已刪除）的 `_downloadOne()`。
///
/// 【行為調整】原本的批次匯入（整批下載完才一次呼叫 `importFiles()`）
/// 改為每筆下載完成後各自呼叫一次（見 [DownloadQueueController] 類別
/// 文件說明），與雲端硬碟版本的既有行為一致，結果對圖書庫而言等價。
class RemoteDownloadJob implements QueuedDownloadJob {
  final OpdsEntry entry;
  final OpdsAcquisition acquisition;
  final OpdsClient client;
  final RemoteServerProfile server;
  final String? password;
  final BookImportService importService;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprintFn;

  final OpdsDownloadCancellationToken _token = OpdsDownloadCancellationToken();

  RemoteDownloadJob({
    required this.entry,
    required this.acquisition,
    required this.client,
    required this.server,
    required this.password,
    required this.importService,
    required this.libraryRepository,
    required this.computeFingerprintFn,
  });

  @override
  String get id => entry.remoteBookId;

  @override
  String get name => entry.title;

  @override
  Future<String> download({
    required void Function(int received, int total) onProgress,
  }) {
    return downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      // acquisition.format 在此保證非 null：能進入下載佇列的項目，其
      // acquisition 必然已通過 `_startDownload()` 的格式過濾（見
      // RemoteCatalogScreen 既有邏輯）。
      format: acquisition.format!,
      password: password,
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
    return computeFingerprintFn(tempPath, acquisition.format!);
  }

  @override
  Future<bool> hasDuplicate(String fingerprint) async {
    return await libraryRepository.findByContentFingerprint(fingerprint) !=
        null;
  }

  @override
  Future<String> promote(String tempPath) => promoteToPermanent(tempPath);

  @override
  Future<void> import(String permanentPath) async {
    final result = await importService.importFiles(
      [permanentPath],
      source: BookSource.calibreOpds,
      remoteServerId: server.id,
      remoteBookIds: {permanentPath: entry.remoteBookId},
      remoteDownloadUrls: {permanentPath: acquisition.href},
    );
    if (result.updateCandidates.isNotEmpty) {
      final refs = BookSourceRefs(
        source: BookSource.calibreOpds,
        remoteServerId: server.id,
        remoteBookId: entry.remoteBookId,
        remoteDownloadUrl: acquisition.href,
      );
      var anyImported = false;
      for (final candidate in result.updateCandidates) {
        try {
          final book = await importService.importCandidateAsNewBook(
            candidate,
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

  /// OPDS 遠端書庫用 HTTP Basic Auth 或匿名，沒有「重新連結帳號」的概念
  /// （與雲端匯入的 OAuth 不同，見 `CONTEXT.md`「遠端書庫」）。
  @override
  bool isAuthFailure(Object error) => false;

  @override
  Future<BookUpdateCandidate?> detectUpdate(String tempPath) async {
    try {
      final ext = acquisition.format!.fileExtension;
      final displayName = '${entry.title}.$ext';
      final result = await importService.detectBookUpdate(
        tempPath,
        displayName: displayName,
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
        source: BookSource.calibreOpds,
        remoteServerId: server.id,
        remoteBookId: entry.remoteBookId,
        remoteDownloadUrl: acquisition.href,
      ),
    );
  }
}
