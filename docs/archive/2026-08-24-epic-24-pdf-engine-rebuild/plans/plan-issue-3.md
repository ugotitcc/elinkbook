# Epic 24 Issue 3 — E-Ink 影像濾鏡/裁切功能對等 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `PdfReaderView` 重現現行（已隨 Issue 1 清退的）原生 `PdfImageProcessor.kt` 四項影像處理能力——對比度/亮度、加粗（型態學膨脹）、智慧自動裁切、手動選區裁切——功能對等，不接受退化。

**Architecture:** 對比度/亮度改用 Flutter 內建 `ColorFiltered` widget（`ColorFilter.matrix`，與 Android `ColorMatrix` 格式完全相同）即時包住整個 `PdfViewer`，GPU 合成、不需要背景運算（**與 `spec.md`/`issues.md` 字面「一律 Isolate＋debounce」的既定決策不同，屬本計畫的刻意偏離，經人類確認採用**，詳見下方「與 spec.md 的偏離」）。加粗與裁切因為 `pdfrx` 的 `PdfViewer` **沒有**公開 API 可以攔截或替換它自己畫出來的頁面點陣圖，改用 `PdfPage.render()` 自行渲染整頁到 `PdfImage`（BGRA 原始像素，`pdfrx` 官方 `PdfPageView`/縮圖範例採用的同一個公開 API），在背景 `Isolate.run()` 執行像素處理（裁切先、加粗後，此順序沿用已歸檔 `epic-4-pdf-enhance` 的定案管線），再用 `PdfImage.createFromBgraData()` 包回 `PdfImage`、`.createImage()` 轉成 `ui.Image`，透過 `pageOverlaysBuilder` 疊一張不透明 `RawImage` 蓋住該頁——`pdfrx` 底層仍會渲染原始頁面但被完全遮住（視覺結果正確，運算浪費可接受，`pageOverlaysBuilder` 回傳的 widget 本身也在 `ColorFiltered` 的渲染子樹內，因此對比度/亮度會自動套用到疊加圖層，不需要重複處理）。裁切要改變頁面在畫面上的顯示尺寸，沿用 Issue 2 建立的 `layoutPages` 自訂版面模式（裁切後的虛擬頁面尺寸），因此裁切與雙頁並列在版面計算上互斥（見 Global Constraints）。純函式核心（矩陣計算/膨脹/裁切偵測/裁切裁剪）與 pdfrx/Flutter widget 完全獨立，可直接 `flutter test` 用固定 BGRA 像素陣列驗證。

**Tech Stack:** Flutter/Dart、`pdfrx`（`PdfPage.render()`/`PdfImage`/`pageOverlaysBuilder`/`layoutPages` 既有 API，不新增套件依賴）、`dart:isolate`（`Isolate.run()`，比照既有 `book_content_fingerprint.dart` 前例）、`ColorFiltered`/`ColorFilter.matrix`（Flutter 內建）。

## 與 spec.md 的偏離（人類已確認，執行前務必知悉）

`spec.md`「E-Ink 影像濾鏡/裁切（FR-11 功能對等）」原文要求對比度/亮度「一律於背景 Isolate 執行」「Slider 連續調整需防手震延遲」。經與人類確認：Flutter 內建 `ColorFiltered`（`ColorFilter.matrix`）可以直接包住整個 `PdfViewer`，即時、GPU 合成，視覺輸出與原生 `ColorMatrixColorFilter` 實作完全一致（兩者本來就是同一種矩陣濾鏡格式），且不需要任何背景運算或防手震——**這是比字面規格更簡單、效能更好的做法，非規避規格意圖**（規格要求 Isolate/debounce 的真正意圖是「不能讓濾鏡調整卡住 UI」，`ColorFiltered` 直接讓這個問題不存在，不是繞過它）。因此本計畫：

- **對比度/亮度**：`ColorFiltered` 即時渲染，Task 3 不需要 Isolate/debounce。
- **加粗（型態學膨脹）**：仍走 Isolate＋debounce（`spec.md`「尤其型態學膨脹屬於逐像素運算」本來就是針對這個操作，逐像素鄰域掃描無法用 `ColorFilter` 表達）。
- **裁切**：不需要 debounce（裁切矩形不是連續拖曳觸發，見下方 Task 6/7），但仍透過 Isolate 執行像素裁剪＋（若同時啟用加粗）串接加粗處理，避免大頁面裁剪本身佔用 UI 執行緒。

若日後真機驗證發現 `ColorFiltered` 有無法接受的視覺落差（理論上不應該，兩者矩陣數學完全一致），才需要回頭補上 Isolate 版本——這是本計畫明確记錄、可回退的風險，不是被忽略的已知缺口。

**`issues.md` AC 字面對應說明**：AC 原文「Slider 連續調整對比度/亮度時有防手震延遲」在本計畫下不適用（對比度/亮度已無背景運算可言，沒有東西需要防手震）；`pdf_settings_sheet.dart` 唯一真正連續拖曳且驅動背景 Isolate 運算的是「加粗強度」Slider（`_buildSliderRow` 的 `onChanged` 在拖曳過程中逐格觸發），因此 Task 3/5 的 `PdfFilterDebouncer` 實際套用對象是加粗強度，而非 AC 字面寫的對比度/亮度——這是前述架構偏離的直接推論結果，不是另一個獨立的偏離。

## Global Constraints

- 語意與資料層完全不變：`PdfCropMode`（`none`/`autoDetect`/`manual`）、`PdfCropRect`、`BookReaderPrefs.pdfContrast`/`pdfBrightness`/`pdfBoldStrength`/`pdfCropMode`/`pdfCropRect`、`ResolvedPreferences` 對應欄位皆為既有型別，不得修改；`app/lib/screens/pdf_settings_sheet.dart` 的既有三個 Slider（`_buildFiltersTab`）與裁切模式按鈕（`_buildCropTab`）UI 已完整存在且已正確產生 `BookReaderPrefs` 欄位，**本工單不修改這個檔案**（`onRequestManualCrop` callback 已存在且已在 `reader_screen.dart._handleRequestManualCrop` 接上 `_cropEditModeActive = true`，智慧自動裁切不需要額外 UI 觸發按鈕——見 Task 6）。
- 濾鏡/裁切像素處理管線順序沿用已歸檔 `epic-4-pdf-enhance/spec.md` 定案：**裁切 → 加粗**（對比度/亮度因改走 `ColorFiltered`，作用在整個渲染輸出之上，不是管線的一部分，不影響這個順序）。
- **裁切與雙頁並列（Issue 2）互斥**：`pdfCropMode != PdfCropMode.none` 時，`_dualPageEnabled` 強制為 `false`（不論 `dualPageMode` 設定為何），避免 `layoutPages` 需要同時支援「雙頁配對」與「裁切後虛擬頁面尺寸」兩種版面邏輯疊加的組合爆炸；沿用 Issue 2 plan 明確記錄的開放項「裁切編輯模式與雙頁互斥（Issue 3）」，本計畫將互斥範圍從「僅編輯中」擴大為「裁切模式已啟用時」，因為兩者共用同一個 `layoutPages` 插槽、技術上無法只在編輯瞬間切換。這是本計畫的技術決策，非規格明文要求，若日後有「裁切+雙頁」同時需求，需另立工單處理版面合併邏輯。
- 智慧自動裁切維持「取樣偵測邊界後全書統一套用同一比例」語意（非逐頁各自計算，沿用 `epic-4-pdf-enhance` 定案）：偵測只在 `pdfCropMode == autoDetect && pdfCropRect == null`（尚無快取矩形）時，於第一次可視頁面渲染時觸發一次，透過 `onCropRectComputed` 回呼交給 `ReaderScreen` 持久化，之後全書沿用同一矩形，不重新計算。
- 手動選區裁切維持「使用者框選矩形後全書統一套用」語意：裁切互動模式（`cropEditModeActive == true`）期間，`_nextPage`/`_previousPage` 暫停回應（沿用 `epic-4-pdf-enhance/spec.md` 定案「此模式下 nextPage／previousPage 暫停回應，避免翻頁與拖拉手勢互相干擾」）。
- 本工單明確不做（不得動手實作，只需不阻塞）：劃線/備註選取矩形換算（Issue 4，含裁切模式下的座標換算）、PDF 工具列 FAB 化（Issue 8）、E-Ink 影像濾鏡與雙頁並列的產品層級組合支援（見上方裁切/雙頁互斥說明，同一技術限制）。
- 測試策略：純函式（矩陣計算/膨脹/裁切偵測/裁切裁剪/debounce）用 `flutter test` 的 `test()`，不需要 `pdfrxInitialize()`；`PdfReaderView` 整合行為用 widget test，樣板沿用 Issue 1/2 既有 `pdfrxInitialize()`/`tester.runAsync()` 輪詢慣例；裁切框選 UI（`PdfCropFrameOverlay`）是純 Flutter widget，不依賴 pdfrx，一般 widget test 即可。
- 不新增 PDF 測試 fixture：`app/test/fixtures/sample_multi_page.pdf`（5 頁）已足夠驗證濾鏡/裁切在多頁情境下的行為一致性。
- 不修改：`app/lib/screens/pdf_settings_sheet.dart`、`app/lib/reader/pdf_crop_mode.dart`、`app/lib/reader/pdf_crop_rect.dart`、`app/lib/reader/book_reader_prefs.dart`、`app/lib/reader/resolved_preferences.dart`、`app/test/reader/pdf_reader_view_test.dart`（Issue 1 既有測試，diff 必須為空）、`app/test/reader/pdf_reader_view_dual_page_test.dart`（Issue 2 既有測試，diff 必須為空）。

---

## File Structure

