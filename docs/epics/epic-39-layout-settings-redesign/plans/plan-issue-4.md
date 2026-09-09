# Epic 39 — Issue 4：`ReaderSettingsSheet` 預設集分頁 —「目前套用中」標示 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `_buildPresetSlot()` 新增「目前套用中」視覺標示：當某個已存預設集的 `prefs` 與目前草稿 `_currentDraft` 完全相等時，該列反白（底色 `colorScheme.inverseSurface`）並以獨立的「已套用」指示器取代既有的「套用到本書」按鈕，「套用到其他書籍」／「刪除」兩顆按鈕維持顯示；反白列內所有文字/圖示前景色統一改為 `colorScheme.onInverseSurface`。

**Architecture:** 核心比對邏輯只有一行（`preset.prefs == _currentDraft`，`BookReaderPrefs` 既有值相等實作已可直接使用），主要工作量在 `_buildPresetSlot()` 依這個布林值切換渲染分支。**額外必要前置修復**：撰寫本計畫時實測發現 `app/lib/theme/app_theme_data.dart` 的 `_buildEinkTheme()` 目前**沒有**明確覆寫 `ColorScheme.light()` 的 `inverseSurface`／`onInverseSurface` 兩個角色，會落回 Flutter Material 3 的預設值（一個中性灰紫色配一個近白色，不是純黑白）——這與 E-Ink 模式「全角色純黑白、不留 M3 baseline」的既定設計語言矛盾（既有測試 `test/theme/app_theme_data_test.dart` 的「eink 主題 ColorScheme 全角色對齊 DESIGN.md §1.1」測試也證實只覆蓋了 11 個角色，未涵蓋這兩個）。由於本 Issue 是全專案第一個真正讀取 `inverseSurface`／`onInverseSurface` 的功能（`grep -rn "inverseSurface" lib/ test/` 目前查無任何既有使用），若不先修，E-Ink 模式下的反白列會是灰底近白字，不符合 spec.md「E-Ink 模式為純黑」的要求，也會讓 Task 2 的 E-Ink 測試無法通過。因此拆成兩個 Task：(1) 先修 `_buildEinkTheme()` 補上這兩個角色（獨立、與 `reader_settings_sheet.dart` 無關，可獨立驗證與 commit）；(2) 再實作 `_buildPresetSlot()` 的反白邏輯，此時 `colorScheme.inverseSurface`/`onInverseSurface` 在兩種主題下都已經是正確值，`_buildPresetSlot()` 本身完全不需要判斷 `widget.isEinkMode`，直接讀 `colorScheme` 即可（比 `_buildOverrideBadge()`/`_buildSliderRow()` 既有的 `isEinkMode` 分支寫法更單純）。

