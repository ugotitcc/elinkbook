# Epic 4 Issue 6：手動選區裁切 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `PdfSettingsSheet` 裁切分頁啟用「手動選區」第三選項，讓使用者透過原生 `CropOverlayView` 疊加層拖拉四角控制點框選裁切範圍，確認後套用並持久化為 `pdfCropMode = manual`。

**Architecture:** 沿用 Issue 5 已建立的 `cropMode`/`cropRect` 渲染管線（`renderCurrentPage()` 依 `effectiveCrop` 調整 `Matrix`，`manual` 模式已可正確渲染任何已提供的矩形，不需改動）。本 issue 新增的是「如何取得使用者手動框選的矩形」這一段：`PdfReaderView.kt` 的 `getView()` 從單一 `ImageView`改為包一層 `FrameLayout`，讓新增的 `CropOverlayView`（自訂 `View`）能疊加在 `imageView` 之上；互動模式透過宣告式的 `cropEditModeActive: bool` 輸入參數（`PdfReaderView` 既有慣例，見 spec.md）進入/離開，使用者拖拉裁切框四角、點擊原生繪製的確認按鈕後，透過 `onCropRectSelected` 回呼把結果交回 Dart 端；Dart 端收到後把 `cropEditModeActive` 撥回 `false`（宣告式，觸發 `exitCropEditMode` 送出），並把結果寫入 `BookReaderPrefs`。

**Tech Stack:** Flutter（Dart）+ Android 原生 Kotlin（`View`／`Canvas`／`MotionEvent` 手動繪製與觸控處理，不使用第三方裁切函式庫，見 design.md 決策 #14）。

## Global Constraints

- **技術棧鎖定為 Native，非 Flutter 全螢幕畫面**（design.md 決策 #14）：裁切互動疊加層必須是 `PdfReaderView.kt` 上的原生 `View`，不新建獨立 Flutter 全螢幕畫面，避免大尺寸 Bitmap 跨 method channel 傳輸的效能/記憶體代價。
- **`PdfReaderView` 契約異動皆為宣告式**（spec.md「介面」）：`cropEditModeActive: bool`（預設 `false`）與既有 `fitMode`/`contrast`/`cropMode` 等欄位風格一致，`didUpdateWidget` 偵測 `false→true`/`true→false` 分別送出 `enterCropEditMode`/`exitCropEditMode`；`exitCropEditMode` **只由 Dart 端在收到 `onCropRectSelected` 後把 prop 撥回 `false` 才會送出，原生端絕不主動呼叫 `exitCropEditMode()` 自己清理**（沒有獨立「取消」語意，見 spec.md 第 123 行）——原生端收到使用者點擊確認手勢後，**只**透過 `channel.invokeMethod("onCropRectSelected", ...)` 通知 Dart，不自行移除 overlay；移除動作統一等待 Dart 送回 `exitCropEditMode` 才執行（單向宣告式資料流，不要在原生端抄捷徑提前清理）。
- **裁切矩形語意**：`PdfCropRect`（`left`/`top`/`right`/`bottom`，0.0–1.0）永遠相對**完整原始頁面**，不是相對「目前已裁切畫面」——因此進入裁切互動模式時，畫面必須暫時改為顯示**完整未裁切頁面**（不管目前 `cropMode` 為何），讓使用者從整頁範圍框選，避免「裁切一個已經被裁切過的畫面」造成座標混淆。
- **初始框選範圍**：若已有快取的 `cropRect`（不論來自先前的 `autoDetect` 或 `manual`），進入編輯模式時沿用該矩形作為起始框，讓使用者「微調」既有選區；否則預設置中、四周各留 10% 邊距。
- **確認手勢的具體 UI 未在 spec.md/design.md 定案**（design.md 決策 #12 僅指出「類似手機相簿的裁切工具，四角拖拉裁切框」）：本計劃選擇在 `CropOverlayView` 的 `Canvas` 上直接繪製一個固定位置（右下角）的圓形打勾確認按鈕，觸控命中該按鈕範圍內的 down+up 視為確認手勢——這是規劃階段的實作決策，不是規格異動。
- **`PdfReaderView.kt` 既有 `CropRect`（Issue 5 引入的內部資料類別）目前是 `private data class`**：本 issue 需要讓新檔案 `CropOverlayView.kt`（同套件 `cc.ugotit.elinkbook`，不同檔案）也能使用它，因此 Task 2 會把 `private` 修飾詞移除（Kotlin 同套件不需要 import，改為套件內可見即可）——這是刻意、最小幅度的可見度放寬，不改變欄位或行為。
- **渲染管線本身不需改動**：Issue 5 的 `renderCurrentPage()` 已能正確處理 `cropMode == "manual"` + 任意已提供 `cropRect` 的渲染（`effectiveCrop = if (cropMode != "none") cropRect else null`），本 issue 純粹是「如何取得使用者手動框選的矩形」，不涉及 `renderCurrentPage()` 的裁切套用邏輯本身。
- **翻頁手勢在裁切互動模式下暫停**：透過原生端 `nextPage()`/`previousPage()` 方法頂端的 `cropEditModeActive` 守衛實作（不論呼叫來源是 Flutter 手勢或其他管道），這是唯一事實來源，不在 Dart 端另外停用 `GestureDetector`。
- **承接 Issue 5 whole-branch review 的兩點交接提醒**（見 `issues.md` Issue 6 區塊）：
  1. `PdfReaderView.dart` 的 `didUpdateWidget` 目前只比較 `cropMode`、不比較 `cropRect`（因為 Issue 5 唯一會寫入 `cropRect` 的來源是原生端主動回呼）。本 issue 讓使用者能在 `cropMode` 已經是 `manual` 的情況下重新選取新的裁切框——但這個情境本身**不經過 `cropRect` prop 的變動**：手動選區的結果是透過獨立的 `onCropRectSelected` 回呼（原生 → Dart）取得，不是透過 Dart 端主動把新 `cropRect` 塞進 `PdfReaderView` 的 prop 觸發 `setPdfPreferences`（那是 Issue 5 建立的、給「已持久化好的值」使用的路徑，例如重開書）。因此本 issue **不需要**修改 `didUpdateWidget` 對 `cropRect` 的比較邏輯——手動選區的資料流完全走 `cropEditModeActive`/`onCropRectSelected` 這條獨立通道，與 `didUpdateWidget` 是否比較 `cropRect` 無關。此提醒僅供設計脈絡參考，本 issue 範圍內不需動作。
  2. `detectCropRect()`（智慧自動裁切）在近乎全白的頁面上可能算出退化矩形，此為 Issue 5 已知殘留風險，與本 issue（手動選區）無直接關聯，不在本 issue 範圍內處理。
