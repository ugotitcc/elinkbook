import 'dart:async';

import 'package:elinkbook/reader/webview_font_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('parseChromeMajorVersion', () {
    test('從 WebView 的 User-Agent 取出 Chrome 主版本號', () {
      expect(
        parseChromeMajorVersion(
            'Mozilla/5.0 (Linux; Android 11; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'),
        91,
      );
      expect(parseChromeMajorVersion('... Chrome/154.0.8037.49 Mobile Safari/537.36'), 154);
    });

    test('廠商 WebView 的套件版本編號不影響判斷：只看 UA 裡的 Chrome/NN（審查 I-1）', () {
      // 例如 com.huawei.webview 的 versionName 可能是 12.x，但核心是 Chromium 99
      expect(
        parseChromeMajorVersion(
            'Mozilla/5.0 (Linux; Android 10; XYZ; HMSCore 6.0; wv) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Version/4.0 Chrome/99.0.4844.88 HuaweiBrowser/12.1.0 '
            'Mobile Safari/537.36'),
        99,
      );
    });

    test('null、空字串、沒有 Chrome/NN → null', () {
      expect(parseChromeMajorVersion(null), isNull);
      expect(parseChromeMajorVersion(''), isNull);
      expect(parseChromeMajorVersion('91.0.4472.114'), isNull);
      expect(parseChromeMajorVersion('Mozilla/5.0 (Linux; Android 11) Chrome/ Mobile'), isNull);
    });
  });

  group('webViewCanLoadFont', () {
    const sans = 36034016; // 思源黑體
    const serif = 59898316; // 思源宋體

    test('WebView 106 以前：超過 30MB 的字型載不動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: sans), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: serif), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 106, fontSizeBytes: sans), isFalse);
    });

    test('WebView 107 起：128MB 以內都載得動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 107, fontSizeBytes: sans), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: serif), isTrue);
    });

    test('剛好等於上限可以載入，多 1 byte 就不行（Chromium 用「大於」判斷）', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 31457280), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 31457281), isFalse);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: 134217728), isTrue);
      expect(webViewCanLoadFont(webViewMajorVersion: 154, fontSizeBytes: 134217729), isFalse);
    });

    test('小於 30MB 的字型在舊 WebView 也載得動', () {
      expect(webViewCanLoadFont(webViewMajorVersion: 91, fontSizeBytes: 21704488), isTrue);
    });

    test('讀不到版本（null）→ 視同支援，行為和現在一樣', () {
      expect(webViewCanLoadFont(webViewMajorVersion: null, fontSizeBytes: serif), isTrue);
    });
  });

  group('readWebViewMajorVersion', () {
    test('回傳平台 User-Agent 裡的 Chrome 主版本號', () async {
      expect(await readWebViewMajorVersion(readUserAgent: () async => 'Mozilla/5.0 (Linux; Android 11; wv) Chrome/91.0.4472.114 Mobile'), 91);
    });

    test('平台回傳沒有 Chrome/NN 的 User-Agent → null', () async {
      expect(await readWebViewMajorVersion(readUserAgent: () async => 'Mozilla/5.0'), isNull);
    });

    test('平台呼叫拋例外（例如 MissingPluginException）→ null，不往外拋', () async {
      expect(
        await readWebViewMajorVersion(
            readUserAgent: () async => throw MissingPluginException('no impl')),
        isNull,
      );
    });

    test('平台一直不回應 → 逾時後 null，不卡住啟動', () async {
      final never = Completer<String?>();
      expect(
        await readWebViewMajorVersion(
          readUserAgent: () => never.future,
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });

  group('readWebViewMajorVersionWithCache（Issue 8 真機發現）', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('讀到版本 → 回傳並記住', () async {
      expect(await readWebViewMajorVersionWithCache(readFresh: () async => 91), 91);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kWebViewMajorVersionPrefsKey), 91);
    });

    test('讀不到版本（例如剛安裝完第一次開，逾時）→ 改用上次記住的值', () async {
      SharedPreferences.setMockInitialValues({kWebViewMajorVersionPrefsKey: 91});
      expect(await readWebViewMajorVersionWithCache(readFresh: () async => null), 91);
    });

    test('讀不到版本，也沒有記住的值 → null（視同支援，Issue 7 決定 2）', () async {
      expect(await readWebViewMajorVersionWithCache(readFresh: () async => null), isNull);
    });

    test('WebView 升級後讀到新版本 → 蓋掉舊值', () async {
      SharedPreferences.setMockInitialValues({kWebViewMajorVersionPrefsKey: 91});
      expect(await readWebViewMajorVersionWithCache(readFresh: () async => 154), 154);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kWebViewMajorVersionPrefsKey), 154);
    });
  });
}
