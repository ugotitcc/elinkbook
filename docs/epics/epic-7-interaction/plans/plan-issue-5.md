# Epic 7 Issue 5 — EPUB FXL 熱區導覽 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 EPUB FXL（固定版面）現有的暫代版三欄熱區（`epic-16-dual-page` Issue 9）擴充為 3×3 九宮格，並接上 Issue 4 建立的統一沉浸模式與熱區分派機制（`ReaderScreen._handleZoneAction`／`triggerZoneAction`）。

**Architecture:** `EpubReaderView` 既有的 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn` 兩個暫代版建構參數整段移除，改為與 `PdfReaderView`（Issue 4）對稱的 `navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 三個建構參數；`build()` 內既有的三欄 `Row`+`GestureDetector` 疊加層擴充為 `Column`（3 列）+`Row`（3 欄）共 9 個獨立 `GestureDetector`，每格 `key: Key('nav_zone_$index')`，索引由格子在陣列中的位置直接決定（`row * 3 + col`），**不需要**呼叫 `hitTestZoneIndex()`（與 PDF 不同，spec.md 已明確定調：9 個獨立小 `GestureDetector` 時格子索引由排版位置決定，只有原生 Kotlin 端座標回呼才需要 `hitTestZoneIndex()`/`NavZoneHitTester.cellIndex()` 換算）。**FXL 的九宮格疊加層不會遇到 Issue 4 在 PDF 上發現的「`GestureDetector.onTapUp` 包住 `AndroidView` 時永遠不會觸發」問題**——關鍵結構差異是：`EpubReaderView.build()` 的疊加層是 `Stack` 中與 `AndroidView`同層級的「兄弟節點」（`AndroidView` 與熱區疊加層是 `Stack` 的兩個並列子節點），而不是像 `PdfReaderView` 那樣把 `GestureDetector` 包在 `AndroidView` 外層（`AndroidView` 是 `GestureDetector` 的子孫節點）；疊加層本身不透明（`HitTestBehavior.opaque`）且繪製在 `AndroidView` 之上，`Stack.hitTestChildren()` 由上而下、命中即停止，一旦熱區疊加層被命中，`AndroidView` 完全不會進入 hit-test 路徑，其內建的 `_PlatformViewGestureRecognizer` 根本不會加入手勢競技場——不會發生 Issue 4 那種「先加入者贏」的仲裁問題，`onTap` 可以正常觸發，不需要比照 `PdfReaderView` 改用 `Listener` 手動座標判讀。此結構自 `epic-16-dual-page` Issue 9 起已生產驗證（既有三欄熱區用同一模式運作正常），本 issue 只是把格數從 3 擴充為 9，機制不變。

`ReaderScreen._handleZoneAction`（Issue 4 已建立）新增 EPUB 分支：`previousPage`/`nextPage` 呼叫新增的 `EpubReaderView.nextPage`/`previousPage` 強型別 static helper（比照 `PdfReaderView.nextPage`/`previousPage` 既有模式，取代原本掛在熱區 `onTap` 上直接呼叫 State 私有 instance method 的舊寫法）；`menu` 沿用既有的 `_chromeVisible` 切換邏輯，PDF／EPUB FXL 共用同一段程式碼，不需要另外分支。**`previousPage`/`nextPage` 刻意不影響 `_chromeVisible`**（design.md 決策 #14）——這是與 `epic-16-dual-page` Issue 9 舊行為刻意不同的行為變更：舊版換頁一律強制收起懸浮控制項，本 issue 起換頁不再影響沉浸模式顯示狀態。

**Tech Stack:** Flutter（`GestureDetector.onTap`／`Column`+`Row`+`Expanded` 排版）、既有 `ZoneAction`（epic-7 Issue 2 已完成）、`flutter_test`（純 Dart widget test，無需真實裝置）、`integration_test`（真實裝置，FXL 的 `tester.tap()` 手勢模擬**可靠**——與 PDF 不同，見上方「架構」段落的結構差異說明；本 issue 沿用 `epic-16-dual-page` Issue 9 既有 `integration_test` 檔案已驗證多年的 `tester.tap()` 模式，不需要比照 PDF Issue 4 改用 `triggerZoneAction` 靜態 helper 繞開手勢模擬）。

## Global Constraints

