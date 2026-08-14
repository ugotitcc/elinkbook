import 'package:flutter/material.dart';

import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';

/// 設定畫面：「佈景」（主題圓點，原位於 `LibraryScreen` AppBar，見
/// `epic-18-reader-device-qa` 工具列溢位修復）、「字型管理」、「閱讀預設值」、
/// 「導航熱區」、「同步」、「閱讀器 Console Log」（Issue 33 診斷用）、
/// Console Log 攔截開關（epic-28-reader-settings-enhancements Issue 2）與
/// 「關於」項目。
class SettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式（比照
  /// `ReadingDefaultsScreen` 的 `_loading` 布林 + `CircularProgressIndicator`
  /// 擋住整頁）——本畫面其餘 `ListTile`（佈景／字型管理等）與這個開關無關，
  /// 初始值先顯示預設 `false`，`initState()` 的非同步載入完成後才 `setState`
  /// 更新為實際已儲存值，不阻塞其餘項目的同步顯示。
  bool _consoleLogEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadConsoleLogEnabled();
  }

  Future<void> _loadConsoleLogEnabled() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _consoleLogEnabled = prefs.consoleLogEnabled);
  }

  Future<void> _updateConsoleLogEnabled(bool value) async {
    setState(() => _consoleLogEnabled = value);
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    await widget.prefsManager
        .saveGlobalPrefs(prefs.copyWith(consoleLogEnabled: value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('佈景'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    const Color(0xFFF5F5F5), 'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    const Color(0xFF121212), 'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    const Color(0xFFF4ECD8), 'settings_theme_dot_sepia'),
              ],
            ),
          ),
          ListTile(
            key: const Key('settings_font_management_button'),
            title: const Text('字型管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.customFontsRepository == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => FontManagementScreen(
                          repository: widget.customFontsRepository!,
                        ),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const Key('settings_reading_defaults_button'),
            title: const Text('閱讀預設值'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ReadingDefaultsScreen(prefsManager: widget.prefsManager),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('settings_nav_zone_button'),
            title: const Text('導航熱區'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      NavZoneSettingsScreen(prefsManager: widget.prefsManager),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('settings_sync_button'),
            title: const Text('同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.syncAccountRepository == null ||
                    widget.syncClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SyncSettingsScreen(
                          accountRepository: widget.syncAccountRepository!,
                          syncClient: widget.syncClient!,
                        ),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const Key('settings_reader_console_log_button'),
            title: const Text('閱讀器 Console Log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ReaderConsoleLogScreen(),
                ),
              );
            },
          ),
          SwitchListTile(
            key: const Key('settings_console_log_switch'),
            title: const Text('Console Log 攔截'),
            subtitle: const Text('關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄'),
            value: _consoleLogEnabled,
            onChanged: (value) => _updateConsoleLogEnabled(value),
          ),
          ListTile(
            key: const Key('settings_about_button'),
            title: const Text('關於'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 主題選擇圓點，比照 `epic-18` 之前放在 `LibraryScreen` AppBar 的既有互動
  /// 設計原樣搬移（E-Ink 模式下停用點擊並降低不透明度）。
  Widget _buildThemeDot(
      BuildContext context, AppTheme theme, Color color, String key) {
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap:
          widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
