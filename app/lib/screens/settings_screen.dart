import 'package:flutter/material.dart';

/// 設定佔位畫面。實際設定項目（版面、字型、主題等）屬於後續各功能 Epic，
/// 此處僅提供可導航、可測試的最小畫面。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: const Center(
        child: Text('設定（佔位畫面）'),
      ),
    );
  }
}
