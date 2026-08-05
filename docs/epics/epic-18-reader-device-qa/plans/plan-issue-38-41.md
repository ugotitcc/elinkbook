# Issue 38-41 實作計劃：真機 WebView 相容性與時序問題（`/diagnose` 第五輪）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 `/diagnose` 第五輪查明的 4 個真機回報根因（ViWoods Air Reader C 開書不穩定、iReader Ocean 4 Plus 開書逾時），皆屬 `epic-18-reader-device-qa`。

**Architecture:** 全部改動集中在 `app/lib/reader/foliate_epub_reader_view.dart`（Dart 端嵌入的 JS 常數字串，透過 `initialUserScripts` 於 `AT_DOCUMENT_START` 注入）、`app/android/app/src/main/assets/foliate/main.js`（本專案自己的 JS↔Dart 膠水層，非 vendored 檔案，可修改）、`app/android/app/src/main/assets/foliate/index.html`、`app/tool/check_foliate_es_compat.js`（開發輔助掃描腳本）。**不修改** `readest/foliate-js` 釘定 vendor 檔案本身（`view.js`／`epub.js`／`paginator.js`／`epubcfi.js` 等，見 ADR 0011「不修改釘定版本」）。

**Tech Stack:** Flutter/Dart、`flutter_inappwebview`、`readest/foliate-js`（vendored ES module）、Node.js（`app/tool/` 開發輔助腳本，非 App 本體）。

## Global Constraints

- 提交前 `flutter analyze` 必須乾淨（"No issues found!"）。
- 每個 Task 完成後跑一次全專案 `flutter test`（不只跑該 Task 新增的測試檔），確認零回歸。
- 所有程式碼註解與 commit message 使用正體中文（專有名詞/API 名稱維持英文原文）。
- `app/android/app/src/main/assets/foliate/` 底下，只有 `main.js`／`index.html` 是本專案自己的膠水層檔案，可以修改；其餘 `.js` 檔案（`view.js`／`epub.js`／`paginator.js`／`epubcfi.js`／`overlayer.js`／`fixed-layout.js`／`construct-style-sheets-polyfill.js` 等）是 `readest/foliate-js` 釘定 commit 的原始複製，**絕對不可修改**。
- `_esCompatPolyfillJs`／新增的任何 polyfill 本體程式碼，**禁止使用 ES2020 之後才有的語法糖**（包括但不限於邏輯賦值運算子 `??=`／`||=`／`&&=`，Chromium 85+ 才支援）——這份腳本存在的唯一目的就是在不支援新語法的舊版 WebView 上執行，若用了新語法糖，會在解析階段（parse time）讓整個腳本失敗，等於完全沒有防護效果（見 Task 1 的根因說明）。
- 每個 Task 各自一個 commit，commit message 開頭比照既有慣例 `fix(epic-18): Issue <N> — <一句話摘要>`。

---

### Task 1: Issue 38 — `_esCompatPolyfillJs` 自身使用 `??=` 導致 Chromium <85 整份腳本解析失敗

