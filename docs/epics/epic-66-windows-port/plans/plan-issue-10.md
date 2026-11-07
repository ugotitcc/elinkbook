# Issue 10：Windows 隱藏手機專屬功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows 版看不到音量鍵翻頁、螢幕方向鎖定、全螢幕模式偏好、PDF 濾鏡、E-Ink 高對比的任何入口，也不再呼叫 Windows 上不存在的 Android 原生 channel；其他平台行為完全不變。

**Architecture:** 在 `lib/platform/platform_support.dart` 新增一個 getter `supportsMobileReaderControls`（Windows 為 `false`）。各畫面用它做 collection-if 隱藏控制項；`ReaderScreen` 用它跳過原生 channel 與 `SystemChrome` 呼叫；`ElinkBookApp` 用它把 E-Ink 強制關閉。不新增字串、不改資料庫、不清除既有偏好值。

**Tech Stack:** Flutter 3.41.9；測試以 `debugDefaultTargetPlatformOverride = TargetPlatform.windows` 切換平台（`flutter test` 預設平台為 Android，既有測試不受影響）。

**Spec:** `docs/epics/epic-66-windows-port/epic.md` 決策 1（隱藏：音量鍵翻頁、E-Ink 高對比與影像濾鏡、螢幕方向鎖定）；`issues.md` 的「Issue 10 範圍／過關條件／單元測試要求」。

## 設計取捨（2026-11-07，請審查時確認）

1. **只用一個 getter。** 五項功能今天的隱藏條件相同，不為每項各建一個旗標。日後某項要在別的平台分開處理時再拆。
2. **「濾鏡」是整個 PDF 分頁。** 對比度、亮度、加粗三項都是 E-Ink 影像濾鏡，所以 Windows 隱藏整個「濾鏡」分頁，不是只藏部分滑桿。
3. **「全螢幕模式」偏好項一律隱藏。** 它是 Android 的 `WindowInsetsController` 沉浸模式；Windows 的 F11（Issue 7）不受影響。
4. **E-Ink 在 `ElinkBookApp` 層強制關閉。** 隱藏開關還不夠：若本機 SharedPreferences 殘留 `true`，主題仍會變成 E-Ink 且使用者無法關掉。
5. **不清除既有資料。** 資料庫已有的 `fullscreen`、`screenOrientationOverride`、`pdfContrast` 等欄位保持原樣；Windows 新安裝沒有這些值，日後有匯入或同步時另開 Issue。

### 已知限制（審查 2026-11-07 確認，本 Issue 不處理）

- 「關於」頁在 Windows 會顯示錯誤文字：`about_screen.dart` 呼叫 Android 專用的 `elinkbook/app_info`（建置時間、系統 WebView 版本），已有 try/catch，不崩潰。實機確認時看到不算本 Issue 漏項，另案處理。
- TXT 封面產生（`book_import_service_impl.dart`）直接讀 `themePreferences.loadEinkMode()`，繞過 `ElinkBookApp` 的強制關閉。Windows 新安裝沒有殘留值，僅是潛在風險。

## Global Constraints

