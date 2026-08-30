# Epic 28 Issue 4 — 檢討「設定面板草稿具現化」原則是否意外覆寫書本原生 CSS 樣式 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ReaderSettingsSheet` 目前只要使用者觸碰過畫面上「任何一個」控制項（哪怕只是切換「顯示頁首」這種完全不相干的開關），就會把字級／字型粗細／行高／段落間距／字距這 5 個滑桿「目前顯示的數字」一併悄悄寫入該書的持久化設定，永久覆蓋書本自己的原生 CSS 樣式，即使使用者從未主動調整過這些滑桿。本計畫修正這個「草稿具現化」bug，讓這 5 個欄位只有在使用者真的觸碰過該欄位時才會被送出／持久化為具體數字；並在畫面上用一個「禁止」圖示取代未覆寫欄位的數字顯示，讓使用者一眼看出「這項還沒調整、跟著書本走」，同時提供明確的「恢復本書原樣式」按鈕。

**Architecture:** 純 `ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`）UI 狀態管理修正，不涉及任何資料層改動——`BookReaderPrefs` 的這 5 個欄位（`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`letterSpacing`）本來就是 `double?`，`ReaderPrefsManagerImpl.resolve()` 對它們是直接透傳（無 `?? 預設值`），`main.js` 的 `buildOverrideCss()` 也已正確處理 `null`（不注入 CSS 覆蓋規則，讓書本原生樣式生效）——問題純粹出在 `ReaderSettingsSheet` 把 `null` 具現化成畫面預設數字後，`_notifyChanged()` 無條件把這個具現化數字送出。修法是新增 5 個「是否已被使用者覆寫」的旗標，`_currentDraft` 依旗標決定要送出具體數字還是 `null`；UI 層再依同一組旗標決定顯示數字還是「原樣式」圖示。**範圍界定（已與人類確認）**：只處理這 5 個欄位；上/下/左/右邊界（`marginTop`／`marginBottom`／`marginLeft`／`marginRight`）已查證是 App 自身的閱讀版面留白設定（`main.js` 用 `view.renderer.setAttribute()` 套用、非 CSS 注入，且有自己的 JS 端寫死預設值 32/16/24/24px），與「書本原生樣式」無關，不受本 bug 影響，維持現狀不動；「停用書本 CSS」（`publisherStyles`）開關另有獨立、與本 Issue 無關的可能設計缺陷（`buildOverrideCss()` 的 selector 廣度／`!important` 優先度邏輯），留待後續獨立 `/diagnose` 處理，本計畫不觸碰。**不做「即時查詢書本實際渲染樣式來預先帶入數字」**（技術上需要 JS 橋接 `getComputedStyle()`＋跨單位換算＋處理書內多元素樣式不一致，複雜度與不確定性高，已與人類確認捨棄）——改用靜態圖示表示「未覆寫」狀態。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/issues.md`「Issue 4」（根因分析、已排除欄位清單、3 個修法方向）。本計畫採用該文件列出的**方向 3**（全面調整為 `null` 語意＋新增重置操作），範圍收斂為文件本身標示為「真正受影響」的 5 個欄位（原文列出的 9 個欄位中，4 個邊界欄位經本計畫查證後排除，見上方 Architecture）。

## Global Constraints

