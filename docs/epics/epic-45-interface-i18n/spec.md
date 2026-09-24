# Epic 45 — 多語系介面：Spec

本檔案是 `epic-45-interface-i18n` 的唯一技術事實來源（Single Source of Truth），基於 `design.md` 的 Discovery 決策定義核心介面/型別。Scrum Master 階段拆 Issue 時以本檔案為準。

## 1. 新增依賴與專案設定

### 1.1 `pubspec.yaml`

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: <flutter_localizations 遞移相依鎖定的版本> # 不手動指定版本號，交給 flutter pub get 依 flutter_localizations 解析

flutter:
  generate: true
```

`intl` 版本必須跟隨 `flutter_localizations` 的遞移相依鎖定（`flutter pub get` 會自動解析出相容版本），不手動釘版本號——比照本專案既有「不釘死第三方套件版本」慣例（見 `epic-44-wifi-book-transfer` `epic.md` M-5 不採納紀錄）。

### 1.2 `l10n.yaml`（app 根目錄新檔案）

```yaml
arb-dir: lib/l10n
template-arb-file: app_zh_TW.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/l10n
preferred-supported-locales: ["zh_TW"]
```

- `template-arb-file` 定為 `app_zh_TW.arb`（正體中文），對齊本專案「正體中文為主要撰寫語言」的既有慣例（`CLAUDE.md` 全域規則）——所有字串 key／描述以此檔為權威來源，其餘語言檔跟隨其 key 集合翻譯。
- **`output-dir` 顯式宣告為 `lib/l10n`（`/receiving-code-review` I-2 修正，但修正其診斷理由）**：查核本專案實際安裝的 Flutter SDK（`flutter --version` 為 3.41.9／Dart 3.11.5），`flutter gen-l10n --help` 顯示 `--synthetic-package` 旗標已標示「DEPRECATED. This flag cannot be enabled and should be removed」，且 `--output-dir` 未指定時本來就預設與 `arb-dir` 相同目錄——也就是說這個版本**已無** synthetic package 模式，即使不寫 `output-dir` 也不會輸出到 `.dart_tool/flutter_gen/`。顯式寫出 `output-dir: lib/l10n` 純粹是明確化寫法（避免依賴「不寫就跟 arb-dir 相同」這個隱性預設值，對未來 Flutter 版本行為變動更穩健），不是修復實際問題。不論如何，`AppLocalizations` 皆為可被 `flutter analyze` 檢查、可被一般 `import` 陳述式引用的型別。

### 1.3 ARB 檔案

- `app/lib/l10n/app_zh_TW.arb`（template，含每個 key 的 `@key` 描述區塊）
- `app/lib/l10n/app_zh_CN.arb`
- `app/lib/l10n/app_en.arb`

Key 命名慣例：`小駝峰`，依畫面/模組分組但不強制巢狀（ARB 本身是扁平結構），例如 `settingsAppearanceSectionTitle`、`groupUncategorized`、`errorNetworkConnection`。計數相關字串一律用 ICU `plural` 語法（見 `design.md` M-1 修正範例），不手動拼接單複數字串。

## 2. 核心型別

### 2.1 `AppLocale`（`app/lib/l10n/app_locale.dart`，新檔案）

```dart
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
```

比照既有 `AppTheme` enum 的既定模式（型別安全、無 magic string 外洩到呼叫端）。

### 2.2 `resolveSupportedLocale()`（同檔案，頂層函式）

```dart
/// 依 `design.md`「Locale 解析矩陣」把裝置回報的任意 [Locale] 對應到本 App
/// 支援的三個語系之一。純函式，不依賴 BuildContext，供
/// [localeListResolutionCallback] 與單元測試共用。
///
/// **必須先比對 `languageCode`，再依中文語境下的 script/country 判斷繁簡**
/// （`/receiving-code-review` C-1 修正）——原始版本先比對 country 會導致
/// `en_SG`／`en_HK`／`en_TW`（港澳星台地區偏好英文介面的使用者，常見情境）
/// 被地區代碼誤判為中文，`language == 'en'` 分支永遠輪不到。
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
```

純 Dart 函式，`flutter test` 可直接單元測試（不需 Widget 環境）。測試案例須涵蓋 `en_SG`／`en_HK`／`en_TW` 這組「地區代碼落在中文區域但語言是英文」的組合，確保回傳 `AppLocale.en` 而非誤判為中文（`/receiving-code-review` C-1 修正要求的迴歸測試）。

### 2.3 `AppLocalePreferences`（`app/lib/l10n/app_locale_preferences.dart`，新檔案）

比照 `app/lib/theme/app_theme_preferences.dart` 既有模式：

```dart
class AppLocalePreferences {
  static const _localeKey = 'app_locale'; // 值域：'zhTW' / 'zhCN' / 'en'（AppLocale enum 成員名稱，非 BCP-47 格式，見下方 byName() 對應）；鍵不存在＝跟隨系統

