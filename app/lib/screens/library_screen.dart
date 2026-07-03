import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// 書架佔位畫面。真正的圖書庫管理邏輯屬於 epic-1-library，此處僅提供
/// 可導航、可測試的最小畫面。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('書架（佔位畫面）'),
      ),
    );
  }
}
