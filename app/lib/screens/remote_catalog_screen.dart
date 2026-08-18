import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../remote/opds_client.dart';
import '../remote/opds_types.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// OPDS 目錄瀏覽畫面（epic-30-calibre-remote-library Issue 2，
/// spec.md「UI 落地位置」）：依 [OpdsFeed.navigationLinks] 分類下鑽（點擊
/// 後 push 新的本畫面實例）、依 [OpdsFeed.nextUrl] 提供「載入更多」、
/// 封面縮圖網格（帶 Basic Auth header）、多選勾選批次下載。
///
/// [createOpdsClient] 在 [initState] 只呼叫一次，整個瀏覽 session（含
/// 分頁下鑽、下載）共用同一個 [OpdsClient] 實例——比照
/// `opds_http_client.dart` 類別文件的生命週期警告，分頁循環防護的
/// `_visitedFeedUrls` 才會正確對應「一次瀏覽路徑」。
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
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
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
      ),
    ));
  }

  void _toggleSelection(OpdsEntry entry) {
    if (!_isSelectable(entry)) return;
    setState(() {
      if (_selectedRemoteBookIds.contains(entry.remoteBookId)) {
        _selectedRemoteBookIds.remove(entry.remoteBookId);
      } else {
        _selectedRemoteBookIds.add(entry.remoteBookId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? widget.server.name)),
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