- Flutter 3.41.9，`flutter analyze` 乾淨；不得使用此版本沒有的 API。
- 平台判斷一律走 `defaultTargetPlatform`（`lib/platform/platform_support.dart`），不用 `dart:io` 的 `Platform`。
- Android 與其他平台零改動：既有測試一行都不改；改了既有測試就代表行為變了，停下來重新檢討。
- 不新增、不修改任何 ARB 字串（本 Issue 只隱藏既有控制項）。
- 每個 collection-if 必須連同與被隱藏控制項相鄰的 `Divider`、`SizedBox` 一起包；否則 Windows 會留下連續兩條分隔線或空洞。這無法靠單元測試鎖住，靠 Task 7 實機目視確認。
- `git add` 一律明確列檔。不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`（本機 `pub get` 會改動它們）；不得 commit `pubspec.lock` 的任何變動。
- 提交前跑 `node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`（Windows 的 Node 在 pnpm 內，見記憶 `reference_windows-node-via-pnpm`）。
- Windows 建置需在 PowerShell 設環境變數 `CL=/utf-8`（繁中字碼頁 950，見 `epic.md` 決策 27）。

## Review Focus

1. Windows 上本機殘留 `eink = true`（例如日後設定匯入）：啟動仍用一般主題，使用者看得到正常畫面。（Task 5）
2. Windows 的 PDF 設定面板只剩 2 個分頁：切到「裁切」、左右滑動、關閉再開都不拋 `RangeError`，`TabController.length` 與 `TabBar`、`TabBarView` 子項數一致。（Task 4）
3. Windows 進出閱讀器：兩個 channel 都收到 0 次呼叫，沒有未處理的 `MissingPluginException`。（Task 6）
4. 閱讀預設值畫面在 Windows 隱藏三項後，改動其他開關不會把被隱藏的值（`volumeKeyEnabled`、`screenOrientation`、`fullscreen`）覆寫成預設。（Task 2）
5. Android 預設平台下所有被動到的控制項都還在。（每個 Task 各一條對照測試）

---

### Task 1：`supportsMobileReaderControls`

**Files:**
- Modify: `app/lib/platform/platform_support.dart`
- Test: `app/test/platform/platform_support_test.dart`

**Interfaces:**
- Produces: `bool get supportsMobileReaderControls`（Windows 為 `false`，其他平台為 `true`），後續所有 Task 使用。

- [x] **Step 1: 寫失敗測試。** 在既有 `platform_support_test.dart` 新增 `supportsMobileReaderControls 在 Windows 為 false，Android 與 iOS 為 true`：用 `debugDefaultTargetPlatformOverride` 依序設為 `windows`、`android`、`iOS`，各自 `expect`；`tearDown` 沿用該檔既有的還原寫法。
- [x] **Step 2: 執行確認失敗。** `flutter test test/platform/platform_support_test.dart`，預期編譯失敗（getter 不存在）。
- [x] **Step 3: 實作。** 在 `platform_support.dart` 加 `bool get supportsMobileReaderControls => !isWindowsPlatform;`，附一段中文 doc 註解，列出五項功能（音量鍵、螢幕方向鎖定、全螢幕模式偏好、PDF 濾鏡、E-Ink）。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令，預期全過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/platform/platform_support.dart app/test/platform/platform_support_test.dart
git commit -m "feat(platform): 新增 supportsMobileReaderControls（epic-66 Issue 10 Task 1）"
```

---

### Task 2：閱讀預設值畫面

