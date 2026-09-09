# Epic 39 Issue 6：`FxlSettingsSheet` 視覺風格對齊 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `FxlSettingsSheet`（EPUB 固定版面/漫畫專屬的精簡版設定面板）在介面契約與視覺風格上對齊 Issue 2-5 已完成的 `ReaderSettingsSheet`／`PdfSettingsSheet`：新增 `isEinkMode` 建構參數、兩組單選群組改用 `EBOptionChipGroup`，並確認既有三顆 `SwitchListTile` 本就正確跟隨主題色。

**Architecture:** `FxlSettingsSheet` 是三個版面設定 Bottom Sheet 中內容最單純的一個（無分頁、無 Slider/Stepper、無覆寫徽章語意），本 Issue 只做純介面/視覺對齊，不新增任何渲染分支或業務邏輯。沿用 Issue 5 對 `PdfSettingsSheet` 的相同轉換模式：`Wrap` 包 `ReaderOptionTile` → `EBOptionChipGroup`（內部一樣是 `ReaderOptionTile`，既有的選中態/E-Ink 高對比背景色斷言測試零改動即可通過）。`isEinkMode` 目前不影響任何渲染分支——加入它純粹是為了讓 `ReaderScreen` 呼叫三個設定面板時能統一傳入同一個欄位（`spec.md`「ReaderScreen」段落）。