- 只修改 `app/lib/screens/reader_settings_sheet.dart` 與其測試 `app/test/screens/reader_settings_sheet_test.dart`；`app/test/screens/reader_screen_test.dart` 只有 1 處**既有註解**因本次修復而不再準確，需同步更新文字（不改動任何斷言，見 Task 1 Step 6）。
- 只對 `fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`letterSpacing` 這 5 個欄位新增「是否已覆寫」追蹤；`marginTop`／`marginBottom`／`marginLeft`／`marginRight`／`publisherStyles`／`columnMode`／`columnSize`／`showHeader`／`showFooter`／`fullscreen` 等其餘欄位一律維持現狀不動，不新增任何旗標或 UI 變化。
- 不修改 `BookReaderPrefs`、`ReaderPrefsManagerImpl.resolve()`、`main.js`、SQLite schema——這 5 個欄位在這些層級已經是正確的 nullable／直接透傳／`typeof === 'number'` 判斷，不需要改動。
- 「原樣式」提示一律用 `Icons.block`（圈圈內一條斜線的禁止圖示，Material Icons 內建，不需額外圖示資源）；未覆寫時以唯讀 `Icon`＋`Tooltip`（文字「跟隨本書原樣式，尚未調整」）取代原本的數字 `Text`；已覆寫時在數字旁新增同款圖示的 `IconButton`（tooltip「恢復本書原樣式」），按下後清空覆寫、旗標歸位、滑桿視覺回到 `_buildSliderRow` 現有的 `_default*` 常數位置（不查詢書本實際渲染值，見上方 Architecture）。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：新增 5 個欄位「是否已覆寫」追蹤旗標，修正 `_currentDraft` 不再無條件具現化

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:71-279`（狀態欄位宣告、`initState()`、`didUpdateWidget()`、`_currentDraft` getter、5 個 `_buildSliderRow` 呼叫點的 `onChanged` 閉包）
- Modify: `app/test/screens/reader_screen_test.dart`（僅更新 1 處因本次修復而過時的既有註解文字，約第 1341-1344 行，不改動任何斷言）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: 既有 `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`，`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`letterSpacing` 皆為 `double?`）；既有 `widget.onChanged`（`ValueChanged<BookReaderPrefs>`，`app/lib/screens/reader_settings_sheet.dart:26`）。
- Produces: 新增 5 個私有 `bool` 欄位 `_fontSizeOverridden`／`_fontWeightOverridden`／`_lineHeightOverridden`／`_paragraphSpacingOverridden`／`_letterSpacingOverridden`，供 Task 2 的 UI 層讀取以決定顯示圖示或數字、決定是否顯示重置按鈕。

- [ ] **Step 1：寫失敗測試——重現「切換不相干開關會悄悄覆寫」的原始 bug 場景**

編輯 `app/test/screens/reader_settings_sheet_test.dart`，在既有 `testWidgets('任一欄位為 null 時，滑桿顯示原型範例預設值', ...)`（約第 111-184 行）之後，新增以下 2 則測試：

```dart
  testWidgets(
      '只切換「顯示頁首」開關，onChanged 帶出的字級/粗細/行高/段落間距/字距皆維持 null'
      '（epic-28-reader-settings-enhancements Issue 4：草稿具現化不應覆寫書本原生樣式）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showHeader, isTrue);
    expect(result!.fontSize, isNull,
        reason: '使用者從未調整過字級，不應被草稿具現化悄悄寫入');
    expect(result!.fontWeight, isNull,
        reason: '使用者從未調整過字型粗細，不應被草稿具現化悄悄寫入');
    expect(result!.lineHeight, isNull,
        reason: '使用者從未調整過行高，不應被草稿具現化悄悄寫入');
    expect(result!.paragraphSpacing, isNull,
        reason: '使用者從未調整過段落間距，不應被草稿具現化悄悄寫入');
    expect(result!.letterSpacing, isNull,
        reason: '使用者從未調整過字距，不應被草稿具現化悄悄寫入');
  });

  testWidgets(
      '只調整字距 + 按鈕，onChanged 帶出的字級/粗細/行高/段落間距仍維持 null，'
      '只有字距被覆寫（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_letter_spacing_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, closeTo(0.01, 1e-9));
    expect(result!.fontSize, isNull);
    expect(result!.fontWeight, isNull);
    expect(result!.lineHeight, isNull);
    expect(result!.paragraphSpacing, isNull);
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "草稿具現化"`

預期：兩則測試皆 FAIL——目前 `_currentDraft` 對這 5 個欄位無條件送出具體數字（`fontSize` 會是 `1.0`、`fontWeight` 會是 `1.0`、`lineHeight` 會是 `1.0`、`paragraphSpacing` 會是 `1.0`、`letterSpacing` 在第一則測試會是 `0.0`），與 `isNull` 斷言不符。

- [ ] **Step 3：新增 5 個「是否已覆寫」旗標**

編輯 `app/lib/screens/reader_settings_sheet.dart`，於狀態欄位宣告區（約第 71-90 行）：

```dart
  late String? _fontFamily;
  late double _fontSize;
  late double _fontWeightMultiplier;
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _letterSpacing;
```

改為（新增 5 個旗標，緊接在對應數值欄位之後）：

```dart
  late String? _fontFamily;
  late double _fontSize;
  late bool _fontSizeOverridden;
  late double _fontWeightMultiplier;
  late bool _fontWeightOverridden;
  late double _lineHeight;
  late bool _lineHeightOverridden;
  late double _paragraphSpacing;
  late bool _paragraphSpacingOverridden;
  late double _letterSpacing;
  late bool _letterSpacingOverridden;
```

- [ ] **Step 4：`initState()`／`didUpdateWidget()` 初始化旗標**

編輯 `app/lib/screens/reader_settings_sheet.dart` 的 `initState()`（約第 92-119 行），找到：

```dart
    _fontSize = widget.prefs.fontSize != null
        ? (widget.prefs.fontSize! * 16.0).roundToDouble()
        : _defaultFontSize;
    _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing = widget.prefs.paragraphSpacing != null
        ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
        : _defaultParagraphSpacing;
    _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
```

改為：

```dart
    _fontSize = widget.prefs.fontSize != null
        ? (widget.prefs.fontSize! * 16.0).roundToDouble()
        : _defaultFontSize;
    _fontSizeOverridden = widget.prefs.fontSize != null;
    _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _fontWeightOverridden = widget.prefs.fontWeight != null;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _lineHeightOverridden = widget.prefs.lineHeight != null;
    _paragraphSpacing = widget.prefs.paragraphSpacing != null
        ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
        : _defaultParagraphSpacing;
    _paragraphSpacingOverridden = widget.prefs.paragraphSpacing != null;
    _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
    _letterSpacingOverridden = widget.prefs.letterSpacing != null;
```

`didUpdateWidget()`（約第 121-152 行）內有逐位元組相同的一段（差別只在賦值目標是 `setState` 內），套用完全相同的插入方式：

```dart
        _fontSize = widget.prefs.fontSize != null
            ? (widget.prefs.fontSize! * 16.0).roundToDouble()
            : _defaultFontSize;
        _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _paragraphSpacing = widget.prefs.paragraphSpacing != null
            ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
            : _defaultParagraphSpacing;
        _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
```

改為：

```dart
        _fontSize = widget.prefs.fontSize != null
            ? (widget.prefs.fontSize! * 16.0).roundToDouble()
            : _defaultFontSize;
        _fontSizeOverridden = widget.prefs.fontSize != null;
        _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _fontWeightOverridden = widget.prefs.fontWeight != null;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _lineHeightOverridden = widget.prefs.lineHeight != null;
        _paragraphSpacing = widget.prefs.paragraphSpacing != null
            ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
            : _defaultParagraphSpacing;
        _paragraphSpacingOverridden = widget.prefs.paragraphSpacing != null;
        _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
        _letterSpacingOverridden = widget.prefs.letterSpacing != null;
```

- [ ] **Step 5：`_currentDraft` 依旗標決定送出 `null` 或具體數字，5 個 `onChanged` 閉包同步標記已覆寫**

編輯 `app/lib/screens/reader_settings_sheet.dart` 的 `_currentDraft` getter（約第 158-179 行），找到：

```dart
        fontSize: _toMultiplier(_fontSize, 16.0),
        fontWeight: _fontWeightMultiplier,
        lineHeight: _lineHeight,
        paragraphSpacing: _toMultiplier(_paragraphSpacing, 10.0),
        letterSpacing: _letterSpacing,
```

改為：

```dart
        fontSize: _fontSizeOverridden ? _toMultiplier(_fontSize, 16.0) : null,
        fontWeight: _fontWeightOverridden ? _fontWeightMultiplier : null,
        lineHeight: _lineHeightOverridden ? _lineHeight : null,
        paragraphSpacing:
            _paragraphSpacingOverridden ? _toMultiplier(_paragraphSpacing, 10.0) : null,
        letterSpacing: _letterSpacingOverridden ? _letterSpacing : null,
```

接著在 `build()` 內找到這 5 個 `_buildSliderRow` 呼叫點（約第 215-279 行）的 `onChanged` 閉包，逐一在 `setState` 內新增對應的 `..Overridden = true;`：

字型大小（約第 223-226 行）：

```dart
                  onChanged: (v) => setState(() {
                    _fontSize = v;
                    _notifyChanged();
                  }),
```

改為：

```dart
                  onChanged: (v) => setState(() {
                    _fontSize = v;
                    _fontSizeOverridden = true;
                    _notifyChanged();
                  }),
```

字型粗細（約第 236-239 行）：

```dart
                  onChanged: (v) => setState(() {
                    _fontWeightMultiplier = v / 400;
                    _notifyChanged();
                  }),
```

改為：

```dart
                  onChanged: (v) => setState(() {
                    _fontWeightMultiplier = v / 400;
                    _fontWeightOverridden = true;
                    _notifyChanged();
                  }),
```

行高（約第 249-252 行）：

```dart
                  onChanged: (v) => setState(() {
                    _lineHeight = double.parse(v.toStringAsFixed(1));
                    _notifyChanged();
                  }),
```

改為：

```dart
                  onChanged: (v) => setState(() {
                    _lineHeight = double.parse(v.toStringAsFixed(1));
                    _lineHeightOverridden = true;
                    _notifyChanged();
                  }),
```

段落間距（約第 262-265 行）：

```dart
                  onChanged: (v) => setState(() {
                    _paragraphSpacing = v;
                    _notifyChanged();
                  }),
```

改為：

```dart
                  onChanged: (v) => setState(() {
                    _paragraphSpacing = v;
                    _paragraphSpacingOverridden = true;
                    _notifyChanged();
                  }),
```

字距（約第 275-278 行）：

```dart
                  onChanged: (v) => setState(() {
                    _letterSpacing = double.parse(v.toStringAsFixed(2));
                    _notifyChanged();
                  }),
```

改為：

```dart
                  onChanged: (v) => setState(() {
                    _letterSpacing = double.parse(v.toStringAsFixed(2));
                    _letterSpacingOverridden = true;
                    _notifyChanged();
                  }),
```

- [ ] **Step 6：更新 `reader_screen_test.dart` 內因本次修復而過時的既有註解（不改動任何斷言）**

編輯 `app/test/screens/reader_screen_test.dart`，找到（約第 1341-1344 行，測試「流式 EPUB 頁尾頁碼隨字級調整重新估算」內）：

```dart
    // fontSize 倍率變成 2.0，且 16 次點擊過程中 ReaderSettingsSheet 的
    // _notifyChanged() 一併把行高／邊界的目前 UI 狀態（即使使用者未曾觸碰）
    // 送入 BookReaderPrefs——這些值恰好等於 estimateCharsPerScreen() 自身
    // 的預設 fallback（lineHeight 1.0／margin 32-16-24-24），數值不受影響。
```

改為（`EpubPageEstimator.estimateCharsPerScreen()` 本身對 `lineHeight` 等參數皆有 `?? 1.0` 這類獨立防呆 fallback，見 `app/lib/reader/epub_page_estimator.dart:70-89`，故無論 `resolved.lineHeight` 是 `null` 或具體數值 `1.0`，算出來的 `lineHeightFactor` 恆相同，這則測試的頁碼估算結果不受本次修復影響，只有註解描述的「行高也被具現化」這件事本身不再成立）：

```dart
    // fontSize 倍率變成 2.0。epic-28-reader-settings-enhancements Issue 4
    // 修復後，ReaderSettingsSheet 只有「使用者實際觸碰過的欄位」才會送出
    // 具體數值——lineHeight 未被觸碰，因此正確維持 null，不再被具現化；
    // 邊界（margin）4 個欄位屬於 App 自身版面留白設定、與「書本原生樣式」
    // 無關，不在本次修復範圍內，_notifyChanged() 仍會送出目前 UI 顯示值
    // （32-16-24-24）。兩者皆與 estimateCharsPerScreen() 自身的獨立
    // fallback（lineHeight ?? 1.0 等，見 epub_page_estimator.dart）相同，
    // 頁碼估算數值不受影響。
```

- [ ] **Step 7：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：全數 PASS（含 Step 1 新增的 2 則測試，以及既有全部測試——既有測試皆以非 `null` 的具體值初始化這 5 個欄位，見下方確認，故不受影響）。

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "頁尾"`

預期：PASS（Step 6 只改註解文字，斷言不變，數值原因見 Step 6 說明）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-28): Issue 4——ReaderSettingsSheet 5 個版面欄位只在使用者實際調整後才覆寫書本原生樣式"
```

---

### Task 2：畫面上以「原樣式」圖示取代未覆寫欄位的數字，並提供明確的重置按鈕

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:511-563`（`_buildSliderRow` 方法本體）、`app/lib/screens/reader_settings_sheet.dart:215-279`（5 個受影響欄位的 `_buildSliderRow` 呼叫點，新增 `isOverridden`／`onReset` 參數）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 新增的 5 個 `_fontSizeOverridden`／`_fontWeightOverridden`／`_lineHeightOverridden`／`_paragraphSpacingOverridden`／`_letterSpacingOverridden` 旗標；既有 `_defaultFontSize`／`_defaultFontWeightMultiplier`／`_defaultLineHeight`／`_defaultParagraphSpacing`／`_defaultLetterSpacing` 常數（`app/lib/screens/reader_settings_sheet.dart:61-65`）。
- Produces: `_buildSliderRow` 新增 2 個具名可選參數 `bool? isOverridden`（預設 `null`，代表「不適用本機制」，供 4 個邊界欄位呼叫點維持現狀不傳）、`VoidCallback? onReset`（`isOverridden == true` 時才會被實際渲染成可按的重置按鈕）。新增 2 個測試用 `Key` 命名慣例：`'${keyPrefix}_unset_indicator'`（未覆寫時的圖示）、`'${keyPrefix}_reset'`（已覆寫時的重置按鈕）。

