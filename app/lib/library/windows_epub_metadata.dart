// Windows HeadlessInAppWebView EPUB metadata 解析（epic-66 Issue 2 Task 4）。
//
// 使用 WebView2 背景載入 foliate-js 的 metadata-probe.js 模組，
// 透過 HTTP 請求攔截服務 foliate-js 靜態資源，以及 EPUB 檔案「被要求的區段」。
//
// 為什麼只傳區段、不傳整本書：被 shouldInterceptRequest 回傳的大資料，會在 App 程序留下
// 約兩份資料大小的原生記憶體且不釋放（量大小與傳輸位元組成正比；224 MB 的書每解析一次
// 私有記憶體多約 450 MB），尖峰也高達數 GB。metadata 只需要 ZIP 中央目錄、OPF 與封面，
// 所以探針頁用 readBookMetadataByRange 只抓這幾段（見 metadata-probe.js、
// reviews/review-issue-2.md、issue-2-report.md）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../reader/foliate_native_bridge.dart';
import '../reader/windows_reader_resources.dart';
import '../windows/windows_webview_environment.dart';

const _probeOrigin = 'https://foliate-metadata.local';

/// 單次區段請求的位元組上限。JS 端以 256 KB 為區塊讀取，這個上限遠大於區塊，
/// 只用來擋掉「一次要走整本書」的請求。
const int kMaxBookRangeBytes = 4 * 1024 * 1024;

/// 探針頁面：以 readBookMetadataByRange 只抓需要的區段。[size] 是書檔位元組數。
String _probeHtml(int size) => '''
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

/// 書檔區段請求的範圍：[start, end)，單位位元組。
class BookRange {
  const BookRange(this.start, this.end);
  final int start;
  final int end;
}

/// 從攔截到的網址解析 `start`／`end` 查詢參數；缺少或不是整數回 `null`。
BookRange? parseBookRange(Uri uri) {
  final start = int.tryParse(uri.queryParameters['start'] ?? '');
  final end = int.tryParse(uri.queryParameters['end'] ?? '');
  if (start == null || end == null) return null;
  return BookRange(start, end);
}

/// 讀取 [path] 的 [start, end) 位元組，不把整個檔案載入記憶體。
///
/// 回傳 `null`：檔案不存在、[start] 為負或不小於檔案長度、[end] 不大於 [start]、
/// 或範圍超過 [kMaxBookRangeBytes]。[end] 超過檔案長度時夾回檔案結尾。
Future<Uint8List?> readFileRange(String path, int start, int end) async {
  if (start < 0 || end <= start || end - start > kMaxBookRangeBytes) return null;
  final file = File(path);
  RandomAccessFile? raf;
  try {
    if (!await file.exists()) return null;
    raf = await file.open();
    final length = await raf.length();
    if (start >= length) return null;
    final clampedEnd = end > length ? length : end;
    await raf.setPosition(start);
    return await raf.read(clampedEnd - start);
  } on FileSystemException {
    return null;
  } finally {
    await raf?.close();
  }
}

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

  final fileSize = File(epubPath).lengthSync();
  final probeHtml = _probeHtml(fileSize);

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
          data: Uint8List.fromList(utf8.encode(probeHtml)),
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
        // 只回應被要求的區段；沒有 start／end 就不回應，絕不整本回傳。
        final range = parseBookRange(request.url);
        if (range == null) return null;
        final bytes = await readFileRange(epubPath, range.start, range.end);
        if (bytes == null) return null;
        return WebResourceResponse(
          contentType: 'application/octet-stream',
          data: bytes,
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
