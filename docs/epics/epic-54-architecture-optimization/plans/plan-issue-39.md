# Issue 39 實作計畫：版面設定草稿收成純 Dart module

> **給執行者**：必須使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。步驟用 `- [ ]` 追蹤，完成一步就改成 `- [x]`。

**目標**：把 `ReaderSettingsSheet` 的本地欄位與「`BookReaderPrefs` ↔ 欄位」的四份手寫對應收成純 Dart 的 `ReaderSettingsDraft`，面板 State 只留 UI 暫態。**行為完全不變。**

**架構**：新增可變物件 `ReaderSettingsDraft`（`app/lib/reader/reader_settings_draft.dart`）與小型值物件 `OverridableValue`。單位換算與預設值常數收進草稿。面板 State 持有一個 `_draft`。

**技術**：Flutter 3.47.9／Dart 3.13.7；既有 `BookReaderPrefs`、`fullBookReaderPrefsSeed`。

**設計來源**：`epic.md`「Issue 39 設計決策」。本計畫只列施工步驟。

## Global Constraints

- **不改任何使用者可見行為**：包含 `?? false`／`?? true` 的具現化、12 個非流式欄位清成 null、`didUpdateWidget` 整個換掉草稿。疑似缺陷留給 Issue 41。
- `flutter analyze` 必須顯示 `No issues found!`；不新增使用者可見字串。
- **138 個 widget 測試一個都不刪、不改斷言**；若有測試因重構失敗，先判斷是重構錯誤，不是改測試。
- 不改 `PdfSettingsSheet`、`FxlSettingsSheet`、`BookReaderPrefs`。
- 提交不加 `Co-Authored-By`；註解與文件用正體中文。
- 測試範圍：Task 1、2 只跑受影響的測試檔；完整 `flutter test` 只在 Task 3 跑一次。

## Review Focus

1. 空 prefs 的具現化結果不變（邊距 32／16／24／24、`publisherStyles` true、頁首頁尾全螢幕 false、`columnMode` auto、`columnSize` 720）。→ Task 1 測試 1。
2. 倍率往返與四捨五入：字級 1.5 ↔ 24、段距 1.2 ↔ 12；非整數倍率（如 1.03）取整到 UI 刻度後輸出 1.0（有損，維持現況）。→ Task 1 測試 3、4。
3. 首行縮排關閉時保留數字、`0` 不被當成「未設定」。→ Task 1 測試 8、9。
4. `resetToBookDefault` 只動 6 欄位，不碰字型、邊距、對齊等。→ Task 1 測試 10。
5. 預設集「目前使用中」判定（`preset.prefs == 草稿輸出`）與「另存為預設集」傳出的內容不變。→ Task 2（既有 widget 測試守住）。

## 現況（2026-11-15 讀碼確認）

- `reader_settings_sheet.dart`：`initState`（:140）與 `didUpdateWidget`（:185）各約 30 行逐行相同的對應；`_currentDraft`（:297）；`_toMultiplier`（:272）；預設常數 `_defaultFontSize` 等（:88-97）；`_resetToBookDefault`（:1811）；「系統預設」列 `isActive`（:1783）；`preset.prefs == _currentDraft`（:1858）；`widget.onSaveAsPreset(_currentDraft)`（:1653）；`_notifyChanged()` 32 處。
- 各欄位在檔內出現次數（grep）：`_fontSize` 等 5 個數值欄各約 9、對應的 `…Overridden` 旗標各約 9～10、`_firstLineIndent` 8、`_firstLineIndentOn` 10。
- `BookReaderPrefs.reflowableEpubFields()`（`lib/reader/book_reader_prefs.dart:428`）是「23 個流式欄位」的權威過濾。

## 目標 interface