- [ ] **Step 1：寫失敗測試——圖示顯示邏輯與重置按鈕**

編輯 `app/test/screens/reader_settings_sheet_test.dart`，在 Task 1 Step 1 新增的 2 則測試之後，接續新增以下 4 則測試：

```dart
  testWidgets(
      '5 個受本 Issue 影響欄位皆為 null 時，顯示「原樣式」禁止圖示取代數字；'
      '邊界 4 個欄位不受影響，仍顯示具體數字，也不出現重置按鈕'
      '（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    for (final keyPrefix in [
      'reader_settings_font_size',
      'reader_settings_font_weight',
      'reader_settings_line_height',
      'reader_settings_paragraph_spacing',
      'reader_settings_letter_spacing',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsOneWidget,
          reason: '$keyPrefix 尚未被使用者調整過，應顯示原樣式圖示而非數字');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing,
          reason: '$keyPrefix 尚未覆寫，不應出現重置按鈕');
    }

    for (final keyPrefix in [
      'reader_settings_margin_top',
      'reader_settings_margin_bottom',
      'reader_settings_margin_left',
      'reader_settings_margin_right',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 是 App 版面留白設定，與書本原生樣式無關，不適用本機制');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing);
    }
  });

  testWidgets(
      '依序調整 5 個受影響欄位，每次只有剛調整的欄位轉為顯示數字＋重置按鈕，'
      '其餘尚未調整的欄位持續顯示原樣式圖示（不互相污染，'
      'epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    const steps = [
      ('reader_settings_font_size', 'reader_settings_font_size_increment'),
      (
        'reader_settings_font_weight',
        'reader_settings_font_weight_increment'
      ),
      (
        'reader_settings_line_height',
        'reader_settings_line_height_increment'
      ),
      (
        'reader_settings_paragraph_spacing',
        'reader_settings_paragraph_spacing_increment'
      ),
      (
        'reader_settings_letter_spacing',
        'reader_settings_letter_spacing_increment'
      ),
    ];

    for (var i = 0; i < steps.length; i++) {
      final (keyPrefix, incrementKey) = steps[i];
      await tester.tap(find.byKey(Key(incrementKey)));
      await tester.pump();

      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 剛被調整，應改顯示數字');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsOneWidget,
          reason: '$keyPrefix 剛被調整，應出現重置按鈕');

      for (var j = i + 1; j < steps.length; j++) {
        final (untouchedPrefix, _) = steps[j];
        expect(find.byKey(Key('${untouchedPrefix}_unset_indicator')),
            findsOneWidget,
            reason: '$untouchedPrefix 尚未被調整，不應被 $keyPrefix 的互動連帶影響');
      }
    }
  });

  testWidgets(
      '按下字距重置按鈕後，onChanged 帶出 letterSpacing=null，滑桿回到預設位置、'
      '重新顯示原樣式圖示（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      (prefs) => result = prefs,
    );

    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('reader_settings_letter_spacing_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, isNull);
    expect(
        tester
            .widget<Slider>(find
                .byKey(const Key('reader_settings_letter_spacing_slider')))
            .value,
        0.0,
        reason: '重置後滑桿應回到原型範例預設位置');
    expect(
        find.byKey(
            const Key('reader_settings_letter_spacing_unset_indicator')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsNothing);
  });

  testWidgets(
      '按下字型大小重置按鈕後，onChanged 帶出 fontSize=null，滑桿回到 16px 預設位置'
      '（epic-28-reader-settings-enhancements Issue 4，涵蓋倍率換算路徑）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 1.375), // UI 22.0
      (prefs) => result = prefs,
    );

    expect(find.byKey(const Key('reader_settings_font_size_reset')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_settings_font_size_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, isNull);
    expect(
        tester
            .widget<Slider>(
                find.byKey(const Key('reader_settings_font_size_slider')))
            .value,
        16.0,
        reason: '重置後滑桿應回到原型範例預設位置');
    expect(
        find.byKey(const Key('reader_settings_font_size_unset_indicator')),
        findsOneWidget);
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "原樣式圖示|重置按鈕|不互相污染"`

