# Epic 24 Issue 4 — 書籤/劃線/備註遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在新 `pdfrx` 引擎的 `PdfReaderView` 上重建「長按拖曳框選矩形」劃線/備註選取互動與既有標記渲染，並補上 PDF 書籤 toggle 邏輯，功能與已刪除的舊原生架構對等，不接受退化。

**Architecture:** 選取手勢用真正的 `GestureDetector`（`onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd`）而非 `pdfrx` 官方的 `PdfOverlayInteractionRegion`（後者只回報「已辨識」的單次離散事件，沒有連續拖曳座標，見下方「手勢架構決策」），置於 Issue 3 已建立的 `pageOverlaysBuilder` 每頁疊加層內——選取矩形的座標換算天然以該頁的 `pageRectInViewer`（單頁/雙頁/裁切模式下皆已是該頁自己的螢幕矩形，不需要另外查 `PdfSpreadLayout.pageRects`）為基準，不需要額外的座標系統。裁切啟用時，使用者在畫面上拖出的矩形是相對「裁切後可視內容」，持久化前需反向換算回相對「原始整頁」的座標（`pdf_selection_geometry.dart` 提供對稱的正反換算純函式）。`reader_screen.dart` 側幾乎不需要新建 UI/狀態機——`AnnotationToolbar`、劃線/備註 CRUD handler、`_currentPdfSelection`/`_pdfAnnotationToolbarTop` 皆是已刪除舊原生架構遺留、完整實作但目前無法觸發的既有程式碼（`_currentPdfSelection` 全檔案只有被設為 `null` 的賦值，從未被設為非 null），本工單的 `reader_screen.dart` 部分純粹是「把 `PdfReaderView` 接上這組既有回呼」與「補一個 PDF 版本的書籤 toggle 方法」。

**Tech Stack:** Flutter/Dart（`GestureDetector`/`Listener`，`pdfrx` 既有 `pageOverlaysBuilder`/`PdfPage`，不新增套件依賴）、既有 `Highlight`/`Note`/`Bookmark`/`PercentRect`/`PdfSelectionInfo`/`PdfAnnotationDecoration` 資料層與 UI 層元件（`AnnotationToolbar`）。

## 手勢架構決策（務必先讀）

`pdfrx` 2.4.7 官方文件（`pdf_viewer.dart` 內 `PdfOverlayHitTester`/`PdfOverlayInteractionRegion` 一段，已直接查證原始碼）明確警告：在 `pageOverlaysBuilder` 內放一個會進入 Flutter 手勢競技場（gesture arena）的 `GestureDetector`，若它「贏得」競技場，`PdfViewer` 內建的平移/縮放/文字選取/連結點擊都可能失效——因此官方提供 `PdfOverlayInteractionRegion` 這個「疊加層本身對指標事件透明（`IgnorePointer`），由 `PdfViewer` 自己辨識手勢後才分派」的專用機制。

**本計畫刻意不採用 `PdfOverlayInteractionRegion`**：實際讀取其 API（`PdfOverlayInteractionCallbacks`）確認它只有 `onTap`／`onDoubleTap`／`onLongPress`／`onSecondaryTap` 四種「離散辨識完成」回呼，每種都只給單一時間點的 `PdfOverlayInteractionDetails`（`localPosition` 一個座標），**沒有 `onLongPressMoveUpdate`／`onLongPressEnd` 等價物**——長按辨識成功後無法拿到後續拖曳中的連續座標，做不到「長按後拖曳出一個可即時看到大小變化的矩形」這個 spec.md 明文要求的既有互動。

改用真正的 `GestureDetector`（`onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd`）疊在每頁的 `pageOverlaysBuilder` 內容之上。這件事本身有沒有前例可循、會不會被 `PdfViewer` 內建的平移/縮放搶走？**有——已刪除的舊 Dart 端 `PdfReaderView`（`git show 8535836:app/lib/reader/pdf_reader_view.dart`）在單頁 `AndroidView` 之上疊了同一種 `GestureDetector`（`onHorizontalDragEnd` 翻頁 + `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd` 框選），兩種手勢辨識器在同一個 `GestureDetector` 內同時存在、在真機上已驗證穩定運作**——`LongPressGestureRecognizer` 與 `PanGestureRecognizer`/`HorizontalDragGestureRecognizer` 的競技場消歧規則是 Flutter 框架本身的通用機制（「按住不動滿足時長 → 判定為長按，之後的移動改路由給長按辨識器的 move-update；按下後很快就有明顯位移 → 判定為拖曳/平移」），不因為對手是 `pdfrx` 內建的平移辨識器還是任何其他 `PanGestureRecognizer` 而改變。因此本計畫沿用同一種、已在本專案驗證過的手勢併存模式，只是把疊加層從舊架構的「整個 `AndroidView` 之上」改成「`pageOverlaysBuilder` 回傳的每頁疊加層之上」（後者的座標系統換算更單純，見下方）。

**殘留風險（比照本 Epic 一貫的「不做技術 Spike、風險留待實作/真機驗證階段處理」政策，design.md 決策 5）**：`GestureDetector` 與 `pdfrx` 內建平移/縮放辨識器的競技場消歧，理論上與已驗證過的舊架構同一套機制，但兩者的「對手」實作細節不同（`pdfrx` 內部平移邏輯 vs. 舊架構的 `AndroidView` 平移），不是逐位元相同的情境，**須在真機/模擬器上實際測試「長按拖曳框選」與「雙指縮放」「單指平移翻頁」三者互不干擾**，這件事無法在 `flutter test`（無真實觸控事件序列）完整驗證，widget test 只能驗證「呼叫 `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd` 後計算結果正確」這一段邏輯本身。

## Global Constraints

