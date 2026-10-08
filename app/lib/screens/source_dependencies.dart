import 'package:flutter/foundation.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
import '../remote/remote_thumbnail_cache.dart';
import '../wifi_transfer/network_availability.dart';

/// 來源依賴組（ADR 0037）：雲端帳號與 Google Drive／OneDrive、OPDS／Calibre 遠端書庫、
/// 下載佇列、WiFi 傳書的網路偵測，以及這些來源共用的內容指紋與行動網路判斷。
/// 「來源」頁（`SourcesHomeScreen`）、書架（重新下載遠端書）與設定頁（雲端帳號入口）
/// 接收這一個物件，取代 epic-26 Issue 7 的雲端／遠端 bundle 與 epic-44 的
/// WiFi 傳書 bundle。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好。WiFi 傳書不設開關（正式
/// 環境恆提供，見 ADR 0037 §3）。`computeFingerprint` 同時服務雲端匯入、OPDS 下載與
/// WiFi 傳書，只有這一個來源，不得各處自行傳入。
@immutable
class SourceDependencies {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;
  final OneDriveOAuthClient oneDriveOAuthClient;
  final CloudStorageClient googleDriveStorageClient;
  final CloudStorageClient oneDriveStorageClient;
  final RemoteServerRepository remoteServerRepository;

  /// OPDS client 有內部可變的 session 狀態（走訪過的 feed），每次使用要新建，所以是工廠函式。
  final OpdsClient Function() createOpdsClient;
  final RemoteThumbnailCache thumbnailCache;
  final ComputeRemoteFingerprint computeFingerprint;
  final Future<bool> Function() isMobileDataConnection;
  final CheckNetworkAvailability checkNetworkAvailability;
  final DownloadQueueController downloadQueueController;

  const SourceDependencies({
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
    required this.oneDriveOAuthClient,
    required this.googleDriveStorageClient,
    required this.oneDriveStorageClient,
    required this.remoteServerRepository,
    required this.createOpdsClient,
    required this.thumbnailCache,
    required this.computeFingerprint,
    required this.isMobileDataConnection,
    required this.checkNetworkAvailability,
    required this.downloadQueueController,
  });
}
