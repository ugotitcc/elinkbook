import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';

/// WiFi 傳書網頁（`assets/wifi_transfer/index.html`，由 App 內建 HTTP Server 提供、
/// 在「電腦瀏覽器」上顯示）的多語系支援（epic-45-interface-i18n Issue 10）。
///
/// 這個顯示面不在 Flutter Widget 樹內，所以無法用 `AppLocalizations.of(context)`：
/// 語言改由瀏覽器送來的 `Accept-Language` 決定（見 [resolveWifiPageLocale]），
/// 字串與其他畫面一樣放在 ARB（單一事實來源、三語言對齊測試一併涵蓋），
/// 由 [renderWifiTransferPage] 在提供頁面時注入。
///
/// 為何以「瀏覽器語言」而不是「App 目前語言」：讀這個網頁的是電腦前的人，
/// 電腦瀏覽器的語言偏好才是該處的權威；App 內的語言設定屬於手機畫面。
Locale resolveWifiPageLocale(String? acceptLanguage) {
  return resolveMaterialAppLocale(parseAcceptLanguage(acceptLanguage));
}

/// 解析 `Accept-Language` 標頭為依偏好排序（q 值高者在前、同 q 保持原順序）的
/// [Locale] 清單。`q=0`（明確拒絕）與萬用字元 `*` 略過，格式錯誤的項目忽略。
List<Locale> parseAcceptLanguage(String? header) {
  if (header == null || header.trim().isEmpty) return const [];
  final entries = <({Locale locale, double q, int order})>[];
  var order = 0;
  for (final part in header.split(',')) {
    final pieces = part.trim().split(';');
    final tag = pieces.first.trim();
    if (tag.isEmpty || tag == '*') continue;
    var q = 1.0;
    for (final param in pieces.skip(1)) {
      final kv = param.trim().split('=');
      if (kv.length == 2 && kv[0].trim().toLowerCase() == 'q') {
        q = double.tryParse(kv[1].trim()) ?? 0;
      }
    }
    if (q <= 0) continue;
    final locale = _localeFromTag(tag);
    if (locale == null) continue;
    entries.add((locale: locale, q: q, order: order++));
  }
  entries.sort((a, b) {
    final byQ = b.q.compareTo(a.q);
    return byQ != 0 ? byQ : a.order.compareTo(b.order);
  });
  return [for (final e in entries) e.locale];
}

/// `zh-TW`、`zh-Hant-TW`、`en` 這類 BCP 47 標籤 → [Locale]；不合格式回傳 `null`。
Locale? _localeFromTag(String tag) {
  final subtags = tag.split(RegExp('[-_]'));
  final language = subtags.first.toLowerCase();
  if (!RegExp(r'^[a-z]{2,3}$').hasMatch(language)) return null;
  String? script;
  String? country;
  for (final subtag in subtags.skip(1)) {
    if (subtag.length == 4 && RegExp(r'^[A-Za-z]{4}$').hasMatch(subtag)) {
      script ??= subtag[0].toUpperCase() + subtag.substring(1).toLowerCase();
    } else if (RegExp(r'^([A-Za-z]{2}|\d{3})$').hasMatch(subtag)) {
      country ??= subtag.toUpperCase();
    }
  }
  return Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: country,
  );
}

