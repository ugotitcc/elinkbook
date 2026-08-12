# Epic 22 Issue 1 — 流式 EPUB 內容強制套用主題色（背景色＋文字色）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 流式（reflowable）EPUB 顯示時，書頁的背景色與文字色跟隨當下 `Theme.of(context)`（已解析好的 `AppTheme` + E-Ink 高對比狀態）強制套用，不論書本自己的 CSS 宣告了什麼顏色；EPUB 固定版面（漫畫）與 PDF 完全不受影響。

**Architecture:** `ReaderScreen` 在建構 `FoliateEpubReaderView` 時，讀取 `Theme.of(context)` 算出前景/背景 `Color`，以兩個新的 nullable 建構子參數傳入；`FoliateEpubReaderView` 把這兩個 `Color` 轉成 CSS 合法的十六進位色碼字串，併入既有送往 `main.js` 的 `prefs` 物件（沿用既有 `fontWeight`/`lineHeight` 橋接管道，不新增橋接機制）；`main.js` 的 `buildOverrideCss()` 新增這兩個欄位的 CSS 規則產生邏輯，透過既有 `setStyles()` 機制套用到書頁。EPUB 固定版面（`_isFixedLayout == true`）時，兩個 `Color` 皆為 `null`——`main.js` 既有的 `view.isFixedLayout` 分支本就完全跳過 CSS 覆蓋，這裡傳 `null` 只是與其他 nullable 欄位（`fontWeight`/`lineHeight` 等）「FXL 不適用時傳 null」的既有慣例保持一致。

**Tech Stack:** Flutter/Dart（`ReaderScreen`／`FoliateEpubReaderView`）、`flutter_inappwebview`（JS 橋接）、`readest/foliate-js` 釘定版本上層的本專案自建 `main.js`（純 JavaScript，無建置工具鏈、無自動化測試框架）。

## Global Constraints

- 不修改 `readest/foliate-js` 釘定版本本身（`view.js`／`paginator.js`／`epub.js` 等 vendored 檔案）——本 Epic 所有變更僅限本專案自己的 `main.js`／Dart 程式碼（ADR 0011）。
- `ReaderScreen` **不新增任何建構子參數**——直接在既有的 `context`（`State.context`）呼叫 `Theme.of(context)`，`ReaderScreen` 本來就掛載於 `MaterialApp` 之下（spec.md 定案）。
- `app/lib/theme/`（`app_theme.dart`／`app_theme_data.dart`／`app_theme_preferences.dart`）**不修改**——現有 `ColorScheme`/`ThemeData` 已透過標準 `Theme.of(context)` 存取子公開所需顏色。
- `ResolvedPreferences`／`BookReaderPrefs`／`GlobalReaderPrefs` **不修改**——主題顏色資料流獨立於這條既有偏好解析管線之外。
- `Color` → CSS 十六進位色碼轉換**不可直接對 `Color.value` 呼叫 `toRadixString(16)`**（`Color.value` 是 `AARRGGBB`，CSS 8 位色碼標準是 `#RRGGBBAA`，順序相反，直接轉換會產生錯誤顏色，不只是格式問題）。
- `main.js` 背景色覆蓋規則**僅套用 `html, body` 選取器**，不使用文字色沿用的廣選取器（`body, p, div, li, span, td, th, blockquote, dd, dt, a, h1-h6`）——避免包裹圖片的 `div`/`span` 出現不協調背景色塊（spec.md 定案取捨）。
- `main.js` 目前沒有任何自動化測試框架，本 Issue 不新增（`check_foliate_es_compat.js` 是純文字掃描腳本，非單元測試）。

---

## File Structure

- **Modify:** `app/lib/reader/foliate_epub_reader_view.dart`
  - 新增頂層純函式 `colorToCssHex(Color color)`（Task 1）
  - `FoliateEpubReaderView` 新增 `Color? textColor`／`Color? backgroundColor` 兩個建構子欄位（Task 2）
  - `buildFoliatePreferencesMap()` 新增這兩個欄位的序列化（Task 2）
  - `foliatePreferencesChanged()` 新增這兩個欄位的比對（Task 2）
- **Modify:** `app/android/app/src/main/assets/foliate/main.js`
  - `buildOverrideCss(prefs)` 新增 `prefs.textColor`／`prefs.backgroundColor` 的 CSS 規則產生邏輯（Task 3）
