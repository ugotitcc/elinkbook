import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

ElinkTokens _tokensOf(ThemeData theme) => theme.extension<ElinkTokens>()!;

List<Color> _levels(ElinkTokens t) => [
      t.heatmapLevel0,
      t.heatmapLevel1,
      t.heatmapLevel2,
      t.heatmapLevel3,
      t.heatmapLevel4,
    ];

void main() {
  group('四套主題的五級色值（epic.md Issue 1 定案表）', () {
    test('Light', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.light))), const [
        Color(0xFFEAF1F5),
        Color(0xFFBAE6FD),
        Color(0xFF7DD3FC),
        Color(0xFF38BDF8),
        Color(0xFF0284C7),
      ]);
    });

    test('Dark', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.dark))), const [
        Color(0xFF2C2C34),
        Color(0xFF0C4A6E),
        Color(0xFF0369A1),
        Color(0xFF0EA5E9),
        Color(0xFF7DD3FC),
      ]);
    });

    test('Sepia', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.sepia))), const [
        Color(0xFFE6DFCB),
        Color(0xFFEFD3C4),
        Color(0xFFDEA08E),
        Color(0xFFC85F4F),
        Color(0xFFB8362D),
      ]);
    });

    test('E-Ink：階梯灰階', () {
      expect(_levels(_tokensOf(buildEinkThemeData())), const [
        Color(0xFFFFFFFF),
        Color(0xFFD4D4D4),
        Color(0xFFA3A3A3),
        Color(0xFF525252),
        Color(0xFF000000),
      ]);
    });
  });

  test('四套主題各自的五級色值彼此不同（E-Ink 灰階可區分，不依賴色相）', () {
    for (final theme in [
      buildThemeData(AppTheme.light),
      buildThemeData(AppTheme.dark),
      buildThemeData(AppTheme.sepia),
      buildEinkThemeData(),
    ]) {
      expect(_levels(_tokensOf(theme)).toSet().length, 5);
    }
  });

  test('Dark 第 0 級與深色底 surface 可區分（0 級方格看得見）', () {
    final theme = buildThemeData(AppTheme.dark);
    expect(_tokensOf(theme).heatmapLevel0, isNot(theme.colorScheme.surface));
  });

  test('E-Ink 灰階由淺到深單調遞減', () {
    final levels = _levels(_tokensOf(buildEinkThemeData()));
    final lum = [for (final c in levels) c.computeLuminance()];
    for (var i = 1; i < lum.length; i++) {
      expect(lum[i], lessThan(lum[i - 1]));
    }
  });

  test('heatmapLevelColor 依級別取值，超出 0–4 拋 RangeError', () {
    final t = _tokensOf(buildThemeData(AppTheme.light));
    for (var i = 0; i < 5; i++) {
      expect(t.heatmapLevelColor(i), _levels(t)[i]);
    }
    expect(() => t.heatmapLevelColor(5), throwsRangeError);
    expect(() => t.heatmapLevelColor(-1), throwsRangeError);
  });

  test('copyWith 只覆寫指定的色階欄位；lerp 在 t=0.5 走 Color.lerp', () {
    final light = _tokensOf(buildThemeData(AppTheme.light));
    final dark = _tokensOf(buildThemeData(AppTheme.dark));
    final copy = light.copyWith(heatmapLevel3: const Color(0xFF123456));
    expect(copy.heatmapLevel3, const Color(0xFF123456));
    expect(copy.heatmapLevel0, light.heatmapLevel0);
    expect(copy.heatmapLevel4, light.heatmapLevel4);

    final mid = light.lerp(dark, 0.5);
    expect(mid.heatmapLevel2,
        Color.lerp(light.heatmapLevel2, dark.heatmapLevel2, 0.5));
  });
}