- 選取範圍資料模型維持既有語意不變：`PdfSelectionInfo`（`pageIndex`＋`rect`＋`widgetRect`，`app/lib/reader/pdf_selection_info.dart`，**不修改**）、`PercentRect`（`app/lib/reader/percent_rect.dart`，**不修改**）、`PdfAnnotationDecoration`（`app/lib/reader/pdf_annotation_decoration.dart`，**不修改**）、`Highlight`/`Note`/`Bookmark`/`HighlightsRepository`/`NotesRepository`/`BookmarksRepository`（**不修改**，資料層已完整支援 PDF、無需 schema 遷移）。
- 雙頁模式下，「相對頁面內容範圍的百分比矩形」須明確定義為相對「使用者實際長按所在那一個單一頁面」的邊界，不是相對整個雙頁 spread——這在本計畫的架構下是**構造性保證**：`pageOverlaysBuilder` 本來就是逐頁呼叫，Issue 2 的 `_layoutSpreadPages` 已經是逐頁（非逐 spread）定義 `pageLayouts`，`pageRectInViewer` 天生就是該次呼叫對應的那一頁的矩形，不需要額外查詢或換算，也因此不需要直接使用 `PdfSpreadLayout.pageRects`（該欄位是留給「有獨立於逐頁 overlay 呼叫之外、需要另外查某頁邊界」情境使用；本計畫的座標換算全程只依賴 `pageOverlaysBuilder` 自己傳入的 `pageRectInViewer`，架構上更簡單，也更不容易在雙頁/單頁間出現不一致）。
- 裁切模式下（`_cropEnabled`），使用者拖曳出的矩形座標基準是「裁切後可視內容」（`_layoutCroppedPages` 算出的較小 `pageRectInViewer`），**持久化前必須換算回相對「原始整頁」的座標**，換算函式見 Task 1；渲染既有標記時則反向操作（原始整頁座標 → 裁切後可視座標），完全落在裁切範圍外的標記不渲染。
- 裁切編輯模式（`cropEditModeActive`）與長按框選互斥——裁切編輯模式期間使用者在拖曳裁切框的四角控制點，不應同時觸發劃線框選手勢。
- 多指觸控時取消進行中的框選（比照已刪除的舊原生架構既有行為），讓雙指縮放不會被卡住的框選狀態干擾。
- 本工單只需完成書籤 toggle 的**邏輯本身**（可透過既有測試 seam 觸發驗證）；toggle 對應的 FAB 按鈕留給 Issue 8 統一接線，本工單不在 `reader_screen.dart` 的 body Stack 新增任何按鈕。
- 不修改：`app/lib/reader/pdf_selection_info.dart`、`app/lib/reader/percent_rect.dart`、`app/lib/reader/pdf_annotation_decoration.dart`、`app/lib/reader/highlight.dart`、`app/lib/reader/note.dart`、`app/lib/reader/bookmark.dart`、`app/lib/reader/highlight_style.dart`、`app/lib/reader/*_repository.dart`、`app/lib/screens/annotation_toolbar.dart`、`app/test/reader/pdf_reader_view_test.dart`、`app/test/reader/pdf_reader_view_dual_page_test.dart`、`app/test/reader/pdf_reader_view_filters_test.dart`（Issue 1/2/3 既有測試，diff 必須為空）。

---

## File Structure

- **Create:** `app/lib/reader/pdf_selection_geometry.dart`（純函式模組：拖曳座標→百分比矩形、裁切正反座標換算、退化選取判斷）
- **Create:** `app/test/reader/pdf_selection_geometry_test.dart`
- **Create:** `app/test/reader/pdf_reader_view_selection_test.dart`（widget test，真實 fixture，獨立於既有三份 `pdf_reader_view_*_test.dart`，讓「Issue 1/2/3 測試零回歸」可用 `git diff` 直接證明）
- **Modify:** `app/lib/reader/pdf_reader_view.dart`（新增長按拖曳框選手勢、選取中即時矩形視覺回饋、多指取消、`onSelectionRectComputed`/`onSelectionCanceled` 回呼、既有標記渲染使 `refreshAnnotations` 從 no-op 變為真正生效）
- **Modify:** `app/lib/screens/reader_screen.dart`（`PdfReaderView` 建構呼叫新增 2 個回呼參數、PDF 版本書籤 toggle 邏輯與 static 測試 seam）
- **Modify:** `app/test/screens/reader_screen_test.dart`（新增選取回呼接線與書籤 toggle 測試）
- **不修改：** 見上方 Global Constraints 清單。

---

### Task 1：`pdf_selection_geometry.dart`——拖曳座標換算與裁切正反轉換（純函式，無 pdfrx/Flutter 相依）

**Files:**
- Create: `app/lib/reader/pdf_selection_geometry.dart`
- Create: `app/test/reader/pdf_selection_geometry_test.dart`

**Interfaces:**
- Consumes: 既有 `app/lib/reader/percent_rect.dart`（`PercentRect`）、`app/lib/reader/pdf_crop_rect.dart`（`PdfCropRect`）。
- Produces: `PercentRect? percentRectFromDrag({required Offset start, required Offset end, required Size areaSize, double minFraction = 0.01})`、`PercentRect cropRelativeToOriginalPercent({required PercentRect rect, required PdfCropRect? cropRect})`、`PercentRect? originalToCropRelativePercent({required PercentRect rect, required PdfCropRect? cropRect})`。供 Task 2（拖曳結束時換算選取矩形）與 Task 4（既有標記渲染時換算顯示位置）使用。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_selection_geometry_test.dart`：

```dart
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
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_selection_geometry_test.dart`
Expected: 編譯失敗（`pdf_selection_geometry.dart` 尚不存在）。

- [ ] **Step 3: 建立 `pdf_selection_geometry.dart`**

```dart
import 'dart:ui' show Offset, Size;

import 'pdf_crop_rect.dart';
import 'percent_rect.dart';

/// PDF 長按框選座標換算純函式核心（epic-24-pdf-engine-rebuild Issue 4）。
/// 不依賴 pdfrx/Flutter widget（僅用 dart:ui 的 Offset/Size 值型別），
/// 可在純 Dart 環境直接呼叫、單元測試。

/// 把使用者拖曳的起訖座標（[start]／[end]，皆為相對 [areaSize] 這塊區域
/// 左上角的局部座標，單位與 [areaSize] 相同）換算為正規化（left<right、
/// top<bottom）且夾限在 [0,1] 範圍內的 [PercentRect]。
///
/// [minFraction] 為最小有效選取比例（預設 1%）：寬度或高度小於這個比例
/// 時視為使用者長按後幾乎沒有移動（誤觸/退化選取，不是有意義的框選），
/// 回傳 null，呼叫端應視同「取消」處理，不建立劃線/備註。移植自已刪除
/// 原生 `PdfReaderView.kt` 的 `minFraction = 0.01f` 既有防呆常數。
PercentRect? percentRectFromDrag({
  required Offset start,
  required Offset end,
  required Size areaSize,
  double minFraction = 0.01,
}) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  final left = clamp01((start.dx < end.dx ? start.dx : end.dx) / areaSize.width);
  final right = clamp01((start.dx > end.dx ? start.dx : end.dx) / areaSize.width);
  final top = clamp01((start.dy < end.dy ? start.dy : end.dy) / areaSize.height);
  final bottom = clamp01((start.dy > end.dy ? start.dy : end.dy) / areaSize.height);
  if ((right - left) < minFraction || (bottom - top) < minFraction) return null;
  return PercentRect(left: left, top: top, right: right, bottom: bottom);
}

