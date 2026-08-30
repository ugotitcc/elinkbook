# Epic 28 Issue 5 — 版面設定畫面 Tab 化重構（`ReaderSettingsSheet`） 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ReaderSettingsSheet` 從單一 `ListView(shrinkWrap: true)` 平鋪全部控制項，改為 4 個 Tab 頁籤（文字內容／邊界首尾／版面呈現／設定喜好），比照既有 `TocBottomSheet` 先例讓 Bottom Sheet 撐到近全螢幕高度、各頁籤各自獨立捲動，大幅減少使用者需要的捲動量。

**Architecture:** 純 UI 層重構，不改動 `BookReaderPrefs`／`LayoutPreset`／任何 Repository。核心變更是 `build()` 的根 `Column` 從 `mainAxisSize: MainAxisSize.min`（依內容縮小）改為預設 `mainAxisSize: MainAxisSize.max`，新增 `Expanded(child: DefaultTabController(length: 4, child: Column(children: [TabBar(...), Expanded(child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [...]))])))`——`Expanded` 需要有界高度，`showModalBottomSheet(isScrollControlled: true)` 恰好提供這個上限（技術路徑已由既有 `TocBottomSheet`，`app/lib/screens/toc_bottom_sheet.dart:178-202` 驗證過）。4 個頁籤只是同一個 `_ReaderSettingsSheetState.build()` 內呼叫既有 `_buildXxx()` 方法組成的展示分支（例如 `_buildTextContentTab()` 內部呼叫既有的 `_buildFontFamilyDropdown()`／`_buildSliderRow()`），**不是**獨立的 `StatefulWidget`——這些方法本來就是同一個 State 的私有方法、直接讀寫同一組欄位（例如 `_fontSizeOverridden`），Tab 切換只是 `TabBarView` 內部 `PageView` 顯示哪一頁，不會重建或遺失任何狀態，因此 Issue 4 新增的 5 個「是否已覆寫」旗標天生安全，不需要額外防禦程式碼。

**刻意的行為改變（非回歸）：** 因為根 `Column` 不再 `mainAxisSize: MainAxisSize.min`，`ReaderSettingsSheet` 從此一律撐到 `showModalBottomSheet(isScrollControlled: true)` 提供的近全螢幕高度上限，不再依內容量縮小——既有測試「內容小於可用高度時，Bottom Sheet 保持緊湊包裹」（`reader_settings_sheet_test.dart:892-907`）斷言的正是舊行為，本計畫 Task 4 會明確把它改寫成斷言新行為，這是設計決策的必然結果，不是遺漏。

