# Epic 4 Issue 3 — 影像濾鏡：對比度／亮度 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在 `PdfSettingsSheet` 的「濾鏡」分頁調整對比度與亮度，即時反映在 PDF 頁面上並持久化，改善淡色掃描件的可讀性。

**Architecture:** 沿用 Issue 2 已建立的 `initialPreferences`/`setPdfPreferences` method channel 契約，新增 `contrast`／`brightness` 兩個欄位；原生端在既有 `applyFitMode()`（決定縮放）之後，新增 `applyFilters()`（決定色彩），透過 `ImageView.colorFilter = ColorMatrixColorFilter(...)` 套用，與 `scaleType`/`imageMatrix` 完全獨立的顯示層機制，不會互相干擾。

**Tech Stack:** Flutter/Dart（`MethodChannel`）、Kotlin（`android.graphics.ColorMatrix`/`ColorMatrixColorFilter`）。

## Global Constraints

- 所有新增的程式碼註解與文件皆須使用正體中文（zh-TW），不得使用簡體中文。
- `flutter analyze` 全程必須保持乾淨（"No issues found!"）。
- `contrast`／`brightness` 為單書持久化、無全域預設層（design.md 決策 #2），範圍 -100..100，`null`＝0（無調整），已於 Issue 1 定義在 `BookReaderPrefs.pdfContrast`／`pdfBrightness`（`app/lib/reader/book_reader_prefs.dart`）與 `book_reader_prefs` 表的 `pdf_contrast`／`pdf_brightness` 欄位（皆已存在，不需要新增資料層）。
- 濾鏡調整滑桿的互動模式（design.md 決策 #11「即時預覽，鬆手後才寫入持久化」）**在本計劃中依實際程式碼慣例解讀為**：拖動滑桿的 `onChanged` 逐格觸發、每次都呼叫 `widget.onChanged`（沒有 `onChangeEnd` 防抖），因為這正是既有 `ReaderSettingsSheet._buildSliderRow`（`app/lib/screens/reader_settings_sheet.dart`）字型大小/行高滑桿的實際行為——design.md 的文字略為超前於程式碼實況，本計劃選擇「比照既有程式碼慣例」而非重新引入一個本專案沒有先例的防抖機制。
- 原生端渲染管線順序（`spec.md`「原生 method channel 契約異動」）：裁切 → fit 模式縮放 → 濾鏡，濾鏡永遠是最後一步，本 issue 尚未實作裁切（Issue 5/6），故目前管線為「fit 模式縮放 → 濾鏡」。
- **重要教訓（Issue 2 收尾時發現）**：真機 `integration_test` 若只在無人值守背景執行，只能驗證「無 crash／無 onError」，無法驗證「畫面看起來對不對」。本 issue 的 Task 3 明確要求透過 `adb exec-out screencap` 截圖並用 Read 工具實際檢視畫面內容，不能只憑測試斷言通過就宣稱視覺驗證完成。

---

## Task 1: `PdfReaderView`（Dart＋原生）——contrast／brightness 契約與 ColorMatrixColorFilter

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: 無新型別依賴（`contrast`／`brightness` 皆為 `double?`）
- Produces: `PdfReaderView` 新增 `final double? contrast; final double? brightness;` 建構參數——Task 2（`PdfSettingsSheet`）會建構帶有這兩個值的 `BookReaderPrefs`，Task 3（`ReaderScreen`，已於 Issue 2 完成，本 issue不需修改）已經是格式無關地把 `_prefs.pdfContrast`/`_prefs.pdfBrightness` 傳給 `PdfReaderView`——**等等，需要確認**：`ReaderScreen._buildNativeView` 的 `BookFormat.pdf` 分支目前只傳了 `fitMode: _resolvedPdfFitMode`，還沒有傳 `contrast`/`brightness`，本 task 需要一併修改 `reader_screen.dart`（見 Step 5）。

- [ ] **Step 1: 為 Dart 端 contrast／brightness 契約寫失敗測試**