- `EpubReaderView` 移除 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn` 兩個建構參數（`epic-16-dual-page` Issue 9 暫代版 API），新增 `navZoneActions`（`List<ZoneAction>`，預設全 9 格 `ZoneAction.none`，非 `required`）、`onZoneAction`（`ValueChanged<ZoneAction>?`，預設 `null`）、`showNavZoneDebugOverlay`（`bool`，預設 `false`）——三者定義與預設值完全比照 `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`，epic-7 Issue 4）既有慣例。
- 熱區 `Key` 命名從舊版 `epub_fxl_tap_zone_previous`／`epub_fxl_tap_zone_next`／`epub_fxl_tap_zone_toggle_controls` 改為 `Key('nav_zone_$index')`（`index` 0-8，列優先），與 `PdfReaderView` 既有的 9 格 `Key` 命名慣例一致。
- 每格 `GestureDetector` 沿用既有「`onTap` + no-op `onHorizontalDragStart`/`onVerticalDragStart` 搶手勢競技場」機制不變（design.md 決策 #18；spec.md「EPUB FXL：沿用既有 3 欄疊加層機制...擴充為 9 格」）——底層 Readium WebView 有自己的原生滑動手勢，沒有 no-op drag 搶先決議，一段拖曳手勢仍可能被判定為非點擊而讓 `AndroidView` 接手。
- 「無動作」格（`ZoneAction.none`）維持既有已知限制：攔截觸控但不做事（`HitTestBehavior.opaque` 天然滿足，呼叫 `onZoneAction?.call(ZoneAction.none)` 後 `_handleZoneAction` 的 `none` 分支不做任何事），FXL 內嵌超連結等 HTML 互動元素在熱區範圍內仍無法點選——**不順便修復**（design.md 決策 #17，刻意維持現狀）。
- 新增 `static void nextPage(GlobalKey<State<EpubReaderView>> key)`／`static void previousPage(...)`，比照 `PdfReaderView.nextPage`/`previousPage`（epic-7 Issue 4）既有模式：不使用 `as dynamic` 跨越 State 的 private 邊界。取代原本 `_EpubReaderViewState` 內的私有 instance method `nextPage()`/`previousPage()`（原本掛在舊版三欄熱區的 `onTap` 上直接呼叫；本 issue 起熱區只負責回報 `ZoneAction`，實際換頁呼叫改由 `ReaderScreen._handleZoneAction` 透過新的 static helper 觸發）。全文檢索確認這兩個 instance method 除了 `build()` 內部呼叫外沒有其他呼叫端，可安全整段移除。
- `ReaderScreen._handleZoneAction`（Issue 4 已建立，`app/lib/screens/reader_screen.dart`）新增 EPUB 分支：`previousPage`/`nextPage` 呼叫 `EpubReaderView.previousPage`/`nextPage`（僅當 `detectBookFormat(widget.filePath) == BookFormat.epub` 時；流式 EPUB 由於 `EpubReaderView` 只在 `_isFixedLayout == true` 時才疊加熱區、才會回呼 `onZoneAction`，`_handleZoneAction` 收到 EPUB 格式的 `previousPage`/`nextPage` 時必然來自 FXL，不需要額外檢查 `_isFixedLayout`）。**`previousPage`/`nextPage` 依然不得變更 `_chromeVisible`**（design.md 決策 #14，Issue 4 已建立的既有規則，本 issue 延續不變）。
- `_buildNativeView()` 的 `EpubReaderView(...)` 建構呼叫新增 `navZoneActions: resolved.navZoneActions`／`onZoneAction: _handleZoneAction`／`showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay`（`ResolvedPreferences` 兩欄位已由 epic-7 Issue 2 建立，`PdfReaderView` 分支已在用，直接複用同一份 `resolved` 物件），移除舊的 `onToggleFixedLayoutControls`/`onFixedLayoutPageTurn` 兩個具名參數。
- FXL 既有 4 個懸浮按鈕（返回／設定／書籤／筆記，`app/lib/screens/reader_screen.dart` 約 1204-1281 行）的 `_chromeVisible` 判斷式**不需要變動**——Issue 4 已完成從 `_fixedLayoutControlsVisible` 到 `_chromeVisible` 的遷移，本 issue 純粹是熱區觸發來源從舊回呼改為 `_handleZoneAction`，讀取的狀態欄位不變。
- 懸浮按鈕與熱區疊加層的畫面層級關係：懸浮按鈕是外層 `body` `Stack`（`app/lib/screens/reader_screen.dart` 的 `LayoutBuilder`／`Stack` 內，`_buildNativeView(format, isLandscape)` 之後的 `Positioned` 子節點）的**兄弟節點**，在 `_buildNativeView()` 回傳的 `EpubReaderView` 整體之後才加入 `Stack`，因此繪製順序在 `EpubReaderView`（含其內部熱區疊加層）之上、hit-test 優先層級也更高——懸浮按鈕本身的點擊不會被底下的九宮格熱區攔截，design.md「已知風險」段落標記的「熱區疊加層搶走懸浮按鈕點擊」疑慮，因既有 `Stack` 分層架構已天然規避，不需要額外程式碼處理，僅需一個 widget test 驗證。
- 本 issue 完全不涉及 EPUB 流式（`_isFixedLayout == false`）路徑，流式熱區由 Issue 6 建立（原生 Kotlin `InputListener`），與本 issue 的 Flutter 端 `GestureDetector` 疊加層完全獨立、互不影響。
- `flutter analyze` 全程須保持乾淨；本 issue 前 2 個 Task 完全不需要真實裝置即可驗收，Task 3 需要真實裝置/模擬器。
- 套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/...`）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/epub_reader_view.dart` | 修改 | 移除 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn`；新增 `navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay`／`static nextPage`/`previousPage`；三欄熱區擴充為九宮格 |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` 的 `EpubReaderView(...)` 建構改接新參數；`_handleZoneAction()` 新增 EPUB 分支 |
| `app/test/reader/epub_reader_view_test.dart` | 修改 | 舊三欄熱區 2 個測試改寫為九宮格版本（Task 1） |
| `app/test/screens/reader_screen_test.dart` | 修改 | 舊 2 個 FXL 熱區測試改寫（其中換頁測試依 design.md 決策 #14 反轉斷言）＋新增端到端真實點擊測試（Task 2） |
| `app/integration_test/epub_fxl_tap_zone_test.dart` | 修改 | 既有三欄熱區真機測試擴充/改寫為九宮格版本（Task 3） |

---

### Task 1：`EpubReaderView` — 移除舊三欄 API，新增九宮格熱區判讀

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`
- Test: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes：`ZoneAction`（epic-7 Issue 2，`app/lib/reader/zone_action.dart`）
- Produces：`EpubReaderView` 新增建構參數 `List<ZoneAction> navZoneActions`（預設全 9 格 `ZoneAction.none`）、`ValueChanged<ZoneAction>? onZoneAction`（預設 `null`）、`bool showNavZoneDebugOverlay`（預設 `false`）；移除 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn`；`static void nextPage(GlobalKey<State<EpubReaderView>> key)`／`static void previousPage(...)`——供 Task 2 的 `_handleZoneAction` 呼叫

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/epub_reader_view_test.dart` 頂部 import 區塊，`import 'package:elinkbook/reader/writing_mode.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/zone_action.dart';
```

