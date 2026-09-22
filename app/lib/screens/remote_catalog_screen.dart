import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../downloads/download_queue_controller.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../remote/remote_catalog_dependencies.dart';
import '../remote/opds_client.dart';
import '../remote/opds_types.dart';
import '../remote/remote_download_job.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';
import '../library/widgets/book_cover.dart';
import '../l10n/app_localizations.dart';
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

  /// 收斂原本 `computeFingerprint`／`thumbnailCache`／`createOpdsClient`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 6）。
  final RemoteCatalogDependencies dependencies;

  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  /// E-Ink 模式（epic-30-calibre-remote-library Issue 5，design.md
  /// 「E-Ink 與後續優化」）：`true` 時把連續捲動「載入更多」換成離散
  /// 「上一頁／下一頁」整頁換頁，避免高幀率捲動動畫造成的殘影。比照
  /// 既有 `LibraryScreen.isEinkMode` 的預設值與非空語意。
  final bool isEinkMode;

  /// 視覺還原（Visual Accuracy Mode）：確認下載後改為把每個檔案包成
  /// [RemoteDownloadJob] 加入這個常駐佇列（顯示於「來源」畫面），取代
  /// 原本本畫面自己 `showDialog()` 跳出模態下載對話框的做法，與
  /// `CloudBrowserScreen` 共用同一份佇列。
  final DownloadQueueController downloadQueueController;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.dependencies,
    required this.importService,
    required this.downloadQueueController,
    this.feedUrl,
    this.title,
    this.isEinkMode = false,
  });

  @override
  State<RemoteCatalogScreen> createState() => _RemoteCatalogScreenState();
}

class _RemoteCatalogScreenState extends State<RemoteCatalogScreen> {
  late final OpdsClient _client;
  bool _loading = true;
  bool _loadError = false;
  final List<OpdsNavigationLink> _navigationLinks = [];
  final List<OpdsEntry> _entries = [];
  String? _nextUrl;
  String? _prevUrl;
  bool _loadingMore = false;
  // 〔審查 review-plan-issue-5.md Minor 採納〕ListView 沒有替換 Key，
  // Element／ScrollableState 在 _goToPage() 整批替換 _entries 後仍是
  // 同一個，捲動位移預設不會自動歸零——E-Ink 離散換頁若使用者在上一頁
  // 捲到一半才換頁，新頁面會直接停在同一個像素位移，容易讓使用者誤以為
  // 換頁沒有生效或畫面跑版，換頁後主動歸零比較符合「翻到新的一頁」的
  // 直覺。
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedRemoteBookIds = {};
  // 〔審查 review-issue-3.md Minor 採納〕快速連續點擊同一個尚未勾選的
  // 書目時，避免兩次 findByRemoteBookId() 查詢並行、各自可能彈出一次
  // 重複提示——查詢期間先記錄該 remoteBookId，重入的點擊直接忽略。
  final Set<String> _pendingDuplicateChecks = {};
  String? _password;

