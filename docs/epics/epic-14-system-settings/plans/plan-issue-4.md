# Epic 14 Issue 4 — 閱讀預設值畫面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增「閱讀預設值」設定畫面，集中呈現音量鍵翻頁開關、翻頁模式、螢幕方向、全螢幕模式四項全域預設值（FR-36/37/38/42），各自獨立即時生效；並補上 `fullscreen` 全域-單書雙層解析與 `volumeKeyEnabled` 全域開關對 `ReaderScreen` 音量鍵翻頁的門閥判定。

**Architecture:** 沿用 `NavZoneSettingsScreen`（epic-7-interaction Issue 3）既有的「讀寫 `GlobalReaderPrefs`、即時呼叫 `saveGlobalPrefs()`、無儲存按鈕」互動模式與程式碼結構（`StatefulWidget` + `_load()`/`_update()` 兩個核心方法）。資料層新增 `GlobalReaderPrefs.volumeKeyEnabled`／`fullscreen` 兩個 non-nullable 欄位（皆有預設值，`copyWith` 簽章沿用既有 nullable-覆寫模式），`ReaderPrefsManagerImpl` 新增對應 SharedPreferences key（沿用既有 `global_reader_<欄位名>` 命名慣例）與 `resolve()` 內的雙層解析／直接透傳邏輯，`ResolvedPreferences` 新增 `volumeKeyEnabled` 欄位供 `ReaderScreen._handleVolumeKeyCall` 早期 `return` 判斷用。`fullscreen` 欄位本身（`BookReaderPrefs.fullscreen`／`ResolvedPreferences.fullscreen`）已存在（epic-19-shelf-reading-enhance Issue 1），本次只補上全域層與雙層解析，不重新設計。

**Tech Stack:** Flutter/Dart，純 widget test（`flutter test`），不需真機、不需 SQLite migration（`GlobalReaderPrefs` 全部走 SharedPreferences，既有慣例）。

## Global Constraints

- **SharedPreferences key 命名**：沿用 `reader_prefs_manager_impl.dart` 既有的 `global_reader_<欄位名>` 命名慣例——`volumeKeyEnabled` → `global_reader_volume_key_enabled`，`fullscreen` → `global_reader_fullscreen`（spec.md「閱讀預設值模組」，design.md 決策 6）。
- **`GlobalReaderPrefs` 新欄位的建構子預設值**（**不要**改成 `required`）：`volumeKeyEnabled` 預設 `true`、`fullscreen` 預設 `false`，直接寫在主建構子的具名參數預設值（`this.volumeKeyEnabled = true`），沿用 `ResolvedPreferences.fullscreen` 既有 `this.fullscreen = false` 的模式——這樣 `test/reader/global_reader_prefs_test.dart`／`test/reader/reader_prefs_manager_test.dart`／`test/screens/toc_bottom_sheet_test.dart` 等既有直接呼叫 `GlobalReaderPrefs(...)`／`ResolvedPreferences(...)` 建構子、未傳入新欄位的既有測試呼叫點完全不需要修改也能繼續編譯通過（見 Self-Review Notes）。
- **`ReadingDefaultsScreen` 即時生效、不設「儲存」按鈕**：每項控制項變更當下立即呼叫 `saveGlobalPrefs()`，這是刻意的決定（spec.md「Further Notes」：無預覽跟要不要即時存檔是兩個獨立問題，四項設定彼此獨立不需要批次提交語意），**不要**因為看起來像疏漏而加上儲存按鈕或確認對話框。
- **`fullscreen` 雙層解析**：`resolve()` 內由目前的 `book.fullscreen ?? false` 改為 `book.fullscreen ?? global.fullscreen`（比照既有 `pageTurnMode`/`screenOrientation` 雙層解析寫法）。
- **`volumeKeyEnabled` 無單書覆寫層**：`resolve()` 內直接 `volumeKeyEnabled: global.volumeKeyEnabled`，不新增 `BookReaderPrefs` 欄位（FR-36 本身即為全域總開關語意，spec.md 未定義單書覆寫）。
- **`ReadingDefaultsScreen` 不接受 `bookId` 參數**：熱區/全域設定畫面既有慣例（比照 `NavZoneSettingsScreen`），全域生效不做單書覆寫。
- **良好測試判準**（比照專案既有慣例）：只驗證外部可觀察行為（`saveGlobalPrefs` 呼叫紀錄與其攜帶的值、SharedPreferences 最終寫入值、`MethodChannel` 呼叫紀錄），不斷言內部實作細節。