- **Modify:** `app/lib/screens/reader_screen.dart`
  - `_ReaderScreenState` 新增 `_themedTextColor`／`_themedBackgroundColor` 兩個私有 getter（Task 4）
  - `_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 `textColor:`／`backgroundColor:` 兩個參數（Task 4）
- **Test:** `app/test/reader/foliate_epub_reader_view_test.dart`（既有檔案，擴充既有 `group`）
- **Test:** `app/test/screens/reader_screen_test.dart`（既有檔案，新增 `testWidgets`）

---

### Task 1: `Color` → CSS 十六進位色碼轉換純函式

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`（新增頂層函式，緊接在既有 `buildFontFaceCss` 之後、`buildFoliatePreferencesMap` 之前）
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Produces: `String colorToCssHex(Color color)` —— 輸入任意 `Color`，回傳 `#RRGGBB` 格式的 6 位十六進位色碼字串（不含 alpha）。Task 2 會呼叫此函式。

- [x] **Step 1: 在 `foliate_epub_reader_view_test.dart` 新增 `colorToCssHex` 測試 group**

在既有 `void main() {` 區塊內、`group('buildFoliatePreferencesMap', ...)` 之前，新增：

```dart
  group('colorToCssHex', () {
    test('不透明色轉換為 6 位十六進位色碼（丟棄 alpha）', () {
      expect(colorToCssHex(const Color(0xFF121214)), '#121214');
    });

    test('RGB 帶前導零時仍正確補零（不會被截斷成較短字串）', () {
      expect(colorToCssHex(const Color(0xFF010203)), '#010203');
    });

    test('純白色轉換正確', () {
      expect(colorToCssHex(const Color(0xFFFFFFFF)), '#ffffff');
    });

    test('純黑色轉換正確', () {
      expect(colorToCssHex(const Color(0xFF000000)), '#000000');
    });
  });

```

- [x] **Step 2: 執行測試確認失敗（`colorToCssHex` 尚未定義）**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name colorToCssHex`
Expected: 編譯錯誤或 FAIL，訊息包含 `colorToCssHex` 未定義（`The function 'colorToCssHex' isn't defined`）。

- [x] **Step 3: 實作 `colorToCssHex`**

在 `app/lib/reader/foliate_epub_reader_view.dart` 找到既有的 `buildFontFaceCss` 函式結尾，緊接著新增：

```dart
/// 把 [Color] 轉換為 CSS 合法的 6 位十六進位色碼字串（`#RRGGBB`，不含
/// alpha）。**不可直接對 [Color.value] 呼叫 `toRadixString(16)`**：
/// `Color.value` 是 32 位 `AARRGGBB`（alpha 在前），CSS 標準的 8 位
/// 十六進位色碼是 `#RRGGBBAA`（alpha 在後），順序相反，直接轉換會產生
/// 錯誤顏色而非只是格式問題（epic-22-reader-theme-integration Issue 1，
/// 程式碼審查發現）。做法：先補零到 8 碼（`padLeft(8, '0')`，避免
/// RGB 帶前導零時被截斷成較短字串），再捨棄前 2 碼 alpha，只保留後
/// 6 碼 RGB。
String colorToCssHex(Color color) {
  final hex = color.value.toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2)}';
}

```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name colorToCssHex`
Expected: PASS，4 個測試全數通過。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-22): 新增 Color 轉 CSS 十六進位色碼純函式 colorToCssHex"
```

---

### Task 2: `FoliateEpubReaderView` 新增 `textColor`/`backgroundColor` 欄位

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `colorToCssHex(Color color) -> String`
- Produces: `FoliateEpubReaderView` 新增 `final Color? textColor`／`final Color? backgroundColor` 兩個欄位；`buildFoliatePreferencesMap(FoliateEpubReaderView view)` 回傳的 map 在這兩個欄位非 null 時新增 `'textColor'`／`'backgroundColor'` 兩個 key（值為 `colorToCssHex()` 轉換後的字串）；`foliatePreferencesChanged(oldView, newView)` 新增這兩個欄位的比對。Task 4 會建構帶有這兩個新欄位的 `FoliateEpubReaderView`。

- [x] **Step 1: 在 `foliate_epub_reader_view_test.dart` 新增欄位序列化測試**

在既有 `group('buildFoliatePreferencesMap', ...)` 區塊內，緊接在既有的 `test('showFooter: false 時 map 含 showFooter: false', ...)` 之後，新增：

```dart

    test('textColor 非 null 時 map 含轉換後的十六進位色碼字串', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFFE8E8EC),
      );
      expect(buildFoliatePreferencesMap(view), {
        'textColor': '#e8e8ec',
        'isLandscape': false,
      });
    });

    test('backgroundColor 非 null 時 map 含轉換後的十六進位色碼字串', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFF121214),
      );
      expect(buildFoliatePreferencesMap(view), {
        'backgroundColor': '#121214',
        'isLandscape': false,
      });
    });

    test('textColor／backgroundColor 未設定（null）時 map 不含這兩個 key', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view).containsKey('textColor'), isFalse);
      expect(
        buildFoliatePreferencesMap(view).containsKey('backgroundColor'),
        isFalse,
      );
    });
