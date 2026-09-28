# Epic 45 Issue 1：語言選擇 UI（設定→外觀）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在「設定→外觀」新增「語言」選項，讓使用者在跟隨系統／正體中文／簡體中文／English 四者間切換介面語言，切換後立即生效（不需重啟）且持久化，並完成 `spec.md` §4 定案的 `LibraryLocaleDependencies` 全鏈路串接（`ElinkBookApp` → `AdaptiveShellScaffold` → `SettingsScaffold`）。

**Architecture:** 新增 `LibraryLocaleDependencies`（比照既有 `LibraryThemeDependencies` 同檔案、同模式），由 `main.dart` 的 `_ElinkBookAppState` 持有 `_localeOverride` 並透過 `_handleLocaleChanged()` 更新+持久化（比照既有 `_handleThemeChanged()`/`_handleEinkModeChanged()` 寫法對稱）；`AdaptiveShellScaffold` 把 bundle 攤平成具名參數傳給 `SettingsScaffold`（比照 `themeDependencies` 既有攤平慣例，`/receiving-code-review` review-issues M-2 修正已定案）；`SettingsScaffold`「外觀」分區新增「語言」`ListTile`，點擊透過既有共用元件 `EBSheetShell.show<T>` 開啟 4 選項 `RadioListTile` 選擇器。本 Issue 是本 Epic 第一批「畫面字串抽取」的最小示範（`settingsLanguage*` 六個 key），`SettingsScaffold.build()` 首次改用 `AppLocalizations.of(context)!`（force-unwrap，非 Issue 0 `EBSheetShell` 那種 null-safe 過渡寫法——`issues.md` Issue 1「沿用既有 `settings_scaffold_test.dart` 慣例，改用 `pumpLocalizedWidget()`」已定案走完整遷移路線），因此本 Issue 必須把 `settings_scaffold_test.dart`（33 處）與 `adaptive_shell_scaffold_test.dart`（7 處，因 `IndexedStack` 讓 `SettingsScaffold` 全程掛載＋建構，即使測試從未切到設定分頁也一樣會觸發其 `build()`）既有裸 `MaterialApp(...)` 測試一併遷移至 `pumpLocalizedWidget()`，否則這兩個檔案的既有測試會立即因 `Null check operator used on a null value` 崩潰。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5；`AppLocalizations`（Issue 0 已產生）；`EBSheetShell.show<T>`（既有共用底部抽屜元件，`app/lib/screens/widgets/eb_sheet_shell.dart`）；`RadioGroup<AppLocale?>` 包裹 `RadioListTile<AppLocale?>`（比照 `reading_defaults_screen.dart` 既有 `RadioGroup<PageTurnMode>`／`RadioListTile<PageTurnMode>` 慣例——`RadioListTile.groupValue`/`onChanged` 已於 Flutter 3.32 棄用，見 commit `5fa3f5bb`）；`WidgetTester.platformDispatcher.localeTestValue`（`flutter_test` 官方 API，`TestPlatformDispatcher`，用於測試「跟隨系統」動態標註）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md` §4（`LibraryLocaleDependencies`／設定 UI 契約）；工單定義見 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 1」。

## Global Constraints

- **`LibraryLocaleDependencies` 攤平傳遞、不整包傳給 `SettingsScaffold`**（`spec.md` §4，`/receiving-code-review` review-issues M-2 修正，比照 `AdaptiveShellScaffold` 現行 `themeDependencies` 的攤平慣例：`currentTheme:`/`onThemeChanged:` 等個別具名參數）。
- **語言選單一律列舉 `AppLocale.values`（3 個成員：`zhTW`/`zhCN`/`en`），絕不可迭代 `AppLocalizations.supportedLocales`**（該清單因 Flutter 3.41.9 `gen-l10n` 工具限制含 4 個項目，多一個裸 `Locale('zh')`——`plan-issue-0.md` Task 1 事後補記的陷阱提醒）。
- **`currentLocaleOverride == null`（跟隨系統）時，「語言」`ListTile` 的 subtitle 動態標註目前實際生效語言**（例如「跟隨系統（正體中文）」），透過 `resolveSupportedLocale()` 搭配 `View.of(context).platformDispatcher.locale` 計算（`spec.md` §4，`/receiving-code-review` review-issues M-3 修正）。
- **`SettingsScaffold` 新增建構參數必須是可選的**（預設 `null`），既有大量呼叫端（`AdaptiveShellScaffold`、`settings_scaffold_test.dart`）不會傳新參數。
- **本 Issue 觸及的既有測試檔（`settings_scaffold_test.dart`／`adaptive_shell_scaffold_test.dart`）一律改用 `pumpLocalizedWidget()`，不得殘留裸 `MaterialApp(...)`**（`issues.md` Issue 1 單元測試要求；`spec.md` §10 I-1 修正：字串抽取與對應測試遷移須在同一個 Issue 內完成，不可分離成獨立後置 Issue）。
- **計數/ICU plural 語法本 Issue 不適用**（本 Issue 新增的 6 個 key 皆無計數語意，`design.md`/`spec.md` 的 ICU plural 規則留給 Issue 3/5/6）。
- **提交前 `flutter analyze` 必須乾淨（"No issues found!"）**；每個 Task 只需跑該 Task 觸及的測試檔（`CLAUDE.md`「測試執行範圍」既有慣例），完整 `flutter test` 只在本計畫最後一個 Task 跑一次。
- 所有新增檔案/程式碼的中文說明/註解一律使用正體中文（`CLAUDE.md` 全域規則）。

所有指令皆在 `app/` 目錄下執行（`cd /c/Users/fycdc/AI/elinkBook/app`）。

---

### Task 1: `LibraryLocaleDependencies`（依賴 bundle）

**Files:**
- Modify: `app/lib/screens/library_screen_dependencies.dart`
- Test: `app/test/screens/library_screen_dependencies_test.dart`

**Interfaces:**
- Produces: `LibraryLocaleDependencies({AppLocale? currentLocaleOverride, ValueChanged<AppLocale?>? onLocaleChanged})`，供 Task 3（`AdaptiveShellScaffold`）與 Task 4（`main.dart`）使用。

- [x] **Step 1: 寫失敗測試**

在 `app/test/screens/library_screen_dependencies_test.dart` 開頭新增 import：

```dart
import 'package:elinkbook/l10n/app_locale.dart';
```

在檔案最後一個 `test(...)`（`LibraryThemeDependencies` 那一則）之後新增：

```dart
  test('LibraryLocaleDependencies 原樣持有兩個注入的值，未提供時皆為 null（跟隨系統／無回呼）', () {
    const empty = LibraryLocaleDependencies();
    expect(empty.currentLocaleOverride, isNull);
    expect(empty.onLocaleChanged, isNull);

    void onLocaleChanged(AppLocale? locale) {}
    final dependencies = LibraryLocaleDependencies(
      currentLocaleOverride: AppLocale.zhCN,
      onLocaleChanged: onLocaleChanged,
    );
    expect(dependencies.currentLocaleOverride, AppLocale.zhCN);
    expect(dependencies.onLocaleChanged, same(onLocaleChanged));
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_dependencies_test.dart`
Expected: 編譯錯誤（`LibraryLocaleDependencies` 尚未定義）。

- [x] **Step 3: 實作 `LibraryLocaleDependencies`**

修改 `app/lib/screens/library_screen_dependencies.dart`：在 `import '../theme/app_theme.dart';` 之後新增：

```dart
import '../l10n/app_locale.dart';
```

在檔案最後（`LibraryThemeDependencies` 類別之後）新增：

```dart

/// 收斂介面語言相關欄位（epic-45-interface-i18n Issue 1，`spec.md` §4）。
/// `currentLocaleOverride == null` 代表跟隨系統（比照 `AppLocalePreferences`
/// 既有 nullable 儲存語意，見 `app/lib/l10n/app_locale_preferences.dart`）。
@immutable
class LibraryLocaleDependencies {
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppLocale?>? onLocaleChanged;

  const LibraryLocaleDependencies({
    this.currentLocaleOverride,
    this.onLocaleChanged,
  });
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_screen_dependencies_test.dart`
Expected: PASS（全部既有 test + 新增的 1 個皆通過）。

- [x] **Step 5: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [x] **Step 6: Commit**

```bash
git add lib/screens/library_screen_dependencies.dart test/screens/library_screen_dependencies_test.dart
git commit -m "feat(epic-45): 新增 LibraryLocaleDependencies 依賴 bundle"
```

---

### Task 2: `SettingsScaffold`「語言」選項 UI ＋ ARB 字串抽取 ＋ 既有測試遷移

**Files:**
- Modify: `app/lib/l10n/app_zh_TW.arb`
- Modify: `app/lib/l10n/app_zh_CN.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/test/screens/settings_scaffold_test.dart`（新增 8 個測試＋既有 33 處 `MaterialApp(...)` 全數遷移至 `pumpLocalizedWidget()`）

**Interfaces:**
- Consumes: `LibraryLocaleDependencies`（Task 1，本 Task 不直接用到這個型別本身，`SettingsScaffold` 收的是攤平後的 `AppLocale? currentLocaleOverride`/`ValueChanged<AppLocale?>? onLocaleChanged`）；`AppLocale`（`app/lib/l10n/app_locale.dart`，Issue 0 已產生）；`resolveSupportedLocale()`（同檔案，Issue 0 已產生）；`EBSheetShell.show<T>`（`app/lib/screens/widgets/eb_sheet_shell.dart`，Issue 0 已在地化其關閉按鈕）；`pumpLocalizedWidget()`（`app/test/support/pump_localized_widget.dart`，Issue 0 已產生）。
- Produces: `SettingsScaffold` 新增 `currentLocaleOverride`/`onLocaleChanged` 建構參數；`Key('settings_language_button')`（開啟選擇器的 `ListTile`）；`Key('settings_language_option_follow_system')`/`Key('settings_language_option_zh_tw')`/`Key('settings_language_option_zh_cn')`/`Key('settings_language_option_en')`（選擇器內 4 個 `RadioListTile`），供 Task 3/4 的 widget test 以及未來 Issue 5（其餘設定畫面字串抽取）沿用同一批 ARB key 命名慣例參考。

- [x] **Step 1: 新增 ARB key（4 份檔案）**

`app/lib/l10n/app_zh_TW.arb`（template，在既有 `"close"`/`"@close"` 區塊之後新增，注意在 `"@close": {...}` 後補上逗號）：

```json
{
  "@@locale": "zh_TW",
  "groupUncategorized": "未分類",
  "@groupUncategorized": {
    "description": "系統保留分類「未分類」的表現層顯示名稱（僅用於畫面呈現，不影響底層資料庫欄位值，見 CONTEXT.md「介面語言」詞條）"
  },
  "close": "關閉",
  "@close": {
    "description": "通用「關閉」按鈕/圖示的無障礙提示文字（tooltip）"
  },
  "settingsLanguageTitle": "語言",
  "@settingsLanguageTitle": {
    "description": "設定「外觀」分區的語言選擇入口標題"
  },
  "settingsLanguageFollowSystem": "跟隨系統",
  "@settingsLanguageFollowSystem": {
    "description": "語言選擇器中「跟隨系統」選項標籤"
  },
  "settingsLanguageFollowSystemSubtitle": "跟隨系統（{language}）",
  "@settingsLanguageFollowSystemSubtitle": {
    "description": "「語言」入口未手動覆寫時的動態副標題，{language} 為依目前系統語言解析出的語言顯示名稱",
    "placeholders": {
      "language": {
        "type": "String"
      }
    }
  },
  "settingsLanguageZhTW": "正體中文",
  "@settingsLanguageZhTW": {
    "description": "語言選項：正體中文"
  },
  "settingsLanguageZhCN": "簡體中文",
  "@settingsLanguageZhCN": {
    "description": "語言選項：簡體中文"
  },
  "settingsLanguageEn": "English",
  "@settingsLanguageEn": {
    "description": "語言選項：英文（語言本身的固有名稱，不翻譯）"
  }
}
```

`app/lib/l10n/app_zh_CN.arb`：

```json
{
  "@@locale": "zh_CN",
  "groupUncategorized": "未分类",
  "close": "关闭",
  "settingsLanguageTitle": "语言",
  "settingsLanguageFollowSystem": "跟随系统",
  "settingsLanguageFollowSystemSubtitle": "跟随系统（{language}）",
  "settingsLanguageZhTW": "正体中文",
  "settingsLanguageZhCN": "简体中文",
  "settingsLanguageEn": "English"
}
```

`app/lib/l10n/app_en.arb`：

```json
{
  "@@locale": "en",
  "groupUncategorized": "Uncategorized",
  "close": "Close",
  "settingsLanguageTitle": "Language",
  "settingsLanguageFollowSystem": "Follow System",
  "settingsLanguageFollowSystemSubtitle": "Follow System ({language})",
  "settingsLanguageZhTW": "Traditional Chinese",
  "settingsLanguageZhCN": "Simplified Chinese",
  "settingsLanguageEn": "English"
}
```

`app/lib/l10n/app_zh.arb`（`gen-l10n` 要求的基礎 fallback，比照既有 2 個 key 沿用 `zh_TW` 的值，見 `plan-issue-0.md` Task 1 附註）：

```json
{
  "@@locale": "zh",
  "groupUncategorized": "未分類",
  "close": "關閉",
  "settingsLanguageTitle": "語言",
  "settingsLanguageFollowSystem": "跟隨系統",
  "settingsLanguageFollowSystemSubtitle": "跟隨系統（{language}）",
  "settingsLanguageZhTW": "正體中文",
  "settingsLanguageZhCN": "簡體中文",
  "settingsLanguageEn": "English"
}
```

- [x] **Step 2: 重新產生 `AppLocalizations`**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/app_localizations*.dart` 已更新，新增 `settingsLanguageTitle`/`settingsLanguageFollowSystem`/`settingsLanguageZhTW`/`settingsLanguageZhCN`/`settingsLanguageEn`（無參數 getter）與 `settingsLanguageFollowSystemSubtitle(String language)`（帶參數方法）。

- [x] **Step 3: 寫失敗測試（新增 8 個 test，含 `/receiving-code-review` I-1／I-3 修正後補齊的選項覆蓋）**

在 `app/test/screens/settings_scaffold_test.dart` 開頭新增 import（與既有 import 群組對齊，`elinkbook/` 套件 import 區塊內按字母序插入）：

```dart
import 'package:elinkbook/l10n/app_locale.dart';
```

並在檔案最後一個既有 `testWidgets` 區塊（`didUpdateWidget 時重新載入全文檢索開關狀態`，`group('epic-10-search Issue 3：全文檢索設定開關', ...)` 內）之後、`group()` 的收尾 `});` 之外，新增一個新的頂層 `group('epic-45-interface-i18n Issue 1：語言選擇 UI', () { ... });`：

```dart

  group('epic-45-interface-i18n Issue 1：語言選擇 UI', () {
    testWidgets('顯示「語言」入口，currentLocaleOverride 非 null 時 subtitle 顯示該語言名稱',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.zhCN,
        ),
      );

      expect(find.byKey(const Key('settings_language_button')), findsOneWidget);
      expect(find.text('語言'), findsOneWidget);
      expect(find.text('簡體中文'), findsOneWidget);
    });

    testWidgets(
        'currentLocaleOverride 為 null（跟隨系統）時，subtitle 動態標註目前系統實際生效語言',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      expect(find.text('跟隨系統（English）'), findsOneWidget);
    });

    testWidgets('點擊「語言」開啟選擇器，4 個選項存在，目前選中項目正確反映 currentLocaleOverride',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings_language_option_follow_system')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_language_option_zh_tw')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_language_option_zh_cn')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings_language_option_en')), findsOneWidget);

      // 【/receiving-code-review I-1 修正】`RadioListTile.groupValue`／
      // `onChanged` 已於本專案改用 `RadioGroup<T>` 祖先包裹（見
      // reading_defaults_screen.dart／commit 5fa3f5bb），選中狀態改斷言
      // 外層 `RadioGroup` 的 `groupValue`，而非逐一讀取個別 tile（個別
      // tile 已不再持有這個值）。
      final group = tester.widget<RadioGroup<AppLocale?>>(
        find.byType(RadioGroup<AppLocale?>),
      );
      expect(group.groupValue, AppLocale.en);
    });

    testWidgets(
        'currentLocaleOverride 為 null 時，開啟選擇器「跟隨系統」呈現選中狀態（/receiving-code-review I-3 修正）',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();

      final group = tester.widget<RadioGroup<AppLocale?>>(
        find.byType(RadioGroup<AppLocale?>),
      );
      expect(group.groupValue, isNull);
    });

    testWidgets('選取「正體中文」選項，onLocaleChanged 收到 AppLocale.zhTW 且 Sheet 關閉',
        (tester) async {
      AppLocale? received;
      var receivedCalled = false;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
          onLocaleChanged: (locale) {
            receivedCalled = true;
            received = locale;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_zh_tw')));
      await tester.pumpAndSettle();

      expect(receivedCalled, isTrue);
      expect(received, AppLocale.zhTW);
      expect(
        find.byKey(const Key('settings_language_option_zh_tw')),
        findsNothing,
        reason: 'Sheet 應已關閉',
      );
    });

    testWidgets('選取「跟隨系統」選項，onLocaleChanged 收到 null', (tester) async {
      AppLocale? received = AppLocale.en;
      var receivedCalled = false;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
          onLocaleChanged: (locale) {
            receivedCalled = true;
            received = locale;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings_language_option_follow_system')),
      );
      await tester.pumpAndSettle();

      expect(receivedCalled, isTrue);
      expect(received, isNull);
    });

    testWidgets(
        '選取「簡體中文」與「English」選項，onLocaleChanged 分別收到對應列舉值（/receiving-code-review I-3 修正：原測試僅覆蓋正體中文／跟隨系統兩個選項）',
        (tester) async {
      AppLocale? received;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          onLocaleChanged: (locale) => received = locale,
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_zh_cn')));
      await tester.pumpAndSettle();
      expect(received, AppLocale.zhCN);

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_en')));
      await tester.pumpAndSettle();
      expect(received, AppLocale.en);
    });

    testWidgets('未接上 onLocaleChanged 時，選取選項不崩潰', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_en')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
```

- [x] **Step 4: 執行新測試確認失敗**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: 編譯錯誤（`SettingsScaffold` 沒有 `currentLocaleOverride`/`onLocaleChanged` 具名參數）。

- [x] **Step 5: 實作 `SettingsScaffold`「語言」選項**

修改 `app/lib/screens/settings_scaffold.dart`。

**5a. 新增 import**（`import '../cloud_import/onedrive_oauth_client.dart';` 之後、`import '../reader/custom_fonts_repository.dart';` 之前插入，按字母序）：

```dart
import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
```

並在 `import 'widgets/eb_field_card.dart';`/`import 'widgets/eb_section_header.dart';` 之後新增：

```dart
import 'widgets/eb_sheet_shell.dart';
```

**5b. 新增欄位**（在 `final ValueChanged<bool>? onEinkModeChanged;` 之後插入）：

```dart
  final ValueChanged<bool>? onEinkModeChanged;

  /// 介面語言（FR-49，epic-45-interface-i18n Issue 1）。`null` 代表跟隨
  /// 系統，比照 `spec.md` §4 `LibraryLocaleDependencies` 的 nullable 儲存
  /// 語意。
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppLocale?>? onLocaleChanged;
  final CustomFontsRepository? customFontsRepository;
```

（原本緊接在 `onEinkModeChanged` 之後的 `customFontsRepository` 欄位宣告原樣保留，只是插入點在它之前。）

**5c. 新增建構參數**（在 `this.onEinkModeChanged,` 之後插入）：

```dart
    this.onEinkModeChanged,
    this.currentLocaleOverride,
    this.onLocaleChanged,
    this.customFontsRepository,
```

**5d. `build()` 開頭新增 `l10n` 變數**：

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
```

**5e. 「佈景」卡片之後、E-Ink 開關卡片之前，新增「語言」卡片**（緊接 `_SettingsCard(child: ListTile(title: const Text('佈景'), ...))` 那個 `_SettingsCard(...)` 區塊結尾的 `),` 之後）：

```dart
          _SettingsCard(
            child: ListTile(
              key: const Key('settings_language_button'),
              title: Text(l10n.settingsLanguageTitle),
              subtitle: _buildLanguageSubtitle(context, l10n),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLanguagePicker(context, l10n),
            ),
          ),
```

**5f. 新增私有方法**（在既有 `_buildThemeDot()` 方法之前或之後皆可，此處放在 `_themeLabel()` 方法之後、`_SettingsScaffoldState` 類別收尾 `}` 之前）：

```dart

  Widget _buildLanguageSubtitle(BuildContext context, AppLocalizations l10n) {
    final override = widget.currentLocaleOverride;
    if (override != null) {
      return Text(_languageLabel(override, l10n));
    }
    final resolved = resolveSupportedLocale(
      View.of(context).platformDispatcher.locale,
    );
    return Text(
      l10n.settingsLanguageFollowSystemSubtitle(_languageLabel(resolved, l10n)),
    );
  }

  String _languageLabel(AppLocale locale, AppLocalizations l10n) =>
      switch (locale) {
        AppLocale.zhTW => l10n.settingsLanguageZhTW,
        AppLocale.zhCN => l10n.settingsLanguageZhCN,
        AppLocale.en => l10n.settingsLanguageEn,
      };

  Future<void> _openLanguagePicker(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final choice = await EBSheetShell.show<_LocaleChoice>(
      context,
      title: l10n.settingsLanguageTitle,
      isEinkMode: widget.isEinkMode,
      builder: (context) => _LanguagePickerSheet(
        currentLocaleOverride: widget.currentLocaleOverride,
      ),
    );
    if (choice == null) return;
    widget.onLocaleChanged?.call(choice.value);
  }
```

**5g. 新增私有類別**（檔案最後，`_SettingsCard` 類別之後、`_LockedDotBorderPainter` 類別之前或之後皆可，此處放在檔案最末）：

```dart

/// [EBSheetShell.show] 的回傳型別包裝：`null`（整個 Future 的結果）代表
/// 使用者未選取任何選項就關閉 Sheet（滑動/點擊外部），[_LocaleChoice.value]
/// 才是使用者實際選取的語言——`value` 本身也可能是 `null`（代表「跟隨
/// 系統」），兩種「null」意義不同，若不用這層包裝、直接讓 `EBSheetShell.
/// show<AppLocale?>` 回傳 `AppLocale?`，會無法分辨「使用者選了跟隨系統」
/// 與「使用者什麼都沒選就關閉」。
class _LocaleChoice {
  final AppLocale? value;

  const _LocaleChoice(this.value);
}

class _LanguagePickerSheet extends StatelessWidget {
  final AppLocale? currentLocaleOverride;

  const _LanguagePickerSheet({required this.currentLocaleOverride});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 【/receiving-code-review I-1 修正】`RadioListTile.groupValue`／
    // `onChanged` 已棄用（見 reading_defaults_screen.dart／commit
    // 5fa3f5bb 既有慣例），改用外層 `RadioGroup<T>` 統一管理選中值與變更
    // 回呼，個別 `RadioListTile` 只宣告自己的 `value`。
    //
    // 【/receiving-code-review M-2 補述】Radio 的原生行為是「點擊與
    // groupValue 相同的選項不會觸發 onChanged」——若使用者打開選擇器後
    // 點擊「目前已選中的語言」，Sheet 不會自動關閉（需手動點右上角關閉或
    // 點遮罩），這是符合預期的單選元件原生行為，不是缺陷；未來若要優化
    // 這個互動（例如點擊已選中項也能關閉），需另外包一層 `GestureDetector`
    // /`InkWell`，不在本 Issue 範圍內。
    return RadioGroup<AppLocale?>(
      groupValue: currentLocaleOverride,
      onChanged: (value) => Navigator.of(context).pop(_LocaleChoice(value)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_follow_system'),
            title: Text(l10n.settingsLanguageFollowSystem),
            value: null,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_zh_tw'),
            title: Text(l10n.settingsLanguageZhTW),
            value: AppLocale.zhTW,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_zh_cn'),
            title: Text(l10n.settingsLanguageZhCN),
            value: AppLocale.zhCN,
          ),
          RadioListTile<AppLocale?>(
            key: const Key('settings_language_option_en'),
            title: Text(l10n.settingsLanguageEn),
            value: AppLocale.en,
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 6: 執行新測試確認通過**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: 新增的 8 個測試 PASS；既有測試此時預期**大量失敗**（`Null check operator used on a null value`，因為 `build()` 現在無條件呼叫 `AppLocalizations.of(context)!`，既有測試仍是裸 `MaterialApp(...)`）——這是本 Step 的預期中間狀態，下一步處理。

- [x] **Step 7: 既有 33 處 `MaterialApp(...)` 遷移至 `pumpLocalizedWidget()`**

在檔案開頭新增 import（與既有 `elinkbook/` import 群組分開，比照 `eb_sheet_shell_test.dart` 既有慣例獨立一行）：

```dart
import '../support/pump_localized_widget.dart';
```

**機械式轉換規則**：把每一處

```dart
await tester.pumpWidget(
  MaterialApp(
    home: SettingsScaffold(
      ...
    ),
  ),
);
```

改為

```dart
await pumpLocalizedWidget(
  tester,
  SettingsScaffold(
    ...
  ),
);
```

`SettingsScaffold(...)` 內部參數原封不動搬移，其餘測試邏輯（`tester.tap()`／`expect()`／`tester.view.physicalSize` 等）不變。單行寫法比照相同規則，例如：

```dart
// Before
await tester.pumpWidget(
  MaterialApp(home: SettingsScaffold(prefsManager: prefsManager)),
);
// After
await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: prefsManager));
```

少數測試（`didUpdateWidget 時重新載入全文檢索開關狀態`）同一個 test 內有 2 次 `tester.pumpWidget(MaterialApp(...))`（第二次是模擬 `IndexedStack` 切分頁重新 build），兩次都套用同一條規則各自轉換。

對以下 33 個 `MaterialApp(` 起始行號（遷移前行號，逐一套用上述規則；遷移後實際行號會偏移，以內容比對為準，不要死板依賴行號）逐一套用：
62、89、107、137、155、168、184、208、240、279、310、346、375、399、421、477、544、569、600、633、676、719、745、760、783、817、857、894、927、951、975、1011、1032。

- [x] **Step 8: 執行完整檔案測試確認全數通過**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: PASS（既有 32 個 `testWidgets` 全數遷移後通過＋新增 8 個 test，零回歸）。

- [x] **Step 9: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [x] **Step 10: Commit**

```bash
git add lib/l10n/app_zh_TW.arb lib/l10n/app_zh_CN.arb lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_zh.dart lib/l10n/app_localizations_en.dart lib/screens/settings_scaffold.dart test/screens/settings_scaffold_test.dart
git commit -m "feat(epic-45): SettingsScaffold 新增「語言」選擇 UI"
```

（`gen-l10n` 實際會為每個支援語言各自產生一個 `app_localizations_<locale>.dart` 檔案，例如 `app_localizations_zh.dart`／`app_localizations_en.dart`——`git add lib/l10n/` 整個目錄比逐一列舉檔名更不易遺漏，若採用整目錄寫法為 `git add lib/l10n/`。）

---

### Task 3: `AdaptiveShellScaffold` 串接 `localeDependencies`

**Files:**
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Test: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces:**
- Consumes: `LibraryLocaleDependencies`（Task 1）；`SettingsScaffold.currentLocaleOverride`/`onLocaleChanged`（Task 2）。
- Produces: `AdaptiveShellScaffold.localeDependencies`（預設 `const LibraryLocaleDependencies()`），供 Task 4（`main.dart`）注入。

- [x] **Step 1: 寫失敗測試**

在 `app/test/screens/adaptive_shell_scaffold_test.dart` 開頭新增 import（`/receiving-code-review` I-2 修正：直接引入 `pumpLocalizedWidget()`，本 Step 新增的測試從一開始就不使用裸 `MaterialApp(...)`——Task 2 已使 `SettingsScaffold.build()` 無條件呼叫 `AppLocalizations.of(context)!`，而 `IndexedStack` 讓 `AdaptiveShellScaffold` 的任何一次 `pumpWidget()` 都會連帶建構、渲染 `SettingsScaffold`，裸 `MaterialApp(...)` 會讓本 Step 新增的測試本身也在 Step 4 崩潰，而非只有既有測試崩潰）：

```dart
import 'package:elinkbook/l10n/app_locale.dart';

import '../support/pump_localized_widget.dart';
```

在檔案最後一個既有 `testWidgets`（`wifiTransferDependencies 正確原樣傳遞給 SourcesHomeScreen`）之後新增：

```dart

  testWidgets('SettingsScaffold 收到 localeDependencies.currentLocaleOverride／onLocaleChanged 轉送',
      (tester) async {
    AppLocale? received;
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        localeDependencies: LibraryLocaleDependencies(
          currentLocaleOverride: AppLocale.zhCN,
          onLocaleChanged: (locale) => received = locale,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScaffold =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(settingsScaffold.currentLocaleOverride, AppLocale.zhCN);
    expect(settingsScaffold.onLocaleChanged, isNotNull);

    settingsScaffold.onLocaleChanged!(AppLocale.en);
    expect(received, AppLocale.en);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: 編譯錯誤（`AdaptiveShellScaffold` 沒有 `localeDependencies` 具名參數）。

- [x] **Step 3: 實作 `AdaptiveShellScaffold` 接線**

修改 `app/lib/screens/adaptive_shell_scaffold.dart`。

**3a.** 在 `final LibraryThemeDependencies themeDependencies;` 之後新增：

```dart
  final LibraryThemeDependencies themeDependencies;

  /// 介面語言依賴（epic-45-interface-i18n Issue 1，`spec.md` §4）。
  final LibraryLocaleDependencies localeDependencies;
```

**3b.** 在 `this.themeDependencies = const LibraryThemeDependencies(),` 之後新增：

```dart
    this.themeDependencies = const LibraryThemeDependencies(),
    this.localeDependencies = const LibraryLocaleDependencies(),
```

**3c.** 在 `build()` 內 `SettingsScaffold(...)` 呼叫中，`onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,` 之後新增：

```dart
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              currentLocaleOverride:
                  widget.localeDependencies.currentLocaleOverride,
              onLocaleChanged: widget.localeDependencies.onLocaleChanged,
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: 新增測試 PASS；既有測試此時預期大量失敗（原因同 Task 2 Step 6——`SettingsScaffold.build()` 已無條件需要 `AppLocalizations`，本檔案既有 7 處裸 `MaterialApp(...)` 尚未遷移）。

- [x] **Step 5: 既有 7 處 `MaterialApp(...)` 遷移至 `pumpLocalizedWidget()`**

（`pump_localized_widget.dart` 的 import 已在 Step 1 新增，本 Step 不需要重複新增。）

逐一改寫（`AdaptiveShellScaffold(...)` 內部參數原封不動搬移；原本 `theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false)` 恰為 `pumpLocalizedWidget()` 預設值，直接省略即可，不需要顯式傳遞）：

**`buildApp()` 輔助函式**（原第 33-42 行）：

```dart
  Widget buildApp() {
    return AdaptiveShellScaffold(
      repository: FakeLibraryRepository(),
      importService: FakeBookImportService(),
      prefsManager: prefsManager,
    );
  }
```

呼叫端隨之改為 `await pumpLocalizedWidget(tester, buildApp());`（取代原本的 `await tester.pumpWidget(buildApp());`——`buildApp()` 現在回傳 `AdaptiveShellScaffold` 本身而非包好的 `MaterialApp`，共 4 處呼叫：「三個目的地圖示切換」「非書架分頁時系統返回鍵優先切回書架」「在設定分頁點擊『書架』圖示切回書架分頁」「在設定分頁點擊『來源』圖示切到來源分頁」）。

**「切回書架分頁時觸發 refreshSignal」測試**（原第 79-88 行）：

```dart
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
```

**「SettingsScreen 收到 customFontsRepository/onEinkModeChanged 轉送」測試**（原第 129-144 行）：

```dart
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          customFontsRepository: customFontsRepository,
        ),
        themeDependencies: LibraryThemeDependencies(
          onEinkModeChanged: (val) => toggledValue = val,
        ),
      ),
    );
```

**「上層 themeDependencies 更新後...」測試的 `buildWithEink()`**（原第 162-172 行，`isEinkMode` 為動態參數，需顯式傳給 `pumpLocalizedWidget()`）：

```dart
    Widget buildWithEink(bool isEinkMode) {
      return AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        themeDependencies: LibraryThemeDependencies(isEinkMode: isEinkMode),
      );
    }
```

呼叫端改為 `await pumpLocalizedWidget(tester, buildWithEink(false), isEinkMode: false);` 與 `await pumpLocalizedWidget(tester, buildWithEink(true), isEinkMode: true);`（取代原本 2 處 `await tester.pumpWidget(buildWithEink(...));`）。

**「SettingsScaffold 收到 readerFeatureRepositories.ttsProvider 轉送」測試**（原第 227-238 行）：

```dart
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories:
            LibraryReaderFeatureRepositories(ttsProvider: ttsProvider),
      ),
    );
```

**「SettingsScreen 收到 fullTextSearchSettingsRepository/isFullTextSearchAvailable 轉送」測試**（原第 254-266 行）：

```dart
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
          isFullTextSearchAvailable: false,
        ),
      ),
    );
```

**「wifiTransferDependencies 正確原樣傳遞給 SourcesHomeScreen」測試**（原第 291-300 行）：

```dart
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        wifiTransferDependencies: wifiDeps,
      ),
    );
```

**本 Task 自己 Step 1 新增的測試**（`SettingsScaffold 收到 localeDependencies...`）已在 Step 1 直接以 `pumpLocalizedWidget()` 撰寫（`/receiving-code-review` I-2 修正），本 Step 不需要再處理它。

**（`/receiving-code-review` M-3 修正）**：全部 7 處遷移完成後，`import 'package:elinkbook/theme/app_theme_data.dart';`（第 13 行）在本檔案不再被任何程式碼引用——`buildWithEink()` 的 `LibraryThemeDependencies(isEinkMode: isEinkMode)` 不需要 `AppTheme`/`resolveThemeData`，其餘既有程式碼也未引用——直接移除這行 import，不需要另外執行 `flutter analyze` 才能判斷。

- [x] **Step 6: 執行完整檔案測試確認全數通過**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: **新增測試 PASS**；整檔執行呈現 `10 passed, 2 failed`（既有 11 個 `testWidgets` ＋新增 1 個＝12 個，其中 2 項失敗——`LateInitializationError: Field '_batchActions@...' has already been initialized.` 與 `'_dependents.isEmpty': is not true.`——為 `main` 分支既知既存問題，`review-issue-0.md` 已獨立在 base commit 重跑驗證同一結論，非本 Task 引入之回歸，見 `/receiving-code-review` M-1 修正）。

- [x] **Step 7: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [x] **Step 8: Commit**

```bash
git add lib/screens/adaptive_shell_scaffold.dart test/screens/adaptive_shell_scaffold_test.dart
git commit -m "feat(epic-45): AdaptiveShellScaffold 串接 localeDependencies"
```

---

### Task 4: `main.dart` 接線（`_handleLocaleChanged`）

**Files:**
- Modify: `app/lib/main.dart`
- Test: `app/test/l10n/elinkbook_app_locale_test.dart`

**Interfaces:**
- Consumes: `LibraryLocaleDependencies`（Task 1）；`AdaptiveShellScaffold.localeDependencies`（Task 3）；既有 `AppLocalePreferences`／`_localeOverride`（Issue 0 已產生，`app/lib/main.dart` 既有 `_ElinkBookAppState._localeOverride` 欄位目前尚未被任何 UI 更新過）。
- Produces: `_ElinkBookAppState._handleLocaleChanged(AppLocale?)`，完成本 Epic 「語言切換立即生效＋持久化」的端對端行為。

- [x] **Step 1: 寫失敗測試**

在 `app/test/l10n/elinkbook_app_locale_test.dart` 開頭新增 import：

```dart
import 'package:elinkbook/l10n/app_locale_preferences.dart';
```

在檔案最後一個既有 `testWidgets`（`AppLocalizations.of(context) 在 Widget 樹內可正常取得而不拋例外`）之後新增：

```dart

  testWidgets(
      '選取語言後，MaterialApp.locale 立即反映新語言，且 AppLocalePreferences.saveLocaleOverride 持久化新值',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_option_zh_cn')));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('zh', 'CN'));

    final saved = await AppLocalePreferences().loadLocaleOverride();
    expect(saved, AppLocale.zhCN);
  });

  testWidgets('選取「跟隨系統」後，MaterialApp.locale 變回 null（不再手動覆寫）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        initialLocaleOverride: AppLocale.en,
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(before.locale, const Locale('en'));

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings_language_option_follow_system')),
    );
    await tester.pumpAndSettle();

    final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(after.locale, isNull);

    final saved = await AppLocalePreferences().loadLocaleOverride();
    expect(saved, isNull);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/l10n/elinkbook_app_locale_test.dart`
Expected: 2 個新測試 FAIL（`materialApp.locale` 斷言失敗——`main.dart` 尚未把 `onLocaleChanged` 接上，點擊選項後 `MaterialApp.locale` 不會變化）。

- [x] **Step 3: 實作 `_handleLocaleChanged()` 並接線**

修改 `app/lib/main.dart`。

**3a.** 在 `_handleEinkModeChanged()` 方法之後新增：

```dart
  void _handleEinkModeChanged(bool enabled) {
    setState(() => _isEinkMode = enabled);
    widget.themePreferences.saveEinkMode(enabled);
  }

  void _handleLocaleChanged(AppLocale? locale) {
    setState(() => _localeOverride = locale);
    widget.localePreferences.saveLocaleOverride(locale);
  }
```

**3b.** 在 `build()` 內 `AdaptiveShellScaffold(...)` 呼叫中，`themeDependencies: LibraryThemeDependencies(...)` 區塊之後新增：

```dart
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
        localeDependencies: LibraryLocaleDependencies(
          currentLocaleOverride: _localeOverride,
          onLocaleChanged: _handleLocaleChanged,
        ),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/l10n/elinkbook_app_locale_test.dart`
Expected: PASS（既有 6 個 test ＋新增 2 個，共 8 個，零回歸）。

- [x] **Step 5: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [x] **Step 6: Commit**

```bash
git add lib/main.dart test/l10n/elinkbook_app_locale_test.dart
git commit -m "feat(epic-45): main.dart 接線語言切換（_handleLocaleChanged）"
```

---

### Task 5: 完整驗收

**Files:** 無新增/修改，純驗證＋文件更新。

- [x] **Step 1: 完整 `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [x] **Step 2: 完整 `flutter test`**

Run: `flutter test`
Expected: 全數通過（若有既存、與本 Issue 無關的既知不穩定測試——例如 `review-issue-0.md` 記錄的 `adaptive_shell_scaffold_test.dart` 2 則既知瑕疵——比對是否為 base commit 既存缺陷而非本 Issue 引入的回歸）。

- [x] **Step 3: 手動驗證語言切換行為**

Run:
```bash
flutter run
```
Expected: 「設定→外觀」出現「語言」項目，subtitle 依目前系統語言正確標註；點擊開啟 4 選項選擇器；切換任一語言後畫面立即以新語言渲染（至少「語言」項目本身），不需重啟 App；重新啟動 App 後記住選擇；選「跟隨系統」後裝置系統語言變更時 App 動態跟隨。

- [x] **Step 4: 更新 `docs/epics/epic-45-interface-i18n/issues.md` 與 `epic.md`**

在 `issues.md` 的「Issue 1」標題旁補上 `**Status:** completed`，並在 `epic.md` 新增一段開發記錄，記錄本 Issue 完成情況。

- [x] **Step 5: 更新 `docs/epics.md` 進度**

把第 46 列（`epic-45-interface-i18n`）備註欄位改為反映 Issue 1 已完成（例如「Issue 0／1（PR #261／#<新 PR 號>）已完成並合併，待認領 Issue 2」，實際 PR 編號待發 PR 時才會知道，這裡先用「Issue 0／1 已完成」佔位，發 PR 後再補號碼——這不算計畫文件的 placeholder 違規，是流程上必然晚於本計畫產出的資訊）。

- [x] **Step 6: Commit**

```bash
git add ../docs/epics/epic-45-interface-i18n/issues.md ../docs/epics/epic-45-interface-i18n/epic.md ../docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 1 為 completed"
```

---

## Self-Review 摘要（撰寫計畫時的自我檢查紀錄）

- **Spec 覆蓋度**：`spec.md` §4「`LibraryLocaleDependencies`」→ Task 1；§4「`SettingsScaffold` 語言選項 UI」→ Task 2；§4「逐層透傳」→ Task 3（`AdaptiveShellScaffold`）／Task 4（`main.dart`）。`issues.md` Issue 1 的 4 條 What-to-build 項目（`LibraryLocaleDependencies`／逐層透傳＋攤平慣例／「語言」`ListTile`＋動態 subtitle／ARB key）依序對應 Task 1／Task 3-4／Task 2／Task 2。單元測試要求 4 條（`SettingsScaffold` widget test／`AdaptiveShellScaffold` widget test／`ElinkBookApp` widget test／既有測試遷移）依序對應 Task 2／Task 3／Task 4／Task 2+3。
- **型別一致性**：`AppLocale?`（Task 1 `LibraryLocaleDependencies.currentLocaleOverride`）→ `SettingsScaffold.currentLocaleOverride`（Task 2）→ `AdaptiveShellScaffold.localeDependencies.currentLocaleOverride`（Task 3 透傳）→ `_ElinkBookAppState._localeOverride`（Task 4，Issue 0 已定義）全程一致；`ValueChanged<AppLocale?>?`（callback 簽章）同理全程一致。`_LocaleChoice`（Task 2 私有包裝型別）僅存在於 `settings_scaffold.dart` 內部，不外洩至其他檔案，不影響跨 Task 型別一致性。
- **未使用 placeholder**：所有 Step 皆含可直接執行的完整程式碼／指令；Task 2 Step 7 的「33 處遷移」與 Task 3 Step 5 的「7 處遷移」因數量較大改用「機械式轉換規則＋逐一列出行號或逐一列出實際程式碼」的方式呈現（Task 3 因只有 7 處、且彼此參數差異較大，逐一列出完整程式碼；Task 2 因 33 處皆為單純 `home: SettingsScaffold(...)` 同構寫法，列出轉換規則＋完整行號清單，不逐一複製貼上 33 段幾乎相同的程式碼），規則本身無歧義、可直接執行，不是「依實際情況調整」之類的空話。
- **陷阱提醒沿用**：`plan-issue-0.md` Task 1 事後補記的「語言選單須走 `AppLocale.values`（3 個成員），不可迭代 `AppLocalizations.supportedLocales`（4 個項目，多一個裸 `zh`）」——本計畫 Task 2 的 `_LanguagePickerSheet` 直接寫死 4 個 `RadioListTile`（`null`／`AppLocale.zhTW`／`AppLocale.zhCN`／`AppLocale.en`），未迭代 `AppLocalizations.supportedLocales`，已避開此陷阱。

**2026-09-21 `/superpowers:receiving-code-review` 審查（`reviews/review-plan-issue-1.md`，結論 Changes Requested，0 Critical／3 Important／3 Minor）已完成修訂，6 項全數查證屬實**：I-1（`RadioListTile.groupValue`/`onChanged` 已於 Flutter 3.32 棄用——已對照本機安裝的 Flutter SDK 原始碼 `radio_list_tile.dart` 確認兩者建構參數皆標記 `@Deprecated`，且專案已有 `reading_defaults_screen.dart`／commit `5fa3f5bb` 的 `RadioGroup<T>` 包裹慣例先例）——Task 2 Step 5g 的 `_LanguagePickerSheet` 改為 `RadioGroup<AppLocale?>` 包裹 4 個只宣告 `value` 的 `RadioListTile`，Tech Stack 段落同步修正措辭；Step 3 選中狀態斷言改讀外層 `RadioGroup.groupValue`。I-2（Task 3 Step 1 新增測試誤用裸 `MaterialApp(theme: resolveThemeData(...), home: ...)`，導致 Step 4「新增測試 PASS」預期在 `SettingsScaffold.build()` 已強制要求 `AppLocalizations` 後不可能成立——已重新執行 `flutter test test/screens/adaptive_shell_scaffold_test.dart` 確認現況為 `9 passed, 2 failed`，證實裸 `MaterialApp` 測試確實會撞上 `Null check operator`）——Step 1 改為直接以 `pumpLocalizedWidget()` 撰寫，Step 5 移除自相矛盾的「Step 1 測試等同尚未遷移、一併改寫」段落。I-3（Issue 1 單元測試要求「4 個選項分別點選」，原計畫僅點選正體中文／跟隨系統，簡體中文／English 兩個選項與 `currentLocaleOverride == null` 時的選取狀態完全未覆蓋——已對照 `issues.md` 原文確認要求屬實）——Task 2 Step 3 新增 2 個測試補齊缺口，新增測試總數由 6 個增至 8 個，Task 2 各處「6 個測試」計數同步修正為「8 個」。M-1（Task 3 Step 6 宣稱「PASS，既有 10 個 `testWidgets`，零回歸」，但本機重跑 `adaptive_shell_scaffold_test.dart` 實測為 `9 passed, 2 failed`——`LateInitializationError: Field '_batchActions@...' has already been initialized.` 與 `'_dependents.isEmpty': is not true.`，與 `review-issue-0.md` 記錄的既知瑕疵逐字相符，且既有 `testWidgets` 實際為 11 個而非 10 個）——Step 6 預期結果改為「新增測試 PASS；整檔呈現 `10 passed, 2 failed`」並註明兩則既知失敗與其錯誤訊息。M-2（`_LanguagePickerSheet` 點擊已選中語言不會觸發 `onChanged`、Sheet 不會自動關閉，屬 Radio 原生行為而非缺陷）——已在 `_LanguagePickerSheet` 程式碼補上說明註解。M-3（Task 3 Step 5 的 unused import 移除指引應直接點名）——已明確指出移除 `import 'package:elinkbook/theme/app_theme_data.dart';`，不再要求先跑 `flutter analyze` 才能判斷。本輪修訂全數為測試正確性與程式碼規範對齊補強，未變動任何既有架構決策（`LibraryLocaleDependencies` 攤平傳遞／`_LocaleChoice` 雙重 null 語意包裝／`AppLocale.values` 避開 4 語言陷阱等核心設計維持不變）。
