import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/reading_position_conflict_dialog.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

void main() {
  const conflict = ReadingPositionConflict(
    bookId: 'b1',
    bookTitle: '測試書名',
    format: BookFileFormat.pdf,
    local: ReadingPositionSnapshot(pdfPageIndex: 9, progress: 0.5),
    remote: ReadingPositionSnapshot(pdfPageIndex: 19, progress: 0.8),
  );

  Future<void> pumpTrigger(
    WidgetTester tester,
    ValueSetter<ReadingPositionChoice?> onResult, {
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final choice = await showReadingPositionConflictDialog(context, conflict);
            onResult(choice);
          },
          child: const Text('trigger'),
        ),
      ),
    ));
  }

  testWidgets('顯示書名，以及本機／雲端兩個版本的進度描述', (tester) async {
    await pumpTrigger(tester, (_) {});
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.textContaining('測試書名'), findsOneWidget);
    expect(find.textContaining('第 10 頁'), findsOneWidget); // pdfPageIndex 9 -> 顯示第 10 頁
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('第 20 頁'), findsOneWidget);
    expect(find.textContaining('80%'), findsOneWidget);
  });

  testWidgets('點擊「保留本機」，回傳 ReadingPositionChoice.keepLocal', (tester) async {
    ReadingPositionChoice? result;
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading_position_conflict_keep_local')));
    await tester.pumpAndSettle();

    expect(result, ReadingPositionChoice.keepLocal);
  });

  testWidgets('點擊「保留雲端」，回傳 ReadingPositionChoice.keepCloud', (tester) async {
    ReadingPositionChoice? result;
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading_position_conflict_keep_cloud')));
    await tester.pumpAndSettle();

    expect(result, ReadingPositionChoice.keepCloud);
  });

  testWidgets('點擊對話框外部關閉（未決定）時，回傳 null，不視為任何選擇', (tester) async {
    ReadingPositionChoice? result = ReadingPositionChoice.keepLocal; // 給一個非 null 初始值，確保下方真的被覆寫成 null
    await pumpTrigger(tester, (choice) => result = choice);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // 點擊 barrier（對話框外部區域）觸發預設的 dismiss 行為。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
  testWidgets('英文介面下標題/訊息/按鈕正確以英文渲染', (tester) async {
    await pumpTrigger(tester, (_) {}, locale: const Locale('en'));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't match"), findsOneWidget);
    expect(find.text('Keep cloud'), findsOneWidget);
    expect(find.text('Keep this device'), findsOneWidget);
  });
}
