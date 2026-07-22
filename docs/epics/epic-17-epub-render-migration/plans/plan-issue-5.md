# Epic 17 Issue 5 — 換頁與 3×3 導航熱區 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `FoliateEpubReaderView`（Issue 3/4 已建置，目前只能開書＋套用版面偏好）支援強型別的 `nextPage`/`previousPage`/`jumpToProgression` 換頁 API，並疊加與既有 `EpubReaderView` FXL 分支逐位元組相同的 3×3 導航熱區，讓 `ReaderScreen` 對流式（reflowable）EPUB 的翻頁/沉浸模式切換行為與 FXL、PDF 完全一致。

**Architecture:** 原生端 `FoliateEpubReaderView.kt` 新增三個 method channel case（`nextPage`／`previousPage`／`jumpToProgression`），透過 `webView.evaluateJavascript()` 呼叫 `main.js` 新增的 `window.nextPage()`/`window.previousPage()`/`window.jumpToFraction()` 全域橋接函式（比照既有 `window.applyPreferences` 慣例——`main.js` 的 `view` 是 `<script type="module">` 內的模組作用域 `const`，`evaluateJavascript` 只能呼叫掛在 `window` 上的函式），底層分別呼叫 `readest/foliate-js` 既有 API `view.next()`/`view.prev()`/`view.goToFraction(fraction)`（已查證 `view.js` 原始碼確認存在）。Dart 端 `foliate_epub_reader_view.dart` 新增三個對稱既有 `EpubReaderView` 的強型別 static helper，並在 `build()` 內新增 3×3 `Stack` 疊加層——**不在原生端判讀**，直接複用 `EpubReaderView` FXL 分支既有的「9 個獨立 `GestureDetector`、格子索引由排版位置直接決定」模式（見 `spec.md`「介面」節），`FoliateEpubReaderView.kt` 完全不需要移植 `NavZoneHitTester`/`InputListener`。`ReaderScreen._buildNativeView()` 的 Foliate 分支傳入 `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay`，`_handleZoneAction()` 依既有 `_dispatchedIsFixedLayout` 旗標分派到 `EpubReaderView`（FXL）或 `FoliateEpubReaderView`（流式）對應的 static helper。

**Tech Stack:** Kotlin（`WebView.evaluateJavascript`）、JavaScript（`readest/foliate-js` 既有 `View.next()`/`View.prev()`/`View.goToFraction()`，見 `view.js`）、Dart/Flutter（`GlobalKey<State<T>>` 強型別 static helper、`Stack`/`GestureDetector`）、`flutter_test`（widget test）、`integration_test`（真機驗證）。

## Global Constraints

