# Epic 7 Issue 3 — 導航熱區設定畫面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立使用者可見的熱區設定入口——`SettingsScreen` 新增「導航熱區」項目，導向新畫面 `NavZoneSettingsScreen`，讓使用者能切換四選一熱區模板（左翻頁／右翻頁／單手／自訂）、編輯自訂 9 格動作、切換熱區輔助線顯示，全部即時全域生效。

**Architecture:** `NavZoneSettingsScreen` 讀寫對象是 `GlobalReaderPrefs`（透過 `ReaderPrefsManager`），不經過 `ResolvedPreferences`（該型別只服務 `ReaderScreen` 渲染需求，見 spec.md「模組」節）。`ReaderPrefsManager` 目前只有 `load(bookId)`（需要書籍 ID）可以取得 `GlobalReaderPrefs`，沒有不依附書籍的讀取入口，本計畫 Task 1 新增 `loadGlobalPrefs()` 介面方法補上這個缺口（`ReaderPrefsManagerImpl` 內部把原本 private 的 `_loadGlobalPrefs()` 直接升級為這個新的 public override，`load()` 內部呼叫改用同一份，兩者保證讀到一致的值，不重複實作）。畫面本身用 `StatefulWidget`：模板切換與熱區輔助線開關即時儲存；自訂模式的 9 格編輯器則先只更新畫面上的暫存陣列，直到使用者按下「儲存」且通過 `isValidCustomZoneConfig()` 驗證才真正寫入，避免中途編輯出的無效狀態（暫時全部非 `menu`）被意外持久化。

**Tech Stack:** Flutter（`StatefulWidget`／`RadioListTile`／`SwitchListTile`／`GridView.count`）、既有 `ReaderPrefsManager`/`GlobalReaderPrefs`（epic-7 Issue 2 已完成）、`flutter_test`（widget test，無需真實裝置）。

## Global Constraints

- 讀寫對象為 `GlobalReaderPrefs`（透過 `ReaderPrefsManager`），**不經過** `ResolvedPreferences`（issues.md Issue 3）。
- 四選一模板：`RadioListTile`（左翻頁／右翻頁／單手／自訂），對應 `NavZoneMode` 四值。選到「自訂」時顯示 9 格自由編輯器（3×3 排列，每格點擊循環切換 4 種 `ZoneAction`：`previousPage`/`nextPage`/`menu`/`none`）。
- 獨立的「顯示熱區輔助線」`SwitchListTile`，對應 `GlobalReaderPrefs.showNavZoneDebugOverlay`。
- **儲存自訂設定前必須呼叫 `isValidCustomZoneConfig()`**（`app/lib/reader/zone_action.dart`，Issue 2 已提供）：`actions.length == 9 && actions.contains(ZoneAction.menu)`。未通過（9 格皆非 `menu`）**必須擋下儲存**、顯示錯誤提示（design.md 決策 #7，收斂沉浸模式死鎖風險——避免使用者設定出沒有任何格子能退出沉浸模式的組合）。
- `SettingsScreen`（`app/lib/screens/settings_screen.dart`）新增「導航熱區」`ListTile`，導向新畫面 `NavZoneSettingsScreen`。
- 熱區設定為**全域生效**，不做單書覆寫（design.md 決策 #9）——`NavZoneSettingsScreen` 完全不接受 `bookId` 參數。
- 本 issue **完全不需要真實裝置**即可驗收（純 Flutter widget，無原生 `PlatformView`）。
- `flutter analyze` 全程須保持乾淨（"No issues found!"），每個 Task 結束時整個 `app/` 套件都必須能通過編譯與既有全部測試。
- 套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/...`）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/reader_prefs_manager.dart` | 修改 | 新增抽象方法 `loadGlobalPrefs()`——不依附書籍 ID 的全域偏好讀取入口 |
| `app/lib/reader/reader_prefs_manager_impl.dart` | 修改 | 原本 private 的 `_loadGlobalPrefs()` 升級為 `loadGlobalPrefs()`（public override），`load()` 內部呼叫點同步更新 |
| `app/test/support/fake_reader_prefs_manager.dart` | 修改 | 新增 `loadGlobalPrefs()` override（直接回傳目前持有的 `globalPrefs` 欄位） |
| `app/lib/screens/nav_zone_settings_screen.dart` | 新增 | 導航熱區設定畫面：四選一模板、自訂 9 格編輯器、熱區輔助線開關 |
| `app/lib/screens/settings_screen.dart` | 修改 | 新增 `prefsManager` 建構參數與「導航熱區」`ListTile` 入口 |
| `app/lib/screens/library_screen.dart` | 修改 | 導航至 `SettingsScreen` 的呼叫點補上 `prefsManager: widget.prefsManager` |
| `app/test/reader/reader_prefs_manager_test.dart` | 修改 | 新增 `loadGlobalPrefs()` 與 `load(bookId).globalPrefs` 一致性測試 |
| `app/test/screens/nav_zone_settings_screen_test.dart` | 新增 | `NavZoneSettingsScreen` widget test |
| `app/test/screens/settings_screen_test.dart` | 修改 | 既有測試改用 `FakeReaderPrefsManager`；新增「導航熱區」入口與導航測試 |

