// Android foliate-js 探針單元測試（epic-66 Issue 12 Task 2）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/android_epub_metadata.dart';

void main() {
  group('mapProbeResult', () {
    test('完整 JSON 包含封面 base64 時正確解析', () {
      final cover = Uint8List.fromList([1, 2, 3, 4, 5]);
      final json = jsonEncode({
        'title': '測試書名',
        'author': '測試作者',
        'identifier': 'urn:uuid:12345',
        'isFixedLayout': true,
        'coverBase64': base64Encode(cover),
      });

      final result = mapProbeResult(json);
      expect(result['title'], '測試書名');
      expect(result['author'], '測試作者');
      expect(result['identifier'], 'urn:uuid:12345');
      expect(result['isFixedLayout'], true);
      expect(result['coverBytes'], cover);
    });

    test('沒封面時 coverBytes 為 null', () {
      final json = jsonEncode({
        'title': '無封面書',
        'author': null,
        'identifier': 'id-1',
        'isFixedLayout': false,
        'coverBase64': null,
      });

      final result = mapProbeResult(json);
      expect(result['coverBytes'], isNull);
      expect(result['author'], isNull);
    });

    test('壞掉的 base64 時 coverBytes 為 null 且不拋例外', () {
      final json = jsonEncode({
        'title': '損壞封面書',
        'coverBase64': '!!!not-valid-base64???',
      });

      final result = mapProbeResult(json);
      expect(result['coverBytes'], isNull);
    });

    test('缺 isFixedLayout 時預設 false', () {
      final json = jsonEncode({
        'title': '一般書',
      });

      final result = mapProbeResult(json);
      expect(result['isFixedLayout'], isFalse);
    });

    test('title、author、identifier 缺漏時為 null', () {
      final json = jsonEncode({});

      final result = mapProbeResult(json);
      expect(result['title'], isNull);
      expect(result['author'], isNull);
      expect(result['identifier'], isNull);
      expect(result['isFixedLayout'], isFalse);
      expect(result['coverBytes'], isNull);
      expect(result['coverType'], isNull);
    });

    test('coverType 為 application/xhtml+xml 時 coverBytes 為 null 且保留 coverType', () {
      final cover = Uint8List.fromList([10, 20, 30]);
      final json = jsonEncode({
        'title': 'XHTML 封面書',
        'coverBase64': base64Encode(cover),
        'coverType': 'application/xhtml+xml',
      });

      final result = mapProbeResult(json);
      expect(result['coverBytes'], isNull);
      expect(result['coverType'], 'application/xhtml+xml');
    });

    test('coverType 為 image/jpeg 時照常解碼並保留 coverType', () {
      final cover = Uint8List.fromList([0xff, 0xd8, 0xff]);
      final json = jsonEncode({
        'title': 'JPEG 封面書',
        'coverBase64': base64Encode(cover),
        'coverType': 'image/jpeg',
      });

      final result = mapProbeResult(json);
      expect(result['coverBytes'], cover);
      expect(result['coverType'], 'image/jpeg');
    });

    test('coverType 缺漏或空字串時照常解碼（相容既有案例）', () {
      final cover = Uint8List.fromList([1, 2, 3]);
      final jsonMissing = jsonEncode({
        'title': '缺 coverType',
        'coverBase64': base64Encode(cover),
      });
      final resMissing = mapProbeResult(jsonMissing);
      expect(resMissing['coverBytes'], cover);
      expect(resMissing['coverType'], isNull);

      final jsonEmpty = jsonEncode({
        'title': '空 coverType',
        'coverBase64': base64Encode(cover),
        'coverType': '',
      });
      final resEmpty = mapProbeResult(jsonEmpty);
      expect(resEmpty['coverBytes'], cover);
      expect(resEmpty['coverType'], '');
    });
  });

  group('androidProbeHtml', () {
    test('包含書檔大小、handler 名稱與 probe 模組路徑', () {
      final html = androidProbeHtml(123456);
      expect(html, contains('123456'));
      expect(html, contains('metadataResult'));
      expect(html, contains('metadataError'));
      expect(html, contains('/assets/foliate/metadata-probe.js'));
    });
  });

  group('interceptBookRange', () {
    test('讀取成功回傳 200 與資料', () async {
      final payload = Uint8List.fromList([10, 20, 30]);
      final uri = Uri.parse('https://foliate-metadata.local/book/current.epub?start=0&end=3');

      var called = false;
      final response = await interceptBookRange(
        uri,
        readRange: (start, end) async {
          called = true;
          expect(start, 0);
          expect(end, 3);
          return payload;
        },
      );

      expect(called, isTrue);
      expect(response, isNotNull);
      expect(response!.statusCode, 200);
      expect(response.data, payload);
    });

    test('readRange 回傳 null 時回傳 404', () async {
      final uri = Uri.parse('https://foliate-metadata.local/book/current.epub?start=100&end=200');

      final response = await interceptBookRange(
        uri,
        readRange: (start, end) async => null,
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 404);
      expect(response.reasonPhrase, 'Not Found');
      expect(response.data?.isEmpty, isTrue);
    });

    test('readRange 拋例外時回傳 404 且不往外拋', () async {
      final uri = Uri.parse('https://foliate-metadata.local/book/current.epub?start=10&end=20');

      final response = await interceptBookRange(
        uri,
        readRange: (start, end) async {
          throw Exception('檔案讀取失敗');
        },
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 404);
      expect(response.reasonPhrase, 'Not Found');
    });

    test('缺少 start 或 end 參數時回傳 404 且從未呼叫 readRange', () async {
      var called = false;
      Future<Uint8List?> dummyReader(int start, int end) async {
        called = true;
        return Uint8List(0);
      }

      // 缺少 end
      final noEnd = Uri.parse('https://foliate-metadata.local/book/current.epub?start=0');
      final res1 = await interceptBookRange(noEnd, readRange: dummyReader);
      expect(res1?.statusCode, 404);
      expect(called, isFalse);

      // 缺少 start
      final noStart = Uri.parse('https://foliate-metadata.local/book/current.epub?end=10');
      final res2 = await interceptBookRange(noStart, readRange: dummyReader);
      expect(res2?.statusCode, 404);
      expect(called, isFalse);

      // 非整數
      final invalid = Uri.parse('https://foliate-metadata.local/book/current.epub?start=abc&end=def');
      final res3 = await interceptBookRange(invalid, readRange: dummyReader);
      expect(res3?.statusCode, 404);
      expect(called, isFalse);
    });
  });
}
