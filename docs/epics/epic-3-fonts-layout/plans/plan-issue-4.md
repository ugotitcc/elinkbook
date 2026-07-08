# Issue 4 實作計劃：版面設定 Bottom Sheet——三個覆寫選擇器與螢幕方向鎖定

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 在 Issue 3 已完成的 `ReaderSettingsSheet` 內新增排版方向／翻頁模式／螢幕方向三個持久化覆寫圖示選擇器；`ReaderScreen` 補上「單書覆寫 `??` 自動偵測結果／全域預設值」的雙層解析邏輯，並套用真實 OS 層級的螢幕方向鎖定；同時整併退場 Epic 2 遺留、僅限當次 session 即時切換且不持久化的兩顆過渡性按鈕（`reader_writing_mode_toggle`／`reader_page_turn_mode_toggle`）。

**架構：** 本 issue **完全不需要修改任何 Kotlin/原生程式碼**——`EpubReaderView`/`EpubReaderView.kt` 既有的批次偏好設定契約（ADR 0006，`writingMode`/`pageTurnMode` map key）已完整支援本 issue 需要的所有語意，`EpubReaderView` 呼叫端只需要傳入「已解析好的最終生效值」。`ReaderSettingsSheet`（Issue 3 建立）延續其「純展示、無 I/O，透過 `onChanged` 回報完整 `BookReaderPrefs`」的既有設計，新增三個內部可變欄位（`_writingModeOverride`／`_pageTurnModeOverride`／`_screenOrientationOverride`），從原本單純的「原樣保留、不清空」passthrough 改為由使用者實際互動控制。`ReaderScreen` 新增三個 resolved getter，把「覆寫值 `??` 預設值」的解析邏輯集中在一處，`EpubReaderView` 建構參數與 `SystemChrome.setPreferredOrientations` 呼叫皆改用這三個 getter，不再各自散落判斷式。

**技術棧：** Dart/Flutter、`SharedPreferences.setMockInitialValues`（widget test 中驅動 `GlobalReaderDefaults`，比照 `LibraryPreferences` 既有測試慣例）、`TestDefaultBinaryMessengerBinding`（攔截 `SystemChannels.platform` 的 `SystemChrome.setPreferredOrientations` 呼叫，驗證螢幕方向鎖定/還原邏輯，不需要真的觀察裝置實際轉動）、`integration_test`（真實裝置，`flutter devices` 已確認可用裝置 9491G，ID：`3CEF42ECD491687`）。

## 全域限制條件

- 本 issue 完全不需要修改任何 Kotlin/原生程式碼——`EpubReaderView.kt` 的 `buildPreferencesFromMap` 已能處理 `writingMode`/`pageTurnMode` 這兩個既有 map key，本 issue 只是在 Dart 端改變「傳入 `EpubReaderView` 的值是怎麼算出來的」，不新增任何 map key、不擴充原生端契約。
- 三個覆寫選擇器統一採圖示直接點選（`design.md` 明確決策），不使用下拉選單；「使用全域預設」／「採用書籍排版」皆以獨立圖示表示 `null` 覆寫值，比照既有 `_buildTextAlignRow` 的圖示列風格。
- `ScreenOrientationSetting` → `DeviceOrientation` 對應（本 issue 撰寫計劃階段決定的慣例，非官方規範）：`auto` → `[]`（空列表，允許全部方向）、`lock0` → `[DeviceOrientation.portraitUp]`、`lock90` → `[DeviceOrientation.landscapeLeft]`、`lock180` → `[DeviceOrientation.portraitDown]`、`lock270` → `[DeviceOrientation.landscapeRight]`。實際物理旋轉角度是否與此對應一致，留待 Task 3 之後的人工視覺 QA 確認（見驗收標準），非本計劃阻塞項。
- 螢幕方向圖示 0°/180° 共用 `Icons.stay_current_portrait`、90°/270° 共用 `Icons.stay_current_landscape`（Material icon 集無法用單一圖示區分 4 個角度），以 tooltip 文字消歧，比照 Issue 3 `_buildTextAlignRow` 對 `start`/`end`（共用 `first_page`/`last_page` 以外的獨立圖示但仍以 tooltip 消歧文字對齊語意）的既有處理原則。
- `GlobalReaderDefaults` 比照既有 `LibraryPreferences`／`AppThemePreferences` 慣例，直接以欄位形式在 `_ReaderScreenState` 內建構（`final _globalDefaults = GlobalReaderDefaults();`），**不**透過建構子注入——與 ADR 0007 為 `BookReaderPrefsRepository`（需要與 `LibraryRepository` 共用同一個 `Database` 連線）建立的跨 Widget 樹 DI 路徑不同，`GlobalReaderDefaults` 純粹包裝 `shared_preferences`、無資料庫依賴，沿用 `LibraryScreen._preferences = LibraryPreferences();` 既有的直接實例化慣例即可，不需要新的 ADR。
- **移除** `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 兩顆 AppBar 按鈕，以及 `_toggleWritingMode`／`_togglePageTurnMode` 兩個方法；連同測試對應的兩個 Key 逐一移除或改寫（見 Task 2／Task 3 精確清單），`ReaderScreen` AppBar 的 `_buildAppBarActions` 最終只回傳單一個「⚙️版面」按鈕。
- 所有新增程式碼註解與文件維持正體中文。
- `flutter build apk --debug`／`flutter devices` 已確認裝置 9491G（ID：`3CEF42ECD491687`）可用，Task 3 的 `integration_test` 須在此裝置上實際執行，不得省略或僅寫程式碼不驗證；若裝置 ID 已變動，以當下 `flutter devices` 實際輸出為準替換指令中的 ID。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`ReaderSettingsSheet` 新增三個覆寫圖示選擇器

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Modify: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Epic 3 Issue 1 的 `BookReaderPrefs`（`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride` 三個既有欄位，型別分別為 `WritingMode?`／`PageTurnMode?`／`ScreenOrientationSetting?`，皆已存在於 `app/lib/reader/book_reader_prefs.dart`，本 Task 不新增/修改任何 model 欄位）
- Produces：新增固定 Key：`reader_settings_writing_mode_book`／`_vertical`／`_horizontal`、`reader_settings_page_turn_mode_global`／`_paginated`／`_scroll`、`reader_settings_screen_orientation_global`／`_auto`／`_lock0`／`_lock90`／`_lock180`／`_lock270`，供 Task 3（`integration_test`）使用

`ReaderSettingsSheet` 目前（Issue 3 完成後）對這三個欄位的處理是「原樣保留、不清空」的 passthrough（`_notifyChanged()` 直接讀 `widget.prefs.writingModeOverride` 等，見下方 Step 3 的 Before 區塊）——本 Task 把這三個欄位比照其餘 8 個既有欄位的模式，改為由使用者互動的內部可變狀態控制。

- [ ] **Step 1：撰寫失敗測試**

開啟 `app/test/screens/reader_settings_sheet_test.dart`，確認檔案開頭已有以下 import（Issue 3 已建立，此處只新增一行）：

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
```