---

### Task 1：`ReaderPrefsManager.loadGlobalPrefs()`——不依附書籍的全域偏好讀取入口

**Files:**
- Modify: `app/lib/reader/reader_prefs_manager.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/test/support/fake_reader_prefs_manager.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes：既有 `GlobalReaderPrefs`（epic-7 Issue 2）
- Produces：`Future<GlobalReaderPrefs> loadGlobalPrefs()`（`ReaderPrefsManager` 介面方法）——供 Task 2 的 `NavZoneSettingsScreen` 呼叫

- [ ] **Step 1：寫失敗測試**

修改 `app/test/reader/reader_prefs_manager_test.dart`，在 `group('load()（async...', () { ... })` 群組內、既有「saveGlobalPrefs 寫入後，load 讀回相同的全域預設值（含熱區三欄位）」測試之後，新增：

```dart
    test('loadGlobalPrefs() 回傳與 load(bookId).globalPrefs 一致的值', () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
        navZoneMode: NavZoneMode.oneHand,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final direct = await manager.loadGlobalPrefs();
      final viaLoad = await manager.load('b1');

      expect(direct, globalPrefs);
      expect(direct, viaLoad.globalPrefs);
    });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL（`Error: The method 'loadGlobalPrefs' isn't defined for the type 'ReaderPrefsManagerImpl'`）。

- [ ] **Step 3：實作**

修改 `app/lib/reader/reader_prefs_manager.dart`，在既有 `Future<LoadedPrefs> load(String bookId);` 之後新增抽象方法：

```dart
  /// 一次載入單書覆寫值、全域預設值與本機閱讀位置（原本 `ReaderScreen.initState`
  /// 裡 3 個平行 Future 中的 2 個，見 Task 3；epic-5-toc-pagination Issue 2
  /// 新增第 3 個平行讀取）。
  Future<LoadedPrefs> load(String bookId);

  /// 單獨載入全域偏好，不需要 bookId——供不依附特定書籍的設定畫面（例如
  /// `NavZoneSettingsScreen`，epic-7-interaction Issue 3）使用；`load(bookId)`
  /// 內部也呼叫同一份實作，兩者保證讀到一致的值。
  Future<GlobalReaderPrefs> loadGlobalPrefs();
```

（`Future<LoadedPrefs> load(String bookId);` 那一行已存在，只是把新方法插入在它後面，不要重複貼上該行本身。）

修改 `app/lib/reader/reader_prefs_manager_impl.dart`，原本：

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      _loadGlobalPrefs(),
      _positionRepository.load(bookId),
      _characterCountRepository?.load(bookId) ?? Future.value(null),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
      totalCharacterCount: results[3] as int?,
    );
  }

  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
      navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
          NavZoneMode.rightFlip,
      navZoneCustomActions:
          _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
      showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
    );
  }
```

改為：

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      loadGlobalPrefs(),
      _positionRepository.load(bookId),
      _characterCountRepository?.load(bookId) ?? Future.value(null),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
      totalCharacterCount: results[3] as int?,
    );
  }

  /// 單獨載入全域偏好，不需要 bookId——供不依附特定書籍的設定畫面（例如
  /// `NavZoneSettingsScreen`，epic-7-interaction Issue 3）使用；`load(bookId)`
  /// 內部也呼叫這裡，兩者保證讀到一致的值。
  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
      navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
          NavZoneMode.rightFlip,
      navZoneCustomActions:
          _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
      showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
    );
  }
```