檔案第 273-366 行（`FXL 三欄熱區：...` 與 `isFixedLayout 維持預設 false 時，不疊加三欄熱區` 兩個測試），原本：

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
    var pageTurnCalled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          onToggleFixedLayoutControls: () => toggleCalled++,
          onFixedLayoutPageTurn: () => pageTurnCalled++,
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
    expect(pageTurnCalled, 2,
        reason: '左右熱區各觸發一次換頁，onFixedLayoutPageTurn 應各被呼叫一次，'
            '中間熱區（純顯示切換）不應觸發它');
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

改為：

```dart
  testWidgets(
      'FXL 九宮格熱區：isFixedLayout 變為 true 後，9 個 Key(nav_zone_$index) 存在，'
      '點擊各格觸發對應 onZoneAction（含 none 格仍攔截觸控）',
      (tester) async {
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

    final capturedActions = <ZoneAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.none, ZoneAction.menu, ZoneAction.none,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneAction: capturedActions.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

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

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage]);

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage, ZoneAction.menu]);

    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(capturedActions,
        [ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage]);

    // index 3：ZoneAction.none——「無動作」格仍應攔截觸控並回報 none（而非
    // 完全沒有反應，design.md 決策 #17：攔截但不做事，不是穿透不處理）。
    await tester.tap(find.byKey(const Key('nav_zone_3')));
    await tester.pump();
    expect(capturedActions,
        [ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage, ZoneAction.none]);
  });

  testWidgets('showNavZoneDebugOverlay=true 時，FXL 格子顯示對應動作文字標籤', (tester) async {
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
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          showNavZoneDebugOverlay: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

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

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
  });

  testWidgets('isFixedLayout 維持預設 false 時，不疊加九宮格熱區', (tester) async {
    await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsNothing);
    }
  });

  testWidgets('EpubReaderView.nextPage/previousPage static helper 呼叫原生端對應 method',
      (tester) async {
    final key = GlobalKey<State<EpubReaderView>>();
    final calls = await _pumpEpubReaderView(
      tester,
      EpubReaderView(
        key: key,
        filePath: '/tmp/sample_fixed_layout.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    EpubReaderView.nextPage(key);
    await tester.pump();
    EpubReaderView.previousPage(key);
    await tester.pump();

    expect(calls.map((c) => c.method).toList(), ['nextPage', 'previousPage']);
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/epub_reader_view_test.dart
```