編輯 `app/test/reader/pdf_reader_view_test.dart`，在既有 `void main() {` 之後、第一個 `testWidgets` 之前**不需插入任何東西**；在檔案最後（最後一個 `testWidgets` 結尾的 `});` 之後、`}` 之前）新增以下 2 個測試：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 contrast／brightness',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        contrast: 20.0,
        brightness: -15.0,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'contrast': 20.0,
      'brightness': -15.0,
    });
  });

  testWidgets('contrast／brightness 變動時，didUpdateWidget 呼叫 setPdfPreferences',
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
        contrast: 10.0,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        contrast: 10.0,
        brightness: 25.0, // 新增一個原本是 null 的欄位
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'contrast': 10.0,
      'brightness': 25.0,
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: FAIL（`PdfReaderView` 建構子沒有 `contrast`/`brightness` 具名參數，編譯錯誤）

- [ ] **Step 3: 擴充 Dart 端 `PdfReaderView`**

編輯 `app/lib/reader/pdf_reader_view.dart`。

把建構參數清單（第 19-37 行）改為：

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
  });
```

把 `didUpdateWidget`（第 56-62 行）改為：

```dart
  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
  }
```

把 `_buildPreferencesMap`（第 64-70 行）改為：

```dart
  /// 把目前所有非 null 的偏好參數組成一個 map，`null` 值的欄位完全不出現在
  /// map 中，比照 EpubReaderView 的既有模式。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    if (widget.contrast != null) map['contrast'] = widget.contrast;
    if (widget.brightness != null) map['brightness'] = widget.brightness;
    return map;
  }
```

- [ ] **Step 4: 執行測試確認 Dart 端測試通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（6 個測試全過：Issue 2 既有 4 個＋本 issue 新增 2 個）

- [ ] **Step 5: 讓 `ReaderScreen` 把 contrast／brightness 傳給 `PdfReaderView`**

編輯 `app/lib/screens/reader_screen.dart`，找到 `_buildNativeView` 的 `BookFormat.pdf` 分支：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: _resolvedPdfFitMode,
        );
```

改為：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: _resolvedPdfFitMode,
          contrast: _prefs.pdfContrast,
          brightness: _prefs.pdfBrightness,
        );
```

（`contrast`／`brightness` 是單書持久化、無雙層解析，見 Global Constraints，直接讀 `_prefs` 即可，不需要像 `_resolvedPdfFitMode` 那樣額外定義 getter——`pdfContrast`/`pdfBrightness` 本身已經是 `double?`，`null` 語意由原生端 `applyFilters()` 自行處理為「無調整」，不需要 Dart 端先解出預設值 0.0）

- [ ] **Step 6: 執行 `reader_screen_test.dart` 確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（既有測試不迴歸；這些測試不檢查 `contrast`/`brightness`，新增的傳遞邏輯屬於未被既有測試覆蓋的行為，這是預期的——Task 3 的真機測試會涵蓋端到端行為，此處只需確認不迴歸）

- [ ] **Step 7: 擴充原生端 `PdfReaderView.kt`**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`。

覆寫前先執行 `git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 確認工作目錄乾淨。

在 `fitMode` 欄位宣告（第 43-45 行）之後新增：

```kotlin
    // Dart contrast／brightness 值，-100..100，預設 0（無調整），與
    // BookReaderPrefs.pdfContrast/pdfBrightness 為 null 時的語意一致。
    private var contrast: Float = 0f
    private var brightness: Float = 0f
```

把 `setPdfPreferences`（第 80-90 行）改為：

```kotlin
    /**
     * 合併 [preferences] 到目前生效狀態並套用（fitMode／contrast／
     * brightness，之後 Issue 4-6 會擴充加粗/裁切欄位）。書本尚未成功開啟
     * （renderer 仍為 null）時仍安全執行——applyFitMode()／applyFilters()
     * 內部若沒有已渲染的 bitmap 會靜默不做事。
     */
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = it }
        (preferences["contrast"] as? Number)?.let { contrast = it.toFloat() }
        (preferences["brightness"] as? Number)?.let { brightness = it.toFloat() }
        applyFitMode()
        applyFilters()
    }
```

把 `openBook`（第 92-119 行）內套用 `initialPreferences` 的那一行：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
```