- **Create:** `app/lib/reader/pdf_image_filters.dart`（純函式模組：`contrastBrightnessColorMatrix`、`dilateBgraPixels`、`detectCropRectFromBgraPixels`、`cropBgraPixels`）
- **Create:** `app/test/reader/pdf_image_filters_test.dart`
- **Create:** `app/lib/reader/pdf_filter_debounce.dart`（可取消的防手震延遲排程器，供加粗強度 Slider 使用）
- **Create:** `app/test/reader/pdf_filter_debounce_test.dart`
- **Create:** `app/lib/reader/pdf_crop_frame_overlay.dart`（手動裁切框選 UI：全螢幕遮罩＋四角控制點可拖曳矩形＋確認/取消）
- **Create:** `app/test/reader/pdf_crop_frame_overlay_test.dart`
- **Create:** `app/test/reader/pdf_reader_view_filters_test.dart`（widget test，真實 fixture，獨立於 `pdf_reader_view_test.dart`/`pdf_reader_view_dual_page_test.dart`，讓「Issue 1/2 測試零回歸」可用 `git diff` 直接證明）
- **Modify:** `app/lib/reader/pdf_reader_view.dart`（新增 6 個建構參數＋1 個回呼、`ColorFiltered` 包裝、`pageOverlaysBuilder`、裁切用 `layoutPages`、裁切/雙頁互斥、裁切編輯模式下暫停翻頁）
- **Modify:** `app/lib/screens/reader_screen.dart`（PDF 分支新增參數與回呼接線、裁切編輯模式疊加 `PdfCropFrameOverlay`）
- **Modify:** `app/test/screens/reader_screen_test.dart`（新增裁切編輯模式相關 widget test）
- **Modify:** `app/pubspec.yaml`（新增 `fake_async` 為直接 `dev_dependencies`，供 Task 3 的防手震延遲測試使用）
- **不修改：** `app/lib/screens/pdf_settings_sheet.dart`、`app/lib/reader/pdf_crop_mode.dart`、`app/lib/reader/pdf_crop_rect.dart`、`app/lib/reader/book_reader_prefs.dart`、`app/lib/reader/resolved_preferences.dart`、`app/test/reader/pdf_reader_view_test.dart`、`app/test/reader/pdf_reader_view_dual_page_test.dart`

---

### Task 1：`pdf_image_filters.dart`——對比度/亮度矩陣與加粗（型態學膨脹）核心

**Files:**
- Create: `app/lib/reader/pdf_image_filters.dart`
- Create: `app/test/reader/pdf_image_filters_test.dart`

**Interfaces:**
- Consumes: 無（純函式，無專案內部相依）。
- Produces: `List<double> contrastBrightnessColorMatrix({required double contrast, required double brightness})`、`Uint8List dilateBgraPixels(Uint8List bgra, {required int width, required int height, required int radius})`、`double pageRenderScale(double devicePixelRatio)`。供 Task 4（`ColorFiltered`）、Task 5/6/7（加粗/裁切 Isolate 呼叫的渲染解析度計算，取代寫死的固定倍率）使用。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_image_filters_test.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_image_filters.dart';

void main() {
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
      expect(m[0], closeTo(2.0, 1e-9)); // R 係數
      expect(m[6], closeTo(2.0, 1e-9)); // G 係數
      expect(m[12], closeTo(2.0, 1e-9)); // B 係數
      expect(m[18], 1); // Alpha 係數恆為 1（不受對比度/亮度影響）
      expect(m[19], 0); // Alpha 平移恆為 0
    });

    test('contrast=-100 時對比度係數為 0.0', () {
      final m = contrastBrightnessColorMatrix(contrast: -100, brightness: 0);
      expect(m[0], closeTo(0.0, 1e-9));
    });

    test('brightness=100 時平移量約 255（8-bit 全亮）', () {
      final m = contrastBrightnessColorMatrix(contrast: 0, brightness: 100);
      expect(m[4], closeTo(255, 1e-9)); // R 平移
      expect(m[9], closeTo(255, 1e-9)); // G 平移
      expect(m[14], closeTo(255, 1e-9)); // B 平移
    });

    test('brightness=-100 時平移量約 -255（8-bit 全暗）', () {
      final m = contrastBrightnessColorMatrix(contrast: 0, brightness: -100);
      expect(m[4], closeTo(-255, 1e-9));
    });
  });

  group('dilateBgraPixels', () {
    // 3x3 單像素黑點（其餘白色），BGRA：白=[255,255,255,255]，黑=[0,0,0,255]。
    Uint8List makeSinglePixelDot() {
      final px = Uint8List(3 * 3 * 4);
      for (var i = 0; i < 9; i++) {
        px[i * 4 + 0] = 255; // B
        px[i * 4 + 1] = 255; // G
        px[i * 4 + 2] = 255; // R
        px[i * 4 + 3] = 255; // A
      }
      // 中心 (1,1) 設為黑。
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
      px[0] = 0; px[1] = 0; px[2] = 0; px[3] = 255; // 黑，不透明
      px[4] = 255; px[5] = 255; px[6] = 255; px[7] = 128; // 白，半透明
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
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_image_filters_test.dart`
Expected: 編譯失敗（`pdf_image_filters.dart` 尚不存在）。

- [ ] **Step 3: 建立 `pdf_image_filters.dart`（本 Task 範圍：矩陣計算與膨脹核心）**

```dart
import 'dart:typed_data';

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
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_image_filters_test.dart`
Expected: 13 項測試全數 PASS（原 10 項＋本次新增 `pageRenderScale` 3 項）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_image_filters.dart app/test/reader/pdf_image_filters_test.dart
git commit -m "feat(epic-24): 新增 pdf_image_filters 純函式核心——對比度/亮度矩陣與加粗膨脹"
```

---

### Task 2：`pdf_image_filters.dart`——智慧裁切邊界偵測與裁切裁剪

**Files:**
- Modify: `app/lib/reader/pdf_image_filters.dart`
- Modify: `app/test/reader/pdf_image_filters_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `PdfCropRect detectCropRectFromBgraPixels(Uint8List bgra, {required int width, required int height})`（沿用既有 `app/lib/reader/pdf_crop_rect.dart` 的 `PdfCropRect` 型別，本 Task 只 import 消費、不修改該檔案）、`Uint8List cropBgraPixels(Uint8List bgra, {required int width, required int height, required PdfCropRect rect, required int outWidth, required int outHeight})`。供 Task 5（自動裁切偵測）與 Task 6（裁切裁剪 Isolate 呼叫）使用。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_image_filters_test.dart` 頂部新增 import，並新增兩個 group：

```dart
import 'package:elinkbook/reader/pdf_crop_rect.dart';
```

```dart
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
      expect(rect.right, closeTo(0.71, 0.02));  // 修正：掃描最後有內容索引7，7/10+0.01=0.71
      expect(rect.bottom, closeTo(0.71, 0.02));  // 同上
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
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_image_filters_test.dart`
Expected: 編譯失敗（`detectCropRectFromBgraPixels`/`cropBgraPixels` 尚不存在）。

- [ ] **Step 3: 在 `pdf_image_filters.dart` 新增裁切函式**

在檔案頂部新增 import：

```dart
import 'pdf_crop_rect.dart';
```

在 `dilateBgraPixels` 之後追加：

```dart
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
  while (top < height - 1 && !isRowContent(top)) top++;
  var bottom = height - 1;
  while (bottom > top && !isRowContent(bottom)) bottom--;
  var left = 0;
  while (left < width - 1 && !isColContent(left)) left++;
  var right = width - 1;
  while (right > left && !isColContent(right)) right--;

  // 【本計畫審查修正 Critical 1】全白（無內容）頁面時，上面兩組 while
  // 迴圈的終止條件會讓 top/left 一路累加到 height-1/width-1、bottom/right
  // 則因為 `bottom > top` 一開始就不成立而停在原地——四個變數收斂到同一個
  // 點（畫面右下角），而不是「找不到內容」。這是移植自已刪除的原生
  // `PdfImageProcessor.detectCropRectFromPixels()` 就已經存在、從未被
  // 觸發過的潛在缺陷（該實作演算法完全相同，只是舊架構的呼叫路徑沒有
  // 遇過真正全白的頁面）。全白/無內容時直接回傳全頁矩形，不繼續套用
  // margin 換算，避免使用者對著一片空白掃描頁面卻被自動裁成右下角一小塊。
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
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_image_filters_test.dart`
Expected: 全部 17 項測試（Task 1 的 13 項＋本 Task 的 4 項）PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_image_filters.dart app/test/reader/pdf_image_filters_test.dart
git commit -m "feat(epic-24): pdf_image_filters 新增智慧裁切邊界偵測與裁切裁剪"
```

---

### Task 3：`pdf_filter_debounce.dart`——可取消的防手震延遲排程器

**Files:**
- Create: `app/lib/reader/pdf_filter_debounce.dart`
- Create: `app/test/reader/pdf_filter_debounce_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `class PdfFilterDebouncer`（方法：`void schedule(void Function() action)`、`void dispose()`）。供 Task 4（加粗強度變更時排程 Isolate 運算）使用。

- [ ] **Step 1: 新增 `fake_async` 測試依賴**

`fake_async` 目前只是本專案的**間接**依賴（`app/pubspec.lock` 已有 `fake_async: 1.3.3`，但 `dependency: transitive`——只能被其他套件內部使用，`app/test/` 底下的程式碼不能直接 `import`）。在 `app/pubspec.yaml` 的 `dev_dependencies:` 區塊（`flutter_test:` 那一行附近）新增：

```yaml
  fake_async: ^1.3.3
```

Run: `cd app && flutter pub get`
Expected: 成功解析，無版本衝突（`pubspec.lock` 內既有版本已是 `1.3.3`，直接宣告同版本應可正常解析）。

- [ ] **Step 2: 撰寫失敗測試**

建立 `app/test/reader/pdf_filter_debounce_test.dart`：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_filter_debounce.dart';

void main() {
  test('單次 schedule 延遲後執行一次', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      var callCount = 0;
      debouncer.schedule(() => callCount++);
      async.elapse(const Duration(milliseconds: 299));
      expect(callCount, 0, reason: '延遲時間未到不應執行');
      async.elapse(const Duration(milliseconds: 1));
      expect(callCount, 1);
      debouncer.dispose();
    });
  });

  test('延遲時間內多次 schedule 只執行最後一次的 action', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      final calls = <int>[];
      debouncer.schedule(() => calls.add(1));
      async.elapse(const Duration(milliseconds: 100));
      debouncer.schedule(() => calls.add(2));
      async.elapse(const Duration(milliseconds: 100));
      debouncer.schedule(() => calls.add(3));
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, [3]);
      debouncer.dispose();
    });
  });

  test('dispose 後不再執行任何已排程的 action', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      var callCount = 0;
      debouncer.schedule(() => callCount++);
      debouncer.dispose();
      async.elapse(const Duration(milliseconds: 300));
      expect(callCount, 0);
    });
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_filter_debounce_test.dart`
Expected: 編譯失敗（`pdf_filter_debounce.dart` 尚不存在）。

- [ ] **Step 4: 建立 `pdf_filter_debounce.dart`**

```dart
import 'dart:async';