在這個 import 區塊新增一行（依字母順序放在 `page_turn_mode.dart` 之後）：

```dart
import 'package:elinkbook/reader/screen_orientation_setting.dart';
```

在檔案最後一個既有 `testWidgets`（`'任一控制項互動後，writingModeOverride/pageTurnModeOverride/screenOrientationOverride 三個 Issue 4 欄位維持原值不被清空'`）之後、`main()` 收尾的 `}` 之前，新增：

```dart

  testWidgets(
      'writingModeOverride 初始為 vertical 時，點擊「採用書籍排版」圖示後，'
      'onChanged 帶入 null', (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: const BookReaderPrefs(
            writingModeOverride: WritingMode.vertical,
          ),
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_writing_mode_book')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, isNull);
  });

  testWidgets(
      'writingModeOverride 初始為 null 時，點擊「強制直排」圖示後，'
      'onChanged 帶入 WritingMode.vertical', (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
  });

  testWidgets('點擊「滾動翻頁」圖示後，onChanged 帶入 PageTurnMode.scroll',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_page_turn_mode_scroll')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets(
      '點擊「鎖定 90°」圖示後，onChanged 帶入 ScreenOrientationSetting.lock90',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester.tap(
        find.byKey(const Key('reader_settings_screen_orientation_lock90')));
    await tester.pump();

    expect(result, isNotNull);
    expect(
      result!.screenOrientationOverride,
      ScreenOrientationSetting.lock90,
    );
  });

  testWidgets(
      '點擊排版方向覆寫圖示後，pageTurnModeOverride／screenOrientationOverride '
      '維持原值不被清空', (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: const BookReaderPrefs(
            pageTurnModeOverride: PageTurnMode.scroll,
            screenOrientationOverride: ScreenOrientationSetting.lock180,
          ),
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_horizontal')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
    expect(
      result!.screenOrientationOverride,
      ScreenOrientationSetting.lock180,
    );
  });
}
```

**注意：** 上面新增的內容取代了原檔案結尾的 `}`（`main()` 函式收尾），請確保修改後檔案只有一個 `main() { ... }` 收尾大括號。既有的 `'任一控制項互動後...三個 Issue 4 欄位維持原值不被清空'` 測試**不需要修改**——本 Task 完成後它依然成立（拖動字重滑桿不會觸碰這三個新欄位的內部狀態，效果與 passthrough 時代相同），繼續作為既有欄位不受本 Task 影響的回歸驗證。

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_settings_sheet_test.dart
```
Expected：FAIL——`Key('reader_settings_writing_mode_book')` 等新 Key 尚不存在（`findsOneWidget` 相關的 `tap()` 呼叫找不到目標 widget）。

- [ ] **Step 3：新增三個覆寫欄位與圖示選擇列**

開啟 `app/lib/screens/reader_settings_sheet.dart`。把檔案開頭 import 區塊：

```dart
import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_text_align.dart';
```

改為：

```dart
import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_text_align.dart';
import '../reader/page_turn_mode.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
```

把類別上方的文件註解：

```dart
/// 版面設定 Bottom Sheet（FR-09／FR-10 字型與數值型控制項），比照
/// prototype/index.html 第 1379-1520 行設計。排版方向／翻頁模式／螢幕方向
/// 三個覆寫選擇器屬 Issue 4，尚未加入本檔案。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數皆由呼叫端
/// （`ReaderScreen`）負責。[prefs] 中本 widget 不控制的三個欄位
/// （`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`，
/// Issue 4 範圍）在每次 [onChanged] 回呼時原樣保留，不會被清空或覆寫。
```

改為：

```dart
/// 版面設定 Bottom Sheet（FR-09／FR-10 字型、數值型控制項與三個持久化覆寫
/// 選擇器），比照 prototype/index.html 第 1379-1520 行設計。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數、螢幕方向鎖定
/// 皆由呼叫端（`ReaderScreen`）負責——本 widget 只負責回報使用者選擇的覆寫
/// 值，不負責解析「覆寫值 `??` 自動偵測結果／全域預設值」的最終生效值
/// （見 `ReaderScreen._resolvedWritingMode`／`_resolvedPageTurnMode`／
/// `_resolvedScreenOrientation`）。
```

把：

```dart
  late AppFont? _fontFamily;
  late double _fontSize;
  late double _fontWeightMultiplier; // Readium 倍率語意，UI 顯示時 ×400
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _pageMargins;
  late EpubTextAlign? _textAlign;
  late bool _publisherStyles;
```

改為：

```dart
  late AppFont? _fontFamily;
  late double _fontSize;
  late double _fontWeightMultiplier; // Readium 倍率語意，UI 顯示時 ×400
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _pageMargins;
  late EpubTextAlign? _textAlign;
  late bool _publisherStyles;
  late WritingMode? _writingModeOverride;
  late PageTurnMode? _pageTurnModeOverride;
  late ScreenOrientationSetting? _screenOrientationOverride;
