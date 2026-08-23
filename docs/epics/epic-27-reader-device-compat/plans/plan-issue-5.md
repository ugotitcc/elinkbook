# Epic 27 Issue 5：E-Ink 高對比模式狀態感知與切換識別強化 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 強化 E-Ink 模式的視覺感知與狀態辨識度，在書架 AppBar 上使用具備反白實心底色的切換按鈕，並於設定頁面新增獨立的「E-Ink 高對比模式」開關項目。

**Architecture:**
- 在 `LibraryScreen` 的 AppBar 中將純圖示 `IconButton` 升級為具備容器底色與外框的狀態按鈕（E-Ink 生效時使用純黑背景＋純白圖示，關閉時為透明背景＋邊框），提供即時、明確的「目前已開啟」狀態回饋。
- 在 `SettingsScreen` 中新增「E-Ink 高對比模式」`SwitchListTile`（`key: Key('settings_eink_mode_switch')`），接收 `onEinkModeChanged` 回呼，讓使用者可於設定頁面直接檢視與切換 E-Ink 模式。

**Tech Stack:** Flutter 3, Material 3, Dart

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 5」

## Global Constraints

- **Language**: 程式碼註解與說明一律使用正體中文 (Traditional Chinese, zh-TW)。
- **Flutter Analyze**: 靜態分析必須保持 0 warning / 0 error。
- **Keys**: 保留既有測試 Keys（如 `library_eink_toggle`、`settings_theme_dot_*`），新增 `settings_eink_mode_switch`。
- **測試 fixture**（【審查修正】見 `reviews/review-plan-issue-5-8.md` Recommendations #2）：新增至 `app/test/screens/library_screen_test.dart` 的測試須遵循該檔案既有的 fixture 建構模式（`FakeLibraryRepository()`／`FakeBookImportService()`／檔案共用 `prefsManager`）——Issue 8 的計畫也會修改同一份測試檔案，兩者須一致，避免各自漏帶 `LibraryScreen` 必要建構參數。

---

### Task 1: 設定畫面（SettingsScreen）新增 E-Ink 高對比模式開關

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`（貫穿傳遞 `onEinkModeChanged`）
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsScreen` 新增 `final ValueChanged<bool>? onEinkModeChanged;` 參數。
- Produces: `SwitchListTile(key: Key('settings_eink_mode_switch'), value: widget.isEinkMode, onChanged: widget.onEinkModeChanged)`

- [x] **Step 1: Write the failing test**

在 `app/test/screens/settings_screen_test.dart` 中新增測試：

```dart
testWidgets('SettingsScreen 顯示 E-Ink 模式開關，點擊切換觸發 onEinkModeChanged', (tester) async {
  bool? receivedEink;
  await tester.pumpWidget(MaterialApp(
    home: SettingsScreen(
      prefsManager: FakeReaderPrefsManager(),
      currentTheme: AppTheme.light,
      isEinkMode: false,
      onEinkModeChanged: (val) => receivedEink = val,
    ),
  ));

  expect(find.byKey(const Key('settings_eink_mode_switch')), findsOneWidget);
  expect(find.text('E-Ink 高對比模式'), findsOneWidget);

  await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
  await tester.pumpAndSettle();

  expect(receivedEink, isTrue);
});
```

