import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:elinkbook/reader/local_book_handler.dart';

void main() {
  group('createLocalBookHandler', () {
    const allowedOrigin = 'https://appassets.androidplatform.net';
    const expectedHost = '127.0.0.1:8080';
    late Directory tempDir;
    late File testFile;
    late Uint8List testBytes;
    late Completer<void> disposedCompleter;
    late Map<String, RegisteredBook> registry;
    late Handler handler;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('local_book_handler_test_');
      testBytes = Uint8List.fromList(List.generate(256, (i) => i));
      testFile = File('${tempDir.path}/test.epub');
      await testFile.writeAsBytes(testBytes, flush: true);

      disposedCompleter = Completer<void>();
      registry = {
        'token-123': RegisteredBook(
          filePath: testFile.path,
          fileName: 'current.epub',
          contentType: 'application/epub+zip',
          disposed: disposedCompleter.future,
        ),
      };

      handler = createLocalBookHandler(
        registry: registry,
        expectedHost: () => expectedHost,
        allowedOrigin: allowedOrigin,
      );
    });

    tearDown(() async {
      if (!disposedCompleter.isCompleted) {
        disposedCompleter.complete();
      }
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Request makeRequest({
      String method = 'GET',
      String path = '/book/token-123/current.epub',
      String host = expectedHost,
      Map<String, String>? headers,
    }) {
      return Request(
        method,
        Uri.parse('http://$host$path'),
        headers: {
          'host': host,
          ...?headers,
        },
      );
    }

    test('OPTIONS 預檢請求回傳 204 與完整 CORS / Private Network 標頭', () async {
      final req = makeRequest(method: 'OPTIONS');
      final res = await handler(req);

      expect(res.statusCode, 204);
      expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
      expect(res.headers['Access-Control-Allow-Methods'], 'GET, HEAD, OPTIONS');
      expect(res.headers['Access-Control-Allow-Headers'], 'Range');
      expect(res.headers['Access-Control-Allow-Private-Network'], 'true');
      expect(res.headers['Access-Control-Max-Age'], '86400');
      expect(res.headers['Vary'], 'Origin');
    });

    test('不支援的 HTTP 方法回傳 405 與 Allow 標頭與 CORS', () async {
      for (final m in ['POST', 'PUT', 'DELETE', 'PATCH']) {
        final req = makeRequest(method: m);
        final res = await handler(req);

        expect(res.statusCode, 405);
        expect(res.headers['Allow'], 'GET, HEAD, OPTIONS');
        expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
        expect(res.headers['Vary'], 'Origin');
      }
    });

    test('Host 不符時回傳 403 並帶 CORS', () async {
      final req = makeRequest(host: 'evil.com');
      final res = await handler(req);

      expect(res.statusCode, 403);
      expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
      expect(res.headers['Vary'], 'Origin');
    });

    test('未知權杖或檔名不符回傳 404 並帶 CORS', () async {
      final req1 = makeRequest(path: '/book/unknown-token/current.epub');
      final res1 = await handler(req1);
      expect(res1.statusCode, 404);
      expect(res1.headers['Access-Control-Allow-Origin'], allowedOrigin);

      final req2 = makeRequest(path: '/book/token-123/wrong.epub');
      final res2 = await handler(req2);
      expect(res2.statusCode, 404);
      expect(res2.headers['Access-Control-Allow-Origin'], allowedOrigin);

      final req3 = makeRequest(path: '/other/token-123/current.epub');
      final res3 = await handler(req3);
      expect(res3.statusCode, 404);
      expect(res3.headers['Access-Control-Allow-Origin'], allowedOrigin);
    });

    test('註冊之檔案不存在時回傳 404 並帶 CORS', () async {
      await testFile.delete();
      final req = makeRequest();
      final res = await handler(req);

      expect(res.statusCode, 404);
      expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
    });

    test('GET 無 Range 標頭回傳 200 與整檔內容串流', () async {
      final req = makeRequest();
      final res = await handler(req);

      expect(res.statusCode, 200);
      expect(res.headers['Accept-Ranges'], 'bytes');
      expect(res.headers['Content-Type'], 'application/epub+zip');
      expect(res.headers['Cache-Control'], 'no-store');
      expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
      expect(
        res.headers['Access-Control-Expose-Headers'],
        'Content-Length, Content-Range, Accept-Ranges',
      );
      expect(res.headers['Vary'], 'Origin');
      expect(res.contentLength, 256);

      final received = await res.read().expand((chunk) => chunk).toList();
      expect(received, testBytes);
    });

    test('GET 帶 Range 標頭回傳 206 與指定區段內容（含 0-0、檔尾單位元組、中間區段）', () async {
      // 0-0
      final res0 = await handler(makeRequest(headers: {'range': 'bytes=0-0'}));
      expect(res0.statusCode, 206);
      expect(res0.headers['Content-Range'], 'bytes 0-0/256');
      expect(res0.contentLength, 1);
      final bytes0 = await res0.read().expand((c) => c).toList();
      expect(bytes0, [testBytes[0]]);

      // 10-25
      final res10 = await handler(makeRequest(headers: {'range': 'bytes=10-25'}));
      expect(res10.statusCode, 206);
      expect(res10.headers['Content-Range'], 'bytes 10-25/256');
      expect(res10.contentLength, 16);
      final bytes10 = await res10.read().expand((c) => c).toList();
      expect(bytes10, testBytes.sublist(10, 26));

      // 檔尾單位元組 bytes=255-255
      final resEnd = await handler(makeRequest(headers: {'range': 'bytes=255-255'}));
      expect(resEnd.statusCode, 206);
      expect(resEnd.headers['Content-Range'], 'bytes 255-255/256');
      expect(resEnd.contentLength, 1);
      final bytesEnd = await resEnd.read().expand((c) => c).toList();
      expect(bytesEnd, [testBytes[255]]);

      // bytes=200-
      final resFrom = await handler(makeRequest(headers: {'range': 'bytes=200-'}));
      expect(resFrom.statusCode, 206);
      expect(resFrom.headers['Content-Range'], 'bytes 200-255/256');
      expect(resFrom.contentLength, 56);
      final bytesFrom = await resFrom.read().expand((c) => c).toList();
      expect(bytesFrom, testBytes.sublist(200));
    });

    test('GET 帶不可滿足的 Range 回傳 416 Content-Range: bytes */len', () async {
      final req = makeRequest(headers: {'range': 'bytes=300-400'});
      final res = await handler(req);

      expect(res.statusCode, 416);
      expect(res.headers['Content-Range'], 'bytes */256');
      expect(res.headers['Access-Control-Allow-Origin'], allowedOrigin);
      expect(res.headers['Vary'], 'Origin');
      final body = await res.read().expand((c) => c).toList();
      expect(body, isEmpty);
    });

    test('HEAD 請求具備所有相同標頭但不帶本文', () async {
      final req200 = makeRequest(method: 'HEAD');
      final res200 = await handler(req200);
      expect(res200.statusCode, 200);
      expect(res200.contentLength, 256);
      expect(res200.headers['Content-Type'], 'application/epub+zip');
      final body200 = await res200.read().expand((c) => c).toList();
      expect(body200, isEmpty);

      final req206 = makeRequest(method: 'HEAD', headers: {'range': 'bytes=10-19'});
      final res206 = await handler(req206);
      expect(res206.statusCode, 206);
      expect(res206.contentLength, 10);
      expect(res206.headers['Content-Range'], 'bytes 10-19/256');
      final body206 = await res206.read().expand((c) => c).toList();
      expect(body206, isEmpty);
    });

    test('disposed 完成時主動中止進行中的串流並釋放檔案', () async {
      // 建立稍大檔案以便觀察串流中途關閉
      final largeBytes = Uint8List(512 * 1024); // 512 KB
      final largeFile = File('${tempDir.path}/large.epub');
      await largeFile.writeAsBytes(largeBytes, flush: true);

      final streamDisposedCompleter = Completer<void>();
      registry['token-large'] = RegisteredBook(
        filePath: largeFile.path,
        fileName: 'current.epub',
        contentType: 'application/epub+zip',
        disposed: streamDisposedCompleter.future,
      );

      final req = makeRequest(path: '/book/token-large/current.epub');
      final res = await handler(req);
      expect(res.statusCode, 200);

      var chunksReceived = 0;
      final streamDone = Completer<void>();

      res.read().listen(
        (chunk) {
          chunksReceived++;
          if (chunksReceived == 1) {
            // 收到第一塊時觸發 disposed
            streamDisposedCompleter.complete();
          }
        },
        onDone: () {
          if (!streamDone.isCompleted) streamDone.complete();
        },
        onError: (e) {
          if (!streamDone.isCompleted) streamDone.complete();
        },
      );

      await streamDone.future.timeout(const Duration(seconds: 5));
      // 驗證串流被提前中止且檔案可立即刪除（檔案 handle 已釋放）
      expect(chunksReceived, greaterThanOrEqualTo(1));
      expect(largeFile.existsSync(), isTrue);
      // 在 Windows 若有開啟中的 handle，delete 會拋 FileSystemException
      expect(() => largeFile.deleteSync(), returnsNormally);
    });

    test('客戶端取消訂閱（斷線）時 cancel() 必須完成，且檔案 handle 釋放', () async {
      // 審查 Important 3：onCancel 內若自我等待 controller.close()，cancel() 會永不返回
      final largeFile = File('${tempDir.path}/cancel.epub');
      await largeFile.writeAsBytes(Uint8List(2 * 1024 * 1024), flush: true);
      registry['token-cancel'] = RegisteredBook(
        filePath: largeFile.path,
        fileName: 'current.epub',
        contentType: 'application/epub+zip',
        disposed: Completer<void>().future, // 永不完成：只走客戶端取消路徑
      );

      final res = await handler(makeRequest(path: '/book/token-cancel/current.epub'));
      final gotChunk = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = res.read().listen((_) {
        if (!gotChunk.isCompleted) gotChunk.complete();
      });
      await gotChunk.future.timeout(const Duration(seconds: 5));

      // 若 onCancel 自我等待，這裡會逾時
      await sub.cancel().timeout(const Duration(seconds: 3));

      expect(() => largeFile.deleteSync(), returnsNormally);
    });
  });
}