```

把：

```dart
  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
    _fontWeightMultiplier =
        widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing =
        widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
    _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
    _textAlign = widget.prefs.textAlign;
    _publisherStyles = widget.prefs.publisherStyles ?? true;
  }

  @override
  void didUpdateWidget(ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      setState(() {
        _fontFamily = widget.prefs.fontFamily;
        _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
        _fontWeightMultiplier =
            widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _paragraphSpacing =
            widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
        _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
        _textAlign = widget.prefs.textAlign;
        _publisherStyles = widget.prefs.publisherStyles ?? true;
      });
    }
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      fontWeight: _fontWeightMultiplier,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      pageMargins: _pageMargins,
      textAlign: _textAlign,
      publisherStyles: _publisherStyles,
      // Issue 4 範圍的三個欄位：原樣保留，本 widget 不控制。
      writingModeOverride: widget.prefs.writingModeOverride,
      pageTurnModeOverride: widget.prefs.pageTurnModeOverride,
      screenOrientationOverride: widget.prefs.screenOrientationOverride,
    ));
  }
```

改為：

```dart
  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
    _fontWeightMultiplier =
        widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing =
        widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
    _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
    _textAlign = widget.prefs.textAlign;
    _publisherStyles = widget.prefs.publisherStyles ?? true;
    _writingModeOverride = widget.prefs.writingModeOverride;
    _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
    _screenOrientationOverride = widget.prefs.screenOrientationOverride;
  }

  @override
  void didUpdateWidget(ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      setState(() {
        _fontFamily = widget.prefs.fontFamily;
        _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
        _fontWeightMultiplier =
            widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _paragraphSpacing =
            widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
        _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
        _textAlign = widget.prefs.textAlign;
        _publisherStyles = widget.prefs.publisherStyles ?? true;
        _writingModeOverride = widget.prefs.writingModeOverride;
        _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
        _screenOrientationOverride = widget.prefs.screenOrientationOverride;
      });
    }
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      fontWeight: _fontWeightMultiplier,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      pageMargins: _pageMargins,
      textAlign: _textAlign,
      publisherStyles: _publisherStyles,
      writingModeOverride: _writingModeOverride,
      pageTurnModeOverride: _pageTurnModeOverride,
      screenOrientationOverride: _screenOrientationOverride,
    ));
  }
```

把 `build()` 方法內，`SwitchListTile`（停用書本 CSS）之後的收尾部分：

```dart
          SwitchListTile(
            key: const Key('reader_settings_disable_book_css'),
            title: const Text('停用書本 CSS'),
            value: !_publisherStyles,
            onChanged: (v) => setState(() {
              _publisherStyles = !v;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }
```

改為：

```dart
          SwitchListTile(
            key: const Key('reader_settings_disable_book_css'),
            title: const Text('停用書本 CSS'),
            value: !_publisherStyles,
            onChanged: (v) => setState(() {
              _publisherStyles = !v;
              _notifyChanged();
            }),
          ),
          const SizedBox(height: 12),
          _buildWritingModeOverrideRow(),
          const SizedBox(height: 12),
          _buildScreenOrientationOverrideRow(),
          const SizedBox(height: 12),
          _buildPageTurnModeOverrideRow(),
        ],
      ),
    );
  }
