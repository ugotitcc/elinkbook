# Epic 36 Issue 5：設定畫面四分區＋`GlobalReaderPrefs` 持久化契約 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定畫面重構為「外觀／閱讀／同步與帳號／關於」四分區（`SettingsScreen` 更名為 `SettingsScaffold`），並補上「顯示頁首/頁尾」全域預設與「朗讀語音與語速」兩組新設定項的持久化契約（`GlobalReaderPrefs` 新增 4 個欄位）。

**Architecture：** 純重排＋新增，不重寫既有邏輯。`GlobalReaderPrefs`／`ReaderPrefsManagerImpl` 先獨立完成 4 個新欄位的資料層（Task 1-2），再進行 `SettingsScreen`→`SettingsScaffold` 更名與四分區重排（Task 3-4，純搬遷既有 `ListTile`，不改行為），然後疊加「來源」「書架」導覽圖示（Task 5）、`ReadingDefaultsScreen` 新開關（Task 6）、全新 `TtsDefaultsScreen`（Task 7），最後一次性全套驗證（Task 8）。除 Task 1-2 的資料層可獨立先行外，其餘 Task 依序疊加同一個檔案（`settings_scaffold.dart`），順序不可打亂。

**Tech Stack：** Flutter 3.41.9；既有 `flutter_test` widget test 慣例；`RadioGroup<T>` Flutter 3.32+ 新 API（`ReadingDefaultsScreen` 已有既有用法可參考）；`Slider`＋內聯 `+`/`-` `IconButton` 微調（`reader_settings_sheet.dart` 既有慣例，`.clamp()` 在本專案 Dart/Flutter SDK 版本下對 `double` 接收者維持 `double` 靜態型別、已用 `flutter analyze` 實測確認乾淨，不需要額外 `.toDouble()`）。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/spec.md` §功能⑤、`docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 5。

## Global Constraints

- 本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目（`issues.md` 共同規則）。
- `EBButton`／`EBIconButton`／`EBStepper`／`EBRadius` 等 `DESIGN.md` 第一層基礎元件命名本 Epic 明確排除；本 Issue 只落地 `EBSectionHeader` 一個新基礎元件，數值型控制項（TTS 語速）沿用既有 `Slider`＋內聯 `+`/`-` `IconButton` 慣例，不預先建立 `EBStepper`（`spec.md` 功能⑤明文決策）。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔，全套 `flutter test`（不帶路徑）留到最後一個 Task 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。
- **（`review-plan-issue-2.md` I-1 教訓沿用）**：任何 Task 的收尾 Commit 前，該 Task 實際觸及的測試檔必須 100% PASS，不得把已知失敗留到下一個 Task 才修。
- TTS 播放端何時讀取套用 `ttsVoiceId`/`defaultTtsSpeed` 為預設值，不在本 Issue 範圍內（`spec.md` Out of Scope，留給下一個涉及 TTS 播放邏輯的 Epic）。
- 平板/桌機 `NavigationRail`、`DESIGN.md` §16 `SourceBrowser` 新架構、閱讀器 Chrome/TTS UI 重構、「關於」區塊「連點版號」手勢，皆不在本 Issue 範圍（`spec.md` Out of Scope）。

## 計劃範圍澄清（撰寫本計劃時發現並解決的 spec.md 內部落差）

1. **`spec.md`「已知測試影響」清單遺漏 `app/test/screens/adaptive_shell_scaffold_test.dart`**：`spec.md` Testing Decisions 段落列出的既有測試影響清單（`library_import_button`／`library_eink_toggle`／...／`library_settings_button`）皆屬於 Epic 較早期 Issue 1 的既有測試盤點，唯獨遺漏了 Issue 1 自己新增、也直接引用 `SettingsScreen` 型別的 `app/test/screens/adaptive_shell_scaffold_test.dart`——查證後確認該檔案第 10 行 `import 'package:elinkbook/screens/settings_screen.dart';`，以及第 120-153、155-191 行兩則測試皆用 `tester.widget<SettingsScreen>(find.byType(SettingsScreen))` 直接具現化並斷言型別。`SettingsScreen`→`SettingsScaffold` 更名（Task 3）若不同步更新這個檔案，會導致 `flutter analyze`／`flutter test` 立即編譯失敗（`Error: 'SettingsScreen' isn't a type` 等）。本計劃 Task 3 已將這個檔案的更新納入必要步驟，不是遺漏。
2. **`SettingsScaffold` 新增的 `ttsProvider` 欄位不透過既有的 `LibraryReaderFeatureRepositories` bundle 整包轉送**：`adaptive_shell_scaffold.dart` 目前把 `LibraryReaderFeatureRepositories` 整包轉送給 `LibraryScreen`，但轉送給 `SettingsScreen`（未來 `SettingsScaffold`）時是逐欄位手動挑選（目前只挑了 `customFontsRepository`），比照這個既有慣例，本計劃 Task 7 新增 `ttsProvider` 時同樣採用逐欄位挑選（`ttsProvider: widget.readerFeatureRepositories.ttsProvider`），不是把整個 bundle 傳給 `SettingsScaffold`（`SettingsScaffold` 不需要也不該知道 bundle 型別，只需要它實際用到的兩三個具體依賴，維持既有淺層轉送風格）。
3. **`ReadingDefaultsScreen`／`TtsDefaultsScreen` 兩個新 `SwitchListTile`/控制項的畫面內排列順序，`spec.md` 未明文規定**：`spec.md` 只講「新增兩個 `SwitchListTile`」「比照既有 `_update()` 寫法」，未規定插入既有清單的確切位置。本計劃決定：`ReadingDefaultsScreen` 的兩個新開關附加在既有清單最尾端（`reading_defaults_open_last_book_switch` 之後），最小化對既有清單既有測試（多處使用 `find.byKey` 而非位置索引）的影響面；`TtsDefaultsScreen` 為全新畫面，排列順序（語音在上、語速在下）依 `spec.md` 描述順序（「語音選擇」先於「語速控制」提及）決定。

---

## Task 1：`GlobalReaderPrefs` 新增 4 個欄位

**Files:**
- Modify: `app/lib/reader/global_reader_prefs.dart`
- Test: `app/test/reader/global_reader_prefs_test.dart`

