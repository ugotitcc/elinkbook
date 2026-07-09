# Issue 5：全域主題與 E-Ink 高對比模式 — 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 ElinkBookApp 根據使用者選擇的主題（Light / Dark / Sepia）與 E-Ink 高對比開關套用對應的 `ThemeData`，並在 LibraryScreen 頂部工具列提供切換介面。

**Architecture:** 新增 `app/lib/theme/app_theme_data.dart` 集中定義 4 組 `ThemeData`（light / dark / sepia / eink 高對比）。將 `ElinkBookApp` 從 `StatelessWidget` 改為 `StatefulWidget`，啟動時非同步載入 `AppThemePreferences`，根據 `isEinkMode` 決定套用哪組 `ThemeData`。`LibraryScreen` 的 AppBar 新增 3 個主題圓點按鈕與 1 個 E-Ink 開關，透過 callback 通知 `ElinkBookApp` 更新主題。

**Tech Stack:** Flutter / Dart、`shared_preferences`（已由 Issue 1 建立 `AppThemePreferences`）、Material `ThemeData`

## Global Constraints

- Flutter stable channel（目前 3.41.9）
- 所有程式碼註解使用正體中文
- `flutter analyze` 必須乾淨
- `flutter test` 全部通過、無回歸
- E-Ink 高對比模式為**獨立布林開關**，不是第 4 種主題選項（見 design.md FR-31 與 CONTEXT.md）
- 主題三選一（Light / Dark / Sepia）為全域設定，存於 `shared_preferences`，不進 `book_reader_prefs`
- Prototype UI 把 E-Ink 當第 4 種互斥主題——正式實作以 PRD 為準，E-Ink 為獨立開關

---

### Task 1: 定義 ThemeData 集合（`app_theme_data.dart`）

**Files:**
- Create: `app/lib/theme/app_theme_data.dart`
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: `AppTheme` enum from `app/lib/theme/app_theme.dart`
- Produces:
  - `ThemeData buildThemeData(AppTheme theme)` — 根據 `AppTheme` 回傳對應的 `ThemeData`
  - `ThemeData buildEinkThemeData()` — 回傳 E-Ink 高對比黑白 `ThemeData`
  - `ThemeData resolveThemeData({required AppTheme theme, required bool isEinkMode})` — 解析最終生效的 `ThemeData`（isEinkMode 為 true 時一律回傳 eink，否則依 theme 回傳）

- [ ] **Step 1: 撰寫失敗測試 — 驗證 resolveThemeData 在 E-Ink 關閉時依 theme 回傳不同 ThemeData**

```dart
// app/test/theme/app_theme_data_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  group('resolveThemeData', () {
    test('isEinkMode 為 false 時，light/dark/sepia 回傳不同的 ThemeData', () {
      final light = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      final dark = resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
      final sepia = resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);

      // 三組主題的 scaffoldBackgroundColor 皆不同
      expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
      expect(light.scaffoldBackgroundColor, isNot(sepia.scaffoldBackgroundColor));
      expect(dark.scaffoldBackgroundColor, isNot(sepia.scaffoldBackgroundColor));
    });

    test('isEinkMode 為 true 時，不論 theme 為何皆回傳相同的高對比 ThemeData', () {
      final einkLight =
          resolveThemeData(theme: AppTheme.light, isEinkMode: true);
      final einkDark =
          resolveThemeData(theme: AppTheme.dark, isEinkMode: true);
      final einkSepia =
          resolveThemeData(theme: AppTheme.sepia, isEinkMode: true);

      expect(einkLight.scaffoldBackgroundColor,
          einkDark.scaffoldBackgroundColor);
      expect(einkLight.scaffoldBackgroundColor,
          einkSepia.scaffoldBackgroundColor);
    });

    test('E-Ink 高對比 ThemeData 使用純白背景與純黑文字', () {
      final eink = resolveThemeData(theme: AppTheme.light, isEinkMode: true);
      expect(eink.scaffoldBackgroundColor, Colors.white);
      expect(eink.colorScheme.onSurface, Colors.black);
    });
  });

  group('buildThemeData', () {
    test('light 主題使用淺色背景', () {
      final theme = buildThemeData(AppTheme.light);
      expect(theme.brightness, Brightness.light);
    });

    test('dark 主題使用深色背景', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.brightness, Brightness.dark);
    });

    test('sepia 主題使用暖色調背景', () {
      final theme = buildThemeData(AppTheme.sepia);
      // sepia 是 light brightness 但背景帶暖黃色
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF4ECD8));
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL — `app_theme_data.dart` 尚不存在

- [ ] **Step 3: 實作 app_theme_data.dart**

```dart
// app/lib/theme/app_theme_data.dart
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 參考 prototype/index.html 的 CSS 變數定義，為每種主題建立對應的
/// [ThemeData]。色彩值取自 prototype 的設計（見
/// docs/epics/epic-3-fonts-layout/issues.md Issue 5）。