```

最後，在 `_buildTextAlignRow()` 方法結束（該方法最後一個 `}`）之後、類別結尾的 `}` 之前，新增三個方法：

```dart

  /// 排版方向覆寫（三態，FR-10）：`null`＝採用書籍排版（自動偵測結果，見
  /// `ReaderScreen._resolvedWritingMode`）、`vertical`＝強制直排、
  /// `horizontal`＝強制橫排。
  Widget _buildWritingModeOverrideRow() {
    const options = [
      (null, 'book', Icons.auto_stories, '採用書籍排版'),
      (WritingMode.vertical, 'vertical', Icons.text_rotate_vertical, '強制直排'),
      (WritingMode.horizontal, 'horizontal', Icons.text_rotation_none, '強制橫排'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('排版方向模式'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (mode, keySuffix, icon, tooltip) = option;
            final selected = _writingModeOverride == mode;
            return IconButton(
              key: Key('reader_settings_writing_mode_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _writingModeOverride = mode;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 翻頁模式覆寫（FR-10／FR-38，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedPageTurnMode`），非 `null`＝單書
  /// 覆寫。
  Widget _buildPageTurnModeOverrideRow() {
    const options = [
      (null, 'global', Icons.tune, '使用全域預設'),
      (PageTurnMode.paginated, 'paginated', Icons.menu_book, '點擊翻頁'),
      (PageTurnMode.scroll, 'scroll', Icons.swap_vert, '滾動翻頁'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('翻頁模式覆寫'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (mode, keySuffix, icon, tooltip) = option;
            final selected = _pageTurnModeOverride == mode;
            return IconButton(
              key: Key('reader_settings_page_turn_mode_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _pageTurnModeOverride = mode;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 螢幕方向覆寫（FR-10／FR-37，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedScreenOrientation`），非 `null`＝
  /// 單書覆寫。0°／180° 與 90°／270° 分別共用同一個 Material icon（無法用
  /// 單一圖示區分 4 個角度），以 tooltip 文字消歧，比照 `_buildTextAlignRow`
  /// 的既有處理方式。
  Widget _buildScreenOrientationOverrideRow() {
    const options = [
      (null, 'global', Icons.tune, '使用全域預設'),
      (
        ScreenOrientationSetting.auto,
        'auto',
        Icons.screen_rotation,
        '自動旋轉',
      ),
      (
        ScreenOrientationSetting.lock0,
        'lock0',
        Icons.stay_current_portrait,
        '鎖定 0°',
      ),
      (
        ScreenOrientationSetting.lock90,
        'lock90',
        Icons.stay_current_landscape,
        '鎖定 90°',
      ),
      (
        ScreenOrientationSetting.lock180,
        'lock180',
        Icons.stay_current_portrait,
        '鎖定 180°',
      ),
      (
        ScreenOrientationSetting.lock270,
        'lock270',
        Icons.stay_current_landscape,
        '鎖定 270°',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('螢幕方向鎖定覆寫'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (setting, keySuffix, icon, tooltip) = option;
            final selected = _screenOrientationOverride == setting;
            return IconButton(
              key: Key('reader_settings_screen_orientation_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _screenOrientationOverride = setting;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }
```

- [ ] **Step 4：執行測試確認通過**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_settings_sheet_test.dart
```
Expected：`All tests passed!`（既有 9 項 + 本 Task 新增 5 項，共 14 項）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（撰寫本計劃時基準為 126 項，本 Task 新增 5 項，共 131 項），無回歸；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "Add writing mode/page turn mode/screen orientation override rows to ReaderSettingsSheet"
```

---

### Task 2：`ReaderScreen` 雙層解析、螢幕方向鎖定，移除過渡性按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Epic 3 Issue 1 的 `GlobalReaderDefaults`（`app/lib/reader/global_reader_defaults.dart`，`loadPageTurnMode()`/`loadScreenOrientation()`，皆無需建構參數）；Task 1 完成的 `ReaderSettingsSheet`（本 Task 不直接呼叫其內部方法，只透過既有 `prefs`/`onChanged` 介面）
- Produces: `_ReaderScreenState._resolvedWritingMode`／`_resolvedPageTurnMode`／`_resolvedScreenOrientation` 三個 getter（供 Task 3 的 `integration_test` 理解畫面行為時參考，無需直接呼叫——皆為 private）

- [ ] **Step 1：撰寫失敗測試**

開啟 `app/test/screens/reader_screen_test.dart`，把整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_book_reader_prefs_repository.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支、
// 「⚙️版面」按鈕在 onLayoutResolved 觸發前的初始狀態，以及排版方向／
// 翻頁模式雙層解析邏輯（後者不依賴 onLayoutResolved，可離線驗證，見
// docs/epics/epic-3-fonts-layout/plans/plan-issue-4.md）。
void main() {
  late BookReaderPrefsRepository prefsRepository;

  setUp(() {
    prefsRepository = FakeBookReaderPrefsRepository();
    // ReaderScreen 自 Issue 4 起會呼叫 GlobalReaderDefaults（內部使用
    // SharedPreferences.getInstance()），純 Dart widget test 環境沒有真正
    // 的原生實作，須用官方支援的測試替身，比照 LibraryScreen 既有慣例。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.txt',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason:
          '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式不顯示「⚙️版面」按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(
      find.byKey(const Key('reader_layout_settings_button')),
      findsNothing,
    );
  });

  testWidgets('開啟該書已有的持久化版面偏好設定後，狀態正確載入', (tester) async {
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(fontSize: 24),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final viewFinder = find.byType(EpubReaderView);
    expect(viewFinder, findsOneWidget);
    final epubView = tester.widget<EpubReaderView>(viewFinder);
    expect(epubView.fontSize, 24.0);
  });

  testWidgets(
      'writingModeOverride 已持久化時，即使尚未收到 onLayoutResolved，'
      'EpubReaderView.writingMode 仍採用覆寫值', (tester) async {
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(writingModeOverride: WritingMode.vertical),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.writingMode, WritingMode.vertical);
    // 排版方向的雙層解析獨立於「⚙️版面」按鈕的啟用條件——後者仍要求真正
    // 收到 onLayoutResolved（見 _buildAppBarActions 的
    // _autoDetectedWritingMode 判斷），純 flutter test 環境下 AndroidView
    // 不會觸發原生回呼，因此這裡按鈕仍是停用狀態，屬預期行為，不是本測試
    // 要驗證的重點。
    expect(
      tester
          .widget<IconButton>(
              find.byKey(const Key('reader_layout_settings_button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('pageTurnModeOverride 為 null 時，未覆寫的書籍採用全域預設值（paginated）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.paginated);
  });

  testWidgets('全域預設值已改為 scroll 時，未覆寫的書籍採用該全域值', (tester) async {
    SharedPreferences.setMockInitialValues({
      'global_reader_page_turn_mode': 'scroll',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('pageTurnModeOverride 已持久化時，優先於全域預設值', (tester) async {
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(pageTurnModeOverride: PageTurnMode.scroll),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });
}
```

**注意：** 這是整份檔案的完整取代內容（相對於 Task 1 開始前的既有內容），移除了原本測試 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 兩顆按鈕的 3 個測試案例（`'EPUB 格式顯示橫直排切換按鈕，初始為停用狀態'`／`'EPUB 格式顯示換頁模式切換按鈕...'`／`'PDF 格式不顯示橫直排切換按鈕與換頁模式切換按鈕'`），新增 4 個驗證雙層解析邏輯的測試案例。

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：FAIL——`_ReaderScreenState` 尚未提供雙層解析邏輯，`EpubReaderView.writingMode`/`pageTurnMode` 仍是舊的 `_writingMode`/`_pageTurnMode` 欄位值（例如 `pageTurnMode` 恆為 `PageTurnMode.paginated` 這個舊的硬編碼預設值，`writingModeOverride` 相關斷言會失敗，因為目前完全沒有讀取這個欄位）；`GlobalReaderDefaults` 也尚未被呼叫。

- [ ] **Step 3：`ReaderScreen` 新增雙層解析邏輯、螢幕方向鎖定，移除過渡性按鈕**

開啟 `app/lib/screens/reader_screen.dart`。把檔案開頭 import 區塊：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
import 'reader_settings_sheet.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/global_reader_defaults.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';
import 'reader_settings_sheet.dart';
```

把類別 `ReaderScreen` 上方的文件註解中，這一段：

```dart
/// EPUB 格式下的橫直排切換按鈕（`reader_writing_mode_toggle`）與換頁模式
/// 切換按鈕（`reader_page_turn_mode_toggle`，Issue 4 新增）同理：純屬內部
/// 狀態管理，僅限當次閱讀 session 即時切換，不持久化（見
/// docs/epics/epic-2-vertical-core/design.md「範圍與排除項目」——持久化與
/// 三態覆寫 UI 屬 FR-10／epic-3）。
```

改為：

```dart
/// EPUB 格式下原本各自獨立的橫直排／換頁模式切換按鈕（`reader_writing_mode_toggle`／
/// `reader_page_turn_mode_toggle`，Epic 2 建立的過渡方案）已於
/// epic-3-fonts-layout Issue 4 整併進「⚙️版面」按鈕開啟的
/// `ReaderSettingsSheet`，改為三個持久化的覆寫選擇器（排版方向／翻頁模式／
/// 螢幕方向，見 [_ReaderScreenState._resolvedWritingMode]／
/// [_ReaderScreenState._resolvedPageTurnMode]／
/// [_ReaderScreenState._resolvedScreenOrientation]）。
```

把：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  PageTurnMode _pageTurnMode = PageTurnMode.paginated;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;

  @override
  void initState() {
    super.initState();
    widget.prefsRepository.load(widget.bookId).then((prefs) {
      if (!mounted) return;
      setState(() => _prefs = prefs);
    });
  }

  /// 版面設定 Bottom Sheet 任一控制項變動時呼叫：立即更新本地狀態（驅動
  /// EpubReaderView 以新值重建）並非同步持久化。不 await 持久化結果——
  /// 使用者互動的視覺回饋（畫面即時反映新設定）不應等待資料庫寫入完成，
  /// 比照本專案其餘偏好設定寫入呼叫的既有慣例（例如 LibraryPreferences
  /// 系列方法在 UI callback 中皆未 await）。
  void _handlePrefsChanged(BookReaderPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.prefsRepository.save(widget.bookId, prefs);
  }

  void _openLayoutSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Bottom Sheet 預設的下滑關閉手勢（enableDrag: true）與 Slider 的
      // 水平拖曳手勢在混合角度滑動時容易被手勢競技場誤判，導致使用者
      // 調整滑桿時選單意外關閉；停用後仍可點擊背景遮罩關閉。
      enableDrag: false,
      builder: (_) => ReaderSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }

  void _handlePageRendered() {
```

改為：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  final _globalDefaults = GlobalReaderDefaults();

  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  // 自動偵測結果（來自 onLayoutResolved），唯讀、不持久化，每次開書重新
  // 偵測（見 docs/epics/epic-3-fonts-layout/design.md「架構異動：新增
  // book_reader_prefs 資料表」）。
  WritingMode? _autoDetectedWritingMode;
  // 全域預設值（GlobalReaderDefaults，shared_preferences），供未覆寫的
  // 書籍回退使用；初始值與擴充前的硬編碼預設一致（paginated／auto），
  // 避免非同步載入完成前出現行為落差。
  PageTurnMode _globalPageTurnMode = PageTurnMode.paginated;
  ScreenOrientationSetting _globalScreenOrientation =
      ScreenOrientationSetting.auto;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;

  /// 排版方向最終生效值：單書覆寫優先於自動偵測結果。onLayoutResolved
  /// 尚未觸發、且沒有持久化覆寫時為 null。
  WritingMode? get _resolvedWritingMode =>
      _prefs.writingModeOverride ?? _autoDetectedWritingMode;

  /// 翻頁模式最終生效值：單書覆寫優先於全域預設值。
  PageTurnMode get _resolvedPageTurnMode =>
      _prefs.pageTurnModeOverride ?? _globalPageTurnMode;

  /// 螢幕方向最終生效值：單書覆寫優先於全域預設值。
  ScreenOrientationSetting get _resolvedScreenOrientation =>
      _prefs.screenOrientationOverride ?? _globalScreenOrientation;

  @override
  void initState() {
    super.initState();
    // 單書偏好設定與兩項全域預設值彼此獨立、互不依賴，一次併發載入完成
    // 後才更新狀態並套用螢幕方向鎖定——避免分開 await 造成畫面在載入期間
    // 出現多段不同時機的中繼閃爍。
    Future.wait([
      widget.prefsRepository.load(widget.bookId),
      _globalDefaults.loadPageTurnMode(),
      _globalDefaults.loadScreenOrientation(),
    ]).then((results) {
      if (!mounted) return;
      setState(() {
        _prefs = results[0] as BookReaderPrefs;
        _globalPageTurnMode = results[1] as PageTurnMode;
        _globalScreenOrientation = results[2] as ScreenOrientationSetting;
      });
      _applyScreenOrientation();
    });
  }

  @override
  void dispose() {
    // 還原系統預設（允許自由旋轉），不論進入閱讀器時鎖定了哪個角度，比照
    // 音量鍵離開閱讀介面後恢復正常系統音量控制的既有處理原則，避免鎖定
    // 狀態外溢到書架等其他畫面。
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// 依 [_resolvedScreenOrientation] 呼叫 SystemChrome 套用真實 OS 層級
  /// 鎖定（非僅內容排版層級的假象）。角度與 [DeviceOrientation] 的對應
  /// 是本 issue 撰寫計劃階段決定的慣例（0°→portraitUp、90°→landscapeLeft、
  /// 180°→portraitDown、270°→landscapeRight），實際物理旋轉是否與這組
  /// 對應一致，留待真機測試以驗收標準的人工視覺 QA 確認。
  void _applyScreenOrientation() {
    SystemChrome.setPreferredOrientations(
      _deviceOrientationsFor(_resolvedScreenOrientation),
    );
  }

  List<DeviceOrientation> _deviceOrientationsFor(
    ScreenOrientationSetting setting,
  ) {
    switch (setting) {
      case ScreenOrientationSetting.auto:
        return const [];
      case ScreenOrientationSetting.lock0:
        return const [DeviceOrientation.portraitUp];
      case ScreenOrientationSetting.lock90:
        return const [DeviceOrientation.landscapeLeft];
      case ScreenOrientationSetting.lock180:
        return const [DeviceOrientation.portraitDown];
      case ScreenOrientationSetting.lock270:
        return const [DeviceOrientation.landscapeRight];
    }
  }

  /// 版面設定 Bottom Sheet 任一控制項變動時呼叫：立即更新本地狀態（驅動
  /// EpubReaderView 以新值重建）並非同步持久化，同時重新套用螢幕方向鎖定
  /// （screenOrientationOverride 可能剛被這次變動改變）。不 await 持久化
  /// 結果——使用者互動的視覺回饋（畫面即時反映新設定）不應等待資料庫寫入
  /// 完成，比照本專案其餘偏好設定寫入呼叫的既有慣例（例如
  /// LibraryPreferences 系列方法在 UI callback 中皆未 await）。
  void _handlePrefsChanged(BookReaderPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.prefsRepository.save(widget.bookId, prefs);
    _applyScreenOrientation();
  }

  void _openLayoutSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Bottom Sheet 預設的下滑關閉手勢（enableDrag: true）與 Slider 的
      // 水平拖曳手勢在混合角度滑動時容易被手勢競技場誤判，導致使用者
      // 調整滑桿時選單意外關閉；停用後仍可點擊背景遮罩關閉。
      enableDrag: false,
      builder: (_) => ReaderSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }

  void _handlePageRendered() {
```

把：

```dart
  /// 【已知、可接受的行為】把自動偵測結果寫回 [_writingMode] 後，會驅動
  /// EpubReaderView 以非 null 值重建；EpubReaderView 的 didUpdateWidget 偵測
  /// 到「null → 非 null」的變化時，會多送一次 setWritingMode 給原生端，等於
  /// 把 Readium 剛剛自動判斷好的值重新套用一次。這是多餘但無害的呼叫（目前
  /// 沒有其他偏好設定會被覆蓋，見 EpubReaderView.kt 的 setWritingMode 註解），
  /// 不特地加狀態去抑制它，避免為了避免一次無害的重複呼叫而增加複雜度。
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _writingMode = info.writingMode;
    });
  }

  void _toggleWritingMode() {
    setState(() {
      _writingMode = _writingMode == WritingMode.vertical
          ? WritingMode.horizontal
          : WritingMode.vertical;
    });
  }

  void _togglePageTurnMode() {
    setState(() {
      _pageTurnMode = _pageTurnMode == PageTurnMode.scroll
          ? PageTurnMode.paginated
          : PageTurnMode.scroll;
    });
  }

  @override
  Widget build(BuildContext context) {
```

改為：

```dart
  /// 【已知、可接受的行為】把自動偵測結果寫回 [_autoDetectedWritingMode]
  /// 後，若當下沒有 writingModeOverride，[_resolvedWritingMode] 會從 null
  /// 變成非 null，驅動 EpubReaderView 以非 null 值重建；EpubReaderView 的
  /// didUpdateWidget 偵測到「null → 非 null」的變化時，會多送一次
  /// setPreferences 給原生端，等於把 Readium 剛剛自動判斷好的值重新套用
  /// 一次。這是多餘但無害的呼叫（見 EpubReaderView.kt 的 setPreferences
  /// 註解——currentPreferences.plus() 合併語意，不會覆蓋其他已生效欄位），
  /// 不特地加狀態去抑制它，避免為了避免一次無害的重複呼叫而增加複雜度。
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
    });
  }

  @override
  Widget build(BuildContext context) {
```

把：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_writing_mode_toggle'),
        icon: Icon(
          _writingMode == WritingMode.vertical
              ? Icons.text_rotation_none
              : Icons.text_rotate_vertical,
        ),
        tooltip: _writingMode == WritingMode.vertical ? '切換為橫排' : '切換為直排',
        onPressed: _writingMode == null ? null : _toggleWritingMode,
      ),
      IconButton(
        key: const Key('reader_page_turn_mode_toggle'),
        icon: Icon(
          _pageTurnMode == PageTurnMode.scroll ? Icons.menu_book : Icons.swap_vert,
        ),
        tooltip:
            _pageTurnMode == PageTurnMode.scroll ? '切換為分頁模式' : '切換為捲動模式',
        // 與橫直排切換按鈕共用同一個啟用條件：_writingMode 非 null 代表
        // onLayoutResolved 已觸發，書本已成功開啟、navigatorFragment 已存在，
        // 此時呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的
        // 靜默忽略邏輯說明）。
        onPressed: _writingMode == null ? null : _togglePageTurnMode,
      ),
      IconButton(
        key: const Key('reader_layout_settings_button'),
        icon: const Icon(Icons.settings),
        tooltip: '版面設定',
        onPressed: _writingMode == null ? null : _openLayoutSettings,
      ),
    ];
  }
```

改為：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_layout_settings_button'),
        icon: const Icon(Icons.settings),
        tooltip: '版面設定',
        // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
        // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並呼叫
        // setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略邏輯
        // 說明）。
        onPressed:
            _autoDetectedWritingMode == null ? null : _openLayoutSettings,
      ),
    ];
  }
```

最後把：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          pageTurnMode: _pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: _prefs.fontFamily,
          fontSize: _prefs.fontSize,
          fontWeight: _prefs.fontWeight,
          lineHeight: _prefs.lineHeight,
          paragraphSpacing: _prefs.paragraphSpacing,
          pageMargins: _prefs.pageMargins,
          textAlign: _prefs.textAlign,
          publisherStyles: _prefs.publisherStyles,
        );
```

改為：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _resolvedWritingMode,
          pageTurnMode: _resolvedPageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: _prefs.fontFamily,
          fontSize: _prefs.fontSize,
          fontWeight: _prefs.fontWeight,
          lineHeight: _prefs.lineHeight,
          paragraphSpacing: _prefs.paragraphSpacing,
          pageMargins: _prefs.pageMargins,
          textAlign: _prefs.textAlign,
          publisherStyles: _prefs.publisherStyles,
        );
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：`All tests passed!`（8 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（Task 1 完成後基準 131 項，本 Task 移除 3 項舊測試、新增 4 項新測試，淨增 1 項，共 132 項）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：建置確認原生端無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter build apk --debug
```
Expected：建置成功（本 Task 未修改任何 Kotlin 檔案，此步驟純粹確認 Dart 端改動沒有意外破壞建置流程）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Add writing mode/page turn mode dual-layer resolution and screen orientation lock to ReaderScreen"
```

---

### Task 3：真機驗證——覆寫選擇器互動與螢幕方向鎖定/還原，移除舊按鈕的裝置測試

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 完成的三個覆寫圖示 Key、Task 2 完成的 `ReaderScreen` 雙層解析與螢幕方向鎖定邏輯
- Produces: 無新介面（純測試驗證）

**⚠️ 執行前環境確認事項：** 本 Task 的驗證步驟須在真實 Android 裝置/模擬器上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器（撰寫本計劃時已確認裝置 9491G 可用，Android 15/API 35，ID：`3CEF42ECD491687`——下方指令中的裝置 ID 即指這台裝置）。

- [ ] **Step 1：於 `integration_test/reader_screen_test.dart` 移除舊按鈕測試、修正讀取信號、新增覆寫與螢幕方向測試**

開啟 `app/integration_test/reader_screen_test.dart`，把整份內容改為：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。原生
/// 渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，不能直接
/// 讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到 [condition] 成立或逾時。`ReaderScreen` 對外只有 filePath
/// 一個建構參數（見 spec.md 的 seam 定義），onPageRendered/onError 是內部
/// 實作細節，因此本檔案用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

/// 判斷「⚙️版面」按鈕是否已就緒（存在且可點擊）。`onLayoutResolved` 觸發前
/// `_autoDetectedWritingMode` 為 null，此時按鈕的 `onPressed` 亦為 null
/// （見 reader_screen.dart 的 `_buildAppBarActions`），因此以此作為「自動
/// 偵測已完成」的觀察點——取代 Issue 4 移除的 `reader_writing_mode_toggle`
/// 讀取信號。
bool _layoutSettingsButtonReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_layout_settings_button'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}

Book _book(String id) => Book(
      id: id,
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ReaderScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。真實裝置上用記憶體
  // 資料庫即可，這些既有測試情境本身不驗證版面偏好設定的持久化行為
  // （持久化驗證見既有的 Bottom Sheet 互動測試）。
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('開啟定樣式範例 EPUB，⚙️版面按鈕最終不顯示', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_toggle_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          _loadingIndicatorGone() &&
          find
              .byKey(const Key('reader_layout_settings_button'))
              .evaluate()
              .isEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟版面設定 Bottom Sheet，調整字型大小後畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_font_size.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_settings_1'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_settings_1',
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

    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '調整字型大小後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('調整版面設定後關閉重開該書，設定被正確記住（驗證 initialPreferences 生效）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_persist.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_settings_persist';
    await libraryRepository.insertBook(_book(bookId));

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
    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    // 給非同步的 BookReaderPrefsRepository.save() 足夠時間完成寫入，避免
    // 下方關閉重開的讀取搶在寫入完成前發生（widget test 環境下兩者共用
    // 同一個 event loop，不需要真的等很久，但仍需保守給一個緩衝）。
    await tester.pump(const Duration(milliseconds: 500));

    // 關閉目前畫面，模擬使用者離開閱讀器（觸發 EpubReaderView.dispose()
    // 釋放原生資源），再重新開啟同一本書。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final reloadedPrefs = await prefsRepository.load(bookId);
    expect(reloadedPrefs.fontSize, 17.0,
        reason: '初始值為 null（顯示原型預設 16），點擊一次 + 按鈕後應存成 17');

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

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '帶著已持久化的 fontSize=17 重新開書，應正常渲染、不觸發 onError'
            '（驗證 EpubReaderView 的 initialPreferences 機制在真實裝置上正確運作）');
  });

  testWidgets('點擊排版方向覆寫圖示「強制直排」後，畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_writing_mode_override.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_writing_mode_override'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_writing_mode_override',
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

    await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '點擊「強制直排」覆寫圖示後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('點擊翻頁模式覆寫圖示「滾動翻頁」後，畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_page_turn_mode_override.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_page_turn_mode_override'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_page_turn_mode_override',
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

    await tester
        .tap(find.byKey(const Key('reader_settings_page_turn_mode_scroll')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '點擊「滾動翻頁」覆寫圖示後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets(
      '未覆寫螢幕方向時，進入 ReaderScreen 後依全域預設值呼叫 '
      'SystemChrome.setPreferredOrientations（auto→空列表）', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_default.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_orientation_default',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );

    final call = calls.firstWhere(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(call.arguments, isEmpty,
        reason: 'ScreenOrientationSetting.auto（未覆寫時的全域預設值）'
            '應對應空列表（允許全部方向）');
  });

  testWidgets(
      'screenOrientationOverride=lock90 時，SystemChrome.setPreferredOrientations '
      '帶入 landscapeLeft', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const bookId = 'b_orientation_lock90';
    await libraryRepository.insertBook(_book(bookId));
    await prefsRepository.save(
      bookId,
      const BookReaderPrefs(
        screenOrientationOverride: ScreenOrientationSetting.lock90,
      ),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_lock90.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

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
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );

    final call = calls.firstWhere(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(call.arguments, ['DeviceOrientation.landscapeLeft']);
  });

  testWidgets('離開 ReaderScreen 後，SystemChrome.setPreferredOrientations([]) 被呼叫還原',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const bookId = 'b_orientation_dispose';
    await libraryRepository.insertBook(_book(bookId));
    await prefsRepository.save(
      bookId,
      const BookReaderPrefs(
        screenOrientationOverride: ScreenOrientationSetting.lock0,
      ),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_dispose.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

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
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );
    calls.clear();

    // 離開畫面（觸發 ReaderScreen.dispose()），比照既有「關閉重開該書」
    // 測試模擬使用者離開閱讀器的既有手法。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(
      calls.any((c) =>
          c.method == 'SystemChrome.setPreferredOrientations' &&
          (c.arguments as List).isEmpty),
      isTrue,
      reason: 'dispose() 應呼叫 SystemChrome.setPreferredOrientations([]) '
          '還原系統預設，不論進入時鎖定了哪個角度',
    );
  });
}
```

**注意：** 這是整份檔案的完整取代內容。與 Task 3 開始前相比，移除了測試 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 行為本身的 5 個測試案例（直排/橫排提示切換、點擊切換按鈕提示反轉、換頁模式按鈕啟用/點擊反轉），`'開啟定樣式範例 EPUB...'` 測試改用 `reader_layout_settings_button` 觀察（取代原本的 `reader_writing_mode_toggle`），既有 Bottom Sheet 互動測試的讀取信號從 `_writingModeToggleReady` 改為 `_layoutSettingsButtonReady`，新增 5 個測試（排版方向/翻頁模式覆寫互動、螢幕方向鎖定/還原的呼叫記錄驗證）。

- [ ] **Step 2：於真實裝置上執行測試確認全部通過**

Run（於 `app/` 目錄下；裝置 ID 請以 `flutter devices` 實際列出的為準，撰寫本計劃時為 `3CEF42ECD491687`）：
```bash
flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687
```
Expected：`All tests passed!`（10 項測試）。

- [ ] **Step 3：重新執行既有 `integration_test` 套件確認無回歸**

Run：
```bash
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
```
Expected：`All tests passed!`。

- [ ] **Step 4：靜態分析、建置與純 Dart 測試最終確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test` 全數通過（132 項），無回歸。

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "Add device-verified tests for override selectors and screen orientation lock/restore"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** `issues.md` Issue 4 列出的三個覆寫選擇器（排版方向三態、翻頁模式雙層解析、螢幕方向雙層解析＋真實 OS 鎖定）皆對應到 Task 1（`ReaderSettingsSheet` UI）＋Task 2（`ReaderScreen` 解析邏輯）；「移除現有兩顆過渡性按鈕」對應 Task 2（程式碼）＋Task 3（測試）；`integration_test` 驗收標準（螢幕方向鎖定生效、離開後還原、`reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 已移除）對應 Task 3。
- **本 issue 未新增任何 ADR：** 唯一的新設計決策（`ScreenOrientationSetting` → `DeviceOrientation` 的角度對應慣例、螢幕方向圖示重複使用＋tooltip 消歧）皆屬實作細節、可低成本日後調整，不符合 domain-modeling skill 的 ADR 三要件（難以逆轉／缺乏脈絡會讓人意外／真正的權衡取捨），已在「全域限制條件」與程式碼註解中記錄理由，不另立 ADR。
- **`GlobalReaderDefaults` 的依賴取得方式：** 比照既有 `LibraryScreen._preferences = LibraryPreferences();` 慣例直接實例化，不透過 ADR 0007 的建構子注入路徑——已在「全域限制條件」明確記錄兩者適用情境不同的理由（`BookReaderPrefsRepository` 需要與資料庫共用連線；`GlobalReaderDefaults` 純 `shared_preferences`，無此需求）。
- **與既有慣例的一致性：** `ReaderSettingsSheet` 新增的三個覆寫圖示列沿用既有 `_buildTextAlignRow` 的圖示＋tooltip 消歧設計；`ReaderScreen` 新增的 resolved getter 與 `_applyScreenOrientation` 沿用既有 `_handlePrefsChanged` 不 await 持久化結果的既有慣例；`Key` 命名沿用既有 `reader_settings_*`／`reader_*` 前綴慣例。
- **測試技巧：** 排版方向／翻頁模式的雙層解析邏輯經確認不依賴 `onLayoutResolved`（`_autoDetectedWritingMode` 為 null 時，只要有 `writingModeOverride` 持久化值，`_resolvedWritingMode` 仍非 null），因此改寫為 `app/test/screens/reader_screen_test.dart` 的純 Dart widget test，不需要真實裝置，比原先設想的「必須留給 integration_test」更快、更可靠；螢幕方向鎖定/還原則依 issues.md 原文（「可透過方法呼叫記錄斷言，不需要真的觀察裝置實際轉動」）採用 `TestDefaultBinaryMessengerBinding` 攔截 `SystemChannels.platform` 的方式驗證，技術上不需要真實裝置，但仍安排在 Task 3 的 `integration_test` 檔案內於真機執行，取得額外的真機環境確信度（比照本 issue 其餘裝置測試的一貫作法）。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出，無 TBD/佔位文字。
- **型別/命名一致性：** `WritingMode`／`PageTurnMode`／`ScreenOrientationSetting` 全程與 Epic 3 Issue 1 建立的既有列舉型別一致，未新增或修改任何列舉值；`_resolvedWritingMode`／`_resolvedPageTurnMode`／`_resolvedScreenOrientation` 三個 getter 名稱與 Task 2 文件註解、Task 3 測試註解引用的名稱逐字一致。
- **已知、記錄在案但刻意不處理的情形：** `ScreenOrientationSetting` 角度與 `DeviceOrientation` 的對應關係（0°→portraitUp 等）是本計劃撰寫階段自行決定的慣例，非官方保證的一一對應規則，實際物理旋轉是否與此一致，留待驗收標準的人工視覺 QA 確認；若實機測試發現對應關係錯誤（例如「鎖定 90°」實際鎖住的是另一個角度），屬程式碼一行 `switch` 分支的修正，不影響其餘架構。
