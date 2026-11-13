# Issue 3：設定面板標題字型下拉與 l10n 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 讓使用者第一次能操作標題字型：`ReaderSettingsSheet`（流式 Foliate 設定面板）的「字型」卡片在主字型下拉之下新增「標題字型」下拉（`Key('reader_settings_heading_font_family')`，第一項「跟隨主字型」＝`null`）；主字型標籤改為「主字型」；l10n 四份 arb 同步並重新產生 `app_localizations*.dart`；`FxlSettingsSheet`／`PdfSettingsSheet` 不顯示；最後在 Windows 桌面版以真實 EPUB 目視確認並寫入 `reports/issue-3-report.md`。**不動資料層（Issue 1）、不動渲染層（Issue 2）、不動刪除字型連動（Issue 4）。**

**Architecture：** Issue 1 已把 `_headingFontFamily` 草稿欄位接進 `_currentDraft`／`initState`／`didUpdateWidget`，Issue 2 已讓閱讀器吃 `headingFontFamily`；本張只補「使用者可寫入這個欄位」的 UI：抽出一個共用的字型選項建構（主、標題兩個下拉的選項清單完全相同，只有第一項文字不同），新增標題字型下拉，`onChanged` 與主字型同一模式（`setState` 寫草稿 → `_notifyChanged()`）。目前值取 `fonts.effectiveFamily(_headingFontFamily)`，不可用時只影響顯示，**絕不改寫偏好**（ADR 0035）。

**Tech Stack：** Flutter 3.47.9／Dart 3.13.7、`flutter_test`、`flutter gen-l10n`。指令一律在 `C:\Users\fycdc\AI\elinkBook\app` 下執行。

**Spec：** `docs/epics/epic-68-heading-font/spec.md` §4（UI 契約）；`design.md` D8、D10、D15；驗收 `issues.md` Issue 3。

## 已實際查證的現況（行號僅供參考，一律以字串定位）

