// Windows HeadlessInAppWebView EPUB metadata 解析（epic-66 Issue 2 Task 4）。
//
// 使用 WebView2 背景載入 foliate-js 的 metadata-probe.js 模組，
// 透過 HTTP 請求攔截服務本機 EPUB 檔案與 foliate-js 靜態資源。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../reader/foliate_native_bridge.dart';
import '../reader/windows_reader_resources.dart';
import '../windows/windows_webview_environment.dart';

const _probeOrigin = 'https://foliate-metadata.local';

const _probeHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>metadata-probe</title></head>
<body>
<script type="module">
import { readBookMetadata } from '/assets/foliate/metadata-probe.js';
const send = (name, payload) => {
  try { window.flutter_inappwebview.callHandler(name, payload); }
  catch (e) { console.error('callHandler failed: ' + e); }
};
try {
  const res = await fetch('/book/current.epub');
  if (!res.ok) throw new Error('book fetch ' + res.status);
  const file = new File([await res.blob()], '/book/current.epub');
  const data = await readBookMetadata(file);
  send('metadataResult', JSON.stringify(data));
} catch (e) {
  send('metadataError', String((e && e.stack) || e));
}
</script>
</body>
</html>
''';

/// 在 HeadlessInAppWebView 內以 foliate-js 解析 [epubPath] 之詮釋資料。
///
/// 逾時拋出 [TimeoutException]，JavaScript 或檔案錯誤拋出 [StateError]。
/// 回傳 Map 鍵包含：`title`, `author`, `identifier`, `isFixedLayout`, `coverBytes`。
Future<Map<String, Object?>> readEpubMetadataInWebView(
  String epubPath, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (!File(epubPath).existsSync()) {
    throw StateError('找不到檔案或檔案不存在：$epubPath');
  }

  final completer = Completer<String>();
  late final HeadlessInAppWebView headless;

  headless = HeadlessInAppWebView(
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
        handlerName: 'metadataResult',
        callback: (args) {
          if (!completer.isCompleted && args.isNotEmpty) {
            completer.complete(args.first as String);
          }
          return null;
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'metadataError',
        callback: (args) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('metadata-probe 失敗：${args.isNotEmpty ? args.first : "unknown error"}'),
            );
          }
          return null;
        },
      );
    },
    shouldInterceptRequest: (controller, request) async {
      final url = request.url.toString();
      final path = request.url.path;

      if (url == '$_probeOrigin/probe.html' || path == '/probe.html') {
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
        final contentType = path.endsWith('.js')
            ? 'text/javascript; charset=utf-8'
            : 'text/html';
        return WebResourceResponse(
          contentType: contentType,
          data: assetBytes,
        );
      }

      if (path == '/book/current.epub') {
        final bookBytes = await loadWindowsFileBytes(epubPath);
        if (bookBytes == null) return null;
        return WebResourceResponse(
          contentType: windowsBookContentType('current.epub'),
          data: bookBytes,
        );
      }

      return null;
    },
  );

  try {
    await headless.run();
    final resultJson = await completer.future.timeout(timeout);
    final raw = jsonDecode(resultJson) as Map<String, dynamic>;

    Uint8List? coverBytes;
    final coverBase64 = raw['coverBase64'] as String?;
    if (coverBase64 != null && coverBase64.isNotEmpty) {
      try {
        coverBytes = base64Decode(coverBase64);
      } catch (_) {
        coverBytes = null;
      }
    }

    return <String, Object?>{
      'title': raw['title'] as String?,
      'author': raw['author'] as String?,
      'identifier': raw['identifier'] as String?,
      'isFixedLayout': raw['isFixedLayout'] as bool? ?? false,
      'coverBytes': coverBytes,
    };
  } finally {
    try {
      // 等待 JavaScript callHandler 回應之 C++ evaluateJavascript 完成，
      // 避免 flutter_inappwebview_windows 在尚未回應時銷毀 native 物件導致崩潰。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await headless.dispose();
    } catch (_) {}
  }
}
