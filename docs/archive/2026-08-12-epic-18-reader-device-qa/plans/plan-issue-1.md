# Epic 18 Issue 1 — 版面設定 Bottom Sheet 加入明確關閉按鈕 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `ReaderSettingsSheet`／`PdfSettingsSheet` 這兩個以 `showModalBottomSheet(isScrollControlled: true, enableDrag: false)` 開啟、內容可能撐滿整個小螢幕視窗的 Bottom Sheet，都新增一個固定式關閉列（標題＋`X` 關閉鈕），確保使用者在任何螢幕尺寸下都能點擊退出；同時確認 `FxlSettingsSheet` 是否有相同缺口（結論：沒有，見 Task 1）。

**Architecture:** `ReaderSettingsSheet.build()` 目前是 `SafeArea(child: ListView(shrinkWrap: true, ...))`，改為 `SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [固定關閉列, Flexible(child: ListView(shrinkWrap: true, ...))]))`——`mainAxisSize: MainAxisSize.min` 是關鍵，`showModalBottomSheet(isScrollControlled: true)` 給子項的是 loose constraints（`minHeight: 0`），若沿用 `Column` 預設的 `MainAxisSize.max` 會讓 Sheet 一律撐滿到可用高度上限（即使內容很短），與是否使用 `Expanded` 無關；加上 `mainAxisSize: MainAxisSize.min` 後，`Flexible`（非 `Expanded`）搭配 `shrinkWrap: true` 的 `ListView` 才能在「內容小於螢幕高度時保持緊湊」與「內容大於螢幕高度時限制最大高度、允許內部捲動且關閉列不隨之捲動」兩種情境下都正確。`PdfSettingsSheet.build()` 是固定 `SizedBox(height: 400)` 包裹 `Column`（無 loose-constraints 撐滿風險），只需要在既有標題 `Padding` 內把 `Text` 換成 `Row(Expanded(Text) + IconButton)`，不需要引入 `mainAxisSize`/`Flexible` 這套機制。`FxlSettingsSheet` 經 Task 1 調查後判定不需要修改（原因見 Task 1）。

**Tech Stack:** Flutter/Dart（`app/lib/screens/*.dart` widget 層），`flutter_test`（widget test，本 Issue 全數變更皆可用 `flutter test` 驗證，不需要 `integration_test`），驗收另需真機/模擬螢幕尺寸人工確認（`adb shell wm size`/`wm density`，見 Task 4）。

## Global Constraints

- **所有指令皆在 `app/` 目錄下執行**（`cd "U:/MyDeveloper/AI/elinkBook/app"`），使用 POSIX 相容 Bash（Git Bash），非 PowerShell。
- **`flutter analyze` 必須保持乾淨**（"No issues found!"）——每個 Task 完成程式碼異動後都要跑一次。
- **三個 Bottom Sheet 的既有開啟參數不同，這是判斷是否需要修正的關鍵依據**（`app/lib/screens/reader_screen.dart:516-553`）：
  - `_openLayoutSettings()`（開 `ReaderSettingsSheet`）：`isScrollControlled: true, enableDrag: false` → **有缺口**（Task 2）。
  - `_openPdfSettings()`（開 `PdfSettingsSheet`）：`isScrollControlled: true, enableDrag: false` → **有缺口**（Task 3）。
  - `_openFxlSettings()`（開 `FxlSettingsSheet`）：只有 `isScrollControlled: true`，**未設 `enableDrag: false`**（預設 `true`，使用者仍可下滑關閉）→ 經 Task 1 調查判定**無缺口，本 Issue 不修改** `fxl_settings_sheet.dart`。
  - 本 Issue **不修改** `reader_screen.dart`——三個 `_open*Settings()` 方法呼叫 `showModalBottomSheet` 的參數皆維持原樣；`Navigator.of(context).pop()` 由 Sheet 自己的 `BuildContext`（即 `builder: (_) => ...` 的 `_` 參數所在的 context 樹）觸發，該 context 本來就位於 `showModalBottomSheet` 建立的路由之下，不需要呼叫端配合改動。