修改 `app/test/support/fake_reader_prefs_manager.dart`，在既有 `@override Future<LoadedPrefs> load(String bookId) async { ... }` 方法之後新增：

```dart
  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async => globalPrefs;
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：PASS（全部測試，含新增的 1 個）。

- [ ] **Step 5：確認全專案仍可編譯（`FakeReaderPrefsManager` 是共用測試工具）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（`FakeReaderPrefsManager` 被 `reader_screen_test.dart` 大量使用，確認新增的 `loadGlobalPrefs()` override 沒有破壞既有用法）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/reader_prefs_manager.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/support/fake_reader_prefs_manager.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-7): add ReaderPrefsManager.loadGlobalPrefs()"
```

---

### Task 2：`NavZoneSettingsScreen` 骨架——四選一模板即時持久化、熱區輔助線開關

**Files:**
- Create: `app/lib/screens/nav_zone_settings_screen.dart`
- Test: `app/test/screens/nav_zone_settings_screen_test.dart`

**Interfaces:**
- Consumes：`ReaderPrefsManager.loadGlobalPrefs()`/`saveGlobalPrefs()`（Task 1）、`GlobalReaderPrefs`/`NavZoneMode`（epic-7 Issue 2）
- Produces：`NavZoneSettingsScreen({required ReaderPrefsManager prefsManager})`——供 Task 4 的 `SettingsScreen` 建構並導航

- [ ] **Step 1：寫失敗測試**

建立 `app/test/screens/nav_zone_settings_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/screens/nav_zone_settings_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示四選一模板', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsNothing,
    );
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_oneHand')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_custom')), findsOneWidget);
  });

  testWidgets('點擊「左翻頁」模板觸發 GlobalReaderPrefs 更新為 leftFlip', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_leftFlip')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.leftFlip,
    );
  });

  testWidgets('點擊「單手」模板觸發 GlobalReaderPrefs 更新為 oneHand', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_oneHand')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.oneHand,
    );
  });

  testWidgets('切換「顯示熱區輔助線」開關觸發 GlobalReaderPrefs 更新', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_debug_overlay_switch')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('nav_zone_debug_overlay_switch')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.showNavZoneDebugOverlay,
      isTrue,
    );
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：FAIL（`Error: Not found: 'package:elinkbook/screens/nav_zone_settings_screen.dart'`，檔案尚不存在）。

- [ ] **Step 3：實作**

建立 `app/lib/screens/nav_zone_settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/nav_zone_mode.dart';
import '../reader/reader_prefs_manager.dart';

/// 導航熱區設定畫面（FR-24）：四選一模板（左翻頁／右翻頁／單手／自訂）
/// 選擇即時全域生效；讀寫對象為 [GlobalReaderPrefs]（透過
/// [ReaderPrefsManager]），不經過 `ResolvedPreferences`——該型別只服務
/// `ReaderScreen` 的渲染需求，不服務設定畫面（見
/// docs/epics/epic-7-interaction/spec.md「模組」節）。熱區設定為全域生效，
/// 不做單書覆寫（design.md 決策 #9），本畫面不接受 bookId 參數。
class NavZoneSettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const NavZoneSettingsScreen({super.key, required this.prefsManager});

  @override
  State<NavZoneSettingsScreen> createState() => _NavZoneSettingsScreenState();
}