- **原生端無法透過 `flutter test` 驗證觸控拖拉邏輯**（spec.md「測試決策」，沿用既有慣例，見 `docs/archive/2026-07-10-epic-3-fonts-layout/issues.md` Issue 2）：`CropOverlayView.kt` 的手勢/繪製邏輯只能透過真機 `integration_test`（Task 5）與人工視覺確認驗證，Task 2 的驗收標準是「編譯成功＋不影響既有 19 個真機測試」，不要求（也無法要求）該任務自己產出觸控邏輯的自動化測試。
- **螢幕截圖視覺比對為必要步驟，不是可選項**（本 epic 自 Issue 3 起確立的紀律）：Task 5 的真機驗證除了 `integration_test` 綠燈之外，必須實際用 `Read` 工具檢視螢幕截圖並在報告中誠實描述看到的畫面內容；若受限於環境無法完成某項視覺確認，必須在報告中誠實記錄，不得宣稱已完成。

---

### Task 1：`PdfReaderView`（Dart）—— `cropEditModeActive`／`onCropRectSelected` 契約

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：既有 `PdfReaderView` 建構參數（`fitMode`/`contrast`/`brightness`/`boldStrength`/`cropMode`/`cropRect`/`onCropRectComputed`，Issue 2-5 已建立，本 task 不變動）。
- Produces：`PdfReaderView.cropEditModeActive: bool`（預設 `false`）、`PdfReaderView.onCropRectSelected: ValueChanged<PdfCropRect>?`——供 Task 4（`ReaderScreen`）使用。

- [ ] **Step 1：撰寫失敗測試——`cropEditModeActive` 由 `false` 變 `true` 時觸發 `enterCropEditMode`**

在 `app/test/reader/pdf_reader_view_test.dart` 檔案最後一個 `testWidgets` 之後、`}`（`main()` 結尾）之前新增：

```dart
  testWidgets('cropEditModeActive 由 false 變 true 時，didUpdateWidget 呼叫 enterCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: true, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'enterCropEditMode');
    expect(instanceCalls.single.arguments, isNull);
  });

  testWidgets('cropEditModeActive 由 true 變 false 時，didUpdateWidget 呼叫 exitCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: true,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: false, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'exitCropEditMode');
    expect(instanceCalls.single.arguments, isNull);
  });

  testWidgets('cropEditModeActive 未變動時，不觸發 enterCropEditMode／exitCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      cropEditModeActive: false,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });

  testWidgets('收到原生端 onCropRectSelected 時，正確觸發回呼', (tester) async {
    PdfCropRect? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onCropRectSelected: (rect) => received = rect,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onCropRectSelected', {
      'left': 0.1,
      'top': 0.15,
      'right': 0.9,
      'bottom': 0.85,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received,
        const PdfCropRect(left: 0.1, top: 0.15, right: 0.9, bottom: 0.85));
  });
```

- [ ] **Step 2：執行測試，確認全數 FAIL**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: 新增的 4 個測試 FAIL（`cropEditModeActive`/`onCropRectSelected` 建構參數不存在，編譯錯誤）。

- [ ] **Step 3：修改 `app/lib/reader/pdf_reader_view.dart`——新增建構參數**

把第 21-55 行的 class 定義改為（新增 `cropEditModeActive`／`onCropRectSelected` 兩個欄位，插入於既有 `onCropRectComputed` 之後）：

```dart
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<int>? onPageChanged;
  final PdfFitMode? fitMode;
  final double? contrast;
  final double? brightness;
  final double? boldStrength;
  final PdfCropMode? cropMode;
  final PdfCropRect? cropRect;
  final ValueChanged<PdfCropRect>? onCropRectComputed;
  final bool cropEditModeActive;
  final ValueChanged<PdfCropRect>? onCropRectSelected;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
    this.onCropRectSelected,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}
```

- [ ] **Step 4：修改 `didUpdateWidget`——新增 `cropEditModeActive` 判斷**

把第 70-80 行的 `didUpdateWidget` 改為：

```dart
  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness ||
        widget.boldStrength != oldWidget.boldStrength ||
        widget.cropMode != oldWidget.cropMode) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
    if (widget.cropEditModeActive != oldWidget.cropEditModeActive) {
      _channel?.invokeMethod(
        widget.cropEditModeActive ? 'enterCropEditMode' : 'exitCropEditMode',
      );
    }
  }
```

- [ ] **Step 5：修改 `_handleMethodCall`——新增 `onCropRectSelected` case**

把第 102-124 行的 `_handleMethodCall` 改為（在既有 `onCropRectComputed` case 之後新增一個 case）：

```dart
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onPageChanged':
        final pageIndex = call.arguments as int;
        widget.onPageChanged?.call(pageIndex);
        break;
      case 'onCropRectComputed':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onCropRectComputed?.call(PdfCropRect(
          left: (args['left'] as num).toDouble(),
          top: (args['top'] as num).toDouble(),
          right: (args['right'] as num).toDouble(),
          bottom: (args['bottom'] as num).toDouble(),
        ));
        break;
      case 'onCropRectSelected':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onCropRectSelected?.call(PdfCropRect(
          left: (args['left'] as num).toDouble(),
          top: (args['top'] as num).toDouble(),
          right: (args['right'] as num).toDouble(),
          bottom: (args['bottom'] as num).toDouble(),
        ));
        break;
    }
  }
```

- [ ] **Step 6：執行測試，確認全數 PASS**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: 全數 PASS（既有測試 + 本 task 新增的 4 個）。

- [ ] **Step 7：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-4): PdfReaderView 新增 cropEditModeActive/onCropRectSelected 契約"
```

---

### Task 2：原生端——`CropOverlayView.kt` 新建 ＋ `PdfReaderView.kt` 裁切互動模式整合

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Consumes：Task 1 建立的 Dart 端 `enterCropEditMode`／`exitCropEditMode`（Dart→原生，無參數）method channel 呼叫；既有 `PdfReaderView.kt` 的 `renderer`／`currentPageIndex`／`context`／`channel`／`cropRect` 欄位。
- Produces：`CropOverlayView`（Kotlin class，建構子 `CropOverlayView(context: Context, pageWidthPx: Int, pageHeightPx: Int, initialRelativeRect: PdfReaderView.CropRect, onConfirm: (PdfReaderView.CropRect) -> Unit)`）；`PdfReaderView.kt` 新增的 `onCropRectSelected`（原生→Dart，`Map<String, Double>`，格式同既有 `onCropRectComputed`）method channel 呼叫，供 Task 4（`ReaderScreen`）串接。

本任務原生端邏輯無法透過 `flutter test` 驗證（見 Global Constraints），驗收標準為「編譯成功＋不影響既有測試」，不要求自行產出觸控邏輯的自動化測試。

- [ ] **Step 1：新建 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`**

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View

/**
 * 手動裁切互動疊加層（design.md 決策 #14）：疊加於 PdfReaderView 的
 * imageView 之上，顯示可拖拉四角控制點的裁切框，並提供一個固定位置
 * （右下角）的確認按鈕。只在 PdfReaderView.enterCropEditMode() 期間加入
 * View 樹，exitCropEditMode() 時移除。
 *
 * 座標系統：[pageWidthPx]／[pageHeightPx] 是目前頁面渲染時使用的像素尺寸
 * （由呼叫端提供），用來計算 FIT_CENTER letterbox 後頁面內容在本 View 內
 * 的實際顯示範圍 [contentBounds]；裁切框的拖拉範圍限制在 [contentBounds]
 * 內。[onConfirm] 回傳的矩形已換算為相對頁面座標（0.0-1.0），對應
 * PdfCropRect 的語意——呼叫端（PdfReaderView）收到後只透過 channel 通知
 * Dart 端（onCropRectSelected），不在此處自行移除 overlay，等待 Dart 端
 * 依宣告式流程送回 exitCropEditMode 才清理（見 plan-issue-6.md Global
 * Constraints「PdfReaderView 契約異動皆為宣告式」）。
 */