預期：4 則測試皆 FAIL——目前完全沒有 `_unset_indicator`／`_reset` 這兩種 Key，`findsOneWidget` 斷言全數找不到元件。

- [ ] **Step 3：`_buildSliderRow` 新增圖示/重置按鈕邏輯**

編輯 `app/lib/screens/reader_settings_sheet.dart`，找到 `_buildSliderRow` 方法簽章（約第 511-520 行）：

```dart
  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
```

改為：

```dart
  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String displayValue,
    required ValueChanged<double> onChanged,
    bool? isOverridden,
    VoidCallback? onReset,
  }) {
```

找到數值顯示那一行（約第 528-531 行）：

```dart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(displayValue)],
          ),
```

改為：

```dart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              if (isOverridden == null)
                Text(displayValue)
              else if (isOverridden == true)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayValue),
                    IconButton(
                      key: Key('${keyPrefix}_reset'),
                      icon: const Icon(Icons.block),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: '恢復本書原樣式',
                      onPressed: onReset,
                    ),
                  ],
                )
              else
                Tooltip(
                  message: '跟隨本書原樣式，尚未調整',
                  child: Icon(
                    Icons.block,
                    key: Key('${keyPrefix}_unset_indicator'),
                    size: 18,
                    color: Theme.of(context).disabledColor,
                  ),
                ),
            ],
          ),
```

