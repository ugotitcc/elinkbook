import 'package:flutter/material.dart';

import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';

/// Settings「同步」子頁面（spec.md「Settings『同步』子頁面」）：未登入時
/// 顯示 base URL／email／password 輸入欄位＋「連線／登入」按鈕；已登入
/// 時顯示登入中的 email＋登出按鈕，以及「立即同步」按鈕＋最後同步時間
/// （2026-09-08 `/grill-with-docs` 使用者需求）。同步功能完全可選
/// （opt-in，design.md 決策 9），不影響任何既有單機功能。
class SyncSettingsScreen extends StatefulWidget {
  final SyncAccountRepository accountRepository;
  final SyncClient syncClient;
  /// 重用 [SyncEngine.runCheckpoint]（增量同步）——刻意收窄成單一
  /// callback 而非直接依賴整個 `SyncEngine`，見 `LibrarySyncDependencies`
  /// 的欄位說明（widget test 可注入輕量假 closure，不需要真正的
  /// sqflite `Database`）。
  final Future<bool> Function() onManualSync;
  /// 重用 [SyncMetadataRepository.loadLastPushCompletedAt]，同上理由收窄。
  final Future<int?> Function() loadLastSyncedAt;

  const SyncSettingsScreen({
    super.key,
    required this.accountRepository,
    required this.syncClient,
    required this.onManualSync,
    required this.loadLastSyncedAt,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _connecting = false;
  String? _loggedInEmail;
  String? _errorText;
  bool _obscurePassword = true;
  int? _lastSyncedAtMillis;
  bool _syncing = false;

  final _baseUrlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final baseUrl = await widget.accountRepository.loadBaseUrl();
    final isLoggedIn = await widget.accountRepository.isLoggedIn();
    final email = await widget.accountRepository.loadEmail();
    final lastSyncedAtMillis = await widget.loadLastSyncedAt();
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl;
      _isLoggedIn = isLoggedIn;
      _loggedInEmail = email;
      _lastSyncedAtMillis = lastSyncedAtMillis;
      _loading = false;
    });
  }

  /// 「立即同步」按鈕（2026-09-08 `/grill-with-docs` 使用者需求）：直接
  /// 重用既有 [SyncEngine.runCheckpoint]（增量同步，不做全量重推）。失敗
  /// 時提示 SnackBar——手動觸發是使用者主動要求「現在就同步」，跟三種
  /// 既有自動觸發來源（背景化／切書／閒置 5 分鐘）刻意靜默失敗的精神不同
  /// （見 `SyncEngine.runCheckpoint` doc）。
  Future<void> _manualSync() async {
    setState(() => _syncing = true);
    final success = await widget.onManualSync();
    if (!mounted) return;
    if (success) {
      final lastSyncedAtMillis = await widget.loadLastSyncedAt();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _lastSyncedAtMillis = lastSyncedAtMillis;
      });
    } else {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同步失敗，請確認網路連線')),
      );
    }
  }

  /// 絕對日期時間格式（Q9 決策：不用相對時間，避免畫面停留很久後文字
  /// 顯得不準確）。不引入 `intl` 套件——只有這一處需要格式化，手動拼接
  /// 即可。
  String _formatLastSyncedAt() {
    final millis = _lastSyncedAtMillis;
    if (millis == null) return '尚未同步過';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '最後同步：${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _errorText = null;
    });
    final success = await widget.syncClient.testConnection(
      _baseUrlController.text,
      _emailController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      setState(() {
        _connecting = false;
        _isLoggedIn = true;
        _loggedInEmail = _emailController.text;
        _passwordController.clear();
      });
    } else {
      setState(() {
        _connecting = false;
        _errorText = '連線失敗，請確認伺服器網址與帳號密碼是否正確';
      });
    }
  }

  Future<void> _logout() async {
    await widget.syncClient.logout();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _loggedInEmail = null;
      _emailController.clear();
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('同步')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('sync_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoggedIn ? _buildLoggedInView() : _buildLoginForm(),
            ),
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已登入：${_loggedInEmail ?? ''}',
          key: const Key('sync_settings_logged_in_email'),
        ),
        const SizedBox(height: 16),
        Text(
          _formatLastSyncedAt(),
          key: const Key('sync_settings_last_synced_text'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('sync_settings_manual_sync_button'),
          onPressed: _syncing ? null : _manualSync,
          child: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('立即同步'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('sync_settings_logout_button'),
          onPressed: _logout,
          child: const Text('登出'),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('sync_settings_base_url_field'),
          controller: _baseUrlController,
          decoration: const InputDecoration(labelText: '伺服器網址'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_email_field'),
          controller: _emailController,
          // 帳密欄位停用自動校正／輸入法建議，避免鍵盤記憶敏感帳密
          // （2026-08-03 審查修正，tmp/epic-8/plan-issue-2-review.md 建議 3）。
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_password_field'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '密碼',
            suffixIcon: IconButton(
              key: const Key('sync_settings_password_visibility_toggle'),
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _errorText!,
              key: const Key('sync_settings_error_text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ElevatedButton(
          key: const Key('sync_settings_connect_button'),
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('連線／登入'),
        ),
      ],
    );
  }
}
