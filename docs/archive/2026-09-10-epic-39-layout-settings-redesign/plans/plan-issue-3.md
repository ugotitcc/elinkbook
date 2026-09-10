# Epic 39 — Issue 3：`ReaderSettingsSheet` 分頁重組（文字對齊搬移＋單選群組改用 `EBOptionChipGroup`＋欄位大小步進器）實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** `ReaderSettingsSheet` 四個 Tab 顯示文字改名（`Key` 不變）；`_buildTextAlignRow()` 從「邊界」分頁搬到「呈現」分頁；欄數／文字對齊／書寫方向／翻頁模式／螢幕方向共 5 組單選群組改用 Issue 1 新增的 `EBOptionChipGroup`（套用 spec.md「選項標籤對照表」的短標籤）；`_buildColumnModeRow()` 內獨立的 `reader_settings_column_size_slider` 依 `isEinkMode` 切換 `EBStepper`。

**Architecture:** 四個子變更全部集中在 `reader_settings_sheet.dart` 同一批私有方法（`_buildBoundaryTab`／`_buildPresentationTab`／`_buildTextAlignRow`／`_buildColumnModeRow`／`_buildWritingModeOverrideRow`／`_buildPageTurnModeOverrideRow`／`_buildScreenOrientationOverrideRow`），依「不需要重工」的順序拆成 4 個 Task：(1) 先把 Tab 顯示文字改名並同步修正兩個測試檔案的呼叫點——**這一步必須排在最前面**，因為後續 Task 2-4 新增/修改的測試全部要用新分頁名稱呼叫 `switchToTab`，若不先完成改名，後面每個 Task 都要在自己的 Step 裡额外處理分頁名稱不一致的問題；(2) 搬移 `_buildTextAlignRow()`，此時分頁名稱已經是新名稱，只需要處理「內容搬去哪個分頁」這一個變數；(3) 5 組單選群組改用 `EBOptionChipGroup`，此時文字對齊已經在最終分頁位置，可以和其餘 4 組一起處理，不用等它搬完再回頭補一次；(4) 最後處理 `reader_settings_column_size_slider`，因為它是 `_buildColumnModeRow()` 內獨立宣告、不經過 `_buildSliderRow` 的控制項，Task 3 轉 `EBOptionChipGroup` 只會動到 `_buildColumnModeRow()` 最上面的 `Wrap` 部分，不會影響到它，順序上放最後互不干擾。

**Tech Stack:** Flutter/Dart，`flutter_test`，既有 `ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`）、Issue 1 新增的 `EBOptionChipGroup`／`EBOptionChipItem`（`app/lib/screens/widgets/eb_option_chip_group.dart`）與 `EBStepper`（`app/lib/screens/widgets/eb_stepper.dart`）。

**Spec:** `docs/epics/epic-39-layout-settings-redesign/spec.md`（§「既有元件異動」`ReaderSettingsSheet` 第 4-8 條、§「選項標籤對照表」、§「新增元件」`EBOptionChipGroup`）、`docs/epics/epic-39-layout-settings-redesign/issues.md`（Issue 3，含審查回應 C1/I3）——本計畫實作前已讀過 `design.md`／`issues.md`／`spec.md`、三份 Epic 階段審查報告（`reviews/review-design.md`、`review-spec.md`、`review-issues.md`），以及 Issue 1／2 的計畫與實作審查報告（`reviews/review-plan-issue-1.md`、`review-issue-1-implementation.md`、`review-plan-issue-2.md`、`review-issue-2-implementation.md`），並實際讀取目前（Issue 1-2 已合併後）的 `reader_settings_sheet.dart`／`reader_settings_sheet_test.dart`／`reader_screen_test.dart` 原始碼確認本計畫所有行號與程式碼片段皆對應現況。

## Global Constraints