  /// 回傳 `null` 代表「跟隨系統」（`design.md` I-1 修正的 nullable 儲存語意）。
  Future<AppLocale?> loadLocaleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localeKey);
    if (raw == null) return null;
    try {
      return AppLocale.values.byName(raw); // 儲存格式需與 enum name 一致，見下方命名對應
    } catch (_) {
      return null; // 資料污染/未來列舉改名時安全退回「跟隨系統」
    }
  }

  /// 傳入 `null` 清除覆寫（回到跟隨系統）。
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

`AppLocale.values.byName()` 要求儲存字串與 enum 成員名稱（`zhTW`/`zhCN`/`en`）完全一致，非 BCP-47 格式（`zh_TW`）——實作時需注意這個對應，不要直接把 `Locale.toString()` 存進去。

## 3. `MaterialApp` 接線契約（`ElinkBookApp`）

`app/lib/main.dart` 的 `_ElinkBookAppState` 新增 `AppLocale? _localeOverride`（初值來自 `main()` 內 `AppLocalePreferences().loadLocaleOverride()`，比照 `initialTheme`/`initialEinkMode` 既有的「main() 先讀、建構子注入、避免開機閃爍」模式）。

```dart
MaterialApp(
  locale: _localeOverride?.locale, // null 時交給 localeListResolutionCallback 動態解析
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  localeListResolutionCallback: (deviceLocales, supportedLocales) {
    // 依序走訪使用者的語言喜好清單（`/receiving-code-review` I-3 修正：
    // 原本只取 firstOrNull 會讓「次要偏好為中文/英文、但首選是本 App 不
    // 支援語言（例如法語）」的使用者被直接 fallback 正體中文，忽視次要
    // 偏好），找到第一個語言碼落在本 App 實際支援範圍（zh／en）的項目才
    // 採用；清單為 null 或全部不支援時才 fallback 正體中文。
    for (final locale in deviceLocales ?? const <Locale>[]) {
      if (locale.languageCode == 'zh' || locale.languageCode == 'en') {
        return resolveSupportedLocale(locale).locale;
      }
    }
    return AppLocale.zhTW.locale;
  },
  ...
)
```

`_localeOverride` 变更時呼叫 `setState()`＋`AppLocalePreferences().saveLocaleOverride()`，比照既有 `_handleThemeChanged()`/`_handleEinkModeChanged()` 寫法對稱。

## 4. 設定 UI 契約

新增 `LibraryLocaleDependencies`（`app/lib/screens/library_screen_dependencies.dart`，比照既有 `LibraryThemeDependencies` 同檔案、同模式）：

```dart
class LibraryLocaleDependencies {
  final AppLocale? currentLocaleOverride; // null＝目前跟隨系統
  final ValueChanged<AppLocale?>? onLocaleChanged;

  const LibraryLocaleDependencies({
    this.currentLocaleOverride,
    this.onLocaleChanged,
  });
}
```

由 `ElinkBookApp` → `AdaptiveShellScaffold` → `SettingsScaffold` 逐層透傳（比照 `themeDependencies` 既有透傳路徑）。`SettingsScaffold`「外觀」分區新增一個 `ListTile`（緊接「佈景」之後），點擊開啟 4 選項選擇器（`跟隨系統`／`正體中文`／`簡體中文`／`English`，單選 `RadioListTile` 或 `showModalBottomSheet` 選單，比照既有「佈景」選色 UI 的呈現層級），選取後呼叫 `onLocaleChanged`。具體 Widget（獨立 Bottom Sheet vs 內嵌 Dialog）留待 Issue 拆分時依「佈景」既有 UI 模式決定，不在本 spec 另立新樣式。

## 5. 系統保留分類名稱在地化契約

### 5.1 表現層轉譯 helper（`app/lib/library/models/book_group.dart`，擴充既有檔案）

```dart
/// 表現層顯示名稱轉換：系統保留分類（`BookGroup.uncategorized`）依目前介面
/// 語言轉譯；使用者自訂分類原樣顯示，不經過此轉譯（`design.md`「系統保留
/// 分類名稱的在地化契約」）。獨立頂層函式而非只做成 [BookGroup] 擴充方法
/// （`/receiving-code-review` M-2 修正）——`cloud_browser_screen.dart` 等
/// 多處畫面是以裸 `String` 持有群組名稱（例如 `_selectedGroupName`），並非
/// 都經手 [BookGroup] 物件，需要能直接對字串呼叫。
String localizeGroupName(String name, AppLocalizations l10n) =>
    name == BookGroup.uncategorized ? l10n.groupUncategorized : name;

extension BookGroupL10n on BookGroup {
  /// 轉發至 [localizeGroupName]，供已持有 [BookGroup] 物件的呼叫端使用。
  String displayName(AppLocalizations l10n) => localizeGroupName(name, l10n);
}
```

