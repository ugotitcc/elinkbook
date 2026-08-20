import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_toc_item.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

void main() {
  final ch1 =
      const TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
  final ch2s1 =
      const TocEntry(title: '第一節', locatorJson: 'l2s1', progression: 0.35);
  final ch2s2 =
      const TocEntry(title: '第二節', locatorJson: 'l2s2', progression: 0.45);
  final ch2 = TocEntry(
    title: '第二章',
    locatorJson: 'l2',
    progression: 0.3,
    children: [ch2s1, ch2s2],
  );
  final ch3s1 =
      const TocEntry(title: '附錄一', locatorJson: 'l3s1', progression: 0.85);
  final ch3 = TocEntry(
    title: '第三章',
    locatorJson: 'l3',
    progression: 0.7,
    children: [ch3s1],
  );
  final entries = [ch1, ch2, ch3];

  testWidgets('多層級結構正確渲染，當前章節路徑預設展開、其餘章節預設收起',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
    expect(find.text('第一節'), findsOneWidget); // ch2 已預設展開
    expect(find.text('第二節'), findsOneWidget);
    expect(find.text('第三章'), findsOneWidget);
    expect(find.text('附錄一'),
        findsNothing); // ch3 未在目前路徑內，預設收起

    await tester
        .tap(find.byKey(Key('toc_entry_expand_${ch3.locatorJson}')));
    await tester.pump();

    expect(find.text('附錄一'), findsOneWidget);
  });

  testWidgets('當前章節項目標題以粗體高亮顯示，其餘項目不受影響', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    final currentTitle = tester.widget<Text>(find.text('第一節'));
    expect(currentTitle.style?.fontWeight, FontWeight.bold);

    final otherTitle = tester.widget<Text>(find.text('第一章'));
    expect(otherTitle.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('點選項目標題觸發 onEntrySelected 並傳遞正確的 TocEntry',
      (tester) async {
    BookTocItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (entry) => selected = entry,
        ),
      ),
    ));

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('點擊展開/收起按鈕不會觸發 onEntrySelected（兩個熱區互不干擾）',
      (tester) async {
    var selectedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) => selectedCount++,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(Key('toc_entry_expand_${ch2.locatorJson}')));
    await tester.pump();

    expect(selectedCount, 0);
    expect(find.text('第一節'), findsOneWidget,
        reason: '展開按鈕本身仍應正常運作');
  });

  testWidgets(
      'EPUB／TXT／MD 目錄項目不顯示頁碼標籤（僅標題），epic-26-architecture-hardening '
      'Issue 5：EpubPageEstimator／totalCharacterCount 估算管線已移除', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      find.byKey(Key('toc_entry_page_${ch1.locatorJson}')),
      findsNothing,
      reason: 'EPUB 目錄項目不再顯示頁碼標籤（Issue 5 選項 A：不重新設計字元數回報管道）',
    );
    expect(find.text('第一章'), findsOneWidget, reason: '標題仍正常顯示');
  });

  testWidgets('點擊右上角 X 取消按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）',
      (tester) async {
    await _pumpModalSheet(tester, entries);

    expect(find.byType(TocBottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing);
  });
}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  List<TocEntry> entries,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => TocBottomSheet(
              entries: entries,
              initiallyExpandedEntries: const {},
              currentEntry: null,
              onEntrySelected: (_) {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