- 所有顏色一律讀 `Theme.of(context).colorScheme`（`CLAUDE.md`）——本 Issue 不新增任何顏色邏輯，`EBOptionChipGroup`/`ReaderOptionTile` 既有配色沿用不動，純粹是「多顯示一行短標籤文字」與「底層元件替換」。
- **所有既有 `itemKey`／`Key` 字串一律不變**——本 Issue 只換底層渲染元件（`Wrap`+`ReaderOptionTile` → `EBOptionChipGroup`；`Slider` → `EBStepper`）與新增顯示文字，不改變任何既有測試賴以定位元件的 Key 命名。
- **本計畫在撰寫階段發現 `issues.md`／`spec.md` 皆未記載的既有缺口，一併納入範圍**：Tab 改名不只影響 `issues.md` 記載的 `app/test/screens/reader_settings_sheet_test.dart`（45 處 `switchToTab` 呼叫點，含註解共 55 處分頁名稱字串），**也影響 `app/test/screens/reader_screen_test.dart`**——該檔案有自己獨立的 `switchToTab` helper（第 9057 行，邏輯與斷言方式與 `reader_settings_sheet_test.dart` 完全相同：`find.widgetWithText(Tab, tabLabel)`），另有 11 處呼叫點（2 處 `'版面呈現'`／`'邊界首尾'`、9 處 `'設定喜好'`）依賴舊分頁文字，Tab 改名後這些呼叫點必然一併失效。Task 1 明確涵蓋這兩個檔案。
- **`ScreenOrientationSetting` tuple 既有的 `angle`（旋轉角度）欄位是既有死碼，非本 Issue 引入，不在本 Issue 職責範圍內修復**：現況 `_buildScreenOrientationOverrideRow()` 的 6-tuple 解構出 `angle` 後從未實際套用到任何 `Transform.rotate`（doc comment 聲稱「以 `Transform.rotate` 配合角度旋轉」但程式碼並未真的這樣做）。Task 3 改寫這個 tuple 時維持現狀行為不修復這個既有問題，只是把這個未使用的值改用 Dart 的 `_` 萬用字元明確標示為「刻意捨棄」，不再用具名但實際沒用到的 `angle` 變數。
- TDD 嚴格執行：每個 Step 先寫失敗測試（或確認現況會失敗），確認 RED（含確認失敗原因正確），再寫最小實作使其 GREEN，不得反向操作。
- **測試執行範圍**（比照 `CLAUDE.md`「測試執行範圍」慣例）：Task 1 因為直接改動 Tab 顯示文字，兩個測試檔案（`reader_settings_sheet_test.dart`／`reader_screen_test.dart`）都要各跑一次確認 RED 與 GREEN；Task 2-4 只改動 `reader_settings_sheet.dart`／`reader_settings_sheet_test.dart`，不再牽動 `reader_screen_test.dart`（該檔案的 11 處呼叫點在 Task 1 之後即與新分頁名稱一致，Task 2-4 不改變分頁名稱本身），故 Task 2-4 只需要跑 `flutter test test/screens/reader_settings_sheet_test.dart`；全套 `flutter test`（含 `reader_screen_test.dart` 完整重跑）留到本計畫最後一個 Task 執行一次。
- 所有新程式碼註解、文件字串、測試描述文字一律使用正體中文（zh-TW），專業術語可保留英文。
- 所有 `flutter test`／`flutter analyze` 指令皆在 `app/` 目錄下執行。

---

### Task 1：Tab 顯示文字改名（`Key` 不變）＋兩個測試檔案呼叫點同步更新

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:246-264`（`TabBar` 的 4 個 `Tab` `text:`）、`:270`／`:297-298`（兩處提及舊分頁名稱的註解／doc comment）
- Test: `app/test/screens/reader_settings_sheet_test.dart`（45 處 `switchToTab` 呼叫點＋10 處提及舊分頁名稱的註解，共 55 處字串）
- Test: `app/test/screens/reader_screen_test.dart`（11 處 `switchToTab` 呼叫點，第 536／547／7301／7344／7388／7422／7464／7510／7568／7604／7636 行）

**Interfaces:**
- Consumes：無新依賴，`TabBar`／`Tab`／既有 `switchToTab(tester, tabLabel)` helper（兩個測試檔案各自獨立定義，簽章相同：`Future<void> switchToTab(WidgetTester tester, String tabLabel) async`，內部用 `find.widgetWithText(Tab, tabLabel)` 定位並點擊）不變。
- Produces：4 個 Tab 的新顯示文字——`文字內容`→`文字`、`邊界首尾`→`邊界`、`版面呈現`→`呈現`、`設定喜好`→`預設集`；`Key` 常數（`reader_settings_tab_text_content`／`reader_settings_tab_boundary`／`reader_settings_tab_presentation`／`reader_settings_tab_preferences`）完全不變，供 Task 2-4 沿用。

- [x] **Step 1：修改 `reader_settings_sheet.dart`（刻意讓兩個測試檔案大量失敗，作為本 Task 的 RED）**

修改 `app/lib/screens/reader_settings_sheet.dart` 第 246-264 行：

```dart
                  const TabBar(
                    key: Key('reader_settings_tab_bar'),
                    tabs: [
                      Tab(
                        key: Key('reader_settings_tab_text_content'),
                        text: '文字',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_boundary'),
                        text: '邊界',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_presentation'),
                        text: '呈現',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_preferences'),
                        text: '預設集',
                      ),
                    ],
                  ),