- [ ] **Step 4：5 個受影響欄位的呼叫點傳入 `isOverridden`／`onReset`**

編輯 `app/lib/screens/reader_settings_sheet.dart`，於 5 個 `_buildSliderRow` 呼叫點（約第 215-279 行）分別補上 2 個參數。

字型大小：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_font_size',
                  label: '字型大小',
                  value: _fontSize,
                  min: 12,
                  max: 80,
                  step: 1,
                  displayValue: _fontSize.round().toString(),
                  isOverridden: _fontSizeOverridden,
                  onReset: () => setState(() {
                    _fontSizeOverridden = false;
                    _fontSize = _defaultFontSize;
                    _notifyChanged();
                  }),
                  onChanged: (v) => setState(() {
                    _fontSize = v;
                    _fontSizeOverridden = true;
                    _notifyChanged();
                  }),
                ),
```

字型粗細：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_font_weight',
                  label: '字型粗細',
                  value: _fontWeightMultiplier * 400,
                  min: 300,
                  max: 900,
                  step: 100,
                  displayValue: (_fontWeightMultiplier * 400).round().toString(),
                  isOverridden: _fontWeightOverridden,
                  onReset: () => setState(() {
                    _fontWeightOverridden = false;
                    _fontWeightMultiplier = _defaultFontWeightMultiplier;
                    _notifyChanged();
                  }),
                  onChanged: (v) => setState(() {
                    _fontWeightMultiplier = v / 400;
                    _fontWeightOverridden = true;
                    _notifyChanged();
                  }),
                ),
```

