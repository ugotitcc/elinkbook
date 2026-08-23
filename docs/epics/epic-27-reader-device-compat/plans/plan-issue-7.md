# Epic 27 Issue 7：PDF 手動裁切疊加層高對比視覺與 FAB 按鈕重構 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解決各種佈景下 PDF 裁切模式選擇框在白底書籍上無法識別、確認與取消按鈕為白色隱形的問題，加入挖空半透明遮罩、雙色高對比框線、圓形控制手柄與深對比 FAB 浮動按鈕。

**Architecture:**
- 使用 `CustomPainter`（`CropOverlayPainter`）以四個不重疊矩形色帶（上/下/左/右）繪製外部半透明暗色遮罩（50% 黑色），並繪製雙層高對比邊框（外層純黑 3px ＋ 內層純白 1.5px）。【審查修正 Important】原案採 `Path.combine(PathOperation.difference, ...)` 做布林運算，但裁切框是使用者拖曳四角即時更新的互動元件——`_dragHandle()`（`pdf_crop_frame_overlay.dart:42-60`）每個 `onPanUpdate` 觸控影格都會 `setState()`，導致 `shouldRepaint` 幾乎每影格觸發一次 `Path.combine`。Path 布林運算相對於四個矩形直接疊色運算量明顯較高，本產品目標裝置明確包含 E-Ink／低效能硬體（本 Issue 情境正是電子紙裝置回報的可辨識度問題），在互動拖曳每影格都做布林運算有實際掉幀風險。改用四矩形色帶（不需要 `Path.combine`）在數學上與挖空遮罩視覺效果完全等價、運算量遠低，故直接採用此方案取代原案，不需要額外節流。
- `CropOverlayPainter` 必須鋪滿整個 `LayoutBuilder` 量到的可用畫布（`Positioned.fill`，而非只鋪在裁切框範圍內），並接收「絕對座標」的 `cropRect`（即既有 `frameRect` 變數，非 `_left/_top/_right/_bottom` 的 0-1 比例值），取代舊有 `Positioned.fromRect(rect: frameRect, child: Container(decoration: BoxDecoration(border: ...)))` 這段畫框邏輯——邊框與遮罩改由 `CropOverlayPainter` 一次畫完。
- 四角控制手柄改為帶邊框與陰影之圓形手柄，擴大觸控命中區域。
- 底部確認與取消按鈕升級為高對比深底色 **FAB 樣式浮動按鈕**：
  - 取消按鈕（`Key('pdf_crop_frame_cancel')`）：圓形深灰/黑色背景（`Color(0xFF2A2A2E)`）＋ 白色 `Icons.close` 圖示 ＋ 白色細邊框 ＋ Elevation 6。
  - 確認按鈕（`Key('pdf_crop_frame_confirm')`）：圓形高對比深綠/主題色背景（`Color(0xFF16A34A)`）＋ 白色 `Icons.check` 圖示 ＋ 白色細邊框 ＋ Elevation 6。

**Tech Stack:** Flutter 3, Dart, CustomPainter, Canvas

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 7」

## Global Constraints

- **Language**: 程式碼註解與說明一律使用正體中文 (Traditional Chinese, zh-TW)。
- **Flutter Analyze**: 靜態分析必須保持 0 warning / 0 error。
- **Keys**: 嚴格保留 `pdf_crop_frame_confirm`、`pdf_crop_frame_cancel`、`pdf_crop_frame_handle_top_left`、`pdf_crop_frame_handle_top_right`、`pdf_crop_frame_handle_bottom_left`、`pdf_crop_frame_handle_bottom_right`。

---

### Task 1: 實作遮罩繪製與 FAB 按鈕重構

**Files:**
- Modify: `app/lib/reader/pdf_crop_frame_overlay.dart`
- Test: `app/test/reader/pdf_crop_frame_overlay_test.dart`

**Interfaces:**
- Consumes: `PdfCropFrameOverlay({required initialRect, required onConfirm, required onCancel})`
- Produces: 包含 `CropOverlayPainter` 遮罩與高對比 FAB 樣式之 `PdfCropFrameOverlay`

- [x] **Step 1: Write the failing test**

在 `app/test/reader/pdf_crop_frame_overlay_test.dart` 中追加測試：