/// 把「相對裁切後可視內容」的百分比矩形 [rect]，換算回「相對原始整頁」
/// 的百分比矩形——持久化選取結果前使用，確保之後裁切矩形變更或關閉時
/// 既有標記位置仍然正確（不會跟著上一次的裁切範圍跑位）。[cropRect] 為
/// null（裁切未啟用）時原樣回傳，等同單位轉換。
PercentRect cropRelativeToOriginalPercent({
  required PercentRect rect,
  required PdfCropRect? cropRect,
}) {
  if (cropRect == null) return rect;
  final w = cropRect.right - cropRect.left;
  final h = cropRect.bottom - cropRect.top;
  return PercentRect(
    left: cropRect.left + rect.left * w,
    top: cropRect.top + rect.top * h,
    right: cropRect.left + rect.right * w,
    bottom: cropRect.top + rect.bottom * h,
  );
}

/// [cropRelativeToOriginalPercent] 的反函式：把「相對原始整頁」的既有
/// 標記矩形 [rect] 換算為「相對裁切後可視內容」的矩形，供裁切啟用時渲染
/// 既有標記使用。完全落在裁切範圍外時回傳 null，呼叫端應跳過渲染這筆
/// 標記；部分重疊時換算結果會被夾限到 [0,1]（只顯示可見的那一部分）。
/// [cropRect] 為 null 時原樣回傳。
PercentRect? originalToCropRelativePercent({
  required PercentRect rect,
  required PdfCropRect? cropRect,
}) {
  if (cropRect == null) return rect;
  if (rect.right <= cropRect.left ||
      rect.left >= cropRect.right ||
      rect.bottom <= cropRect.top ||
      rect.top >= cropRect.bottom) {
    return null; // 完全落在裁切範圍外。
  }
  final w = cropRect.right - cropRect.left;
  final h = cropRect.bottom - cropRect.top;
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  return PercentRect(
    left: clamp01((rect.left - cropRect.left) / w),
    top: clamp01((rect.top - cropRect.top) / h),
    right: clamp01((rect.right - cropRect.left) / w),
    bottom: clamp01((rect.bottom - cropRect.top) / h),
  );
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_selection_geometry_test.dart`
Expected: 12 項測試全數 PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_selection_geometry.dart app/test/reader/pdf_selection_geometry_test.dart
git commit -m "feat(epic-24): 新增 pdf_selection_geometry 純函式模組——拖曳座標換算與裁切正反轉換"
```

---

### Task 2：`PdfReaderView` 接上長按拖曳框選手勢——即時視覺回饋與 `onSelectionRectComputed`/`onSelectionCanceled`

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Create: `app/test/reader/pdf_reader_view_selection_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `percentRectFromDrag`、既有 `app/lib/reader/pdf_selection_info.dart`（`PdfSelectionInfo`）。
- Produces: `PdfReaderView` 新增建構參數 `onSelectionRectComputed`（`ValueChanged<PdfSelectionInfo>?`）、`onSelectionCanceled`（`VoidCallback?`）。`_PdfReaderViewState` 新增 `_activeDragState`（進行中的框選追蹤）與擴充後的 `_buildProcessedOverlay`（疊上手勢偵測層與即時矩形）。供 Task 3（多指取消/裁切互斥）、Task 6（`reader_screen.dart` 接住回呼）使用。

**本 Task 刻意的測試順序**：先寫「不傳回呼時行為與 Issue 1/2/3 完全相同」的零回歸基準測試，再寫「模擬長按拖曳手勢後正確觸發 `onSelectionRectComputed`」的測試。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_selection_test.dart`（樣板沿用 Issue 1-3 既有測試檔）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';

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

  testWidgets('不傳選取回呼時，行為與 Issue 1/2/3 完全相同（零回歸基準）',
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

    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '翻頁行為不受本工單新增邏輯影響');
  });

  testWidgets('長按拖曳後放開，觸發 onSelectionRectComputed 且矩形座標在合理範圍內',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final pageFinder = find.byType(PdfReaderView);
    final topLeft = tester.getTopLeft(pageFinder);
    final startPos = topLeft + const Offset(40, 60);
    final endPos = topLeft + const Offset(160, 220);

    final gesture = await tester.startGesture(startPos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(endPos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(computed, isNotNull, reason: '長按滿足時長且有明顯拖曳位移，應觸發選取回呼');
    expect(computed!.pageIndex, 0);
    expect(computed!.rect.left, greaterThanOrEqualTo(0));
    expect(computed!.rect.right, lessThanOrEqualTo(1));
    expect(computed!.rect.left, lessThan(computed!.rect.right));
    expect(computed!.rect.top, lessThan(computed!.rect.bottom));
  });

  testWidgets('長按但幾乎沒有拖曳位移（退化選取）時，不觸發 onSelectionRectComputed',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final pos = topLeft + const Offset(100, 150);

    final gesture = await tester.startGesture(pos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(computed, isNull, reason: '沒有明顯拖曳位移的長按不應建立選取');
  });

  testWidgets('長按拖曳過程中即時顯示選取矩形視覺回饋', (tester) async {
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

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsOneWidget,
        reason: '拖曳過程中應顯示即時選取矩形視覺回饋');

    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing,
        reason: '放開後即時回饋應消失（改由呼叫端決定是否顯示 AnnotationToolbar）');
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 編譯失敗（`onSelectionRectComputed` 尚不存在）。

- [ ] **Step 3: `PdfReaderView` 新增建構參數與長按拖曳手勢**

新增 import：

```dart
import 'pdf_selection_geometry.dart';
import 'pdf_selection_info.dart';
```

新增建構參數（與既有 Issue 3 欄位群組並列）：

```dart
  // ── epic-24-pdf-engine-rebuild Issue 4 新增 ──
  /// 使用者長按拖曳框選完成（且非退化選取）時觸發，回報的座標已换算為
  /// 相對原始整頁（裁切啟用時已反向換算，見 pdf_selection_geometry.dart）。
  final ValueChanged<PdfSelectionInfo>? onSelectionRectComputed;
  /// 選取被取消時觸發（例如多指觸控介入，見 Task 3）。
  final VoidCallback? onSelectionCanceled;
```

```dart
    this.onSelectionRectComputed,
    this.onSelectionCanceled,
```

在 `_PdfReaderViewState` 新增欄位（`_cropDetectionInFlight` 之後）：

```dart
  // ── Issue 4: 長按拖曳框選 ──

  /// 進行中的框選追蹤：非 null 代表使用者正在某一頁上長按拖曳。記錄手勢
  /// 開始時所在的頁碼與該頁當下的 `pageRectInViewer`（拖曳過程中頁面
  /// 理論上不會移動——長按辨識成功後 `pdfrx` 內建平移已經輸掉競技場，
  /// 見上方「手勢架構決策」），以及拖曳起點/目前終點的局部座標。
  _PdfSelectionDragState? _selectionDrag;
```

在檔案結尾（`PdfReaderView` class 之後，供 Isolate 頂層函式所在的同一個區塊之前）新增私有資料類別：

```dart
/// [_PdfReaderViewState] 內部使用的框選追蹤狀態，不對外暴露。
class _PdfSelectionDragState {
  _PdfSelectionDragState({required this.pageIndex, required this.areaSize, required this.start})
      : current = start;

  final int pageIndex;
  final Size areaSize;
  final Offset start;
  Offset current;
}
```

在 `_buildProcessedOverlay` 內、`return const [];`／回傳前的既有邏輯之後，把回傳值從單一 `RawImage`／空清單擴充為可疊加清單，並在清單最後加入手勢偵測層（**必須排在清單最後**——`pageOverlaysBuilder` 的回傳值會被 `pdfrx` 包進 `Stack(children: overlay)`，清單順序即畫面疊放順序，手勢偵測層需要疊在最上層才能正確接收觸控）：

```dart
  List<Widget> _buildProcessedOverlay(
    BuildContext context,
    Rect pageRectInViewer,
    PdfPage page,
  ) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    _maybeDetectCropRect(page, devicePixelRatio);
    final pageIndex = page.pageNumber - 1;
    final widgets = <Widget>[];

    if (_cropEnabled || _committedBoldStrength > 0) {
      final cacheKey = (crop: widget.pdfCropRect, bold: _committedBoldStrength);
      if (_overlayCacheKey[page.pageNumber] != cacheKey) {
        unawaited(_recomputeOverlay(page, cacheKey, devicePixelRatio)
            .catchError((e) {
          debugPrint('pdf_reader_view: overlay recompute failed: $e');
        }));
      } else {
        final image = _touchOverlayCache(page.pageNumber);
        if (image != null) widgets.add(RawImage(image: image, fit: BoxFit.fill));
      }
    }

    final drag = _selectionDrag;
    if (drag != null && drag.pageIndex == pageIndex) {
      widgets.add(_buildDragIndicator(drag));
    }

    widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer.size));

    return widgets;
  }
```

（上面這段等於把 Task 5-7 原本「直接 `return` 加粗/裁切覆蓋圖或空清單」的寫法，改成先蒐集到 `widgets` 這個可變清單、最後統一回傳；行為對加粗/裁切部分完全不變，只是資料流從「單一 return」改為「累積後 return」，供本 Task 疊加選取相關 widget。）

新增即時拖曳矩形視覺回饋：

```dart
  Widget _buildDragIndicator(_PdfSelectionDragState drag) {
    final rect = Rect.fromPoints(drag.start, drag.current);
    return Positioned.fromRect(
      key: const Key('pdf_reader_selection_drag_indicator'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.yellow.withValues(alpha: 0.3),
          border: Border.all(color: Colors.orange, width: 1.5),
        ),
      ),
    );
  }
```

新增手勢偵測層：

```dart
  Widget _buildSelectionGestureLayer(int pageIndex, Size areaSize) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: areaSize,
              start: details.localPosition,
            );
          });
        },
        onLongPressMoveUpdate: (details) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = details.localPosition);
        },
        onLongPressEnd: (details) => _finishSelectionDrag(),
        onLongPressCancel: () => _cancelSelectionDrag(),
      ),
    );
  }

  void _finishSelectionDrag() {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final draggedRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (draggedRect == null) return; // 退化選取，等同取消。
    final originalRect = cropRelativeToOriginalPercent(
      rect: draggedRect,
      cropRect: _cropEnabled ? widget.pdfCropRect : null,
    );
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: draggedRect, // 見 Step 3 補充說明：widgetRect 換算方式。
    ));
  }

  void _cancelSelectionDrag() {
    if (_selectionDrag == null) return;
    setState(() => _selectionDrag = null);
    widget.onSelectionCanceled?.call();
  }
```

**`widgetRect` 換算的暫時簡化說明**：本 Task 先把 `widgetRect` 設為與裁切後可視內容相對的 `draggedRect`（未反向換算裁切、也未换算成相對整個 `PdfReaderView` 而非單一頁面）——這是刻意的中間狀態，`widgetRect` 唯一用途是 `reader_screen.dart` 拿來定位浮動 `AnnotationToolbar`（見 Task 6），只要求「大致落在選取範圍附近」即可，不要求逐位元精確；Task 3 會補上跨頁面座標系統的正確換算。本 Step 先確保 `rect`（用於持久化）是完全正確的，`widgetRect`（僅用於 UI 定位）留到 Task 3 補強，避免本 Task 一次處理太多座標系統。

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 4 項測試全數 PASS。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_filters_test.dart`
Expected: Issue 1/2/3 既有測試全數 PASS，**且三個檔案 `git diff` 皆為空**。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "feat(epic-24): PdfReaderView 接上長按拖曳框選手勢與即時視覺回饋"
```

---

### Task 3：多指觸控取消選取、裁切編輯模式互斥、`widgetRect` 正確換算

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`

**Interfaces:**
- Consumes: Task 1 的座標換算函式。
- Produces: `_PdfReaderViewState` 新增 `_activePointerCount` 追蹤與外層 `Listener`；`_finishSelectionDrag` 改為正確换算 `widgetRect`（相對整個 `PdfReaderView` 尺寸，非單一頁面）。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 新增：

```dart
  testWidgets('框選進行中第二指觸控介入時，取消選取並觸發 onSelectionCanceled',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    var canceled = false;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
          onSelectionCanceled: () => canceled = true,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsOneWidget);

    final secondFinger = await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(canceled, isTrue, reason: '第二指觸控應取消進行中的框選');
    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing);

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    expect(computed, isNull, reason: '被取消的選取不應觸發 onSelectionRectComputed');
  });

  testWidgets('cropEditModeActive=true 時，長按拖曳不觸發框選（與裁切互斥）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          cropEditModeActive: true,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_selection_drag_indicator')), findsNothing,
        reason: '裁切編輯模式下不應顯示框選視覺回饋');

    await gesture.up();
    await tester.pump();
    expect(computed, isNull);
  });

  testWidgets('widgetRect 相對整個 PdfReaderView 尺寸，而非單一頁面（多頁情境下 top 應反映頁面在文件中的位置）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 2000,
          child: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onSelectionRectComputed: (info) => computed = info,
          ),
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(computed, isNotNull);
    // widgetRect 與 rect 皆為 0-1 範圍內的有效值；在夠高的可視區域內，
    // 第一頁通常從畫面最頂端開始，widgetRect.top 應是一個很小的值。
    expect(computed!.widgetRect.top, greaterThanOrEqualTo(0));
    expect(computed!.widgetRect.top, lessThanOrEqualTo(1));
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart --plain-name "第二指"`
Expected: FAIL（`_activePointerCount`/多指取消尚未實作）。

- [ ] **Step 3: 新增多指取消、裁切互斥防呆、`widgetRect` 正確換算**

在 `_PdfReaderViewState` 新增欄位（`_selectionDrag` 之後）：

```dart
  int _activePointerCount = 0;