改為：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
```

把 `renderCurrentPage()`（第 121-151 行）內兩處 `applyFitMode()` 呼叫都改為緊接著呼叫 `applyFilters()`：

```kotlin
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            applyFitMode()
            applyFilters()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
```

在 `applyFitMode()` 方法（第 153-198 行）結尾的 `}` 之後新增：

```kotlin
    /**
     * 依 [contrast]／[brightness] 設定 imageView 的 colorFilter，與
     * applyFitMode() 的 scaleType／imageMatrix 是完全獨立的顯示層機制
     * （ColorMatrixColorFilter 作用於像素色彩，不影響座標變換），呼叫順序
     * 不影響結果，但依慣例排在 applyFitMode() 之後（見 spec.md「裁切 →
     * fit 模式縮放 → 濾鏡」的管線順序）。
     *
     * 標準對比度/亮度 ColorMatrix 公式：先以 128（灰階中點）為軸心縮放對比
     * 度，再疊加亮度位移，確保 contrast=0／brightness=0 時是單位矩陣（無
     * 視覺變化）。
     */
    private fun applyFilters() {
        val contrastFactor = (100f + contrast) / 100f // -100→0.0，0→1.0，100→2.0
        val brightnessOffset = brightness * 2.55f // -100..100 映射到約 -255..255 的像素位移範圍
        val translate = brightnessOffset + (255f - contrastFactor * 255f) / 2f
        val colorMatrix = android.graphics.ColorMatrix(
            floatArrayOf(
                contrastFactor, 0f, 0f, 0f, translate,
                0f, contrastFactor, 0f, 0f, translate,
                0f, 0f, contrastFactor, 0f, translate,
                0f, 0f, 0f, 1f, 0f,
            )
        )
        imageView.colorFilter = android.graphics.ColorMatrixColorFilter(colorMatrix)
    }
```

- [ ] **Step 8: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL（Kotlin 編譯通過；邏輯正確性留給 Task 3 的 `integration_test`）

- [ ] **Step 9: 重新執行 Dart 端全部測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS（全部通過）

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-4): PdfReaderView 新增 contrast/brightness 契約與 ColorMatrixColorFilter"
```

---

## Task 2: `PdfSettingsSheet` 濾鏡分頁——對比度／亮度滑桿

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Modify: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `PdfReaderView.contrast`／`brightness`（Task 1，透過 `BookReaderPrefs.pdfContrast`／`pdfBrightness` 間接消費，`PdfSettingsSheet` 本身不直接依賴 `PdfReaderView`）
- Produces: 無新公開介面——`_notifyChanged()` 擴充後送出的 `BookReaderPrefs` 多帶 `pdfContrast`/`pdfBrightness` 兩個欄位，`ReaderScreen`（已於 Issue 2 完成）的 `_handlePrefsChanged` 不需修改即可正確處理（見 Issue 2 spec 的既有邏輯，格式無關）

- [ ] **Step 1: 為濾鏡分頁的對比度／亮度滑桿寫失敗測試**

編輯 `app/test/screens/pdf_settings_sheet_test.dart`，在檔案最後（最後一個 `testWidgets` 的 `});` 之後、`}` 之前）新增：

```dart
  testWidgets('濾鏡分頁存在對比度／亮度滑桿，初始值反映 prefs', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 30, pdfBrightness: -20),
      (_) {},
    );

    // 切到濾鏡分頁
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      30,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_brightness_slider')))
          .value,
      -20,
    );
  });

  testWidgets('prefs.pdfContrast／pdfBrightness 為 null 時，滑桿顯示預設值 0',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_brightness_slider')))
          .value,
      0,
    );
  });

  testWidgets('拖動對比度滑桿後，onChanged 帶入新的 pdfContrast，其餘 PDF 欄位不變',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 0, pdfBrightness: 15),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.pdfBrightness, 15);
  });

  testWidgets('拖動亮度滑桿後，onChanged 帶入新的 pdfBrightness', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_brightness_decrement')));
    await tester.pump();

    expect(notified?.pdfBrightness, lessThan(0));
  });
```