**Tech Stack:** Flutter/Dart、`flutter_test`、既有 `EBOptionChipGroup`／`EBOptionChipItem`（`app/lib/screens/widgets/eb_option_chip_group.dart`，Issue 1 建立）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`「`FxlSettingsSheet`」段落（第 119-123 行）＋「選項標籤對照表」（第 129-142 行，PDF/FXL 共用同一組標籤）＋「卡片邊框視覺規範」（第 144-149 行）；`docs/epics/epic-39-layout-settings-redesign/issues.md` Issue 6（第 54-64 行）。

## Global Constraints

- **`isEinkMode` 為 `required` 建構參數**，不是可選欄位（比照 Issue 4／Issue 5 對 `ReaderSettingsSheet`／`PdfSettingsSheet` 的既有做法），即使目前它「暫不影響任何渲染分支」（spec.md 原文）。
- **選項標籤（≤2 字）逐字比照 spec.md 對照表**：雙頁模式 auto/always/never → `自動`／`雙頁`／`單頁`；翻頁方向 ltr/rtl → `左翻`／`右翻`（PDF/FXL 共用同一組標籤定義，`PdfSettingsSheet` 已在 Issue 5 用完全相同字串）。
- **`FxlSettingsSheet` 不與 `ReaderSettingsSheet`／`PdfSettingsSheet` 共用私有邏輯**（沿用 `docs/epics/epic-16-dual-page/design.md` 決策 #10），本 Issue 只共用兩個通用元件：`EBOptionChipGroup`／`EBOptionChipItem`（Issue 1 建立，`PdfSettingsSheet` 已在 Issue 5 使用相同元件，非新增共用面）。
- **顏色一律讀 `Theme.of(context).colorScheme`，不得新增任何 `Colors.xxx` 字面值**（`CLAUDE.md`「版面與排版」段落）；`EBOptionChipGroup` 內部的 `ReaderOptionTile` 已完整處理一般主題／E-Ink 模式兩套配色與卡片邊框規範（`colorScheme.outline.withValues(alpha: 0.35)`／`1.0dp`／`BorderRadius.circular(8)` vs. E-Ink 純黑 `1.5dp`），本 Issue 不需重新實作。
- **三顆 `SwitchListTile`（全螢幕模式／顯示頁首／顯示頁尾）不需要程式碼變更**：spec.md 原文明確標註「跟隨 `Theme.of(context)`，非新邏輯」——三者目前皆未設定 `activeColor`/`inactiveThumbColor` 等顯式顏色，已由全域 `SwitchThemeData`（`app/lib/theme/app_theme_data.dart:52-66` 的 `_buildSwitchTheme()`，四套主題含 E-Ink 皆已套用）自動決定配色，`ReaderSettingsSheet`／`PdfSettingsSheet` 的既有 `SwitchListTile` 也是同樣寫法（零顯式顏色）。Task 3 只需確認、不需 TDD 紅綠循環。
- **`app/lib/screens/library_screen.dart` 也直接使用 `ReaderOptionTile`**（`WritingMode?`/`PageTurnMode?` 快速設定選單，第 1761-1808 行），與本 Issue 無關，不在範圍內，不得誤觸。
- **測試執行範圍**：單一 Task 完成後只跑 `flutter test test/screens/fxl_settings_sheet_test.dart`；完整 `flutter test`（無參數）＋ `flutter analyze` 只在 Task 3（本計畫最後一個 Task，同時也是 Issue 收尾）執行一次（`CLAUDE.md`「測試執行範圍」政策）。

---

### Task 1：新增 `isEinkMode` 建構參數＋呼叫端串接

**Files:**
- Modify: `app/lib/screens/fxl_settings_sheet.dart:8-21`（class doc comment、欄位、建構子）
- Modify: `app/lib/screens/reader_screen.dart:848-855`（`_openFxlSettings()`）
- Test: `app/test/screens/fxl_settings_sheet_test.dart`（14 處 `FxlSettingsSheet(` 建構呼叫點：第 18、36、54、90、113、143、164、186、206、226、243、259、294、323 行）

**Interfaces:**
- Consumes: 無（本 Task 不依賴其他 Task）
- Produces: `FxlSettingsSheet` 建構子新增 `required bool isEinkMode` 欄位／`widget.isEinkMode`，供 Task 2 若需要時使用（目前 Task 2 的 `EBOptionChipGroup` 轉換不依賴這個欄位，兩者是獨立變更）。

- [x] **Step 1：修改 `FxlSettingsSheet` 建構子，新增必要參數 `isEinkMode`**

修改 `app/lib/screens/fxl_settings_sheet.dart` 第 8-21 行：

```dart
/// EPUB 固定版面（FXL 漫畫）專屬的精簡版設定 Bottom Sheet（見
/// docs/epics/epic-16-dual-page/spec.md「模組」段落）：提供「雙頁模式」
/// 三態切換與「全螢幕模式」開關（epic-19-shelf-reading-enhance Issue 1），
/// 不與 PdfSettingsSheet／ReaderSettingsSheet 共用元件（固定版面沒有
/// 字型/裁切/濾鏡等其餘設定）。[isEinkMode] 目前不影響任何渲染分支（本
/// 畫面沒有數值型 Slider/EBStepper 需要二選一切換），僅為呼叫端三個
/// 版面設定面板統一介面而保留（見 epic-39-layout-settings-redesign
/// spec.md「FxlSettingsSheet」段落）。
class FxlSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final bool isEinkMode;

  const FxlSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.isEinkMode,
  });
```

此時专案無法通過編譯（`reader_screen.dart` 與整個測試檔案都少了必要引數），這是預期中的「紅燈」狀態，下一步先確認錯誤訊息正確，再逐一修正呼叫點。

- [x] **Step 2：執行測試，確認因缺少必要引數而編譯失敗**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: FAIL（編譯錯誤，`analyzer` 回報多處 `The named parameter 'isEinkMode' is required, but there's no corresponding argument` ── 至少涵蓋 `fxl_settings_sheet_test.dart` 全部 14 處建構呼叫點與 `reader_screen.dart` 的 `_openFxlSettings()`）

- [x] **Step 3：修正 `ReaderScreen._openFxlSettings()` 呼叫點**

修改 `app/lib/screens/reader_screen.dart` 第 848-855 行：

```dart
  void _openFxlSettings() {
    _showThemedModalBottomSheet<void>(
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        isEinkMode: widget.isEinkMode,
      ),
    );
  }
```

- [x] **Step 4：修正 `fxl_settings_sheet_test.dart` 全部 14 處建構呼叫點**

第 18、36、54、90、113、143、164、186、206、226、243、259、323 行（共 13 處，皆為一般情境測試）在既有 `onChanged:` 引數後補上一行：

