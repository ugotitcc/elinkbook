# Epic 4 Issue 4 — 影像濾鏡：加粗（型態學膨脹） 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在 `PdfSettingsSheet` 的「濾鏡」分頁調整加粗強度，透過型態學膨脹（dilate）處理淡色掃描件的文字筆畫，改善可讀性。

**Architecture:** 與 Issue 3 的 `contrast`/`brightness`（非破壞性 `ColorMatrixColorFilter`，只影響顯示層）不同，加粗需要**修改 Bitmap 實際像素**（型態學膨脹是空間鄰域運算，`ColorFilter` 做不到）。這代表加粗必須整合進 `renderCurrentPage()` 的 bitmap 產生流程本身，而非像 `applyFitMode()`/`applyFilters()` 那樣的輕量顯示層調整——`boldStrength` 變動時，`setPdfPreferences()` 必須觸發完整的 `renderCurrentPage()` 重新渲染（含重新解碼 PDF 頁面＋重新膨脹），而不能只做局部調整。

**Tech Stack:** Flutter/Dart（`MethodChannel`）、Kotlin（手動像素陣列運算，`Bitmap.getPixels()`/`setPixels()`）。

## Global Constraints

- 所有新增的程式碼註解與文件皆須使用正體中文（zh-TW），不得使用簡體中文。
- `flutter analyze` 全程必須保持乾淨（"No issues found!"）。
- `boldStrength` 為單書持久化、無全域預設層，範圍 0..1，`null`＝0（無加粗），已於 Issue 1 定義在 `BookReaderPrefs.pdfBoldStrength`（`app/lib/reader/book_reader_prefs.dart`）與 `book_reader_prefs` 表的 `pdf_bold_strength` 欄位（皆已存在，不需要新增資料層）。
- **演算法決策（本計劃裁量，issues.md 授權「實作者需先依效能實測決定」）**：API 24-30 沒有 `RenderEffect`（需 API 31），而 API 31+ 雖然有 `RenderEffect` 但**沒有現成的「膨脹」factory method**（`createBlurEffect`/`createColorFilterEffect`/`createOffsetEffect`/`createShaderEffect`/`createChainEffect` 皆非膨脹運算），要組出真正的膨脹效果仍需自行實作邏輯（例如用 AGSL RuntimeShader，但那需要 API 33+，落在本專案 minSdk=24 的支援範圍內又是另一層版本分裂）。本計劃選擇**全 API 統一用同一套手動像素陣列運算**（`Bitmap.getPixels()`/`setPixels()` 對縮小版工作副本做「取鄰域最小亮度值」的膨脹），不分 API 24-30／31+ 兩條路徑——理由：(1) 統一實作大幅降低維護與測試負擔（本專案目前只有一台真機可測，見 Task 3 已知限制）；(2) `RenderEffect` 就算能用也需要額外組合邏輯才能達成膨脹效果，不是「現成可用」的捷徑；(3) 決策 #13（NFR-1 不涵蓋濾鏡效能）已授權效能寬鬆處理，手動像素運算的效能代價可被接受。
- **效能策略**：直接對全解析度 bitmap 做二維鄰域掃描成本過高，先縮小到工作尺寸（原尺寸 25%）做膨脹運算，再放大回原尺寸——犧牲邊緣精細度換取可接受效能，符合決策 #13「允許翻頁後短暫延遲完成處理」的寬鬆門檻。
- **OOM 回退路徑不套用加粗**：`renderCurrentPage()` 的 `OutOfMemoryError` catch 區塊本身就代表裝置記憶體已經吃緊，加粗運算需要額外配置工作用 bitmap（縮小版＋膨脹結果），在 OOM 回退路徑再疊加這個配置需求風險過高，故此路徑刻意跳過加粗、只做既有的無縮放回退渲染，維持「不崩潰」優先於「效果完整」的既有原則。
- **`boldStrength` 變動的重繪成本**：與 `contrast`/`brightness`（改變不需要重新解碼 PDF、只需重設 `ImageView` 屬性）不同，`boldStrength` 變動必須呼叫完整的 `renderCurrentPage()`（重新解碼頁面＋重新膨脹＋重新套用 fit 模式與濾鏡）。issues.md 明確要求「互動模式同 Issue 3（即時預覽、鬆手持久化）」，即拖動滑桿的 `onChanged` 逐格觸發、無防抖——本計劃遵循此要求，但這代表拖動加粗滑桿時每一格都會觸發一次完整重新渲染，效能明顯重於 Issue 3 的濾鏡滑桿；已符合決策 #13 的寬鬆門檻但需要在 Task 3 真機測試時留意是否有感卡頓。
- **已知裝置限制**：本專案目前唯一可用的真機是 `9491G`（Android 15，API 35，屬於 API 31+ 那一側）。issues.md 驗收標準要求「至少涵蓋一台 API 24-30 裝置與一台 API 31+ 裝置」，但由於統一實作不分 API 版本分支（見上方演算法決策），理論上不需要分別驗證兩個 API 層級的「不同程式碼路徑」，只需在僅有的 API 35 裝置上驗證這一套統一邏輯即可；Task 3 會明確記錄「未涵蓋 API 24-30 實機測試」這個限制，不假裝已完成分層驗證。

