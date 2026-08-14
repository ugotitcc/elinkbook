# Epic 28 Issue 2：Console Log 攔截可手動關閉 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在「設定」畫面可以關閉/開啟 EPUB 閱讀器的 Console Log 攔截；關閉時一般等級（`LOG`/`WARNING`/`DEBUG`/`TIP`）訊息不再寫入 `ReaderConsoleLog`，但 `ERROR` 等級（含未捕捉例外的崩潰診斷用途）永遠強制記錄、不受開關影響。

**Architecture:** 新增一個跨書生效的全域布林開關 `GlobalReaderPrefs.consoleLogEnabled`（比照既有 `volumeKeyEnabled`/`fullscreen` 全域布林欄位模式，SharedPreferences 持久化），透過 `ReaderPrefsManagerImpl.resolve()` 直接透傳（無單書覆寫層）到 `ResolvedPreferences.consoleLogEnabled`，再貫穿到 `FoliateEpubReaderView` 建構參數，由 `handleFoliateConsoleMessage()` 依此參數決定是否過濾非 `ERROR` 等級的訊息。UI 端在 `SettingsScreen` 新增一個 `SwitchListTile`，讀寫比照 `ReadingDefaultsScreen` 既有的「載入→`copyWith`→存檔」互動模式。

**Tech Stack:** Flutter/Dart、`shared_preferences`、`flutter_inappwebview`（`ConsoleMessageLevel.toString()` 回傳大寫等級字串，例如 `'ERROR'`/`'LOG'`/`'WARNING'`/`'DEBUG'`/`'TIP'`，已用套件原始碼確認）。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/design.md`（「Issue 2：Console Log 開關」）、`docs/epics/epic-28-reader-settings-enhancements/issues.md`（「Issue 2」）。

## Global Constraints

- 預設**關閉**（`consoleLogEnabled` 預設值 `false`）。
- 開關只控制非 `ERROR` 等級訊息（`LOG`/`WARNING`/`DEBUG`/`TIP`）是否寫入 `ReaderConsoleLog`；`ERROR` 等級（`levelName == 'ERROR'`）永遠強制記錄，不受開關影響。
- `_globalErrorCaptureJs`（`window.onerror`/`window.onunhandledrejection` → `onError` bridge → `_handleError()`）是完全獨立的另一條管線，本 Issue 不觸碰、不受影響。
- 關閉當下不清空既有紀錄——不新增清空邏輯（`ReaderConsoleLog` 既有 500 筆記憶體上限與 `ReaderConsoleLogScreen` 既有清空按鈕已足夠，見 `spec.md`「審查回應」對 Minor 2.9 的既有澄清）。
- 只影響 EPUB（`FoliateEpubReaderView`／`InAppWebView`）——PDF 路徑（`PdfReaderView`，`pdfrx`）沒有 WebView、無 console 訊息可攔截，不在本 Issue 範圍內。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：資料層——`GlobalReaderPrefs` / `ReaderPrefsManagerImpl` / `ResolvedPreferences`

**Files:**
- Modify: `app/lib/reader/global_reader_prefs.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/reader/resolved_preferences.dart`
- Test: `app/test/reader/global_reader_prefs_test.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Produces: `GlobalReaderPrefs.consoleLogEnabled`（`bool`，預設 `false`）；`ResolvedPreferences.consoleLogEnabled`（`bool`，預設 `false`，直接透傳 `global.consoleLogEnabled`，無單書覆寫層）。

- [ ] **Step 1: 寫失敗測試——`GlobalReaderPrefs` 新欄位的預設值/copyWith/相等性**

編輯 `app/test/reader/global_reader_prefs_test.dart`，於檔案最後一個 `test(...)`（`openLastBookOnLaunch 不同時視為不相等`）之後新增：

```dart
  test('GlobalReaderPrefs.initial() 的 consoleLogEnabled 預設 false', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.consoleLogEnabled, isFalse);
  });

  test('copyWith 可更新 consoleLogEnabled，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated = original.copyWith(consoleLogEnabled: true);
    expect(updated.consoleLogEnabled, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
    expect(updated.volumeKeyEnabled, original.volumeKeyEnabled);
  });

  test('consoleLogEnabled 不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    final b = a.copyWith(consoleLogEnabled: true);
    expect(a == b, isFalse);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/global_reader_prefs_test.dart`
