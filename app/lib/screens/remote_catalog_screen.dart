import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import '../remote/opds_client.dart';
import '../remote/opds_types.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';
import 'format_selection_dialog.dart';

/// OPDS 目錄瀏覽畫面（epic-30-calibre-remote-library Issue 2，
/// spec.md「UI 落地位置」）：依 [OpdsFeed.navigationLinks] 分類下鑽（點擊
/// 後 push 新的本畫面實例）、依 [OpdsFeed.nextUrl] 提供「載入更多」、
/// 封面縮圖網格（帶 Basic Auth header）、多選勾選批次下載。
///
/// [createOpdsClient] 在 [initState] 只呼叫一次，**本畫面實例**的生命
/// 週期內（含這一頁 Feed 的「載入更多」分頁與下載佇列）共用同一個
/// [OpdsClient] 實例——比照 `opds_http_client.dart` 類別文件的生命週期
/// 警告，分頁循環防護的 `_visitedFeedUrls` 才會正確對應「這個 Feed 的
/// 分頁路徑」。**〔`review-issue-2.md` Minor #2 核實修正〕** 分類下鑽
/// （[_openSubsection] push 新的本畫面實例）會呼叫**新的一次**
/// `createOpdsClient()`，取得另一個全新實例，不是延續上一層的實例——
/// 這是刻意且安全的行為：不同分類各自的分頁路徑本來就彼此獨立，沒有
/// 必要、也不應該共用同一份 `_visitedFeedUrls` 循環防護狀態。
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
  });

  @override
  State<RemoteCatalogScreen> createState() => _RemoteCatalogScreenState();
}

class _RemoteCatalogScreenState extends State<RemoteCatalogScreen> {
  late final OpdsClient _client;
  bool _loading = true;
  String? _errorText;
  final List<OpdsNavigationLink> _navigationLinks = [];
  final List<OpdsEntry> _entries = [];
  String? _nextUrl;
  bool _loadingMore = false;
  final Set<String> _selectedRemoteBookIds = {};
  String? _password;

  @override
  void initState() {
    super.initState();
    _client = widget.createOpdsClient();
    _load();
  }