| 位置 | 查證結果 |
|---|---|
| `lib/screens/reader_settings_sheet.dart` 狀態欄位 | `late String? _headingFontFamily;`（約 101，註解「Issue 1 僅帶入草稿，下拉 UI 在 Issue 3」）；`initState`（約 147）與 `didUpdateWidget`（約 189，在 `widget.prefs != oldWidget.prefs` 的 `setState` 內）皆已同步 `widget.prefs.headingFontFamily`；`_currentDraft`（約 297）已有 `headingFontFamily: _headingFontFamily`；`_notifyChanged()` 只是 `widget.onChanged(_currentDraft)`。**目前沒有任何地方寫入 `_headingFontFamily`**（只讀不寫）。 |
| 字型卡片位置 | `_buildFontFamilyDropdown()`（約 1124）由 `_buildTextContentTab()`（「文字」分頁，`ListView` 第一個子項，約 452）呼叫；是一張 `EBFieldCard` → `Column`：`Row[Text(標籤), SizedBox(12), Expanded(DropdownButton<String?>(key reader_settings_font_family, isExpanded: true, value: fonts.effectiveFamily(_fontFamily), items: [null→readerSettingsUseBookFontLabel, ...builtInFonts, ...customFonts]))]`，其後 `if (builtInFonts.isEmpty)` 顯示 `reader_settings_download_fonts_hint`。 |
| Windows／E-Ink 版面 | 該卡片**沒有 Slider／`EBStepper`**（步進器只出現在 `_buildSliderRow`，約 1079、1285 行）；字型卡片在一般主題與 E-Ink 主題結構相同，Windows 桌面版與手機走同一個 `ReaderSettingsSheet`（`reader_settings_sheet.dart` 內無 `Platform.isWindows` 分支）。新增一列下拉不涉及 E-Ink 專屬分支，但會讓「文字」分頁變高約 60px：既有測試「版面設定面板高度跟最高分頁一樣…」斷言面板高度 < 1000 且各分頁等高（IndexedStack 取最高者），須在本張回歸。 |
| 刪除重置流程 | `_resetToBookDefault()`（約 1784，「重設為本書原樣式」）只清字級／字重／行距／段落間距／首行縮排／字距六欄，**本來就不動 `_fontFamily` 與 `_headingFontFamily`**；Issue 1 已有測試「『重設為本書原樣式』不清空標題字型（epic-68 Issue 1）」。本張無需改此流程。 |
| 開面板分派 | `reader_screen.dart`：`onLayoutTap: _isFixedLayout ? _openFxlSettings : (… _openLayoutSettings)`（約 2126）；PDF 分支 `onLayoutTap: _openBookFlow.isRendered ? _openPdfSettings : null`（約 2549）；只有 `_openLayoutSettings`（約 947）建構 `ReaderSettingsSheet`（全 repo 唯一建構處，除測試外）。`_openFxlSettings`（約 1016）建構 `FxlSettingsSheet`，`_openPdfSettings`（約 1003）建構 `PdfSettingsSheet`。 |
| FXL／PDF 面板無字型 UI（證據） | `grep -n "fontFamily\|字型"`：`fxl_settings_sheet.dart` 只在 `_notifyChanged()` 整列重建中出現 `fontFamily: widget.prefs.fontFamily`／`headingFontFamily: widget.prefs.headingFontFamily`（保留用），無任何下拉或字型字串；`pdf_settings_sheet.dart` 完全沒有 `fontFamily`（走 `copyWith`）。兩者本來就不顯示字型控制項，本張只補負向測試鎖定。 |
| **書架「版面覆寫」面板（評估）** | `library_screen.dart`（約 1944 `_save`）的版面覆寫面板**只有「書寫方向」與「翻頁模式」兩個控制項**，沒有任何字型下拉或字型標籤（grep `readerSettingsFont*`／`availableFonts` 在 `library_screen.dart` 無命中，只有 `_save` 整列重建時 `fontFamily`／`headingFontFamily` 原樣帶回，Issue 1 已加測試）。**結論：不需要、也不新增標題字型下拉。** 版面預設集畫面（`layout_preset_*`）只顯示「字級／行距／書寫方向」摘要（`_presetSummary`），不顯示字型，無標籤受影響。 |
| 其他引用 `readerSettingsFontFamilyLabel` 處 | `grep -rn readerSettingsFontFamilyLabel lib test integration_test`：除四份 arb 與產生檔外，**只有 `reader_settings_sheet.dart:1134` 一處使用**；`test/`、`integration_test/` 皆未直接引用該 key。 |
| l10n 設定 | `app/l10n.yaml`：`arb-dir: lib/l10n`、`template-arb-file: app_zh_TW.arb`、`output-localization-file: app_localizations.dart`、`output-class: AppLocalizations`、`output-dir: lib/l10n`、`preferred-supported-locales: ["zh_TW"]`。四份 arb：`app_zh_TW.arb`（樣板，每個 key 帶 `@key` 的 description）、`app_zh.arb`（須與 zh_TW **逐字相同**，見 `arb_consistency_test` 的 `zhMirrorViolations`）、`app_zh_CN.arb`、`app_en.arb`（後三者無 `@key` 區塊）。 |
| 產生檔是否進版控 | **是**：`git ls-files lib/l10n` 含 `app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`（zh_TW／zh_CN 的字串在 `app_localizations_zh.dart` 內以子類別產生）。工作樹為 CRLF（`file` 顯示 CRLF），`gen-l10n` 產出可能是 LF，commit 前須確認 `git diff --stat` 只有新增／修改的 key 相關行，不是整檔改動。 |
| 現有文案 | `readerSettingsFontFamilyLabel`：zh_TW／zh 「字型」、zh_CN 「字体」、en 「Font」；`readerSettingsUseBookFontLabel`：「使用書本內建字型」／「使用书本内建字体」／「Use book's built-in font」；`readerSettingsDownloadMoreFontsHint`：「到「字型管理」下載更多字型」（**本張不改**）。 |
| 依賴「字型」標籤文案的既有斷言（`test/screens/reader_settings_sheet_test.dart`，以字串定位） | (1) `'正體中文介面下字型標籤與欄數「單欄」選項正確渲染'`：`expect(find.text('字型'), findsOneWidget);`；(2) `'簡體中文介面下字型標籤與欄數「单栏」選項正確以簡體渲染'`：`expect(find.text('字体'), findsOneWidget);`＋`expect(find.text('字型'), findsNothing);`；(3) `'英文介面下字型標籤與欄數「Single」選項正確以英文渲染'`：`expect(find.text('Font'), findsOneWidget);`＋`expect(find.text('字型'), findsNothing);`。三者皆為 `find.text` 精確比對，標籤改為「主字型」／「主字体」／「Body font」後會失敗，須同步更新。 |
| 其他字型測試（行為不變，須回歸） | `reader_settings_font_family` 在 `reader_settings_sheet_test.dart` 約 15 處、`reader_screen_test.dart` 一處（開版面設定後展開字型下拉，`find.text('測試自訂字型'), findsWidgets`）。新增的標題下拉在**關閉狀態**下，其所有選項仍會因 `DropdownButton` 內部的 `IndexedStack` 存在於 widget tree，故凡 `find.text('思源黑體')` 等寫成 `findsOneWidget` 的斷言會變成多個；實查 `reader_settings_sheet_test.dart` 內字型名稱斷言皆為 `findsWidgets`／`findsNothing`（`findsOneWidget` 的字型名稱斷言只在 `font_management_screen_test.dart`，與本面板無關），預期不受影響，但 Task 2 仍須跑整個檔案確認。 |
| 提示文字 | `readerSettingsDownloadMoreFontsHint` 的 Text 帶 `Key('reader_settings_download_fonts_hint')`，放在卡片 Column 最後（`if (builtInFonts.isEmpty)`）；既有測試：「一款內建字型都沒下載時…顯示提示」「有已下載…不顯示提示」「英文介面的提示文字」。本張須維持它在卡片中**只出現一次**，且位於兩個下拉之後。 |
| `integration_test` 引用 | `grep -rn "reader_settings_font\|reader_settings_heading\|reader_settings_download_fonts_hint" integration_test`：無命中。新增 Key 不影響 `check_integration_keys.js`（該腳本只找「integration 引用但 lib 已不存在」的 Key），仍照慣例跑一次。 |
| arb 一致性測試 | `test/l10n/arb_consistency_test.dart`：zh／en／zh_CN 與 zh_TW 鍵集合一致、placeholder 一致、zh 與 zh_TW 逐字相同、en 不得與 zh_TW 相同或含中文（除白名單）。新 key 的 en 文案為英文，不需入白名單。 |

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **文案（定案）**：

  | key | zh_TW／zh | zh_CN | en |
  |---|---|---|---|
  | `readerSettingsFontFamilyLabel`（既有，改文案） | 主字型 | 主字体 | Body font |
  | `readerSettingsHeadingFontFamilyLabel`（新） | 標題字型 | 标题字体 | Heading font |
  | `readerSettingsFollowBodyFontLabel`（新） | 跟隨主字型 | 跟随主字体 | Same as body font |

  `readerSettingsUseBookFontLabel`（主字型第一項）與 `readerSettingsDownloadMoreFontsHint` **不改**。zh_TW 的兩個新 key 與改動的 key 的 `@key.description` 須同步（描述「主字型」「標題字型」「第一項」語意）。
