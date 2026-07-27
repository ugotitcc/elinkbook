import 'dart:io';

import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';

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

  group('loadBookBytes（檔案系統路徑分支）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('foliate_native_bridge_test_');
      PathProviderPlatform.instance =
          FakePathProviderPlatform('${tempDir.path}/files');
      await Directory('${tempDir.path}/files').create(recursive: true);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('允許目錄內的真實檔案，正確讀回位元組內容', () async {
      final file = File('${tempDir.path}/files/sample.epub');
      await file.writeAsBytes([9, 8, 7]);

      final bytes = await loadBookBytes(file.path);

      expect(bytes, [9, 8, 7]);
    });

    test('允許目錄之外的路徑，回傳 null（不讀取內容）', () async {
      final outsideDir = await Directory.systemTemp.createTemp('outside_');
      addTearDown(() => outsideDir.delete(recursive: true));
      final file = File('${outsideDir.path}/secret.epub');
      await file.writeAsBytes([1]);

      final bytes = await loadBookBytes(file.path);

      expect(bytes, isNull);
    });

    test('檔案不存在時回傳 null', () async {
      final bytes = await loadBookBytes('${tempDir.path}/files/missing.epub');
      expect(bytes, isNull);
    });
  });
}
