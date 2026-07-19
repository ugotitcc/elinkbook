# Epic 7 Issue 6 — EPUB 流式熱區導覽（原生 `InputListener`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 EPUB 流式（reflowable，`isFixedLayout == false`）閱讀畫面支援 3×3 導航熱區——點擊由原生 Kotlin `InputListener.onTap()` 攔截、換算格子索引、查 `navZoneActions` 後分派上一頁／下一頁／選單／無動作，取代目前完全交由 Readium 原生手勢的現狀。本 issue 是本 epic 技術風險最高的部分，但 Issue 1 spike（`reviews/spike-epub-inputlistener.md`）已在真機驗證 3 項可行性風險全數通過，本計劃依 spike 結論與 `spec.md` 既有規劃直接實作，不需要退回方案。

**Architecture:** 新增純 Kotlin 物件 `NavZoneHitTester`（JVM 可測，比照 `EpubFxlScaler`/`PdfImageProcessor` 既有抽離慣例）負責座標→格子索引換算；`EpubReaderView.kt` 新增巢狀 `ZoneAction` 列舉（比照既有 `DualPageMode` 巢狀型別慣例）與 `navZoneActions: List<ZoneAction>` 欄位（由 `buildPreferencesFromMap()` 解析 Dart 端送來的 `navZoneActions` 字串陣列更新），僅在 `attachNavigator()` 判定 `isFixedLayout == false` 時向 `EpubNavigatorFragment`（實作 Readium `VisualNavigator`）呼叫 `addInputListener()`；`onTap(event)` 回呼內用 `NavZoneHitTester.cellIndex()` 換算 `event.point`（已由 Issue 1 spike 驗證為 `publicationView` 本地座標，與其寬高同一座標系，不需額外轉換）為格子索引，查 `navZoneActions[index]` 後：`previousPage`/`nextPage` 直接呼叫 `navigatorFragment.goBackward()`/`goForward()`（`animated = false`，捲動模式下依 design.md 決策 #15 略過）；`menu` 透過既有 method channel 觸發 `onZoneTapped({"cellIndex": index})` 回呼給 Dart；`none` 不做事、不通知 Dart。

Dart 端 `EpubReaderView` 新增建構參數 `onZoneTapped: ValueChanged<int>?`（接收原生端的 `onZoneTapped` 回呼），並把既有的 `navZoneActions` 欄位（Issue 4/5 已存在，目前只用於 Dart 端 FXL 疊加層渲染，從未送到原生端）納入 `_buildPreferencesMap()`/`_preferencesChanged()`，讓它跟其餘偏好參數一樣在 `openBook`/`setPreferences` 時送到原生端——這是 FXL（Issue 5）沒有做、但流式熱區（本 issue）必須做的新接線，因為 FXL 的熱區判讀完全在 Dart 端進行，從不需要原生端知道 `navZoneActions` 內容。`ReaderScreen._buildNativeView()` 的 EPUB 分支接上 `onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index])`（`_handleZoneAction` 已由 Issue 4/5 建立，本 issue 不新增分支，只新增這一條呼叫路徑，複用既有的 `menu` 分支）。

**Tech Stack:** Kotlin（`EpubReaderView.kt`、新檔 `NavZoneHitTester.kt`）、Readium `kotlin-toolkit` 3.3.0（`org.readium.r2.navigator.input.InputListener`/`TapEvent`、`VisualNavigator.addInputListener()`/`removeInputListener()`——API 簽章已由 Issue 1 以 `javap -p` 反編譯 `readium-navigator-3.3.0.aar` 驗證，見 Global Constraints）、JUnit（Kotlin JVM 單元測試，`./gradlew testDebugUnitTest`）、Flutter（`EpubReaderView`/`ReaderScreen` 既有 method channel 模式）、`flutter_test`（widget test）、`integration_test`（真機）。

## Global Constraints