  bool _isSelectable(OpdsEntry entry) => entry.acquisitions.any((a) => a.format != null);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    _password = await widget.repository.loadPassword(widget.server.id);
    try {
      final feed = await _client.fetchFeed(
        widget.server,
        password: _password,
        feedUrl: widget.feedUrl,
      );
      if (!mounted) return;
      setState(() {
        _navigationLinks
          ..clear()
          ..addAll(feed.navigationLinks);
        _entries
          ..clear()
          ..addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '載入失敗，請檢查網路連線或站點設定';
      });
    }
  }

  Future<void> _loadMore() async {
    final nextUrl = _nextUrl;
    if (nextUrl == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final feed = await _client.fetchFeed(widget.server, password: _password, feedUrl: nextUrl);
      if (!mounted) return;
      setState(() {
        _navigationLinks.addAll(feed.navigationLinks);
        _entries.addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _loadingMore = false;
      });
    } catch (_) {
      // 失敗時保留既有 _nextUrl，讓使用者可以再按一次「載入更多」重試，
      // 不彈額外錯誤訊息干擾——這不是整頁載入失敗，只是分頁的一次嘗試。
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
      ),
    ));
  }

  Future<void> _toggleSelection(OpdsEntry entry) async {
    if (!_isSelectable(entry)) return;
    if (_selectedRemoteBookIds.contains(entry.remoteBookId)) {
      setState(() => _selectedRemoteBookIds.remove(entry.remoteBookId));
      return;
    }
    final existing =
        await widget.libraryRepository.findByRemoteBookId(widget.server.id, entry.remoteBookId);
    if (existing != null) {
      if (!mounted) return;
      final proceed = await _showDuplicateConfirmDialog(
        context,
        '「${entry.title}」之前匯入過了，仍要建立新的一份嗎？',
      );
      if (!proceed) return;
    }
    if (!mounted) return;
    setState(() => _selectedRemoteBookIds.add(entry.remoteBookId));
  }

  Future<void> _startDownload() async {
    final selectedEntries =
        _entries.where((e) => _selectedRemoteBookIds.contains(e.remoteBookId)).toList();
    if (selectedEntries.isEmpty) return;

    final queue = <_DownloadQueueItem>[];
    for (final entry in selectedEntries) {
      final supported = entry.acquisitions.where((a) => a.format != null).toList();
      OpdsAcquisition? chosen;
      if (supported.length == 1) {
        chosen = supported.single;
      } else if (supported.length > 1) {
        if (!mounted) return;
        chosen = await FormatSelectionDialog.show(context, entry);
      }
      if (chosen == null) continue;
      queue.add(_DownloadQueueItem(entry: entry, acquisition: chosen));
    }
    if (queue.isEmpty) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadQueueDialog(
        queue: queue,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedRemoteBookIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.server.name),
        actions: [
          IconButton(
            key: const Key('remote_catalog_download_button'),
            icon: const Icon(Icons.download),
            tooltip: '下載已選取',
            onPressed: _selectedRemoteBookIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(key: Key('remote_catalog_loading_indicator')),
            )
          : _errorText != null
              ? Center(
                  child: Text(_errorText!, key: const Key('remote_catalog_error_text')),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return ListView(
      children: [
        for (final link in _navigationLinks)
          ListTile(
            key: Key('remote_catalog_nav_${link.href}'),
            leading: const Icon(Icons.folder),
            title: Text(link.title),
            onTap: () => _openSubsection(link),
          ),
        if (_navigationLinks.isNotEmpty && _entries.isNotEmpty) const Divider(),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.6,
          ),
          itemCount: _entries.length,
          itemBuilder: (context, index) => _buildEntryTile(_entries[index]),
        ),
        if (_nextUrl != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                key: const Key('remote_catalog_load_more_button'),
                onPressed: _loadingMore ? null : _loadMore,
                child: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('載入更多'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEntryTile(OpdsEntry entry) {
    final selectable = _isSelectable(entry);
    final selected = _selectedRemoteBookIds.contains(entry.remoteBookId);
    return InkWell(
      key: Key('remote_catalog_entry_${entry.remoteBookId}'),
      onTap: selectable ? () => _toggleSelection(entry) : null,
      child: Opacity(
        opacity: selectable ? 1 : 0.4,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildThumbnail(entry)),
                  if (selected)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        Icons.check_circle,
                        key: Key('remote_catalog_checkbox_checked_${entry.remoteBookId}'),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(OpdsEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return Center(
        child: Icon(
          Icons.book,
          key: Key('remote_catalog_thumbnail_placeholder_${entry.remoteBookId}'),
        ),
      );
    }
    return Image.network(
      thumbnailUrl,
      key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
      headers: buildOpdsAuthHeaders(widget.server, _password),
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
          child: const Icon(Icons.book),
        );
      },
      errorBuilder: (context, error, stack) => Center(
        key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
        child: const Icon(Icons.broken_image),
      ),
    );
  }
}

class _DownloadQueueItem {
  final OpdsEntry entry;
  final OpdsAcquisition acquisition;

  _DownloadQueueItem({required this.entry, required this.acquisition});
}

enum _DownloadItemStatus { pending, downloading, done, failed, cancelled }

/// 序列下載佇列對話框（epic-30-calibre-remote-library Issue 2，
/// spec.md「批次下載為序列執行，非平行」）：一本下完才下一本，逐項顯示
/// 等待中/下載中/完成/失敗/已取消狀態；下載失敗可針對單一檔案手動重試
/// （不自動重試）；全部處理完（無論成功/失敗）後，把所有成功下載的檔案
/// 一次呼叫 [BookImportService.importFiles] 匯入圖書庫；之後對個別失敗
/// 項目按重試、成功時額外呼叫一次 `importFiles()` 只匯入那一筆。
class _DownloadQueueDialog extends StatefulWidget {
  final List<_DownloadQueueItem> queue;
  final OpdsClient client;
  final RemoteServerProfile server;
  final String? password;
  final BookImportService importService;

  // 私有 widget、唯一呼叫端（_startDownload）不需要指定 key，故不接受
  // `key` 參數（比照 `flutter analyze` 對未使用的可選參數的既有規範）。
  const _DownloadQueueDialog({
    required this.queue,
    required this.client,
    required this.server,
    required this.password,
    required this.importService,
  });

  @override
  State<_DownloadQueueDialog> createState() => _DownloadQueueDialogState();
}

class _DownloadQueueDialogState extends State<_DownloadQueueDialog> {
  late List<_DownloadItemStatus> _statuses;
  late List<String?> _permanentPaths;
  late List<OpdsDownloadCancellationToken?> _tokens;
  bool _allSettled = false;

  @override
  void initState() {
    super.initState();
    _statuses = List.filled(widget.queue.length, _DownloadItemStatus.pending);
    _permanentPaths = List.filled(widget.queue.length, null);
    _tokens = List.filled(widget.queue.length, null);
    _runQueue();
  }

  Future<void> _runQueue() async {
    for (var i = 0; i < widget.queue.length; i++) {
      await _downloadOne(i);
    }
    await _importSuccessful();
    if (!mounted) return;
    setState(() => _allSettled = true);
  }

  String _extensionFor(BookFileFormat format) {
    switch (format) {
      case BookFileFormat.epub:
        return 'epub';
      case BookFileFormat.pdf:
        return 'pdf';
      case BookFileFormat.txt:
        return 'txt';
      case BookFileFormat.azw3:
        return 'azw3';
      case BookFileFormat.cbz:
        return 'cbz';
      case BookFileFormat.md:
        return 'md';
    }
  }

  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = _DownloadItemStatus.downloading);
    final item = widget.queue[index];
    final token = OpdsDownloadCancellationToken();
    _tokens[index] = token;
    // 〔審查 review-plan-issue-2.md Finding 3 採納〕宣告在 try 外，讓
    // catch 區塊也能存取，用於下方「copy 到永久目錄中途失敗」時的暫存檔
    // 清理。
    String? tempPath;
    try {
      final tempDir = await getTemporaryDirectory();
      final downloadDir = Directory(p.join(tempDir.path, 'remote_download_temp'));
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final fileName = '${const Uuid().v4()}.${_extensionFor(item.acquisition.format!)}';
      tempPath = p.join(downloadDir.path, fileName);

      await widget.client.downloadBook(
        widget.server,
        item.acquisition,
        tempPath,
        password: widget.password,
        cancellationToken: token,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final permanentDir = Directory(p.join(docsDir.path, 'remote_books'));
      if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
      final permanentPath = p.join(permanentDir.path, fileName);
      final tempFile = File(tempPath);
      await tempFile.copy(permanentPath);
      await tempFile.delete();

      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = _DownloadItemStatus.done;
      });
    } catch (_) {
      // 〔審查 review-plan-issue-2.md Finding 3 採納〕downloadBook() 本身
      // 失敗/取消時已經自行清過暫存檔（見 OpdsHttpClient 文件），但
      // copy() 到永久目錄這一步若中途失敗（例如磁碟空間不足），暫存檔
      // 仍會殘留在 remote_download_temp/ 底下——防禦性再清一次，確保
      // 任何例外路徑都不留孤兒檔案。
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      setState(() {
        _statuses[index] =
            token.isCancelled ? _DownloadItemStatus.cancelled : _DownloadItemStatus.failed;
      });
    }
  }

  Future<void> _importSuccessful() async {
    final paths = <String>[];
    final remoteBookIds = <String, String>{};
    final remoteDownloadUrls = <String, String>{};
    for (var i = 0; i < widget.queue.length; i++) {
      final path = _permanentPaths[i];
      if (path == null) continue;
      paths.add(path);
      remoteBookIds[path] = widget.queue[i].entry.remoteBookId;
      remoteDownloadUrls[path] = widget.queue[i].acquisition.href;
    }
    if (paths.isEmpty) return;
    await widget.importService.importFiles(
      paths,
      source: BookSource.calibreOpds,
      remoteServerId: widget.server.id,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
    );
  }

  Future<void> _retry(int index) async {
    await _downloadOne(index);
    if (_statuses[index] != _DownloadItemStatus.done) return;
    final path = _permanentPaths[index]!;
    final item = widget.queue[index];
    await widget.importService.importFiles(
      [path],
      source: BookSource.calibreOpds,
      remoteServerId: widget.server.id,
      remoteBookIds: {path: item.entry.remoteBookId},
      remoteDownloadUrls: {path: item.acquisition.href},
    );
  }

  void _cancel(int index) {
    _tokens[index]?.cancel();
  }

  String _statusLabel(_DownloadItemStatus status) {
    switch (status) {
      case _DownloadItemStatus.pending:
        return '等待中';
      case _DownloadItemStatus.downloading:
        return '下載中';
      case _DownloadItemStatus.done:
        return '完成';
      case _DownloadItemStatus.failed:
        return '失敗';
      case _DownloadItemStatus.cancelled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('download_queue_dialog'),
      title: const Text('下載進度'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.queue.length,
          itemBuilder: (context, index) {
            final item = widget.queue[index];
            final status = _statuses[index];
            final canRetry =
                status == _DownloadItemStatus.failed || status == _DownloadItemStatus.cancelled;
            return ListTile(
              key: Key('download_queue_item_${item.entry.remoteBookId}'),
              title: Text(item.entry.title),
              subtitle: Text(_statusLabel(status)),
              trailing: status == _DownloadItemStatus.downloading
                  ? IconButton(
                      key: Key('download_queue_cancel_${item.entry.remoteBookId}'),
                      icon: const Icon(Icons.close),
                      tooltip: '取消',
                      onPressed: () => _cancel(index),
                    )
                  : canRetry
                      ? IconButton(
                          key: Key('download_queue_retry_${item.entry.remoteBookId}'),
                          icon: const Icon(Icons.refresh),
                          tooltip: '重試',
                          onPressed: () => _retry(index),
                        )
                      : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const Key('download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// 重複匯入確認彈窗（epic-30-calibre-remote-library Issue 3，spec.md
/// 「重複匯入偵測」）：選檔前置（Layer 1）與下載後指紋比對（Layer 2）
/// 兩層檢查共用同一個確認 UI，只有提示文字不同——精確比對命中不代表
/// 強制阻擋，使用者可選擇仍要建立新副本。
Future<bool> _showDuplicateConfirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('remote_catalog_duplicate_dialog'),
      title: const Text('重複的書籍'),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍要建立'),
        ),
      ],
    ),
  );
  return result ?? false;
}