**Tech Stack:** Flutter/Dart，`flutter_test`，既有 `ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`）、`BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`，既有 `operator ==`／`hashCode` 值相等實作）、`app_theme_data.dart`（`app/lib/theme/app_theme_data.dart`）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`（§「既有元件異動」`ReaderSettingsSheet` 第 9 條、審查修正 I3）、`docs/epics/epic-39-layout-settings-redesign/issues.md`（Issue 4，含審查回應 I1）——本計畫實作前已讀過 `design.md`／`issues.md`／`spec.md`、三份 Epic 階段審查報告（`reviews/review-design.md`、`review-spec.md`、`review-issues.md`），並實際讀取目前（Issue 1-3 已合併後）的 `reader_settings_sheet.dart`／`reader_settings_sheet_test.dart`／`app_theme_data.dart`／`app_theme_data_test.dart`／`book_reader_prefs.dart`／`layout_preset.dart` 原始碼確認本計畫所有行號、程式碼片段與欄位預設值皆對應現況。

## Global Constraints

- 所有顏色一律讀 `Theme.of(context).colorScheme`（`CLAUDE.md`）——`_buildPresetSlot()` 不得寫死 `Colors.black`／`Colors.white` 判斷 `isEinkMode`（那是舊 `ReaderOptionTile` 的既有技術債寫法，見 Issue 1 審查報告，本 Issue 不重蹈覆轍）；正確做法是修好 `_buildEinkTheme()`，讓 `colorScheme.inverseSurface`/`onInverseSurface` 本身在 E-Ink 主題下就是純黑白，`_buildPresetSlot()` 全程不需要讀 `widget.isEinkMode`。
- **`BookReaderPrefs.empty`（全欄位皆為 `null`）與 `_currentDraft`（`ReaderSettingsSheet` 內部草稿 getter）在「未經任何互動的初始狀態」下並不相等**——這是撰寫本計畫時逐欄位比對後確認的事實，務必知悉，否則會寫出恆為 false 或恆為 true 的錯誤測試：`_currentDraft` 對 `marginTop`/`marginBottom`/`marginLeft`/`marginRight`/`publisherStyles`/`showHeader`/`showFooter`/`fullscreen`/`columnMode`/`columnSize` 這 10 個欄位一律具現化成 State 內部預設值（`32.0`/`16.0`/`24.0`/`24.0`/`true`/`false`/`false`/`false`/`ColumnMode.auto`/`720.0`），不會是 `null`；只有 `fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`letterSpacing`/`textAlign`/`writingModeOverride`/`pageTurnModeOverride`/`screenOrientationOverride` 這 10 個「有 `xxxOverridden` 旗標」的欄位在未覆寫時才是 `null`。因此要建構一個「與初始 `_currentDraft` 完全相等」的 `LayoutPreset.prefs` 測試固件，必須明確帶入上述 10 個具現化欄位的值（見 Task 2 的 `_activeDraftPrefs` 常數），不能偷懶用 `BookReaderPrefs.empty`；反過來，既有測試裡多處使用 `BookReaderPrefs.empty` 作為 `preset.prefs` 的既有寫法，因為前述原因本來就不會被誤判為「目前套用中」，Task 2 不需要修改任何既有測試。
- **`DESIGN.md` §1.1「全域 Material 3 ColorScheme 補齊規範」目前未列出 `inverseSurface`／`onInverseSurface` 兩個角色**（本 Issue 是第一個實際使用它們的功能）。本計畫刻意**不**在 Task 1 順便替 `DESIGN.md` 新增這兩個角色在四套主題下的完整定義列——那是「重新設計淺色/深色/宣紙三套主題的反轉色」這個更大範圍的文件決策，超出本 Issue「補上 E-Ink 模式純黑白」這個單純訴求；Task 1 只修正 E-Ink 一套主題的程式行為並在程式碼註解說明理由，`DESIGN.md` 表格是否要正式納入這兩個角色留給人類決定是否另立文件工單（比照 Issue 3 對 `_buildScreenOrientationOverrideRow()` `angle` 死碼的處理方式：發現、記錄、不在本 Issue 內擴大範圍修復）。
- 既有 `Key`／`itemKey` 契約全部維持不變；新增的「已套用」指示器使用 spec.md／issues.md 明訂的 `Key('reader_settings_preset_slot_${index}_active_indicator')`。
- TDD 嚴格執行：每個 Step 先寫失敗測試，確認 RED（含確認失敗原因正確），再寫最小實作使其 GREEN，不得反向操作。
- **測試執行範圍**（比照 `CLAUDE.md`「測試執行範圍」慣例）：Task 1 只跑 `flutter test test/theme/app_theme_data_test.dart`；Task 2 只跑 `flutter test test/screens/reader_settings_sheet_test.dart`；全套 `flutter test` 留到本計畫最後一個 Task 執行一次。
- 所有新程式碼註解、文件字串、測試描述文字一律使用正體中文（zh-TW），專業術語可保留英文。
- 所有 `flutter test`／`flutter analyze` 指令皆在 `app/` 目錄下執行。

---

### Task 1：修正 `_buildEinkTheme()` 補上 `inverseSurface`／`onInverseSurface` 純黑白覆寫

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart:236-248`（`_buildEinkTheme()` 內 `ColorScheme.light(...)` 呼叫）
- Test: `app/test/theme/app_theme_data_test.dart:191-207`（既有測試，擴充斷言）

**Interfaces:**
- Consumes：無新依賴，`ColorScheme.light()` 既有具名參數 `inverseSurface`／`onInverseSurface`。
- Produces：`buildEinkThemeData().colorScheme.inverseSurface == Colors.black`、`.onInverseSurface == Colors.white`，供 Task 2 的 `_buildPresetSlot()` 直接讀取。

- [ ] **Step 1：寫失敗測試——擴充既有 E-Ink ColorScheme 全角色測試**

修改 `app/test/theme/app_theme_data_test.dart` 第 191-207 行既有測試：

```dart
    test('eink 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（純黑白，不留'
        ' secondary／onSecondary，且 inverseSurface／onInverseSurface 亦不留'
        ' M3 baseline 預設值；後兩者為 epic-39-layout-settings-redesign Issue 4'
        ' 新增斷言——Issue 4 是全專案第一個實際讀取這兩個角色的功能，此前未被'
        ' 任何測試涵蓋）', () {
      final theme = buildEinkThemeData();
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF000000));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFFFFFFF));
      expect(scheme.onPrimaryContainer, const Color(0xFF000000));
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF000000));
      expect(scheme.onSurfaceVariant, const Color(0xFF000000));
      expect(scheme.outline, const Color(0xFF000000));
      expect(scheme.surfaceContainerHighest, const Color(0xFFFFFFFF));
      expect(scheme.error, const Color(0xFF000000));
      expect(scheme.inverseSurface, const Color(0xFF000000));
      expect(scheme.onInverseSurface, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    });
