# Epic 16 Issue 9 — EPUB FXL 換頁熱區（暫代版）實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後即時勾選為 `[x]`（見 CLAUDE.md SDD 生命週期第 6 步、AGENTS.md 慣例清單）。

**Goal:** 讓 EPUB 固定版面（FXL）閱讀改用「左／右／中三欄點擊熱區」取代原生滑動手勢換頁，繞開 Android WebView 對預載頁面延後渲染造成的縮放跳動，同時避免 E-Ink 裝置滑動動畫殘影；流式 EPUB 完全不受影響。

**Architecture：** 只在 `isFixedLayout == true` 時，於 `EpubReaderView`（Dart）的 `AndroidView` 上疊加一層 `Stack` + 三欄透明 `GestureDetector`（左 1/3／中 1/3／右 1/3），左右熱區呼叫新增的 `nextPage()`/`previousPage()` method channel，原生端直接呼叫 Readium 既有的 `EpubNavigatorFragment.goForward(animated = false)`/`goBackward(animated = false)`（`EpubNavigatorFragment` 已實作 `OverflowableNavigator`，不需要重新實作配對邏輯，Readium 自己知道 spread 生效時要跳幾頁）；中間熱區純 Dart 端回呼，切換 `ReaderScreen` 懸浮控制項的顯示/隱藏。三欄疊加層需同時攔截「輕點」與「拖曳」手勢，避免拖曳手勢繞過我們的疊加層直接落到底層原生 WebView、觸發 Readium 自己的滑動換頁（等於白做）。

**Tech Stack:** Flutter（Dart）、Kotlin、Readium `kotlin-toolkit` 3.3.0（`OverflowableNavigator.goForward`/`goBackward`）、`integration_test`（真機）。

## Global Constraints

- 所有程式碼註解與說明使用正體中文（CLAUDE.md）。
- 本 issue **只處理 FXL（`isFixedLayout == true`）**，流式 EPUB 的原生滑動手勢／文字選取能力必須完全不受影響——任何修改都不得讓 `_isFixedLayout == false` 時的既有行為改變。
- 三欄熱區是**範圍受限的暫代方案**，不是 PRD 完整的可自訂 3×3 九宮格系統（傳統/單手/類 Kindle 多種對應模式、RTL 鏡像）；左右熱區固定不可自訂、不隨閱讀方向鏡像，這是刻意的簡化，完整系統留給獨立的未來 Epic，本計劃不得擴大範圍去實作它。
- 每個 Task 完成後皆需確認既有 `app/test/reader/epub_reader_view_test.dart`（現有 6 個測試）、`app/test/screens/reader_screen_test.dart`（現有測試）維持全數通過，確保 `_isFixedLayout == false` 情境零回歸。

---

### Task 1: 原生端 `nextPage`/`previousPage` method channel

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Produces：EPUB method channel（`cc.ugotit.elinkbook/epub_reader_view_$id`）新增 `"nextPage"`／`"previousPage"` case，供 Task 2 的 Dart 端呼叫。

- [ ] **Step 1: `onMethodCall()` 新增兩個 case**

找到 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 現有：

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
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

