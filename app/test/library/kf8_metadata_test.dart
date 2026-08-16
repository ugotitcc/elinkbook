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

  Uint8List buildSyntheticPdb({required int encryption}) {
    // 最小合法 PDB + record 0（含 PalmDoc header + MOBI header），
    // 足夠讓 extractKf8Metadata 在讀到 encryption 欄位後就能判定，
    // 不需要完整 EXTH 標頭。record 0 至少需要 132 bytes（MOBI header
    // 的 exthFlag 在 offset 128）。比照 Issue 1 Spike 驗證過的合成邏輯。
    final bytes = Uint8List(78 + 8 + 132);
    bytes.setRange(60, 64, 'BOOK'.codeUnits);
    bytes.setRange(64, 68, 'MOBI'.codeUnits);
    ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big); // numRecords
    ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big); // record 0 offset
    // MOBI magic at record0[16:20]
    bytes.setRange(86 + 16, 86 + 20, 'MOBI'.codeUnits);
    // encryption at record0[12:14] (PalmDoc header)
    ByteData.sublistView(bytes, 86 + 12, 86 + 14).setUint16(0, encryption, Endian.big);
    return bytes;
  }

  Future<String> writeTempAzw3(Uint8List bytes, String name) async {
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('DRM 偵測', () {
    test('encryption=0（未加密）不拋出例外', () async {
      final path = await writeTempAzw3(buildSyntheticPdb(encryption: 0), 'kf8_test_unencrypted.azw3');
      addTearDown(() => File(path).delete());

      await expectLater(extractKf8Metadata(path), completes);
    });

    test('encryption=1（舊版 Mobipocket 加密）拋出 DrmProtectedException', () async {
      final path = await writeTempAzw3(buildSyntheticPdb(encryption: 1), 'kf8_test_legacy_drm.azw3');
      addTearDown(() => File(path).delete());

      expect(
        () => extractKf8Metadata(path),
        throwsA(isA<DrmProtectedException>()),
      );
    });

    test('encryption=2（Mobipocket 加密）拋出 DrmProtectedException', () async {
      final path = await writeTempAzw3(buildSyntheticPdb(encryption: 2), 'kf8_test_drm.azw3');
      addTearDown(() => File(path).delete());

      expect(
        () => extractKf8Metadata(path),
        throwsA(isA<DrmProtectedException>()),
      );
    });
  });

  group('metadata 欄位（真實 AZW3 樣本）', () {
    test('title 含 "Time Machine"', () async {
      final result = await extractKf8Metadata('test/fixtures/sample.azw3');
      expect(result['title'], contains('Time Machine'));
    });

    test('coverBytes 非空', () async {
      final result = await extractKf8Metadata('test/fixtures/sample.azw3');
      expect(result['coverBytes'], isA<Uint8List>());
      expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
    });
  });
}