/// 可取消的防手震延遲排程器：[schedule] 在延遲時間內被再次呼叫時，取消
/// 前一次尚未執行的排程，只保留最後一次（epic-24-pdf-engine-rebuild
/// Issue 3，加粗強度 Slider 連續拖曳時避免對每個中間值都觸發一次 Isolate
/// 運算）。
class PdfFilterDebouncer {
  PdfFilterDebouncer({required this.delay});

  final Duration delay;
  Timer? _timer;

  void schedule(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_filter_debounce_test.dart`
Expected: 3 項測試全數 PASS。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/reader/pdf_filter_debounce.dart app/test/reader/pdf_filter_debounce_test.dart
git commit -m "feat(epic-24): 新增 PdfFilterDebouncer——加粗強度 Slider 防手震延遲排程器"
```

---

### Task 4：`PdfReaderView` 接上對比度/亮度——`ColorFiltered` 即時渲染

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Create: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `contrastBrightnessColorMatrix`。
- Produces: `PdfReaderView` 新增建構參數 `pdfContrast`（預設 `0`）、`pdfBrightness`（預設 `0`）。供 Task 9（`reader_screen.dart` 接線）使用。

**本 Task 刻意的測試順序**：先寫「不傳新參數時行為與 Issue 1/2 完全相同」的零回歸基準測試，再寫「傳入非零 contrast/brightness 時外層確實包了一層正確矩陣的 `ColorFiltered`」的測試。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_filters_test.dart`（樣板沿用 Issue 1/2 既有測試檔）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

void main() {
  setUp(() => pdfrxInitialize());

  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('不傳濾鏡參數時，不套用 ColorFiltered（零回歸基準）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final colorFiltered = tester.widgetList<ColorFiltered>(
      find.byType(ColorFiltered),
    );
    expect(colorFiltered, isEmpty,
        reason: 'contrast/brightness 皆為預設值 0 時不應包 ColorFiltered');
  });

  testWidgets('pdfContrast/pdfBrightness 非零時，套用對應矩陣的 ColorFiltered',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfContrast: 50,
          pdfBrightness: -20,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final colorFiltered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    final filter = colorFiltered.colorFilter;
    // ColorFilter.matrix() 是不可變值物件、實作了 == 依矩陣數值比較，
    // 直接建構同一個矩陣的 ColorFilter 並用 == 比對，比字串比對穩健。
    final expectedMatrix =
        contrastBrightnessColorMatrix(contrast: 50, brightness: -20);
    expect(filter, ColorFilter.matrix(expectedMatrix));
  });

  testWidgets('contrast=0 但 brightness 非零時仍套用 ColorFiltered', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfBrightness: 30,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 編譯失敗（`PdfReaderView` 建構子尚無 `pdfContrast`/`pdfBrightness` 具名參數）。

- [ ] **Step 3: `PdfReaderView` 新增建構參數與 `ColorFiltered` 包裝**

在 `app/lib/reader/pdf_reader_view.dart` 頂部新增 import：

```dart
import 'pdf_image_filters.dart';
```

在既有雙頁欄位群組之後新增：

```dart
  // ── epic-24-pdf-engine-rebuild Issue 3 新增 ──
  /// 對比度 -100..100、亮度 -100..100，皆預設 0（無調整）。與
  /// `ResolvedPreferences.pdfContrast`/`pdfBrightness` 同義。
  final double pdfContrast;
  final double pdfBrightness;
```

建構子新增對應具名參數（預設皆為 `0`）：

```dart
    this.pdfContrast = 0,
    this.pdfBrightness = 0,
```

在 `_PdfReaderViewState` 新增 getter（放在 `_dualPageEnabled` 之後）：

```dart
  /// contrast/brightness 皆為預設值時回傳 null，讓 build() 省略
  /// ColorFiltered 包裝——與雙頁模式「單頁時 layoutPages 傳 null」相同的
  /// 「不啟用時完全不改變既有渲染路徑」構造性零回歸保證。
  ColorFilter? get _colorFilter {
    if (widget.pdfContrast == 0 && widget.pdfBrightness == 0) return null;
    return ColorFilter.matrix(
      contrastBrightnessColorMatrix(
        contrast: widget.pdfContrast,
        brightness: widget.pdfBrightness,
      ),
    );
  }
```

修改 `build()`，把原本直接回傳的 `PdfViewer(...)` 包一層條件式 `ColorFiltered`：

```dart
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    final viewer = PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _controller,
      initialPageNumber: (widget.initialPageIndex ?? 0) + 1,
      params: PdfViewerParams(
        layoutPages: _dualPageEnabled ? _layoutSpreadPages : null,
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
        onViewerReady: (doc, controller) {
          if (!_renderedNotified) {
            _renderedNotified = true;
            widget.onPageRendered();
          }
          widget.onPageChanged?.call(PdfPageInfo(
            pageIndex: (controller.pageNumber ?? 1) - 1,
            totalPages: controller.pageCount,
          ));
        },
        onPageChanged: _handlePageChanged,
      ),
    );
    final colorFilter = _colorFilter;
    return colorFilter == null ? viewer : ColorFiltered(colorFilter: colorFilter, child: viewer);
  }
```

（Task 5-8 會再擴充這個 `params: PdfViewerParams(...)` 區塊，本 Task 先只新增 `ColorFiltered` 包裝這一層，其餘既有欄位逐字保留。）

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 3 項測試 PASS（若 Step 1 的矩陣斷言方式需要調整，先確認調整後測試語意仍驗證「矩陣數值正確傳遞」這件事，而不只是「ColorFiltered 存在」）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart`
Expected: Issue 1/2 既有測試全數 PASS，**且兩個檔案 `git diff` 皆為空**。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "feat(epic-24): PdfReaderView 接上對比度/亮度——ColorFiltered 即時渲染"
```

---

### Task 5：`PdfReaderView` 接上加粗——`PdfPage.render()` + Isolate + `pageOverlaysBuilder`

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `dilateBgraPixels`／`pageRenderScale`、Task 3 的 `PdfFilterDebouncer`。
- Produces: `_PdfReaderViewState` 新增 `_boldOverlayImages`（`Map<int, ui.Image>` LRU 快取，上限 `_maxCachedOverlayImages`）、`_committedBoldStrength`（debounce settle 後才更新的「目前允許各頁比對用」的加粗強度）、`_buildBoldOverlay`（`PdfPageOverlaysBuilder` 實作）、`_recomputeBoldOverlay`（逐頁獨立、互不取消的背景運算）。供 Task 6（裁切要與加粗共用同一個 `pageOverlaysBuilder`，串接同一條像素處理管線）使用。

**架構要點（回應 `tmp/epic-24/plan-issue-3-review.md` Critical 2/3、Important 3、Minor 1）**：
1. **debounce 只作用在「要不要開始信任這個新的 `pdfBoldStrength` 值」，不作用在「逐頁排程」**——`PdfFilterDebouncer` 改為在 `didUpdateWidget` 偵測到 `pdfBoldStrength` 改變時觸發，300ms 沉澱後才把新值寫進 `_committedBoldStrength`；`_buildBoldOverlay`／`_recomputeBoldOverlay` 全程只比對 `_committedBoldStrength`（一個穩定值），不直接讀 `widget.pdfBoldStrength`。每一頁各自呼叫 `unawaited(_recomputeBoldOverlay(page))`，**不經過任何共用的 debouncer**——可視範圍內同時有多頁需要重算時，彼此的 `Future` 完全獨立，不會互相取消（修正 Critical 2）；捲動到新頁面時，只要 `_committedBoldStrength` 早已穩定（沒有人在拖 Slider），新頁面立刻開始運算，不會被强迫等滿 300ms（修正 Important 2）。
2. **`_boldOverlayImages` 加上 LRU 容量上限**——超過 `_maxCachedOverlayImages` 時淘汰最久未使用的項目並呼叫 `image.dispose()`，避免長時間捲動累積數十張全解析度覆蓋圖導致顯存暴漲（修正 Critical 3）。
3. **`page.render()` 的目標解析度改用 `pageRenderScale(MediaQuery.of(context).devicePixelRatio)`**，取代寫死的 `page.width * 2`（修正 Important 3）。
4. **非同步運算完成時檢查「目前是否仍是當初出發時的那個 `_committedBoldStrength`」**，不是的話捨棄結果、不寫入快取（修正 Minor 1）。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_filters_test.dart` 新增：

```dart
  testWidgets('pdfBoldStrength > 0 時，第一頁疊加一張 RawImage 覆蓋層',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfBoldStrength: 1.0,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    // 加粗覆蓋層透過 Isolate 非同步產生，等待其完成（輪詢 RawImage 出現）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(find.byType(RawImage), findsWidgets,
        reason: '加粗啟用時應有至少一張處理後的頁面覆蓋圖');
  });

  testWidgets('pdfBoldStrength == 0（預設）時，不產生任何覆蓋層（零回歸）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets(
      '同時有多頁需要加粗運算時，各頁互不取消（Critical 2 回歸測試：'
      '不得共用單一 debouncer 排程逐頁運算）', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    // 用夠高的可視區域讓多於 1 頁同時進入 pageOverlaysBuilder 的呼叫範圍。
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 2000,
          child: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 1.0,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.runAsync(() async {
      for (var i = 0; i < 40 && find.byType(RawImage).evaluate().length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(
      find.byType(RawImage).evaluate().length,
      greaterThanOrEqualTo(2),
      reason: '若採用單一共用 debouncer 排程逐頁運算，後呼叫的頁面會取消先前'
          '排程、只會剩下最後一頁算出覆蓋圖，這裡斷言至少 2 頁都完成運算，'
          '證明各頁是獨立排程、互不取消',
    );
  });

  testWidgets('執行期連續變更 pdfBoldStrength（模擬 Slider 拖曳）時，'
      '在 debounce 沉澱前不會對每個中間值各自觸發一次運算', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(double strength) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: strength,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        );

    await tester.pumpWidget(buildView(0.1));
    await waitRendered(tester, () => renderedCount);
    // 快速連續變更（模擬拖曳中的中間值），每次間隔遠小於 300ms debounce。
    for (final strength in [0.2, 0.3, 0.4, 0.5, 0.6]) {
      await tester.pumpWidget(buildView(strength));
      await tester.pump(const Duration(milliseconds: 30));
    }
    // debounce 沉澱前查詢，此時不應已經有覆蓋圖（仍在等待最後一次變更後
    // 滿 300ms）。
    expect(find.byType(RawImage), findsNothing,
        reason: 'debounce 尚未沉澱，不應提早以任何中間值觸發運算');

    // 等待 debounce 沉澱＋Isolate 運算完成。
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(find.byType(RawImage), findsWidgets,
        reason: 'debounce 沉澱後應以最後一次的值（0.6）完成運算');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart --plain-name "加粗"`
