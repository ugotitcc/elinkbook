import 'dart:typed_data';
import 'dart:ui' as ui;

/// 依書名文字動態產生 TXT 書籍的封面圖片（FR-27：TXT 沒有內嵌封面或首頁可
/// 渲染，改用書名文字合成一張正方形封面）。純 `dart:ui` 實作，不呼叫任何
/// 原生 book_metadata channel；背景色由書名首字的 code unit 決定（同一本書
/// 每次產生的封面一致，非隨機）。[isEinkMode] 為 `true` 時改為 E-Ink 友善的
/// 白底黑框黑字樣式（`spec.md`「寫死顏色遷移」txt_cover_generator.dart
/// 部分）——這是離線產生 PNG 的 `dart:ui` 純函式，不在 widget tree 內、沒有
/// `BuildContext` 可取 `Theme.of(context)`，直接吃 bool 比傳遞 `ElinkTokens`
/// 更單純，白／黑色值就地寫死 `ui.Color`，跟本函式其餘色盤做法一致。
Future<Uint8List> generateTxtCover(
  String title, {
  bool isEinkMode = false,
}) async {
  const size = 400.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));

  final backgroundPaint = ui.Paint()
    ..color = isEinkMode
        ? const ui.Color(0xFFFFFFFF)
        : _backgroundColorForTitle(title);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  if (isEinkMode) {
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = _einkBorderWidth;
    canvas.drawRect(
      const ui.Rect.fromLTWH(
        _einkBorderWidth / 2,
        _einkBorderWidth / 2,
        size - _einkBorderWidth,
        size - _einkBorderWidth,
      ),
      borderPaint,
    );
  }

  final firstChar = title.isNotEmpty ? title.substring(0, 1) : '?';
  final paragraphBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: size * 0.4),
  )
    ..pushStyle(
      ui.TextStyle(
        color: isEinkMode
            ? const ui.Color(0xFF000000)
            : const ui.Color(0xFFFFFFFF),
      ),
    )
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

/// E-Ink 模式外框寬度。`DESIGN.md`／`spec.md` 未指定精確數值，取與封面尺寸
/// （400×400）成比例、目視明顯可辨識的寬度；具體數值未經真機驗證，比照
/// Issue 3／Issue 7 既有慣例，留待下一輪真機驗證確認電子紙上的可辨識度。
const _einkBorderWidth = 8.0;

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