/// 網頁 `t(key)` 使用的字典。帶參數的訊息以 `{名稱}` 標記原樣保留給網頁端代入
/// （ARB 參數型別皆為 `String`，這裡傳入標記本身），因此 ARB 訊息不可使用 ICU
/// plural／select——英文改用不需要複數變化的句型（例如「Selected: {count}」）。
Map<String, String> wifiPageStrings(AppLocalizations l10n) => {
      'pageTitle': l10n.wifiPageTitle,
      'uploadHeading': l10n.wifiPageUploadHeading,
      'dropzoneText': l10n.wifiPageDropzoneText,
      'chooseFile': l10n.wifiPageChooseFile,
      'downloadHeading': l10n.wifiPageDownloadHeading,
      'searchPlaceholder': l10n.wifiPageSearchPlaceholder,
      'selectPage': l10n.wifiPageSelectPage,
      'clearSelection': l10n.wifiPageClearSelection,
      'selectedCount': l10n.wifiPageSelectedCount('{count}'),
      'loading': l10n.wifiPageLoading,
      'prevPage': l10n.wifiPagePrevPage,
      'nextPage': l10n.wifiPageNextPage,
      'pageInfo': l10n.wifiPagePageInfo('{page}', '{total}'),
      'downloadSelected': l10n.wifiPageDownloadSelected,
      'noBooks': l10n.wifiPageNoBooks,
      'noMatch': l10n.wifiPageNoMatch,
      'loadFailed': l10n.wifiPageLoadFailed,
      'totalBooks': l10n.wifiPageTotalBooks('{count}'),
      'matchStats': l10n.wifiPageMatchStats('{matched}', '{total}'),
      'selectAtLeastOne': l10n.wifiPageSelectAtLeastOne,
      'downloading': l10n.wifiPageDownloading,
      'downloadTriggered': l10n.wifiPageDownloadTriggered('{count}'),
      'outcomeImported': l10n.wifiPageOutcomeImported,
      'outcomeDuplicateSkipped': l10n.wifiPageOutcomeDuplicateSkipped,
      'outcomeUnsupportedFormat': l10n.wifiPageOutcomeUnsupportedFormat,
      'outcomeFailed': l10n.wifiPageOutcomeFailed,
      'uploadResultLine':
          l10n.wifiPageUploadResultLine('{name}', '{outcome}'),
      'unknownFileName': l10n.wifiPageUnknownFileName,
      'uploadPreparing': l10n.wifiPageUploadPreparing,
      'uploading': l10n.wifiPageUploading,
      'uploadingPercent': l10n.wifiPageUploadingPercent('{percent}'),
      'uploadProcessing': l10n.wifiPageUploadProcessing,
      'unknownSize': l10n.wifiPageUnknownSize,
      'uploadFailedServer': l10n.wifiPageUploadFailedServer('{status}'),
      'uploadFailedParse': l10n.wifiPageUploadFailedParse,
      'uploadFailedNetwork': l10n.wifiPageUploadFailedNetwork,
      'uploadAborted': l10n.wifiPageUploadAborted,
      'uploadTimeout': l10n.wifiPageUploadTimeout,
    };

/// 範本中的語言屬性佔位符（`<html lang="…">`）。
const String kWifiPageLangPlaceholder = '__WIFI_PAGE_LANG__';

/// 範本中字典 JSON 的佔位符（放在 `<script>` 內、指派給 `I18N`）。
const String kWifiPageI18nPlaceholder = '__WIFI_PAGE_I18N__';

/// 把 [template]（`assets/wifi_transfer/index.html` 原文）填入 [locale] 對應的
/// 語言屬性與字典。字典以 JSON 內嵌於 `<script>`，`<` 一律跳脫為 `<`，
/// 避免任何字串內容提早結束 `</script>`。
String renderWifiTransferPage(String template, Locale locale) {
  final l10n = lookupAppLocalizations(locale);
  final json = jsonEncode(wifiPageStrings(l10n)).replaceAll('<', r'<');
  return template
      .replaceAll(kWifiPageLangPlaceholder, wifiPageHtmlLang(locale))
      .replaceAll(kWifiPageI18nPlaceholder, json);
}

/// `<html lang>` 的值（正體／簡體以 script 區分，比照 HTML 慣例）。
String wifiPageHtmlLang(Locale locale) {
  if (locale.languageCode != 'zh') return locale.languageCode;
  return resolveSupportedLocale(locale) == AppLocale.zhCN ? 'zh-Hans' : 'zh-Hant';
}