class CropOverlayView(
    context: Context,
    private val pageWidthPx: Int,
    private val pageHeightPx: Int,
    initialRelativeRect: PdfReaderView.CropRect,
    private val onConfirm: (PdfReaderView.CropRect) -> Unit,
) : View(context) {

    companion object {
        private const val HANDLE_RADIUS_DP = 10f
        private const val HANDLE_TOUCH_SLOP_DP = 24f
        private const val MIN_CROP_FRACTION = 0.1f // 裁切框最小尺寸，相對 contentBounds 的比例
        private const val CONFIRM_BUTTON_RADIUS_DP = 24f
        private const val CONFIRM_BUTTON_MARGIN_DP = 16f
    }

    private val density = context.resources.displayMetrics.density
    private val handleRadiusPx = HANDLE_RADIUS_DP * density
    private val touchSlopPx = HANDLE_TOUCH_SLOP_DP * density
    private val confirmRadiusPx = CONFIRM_BUTTON_RADIUS_DP * density
    private val confirmMarginPx = CONFIRM_BUTTON_MARGIN_DP * density

    private val dimPaint = Paint().apply { color = Color.argb(153, 0, 0, 0) } // 60% 黑，裁切框外遮罩
    private val borderPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
    }
    private val handlePaint = Paint().apply { color = Color.WHITE; style = Paint.Style.FILL }
    private val confirmBgPaint =
        Paint().apply { color = Color.parseColor("#4CAF50"); style = Paint.Style.FILL }
    private val confirmCheckPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
        strokeCap = Paint.Cap.ROUND
    }

    // 頁面內容在本 View 內的實際顯示範圍（FIT_CENTER letterbox），layout
    // 完成、寬高已知後才計算，見 onSizeChanged()。
    private var contentBounds = RectF()

    // 裁切框目前狀態（View 像素座標，限制在 contentBounds 內）。
    private var cropRectPx = RectF()

    // 只在第一次 onSizeChanged（初次 layout）時套用初始矩形，之後若因裝置
    // 旋轉等原因再次觸發 onSizeChanged，保留使用者當下已調整的框選狀態
    // （已知限制：旋轉當下 contentBounds 改變但 cropRectPx 未重新夾範圍，
    // 見 plan-issue-6.md「已知限制」，本 issue 不處理裁切編輯中旋轉裝置的
    // 情境，屬刻意簡化範圍）。
    private var pendingInitialRect: PdfReaderView.CropRect? = initialRelativeRect

    private var activeHandle: Handle? = null
    private var confirmPressed = false

    private enum class Handle { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        contentBounds = computeContentBounds(w, h)
        val rect = pendingInitialRect ?: return
        cropRectPx = RectF(
            contentBounds.left + rect.left * contentBounds.width(),
            contentBounds.top + rect.top * contentBounds.height(),
            contentBounds.left + rect.right * contentBounds.width(),
            contentBounds.top + rect.bottom * contentBounds.height(),
        )
        pendingInitialRect = null
    }

    /**
     * FIT_CENTER letterbox 數學：頁面依長寬比置中縮放至剛好完整顯示於
     * View 內，多餘空間留白。手動重算是因為裁切框需要知道確切的顯示範圍
     * 才能正確換算座標，ImageView 本身不會公開這個計算結果。
     */
    private fun computeContentBounds(viewWidth: Int, viewHeight: Int): RectF {
        if (viewWidth <= 0 || viewHeight <= 0 || pageWidthPx <= 0 || pageHeightPx <= 0) {
            return RectF(0f, 0f, viewWidth.toFloat(), viewHeight.toFloat())
        }
        val viewRatio = viewWidth.toFloat() / viewHeight.toFloat()
        val pageRatio = pageWidthPx.toFloat() / pageHeightPx.toFloat()
        return if (pageRatio > viewRatio) {
            // 頁面較「寬」：滿版寬度，上下留白
            val displayHeight = viewWidth / pageRatio
            val top = (viewHeight - displayHeight) / 2f
            RectF(0f, top, viewWidth.toFloat(), top + displayHeight)
        } else {
            // 頁面較「高」：滿版高度，左右留白
            val displayWidth = viewHeight * pageRatio
            val left = (viewWidth - displayWidth) / 2f
            RectF(left, 0f, left + displayWidth, viewHeight.toFloat())
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // 裁切框外的四塊區域畫暗色遮罩，讓使用者聚焦於選取範圍。
        canvas.drawRect(0f, 0f, width.toFloat(), cropRectPx.top, dimPaint)
        canvas.drawRect(0f, cropRectPx.bottom, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRect(0f, cropRectPx.top, cropRectPx.left, cropRectPx.bottom, dimPaint)
        canvas.drawRect(cropRectPx.right, cropRectPx.top, width.toFloat(), cropRectPx.bottom, dimPaint)

        canvas.drawRect(cropRectPx, borderPaint)
        canvas.drawCircle(cropRectPx.left, cropRectPx.top, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.right, cropRectPx.top, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.left, cropRectPx.bottom, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.right, cropRectPx.bottom, handleRadiusPx, handlePaint)

        val confirmCx = width - confirmMarginPx - confirmRadiusPx
        val confirmCy = height - confirmMarginPx - confirmRadiusPx
        canvas.drawCircle(confirmCx, confirmCy, confirmRadiusPx, confirmBgPaint)
        // 簡易打勾圖案（兩段折線）
        canvas.drawLine(
            confirmCx - confirmRadiusPx * 0.4f, confirmCy,
            confirmCx - confirmRadiusPx * 0.1f, confirmCy + confirmRadiusPx * 0.35f,
            confirmCheckPaint,
        )
        canvas.drawLine(
            confirmCx - confirmRadiusPx * 0.1f, confirmCy + confirmRadiusPx * 0.35f,
            confirmCx + confirmRadiusPx * 0.45f, confirmCy - confirmRadiusPx * 0.35f,
            confirmCheckPaint,
        )
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val confirmCx = width - confirmMarginPx - confirmRadiusPx
        val confirmCy = height - confirmMarginPx - confirmRadiusPx

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val dxConfirm = event.x - confirmCx
                val dyConfirm = event.y - confirmCy
                if (dxConfirm * dxConfirm + dyConfirm * dyConfirm <= confirmRadiusPx * confirmRadiusPx) {
                    confirmPressed = true
                    return true
                }
                activeHandle = nearestHandle(event.x, event.y)
                return activeHandle != null
            }
            MotionEvent.ACTION_MOVE -> {
                val handle = activeHandle ?: return false
                updateHandle(handle, event.x, event.y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (confirmPressed) {
                    confirmPressed = false
                    val dxConfirm = event.x - confirmCx
                    val dyConfirm = event.y - confirmCy
                    if (dxConfirm * dxConfirm + dyConfirm * dyConfirm <= confirmRadiusPx * confirmRadiusPx) {
                        onConfirm(currentRelativeRect())
                    }
                    return true
                }
                activeHandle = null
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun nearestHandle(x: Float, y: Float): Handle? {
        val candidates = listOf(
            Handle.TOP_LEFT to (cropRectPx.left to cropRectPx.top),
            Handle.TOP_RIGHT to (cropRectPx.right to cropRectPx.top),
            Handle.BOTTOM_LEFT to (cropRectPx.left to cropRectPx.bottom),
            Handle.BOTTOM_RIGHT to (cropRectPx.right to cropRectPx.bottom),
        )
        var nearest: Handle? = null
        var nearestDistSq = touchSlopPx * touchSlopPx
        for ((handle, point) in candidates) {
            val dx = x - point.first
            val dy = y - point.second
            val distSq = dx * dx + dy * dy
            if (distSq <= nearestDistSq) {
                nearest = handle
                nearestDistSq = distSq
            }
        }
        return nearest
    }

    private fun updateHandle(handle: Handle, x: Float, y: Float) {
        val minSize = minOf(contentBounds.width(), contentBounds.height()) * MIN_CROP_FRACTION
        val clampedX = x.coerceIn(contentBounds.left, contentBounds.right)
        val clampedY = y.coerceIn(contentBounds.top, contentBounds.bottom)
        when (handle) {
            Handle.TOP_LEFT -> {
                cropRectPx.left = clampedX.coerceAtMost(cropRectPx.right - minSize)
                cropRectPx.top = clampedY.coerceAtMost(cropRectPx.bottom - minSize)
            }
            Handle.TOP_RIGHT -> {
                cropRectPx.right = clampedX.coerceAtLeast(cropRectPx.left + minSize)
                cropRectPx.top = clampedY.coerceAtMost(cropRectPx.bottom - minSize)
            }
            Handle.BOTTOM_LEFT -> {
                cropRectPx.left = clampedX.coerceAtMost(cropRectPx.right - minSize)
                cropRectPx.bottom = clampedY.coerceAtLeast(cropRectPx.top + minSize)
            }
            Handle.BOTTOM_RIGHT -> {
                cropRectPx.right = clampedX.coerceAtLeast(cropRectPx.left + minSize)
                cropRectPx.bottom = clampedY.coerceAtLeast(cropRectPx.top + minSize)
            }
        }
    }

    private fun currentRelativeRect(): PdfReaderView.CropRect {
        val left = ((cropRectPx.left - contentBounds.left) / contentBounds.width()).coerceIn(0f, 1f)
        val top = ((cropRectPx.top - contentBounds.top) / contentBounds.height()).coerceIn(0f, 1f)
        val right = ((cropRectPx.right - contentBounds.left) / contentBounds.width()).coerceIn(0f, 1f)
        val bottom = ((cropRectPx.bottom - contentBounds.top) / contentBounds.height()).coerceIn(0f, 1f)
        return PdfReaderView.CropRect(left, top, right, bottom)
    }
}
```

- [ ] **Step 2：修改 `PdfReaderView.kt`——`CropRect` 可見度放寬、新增 import**

把第 1-14 行的 import 區塊改為（新增 `android.widget.FrameLayout`）：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
```

把第 66-68 行的 `CropRect` 宣告（`private data class CropRect(...)`）改為移除 `private`：

```kotlin
    /** 裁切矩形（相對座標 0.0-1.0），Kotlin 內部用資料類別，對應 Dart
     * PdfCropRect 的欄位。套件內可見（非 private）供 CropOverlayView.kt
     * 使用（同套件 cc.ugotit.elinkbook，Kotlin 不需額外 import）。*/
    data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)
```

- [ ] **Step 3：修改 `PdfReaderView.kt`——`imageView` 改包一層 `FrameLayout`、新增裁切互動狀態欄位**

把第 30-68 行的 class 主體開頭（欄位宣告區）改為（在既有 `imageView`／`channel` 宣告之間插入 `rootView`，並在既有 `cropRect` 欄位之後新增 `cropEditModeActive`／`cropOverlayView`）：

```kotlin
class PdfReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val imageView: ImageView = ImageView(context)

    // 手動裁切互動模式（決策 #14）需要在 imageView 之上疊加
    // CropOverlayView，因此 getView() 回傳的根 View 從單一 ImageView 改為
    // 包一層 FrameLayout；未進入裁切互動模式時，rootView 只有 imageView
    // 這一個子 View，畫面與改動前完全一致。
    private val rootView: FrameLayout = FrameLayout(context).apply {
        addView(
            imageView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/pdf_reader_view_$id")

    private var renderer: PdfRenderer? = null
    private var currentPageIndex: Int = 0
    private var totalPages: Int = 0

    // Dart PdfFitMode.name 對應字串（'pageFit'／'fitWidth'／'actualSize'），
    // 預設 "pageFit"，與 BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: String = "pageFit"

    // Dart contrast／brightness 值，-100..100，預設 0（無調整），與
    // BookReaderPrefs.pdfContrast/pdfBrightness 為 null 時的語意一致。
    private var contrast: Float = 0f
    private var brightness: Float = 0f

    // Dart boldStrength 值，0..1，預設 0（無加粗），與
    // BookReaderPrefs.pdfBoldStrength 為 null 時的語意一致。
    private var boldStrength: Float = 0f

    // Dart PdfCropMode.name 對應字串（'none'／'autoDetect'／'manual'），
    // 預設 "none"，與 BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: String = "none"

    // 目前生效的裁切矩形（相對座標 0.0-1.0）。autoDetect 模式下由
    // detectCropRect() 首次計算後快取於此（決策 #3，全書統一比例、不逐頁
    // 重算）；也可能由 Dart 端透過 initialPreferences/setPdfPreferences
    // 直接帶入已持久化的值（避免重開書又重新計算一次）；manual 模式下由
    // 使用者透過 CropOverlayView 框選後經 exitCropEditMode 流程間接更新
    // （見 enterCropEditMode()/CropOverlayView 的 onConfirm 回呼）。
    private var cropRect: CropRect? = null

    // 手動裁切互動模式是否進行中（決策 #14）：由 Dart 端
    // cropEditModeActive prop 的宣告式變化驅動（enterCropEditMode／
    // exitCropEditMode method channel 呼叫），true 時 nextPage()／
    // previousPage() 暫停回應，避免翻頁手勢與拖拉裁切框互相干擾。
    private var cropEditModeActive: Boolean = false
    private var cropOverlayView: CropOverlayView? = null

    /** 裁切矩形（相對座標 0.0-1.0），Kotlin 內部用資料類別，對應 Dart
     * PdfCropRect 的欄位。套件內可見（非 private）供 CropOverlayView.kt
     * 使用（同套件 cc.ugotit.elinkbook，Kotlin 不需額外 import）。*/
    data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)
```

（此步驟與 Step 2 合併套用同一份完整欄位宣告區，Step 2 提到的 `CropRect` 已包含在上方程式碼中，不需重複貼一次。）

- [ ] **Step 4：修改 `PdfReaderView.kt`——`getView()` 改回傳 `rootView`**

把第 82 行：

```kotlin
    override fun getView(): View = imageView
```

改為：

```kotlin
    override fun getView(): View = rootView
```

- [ ] **Step 5：修改 `PdfReaderView.kt`——`onMethodCall` 新增 `enterCropEditMode`／`exitCropEditMode` case**

把第 84-109 行的 `onMethodCall` 改為（在既有 `previousPage` case 之後新增兩個 case）：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPdfPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPdfPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                nextPage()
                result.success(null)
            }
            "previousPage" -> {
                previousPage()
                result.success(null)
            }
            "enterCropEditMode" -> {
                enterCropEditMode()
                result.success(null)
            }
            "exitCropEditMode" -> {
                exitCropEditMode()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

- [ ] **Step 6：修改 `PdfReaderView.kt`——`nextPage()`/`previousPage()` 新增裁切互動模式守衛**

把第 462-476 行的 `nextPage()`/`previousPage()` 改為：

```kotlin
    private fun nextPage() {
        if (cropEditModeActive) return
        if (currentPageIndex < totalPages - 1) {
            currentPageIndex++
            renderCurrentPage()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
        if (currentPageIndex > 0) {
            currentPageIndex--
            renderCurrentPage()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }
```

- [ ] **Step 7：修改 `PdfReaderView.kt`——新增 `enterCropEditMode()`／`exitCropEditMode()`／`renderFullPageForCropPreview()`**

在 `detectCropRect()` 方法（原第 284-327 行）之後、`applyFitMode()`（原第 345 行）之前插入以下三個新方法：

```kotlin
    /**
     * 進入手動裁切互動模式（決策 #14）：暫時以「完整未裁切頁面」重新渲染
     * （不管目前 cropMode 設定為何），讓使用者能從整頁範圍框選，避免
     * 「裁切一個已經被裁切過的畫面」造成的座標混淆；並疊加
     * CropOverlayView 讓使用者拖拉四角控制點。翻頁手勢在此模式下停用
     * （見 nextPage()/previousPage() 頂端的 cropEditModeActive 判斷）。
     *
     * 由 onMethodCall 的 "enterCropEditMode" case 呼叫，只在 Dart 端
     * cropEditModeActive prop 由 false 變 true 時觸發（宣告式，見
     * PdfReaderView.dart 的 didUpdateWidget）。
     */
    private fun enterCropEditMode() {
        cropEditModeActive = true
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)
        val pageWidth = page.width
        val pageHeight = page.height
        page.close()

        // 初始框選範圍：若已有裁切矩形（無論來自先前的自動或手動裁切）
        // 沿用之，讓使用者「微調」既有選區；否則預設置中、四周各留 10%
        // 邊距。
        val initial = cropRect ?: CropRect(0.1f, 0.1f, 0.9f, 0.9f)

        val overlay = CropOverlayView(context, pageWidth, pageHeight, initial) { result ->
            // 只透過 channel 通知 Dart 端，不在此處自行移除 overlay——
            // 移除動作統一等待 Dart 送回 exitCropEditMode 才執行（見
            // plan-issue-6.md Global Constraints）。
            channel.invokeMethod(
                "onCropRectSelected",
                mapOf(
                    "left" to result.left.toDouble(),
                    "top" to result.top.toDouble(),
                    "right" to result.right.toDouble(),
                    "bottom" to result.bottom.toDouble(),
                ),
            )
        }
        cropOverlayView = overlay
        rootView.addView(
            overlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        renderFullPageForCropPreview()
    }

    /**
     * 離開手動裁切互動模式：移除 overlay、恢復翻頁手勢，並依目前（可能
     * 已透過 onCropRectSelected 流程更新過 cropMode/cropRect 的）狀態呼叫
     * renderCurrentPage() 重新渲染畫面套用結果。
     *
     * 由 onMethodCall 的 "exitCropEditMode" case 呼叫，只在 Dart 端
     * cropEditModeActive prop 由 true 變 false 時觸發——正常情況下這只會
     * 在 Dart 端收到 onCropRectSelected 後才發生（見 plan-issue-6.md
     * Global Constraints，原生端本身絕不主動呼叫這個方法自己清理）。
     */
    private fun exitCropEditMode() {
        cropEditModeActive = false
        cropOverlayView?.let { rootView.removeView(it) }
        cropOverlayView = null
        renderCurrentPage()
    }

    /**
     * 裁切編輯模式下的預覽渲染：忽略目前 cropMode，永遠顯示完整頁面、
     * 固定 FIT_CENTER，讓 CropOverlayView 的 FIT_CENTER letterbox 座標
     * 換算單純化（見 CropOverlayView.computeContentBounds()）。刻意獨立
     * 於 renderCurrentPage()——後者的裁切/fit/濾鏡管線邏輯與此處「一律
     * 顯示全頁、不套用任何濾鏡」的需求不同，混在一起會讓兩者都變複雜。
     */
    private fun renderFullPageForCropPreview() {
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)
        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)
        val width = (page.width * scale).toInt().coerceAtLeast(1)
        val height = (page.height * scale).toInt().coerceAtLeast(1)
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val matrix = android.graphics.Matrix().apply { postScale(scale, scale) }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            imageView.colorFilter = null
        } catch (e: OutOfMemoryError) {
            // 記憶體不足時放棄預覽渲染，overlay 仍會顯示（背景沿用上一次
            // 畫面），使用者仍可框選，只是背景畫面可能是舊的；不影響裁切
            // 結果正確性（結果仍是相對頁面座標，與背景畫面是否為最新版本
            // 無關）。
        }
        page.close()
    }
```

- [ ] **Step 8：修改 `PdfReaderView.kt`——`dispose()` 新增 overlay 清理**

把第 495-499 行的 `dispose()` 改為：

```kotlin
    override fun dispose() {
        cropOverlayView?.let { rootView.removeView(it) }
        cropOverlayView = null
        renderer?.close()
        renderer = null
        channel.setMethodCallHandler(null)
    }
```

- [ ] **Step 9：編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: `BUILD SUCCESSFUL`（Kotlin 編譯無錯誤——這是本任務唯一能離線驗證的正確性訊號，觸控/繪製邏輯的實際行為留給 Task 5 真機驗證）。

- [ ] **Step 10：既有測試迴歸檢查**

Run: `cd app && flutter test`
Expected: 全數 PASS（本任務未變動任何 Dart 檔案，純粹確認 Kotlin 端改動未間接影響任何既有測試的假設）。

Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`（真實裝置，見 `flutter devices` 取得 device-id）
Expected: 既有 19 個測試全數 PASS——本任務把 `getView()` 從 `imageView` 改為 `rootView`（`FrameLayout`），需要真機確認這個容器改動沒有造成任何既有渲染行為的迴歸（分辨率、Fit 模式、濾鏡、裁切皆不受影響，因為未進入裁切編輯模式時 `rootView` 只有 `imageView` 這一個子 View，行為應與改動前完全一致）。

- [ ] **Step 11：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt \
        app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "feat(epic-4): 新增 CropOverlayView 原生裁切互動疊加層與 PdfReaderView 整合"
```

---

### Task 3：`PdfSettingsSheet`——`onRequestManualCrop` 契約與啟用手動選區選項

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：無新的外部依賴。
- Produces：`PdfSettingsSheet.onRequestManualCrop: VoidCallback`（新增的必要建構參數）——供 Task 4（`ReaderScreen`）使用。

- [ ] **Step 1：撰寫失敗測試——點擊手動選區按鈕觸發 `onRequestManualCrop`，並更新既有測試**

把 `app/test/screens/pdf_settings_sheet_test.dart` 第 208-220 行的既有測試：

```dart
  testWidgets('裁切分頁存在不裁切／智慧自動二選項，手動選區顯示但停用', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdf_settings_crop_mode_none')), findsOneWidget);
    expect(
        find.byKey(const Key('pdf_settings_crop_mode_auto')), findsOneWidget);
    final manualButton = tester.widget<IconButton>(
        find.byKey(const Key('pdf_settings_crop_mode_manual')));
    expect(manualButton.onPressed, isNull, reason: '手動選區留待 Issue 6 實作，本 issue 顯示為停用狀態');
  });
```

改為（手動選區已於本 issue 啟用，不再是停用狀態）：

```dart
  testWidgets('裁切分頁存在不裁切／智慧自動／手動選區三個選項', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdf_settings_crop_mode_none')), findsOneWidget);
    expect(
        find.byKey(const Key('pdf_settings_crop_mode_auto')), findsOneWidget);
    expect(
        find.byKey(const Key('pdf_settings_crop_mode_manual')), findsOneWidget);
  });

  testWidgets('點擊手動選區按鈕後，觸發 onRequestManualCrop（不直接改變 pdfCropMode）',
      (tester) async {
    var requestCount = 0;
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
      onRequestManualCrop: () => requestCount++,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump();

    expect(requestCount, 1);
    // 手動選區的實際框選結果由 ReaderScreen 端的裁切互動模式流程另外
    // 提供（見 spec.md「ReaderScreen 內部行為異動」），本分頁點擊「手動
    // 選區」本身不直接呼叫 onChanged／改變 pdfCropMode。
    expect(notified, isNull);
  });
```

`_pumpSheet` helper（檔案第 261-274 行）目前不接受 `onRequestManualCrop` 參數，本 task 的 Step 3 會同步更新它——先照上面的方式呼叫（多帶一個具名參數），本步驟先讓測試檔案編譯失敗是預期的（下一步才修正 helper 與 widget 本身）。

- [ ] **Step 2：執行測試，確認 FAIL**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（`PdfSettingsSheet` 建構子沒有 `onRequestManualCrop` 具名參數；`_pumpSheet` helper 也還沒有對應參數，編譯錯誤）。

- [ ] **Step 3：修改 `_pumpSheet` helper（測試檔案第 261-274 行）**

```dart
Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        onRequestManualCrop: onRequestManualCrop,
      ),
    ),
  ));
}

void _noopVoid() {}
```

（`_noopVoid` 頂層函式加在檔案最後，`main()` 之後。）

- [ ] **Step 4：修改 `app/lib/screens/pdf_settings_sheet.dart`——新增建構參數並更新頂端文件註解**

把第 7-30 行的類別文件註解與建構子改為（更新已過時的「Issue 2/Issue 3-6」措辭——本 issue 是 Issue 3-6 範圍中最後一個觸碰此檔案的，三個分頁至此皆已完整實作，不再是佔位狀態）：

```dart
/// PDF 專屬版面設定 Bottom Sheet（FR-11），三分頁結構：顯示／濾鏡／裁切，
/// 見 docs/epics/epic-4-pdf-enhance/design.md 決策 #10（不與 EPUB 用的
/// `ReaderSettingsSheet` 共用元件）。三分頁（Fit 模式、濾鏡、裁切模式）
/// 皆已完整實作。
///
/// 純展示、無 I/O：每次選擇立即透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]（`_notifyChanged` 只需重建目前已追蹤的本地狀態欄位
/// ＋ 原樣帶回 [BookReaderPrefs.pdfCropRect]——因為同一本書不會同時是
/// EPUB 又是 PDF，未追蹤的 EPUB 欄位維持 null 不影響實際使用情境）。
/// 「手動選區」選項點擊時透過 [onRequestManualCrop] 通知呼叫端
/// （`PdfSettingsSheet` 本身不直接操作 `PdfReaderView`，維持既有單向資料
/// 流，見 spec.md「模組」段落）；持久化由呼叫端（`ReaderScreen`）負責。
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final VoidCallback onRequestManualCrop;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onRequestManualCrop,
  });
```

- [ ] **Step 5：修改 `_buildCropTab`——啟用手動選區按鈕**

把第 194-236 行的 `_buildCropTab` 方法改為：

```dart
  Widget _buildCropTab(BuildContext context) {
    const options = [
      (PdfCropMode.none, 'none', Icons.crop_free, '不裁切'),
      (PdfCropMode.autoDetect, 'auto', Icons.auto_fix_high, '智慧自動'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('裁切模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              ...options.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _cropMode == mode;
                return IconButton(
                  key: Key('pdf_settings_crop_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _cropMode = mode;
                    _notifyChanged();
                  }),
                );
              }),
              // 手動選區：點擊只通知呼叫端進入裁切互動模式（不直接改變
              // _cropMode／呼叫 _notifyChanged），實際的 pdfCropMode=manual
              // 與 pdfCropRect 由 ReaderScreen 在使用者完成框選確認後才
              // 一併寫入（見 spec.md「ReaderScreen 內部行為異動」）。
              IconButton(
                key: const Key('pdf_settings_crop_mode_manual'),
                icon: const Icon(Icons.crop),
                tooltip: '手動選區',
                onPressed: widget.onRequestManualCrop,
              ),
            ],
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 6：執行測試，確認 PASS**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: 全數 PASS。

- [ ] **Step 7：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-4): PdfSettingsSheet 啟用裁切分頁手動選區選項"
```

---

### Task 4：`ReaderScreen`——裁切互動模式狀態機串接

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `PdfReaderView.cropEditModeActive`／`onCropRectSelected`；Task 3 的 `PdfSettingsSheet.onRequestManualCrop`；既有 `BookReaderPrefs.copyWith()`（Issue 5 Task 1 已建立）。
- Produces：`_ReaderScreenState._cropEditModeActive`（私有狀態，驅動 `PdfReaderView.cropEditModeActive`）。

- [ ] **Step 1：撰寫失敗測試——手動選區請求與框選確認的狀態機**

在 `app/test/screens/reader_screen_test.dart` 檔案最後一個 `testWidgets`（第 247-264 行）之後、`}`（`main()` 結尾）之前新增：

```dart
  testWidgets(
      '點擊手動選區後，關閉 PdfSettingsSheet 並將 cropEditModeActive 傳入 PdfReaderView',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端 onPageRendered，讓「⚙️版面」按鈕轉為可點擊狀態（純
    // flutter test 環境下 AndroidView 不會真正觸發原生回呼，比照本檔案
    // 既有測試對「尚未收到 onPageRendered」情境的說明，見第 69-89 行）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfSettingsSheet), findsNothing);
    expect(
      tester
          .widget<PdfReaderView>(find.byType(PdfReaderView))
          .cropEditModeActive,
      isTrue,
    );
  });

  testWidgets(
      '收到 onCropRectSelected 後，退出裁切模式、寫入 pdfCropMode=manual 並持久化、重新開啟 PdfSettingsSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    const selectedRect =
        PdfCropRect(left: 0.1, top: 0.15, right: 0.9, bottom: 0.85);
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onCropRectSelected!(selectedRect);
    await tester.pumpAndSettle();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.cropEditModeActive, isFalse);
    expect(pdfView.cropMode, PdfCropMode.manual);
    expect(pdfView.cropRect, selectedRect);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '確認框選後應重新開啟 PdfSettingsSheet 顯示套用結果（見 spec.md）');

    final saved = await prefsRepository.load('b1');
    expect(saved.pdfCropMode, PdfCropMode.manual);
    expect(saved.pdfCropRect, selectedRect);
  });
```

新增檔案頂端的 import（第 1-16 行區塊）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_book_reader_prefs_repository.dart';
```

（新增了 `pdf_crop_mode.dart`／`pdf_crop_rect.dart`／`pdf_settings_sheet.dart` 三個 import，其餘維持原樣。）

- [ ] **Step 2：執行測試，確認 FAIL**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`PdfReaderView` 沒有 `cropEditModeActive`/`onCropRectSelected` 會先被 Task 1 補上，此處會是 `PdfSettingsSheet` 缺少 `onRequestManualCrop` 導致 `ReaderScreen` 內部呼叫處編譯失敗，或手動選區按鈕仍是停用狀態導致 `tester.tap` 找不到可互動的按鈕／`_cropEditModeActive` 狀態未定義的執行期錯誤）。

- [ ] **Step 3：修改 `app/lib/screens/reader_screen.dart`——新增 import 與狀態欄位**

把第 4-16 行的 import 區塊改為（新增 `pdf_crop_mode.dart`）：

```dart
import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/global_reader_defaults.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import 'pdf_settings_sheet.dart';
import 'reader_settings_sheet.dart';
```

把第 69 行（`bool _isFixedLayout = false;` 所在的狀態欄位群）新增一行，改為：

```dart
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;
  // 手動裁切互動模式是否進行中（決策 #14），驅動 PdfReaderView 的宣告式
  // cropEditModeActive prop；只有 PDF 分支會用到，EPUB 分支永遠是 false。
  bool _cropEditModeActive = false;
```

- [ ] **Step 4：修改 `_openPdfSettings()`——傳入 `onRequestManualCrop`**

把第 195-205 行的 `_openPdfSettings()` 改為：

```dart
  void _openPdfSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        onRequestManualCrop: _handleRequestManualCrop,
      ),
    );
  }
