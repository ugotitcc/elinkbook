import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// 比照 app/integration_test/epub_reader_view_test.dart 既有的
/// _stageAssetAsFile 手法。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效的流式 EPUB 檔案觸發 onPageRendered', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
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

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟不存在的檔案路徑（但落在允許目錄內）觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final tempDir = await getTemporaryDirectory();
    final missingPath =
        '${tempDir.path}/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
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

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse);
    expect(errorMessage, isNotNull);
  });

  testWidgets(
      'PathHandler 路徑穿越防護：開啟允許目錄之外的檔案路徑觸發 onError（不會被當作合法書籍開啟）',
      (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    // /data/local/tmp 是裝置上真實存在、但不屬於本 App 私有文件目錄
    // （Context.filesDir）的路徑，驗證 FoliatePathValidator 的目錄邊界
    // 檢查會在真機上正確擋下這類請求，而不是被 File I/O 意外允許。
    const outsidePath =
        '/data/local/tmp/foliate_path_traversal_probe_should_not_open.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: outsidePath,
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

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse,
        reason: 'PathHandler 的目錄邊界檢查應該拒絕這個請求，不應該渲染成功');
    expect(errorMessage, contains('允許的目錄範圍'));
  });
}
