import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/reader/system_tts_provider.dart';
import 'package:elinkbook/reader/tts_provider.dart';

import '../support/fake_path_provider_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('system_tts_provider_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('synthesize() 呼叫 synthesizeToFile（isFullPath=true）並在 synth.onComplete 後回傳結果',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'synthesizeToFile') {
        // 模擬原生端非同步完成合成：透過同一個 channel 送回
        // synth.onComplete，讓 FlutterTts() 建構子註冊的
        // platformCallHandler 觸發 SystemTtsProvider 內的 completer。
        scheduleMicrotask(() {
          final message = const StandardMethodCodec()
              .encodeMethodCall(const MethodCall('synth.onComplete'));
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(channel.name, message, (_) {});
        });
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());
    final result = await provider.synthesize(
      '測試文字',
      voice: TtsVoice.systemDefault,
    );

    expect(
      result.audioFilePath,
      endsWith(p.join('elinkbook_tts', 'current_segment.wav')),
    );
    final synthCall =
        calls.firstWhere((c) => c.method == 'synthesizeToFile');
    final args = synthCall.arguments as Map;
    expect(args['text'], '測試文字');
    expect(args['fileName'], result.audioFilePath);
    expect(args['isFullPath'], isTrue);
  });

  test('synthesize() 在 synth.onError 後拋出 TtsSynthesisException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'synthesizeToFile') {
        scheduleMicrotask(() {
          final message = const StandardMethodCodec().encodeMethodCall(
            const MethodCall('synth.onError', '模擬引擎錯誤'),
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(channel.name, message, (_) {});
        });
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());

    await expectLater(
      provider.synthesize('測試文字', voice: TtsVoice.systemDefault),
      throwsA(isA<TtsSynthesisException>()),
    );
  });
}