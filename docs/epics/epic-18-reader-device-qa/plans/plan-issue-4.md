# Epic 18 Issue 4 — 直排文字頂端裁切與本文/頁尾間空白過多 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 直排 EPUB 的上下邊距不再完全依賴 `readest/foliate-js` `paginator.js` 內建的固定 `48px`，改為透過 `main.js` 的 `window.applyPreferences(prefs)` 呼叫 `view.renderer.setAttribute('margin-top'/'margin-bottom', ...)` 動態設定：上邊距放大以避免「頂端文字被裁切」（使用者回報項目 6），下邊距依 `ReaderFooter` 是否顯示分別縮小/維持，避免與 in-flow 頁尾重複扣高度而造成「多一行空白」（使用者回報項目 7）。

**Architecture:** `main.js` 的 `buildOverrideCss(prefs)` 維持既有純函式職責（只組裝 CSS 字串），本 Issue 全部邏輯加在既有的 `window.applyPreferences(prefs)`（副作用進入點）內，讀取既有的 `currentWritingMode` 模組變數（而非 `prefs.writingMode`，理由見 Global Constraints）決定是否套用直排專屬邊距，讀取既有的 `prefs.pageMargins`（重用既有滑桿倍率，不新增 UI/欄位）換算邊距數值。下邊距需要知道 `ReaderFooter` 目前是否顯示，這個資訊（`ResolvedPreferences.showFooter`）目前完全沒有傳給 `FoliateEpubReaderView`/JS 層，因此新增一個 nullable 的 `FoliateEpubReaderView.showFooter` 建構參數，比照既有 9 個 nullable 偏好欄位的既有模式（`_buildPreferencesMap()` 條件式加入 map），一路透傳到 `main.js`。

**Tech Stack:** JavaScript（`app/android/app/src/main/assets/foliate/main.js`，WebView 內執行，無 JS 單元測試框架）、Flutter/Dart（`app/lib/reader/foliate_epub_reader_view.dart`、`app/lib/screens/reader_screen.dart`）、`flutter_test`（widget test，Task 1-2 可用 `flutter test` 驗證）、`integration_test`（Task 3 的開書 smoke test，需真機/模擬器）、Task 4 為真機人工視覺驗收。

## Global Constraints

