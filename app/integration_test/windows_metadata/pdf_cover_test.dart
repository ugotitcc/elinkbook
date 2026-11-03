// Windows PDF 封面產生測試（epic-66 Issue 2 Task 3）。
//
// 驗證 renderPdfCover() 能：
// - 正確使用 pdfrx 開啟 PDF 並渲染第 0 頁為 PNG 位元組；
// - 驗證 PNG 簽章 89 50 4E 47；
// - 限制最長邊不超過 600 px；
// - 檔案不存在時回傳 null。
//
// 執行方式：flutter test integration_test/windows_metadata/pdf_cover_test.dart -d windows

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:elinkbook/library/windows_pdf_cover.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renderPdfCover 正確產生 sample_multi_page.pdf 封面且尺寸符合規範', (
    tester,
  ) async {
    await pdfrxFlutterInitialize();

    final pdfPath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_page.pdf',
      'meta_pdf_sample_multi_page.pdf',
    );
    addTearDown(() async {
      final f = File(pdfPath);
      if (await f.exists()) await f.delete();
    });

    final bytes = await renderPdfCover(pdfPath, maxDimension: 600);
    expect(bytes, isNotNull, reason: '合法 PDF 第 0 頁應渲染成功');
    expect(bytes!.length, greaterThan(4));
    expect(
      bytes.sublist(0, 4),
      [0x89, 0x50, 0x4E, 0x47],
      reason: '開頭必須為 PNG 簽章 89 50 4E 47',
    );

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      expect(image.width, lessThanOrEqualTo(600));
      expect(image.height, lessThanOrEqualTo(600));
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
    } finally {
      image.dispose();
      codec.dispose();
    }

    final nonExistentBytes = await renderPdfCover(
      '${pdfPath}_non_existent.pdf',
      maxDimension: 600,
    );
    expect(nonExistentBytes, isNull, reason: '不存在之檔案應回傳 null');
  });
}
