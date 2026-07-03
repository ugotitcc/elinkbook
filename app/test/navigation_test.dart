import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  testWidgets('點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);

    // 點擊 AppBar 的返回按鈕以代替 tester.pageBack()，增加測試強健度
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
