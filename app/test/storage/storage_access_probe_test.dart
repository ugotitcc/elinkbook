import 'dart:async';

import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:elinkbook/storage/storage_access_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('probeStorageAccessViaChannel（epic-15-storage-permission Issue 1）', () {
    const channel = MethodChannel('elinkbook/reader_resources_cache');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final entry in {
      'readable': StorageAccessProbeResult.readable,
      'permissionRevoked': StorageAccessProbeResult.permissionRevoked,
      'fileNotFound': StorageAccessProbeResult.fileNotFound,
      'unknownError': StorageAccessProbeResult.unknownError,
    }.entries) {
      test('原生回傳 "${entry.key}" 對應到 ${entry.value}', () async {
        MethodCall? captured;
        messenger.setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return entry.key;
        });

        final result = await probeStorageAccessViaChannel(
            'content://com.example.provider/book.epub');

        expect(result, entry.value);
        expect(captured!.method, 'probeUriAccess');
        expect(captured!.arguments,
            {'uri': 'content://com.example.provider/book.epub'});
      });
    }

    test('無法辨識的代碼回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'somethingNew');
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳 null 時回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳非字串（型別不符）回傳 unknownError，不拋出 TypeError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 42);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('PlatformException 回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('通道沒有原生實作（MissingPluginException）回傳 unknownError',
        () async {
      // 不註冊任何 handler：對應 widget test／無原生實作的環境。
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生逾時未回應時回傳 unknownError', () async {
      final never = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (call) => never.future);
      expect(
        await probeStorageAccessViaChannel('content://x/a.epub',
            timeout: const Duration(milliseconds: 50)),
        StorageAccessProbeResult.unknownError,
      );
    });

    test('非 content:// 輸入不呼叫通道，直接回傳 unknownError', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return 'readable';
      });
      expect(await probeStorageAccessViaChannel('/data/user/0/app/book.epub'),
          StorageAccessProbeResult.unknownError);
      expect(called, isFalse);
    });

    test('結果寫入 ReaderConsoleLog', () async {
      ReaderConsoleLog.clear();
      messenger.setMockMethodCallHandler(
          channel, (call) async => 'permissionRevoked');
      await probeStorageAccessViaChannel('content://x/a.epub');
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('content://x/a.epub → permissionRevoked'),
      );
    });

    test('probeStorageAccess 預設指向 probeStorageAccessViaChannel', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'readable');
      expect(await probeStorageAccess('content://x/a.epub'),
          StorageAccessProbeResult.readable);
    });
  });

  // 新增（計畫審查 M-1）：CONTEXT.md「存取探測」把逾時 3 秒寫成領域事實，
  // 這個常數原本只作為預設參數存在、沒有任何直接斷言。
  test('kStorageAccessProbeTimeout 為 3 秒', () {
    expect(kStorageAccessProbeTimeout, const Duration(seconds: 3));
  });
}
