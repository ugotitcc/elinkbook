import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
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
  final ValueChanged<bool>? onEinkModeChanged;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;

  const SettingsScreen({
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

  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.isEinkMode;
    // isCurrentTheme 跟既有的 isSelected 是兩個不同概念：isSelected 只在
    // 「未鎖定」時才有意義（鎖定時 onTap 已經是 null，不需要選取樣式）；
    // isCurrentTheme 不受鎖定與否影響，鎖定時的虛線粗細差異要靠它才能
    // 分辨「原本選的是哪個主題」。
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

  /// 主題預覽圓點的中文名稱，供 E-Ink 鎖定狀態下的 Semantics 標籤朗讀。
  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '淺色',
        AppTheme.dark => '深色',
        AppTheme.sepia => '羊皮紙',
      };
}

/// E-Ink 鎖定狀態的圓形虛線邊框（`DESIGN.md` §17.2：邊框改為虛線，取代
/// 原本的降低透明度手法）。`strokeWidth` 由呼叫端依「是否為目前選擇的
/// 主題」傳入 `3`／`1.5`——沿用 §7.2 既有定義的「Border Width 1.5dp ->
/// 3dp」離散狀態變更數值，不是本工單另外自訂，用意是讓鎖定狀態下仍能
/// 分辨原本選的是哪個主題。虛線本身的 dash／gap 長度 `DESIGN.md` 未給
/// 精確數字，本工單自行決定為 3dp／3dp；若下一輪真機驗證發現電子紙上
/// 不夠清楚，這個數字是可直接調整的錨點。
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