Expected: 編譯失敗（`pdfBoldStrength` 尚不存在）。

- [ ] **Step 3: `PdfReaderView` 新增 `pdfBoldStrength` 與加粗覆蓋層管線**

新增 import：

```dart
import 'dart:isolate';
import 'dart:ui' as ui;

import 'pdf_filter_debounce.dart';
```

新增建構參數（與 `pdfContrast`/`pdfBrightness` 同一群組）：

```dart
  /// 0..1，0=不加粗（預設）。與 `ResolvedPreferences.pdfBoldStrength` 同義。
  final double pdfBoldStrength;
```

```dart
    this.pdfBoldStrength = 0,
```

在 `_PdfReaderViewState` 新增欄位（`_spreadLayout` 群組之後）：

```dart
  /// LRU 容量上限——超過時淘汰最久未被存取的項目並 dispose()，避免長時間
  /// 捲動累積數十張全解析度覆蓋圖導致顯存暴漲（審查修正 Critical 3）。
  /// 6 為初始保守值（略多於單一畫面同時可見的頁數），若真機驗證發現捲動
  /// 時仍有明顯的重算閃爍，可調高，不需要修改快取邏輯本身。
  static const _maxCachedOverlayImages = 6;

  /// pageNumber（1-indexed，與 pdfrx 慣例一致）→ 已算好的加粗覆蓋圖。用
  /// `Map` 的插入順序模擬 LRU：每次存取（讀取既有項目或寫入新項目）都
  /// remove 再重新 put，讓該項目移到「最近使用」端；超過
  /// `_maxCachedOverlayImages` 時淘汰最前面（最久未使用）的項目。
  /// dispose() 時必須逐一 dispose() 釋放，避免大量翻頁後圖片資源洩漏。
  final _boldOverlayImages = <int, ui.Image>{};
  /// 記錄目前每個 pageNumber 對應覆蓋圖是用哪個「已沉澱」加粗強度算出來
  /// 的，供比對快取是否過期——比對對象是 [_committedBoldStrength]，不是
  /// `widget.pdfBoldStrength`（見下方欄位說明）。
  final _boldOverlayStrength = <int, double>{};

  /// debounce 沉澱後才更新的加粗強度，`_buildBoldOverlay`／
  /// `_recomputeBoldOverlay` 全程只比對這個值，不直接讀
  /// `widget.pdfBoldStrength`（審查修正 Critical 2／Important 2）：
  /// Slider 連續拖曳時 `widget.pdfBoldStrength` 每個 frame 都在變，若逐頁
  /// 邏輯直接比對它，每一幀都會判定快取過期、對每個中間值各自觸發一次
  /// Isolate 運算；改成只比對這個「已沉澱」的值，中間值全部被跳過，
  /// debounce 沉澱後才一次性讓所有可視頁面的快取同時失效，之後每頁各自
  /// 獨立（不共用任何 debouncer／timer）呼叫 `_recomputeBoldOverlay`，
  /// 互不取消，也不會因為捲動出現新頁面而被迫等滿 300ms。
  var _committedBoldStrength = 0.0;
  final _boldDebouncer =
      PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
```

在 `initState()` 內、`_openDocument();` 之後新增：

```dart
    _committedBoldStrength = widget.pdfBoldStrength;
```

在 `dispose()` 內、`super.dispose()` 之前新增：

```dart
    _boldDebouncer.dispose();
    for (final image in _boldOverlayImages.values) {
      image.dispose();
    }
```

在既有 `didUpdateWidget`（Issue 2 既有方法，比對 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 那個）內、`super.didUpdateWidget(oldWidget);` 之後、既有 `final changed = ...` 那行之前，新增一段**獨立**的變更偵測（加粗強度不影響版面/頁碼，不需要 `invalidate()`/reanchor，故刻意不併入既有的 `changed` 判斷式）：

```dart
    if (oldWidget.pdfBoldStrength != widget.pdfBoldStrength) {
      _boldDebouncer.schedule(() {
        if (!mounted) return;
        setState(() => _committedBoldStrength = widget.pdfBoldStrength);
      });
    }
```

新增 `_layoutSpreadPages`/`_calculateSpreadAnchorPageNumber` 之後：

```dart
  /// PdfPageOverlaysBuilder 實作。加粗啟用（_committedBoldStrength > 0）時，
  /// 若該頁尚無對應覆蓋圖（或已沉澱的加粗強度已變更），立即（不經過任何
  /// debounce）排程一次該頁獨立的背景 Isolate 運算；運算完成前不回傳任何
  /// widget（該頁維持顯示 pdfrx 自己渲染的原始未加粗畫面，避免空白
  /// 閃爍），完成後透過 setState 觸發重繪、這次 build() 就能取得快取好的
  /// 覆蓋圖。存取既有快取項目時 touch 一次（見 [_touchOverlayCache]），
  /// 維持 LRU 的「最近使用」排序正確。
  List<Widget> _buildBoldOverlay(
    BuildContext context,
    Rect pageRectInViewer,
    PdfPage page,
  ) {
    if (_committedBoldStrength <= 0) return const [];
    final pageNumber = page.pageNumber;
    final cachedStrength = _boldOverlayStrength[pageNumber];
    if (cachedStrength != _committedBoldStrength) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      unawaited(_recomputeBoldOverlay(page, devicePixelRatio));
      return const [];
    }
    final image = _touchOverlayCache(pageNumber);
    if (image == null) return const [];
    return [RawImage(image: image, fit: BoxFit.fill)];
  }

  /// 存取 [_boldOverlayImages] 的唯一入口：remove 再重新 put，把該項目
  /// 移到 Map 插入順序的最後端（= LRU 的「最近使用」端）。找不到時回傳
  /// null，呼叫端不需要另外判斷 containsKey。
  ui.Image? _touchOverlayCache(int pageNumber) {
    final image = _boldOverlayImages.remove(pageNumber);
    if (image == null) return null;
    _boldOverlayImages[pageNumber] = image;
    return image;
  }

  /// 寫入一張新算好的覆蓋圖，超過 [_maxCachedOverlayImages] 時淘汰最久未
  /// 使用（Map 插入順序最前面）的項目並 dispose()（審查修正 Critical 3）。
  void _putOverlayCache(int pageNumber, ui.Image image) {
    _boldOverlayImages.remove(pageNumber)?.dispose();
    if (_boldOverlayImages.length >= _maxCachedOverlayImages) {
      final oldestKey = _boldOverlayImages.keys.first;
      _boldOverlayImages.remove(oldestKey)?.dispose();
      _boldOverlayStrength.remove(oldestKey);
    }
    _boldOverlayImages[pageNumber] = image;
  }

  Future<void> _recomputeBoldOverlay(PdfPage page, double devicePixelRatio) async {
    final targetStrength = _committedBoldStrength;
    final scale = pageRenderScale(devicePixelRatio);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null || !mounted) return;
    try {
      final radius = (targetStrength * 3).round().clamp(1, 3);
      // 【額外修正，發現於本次審查修訂過程，非審查報告原文項目】
      // rendered（pdfrx 的 PdfImage 實作）內部持有 dart:ffi 的
      // Pointer<Uint8>（native malloc 記憶體），不是 Isolate 訊息可傳遞的
      // 型別——若 Isolate.run() 的 closure 直接存取 rendered.pixels／
      // .width／.height，closure 會把 rendered 本身一併捕捉進去，
      // Isolate.run() 會在嘗試把這個 closure 送到新 isolate 時直接拋出
      // 例外（無法傳遞 native pointer）。必須先在呼叫端（目前這個
      // isolate）把需要的資料取出成單純的區域變數（Uint8List 的內容在
      // isolate 訊息傳遞時是拷貝語意，取出後即與 rendered 的生命週期脫鉤，
      // 之後呼叫 rendered.dispose() 不影響已拷貝出去的資料），closure 只
      // 捕捉這些單純變數，不捕捉 rendered 本身。
      final sourcePixels = rendered.pixels;
      final sourceWidth = rendered.width;
      final sourceHeight = rendered.height;
      final processedBytes = await Isolate.run(
        () => dilateBgraPixels(
          sourcePixels,
          width: sourceWidth,
          height: sourceHeight,
          radius: radius,
        ),
      );
      // 【審查修正 Minor 1】非同步運算完成時，若 _committedBoldStrength
      // 已經被之後的一次 debounce 沉澱改變（使用者這期間又調整了
      // Slider），代表這次運算的目標值已經過期，直接捨棄結果，不寫入
      // 快取、不 setState——避免舊結果覆蓋掉即將由更新一輪運算產生的
      // 新結果。
      if (!mounted || _committedBoldStrength != targetStrength) return;
      final processedImage = PdfImage.createFromBgraData(
        processedBytes,
        width: rendered.width,
        height: rendered.height,
      );
      final uiImage = await processedImage.createImage();
      if (!mounted || _committedBoldStrength != targetStrength) {
        uiImage.dispose();
        return;
      }
      setState(() {
        _putOverlayCache(page.pageNumber, uiImage);
        _boldOverlayStrength[page.pageNumber] = targetStrength;
      });
    } finally {
      rendered.dispose();
    }
  }
```