**Files:**
- Modify: `app/lib/screens/reading_defaults_screen.dart`
- Test: `app/test/screens/reading_defaults_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `supportsMobileReaderControls`。
- Produces: 無新公開介面。Key 不變：`reading_defaults_volume_key_switch`、`reading_defaults_screen_orientation_*`、`reading_defaults_fullscreen_switch`。

- [x] **Step 1: 寫失敗測試。** 在既有檔案新增兩個測試，沿用該檔既有的 `MaterialApp` 與 `FakeReaderPrefsManager` 建構寫法：
  - `Windows 隱藏音量鍵、螢幕方向、全螢幕，其餘開關仍在`：設 `TargetPlatform.windows`（`try/finally` 還原為 `null`），`find.byKey` 斷言 `reading_defaults_volume_key_switch`、`reading_defaults_screen_orientation_lock90`、`reading_defaults_fullscreen_switch` 為 `findsNothing`；`reading_defaults_open_last_book_switch`、`reading_defaults_show_header_switch`、`reading_defaults_show_footer_switch`、`reading_defaults_page_turn_mode_scroll`、`reading_defaults_text_conversion_original` 為 `findsOneWidget`。
  - `Windows 改動其他開關不覆寫被隱藏的值`：`FakeReaderPrefsManager` 以 `volumeKeyEnabled: false`、`screenOrientation: lock90`、`fullscreen: true` 起始；Windows 下點 `reading_defaults_show_header_switch`；斷言假管理器最後儲存的 `reading` 三個值仍是 `false`、`lock90`、`true`。
  - Android 對照由既有測試負責，不重寫。
- [x] **Step 2: 執行確認。** `flutter test test/screens/reading_defaults_screen_test.dart`。第一個測試必須失敗（紅）。第二個是防回歸護欄：既有 `_update` 只用 `copyWith` 改單一欄位，所以它在實作前就會通過，這是預期的，不是測試寫錯。
- [x] **Step 3: 實作。** 在 `reading_defaults_screen.dart` 用 `if (supportsMobileReaderControls) ...[ … ]` 包住：音量鍵 `SwitchListTile`（約第 70 行）、螢幕方向的 section header 與 `RadioGroup`（約第 107～151 行）、全螢幕 `SwitchListTile`（約第 182 行）。其餘不動；已寫回的 `copyWith` 本來就只改自己的欄位。每個 collection-if 連同其前後相鄰的 `Divider` 一起包。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令，新舊測試全過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/screens/reading_defaults_screen.dart app/test/screens/reading_defaults_screen_test.dart
git commit -m "feat(windows): 閱讀預設值畫面隱藏音量鍵、螢幕方向、全螢幕（epic-66 Issue 10 Task 2）"
```

---

### Task 3：流式與固定版面設定面板

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`（全螢幕 `SwitchListTile` 約第 660 行；`_buildScreenOrientationOverrideRow()` 呼叫處約第 708 行）
- Modify: `app/lib/screens/fxl_settings_sheet.dart`（全螢幕 `SwitchListTile` 約第 262 行）
- Test: `app/test/screens/reader_settings_sheet_test.dart`、`app/test/screens/fxl_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `supportsMobileReaderControls`。
- Produces: 無新公開介面。Key 不變：`reader_settings_fullscreen`、`fxl_settings_fullscreen`。

- [x] **Step 1: 寫失敗測試。**
  - `reader_settings_sheet_test.dart` 新增 `Windows 隱藏全螢幕開關與螢幕方向列`：用該檔既有的 `_pumpSheet` 輔助；**先 `await switchToTab(tester, '呈現')`**（兩者都在第 3 個分頁「呈現」，分頁內容是 `IndexedStack`，沒切過去 `find` 一律找不到，測試會假綠），必要時再用該檔既有寫法捲動；然後斷言 `reader_settings_fullscreen` 為 `findsNothing`，且 `find.text(l10n.readerSettingsScreenOrientationLabel)` 為 `findsNothing`。
  - `reader_settings_sheet_test.dart` 新增對照 `預設平台顯示全螢幕開關與螢幕方向列`：同樣先切到「呈現」，兩者各 `findsOneWidget`。
  - `fxl_settings_sheet_test.dart` 新增 `Windows 隱藏全螢幕開關` 與對照 `預設平台顯示全螢幕開關`，用該檔既有的 `_pumpModalSheet`。
  - 每個 Windows 測試都 `try/finally` 還原 `debugDefaultTargetPlatformOverride = null`。
- [x] **Step 2: 執行確認失敗。** `flutter test test/screens/reader_settings_sheet_test.dart test/screens/fxl_settings_sheet_test.dart`，預期兩個 Windows 測試失敗，對照測試通過。若流式面板的 Windows 測試在實作前就是綠的，代表沒切到「呈現」分頁，先修測試再往下。
- [x] **Step 3: 實作。** 兩個檔案都用 collection-if `if (supportsMobileReaderControls) …` 包住上述三處，連同相鄰的 `SizedBox`（`reader_settings_sheet.dart` 全螢幕卡片後的 `SizedBox(height: 8)`、螢幕方向列前後的 `SizedBox`）一起包。`_buildScreenOrientationOverrideRow()` 方法本身保留不動，只是不呼叫。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令；另跑兩個檔案全部既有測試，預期全過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/screens/fxl_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/fxl_settings_sheet_test.dart
git commit -m "feat(windows): 版面設定面板隱藏螢幕方向與全螢幕（epic-66 Issue 10 Task 3）"
```

---

### Task 4：PDF 設定面板（濾鏡分頁與全螢幕）

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`（`TabController(length: 3, …)` 約第 66 行；`TabBar.tabs`、`TabBarView.children` 約第 143～160 行；全螢幕 `SwitchListTile` 約第 343 行）
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `supportsMobileReaderControls`。
- Produces: 無新公開介面。Key 不變：`pdf_settings_tab_display`、`pdf_settings_tab_filters`、`pdf_settings_tab_crop`、`pdf_settings_fullscreen`。

