# Epic 27 Issue 6：閱讀器版面設定面板圖示選項高對比選中狀態重構 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解決白色與 E-Ink 模式下 PDF/EPUB/FXL 設定面板中純圖示選項無法判讀選中狀態的問題，建立高對比選項容器（E-Ink 實心黑白反轉，一般主題主題色容器與邊框）。

**Architecture:**
- 建立共用 UI 元件 `ReaderOptionTile<T>`，封裝單選選項按鈕。
- 在 E-Ink 主題下：選中為「純黑背景（`Colors.black`）＋ 純白前景色（`Colors.white`）」，未選中為「純白背景 ＋ 1.5dp 純黑邊框 ＋ 純黑前景色」。
- 在一般主題（Light/Dark/Sepia）下：選中為「`primaryContainer` 背景 ＋ `primary` 邊框 ＋ `onPrimaryContainer` 前景色」，未選中為「`surface` 背景 ＋ 淺灰外框 ＋ `onSurfaceVariant` 前景色」。
- 套用至 `PdfSettingsSheet`（Fit 模式、雙頁模式、方向、換頁動畫、裁切模式）、`ReaderSettingsSheet`（文字對齊、排版方向、翻頁模式、螢幕旋轉、分欄）與 `FxlSettingsSheet`（雙頁模式、翻頁方向）。
- **E-Ink 偵測機制的技術折衷（【審查修正 Important】已記錄，見 `reviews/review-plan-issue-5-8.md` Issue 6 Important #1）：** `ReaderOptionTile` 用「顏色特徵比對」（`theme.colorScheme.primary == Colors.black && theme.scaffoldBackgroundColor == Colors.white`）判斷目前是否為 E-Ink 主題，而非本專案既有慣例——`isEinkMode` 這個明確布林旗標目前已在 `library_screen.dart`／`library_screen_dependencies.dart`／`main.dart`／`settings_screen.dart` 等多處逐層明確傳遞。這裡刻意不沿用同一慣例，是因為 `PdfSettingsSheet`／`ReaderSettingsSheet`／`FxlSettingsSheet` 三個 Sheet 目前的建構子都**沒有** `isEinkMode` 參數，若要讓 `ReaderOptionTile` 改吃顯式布林值，就必須替三個 Sheet 都新增建構參數、並讓呼叫端（`ReaderScreen`）貫穿傳遞，範圍會擴張到遠超過本 Issue「重構圖示選項高對比視覺」的範疇。本 Issue 刻意選擇「顏色推斷」這個侷限在 `ReaderOptionTile` 內部、不影響任何既有建構子簽章的折衷方案；已知風險是若未來新增任何以黑底白字為視覺基調的一般主題會被誤判為 E-Ink，可接受，因為目前專案僅有 Light/Dark/Sepia/E-Ink 四種主題（`app_theme_data.dart`），且此風險易於日後改為顯式傳遞時一次性修正。

**Tech Stack:** Flutter 3, Material 3, Dart

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 6」

## Global Constraints

- **Language**: 程式碼註解與說明一律使用正體中文 (Traditional Chinese, zh-TW)。
- **Flutter Analyze**: 靜態分析必須保持 0 warning / 0 error。
- **Keys**: 嚴格保留所有既有元件 Key（如 `pdf_settings_fit_mode_*`、`reader_settings_text_align_*`、`fxl_settings_dual_page_mode_*` 等）。

---

### Task 1: 建立通用高對比選項元件 `ReaderOptionTile<T>`

**Files:**
- Create: `app/lib/screens/widgets/reader_option_tile.dart`
- Create: `app/test/screens/widgets/reader_option_tile_test.dart`

**Interfaces:**
- Produces: `ReaderOptionTile<T>`（`key`, `value`, `groupValue`, `icon`, `label` 可選, `tooltip`, `onSelected`）

- [ ] **Step 1: Write the failing test**