```

- [ ] **Step 5：新增 `_handleRequestManualCrop()`／`_handleCropRectSelected()`**

在既有 `_handleCropRectComputed`（第 169-178 行）之後、`_openLayoutSettings()`（第 180 行）之前插入：

```dart
  /// 手動選區裁切請求（決策 #14）：關閉目前開啟的 PdfSettingsSheet、切換
  /// 至裁切互動模式（宣告式，觸發 PdfReaderView.didUpdateWidget 送出
  /// enterCropEditMode）。context 用的是 State 自身的 context，Navigator
  /// 會沿同一個 Navigator 找到目前最上層的路由（即 showModalBottomSheet
  /// 推入的 PdfSettingsSheet）並將其關閉。
  void _handleRequestManualCrop() {
    Navigator.of(context).pop();
    setState(() => _cropEditModeActive = true);
  }

  /// 使用者在原生裁切互動模式完成框選確認時觸發（PdfReaderView 原生
  /// onCropRectSelected 回呼）：退出裁切互動模式（宣告式，觸發
  /// PdfReaderView.didUpdateWidget 送出 exitCropEditMode）、把結果寫入
  /// BookReaderPrefs（pdfCropMode 固定為 manual、pdfCropRect 為框選
  /// 結果，透過 copyWith 只更新這兩個欄位，其餘欄位保留原值，比照
  /// _handleCropRectComputed 的既有模式），持久化後重新開啟
  /// PdfSettingsSheet 讓使用者看到套用後的結果（見 spec.md「ReaderScreen
  /// 內部行為異動」）。
  void _handleCropRectSelected(PdfCropRect rect) {
    final updated = _prefs.copyWith(
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: rect,
    );
    setState(() {
      _cropEditModeActive = false;
      _prefs = updated;
    });
    widget.prefsRepository.save(widget.bookId, updated);
    _openPdfSettings();
  }
