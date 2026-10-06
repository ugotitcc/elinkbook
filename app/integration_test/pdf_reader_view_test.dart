import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import '../test/support/pump_localized_widget.dart';

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

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
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

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
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
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });

  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯（openParcelFileDescriptor
  // 對 file:// 與 content:// 走的是完全相同的程式碼路徑）。真正 content://
  // URI 的 SAF 權限情境（takePersistableUriPermission）留待 Issue 4 匯入
  // 服務的手動驗收步驟做端到端驗證，本測試不涵蓋。
  testWidgets('開啟以 file:// URI 表示的有效 PDF 檔案觸發 onPageRendered',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final completer = Completer<void>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: uriPath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟指向不存在資源的 content:// URI 觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingUri =
        'content://cc.ugotit.elinkbook.does_not_exist/${DateTime.now().millisecondsSinceEpoch}.pdf';

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: missingUri,
        onPageRendered: () {
          rendered = true;
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });
}