**Interfaces:**
- Produces：`GlobalReaderPrefs` 新增 `final bool showHeader;`／`final bool showFooter;`／`final String? ttsVoiceId;`／`final double defaultTtsSpeed;`（預設分別為 `false`／`false`／`null`／`1.0`），`copyWith`/`==`/`hashCode` 同步支援。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/reader/global_reader_prefs_test.dart` 檔案結尾（`main()` 內最後一個 `test` 之後）新增：

```dart
  test('GlobalReaderPrefs.initial() 的 showHeader／showFooter 預設 false，ttsVoiceId 預設 null，defaultTtsSpeed 預設 1.0',
      () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.showHeader, isFalse);
    expect(prefs.showFooter, isFalse);
    expect(prefs.ttsVoiceId, isNull);
    expect(prefs.defaultTtsSpeed, 1.0);
  });

  test('copyWith 可個別更新 showHeader／showFooter，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated =
        original.copyWith(showHeader: true, showFooter: true);
    expect(updated.showHeader, isTrue);
    expect(updated.showFooter, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
    expect(updated.volumeKeyEnabled, original.volumeKeyEnabled);
  });

  test('copyWith 可更新 ttsVoiceId／defaultTtsSpeed，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated = original.copyWith(
      ttsVoiceId: 'voice-1',
      defaultTtsSpeed: 1.5,
    );
    expect(updated.ttsVoiceId, 'voice-1');
    expect(updated.defaultTtsSpeed, 1.5);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

  test('showHeader／showFooter／ttsVoiceId／defaultTtsSpeed 不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    final b = a.copyWith(showHeader: true);
    expect(a == b, isFalse);
    final c = a.copyWith(showFooter: true);
    expect(a == c, isFalse);
    final d = a.copyWith(ttsVoiceId: 'voice-1');
    expect(a == d, isFalse);
    final e = a.copyWith(defaultTtsSpeed: 1.25);
    expect(a == e, isFalse);
  });

  test('四個欄位值皆相同（含 ttsVoiceId 皆為 null）的 GlobalReaderPrefs 視為相等，hashCode 也相等',
      () {
    const a = GlobalReaderPrefs.initial();
    const b = GlobalReaderPrefs.initial();
    expect(a, b);
    expect(a.hashCode, b.hashCode);

    final c = a.copyWith(showHeader: true, defaultTtsSpeed: 1.75);
    final d = a.copyWith(showHeader: true, defaultTtsSpeed: 1.75);
    expect(c, d);
    expect(c.hashCode, d.hashCode);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/global_reader_prefs_test.dart`
Expected: FAIL（`showHeader`/`showFooter`/`ttsVoiceId`/`defaultTtsSpeed` 尚不是 `GlobalReaderPrefs` 的欄位，編譯錯誤）

- [ ] **Step 3: 實作**

編輯 `app/lib/reader/global_reader_prefs.dart`：

**3a. 欄位宣告**（緊接在既有 `openLastBookOnLaunch` 欄位定義之後）：

```dart
  /// 「顯示頁首／頁尾」全域預設值（epic-36-adaptive-shelf-navigation
  /// Issue 5，spec.md §功能⑤），預設 `false`——與目前 `reader_screen.dart`
  /// 多處硬編碼的 `?? false` 回退值一致，升級後行為不變。與既有單書層
  /// `BookReaderPrefs.showHeader`/`showFooter` 為雙層解析關係
  /// （`book.showHeader ?? global.showHeader`，見
  /// `ReaderPrefsManagerImpl.resolve()`）。
  final bool showHeader;
  final bool showFooter;

  /// 朗讀（TTS）預設語音 id（epic-36-adaptive-shelf-navigation Issue 5）。
  /// `null` 代表「使用系統預設語音」——語意上沒有一個放諸四海皆準的安全
  /// 非空預設值，不比照本類別其餘欄位一律 non-nullable 的慣例。
  final String? ttsVoiceId;

  /// 朗讀（TTS）預設語速，範圍 0.75x~2.0x（`DESIGN.md#L307` §13.2），
  /// 預設 `1.0`。
  final double defaultTtsSpeed;
```

**3b. 建構子**：在 `const GlobalReaderPrefs({` 參數列的 `this.openLastBookOnLaunch = true,` 之後新增：

```dart
    this.showHeader = false,
    this.showFooter = false,
    this.ttsVoiceId,
    this.defaultTtsSpeed = 1.0,
```

**3c. `.initial()`**（review-plan-issue-5.md M-1：以修改前後完整對比取代文字描述，避免 Dart 具名建構子初始化列表「只有最後一項用分號、其餘一律用逗號」的標點規則被誤放）：

修改前（結尾為分號）：

```dart
        openLastBookOnLaunch = true;
```

修改後（原本的分號改逗號，新 4 行接續，最後一行才用分號）：

```dart
        openLastBookOnLaunch = true,
        showHeader = false,
        showFooter = false,
        ttsVoiceId = null,
        defaultTtsSpeed = 1.0;
```

**3d. `copyWith`**：參數列新增，並在回傳的建構呼叫中新增對應行：

```dart
  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
    bool? volumeKeyEnabled,
    bool? fullscreen,
    bool? consoleLogEnabled,
    bool? openLastBookOnLaunch,
    bool? showHeader,
    bool? showFooter,
    String? ttsVoiceId,
    double? defaultTtsSpeed,
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
      consoleLogEnabled: consoleLogEnabled ?? this.consoleLogEnabled,
      openLastBookOnLaunch: openLastBookOnLaunch ?? this.openLastBookOnLaunch,
      showHeader: showHeader ?? this.showHeader,
      showFooter: showFooter ?? this.showFooter,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      defaultTtsSpeed: defaultTtsSpeed ?? this.defaultTtsSpeed,
    );
  }
```

**3e. `==`／`hashCode`**：

```dart
  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay &&
      other.volumeKeyEnabled == volumeKeyEnabled &&
      other.fullscreen == fullscreen &&
      other.consoleLogEnabled == consoleLogEnabled &&
      other.openLastBookOnLaunch == openLastBookOnLaunch &&
      other.showHeader == showHeader &&
      other.showFooter == showFooter &&
      other.ttsVoiceId == ttsVoiceId &&
      other.defaultTtsSpeed == defaultTtsSpeed;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
        volumeKeyEnabled,
        fullscreen,
        consoleLogEnabled,
        openLastBookOnLaunch,
        showHeader,
        showFooter,
        ttsVoiceId,
        defaultTtsSpeed,
      );
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/global_reader_prefs_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/global_reader_prefs.dart app/test/reader/global_reader_prefs_test.dart
git commit -m "feat(epic-36): GlobalReaderPrefs 新增 showHeader/showFooter/ttsVoiceId/defaultTtsSpeed"
```

---

## Task 2：`ReaderPrefsManagerImpl` 持久化＋`resolve()` 雙層解析

**Files:**
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `GlobalReaderPrefs.showHeader`/`showFooter`/`ttsVoiceId`/`defaultTtsSpeed`。
- Produces：`ReaderPrefsManagerImpl.loadGlobalPrefs()`/`saveGlobalPrefs()` 對稱讀寫 4 個新 SharedPreferences 鍵；`resolve()` 的 `showHeader`/`showFooter` 改為 `book.showHeader ?? global.showHeader`/`book.showFooter ?? global.showFooter`（取代硬編碼 `?? false`）。

- [ ] **Step 1: 寫失敗測試**

**1a.** 在 `app/test/reader/reader_prefs_manager_test.dart` 的 `group('resolve()...')` 內、既有 `test('book.fullscreen 存在時優先於 global.fullscreen', ...)` 之後新增：

```dart
    test('global.showHeader／showFooter 為 true 時，book 未覆寫則 resolve() 回傳 true（非硬編碼 false，證明雙層解析生效）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial()
            .copyWith(showHeader: true, showFooter: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.showHeader, isTrue);
      expect(resolved.showFooter, isTrue);
    });

    test('book.showHeader／showFooter 存在時優先於 global 對應欄位', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(showHeader: false, showFooter: false),
        globalPrefs: const GlobalReaderPrefs.initial()
            .copyWith(showHeader: true, showFooter: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.showHeader, isFalse);
      expect(resolved.showFooter, isFalse);
    });
