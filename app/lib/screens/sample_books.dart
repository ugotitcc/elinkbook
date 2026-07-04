import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../reader/book_format.dart';

/// 書架佔位畫面用的固定範例書籍項目。真正的圖書庫管理（匯入、詮釋資料、
/// 封面產生）屬於 epic-1-library；這裡只是讓「點開一本書」在 epic-0-skeleton
/// 的骨架驗證範圍內，能從 App 正常入口（書架）觸發，而非測試專用的硬編碼
/// 呼叫。
class SampleBook {
  final String title;
  final String assetPath;
  final String fileName;
  final BookFormat format;

  const SampleBook({
    required this.title,
    required this.assetPath,
    required this.fileName,
    required this.format,
  });
}

const sampleBooks = <SampleBook>[
  SampleBook(
    title: '範例 EPUB 書籍',
    assetPath: 'test/fixtures/sample.epub',
    fileName: 'sample.epub',
    format: BookFormat.epub,
  ),
  SampleBook(
    title: '範例 PDF 文件',
    assetPath: 'test/fixtures/sample.pdf',
    fileName: 'sample.pdf',
    format: BookFormat.pdf,
  ),
];

/// 把範例書籍的 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對
/// 路徑。原生渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，
/// 不能直接讀取 Flutter asset，因此書架點擊範例書籍時，必須先做這一步才能
/// 呼叫 ReaderScreen(filePath: ...)。
Future<String> stageSampleBookFile(SampleBook book) async {
  final bytes = await rootBundle.load(book.assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/${book.fileName}');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}