在檔案開頭確認已有 `import 'package:flutter/material.dart';`（已存在，`Slider` 型別由此提供，不需新增 import）。

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（找不到 `Key('pdf_settings_tab_filters')` 底下的 `Slider`，因為目前濾鏡分頁只是 `_buildPlaceholderTab('濾鏡功能即將推出')`）

- [ ] **Step 3: 實作濾鏡分頁**

編輯 `app/lib/screens/pdf_settings_sheet.dart`。

在 `_PdfSettingsSheetState` 類別的欄位宣告（`late final TabController _tabController; late PdfFitMode _fitMode;`）之後新增：

```dart
  late double _contrast;
  late double _brightness;
```

在 `initState`（`_fitMode = widget.prefs.pdfFitMode ?? PdfFitMode.pageFit;` 那一行）之後新增：

```dart
    _contrast = widget.prefs.pdfContrast ?? 0;
    _brightness = widget.prefs.pdfBrightness ?? 0;
```

把 `_notifyChanged()` 改為：

```dart
  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      pdfFitMode: _fitMode,
      pdfContrast: _contrast,
      pdfBrightness: _brightness,
    ));
  }
```

把 `build()` 內的 `TabBarView` 的 `children` 陣列：

```dart
                children: [
                  _buildDisplayTab(context),
                  _buildPlaceholderTab('濾鏡功能即將推出'),
                  _buildPlaceholderTab('裁切功能即將推出'),
                ],
```

改為：

```dart
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildPlaceholderTab('裁切功能即將推出'),
                ],
```

在 `_buildDisplayTab` 方法結尾的 `}` 之後、`_buildPlaceholderTab` 方法之前，新增：

```dart
  Widget _buildFiltersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSliderRow(
            keyPrefix: 'pdf_settings_contrast',
            label: '對比度',
            value: _contrast,
            min: -100,
            max: 100,
            step: 5,
            onChanged: (v) => setState(() {
              _contrast = v;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'pdf_settings_brightness',
            label: '亮度',
            value: _brightness,
            min: -100,
            max: 100,
            step: 5,
            onChanged: (v) => setState(() {
              _brightness = v;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }

  /// 比照 `ReaderSettingsSheet._buildSliderRow` 的既有樣式（滑桿＋±微調
  /// 按鈕），本 widget 依 design.md 決策 #10 不與 `ReaderSettingsSheet`
  /// 共用元件，故獨立實作一份同樣式的 helper。
  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(clampedValue.round().toString())],
          ),
          Row(
            children: [
              IconButton(
                key: Key('${keyPrefix}_decrement'),
                icon: const Icon(Icons.remove),
                onPressed: clampedValue - step < min - 1e-9
                    ? null
                    : () => onChanged((clampedValue - step).clamp(min, max)),
              ),
              Expanded(
                child: Slider(
                  key: Key('${keyPrefix}_slider'),
                  value: clampedValue,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: (v) => onChanged(v.clamp(min, max)),
                ),
              ),
              IconButton(
                key: Key('${keyPrefix}_increment'),
                icon: const Icon(Icons.add),
                onPressed: clampedValue + step > max + 1e-9
                    ? null
                    : () => onChanged((clampedValue + step).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（9 個測試全過：Issue 2 既有 5 個＋本 issue 新增 4 個）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-4): PdfSettingsSheet 濾鏡分頁新增對比度/亮度滑桿"
```

---

## Task 3: 真機驗證（integration_test，含真正的人工視覺確認）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-2 的全部產出
- Produces: 無（驗證性質收尾任務）

**本任務的執行方式與 Issue 2 Task 4 的關鍵差異**：Issue 2 收尾時發現「無人值守背景真機測試」只能驗證無 crash，不能驗證畫面視覺結果，導致完成說明一度需要事後補正兩輪才誠實反映驗證缺口。本任務要求執行者**實際使用 `adb exec-out screencap` 截圖，並用 Read 工具親自檢視截圖內容**，在報告中具體描述看到了什麼（而非只憑測試斷言通過就宣稱視覺驗證完成）。

- [ ] **Step 1: 新增真機驗證測試**

編輯 `app/integration_test/reader_screen_test.dart`。

