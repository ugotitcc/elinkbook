# Epic 4 Issue 5 — 智慧自動裁切 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在 `PdfSettingsSheet` 的「裁切」分頁選擇「智慧自動」，原生端首次渲染時自動偵測內容邊界（去除白邊）、全書統一套用同一比例，並持久化避免重新計算。

**Architecture:** 裁切是**破壞性渲染管線變更**（調整 `PdfRenderer.Page.render()` 的 `Matrix`，決定「PDF 頁面的哪個區域」被解碼進 bitmap），必須在 `renderCurrentPage()` 的最前面（管線順序「裁切 → fit 模式縮放 → 濾鏡」，裁切先於 Issue 2-4 建立的所有後續步驟）。新增一個原生→Dart 的 `onCropRectComputed` callback，把首次偵測結果回傳持久化，比照 Issue 2-4 的 `initialPreferences`/`setPdfPreferences` 契約模式。同時直接回應 Issue 4 整體審查的建議，新增 `BookReaderPrefs.copyWith()`，解決「`PdfSettingsSheet`／`ReaderScreen` 任一處遺漏欄位就靜默清空手足欄位」的地雷類別。

**Tech Stack:** Flutter/Dart（`MethodChannel`）、Kotlin（`Bitmap.getPixel()` 邊界掃描、`Matrix.postTranslate`/`postScale`）。

## Global Constraints

- 所有新增的程式碼註解與文件皆須使用正體中文（zh-TW），不得使用簡體中文。
- `flutter analyze` 全程必須保持乾淨（"No issues found!"）。
- `PdfCropMode`（`none`/`autoDetect`/`manual`）與 `PdfCropRect`（`left`/`top`/`right`/`bottom`，0.0-1.0 相對座標）已於 Issue 1 建立，本 issue 直接使用、不重新定義。
- **本 issue 範圍**：裁切分頁只開放「不裁切」／「智慧自動」二選項；「手動選區」（`PdfCropMode.manual`）圖示顯示但**停用**（`onPressed: null`），實作留給 Issue 6。
- **邊界偵測演算法（本計劃裁量，issues.md 授權「實作者需依 design.md『已知風險』決定」）**：單頁取樣（僅取樣目前這一頁，非設計審查 Finding 1.3 建議的「多頁取樣＋保守交集」——該建議為候選方案、非強制採用）。由四個邊緣向內掃描，找第一個「非全白」的列/行視為內容邊界，加一點邊距。取樣時每 4 個像素跳著取一次以加速掃描（`Bitmap.getPixel()` 逐像素呼叫在大圖上較慢，決策 #13 已授權效能寬鬆處理，但仍值得做這個簡單優化）。
- **快取＋不重算**（決策 #3，全書統一比例、取樣後固定）：`cropRect` 一旦算出（或由 Dart 端透過 `initialPreferences`/`setPdfPreferences` 帶入已持久化的值），原生端後續頁面／`setPdfPreferences` 呼叫一律沿用，不重新偵測。**重開書也不應重新計算**——`PdfReaderView`（Dart）只要 `widget.cropRect != null` 就必須把它放進 `initialPreferences`，讓原生端從一開始就有快取值可用，不會因為是全新的 `PlatformView` 實例就重新跑一次偵測。
- **`copyWith` 新增理由**：Issue 4 整體審查明確指出，`_handlePrefsChanged`／`PdfSettingsSheet._notifyChanged()` 若遺漏任何一個欄位，會在下次呼叫時把該欄位靜默清空成 `null`。本 issue 新增的 `onCropRectComputed` 回呼是第二個「只想更新單一欄位、保留其餘全部」的情境（`ReaderScreen._handleCropRectComputed`），加上 `PdfSettingsSheet._notifyChanged()` 現在也需要「原樣帶回」`pdfCropRect`（見 Task 3），兩者合起來已經足夠證成新增 `copyWith` 的價值，比繼續手動列舉全部欄位更不容易出錯。
- **`copyWith` 語意**：採用 `newValue ?? this.value`（不支援「明確清成 null」），與既有 `EpubReaderView`／`ReaderSettingsSheet` 一貫的「`??` 回退」語意一致。**不可**把 `ReaderScreen._handlePrefsChanged`（EPUB 用 `ReaderSettingsSheet` 與 PDF 用 `PdfSettingsSheet` 共用的既有方法）改成呼叫 `copyWith`——`ReaderSettingsSheet` 的排版方向/翻頁模式/螢幕方向三個覆寫選擇器需要能明確把欄位設回 `null`（例如「採用書籍排版」選項），`copyWith` 的 `??` 語意會讓這個「清空」操作失效。`_handlePrefsChanged` 維持原本的整列覆寫語意不變，`copyWith` 只用在 `ReaderScreen._handleCropRectComputed` 這個新增的單一情境。

