import 'dart:async';

import 'package:elinkbook/reader/webview_font_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWebViewMajorVersion', () {
    test('取出主版本號', () {
      expect(parseWebViewMajorVersion('91.0.4472.114'), 91);
      expect(parseWebViewMajorVersion('154.0.8037.49'), 154);
    });

    test('只有主版本、前後有空白也能解析', () {
      expect(parseWebViewMajorVersion('107'), 107);
      expect(parseWebViewMajorVersion('  106.0.5249.126 '), 106);
    });

    test('null、空字串、非數字開頭 → null', () {
      expect(parseWebViewMajorVersion(null), isNull);
      expect(parseWebViewMajorVersion(''), isNull);
      expect(parseWebViewMajorVersion('   '), isNull);
      expect(parseWebViewMajorVersion('Chrome/91.0'), isNull);
      expect(parseWebViewMajorVersion('abc'), isNull);
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
    test('回傳平台版本字串的主版本號', () async {
      expect(await readWebViewMajorVersion(readVersionName: () async => '91.0.4472.114'), 91);
    });

    test('平台回傳 null → null', () async {
      expect(await readWebViewMajorVersion(readVersionName: () async => null), isNull);
    });

    test('平台呼叫拋例外（例如 MissingPluginException）→ null，不往外拋', () async {
      expect(
        await readWebViewMajorVersion(
            readVersionName: () async => throw MissingPluginException('no impl')),
        isNull,
      );
    });

    test('平台一直不回應 → 逾時後 null，不卡住啟動', () async {
      final never = Completer<String?>();
      expect(
        await readWebViewMajorVersion(
          readVersionName: () => never.future,
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });
}
