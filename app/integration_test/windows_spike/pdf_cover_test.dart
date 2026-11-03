// PDF 開啟與渲染探針（epic-66 Issue 1 Task 10，過關條件 3）。
//
// 驗證 pdfrx（PDFium 經 dart:ffi 直接呼叫，非 PlatformView）在 Windows
// 桌面能：開啟本機 PDF、渲染第 0 頁、把渲染結果轉成 dart:ui.Image 再編碼
// 為 PNG 位元組（PNG 簽章 89 50 4E 47）。
//
// 執行：flutter test integration_test/windows_spike/pdf_cover_test.dart -d windows

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// 把 asset 複製為暫存目錄中的真實檔案（pdfrx 只吃檔案路徑，讀不到
/// rootBundle），比照 `integration_test/book_metadata_channel_test.dart`
/// 既有慣例。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pdfrx 開啟 sample_multi_page.pdf 並渲染第 0 頁為 PNG 位元組', (
    tester,
  ) async {
    // main.dart 啟動時的同一呼叫（見 lib/main.dart:113）；整合測試不經過
    // main()，必須自行初始化。
    await pdfrxFlutterInitialize();

    final pdfPath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_page.pdf',
      'spike_multi_page.pdf',
    );
    addTearDown(() async {
      final f = File(pdfPath);
      if (await f.exists()) await f.delete();
    });

    final document = await PdfDocument.openFile(pdfPath);
    addTearDown(() => document.dispose());

    // 先印出實際頁數供記錄（plan Task 10 Step 1），斷言值以該次執行確認。
    // ignore: avoid_print
    print('[pdf_cover] pages=${document.pages.length}');
    expect(
      document.pages.length,
      5,
      reason: 'sample_multi_page.pdf 已知頁數（執行時先印出再寫死）',
    );

    final page = document.pages[0];
    final rendered = await page.render(
      fullWidth: 100,
      fullHeight: page.height * (100 / page.width),
    );
    expect(rendered, isNotNull, reason: '第 0 頁渲染應有結果');
    try {
      final ui.Image image = await rendered!.createImage();
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull, reason: 'PNG 編碼應有結果');
        final pngBytes = byteData!.buffer.asUint8List();
        expect(pngBytes.length, greaterThan(4));
        expect(
          pngBytes.sublist(0, 4),
          [0x89, 0x50, 0x4E, 0x47],
          reason: 'PNG 簽章 89 50 4E 47',
        );
      } finally {
        image.dispose();
      }
    } finally {
      rendered!.dispose();
    }
  });
}