---

## Task 1: `BookReaderPrefs.copyWith()`

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Modify: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes: 無新依賴
- Produces: `BookReaderPrefs copyWith({...17 個與建構子同名同型別的具名參數...})`——Task 4（`ReaderScreen._handleCropRectComputed`）會呼叫 `_prefs.copyWith(pdfCropRect: rect)`。

- [ ] **Step 1: 為 `copyWith` 寫失敗測試**

編輯 `app/test/reader/book_reader_prefs_test.dart`，在檔案最後（最後一個 `test(...)` 的 `});` 之後、`}` 之前）新增：

```dart
  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = BookReaderPrefs(
      fontSize: 18,
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 10,
      pdfCropMode: PdfCropMode.autoDetect,
    );

    final updated = original.copyWith(
      pdfCropRect:
          const PdfCropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
    );

    expect(updated.fontSize, 18);
    expect(updated.pdfFitMode, PdfFitMode.fitWidth);
    expect(updated.pdfContrast, 10);
    expect(updated.pdfCropMode, PdfCropMode.autoDetect);
    expect(
      updated.pdfCropRect,
      const PdfCropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
    );
  });

  test('copyWith 不傳任何參數時，回傳與原本欄位值完全相同（但非同一個 identity）的物件',
      () {
    const original = BookReaderPrefs(fontSize: 18, pdfContrast: -20);
    final copy = original.copyWith();

    expect(copy, original);
    expect(identical(copy, original), isFalse);
  });
```

在檔案開頭 import 區塊插入以下 1 行新 import（既有 import 保留不動）：

```dart
import 'package:elinkbook/reader/pdf_crop_mode.dart';
```

（`pdf_fit_mode.dart` 若既有測試檔尚未 import，同樣需要新增；檢查既有 import 區塊，若已存在則不重複新增）

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: FAIL（`BookReaderPrefs` 沒有 `copyWith` 方法，編譯錯誤）

- [ ] **Step 3: 實作 `copyWith`**

編輯 `app/lib/reader/book_reader_prefs.dart`，在 `hashCode` getter（`int get hashCode => ...`）結尾的 `}` 之後、類別結尾的 `}` 之前新增：

```dart
  /// 只更新明確傳入的欄位，其餘欄位沿用目前值（`newValue ?? this.value`
  /// 語意，不支援「明確清成 null」——需要清空欄位的情境（例如
  /// `ReaderSettingsSheet` 的排版方向三態選擇器）請繼續用既有的整列
  /// 建構方式，不要用這個方法，見 epic-4 plan-issue-5.md Global
  /// Constraints「copyWith 語意」的說明。
  BookReaderPrefs copyWith({
    AppFont? fontFamily,
    double? fontSize,
    double? fontWeight,
    double? lineHeight,
    double? paragraphSpacing,
    double? pageMargins,
    EpubTextAlign? textAlign,
    bool? publisherStyles,
    WritingMode? writingModeOverride,
    PageTurnMode? pageTurnModeOverride,
    ScreenOrientationSetting? screenOrientationOverride,
    PdfFitMode? pdfFitMode,
    double? pdfContrast,
    double? pdfBrightness,
    double? pdfBoldStrength,
    PdfCropMode? pdfCropMode,
    PdfCropRect? pdfCropRect,
  }) {
    return BookReaderPrefs(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      pageMargins: pageMargins ?? this.pageMargins,
      textAlign: textAlign ?? this.textAlign,
      publisherStyles: publisherStyles ?? this.publisherStyles,
      writingModeOverride: writingModeOverride ?? this.writingModeOverride,
      pageTurnModeOverride: pageTurnModeOverride ?? this.pageTurnModeOverride,
      screenOrientationOverride:
          screenOrientationOverride ?? this.screenOrientationOverride,
      pdfFitMode: pdfFitMode ?? this.pdfFitMode,
      pdfContrast: pdfContrast ?? this.pdfContrast,
      pdfBrightness: pdfBrightness ?? this.pdfBrightness,
      pdfBoldStrength: pdfBoldStrength ?? this.pdfBoldStrength,
      pdfCropMode: pdfCropMode ?? this.pdfCropMode,
      pdfCropRect: pdfCropRect ?? this.pdfCropRect,
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS

- [ ] **Step 5: 執行全部測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-4): BookReaderPrefs 新增 copyWith，回應 Issue 4 審查建議"
```