- **所有指令皆在 `app/` 目錄下執行**（`cd "U:/MyDeveloper/AI/elinkBook/app"`），使用 POSIX 相容 Bash（Git Bash），非 PowerShell。
- **`flutter analyze` 必須保持乾淨**（"No issues found!"）——每個 Task 完成程式碼異動後都要跑一次。
- **`buildOverrideCss(prefs)` 維持純函式，不在其內部呼叫 `setAttribute`**（`spec.md`「模組」段落審查修正明文要求）：本 Issue 新增的 `setAttribute('margin-top', ...)`／`setAttribute('margin-bottom', ...)` 呼叫一律加在 `window.applyPreferences(prefs)` 內，與既有 `pageTurnMode`/`writingMode`/（Issue 5）`singleColumn` 的既有分工一致。
- **不修改 vendored 檔案**：`paginator.js`／`view.js`／`overlayer.js`／`progress.js` 皆不可修改。`margin-top`／`margin-bottom` 已是 `paginator.js` 既有 `Paginator.observedAttributes` 成員（`paginator.js:1157-1161`）與既有 `attributeChangedCallback()`（`paginator.js:1545-1559`）已支援的外部可設定屬性，本 Issue 只呼叫既有的 `view.renderer.setAttribute()` API。
- **`margin-top`/`margin-bottom` 必須帶 CSS 單位（`px`），與 Issue 5 的 `max-column-count` 不同**：`paginator.js` 把這兩個自訂屬性直接用在 `grid-template-rows: minmax(var(--_margin-top), 1fr) ... minmax(var(--_margin-bottom), 1fr)`（`paginator.js:1256-1259`），是長度屬性；`setAttribute()` 傳入純數字（不帶單位）對 CSS 長度屬性是無效值，會被引擎靜默忽略、邊距形同沒設定，且不會有任何錯誤訊息（`spec.md`「CSS 單位要求」審查修正）。本 Issue 所有 `setAttribute('margin-top'/'margin-bottom', ...)` 呼叫皆須傳入形如 `` `${數字}px` `` 的字串。
- **必須用 `currentWritingMode`（既有模組變數）判斷排版方向，不可直接讀 `prefs.writingMode`**：`main.js` 開書當下（ADR 0003「初次開書不主動設定」＋ FR-06 非同步偵測）與後續 `didUpdateWidget` 觸發的 `setPreferences` 呼叫，`prefs.writingMode` 在特定時序下可能是 `undefined`（例如 Dart 端尚未完成排版方向自動偵測、但其他偏好欄位已先變動觸發 `setPreferences`），而 `currentWritingMode`（`main.js` 既有模組級變數，`let currentWritingMode = 'horizontal'`，於 FR-06 `{ once: true }` relocate 監聽器與每次 `applyPreferences()` 呼叫時更新，見宣告處既有註解）已保證持有「目前實際生效」的最新已知值，這正是 Issue 5（epic-17 Issue 8）新增這個變數時要解決的同一類時序問題。本 Issue 的判斷式必須放在 `applyPreferences` 內「`if (prefs.writingMode) { currentWritingMode = prefs.writingMode }`」這行**之後**，才能讀到本次呼叫更新後的值。
- **橫排模式必須明確還原成 `48px` 預設值，不能只在直排時呼叫 `setAttribute`**：`setAttribute()` 具持久性（不會隨排版方向切換自動歸零/還原成 CSS 內建預設值）。若只在 `currentWritingMode === 'vertical'` 時呼叫 `setAttribute`、橫排時完全不呼叫，使用者「直排 → 手動切回橫排」後，`--_margin-top`/`--_margin-bottom` 會殘留先前直排時設定的數值，違反 `issues.md` 驗收標準「橫排模式（不受本 Issue 影響的既定行為）需回歸確認未被意外改動」。本 Issue 的邏輯必須是 `if/else`：直排時套用新邏輯，橫排時明確呼叫 `setAttribute('margin-top', '48px')`／`setAttribute('margin-bottom', '48px')` 還原內建預設值。
- **`FoliateEpubReaderView.showFooter` 必須宣告為 nullable（`bool?`）、`_buildPreferencesMap()` 條件式加入 map，不可做成非 nullable/無條件加入**：已查證 `app/test/reader/foliate_epub_reader_view_test.dart` 現有 7 處對 `initialPreferences`/`setPreferences` 的**完整 map 相等**斷言（第 63、79、147、174-185、200、252 行），這些既有測試建構 `FoliateEpubReaderView` 時皆未傳入任何「頁尾顯示狀態」相關參數。若把 `showFooter` 做成非 nullable 型別並無條件塞進 map，這 7 處既有斷言會全數失敗（預期的空 map／既有欄位 map 會多出一個非預期的 `showFooter` key）。做成 nullable、只在非 null 時才加入 map，比照既有 9 個 nullable 偏好欄位（`writingMode`／`pageTurnMode`／`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`pageMargins`／`textAlign`／`publisherStyles`／`singleColumn`）的既有慣例，這 7 處既有測試完全不需要修改（它們都沒有傳入 `showFooter`，該欄位會如同其餘未傳入的欄位一樣被省略）。`ReaderScreen` 實際建構時一律傳入 `resolved.showFooter`（`ResolvedPreferences.showFooter` 本身是非 nullable `bool`，隱式轉型為 `bool?` 沒有問題），所以在真實 App 執行路徑上 `showFooter` 一定會被送到 `main.js`，只有既有 widget test 的直接建構（略過 `ReaderScreen`）才會省略它。
- **`main.js` 的 `setAttribute` 呼叫本身無 JS 單元測試**（`spec.md`「測試決策」，比照 Epic 17 既有慣例——`evaluateJavascript`/`WebView` 呼叫是框架 API 直接串接，無可抽出的純邏輯）。驗收依賴 Task 3 的 `integration_test`（僅驗證開書不崩潰／`setAttribute` 呼叫本身不拋錯，**不能**驗證「文字是否真的沒被裁切」這種視覺結果）與 Task 4 的真機人工視覺確認（**唯一**能驗證實際視覺效果的方式）。
- **本 Issue 不新增 `BookReaderPrefs`/SQLite 欄位**：`design.md`「決策」明確優先重用既有 `pageMargins` 偏好，`showFooter` 本身已是既有欄位（`epic-5-toc-pagination` Issue 5 新增），本 Issue 只需要把這個既有的已解析值（`ResolvedPreferences.showFooter`）多透傳一層到 `FoliateEpubReaderView`/JS，不涉及任何持久化層變更。
- **具體邊距數值為起始建議值，非最終規格**（比照 Issue 2 的既有慣例，`spec.md`「下邊距具體數值需在實作階段量測」原文亦明確授權 Plan 階段決定具體公式）：上邊距 `Math.round(64 * marginMultiplier)`px（以 `paginator.js` 內建 `48px` 為基準放大約 1.33 倍）；下邊距頁尾顯示時 `Math.round(16 * marginMultiplier)`px、頁尾隱藏時 `Math.round(64 * marginMultiplier)`px；`marginMultiplier` 為 `typeof prefs.pageMargins === 'number' ? prefs.pageMargins : 1`（`1` 對應既有 UI 滑桿未調整時的中性倍率，見 `reader_settings_sheet.dart` `_toMultiplier(_pageMargins, 15.0)` 换算）。Task 4 真機確認若視覺效果不理想，可調整這些起始建議值，不需要回頭修改本計劃的其餘部分。
- **既有測試裝置**：`3CEF42ECD491687`（9491G，Android 15／API 35），Task 4 使用。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 `showFooter` 建構參數（nullable），`_buildPreferencesMap()`／`_preferencesChanged()` 同步更新 |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改（新增測試） | `showFooter` 出現/不出現於 `initialPreferences` map、`didUpdateWidget` 變動時觸發 `setPreferences` |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 `showFooter: resolved.showFooter` |
| `app/test/screens/reader_screen_test.dart` | 修改（擴充既有測試） | `ReaderSettingsSheet` 關閉頁尾開關後正確傳遞到 `FoliateEpubReaderView` |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `window.applyPreferences(prefs)` 新增直排上下邊距 `setAttribute` 邏輯 |
| `app/integration_test/foliate_margin_test.dart` | 新增 | 真機/模擬器 smoke test：直排/橫排、頁尾顯示/隱藏、自訂/預設 `pageMargins` 組合開書不崩潰 |

---

### Task 1：`FoliateEpubReaderView.showFooter` 建構參數

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：`bool? showFooter` 建構參數
- Produces：`_buildPreferencesMap()` 在 `widget.showFooter != null` 時於 map 加入 `'showFooter': widget.showFooter`；`_preferencesChanged()` 涵蓋此欄位

- [ ] **Step 1：撰寫失敗測試**

在 `app/test/reader/foliate_epub_reader_view_test.dart`，於既有 `'singleColumn 變動時，didUpdateWidget 呼叫 setPreferences 並帶入新值'` 測試（第 100-148 行）之後新增：

```dart
  testWidgets('showFooter: false 時，openBook 的 initialPreferences 含 showFooter: false',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {'showFooter': false});
  });

  testWidgets('showFooter 為 null（預設）時，initialPreferences 不含 showFooter key',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments['initialPreferences'] as Map).containsKey('showFooter'),
      isFalse,
    );
  });

  testWidgets('showFooter 變動時，didUpdateWidget 呼叫 setPreferences 並帶入新值',
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

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      ),
    ));
    await tester.pumpAndSettle();

    final setPreferencesCall =
        instanceCalls.firstWhere((c) => c.method == 'setPreferences');
    expect(setPreferencesCall.arguments, {'showFooter': false});
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：新增的 3 個測試皆因 `showFooter` 建構參數不存在而編譯失敗（`The named parameter 'showFooter' isn't defined`）。