```

第 270 行的註解（`NeverScrollableScrollPhysics` 說明）：

```dart
                      // 只能點擊 TabBar 切換——「文字」／「邊界」頁籤內
```

第 297-298 行的 doc comment：

```dart
  /// 【不可逆的技術決策】以下 4 個 `_buildXxxTab()` 方法（文字／邊界／
  /// 呈現／預設集）僅是本 State 的 `build()` 展示分支，一律不得抽成獨立
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 大量 FAIL（`switchToTab` 內 `find.widgetWithText(Tab, '文字內容')` 等舊文字找不到對應 `Tab`，`tester.tap()` 對空 `Finder` 拋出例外，45 個呼叫點所在的測試全數失敗）。

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 至少 11 個測試 FAIL（同樣原因，`switchToTab` 找不到舊分頁文字）。

- [x] **Step 3：批次修正兩個測試檔案的呼叫點與註解**

`switchToTab` 呼叫點與提及分頁名稱的註解在兩個檔案裡都是單純的舊分頁文字字串，且 4 個舊名稱彼此不互為子字串、也不與檔案內其他無關文字重疊（已逐一比對確認：`reader_settings_sheet_test.dart` 內「文字內容」「邊界首尾」「版面呈現」「設定喜好」四組字串的所有出現位置皆為分頁名稱本身或提及分頁名稱的註解，無誤判疑慮），可直接用 `sed` 做全域字串取代。

**審查修正 M2（`review-plan-issue-3.md`）**：使用者開發環境是 Windows，下列指令須透過 Git Bash（本專案 Bash 工具的預設 shell，已於本計畫撰寫階段實測 `sed (GNU sed) 4.9` 可正常執行）執行，**不是** PowerShell／`cmd.exe`——PowerShell 沒有原生 `sed`，若改用其他工具（例如 Edit 工具逐一取代、或 PowerShell 的 `-replace`）達到相同的全域字串取代效果亦可，重點是「4 個舊分頁名稱字串全域取代為新名稱」這個結果，不強制拘泥於 `sed` 這個工具本身：

```bash
cd app
sed -i "s/文字內容/文字/g" test/screens/reader_settings_sheet_test.dart
sed -i "s/邊界首尾/邊界/g" test/screens/reader_settings_sheet_test.dart
sed -i "s/版面呈現/呈現/g" test/screens/reader_settings_sheet_test.dart
sed -i "s/設定喜好/預設集/g" test/screens/reader_settings_sheet_test.dart

sed -i "s/邊界首尾/邊界/g" test/screens/reader_screen_test.dart
sed -i "s/版面呈現/呈現/g" test/screens/reader_screen_test.dart
sed -i "s/設定喜好/預設集/g" test/screens/reader_screen_test.dart
```

（`reader_screen_test.dart` 不含「文字內容」字串，故不需要對它執行第一條取代。）

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（64 個測試全過，數量與 Issue 2 完成時相同——本 Task 純文字改名，未新增/刪除任何測試案例）。

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全數通過，零回歸）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-39): Issue 3 Task 1 — ReaderSettingsSheet 四個 Tab 顯示文字改名"
```

---

### Task 2：`_buildTextAlignRow()` 從「邊界」分頁搬到「呈現」分頁

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:425-531`（`_buildBoundaryTab`／`_buildPresentationTab`）、`:766-798`（`_buildTextAlignRow`，補上 `visualDensity: VisualDensity.compact`）
- Test: `app/test/screens/reader_settings_sheet_test.dart`（新增 1 個位置驗證測試；修正 3 個既有測試改切「呈現」分頁）

**Interfaces:**
- Consumes：Task 1 已完成的新分頁文字（`'邊界'`／`'呈現'`）；既有 `_buildTextAlignRow()` 方法簽章不變，只改變它被呼叫的位置與內部 `visualDensity`。
- Produces：無新公開介面。`_buildTextAlignRow()` 內的 `ReaderOptionTile` 呼叫新增 `visualDensity: VisualDensity.compact`——這是為了讓既有測試「『呈現』頁籤內圖示列的 `ReaderOptionTile` 皆使用緊湊視覺密度」（`reader_settings_sheet_test.dart` 第 1329-1348 行）在文字對齊搬進來後依然成立，不需要修改該既有測試本身。

- [x] **Step 1：寫失敗測試——位置驗證＋修正 3 個受影響既有測試改切換到「呈現」分頁**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `void main()` 內追加新測試：

