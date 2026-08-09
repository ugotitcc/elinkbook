import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_image_filters.dart';

void main() {
  // ── Task 1: 純函式單元測試（原本在 pdf_reader_view_filters_test.dart，
  // 依 plan File Structure 配置移回此檔案。）──

  group('contrastBrightnessColorMatrix', () {
    test('contrast=0, brightness=0 時為單位矩陣（無視覺變化）', () {
      final m = contrastBrightnessColorMatrix(contrast: 0, brightness: 0);
      expect(m, hasLength(20));
      expect(m, [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ]);
    });

    test('contrast=100 時對比度係數為 2.0（0-255 範圍公式）', () {
      final m = contrastBrightnessColorMatrix(contrast: 100, brightness: 0);
      expect(m[0], closeTo(2.0, 1e-9));
      expect(m[6], closeTo(2.0, 1e-9));
      expect(m[12], closeTo(2.0, 1e-9));
      expect(m[18], 1);
      expect(m[19], 0);
    });

    test('contrast=-100 時對比度係數為 0.0', () {
      final m = contrastBrightnessColorMatrix(contrast: -100, brightness: 0);
      expect(m[0], closeTo(0.0, 1e-9));
    });

    test('brightness=100 時平移量約 255（8-bit 全亮）', () {
      final m = contrastBrightnessColorMatrix(contrast: 0, brightness: 100);
      expect(m[4], closeTo(255, 1e-9));
      expect(m[9], closeTo(255, 1e-9));
      expect(m[14], closeTo(255, 1e-9));
    });

    test('brightness=-100 時平移量約 -255（8-bit 全暗）', () {
      final m = contrastBrightnessColorMatrix(contrast: 0, brightness: -100);
      expect(m[4], closeTo(-255, 1e-9));
    });
  });

  group('dilateBgraPixels', () {
    Uint8List makeSinglePixelDot() {
      final px = Uint8List(3 * 3 * 4);
      for (var i = 0; i < 9; i++) {
        px[i * 4 + 0] = 255;
        px[i * 4 + 1] = 255;
        px[i * 4 + 2] = 255;
        px[i * 4 + 3] = 255;
      }
      const centerIdx = (1 * 3 + 1) * 4;
      px[centerIdx + 0] = 0;
      px[centerIdx + 1] = 0;
      px[centerIdx + 2] = 0;
      return px;
    }

    test('radius=1 時中心黑點向外膨脹，全部 9 個像素皆變黑', () {
      final result =
          dilateBgraPixels(makeSinglePixelDot(), width: 3, height: 3, radius: 1);
      expect(result, hasLength(3 * 3 * 4));
      for (var i = 0; i < 9; i++) {
        expect(result[i * 4 + 0], 0, reason: 'pixel $i B channel');
        expect(result[i * 4 + 1], 0, reason: 'pixel $i G channel');
        expect(result[i * 4 + 2], 0, reason: 'pixel $i R channel');
      }
    });

    test('radius=0 時輸出等於輸入（無膨脹）', () {
      final input = makeSinglePixelDot();
      final result = dilateBgraPixels(input, width: 3, height: 3, radius: 0);
      expect(result, input);
    });

    test('每個輸出像素的 alpha 沿用自身原始 alpha，不受鄰域影響', () {
      final px = Uint8List(2 * 1 * 4);
      px[0] = 0; px[1] = 0; px[2] = 0; px[3] = 255;
      px[4] = 255; px[5] = 255; px[6] = 255; px[7] = 128;
      final result = dilateBgraPixels(px, width: 2, height: 1, radius: 1);
      expect(result[3], 255);
      expect(result[7], 128);
    });

    test('邊界像素以夾限方式處理（等同邊緣複製），不擲例外', () {
      expect(
        () => dilateBgraPixels(makeSinglePixelDot(), width: 3, height: 3, radius: 5),
        returnsNormally,
      );
    });
  });

  group('pageRenderScale', () {
    test('devicePixelRatio 落在 2.0-3.0 區間內時原值輸出', () {
      expect(pageRenderScale(2.5), 2.5);
    });

    test('devicePixelRatio 低於 2.0 時夾限為 2.0（避免渲染解析度過低模糊）', () {
      expect(pageRenderScale(1.0), 2.0);
    });

    test('devicePixelRatio 高於 3.0 時夾限為 3.0（避免記憶體/效能問題）', () {
      expect(pageRenderScale(4.0), 3.0);
    });
  });

  // ── Task 2: detectCropRectFromBgraPixels 單元測試 ──

  group('detectCropRectFromBgraPixels', () {
    // 10x10 全白畫布，(2,2)-(7,7) 範圍畫黑色內容區塊。
    Uint8List makeCanvasWithBlackBlock() {
      final px = Uint8List(10 * 10 * 4);
      for (var i = 0; i < 100; i++) {
        px[i * 4] = 255;
        px[i * 4 + 1] = 255;
        px[i * 4 + 2] = 255;
        px[i * 4 + 3] = 255;
      }
      for (var y = 2; y < 8; y++) {
        for (var x = 2; x < 8; x++) {
          final idx = (y * 10 + x) * 4;
          px[idx] = 0;
          px[idx + 1] = 0;
          px[idx + 2] = 0;
        }
      }
      return px;
    }

    test('偵測出的邊界貼近內容區塊，含小幅邊距', () {
      final rect = detectCropRectFromBgraPixels(
        makeCanvasWithBlackBlock(),
        width: 10,
        height: 10,
      );
      // 內容區塊佔 20%-80%，容許 1% 邊距（比照 PdfImageProcessor 既有
      // CROP_MARGIN=0.01f 常數語意）。
      expect(rect.left, closeTo(0.19, 0.02));
      expect(rect.top, closeTo(0.19, 0.02));
      expect(rect.right, closeTo(0.71, 0.02));
      expect(rect.bottom, closeTo(0.71, 0.02));
    });

    test('全白畫布（無內容）回傳全頁矩形，不擲例外', () {
      final px = Uint8List(4 * 4 * 4);
      for (var i = 0; i < px.length; i += 4) {
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = 255;
      }
      final rect = detectCropRectFromBgraPixels(px, width: 4, height: 4);
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.right, 1);
      expect(rect.bottom, 1);
    });
  });

  group('cropBgraPixels', () {
    test('依相對矩形裁剪出對應子區域（左上角像素取樣驗證）', () {
      // 4x4 畫布，左上 (0,0) 紅、其餘藍。裁切矩形取右下 2x2 象限。
      final px = Uint8List(4 * 4 * 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final idx = (y * 4 + x) * 4;
          if (x == 0 && y == 0) {
            px[idx] = 0; px[idx + 1] = 0; px[idx + 2] = 255; // 紅（B=0,G=0,R=255）
          } else {
            px[idx] = 255; px[idx + 1] = 0; px[idx + 2] = 0; // 藍（B=255,G=0,R=0）
          }
          px[idx + 3] = 255;
        }
      }
      final cropped = cropBgraPixels(
        px,
        width: 4,
        height: 4,
        rect: const PdfCropRect(left: 0.5, top: 0.5, right: 1.0, bottom: 1.0),
        outWidth: 2,
        outHeight: 2,
      );
      expect(cropped, hasLength(2 * 2 * 4));
      // 右下象限應全為藍（不含紅色左上角原點）。
      for (var i = 0; i < 4; i++) {
        expect(cropped[i * 4], 255, reason: 'pixel $i B channel（應為藍）');
        expect(cropped[i * 4 + 2], 0, reason: 'pixel $i R channel（應為藍）');
      }
    });

    test('rect 為全頁（0,0,1,1）時輸出等於原圖', () {
      final px = Uint8List.fromList(
        List.generate(4 * 4 * 4, (i) => i % 256),
      );
      final cropped = cropBgraPixels(
        px,
        width: 4,
        height: 4,
        rect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        outWidth: 4,
        outHeight: 4,
      );
      expect(cropped, px);
    });
  });
}
