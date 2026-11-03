// MDX WebView 安全邊界探針（epic-66 Issue 1 Task 10，過關條件 5）。
//
// 對應字典子系統的硬性要求（ADR 0038/0039、AGENTS.md「字典查詢」）：
// MDX 詞條頁 `javaScriptEnabled: false`、封鎖網路載入，`shouldInterceptRequest`
// 對所有請求回明確回應（外部一律 404），永不連網。本探針在 Windows 桌面
// 驗證這三件事：
//   1. 每個外部請求（example.com 的 CSS／圖片）都進了攔截回呼；
//   2. 回呼對所有外部請求回 404——沒有被放行的外部網址；
//   3. 頁面內嵌 `<script>` 沒有執行（標題不變），且 `<noscript>` 內容
//      因 JS 停用而被解析（其內的圖片請求有進回呼）。
//
// 探針頁本身由攔截回呼從 Dart 字串提供（200）——`flutter_inappwebview_windows`
// 0.6.0 未實作 `loadHtmlString`，故與 Task 10 Step 5 相同改走攔截回供。
//
// 執行：flutter test integration_test/windows_spike/mdx_network_block_test.dart -d windows

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/windows/windows_webview_environment.dart';

const _probeOrigin = 'https://mdx-probe.local';

const _probeHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>初始標題</title>
<link rel="stylesheet" href="https://example.com/a.css">
<script>document.title = 'script-ran';</script>
</head>
<body>
<noscript><img id="noscript-img" src="https://example.com/noscript.png" alt="ns"></noscript>
<img id="ext-img" src="https://example.com/x.png" alt="ext">
</body>
</html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('關 JS + 攔截全回 404：外部資源全被攔、內嵌腳本不執行', (tester) async {
    // Task 4 的 WebView2 環境（字典子系統在 Windows 也依賴同一機制）。
    await initAppWebViewEnvironment(
      userDataFolder: (await getApplicationSupportDirectory()).path,
    );

    final intercepted = <String>[];
    final served404 = <String>[];
    final loaded = Completer<void>();
    // 標題變化記錄：原生端 DocumentTitleChanged（in_app_webview.cpp:586）
    // 正確回傳 get_DocumentTitle。注意：Dart 端 getTitle() 在
    // flutter_inappwebview_windows 0.6.0 有缺陷——
    // webview_channel_delegate.cpp:91 的 getTitle 分支誤呼叫 getUrl()，
    // 回傳的是網址而非標題（探針實測發現，已記錄於 Task 10 ledger）。
    final titles = <String>[];

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('$_probeOrigin/index.html'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: false,
        useShouldInterceptRequest: true,
      ),
      webViewEnvironment: appWebViewEnvironment,
      onTitleChanged: (controller, title) {
        titles.add(title ?? '');
      },
      onLoadStop: (controller, url) {
        if (!loaded.isCompleted) loaded.complete();
      },
      shouldInterceptRequest: (controller, request) async {
        final url = request.url.toString();
        intercepted.add(url);
        // 探針頁本身（其餘探針域內請求一律 404）。
        if (url == '$_probeOrigin/index.html') {
          return WebResourceResponse(
            contentType: 'text/html; charset=utf-8',
            data: Uint8List.fromList(utf8.encode(_probeHtml)),
          );
        }
        // 其餘（含所有外部網址）一律明確回 404，永不連網。
        served404.add(url);
        return WebResourceResponse(
          statusCode: 404,
          reasonPhrase: 'Not Found',
          headers: const {},
          contentType: 'text/plain; charset=utf-8',
          data: Uint8List.fromList(utf8.encode('blocked')),
        );
      },
    );
    addTearDown(() => headless.dispose());

    await headless.run();
    await loaded.future.timeout(const Duration(seconds: 30));
    // 等樣式表與圖片等次資源完成請求（load 事件後再寬限）。
    await Future<void>.delayed(const Duration(seconds: 3));

    // 1. 每個外部請求都進了回呼。
    expect(intercepted, contains('https://example.com/a.css'));
    expect(intercepted, contains('https://example.com/x.png'));
    expect(
      intercepted,
      contains('https://example.com/noscript.png'),
      reason: 'JS 停用時 <noscript> 內容才會被解析並發出圖片請求',
    );

    // 2. 沒有被放行的外部網址——所有外部請求都收到 404 回應。
    final externalRequests =
        intercepted.where((u) => !u.startsWith(_probeOrigin)).toSet();
    expect(externalRequests, isNotEmpty);
    expect(
      externalRequests.every(served404.contains),
      isTrue,
      reason: '外部請求一律回 404，沒有被放行的外部網址',
    );

    // 3. 內嵌 <script> 沒有執行：標題維持「初始標題」（執行過會變成
    //    'script-ran'）。以 onTitleChanged 回呼讀取原生 DocumentTitle
    //    （不依賴頁面腳本；見上方 getTitle 缺陷說明）。
    expect(
      titles,
      isNot(contains('script-ran')),
      reason: 'javaScriptEnabled: false 時內嵌腳本不可執行，標題不可被改寫',
    );
    expect(
      titles,
      contains('初始標題'),
      reason: 'HTML <title> 已被解析（載入的是探針頁而非錯誤頁）',
    );
  });
}
