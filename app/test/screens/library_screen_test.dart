import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  testWidgets('圖書庫為空時顯示「尚未匯入書籍」提示與匯入按鈕', (tester) async {
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
    expect(
      find.byKey(const Key('library_empty_import_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library_import_button')), findsOneWidget);
  });
}