- **釘定 commit**：`readest/foliate-js` 維持 Issue 3 釘定的 `dd71f2be356563c16a23272686189fcfb45d0b82`，本工單不更新 `app/android/app/src/main/assets/foliate/` 下任何既有 JS 檔案內容，只在 `main.js`（本專案自寫的 production 進入點，非 `readest/foliate-js` 上游檔案）新增橋接函式。
- **Method Channel 契約**（`cc.ugotit.elinkbook/foliate_epub_reader_view_$id`，見 `spec.md`「介面」節，逐一對稱既有 `EpubReaderView` 契約）：`nextPage`／`previousPage` 無參數；`jumpToProgression` 參數 `progression: double`（全書 0.0-1.0）。三者皆為 fire-and-forget（`result.success(null)`），不等待 JS 執行完成。
- **`window.nextPage()`/`window.previousPage()`/`window.jumpToFraction(fraction)` 必須明確掛在 `window` 上**：`main.js` 的 `const view = document.getElementById('view')` 是 ES module 頂層作用域變數，`WebView.evaluateJavascript()` 執行的字串只能存取全域 `window` 屬性，不能直接呼叫模組內的 `view.next()`（比照 Issue 4 已建立的 `window.applyPreferences` 明確橋接慣例，不依賴瀏覽器「帶 `id` 屬性的 DOM 元素自動成為同名全域變數」這種隱性行為）。
- **3×3 導航熱區「不在原生端判讀」**（`spec.md`「介面」節）：`foliate_epub_reader_view.dart` 的 `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數與對應的 `Stack` 疊加層實作，須與 `app/lib/reader/epub_reader_view.dart` 現有 FXL 分支（`_EpubReaderViewState.build()` 內 `if (_isFixedLayout)` 區塊）**逐位元組相同**，唯一差異是本 widget 疊加層恆常顯示（不需要 `_isFixedLayout` 狀態切換，因為這個 widget 只服務流式書籍）。**不**呼叫 `hitTestZoneIndex()`——格子索引由 9 個獨立 `GestureDetector` 在 `Column`/`Row` 陣列中的排列位置直接決定，`hitTestZoneIndex()` 只服務「單一座標回呼換算格子」的場景（原生 Kotlin `InputListener`/PDF 手勢），這裡不適用（見 `epic-7-interaction/spec.md`「介面」節「釐清」段落）。
- **`navZoneActions` 不送給原生端**：與既有 `EpubReaderView`（同時服務 pre-epic-17 遺留的流式-via-Readium 路徑，故需要把 `navZoneActions` 序列化進 `setPreferences` 供 Kotlin `NavZoneHitTester` 使用）不同，`FoliateEpubReaderView` 的 `navZoneActions` 純粹是 Dart 端本地資料，**不**加入 `_buildPreferencesMap()`／`_preferencesChanged()`，`FoliateEpubReaderView.kt` 完全不需要知道這個陣列。
- **`_handleZoneAction()` 的 `previousPage`/`nextPage` 刻意不影響 `_chromeVisible`（沉浸模式）**（`design.md` 決策 #14，既有行為，本工單不變更這條規則本身，只是讓流式 EPUB 也開始真正經過這個分派邏輯）。
- **測試裝置**：沿用既有測試裝置（`3CEF42ECD491687`，Android 15/API 35）；執行前以 `adb devices -l` 重新確認裝置仍在。
- **執行環境**：所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash/MSYS2）執行，非 PowerShell／`cmd.exe`。
- **語言**：新增/修改的程式碼註解一律使用正體中文，比照本檔案既有慣例。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` | 修改 | `onMethodCall` 新增 `nextPage`／`previousPage`／`jumpToProgression` 三個 case |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | 新增 `window.nextPage()`/`window.previousPage()`/`window.jumpToFraction()` 橋接函式 |
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 `nextPage`/`previousPage`/`jumpToProgression` static helper；新增 `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 建構參數與 `Stack` 疊加層 |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改 | 新增 static helper 與熱區疊加層的 widget test |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` Foliate 分支傳入熱區參數；`_handleZoneAction()` 依 `_dispatchedIsFixedLayout` 分派；更新分派邏輯的說明註解 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增流式 EPUB 熱區點擊觸發沉浸模式切換／換頁不影響沉浸模式的 widget test |
| `app/integration_test/foliate_stream_nav_zone_test.dart` | 新增 | 真機驗證：9 格熱區逐一點擊、無動作格攔截觸控、換頁呼叫不觸發 onError |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 5 完成說明 |

---

### Task 1: `FoliateEpubReaderView.kt` + `main.js`——換頁／跳轉橋接

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: 無新的外部依賴。
- Produces: method channel 新增 `nextPage`（無參數）／`previousPage`（無參數）／`jumpToProgression`（`progression: double`）三個 case；`main.js` 新增全域函式 `window.nextPage()`/`window.previousPage()`/`window.jumpToFraction(fraction)`，供 Task 1 的 Kotlin 端 `evaluateJavascript` 呼叫。Task 2 的 Dart static helper 依賴這三個 method 名稱與參數格式（見 Global Constraints）。

**本 Task 無 JVM 單元測試**（比照 Issue 2/3/4 既定退路）：`evaluateJavascript` 呼叫是框架 API 的直接串接，沒有可抽出的純邏輯。驗收標準是 `compileDebugKotlin` 成功 + 既有 93 個 JVM 測試不受影響，實際行為由 Task 5 真機 `integration_test` 驗證。

- [x] **Step 1: `main.js` 新增換頁／跳轉橋接函式**

在 `app/android/app/src/main/assets/foliate/main.js` 的 `window.applyPreferences = function (prefs) { ... }`（第 81-89 行）之後、`async function openBook() {`（第 91 行）之前，插入：