在 `build()` 的 `PdfViewerParams(...)` 內、`calculateCurrentPageNumber` 之後新增：

```dart
        pageOverlaysBuilder: _buildBoldOverlay,
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全部 7 項測試（Task 4 的 3 項＋本 Task 的 4 項）PASS。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart`
Expected: Issue 1/2 既有測試全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（`unawaited` 需要 `import 'dart:async';`，若 analyze 提示缺 import 請補上）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "feat(epic-24): PdfReaderView 接上加粗——Isolate 型態學膨脹 + pageOverlaysBuilder"
```

---

### Task 6：`PdfReaderView` 接上智慧自動裁切——偵測、持久化回呼、裁切版面

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `detectCropRectFromBgraPixels`/`cropBgraPixels`。
- Produces: `PdfReaderView` 新增建構參數 `pdfCropMode`（預設 `PdfCropMode.none`）、`pdfCropRect`（預設 `null`）、回呼 `onCropRectComputed`（`ValueChanged<PdfCropRect>?`）。`_dualPageEnabled` getter 修改為裁切啟用時強制回傳 `false`（見 Global Constraints）。供 Task 9（`reader_screen.dart` 接住 `onCropRectComputed` 持久化）使用。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_filters_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

新增測試：

```dart
  testWidgets('pdfCropMode=autoDetect 且尚無 pdfCropRect 時，首次渲染後觸發 onCropRectComputed',
      (tester) async {
    var renderedCount = 0;
    PdfCropRect? computedRect;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: PdfCropMode.autoDetect,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onCropRectComputed: (rect) => computedRect = rect,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && computedRect == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    expect(computedRect, isNotNull);
  });

  testWidgets('pdfCropMode=autoDetect 且已有 pdfCropRect 時，不重新觸發偵測',
      (tester) async {
    var renderedCount = 0;
    var computeCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: PdfCropMode.autoDetect,
          pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onCropRectComputed: (rect) => computeCount++,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.pump(const Duration(milliseconds: 500));

    expect(computeCount, 0, reason: '已有快取矩形時不應重新計算');
  });

  testWidgets('裁切模式啟用時，即使 dualPageMode=always 也強制單頁', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.always,
          pdfCropMode: PdfCropMode.autoDetect,
          pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '裁切啟用時應退回單頁步進 1，而非雙頁步進 2');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart --plain-name "裁切"`
Expected: 編譯失敗（`pdfCropMode`/`pdfCropRect`/`onCropRectComputed` 尚不存在）。

- [ ] **Step 3: `PdfReaderView` 新增裁切建構參數與偵測邏輯**

新增 import：

```dart
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
```

新增建構參數：

```dart
  /// 三態裁切模式，預設 `PdfCropMode.none`。與
  /// `ResolvedPreferences.pdfCropMode` 同義。
  final PdfCropMode pdfCropMode;
  /// `pdfCropMode != none` 時才有意義；null 代表尚未有快取矩形（僅
  /// `autoDetect` 模式會觸發偵測並透過 [onCropRectComputed] 回報）。
  final PdfCropRect? pdfCropRect;
  /// 智慧自動裁切首次計算出矩形時觸發，供呼叫端持久化寫入偏好設定。
  final ValueChanged<PdfCropRect>? onCropRectComputed;
```

```dart
    this.pdfCropMode = PdfCropMode.none,
    this.pdfCropRect,
    this.onCropRectComputed,
```

修改 `_dualPageEnabled` getter：

```dart
  bool get _dualPageEnabled =>
      widget.pdfCropMode == PdfCropMode.none &&
      isDualPageEnabled(
        mode: widget.dualPageMode,
        isLandscape: widget.isLandscape,
      );
```

在 `_PdfReaderViewState` 新增欄位（`_boldDebouncer` 之後）：

```dart
  bool _cropDetectionInFlight = false;
```

新增方法（`_recomputeBoldOverlay` 之後）：

```dart
  /// autoDetect 模式下、尚無快取矩形時，於第一次可視頁面觸發一次偵測——
  /// 沿用已歸檔 epic-4-pdf-enhance 定案的「取樣偵測後全書統一套用」語意，
  /// 只在第 0 頁（開書當下最先可視的頁面）取樣，不逐頁計算。
  void _maybeDetectCropRect(PdfPage page, double devicePixelRatio) {
    if (widget.pdfCropMode != PdfCropMode.autoDetect) return;
    if (widget.pdfCropRect != null) return;
    if (_cropDetectionInFlight) return;
    if (page.pageNumber != 1) return;
    _cropDetectionInFlight = true;
    unawaited(_detectCropRect(page, devicePixelRatio));
  }

  Future<void> _detectCropRect(PdfPage page, double devicePixelRatio) async {
    final scale = pageRenderScale(devicePixelRatio);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null) {
      _cropDetectionInFlight = false;
      return;
    }
    try {
      // 同 Task 5 `_recomputeBoldOverlay` 的修正：closure 只能捕捉單純的
      // 區域變數，不能捕捉 rendered 本身（native Pointer<Uint8> 無法跨
      // isolate 傳遞）。
      final sourcePixels = rendered.pixels;
      final sourceWidth = rendered.width;
      final sourceHeight = rendered.height;
      final rect = await Isolate.run(
        () => detectCropRectFromBgraPixels(
          sourcePixels,
          width: sourceWidth,
          height: sourceHeight,
        ),
      );
      if (mounted) {
        widget.onCropRectComputed?.call(rect);
      }
    } finally {
      rendered.dispose();
      _cropDetectionInFlight = false;
    }
  }