- **選項語意（spec §4、D10）**：標題下拉選項清單與主字型完全相同（內建已下載字型＋自訂字型），僅第一項為 `value: null`、文字「跟隨主字型」。目前值 `fonts.effectiveFamily(_headingFontFamily)`；`onChanged` 寫 `_headingFontFamily` 並 `_notifyChanged()`；`_currentDraft`／`initState`／`didUpdateWidget` 已在 Issue 1 完成，**不要重複修改**。
- **不改寫偏好（ADR 0035）**：標題字型不可用時只影響顯示（下拉顯示「跟隨主字型」）；`_headingFontFamily` 草稿值保留原樣，使用者改其他欄位時 `onChanged` 帶出的仍是原值。
- **不順手改**：`_resetToBookDefault`、下載提示、主字型的選項與行為、`_buildSliderRow`。共用選項建構僅是把既有 `items:` 清單抽成私有方法供兩個下拉使用，行為不變（既有主字型測試須全綠作為證據）。
- **測試範圍（CLAUDE.md）**：只跑觸及的測試檔；**本張不跑完整 `flutter test`**（Issue 4 才跑）。
- **每個 Task 結束都必須 commit，且該 commit 可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**（紅燈只存在於 Task 內部，不 commit）。
- **Windows 環境**：Node 步驟用 PowerShell 工具；`node --version` 可執行（v24 以上，本機實測 v26 也可）即可，不必強求 `PNPM_HOME`。多數檔案是 CRLF：Edit 的 `old_string` 不要含換行；不對整個既有檔跑 `dart format`。arb 新增行以 Edit 帶換行時可能產生 LF 混入，Task 1 Step 4 以 `git diff --stat` 檢查。
- **Git**：commit 訊息正體中文、**不加 `Co-Authored-By`**；分支 `feat/epic-68-heading-font`（已存在）；`git add` 一律明確列檔，**絕不** `git add app`／`-A`／`.`，**絕不**加入 `.claude/settings.json` 或 `app/android/app/src/main/assets/foliate/legacy/` 下任何檔案（工作樹有 LF／CRLF 假 diff，不屬本張）。計畫與實作同分支同 PR。

## Review Focus

1. **標籤文案連動**：三份既有斷言（正體／簡體／英文）更新、且四份 arb 與三個產生檔一致。→ Task 1。
2. **不可用字型不改寫偏好**：顯示「跟隨主字型」但草稿保留原值；字型變可用後自然恢復。→ Task 2 測試 7、8、9。
3. **選項清單與主字型一致、第一項文字不同**：以 `items.map(value)` 比對，不靠 `find.text`（被 IndexedStack 干擾）。→ Task 2 測試 3。
4. **版面**：窄螢幕（412）＋過長自訂字型名稱不 overflow；E-Ink 模式；「最高分頁」高度測試。→ Task 2 測試 12、13。
5. **FXL／PDF 不顯示**：負向測試；且 `FxlSettingsSheet` 不清空標題字型（Issue 1 已有，本張回歸）。→ Task 3。
6. **範圍**：`git diff <Issue 2 收尾 commit>..HEAD --stat -- app/lib` 只應出現 `reader_settings_sheet.dart`、四份 arb、三個 `app_localizations*.dart`，不得出現 `main.js`、`foliate_reader_view.dart`、`reader_screen.dart`、資料庫檔、`custom_fonts_repository.dart`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/l10n/app_zh_TW.arb` | 修改 | 樣板：改 `readerSettingsFontFamilyLabel`；新增 2 key（含 `@` description） |
| `app/lib/l10n/app_zh.arb` | 修改 | 與 zh_TW 逐字相同的字串（無 `@` 區塊，比照現況） |
| `app/lib/l10n/app_zh_CN.arb` | 修改 | 簡體 |
| `app/lib/l10n/app_en.arb` | 修改 | 英文 |
| `app/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` | 重新產生 | `flutter gen-l10n`，不手改 |
| `app/lib/screens/reader_settings_sheet.dart` | 修改 | 抽共用選項建構、新增標題字型下拉、更新 `_headingFontFamily` 註解 |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改 | 更新三份標籤斷言；新增 group「標題字型下拉（epic-68 Issue 3）」 |
| `app/test/screens/fxl_settings_sheet_test.dart` | 修改 | 負向：不顯示標題字型下拉 |
| `app/test/screens/pdf_settings_sheet_test.dart` | 修改 | 負向：不顯示標題字型下拉 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 端到端：面板選標題字型 → 偏好儲存且 `FoliateReaderView.headingFontFamily` 更新；補 Issue 2 審查 M1 |
| `docs/epics/epic-68-heading-font/reports/issue-3-report.md` | 新增 | 目視確認報告（先放待填範本，實作者填寫） |
| `docs/epics/epic-68-heading-font/issues.md`、`epic.md` | 修改 | 狀態與進度 |

測試字串統一：主字型 `'SourceHanSerifTC'`、標題字型 `'TaiwanPearl'`（顯示名「台灣圓體」）、自訂字型 `CustomFont(id: 1, displayName: '我的自訂字型', familyName: 'MyCustomFamily', fontUri: 'content://example/font1')`。測試名稱末尾標註（epic-68 Issue 3）。

---

### Task 0：提交本計畫

**Files：** `docs/epics/epic-68-heading-font/plans/plan-issue-3.md`

- [x] **Step 1：** `git branch --show-current` 應為 `feat/epic-68-heading-font`。
- [x] **Step 2：** 只提交本計畫：
  ```bash
  git add docs/epics/epic-68-heading-font/plans/plan-issue-3.md
  git commit -m "docs(epic-68): Issue 3 設定面板標題字型實作計畫"
  ```

---

### Task 1：l10n 文案（四份 arb＋產生檔）與既有標籤斷言

> 本 Task 先讓既有標籤斷言對齊新文案（紅），再改 arb 並重新產生（綠）。新 key 在 Task 2 才被使用，產生出未使用的 getter 不影響 analyze。

**Files：**
- 修改：`app/test/screens/reader_settings_sheet_test.dart`
- 修改：`app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- 重新產生：`app/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`