所有 UI 呈現處（`library_screen.dart` 書架分頁標籤、`library_group_management_dialog.dart` 群組清單、`cloud_browser_screen.dart` 分類選擇下拉選單等）一律改用 `group.displayName(l10n)` 或 `localizeGroupName(rawName, l10n)`，不得直接顯示 `group.name`／原始字串給使用者（原始字串只用於底層比對/寫入）。

### 5.2 撞名防線（`library_group_management_dialog.dart` 修改既有邏輯）

**（`/receiving-code-review` C-2 修正，推翻原「只比對當前介面語言」的設計）**：elinkBook 支援語言是已知的封閉集合（正體中文／簡體中文／英文三種），保留名稱集合本身也是固定已知的——只比對「當前介面語言」下的翻譯結果，會讓使用者在中文介面下建立英文自訂分類 `"Uncategorized"`（此時比對的是 `l10n.groupUncategorized == '未分類'`，不會命中），事後切換到英文介面時，系統保留分類經 `displayName()` 轉譯後也顯示 `"Uncategorized"`，兩者撞名、產生幽靈重複群組。

`_addGroup()`／`_renameGroup()` 呼叫 `repository.upsertGroup()`／`renameGroup()` **之前**，新增前端驗證，同時防禦所有支援語言的保留名稱（不限當前介面語言），英文不分大小寫：

```dart
bool _isReservedGroupName(String name) {
  const reserved = {'未分類', '未分类', 'uncategorized'};
  return reserved.contains(name.trim().toLowerCase());
}
```

這個函式刻意**不需要** `AppLocalizations` 參數——保留名稱清單本身是三語言的靜態已知集合，不依賴目前介面語言，因此純邏輯、`flutter test` 可直接單元測試，也不需要 `BuildContext`。命中時直接顯示錯誤（比照既有 `_errorMessage` 狀態欄位），**不呼叫**底層 repository 方法——`SqliteLibraryRepository.upsertGroup()`／`renameGroup()` 本身不新增這個檢查（它們沒有這層產品語意可用，且底層已用字面值 `BookGroup.uncategorized` 做保留字面值防護，不需要重複）。

## 6. 執行期例外訊息在地化慣例

不建立單一 catch-all 轉換函式（各模組例外類型與語意差異太大，強行統一介面反而失去語境）。建立的是**慣例**，Scrum Master 拆 Issue 時每個模組各自依此慣例補上對應 l10n key：

- 使用者可見的錯誤提示（`SnackBar`／`AlertDialog`／畫面內錯誤文字）一律是 `AppLocalizations` 的具名 key（例如 `l10n.errorNetworkConnection`、`l10n.errorSyncFailed`、`l10n.errorBookOpenTimeout`、`l10n.errorOperationFailed`——具體 key 清單依 `design.md` I-3 列出的 14 個檔案逐一盤點後定案），**禁止**在使用者可見文字中出現 `e.toString()`、`e.message`、或其他例外物件的原始文字內容。
- 原生 `PlatformException.code` → `AppLocalizations` 的對應，建議收斂在各呼叫模組自己的一個小型 `switch`/映射函式（不需要跨模組共用單一巨大映射表）。**（`/receiving-code-review` I-4 修正）**：這個映射函式必須放在**表現層／UI Helper**（例如 `app/lib/screens/support/book_import_picker_helper.dart`，既有 `showImportResultSnackBar()` 所在檔案），**不可**放進 `app/lib/library/book_import_service_impl.dart` 等純業務服務層——查證該服務層目前只 import `package:flutter/services.dart`（取用 `PlatformException` 型別），未 import `package:flutter/material.dart`，維持不依賴 UI 框架的分層現況；服務層職責是回報 `ImportResult` 或拋出帶錯誤代碼的例外，`AppLocalizations` 屬於表現層產物，注入下去會破壞既有分層。
- 技術除錯細節（例外堆疊、原始 `e.toString()`）維持寫入 Console Log（`ReaderConsoleLogScreen`/既有 log 攔截機制），不受本 Epic 翻譯範圍限制。

## 7. Markdown 匯出契約變更

