import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import 'cloud_download_queue_dialog.dart';

/// 【Epic 29 Issue 6，spec.md「Further Notes」建議值】單檔案大小門檻——
/// 目前為行動數據連線且勾選的檔案中有任何一個超過此值時，下載前顯示流量
/// 警示（見本檔案 `_startDownload()`／`_confirmMobileDataDownload()`）。
const _mobileDataWarningThresholdBytes = 20 * 1024 * 1024;

/// 雲端匯入瀏覽畫面（epic-29-cloud-import Issue 3 建置、Issue 4 泛化為
/// Google Drive／OneDrive 共用，原名 `GoogleDriveBrowserScreen`——沿用
/// Issue 2 把 `_buildGoogleDriveTile()` 泛化為 `_buildProviderTile()` 的
/// 既有先例，用一個寫死 provider 名稱的類別瀏覽另一個 provider 是誤導性
/// 命名，故重新命名）：逐層資料夾導覽（不做搜尋）、封面縮圖（含載入佔位符
/// 與記憶體快取）、單選/多選勾選檔案、可選分類，確認匯入後交給
/// [CloudDownloadQueueDialog] 序列下載＋匯入。畫面本身只依賴
/// [CloudStorageClient] 介面，注入 `GoogleDriveStorageClient` 或
/// `OneDriveStorageClient` 皆可直接沿用，不需要重新設計 UI（比照
/// `RemoteCatalogScreen` 對 `OpdsClient` 的既有設計原則）。刻意不含重複
/// 匯入偵測（Issue 5 的範圍）。**內部 `Key('google_drive_browser_...')`
/// 系列 widget key 字串刻意維持原樣未重新命名**——單純內部測試選擇器、
/// 非公開 API，重新命名對正確性無益處，只會在 Issue 3 既有測試套件產生
/// 大量無關 diff。
class CloudBrowserScreen extends StatefulWidget {
  final CloudStorageClient client;
  final LibraryRepository libraryRepository;
  final BookImportService importService;

  /// 【審查修正 review-plan-issue-4.md Critical #1】原本 Issue 3 版本
  /// 在 `_startDownload()` 內把 `BookSource.googleDrive` 寫死，泛化成
  /// `CloudBrowserScreen` 後若不新增這個欄位，OneDrive 匯入的書籍會被
  /// 誤記為 `BookSource.googleDrive`，破壞資料正確性且讓 Issue 5 未來的
  /// `findByCloudFileId(BookSource.oneDrive, ...)` 重複偵測永遠查無結果。
  /// 呼叫端必須明確傳入對應的 provider。
  final BookSource source;

  /// 【Epic 29 Issue 5】貫穿轉發給 [CloudDownloadQueueDialog] 做 Layer 2
  /// 下載後指紋比對；本畫面自己的 Layer 1（選檔前置）只需要
  /// [libraryRepository]，不需要指紋計算，故不在這裡使用。
  final ComputeRemoteFingerprint computeFingerprint;

  /// 【Epic 29 Issue 6】偵測目前是否為行動數據連線，與
  /// `library_screen.dart._handleRedownload()` 共用同一個 provider 無關的
  /// callback 型別（定義於 `main.dart._isMobileDataConnection`，底層為
  /// `connectivity_plus` 的 `Connectivity().checkConnectivity()`）。`null`
  /// 時視同「無法判斷連線類型」，不顯示警示（比照 `library_screen.dart`
  /// 既有 `?? Future.value(false)` 退回慣例）。
  final Future<bool> Function()? isMobileDataConnection;

  /// `null` 代表瀏覽雲端硬碟根目錄；非 `null` 時瀏覽指定資料夾（點擊
  /// [CloudFileEntry.isFolder] 為 `true` 的項目下鑽時使用）。
  final String? folderId;

  /// AppBar 標題，`null` 時使用預設「Google Drive」（呼叫端瀏覽 OneDrive
  /// 時應明確傳入 `title: 'OneDrive'` 覆蓋這個預設值）。
  final String? title;