```dart
testWidgets('PdfCropFrameOverlay 包含 CustomPaint 遮罩層與帶背景之 Material 按鈕', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 1600,
          child: PdfCropFrameOverlay(
            initialRect: const PdfCropRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
            onConfirm: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );

  expect(find.byType(CustomPaint), findsWidgets);
  expect(find.byKey(const Key('pdf_crop_frame_confirm')), findsOneWidget);
  expect(find.byKey(const Key('pdf_crop_frame_cancel')), findsOneWidget);

  // 驗證確認按鈕有 Material 容器包裹（非純透明 IconButton）
  final confirmMaterial = find.ancestor(
    of: find.byKey(const Key('pdf_crop_frame_confirm')),
    matching: find.byType(Material),
  );
  expect(confirmMaterial, findsWidgets);
});
```

- [x] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/reader/pdf_crop_frame_overlay_test.dart`
預期：FAIL（因既有實作確認按鈕只是 IconButton，沒有 Material 祖先）。

- [x] **Step 3: Write minimal implementation**

在 `app/lib/reader/pdf_crop_frame_overlay.dart`：
1. 新增 `CropOverlayPainter`（【審查修正 Important】改用四個不重疊矩形色帶取代 `Path.combine` 布林運算，理由見上方 Architecture 段落）：
```dart
class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Size canvasSize;
  CropOverlayPainter({required this.cropRect, required this.canvasSize});

  @override
  void paint(Canvas canvas, Size size) {
    // 外部半透明遮罩：上/下/左/右四個不重疊色帶，數學上與挖空遮罩視覺
    // 效果等價，但不需要 Path.combine 布林運算——裁切框拖曳互動下每個
    // 觸控影格都會重繪，四矩形運算量遠低於 Path 布林運算，對 E-Ink／
    // 低效能裝置更友善（見 reviews/review-plan-issue-5-8.md Issue 7
    // Important #2）。
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, cropRect.top), maskPaint);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.bottom, size.width, size.height), maskPaint);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom), maskPaint);
    canvas.drawRect(Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom), maskPaint);

    // 雙層高對比邊框（外黑 3.0px，內白 1.5px）
    final outerBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final innerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(cropRect, outerBorder);
    canvas.drawRect(cropRect, innerBorder);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) =>
      cropRect != oldDelegate.cropRect || canvasSize != oldDelegate.canvasSize;
}
```
2. 【審查修正 Important：原案漏了這一步，`CropOverlayPainter` 定義了卻沒有接入畫面會變成死碼】在 `build()` 的 `Stack` 中，用下面這段取代既有的 `Positioned.fromRect(rect: frameRect, child: Container(decoration: BoxDecoration(border: ...)))`（`pdf_crop_frame_overlay.dart:99-106`）——`CropOverlayPainter` 需要拿到絕對座標的 `frameRect`（既有變數，非 `_left/_top/_right/_bottom` 的 0-1 比例值）與整個可用畫布尺寸，故用 `Positioned.fill` 鋪滿，而非只鋪在裁切框範圍內：
```dart
Positioned.fill(
  child: CustomPaint(
    painter: CropOverlayPainter(cropRect: frameRect, canvasSize: size),
  ),
),
```
3. 更新 `_buildHandle` 為圓形帶邊框與陰影控制點（【審查修正 Minor】原案只有一句文字描述，比照另外兩段補上具體程式碼；`key: key` 維持掛在最外層可被拖曳手勢命中的 `GestureDetector` 上，與既有 6 則測試的 `tester.drag(find.byKey(...))` 用法保持相容，不動）：
```dart
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
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
      ),
    ),
  );
}
```
4. 底部確認與取消按鈕改為高對比 FAB 樣式按鈕：
```dart
Positioned(
  bottom: 32,
  left: 0,
  right: 0,
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Material(
        elevation: 6,
        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 1.5)),
        color: const Color(0xFF2A2A2E),
        child: InkWell(
          key: const Key('pdf_crop_frame_cancel'),
          customBorder: const CircleBorder(),
          onTap: widget.onCancel,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.close, color: Colors.white, size: 28),
          ),
        ),
      ),
      const SizedBox(width: 48),
      Material(
        elevation: 6,
        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 1.5)),
        color: const Color(0xFF16A34A),
        child: InkWell(
          key: const Key('pdf_crop_frame_confirm'),
          customBorder: const CircleBorder(),
          onTap: () => widget.onConfirm(
            PdfCropRect(left: _left, top: _top, right: _right, bottom: _bottom),
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.check, color: Colors.white, size: 28),
          ),
        ),
      ),
    ],
  ),
)
```

- [x] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/reader/pdf_crop_frame_overlay_test.dart`
預期：全數 7 個測試 PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/pdf_crop_frame_overlay.dart app/test/reader/pdf_crop_frame_overlay_test.dart
git commit -m "feat(epic-27): Issue 7——PdfCropFrameOverlay 實作挖空半透明遮罩與高對比 FAB 按鈕"
```
