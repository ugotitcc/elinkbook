import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
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
  Future<void> import(String permanentPath) {
    return importService.importFiles(
      [permanentPath],
      source: BookSource.calibreOpds,
      remoteServerId: server.id,
      remoteBookIds: {permanentPath: entry.remoteBookId},
      remoteDownloadUrls: {permanentPath: acquisition.href},
    );
  }
}