---

### Task 1：`GlobalReaderPrefs` 新增 `volumeKeyEnabled`／`fullscreen` 兩欄位

**Files:**
- Modify：`app/lib/reader/global_reader_prefs.dart`
- Test：`app/test/reader/global_reader_prefs_test.dart`

**Interfaces:**
- Consumes：無（純資料類別，本 Task 不依賴其他 Task）
- Produces：`GlobalReaderPrefs.volumeKeyEnabled`（`bool`，預設 `true`）、`GlobalReaderPrefs.fullscreen`（`bool`，預設 `false`），`copyWith({..., bool? volumeKeyEnabled, bool? fullscreen})`，供 Task 2（`ReaderPrefsManagerImpl`）與 Task 4（`ReadingDefaultsScreen`）使用

- [ ] **Step 1：撰寫失敗測試**

在 `app/test/reader/global_reader_prefs_test.dart` 檔案結尾（第 97 行 `expect(a == b, isFalse);` 之後、第 98 行 `}` 之前）新增：

```dart

  test('GlobalReaderPrefs.initial() 的 volumeKeyEnabled 預設 true、fullscreen 預設 false',
      () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.volumeKeyEnabled, isTrue);
    expect(prefs.fullscreen, isFalse);
  });

  test('copyWith 可個別更新 volumeKeyEnabled／fullscreen，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated =
        original.copyWith(volumeKeyEnabled: false, fullscreen: true);
    expect(updated.volumeKeyEnabled, isFalse);
    expect(updated.fullscreen, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
    expect(updated.navZoneMode, original.navZoneMode);
  });

  test('volumeKeyEnabled 或 fullscreen 不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    final b = a.copyWith(volumeKeyEnabled: false);
    expect(a == b, isFalse);
    final c = a.copyWith(fullscreen: true);
    expect(a == c, isFalse);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：FAIL——`GlobalReaderPrefs` 尚未定義 `volumeKeyEnabled`/`fullscreen`（編譯錯誤）。

- [ ] **Step 3：修改 `global_reader_prefs.dart`**

以下列內容取代整個檔案（原檔案 81 行）：

```dart
import 'package:flutter/foundation.dart';

import 'nav_zone_mode.dart';
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';
import 'zone_action.dart';

/// 跨書生效的全域預設閱讀偏好。
///
/// 七個欄位皆 non-nullable——與 [BookReaderPrefs] 的「全欄位 nullable、
/// null=未覆寫」語意刻意不同：全域層本身沒有更上層的預設可回退，任何時候
/// 都必須有一個明確生效值。
class GlobalReaderPrefs {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  /// 熱區映射模式，預設 [NavZoneMode.rightFlip]（design.md「新增的
  /// GlobalReaderPrefs 欄位」）。
  final NavZoneMode navZoneMode;

  /// 長度固定 9。僅 [navZoneMode] 為 [NavZoneMode.custom] 時內容才生效
  /// （其餘模式由 [resolveZoneActions] 查表算出，忽略本欄位）；仍持續
  /// 保留是為了使用者切回自訂模式時能還原上次編輯結果。
  final List<ZoneAction> navZoneCustomActions;

  /// 是否顯示熱區輔助線，預設 `false`。
  final bool showNavZoneDebugOverlay;

  /// 音量鍵翻頁總開關（FR-36，epic-14-system-settings Issue 4），預設
  /// `true`（沿用既有行為，不影響升級前的使用者體驗）。無單書覆寫層——
  /// `ReaderPrefsManagerImpl.resolve()` 直接透傳本欄位。
  final bool volumeKeyEnabled;

  /// 全螢幕模式全域預設值（FR-42，epic-14-system-settings Issue 4），
  /// 預設 `false`。與既有單書層 `BookReaderPrefs.fullscreen` 為雙層解析
  /// 關係（`book.fullscreen ?? global.fullscreen`），涵蓋 EPUB 流式／
  /// FXL／PDF 三種格式（design.md 決策 6）。
  final bool fullscreen;

