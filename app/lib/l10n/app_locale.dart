import 'package:flutter/widgets.dart';

/// 多語系介面（epic-45-interface-i18n，FR-49）支援的三個語系。
enum AppLocale {
  zhTW,
  zhCN,
  en;

  Locale get locale => switch (this) {
        AppLocale.zhTW => const Locale('zh', 'TW'),
        AppLocale.zhCN => const Locale('zh', 'CN'),
        AppLocale.en => const Locale('en'),
      };
}

/// 依「Locale 解析矩陣」把裝置回報的任意 [Locale] 對應到本 App 支援的三個
/// 語系之一。純函式，不依賴 BuildContext，供 [resolveMaterialAppLocale] 與
/// 單元測試共用。
///
/// 必須先比對 [Locale.languageCode]，再依中文語境下的 script/country 判斷
/// 繁簡——先比對 country 會導致 en_SG／en_HK／en_TW（港澳星台地區偏好英文
/// 介面的使用者，常見情境）被地區代碼誤判為中文。
AppLocale resolveSupportedLocale(Locale deviceLocale) {
  final language = deviceLocale.languageCode;
  final script = deviceLocale.scriptCode;
  final country = deviceLocale.countryCode;

  if (language == 'zh') {
    if (script == 'Hans' || const {'CN', 'SG'}.contains(country)) {
      return AppLocale.zhCN;
    }
    // 涵蓋 script == 'Hant'、country 屬於 {TW, HK, MO}，或純 'zh' 無
    // script/country 資訊的情況，一律預設正體中文。
    return AppLocale.zhTW;
  }
  if (language == 'en') return AppLocale.en;

  // 其餘所有非中文、非英語系，fallback 至正體中文。
  return AppLocale.zhTW;
}

/// 供 `MaterialApp.localeListResolutionCallback` 使用：依序走訪裝置的語言
/// 喜好清單，採用第一個語言碼落在本 App 實際支援範圍（zh／en）的項目；
/// 清單為 null 或全部不支援時才 fallback 正體中文。刻意不只取
/// `deviceLocales.firstOrNull`——那會讓「次要偏好為中文/英文、但首選是本
/// App 不支援語言」的使用者被直接 fallback 正體中文，忽視次要偏好。
Locale resolveMaterialAppLocale(List<Locale>? deviceLocales) {
  for (final locale in deviceLocales ?? const <Locale>[]) {
    if (locale.languageCode == 'zh' || locale.languageCode == 'en') {
      return resolveSupportedLocale(locale).locale;
    }
  }
  return AppLocale.zhTW.locale;
}