預期：編譯錯誤（`consoleLogEnabled` 具名參數/getter 不存在於 `GlobalReaderPrefs`）。

- [ ] **Step 3: `GlobalReaderPrefs` 新增 `consoleLogEnabled` 欄位**

編輯 `app/lib/reader/global_reader_prefs.dart`：

於第 38 行 `final bool fullscreen;`（含其上方文件註解區塊）與第 39 行空行之後、`final bool openLastBookOnLaunch;` 之前新增：

```dart

  /// Console Log 攔截總開關（epic-28-reader-settings-enhancements
  /// Issue 2），預設 `false`（不攔截一般等級訊息）。只影響 `[LOG]`/
  /// `[WARNING]`/`[DEBUG]`/`[TIP]` 等級——`[ERROR]` 等級（含未捕捉例外的
  /// 崩潰診斷用途）永遠強制記錄，不受本開關影響，見
  /// `handleFoliateConsoleMessage()`。
  final bool consoleLogEnabled;
```

於建構子（第 46-55 行）的 `this.openLastBookOnLaunch = true,` 之後新增：

```dart
    this.consoleLogEnabled = false,
```

於 `GlobalReaderPrefs.initial()`（第 59-67 行）的 `openLastBookOnLaunch = true;` 之前（改成用逗號分隔的最後一個欄位改為 `consoleLogEnabled`，或直接在其後新增一行並把結尾分號移過去）：

```dart
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto,
        navZoneMode = NavZoneMode.rightFlip,
        navZoneCustomActions = rightFlipZoneTemplate,
        showNavZoneDebugOverlay = false,
        volumeKeyEnabled = true,
        fullscreen = false,
        openLastBookOnLaunch = true,
        consoleLogEnabled = false;
```

於 `copyWith()`（第 69-90 行）參數列的 `bool? openLastBookOnLaunch,` 之後新增 `bool? consoleLogEnabled,`；回傳建構式的 `openLastBookOnLaunch: openLastBookOnLaunch ?? this.openLastBookOnLaunch,` 之後新增：

```dart
      consoleLogEnabled: consoleLogEnabled ?? this.consoleLogEnabled,
```

於 `operator ==`（第 92-102 行）的 `other.openLastBookOnLaunch == openLastBookOnLaunch;` 這行，把行尾分號改成 `&&`，新增一行並把分號移到新行：

```dart
      other.openLastBookOnLaunch == openLastBookOnLaunch &&
      other.consoleLogEnabled == consoleLogEnabled;
```

於 `hashCode`（第 104-114 行）的 `openLastBookOnLaunch,` 之後新增：

```dart
        consoleLogEnabled,
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/global_reader_prefs_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 寫失敗測試——`resolve()` 透傳與 SharedPreferences 讀寫**

編輯 `app/test/reader/reader_prefs_manager_test.dart`：

於既有 `test('全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值', ...)`（第 39-65 行）內，於 `expect(resolved.volumeKeyEnabled, isTrue);`（第 64 行）之後新增：

```dart
      expect(resolved.consoleLogEnabled, isFalse);
```

於既有 `test('volumeKeyEnabled 直接透傳 global 值，無單書覆寫層', ...)`（第 122-135 行）之後新增一個結構相同的獨立測試：

```dart
    test('consoleLogEnabled 直接透傳 global 值，無單書覆寫層', () {
      final loadedDisabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      expect(manager.resolve(loadedDisabled).consoleLogEnabled, isFalse);

      final loadedEnabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs:
            const GlobalReaderPrefs.initial().copyWith(consoleLogEnabled: true),
      );
      expect(manager.resolve(loadedEnabled).consoleLogEnabled, isTrue);
    });