- [x] **Step 1: 寫失敗測試。** 沿用該檔既有的 `_pumpSheet`：
  - `Windows 只有顯示與裁切兩個分頁，切換不拋例外`：斷言 `pdf_settings_tab_filters` 為 `findsNothing`、另外兩個為 `findsOneWidget`；點 `pdf_settings_tab_crop` 後 `pumpAndSettle`，斷言 `tester.takeException()` 為 `null`，且裁切分頁內容出現（用該檔既有裁切分頁的 Key，例如 `pdf_settings_crop_*` 其中之一；先 `grep` 確認實際 Key）。
  - `Windows 水平滑動分頁不拋例外`：在 `TabBarView` 上 `fling` 往左再往右，斷言 `tester.takeException()` 為 `null`。
  - `Windows 隱藏全螢幕開關`：`pdf_settings_fullscreen` 為 `findsNothing`。
  - 對照 `預設平台三個分頁與全螢幕開關都在`。
  - 每個 Windows 測試都 `try/finally` 還原平台覆寫。
- [x] **Step 2: 執行確認失敗。** `flutter test test/screens/pdf_settings_sheet_test.dart`，預期 Windows 測試失敗。
- [x] **Step 3: 實作。** 在 `initState` 以 `final tabCount = supportsMobileReaderControls ? 3 : 2;` 建 `TabController(length: tabCount, vsync: this)`；`TabBar.tabs` 與 `TabBarView.children` 都對「濾鏡」那一項加 `if (supportsMobileReaderControls)`，順序為顯示、（濾鏡）、裁切。`_buildFiltersTab()` 與 `_contrast`、`_brightness`、`_boldStrength` 保留不動（`_notifyChanged` 仍會把它們原值送回，不會被改成 0）。全螢幕 `SwitchListTile` 同樣包 collection-if，連同相鄰的 `Divider`／`SizedBox`（若有）一起包。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令；另跑該檔全部既有測試，預期全過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(windows): PDF 設定面板隱藏濾鏡分頁與全螢幕（epic-66 Issue 10 Task 4）"
```

---

### Task 5：E-Ink 開關與強制關閉

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`（`settings_eink_mode_switch` 的 `_SettingsCard` 約第 219～225 行）
- Modify: `app/lib/main.dart`（`_ElinkBookAppState.initState` 的 `_isEinkMode = widget.initialEinkMode;` 約第 558 行）
- Test: `app/test/screens/settings_scaffold_test.dart`、`app/test/theme/theme_test.dart`（該檔第 88、121 行已有 `initialEinkMode` 的建構 helper，沿用之；`test/elinkbook_app_wiring_test.dart` 也有，二擇一，以較貼近「主題」的 `theme_test.dart` 為準）

**Interfaces:**
- Consumes: Task 1 的 `supportsMobileReaderControls`。
- Produces: 無新公開介面。

