import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
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

    test('GET /api/books 回傳 JSON 陣列，欄位對應正確且僅列出 isDownloaded 書籍',
        () async {
      final now = DateTime.fromMillisecondsSinceEpoch(0);
      final downloaded = Book(
        id: 'b1',
        title: '已下載的書',
        format: BookFileFormat.epub,
        filePath: 'content://com.example/document/1',
        source: BookSource.local,
        createTime: now,
        lastReadTime: now,
      );
      final notDownloaded = Book(
        id: 'b2',
        title: '未下載的書',
        format: BookFileFormat.pdf,
        filePath: 'content://com.example/document/2',
        source: BookSource.local,
        isDownloaded: false,
        createTime: now,
        lastReadTime: now,
      );
      final serverWithBooks = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(
            initialBooks: [downloaded, notDownloaded],
          ),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final serverWithBooksHttp =
          await serverWithBooks.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => serverWithBooks.stop(serverWithBooksHttp));

      final response = await _realGet(
          'http://127.0.0.1:${serverWithBooksHttp.port}/api/books');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      expect(response.headers['cache-control'], 'no-cache');
      final payload = jsonDecode(response.body) as List<dynamic>;
      expect(payload, hasLength(1));
      final entry = payload.single as Map<String, dynamic>;
      expect(entry['id'], 'b1');
      expect(entry['title'], '已下載的書');
      expect(entry['format'], 'epub');
      expect(entry['sizeBytes'], isNull);
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

  group('wrapStreamWithCleanup', () {
    test('來源串流正常 EOF（onDone）：資料原樣轉發，onFinished 恰好被呼叫一次',
        () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final received = <int>[];
      final done = Completer<void>();
      wrapped.listen(
        received.addAll,
        onDone: () => done.complete(),
      );

      source
        ..add([1, 2, 3])
        ..add([4, 5]);
      await source.close();
      await done.future;
      // 【`/receiving-code-review` 審查修正 I-1】onFinished 改為等待
      // controller.done（真正送達下游）才呼叫，與下游自己的 onDone 回呼
      // 是兩個獨立的 Future 鏈，給一次事件迴圈機會讓前者的延續完成。
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2, 3, 4, 5]);
      expect(finishedCount, 1);
    });

    test('來源串流拋出讀取例外（onError）：例外會轉發給下游，onFinished 恰好被呼叫一次',
        () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final errors = <Object>[];
      final done = Completer<void>();
      wrapped.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) => errors.add(error),
        onDone: () => done.complete(),
      );

      source.addError(StateError('讀取失敗'));
      await done.future;
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(finishedCount, 1);
    });

    test('下游訂閱被 cancel()（模擬客戶端中途取消下載/斷線）：等待內部訂閱真正'
        '取消完成後，onFinished 才恰好被呼叫一次', () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final subscription = wrapped.listen((_) {});
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      // 【`/receiving-code-review` 審查修正 I-2】onCancel 內部須先
      // await 對 source 的訂閱真正取消完成，才呼叫 onFinished；本測試
      // 的 subscription.cancel() 回傳的 Future 須等到那個內部 await
      // 也完成才 resolve（不能提早釋放，實務上對應「檔案控制代碼真正
      // 關閉後才刪除暫存檔」）。
      await subscription.cancel();

      expect(finishedCount, 1);
      expect(source.hasListener, isFalse,
          reason: '下游取消後，內部應已完成對來源 StreamController 的取消訂閱');
    });

    test('onFinished 只會被呼叫一次，即使 onDone 之後下游又被取消', () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final done = Completer<void>();
      final subscription = wrapped.listen((_) {}, onDone: () => done.complete());
      await source.close();
      await done.future;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(finishedCount, 1);
    });

    test(
        '下游暫停訂閱（onPause）時，內部對來源的訂閱也會暫停——不會在慢速'
        '消費時無視背壓持續灌入資料（審查修正 I-1 的背壓轉發驗證）',
        () async {
      final source = StreamController<List<int>>();
      final wrapped = wrapStreamWithCleanup(source.stream, () async {});

      final received = <int>[];
      final subscription = wrapped.listen(received.addAll);
      subscription.pause();
      await Future<void>.delayed(Duration.zero);

      // `source.isPaused` 反映的是「它自己內部訂閱」（也就是本函式對
      // source 建立的那個 subscription）目前是否被暫停——若 onPause 有
      // 正確轉發，這裡應為 true，證明下游的暫停訊號確實傳到了上游。
      expect(source.isPaused, isTrue,
          reason: '下游暫停應轉發至內部對 source 的訂閱（背壓正確傳遞）');
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty,
          reason: '下游暫停期間，資料不應被送達（背壓已正確轉發至來源）');

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(received, [1, 2, 3]);

      await subscription.cancel();
    });
  });

  group('buildContentDispositionHeader', () {
    test('純 ASCII 檔名：fallback 與 filename* 皆為原始檔名', () {
      final header = buildContentDispositionHeader('book.epub');
      expect(header,
          "attachment; filename=\"book.epub\"; filename*=UTF-8''book.epub");
    });

    test('中文檔名：fallback 以底線替代非 ASCII 字元，filename* 為 percent-encoded '
        '原始檔名（同時支援中文書名正確顯示）', () {
      final header = buildContentDispositionHeader('書名.epub');
      expect(
        header,
        "attachment; filename=\"__.epub\"; "
        "filename*=UTF-8''%E6%9B%B8%E5%90%8D.epub",
      );
    });

    test('檔名含雙引號與反斜線：fallback 以底線替代，避免破壞 quoted-string 語法',
        () {
      final header = buildContentDispositionHeader('a"b\\c.epub');
      expect(header, contains('filename="a_b_c.epub"'));
    });

    test(
        '檔名含 CRLF（模擬惡意書名中繼資料嘗試 HTTP header injection）：'
        'fallback 與 filename* 皆不含原始的 \\r／\\n 位元組', () {
      final malicious = 'evil\r\nSet-Cookie: x=1.epub';
      final header = buildContentDispositionHeader(malicious);

      expect(header.contains('\r'), isFalse);
      expect(header.contains('\n'), isFalse);
    });

    test(
        '檔名含單引號（`/receiving-code-review` 審查修正 M-1）：filename* '
        '中的單引號額外跳脫為 %27，不與 UTF-8\'\' 語法本身的分隔符混淆',
        () {
      final header = buildContentDispositionHeader("John's Book.epub");
      expect(header, contains("filename*=UTF-8''John%27s%20Book.epub"));
      expect(
        header.substring(header.indexOf("filename*=UTF-8''") + 18),
        isNot(contains("'")),
      );
    });

    test('空字串輸入：fallback 退回單一底線，不產生空的 quoted-string', () {
      final header = buildContentDispositionHeader('');
      expect(header, contains('filename="_"'));
    });
  });
}
