import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// Readium 的 AssetRetriever 需要真實的裝置檔案系統路徑，不能直接讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效 EPUB 檔案觸發 onPageRendered', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    // 清掉暫存目錄裡複製出來的測試檔，避免裝置上的暫存空間隨著測試執行次數累積。
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 用 Completer 等待原生端的非同步 callback，callback 一觸發就立刻往下走，
    // 不需要固定等待一段時間。注意：pumpAndSettle 的參數是「每次 pump 之間
    // 的間隔」，不是「總等待時間」，不能拿來當作 timeout 使用。
    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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

  testWidgets('開啟不存在的檔案路徑觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });

  testWidgets('開啟內容已損毀的 EPUB 檔案觸發 onError', (tester) async {
    // 檔案存在但內容不是合法的 EPUB（甚至不是合法的 zip）——與前一項「不存在」的測試
    // 案例分屬不同的失敗分支：這一項會先通過 AssetRetriever.retrieve()（檔案讀得到），
    // 再於 PublicationOpener.open() 解析失敗，驗證的是不同的 onError 觸發路徑。
    final tempDir = await getTemporaryDirectory();
    final corruptedFile = File(
        '${tempDir.path}/corrupted_${DateTime.now().millisecondsSinceEpoch}.epub');
    await corruptedFile.writeAsBytes(
        List<int>.generate(256, (i) => i % 256), flush: true);
    addTearDown(() async {
      if (await corruptedFile.exists()) await corruptedFile.delete();
    });

    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: corruptedFile.path,
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

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });

  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯（resolveAbsoluteUrl 對
  // file:// 與 content:// 走的是完全相同的程式碼路徑）。真正 content://
  // URI 的 SAF 權限情境（takePersistableUriPermission）留待 Issue 4 匯入
  // 服務的手動驗收步驟做端到端驗證，本測試不涵蓋。
  testWidgets('開啟以 file:// URI 表示的有效 EPUB 檔案觸發 onPageRendered',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample_uri.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: uriPath,
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

  testWidgets('開啟指向不存在資源的 content:// URI 觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingUri =
        'content://cc.ugotit.elinkbook.does_not_exist/${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });

  testWidgets('開啟直排 CJK 範例 EPUB，onLayoutResolved 回報直排且非定樣式',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_layout_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isFalse);
    expect(layoutInfo!.writingMode, WritingMode.vertical);
  });

  testWidgets('開啟英文範例 EPUB，onLayoutResolved 回報橫排', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_horizontal.epub', 'sample_layout_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isFalse);
    expect(layoutInfo!.writingMode, WritingMode.horizontal);
  });

  testWidgets('開啟定樣式範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_layout_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    EpubLayoutInfo? layoutInfo;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            if (!completer.isCompleted) completer.complete();
          },
          onLayoutResolved: (info) {
            layoutInfo = info;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(layoutInfo, isNotNull);
    expect(layoutInfo!.isFixedLayout, isTrue);
  });

  testWidgets('開書後呼叫 setWritingMode 切換橫直排，畫面持續渲染成功',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample_switch.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final renderedCompleter = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.vertical,
          onPageRendered: () {
            if (!renderedCompleter.isCompleted) renderedCompleter.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!renderedCompleter.isCompleted) renderedCompleter.complete();
          },
        ),
      ),
    );
    await renderedCompleter.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '初次開書應成功渲染，但 onError 訊息為: $errorMessage');

    // 重新 pump 同一個位置的 EpubReaderView 但改變 writingMode（filePath 不變，
    // Flutter 會重用既有 State 並呼叫 didUpdateWidget，觸發原生 setWritingMode，
    // 不會重新呼叫 openBook）。
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.horizontal,
          onPageRendered: () {},
          onError: (message) => errorMessage = message,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '切換為橫排後不應觸發 onError');

    // 再切換回直排，驗證來回切換皆穩定。
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          writingMode: WritingMode.vertical,
          onPageRendered: () {},
          onError: (message) => errorMessage = message,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '切換回直排後不應觸發 onError');
  });
}