---

## Task 2: `PdfReaderView`（Dart＋原生）——cropMode／cropRect 契約與自動裁切渲染管線

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: `PdfCropMode`／`PdfCropRect`（Issue 1，已存在）
- Produces: `PdfReaderView` 新增 `final PdfCropMode? cropMode; final PdfCropRect? cropRect; final ValueChanged<PdfCropRect>? onCropRectComputed;`——Task 3（`PdfSettingsSheet`）／Task 4（`ReaderScreen`）會使用這三者。

- [ ] **Step 1: 為 Dart 端 cropMode／cropRect／onCropRectComputed 契約寫失敗測試**

編輯 `app/test/reader/pdf_reader_view_test.dart`，在檔案最後（最後一個 `testWidgets` 結尾的 `});` 之後、`}` 之前）新增：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 cropMode／cropRect',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropMode: PdfCropMode.autoDetect,
        cropRect: PdfCropRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.9),
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'cropMode': 'autoDetect',
      'cropRect': {'left': 0.05, 'top': 0.1, 'right': 0.95, 'bottom': 0.9},
    });
  });

  testWidgets('cropMode 變動時，didUpdateWidget 呼叫 setPdfPreferences',
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
        cropMode: PdfCropMode.none,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropMode: PdfCropMode.autoDetect, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {'cropMode': 'autoDetect'});
  });

  testWidgets('收到原生端 onCropRectComputed 時，正確觸發回呼', (tester) async {
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
        onCropRectComputed: (rect) => received = rect,
      ),
    ));
    await tester.pumpAndSettle();

    // 模擬原生端主動呼叫 onCropRectComputed（比照 EpubReaderView 測試對
    // onLayoutResolved 的模擬方式：透過 binaryMessenger 直接送一個
    // MethodCall 給 Dart 端已註冊的 handler）。
    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onCropRectComputed', {
      'left': 0.02,
      'top': 0.03,
      'right': 0.98,
      'bottom': 0.97,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received,
        const PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97));
  });
```

在檔案開頭 import 區塊插入以下 2 行新 import（既有 import 保留不動）：

```dart
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: FAIL（`PdfReaderView` 建構子沒有 `cropMode`/`cropRect`/`onCropRectComputed` 具名參數，編譯錯誤）

- [ ] **Step 3: 擴充 Dart 端 `PdfReaderView`**

編輯 `app/lib/reader/pdf_reader_view.dart`。

在檔案開頭 import 區塊新增：

```dart
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
```

把建構參數清單加入 `cropMode`／`cropRect`／`onCropRectComputed`：

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
  });
```

把 `didUpdateWidget` 的比較條件加入 `cropMode`（**不需要**比較 `cropRect`——`cropRect` 只會由 `onCropRectComputed` 回呼後、呼叫端重建 widget 時一併帶入，不會有「使用者互動導致 cropRect 單獨變動」的情境，比照 `fitMode` 等既有欄位的判斷原則）：

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
  }
```

把 `_buildPreferencesMap` 加入 `cropMode`／`cropRect`：

```dart
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    if (widget.contrast != null) map['contrast'] = widget.contrast;
    if (widget.brightness != null) map['brightness'] = widget.brightness;
    if (widget.boldStrength != null) map['boldStrength'] = widget.boldStrength;
    if (widget.cropMode != null) map['cropMode'] = widget.cropMode!.name;
    if (widget.cropRect != null) {
      map['cropRect'] = {
        'left': widget.cropRect!.left,
        'top': widget.cropRect!.top,
        'right': widget.cropRect!.right,
        'bottom': widget.cropRect!.bottom,
      };
    }
    return map;
  }
```

把 `_handleMethodCall` 新增 `onCropRectComputed` 分支：

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
    }
  }
