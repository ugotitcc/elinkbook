import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildFontFaceCss 產生 5 款內建字型的 @font-face 宣告', () {
    final css = buildFontFaceCss();
    expect(css, contains(
      "@font-face { font-family: 'SourceHanSansTC'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/SourceHanSansTC-VF.ttf'); }",
    ));
    expect(css, contains(
      "@font-face { font-family: 'GuanKiapTsingKhai'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/GuanKiapTsingKhai.ttf'); }",
    ));
    expect('@font-face'.allMatches(css).length, 5);
  });

  test('loadAndroidAsset 呼叫 elinkbook/reader_resources 的 readAndroidAsset', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources'),
      (call) async {
        captured = call;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final bytes = await loadAndroidAsset('foliate/main.js');

    expect(captured!.method, 'readAndroidAsset');
    expect(captured!.arguments, {'path': 'foliate/main.js'});
    expect(bytes, [1, 2, 3]);
  });

  test('attachReaderView／detachReaderView 呼叫 elinkbook/volume_key 對應 case', () async {
    final calledMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async {
        calledMethods.add(call.method);
        return null;
      },
    );

    await attachReaderView();
    await detachReaderView();

    expect(calledMethods, ['attachReaderView', 'detachReaderView']);
  });

  test('loadFlutterFontAsset 透過 rootBundle 讀取 Flutter 字型 asset', () async {
    final bytes = await loadFlutterFontAsset('assets/fonts/GuanKiapTsingKhai.ttf');
    expect(bytes, isNotNull);
    expect(bytes!.isNotEmpty, isTrue);
  });

  test('cacheBookForServing 呼叫 elinkbook/reader_resources_cache 的 cacheBookForServing', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources_cache'),
      (call) async {
        captured = call;
        return '/fake/cache/dir/current.epub';
      },
    );

    // 使用 content:// URI 測試（不經過檔案存在檢查，直接呼叫原生端）
    final result = await cacheBookForServing('content://com.example.provider/book.epub', 'test_instance');

    expect(captured!.method, 'cacheBookForServing');
    expect(captured!.arguments, {'uri': 'content://com.example.provider/book.epub', 'instanceId': 'test_instance'});
    expect(result, '/fake/cache/dir/current.epub');
  });
}
