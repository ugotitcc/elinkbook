import 'package:flutter/material.dart';

import 'about_screen.dart';

/// 設定畫面：目前只有「關於」入口可用；其餘設定項目（版面、字型、主題等）
/// 屬於後續各功能 Epic。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
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