```

同時把既有的「所有非 null 建構參數皆正確出現於 map」測試整段換成以下版本（新增 `textColor`/`backgroundColor` 建構參數與對應的預期 map key，其餘部分與原測試相同）：

```dart
    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: 'SourceHanSansTC',
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnMode: ColumnMode.single,
        columnSize: 600.0,
        showFooter: false,
        textColor: Color(0xFFE8E8EC),
        backgroundColor: Color(0xFF121214),
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'marginTop': 72.0,
        'marginBottom': 20.0,
        'marginLeft': 30.0,
        'marginRight': 30.0,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnMode': 'single',
        'columnSize': 600.0,
        'showFooter': false,
        'textColor': '#e8e8ec',
        'backgroundColor': '#121214',
        'isLandscape': false,
      });
    });
```

（這個既有測試原本就窮舉所有欄位以確保沒有遺漏，新增兩個欄位維持這個既有測試的「窮舉全部欄位」不變性。）

接著在既有 `group('foliatePreferencesChanged', ...)` 區塊內新增：

```dart

    test('僅 textColor 不同時回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFF000000),
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFFE8E8EC),
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('僅 backgroundColor 不同時回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFFFFFFFF),
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFF121214),
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('textColor／backgroundColor 皆相同（含皆為 null）時回傳 false', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: 編譯錯誤（`FoliateEpubReaderView` 沒有 `textColor`／`backgroundColor` 具名參數）。

- [x] **Step 3: 新增建構子欄位、更新 `buildFoliatePreferencesMap()`／`foliatePreferencesChanged()`**

在 `FoliateEpubReaderView` 類別欄位宣告（`final bool? isFixedLayoutHint;` 之後）新增：

```dart
  final Color? textColor;
  final Color? backgroundColor;
```

在建構子參數列（`this.isFixedLayoutHint,` 之後）新增：

```dart
    this.textColor,
    this.backgroundColor,
```

在 `buildFoliatePreferencesMap()` 內、`if (view.isFixedLayoutHint != null) { ... }` 區塊之後新增：

```dart
  if (view.textColor != null) {
    map['textColor'] = colorToCssHex(view.textColor!);
  }
  if (view.backgroundColor != null) {
    map['backgroundColor'] = colorToCssHex(view.backgroundColor!);
  }
```

在 `foliatePreferencesChanged()` 內、`oldView.isFixedLayoutHint != newView.isFixedLayoutHint ||` 這一行之後新增：

```dart
      oldView.textColor != newView.textColor ||
      oldView.backgroundColor != newView.backgroundColor ||
```

（維持既有的窮舉比對風格，確保這兩個新欄位跟其他既有欄位一樣，改變時會觸發 `didUpdateWidget()` 重新呼叫 `window.applyPreferences()`。）

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: PASS，全部測試（含既有測試與本次新增測試）通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-22): FoliateEpubReaderView 新增 textColor/backgroundColor 建構子參數"
```

---

### Task 3: `main.js` 的 `buildOverrideCss()` 新增顏色覆蓋規則

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 2 送出的 `prefs.textColor`／`prefs.backgroundColor`（`#RRGGBB` 格式字串，或欄位完全不存在）。
- Produces: `buildOverrideCss(prefs)` 回傳的 CSS 字串新增文字色/背景色覆蓋規則。

本 Task 沒有自動化測試（`main.js` 目前無任何 JS 測試框架，`check_foliate_es_compat.js` 是純文字掃描腳本非單元測試，spec.md 已定案不在本 Epic 新增）。改用「實作 → 人工驗證（可選）→ commit」流程。

- [x] **Step 1: 修改 `buildOverrideCss()`**

在 `app/android/app/src/main/assets/foliate/main.js` 的 `buildOverrideCss(prefs)` 函式內，找到既有的：