- [ ] **Step 3：實作 `FoliateEpubReaderView.showFooter`**

在 `app/lib/reader/foliate_epub_reader_view.dart` 第 61 行（`final bool? singleColumn;` 欄位宣告與其文件註解）之後新增欄位：

```dart
  final bool? singleColumn;

  /// 頁尾（`ReaderFooter`）目前是否顯示（epic-18-reader-device-qa
  /// Issue 4）：`null`＝未知（`main.js` 視同已顯示，見該檔案對應邏輯的
  /// `prefs.showFooter === false` 判斷式），非 null 時供直排上下邊距
  /// 計算使用——頁尾顯示時（in-flow，已經壓縮過 WebView 可視高度一次）
  /// 只需要小幅下邊距，頁尾隱藏時則需要較大下邊距避免文字貼齊螢幕底緣。
  /// 與其餘偏好欄位不同，這個值本身不是使用者可覆寫的「偏好」，而是
  /// `ReaderScreen` 已解析的 `ResolvedPreferences.showFooter`（非 nullable
  /// `bool`）原樣透傳，型別維持 `bool?` 只是為了沿用既有「未傳入時 map
  /// 省略此 key」的既有 pass-through 慣例（見 Global Constraints）。
  final bool? showFooter;
```

建構子（第 100-129 行）在 `this.singleColumn,` 之後新增：