Expected：FAIL（`Error: No named parameter with the name 'navZoneActions'`）。

- [ ] **Step 3：實作**

在 `app/lib/reader/epub_reader_view.dart` 頂部 import 區塊尾端（`import 'writing_mode.dart';` 之後）新增：

```dart
import 'zone_action.dart';
```

欄位宣告區塊，原本（第 61-67 行）：

```dart
  /// 固定版面（FXL）中間熱區觸發，切換 ReaderScreen 懸浮控制項的顯示/隱藏。
  final VoidCallback? onToggleFixedLayoutControls;

  /// 固定版面（FXL）左/右熱區換頁時觸發，讓 ReaderScreen 自動收起懸浮控制項
  ///（更沉浸的閱讀體驗）。與 [onToggleFixedLayoutControls] 刻意不同：這裡不論
  /// 收起前是顯示或隱藏，一律強制收起（非切換語意）。
  final VoidCallback? onFixedLayoutPageTurn;
```

改為：

```dart
  /// 3×3 導航熱區的動作對照表（epic-7-interaction Issue 2/5），長度固定
  /// 9，索引慣例見 `zone_hit_test.dart`（0-indexed、列優先）——僅 FXL
  /// （[_EpubReaderViewState._isFixedLayout] 為 true）生效，流式 EPUB 完全
  /// 不使用（見 epic-7-interaction Issue 6，改由原生 Kotlin `InputListener`
  /// 自主處理）。預設全部 [ZoneAction.none]（非 `required`——比照
  /// `PdfReaderView.navZoneActions` 既有慣例，epic-7 Issue 4）。
  final List<ZoneAction> navZoneActions;

  /// 點擊熱區換算出動作後觸發，呼叫端（`ReaderScreen`）負責分派實際行為
  /// （換頁／切換沉浸模式，見 `ReaderScreen._handleZoneAction`）。取代原本
  /// 的 `onToggleFixedLayoutControls`／`onFixedLayoutPageTurn` 兩個舊回呼
  /// （`epic-16-dual-page` Issue 9 暫代版 API，本 issue 移除）。
  final ValueChanged<ZoneAction>? onZoneAction;

  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），比照
  /// `PdfReaderView.showNavZoneDebugOverlay`（epic-7 Issue 2/3/4）。
  final bool showNavZoneDebugOverlay;
```

建構子具名參數區塊，原本：

```dart
    this.onToggleFixedLayoutControls,
    this.onFixedLayoutPageTurn,
```

改為：

```dart
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
```

`setDecorations` static helper（原本第 170-180 行）之後、`@override State<EpubReaderView> createState()` 之前，新增 2 個 static helper：

```dart
  /// 供 `ReaderScreen._handleZoneAction` 呼叫下一頁／spread（僅 FXL 熱區使用；
  /// 流式 EPUB 的換頁完全由原生 Kotlin `InputListener` 自主處理，不經過這裡，
  /// 見 epic-7-interaction Issue 6）。強型別 static helper，比照
  /// `PdfReaderView.nextPage` 既有模式（epic-7 Issue 4），取代原本掛在
  /// 熱區 `GestureDetector.onTap` 上直接呼叫的 State 私有 instance method。
  static void nextPage(GlobalKey<State<EpubReaderView>> key) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('nextPage');
    }
  }

  /// 供 `ReaderScreen._handleZoneAction` 呼叫上一頁／spread，同上僅 FXL 熱區
  /// 使用。強型別 static helper，比照 `PdfReaderView.previousPage`。
  static void previousPage(GlobalKey<State<EpubReaderView>> key) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('previousPage');
    }
  }
```

移除 `_EpubReaderViewState` 內原本的兩個 instance method（原本第 311-324 行，`nextPage()`／`previousPage()` 整段刪除，已由上方新增的 static helper 取代）：

```dart
  /// 導航至下一頁／spread（僅 FXL 三欄熱區呼叫，見 build()）。換頁後一併觸發
  /// [EpubReaderView.onFixedLayoutPageTurn]，讓呼叫端（ReaderScreen）自動收起
  /// 懸浮控制項——這與中間熱區的 [EpubReaderView.onToggleFixedLayoutControls]
  /// 是切換語意（toggle）刻意不同，換頁一律「收起」，不論收起前是顯示或隱藏。
  void nextPage() {
    _channel?.invokeMethod('nextPage');
    widget.onFixedLayoutPageTurn?.call();
  }

  /// 導航至上一頁／spread，同上一併觸發 [EpubReaderView.onFixedLayoutPageTurn]。
  void previousPage() {
    _channel?.invokeMethod('previousPage');
    widget.onFixedLayoutPageTurn?.call();
  }

```

