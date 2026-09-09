# Epic 39 — Issue 5：`PdfSettingsSheet` 視覺風格對齊 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PdfSettingsSheet` 新增必填 `isEinkMode` 建構參數；濾鏡分頁 3 個數值列（對比度/亮度/加粗強度）依 `isEinkMode` 在 `Slider`＋±按鈕與 `EBStepper` 之間切換；顯示／裁切分頁共 5 組單選群組（Fit 模式／雙頁模式／頁面方向／換頁動畫／裁切模式）改用 `EBOptionChipGroup`，裁切模式的「手動選區」項目改用 `EBOptionChipItem.onTap` 承載，取代既有的 `ReaderOptionTile<bool>` sentinel 寫法。

**Architecture:** `PdfSettingsSheet` 依 `epic-4-pdf-enhance/design.md` 決策 #10 刻意不與 `ReaderSettingsSheet` 共用私有邏輯，只共用 Issue 1 新增的兩個通用元件 `EBStepper`／`EBOptionChipGroup`，因此本計畫的程式改動範圍完全侷限在 `pdf_settings_sheet.dart` 這一個檔案（加上 `reader_screen.dart` 呼叫處補一個具名參數）。拆成 3 個程式 Task：(1) 先接上 `isEinkMode` 建構參數（純介面串接，比照 Issue 2 Task 1 對 `ReaderSettingsSheet` 的既有模式）；(2) 濾鏡分頁 3 個滑桿改用 `EBStepper`——**這裡直接套用 Issue 2 審查修正 C1 已在 `ReaderSettingsSheet._buildSliderRow` 建立的先例**：`isEinkMode: true` 時頂列隱藏 `Text(displayValue)`，避免與 `EBStepper` 內部顯示的數值重複；`PdfSettingsSheet` 的 `_buildSliderRow` 目前無條件顯示 `Text(clampedValue.round().toString())`，若不主動套用這個已知修正，之後的程式審查幾乎必然會提出同一個問題（`review-plan-issue-2.md` C1／`review-plan-issue-3.md` M1 都已證實這是本 Epic 反覆出現的既有審查重點）；(3) 5 組單選群組改用 `EBOptionChipGroup`，其中裁切模式的「手動選區」項目**直接使用真實的 `PdfCropMode.manual` 列舉值**（不是舊寫法的 `bool` sentinel）——`EBOptionChipGroup` 對 `item.onTap != null` 的項目會強制 `forceUnselected: true`（見 `eb_option_chip_group.dart:89`），與 `groupValue` 是否恰好等於 `PdfCropMode.manual`（例如使用者先前已完成一次手動裁切、`_cropMode` 已持久化為 `manual`）完全無關，天生就滿足 spec.md「不論裁切模式群組目前選中哪個值，該項目恆為未選中樣式」的要求，比舊的 `ReaderOptionTile<bool>(value: true, groupValue: false, ...)` sentinel 寫法更直接。**「卡片邊框/文字色改跟隨 `Theme.of(context)`」這條 spec.md 需求不需要獨立 Task**——`ReaderOptionTile`（`EBOptionChipGroup` 內部使用的元件）本來就已經是依 `colorScheme` 動態決定邊框/文字色（見 `reader_option_tile.dart:35-60`），這是 Task 3 轉換後自動獲得的效果，不是本 Issue 需要另外實作的邏輯；`pdf_settings_sheet.dart` 目前也確認沒有任何寫死的 `Colors.xxx`（已用 `grep` 逐行查核）。

