import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/windows/webview2_missing_screen.dart';
import 'package:elinkbook/windows/webview2_runtime_check.dart';

void main() {
  group('WebView2MissingApp', () {
    testWidgets('missing：顯示標題、下載按鈕、重新檢查按鈕、網址文字，不顯示錯誤摘要', (tester) async {
      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('webview2_missing_title')), findsOneWidget);
      expect(find.byKey(const Key('webview2_download_button')), findsOneWidget);
      expect(find.byKey(const Key('webview2_recheck_button')), findsOneWidget);
      expect(find.byKey(const Key('webview2_url_text')), findsOneWidget);
      expect(find.text(kWebView2DownloadUrl), findsOneWidget);

      expect(find.byKey(const Key('webview2_detail_text')), findsNothing);
      expect(find.byKey(const Key('webview2_still_missing_text')), findsNothing);
    });

    testWidgets('failed：額外顯示 Key webview2_detail_text，內容含 detail', (tester) async {
      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.failed('無法載入 DLL 0x80070002'),
          recheck: () async => const WebView2CheckResult.failed('無法載入 DLL 0x80070002'),
          onReady: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('webview2_missing_title')), findsOneWidget);
      expect(find.byKey(const Key('webview2_detail_text')), findsOneWidget);
      expect(find.textContaining('無法載入 DLL 0x80070002'), findsOneWidget);
    });

    testWidgets('點下載按鈕：openUrl 以 kWebView2DownloadUrl 被呼叫 1 次', (tester) async {
      Uri? openedUri;
      var openCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
          openUrl: (uri) async {
            openCalls++;
            openedUri = uri;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_download_button')));
      await tester.pumpAndSettle();

      expect(openCalls, 1);
      expect(openedUri, Uri.parse(kWebView2DownloadUrl));
    });

    testWidgets('openUrl 回傳 false：網址文字仍在畫面上，無例外', (tester) async {
      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
          openUrl: (uri) async => false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('webview2_url_text')), findsOneWidget);
      expect(find.text(kWebView2DownloadUrl), findsOneWidget);
    });

    testWidgets('openUrl 丟例外：同上，無未處理例外', (tester) async {
      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
          openUrl: (uri) async => throw Exception('OS launch failed'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('webview2_url_text')), findsOneWidget);
      expect(find.text(kWebView2DownloadUrl), findsOneWidget);
    });

    testWidgets('重新檢查回傳 ready：onReady 被呼叫 1 次', (tester) async {
      var onReadyCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.ready('130.0.1'),
          onReady: () => onReadyCalls++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pumpAndSettle();

      expect(onReadyCalls, 1);
    });

    testWidgets('重新檢查回傳 missing：onReady 未呼叫，出現 webview2_still_missing_text', (tester) async {
      var onReadyCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () => onReadyCalls++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pumpAndSettle();

      expect(onReadyCalls, 0);
      expect(find.byKey(const Key('webview2_still_missing_text')), findsOneWidget);
    });

    testWidgets('重新檢查進行中連按兩次：recheck 只被呼叫 1 次，成功後 onReady 只呼叫 1 次', (tester) async {
      final completer = Completer<WebView2CheckResult>();
      var recheckCalls = 0;
      var onReadyCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () {
            recheckCalls++;
            return completer.future;
          },
          onReady: () => onReadyCalls++,
        ),
      );
      await tester.pumpAndSettle();

      // 第一次點擊：進入 checking 狀態
      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pump();

      // 第二次點擊：應被防重入擋下
      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pump();

      expect(recheckCalls, 1);

      // 完成 recheck
      completer.complete(const WebView2CheckResult.ready('130.0.1'));
      await tester.pumpAndSettle();

      expect(onReadyCalls, 1);
    });

    testWidgets('recheck 成功並呼叫 onReady 之後，按鈕仍為停用，再按也不會呼叫第二次 onReady', (tester) async {
      var recheckCalls = 0;
      var onReadyCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async {
            recheckCalls++;
            return const WebView2CheckResult.ready('130.0.1');
          },
          onReady: () => onReadyCalls++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pumpAndSettle();

      expect(recheckCalls, 1);
      expect(onReadyCalls, 1);

      // 嘗試再次點擊
      final button = tester.widget<ElevatedButton>(find.byKey(const Key('webview2_recheck_button')));
      expect(button.onPressed, isNull, reason: '成功就緒後應保持停用，避免切換根樹前重複點擊');
    });

    testWidgets('recheck 丟例外：顯示失敗狀態與錯誤摘要，按鈕恢復可按', (tester) async {
      var onReadyCalls = 0;

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async {
            throw Exception('recheck socket error');
          },
          onReady: () => onReadyCalls++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('webview2_recheck_button')));
      await tester.pumpAndSettle();

      expect(onReadyCalls, 0);
      expect(find.byKey(const Key('webview2_detail_text')), findsOneWidget);
      expect(find.textContaining('recheck socket error'), findsOneWidget);

      // 按鈕應已恢復可點擊
      final button = tester.widget<ElevatedButton>(find.byKey(const Key('webview2_recheck_button')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('localeOverride 為 en：標題為英文；為 zh_TW：標題為「需要安裝 Microsoft Edge WebView2」', (tester) async {
      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
          localeOverride: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Microsoft Edge WebView2 Required'), findsOneWidget);

      await tester.pumpWidget(
        WebView2MissingApp(
          initialResult: const WebView2CheckResult.missing(),
          recheck: () async => const WebView2CheckResult.missing(),
          onReady: () {},
          localeOverride: const Locale('zh', 'TW'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('需要安裝 Microsoft Edge WebView2'), findsOneWidget);
    });
  });
}
