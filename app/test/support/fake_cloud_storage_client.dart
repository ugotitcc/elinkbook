import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:elinkbook/cloud_import/cloud_storage_client.dart';

/// 供 widget test 使用的記憶體內 [CloudStorageClient] 假實作（比照
/// `FakeOpdsClient` 既有命名慣例）。
class FakeCloudStorageClient implements CloudStorageClient {
  /// 依 folderId（`null` 代表根目錄）預先塞入要回傳的清單。
  final Map<String?, CloudFolderListing> folderContents;

  /// 依 [CloudFileEntry.id] 預先塞入下載成功要寫入的位元組內容；未設定
  /// 的 id 呼叫 [downloadFile] 會拋出例外（模擬下載失敗）。
  final Map<String, List<int>> downloadContents;

  /// 若設定，[downloadFile] 改為等待這個 completer 完成才繼續（或拋出
  /// 例外），供測試模擬「下載中」與「使用者中途取消」情境（比照
  /// `FakeOpdsClient` 既有的 `downloadDelayCompleter` 模式）。
  Completer<void>? pendingDownloadCompleter;

  /// 記錄每次 [downloadFile] 呼叫的 entry id，供測試驗證序列下載順序。
  final List<String> downloadCalls = [];

  Uint8List? thumbnailBytes;

  /// 若設定，[fetchThumbnail] 改為等待這個 completer 完成才回傳，供測試
  /// 模擬「縮圖仍在載入中」的窗口（review-issue-3.md Important #2 迴歸
  /// 測試：驗證這段窗口內畫面重建不會重複發起請求）。
  Completer<void>? pendingThumbnailCompleter;

  /// 記錄每次 [fetchThumbnail] 呼叫的 thumbnailUrl，供測試驗證同一張縮圖
  /// 在完成前是否被重複請求。
  final List<String> fetchThumbnailCalls = [];

  FakeCloudStorageClient({
    this.folderContents = const {},
    this.downloadContents = const {},
  });

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    return folderContents[folderId] ?? const CloudFolderListing();
  }

  @override
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  }) async {
    downloadCalls.add(entry.id);
    final completer = pendingDownloadCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (cancellationToken?.isCancelled ?? false) {
      throw Exception('下載已取消');
    }
    final bytes = downloadContents[entry.id];
    if (bytes == null) {
      throw Exception('模擬下載失敗：${entry.id}');
    }
    final file = File(destinationPath);
    await file.writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return file;
  }

  @override
  Future<Uint8List> fetchThumbnail(String thumbnailUrl) async {
    fetchThumbnailCalls.add(thumbnailUrl);
    final completer = pendingThumbnailCompleter;
    if (completer != null) {
      await completer.future;
    }
    return thumbnailBytes ?? Uint8List(0);
  }
}
