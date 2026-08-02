# Epic 14 Issue 5 — 導航熱區模板圖示化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `NavZoneSettingsScreen` 現有的「左翻頁／右翻頁／單手／自訂」4 選一純文字 `RadioListTile` 改為「簡單／自訂」二選一 `SegmentedButton` ＋ 3 張圖示卡片（左翻頁／右翻頁／單手），讓使用者用視覺化的三欄示意圖理解每個模板實際的分區方式，而不是憑文字猜測（參考截圖 `tmp/images/導航熱區建議.jpg`）。

**Architecture:** 純 UI 層改版，不動底層資料模型——`NavZoneMode` 4 選一列舉、`resolveZoneActions()` 查表、`GlobalReaderPrefs.navZoneMode`/`navZoneCustomActions`、既有的 `_selectMode()`/`_saveCustomActions()`/`_cycleCell()`/`_load()`/`_toggleDebugOverlay()`/`_buildCustomEditor()` 皆完全不變。只重寫 `build()` 方法最上層的模板選擇區塊：新增 `SegmentedButton<bool>`（`false`=簡單／`true`=自訂，`selected` 為 `navZoneMode == NavZoneMode.custom` 的純衍生值，非獨立狀態）取代原本的 4 選一 `RadioGroup`；「簡單」狀態下新增 `_buildTemplateCard()` 產生的 3 張圖示卡片（左翻頁／右翻頁／單手），點選呼叫既有 `_selectMode()`；「自訂」狀態沿用既有 `_buildCustomEditor()` 完全不動。

**Tech Stack:** Flutter/Dart，純 widget test（`flutter test`），不需真機、不需 SQLite/SharedPreferences 結構變更。

## Global Constraints

- **底層資料模型完全不變**：`NavZoneMode` 4 選一列舉（`leftFlip`/`rightFlip`/`oneHand`/`custom`）、`resolveZoneActions()`、`leftFlipZoneTemplate`/`rightFlipZoneTemplate`/`oneHandZoneTemplate` 三個模板常數皆不修改（見 `app/lib/reader/nav_zone_mode.dart`）。本 Issue 純粹是 `nav_zone_settings_screen.dart` 的 UI 層改版。
- **`SegmentedButton<bool>` 的 `selected` 是純衍生值**：`{_prefs.navZoneMode == NavZoneMode.custom}`，不是獨立的 widget 內部狀態——與既有 `RadioGroup.groupValue` 直接讀 `_prefs.navZoneMode`的既有模式一致（沿用既有慣例，不新增額外的 UI-only 狀態欄位）。
- **「自訂」segment 點擊 → 直接呼叫 `_selectMode(NavZoneMode.custom)`**（僅在目前不是 custom 時才呼叫，避免重複觸發 `saveGlobalPrefs()`）；**「簡單」segment 點擊時，若目前是 custom → 呼叫 `_selectMode(NavZoneMode.rightFlip)`**（固定退回全域預設模板 `rightFlip`，不記憶「上次選過的簡單模板」——spec/design/issues.md 皆未要求記憶行為，避免新增未被要求的狀態，YAGNI）；若目前已經是簡單模板（leftFlip/rightFlip/oneHand）則不重複呼叫 `_selectMode()`。
- **3 張圖示卡片的圖示對應實際 `ZoneAction`，不是純裝飾**：卡片左/中/右欄的圖示反映該模板在該欄實際觸發的動作（`Icons.chevron_left`=`previousPage`／`Icons.chevron_right`=`nextPage`／`Icons.menu`=`menu`），讓使用者能從圖示看懂實際分區語意（spec.md User Story 10），不是單純固定的「←/≡/→」裝飾符號。`oneHand` 模板左右欄圖示皆用 `Icons.touch_app`（該模板左右欄對稱，皆依垂直位置在 menu/previousPage/nextPage 間循環，非本卡片格式能完整表達，見 Task 1 doc comment）、中欄不顯示圖示（`oneHandZoneTemplate` 中欄 3 格皆為 `ZoneAction.none`，如實反映）。
- **既有 Key 命名延續**：`nav_zone_mode_leftFlip`／`nav_zone_mode_rightFlip`／`nav_zone_mode_oneHand` 三個 Key 從舊的 `RadioListTile` 移到新的圖示卡片 `Container` 上（同一顆 Key 代表「選取該模板」的語意不變，既有測試 Step 2/3（不修改）能繼續運作）；`nav_zone_mode_custom` Key **移除**（不再是獨立可選項目，改由 `SegmentedButton` 的「自訂」segment 承接，測試改用 `find.text('自訂')` 定位）。
- **良好測試判準**（比照既有慣例）：驗證外部可觀察行為——`savedGlobalPrefsCalls` 攜帶的值、畫面上是否存在特定 `Key`/文字、`Container.decoration` 的邊框顏色是否反映選中狀態——不斷言內部實作細節。