- [x] **Step 1: 寫失敗測試。**
  - `settings_scaffold_test.dart`：`Windows 設定畫面沒有 E-Ink 開關`（`settings_eink_mode_switch` 為 `findsNothing`）；對照 `預設平台有 E-Ink 開關`。
  - `ElinkBookApp` 測試（放 `theme_test.dart`）：`Windows 傳入 initialEinkMode: true 仍套用一般主題`——讀 `MaterialApp` 的 `theme` 或 `ThemeData`，斷言它等於 `resolveThemeData(theme: AppTheme.light, isEinkMode: false)` 的結果（沿用該檔取得主題的方式）；對照 `預設平台傳入 initialEinkMode: true 套用 E-Ink 主題`。
  - 平台覆寫一律 `try/finally` 還原。
- [x] **Step 2: 執行確認失敗。** `flutter test test/screens/settings_scaffold_test.dart test/theme/theme_test.dart`。
- [x] **Step 3: 實作。** `settings_scaffold.dart`：E-Ink 那張 `_SettingsCard` 加 collection-if。`main.dart`：`_isEinkMode = widget.initialEinkMode && supportsMobileReaderControls;`，附中文註解說明「Windows 沒有 E-Ink 入口，殘留的 true 一律忽略」。`main.dart` 其餘（`loadEinkMode()`、`saveEinkMode`）不動。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令；另跑 `flutter test test/theme`，預期全過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/screens/settings_scaffold.dart app/lib/main.dart app/test/screens/settings_scaffold_test.dart app/test/theme/theme_test.dart
git commit -m "feat(windows): 隱藏 E-Ink 開關並強制關閉（epic-66 Issue 10 Task 5）"
```

---

### Task 6：`ReaderScreen` 跳過 Android 原生 channel

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
  - `initState`：`_volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall)`（約第 524 行）
  - `dispose`：`_volumeKeyChannel.setMethodCallHandler(null)`（約第 681 行）、`SystemChrome.setPreferredOrientations(const [])`（約第 701 行）、`_fullscreenChannel.invokeMethod('setEnabled', false)`（約第 704 行）
  - `_applyScreenOrientation()`（約第 739 行）與 `_applySystemUiMode()`（約第 751 行）：方法開頭 early return
  - `onPopInvokedWithResult`：`notifyLeavingReader`（約第 1880 行）
- Test: `app/test/screens/reader_screen_keyboard_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `supportsMobileReaderControls`。
- Produces: 無新公開介面。

- [x] **Step 1: 寫失敗測試。** 在 `reader_screen_keyboard_test.dart`（已是 Windows 導向，`setUp` 已 mock 兩個 channel）新增：
  - `Windows 進出閱讀器不呼叫 volume_key 與 fullscreen channel`：測試內**在 `pumpEpubReader` 之前**重新對 `elinkbook/fullscreen` 與 `elinkbook/volume_key` 設 mock handler（蓋掉 `setUp` 那組），把每次 `call.method` 記進 `List<String>`；設 `TargetPlatform.windows`；`pumpEpubReader`（沿用既有 `FakeReaderSurface` 與 `FakeReaderPrefsManager`），`pumpAndSettle`；再 `pumpWidget(const SizedBox())` 卸載（觸發 `dispose`），**接著再 `await tester.pump()`**，避免卸載後才記錄的呼叫晚於斷言造成假綠；斷言記錄清單為空，且 `tester.takeException()` 為 `null`。
  - 對照 `預設平台進出閱讀器仍呼叫 fullscreen setEnabled 與 volume_key`：同樣記錄，不設平台覆寫；斷言記錄包含 `setEnabled`（卸載時）。
  - 平台覆寫 `try/finally` 還原。