行高：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_line_height',
                  label: '行高',
                  value: _lineHeight,
                  min: 0,
                  max: 3,
                  step: 0.1,
                  displayValue: _lineHeight.toStringAsFixed(1),
                  isOverridden: _lineHeightOverridden,
                  onReset: () => setState(() {
                    _lineHeightOverridden = false;
                    _lineHeight = _defaultLineHeight;
                    _notifyChanged();
                  }),
                  onChanged: (v) => setState(() {
                    _lineHeight = double.parse(v.toStringAsFixed(1));
                    _lineHeightOverridden = true;
                    _notifyChanged();
                  }),
                ),
```

段落間距：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_paragraph_spacing',
                  label: '段落間距',
                  value: _paragraphSpacing,
                  min: 0,
                  max: 40,
                  step: 1,
                  displayValue: _paragraphSpacing.round().toString(),
                  isOverridden: _paragraphSpacingOverridden,
                  onReset: () => setState(() {
                    _paragraphSpacingOverridden = false;
                    _paragraphSpacing = _defaultParagraphSpacing;
                    _notifyChanged();
                  }),
                  onChanged: (v) => setState(() {
                    _paragraphSpacing = v;
                    _paragraphSpacingOverridden = true;
                    _notifyChanged();
                  }),
                ),
```

