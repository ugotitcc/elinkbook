// app/test/support/wcag_contrast.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 相對亮度（sRGB）。
double relativeLuminance(Color color) {
  double transform(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = transform(color.r);
  final g = transform(color.g);
  final b = transform(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// 兩個顏色的 WCAG 對比值（1 到 21）；一般文字至少要 4.5。
double contrastRatio(Color c1, Color c2) {
  final l1 = relativeLuminance(c1);
  final l2 = relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}