```dart
/// 「值＋是否已覆寫」成對欄位。`fontSize`、`paragraphSpacing` 的 value 是 UI 刻度
/// （16／10 的倍數換算在草稿內）；`fontWeight`（倍率，預設 1.0，UI 的 ×400 在面板）、
/// `lineHeight`、`letterSpacing` 的 value 就是儲存值，草稿不換算。
class OverridableValue {
  OverridableValue({required this.defaultValue, double? initial});
  final double defaultValue;
  double value;          // 初值 = initial ?? defaultValue
  bool overridden;       // 初值 = initial != null
  void set(double v);    // value = v; overridden = true
  void reset();          // value = defaultValue; overridden = false
}

class ReaderSettingsDraft {
  ReaderSettingsDraft.fromPrefs(BookReaderPrefs prefs);
  BookReaderPrefs toPrefs();
  void resetToBookDefault();            // 只動下列 6 欄位
  bool get isBookDefaultTextStyle;      // 6 欄位皆未覆寫

  String? fontFamily;  String? headingFontFamily;
  final OverridableValue fontSize, fontWeight, lineHeight, paragraphSpacing, letterSpacing;
  double firstLineIndent;  bool firstLineIndentOn;
  double marginTop, marginBottom, marginLeft, marginRight;
  EpubTextAlign? textAlign;  bool publisherStyles;
  WritingMode? writingModeOverride;  PageTurnMode? pageTurnModeOverride;
  ScreenOrientationSetting? screenOrientationOverride;  TextConversionMode? textConversionOverride;
  bool showHeader, showFooter, fullscreen;
  ColumnMode columnMode;  double columnSize;
}
```

預設值（`static const`，數值與現有 `_defaultXxx`／`??` 完全一致）：字級 16、字重 1.0、行距 1.0、段距 10、首行縮排 2、字距 0、邊距 32／16／24／24、`publisherStyles` true、`showHeader`／`showFooter`／`fullscreen` false、`columnMode` auto、`columnSize` 720。

換算（與現有 `_currentDraft`、`initState` 完全一致）：`fontSize`：儲存倍率 ×16 後 `roundToDouble()` ↔ UI 值 ÷16；`paragraphSpacing`：×10 ↔ ÷10；反向以 `((v / base) * 10000).round() / 10000`。`fontWeight`、`lineHeight`、`letterSpacing` 不換算。

6 個重置欄位：`fontSize`、`fontWeight`、`lineHeight`、`paragraphSpacing`、`letterSpacing`（`reset()`），以及首行縮排（`firstLineIndentOn = false`、`firstLineIndent = 預設 2`）。

---

## Task 1：草稿 module 與單元測試（TDD）

**Files:**
- Create: `app/lib/reader/reader_settings_draft.dart`
- Create: `app/test/reader/reader_settings_draft_test.dart`

**Interfaces:**
- Produces：上方「目標 interface」。
- Consumes：`BookReaderPrefs`（建構子與 `==`、`reflowableEpubFields()`）、`fullBookReaderPrefsSeed`（`test/support/full_book_reader_prefs.dart`）。

- [ ] **Step 1：寫失敗測試。** 測試名稱與斷言：
  1. `空 prefs：fromPrefs(empty).toPrefs() 只輸出具現化的預設欄位`——等於 `BookReaderPrefs(marginTop: 32, marginBottom: 16, marginLeft: 24, marginRight: 24, publisherStyles: true, showHeader: false, showFooter: false, fullscreen: false, columnMode: ColumnMode.auto, columnSize: 720)`
  2. `種子往返：fromPrefs(seed).toPrefs() 等於 seed.reflowableEpubFields()`，並明確斷言 `pdfContrast`、`dualPageMode` 為 null（12 個非流式欄位清成 null）
  3. `字級與段距：儲存倍率 1.5 對應 UI 值 24、1.2 對應 12；UI 值回輸出 1.5、1.2`
  4. `非整數倍率取整到 UI 刻度：fontSize 1.03 的 UI 值為 16，輸出 1.0`
  5. `未覆寫欄位輸出 null：字級、字重、行距、段距、字距在 empty 輸入下 toPrefs 皆為 null`
  6. `OverridableValue.set：value 變為新值且 overridden 為 true`
  7. `OverridableValue.reset：value 回 defaultValue 且 overridden 為 false`
  8. `首行縮排關閉時保留數字：fromPrefs 無縮排 → firstLineIndentOn 為 false、firstLineIndent 為 2；把 firstLineIndent 改成 3 且仍關閉 → toPrefs().firstLineIndent 為 null；再把 firstLineIndentOn 設 true → 輸出 3`
  9. `首行縮排為 0 時視為已開啟：fromPrefs(firstLineIndent: 0) → firstLineIndentOn 為 true、輸出 0.0`
  10. `resetToBookDefault 只動 6 個欄位：先把 6 欄位全改成覆寫、並改 fontFamily、marginTop、textAlign、showFooter；重置後 6 欄位回預設且未覆寫，另外 4 個維持改過的值`
  11. `isBookDefaultTextStyle：empty 為 true；逐一驗證 6 種情境，分別只覆寫 fontSize、fontWeight、lineHeight、paragraphSpacing、letterSpacing、或只把 firstLineIndentOn 設 true，每次都斷言為 false，再 resetToBookDefault() 後斷言回 true`（漏檢查任一欄位都會被抓到）