```dart
    this.singleColumn,
    this.showFooter,
```

`_preferencesChanged()`（第 241-253 行）在 `widget.singleColumn != oldWidget.singleColumn` 之後新增：

```dart
  bool _preferencesChanged(FoliateEpubReaderView oldWidget) {
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
        widget.singleColumn != oldWidget.singleColumn ||
        widget.showFooter != oldWidget.showFooter;
  }
```

`_buildPreferencesMap()`（第 259-287 行）在 `if (widget.singleColumn != null) { map['singleColumn'] = widget.singleColumn; }` 之後新增：

```dart
    if (widget.singleColumn != null) {
      map['singleColumn'] = widget.singleColumn;
    }
    if (widget.showFooter != null) {
      map['showFooter'] = widget.showFooter;
    }
    return map;
  }
```

- [ ] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：全數通過，包含既有 7 處 map 完全相等斷言（第 63、79、147、174-185、200、252 行）不受影響（`showFooter` 未傳入時被省略，map 內容與修改前完全一致）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-18): FoliateEpubReaderView 新增 showFooter 建構參數"
```

---

### Task 2：`ReaderScreen` 接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1657`（`FoliateEpubReaderView(...)` 建構呼叫，`singleColumn: resolved.singleColumn,` 之後）
- Test: `app/test/screens/reader_screen_test.dart`（擴充既有測試）

**Interfaces:**
- Consumes：`FoliateEpubReaderView.showFooter`（Task 1）、`ResolvedPreferences.showFooter`（既有欄位，`epic-5-toc-pagination` Issue 5）
- Produces：`ReaderScreen._buildNativeView()` 建構 `FoliateEpubReaderView` 時傳入 `showFooter: resolved.showFooter`

- [ ] **Step 1：撰寫失敗測試**

在 `app/test/screens/reader_screen_test.dart`，修改既有的 `'流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView'` 測試（第 196-242 行），在 `await tester.tap(find.byKey(const Key('reader_settings_single_column')));` 與其 `pumpAndSettle` 之後、`final updatedView = ...` 之前，新增：

