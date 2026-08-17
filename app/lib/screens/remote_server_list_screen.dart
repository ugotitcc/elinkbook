import 'package:flutter/material.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';
import 'remote_server_form_screen.dart';

/// 遠端書庫站點清單畫面（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）：新增/編輯/刪除 Calibre／OPDS 站點，刪除時
/// 若該站點仍有僅雲端紀錄（尚未下載）的書籍會被拒絕並顯示示警清單。
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient opdsClient;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.opdsClient,
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
          opdsClient: widget.opdsClient,
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
          opdsClient: widget.opdsClient,
          existingProfile: profile,
        ),
      ),
    );
    if (saved == true) _load();
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
                      onTap: () => _openEditForm(profile),
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
                            onPressed: () => _delete(profile),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
