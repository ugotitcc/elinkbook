# Epic 39 — Issue 1：新增共用元件 `EBStepper`／`EBOptionChipGroup` 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增兩個共用 widget——`EBStepper`（E-Ink 模式專用純步進器，補實作 `DESIGN.md` §18.3）與 `EBOptionChipGroup<T>`（取代三個版面設定 Bottom Sheet 共 13 處重複的「`Wrap` 包 `ReaderOptionTile`」寫法，統一負責依可用寬度縮放圖示/文字大小）——並擴充既有 `ReaderOptionTile` 支援這兩個新元件所需的參數。本 Issue 只新增元件本身，**不修改任何既有呼叫端**（`ReaderSettingsSheet`／`PdfSettingsSheet`／`FxlSettingsSheet` 改接留給 Issue 2-6）。

**Architecture:** `EBStepper` 是獨立的 `StatelessWidget`，純 `-`／數值／`+` 三段、無可拖曳元件，顏色一律讀 `Theme.of(context).colorScheme`（不自行判斷 E-Ink，呼叫端已經知道自己在 E-Ink 模式才會建構它）。`ReaderOptionTile` 新增 `iconSize`／`labelFontSize`／`forceUnselected` 三個可選參數（皆有預設值，向下相容既有 13 處呼叫點）。`EBOptionChipGroup<T>` 用 `LayoutBuilder` 依容器**絕對寬度**（非除以項目數，避免與 `Wrap` 折行特性衝突）連續映射出 `iconSize`／`labelFontSize`，內部渲染 `Wrap` of `ReaderOptionTile`；`EBOptionChipItem.onTap` 非 null 的「動作型」項目改用 `ReaderOptionTile.forceUnselected: true` 保證視覺恆為未選中，且點擊時只呼叫 `onTap`、不呼叫外層 `onSelected`。

**Tech Stack:** Flutter/Dart，`flutter_test`，既有 `ReaderOptionTile`（`app/lib/screens/widgets/reader_option_tile.dart`）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`（§「新增元件」1、2 節；§「卡片邊框視覺規範」；§「審查回應」I1/I2）——本計畫實作前已讀過 `design.md`／`issues.md` Issue 1 段落與三份審查報告（`reviews/review-design.md`、`review-spec.md`、`review-issues.md`）。

## Global Constraints

- 所有顏色一律讀 `Theme.of(context).colorScheme`，禁止在畫面/元件層寫死 Hex/`Colors.xxx`（`DESIGN.md` 第 14 行；本 Issue 兩個新元件皆不寫死顏色）。
- `EBStepper` 元件本身不判斷 `isEinkMode`——呼叫端（後續 Issue）已經知道自己在 E-Ink 模式才會建構它，元件內部無條件渲染純步進器。
- `ReaderOptionTile` 新增參數皆為可選、有預設值，**不得**破壞既有 13 處直接呼叫點與 `reader_option_tile_test.dart` 既有測試（零回歸）。
- 所有新程式碼註解、文件字串、測試描述文字一律使用正體中文（zh-TW），專業術語可保留英文。
- TDD 嚴格執行：每個 Step 先寫失敗測試、確認 RED（含確認失敗原因正確），再寫最小實作使其 GREEN，不得反向操作。
- 本 Issue 的 Task 之間只需要跑各自新建的測試檔（`flutter test test/screens/widgets/eb_stepper_test.dart` 等），不需要在每個 Task 都跑全套 `flutter test`；全套測試留到整份 `plan-issue-1.md` 最後一個 Task 完成時執行一次（比照 `CLAUDE.md`「測試執行範圍」既有慣例）。
- 所有 `flutter test`／`flutter analyze` 指令皆在 `app/` 目錄下執行。

---

### Task 1：`EBStepper` 元件

**Files:**
- Create: `app/lib/screens/widgets/eb_stepper.dart`
- Test: `app/test/screens/widgets/eb_stepper_test.dart`

**Interfaces:**
- Produces：
  ```dart
  class EBStepper extends StatelessWidget {
    const EBStepper({
      super.key,
      required this.keyPrefix,
      required this.value,
      required this.min,
      required this.max,
      required this.step,
      required this.displayValue,
      required this.onChanged,
    });

    final String keyPrefix;
    final double value;
    final double min;
    final double max;
    final double step;
    final String displayValue;
    final ValueChanged<double> onChanged;
  }
  ```
  衍生三個 `Key`：`Key('${keyPrefix}_decrement')`（減少按鈕）、`Key('${keyPrefix}_value')`（數值文字）、`Key('${keyPrefix}_increment')`（增加按鈕）。供 Issue 2/3/5 的 `_buildSliderRow`／`reader_settings_column_size_slider` 在 `isEinkMode: true` 時建構使用。

- [x] **Step 1：建立測試檔並寫下第一個失敗測試——顯示 `displayValue`**

建立 `app/test/screens/widgets/eb_stepper_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/eb_stepper.dart';