**背景（本計劃撰寫過程中新發現，優先度最高）：** `_esCompatPolyfillJs`（`app/lib/reader/foliate_epub_reader_view.dart:47-86`）的 `Object.groupBy` polyfill 本體用了 `(result[key] ??= []).push(item);`（邏輯 nullish 賦值運算子，ES2021，需 Chromium 85+）。JS 引擎在**執行任何程式碼之前**會先完整解析（parse）整個腳本；若腳本中任何一處使用了引擎不認得的語法，會在解析階段直接拋出 `SyntaxError`，導致**整個腳本完全不會執行**——不只是 `Object.groupBy` 那個 if 區塊，連同一份腳本裡的 `Map.groupBy`／`Array.prototype.at`／`Array.prototype.findLastIndex` 三個 polyfill 也全部一起失效。iReader Ocean 4 Plus 的系統 WebView 版本為 Chromium 83（已從真機「關於」畫面截圖確認），早於 85，代表**前兩輪 `/diagnose` 已經「修好」的這 4 個 API polyfill，在這台裝置上其實從未真正生效過**——這很可能是它持續回報「開書逾時」的核心原因之一。

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`（`_esCompatPolyfillJs` 常數，約第 47-86 行）
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：無（純字串常數內容修改，不影響任何函式簽章）。
- Produces：`_esCompatPolyfillJs` 常數內容不再含有 `??=`／`||=`／`&&=` 這三種運算子字面文字，供本 Task 自己的測試斷言使用。

- [x] **Step 1: 寫失敗測試——斷言 polyfill 腳本不含邏輯賦值運算子**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 找到既有的「ES 相容性 polyfill（診斷修正）」`group`（搜尋 `ES 相容性 polyfill`），在該 group 內新增一個測試（放在既有的 polyfill 內容測試附近即可，不需要動到 `initialUserScripts` 相關的既有測試）：

```dart
    testWidgets(
        'ES compat polyfill 本體不含邏輯賦值運算子（??=／||=／&&=），'
        '避免 Chromium 85 之前的 WebView 在解析階段整份腳本失敗'
        '（epic-18-reader-device-qa Issue 38，真機使用回報：iReader Ocean 4 '
        'Plus 系統 WebView 為 Chromium 83，早於 ??= 語法需要的 Chromium 85，'
        'JS 引擎會在執行任何程式碼之前完整解析整份腳本，任何一處語法錯誤都會讓'
        '整份腳本（含 Object.groupBy／Map.groupBy／Array.prototype.at／'
        'Array.prototype.findLastIndex 全部 4 個 polyfill）完全不執行）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(polyfillScript.source, isNot(contains('??=')));
      expect(polyfillScript.source, isNot(contains('||=')));
      expect(polyfillScript.source, isNot(contains('&&=')));
    });
```

（`_noop`／`_noopError` 是本檔案既有的頂層測試輔助函式，直接沿用；不需要新增。）

- [x] **Step 2: 執行測試確認失敗**

```bash
cd app
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "邏輯賦值運算子"
```

預期失敗：`Expected: not contains '??='` 斷言失敗（因為目前 `_esCompatPolyfillJs` 確實含有 `??=`）。

- [x] **Step 3: 修正 `_esCompatPolyfillJs`，改用 ES5 相容語法改寫 `Object.groupBy` polyfill**

打開 `app/lib/reader/foliate_epub_reader_view.dart`，找到：

```dart
if (!Object.groupBy) {
  Object.groupBy = function (items, keyFn) {
    const result = Object.create(null);
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      (result[key] ??= []).push(item);
    }
    return result;
  };
}
```

改為：

```dart
if (!Object.groupBy) {
  Object.groupBy = function (items, keyFn) {
    const result = Object.create(null);
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      if (!result[key]) result[key] = [];
      result[key].push(item);
    }
    return result;
  };
}
```

（`Map.groupBy` polyfill 本來就沒用到 `??=`，不需要改；同一份腳本內其餘 `Array.prototype.at`／`Array.prototype.findLastIndex` 也沒有這個問題。）

一併在 `_esCompatPolyfillJs` 常數上方的既有文件註解（第 25-46 行）補一段，記錄這個新發現的自身相容性限制（比照既有段落風格，接在既有說明段落之後）：

```dart
///
/// 【epic-18-reader-device-qa Issue 38，2026-08-05 追加發現】本腳本自身
/// 曾在 `Object.groupBy` polyfill 內用了 `??=`（邏輯 nullish 賦值，ES2021，
/// 需 Chromium 85+）——JS 引擎會在執行任何程式碼之前完整解析整份腳本，
/// 任何一處語法錯誤都會讓整份腳本（含本檔案其餘 3 個 polyfill）完全不
/// 執行。iReader Ocean 4 Plus 的系統 WebView 為 Chromium 83（早於 85），
/// 代表上面 4 個 polyfill 在這台裝置上其實從未真正生效過。已改寫為
/// ES5 相容語法（`if (!x) x = []` 取代 `x ??= []`）。**本腳本後續新增的
/// 任何 polyfill 本體，禁止使用 ES2020 之後的語法糖**（包括 `??=`／`||=`／
/// `&&=`／選用鏈結 `?.` 需 Chromium 80+、標籤模板等），因為這份腳本存在
/// 的唯一目的就是在不支援新語法的舊版 WebView 上執行。
```

- [x] **Step 4: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "邏輯賦值運算子"
```