```js
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`)
  }
  return rules.join('\n')
```

改為：

```js
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`)
  }
  // epic-22-reader-theme-integration Issue 1：文字色沿用上面同一組廣
  // selector（涵蓋 p/div/span 等實際文字容器元素），確保書本自己在
  // 這些元素直接宣告的文字顏色也會被蓋過（與 fontWeight/lineHeight
  // 既有覆蓋邏輯一致，比照 Issue 34 的既有教訓：只設定 html/body 這種
  // 可被繼承的值，遇到書本直接宣告會完全失效）。
  if (prefs.textColor) {
    rules.push(`${selector} { color: ${prefs.textColor} !important; }`)
  }
  // 背景色刻意只套用 html/body，不用上面的廣 selector——若逐一對
  // p/div/span 等元素套用 background-color，會在包裹圖片的容器上畫出
  // 不協調的色塊（真實可見的視覺瑕疵，取捨已於 spec.md 定案）。
  if (prefs.backgroundColor) {
    rules.push(`html, body { background-color: ${prefs.backgroundColor} !important; }`)
  }
  return rules.join('\n')
```

- [ ] **Step 2（可選）：人工驗證 `buildOverrideCss()` 產生的 CSS 字串正確**

`main.js` 沒有自動化測試框架，若想在提交前快速確認邏輯正確（比照 Issue 34 既有做法），可另開一個暫時性 Node.js 腳本手動驗證，驗證完畢後即刪除，不留下永久測試資產：

```js
// 暫存於 scratchpad，例如 /tmp/verify_build_override_css.js
// 直接複製貼上 main.js 當下的 buildOverrideCss 函式本體到這裡執行
// （buildOverrideCss 是純字串邏輯、不依賴任何外部瀏覽器 API，可以直接
// 拿出來單獨跑，驗證後即刪除此檔案，不留下永久測試資產）。
function buildOverrideCss(prefs) {
  const rules = []
  const selector = prefs.publisherStyles === false
    ? '*'
    : 'body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6'
  if (prefs.textColor) {
    rules.push(`${selector} { color: ${prefs.textColor} !important; }`)
  }
  if (prefs.backgroundColor) {
    rules.push(`html, body { background-color: ${prefs.backgroundColor} !important; }`)
  }
  return rules.join('\n')
}

console.log(buildOverrideCss({ textColor: '#e8e8ec', backgroundColor: '#121214' }))
// 預期輸出兩行規則：
//   body, p, div, ... { color: #e8e8ec !important; }
//   html, body { background-color: #121214 !important; }
console.log('---')
console.log(buildOverrideCss({}))
// 預期輸出空字串（兩個欄位皆未提供，真值檢查應完全不 push 任何規則）
```

Run: `node /tmp/verify_build_override_css.js`（或本機 scratchpad 對應路徑）
Expected: 第一段輸出兩行規則、格式如上；第二段輸出空字串。確認後刪除此暫時性腳本。