void main() {
  Widget buildStepper({
    double value = 16,
    double min = 12,
    double max = 80,
    double step = 1,
    String displayValue = '16',
    ValueChanged<double>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: EBStepper(
          keyPrefix: 'test_stepper',
          value: value,
          min: min,
          max: max,
          step: step,
          displayValue: displayValue,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('顯示 displayValue 文字', (tester) async {
    await tester.pumpWidget(buildStepper(displayValue: '42'));

    expect(find.text('42'), findsOneWidget);
    expect(find.byKey(const Key('test_stepper_value')), findsOneWidget);
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: 編譯失敗（`Target of URI doesn't exist: 'package:elinkbook/screens/widgets/eb_stepper.dart'`）——`eb_stepper.dart` 尚未建立，這是本階段預期的失敗原因。

- [x] **Step 3：寫最小實作使測試通過（僅滿足 Step 1，不預先實作點擊/邊界邏輯）**

建立 `app/lib/screens/widgets/eb_stepper.dart`：

```dart
import 'package:flutter/material.dart';

/// E-Ink 模式專用的純步進器（epic-39-layout-settings-redesign Issue 1，
/// spec.md §1）：補實作 `DESIGN.md` §18.3「步進控制」——E-Ink 模式下禁用
/// 所有 Slider 元件，字級/字重/行邊距等控制項一律自動替換為本元件。
///
/// 純展示、無 I/O，顏色一律讀 `Theme.of(context).colorScheme`——E-Ink
/// 主題本身的 `ColorScheme` 已是純黑白（見 `app_theme_data.dart`
/// `_buildEinkTheme()`），元件不自行判斷 `isEinkMode`，呼叫端已經知道
/// 自己在 E-Ink 模式才會建構這個 widget。
///
/// [mainAxisSize]／[mainAxisAlignment] 開放呼叫端覆寫（審查修正 I1，
/// review-plan-issue-1.md）：預設 `MainAxisSize.min` 讓本 widget 在任何
/// 父層（`Column`、`Row` 的非 flex 子項等）中都能安全地依內容自身寬度
/// 渲染，不會因為預設 `MainAxisSize.max` 在無邊界寬度約束下拋出
/// `RenderFlex` 例外；若呼叫端要讓 `-`/`+` 分居兩端撐滿整列寬度（比照
/// 既有 `_buildSliderRow` 用 `Expanded(child: Slider(...))` 撐滿的版面），
/// 可自行傳入 `mainAxisSize: MainAxisSize.max, mainAxisAlignment:
/// MainAxisAlignment.spaceBetween`。
class EBStepper extends StatelessWidget {
  final String keyPrefix;
  final double value;
  final double min;
  final double max;
  final double step;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;

  const EBStepper({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.displayValue,
    required this.onChanged,
    this.mainAxisSize = MainAxisSize.min,
    this.mainAxisAlignment = MainAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        IconButton(
          key: Key('${keyPrefix}_decrement'),
          icon: const Icon(Icons.remove),
          onPressed: null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(displayValue, key: Key('${keyPrefix}_value')),
        ),
        IconButton(
          key: Key('${keyPrefix}_increment'),
          icon: const Icon(Icons.add),
          onPressed: null,
        ),
      ],
    );
  }
}
```

（`onPressed: null` 是刻意的中間狀態——只滿足 Step 1「顯示 displayValue」這一個測試，Step 5／Step 9 才會逐步補上點擊與邊界邏輯，避免審查修正 I2 指出的「一次寫完導致後續測試從未經歷 RED」問題。）

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: PASS（1 個測試）

- [x] **Step 5：新增測試——點擊 `+`/`-` 觸發 `onChanged` 並帶正確值**

在 `eb_stepper_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets('點擊 + 觸發 onChanged 並帶入 value + step', (tester) async {
    double? received;
    await tester.pumpWidget(
      buildStepper(value: 16, step: 1, onChanged: (v) => received = v),
    );

    await tester.tap(find.byKey(const Key('test_stepper_increment')));

    expect(received, 17);
  });

  testWidgets('點擊 - 觸發 onChanged 並帶入 value - step', (tester) async {
    double? received;
    await tester.pumpWidget(
      buildStepper(value: 16, step: 1, onChanged: (v) => received = v),
    );

    await tester.tap(find.byKey(const Key('test_stepper_decrement')));

    expect(received, 15);
  });
```

- [x] **Step 6：執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: 新增的兩個測試 FAIL（`received` 維持 `null`，因為 Step 3 的兩顆按鈕 `onPressed` 皆寫死 `null`，點擊不會有任何反應）；第一個測試（顯示文字）維持 PASS。

- [x] **Step 7：實作點擊 callback（尚不含邊界 clamp）**

修改 `eb_stepper.dart` 的 `build()`：

```dart
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        IconButton(
          key: Key('${keyPrefix}_decrement'),
          icon: const Icon(Icons.remove),
          onPressed: () => onChanged(value - step),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(displayValue, key: Key('${keyPrefix}_value')),
        ),
        IconButton(
          key: Key('${keyPrefix}_increment'),
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(value + step),
        ),
      ],
    );
  }
```

- [x] **Step 8：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: PASS（3 個測試全過）。

- [x] **Step 9：新增測試——邊界值 clamp 與按鈕停用**

追加：

```dart
  testWidgets('value - step < min 時，減少按鈕停用', (tester) async {
    await tester.pumpWidget(buildStepper(value: 12, min: 12, step: 1));

    final button = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_decrement')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('value + step > max 時，增加按鈕停用', (tester) async {
    await tester.pumpWidget(buildStepper(value: 80, max: 80, step: 1));

    final button = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_increment')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('未觸及邊界時，減少/增加按鈕皆為可點擊狀態', (tester) async {
    await tester.pumpWidget(buildStepper(value: 16, min: 12, max: 80, step: 1));

    final decrement = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_decrement')),
    );
    final increment = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_increment')),
    );
    expect(decrement.onPressed, isNotNull);
    expect(increment.onPressed, isNotNull);
  });

  testWidgets('widget tree 內不存在任何 Slider', (tester) async {
    await tester.pumpWidget(buildStepper());

    expect(find.byType(Slider), findsNothing);
  });
```

- [x] **Step 10：執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: 前兩個新測試 FAIL（Step 7 的實作沒有邊界判斷，`onPressed` 恆非 `null`）；後兩個新測試 PASS（未觸及邊界的可點擊狀態、無 `Slider` 這兩項 Step 7 的實作已經滿足）。

- [x] **Step 11：實作邊界 clamp 與按鈕停用（最終完整邏輯）**

修改 `eb_stepper.dart` 的 `build()`：

```dart
  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max);
    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        IconButton(
          key: Key('${keyPrefix}_decrement'),
          icon: const Icon(Icons.remove),
          onPressed: clampedValue - step < min - 1e-9
              ? null
              : () => onChanged((clampedValue - step).clamp(min, max)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(displayValue, key: Key('${keyPrefix}_value')),
        ),
        IconButton(
          key: Key('${keyPrefix}_increment'),
          icon: const Icon(Icons.add),
          onPressed: clampedValue + step > max + 1e-9
              ? null
              : () => onChanged((clampedValue + step).clamp(min, max)),
        ),
      ],
    );
  }
```

- [x] **Step 12：執行測試確認全部通過**

Run: `flutter test test/screens/widgets/eb_stepper_test.dart`
Expected: PASS（7 個測試全過）。

- [x] **Step 13：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/widgets/eb_stepper.dart test/screens/widgets/eb_stepper_test.dart`
Expected: `No issues found!`

- [x] **Step 14：Commit**

```bash
git add app/lib/screens/widgets/eb_stepper.dart app/test/screens/widgets/eb_stepper_test.dart
git commit -m "feat(epic-39): Issue 1 Task 1 — 新增 EBStepper 純步進器元件"
```

---

### Task 2：擴充 `ReaderOptionTile`（`iconSize`／`labelFontSize`／`forceUnselected`）

**Files:**
- Modify: `app/lib/screens/widgets/reader_option_tile.dart:4-104`（全檔，見下方逐段修改）
- Test: `app/test/screens/widgets/reader_option_tile_test.dart`（既有檔案，新增測試案例，不修改既有測試）

**Interfaces:**
- Produces：`ReaderOptionTile<T>` 新增三個可選建構參數：
  - `double iconSize = 20`（既有預設值原樣保留）
  - `double labelFontSize = 13`（既有預設值原樣保留）
  - `bool forceUnselected = false`——為 `true` 時，不論 `value == groupValue` 為何，視覺恆為未選中樣式。供 Task 3 的 `EBOptionChipGroup` 承載「動作型」項目使用。
- Consumes：無（本 Task 不依賴 Task 1）。

- [x] **Step 1：寫失敗測試——`iconSize` 覆寫圖示大小**

在 `app/test/screens/widgets/reader_option_tile_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets('iconSize 覆寫圖示大小，未提供時維持既有預設值 20', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReaderOptionTile<String>(
              itemKey: const Key('tile_default'),
              value: 'A',
              groupValue: 'A',
              icon: Icons.crop_portrait,
              tooltip: '預設大小',
              onSelected: (_) {},
            ),
            ReaderOptionTile<String>(
              itemKey: const Key('tile_custom'),
              value: 'B',
              groupValue: 'A',
              icon: Icons.crop_landscape,
              tooltip: '自訂大小',
              iconSize: 16,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    final defaultIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('tile_default')),
        matching: find.byType(Icon),
      ),
    );
    final customIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('tile_custom')),
        matching: find.byType(Icon),
      ),
    );
    expect(defaultIcon.size, 20);
    expect(customIcon.size, 16);
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: FAIL（`No named parameter with the name 'iconSize'`，編譯期錯誤）。

- [x] **Step 3：修改 `ReaderOptionTile` 新增 `iconSize` 參數**

修改 `app/lib/screens/widgets/reader_option_tile.dart`：

```dart
// 第 4-24 行，class 宣告與建構子：
class ReaderOptionTile<T> extends StatelessWidget {
  final Key? itemKey;
  final T value;
  final T groupValue;
  final IconData icon;
  final String? label;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;
  final double iconSize;

  const ReaderOptionTile({
    super.key,
    this.itemKey,
    required this.value,
    required this.groupValue,
    required this.icon,
    this.label,
    required this.tooltip,
    required this.onSelected,
    this.visualDensity = VisualDensity.standard,
    this.iconSize = 20,
  });
```

```dart
// 第 59 行，Icon 建構：
        Icon(icon, size: iconSize, color: foregroundColor),
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: PASS（2 個測試，含既有的 E-Ink 高對比測試零回歸）。

- [x] **Step 5：寫失敗測試——`labelFontSize` 覆寫文字大小**

追加：

```dart
  testWidgets('labelFontSize 覆寫標籤文字大小，未提供時維持既有預設值 13', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReaderOptionTile<String>(
              itemKey: const Key('tile_default_label'),
              value: 'A',
              groupValue: 'A',
              icon: Icons.crop_portrait,
              label: '預設',
              tooltip: '預設大小',
              onSelected: (_) {},
            ),
            ReaderOptionTile<String>(
              itemKey: const Key('tile_custom_label'),
              value: 'B',
              groupValue: 'A',
              icon: Icons.crop_landscape,
              label: '自訂',
              tooltip: '自訂大小',
              labelFontSize: 11,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    final defaultText = tester.widget<Text>(find.text('預設'));
    final customText = tester.widget<Text>(find.text('自訂'));
    expect(defaultText.style?.fontSize, 13);
    expect(customText.style?.fontSize, 11);
  });
```

- [x] **Step 6：執行測試確認失敗**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: FAIL（`No named parameter with the name 'labelFontSize'`）。

- [x] **Step 7：修改 `ReaderOptionTile` 新增 `labelFontSize` 參數**

```dart
// class 欄位新增（緊接 iconSize 之後）：
  final double labelFontSize;

// 建構子新增（緊接 iconSize 之後）：
    this.labelFontSize = 13,
```

```dart
// 原本第 62-69 行的 Text：
          Text(
            label!,
            style: TextStyle(
              fontSize: labelFontSize,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: foregroundColor,
            ),
          ),
```

- [x] **Step 8：執行測試確認通過**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: PASS（3 個測試）。

- [x] **Step 9：寫失敗測試——`forceUnselected` 恆為未選中樣式**

追加：

```dart
  testWidgets('forceUnselected: true 時，即使 value == groupValue 仍呈現未選中樣式',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderOptionTile<String>(
          itemKey: const Key('tile_forced'),
          value: 'A',
          groupValue: 'A', // 故意讓 value == groupValue
          icon: Icons.crop,
          tooltip: '動作型項目',
          forceUnselected: true,
          onSelected: (_) {},
        ),
      ),
    ));

    final tile = tester.widget<Container>(find.byKey(const Key('tile_forced')));
    final decoration = tile.decoration as BoxDecoration;
    // E-Ink 主題下未選中樣式底色為白色（見既有 build() 邏輯），
    // 若 forceUnselected 沒有生效，value==groupValue 會被判定為選中、
    // 底色變黑。
    expect(decoration.color, Colors.white);
  });
```

- [x] **Step 10：執行測試確認失敗**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: FAIL（`No named parameter with the name 'forceUnselected'`）。

- [x] **Step 11：修改 `ReaderOptionTile` 新增 `forceUnselected` 參數**

```dart
// class 欄位新增（緊接 labelFontSize 之後）：
  final bool forceUnselected;

// 建構子新增（緊接 labelFontSize 之後）：
    this.forceUnselected = false,
```

```dart
// build() 第一行，原本：
    final selected = value == groupValue;
// 改為：
    final selected = !forceUnselected && value == groupValue;
```

- [x] **Step 12：執行測試確認通過**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart`
Expected: PASS（4 個測試全過，含既有 1 個測試零回歸）。

- [x] **Step 13：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/widgets/reader_option_tile.dart test/screens/widgets/reader_option_tile_test.dart`
Expected: `No issues found!`

- [x] **Step 14：Commit**

```bash
git add app/lib/screens/widgets/reader_option_tile.dart app/test/screens/widgets/reader_option_tile_test.dart
git commit -m "feat(epic-39): Issue 1 Task 2 — ReaderOptionTile 新增 iconSize/labelFontSize/forceUnselected"
```

---

### Task 3：`EBOptionChipGroup<T>` 元件

**Files:**
- Create: `app/lib/screens/widgets/eb_option_chip_group.dart`
- Test: `app/test/screens/widgets/eb_option_chip_group_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `ReaderOptionTile<T>`（`iconSize`／`labelFontSize`／`forceUnselected` 參數）。
- Produces：
  ```dart
  class EBOptionChipItem<T> {
    const EBOptionChipItem({
      this.itemKey,
      required this.value,
      required this.icon,
      required this.label,
      required this.tooltip,
      this.onTap,
    });

    final Key? itemKey;
    final T value;
    final IconData icon;
    final String label;
    final String tooltip;
    final VoidCallback? onTap;
  }

  class EBOptionChipGroup<T> extends StatelessWidget {
    const EBOptionChipGroup({
      super.key,
      required this.items,
      required this.groupValue,
      required this.onSelected,
      this.visualDensity = VisualDensity.standard,
    });

    final List<EBOptionChipItem<T>> items;
    final T groupValue;
    final ValueChanged<T> onSelected;
    final VisualDensity visualDensity;
  }
  ```
  供 Issue 3（`ReaderSettingsSheet` 5 組單選群組）、Issue 5（`PdfSettingsSheet` 5 組單選群組，含手動選區）、Issue 6（`FxlSettingsSheet` 2 組單選群組）改接使用。

- [x] **Step 1：寫失敗測試——寬度充足時圖示/文字為上限尺寸且點擊觸發 `onSelected`**

建立 `app/test/screens/widgets/eb_option_chip_group_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/eb_option_chip_group.dart';

void main() {
  List<EBOptionChipItem<String>> buildItems({VoidCallback? onManualTap}) {
    return [
      EBOptionChipItem<String>(
        itemKey: const Key('chip_a'),
        value: 'A',
        icon: Icons.crop_portrait,
        label: '甲',
        tooltip: '選項甲',
      ),
      EBOptionChipItem<String>(
        itemKey: const Key('chip_b'),
        value: 'B',
        icon: Icons.crop_landscape,
        label: '乙',
        tooltip: '選項乙',
      ),
      EBOptionChipItem<String>(
        itemKey: const Key('chip_c'),
        value: 'C',
        icon: Icons.crop_square,
        label: '丙',
        tooltip: '選項丙',
      ),
      if (onManualTap != null)
        EBOptionChipItem<String>(
          itemKey: const Key('chip_action'),
          value: 'C', // 故意跟丙相同值，驗證 onTap 項目不受 groupValue 比對影響
          icon: Icons.touch_app,
          label: '動作',
          tooltip: '動作項目',
          onTap: onManualTap,
        ),
    ];
  }

  Widget buildGroup({
    required double width,
    String groupValue = 'A',
    ValueChanged<String>? onSelected,
    VoidCallback? onManualTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: EBOptionChipGroup<String>(
            items: buildItems(onManualTap: onManualTap),
            groupValue: groupValue,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('寬度充足（>=360）時，圖示為 20sp、文字為 13sp', (tester) async {
    await tester.pumpWidget(buildGroup(width: 400));

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    final label = tester.widget<Text>(find.text('甲'));
    expect(icon.size, 20);
    expect(label.style?.fontSize, 13);
  });

  testWidgets('點擊 chip 觸發 onSelected 並帶入該 chip 的 value', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildGroup(width: 400, onSelected: (v) => selected = v),
    );

    await tester.tap(find.byKey(const Key('chip_b')));

    expect(selected, 'B');
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_option_chip_group_test.dart`
Expected: 編譯失敗（`eb_option_chip_group.dart` 不存在）。

- [x] **Step 3：寫最小實作使測試通過**

建立 `app/lib/screens/widgets/eb_option_chip_group.dart`：

```dart
import 'package:flutter/material.dart';

import 'reader_option_tile.dart';

/// 單選晶片群組的其中一個選項（epic-39-layout-settings-redesign Issue 1，
/// spec.md §2）。[onTap] 非 null 時代表這是「動作型」項目（例如 PDF 裁切
/// 分頁的「手動選區」：點擊只觸發外部動作、不代表選中一個可選值）——
/// 點擊時只呼叫 [onTap]，不呼叫 [EBOptionChipGroup.onSelected]，且該
/// chip 恆為未選中樣式（透過 [ReaderOptionTile.forceUnselected]，不參與
/// groupValue 比對）。
class EBOptionChipItem<T> {
  final Key? itemKey;
  final T value;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  const EBOptionChipItem({
    this.itemKey,
    required this.value,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
  });
}

/// 取代分散在三個版面設定 Bottom Sheet 共 13 處「`Wrap` 包一組
/// `ReaderOptionTile`」的重複寫法（spec.md §2）：依可用寬度連續縮放圖示/
/// 文字大小，寬度極窄時只顯示圖示。**寬度縮放依容器絕對寬度**（不除以
/// `items.length`）——除以項目數會與 `Wrap` 本身的折行特性衝突：6 選項
/// 群組在常規手機寬度下會被誤判為「永遠過窄」，但 `Wrap` 實際上會自動
/// 折成兩行，每行 3 顆的可用寬度其實綽綽有餘（見 spec.md 審查回應 I2）。
class EBOptionChipGroup<T> extends StatelessWidget {
  static const double _maxWidthForMinSize = 240;
  static const double _minWidthForMaxSize = 360;
  static const double _hideLabelWidth = 200;
  static const double _minIconSize = 16;
  static const double _maxIconSize = 20;
  static const double _minLabelFontSize = 11;
  static const double _maxLabelFontSize = 13;

  final List<EBOptionChipItem<T>> items;
  final T groupValue;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;

  const EBOptionChipGroup({
    super.key,
    required this.items,
    required this.groupValue,
    required this.onSelected,
    this.visualDensity = VisualDensity.standard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final clampedWidth =
            maxWidth.clamp(_maxWidthForMinSize, _minWidthForMaxSize);
        final t = (clampedWidth - _maxWidthForMinSize) /
            (_minWidthForMaxSize - _maxWidthForMinSize);
        final iconSize = _minIconSize + (_maxIconSize - _minIconSize) * t;
        final labelFontSize =
            _minLabelFontSize + (_maxLabelFontSize - _minLabelFontSize) * t;
        final showLabel = maxWidth >= _hideLabelWidth;

        return Wrap(
          spacing: 4,
          // 審查修正 M1（review-plan-issue-1.md）：Wrap 的 runSpacing 預設
          // 為 0，6 選項群組折成兩行時，第二行晶片會與第一行緊貼、垂直
          // 無間距，補上與 spacing 一致的 4，讓水平/垂直留白一致。
          runSpacing: 4,
          children: items.map((item) {
            final isAction = item.onTap != null;
            return ReaderOptionTile<T>(
              itemKey: item.itemKey,
              value: item.value,
              groupValue: groupValue,
              icon: item.icon,
              label: showLabel ? item.label : null,
              tooltip: item.tooltip,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              visualDensity: visualDensity,
              forceUnselected: isAction,
              onSelected: (v) {
                if (isAction) {
                  item.onTap!();
                } else {
                  onSelected(v);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_option_chip_group_test.dart`
Expected: PASS（2 個測試）。

- [x] **Step 5：寫失敗測試——寬度下限、中間內插、隱藏標籤門檻**

追加：

```dart
  testWidgets('寬度極小（<=240）時，圖示為 16sp、文字為 11sp', (tester) async {
    await tester.pumpWidget(buildGroup(width: 240));

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    final label = tester.widget<Text>(find.text('甲'));
    expect(icon.size, 16);
    expect(label.style?.fontSize, 11);
  });

  testWidgets('寬度介於門檻之間時，尺寸線性介於上下限之間', (tester) async {
    await tester.pumpWidget(buildGroup(width: 300)); // (300-240)/(360-240) = 0.5

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.size, greaterThan(16));
    expect(icon.size, lessThan(20));
  });

  testWidgets('寬度低於 200 時，不顯示 label 文字，只留圖示', (tester) async {
    await tester.pumpWidget(buildGroup(width: 150));

    expect(find.text('甲'), findsNothing);
    expect(find.text('乙'), findsNothing);
    expect(find.text('丙'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
  });

  testWidgets('6 個項目的群組在常規手機寬度（約 328dp）下不會因為除以項目數而隱藏 label'
      '（回歸保護：審查發現原「maxWidth / items.length」公式在此寬度會誤判過窄）',
      (tester) async {
    final sixItems = List.generate(
      6,
      (i) => EBOptionChipItem<int>(
        itemKey: Key('six_$i'),
        value: i,
        icon: Icons.circle,
        label: '選$i',
        tooltip: '選項 $i',
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 328,
          child: EBOptionChipGroup<int>(
            items: sixItems,
            groupValue: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    ));

    for (var i = 0; i < 6; i++) {
      expect(find.text('選$i'), findsOneWidget);
    }
  });
```

- [x] **Step 6：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_option_chip_group_test.dart`
Expected: PASS（6 個測試全過）——Step 3 的實作已涵蓋這些情境。

- [x] **Step 7：寫失敗測試——`onTap` 動作型項目**

追加：

```dart
  testWidgets('item.onTap 非 null 時，點擊觸發 onTap 而非 onSelected', (tester) async {
    var manualTapped = false;
    String? selected;
    await tester.pumpWidget(buildGroup(
      width: 400,
      groupValue: 'C', // 與 chip_action 的 value 相同
      onSelected: (v) => selected = v,
      onManualTap: () => manualTapped = true,
    ));

    await tester.tap(find.byKey(const Key('chip_action')));

    expect(manualTapped, isTrue);
    expect(selected, isNull);
  });

  testWidgets('item.onTap 非 null 時，該 chip 恆為未選中樣式（即使 value == groupValue）',
      (tester) async {
    await tester.pumpWidget(buildGroup(
      width: 400,
      groupValue: 'C', // 與 chip_action 的 value 相同、也與 chip_c 相同
      onManualTap: () {},
    ));

    final actionTile =
        tester.widget<Container>(find.byKey(const Key('chip_action')));
    final normalTile = tester.widget<Container>(find.byKey(const Key('chip_c')));
    final actionDecoration = actionTile.decoration as BoxDecoration;
    final normalDecoration = normalTile.decoration as BoxDecoration;
    // chip_c 的 value 與 groupValue 相同，應呈現選中樣式；chip_action 的
    // value 雖然也相同，但 onTap 非 null 應強制未選中，兩者底色應不同。
    expect(actionDecoration.color, isNot(normalDecoration.color));
  });
```

- [x] **Step 8：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_option_chip_group_test.dart`
Expected: PASS（8 個測試全過）——Step 3 的實作已涵蓋這些情境。

- [x] **Step 9：新增測試——nullable 泛型（`T = WritingMode?`）的選中比對迴歸保護**

**審查修正 M2（review-plan-issue-1.md）**：後續 Issue 3 會有 `WritingMode?`／`PageTurnMode?`／`ScreenOrientationSetting?` 這類選項值本身包含真實 `null`（代表「採用書籍排版」／「使用全域預設」）的單選群組，先在本 Task 補一組含 `null` 的泛型測試，確保 `EBOptionChipGroup<T>`／`ReaderOptionTile<T>` 這層泛型轉發對 `null` 的相等比對沒有非預期行為。

追加（於檔案頂部 `import` 區塊補上 `import 'package:elinkbook/reader/writing_mode.dart';`）：

```dart
  testWidgets('T 為 nullable 型別（WritingMode?）且選項值含 null 時，選中比對正確',
      (tester) async {
    WritingMode? selected = WritingMode.horizontal;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EBOptionChipGroup<WritingMode?>(
              items: const [
                EBOptionChipItem<WritingMode?>(
                  itemKey: Key('writing_mode_book'),
                  value: null,
                  icon: Icons.auto_stories,
                  label: '書籍',
                  tooltip: '採用書籍排版',
                ),
                EBOptionChipItem<WritingMode?>(
                  itemKey: Key('writing_mode_vertical'),
                  value: WritingMode.vertical,
                  icon: Icons.text_rotate_vertical,
                  label: '直排',
                  tooltip: '強制直排',
                ),
              ],
              groupValue: selected,
              onSelected: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    ));

    // 初始 groupValue 是 WritingMode.horizontal，兩個選項皆不相符，兩者
    // 都應呈現未選中樣式（不應有任何一個誤判為選中）。
    final bookTile =
        tester.widget<Container>(find.byKey(const Key('writing_mode_book')));
    final verticalTile = tester.widget<Container>(
        find.byKey(const Key('writing_mode_vertical')));
    expect(
      (bookTile.decoration as BoxDecoration).color,
      (verticalTile.decoration as BoxDecoration).color,
    );

    // 點擊「書籍」（value: null）應正確觸發 onSelected(null)。
    await tester.tap(find.byKey(const Key('writing_mode_book')));
    await tester.pump();
    expect(selected, isNull);

    // groupValue 變成 null 後，「書籍」這個 value 同為 null 的選項應正確
    // 判定為選中（與「直排」呈現不同底色）。
    final bookTileAfter =
        tester.widget<Container>(find.byKey(const Key('writing_mode_book')));
    final verticalTileAfter = tester.widget<Container>(
        find.byKey(const Key('writing_mode_vertical')));
    expect(
      (bookTileAfter.decoration as BoxDecoration).color,
      isNot((verticalTileAfter.decoration as BoxDecoration).color),
    );
  });
```

- [x] **Step 10：執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_option_chip_group_test.dart`
Expected: PASS（9 個測試全過）——`EBOptionChipGroup<T>`／`ReaderOptionTile<T>` 的泛型轉發本來就沒有對 `T` 做任何額外假設，這是一個純粹的迴歸保護測試，預期不需要修改 `eb_option_chip_group.dart` 就會直接通過；若竟然沒通過，代表 Step 3 的實作藏有未預期的泛型 bug，須另外排查修正。

- [x] **Step 11：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/widgets/eb_option_chip_group.dart test/screens/widgets/eb_option_chip_group_test.dart`
Expected: `No issues found!`

- [x] **Step 12：Commit**

```bash
git add app/lib/screens/widgets/eb_option_chip_group.dart app/test/screens/widgets/eb_option_chip_group_test.dart
git commit -m "feat(epic-39): Issue 1 Task 3 — 新增 EBOptionChipGroup 響應式單選晶片群組"
```

---

### Task 4：收尾——全套測試與更新計畫狀態

**Files:**
- 無新增/修改程式碼檔案（僅驗證與文件收尾）。

- [x] **Step 1：跑全套 `flutter test`**

Run: `flutter test`
Expected: 全數通過（既有測試數量 + 本 Issue 新增的 19 個測試——`eb_stepper_test.dart` 7 個、`reader_option_tile_test.dart` 新增 3 個〔既有 1 個零回歸〕、`eb_option_chip_group_test.dart` 9 個），零回歸。

- [x] **Step 2：跑全套 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3：將本檔案所有 Task 的 Step 勾選為完成**

把本檔案（`docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-1.md`）Task 1-4 全部 `- [ ]` 改為 `- [x]`。

- [x] **Step 4：Commit 計畫狀態更新**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-1.md
git commit -m "docs(epic-39): Issue 1 計畫執行完成，全部 Step 標記完成"
```

Issue 1 完成後，交由人類決定是否發起程式碼審查（`superpowers:requesting-code-review`），審查通過後才可進入 Issue 2。
