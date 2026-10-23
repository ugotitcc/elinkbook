import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 長目錄：60 個同層章節，列高約 56dp，遠超過一個螢幕。
final _chapters = [
  for (var i = 0; i < 60; i++)
    TocEntry(title: '章節 $i', locatorJson: 'l$i', progression: i / 60),
];

Future<void> _pump(WidgetTester tester, {TocEntry? current}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TocBottomSheet(
        entries: _chapters,
        initiallyExpandedEntries: const {},
        currentEntry: current,
        onEntrySelected: (_) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('目錄清單往下捲動後，標題列與關閉鈕仍固定在畫面上', (tester) async {
    await _pump(tester);

    await tester.drag(
      find.byKey(const Key('toc_bottom_sheet_list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    final close = find.byKey(const Key('toc_bottom_sheet_close_button'));
    expect(close, findsOneWidget);
    expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(0));
  });

  testWidgets('開啟長目錄時自動捲到目前章節，不必從頭往下滑', (tester) async {
    await _pump(tester, current: _chapters[50]);

    final row = find.byKey(Key('toc_entry_${_chapters[50].stableId}'));
    expect(row, findsOneWidget);
    final viewHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final rect = tester.getRect(row);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(viewHeight));
  });
}