  @override
  void initState() {
    super.initState();
    _client = widget.dependencies.createOpdsClient();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSelectable(OpdsEntry entry) => entry.acquisitions.any((a) => a.format != null);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
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
        _prevUrl = feed.prevUrl;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
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

  /// E-Ink 模式的離散換頁（epic-30-calibre-remote-library Issue 5）：與
  /// [_loadMore] 的累加語意不同——整批替換 [_entries]/[_navigationLinks]，
  /// 不是累加在後面。換頁後清空選取狀態：[_entries] 整批替換後，先前選取
  /// 的 remoteBookId 可能已經不在畫面上，[_startDownload] 只會處理目前
  /// [_entries] 內找得到的項目，若保留跨頁選取容易讓使用者誤以為换頁前
  /// 選的書也會一併下載，實際上卻被靜默忽略——比起保留容易誤解的狀態，
  /// 換頁清空更符合直覺。
  Future<void> _goToPage(String pageUrl) async {
    setState(() => _loadingMore = true);
    try {
      final feed = await _client.fetchFeed(widget.server, password: _password, feedUrl: pageUrl);
      if (!mounted) return;
      setState(() {
        _navigationLinks
          ..clear()
          ..addAll(feed.navigationLinks);
        _entries
          ..clear()
          ..addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _prevUrl = feed.prevUrl;
        _selectedRemoteBookIds.clear();
        _loadingMore = false;
      });
      // 〔審查 review-plan-issue-5.md Minor 採納〕換頁成功後把捲動位置
      // 歸零，避免停留在上一頁的捲動位移。`hasClients` 防禦性檢查——理論
      // 上 `_buildContent()` 一定會掛上 `ListView`，但 `setState()` 之後
      // 到下一次 build 完成前的極短暫窗口仍可能尚未附加，直接呼叫
      // `jumpTo()` 會拋例外。
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (_) {
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
        dependencies: widget.dependencies,
        importService: widget.importService,
        downloadQueueController: widget.downloadQueueController,
        feedUrl: link.href,
        title: link.title,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }

  Future<void> _toggleSelection(OpdsEntry entry) async {
    if (!_isSelectable(entry)) return;
    if (_selectedRemoteBookIds.contains(entry.remoteBookId)) {
      setState(() => _selectedRemoteBookIds.remove(entry.remoteBookId));
      return;
    }
    if (_pendingDuplicateChecks.contains(entry.remoteBookId)) return;
    _pendingDuplicateChecks.add(entry.remoteBookId);
    // 〔審查 review-issue-3.md Important 採納〕findByRemoteBookId() 查詢
    // 失敗（例如暫時性 SQLite 錯誤）時，不應該讓整個點擊動作靜默無反應
    // ——退化為「視同沒有查到重複」直接放行勾選，比照本畫面對「重複」
    // 本身的既有態度（偵測到也不強制阻擋，使用者仍可選擇建立新副本）。
    var hasDuplicate = false;
    try {
      hasDuplicate =
          await widget.libraryRepository.findByRemoteBookId(widget.server.id, entry.remoteBookId) !=
              null;
    } catch (_) {
      hasDuplicate = false;
    } finally {
      _pendingDuplicateChecks.remove(entry.remoteBookId);
    }
    if (hasDuplicate) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final proceed = await _showDuplicateConfirmDialog(
        context,
        l10n.remoteCatalogDuplicateConfirmMessage(entry.title),
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

    final jobs = <RemoteDownloadJob>[];
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
      jobs.add(RemoteDownloadJob(
        entry: entry,
        acquisition: chosen,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprintFn: widget.dependencies.computeFingerprint,
      ));
    }
    if (jobs.isEmpty) return;

    if (!mounted) return;
    widget.downloadQueueController.enqueueJobs(jobs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('remote_catalog_queued_snackbar'),
        content: Text(
          AppLocalizations.of(context)!.remoteCatalogQueuedMessage(jobs.length),
        ),
      ),
    );
    setState(() => _selectedRemoteBookIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.server.name),
        actions: [
          IconButton(
            key: const Key('remote_catalog_download_button'),
            icon: const Icon(Icons.download),
            tooltip: l10n.remoteCatalogDownloadSelectedTooltip,
            onPressed: _selectedRemoteBookIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(key: Key('remote_catalog_loading_indicator')),
            )
          : _loadError
              ? Center(
                  child: Text(
                    l10n.remoteCatalogLoadFailedMessage,
                    key: const Key('remote_catalog_error_text'),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return ListView(
      controller: _scrollController,
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
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildPaginationControls() {
    final l10n = AppLocalizations.of(context)!;
    if (widget.isEinkMode) {
      if (_prevUrl == null && _nextUrl == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('remote_catalog_eink_prev_page_button'),
              onPressed: _prevUrl == null || _loadingMore ? null : () => _goToPage(_prevUrl!),
              child: Text(l10n.remoteCatalogEinkPrevPageButton),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              key: const Key('remote_catalog_eink_next_page_button'),
              onPressed: _nextUrl == null || _loadingMore ? null : () => _goToPage(_nextUrl!),
              child: Text(l10n.remoteCatalogEinkNextPageButton),
            ),
          ],
        ),
      );
    }
    if (_nextUrl == null) return const SizedBox.shrink();
    return Padding(
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
              : Text(l10n.remoteCatalogLoadMoreButton),
        ),
      ),
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
      return CoverPlaceholder(
        key: Key('remote_catalog_thumbnail_placeholder_${entry.remoteBookId}'),
        icon: Icons.book,
        title: entry.title,
      );
    }
    return FutureBuilder<Uint8List>(
      future: widget.dependencies.thumbnailCache.fetch(
        widget.server,
        thumbnailUrl,
        buildOpdsAuthHeaders(widget.server, _password),
      ),
      // 〔審查 review-plan-issue-5.md Important 採納〕Flutter 的
      // FutureBuilder.didUpdateWidget() 只要傳入的 future 是新的物件實例
      // 就會把 connectionState 重置（不是 done），但 snapshot.data 仍保留
      // 上一輪成功的結果——這個 build() 方法每次重建都會呼叫一次
      // fetch()、產生新的 Future 實例（即使底層記憶體 LRU 幾乎立即命中），
      // 若先判斷 connectionState != done 就先回傳載入中佔位符，會讓已經
      // 載入完成的縮圖在任何無關的 setState()（例如勾選另一本書）後閃爍
      // 回佔位符一幀，在 E-Ink 螢幕上更明顯、恰好牴觸本 Issue 想解決的
      // 殘影問題——優先檢查 hasData，已有資料就直接顯示，不受
      // connectionState 短暫重置影響。
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return CoverPlaceholder(
            key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
            icon: Icons.book,
            title: entry.title,
          );
        }
        return CoverPlaceholder(
          key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
          icon: Icons.broken_image,
          title: entry.title,
        );
      },
    );
  }
}

/// 重複匯入確認彈窗（epic-30-calibre-remote-library Issue 3，spec.md
/// 「重複匯入偵測」）：選檔前置（Layer 1）與下載後指紋比對（Layer 2）
/// 兩層檢查共用同一個確認 UI，只有提示文字不同——精確比對命中不代表
/// 強制阻擋，使用者可選擇仍要建立新副本。
Future<bool> _showDuplicateConfirmDialog(BuildContext context, String message) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('remote_catalog_duplicate_dialog'),
      title: Text(l10n.remoteCatalogDuplicateDialogTitle),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.remoteCatalogDuplicateDialogConfirmButton),
        ),
      ],
    ),
  );
  return result ?? false;
}
