import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  testWidgets('LibraryScreen 顯示書架標題與佔位內容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('書架（佔位畫面）'), findsOneWidget);
  });
}