- [x] **Step 3: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-22): main.js buildOverrideCss() 新增 textColor/backgroundColor 覆蓋規則"
```

---

### Task 4: `ReaderScreen` 讀取 `Theme.of(context)` 並傳入 `FoliateEpubReaderView`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `FoliateEpubReaderView({..., Color? textColor, Color? backgroundColor})`。
- Produces: `_ReaderScreenState` 新增 `Color? get _themedTextColor`／`Color? get _themedBackgroundColor` 兩個私有 getter（顯示 EPUB 固定版面時回傳 `null`，否則回傳 `Theme.of(context)` 對應值）——epic-22 Issue 2（頁首/頁尾文字色）之後會重用這兩個 getter，不在本 Task 範圍內先行串接。

- [x] **Step 1: 在 `reader_screen_test.dart` 新增顏色透傳測試**

在檔案頂部 import 區塊新增：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

在既有的「流式 EPUB：邊距 4 個欄位從 ResolvedPreferences 正確透傳到 FoliateEpubReaderView（Issue 14）」測試（`testWidgets('流式 EPUB：邊距 4 個欄位...')`）之後，新增：

```dart

  testWidgets(
      '流式 EPUB：Theme.of(context) 的顏色正確透傳到 FoliateEpubReaderView'
      '（epic-22-reader-theme-integration Issue 1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets(
      '流式 EPUB：預設淺色主題（AppTheme.light）下顏色仍正確透傳，'
      '與改動前行為相容（epic-22-reader-theme-integration Issue 1）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.light);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，傳給 FoliateEpubReaderView 的顏色皆為 null'
      '（epic-22-reader-theme-integration Issue 1，圖片內容無法預期背景色）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_foliate_theme_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.textColor, isNull);
    expect(foliateView.backgroundColor, isNull);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 1"`
Expected: FAIL——`foliateView.textColor`/`foliateView.backgroundColor` 目前恆為 `null`（因為 `ReaderScreen` 還沒有把 `Theme.of(context)` 的顏色傳進去），深色/淺色主題兩個測試會失敗（實際值 `null` ≠ 預期的具體顏色）。

- [x] **Step 3: 在 `ReaderScreen` 新增 getter 並串接**

在 `_ReaderScreenState` 內、`_buildNativeView()` 方法之前，新增：

```dart
  /// 流式 EPUB 顯示時的內容前景/背景色，來自 `Theme.of(context)`
  /// （已解析後的最終 `AppTheme`/E-Ink 高對比結果，見
  /// `resolveThemeData()`）；EPUB 固定版面顯示時回傳 `null`——固定
  /// 版面內容是圖片，無法預期背景色，強制上色沒有意義。呼叫端依情境
  /// 決定 `null` 時的退回值（epic-22-reader-theme-integration Issue 1：
  /// `FoliateEpubReaderView` 直接傳 `null`；Issue 2 的頁首/頁尾會退回
  /// 既有寫死 `Colors.black`，不在本 Task 範圍）。
  Color? get _themedTextColor =>
      _isFixedLayout ? null : Theme.of(context).colorScheme.onSurface;
  Color? get _themedBackgroundColor =>
      _isFixedLayout ? null : Theme.of(context).scaffoldBackgroundColor;

```

在 `_buildNativeView()` 內的 `FoliateEpubReaderView(...)` 建構呼叫中，`isFixedLayoutHint: widget.isFixedLayout,` 這一行之後新增：

```dart
          textColor: _themedTextColor,
          backgroundColor: _themedBackgroundColor,
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 1"`
Expected: PASS，3 個新測試全數通過。

- [x] **Step 5: 執行完整 `reader_screen_test.dart` 確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過（含既有的邊距透傳測試、Issue 43 頁首/頁尾黑色文字測試等既有測試不受影響）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-22): ReaderScreen 讀取 Theme.of(context) 並傳入 FoliateEpubReaderView"
```

---

### Task 5: 全專案回歸測試 + 真機視覺驗證

**Files:** 無新增/修改檔案，純驗證。

**Interfaces:** 無新增介面，驗證 Task 1-4 整合後的端到端行為。

- [x] **Step 1: 執行全專案 `flutter test`**

Run: `flutter test`
Expected: 全數通過，無任何回歸（含本 Epic 新增的測試與既有全部測試）。

- [x] **Step 2: 執行全專案 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3: 建置 debug APK**

Run: `flutter build apk --debug`
Expected: `BUILD SUCCESSFUL`。

- [x] **Step 4: 真機/模擬器人工視覺確認**（2026-08-06 已完成並通過，`/superpowers:requesting-code-review` 審查曾指出此步驟原本漏勾選，已補正）

`flutter test` 無法觀察 `InAppWebView` 實際渲染結果（比照本專案既有兩層測試架構慣例），此步驟不可省略：

1. 安裝 debug APK 至真機或模擬器。
2. 進入「設定 → 佈景」，切換為「深色」。
3. 從書架開啟一本流式（非固定版面）EPUB。
4. 確認書頁背景變深、文字變淺，且顏色與書架/設定畫面的深色主題視覺一致。
5. 切換回「預設淺色」主題，重新開啟同一本書，確認書頁背景/文字色與 App 既有淺色主題殼層視覺（`#F8F8FA`／`#1A1A2E`，近白/近黑）一致——**注意**：這與「本 Epic 實作前書本完全不受顏色覆蓋的原始渲染色」不是逐位元組相同（程式碼審查發現的措辭精確度落差，已修正 `spec.md`/`issues.md` 用詞，人眼幾乎無法察覺差異，非阻擋項）。
6. 若手邊有固定版面（FXL，漫畫）EPUB，開啟後確認頁面圖片內容不受影響（不論當下選的是深色或淺色主題）。

- [x] **Step 5: Commit（若真機驗證過程中有任何修正）**——真機驗證全數通過且無需修正程式碼，本 Step 略過（Task 4 的 commit 已是本 Issue 最終狀態）。