```

- [ ] **Step 4: 執行測試確認 Dart 端測試通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（11 個測試全過：Issue 2-4 既有 8 個＋本 issue 新增 3 個）

- [ ] **Step 5: 讓 `ReaderScreen` 把 cropMode／cropRect 傳給 `PdfReaderView`（本步驟先做最小串接，完整持久化留給 Task 4）**

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
          boldStrength: _prefs.pdfBoldStrength,
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
          cropMode: _prefs.pdfCropMode,
          cropRect: _prefs.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
        );
```

在 `_handlePrefsChanged` 方法（`void _handlePrefsChanged(BookReaderPrefs prefs) { ... }`）結尾的 `}` 之後新增：

```dart
  /// 智慧自動裁切首次計算出矩形時觸發（原生端 onCropRectComputed），只
  /// 更新 pdfCropRect 這一個欄位，其餘欄位透過 copyWith 保留原值——這與
  /// _handlePrefsChanged（整列覆寫語意）刻意不同，因為這裡的呼叫端
  /// （PdfReaderView 原生回呼）本來就只知道新計算出的矩形，不該也不會
  /// 附帶其餘欄位的完整狀態。
  void _handleCropRectComputed(PdfCropRect rect) {
    final updated = _prefs.copyWith(pdfCropRect: rect);
    setState(() => _prefs = updated);
    widget.prefsRepository.save(widget.bookId, updated);
  }
```

在檔案開頭 import 區塊新增：

```dart
import '../reader/pdf_crop_rect.dart';
```

- [ ] **Step 6: 執行 `reader_screen_test.dart` 確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（既有測試不迴歸）

- [ ] **Step 7: 擴充原生端 `PdfReaderView.kt`**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`。

覆寫前先執行 `git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 確認工作目錄乾淨。

在 `boldStrength` 欄位宣告之後新增：

```kotlin
    // Dart PdfCropMode.name 對應字串（'none'／'autoDetect'／'manual'），
    // 預設 "none"，與 BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: String = "none"

    // 目前生效的裁切矩形（相對座標 0.0-1.0）。autoDetect 模式下由
    // detectCropRect() 首次計算後快取於此（決策 #3，全書統一比例、不逐頁
    // 重算）；也可能由 Dart 端透過 initialPreferences/setPdfPreferences
    // 直接帶入已持久化的值（避免重開書又重新計算一次）。
    private var cropRect: CropRect? = null

    /** 裁切矩形（相對座標 0.0-1.0），Kotlin 內部用資料類別，對應 Dart
     * PdfCropRect 的欄位。*/
    private data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)
```

把 `setPdfPreferences` 改為（`cropMode`／`cropRect` 變動需要完整重新渲染，理由同 `boldStrength`——裁切是調整 `PdfRenderer.Page.render()` 的 `Matrix`，必須重新解碼頁面）：

```kotlin
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
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val changed = it != cropMode
            cropMode = it
            changed
        } ?: false
        parseCropRect(preferences["cropRect"])?.let { cropRect = it }
        if (boldChanged || cropChanged) {
            renderCurrentPage()
        } else {
            applyFitMode()
            applyFilters()
        }
    }

    /** 從 method channel map 解析裁切矩形，格式不符時回傳 null（靜默忽略，
     * 比照其餘欄位的 `as? Number` 容錯風格）。*/
    @Suppress("UNCHECKED_CAST")
    private fun parseCropRect(raw: Any?): CropRect? {
        val map = raw as? Map<String, Any?> ?: return null
        val left = (map["left"] as? Number)?.toFloat() ?: return null
        val top = (map["top"] as? Number)?.toFloat() ?: return null
        val right = (map["right"] as? Number)?.toFloat() ?: return null
        val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
        return CropRect(left, top, right, bottom)
    }
```

把 `openBook` 內套用 `initialPreferences` 的那幾行：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
```

改為：

```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = it }
        parseCropRect(initialPreferences?.get("cropRect"))?.let { cropRect = it }
