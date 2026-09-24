import 'package:flutter/widgets.dart';

import 'app_locale.dart';
import 'app_localizations.dart';

/// 在沒有 `BuildContext` 的啟動階段（`main()` 內、`runApp()` 之前，例如
/// `AudioService.init()` 的通知頻道名稱）取得目前應使用的 [AppLocalizations]
/// （epic-45-interface-i18n Issue 10）。
///
/// 解析順序與 `MaterialApp` 完全一致：使用者在設定中明確覆寫語言
/// （[localeOverride]）時優先採用；否則走 [resolveMaterialAppLocale] 跟隨
/// 裝置語言清單（[deviceLocales]），與 `MaterialApp.localeListResolutionCallback`
/// 共用同一套解析，不另寫第二份規則。
///
/// 注意：這只是「啟動當下」的快照，之後使用者在 App 內切換語言不會回頭更新
/// 已建立的資源（例如 Android 通知頻道名稱）。
AppLocalizations resolveStartupLocalizations({
  AppLocale? localeOverride,
  List<Locale>? deviceLocales,
}) {
  final locale = localeOverride?.locale ?? resolveMaterialAppLocale(deviceLocales);
  return lookupAppLocalizations(locale);
}