- **Key 命名慣例**：延續各檔案既有前綴——`reader_settings_*`（`ReaderSettingsSheet`）、`pdf_settings_*`（`PdfSettingsSheet`）。新關閉按鈕分別命名為 `Key('reader_settings_close_button')`（issues.md 原文指定）、`Key('pdf_settings_close_button')`（比照前綴慣例新增）。
- **不變更任何既有 Key／既有測試斷言的既有行為**——本 Issue 只新增關閉列與對應測試，兩個檔案原有的所有滑桿/開關/分頁互動邏輯與 Key 一律不動。
- **測試裝置**：真機 `3CEF42ECD491687`（9491G，Android 15/API 35）；驗收另需比對三種螢幕尺寸/密度：824×1648／150 PPI（使用者回報環境 AiPaper Reader C）、1404×1872／300 PPI（黑白）、702×936／150 PPI（彩色）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/screens/reader_settings_sheet.dart` | 修改（`build()`，現行 133-248 行） | 加入固定式關閉列，`ListView` 改為 `Column(mainAxisSize.min) > [關閉列, Flexible(ListView(shrinkWrap))]` |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改（新增測試，附加在既有 `main()` 最後一個 `testWidgets` 之後） | 關閉按鈕存在／可點擊關閉、內容溢出時關閉列位置不變、內容較短時 Sheet 不撐滿版面（回歸 `mainAxisSize.min`） |
| `app/lib/screens/pdf_settings_sheet.dart` | 修改（`build()`，現行 90-127 行） | 標題列加入相同的固定式關閉按鈕 |
| `app/test/screens/pdf_settings_sheet_test.dart` | 修改（新增測試，附加在既有 `main()` 最後一個 `testWidgets` 之後） | 關閉按鈕存在／可點擊關閉 |
| `app/lib/screens/fxl_settings_sheet.dart` | 修改（**計畫外追加，事後經人類確認接受**，見 Task 1 結論下方「事後決策」；`build()` 標題列加入相同的固定式關閉按鈕） | 與 `ReaderSettingsSheet`／`PdfSettingsSheet` 統一 UI 樣式，非修補實際缺陷 |
| `app/test/screens/fxl_settings_sheet_test.dart` | 修改（計畫外追加，新增關閉按鈕存在／可點擊關閉測試） | 鎖定 `Key('fxl_settings_close_button')` 行為 |

---

### Task 1：調查 `PdfSettingsSheet`／`FxlSettingsSheet` 是否有相同缺口

**Files:** 無程式碼異動（純調查，供 Task 2/3 決定修改範圍）

**Interfaces:**
- Consumes：無
- Produces：本 Issue 後續 Task 的範圍依據（確認 Task 2/3 該改哪些檔案、Task 1 本身不產生任何介面）

- [x] **Step 1：確認三個 Bottom Sheet 的開啟參數**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -n "showModalBottomSheet\|_openLayoutSettings\|_openPdfSettings\|_openFxlSettings\|enableDrag" lib/screens/reader_screen.dart
```

Expected：看到三段 `showModalBottomSheet<void>(...)` 呼叫——`_openLayoutSettings()`（開 `ReaderSettingsSheet`）與 `_openPdfSettings()`（開 `PdfSettingsSheet`）皆帶 `isScrollControlled: true, enableDrag: false`；`_openFxlSettings()`（開 `FxlSettingsSheet`）只帶 `isScrollControlled: true`，沒有 `enableDrag` 這一行（代表沿用 Flutter 預設值 `enableDrag: true`，使用者仍可用下滑手勢關閉）。

- [x] **Step 2：確認 `FxlSettingsSheet` 本身的版面結構是否已經緊湊包裹**

```bash
grep -n "mainAxisSize\|ListView\|Expanded\|SizedBox" lib/screens/fxl_settings_sheet.dart
```

