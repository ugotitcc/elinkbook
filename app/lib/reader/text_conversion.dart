import 'text_conversion_dict.dart';
import 'text_conversion_mode.dart';

/// 依 [mode] 對 [input] 做簡繁字元轉換。[TextConversionMode.original] 原樣
/// 回傳；查找表（[kS2tDict]／[kT2sDict]，`app/tool/generate_conversion_
/// dicts.js` 產出）內找不到的字元維持原樣，不視為錯誤。逐字元查表替換，
/// 保證輸出與輸入的 UTF-16 長度與 code point 數量恆相同（ADR 0030：
/// ΔL=0，保護 CFI 座標系；查找表本身已在生成階段排除會破壞這個不變量的
/// BMP↔輔助平面字元配對，見 `generate_conversion_dicts.js` 的
/// `parseCharTable()`）。
String convertText(String input, TextConversionMode mode) {
  // 審查修正 I-1：空字串／original 模式提早返回，避免不必要的
  // StringBuffer 配置與 runes 走訪。
  if (mode == TextConversionMode.original || input.isEmpty) return input;
  final dict = mode == TextConversionMode.toTraditional ? kS2tDict : kT2sDict;
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(dict[ch] ?? ch);
  }
  return buffer.toString();
}
