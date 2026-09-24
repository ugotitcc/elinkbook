import 'dart:io';

import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAcceptLanguage', () {
    test('null／空字串／全空白回傳空清單', () {
      expect(parseAcceptLanguage(null), isEmpty);
      expect(parseAcceptLanguage(''), isEmpty);
      expect(parseAcceptLanguage('  '), isEmpty);
    });

    test('依 q 值由高到低排序，同 q 保持原順序', () {
      final locales = parseAcceptLanguage('en;q=0.5, zh-TW, ja;q=0.9, zh-CN');
      expect(
        locales.map((l) => l.toLanguageTag()),
        ['zh-TW', 'zh-CN', 'ja', 'en'],
      );
    });

    test('q=0（明確拒絕）、萬用字元與格式錯誤的項目被略過', () {
      final locales = parseAcceptLanguage('zh-TW;q=0, *, 12-34, en;q=abc, ja');
      // en;q=abc 的 q 無法解析視為 0；只剩 ja。
      expect(locales.map((l) => l.toLanguageTag()), ['ja']);
    });

    test('解析 script 與 country，大小寫不敏感', () {
      final locale = parseAcceptLanguage('ZH-hant-tw').single;
      expect(locale.languageCode, 'zh');
      expect(locale.scriptCode, 'Hant');
      expect(locale.countryCode, 'TW');
    });
  });

  group('resolveWifiPageLocale', () {
    Locale resolve(String? header) => resolveWifiPageLocale(header);

    test('沒有標頭或無可用語言時 fallback 正體中文', () {
      expect(resolve(null), AppLocale.zhTW.locale);
      expect(resolve('fr-FR'), AppLocale.zhTW.locale);
    });

    test('對應矩陣與 App 一致（同一套 resolveMaterialAppLocale）', () {
      expect(resolve('en-US,en;q=0.9'), AppLocale.en.locale);
      expect(resolve('zh-TW'), AppLocale.zhTW.locale);
      expect(resolve('zh-HK'), AppLocale.zhTW.locale);
      expect(resolve('zh-CN'), AppLocale.zhCN.locale);
      expect(resolve('zh-Hans'), AppLocale.zhCN.locale);
      expect(resolve('zh-Hant'), AppLocale.zhTW.locale);
    });

    test('首選不支援時採用次要偏好', () {
      expect(resolve('fr-FR,en;q=0.8'), AppLocale.en.locale);
    });
  });

  group('wifiPageHtmlLang', () {
    test('正體／簡體以 script 區分，英文只回語言碼', () {
      expect(wifiPageHtmlLang(AppLocale.zhTW.locale), 'zh-Hant');
      expect(wifiPageHtmlLang(AppLocale.zhCN.locale), 'zh-Hans');
      expect(wifiPageHtmlLang(AppLocale.en.locale), 'en');
    });
  });

  group('wifiPageStrings', () {
    for (final appLocale in AppLocale.values) {
      test('${appLocale.name}：所有字串非空，且參數標記原樣保留給網頁端代入', () {
        final strings = wifiPageStrings(lookupAppLocalizations(appLocale.locale));
        for (final entry in strings.entries) {
          expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        }
        expect(strings['selectedCount'], contains('{count}'));
        expect(strings['pageInfo'], allOf(contains('{page}'), contains('{total}')));
        expect(strings['totalBooks'], contains('{count}'));
        expect(strings['matchStats'], allOf(contains('{matched}'), contains('{total}')));
        expect(strings['downloadTriggered'], contains('{count}'));
        expect(strings['uploadResultLine'], allOf(contains('{name}'), contains('{outcome}')));
        expect(strings['uploadingPercent'], contains('{percent}'));
        expect(strings['uploadFailedServer'], contains('{status}'));
      });
    }

    test('三個語言的鍵完全一致', () {
      final keySets = [
        for (final l in AppLocale.values)
          wifiPageStrings(lookupAppLocalizations(l.locale)).keys.toSet(),
      ];
      expect(keySets[1], keySets[0]);
      expect(keySets[2], keySets[0]);
    });
  });

  group('index.html 與字典的一致性', () {
    // flutter test 的工作目錄是 app/。
    final html = File('assets/wifi_transfer/index.html').readAsStringSync();
    final dictionaryKeys =
        wifiPageStrings(lookupAppLocalizations(AppLocale.en.locale)).keys.toSet();

    Set<String> usedKeys() => {
          for (final m in RegExp(r'''\bt\(\s*['"](\w+)['"]''').allMatches(html))
            m.group(1)!,
          for (final m in RegExp(r'data-i18n(?:-placeholder)?="(\w+)"')
              .allMatches(html))
            m.group(1)!,
        };

    test('頁面用到的每個鍵都存在於字典（避免執行期 undefined）', () {
      expect(usedKeys().difference(dictionaryKeys), isEmpty);
    });

    test('字典的每個鍵都被頁面使用（避免留下死字串）', () {
      expect(dictionaryKeys.difference(usedKeys()), isEmpty);
    });

    test('範本含兩個佔位符各一處，且不含任何中文字面值（註解除外）', () {
      expect(kWifiPageLangPlaceholder.allMatches(html).length, 1);
      expect(kWifiPageI18nPlaceholder.allMatches(html).length, 1);
      final withoutComments = html
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
      final cjk = RegExp(r'[㐀-鿿＀-￯]');
      final offending = withoutComments
          .split('\n')
          .where((line) => cjk.hasMatch(line.replaceFirst(RegExp(r'\s//.*$'), '')))
          .toList();
      expect(offending, isEmpty, reason: '網頁文案一律走 t()／data-i18n');
    });

    test('renderWifiTransferPage：佔位符全部替換，字典為合法內嵌 JSON', () {
      for (final appLocale in AppLocale.values) {
        final rendered = renderWifiTransferPage(html, appLocale.locale);
        expect(rendered, isNot(contains('__WIFI_PAGE_')));
        expect(rendered, contains('<html lang="${wifiPageHtmlLang(appLocale.locale)}">'));
      }
    });
  });
}