```

**1b.** 在 `group('load()...')` 內、既有 `test('saveGlobalPrefs 寫入 consoleLogEnabled ...')` 之後新增：

```dart
    test('saveGlobalPrefs 寫入 showHeader／showFooter／ttsVoiceId／defaultTtsSpeed 至既有慣例命名的 SharedPreferences key',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        showHeader: true,
        showFooter: true,
        ttsVoiceId: 'voice-42',
        defaultTtsSpeed: 1.5,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('global_reader_show_header'), isTrue);
      expect(sp.getBool('global_reader_show_footer'), isTrue);
      expect(sp.getString('global_reader_tts_voice_id'), 'voice-42');
      expect(sp.getDouble('global_reader_default_tts_speed'), 1.5);

      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.showHeader, isTrue);
      expect(loaded.globalPrefs.showFooter, isTrue);
      expect(loaded.globalPrefs.ttsVoiceId, 'voice-42');
      expect(loaded.globalPrefs.defaultTtsSpeed, 1.5);
    });

    test('showHeader／showFooter／defaultTtsSpeed 未儲存過（缺鍵）時，安全回退為預設值 false／false／1.0，ttsVoiceId 回退為 null',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.showHeader, isFalse);
      expect(loaded.globalPrefs.showFooter, isFalse);
      expect(loaded.globalPrefs.ttsVoiceId, isNull);
      expect(loaded.globalPrefs.defaultTtsSpeed, 1.0);
    });

    test('ttsVoiceId 先儲存再清空後（saveGlobalPrefs 傳入 null），load 讀回 null', () async {
      const withVoice = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        ttsVoiceId: 'voice-1',
      );
      await manager.saveGlobalPrefs(withVoice);
      expect((await manager.loadGlobalPrefs()).ttsVoiceId, 'voice-1');

      const withoutVoice = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
      );
      await manager.saveGlobalPrefs(withoutVoice);
      expect((await manager.loadGlobalPrefs()).ttsVoiceId, isNull);
    });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: FAIL（`GlobalReaderPrefs` 建構呼叫可通過編譯——Task 1 已完成，但 `resolve()` 仍是硬編碼 `?? false`、`saveGlobalPrefs`/`loadGlobalPrefs` 尚未讀寫新鍵，斷言失敗）

- [ ] **Step 3: 實作**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`：

**3a. 新增 SharedPreferences 鍵常數**（緊接在既有 `_consoleLogEnabledKey` 之後）：

```dart
  static const _showHeaderKey = 'global_reader_show_header';
  static const _showFooterKey = 'global_reader_show_footer';
  static const _ttsVoiceIdKey = 'global_reader_tts_voice_id';
  static const _defaultTtsSpeedKey = 'global_reader_default_tts_speed';
```

**3b. `loadGlobalPrefs()`**：在既有 `consoleLogEnabled: sp.getBool(_consoleLogEnabledKey) ?? false,` 之後新增：

```dart
      showHeader: sp.getBool(_showHeaderKey) ?? false,
      showFooter: sp.getBool(_showFooterKey) ?? false,
      ttsVoiceId: sp.getString(_ttsVoiceIdKey),
      defaultTtsSpeed: sp.getDouble(_defaultTtsSpeedKey) ?? 1.0,
```

**3c. `saveGlobalPrefs()`**：在既有 `await sp.setBool(_consoleLogEnabledKey, prefs.consoleLogEnabled);` 之後新增：

```dart
    await sp.setBool(_showHeaderKey, prefs.showHeader);
    await sp.setBool(_showFooterKey, prefs.showFooter);
    // ttsVoiceId 為 nullable——setString 不接受 null，缺席時須明確 remove()
    // 該鍵，否則舊值會殘留，導致「清空語音選擇」的意圖被忽略。
    if (prefs.ttsVoiceId != null) {
      await sp.setString(_ttsVoiceIdKey, prefs.ttsVoiceId!);
    } else {
      await sp.remove(_ttsVoiceIdKey);
    }
    await sp.setDouble(_defaultTtsSpeedKey, prefs.defaultTtsSpeed);
```

**3d. `resolve()`**：把既有硬編碼

```dart
      showHeader: book.showHeader ?? false,
      showFooter: book.showFooter ?? false,
```

改為：

```dart
      showHeader: book.showHeader ?? global.showHeader,
      showFooter: book.showFooter ?? global.showFooter,
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-36): ReaderPrefsManagerImpl 持久化新欄位，resolve() 頁首/頁尾改雙層解析"
```

---

## Task 3：`EBSectionHeader`（設定分區標題基礎元件）

**Files:**
- Create: `app/lib/screens/widgets/eb_section_header.dart`
- Test: `app/test/screens/widgets/eb_section_header_test.dart`

**Interfaces:**
- Produces：`class EBSectionHeader extends StatelessWidget`，建構參數 `title`（`String`，required）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/widgets/eb_section_header_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/eb_section_header.dart';

void main() {
  testWidgets('顯示傳入的標題文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EBSectionHeader(title: '外觀')),
      ),
    );

    expect(find.text('外觀'), findsOneWidget);
  });

  testWidgets('文字樣式為粗體（DESIGN.md §17 分區標題規格）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EBSectionHeader(title: '閱讀')),
      ),
    );

    final text = tester.widget<Text>(find.text('閱讀'));
    expect(text.style?.fontWeight, FontWeight.bold);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_section_header_test.dart`
Expected: FAIL（`eb_section_header.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/widgets/eb_section_header.dart`：

```dart
import 'package:flutter/material.dart';

/// 設定畫面分區標題基礎元件（`DESIGN.md` §17，
/// epic-36-adaptive-shelf-navigation Issue 5 首次落地）。最小可用版本，
/// 不含互動；比照 `ReadingDefaultsScreen._buildSectionHeader()` 既有樣式
/// 定調，抽成共用元件供 `SettingsScaffold` 使用。
class EBSectionHeader extends StatelessWidget {
  final String title;

  const EBSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_section_header_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/widgets/eb_section_header.dart app/test/screens/widgets/eb_section_header_test.dart
git commit -m "feat(epic-36): 新增設定分區標題基礎元件 EBSectionHeader"
```

---

## Task 4：`SettingsScreen` → `SettingsScaffold` 更名＋四分區重排