---

## Task 1: `PdfReaderView`（Dart＋原生）——boldStrength 契約與型態學膨脹渲染整合

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: 無新型別依賴（`boldStrength` 為 `double?`）
- Produces: `PdfReaderView` 新增 `final double? boldStrength;` 建構參數——Task 2（`PdfSettingsSheet`）會建構帶有此值的 `BookReaderPrefs`。

- [ ] **Step 1: 為 Dart 端 boldStrength 契約寫失敗測試**

編輯 `app/test/reader/pdf_reader_view_test.dart`，在檔案最後（最後一個 `testWidgets` 結尾的 `});` 之後、`}` 之前）新增：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 boldStrength',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        boldStrength: 0.5,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {'boldStrength': 0.5});
  });

  testWidgets('boldStrength 變動時，didUpdateWidget 呼叫 setPdfPreferences',
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
        boldStrength: 0.2,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        boldStrength: 0.8, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {'boldStrength': 0.8});
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: FAIL（`PdfReaderView` 建構子沒有 `boldStrength` 具名參數，編譯錯誤）

- [ ] **Step 3: 擴充 Dart 端 `PdfReaderView`**

編輯 `app/lib/reader/pdf_reader_view.dart`。

把建構參數清單加入 `boldStrength`：

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
  });
```

把 `didUpdateWidget` 的比較條件加入 `boldStrength`：

```dart
  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness ||
        widget.boldStrength != oldWidget.boldStrength) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
  }
```

把 `_buildPreferencesMap` 加入 `boldStrength`：

```dart
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    if (widget.contrast != null) map['contrast'] = widget.contrast;
    if (widget.brightness != null) map['brightness'] = widget.brightness;
    if (widget.boldStrength != null) map['boldStrength'] = widget.boldStrength;
    return map;
  }
```

- [ ] **Step 4: 執行測試確認 Dart 端測試通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（8 個測試全過：Issue 2/3 既有 6 個＋本 issue 新增 2 個）

- [ ] **Step 5: 讓 `ReaderScreen` 把 boldStrength 傳給 `PdfReaderView`**

編輯 `app/lib/screens/reader_screen.dart`，找到 `_buildNativeView` 的 `BookFormat.pdf` 分支：

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
          boldStrength: _prefs.pdfBoldStrength,
        );
```

- [ ] **Step 6: 執行 `reader_screen_test.dart` 確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（既有測試不迴歸）

- [ ] **Step 7: 擴充原生端 `PdfReaderView.kt`**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`。

覆寫前先執行 `git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 確認工作目錄乾淨。

在 `contrast`／`brightness` 欄位宣告之後新增：

```kotlin
    // Dart boldStrength 值，0..1，預設 0（無加粗），與
    // BookReaderPrefs.pdfBoldStrength 為 null 時的語意一致。
    private var boldStrength: Float = 0f

    companion object {
        // 加粗（型態學膨脹）運算的效能策略常數，見 spec.md/design.md「已知
        // 風險」與本 issue 計劃的「效能策略」段落：對縮小版工作副本做膨脹，
        // 而非對全解析度 bitmap 直接運算。
        private const val BOLD_DOWNSCALE_FACTOR = 0.25f
        private const val BOLD_MAX_RADIUS = 3
    }
```

把 `setPdfPreferences` 改為（加粗變動時需要完整重新渲染，其餘欄位變動維持原本的輕量顯示層調整）：

```kotlin
    /**
     * 合併 [preferences] 到目前生效狀態並套用。fitMode／contrast／
     * brightness 屬於輕量顯示層調整（不需重新解碼 PDF），但
     * boldStrength 變動需要完整重新渲染（型態學膨脹是對 bitmap 像素本身
     * 的運算，不像 ColorMatrixColorFilter 是非破壞性的顯示層濾鏡）。
     */
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = it }
        (preferences["contrast"] as? Number)?.let { contrast = it.toFloat() }
        (preferences["brightness"] as? Number)?.let { brightness = it.toFloat() }
        val boldChanged = (preferences["boldStrength"] as? Number)?.let {
            val newValue = it.toFloat()
            val changed = newValue != boldStrength
            boldStrength = newValue
            changed
        } ?: false
        if (boldChanged) {
            renderCurrentPage()
        } else {
            applyFitMode()
            applyFilters()
        }
    }
```

