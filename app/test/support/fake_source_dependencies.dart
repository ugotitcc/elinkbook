import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';
import 'package:elinkbook/screens/source_dependencies.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import 'fake_cloud_account_repository.dart';
import 'fake_cloud_storage_client.dart';
import 'fake_fingerprint_computer.dart';
import 'fake_opds_client.dart';
import 'fake_remote_server_repository.dart';
import 'fake_remote_thumbnail_cache.dart';

/// 預設全 fake 的來源依賴組（ADR 0037）。只覆寫情境需要的欄位；每次呼叫都建新實例。
/// OAuth client 預設與 [cloudAccountRepository] 共用同一個帳號 repository
/// （`GoogleDriveOAuthClient`／`OneDriveOAuthClient` 建構時不做 I/O）。
SourceDependencies fakeSourceDependencies({
  CloudAccountRepository? cloudAccountRepository,
  GoogleDriveOAuthClient? googleDriveOAuthClient,
  OneDriveOAuthClient? oneDriveOAuthClient,
  CloudStorageClient? googleDriveStorageClient,
  CloudStorageClient? oneDriveStorageClient,
  RemoteServerRepository? remoteServerRepository,
  OpdsClient Function()? createOpdsClient,
  RemoteThumbnailCache? thumbnailCache,
  ComputeRemoteFingerprint? computeFingerprint,
  Future<bool> Function()? isMobileDataConnection,
  CheckNetworkAvailability? checkNetworkAvailability,
  DownloadQueueController? downloadQueueController,
}) {
  final account = cloudAccountRepository ?? FakeCloudAccountRepository();
  return SourceDependencies(
    cloudAccountRepository: account,
    googleDriveOAuthClient:
        googleDriveOAuthClient ?? GoogleDriveOAuthClient(accountRepository: account),
    oneDriveOAuthClient:
        oneDriveOAuthClient ?? OneDriveOAuthClient(accountRepository: account),
    googleDriveStorageClient: googleDriveStorageClient ?? FakeCloudStorageClient(),
    oneDriveStorageClient: oneDriveStorageClient ?? FakeCloudStorageClient(),
    remoteServerRepository: remoteServerRepository ?? FakeRemoteServerRepository(),
    createOpdsClient: createOpdsClient ?? () => FakeOpdsClient(),
    thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
    computeFingerprint: computeFingerprint ?? FakeFingerprintComputer().call,
    isMobileDataConnection: isMobileDataConnection ?? () async => false,
    checkNetworkAvailability: checkNetworkAvailability ??
        () async =>
            const NetworkAvailability(kind: NetworkAvailabilityKind.unavailable),
    downloadQueueController: downloadQueueController ??
        DownloadQueueController(onDuplicateConfirm: (_) async => false),
  );
}
