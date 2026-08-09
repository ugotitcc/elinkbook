import 'package:flutter/material.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_selection_geometry.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('percentRectFromDrag', () {
    test('由左上拖到右下，正確換算為百分比矩形', () {
      final rect = percentRectFromDrag(
        start: const Offset(20, 40),
        end: const Offset(80, 160),
        areaSize: const Size(100, 200),
      );
      expect(rect, const PercentRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8));
    });

    test('拖曳方向為右下到左上（反向拖曳）時仍正確正規化，left<right、top<bottom', () {
      final rect = percentRectFromDrag(
        start: const Offset(80, 160),
        end: const Offset(20, 40),
        areaSize: const Size(100, 200),
      );
      expect(rect, const PercentRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8));
    });

    test('拖曳範圍超出頁面邊界時夾限到 [0,1]', () {
      final rect = percentRectFromDrag(
        start: const Offset(-50, -50),
        end: const Offset(150, 250),
        areaSize: const Size(100, 200),
      );
      expect(rect, const PercentRect(left: 0, top: 0, right: 1, bottom: 1));
    });

    test('寬度或高度小於 minFraction 時視為退化選取（長按未拖曳），回傳 null', () {
      final rect = percentRectFromDrag(
        start: const Offset(50, 100),
        end: const Offset(50.5, 100.5),
        areaSize: const Size(100, 200),
      );
      expect(rect, isNull);
    });

    test('剛好等於 minFraction 邊界時視為有效選取（非退化）', () {
      final rect = percentRectFromDrag(
        start: const Offset(0, 0),
        end: const Offset(1, 2), // 100 * 0.01 = 1, 200 * 0.01 = 2
        areaSize: const Size(100, 200),
        minFraction: 0.01,
      );
      expect(rect, isNotNull);
    });
  });

  group('cropRelativeToOriginalPercent', () {
    test('cropRect 為 null 時原樣回傳（單位轉換，不裁切）', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      expect(cropRelativeToOriginalPercent(rect: rect, cropRect: null), rect);
    });

    test('裁切啟用時，把「相對裁切後內容」的矩形換算回「相對原始整頁」', () {
      // 裁切範圍是原頁的 [0.25, 0.1]-[0.75, 0.9]（寬 0.5、高 0.8）。
      // 使用者在裁切後畫面正中央（0.5,0.5）拖出一個佔滿一半寬高的矩形。
      const cropRect = PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
      const draggedRect = PercentRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75);
      final result = cropRelativeToOriginalPercent(rect: draggedRect, cropRect: cropRect);
      // left = 0.25 + 0.25*0.5 = 0.375；right = 0.25 + 0.75*0.5 = 0.625
      // top  = 0.1  + 0.25*0.8 = 0.3 ； bottom = 0.1 + 0.75*0.8 = 0.7
      expect(result.left, closeTo(0.375, 1e-9));
      expect(result.top, closeTo(0.3, 1e-9));
      expect(result.right, closeTo(0.625, 1e-9));
      expect(result.bottom, closeTo(0.7, 1e-9));
    });

    test('裁切後畫面的整個範圍（0,0,1,1）換算回原始頁面時等於裁切矩形本身', () {
      const cropRect = PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
      const fullDrag = PercentRect(left: 0, top: 0, right: 1, bottom: 1);
      final result = cropRelativeToOriginalPercent(rect: fullDrag, cropRect: cropRect);
      expect(result.left, closeTo(cropRect.left, 1e-9));
      expect(result.top, closeTo(cropRect.top, 1e-9));
      expect(result.right, closeTo(cropRect.right, 1e-9));
      expect(result.bottom, closeTo(cropRect.bottom, 1e-9));
    });
  });

  group('originalToCropRelativePercent（正轉換的反向：渲染既有標記時使用）', () {
    test('cropRect 為 null 時原樣回傳', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      expect(originalToCropRelativePercent(rect: rect, cropRect: null), rect);
    });

    test('與 cropRelativeToOriginalPercent 互為反函式', () {
      const cropRect = PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
      const original = PercentRect(left: 0.375, top: 0.3, right: 0.625, bottom: 0.7);
      final cropRelative = originalToCropRelativePercent(rect: original, cropRect: cropRect);
      expect(cropRelative, isNotNull);
      expect(cropRelative!.left, closeTo(0.25, 1e-9));
      expect(cropRelative.top, closeTo(0.25, 1e-9));
      expect(cropRelative.right, closeTo(0.75, 1e-9));
      expect(cropRelative.bottom, closeTo(0.75, 1e-9));
    });

    test('標記完全落在裁切範圍外時回傳 null（呼叫端應跳過渲染）', () {
      const cropRect = PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
      const original = PercentRect(left: 0, top: 0, right: 0.1, bottom: 0.05);
      expect(originalToCropRelativePercent(rect: original, cropRect: cropRect), isNull);
    });

    test('標記與裁切範圍部分重疊時，換算結果被夾限到 [0,1] 內（部分可見）', () {
      const cropRect = PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
      // 標記橫跨裁切左邊界：原始座標 0.1-0.4，裁切左邊界是 0.25。
      const original = PercentRect(left: 0.1, top: 0.3, right: 0.4, bottom: 0.5);
      final result = originalToCropRelativePercent(rect: original, cropRect: cropRect);
      expect(result, isNotNull);
      expect(result!.left, 0); // 夾限到裁切區域左邊界。
      expect(result.right, closeTo(0.3, 1e-9)); // (0.4-0.25)/0.5 = 0.3
    });
  });
}