把 `openBook` 內套用 `initialPreferences` 的那幾行：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
```

改為（`boldStrength` 一併在此處先解析好，因為緊接著就會呼叫 `renderCurrentPage()`，不需要額外觸發）：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
```

把 `renderCurrentPage()` 的正常渲染路徑（`page.render(bitmap, ...)` 到 `applyFilters()` 之間）：

```kotlin
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            applyFitMode()
            applyFilters()
```

改為：

```kotlin
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val finalBitmap = if (boldStrength > 0f) applyBoldEffect(bitmap) else bitmap
            imageView.setImageBitmap(finalBitmap)
            applyFitMode()
            applyFilters()
```

**OOM 回退路徑維持不變，刻意不加入 `applyBoldEffect()`**（見 Global Constraints「OOM 回退路徑不套用加粗」）。

在 `applyFilters()` 方法結尾的 `}` 之後新增：

```kotlin
    /**
     * 型態學膨脹（加粗），對 bitmap 做「取鄰域內最小亮度值」的膨脹運算，
     * 讓深色筆畫（文字）向外擴張、變粗變黑（見 docs/epics/epic-4-pdf-enhance/
     * plans/plan-issue-4.md「演算法決策」：全 API 24+ 統一用同一套手動像素
     * 陣列運算，不分 API 24-30／31+ 兩條路徑）。
     *
     * 效能策略：先縮小到 [BOLD_DOWNSCALE_FACTOR] 工作尺寸做膨脹運算，再放大
     * 回原尺寸，避免對全解析度 bitmap 直接做二維鄰域掃描造成明顯延遲（決策
     * #13 已授權濾鏡效能寬鬆處理）。
     */
    private fun applyBoldEffect(source: Bitmap): Bitmap {
        val workWidth = (source.width * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val workHeight = (source.height * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val working = Bitmap.createScaledBitmap(source, workWidth, workHeight, true)
        val radius = (boldStrength * BOLD_MAX_RADIUS).toInt().coerceIn(1, BOLD_MAX_RADIUS)
        val dilated = dilate(working, radius)
        val result = Bitmap.createScaledBitmap(dilated, source.width, source.height, true)
        working.recycle()
        dilated.recycle()
        return result
    }

    /**
     * 對 [bitmap] 做半徑 [radius] 的膨脹（取 (2*radius+1)^2 鄰域內每個色版
     * 的最小值，讓深色像素向外擴張）。邊界像素以 coerceIn 夾到合法範圍內
     * （等同邊緣複製，非補零），避免邊框產生非預期的暗色/亮色偽影。
     */
    private fun dilate(bitmap: Bitmap, radius: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val result = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var minR = 255
                var minG = 255
                var minB = 255
                for (dy in -radius..radius) {
                    val ny = (y + dy).coerceIn(0, height - 1)
                    for (dx in -radius..radius) {
                        val nx = (x + dx).coerceIn(0, width - 1)
                        val p = pixels[ny * width + nx]
                        val r = (p shr 16) and 0xFF
                        val g = (p shr 8) and 0xFF
                        val b = p and 0xFF
                        if (r < minR) minR = r
                        if (g < minG) minG = g
                        if (b < minB) minB = b
                    }
                }
                val a = (pixels[y * width + x] shr 24) and 0xFF
                result[y * width + x] = (a shl 24) or (minR shl 16) or (minG shl 8) or minB
            }
        }
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        out.setPixels(result, 0, width, 0, 0, width, height)
        return out
    }
```

- [ ] **Step 8: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL（邏輯正確性與效能留給 Task 3 的 `integration_test`／真機人工視覺確認）