```

在 `_buildBoldOverlay` 開頭新增裁切偵測觸發（本 Task 只做偵測觸發，裁切的實際視覺套用留給下一步；`devicePixelRatio` 取自 `context`，與 Task 5 加粗渲染共用同一個 `pageRenderScale` 換算函式，避免兩處各自寫一份换算邏輯）：

```dart
  List<Widget> _buildBoldOverlay(
    BuildContext context,
    Rect pageRectInViewer,
    PdfPage page,
  ) {
    _maybeDetectCropRect(page, MediaQuery.of(context).devicePixelRatio);
    if (_committedBoldStrength <= 0) return const [];
    // ...（其餘邏輯不變）
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全部 10 項測試（Task 4 的 3 項＋Task 5 的 4 項＋本 Task 的 3 項）PASS。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "feat(epic-24): PdfReaderView 接上智慧自動裁切偵測與雙頁互斥"
```

---

### Task 7：`PdfReaderView` 套用裁切視覺效果——`layoutPages` 裁切版面 + 裁剪覆蓋圖

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `cropBgraPixels`／`pageRenderScale`，Task 6 的 `pdfCropRect`。
- Produces: `_PdfReaderViewState._layoutCroppedPages`（`PdfPageLayoutFunction` 實作），`_buildBoldOverlay` 擴充為裁切後再加粗（沿用 `epic-4-pdf-enhance` 定案順序）。裁切與雙頁的 `layoutPages` 二選一由 Task 6 已完成的 `_dualPageEnabled` 互斥保證彼此不衝突。

**本 Task 額外修正 `tmp/epic-24/plan-issue-3-review.md` Critical 4**：`layoutPages` 傳入的是 State 的 instance method tear-off（`_layoutCroppedPages`／`_layoutSpreadPages`），tear-off 本身的 `==` 比較只看「是不是同一個 State 實例的同一個方法」，不會反映方法內部讀取的 `widget.pdfCropRect` 是否改變——這與 Issue 2 當初為了同樣理由（`_layoutSpreadPages` 讀取 `widget.dualPageCoverAlone`/`widget.dualPageDirection`）已經在既有 `didUpdateWidget` 加上 `_controller.invalidate()` 是同一個問題。裁切目前完全沒有掛上這個機制，代表使用者在 `PdfSettingsSheet` 切換裁切模式或智慧自動裁切偵測完成寫回 `pdfCropRect` 後，`pdfrx` 會沿用切換前算好的舊版面快取，畫面不會反映新的裁切尺寸，直到某個恰好會觸發 pdfrx 自行 relayout 的操作（例如翻頁）才會「意外」更新——是實際會發生的 Bug，不是理論疑慮。本 Task 把既有 `changed` 判斷式擴充為同時涵蓋裁切欄位，讓裁切也走同一條已經驗證過的 invalidate() 路徑。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_filters_test.dart` 新增：

```dart
  testWidgets('裁切啟用時，頁面顯示尺寸依裁切矩形縮小（非原始頁面比例）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: PdfCropMode.autoDetect,
          pdfCropRect: const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(find.byType(RawImage), findsWidgets,
        reason: '裁切啟用時第一頁應有裁切後的覆蓋圖');
  });

  testWidgets('pdfCropMode=none（預設）時不影響 layoutPages（零回歸）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    expect(lastPageInfo?.totalPages, 5);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets(
      '執行期切換 pdfCropRect（模擬智慧自動裁切偵測完成寫回）時，'
      '版面尺寸立即反映新裁切矩形（Critical 4 回歸測試：didUpdateWidget '
      '須涵蓋裁切欄位並呼叫 invalidate()）', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(PdfCropRect? cropRect) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: cropRect == null ? PdfCropMode.none : PdfCropMode.manual,
            pdfCropRect: cropRect,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        );

    await tester.pumpWidget(buildView(null));
    await waitRendered(tester, () => renderedCount);
    final sizeBeforeCrop = tester.getSize(find.byType(PdfReaderView));

    await tester.pumpWidget(
      buildView(const PdfCropRect(left: 0.3, top: 0.1, right: 0.7, bottom: 0.9)),
    );
    // 兩層巢狀 addPostFrameCallback（比照 Issue 2 既有樣板）等待 relayout
    // 真正完成。
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // widget 本身外觀尺寸（畫面容器大小）不受裁切影響（那是 pdfrx 內部
    // 文件版面座標系的縮小，不是 Flutter widget 樹的外部尺寸），這裡改為
    // 直接斷言裁切覆蓋圖確實出現——若 didUpdateWidget 沒有正確偵測
    // pdfCropRect 變更並呼叫 invalidate()，_layoutCroppedPages 根本不會
    // 被 pdfrx 重新呼叫，覆蓋圖也就不會被觸發計算。
    expect(sizeBeforeCrop, isNotNull);
    expect(find.byType(RawImage), findsWidgets,
        reason: '裁切矩形切換後應觸發 relayout 與覆蓋圖運算');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart --plain-name "頁面顯示尺寸"`
Expected: FAIL（尚未有裁切覆蓋圖產生邏輯）。

- [ ] **Step 3: 擴充 `_buildBoldOverlay` 支援裁切，新增 `_layoutCroppedPages`**

**刪除** Task 5 新增的 `_buildBoldOverlay`／`_recomputeBoldOverlay` 兩個方法，改以下方新方法（`_buildProcessedOverlay`／`_recomputeOverlay`）取代——同時處理裁切＋加粗（裁切先、加粗後），不是在旁邊新增一份平行邏輯（`_touchOverlayCache`／`_putOverlayCache` 兩個 LRU 輔助方法維持 Task 5 版本不動，繼續共用）：

```dart
  bool get _cropEnabled =>
      widget.pdfCropMode != PdfCropMode.none && widget.pdfCropRect != null;

  List<Widget> _buildProcessedOverlay(
    BuildContext context,
    Rect pageRectInViewer,
    PdfPage page,
  ) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    _maybeDetectCropRect(page, devicePixelRatio);
    if (!_cropEnabled && _committedBoldStrength <= 0) return const [];
    final pageNumber = page.pageNumber;
    // 【與 Task 5 相同的設計原則】裁切矩形不是連續拖曳觸發（智慧自動只
    // 算一次、手動裁切靠按鈕確認一次），不需要 debounce，直接讀
    // widget.pdfCropRect 當作 cacheKey 的一部分；加粗沿用 Task 5 已建立
    // 的 _committedBoldStrength（debounce 沉澱後才更新），不是
    // widget.pdfBoldStrength。
    final cacheKey = (crop: widget.pdfCropRect, bold: _committedBoldStrength);
    if (_overlayCacheKey[pageNumber] != cacheKey) {
      unawaited(_recomputeOverlay(page, cacheKey, devicePixelRatio));
      return const [];
    }
    final image = _touchOverlayCache(pageNumber);
    if (image == null) return const [];
    return [RawImage(image: image, fit: BoxFit.fill)];
  }

  Future<void> _recomputeOverlay(
    PdfPage page,
    ({PdfCropRect? crop, double bold}) cacheKey,
    double devicePixelRatio,
  ) async {
    final scale = pageRenderScale(devicePixelRatio);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null || !mounted) return;
    try {
      final cropRect = cacheKey.crop;
      // 同 Task 5 的修正：closure 只能捕捉單純的區域變數（Uint8List／
      // int），不能捕捉 rendered 本身（native Pointer<Uint8> 無法跨
      // isolate 傳遞，closure 一旦存取 rendered.xxx 就會把整個 rendered
      // 捕捉進去）。
      final sourcePixels = rendered.pixels;
      final sourceWidth = rendered.width;
      final sourceHeight = rendered.height;
      final processed = await Isolate.run(() {
        var pixels = sourcePixels;
        var width = sourceWidth;
        var height = sourceHeight;
        if (cropRect != null) {
          final outWidth = ((cropRect.right - cropRect.left) * width).round().clamp(1, width);
          final outHeight = ((cropRect.bottom - cropRect.top) * height).round().clamp(1, height);
          pixels = cropBgraPixels(
            pixels,
            width: width,
            height: height,
            rect: cropRect,
            outWidth: outWidth,
            outHeight: outHeight,
          );
          width = outWidth;
          height = outHeight;
        }
        if (cacheKey.bold > 0) {
          final radius = (cacheKey.bold * 3).round().clamp(1, 3);
          pixels = dilateBgraPixels(pixels, width: width, height: height, radius: radius);
        }
        return (pixels: pixels, width: width, height: height);
      });
      // 【審查修正 Minor 1，沿用 Task 5 同一個防禦】非同步運算完成時，
      // 若目前這一頁「應該要用的」cacheKey 已經不是出發時的那一組（裁切
      // 矩形又變了、或加粗強度又沉澱出新值），代表這次結果已經過期，
      // 直接捨棄，不覆蓋掉即將由更新一輪運算產生的結果。
      final currentDesiredKey =
          (crop: widget.pdfCropRect, bold: _committedBoldStrength);
      if (!mounted || currentDesiredKey != cacheKey) return;
      final processedImage = PdfImage.createFromBgraData(
        processed.pixels,
        width: processed.width,
        height: processed.height,
      );
      final uiImage = await processedImage.createImage();
      if (!mounted || currentDesiredKey != cacheKey) {
        uiImage.dispose();
        return;
      }
      setState(() {
        _putOverlayCache(page.pageNumber, uiImage);
        _overlayCacheKey[page.pageNumber] = cacheKey;
      });
    } finally {
      rendered.dispose();
    }
  }

  /// 裁切啟用時的自訂版面：每頁顯示尺寸依裁切矩形縮小（保持裁切後內容
  /// 比例），取代 pdfrx 預設的「頁面原始尺寸」版面。與 Issue 2 的
  /// `_layoutSpreadPages` 走同一個 `layoutPages` 插槽，兩者互斥（見
  /// `_dualPageEnabled`／build() 選用邏輯）。
  PdfPageLayout _layoutCroppedPages(List<PdfPage> pages, PdfViewerParams params) {
    final cropRect = widget.pdfCropRect!;
    final margin = params.margin;
    var y = margin;
    final rects = <Rect>[];
    var maxWidth = 0.0;
    for (final page in pages) {
      final w = page.width * (cropRect.right - cropRect.left);
      final h = page.height * (cropRect.bottom - cropRect.top);
      rects.add(Rect.fromLTWH(margin, y, w, h));
      if (w > maxWidth) maxWidth = w;
      y += h + margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(maxWidth + margin * 2, y));
  }
```

把 `_PdfReaderViewState` 的 `_boldOverlayStrength` 欄位替換為：

```dart
  /// pageNumber → 已算好覆蓋圖對應的（裁切矩形, 已沉澱加粗強度）組合，
  /// 任一項改變即視為快取過期。
  final _overlayCacheKey = <int, ({PdfCropRect? crop, double bold})>{};
```

修改既有（Issue 2 新增、Task 5 已沿用）的 `didUpdateWidget`，把 `changed` 判斷式擴充為同時涵蓋裁切欄位（**修正 Critical 4**——裁切矩形改變時，`layoutPages` 傳入的 tear-off 引用本身不會變，`pdfrx` 不會自動察覺需要 relayout，必須沿用既有 `invalidate()` 機制主動通知）：

```dart
    final changed = oldWidget.dualPageMode != widget.dualPageMode ||
        oldWidget.dualPageCoverAlone != widget.dualPageCoverAlone ||
        oldWidget.dualPageDirection != widget.dualPageDirection ||
        oldWidget.isLandscape != widget.isLandscape ||
        oldWidget.pdfCropMode != widget.pdfCropMode ||
        oldWidget.pdfCropRect != widget.pdfCropRect;
```

（`changed` 之後的既有邏輯——`anchorBefore` 記錄、`_spreadLayout`/`_cachedLayoutKey`/`_cachedPdfLayout` 清空、`_pendingReanchorPageIndex`、兩層巢狀 `addPostFrameCallback` reanchor——完全不用修改，這條 if 區塊本來就是「只要偵測到需要 relayout 的欄位變了，就統一走這一套流程」，裁切欄位併入判斷式即可直接複用，不需要另外寫一份。）

在 `build()` 內，`layoutPages: _dualPageEnabled ? _layoutSpreadPages : null,` 改為：

```dart
        layoutPages: _cropEnabled
            ? _layoutCroppedPages
            : (_dualPageEnabled ? _layoutSpreadPages : null),
```

`pageOverlaysBuilder: _buildBoldOverlay,` 改為：

```dart
        pageOverlaysBuilder: _buildProcessedOverlay,
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全部 13 項測試 PASS（Task 4-6 累計 10 項＋本 Task 新增 3 項，含 Critical 4 回歸測試）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "feat(epic-24): PdfReaderView 套用裁切視覺效果——自訂版面 + 裁切/加粗合併管線"
```

---

### Task 8：`pdf_crop_frame_overlay.dart`——手動裁切框選 UI

**Files:**
- Create: `app/lib/reader/pdf_crop_frame_overlay.dart`
- Create: `app/test/reader/pdf_crop_frame_overlay_test.dart`

**Interfaces:**
- Consumes: 既有 `PdfCropRect`。
- Produces: `class PdfCropFrameOverlay extends StatefulWidget`（參數：`initialRect`、`onConfirm: ValueChanged<PdfCropRect>`、`onCancel: VoidCallback`）。純 Flutter widget，不依賴 pdfrx，供 Task 9（`reader_screen.dart` 在 `_cropEditModeActive == true` 時疊加顯示）使用。四角（左上/右上/左下/右下）皆有獨立可拖曳控制點（**回應審查 Important 1**：早期草案只放右下角一個控制點，使用者完全無法調整 `top`/`left`——裁切最常見的真實需求恰好就是去掉頁面頂部的頁首與左側裝訂邊留白，缺了這兩個方向等於失去大半實用價值）。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_crop_frame_overlay_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, height: 800, child: child)),
      );

  testWidgets('顯示確認/取消按鈕，點擊確認時回傳目前框選矩形', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    expect(find.byKey(const Key('pdf_crop_frame_confirm')), findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9));
  });

  testWidgets('點擊取消時觸發 onCancel、不觸發 onConfirm', (tester) async {
    var cancelled = false;
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () => cancelled = true,
      )),
    );

    await tester.tap(find.byKey(const Key('pdf_crop_frame_cancel')));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(confirmed, isNull);
  });

  testWidgets('拖曳右下角控制點縮小裁切框後確認，回傳的矩形右/下邊界變小',
      (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_bottom_right'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(-100, -200));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.right, lessThan(1.0));
    expect(confirmed!.bottom, lessThan(1.0));
  });

  testWidgets('裁切框不可拖曳縮小到零面積以下（最小尺寸防呆）', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.4, top: 0.4, right: 0.6, bottom: 0.6),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_bottom_right'));
    // 拖曳到遠超過左上角的位置，驗證不會產生 right < left 或 bottom < top。
    await tester.drag(handle, const Offset(-1000, -1000));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed!.right, greaterThan(confirmed!.left));
    expect(confirmed!.bottom, greaterThan(confirmed!.top));
  });

  testWidgets(
      '拖曳左上角控制點可獨立調整 top 與 left（Important 1 回歸測試：'
      '不得只有右下角一個控制點）', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_top_left'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(80, 120));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.left, greaterThan(0.0),
        reason: '拖曳左上角控制點應能收窄 left 邊界');
    expect(confirmed!.top, greaterThan(0.0),
        reason: '拖曳左上角控制點應能收窄 top 邊界');
    // right/bottom 是這次拖曳的固定錨點，不應被連帶改動。
    expect(confirmed!.right, 1.0);
    expect(confirmed!.bottom, 1.0);
  });

  testWidgets('右上角／左下角控制點皆存在，且只調整各自對應的兩個邊界',
      (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    expect(find.byKey(const Key('pdf_crop_frame_handle_top_right')), findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_handle_bottom_left')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('pdf_crop_frame_handle_top_right')),
      const Offset(-80, 120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed!.right, lessThan(1.0));
    expect(confirmed!.top, greaterThan(0.0));
    expect(confirmed!.left, 0.0);
    expect(confirmed!.bottom, 1.0);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_crop_frame_overlay_test.dart`
Expected: 編譯失敗（`pdf_crop_frame_overlay.dart` 尚不存在）。

- [ ] **Step 3: 建立 `pdf_crop_frame_overlay.dart`**

```dart
import 'package:flutter/material.dart';

import 'pdf_crop_rect.dart';

/// 手動裁切框選 UI（epic-24-pdf-engine-rebuild Issue 3）：全螢幕疊加層，
/// 顯示一個可拖曳右下角控制點縮放的矩形框，確認/取消由呼叫端
/// （`ReaderScreen`）決定後續動作（本 widget 不直接持有 `PdfReaderView`
/// 或持久化邏輯，維持既有單向資料流慣例，比照 `PdfSettingsSheet`）。
///
/// 座標系統：內部以「相對於本 widget 佔滿的可用空間」的比例（0.0-1.0）
/// 追蹤裁切框，與 [PdfCropRect] 語意一致——呼叫端須把本 widget 疊在與
/// `PdfReaderView` 完全同尺寸的區域上，兩者的相對座標系統才會對齊。
class PdfCropFrameOverlay extends StatefulWidget {
  const PdfCropFrameOverlay({
    super.key,
    required this.initialRect,
    required this.onConfirm,
    required this.onCancel,
  });

  final PdfCropRect initialRect;
  final ValueChanged<PdfCropRect> onConfirm;
  final VoidCallback onCancel;

  @override
  State<PdfCropFrameOverlay> createState() => _PdfCropFrameOverlayState();
}

class _PdfCropFrameOverlayState extends State<PdfCropFrameOverlay> {
  static const _minSize = 0.05;

  late double _left = widget.initialRect.left;
  late double _top = widget.initialRect.top;
  late double _right = widget.initialRect.right;
  late double _bottom = widget.initialRect.bottom;

  /// 四個角落控制點共用的拖曳處理：[movesLeft]/[movesTop] 決定這次拖曳
  /// 調整的是哪一組邊界（例如左上角控制點 movesLeft=true, movesTop=true，
  /// 只動 `_left`/`_top`，`_right`/`_bottom` 維持不動當錨點）——這是
  /// 【審查修正 Important 1】的核心：早期版本不論拖哪個控制點都只動
  /// `_right`/`_bottom`，導致使用者永遠無法收窄 `top`/`left`。
  void _dragHandle({
    required Offset delta,
    required Size size,
    required bool movesLeft,
    required bool movesTop,
  }) {
    setState(() {
      if (movesLeft) {
        _left = (_left + delta.dx / size.width).clamp(0.0, _right - _minSize);
      } else {
        _right = (_right + delta.dx / size.width).clamp(_left + _minSize, 1.0);
      }
      if (movesTop) {
        _top = (_top + delta.dy / size.height).clamp(0.0, _bottom - _minSize);
      } else {
        _bottom = (_bottom + delta.dy / size.height).clamp(_top + _minSize, 1.0);
      }
    });
  }

  Widget _buildHandle({
    required Key key,
    required double cornerLeft,
    required double cornerTop,
    required Size size,
    required bool movesLeft,
    required bool movesTop,
  }) {
    return Positioned(
      left: cornerLeft - 16,
      top: cornerTop - 16,
      child: GestureDetector(
        key: key,
        onPanUpdate: (details) => _dragHandle(
          delta: details.delta,
          size: size,
          movesLeft: movesLeft,
          movesTop: movesTop,
        ),
        child: Container(width: 32, height: 32, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final frameRect = Rect.fromLTRB(
          _left * size.width,
          _top * size.height,
          _right * size.width,
          _bottom * size.height,
        );
        return Stack(
          children: [
            Positioned.fromRect(
              rect: frameRect,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_top_left'),
              cornerLeft: frameRect.left,
              cornerTop: frameRect.top,
              size: size,
              movesLeft: true,
              movesTop: true,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_top_right'),
              cornerLeft: frameRect.right,
              cornerTop: frameRect.top,
              size: size,
              movesLeft: false,
              movesTop: true,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_bottom_left'),
              cornerLeft: frameRect.left,
              cornerTop: frameRect.bottom,
              size: size,
              movesLeft: true,
              movesTop: false,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_bottom_right'),
              cornerLeft: frameRect.right,
              cornerTop: frameRect.bottom,
              size: size,
              movesLeft: false,
              movesTop: false,
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('pdf_crop_frame_cancel'),
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onCancel,
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    key: const Key('pdf_crop_frame_confirm'),
                    icon: const Icon(Icons.check, color: Colors.white),
                    onPressed: () => widget.onConfirm(
                      PdfCropRect(left: _left, top: _top, right: _right, bottom: _bottom),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_crop_frame_overlay_test.dart`
Expected: 6 項測試全數 PASS（原 4 項＋本次新增左上角/右上角回歸測試 2 項）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_crop_frame_overlay.dart app/test/reader/pdf_crop_frame_overlay_test.dart
git commit -m "feat(epic-24): 新增 PdfCropFrameOverlay——手動裁切框選 UI"
```

---

### Task 9：`PdfReaderView` 裁切編輯模式（暫停翻頁）+ `onCropRectSelected` 回呼

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: 無新增外部相依。
- Produces: `PdfReaderView` 新增建構參數 `cropEditModeActive`（預設 `false`）。`_jumpToPage`/`_nextPage`/`_previousPage` 於 `cropEditModeActive == true` 時提早 return（暫停回應）。供 Task 10（`reader_screen.dart` 接上 `_cropEditModeActive` 既有欄位）使用。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_filters_test.dart` 新增：

```dart
  testWidgets('cropEditModeActive=true 時，nextPage/previousPage 暫停回應',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          cropEditModeActive: true,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0, reason: '裁切編輯模式下翻頁應無效');

    PdfReaderView.jumpToPage(key, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0, reason: '裁切編輯模式下跳頁應無效');
  });

  testWidgets('cropEditModeActive=false（預設）時翻頁行為不變（零回歸）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart --plain-name "裁切編輯模式"`
Expected: 編譯失敗（`cropEditModeActive` 尚不存在）。

- [ ] **Step 3: 新增 `cropEditModeActive` 參數與翻頁暫停判斷**

新增建構參數：

```dart
  /// 手動裁切互動模式是否啟用中，預設 false。啟用時 [jumpToPage]／
  /// [nextPage]／[previousPage] 暫停回應，避免翻頁與拖拉裁切框控制點的
  /// 手勢互相干擾（沿用 epic-4-pdf-enhance/spec.md 定案）。
  final bool cropEditModeActive;
```

```dart
    this.cropEditModeActive = false,
```

在 `_jumpToPage`／`_nextPage`／`_previousPage` 三個方法開頭各自新增一行防呆（單頁分支邏輯本身逐字不動，只在最前面新增一個提早 return）：

```dart
  void _jumpToPage(int pageIndex) {
    if (widget.cropEditModeActive) return;
    // ...（其餘邏輯不變）
```

```dart
  void _nextPage() {
    if (widget.cropEditModeActive) return;
    // ...（其餘邏輯不變）
```

```dart
  void _previousPage() {
    if (widget.cropEditModeActive) return;
    // ...（其餘邏輯不變）
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全部 15 項測試 PASS（Task 4-7 累計 13 項＋本 Task 新增 2 項）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增裁切編輯模式——暫停翻頁回應"
```

---

### Task 10：接線 `reader_screen.dart`，跑全專案回歸

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-9 的 `PdfReaderView` 全部新增參數/回呼、Task 8 的 `PdfCropFrameOverlay`。
- Produces: `ReaderScreen` PDF 分支正確傳入濾鏡/裁切參數；`_handleRequestManualCrop`（既有方法，見檔案 568-571 行既有 doc comment 已預告本次接線）完整接上 `PdfCropFrameOverlay` 顯示、確認/取消回呼；`onCropRectComputed`/裁切確認皆透過既有 `_handlePrefsChanged` 寫入持久化。本工單最後一個 Task，完成後 Issue 3 全數功能對等驗收條件達成。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 新增（沿用檔案既有 PDF 測試樣板——直接用 `MaterialApp(home: ReaderScreen(filePath: 'test/fixtures/sample_multi_page.pdf', bookId: 'b1', prefsManager: ...))` 建構＋`tester.runAsync` 輪詢等待 pdfrx 真實載入完成，比照既有第 2657-2703 行「`PdfReaderView.nextPage／previousPage` 在真實 pdfrx 載入後正確切換頁碼」測試的既有寫法；PDF 版面設定入口是既有 `_buildAppBarActions()` 內 `case BookFormat.pdf:` 分支（`reader_screen.dart:1407-1422`）的 AppBar `IconButton`——`Key('reader_layout_settings_button')`、`onPressed: _state == _RenderState.rendered ? _openPdfSettings : null`（`_openPdfSettings()` 開啟的正是 `PdfSettingsSheet`，見 `reader_screen.dart:616-625`），**不是** FAB（PDF 工具列 FAB 化是 Issue 8 尚未實作的範圍；注意 EPUB 分支在同一個檔案內也用同一個 Key 名稱但綁定 `_openLayoutSettings`/`_autoDetectedWritingMode` 判斷式，兩者是 `switch (format)` 底下互斥的不同分支，PDF 測試不會經過 EPUB 那一支）；`PdfSettingsSheet` 的裁切分頁 Tab 是 `Key('pdf_settings_tab_crop')`（`pdf_settings_sheet.dart:124`）；手動選區按鈕是既有 `Key('pdf_settings_crop_mode_manual')`（`pdf_settings_sheet.dart:357`））：

```dart
  testWidgets('進入手動裁切模式時顯示 PdfCropFrameOverlay，確認後寫回 prefs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfCropFrameOverlay), findsNothing,
        reason: '確認後應退出裁切編輯模式');
  });
```

（`FakeReaderPrefsManager()` 為本檔案既有的測試替身類別，見既有第 2723-2725 行用法；若其預設建構子的必要參數與本例不完全相同，以檔案內既有其他測試案例的實際呼叫方式為準。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "手動裁切模式"`
Expected: FAIL（`PdfCropFrameOverlay` 尚未接線）。

- [ ] **Step 3: `reader_screen.dart` 接線**

在 `PdfReaderView(...)` 建構呼叫（`app/lib/screens/reader_screen.dart:1949` 一帶）新增參數：

```dart
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
          pdfContrast: resolved.pdfContrast,
          pdfBrightness: resolved.pdfBrightness,
          pdfBoldStrength: resolved.pdfBoldStrength,
          pdfCropMode: resolved.pdfCropMode,
          pdfCropRect: resolved.pdfCropRect,
          cropEditModeActive: _cropEditModeActive,
          onCropRectComputed: (rect) => _handlePrefsChanged(
            _prefs.copyWith(pdfCropRect: rect),
          ),
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
```

在 `build()` 方法中，`PdfReaderView` 所在的 `Stack`（或既有畫面組裝處——實作者需先確認既有 `build()` 結構，`_cropEditModeActive` 已在既有欄位宣告，只是尚未在畫面上實際顯示任何內容）新增裁切編輯模式疊加層。找到既有 `canPop: !_cropEditModeActive` 一帶（`reader_screen.dart:1242`）所在的最外層 `Scaffold`/`Stack` 結構，在 PDF 閱讀畫面主體之後疊加：

```dart
              if (_cropEditModeActive)
                PdfCropFrameOverlay(
                  initialRect: _prefs.pdfCropRect ??
                      const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
                  onConfirm: (rect) {
                    setState(() => _cropEditModeActive = false);
                    _handlePrefsChanged(
                      _prefs.copyWith(pdfCropMode: PdfCropMode.manual, pdfCropRect: rect),
                    );
                  },
                  onCancel: () => setState(() => _cropEditModeActive = false),
                ),
```

（確切插入位置——本 Task 實作者須先讀 `reader_screen.dart` `build()` 方法既有的 `Stack`/`Scaffold` 巢狀結構，找到 PDF 閱讀主體與既有 FAB/Bottom Sheet 疊加層的既有寫法，比照既有慣例插入，確保 `PdfCropFrameOverlay` 疊在 `PdfReaderView` 之上、佔滿同一塊可視區域，兩者座標系統才會對齊——見 Task 8 `PdfCropFrameOverlay` doc comment 的座標系統說明。）

新增 import：

```dart
import '../reader/pdf_crop_frame_overlay.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
```

（若這些型別已經因為其他既有 import 間接可見，以 `flutter analyze` 的 `unused_import`/`undefined_identifier` 結果為準調整。）

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS（含既有測試零回歸）。

- [ ] **Step 5: 全專案回歸**

Run: `cd app && flutter test`
Expected: 全數 PASS，無失敗案例（含 Issue 1/2 既有測試零回歸、Task 1-9 本工單新增測試）。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run（比照 Issue 1/2 既有慣例，確認零回歸的直接證據）:
```bash
git diff -- app/test/reader/pdf_reader_view_test.dart app/test/reader/pdf_reader_view_dual_page_test.dart app/lib/screens/pdf_settings_sheet.dart app/lib/reader/pdf_crop_mode.dart app/lib/reader/pdf_crop_rect.dart app/lib/reader/book_reader_prefs.dart app/lib/reader/resolved_preferences.dart
```
Expected: 空輸出（Global Constraints 列出的不得修改檔案清單，一個字元的異動都不應該有）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): PDF 影像濾鏡/裁切接線 reader_screen.dart，Issue 3 完成"
```

---

## Self-Review Notes（供實作者與審查者參考，非待辦事項）

- **Spec Coverage**：`spec.md`/`issues.md` 四項能力（對比度、亮度、加粗、智慧/手動裁切）與其驗收條件（背景執行不卡 UI、Slider 防手震、全書統一套用裁切比例、`flutter analyze`/`flutter test` 零回歸）在 Task 1-10 皆有對應實作與測試，唯一經人類確認的字面偏離是「對比度/亮度改用 `ColorFiltered` 即時渲染、不走 Isolate/debounce」，已在文件開頭「與 spec.md 的偏離」段落明確記錄理由。
- **未涵蓋、留給後續工單**：裁切模式下劃線/備註選取矩形換算需要額外考慮「使用者看到的是裁切後畫面、儲存的定位需相對原始頁面座標」的換算（Issue 4 範圍，本計畫的 `PdfCropRect`/`cropBgraPixels` 已提供 Issue 4 換算所需的裁切矩形資料，但換算邏輯本身不在本工單）；PDF 工具列 FAB 化、「手動選區」與「智慧自動」在 `PdfSettingsSheet` 的 UI 觸發按鈕本身（本工單刻意不修改該檔案，因為既有按鈕已可用、UI 邏輯已完整）。
- **效能未知數（比照 design.md 決策 5，留待真機驗證）**：加粗/裁切的 `page.render(fullWidth: page.width * pageRenderScale(devicePixelRatio), ...)` 全頁點陣圖 Isolate 往返（含資料複製）在大尺寸掃描件 PDF（100MB+ 檔案常見的高解析度單頁）上的實際延遲尚未實測，`pageRenderScale` 已把倍率夾限在 2.0-3.0（見 Task 1，移植自原生 `PdfImageProcessor.pageRenderScale()` 的既有防護），若真機驗證仍發現明顯卡頓（覆蓋圖延遲出現、翻頁時感覺不流暢），可考慮比照原生 `PdfImageProcessor.applyBoldEffect()` 的降取樣工作副本策略再放大——這個優化選項不需要修改本計畫已定義的函式簽章，可作為獨立後續修正。
- **審查回應紀錄**：本計畫已依 `tmp/epic-24/plan-issue-3-review.md`（2026-08-09）修訂全部 4 項 Critical（全白頁面裁切邊界防呆、`PdfFilterDebouncer` 改為只作用於「已沉澱」的加粗強度而非逐頁排程、`_boldOverlayImages` 加上 LRU 容量上限、`didUpdateWidget` 補齊 `pdfCropMode`/`pdfCropRect` 監聽）與 3 項 Important（`PdfCropFrameOverlay` 補齊四角控制點、逐頁排程改為互不取消／不再被迫等滿 debounce、`page.render()` 目標解析度改用裝置密度換算取代寫死倍率），Minor 1（非同步結果的過期檢查）亦已納入。修訂集中在 Task 1（新增 `pageRenderScale`）、Task 2（`detectCropRectFromBgraPixels` 全空防呆）、Task 5/6/7（LRU 快取、debounce 改採「沉澱值」模式、`didUpdateWidget` 擴充、動態渲染解析度）、Task 8（四角控制點）。
- **複審發現並修正的實作缺陷（`tmp/epic-24/review-issue-3.md`／`review-issue-3-followup.md`，2026-08-09）**：實作階段一度誤判「`Isolate.run()` 在 `flutter test` 環境中無法 spawn 新 isolate」，因此 Task 5/6/7 的加粗/裁切覆蓋圖測試刻意迴避觸發 Isolate 的路徑。經逐層排除法重新排查後確認**這其實是真實的程式碼缺陷，不是測試環境限制**：Task 5/7 把 `Isolate.run()` 的 closure 直接定義在 `_recomputeOverlay`/`_detectCropRect` 這兩個 State 方法內部時，即使 closure 本身只讀取已取出的區域變數（`sourcePixels`/`sourceWidth`/`sourceHeight`/`cropRect`），Dart VM 仍會把該 closure 所在的整個詞法作用域 Context（含 `page: PdfPage` 這個方法參數）一併打包試圖送往新 isolate——`page` 內部持有 pdfrx 的 `_PdfDocumentPdfium`，其 `permissions` 欄位是 rxdart 的 `BehaviorSubject`（不可跨 isolate 傳遞），因此執行期必定擲出 `Illegal argument in isolate message: object is unsendable` 例外，**這在真機上會同樣發生，代表加粗/裁切在合併當下實際上完全不會產生任何視覺效果**（例外被 `.catchError` 靜默吞掉，此前只有 `flutter test` 主控台的 `debugPrint` 診斷訊息意外讓這個問題浮現）。修法：把 `Isolate.run()` 呼叫移到兩個獨立於 `_PdfReaderViewState` 之外的頂層函式（`_isolateProcessOverlayPixels`／`_isolateDetectCropRect`，宣告於 `pdf_reader_view.dart` 檔案結尾），這兩個函式的參數列只接受單純可跨 isolate 傳遞的型別，其詞法作用域內從頭到尾不存在 `PdfPage`/`PdfDocument`，從根本上排除被牽連打包的可能性——修正後 Task 5/7 原本因「環境限制」而省略的測試（加粗實際產生 `RawImage` 覆蓋層、多頁同時運算互不取消、裁切偵測 `onCropRectComputed` 觸發時機、裁切啟用時覆蓋圖實際產出）皆已全數補回並通過。