**Tech Stack:** Flutter/Dart，`flutter_test`，既有 `PdfSettingsSheet`（`app/lib/screens/pdf_settings_sheet.dart`）、Issue 1 新增的 `EBStepper`（`app/lib/screens/widgets/eb_stepper.dart`）與 `EBOptionChipGroup`／`EBOptionChipItem`（`app/lib/screens/widgets/eb_option_chip_group.dart`）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`（§「既有元件異動」`PdfSettingsSheet`、§「選項標籤對照表」PDF 相關 5 列、審查修正 I1）、`docs/epics/epic-39-layout-settings-redesign/issues.md`（Issue 5，含審查回應 I4）——本計畫實作前已讀過 `design.md`／`issues.md`／`spec.md`、三份 Epic 階段審查報告（`reviews/review-design.md`、`review-spec.md`、`review-issues.md`），以及 Issue 1-4 的計畫與實作審查報告，並實際讀取目前（Issue 1-4 已合併後）的 `pdf_settings_sheet.dart`（457 行）／`pdf_settings_sheet_test.dart`（720 行，42 個既有測試）／`reader_screen.dart`／`pdf_crop_mode.dart` 原始碼確認本計畫所有行號、程式碼片段與既有測試數量皆對應現況。

## Global Constraints

- 所有顏色一律讀 `Theme.of(context).colorScheme`（`CLAUDE.md`）——本 Issue 不新增任何顏色邏輯，`grep -n "Colors\." lib/screens/pdf_settings_sheet.dart` 目前查無結果，Task 3 轉換後也不應該出現任何寫死色值。
- `PdfSettingsSheet` 新增 `isEinkMode` 為**必填**參數（`required bool isEinkMode`，比照 `ReaderSettingsSheet`／`TtsPanel`／`ReaderChromeTopBar` 既有慣例，不使用預設值 `false` 免填），因此所有既有建構呼叫點（`reader_screen.dart` 1 處、`pdf_settings_sheet_test.dart` 3 處：`_pumpSheet`／`_pumpModalSheet` 兩個 helper 內各 1 處＋既有 E-Ink 測試 1 處直接建構）皆須同步更新。
- **`_buildSliderRow` 已覆寫的頂列數值文字，只在 `isEinkMode: true` 時隱藏**——比照 Issue 2 審查修正 C1 已在 `ReaderSettingsSheet._buildSliderRow` 建立的先例：一般主題下 `Slider` 本身不具備數值回饋能力（沒有設定 `label` 參數），若把數值文字整個拿掉，使用者調整滑桿時會完全看不到目前數值，因此一般主題下必須保留、只有 E-Ink 模式才隱藏（`EBStepper` 內部已經顯示一次）。
- **裁切模式群組的「手動選區」項目改用 `EBOptionChipItem<PdfCropMode>.onTap`，`value` 直接填入真實的 `PdfCropMode.manual`**（不是 `bool` sentinel）——`EBOptionChipGroup` 對 `onTap != null` 的項目天生強制 `forceUnselected: true`，與 `groupValue` 目前是否恰好等於 `PdfCropMode.manual` 無關，`onSelected` 也不會被觸發（改呼叫 `item.onTap!`），行為與 spec.md 要求完全一致。
- **5 組單選群組轉換為 `EBOptionChipGroup` 時不設定 `visualDensity`**（維持元件預設值 `VisualDensity.standard`）——這是刻意的選擇，不是遺漏：現況 `pdf_settings_sheet.dart` 的既有 5 處 `ReaderOptionTile` 呼叫全部都沒有傳入 `visualDensity` 參數（皆為預設 `standard`），與 `ReaderSettingsSheet` 那邊統一用 `VisualDensity.compact` 是兩碼事，本 Issue 不應該借機把視覺密度也改掉。
- TDD 嚴格執行：每個 Step 先寫失敗測試，確認 RED（含確認失敗原因正確），再寫最小實作使其 GREEN，不得反向操作；不得寫一個「當下就會直接通過、不曾真正經歷 RED」的測試獨立成一個 Step（比照 `review-plan-issue-2.md` I2 的既有先例：若某個情境的驗證與另一個情境共用同一次實作，兩者須合併在同一個 Step 內一起寫測試）。
- 測試執行範圍：本 Issue 只需要跑 `flutter test test/screens/pdf_settings_sheet_test.dart`（本 Issue 唯一異動的測試檔），全套 `flutter test` 留到本計畫最後一個 Task 執行一次。
- 所有新程式碼註解、文件字串、測試描述文字一律使用正體中文（zh-TW），專業術語可保留英文。
- 所有 `flutter test`／`flutter analyze` 指令皆在 `app/` 目錄下執行。

---

### Task 1：`PdfSettingsSheet` 新增 `isEinkMode` 建構參數（純介面串接）

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart:23-37`（class 宣告與建構子）
- Modify: `app/lib/screens/reader_screen.dart:836-845`（`_openPdfSettings()` 呼叫處）
- Test: `app/test/screens/pdf_settings_sheet_test.dart`（既有 3 處 `PdfSettingsSheet(` 建構呼叫點：`_pumpSheet`／`_pumpModalSheet` 兩個 helper＋第 649-669 行既有 E-Ink 測試的直接建構）