```js
/**
 * 換頁／跳轉全書進度比例，供原生端 FoliateEpubReaderView.kt 的
 * nextPage／previousPage／jumpToProgression method channel case 呼叫
 * （evaluateJavascript 只能存取掛在 window 上的函式，view 是本模組頂層
 * 作用域的 const，不會自動出現在 window 上，見 Global Constraints）。
 * view.next()/view.prev()/view.goToFraction() 為 readest/foliate-js
 * View 類別既有 API（已查證 view.js 原始碼確認存在），本函式不重新實作
 * 任何換頁邏輯，純粹是可供 evaluateJavascript 呼叫的橋接層。
 */
window.nextPage = function () {
  view.next()
}

window.previousPage = function () {
  view.prev()
}

window.jumpToFraction = function (fraction) {
  view.goToFraction(fraction)
}

```

- [x] **Step 2: `FoliateEpubReaderView.kt` 新增 method channel case**

第 126-143 行的 `onMethodCall`：

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
                // 3×3 導航熱區完全由 Dart 端 Stack 疊加層判讀（見
                // foliate_epub_reader_view.dart，epic-17-epub-render-migration
                // Issue 5「不在原生端判讀」），本 case 純粹是換頁指令的轉發，
                // 不做任何座標/熱區判斷。
                webView.evaluateJavascript("window.nextPage()", null)
                result.success(null)
            }
            "previousPage" -> {
                webView.evaluateJavascript("window.previousPage()", null)
                result.success(null)
            }
            "jumpToProgression" -> {
                val progression = call.argument<Double>("progression")
                if (progression != null) {
                    webView.evaluateJavascript("window.jumpToFraction($progression)", null)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

- [x] **Step 3: 確認 Kotlin 編譯成功**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`。

- [x] **Step 4: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-17): FoliateEpubReaderView.kt/main.js 新增換頁與進度跳轉橋接"
```

---

### Task 2: `foliate_epub_reader_view.dart`——`nextPage`/`previousPage`/`jumpToProgression` static helper

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 新增的 `nextPage`／`previousPage`／`jumpToProgression` method channel 契約。
- Produces: `FoliateEpubReaderView.nextPage(GlobalKey<State<FoliateEpubReaderView>> key)`／`FoliateEpubReaderView.previousPage(GlobalKey<State<FoliateEpubReaderView>> key)`／`FoliateEpubReaderView.jumpToProgression(GlobalKey<State<FoliateEpubReaderView>> key, double progression)` 三個強型別 static helper，供 Task 4 的 `ReaderScreen._handleZoneAction()` 呼叫。

- [x] **Step 1: 寫失敗測試——static helper 呼叫對應 method channel**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 的 `main()` 內、最後一個 `testWidgets` 區塊之後，新增：

```dart
  testWidgets(
      'FoliateEpubReaderView.nextPage()／previousPage()／jumpToProgression()'
      '（強型別 static helper）呼叫原生端對應 method channel',
      (tester) async {
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    FoliateEpubReaderView.nextPage(key);
    await tester.pump();
    expect(calls.any((c) => c.method == 'nextPage'), isTrue);

    FoliateEpubReaderView.previousPage(key);
    await tester.pump();
    expect(calls.any((c) => c.method == 'previousPage'), isTrue);

    FoliateEpubReaderView.jumpToProgression(key, 0.42);
    await tester.pump();
    final jumpCall = calls.firstWhere((c) => c.method == 'jumpToProgression');
    expect(jumpCall.arguments, {'progression': 0.42});
  });
```

- [x] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：新測試 FAIL，錯誤訊息為 `The method 'nextPage' isn't defined for the type 'FoliateEpubReaderView'`（或等價的 static method 不存在錯誤）。

- [x] **Step 3: 於 `foliate_epub_reader_view.dart` 新增 static helper**

第 40-60 行（建構子與 `createState()` 之間）：

```dart
    this.textAlign,
    this.publisherStyles,
  });

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}
```

改為：

```dart
    this.textAlign,
    this.publisherStyles,
  });

  /// 呼叫原生端 view.next()，換頁不觸發任何回呼（強型別 static helper，
  /// 比照既有 EpubReaderView.nextPage 模式，不使用 `as dynamic` 跨越
  /// State 的 private 邊界）。[key] 對應的 State 若尚未掛載（例如純
  /// flutter_test 環境下 AndroidView 尚未建立），靜默忽略。
  static void nextPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('nextPage');
    }
  }

  /// 呼叫原生端 view.prev()，同上僅換頁方向相反。
  static void previousPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('previousPage');
    }
  }

  /// 跳轉到指定全書進度比例（0.0-1.0），原生端呼叫 view.goToFraction()。
  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('jumpToProgression', {
        'progression': progression,
      });
    }
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}
```

- [x] **Step 4: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：全數 PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): FoliateEpubReaderView 新增 nextPage/previousPage/jumpToProgression static helper"
```

---

### Task 3: `foliate_epub_reader_view.dart`——3×3 導航熱區疊加層

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: 既有 `ZoneAction`（`app/lib/reader/zone_action.dart`）列舉。
- Produces: `FoliateEpubReaderView` 新增建構參數 `navZoneActions: List<ZoneAction>`（預設 9 格皆 `ZoneAction.none`）／`onZoneAction: ValueChanged<ZoneAction>?`／`showNavZoneDebugOverlay: bool`（預設 `false`），`build()` 疊加 9 個 `Key('nav_zone_$index')` 的 `GestureDetector`。供 Task 4 的 `ReaderScreen._buildNativeView()` 傳入。

- [x] **Step 1: 寫失敗測試——9 個熱區存在且點擊觸發 onZoneAction**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/zone_action.dart';
```

在 `main()` 內新增（緊接 Task 2 新增的測試之後）：

```dart
  testWidgets(
      '3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
      (tester) async {
    final capturedActions = <ZoneAction>[];
    await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
        ],
        onZoneAction: capturedActions.add,
      ),
    );

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.nextPage]);

    await tester.tap(find.byKey(const Key('nav_zone_4')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.nextPage, ZoneAction.menu]);

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();
    expect(
      capturedActions,
      [ZoneAction.nextPage, ZoneAction.menu, ZoneAction.none],
    );
  });

  testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤',
      (tester) async {
    await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.none, ZoneAction.none, ZoneAction.none,
          ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ],
        showNavZoneDebugOverlay: true,
      ),
    );

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
    expect(find.text('無動作'), findsWidgets);
  });
```

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：新測試 FAIL（`navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 建構參數不存在，或 `find.byKey(Key('nav_zone_0'))` 找不到 widget）。

- [x] **Step 3: 新增 `zone_action.dart` import**

第 1-7 行：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';
import 'zone_action.dart';
```

- [x] **Step 4: 新增建構參數**

第 37-56 行：

```dart
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
  });
```

改為：

```dart
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  /// 3×3 導航熱區的動作對照表（epic-17-epub-render-migration Issue 5，
  /// 對稱 epic-7-interaction 為 EpubReaderView FXL 分支建立的既有模式，
  /// 見 zone_hit_test.dart 索引慣例：0-indexed、列優先）。與
  /// EpubReaderView 不同，這個陣列**只在 Dart 端使用**，不會送給原生端
  /// （見 Global Constraints「不在原生端判讀」）。
  final List<ZoneAction> navZoneActions;

  /// 點擊熱區換算出動作後觸發，呼叫端（ReaderScreen）負責分派實際行為
  /// （換頁／切換沉浸模式）。
  final ValueChanged<ZoneAction>? onZoneAction;

  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供設定畫面開啟除錯
  /// 用途。
  final bool showNavZoneDebugOverlay;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
  });
```

- [x] **Step 5: 新增 `Stack` 疊加層與 `build()` 修改**

原本的 `build()`（新增 static helper 後，位於檔案最末段）：

```dart
  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/foliate_epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    // 3×3 導航熱區疊加層（epic-17-epub-render-migration Issue 5）：與
    // EpubReaderView 的 FXL 分支逐位元組相同的 Stack 兄弟節點模式（見
    // spec.md「介面」節「不在原生端判讀」）——每格是獨立的
    // GestureDetector，格子索引由排版位置直接決定，不需要座標換算
    // （hitTestZoneIndex() 只服務原生 Kotlin InputListener 這種單一座標
    // 回呼的場景）。與 EpubReaderView 不同的是，這個 widget 只服務流式
    // 書籍，疊加層恆常顯示，不需要像 EpubReaderView 那樣依
    // _isFixedLayout 狀態切換。
    return Stack(
      children: [
        AndroidView(
          viewType: 'cc.ugotit.elinkbook/foliate_epub_reader_view',
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        onHorizontalDragStart: (_) {},
                        onVerticalDragStart: (_) {},
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
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

- [x] **Step 6: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：全數 PASS（含 Task 2 新增的 static helper 測試——`_pumpFoliateEpubReaderView` 的既有測試不受 `Stack` 疊加層影響，`AndroidView` 仍是 `find.byType(AndroidView)` 唯一符合的祖先鏈節點）。

- [x] **Step 7: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 8: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): FoliateEpubReaderView 新增 3×3 導航熱區疊加層"
```

---

### Task 4: `ReaderScreen`——接上流式 EPUB 的換頁與熱區分派

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2/3 新增的 `FoliateEpubReaderView.nextPage`/`previousPage`/`navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay`；既有 `ResolvedPreferences.navZoneActions`/`showNavZoneDebugOverlay`（epic-7-interaction 既有欄位，未變動）；既有 `_dispatchedIsFixedLayout`（Issue 3 已建立，`true`=FXL/`EpubReaderView`、`false`=流式/`FoliateEpubReaderView`）。
- Produces: 流式 EPUB 開書後，`_handleZoneAction()` 的 `previousPage`/`nextPage`/`menu` 三種動作皆正確生效，供 Task 5 真機驗證。

- [x] **Step 1: 寫失敗測試——流式 EPUB 點擊選單熱區觸發沉浸模式切換**

在 `app/test/screens/reader_screen_test.dart` 的 `main()` 內最後一個 `testWidgets` 區塊之後（第 2497-2527 行既有的「EPUB 流式：原生端 onZoneTapped 回呼」測試之後），新增：

```dart
  testWidgets('EPUB 流式（isFixedLayout: false）：點擊選單熱區觸發沉浸模式切換',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
    // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets(
      'EPUB 流式：previousPage/nextPage 熱區呼叫 FoliateEpubReaderView 對應'
      ' method channel，且不影響沉浸模式狀態（design.md 決策 #14）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // rightFlip 模板：index 2（右欄）＝ nextPage。
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(instanceCalls.any((c) => c.method == 'nextPage'), isTrue);
    expect(find.byType(AppBar), findsOneWidget,
        reason: '換頁動作不應影響沉浸模式狀態');

    // rightFlip 模板：index 0（左欄）＝ previousPage。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(instanceCalls.any((c) => c.method == 'previousPage'), isTrue);
    expect(find.byType(AppBar), findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：兩個新測試 FAIL——`find.byKey(Key('nav_zone_1'))`/`find.byKey(Key('nav_zone_0'))`/`find.byKey(Key('nav_zone_2'))` 找不到 widget（`_buildNativeView()` 尚未傳入 `navZoneActions`/`onZoneAction`）。

- [x] **Step 3: `_buildNativeView()` Foliate 分支傳入熱區參數**

第 1508-1527 行：

```dart
      case BookFormat.epub:
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
            writingMode: resolved.writingMode,
            pageTurnMode: resolved.pageTurnMode,
            fontFamily: resolved.fontFamily,
            fontSize: resolved.fontSize,
            fontWeight: resolved.fontWeight,
            lineHeight: resolved.lineHeight,
            paragraphSpacing: resolved.paragraphSpacing,
            pageMargins: resolved.pageMargins,
            textAlign: resolved.textAlign,
            publisherStyles: resolved.publisherStyles,
          );
        }
        return EpubReaderView(
```

改為：

```dart
      case BookFormat.epub:
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
            writingMode: resolved.writingMode,
            pageTurnMode: resolved.pageTurnMode,
            fontFamily: resolved.fontFamily,
            fontSize: resolved.fontSize,
            fontWeight: resolved.fontWeight,
            lineHeight: resolved.lineHeight,
            paragraphSpacing: resolved.paragraphSpacing,
            pageMargins: resolved.pageMargins,
            textAlign: resolved.textAlign,
            publisherStyles: resolved.publisherStyles,
            navZoneActions: resolved.navZoneActions,
            onZoneAction: _handleZoneAction,
            showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          );
        }
        return EpubReaderView(
```

- [x] **Step 4: `_handleZoneAction()` 依 `_dispatchedIsFixedLayout` 分派**

第 1596-1646 行（含既有說明註解與 `previousPage`/`nextPage` 分支）：

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
  /// 原生端 `MainActivity.dispatchKeyEvent()` 攔截音量鍵後的回呼
  /// （epic-7-interaction Issue 7）：方向固定映射，不查詢
  /// `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律上一頁、
  /// `down` 一律下一頁。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    final args = call.arguments as Map<Object?, Object?>;
    switch (args['direction'] as String?) {
      case 'up':
        _handleZoneAction(ZoneAction.previousPage);
        break;
      case 'down':
        _handleZoneAction(ZoneAction.nextPage);
        break;
    }
  }

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
}
```

改為：

```dart
  /// 熱區動作統一分派入口（epic-7-interaction Issue 4，Issue 5 擴充 EPUB
  /// FXL 分支，epic-17-epub-render-migration Issue 5 擴充流式 EPUB 的
  /// `FoliateEpubReaderView` 分支）：`previousPage`/`nextPage` 呼叫目前
  /// 格式對應的既有換頁方法；`menu` 切換 [_chromeVisible]（沉浸模式）；
  /// `none` 不做事。**`previousPage`/`nextPage` 刻意不影響
  /// [_chromeVisible]**（design.md 決策 #14）。EPUB 分支的 `previousPage`/
  /// `nextPage` 依 `_dispatchedIsFixedLayout` 分派：`true`（FXL，
  /// `EpubReaderView`）呼叫 `EpubReaderView.previousPage`/`nextPage`；
  /// `false`（流式，`FoliateEpubReaderView`）呼叫
  /// `FoliateEpubReaderView.previousPage`/`nextPage`——兩者的 3×3 熱區皆是
  /// Dart 端 `Stack` 疊加層，`onTap` 直接回呼 [onZoneAction]（見
  /// `_buildNativeView()` 接線），不經過原生端判讀。`EpubReaderView` 既有的
  /// `onZoneTapped`（cellIndex 回呼）是 epic-17-epub-render-migration 之前
  /// 遺留的流式 EPUB via Readium 機制（原生 `InputListener` 座標換算），
  /// post-epic-17 的分派邏輯下流式書籍一律改建構 `FoliateEpubReaderView`，
  /// 這條舊路徑理論上不再被觸發，保留是避免不必要地改動
  /// `EpubReaderView.kt`（本工單範圍外，見 issues.md Issue 5 描述「原生端
  /// FoliateEpubReaderView.kt 完全不需要移植 NavZoneHitTester.cellIndex()
  /// 或 InputListener 註冊邏輯」）。原生端 `MainActivity.dispatchKeyEvent()`
  /// 攔截音量鍵後的回呼（epic-7-interaction Issue 7）：方向固定映射，不
  /// 查詢 `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律
  /// 上一頁、`down` 一律下一頁。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    final args = call.arguments as Map<Object?, Object?>;
    switch (args['direction'] as String?) {
      case 'up':
        _handleZoneAction(ZoneAction.previousPage);
        break;
      case 'down':
        _handleZoneAction(ZoneAction.nextPage);
        break;
    }
  }

  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          if (_dispatchedIsFixedLayout == true) {
            EpubReaderView.previousPage(_epubReaderViewKey);
          } else {
            FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
          }
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          if (_dispatchedIsFixedLayout == true) {
            EpubReaderView.nextPage(_epubReaderViewKey);
          } else {
            FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
          }
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
}
```

- [x] **Step 5: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數 PASS，特別留意既有「EPUB 流式：原生端 onZoneTapped 回呼」測試（第 2497 行）不受影響——該測試未傳入 `isFixedLayout`，`_dispatchedIsFixedLayout` 退回既有預設值 `true`，仍建構 `EpubReaderView`，不受本工單新增分支影響。

- [x] **Step 6: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-17): ReaderScreen 接上流式 EPUB 的換頁與 3×3 熱區分派"
```