```

（只改了測試標題字串與新增兩行 `expect`，其餘既有斷言逐行不動。）

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/theme/app_theme_data_test.dart`
Expected: 新增的兩個斷言 FAIL——`scheme.inverseSurface`／`scheme.onInverseSurface` 現況分別回傳 Flutter Material 3 `ColorScheme.light()` 的預設值（一個中性灰紫色與一個近白色），不等於 `Color(0xFF000000)`／`Color(0xFFFFFFFF)`。其餘既有斷言與其餘 18 個測試維持 PASS。

- [ ] **Step 3：實作**

修改 `app/lib/theme/app_theme_data.dart` 第 236-248 行：

```dart
  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
    onError: Colors.white,
    // epic-39-layout-settings-redesign Issue 4：ReaderSettingsSheet 預設集
    // 「目前套用中」反白列是全專案第一個實際讀取這兩個角色的功能，
    // ColorScheme.light() 若不明確覆寫會落回 M3 預設的灰紫色/近白色，
    // 與 E-Ink「全角色純黑白」的既定設計語言矛盾。
    inverseSurface: primary,
    onInverseSurface: Colors.white,
  );
```

（`primary` 是本函式頂端已宣告的區域常數 `const primary = Color(0xFF000000);`，沿用既有命名慣例——`onPrimary`/`onError` 兩處既有程式碼也是直接寫 `Colors.white` 字面值而非另外宣告常數，`onInverseSurface` 比照辦理。）

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS（19 個測試全過）。

- [ ] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/theme/app_theme_data.dart test/theme/app_theme_data_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "fix(epic-39): Issue 4 Task 1 — E-Ink 主題補上 inverseSurface/onInverseSurface 純黑白覆寫"
```

---

### Task 2：`_buildPresetSlot()` 新增「目前套用中」反白標示與「已套用」指示器

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:998-1038`（`_buildPresetSlot()`）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1 修好的 `colorScheme.inverseSurface`／`onInverseSurface`；既有 `BookReaderPrefs.operator ==`（`book_reader_prefs.dart:222-254`，已涵蓋全部欄位值相等比較，無需新增）；`_currentDraft` getter（`reader_settings_sheet.dart:190-212`，既有）。
- Produces：`_buildPresetSlot()` 內新增區域變數 `isActive`（`bool`）與 `foregroundColor`（`Color?`），僅供本方法內部使用；新增外層 `Container`（`key: Key('reader_settings_preset_slot_${index}_row')`，非 spec.md/issues.md 明訂但為測試觀察背景色所需，供本 Issue 內部測試使用，不影響任何既有 Key）；新增「已套用」指示器 `Key('reader_settings_preset_slot_${index}_active_indicator')`（spec.md/issues.md 明訂）。

- [ ] **Step 1：寫失敗測試——涵蓋 4 項單元測試要求（共 3 則 testWidgets，第 1／2 項合併在同一測試內驗證 slot 0／slot 1）**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `void main()` 內追加（`_activeDraftPrefs` 這個 top-level `const` 建議加在檔案既有的 top-level helper 區塊，例如緊鄰 `_noopOnChanged` 等函式之前均可，只要在 `void main()` 之外、可被以下測試存取）：

```dart
const _activeDraftPrefs = BookReaderPrefs(
  marginTop: 32.0,
  marginBottom: 16.0,
  marginLeft: 24.0,
  marginRight: 24.0,
  publisherStyles: true,
  showHeader: false,
  showFooter: false,
  fullscreen: false,
  columnMode: ColumnMode.auto,
  columnSize: 720.0,
);
```

