import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_locale.dart';

void main() {
  group('AppLocale.locale', () {
    test('三個成員各自對應正確的 Locale', () {
      expect(AppLocale.zhTW.locale, const Locale('zh', 'TW'));
      expect(AppLocale.zhCN.locale, const Locale('zh', 'CN'));
      expect(AppLocale.en.locale, const Locale('en'));
    });
  });

  group('resolveSupportedLocale', () {
    test('zh_TW 直接對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'TW')), AppLocale.zhTW);
    });

    test('zh_HK／zh_MO 對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'HK')), AppLocale.zhTW);
      expect(resolveSupportedLocale(const Locale('zh', 'MO')), AppLocale.zhTW);
    });

    test('zh_Hant（無 country）對應正體中文', () {
      expect(
        resolveSupportedLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        AppLocale.zhTW,
      );
    });

    test('純 zh（無 script/country）對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh')), AppLocale.zhTW);
    });

    test('zh_CN 對應簡體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'CN')), AppLocale.zhCN);
    });

    test('zh_SG 對應簡體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'SG')), AppLocale.zhCN);
    });

    test('zh_Hans（無 country）對應簡體中文', () {
      expect(
        resolveSupportedLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')),
        AppLocale.zhCN,
      );
    });

    test('en／en_US 對應英文', () {
      expect(resolveSupportedLocale(const Locale('en')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'US')), AppLocale.en);
    });

    test('迴歸測試：en_SG／en_HK／en_TW 不得被地區碼誤判為中文（審查 C-1 修正）', () {
      expect(resolveSupportedLocale(const Locale('en', 'SG')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'HK')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'TW')), AppLocale.en);
    });

    test('未支援語言（例如法語）fallback 正體中文', () {
      expect(resolveSupportedLocale(const Locale('fr', 'FR')), AppLocale.zhTW);
    });
  });

  group('resolveMaterialAppLocale', () {
    test('清單第一個支援語言（zh 或 en）即採用', () {
      expect(
        resolveMaterialAppLocale(const [Locale('en', 'US')]),
        const Locale('en'),
      );
    });

    test('清單第一項不支援、第二項支援時，改採第二項（不可只看 firstOrNull）', () {
      expect(
        resolveMaterialAppLocale(const [Locale('fr', 'FR'), Locale('en', 'US')]),
        const Locale('en'),
      );
    });

    test('清單為 null 或全部不支援時 fallback 正體中文', () {
      expect(resolveMaterialAppLocale(null), const Locale('zh', 'TW'));
      expect(
        resolveMaterialAppLocale(const [Locale('fr', 'FR'), Locale('de', 'DE')]),
        const Locale('zh', 'TW'),
      );
    });
  });
}