---

### Task 5: 真機整合測試——流式 EPUB 3×3 導航熱區

**Files:**
- Create: `app/integration_test/foliate_stream_nav_zone_test.dart`

**Interfaces:**
- Consumes: Task 1-3 的完整換頁/熱區實作；既有測試素材 `test/fixtures/sample_multi_chapter.epub`（已在 `pubspec.yaml` 宣告為 asset，`epub_stream_nav_zone_test.dart`／`epub_fxl_tap_zone_test.dart` 既有使用）。
- Produces: 真機驗證證據，供 Task 6 全面驗證引用。

**本 Task 無法寫「失敗測試先行」的 TDD 循環**（比照本 Epic Issue 3/4 既有慣例）：`integration_test` 需要真實裝置渲染 `WebView`，Task 1-3 完成前這個測試必然全數失敗（`FoliateEpubReaderView.nextPage`/`navZoneActions` 尚不存在），Task 1-3 完成後才具備可執行的前提。本 Task 直接撰寫最終版本，於裝置上執行驗證。

- [x] **Step 1: 新增真機整合測試檔案**

建立 `app/integration_test/foliate_stream_nav_zone_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 17 Issue 5：流式 EPUB（FoliateEpubReaderView）3×3 導航熱區——真機
/// 整合測試。
///
/// 【與 epub_fxl_tap_zone_test.dart 的差異】FoliateEpubReaderView 尚未有
/// onLocatorChanged（頁碼/定位回報是 Issue 6 的範圍），本檔案無法比對
/// locatorJson 變動來證實「真的換頁了」，只能驗證：熱區點擊確實觸發正確
/// 的 onZoneAction、換頁呼叫（FoliateEpubReaderView.previousPage/
/// nextPage）送達原生端後不觸發 onError／不崩潰。實際換頁後畫面內容是否
/// 正確變動，留待人工於裝置畫面截圖確認（比照
/// foliate_epub_reader_view_test.dart「手動切換橫排→直排」測試既有的
/// 相同限制記錄慣例）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '流式 EPUB 開書後出現九宮格熱區，點擊各格觸發對應動作、'
      '「無動作」格仍攔截觸控不崩潰，previousPage/nextPage 換頁呼叫不觸發 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub',
        'foliate_stream_nav_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedActions = <ZoneAction>[];
    final key = GlobalKey<State<FoliateEpubReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          // 涵蓋 previousPage／menu／nextPage／none 四種動作，其中 index 3
          // 為 none（比照 epub_fxl_tap_zone_test.dart 既有先例：無動作格
          // 仍應攔截觸控，只是不做事）。
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.none, ZoneAction.menu, ZoneAction.none,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneAction: (action) {
            capturedActions.add(action);
            // 模擬 ReaderScreen._handleZoneAction 的實際分派邏輯（本測試
            // 直接建構 FoliateEpubReaderView，不經過 ReaderScreen，故在此
            // 手動呼叫，讓換頁動作真的送到原生端，而非只驗證回呼有沒有
            // 被呼叫，比照 epub_fxl_tap_zone_test.dart 既有模式）。
            switch (action) {
              case ZoneAction.previousPage:
                FoliateEpubReaderView.previousPage(key);
                break;
              case ZoneAction.nextPage:
                FoliateEpubReaderView.nextPage(key);
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
          reason: 'FoliateEpubReaderView 的九宮格熱區疊加層應恆常顯示');
    }

    await tester.tap(find.byKey(const Key('nav_zone_2'))); // index 2 = nextPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.nextPage);

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
        reason: '無動作格仍應攔截觸控並回報 none（不穿透到底層 WebView——若真的'
            '穿透，onZoneAction 閉包根本不會被呼叫，capturedActions 不會有'
            '新項目）');
  });
}
```

