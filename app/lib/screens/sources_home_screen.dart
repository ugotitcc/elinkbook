import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/library_enums.dart';
import '../remote/remote_catalog_dependencies.dart';
import 'appearance_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'reader_feature_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'source_dependencies.dart';
import 'support/book_import_picker_helper.dart';
import 'widgets/download_queue_panel.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_section_header.dart';
import 'wifi_transfer_screen.dart';

/// 「來源」目的地聚合頁（epic-36-adaptive-shelf-navigation spec.md
/// §功能①）：只聚合既有本機/雲端/OPDS 入口，不新增任何底層匯入/雲端
/// 邏輯——AppBar 拿掉「＋」匯入選單後的功能真空由本畫面承接。
class SourcesHomeScreen extends StatelessWidget {
  /// 閱讀器功能依賴組（ADR 0037）：本機匯入與書庫存取取自這一組。
  final ReaderFeatureDependencies readerFeatures;

  /// 來源依賴組（ADR 0037）：雲端、遠端書庫、WiFi 傳書與下載佇列取自這一組，
  /// 全部 non-null——正式環境恆提供，各入口恆啟用。
  final SourceDependencies sources;

  /// 外觀快照（ADR 0037）：E-Ink 修飾子等由上層每次 build 現組往下傳。
  final AppearanceDependencies appearance;
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSettings;

  const SourcesHomeScreen({
    super.key,
    required this.readerFeatures,
    required this.sources,
    required this.appearance,
    this.onNavigateToLibrary,
    this.onNavigateToSettings,
  });

  Future<void> _handlePickFiles(BuildContext context) async {
    final result = await pickAndImportFiles(readerFeatures.bookImportService);
    if (result == null) return;
    if (!context.mounted) return;
    showImportResultSnackBar(context, result);
  }

  Future<void> _handlePickFolder(BuildContext context) async {
    final result = await pickAndImportFolder(
      readerFeatures.bookImportService,
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

  void _openGoogleDriveBrowser(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: sources.googleDriveStorageClient,
          libraryRepository: readerFeatures.libraryRepository,
          importService: readerFeatures.bookImportService,
          source: BookSource.googleDrive,
          computeFingerprint: sources.computeFingerprint,
          isMobileDataConnection: sources.isMobileDataConnection,
          downloadQueueController: sources.downloadQueueController,
        ),
      ),
    );
  }

  void _openOneDriveBrowser(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: sources.oneDriveStorageClient,
          libraryRepository: readerFeatures.libraryRepository,
          importService: readerFeatures.bookImportService,
          source: BookSource.oneDrive,
          computeFingerprint: sources.computeFingerprint,
          isMobileDataConnection: sources.isMobileDataConnection,
          title: 'OneDrive',
          downloadQueueController: sources.downloadQueueController,
        ),
      ),
    );
  }

  void _openRemoteLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RemoteServerListScreen(
          repository: sources.remoteServerRepository,
          libraryRepository: readerFeatures.libraryRepository,
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: sources.computeFingerprint,
            thumbnailCache: sources.thumbnailCache,
            createOpdsClient: sources.createOpdsClient,
          ),
          importService: readerFeatures.bookImportService,
          isEinkMode: appearance.isEinkMode,
          downloadQueueController: sources.downloadQueueController,
        ),
      ),
    );
  }

  void _openWifiTransfer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WifiTransferScreen(
          libraryRepository: readerFeatures.libraryRepository,
          importService: readerFeatures.bookImportService,
          computeFingerprint: sources.computeFingerprint,
          checkNetworkAvailability: sources.checkNetworkAvailability,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
          EBSectionHeader(title: l10n.sourcesHomeLocalSection),
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
          EBSectionHeader(title: l10n.sourcesHomeConnectedServicesSection),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_google_drive_tile'),
              leading: const Icon(Icons.cloud),
              title: const Text('Google Drive'),
              onTap: () => _openGoogleDriveBrowser(context),
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_onedrive_tile'),
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('OneDrive'),
              onTap: () => _openOneDriveBrowser(context),
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_remote_library_tile'),
              leading: const Icon(Icons.dns),
              title: Text(l10n.sourcesHomeRemoteLibraryTitle),
              onTap: () => _openRemoteLibrary(context),
            ),
          ),
          // 視覺還原（VISUAL_ANALYSIS.md）：常駐下載佇列——Google Drive／
          // OneDrive／OPDS 遠端書庫下載一律改為加入這個常駐佇列，取代原本
          // `CloudBrowserScreen`／`RemoteCatalogScreen` 各自用
          // `showDialog()` 跳出的模態下載對話框——三種來源共用同一份清單。
          DownloadQueuePanel(controller: sources.downloadQueueController),
        ],
      ),
    );
  }
}
