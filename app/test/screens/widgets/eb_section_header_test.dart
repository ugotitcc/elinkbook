import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/widgets/eb_section_header.dart';

void main() {
  testWidgets('顯示傳入的標題文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EBSectionHeader(title: '外觀')),
      ),
    );

    expect(find.text('外觀'), findsOneWidget);
  });

  testWidgets('文字樣式為粗體（DESIGN.md §17 分區標題規格）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EBSectionHeader(title: '閱讀')),
      ),
    );

    final text = tester.widget<Text>(find.text('閱讀'));
    expect(text.style?.fontWeight, FontWeight.bold);
  });
}
