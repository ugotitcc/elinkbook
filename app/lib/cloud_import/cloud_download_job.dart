import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
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
    // 檔案，其 format 必然已通過 detectCloudFileFormat() 驗證（見
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
  Future<void> import(String permanentPath) {
    return importService.importFiles(
      [permanentPath],
      folderName: folderName,
      source: source,
      cloudFileIds: {permanentPath: entry.id},
    );
  }
}