  const GlobalReaderPrefs({
    required this.pageTurnMode,
    required this.screenOrientation,
    required this.navZoneMode,
    required this.navZoneCustomActions,
    required this.showNavZoneDebugOverlay,
    this.volumeKeyEnabled = true,
    this.fullscreen = false,
  });

  /// 初始值，與現行 GlobalReaderDefaults 的既有硬編碼預設一致，
  /// 不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto,
        navZoneMode = NavZoneMode.rightFlip,
        navZoneCustomActions = rightFlipZoneTemplate,
        showNavZoneDebugOverlay = false,
        volumeKeyEnabled = true,
        fullscreen = false;

  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
    bool? volumeKeyEnabled,
    bool? fullscreen,
  }) {
    return GlobalReaderPrefs(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      navZoneMode: navZoneMode ?? this.navZoneMode,
      navZoneCustomActions: navZoneCustomActions ?? this.navZoneCustomActions,
      showNavZoneDebugOverlay:
          showNavZoneDebugOverlay ?? this.showNavZoneDebugOverlay,
      volumeKeyEnabled: volumeKeyEnabled ?? this.volumeKeyEnabled,
      fullscreen: fullscreen ?? this.fullscreen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay &&
      other.volumeKeyEnabled == volumeKeyEnabled &&
      other.fullscreen == fullscreen;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
        volumeKeyEnabled,
        fullscreen,
      );
}
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：全數 PASS（含既有 5 個測試不受影響）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/reader/global_reader_prefs.dart test/reader/global_reader_prefs_test.dart
git commit -m "feat(epic-14): Issue 4 Task 1 — GlobalReaderPrefs 新增 volumeKeyEnabled/fullscreen"
```

Expected：`flutter analyze` 顯示 "No issues found!"。

---

### Task 2：`ReaderPrefsManagerImpl` 讀寫 + `resolve()` 雙層解析 + `ResolvedPreferences` 新欄位

**Files:**
- Modify：`app/lib/reader/reader_prefs_manager_impl.dart`
- Modify：`app/lib/reader/resolved_preferences.dart`
- Test：`app/test/reader/reader_prefs_manager_test.dart`
- Test：`app/test/reader/resolved_preferences_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `GlobalReaderPrefs.volumeKeyEnabled`／`fullscreen`
- Produces：`ResolvedPreferences.volumeKeyEnabled`（`bool`，預設 `true`），`ReaderPrefsManagerImpl.resolve()` 正確填入 `volumeKeyEnabled: global.volumeKeyEnabled`／`fullscreen: book.fullscreen ?? global.fullscreen`；`ReaderPrefsManagerImpl.loadGlobalPrefs()`/`saveGlobalPrefs()` 正確讀寫新的 2 個 SharedPreferences key。供 Task 3（`ReaderScreen._handleVolumeKeyCall`）與 Task 4（`ReadingDefaultsScreen`）使用

- [ ] **Step 1：撰寫失敗測試——`ResolvedPreferences` 新欄位**

`app/test/reader/resolved_preferences_test.dart` 第 12 行既有 `test(...)` 之後（第 52 行 `});` 之後、檔案結尾 `}` 之前）新增：

```dart

  test('volumeKeyEnabled 未傳入時預設 true', () {
    const resolved = ResolvedPreferences(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      dualPageMode: DualPageMode.auto,
      dualPageCoverAlone: true,
      dualPageDirection: DualPageDirection.ltr,
      showHeader: true,
      showFooter: true,
      navZoneActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );
    expect(resolved.volumeKeyEnabled, isTrue);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/resolved_preferences_test.dart
```

Expected：FAIL——`ResolvedPreferences` 尚未定義 `volumeKeyEnabled`（編譯錯誤）。

- [ ] **Step 3：`resolved_preferences.dart` 新增 `volumeKeyEnabled` 欄位**

第 71-74 行（`fullscreen` 欄位宣告）之前插入：