```dart
    await tester.tap(find.byKey(const Key('reader_settings_single_column')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
    await tester.pumpAndSettle();

    final updatedView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(updatedView.writingMode, WritingMode.vertical);
    expect(updatedView.singleColumn, isTrue);
    expect(updatedView.showFooter, isFalse);
  });
```

（`reader_settings_show_footer` 開關預設為開啟——`ReaderSettingsSheet._showFooter = widget.prefs.showFooter ?? true`，見 `reader_settings_sheet.dart` 既有邏輯——本測試點擊一次即為關閉，`onChanged` 應帶出 `showFooter: false`。）

- [ ] **Step 2：執行測試確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：修改的測試因 `FoliateEpubReaderView.showFooter` 尚未從 `ReaderScreen` 傳入（`updatedView.showFooter` 恆為 `null`）而在 `expect(updatedView.showFooter, isFalse);` 這行失敗。

- [ ] **Step 3：實作接線**

在 `app/lib/screens/reader_screen.dart` 第 1657 行（`singleColumn: resolved.singleColumn,`）之後新增：

```dart
            singleColumn: resolved.singleColumn,
            showFooter: resolved.showFooter,
```

- [ ] **Step 4：執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數通過。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-18): ReaderScreen 接通 showFooter 透傳給 FoliateEpubReaderView"
```

---

### Task 3：`main.js` 直排上下邊距核心邏輯

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Create: `app/integration_test/foliate_margin_test.dart`

**Interfaces:**
- Consumes：`prefs.pageMargins`（既有欄位，`number | undefined`）、`prefs.showFooter`（Task 1/2，`boolean | undefined`）、既有模組變數 `currentWritingMode`
- Produces：`currentWritingMode === 'vertical'` 時，呼叫 `view.renderer.setAttribute('margin-top', '${數字}px')`／`setAttribute('margin-bottom', '${數字}px')`（數值公式見 Global Constraints）；否則呼叫 `setAttribute('margin-top', '48px')`／`setAttribute('margin-bottom', '48px')` 還原內建預設值

- [ ] **Step 1：實作 `main.js` 變更（本檔案無 JS 單元測試，見 Global Constraints，直接實作後以 Step 2 的 `integration_test` 驗證）**

修改 `app/android/app/src/main/assets/foliate/main.js` 的 `window.applyPreferences`（目前在 `singleColumn` 判斷式與最後 `view.renderer.setStyles(...)` 呼叫之間）：

```js
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  // epic-17 Issue 8：劃線/備註繪製需要知道目前實際生效的排版方向，見
  // currentWritingMode 宣告處註解。
  if (prefs.writingMode) {
    currentWritingMode = prefs.writingMode
  }
  // epic-18 Issue 5：強制單欄覆寫（nullable，undefined 時保留 foliate-js
  // 內建 --_max-column-count: 2 的自動判斷行為，不呼叫 setAttribute）。
  // max-column-count 用於 CSS calc() 乘數，非長度屬性，不需 CSS 單位。
  if (prefs.singleColumn === true) {
    view.renderer.setAttribute('max-column-count', '1')
  } else if (prefs.singleColumn === false) {
    view.renderer.setAttribute('max-column-count', '2')
  }
  // epic-18 Issue 4：直排上下邊距。paginator.js 內建 --_margin-top/
  // --_margin-bottom 固定 48px，從未接上使用者 pageMargins 偏好（見
  // docs/epics/epic-18-reader-device-qa/design.md「調查結論」），導致
  // (a) 頂端文字在某些字級/行高組合下被裁切（使用者回報項目 6）、
  // (b) 本文與頁尾間空白過多（項目 7，因為 ReaderFooter 已經是 in-flow
  // 子項壓縮過 WebView 可視高度一次，paginator.js 又在這個已壓縮高度內
  // 再扣一次完整 48px 下邊距，兩者疊加）。用 currentWritingMode（上面
  // 已更新為本次呼叫的最新值）判斷，不用 prefs.writingMode——理由同上方
  // 單欄覆寫註解，prefs.writingMode 在特定呼叫時序下可能是 undefined，
  // currentWritingMode 已保證持有最新已知值。margin-top/margin-bottom
  // 是長度屬性，setAttribute 傳入值必須帶 CSS 單位（純數字會被靜默
  // 忽略，見 spec.md「CSS 單位要求」）。
  if (currentWritingMode === 'vertical') {
    // pageMargins 是既有的頁邊距倍率偏好（body 左右 padding 已使用同一個
    // 值，見 buildOverrideCss()），未設定時（prefs.pageMargins 非數字）
    // 以 1（既有 UI 滑桿中性初始位置對應的倍率）當基準。
    const marginMultiplier = typeof prefs.pageMargins === 'number' ? prefs.pageMargins : 1
    // 上邊距：以內建預設值 48px 為基準放大約 1.33 倍（起始建議值，見
    // Global Constraints），解決「頂端文字被裁切」；隨 pageMargins 倍率
    // 同步縮放，使用者可再依需要調整。
    const marginTopPx = Math.round(64 * marginMultiplier)
    // 下邊距：頁尾顯示時（prefs.showFooter !== false，涵蓋 true 與
    // undefined 兩種「視同顯示」情況）只需要小幅視覺緩衝（16px 起始
    // 建議值），避免在已經被頁尾壓縮過的可視高度內再扣一次完整邊距；
    // 頁尾明確隱藏時（prefs.showFooter === false）沒有頁尾提供視覺
    // 邊界，改用與上邊距相同的較大緩衝，避免文字貼齊螢幕底緣。
    const marginBottomPx = prefs.showFooter === false
      ? Math.round(64 * marginMultiplier)
      : Math.round(16 * marginMultiplier)
    view.renderer.setAttribute('margin-top', `${marginTopPx}px`)
    view.renderer.setAttribute('margin-bottom', `${marginBottomPx}px`)
  } else {
    // 橫排：還原 paginator.js 內建預設值。setAttribute 具持久性（不會
    // 隨排版方向切換自動歸零/還原），若省略這個 else 分支，使用者從
    // 直排切回橫排後會殘留直排時設定的邊距值，違反「橫排不受本 Issue
    // 影響」的驗收標準。
    view.renderer.setAttribute('margin-top', '48px')
    view.renderer.setAttribute('margin-bottom', '48px')
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}
```

- [ ] **Step 2：撰寫開書 smoke test（`integration_test`，需真機/模擬器）**

新增 `app/integration_test/foliate_margin_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// 比照 app/integration_test/foliate_epub_reader_view_test.dart 既有的
/// _stageAssetAsFile 手法。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 18 Issue 4：直排上下邊距——真機 smoke test。
///
/// 本檔案**不能**驗證「文字是否真的沒被裁切」這類視覺結果（`main.js` 的
/// `setAttribute` 呼叫無法從 Dart 端讀回渲染後的實際邊距，見
/// plan-issue-4.md Global Constraints），只驗證：不同 writingMode／
/// pageMargins／showFooter 組合下，main.js 新增的 setAttribute 呼叫本身
/// 不會拋出例外、不會導致開書失敗（onError）。實際視覺效果由
/// plan-issue-4.md Task 4 的真機人工確認負責。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('直排、預設 pageMargins／showFooter（皆省略）開書不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_default.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          writingMode: WritingMode.vertical,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });

  testWidgets('直排、自訂 pageMargins 且 showFooter=false（隱藏頁尾分支）開書不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_hidden_footer.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          writingMode: WritingMode.vertical,
          pageMargins: 1.6667,
          showFooter: false,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });

  testWidgets('橫排（還原預設邊距分支）開書不崩潰', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub', 'margin_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          writingMode: WritingMode.horizontal,
          showFooter: true,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '開書過程不應觸發 onError，但收到: $errorMessage');
  });
}
```

- [ ] **Step 3：於真機/模擬器執行新測試確認通過**

```bash
flutter devices
flutter test integration_test/foliate_margin_test.dart -d 3CEF42ECD491687
```

Expected：3 個測試皆通過（`onError` 皆為 `null`）。若任一測試因 `onError` 觸發而失敗，先確認是否為 `setAttribute` 傳入值格式錯誤（例如漏了 `px` 單位字尾——但如 Global Constraints 所述，格式錯誤通常是**靜默**失敗、不會觸發 `onError`，若這裡真的觸發 `onError` 反而代表有其他更嚴重的問題，例如 JS 語法錯誤）。

- [ ] **Step 4：跑既有 `foliate_epub_reader_view_test.dart`／`foliate_toc_footer_test.dart` integration test 確認無回歸**

```bash
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687
```

Expected：全數通過（`main.js` 的變更是新增獨立的 `if/else` 分支，不影響既有 `pageTurnMode`/`writingMode`/`singleColumn` 分支的既有行為）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/integration_test/foliate_margin_test.dart
git commit -m "feat(epic-18): main.js applyPreferences 新增直排上下邊距 setAttribute 邏輯"
```

