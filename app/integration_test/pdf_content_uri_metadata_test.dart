import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      // docs/epics/epic-21-pdf-import-cover-fix/issues.md Issue 1：既有
      // book_metadata_channel_test.dart 只驗證過純檔案路徑／file:// URI，
      // 真實「匯入書籍」UI 流程對權限核發成功的 content:// URI 完全沒有
      // 測試涵蓋，本測試比照 content_uri_acceptance_test.dart 對 EPUB 的
      // 做法補上這塊空白，用 sample.pdf 精準判定卡住的是否是這條分支。
      '真正的 content:// SAF URI（透過 FileProvider 授權）呼叫 extractMetadata（PDF）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'content_uri_sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final contentUri = await _channel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue,
        reason: '必須是真正的 content:// URI，而非 file://（既有測試已驗證過 file://，'
            '本測試要驗證的是不同的內部程式碼路徑）');

    await _channel.invokeMethod<void>(
        'takePersistableUriPermission', {'uri': contentUri});

    // 刻意加上有界逾時：若原生端真的卡住不回應，測試要在合理時間內失敗並
    // 報告「TimeoutException」，而不是讓測試跑者無限期掛起。
    final result = await _channel
        .invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': contentUri, 'format': 'pdf'},
        )
        .timeout(const Duration(seconds: 20));

    expect(result, isNotNull);
    expect(result!['coverBytes'], isNotNull);
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
  });
}
