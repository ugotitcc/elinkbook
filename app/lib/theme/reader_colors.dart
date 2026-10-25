import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 閱讀器自訂背景色與文字色值物件（epic-65 Issue 2）。
///
/// 各自為 nullable：`background == null` 代表退回佈景原色（`scaffoldBackgroundColor`），
/// `text == null` 代表退回佈景原色（`colorScheme.onSurface`）。
@immutable
class ReaderColors {
  final Color? background;
  final Color? text;

  const ReaderColors({this.background, this.text});

  static const ReaderColors empty = ReaderColors();

  /// 產生新實例並替換背景色；傳入 `null` 即清除自訂背景色，退回佈景原色。
  ReaderColors withBackground(Color? c) => ReaderColors(background: c, text: text);

  /// 產生新實例並替換文字色；傳入 `null` 即清除自訂文字色，退回佈景原色。
  ReaderColors withText(Color? c) => ReaderColors(background: background, text: c);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderColors &&
          runtimeType == other.runtimeType &&
          background == other.background &&
          text == other.text;

  @override
  int get hashCode => Object.hash(background, text);

  @override
  String toString() => 'ReaderColors(background: $background, text: $text)';
}

final _hexColorRegex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 解析 6 位十六進制色碼字串（大小寫皆可，必須以 `#` 開頭，例如 `#FFFFFF`、`#ff8800`）。
/// 格式不合者一律安全回傳 `null`，不拋出例外。
Color? parseHexColor(String input) {
  if (!_hexColorRegex.hasMatch(input)) {
    return null;
  }
  final value = int.tryParse(input.substring(1), radix: 16);
  if (value == null) {
    return null;
  }
  return Color(0xFF000000 | value);
}

/// 將顏色轉換為大寫 `#RRGGBB` 色碼字串（忽略 Alpha，固定輸出 6 位十六進制大寫）。
String formatHexColor(Color c) {
  final argb = c.toARGB32();
  final rgb = argb & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 依據 WCAG 2.1 規範計算兩顏色之間的對比度：
/// `(L1 + 0.05) / (L2 + 0.05)`，其中 L1 為較亮色的相對明度（0.0～1.0）。
double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}