---

### Task 4：真機驗收——頂端裁切／頁尾間距症狀消除，橫排不受影響

**Files:** 無程式碼異動（純驗收，`issues.md` Issue 4 驗收標準要求的真機確認）

**Interfaces:**
- Consumes：Task 1-3 已 commit 的完整上下邊距管線
- Produces：驗收結論，供人類決定是否合併；若視覺效果不理想，記錄具體觀察與建議調整值（對應 Global Constraints「起始建議值」）交由人類決定是否回頭調整 Task 3 的數值公式

- [x] **Step 1：建置並安裝 debug APK 到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
adb devices -l
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：`adb devices -l` 列出 `3CEF42ECD491687`；建置與安裝皆成功（`Success`）。

- [x] **Step 2：確認直排頂端裁切症狀消除**

開一本直排 EPUB（或透過版面設定將既有書籍手動切換為直排），嘗試多種字級/行高組合（`reader_settings_font_size`／`reader_settings_line_height` 滑桿），確認畫面頂端文字不再被裁切/壓字（使用者回報項目 6：「上面會壓到字」）。

Expected：頂端文字完整可見，肉眼可辨識比修改前有更明顯的留白空間。

- [x] **Step 3：確認本文與頁尾間空白過多症狀消除（頁尾顯示情境）**