Expected：只看到一行 `mainAxisSize: MainAxisSize.min`（在 `build()` 內的 `Column` 上），沒有 `ListView`／`Expanded`——代表 `FxlSettingsSheet` 的內容（標題 + 單一「雙頁模式」三選一列）本來就用 `Column(mainAxisSize: MainAxisSize.min)` 緊湊包裹，不會受 loose constraints 撐滿版面（這正是 `issues.md` 審查修訂紀錄裡提到「即使內容很短的 `FxlSettingsSheet`」的參照對象，但它已經有 `mainAxisSize: MainAxisSize.min`，不是本 Issue 要修的那個缺陷）。

- [x] **Step 3：記錄結論（本計劃即為書面紀錄，不需另立文件）**

結論：
- `ReaderSettingsSheet`（`enableDrag: false` + 無關閉按鈕 + `ListView(shrinkWrap)` 缺少 `mainAxisSize.min` 保護）→ **需要修正**，見 Task 2。
- `PdfSettingsSheet`（`enableDrag: false` + 無關閉按鈕，雖然固定 `height: 400` 不會撐滿版面，但同樣沒有可見的關閉手段）→ **需要修正**，見 Task 3。
- `FxlSettingsSheet`（`enableDrag` 預設 `true`，使用者仍可下滑關閉；內容本身已用 `mainAxisSize: MainAxisSize.min` 緊湊包裹，背景遮罩必然可見可點擊）→ **不具備 `issues.md` 描述的「背景遮罩完全不可見、無法關閉」缺陷，本 Issue 不修改 `fxl_settings_sheet.dart`**。

無需 commit（本 Task 未變更任何檔案）。

**【事後決策，經人類確認，見 `tmp/epic-18/reviews/review-issue-1.md` Important #1】** 實作階段（commit `182295d`）在上述結論之外，仍為 `FxlSettingsSheet` 加上了同款固定式關閉按鈕（`Key('fxl_settings_close_button')`，與另外兩個 Sheet 相同的 `Icons.close` + `Navigator.of(context).pop()` + `fromLTRB(16, 12, 8, ...)` padding 寫法，並附上對應的 `showModalBottomSheet` 關閉測試）。這是計畫範圍外的追加——Task 1 的調查結論本身沒有錯（`FxlSettingsSheet` 確實不具備「無法關閉」的缺陷），追加的理由是「三個版面設定 Sheet 的 UI 樣式統一」，非修補一個實際缺陷。經人類於程式碼審查後確認**接受**此追加，不需要回退 `182295d`；本節僅補記決策與理由，`fxl_settings_sheet.dart`／`fxl_settings_sheet_test.dart` 的實際程式碼與測試維持 commit `182295d` 現狀，不需要重新實作。

---

### Task 2：`ReaderSettingsSheet` 加入固定式關閉列

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:133-248`（`build()`）
- Test: `app/test/screens/reader_settings_sheet_test.dart`（新增測試 + 新增一個 modal 版本的 pump helper）

**Interfaces:**
- Consumes：`BookReaderPrefs`／`ValueChanged<BookReaderPrefs>`（既有建構參數，不變）
- Produces：新增 `Key('reader_settings_close_button')`（`IconButton`，`onPressed: () => Navigator.of(context).pop()`），供 Task 4 真機驗收時點擊

- [x] **Step 1：撰寫失敗測試——擴充 `reader_settings_sheet_test.dart`**

在 `app/test/screens/reader_settings_sheet_test.dart` 現有最後一個 `testWidgets` 區塊（`'切換頁首/頁尾開關不會清空其他既有覆寫欄位（回歸檢查）'`，結尾在第 454 行 `});`）之後、`main()` 的收尾 `}`（第 455 行）之前，插入以下三個測試：

```dart
  testWidgets('點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (tester) async {
    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_settings_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsNothing);
  });

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

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    expect(find.byKey(const Key('reader_settings_close_button')), findsOneWidget);
    final afterScroll = tester.getTopLeft(
      find.byKey(const Key('reader_settings_close_button')),
    );
    expect(afterScroll, beforeScroll,
        reason: '關閉列在 Column 頂端、ListView 之外，捲動內部 ListView 不應移動它的位置');
  });

  testWidgets('內容小於可用高度時，Bottom Sheet 保持緊湊包裹（不撐滿刻意放大的可用高度）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    final sheetHeight = tester.getSize(find.byType(ReaderSettingsSheet)).height;
    expect(sheetHeight, lessThan(2500),
        reason:
            'mainAxisSize.min 應讓內容較短時 Sheet 緊湊包裹，不應撐滿刻意放大的可用高度 3000');
  });