```

於既有 `test('saveGlobalPrefs 寫入 volumeKeyEnabled／fullscreen 至既有慣例命名的 SharedPreferences key', ...)`（第 346-366 行）與 `test('volumeKeyEnabled／fullscreen 未儲存過（缺鍵）時，安全回退為預設值 true／false', ...)`（第 368-373 行）之後新增兩則結構相同的測試：

```dart
    test('saveGlobalPrefs 寫入 consoleLogEnabled 至既有慣例命名的 SharedPreferences key',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        consoleLogEnabled: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('global_reader_console_log_enabled'), isTrue);

      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.consoleLogEnabled, isTrue);
    });

    test('consoleLogEnabled 未儲存過（缺鍵）時，安全回退為預設值 false', () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.consoleLogEnabled, isFalse);
    });
```

- [ ] **Step 6: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：編譯錯誤（`consoleLogEnabled` 具名參數不存在於 `GlobalReaderPrefs`／`ResolvedPreferences`）。

- [ ] **Step 7: `ResolvedPreferences` 新增 `consoleLogEnabled` 欄位**

編輯 `app/lib/reader/resolved_preferences.dart`：

於第 78 行 `final bool fullscreen;` 之後新增：

```dart
  final bool consoleLogEnabled;
```

於建構子（第 80-113 行）的 `this.fullscreen = false,` 之後新增：

```dart
    this.consoleLogEnabled = false,
```

- [ ] **Step 8: `ReaderPrefsManagerImpl` 讀寫 SharedPreferences**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`：

於第 46 行 `static const _openLastBookOnLaunchKey = 'global_reader_open_last_book_on_launch';` 之後新增：

```dart
  static const _consoleLogEnabledKey = 'global_reader_console_log_enabled';
```

於 `loadGlobalPrefs()`（第 68-88 行）的 `openLastBookOnLaunch: sp.getBool(_openLastBookOnLaunchKey) ?? true,` 之後新增：

```dart
      consoleLogEnabled: sp.getBool(_consoleLogEnabledKey) ?? false,
```

於 `saveGlobalPrefs()`（第 129-142 行）的 `await sp.setBool(_openLastBookOnLaunchKey, prefs.openLastBookOnLaunch);` 之後新增：

```dart
    await sp.setBool(_consoleLogEnabledKey, prefs.consoleLogEnabled);
```

於 `resolve()`（第 154-197 行）的 `volumeKeyEnabled: global.volumeKeyEnabled,` 之後新增：

```dart
      consoleLogEnabled: global.consoleLogEnabled,
```

- [ ] **Step 9: 執行測試確認通過**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：全數 PASS。

- [ ] **Step 10: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 11: Commit**

```bash
git add app/lib/reader/global_reader_prefs.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/reader/resolved_preferences.dart app/test/reader/global_reader_prefs_test.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-28): Issue 2 Task 1——GlobalReaderPrefs 新增 consoleLogEnabled 欄位"
```

---

### Task 2：Console 攔截過濾邏輯 ＋ `FoliateEpubReaderView` 接線

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: `ResolvedPreferences.consoleLogEnabled`（Task 1 產出）。
- Produces: `FoliateEpubReaderView.consoleLogEnabled`（`bool` 建構參數，預設 `false`）；`handleFoliateConsoleMessage(String message, String levelName, {required bool consoleLogEnabled})`——簽章變更（新增必要具名參數），呼叫端需同步更新。

- [ ] **Step 1: 寫失敗測試——`handleFoliateConsoleMessage` 依開關過濾**

編輯 `app/test/reader/foliate_epub_reader_view_test.dart`：

於既有 `group('handleFoliateConsoleMessage', ...)`（約第 1037-1055 行）內，把既有兩則測試的呼叫改為明確傳入 `consoleLogEnabled: true`（維持原本「攔截全部等級」的既有行為驗證意圖）：

```dart
    test('把 messageLevel 與 message 組成單行文字附加到 ReaderConsoleLog', () {
      handleFoliateConsoleMessage('測試訊息', 'LOG', consoleLogEnabled: true);

      expect(ReaderConsoleLog.entries.value, hasLength(1));
      expect(ReaderConsoleLog.entries.value.single, '[LOG] 測試訊息');
    });

    test('可連續呼叫多次，依序附加不覆蓋既有訊息', () {
      handleFoliateConsoleMessage('第一筆', 'LOG', consoleLogEnabled: true);
      handleFoliateConsoleMessage('第二筆', 'ERROR', consoleLogEnabled: true);

      expect(ReaderConsoleLog.entries.value, ['[LOG] 第一筆', '[ERROR] 第二筆']);
    });
```