建立 `app/test/screens/widgets/reader_option_tile_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/reader_option_tile.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  testWidgets('ReaderOptionTile 在 E-Ink 模式下選中項目呈現黑底白字高對比', (tester) async {
    String? selectedValue = 'A';

    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Row(
            children: [
              ReaderOptionTile<String>(
                itemKey: const Key('tile_a'),
                value: 'A',
                groupValue: selectedValue,
                icon: Icons.crop_portrait,
                tooltip: '選項 A',
                onSelected: (v) => setState(() => selectedValue = v),
              ),
              ReaderOptionTile<String>(
                itemKey: const Key('tile_b'),
                value: 'B',
                groupValue: selectedValue,
                icon: Icons.crop_landscape,
                tooltip: '選項 B',
                onSelected: (v) => setState(() => selectedValue = v),
              ),
            ],
          ),
        ),
      ),
    ));

    // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
    // （見 Task 1 Step 3 實作），不再用 find.descendant(...).first 這種
    // 依賴子樹結構的脆弱寫法（見 reviews/review-plan-issue-5-8.md Issue 6
    // Important #2）。
    final tileA = tester.widget<Container>(find.byKey(const Key('tile_a')));
    final boxDecorationA = tileA.decoration as BoxDecoration;
    expect(boxDecorationA.color, Colors.black);

    final tileB = tester.widget<Container>(find.byKey(const Key('tile_b')));
    final boxDecorationB = tileB.decoration as BoxDecoration;
    expect(boxDecorationB.color, Colors.white);

    // 點擊切換至 B
    await tester.tap(find.byKey(const Key('tile_b')));
    await tester.pumpAndSettle();

    expect(selectedValue, 'B');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/widgets/reader_option_tile_test.dart`
預期：FAIL（找不到 `reader_option_tile.dart`）。

- [ ] **Step 3: Write minimal implementation**

建立 `app/lib/screens/widgets/reader_option_tile.dart`：

```dart
import 'package:flutter/material.dart';

/// 專為閱讀器設定面板設計的高對比選項單選元件（支援 E-Ink 黑白反轉）。
class ReaderOptionTile<T> extends StatelessWidget {
  final Key? itemKey;
  final T value;
  final T groupValue;
  final IconData icon;
  final String? label;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;

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
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final theme = Theme.of(context);
    final isEink = theme.colorScheme.primary == Colors.black &&
        theme.scaffoldBackgroundColor == Colors.white;

    final Color backgroundColor;
    final Color foregroundColor;
    final Border border;

    if (isEink) {
      backgroundColor = selected ? Colors.black : Colors.white;
      foregroundColor = selected ? Colors.white : Colors.black;
      border = Border.all(color: Colors.black, width: 1.5);
    } else {
      backgroundColor = selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface;
      foregroundColor = selected
          ? theme.colorScheme.onPrimaryContainer
          : theme.colorScheme.onSurfaceVariant;
      border = Border.all(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outline.withValues(alpha: 0.35),
        width: selected ? 1.5 : 1.0,
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: foregroundColor),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(
            label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: foregroundColor,
            ),
          ),
        ],
      ],
    );

    // 【審查修正 Important】key 掛在帶 BoxDecoration 的 Container 上（而非
    // InkWell）：tester.tap(find.byKey(...)) 對 Container 一樣有效（觸控
    // 事件依 hit-test 順序傳給祖先鏈上的 InkWell），但測試斷言外觀時可以
    // 直接 tester.widget<Container>(find.byKey(...)) 精確取得，不需要
    // find.descendant(...).first 這種依賴「子樹第幾個 Container」的脆弱
    // 寫法（見 reviews/review-plan-issue-5-8.md Issue 6 Important #2）。
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            key: itemKey,
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 10 : 8,
              vertical: visualDensity == VisualDensity.compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/screens/widgets/reader_option_tile_test.dart`
預期：PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/widgets/reader_option_tile.dart app/test/screens/widgets/reader_option_tile_test.dart
git commit -m "feat(epic-27): Issue 6——新增共用高對比選項元件 ReaderOptionTile"
```

---

### Task 2: 改造 `PdfSettingsSheet` 圖示選項

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `ReaderOptionTile<T>`
- Produces: 替換 Fit 模式、雙頁模式、頁面方向、換頁動畫、裁切模式為 `ReaderOptionTile`

- [ ] **Step 1: Write the failing test**

在 `app/test/screens/pdf_settings_sheet_test.dart` 中追加測試（【審查修正 Important】既有檔案第 1-11 行目前**沒有**匯入 `package:elinkbook/theme/app_theme_data.dart`，須新增這行 import，否則 `buildEinkThemeData` 找不到符號、編譯失敗）：

```dart
// 新增 import（既有檔案尚未匯入）：
import 'package:elinkbook/theme/app_theme_data.dart';

testWidgets('PdfSettingsSheet 在 E-Ink 模式下選中項目呈現高對比底色', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildEinkThemeData(),
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
        onChanged: (_) {},
        onRequestManualCrop: () {},
      ),
    ),
  ));

  // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
  // （見 Task 1 ReaderOptionTile 實作），不再用
  // find.descendant(...).first 這種依賴子樹結構的脆弱寫法。
  expect(find.byKey(const Key('pdf_settings_fit_mode_fit_width')), findsOneWidget);
  final container = tester.widget<Container>(
    find.byKey(const Key('pdf_settings_fit_mode_fit_width')),
  );
  expect((container.decoration as BoxDecoration).color, Colors.black);
});
```

- [ ] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/pdf_settings_sheet_test.dart --plain-name "PdfSettingsSheet 在 E-Ink 模式下選中項目呈現高對比底色"`
預期：FAIL。

