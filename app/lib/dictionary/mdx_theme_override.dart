// MDX 深色與 E-Ink 配色覆寫（epic-63 Issue 6b Task 4）。
import 'package:flutter/material.dart';

/// MDX 詞條在特定主題模式下的覆寫色彩配置。
class MdxColors {
  final Color background;
  final Color foreground;
  final Color link;
  final bool underlineLinks;

  const MdxColors({
    required this.background,
    required this.foreground,
    required this.link,
    required this.underlineLinks,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdxColors &&
          runtimeType == other.runtimeType &&
          background == other.background &&
          foreground == other.foreground &&
          link == other.link &&
          underlineLinks == other.underlineLinks;

  @override
  int get hashCode => Object.hash(
        background,
        foreground,
        link,
        underlineLinks,
      );
}

/// 依目前的 E-Ink 模式、亮度與色彩架構，決定詞條是否需要色彩覆寫及相應顏色。
///
/// 規格：
/// - E-Ink 模式（任何亮度）：白底黑字、連結同黑加底線以確保電子墨水屏對比與可辨識度。
/// - 深色模式（非 E-Ink）：取自 [scheme] 的 `surface`、`onSurface` 與 `primary`。
/// - 淺色模式（非 E-Ink）：回傳 `null`，使用字典原生樣式或瀏覽器預設樣式。
MdxColors? mdxColorsFor({
  required bool isEinkMode,
  required Brightness brightness,
  required ColorScheme scheme,
}) {
  if (isEinkMode) {
    return const MdxColors(
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF000000),
      link: Color(0xFF000000),
      underlineLinks: true,
    );
  }
  if (brightness == Brightness.dark) {
    return MdxColors(
      background: scheme.surface,
      foreground: scheme.onSurface,
      link: scheme.primary,
      underlineLinks: false,
    );
  }
  return null;
}

String _toHex(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').toLowerCase();
  return '#${hex.substring(2)}';
}

/// 產生注入詞條 HTML 的 CSS 覆寫樣式字串（不含 `<style>` 外殼）。
///
/// 規格：
/// 1. `html,body` 設定背景與文字顏色（帶 `!important`）。
/// 2. `*` 全域選擇器覆寫文字色、邊框色，並將背景色設為透明（帶 `!important`），
///    以蓋過字典內嵌或行內的寫死配色。
/// 3. `a` 標籤設定連結顏色，若 [MdxColors.underlineLinks] 為真則強制加上底線。
/// 4. `img` 標籤強制保留白底（`background-color:#ffffff !important`），避免黑線透明底圖檔
///    在深色模式下隱形；同時限制最大寬度為 100% 保持響應式。
String mdxOverrideCss(MdxColors colors) {
  final bg = _toHex(colors.background);
  final fg = _toHex(colors.foreground);
  final link = _toHex(colors.link);
  final aRule = colors.underlineLinks
      ? 'a{color:$link !important;text-decoration:underline !important}'
      : 'a{color:$link !important}';

  return 'html,body{background:$bg !important;color:$fg !important}'
      '*{color:$fg !important;background-color:transparent !important;border-color:$fg !important}'
      '$aRule'
      'img{background-color:#ffffff !important;max-width:100% !important;height:auto}';
}