（這個常數精準對應 `ReaderSettingsSheet` 以 `BookReaderPrefs.empty` 為 `prefs` 初始化、且使用者尚未做任何互動時 `_currentDraft` 的實際值——見 Global Constraints 的逐欄位推導；用它當某個 `LayoutPreset.prefs` 即可製造「目前草稿與此預設集完全相等」的測試情境。）

在 `void main()` 內追加：

```dart
  testWidgets(
      '目前草稿與某預設集 prefs 完全相等時，該列反白（底色 colorScheme.inverseSurface、'
      '前景色 colorScheme.onInverseSurface）並顯示「已套用」指示器，「套用到本書」'
      '按鈕改為隱藏；其餘不相等的預設集列維持一般樣式（既有行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );
    final otherPreset = LayoutPreset(
      id: 2,
      name: '未套用預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [activePreset, otherPreset]);
    await switchToTab(tester, '預設集');

    final context = tester.element(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final activeContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    expect((activeContainer.decoration as BoxDecoration).color,
        colorScheme.inverseSurface);

    final activeLabel = tester.widget<Text>(
      find.byKey(const Key('reader_settings_preset_slot_0_label')),
    );
    expect(activeLabel.style?.color, colorScheme.onInverseSurface);

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
        findsNothing);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_delete')),
        findsOneWidget);

    // 審查修正 I1（review-plan-issue-4.md）：spec.md 明確要求反白列「所有」
    // 文字與圖示前景色皆為 colorScheme.onInverseSurface，不能只驗證標籤
    // 文字——若實作漏寫某顆 Icon 的 color 參數，只斷言文字顏色的測試不會
    // 抓到這個對比度缺陷，故逐一驗證 apply_others／delete／active_indicator
    // 內的 Check 圖示三者的前景色。
    final activeIndicatorIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
      matching: find.byType(Icon),
    ));
    expect(activeIndicatorIcon.color, colorScheme.onInverseSurface);

    final applyOthersIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      matching: find.byType(Icon),
    ));
    expect(applyOthersIcon.color, colorScheme.onInverseSurface);

    final deleteIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      matching: find.byType(Icon),
    ));
    expect(deleteIcon.color, colorScheme.onInverseSurface);

    // Slot 1（未套用，既有行為零回歸）
    final otherContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_1_row')),
    );
    expect((otherContainer.decoration as BoxDecoration?)?.color, isNull,
        reason: '未套用的列不應套用反白底色（審查修正 M1，review-plan-issue-4.md：'
            '改用可空安全轉型，即使日後改成 decoration: null 也不會讓測試拋出 '
            'TypeError 而是回報清楚的斷言失敗）');
    expect(
        find.byKey(const Key('reader_settings_preset_slot_1_active_indicator')),
        findsNothing);
    expect(find.byKey(const Key('reader_settings_preset_slot_1_apply_current')),
        findsOneWidget);
  });

  testWidgets(
      '使用者調整任一數值後，草稿不再與預設集相等，先前反白的列恢復一般樣式'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [activePreset]);
    await switchToTab(tester, '預設集');

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsOneWidget,
        reason: '互動前草稿與預設集相等，應顯示已套用');

    await switchToTab(tester, '文字');
    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    await switchToTab(tester, '預設集');

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsNothing,
        reason: '字級已調整，fontSize 不再是 null，草稿不再與預設集相等');
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
        findsOneWidget,
        reason: '恢復一般樣式後，套用到本書按鈕應重新出現');
  });

  testWidgets(
      'E-Ink 模式下反白列使用純黑底（colorScheme.inverseSurface）與純白前景'
      '（colorScheme.onInverseSurface），驗證不會出現深底深字對比度不足的組合'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: BookReaderPrefs.empty,
          isEinkMode: true,
          layoutPresets: [activePreset],
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));
    await switchToTab(tester, '預設集');

    final container = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    expect((container.decoration as BoxDecoration).color, Colors.black);

    final label = tester.widget<Text>(
      find.byKey(const Key('reader_settings_preset_slot_0_label')),
    );
    expect(label.style?.color, Colors.white);

    // 審查修正 I1（review-plan-issue-4.md）：E-Ink 模式同樣須驗證圖示前景色，
    // 不能只驗證文字，理由同上方一般主題測試。
    final einkActiveIndicatorIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
      matching: find.byType(Icon),
    ));
    expect(einkActiveIndicatorIcon.color, Colors.white);

    final einkApplyOthersIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      matching: find.byType(Icon),
    ));
    expect(einkApplyOthersIcon.color, Colors.white);

    final einkDeleteIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      matching: find.byType(Icon),
    ));
    expect(einkDeleteIcon.color, Colors.white);
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 新增的 3 個測試全數 FAIL——現況 `_buildPresetSlot()` 完全沒有 `reader_settings_preset_slot_${index}_row` 這個 Key（`find.byKey` 找不到目標，`tester.widget<Container>(...)` 會拋出例外）、沒有 `_active_indicator`、`_apply_current` 一律無條件顯示。其餘既有 72 個測試維持 PASS。

- [ ] **Step 3：實作**

修改 `app/lib/screens/reader_settings_sheet.dart` 第 998-1038 行 `_buildPresetSlot()`：

```dart
  Widget _buildPresetSlot(int index) {
    if (index >= widget.layoutPresets.length) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('（空）', key: Key('reader_settings_preset_slot_${index}_empty')),
      );
    }
    final preset = widget.layoutPresets[index];
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = preset.prefs == _currentDraft;
    final foregroundColor = isActive ? colorScheme.onInverseSurface : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        key: Key('reader_settings_preset_slot_${index}_row'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.inverseSurface : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${preset.name}（${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）',
                key: Key('reader_settings_preset_slot_${index}_label'),
                style: TextStyle(color: foregroundColor),
              ),
            ),
            if (isActive)
              Row(
                key: Key('reader_settings_preset_slot_${index}_active_indicator'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: foregroundColor, size: 18),
                  const SizedBox(width: 4),
                  Text('已套用', style: TextStyle(color: foregroundColor)),
                ],
              )
            else
              IconButton(
                key: Key('reader_settings_preset_slot_${index}_apply_current'),
                icon: const Icon(Icons.check),
                tooltip: '套用到本書',
                onPressed: () =>
                    widget.onApplyPreset(preset, targetBookIds: [widget.bookId]),
              ),
            IconButton(
              key: Key('reader_settings_preset_slot_${index}_apply_others'),
              icon: Icon(Icons.library_books, color: foregroundColor),
              tooltip: '套用到其他書籍',
              onPressed: () => _handleApplyPresetToOthers(preset),
            ),
            IconButton(
              key: Key('reader_settings_preset_slot_${index}_delete'),
              icon: Icon(Icons.delete, color: foregroundColor),
              tooltip: '刪除',
              onPressed: () => widget.onDeletePreset(preset.id!),
            ),
          ],
        ),
      ),
    );
  }