（刪除後，`_handleMethodCall()` 方法結尾的 `}` 直接接續 `build()` 方法，中間不留空白方法。）

`build()` 方法內三欄熱區疊加層，原本：

```dart
        if (_isFixedLayout)
          // FXL 專屬的三欄點擊熱區（暫代版，見 CONTEXT.md「FXL 換頁熱區
          // （暫代版）」／docs/epics/epic-16-dual-page/issues.md Issue 9）：
          // 取代原生滑動手勢換頁，避免 E-Ink 裝置動畫殘影，並繞開 Android
          // WebView 對尚未可視的預載頁面延後渲染造成的縮放跳動（Readium
          // kotlin-toolkit 已知問題，非本專案可控）。流式 EPUB
          // （_isFixedLayout == false）完全不受影響，維持原生手勢。
          //
          // 每個熱區同時提供 onTap 與（no-op 的）onHorizontalDragStart/
          // onVerticalDragStart——沒有後兩者的話，一段「越過臨界距離的拖曳」
          // 手勢會被 Flutter 的手勢競技場判定不是點擊，讓底層原生
          // AndroidView 有機會接手（等於滑動手勢還是繞過我們直接落到
          // Readium 的 WebView，觸發它自己的滑動換頁，等於沒解決問題）。
          // 加上這兩個 no-op 回呼，讓我們的 GestureDetector 對任何觸控
          // 序列（不論最終是否判定為點擊）都搶到手勢競技場的勝利，原生層
          // 完全收不到觸控事件。（雙指縮放/pinch-to-zoom 刻意不攔截，見
          // Task 2 Step 3 之後的「待確認事項」。）
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
}
```

改為：

```dart
        if (_isFixedLayout)
          // FXL 專屬的九宮格點擊熱區（epic-7-interaction Issue 5，取代
          // epic-16-dual-page Issue 9 的三欄暫代版）：取代原生滑動手勢換頁，
          // 避免 E-Ink 裝置動畫殘影，並繞開 Android WebView 對尚未可視的
          // 預載頁面延後渲染造成的縮放跳動（Readium kotlin-toolkit 已知
          // 問題，非本專案可控）。流式 EPUB（_isFixedLayout == false）完全
          // 不受影響，維持原生手勢（見 epic-7-interaction Issue 6）。
          //
          // 每個熱區同時提供 onTap 與（no-op 的）onHorizontalDragStart/
          // onVerticalDragStart——沒有後兩者的話，一段「越過臨界距離的拖曳」
          // 手勢會被 Flutter 的手勢競技場判定不是點擊，讓底層原生
          // AndroidView 有機會接手（等於滑動手勢還是繞過我們直接落到
          // Readium 的 WebView，觸發它自己的滑動換頁，等於沒解決問題）。
          // 加上這兩個 no-op 回呼，讓我們的 GestureDetector 對任何觸控
          // 序列（不論最終是否判定為點擊）都搶到手勢競技場的勝利，原生層
          // 完全收不到觸控事件。（雙指縮放/pinch-to-zoom 刻意不攔截。）
          //
          // 【與 PdfReaderView 熱區疊加層刻意不同，供未來維護者知悉】本疊加
          // 層是 Stack 中與 AndroidView 同層級的「兄弟節點」，而非像
          // PdfReaderView（epic-7-interaction Issue 4）那樣把 GestureDetector
          // 包在 AndroidView 外層——Issue 4 發現「GestureDetector 包住
          // AndroidView 時 onTapUp 永遠不會觸發」（AndroidView 內建的被動
          // _PlatformViewGestureRecognizer 依 Flutter 手勢競技場「先加入者
          // 贏」的預設仲裁規則必勝）。這裡不會遇到同樣的問題：本疊加層不透明
          // （HitTestBehavior.opaque）且繪製在 AndroidView 之上，Stack 的
          // hit-test 由上而下、命中即停止，AndroidView 完全不會被 hit-test
          // 到，其內建的 _PlatformViewGestureRecognizer 根本不會加入手勢
          // 競技場——onTap 可以正常觸發，不需要比照 PdfReaderView 改用
          // Listener 手動座標判讀。此結構自 epic-16-dual-page Issue 9
          // 起已生產驗證，本次只是把格數從 3 擴充為 9。
          //
          // 【已知取捨，記錄於此供未來維護者知悉】九宮格熱區疊加層覆蓋整個
          // AndroidView 範圍，會擋住底層 Readium WebView 的所有觸控事件——若
          // FXL 書籍內嵌超連結或其他 HTML 互動元素，這些功能在熱區生效期間
          // 會失效。目前鎖定的使用情境（FXL 漫畫）通常沒有這類互動元素，此為
          // 刻意接受的限制，不順便修復（design.md 決策 #17）。
          Positioned.fill(
            child: Column(
              children: List.generate(3, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(3, (col) {
                      final index = row * 3 + col;
                      return Expanded(
                        child: GestureDetector(
                          key: Key('nav_zone_$index'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onZoneAction
                              ?.call(widget.navZoneActions[index]),
                          onHorizontalDragStart: (_) {},
                          onVerticalDragStart: (_) {},
                          child: widget.showNavZoneDebugOverlay
                              ? Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _zoneActionLabel(widget.navZoneActions[index]),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  String _zoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/epub_reader_view_test.dart
```