class _NavZoneSettingsScreenState extends State<NavZoneSettingsScreen> {
  bool _loading = true;
  late GlobalReaderPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  void _selectMode(NavZoneMode mode) {
    final updated = _prefs.copyWith(navZoneMode: mode);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  void _toggleDebugOverlay(bool value) {
    final updated = _prefs.copyWith(showNavZoneDebugOverlay: value);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('導航熱區')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('nav_zone_settings_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_leftFlip'),
                  title: const Text('左翻頁'),
                  value: NavZoneMode.leftFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_rightFlip'),
                  title: const Text('右翻頁'),
                  value: NavZoneMode.rightFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_oneHand'),
                  title: const Text('單手'),
                  value: NavZoneMode.oneHand,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_custom'),
                  title: const Text('自訂'),
                  value: NavZoneMode.custom,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                const Divider(),
                SwitchListTile(
                  key: const Key('nav_zone_debug_overlay_switch'),
                  title: const Text('顯示熱區輔助線'),
                  value: _prefs.showNavZoneDebugOverlay,
                  onChanged: _toggleDebugOverlay,
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：PASS（4 個測試全過）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "feat(epic-7): add NavZoneSettingsScreen template selection"
```

---

### Task 3：`NavZoneSettingsScreen` 自訂模式 9 格編輯器 + 儲存前驗證

**Files:**
- Modify: `app/lib/screens/nav_zone_settings_screen.dart`（全檔重寫，見 Step 3）
- Modify: `app/test/screens/nav_zone_settings_screen_test.dart`（新增測試，見 Step 1）

**Interfaces:**
- Consumes：`ZoneAction`/`isValidCustomZoneConfig()`（epic-7 Issue 2，`app/lib/reader/zone_action.dart`）
- Produces：無新增對外介面（`NavZoneSettingsScreen` 建構參數不變），本 Task 只擴充畫面內部行為

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/nav_zone_settings_screen_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/zone_action.dart';
```

在 `main()` 內既有測試之後（`}` 前）新增 3 個測試：

```dart
  testWidgets('選到「自訂」後顯示 9 格編輯器，逐格點擊循環切換 4 種動作', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
    // rightFlip 預設模板第 0 格為 previousPage。
    expect(find.text('上一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('下一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('選單'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('無動作'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('上一頁'), findsWidgets);
  });

  testWidgets('儲存自訂設定時，全部非 menu 會被擋下（錯誤提示存在、儲存回呼未被觸發）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
    await tester.pumpAndSettle();
    final savedCallCountAfterModeSwitch =
        fakeManager.savedGlobalPrefsCalls.length;

    // rightFlip 預設模板的 menu 格在 index 1/4/7，各點擊一次轉為 none。
    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_7')));
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('nav_zone_save_custom_button')));
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsOneWidget,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.length,
      savedCallCountAfterModeSwitch,
    );
  });

  testWidgets('儲存自訂設定時，至少 1 格為 menu 則成功儲存並清除錯誤提示', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
    await tester.pumpAndSettle();

    // 修改第 0 格（原為 previousPage），其餘 menu 格（index 1/4/7）不動，
    // 陣列仍然合法。
    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_save_custom_button')));
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneCustomActions[0],
      ZoneAction.nextPage,
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：FAIL（`nav_zone_custom_cell_0` 等 Key 找不到——目前畫面尚未在 `custom` 模式下顯示 9 格編輯器）。

- [ ] **Step 3：實作**

全檔重寫 `app/lib/screens/nav_zone_settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/nav_zone_mode.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/zone_action.dart';

/// 導航熱區設定畫面（FR-24）：四選一模板（左翻頁／右翻頁／單手／自訂）
/// 選擇即時全域生效；選到「自訂」時顯示 9 格自由編輯器，逐格點擊循環切換
/// 4 種 [ZoneAction]，儲存前呼叫 [isValidCustomZoneConfig] 驗證（design.md
/// 決策 #7，避免使用者設定出沒有任何格子能退出沉浸模式的死鎖組合）。讀寫
/// 對象為 [GlobalReaderPrefs]（透過 [ReaderPrefsManager]），不經過
/// `ResolvedPreferences`——該型別只服務 `ReaderScreen` 的渲染需求，不服務
/// 設定畫面（見 docs/epics/epic-7-interaction/spec.md「模組」節）。熱區
/// 設定為全域生效，不做單書覆寫（design.md 決策 #9），本畫面不接受 bookId
/// 參數。
class NavZoneSettingsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const NavZoneSettingsScreen({super.key, required this.prefsManager});

  @override
  State<NavZoneSettingsScreen> createState() => _NavZoneSettingsScreenState();
}

class _NavZoneSettingsScreenState extends State<NavZoneSettingsScreen> {
  bool _loading = true;
  late GlobalReaderPrefs _prefs;

  /// 自訂模式的編輯中陣列——只在 [_prefs] 的 `navZoneMode` 為
  /// [NavZoneMode.custom] 時於畫面上可見/可互動；點擊格子只更新這裡，
  /// 尚未通過 [_saveCustomActions] 驗證前不會寫入 [_prefs]／持久化，避免
  /// 編輯過程中暫時出現的無效狀態（例如暫時全部非 `menu`）被意外儲存。
  late List<ZoneAction> _customActions;

  String? _validationError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _customActions = List.of(prefs.navZoneCustomActions);
      _loading = false;
    });
  }