確認「顯示頁尾」開關為開啟（`reader_settings_show_footer`），直排開書，捲動/翻頁到含有較多文字的頁面，確認本文最後一行與頁尾進度列之間**不再有明顯多餘空白**（不要求數學上完全零間距，只要求「約一行」的過多空白症狀消除，比照 `issues.md` 驗收標準原文）。

Expected：本文與頁尾之間僅剩小幅、合理的視覺緩衝，不再有肉眼明顯可辨識的「多一行」空白。

- [x] **Step 4：確認頁尾隱藏時下邊距合理（不貼齊螢幕底緣）**

關閉「顯示頁尾」開關（`reader_settings_show_footer`），直排開書，確認本文最後一行與螢幕底緣之間仍保留合理留白，文字不會貼齊螢幕邊緣。

Expected：頁尾隱藏時的下邊距明顯大於頁尾顯示時的下邊距（比照 Task 3 的公式：`64px` 起始建議值 vs `16px` 起始建議值，皆乘上 `pageMargins` 倍率），視覺上不會有文字緊貼螢幕邊緣的問題。

- [x] **Step 5：橫排模式回歸確認**

切換回橫排閱讀同一本書（或開啟一本橫排既定行為的一般 EPUB），確認畫面上下邊距與修改前一致（無變化），驗證「橫排不受本 Issue 影響」的既定行為未被意外改動。額外確認：先切到直排（邊距套用新邏輯）、再切回橫排，確認邊距正確還原（不殘留直排時的邊距設定值，驗證 Global Constraints 提到的 `else` 分支還原邏輯正確生效）。