預期：`All tests passed!`

- [x] **Step 5: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
flutter analyze
```

預期：兩者皆乾淨。

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-18): Issue 38 — 修正 ES compat polyfill 自身使用 ??= 導致 Chromium <85 整份腳本解析失敗"
```

---

### Task 2: Issue 39 — `window.applyPreferences` 過早呼叫的競速（ViWoods 真機回報，`Uncaught TypeError: window.applyPreferences is not a function`）

**背景：** `foliate_epub_reader_view.dart` 的 `didUpdateWidget()`（約第 567-575 行）只要 `foliatePreferencesChanged(oldWidget, widget)` 為真（例如 `isLandscape` 因螢幕方向鎖定套用時機、`isFixedLayoutHint` 因既有書籍的非同步 FXL 判斷完成而改變），就會呼叫 `_evaluate('window.applyPreferences(...)')`。這個呼叫完全沒有檢查 `main.js`（ES module，`index.html` 用 `<script type="module" src="./main.js">` 載入）是否已經執行完成、真正定義出 `window.applyPreferences`——這是純 Dart 端狀態變動觸發的呼叫，跟 WebView／JS module 是否載入完成完全無關，時機上必然存在競速。真機 LOG 顯示的 `Uncaught TypeError: window.applyPreferences is not a function` 精確對應這個成因。

**修法：** 透過 `initialUserScripts` 在 `AT_DOCUMENT_START`（比 `main.js` 更早）注入一個佔位 shim，把 `window.applyPreferences` 暫時定義成「只是把傳入的偏好值存起來，不做任何事」；`main.js` 真正的 `window.applyPreferences = function (prefs) {...}` 賦值執行時（這個賦值會直接覆蓋掉 shim），緊接著檢查有沒有暫存的待套用值，有的話立刻補套用一次。這樣不論 Dart 端呼叫發生在 `main.js` 載入完成前後，都不會出錯，也不會遺漏。

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：無新增 Dart 型別；沿用既有 `UserScript`／`UserScriptInjectionTime.AT_DOCUMENT_START` 機制（Task 1 不動這部分）。
- Produces：`initialUserScripts` 陣列從 3 個腳本變成 4 個（Task 1 之後 `scripts!.first` 仍是 ES compat polyfill 不變，但 `scripts` 長度斷言需要同步更新，見 Step 4）。新增常數 `_applyPreferencesQueueShimJs`。

- [x] **Step 1: 寫失敗測試——斷言新腳本已注入且內容正確**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 的「ES 相容性 polyfill（診斷修正）」group 內新增：

