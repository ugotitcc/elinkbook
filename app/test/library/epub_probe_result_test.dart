// mapProbeResult 單元測試（原在 android_epub_metadata_test.dart；epic-66 Issue 25 起
// 該函式由 Android 與 Windows 共用，測試改放平台中立檔名下）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/epub_probe_result.dart';

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
}