```dart
            isEinkMode: false,
```

第 294 行（唯一使用 `buildEinkThemeData()` 的 E-Ink 情境測試）補上：

```dart
          isEinkMode: true,
```

（縮排依各處既有引數對齊；`isEinkMode` 目前雖不影響渲染分支，仍應與情境語意一致，避免將來有人依字面值誤判測試情境。）

- [x] **Step 5：執行測試，確認全數通過**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: PASS（原有 14 個測試全數通過，無新增/刪除測試案例）

- [x] **Step 6：執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7：勾選 Task 1 全部 Step 為完成，並 Commit**

將本檔案 Task 1 的 Step 1-7 全部 `- [ ]` 改為 `- [x]`（**審查修正 M2**：依 SDD 慣例逐 Task 漸進勾選，不留到 Task 3 才一次補齊）。

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/lib/screens/reader_screen.dart app/test/screens/fxl_settings_sheet_test.dart docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-6.md
git commit -m "feat(epic-39): Issue 6 Task 1 — FxlSettingsSheet 新增 isEinkMode 建構參數"
```

---

### Task 2：兩組單選群組改用 `EBOptionChipGroup`

**Files:**
- Modify: `app/lib/screens/fxl_settings_sheet.dart:1-6`（import）、`54-158`（`build()` 方法整體；此為 Task 1 執行**前**的行號——Task 1 在 class doc comment／欄位／建構子新增約 6-7 行後，`build()` 起始行會順延，請以 `@override` `Widget build(BuildContext context) {` 這行實際所在位置為準，不要死板套用行號）
- Test: `app/test/screens/fxl_settings_sheet_test.dart`（新增 2 個 `testWidgets`）

**Interfaces:**
- Consumes: `EBOptionChipGroup<T>`／`EBOptionChipItem<T>`（`app/lib/screens/widgets/eb_option_chip_group.dart`）——建構參數 `items: List<EBOptionChipItem<T>>`、`groupValue: T`、`onSelected: ValueChanged<T>`、`visualDensity: VisualDensity`；`EBOptionChipItem<T>` 建構參數 `itemKey`／`value`／`icon`／`label`／`tooltip`。
- Produces: 無（本 Task 為 Issue 6 最後一項介面異動；Task 3 不依賴本 Task 的產出型別）。

- [ ] **Step 1：撰寫兩個失敗測試，鎖定新標籤文字**

在 `app/test/screens/fxl_settings_sheet_test.dart` 檔案結尾（`_pumpModalSheet` 函式定義之前，即目前第 309 行之前）新增：

```dart
  testWidgets(
      '雙頁模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤'
      '對照表定義的短標籤（epic-39-layout-settings-redesign Issue 6）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
        ),
      ),
    ));

    for (final item in [
      ('auto', '自動'),
      ('always', '雙頁'),
      ('never', '單頁'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('fxl_settings_dual_page_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'fxl_settings_dual_page_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '翻頁方向群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 6）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
        ),
      ),
    ));

    for (final item in [
      ('ltr', '左翻'),
      ('rtl', '右翻'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('fxl_settings_direction_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'fxl_settings_direction_$suffix 應顯示標籤「$label」',
      );
    }
  });