Expected：PASS（含改寫的 4 個測試，以及全部既有測試——證明 API 變更與九宮格擴充沒有造成其餘偏好參數/字元計數/選字/標記相關測試回歸）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-7): expand EPUB FXL hotzone from 3-column to 9-cell nav zone API"
```

---

### Task 2：`ReaderScreen` 串接新版 `EpubReaderView` API + 擴充 `_handleZoneAction`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`EpubReaderView.navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay`/`nextPage`/`previousPage`（Task 1）、`ResolvedPreferences.navZoneActions`/`showNavZoneDebugOverlay`（epic-7 Issue 2）、既有 `_handleZoneAction`（epic-7 Issue 4）
- Produces：無新增對外介面，`_handleZoneAction` 新增 EPUB 分支

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 檔案第 565-620 行（`固定版面點擊中間熱區可切換懸浮按鈕顯示/隱藏`）與第 622-661 行（`固定版面點擊左/右熱區換頁後，懸浮按鈕自動收起`），原本：

```dart
  testWidgets('固定版面點擊中間熱區可切換懸浮按鈕顯示/隱藏', (tester) async {
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

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
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

    // 直接呼叫 onToggleFixedLayoutControls 模擬中間熱區觸發
    view.onToggleFixedLayoutControls?.call();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );

    // 再次觸發切換顯示
    view.onToggleFixedLayoutControls?.call();
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

  testWidgets('固定版面點擊左/右熱區換頁後，懸浮按鈕自動收起', (tester) async {
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

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );

    // 直接呼叫 onFixedLayoutPageTurn 模擬換頁觸發
    view.onFixedLayoutPageTurn?.call();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
      reason: '換頁後，懸浮控制項應自動收起',
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );
  });