```dart
    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入 applyPreferences 佇列 shim，'
        '避免 main.js 尚未載入完成前呼叫 window.applyPreferences 拋出 '
        'TypeError（epic-18-reader-device-qa Issue 39，真機使用回報：'
        'ViWoods Air Reader C，Uncaught TypeError: window.applyPreferences '
        'is not a function）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, hasLength(4));
      final shimScript = scripts![1];
      expect(
          shimScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(shimScript.source, contains('window.__pendingApplyPreferences'));
      expect(shimScript.source, contains('window.applyPreferences'));
    });
```

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "applyPreferences 佇列 shim"
```

預期失敗：`hasLength(4)` 斷言失敗（目前是 3）。

- [x] **Step 3: 新增 `_applyPreferencesQueueShimJs` 常數並接線**

在 `app/lib/reader/foliate_epub_reader_view.dart` 的 `_esCompatPolyfillJs` 常數之後（Task 1 已修改過的那個常數）、`_globalErrorCaptureJs` 常數之前，插入：

```dart
/// `window.applyPreferences` 過早呼叫佇列 shim（epic-18-reader-device-qa
/// Issue 39，真機使用回報：ViWoods Air Reader C，`Uncaught TypeError:
/// window.applyPreferences is not a function`）。`didUpdateWidget()`
/// （見下方）只要 Dart 端偏好狀態變動（例如螢幕方向鎖定套用、既有書籍的
/// 非同步 FXL 判斷完成）就會呼叫 `window.applyPreferences(...)`，這個呼叫
/// 跟 `main.js`（ES module）是否已載入完成、真正定義出這個函式完全無關，
/// 時機上必然存在競速。在 `AT_DOCUMENT_START`（比 `main.js` 更早）注入這個
/// 佔位 shim，把 `window.applyPreferences` 暫時定義成「先把傳入值存起
/// 來」；`main.js` 真正的賦值執行時會直接覆蓋掉這個 shim，並緊接著檢查
/// 有沒有暫存值、有的話立刻補套用（見 main.js 對應修改）。不論 Dart 端
/// 呼叫發生在 main.js 載入完成前後都不會出錯、也不會遺漏。
const _applyPreferencesQueueShimJs = '''
window.__pendingApplyPreferences = null;
window.applyPreferences = function (prefs) {
  window.__pendingApplyPreferences = prefs;
};
''';
```

找到 `initialUserScripts: UnmodifiableListView<UserScript>([...])`（build 方法內），在 `_esCompatPolyfillJs` 的 `UserScript` 之後、`_globalErrorCaptureJs` 的 `UserScript` 之前插入：

```dart
            UserScript(
              source: _applyPreferencesQueueShimJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
```

（沿用既有的簡短說明性註解風格，例如「epic-18-reader-device-qa Issue 39：見上方 _applyPreferencesQueueShimJs 註解」，比照 `_globalErrorCaptureJs`/`_userAgentLogJs` 那兩個 `UserScript` 前面各自的既有單行/兩行註解寫法。）

- [x] **Step 4: 修正既有 3 個 `hasLength(3)` 斷言為 `hasLength(4)`，並修正受影響的索引**

`app/test/reader/foliate_epub_reader_view_test.dart` 目前有 3 處 `expect(scripts, hasLength(3));`（分別對應：polyfill 測試、全局 JS 錯誤捕捉測試、navigator.userAgent 測試）。新腳本插入在索引 1（原本索引 1 是 `_globalErrorCaptureJs`，順移到索引 2；原本索引 2 的 `_userAgentLogJs` 順移到索引 3）。逐一修正：

1. polyfill 測試（用 `scripts!.first`，索引 0 不變）：`hasLength(3)` → `hasLength(4)`，其餘不動。
2. 全局 JS 錯誤捕捉測試（原本用 `scripts![1]`）：`hasLength(3)` → `hasLength(4)`，`scripts![1]` → `scripts![2]`。
3. navigator.userAgent 測試（用 `scripts!.last`，`.last` 語意不受索引順移影響，本來就會自動指向新的最後一個）：`hasLength(3)` → `hasLength(4)`，其餘不動。

- [x] **Step 5: 修改 `main.js`，在真正的 `applyPreferences` 定義後補上佇列 flush 邏輯**

打開 `app/android/app/src/main/assets/foliate/main.js`，找到 `window.applyPreferences = function (prefs) {` 開頭的區塊（約第 130 行起），在該函式定義結束的右大括號 `}` 之後（即 `window.applyPreferences = function (prefs) { ... }` 整個賦值陳述式結束後），緊接著加入：

```js
// epic-18-reader-device-qa Issue 39：main.js 這個 ES module 執行到這裡時
// 才「真正」定義出 window.applyPreferences，覆蓋掉 AT_DOCUMENT_START 階段
// 注入的佔位 shim（見 foliate_epub_reader_view.dart 的
// _applyPreferencesQueueShimJs）。若 Dart 端在這之前已經呼叫過一次（被
// shim 接住、存進 window.__pendingApplyPreferences），這裡立刻補套用一次，
// 避免那次呼叫被靜默遺漏。
if (window.__pendingApplyPreferences) {
  const pendingPrefs = window.__pendingApplyPreferences
  window.__pendingApplyPreferences = null
  window.applyPreferences(pendingPrefs)
}
```

- [x] **Step 6: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "applyPreferences 佇列 shim"
```

預期：`All tests passed!`

- [x] **Step 7: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
flutter analyze
```

- [x] **Step 8: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-18): Issue 39 — window.applyPreferences 過早呼叫佇列 shim，修正 main.js 載入完成前的競速"
```

---

### Task 3: Issue 40 — `<script type="module">` 補上 `crossorigin="anonymous"`，改善診斷可讀性

**背景：** ViWoods Air Reader C 真機截圖顯示我方 `window.onerror` 診斷畫面（Issue 33）只顯示「JS Error: Script error. (:0)」，完全看不出真正原因；但同一時間點的瀏覽器 console log 卻能看到完整訊息（`Uncaught TypeError: window.applyPreferences is not a function`，即 Task 2 的錯誤）。這是瀏覽器對某些情況下的 script 標準錯誤訊息改寫行為；`index.html` 的 `<script type="module" src="./main.js">` 目前沒有 `crossorigin` 屬性。已用桌機 Edge + 同源 HTTP server 實測：純同源情況下這個改寫不會發生，故確切機制應與 Android WebView 的 `WebViewAssetLoader`／`shouldInterceptRequest` 合成回應方式有關（已知的 Android WebView 怪癖類別），無法在本機環境完全重現細節。`crossorigin="anonymous"` 是這類問題的標準建議做法，且在真正同源時沒有任何負面作用，值得一試——**這是改善診斷能力的低風險嘗試，不保證是根因，Task 2 才是有確切錯誤訊息比對的根因**。

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/index.html`

**Interfaces:** 無（純靜態 HTML 屬性修改，不影響任何 Dart/JS 介面）。

- [x] **Step 1: 修改 `index.html`**

```html
<script type="module" src="./main.js" crossorigin="anonymous"></script>
```

- [x] **Step 2: 無自動化測試 seam——如實記錄**

`index.html` 是純靜態資源，`app/test/` 沒有任何測試會實際載入並解析這個檔案（既有 widget test 用 `FakePlatformInAppWebViewWidget`，不會真正渲染 WebView 內容）。這是本 Task 唯一沒有測試覆蓋的项目，比照 Issue 34（`main.js` 的 `buildOverrideCss()`）已有的先例，在 `issues.md` 對應段落如實記錄「無自動化測試 seam，需未來真機／`chrome://inspect` 遠端除錯或使用者截圖驗證這個屬性是否真的讓 Issue 33 診斷畫面顯示出完整錯誤訊息」。

- [x] **Step 3: `flutter analyze` 確認無回歸（本 Task 不改 Dart 檔案，純粹確認流程完整）**

```bash
flutter analyze
```

- [x] **Step 4: Commit**

```bash
git add app/android/app/src/main/assets/foliate/index.html
git commit -m "fix(epic-18): Issue 40 — main.js 模組腳本補上 crossorigin=anonymous，改善診斷畫面錯誤訊息可讀性"
```

---

### Task 4: Issue 41 — `epub.js`／`view.js` 使用的 `replaceAll`／`WeakRef` 未設防 + 更新相容性掃描工具

**背景：** 逐字掃描已 vendored 的 `epub.js`／`view.js`，發現兩處尚未設防的較新 API：

- `epub.js:711,716`：`String.prototype.replaceAll`（ES2021，需 Chromium 85+）——用於 `deobfuscators`（IDPF 字型混淆／Adobe 字型混淆的 key 推導），**只在書籍含有混淆內嵌字型時才會執行到**，非每本書都會觸發。
- `view.js:286`：`new WeakRef(el)`（ES2021，需 Chromium 84+）——用於 EPUB Media Overlays（有聲書同步標色）的「最後啟用元素」追蹤，**只在書籍含有 media overlay 時才會執行到**。

iReader Ocean 4 Plus 的系統 WebView 為 Chromium 83，兩者皆不支援。這跟前兩輪已修過的 `Object.groupBy`／`Array.prototype.at`／`findLastIndex` 是同一類問題，只是範圍較窄（特定書籍功能，非通用開書路徑）；`check_foliate_es_compat.js` 目前的靜態掃描清單（`RISKY_APIS`）還沒涵蓋這兩個 API，一併補上避免未來再靠人工逐字掃描才發現。

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`（`_esCompatPolyfillJs` 常數）
- Modify: `app/tool/check_foliate_es_compat.js`（`RISKY_APIS` 陣列）
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 1 修正後的 `_esCompatPolyfillJs`（本 Task 在其尾端追加兩個新的 `if` 防護區塊，維持 Task 1 立下的「禁止 ES2020+ 語法糖」約束）。
- Produces：`_esCompatPolyfillJs` 新增 `String.prototype.replaceAll`／`WeakRef` 兩個 polyfill 標記字串，供 `check_foliate_es_compat.js` 的 `polyfillMarkers` 比對。

- [x] **Step 1: 寫失敗測試——斷言新 polyfill 已加入**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 的「ES 相容性 polyfill（診斷修正）」group 內新增：

```dart
    testWidgets(
        'ES compat polyfill 含 String.prototype.replaceAll／WeakRef 防護'
        '（epic-18-reader-device-qa Issue 41，iReader Ocean 4 Plus 系統 '
        'WebView 為 Chromium 83，早於 replaceAll 需要的 85／WeakRef 需要的 '
        '84，epub.js 的字型反混淆與 view.js 的 media overlay 功能會用到）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(polyfillScript.source, contains('String.prototype.replaceAll'));
      expect(polyfillScript.source, contains('WeakRef'));
    });
