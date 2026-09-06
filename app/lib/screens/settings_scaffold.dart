import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/tts_provider.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_data.dart';
import 'about_screen.dart';
import 'cloud_account_settings_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';
import 'tts_defaults_screen.dart';
import 'widgets/eb_section_header.dart';

/// 設定畫面：四分區（外觀／閱讀／同步與帳號／關於，`DESIGN.md` §17，
/// epic-36-adaptive-shelf-navigation spec.md §功能⑤）。「佈景」（主題圓點，
/// 原位於 `LibraryScreen` AppBar，見 `epic-18-reader-device-qa` 工具列溢位
/// 修復）、「字型管理」、「閱讀預設值」、「導航熱區」、「同步」、「閱讀器
/// Console Log」（Issue 33 診斷用）、Console Log 攔截開關
/// （`epic-28-reader-settings-enhancements` Issue 2）與「關於」項目皆為既有
/// 功能原樣搬移，本次（由 `SettingsScreen` 更名而來）只是重新分組，行為與
/// 既有 Key 契約不變。
class SettingsScaffold extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSource;
  final TtsProvider? ttsProvider;

  const SettingsScaffold({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.onNavigateToLibrary,
    this.onNavigateToSource,
    this.ttsProvider,
  });

  @override
  State<SettingsScaffold> createState() => _SettingsScaffoldState();
}

class _SettingsScaffoldState extends State<SettingsScaffold> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式——本畫面其餘 `ListTile`
  /// （佈景／字型管理等）與這個開關無關，初始值先顯示預設 `false`，
  /// `initState()` 的非同步載入完成後才 `setState` 更新為實際已儲存值，不
  /// 阻塞其餘項目的同步顯示。
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
        actions: [
          IconButton(
            key: const Key('settings_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: '書架',
            onPressed: widget.onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('settings_source_button'),
            icon: const Icon(Icons.cloud_download),
            tooltip: '來源',
            onPressed: widget.onNavigateToSource,
          ),
        ],
      ),
      body: ListView(
        children: [
          const EBSectionHeader(title: '外觀'),
          ListTile(
            title: const Text('佈景'),
            subtitle: widget.isEinkMode
                ? const Text(
                    '這裡選的是關閉 E-Ink 後要恢復的主題',
                    key: Key('settings_theme_locked_hint'),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    'settings_theme_dot_sepia'),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('settings_eink_mode_switch'),
            title: const Text('E-Ink 高對比模式'),
            subtitle: const Text('停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化'),
            value: widget.isEinkMode,
            onChanged: widget.onEinkModeChanged,
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
          const EBSectionHeader(title: '閱讀'),
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
            key: const Key('settings_tts_defaults_button'),
            title: const Text('朗讀預設值'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TtsDefaultsScreen(
                    prefsManager: widget.prefsManager,
                    ttsProvider: widget.ttsProvider,
                    isEinkMode: widget.isEinkMode,
                  ),
                ),
              );
            },
          ),
          const EBSectionHeader(title: '同步與帳號'),
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
            key: const Key('settings_cloud_account_button'),
            title: const Text('已連結的雲端匯入帳戶'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.cloudAccountRepository == null ||
                    widget.googleDriveOAuthClient == null ||
                    widget.oneDriveOAuthClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CloudAccountSettingsScreen(
                          cloudAccountRepository: widget.cloudAccountRepository!,
                          googleDriveOAuthClient: widget.googleDriveOAuthClient!,
                          oneDriveOAuthClient: widget.oneDriveOAuthClient!,
                        ),
                      ),
                    );
                  },
          ),
          const EBSectionHeader(title: '關於'),
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
        ],
      ),
    );
  }

  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.isEinkMode;
    final isCurrentTheme = widget.currentTheme == theme;
    final isSelected = isCurrentTheme && !locked;
    return Semantics(
      label: locked
          ? '${_themeLabel(theme)}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，'
              '目前選擇：${_themeLabel(widget.currentTheme)}'
          : '${_themeLabel(theme)}佈景',
      button: !locked,
      child: GestureDetector(
        key: Key(key),
        onTap: locked ? null : () => widget.onThemeChanged?.call(theme),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: locked
                ? null
                : Border.all(
                    color: isSelected
                        ? previewTheme.colorScheme.primary
                        : previewTheme.colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
          ),
          child: locked
              ? CustomPaint(
                  painter: _LockedDotBorderPainter(
                    color: Theme.of(context).colorScheme.onSurface,
                    strokeWidth: isCurrentTheme ? 3 : 1.5,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '淺色',
        AppTheme.dark => '深色',
        AppTheme.sepia => '羊皮紙',
      };
}

/// E-Ink 鎖定狀態的圓形虛線邊框（`DESIGN.md` §17.2：邊框改為虛線，取代
/// 原本的降低透明度手法）。
class _LockedDotBorderPainter extends CustomPainter {
  const _LockedDotBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  static const double _dashLength = 3;
  static const double _gapLength = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LockedDotBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