```dart
  /// 全域音量鍵翻頁開關（epic-14-system-settings Issue 4）：恆非 null，
  /// resolve() 內直接透傳 global.volumeKeyEnabled（無單書覆寫層，FR-36
  /// 本身即為全域總開關語意）。
  final bool volumeKeyEnabled;

```

第 107 行 `this.fullscreen = false,` 之前插入：

```dart
    this.volumeKeyEnabled = true,
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/resolved_preferences_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：撰寫失敗測試——`ReaderPrefsManagerImpl` 雙層解析與讀寫**

`app/test/reader/reader_prefs_manager_test.dart` 第 39-64 行既有測試 `test('全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值', () { ... });` 內，第 63 行 `expect(resolved.fullscreen, isFalse);` 之後新增一行：

```dart
      expect(resolved.volumeKeyEnabled, isTrue);
```

第 98 行（單書覆寫測試 `});`）之後新增：

```dart

    test('book.fullscreen 為 null 時退回 global.fullscreen（非硬編碼 false，證明雙層解析生效）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs:
            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.fullscreen, isTrue);
    });

    test('book.fullscreen 存在時優先於 global.fullscreen', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(fullscreen: false),
        globalPrefs:
            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.fullscreen, isFalse);
    });

    test('volumeKeyEnabled 直接透傳 global 值，無單書覆寫層', () {
      final loadedEnabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      expect(manager.resolve(loadedEnabled).volumeKeyEnabled, isTrue);

      final loadedDisabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial()
            .copyWith(volumeKeyEnabled: false),
      );
      expect(manager.resolve(loadedDisabled).volumeKeyEnabled, isFalse);
    });
```

在 `group('load()...')` 內，第 281 行（`loadGlobalPrefs() 回傳與 load(bookId).globalPrefs 一致的值` 測試的 `});`）之後新增：

```dart

    test('saveGlobalPrefs 寫入 volumeKeyEnabled／fullscreen 至既有慣例命名的 SharedPreferences key',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        volumeKeyEnabled: false,
        fullscreen: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('global_reader_volume_key_enabled'), isFalse);
      expect(sp.getBool('global_reader_fullscreen'), isTrue);

      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.volumeKeyEnabled, isFalse);
      expect(loaded.globalPrefs.fullscreen, isTrue);
    });

    test('volumeKeyEnabled／fullscreen 未儲存過（缺鍵）時，安全回退為預設值 true／false',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.volumeKeyEnabled, isTrue);
      expect(loaded.globalPrefs.fullscreen, isFalse);
    });
```

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL——`resolved.volumeKeyEnabled`/`GlobalReaderPrefs(volumeKeyEnabled: ...)` 尚未存在，或 `fullscreen` 雙層解析斷言不成立（目前 `resolve()` 仍是 `book.fullscreen ?? false`，Task 1 完成後編譯可過但邏輯測試會失敗）。

- [ ] **Step 7：修改 `reader_prefs_manager_impl.dart`**

第 42-43 行（`_navZoneDebugOverlayKey` 常數宣告）之後新增：

```dart
  static const _volumeKeyEnabledKey = 'global_reader_volume_key_enabled';
  static const _fullscreenKey = 'global_reader_fullscreen';
```

第 65-82 行 `loadGlobalPrefs()` 改為：

```dart
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
      volumeKeyEnabled: sp.getBool(_volumeKeyEnabledKey) ?? true,
      fullscreen: sp.getBool(_fullscreenKey) ?? false,
    );
  }
```

第 122-133 行 `saveGlobalPrefs()` 改為：

```dart
  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
    await sp.setString(_navZoneModeKey, prefs.navZoneMode.name);
    await sp.setString(
      _navZoneCustomActionsKey,
      _encodeZoneActions(prefs.navZoneCustomActions),
    );
    await sp.setBool(_navZoneDebugOverlayKey, prefs.showNavZoneDebugOverlay);
    await sp.setBool(_volumeKeyEnabledKey, prefs.volumeKeyEnabled);
    await sp.setBool(_fullscreenKey, prefs.fullscreen);
  }
