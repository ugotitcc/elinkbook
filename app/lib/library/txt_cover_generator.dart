import 'dart:typed_data';
import 'dart:ui' as ui;

/// 依書名文字動態產生 TXT 書籍的封面圖片（FR-27：TXT 沒有內嵌封面或首頁可
/// 渲染，改用書名文字合成一張正方形封面）。純 `dart:ui` 實作，不呼叫任何
/// 原生 book_metadata channel；背景色由書名首字的 code unit 決定（同一本書
/// 每次產生的封面一致，非隨機）。
Future<Uint8List> generateTxtCover(String title) async {
  const size = 400.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));

  final backgroundPaint = ui.Paint()..color = _backgroundColorForTitle(title);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  final firstChar = title.isNotEmpty ? title.substring(0, 1) : '?';
  final paragraphBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: size * 0.4),
  )
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
    ..addText(firstChar);
  final paragraph = paragraphBuilder.build()
    ..layout(const ui.ParagraphConstraints(width: size));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(0, (size - paragraph.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

const _palette = [
  ui.Color(0xFF5C6BC0),
  ui.Color(0xFF26A69A),
  ui.Color(0xFFEF5350),
  ui.Color(0xFFFFA726),
  ui.Color(0xFF8D6E63),
  ui.Color(0xFF7E57C2),
];

ui.Color _backgroundColorForTitle(String title) {
  final index = title.isEmpty ? 0 : title.codeUnitAt(0) % _palette.length;
  return _palette[index];
}