```

- [ ] **Step 6：修改 `_buildNativeView`——PDF 分支傳入 `cropEditModeActive`／`onCropRectSelected`**

把第 351-363 行的 PDF 分支改為：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: _resolvedPdfFitMode,
          contrast: _prefs.pdfContrast,
          brightness: _prefs.pdfBrightness,
          boldStrength: _prefs.pdfBoldStrength,
          cropMode: _prefs.pdfCropMode,
          cropRect: _prefs.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
          cropEditModeActive: _cropEditModeActive,
          onCropRectSelected: _handleCropRectSelected,
        );
```

- [ ] **Step 7：執行測試，確認 PASS**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS。

- [ ] **Step 8：執行完整測試套件與 `flutter analyze`**

Run: `cd app && flutter test`
Expected: 全數 PASS，無回歸。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-4): ReaderScreen 串接手動裁切互動模式狀態機"
```

---

### Task 5：真機驗證（觸控拖拉、翻頁暫停、確認寫入、螢幕截圖視覺比對）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`
- Modify: `docs/epics/epic-4-pdf-enhance/issues.md`（標記 Issue 6 完成狀態）

**Interfaces:**
- Consumes：Task 1-4 的完整實作（`PdfReaderView.cropEditModeActive`/`onCropRectSelected`、原生 `CropOverlayView`、`PdfSettingsSheet` 手動選區按鈕、`ReaderScreen` 狀態機）。
- Produces：無（本任務是驗證與文件收尾）。