- 格子索引慣例：全文一律 0-indexed、列優先（`0 1 2 / 3 4 5 / 6 7 8`）。
- `hitTestZoneIndex()`/`NavZoneHitTester.cellIndex()` 演算法（Dart／Kotlin 兩端平行實作，須逐位元一致）：`col = clamp(floor(dx/width*3), 0, 2)`、`row = clamp(floor(dy/height*3), 0, 2)`、回傳 `row*3+col`；`width`/`height` 為 0 或負數時直接回傳 4（正中央），避免除以 0。
- Readium API 簽章（Issue 1 已用 `javap -p` 反編譯 `readium-navigator-3.3.0.aar` 逐一驗證，非猜測，見 `plans/plan-issue-1.md` Global Constraints）：`VisualNavigator.addInputListener(InputListener)`/`removeInputListener(InputListener)`/`getPublicationView(): View`（Kotlin 端 `publicationView` 屬性）；`InputListener.onTap(event: TapEvent): Boolean`（有預設實作回傳 `false`）；`TapEvent(val point: PointF)`；`EpubNavigatorFragment` 實作 `OverflowableNavigator extends VisualNavigator`，`navigatorFragment?.addInputListener(...)` 可直接呼叫，不需轉型。
- Issue 1 spike 三項結論（`reviews/spike-epub-inputlistener.md`，本 issue 直接採用，不需要再驗證一次）：(1) `EpubNavigatorFragment` 對純點擊無內建翻頁反應，不需要停用步驟；(2) `InputListener.onTap()` 攔截可靠，`goForward()`/`goBackward()` 呼叫與點擊次數嚴格 1:1，無重複觸發；(3) `TapEvent.point` 為 `publicationView` 本地座標（與其寬高同一座標系，無 letterbox），`NavZoneHitTester.cellIndex()` 不需額外轉換公式。
- design.md 決策 #15：EPUB 流式捲動翻頁模式（`pageTurnMode == scroll`，即 `EpubPreferences.scroll == true`）下，左右熱區（`previousPage`/`nextPage`）失效（略過、不呼叫 `goBackward()`/`goForward()`）；中間選單格仍可切換沉浸模式，不受影響。
- 原生 Method Channel 契約異動（`spec.md`「介面」節）：EPUB 頻道 `openBook`/`setPreferences` 的偏好 Map 新增 `navZoneActions: List<String>`（9 個 `ZoneAction.name`，一律非 null）；新增原生→Dart 回呼 `onZoneTapped`：`{ "cellIndex": Int }`，僅在該格解析結果為 `menu` 時觸發。
- 本 issue 完全不涉及 EPUB FXL（`isFixedLayout == true`）路徑——FXL 熱區已由 Issue 5 以 Dart 端 `GestureDetector` 疊加層完成，兩條路徑互斥（原生端僅在 `isFixedLayout == false` 時註冊 `InputListener`）。`PdfReaderView.kt` 本 issue不涉及（PDF 熱區完全在 Dart 端處理，見 Issue 4）。
- 已知測試限制（`spec.md`「測試決策」）：`InputListener.onTap()` 實際換頁效果無法透過 `flutter test`／JVM 單元測試驗證（需要真實 Android Fragment/View），只有 `NavZoneHitTester.cellIndex()` 這個純函式部分可 JVM 測試，其餘原生分派邏輯的正確性留給 `integration_test`（Task 5）。
- `flutter analyze` 全程須保持乾淨；套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/...`）；JVM 測試指令：於 `app/android` 目錄執行 `./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.<ClassName>"`（若 `./gradlew` 不存在，先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/NavZoneHitTester.kt` | 新增 | 純 Kotlin 座標→格子索引換算，JVM 可測 |
| `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/NavZoneHitTesterTest.kt` | 新增 | `NavZoneHitTester.cellIndex()` 邊界值測試，與 Dart 端 `zone_hit_test_test.dart` 案例一一對應 |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` | 修改 | 新增巢狀 `ZoneAction` 列舉、`navZoneActions`/`navInputListener` 欄位、`buildPreferencesFromMap()` 解析、`attachNavigator()` 內註冊 `InputListener`、`dispose()` 內釋放 |
| `app/lib/reader/epub_reader_view.dart` | 修改 | 新增 `onZoneTapped` 建構參數；`navZoneActions` 納入 `_buildPreferencesMap()`/`_preferencesChanged()`；`_handleMethodCall()` 新增 `onZoneTapped` case |
| `app/test/reader/epub_reader_view_test.dart` | 修改 | 更新 3 個既有 exact-match 偏好 Map 測試；新增 `navZoneActions` 變動觸發 `setPreferences`、`onZoneTapped` 回呼兩個測試 |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` EPUB 分支接上 `onZoneTapped`；更新 `_handleZoneAction()` 過時文件註解 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增流式 EPUB `onZoneTapped` 觸發沉浸模式切換測試 |
| `app/integration_test/epub_stream_nav_zone_test.dart` | 新增 | 真機驗證：熱區換頁、選單觸發、捲動模式左右熱區失效 |

---

### Task 1：`NavZoneHitTester.kt` — 純 Kotlin 熱區座標換算 + JVM 單元測試

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/NavZoneHitTester.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/NavZoneHitTesterTest.kt`

**Interfaces:**
- Consumes：無（純函式，無外部依賴）
- Produces：`NavZoneHitTester.cellIndex(dx: Float, dy: Float, width: Float, height: Float): Int`——供 Task 3 的 `EpubReaderView.kt` `InputListener.onTap()` 呼叫

- [ ] **Step 1：寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/NavZoneHitTesterTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 與 app/test/reader/zone_hit_test_test.dart 的 hitTestZoneIndex() 測試案例
 * 一一對應（spec.md 要求兩端演算法輸出一致，見該檔案測試案例）。
 */
class NavZoneHitTesterTest {

    private val width = 300f
    private val height = 300f

    @Test
    fun `左上角 (0,0) 回傳格子 0`() {
        assertEquals(0, NavZoneHitTester.cellIndex(0f, 0f, width, height))
    }

    @Test
    fun `正中心回傳格子 4`() {
        assertEquals(4, NavZoneHitTester.cellIndex(150f, 150f, width, height))
    }

    @Test
    fun `右上角（寬度邊界內）回傳格子 2`() {
        assertEquals(2, NavZoneHitTester.cellIndex(299f, 0f, width, height))
    }

    @Test
    fun `左下角（高度邊界內）回傳格子 6`() {
        assertEquals(6, NavZoneHitTester.cellIndex(0f, 299f, width, height))
    }

    @Test
    fun `右下角（寬高邊界內）回傳格子 8`() {
        assertEquals(8, NavZoneHitTester.cellIndex(299f, 299f, width, height))
    }

    @Test
    fun `dx 恰好等於 width（浮點邊界）仍 clamp 在格子 2，不產生 index 9`() {
        assertEquals(2, NavZoneHitTester.cellIndex(300f, 0f, width, height))
    }

    @Test
    fun `dy 恰好等於 height（浮點邊界）仍 clamp 在格子 6，不產生超界`() {
        assertEquals(6, NavZoneHitTester.cellIndex(0f, 300f, width, height))
    }

    @Test
    fun `第一條格線正上方座標 (dx=100) 歸屬 col 1`() {
        assertEquals(4, NavZoneHitTester.cellIndex(100f, 150f, width, height))
    }

    @Test
    fun `第二條格線正上方座標 (dx=200) 歸屬 col 2`() {
        assertEquals(5, NavZoneHitTester.cellIndex(200f, 150f, width, height))
    }

    @Test
    fun `width 或 height 為 0 或負數時，安全回傳格子 4，不拋出例外`() {
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 0f, 300f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 300f, 0f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, -1f, 300f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 300f, -1f))
    }
}
```