```

修改 `build()`，在既有的 `ColorFiltered`/`viewer` 回傳之前，用 `Listener` 包住整個 widget 樹以偵測任何指標按下/放開（**放在最外層**，才能觀察到落在頁面 overlay 手勢層之外的觸控，例如第二指落在 `pdfrx` 自己的平移辨識區域）：

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
        layoutPages: _cropEnabled
            ? _layoutCroppedPages
            : (_dualPageEnabled ? _layoutSpreadPages : null),
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
        pageOverlaysBuilder: _buildProcessedOverlay,
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
    final colorFiltered = colorFilter == null
        ? viewer
        : ColorFiltered(colorFilter: colorFilter, child: viewer);
    return Listener(
      onPointerDown: (_) {
        _activePointerCount++;
        if (_activePointerCount >= 2) _cancelSelectionDrag();
      },
      onPointerUp: (_) => _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
      onPointerCancel: (_) => _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
      child: colorFiltered,
    );
  }
```

修改 `_buildSelectionGestureLayer` 的 `onLongPressStart`，把裁切編輯模式防呆邏輯集中到手勢層入口（Step 3 之前的版本已有一份 `if (widget.cropEditModeActive) return;`，維持不動即可，本 Step 不需要修改這段）。

修改 `_finishSelectionDrag`，正確換算 `widgetRect`（相對整個 `PdfReaderView` 尺寸，而非拖曳所在單一頁面）——需要拿到 `pageRectInViewer` 在整個 viewer 中的絕對位置，而不只是該頁自己的尺寸。為此，把 `_PdfSelectionDragState` 增加一個 `pageOffsetInViewer` 欄位，並在 `_buildSelectionGestureLayer` 建立時一併帶入：