在檔案最後（`}` 之前，緊接在既有最後一個 `testWidgets` 之後）新增：

```dart
  testWidgets('PDF 調整對比度／亮度後畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_filters.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_filters';
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    for (final keySuffix in ['contrast_increment', 'brightness_decrement']) {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(Key('pdf_settings_$keySuffix')));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('reader_error_text')), findsNothing,
          reason: '調整 $keySuffix 後畫面應持續渲染成功，不應觸發 onError');
    }
  });

  testWidgets('調整 PDF 對比度／亮度後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_filters_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_filters_persist';
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await prefsRepository.load(bookId);
    expect(saved.pdfContrast, 5); // 預設 0，點一次 +5

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

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
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.contrast, 5);
  });
```

- [ ] **Step 2: 於真實裝置/模擬器上執行自動化測試**

Run: `cd app && flutter devices`（確認至少一台可用裝置）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全部測試通過（含既有 EPUB/Fit 模式相關測試不迴歸）

- [ ] **Step 3: 實際截圖並親自檢視畫面（不可省略，這是本任務與 Issue 2 Task 4 的關鍵差異）**

在裝置上安裝一份正常（非 instrumented）debug APK 並手動開啟一本 PDF（或沿用 Issue 2 Task 4 已驗證可行的裝置操作方式），依序執行：

```bash
# 1. 截一張「未調整濾鏡」的基準畫面
adb -s <device-id> exec-out screencap -p > /tmp/pdf_filter_baseline.png

# 2. 透過裝置畫面手動（或用 adb shell input tap 依實際 UI 座標）把對比度
#    拉到接近 -100（大幅降低），亮度也大幅調整，再截圖
adb -s <device-id> exec-out screencap -p > /tmp/pdf_filter_adjusted.png
```

**用 Read 工具實際開啟 `/tmp/pdf_filter_baseline.png` 與 `/tmp/pdf_filter_adjusted.png` 兩張截圖並親自檢視**，在報告中具體描述兩張截圖的視覺差異（例如「調整後的畫面明顯偏灰／偏亮／偏暗，與基準畫面有可辨識的對比度變化」），而不是只說「已截圖」。若兩張截圖看起來沒有差異（濾鏡沒有實際生效），這是真實發現，不要略過或美化，直接在報告中如實記錄並標記 DONE_WITH_CONCERNS。

若因裝置操作環境限制（例如無法手動操作裝置畫面、找不到穩定的座標點擊 UI）導致無法完成這一步，**必須**在報告中明確說明具體卡在哪裡，比照 Issue 2 Task 4 的教訓——不能讓「已完成」的描述超出實際驗證範圍。

- [ ] **Step 4: 更新 `docs/epics/epic-4-pdf-enhance/issues.md` 的 Issue 3 狀態**

編輯 `docs/epics/epic-4-pdf-enhance/issues.md`，找到（測試名稱字串 `## Issue 3：影像濾鏡——對比度／亮度` 定位）：

```markdown
## Issue 3：影像濾鏡——對比度／亮度

**Status:** ready-for-agent
```

改為（**如實反映 Step 3 實際完成到什麼程度**，不要無論 Step 3 結果如何都寫「已完成並經視覺驗證」——若 Step 3 因故無法完成截圖比對，這裡要照實寫「自動化測試通過，但截圖視覺比對因故未完成」）：

```markdown
## Issue 3：影像濾鏡——對比度／亮度（已完成）

**Status:** ✅ 已完成。`PdfReaderView`（Dart＋原生）新增 `contrast`／`brightness` 契約與 `ColorMatrixColorFilter` 套用、`PdfSettingsSheet` 濾鏡分頁新增對比度/亮度滑桿皆已完成。[此處由執行者依 Step 3 實際結果填寫：真機自動化測試 N/N 通過；截圖視覺比對結果——具體描述基準與調整後畫面的差異，或說明未完成的原因]。完整計劃見 `plans/plan-issue-3.md`。
```

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/reader_screen_test.dart docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "test(epic-4): 新增 Issue 3 真機驗證測試（含截圖視覺比對）並標記完成"
```
