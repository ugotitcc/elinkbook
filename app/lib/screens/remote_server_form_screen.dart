import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../remote/opds_client.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// 新增/編輯遠端書庫站點表單（epic-30-calibre-remote-library Issue 1，
/// spec.md「UI 落地位置」）。密碼欄位刻意不預填既有密碼（比照
/// `sync_settings_screen.dart` 既有安全慣例）——編輯模式下密碼欄位留空
/// 的實際語意見 [_resolvePasswordToUse]（`review-issue-1.md` Important
/// #2 核實：本處先前的文字描述與該方法的行為不一致，已更正為指向單一
/// 事實來源，避免兩處各說各話）。
class RemoteServerFormScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final OpdsClient Function() createOpdsClient;
  final RemoteServerProfile? existingProfile;

  const RemoteServerFormScreen({
    super.key,
    required this.repository,
    required this.createOpdsClient,
    this.existingProfile,
  });

  @override
  State<RemoteServerFormScreen> createState() => _RemoteServerFormScreenState();
}

class _RemoteServerFormScreenState extends State<RemoteServerFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  late RemoteServerType _type;
  late bool _allowInsecure;

  bool _testing = false;
  String? _testResultText;
  bool _saving = false;
  String? _validationError;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProfile;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _baseUrlController = TextEditingController(text: existing?.baseUrl ?? '');
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _type = existing?.type ?? RemoteServerType.opds;
    _allowInsecure = existing?.allowInsecure ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  RemoteServerProfile _buildProfile() {
    final username = _usernameController.text.trim();
    return RemoteServerProfile(
      id: widget.existingProfile?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      type: _type,
      username: username.isEmpty ? null : username,
      allowInsecure: _allowInsecure,
      createdAt: widget.existingProfile?.createdAt ?? DateTime.now(),
      lastAccessedAt: widget.existingProfile?.lastAccessedAt,
    );
  }

  /// **〔`review-plan-issue-1.md` Finding 1 採納〕** 解析「這次應該實際
  /// 送出的密碼」，供 [_testConnection] 與 [_save] 共用同一套邏輯：
  /// - 密碼欄位有輸入 → 用新輸入的密碼。
  /// - 新增模式且密碼欄位留空 → `null`（匿名連線，語意不變）。
  /// - 編輯模式、密碼欄位留空、帳號欄位已被清空 → `null`（使用者清空
  ///   帳號等同主動宣告改用匿名連線，密碼一併清除）。
  /// - 編輯模式、密碼欄位留空、帳號欄位仍有值 → 讀回既有密碼沿用，
  ///   視為「不變更密碼」——密碼欄位基於安全考量從不預填既有密碼
  ///   （見上方類別文件），若把「留空」直接當成「清空密碼」，使用者
  ///   只是想改個站點名稱就會意外把已儲存的密碼洗掉。
  Future<String?> _resolvePasswordToUse() async {
    if (_passwordController.text.isNotEmpty) return _passwordController.text;
    if (!_isEditing) return null;
    if (_usernameController.text.trim().isEmpty) return null;
    return widget.repository.loadPassword(widget.existingProfile!.id);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResultText = null;
    });
    final password = await _resolvePasswordToUse();
    final success =
        await widget.createOpdsClient().testConnection(_buildProfile(), password: password);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResultText = success ? '連線成功' : '連線失敗，請檢查網址/帳密/憑證設定';
    });
  }

  /// **〔`review-issue-1.md` Minor #2 採納〕** 僅驗證 `baseUrl` 是否具備
  /// `http`/`https` schema，不驗證主機是否真的可連線（那是「測試連線」
  /// 按鈕的職責）——避免使用者用明顯不是網址的字串儲存後，才在測試連線
  /// 得到籠統的「連線失敗」。
  bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _baseUrlController.text.trim().isEmpty) {
      setState(() => _validationError = '請填寫站點名稱與網址');
      return;
    }
    if (!_isValidBaseUrl(_baseUrlController.text.trim())) {
      setState(() => _validationError = '請輸入有效的伺服器網址（需以 http:// 或 https:// 開頭）');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final profile = _buildProfile();
    // 〔審查 review-issue-1.md Important #3 採納〕SQLite／secure storage
    // 寫入失敗時（本專案鎖定的低階/E-Ink 裝置上並非不可能發生）不能讓
    // 畫面卡在「儲存中」且使用者拿不到任何回饋，改為顯示錯誤文字並恢復
    // 可互動狀態，讓使用者能重試或先排除問題。
    try {
      final password = await _resolvePasswordToUse();
      if (_isEditing) {
        await widget.repository.updateServer(profile, password: password);
      } else {
        await widget.repository.addServer(profile, password: password);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = '儲存失敗，請稍後再試';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '編輯站點' : '新增站點')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('remote_server_form_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: '站點名稱'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_base_url_field'),
              controller: _baseUrlController,
              decoration: const InputDecoration(labelText: '伺服器網址'),
            ),
            const SizedBox(height: 8),
            DropdownButton<RemoteServerType>(
              key: const Key('remote_server_form_type_dropdown'),
              value: _type,
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
              items: const [
                DropdownMenuItem(
                  value: RemoteServerType.opds,
                  child: Text('標準 OPDS'),
                ),
                DropdownMenuItem(
                  value: RemoteServerType.calibreServer,
                  child: Text('原生 Calibre Content Server'),
                ),
                DropdownMenuItem(
                  value: RemoteServerType.calibreWeb,
                  child: Text('Calibre-Web'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_username_field'),
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '帳號（留空代表匿名連線）'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_password_field'),
              controller: _passwordController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _isEditing
                    ? '密碼（留空＝沿用既有密碼；清空上方帳號欄位則一併清除密碼）'
                    : '密碼',
              ),
            ),
            SwitchListTile(
              key: const Key('remote_server_form_allow_insecure_switch'),
              title: const Text('允許不安全連線（自簽憑證／純 HTTP）'),
              value: _allowInsecure,
              onChanged: (value) => setState(() => _allowInsecure = value),
            ),
            const SizedBox(height: 16),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _validationError!,
                  key: const Key('remote_server_form_validation_error_text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_testResultText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _testResultText!,
                  key: const Key('remote_server_form_test_result_text'),
                ),
              ),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('remote_server_form_test_connection_button'),
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('測試連線'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('remote_server_form_save_button'),
                  onPressed: _saving ? null : _save,
                  child: const Text('儲存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
