import 'dart:typed_data';

import 'pdf_crop_rect.dart';

/// PDF 頁面影像處理純函式核心（epic-24-pdf-engine-rebuild Issue 3）。
/// 對應已隨 Issue 1 清退的原生 `PdfImageProcessor.kt`（見
/// `docs/archive/2026-07-14-epic-4-pdf-enhance/`）——公式與演算法邏輯
/// 逐一對應移植，僅資料型別從 Android `Bitmap`/`IntArray`（ARGB 打包）
/// 改為 `Uint8List`（BGRA8888，`pdfrx` `PdfImage.pixels` 的既有格式）。
/// 不依賴 pdfrx/Flutter widget，可在純 Dart 環境（含 Isolate 內）直接呼叫。

/// 標準對比度/亮度 ColorMatrix 公式：先以 127.5（8-bit 色階灰階中點）為
/// 軸心縮放對比度，再疊加亮度位移，確保 contrast=0／brightness=0 時是
/// 單位矩陣（無視覺變化）。回傳值可直接傳入 Flutter
/// `ColorFilter.matrix(List<double>)`——Flutter 的矩陣格式（4x5、
/// row-major、0-255 值域、第 5 欄為平移量）與 Android
/// `android.graphics.ColorMatrix` 完全相同，此函式為
/// `PdfImageProcessor.contrastBrightnessColorMatrix()` 的逐行移植。
List<double> contrastBrightnessColorMatrix({
  required double contrast,
  required double brightness,
}) {
  final contrastFactor = (100 + contrast) / 100; // -100→0.0，0→1.0，100→2.0
  final brightnessOffset = brightness * 2.55; // -100..100 映射到約 -255..255
  final translate = brightnessOffset + (255 - contrastFactor * 255) / 2;
  return [
    contrastFactor, 0, 0, 0, translate, //
    0, contrastFactor, 0, 0, translate, //
    0, 0, contrastFactor, 0, translate, //
    0, 0, 0, 1, 0, //
  ];
}

/// 型態學膨脹（加粗），對 [bgra] 做「取鄰域內最小亮度值」的膨脹運算，讓
/// 深色筆畫（文字）向外擴張、變粗變黑。[bgra] 為 BGRA8888 格式（與
/// `PdfImage.pixels` 一致），長度須為 `width * height * 4`。
///
/// 直接對原始解析度運算，不像 `PdfImageProcessor.applyBoldEffect()` 額外
/// 做縮小工作副本的效能優化——本函式在背景 Isolate 執行（見
/// `pdf_reader_view.dart` 呼叫端），不阻塞 UI，若真機驗證發現效能不足，
/// 可在呼叫端加上降取樣，不需要修改本函式介面。
///
/// 邊界像素以 coerceIn 夾到合法範圍內（等同邊緣複製，非補零），避免邊框
/// 產生非預期的暗色/亮色偽影。每個輸出像素的 alpha 沿用其「自身」原始
/// 像素的 alpha（不受鄰域影響）。
Uint8List dilateBgraPixels(
  Uint8List bgra, {
  required int width,
  required int height,
  required int radius,
}) {
  if (radius <= 0) return Uint8List.fromList(bgra);
  final result = Uint8List(bgra.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var minB = 255, minG = 255, minR = 255;
      for (var dy = -radius; dy <= radius; dy++) {
        final ny = (y + dy).clamp(0, height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final nx = (x + dx).clamp(0, width - 1);
          final idx = (ny * width + nx) * 4;
          if (bgra[idx] < minB) minB = bgra[idx];
          if (bgra[idx + 1] < minG) minG = bgra[idx + 1];
          if (bgra[idx + 2] < minR) minR = bgra[idx + 2];
        }
      }
      final outIdx = (y * width + x) * 4;
      final selfIdx = outIdx;
      result[outIdx] = minB;
      result[outIdx + 1] = minG;
      result[outIdx + 2] = minR;
      result[outIdx + 3] = bgra[selfIdx + 3]; // alpha 沿用自身原始值。
    }
  }
  return result;
}

const _pageRenderMinScale = 2.0;
const _pageRenderMaxScale = 3.0;

