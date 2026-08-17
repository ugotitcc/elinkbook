import 'package:flutter/material.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// 新增/編輯遠端書庫站點表單（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）。完整實作見 Task 8；本檔案由 Task 7 建立
/// 最小可編譯版本，Task 8 逐步補齊欄位與測試連線邏輯。
class RemoteServerFormScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient opdsClient;
  final RemoteServerProfile? existingProfile;

  const RemoteServerFormScreen({
    super.key,
    required this.repository,
    required this.opdsClient,
    this.existingProfile,
  });

  @override
  State<RemoteServerFormScreen> createState() => _RemoteServerFormScreenState();
}

class _RemoteServerFormScreenState extends State<RemoteServerFormScreen> {
  bool get _isEditing => widget.existingProfile != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯站點' : '新增站點')),
      body: const SizedBox.shrink(),
    );
  }
}
