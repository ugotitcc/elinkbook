// book_range_reader 單元測試（epic-66 Issue 12 Task 1）。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/book_range_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleFile;
  final sampleBytes = Uint8List.fromList(List.generate(100, (i) => i));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('book_range_reader_test_');
    sampleFile = File('${tempDir.path}/sample.bin');
    await sampleFile.writeAsBytes(sampleBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('本機檔案讀取', () {
    test('本機路徑讀 [start, end) 與檔案內容一致', () async {
      final bytes = await readBookRange(sampleFile.path, 10, 20);
      expect(bytes, equals(sampleBytes.sublist(10, 20)));
    });

    test('end 超過長度被夾回檔案末尾', () async {
      final bytes = await readBookRange(sampleFile.path, 90, 150);
      expect(bytes, equals(sampleBytes.sublist(90, 100)));
    });

    test('start 不小於長度回傳 null', () async {
      final atEnd = await readBookRange(sampleFile.path, 100, 110);
      expect(atEnd, isNull);

      final pastEnd = await readBookRange(sampleFile.path, 105, 110);
      expect(pastEnd, isNull);
    });

    test('file:/// 網址轉成本機路徑讀取且不走通道', () async {
      final fileUri = sampleFile.uri.toString();
      expect(fileUri, startsWith('file://'));

      var channelCalled = false;
      final mockChannel = MethodChannel('mock/reader_resources');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (call) async {
        channelCalled = true;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(mockChannel, null);
      });

      final bytes = await readBookRange(
        fileUri,
        0,
        5,
        channel: mockChannel,
      );
      expect(bytes, equals(sampleBytes.sublist(0, 5)));
      expect(channelCalled, isFalse);
    });

    test('bookLength 本機路徑回傳真實檔案長度', () async {
      final len = await bookLength(sampleFile.path);
      expect(len, equals(100));

      final uriLen = await bookLength(sampleFile.uri.toString());
      expect(uriLen, equals(100));
    });

    test('bookLength 本機不存在檔案回傳 null', () async {
      final len = await bookLength('${tempDir.path}/non_existent.bin');
      expect(len, isNull);
    });
  });

  group('content:// URI 讀取', () {
    const testContentUri = 'content://media/external/file/12345';
    late MethodChannel mockChannel;
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      mockChannel = const MethodChannel('mock/reader_resources_cache');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (call) async {
        methodCalls.add(call);
        if (call.method == 'readContentUriRange') {
          final uri = call.arguments['uri'] as String?;
          final start = call.arguments['start'] as int?;
          final end = call.arguments['end'] as int?;
          if (uri == testContentUri && start == 0 && end == 10) {
            return Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
          }
          return null;
        } else if (call.method == 'contentUriLength') {
          final uri = call.arguments['uri'] as String?;
          if (uri == testContentUri) return 123456;
          return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, null);
    });

    test('content:// 走通道並帶入正確參數', () async {
      final bytes = await readBookRange(
        testContentUri,
        0,
        10,
        channel: mockChannel,
      );

      expect(bytes, equals(Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])));
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'readContentUriRange');
      expect(methodCalls.first.arguments, {
        'uri': testContentUri,
        'start': 0,
        'end': 10,
      });
    });

    test('通道回傳 null 時回傳 null', () async {
      final bytes = await readBookRange(
        'content://media/external/file/not_found',
        0,
        10,
        channel: mockChannel,
      );
      expect(bytes, isNull);
    });

    test('通道丟 PlatformException 時 readBookRange 把例外往外拋', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (call) async {
        throw PlatformException(code: 'permission_denied', message: 'No access');
      });

      expect(
        () => readBookRange(testContentUri, 0, 10, channel: mockChannel),
        throwsA(isA<PlatformException>()),
      );
    });

    test('bookLength content:// 走通道取得長度', () async {
      final len = await bookLength(testContentUri, channel: mockChannel);
      expect(len, equals(123456));
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'contentUriLength');
      expect(methodCalls.first.arguments, {'uri': testContentUri});
    });

    test('bookLength 通道丟 PlatformException 時把例外往外拋', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (call) async {
        throw PlatformException(code: 'error', message: 'Failed');
      });

      expect(
        () => bookLength(testContentUri, channel: mockChannel),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
