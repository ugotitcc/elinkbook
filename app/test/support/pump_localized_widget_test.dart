import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

import 'pump_localized_widget.dart';

void main() {
  testWidgets('預設參數：成功 pump 一個簡單 Text widget 且不拋例外', (tester) async {
    await pumpLocalizedWidget(tester, const Text('hello'));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('預設 locale 為正體中文', (tester) async {
    late Locale resolvedLocale;
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) {
          resolvedLocale = Localizations.localeOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(resolvedLocale, const Locale('zh', 'TW'));
  });

  testWidgets('可指定其他 locale，且 AppLocalizations.of(context) 正確可用', (tester) async {
    late AppLocalizations l10n;
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context)!;
          return const SizedBox.shrink();
        },
      ),
      locale: const Locale('en'),
    );
    expect(l10n.groupUncategorized, 'Uncategorized');
  });

  testWidgets(
      '可傳入 navigatorObservers 並正確透傳給 MaterialApp（/receiving-code-review I-2 修正）',
      (tester) async {
    final observer = NavigatorObserver();
    await pumpLocalizedWidget(
      tester,
      const Text('hello'),
      navigatorObservers: [observer],
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.navigatorObservers, contains(observer));
  });
}