```

（`isActive == false` 時 `foregroundColor` 為 `null`，`TextStyle(color: null)`／`Icon(icon, color: null)` 與完全不傳 `color` 參數行為一致，既有非套用中列的視覺效果零回歸；`Container` 的 `width: double.infinity` 讓反白色塊填滿整列寬度而非只包住文字內容寬度——`_buildPreferencesTab()` 的父層是 `ListView`，提供有界寬度約束，`Container` 在 `Column` 內請求 `width: double.infinity` 是合法且常見的「填滿可用寬度」寫法，不會拋出 `RenderFlex`/無界寬度例外。）

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（75 個測試全過：既有 72 個＋本 Task 新增 3 個）。

- [ ] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 4 Task 2 — _buildPresetSlot 新增目前套用中反白標示"
```

---

### Task 3：收尾——全套測試與更新計畫狀態

**Files:**
- 無新增/修改程式碼檔案（僅驗證與文件收尾）。

- [ ] **Step 1：跑全套 `flutter test`**

Run: `flutter test`
Expected: 全數通過，零回歸（`reader_settings_sheet_test.dart` 75 個＋`app_theme_data_test.dart` 19 個＋其餘全專案測試皆維持 PASS）。

- [ ] **Step 2：跑全套 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3：將本檔案所有 Task 的 Step 勾選為完成**

把本檔案（`docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-4.md`）Task 1-3 全部 `- [ ]` 改為 `- [x]`。

- [ ] **Step 4：Commit 計畫狀態更新**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-4.md
git commit -m "docs(epic-39): Issue 4 計畫執行完成，全部 Step 標記完成"
```

Issue 4 完成後，交由人類決定是否發起程式碼審查（`superpowers:requesting-code-review`），審查通過後才可進入 Issue 5。