- [x] **Step 2: 確認測試裝置在線**

```bash
adb devices -l
```

預期：`3CEF42ECD491687` 出現在清單中且狀態為 `device`（非 `unauthorized`/`offline`）。

- [x] **Step 3: 於真機執行本測試**

於 `app/` 目錄執行：

```bash
flutter test integration_test/foliate_stream_nav_zone_test.dart -d 3CEF42ECD491687
```

預期：PASS。若失敗，依錯誤訊息判斷是 Task 1（原生換頁橋接）或 Task 3（Dart 熱區疊加層）的問題，回頭修正對應 Task 後重新執行，不在本 Task 內臨時繞過。

- [x] **Step 4: Commit**

```bash
git add app/integration_test/foliate_stream_nav_zone_test.dart
git commit -m "test(epic-17): 新增流式 EPUB 3×3 導航熱區真機整合測試"
```

---

### Task 6: 全面驗證

**Files:** 無新增/修改檔案（除 Step 6 的 `issues.md` 狀態更新）。

**Interfaces:**
- Consumes: Task 1-5 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [x] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS（Issue 4 完成時基準為 564 個測試，本工單 Task 2 新增 1 個、Task 3 新增 2 個、Task 4 新增 2 個，預期共 569 個）。

- [x] **Step 2: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 3: 執行 Kotlin 編譯與 JVM 測試**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:testDebugUnitTest
```

預期：兩者皆 `BUILD SUCCESSFUL`（93 個既有 JVM 測試，本 Issue 無新增）。

- [x] **Step 4: 於真機執行 Foliate 相關 `integration_test`**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_stream_nav_zone_test.dart -d 3CEF42ECD491687
```