```

把 `renderCurrentPage()` 整個方法改為（新增裁切偵測與 Matrix 調整，其餘邏輯不變）：

```kotlin
    private fun renderCurrentPage() {
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)

        // 智慧自動裁切：尚無快取矩形時，先用一次全頁、無縮放的渲染取樣
        // 偵測邊界，計算結果快取於 cropRect 並回傳給 Dart 端持久化（決策
        // #3，全書統一比例、不逐頁重算）。
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap =
                Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            detectBitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val detected = detectCropRect(detectBitmap)
            detectBitmap.recycle()
            cropRect = detected
            channel.invokeMethod(
                "onCropRectComputed",
                mapOf(
                    "left" to detected.left.toDouble(),
                    "top" to detected.top.toDouble(),
                    "right" to detected.right.toDouble(),
                    "bottom" to detected.bottom.toDouble(),
                ),
            )
        }

        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)

        val effectiveCrop = if (cropMode != "none") cropRect else null
        val renderLeft: Float
        val renderTop: Float
        val renderWidth: Float
        val renderHeight: Float
        if (effectiveCrop != null) {
            renderLeft = effectiveCrop.left * page.width
            renderTop = effectiveCrop.top * page.height
            renderWidth = (effectiveCrop.right - effectiveCrop.left) * page.width
            renderHeight = (effectiveCrop.bottom - effectiveCrop.top) * page.height
        } else {
            renderLeft = 0f
            renderTop = 0f
            renderWidth = page.width.toFloat()
            renderHeight = page.height.toFloat()
        }

        val width = (renderWidth * scale).toInt().coerceAtLeast(1)
        val height = (renderHeight * scale).toInt().coerceAtLeast(1)

        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val matrix = android.graphics.Matrix().apply {
                // 先把裁切區域的左上角平移到原點，再統一縮放——順序不可顛倒
                // （Android Matrix 的 post* 方法依呼叫順序疊加：先
                // postTranslate 再 postScale，等同「先平移、再縮放」）。
                // effectiveCrop 為 null 時 renderLeft/renderTop 皆為 0，
                // 退化為既有（無裁切）行為，不影響 Issue 2-4 既有邏輯。
                postTranslate(-renderLeft, -renderTop)
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val finalBitmap = if (boldStrength > 0f) applyBoldEffect(bitmap) else bitmap
            imageView.setImageBitmap(finalBitmap)
            applyFitMode()
            applyFilters()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                // 同上，回退路徑也需要先填滿不透明白色背景。
                fallbackBitmap.eraseColor(android.graphics.Color.WHITE)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
        }

        page.close()
    }

    /**
     * 智慧自動裁切邊界偵測（見 plans/plan-issue-5.md Global Constraints
     * 「邊界偵測演算法」）：由四個邊緣向內掃描，找第一個「非全白」的
     * 列/行視為內容邊界，加一點邊距避免裁得太緊。單頁取樣，每 4 個像素
     * 跳著檢查一次以加速掃描。
     */
    private fun detectCropRect(bitmap: Bitmap): CropRect {
        val width = bitmap.width
        val height = bitmap.height
        val whiteThreshold = 245
        val margin = 0.01f
        val step = 4

        fun isRowContent(y: Int): Boolean {
            var x = 0
            while (x < width) {
                val p = bitmap.getPixel(x, y)
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < whiteThreshold) return true
                x += step
            }
            return false
        }

        fun isColContent(x: Int): Boolean {
            var y = 0
            while (y < height) {
                val p = bitmap.getPixel(x, y)
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < whiteThreshold) return true
                y += step
            }
            return false
        }

        var top = 0
        while (top < height - 1 && !isRowContent(top)) top++
        var bottom = height - 1
        while (bottom > top && !isRowContent(bottom)) bottom--
        var left = 0
        while (left < width - 1 && !isColContent(left)) left++
        var right = width - 1
        while (right > left && !isColContent(right)) right--

        val relLeft = (left.toFloat() / width - margin).coerceIn(0f, 1f)
        val relTop = (top.toFloat() / height - margin).coerceIn(0f, 1f)
        val relRight = (right.toFloat() / width + margin).coerceIn(0f, 1f)
        val relBottom = (bottom.toFloat() / height + margin).coerceIn(0f, 1f)
        return CropRect(relLeft, relTop, relRight, relBottom)
    }
```

- [ ] **Step 8: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL（裁切偵測與渲染邏輯正確性留給 Task 4 的真機驗證）

- [ ] **Step 9: 重新執行 Dart 端全部測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS（全部通過）

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-4): PdfReaderView 新增智慧自動裁切契約與原生偵測/渲染管線"
```

---

## Task 3: `PdfSettingsSheet` 裁切分頁——不裁切／智慧自動二選項

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Modify: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `PdfCropMode`（Issue 1，已存在）
- Produces: 無新公開介面——`_notifyChanged()` 擴充後送出的 `BookReaderPrefs` 多帶 `pdfCropMode` 欄位（並原樣帶回 `pdfCropRect`，見下方說明）

