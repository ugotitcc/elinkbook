import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/windows/webview2_runtime_check.dart';

void main() {
  group('checkAndInitWebView2', () {
    test('探測回 "130.0.1" 且建立成功 → ready，version 為 "130.0.1"，createEnvironment 被呼叫 1 次', () async {
      var createCalls = 0;
      final result = await checkAndInitWebView2(
        probe: () async => '130.0.1',
        createEnvironment: () async {
          createCalls++;
        },
      );

      expect(result.status, WebView2CheckStatus.ready);
      expect(result.isReady, isTrue);
      expect(result.version, '130.0.1');
      expect(result.detail, isNull);
      expect(createCalls, 1);
    });

    test('探測回 null → missing，createEnvironment 從未被呼叫', () async {
      var createCalls = 0;
      final result = await checkAndInitWebView2(
        probe: () async => null,
        createEnvironment: () async {
          createCalls++;
        },
      );

      expect(result.status, WebView2CheckStatus.missing);
      expect(result.isReady, isFalse);
      expect(result.version, isNull);
      expect(result.detail, isNull);
      expect(createCalls, 0);
    });

    test('探測回空字串 "" → missing', () async {
      var createCalls = 0;
      final result = await checkAndInitWebView2(
        probe: () async => '',
        createEnvironment: () async {
          createCalls++;
        },
      );

      expect(result.status, WebView2CheckStatus.missing);
      expect(result.isReady, isFalse);
      expect(createCalls, 0);
    });

    test('探測回 "   "（只有空白）→ missing', () async {
      var createCalls = 0;
      final result = await checkAndInitWebView2(
        probe: () async => '   ',
        createEnvironment: () async {
          createCalls++;
        },
      );

      expect(result.status, WebView2CheckStatus.missing);
      expect(result.isReady, isFalse);
      expect(createCalls, 0);
    });

    test('探測丟例外 → failed，detail 含例外訊息，不向外丟', () async {
      var createCalls = 0;
      final result = await checkAndInitWebView2(
        probe: () async => throw Exception('probe broken'),
        createEnvironment: () async {
          createCalls++;
        },
      );

      expect(result.status, WebView2CheckStatus.failed);
      expect(result.isReady, isFalse);
      expect(result.detail, contains('probe broken'));
      expect(createCalls, 0);
    });

    test('探測成功但 createEnvironment 丟 StateError("boom") → failed，detail 含 "boom"', () async {
      final result = await checkAndInitWebView2(
        probe: () async => '130.0.1',
        createEnvironment: () async => throw StateError('boom'),
      );

      expect(result.status, WebView2CheckStatus.failed);
      expect(result.isReady, isFalse);
      expect(result.detail, contains('boom'));
    });

    test('createEnvironment 回傳永遠不完成的 Future，createTimeout 設 50ms → failed，detail 提到 timed out', () async {
      final completer = Completer<void>();
      final result = await checkAndInitWebView2(
        probe: () async => '130.0.1',
        createEnvironment: () => completer.future,
        createTimeout: const Duration(milliseconds: 50),
      );

      expect(result.status, WebView2CheckStatus.failed);
      expect(result.isReady, isFalse);
      expect(result.detail, contains('timed out'));
    });
  });

  group('WebView2CheckResult 等值性與字串表示（Ruling 7）', () {
    test('相同屬性的實例相等', () {
      expect(
        const WebView2CheckResult.ready('130.0.1'),
        equals(const WebView2CheckResult.ready('130.0.1')),
      );
      expect(
        const WebView2CheckResult.missing(),
        equals(const WebView2CheckResult.missing()),
      );
      expect(
        const WebView2CheckResult.failed('err'),
        equals(const WebView2CheckResult.failed('err')),
      );
      expect(
        const WebView2CheckResult.ready('130.0.1'),
        isNot(equals(const WebView2CheckResult.ready('130.0.2'))),
      );
      expect(
        const WebView2CheckResult.ready('130.0.1').toString(),
        contains('ready'),
      );
    });
  });
}