裝置：使用此環境目前唯一連接的真實裝置（`flutter devices` 查詢 device id），比照 Issue 3-5 既有慣例。

- [ ] **Step 1：撰寫真機驗證測試**

先確認檔案頂端 import 是否已有 `import 'package:elinkbook/reader/pdf_crop_mode.dart';`——若沒有就在既有 `import 'package:elinkbook/reader/pdf_fit_mode.dart';` 之後新增一行。

在 `app/integration_test/reader_screen_test.dart` 檔案最後一個 `testWidgets`（第 922-983 行，"智慧自動裁切計算後關閉重開該書...") 之後、`}`（`main()` 結尾）之前新增。**本檔案既有的 `_stageAssetAsFile`／`_pumpUntil`／`_layoutSettingsButtonReady`／`_book` 輔助函式與 `prefsRepository`／`libraryRepository`（`setUp` 建立的共用變數，見第 81-93 行）直接沿用，不要重新宣告**，寫法完全比照本檔案第 883-983 行既有的裁切相關測試：

```dart
  testWidgets('PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_pause.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_pause';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '點擊手動選區後應關閉 PdfSettingsSheet、進入裁切互動模式');

    // 進入裁切互動模式期間，對 PdfReaderView 區域做水平拖曳手勢（正常
    // 閱讀模式下會觸發翻頁），確認不會出現錯誤畫面，也不會意外重新開啟
    // PdfSettingsSheet（那只在確認框選、onCropRectSelected 觸發後才會
    // 發生）——用來間接驗證翻頁手勢在裁切互動模式下確實被暫停，沒有讓
    // 原生端 nextPage()/previousPage() 觸發非預期的重新渲染或狀態改變。
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '拖曳手勢不應觸發任何確認流程，裁切互動模式應維持進行中');
  });

  testWidgets('PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_confirm.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_confirm';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    // 拖拉右下角控制點：從 PdfReaderView 區域內、預設初始裁切框（四周
    // 10% 邊距，見 PdfReaderView.kt 的 enterCropEditMode()）的右下角附近
    // 往左上方拖曳一段距離，縮小裁切框範圍。實際手勢座標依真機畫面尺寸
    // 計算——若 tester.drag()/tester.timedDrag() 對疊加於 AndroidView 之
    // 上的原生 CropOverlayView 無法正確傳遞觸控事件，改用
    // `adb shell input touchscreen swipe`（座標依 `adb shell wm size`
    // 查得的真機解析度換算），並在報告中誠實記錄實際採用的方式。
    final pdfViewBox = tester.getRect(find.byType(PdfReaderView));
    final approxBottomRightHandle = Offset(
      pdfViewBox.left + pdfViewBox.width * 0.9,
      pdfViewBox.top + pdfViewBox.height * 0.9,
    );
    final dragGesture = await tester.startGesture(approxBottomRightHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.moveBy(const Offset(-80, -80));
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.up();
    await tester.pump(const Duration(seconds: 1));

    // 點擊確認按鈕：CropOverlayView 把它畫在固定右下角（見
    // CONFIRM_BUTTON_MARGIN_DP/CONFIRM_BUTTON_RADIUS_DP 常數），螢幕座標
    // 需依裝置 density 換算，實測時直接對 PdfReaderView 區域右下角附近
    // 嘗試點擊即可命中（確認按鈕的視覺半徑遠大於一般手指誤差）。
    final approxConfirmButton = Offset(
      pdfViewBox.right - 40,
      pdfViewBox.bottom - 40,
    );
    await tester.tapAt(approxConfirmButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '確認框選後應重新開啟 PdfSettingsSheet 顯示套用結果');

    final saved = await prefsRepository.load(bookId);
    expect(saved.pdfCropMode, PdfCropMode.manual);
    expect(saved.pdfCropRect, isNotNull);
  });
```

