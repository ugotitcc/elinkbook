import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_provider.dart';
import '../cloud_import/google_drive_oauth_client.dart';

/// Settings「已連結的雲端匯入帳戶」子頁面（spec.md「UI 落地位置」）：
/// 顯示 Google Drive 連結狀態（未連結／已連結＋帳號 email），提供連結／
/// 解除連結操作。比照 `SyncSettingsScreen` 的載入中/已連結/未連結三態
/// 結構，但資料來源是 [CloudAccountRepository]，與 `SyncAccountRepository`
/// 完全獨立、不共用元件狀態。OneDrive 由 Issue 2 擴充。
class CloudAccountSettingsScreen extends StatefulWidget {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;

  const CloudAccountSettingsScreen({
    super.key,
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
  });

  @override
  State<CloudAccountSettingsScreen> createState() =>
      _CloudAccountSettingsScreenState();
}

class _CloudAccountSettingsScreenState
    extends State<CloudAccountSettingsScreen> {
  bool _loading = true;
  bool _linking = false;
  bool _googleDriveLinked = false;
  String? _googleDriveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final linked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.googleDrive);
    final email = linked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.googleDrive)
        : null;
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = linked;
      _googleDriveEmail = email;
      _loading = false;
    });
  }

  Future<void> _link() async {
    setState(() => _linking = true);
    final success = await widget.googleDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    await widget.googleDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = false;
      _googleDriveEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已連結的雲端匯入帳戶')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('cloud_account_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _buildGoogleDriveTile(),
            ),
    );
  }

  Widget _buildGoogleDriveTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Google Drive', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_googleDriveLinked) ...[
          Text(
            '已連結：${_googleDriveEmail ?? ''}',
            key: const Key('cloud_account_settings_google_drive_linked_email'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('cloud_account_settings_google_drive_unlink_button'),
            onPressed: _unlink,
            child: const Text('解除連結'),
          ),
        ] else ...[
          const Text(
            '未連結',
            key: Key('cloud_account_settings_google_drive_unlinked_text'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('cloud_account_settings_google_drive_link_button'),
            onPressed: _linking ? null : _link,
            child: _linking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('連結'),
          ),
        ],
      ],
    );
  }
}
