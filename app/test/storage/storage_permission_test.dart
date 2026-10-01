import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/storage/storage_permission.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kBookMetadataChannel, null));

  test('核發成功：回傳 true，並把 uri 以 takePersistableUriPermission 傳給原生端', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      calls.add(call);
      return null;
    });

    final granted = await persistReadAccess('content://x/font.ttf');

    expect(granted, isTrue);
    expect(calls.single.method, 'takePersistableUriPermission');
    expect((calls.single.arguments as Map)['uri'], 'content://x/font.ttf');
  });

  test('原生端拋出 PlatformException（提供者不核發）：回傳 false', () async {
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      throw PlatformException(code: 'denied');
    });

    expect(await persistReadAccess('content://x/font.ttf'), isFalse);
  });

  test('只轉換 PlatformException：原生端沒有實作（MissingPluginException）時照樣拋出', () async {
    // 沒有設定 mock handler
    expect(
      () => persistReadAccess('content://x/font.ttf'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