**Interfaces:**
- Produces：`PdfSettingsSheet` 新增必填欄位 `final bool isEinkMode;`。`_pumpSheet`／`_pumpModalSheet` 兩個測試 helper 皆新增可選具名參數 `bool isEinkMode = false`，供 Task 2 的新測試轉發使用。
- Consumes：無新依賴。本 Task 不改變任何渲染邏輯，純粹讓 `widget.isEinkMode` 在 State 內可讀取，供 Task 2/3 使用。

- [ ] **Step 1：新增必填參數（刻意讓既有測試檔案編譯失敗，作為本 Task 的 RED）**

修改 `app/lib/screens/pdf_settings_sheet.dart` 第 23-37 行（審查修正 M1，`review-plan-issue-5.md`：順帶在類別頂端既有 doc comment 補上一句說明 `isEinkMode` 用途，比照 `ReaderSettingsSheet` 既有慣例）：

```dart
/// PDF 專屬版面設定 Bottom Sheet（FR-11），三分頁結構：顯示／濾鏡／裁切，
/// 見 docs/epics/epic-4-pdf-enhance/design.md 決策 #10（不與 EPUB 用的
/// `ReaderSettingsSheet` 共用元件）。三分頁（Fit 模式、濾鏡、裁切模式）
/// 皆已完整實作。
///
/// 純展示、無 I/O：每次選擇立即透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]（`_notifyChanged` 只需重建目前已追蹤的本地狀態欄位
/// ＋ 原樣帶回 [BookReaderPrefs.pdfCropRect]——因為同一本書不會同時是
/// EPUB 又是 PDF，未追蹤的 EPUB 欄位維持 null 不影響實際使用情境）。
/// 「手動選區」選項點擊時透過 [onRequestManualCrop] 通知呼叫端
/// （`PdfSettingsSheet` 本身不直接操作 `PdfReaderView`，維持既有單向資料
/// 流，見 spec.md「模組」段落）；持久化由呼叫端（`ReaderScreen`）負責。
/// [isEinkMode] 決定濾鏡分頁數值列採用一般主題的 `Slider`＋±按鈕，或
/// E-Ink 模式的 `EBStepper`。
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final VoidCallback onRequestManualCrop;
  final bool isEinkMode;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onRequestManualCrop,
    required this.isEinkMode,
  });

  @override
  State<PdfSettingsSheet> createState() => _PdfSettingsSheetState();
}
```

同步修改 `app/lib/screens/reader_screen.dart` 第 836-845 行的呼叫處：

```dart
  void _openPdfSettings() {
    _showThemedModalBottomSheet<void>(
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        onRequestManualCrop: _handleRequestManualCrop,
        isEinkMode: widget.isEinkMode,
      ),
    );
  }
```

- [ ] **Step 2：執行測試確認編譯失敗**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: 編譯失敗（`The named parameter 'isEinkMode' is required, but there's no corresponding argument.`——`pdf_settings_sheet_test.dart` 內 3 處既有 `PdfSettingsSheet(` 建構呼叫點皆未提供）。