  void _selectMode(NavZoneMode mode) {
    final updated = _prefs.copyWith(navZoneMode: mode);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() {
      _prefs = updated;
      // 切換模板時捨棄尚未儲存的自訂編輯，回到上次已儲存的自訂陣列。
      _customActions = List.of(updated.navZoneCustomActions);
      _validationError = null;
    });
  }

  void _toggleDebugOverlay(bool value) {
    final updated = _prefs.copyWith(showNavZoneDebugOverlay: value);
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  void _cycleCell(int index) {
    final current = _customActions[index];
    final next = ZoneAction
        .values[(ZoneAction.values.indexOf(current) + 1) % ZoneAction.values.length];
    setState(() {
      _customActions = List.of(_customActions)..[index] = next;
    });
  }

  void _saveCustomActions() {
    if (!isValidCustomZoneConfig(_customActions)) {
      setState(() {
        _validationError = '至少需要 1 格設為「選單」，否則將無法退出沉浸模式';
      });
      return;
    }
    final updated =
        _prefs.copyWith(navZoneCustomActions: List.of(_customActions));
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() {
      _prefs = updated;
      _validationError = null;
    });
  }

  String _actionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('導航熱區')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('nav_zone_settings_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_leftFlip'),
                  title: const Text('左翻頁'),
                  value: NavZoneMode.leftFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_rightFlip'),
                  title: const Text('右翻頁'),
                  value: NavZoneMode.rightFlip,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_oneHand'),
                  title: const Text('單手'),
                  value: NavZoneMode.oneHand,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                RadioListTile<NavZoneMode>(
                  key: const Key('nav_zone_mode_custom'),
                  title: const Text('自訂'),
                  value: NavZoneMode.custom,
                  groupValue: _prefs.navZoneMode,
                  onChanged: (mode) => _selectMode(mode!),
                ),
                if (_prefs.navZoneMode == NavZoneMode.custom)
                  _buildCustomEditor(),
                const Divider(),
                SwitchListTile(
                  key: const Key('nav_zone_debug_overlay_switch'),
                  title: const Text('顯示熱區輔助線'),
                  value: _prefs.showNavZoneDebugOverlay,
                  onChanged: _toggleDebugOverlay,
                ),
              ],
            ),
    );
  }

  Widget _buildCustomEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(9, (index) {
              return InkWell(
                key: Key('nav_zone_custom_cell_$index'),
                onTap: () => _cycleCell(index),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  alignment: Alignment.center,
                  child: Text(_actionLabel(_customActions[index])),
                ),
              );
            }),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _validationError!,
                key: const Key('nav_zone_custom_validation_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('nav_zone_save_custom_button'),
            onPressed: _saveCustomActions,
            child: const Text('儲存自訂熱區設定'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/nav_zone_settings_screen_test.dart
```

Expected：PASS（7 個測試全過，含 Task 2 既有 4 個）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "feat(epic-7): add custom 9-cell editor with save validation"
```

---

### Task 4：`SettingsScreen`「導航熱區」入口 + `LibraryScreen` 呼叫點更新

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`（全檔重寫，見 Step 3）
- Modify: `app/lib/screens/library_screen.dart:452-462`
- Modify: `app/test/screens/settings_screen_test.dart`（全檔重寫，見 Step 1）

**Interfaces:**
- Consumes：`NavZoneSettingsScreen`（Task 2/3）、`ReaderPrefsManager`（既有，`LibraryScreen` 已持有）
- Produces：`SettingsScreen({required ReaderPrefsManager prefsManager})`——`prefsManager` 從既有 `LibraryScreen.prefsManager` 逐層傳遞

**⚠️ 破壞性變更說明**：`SettingsScreen` 新增必填建構參數 `prefsManager`，`app/lib/screens/library_screen.dart:458` 既有的 `const SettingsScreen()` 呼叫點與 `app/test/screens/settings_screen_test.dart` 既有 2 個測試皆會編譯失敗，必須在同一個 Task 內一併修正。

- [ ] **Step 1：寫失敗測試**

全檔重寫 `app/test/screens/settings_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('SettingsScreen 顯示設定標題與「關於」「導航熱區」入口', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    expect(find.text('設定'), findsOneWidget);
    expect(find.byKey(const Key('settings_about_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_nav_zone_button')), findsOneWidget);
  });

  testWidgets('點擊「關於」導航至 AboutScreen，可返回 SettingsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_about_button')));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('點擊「導航熱區」導航至 NavZoneSettingsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_nav_zone_button')));
    await tester.pumpAndSettle();

    expect(find.text('導航熱區'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/settings_screen_test.dart
```

Expected：FAIL（`Error: No named parameter with the name 'prefsManager'`，`SettingsScreen` 尚未接受此建構參數）。

- [ ] **Step 3：實作**

全檔重寫 `app/lib/screens/settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/reader_prefs_manager.dart';
import 'about_screen.dart';
import 'nav_zone_settings_screen.dart';

/// 設定畫面：目前有「導航熱區」與「關於」兩個入口；其餘設定項目（版面、
/// 字型、主題等）屬於後續各功能 Epic。
class SettingsScreen extends StatelessWidget {
  final ReaderPrefsManager prefsManager;

  const SettingsScreen({super.key, required this.prefsManager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          ListTile(
            key: const Key('settings_nav_zone_button'),
            title: const Text('導航熱區'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      NavZoneSettingsScreen(prefsManager: prefsManager),
                ),
              );
            },
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
}
```

修改 `app/lib/screens/library_screen.dart`，原本（第 452-462 行）：

```dart
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const SettingsScreen(),
              ),
            );
          },
        ),