```dart
  testWidgets(
      '「文字對齊」已從「邊界」分頁搬到「呈現」分頁'
      '（epic-39-layout-settings-redesign Issue 3：spec.md「既有元件異動」'
      'ReaderSettingsSheet 第 4 條）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '邊界');

    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_tab_boundary_list')),
        matching: find.text('文字對齊'),
      ),
      findsNothing,
      reason: '文字對齊已搬離邊界分頁',
    );

    await switchToTab(tester, '呈現');

    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_tab_presentation_list')),
        matching: find.text('文字對齊'),
      ),
      findsOneWidget,
      reason: '文字對齊應出現在呈現分頁',
    );
  });
```

接著修正 3 個既有測試，把切到「邊界」改成切到「呈現」（此時 `_buildTextAlignRow()` 尚未搬移，這 3 個測試改完後會在「呈現」分頁找不到 `reader_settings_text_align_*` 系列 Key，形成本 Step 真正的 RED）：

(a) 測試「點擊文字對齊「置中」圖示後，onChanged 帶入 EpubTextAlign.center」：

```dart
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '呈現');

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_center')));
```

（原本此處是 `await switchToTab(tester, '邊界');`，只改這一行。）

(b) 測試「任一控制項互動後，writingModeOverride/pageTurnModeOverride/screenOrientationOverride 三個 Issue 4 欄位維持原值不被清空」：

```dart
    await switchToTab(tester, '呈現');

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_justify')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });
```

（原本此處是 `await switchToTab(tester, '邊界');`，只改這一行。）

(c) 測試「ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色」：

```dart
    // 切換到「呈現」頁籤（文字對齊選項已搬移至此）
    await switchToTab(tester, '呈現');
```

（原本此處是註解「切換到「邊界」頁籤（文字對齊選項在此頁籤）」＋`await switchToTab(tester, '邊界');`，兩行一起改。）

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 4 個測試 FAIL——新增的位置驗證測試（目前文字對齊仍在邊界分頁，`reader_settings_tab_boundary_list` 內找得到「文字對齊」文字，與預期的 `findsNothing` 不符）；另外 3 個被修正的既有測試（切到「呈現」分頁後，`reader_settings_text_align_*` 系列 Key 目前還掛在「邊界」分頁，`tester.tap()`／`find.byKey()` 皆找不到對應元件）。其餘既有測試維持 PASS。

- [x] **Step 3：實作搬移**

修改 `app/lib/screens/reader_settings_sheet.dart` 的 `_buildBoundaryTab()`（第 425-505 行），刪除結尾的 `_buildTextAlignRow()` 呼叫：

```dart
        SwitchListTile(
          key: const Key('reader_settings_show_footer'),
          title: const Text('顯示頁尾'),
          value: _showFooter,
          onChanged: (v) => setState(() {
            _showFooter = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

（原本這裡結尾是 `SwitchListTile(...show_footer...)` 後面接 `const SizedBox(height: 12),` 與 `_buildTextAlignRow(),` 兩行，一併刪除，`SwitchListTile` 後直接接 `],`。）

`_buildPresentationTab()`（第 507-531 行）在 `_buildColumnModeRow()` 之後插入 `_buildTextAlignRow()`：

```dart
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
        _buildTextAlignRow(),
        const SizedBox(height: 8),
        _buildWritingModeOverrideRow(),
        const SizedBox(height: 8),
        _buildScreenOrientationOverrideRow(),
        const SizedBox(height: 8),
        _buildPageTurnModeOverrideRow(),
      ],
    );
  }
```

`_buildTextAlignRow()`（第 766-798 行）的 `ReaderOptionTile` 呼叫補上 `visualDensity: VisualDensity.compact`（讓「呈現」頁籤內全部圖示列維持既有的緊湊視覺密度一致性）：

```dart
            return ReaderOptionTile<EpubTextAlign>(
              itemKey: Key('reader_settings_text_align_${align.name}'),
              value: align,
              groupValue: _textAlign ?? EpubTextAlign.justify,
              icon: icon,
              tooltip: tooltip,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _textAlign = v;
                _notifyChanged();
              }),
            );
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（65 個測試全過：既有 64 個＋本 Task 新增 1 個位置驗證測試；3 個修正過的既有測試與既有「緊湊視覺密度」測試皆零回歸）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 3 Task 2 — _buildTextAlignRow 從邊界分頁搬到呈現分頁"
```

---

### Task 3：5 組單選群組改用 `EBOptionChipGroup`（欄數／文字對齊／書寫方向／翻頁模式／螢幕方向）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`（`import` 區塊；`_buildColumnModeRow`／`_buildTextAlignRow`／`_buildWritingModeOverrideRow`／`_buildPageTurnModeOverrideRow`／`_buildScreenOrientationOverrideRow` 共 5 個方法）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Issue 1 的 `EBOptionChipGroup<T>`／`EBOptionChipItem<T>`（`app/lib/screens/widgets/eb_option_chip_group.dart`，`items`／`groupValue`／`onSelected`／`visualDensity` 皆已存在，直接複用；本 Issue 5 組群組皆不需要 `EBOptionChipItem.onTap` 動作型項目，該欄位留給 Issue 5 的 PDF 手動選區使用）。
- Produces：無新公開介面，5 個 `_buildXxxRow()` 方法簽章不變，內部改為建構 `EBOptionChipGroup` 而非手寫 `Wrap`。`app/lib/screens/reader_settings_sheet.dart` 不再直接參照 `ReaderOptionTile`（改由 `EBOptionChipGroup` 間接使用），故移除 `import 'widgets/reader_option_tile.dart';`，新增 `import 'widgets/eb_option_chip_group.dart';`。