- [ ] **Step 2：執行確認失敗。** `cd app && flutter test test/reader/reader_settings_draft_test.dart`；預期：編譯失敗（找不到 `ReaderSettingsDraft`）。
- [ ] **Step 3：實作 `OverridableValue` 與 `ReaderSettingsDraft`。** 對應邏輯從 `reader_settings_sheet.dart` 的 `initState`（:140）、`_currentDraft`（:297）、`_resetToBookDefault`（:1811）搬過來，數值與預設值一字不改。每個類別加正體中文 class doc；`toPrefs()` 上方註解保留 `_currentDraft` 原有那段「null 會被整列寫入預設集與目標書籍」的警語（見現有 :276-296）。
- [ ] **Step 4：執行確認通過。** 同 Step 2 指令；預期：11 個測試全過。
- [ ] **Step 5：`cd app && flutter analyze` 乾淨後提交。** 回到 repo 根目錄再執行 git 指令：`git add app/lib/reader/reader_settings_draft.dart app/test/reader/reader_settings_draft_test.dart`；訊息 `feat(reader): 新增 ReaderSettingsDraft 與 OverridableValue（epic-54 Issue 39 Task 1）`。

## Task 2：面板改用草稿

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`

**Interfaces:**
- Consumes：Task 1 的 `ReaderSettingsDraft`、`OverridableValue`。
- Produces：無新公開介面；`ReaderSettingsSheet` 對外行為不變。

- [ ] **Step 1：基線。** `cd app && flutter test test/screens/reader_settings_sheet_test.dart`；預期：全過（記下通過數，之後每一步都要相同）。
- [ ] **Step 2：State 欄位換成草稿。** 刪除所有 `BookReaderPrefs` 相關的 `late` 欄位（`_fontFamily` 到 `_columnSize`，約 :99-132）與預設常數（:88-97）；新增 `late ReaderSettingsDraft _draft`。保留 `_readerColors`、`_bgHexController`、`_textHexController`、`_bgHexError`、`_textHexError`。`initState` 與 `didUpdateWidget`（prefs 變動時）都改為 `_draft = ReaderSettingsDraft.fromPrefs(widget.prefs)`（`didUpdateWidget` 仍包在 `setState`）。
- [ ] **Step 3：輸出與重置改走草稿。** `_currentDraft` getter 改成呼叫 `_draft.toPrefs()`（或刪除並讓 :326、:1653、:1858 三處直接用 `_draft.toPrefs()`）；刪除 `_toMultiplier`（:272）；`_resetToBookDefault` 改為 `setState(() { _draft.resetToBookDefault(); _notifyChanged(); })`；「系統預設」列 `isActive` 改為 `_draft.isBookDefaultTextStyle`。
- [ ] **Step 4：各列改讀寫草稿。** 5 個 `OverridableValue` 欄位的 `_buildSliderRow` 只替換「讀寫哪個欄位」，**UI 端既有的換算與取整一律保留**（`reader_settings_sheet.dart` :473-552，審查 I-1 逐行核對）：
  - `fontSize`、`paragraphSpacing`：`value: _draft.fontSize.value`、`isOverridden: _draft.fontSize.overridden`、`onReset: () => setState(() { _draft.fontSize.reset(); _notifyChanged(); })`、`onChanged: (v) => setState(() { _draft.fontSize.set(v); _notifyChanged(); })`（段距同形，`displayValue` 維持 `.round()`）。
  - `fontWeight`：草稿的 `fontWeight.value` 存的是**倍率**（預設 1.0），`× 400` 只存在於 UI。滑桿 `value: _draft.fontWeight.value * 400`、`displayValue: (_draft.fontWeight.value * 400).round().toString()`、`onChanged` 呼叫 `_draft.fontWeight.set(v / 400)`。
  - `lineHeight`：`onChanged` 維持 `_draft.lineHeight.set(double.parse(v.toStringAsFixed(1)))`；`letterSpacing`：維持 `_draft.letterSpacing.set(double.parse(v.toStringAsFixed(2)))`。這兩個取整是消除 `Slider` 步進的浮點尾數，漏掉會破壞 `preset.prefs == _draft.toPrefs()` 的精確比對。
  - 其他欄位（字型、邊距、對齊、各覆寫選項、頁首頁尾、全螢幕、欄位模式與寬度、首行縮排）把 `_xxx` 改為 `_draft.xxx`。不改任何 Key、文字、版面。
- [ ] **Step 5：同步更新過時註解並確認沒有殘留。** 先把註解裡的舊欄位名改成新名稱：:100（`_currentDraft`）、:112（`_currentDraft`）、:439（`_fontSizeOverridden`）、:1436（`_writingModeOverride` → `_draft.writingModeOverride`）；不改註解的語意。再執行（Git Bash；PowerShell 可改用 `Select-String -Pattern` 同樣的規則）：`cd app && grep -nE "_fontSizeOverridden|_fontWeightOverridden|_lineHeightOverridden|_paragraphSpacingOverridden|_letterSpacingOverridden|_firstLineIndentOn\b|_toMultiplier|_defaultFontSize|_marginTop\b|_columnSize\b|_writingModeOverride\b|_currentDraft" lib/screens/reader_settings_sheet.dart`；預期：無輸出（若保留 `_currentDraft` getter 則只剩該定義處）。
- [ ] **Step 6：執行確認全綠。** `cd app && flutter analyze lib/screens/reader_settings_sheet.dart` 乾淨；`flutter test test/screens/reader_settings_sheet_test.dart test/reader/reader_settings_draft_test.dart test/reader/layout_preset_flow_test.dart`；預期：通過數與 Step 1 的基線一致再加 Task 1 的 11 個。
- [ ] **Step 7：開啟面板的整合點。** `cd app && flutter test test/screens/reader_screen_test.dart`；預期：全過。
- [ ] **Step 8：提交。** 訊息 `refactor(reader): 版面設定面板改用 ReaderSettingsDraft（epic-54 Issue 39 Task 2）`。

## Task 3：整體驗證與文件

**Files:**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`、`issues.md`、`docs/epics.md`

- [ ] **Step 1：兩個靜態守衛。** `cd app && node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`（Windows 用 pnpm 內建 Node，PATH 前置 `$env:PNPM_HOME`）；預期：兩者 PASS。
- [ ] **Step 2：完整測試。** `cd app && flutter test`；預期：0 失敗。若出現 `pdf_reader_view_filters_test` 偶發失敗，單獨重跑 3 次並照實記錄（已知偶發，見 Issue 35）。
- [ ] **Step 3：寫入 `epic.md`。** 記實作內容、與設計決策的差異（如有）、驗證結果，以及**未驗證**：未在真機操作版面設定面板的實際手感；Issue 41 疑似缺陷仍待重現。
- [ ] **Step 4：`issues.md` 的 Issue 39 狀態改為「已完成待合併」；`docs/epics.md` epic-54 那列補一句。** 提交並 push，開 PR。
