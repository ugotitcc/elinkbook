# Epic 45 Issue 0：依賴引進＋核心型別骨架＋`MaterialApp` 接線 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 `epic-45-interface-i18n`（多語系介面，FR-49）建立 i18n 基礎設施——`flutter_localizations`/`intl` 依賴、ARB 骨架、`AppLocale`/`AppLocalePreferences` 核心型別、`MaterialApp` 語言接線、測試包裝器 `pumpLocalizedWidget()`——且不改變任何使用者可見行為。

**Architecture:** 純 Dart 核心型別（`AppLocale`/`resolveSupportedLocale()`/`resolveMaterialAppLocale()`/`AppLocalePreferences`）與既有 `AppTheme`/`AppThemePreferences` 對稱設計；`ElinkBookApp` 新增 nullable 建構參數承接語言覆寫，比照既有 `initialTheme`/`initialEinkMode` 的「`main()` 先讀、建構子注入」模式；共用元件 `EBSheetShell` 的關閉按鈕 tooltip 改為「有 `AppLocalizations` 就用、沒有就退回既有中文字面值」的 null-safe 寫法，避免立即強制遷移它在 Issue 3/4 的既有呼叫端測試檔。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5（已安裝版本）、`flutter_localizations`（SDK 內建）、`intl`（隨 `flutter_localizations` 遞移解析）、`flutter gen-l10n`（ARB → `AppLocalizations`，`--synthetic-package` 在此版本已不存在，見下方 Global Constraints）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§1-3、§8，Architecting 產出，已通過審查修訂）；工單定義見 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 0」。

## Global Constraints

- **不手動釘 `intl` 版本**——交給 `flutter pub get` 依 `flutter_localizations` 遞移解析（`spec.md` §1.1）。
- **`l10n.yaml` 顯式宣告 `output-dir: lib/l10n`**（`spec.md` §1.2；本機已查證 Flutter 3.41.9 的 `--synthetic-package` 旗標已「cannot be enabled」，此設定是明確化寫法而非修復實際問題）。
- **`template-arb-file: app_zh_TW.arb`**（正體中文為權威來源，比照 `CLAUDE.md` 全域規則）。
- **ARB key 命名一律小駝峰**，計數相關字串一律用 ICU `plural` 語法（`spec.md` §1.3；本 Issue 尚未新增任何計數字串，此為後續 Issue 的約束，先在此記錄不違反）。
- **`resolveSupportedLocale()` 必須先比對 `languageCode`**，再依中文語境下的 `script`/`country` 判斷繁簡（`spec.md` §2.2，修復 `en_SG`/`en_HK`/`en_TW` 誤判為中文的既有審查發現）。
- **`AppLocalePreferences` 儲存值為 `AppLocale` enum 成員名稱**（`zhTW`/`zhCN`/`en`），非 BCP-47 格式（`spec.md` §2.3）。
- **`ElinkBookApp` 新增建構參數必須是可選的**（預設 `null`），既有測試套件（`elinkbook_app_wiring_test.dart`、`test/theme/theme_test.dart`、`app_lifecycle_sync_test.dart` 等）大量直接建構 `ElinkBookApp(...)` 且不會傳新參數，宣告為必填會導致既有測試編譯失敗（`spec.md`/`issues.md` M-1）。
- **本 Issue 完成後，App 實際外觀與既有行為必須零差異**——尚未有任何既有畫面改用 `AppLocalizations` 顯示字串（`issues.md` Issue 0 驗收標準）。
- **提交前 `flutter analyze` 必須乾淨（"No issues found!"）、`flutter test`（本 Issue 觸及的測試檔）必須全數通過**（`CLAUDE.md`/`AGENTS.md` 既有硬性門檻）。
- 所有新增檔案的中文說明/註解一律使用正體中文（`CLAUDE.md` 全域規則）。

所有指令皆在 `app/` 目錄下執行（`cd /c/Users/fycdc/AI/elinkBook/app`）。

---

