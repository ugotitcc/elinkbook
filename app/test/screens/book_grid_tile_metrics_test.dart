import 'dart:math' show sqrt;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/book_grid_tile_metrics.dart';

void main() {
  test('系統字級 1.0 倍（TextScaler.noScaling）時，回傳基準值 34.0', () {
    expect(gridTileFooterHeight(TextScaler.noScaling), 34.0);
  });

  test('線性縮放（TextScaler.linear）時，回傳依比例放大的高度', () {
    final result = gridTileFooterHeight(const TextScaler.linear(1.5));
    expect(result, closeTo(34.0 * 1.5, 0.001));
  });

  test(
      '非線性縮放曲線時，對書名／進度兩個字級分別呼叫 scale() 後相加，'
      '不等於把基準值 34.0 整體丟進 scale()（/diagnose 第七輪真機回報重現方式）',
      () {
    const scaler = _NonLinearTextScaler(1.5);
    final result = gridTileFooterHeight(scaler);
    final expected = (scaler.scale(kGridTileFooterTitleFontSize) +
            scaler.scale(kGridTileFooterProgressFontSize)) *
        kGridTileFooterLineHeightFactor;
    expect(result, expected);
    expect(result, isNot(closeTo(scaler.scale(34.0), 0.001)));
  });
}

/// 刻意「非線性」的測試用 TextScaler，比照
/// `test/screens/library_screen_test.dart` 既有的 `_NonLinearTextScaler`
/// 同一種設計（凹函式：`scale(A) + scale(B)` 恆大於 `scale(A + B)`），
/// 獨立複製一份而非共用同一個類別——這是純函式的獨立單元測試，刻意不
/// 依賴 `library_screen_test.dart`（widget test）內的測試替身，兩者測試
/// 對象不同（純函式 vs widget 渲染）。
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler(this.textScaleFactor);

  @override
  final double textScaleFactor;

  @override
  double scale(double fontSize) {
    if (textScaleFactor == 1.0) return fontSize;
    return fontSize + (textScaleFactor - 1.0) * 6.0 * sqrt(fontSize);
  }

  @override
  bool operator ==(Object other) =>
      other is _NonLinearTextScaler && other.textScaleFactor == textScaleFactor;

  @override
  int get hashCode => textScaleFactor.hashCode;
}