- [ ] **Step 9: 重新執行 Dart 端全部測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS（全部通過）

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-4): PdfReaderView 新增 boldStrength 契約與型態學膨脹渲染"
```

---

## Task 2: `PdfSettingsSheet` 濾鏡分頁——加粗強度滑桿

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Modify: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `PdfReaderView.boldStrength`（Task 1，透過 `BookReaderPrefs.pdfBoldStrength` 間接消費）
- Produces: 無新公開介面——`_notifyChanged()` 擴充後送出的 `BookReaderPrefs` 多帶 `pdfBoldStrength` 欄位

**⚠️ 重要提醒（Issue 3 最終整體審查發現的注意事項）**：`_notifyChanged()` 每次都是**重建整個 `BookReaderPrefs`**，只包含目前 `_PdfSettingsSheetState` 已追蹤的本地狀態欄位（`_fitMode`／`_contrast`／`_brightness`，本 issue 新增 `_boldStrength`）。本 task **必須**把 `_boldStrength` 一併加入 `_notifyChanged()` 的建構——若漏掉，會導致「調整加粗滑桿時，先前已設定的 fitMode/contrast/brightness 被意外清空成 null」這個嚴重回歸。Task 4 的單元測試（Step 1）明確涵蓋這個情境，須確保通過。

- [ ] **Step 1: 為加粗強度滑桿寫失敗測試**

編輯 `app/test/screens/pdf_settings_sheet_test.dart`，在檔案最後（最後一個 `testWidgets` 的 `});` 之後、`}` 之前）新增：

```dart
  testWidgets('濾鏡分頁存在加粗強度滑桿，初始值反映 prefs（0..1 換算為 0..100 顯示）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfBoldStrength: 0.6),
      (_) {},
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_bold_strength_slider')))
          .value,
      60,
    );
  });

  testWidgets('prefs.pdfBoldStrength 為 null 時，滑桿顯示預設值 0', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_bold_strength_slider')))
          .value,
      0,
    );
  });

  testWidgets('拖動加粗強度滑桿後，onChanged 帶入新的 pdfBoldStrength（0..1），其餘 PDF 欄位不變',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfFitMode: PdfFitMode.fitWidth,
        pdfContrast: 10,
        pdfBrightness: -5,
        pdfBoldStrength: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump();

    expect(notified?.pdfBoldStrength, greaterThan(0));
    // 關鍵回歸檢查：加粗滑桿變動不應清空其他已追蹤的 PDF 欄位。
    expect(notified?.pdfFitMode, PdfFitMode.fitWidth);
    expect(notified?.pdfContrast, 10);
    expect(notified?.pdfBrightness, -5);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（找不到 `Key('pdf_settings_bold_strength_slider')`）

- [ ] **Step 3: 實作加粗強度滑桿**

編輯 `app/lib/screens/pdf_settings_sheet.dart`。

在欄位宣告（`late double _contrast; late double _brightness;`）之後新增：

```dart
  late double _boldStrength; // 內部儲存為 UI 顯示用的 0..100，送出前才換算回 0..1
```

在 `initState`（`_brightness = widget.prefs.pdfBrightness ?? 0;` 那一行）之後新增：

```dart
    _boldStrength = (widget.prefs.pdfBoldStrength ?? 0) * 100;
```

把 `_notifyChanged()` 改為：

```dart
  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      pdfFitMode: _fitMode,
      pdfContrast: _contrast,
      pdfBrightness: _brightness,
      pdfBoldStrength: _boldStrength / 100,
    ));
  }
```

把 `_buildFiltersTab()` 的 `children` 陣列（`_buildSliderRow(keyPrefix: 'pdf_settings_contrast', ...)` 與 `_buildSliderRow(keyPrefix: 'pdf_settings_brightness', ...)` 兩個既有項目）之後新增第三個：

```dart
          _buildSliderRow(
            keyPrefix: 'pdf_settings_bold_strength',
            label: '加粗強度',
            value: _boldStrength,
            min: 0,
            max: 100,
            step: 10,
            onChanged: (v) => setState(() {
              _boldStrength = v;
              _notifyChanged();
            }),
          ),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（12 個測試全過：Issue 2/3 既有 9 個＋本 issue 新增 3 個）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-4): PdfSettingsSheet 濾鏡分頁新增加粗強度滑桿"
```

---

## Task 3: 真機驗證（integration_test，含真正的人工視覺確認）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-2 的全部產出
- Produces: 無（驗證性質收尾任務）

**沿用 Issue 3 建立的驗證紀律**：不能只憑無人值守測試斷言通過就宣稱視覺驗證完成，必須實際截圖並用 Read 工具親自檢視。本 task 額外要留意「加粗滑桿拖動時是否有感卡頓」（因為 `boldStrength` 變動觸發完整 `renderCurrentPage()` 重新渲染，比 Issue 3 的 `contrast`/`brightness` 更重）。

- [ ] **Step 1: 新增真機驗證測試**

編輯 `app/integration_test/reader_screen_test.dart`。

在檔案最後（`}` 之前，緊接在既有最後一個 `testWidgets` 之後）新增：

```dart
  testWidgets('PDF 調整加粗強度後畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_bold.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_bold';
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

    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    // boldStrength 變動觸發完整重新渲染，比 contrast/brightness 更重，給予
    // 較長的 settle 時間。
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '調整加粗強度後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('調整 PDF 加粗強度後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_bold_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_bold_persist';
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
    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump(const Duration(seconds: 1));

    final saved = await prefsRepository.load(bookId);
    expect(saved.pdfBoldStrength, closeTo(0.1, 0.001)); // 預設 0，點一次 +10（UI）換算 +0.1

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
    expect(pdfView.boldStrength, closeTo(0.1, 0.001));
  });
```

- [ ] **Step 2: 於真實裝置上執行自動化測試**

Run: `cd app && flutter devices`（確認可用裝置；已知只有 `9491G`／API 35 這一台，見 Global Constraints「已知裝置限制」）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全部測試通過（含既有 EPUB/Fit 模式/濾鏡相關測試不迴歸）

- [ ] **Step 3: 實際截圖並親自檢視畫面（比照 Issue 3 的驗證紀律，不可省略）**

在裝置上安裝一份正常（非 instrumented）debug APK，開啟一本內容豐富、對比鮮明的真實 PDF（比照 Issue 3 Task 3 已驗證可行的操作方式與裝置座標換算注意事項——**切記把螢幕截圖顯示座標換算回真機實際解析度**，Issue 3 的 `task-3-report.md` 記錄了這個踩雷細節），依序執行：

```bash
# 1. 基準截圖（加粗強度 0）
adb -s <device-id> exec-out screencap -p > /tmp/pdf_bold_baseline.png

# 2. 把加粗強度拉到接近 100（多次點擊 increment 按鈕或拖動滑桿）
adb -s <device-id> exec-out screencap -p > /tmp/pdf_bold_adjusted.png
```

**用 Read 工具實際開啟兩張截圖並親自檢視**，具體描述視覺差異（文字筆畫是否明顯變粗、變黑）。若使用 Issue 3 已驗證過的正式 PDF（例如那份直排中文內容），特別留意加粗效果是否讓原本較細的筆畫看起來更粗更黑。

**同時記錄拖動加粗滑桿時的主觀卡頓感受**（Global Constraints 已說明 `boldStrength` 變動比 `contrast`/`brightness` 昂貴很多），依決策 #13 的寬鬆門檻判斷是否「主觀可接受」，若明顯卡頓需在報告中如實記錄，不需要當場修復（除非卡頓嚴重到近乎無法使用，那種情況才需要停下來評估是否要調整 `BOLD_DOWNSCALE_FACTOR`）。

若因故無法完成截圖比對，**必須**在報告中明確說明卡在哪裡，比照 Issue 3 的教訓，不能讓「已完成」的描述超出實際驗證範圍。

- [ ] **Step 4: 更新 `docs/epics/epic-4-pdf-enhance/issues.md` 的 Issue 4 狀態**

編輯 `docs/epics/epic-4-pdf-enhance/issues.md`，找到（測試名稱字串 `## Issue 4：影像濾鏡——加粗` 定位）：

```markdown
## Issue 4：影像濾鏡——加粗

**Status:** ready-for-agent
```

改為（**如實反映 Step 3 實際完成到什麼程度**，並明確記錄「僅在 API 35 裝置驗證，未涵蓋 API 24-30」這個已知限制，不要略過）：

```markdown
## Issue 4：影像濾鏡——加粗（已完成）

**Status:** ✅ 已完成。`PdfReaderView`（Dart＋原生）新增 `boldStrength` 契約，原生端以統一的手動像素陣列運算（縮小工作尺寸做膨脹再放大，涵蓋全部 API 24+，不分版本分支）實作型態學膨脹、`PdfSettingsSheet` 濾鏡分頁新增加粗強度滑桿皆已完成。**已知限制**：僅在 API 35 真機（9491G）驗證，未涵蓋 API 24-30 裝置（本專案目前無此範圍的可用測試裝置），但因實作本身不分 API 版本分支，風險已透過統一實作降低。[此處由執行者依 Step 3 實際結果填寫：真機自動化測試 N/N 通過；截圖視覺比對結果——具體描述加粗前後的筆畫差異；拖動滑桿的主觀卡頓感受，或說明未完成的原因]。完整計劃見 `plans/plan-issue-4.md`。
```

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/reader_screen_test.dart docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "test(epic-4): 新增 Issue 4 真機驗證測試（含截圖視覺比對）並標記完成"
```