```

第 181-184 行 `resolve()` 尾段改為：

```dart
      navZoneActions:
          resolveZoneActions(global.navZoneMode, global.navZoneCustomActions),
      showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,
      fullscreen: book.fullscreen ?? global.fullscreen,
      volumeKeyEnabled: global.volumeKeyEnabled,
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart test/reader/global_reader_prefs_test.dart
```

Expected：全數 PASS。

- [ ] **Step 9：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
git add lib/reader/reader_prefs_manager_impl.dart lib/reader/resolved_preferences.dart test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart
git commit -m "feat(epic-14): Issue 4 Task 2 — resolve() fullscreen 雙層解析 + volumeKeyEnabled 透傳"
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（含既有測試不受影響——`ResolvedPreferences`／`GlobalReaderPrefs` 新欄位皆有預設值，不影響任何既有未傳入新欄位的建構呼叫點）。

---

### Task 3：`ReaderScreen` 音量鍵開關門閥判定

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Test：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `ResolvedPreferences.volumeKeyEnabled`（透過既有 `_resolved` 欄位取得）
- Produces：無新公開介面——`_handleVolumeKeyCall` 為既有私有方法，行為擴充

- [ ] **Step 1：撰寫失敗測試**

`app/test/screens/reader_screen_test.dart` 第 1-5 行 import 區塊（`dart:async` 之後）新增：

```dart
import 'package:elinkbook/reader/global_reader_prefs.dart';
```

第 2976 行（既有測試 `'音量鍵 onVolumeKey(up/down) 觸發真實換頁（PDF，模擬原生端會呼叫的全域頻道）'` 的結尾 `});`）之後、第 2978 行 `testWidgets('PopScope：...` 之前，新增：

```dart

  testWidgets('全域音量鍵開關關閉時，onVolumeKey 觸發被忽略，不執行翻頁', (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );

    final disabledPrefsManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(volumeKeyEnabled: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: disabledPrefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final byteData = volumeKeyChannel.codec.encodeMethodCall(
      const MethodCall('onVolumeKey', {'direction': 'down'}),
    );
    await binaryMessenger.handlePlatformMessage(
      volumeKeyChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    expect(
      instanceCalls.any((c) => c.method == 'nextPage'),
      isFalse,
      reason: '全域音量鍵開關關閉時，onVolumeKey(down) 不應觸發翻頁',
    );
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/reader_screen_test.dart --plain-name "全域音量鍵開關關閉時"
```

Expected：FAIL——目前 `_handleVolumeKeyCall` 沒有檢查 `volumeKeyEnabled`，`instanceCalls` 會包含 `nextPage`。

- [ ] **Step 3：修改 `_handleVolumeKeyCall`**

`app/lib/screens/reader_screen.dart` 第 1922-1937 行改為：

```dart
  /// `MainActivity.dispatchKeyEvent()` 攔截音量鍵後的回呼
  /// （epic-7-interaction Issue 7）：方向固定映射，不查詢
  /// `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律上一頁、
  /// `down` 一律下一頁。全域音量鍵開關關閉時（`_resolved?.volumeKeyEnabled
  /// == false`，epic-14-system-settings Issue 4）忽略此次觸發。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    if (_resolved?.volumeKeyEnabled == false) return;
    final args = call.arguments as Map<Object?, Object?>;
    switch (args['direction'] as String?) {
      case 'up':
        _handleZoneAction(ZoneAction.previousPage);
        break;
      case 'down':
        _handleZoneAction(ZoneAction.nextPage);
        break;
    }
  }
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含既有「音量鍵 onVolumeKey(up/down) 觸發真實換頁」測試不受影響——該測試使用預設 `FakeReaderPrefsManager()`，`GlobalReaderPrefs.initial().volumeKeyEnabled` 為 `true`）。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
git commit -m "feat(epic-14): Issue 4 Task 3 — ReaderScreen 全域音量鍵開關門閥判定"
```

Expected：`flutter analyze` "No issues found!"。

---

### Task 4：新建 `ReadingDefaultsScreen`

**Files:**
- Create：`app/lib/screens/reading_defaults_screen.dart`
- Test：`app/test/screens/reading_defaults_screen_test.dart`

**Interfaces:**
- Consumes：Task 1/2 的 `GlobalReaderPrefs`（`volumeKeyEnabled`／`pageTurnMode`／`screenOrientation`／`fullscreen` 四欄位 + `copyWith`）、既有 `ReaderPrefsManager`（`loadGlobalPrefs()`／`saveGlobalPrefs()`）
- Produces：`class ReadingDefaultsScreen extends StatefulWidget`，建構參數 `{required ReaderPrefsManager prefsManager}`，供 Task 5（`SettingsScreen`）串接

- [ ] **Step 1：建立失敗測試檔案**

建立 `app/test/screens/reading_defaults_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/reading_defaults_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示四項控制項與既有 GlobalReaderPrefs 初始值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        volumeKeyEnabled: false,
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
        fullscreen: true,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));

    expect(
      find.byKey(const Key('reading_defaults_loading_indicator')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reading_defaults_loading_indicator')),
      findsNothing,
    );

    final volumeSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('reading_defaults_volume_key_switch')),
    );
    expect(volumeSwitch.value, isFalse);

    final fullscreenSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('reading_defaults_fullscreen_switch')),
    );
    expect(fullscreenSwitch.value, isTrue);

    final scrollTile = tester.widget<RadioListTile<PageTurnMode>>(
      find.byKey(const Key('reading_defaults_page_turn_mode_scroll')),
    );
    expect(scrollTile.value, PageTurnMode.scroll);

    expect(
      find.byKey(const Key('reading_defaults_screen_orientation_lock90')),
      findsOneWidget,
    );
  });

  testWidgets('切換音量鍵翻頁開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('reading_defaults_volume_key_switch')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(fakeManager.savedGlobalPrefsCalls.last.volumeKeyEnabled, isFalse);
  });

  testWidgets('切換全螢幕模式開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('reading_defaults_fullscreen_switch')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.fullscreen, isTrue);
  });

  testWidgets('點選翻頁模式選項立即呼叫 saveGlobalPrefs 更新為對應模式', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reading_defaults_page_turn_mode_scroll')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.pageTurnMode,
      PageTurnMode.scroll,
    );
  });

  testWidgets('點選螢幕方向選項立即呼叫 saveGlobalPrefs 更新為對應設定', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reading_defaults_screen_orientation_lock180')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.screenOrientation,
      ScreenOrientationSetting.lock180,
    );
  });

  testWidgets('畫面上不存在任何「儲存」按鈕', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.text('儲存'), findsNothing);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/reading_defaults_screen_test.dart