/// 根據 [theme] 回傳對應的 [ThemeData]，不考慮 E-Ink 高對比模式。
ThemeData buildThemeData(AppTheme theme) {
  switch (theme) {
    case AppTheme.light:
      return _buildLightTheme();
    case AppTheme.dark:
      return _buildDarkTheme();
    case AppTheme.sepia:
      return _buildSepiaTheme();
  }
}

/// 回傳 E-Ink 高對比模式專用的固定黑白 [ThemeData]。
ThemeData buildEinkThemeData() => _buildEinkTheme();

/// 解析最終生效 of [ThemeData]：[isEinkMode] 為 true 時一律套用 E-Ink
/// 高對比主題，不論 [theme] 為何；為 false 時依 [theme] 套用對應主題。
ThemeData resolveThemeData({
  required AppTheme theme,
  required bool isEinkMode,
}) {
  if (isEinkMode) return buildEinkThemeData();
  return buildThemeData(theme);
}

// ──────────────────────────────────────────────────────────
// 私有建構方法
// ──────────────────────────────────────────────────────────

ThemeData _buildLightTheme() {
  const background = Color(0xFFF8F8FA);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF1A1A2E);
  const border = Color(0xFFE0E0E5);
  const primary = Color(0xFF8B5CF6);

  final colorScheme = ColorScheme.light(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildDarkTheme() {
  const background = Color(0xFF121214);
  const surface = Color(0xFF1E1E22);
  const onSurface = Color(0xFFE8E8EC);
  const border = Color(0xFF2A2A30);
  const primary = Color(0xFFBB86FC);

  final colorScheme = ColorScheme.dark(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildSepiaTheme() {
  const background = Color(0xFFF4ECD8);
  const surface = Color(0xFFFAF3E3);
  const onSurface = Color(0xFF5B4636);
  const border = Color(0xFFE6DCBF);
  const primary = Color(0xFFB45309);

  final colorScheme = ColorScheme.light(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildEinkTheme() {
  final colorScheme = ColorScheme.light(
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    background: Colors.white,
    onBackground: Colors.black,
    error: Colors.black,
    onError: Colors.white,
    outline: Colors.black,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    cardColor: Colors.white,
    dividerColor: Colors.black,
    useMaterial3: true,
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/theme/app_theme_data_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "feat(theme): add ThemeData definitions for light/dark/sepia/eink

Issue 5: 新增 resolveThemeData 函式，根據 AppTheme 與 isEinkMode
解析最終生效的 ThemeData。色彩值參考 prototype CSS 變數定義。"
```

---

### Task 2: ElinkBookApp 改為 StatefulWidget 並載入主題

**Files:**
- Modify: `app/lib/main.dart:31-54`
- Test: `app/test/theme/theme_test.dart` (create)

**Interfaces:**
- Consumes:
  - `AppThemePreferences` from `app/lib/theme/app_theme_preferences.dart` — `loadTheme()`, `loadEinkMode()`, `saveTheme()`, `saveEinkMode()`
  - `resolveThemeData({required AppTheme theme, required bool isEinkMode})` from `app/lib/theme/app_theme_data.dart`
- Produces:
  - `ElinkBookApp` 改為 `StatefulWidget`，新增可選建構參數 `AppThemePreferences? themePreferences`（預設建構新實例，方便測試）
  - 內部 state：`_theme`（`AppTheme`）、`_isEinkMode`（`bool`）
  - `MaterialApp.theme` 綁定 `resolveThemeData()` 的結果
  - 暴露方法 `_handleThemeChanged(AppTheme)` 與 `_handleEinkModeChanged(bool)`（Task 3 透過 callback 傳給 LibraryScreen）

- [ ] **Step 1: 撰寫失敗測試 — ElinkBookApp 依載入的主題套用正確 ThemeData**

```dart
// app/test/theme/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/main.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  late SqliteLibraryRepository sqliteRepo;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    sqliteRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(sqliteRepo.database);
  });

  tearDown(() async {
    await sqliteRepo.close();
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (非 E-Ink 模式)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': false,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsRepository: prefsRepository,
        initialTheme: theme,
        initialEinkMode: eink,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (E-Ink 高對比模式)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': true,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsRepository: prefsRepository,
        initialTheme: theme,
        initialEinkMode: eink,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    // E-Ink 高對比模式下，不論原本主題為何，背景皆為純白
    expect(materialApp.theme?.scaffoldBackgroundColor, Colors.white);
    // brightness 為 light（高對比黑白用 light scheme）
    expect(materialApp.theme?.brightness, Brightness.light);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/theme/theme_test.dart`
Expected: FAIL — `ElinkBookApp` 仍為 `StatelessWidget`，`MaterialApp` 沒有設定 `theme` 參數

- [ ] **Step 3: 實作 — 將 ElinkBookApp 改為 StatefulWidget**

將 `app/lib/main.dart` 整檔替換為：

```dart
// app/lib/main.dart
import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'screens/library_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_data.dart';
import 'theme/app_theme_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 於啟動前先非同步載入主題偏好，解決開機畫面閃爍與 Race Condition（見 review 意見）
  final themePreferences = AppThemePreferences();
  final initialTheme = await themePreferences.loadTheme();
  final initialEinkMode = await themePreferences.loadEinkMode();

  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsRepository: prefsRepository,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
    ),
  );
}

/// elinkBook App 根元件。啟動時接受從 main 傳入之 [initialTheme] 與
/// [initialEinkMode]（解決開機閃白屏與狀態競爭問題，見 review 意見）。
class ElinkBookApp extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final BookReaderPrefsRepository prefsRepository;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsRepository,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();

  @override
  State<ElinkBookApp> createState() => _ElinkBookAppState();
}

class _ElinkBookAppState extends State<ElinkBookApp> {
  late AppTheme _theme;
  late bool _isEinkMode;

  @override
  void initState() {
    super.initState();
    _theme = widget.initialTheme;
    _isEinkMode = widget.initialEinkMode;
  }

  Future<void> _handleThemeChanged(AppTheme theme) async {
    setState(() => _theme = theme);
    await widget.themePreferences.saveTheme(theme);
  }

  Future<void> _handleEinkModeChanged(bool enabled) async {
    setState(() => _isEinkMode = enabled);
    await widget.themePreferences.saveEinkMode(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final themeData = resolveThemeData(
      theme: _theme,
      isEinkMode: _isEinkMode,
    );

    return MaterialApp(
      title: 'elinkBook',
      theme: themeData,
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsRepository: widget.prefsRepository,
      ),
    );
  }
}
```

> **重要設計決策：** `ElinkBookApp` 的建構子從 `const` 改為非 const（因為 `themePreferences` 有預設值建構邏輯）。既有程式碼中沒有 `const ElinkBookApp(...)` 的呼叫（`main()` 裡不用 const），所以不會產生破壞性變更。
>
> `LibraryScreen` 的 4 個新建構參數（`currentTheme`/`isEinkMode`/`onThemeChanged`/`onEinkModeChanged`）在 Task 3 才加入。Task 2 階段的 `build()` 方法只傳原有的 3 個參數。

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/theme/theme_test.dart`
Expected: All tests PASS

- [ ] **Step 5: 執行全部測試確認無回歸**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/main.dart app/test/theme/theme_test.dart
git commit -m "feat(theme): ElinkBookApp loads theme from AppThemePreferences

Issue 5: 將 ElinkBookApp 從 StatelessWidget 改為 StatefulWidget，
啟動時載入 AppThemePreferences，根據 isEinkMode 決定套用的
ThemeData。新增 theme_test.dart 驗證主題與 E-Ink 模式的套用行為。"
```

---

### Task 3: LibraryScreen 主題切換 UI

**Files:**
- Modify: `app/lib/main.dart:89-97` (在 `build` 方法中傳遞 4 個新參數給 LibraryScreen)
- Modify: `app/lib/screens/library_screen.dart:1-17` (新增 import)
- Modify: `app/lib/screens/library_screen.dart:24-38` (新增建構參數)
- Modify: `app/lib/screens/library_screen.dart:346-406` (AppBar actions 新增主題 UI)
- Test: `app/test/theme/theme_test.dart` (append 2 tests)

**Interfaces:**
- Consumes:
  - `AppTheme` from `app/lib/theme/app_theme.dart`
  - `ElinkBookApp` 的 `_handleThemeChanged` / `_handleEinkModeChanged` 透過 callback 傳入
- Produces:
  - `LibraryScreen` 新增 4 個可選建構參數（皆有預設值，既有測試不需修改）：
    - `AppTheme currentTheme`（預設 `AppTheme.light`）
    - `bool isEinkMode`（預設 `false`）
    - `ValueChanged<AppTheme>? onThemeChanged`
    - `ValueChanged<bool>? onEinkModeChanged`
  - AppBar 新增 UI 元素，Key 值：
    - `library_theme_dot_light`、`library_theme_dot_dark`、`library_theme_dot_sepia`
    - `library_eink_toggle`

- [ ] **Step 1: 撰寫失敗測試 — LibraryScreen 主題切換按鈕與 E-Ink 開關行為**

在 `app/test/theme/theme_test.dart` 中追加 2 個 testWidgets：

```dart
  testWidgets('LibraryScreen 主題切換按鈕點擊更新 preferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppTheme? receivedTheme;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsRepository: prefsRepository,
          currentTheme: AppTheme.light,
          isEinkMode: false,
          onThemeChanged: (theme) => receivedTheme = theme,
          onEinkModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 點擊 dark 主題圓點
    await tester.tap(find.byKey(const Key('library_theme_dot_dark')));
    await tester.pumpAndSettle();

    expect(receivedTheme, AppTheme.dark);
  });

  testWidgets('LibraryScreen E-Ink 切換按鈕點擊更新 preferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? receivedEinkMode;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsRepository: prefsRepository,
          currentTheme: AppTheme.light,
          isEinkMode: false,
          onThemeChanged: (_) {},
          onEinkModeChanged: (enabled) => receivedEinkMode = enabled,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 點擊 E-Ink 開關
    await tester.tap(find.byKey(const Key('library_eink_toggle')));
    await tester.pumpAndSettle();

    expect(receivedEinkMode, true);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/theme/theme_test.dart`
Expected: FAIL — `LibraryScreen` 尚未接受 `currentTheme`/`isEinkMode`/`onThemeChanged`/`onEinkModeChanged` 參數

- [ ] **Step 3: 修改 LibraryScreen — 新增建構參數與 import**

在 `app/lib/screens/library_screen.dart` 中：

**3a. 新增 import**（在既有 import 區塊後）：

```dart
import '../theme/app_theme.dart';
```

**3b. 修改 `LibraryScreen` class 定義**（原 L24-38）：

```dart
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final BookReaderPrefsRepository prefsRepository;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsRepository,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
```

- [ ] **Step 4: 修改 LibraryScreen — AppBar 新增主題切換 UI**

**4a.** 在 `_LibraryScreenState` 中新增私有方法 `_buildThemeDot`（建議放在 `_buildNormalAppBar` 方法之前或之後）：

```dart
  Widget _buildThemeDot(
    AppTheme theme,
    Color dotColor,
    Color borderColor,
    String keyString,
  ) {
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(keyString),
      // E-Ink 模式下，禁用主題圓點的點擊事件（解決無效點擊反饋問題，見 review 意見）
      onTap: widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        // E-Ink 模式下降低主題圓點不透明度以作視覺提示
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : borderColor,
              width: isSelected ? 2.5 : 1.0,
            ),
          ),
        ),
      ),
    );
  }