```

- [ ] **Step 2：執行測試，確認新測試失敗**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: 新增的 2 個測試 FAIL（`find.text('自動')` 等找不到任何 widget——目前 `ReaderOptionTile` 呼叫皆未傳入 `label`，只有圖示無文字）；其餘 14 個既有測試維持 PASS。

- [ ] **Step 3：`build()` 內兩組 `Wrap`＋`ReaderOptionTile` 改為 `EBOptionChipGroup`**

> **【審查修正 I1，見 `reviews/review-plan-issue-6.md`】** 下方替換目標是**整個 `build()` 方法**（從 `@override` `Widget build(BuildContext context) {` 開頭，到方法本身的閉合右大括號 `}` 為止，含未變動的三顆 `SwitchListTile`），不是行號區間「56-125」這種局部片段——若用行號區間指定的自動化編輯（例如只指定 `StartLine/EndLine`）去套用下方程式碼，會讓原檔案尾端的三顆 `SwitchListTile` 殘留一份、造成重複 Key 與編譯錯誤。且 Task 1 已在檔案開頭新增約 6-7 行 docstring／欄位，`build()` 實際起始行號已順延，請直接搜尋 `Widget build(BuildContext context) {` 字串定位，不要依賴任何寫死的行號。

修改 `app/lib/screens/fxl_settings_sheet.dart` 第 1-6 行的 import：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_direction.dart';
import '../reader/dual_page_mode.dart';
import 'widgets/eb_option_chip_group.dart';
```

（移除 `import 'widgets/reader_option_tile.dart';`——`EBOptionChipGroup` 內部已引用它，`FxlSettingsSheet` 本身改用後不再直接依賴。）

修改 `build()` 方法整體（原檔第 54-158 行，Task 1 後行號順延，見上方提示）：

```dart
  @override
  Widget build(BuildContext context) {
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）', '自動'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁', '雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁', '單頁'),
    ];
    const directionOptions = [
      (DualPageDirection.ltr, 'ltr', Icons.arrow_forward, '左到右（LTR，美漫慣例）', '左翻'),
      (DualPageDirection.rtl, 'rtl', Icons.arrow_back, '右到左（RTL，日漫慣例）', '右翻'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('⚙️ 漫畫版面設定',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  key: const Key('fxl_settings_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('雙頁模式'),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageMode>(
              items: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageMode>(
                  itemKey: Key('fxl_settings_dual_page_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageMode,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _dualPageMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('翻頁方向'),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageDirection>(
              items: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageDirection>(
                  itemKey: Key('fxl_settings_direction_$keySuffix'),
                  value: direction,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageDirection,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _dualPageDirection = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('fxl_settings_fullscreen'),
              title: const Text('全螢幕模式'),
              value: _fullscreen,
              onChanged: (v) => setState(() {
                _fullscreen = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('fxl_settings_show_header'),
              title: const Text('顯示頁首'),
              value: _showHeader,
              onChanged: (v) => setState(() {
                _showHeader = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('fxl_settings_show_footer'),
              title: const Text('顯示頁尾'),
              value: _showFooter,
              onChanged: (v) => setState(() {
                _showFooter = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }
```

（三顆 `SwitchListTile` 原樣保留，不屬於本 Step 異動範圍，列出完整 `build()` 方法只是為了讓實作者能直接整段替換、避免手動拼接時漏改前後邊界。）

- [ ] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: PASS（14 個既有測試 + 2 個新測試，共 16 個全數通過）。既有的選中態／E-Ink 高對比背景色斷言測試（第 50-84、256-287、290-307 行）之所以零改動就能通過，是因為 `EBOptionChipGroup` 內部仍是 `ReaderOptionTile`，`key: itemKey` 一樣掛在帶 `BoxDecoration` 的 `Container` 上（`eb_option_chip_group.dart:79-97`）。

- [ ] **Step 5：執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：勾選 Task 2 全部 Step 為完成，並 Commit**

將本檔案 Task 2 的 Step 1-6 全部 `- [ ]` 改為 `- [x]`（**審查修正 M2**：依 SDD 慣例逐 Task 漸進勾選）。

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/test/screens/fxl_settings_sheet_test.dart docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-6.md
git commit -m "feat(epic-39): Issue 6 Task 2 — 雙頁模式／翻頁方向改用 EBOptionChipGroup"
```

---

### Task 3：`SwitchListTile` 視覺確認＋收尾（全套測試＋分析）

**Files:**
- 無程式碼異動（本 Task 為確認性質，見下方 Step 1 說明）
- Modify: `docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-6.md`（全部 Step 勾選為完成）

**Interfaces:**
- Consumes: Task 1／Task 2 的最終程式碼狀態
- Produces: 無（Issue 6 為 Epic 39 最後一個 Issue，無下游 Task 依賴本 Task 產出）

- [ ] **Step 1：確認三顆 `SwitchListTile` 未設定任何顯式顏色**

Run: `git grep -n -E "activeColor|inactiveThumbColor|inactiveTrackColor|activeTrackColor|thumbColor|trackColor" app/lib/screens/fxl_settings_sheet.dart`

（**審查修正 M1**：改用 `git grep` 而非裸 `grep`——Windows 環境未必有原生 `grep` 可執行檔，`git grep` 在 Bash／PowerShell 兩種終端機皆可直接執行。）
Expected: 無任何輸出（`fxl_settings_fullscreen`／`fxl_settings_show_header`／`fxl_settings_show_footer` 三顆 `SwitchListTile` 皆未設定顯式顏色引數，因此已由全域 `SwitchThemeData`——`app/lib/theme/app_theme_data.dart:52-66` 的 `_buildSwitchTheme()`，四套主題含 E-Ink 皆已套用——自動決定配色）。

此結果確認 spec.md「`FxlSettingsSheet`」段落第三點「三顆 `SwitchListTile` 視覺風格調整（跟隨 `Theme.of(context)`，非新邏輯）」的要求已經滿足，不需要修改 `fxl_settings_sheet.dart` 本身；`app/test/screens/fxl_settings_sheet_test.dart` 現有的三個 `SwitchListTile` 相關測試（第 86-105、139-158、160-179 行，斷言 `.value` 反映持久化狀態）與四個 `onChanged` 行為測試（第 107-126、181-199、201-219 行）已涵蓋 issues.md 要求的「既有 `onChanged` 行為零回歸」，不需新增測試。

- [ ] **Step 2：勾選 Task 3 本身的 Step 為完成，並確認全文已無遺漏**

將本檔案 Task 3 的 Step 1-5 改為 `- [x]`（**審查修正 M2**：Task 1／Task 2 的 Step 已分別在各自 Step 7／Step 6 隨 commit 勾選完成，此處只需勾選 Task 3 本身，並巡覽全文確認沒有任何 Task 1-3 的 Step 遺漏勾選）。

- [ ] **Step 3：執行完整測試套件**

Run: `flutter test`
Expected: 全數通過（含本 Issue 新增的 2 個測試），無回歸。此為本計畫最後一個 Task，依 `CLAUDE.md`「測試執行範圍」政策於此執行一次完整套件。

- [ ] **Step 4：執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-6.md
git commit -m "docs(epic-39): Issue 6 計畫執行完成，全部 Step 標記完成"
```

---

## Self-Review（撰寫計畫者自行檢查，非審查報告）

**Spec 覆蓋度：**
- `isEinkMode` 必要建構參數 → Task 1 ✅
- 雙頁模式／翻頁方向改用 `EBOptionChipGroup`＋短標籤 → Task 2 ✅
- `SwitchListTile` 視覺風格（跟隨主題、非新邏輯）→ Task 3 Step 1 確認 ✅
- `ReaderScreen` 呼叫端新增 `isEinkMode: widget.isEinkMode` → Task 1 Step 3 ✅
- 卡片邊框視覺規範（一般/E-Ink）→ 由 `ReaderOptionTile` 既有實作滿足，`EBOptionChipGroup` 只是包裝，已在 Global Constraints 說明，無需獨立 Task ✅
- Issue 收尾（完整 `flutter test` + `flutter analyze`）→ Task 3 Step 3-4 ✅

**佔位符掃描：** 全文檢查過，無 TBD／"add appropriate"／"similar to Task N" 等禁止用語，所有程式碼步驟皆附完整可執行程式碼。

**型別一致性：** `EBOptionChipItem<DualPageMode>`／`EBOptionChipItem<DualPageDirection>` 的欄位名稱（`itemKey`／`value`／`icon`／`label`／`tooltip`）與 `EBOptionChipGroup`（`items`／`groupValue`／`onSelected`／`visualDensity`）皆逐字核對 `app/lib/screens/widgets/eb_option_chip_group.dart` 現有定義，並與 `PdfSettingsSheet`（Issue 5，`app/lib/screens/pdf_settings_sheet.dart:190-224`）已驗證可用的呼叫寫法保持一致。
