import 'package:flutter/material.dart';

import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';

/// Settings「同步」子頁面（spec.md「Settings『同步』子頁面」）：未登入時
/// 顯示 base URL／email／password 輸入欄位＋「連線／登入」按鈕；已登入
/// 時顯示登入中的 email＋登出按鈕。同步功能完全可選（opt-in，design.md
/// 決策 9），不影響任何既有單機功能。
class SyncSettingsScreen extends StatefulWidget {
  final SyncAccountRepository accountRepository;
  final SyncClient syncClient;

  const SyncSettingsScreen({
    super.key,
    required this.accountRepository,
    required this.syncClient,
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
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl;
      _isLoggedIn = isLoggedIn;
      _loggedInEmail = email;
      _loading = false;
    });
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
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '密碼'),
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
