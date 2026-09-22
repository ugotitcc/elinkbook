import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/format_selection_dialog.dart';

void main() {
  const entry = OpdsEntry(
    remoteBookId: 'book-1',
    title: '紅樓夢',
    acquisitions: [
      OpdsAcquisition(href: 'http://example.com/1.epub', format: BookFileFormat.epub),
      OpdsAcquisition(href: 'http://example.com/1.pdf', format: BookFileFormat.pdf),
      OpdsAcquisition(href: 'http://example.com/1.doc', format: null),
    ],
  );

  testWidgets('顯示每個 acquisition 的格式選項，不支援格式置灰', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('format_selection_option_http://example.com/1.epub')),
        findsOneWidget);
    expect(find.byKey(const Key('format_selection_option_http://example.com/1.pdf')),
        findsOneWidget);
    final unsupportedTile = tester.widget<ListTile>(
        find.byKey(const Key('format_selection_option_http://example.com/1.doc')));
    expect(unsupportedTile.enabled, false);
  });

  testWidgets('點擊支援的格式選項後回傳對應 OpdsAcquisition', (tester) async {
    OpdsAcquisition? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('format_selection_option_http://example.com/1.epub')));
    await tester.pumpAndSettle();

    expect(result?.format, BookFileFormat.epub);
  });

  testWidgets('點擊取消時回傳 null', (tester) async {
    OpdsAcquisition? result;
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await FormatSelectionDialog.show(context, entry);
            completed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(completed, true);
    expect(result, isNull);
  });

  testWidgets('英文介面下標題與按鈕正確顯示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Select Format: 紅樓夢'), findsOneWidget);
    final unsupportedTile = tester.widget<ListTile>(
        find.byKey(const Key('format_selection_option_http://example.com/1.doc')));
    expect((unsupportedTile.title as Text).data, 'Unsupported format');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