在這兩則之後，新增以下 3 則測試（epic-28 Issue 2 新行為）：

```dart
    test('consoleLogEnabled 為 false 時，LOG／WARNING 等非 ERROR 等級不寫入', () {
      handleFoliateConsoleMessage('一般訊息', 'LOG', consoleLogEnabled: false);
      handleFoliateConsoleMessage('警告訊息', 'WARNING', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, isEmpty);
    });

    test('consoleLogEnabled 為 false 時，ERROR 等級仍強制寫入（崩潰診斷能力不受開關影響）',
        () {
      handleFoliateConsoleMessage('例外訊息', 'ERROR', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, ['[ERROR] 例外訊息']);
    });

    test('consoleLogEnabled 為 false 時，ERROR 與 LOG 混合呼叫，只有 ERROR 被記錄',
        () {
      handleFoliateConsoleMessage('一般訊息', 'LOG', consoleLogEnabled: false);
      handleFoliateConsoleMessage('例外訊息', 'ERROR', consoleLogEnabled: false);
      handleFoliateConsoleMessage('警告訊息', 'WARNING', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, ['[ERROR] 例外訊息']);
    });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：編譯錯誤（`consoleLogEnabled` 具名參數不存在於 `handleFoliateConsoleMessage`）。

- [ ] **Step 3: `handleFoliateConsoleMessage()` 依開關過濾非 ERROR 等級**

編輯 `app/lib/reader/foliate_epub_reader_view.dart`，第 213-215 行原為：

```dart
void handleFoliateConsoleMessage(String message, String levelName) {
  ReaderConsoleLog.add('[$levelName] $message');
}
```

改為：

```dart
/// epic-28-reader-settings-enhancements Issue 2：[consoleLogEnabled] 為
/// `false` 時，只有 `ERROR` 等級（WebView 自動鏡射的未捕捉例外，崩潰診斷
/// 用途）強制記錄；`LOG`/`WARNING`/`DEBUG`/`TIP` 等一般等級一律略過。
/// `levelName` 來自 `ConsoleMessageLevel.toString()`，恆為大寫字串
/// （已用套件原始碼確認：`'ERROR'`/`'LOG'`/`'WARNING'`/`'DEBUG'`/`'TIP'`
/// 五種）。
void handleFoliateConsoleMessage(
  String message,
  String levelName, {
  required bool consoleLogEnabled,
}) {
  if (!consoleLogEnabled && levelName != 'ERROR') return;
  ReaderConsoleLog.add('[$levelName] $message');
}
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：FAIL（`FoliateEpubReaderView`／呼叫端尚未更新，見下一步；`handleFoliateConsoleMessage` 相關的測試本身應已 PASS，其餘既有測試因呼叫端 `onConsoleMessage` 尚未同步更新可能編譯失敗）。

- [ ] **Step 5: `FoliateEpubReaderView` 新增 `consoleLogEnabled` 建構參數並接線**

編輯 `app/lib/reader/foliate_epub_reader_view.dart`：

於第 376 行 `final bool showNavZoneDebugOverlay;` 之後新增：

```dart
  final bool consoleLogEnabled;
```

於建構子第 418 行 `this.showNavZoneDebugOverlay = false,` 之後新增：

```dart
    this.consoleLogEnabled = false,
```

於 `onConsoleMessage:` 呼叫處（約第 774-778 行）：

```dart
          onConsoleMessage: (controller, consoleMessage) =>
              handleFoliateConsoleMessage(
            consoleMessage.message,
            consoleMessage.messageLevel.toString(),
          ),
```

改為：

```dart
          onConsoleMessage: (controller, consoleMessage) =>
              handleFoliateConsoleMessage(
            consoleMessage.message,
            consoleMessage.messageLevel.toString(),
            consoleLogEnabled: widget.consoleLogEnabled,
          ),
```

- [ ] **Step 6: `reader_screen.dart` 傳遞 `resolved.consoleLogEnabled`**

編輯 `app/lib/screens/reader_screen.dart`，於第 2304 行（`case BookFormat.epub:` 分支內）：

