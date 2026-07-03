import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen 顯示設定標題與佔位內容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('設定（佔位畫面）'), findsOneWidget);
  });
}
