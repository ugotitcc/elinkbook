import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/library_screen.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
