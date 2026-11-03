// Windows PDF 封面渲染實作（epic-66 Issue 2 Task 3）。
//
// 利用 pdfrx（PDFium 透過 dart:ffi 直接呼叫）開啟本機 PDF，
// 將第 0 頁渲染為 PNG 位元組，並限制最長邊不超過 maxDimension（預設 600 px）。

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// 渲染 [path] PDF 檔案第 0 頁為 PNG 封面位元組。
///
/// 尺寸限制最長邊不超過 [maxDimension]（預設 600 px，不放大）。
/// 若檔案不存在或內部無任何頁面回傳 `null`；檔案損毀或載入失敗時拋出例外。
Future<Uint8List?> renderPdfCover(
  String path, {
  int maxDimension = 600,
}) async {
  final file = File(path);
  if (!await file.exists()) return null;

  final document = await PdfDocument.openFile(path);
  try {
    if (document.pages.isEmpty) return null;

    final page = document.pages[0];
    final scale = min(
      min(maxDimension / page.width, maxDimension / page.height),
      1.0,
    );
    final width = (page.width * scale).round().clamp(1, maxDimension);
    final height = (page.height * scale).round().clamp(1, maxDimension);

    final rendered = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (rendered == null) return null;

    try {
      final ui.Image image = await rendered.createImage();
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      rendered.dispose();
    }
  } finally {
    await document.dispose();
  }
}
