import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/kf8_metadata.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

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

  group('content:// URI 支援（epic-11 Issue 2 程式碼審查 C1 迴歸測試）', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('kf8_metadata_test_tmp');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('content:// URI 先複製到暫存檔再解析，title 正確擷取', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'copyContentUriToFile');
        final args = call.arguments as Map;
        final bytes = await File('test/fixtures/sample.azw3').readAsBytes();
        await File(args['destinationPath'] as String).writeAsBytes(bytes);
        return null;
      });

      final result =
          await extractKf8Metadata('content://example/sample.azw3');

      expect(result['title'], contains('Time Machine'));
    });

    test('content:// URI 對應的暫存檔在解析完成後被刪除', () async {
      String? capturedTempPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        final args = call.arguments as Map;
        capturedTempPath = args['destinationPath'] as String;
        final bytes = await File('test/fixtures/sample.azw3').readAsBytes();
        await File(capturedTempPath!).writeAsBytes(bytes);
        return null;
      });

      await extractKf8Metadata('content://example/sample.azw3');

      expect(capturedTempPath, isNotNull);
      expect(File(capturedTempPath!).existsSync(), isFalse);
    });
  });

  group('欄位層級錯誤隔離（epic-11 Issue 2 程式碼審查 I2 迴歸測試）', () {
    Uint8List buildSyntheticPdbWithFixedLayoutExth() {
      // record 0 佈局：PalmDoc header(16) + MOBI header 需要的欄位（僅寫入
      // 本模組實際讀取的位置，其餘保留 0）+ EXTH（含 tag 122=fixedLayout）。
      // titleOffset 故意設為超出 record 0 範圍的值，驗證標題解析失敗不會
      // 連帶丟失已成功解析的 isFixedLayout。
      const record0Length = 280;
      final bytes = Uint8List(78 + 8 + record0Length);
      bytes.setRange(60, 64, 'BOOK'.codeUnits); // PDB type
      bytes.setRange(64, 68, 'MOBI'.codeUnits); // PDB creator
      ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big); // numRecords
      ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big); // record 0 offset

      const r0 = 86; // record 0 起點（絕對 offset）
      bytes.setRange(r0 + 16, r0 + 20, 'MOBI'.codeUnits); // MOBI magic
      ByteData.sublistView(bytes, r0 + 20, r0 + 24).setUint32(0, 232, Endian.big); // mobiLength
      ByteData.sublistView(bytes, r0 + 28, r0 + 32).setUint32(0, 65001, Endian.big); // encoding=utf-8
      ByteData.sublistView(bytes, r0 + 84, r0 + 88).setUint32(0, 999999, Endian.big); // titleOffset（故意越界）
      ByteData.sublistView(bytes, r0 + 88, r0 + 92).setUint32(0, 10, Endian.big); // titleLength
      ByteData.sublistView(bytes, r0 + 128, r0 + 132).setUint32(0, 0x40, Endian.big); // exthFlag（bit 6 = 有 EXTH）

      // EXTH header 位於 record 0 內 offset mobiLength+16 = 248
      const exthOffset = 248;
      final exthAbs = r0 + exthOffset;
      bytes.setRange(exthAbs, exthAbs + 4, 'EXTH'.codeUnits); // magic
      ByteData.sublistView(bytes, exthAbs + 8, exthAbs + 12).setUint32(0, 1, Endian.big); // count=1
      // 唯一一筆 EXTH entry：tag 122（fixedLayout），資料 'true'
      ByteData.sublistView(bytes, exthAbs + 12, exthAbs + 16).setUint32(0, 122, Endian.big); // type
      ByteData.sublistView(bytes, exthAbs + 16, exthAbs + 20).setUint32(0, 12, Endian.big); // length(含8 byte前綴)
      bytes.setRange(exthAbs + 20, exthAbs + 24, 'true'.codeUnits); // data

      return bytes;
    }

    test('標題欄位解析失敗（titleOffset 越界）不影響 isFixedLayout 正確解析為 true', () async {
      final path = await writeTempAzw3(
        buildSyntheticPdbWithFixedLayoutExth(),
        'kf8_test_title_failure.azw3',
      );
      addTearDown(() => File(path).delete());

      final result = await extractKf8Metadata(path);

      expect(result['title'], isNull);
      expect(result['isFixedLayout'], isTrue);
    });

    test('coverOffset 為 EXTH 哨兵值 0xFFFFFFFF 時 coverBytes 為 null、不拋出例外', () async {
      // 沿用上面的合成緩衝區，額外在其後補一筆 tag 201（coverOffset）＝
      // 0xFFFFFFFF（EXTH 明確宣告「沒有封面」時常見的哨兵值）。
      final base = buildSyntheticPdbWithFixedLayoutExth();
      const record0Length = 280;
      final bytes = Uint8List(78 + 8 + record0Length + 12)
        ..setRange(0, base.length, base);
      const r0 = 86;
      const exthOffset = 248;
      final exthAbs = r0 + exthOffset;
      // count 改為 2 筆
      ByteData.sublistView(bytes, exthAbs + 8, exthAbs + 12).setUint32(0, 2, Endian.big);
      // 第二筆 entry 緊接在第一筆（type 122，12 bytes）之後
      final secondEntryAbs = exthAbs + 12 + 12;
      ByteData.sublistView(bytes, secondEntryAbs, secondEntryAbs + 4).setUint32(0, 201, Endian.big); // type=coverOffset
      ByteData.sublistView(bytes, secondEntryAbs + 4, secondEntryAbs + 8).setUint32(0, 12, Endian.big); // length
      ByteData.sublistView(bytes, secondEntryAbs + 8, secondEntryAbs + 12)
          .setUint32(0, 0xFFFFFFFF, Endian.big); // data=哨兵值

      final path = await writeTempAzw3(bytes, 'kf8_test_cover_sentinel.azw3');
      addTearDown(() => File(path).delete());

      final result = await extractKf8Metadata(path);

      expect(result['coverBytes'], isNull);
      expect(result['isFixedLayout'], isTrue);
    });
  });
}