- [ ] **Step 3：修正測試檔既有 3 處建構呼叫點**

(a) `_pumpSheet` helper（第 672-687 行）新增可選參數並轉發：

```dart
Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
  bool isEinkMode = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        onRequestManualCrop: onRequestManualCrop,
        isEinkMode: isEinkMode,
      ),
    ),
  ));
}
```

(b) `_pumpModalSheet` helper（第 691-719 行）同樣新增可選參數並轉發（比照 `review-plan-issue-2.md` M2 的既有先例：不寫死 `isEinkMode: false`，改為可選具名參數）：

```dart
Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
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
            builder: (_) => PdfSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
              onRequestManualCrop: onRequestManualCrop,
              isEinkMode: isEinkMode,
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

（既有唯一一處呼叫點 `await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});` 不需要修改——`isEinkMode` 有預設值 `false`，維持零回歸。）

(c) 既有 E-Ink 測試「`PdfSettingsSheet` 在 E-Ink 模式下選中項目呈現高對比底色」（第 649-669 行）補上 `isEinkMode: true,`（這個測試本來就套用 `buildEinkThemeData()`，語意上就是在 E-Ink 情境下測試，補上此參數才誠實反映情境）：

```dart
  testWidgets('PdfSettingsSheet 在 E-Ink 模式下選中項目呈現高對比底色', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: PdfSettingsSheet(
          prefs: const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
          onChanged: (_) {},
          onRequestManualCrop: () {},
          isEinkMode: true,
        ),
      ),
    ));
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（42 個測試全過，數量與異動前相同——本 Task 純介面新增，無行為變化，零回歸）。

- [ ] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/pdf_settings_sheet.dart lib/screens/reader_screen.dart test/screens/pdf_settings_sheet_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/lib/screens/reader_screen.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 5 Task 1 — PdfSettingsSheet 新增 isEinkMode 建構參數"
```

---

### Task 2：`_buildSliderRow`（對比度/亮度/加粗強度）依 `isEinkMode` 切換 `EBStepper`

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`（頂端 `import`；`_buildSliderRow`，第 404-455 行）
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Issue 1 的 `EBStepper`（`keyPrefix`／`value`／`min`／`max`／`step`／`displayValue`／`onChanged`／`mainAxisSize`／`mainAxisAlignment` 皆已存在，直接複用）；Task 1 的 `widget.isEinkMode`。
- Produces：無新公開介面，`_buildSliderRow` 依然是 `_PdfSettingsSheetState` 私有方法，簽章不變（不像 `ReaderSettingsSheet._buildSliderRow` 有 `isOverridden`／`onReset` 參數——spec.md 明訂「覆寫徽章不適用」，`PdfSettingsSheet` 沒有全域/單書雙態語意欄位，本方法不需要也不會新增這兩個參數）。

- [ ] **Step 1：寫失敗測試——結構＋互動＋頂列數值文字條件顯示，一併撰寫**