  const CloudBrowserScreen({
    super.key,
    required this.client,
    required this.libraryRepository,
    required this.importService,
    required this.source,
    required this.computeFingerprint,
    this.isMobileDataConnection,
    this.folderId,
    this.title,
  });

  @override
  State<CloudBrowserScreen> createState() => _CloudBrowserScreenState();
}

class _CloudBrowserScreenState extends State<CloudBrowserScreen> {
  bool _loading = true;
  bool _needsReauth = false;
  String? _errorText;
  List<CloudFileEntry> _entries = const [];
  bool _truncated = false;
  final Set<String> _selectedIds = {};
  List<BookGroup> _groups = const [];
  String _selectedGroupName = BookGroup.uncategorized;
  final Map<String, Uint8List> _thumbnailCache = {};

  /// 【審查修正 review-issue-3.md Important #2】記憶化「進行中」的縮圖
  /// Future 本身（不只是解析完成後的位元組）——`_buildThumbnail()` 是在
  /// `build()` 過程中被 `GridView.builder` 呼叫的一般方法，只要父層因
  /// 任何原因（最常見即 `_toggleSelection()` 點擊勾選）觸發 `setState()`
  /// 重建，尚未解析完成的縮圖若每次都呼叫 `widget.client.fetchThumbnail()`
  /// 建立新 Future，會被 `FutureBuilder` 視為全新的非同步狀態、重新發起
  /// 一次帶授權標頭的網路請求並閃回載入圖示。比照 `RemoteThumbnailCache`
  /// 底層 LRU 解決同一個陷阱的既有先例（`RemoteCatalogScreen._buildThumbnail()`
  /// 已有明確記載），這裡改把 in-flight 的 Future 存起來，同一個
  /// [thumbnailUrl] 在完成前只會真正發起一次請求。
  final Map<String, Future<Uint8List>> _pendingThumbnailFetches = {};