---

### Task 1：`NavZoneSettingsScreen` 模板選擇區塊圖示化改版

**Files:**
- Modify：`app/lib/screens/nav_zone_settings_screen.dart`
- Test：`app/test/screens/nav_zone_settings_screen_test.dart`

**Interfaces:**
- Consumes：既有 `NavZoneMode`（`app/lib/reader/nav_zone_mode.dart`）、既有 `GlobalReaderPrefs`／`ReaderPrefsManager`（不變）
- Produces：`NavZoneSettingsScreen` 對外建構參數（`prefsManager`）不變，無新增公開介面；新增私有 `_buildTemplateCard()` 方法（`nav_zone_settings_screen.dart` 內部實作細節，不供外部消費）

- [ ] **Step 1：撰寫失敗測試——以下列內容取代整個測試檔案**

`app/test/screens/nav_zone_settings_screen_test.dart`（原檔案 206 行）整份取代為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/nav_zone_settings_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示「翻頁方式」二選一與 3 張模板卡片', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsNothing,
    );
    expect(find.byKey(const Key('nav_zone_template_toggle')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_oneHand')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_custom')), findsNothing);
  });

  testWidgets('SegmentedButton 選中狀態正確反映 navZoneMode：簡單模板對應「簡單」，隱藏 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.oneHand),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('nav_zone_template_toggle')),
    );
    expect(toggle.selected, {false});
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);
  });

  testWidgets('SegmentedButton 選中狀態正確反映 navZoneMode：custom 對應「自訂」，顯示 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.custom),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('nav_zone_template_toggle')),
    );
    expect(toggle.selected, {true});
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsNothing);
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
  });

  testWidgets('點擊「左翻頁」模板卡片觸發 GlobalReaderPrefs 更新為 leftFlip', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_leftFlip')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.leftFlip,
    );
  });

  testWidgets('點擊「單手」模板卡片觸發 GlobalReaderPrefs 更新為 oneHand', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_oneHand')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.oneHand,
    );
  });

  testWidgets('選中的模板卡片顯示 primary 色外框，未選中則為預設 dividerColor 外框', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.leftFlip),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;

    final leftFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_leftFlip')),
    );
    final leftFlipBorder =
        (leftFlipCard.decoration as BoxDecoration).border as Border;
    expect(leftFlipBorder.top.color, primaryColor);

    final rightFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_rightFlip')),
    );
    final rightFlipBorder =
        (rightFlipCard.decoration as BoxDecoration).border as Border;
    expect(rightFlipBorder.top.color, dividerColor);
  });

  testWidgets('點擊「自訂」segment，切換為 custom 模式並顯示 9 格編輯器', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.custom,
    );
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
  });

  testWidgets('在「自訂」模式下點擊「簡單」segment，切換回 rightFlip 模板並隱藏 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.custom),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('簡單'));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.rightFlip,
    );
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
  });

  testWidgets('模式切換（簡單→自訂→簡單→自訂）不影響既有 navZoneCustomActions 資料', (tester) async {
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        navZoneMode: NavZoneMode.custom,
        navZoneCustomActions: customActions,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('簡單'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_0')),
        matching: find.text('選單'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_3')),
        matching: find.text('上一頁'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_5')),
        matching: find.text('下一頁'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('切換「顯示熱區輔助線」開關觸發 GlobalReaderPrefs 更新', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_debug_overlay_switch')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('nav_zone_debug_overlay_switch')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.showNavZoneDebugOverlay,
      isTrue,
    );
  });

  testWidgets('選到「自訂」後顯示 9 格編輯器，逐格點擊循環切換 4 種動作', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
    // rightFlip 預設模板第 0 格為 previousPage。
    expect(find.text('上一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('下一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('選單'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('無動作'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('上一頁'), findsWidgets);
  });

  testWidgets('儲存自訂設定時，全部非 menu 會被擋下（錯誤提示存在、儲存回呼未被觸發）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();
    final savedCallCountAfterModeSwitch =
        fakeManager.savedGlobalPrefsCalls.length;

    // rightFlip 預設模板的 menu 格在 index 1/4/7，各點擊一次轉為 none。
    final cell1 = find.byKey(const Key('nav_zone_custom_cell_1'));
    await tester.ensureVisible(cell1);
    await tester.tap(cell1);
    await tester.pump();

    final cell4 = find.byKey(const Key('nav_zone_custom_cell_4'));
    await tester.ensureVisible(cell4);
    await tester.tap(cell4);
    await tester.pump();

    final cell7 = find.byKey(const Key('nav_zone_custom_cell_7'));
    await tester.ensureVisible(cell7);
    await tester.tap(cell7);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );

    final saveButton = find.byKey(const Key('nav_zone_save_custom_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsOneWidget,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.length,
      savedCallCountAfterModeSwitch,
    );
  });

  testWidgets('儲存自訂設定時，至少 1 格為 menu 則成功儲存並清除錯誤提示', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    // 修改第 0 格（原為 previousPage），其餘 menu 格（index 1/4/7）不動，
    // 陣列仍然合法。
    final cell0 = find.byKey(const Key('nav_zone_custom_cell_0'));
    await tester.ensureVisible(cell0);
    await tester.tap(cell0);
    await tester.pump();

    final saveButton = find.byKey(const Key('nav_zone_save_custom_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneCustomActions[0],
      ZoneAction.nextPage,
    );
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：FAIL——`Key('nav_zone_template_toggle')` 尚不存在、`Key('nav_zone_mode_custom')` 仍然存在（新測試斷言 `findsNothing` 會失敗）、`SegmentedButton<bool>` 型別在畫面上找不到、圖示卡片的 `Container` 找不到等多項編譯期／執行期失敗。

- [ ] **Step 3：修改 `nav_zone_settings_screen.dart`**

第 109-161 行（`build()` 方法全文）改為：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('導航熱區')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('nav_zone_settings_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text('翻頁方式'),
                      const Spacer(),
                      SegmentedButton<bool>(
                        key: const Key('nav_zone_template_toggle'),
                        segments: const [
                          ButtonSegment(value: false, label: Text('簡單')),
                          ButtonSegment(value: true, label: Text('自訂')),
                        ],
                        selected: {_prefs.navZoneMode == NavZoneMode.custom},
                        onSelectionChanged: (selection) {
                          final showCustom = selection.first;
                          if (showCustom) {
                            if (_prefs.navZoneMode != NavZoneMode.custom) {
                              _selectMode(NavZoneMode.custom);
                            }
                          } else {
                            if (_prefs.navZoneMode == NavZoneMode.custom) {
                              _selectMode(NavZoneMode.rightFlip);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (_prefs.navZoneMode != NavZoneMode.custom)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildTemplateCard(
                          key: const Key('nav_zone_mode_leftFlip'),
                          mode: NavZoneMode.leftFlip,
                          leftIcon: Icons.chevron_right,
                          middleIcon: Icons.menu,
                          rightIcon: Icons.chevron_left,
                        ),
                        _buildTemplateCard(
                          key: const Key('nav_zone_mode_rightFlip'),
                          mode: NavZoneMode.rightFlip,
                          leftIcon: Icons.chevron_left,
                          middleIcon: Icons.menu,
                          rightIcon: Icons.chevron_right,
                        ),
                        _buildTemplateCard(
                          key: const Key('nav_zone_mode_oneHand'),
                          mode: NavZoneMode.oneHand,
                          leftIcon: Icons.touch_app,
                          middleIcon: null,
                          rightIcon: Icons.touch_app,
                        ),
                      ],
                    ),
                  ),
                if (_prefs.navZoneMode == NavZoneMode.custom)
                  _buildCustomEditor(),
                const Divider(),
                SwitchListTile(
                  key: const Key('nav_zone_debug_overlay_switch'),
                  title: const Text('顯示熱區輔助線'),
                  value: _prefs.showNavZoneDebugOverlay,
                  onChanged: _toggleDebugOverlay,
                ),
              ],
            ),
    );
  }

  /// 模板圖示卡片（Issue 5，取代原本的文字 `RadioListTile`）：縮小版三欄
  /// 示意圖（左/中/右三色區塊＋圖示），點選呼叫既有 [_selectMode]；與目前
  /// [GlobalReaderPrefs.navZoneMode] 相同的卡片顯示 primary 色選中外框
  /// （design.md 決策 #7，參考 `tmp/images/導航熱區建議.jpg`）。三欄圖示
  /// 對應該模板實際指派的 [ZoneAction]（`leftFlip`/`rightFlip` 左右欄分別
  /// 對應 `nextPage`/`previousPage`，非固定裝飾符號）。[middleIcon] 為
  /// `null` 時中欄不顯示圖示——`oneHand` 模板中欄 3 格皆為 [ZoneAction.none]
  /// （見 `oneHandZoneTemplate`），左右欄則依垂直位置在 menu/previousPage/
  /// nextPage 間循環、彼此對稱，本卡片格式（單欄單圖示）無法完整表達列
  /// 逐格語意，故左右欄皆用通用的 [Icons.touch_app] 表示「可點擊區」。
  Widget _buildTemplateCard({
    required Key key,
    required NavZoneMode mode,
    required IconData leftIcon,
    IconData? middleIcon,
    required IconData rightIcon,
  }) {
    final selected = _prefs.navZoneMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectMode(mode),
      child: Container(
        key: key,
        width: 88,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: Colors.blue.shade100,
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.green.shade100,
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.red.shade100,
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
git add lib/screens/nav_zone_settings_screen.dart test/screens/nav_zone_settings_screen_test.dart
git commit -m "feat(epic-14): Issue 5 — NavZoneSettingsScreen 模板選擇區塊圖示化改版"
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（無 Regression——`nav_zone_settings_screen.dart` 是唯一被修改的生產程式碼檔案，且 `NavZoneMode`／`resolveZoneActions()`／`GlobalReaderPrefs` 皆未變更，其餘檔案不受影響）。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

**Spec 覆蓋檢查**（對照 `issues.md` Issue 5「驗收標準」5 項）：

1. `SegmentedButton` 正確反映並切換「簡單／自訂」狀態 → Step 1 的「SegmentedButton 選中狀態正確反映 navZoneMode」兩個測試（簡單／自訂各一）＋「點擊『自訂』segment」「在『自訂』模式下點擊『簡單』segment」兩個切換測試。
2. 「簡單」下 3 張圖示卡片正確呈現與選取，立即全域生效 → 「載入完成後顯示...3 張模板卡片」（呈現）＋「點擊『左翻頁』/『單手』模板卡片」（既有測試延用，選取生效）＋「選中的模板卡片顯示 primary 色外框」（選中外框）。
3. 「自訂」下 9 格編輯器行為與改版前完全一致（含防死鎖驗證） → 「選到『自訂』後顯示 9 格編輯器...」「儲存自訂設定時，全部非 menu 會被擋下」「儲存自訂設定時，至少 1 格為 menu 則成功儲存」三個測試逐字延用既有邏輯，只把觸發「自訂」的方式從 `tap(Key('nav_zone_mode_custom'))` 改為 `tap(find.text('自訂'))`，其餘斷言完全不變。
4. 模式切換不影響 `navZoneCustomActions` 既有資料 → 「模式切換（簡單→自訂→簡單→自訂）不影響既有 navZoneCustomActions 資料」，以非預設的 `customActions` 陣列驗證往返切換後 9 格內容未被重置為 `rightFlipZoneTemplate`。
5. 上述測試皆通過，`flutter analyze` 乾淨 → Step 5。

**Placeholder 掃描**：全文無 TBD/TODO/「類似 Task N」等字樣，測試檔案與生產程式碼皆為完整可執行內容（測試檔案為整份取代，非片段 diff）。

**型別一致性檢查**：`_buildTemplateCard({required Key key, required NavZoneMode mode, required IconData leftIcon, IconData? middleIcon, required IconData rightIcon})` 的呼叫端（`build()` 內 3 處呼叫）與定義完全對應；`SegmentedButton<bool>.selected`（`Set<bool>`）與 `onSelectionChanged`（`ValueChanged<Set<bool>>`）簽章為 Flutter Material 標準型別，測試中 `tester.widget<SegmentedButton<bool>>(...).selected` 讀取方式與生產程式碼宣告的泛型型別一致。

**既有測試相容性檢查**：本 Issue 只修改 `nav_zone_settings_screen.dart` 一個生產程式碼檔案，`NavZoneMode`／`resolveZoneActions()`／`GlobalReaderPrefs`／`ReaderPrefsManager` 介面完全不變，因此 `reader_prefs_manager_test.dart`／`global_reader_prefs_test.dart`／`reader_screen_test.dart` 等其餘測試檔案不受影響、不需修改。

**與既有「自訂」相關測試的相容性**：三個沿用既有邏輯的自訂編輯器測試（Step 1 檔案內「選到『自訂』後顯示 9 格編輯器」「儲存自訂設定時，全部非 menu 會被擋下」「儲存自訂設定時，至少 1 格為 menu 則成功儲存」）唯一改動是把切換至自訂模式的觸發方式從舊 Key 改為 `find.text('自訂')`，`_cycleCell()`／`_saveCustomActions()`／`isValidCustomZoneConfig()` 等既有邏輯與其餘斷言逐字保留不變。

**Epic 14 完成度**：本 Issue 完成並通過審查合併後，Epic 14（系統設定）5 個 Issue 將全數完成。