```dart
class _PdfSelectionDragState {
  _PdfSelectionDragState({
    required this.pageIndex,
    required this.areaSize,
    required this.pageOffsetInViewer,
    required this.start,
  }) : current = start;

  final int pageIndex;
  final Size areaSize;
  final Offset pageOffsetInViewer;
  final Offset start;
  Offset current;
}
```

在 `_buildProcessedOverlay` 呼叫 `_buildSelectionGestureLayer` 時多傳入 `pageRectInViewer.topLeft`：

```dart
    widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer));
```

`_buildSelectionGestureLayer` 簽章與內部建構 `_PdfSelectionDragState` 處改為：

```dart
  Widget _buildSelectionGestureLayer(int pageIndex, Rect pageRectInViewer) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: details.localPosition,
            );
          });
        },
        onLongPressMoveUpdate: (details) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = details.localPosition);
        },
        onLongPressEnd: (details) => _finishSelectionDrag(),
        onLongPressCancel: () => _cancelSelectionDrag(),
      ),
    );
  }
```

`_finishSelectionDrag` 改為額外算出相對整個 `PdfReaderView` 尺寸的 `widgetRect`（透過 `context.size`——`_PdfReaderViewState` 的 `build()` 回傳樹頂層即為本 widget 自身尺寸，`context` 用 state 自己的 `context` 即可，不需要額外傳遞）：

```dart
  void _finishSelectionDrag() {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final pageRelativeRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (pageRelativeRect == null) return; // 退化選取，等同取消。
    final originalRect = cropRelativeToOriginalPercent(
      rect: pageRelativeRect,
      cropRect: _cropEnabled ? widget.pdfCropRect : null,
    );
    final viewerSize = context.size;
    final widgetRect = viewerSize == null || viewerSize.isEmpty
        ? pageRelativeRect // 理論上不會發生（拖曳能完成代表已經 layout 過）。
        : percentRectFromDrag(
            start: drag.pageOffsetInViewer +
                Offset(drag.start.dx, drag.start.dy),
            end: drag.pageOffsetInViewer + Offset(drag.current.dx, drag.current.dy),
            areaSize: viewerSize,
            minFraction: 0, // 已經在上面用 pageRelativeRect 判斷過退化選取，這裡不重複擋。
          )!;
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: widgetRect,
    ));
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全部 7 項測試 PASS。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_filters_test.dart`
Expected: 全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "feat(epic-24): PdfReaderView 框選手勢新增多指取消、裁切互斥、widgetRect 正確換算"
```

---

### Task 4：既有標記渲染——`refreshAnnotations` 從 no-op 變為真正生效

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `originalToCropRelativePercent`、既有 `app/lib/reader/pdf_annotation_decoration.dart`（`PdfAnnotationDecoration`）。
- Produces: `PdfReaderView.refreshAnnotations` 真正把資料寫入對應 State（透過既有 `GlobalKey` 命令式呼叫慣例，比照 `jumpToPage`）；`_buildProcessedOverlay` 疊加每頁對應的標記 widget。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
```

新增測試：

```dart
  testWidgets('refreshAnnotations 呼叫後，對應頁面顯示標記疊圖', (tester) async {
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

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget,
        reason: 'refreshAnnotations 應觸發重繪並顯示對應頁面的標記');
  });

  testWidgets('同一頁有多筆標記時，逐筆使用不同 key 渲染，不觸發 Duplicate Key 例外',
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

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.3, right: 0.5, bottom: 0.4),
        tint: 0x73F472B6,
      ),
    ]);
    await tester.pump();

    // 兩筆標記都在 page 0，若 key 只用 pageIndex 組成會彼此相同，
    // Flutter 會在 pumpWidget/pump 期間擲出「Multiple widgets used the
    // same key」例外，tester.pump() 之後 takeException() 會抓到；本測試
    // 先確認沒有例外，再確認兩個 key 都各自渲染出一個 widget。
    expect(tester.takeException(), isNull,
        reason: '同頁多筆標記不應觸發 Duplicate Key 例外');
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget);
    expect(find.byKey(const Key('pdf_reader_decoration_0_1')), findsOneWidget);
  });

  testWidgets('再次呼叫 refreshAnnotations 傳入空清單時，既有標記全部移除',
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

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsOneWidget);

    PdfReaderView.refreshAnnotations(key, const []);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing,
        reason: '整批送出語意（非增量 diff）：空清單代表本書已無任何標記');
  });

  testWidgets('裁切啟用時，完全落在裁切範圍外的標記不渲染', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: PdfCropMode.manual,
          pdfCropRect: const PdfCropRect(left: 0.4, top: 0.4, right: 0.6, bottom: 0.6),
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.refreshAnnotations(key, const [
      PdfAnnotationDecoration(
        pageIndex: 0,
        rect: PercentRect(left: 0, top: 0, right: 0.1, bottom: 0.1), // 完全在裁切範圍外。
        tint: 0x73FDE047,
      ),
    ]);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_decoration_0_0')), findsNothing,
        reason: '標記完全落在裁切可視範圍外時不應渲染');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart --plain-name "refreshAnnotations"`
Expected: FAIL（`refreshAnnotations` 仍是 no-op）。

- [ ] **Step 3: `refreshAnnotations` 改為真正生效，`_buildProcessedOverlay` 疊加標記**

修改 `PdfReaderView.refreshAnnotations`（class 內 static method）：

```dart
  /// 一次性送出目前應顯示的完整標記清單（非增量 diff，比照 EPUB
  /// `EpubDecoration`／`setDecorations` 整組送出慣例）——epic-24 Issue 4
  /// 落地，取代 Issue 1 暫時性 no-op。[key] 對應的 State 若尚未掛載，
  /// 靜默忽略。
  static void refreshAnnotations(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setAnnotations(annotations);
    }
  }
```

在 `_PdfReaderViewState` 新增欄位（`_selectionDrag` 之後）：

```dart
  List<PdfAnnotationDecoration> _annotations = const [];

  void _setAnnotations(List<PdfAnnotationDecoration> annotations) {
    if (!mounted) return;
    setState(() => _annotations = annotations);
  }
```

在 `_buildProcessedOverlay` 內、加入手勢層之前（拖曳即時回饋之前），插入既有標記疊圖——**注意用 `decorationIndex` 而非只用 `pageIndex` 組 key**：`pageOverlaysBuilder` 回傳的整份清單會被 `pdfrx` 包進同一個 `Stack(children: overlay)`（見本檔案頂部「架構決策」已查證的原始碼），若同一頁有 2 筆以上標記卻共用同一把 `Key`，會在同一個 `Stack` 底下出現重複 key，Flutter 的 element 對帳機制會直接擲出「Multiple widgets used the same key」執行期例外（`/superpowers:receiving-code-review` 審查 Important #1 抓到的問題——本計畫最初版本的 key 只含 `pageIndex`，只有單頁單筆標記的測試情境剛好沒有觸發）：

```dart
    var decorationIndex = 0;
    for (final decoration in _annotations) {
      if (decoration.pageIndex != pageIndex) continue;
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(rect: decoration.rect, cropRect: widget.pdfCropRect)
          : decoration.rect;
      if (visibleRect == null) continue; // 完全落在裁切範圍外。
      widgets.add(_buildDecorationWidget(
        pageIndex,
        decorationIndex++,
        decoration,
        visibleRect,
        pageRectInViewer.size,
      ));
    }
```

新增標記渲染 widget（螢光筆/底線兩種樣式＋純備註圖釘標示，樣式比照已刪除原生 `drawAnnotationOverlays`／`drawNoteOnlyMarker` 的視覺意圖，改以 Flutter widget 而非直接畫進 bitmap 實現）：

```dart
  Widget _buildDecorationWidget(
    int pageIndex,
    int decorationIndex,
    PdfAnnotationDecoration decoration,
    PercentRect visibleRect,
    Size areaSize,
  ) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    final color = Color(decoration.tint);
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 decorationIndex——同一頁可能有多筆
      // 標記，只用 pageIndex 當 key 在同頁多筆標記時會產生重複 key。
      key: Key('pdf_reader_decoration_${pageIndex}_$decorationIndex'),
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (decoration.isUnderline)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 2, color: color),
            )
          else
            Container(color: color),
          if (decoration.isNoteOnly)
            const Positioned(
              right: -6,
              top: -6,
              child: Icon(Icons.push_pin, size: 16, color: Colors.black87),
            ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全部 11 項測試 PASS（Task 2 的 4 項＋Task 3 的 3 項＋本 Task 的 4 項，含審查新增的同頁多筆標記回歸測試）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_filters_test.dart`
Expected: 全數 PASS，diff 為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "feat(epic-24): PdfReaderView refreshAnnotations 落地——既有標記疊圖渲染"
```

---

### Task 5：雙頁模式下框選正確歸屬單一頁面（回歸測試，構造性保證的驗證）

**Files:**
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`

**Interfaces:**
- Consumes: Task 2-4 已完成的手勢與換算邏輯（本 Task 不新增任何 `pdf_reader_view.dart` 程式碼，純粹驗證 Global Constraints 宣稱的「構造性保證」）。

**本 Task 為何沒有 Step 3「新增實作」**：Global Constraints 已經說明，雙頁模式下的座標歸屬正確性是 `pageOverlaysBuilder` 逐頁呼叫這件事本身保證的，不需要額外程式碼——本 Task 只是把這個宣稱寫成可執行的回歸測試，一旦未來有人修改 `_buildProcessedOverlay`／`_buildSelectionGestureLayer` 導致這個保證被破壞，測試會失敗。

- [ ] **Step 1: 撰寫測試**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/dual_page_mode.dart';
```

新增測試：

```dart
  testWidgets('雙頁模式下，在右頁長按拖曳，選取結果歸屬右頁而非左頁',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // 封面獨立顯示，第一個雙頁 spread 是 [1,2]（0-indexed page 1、2）。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 找到右頁（page 2）的疊加層：以其手勢偵測層的 Positioned.fill 所在
    // RenderBox 中心點觸發長按拖曳。由於 LTR 排版下 spread [1,2] 內
    // page 2 在右側，直接對整個 PdfReaderView 右半部觸發手勢即可命中。
    final box = tester.getRect(find.byType(PdfReaderView));
    final rightHalfStart = Offset(box.left + box.width * 0.75, box.top + box.height * 0.3);
    final rightHalfEnd = Offset(box.left + box.width * 0.9, box.top + box.height * 0.5);

    final gesture = await tester.startGesture(rightHalfStart);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(rightHalfEnd);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(computed, isNotNull);
    expect(computed!.pageIndex, 2,
        reason: 'spread [1,2] 內觸控畫面右半部應命中 page 2（0-indexed），'
            '不是 page 1');
  });