預期：全數 PASS（`foliate_epub_reader_view_test.dart` 為 Issue 3/4 既有 7 個 + 本工單新增的 `foliate_stream_nav_zone_test.dart` 1 個）。

- [x] **Step 5: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-5 修改/新增的檔案，無不相關的暫存產物。

- [x] **Step 6: 更新 `issues.md` Issue 5 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 5」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1-4 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-5.md` Task 1-6 完成 `FoliateEpubReaderView.kt`（`nextPage`/`previousPage`/`jumpToProgression` method channel）／`main.js`（`window.nextPage`/`window.previousPage`/`window.jumpToFraction` 橋接）／`foliate_epub_reader_view.dart`（static helper 三個＋與 `EpubReaderView` FXL 分支逐位元組相同的 3×3 導航熱區疊加層）／`ReaderScreen`（`_buildNativeView()` 傳入熱區參數、`_handleZoneAction()` 依 `_dispatchedIsFixedLayout` 分派）。新增真機整合測試 `foliate_stream_nav_zone_test.dart`。`flutter test`（569 tests）／`flutter analyze`／`./gradlew.bat :app:compileDebugKotlin`／`./gradlew.bat :app:testDebugUnitTest` 以及真機 `integration_test`（9 格熱區逐一點擊、無動作格攔截觸控、換頁呼叫不觸發 onError）皆全數通過。目錄跳轉、定位持久化與頁碼顯示、劃線備註留給 Issue 6-8。
```

