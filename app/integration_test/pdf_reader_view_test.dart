import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// PdfRenderer 需要真實的裝置檔案系統路徑，不能直接讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效 PDF 檔案觸發 onPageRendered', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');

    // 用 Completer 等待原生端的非同步 callback，callback 一觸發就立刻往下走，
    // 不需要固定等待一段時間。注意：pumpAndSettle 的參數是「每次 pump 之間
    // 的間隔」，不是「總等待時間」，不能拿來當作 timeout 使用。
    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟不存在的檔案路徑觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: missingPath,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });
}
