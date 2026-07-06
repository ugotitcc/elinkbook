import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。原生
/// 渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，不能直接
/// 讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到 [condition] 成立或逾時。`ReaderScreen` 對外只有 filePath
/// 一個建構參數（見 spec.md 的 seam 定義），onPageRendered/onError 是內部
/// 實作細節，因此本檔案用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

/// 判斷橫直排切換按鈕是否已就緒（存在且可點擊）。`onLayoutResolved` 觸發前
/// `_writingMode` 為 null，此時按鈕的 `onPressed` 亦為 null（見
/// reader_screen.dart 的 `_buildAppBarActions`），因此以此作為「自動偵測已
/// 完成」的觀察點。
bool _writingModeToggleReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_writing_mode_toggle'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    // 先確認載入指示器真的存在，才能保證下面「等它消失」是有意義的等待，
    // 而不是 Key 被改名/移除後，condition 從一開始就成立、測試沒等待就
    // silently 通過。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
    // 與 Issue 4 的 EpubReaderView 整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    // 先確認載入指示器真的存在，才能保證下面「等它消失」是有意義的等待，
    // 而不是 Key 被改名/移除後，condition 從一開始就成立、測試沒等待就
    // silently 通過。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    // 5 秒逾時：PdfRenderer 為同步點陣圖渲染，與 Issue 3 的 PdfReaderView
    // 整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('開啟直排 CJK 範例 EPUB，切換按鈕啟用且提示切換為橫排',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_toggle_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_writing_mode_toggle')),
    );
    expect(button.tooltip, '切換為橫排');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟英文範例 EPUB，切換按鈕啟用且提示切換為直排', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_horizontal.epub', 'sample_toggle_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_writing_mode_toggle')),
    );
    expect(button.tooltip, '切換為直排');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟定樣式範例 EPUB，切換按鈕最終不顯示', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_toggle_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () =>
          _loadingIndicatorGone() &&
          find.byKey(const Key('reader_writing_mode_toggle')).evaluate().isEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('點擊切換按鈕後，提示文字反轉且不觸發錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_toggle_tap.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_writing_mode_toggle')))
          .tooltip,
      '切換為橫排',
    );

    await tester.tap(find.byKey(const Key('reader_writing_mode_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_writing_mode_toggle')))
          .tooltip,
      '切換為直排',
    );
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