### Task 1: 依賴引進與 l10n 基礎設施（`pubspec.yaml`／`l10n.yaml`／ARB 骨架）

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/l10n.yaml`
- Create: `app/lib/l10n/app_zh_TW.arb`
- Create: `app/lib/l10n/app_zh_CN.arb`
- Create: `app/lib/l10n/app_en.arb`
- Create: `app/lib/l10n/app_zh.arb`（`/superpowers:requesting-code-review` `review-issue-0.md` Important #1 事後補記，見下方 Step 5 之後的附註）
- Test: `app/test/l10n/app_localizations_generated_test.dart`

**Interfaces:**
- Produces: 產生的 `AppLocalizations` 類別（含頂層同步函式 `lookupAppLocalizations(Locale)`）＋ `groupUncategorized` 字串 key，供 Task 2-6 與後續所有 Issue 使用。

- [ ] **Step 1: 寫失敗測試（此階段連編譯都會失敗，因為 `AppLocalizations` 尚不存在）**

建立 `app/test/l10n/app_localizations_generated_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  test('三語言 ARB 皆能正確產生 groupUncategorized 字串', () {
    expect(
      lookupAppLocalizations(const Locale('zh', 'TW')).groupUncategorized,
      '未分類',
    );
    expect(
      lookupAppLocalizations(const Locale('zh', 'CN')).groupUncategorized,
      '未分类',
    );
    expect(
      lookupAppLocalizations(const Locale('en')).groupUncategorized,
      'Uncategorized',
    );
  });

  test('三語言 ARB 皆能正確產生 close 字串（`/receiving-code-review` M-4 修正）', () {
    expect(lookupAppLocalizations(const Locale('zh', 'TW')).close, '關閉');
    expect(lookupAppLocalizations(const Locale('zh', 'CN')).close, '关闭');
    expect(lookupAppLocalizations(const Locale('en')).close, 'Close');
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/l10n/app_localizations_generated_test.dart`
Expected: 編譯錯誤（`Target of URI doesn't exist: 'package:elinkbook/l10n/app_localizations.dart'`），因為尚未新增依賴／設定／ARB。

- [ ] **Step 3: 新增依賴至 `pubspec.yaml`**

在 `dependencies:` 區塊新增（緊接既有 `cupertino_icons: ^1.0.8` 之後）：

```yaml
  # 多語系介面（epic-45-interface-i18n，FR-49）：Flutter 官方標準方案。
  flutter_localizations:
    sdk: flutter
  intl:
```

在既有 `flutter:` 區塊（`uses-material-design: true` 那一段）新增一行：

```yaml
flutter:
  uses-material-design: true
  generate: true
```

- [ ] **Step 4: 新增 `app/l10n.yaml`**

```yaml
arb-dir: lib/l10n
template-arb-file: app_zh_TW.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/l10n
preferred-supported-locales: ["zh_TW"]
```

- [ ] **Step 5: 新增三份 ARB 骨架**

`app/lib/l10n/app_zh_TW.arb`：

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
  }
}
```

`app/lib/l10n/app_zh_CN.arb`：

```json
{
  "@@locale": "zh_CN",
  "groupUncategorized": "未分类",
  "close": "关闭"
}
```

`app/lib/l10n/app_en.arb`：

```json
{
  "@@locale": "en",
  "groupUncategorized": "Uncategorized",
  "close": "Close"
}
```

**必要的第 4 份 ARB（`/superpowers:requesting-code-review` `review-issue-0.md` Important #1 事後補記，非計畫撰寫當下已知，Task 1 實作時才發現）**：`app/lib/l10n/app_zh.arb`（內容與 `app_zh_TW.arb` 一致：`未分類`／`關閉`），無 `@` 描述區塊：

```json
{
  "@@locale": "zh",
  "groupUncategorized": "未分類",
  "close": "關閉"
}
```

**原因**：Flutter 3.41.9 的 `flutter gen-l10n` 在同時存在 `zh_TW`／`zh_CN` 兩個帶 country code 的變體時，強制要求一個不帶 country code 的 `zh` 基礎 ARB 檔案作為 fallback，否則會報錯：
```
Arb file for a fallback, zh, does not exist, even though
the following locale(s) exist: [zh_CN, zh_TW].
```
`review-issue-0.md` 審查時已實測移除此檔案會導致 `gen-l10n` 直接失敗，確認這是工具限制而非失誤。**已知影響（記錄於此，供 Issue 1 實作者留意）**：`AppLocalizations.supportedLocales` 因此含 4 個項目（多一個裸 `zh`），本 App 自身的 locale 決策路徑（`_localeOverride?.locale`／`resolveMaterialAppLocale()`）永遠不會選出這個裸 `Locale('zh')`，目前不構成執行期臭蟲；但 Issue 1 的語言選擇 UI 若要列舉支援語言產生選單，**一律走 `AppLocale.values`（3 個成員），不要直接迭代 `AppLocalizations.supportedLocales`（4 個項目，多一個裸 `zh` 會讓選單多出不該有的選項）**。

- [ ] **Step 6: 安裝依賴並產生 `AppLocalizations`**

Run:
```bash
flutter pub get
flutter gen-l10n
```
Expected: 兩個指令皆無錯誤；`app/lib/l10n/app_localizations.dart`（與各語言子檔）已產生。

- [ ] **Step 7: 執行測試確認通過**

Run: `flutter test test/l10n/app_localizations_generated_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 8: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"（產生的 `app_localizations.dart` 屬於 generated code，若 analyzer 對其報錯需檢查 `l10n.yaml` 設定，不應手動編輯產生檔）。若 analyzer 對 `lib/l10n/app_localizations*.dart` 報出風格類 lint（實務上 gen-l10n 產生碼通常乾淨，若真的發生），在 `analysis_options.yaml` 的 `analyzer.exclude` 清單新增 `lib/l10n/app_localizations*.dart`（比照既有 `patches/**` 排除寫法），而非手動編輯產生檔本身。

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock l10n.yaml lib/l10n/ test/l10n/app_localizations_generated_test.dart
git commit -m "feat(epic-45): 引進 flutter_localizations/intl 依賴與 ARB 骨架"
```

---

### Task 2: `AppLocale` enum ＋ `resolveSupportedLocale()` ＋ `resolveMaterialAppLocale()`

**Files:**
- Create: `app/lib/l10n/app_locale.dart`
- Test: `app/test/l10n/app_locale_test.dart`

**Interfaces:**
- Consumes: 無（純 Dart，僅依賴 `package:flutter/widgets.dart` 的 `Locale` 型別）。
- Produces: `enum AppLocale { zhTW, zhCN, en }`（含 `Locale get locale`）；`AppLocale resolveSupportedLocale(Locale deviceLocale)`；`Locale resolveMaterialAppLocale(List<Locale>? deviceLocales)`——供 Task 3（儲存值對應）與 Task 5（`MaterialApp.localeListResolutionCallback`）使用。

- [ ] **Step 1: 寫失敗測試——`resolveSupportedLocale()` 完整矩陣**

建立 `app/test/l10n/app_locale_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_locale.dart';