- [x] **Step 2: 執行確認失敗。** `flutter test test/screens/reader_screen_keyboard_test.dart --plain-name "進出閱讀器"`，預期 Windows 測試失敗（記錄非空）。
- [x] **Step 3: 實作。** 七個呼叫點都加 `supportsMobileReaderControls` 判斷：`initState` 與 `dispose` 的 `setMethodCallHandler` 用 `if`；`dispose` 的 `SystemChrome` 與 `setEnabled` 用同一個 `if` 包起來；兩個 `_apply*` 方法開頭加 `if (!supportsMobileReaderControls) return;`；`onPopInvokedWithResult` 內 `if (didPop && supportsMobileReaderControls)`。`dispose` 內的 `HardwareKeyboard.instance.removeHandler` 與 `_unregisterEscConsumer` 對應的是 `isWindowsPlatform`，語意相反，**不要**包進新判斷。不改任何其他邏輯與註解。
- [x] **Step 4: 執行確認通過。** 跑整個 `test/screens/reader_screen_keyboard_test.dart`、`test/screens/reader_screen_test.dart`，預期全過（`reader_screen_test.dart` 為既有大檔，過程中的 `LocalBookServer` 失敗屬 Issue 11 範圍，需與 `main` 比對再下結論）。
- [x] **Step 5: Commit。**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_keyboard_test.dart
git commit -m "fix(windows): ReaderScreen 不再呼叫 Android 原生 channel（epic-66 Issue 10 Task 6）"
```

---

### Task 7：驗證、報告與文件

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-10-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 10 狀態列）、`docs/epics/epic-66-windows-port/plans/plan-issue-10.md`（勾選步驟）

- [x] **Step 1: 靜態與全套驗證。** 在 `app/` 依序執行：`flutter analyze`（預期 `No issues found!`）、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（預期都 PASS），最後 `flutter test` 全套一次。全套失敗項目與 `main` 逐項比對；`LocalBookServer` 的失敗屬 Issue 11，其餘有新增失敗就停下來處理。
- [ ] **Step 2: Windows 實機人工確認。** PowerShell 設 `$env:CL='/utf-8'`，`flutter run -d windows`（或 `flutter build windows --debug` 後執行 exe）。逐項確認並截圖（同時目視檢查被隱藏處沒有連續兩條分隔線或多餘空洞）：閱讀預設值畫面、開 EPUB 後的版面設定面板（流式）、開 PDF 後的設定面板（只剩顯示與裁切，來回切換）、設定畫面（無 E-Ink 開關）、進出閱讀器的主控台無 `MissingPluginException`。固定版面（FXL／CBZ）若手邊沒有樣本，在報告註明「未實測」。「關於」頁若顯示錯誤文字，屬「已知限制」，不算本 Issue 漏項，在報告中記下即可。
- [x] **Step 3: 寫 `issue-10-report.md`。** 內容：變更清單、Review Focus 五條各自對應的測試名稱、全套測試結果與 `main` 比對、實機確認結果與未實測項目。
- [x] **Step 4: 同步文件並勾選。** `issues.md` Issue 10 狀態改為「✅ 實作完成，待 PR」；本檔所有已完成步驟 `- [ ]` 改為 `- [x]`。
- [x] **Step 5: Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-10-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/plans/plan-issue-10.md
git commit -m "docs(epic-66): Issue 10 驗證報告與進度同步"
```

---

## Self-Review

- **範圍涵蓋：** 音量鍵（Task 2、6）、螢幕方向（Task 2、3、6）、全螢幕偏好（Task 2、3、4、6）、PDF 濾鏡（Task 4）、E-Ink（Task 5）、原生 channel 未處理例外（Task 6）；`issues.md` 範圍 1～8 各有對應 Task。
- **型別一致：** 全計畫只有一個新名稱 `supportsMobileReaderControls`，Task 1 定義，Task 2～6 使用，名稱一致。
- **比例：** 計畫只列簽章、Key、測試名稱與行為，沒有貼函式本體。
- **已知風險：**（a）各檔案行號為 2026-11-07 `main`（`f8712bc5`）的約略位置，實作時以 Key 與方法名稱為準；（b）`SystemChrome.setPreferredOrientations` 在 Windows 本來可能無害，但 Issue 範圍明列不呼叫，故一併跳過；（c）Task 6 的對照測試依賴既有 `pumpEpubReader` 在預設平台下可正常卸載，若卸載會多出其他 channel 呼叫，只斷言 `setEnabled` 有出現即可。
