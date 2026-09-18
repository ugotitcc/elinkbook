import 'package:flutter/material.dart';

import '../../reader/text_conversion_mode.dart';

/// 簡繁轉換文字示意圖示（繁轉簡／簡轉繁）。
///
/// 取代語意不相符的通用翻譯圖示（[Icons.translate]、[Icons.g_translate]），
/// 直接以「简 → 繁」與「繁 → 简」微型圖標呈現轉換方向，
/// 並自動繼承當前 [IconTheme] 或 [DefaultTextStyle] 的前景色彩與尺寸。
class TextConversionIcon extends StatelessWidget {
  final TextConversionMode mode;
  final double? size;
  final Color? color;
  final bool showBorder;

  const TextConversionIcon({
    super.key,
    required this.mode,
    this.size,
    this.color,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;

    final effectiveSize = size ?? IconTheme.of(context).size ?? 20.0;

    if (mode == TextConversionMode.original) {
      return Icon(
        Icons.article_outlined,
        size: effectiveSize,
        color: effectiveColor,
      );
    }

    final String sourceChar;
    final String targetChar;
    if (mode == TextConversionMode.toTraditional) {
      sourceChar = '简';
      targetChar = '繁';
    } else {
      sourceChar = '繁';
      targetChar = '简';
    }

    final fontSize = (effectiveSize * 0.52).clamp(9.0, 13.0);
    final arrowSize = (effectiveSize * 0.45).clamp(8.0, 12.0);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          sourceChar,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
            color: effectiveColor,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Icon(
            Icons.arrow_forward,
            size: arrowSize,
            color: effectiveColor,
          ),
        ),
        Text(
          targetChar,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
            color: effectiveColor,
          ),
        ),
      ],
    );

    if (!showBorder) {
      return content;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 1.5),
      decoration: BoxDecoration(
        border: Border.all(
          color: effectiveColor.withValues(alpha: 0.8),
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: content,
    );
  }
}