```

- [ ] **Step 2: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart --plain-name "雙頁模式下"`
Expected: PASS（若失敗，代表本 Task 開頭宣稱的「構造性保證」不成立，須回頭檢查 Task 2-4 的 `_buildProcessedOverlay`/`_buildSelectionGestureLayer` 是否有地方誤用了合併後的 spread 座標而非單頁座標，而不是在本 Task 新增修補程式碼）。

- [ ] **Step 3: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "test(epic-24): 驗證雙頁模式下框選正確歸屬單一頁面（構造性保證回歸測試）"
```

---

### Task 6：`reader_screen.dart` 接上選取回呼——`_currentPdfSelection` 從死碼變為可觸發

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2-3 的 `PdfReaderView.onSelectionRectComputed`/`onSelectionCanceled`。
- Produces: `_ReaderScreenState` 新增 `_handlePdfSelectionRectComputed`/`_handlePdfSelectionCanceled`（比照既有 `_handleSelectionChanged`/`_handleSelectionCleared`），接上 `PdfReaderView` 建構呼叫。既有的 `_currentPdfSelection`、`_handlePdfHighlightStyleSelected`、`_handlePdfNotePressed`、`_pdfAnnotationToolbarTop`、body Stack 內的 `AnnotationToolbar` Positioned 區塊**完全不用修改**——這些都是已刪除舊原生架構遺留、完整且正確的既有程式碼，只是從未被觸發過。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/reader_screen_test.dart`（`app/test/screens/reader_screen_test.dart`）新增（沿用既有 PDF 分支測試樣板——直接用 `MaterialApp(home: ReaderScreen(...))` 建構＋`tester.runAsync` 輪詢等待 pdfrx 真實載入完成，比照本檔案既有 PDF 測試慣例）：

```dart
  testWidgets('PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後 Toolbar 消失且劃線已寫入',
      (tester) async {
    final highlightsRepository = FakeHighlightsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: highlightsRepository,
          notesRepository: FakeNotesRepository(),
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

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar');

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_yellow')));
    await tester.pumpAndSettle();

    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '選色後應建立劃線並清空選取狀態，Toolbar 隨之消失');
    final saved = await highlightsRepository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.pdfPageIndex, 0);
  });

  testWidgets('PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
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

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();
    final secondFinger = await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
  });
```

（已核對 `app/test/support/fake_highlights_repository.dart`／`fake_notes_repository.dart`：`FakeHighlightsRepository()`／`FakeNotesRepository()` 皆為無參數建構子、`insert(Highlight/Note)`／`listByBook(bookId)` 簽章與上方程式碼一致，不需調整；`AnnotationToolbar` 需從 `package:elinkbook/screens/annotation_toolbar.dart` import。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "長按拖曳框選完成"`
Expected: FAIL（`PdfReaderView` 尚未接上 `onSelectionRectComputed`）。

- [ ] **Step 3: `reader_screen.dart` 接上選取回呼**

新增兩個 handler（放在既有 `_handleSelectionChanged`/`_handleSelectionCleared` 之後，供對照）：

```dart
  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = info;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  void _handlePdfSelectionCanceled() {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }
```

在 `PdfReaderView(...)` 建構呼叫（`reader_screen.dart` 內 `return PdfReaderView(` 一帶）新增兩個參數：

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
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS（含新增 2 項與既有測試零回歸）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): reader_screen.dart 接上 PDF 選取回呼，AnnotationToolbar 恢復可觸發"
```

---

### Task 7：PDF 書籤 toggle 邏輯（測試 seam，UI 按鈕留給 Issue 8）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_fxlBookmarks`/`_loadFxlBookmarks()`（跨格式共用的書籤快取，儘管命名沿用歷史上的 `fxl` 前綴）、既有 `BookmarkPositionContext.pdfPageIndex`、既有 `Bookmark.defaultName()`。
- Produces: `_ReaderScreenState._bookmarkAtCurrentPdfPosition`（getter）、`_togglePdfBookmark()`（method）、`ReaderScreen.togglePdfBookmark`（static 測試 seam，比照既有 `ReaderScreen.triggerZoneAction` 模式）。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 新增：

```dart
  testWidgets('PDF 書籤 toggle：目前頁無書籤時呼叫後新增一筆，頁碼定位正確',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
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

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.pdfPageIndex, 0);
    expect(saved.single.name, '第 1 頁');
  });

  testWidgets('PDF 書籤 toggle：目前頁已有書籤時呼叫後移除該筆', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(Bookmark(
      id: 'existing',
      bookId: 'b1',
      name: '第 1 頁',
      pdfPageIndex: 0,
    ));
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
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

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, isEmpty, reason: '已存在同頁書籤時應移除，而非重複新增');
  });
```

（已核對 `app/test/support/fake_bookmarks_repository.dart`：`FakeBookmarksRepository()` 為無參數建構子，`insert(Bookmark)`／`listByBook(bookId)`／`delete(id)` 簽章與上方程式碼一致，不需調整。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "PDF 書籤 toggle"`
Expected: 編譯失敗（`ReaderScreen.togglePdfBookmark` 尚不存在）。

- [ ] **Step 3: 新增 PDF 書籤 toggle 邏輯**

在 `_ReaderScreenState` 新增 getter 與方法（放在既有 `_bookmarkAtCurrentPosition`/`_toggleBookmark`——EPUB 版本——之後，供對照參考；**不修改** EPUB 版本本體）：

```dart
  /// PDF 版本的「目前頁是否已有書籤」查詢，比照 EPUB 的
  /// [_bookmarkAtCurrentPosition]，但比對基準是 [_pdfPageInfo]?.pageIndex
  /// 而非 EPUB 的 Locator JSON。
  Bookmark? get _bookmarkAtCurrentPdfPosition {
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (pageIndex == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.pdfPageIndex == pageIndex) return bookmark;
    }
    return null;
  }

  /// PDF 版本的書籤 toggle：本工單只需完成邏輯本身（見 issues.md Issue 4
  /// 範圍界定），對應的 FAB 按鈕留給 Issue 8 統一接線——目前僅能透過
  /// [ReaderScreen.togglePdfBookmark] 這個測試 seam 觸發，UI 尚無法直接
  /// 點擊呼叫。
  Future<void> _togglePdfBookmark() async {
    final repository = widget.bookmarksRepository;
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (repository == null || pageIndex == null) return;
    final existing = _bookmarkAtCurrentPdfPosition;
    if (existing != null) {
      await repository.delete(existing.id);
    } else {
      await repository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(pdfPageIndex: pageIndex)),
        pdfPageIndex: pageIndex,
      ));
    }
    await _loadFxlBookmarks();
  }
