// 背景解析探針（epic-66 Issue 1 Task 10，過關條件 4）。
//
// 驗證 Windows 桌面能在 `HeadlessInAppWebView` 背景解析 EPUB 詮釋資料：
// 探針頁由攔截回呼從 Dart 字串提供，`<script type="module">` 從
// `/assets/foliate/view.js` 取 `makeBook`，開 `/book/current.epub`（由
// Task 6 的 `cacheWindowsBook` 複製 fixture、攔截回呼直接讀快取複本服務），
// 把 title／第一位作者／identifier／rendition.layout／封面 Blob 的 type
// 與 size 以 `callHandler` 傳回。四個欄位印成 JSON 供 Task 11 對比表使用。
//
// 執行：flutter test integration_test/windows_spike/headless_metadata_test.dart -d windows

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/windows_reader_resources.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

const _probeOrigin = 'https://foliate-probe.local';

const _probeHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>metadata-probe</title></head>
<body>
<script type="module">
import { makeBook } from '/assets/foliate/view.js';
const send = (name, payload) => {
  try { window.flutter_inappwebview.callHandler(name, payload); }
  catch (e) { console.error('callHandler failed: ' + e); }
};
try {
  const res = await fetch('/book/current.epub');
  if (!res.ok) throw new Error('book fetch ' + res.status);
  const file = new File([await res.blob()], '/book/current.epub');
  const book = await makeBook(file);
  const cover = await book.getCover();
  const creator = Array.isArray(book.metadata.creator)
      ? book.metadata.creator[0] : book.metadata.creator;
  send('probeResult', JSON.stringify({
    title: book.metadata.title ?? null,
    author: creator?.name ?? null,
    identifier: book.metadata.identifier ?? null,
    layout: book.rendition?.layout ?? null,
    coverType: cover ? cover.type : null,
    coverSize: cover ? cover.size : 0,
  }));
} catch (e) {
  send('probeError', String((e && e.stack) || e));
}
</script>
</body>
</html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HeadlessInAppWebView 背景解析 sample.epub 詮釋資料', (tester) async {
    await initAppWebViewEnvironment(
      userDataFolder: (await getApplicationSupportDirectory()).path,
    );

    // 用 Task 6 的 cacheWindowsBook 把 fixture 複製到暫存子目錄，
    // 攔截回呼再直接讀快取複本服務 /book/current.epub。
    final bytes = await rootBundle.load('test/fixtures/sample.epub');
    final tempDir = await getTemporaryDirectory();
    final staged = File(p.join(tempDir.path, 'spike_metadata_sample.epub'));
    await staged.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final cacheBase = Directory(p.join(tempDir.path, 'spike_metadata_cache'));
    final cachedPath = await cacheWindowsBook(
      staged.path,
      'spike-1',
      baseDir: cacheBase,
    );
    expect(cachedPath, isNotNull, reason: 'cacheWindowsBook 應複製成功');
    final bookDir = p.dirname(cachedPath!);
    addTearDown(() async {
      for (final f in [staged]) {
        if (await f.exists()) await f.delete();
      }
      if (await cacheBase.exists()) await cacheBase.delete(recursive: true);
    });

    final resultCompleter = Completer<String>();
    final loaded = Completer<void>();

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('$_probeOrigin/probe.html'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldInterceptRequest: true,
      ),
      webViewEnvironment: appWebViewEnvironment,
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'probeResult',
          callback: (args) {
            if (!resultCompleter.isCompleted && args.isNotEmpty) {
              resultCompleter.complete(args.first as String);
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'probeError',
          callback: (args) {
            if (!resultCompleter.isCompleted) {
              resultCompleter.complete('JS_ERROR: ${args.first}');
            }
            return null;
          },
        );
      },
      onConsoleMessage: (controller, consoleMessage) {
        // 診斷用：失敗時輸出 WebView console 訊息。
        // ignore: avoid_print
        print('[headless_metadata][console] ${consoleMessage.message}');
      },
      onLoadStop: (controller, url) {
        if (!loaded.isCompleted) loaded.complete();
      },
      shouldInterceptRequest: (controller, request) async {
        final url = request.url.toString();
        final path = request.url.path;
        if (url == '$_probeOrigin/probe.html') {
          return WebResourceResponse(
            contentType: 'text/html; charset=utf-8',
            data: Uint8List.fromList(utf8.encode(_probeHtml)),
          );
        }
        const foliatePrefix = '/assets/foliate/';
        if (path.startsWith(foliatePrefix)) {
          final relative = 'foliate/${path.substring(foliatePrefix.length)}';
          final assetBytes = await loadWindowsFoliateAsset(
            relative,
            assetRoot: windowsFoliateAssetRoot,
          );
          if (assetBytes == null) return null;
          final contentType =
              path.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/html';
          return WebResourceResponse(
            contentType: contentType,
            data: assetBytes,
          );
        }
        if (path == '/book/current.epub') {
          // 書檔直接讀 bookDir 內的快取複本（正式程式改走 loopback 伺服器，
          // 見 ADR 0042；`readWindowsBookBytes` 已隨 Issue 36 移除）。
          final bookBytes = await loadWindowsFileBytes(p.join(bookDir, 'current.epub'));
          if (bookBytes == null) return null;
          return WebResourceResponse(
            contentType: 'application/epub+zip',
            data: bookBytes,
          );
        }
        return null;
      },
    );
    addTearDown(() => headless.dispose());

    await headless.run();
    await loaded.future.timeout(const Duration(seconds: 30));
    final resultJson = await resultCompleter.future
        .timeout(const Duration(seconds: 60));

    expect(
      resultJson,
      isNot(startsWith('JS_ERROR:')),
      reason: '探針 JS 不應拋例外：$resultJson',
    );
    final result = jsonDecode(resultJson) as Map<String, dynamic>;

    // Task 10 Step 5 斷言。
    expect(result['title'], isNotNull, reason: 'sample.epub 有 dc:title');
    if (result['title'] is String) {
      expect(result['title'], isNotEmpty);
    }
    expect(result['identifier'], isNotNull, reason: 'sample.epub 有 dc:identifier');
    expect(result['identifier'].toString(), isNotEmpty);
    expect(
      result['coverSize'],
      greaterThan(0),
      reason: 'sample.epub 宣告 cover-image，封面 Blob 應有大小',
    );
    expect(result['coverType'], isNotNull);

    // 四個欄位印成 JSON，供 Task 11 做 Readium 對比表。
    // ignore: avoid_print
    print('[headless_metadata] $resultJson');
  });
}