- [x] **Step 7: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 5 完成，更新 issues.md 狀態"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 5 描述逐項對應：
- `nextPage`／`previousPage` 強型別 static helper（原生端呼叫 `view.next()`/`view.prev()`）→ Task 1（原生橋接）+ Task 2（Dart static helper）。
- 3×3 導航熱區「不在原生端判讀」，複用 `EpubReaderView` FXL 分支既有模式 → Task 3。
- `jumpToProgression` 強型別 static helper（原生端呼叫 `view.goToFraction(progression)`）→ Task 1 + Task 2（與 `nextPage`/`previousPage` 合併同一組 Task，因三者共用同一個 `evaluateJavascript` 橋接機制與同一份 Dart State 存取模式）。
- `ReaderScreen._handleZoneAction` 新增流式 `foliate-js` 分支，接上 `onZoneAction`（與 FXL 分支邏輯相同，複用同一個分派入口）→ Task 4。

**單元測試要求逐項對應**：
- `foliate_epub_reader_view.dart` widget test：9 個 `Key('nav_zone_$index')` widget 存在且可點擊，點擊後觸發 `onZoneAction` 回呼、傳入正確的 `ZoneAction` → Task 3 Step 1。
- `ReaderScreen` widget test：流式 `foliate-js` 開書後點擊選單格觸發沉浸模式切換；翻頁動作不影響沉浸模式狀態 → Task 4 Step 1（兩個測試）。
- （額外，非 issues.md 明確要求但屬於本工單新增公開 API 的合理測試覆蓋）`nextPage`/`previousPage`/`jumpToProgression` static helper 呼叫正確 method channel → Task 2 Step 1。

