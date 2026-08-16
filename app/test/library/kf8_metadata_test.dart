import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/kf8_metadata.dart';

void main() {
  group('extractKf8Metadata：真實 AZW3 樣本', () {
    test('可成功解析（不拋出例外）', () async {
      final result = await extractKf8Metadata('test/fixtures/sample.azw3');
      expect(result, isNotNull);
    });
  });

  test('PDB type/creator 不符時拋出 FormatException', () async {
    final bytes = Uint8List(90);
    bytes.setRange(60, 64, 'ZZZZ'.codeUnits);
    bytes.setRange(64, 68, 'ZZZZ'.codeUnits);
    final tempFile = File('${Directory.systemTemp.path}/kf8_test_invalid.azw3');
    await tempFile.writeAsBytes(bytes);
    addTearDown(() => tempFile.delete());

    expect(
      () => extractKf8Metadata(tempFile.path),
      throwsA(isA<FormatException>()),
    );
  });
}