字距：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_letter_spacing',
                  label: '字距',
                  value: _letterSpacing,
                  min: -0.05,
                  max: 1,
                  step: 0.01,
                  displayValue: '${_letterSpacing.toStringAsFixed(2)}em',
                  isOverridden: _letterSpacingOverridden,
                  onReset: () => setState(() {
                    _letterSpacingOverridden = false;
                    _letterSpacing = _defaultLetterSpacing;
                    _notifyChanged();
                  }),
                  onChanged: (v) => setState(() {
                    _letterSpacing = double.parse(v.toStringAsFixed(2));
                    _letterSpacingOverridden = true;
                    _notifyChanged();
                  }),
                ),
```

4 個邊界欄位（上/下/左/右邊界）的呼叫點維持逐位元組不變，不傳 `isOverridden`／`onReset`（沿用 `_buildSliderRow` 的預設 `null`，行為與修改前完全一致）。

- [ ] **Step 5：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：全數 PASS（含 Task 1、Task 2 新增的 6 則測試，以及既有全部測試）。

- [ ] **Step 6：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`

預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS，零回歸。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-28): Issue 4——版面設定以禁止圖示標示未覆寫欄位，並提供恢復本書原樣式按鈕"
```

---

## 完成後的驗證（對照 `issues.md` Issue 4 應補齊項目）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] 只切換與版面樣式無關的開關（例如「顯示頁首」），字級/粗細/行高/段落間距/字距 5 個欄位不會被悄悄覆寫（Task 1 測試已涵蓋）
- [ ] 使用者實際調整某一個欄位時，只有該欄位被標記為已覆寫，其餘 4 個仍維持跟隨書本原生樣式（Task 2 測試已涵蓋）
- [ ] 未覆寫欄位顯示「原樣式」禁止圖示；已覆寫欄位可透過重置按鈕恢復未覆寫狀態（Task 2 測試已涵蓋）
- [ ] 邊界（margin）4 個欄位與「停用書本 CSS」以外的其餘欄位行為完全不變（Task 1／Task 2 測試皆已涵蓋回歸檢查）