```

同時在檔案最底部（既有 `_pumpSheet`／`_noopOnChanged`／`_TestSettingsSheetWrapper` 之後）新增一個透過真實 `showModalBottomSheet` 開啟的 pump helper（前三個新測試都要用到，既有測試沿用既有的 `_pumpSheet` 不受影響）：

```dart
Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
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

- [x] **Step 2：執行測試，確認新增的三個測試皆失敗**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：新增的三個測試 FAIL——`find.byKey(const Key('reader_settings_close_button'))` 在目前的 `build()` 中找不到任何 widget（`findsOneWidget` 斷言失敗，因為 `reader_settings_sheet.dart` 目前完全沒有這個 Key）；既有測試維持 PASS。

- [x] **Step 3：修改 `reader_settings_sheet.dart` 的 `build()`**

把現行第 133-248 行的 `build()`：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('⚙️ 版面設定', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildFontFamilyDropdown(),
          _buildSliderRow(
            keyPrefix: 'reader_settings_font_size',
            label: '字型大小',
            value: _fontSize,
            min: 12,
            max: 40,
            step: 1,
            displayValue: _fontSize.round().toString(),
            onChanged: (v) => setState(() {
              _fontSize = v;
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
            onChanged: (v) => setState(() {
              _fontWeightMultiplier = v / 400;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_line_height',
            label: '行高',
            value: _lineHeight,
            min: 1.2,
            max: 2.5,
            step: 0.1,
            displayValue: _lineHeight.toStringAsFixed(1),
            onChanged: (v) => setState(() {
              _lineHeight = double.parse(v.toStringAsFixed(1));
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
            onChanged: (v) => setState(() {
              _paragraphSpacing = v;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_page_margins',
            label: '邊距',
            value: _pageMargins,
            min: 0,
            max: 50,
            step: 1,
            displayValue: _pageMargins.round().toString(),
            onChanged: (v) => setState(() {
              _pageMargins = v;
              _notifyChanged();
            }),
          ),
          const SizedBox(height: 12),
          _buildTextAlignRow(),
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

改為：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _buildFontFamilyDropdown(),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_font_size',
                  label: '字型大小',
                  value: _fontSize,
                  min: 12,
                  max: 40,
                  step: 1,
                  displayValue: _fontSize.round().toString(),
                  onChanged: (v) => setState(() {
                    _fontSize = v;
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
                  onChanged: (v) => setState(() {
                    _fontWeightMultiplier = v / 400;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_line_height',
                  label: '行高',
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.5,
                  step: 0.1,
                  displayValue: _lineHeight.toStringAsFixed(1),
                  onChanged: (v) => setState(() {
                    _lineHeight = double.parse(v.toStringAsFixed(1));
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
                  onChanged: (v) => setState(() {
                    _paragraphSpacing = v;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_page_margins',
                  label: '邊距',
                  value: _pageMargins,
                  min: 0,
                  max: 50,
                  step: 1,
                  displayValue: _pageMargins.round().toString(),
                  onChanged: (v) => setState(() {
                    _pageMargins = v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                _buildTextAlignRow(),
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
                _buildWritingModeOverrideRow(),
                const SizedBox(height: 12),
                _buildScreenOrientationOverrideRow(),
                const SizedBox(height: 12),
                _buildPageTurnModeOverrideRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

（只動 `build()` 本身，`_buildFontFamilyDropdown()`／`_buildSliderRow()`／`_buildTextAlignRow()`／`_buildWritingModeOverrideRow()`／`_buildScreenOrientationOverrideRow()`／`_buildPageTurnModeOverrideRow()` 這幾個既有 helper 方法簽章與內容完全不變。）

- [x] **Step 4：執行測試，確認全部通過**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：全部 PASS，包含 Step 1 新增的三個測試與既有全部測試。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "fix(epic-18): ReaderSettingsSheet 加入固定式關閉按鈕"
```

---

### Task 3：`PdfSettingsSheet` 加入相同的固定式關閉按鈕

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart:90-127`（`build()`）
- Test: `app/test/screens/pdf_settings_sheet_test.dart`（新增測試 + 新增一個 modal 版本的 pump helper）

**Interfaces:**
- Consumes：`BookReaderPrefs`／`ValueChanged<BookReaderPrefs>`／`VoidCallback onRequestManualCrop`（既有建構參數，不變）
- Produces：新增 `Key('pdf_settings_close_button')`（`IconButton`，`onPressed: () => Navigator.of(context).pop()`），供 Task 4 真機驗收時點擊

- [x] **Step 1：撰寫失敗測試——擴充 `pdf_settings_sheet_test.dart`**

在 `app/test/screens/pdf_settings_sheet_test.dart` 現有最後一個 `testWidgets` 區塊（`'已持久化 showFooter=false 時，調整雙頁模式不會清空該欄位（回歸檢查）'`，結尾在第 526 行 `});`）之後、`main()` 的收尾 `}`（第 527 行）之前，插入以下測試：

```dart
  testWidgets('點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (tester) async {
    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byType(PdfSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_settings_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfSettingsSheet), findsNothing);
  });
```

同時在檔案最底部（既有 `_pumpSheet`／`_noopVoid` 之後）新增一個透過真實 `showModalBottomSheet` 開啟的 pump helper：

```dart
Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
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

- [x] **Step 2：執行測試，確認新增測試失敗**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：新增的測試 FAIL——`find.byKey(const Key('pdf_settings_close_button'))` 找不到任何 widget；既有測試維持 PASS。

- [x] **Step 3：修改 `pdf_settings_sheet.dart` 的 `build()`**

把現行第 90-127 行的 `build()`：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        // TabBarView 無法在無邊界的父層自我量測高度（不同於 ReaderSettingsSheet
        // 用 ListView(shrinkWrap: true) 的做法），固定高度是本 widget 刻意的
        // 簡化選擇。
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('⚙️ PDF 版面設定',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(key: Key('pdf_settings_tab_display'), text: '顯示'),
                Tab(key: Key('pdf_settings_tab_filters'), text: '濾鏡'),
                Tab(key: Key('pdf_settings_tab_crop'), text: '裁切'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildCropTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        // TabBarView 無法在無邊界的父層自我量測高度（不同於 ReaderSettingsSheet
        // 用 ListView(shrinkWrap: true) 的做法），固定高度是本 widget 刻意的
        // 簡化選擇。
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('⚙️ PDF 版面設定',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    key: const Key('pdf_settings_close_button'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(key: Key('pdf_settings_tab_display'), text: '顯示'),
                Tab(key: Key('pdf_settings_tab_filters'), text: '濾鏡'),
                Tab(key: Key('pdf_settings_tab_crop'), text: '裁切'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildCropTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [x] **Step 4：執行測試，確認全部通過**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：全部 PASS，包含 Step 1 新增的測試與既有全部測試。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：全專案回歸測試**

```bash
flutter test
```

Expected：全數 PASS（含 Task 2、Task 3 新增/修改的所有測試，以及既有全部測試不受影響）。

- [x] **Step 7：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "fix(epic-18): PdfSettingsSheet 加入固定式關閉按鈕"
```

---

### Task 4：真機／模擬三種螢幕尺寸驗收

**Files:** 無程式碼異動（純驗收，`issues.md` Issue 1 驗收標準要求的真機確認）

**Interfaces:**
- Consumes：Task 2／Task 3 已 commit 的 `reader_settings_close_button`／`pdf_settings_close_button`
- Produces：驗收結論（記錄於本計劃 Step 3 的核對表，供人類決定是否合併）

- [x] **Step 1：建置並安裝 debug APK 到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
adb devices -l
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：`adb devices -l` 列出 `3CEF42ECD491687`；建置與安裝皆成功（`Success`）。

- [x] **Step 2：記錄裝置原生解析度/密度，供之後復原**

```bash
adb -s 3CEF42ECD491687 shell wm size
adb -s 3CEF42ECD491687 shell wm density
```

Expected：輸出目前的 `Physical size`／`Physical density`（記下數值，Step 4 三種尺寸驗證完後要復原成這組數值）。

- [x] **Step 3：依序覆蓋三種目標螢幕尺寸/密度，逐一開啟 EPUB「版面設定」與 PDF「版面設定」，確認關閉按鈕可見且可點擊退出**

對下列三組尺寸/密度逐一執行（每組都重複「覆蓋 → 開啟 App → 開一本流式 EPUB → 點右上角版面設定 → 確認可見 `X` 關閉鈕並點擊退出 → 開一本 PDF → 點版面設定 → 確認可見 `X` 關閉鈕並點擊退出」）：

```bash
# 824×1648／150 PPI（AiPaper Reader C 對應尺寸）
adb -s 3CEF42ECD491687 shell wm size 824x1648
adb -s 3CEF42ECD491687 shell wm density 150
adb -s 3CEF42ECD491687 shell am force-stop cc.ugotit.elinkbook
adb -s 3CEF42ECD491687 shell monkey -p cc.ugotit.elinkbook -c android.intent.category.LAUNCHER 1
```

Expected：App 正常啟動；書架 → 開啟範例 EPUB → 點擊版面設定按鈕（AppBar 上的齒輪圖示）→ `ReaderSettingsSheet` 顯示，畫面頂端可見「⚙️ 版面設定」標題列與右側 `X` 關閉鈕（`Key('reader_settings_close_button')` 對應的 `IconButton`）→ 點擊該 `X` → Bottom Sheet 關閉、回到閱讀畫面。接著開啟範例 PDF → 點擊版面設定按鈕 → `PdfSettingsSheet` 顯示，同樣可見標題列右側 `X` 關閉鈕（`Key('pdf_settings_close_button')`）→ 點擊後關閉。

重複同樣的步驟，改用另外兩組尺寸/密度：

```bash
# 1404×1872／300 PPI（黑白）
adb -s 3CEF42ECD491687 shell wm size 1404x1872
adb -s 3CEF42ECD491687 shell wm density 300
adb -s 3CEF42ECD491687 shell am force-stop cc.ugotit.elinkbook
adb -s 3CEF42ECD491687 shell monkey -p cc.ugotit.elinkbook -c android.intent.category.LAUNCHER 1
```

```bash
# 702×936／150 PPI（彩色）
adb -s 3CEF42ECD491687 shell wm size 702x936
adb -s 3CEF42ECD491687 shell wm density 150
adb -s 3CEF42ECD491687 shell am force-stop cc.ugotit.elinkbook
adb -s 3CEF42ECD491687 shell monkey -p cc.ugotit.elinkbook -c android.intent.category.LAUNCHER 1
```

Expected：兩組尺寸下皆與第一組相同——`ReaderSettingsSheet`／`PdfSettingsSheet` 皆能正確顯示、`X` 關閉鈕皆可見可點擊退出，無版面溢出（`RenderFlex overflow`）警告、無崩潰。

- [x] **Step 4：復原裝置螢幕尺寸/密度**

```bash
adb -s 3CEF42ECD491687 shell wm size reset
adb -s 3CEF42ECD491687 shell wm density reset
adb -s 3CEF42ECD491687 shell wm size
adb -s 3CEF42ECD491687 shell wm density
```

Expected：最後兩行指令輸出的 `Physical size`／`Physical density` 與 Step 2 記錄的原始數值一致，確認裝置已復原。

無需 commit（本 Task 純驗收，不變更任何檔案）。若 Step 3 任一組尺寸出現非預期行為（溢出/崩潰/關閉鈕不可見），停止並回報，不自行猜測修正方案。

**【驗收完成，人類親自確認】** 真機（`3CEF42ECD491687`）與三種目標螢幕尺寸/密度（824×1648／150 PPI、1404×1872／300 PPI 黑白、702×936／150 PPI 彩色）已由本人親自測試，`ReaderSettingsSheet`／`PdfSettingsSheet`（含 `FxlSettingsSheet`，見 Task 1 下方「事後決策」）三者的關閉按鈕在上述尺寸下皆可正確顯示並點擊退出，無版面溢出或崩潰。Issue 1 全部 4 個 Task 至此皆已完成。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`issues.md` Issue 1 的兩個修改點（`ReaderSettingsSheet` 加關閉列＋`Column(mainAxisSize.min)`/`Flexible`/`ListView(shrinkWrap)` 結構、檢查 `pdf_settings_sheet.dart`／`fxl_settings_sheet.dart` 是否有相同缺口）分別對應 Task 2 與 Task 1＋Task 3；三項單元測試要求（關閉鈕存在可點擊、內容溢出時位置固定、Pdf/Fxl 套用相同測試模式「若確實有相同缺口」）分別對應 Task 2 Step 1 的三個測試、Task 3 Step 1 的測試，以及 Task 1 對 Fxl 判定「無缺口」故不套用；驗收標準的三種螢幕尺寸真機/模擬確認對應 Task 4。
- **Fxl 判斷依據可回溯**：Task 1 記錄的判斷依據（`_openFxlSettings()` 未設 `enableDrag: false`＋`FxlSettingsSheet` 已用 `mainAxisSize: MainAxisSize.min` 緊湊包裹）皆附上可重新執行的 `grep` 指令與預期輸出，未來若 `_openFxlSettings()` 被改為 `enableDrag: false`，這組判斷需要重新檢視——但本計劃範圍內不做這個假設性防護（YAGNI，該情境尚未發生）。
- **無佔位符掃描**：所有 Task 皆附完整可執行的程式碼（`build()` 完整 before/after、測試完整程式碼、`adb`/`flutter` 完整指令），無 "TODO"/"視情況" 字樣；Task 2 的 `build()` before/after 皆逐字列出全部既有 slider/switch/override row 呼叫，未省略成「其餘不變」。
- **型別/介面一致性**：`Key('reader_settings_close_button')` 沿用 `issues.md` 原文指定的確切字串；`Key('pdf_settings_close_button')` 比照 `pdf_settings_*` 既有前綴慣例（`pdf_settings_tab_display`／`pdf_settings_dual_page_mode_$suffix` 等）命名，兩者的 `onPressed: () => Navigator.of(context).pop()` 寫法一致。Task 2／Task 3 新增的 `_pumpModalSheet` helper 分別對應各自檔案既有的 `_pumpSheet` helper 命名慣例（新增 `Modal` 字樣區分「直接塞進 `Scaffold.body`」與「透過真實 `showModalBottomSheet` 開啟」兩種 pump 方式）。
- **Task 執行順序的依賴關係**：Task 1（純調查）必須先於 Task 2／Task 3（決定要不要修改 Fxl），但 Task 1 不修改任何檔案，Task 2／Task 3 之間彼此獨立、可任意順序或平行進行；Task 4（真機驗收）必須在 Task 2、Task 3 皆已 commit 之後才進行（依賴兩者新增的 Key 存在於已建置的 APK 中）。