- [x] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/settings_screen_test.dart`
預期：FAIL，因 `settings_eink_mode_switch` 尚未建立。

- [x] **Step 3: Write minimal implementation**

在 `app/lib/screens/settings_screen.dart`：
1. `SettingsScreen` 建構子新增 `this.onEinkModeChanged`。
2. 於 `ListView` 中「佈景」`ListTile` 下方新增 `SwitchListTile`：
```dart
SwitchListTile(
  key: const Key('settings_eink_mode_switch'),
  title: const Text('E-Ink 高對比模式'),
  subtitle: const Text('停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化'),
  value: widget.isEinkMode,
  onChanged: widget.onEinkModeChanged,
),
```
3. 在 `app/lib/screens/library_screen.dart:860` 導航至 `SettingsScreen` 處傳入 `onEinkModeChanged: widget.themeDependencies.onEinkModeChanged`。

- [x] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/screens/settings_screen_test.dart`
預期：PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/settings_screen.dart app/lib/screens/library_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "feat(epic-27): Issue 5——SettingsScreen 新增 E-Ink 高對比模式切換開關"
```

---

### Task 2: 書架主畫面（LibraryScreen）AppBar E-Ink 切換按鈕狀態視覺強化

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: `widget.themeDependencies.isEinkMode`
- Produces: 帶有實心反白容器的 `IconButton(key: Key('library_eink_toggle'))`

- [x] **Step 1: Write the failing test**

在 `app/test/screens/library_screen_test.dart` 中新增測試（【審查修正 Critical】`LibraryScreen` 建構子的 `repository`／`importService`／`prefsManager` 三個參數皆為 `required`、無預設值，原片段完全沒有提供會直接編譯失敗；改用檔案既有 `setUp()` 已建立的 `FakeLibraryRepository()`／`FakeBookImportService()`／共用 `prefsManager` fixture 模式，比照同檔案第 100-105 行既有寫法）：

```dart
testWidgets('LibraryScreen 在 E-Ink 模式開啟與關閉時，切換按鈕具備明確狀態容器與 tooltip', (tester) async {
  bool? toggledValue;
  await tester.pumpWidget(MaterialApp(
    home: LibraryScreen(
      repository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      prefsManager: prefsManager,
      themeDependencies: LibraryThemeDependencies(
        isEinkMode: true,
        onEinkModeChanged: (val) => toggledValue = val,
      ),
    ),
  ));

  final toggleFinder = find.byKey(const Key('library_eink_toggle'));
  expect(toggleFinder, findsOneWidget);

  final iconButton = tester.widget<IconButton>(toggleFinder);
  expect(iconButton.tooltip, contains('開啟'));

  await tester.tap(toggleFinder);
  await tester.pump();

  expect(toggledValue, isFalse);
});
```

- [x] **Step 2: Run test to verify it fails**

執行：`cd app && flutter test test/screens/library_screen_test.dart --plain-name "LibraryScreen 在 E-Ink 模式開啟與關閉時"`
預期：FAIL（因 tooltip 或樣式不匹配）。

- [x] **Step 3: Write minimal implementation**

在 `app/lib/screens/library_screen.dart` 的 `_buildNormalAppBar` 中修改 E-Ink 切換按鈕（【審查修正 Important】原片段用 `Theme.of(context).brightness == Brightness.dark` 判斷按鈕黑/白配色，但核對 `app_theme_data.dart:127-152` 的 `_buildEinkTheme()` 可知只要 `isEinkMode == true`，全域主題一律套用 `_buildEinkTheme()`，且該函式寫死 `brightness: Brightness.light`——`isEinkMode == true` 時 `brightness` 永遠不可能是 `Brightness.dark`，這個分支是永遠不會被走到的死碼，會誤導後續維護者以為深色主題下配色會不同；已拿掉該判斷，固定使用黑底白圖示）：
```dart
Container(
  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
  decoration: BoxDecoration(
    // E-Ink 開啟時全域主題一律為 _buildEinkTheme()（brightness 恆為
    // Brightness.light），不需要再判斷 brightness，固定黑底即可。
    color: widget.themeDependencies.isEinkMode ? Colors.black : Colors.transparent,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: widget.themeDependencies.isEinkMode
          ? Colors.transparent
          : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
      width: 1.5,
    ),
  ),
  child: IconButton(
    key: const Key('library_eink_toggle'),
    icon: Icon(
      widget.themeDependencies.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
      color: widget.themeDependencies.isEinkMode
          ? Colors.white
          : Theme.of(context).colorScheme.onSurface,
      size: 20,
    ),
    tooltip: widget.themeDependencies.isEinkMode
        ? 'E-Ink 模式：已開啟（點擊切換）'
        : 'E-Ink 模式：已關閉（點擊切換）',
    onPressed: () => widget.themeDependencies.onEinkModeChanged?.call(!widget.themeDependencies.isEinkMode),
  ),
),
```

- [x] **Step 4: Run test to verify it passes**

執行：`cd app && flutter test test/screens/library_screen_test.dart --plain-name "LibraryScreen 在 E-Ink 模式開啟與關閉時"`
預期：PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-27): Issue 5——LibraryScreen AppBar E-Ink 切換按鈕狀態視覺強化"
```