```

改為：

```dart
  testWidgets('FXL：觸發熱區「選單」動作可切換懸浮按鈕顯示/隱藏', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
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

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
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

  testWidgets(
      'FXL：觸發熱區「上一頁/下一頁」動作不影響懸浮按鈕顯示狀態'
      '（design.md 決策 #14，與 epic-16-dual-page Issue 9 舊行為刻意不同——'
      '換頁後不再自動收起）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
      reason: '換頁不應收起懸浮控制項（design.md 決策 #14）',
    );

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );
  });

  testWidgets('FXL：真實點擊熱區「選單」格（index 1，中欄）觸發沉浸模式切換', (tester) async {
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

    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu
    // （見 app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL（`Error: The method 'triggerZoneAction' isn't defined` 不會發生——該 helper 已存在——實際會是 `The named parameter 'onToggleFixedLayoutControls' isn't defined` 之類的建構參數編譯錯誤，或第三個新測試點擊 `nav_zone_1` 後 AppBar/懸浮按鈕未如預期變化，因為 `_buildNativeView()` 尚未接上新參數）。

- [ ] **Step 3：實作**

修改 `app/lib/screens/reader_screen.dart` 的 `_buildNativeView()` 方法，`case BookFormat.epub:` 分支原本：

```dart
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          onToggleFixedLayoutControls: () => setState(
            () => _chromeVisible = !_chromeVisible,
          ),
          // 換頁時一律收起懸浮控制項（更沉浸的閱讀體驗，人類決策，見
          // tmp/epic-16/reviews/review-plan-issue-9.md 之後的討論）——與上面的
          // onToggleFixedLayoutControls 刻意不同：這裡不論收起前是顯示或隱藏，
          // 一律強制設為 false，不是切換（toggle）語意。
          onFixedLayoutPageTurn: () =>
              setState(() => _chromeVisible = false),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
```

改為：

```dart
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          initialLocatorJson: _initialPosition?.epubLocatorJson,
```

`_handleZoneAction()` 方法，原本：

```dart
  /// 熱區動作統一分派入口（epic-7-interaction Issue 4）：`previousPage`/
  /// `nextPage` 呼叫目前格式對應的既有換頁方法；`menu` 切換 [_chromeVisible]
  /// （沉浸模式）；`none` 不做事。**`previousPage`/`nextPage` 刻意不影響
  /// [_chromeVisible]**（design.md 決策 #14）。目前只實作 PDF 換頁分支——
  /// EPUB FXL 分支由 Issue 5 擴充，EPUB 流式的 previousPage/nextPage 完全
  /// 不經過這裡（原生 Kotlin `InputListener` 自主處理，只有 `menu` 動作經
  /// Issue 6 的 `onZoneTapped` 回呼）。
  void _handleZoneAction(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        if (detectBookFormat(widget.filePath) == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (detectBookFormat(widget.filePath) == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
```

改為：

```dart
  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支）：`previousPage`/`nextPage` 呼叫目前格式對應的既有換頁方法；
  /// `menu` 切換 [_chromeVisible]（沉浸模式）；`none` 不做事。
  /// **`previousPage`/`nextPage` 刻意不影響 [_chromeVisible]**（design.md
  /// 決策 #14）。EPUB 分支只在 FXL（`EpubReaderView` 僅 `_isFixedLayout ==
  /// true` 時才疊加熱區、才會回呼 `onZoneAction`）生效——EPUB 流式的
  /// previousPage/nextPage 完全不經過這裡（原生 Kotlin `InputListener`
  /// 自主處理，只有 `menu` 動作經 Issue 6 的 `onZoneTapped` 回呼）。
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          EpubReaderView.previousPage(_epubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          EpubReaderView.nextPage(_epubReaderViewKey);
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（含改寫/新增的 3 個測試，以及全部既有測試——證明 API 變更沒有造成其餘 PDF／EPUB 流式相關測試回歸）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-7): wire EpubReaderView nav zone params, add FXL branch to _handleZoneAction"
```

---

### Task 3：真機驗證——`integration_test`

**Files:**
- Modify: `app/integration_test/epub_fxl_tap_zone_test.dart`

**Interfaces:**
- Consumes：`EpubReaderView`（Task 1）
- Produces：無（驗證性質工單）

**與 PDF（Issue 4 Task 4）刻意不同**：PDF 的 `integration_test` 因 `GestureDetector` 包住 `AndroidView` 導致 `tester.tap()` 無法可靠模擬觸控，改用 `ReaderScreen.triggerZoneAction` 繞開手勢模擬。EPUB FXL 的熱區疊加層是 `AndroidView` 的**兄弟節點**（見本計畫「Architecture」段落的結構差異說明），不會遇到同樣的問題——本檔案沿用 `epic-16-dual-page` Issue 9 既有的 `tester.tap()` 直接模擬觸控做法（該既有測試已在真機上驗證多年），只是把測試目標從 3 欄擴充為 9 格、API 換成新的 `navZoneActions`/`onZoneAction`。

- [ ] **Step 1：改寫測試檔**

將 `app/integration_test/epub_fxl_tap_zone_test.dart` 整份內容取代為：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '固定版面 EPUB 開書後出現九宮格熱區，點擊各格觸發對應動作且真的換頁/'
      '「無動作」格仍攔截觸控不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_fxl_tap_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedActions = <ZoneAction>[];
    EpubPositionInfo? lastPosition;
    final key = GlobalKey<State<EpubReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) => lastPosition = info,
          // 涵蓋 previousPage／menu／nextPage／none 四種動作，其中 index 3
          // 為 none（design.md 決策 #17：無動作格仍應攔截觸控，只是不做事）。
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.none, ZoneAction.menu, ZoneAction.none,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneAction: (action) {
            capturedActions.add(action);
            // 模擬 ReaderScreen._handleZoneAction 的實際分派邏輯（本測試直接
            // 建構 EpubReaderView，不經過 ReaderScreen，故在此手動呼叫，讓
            // 換頁動作真的觸發原生端渲染，而非只驗證回呼有沒有被呼叫）。
            switch (action) {
              case ZoneAction.previousPage:
                EpubReaderView.previousPage(key);
                break;
              case ZoneAction.nextPage:
                EpubReaderView.nextPage(key);
                break;
              case ZoneAction.menu:
              case ZoneAction.none:
                break;
            }
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget,
          reason: '固定版面書籍應已回報 isFixedLayout=true，九宮格熱區應已疊加');
    }

    final positionAfterOpen = lastPosition;

    await tester.tap(find.byKey(const Key('nav_zone_2'))); // index 2 = nextPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.nextPage);
    expect(lastPosition?.locatorJson, isNot(equals(positionAfterOpen?.locatorJson)),
        reason: '點擊下一頁熱區應真的觸發原生端換頁，locatorJson 應變動');

    await tester.tap(find.byKey(const Key('nav_zone_0'))); // index 0 = previousPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊上一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.previousPage);

    await tester.tap(find.byKey(const Key('nav_zone_1'))); // index 1 = menu
    await tester.pump();
    expect(capturedActions.last, ZoneAction.menu,
        reason: '點擊選單熱區應回報 ZoneAction.menu');

    await tester.tap(find.byKey(const Key('nav_zone_3'))); // index 3 = none
    await tester.pump();
    expect(errorMessage, isNull, reason: '點擊無動作熱區不應觸發 onError 或崩潰');
    expect(capturedActions.last, ZoneAction.none,
        reason: '無動作格仍應攔截觸控並回報 none（並非完全無反應／穿透到底層 '
            'WebView，design.md 決策 #17）');
  });
}
```

- [ ] **Step 2：確認裝置已連線**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter devices
```

Expected：列出至少 1 台已連線的 Android 真機/模擬器，記下其 `<device-id>`。

- [ ] **Step 3：於真機執行測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test integration_test/epub_fxl_tap_zone_test.dart -d <device-id>
```

（若執行環境確認僅連接一台裝置，`-d <device-id>` 參數可省略。）

Expected：測試 PASS。若 `lastPosition?.locatorJson` 斷言失敗（例如 FXL 素材書 `onLocatorChanged` 回報頻率與預期不同），記錄實際觀察到的行為，評估是否需要放寬斷言（例如改為只驗證 `errorMessage` 維持 `null` 且無崩潰），並在下方 Step 4 一併記錄。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/epub_fxl_tap_zone_test.dart
git commit -m "test(epic-7): expand EPUB FXL nav zone integration test from 3-column to 9-cell"
```

---

### Task 4：全域驗證與收尾

**Files:** 無異動（本 Task 僅執行驗證指令，不修改任何檔案）

**Interfaces:**
- Consumes：Task 1-3 全部產出
- Produces：驗收證據（`flutter analyze`/`flutter test` 輸出），供人類判斷本 issue 是否可合併

- [ ] **Step 1：`flutter analyze` 全專案靜態分析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：`flutter test` 執行全專案測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
```

Expected：全數 PASS，含本 issue 改寫/新增的 `epub_reader_view_test.dart`／`reader_screen_test.dart`，無既有測試因 `EpubReaderView` API 變更而回歸失敗。基準為 528 個既有測試（epic-7 Issue 4 完成時的計數），本 issue 淨增加測試數：`epub_reader_view_test.dart` 由 15 個變為 17 個（移除 2 個舊版三欄熱區測試、新增 4 個九宮格版本測試），`reader_screen_test.dart` 由 64 個變為 65 個（移除 2 個舊版 FXL 熱區測試、新增 3 個），預期總數 528 - 2 - 2 + 4 + 3 = 531。

- [ ] **Step 3：確認 `git status` 乾淨（無未提交變更）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無輸出（Task 1-3 皆已個別 commit）。

（本 Task 不修改任何檔案，無需 commit。）

---

## Self-Review 摘要

- **Spec coverage**：`issues.md` Issue 5 描述的兩處模組異動（`EpubReaderView.dart` 三欄擴充九宮格＋API 改造、`ReaderScreen` 接上 `_handleZoneAction`）逐一對應 Task 1-2；`integration_test`（真實裝置，真實漫畫 FXL 素材）驗收標準對應 Task 3；`flutter analyze`／全數測試通過對應 Task 4。design.md 決策 #14（換頁不影響沉浸模式，行為變更）以 Task 2 反轉舊測試斷言的方式明確驗證；決策 #17（無動作格觸控攔截但不做事）以 Task 1/Task 3 的 `ZoneAction.none` 案例明確驗證；已知風險段落提及的「熱區疊加層與懸浮按鈕觸控範圍協調」已在 Global Constraints 說明既有 `Stack` 分層架構天然規避，Task 2 Step 1 的端到端測試（點擊 `nav_zone_1` 後懸浮按鈕正確收合）間接佐證懸浮按鈕本身不受熱區疊加層影響。
- **Placeholder scan**：所有 Task 的程式碼區塊皆為完整可執行內容，無 TBD/待補；Task 3 Step 3 對 `lastPosition` 斷言失敗情境的處理方式已明確寫出降級做法（放寬斷言＋記錄觀察），非模糊的「視情況處理」。
- **Type consistency**：`ZoneAction`／`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay`／`EpubReaderView.nextPage`/`previousPage` 命名與型別簽章在 Task 1-3 間保持一致，與 `PdfReaderView`（epic-7 Issue 4）既有對稱定義逐字相符；`_handleZoneAction` 的 EPUB 分支與既有 PDF 分支使用相同的 `detectBookFormat()` 判斷模式（並順手把原本呼叫兩次的 `detectBookFormat()` 提升到方法開頭一次，消除 Issue 4 最終審查記錄的 Minor 重複呼叫）。