```dart
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
```

之後新增：

```dart
          consoleLogEnabled: resolved.consoleLogEnabled,
```

**不要**修改 `case BookFormat.pdf:` 分支（`PdfReaderView` 第 2341 行附近的同名 `showNavZoneDebugOverlay`）——PDF 路徑無 WebView、無 console 訊息可攔截，本 Issue 不涉及 `PdfReaderView`。

- [ ] **Step 7: 執行測試確認通過**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：全數 PASS。

- [ ] **Step 8: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS（尤其確認 `reader_screen_test.dart` 未因 `FoliateEpubReaderView` 建構簽章新增可選參數而回歸——新參數有預設值，既有呼叫端不需修改）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-28): Issue 2 Task 2——handleFoliateConsoleMessage 依 consoleLogEnabled 過濾非 ERROR 等級"
```

---

### Task 3：UI——`SettingsScreen` 新增 Console Log 開關

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `widget.prefsManager.loadGlobalPrefs()`/`saveGlobalPrefs()`（既有介面，`ReaderPrefsManager`，Task 1 已擴充 `GlobalReaderPrefs`）。
- Produces：使用者互動後，透過 `prefsManager.saveGlobalPrefs()` 持久化 `consoleLogEnabled`。

**背景**：`SettingsScreen` 目前是 `StatelessWidget`，本身不持有任何非同步載入狀態（`ReadingDefaultsScreen`／`NavZoneSettingsScreen` 才各自管理自己的 `GlobalReaderPrefs` 狀態）。本 Task 須將它改為 `StatefulWidget`，但**刻意不採用** `ReadingDefaultsScreen` 的「整頁 loading gate」模式（`_loading` 布林 + `CircularProgressIndicator` 擋住整個畫面）——`SettingsScreen` 有「佈景」「字型管理」等其餘與本開關無關的項目，不應該因為這個開關的非同步載入而讓整頁初次顯示延遲。改為：開關初始顯示 `false`（與 `GlobalReaderPrefs` 預設值一致），載入完成後才透過 `setState` 更新為實際已儲存值，其餘 `ListTile` 完全不受影響、與遷移前行為一致（不需要修改任何既有測試）。

- [ ] **Step 1: 寫失敗測試——開關存在、初始值反映已儲存設定、互動後持久化**

編輯 `app/test/screens/settings_screen_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/global_reader_prefs.dart';
```

於檔案最後一個 `testWidgets(...)`（`點擊「閱讀器 Console Log」導航至 ReaderConsoleLogScreen`）之後新增：

```dart
  testWidgets('SettingsScreen 顯示 Console Log 開關，初始值反映已儲存的 consoleLogEnabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(
          globalPrefs:
              const GlobalReaderPrefs.initial().copyWith(consoleLogEnabled: true),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('settings_console_log_switch')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isTrue,
    );
  });

  testWidgets('Console Log 開關預設關閉（尚未儲存過設定時）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('切換 Console Log 開關後，onChanged 觸發 saveGlobalPrefs 持久化新值',
      (tester) async {
    final prefsManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: prefsManager),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings_console_log_switch')));
    await tester.pump();

    expect(prefsManager.savedGlobalPrefsCalls, hasLength(1));
    expect(prefsManager.savedGlobalPrefsCalls.single.consoleLogEnabled, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isTrue,
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/settings_screen_test.dart`
預期：FAIL（找不到 `Key('settings_console_log_switch')`）。

- [ ] **Step 3: `SettingsScreen` 改為 `StatefulWidget` 並新增開關**

`app/lib/screens/settings_screen.dart` 涉及的欄位存取散落在 `build()`／`_buildThemeDot()` 多處、且轉換為 `StatefulWidget` 後全部要加上 `widget.` 前綴，逐一 diff 容易遺漏——直接用完整檔案內容覆寫整份檔案：

```dart
import 'package:flutter/material.dart';

import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';

/// 設定畫面：「佈景」（主題圓點，原位於 `LibraryScreen` AppBar，見
/// `epic-18-reader-device-qa` 工具列溢位修復）、「字型管理」、「閱讀預設值」、
/// 「導航熱區」、「同步」、「閱讀器 Console Log」（Issue 33 診斷用）、
/// Console Log 攔截開關（epic-28-reader-settings-enhancements Issue 2）與
/// 「關於」項目。
class SettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式（比照
  /// `ReadingDefaultsScreen` 的 `_loading` 布林 + `CircularProgressIndicator`
  /// 擋住整頁）——本畫面其餘 `ListTile`（佈景／字型管理等）與這個開關無關，
  /// 初始值先顯示預設 `false`，`initState()` 的非同步載入完成後才 `setState`
  /// 更新為實際已儲存值，不阻塞其餘項目的同步顯示。
  bool _consoleLogEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadConsoleLogEnabled();
  }

  Future<void> _loadConsoleLogEnabled() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _consoleLogEnabled = prefs.consoleLogEnabled);
  }

  Future<void> _updateConsoleLogEnabled(bool value) async {
    setState(() => _consoleLogEnabled = value);
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    await widget.prefsManager
        .saveGlobalPrefs(prefs.copyWith(consoleLogEnabled: value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('佈景'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    const Color(0xFFF5F5F5), 'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    const Color(0xFF121212), 'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    const Color(0xFFF4ECD8), 'settings_theme_dot_sepia'),
              ],
            ),
          ),
          ListTile(
            key: const Key('settings_font_management_button'),
            title: const Text('字型管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.customFontsRepository == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => FontManagementScreen(
                          repository: widget.customFontsRepository!,
                        ),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const Key('settings_reading_defaults_button'),
            title: const Text('閱讀預設值'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ReadingDefaultsScreen(prefsManager: widget.prefsManager),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('settings_nav_zone_button'),
            title: const Text('導航熱區'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      NavZoneSettingsScreen(prefsManager: widget.prefsManager),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('settings_sync_button'),
            title: const Text('同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.syncAccountRepository == null ||
                    widget.syncClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SyncSettingsScreen(
                          accountRepository: widget.syncAccountRepository!,
                          syncClient: widget.syncClient!,
                        ),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const Key('settings_reader_console_log_button'),
            title: const Text('閱讀器 Console Log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ReaderConsoleLogScreen(),
                ),
              );
            },
          ),
          SwitchListTile(
            key: const Key('settings_console_log_switch'),
            title: const Text('Console Log 攔截'),
            subtitle: const Text('關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄'),
            value: _consoleLogEnabled,
            onChanged: (value) => _updateConsoleLogEnabled(value),
          ),
          ListTile(
            key: const Key('settings_about_button'),
            title: const Text('關於'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 主題選擇圓點，比照 `epic-18` 之前放在 `LibraryScreen` AppBar 的既有互動
  /// 設計原樣搬移（E-Ink 模式下停用點擊並降低不透明度）。
  Widget _buildThemeDot(
      BuildContext context, AppTheme theme, Color color, String key) {
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap:
          widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
```

（新的 Console Log 開關 `ListTile` 放在「閱讀器 Console Log」入口之後、「關於」之前——與 `design.md`「同一頁」的要求一致，位置選在既有診斷入口旁邊，語意上相鄰。）

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/screens/settings_screen_test.dart`
預期：全數 PASS（含 Step 1 新增的 3 則測試與全部既有測試——既有測試皆未使用 `await tester.pump()` 額外等待即斷言，須確認轉換為 `StatefulWidget` 後這些既有斷言依然成立：`_consoleLogEnabled` 的非同步載入不影響其餘 `ListTile` 的同步顯示，見 Task 3 開頭「背景」說明）。

- [ ] **Step 5: 執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/settings_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "feat(epic-28): Issue 2 Task 3——SettingsScreen 新增 Console Log 開關"
```

---

## 完成後的驗證（對照 `issues.md` Issue 2 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化）於真機或模擬器：開啟一本流式 EPUB 觸發幾筆一般 console log，確認「閱讀器 Console Log」畫面有紀錄；到「設定」關閉 Console Log 攔截開關，重新觸發同樣操作，確認一般訊息不再新增，但故意觸發一個 JS 例外（或參考 `epic-27-reader-device-compat` 已知的載入中點擊崩潰情境，若尚未修復）時 `[ERROR]` 訊息仍正確出現。