**⚠️ 重要（本 issue 的關鍵地雷防範，見 Global Constraints）**：`pdfCropRect` 是原生端計算、透過 `ReaderScreen._handleCropRectComputed`（Task 2）另一條路徑寫入的欄位，`PdfSettingsSheet` 本身不直接控制它。但 `_notifyChanged()` 每次都會呼叫 `widget.onChanged`（也就是 `ReaderScreen._handlePrefsChanged`，**整列覆寫語意**），若 `_notifyChanged()` 沒有把 `pdfCropRect` 原樣帶回，使用者在裁切算好之後只要調整任何一個濾鏡滑桿，就會把剛算好的裁切矩形靜默清空成 `null`。本 task 必須從 `widget.prefs.pdfCropRect`（不是本地狀態）讀取並原樣帶回。

- [ ] **Step 1: 為裁切分頁二選項寫失敗測試**

編輯 `app/test/screens/pdf_settings_sheet_test.dart`，在檔案最後（最後一個 `testWidgets` 的 `});` 之後、`}` 之前）新增：

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

  testWidgets('點擊智慧自動選項後，onChanged 帶入 pdfCropMode=autoDetect', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump();

    expect(notified?.pdfCropMode, PdfCropMode.autoDetect);
  });

  testWidgets(
      '已持久化 pdfCropRect 時，調整其他分頁的滑桿不會清空 pdfCropRect（關鍵回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    const existingCropRect =
        PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97);
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfCropMode: PdfCropMode.autoDetect,
        pdfCropRect: existingCropRect,
        pdfContrast: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.pdfCropMode, PdfCropMode.autoDetect);
    expect(notified?.pdfCropRect, existingCropRect); // 關鍵斷言：未被清空
  });
```

在檔案開頭 import 區塊插入以下 2 行新 import（既有 import 保留不動）：

```dart
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_crop_rect.dart';
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（找不到 `Key('pdf_settings_tab_crop')` 底下對應的 icon buttons，因為目前裁切分頁只是 `_buildPlaceholderTab('裁切功能即將推出')`）

- [ ] **Step 3: 實作裁切分頁**

編輯 `app/lib/screens/pdf_settings_sheet.dart`。

在欄位宣告（`late double _boldStrength;`）之後新增：

```dart
  late PdfCropMode _cropMode;
```

在 `initState`（`_boldStrength = (widget.prefs.pdfBoldStrength ?? 0) * 100;` 那一行）之後新增：

```dart
    _cropMode = widget.prefs.pdfCropMode ?? PdfCropMode.none;
```

把 `_notifyChanged()` 改為（新增 `pdfCropMode` 與**原樣帶回**的 `pdfCropRect`）：

```dart
  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      pdfFitMode: _fitMode,
      pdfContrast: _contrast,
      pdfBrightness: _brightness,
      pdfBoldStrength: _boldStrength / 100,
      pdfCropMode: _cropMode,
      // pdfCropRect 由原生端計算、透過 ReaderScreen.onCropRectComputed
      // 另一條路徑寫入，本分頁不直接控制，但必須原樣帶回（讀取目前的
      // widget.prefs，不是本地狀態），否則使用者調整本分頁任何一個控制項
      // 都會把已算好的裁切矩形靜默清空成 null。
      pdfCropRect: widget.prefs.pdfCropRect,
    ));
  }
```

把 `build()` 內的 `TabBarView` 的 `children` 陣列：

```dart
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildPlaceholderTab('裁切功能即將推出'),
                ],
```

改為：

```dart
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildCropTab(context),
                ],
```

