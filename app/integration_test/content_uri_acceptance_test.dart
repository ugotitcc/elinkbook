import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import '../test/support/pump_localized_widget.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

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
      '真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'content_uri_sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 這兩步驟模擬真實匯入流程：file_picker 回傳一個已有 SAF 授權的
    // content:// URI（此處用 FileProvider + 自我授權模擬，見 Step 5 的
    // createTestContentUri），接著呼叫 takePersistableUriPermission 持久化
    // 該授權——與 Task 3 的 BookImportServiceImpl 真實流程一致。
    final contentUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue,
        reason: '必須是真正的 content:// URI，而非 file://（Issue 3 已驗證過 file://，'
            '本測試要驗證的是不同的內部程式碼路徑）');

    await _metadataChannel.invokeMethod<void>(
        'takePersistableUriPermission', {'uri': contentUri});

    final completer = Completer<void>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: contentUri,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });
}
