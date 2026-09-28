import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_http_server.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';

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

Future<_Resp> _realGet(String url, {Map<String, String> headers = const {}}) =>
    _sendRealRequest(url, openRequest: (client, uri) async {
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      return req;
    });

Future<_Resp> _realPost(String url) =>
    _sendRealRequest(url, openRequest: (client, uri) => client.postUrl(uri));

class _BytesResp {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  _BytesResp(this.statusCode, this.headers, this.bodyBytes);
}

Future<_BytesResp> _realGetBytes(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    final headers = <String, String>{};
    resp.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return _BytesResp(resp.statusCode, headers, bytes);
  } finally {
    client.close(force: true);
  }
}

Future<_Resp> _realMultipartUpload(
  String url,
  List<({String? filename, List<int> bytes})> files,
) async {
  final request = http.MultipartRequest('POST', Uri.parse(url));
  for (final file in files) {
    request.files.add(
      http.MultipartFile.fromBytes('files', file.bytes, filename: file.filename),
    );
  }
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  final headers = <String, String>{};
  response.headers.forEach((key, value) => headers[key] = value);
  return _Resp(response.statusCode, headers, response.body);
}

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
      expect(response.headers['vary'], 'Accept-Language');
      // 沒有 Accept-Language 時 fallback 正體中文（與 App 一致）。
      expect(response.body, contains('"pageTitle":"elinkBook WiFi 傳書"'));
      expect(response.body, contains('<html lang="zh-Hant">'));
    });

    test('GET /：依 Accept-Language 注入對應語言的字典與 <html lang>（Issue 10）',
        () async {
      final url = 'http://127.0.0.1:${httpServer.port}/';
      final en = await _realGet(url, headers: {'accept-language': 'en-US,en;q=0.9'});
      expect(en.body, contains('<html lang="en">'));
      expect(en.body, contains('"pageTitle":"elinkBook WiFi Transfer"'));
      expect(en.body, isNot(contains('WiFi 傳書')));

      final zhCn = await _realGet(url, headers: {'accept-language': 'zh-CN,zh;q=0.9'});
      expect(zhCn.body, contains('<html lang="zh-Hans">'));
      expect(zhCn.body, contains('"pageTitle":"elinkBook WiFi 传书"'));

      // 首選語言本 App 不支援時，依次要偏好（en）而非直接 fallback 正體中文。
      final fr = await _realGet(url, headers: {'accept-language': 'fr-FR,en;q=0.8'});
      expect(fr.body, contains('<html lang="en">'));

      // 佔位符必須全部被替換掉。
      for (final body in [en.body, zhCn.body, fr.body]) {
        expect(body, isNot(contains('__WIFI_PAGE_')));
      }
    });

    test('GET /：HTML 結構中 #upload-section 位於 #download-section 之前（Issue 4 佈局重排）',
        () async {
      final response = await _realGet('http://127.0.0.1:${httpServer.port}/');
      expect(response.statusCode, 200);
      final body = response.body;
      final uploadIndex = body.indexOf('id="upload-section"');
      final downloadIndex = body.indexOf('id="download-section"');
      expect(uploadIndex, greaterThan(-1));
      expect(downloadIndex, greaterThan(-1));
      expect(uploadIndex, lessThan(downloadIndex),
          reason: '上傳區塊應位於下載區塊之前，避免藏書量多時需一直下拉');
    });

    test('GET /：HTML 包含上傳狀態與雙階段進度元素（Issue 4 上傳體驗增強）', () async {
      final response = await _realGet('http://127.0.0.1:${httpServer.port}/');
      expect(response.statusCode, 200);
      final body = response.body;
      expect(body, contains('id="upload-status-text"'));
      expect(body, contains('id="upload-status-spinner"'));
      expect(body, contains('id="upload-bytes-text"'));
      expect(body, contains('formatBytesShort'));
    });

    test('GET /：HTML 包含書籍清單搜尋、分頁控制項與批次勾選工具列（Issue 4 下載體驗增強）',
        () async {
      final response = await _realGet('http://127.0.0.1:${httpServer.port}/');
      expect(response.statusCode, 200);
      final body = response.body;
      expect(body, contains('id="download-search-input"'));
      expect(body, contains('id="download-search-stats"'));
      expect(body, contains('id="download-select-page-button"'));
      expect(body, contains('id="download-clear-selection-button"'));
      expect(body, contains('id="download-selection-count"'));
      expect(body, contains('id="download-pagination"'));
      expect(body, contains('id="download-prev-page-button"'));
      expect(body, contains('id="download-next-page-button"'));
      expect(body, contains('id="download-page-info"'));
      expect(body, contains('const PAGE_SIZE = 20;'));
      expect(body, contains('new Set()'));
      expect(body, contains('toLowerCase()'));
    });

    test('GET /index.html 與 GET / 行為相同（M-3：容錯使用者手動輸入的網址）',
        () async {
      final response =
          await _realGet('http://127.0.0.1:${httpServer.port}/index.html');
      expect(response.statusCode, 200);
      expect(response.body, contains('"pageTitle":"elinkBook WiFi 傳書"'));
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

    test('GET /api/books/<id>/download：找不到書籍回傳 404', () async {
      final response = await _realGet(
          'http://127.0.0.1:${httpServer.port}/api/books/no-such-book/download');
      expect(response.statusCode, 404);
    });

    test('POST /api/upload：非 multipart 請求回傳 400', () async {
      final response =
          await _realPost('http://127.0.0.1:${httpServer.port}/api/upload');
      expect(response.statusCode, 400);
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

  group('GET /api/books/<id>/download', () {
    Book bookWith({
      required String id,
      required String filePath,
      String title = '書名',
      BookFileFormat format = BookFileFormat.epub,
    }) {
      final now = DateTime.fromMillisecondsSinceEpoch(0);
      return Book(
        id: id,
        title: title,
        format: format,
        filePath: filePath,
        source: BookSource.local,
        createTime: now,
        lastReadTime: now,
      );
    }

    test('本機路徑來源：回傳正確位元組、Content-Length 與 Content-Disposition',
        () async {
      final book = bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        title: '測試書',
        format: BookFileFormat.pdf,
      );
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      final expectedBytes = await File('test/fixtures/sample.pdf').readAsBytes();
      expect(response.statusCode, 200);
      expect(response.bodyBytes, expectedBytes);
      expect(response.headers['content-length'], '${expectedBytes.length}');
      expect(response.headers['content-disposition'],
          contains(buildContentDispositionHeader('測試書.pdf')));
    });

    test('content:// 來源：呼叫 materializeContentUri，下載完成後呼叫 deleteFile '
        '恰好一次', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/wifi_transfer_download_test_${DateTime.now().microsecondsSinceEpoch}.epub');
      await tempFile.writeAsBytes([1, 2, 3, 4, 5]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      final book = bookWith(
        id: 'b1',
        filePath: 'content://com.example/document/1',
        title: 'content 書',
      );
      final deleteCalls = <String>[];
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => tempFile.path,
          deleteFile: (path) async {
            deleteCalls.add(path);
            if (await File(path).exists()) await File(path).delete();
          },
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3, 4, 5]);
      expect(deleteCalls, [tempFile.path]);
    });

    test('resolveDownloadSource 回傳 null（材質化失敗）：回傳 404', () async {
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGet(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 404);
    });

    test(
        'resolveDownloadSource 成功後、file.length() 才拋出例外：仍會清理'
        '已材質化的 content:// 暫存檔並釋放許可（審查修正 I-3）', () async {
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final deleteCalls = <String>[];
      final nonexistentPath =
          '${Directory.systemTemp.path}/wifi_transfer_i3_test_${DateTime.now().microsecondsSinceEpoch}.epub';
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          // 回傳一個不存在的路徑，模擬材質化「回報成功」但緊接著
          // file.length() 讀取時才發現實際上失敗（例如檔案系統極短暫的
          // 競態）——重點是驗證 catch 區塊確實會嘗試清理這個路徑。
          materializeContentUri: (uri) async => nonexistentPath,
          deleteFile: (path) async {
            deleteCalls.add(path);
          },
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGet(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 500);
      expect(deleteCalls, [nonexistentPath]);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test(
        'deleteFile 清理暫存檔時拋出例外：不會成為未捕捉的非同步例外，'
        '許可仍正確釋放（審查修正 I-5）', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/wifi_transfer_i5_test_${DateTime.now().microsecondsSinceEpoch}.epub');
      await tempFile.writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => tempFile.path,
          deleteFile: (path) async => throw FileSystemException('模擬刪除失敗'),
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test(
        '下載期間 activeTransfersNotifier 維持在 1，直到用戶端讀完整個回應串流'
        '（許可涵蓋整個串流生命週期，非僅至 Response 建構完成——Task 3/7 的'
        '設計修正）', () async {
      // epic-51：原本下載 591 位元組的 test/fixtures/sample.pdf，整個檔案
      // 一次就塞進作業系統的 socket 緩衝區，伺服器在用戶端收到回應標頭前
      // 就已送完並釋放許可，本斷言因此必定失敗（伺服器行為本身正確）。改用
      // 產生的 16MB 檔案，遠大於 socket 緩衝區，確保用戶端還沒讀完時伺服器
      // 一定還在傳（實測 1MB 即可，留數倍餘裕給緩衝區較大的作業系統）。
      final bigFile = File(
          '${Directory.systemTemp.path}/wifi_transfer_download_permit_test.bin');
      await bigFile.writeAsBytes(List<int>.filled(16 * 1024 * 1024, 7));
      addTearDown(() async {
        if (await bigFile.exists()) await bigFile.delete();
      });
      final book = bookWith(id: 'b1', filePath: bigFile.path);
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
        maxConcurrentTransfers: 1,
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/api/books/b1/download'));
      final response = await request.close();

      expect(wifiServer.activeTransfersNotifier.value, 1,
          reason: '許可應持續持有，直到位元組真正傳輸完畢，而非 Response 建構'
              '完成的當下就釋放');

      await response.drain<void>();
      await Future<void>.delayed(Duration.zero);

      expect(wifiServer.activeTransfersNotifier.value, 0);
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

  group('bookFileFormatForFileName', () {
    test('支援的副檔名對應到正確的 BookFileFormat，且不分大小寫', () {
      expect(bookFileFormatForFileName('book.epub'), BookFileFormat.epub);
      expect(bookFileFormatForFileName('book.EPUB'), BookFileFormat.epub);
      expect(bookFileFormatForFileName('book.pdf'), BookFileFormat.pdf);
      expect(bookFileFormatForFileName('book.txt'), BookFileFormat.txt);
      expect(bookFileFormatForFileName('book.azw3'), BookFileFormat.azw3);
      expect(bookFileFormatForFileName('book.cbz'), BookFileFormat.cbz);
      expect(bookFileFormatForFileName('book.md'), BookFileFormat.md);
    });

    test('不在白名單內的副檔名回傳 null', () {
      expect(bookFileFormatForFileName('book.docx'), isNull);
      expect(bookFileFormatForFileName('book.zip'), isNull);
    });

    test('無副檔名或空字串回傳 null', () {
      expect(bookFileFormatForFileName('book'), isNull);
      expect(bookFileFormatForFileName(''), isNull);
    });
  });

  group('POST /api/upload', () {
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md C-1】
    // 本群組所有測試皆透過真實 HTTP 請求觸發 _landUpload()，其內部呼叫
    // path_provider 的 getApplicationDocumentsDirectory()——純 Dart
    // `flutter test` 環境沒有原生實作可回應，需替換 PathProviderPlatform
    // 為 FakePathProviderPlatform（比照 book_import_service_test.dart 等
    // 既有慣例），否則 100% 拋出 MissingPluginException。
    late Directory tempDocsDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      originalPathProvider = PathProviderPlatform.instance;
      tempDocsDir = Directory.systemTemp.createTempSync('wifi_upload_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDocsDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempDocsDir.existsSync()) {
        try {
          tempDocsDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('上傳一個支援格式的檔案：回傳 200、outcome 為 imported，落地檔案內容正確、'
        'displayNames 正確帶入原始檔名', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.epub,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '我的書.epub', bytes: [1, 2, 3, 4, 5])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results, hasLength(1));
      expect(results.single['originalFileName'], '我的書.epub');
      expect(results.single['outcome'], 'imported');
      final landedPath = importService.lastImportCall!.uris.single;
      addTearDown(() async {
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
      expect(await File(landedPath).readAsBytes(), [1, 2, 3, 4, 5]);
      expect(landedPath.endsWith('我的書.epub'), isTrue);
      expect(importService.lastImportCall!.displayNames, ['我的書.epub']);
    });

    test('上傳不支援格式的檔案：回傳 200、outcome 為 unsupportedFormat，未呼叫 '
        'importFiles', () async {
      final importService = FakeBookImportService();
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '文件.docx', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['originalFileName'], '文件.docx');
      expect(results.single['outcome'], 'unsupportedFormat');
      expect(importService.lastImportCall, isNull);
    });

    test('上傳的 part 缺少檔名：originalFileName 為 null（由網頁端依語言顯示），'
        'outcome 為 unsupportedFormat', () async {
      final importService = FakeBookImportService();
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: null, bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['originalFileName'], isNull);
      expect(results.single['outcome'], 'unsupportedFormat');
      expect(importService.lastImportCall, isNull);
    });

    test(
        '同一請求內第一個檔案格式不支援、第二個支援：不支援的那個不會卡住'
        '後續 part 的解析（M-2 驗證），第二個檔案正常匯入', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.pdf,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [
          (filename: '不支援.docx', bytes: List.filled(1024, 7)),
          (filename: '支援.pdf', bytes: [9, 9, 9]),
        ],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results, hasLength(2));
      expect(results[0]['outcome'], 'unsupportedFormat');
      expect(results[1]['outcome'], 'imported');
      addTearDown(() async {
        final landedPath = importService.lastImportCall!.uris.single;
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
    });

    test('內容指紋命中既有書籍：回傳 duplicateSkipped，落地暫存檔已被刪除',
        () async {
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'dup-fp';
      final existing = Book(
        id: 'existing',
        title: 'existing',
        format: BookFileFormat.epub,
        filePath: '/tmp/existing.epub',
        source: BookSource.local,
        contentFingerprint: 'dup-fp',
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final deleteCalls = <String>[];
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [existing]),
          importService: FakeBookImportService(),
          computeFingerprint: fingerprintComputer.call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async => deleteCalls.add(path),
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '重複的書.epub', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['outcome'], 'duplicateSkipped');
      expect(deleteCalls, hasLength(1));
      expect(deleteCalls.single.endsWith('重複的書.epub'), isTrue);
    });

    test('沒有任何檔案的合法 multipart 請求：回傳 200 與空陣列', () async {
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [],
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isEmpty);
    });

    test(
        '檔名含作業系統禁用字元（例如冒號）：仍能成功落地並匯入，不因'
        '非法檔名字元拋出 FileSystemException（`review-plan-issue-3.md` '
        'I-3 回歸測試）', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.epub,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '深入理解電腦系統：工程師觀點.epub', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['outcome'], 'imported');
      addTearDown(() async {
        final landedPath = importService.lastImportCall!.uris.single;
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
    });
  });
}
