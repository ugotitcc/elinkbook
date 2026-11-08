// Android HeadlessInAppWebView foliate-js EPUB metadata 解析（epic-66 Issue 12 Task 2）。
//
// 使用 HeadlessInAppWebView 背景載入 foliate-js 的 metadata-probe.js 模組，
// 透過 shouldInterceptRequest 提供 foliate-js 靜態資源與書檔區段。

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../reader/foliate_bridge_handlers.dart';
import '../reader/foliate_native_bridge.dart';
import 'book_range_reader.dart';
import 'windows_epub_metadata.dart' show parseBookRange;

const _probeOrigin = 'https://foliate-metadata.local';

/// 探針頁面 HTML：以 readBookMetadataByRange 只抓需要的區段。[size] 是書檔位元組數。
String androidProbeHtml(int size) => '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>metadata-probe</title></head>
<body>
<script type="module">
import { readBookMetadataByRange } from '/assets/foliate/metadata-probe.js';
const send = (name, payload) => {
  try { window.flutter_inappwebview.callHandler(name, payload); }
  catch (e) { console.error('callHandler failed: ' + e); }
};
const fetchRange = async (start, end) => {
  const res = await fetch('/book/current.epub?start=' + start + '&end=' + end);
  if (!res.ok) throw new Error('range fetch ' + res.status);
  return await res.arrayBuffer();
};
try {
  const data = await readBookMetadataByRange($size, fetchRange, 'book.epub');
  send('metadataResult', JSON.stringify(data));
} catch (e) {
  send('metadataError', String((e && e.stack) || e));
}
</script>
</body>
</html>
''';

/// 解析探針回傳的 JSON 字串，轉換為詮釋資料 Map。
Map<String, Object?> mapProbeResult(String json) {
  final raw = jsonDecode(json) as Map<String, dynamic>;

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
}

/// 攔截 `/book/current.epub` 區段請求。
///
/// 讀取成功回傳 200 與資料；
/// 缺少 `start`／`end`、讀取回傳 `null`、讀取丟例外一律回傳 404（絕不回傳 `null`）。
Future<WebResourceResponse?> interceptBookRange(
  Uri url, {
  required Future<Uint8List?> Function(int start, int end) readRange,
}) async {
  final range = parseBookRange(url);
  if (range == null) {
    return WebResourceResponse(
      statusCode: 404,
      reasonPhrase: 'Not Found',
      headers: const {},
      data: Uint8List(0),
    );
  }

  try {
    final bytes = await readRange(range.start, range.end);
    if (bytes == null) {
      return WebResourceResponse(
        statusCode: 404,
        reasonPhrase: 'Not Found',
        headers: const {},
        data: Uint8List(0),
      );
    }
    return WebResourceResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      contentType: 'application/octet-stream',
      data: bytes,
    );
  } catch (e) {
    debugPrint('interceptBookRange 讀取失敗：$e');
    return WebResourceResponse(
      statusCode: 404,
      reasonPhrase: 'Not Found',
      headers: const {},
      data: Uint8List(0),
    );
  }
}

/// 在 Android HeadlessInAppWebView 內以 foliate-js 解析 [uri] 之 EPUB 詮釋資料。
///
/// 逾時拋出 [TimeoutException]，JavaScript 或檔案錯誤拋出 [StateError]。
/// 回傳 Map 鍵包含：`title`, `author`, `identifier`, `isFixedLayout`, `coverBytes`。
Future<Map<String, Object?>> readEpubMetadataOnAndroid(
  String uri, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final length = await bookLength(uri);
  if (length == null || length <= 0) {
    throw StateError('無法取得檔案長度或檔案為空：$uri');
  }

  final probeHtml = androidProbeHtml(length);
  final completer = Completer<String>();
  late final HeadlessInAppWebView headless;

  headless = HeadlessInAppWebView(
    initialSize: const Size(800, 1280),
    initialUrlRequest: URLRequest(
      url: WebUri('$_probeOrigin/probe.html'),
    ),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldInterceptRequest: true,
    ),
    initialUserScripts: UnmodifiableListView<UserScript>([
      UserScript(
        source: esCompatPolyfillJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: globalErrorCaptureJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
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
              StateError(
                'metadata-probe 失敗：${args.isNotEmpty ? args.first : "unknown error"}',
              ),
            );
          }
          return null;
        },
      );
      controller.addJavaScriptHandler(
        handlerName: FoliateBridgeHandlers.onError,
        callback: (args) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'foliate 腳本載入錯誤：${args.isNotEmpty ? args.first : "unknown error"}',
              ),
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
          data: Uint8List.fromList(utf8.encode(probeHtml)),
        );
      }

      const foliatePrefix = '/assets/foliate/';
      if (path.startsWith(foliatePrefix)) {
        final relative = 'foliate/${path.substring(foliatePrefix.length)}';
        final assetBytes = await loadAndroidAsset(relative);
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
        return await interceptBookRange(
          request.url,
          readRange: (start, end) => readBookRange(uri, start, end),
        );
      }

      return null;
    },
  );

  try {
    await headless.run();
    final resultJson = await completer.future.timeout(timeout);
    return mapProbeResult(resultJson);
  } finally {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await headless.dispose();
    } catch (_) {}
  }
}
