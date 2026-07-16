import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

const _testResolved = ResolvedPreferences(
  pageTurnMode: PageTurnMode.paginated,
  screenOrientation: ScreenOrientationSetting.auto,
  pdfFitMode: PdfFitMode.pageFit,
  pdfContrast: 0,
  pdfBrightness: 0,
  pdfBoldStrength: 0,
  pdfCropMode: PdfCropMode.none,
  dualPageMode: DualPageMode.auto,
  dualPageCoverAlone: true,
  dualPageDirection: DualPageDirection.rtl,
);

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
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
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
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
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
    TocEntry? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
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
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
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

  testWidgets('全書字元數尚未計算完成時顯示佔位符，計算完成後即時替換為估算頁碼',
      (tester) async {
    final notifier = ValueNotifier<int?>(null);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: notifier,
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester
          .widget<Text>(find.byKey(Key('toc_entry_page_${ch1.locatorJson}')))
          .data,
      '…',
    );

    notifier.value = 5000;
    await tester.pump();

    // 預設版面參數下 EpubPageEstimator.estimateCharsPerScreen() = 500，
    // totalPages = 5000/500 = 10；ch1.progression = 0.0 →
    // estimateCurrentPage(0.0, 10) = 1。
    expect(
      tester
          .widget<Text>(find.byKey(Key('toc_entry_page_${ch1.locatorJson}')))
          .data,
      '1',
    );
  });

  testWidgets(
      '全書字元數已計算完成，但節點本身 progression 為 null（原生端兩層 fallback 皆查無位置）時，'
      '頁碼仍顯示佔位符而非誤植為第 1 頁（審查修正）', (tester) async {
    const unknownPositionEntry =
        TocEntry(title: '位置不明章節', locatorJson: 'l_unknown', progression: null);
    final notifier = ValueNotifier<int?>(5000);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: const [unknownPositionEntry],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: notifier,
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester
          .widget<Text>(
              find.byKey(Key('toc_entry_page_${unknownPositionEntry.locatorJson}')))
          .data,
      '…',
      reason: 'progression 為 null 時應顯示佔位符，不應誤植為 estimateCurrentPage 的 '
          'null-fallback 值（第 1 頁），避免誤導使用者以為該章節就在全書開頭',
    );
  });
}
