import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:elinkbook/screens/reader_console_log_screen.dart';

void main() {
  setUp(() {
    ReaderConsoleLog.clear();
  });

  testWidgets('沒有記錄時顯示空狀態', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReaderConsoleLogScreen()),
    );

    expect(find.byKey(const Key('reader_console_log_empty')), findsOneWidget);
    expect(find.byKey(const Key('reader_console_log_list')), findsNothing);
  });

  testWidgets('有記錄時依序顯示每一筆訊息', (tester) async {
    ReaderConsoleLog.add('[ERROR] 第一筆訊息');
    ReaderConsoleLog.add('[LOG] 第二筆訊息');

    await tester.pumpWidget(
      const MaterialApp(home: ReaderConsoleLogScreen()),
    );

    expect(find.byKey(const Key('reader_console_log_list')), findsOneWidget);
    expect(find.text('[ERROR] 第一筆訊息'), findsOneWidget);
    expect(find.text('[LOG] 第二筆訊息'), findsOneWidget);
  });

  testWidgets('點擊清空按鈕後，清單清空並顯示空狀態', (tester) async {
    ReaderConsoleLog.add('[ERROR] 某筆訊息');

    await tester.pumpWidget(
      const MaterialApp(home: ReaderConsoleLogScreen()),
    );
    expect(find.byKey(const Key('reader_console_log_empty')), findsNothing);

    await tester.tap(find.byKey(const Key('reader_console_log_clear_button')));
    await tester.pump();

    expect(find.byKey(const Key('reader_console_log_empty')), findsOneWidget);
    expect(ReaderConsoleLog.entries.value, isEmpty);
  });
}