在 `app/test/screens/pdf_settings_sheet_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets(
      'isEinkMode: true 時，濾鏡分頁 3 個數值列皆改為 EBStepper，不存在任何 '
      'Slider，且頂列不重複顯示數值文字（比照 review-plan-issue-2.md C1 對 '
      'ReaderSettingsSheet._buildSliderRow 已建立的先例——EBStepper 內部已顯示'
      '一次，頂列不應再顯示第二次），點擊 + 觸發 onChanged'
      '（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 20),
      (prefs) => notified = prefs,
      isEinkMode: true,
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    for (final keyPrefix in [
      'pdf_settings_contrast',
      'pdf_settings_brightness',
      'pdf_settings_bold_strength',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_value')), findsOneWidget,
          reason: '$keyPrefix 應改為 EBStepper（僅 EBStepper 具備 _value Key）');
    }
    expect(find.byType(Slider), findsNothing,
        reason: '濾鏡分頁在 E-Ink 模式下不應存在任何 Slider');
    expect(find.text('20'), findsOneWidget,
        reason: '對比度數值只應在 EBStepper 內顯示一次，頂列不應重複顯示');
    // 審查修正 M3（review-plan-issue-5.md）：一併確認 _decrement 按鈕存在，
    // 不只驗證 +（EBStepper 本身的 +/- 邊界行為已在 Issue 1 完整測試，這裡
    // 只需確認整合層兩顆按鈕都確實被渲染出來）。
    expect(find.byKey(const Key('pdf_settings_contrast_decrement')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified, isNotNull);
    expect(notified!.pdfContrast, greaterThan(20));
  });

  testWidgets(
      'isEinkMode: false（預設）時，濾鏡分頁維持既有 Slider 且頂列保留數值文字'
      '（一般主題 Slider 不具備數值回饋能力，比照 review-plan-issue-2.md C1 '
      '先例，既有行為零回歸）（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(pdfContrast: 20), (_) {});
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdf_settings_contrast_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_contrast_value')),
        findsNothing);
    expect(find.text('20'), findsOneWidget,
        reason: '一般主題下頂列應保留數值文字');
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: 第一個測試 FAIL——現況無條件渲染 `Slider`，`_value` 這個 Key 尚不存在於任何地方，`find.byType(Slider)` 也會 `findsWidgets` 而非 `findsNothing`。第二個測試（`isEinkMode: false` 迴歸）在目前程式碼下**已經會通過**——現況本來就無條件渲染 `Slider` 且頂列本來就顯示數值文字；因為兩個測試寫在同一個 Step、一起執行，整體 `flutter test` 結果仍是 FAIL（第一個測試失敗），這是刻意避免「有測試從未真正 RED 過」的寫法（比照 `review-plan-issue-2.md` I2 的既有先例）——待 Step 3 實作完成後，兩個測試會在同一次 GREEN 內一起被驗證。

- [ ] **Step 3：實作**

`app/lib/screens/pdf_settings_sheet.dart` 頂端 import 區塊新增：

```dart
import 'widgets/eb_stepper.dart';
```

修改 `_buildSliderRow`（第 404-455 行）：

```dart
  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    final displayValue = clampedValue.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              if (!widget.isEinkMode) Text(displayValue),
            ],
          ),
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
        ],
      ),
    );
  }
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（44 個測試全過：既有 42 個＋本 Task 新增 2 個）。

- [ ] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/pdf_settings_sheet.dart test/screens/pdf_settings_sheet_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 5 Task 2 — PdfSettingsSheet 濾鏡數值列依 isEinkMode 切換 EBStepper"
```

---

### Task 3：5 組單選群組改用 `EBOptionChipGroup`（含裁切模式「手動選區」改用 `EBOptionChipItem.onTap`）

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`（`import` 區塊；`_buildDisplayTab`／`_buildCropTab` 共 5 組單選群組）
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Issue 1 的 `EBOptionChipGroup<T>`／`EBOptionChipItem<T>`（`items`／`groupValue`／`onSelected`／`EBOptionChipItem.onTap` 皆已存在，直接複用）。
- Produces：無新公開介面，5 個群組所在的 `_buildDisplayTab()`／`_buildCropTab()` 方法簽章不變。`app/lib/screens/pdf_settings_sheet.dart` 不再直接參照 `ReaderOptionTile`，移除 `import 'widgets/reader_option_tile.dart';`，新增 `import 'widgets/eb_option_chip_group.dart';`。

- [ ] **Step 1：寫失敗測試——5 組群組皆應顯示 spec.md 選項標籤對照表定義的短標籤＋手動選區恆未選中的回歸測試**

