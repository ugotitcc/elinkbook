import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:elinkbook/screens/reader_console_log_screen.dart';

void main() {
  final List<ClipboardData> copiedData = [];

  // ReaderConsoleLog 每筆自帶時間戳；固定時鐘讓顯示與複製的字串可預期。
  const ts = '14:39:51.123';

  setUp(() {
    ReaderConsoleLog.clear();
    ReaderConsoleLog.clock = () => DateTime(2026, 9, 24, 14, 39, 51, 123);
    copiedData.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedData.add(ClipboardData(text: call.arguments['text'] as String));
      }
      return null;
    });
  });

  tearDown(() {
    ReaderConsoleLog.clock = DateTime.now;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('沒有記錄時顯示空狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );

    expect(find.byKey(const Key('reader_console_log_empty')), findsOneWidget);
    expect(find.byKey(const Key('reader_console_log_list')), findsNothing);
  });

  testWidgets('有記錄時依序顯示每一筆訊息', (tester) async {
    ReaderConsoleLog.add('[ERROR] 第一筆訊息');
    ReaderConsoleLog.add('[LOG] 第二筆訊息');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );

    expect(find.byKey(const Key('reader_console_log_list')), findsOneWidget);
    expect(find.text('$ts [ERROR] 第一筆訊息'), findsOneWidget);
    expect(find.text('$ts [LOG] 第二筆訊息'), findsOneWidget);
  });

  testWidgets('點擊清空按鈕後，清單清空並顯示空狀態', (tester) async {
    ReaderConsoleLog.add('[ERROR] 某筆訊息');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );
    expect(find.byKey(const Key('reader_console_log_empty')), findsNothing);

    await tester.tap(find.byKey(const Key('reader_console_log_clear_button')));
    await tester.pump();

    expect(find.byKey(const Key('reader_console_log_empty')), findsOneWidget);
    expect(ReaderConsoleLog.entries.value, isEmpty);
  });

  testWidgets('點擊「複製全部」按鈕後，所有記錄以換行組成單一字串複製到剪貼簿',
      (tester) async {
    ReaderConsoleLog.add('[ERROR] 第一筆訊息');
    ReaderConsoleLog.add('[LOG] 第二筆訊息');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );

    await tester
        .tap(find.byKey(const Key('reader_console_log_copy_all_button')));
    await tester.pump();

    expect(copiedData, hasLength(1));
    expect(copiedData.single.text,
        '$ts [ERROR] 第一筆訊息\n$ts [LOG] 第二筆訊息');
    expect(find.text('已複製全部記錄到剪貼簿'), findsOneWidget);
  });

  testWidgets('英文介面下標題/按鈕提示/空狀態提示正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );

    expect(find.text('Reader Console Log'), findsOneWidget);
    expect(find.text('No records yet'), findsOneWidget);
    expect(find.byTooltip('Copy all'), findsOneWidget);
    expect(find.byTooltip('Clear'), findsOneWidget);
  });
}