- [x] **Step 1（紅，先改測試）：** 在 `reader_settings_sheet_test.dart` 以字串定位修改三個測試：
  - `'正體中文介面下字型標籤與欄數「單欄」選項正確渲染'`：`expect(find.text('字型'), findsOneWidget);` → `expect(find.text('主字型'), findsOneWidget);`（測試名稱維持，可在名稱中的「字型標籤」改為「主字型標籤」）。
  - `'簡體中文介面下字型標籤與欄數「单栏」選項正確以簡體渲染'`：`find.text('字体')` → `find.text('主字体')`；其下 `find.text('字型'), findsNothing` 保留。
  - `'英文介面下字型標籤與欄數「Single」選項正確以英文渲染'`：`find.text('Font')` → `find.text('Body font')`；其下 `find.text('字型'), findsNothing` 保留。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/screens/reader_settings_sheet_test.dart --plain-name "字型標籤與欄數"
  ```
  預期：三個測試失敗（找不到「主字型」「主字体」「Body font」）。
- [x] **Step 3（綠，改 arb）：** 以 Edit（字串定位，`old_string` 不含換行）：
  - `app_zh_TW.arb`：`"readerSettingsFontFamilyLabel": "字型",` → `"readerSettingsFontFamilyLabel": "主字型",`；其 `@readerSettingsFontFamilyLabel` description 改為「版面設定「文字」分頁中主字型下拉選單左側的標籤（epic-68 起與「標題字型」區分）」。在 `@readerSettingsFontFamilyLabel` 區塊之後新增：
    ```json
    "readerSettingsHeadingFontFamilyLabel": "標題字型",
    "@readerSettingsHeadingFontFamilyLabel": {
      "description": "版面設定「文字」分頁中標題字型下拉選單左側的標籤（epic-68）"
    },
    "readerSettingsFollowBodyFontLabel": "跟隨主字型",
    "@readerSettingsFollowBodyFontLabel": {
      "description": "標題字型下拉選單第一項：標題沿用主字型，不另指定字型（epic-68）"
    },
    ```
  - `app_zh.arb`：改 `"readerSettingsFontFamilyLabel": "主字型",`，並在其後新增 `"readerSettingsHeadingFontFamilyLabel": "標題字型",`、`"readerSettingsFollowBodyFontLabel": "跟隨主字型",`（與 zh_TW 字串逐字相同；key 順序與 zh_TW 一致）。
  - `app_zh_CN.arb`：`"主字体"`、`"标题字体"`、`"跟随主字体"`。
  - `app_en.arb`：`"Body font"`、`"Heading font"`、`"Same as body font"`。
- [x] **Step 4：重新產生並檢查：**
  ```bash
  flutter gen-l10n
  git diff --stat -- lib/l10n
  ```
  預期：三個 `app_localizations*.dart` 與四份 arb 有變動；`app_localizations.dart` 新增兩個 abstract getter（含 description 文件註解）、`_en.dart` 與 `_zh.dart` 各增相應 override（zh 檔含 zh、zh_CN、zh_TW 三個子類別）。索引為 LF、`core.autocrlf=true`，產生檔不會造成整檔 diff；以 `git diff --stat` 確認 diff 合理即可，不需 `--renormalize`（審查 M1）。
- [x] **Step 5（確認綠）：**
  ```bash
  flutter test test/screens/reader_settings_sheet_test.dart test/l10n/arb_consistency_test.dart
  flutter analyze
  ```
  預期：全綠（既有字型相關測試不受影響，主字型下拉行為尚未改動）；`No issues found!`。
- [x] **Step 6：** 檢查範圍並 commit（明確列檔）：
  ```bash
  git status --short
  git add app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_localizations.dart app/lib/l10n/app_localizations_en.dart app/lib/l10n/app_localizations_zh.dart app/test/screens/reader_settings_sheet_test.dart
  git commit -m "feat(epic-68): l10n 主字型標籤改文案並新增標題字型、跟隨主字型字串"
  ```

---

### Task 2：`ReaderSettingsSheet` 標題字型下拉

**Files：**
- 修改：`app/lib/screens/reader_settings_sheet.dart`
- 修改：`app/test/screens/reader_settings_sheet_test.dart`

- [x] **Step 1（紅，先寫測試）：** 在 `reader_settings_sheet_test.dart` 新增 `group('標題字型下拉（epic-68 Issue 3）', () { ... })`，放在既有「字型選單合併顯示內建 2 款與傳入的自訂字型清單」測試之後（以字串定位）。group 內定義小 helper `Finder headingKey() => find.byKey(const Key('reader_settings_heading_font_family'));` 與 `DropdownButton<String?> dd(WidgetTester t, Finder f) => t.widget<DropdownButton<String?>>(f);`。測試（皆用 `_pumpSheet`，自訂字型用上列統一字串）：
  1. `預設顯示標題字型下拉與標籤，目前值為 null（跟隨主字型）`：`BookReaderPrefs()`；`headingKey()` `findsOneWidget`；`find.text('標題字型')` `findsOneWidget`；`dd(headingKey()).value` `isNull`；`dd(...).isExpanded` `isTrue`。
  2. `主字型標籤為「主字型」，且不再有單獨的「字型」標籤`：`find.text('主字型')` `findsOneWidget`；`find.text('字型')` `findsNothing`。
  3. `標題字型選項清單與主字型一致，僅第一項文字不同`：傳 `customFonts: [我的自訂字型]`；`final h = dd(headingKey()).items!; final b = dd(find.byKey(const Key('reader_settings_font_family'))).items!;`，`expect(h.map((e) => e.value).toList(), b.map((e) => e.value).toList())`；`h.first.value` `isNull` 且 `b.first.value` `isNull`；`(h.first.child as Text).data` 為 `'跟隨主字型'`、`(b.first.child as Text).data` 為 `'使用書本內建字型'`；`h.map((e) => e.value)` 含 `'MyCustomFamily'`。（不用 `find.text` 比對選項，因 `DropdownButton` 內部 `IndexedStack` 會讓關閉狀態的選項也在 tree 中。）
  4. `選擇標題字型後 onChanged 帶出新值，主字型與其他欄位不變`：prefs `BookReaderPrefs(fontFamily: 'SourceHanSerifTC', fontSize: 1.25)`；`dd(headingKey()).onChanged!('TaiwanPearl'); await tester.pump();` → `result!.headingFontFamily == 'TaiwanPearl'`、`result.fontFamily == 'SourceHanSerifTC'`、`result.fontSize == 1.25`。
  5. `選「跟隨主字型」回傳 headingFontFamily=null，主字型保留`：prefs `BookReaderPrefs(fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')`；`onChanged!(null)` → `result` 非 null、`result!.headingFontFamily` `isNull`、`result.fontFamily == 'SourceHanSerifTC'`。
  6. `實際點選標題字型選單與選項可寫入偏好（含自訂字型）`：`tester.tap(headingKey())`、`pumpAndSettle()`、`tester.tap(find.text('我的自訂字型').last)`、`pumpAndSettle()` → `result!.headingFontFamily == 'MyCustomFamily'`；再開啟選單點 `find.text('跟隨主字型').last` → `result!.headingFontFamily` `isNull`。
  7. `標題字型不可用時顯示「跟隨主字型」，且不改寫偏好（ADR 0035）`：prefs `BookReaderPrefs(fontFamily: 'SourceHanSansTC', headingFontFamily: 'TaiwanPearl')`（以 `AppFont` 實際 familyName 為準，若不同則用 `AppFont.sourceHanSans.familyName`），`installedFonts: {AppFont.sourceHanSans}`（台灣圓體未下載）；斷言 `tester.takeException()` `isNull`、`dd(headingKey()).value` `isNull`、接著呼叫主字型 `onChanged!(null)` 觸發一次通知，`result!.headingFontFamily` 仍為 `'TaiwanPearl'`（草稿保留原值，沒有被顯示用的 null 覆蓋；此為主斷言，不做「onChanged 未被呼叫」計數，審查 M2）。
  8. `標題字型為不認得的名稱時面板正常開啟且顯示「跟隨主字型」`：`BookReaderPrefs(headingFontFamily: 'NoSuchFont')` → `takeException` null、`dd(headingKey()).value` null。
  9. `字型之後變成可用，標題字型自然恢復顯示（不需重設）`：先以 `installedFonts: {AppFont.sourceHanSans}` pump（值 null），再以同一份 prefs、`installedFonts: AppFont.values.toSet()` 再呼叫一次 `_pumpSheet`（沿用同一棵 widget 樹、State 保留；測試註解須寫明「依賴同型別重 pump 以保留 State」，審查 M3）→ `dd(headingKey()).value == 'TaiwanPearl'`。
  10. `prefs 外部變動時（例如套用預設集）標題字型下拉同步更新`：先 pump `BookReaderPrefs()`，再以 `BookReaderPrefs(headingFontFamily: 'TaiwanPearl')` 重 pump（註解同樣寫明依賴重 pump 時 State 保留，審查 M3）→ 值為 `'TaiwanPearl'`（驗證 `didUpdateWidget` 路徑有被下拉實際使用）。
  11. `下載提示只出現一次且位於標題字型下拉之後，文案不變`：`installedFonts: const {}`；`find.byKey(const Key('reader_settings_download_fonts_hint'))` `findsOneWidget`、文字 `'到「字型管理」下載更多字型'`；`tester.getTopLeft(hint).dy > tester.getTopLeft(headingKey()).dy`。有已下載字型時 `findsNothing`（既有測試保留，不重複）。
  12. `簡體與英文介面：標題字型標籤與「跟隨」選項正確`：`locale: const Locale('zh','CN')` → `find.text('标题字体')` `findsOneWidget`、`(dd(headingKey()).items!.first.child as Text).data == '跟随主字体'`；`locale: const Locale('en')` → `find.text('Heading font')` `findsOneWidget`、第一項 `'Same as body font'`。
  13. `窄螢幕（412 寬）與過長自訂字型名稱時，標題字型下拉不 overflow；E-Ink 模式同樣可顯示`：仿照既有「自訂字型清單中存在過長顯示名稱時…不應造成 RenderFlex overflow」測試的 `pumpWidget` 寫法（`physicalSize 412×1800`、過長 `displayName`），prefs 設 `headingFontFamily: 'CustomLongFontName'`，`takeException` null；另用 `_pumpSheet(..., isEinkMode: true)` 確認 `headingKey()` `findsOneWidget` 且無例外。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/screens/reader_settings_sheet_test.dart --plain-name "標題字型下拉"
  ```
  預期：除「測試 2」可能已綠（Task 1 已改標籤）外，其餘因找不到 `reader_settings_heading_font_family`（`findsOneWidget` 失敗／`widget` 找不到）而紅。
- [x] **Step 3（綠，實作）：** 修改 `reader_settings_sheet.dart`（以字串定位）：
  1. 抽出私有方法 `List<DropdownMenuItem<String?>> _fontMenuItems(AppLocalizations l10n, String firstItemLabel)`：回傳 `[DropdownMenuItem(value: null, child: Text(firstItemLabel, overflow: TextOverflow.ellipsis)), ...widget.availableFonts.builtInFonts.map(...), ...widget.availableFonts.customFonts.map(...)]`，內容逐字取自既有主字型下拉的 `items:`；主字型改為 `items: _fontMenuItems(l10n, l10n.readerSettingsUseBookFontLabel)`。**行為與既有完全相同。**
  2. 在 `_buildFontFamilyDropdown()` 的 `Row`（主字型）之後、`if (builtInFonts.isEmpty)` 提示之前，新增標題字型列：
     ```dart
     // epic-68 Issue 3：標題字型下拉。選項與主字型相同，第一項為「跟隨主字型」（null）。
     // 目前值走 effectiveFamily：標題字型不可用時只影響顯示，不改寫偏好（ADR 0035）。
     const SizedBox(height: 8),
     Row(
       children: [
         Text(l10n.readerSettingsHeadingFontFamilyLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
         const SizedBox(width: 12),
         Expanded(
           child: DropdownButton<String?>(
             key: const Key('reader_settings_heading_font_family'),
             isExpanded: true,
             value: fonts.effectiveFamily(_headingFontFamily),
             items: _fontMenuItems(l10n, l10n.readerSettingsFollowBodyFontLabel),
             onChanged: (value) => setState(() {
               _headingFontFamily = value;
               _notifyChanged();
             }),
           ),
         ),
       ],
     ),
     ```
     （標籤與主字型標籤寬度不同導致兩個下拉左緣不齊，屬可接受的視覺細節；若目視確認覺得突兀，另案處理，不在本張擴大。）
  3. 更新 `_headingFontFamily` 欄位上方註解：由「Issue 1 僅帶入草稿，下拉 UI 在 Issue 3」改為「標題字型（epic-68）：null＝跟隨主字型；下拉在字型卡片，`_currentDraft`／`didUpdateWidget` 同步」。
  4. 提示文字 `readerSettingsDownloadMoreFontsHint` 保持在卡片最後，不動。
- [x] **Step 4（確認綠）：**
  ```bash
  flutter test test/screens/reader_settings_sheet_test.dart
  flutter analyze
  ```
  預期：整個檔案全綠（含既有「面板高度跟最高分頁一樣…」< 1000 與各分頁等高、字型相關舊測試、Issue 1 的「不清空」測試）；`No issues found!`。並把實測「文字」分頁高度（`textTabHeight`）與是否為最高分頁記進執行紀錄（審查 M6）。若「面板高度…」失敗，代表文字分頁增高後超出預期，須回報而非調高門檻（先確認 < 1000 的數值餘裕）。
- [x] **Step 5（反向驗證，不 commit）：** 暫時把標題下拉的 `value:` 改成 `_headingFontFamily`（不經 `effectiveFamily`）、`installedFonts` 不含該字型的測試 7、8 必須因 `DropdownButton` assert／值不符而紅；還原。再暫時把 `onChanged` 內的 `_notifyChanged()` 拿掉，測試 4、5、6 必紅；還原。`git diff` 確認已還原。
- [x] **Step 6：** commit：
  ```bash
  git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
  git commit -m "feat(epic-68): 版面設定新增標題字型下拉，選項與主字型共用"
  ```

---

### Task 3：負向與整合回歸測試（FXL／PDF 不顯示、端到端、Issue 2 審查 M1）

> 本 Task 只新增測試（鎖定既有行為與 Task 2 的整合），不改 `lib/`；新增測試一加入即應為綠。反向驗證見 Step 4。

**Files：**
- 修改：`app/test/screens/fxl_settings_sheet_test.dart`、`app/test/screens/pdf_settings_sheet_test.dart`、`app/test/screens/reader_screen_test.dart`

- [ ] **Step 1：FXL／PDF 負向測試。**
  - `fxl_settings_sheet_test.dart`（先 `grep -n "^Future<void> _pump" test/screens/fxl_settings_sheet_test.dart` 確認其 helper 簽章，沿用）：新增 `FxlSettingsSheet 不顯示字型與標題字型下拉，且既有標題字型不被清空（epic-68 Issue 3）`：prefs `BookReaderPrefs(fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')`；`find.byKey(const Key('reader_settings_heading_font_family'))` 與 `find.byKey(const Key('reader_settings_font_family'))` 皆 `findsNothing`；觸發一個既有可操作控制項（例如「永遠雙頁」，比照該檔既有 `點擊「永遠雙頁」觸發 onChanged` 測試的點法）後，`result!.headingFontFamily == 'TaiwanPearl'`（審查 M4：Issue 1 已有保留測試，只在既有「切換全螢幕後標題字型不被清空」測試所在 group 補兩個 Key 的 `findsNothing`，不另寫完整觸發測試）。
  - `pdf_settings_sheet_test.dart`：新增 `PdfSettingsSheet 不顯示標題字型下拉（epic-68 Issue 3）`：`_pumpSheet(tester, const BookReaderPrefs(headingFontFamily: 'TaiwanPearl'), (_) {})` 後兩個 Key 皆 `findsNothing`。
- [ ] **Step 2：端到端測試（`reader_screen_test.dart`）。** 以既有測試 `提供 customFontsRepository 時，開啟版面設定顯示自訂字型選項`（約 7925）為範本，新增 `在版面設定選擇標題字型後，偏好被儲存且 FoliateReaderView 收到標題字型（epic-68 Issue 3）`：`FakeCustomFontsRepository` 插入 `測試自訂字型`／`TestCustomFamily`，沿用檔內 group 級 `prefsManager`（`prefsManager.saveBookPrefs('b1', const BookReaderPrefs())`，不新建 Fake；審查 M5），開 `sample.epub`、`onLayoutResolved` 回報流式後點 `reader_chrome_layout_button` 開面板；`tester.widget<DropdownButton<String?>>(find.byKey(const Key('reader_settings_heading_font_family'))).onChanged!('TestCustomFamily'); await tester.pump();` 後斷言 `prefsManager.bookPrefsByBookId['b1']!.headingFontFamily == 'TestCustomFamily'`（取值方式比照該 group 既有 `bookPrefsByBookId` 斷言）、`tester.widget<FoliateReaderView>(find.byType(FoliateReaderView)).headingFontFamily == 'TestCustomFamily'`；再 `onChanged!(null)` 後兩者皆為 null。此測試把 Issue 2（傳遞）與 Issue 3（UI）接起來。
- [ ] **Step 3：補 Issue 2 審查 M1。** 在 `reader_screen_test.dart` Issue 2 的傳遞 group（以字串 `epic-68` 搜尋定位）新增：`CBZ 明確宣告 isFixedLayout=false 時仍傳 null（epic-68，審查 M1）`：`filePath: 'test/fixtures/sample.cbz'`、`isFixedLayout: false`、種子 `headingFontFamily: 'TaiwanPearl'` 並使其可用，`readerView(tester).headingFontFamily` `isNull`（比照同 group CBZ 既有測試的 pump 寫法）。此為既有行為的測試鎖定。
- [ ] **Step 4（反向驗證，不 commit）：** 暫時在 `fxl_settings_sheet.dart` 的 `build` 內插入一個帶 `Key('reader_settings_heading_font_family')` 的 `SizedBox`，確認 FXL 負向測試轉紅後還原（`git diff -- app/lib` 應為空）。
- [ ] **Step 5：** 跑觸及檔並 commit：
  ```bash
  flutter test test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart
  flutter test test/screens/reader_screen_test.dart
  flutter analyze
  git add app/test/screens/fxl_settings_sheet_test.dart app/test/screens/pdf_settings_sheet_test.dart app/test/screens/reader_screen_test.dart
  git commit -m "test(epic-68): 補標題字型下拉的 FXL／PDF 負向與端到端測試"
  ```

---

### Task 4：靜態檢查與本張觸及測試彙整

- [ ] **Step 1：範圍檢查。**
  ```bash
  git diff <Issue 2 收尾 commit baa23975>..HEAD --stat -- app/lib
  ```
  預期只有 `app/lib/screens/reader_settings_sheet.dart`、四份 arb、三個 `app_localizations*.dart`。不得出現 `foliate/`、`foliate_reader_view.dart`、`reader_screen.dart`、`custom_fonts_repository.dart`、資料庫檔。
- [ ] **Step 2：靜態與慣例檢查（PowerShell；`node` 可執行即可）：**
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app
  flutter analyze
  node tool/check_l10n_hardcoded_strings.js
  node tool/check_integration_keys.js
  ```
  預期：`No issues found!`；兩個腳本 PASS／exit 0。若 `check_l10n_hardcoded_strings.js` 抱怨新測試的 `MaterialApp` 缺 locale，補 `locale: const Locale('zh','TW')`。
- [ ] **Step 3：觸及測試檔最終彙整（不是完整 `flutter test`）：**
  ```bash
  flutter test test/screens/reader_settings_sheet_test.dart test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart test/l10n/arb_consistency_test.dart
  flutter test test/screens/reader_screen_test.dart
  ```
  預期全綠。記錄通過數供審查報告引用。
- [ ] **Step 4：** 本 Task 無檔案變更，不 commit；若 Step 2 因補 locale 而改檔，以明確列檔 commit：`fix(epic-68): 補測試 locale 以通過硬編碼字串檢查`。

---

### Task 5：Windows 桌面版目視確認與報告

> 這是 Issue 2 移來的真實 EPUB 目視確認。目的：證明「選了標題字型後章名字形真的變」「改回跟隨主字型恢復」「PDF／FXL 面板不出現下拉」。實作者若無法在目前環境互動操作桌面 App（例如純終端、無法看畫面），**必須在報告明載限制**，並以替代證據補足（見 Step 4），不可宣稱已目視確認。

**Files：** 新增 `docs/epics/epic-68-heading-font/reports/issue-3-report.md`

- [ ] **Step 1：先建立報告範本並單獨 commit（待填）。** 建立目錄與檔案，內容：
  ```markdown
  # Issue 3 目視確認報告：標題字型 UI

  - 日期：（待填）
  - 環境：Windows 桌面版（`flutter run -d windows`）／分支 `feat/epic-68-heading-font`／commit （待填）
  - 實作者是否能互動操作桌面 App：（待填：是／否；若否，說明限制與替代證據）

  ## 測試書籍
  | 書籍 | 來源 | 含 h1–h6 | 備註 |
  |---|---|---|---|
  | （待填：真實流式 EPUB，章名為 h1／h2，最好有 `h1>span` 或 `h2>a`） | | | |
  | （待填：PDF） | | | |
  | （待填：FXL EPUB，例如 `test/fixtures/sample_fixed_layout.epub`） | | | |

  ## 檢查項目
  | # | 項目 | 預期 | 結果（通過／失敗／未驗證） | 證據（截圖檔名或描述） |
  |---|---|---|---|---|
  | 1 | 流式 EPUB 開啟版面設定「文字」分頁，字型卡片顯示「主字型」與「標題字型」兩個下拉 | 兩個下拉，標籤正確，下載提示（若無已下載字型）仍只一個 | | |
  | 2 | 主字型選 A、標題字型選 B（兩者外觀明顯不同，例如明體與圓體） | 章名（h1／h2）字形為 B，內文為 A | | |
  | 3 | 章名內有 `span`／`a` 的書 | 內層文字同為標題字型 | | |
  | 4 | 標題字型改回「跟隨主字型」 | 章名恢復為主字型，不需重開書 | | |
  | 5 | 主字型為「使用書本內建字型」＋標題字型 B | 章名為 B，內文為書本字型 | | |
  | 6 | 設定「停用書本 CSS」開關 | 標題字型仍勝出 | | |
  | 7 | 關書再開 | 標題字型設定保留 | | |
  | 8 | 到字型管理刪除標題字型使用的自訂字型（若環境可行） | 預期此時標題退回主字型顯示（注意：偏好是否被重置屬 Issue 4，本張只記錄現況） | | |
  | 9 | 開 PDF 的版面設定 | 沒有字型／標題字型下拉 | | |
  | 10 | 開 FXL EPUB 的版面設定 | 沒有字型／標題字型下拉 | | |
  | 11 | 視窗縮窄／E-Ink 模式下字型卡片版面 | 無溢位、可操作 | | |

  ## 發現與限制
  （待填：視覺瑕疵、下拉左緣不齊是否可接受、無法驗證的項目與原因）

  ## 結論
  （待填）
  ```
  ```bash
  git add docs/epics/epic-68-heading-font/reports/issue-3-report.md
  git commit -m "docs(epic-68): Issue 3 目視確認報告範本"
  ```
- [ ] **Step 2：準備真實 EPUB。** 使用者環境中的真實 EPUB（優先選章名為 `h1`／`h2` 者）；若沒有，可用 `app/test/fixtures/sample_multi_chapter.epub` 或 `sample_horizontal.epub` 先確認其章節檔含 `<h1>`（`unzip -p <epub> OEBPS/chapter1.xhtml | grep -i "<h"`），不含則改用 `app/tool/foliate_touch_harness/scenario-heading-font.mjs` 內的最小 EPUB 建構方式另存一本。需有兩款**外觀明顯不同**且已下載的字型（到字型管理下載，或匯入自訂字型）。
- [ ] **Step 3：執行與記錄。** 於 `app/` 以 `flutter run -d windows` 啟動，依報告表格逐項操作並填寫結果；有截圖者存於 scratchpad 並在報告寫檔名（不把截圖放進 repo，除非體積極小且使用者同意）。
- [ ] **Step 4：若無法互動操作** 桌面 App：報告「環境」欄明載原因，並提供替代證據：(a) 重跑 `node app/tool/foliate_touch_harness/scenario-heading-font.mjs`（PATH 上有可用 `node`）全 PASS（證明規則含後代、順序、停用書本 CSS 正確）；(b) Task 2、3 的 widget／端到端測試通過（證明 UI→偏好→`FoliateReaderView` 鏈路）；(c) 明確標示「字形是否真的變化」「PDF／FXL 面板實機外觀」兩項為**未驗證**，留待使用者或之後的真機確認。不得把未驗證項目標為通過。若 Node 與互動操作皆不可用，兩項替代證據皆缺，報告結論須標「Issue 3 目視確認未完成」（審查 M7）；解壓 EPUB 以 `tar -xf` 或 `Expand-Archive`，Windows 不一定有 `unzip`。
- [ ] **Step 5：填寫完成後 commit 報告：**
  ```bash
  git add docs/epics/epic-68-heading-font/reports/issue-3-report.md
  git commit -m "docs(epic-68): Issue 3 目視確認結果"
  ```

---

### Task 6：文件狀態

- [ ] **Step 1：** `issues.md` 表格 Issue 3 狀態改「完成（待 PR）」；`epic.md`「進度」補一行：Issue 3 完成——`ReaderSettingsSheet` 標題字型下拉（`reader_settings_heading_font_family`，選項與主字型共用、第一項「跟隨主字型」＝null、不可用時顯示跟隨且不改寫偏好）、主字型標籤改「主字型」、四份 arb 與產生檔、FXL／PDF 負向測試、端到端測試、目視確認報告 `reports/issue-3-report.md`；註記：書架「版面覆寫」面板與版面預設集畫面無字型控制項，不需標題字型下拉。**不動** `docs/epics.md`、`CLAUDE.md`、`AGENTS.md`（本張不改變其描述的架構事實；主庫 `version` 已在 Issue 1 更新）。
- [ ] **Step 2：commit（明確列檔，不含 `.claude/settings.json`）：**
  ```bash
  git add docs/epics/epic-68-heading-font/issues.md docs/epics/epic-68-heading-font/epic.md
  git commit -m "docs(epic-68): Issue 3 收尾，更新狀態與進度"
  ```
- [ ] **Step 3：** 程式審查（由獨立審查者產出，報告存 `docs/epics/epic-68-heading-font/reviews/review-code-issue-3.md`，依專案慣例審查先出報告、不直接修改）。本張無 PR（Epic 全部 Issue 完成後同一個 PR）。

## 完成標準

1. 流式 Foliate 設定面板的字型卡片有「主字型」與「標題字型」兩個下拉；標題字型第一項「跟隨主字型」＝`null`；選項與主字型一致；選擇後 `onChanged` 帶出新值、選跟隨回傳 null，其他欄位（含主字型）不變。
2. 標題字型不可用（未下載／已刪除／不認得）時下拉顯示「跟隨主字型」，草稿與偏好**不被改寫**；字型變可用後恢復。
3. `FxlSettingsSheet`、`PdfSettingsSheet` 不顯示任何字型下拉（有測試），FXL 面板不清空既有標題字型。
4. 四份 arb 同步、`flutter gen-l10n` 已重新產生且產生檔進版控；`arb_consistency_test` 綠；`check_l10n_hardcoded_strings.js`、`check_integration_keys.js` 通過；`flutter analyze` 乾淨。
5. 既有標籤斷言已更新；下載提示行為不變（仍只一個、位於兩個下拉之後）。
6. `reports/issue-3-report.md` 已填寫；無法驗證的項目明載為未驗證。
7. 本張觸及測試檔全綠；未跑完整 `flutter test`（刻意，Issue 4 才跑）。

## 風險與備註

- **`DropdownButton` 的 `IndexedStack`**：關閉狀態下所有選項文字都在 widget tree，`find.text(選項名)` 在兩個下拉並存後可能比對到多個。本計畫的選項比對一律用 `items.map(value)`，點選用 `.last`；實作時若既有測試在 Task 2 Step 4 意外變紅，先判斷是否為此原因，再改測試的定位方式（不要為了過測試放寬語意）。
- **文字分頁增高**：新增一列約 60px，「面板高度跟最高分頁一樣」測試的 < 1000 門檻需有餘裕；矮螢幕時文字分頁內仍可捲動（既有設計）。
- **兩個下拉左緣不齊**：標籤「主字型」與「標題字型」寬度不同。本張不加固定寬度；目視確認時評估，若使用者覺得突兀另案處理。
- **gen-l10n 行尾**：產生檔工作樹為 CRLF，產出若為 LF 會造成整檔 diff 或 autocrlf 警告，commit 前必須用 `git diff --stat` 確認，不可夾帶整檔改動。
- **刪除自訂字型連動不在本張**：在 Issue 4 之前，刪除標題字型使用的自訂字型時，偏好仍指向已刪字型，由 `effectiveFamily` 退回顯示「跟隨主字型」，不會崩潰也不會顯示錯誤字型；Issue 4 才負責重置與計數。
- **家族名稱含單引號**：沿用主字型既有處理（spec §3.2），本張不擴大。
- **本機 `.claude/settings.json` 與 `legacy/` 假 diff**：工作樹既有，不屬本張，任何 `git add` 都不得包含。

## 審查處理紀錄

### 計畫審查（review-plan-issue-3）Minor 處理

- M1 採納：移除 `--renormalize` 指示，改以 `git diff --stat` 確認。
- M2 採納：測試 7 以「草稿保留 TaiwanPearl」為主斷言，不做 onChanged 計數。
- M3 採納：測試 9、10 註解寫明依賴重 pump 保留 State。
- M4 採納：FXL 負向只補兩個 Key 的 findsNothing。
- M5 採納：端到端沿用檔內 prefsManager。
- M6 採納：實測面板高度記進執行紀錄。
- M7 採納：目視確認做不到時標「未完成」，不宣稱已驗證。
- M8 不處理（Issue 2 既有邊角），僅於報告「發現與限制」記錄。

## 執行紀錄

- Task 1：紅燈＝三個標籤測試失敗（-3）；改 arb＋`flutter gen-l10n` 後 `reader_settings_sheet_test.dart`＋`arb_consistency_test.dart` 129 通過；`git diff --stat -- lib/l10n` 7 檔 61 增 11 刪，無整檔 diff。
- Task 2：紅燈＝新 group 13 測試中 12 紅（測試 2 因 Task 1 已綠）。實作後整檔 138 通過。反向驗證：`value` 不經 `effectiveFamily` → 測試 7、8、9 紅；拿掉 `_notifyChanged()` → 測試 4、5、6 紅；皆已還原。
- 面板高度（審查 M6）：「版面設定面板高度…」測試實測 `textTabHeight`（面板高度）新增下拉前後皆為 988.0（門檻 <1000，餘裕僅 12，但未變動）；「文字」分頁內容在 viewport 738 內 `maxScrollExtent=0`，代表文字分頁不是最高分頁，面板高度由其他分頁決定，故新增一列不影響。註：計畫與測試註解寫的「最高分頁約 700 多」實為面板整體 988。

### 程式審查後處理

（程式審查後填寫。）