在 `app/test/screens/pdf_settings_sheet_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets(
      'Fit 模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤'
      '對照表定義的短標籤（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [
      ('page_fit', '整頁'),
      ('fit_width', '頁寬'),
      ('actual_size', '原比'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_fit_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_fit_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '雙頁模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [
      ('auto', '自動'),
      ('always', '雙頁'),
      ('never', '單頁'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_dual_page_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_dual_page_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '頁面方向群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [
      ('ltr', '左翻'),
      ('rtl', '右翻'),
    ]) {
      final (suffix, label) = item;
      await tester.ensureVisible(
          find.byKey(Key('pdf_settings_dual_page_direction_$suffix')));
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_dual_page_direction_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_dual_page_direction_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '換頁動畫群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [
      ('slide', '滑動'),
      ('none', '無'),
    ]) {
      final (suffix, label) = item;
      await tester.dragUntilVisible(
        find.byKey(Key('pdf_settings_page_turn_animation_$suffix')),
        find.byKey(const Key('pdf_settings_display_scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_page_turn_animation_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_page_turn_animation_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '裁切模式群組改用 EBOptionChipGroup 後，「不裁」「智慧」「手動」三個選項'
      '皆顯示短標籤（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    for (final item in [
      ('none', '不裁'),
      ('auto', '智慧'),
      ('manual', '手動'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_crop_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_crop_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '裁切模式群組選中態機制正確運作：一般選項相符時顯示選中樣式，'
      '「手動選區」動作型項目無論 groupValue 為何皆恆為未選中樣式'
      '（審查修正 I1，review-plan-issue-5.md：補上正反對照斷言，避免僅斷言'
      '未選中態時，若選取機制整體失效〔例如 groupValue 傳遞錯誤導致全部'
      '晶片皆渲染為未選中〕仍會誤判通過；審查修正 I4，review-issues.md／'
      'I1，review-spec.md：EBOptionChipItem.onTap 項目由 forceUnselected '
      '保證，取代舊 bool sentinel 寫法後行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 5）',
      (tester) async {
    // 情境一：groupValue 為一般選項（autoDetect），驗證選中態機制正常
    // 運作，「手動選區」在此一般情境下也維持未選中（基準對照）。
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfCropMode: PdfCropMode.autoDetect),
      (_) {},
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('pdf_settings_crop_mode_auto')),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final autoContainer = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_crop_mode_auto')),
    );
    expect((autoContainer.decoration as BoxDecoration).color,
        colorScheme.primaryContainer,
        reason: '選中態項目背景色應為 primaryContainer，證明選取機制正常運作');

    final manualContainerCase1 = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_crop_mode_manual')),
    );
    expect((manualContainerCase1.decoration as BoxDecoration).color,
        colorScheme.surface,
        reason: '手動選區項目在一般情境下應維持未選中樣式');

    // 情境二（原本的邊界情境）：groupValue 剛好等於 PdfCropMode.manual
    // （例如使用者先前已完成一次手動裁切、_cropMode 已持久化為 manual），
    // 「手動選區」項目仍必須維持未選中——若實作誤用 value == groupValue
    // 判斷選中（而非依賴 forceUnselected），這裡就會變成選中態。
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfCropMode: PdfCropMode.manual),
      (_) {},
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    final manualContainerCase2 = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_crop_mode_manual')),
    );
    expect((manualContainerCase2.decoration as BoxDecoration).color,
        colorScheme.surface,
        reason: 'groupValue 剛好等於 PdfCropMode.manual 時，手動選區項目仍'
            '應維持未選中樣式（forceUnselected 機制的關鍵驗證）');
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: 前 5 個測試全數 FAIL——現況 5 組群組皆用裸 `ReaderOptionTile`（未傳 `label`），畫面上完全沒有任何選項文字標籤，`find.text(label)` 一律 `findsNothing`，與預期的 `findsOneWidget` 不符。第 6 個測試（裁切模式選中態機制＋手動選區恆未選中）在目前程式碼下**已經會通過**——情境一（`autoDetect` 選中態）現況的 `ReaderOptionTile<PdfCropMode>(value: mode, groupValue: _cropMode, ...)` 本來就依真實值比較正確顯示選中樣式；情境二（`manual` 恆未選中）現況的 `ReaderOptionTile<bool>(value: true, groupValue: false, ...)` sentinel 寫法本來就恆為未選中，與 `_cropMode` 實際值無關；這則測試的價值是**迴歸防護**（Task 3 把底層元件換成 `EBOptionChipGroup`／`EBOptionChipItem.onTap` 後，這兩個既有正確行為都不能跑掉），而非本 Step 的 RED 來源。因為 6 個測試寫在同一個 Step、一起執行，整體 `flutter test` 結果仍是 FAIL（前 5 個測試失敗），這是刻意避免「有測試從未真正 RED 過」的寫法——待 Step 3 實作完成後，6 個測試會在同一次 GREEN 內一起被驗證。其餘既有 44 個測試維持 PASS。

- [ ] **Step 3：實作**

`app/lib/screens/pdf_settings_sheet.dart` 頂端 import 區塊：移除 `import 'widgets/reader_option_tile.dart';`，新增：

```dart
import 'widgets/eb_option_chip_group.dart';
```

`_buildDisplayTab()`（第 149-300 行）4 個 tuple 清單各自補上第 5 個欄位（短標籤），並把對應的 4 個 `Wrap` 區塊改為 `EBOptionChipGroup`：

```dart
  Widget _buildDisplayTab(BuildContext context) {
    const fitOptions = [
      (PdfFitMode.pageFit, 'page_fit', Icons.fit_screen, 'Page-fit（整頁）', '整頁'),
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（頁寬）', '頁寬'),
      (PdfFitMode.actualSize, 'actual_size', Icons.crop_original, '真實比例 1:1', '原比'),
    ];
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）', '自動'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁', '雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁', '單頁'),
    ];
    const directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.format_textdirection_l_to_r,
        '左到右',
        '左翻',
      ),
      (
        DualPageDirection.rtl,
        'rtl',
        Icons.format_textdirection_r_to_l,
        '右到左（日漫慣例）',
        '右翻',
      ),
    ];
    const pageTurnAnimationOptions = [
      (PdfPageTurnAnimation.slide, 'slide', Icons.swipe, '滑動', '滑動'),
      (PdfPageTurnAnimation.none, 'none', Icons.flash_on, '無', '無'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        key: const Key('pdf_settings_display_scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fit 模式'),
            const SizedBox(height: 8),
            EBOptionChipGroup<PdfFitMode>(
              items: fitOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfFitMode>(
                  itemKey: Key('pdf_settings_fit_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _fitMode,
              onSelected: (v) => setState(() {
                _fitMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('雙頁模式'),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageMode>(
              items: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageMode>(
                  itemKey: Key('pdf_settings_dual_page_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageMode,
              onSelected: (v) => setState(() {
                _dualPageMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_show_footer'),
              title: const Text('顯示頁尾'),
              value: _showFooter,
              onChanged: (v) => setState(() {
                _showFooter = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_fullscreen'),
              title: const Text('全螢幕模式'),
              value: _fullscreen,
              onChanged: (v) => setState(() {
                _fullscreen = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('頁面方向'),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageDirection>(
              items: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageDirection>(
                  itemKey: Key('pdf_settings_dual_page_direction_$keySuffix'),
                  value: direction,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageDirection,
              onSelected: (v) => setState(() {
                _dualPageDirection = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('換頁動畫'),
            const SizedBox(height: 8),
            EBOptionChipGroup<PdfPageTurnAnimation>(
              items: pageTurnAnimationOptions.map((option) {
                final (animation, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfPageTurnAnimation>(
                  itemKey: Key('pdf_settings_page_turn_animation_$keySuffix'),
                  value: animation,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _pageTurnAnimation,
              onSelected: (v) => setState(() {
                _pageTurnAnimation = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }
```

`_buildCropTab()`（第 349-399 行）：

```dart
  Widget _buildCropTab(BuildContext context) {
    const options = [
      (PdfCropMode.none, 'none', Icons.crop_free, '不裁切', '不裁'),
      (PdfCropMode.autoDetect, 'auto', Icons.auto_fix_high, '智慧自動', '智慧'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('裁切模式'),
          const SizedBox(height: 8),
          EBOptionChipGroup<PdfCropMode>(
            items: [
              ...options.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfCropMode>(
                  itemKey: Key('pdf_settings_crop_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }),
              // 手動選區：點擊只通知呼叫端進入裁切互動模式（不直接改變
              // _cropMode／呼叫 _notifyChanged），實際的 pdfCropMode=manual
              // 與 pdfCropRect 由 ReaderScreen 在使用者完成框選確認後才
              // 一併寫入（見 spec.md「ReaderScreen 內部行為異動」）。
              // 審查修正 I4（review-issues.md）／I1（review-spec.md）：改用
              // EBOptionChipItem.onTap 承載，value 直接填入真實的
              // PdfCropMode.manual——EBOptionChipGroup 對 onTap != null 的
              // 項目天生強制 forceUnselected: true，不需要再用 bool sentinel
              // （value: true, groupValue: false）製造「恆不相等」的效果。
              EBOptionChipItem<PdfCropMode>(
                itemKey: const Key('pdf_settings_crop_mode_manual'),
                value: PdfCropMode.manual,
                icon: Icons.crop,
                label: '手動',
                tooltip: '手動選區',
                onTap: () => widget.onRequestManualCrop(),
              ),
            ],
            groupValue: _cropMode,
            onSelected: (v) => setState(() {
              _cropMode = v;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }
```

（`_buildDisplayTab`／`_buildCropTab` 的 `BuildContext context` 參數維持宣告但本 Task 依然不使用——這是既有程式碼原本就有的情況，`EBStepper`／`EBOptionChipGroup` 內部自行透過各自的 `build(BuildContext context)` 讀取 `Theme.of(context)`，呼叫端不需要另外傳遞，不在本 Task 範圍內處理。）

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（50 個測試全過：既有 44 個＋本 Task 新增 6 個；既有選取/點擊切換測試、手動選區觸發 `onRequestManualCrop` 且不改變 `_cropMode` 的既有測試、`pdfCropRect` 不被清空的既有回歸測試、E-Ink 高對比選中底色測試皆零回歸——`EBOptionChipGroup` 內部仍然渲染帶相同 `itemKey` 的 `ReaderOptionTile`，既有依賴這些 Key 的測試不受影響）。

- [ ] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/pdf_settings_sheet.dart test/screens/pdf_settings_sheet_test.dart`
Expected: `No issues found!`（含確認移除 `reader_option_tile.dart` import 後沒有殘留的 unused import 警告）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 5 Task 3 — 5 組單選群組改用 EBOptionChipGroup，手動選區改用 onTap"
```

---

### Task 4：收尾——全套測試與更新計畫狀態

**Files:**
- 無新增/修改程式碼檔案（僅驗證與文件收尾）。

- [ ] **Step 1：跑全套 `flutter test`**

Run: `flutter test`
Expected: 全數通過，零回歸（`pdf_settings_sheet_test.dart` 既有 42 個＋本 Issue 新增 8 個＝50 個）。

- [ ] **Step 2：跑全套 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3：將本檔案所有 Task 的 Step 勾選為完成**

把本檔案（`docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-5.md`）Task 1-4 全部 `- [ ]` 改為 `- [x]`。

- [ ] **Step 4：Commit 計畫狀態更新**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-5.md
git commit -m "docs(epic-39): Issue 5 計畫執行完成，全部 Step 標記完成"
```

Issue 5 完成後，交由人類決定是否發起程式碼審查（`superpowers:requesting-code-review`），審查通過後才可進入 Issue 6。