**驗收標準逐項對應**：
- 上述測試皆通過、`flutter analyze` 乾淨 → Task 6 Step 1-2。
- `integration_test`（真實裝置）：9 格熱區逐一點擊觸發正確換頁/沉浸模式切換；「無動作」格正確攔截觸控（不穿透到底層 WebView）→ Task 5。

**Placeholder 掃描**：全文檢查未發現「TBD」/「待補」/「依實際情況調整」等佔位語句，所有程式碼區塊皆為完整可執行內容。

**型別一致性檢查**：`FoliateEpubReaderView.nextPage`/`previousPage`/`jumpToProgression` 的簽章（`GlobalKey<State<FoliateEpubReaderView>>` 作為第一參數）在 Task 2（定義）、Task 4（`_handleZoneAction` 呼叫）、Task 5（整合測試呼叫）三處逐字一致；`navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數的型別（`List<ZoneAction>`／`ValueChanged<ZoneAction>?`／`bool`）在 Task 3（定義）與 Task 4（`ReaderScreen` 傳入 `resolved.navZoneActions`/`_handleZoneAction`/`resolved.showNavZoneDebugOverlay`）保持一致，且與既有 `ResolvedPreferences` 對應欄位型別相同，不需要轉換。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-5.md`. Two execution options:

1. **Subagent-Driven（推薦）**——每個 Task 派一個全新 subagent 執行，Task 之間插入審查
2. **Inline Execution**——在目前這個 session 內依 executing-plans 批次執行，於檢查點暫停

Which approach?
