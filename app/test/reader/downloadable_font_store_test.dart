import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import 'package:elinkbook/reader/font_download_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// 測試用的假字型內容：100,000 bytes，內容固定，方便計算雜湊。
final List<int> fontBytesA = List<int>.generate(100000, (i) => i % 251);
final List<int> fontBytesB = List<int>.generate(50000, (i) => (i * 7) % 253);

FontDownloadSpec specFor(String path, List<int> bytes) => FontDownloadSpec(
      publishPath: path,
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

/// 思源黑體對應 v1/A.ttf、思源宋體對應 v1/B.ttf，讓兩款字型的檔案互不干擾。
final specA = specFor('v1/A.ttf', fontBytesA);
final specB = specFor('v1/B.ttf', fontBytesB);
FontDownloadSpec testSpecOf(AppFont font) =>
    font == AppFont.sourceHanSans ? specA : specB;

/// 把 [bytes] 切成每塊 [chunkSize] bytes 的串流。
Stream<List<int>> chunked(List<int> bytes, {int chunkSize = 1000}) async* {
  for (var i = 0; i < bytes.length; i += chunkSize) {
    yield bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
  }
}

/// 依請求路徑回傳對應內容的 MockClient；[served] 沒有的路徑回 404。
http.Client serving(
  Map<String, List<int>> served, {
  int chunkSize = 1000,
  int? Function(List<int> bytes)? contentLengthOf,
}) {
  return MockClient.streaming((request, _) async {
    final bytes = served[request.url.path];
    if (bytes == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      chunked(bytes, chunkSize: chunkSize),
      200,
      contentLength: contentLengthOf == null ? bytes.length : contentLengthOf(bytes),
    );
  });
}

/// 斷言 download 以指定原因的 FontDownloadException 失敗。
Matcher failsWith(FontDownloadFailure reason, {int? statusCode}) => throwsA(
      isA<FontDownloadException>()
          .having((e) => e.reason, 'reason', reason)
          .having((e) => e.statusCode, 'statusCode', statusCode),
    );

void main() {
  late Directory root;
  late Directory fontsDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('downloadable_font_store_test');
    fontsDir = Directory(p.join(root.path, 'downloaded-fonts'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DownloadableFontStore storeWith(http.Client client,
          {Duration idleTimeout = const Duration(seconds: 30)}) =>
      DownloadableFontStore(
        httpClient: client,
        directory: fontsDir,
        baseUri: Uri.parse('https://fonts.test/'),
        specOf: testSpecOf,
        idleTimeout: idleTimeout,
      );

  /// 存放目錄底下所有檔案的相對路徑（用 / 分隔），方便斷言「沒有留下任何檔案」。
  Future<List<String>> filesIn(Directory dir) async {
    if (!await dir.exists()) return [];
    return dir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => p.relative(e.path, from: dir.path).replaceAll(r'\', '/'))
        .toList();
  }

  File fileFor(String publishPath) =>
      File(p.joinAll([fontsDir.path, ...publishPath.split('/')]));

  group('download 成功', () {
    test('下載後正式檔案內容正確、列為已下載，且請求的網址是基底網址加發布路徑', () async {
      Uri? requested;
      final client = MockClient.streaming((request, _) async {
        requested = request.url;
        return http.StreamedResponse(chunked(fontBytesA), 200,
            contentLength: fontBytesA.length);
      });
      final store = storeWith(client);
      await store.prepare();

      await store.download(AppFont.sourceHanSans);

      expect(requested.toString(), 'https://fonts.test/v1/A.ttf');
      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });

    test('存放目錄尚未建立時也能下載（download 會自行建立子目錄）', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await store.download(AppFont.sourceHanSans);

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('重新下載成功會取代既有檔案（Windows 上 rename 不能覆蓋既有檔案）', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await fileFor('v1/A.ttf').writeAsBytes([9, 9, 9]);
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await store.download(AppFont.sourceHanSans);

      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });
  });

  group('download 失敗', () {
    test('SHA-256 不符 → integrity，且沒有留下任何檔案', () async {
      final corrupted = List<int>.from(fontBytesA)..[0] ^= 0xff;
      final store = storeWith(serving({'/v1/A.ttf': corrupted}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.integrity));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('HTTP 404 → httpStatus，附狀態碼', () async {
      final store = storeWith(serving({}));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.httpStatus, statusCode: 404));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('HTTP 500 → httpStatus，附狀態碼', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => http.StreamedResponse(const Stream.empty(), 500)));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.httpStatus, statusCode: 500));
    });

    test('連線失敗（ClientException）→ network', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => throw http.ClientException('offline')));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.network));
    });

    test('連線失敗（SocketException）→ network', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => throw const SocketException('no route')));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.network));
    });

    test('無法建立暫存檔（存放目錄下的 v1 被一個檔案佔住）→ storage', () async {
      await fontsDir.create(recursive: true);
      await File(p.join(fontsDir.path, 'v1')).writeAsBytes([0]);
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.storage));
    });

    test('已下載時重新下載失敗，不影響既有的正式檔案', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await fileFor('v1/A.ttf').writeAsBytes(fontBytesA);
      final corrupted = List<int>.from(fontBytesA)..[0] ^= 0xff;
      final store = storeWith(serving({'/v1/A.ttf': corrupted}));

      await expectLater(
          store.download(AppFont.sourceHanSans), failsWith(FontDownloadFailure.integrity));
      expect(await fileFor('v1/A.ttf').readAsBytes(), fontBytesA);
      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });

    test('失敗後可以再下載（內部的「下載中」狀態有被重設）', () async {
      var attempts = 0;
      final store = storeWith(MockClient.streaming((request, _) async {
        attempts++;
        if (attempts == 1) throw http.ClientException('offline');
        return http.StreamedResponse(chunked(fontBytesA), 200,
            contentLength: fontBytesA.length);
      }));

      await expectLater(
          store.download(AppFont.sourceHanSans), throwsA(isA<FontDownloadException>()));
      await store.download(AppFont.sourceHanSans);

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });
  });

  group('installedFonts／delete／prepare', () {
    test('installedFonts 只看正式檔案是否存在，.part 不算', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await File('${fileFor('v1/B.ttf').path}.part').create(recursive: true);
      final store = storeWith(serving({}));

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('delete 後不再列為已下載；刪除不存在的檔案不拋錯', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      final store = storeWith(serving({}));

      await store.delete(AppFont.sourceHanSans);
      await store.delete(AppFont.sourceHanSerif);

      expect(await store.installedFonts(), isEmpty);
    });

    test('prepare 會建立不存在的存放目錄', () async {
      final store = storeWith(serving({}));

      await store.prepare();

      expect(await fontsDir.exists(), isTrue);
      expect(store.directory, fontsDir.path);
    });

    test('prepare 會刪除殘留的 .part 檔，保留正式檔案', () async {
      await fileFor('v1/A.ttf').create(recursive: true);
      await File('${fileFor('v1/A.ttf').path}.part').create(recursive: true);
      await File('${fileFor('v1/B.ttf').path}.part').create(recursive: true);
      final store = storeWith(serving({}));

      await store.prepare();

      expect(await filesIn(fontsDir), ['v1/A.ttf']);
    });
  });

  group('進度、取消、重疊下載、中途斷線', () {
    test('大量小區塊時，進度回呼不超過 101 次、嚴格遞增、最後是 100', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}, chunkSize: 10));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported.length, lessThanOrEqualTo(101));
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThan(reported[i - 1]));
      }
      expect(reported.last, 100);
    });

    test('伺服器沒回傳 Content-Length 時，用字型目錄中的大小計算進度', () async {
      final store = storeWith(
          serving({'/v1/A.ttf': fontBytesA}, contentLengthOf: (_) => null));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported, contains(50));
      expect(reported.last, 100);
    });

    test('Content-Length 比實際小時，進度不超過 100 且嚴格遞增，下載仍以雜湊判定成功', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA},
          contentLengthOf: (bytes) => bytes.length ~/ 2));
      final reported = <int>[];

      await store.download(AppFont.sourceHanSans, onProgress: reported.add);

      expect(reported.every((percent) => percent <= 100), isTrue);
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThan(reported[i - 1]));
      }
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('取消 → cancelled，且沒有留下任何檔案', () async {
      final store = storeWith(serving({'/v1/A.ttf': fontBytesA}));
      final token = FontDownloadCancellationToken();

      await expectLater(
        store.download(AppFont.sourceHanSans,
            cancellationToken: token,
            onProgress: (percent) {
              if (percent >= 10) token.cancel();
            }),
        throwsA(isA<FontDownloadException>()
            .having((e) => e.reason, 'reason', FontDownloadFailure.cancelled)),
      );
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('串流中途斷線 → network，且沒有留下任何檔案', () async {
      Stream<List<int>> brokenStream() async* {
        yield fontBytesA.sublist(0, 30000);
        throw http.ClientException('connection reset');
      }
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(brokenStream(), 200, contentLength: fontBytesA.length)));

      await expectLater(
        store.download(AppFont.sourceHanSans),
        throwsA(isA<FontDownloadException>()
            .having((e) => e.reason, 'reason', FontDownloadFailure.network)),
      );
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('下載進行中再呼叫 download 拋出 StateError，進行中那一筆照常完成', () async {
      // 每次請求都給新的串流：如果拿掉重疊防護，第二次呼叫會真的送出請求，
      // 而不是因為「串流已被訂閱」這個同樣是 StateError 的錯誤碰巧通過（程式審查 M-1）
      final controllers = <StreamController<List<int>>>[];
      final firstRequestArrived = Completer<void>();
      final store = storeWith(MockClient.streaming((request, _) async {
        final controller = StreamController<List<int>>();
        controllers.add(controller);
        if (!firstRequestArrived.isCompleted) firstRequestArrived.complete();
        return http.StreamedResponse(controller.stream, 200, contentLength: fontBytesA.length);
      }));

      final first = store.download(AppFont.sourceHanSans);
      await expectLater(
        store.download(AppFont.sourceHanSerif),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('已有字型下載進行中'))),
      );
      await firstRequestArrived.future;
      await pumpEventQueue();
      expect(controllers, hasLength(1));

      controllers.single.add(fontBytesA);
      await controllers.single.close();
      await first;

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });
  });

  group('例外轉換、閒置逾時、立即取消（程式審查 I-1、I-2、M-6）', () {
    test('送出請求時 TLS 握手失敗（HandshakeException）→ network', () async {
      final store = storeWith(MockClient.streaming(
          (request, _) async => throw const HandshakeException('bad certificate')));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.network));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('串流途中出現 TlsException → network，且沒有留下任何檔案', () async {
      Stream<List<int>> brokenStream() async* {
        yield fontBytesA.sublist(0, 30000);
        throw const TlsException('connection closed');
      }
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(brokenStream(), 200, contentLength: fontBytesA.length)));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.network));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('伺服器一直不回應 → 閒置逾時後 network，之後可以再下載', () async {
      var attempts = 0;
      final store = storeWith(
        MockClient.streaming((request, _) async {
          attempts++;
          if (attempts == 1) return Completer<http.StreamedResponse>().future;
          return http.StreamedResponse(chunked(fontBytesA), 200, contentLength: fontBytesA.length);
        }),
        idleTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.network));
      await store.download(AppFont.sourceHanSans);

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('收到部分資料後連線停住 → 閒置逾時後 network，沒有留下任何檔案，之後可以再下載', () async {
      var attempts = 0;
      final store = storeWith(
        MockClient.streaming((request, _) async {
          attempts++;
          if (attempts == 1) {
            final stalled = StreamController<List<int>>()..add(fontBytesA.sublist(0, 30000));
            return http.StreamedResponse(stalled.stream, 200, contentLength: fontBytesA.length);
          }
          return http.StreamedResponse(chunked(fontBytesA), 200, contentLength: fontBytesA.length);
        }),
        idleTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.network));
      expect(await filesIn(fontsDir), isEmpty);

      await store.download(AppFont.sourceHanSans);
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('連線停住時按取消 → 立即 cancelled（不必等下一個資料區塊），沒有留下任何檔案', () async {
      final stalled = StreamController<List<int>>();
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(stalled.stream, 200, contentLength: fontBytesA.length)));
      final token = FontDownloadCancellationToken();
      final firstProgress = Completer<void>();

      final download = store.download(AppFont.sourceHanSans,
          cancellationToken: token, onProgress: (_) {
        if (!firstProgress.isCompleted) firstProgress.complete();
      });
      stalled.add(fontBytesA.sublist(0, 30000));
      // 收到第一段資料後連線停住（之後不再有資料區塊），此時才按取消
      await firstProgress.future;

      token.cancel();

      await expectLater(download, failsWith(FontDownloadFailure.cancelled));
      expect(await filesIn(fontsDir), isEmpty);
    });

    test('還在等伺服器回應時按取消 → 立即 cancelled，之後可以再下載', () async {
      var attempts = 0;
      final store = storeWith(MockClient.streaming((request, _) async {
        attempts++;
        if (attempts == 1) return Completer<http.StreamedResponse>().future;
        return http.StreamedResponse(chunked(fontBytesA), 200, contentLength: fontBytesA.length);
      }));
      final token = FontDownloadCancellationToken();

      final download = store.download(AppFont.sourceHanSans, cancellationToken: token);
      // 等請求真的送出（前面有建立暫存檔的檔案 I/O），伺服器還沒回應時才按取消
      while (attempts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      token.cancel();

      await expectLater(download, failsWith(FontDownloadFailure.cancelled));
      await store.download(AppFont.sourceHanSans);
      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });

    test('HTTP 非 200 時會取消訂閱回應內容，讓連線可以回收', () async {
      var listened = false;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onListen: () => listened = true,
        onCancel: () => cancelled = true,
      );
      final store = storeWith(MockClient.streaming(
          (request, _) async => http.StreamedResponse(body.stream, 503)));

      await expectLater(store.download(AppFont.sourceHanSans),
          failsWith(FontDownloadFailure.httpStatus, statusCode: 503));
      await pumpEventQueue();

      expect(listened, isTrue);
      expect(cancelled, isTrue);
    });
  });

  group('WebView 太舊時只公開載得動的字型（Issue 7）', () {
    /// 思源黑體標成 40MB（舊 WebView 載不動）、思源宋體維持 50,000 bytes（載得動），
    /// 驗證判斷是依每款字型的大小，不是一律全擋。
    FontDownloadSpec mixedSpecOf(AppFont font) => font == AppFont.sourceHanSans
        ? FontDownloadSpec(
            publishPath: specA.publishPath, sizeBytes: 40 * 1024 * 1024, sha256: specA.sha256)
        : specB;

    DownloadableFontStore storeFor(int? webViewMajorVersion) => DownloadableFontStore(
          httpClient: serving({}),
          directory: fontsDir,
          baseUri: Uri.parse('https://fonts.test/'),
          specOf: mixedSpecOf,
          webViewMajorVersion: webViewMajorVersion,
        );

    Future<void> placeInstalledFiles() async {
      await fileFor(specA.publishPath).create(recursive: true);
      await fileFor(specB.publishPath).create(recursive: true);
    }

    test('舊 WebView（91）：supportedFonts 不含超過 30MB 的字型', () {
      expect(storeFor(91).supportedFonts, [AppFont.sourceHanSerif]);
    });

    test('新 WebView（154）與讀不到版本（null）：supportedFonts 是全部字型', () {
      expect(storeFor(154).supportedFonts, AppFont.values);
      expect(storeFor(null).supportedFonts, AppFont.values);
    });

    test('沒有傳 webViewMajorVersion 時行為和以前一樣（全部支援）', () {
      expect(storeWith(serving({})).supportedFonts, AppFont.values);
    });

    test('舊 WebView：檔案存在也不列為已下載', () async {
      await placeInstalledFiles();
      expect(await storeFor(91).installedFonts(), {AppFont.sourceHanSerif});
    });

    test('舊 WebView：prepare 刪除載不動的已下載檔案，保留載得動的', () async {
      await placeInstalledFiles();
      await storeFor(91).prepare();
      expect(await filesIn(fontsDir), [specB.publishPath]);
    });

    test('讀不到版本（null）：prepare 不刪任何正式檔案', () async {
      await placeInstalledFiles();
      await storeFor(null).prepare();
      expect((await filesIn(fontsDir))..sort(), [specA.publishPath, specB.publishPath]);
    });
  });
}