**若座標計算方式在真機上實測不可靠**（例如確認按鈕沒有命中、拖曳沒有真的改變裁切框範圍）：實作者可調整上方 `approxBottomRightHandle`／`approxConfirmButton` 的計算方式（先用 `adb -s <device-id> exec-out screencap -p` 截圖搭配 `Read` 工具目視確認裁切框/確認按鈕實際畫面位置，反推正確座標），或改用 `adb shell input touchscreen swipe`／`adb shell input tap`（透過 Bash 工具直接下指令）。**必須在報告中誠實記錄實際採用的方式、遇到的困難與座標計算邏輯**，不得為了讓測試通過而弱化斷言內容（例如把「驗證確實套用新裁切結果」弱化成「沒有 crash」）。

**`sample.pdf` 素材限制**：Issue 5 Task 4 已確認 `test/fixtures/sample.pdf` 是完全空白頁面，無法用於「裁切後內容明顯放大」這類視覺比對（但不影響上方兩個測試的功能性斷言——拖拉/確認/持久化寫入是否正確與頁面內容無關）。Step 3 的螢幕截圖視覺比對若需要看出裁切前後的實際差異，比照 Issue 5 Task 4 的作法，另行產生一份僅供本次驗證用、不納入版本控制的 PDF 素材（例如四周留白邊界＋置中內容色塊），驗證後刪除。

