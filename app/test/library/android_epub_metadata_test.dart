// Android foliate-js 探針單元測試（epic-66 Issue 12 Task 2）。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/android_epub_metadata.dart';

void main() {
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
