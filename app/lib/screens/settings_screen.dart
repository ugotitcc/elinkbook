import 'package:flutter/material.dart';

import '../reader/reader_prefs_manager.dart';
import 'about_screen.dart';
import 'nav_zone_settings_screen.dart';

/// 設定畫面：目前有「導航熱區」與「關於」兩個入口；其餘設定項目（版面、
/// 字型、主題等）屬於後續各功能 Epic。
class SettingsScreen extends StatelessWidget {
  final ReaderPrefsManager prefsManager;

  const SettingsScreen({super.key, required this.prefsManager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
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
}