- [ ] **Step 2：真機執行**

Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全數 PASS（既有測試 + 本 task 新增的 2 個）。若拖拉手勢座標計算需要調整才能穩定通過，反覆調整座標邏輯直到測試穩定，並記錄最終採用的方式。

- [ ] **Step 3：螢幕截圖視覺比對（必要步驟，見 Global Constraints）**

用 `adb -s <device-id> exec-out screencap -p > <path>.png` 在以下時機各拍一張截圖，並實際用 `Read` 工具檢視每一張、在報告中描述看到的畫面內容：

1. 點擊「手動選區」、進入裁切互動模式當下（應可見：暗色遮罩、白色邊框裁切框、四個白色圓形控制點、右下角綠色打勾確認按鈕，背景是完整未裁切的頁面）。
2. 拖拉一個控制點、縮小裁切框範圍之後、點擊確認之前（應可見：裁切框範圍變小，控制點跟著移動到新位置）。
3. 點擊確認按鈕之後（應可見：`PdfSettingsSheet` 重新開啟；若能先關閉 Sheet 再截一張，應可見畫面已套用新裁切範圍——內容明顯放大填滿，裁切框/確認按鈕/暗色遮罩皆已消失）。

若因裝置畫面過場動畫、截圖時機掌握困難等原因無法取得完全乾淨的截圖（比照 Issue 5 Task 4 曾出現的情況），可搭配原生端暫時性診斷 log（驗證後移除、不入版控）交叉佐證，並在報告中誠實記錄實際遇到的困難，不得宣稱已完成未實際完成的視覺確認。

- [ ] **Step 4：完整測試套件與靜態分析**

Run: `cd app && flutter test`
Expected: 全數 PASS，無回歸。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5：更新 `docs/epics/epic-4-pdf-enhance/issues.md`**

把 Issue 6 的標題與 `**Status:**` 段落改為完成狀態，比照 Issue 3-5 既有的完成說明風格（涵蓋：已完成範圍、已知限制如裝置矩陣、真機測試通過數量、螢幕截圖視覺比對的具體發現、任何驗證過程中的曲折或殘留風險，誠實記錄，不得省略任何已知的限制或風險）。

- [ ] **Step 6：Commit**

```bash
git add app/integration_test/reader_screen_test.dart docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "test(epic-4): Issue 6 真機驗證（手動裁切互動、翻頁暫停、螢幕截圖視覺比對）並標記完成"
```