  /// 【Epic 29 Issue 5，比照 `remote_catalog_screen.dart` 的
  /// `_pendingDuplicateChecks` 既有先例】快速連續點擊同一個尚未勾選的
  /// 檔案時，避免兩次 `findByCloudFileId()` 查詢並行、各自可能彈出一次
  /// 重複提示——查詢期間先記錄該 entry id，重入的點擊直接忽略。
  final Set<String> _pendingDuplicateChecks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
      _needsReauth = false;
    });
    try {
      final listing = await widget.client.listFolder(folderId: widget.folderId);
      final groups = await widget.libraryRepository.listGroups();
      if (!mounted) return;
      setState(() {
        _entries = listing.entries;
        _truncated = listing.truncated;
        _groups = groups;
        _loading = false;
      });
    } on CloudAuthRequiredException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsReauth = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '載入失敗，請檢查網路連線';
      });
    }
  }

  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CloudBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        source: widget.source,
        computeFingerprint: widget.computeFingerprint,
        isMobileDataConnection: widget.isMobileDataConnection,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }

  Future<void> _toggleSelection(CloudFileEntry entry) async {
    if (_selectedIds.contains(entry.id)) {
      setState(() => _selectedIds.remove(entry.id));
      return;
    }
    if (_pendingDuplicateChecks.contains(entry.id)) return;
    _pendingDuplicateChecks.add(entry.id);
    var hasDuplicate = false;
    try {
      hasDuplicate =
          await widget.libraryRepository.findByCloudFileId(widget.source, entry.id) != null;
    } catch (_) {
      hasDuplicate = false;
    } finally {
      _pendingDuplicateChecks.remove(entry.id);
    }
    if (hasDuplicate) {
      if (!mounted) return;
      final proceed = await showCloudDuplicateConfirmDialog(
        context,
        '「${entry.name}」之前匯入過了，仍要建立新的一份嗎？',
      );
      if (!proceed) return;
    }
    if (!mounted) return;
    setState(() => _selectedIds.add(entry.id));
  }

  Future<void> _startDownload() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    final hasLargeFile = selected.any(
      (e) => e.sizeBytes != null && e.sizeBytes! > _mobileDataWarningThresholdBytes,
    );
    if (hasLargeFile) {
      final isMobileData =
          await (widget.isMobileDataConnection?.call() ?? Future.value(false));
      if (!mounted) return;
      if (isMobileData) {
        final proceed = await _confirmMobileDataDownload();
        if (!mounted) return;
        if (proceed != true) return;
      }
    }

    final folderName =
        _selectedGroupName == BookGroup.uncategorized ? null : _selectedGroupName;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        source: widget.source,
        folderName: folderName,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedIds.clear());
  }

  /// 【Epic 29 Issue 6】整批判斷一次的行動數據流量警示彈窗（見本計劃「批次
  /// 判斷方式決策」）——只在 `_startDownload()` 偵測到「行動數據連線＋勾選
  /// 檔案內有超過門檻的項目」時才會被呼叫一次，不逐檔案詢問。UI 慣例比照
  /// `library_screen.dart._confirmRedownload()`。
  Future<bool?> _confirmMobileDataDownload() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('cloud_mobile_data_dialog'),
        title: const Text('行動數據下載提醒'),
        content: const Text(
          '目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，'
          '確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            key: const Key('cloud_mobile_data_dialog_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('cloud_mobile_data_dialog_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('繼續下載'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Google Drive'),
        actions: [
          IconButton(
            key: const Key('google_drive_browser_download_button'),
            icon: const Icon(Icons.download),
            tooltip: '下載已選取',
            onPressed: _selectedIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('google_drive_browser_loading_indicator'),
              ),
            )
          : _needsReauth
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '登入已過期，請至「設定」重新連結 ${widget.title ?? '雲端'} 帳號',
                      key: const Key('google_drive_browser_reauth_text'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _errorText != null
                  ? Center(
                      child: Text(
                        _errorText!,
                        key: const Key('google_drive_browser_error_text'),
                      ),
                    )
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('匯入分類：'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                key: const Key('google_drive_browser_group_dropdown'),
                value: _selectedGroupName,
                items: [
                  const DropdownMenuItem(
                    value: BookGroup.uncategorized,
                    child: Text(BookGroup.uncategorized),
                  ),
                  for (final group
                      in _groups.where((g) => g.name != BookGroup.uncategorized))
                    DropdownMenuItem(value: group.name, child: Text(group.name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedGroupName = value);
                },
              ),
            ],
          ),
        ),
        if (_truncated)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '這個資料夾檔案較多，僅顯示前 1000 筆',
              key: Key('google_drive_browser_truncated_text'),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.6,
            ),
            itemCount: _entries.length,
            itemBuilder: (context, index) => _buildEntryTile(_entries[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(CloudFileEntry entry) {
    final selected = _selectedIds.contains(entry.id);
    return InkWell(
      key: Key('google_drive_browser_entry_${entry.id}'),
      onTap:
          entry.isFolder ? () => _openSubfolder(entry) : () => _toggleSelection(entry),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: entry.isFolder
                      ? const Icon(Icons.folder, size: 48)
                      : _buildThumbnail(entry),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(
                      Icons.check_circle,
                      key: Key('google_drive_browser_checkbox_checked_${entry.id}'),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(CloudFileEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return Center(
        child: Icon(
          Icons.book,
          key: Key('google_drive_browser_thumbnail_placeholder_${entry.id}'),
        ),
      );
    }
    final cached = _thumbnailCache[thumbnailUrl];
    if (cached != null) {
      return Image.memory(
        cached,
        key: Key('google_drive_browser_thumbnail_${entry.id}'),
        fit: BoxFit.cover,
      );
    }
    final pending = _pendingThumbnailFetches[thumbnailUrl] ??=
        widget.client.fetchThumbnail(thumbnailUrl).then((bytes) {
      _thumbnailCache[thumbnailUrl] = bytes;
      _pendingThumbnailFetches.remove(thumbnailUrl);
      return bytes;
    });
    return FutureBuilder<Uint8List>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('google_drive_browser_thumbnail_${entry.id}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            key: Key('google_drive_browser_thumbnail_loading_${entry.id}'),
            child: const Icon(Icons.book),
          );
        }
        return Center(
          key: Key('google_drive_browser_thumbnail_error_${entry.id}'),
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
}