/// PDF 頁面渲染縮放係數：以裝置螢幕密度 [devicePixelRatio] 為基準，夾限在
/// 2.0-3.0 之間，避免極端 density 值造成渲染解析度過低（模糊）或過高
/// （記憶體/效能問題）。直接移植自已隨 Issue 1 清退的原生
/// `PdfImageProcessor.pageRenderScale()`——供 Task 5/6/7 計算加粗/裁切
/// Isolate 運算所需的渲染解析度使用，取代寫死的固定倍率（`page.width * 2`
/// 這種寫法在使用者放大畫面到 3x/4x 時會讓覆蓋圖明顯比底層 pdfrx 渲染模糊，
/// 在高 DPI 掃描件上又可能算出過大的點陣圖，兩個問題本函式一次解決）。
double pageRenderScale(double devicePixelRatio) =>
    devicePixelRatio.clamp(_pageRenderMinScale, _pageRenderMaxScale);

const _cropWhiteThreshold = 245;
const _cropMargin = 0.01;
const _cropScanStep = 4;

/// 智慧自動裁切邊界偵測：由四個邊緣向內掃描，找第一個「非全白」的列/行
/// 視為內容邊界，加一點邊距避免裁得太緊。逐 [_cropScanStep] 個像素跳著
/// 檢查一次以加速掃描。直接移植自 `PdfImageProcessor.detectCropRectFromPixels()`
/// （型別由 ARGB `IntArray` 改為 BGRA `Uint8List`，判斷邏輯不變：三色版
/// 最小值 < 門檻即視為內容）。
PdfCropRect detectCropRectFromBgraPixels(
  Uint8List bgra, {
  required int width,
  required int height,
}) {
  int minChannelAt(int pixelIndex) {
    final idx = pixelIndex * 4;
    final b = bgra[idx], g = bgra[idx + 1], r = bgra[idx + 2];
    return b < g ? (b < r ? b : r) : (g < r ? g : r);
  }

  bool isRowContent(int y) {
    for (var x = 0; x < width; x += _cropScanStep) {
      if (minChannelAt(y * width + x) < _cropWhiteThreshold) return true;
    }
    return false;
  }

  bool isColContent(int x) {
    for (var y = 0; y < height; y += _cropScanStep) {
      if (minChannelAt(y * width + x) < _cropWhiteThreshold) return true;
    }
    return false;
  }

  var top = 0;
  while (top < height - 1 && !isRowContent(top)) {
    top++;
  }
  var bottom = height - 1;
  while (bottom > top && !isRowContent(bottom)) {
    bottom--;
  }
  var left = 0;
  while (left < width - 1 && !isColContent(left)) {
    left++;
  }
  var right = width - 1;
  while (right > left && !isColContent(right)) {
    right--;
  }

  // 全白（無內容）頁面時直接回傳全頁矩形，不繼續套用 margin 換算。
  if (top >= bottom || left >= right) {
    return const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1);
  }

  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  return PdfCropRect(
    left: clamp01(left / width - _cropMargin),
    top: clamp01(top / height - _cropMargin),
    right: clamp01(right / width + _cropMargin),
    bottom: clamp01(bottom / height + _cropMargin),
  );
}

/// 依相對座標 [rect]（0.0-1.0）從 [bgra]（尺寸 [width]x[height]）裁剪出
/// 子區域，並輸出為 [outWidth]x[outHeight] 的新緩衝區（最近鄰取樣）。
/// [outWidth]/[outHeight] 由呼叫端依 [rect] 的長寬比例與目標渲染解析度
/// 算好傳入，本函式不自行推算比例，避免和呼叫端的版面計算產生兩份事實
/// 來源。
Uint8List cropBgraPixels(
  Uint8List bgra, {
  required int width,
  required int height,
  required PdfCropRect rect,
  required int outWidth,
  required int outHeight,
}) {
  final srcLeft = (rect.left * width).round().clamp(0, width - 1);
  final srcTop = (rect.top * height).round().clamp(0, height - 1);
  final srcWidth = ((rect.right - rect.left) * width).round().clamp(1, width - srcLeft);
  final srcHeight = ((rect.bottom - rect.top) * height).round().clamp(1, height - srcTop);

  final out = Uint8List(outWidth * outHeight * 4);
  for (var oy = 0; oy < outHeight; oy++) {
    final sy = srcTop + (oy * srcHeight / outHeight).floor().clamp(0, srcHeight - 1);
    for (var ox = 0; ox < outWidth; ox++) {
      final sx = srcLeft + (ox * srcWidth / outWidth).floor().clamp(0, srcWidth - 1);
      final srcIdx = (sy * width + sx) * 4;
      final dstIdx = (oy * outWidth + ox) * 4;
      out[dstIdx] = bgra[srcIdx];
      out[dstIdx + 1] = bgra[srcIdx + 1];
      out[dstIdx + 2] = bgra[srcIdx + 2];
      out[dstIdx + 3] = bgra[srcIdx + 3];
    }
  }
  return out;
}