```

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "replaceAll／WeakRef 防護"
```

- [x] **Step 3: 在 `_esCompatPolyfillJs` 尾端（`Array.prototype.findLastIndex` 區塊之後、結尾 `''';` 之前）追加兩個防護區塊**

```dart
if (!String.prototype.replaceAll) {
  String.prototype.replaceAll = function (search, replacement) {
    if (search instanceof RegExp) {
      if (!search.global) {
        throw new TypeError('replaceAll must be called with a global RegExp');
      }
      return this.replace(search, replacement);
    }
    return this.split(search).join(
      typeof replacement === 'function' ? replacement : String(replacement)
    );
  };
}
if (typeof WeakRef === 'undefined') {
  window.WeakRef = function (target) {
    this._target = target;
  };
  window.WeakRef.prototype.deref = function () {
    return this._target;
  };
}
```

（`replaceAll` 的字串取代分支同時支援字串與函式型 `replacement`，比照原生 `String.prototype.replace` 語意；`WeakRef` polyfill 用一般強參照模擬——沒有真正的「弱」語意，會讓 `view.js:286` 那個單一插槽的 `lastActive` 變數多保留一個 DOM 元素參照直到下一次 `highlight` 事件覆寫掉它，範圍有限、可接受，換取避免 `ReferenceError` 直接崩潰。）

