import 'package:flutter/material.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../remote/opds_client.dart';
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
  final ComputeRemoteFingerprint computeFingerprint;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;
  final bool isEinkMode;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.createOpdsClient,
    required this.importService,
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
          createOpdsClient: widget.createOpdsClient,
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
          createOpdsClient: widget.createOpdsClient,
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
        computeFingerprint: widget.computeFingerprint,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }

  /// **〔`review-issue-1.md` Minor #1 採納〕** 刪除站點會連帶移除已儲存
  /// 的帳密憑證，先跳確認對話框避免誤觸；「僅雲端紀錄書籍擋下刪除」的
  /// 示警對話框（下方）是另一個獨立情境，兩者不衝突。
  Future<void> _confirmDelete(RemoteServerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remote_server_delete_confirm_dialog'),
        title: const Text('刪除站點'),
        content: Text('確定要刪除站點「${profile.name}」嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('remote_server_delete_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('remote_server_delete_blocked_dialog'),
          title: const Text('無法刪除站點'),
          content: Text(
            '這個站點還有 ${e.blockingBooks.length} 本書僅有雲端紀錄、尚未下載：\n'
            '${e.blockingBooks.map((b) => '．${b.title}').join('\n')}\n\n'
            '請先於書架移除這些書籍，或重新下載後再刪除站點。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('了解'),
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
        const SnackBar(
          key: Key('remote_server_delete_error_snackbar'),
          content: Text('刪除站點失敗，請稍後再試'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('遠端書庫'),
        actions: [
          IconButton(
            key: const Key('remote_server_list_add_button'),
            icon: const Icon(Icons.add),
            tooltip: '新增站點',
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
              ? const Center(
                  child: Text(
                    '尚未新增任何遠端書庫站點',
                    key: Key('remote_server_list_empty_state'),
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
                            tooltip: '編輯',
                            onPressed: () => _openEditForm(profile),
                          ),
                          IconButton(
                            key: Key('remote_server_item_delete_${profile.id}'),
                            icon: const Icon(Icons.delete),
                            tooltip: '刪除',
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