- [x] **Step 1：寫失敗測試——5 組群組皆應顯示 spec.md 選項標籤對照表定義的短標籤**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets(
      '欄數群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤對照表'
      '定義的短標籤（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('auto', '自動'),
      ('single', '單欄'),
      ('double', '雙欄'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_column_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_column_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '文字對齊群組改用 EBOptionChipGroup 後，6 個選項皆顯示短標籤且全部存在'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('center', '置中'),
      ('justify', '齊行'),
      ('start', '起始'),
      ('end', '結尾'),
      ('left', '靠左'),
      ('right', '靠右'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_text_align_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_text_align_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '書寫方向覆寫群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('book', '書籍'),
      ('vertical', '直排'),
      ('horizontal', '橫排'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_writing_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_writing_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '翻頁模式覆寫群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('global', '全域'),
      ('paginated', '點擊'),
      ('scroll', '滾動'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_page_turn_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_page_turn_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '螢幕方向覆寫群組改用 EBOptionChipGroup 後，6 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('global', '全域'),
      ('auto', '自動'),
      ('lock0', '0°'),
      ('lock90', '90°'),
      ('lock180', '180°'),
      ('lock270', '270°'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_screen_orientation_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_screen_orientation_$suffix 應顯示標籤「$label」',
      );
    }
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 新增的 5 個測試全數 FAIL——現況 5 個群組皆用裸 `ReaderOptionTile`（未傳 `label`），畫面上完全沒有任何選項文字標籤，`find.text(label)` 一律 `findsNothing`，與預期的 `findsOneWidget` 不符。其餘既有 65 個測試維持 PASS。

- [x] **Step 3：實作 5 組 `EBOptionChipGroup` 轉換**

`app/lib/screens/reader_settings_sheet.dart` 頂端 import 區塊：移除 `import 'widgets/reader_option_tile.dart';`，新增：

```dart
import 'widgets/eb_option_chip_group.dart';
```

`_buildColumnModeRow()`（原第 549-571 行，僅改 `const Text('欄數')` 到 `Wrap(...)` 結尾這段——`if (_columnMode == ColumnMode.auto)` 以下的 Slider 部分本 Task 不動，留給 Task 4；審查修正 M3，`review-plan-issue-3.md`：明確標註本方法本 Task 只改這一段，不若其餘 4 個方法一次整段重寫，是刻意的最小改動範圍，非遺漏）：

```dart
          const Text('欄數'),
          const SizedBox(height: 4),
          EBOptionChipGroup<ColumnMode>(
            items: [
              (ColumnMode.auto, 'auto', Icons.auto_awesome, '自動', '自動'),
              (ColumnMode.single, 'single', Icons.crop_portrait, '單欄', '單欄'),
              (ColumnMode.double, 'double', Icons.book, '雙欄', '雙欄'),
            ].map((option) {
              final (mode, keySuffix, icon, tooltip, label) = option;
              return EBOptionChipItem<ColumnMode>(
                itemKey: Key('reader_settings_column_mode_$keySuffix'),
                value: mode,
                icon: icon,
                label: label,
                tooltip: tooltip,
              );
            }).toList(),
            groupValue: _columnMode,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() {
              _columnMode = v;
              _notifyChanged();
            }),
          ),
```

`_buildTextAlignRow()`：

```dart
  Widget _buildTextAlignRow() {
    const options = [
      (EpubTextAlign.center, Icons.format_align_center, '置中', '置中'),
      (EpubTextAlign.justify, Icons.format_align_justify, '左右對齊', '齊行'),
      (EpubTextAlign.start, Icons.first_page, '起始邊對齊', '起始'),
      (EpubTextAlign.end, Icons.last_page, '結尾邊對齊', '結尾'),
      (EpubTextAlign.left, Icons.format_align_left, '靠左', '靠左'),
      (EpubTextAlign.right, Icons.format_align_right, '靠右', '靠右'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文字對齊'),
        EBOptionChipGroup<EpubTextAlign>(
          items: options.map((option) {
            final (align, icon, tooltip, label) = option;
            return EBOptionChipItem<EpubTextAlign>(
              itemKey: Key('reader_settings_text_align_${align.name}'),
              value: align,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _textAlign ?? EpubTextAlign.justify,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _textAlign = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

`_buildWritingModeOverrideRow()`：

```dart
  Widget _buildWritingModeOverrideRow() {
    const options = [
      (null, 'book', Icons.auto_stories, '採用書籍排版', '書籍'),
      (WritingMode.vertical, 'vertical', Icons.text_rotate_vertical, '強制直排', '直排'),
      (WritingMode.horizontal, 'horizontal', Icons.text_rotation_none, '強制橫排', '橫排'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('排版方向模式'),
        EBOptionChipGroup<WritingMode?>(
          items: options.map((option) {
            final (mode, keySuffix, icon, tooltip, label) = option;
            return EBOptionChipItem<WritingMode?>(
              itemKey: Key('reader_settings_writing_mode_$keySuffix'),
              value: mode,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _writingModeOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _writingModeOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

（`_buildWritingModeOverrideRow()` 上方既有 doc comment 提及具體型別 `ReaderOptionTile<WritingMode?>`，轉換後型別已改為 `EBOptionChipItem<WritingMode?>`，順手把該行文字內的型別名稱同步更新，其餘說明「為何直接傳原始 nullable 值、不用 sentinel」的理由不變：

```dart
            // 【審查修正 Important：見 reviews/review-issue-5-8.md Issue 6
            // Important #1】原本用「某個真實 enum 值當 sentinel 代表 null」
            // （例如 WritingMode.horizontal），但 options 清單裡剛好也有一個
            // 真實選項是 WritingMode.horizontal，兩者的 effectiveValue 會
            // 撞在一起，導致 _writingModeOverride == null 時「採用書籍排版」
            // 與「強制橫排」兩顆 tile 同時判定為選中。改用
            // EBOptionChipItem<WritingMode?>，value 直接傳原始 nullable 值，
            // 不需要 fallback，null 只會跟 null 相等。
```

同理，`_buildPageTurnModeOverrideRow()`／`_buildScreenOrientationOverrideRow()` 上方各自的既有 doc comment 也各自提及 `ReaderOptionTile<PageTurnMode?>`／`ReaderOptionTile<ScreenOrientationSetting?>`，一併同步改為 `EBOptionChipItem<PageTurnMode?>`／`EBOptionChipItem<ScreenOrientationSetting?>`，其餘文字不變：

```dart
            // 【審查修正 Important，同排版方向覆寫的修法】改用
            // EBOptionChipItem<PageTurnMode?>，避免 sentinel 值與真實選項
            // （PageTurnMode.scroll）衝突。
```

```dart
            // 【審查修正 Important，同排版方向覆寫的修法】改用
            // EBOptionChipItem<ScreenOrientationSetting?>，避免 sentinel 值
            // 與真實選項（ScreenOrientationSetting.auto）衝突。
```)

`_buildPageTurnModeOverrideRow()`：

```dart
  Widget _buildPageTurnModeOverrideRow() {
    const options = [
      (null, 'global', Icons.tune, '使用全域預設', '全域'),
      (PageTurnMode.paginated, 'paginated', Icons.menu_book, '點擊翻頁', '點擊'),
      (PageTurnMode.scroll, 'scroll', Icons.swap_vert, '滾動翻頁', '滾動'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('翻頁模式覆寫'),
        EBOptionChipGroup<PageTurnMode?>(
          items: options.map((option) {
            final (mode, keySuffix, icon, tooltip, label) = option;
            return EBOptionChipItem<PageTurnMode?>(
              itemKey: Key('reader_settings_page_turn_mode_$keySuffix'),
              value: mode,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _pageTurnModeOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _pageTurnModeOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

`_buildScreenOrientationOverrideRow()`（既有 6-tuple 的 `angle` 欄位維持原樣宣告在 tuple type 中，但解構時改用 `_` 明確標示未使用，不再修復它「宣告卻未套用到任何 Widget」這個既有問題——見 Global Constraints）：

```dart
  Widget _buildScreenOrientationOverrideRow() {
    // (setting, keySuffix, icon, tooltip, rotationAngle, label)
    const options = <(
      ScreenOrientationSetting?,
      String,
      IconData,
      String,
      double,
      String,
    )>[
      (null, 'global', Icons.tune, '使用全域預設', 0.0, '全域'),
      (ScreenOrientationSetting.auto, 'auto', Icons.screen_rotation, '自動旋轉', 0.0, '自動'),
      (ScreenOrientationSetting.lock0, 'lock0', Icons.stay_current_portrait, '鎖定 0°', 0.0, '0°'),
      (ScreenOrientationSetting.lock90, 'lock90', Icons.stay_current_landscape, '鎖定 90°', 0.0, '90°'),
      (ScreenOrientationSetting.lock180, 'lock180', Icons.stay_current_portrait, '鎖定 180°', pi, '180°'),
      (ScreenOrientationSetting.lock270, 'lock270', Icons.stay_current_landscape, '鎖定 270°', pi * 1.5, '270°'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('螢幕方向鎖定覆寫'),
        EBOptionChipGroup<ScreenOrientationSetting?>(
          items: options.map((option) {
            final (setting, keySuffix, icon, tooltip, _, label) = option;
            return EBOptionChipItem<ScreenOrientationSetting?>(
              itemKey: Key('reader_settings_screen_orientation_$keySuffix'),
              value: setting,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _screenOrientationOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _screenOrientationOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（70 個測試全過：既有 65 個＋本 Task 新增 5 個；既有「緊湊視覺密度」測試、E-Ink 高對比選中底色測試、`switchToTab`／`find.byKey` 系列既有測試皆零回歸——`EBOptionChipGroup` 內部仍然渲染帶相同 `itemKey` 的 `ReaderOptionTile`，既有依賴這些 Key 的測試不受影響）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`（含確認移除 `reader_option_tile.dart` import 後沒有殘留的 unused import 警告）。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 3 Task 3 — 5 組單選群組改用 EBOptionChipGroup"
```

---

### Task 4：`_buildColumnModeRow()` 內 `reader_settings_column_size_slider` 依 `isEinkMode` 切換 `EBStepper`（審查修正 C3／I3）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart:573-588`（`_buildColumnModeRow()` 內 `if (_columnMode == ColumnMode.auto)` 區塊）
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1 的新分頁名稱；Issue 1 的 `EBStepper`（`keyPrefix`／`value`／`min`／`max`／`step`／`displayValue`／`onChanged`／`mainAxisSize`／`mainAxisAlignment`）；`widget.isEinkMode`。
- Produces：無新公開介面。`isEinkMode: true` 時，`reader_settings_column_size_slider` 這個 Key 被 `reader_settings_column_size_decrement`／`_value`／`_increment` 三個 Key 取代（僅在此分支下，`isEinkMode: false` 時 `reader_settings_column_size_slider` Key 維持不變）；上方標題 `Text` 依 `isEinkMode` 決定是否帶數值（審查修正 M1，`review-plan-issue-3.md`：E-Ink 模式隱藏數值避免與 `EBStepper` 內部顯示重複，比照 Issue 2 C1 先例）。

- [x] **Step 1：寫失敗測試——E-Ink 模式改為 EBStepper＋一般主題零回歸**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `void main()` 內追加：

```dart
  testWidgets(
      'isEinkMode: true 且 columnMode=auto 時，欄位大小改為 EBStepper，'
      '點擊 + 觸發 onChanged 帶入 columnSize+60（審查修正 C3/I3，'
      'review-spec.md／review-issues.md：reader_settings_column_size_slider '
      '未經過 _buildSliderRow，需獨立處理，epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
      isEinkMode: true,
    );
    await switchToTab(tester, '呈現');

    expect(find.byKey(const Key('reader_settings_column_size_slider')),
        findsNothing,
        reason: 'E-Ink 模式不應存在 Slider');
    expect(find.byKey(const Key('reader_settings_column_size_value')),
        findsOneWidget);
    expect(find.text('欄位大小'), findsOneWidget,
        reason: '審查修正 M1（review-plan-issue-3.md）：E-Ink 模式下標題不應帶數值，'
            '避免與 EBStepper 內部顯示的數值重複（比照 Issue 2 C1 對 _buildSliderRow '
            '已建立的先例）');
    expect(find.text('欄位大小 720px'), findsNothing,
        reason: '標題與 EBStepper 顯示同一個數值視為重複顯示');

    await tester
        .tap(find.byKey(const Key('reader_settings_column_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.columnSize, 780.0, reason: '預設 720 + step 60 = 780');
  });

  testWidgets(
      'isEinkMode: false（預設）時，欄位大小維持既有 Slider 與帶數值標題（既有行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    expect(find.byKey(const Key('reader_settings_column_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_column_size_value')),
        findsNothing);
    expect(find.text('欄位大小 720px'), findsOneWidget,
        reason: '一般主題下 Slider 本身不具備數值回饋能力，標題必須保留數值'
            '（比照 Issue 2 C1 對 _buildSliderRow 已建立的先例）');
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 第一個測試 FAIL——現況無條件渲染 `Slider`，`reader_settings_column_size_slider` 在 `isEinkMode: true` 時依然存在（與預期的 `findsNothing` 不符）；`reader_settings_column_size_value` 這個 Key 尚不存在於任何地方；標題現況固定是 `Text('欄位大小 ${_columnSize.round()}px')`，`find.text('欄位大小')`（不含數值）找不到、`find.text('欄位大小 720px')` 卻找得到，兩者皆與預期相反。第二個測試（`isEinkMode: false` 迴歸）在目前程式碼下**已經會通過**——現況本來就無條件渲染 `Slider` 且標題本來就帶數值；因為兩個測試寫在同一個 Step、一起執行，整體 `flutter test` 結果仍是 FAIL（第一個測試失敗），這是刻意避免「有測試從未真正 RED 過」的寫法（比照 `review-plan-issue-2.md` I2 的既有先例）——待 Step 3 實作完成後，兩個測試會在同一次 GREEN 內一起被驗證。

- [x] **Step 3：實作 `EBStepper` 分支**

修改 `app/lib/screens/reader_settings_sheet.dart` 的 `_buildColumnModeRow()`（原第 573-588 行 `if (_columnMode == ColumnMode.auto)` 區塊）：

```dart
          if (_columnMode == ColumnMode.auto) ...[
            const SizedBox(height: 8),
            // 審查修正 M1（review-plan-issue-3.md）：isEinkMode 時標題不帶數值，
            // 避免與下方 EBStepper 內部顯示的數值重複（比照 Issue 2 C1 對
            // _buildSliderRow 已建立的先例——一般主題下 Slider 不具備數值回饋
            // 能力，標題仍須保留數值）。
            Text(widget.isEinkMode
                ? '欄位大小'
                : '欄位大小 ${_columnSize.round()}px'),
            widget.isEinkMode
                ? EBStepper(
                    keyPrefix: 'reader_settings_column_size',
                    value: _columnSize,
                    min: 360.0,
                    max: 1440.0,
                    step: 60.0,
                    displayValue: '${_columnSize.round()}px',
                    onChanged: (v) => setState(() {
                      _columnSize = v;
                      _notifyChanged();
                    }),
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  )
                : Slider(
                    key: const Key('reader_settings_column_size_slider'),
                    value: _columnSize,
                    min: 360.0,
                    max: 1440.0,
                    divisions: 18, // (1440 - 360) / 60 = 18
                    label: '${_columnSize.round()}px',
                    onChanged: (v) => setState(() {
                      _columnSize = v;
                      _notifyChanged();
                    }),
                  ),
          ],
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（72 個測試全過：既有 70 個＋本 Task 新增 2 個）。

- [x] **Step 5：`flutter analyze` 確認零警告**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart test/screens/reader_settings_sheet_test.dart`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-39): Issue 3 Task 4 — reader_settings_column_size_slider 依 isEinkMode 切換 EBStepper"
```

---

### Task 5：收尾——全套測試與更新計畫狀態

**Files:**
- 無新增/修改程式碼檔案（僅驗證與文件收尾）。

- [x] **Step 1：跑全套 `flutter test`**

Run: `flutter test`
Expected: 全數通過，零回歸（`reader_settings_sheet_test.dart` 72 個＋`reader_screen_test.dart` 與其餘全專案測試皆維持 PASS）。

- [x] **Step 2：跑全套 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3：將本檔案所有 Task 的 Step 勾選為完成**

把本檔案（`docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-3.md`）Task 1-5 全部 `- [x]` 改為 `- [x]`。

- [x] **Step 4：Commit 計畫狀態更新**

```bash
git add docs/epics/epic-39-layout-settings-redesign/plans/plan-issue-3.md
git commit -m "docs(epic-39): Issue 3 計畫執行完成，全部 Step 標記完成"
```

Issue 3 完成後，交由人類決定是否發起程式碼審查（`superpowers:requesting-code-review`），審查通過後才可進入 Issue 4。
