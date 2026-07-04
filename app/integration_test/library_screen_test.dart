import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 注意：此處測試已改為使用假實作（FakeLibraryRepository/FakeBookImportService），
  // 因為 LibraryScreen 已不再使用固定的範例書籍清單。真實的圖書庫導入與書籍渲染
  // 的集成測試將在 Issue 5 Task 3 中重新實作。
  testWidgets('LibraryScreen 以假實作呈現空清單狀態（integration_test 結構驗證）',
      (tester) async {
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
    expect(find.text('尚未匯入書籍'), findsOneWidget);
  });
}