在 `_buildFiltersTab()` 方法結尾的 `}` 之後、`_buildSliderRow` 方法之前，新增：

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
              // 手動選區：Issue 6 才實作，本 issue 顯示為停用狀態預留位置。
              const IconButton(
                key: Key('pdf_settings_crop_mode_manual'),
                icon: Icon(Icons.crop),
                tooltip: '手動選區（即將推出）',
                onPressed: null,
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
Expected: PASS（15 個測試全過：Issue 2-4 既有 12 個＋本 issue 新增 3 個）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-4): PdfSettingsSheet 裁切分頁新增不裁切/智慧自動二選項"
```

---

## Task 4: 真機驗證（integration_test，含真正的人工視覺確認＋「不重算」驗證）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-3 的全部產出
- Produces: 無（驗證性質收尾任務）

**沿用 Issue 3-4 建立的驗證紀律**：不能只憑無人值守測試斷言通過就宣稱視覺驗證完成，必須實際截圖並用 Read 工具親自檢視。本 task 額外要驗證 issues.md 明確要求的「不重新計算」——這是本 issue 獨有的驗收標準，Issue 3-4 都沒有這個要求。

- [ ] **Step 1: 新增真機驗證測試**

編輯 `app/integration_test/reader_screen_test.dart`。

在檔案最後（`}` 之前，緊接在既有最後一個 `testWidgets` 之後）新增：

```dart
  testWidgets('PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop';
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
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    // 首次切到 autoDetect 會觸發偵測＋完整重新渲染，給予較長的 settle
    // 時間。
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '切換至智慧自動裁切後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('智慧自動裁切計算後關閉重開該書，pdf_crop_rect 不重新計算（值一致）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_persist';
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
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    final firstRect = (await prefsRepository.load(bookId)).pdfCropRect;
    expect(firstRect, isNotNull, reason: '智慧自動裁切應已計算出矩形並持久化');

    // 關閉重開，確認 initialPreferences 帶入已持久化的 cropRect，原生端
    // 不會因為是全新 PlatformView 實例就重新偵測一次。
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
    await tester.pump(const Duration(seconds: 1));

    final secondRect = (await prefsRepository.load(bookId)).pdfCropRect;
    expect(secondRect, firstRect,
        reason: '重開書後 pdf_crop_rect 應與第一次計算的值完全一致，代表沒有重新計算');
  });
```

- [ ] **Step 2: 於真實裝置上執行自動化測試**

Run: `cd app && flutter devices`（確認可用裝置；已知只有 `9491G`／API 35 這一台）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全部測試通過（含既有測試不迴歸）

- [ ] **Step 3: 實際截圖並親自檢視畫面（比照 Issue 3-4 的驗證紀律，不可省略）**

在裝置上安裝一份正常（非 instrumented）debug APK，開啟一本**四周有明顯白邊**的真實 PDF（裁切效果需要有白邊才看得出差異，若手邊測試 PDF 內容已經頂滿整頁，裁切前後可能看不出視覺差異，屬於測試素材選擇問題、非程式邏輯問題，需要在報告中說明用了哪份 PDF、其版面特徵），依序執行：

```bash
# 1. 基準截圖（不裁切）
adb -s <device-id> exec-out screencap -p > /tmp/pdf_crop_baseline.png

# 2. 切換至智慧自動裁切
adb -s <device-id> exec-out screencap -p > /tmp/pdf_crop_adjusted.png
```

**用 Read 工具實際開啟兩張截圖並親自檢視**，具體描述視覺差異（白邊是否明顯減少、內容是否放大填滿畫面）。

- [ ] **Step 4: 更新 `docs/epics/epic-4-pdf-enhance/issues.md` 的 Issue 5 狀態**

編輯 `docs/epics/epic-4-pdf-enhance/issues.md`，找到（測試名稱字串 `## Issue 5：智慧自動裁切` 定位）：

```markdown
## Issue 5：智慧自動裁切

**Status:** ready-for-agent
```

改為（**如實反映 Step 3 實際完成到什麼程度**）：

```markdown
## Issue 5：智慧自動裁切（已完成）

**Status:** ✅ 已完成。`BookReaderPrefs.copyWith()`（回應 Issue 4 審查建議）、`PdfReaderView`（Dart＋原生）的 `cropMode`／`cropRect`／`onCropRectComputed` 契約、原生端單頁取樣邊界偵測演算法與裁切渲染管線整合（裁切 → fit 模式縮放 → 濾鏡/加粗，管線順序符合 spec.md 定案）、`PdfSettingsSheet` 裁切分頁不裁切/智慧自動二選項（手動選區停用預留 Issue 6）皆已完成。[此處由執行者依 Step 3 實際結果填寫：真機自動化測試 N/N 通過；截圖視覺比對結果——具體描述使用的 PDF 版面特徵與裁切前後差異；「不重新計算」驗證結果]。完整計劃見 `plans/plan-issue-5.md`。
```

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/reader_screen_test.dart docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "test(epic-4): 新增 Issue 5 真機驗證測試（含截圖視覺比對與不重算驗證）並標記完成"
```