`app/lib/reader/markdown_export.dart` 的 `generateMarkdownExport()` 簽章新增 `required AppLocalizations l10n` 參數，函式內所有系統結構文字（`# 閱讀筆記：《...》`、`**作者**`、`**閱讀進度**`、`**導出時間**`、`## 🔖 書籤清單`、`*(尚未加入書籤)*`、`## ✏️ 劃線與個人備註`、`*(尚未加入任何劃線或備註)*`、`_highlightStyleLabel()` 內的樣式標籤）改為讀取對應 `l10n.xxx`。書名/作者本身（使用者資料）與位置標籤（複用 `Bookmark.defaultName`，其字串已是既有機制產出，另外評估是否也需要 l10n 化留待該函式所屬模組一併檢視，不在本次變更範圍）不受影響。呼叫端 `NotesBottomSheet` 需改為傳入當下 `BuildContext` 解析出的 `AppLocalizations.of(context)!`。

**純 Dart 單元測試如何取得 `AppLocalizations` 實例（`/receiving-code-review` I-5 修正）**：查閱既有 `app/test/reader/markdown_export_test.dart`，是 `test(...)`（非 `testWidgets(...)`）的純 Dart 單元測試，沒有 `BuildContext`/Widget 渲染樹可用，不能透過 `AppLocalizations.of(context)!` 取得實例。`flutter gen-l10n` 產生的 `app_localizations.dart` 內建一個同步頂層函式 `lookupAppLocalizations(Locale locale)`，測試中直接呼叫即可同步取得實例：

```dart
final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
generateMarkdownExport(..., l10n: l10n);
```

不需要啟動非同步 delegate、也不需要建構假 Widget 樹。

## 8. 測試套件相容性契約

新增 `app/test/support/pump_localized_widget.dart`：

```dart
Future<void> pumpLocalizedWidget(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
    home: home,
  ));
}
```

`theme`/`isEinkMode` 直接收 `AppTheme`／`bool`（而非裸 `ThemeData?`），內部呼叫 `resolveThemeData()`（`/receiving-code-review` M-3 修正）——既有測試檔案本來就大量是 `MaterialApp(theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false), ...)` 這種寫法（見 `settings_scaffold_test.dart` 等既有慣例），直接收窄參數型別讓遷移時的呼叫端更精簡，不需要每個測試檔自己再組一次 `resolveThemeData()`。

- 預設 `locale` 釘定為 `zh_TW`，讓既有 300+ 處中文 `find.text()` 斷言遷移期間維持通過（`design.md` C-2 修正）。
- 既有 68 個測試檔逐一把裸 `MaterialApp(...)` 呼叫改為 `pumpLocalizedWidget(tester, ...)` 是純機械式改動（不改變任何斷言內容），適合收斂成 Scrum Master 階段的獨立 Issue（或依模組拆成多個 Issue），不與各功能畫面的字串抽取 Issue 混在一起，避免單一 Issue 改動面過大。
- 新增 `app/test/l10n/locale_switch_test.dart`：針對少數代表性畫面（例如 `SettingsScaffold`、`LibraryScreen`）分別在 `zh_CN`/`en` locale 下驗證關鍵字串正確渲染，不要求每個既有測試檔都複製三語言版本。

## 9. 防遺漏稽核腳本契約

新增 `app/tool/check_l10n_hardcoded_strings.js`（Node，比照既有 `app/tool/check_foliate_es_compat.js` 執行方式與慣例）：

- 掃描範圍：`app/lib/**/*.dart`（不含 `app/lib/l10n/**` 產生檔與 ARB 字典本身）。
- 規則：偵測 Widget 建構式常見字串參數位置（`Text('...')`、`title:`/`subtitle:`/`label:`/`hintText:`/`content:` 等關鍵字後的字串字面值）中出現中文字元（Unicode 範圍 U+4E00–U+9FFF，CJK Unified Ideographs）且未透過 `AppLocalizations`/`l10n.` 存取。**掃描前須先剝離 `//` 單行與 `/* ... */` 多行註解內容再比對正則**（`/receiving-code-review` M-4 修正）——本專案依 `CLAUDE.md` 規範，Dart 原始碼註解一律使用正體中文（例如 `// Text('確定') 按鈕`），若不先剝離註解，這類註解文字會被誤判為未包裝的硬編碼字串，產生大量假警報。
- 排除清單（`design.md` M-2 修正）：內建於腳本的允許清單，至少涵蓋——
  - `BookGroup.uncategorized` 等系統保留 Sentinel 常數定義所在檔案（`book_group.dart`）；
  - 內建字型品牌名所在檔案；
  - `epic-42-text-conversion` 簡繁字典檔案；
  - `app/test/**`（測試 fixture/mock 資料不受本腳本規範）。
  - 具體檔案清單／行內 `// l10n-ignore: <理由>` 標記機制的實作細節，留待落地該 Issue 時依實際掃描結果調整。