Expected：橫排模式視覺上與修改前完全一致；直排→橫排切換後邊距正確還原，無殘留。

- [x] **Step 6：若視覺效果不理想，記錄具體觀察**

若 Step 2-4 任一項視覺效果不理想（例如上邊距仍嫌不足、或下邊距仍偏大/偏小），記錄具體觀察與建議調整的數值（例如「上邊距建議由 64px 提高到 80px」），交由人類決定是否回頭調整 Task 3 的 `main.js` 起始建議值常數（`64`／`16` 兩個乘數基準）。

無需 commit（本 Task 純驗收，不變更任何檔案，除非 Step 6 發現需要調整起始建議值並經人類確認後才回頭修改 Task 3 程式碼）。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「`main.js` 上下邊距組裝」段落的三個要求——(1) `buildOverrideCss` 維持純函式、`setAttribute` 呼叫加在 `applyPreferences` 內、(2) `setAttribute` 值須帶 CSS 單位、(3) 下邊距需考慮 `ReaderFooter` 實際佔用高度避免重複扣除——分別對應 Task 3 的實作與 Global Constraints 的對應說明；`issues.md` Issue 4 描述的兩個異動點（`main.js` 上下邊距 `setAttribute`、底部邊距避免與頁尾重複扣除）對應 Task 3；「若需要新增/調整 Dart 端偏好欄位」這個條件式的單元測試要求，在本計劃中對應到 Task 1 新增的 `showFooter` 建構參數（並非新增 `BookReaderPrefs` 欄位，而是既有欄位多一層透傳，仍比照既有欄位新增時的 widget test 模式提供測試覆蓋）。
- **無佔位符掃描**：所有 Task 皆附完整可執行的程式碼（`main.js` 完整 before/after、Dart 檔案完整片段、測試完整程式碼、完整 `flutter`/`adb`/`git` 指令），無 "TODO"/"視情況" 字樣。`issues.md`/`spec.md` 原文刻意留給實作階段決定的開放式描述（上下邊距具體數值/公式、是否需要動態依 `showFooter` 調整）皆已在 Global Constraints 中做出具體、可執行的落地決定（`64px`/`16px` 起始建議值 + `showFooter` 三態判斷公式）。撰寫 Task 3 的 `integration_test` 草稿時初版曾誤用一個混用不存在 API、未被任何測試呼叫的 helper 函式，複查後已直接移除，目前三個 `testWidgets` 區塊皆各自用標準的 `tester.pumpWidget`/`tester.pumpAndSettle` 完整寫法、彼此獨立，程式碼可直接照抄無需再自行刪減。
- **型別/介面一致性**：`FoliateEpubReaderView.showFooter`（`bool?`，Task 1）→ `reader_screen.dart` 的 `showFooter: resolved.showFooter`（Task 2，`ResolvedPreferences.showFooter` 為非 nullable `bool`，隱式轉為 `bool?` 合法）→ `main.js` 的 `prefs.showFooter`（Task 3，`boolean | undefined`）三層命名與型別語意一致；`main.js` 內 `currentWritingMode`／`prefs.pageMargins`／`prefs.showFooter` 三個判斷來源的既有/新增語意（何時該讀哪個變數）已在 Global Constraints 逐一說明依據，避免與 Issue 5 既有的 `singleColumn` 判斷式（同樣位於 `applyPreferences` 內、緊鄰新程式碼）在維護時被誤改或搞混判斷來源。

---

## Execution Handoff

Plan complete and saved to `docs/epics/epic-18-reader-device-qa/plans/plan-issue-4.md`. Two execution options:

1. **Subagent-Driven (recommended)** — 逐一 Task 派出新的 subagent 執行，每個 Task 之間進行審查、快速迭代。
2. **Inline Execution** — 在目前 session 中依序執行，批次執行並在檢查點暫停確認。

要採用哪一種？
