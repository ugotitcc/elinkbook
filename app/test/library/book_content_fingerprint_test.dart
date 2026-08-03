import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kBookMetadataChannel, null);
  });

  group('EPUB：OPF identifier 優先', () {
    test('epubIdentifier 非空時，直接回傳該值，不計算 SHA-256', () async {
      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: 'urn:uuid:00000000-0000-0000-0000-000000000001',
      );

      expect(result, 'urn:uuid:00000000-0000-0000-0000-000000000001');
    });

    test('epubIdentifier 為 null 時，退回計算整份檔案的 SHA-256', () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
      );

      expect(result, expected);
    });

    test('epubIdentifier 為空字串時，同樣退回計算 SHA-256（OPF identifier 元素存在但內容為空）',
        () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '',
      );

      expect(result, expected);
    });

    test('epubIdentifier 為純空白字串時，視同缺漏，退回計算 SHA-256（不規範 EPUB 防禦）',
        () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '   ',
      );

      expect(result, expected);
    });

    test('epubIdentifier 前後夾帶空白時，回傳修剪後的值', () async {
      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '  urn:uuid:00000000-0000-0000-0000-000000000001  ',
      );

      expect(result, 'urn:uuid:00000000-0000-0000-0000-000000000001');
    });
  });

  group('PDF／TXT：一律 SHA-256', () {
    test('PDF 檔案計算結果與獨立計算的參考雜湊值一致', () async {
      final fileBytes = await File('test/fixtures/sample.pdf').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );

      expect(result, expected);
    });

    test('同一檔案計算兩次，結果一致（確定性）', () async {
      final result1 = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );
      final result2 = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );

      expect(result1, result2);
    });

    test('大檔案（>10MB）以串流方式計算，結果與獨立計算的參考雜湊值一致', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('fingerprint_large_file_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(p.join(tempDir.path, 'large.pdf'));

      final sink = file.openWrite();
      final chunk = List<int>.generate(1024 * 1024, (i) => i % 256); // 1MB
      for (var i = 0; i < 15; i++) {
        sink.add(chunk);
      }
      await sink.close();

      final expected = sha256.convert(await file.readAsBytes()).toString();

      final result =
          await computeBookContentFingerprint(file.path, BookFileFormat.pdf);

      expect(result, expected);
    });
  });

  group('content:// URI：委由原生端 computeSha256', () {
    test('filePath 為 content:// URI 時，呼叫原生 computeSha256 並回傳其結果', () async {
      String? capturedMethod;
      Map? capturedArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        capturedMethod = call.method;
        capturedArgs = call.arguments as Map;
        return 'abc123deadbeef';
      });

      final result = await computeBookContentFingerprint(
        'content://example/book.pdf',
        BookFileFormat.pdf,
      );

      expect(result, 'abc123deadbeef');
      expect(capturedMethod, 'computeSha256');
      expect(capturedArgs?['uri'], 'content://example/book.pdf');
    });

    test('EPUB 且 epubIdentifier 非空時，即使 filePath 是 content:// 也不呼叫原生 computeSha256',
        () async {
      var computeSha256Called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        if (call.method == 'computeSha256') computeSha256Called = true;
        return null;
      });

      final result = await computeBookContentFingerprint(
        'content://example/book.epub',
        BookFileFormat.epub,
        epubIdentifier: 'urn:isbn:9780000000000',
      );

      expect(result, 'urn:isbn:9780000000000');
      expect(computeSha256Called, isFalse);
    });

    test('原生 computeSha256 回傳 null 時，視為計算失敗並拋出例外', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async => null);

      await expectLater(
        () => computeBookContentFingerprint(
          'content://example/book.pdf',
          BookFileFormat.pdf,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