**Tech Stack:** Flutter/Dart（`DefaultTabController`／`TabBar`／`TabBarView`／`NeverScrollableScrollPhysics`，皆為 Flutter SDK 內建，無新增依賴）。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/issues.md`「Issue 5」、`design.md`「2026-08-15 追加」與其「審查回應」小節（`TabBarView` 手勢衝突／狀態穩定性／測試遷移三項審查結論皆已回寫進 `issues.md` Issue 5 內文，本計畫直接依 `issues.md` 現況執行）。

## Global Constraints

- 只修改 `app/lib/screens/reader_settings_sheet.dart` 與 `app/test/screens/reader_settings_sheet_test.dart`（不改動 `reader_screen.dart` 或任何呼叫端——`ReaderSettingsSheet` 對外建構參數與 `onChanged`／`onSaveAsPreset` 等 5 個 callback 簽章完全不變）。
- `TabBarView` 必須設定 `physics: const NeverScrollableScrollPhysics()`（`issues.md` Issue 5 Solution 第 5 點），只能點擊 `TabBar` 切換，避免與頁籤內的 `Slider` 搶手勢競技場。
- 4 個頁籤標籤與內容分配（逐字依 `issues.md` Issue 5）：
  - **文字內容**（Tab index 0，預設頁籤）：`_buildFontFamilyDropdown()`、`reader_settings_font_size`／`reader_settings_font_weight`／`reader_settings_line_height`／`reader_settings_paragraph_spacing`／`reader_settings_letter_spacing` 這 5 個 `_buildSliderRow()`、`reader_settings_disable_book_css`（`_publisherStyles` 開關）。
  - **邊界首尾**（Tab index 1）：`reader_settings_margin_top`／`_bottom`／`_left`／`_right` 這 4 個 `_buildSliderRow()`、`reader_settings_show_header`／`reader_settings_show_footer`（`_showHeader`/`_showFooter` 開關）、`_buildTextAlignRow()`。
  - **版面呈現**（Tab index 2）：`reader_settings_fullscreen`（`_fullscreen` 開關）、`_buildColumnModeRow()`、`_buildWritingModeOverrideRow()`、`_buildScreenOrientationOverrideRow()`、`_buildPageTurnModeOverrideRow()`。
  - **設定喜好**（Tab index 3）：`_buildLayoutPresetSection()`（版面設定預設集＋從其他書籍複製，維持現有合併在同一區塊）。
- 4 個頁籤只是 `build()` 分支，一律不得為個別頁籤內容抽出獨立的 `StatefulWidget`；所有草稿狀態維持在 `_ReaderSettingsSheetState` 根層級不動。
- 既有控制項的操作邏輯與測試 `Key`（例如 `reader_settings_font_size_slider`）一律逐位元組不變，只是被移動到不同的 Tab 容器內。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：寫失敗測試——Tab 切換行為＋橫向拖曳手勢不誤觸換頁

**Files:**
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: 既有 `_pumpSheet()`（測試 helper，`reader_settings_sheet_test.dart:1197-1235`）、`BookReaderPrefs.empty`。
- Produces: 新增共用測試 helper `Future<void> switchToTab(WidgetTester tester, String tabLabel)`，供本檔案後續所有測試（Task 3／Task 4／Task 5）呼叫；新增 4 個測試用 `Key`（`reader_settings_tab_text_content`／`_boundary`／`_presentation`／`_preferences`，掛在對應 `Tab` widget 上，本 Task 只在測試裡引用其文字，Task 2 才會真正建立）與 4 個 Tab 內容 `ListView` 的 `Key`（`reader_settings_tab_text_content_list`／`_boundary_list`／`_presentation_list`／`_preferences_list`，供 Task 4 的捲動測試使用）。

- [ ] **Step 1：新增 `switchToTab` helper 與 3 則新測試**

編輯 `app/test/screens/reader_settings_sheet_test.dart`，在檔案最下方 `_pumpModalSheet` 函式（第 1287-1319 行）之後新增：

```dart
/// 點擊 `TabBar` 上文字為 [tabLabel] 的頁籤並等待切換動畫完成
/// （epic-28-reader-settings-enhancements Issue 5）。
Future<void> switchToTab(WidgetTester tester, String tabLabel) async {
  await tester.tap(find.widgetWithText(Tab, tabLabel));
  await tester.pumpAndSettle();
}
```

在 `void main() {` 開頭（第 13 行）之後、既有第一則測試「初始值正確反映傳入的 BookReaderPrefs」之前，新增以下 3 則測試：

```dart
  testWidgets(
      '4 個頁籤皆可切換，切換後對應欄位的既有 Key 可見、其餘頁籤內容不可見'
      '（epic-28-reader-settings-enhancements Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    // 預設應停在「文字內容」頁籤（index 0）。
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsNothing);

    await switchToTab(tester, '邊界首尾');
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsNothing);

    await switchToTab(tester, '版面呈現');
    expect(
        find.byKey(const Key('reader_settings_fullscreen')), findsOneWidget);
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsNothing);

    await switchToTab(tester, '設定喜好');
    expect(find.byKey(const Key('reader_settings_save_as_preset')),
        findsOneWidget);
    expect(
        find.byKey(const Key('reader_settings_fullscreen')), findsNothing);

    await switchToTab(tester, '文字內容');
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_save_as_preset')),
        findsNothing);
  });

  testWidgets(
      '在「文字內容」頁籤內對 Slider 做橫向拖曳手勢，頁籤不會被意外切換'
      '（epic-28-reader-settings-enhancements Issue 5：TabBarView 需設定 '
      'NeverScrollableScrollPhysics，避免與 Slider 搶手勢競技場）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    final tabController = DefaultTabController.of(
      tester.element(find.byKey(const Key('reader_settings_font_size_slider'))),
    );
    expect(tabController.index, 0);

    await tester.drag(
      find.byKey(const Key('reader_settings_font_size_slider')),
      const Offset(200, 0),
    );
    await tester.pump();

    expect(tabController.index, 0,
        reason: '對 Slider 的橫向拖曳應被 Slider 自己吃掉並調整數值，不應被 TabBarView '
            '判定為切換頁籤手勢');
  });

  testWidgets(
      '在「邊界首尾」頁籤內對邊界 Slider 做橫向拖曳手勢，頁籤不會被意外切換'
      '（epic-28-reader-settings-enhancements Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '邊界首尾');

    final tabController = DefaultTabController.of(
      tester.element(find.byKey(const Key('reader_settings_margin_top_slider'))),
    );
    expect(tabController.index, 1);

    await tester.drag(
      find.byKey(const Key('reader_settings_margin_top_slider')),
      const Offset(200, 0),
    );
    await tester.pump();

    expect(tabController.index, 1);
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "頁籤"`

預期：3 則新測試皆 FAIL（`find.widgetWithText(Tab, ...)` 與 `find.byKey('reader_settings_fullscreen')`／`'reader_settings_save_as_preset'` 等目前並存於同一個可視畫面，`findsNothing` 斷言會失敗；`DefaultTabController.of()` 會因為找不到 `DefaultTabController` 祖先直接拋出例外）——這是預期中的紅燈，Task 2 會讓它們轉綠。

---

### Task 2：實作 Tab 容器骨架，既有控制項分配進 4 個頁籤

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:213-451`（`build()` 方法本體）

**Interfaces:**
- Consumes: Task 1 定義的 4 個 Tab 標籤文字（`'文字內容'`／`'邊界首尾'`／`'版面呈現'`／`'設定喜好'`）。
- Produces：新增 4 個私有方法 `_buildTextContentTab()`／`_buildBoundaryTab()`／`_buildPresentationTab()`／`_buildPreferencesTab()`，皆回傳 `Widget`（內部為 `ListView`），供 `build()` 的 `TabBarView.children` 使用；不新增/修改任何既有 `_buildXxx()` 方法的簽章。

- [ ] **Step 1：改寫 `build()`，新增 4 個 Tab 內容方法**

編輯 `app/lib/screens/reader_settings_sheet.dart`，將整個 `build()` 方法（第 213-451 行，從 `@override\n  Widget build(BuildContext context) {` 到對應的收尾 `}`）替換為：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '⚙️ 版面設定',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const Key('reader_settings_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    key: Key('reader_settings_tab_bar'),
                    tabs: [
                      Tab(
                        key: Key('reader_settings_tab_text_content'),
                        text: '文字內容',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_boundary'),
                        text: '邊界首尾',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_presentation'),
                        text: '版面呈現',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_preferences'),
                        text: '設定喜好',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildTextContentTab(),
                        _buildBoundaryTab(),
                        _buildPresentationTab(),
                        _buildPreferencesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextContentTab() {
    return ListView(
      key: const Key('reader_settings_tab_text_content_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildFontFamilyDropdown(),
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
        const SizedBox(height: 12),
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
    );
  }

  Widget _buildBoundaryTab() {
    return ListView(
      key: const Key('reader_settings_tab_boundary_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_top',
          label: '上邊界',
          value: _marginTop,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginTop.round().toString(),
          onChanged: (v) => setState(() {
            _marginTop = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_bottom',
          label: '下邊界',
          value: _marginBottom,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginBottom.round().toString(),
          onChanged: (v) => setState(() {
            _marginBottom = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_left',
          label: '左邊界',
          value: _marginLeft,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginLeft.round().toString(),
          onChanged: (v) => setState(() {
            _marginLeft = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_right',
          label: '右邊界',
          value: _marginRight,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginRight.round().toString(),
          onChanged: (v) => setState(() {
            _marginRight = v;
            _notifyChanged();
          }),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('reader_settings_show_header'),
          title: const Text('顯示頁首'),
          value: _showHeader,
          onChanged: (v) => setState(() {
            _showHeader = v;
            _notifyChanged();
          }),
        ),
        SwitchListTile(
          key: const Key('reader_settings_show_footer'),
          title: const Text('顯示頁尾'),
          value: _showFooter,
          onChanged: (v) => setState(() {
            _showFooter = v;
            _notifyChanged();
          }),
        ),
        const SizedBox(height: 12),
        _buildTextAlignRow(),
      ],
    );
  }

  Widget _buildPresentationTab() {
    return ListView(
      key: const Key('reader_settings_tab_presentation_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        SwitchListTile(
          key: const Key('reader_settings_fullscreen'),
          title: const Text('全螢幕模式'),
          value: _fullscreen,
          onChanged: (v) => setState(() {
            _fullscreen = v;
            _notifyChanged();
          }),
        ),
        const SizedBox(height: 8),
        _buildColumnModeRow(),
        const SizedBox(height: 8),
        _buildWritingModeOverrideRow(),
        const SizedBox(height: 8),
        _buildScreenOrientationOverrideRow(),
        const SizedBox(height: 8),
        _buildPageTurnModeOverrideRow(),
      ],
    );
  }

  Widget _buildPreferencesTab() {
    return ListView(
      key: const Key('reader_settings_tab_preferences_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildLayoutPresetSection(),
      ],
    );
  }
```

`_buildColumnModeRow()`／`_buildFontFamilyDropdown()`／`_buildSliderRow()`／`_buildTextAlignRow()`／`_buildWritingModeOverrideRow()`／`_buildPageTurnModeOverrideRow()`／`_buildScreenOrientationOverrideRow()`／`_buildLayoutPresetSection()`／`_buildPresetSlot()` 與其後所有方法（第 453 行之後）**維持逐位元組不變**，不需要任何修改。

- [ ] **Step 2：執行 Task 1 測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "頁籤"`

預期：Task 1 新增的 3 則測試全數 PASS。

- [ ] **Step 3：執行完整測試檔，確認已知範圍的失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：**大量既有測試 FAIL**——這是預期中的結果，不是本 Step 的錯誤。原因：多數既有測試假設所有欄位在同一個可視畫面內，現在分頁後找不到不在「文字內容」（預設頁籤）內的元件。Task 3／Task 4 會逐一修正。執行後記下失敗測試數量，供 Task 3／Task 4 完成後比對（應歸零）。

---

### Task 3：遷移「只需切換到正確頁籤」的既有測試（機械式，依頁籤分組）

**Files:**
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 新增的 `switchToTab(WidgetTester tester, String tabLabel)`。

以下每一則測試，找到其 `await _pumpSheet(...)` 呼叫（多行呼叫時以其收尾的 `);` 為準）之後、第一個 `await tester.tap`/`tester.drag`/其他互動呼叫之前，插入對應的 `await switchToTab(tester, '<標籤>');`。「文字內容」是預設頁籤（index 0），以下測試皆不需要任何修改（僅供核對用途，不是本 Task 的操作項目）：「只調整字距 + 按鈕」「依序調整 5 個受影響欄位」「按下字距重置按鈕後」「按下字型大小重置按鈕後」「點擊字型大小 + 按鈕後」「拖動字重滑桿到 UI 值 700」「選擇字型下拉選單」「切換「停用書本 CSS」開關後」「點擊字距 + 按鈕後」「字型選單合併顯示」「選擇自訂字型後」「點擊關閉按鈕後」——這些測試互動的元件全在「文字內容」頁籤或 Tab 容器外層（關閉按鈕），維持不動。**「5 個受本 Issue 影響欄位皆為 null 時」這則測試不屬於此類**，雖然只調整就能通過表面斷言，但需要真正切到「邊界首尾」頁籤才能驗證「不適用」是設計使然而非巧合，處理方式見 Task 4 Step 3，不在本 Task 範圍。

- [ ] **Step 1：「邊界首尾」頁籤，9 則測試插入 `switchToTab(tester, '邊界首尾')`**

| 測試描述（用於定位） | 插入位置 |
| --- | --- |
| `只切換「顯示頁首」開關，onChanged 帶出的字級/粗細/行高/段落間距/字距皆維持 null（epic-28-reader-settings-enhancements Issue 4：草稿具現化不應覆寫書本原生樣式）` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_show_header')))` 之前 |
| `點擊上邊界 + 按鈕後，onChanged 帶入 marginTop+2 且其他欄位不變` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_margin_top_increment')))` 之前 |
| `點擊文字對齊「置中」圖示後，onChanged 帶入 EpubTextAlign.center` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_text_align_center')))` 之前 |
| `任一控制項互動後，writingModeOverride/pageTurnModeOverride/screenOrientationOverride 三個 Issue 4 欄位維持原值不被清空` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_text_align_justify')))` 之前 |
| `頁首/頁尾開關初始值反映 prefs（未持久化時預設關閉）` | `_pumpSheet(...)` 之後、第一個 `expect(tester.widget<SwitchListTile>(find.byKey(const Key('reader_settings_show_header')))...)` 之前 |
| `已持久化 showHeader=false 時，頁首開關初始值反映為關閉` | `_pumpSheet(...)` 之後、`expect(tester.widget<SwitchListTile>(find.byKey(const Key('reader_settings_show_header')))...)` 之前 |
| `關閉頁首開關後，onChanged 帶入 showHeader=false 且不影響 showFooter` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_show_header')))` 之前 |
| `關閉頁尾開關後，onChanged 帶入 showFooter=false 且不影響 showHeader` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_show_footer')))` 之前 |
| `切換頁首/頁尾開關不會清空其他既有覆寫欄位（回歸檢查）` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_show_header')))` 之前 |

範例（第一則的完整修改，其餘 7 則比照同一模式套用）：

```dart
  testWidgets('點擊上邊界 + 按鈕後，onChanged 帶入 marginTop+2 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(marginTop: 64, marginLeft: 24),
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '邊界首尾');

    await tester
        .tap(find.byKey(const Key('reader_settings_margin_top_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.marginTop, 66.0);
    expect(result!.marginLeft, 24.0, reason: '未被觸碰的欄位應維持原值');
  });
```

- [ ] **Step 2：「版面呈現」頁籤，13 則測試插入 `switchToTab(tester, '版面呈現')`**

| 測試描述（用於定位） | 插入位置 |
| --- | --- |
| `writingModeOverride 初始為 vertical 時，點擊「採用書籍排版」圖示後，onChanged 帶入 null` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_writing_mode_book')))` 之前 |
| `writingModeOverride 初始為 null 時，點擊「強制直排」圖示後，onChanged 帶入 WritingMode.vertical` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_writing_mode_vertical')))` 之前 |
| `點擊「滾動翻頁」圖示後，onChanged 帶入 PageTurnMode.scroll` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_page_turn_mode_scroll')))` 之前 |
| `點擊「鎖定 90°」圖示後，onChanged 帶入 ScreenOrientationSetting.lock90` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_screen_orientation_lock90')))` 之前 |
| `點擊排版方向覆寫圖示後，pageTurnModeOverride／screenOrientationOverride 維持原值不被清空` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_writing_mode_horizontal')))` 之前 |
| `已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟` | `_pumpSheet(...)` 之後、`expect(tester.widget<SwitchListTile>(find.byKey(const Key('reader_settings_fullscreen')))...)` 之前 |
| `開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true 且不影響 showHeader` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_fullscreen')))` 之前 |
| `點選「單欄」按鈕後，onChanged 帶入 columnMode=single` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_column_mode_single')))` 之前 |
| `切換欄數不會清空其他既有覆寫欄位（回歸檢查）` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_column_mode_single')))` 之前 |
| `columnMode 預設 auto 時，自動按鈕高亮、Slider 可見` | `_pumpSheet(...)` 之後、`expect(find.byKey(const Key('reader_settings_column_mode_auto')), findsOneWidget)` 之前 |
| `columnMode=single 時，Slider 不可見` | `_pumpSheet(...)` 之後、`expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing)` 之前 |
| `columnMode=double 時，Slider 不可見` | `_pumpSheet(...)` 之後、`expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing)` 之前 |
| `從單欄切換到自動，onChanged 帶入 columnMode=auto（可逆性）` | `_pumpSheet(...)` 之後、`tester.tap(find.byKey(const Key('reader_settings_column_mode_auto')))` 之前 |

- [ ] **Step 3：「設定喜好」頁籤，9 則測試插入 `switchToTab(tester, '設定喜好')`**

| 測試描述（用於定位） | 插入位置 |
| --- | --- |
| `空 slot 顯示「（空）」，已存的 slot 顯示名稱與更新日期` | `_pumpSheet(...)` 之後、`expect(find.byKey(const Key('reader_settings_preset_slot_0_label')), findsOneWidget)` 之前 |
| `點擊「另存為新預設集」呼叫 onSaveAsPreset 並帶入目前完整草稿` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_save_as_preset')))` 之前 |
| `點擊 slot 的「套用到本書」呼叫 onApplyPreset 且 targetBookIds=[bookId]` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')))` 之前 |
| `點擊 slot 的「套用到其他書籍」，onRequestBookPicker 回傳清單後呼叫 onApplyPreset 帶入該清單` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')))` 之前 |
| `onRequestBookPicker 回傳 null（使用者取消）時，不呼叫 onApplyPreset` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')))` 之前 |
| `點擊 slot 的「刪除」呼叫 onDeletePreset 帶入該 preset 的 id` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_preset_slot_0_delete')))` 之前 |
| `點擊「複製到本書」，onRequestBookPicker(multiSelect:false) 回傳後呼叫 onApplyFromBook(sourceId, targetBookIds:[bookId])` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_copy_from_book_current')))` 之前 |
| `點擊「複製到其他書籍」，依序呼叫兩次 onRequestBookPicker 後呼叫 onApplyFromBook` | `_pumpSheet(...)` 之後、`tester.ensureVisible(find.byKey(const Key('reader_settings_copy_from_book_others')))` 之前 |
| `Sheet 開啟中，layoutPresets 外部更新後畫面立即反映新清單（Bottom Sheet 開啟中同步）` | 第一個 `_pumpSheet(...)` 之後、`expect(find.byKey(const Key('reader_settings_preset_slot_0_empty')), findsOneWidget)` 之前——**第二個** `_pumpSheet(...)`（重新 pump 帶入 `layoutPresets: [preset]`）之後同樣需要插入一次，因為 `pumpWidget` 重新建構整棵樹會回到預設頁籤 |

- [ ] **Step 4：執行測試確認 Task 3 涵蓋的測試皆通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：Task 3 處理的 31 則測試全數 PASS；Task 4 尚未處理的測試（見下）仍會 FAIL，這是預期中的結果。

---

### Task 4：處理需結構性修改的既有測試（跨頁籤斷言拆分／高度行為反轉／捲動機制調整）

**Files:**
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `switchToTab()`；Task 2 新增的 4 個 Tab 內容 `ListView` Key（`reader_settings_tab_text_content_list` 等）。

- [ ] **Step 1：拆分「初始值正確反映傳入的 BookReaderPrefs」（第 14-109 行）**

找到整段測試本體，改為：

```dart
  testWidgets('初始值正確反映傳入的 BookReaderPrefs', (tester) async {
    const prefs = BookReaderPrefs(
      fontFamily: 'SourceHanSerifTC',
      fontSize: 1.375, // UI 22.0
      fontWeight: 1.75, // UI 700
      lineHeight: 1.8,
      paragraphSpacing: 2.0, // UI 20.0
      letterSpacing: 0.2,
      marginTop: 72,
      marginBottom: 20,
      marginLeft: 30,
      marginRight: 30,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false, // 停用書本 CSS 開關應為 true（反向語意）
    );

    await _pumpSheet(tester, prefs, (_) {});

    // 「文字內容」頁籤（預設）。
    expect(
      tester
          .widget<DropdownButton<String?>>(
              find.byKey(const Key('reader_settings_font_family')))
          .value,
      'SourceHanSerifTC',
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      22.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      700.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.8,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.2,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      true,
    );

    // 「邊界首尾」頁籤。
    await switchToTab(tester, '邊界首尾');
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      72.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      30.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      30.0,
    );
  });
```

- [ ] **Step 2：拆分「任一欄位為 null 時，滑桿顯示原型範例預設值」（第 111-184 行）**

改為：

```dart
  testWidgets('任一欄位為 null 時，滑桿顯示原型範例預設值', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    // 「文字內容」頁籤（預設）。
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      400.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.0,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      10.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.0,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      false,
    );

    // 「邊界首尾」頁籤。
    await switchToTab(tester, '邊界首尾');
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      32.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      24.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      24.0,
    );
  });
```

- [ ] **Step 3：修正「5 個受本 Issue 影響欄位皆為 null 時」（第 237-267 行），改為真正切到「邊界首尾」頁籤驗證邊界欄位不適用本機制**

原本邊界欄位的 `findsNothing` 斷言在分頁後會「因為頁籤根本沒被切換過而巧合通過」，不是真的驗證「邊界欄位不支援這個機制」。改為：

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

    // epic-28-reader-settings-enhancements Issue 5 審查：必須真的切到「邊界
    // 首尾」頁籤才能驗證邊界欄位「不支援本機制」是設計使然，而非單純因為
    // 該頁籤尚未被掛載而巧合通過。
    await switchToTab(tester, '邊界首尾');
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
```

- [ ] **Step 4：核對「當外部 prefs 更新時，應透過 didUpdateWidget 同步 UI state」（第 510-548 行）**

此測試只操作 `font_size_slider`（「文字內容」預設頁籤），不需要修改程式碼。執行 `cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "didUpdateWidget"` 確認仍為 PASS（若因新 Tab 版面在 `Size(800, 1200)` 視窗下觸發 `RenderFlex` 溢位，將該測試內的 `tester.view.physicalSize` 由 `Size(800, 1200)` 調整為 `Size(800, 2400)`，比照 `_pumpSheet` 既有慣例）。

- [ ] **Step 5：重寫「內容超出小螢幕視窗高度並捲動內容後，關閉按鈕位置維持不變」（第 865-890 行）**

`find.byType(ListView)` 在新版面下不再唯一（4 個頁籤各自一個 `ListView`），改為指定「文字內容」頁籤自己的 `ListView`：

```dart
  testWidgets('內容超出小螢幕視窗高度並捲動內容後，關閉按鈕位置維持不變（未被捲出畫面）',
      (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('reader_settings_close_button')), findsOneWidget);
    final beforeScroll = tester.getTopLeft(
      find.byKey(const Key('reader_settings_close_button')),
    );

    await tester.drag(
      find.byKey(const Key('reader_settings_tab_text_content_list')),
      const Offset(0, -300),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_settings_close_button')), findsOneWidget);
    final afterScroll = tester.getTopLeft(
      find.byKey(const Key('reader_settings_close_button')),
    );
    expect(afterScroll, beforeScroll,
        reason: '關閉列在最外層 Column 頂端、TabBarView 之外，捲動任一頁籤內部的 '
            'ListView 不應移動它的位置');
  });
```

- [ ] **Step 6：改寫「內容小於可用高度時，Bottom Sheet 保持緊湊包裹」（第 892-907 行）為斷言新行為（刻意的設計變更，非回歸）**

```dart
  testWidgets(
      '改用 Tab 化版面後，Bottom Sheet 一律撐到近全螢幕高度（不再依內容量縮小）'
      '（epic-28-reader-settings-enhancements Issue 5：刻意的設計變更，比照 '
      'TocBottomSheet 既有先例，讓 Expanded(TabBarView) 有界高度可用，取代舊版 '
      '「內容小於可用高度時緊湊包裹」的 shrink-wrap 行為）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    final sheetHeight = tester.getSize(find.byType(ReaderSettingsSheet)).height;
    expect(sheetHeight, greaterThan(2500),
        reason:
            '改用 DefaultTabController + Expanded(TabBarView) 後，Sheet 應撐滿 '
            'showModalBottomSheet(isScrollControlled: true) 提供的近全高上限，'
            '不再像舊版 ListView(shrinkWrap: true) 那樣依內容量縮小');
  });
```

- [ ] **Step 7：執行測試確認 Task 4 涵蓋的測試皆通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：目前為止 Task 1-4 涵蓋的測試全數 PASS，剩餘 FAIL 數量應僅為 Task 5 尚未新增的測試（若 Task 5 測試尚未寫入，此時應為 0 個 FAIL，因為 Task 5 是新增測試而非修正既有測試）。

---

### Task 5：「版面呈現」頁籤視覺密度調整

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:453-520`（`_buildColumnModeRow()`）、`:693-807`（`_buildWritingModeOverrideRow()`／`_buildPageTurnModeOverrideRow()`／`_buildScreenOrientationOverrideRow()`）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `switchToTab()`。
- Produces: 無新增介面，既有 4 個 `_buildXxxRow()` 方法內的 `IconButton` 新增 `visualDensity: VisualDensity.compact` 參數。

- [ ] **Step 1：寫失敗測試**

在 `reader_settings_sheet_test.dart` 新增：

```dart
  testWidgets(
      '「版面呈現」頁籤內圖示列的 IconButton 皆使用緊湊視覺密度以節省垂直空間'
      '（epic-28-reader-settings-enhancements Issue 5，視覺密度調整）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '版面呈現');

    expect(
      tester
          .widget<IconButton>(
              find.byKey(const Key('reader_settings_column_mode_auto')))
          .visualDensity,
      VisualDensity.compact,
    );
    expect(
      tester
          .widget<IconButton>(
              find.byKey(const Key('reader_settings_writing_mode_book')))
          .visualDensity,
      VisualDensity.compact,
    );
    expect(
      tester
          .widget<IconButton>(find
              .byKey(const Key('reader_settings_screen_orientation_auto')))
          .visualDensity,
      VisualDensity.compact,
    );
    expect(
      tester
          .widget<IconButton>(
              find.byKey(const Key('reader_settings_page_turn_mode_scroll')))
          .visualDensity,
      VisualDensity.compact,
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "緊湊視覺密度"`

預期：FAIL（`visualDensity` 目前為預設值 `null`/`VisualDensity.standard`，非 `VisualDensity.compact`）。

- [ ] **Step 3：`_buildColumnModeRow()` 的 3 個 `IconButton` 新增 `visualDensity`**

編輯 `app/lib/screens/reader_settings_sheet.dart`，`_buildColumnModeRow()` 內 3 個 `IconButton`（`reader_settings_column_mode_auto`／`_single`／`_double`）逐一在 `icon:` 參數後新增一行：

```dart
                visualDensity: VisualDensity.compact,
```

例如「自動」按鈕改為：

```dart
              IconButton(
                key: const Key('reader_settings_column_mode_auto'),
                icon: const Icon(Icons.auto_awesome),
                visualDensity: VisualDensity.compact,
                tooltip: '自動',
                color: _columnMode == ColumnMode.auto
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: () => setState(() {
                  _columnMode = ColumnMode.auto;
                  _notifyChanged();
                }),
              ),
```

「單欄」「雙欄」兩個 `IconButton` 比照同一模式各自新增 `visualDensity: VisualDensity.compact,`。

- [ ] **Step 4：`_buildWritingModeOverrideRow()`／`_buildPageTurnModeOverrideRow()`／`_buildScreenOrientationOverrideRow()` 的 `.map()` 閉包新增 `visualDensity`**

這 3 個方法各自只有一個 `options.map((option) => IconButton(...))` 閉包，逐一在其 `icon:` 參數後新增 `visualDensity: VisualDensity.compact,`。以 `_buildWritingModeOverrideRow()` 為例，改為：

```dart
            return IconButton(
              key: Key('reader_settings_writing_mode_$keySuffix'),
              icon: Icon(icon),
              visualDensity: VisualDensity.compact,
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _writingModeOverride = mode;
                _notifyChanged();
              }),
            );
```

`_buildPageTurnModeOverrideRow()`／`_buildScreenOrientationOverrideRow()` 比照同一模式，各自在其 `.map()` 閉包回傳的 `IconButton` 新增 `visualDensity: VisualDensity.compact,`（`_buildScreenOrientationOverrideRow()` 的 `icon:` 參數是條件表達式 `angle == 0.0 ? iconWidget : Transform.rotate(...)`，`visualDensity` 加在同一個 `IconButton` 建構子內、與 `icon:` 同層級即可，不受這個條件表達式影響）。

- [ ] **Step 5：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`

預期：全數 PASS。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-28): Issue 5——版面呈現頁籤圖示列改用緊湊視覺密度"
```

---

### Task 6：`reader_screen_test.dart` 既有測試補上 Tab 切換步驟＋全專案回歸測試

**Files:**
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 無（`reader_screen_test.dart` 是獨立測試檔，不 import `reader_settings_sheet_test.dart`，需複製一份 `switchToTab` helper）。

已用 `Grep` 逐一核對 `reader_screen_test.dart` 全文，確認以下 9 則既有測試透過 `ReaderScreen` 開啟 `ReaderSettingsSheet` 後直接互動非「文字內容」頁籤的元件，Task 2 落地後會找不到目標元件而 FAIL，須逐一補上切換步驟。

- [ ] **Step 1：複製 `switchToTab` helper 到 `reader_screen_test.dart`**

在檔案最下方任一既有頂層 helper 函式（例如既有的 `_pumpReaderScreen`／其他既有 helper，實際位置依當下檔案現況為準）附近新增：

```dart
/// 點擊 `TabBar` 上文字為 [tabLabel] 的頁籤並等待切換動畫完成
/// （epic-28-reader-settings-enhancements Issue 5，`ReaderSettingsSheet` 的
/// 4 個頁籤）。與 `reader_settings_sheet_test.dart` 內同名 helper 邏輯相同，
/// 因測試檔互不 import，各自維護一份。
Future<void> switchToTab(WidgetTester tester, String tabLabel) async {
  await tester.tap(find.widgetWithText(Tab, tabLabel));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2：測試「流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView」（約第 407-468 行）補上頁籤切換**

找到：

```dart
      await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('reader_settings_column_mode_single')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
      await tester.pumpAndSettle();
```

改為（`writing_mode`／`column_mode` 在「版面呈現」頁籤，`show_footer` 在「邊界首尾」頁籤，兩者跨頁籤，需切換兩次）：

```dart
      await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();

      await switchToTab(tester, '版面呈現');
      await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('reader_settings_column_mode_single')),
      );
      await tester.pumpAndSettle();

      await switchToTab(tester, '邊界首尾');
      await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
      await tester.pumpAndSettle();
```

- [ ] **Step 3：8 則「版面設定預設集（epic-28-reader-settings-enhancements Issue 3）」群組測試（約第 6623-6859 行）補上 `switchToTab(tester, '設定喜好')`**

這 8 則測試（`另存為新預設集：命名對話框輸入名稱後...`／`存滿 3 組後再次另存...`／`套用預設集到目前書籍...`／`套用預設集到其他書籍（多本）...`／`刪除預設集：正確從 LayoutPresetRepository 移除`／`刪除預設集：確認對話框取消時不刪除`／`複製其他書籍設定到本書...`，以及同群組其餘操作 `reader_settings_save_as_preset`／`reader_settings_preset_slot_0_*`／`reader_settings_copy_from_book_current` 的測試）皆遵循同一個模式：

```dart
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
```

在這兩行之後、下一行（`ensureVisible`／直接 `tap` 目標預設集控制項）之前，插入：

```dart
      await switchToTab(tester, '設定喜好');
```

8 則測試逐一比照套用，插入點皆為同一個「開啟設定 Sheet 之後、第一次操作預設集相關控制項之前」的位置。

- [ ] **Step 4：執行 `reader_screen_test.dart` 確認全數通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`

預期：全數 PASS，零回歸。

- [ ] **Step 5：執行完整測試檔與全專案測試**

執行：`cd app && flutter analyze && flutter test`

預期：`flutter analyze` "No issues found!"；全專案 `flutter test` 全數 PASS，零回歸。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-28): Issue 5——ReaderSettingsSheet 改為 4 個 Tab 頁籤，減少捲動需求"
```

---

## 完成後的驗證（對照 `issues.md` Issue 5 驗收標準）

- [ ] 使用者開啟版面設定可透過 4 個頁籤切換分類
- [ ] 「文字內容」「邊界首尾」在一般手機直向螢幕下不需捲動即可看到該頁籤全部控制項（「版面呈現」5 組控制項＋「設定喜好」預設集區塊內容量較大，允許捲動）
- [ ] 在任一頁籤內對 Slider 做橫向拖曳不會意外切換頁籤（Task 1 測試已涵蓋）
- [ ] 既有全部控制項的互動邏輯、持久化行為、測試 `Key` 不變，只是視覺分組位置改變
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸
