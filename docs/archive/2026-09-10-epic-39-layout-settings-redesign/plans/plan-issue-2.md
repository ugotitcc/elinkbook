# Epic 39 — Issue 2：`ReaderSettingsSheet` 文字＋邊界分頁 — Slider/EBStepper 切換與覆寫文字徽章 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ReaderSettingsSheet` 新增 `isEinkMode` 建構參數；私有 `_buildSliderRow`（同時承載「文字」分頁 5 個數值列與「邊界」分頁 4 個邊界數值列共 9 處）依 `isEinkMode` 在 `Slider`＋±按鈕與 Issue 1 新增的 `EBStepper` 之間切換；「已覆寫／使用全域預設」的視覺呈現從封鎖圖示改為文字徽章。

**Architecture:** 三項變更全部集中在同一個私有方法 `_buildSliderRow`，依「不需要重工」的順序拆成三個 Task：(1) 先幫 `ReaderSettingsSheet` 接上 `isEinkMode` 建構參數（純介面串接，零視覺變動，順便修正 5 處既有測試建構呼叫點）——**這一步必須排在最前面**，因為文字徽章（Task 2）本身的邊框樣式與「已覆寫時是否保留原始數值文字」都需要依 `widget.isEinkMode` 分支，若不先接好這個參數，Task 2 會沒有旗標可讀；(2) 覆寫徽章從圖示改成文字，徽章本身依 `widget.isEinkMode` 套用不同邊框樣式（一般主題 35% 透明度細框／E-Ink 純黑 1.5dp 高對比框），且**只有 E-Ink 模式**才隱藏已覆寫欄位頂列的原始數值文字（一般主題下 Slider 沒有任何其他管道顯示目前數值，必須保留，否則使用者調整滑桿時完全看不到數字，見 `reviews/review-plan-issue-2.md` C1）；(3) 最後才讓 `_buildSliderRow` 依 `isEinkMode` 切換 `EBStepper`，此時只剩 `isOverridden == null`（邊界分頁 4 欄，該分支不受 Task 2 影響）這一個分支仍會在 E-Ink 模式下重複顯示原始數值，只需要把這一個分支的顯示條件加上 `&& !widget.isEinkMode` 即可滿足審查修正 M1，不需要動到 Task 2 已經改好的另外兩個分支。

**Tech Stack:** Flutter/Dart，`flutter_test`，既有 `ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`）、Issue 1 新增的 `EBStepper`（`app/lib/screens/widgets/eb_stepper.dart`）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`（§「既有元件異動」`ReaderSettingsSheet` 前 4 條、§「卡片邊框視覺規範」、§「審查回應」C2/C3/M1）、`docs/epics/epic-39-layout-settings-redesign/issues.md`（Issue 2，含審查回應 C2/I2）——本計畫實作前已讀過 `design.md`／`issues.md`／`spec.md`、三份 Epic 階段審查報告（`reviews/review-design.md`、`review-spec.md`、`review-issues.md`），以及本計畫自己的審查報告 `reviews/review-plan-issue-2.md`（本版已依該報告 C1/I1/I2/M1/M2 全數修正，見下方各 Task 內文標註）。

## Global Constraints

- 所有顏色一律讀 `Theme.of(context).colorScheme`，禁止在畫面/元件層寫死 Hex/`Colors.xxx`（`CLAUDE.md`；本 Issue 新增的 `_buildOverrideBadge` 徽章樣式必須遵守）。
- **本 Issue 範圍明確排除**：`_buildColumnModeRow()` 內獨立宣告、未經過 `_buildSliderRow` 的 `reader_settings_column_size_slider`（該控制項未受本 Issue 影響，留給 Issue 3——`spec.md` 審查修正 C3）；Tab 改名／`_buildTextAlignRow()` 搬移；任何 `Wrap` 包 `ReaderOptionTile` 的單選群組改用 `EBOptionChipGroup`（皆屬 Issue 3）；`_buildLayoutPresetSection()`「目前套用中」標示（屬 Issue 4）；`PdfSettingsSheet`／`FxlSettingsSheet`（屬 Issue 5/6）。
- 「已覆寫／使用全域預設」文字徽章的 `Key('${keyPrefix}_reset')`／`Key('${keyPrefix}_unset_indicator')` 兩個既有 Key **必須維持掛載在對應位置不變**（`spec.md` 審查修正 C2：`reader_settings_sheet_test.dart` 有多處既有斷言直接依賴這兩個 Key）。
- `ReaderSettingsSheet` 新增 `isEinkMode` 為**必填**參數（`required bool isEinkMode`，比照 `spec.md`「既有元件異動」與 `TtsPanel`／`ReaderChromeTopBar` 既有慣例，不使用預設值 `false` 免填），因此所有既有建構呼叫點（`reader_screen.dart` 1 處、`reader_settings_sheet_test.dart` 5 處）皆須同步更新，這是本 Issue 必要的配套修改，不是意外波及。
- **已覆寫（`isOverridden == true`）欄位的頂列原始數值文字 `Text(displayValue)`，只在 `widget.isEinkMode == true` 時隱藏**——一般主題下必須與文字徽章並存（`review-plan-issue-2.md` C1：一般主題的 `Slider` 沒有設定 `label` 參數、本身不具備數值回饋能力，若把原始數值文字整個拿掉，一般使用者調整滑桿時會完全看不到目前數值）。
- 文字徽章 `_buildOverrideBadge` 必須依 `widget.isEinkMode` 套用邊框（一般主題：`colorScheme.outline.withValues(alpha: 0.35)`、寬度 `1.0dp`；E-Ink 模式：純黑 `1.5dp`，比照 `spec.md`「卡片邊框視覺規範」既有 Token）——E-Ink 主題的 `surfaceContainerHighest` 與 `surface` 皆為純白（`app_theme_data.dart` `_buildEinkTheme()`），若徽章沒有邊框，在 E-Ink 模式下會呈現白底白字般的視覺隱形（`review-plan-issue-2.md` I1）。
- TDD 嚴格執行：每個 Step 先寫失敗測試（或確認編譯失敗），確認 RED（含確認失敗原因正確），再寫最小實作使其 GREEN，不得反向操作；**不得**寫一個「當下就會直接通過、不曾真正經歷 RED」的測試獨立成一個 Step（`review-plan-issue-2.md` I2）——若某個互動情境的驗證與另一個情境共用同一次實作，兩者須合併在同一個 Step 內一起寫測試、一起確認 RED、一起靠同一次實作 GREEN。
- 本 Issue 的 Task 之間只需要跑 `flutter test test/screens/reader_settings_sheet_test.dart`（本 Issue 唯一異動的測試檔），不需要在每個 Task 都跑全套 `flutter test`；全套測試留到本計畫最後一個 Task 執行一次（比照 `CLAUDE.md`「測試執行範圍」既有慣例）。
- 所有新程式碼註解、文件字串、測試描述文字一律使用正體中文（zh-TW），專業術語可保留英文。
- 所有 `flutter test`／`flutter analyze` 指令皆在 `app/` 目錄下執行。

---

### Task 1：`ReaderSettingsSheet` 新增 `isEinkMode` 建構參數（純介面串接）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:25-56`（class 宣告與建構子）
- Modify: `app/lib/screens/reader_screen.dart:806-829`（`_openLayoutSettings()` 呼叫處）
- Test: `app/test/screens/reader_settings_sheet_test.dart`（既有 5 處 `ReaderSettingsSheet(` 建構呼叫點，含 `_pumpSheet`／`_pumpModalSheet` 兩個 helper）

**Interfaces:**
- Produces：`ReaderSettingsSheet` 新增必填欄位 `final bool isEinkMode;`。`_pumpSheet`／`_pumpModalSheet` 兩個測試 helper 皆新增可選具名參數 `bool isEinkMode = false`，供 Task 2/3 的新測試轉發使用。
- Consumes：無新依賴。本 Task 不改變任何渲染邏輯，純粹讓 `widget.isEinkMode` 在 State 內可讀取，供 Task 2/3 使用。

- [x] **Step 1：新增必填參數（刻意讓既有測試檔案編譯失敗，作為本 Task 的 RED）**

修改 `app/lib/screens/reader_settings_sheet.dart` 第 25-56 行：

```dart
class ReaderSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final List<CustomFont> customFonts;
  final String bookId;
  final List<LayoutPreset> layoutPresets;
  final void Function(BookReaderPrefs currentDraft) onSaveAsPreset;
  final void Function(LayoutPreset preset, {required List<String> targetBookIds})
      onApplyPreset;
  final void Function(String sourceBookId, {required List<String> targetBookIds})
      onApplyFromBook;
  final Future<List<String>?> Function({required bool multiSelect})
      onRequestBookPicker;
  final void Function(int id) onDeletePreset;
  final bool isEinkMode;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    this.customFonts = const [],
    required this.bookId,
    this.layoutPresets = const [],
    required this.onSaveAsPreset,
    required this.onApplyPreset,
    required this.onApplyFromBook,
    required this.onRequestBookPicker,
    required this.onDeletePreset,
    required this.isEinkMode,
  });
```

同步修改 `app/lib/screens/reader_screen.dart` 第 806-816 行的呼叫處，新增一行：

```dart
          return ReaderSettingsSheet(
            prefs: _prefs,
            onChanged: _handlePrefsChanged,
            customFonts: _customFonts,
            bookId: widget.bookId,
            layoutPresets: _layoutPresets,
            isEinkMode: widget.isEinkMode,
            onSaveAsPreset: (draft) async {
```

- [x] **Step 2：執行測試確認編譯失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 編譯失敗（`The named parameter 'isEinkMode' is required, but there's no corresponding argument.`——`reader_settings_sheet_test.dart` 內 5 處既有 `ReaderSettingsSheet(` 建構呼叫點皆未提供）。

- [x] **Step 3：修正測試檔既有 5 處建構呼叫點**

(a) `_pumpSheet` helper（約第 1434-1472 行）新增可選參數並轉發：

```dart
Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  List<CustomFont> customFonts = const [],
  String bookId = 'b1',
  List<LayoutPreset> layoutPresets = const [],
  void Function(BookReaderPrefs)? onSaveAsPreset,
  void Function(LayoutPreset, {required List<String> targetBookIds})? onApplyPreset,
  void Function(String, {required List<String> targetBookIds})? onApplyFromBook,
  Future<List<String>?> Function({required bool multiSelect})? onRequestBookPicker,
  void Function(int)? onDeletePreset,
  bool isEinkMode = false,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ReaderSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        customFonts: customFonts,
        bookId: bookId,
        layoutPresets: layoutPresets,
        isEinkMode: isEinkMode,
        onSaveAsPreset: onSaveAsPreset ?? _noopSaveAsPreset,
        onApplyPreset: onApplyPreset ?? _noopApplyPreset,
        onApplyFromBook: onApplyFromBook ?? _noopApplyFromBook,
        onRequestBookPicker: onRequestBookPicker ?? _noopRequestBookPicker,
        onDeletePreset: onDeletePreset ?? _noopDeletePreset,
      ),
    ),
  ));
}
```

(b) 兩處既有 E-Ink 主題測試直接建構（`'ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色'`／`'排版方向覆寫為 null（預設）時...'` 兩個 `testWidgets`，各自的 `ReaderSettingsSheet(` 建構區塊內）補上一行 `isEinkMode: true,`（這兩個測試本來就套用 `buildEinkThemeData()`，語意上就是在 E-Ink 情境下測試，補上此參數才誠實反映情境，也才符合 `ReaderOptionTile` 依 `Theme` 判斷 `isEink` 的既有邏輯）：

```dart
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: const BookReaderPrefs(textAlign: EpubTextAlign.justify),
          isEinkMode: true,
          onChanged: (_) {},
```

（第二處 `prefs: BookReaderPrefs.empty` 的建構同樣補上 `isEinkMode: true,`。）

(c) `_TestSettingsSheetWrapper.build()`（約第 1509-1521 行）補上 `isEinkMode: false,`：

```dart
  @override
  Widget build(BuildContext context) {
    return ReaderSettingsSheet(
      prefs: _prefs,
      onChanged: (_) {},
      bookId: 'b1',
      isEinkMode: false,
      onSaveAsPreset: _noopSaveAsPreset,
      onApplyPreset: _noopApplyPreset,
      onApplyFromBook: _noopApplyFromBook,
      onRequestBookPicker: _noopRequestBookPicker,
      onDeletePreset: _noopDeletePreset,
    );
  }
```

(d) `_pumpModalSheet`（約第 1524-1556 行）新增可選參數並轉發（**審查修正 M2，`review-plan-issue-2.md`**：不寫死 `isEinkMode: false`，改為可選具名參數，供未來需要 modal 情境下的 E-Ink 測試時可直接傳入，不需要再改一次 helper 簽章）：

```dart
Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  bool isEinkMode = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            enableDrag: false,
            builder: (_) => ReaderSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
              bookId: 'b1',
              isEinkMode: isEinkMode,
              onSaveAsPreset: _noopSaveAsPreset,
              onApplyPreset: _noopApplyPreset,
              onApplyFromBook: _noopApplyFromBook,
              onRequestBookPicker: _noopRequestBookPicker,
              onDeletePreset: _noopDeletePreset,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
```

（既有 3 處呼叫點 `await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});` 不需要修改——`isEinkMode` 有預設值 `false`，既有呼叫點維持零回歸。）

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（55 個測試全過，數量與異動前相同——本 Task 純介面新增，無行為變化，零回歸）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart lib/screens/reader_screen.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/screens/reader_screen.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 2 Task 1 — ReaderSettingsSheet 新增 isEinkMode 建構參數"
```

---

### Task 2：`_buildSliderRow` 覆寫狀態改用文字徽章（含審查修正 C1／I1）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:642-725`（`_buildSliderRow`，新增私有 helper `_buildOverrideBadge`）
- Test: `app/test/screens/reader_settings_sheet_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Produces：私有 helper `Widget _buildOverrideBadge(BuildContext context, String text, {Key? key})`——僅供 `_buildSliderRow` 內部使用，不對外暴露；讀取 `widget.isEinkMode` 決定邊框樣式。
- Consumes：Task 1 的 `widget.isEinkMode`。

- [x] **Step 1：寫失敗測試——覆寫徽章文字、C1（一般主題保留數值／E-Ink 隱藏數值）、I1（徽章邊框）**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets(
      'isOverridden 為 false（未覆寫）時，顯示文字徽章「使用全域預設」，'
      '且維持掛載既有 _unset_indicator Key（epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    expect(find.text('使用全域預設'), findsNWidgets(5),
        reason: '文字分頁 5 個受影響欄位皆未覆寫，應各自顯示一個文字徽章');
    expect(
        find.byKey(const Key('reader_settings_font_size_unset_indicator')),
        findsOneWidget,
        reason: '既有測試依賴此 Key 判斷未覆寫狀態，Key 語意不變');
  });

  testWidgets(
      'isOverridden 為 true 且一般主題（isEinkMode: false）時，顯示「此書已覆寫」文字徽章，'
      '且仍保留原始數值文字與可運作的重置按鈕（審查修正 C1，review-plan-issue-2.md：'
      '一般主題的 Slider 不具備數值回饋能力，不可把數值文字整個拿掉）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      (prefs) => result = prefs,
    );

    expect(find.text('此書已覆寫'), findsOneWidget);
    expect(find.text('0.30em'), findsOneWidget,
        reason: '一般主題下必須保留原始數值文字，供使用者確認目前數值');
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('reader_settings_letter_spacing_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, isNull, reason: '重置行為應零回歸');
  });

  testWidgets(
      'isOverridden 為 true 且 isEinkMode: true 時，頂列只顯示「此書已覆寫」文字徽章與重置按鈕，'
      '不重複顯示原始數值文字（審查修正 C1，review-plan-issue-2.md：僅 E-Ink 模式隱藏，'
      '因為只有 EBStepper 本身會另外顯示一次數值）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      _noopOnChanged,
      isEinkMode: true,
    );

    expect(find.text('此書已覆寫'), findsOneWidget);
    expect(find.text('0.30em'), findsNothing,
        reason: 'E-Ink 模式下頂列不應顯示原始數值文字，避免與 Issue 2 後續（Task 3）'
            '接上的 EBStepper 內部顯示重複');
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);
  });

  testWidgets(
      '覆寫徽章依 isEinkMode 套用不同邊框樣式（審查修正 I1，review-plan-issue-2.md：'
      'E-Ink 主題的 surfaceContainerHighest 與 surface 皆為純白，徽章若無邊框會視覺隱形）',
      (tester) async {
    // E-Ink 主題：純黑 1.5dp 邊框。
    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: BookReaderPrefs.empty,
          isEinkMode: true,
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));

    final einkContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final einkBorder =
        (einkContainer.decoration as BoxDecoration).border as Border;
    expect(einkBorder.top.color, Colors.black);
    expect(einkBorder.top.width, 1.5);
  });

  testWidgets(
      '一般主題下覆寫徽章邊框為 outline 35% 透明度、寬度 1.0dp'
      '（審查修正 I1，review-plan-issue-2.md）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    final context = tester.element(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final expectedColor =
        Theme.of(context).colorScheme.outline.withValues(alpha: 0.35);
    final container = tester.widget<Container>(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final border = (container.decoration as BoxDecoration).border as Border;

    expect(border.top.color, expectedColor);
    expect(border.top.width, 1.0);
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 新增的 5 個測試全數 FAIL——前 3 個因為現況是 `Icon(Icons.block)` 而非文字（`find.text(...)` 找不到）；後 2 個因為現況的頂端 `Row` 完全沒有 `Container`/`BoxDecoration` 邊框可供斷言（`_unset_indicator` 目前掛在 `Icon` 上，`tester.widget<Container>(...)` 會找不到符合型別的 widget 而拋出例外）。其餘既有 55 個測試維持 PASS。

- [x] **Step 3：實作文字徽章（含邊框與 C1 條件式數值保留）**

修改 `app/lib/screens/reader_settings_sheet.dart`，在 `_buildSliderRow` 之前新增 helper，並替換 `_buildSliderRow` 頂端 `Row` 的後兩個分支：

```dart
  Widget _buildOverrideBadge(BuildContext context, String text, {Key? key}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline
              .withValues(alpha: widget.isEinkMode ? 1.0 : 0.35),
          width: widget.isEinkMode ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
```

`_buildSliderRow` 內的 `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [...])`（原第 661-693 行）改為：

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
                    if (!widget.isEinkMode) ...[
                      Text(displayValue),
                      const SizedBox(width: 8),
                    ],
                    _buildOverrideBadge(context, '此書已覆寫'),
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
              else if (isOverridden == false)
                Tooltip(
                  message: '跟隨本書原樣式，尚未調整',
                  child: _buildOverrideBadge(
                    context,
                    '使用全域預設',
                    key: Key('${keyPrefix}_unset_indicator'),
                  ),
                ),
            ],
          ),
```

（`isOverridden == null` 分支維持 `Text(displayValue)` 不變——`bool?` 只有 `null`/`true`/`false` 三種取值，把原本的 `else` 明確改寫為 `else if (isOverridden == false)` 是刻意的等價重寫，目的是讓 Task 3 之後只需要修改第一個 `if` 的條件式，不用再動這兩個已經改好的分支；`isOverridden == true` 分支依 `!widget.isEinkMode` 決定是否並存原始數值文字，滿足審查修正 C1。）

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（60 個測試全過，含既有 55 個零回歸）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 2 Task 2 — ReaderSettingsSheet 覆寫狀態改用文字徽章"
```

---

### Task 3：`_buildSliderRow` 依 `isEinkMode` 切換為 `EBStepper`（含審查修正 M1）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`（新增 `import 'widgets/eb_stepper.dart';`；`_buildSliderRow` 底部控制列與 `isOverridden == null` 分支條件式）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Issue 1 的 `EBStepper`（`app/lib/screens/widgets/eb_stepper.dart`，`keyPrefix`／`value`／`min`／`max`／`step`／`displayValue`／`onChanged`／`mainAxisSize`／`mainAxisAlignment` 皆已存在，直接複用）；Task 1 的 `widget.isEinkMode`；Task 2 已改寫過的 `_buildSliderRow` 頂端 `Row`（本 Task 只再修改其中 `isOverridden == null` 這一個分支的條件式）。
- Produces：無新公開介面，`_buildSliderRow` 依然是 `_ReaderSettingsSheetState` 私有方法，簽章不變。

- [x] **Step 1：寫失敗測試——結構（EBStepper 取代 Slider）與互動（點擊 +/- 觸發 onChanged）一併撰寫**

**審查修正 I2（`review-plan-issue-2.md`）**：結構驗證與互動驗證會被同一次實作（Step 3）一起滿足，因此兩者必須寫在同一個 Step 內、一起經歷 RED，不得把互動驗證拆成後面一個「寫測試即通過」的假 Step。

追加：

```dart
  testWidgets(
      'isEinkMode: true 時，文字分頁與邊界分頁共 9 個數值列皆改為 EBStepper，'
      '不存在任何 Slider（邊界分頁 4 欄不支援覆寫語意，EBStepper 版本同樣不顯示覆寫徽章，'
      'epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        isEinkMode: true);

    for (final keyPrefix in [
      'reader_settings_font_size',
      'reader_settings_font_weight',
      'reader_settings_line_height',
      'reader_settings_paragraph_spacing',
      'reader_settings_letter_spacing',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_value')), findsOneWidget,
          reason: '$keyPrefix 應改為 EBStepper（僅 EBStepper 具備 _value Key）');
    }
    expect(find.byType(Slider), findsNothing,
        reason: '文字分頁在 E-Ink 模式下不應存在任何 Slider');

    await switchToTab(tester, '邊界首尾');
    for (final keyPrefix in [
      'reader_settings_margin_top',
      'reader_settings_margin_bottom',
      'reader_settings_margin_left',
      'reader_settings_margin_right',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_value')), findsOneWidget,
          reason: '$keyPrefix 應改為 EBStepper');
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 不支援覆寫語意（isOverridden == null），'
              'EBStepper 版本同樣不應顯示覆寫徽章（issues.md Issue 2 單元測試要求）');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing,
          reason: '$keyPrefix 不支援覆寫語意，不應出現重置按鈕');
    }
    expect(find.byType(Slider), findsNothing,
        reason: '邊界分頁在 E-Ink 模式下不應存在任何 Slider');
  });

  testWidgets(
      'isEinkMode: true 時，點擊 EBStepper 的 + 觸發 onChanged，行為與 Slider 模式等價'
      '（epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
      isEinkMode: true,
    );

    await tester.tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, closeTo(17 / 16, 1e-9),
        reason: '預設 16px + step 1 = 17px，換算倍率應為 17/16');
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 第一個測試 FAIL（目前無條件渲染 `Slider`，`_value` 這個 Key 尚不存在於任何地方，`find.byType(Slider)` 也會 `findsWidgets` 而非 `findsNothing`）。第二個測試（點擊 `+`）在目前程式碼下**已經會通過**——`_increment` Key 目前無條件渲染於既有 Slider 模式的 `IconButton` 上，點擊行為與 `onChanged` 轉發邏輯本來就正確；因為兩個測試寫在同一個 Step、一起執行，整體 `flutter test` 結果仍是 FAIL（第一個測試失敗），這正是刻意避免「有測試從未真正 RED 過」的寫法——待 Step 3 實作完成後，兩個測試會在同一次 GREEN 內一起被驗證。

- [x] **Step 3：實作 `EBStepper` 分支**

在 `app/lib/screens/reader_settings_sheet.dart` 檔案頂端 import 區塊新增：

```dart
import 'widgets/eb_stepper.dart';
```

`_buildSliderRow` 內原本的控制列 `Row(children: [IconButton(_decrement), Expanded(child: Slider(...)), IconButton(_increment)])`（Task 2 未改動這段，內容與異動前一致）改為：

```dart
          widget.isEinkMode
              ? EBStepper(
                  keyPrefix: keyPrefix,
                  value: clampedValue,
                  min: min,
                  max: max,
                  step: step,
                  displayValue: displayValue,
                  onChanged: onChanged,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                )
              : Row(
                  children: [
                    IconButton(
                      key: Key('${keyPrefix}_decrement'),
                      icon: const Icon(Icons.remove),
                      onPressed: clampedValue - step < min - 1e-9
                          ? null
                          : () => onChanged((clampedValue - step).clamp(min, max)),
                    ),
                    Expanded(
                      child: Slider(
                        key: Key('${keyPrefix}_slider'),
                        value: clampedValue,
                        min: min,
                        max: max,
                        divisions: divisions,
                        onChanged: (v) => onChanged(v.clamp(min, max)),
                      ),
                    ),
                    IconButton(
                      key: Key('${keyPrefix}_increment'),
                      icon: const Icon(Icons.add),
                      onPressed: clampedValue + step > max + 1e-9
                          ? null
                          : () => onChanged((clampedValue + step).clamp(min, max)),
                    ),
                  ],
                ),
```

（`EBStepper` 衍生的 `${keyPrefix}_decrement`/`_increment` 與既有 `Slider` 模式的 ± `IconButton` Key 完全同名——兩個分支互斥渲染，不會有 Key 衝突，既有依賴這兩個 Key 的測試在兩種模式下都能找到對應按鈕。）

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（62 個測試全過）。

- [x] **Step 5：寫失敗測試——審查修正 M1：頂列不重複顯示數值文字（邊界分頁與文字分頁已覆寫欄位）**

追加：

```dart
  testWidgets(
      'isEinkMode: true 時，邊界分頁數值列頂端不重複顯示數值文字'
      '（審查修正 M1，spec.md／review-plan-issue-1.md：EBStepper 內部已顯示一次，'
      '頂列不應再顯示第二次，epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        isEinkMode: true);
    await switchToTab(tester, '邊界首尾');

    expect(find.text('32'), findsOneWidget,
        reason: '上邊界預設值 32 只應出現一次（EBStepper 內部），頂列不應重複顯示');
    expect(
        find.descendant(
          of: find.byKey(const Key('reader_settings_margin_top_value')),
          matching: find.text('32'),
        ),
        findsOneWidget,
        reason: '唯一一次顯示應在 EBStepper 的 _value 文字上');
  });

  testWidgets(
      'isEinkMode: true 且文字分頁欄位已覆寫時，數值只透過 EBStepper 顯示一次'
      '（審查修正 M1／M1-補充，review-plan-issue-2.md：Task 2 已讓 isEinkMode 時頂列'
      '不顯示原始數值，本測試驗證接上 EBStepper 後該數值改由 EBStepper 顯示，'
      '總出現次數維持恰好一次，epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 1.125), // UI 18px
      _noopOnChanged,
      isEinkMode: true,
    );

    expect(find.text('18'), findsOneWidget,
        reason: '字型大小 18px 只應出現一次，來源是 EBStepper 的 _value 文字');
    expect(
        find.descendant(
          of: find.byKey(const Key('reader_settings_font_size_value')),
          matching: find.text('18'),
        ),
        findsOneWidget,
        reason: '唯一一次顯示應在 EBStepper 的 _value 文字上，而非頂列殘留的舊 Text(displayValue)');
  });
```

- [x] **Step 6：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 第一個測試（邊界分頁）FAIL——目前 `isOverridden == null` 分支無條件渲染 `Text(displayValue)`，'32' 會在頂列與 `EBStepper` 內部（Step 3 已實作）各出現一次，`find.text('32')` 實際 `findsNWidgets(2)`，與預期的 `findsOneWidget` 不符，這是驅動 Step 7 修改的真正 RED。第二個測試（文字分頁已覆寫）在此步驟**已經 PASS**——Task 2 的 C1 修正已讓 `isOverridden == true` 分支在 `isEinkMode: true` 時不顯示頂列原始數值，Step 3 的 `EBStepper` 又已經接上並顯示該數值一次，兩者疊加後總出現次數恰好是 1，這是 Task 2＋Task 3 Step 3 組合後自然成立的迴歸保護測試，不需要 Step 7 的修改；整體 `flutter test` 結果因第一個測試失敗仍是 FAIL。

- [x] **Step 7：實作隱藏邊界分頁頂列重複數值**

修改 `_buildSliderRow` 頂端 `Row` 的第一個分支條件式（Task 2 產出的版本裡是 `if (isOverridden == null)`），改為：

```dart
              if (isOverridden == null && !widget.isEinkMode)
                Text(displayValue)
```

（只改這一行的條件式，其餘 `else if (isOverridden == true)`／`else if (isOverridden == false)` 兩個分支維持 Task 2 的版本不變——`isOverridden == null && widget.isEinkMode` 時三個條件式全部不成立，該欄位頂列不會渲染任何 Widget，只保留 `Text(label)`，符合 spec.md M1「頂端列 E-Ink 模式下只保留 Label 與覆寫徽章」。）

- [x] **Step 8：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（64 個測試全過，含既有 55 個零回歸）。

- [x] **Step 9：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [x] **Step 10：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 2 Task 3 — ReaderSettingsSheet 數值列依 isEinkMode 切換 EBStepper"
```

---

### Task 4：收尾——全套測試與更新計畫狀態

**Files:**
- 無新增/修改程式碼檔案（僅驗證與文件收尾）。

- [x] **Step 1：跑全套 `flutter test`**

Run: `flutter test`
Expected: 全數通過，零回歸（`reader_settings_sheet_test.dart` 既有 55 個＋本 Issue 新增 9 個＝64 個）。

- [x] **Step 2：跑全套 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3：將本檔案所有 Task 的 Step 勾選為完成**

把本檔案（`docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-2.md`）Task 1-4 全部 `- [x]` 改為 `- [x]`。

- [x] **Step 4：Commit 計畫狀態更新**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-2.md
git commit -m "docs(epic-39): Issue 2 計畫執行完成，全部 Step 標記完成"
```

Issue 2 完成後，交由人類決定是否發起程式碼審查（`superpowers:requesting-code-review`），審查通過後才可進入 Issue 3。
