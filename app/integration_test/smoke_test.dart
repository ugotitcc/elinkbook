import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LibraryScreen 可在真實裝置/模擬器上渲染（integration_test 基礎設施驗證）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