```

在 `ReaderScreen`（class，非 State）新增 static 測試 seam，比照既有 `triggerZoneAction` 模式（放在 `triggerZoneAction` 之後）：

```dart
  /// 供測試（Issue 4 範圍：書籤 toggle 邏輯已完成，對應 FAB 按鈕留給
  /// Issue 8）安全呼叫 [_ReaderScreenState._togglePdfBookmark] 的強型別
  /// static helper，比照 [triggerZoneAction] 既有模式。[key] 對應的 State
  /// 若尚未掛載，靜默忽略。
  static void togglePdfBookmark(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      unawaited(state._togglePdfBookmark());
    }
  }
```

（若檔案頂部尚未 import `dart:async`（供 `unawaited`），確認既有 import 是否已涵蓋；`reader_screen.dart` 已大量使用 `unawaited`，理論上已有此 import。）

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS（含新增 2 項與既有測試零回歸）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): 新增 PDF 書籤 toggle 邏輯與測試 seam（FAB 按鈕留給 Issue 8）"
```

---

### Task 8：全專案回歸

**Files:**
- 無新增/修改（純驗證 Task）。

**Interfaces:**
- Consumes: Task 1-7 全部產出。

- [ ] **Step 1: 全專案測試**

Run: `cd app && flutter test`
Expected: 全數 PASS，無失敗案例（含 Issue 1-3 既有測試零回歸、本工單 Task 1-7 新增測試）。

- [ ] **Step 2: `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 驗證零回歸的直接證據**

Run:
```bash
git diff -- app/lib/reader/pdf_selection_info.dart app/lib/reader/percent_rect.dart app/lib/reader/pdf_annotation_decoration.dart app/lib/reader/highlight.dart app/lib/reader/note.dart app/lib/reader/bookmark.dart app/lib/reader/highlight_style.dart app/lib/reader/highlights_repository.dart app/lib/reader/notes_repository.dart app/lib/reader/bookmarks_repository.dart app/lib/screens/annotation_toolbar.dart app/test/reader/pdf_reader_view_test.dart app/test/reader/pdf_reader_view_dual_page_test.dart app/test/reader/pdf_reader_view_filters_test.dart
```
Expected: 空輸出（Global Constraints 列出的不得修改檔案清單，一個字元的異動都不應該有）。

- [ ] **Step 4: 真機驗證提醒（非阻塞、建議事項）**

比照本 Epic「與 spec.md 的偏離」/「手勢架構決策」段落已記錄的殘留風險：長按拖曳框選與 `pdfrx` 內建平移/縮放是否在真實觸控序列（非 `WidgetTester` 合成事件）下正確互斥，`flutter test` 無法完整驗證，建議合併前或合併後盡快找機會在真機/模擬器上實測「長按拖曳框選＋雙指縮放＋單指平移翻頁」三者互不干擾，若發現問題記錄為後續修正項，不阻塞本工單合併（比照 design.md 決策 5 的既有風險排序原則）。

- [ ] **Step 5: Commit**（若前面步驟有任何修正）

```bash
git add -A
git commit -m "fix(epic-24): Issue 4 全專案回歸修正"
```

---

## Self-Review Notes（供實作者與審查者參考，非待辦事項）

- **Spec Coverage**：spec.md「劃線/備註/選取機制」與「書籤」兩節的全部要求（保留矩形選取、雙頁模式單頁座標基準、`Highlight`/`Note`/`Bookmark` 免 schema 遷移、書籤 toggle 邏輯）在 Task 1-7 皆有對應實作與測試。issues.md Issue 4 的全部 6 項 Acceptance Criteria 對應：長按拖曳框選（Task 2-3）、雙頁座標基準（Task 5）、劃線/備註持久化與重新開書還原顯示（Task 4，`refreshAnnotations` 落地＋`reader_screen.dart` 既有 `_reloadPdfAnnotationsAndSync` 在 `_handlePageRendered` 已會自動觸發，不需要額外接線）、書籤 toggle（Task 7）、單元測試涵蓋（Task 1/2/3/5/6/7）、`flutter analyze`/`flutter test` 零回歸（Task 8）。
- **裁切模式與選取的座標換算是本工單獨有的新複雜度**：`epic-24` 前三個 Issue 都沒有處理「畫面顯示的東西經過幾何變換、但持久化座標系統必須維持不變」這個問題，Task 1 的正反換算函式與其對稱性測試（`cropRelativeToOriginalPercent`/`originalToCropRelativePercent` 互為反函式）是這個複雜度的核心防線，實作/審查時應特別注意這兩個函式改動時是否還保持對稱。
- **未涵蓋、留給後續工單**：Issue 8（PDF FAB 工具列整合）需要新增書籤 toggle 對應的 FAB 按鈕本身（本工單只完成邏輯＋測試 seam）；長按拖曳框選與 `pdfrx` 內建手勢在真實觸控序列下的互斥，`flutter test` 無法完整驗證，需要真機/模擬器驗證（Task 8 Step 4 已記錄，非阻塞）。
- **與已刪除舊原生架構的關鍵行為差異（刻意，非遺漏）**：既有標記渲染從「直接畫進 bitmap」改為「Flutter widget 疊加層」（`pdfrx` 沒有暴露 bitmap 修改鉤子，沿用 Issue 3 建立的 `pageOverlaysBuilder` 疊加模式）；`PdfAnnotationDecoration` 沒有 `id` 欄位、PDF 端仍不支援點擊既有標記互動（維持既有限制，非本工單新增）。
- **審查回應紀錄**：本計畫已依 `tmp/epic-24/review-plan-issue-4.md`（2026-08-09）修正 Important #1——`_buildDecorationWidget` 的 `Key` 原本只含 `pageIndex`，`pageOverlaysBuilder` 整份回傳清單會被 `pdfrx` 包進同一個 `Stack(children: overlay)`，同一頁有 2 筆以上標記時會因 key 重複觸發 Flutter「Multiple widgets used the same key」執行期例外——原始版本的 Task 4 測試只涵蓋單頁單筆標記情境，未能自行發現這個問題。修法為 key 同時包含 `pageIndex`／`decorationIndex`，並新增一則「同一頁有多筆標記」的專屬回歸測試（斷言 `tester.takeException()` 為 null）。Minor Suggestion 1（`widgetRect` 在極少數 layout 調整時機的穩定度）審查結論本身已判定設計無需修改，僅提醒實作階段留意真機 Toolbar 定位精準度，未變更計畫程式碼。