**Files:**
- Create: `app/lib/screens/settings_scaffold.dart`
- Delete: `app/lib/screens/settings_screen.dart`
- Create: `app/test/screens/settings_scaffold_test.dart`
- Delete: `app/test/screens/settings_screen_test.dart`
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Modify: `app/test/screens/adaptive_shell_scaffold_test.dart`
- Modify: `app/test/theme/theme_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `EBSectionHeader`。
- Produces：`class SettingsScaffold extends StatefulWidget`（原 `SettingsScreen`，建構參數與既有 Key 契約完全不變）。

**行為不變（純重排，不是重寫）**：本 Task 只做類別更名／檔案更名／`ListTile` 分組重排，五個依賴 nullable 判斷可否點擊的既有邏輯（字型管理／同步／雲端帳戶）、Console Log 開關讀寫邏輯、主題圓點三態渲染邏輯，皆逐行原樣搬移，不改動任何條件判斷或既有 Key 字串。

- [ ] **Step 1: 建立新測試檔（原檔案更名＋新增分區斷言）**

建立 `app/test/screens/settings_scaffold_test.dart`：將 `app/test/screens/settings_screen_test.dart`（見上方已讀取的完整內容）逐一複製，做以下純文字替換：
- import 第 11 行 `package:elinkbook/screens/settings_screen.dart` → `package:elinkbook/screens/settings_scaffold.dart`
- 全檔案 `SettingsScreen(` → `SettingsScaffold(`（建構呼叫，共 15 處）
- 全檔案測試描述字串中的 `SettingsScreen` 字樣（`testWidgets('SettingsScreen ...`，純文字說明，共 11 處）維持原樣不強制改（測試描述文字不影響編譯與斷言，是否同步更名為 `SettingsScaffold` 由實作者自行決定，不是本 Task 的驗收項）

**【review-plan-issue-5.md C-2】四個 `EBSectionHeader`＋重排後，「同步與帳號」與「關於」分區內的既有測試須放大測試視窗**：四分區重排把 `ListTile` 插入 4 段 `EBSectionHeader`（累積約 200dp）並把「關於」整段推到清單最尾端，原本在預設 800×600 視窗下勉強可見／可點擊的下半段項目會被推出可視範圍，`tester.tap()` 對不在螢幕範圍內的座標會失敗。除了原檔案第 102 行「點擊「關於」...」測試本來就已為此加大視窗（維持原樣不動，見 Step 1 純文字替換規則），複製後的測試檔另外還有 4 則測試在重排後會位於視窗外，須各自比照同一手法補上（在各測試 `pumpWidget` 之前插入，`addTearDown` 內還原）：

```dart
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
```

需要補上這段的 4 則既有測試（依原檔案 `settings_screen_test.dart` 內的測試描述定位）：
- `'SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen'`
- `'SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen'`
- `'點擊「閱讀器 Console Log」導航至 ReaderConsoleLogScreen（epic-18-reader-device-qa Issue 33）'`（審查報告 C-2 原始舉例）
- `'切換 Console Log 開關後，onChanged 觸發 saveGlobalPrefs 持久化新值'`（審查報告 C-2 原始舉例）

前兩則（同步／雲端帳戶）並非審查報告原始指出的項目，是規劃階段依四分區實際疊加高度重新估算後判斷落在視窗邊緣（同步與帳號分區起點約在 468~580dp，逼近 600dp 視窗下緣），保守一併加上視窗放大，避免因元件實際渲染高度與估算值有出入而在裝置/字型差異下才浮現的不穩定測試。

在檔案結尾（`main()` 內最後一個 `testWidgets` 之後）新增：

```dart
  testWidgets('四個區塊標題依序為外觀／閱讀／同步與帳號／關於', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pumpAndSettle();

    final headerTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((text) => ['外觀', '閱讀', '同步與帳號', '關於'].contains(text))
        .toList();

    expect(headerTexts, ['外觀', '閱讀', '同步與帳號', '關於']);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: FAIL（`settings_scaffold.dart` 不存在）

- [ ] **Step 3: 建立新實作檔並刪除舊檔**

建立 `app/lib/screens/settings_scaffold.dart`：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_data.dart';
import 'about_screen.dart';
import 'cloud_account_settings_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';
import 'widgets/eb_section_header.dart';

/// 設定畫面：四分區（外觀／閱讀／同步與帳號／關於，`DESIGN.md` §17，
/// epic-36-adaptive-shelf-navigation spec.md §功能⑤）。「佈景」（主題圓點，
/// 原位於 `LibraryScreen` AppBar，見 `epic-18-reader-device-qa` 工具列溢位
/// 修復）、「字型管理」、「閱讀預設值」、「導航熱區」、「同步」、「閱讀器
/// Console Log」（Issue 33 診斷用）、Console Log 攔截開關
/// （`epic-28-reader-settings-enhancements` Issue 2）與「關於」項目皆為既有
/// 功能原樣搬移，本次（由 `SettingsScreen` 更名而來）只是重新分組，行為與
/// 既有 Key 契約不變。
class SettingsScaffold extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;

  const SettingsScaffold({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
  });

  @override
  State<SettingsScaffold> createState() => _SettingsScaffoldState();
}

class _SettingsScaffoldState extends State<SettingsScaffold> {
  /// Console Log 攔截開關目前顯示值（epic-28-reader-settings-enhancements
  /// Issue 2）。刻意不採用「整頁 loading gate」模式——本畫面其餘 `ListTile`
  /// （佈景／字型管理等）與這個開關無關，初始值先顯示預設 `false`，
  /// `initState()` 的非同步載入完成後才 `setState` 更新為實際已儲存值，不
  /// 阻塞其餘項目的同步顯示。
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
          const EBSectionHeader(title: '外觀'),
          ListTile(
            title: const Text('佈景'),
            subtitle: widget.isEinkMode
                ? const Text(
                    '這裡選的是關閉 E-Ink 後要恢復的主題',
                    key: Key('settings_theme_locked_hint'),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    'settings_theme_dot_sepia'),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('settings_eink_mode_switch'),
            title: const Text('E-Ink 高對比模式'),
            subtitle: const Text('停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化'),
            value: widget.isEinkMode,
            onChanged: widget.onEinkModeChanged,
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
          const EBSectionHeader(title: '閱讀'),
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
          const EBSectionHeader(title: '同步與帳號'),
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
            key: const Key('settings_cloud_account_button'),
            title: const Text('已連結的雲端匯入帳戶'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.cloudAccountRepository == null ||
                    widget.googleDriveOAuthClient == null ||
                    widget.oneDriveOAuthClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CloudAccountSettingsScreen(
                          cloudAccountRepository: widget.cloudAccountRepository!,
                          googleDriveOAuthClient: widget.googleDriveOAuthClient!,
                          oneDriveOAuthClient: widget.oneDriveOAuthClient!,
                        ),
                      ),
                    );
                  },
          ),
          const EBSectionHeader(title: '關於'),
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
        ],
      ),
    );
  }

  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.isEinkMode;
    final isCurrentTheme = widget.currentTheme == theme;
    final isSelected = isCurrentTheme && !locked;
    return Semantics(
      label: locked
          ? '${_themeLabel(theme)}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，'
              '目前選擇：${_themeLabel(widget.currentTheme)}'
          : '${_themeLabel(theme)}佈景',
      button: !locked,
      child: GestureDetector(
        key: Key(key),
        onTap: locked ? null : () => widget.onThemeChanged?.call(theme),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: locked
                ? null
                : Border.all(
                    color: isSelected
                        ? previewTheme.colorScheme.primary
                        : previewTheme.colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
          ),
          child: locked
              ? CustomPaint(
                  painter: _LockedDotBorderPainter(
                    color: Theme.of(context).colorScheme.onSurface,
                    strokeWidth: isCurrentTheme ? 3 : 1.5,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '淺色',
        AppTheme.dark => '深色',
        AppTheme.sepia => '羊皮紙',
      };
}

/// E-Ink 鎖定狀態的圓形虛線邊框（`DESIGN.md` §17.2：邊框改為虛線，取代
/// 原本的降低透明度手法）。
class _LockedDotBorderPainter extends CustomPainter {
  const _LockedDotBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  static const double _dashLength = 3;
  static const double _gapLength = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LockedDotBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
```

刪除舊檔：

```bash
git rm app/lib/screens/settings_screen.dart app/test/screens/settings_screen_test.dart
```

- [ ] **Step 4: 更新 `adaptive_shell_scaffold.dart`**

編輯 `app/lib/screens/adaptive_shell_scaffold.dart`：

**4a.** import 第 9 行 `import 'settings_screen.dart';` 改為 `import 'settings_scaffold.dart';`

**4b.** 移除 class doc comment 中「過渡期型別標注」整段（第 32-34 行）：

```dart
/// **過渡期型別標注**：`SettingsScreen`→`SettingsScaffold` 更名排在 Issue
/// 5，本類別第三個子畫面暫時掛載既有 `SettingsScreen`（見
/// `reviews/review-issues.md` M-1）。
```

同段落下方註解中的 `SettingsScreen/SourcesHomeScreen` 字樣（第 87 行附近）改為 `SettingsScaffold/SourcesHomeScreen`。

**4c.** `build()` 內第三個 `IndexedStack` 子項的 `SettingsScreen(` 建構呼叫改為 `SettingsScaffold(`（其餘具名參數不變，本 Task 不新增參數，Task 5/7 才會再疊加）。

- [ ] **Step 5: 更新 `adaptive_shell_scaffold_test.dart`**

編輯 `app/test/screens/adaptive_shell_scaffold_test.dart`：

- import 第 10 行 `import 'package:elinkbook/screens/settings_screen.dart';` 改為 `import 'package:elinkbook/screens/settings_scaffold.dart';`
- 第 120 行、155 行測試描述字串中的 `SettingsScreen` 字樣可維持不改（純文字說明，不影響編譯，比照 Step 1 的判斷）
- 第 145、174、184 行的 `tester.widget<SettingsScreen>(find.byType(SettingsScreen))` 三處皆改為 `tester.widget<SettingsScaffold>(find.byType(SettingsScaffold))`

- [ ] **Step 6: 更新 `theme_test.dart`**

編輯 `app/test/theme/theme_test.dart`：

- import 第 8 行 `import 'package:elinkbook/screens/settings_screen.dart';` 改為 `import 'package:elinkbook/screens/settings_scaffold.dart';`
- 第 118、143 行 `home: SettingsScreen(` 改為 `home: SettingsScaffold(`
- 第 111、136 行測試描述字串中的 `SettingsScreen` 字樣可維持不改（純文字說明）

- [ ] **Step 7: 執行測試確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart test/theme/theme_test.dart`
Expected: PASS（全部案例，含 Step 1 新增的四分區標題順序測試）

- [ ] **Step 8: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`（確認沒有殘留對已刪除的 `settings_screen.dart`/`SettingsScreen` 的引用）

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/settings_scaffold.dart app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/settings_scaffold_test.dart app/test/screens/adaptive_shell_scaffold_test.dart app/test/theme/theme_test.dart
git commit -m "refactor(epic-36): SettingsScreen 更名為 SettingsScaffold 並重排為四分區"
```

---

## Task 5：`SettingsScaffold` AppBar 新增「書架」「來源」圖示

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Modify: `app/test/screens/settings_scaffold_test.dart`
- Modify: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces:**
- Produces：`SettingsScaffold` 新增建構參數 `final VoidCallback? onNavigateToLibrary;`／`final VoidCallback? onNavigateToSource;`；AppBar 新增 `settings_library_button`（`Icons.grid_view`）／`settings_source_button`（`Icons.cloud_download`）兩個 `IconButton`。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/settings_scaffold_test.dart` 結尾新增：

```dart
  testWidgets('AppBar 顯示「書架」「來源」圖示，點擊分別呼叫對應 callback', (tester) async {
    var libraryTapped = 0;
    var sourceTapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        onNavigateToLibrary: () => libraryTapped++,
        onNavigateToSource: () => sourceTapped++,
      ),
    ));

    expect(find.byKey(const Key('settings_library_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_source_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(libraryTapped, 1);
    expect(sourceTapped, 0);

    await tester.tap(find.byKey(const Key('settings_source_button')));
    await tester.pumpAndSettle();
    expect(sourceTapped, 1);
  });

  testWidgets('未接上 onNavigateToLibrary／onNavigateToSource 時，圖示仍存在但不崩潰', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    expect(find.byKey(const Key('settings_library_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_source_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: FAIL（`settings_library_button`/`settings_source_button` 不存在）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/settings_scaffold.dart`：

**3a.** `SettingsScaffold` 欄位新增（緊接在既有 `oneDriveOAuthClient` 欄位之後）：

```dart
  final VoidCallback? onNavigateToLibrary;
  final VoidCallback? onNavigateToSource;
```

建構子參數列同步新增 `this.onNavigateToLibrary,`／`this.onNavigateToSource,`。

**3b.** `build()` 的 `AppBar` 新增 `actions`：

```dart
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          IconButton(
            key: const Key('settings_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: '書架',
            onPressed: widget.onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('settings_source_button'),
            icon: const Icon(Icons.cloud_download),
            tooltip: '來源',
            onPressed: widget.onNavigateToSource,
          ),
        ],
      ),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `AdaptiveShellScaffold` 串接**

編輯 `app/lib/screens/adaptive_shell_scaffold.dart`，`SettingsScaffold(` 建構呼叫新增：

```dart
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSource: () => _navigateTo(1),
```

- [ ] **Step 6: 新增 `AdaptiveShellScaffold` 整合測試**

在 `app/test/screens/adaptive_shell_scaffold_test.dart` 結尾新增：

```dart
  testWidgets('在設定分頁點擊「書架」圖示切回書架分頁', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('在設定分頁點擊「來源」圖示切到來源分頁', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    await tester.tap(find.byKey(const Key('settings_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
  });
```

- [ ] **Step 7: 執行測試確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 8: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/settings_scaffold.dart app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/settings_scaffold_test.dart app/test/screens/adaptive_shell_scaffold_test.dart
git commit -m "feat(epic-36): SettingsScaffold AppBar 新增書架/來源導覽圖示"
```

---

## Task 6：`ReadingDefaultsScreen` 新增「顯示頁首／頁尾」全域預設開關

**Files:**
- Modify: `app/lib/screens/reading_defaults_screen.dart`
- Modify: `app/test/screens/reading_defaults_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `GlobalReaderPrefs.showHeader`/`showFooter`。
- Produces：新增 Key `reading_defaults_show_header_switch`／`reading_defaults_show_footer_switch`。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/reading_defaults_screen_test.dart` 結尾新增：

```dart
  testWidgets('顯示頁首/頁尾開關反映既有 GlobalReaderPrefs 初始值', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(showHeader: true, showFooter: false),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final headerSwitchFinder =
        find.byKey(const Key('reading_defaults_show_header_switch'));
    await tester.scrollUntilVisible(headerSwitchFinder, 100);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(headerSwitchFinder).value, isTrue);

    final footerSwitchFinder =
        find.byKey(const Key('reading_defaults_show_footer_switch'));
    await tester.scrollUntilVisible(footerSwitchFinder, 100);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(footerSwitchFinder).value, isFalse);
  });

  testWidgets('切換顯示頁首開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_show_header_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.showHeader, isTrue);
  });

  testWidgets('切換顯示頁尾開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_show_footer_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.showFooter, isTrue);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reading_defaults_screen_test.dart`
Expected: FAIL（`reading_defaults_show_header_switch`/`reading_defaults_show_footer_switch` 不存在）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/reading_defaults_screen.dart`，在 `ListView` 的 `children` 最後一項（`reading_defaults_open_last_book_switch` 的 `SwitchListTile`）之後新增：

```dart
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_show_header_switch'),
                  title: const Text('顯示頁首'),
                  value: _prefs.showHeader,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(showHeader: value)),
                ),
                // 【review-plan-issue-5.md M-2】比照本畫面其餘控制項之間的
                // 既有節奏，兩個開關之間也補上分隔線。
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_show_footer_switch'),
                  title: const Text('顯示頁尾'),
                  value: _prefs.showFooter,
                  onChanged: (value) =>
                      _update(_prefs.copyWith(showFooter: value)),
                ),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reading_defaults_screen_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reading_defaults_screen.dart app/test/screens/reading_defaults_screen_test.dart
git commit -m "feat(epic-36): ReadingDefaultsScreen 新增顯示頁首/頁尾全域預設開關"
```

---

## Task 7：`TtsDefaultsScreen`（朗讀語音與語速）＋ `settings_tts_defaults_button` 串接

**Files:**
- Create: `app/lib/screens/tts_defaults_screen.dart`
- Test: `app/test/screens/tts_defaults_screen_test.dart`
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Modify: `app/test/screens/settings_scaffold_test.dart`
- Modify: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `GlobalReaderPrefs.ttsVoiceId`/`defaultTtsSpeed`；Task 3 的 `EBSectionHeader`（review-plan-issue-5.md M-3：不再自訂私有 `_buildSectionHeader`，直接重用）；既有 `TtsProvider.getAvailableVoices()`（`app/lib/reader/tts_provider.dart`）；既有 `TtsVoice.systemDefault`。
- Produces：`class TtsDefaultsScreen extends StatefulWidget`，建構參數 `prefsManager`（required）／`ttsProvider`（`TtsProvider?`）／`isEinkMode`（`bool`，預設 `false`）。Key 契約：`tts_defaults_loading_indicator`／`tts_defaults_voice_unavailable_hint`／`tts_defaults_voice_${voice.id}`／`tts_defaults_speed_decrement`／`tts_defaults_speed_slider`／`tts_defaults_speed_value`（E-Ink 模式取代 slider）／`tts_defaults_speed_increment`。`SettingsScaffold` 新增建構參數 `ttsProvider`，「閱讀」分區新增 `settings_tts_defaults_button`。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/tts_defaults_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/screens/tts_defaults_screen.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_tts_provider.dart';

/// 【review-plan-issue-5.md I-2】模擬「裝置具備 TTS 引擎，但尚未安裝任何
/// 語言包/可用語音」的情境——`FakeTtsProvider` 固定回傳
/// `[TtsVoice.systemDefault]`，無法模擬空清單，改用這個最小 ad-hoc 實作，
/// 不修改共用的 `FakeTtsProvider`（避免影響其他既有測試檔案）。
class _EmptyVoicesTtsProvider implements TtsProvider {
  @override
  Future<List<TtsVoice>> getAvailableVoices() async => const [];

  @override
  Future<int?> getMaxInputLength() async => null;

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('ttsProvider 為 null 時顯示不可用提示，不崩潰，且無語音選項', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tts_defaults_voice_unavailable_hint')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ttsProvider 存在時列出 getAvailableVoices() 回傳的語音', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(
        prefsManager: FakeReaderPrefsManager(),
        ttsProvider: FakeTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
      findsOneWidget,
    );
    expect(find.text(TtsVoice.systemDefault.displayName), findsOneWidget);
  });

  testWidgets(
      'ttsProvider 存在但 getAvailableVoices() 回傳空清單時，顯示不可用提示而非空白區塊'
      '（review-plan-issue-5.md I-2）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(
        prefsManager: FakeReaderPrefsManager(),
        ttsProvider: _EmptyVoicesTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tts_defaults_voice_unavailable_hint')),
      findsOneWidget,
    );
  });

  testWidgets('點選語音選項立即呼叫 saveGlobalPrefs 更新 ttsVoiceId', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(
        prefsManager: fakeManager,
        ttsProvider: FakeTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.ttsVoiceId,
      TtsVoice.systemDefault.id,
    );
  });

  testWidgets(
      '非 E-Ink 模式顯示語速 Slider（無 divisions，改在 onChanged 內吸附至 0.1 步進），'
      '拖曳後呼叫 saveGlobalPrefs 更新 defaultTtsSpeed 且結果精確對齊 0.1 格'
      '（review-plan-issue-5.md I-1/I-3：divisions: 13 會漏掉 1.0x 基準格，'
      '改為連續 Slider＋onChanged 內四捨五入至 0.1，兩種互動路徑〔Slider／'
      'E-Ink +/- 按鈕〕產生的可達值集合一致）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: false),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tts_defaults_speed_slider')), findsOneWidget);
    expect(find.byKey(const Key('tts_defaults_speed_value')), findsNothing);
    final slider =
        tester.widget<Slider>(find.byKey(const Key('tts_defaults_speed_slider')));
    expect(slider.divisions, isNull, reason: '改為連續 Slider，不使用 divisions 離散刻度');

    await tester.drag(
      find.byKey(const Key('tts_defaults_speed_slider')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    final result = fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed;
    expect(result, greaterThan(1.0));
    expect(result, lessThanOrEqualTo(2.0));
    // 結果須精確落在 0.1 的整數倍格點上（容許浮點誤差），驗證 onChanged
    // 內的吸附邏輯確實生效，而非任意連續值。
    final steps = (result - 0.75) * 10;
    expect(steps.roundToDouble(), closeTo(steps, 1e-6));
  });

  testWidgets('E-Ink 模式隱藏 Slider，改用 +/- 按鈕以 0.1x 步進調整語速', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tts_defaults_speed_slider')), findsNothing);
    expect(find.byKey(const Key('tts_defaults_speed_value')), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_increment')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed, 1.1);
    expect(find.text('1.1x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_decrement')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed, 1.0);
  });

  testWidgets('語速已達上限 2.0x 時，+按鈕停用；已達下限 0.75x 時，-按鈕停用', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(defaultTtsSpeed: 2.0),
    );
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    final incrementButton = tester.widget<IconButton>(
      find.byKey(const Key('tts_defaults_speed_increment')),
    );
    expect(incrementButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_decrement')));
    await tester.pumpAndSettle();
    // 2.0 -> 1.9，仍未到下限，- 按鈕應仍可用
    final decrementButton = tester.widget<IconButton>(
      find.byKey(const Key('tts_defaults_speed_decrement')),
    );
    expect(decrementButton.onPressed, isNotNull);
  });

  testWidgets(
      '從預設 1.0x 連續點擊減號至 0.75x（不會卡在 0.8x），到達 0.75x 後減號按鈕停用'
      '（review-plan-issue-5.md C-1 核心回歸測試：停用判斷須看「目前值」而非'
      '「預判扣除後的值」，否則 1.0→0.9→0.8 時，0.8-0.1=0.7<0.75 會讓按鈕在'
      '0.8x 就被錯誤停用，永遠到不了規格下限 0.75x）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    final decrementFinder = find.byKey(const Key('tts_defaults_speed_decrement'));

    // 1.0 -> 0.9 -> 0.8：每次點擊前按鈕都必須是可用的。
    for (final expected in [0.9, 0.8]) {
      expect(tester.widget<IconButton>(decrementFinder).onPressed, isNotNull);
      await tester.tap(decrementFinder);
      await tester.pumpAndSettle();
      expect(fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed,
          closeTo(expected, 1e-9));
    }

    // 關鍵一步：目前為 0.8x，按鈕必須仍可用，點擊後正確 clamp 至 0.75x。
    expect(tester.widget<IconButton>(decrementFinder).onPressed, isNotNull);
    await tester.tap(decrementFinder);
    await tester.pumpAndSettle();
    expect(fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed,
        closeTo(0.75, 1e-9));
    expect(find.text('0.8x'), findsNothing);

    // 已達 0.75x 下限，減號按鈕停用。
    expect(tester.widget<IconButton>(decrementFinder).onPressed, isNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/tts_defaults_screen_test.dart`
Expected: FAIL（`tts_defaults_screen.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/tts_defaults_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/tts_provider.dart';
import 'widgets/eb_section_header.dart';

/// 朗讀（TTS）預設值畫面（epic-36-adaptive-shelf-navigation spec.md
/// §功能⑤）：語音選擇＋預設語速，皆讀寫 [GlobalReaderPrefs]，比照既有
/// `ReadingDefaultsScreen`/`NavZoneSettingsScreen`「全域偏好、即時生效、
/// 無儲存按鈕」慣例。**播放端何時讀取套用為預設值不在本畫面範圍**——本畫面
/// 只負責把使用者選擇寫進 `GlobalReaderPrefs`，播放端串接留待下一個涉及
/// TTS 播放邏輯的 Epic（spec.md「Out of Scope」）。
class TtsDefaultsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final TtsProvider? ttsProvider;
  final bool isEinkMode;

  const TtsDefaultsScreen({
    super.key,
    required this.prefsManager,
    this.ttsProvider,
    this.isEinkMode = false,
  });

  @override
  State<TtsDefaultsScreen> createState() => _TtsDefaultsScreenState();
}

class _TtsDefaultsScreenState extends State<TtsDefaultsScreen> {
  static const _minSpeed = 0.75;
  static const _maxSpeed = 2.0;
  static const _speedStep = 0.1;

  bool _loading = true;
  late GlobalReaderPrefs _prefs;
  List<TtsVoice> _voices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    final voices = await widget.ttsProvider?.getAvailableVoices() ?? const [];
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _voices = voices;
      _loading = false;
    });
  }

  void _update(GlobalReaderPrefs updated) {
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('朗讀語音與語速')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('tts_defaults_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                const EBSectionHeader(title: '語音'),
                // 【review-plan-issue-5.md I-2】ttsProvider 缺席「或」裝置
                // 雖有 TTS 引擎但回傳空清單（尚未安裝語言包）時，皆顯示同一
                // 個不可用提示，不留空白區塊。
                if (widget.ttsProvider == null || _voices.isEmpty)
                  const Padding(
                    key: Key('tts_defaults_voice_unavailable_hint'),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('目前裝置未安裝或不支援語音選擇'),
                  )
                else
                  RadioGroup<String>(
                    groupValue: _prefs.ttsVoiceId ?? TtsVoice.systemDefault.id,
                    onChanged: (voiceId) {
                      if (voiceId == null) return;
                      _update(_prefs.copyWith(ttsVoiceId: voiceId));
                    },
                    child: Column(
                      children: [
                        for (final voice in _voices)
                          RadioListTile<String>(
                            key: Key('tts_defaults_voice_${voice.id}'),
                            title: Text(voice.displayName),
                            value: voice.id,
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                const EBSectionHeader(title: '語速'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('tts_defaults_speed_decrement'),
                        icon: const Icon(Icons.remove),
                        // 【review-plan-issue-5.md C-1】停用判斷須看「目前值
                        // 是否已到達下限」，不能看「預判扣除一步後是否會低於
                        // 下限」——0.75 與預設起點 1.0 之間不是 0.1 的整數倍
                        // （1.0 - 0.75 = 0.25），若用後者，0.8x 時
                        // 0.8 - 0.1 = 0.7 < 0.75 已成立，按鈕會在到達 0.75x
                        // 之前就被錯誤停用，使用者永遠调不到規格下限。
                        onPressed: _prefs.defaultTtsSpeed <= _minSpeed + 1e-9
                            ? null
                            : () => _update(_prefs.copyWith(
                                defaultTtsSpeed:
                                    (_prefs.defaultTtsSpeed - _speedStep)
                                        .clamp(_minSpeed, _maxSpeed))),
                      ),
                      Expanded(
                        child: widget.isEinkMode
                            ? Text(
                                '${_prefs.defaultTtsSpeed.toStringAsFixed(1)}x',
                                key: const Key('tts_defaults_speed_value'),
                                textAlign: TextAlign.center,
                              )
                            : Slider(
                                key: const Key('tts_defaults_speed_slider'),
                                value: _prefs.defaultTtsSpeed,
                                min: _minSpeed,
                                max: _maxSpeed,
                                // 【review-plan-issue-5.md I-1】不設
                                // divisions——(_maxSpeed - _minSpeed) /
                                // _speedStep = 1.25 / 0.1 = 12.5，四捨五入成
                                // 13 個刻度後，每格間距變成約 0.0962x，不只
                                // 不是 0.1 的整數倍，連基準語速 1.0x 都不落在
                                // 任何一個刻度上。改為連續 Slider，實際的
                                // 0.1x 步進吸附放在 onChanged 內以四捨五入
                                // 達成，確保 Slider 拖曳與下方 E-Ink +/-
                                // 按鈕產生的是同一組可達值。
                                label:
                                    '${_prefs.defaultTtsSpeed.toStringAsFixed(2)}x',
                                onChanged: (v) {
                                  final snapped =
                                      (v * 10).round() / 10;
                                  _update(_prefs.copyWith(
                                      defaultTtsSpeed: snapped.clamp(
                                          _minSpeed, _maxSpeed)));
                                },
                              ),
                      ),
                      IconButton(
                        key: const Key('tts_defaults_speed_increment'),
                        icon: const Icon(Icons.add),
                        // 【review-plan-issue-5.md C-1】同上改看「目前值」
                        // 而非「預判下一步」——上限側目前用預設起點 1.0
                        // 推算剛好落在整數格上不會复現同一個 bug，但停用
                        // 判斷式仍須與下限側維持同一套邏輯（看目前值），
                        // 否則 Slider 端四捨五入吸附（見下方 I-1 修正）
                        // 得出的浮點值一旦有極小誤差飄出格線，預判式會比
                        // 目前值式更早停用，行為不一致、也更脆弱。
                        onPressed: _prefs.defaultTtsSpeed >= _maxSpeed - 1e-9
                            ? null
                            : () => _update(_prefs.copyWith(
                                defaultTtsSpeed:
                                    (_prefs.defaultTtsSpeed + _speedStep)
                                        .clamp(_minSpeed, _maxSpeed))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/tts_defaults_screen_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `SettingsScaffold` 串接**

編輯 `app/lib/screens/settings_scaffold.dart`：

**5a.** import 新增：

```dart
import '../reader/tts_provider.dart';
import 'tts_defaults_screen.dart';
```

**5b.** `SettingsScaffold` 欄位新增（緊接在 `onNavigateToSource` 之後）：

```dart
  final TtsProvider? ttsProvider;
```

建構子參數列同步新增 `this.ttsProvider,`。

**5c.** 「閱讀」分區（`settings_nav_zone_button` 的 `ListTile` 之後）新增：

```dart
          ListTile(
            key: const Key('settings_tts_defaults_button'),
            title: const Text('朗讀語音與語速'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TtsDefaultsScreen(
                    prefsManager: widget.prefsManager,
                    ttsProvider: widget.ttsProvider,
                    isEinkMode: widget.isEinkMode,
                  ),
                ),
              );
            },
          ),
```

- [ ] **Step 6: `AdaptiveShellScaffold` 串接**

編輯 `app/lib/screens/adaptive_shell_scaffold.dart`，`SettingsScaffold(` 建構呼叫新增：

```dart
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
```

- [ ] **Step 7: 新增測試**

在 `app/test/screens/settings_scaffold_test.dart` 結尾新增：

```dart
  testWidgets('點擊「朗讀語音與語速」導航至 TtsDefaultsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    final buttonFinder = find.byKey(const Key('settings_tts_defaults_button'));
    await tester.scrollUntilVisible(buttonFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(find.text('朗讀語音與語速'), findsOneWidget);
  });
```

在 `app/test/screens/adaptive_shell_scaffold_test.dart` 結尾新增：

```dart
  testWidgets('SettingsScaffold 收到 readerFeatureRepositories.ttsProvider 轉送', (tester) async {
    final ttsProvider = FakeTtsProvider();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories:
              LibraryReaderFeatureRepositories(ttsProvider: ttsProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScaffold =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(settingsScaffold.ttsProvider, ttsProvider);
  });
```

並在檔案 import 區塊新增：

```dart
import '../support/fake_tts_provider.dart';
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart test/screens/tts_defaults_screen_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 9: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add app/lib/screens/tts_defaults_screen.dart app/lib/screens/settings_scaffold.dart app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/tts_defaults_screen_test.dart app/test/screens/settings_scaffold_test.dart app/test/screens/adaptive_shell_scaffold_test.dart
git commit -m "feat(epic-36): 新增 TtsDefaultsScreen 朗讀語音與語速設定，串接進設定畫面「閱讀」分區"
```

---

## Task 8：全套驗證與收尾

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1: 執行全套 `flutter test`（不帶檔案路徑）**

Run: `flutter test`
Expected: 全數通過（比照 `CLAUDE.md`「測試執行範圍」，這是整份計劃收尾的唯一一次全套執行）。若有失敗，比對是否為本計劃改動觸及的檔案；非本計劃觸及範圍的既有不穩定測試（例如已追蹤的 `epic-37-test-suite-flakiness`）記錄下來，不在本 Issue 修復範圍內。

- [ ] **Step 2: 執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 逐條核對 `issues.md` Issue 5 驗收標準**

- [ ] 設定畫面分四區塊，既有功能與 Key 契約不變
- [ ] 「顯示頁首/頁尾」全域預設可調整且單書覆寫優先
- [ ] 「朗讀語音與語速」設定畫面可寫入 `GlobalReaderPrefs`（播放端串接留待後續 Epic）
- [ ] 既有使用者升級後新欄位有安全預設值不崩潰
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過

- [ ] **Step 4: 更新 `docs/epics.md` 備註欄位**

將 Epic 36 該列備註改為「Issue 1-5 已完成並合併，Epic 36 全數完成」（執行時以 `issues.md` 實際狀態為準調整措辭；若尚有其他未完成 Issue 則相應調整）。

- [ ] **Step 5: 依 `superpowers:requesting-code-review` 發起本 Issue 的程式碼審查**

審查者先產出報告至 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-5.md`，不得直接修改程式碼（比照專案 SDD 工作流程第 6 步）。審查請求內容須包含「計劃範圍澄清」第 1 點的 `adaptive_shell_scaffold_test.dart` 更名影響盤點（spec.md 遺漏、本計劃已補上），供審查者重點覆核 Task 4 是否確實同步更新了這個檔案。

---

## Self-Review 紀錄（撰寫本計劃時的覆核結果）

- **Spec 覆蓋**：`spec.md` §功能⑤逐條對照——`SettingsScreen`→`SettingsScaffold` 更名＋四分區重排（Task 4）、`EBSectionHeader`（Task 3）、AppBar 新增書架/來源圖示（Task 5）、`GlobalReaderPrefs` 4 個新欄位與 `ReaderPrefsManagerImpl` 持久化＋`resolve()` 雙層解析（Task 1-2）、`ReadingDefaultsScreen` 兩個新開關（Task 6）、`TtsDefaultsScreen` 新畫面＋按鈕串接（Task 7）皆有對應 Task，無遺漏。
- **`issues.md`「單元測試要求」逐條對照**：`settings_screen_test.dart` 重新命名且既有斷言全數維持通過＋新增 `EBSectionHeader` 四區塊順序斷言（Task 4）；`theme_test.dart` 同步更新（Task 4 Step 6，呼應 `issues.md` I-3）；`GlobalReaderPrefs` 新欄位 `copyWith`/`==`/`hashCode`/SharedPreferences round-trip／缺席預設值（Task 1-2）；`resolve()` 雙層解析單元測試（Task 2）皆已納入。
- **型別一致性**：`SettingsScaffold` 的 `onNavigateToLibrary`/`onNavigateToSource`/`ttsProvider` 三個新欄位在 Task 5/7 分別定義並在同一 Task 內於 `adaptive_shell_scaffold.dart` 完成串接，未跨 Task 留下編譯失敗的中繼狀態；`TtsDefaultsScreen` 的建構參數（`prefsManager`/`ttsProvider`/`isEinkMode`）在 Task 7 定義並在同一 Task 內完成呼叫端串接。
- **範圍落差已於「計劃範圍澄清」段落明文記錄並解決**：`spec.md`「已知測試影響」清單遺漏 `adaptive_shell_scaffold_test.dart`（第 1 點，本計劃 Task 4 已補上）、`ttsProvider` 逐欄位轉送而非整包 bundle 的既有慣例確認（第 2 點）、兩個新畫面控制項排列順序的合理決定（第 3 點）。
- **依 `reviews/review-plan-issue-5.md` 複審修訂**：2 項 Critical（Task 7 語速 Stepper 邊界判斷改看「目前值」而非「預判下一步」，並補上從 1.0 連續降至 0.75 的回歸測試；Task 4 四分區加高後為「同步」「雲端帳戶」「Console Log 按鈕/開關」4 則既有測試補上測試視窗放大）、3 項 Important（Slider 移除 `divisions: 13` 改在 `onChanged` 內吸附 0.1 步進，並補上精確刻度斷言；語音清單為空時比照 `ttsProvider == null` 顯示同一個不可用提示，並補上對應測試）、3 項 Minor（`.initial()` 初始化列表改用前後對照程式碼區塊；`ReadingDefaultsScreen` 新舊開關之間補 `Divider`；`TtsDefaultsScreen` 改重用 Task 3 的 `EBSectionHeader`，移除自訂私有方法）皆已修訂完成，逐項查證過與現有程式碼／數學計算相符後才落實。
