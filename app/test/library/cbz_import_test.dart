import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/cbz_import.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

Uint8List _buildSyntheticCbz(
  List<String> imageNames, {
  List<String> extraNonImageNames = const [],
}) {
  final archive = Archive();
  for (final name in imageNames) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode('fake-image-bytes:$name')));
  }
  for (final name in extraNonImageNames) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode('non-image:$name')));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('compareNaturalOrder', () {
    test('非零填補檔名依數值排出正確頁序（Issue 1 Spike 已查證的既有缺陷情境）', () {
      final names = ['2.jpg', '10.jpg', '1.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['1.jpg', '2.jpg', '10.jpg']);
    });

    test('零填補檔名維持原有正確順序（字典序與自然序結果一致的情境）', () {
      final names = ['003.jpg', '001.jpg', '002.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['001.jpg', '002.jpg', '003.jpg']);
    });

    test('相同前綴、數字不同的檔名依數值比較，不受字典序位數影響', () {
      final names = ['page10.png', 'page2.png', 'page1.png'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.png', 'page2.png', 'page10.png']);
    });

    test('完全非數字的檔名退回字典序比較', () {
      final names = ['cover.jpg', 'back.jpg', 'front.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['back.jpg', 'cover.jpg', 'front.jpg']);
    });

    test('非數字片段忽略大小寫比較（審查修正：混用大小寫檔名仍依數字正確排序）', () {
      final names = ['Page2.jpg', 'page1.jpg', 'PAGE10.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.jpg', 'Page2.jpg', 'PAGE10.jpg']);
    });
  });

  group('prepareCbzForImport', () {
    test('非零填補檔名依自然排序重建，封面取排序後第一張圖片', () async {
      final bytes = _buildSyntheticCbz(['2.jpg', '10.jpg', '1.jpg']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_unpadded.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      expect(result.coverBytes, utf8.encode('fake-image-bytes:1.jpg'));
      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      final names = rebuilt.files.map((f) => f.name).toList();
      expect(names, ['page_0001.jpg', 'page_0002.jpg', 'page_0003.jpg']);
      expect(rebuilt.files[0].readBytes(), utf8.encode('fake-image-bytes:1.jpg'));
      expect(rebuilt.files[1].readBytes(), utf8.encode('fake-image-bytes:2.jpg'));
      expect(rebuilt.files[2].readBytes(), utf8.encode('fake-image-bytes:10.jpg'));
    });

    test('零填補檔名重建後頁序不變', () async {
      final bytes = _buildSyntheticCbz(['001.jpg', '002.jpg', '003.jpg']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_padded.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      expect(result.coverBytes, utf8.encode('fake-image-bytes:001.jpg'));
      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      expect(rebuilt.files[0].readBytes(), utf8.encode('fake-image-bytes:001.jpg'));
      expect(rebuilt.files[1].readBytes(), utf8.encode('fake-image-bytes:002.jpg'));
      expect(rebuilt.files[2].readBytes(), utf8.encode('fake-image-bytes:003.jpg'));
    });

    test('非圖片項目（例如 ComicInfo.xml）不保留於重建後的壓縮檔', () async {
      final bytes = _buildSyntheticCbz(
        ['001.jpg', '002.jpg'],
        extraNonImageNames: ['ComicInfo.xml'],
      );
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_nonimage.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      final result = await prepareCbzForImport(tempFile.path);

      final rebuilt = ZipDecoder().decodeBytes(result.rebuiltArchiveBytes);
      expect(rebuilt.files, hasLength(2));
    });

    test('壓縮檔內沒有支援的圖片格式時拋出 NoComicPagesException', () async {
      final bytes = _buildSyntheticCbz([], extraNonImageNames: ['readme.txt']);
      final tempFile =
          File('${Directory.systemTemp.path}/cbz_test_empty.cbz');
      await tempFile.writeAsBytes(bytes);
      addTearDown(() => tempFile.delete());

      expect(
        () => prepareCbzForImport(tempFile.path),
        throwsA(isA<NoComicPagesException>()),
      );
    });

    group('content:// URI 支援', () {
      late Directory tempDir;
      late PathProviderPlatform originalPathProvider;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('cbz_import_test_tmp');
        originalPathProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
      });

      tearDown(() {
        PathProviderPlatform.instance = originalPathProvider;
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
      });

      test('content:// URI 先複製到暫存檔再解析', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'copyContentUriToFile');
          final args = call.arguments as Map;
          final bytes = _buildSyntheticCbz(['001.jpg', '002.jpg']);
          await File(args['destinationPath'] as String).writeAsBytes(bytes);
          return null;
        });

        final result = await prepareCbzForImport('content://example/sample.cbz');

        expect(result.coverBytes, utf8.encode('fake-image-bytes:001.jpg'));
      });

      test('content:// URI 對應的暫存檔在解析完成後被刪除', () async {
        String? capturedTempPath;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          final args = call.arguments as Map;
          capturedTempPath = args['destinationPath'] as String;
          final bytes = _buildSyntheticCbz(['001.jpg']);
          await File(capturedTempPath!).writeAsBytes(bytes);
          return null;
        });

        await prepareCbzForImport('content://example/sample.cbz');

        expect(capturedTempPath, isNotNull);
        expect(File(capturedTempPath!).existsSync(), isFalse);
      });
    });
  });
}