- [ ] **Step 3: Write minimal implementation**

在 `app/lib/screens/pdf_settings_sheet.dart` 中：
1. Import `widgets/reader_option_tile.dart`。
2. 將 `fitOptions`、`dualPageOptions`、`directionOptions`、`pageTurnAnimationOptions`、`cropMode options` 中的 `IconButton` 改用 `ReaderOptionTile`，並保留既有的 `Key` 與 `tooltip`。
3. 手動選區裁切按鈕（`pdf_settings_crop_mode_manual`，`pdf_settings_sheet.dart:386-391`）亦改為高對比外框按鈕。【審查修正 Minor：釐清模糊地帶，見 `reviews/review-plan-issue-5-8.md` Issue 6 Minor #4】現有程式碼中這顆按鈕完全沒有「選中」語意（點擊只呼叫 `widget.onRequestManualCrop` 進入互動裁切模式，不會設定 `_cropMode` 或呼叫 `_notifyChanged()`，即使 `_cropMode == PdfCropMode.manual` 也不反映選中樣式）——維持這個既有行為不變，本 Task 只需把它從 `IconButton` 換成 `ReaderOptionTile` 的「未選中」樣式（`value`／`groupValue` 傳入兩個恆不相等的值，例如 `value: true, groupValue: false`，確保視覺上恆為未選中狀態，不需要新增選中語意），不要自行擴充成會反映 `_cropMode` 的單選項目。

- [ ] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
預期：全數 PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-27): Issue 6——PdfSettingsSheet 圖示選項全面升級為 ReaderOptionTile"
```

---

### Task 3: 改造 `ReaderSettingsSheet` 與 `FxlSettingsSheet` 圖示選項

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Modify: `app/lib/screens/fxl_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`
- Test: `app/test/screens/fxl_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `ReaderOptionTile<T>`
- Produces: 替換文字對齊、排版方向、翻頁模式、螢幕旋轉鎖定、分欄、FXL 雙頁與方向選項

- [x] **Step 1: Write the failing test**

在 `app/test/screens/reader_settings_sheet_test.dart` 中追加測試（【審查修正 Important】既有檔案第 1-11 行目前**沒有**匯入 `package:elinkbook/theme/app_theme_data.dart`，須新增這行 import，否則 `buildEinkThemeData` 找不到符號、編譯失敗）：

```dart
// 新增 import（既有檔案尚未匯入）：
import 'package:elinkbook/theme/app_theme_data.dart';

testWidgets('ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildEinkThemeData(),
    home: Scaffold(
      body: ReaderSettingsSheet(
        bookId: 'test-book',
        prefs: const BookReaderPrefs(textAlign: EpubTextAlign.justify),
        onChanged: (_) {},
        onSaveAsPreset: (_) {},
        onApplyPreset: (_, {required targetBookIds}) {},
        onApplyFromBook: (_, {required targetBookIds}) {},
        onRequestBookPicker: ({required multiSelect}) async => null,
        onDeletePreset: (_) {},
      ),
    ),
  ));

  // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
  // （見 Task 1 ReaderOptionTile 實作），不再用
  // find.descendant(...).first 這種依賴子樹結構的脆弱寫法。
  final justifyTile = find.byKey(const Key('reader_settings_text_align_justify'));
  expect(justifyTile, findsOneWidget);
  final container = tester.widget<Container>(justifyTile);
  expect((container.decoration as BoxDecoration).color, Colors.black);
});
```

- [x] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart --plain-name "ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下"`
預期：FAIL。

- [x] **Step 3: Write minimal implementation**

在 `app/lib/screens/reader_settings_sheet.dart` 與 `app/lib/screens/fxl_settings_sheet.dart` 中：
1. Import `widgets/reader_option_tile.dart`。
2. 將文字對齊（`reader_settings_text_align_*`）、排版方向（`reader_settings_writing_mode_*`）、翻頁模式（`reader_settings_page_turn_mode_*`）、螢幕旋轉（`reader_settings_screen_orientation_*`）、分欄模式（`reader_settings_column_mode_*`）及 FXL 設定中的 `IconButton` 替換為 `ReaderOptionTile`。

- [x] **Step 4: Run test to verify it passes**

執行：
`cd app && flutter test test/screens/reader_settings_sheet_test.dart`
`cd app && flutter test test/screens/fxl_settings_sheet_test.dart`
預期：全數 PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/screens/fxl_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/fxl_settings_sheet_test.dart
git commit -m "feat(epic-27): Issue 6——ReaderSettingsSheet 與 FxlSettingsSheet 圖示選項升級為 ReaderOptionTile"
```