在 `_esCompatPolyfillJs` 上方文件註解（Task 1 已經加過一段）之後，再補一段記錄這兩個新增防護：

```dart
///
/// 【epic-18-reader-device-qa Issue 41】`epub.js` 的字型反混淆
/// （`deobfuscators`）用了 `String.prototype.replaceAll`（ES2021，需
/// Chromium 85+）；`view.js` 的 Media Overlays 用了 `WeakRef`（ES2021，需
/// Chromium 84+）。iReader Ocean 4 Plus 的 Chromium 83 兩者皆不支援。兩者
/// 皆只在特定書籍功能（含混淆內嵌字型／含 media overlay）才會執行到，非
/// 通用開書路徑，故不像 Task 38 的 `??=` 語法解析失敗那樣影響「每一本
/// 書」，但仍是真實存在的崩潰風險，一併補上防護。
```

- [x] **Step 4: 更新 `app/tool/check_foliate_es_compat.js` 的 `RISKY_APIS` 清單**

在 `RISKY_APIS` 陣列（`Array.fromAsync` 那個物件之後，陣列結尾 `];` 之前）追加：

```js
  {
    name: 'String.prototype.replaceAll',
    usagePattern: /\.replaceAll\(/g,
    polyfillMarkers: ['String.prototype.replaceAll'],
    minChromium: 85,
    specYear: 'ES2021',
  },
  {
    name: 'WeakRef',
    usagePattern: /\bnew WeakRef\(/g,
    polyfillMarkers: ['WeakRef'],
    minChromium: 84,
    specYear: 'ES2021',
  },
```