- [ ] **Step 2：執行測試確認失敗**

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.NavZoneHitTesterTest"
```

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: NavZoneHitTester`（若 `./gradlew` 不存在，先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生 `app/android/gradlew`）。

- [ ] **Step 3：實作**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/NavZoneHitTester.kt`：

```kotlin
package cc.ugotit.elinkbook

import kotlin.math.floor

/**
 * 依點擊座標換算 3×3 導航熱區的格子索引（0-8，列優先，見
 * docs/epics/epic-7-interaction/spec.md「格子索引慣例」）。與 Dart 端
 * `hitTestZoneIndex()`（app/lib/reader/zone_hit_test.dart）平行實作相同演算法
 * ——供 EPUB 流式（`isFixedLayout == false`）路徑的原生 `InputListener.onTap()`
 * 使用；PDF／EPUB FXL 兩條 Flutter 端手勢路徑已各自在 Dart 端處理，不使用本
 * 物件。純 Kotlin、不依賴任何 Android 型別，可在 JVM 單元測試（app/src/test）
 * 直接驗證，比照 `EpubFxlScaler`／`PdfImageProcessor` 既有抽離慣例。
 */
object NavZoneHitTester {

    /**
     * [dx]/[dy] 為點擊座標（像素，相對容器左上角），[width]/[height] 為容器
     * 尺寸（像素）。回傳值以 `coerceIn` 保證落在 0-8，不因浮點誤差在邊界產生
     * 超界索引。[width]/[height] 為 0 或負數時直接回傳格子 4（正中央），比照
     * Dart 端 `hitTestZoneIndex()` 的邊界防護（避免除以 0 產生 `NaN`/
     * `Infinity`）。
     */
    fun cellIndex(dx: Float, dy: Float, width: Float, height: Float): Int {
        if (width <= 0f || height <= 0f) return 4
        val col = floor((dx / width) * 3).toInt().coerceIn(0, 2)
        val row = floor((dy / height) * 3).toInt().coerceIn(0, 2)
        return row * 3 + col
    }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.NavZoneHitTesterTest"
```

Expected：`BUILD SUCCESSFUL`，10 個測試皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/NavZoneHitTester.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/NavZoneHitTesterTest.kt
git commit -m "feat(epic-7): add NavZoneHitTester for streaming EPUB nav zone cell lookup"
```

---

### Task 2：`EpubReaderView.dart` — 熱區設定送達原生端 + `onZoneTapped` 回呼接收

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`
- Test: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes：`ZoneAction`（epic-7 Issue 2）
- Produces：`EpubReaderView` 新增建構參數 `ValueChanged<int>? onZoneTapped`；既有 `navZoneActions` 欄位開始送到原生端（`_buildPreferencesMap()`/`_preferencesChanged()`）——供 Task 4 的 `ReaderScreen` 接線

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/epub_reader_view_test.dart`，第 78-91 行（`_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含所有非 null 建構參數`），原本：

```dart
    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], {
      'writingMode': 'vertical',
      'pageTurnMode': 'scroll',
      'fontFamily': 'SourceHanSansTC',
      'fontSize': 1.125,
      'fontWeight': 1.75,
      'lineHeight': 1.6,
      'paragraphSpacing': 1.2,
      'pageMargins': 1.3333,
      'textAlign': 'justify',
      'publisherStyles': false,
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });
```

改為：

```dart
    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], {
      'writingMode': 'vertical',
      'pageTurnMode': 'scroll',
      'fontFamily': 'SourceHanSansTC',
      'fontSize': 1.125,
      'fontWeight': 1.75,
      'lineHeight': 1.6,
      'paragraphSpacing': 1.2,
      'pageMargins': 1.3333,
      'textAlign': 'justify',
      'publisherStyles': false,
      'dualPageMode': 'auto',
      'isLandscape': false,
      'navZoneActions': List.filled(9, 'none'),
    });
  });
```

第 94-110 行（`所有偏好欄位皆為 null 時，initialPreferences 只含 dualPageMode/isLandscape`），原本：

```dart
  testWidgets('所有偏好欄位皆為 null 時，initialPreferences 只含 dualPageMode/isLandscape',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });
```

改為（測試名稱與斷言同步更新，反映 `navZoneActions` 現在也一律出現）：

```dart
  testWidgets(
      '所有偏好欄位皆為 null 時，initialPreferences 只含 dualPageMode/isLandscape/navZoneActions',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'auto',
      'isLandscape': false,
      'navZoneActions': List.filled(9, 'none'),
    });
  });
```

第 157-164 行（`任一偏好欄位變動時，didUpdateWidget 呼叫 setPreferences 並帶入目前所有非 null 欄位`），原本：

```dart
    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments, {
      'fontSize': 1.25,
      'writingMode': 'vertical',
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });
```

改為：

```dart
    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments, {
      'fontSize': 1.25,
      'writingMode': 'vertical',
      'dualPageMode': 'auto',
      'isLandscape': false,
      'navZoneActions': List.filled(9, 'none'),
    });
  });
```

在檔案末尾（`}` 結束 `main()` 之前，`setDecorations 呼叫原生端時正確序列化 EpubDecoration 清單` 測試之後）新增 2 個測試：

```dart

  testWidgets(
      'navZoneActions 變動時，didUpdateWidget 呼叫 setPreferences 並帶入新的動作陣列',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
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
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments['navZoneActions'], [
      'previousPage', 'menu', 'nextPage',
      'previousPage', 'menu', 'nextPage',
      'previousPage', 'menu', 'nextPage',
    ]);
  });

  testWidgets('收到原生端 onZoneTapped 事件時，傳回 cellIndex 整數', (tester) async {
    int? tappedIndex;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onZoneTapped: (index) => tappedIndex = index,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(
      const MethodCall('onZoneTapped', {'cellIndex': 4}),
    );
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(tappedIndex, 4);
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/epub_reader_view_test.dart
```

Expected：FAIL（既有 3 個測試因 `initialPreferences`/`setPreferences` 的 Map 缺少 `navZoneActions` 鍵而斷言不符；新增的 2 個測試因 `onZoneTapped` 具名參數不存在而編譯失敗）。

- [ ] **Step 3：實作**

`app/lib/reader/epub_reader_view.dart` 頂部 import 區塊，原本：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
```

改為：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
```

欄位宣告區塊，原本（`showNavZoneDebugOverlay` 欄位之後、`totalCharacterCount` 欄位之前）：

```dart
  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供使用者於設定畫面
  /// 開啟除錯用途（epic-7-interaction Issue 2/3 `showNavZoneDebugOverlay`）。
  final bool showNavZoneDebugOverlay;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3）。
```

改為：

```dart
  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供使用者於設定畫面
  /// 開啟除錯用途（epic-7-interaction Issue 2/3 `showNavZoneDebugOverlay`）。
  final bool showNavZoneDebugOverlay;

  /// 僅流式 EPUB（`_isFixedLayout == false`）路徑觸發：原生端
  /// `InputListener.onTap()` 判讀出熱區動作為 [ZoneAction.menu] 時，透過
  /// method channel 回呼傳回該格索引（0-8，見 `zone_hit_test.dart` 索引
  /// 慣例），呼叫端（`ReaderScreen`）負責分派實際行為（epic-7-interaction
  /// Issue 6）。`previousPage`/`nextPage`/`none` 三種動作完全由原生端自主
  /// 處理（呼叫 Readium `goForward()`/`goBackward()` 或不做事），不會觸發
  /// 這個回呼——與 FXL 路徑的 [onZoneAction] 互斥，兩者不會同時被呼叫。
  final ValueChanged<int>? onZoneTapped;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3）。
```

建構子具名參數區塊，原本：

```dart
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.totalCharacterCount,
```

改為：

```dart
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.onZoneTapped,
    this.totalCharacterCount,
```

`_preferencesChanged()`，原本：

```dart
  bool _preferencesChanged(EpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.isLandscape != oldWidget.isLandscape;
  }
```

改為：

```dart
  bool _preferencesChanged(EpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.isLandscape != oldWidget.isLandscape ||
        !listEquals(widget.navZoneActions, oldWidget.navZoneActions);
  }
```

`_buildPreferencesMap()`，原本結尾：

```dart
    map['dualPageMode'] = widget.dualPageMode.name;
    map['isLandscape'] = widget.isLandscape;
    return map;
  }
```

改為：

```dart
    map['dualPageMode'] = widget.dualPageMode.name;
    map['isLandscape'] = widget.isLandscape;
    map['navZoneActions'] =
        widget.navZoneActions.map((action) => action.name).toList();
    return map;
  }
```

`_handleMethodCall()`，原本結尾：

```dart
      case 'onAnnotationActivated':
        widget.onAnnotationActivated?.call(call.arguments as String);
        break;
    }
  }
```

改為：

```dart
      case 'onAnnotationActivated':
        widget.onAnnotationActivated?.call(call.arguments as String);
        break;
      case 'onZoneTapped':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onZoneTapped?.call(args['cellIndex'] as int);
        break;
    }
  }
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/epub_reader_view_test.dart
```

Expected：PASS（含 3 個改寫測試與 2 個新增測試，以及全部既有測試，證明 `navZoneActions` 新增進偏好 Map 沒有影響其餘欄位序列化邏輯）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-7): send navZoneActions to native EpubReaderView, add onZoneTapped callback"
```

---

### Task 3：`EpubReaderView.kt` — 原生 `InputListener` 熱區分派邏輯

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes：`NavZoneHitTester.cellIndex()`（Task 1）；Dart 端透過 `openBook`/`setPreferences` 送來的 `navZoneActions: List<String>`（Task 2）
- Produces：僅流式（`isFixedLayout == false`）路徑註冊的 `InputListener`，`menu` 動作透過既有 `channel` 觸發 `onZoneTapped({"cellIndex": Int})` 回呼給 Dart（Task 2 已能接收）

本 Task 無自動化測試（原生 `InputListener` 分派邏輯需要真實 Android Fragment/View，無法在 JVM 單元測試驗證，見 Global Constraints「已知測試限制」），改以編譯驗證作為本 Task 的完成判準，實際換頁/選單行為由 Task 5 `integration_test` 真機驗證。

- [ ] **Step 1：新增 `InputListener`／`TapEvent` import**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，原本（第 43-44 行）：

```kotlin
import org.readium.r2.navigator.util.BaseActionModeCallback
import org.readium.r2.shared.publication.Layout
```

改為：

```kotlin
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.util.BaseActionModeCallback
import org.readium.r2.shared.publication.Layout
```

- [ ] **Step 2：新增巢狀 `ZoneAction` 列舉**

原本（`DualPageMode` 巢狀列舉結束、`companion object` 開始之間，第 111-123 行）：

```kotlin
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    companion object {
```

改為：

```kotlin
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    /**
     * 3×3 導航熱區動作（epic-7-interaction design.md 決策 #8），對應 Dart
     * `ZoneAction` 列舉（app/lib/reader/zone_action.dart）透過 Method Channel
     * 傳來的 `.name` 字串（'previousPage'/'nextPage'/'menu'/'none'）。與
     * [DualPageMode] 是各自獨立的巢狀型別，比照既有慣例。
     */
    internal enum class ZoneAction {
        PREVIOUS_PAGE, NEXT_PAGE, MENU, NONE;

        companion object {
            fun fromWireValue(value: String?): ZoneAction = when (value) {
                "previousPage" -> PREVIOUS_PAGE
                "nextPage" -> NEXT_PAGE
                "menu" -> MENU
                else -> NONE
            }
        }
    }

    companion object {
```

- [ ] **Step 3：新增 `navZoneActions`／`navInputListener` 欄位**

原本（`isLandscape` 欄位之後、`decorationListener` 欄位之前）：

```kotlin
    /** 裝置是否為橫向，由 [applyDualPagePreferences] 更新。 */
    private var isLandscape: Boolean = false

    /** 標記點擊監聽器，dispose() 時需要用同一個實例呼叫
     * removeDecorationListener，故保留參照（見 Decoration.kt
     * addDecorationListener／removeDecorationListener 簽章）。*/
    private var decorationListener: DecorableNavigator.Listener? = null
```

改為：

```kotlin
    /** 裝置是否為橫向，由 [applyDualPagePreferences] 更新。 */
    private var isLandscape: Boolean = false

    /**
     * 3×3 導航熱區動作對照表（epic-7-interaction Issue 6），由
     * [buildPreferencesFromMap] 解析 Dart 端送來的 `navZoneActions` 字串陣列
     * 更新此欄位，供僅流式（`isFixedLayout == false`）路徑註冊的
     * `InputListener.onTap()` 查表使用。預設全部 [ZoneAction.NONE]——尚未
     * 收到任何偏好設定時的安全預設，不會誤觸發任何動作。
     */
    private var navZoneActions: List<ZoneAction> = List(9) { ZoneAction.NONE }

    /** [attachNavigator] 註冊的熱區點擊監聽器，dispose() 時需要用同一個實例
     * 呼叫 removeInputListener，故保留參照——比照下方 [decorationListener]
     * 既有慣例。僅流式（`isFixedLayout == false`）路徑會賦值。 */
    private var navInputListener: InputListener? = null

    /** 標記點擊監聽器，dispose() 時需要用同一個實例呼叫
     * removeDecorationListener，故保留參照（見 Decoration.kt
     * addDecorationListener／removeDecorationListener 簽章）。*/
    private var decorationListener: DecorableNavigator.Listener? = null
```

- [ ] **Step 4：`buildPreferencesFromMap()` 新增 `navZoneActions` 解析**

原本：

```kotlin
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
```

改為：

```kotlin
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        (map["navZoneActions"] as? List<*>)?.let { raw ->
            navZoneActions = raw.map { ZoneAction.fromWireValue(it as? String) }
        }
        return EpubPreferences(
```

- [ ] **Step 5：`attachNavigator()` 內註冊 `InputListener`**

原本（`initialPreferences` 套用區塊之後、字元數背景計算之前）：

```kotlin
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
            // epic-5-toc-pagination Issue 3：僅在尚無快取值時才觸發背景字元數
            // 計算，之後每次開書直接沿用 Dart 端傳入的快取值，不重新走訪全書
            // （見 spec.md「執行緒與快取」）。
            if (initialTotalCharacterCount == null) {
                computeTotalCharacterCountInBackground(openedPublication)
            }
```

改為：

```kotlin
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
            // epic-7-interaction Issue 6：僅流式（isFixedLayout == false）路徑
            // 註冊熱區點擊監聽器——Issue 1 spike（reviews/spike-epub-inputlistener.md）
            // 已在真機驗證 3 項風險：(1) EpubNavigatorFragment 對純點擊無內建
            // 翻頁反應，不需要停用步驟；(2) onTap() 攔截可靠，goForward()/
            // goBackward() 呼叫與點擊次數嚴格 1:1，無重複觸發；(3) TapEvent.point
            // 為 publicationView 本地座標（與其寬高同一座標系，無 letterbox），
            // NavZoneHitTester.cellIndex() 不需額外轉換。FXL（isFixedLayout ==
            // true）完全不進這個分支，熱區疊加層由 Dart 端 GestureDetector
            // 處理（epic-7-interaction Issue 5）。
            if (openedPublication.metadata.layout != Layout.FIXED) {
                val listener = object : InputListener {
                    override fun onTap(event: TapEvent): Boolean {
                        val view = navigatorFragment?.publicationView ?: return false
                        val index = NavZoneHitTester.cellIndex(
                            dx = event.point.x,
                            dy = event.point.y,
                            width = view.width.toFloat(),
                            height = view.height.toFloat(),
                        )
                        when (navZoneActions.getOrElse(index) { ZoneAction.NONE }) {
                            ZoneAction.PREVIOUS_PAGE -> {
                                // design.md 決策 #15：捲動翻頁模式下左右熱區失效。
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goBackward(animated = false)
                                }
                            }
                            ZoneAction.NEXT_PAGE -> {
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goForward(animated = false)
                                }
                            }
                            ZoneAction.MENU ->
                                channel.invokeMethod("onZoneTapped", mapOf("cellIndex" to index))
                            ZoneAction.NONE -> {}
                        }
                        return true
                    }
                }
                navInputListener = listener
                navigatorFragment?.addInputListener(listener)
            }
            // epic-5-toc-pagination Issue 3：僅在尚無快取值時才觸發背景字元數
            // 計算，之後每次開書直接沿用 Dart 端傳入的快取值，不重新走訪全書
            // （見 spec.md「執行緒與快取」）。
            if (initialTotalCharacterCount == null) {
                computeTotalCharacterCountInBackground(openedPublication)
            }
```

- [ ] **Step 6：`dispose()` 內釋放 `InputListener`**

原本：

```kotlin
    override fun dispose() {
        isDisposed = true
        scope.cancel()
        removeFxlLayoutListener()
        decorationListener?.let { navigatorFragment?.removeDecorationListener(it) }
```

改為：

```kotlin
    override fun dispose() {
        isDisposed = true
        scope.cancel()
        removeFxlLayoutListener()
        decorationListener?.let { navigatorFragment?.removeDecorationListener(it) }
        navInputListener?.let { navigatorFragment?.removeInputListener(it) }
```

- [ ] **Step 7：編譯驗證**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
```

Expected：建置成功，無 Kotlin 編譯錯誤（確認 `InputListener`/`TapEvent` import 路徑正確、`ZoneAction` 巢狀列舉與 `NavZoneHitTester` 呼叫皆型別正確）。

- [ ] **Step 8：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "feat(epic-7): register native InputListener for streaming EPUB nav zone dispatch"
```

---

### Task 4：`ReaderScreen` — 串接 `onZoneTapped`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`EpubReaderView.onZoneTapped`（Task 2）、既有 `_handleZoneAction`（Issue 4/5）、`ResolvedPreferences.navZoneActions`（Issue 2）
- Produces：無新增對外介面，`_buildNativeView()` 的 `EpubReaderView(...)` 建構多接一個具名參數

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart`，緊接在既有的 `'PDF：真實點擊熱區「選單」格（index 1）觸發沉浸模式切換'` 測試之後（檔案結尾 `}` 之前）新增：

```dart

  testWidgets('EPUB 流式：原生端 onZoneTapped 回呼（cellIndex=1）觸發沉浸模式切換',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
    // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。EPUB 流式的
    // previousPage/nextPage/none 完全由原生端 InputListener 自行處理、不通知
    // Dart（見 EpubReaderView.kt），只有 menu 動作會透過
    // onZoneTapped(cellIndex) 回呼給 Dart——這裡直接呼叫該回呼模擬原生端已
    // 完成熱區判讀後的通知，驗證 ReaderScreen 接線到 _handleZoneAction 的
    // 部分（不涉及原生 InputListener 本身是否正確攔截點擊，那部分由
    // integration_test 真機驗證，見 plan-issue-6.md Task 5）。
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onZoneTapped?.call(1);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
  });
}
```

（注意：新增的測試取代原本檔案結尾的單一 `}`——上面程式碼區塊末尾的 `}` 就是 `main()` 的收尾，貼上時不要重複兩個 `}`。）

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL（`view.onZoneTapped` 因 `EpubReaderView` 尚未建構此參數而編譯失敗，或編譯通過但因 `_buildNativeView()` 尚未接線而 `onZoneTapped` 恆為 `null`，呼叫 `?.call(1)` 無效果，`AppBar` 斷言失敗）。

- [ ] **Step 3：實作**

`app/lib/screens/reader_screen.dart` 的 `_buildNativeView()` 方法，`case BookFormat.epub:` 分支，原本：

```dart
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          initialLocatorJson: _initialPosition?.epubLocatorJson,
```

改為：

```dart
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index]),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
```

`_handleZoneAction()` 方法的文件註解（過時，Issue 5 已完成但註解仍稱「目前只實作 PDF 換頁分支」），原本：

```dart
  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支）：`previousPage`/`nextPage` 呼叫目前格式對應的既有換頁方法；
  /// `menu` 切換 [_chromeVisible]（沉浸模式）；`none` 不做事。
  /// **`previousPage`/`nextPage` 刻意不影響 [_chromeVisible]**（design.md
  /// 決策 #14）。EPUB 分支只在 FXL（`EpubReaderView` 僅 `_isFixedLayout ==
  /// true` 時才疊加熱區、才會回呼 `onZoneAction`）生效——EPUB 流式的
  /// previousPage/nextPage 完全不經過這裡（原生 Kotlin `InputListener`
  /// 自主處理，只有 `menu` 動作經 Issue 6 的 `onZoneTapped` 回呼）。
```

改為：

```dart
  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支，Issue 6 接上流式 EPUB 的 `menu` 動作）：`previousPage`/
  /// `nextPage` 呼叫目前格式對應的既有換頁方法；`menu` 切換 [_chromeVisible]
  /// （沉浸模式）；`none` 不做事。**`previousPage`/`nextPage` 刻意不影響
  /// [_chromeVisible]**（design.md 決策 #14）。EPUB 分支的 `previousPage`/
  /// `nextPage` 只在 FXL（`EpubReaderView` 僅 `_isFixedLayout == true` 時才
  /// 疊加熱區、才會回呼 `onZoneAction`）生效——EPUB 流式的 `previousPage`/
  /// `nextPage` 完全不經過這裡（原生 Kotlin `InputListener` 自主呼叫
  /// `goBackward()`/`goForward()`），只有 `menu` 動作經下方
  /// `_buildNativeView()` 接上的 `onZoneTapped` 回呼觸發這裡的 `menu` 分支。
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（含新增測試，以及全部既有測試，證明新增的具名參數與註解更新沒有影響其餘 PDF／FXL 熱區與其他既有行為）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-7): wire EpubReaderView onZoneTapped into ReaderScreen for streaming EPUB"
```

---

### Task 5：真機驗證——`integration_test`

**Files:**
- Create: `app/integration_test/epub_stream_nav_zone_test.dart`

**Interfaces:**
- Consumes：`EpubReaderView`（Task 2/3）
- Produces：無（驗證性質工單）；若自動化 `tester.tapAt()` 於真機不可靠，本檔案標頭記錄的人工驗證清單作為替代驗收依據

- [ ] **Step 1：撰寫測試檔**

建立 `app/integration_test/epub_stream_nav_zone_test.dart`：

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
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 7 Issue 6：EPUB 流式熱區導覽（原生 InputListener）——真機整合測試。
///
/// 【本檔案與 PDF（epic-7-interaction Issue 4，pdf_nav_zone_test.dart）的
/// 差異】PDF 熱區疊加層曾經包住 AndroidView 的 GestureDetector，因 Flutter
/// 手勢競技場「先加入者贏」的仲裁規則導致 onTapUp 永遠不會觸發（見
/// issues.md Issue 4），該檔案因此完全放棄 tester.tap 模擬、改用
/// ReaderScreen.triggerZoneAction 繞開手勢模擬，實際熱區點擊改交由人工
/// 驗證。流式 EPUB 熱區完全由原生 Kotlin InputListener 處理（見
/// EpubReaderView.kt），Flutter 端沒有任何 GestureDetector 包住 AndroidView，
/// 不會遇到 PDF 那種特定的手勢競技場仲裁問題，因此本檔案改為直接嘗試
/// tester.tapAt() 對 AndroidView 所在螢幕座標送出真實觸控事件，觀察是否能
/// 觸達原生 InputListener（Issue 1 spike 已用 `adb shell input tap` 這種
/// OS 層級的觸控注入方式驗證過 InputListener 本身可靠攔截，但 Flutter
/// `tester.tapAt()` 屬於測試框架層級的觸控合成，是否對 Hybrid Composition
/// 下的 AndroidView 同樣可靠並未事先驗證，須靠本檔案的真機執行結果確認）。
///
/// 【若 tester.tapAt() 證實不可靠，改用以下人工驗證清單】比照
/// pdf_nav_zone_test.dart 既有先例，若下方任一測試在真機執行時斷言失敗
/// （locatorJson 未變動／onZoneTapped 未觸發），改用 Issue 1 spike 已驗證
/// 可靠的 `adb shell input tap <x> <y>` 直接對真機螢幕座標注入觸控（座標
/// 算法：畫面左 1/6 處＝上一頁、正中央＝選單、右 5/6 處＝下一頁，y 任取
/// 畫面垂直中點即可，見 reviews/spike-epub-inputlistener.md 座標換算方式），
/// 人工確認：
///   1. 依序點擊左/中/右三個位置，確認換頁與沉浸模式切換行為與
///      navZoneActions（本檔案採用預設 rightFlip 模板）一致。
///   2. 捲動翻頁模式（pageTurnMode=scroll）下，左右熱區點擊不應換頁，
///      中間選單熱區仍可正常觸發。
/// 並記錄實際觀察結果於 issues.md Issue 6 段落，比照 issues.md Issue 4
/// 「待辦」記錄慣例，不阻塞本 issue 合併。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '流式 EPUB 開書後，點擊左/右熱區真的換頁，點擊中間熱區觸發 onZoneTapped',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_stream_nav_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedZoneTaps = <int>[];
    EpubPositionInfo? lastPosition;

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
          onLocatorChanged: (info) => lastPosition = info,
          // rightFlip 模板：左欄＝上一頁、中欄＝選單、右欄＝下一頁
          // （design.md 決策 #5），逐列重複 3 次填滿 9 格。
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneTapped: capturedZoneTaps.add,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final topLeft = tester.getTopLeft(find.byType(EpubReaderView));
    final size = tester.getSize(find.byType(EpubReaderView));
    final rightZone = topLeft + Offset(size.width * 5 / 6, size.height / 2);
    final leftZone = topLeft + Offset(size.width / 6, size.height / 2);
    final menuZone = topLeft + Offset(size.width / 2, size.height / 2);

    final positionAfterOpen = lastPosition;

    await tester.tapAt(rightZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(
      lastPosition?.locatorJson,
      isNot(equals(positionAfterOpen?.locatorJson)),
      reason: '點擊右側熱區應透過原生 InputListener 觸發 goForward()，'
          'locatorJson 應變動；若本斷言失敗，代表 tester.tapAt() 對此原生 '
          'InputListener 路徑不可靠，需改依本檔案標頭註解的人工驗證清單改用 '
          'adb shell input tap 驗證，並記錄實際觀察結果於 issues.md。',
    );

    final positionAfterNext = lastPosition;

    await tester.tapAt(leftZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊上一頁熱區後不應觸發 onError');
    expect(
      lastPosition?.locatorJson,
      isNot(equals(positionAfterNext?.locatorJson)),
      reason: '點擊左側熱區應觸發 goBackward()，locatorJson 應變動',
    );

    await tester.tapAt(menuZone);
    await tester.pump();
    expect(
      capturedZoneTaps,
      contains(1),
      reason: '點擊中間熱區（index 1，選單）應透過 onZoneTapped(cellIndex: 1) '
          '回呼通知 Dart 端',
    );
  });

  testWidgets(
      '捲動翻頁模式（pageTurnMode=scroll）下，左右熱區失效但選單格仍可用'
      '（design.md 決策 #15）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub',
        'epub_stream_nav_zone_scroll.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedZoneTaps = <int>[];
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          pageTurnMode: PageTurnMode.scroll,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) => lastPosition = info,
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneTapped: capturedZoneTaps.add,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final topLeft = tester.getTopLeft(find.byType(EpubReaderView));
    final size = tester.getSize(find.byType(EpubReaderView));
    final rightZone = topLeft + Offset(size.width * 5 / 6, size.height / 2);
    final menuZone = topLeft + Offset(size.width / 2, size.height / 2);

    final positionAfterOpen = lastPosition;

    await tester.tapAt(rightZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '捲動模式下點擊右側熱區不應觸發 onError');
    expect(
      lastPosition?.locatorJson,
      equals(positionAfterOpen?.locatorJson),
      reason: '捲動翻頁模式下右側熱區（下一頁）應失效，locatorJson 不應變動'
          '（design.md 決策 #15）',
    );

    await tester.tapAt(menuZone);
    await tester.pump();
    expect(
      capturedZoneTaps,
      contains(1),
      reason: '捲動模式下選單格仍應正常觸發 onZoneTapped（design.md 決策 #15）',
    );
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
flutter test integration_test/epub_stream_nav_zone_test.dart -d <device-id>
```

（若執行環境確認僅連接一台裝置，`-d <device-id>` 參數可省略。）

Expected：兩個測試 PASS。若 `locatorJson`/`onZoneTapped` 相關斷言失敗，依檔案標頭註解記錄的人工驗證清單，改用 `adb shell input tap` 對真機螢幕座標實測，並在下方 Step 4 記錄實際觀察到的行為（是自動化斷言失敗但人工驗證通過，或原生分派邏輯本身有問題）。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/epub_stream_nav_zone_test.dart
git commit -m "test(epic-7): add streaming EPUB nav zone integration test"
```

---

### Task 6：全域驗證與收尾

**Files:** 無異動（本 Task 僅執行驗證指令，不修改任何檔案）

**Interfaces:**
- Consumes：Task 1-5 全部產出
- Produces：驗收證據（`flutter analyze`/`flutter test`/`gradlew testDebugUnitTest` 輸出），供人類判斷本 issue 是否可合併

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

Expected：全數 PASS，含 Task 2、4 改寫/新增的測試。基準為 531 個既有測試（epic-7 Issue 5 完成時的計數），本 issue 淨增加：`epub_reader_view_test.dart` 新增 2 個測試（既有 3 個測試改寫不變更數量），`reader_screen_test.dart` 新增 1 個測試，預期總數 531 + 2 + 1 = 534。

- [ ] **Step 3：`gradlew testDebugUnitTest` 執行原生 JVM 單元測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app/android"
./gradlew testDebugUnitTest
```

Expected：`BUILD SUCCESSFUL`，含 Task 1 新增的 `NavZoneHitTesterTest`（10 個測試）與既有 `EpubFxlScalerTest`/`PdfImageProcessorTest` 等既有 JVM 測試全數通過。

- [ ] **Step 4：確認 `git status` 乾淨（無未提交變更）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無輸出（Task 1-5 皆已個別 commit）。

（本 Task 不修改任何檔案，無需 commit。）

---

## Self-Review 摘要

- **Spec coverage**：`issues.md` Issue 6 描述的三處模組異動——`EpubReaderView.kt`（`buildPreferencesFromMap()` 解析、`NavZoneHitTester`、`InputListener` 註冊與分派）對應 Task 1/3；`EpubReaderView.dart` 新增 `onZoneTapped`（含既有 `navZoneActions` 首次送到原生端）對應 Task 2；`ReaderScreen` 接上 `onZoneTapped` 對應 Task 4——逐一有對應 Task。`spec.md`「待驗證風險與收斂關卡」三項已由 Issue 1 spike 收斂，本計劃 Task 3 直接依 spike 結論實作，不再重複驗證。design.md 決策 #15（捲動模式左右熱區失效）由 Task 3 Step 5 的 `currentPreferences.scroll != true` 判斷式與 Task 5 第二個測試共同驗證；原生 method channel 契約異動（`navZoneActions` 送出、`onZoneTapped: {"cellIndex": Int}` 回呼）由 Task 2/3 對應實作，Task 2 新增測試驗證兩個方向的序列化格式。`spec.md`「測試決策」第 2 項（JVM 單元測試，兩端演算法一致）由 Task 1 涵蓋；「已知測試限制」（`InputListener.onTap()` 無法自動化驗證換頁效果）由 Task 3 明確不寫自動化測試、改依 Task 5 `integration_test` 涵蓋。
- **Placeholder scan**：所有 Task 的程式碼區塊皆為完整可執行內容，無 TBD/待補；Task 5 對「`tester.tapAt()` 若不可靠」的情境已給出具體替代方案（`adb shell input tap` 人工驗證清單，附具體座標算法與驗證項目），非模糊的「視情況處理」，也非要求執行者自行發明退回方案。
- **Type consistency**：`ZoneAction`（Dart `zone_action.dart` 列舉 vs Kotlin `EpubReaderView.ZoneAction` 巢狀列舉）之間以 `.name` 字串／`fromWireValue()` 雙向轉換，`previousPage`/`nextPage`/`menu`/`none` 四個字串值在 Dart 序列化（`_buildPreferencesMap()`）與 Kotlin 解析（`ZoneAction.fromWireValue()`）兩端逐字一致；`onZoneTapped: ValueChanged<int>?`（Dart）與 `channel.invokeMethod("onZoneTapped", mapOf("cellIndex" to index))`（Kotlin）的 payload 格式 `{"cellIndex": Int}` 在 Task 2 Step 3（`_handleMethodCall` 解析 `args['cellIndex'] as int`）與 Task 3 Step 5 兩端一致，並與 `spec.md`「原生 Method Channel 契約異動」逐字相符；`NavZoneHitTester.cellIndex()`（Kotlin）與既有 `hitTestZoneIndex()`（Dart）的參數順序、`coerceIn`/`clamp` 邊界防護、`width`/`height` ≤0 時回傳格子 4 的行為完全對應，Task 1 測試案例與既有 `zone_hit_test_test.dart` 逐條對應。
