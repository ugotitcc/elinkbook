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

  DownloadableFontStore storeWith(http.Client client) => DownloadableFontStore(
        httpClient: client,
        directory: fontsDir,
        baseUri: Uri.parse('https://fonts.test/'),
        specOf: testSpecOf,
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
    Matcher failsWith(FontDownloadFailure reason, {int? statusCode}) => throwsA(
          isA<FontDownloadException>()
              .having((e) => e.reason, 'reason', reason)
              .having((e) => e.statusCode, 'statusCode', statusCode),
        );

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
      final controller = StreamController<List<int>>();
      final store = storeWith(MockClient.streaming((request, _) async =>
          http.StreamedResponse(controller.stream, 200, contentLength: fontBytesA.length)));

      final first = store.download(AppFont.sourceHanSans);
      await expectLater(
          store.download(AppFont.sourceHanSerif), throwsA(isA<StateError>()));

      controller.add(fontBytesA);
      await controller.close();
      await first;

      expect(await store.installedFonts(), {AppFont.sourceHanSans});
    });
  });
}