```

**4b.** 在 `_buildNormalAppBar` 方法的 `actions` 列表中，在 `PopupMenuButton<LibrarySortBy>` **之前**插入主題元素：

```dart
  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      title: const Text('書架'),
      actions: [
        // ── 主題切換圓點 ──
        _buildThemeDot(AppTheme.light, const Color(0xFFFFFFFF),
            const Color(0xFFCCCCCC), 'library_theme_dot_light'),
        _buildThemeDot(AppTheme.dark, const Color(0xFF121214),
            const Color(0xFF444444), 'library_theme_dot_dark'),
        _buildThemeDot(AppTheme.sepia, const Color(0xFFF4ECD8),
            const Color(0xFFD2C4A5), 'library_theme_dot_sepia'),
        // ── E-Ink 高對比開關 ──
        IconButton(
          key: const Key('library_eink_toggle'),
          icon: Icon(
            widget.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
          ),
          tooltip: widget.isEinkMode ? '關閉 E-Ink 高對比' : '開啟 E-Ink 高對比',
          onPressed: () {
            widget.onEinkModeChanged?.call(!widget.isEinkMode);
          },
        ),
        const SizedBox(width: 4),
        // ── 以下為既有按鈕（排序、檢視模式、匯入、設定），保持不變 ──
        PopupMenuButton<LibrarySortBy>(
          key: const Key('library_sort_button'),
          // ... 其餘不變
```

- [ ] **Step 5: 修改 main.dart — 傳遞主題 callback 給 LibraryScreen**

在 `_ElinkBookAppState.build()` 中，將 `LibraryScreen` 加上 4 個新參數：

```dart
  @override
  Widget build(BuildContext context) {
    final themeData = resolveThemeData(
      theme: _theme,
      isEinkMode: _isEinkMode,
    );

    return MaterialApp(
      title: 'elinkBook',
      theme: themeData,
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsRepository: widget.prefsRepository,
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
      ),
    );
  }
```

- [ ] **Step 6: 執行測試確認通過**

Run: `flutter test test/theme/theme_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 7: 執行全部測試確認無回歸**

Run: `flutter test`
Expected: All tests PASS

> **回歸安全網：** 既有的 `library_screen_test.dart` 建構 `LibraryScreen` 時沒有傳 `currentTheme`/`isEinkMode`/`onThemeChanged`/`onEinkModeChanged`。因為這 4 個參數都有預設值（`AppTheme.light`、`false`、`null`、`null`），所以既有測試不需要任何修改即可通過。

- [ ] **Step 8: Commit**

```bash
git add app/lib/main.dart app/lib/screens/library_screen.dart app/test/theme/theme_test.dart
git commit -m "feat(theme): add theme toggle UI to LibraryScreen AppBar

Issue 5: 在書架頂部工具列新增 3 個主題圓點（light/dark/sepia）與
E-Ink 高對比開關。點擊後透過 callback 通知 ElinkBookApp 更新主題
並持久化至 SharedPreferences。"
```

---

### Task 4: flutter analyze 驗證與最終整合測試

**Files:**
- 無新增檔案，僅執行驗證與必要修正

**Interfaces:**
- Consumes: 前 3 個 Task 的所有產出
- Produces: 乾淨的 `flutter analyze` 輸出與完整通過的測試報告

- [ ] **Step 1: 執行 flutter analyze**

Run: `flutter analyze`
Expected: No issues found

> 若有問題，常見修正項：
> - `unused_import`：移除多餘的 import
> - `prefer_const_constructors`：為 `const` 可行的建構子加上 `const`
> - `unnecessary_this`：移除不必要的 `this.`

- [ ] **Step 2: 修正 analyze 問題（如有）**

依據 Step 1 的錯誤訊息逐一修正對應檔案。

- [ ] **Step 3: 執行全部測試**

Run: `flutter test`
Expected: All tests PASS（原有的所有測試 + 新增的 theme 相關測試）

確認測試清單包含：
- `app_theme_data_test.dart`（6 個測試）
- `theme_test.dart`（4 個測試）
- 所有既有測試（不得有任何回歸）

- [ ] **Step 4: Commit（如有修正）**

```bash
git add -A
git commit -m "fix(theme): address flutter analyze warnings

Issue 5: 修正 flutter analyze 發現的問題。"
```

---

## 檔案結構一覽

| 檔案 | 動作 | 責任 |
|------|------|------|
| `app/lib/theme/app_theme_data.dart` | **新增** | 4 組 ThemeData 定義 + `resolveThemeData` 解析函式 |
| `app/lib/main.dart` | **修改** | `ElinkBookApp` 改為 `StatefulWidget`，載入 `AppThemePreferences` 並套用主題 |
| `app/lib/screens/library_screen.dart` | **修改** | 新增 4 個建構參數 + AppBar 主題切換圓點 + E-Ink 開關 |
| `app/test/theme/app_theme_data_test.dart` | **新增** | ThemeData 建構與解析的單元測試（6 個） |
| `app/test/theme/theme_test.dart` | **新增** | ElinkBookApp 主題載入 + LibraryScreen 主題切換互動的 Widget 測試（4 個） |

## 不在範圍內

- Readium WebView 的閱讀器內容配色（主題只影響 App 的 Flutter UI 層，不影響 EPUB 內容渲染）
- SettingsScreen 內的主題設定（Issue 5 規格明確指定 UI 放在 LibraryScreen 頂部工具列）
- 主題動畫過渡效果（不在 Issue 5 規格範圍內）
- 字型或版面設定相關功能（屬 Issue 2/3/4）
