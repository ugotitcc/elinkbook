import 'package:flutter/material.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import '../remote/remote_catalog_dependencies.dart';
import '../wifi_transfer/wifi_transfer_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'library_screen_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'support/book_import_picker_helper.dart';
import 'widgets/download_queue_panel.dart';
import '../l10n/app_localizations.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'wifi_transfer_screen.dart';

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

  /// 視覺還原（Visual Accuracy Mode）：Google Drive／OneDrive／OPDS 遠端
  /// 書庫下載一律改為加入這個常駐佇列（見 `DownloadQueuePanel`），取代
  /// 原本 `CloudBrowserScreen`／`RemoteCatalogScreen` 各自用
  /// `showDialog()` 跳出的模態下載對話框——三種來源共用同一份清單。`null`
  /// 時（例如尚未組裝完整匯入相依）本畫面不渲染下載佇列區塊，
  /// `_openXxxBrowser`／`_openRemoteLibrary` 也不會把控制器往下傳
  /// ——`computeFingerprint` 為 `null` 時本來就已經停用這三個入口本身
  /// （見下方 `googleDriveEnabled`/`oneDriveEnabled`/`remoteEnabled`），
  /// 這裡維持同一個「有齊全相依才啟用」的既有慣例。
  final DownloadQueueController? downloadQueueController;

  /// WiFi 傳書入口依賴（epic-44-wifi-book-transfer Issue 1，spec.md
  /// 「依賴注入收斂」）：任一必要欄位為 `null` 時「本機」分區不顯示此
  /// 入口。
  final WifiTransferDependencies? wifiTransferDependencies;

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
    this.downloadQueueController,
    this.wifiTransferDependencies,
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
          downloadQueueController: downloadQueueController!,
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
          downloadQueueController: downloadQueueController!,
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
          downloadQueueController: downloadQueueController!,
        ),
      ),
    );
  }

  void _openWifiTransfer(BuildContext context) {
    final deps = wifiTransferDependencies!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WifiTransferScreen(
          libraryRepository: deps.libraryRepository!,
          importService: deps.importService!,
          computeFingerprint: deps.computeFingerprint!,
          checkNetworkAvailability: deps.checkNetworkAvailability!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final googleDriveClient = cloudAccountDependencies.googleDriveStorageClient;
    final oneDriveClient = cloudAccountDependencies.oneDriveStorageClient;
    final googleDriveEnabled =
        googleDriveClient != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final oneDriveEnabled =
        oneDriveClient != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final remoteEnabled =
        remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final wifiTransferEnabled =
        wifiTransferDependencies?.libraryRepository != null &&
        wifiTransferDependencies?.importService != null &&
        wifiTransferDependencies?.computeFingerprint != null &&
        wifiTransferDependencies?.checkNetworkAvailability != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcesHomeTitle),
        actions: [
          IconButton(
            key: const Key('sources_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: l10n.sourcesHomeLibraryTooltip,
            onPressed: onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('sources_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: l10n.sourcesHomeSettingsTooltip,
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
              title: Text(l10n.sourcesHomePickFilesTitle),
              onTap: () => _handlePickFiles(context),
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_folder_button'),
              leading: const Icon(Icons.folder),
              title: Text(l10n.sourcesHomePickFolderTitle),
              onTap: () => _handlePickFolder(context),
            ),
          ),
          if (wifiTransferEnabled)
            EBFieldCard(
              padding: EdgeInsets.zero,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                key: const Key('sources_wifi_transfer_tile'),
                leading: const Icon(Icons.wifi),
                title: Text(l10n.sourcesHomeWifiTransferTile),
                onTap: () => _openWifiTransfer(context),
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
                  : Text(l10n.sourcesHomeCloudNotLinkedSubtitle),
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
              subtitle: oneDriveEnabled ? null : Text(l10n.sourcesHomeCloudNotLinkedSubtitle),
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
              title: Text(l10n.sourcesHomeRemoteLibraryTitle),
              subtitle: remoteEnabled ? null : Text(l10n.sourcesHomeRemoteLibraryNotConfiguredSubtitle),
              enabled: remoteEnabled,
              onTap: remoteEnabled ? () => _openRemoteLibrary(context) : null,
            ),
          ),
          if (downloadQueueController != null)
            DownloadQueuePanel(controller: downloadQueueController!),
        ],
      ),
    );
  }
}
