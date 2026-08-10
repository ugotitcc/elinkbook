import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
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
  showHeader: true,
  showFooter: true,
  navZoneActions: rightFlipZoneTemplate,
  showNavZoneDebugOverlay: false,
);

void main() {
  final ch1 = const PdfTocItem(title: 'Part One', pageIndex: 0, stableId: 'p0');
  final ch1s1 =
      const PdfTocItem(title: 'Chapter 1', pageIndex: 0, stableId: 'p1');
  final ch1WithChild = PdfTocItem(
    title: 'Part One',
    pageIndex: 0,
    stableId: 'p0',
    children: [ch1s1],
  );
  final noDest =
      const PdfTocItem(title: '無目的地章節', pageIndex: null, stableId: 'pNull');

  testWidgets('PDF 節點頁碼顯示為 pageIndex+1（1-indexed），不使用 EpubPageEstimator',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1WithChild],
          initiallyExpandedEntries: {ch1WithChild},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p0'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p1'))).data,
      '1',
    );
  });

  testWidgets('pageIndex 為 null 的 PDF 節點顯示佔位符', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [noDest],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_pNull'))).data,
      '…',
    );
  });

  testWidgets('點選 PDF 項目觸發 onEntrySelected 並傳遞正確的 PdfTocItem',
      (tester) async {
    PdfTocItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (entry) => selected = entry as PdfTocItem,
        ),
      ),
    ));

    await tester.tap(find.text('Part One'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('entries 為空清單時顯示提示文字，不拋出例外', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.byKey(const Key('toc_bottom_sheet_empty_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 格式下顯示三個分頁籤，且縮圖與搜尋分頁顯示佔位文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: [ch1],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('章節目錄'), findsOneWidget);
    expect(find.text('縮圖'), findsOneWidget);
    expect(find.text('搜尋'), findsOneWidget);

    // 預設顯示章節目錄
    expect(find.byKey(const Key('toc_bottom_sheet_list')), findsOneWidget);

    // 切換到縮圖分頁
    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();
    expect(find.text('此功能將於後續版本提供'), findsOneWidget);

    // 切換到搜尋分頁
    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();
    expect(find.text('此功能將於後續版本提供'), findsOneWidget);
  });
}
