import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/content_uri_reader.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('content_uri_reader_test_tmp');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('複製 content:// URI 到暫存檔並讀回位元組', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'copyContentUriToFile');
      final args = call.arguments as Map;
      await File(args['destinationPath'] as String).writeAsBytes([1, 2, 3]);
      return null;
    });

    final bytes = await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'test_probe',
      tempFileExtension: '.txt',
    );

    expect(bytes, [1, 2, 3]);
  });

  test('讀取完成後刪除暫存檔', () async {
    String? capturedTempPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map;
      capturedTempPath = args['destinationPath'] as String;
      await File(capturedTempPath!).writeAsBytes([9]);
      return null;
    });

    await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'test_probe',
      tempFileExtension: '.txt',
    );

    expect(capturedTempPath, isNotNull);
    expect(File(capturedTempPath!).existsSync(), isFalse);
  });

  test('暫存檔名帶有指定的 prefix 與副檔名', () async {
    String? capturedTempPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map;
      capturedTempPath = args['destinationPath'] as String;
      await File(capturedTempPath!).writeAsBytes([1]);
      return null;
    });

    await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'txt_probe',
      tempFileExtension: '.txt',
    );

    expect(capturedTempPath, contains('txt_probe_'));
    expect(capturedTempPath, endsWith('.txt'));
  });
}
