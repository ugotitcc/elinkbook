import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/local_book_server.dart';

void main() {
  group('LocalBookServer', () {
    late Directory tempDir;
    late File sampleFile;
    late Uint8List sampleBytes;
    late LocalBookServer server;
    late HttpClient client;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('local_book_server_test_');
      sampleBytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      sampleFile = File('${tempDir.path}/sample.epub');
      await sampleFile.writeAsBytes(sampleBytes, flush: true);

      server = LocalBookServer();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('第一次 register 惰性啟動：綁定 loopback 位址且埠號非 0', () async {
      expect(server.address, isNull);
      expect(server.port, isNull);

      final handle = await server.register(sampleFile.path);
      addTearDown(handle.dispose);

      expect(server.address, isNotNull);
      expect(server.address!.isLoopback, isTrue);
      expect(server.port, isNotNull);
      expect(server.port, greaterThan(0));
      expect(handle.bookBaseUri.host, '127.0.0.1');
      expect(handle.bookBaseUri.port, server.port);
      expect(handle.bookBaseUri.path, endsWith('/'));
    });

    test('透過 HttpClient 讀取整檔、Range 區段、與尾端 bytes=-N，內容與原檔一致', () async {
      final handle = await server.register(sampleFile.path);
      addTearDown(handle.dispose);

      final fileUri = handle.bookBaseUri.resolve(handle.fileName);

      // 1. 整檔
      final reqFull = await client.getUrl(fileUri);
      reqFull.persistentConnection = false;
      final resFull = await reqFull.close();
      expect(resFull.statusCode, 200);
      final bodyFull = await resFull.expand((chunk) => chunk).toList();
      expect(bodyFull, sampleBytes);

      // 2. Range: bytes=100-199
      final reqRange = await client.getUrl(fileUri);
      reqRange.persistentConnection = false;
      reqRange.headers.set('Range', 'bytes=100-199');
      final resRange = await reqRange.close();
      expect(resRange.statusCode, 206);
      expect(resRange.headers.value('Content-Range'), 'bytes 100-199/1024');
      final bodyRange = await resRange.expand((c) => c).toList();
      expect(bodyRange, sampleBytes.sublist(100, 200));

      // 3. Range: bytes=-300 (尾端 300 位元組)
      final reqSuffix = await client.getUrl(fileUri);
      reqSuffix.persistentConnection = false;
      reqSuffix.headers.set('Range', 'bytes=-300');
      final resSuffix = await reqSuffix.close();
      expect(resSuffix.statusCode, 206);
      expect(resSuffix.headers.value('Content-Range'), 'bytes 724-1023/1024');
      final bodySuffix = await resSuffix.expand((c) => c).toList();
      expect(bodySuffix, sampleBytes.sublist(724));
    });

    test('dispose 後同網址回傳 404，其他已註冊權杖不受影響', () async {
      final handle1 = await server.register(sampleFile.path);
      final handle2 = await server.register(sampleFile.path);
      addTearDown(handle2.dispose);

      final uri1 = handle1.bookBaseUri.resolve(handle1.fileName);
      final uri2 = handle2.bookBaseUri.resolve(handle2.fileName);

      // 釋放 handle1
      handle1.dispose();

      // uri1 應回傳 404
      final req1 = await client.getUrl(uri1);
      req1.persistentConnection = false;
      final res1 = await req1.close();
      expect(res1.statusCode, 404);
      await res1.drain();

      // uri2 應照常回傳 200
      final req2 = await client.getUrl(uri2);
      req2.persistentConnection = false;
      final res2 = await req2.close();
      expect(res2.statusCode, 200);
      await res2.drain();
    });

    test('串流中途 dispose 主動中止串流並釋放檔案 handle，檔案可成功刪除', () async {
      final largeBytes = Uint8List(2 * 1024 * 1024); // 2 MB
      final largeFile = File('${tempDir.path}/large_stream.epub');
      await largeFile.writeAsBytes(largeBytes, flush: true);

      final handle = await server.register(largeFile.path);
      final uri = handle.bookBaseUri.resolve(handle.fileName);

      final req = await client.getUrl(uri);
      req.persistentConnection = false;
      final res = await req.close();
      expect(res.statusCode, 200);

      var chunks = 0;
      final streamFinished = Completer<void>();

      res.listen(
        (chunk) {
          chunks++;
          if (chunks == 1) {
            // 讀取第一塊後立即 dispose
            handle.dispose();
          }
        },
        onDone: () {
          if (!streamFinished.isCompleted) streamFinished.complete();
        },
        onError: (_) {
          if (!streamFinished.isCompleted) streamFinished.complete();
        },
        cancelOnError: true,
      );

      await streamFinished.future.timeout(const Duration(seconds: 5));
      expect(chunks, greaterThanOrEqualTo(1));

      // Windows 上若檔案 handle 未被釋放，delete 會拋 PathAccessException
      expect(() => largeFile.deleteSync(), returnsNormally);
    });

    test('客戶端中途斷線：檔案 handle 釋放、檔案可刪除，伺服器仍可服務新請求', () async {
      // 審查 Important 3 的重現測試：客戶端（WebView）讀一部分後強制關閉連線，
      // 驗證 onCancel 路徑不會自我等待而懸掛
      final largeFile = File('${tempDir.path}/client_abort.epub');
      await largeFile.writeAsBytes(Uint8List(20 * 1024 * 1024), flush: true);

      final handle = await server.register(largeFile.path);
      addTearDown(handle.dispose);
      final uri = handle.bookBaseUri.resolve(handle.fileName);

      final abortClient = HttpClient();
      final req = await abortClient.getUrl(uri);
      final res = await req.close();
      expect(res.statusCode, 200);

      final gotFirstChunk = Completer<void>();
      res.listen(
        (_) {
          if (!gotFirstChunk.isCompleted) gotFirstChunk.complete();
        },
        onError: (_) {},
        cancelOnError: true,
      );
      await gotFirstChunk.future.timeout(const Duration(seconds: 5));

      // 客戶端強制斷線（等同 WebView 關閉分頁或 fetch abort）
      abortClient.close(force: true);

      // 給伺服端一點時間處理斷線，再確認檔案 handle 已釋放
      var deleted = false;
      for (var i = 0; i < 50 && !deleted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          largeFile.deleteSync();
          deleted = true;
        } on FileSystemException {
          // handle 尚未釋放，繼續等
        }
      }
      expect(deleted, isTrue, reason: '客戶端斷線後檔案 handle 應被釋放');

      // 伺服器仍可服務其他書籍的新請求
      final h2 = await server.register(sampleFile.path);
      addTearDown(h2.dispose);
      final req2 = await client.getUrl(h2.bookBaseUri.resolve(h2.fileName));
      req2.persistentConnection = false;
      final res2 = await req2.close().timeout(const Duration(seconds: 5));
      expect(res2.statusCode, 200);
      final body = await res2.expand((c) => c).toList();
      expect(body, sampleBytes);
    });

    test('啟動失敗（埠綁定例外）不永久快取失敗，修復後再次 register 可成功', () async {
      // 審查 Important 2：先佔住一個埠，再讓伺服器綁定同一埠使其失敗
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(blocker.close);

      final failing = LocalBookServer(
        bindAddress: InternetAddress.loopbackIPv4,
        port: blocker.port,
      );
      addTearDown(failing.close);

      await expectLater(failing.register(sampleFile.path), throwsA(anything));

      // 釋放埠後重試，應可成功啟動
      await blocker.close();
      final handle = await failing.register(sampleFile.path);
      addTearDown(handle.dispose);
      expect(failing.port, blocker.port);
    });

    test('同一檔案連續註冊兩次得到不同權杖與基底網址', () async {
      final h1 = await server.register(sampleFile.path);
      final h2 = await server.register(sampleFile.path);
      addTearDown(h1.dispose);
      addTearDown(h2.dispose);

      expect(h1.bookBaseUri, isNot(equals(h2.bookBaseUri)));
    });

    test('權杖具備至少 128 位元亂數熵，連續註冊 1000 次無重複', () async {
      final tokens = <String>{};
      final handles = <BookServeHandle>[];

      for (var i = 0; i < 1000; i++) {
        final h = await server.register(sampleFile.path);
        handles.add(h);
        final segments = h.bookBaseUri.pathSegments;
        // /book/<token>/
        final token = segments.where((s) => s.isNotEmpty).last;
        // 至少 128 位元（以 URL-safe base64 編碼至少 22 字元，hex 至少 32 字元）
        expect(token.length, greaterThanOrEqualTo(22));
        // URL-safe 字元集合檢查
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token), isTrue);
        tokens.add(token);
      }

      for (final h in handles) {
        h.dispose();
      }

      expect(tokens.length, 1000);
    });

    test('錯誤 Host 標頭回傳 403', () async {
      final handle = await server.register(sampleFile.path);
      addTearDown(handle.dispose);

      final uri = handle.bookBaseUri.resolve(handle.fileName);
      final req = await client.getUrl(uri);
      req.persistentConnection = false;
      // 手動覆寫 Host
      req.headers.set('Host', 'spoofed.local:1234');
      final res = await req.close();

      expect(res.statusCode, 403);
      await res.drain();
    });

    test('close 後連線被拒，再次 register 會重啟並可服務', () async {
      final h1 = await server.register(sampleFile.path);
      final uri1 = h1.bookBaseUri.resolve(h1.fileName);

      await server.close();

      // 連線至舊埠應拋出 SocketException
      expect(
        () async {
          final reqOld = await client.getUrl(uri1);
          reqOld.persistentConnection = false;
          await reqOld.close();
        },
        throwsA(isA<SocketException>()),
      );

      // 再次 register 會自動重啟
      final h2 = await server.register(sampleFile.path);
      addTearDown(h2.dispose);
      final uri2 = h2.bookBaseUri.resolve(h2.fileName);

      final reqNew = await client.getUrl(uri2);
      reqNew.persistentConnection = false;
      final resNew = await reqNew.close();
      expect(resNew.statusCode, 200);
      await resNew.drain();
    });

    test('並行 register 只會綁定一次 socket 埠號', () async {
      final futures = List.generate(10, (_) => server.register(sampleFile.path));
      final handles = await Future.wait(futures);

      for (final h in handles) {
        addTearDown(h.dispose);
        expect(h.bookBaseUri.port, server.port);
      }
    });
  });

  // epic-66 Issue 11：`--dart-define=LOCAL_BOOK_SERVER_BIND` 的解析。
  // 只接受 IPv4 loopback，其餘一律退回 127.0.0.1，避免把書檔服務暴露到區網。
  group('bindAddressFromDefine', () {
    test("'127.0.0.2' 回傳該位址", () {
      final address = LocalBookServer.bindAddressFromDefine('127.0.0.2');
      expect(address.address, '127.0.0.2');
    });

    for (final value in ['', 'abc', '0.0.0.0', '192.168.1.5', '::1']) {
      test("'$value' 退回 127.0.0.1 且不拋例外", () {
        final address = LocalBookServer.bindAddressFromDefine(value);
        expect(address, InternetAddress.loopbackIPv4);
      });
    }
  });
}