- [x] **Step 5: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "replaceAll／WeakRef 防護"
```

- [x] **Step 6: 執行相容性掃描工具，確認回報乾淨（驗證新掃描規則正確比對到 Step 3 補上的 polyfill）**

```bash
node app/tool/check_foliate_es_compat.js
```

預期輸出：`[check_foliate_es_compat] 乾淨——目前已知的較新 ES 內建方法用法都已有對應 polyfill 防護。`，結束碼 0。

（若想額外驗證掃描規則本身「找得到」用法而非誤判為零筆，可暫時把 Step 3 加入的兩個 polyfill 區塊註解掉、重跑一次這支工具，確認它會回報 `epub.js:711`／`epub.js:716`／`view.js:286` 三筆 finding，再取消註解、確認恢復乾淨。這步驟純粹是實作時的人工驗證，不需要寫進自動化測試。）

- [x] **Step 7: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
flutter analyze
```

- [x] **Step 8: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/tool/check_foliate_es_compat.js app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-18): Issue 41 — 補上 String.prototype.replaceAll／WeakRef polyfill，更新相容性掃描工具清單"
```

---

### Task 5: 全專案回歸驗證 + 文件收尾

**Files:**
- Modify: `docs/epics/epic-18-reader-device-qa/issues.md`（新增 Issue 38-41 區塊，比照既有 Issue 34-36／37 段落格式）
- Modify: `docs/epics.md`（epic-18 列備註新增本輪摘要）

- [x] **Step 1: 跑全專案 `flutter test`，確認總數較 Task 開始前只增加本計劃新增的測試數、其餘全數通過**

```bash
flutter test
```

- [x] **Step 2: 跑 `flutter analyze`，確認乾淨**

```bash
flutter analyze
```

- [x] **Step 3: 更新 `issues.md`**，比照既有「Issue 34-36」／「Issue 37」段落格式，新增「Issue 38-41」區塊，內容涵蓋：
  - Issue 38：`??=` 導致舊 WebView 整份 polyfill 腳本解析失敗（本計劃撰寫過程中發現，非原始回報項目，說明清楚這點）。
  - Issue 39：`applyPreferences` 過早呼叫競速（ViWoods 真機回報，附精確錯誤訊息比對）。
  - Issue 40：`crossorigin` 屬性補強（診斷能力改善，非確認根因，如實記錄未驗證的部分）。
  - Issue 41：`replaceAll`／`WeakRef` polyfill + 掃描工具更新。
  - 單元測試要求／驗收標準／相關佐證（截圖檔名：`tmp/images/JSScript.jpg`／`tmp/images/iReader1.jpg`／`tmp/images/iReader2.jpg`）。

- [x] **Step 4: 更新 `docs/epics.md`** 的 epic-18 列備註，比照既有段落風格，接續 Issue 37 之後補上本輪摘要一句話。

- [x] **Step 5: Commit**

```bash
git add docs/epics/epic-18-reader-device-qa/issues.md docs/epics.md
git commit -m "docs(epic-18): 記錄 Issue 38-41（真機 WebView 相容性與時序問題，/diagnose 第五輪）"
```

---

## 執行順序與注意事項

- Task 1（Issue 38）**必須排在最前面**——它是本輪影響範圍最大、確信度最高的發現，且後續 Task 4 會在同一份 `_esCompatPolyfillJs` 常數尾端追加內容，先把 Task 1 的語法問題修乾淨可避免疊加修改時的合併衝突。
- Task 2（Issue 39）與 Task 4（Issue 41）都會修改 `_esCompatPolyfillJs`／`initialUserScripts`，建議依序（Task 1 → 2 → 3 → 4）進行，不要平行處理，避免同一個常數/陣列的多處編輯互相打架。
- Task 3（Issue 40）與其他 Task 完全獨立（只動 `index.html`），可以在任意順序穿插執行。
- 全部 4 個 Task 完成、且 Task 5 的全專案回歸驗證通過後，才發起程式碼審查（`/superpowers:requesting-code-review`）與 PR，比照本 Epic 既有的「一輪真機回報 = 一個分支 = 多個 commit = 一個 PR」慣例。
