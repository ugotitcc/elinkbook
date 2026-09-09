import 'package:flutter/material.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import '../remote/remote_catalog_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'library_screen_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'support/book_import_picker_helper.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';

/// 「來源」目的地聚合頁（epic-36-adaptive-shelf-navigation spec.md
/// §功能①）：只聚合既有本機/雲端/OPDS 入口，不新增任何底層匯入/雲端
/// 邏輯——AppBar 拿掉「＋」匯入選單後的功能真空由本畫面承接。
class SourcesHomeScreen extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final LibraryCloudAccountDependencies cloudAccountDependencies;
  final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
  final ComputeRemoteFingerprint? computeFingerprint;
  final Future<bool> Function()? isMobileDataConnection;
  final bool isEinkMode;
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSettings;

  const SourcesHomeScreen({
    super.key,
    required this.repository,
    required this.importService,
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.isEinkMode = false,
    this.onNavigateToLibrary,
    this.onNavigateToSettings,
  });

  Future<void> _handlePickFiles(BuildContext context) async {
    final result = await pickAndImportFiles(importService);
    if (result == null) return;
    if (!context.mounted) return;
    showImportResultSnackBar(context, result);
  }

  Future<void> _handlePickFolder(BuildContext context) async {
    final result = await pickAndImportFolder(
      importService,
      // 資料夾選擇器等待期間使用者可能已離開此畫面（審查報告 M-1）：
      // `context.mounted` 需在等待結束、真正要彈出確認對話框前才檢查，
      // 而非在呼叫 pickAndImportFolder() 之前檢查一次就假設之後都有效。
      confirmAutoGroup: () => context.mounted
          ? confirmAutoGroupByFolderName(context)
          : Future.value(null),
    );
    if (result == null) return;
    if (!context.mounted) return;
    showImportResultSnackBar(context, result);
  }

  void _openGoogleDriveBrowser(
    BuildContext context,
    CloudStorageClient client,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: client,
          libraryRepository: repository,
          importService: importService,
          source: BookSource.googleDrive,
          computeFingerprint: computeFingerprint!,
          isMobileDataConnection: isMobileDataConnection,
        ),
      ),
    );
  }

  void _openOneDriveBrowser(BuildContext context, CloudStorageClient client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: client,
          libraryRepository: repository,
          importService: importService,
          source: BookSource.oneDrive,
          computeFingerprint: computeFingerprint!,
          isMobileDataConnection: isMobileDataConnection,
          title: 'OneDrive',
        ),
      ),
    );
  }

  void _openRemoteLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RemoteServerListScreen(
          repository: remoteLibraryDependencies.remoteServerRepository!,
          libraryRepository: repository,
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: computeFingerprint!,
            thumbnailCache: remoteLibraryDependencies.thumbnailCache!,
            createOpdsClient: remoteLibraryDependencies.createOpdsClient!,
          ),
          importService: importService,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final googleDriveClient = cloudAccountDependencies.googleDriveStorageClient;
    final oneDriveClient = cloudAccountDependencies.oneDriveStorageClient;
    final googleDriveEnabled =
        googleDriveClient != null && computeFingerprint != null;
    final oneDriveEnabled =
        oneDriveClient != null && computeFingerprint != null;
    final remoteEnabled =
        remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('來源'),
        actions: [
          IconButton(
            key: const Key('sources_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: '書架',
            onPressed: onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('sources_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: onNavigateToSettings,
          ),
        ],
      ),
      body: ListView(
        children: [
          const EBSectionHeader(title: '本機'),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_files_button'),
              leading: const Icon(Icons.description),
              title: const Text('選擇檔案（可多選）'),
              onTap: () => _handlePickFiles(context),
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_folder_button'),
              leading: const Icon(Icons.folder),
              title: const Text('選擇資料夾'),
              onTap: () => _handlePickFolder(context),
            ),
          ),
          const EBSectionHeader(title: '已連結服務'),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_google_drive_tile'),
              leading: const Icon(Icons.cloud),
              title: const Text('Google Drive'),
              subtitle: googleDriveEnabled
                  ? null
                  : const Text('尚未連結，請至設定畫面連結帳戶'),
              enabled: googleDriveEnabled,
              onTap: googleDriveEnabled
                  ? () => _openGoogleDriveBrowser(context, googleDriveClient)
                  : null,
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_onedrive_tile'),
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('OneDrive'),
              subtitle: oneDriveEnabled ? null : const Text('尚未連結，請至設定畫面連結帳戶'),
              enabled: oneDriveEnabled,
              onTap: oneDriveEnabled
                  ? () => _openOneDriveBrowser(context, oneDriveClient)
                  : null,
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_remote_library_tile'),
              leading: const Icon(Icons.dns),
              title: const Text('遠端書庫（OPDS）'),
              subtitle: remoteEnabled ? null : const Text('尚未設定遠端書庫伺服器'),
              enabled: remoteEnabled,
              onTap: remoteEnabled ? () => _openRemoteLibrary(context) : null,
            ),
          ),
        ],
      ),
    );
  }
}
