import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

/// 統一測試包裝器（epic-45-interface-i18n Issue 0，`spec.md` §8）：既有
/// 測試檔案大量各自建構裸 `MaterialApp(...)`，一旦畫面改用
/// `AppLocalizations.of(context)!` 就會因缺少 `localizationsDelegates`
/// 觸發 `Null check operator` 崩潰。本函式強制注入
/// `AppLocalizations.localizationsDelegates`/`supportedLocales`，並把
/// `locale` 預設釘定為正體中文，讓既有中文 `find.text()` 斷言在遷移期間
/// 維持通過。`theme`/`isEinkMode` 直接收 `AppTheme`/`bool`（而非裸
/// `ThemeData?`），內部呼叫既有 `resolveThemeData()`，比照既有測試檔案
/// `MaterialApp(theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false), ...)`
/// 這種既定寫法收窄參數型別。
Future<void> pumpLocalizedWidget(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: navigatorObservers,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
    home: home,
  ));
}
