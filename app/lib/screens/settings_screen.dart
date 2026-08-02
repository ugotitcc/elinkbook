import 'package:flutter/material.dart';

import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reading_defaults_screen.dart';

/// 設定畫面：「佈景」（主題圓點，原位於 `LibraryScreen` AppBar，見
/// `epic-18-reader-device-qa` 工具列溢位修復）、「字型管理」、「閱讀預設值」、
/// 「導航熱區」與「關於」五個項目。
class SettingsScreen extends StatelessWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final CustomFontsRepository? customFontsRepository;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
  });

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
            onTap: customFontsRepository == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => FontManagementScreen(
                          repository: customFontsRepository!,
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
                      ReadingDefaultsScreen(prefsManager: prefsManager),
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
                      NavZoneSettingsScreen(prefsManager: prefsManager),
                ),
              );
            },
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
    final isSelected = currentTheme == theme && !isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap: isEinkMode ? null : () => onThemeChanged?.call(theme),
      child: Opacity(
        opacity: isEinkMode ? 0.4 : 1.0,
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