```

Expected：FAIL——`package:elinkbook/screens/reading_defaults_screen.dart` 不存在（編譯錯誤）。

- [ ] **Step 3：建立 `ReadingDefaultsScreen`**

建立 `app/lib/screens/reading_defaults_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/page_turn_mode.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/screen_orientation_setting.dart';

/// 閱讀預設值畫面（FR-36/37/38/42）：音量鍵翻頁開關、翻頁模式、螢幕方向、
/// 全螢幕模式四個獨立控制項，皆讀寫 [GlobalReaderPrefs]。**即時生效、無
/// 「儲存」按鈕**——每項控制項變更當下立即呼叫 `saveGlobalPrefs()`，互動
/// 模式比照既有 `NavZoneSettingsScreen`（design.md 決策 1，spec.md「閱讀
/// 預設值模組」：無預覽跟要不要即時存檔是兩個獨立問題，四項設定彼此獨立
/// 不需要批次提交語意，刻意決定不做「儲存」按鈕，勿因看起來像疏漏而改回
/// 儲存按鈕模式）。全域生效，不做單書覆寫，本畫面不接受 bookId 參數。
class ReadingDefaultsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;

  const ReadingDefaultsScreen({super.key, required this.prefsManager});

  @override
  State<ReadingDefaultsScreen> createState() => _ReadingDefaultsScreenState();
}

class _ReadingDefaultsScreenState extends State<ReadingDefaultsScreen> {
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