改為：

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
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()）；直接呼叫
                // Readium 既有的 OverflowableNavigator.goForward()，animated=false 避免
                // 觸發滑動動畫——這正是本 issue 要繞開的「揭露未縮放內容的可見時間窗口」
                // （見 docs/epics/epic-16-dual-page/issues.md Issue 9）。EpubNavigatorFragment
                // 已實作 OverflowableNavigator，不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
            "previousPage" -> {
                navigatorFragment?.goBackward(animated = false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

- [ ] **Step 2: 編譯確認**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 3: 既有回歸測試**

```bash
cd ../../app
flutter analyze
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected: `flutter analyze` 顯示 `No issues found!`；既有 9 個 `integration_test` 全數通過（本 Task 只新增 method channel case，未變動任何既有呼叫路徑）。

- [ ] **Step 4: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "feat(epic-16): EpubReaderView 新增 nextPage/previousPage method channel（FXL 熱區用）"
```

---

### Task 2: Dart `EpubReaderView` 三欄點擊熱區

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`
- Modify: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 1 的原生 `"nextPage"`/`"previousPage"` method channel。
- Produces：`EpubReaderView` 新增建構參數 `onToggleFixedLayoutControls: VoidCallback?`；新增公開方法 `nextPage()`/`previousPage()`（供 Task 4 `integration_test` 與測試以 `tester.state(...) as dynamic` 呼叫）；新增 `Key`：`epub_fxl_tap_zone_previous`／`epub_fxl_tap_zone_toggle_controls`／`epub_fxl_tap_zone_next`（供 Task 3 的 `ReaderScreen` 測試使用）。

- [ ] **Step 1: 新增建構參數**

在 `app/lib/reader/epub_reader_view.dart` 的 `class EpubReaderView` 欄位宣告新增（緊接在 `isLandscape` 之後）：

```dart
  final VoidCallback? onToggleFixedLayoutControls;
```

建構子新增：

```dart
    this.onToggleFixedLayoutControls,
```

- [ ] **Step 2: State 新增 `_isFixedLayout` 追蹤與 `nextPage()`/`previousPage()` 方法**

找到 `class _EpubReaderViewState` 開頭的 `MethodChannel? _channel;`，改為：

```dart
class _EpubReaderViewState extends State<EpubReaderView> {
  MethodChannel? _channel;
  bool _isFixedLayout = false;
```

在 `_handleMethodCall()` 內找到：

```dart
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
        break;
```

改為：

```dart
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        setState(() => _isFixedLayout = info.isFixedLayout);
        widget.onLayoutResolved?.call(info);
        break;
```

在 `_handleMethodCall()` 之後新增（比照 `PdfReaderView` 既有的 `nextPage()`/`previousPage()` 命名慣例）：

```dart
  /// 導航至下一頁／spread（僅 FXL 三欄熱區呼叫，見 build()）。
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁／spread。
  void previousPage() => _channel?.invokeMethod('previousPage');
```

- [ ] **Step 3: `build()` 疊加三欄熱區**

找到現有：

```dart
  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final androidView = AndroidView(
      viewType: 'cc.ugotit.elinkbook/epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
    if (!_isFixedLayout) return androidView;
    // FXL 專屬的三欄點擊熱區（暫代版，見 CONTEXT.md「FXL 換頁熱區（暫代版）」／
    // docs/epics/epic-16-dual-page/issues.md Issue 9）：取代原生滑動手勢換頁，
    // 避免 E-Ink 裝置動畫殘影，並繞開 Android WebView 對尚未可視的預載頁面
    // 延後渲染造成的縮放跳動（Readium kotlin-toolkit 已知問題，非本專案可控）。
    // 流式 EPUB（_isFixedLayout == false）完全不受影響，維持原生手勢。
    //
    // 每個熱區同時提供 onTap 與（no-op 的）onHorizontalDragStart/onVerticalDragStart
    // ——沒有後兩者的話，一段「越過臨界距離的拖曳」手勢會被 Flutter 的手勢競技場
    // 判定為不是點擊、讓底層原生 AndroidView 有機會接手（等於滑動手勢還是繞過我們
    // 直接落到 Readium 的 WebView，觸發它自己的滑動換頁，等於沒解決問題）。加上
    // 這兩個 no-op 回呼，讓我們的 GestureDetector 對任何觸控序列（不論最終是否
    // 判定為點擊）都搶到手勢競技場的勝利，原生層完全收不到觸控事件。
    return Stack(
      children: [
        androidView,
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const Key('epub_fxl_tap_zone_previous'),
                  behavior: HitTestBehavior.opaque,
                  onTap: previousPage,
                  onHorizontalDragStart: (_) {},
                  onVerticalDragStart: (_) {},
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: const Key('epub_fxl_tap_zone_toggle_controls'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onToggleFixedLayoutControls?.call(),
                  onHorizontalDragStart: (_) {},
                  onVerticalDragStart: (_) {},
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: const Key('epub_fxl_tap_zone_next'),
                  behavior: HitTestBehavior.opaque,
                  onTap: nextPage,
                  onHorizontalDragStart: (_) {},
                  onVerticalDragStart: (_) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 4: 撰寫 widget test**

在 `app/test/reader/epub_reader_view_test.dart` 新增（放在既有測試之後，`void _noop() {}` 之前）：

```dart
  testWidgets(
      'FXL 三欄熱區：isFixedLayout 變為 true 後，左/右/中熱區分別觸發 previousPage/nextPage/onToggleFixedLayoutControls',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    var toggleCalled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          onToggleFixedLayoutControls: () => toggleCalled++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    instanceCalls.clear();

    // 模擬原生端 reportLayoutResolved() 回報 isFixedLayout=true——真機上這是
    // EpubReaderView.kt 在 onPageLoaded() 首次觸發時主動送出的，這裡以正確編碼
    // 的 MethodCall 直接送進 per-instance 頻道模擬同一件事。
    final byteData = instanceChannel.codec.encodeMethodCall(
      const MethodCall('onLayoutResolved', {
        'isFixedLayout': true,
        'writingMode': 'horizontal',
      }),
    );
    await binaryMessenger.handlePlatformMessage(
      instanceChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsOneWidget);
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsOneWidget);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_next')));
    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_previous')));
    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();

    expect(instanceCalls.map((c) => c.method).toList(),
        ['nextPage', 'previousPage']);
    expect(toggleCalled, 1);
  });

  testWidgets('isFixedLayout 維持預設 false 時，不疊加三欄熱區', (tester) async {
    await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsNothing);
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsNothing);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsNothing,
    );
  });
```

- [ ] **Step 5: 執行測試**

```bash
cd app
flutter test test/reader/epub_reader_view_test.dart
flutter analyze
```

Expected: 8 個測試（既有 6 個 + 新增 2 個）全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-16): EpubReaderView(Dart) 新增 FXL 三欄點擊熱區，取代原生滑動手勢"
```

---

### Task 3: `ReaderScreen` 懸浮控制項顯示/隱藏

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `EpubReaderView.onToggleFixedLayoutControls`。
- Produces：無新增對外介面，純粹是 `ReaderScreen` 內部狀態串接。

- [ ] **Step 1: 新增 `_fixedLayoutControlsVisible` 狀態**

在 `app/lib/screens/reader_screen.dart` 的 `class _ReaderScreenState` 找到：

```dart
  bool _isFixedLayout = false;
```

之後新增：

```dart
  // 固定版面（FXL）懸浮控制項（返回鍵／設定鍵）是否顯示，由 EpubReaderView
  // 三欄熱區的中間熱區觸發切換（見 epic-16-dual-page Issue 9）。預設顯示。
  bool _fixedLayoutControlsVisible = true;
```

- [ ] **Step 2: `_buildBody()` 懸浮按鈕顯示條件加上 `_fixedLayoutControlsVisible`**

找到 `_buildBody()` 內兩個 `if (_isFixedLayout)`（分別對應 `reader_fixed_layout_back_button` 與 `reader_fixed_layout_settings_button`），皆改為：

```dart
        if (_isFixedLayout && _fixedLayoutControlsVisible)
```

（共兩處，`Positioned` 內容本身不變。）

- [ ] **Step 3: `_buildNativeView()` 傳入 `onToggleFixedLayoutControls`**

找到 `_buildNativeView()` 內 `EpubReaderView(...)` 建構呼叫，在其既有參數列末（`isLandscape: isLandscape,` 之後）新增：

```dart
          onToggleFixedLayoutControls: () => setState(
            () => _fixedLayoutControlsVisible = !_fixedLayoutControlsVisible,
          ),
```

- [ ] **Step 4: 撰寫 widget test**

在 `app/test/screens/reader_screen_test.dart` 新增（放在既有 EPUB 固定版面相關測試之後）：

```dart
  testWidgets('固定版面點擊中間熱區可切換懸浮按鈕顯示/隱藏', (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final byteData = instanceChannel.codec.encodeMethodCall(
      const MethodCall('onLayoutResolved', {
        'isFixedLayout': true,
        'writingMode': 'horizontal',
      }),
    );
    await binaryMessenger.handlePlatformMessage(
      instanceChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsOneWidget,
    );
  });
```

- [ ] **Step 5: 執行測試**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
flutter analyze
```

Expected: 全數通過（既有測試 + 新增 1 個）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-16): ReaderScreen 新增固定版面懸浮控制項顯示/隱藏切換"
```

---

### Task 4: 真機整合測試 + 文件收尾

**Files:**
- Create: `app/integration_test/epub_fxl_tap_zone_test.dart`
- Modify: `docs/epics/epic-16-dual-page/spec.md`
- Modify: `docs/epics/epic-16-dual-page/issues.md`

**Interfaces:** 無（本 Task 為驗收與文件收尾）。

- [ ] **Step 1: 撰寫真機整合測試**

建立 `app/integration_test/epub_fxl_tap_zone_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定版面 EPUB 開書後出現三欄熱區，點擊左/右/中皆不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_fxl_tap_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    var toggleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onToggleFixedLayoutControls: () => toggleCount++,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsOneWidget,
        reason: '固定版面書籍應已回報 isFixedLayout=true，三欄熱區應已疊加');
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsOneWidget);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_next')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊右熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_previous')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊左熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();
    expect(toggleCount, 1, reason: '點擊中間熱區應觸發 onToggleFixedLayoutControls');
  });
}
```

- [ ] **Step 2: 執行整合測試**

```bash
cd app
flutter test integration_test/epub_fxl_tap_zone_test.dart -d <device-id>
```

Expected: 1 個測試通過。

- [ ] **Step 3: 用真實漫畫素材人工視覺 QA**

把 `tmp/一弦定音！(06).epub` 暫時推送到裝置（`adb push`），透過既有 `ReaderScreen` 流程或臨時進入點開啟（比照 Issue 6 Bugfix 紀錄的做法），在橫向、`dualPageMode = auto` 下：
- 點擊右熱區連續換頁多次，確認**不再出現「先停下再閃一下縮小」的跳動**，也沒有滑動動畫殘影
- 點擊左熱區確認能正確回到前一頁/spread
- 點擊中間熱區確認懸浮返回鍵/設定鍵正確顯示/隱藏
- 單頁模式（`dualPageMode = never`）下重複以上驗證

若跳動仍未完全消除，如實記錄觀察到的殘餘現象（例如是否比滑動手勢時明顯減少、是否只在特定情境出現），不要為了讓驗收看起來「全過」而誇大結果。

- [ ] **Step 4: 執行全專案回歸**

```bash
flutter analyze
flutter test
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/epub_dual_page_test.dart -d <device-id>
```

Expected: 全數通過，無回歸（特別留意流式 EPUB 相關測試——本 issue 完全不應影響它們）。

- [ ] **Step 5: 更新 `spec.md`「已知限制」**

在 `docs/epics/epic-16-dual-page/spec.md`「已知限制」段落，找到 Issue 6 完成後新增的「EPUB FXL 換頁縮放跳動（2026-07-14 記錄，待優化）」條目，在其後追加一段（依 Step 3 真機驗證的實際結果調整用詞）：

```markdown
> **後續處理（Issue 9，2026-07-14 討論定案）：** 依 `/grill-with-docs` 分析，根因確認為 Android WebView 對尚未可視的預載頁面不做預先渲染/圖片解碼（Readium kotlin-toolkit 官方 [Discussion #513](https://github.com/readium/kotlin-toolkit/discussions/513) 已記錄同一類已知、未解決問題），無法單靠調整監聽時機解決。改採「三欄點擊熱區取代原生滑動手勢、`goForward`/`goBackward(animated=false)` 直接換頁」（見 `plans/plan-issue-9.md`），繞開動畫揭露未縮放內容的可見時間窗口。真機驗證結論：<依 Step 3 實際觀察結果填入>。
```

- [ ] **Step 6: 更新 `issues.md` Issue 9 狀態**

在 `docs/epics/epic-16-dual-page/issues.md` Issue 9 的 `**依賴：**` 之前加入 `**Status:** ✅ 已完成`，並附簡短完成摘要（Task 1-4 完成情形、測試通過數量、真機人工視覺 QA 的實際結論——如實反映 Step 3 的觀察結果，不誇大）。

- [ ] **Step 7: Commit**

```bash
git add app/integration_test/epub_fxl_tap_zone_test.dart \
        docs/epics/epic-16-dual-page/spec.md \
        docs/epics/epic-16-dual-page/issues.md
git commit -m "test(epic-16): Issue 9 真機整合測試 + spec.md/issues.md 收尾更新"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：issues.md Issue 9 的 3 項描述（`EpubReaderView.kt` method channel／Dart 三欄熱區／`ReaderScreen` 顯示切換）與單元測試要求，逐一對應 Task 1（原生）、Task 2（Dart 熱區）、Task 3（ReaderScreen）、Task 4（`integration_test`＋人工 QA）。「已知測試限制」（換頁動畫效果無法 `flutter test` 驗證）對應 Task 4 的真機測試與人工視覺 QA。

**占位符掃描**：全文無 TBD/待補/「同 Task N」等字樣，每個 Step 皆含可直接使用的完整程式碼；Task 4 Step 3/5/6 雖然要求「依實際結果填入」，但這是驗收/文件步驟本質使然（結果需要真機驗證才能得知），不是遺漏程式碼。

**型別一致性**：`onToggleFixedLayoutControls: VoidCallback?`／`nextPage()`／`previousPage()` 在 Task 2 定義後，Task 3（`ReaderScreen` 呼叫 `onToggleFixedLayoutControls`）、Task 4（`integration_test` 呼叫 `onToggleFixedLayoutControls`／點擊 `epub_fxl_tap_zone_*` 系列 Key）的引用皆逐字相符；三個 Key 名稱（`epub_fxl_tap_zone_previous`/`_toggle_controls`/`_next`）在 Task 2-4 全程一致。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-16-dual-page/plans/plan-issue-9.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