void main() {
  group('AppLocale.locale', () {
    test('三個成員各自對應正確的 Locale', () {
      expect(AppLocale.zhTW.locale, const Locale('zh', 'TW'));
      expect(AppLocale.zhCN.locale, const Locale('zh', 'CN'));
      expect(AppLocale.en.locale, const Locale('en'));
    });
  });

  group('resolveSupportedLocale', () {
    test('zh_TW 直接對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'TW')), AppLocale.zhTW);
    });

    test('zh_HK／zh_MO 對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'HK')), AppLocale.zhTW);
      expect(resolveSupportedLocale(const Locale('zh', 'MO')), AppLocale.zhTW);
    });

    test('zh_Hant（無 country）對應正體中文', () {
      expect(
        resolveSupportedLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        AppLocale.zhTW,
      );
    });

    test('純 zh（無 script/country）對應正體中文', () {
      expect(resolveSupportedLocale(const Locale('zh')), AppLocale.zhTW);
    });

    test('zh_CN 對應簡體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'CN')), AppLocale.zhCN);
    });

    test('zh_SG 對應簡體中文', () {
      expect(resolveSupportedLocale(const Locale('zh', 'SG')), AppLocale.zhCN);
    });

    test('zh_Hans（無 country）對應簡體中文', () {
      expect(
        resolveSupportedLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')),
        AppLocale.zhCN,
      );
    });

    test('en／en_US 對應英文', () {
      expect(resolveSupportedLocale(const Locale('en')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'US')), AppLocale.en);
    });

    test('迴歸測試：en_SG／en_HK／en_TW 不得被地區碼誤判為中文（審查 C-1 修正）', () {
      expect(resolveSupportedLocale(const Locale('en', 'SG')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'HK')), AppLocale.en);
      expect(resolveSupportedLocale(const Locale('en', 'TW')), AppLocale.en);
    });

    test('未支援語言（例如法語）fallback 正體中文', () {
      expect(resolveSupportedLocale(const Locale('fr', 'FR')), AppLocale.zhTW);
    });
  });

  group('resolveMaterialAppLocale', () {
    test('清單第一個支援語言（zh 或 en）即採用', () {
      expect(
        resolveMaterialAppLocale(const [Locale('en', 'US')]),
        const Locale('en'),
      );
    });

    test('清單第一項不支援、第二項支援時，改採第二項（不可只看 firstOrNull）', () {
      expect(
        resolveMaterialAppLocale(const [Locale('fr', 'FR'), Locale('en', 'US')]),
        const Locale('en'),
      );
    });

    test('清單為 null 或全部不支援時 fallback 正體中文', () {
      expect(resolveMaterialAppLocale(null), const Locale('zh', 'TW'));
      expect(
        resolveMaterialAppLocale(const [Locale('fr', 'FR'), Locale('de', 'DE')]),
        const Locale('zh', 'TW'),
      );
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/l10n/app_locale_test.dart`
Expected: 編譯錯誤（`app_locale.dart` 尚不存在）。

- [ ] **Step 3: 寫最小實作**

建立 `app/lib/l10n/app_locale.dart`：

```dart
import 'package:flutter/widgets.dart';

/// 多語系介面（epic-45-interface-i18n，FR-49）支援的三個語系。
enum AppLocale {
  zhTW,
  zhCN,
  en;

  Locale get locale => switch (this) {
        AppLocale.zhTW => const Locale('zh', 'TW'),
        AppLocale.zhCN => const Locale('zh', 'CN'),
        AppLocale.en => const Locale('en'),
      };
}

/// 依「Locale 解析矩陣」把裝置回報的任意 [Locale] 對應到本 App 支援的三個
/// 語系之一。純函式，不依賴 BuildContext，供 [resolveMaterialAppLocale] 與
/// 單元測試共用。
///
/// 必須先比對 [Locale.languageCode]，再依中文語境下的 script/country 判斷
/// 繁簡——先比對 country 會導致 en_SG／en_HK／en_TW（港澳星台地區偏好英文
/// 介面的使用者，常見情境）被地區代碼誤判為中文。
AppLocale resolveSupportedLocale(Locale deviceLocale) {
  final language = deviceLocale.languageCode;
  final script = deviceLocale.scriptCode;
  final country = deviceLocale.countryCode;

  if (language == 'zh') {
    if (script == 'Hans' || const {'CN', 'SG'}.contains(country)) {
      return AppLocale.zhCN;
    }
    // 涵蓋 script == 'Hant'、country 屬於 {TW, HK, MO}，或純 'zh' 無
    // script/country 資訊的情況，一律預設正體中文。
    return AppLocale.zhTW;
  }
  if (language == 'en') return AppLocale.en;

  // 其餘所有非中文、非英語系，fallback 至正體中文。
  return AppLocale.zhTW;
}

/// 供 `MaterialApp.localeListResolutionCallback` 使用：依序走訪裝置的語言
/// 喜好清單，採用第一個語言碼落在本 App 實際支援範圍（zh／en）的項目；
/// 清單為 null 或全部不支援時才 fallback 正體中文。刻意不只取
/// `deviceLocales.firstOrNull`——那會讓「次要偏好為中文/英文、但首選是本
/// App 不支援語言」的使用者被直接 fallback 正體中文，忽視次要偏好。
Locale resolveMaterialAppLocale(List<Locale>? deviceLocales) {
  for (final locale in deviceLocales ?? const <Locale>[]) {
    if (locale.languageCode == 'zh' || locale.languageCode == 'en') {
      return resolveSupportedLocale(locale).locale;
    }
  }
  return AppLocale.zhTW.locale;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/l10n/app_locale_test.dart`
Expected: PASS（全部 test，含 `en_SG`/`en_HK`/`en_TW` 迴歸測試）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_locale.dart test/l10n/app_locale_test.dart
git commit -m "feat(epic-45): 新增 AppLocale/resolveSupportedLocale 純函式"
```

---

### Task 3: `AppLocalePreferences`

**Files:**
- Create: `app/lib/l10n/app_locale_preferences.dart`
- Test: `app/test/l10n/app_locale_preferences_test.dart`

**Interfaces:**
- Consumes: `AppLocale`（Task 2）、`package:shared_preferences/shared_preferences.dart`。
- Produces: `class AppLocalePreferences { Future<AppLocale?> loadLocaleOverride(); Future<void> saveLocaleOverride(AppLocale? locale); }`——供 Task 5（`main.dart`）使用。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/l10n/app_locale_preferences_test.dart`（比照既有 `test/theme/app_theme_preferences_test.dart` 慣例）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/app_locale_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過語言覆寫時，loadLocaleOverride 回傳 null（跟隨系統）', () async {
    final prefs = AppLocalePreferences();
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('saveLocaleOverride 寫入後，loadLocaleOverride 讀回相同的值', () async {
    final prefs = AppLocalePreferences();
    await prefs.saveLocaleOverride(AppLocale.en);
    expect(await prefs.loadLocaleOverride(), AppLocale.en);
  });

  test('saveLocaleOverride(null) 清除既有覆寫，之後回到跟隨系統', () async {
    final prefs = AppLocalePreferences();
    await prefs.saveLocaleOverride(AppLocale.zhCN);
    expect(await prefs.loadLocaleOverride(), AppLocale.zhCN);

    await prefs.saveLocaleOverride(null);
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('已儲存的字串無法對應到任何列舉值時，loadLocaleOverride 安全回退為 null', () async {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'not_a_real_enum_value',
    });
    final prefs = AppLocalePreferences();
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('三個 AppLocale 成員皆能正確 round-trip', () async {
    final prefs = AppLocalePreferences();
    for (final locale in AppLocale.values) {
      await prefs.saveLocaleOverride(locale);
      expect(await prefs.loadLocaleOverride(), locale);
    }
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/l10n/app_locale_preferences_test.dart`
Expected: 編譯錯誤（`app_locale_preferences.dart` 尚不存在）。

- [ ] **Step 3: 寫最小實作**

建立 `app/lib/l10n/app_locale_preferences.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';

/// 介面語言偏好的持久化（FR-49，`docs/adr/0033-interface-locale-device-local-not-synced.md`：
/// 裝置本地儲存，不跨裝置同步）。比照 `AppThemePreferences` 既有模式，直接
/// 使用 `shared_preferences` 官方支援的測試方式驅動測試。
class AppLocalePreferences {
  static const _localeKey = 'app_locale'; // 值域：'zhTW' / 'zhCN' / 'en'（AppLocale enum 成員名稱，非 BCP-47 格式）；鍵不存在＝跟隨系統

  /// 回傳 `null` 代表「跟隨系統」。
  Future<AppLocale?> loadLocaleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localeKey);
    if (raw == null) return null;
    try {
      return AppLocale.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為跟隨系統。
      return null;
    }
  }

  /// 傳入 `null` 清除既有覆寫（回到跟隨系統）。
  Future<void> saveLocaleOverride(AppLocale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.name);
    }
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/l10n/app_locale_preferences_test.dart`
Expected: PASS（全部 test）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_locale_preferences.dart test/l10n/app_locale_preferences_test.dart
git commit -m "feat(epic-45): 新增 AppLocalePreferences 偏好持久化"
```

---

### Task 4: `pumpLocalizedWidget()` 測試包裝器

**Files:**
- Create: `app/test/support/pump_localized_widget.dart`
- Test: `app/test/support/pump_localized_widget_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations`（Task 1）、`AppTheme`/`resolveThemeData()`（既有 `app/lib/theme/app_theme.dart`／`app_theme_data.dart`）。
- Produces: `Future<void> pumpLocalizedWidget(WidgetTester tester, Widget home, {Locale locale, AppTheme theme, bool isEinkMode, GlobalKey<NavigatorState>? navigatorKey, List<NavigatorObserver> navigatorObservers})`——供 Task 6 與後續全部 Issue 的測試遷移使用。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/support/pump_localized_widget_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

import 'pump_localized_widget.dart';

void main() {
  testWidgets('預設參數：成功 pump 一個簡單 Text widget 且不拋例外', (tester) async {
    await pumpLocalizedWidget(tester, const Text('hello'));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('預設 locale 為正體中文', (tester) async {
    late Locale resolvedLocale;
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) {
          resolvedLocale = Localizations.localeOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(resolvedLocale, const Locale('zh', 'TW'));
  });

  testWidgets('可指定其他 locale，且 AppLocalizations.of(context) 正確可用', (tester) async {
    late AppLocalizations l10n;
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context)!;
          return const SizedBox.shrink();
        },
      ),
      locale: const Locale('en'),
    );
    expect(l10n.groupUncategorized, 'Uncategorized');
  });

  testWidgets(
      '可傳入 navigatorObservers 並正確透傳給 MaterialApp（`/receiving-code-review` I-2 修正）',
      (tester) async {
    final observer = NavigatorObserver();
    await pumpLocalizedWidget(
      tester,
      const Text('hello'),
      navigatorObservers: [observer],
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.navigatorObservers, contains(observer));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/support/pump_localized_widget_test.dart`
Expected: 編譯錯誤（`pump_localized_widget.dart` 尚不存在）。

- [ ] **Step 3: 寫最小實作**

建立 `app/test/support/pump_localized_widget.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

/// 統一測試包裝器（epic-45-interface-i18n Issue 0，`spec.md` §8）：既有
/// 測試檔案大量各自建構裸 `MaterialApp(...)`，一旦畫面改用
/// `AppLocalizations.of(context)!` 就會因缺少 `localizationsDelegates`
/// 觸發 `Null check operator` 崩潰。本函式強制注入
/// `AppLocalizations.localizationsDelegates`/`supportedLocales`，並把
/// `locale` 預設釘定為正體中文，讓既有中文 `find.text()` 斷言在遷移期間
/// 維持通過。`theme`/`isEinkMode` 直接收 `AppTheme`/`bool`（而非裸
/// `ThemeData?`），內部呼叫既有 `resolveThemeData()`，比照既有測試檔案
/// `MaterialApp(theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false), ...)`
/// 這種既定寫法收窄參數型別。
Future<void> pumpLocalizedWidget(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: navigatorObservers,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
    home: home,
  ));
}
```

**（`/receiving-code-review` I-2 修正）**：新增 `navigatorObservers` 具名參數（預設空清單，比照 `MaterialApp` 自身預設值），供後續 Issue 3-6/9 遷移既有測試時（既有多處測試以裸 `MaterialApp(navigatorObservers: [...])` 驗證 Route 轉場行為，例如 `eb_sheet_shell_test.dart` 的 `_RecordingNavigatorObserver`）能直接透過本包裝器遷移，不需要因缺少這個參數而保留裸 `MaterialApp` 或另寫平行包裝器。

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/support/pump_localized_widget_test.dart`
Expected: PASS（全部 test）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add test/support/pump_localized_widget.dart test/support/pump_localized_widget_test.dart
git commit -m "feat(epic-45): 新增 pumpLocalizedWidget 測試包裝器"
```

---

### Task 5: `MaterialApp` 接線（`app/lib/main.dart`）

**Files:**
- Modify: `app/lib/main.dart`
- Test: `app/test/l10n/elinkbook_app_locale_test.dart`

**Interfaces:**
- Consumes: `AppLocale`/`resolveMaterialAppLocale()`（Task 2）、`AppLocalePreferences`（Task 3）、`AppLocalizations`（Task 1）。
- Produces: `ElinkBookApp` 新增可選建構參數 `AppLocale? initialLocaleOverride`／`AppLocalePreferences? localePreferences`；`_ElinkBookAppState._localeOverride`（供 Issue 1 的 `_handleLocaleChanged` 使用，本 Issue 尚不新增該方法）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/l10n/elinkbook_app_locale_test.dart`（比照既有 `test/elinkbook_app_wiring_test.dart` 的最小建構模式）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('不傳 initialLocaleOverride／localePreferences 時仍可正常建構（既有相容性）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('MaterialApp 正確接上 localizationsDelegates／supportedLocales',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      materialApp.localizationsDelegates,
      containsAll(AppLocalizations.localizationsDelegates),
    );
    expect(
      materialApp.supportedLocales,
      containsAll(AppLocalizations.supportedLocales),
    );
  });

  testWidgets('initialLocaleOverride 非 null 時，MaterialApp.locale 直接採用該語言',
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

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('en'));
  });

  testWidgets('initialLocaleOverride 為 null 時，MaterialApp.locale 亦為 null（交給 localeListResolutionCallback 動態解析）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, isNull);
  });

  testWidgets(
      'localeListResolutionCallback 正確接線至 resolveMaterialAppLocale（`/receiving-code-review` I-1 修正）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final callback = materialApp.localeListResolutionCallback;
    expect(callback, isNotNull);

    // 直接呼叫 MaterialApp 實際持有的那個 callback 實例——若 main.dart
    // 誤接了別的函式或簽章寫錯，這裡會直接暴露，而不只是驗證
    // resolveMaterialAppLocale() 本身正確（Task 2 已覆蓋純函式邏輯，這裡
    // 驗證的是「main.dart 真的把它接上去了」這條接線本身）。
    final resolved = callback!(
      const [Locale('fr', 'FR'), Locale('en', 'US')],
      AppLocalizations.supportedLocales,
    );
    expect(resolved, const Locale('en'));
  });

  testWidgets(
      'AppLocalizations.of(context) 在 Widget 樹內可正常取得而不拋例外（`/receiving-code-review` I-1 修正）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldContext =
        tester.element(find.byType(AdaptiveShellScaffold));
    expect(AppLocalizations.of(scaffoldContext), isNotNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/l10n/elinkbook_app_locale_test.dart`
Expected: 編譯錯誤（`ElinkBookApp` 尚無 `initialLocaleOverride` 參數）。

- [ ] **Step 3: 修改 `app/lib/main.dart`**

在檔案頂部 import 區塊新增（比照既有 `import 'theme/app_theme_preferences.dart';` 風格，置於同一組排序中）：

```dart
import 'l10n/app_locale.dart';
import 'l10n/app_locale_preferences.dart';
import 'l10n/app_localizations.dart';
```

修改 `main()` 函式，在既有 `final themePreferences = AppThemePreferences();` 那組讀取邏輯旁新增（緊接其後）：

```dart
  final localePreferences = AppLocalePreferences();
  final initialLocaleOverride = await localePreferences.loadLocaleOverride();
```

在 `runApp(ElinkBookApp(...))` 呼叫中新增兩個具名參數（緊接既有 `themePreferences: themePreferences,` 之後）：

```dart
      localePreferences: localePreferences,
      initialLocaleOverride: initialLocaleOverride,
```

修改 `ElinkBookApp` 類別，新增欄位（緊接既有 `final AppThemePreferences themePreferences;` 之後）：

```dart
  final AppLocalePreferences localePreferences;
  final AppLocale? initialLocaleOverride;
```

修改 `ElinkBookApp` 建構子，新增具名參數（緊接既有 `AppThemePreferences? themePreferences,` 之後，同樣在初始化列表用 `??` 具現化）：

```dart
    this.initialLocaleOverride,
    AppLocalePreferences? localePreferences,
```

並把既有初始化列表：

```dart
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

改為：

```dart
  })  : themePreferences = themePreferences ?? AppThemePreferences(),
        localePreferences = localePreferences ?? AppLocalePreferences();
```

修改 `_ElinkBookAppState`，在既有 `late AppTheme _theme;` / `late bool _isEinkMode;` 旁新增欄位：

```dart
  AppLocale? _localeOverride;
```

**（`/receiving-code-review` M-1 修正）**：不加 `late`——`AppLocale?` 是 nullable 型別，預設初值本就是 `null`，`late` 只適用於「非 nullable、但需要延後賦值」的情境（如 `_theme`/`_isEinkMode` 這兩個 non-nullable 欄位），加在 nullable 型別上沒有實質效果，反而若不慎在賦值前讀取會誤觸 `LateInitializationError`（雖然 `initState()` 會立即賦值，實務上不會發生，但這個宣告寫法本身是不必要的反模式）。

在 `initState()` 內，緊接既有 `_theme = widget.initialTheme;` / `_isEinkMode = widget.initialEinkMode;` 之後新增：

```dart
    _localeOverride = widget.initialLocaleOverride;
```

修改 `build()` 內的 `MaterialApp(...)` 建構，新增四個具名參數（緊接既有 `theme: themeData,` 之後）：

```dart
      locale: _localeOverride?.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (deviceLocales, supportedLocales) =>
          resolveMaterialAppLocale(deviceLocales),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/l10n/elinkbook_app_locale_test.dart`
Expected: PASS（全部 6 個 test）。

- [ ] **Step 5: 既有 `ElinkBookApp` 相關測試零回歸**

Run:
```bash
flutter test test/elinkbook_app_wiring_test.dart
flutter test test/theme/theme_test.dart
flutter test test/app_lifecycle_sync_test.dart
```
Expected: 三者皆 PASS，無編譯錯誤、無既有斷言失敗。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart test/l10n/elinkbook_app_locale_test.dart
git commit -m "feat(epic-45): MaterialApp 接上 locale/localizationsDelegates"
```

---

### Task 6: `EBSheetShell` 關閉按鈕 tooltip 在地化（null-safe）

**Files:**
- Modify: `app/lib/screens/widgets/eb_sheet_shell.dart`
- Modify: `app/test/screens/widgets/eb_sheet_shell_test.dart`（新增測試，既有 4 個 test 原樣保留不動）

**Interfaces:**
- Consumes: `AppLocalizations`（Task 1）、`pumpLocalizedWidget()`（Task 4）。
- Produces: 無新公開介面——`EBSheetShell` 的公開建構參數與 `show()` 簽章皆不變，僅內部 `tooltip` 字串來源改變。

**背景（設計取捨，供實作者理解為何選擇 null-safe 寫法而非強制遷移）：** `EBSheetShell` 被 5 個檔案引用，橫跨 Issue 3（書架模組）與 Issue 4（閱讀器模組）尚未執行的字串抽取範圍。若把 `tooltip` 改為 `AppLocalizations.of(context)!.close`（無 `?`），任何仍用裸 `MaterialApp(...)`（無 `localizationsDelegates`）pump 這個元件的既有測試會立即因 `Null check operator used on a null value` 崩潰——而那些呼叫端測試檔案的遷移是 Issue 3/4 的範圍，不該提前綁進 Issue 0。改用 `AppLocalizations.of(context)?.close ?? '關閉'`：有 delegates（新測試、正式 App）時正確在地化；沒有 delegates（既有未遷移測試）時優雅回退既有中文字面值，兩邊都不崩潰。

- [ ] **Step 1: 寫失敗測試——新增三語言在地化驗證（既有 4 個 test 不動）**

在 `app/test/screens/widgets/eb_sheet_shell_test.dart` 檔案開頭新增 import：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';

import '../../support/pump_localized_widget.dart';
```

在既有 `void main() {` 開頭（既有 4 個 `testWidgets` 之前）新增：

```dart
  testWidgets('AppLocalizations 存在時，關閉按鈕 tooltip 依三語言正確在地化',
      (tester) async {
    for (final entry in {
      const Locale('zh', 'TW'): '關閉',
      const Locale('zh', 'CN'): '关闭',
      const Locale('en'): 'Close',
    }.entries) {
      await pumpLocalizedWidget(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EBSheetShell.show<void>(
              context,
              title: '標題',
              builder: (context) => const Text('內容'),
            ),
            child: const Text('open'),
          ),
        ),
        locale: entry.key,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('eb_sheet_shell_close_button')),
      );
      expect(iconButton.tooltip, entry.value);

      // （`/receiving-code-review` M-2 修正）額外驗證三語言下關閉按鈕本身
      // 仍可正常點擊關閉，不只是 tooltip 文字正確。
      await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
      await tester.pumpAndSettle();
      expect(find.text('內容'), findsNothing);
    }
  });

  testWidgets('AppLocalizations 不存在（裸 MaterialApp）時，tooltip 回退既有中文字面值',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EBSheetShell.show<void>(
              context,
              title: '標題',
              builder: (context) => const Text('內容'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(
      find.byKey(const Key('eb_sheet_shell_close_button')),
    );
    expect(iconButton.tooltip, '關閉');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_sheet_shell_test.dart`
Expected: 新增的 2 個 test FAIL（目前 `tooltip` 恆為 `'關閉'`，`en`/`zh_CN` 情境會斷言失敗）；既有 4 個 test 仍 PASS。

- [ ] **Step 3: 修改 `app/lib/screens/widgets/eb_sheet_shell.dart`**

新增 import（緊接既有 `import 'package:flutter/material.dart';` 之後）：

```dart
import '../../l10n/app_localizations.dart';
```

把 `build()` 內的：

```dart
                    tooltip: '關閉',
```

改為：

```dart
                    tooltip: AppLocalizations.of(context)?.close ?? '關閉',
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_sheet_shell_test.dart`
Expected: PASS（全部 6 個 test，含既有 4 個原樣不動的 test 與新增的 2 個）。

- [ ] **Step 5: 既有跨模組呼叫端測試零回歸（尚未遷移至 `pumpLocalizedWidget()`，驗證 null-safe fallback 確實生效）**

Run:
```bash
flutter test test/screens/library_screen_test.dart
flutter test test/screens/library_search_screen_test.dart
flutter test test/screens/book_action_sheet_test.dart
flutter test test/screens/notes_bottom_sheet_test.dart
```
Expected: 四者皆 PASS，零回歸（這些檔案本身在本 Issue 不做任何修改，僅驗證 `eb_sheet_shell.dart` 的變更未波及它們）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/screens/widgets/eb_sheet_shell.dart test/screens/widgets/eb_sheet_shell_test.dart
git commit -m "feat(epic-45): EBSheetShell 關閉按鈕 tooltip null-safe 在地化"
```

---

### Task 7: 完整驗收

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1: 完整 `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: 完整 `flutter test`**

Run: `flutter test`
Expected: 全數通過（比照本專案既有慣例，若有既存、與本 Issue 無關的既知不穩定測試，比對是否為 base commit 既存缺陷而非本 Issue 引入的回歸）。

- [ ] **Step 3: 手動驗證 App 外觀零差異**

Run:
```bash
flutter run
```
Expected: App 正常啟動，書架/設定/閱讀器等既有畫面外觀與行為與 Issue 0 之前完全一致（因為尚無任何既有畫面改用 `AppLocalizations`）；「設定→外觀」尚未出現「語言」項目（那是 Issue 1 的範圍）。

- [ ] **Step 4: 更新 `docs/epics/epic-45-interface-i18n/issues.md` 與 `epic.md`**

在 `issues.md` 的「Issue 0」標題旁補上 `**Status:** completed`，並在 `epic.md` 新增一段開發記錄（比照既有其他 Issue 完成時的記錄慣例），記錄本 Issue 完成情況與下一步（認領 Issue 1／Issue 2）。

- [ ] **Step 5: Commit**

**（`/receiving-code-review` M-3 修正）**：本步驟修改的檔案在 `docs/`，位於 `app/` 上一層——沿用 Global Constraints「指令皆在 `app/` 目錄下執行」時，路徑須加 `../` 前綴，否則會觸發 Git `pathspec did not match any files` 錯誤：

```bash
git add ../docs/epics/epic-45-interface-i18n/issues.md ../docs/epics/epic-45-interface-i18n/epic.md
git commit -m "docs(epic-45): 標記 Issue 0 為 completed"
```

---

## Self-Review 摘要（撰寫計畫時的自我檢查紀錄）

- **Spec 覆蓋度**：`spec.md` §1（依賴/l10n.yaml/ARB）→ Task 1；§2.1-2.2（`AppLocale`/`resolveSupportedLocale`）→ Task 2；§2.3（`AppLocalePreferences`）→ Task 3；§3（`MaterialApp` 接線）→ Task 5；§8（`pumpLocalizedWidget`）→ Task 4；`issues.md` M-1（建構子可選參數）→ Task 5 Step 3；`issues.md` I-3（`EBSheetShell` 共用元件衝突）→ Task 6。§4-7、§9（`LibraryLocaleDependencies`／分類名稱契約／執行期例外／Markdown 匯出／稽核腳本）刻意不在本計畫範圍——分屬 Issue 1/2/7/8/10，`issues.md` 已明確排除於 Issue 0。
- **型別一致性**：`AppLocale`（Task 2）→ `AppLocalePreferences.loadLocaleOverride()`/`saveLocaleOverride()` 回傳/參數型別（Task 3）→ `ElinkBookApp.initialLocaleOverride`（Task 5）三處皆為 `AppLocale?`，命名一致；`resolveMaterialAppLocale()`（Task 2）與 `MaterialApp.localeListResolutionCallback` 簽章（`(List<Locale>?, Iterable<Locale>) => Locale?`）相容。
- **未使用 placeholder**：所有 Step 皆含可直接執行的完整程式碼／指令，無「TBD」「依實際情況調整」等字樣。

**2026-09-21 `/superpowers:receiving-code-review` 審查（`reviews/review-plan-issue-0.md`，結論 Changes Requested，0 Critical／2 Important／4 Minor）已完成修訂，6 項全數查證屬實**：I-1（`elinkbook_app_locale_test.dart` 缺少 `MaterialApp.localeListResolutionCallback` 實際接線驗證與 `AppLocalizations.of(context)` 有效性驗證——Task 2 只測了純函式本身，沒有測試證明 `main.dart` 真的把它接上去）——Task 5 新增兩個 test，直接呼叫 `materialApp.localeListResolutionCallback` 實例＋透過 `AdaptiveShellScaffold` 的 context 驗證 `AppLocalizations.of()` 可用。I-2（`pumpLocalizedWidget()` 缺 `navigatorObservers`，會阻礙後續 Issue 3-6/9 遷移既有仰賴 `NavigatorObserver` 的測試檔）——Task 4 新增該參數＋對應測試。M-1（nullable 型別加 `late` 屬反模式）——Task 5 移除。M-2（Task 6 測試迴圈補關閉驗證，額外覆蓋「三語言下關閉按鈕真的可點擊生效」而不只是 tooltip 文字）——Task 6 補上。M-3（Task 7 Step 5 在 `app/` 目錄下執行 `git add docs/...` 會因路徑不存在觸發 pathspec 錯誤）——修正為 `../docs/...`。M-4（Task 1 產生檔測試漏驗證 `close` key）——補上三語言斷言。本輪修訂全數為測試覆蓋率與程式碼正確性補強，未變動任何既有架構決策。

**2026-09-21 `/superpowers:requesting-code-review` 對實際落地程式碼（分支 `feat/epic-45-issue-0`，7 個 Task 皆已執行完成）的審查（`reviews/review-issue-0.md`，結論 Ready to merge: Yes，0 Critical／1 Important／2 Minor）已完成修訂**：Important（`app/lib/l10n/app_zh.arb` 是 Task 1 實作時才發現、`gen-l10n` 工具限制強制要求的必要第 4 份 ARB，但未同步反映回本計畫文件）——已補入 Task 1 的 Files 清單與 Step 5 之後的附註，並記錄「Issue 1 語言選單須走 `AppLocale.values`、不可直接迭代 `AppLocalizations.supportedLocales`」這個陷阱提醒。Minor #1（`pubspec.yaml` 誤刪與本次改動無關的既有註解）／Minor #2（`eb_sheet_shell_test.dart` 新增一個靠 `// ignore: unused_import` 壓下警告、實際上沒用到的 import）——皆已在分支上直接修正程式碼（非計畫文件），`flutter analyze` 確認乾淨、`eb_sheet_shell_test.dart` 全部 6 個 test 重跑確認通過。本輪修訂為分支程式碼的整潔性補強＋計畫文件與實作現況同步，未變動任何架構決策，本 Issue 原本「零使用者可見行為變動」的核心承諾不受影響。
