import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import '../test/support/pump_localized_widget.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// 比照 app/integration_test/foliate_epub_reader_view_test.dart 既有的
/// _stageAssetAsFile 手法。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 18 Issue 4：直排上下邊距——真機 smoke test。
///
/// 本檔案**不能**驗證「文字是否真的沒被裁切」這類視覺結果（`main.js` 的
/// `setAttribute` 呼叫無法從 Dart 端讀回渲染後的實際邊距，見
/// plan-issue-4.md Global Constraints），只驗證：不同 writingMode／
/// pageMargins／showFooter 組合下，main.js 新增的 setAttribute 呼叫本身
/// 不會拋出例外、不會導致開書失敗（onError）。實際視覺效果由
/// plan-issue-4.md Task 4 的真機人工確認負責。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('直排、預設 pageMargins／showFooter（皆省略）開書不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_default.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        writingMode: WritingMode.vertical,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });

  testWidgets('直排、自訂 pageMargins 且 showFooter=false（隱藏頁尾分支）開書不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_hidden_footer.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        writingMode: WritingMode.vertical,
        marginTop: 1.6667,
        marginBottom: 1.6667,
        marginLeft: 1.6667,
        marginRight: 1.6667,
        showFooter: false,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });

  testWidgets('橫排（還原預設邊距分支）開書不崩潰', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        writingMode: WritingMode.horizontal,
        showFooter: true,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });
}
