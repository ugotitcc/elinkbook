// Windows／Android 平台分流的 channel 行為測試（epic-66 Issue 1 Task 7）。
//
// Windows 沒有 `elinkbook/volume_key`、`elinkbook/reader_resources` 原生端，
// 分流必須在 Dart 端直接返回，不能呼叫 MethodChannel（否則丟
// MissingPluginException）。

import 'dart:io';

import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
  const readerResourcesChannel = MethodChannel('elinkbook/reader_resources');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  int volumeKeyCalls = 0;
  int readerResourceCalls = 0;

  setUp(() {
    volumeKeyCalls = 0;
    readerResourceCalls = 0;
    messenger.setMockMethodCallHandler(volumeKeyChannel, (call) async {
      volumeKeyCalls++;
      return null;
    });
    messenger.setMockMethodCallHandler(readerResourcesChannel, (call) async {
      readerResourceCalls++;
      return Uint8List.fromList([9]);
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    windowsFoliateAssetRootOverride = null;
    messenger.setMockMethodCallHandler(volumeKeyChannel, null);
    messenger.setMockMethodCallHandler(readerResourcesChannel, null);
  });

  test('Windows：attachReaderView 不呼叫 MethodChannel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await attachReaderView();
    await detachReaderView();

    expect(volumeKeyCalls, 0);
  });

  test('Android：attachReaderView 仍呼叫 volume_key channel 一次', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await attachReaderView();

    expect(volumeKeyCalls, 1);
  });

  test('Windows：loadAndroidAsset 不呼叫 reader_resources channel', () async {
    final tempRoot = await Directory.systemTemp.createTemp('win_asset_root_');
    addTearDown(() async {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    });
    final foliateDir = Directory('${tempRoot.path}${Platform.pathSeparator}foliate');
    await foliateDir.create(recursive: true);
    await File('${foliateDir.path}${Platform.pathSeparator}main.js')
        .writeAsString('console.log(1);');
    windowsFoliateAssetRootOverride = tempRoot.path;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final bytes = await loadAndroidAsset('foliate/main.js');

    expect(readerResourceCalls, 0, reason: 'Windows 必須從磁碟讀，不可呼叫原生 channel');
    expect(bytes, isNotNull, reason: '應讀到 override 指向的本機檔案');
  });
}
