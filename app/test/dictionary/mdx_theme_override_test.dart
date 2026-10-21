// MDX 深色與 E-Ink 配色覆寫（epic-63 Issue 6b Task 4）。
import 'dart:math' as math;
import 'package:elinkbook/dictionary/mdx_theme_override.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _relativeLuminance(Color color) {
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

double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('MdxColors 相等性', () {
    test('相同欄位的兩個實例 == 為真且 hashCode 相等', () {
      const a = MdxColors(
        background: Color(0xFF112233),
        foreground: Color(0xFF445566),
        link: Color(0xFF778899),
        underlineLinks: true,
      );
      const b = MdxColors(
        background: Color(0xFF112233),
        foreground: Color(0xFF445566),
        link: Color(0xFF778899),
        underlineLinks: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('不同欄位的兩個實例 == 為假', () {
      const a = MdxColors(
        background: Color(0xFF112233),
        foreground: Color(0xFF445566),
        link: Color(0xFF778899),
        underlineLinks: true,
      );
      const b = MdxColors(
        background: Color(0xFF112233),
        foreground: Color(0xFF445566),
        link: Color(0xFF778899),
        underlineLinks: false,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('mdxColorsFor', () {
    final darkTheme = ThemeData.dark();
    final lightTheme = ThemeData.light();

    test('E-Ink 模式（任何亮度）回傳黑字白底且底線為真', () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final colors = mdxColorsFor(
          isEinkMode: true,
          brightness: brightness,
          scheme: brightness == Brightness.dark
              ? darkTheme.colorScheme
              : lightTheme.colorScheme,
        );
        expect(colors, isNotNull);
        expect(colors!.background, const Color(0xFFFFFFFF));
        expect(colors.foreground, const Color(0xFF000000));
        expect(colors.link, const Color(0xFF000000));
        expect(colors.underlineLinks, isTrue);
      }
    });

    test('深色非 E-Ink 取自 ColorScheme', () {
      final scheme = darkTheme.colorScheme;
      final colors = mdxColorsFor(
        isEinkMode: false,
        brightness: Brightness.dark,
        scheme: scheme,
      );
      expect(colors, isNotNull);
      expect(colors!.background, scheme.surface);
      expect(colors.foreground, scheme.onSurface);
      expect(colors.link, scheme.primary);
      expect(colors.underlineLinks, isFalse);
    });

    test('淺色非 E-Ink 回傳 null', () {
      final scheme = lightTheme.colorScheme;
      final colors = mdxColorsFor(
        isEinkMode: false,
        brightness: Brightness.light,
        scheme: scheme,
      );
      expect(colors, isNull);
    });
  });

  group('mdxOverrideCss', () {
    test('輸出含 !important、小寫六碼色碼與各元素規則', () {
      const colors = MdxColors(
        background: Color(0xFF1A1B1C),
        foreground: Color(0xFFE1E2E3),
        link: Color(0xFF4A90E2),
        underlineLinks: false,
      );
      final css = mdxOverrideCss(colors);

      expect(
        css,
        contains('html,body{background:#1a1b1c !important;color:#e1e2e3 !important}'),
      );
      expect(
        css,
        contains('*{color:#e1e2e3 !important;background-color:transparent !important;border-color:#e1e2e3 !important}'),
      );
      expect(css, contains('a{color:#4a90e2 !important}'));
      expect(css, isNot(contains('text-decoration:underline')));
      expect(
        css,
        contains('img{background-color:#ffffff !important;max-width:100% !important;height:auto}'),
      );
      expect(
        RegExp(r'img\{[^}]*background-color:\s*#ffffff\s*!important').hasMatch(css),
        isTrue,
      );
    });

    test('underlineLinks 為真時加 text-decoration:underline !important', () {
      const colors = MdxColors(
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF000000),
        link: Color(0xFF000000),
        underlineLinks: true,
      );
      final css = mdxOverrideCss(colors);
      expect(
        css,
        contains('a{color:#000000 !important;text-decoration:underline !important}'),
      );
    });
  });

  group('對比可讀性 (WCAG AA >= 4.5)', () {
    test('E-Ink 色彩對比 >= 4.5', () {
      final colors = mdxColorsFor(
        isEinkMode: true,
        brightness: Brightness.light,
        scheme: ThemeData.light().colorScheme,
      )!;
      final cr = _contrastRatio(colors.foreground, colors.background);
      expect(cr, greaterThanOrEqualTo(4.5));
    });

    test('深色色彩對比 >= 4.5', () {
      final colors = mdxColorsFor(
        isEinkMode: false,
        brightness: Brightness.dark,
        scheme: ThemeData.dark().colorScheme,
      )!;
      final cr = _contrastRatio(colors.foreground, colors.background);
      expect(cr, greaterThanOrEqualTo(4.5));
    });
  });
}
