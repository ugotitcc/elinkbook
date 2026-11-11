import 'dart:io';

import 'package:crypto/crypto.dart';
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

  testWidgets('extractMetadata 收到 epub 格式回 unsupported_format',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await expectLater(
      () => _channel.invokeMapMethod<String, Object?>(
        'extractMetadata',
        {'uri': samplePath, 'format': 'epub'},
      ),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'unsupported_format'),
      ),
    );
  });

  testWidgets('PDF 詮釋資料提取回傳非空的 coverBytes', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!['coverBytes'], isNotNull);
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
  });

  testWidgets('不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException',
      (tester) async {
    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await expectLater(
      () => _channel.invokeMapMethod<String, Object?>(
        'extractMetadata',
        {'uri': missingPath, 'format': 'pdf'},
      ),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'extraction_failed'),
      ),
    );
  });

  testWidgets('以 file:// URI 表示路徑呼叫 extractMetadata（PDF）同樣回傳非空結果',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': uriPath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!['coverBytes'], isNotNull);
  });

  testWidgets('PDF 呼叫 extractMetadata 時，回應 map 沒有 identifier 鍵', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_id.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!.containsKey('identifier'), isFalse);
  });

  testWidgets('computeSha256 對本機檔案路徑計算結果與獨立計算的參考雜湊值一致',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_hash.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final expected =
        sha256.convert(await File(samplePath).readAsBytes()).toString();

    final result = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': samplePath},
    );

    expect(result, expected);
  });

  testWidgets('computeSha256 對真正的 content:// URI 計算結果與本機路徑計算結果一致',
      (tester) async {
    // createTestContentUri 僅供 integration_test 使用（見該原生方法註解），
    // 把裝置上真實檔案路徑轉為 content:// URI，模擬 SAF 回傳的路徑型態。
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_hash_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final contentUri = await _channel.invokeMethod<String>(
      'createTestContentUri',
      {'path': samplePath},
    );
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue);

    final expectedFromPath = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': samplePath},
    );
    final resultFromContentUri = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': contentUri},
    );

    expect(resultFromContentUri, expectedFromPath);
  });

  testWidgets('computeSha256 對不存在的檔案路徑拋出 PlatformException', (tester) async {
    final missingPath =
        '/data/local/tmp/does_not_exist_hash_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await expectLater(
      () => _channel.invokeMethod<String>('computeSha256', {'uri': missingPath}),
      throwsA(isA<PlatformException>()),
    );
  });
}
