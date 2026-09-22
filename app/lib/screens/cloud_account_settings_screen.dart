import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_provider.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../l10n/app_localizations.dart';

/// Settings「已連結的雲端匯入帳戶」子頁面（spec.md「UI 落地位置」）：
/// 顯示 Google Drive／OneDrive 各自的連結狀態（未連結／已連結＋帳號
/// email），各自提供連結／解除連結操作。比照 `SyncSettingsScreen` 的
/// 載入中/已連結/未連結三態結構，但資料來源是 [CloudAccountRepository]，
/// 與 `SyncAccountRepository` 完全獨立、不共用元件狀態。兩個 provider
/// 的狀態各自獨立維護（各自一組 `_xxxLinked`/`_xxxEmail`/`_xxxLinking`
/// 欄位與 `_linkXxx()`/`_unlinkXxx()` 方法），不共用單一 transient 旗標，
/// 避免其中一個 provider 的連結流程進行中時誤鎖另一個 provider 的按鈕。
class CloudAccountSettingsScreen extends StatefulWidget {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;
  final OneDriveOAuthClient oneDriveOAuthClient;

  const CloudAccountSettingsScreen({
    super.key,
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
    required this.oneDriveOAuthClient,
  });

  @override
  State<CloudAccountSettingsScreen> createState() =>
      _CloudAccountSettingsScreenState();
}

class _CloudAccountSettingsScreenState
    extends State<CloudAccountSettingsScreen> {
  bool _loading = true;
  bool _googleDriveLinking = false;
  bool _googleDriveLinked = false;
  String? _googleDriveEmail;
  bool _oneDriveLinking = false;
  bool _oneDriveLinked = false;
  String? _oneDriveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final googleDriveLinked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.googleDrive);
    final googleDriveEmail = googleDriveLinked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.googleDrive)
        : null;
    final oneDriveLinked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.oneDrive);
    final oneDriveEmail = oneDriveLinked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.oneDrive)
        : null;
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = googleDriveLinked;
      _googleDriveEmail = googleDriveEmail;
      _oneDriveLinked = oneDriveLinked;
      _oneDriveEmail = oneDriveEmail;
      _loading = false;
      // 【審查修正 review-issue-1.md Important #1，OneDrive 比照沿用】
      // _load() 是畫面「已完成處理、可以恢復互動」的唯一收斂點，兩個
      // provider 的 linking 旗標皆在此一併清空。
      _googleDriveLinking = false;
      _oneDriveLinking = false;
    });
  }

  Future<void> _linkGoogleDrive() async {
    setState(() => _googleDriveLinking = true);
    final success = await widget.googleDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _googleDriveLinking = false);
    }
  }

  Future<void> _unlinkGoogleDrive() async {
    await widget.googleDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = false;
      _googleDriveEmail = null;
    });
  }

  Future<void> _linkOneDrive() async {
    setState(() => _oneDriveLinking = true);
    final success = await widget.oneDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _oneDriveLinking = false);
    }
  }

  Future<void> _unlinkOneDrive() async {
    await widget.oneDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _oneDriveLinked = false;
      _oneDriveEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudAccountSettingsTitle)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('cloud_account_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProviderTile(
                    l10n,
                    title: 'Google Drive',
                    keyPrefix: 'google_drive',
                    linked: _googleDriveLinked,
                    linking: _googleDriveLinking,
                    email: _googleDriveEmail,
                    onLink: _linkGoogleDrive,
                    onUnlink: _unlinkGoogleDrive,
                  ),
                  const SizedBox(height: 24),
                  _buildProviderTile(
                    l10n,
                    title: 'OneDrive',
                    keyPrefix: 'onedrive',
                    linked: _oneDriveLinked,
                    linking: _oneDriveLinking,
                    email: _oneDriveEmail,
                    onLink: _linkOneDrive,
                    onUnlink: _unlinkOneDrive,
                  ),
                ],
              ),
            ),
    );
  }

  /// 單一 provider 的連結狀態區塊，`keyPrefix` 對應
  /// `cloud_account_settings_<keyPrefix>_...` 系列既有測試 key 慣例
  /// （Google Drive 沿用 Issue 1 已核准的 `google_drive` 前綴，維持不變，
  /// 不因抽出共用 helper 而變動既有 key 字串，避免破壞 Issue 1 既有
  /// widget test）。
  Widget _buildProviderTile(
    AppLocalizations l10n, {
    required String title,
    required String keyPrefix,
    required bool linked,
    required bool linking,
    required String? email,
    required VoidCallback onLink,
    required VoidCallback onUnlink,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (linked) ...[
          Text(
            l10n.cloudAccountSettingsLinkedEmail(email ?? ''),
            key: Key('cloud_account_settings_${keyPrefix}_linked_email'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_unlink_button'),
            onPressed: onUnlink,
            child: Text(l10n.cloudAccountSettingsUnlinkButton),
          ),
        ] else ...[
          Text(
            l10n.cloudAccountSettingsUnlinkedText,
            key: Key('cloud_account_settings_${keyPrefix}_unlinked_text'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_link_button'),
            onPressed: linking ? null : onLink,
            child: linking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.cloudAccountSettingsLinkButton),
          ),
        ],
      ],
    );
  }
}