```

改為：

```dart
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    SettingsScreen(prefsManager: widget.prefsManager),
              ),
            );
          },
        ),
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/settings_screen_test.dart
flutter test test/screens/library_screen_test.dart
```

Expected：全數 PASS（`library_screen_test.dart` 既有測試不涉及 `SettingsScreen` 導航，本次修改不應造成回歸，此處執行純粹確認 `library_screen.dart` 的其餘既有功能未被破壞）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/settings_screen.dart app/lib/screens/library_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "feat(epic-7): wire NavZoneSettingsScreen entry into SettingsScreen"
```

---

### Task 5：全域驗證與收尾

**Files:** 無異動（本 Task 僅執行驗證指令，不修改任何檔案）

**Interfaces:**
- Consumes：Task 1-4 全部產出
- Produces：驗收證據（`flutter analyze`/`flutter test` 輸出），供人類判斷本 issue 是否可合併

- [ ] **Step 1：`flutter analyze` 全專案靜態分析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：`flutter test` 執行全專案測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
```

Expected：全數 PASS，含本 issue 新增的 `nav_zone_settings_screen_test.dart`，以及擴充後的 `reader_prefs_manager_test.dart`／`settings_screen_test.dart`，無既有測試因 `SettingsScreen`/`ReaderPrefsManager` 介面異動而回歸失敗。

- [ ] **Step 3：確認 `git status` 乾淨（無未提交變更）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無輸出（Task 1-4 皆已個別 commit）。

（本 Task 不修改任何檔案，無需 commit。）

---

## Self-Review 摘要

- **Spec coverage**：`issues.md` Issue 3 描述的 3 項模組異動（`SettingsScreen` 入口、`NavZoneSettingsScreen` 四選一模板＋自訂編輯器＋輔助線開關、儲存前驗證）與全部單元測試要求，逐一對應 Task 2-4；驗收標準（測試通過、`flutter analyze` 乾淨、不需真實裝置）對應 Task 5。Task 1 是為了滿足 spec.md「讀寫對象為 GlobalReaderPrefs（透過 ReaderPrefsManager）」而新增的必要基礎設施（`ReaderPrefsManager` 原本沒有不依附 bookId 的讀取方法），issues.md 未明文列出但屬於實作本 issue 無法迴避的前置需求，已在計畫開頭「Architecture」段落說明理由。
- **Placeholder scan**：所有 Task 的程式碼區塊皆為完整可執行內容，無 TBD/待補。
- **Type consistency**：`NavZoneSettingsScreen`／`SettingsScreen` 建構參數 `prefsManager: ReaderPrefsManager` 命名與型別在 Task 2-4 間保持一致；`loadGlobalPrefs()`／`isValidCustomZoneConfig()`／`ZoneAction`／`NavZoneMode` 等名稱與 epic-7 Issue 2 既有定義逐字一致。
