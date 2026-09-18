import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_http_server.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

class _Resp {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  _Resp(this.statusCode, this.headers, this.body);
}

Future<_Resp> _sendRealRequest(
  String url, {
  required Future<HttpClientRequest> Function(HttpClient client, Uri uri)
      openRequest,
}) async {
  final client = HttpClient();
  try {
    final req = await openRequest(client, Uri.parse(url));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final headers = <String, String>{};
    resp.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return _Resp(resp.statusCode, headers, body);
  } finally {
    client.close(force: true);
  }
}

Future<_Resp> _realGet(String url) =>
    _sendRealRequest(url, openRequest: (client, uri) => client.getUrl(uri));

Future<_Resp> _realPost(String url) =>
    _sendRealRequest(url, openRequest: (client, uri) => client.postUrl(uri));

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  WifiTransferService buildService() {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  group('WifiTransferHttpServer 路由', () {
    late WifiTransferHttpServer wifiServer;
    late HttpServer httpServer;

    setUp(() async {
      wifiServer = WifiTransferHttpServer(service: buildService());
      httpServer = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
    });

    tearDown(() => wifiServer.stop(httpServer));

    test('start() 綁定成功並回傳實際監聽的埠號', () {
      expect(httpServer.port, greaterThan(0));
    });

    test('GET / 回傳 index.html 內容與正確 Content-Type／Cache-Control', () async {
      final response = await _realGet('http://127.0.0.1:${httpServer.port}/');
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.body, contains('elinkBook WiFi 傳書'));
    });

    test('GET /index.html 與 GET / 行為相同（M-3：容錯使用者手動輸入的網址）',
        () async {
      final response =
          await _realGet('http://127.0.0.1:${httpServer.port}/index.html');
      expect(response.statusCode, 200);
      expect(response.body, contains('elinkBook WiFi 傳書'));
    });

    test('GET /api/books 回傳 501（留給 Issue 2 實作）', () async {
      final response =
          await _realGet('http://127.0.0.1:${httpServer.port}/api/books');
      expect(response.statusCode, 501);
    });

    test('GET /api/books/<id>/download 回傳 501（留給 Issue 2 實作）', () async {
      final response = await _realGet(
          'http://127.0.0.1:${httpServer.port}/api/books/abc123/download');
      expect(response.statusCode, 501);
    });

    test('POST /api/upload 回傳 501（留給 Issue 3 實作）', () async {
      final response =
          await _realPost('http://127.0.0.1:${httpServer.port}/api/upload');
      expect(response.statusCode, 501);
    });

    test('未知路徑回傳 404', () async {
      final response =
          await _realGet('http://127.0.0.1:${httpServer.port}/unknown');
      expect(response.statusCode, 404);
    });

    test('stop() 後伺服器確實關閉，後續連線失敗', () async {
      final port = httpServer.port;
      await wifiServer.stop(httpServer);
      await expectLater(
        _realGet('http://127.0.0.1:$port/'),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('WifiTransferHttpServer.withTransferPermit 併發節流', () {
    test('超過 maxConcurrentTransfers 時第三個呼叫會等待，直到有一個釋放', () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 2,
      );
      final release1 = Completer<void>();
      final release2 = Completer<void>();
      var thirdStarted = false;

      final task1 = wifiServer.withTransferPermit(() async {
        await release1.future;
        return 1;
      });
      final task2 = wifiServer.withTransferPermit(() async {
        await release2.future;
        return 2;
      });
      expect(wifiServer.activeTransfersNotifier.value, 2);

      final task3 = wifiServer.withTransferPermit(() async {
        thirdStarted = true;
        return 3;
      });
      expect(thirdStarted, isFalse, reason: '許可已滿，第三個應該還在等待');

      release1.complete();
      final result3 = await task3;
      expect(result3, 3);
      expect(thirdStarted, isTrue);

      release2.complete();
      await Future.wait([task1, task2]);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test('action 拋出例外時仍會釋放許可（finally），不會卡死後續請求', () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 1,
      );

      await expectLater(
        wifiServer.withTransferPermit(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(wifiServer.activeTransfersNotifier.value, 0);

      final result = await wifiServer.withTransferPermit(() async => 'ok');
      expect(result, 'ok');
    });

    test('stop() 時會讓仍在排隊等許可的呼叫以例外結束，不會永久卡住（M-4）',
        () async {
      final wifiServer = WifiTransferHttpServer(
        service: buildService(),
        maxConcurrentTransfers: 1,
      );
      final holdFirst = Completer<void>();

      final task1 = wifiServer.withTransferPermit(() async {
        await holdFirst.future;
        return 1;
      });
      // 許可已滿（1/1），第二個呼叫進入 _waitQueue 排隊。
      // 先掛上錯誤處理，避免在 stop() 完成前被視為未處理的異常。
      final task2 = wifiServer.withTransferPermit(() async => 2);
      final task2Expectation = expectLater(task2, throwsA(isA<StateError>()));
      expect(wifiServer.activeTransfersNotifier.value, 1);

      final httpServer =
          await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      await wifiServer.stop(httpServer);

      await task2Expectation;

      holdFirst.complete();
      expect(await task1, 1);
    });
  });
}