- 是否接入 CI／`flutter analyze` 前置檢查，留待該 Issue 依專案既有 CI 設定方式決定。

**補充（2026-09-24，使用者於 Issue 10 程式審查後裁定；`reviews/review-issue-10.md` I-3）**：

- **稽核範圍新增第二項檢查**：`app/test/**/*.dart` 內每個 `MaterialApp(`／`MaterialApp.router(` 必須在最外層參數帶 `locale`／`localizationsDelegates`／`supportedLocales`（缺 `locale:` 時 flutter_test 預設 en_US，日後在該測試加中文斷言會靜默失敗；缺委派則觸發 `AppLocalizations.of(context)!` 的 Null check）。刻意保留裸 `MaterialApp` 的測試（`eb_sheet_shell_test.dart` 的 fallback 案例）以「檔案＋數量」白名單放行。上方排除清單的「`app/test/**`」僅指測試 fixture／mock 資料中的中文字串不在稽核範圍，不含此項檢查。
- **位置規則放寬**：由「字面值必須直接緊接關鍵字」改為「字面值位於文字參數的參數運算式內」（涵蓋三元運算式與字串串接；含 `??` 的 fallback 刻意放行），參數名由固定清單改為「完整名稱＋`Label`／`Title`／`Text`／`Tooltip`／`Message`／`Hint`／`Subtitle` 後綴」規則（涵蓋自訂 Widget 參數）。
- **§7 位置標籤的延後事項已處理**：§7 提到 `Bookmark.defaultName` 是否也需要 l10n 化「留待該函式所屬模組一併檢視」，已於 Issue 10 處理——`Bookmark.defaultName(context, l10n)` 依介面語言輸出；書籤名稱是建立當下語言的快照，之後切換介面語言不會改變已建立的書籤。

## 10. 下一步

進入 Scrum Master 階段：依本 spec 定義的介面契約拆分 Issue。建議切片方向（僅供參考，實際顆粒度由 Scrum Master 階段與使用者確認）：

0. 依賴引進＋核心型別骨架（`AppLocale`／`AppLocalePreferences`／`resolveSupportedLocale()`／`l10n.yaml`／三份 ARB 骨架含既有共用字串）＋`MaterialApp` 接線＋`pumpLocalizedWidget()`，無使用者可見行為變動。
1. 設定「語言」選擇 UI（`LibraryLocaleDependencies` 全鏈路串接）。
2. 系統保留分類名稱在地化契約落地（`localizeGroupName()`／`BookGroupL10n`／撞名防線）。
3. 依模組分批的既有畫面字串抽取＋**同批測試檔同步遷移**（書架→閱讀器 Chrome Bar→系統設定四分區→其餘管理類彈窗，見 `design.md` 依賴事實）。
4. 執行期例外訊息在地化（依 `design.md` I-3 列出的 14 個檔案逐一盤點）＋對應測試檔同步遷移。
5. Markdown 匯出契約變更（含純 Dart 單元測試改用 `lookupAppLocalizations()`）。
6. 收斂清理：Issue 3／4 未涵蓋到的其餘邊角測試檔遷移至 `pumpLocalizedWidget()`。
7. 防遺漏稽核腳本。

**Issue 3／4 與測試遷移的排序原則（`/receiving-code-review` I-1 修正，推翻原「畫面字串抽取與測試遷移分屬不同 Issue」的排法）**：既有 68 個測試檔皆為裸 `MaterialApp(...)`，一旦某個 Issue 把對應畫面的字串改用 `AppLocalizations.of(context)!`，同一個 Issue 若未同步把該畫面的測試檔改用 `pumpLocalizedWidget()`，`flutter test` 會立即因缺少 `localizationsDelegates` 觸發 `Null check operator` 崩潰，違反 `AGENTS.md` 每個工單提交前必須通過 `flutter test` 的硬性門檻。因此**每個字串抽取 Issue（3、4）必須把該 Issue 觸及畫面對應的測試檔遷移工作一併納入範圍**，不可分離成獨立後置 Issue；原「Issue 6：既有 68 個測試檔遷移」改為「Issue 6：收斂清理 Issue 3／4 未觸及畫面的其餘邊角測試檔」，範圍隨 Issue 3／4 實際涵蓋面縮小，不再是「全部 68 檔」。

各 Issue 之間的相依關係、是否可平行開發，留待 Scrum Master 階段與使用者確認後定案。
