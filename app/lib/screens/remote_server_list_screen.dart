import 'package:flutter/material.dart';

import '../downloads/download_queue_controller.dart';
import '../l10n/app_localizations.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../remote/remote_catalog_dependencies.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';
import 'remote_catalog_screen.dart';
import 'remote_server_form_screen.dart';

/// 遠端書庫站點清單畫面（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）：新增/編輯/刪除 Calibre／OPDS 站點，刪除時
/// 若該站點仍有僅雲端紀錄（尚未下載）的書籍會被拒絕並顯示示警清單。
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;

  /// 收斂原本 `computeFingerprint`／`thumbnailCache`／`createOpdsClient`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 6）。
  final RemoteCatalogDependencies dependencies;

  final BookImportService importService;
  final bool isEinkMode;

  /// 視覺還原（Visual Accuracy Mode）：確認下載後改為加入這個常駐佇列
  /// （顯示於「來源」畫面），取代原本 `RemoteCatalogScreen` 自己
  /// `showDialog()` 跳出模態下載對話框的做法，與 `CloudBrowserScreen`
  /// 共用同一份佇列。
  final DownloadQueueController downloadQueueController;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.dependencies,
    required this.importService,
    required this.downloadQueueController,
    this.isEinkMode = false,
  });

  @override
  State<RemoteServerListScreen> createState() => _RemoteServerListScreenState();
}

class _RemoteServerListScreenState extends State<RemoteServerListScreen> {
  bool _loading = true;
  List<RemoteServerProfile> _servers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final servers = await widget.repository.listServers();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _loading = false;
    });
  }

  Future<void> _openAddForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.dependencies.createOpdsClient,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditForm(RemoteServerProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.dependencies.createOpdsClient,
          existingProfile: profile,
        ),
      ),
    );
    if (saved == true) _load();
  }

  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        dependencies: widget.dependencies,
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
        downloadQueueController: widget.downloadQueueController,
      ),
    ));
  }

  /// **〔`review-issue-1.md` Minor #1 採納〕** 刪除站點會連帶移除已儲存
  /// 的帳密憑證，先跳確認對話框避免誤觸；「僅雲端紀錄書籍擋下刪除」的
  /// 示警對話框（下方）是另一個獨立情境，兩者不衝突。
  Future<void> _confirmDelete(RemoteServerProfile profile) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remote_server_delete_confirm_dialog'),
        title: Text(l10n.remoteServerListDeleteConfirmTitle),
        content: Text(
          l10n.remoteServerListDeleteConfirmMessage(profile.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('remote_server_delete_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.remoteServerListDeleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await _delete(profile);
  }

  Future<void> _delete(RemoteServerProfile profile) async {
    try {
      await widget.repository.deleteServer(profile.id);
      _load();
    } on RemoteServerDeletionBlockedException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final titles = e.blockingBooks.map((b) => '．${b.title}').join('\n');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('remote_server_delete_blocked_dialog'),
          title: Text(l10n.remoteServerListDeleteBlockedTitle),
          content: Text(
            l10n.remoteServerListDeleteBlockedMessage(
              e.blockingBooks.length,
              titles,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.remoteServerListDeleteBlockedConfirmButton),
            ),
          ],
        ),
      );
    } catch (_) {
      // 〔審查 review-issue-1.md Important #3 採納〕刪除防護例外以外的
      // 其餘失敗（例如 secure storage 刪除失敗）不能被靜默吞掉，至少要
      // 讓使用者知道發生了什麼事。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('remote_server_delete_error_snackbar'),
          content: Text(
            AppLocalizations.of(context)!.remoteServerListDeleteFailedMessage,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remoteServerListTitle),
        actions: [
          IconButton(
            key: const Key('remote_server_list_add_button'),
            icon: const Icon(Icons.add),
            tooltip: l10n.remoteServerListAddTooltip,
            onPressed: _openAddForm,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('remote_server_list_loading_indicator'),
              ),
            )
          : _servers.isEmpty
              ? Center(
                  child: Text(
                    l10n.remoteServerListEmptyState,
                    key: const Key('remote_server_list_empty_state'),
                  ),
                )
              : ListView.builder(
                  itemCount: _servers.length,
                  itemBuilder: (context, index) {
                    final profile = _servers[index];
                    return ListTile(
                      key: Key('remote_server_item_${profile.id}'),
                      title: Text(profile.name),
                      subtitle: Text(profile.baseUrl),
                      onTap: () => _openCatalog(profile),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('remote_server_item_edit_${profile.id}'),
                            icon: const Icon(Icons.edit),
                            tooltip: l10n.remoteServerListEditTooltip,
                            onPressed: () => _openEditForm(profile),
                          ),
                          IconButton(
                            key: Key('remote_server_item_delete_${profile.id}'),
                            icon: const Icon(Icons.delete),
                            tooltip: l10n.remoteServerListDeleteTooltip,
                            onPressed: () => _confirmDelete(profile),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
