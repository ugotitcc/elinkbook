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

  testWidgets('EPUB 詮釋資料提取回傳非空的 title 與 coverBytes', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['title'], isNotNull);
    expect((result['title'] as String).isNotEmpty, isTrue);
    expect(result['coverBytes'], isNotNull);
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
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
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await expectLater(
      () => _channel.invokeMapMethod<String, Object?>(
        'extractMetadata',
        {'uri': missingPath, 'format': 'epub'},
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  // 以下兩項驗證 uri 參數走「URI 分支」（而非純檔案路徑）時同樣能提取成功。
  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯；真正 content:// URI
  // 的 SAF 權限情境（takePersistableUriPermission），由 Issue 4 匯入服務
  // 的手動驗收步驟做端到端驗證。
  testWidgets('以 file:// URI 表示路徑呼叫 extractMetadata（EPUB）同樣回傳非空結果',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_uri.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': uriPath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['title'], isNotNull);
    expect(result['coverBytes'], isNotNull);
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
}