  void _update(GlobalReaderPrefs updated) {
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('閱讀預設值')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('reading_defaults_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                SwitchListTile(
                  key: const Key('reading_defaults_volume_key_switch'),
                  title: const Text('音量鍵翻頁'),
                  value: _prefs.volumeKeyEnabled,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(volumeKeyEnabled: value)),
                ),
                const Divider(height: 1),
                _buildSectionHeader(context, '翻頁模式'),
                RadioGroup<PageTurnMode>(
                  groupValue: _prefs.pageTurnMode,
                  onChanged: (mode) =>
                      _update(_prefs.copyWith(pageTurnMode: mode)),
                  child: Column(
                    children: [
                      RadioListTile<PageTurnMode>(
                        key: const Key(
                            'reading_defaults_page_turn_mode_paginated'),
                        title: const Text('點擊翻頁'),
                        value: PageTurnMode.paginated,
                      ),
                      RadioListTile<PageTurnMode>(
                        key: const Key(
                            'reading_defaults_page_turn_mode_scroll'),
                        title: const Text('滾動翻頁'),
                        value: PageTurnMode.scroll,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _buildSectionHeader(context, '螢幕方向'),
                RadioGroup<ScreenOrientationSetting>(
                  groupValue: _prefs.screenOrientation,
                  onChanged: (setting) =>
                      _update(_prefs.copyWith(screenOrientation: setting)),
                  child: Column(
                    children: [
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_auto'),
                        title: const Text('自動旋轉'),
                        value: ScreenOrientationSetting.auto,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock0'),
                        title: const Text('鎖定 0°'),
                        value: ScreenOrientationSetting.lock0,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock90'),
                        title: const Text('鎖定 90°'),
                        value: ScreenOrientationSetting.lock90,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock180'),
                        title: const Text('鎖定 180°'),
                        value: ScreenOrientationSetting.lock180,
                      ),
                      RadioListTile<ScreenOrientationSetting>(
                        key: const Key(
                            'reading_defaults_screen_orientation_lock270'),
                        title: const Text('鎖定 270°'),
                        value: ScreenOrientationSetting.lock270,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_fullscreen_switch'),
                  title: const Text('全螢幕模式'),
                  value: _prefs.fullscreen,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(fullscreen: value)),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/reading_defaults_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/screens/reading_defaults_screen.dart test/screens/reading_defaults_screen_test.dart
git commit -m "feat(epic-14): Issue 4 Task 4 — 新建 ReadingDefaultsScreen"
```

Expected：`flutter analyze` "No issues found!"。

---

### Task 5：`SettingsScreen` 新增「閱讀預設值」入口

**Files:**
- Modify：`app/lib/screens/settings_screen.dart`
- Test：`app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes：Task 4 的 `ReadingDefaultsScreen({required ReaderPrefsManager prefsManager})`
- Produces：無（本 Task 為 Epic 14 字型模組（Issue 1-3）與閱讀預設值模組（本 Issue）在 `SettingsScreen` 上的最終入口串接，`SettingsScreen` 主列表最終為「佈景／字型管理／閱讀預設值／導航熱區／關於」，design.md 決策 1）

- [ ] **Step 1：撰寫失敗測試**

`app/test/screens/settings_screen_test.dart` 第 30-45 行既有測試 `testWidgets('SettingsScreen 顯示設定標題與「佈景」「關於」「導航熱區」入口', ...)` 內，第 44 行 `findsOneWidget);` 之後新增一行：

```dart
    expect(
        find.byKey(const Key('settings_reading_defaults_button')),
        findsOneWidget);
```

第 120 行（既有最後一個測試 `testWidgets('點擊「字型管理」導航至 FontManagementScreen', ...)` 的結尾 `});`）之後、檔案結尾 `}` 之前，新增：

```dart

  testWidgets('點擊「閱讀預設值」導航至 ReadingDefaultsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester
        .tap(find.byKey(const Key('settings_reading_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀預設值'), findsOneWidget);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/settings_screen_test.dart
```

Expected：FAIL——`settings_reading_defaults_button` 尚不存在。

- [ ] **Step 3：修改 `settings_screen.dart`**

第 1-8 行 import 區塊改為：

```dart
import 'package:flutter/material.dart';

import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reading_defaults_screen.dart';
```

第 10-12 行類別文件註解改為：

```dart
/// 設定畫面：「佈景」（主題圓點，原位於 `LibraryScreen` AppBar，見
/// `epic-18-reader-device-qa` 工具列溢位修復）、「字型管理」、「閱讀預設值」、
/// 「導航熱區」與「關於」五個項目。
```

第 66 行（「字型管理」`ListTile` 結尾 `),`）之後、第 67 行「導航熱區」`ListTile` 之前，插入：

```dart
          ListTile(
            key: const Key('settings_reading_defaults_button'),
            title: const Text('閱讀預設值'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ReadingDefaultsScreen(prefsManager: prefsManager),
                ),
              );
            },
          ),
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/settings_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
git add lib/screens/settings_screen.dart test/screens/settings_screen_test.dart
git commit -m "feat(epic-14): Issue 4 Task 5 — SettingsScreen 新增「閱讀預設值」入口"
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（無 Regression）。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

**Spec 覆蓋檢查**（對照 `issues.md` Issue 4「驗收標準」6 項）：

1. `GlobalReaderPrefs` 新增 `volumeKeyEnabled`／`fullscreen`，key 命名與既有慣例一致 → Task 1（欄位）＋ Task 2（SharedPreferences key）。
2. `ReadingDefaultsScreen` 四項控制項即時生效、無儲存按鈕 → Task 4（含專屬測試「畫面上不存在任何『儲存』按鈕」）。
3. `SettingsScreen` 新增「閱讀預設值」入口可正確導航 → Task 5。
4. `resolve()` 的 `fullscreen` 雙層解析正確（單書覆寫 > 全域 > 預設 `false`）→ Task 2（`book.fullscreen ?? global.fullscreen`，`BookReaderPrefs.fullscreen` 為 null 時退回全域、非 null 時優先，兩種情境皆有獨立測試）。
5. 全域音量鍵開關關閉時，`ReaderScreen` 忽略音量鍵翻頁觸發 → Task 3。
6. 上述測試皆通過，`flutter analyze` 乾淨 → 每個 Task 結尾皆有 `flutter analyze` 步驟，Task 2/5 額外執行完整 `flutter test` 套件把關 Regression。

**Placeholder 掃描**：全文無 TBD/TODO/「類似 Task N」等字樣，所有程式碼步驟皆為完整可執行內容。

**型別一致性檢查**：`GlobalReaderPrefs.volumeKeyEnabled`／`fullscreen`（Task 1）→ `ResolvedPreferences.volumeKeyEnabled`（Task 2，型別皆為 `bool`）→ `ReadingDefaultsScreen` 讀寫的 `_prefs.volumeKeyEnabled`／`_prefs.fullscreen`（Task 4，皆透過 `GlobalReaderPrefs.copyWith` 存取，型別一致）→ `ReaderScreen._resolved?.volumeKeyEnabled`（Task 3，存取 Task 2 產出的 `ResolvedPreferences` 欄位）。`ReadingDefaultsScreen({required ReaderPrefsManager prefsManager})` 建構參數命名與型別（Task 4 Produces）與 `SettingsScreen` 既有 `prefsManager` 欄位型別（Task 5 Consumes）一致。

**既有測試相容性檢查**：`GlobalReaderPrefs`／`ResolvedPreferences` 新欄位皆為具預設值的具名參數（非 `required`），`test/reader/global_reader_prefs_test.dart`（5 個既有測試）、`test/reader/reader_prefs_manager_test.dart`（多處直接呼叫 `GlobalReaderPrefs(...)`／`LoadedPrefs(...)`）、`test/reader/resolved_preferences_test.dart`、`test/screens/toc_bottom_sheet_test.dart` 這些既有直接建構 `GlobalReaderPrefs(...)`/`ResolvedPreferences(...)` 卻未傳入新欄位的呼叫點，全部維持可編譯、行為不變，不需要修改（已於 Global Constraints 明確記錄，避免實作時誤判「忘記更新」而動手改動不相關的既有測試）。

**與既有音量鍵測試的相容性**：Task 3 新增的門閥判定只在 `_resolved?.volumeKeyEnabled == false` 時生效；既有測試「音量鍵 onVolumeKey(up/down) 觸發真實換頁」使用預設 `FakeReaderPrefsManager()`（`GlobalReaderPrefs.initial().volumeKeyEnabled` 為 `true`），不受影響。
