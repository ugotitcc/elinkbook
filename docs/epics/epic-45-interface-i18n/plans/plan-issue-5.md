# Epic 45 Issue 5：系統設定四分區模組字串抽取＋測試遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `SettingsScaffold` 四分區（外觀／閱讀／同步與帳號／關於）其餘 9 個子畫面（`settings_scaffold.dart` 本身＋8 個子畫面）的硬編碼中文字串改為 `AppLocalizations` key，三語言皆補上真實翻譯，對應測試檔同步遷移至在地化相容寫法，零使用者可見行為變動（除新增語言支援本身）。

**Architecture:** 沿用 Issue 3／4 已確立的模式——`AppLocalizations.of(context)!`（non-null assertion）＋新增 ARB key（三語言真實翻譯＋`app_zh.arb` fallback 同步）＋既有測試補上 `locale`/`localizationsDelegates`/`supportedLocales`。本 Issue 規模介於 Issue 3（7 Task）與 Issue 4（21 Task）之間，拆為 12 個 Task；`nav_zone_settings_screen.dart`／`reading_defaults_screen.dart` 兩個測試檔 `MaterialApp(` 出現次數較多（17／14 處），比照 Issue 4 Task 15/16 先例把 production 與測試遷移拆成相鄰獨立 Task，其餘檔案（≤10 處）production＋測試合併同一 Task（比照 Issue 4 Task 14 先例）。

**範圍已依實際 grep 盤點修正**（`issues.md` 本身註明「代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準」）：
- **移出**：`settings_scaffold.dart` 的「已索引 $current / $total 本」全文檢索索引進度字串——`issues.md`「ICU plural（review-issues I-2 修正）」段落引用的 `settings_scaffold.dart:289` 附近文字經 grep／`git log -S` 查證**現行程式碼中不存在**（該檔案目前只有「重建索引」按鈕＋開關，沒有任何顯示 current/total 計數的進度文字；`epic-41-search-architecture-hardening` Issue 5 重構 `FullTextSearchTogglesController` 時可能已移除這段 UI，`issues.md` 這個描述已過時）。本 Issue 不新增這個字串對應的 ICU plural 邏輯，Task 1 僅記錄此查證結果，不產生對應程式碼變更。
- **確認保留但範圍縮小**：`settings_scaffold_test.dart` 已在 Issue 1（`plans/plan-issue-1.md` Task 3）完整遷移至 `pumpLocalizedWidget()`（113 處中的全部 33 處裸 `MaterialApp` 早已補上三個 l10n 參數），本 Issue **不重複遷移**，Task 1 只需在既有 `pumpLocalizedWidget()` 呼叫基礎上新增斷言與新測試。
- **確認保留**：`nav_zone_settings_screen.dart`／`tts_defaults_screen.dart`／`reading_defaults_screen.dart`／`sync_settings_screen.dart`／`cloud_account_settings_screen.dart`／`font_management_screen.dart`（內建 5 款字型顯示名稱 `_builtInDisplayName()` 不翻譯，`design.md` 排除範圍，比照 Issue 4 `reader_settings_sheet.dart._fontDisplayName()` 既有先例）／`reader_console_log_screen.dart`／`about_screen.dart` 皆確認為本 Issue 範圍、且皆有硬編碼中文字串待抽取。
- **確認排除**：`cloud_account_settings_screen.dart._buildProviderTile()` 的 `title` 參數（呼叫端固定傳入 `'Google Drive'`／`'OneDrive'`）是雲端服務商品牌名，`design.md`「使用者輸入資料與專有名詞（字型名稱／雲端品牌名）不納入」明文排除，不修改。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`，含 ICU `plural` 與 `DateFormat`）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§8 測試相容性、Key 命名慣例）、`docs/epics/epic-45-interface-i18n/design.md`（ICU plural／字型品牌名不翻譯排除範圍）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 5 段落）。

## Global Constraints

- 所有新增 ARB key 必須同步寫入四份檔案：`app_zh_TW.arb`（含 `@key` description）、`app_zh_CN.arb`、`app_en.arb`（皆為真實翻譯，非機器翻譯佔位）、`app_zh.arb`（與 `app_zh_TW.arb` 相同值，不含 `@key` description block）。異動前四份檔案皆為 337 個 key，完全同步。
- `AppLocalizations.of(context)!` 一律用 non-null assertion，不得使用 `l10n?.xxx ?? '硬編碼字面值'` 的 nullable fallback 寫法（Issue 2 審查 `review-issue-2.md` Important #1 確立的教訓）。
- **`State` 方法可直接呼叫 `AppLocalizations.of(context)!`，不需要額外把 `l10n`/`context` 當作參數逐層傳遞**：本 Issue 全部 9 個檔案的私有 helper 方法（例如 `_themeLabel()`／`_actionLabel()`／`_buildProviderTile()`）皆是各自 `State<T>` 子類別的**實例方法**，`context` 為 `State` 內建 getter，直接在方法內呼叫 `AppLocalizations.of(context)!` 即可，不需要改動這些方法的簽章新增參數（比照 Issue 4 Task 19 `_TtsSleepTimerSheet.build()`／`_annotationDeleteButtonLabel()` 直接在方法內取用 `context` 的既有先例）。**唯一例外**是 `font_management_screen.dart` 的 `buildUploadResultMessage()`——這是檔案層級的**頂層純函式**（非 State 方法），沒有 `context` 可用，且被一個不經過 widget tree 的 `test()` 純邏輯測試直接呼叫，見 Task 9 說明。
- **`initState()` 存取 l10n 陷阱（Issue 3 審查 `review-plan-issue-3.md` C-1 確立的鐵律）**：任何 `State.initState()` 執行期間呼叫 `AppLocalizations.of(context)!` 會拋出 `FlutterError`。本 Issue 逐一核對後，9 個檔案的 `initState()`（`NavZoneSettingsScreen`／`ReadingDefaultsScreen`／`TtsDefaultsScreen`／`SyncSettingsScreen`／`CloudAccountSettingsScreen`／`AboutScreen`／`SettingsScaffold` 皆有）內容皆只呼叫 `_load()`/`_loadXxx()` 等純資料載入方法，不涉及任何字串/l10n 存取，不受影響；`about_screen.dart` 的三個欄位初始值改造（Task 11）刻意採用「State 標記＋build() 才轉譯」設計，確保初始值也不在 `initState()` 存取 l10n。
- ICU plural 全域規則：任何計數字串（英文有單複數變化）一律用 ARB `plural` 語法，中文三語言（`zh_TW`/`zh_CN`/`zh`）雖無文法複數變化，仍比照既有先例維持 `plural` 語法結構（`=1{...} other{...}` 兩分支填相同中文措辭）。本 Issue 唯一命中的計數字串是 `font_management_screen.dart` 的批次上傳結果訊息（`addedCount`／`skippedCount` 各自獨立處理單複數，比照 `issues.md` Issue 6 `book_import_picker_helper.dart` 先例的「兩個計數彼此獨立，不可共用同一個 plural 判斷式」原則）與刪除確認訊息的 `usageCount`，見 Task 9。
- 字型品牌名不翻譯：`font_management_screen.dart._builtInDisplayName()` 回傳的思源黑體／思源宋體／原俠正楷／台灣圓體／源流明體五個字型顯示名稱維持原樣不抽取（`design.md` 排除範圍，比照 Issue 4／Issue 5 `font_management_screen.dart` 既有原則）；使用者自訂字型顯示名稱（`font.displayName`）是使用者輸入資料，同樣不翻譯。
- 雲端服務商品牌名不翻譯：`cloud_account_settings_screen.dart` 的 `'Google Drive'`／`'OneDrive'` 字面值維持原樣（`design.md` 排除範圍）。
- 既有測試檔遷移：除 `settings_scaffold_test.dart`（已於 Issue 1 完成，見上方範圍修正）外，其餘 8 個測試檔皆為裸 `MaterialApp(` 直接呼叫（無共用 `_wrap()` helper），逐一在 `MaterialApp(` 參數列補上 `locale: const Locale('zh', 'TW')`/`localizationsDelegates: AppLocalizations.localizationsDelegates`/`supportedLocales: AppLocalizations.supportedLocales`；原本用 `const MaterialApp(...)` 宣告的呼叫點（`about_screen_test.dart`／`reader_console_log_screen_test.dart`）因新增非常數運算式，移除外層 `const`。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 12（最後一個 Task）執行一次。
- Commit 訊息前綴統一 `feat(epic-45):`，Task 12 除外用 `docs(epic-45):`。

---

### Task 1: `settings_scaffold.dart`

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/settings_scaffold_test.dart`（**不遷移**，已在 Issue 1 完成，僅新增斷言/測試）

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`build()` 內已宣告 `final l10n = AppLocalizations.of(context)!;`，第 184 行，直接沿用）。
- Produces：ARB key `settingsScaffoldTitle`/`settingsLibraryTooltip`/`settingsSourceTooltip`/`settingsAppearanceSectionTitle`/`settingsThemeLabel`/`settingsThemeLockedHint`/`settingsThemeDotSemanticsLabel`/`settingsThemeDotLockedSemanticsLabel`/`settingsThemeLight`/`settingsThemeDark`/`settingsThemeSepia`/`settingsEinkModeLabel`/`settingsEinkModeSubtitle`/`settingsFontManagementLabel`/`settingsReadingSectionTitle`/`settingsReadingDefaultsLabel`/`settingsNavZoneLabel`/`settingsTtsDefaultsLabel`/`settingsFullTextSearchUnavailableLabel`/`settingsFullTextSearchUnavailableSubtitle`/`settingsFullTextSearchPdfLabel`/`settingsFullTextSearchPdfSubtitle`/`settingsFullTextSearchRebuildIndexTooltip`/`settingsFullTextSearchFoliateLabel`/`settingsFullTextSearchFoliateSubtitle`/`settingsSyncAccountSectionTitle`/`settingsSyncLabel`/`settingsCloudAccountLabel`/`settingsAboutSectionTitle`/`settingsAboutLabel`/`settingsReaderConsoleLogLabel`/`settingsConsoleLogInterceptLabel`/`settingsConsoleLogInterceptSubtitle`。

**計劃範圍澄清（ICU plural 查證結果）**：`issues.md` 記載「`settings_scaffold.dart:289` 附近的全文檢索索引進度『已索引 $current / $total 本』」需要 ICU plural——實際 grep 全檔（`grep -n "索引\|current\|total" lib/screens/settings_scaffold.dart`）確認不存在任何此類進度文字，目前該區塊只有「PDF 全文檢索」/「其他格式全文檢索」兩張卡片＋「重建索引」按鈕＋開關，沒有顯示計數進度的 UI。本 Task 不新增對應 ICU plural 邏輯，此為範圍修正記錄的一部分（見 Task 12 Step 4）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "settingsScaffoldTitle": "設定",
  "@settingsScaffoldTitle": {
    "description": "設定畫面 AppBar 標題"
  },
  "settingsLibraryTooltip": "書架",
  "@settingsLibraryTooltip": {
    "description": "設定畫面 AppBar 右上角「書架」導覽按鈕的無障礙提示文字"
  },
  "settingsSourceTooltip": "來源",
  "@settingsSourceTooltip": {
    "description": "設定畫面 AppBar 右上角「來源」導覽按鈕的無障礙提示文字"
  },
  "settingsAppearanceSectionTitle": "外觀",
  "@settingsAppearanceSectionTitle": {
    "description": "設定畫面「外觀」分區標題"
  },
  "settingsThemeLabel": "佈景",
  "@settingsThemeLabel": {
    "description": "設定畫面「佈景」項目標題（主題色點選取器入口）"
  },
  "settingsThemeLockedHint": "這裡選的是關閉 E-Ink 後要恢復的主題",
  "@settingsThemeLockedHint": {
    "description": "E-Ink 模式開啟時，「佈景」項目下方顯示的提示文字，說明目前選的是解除 E-Ink 後要恢復的主題"
  },
  "settingsThemeDotSemanticsLabel": "{themeName}佈景",
  "@settingsThemeDotSemanticsLabel": {
    "description": "主題色點的無障礙 Semantics 標籤（一般狀態），{themeName} 為 settingsThemeLight/Dark/Sepia 的已轉譯結果",
    "placeholders": {
      "themeName": {
        "type": "String"
      }
    }
  },
  "settingsThemeDotLockedSemanticsLabel": "{themeName}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，目前選擇：{currentThemeName}",
  "@settingsThemeDotLockedSemanticsLabel": {
    "description": "主題色點的無障礙 Semantics 標籤（E-Ink 鎖定狀態），{themeName} 為該色點對應主題名稱，{currentThemeName} 為目前實際選擇（鎖定後要恢復）的主題名稱",
    "placeholders": {
      "themeName": {
        "type": "String"
      },
      "currentThemeName": {
        "type": "String"
      }
    }
  },
  "settingsThemeLight": "淺色",
  "@settingsThemeLight": {
    "description": "淺色主題的顯示名稱"
  },
  "settingsThemeDark": "深色",
  "@settingsThemeDark": {
    "description": "深色主題的顯示名稱"
  },
  "settingsThemeSepia": "羊皮紙",
  "@settingsThemeSepia": {
    "description": "羊皮紙主題的顯示名稱"
  },
  "settingsEinkModeLabel": "E-Ink 高對比模式",
  "@settingsEinkModeLabel": {
    "description": "設定畫面「E-Ink 高對比模式」開關標題"
  },
  "settingsEinkModeSubtitle": "停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化",
  "@settingsEinkModeSubtitle": {
    "description": "設定畫面「E-Ink 高對比模式」開關的說明文字"
  },
  "settingsFontManagementLabel": "字型管理",
  "@settingsFontManagementLabel": {
    "description": "設定畫面「字型管理」項目標題，同時是 FontManagementScreen 的 AppBar 標題"
  },
  "settingsReadingSectionTitle": "閱讀",
  "@settingsReadingSectionTitle": {
    "description": "設定畫面「閱讀」分區標題"
  },
  "settingsReadingDefaultsLabel": "閱讀預設值",
  "@settingsReadingDefaultsLabel": {
    "description": "設定畫面「閱讀預設值」項目標題，同時是 ReadingDefaultsScreen 的 AppBar 標題"
  },
  "settingsNavZoneLabel": "導航熱區",
  "@settingsNavZoneLabel": {
    "description": "設定畫面「導航熱區」項目標題，同時是 NavZoneSettingsScreen 的 AppBar 標題"
  },
  "settingsTtsDefaultsLabel": "朗讀語音與語速",
  "@settingsTtsDefaultsLabel": {
    "description": "設定畫面「朗讀語音與語速」項目標題，同時是 TtsDefaultsScreen 的 AppBar 標題"
  },
  "settingsFullTextSearchUnavailableLabel": "全文檢索",
  "@settingsFullTextSearchUnavailableLabel": {
    "description": "裝置不支援全文檢索時顯示的卡片標題"
  },
  "settingsFullTextSearchUnavailableSubtitle": "本裝置不支援全文檢索",
  "@settingsFullTextSearchUnavailableSubtitle": {
    "description": "裝置不支援全文檢索時顯示的卡片說明文字"
  },
  "settingsFullTextSearchPdfLabel": "PDF 全文檢索",
  "@settingsFullTextSearchPdfLabel": {
    "description": "PDF 全文檢索開關卡片標題"
  },
  "settingsFullTextSearchPdfSubtitle": "部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容",
  "@settingsFullTextSearchPdfSubtitle": {
    "description": "PDF 全文檢索開關卡片說明文字"
  },
  "settingsFullTextSearchRebuildIndexTooltip": "重建索引",
  "@settingsFullTextSearchRebuildIndexTooltip": {
    "description": "PDF／其他格式全文檢索卡片「重建索引」按鈕的無障礙提示文字（兩處共用同一 key）"
  },
  "settingsFullTextSearchFoliateLabel": "其他格式全文檢索",
  "@settingsFullTextSearchFoliateLabel": {
    "description": "EPUB／TXT／KF8 等格式全文檢索開關卡片標題"
  },
  "settingsFullTextSearchFoliateSubtitle": "EPUB／TXT／KF8 等格式的背景索引建置",
  "@settingsFullTextSearchFoliateSubtitle": {
    "description": "EPUB／TXT／KF8 等格式全文檢索開關卡片說明文字"
  },
  "settingsSyncAccountSectionTitle": "同步與帳號",
  "@settingsSyncAccountSectionTitle": {
    "description": "設定畫面「同步與帳號」分區標題"
  },
  "settingsSyncLabel": "同步",
  "@settingsSyncLabel": {
    "description": "設定畫面「同步」項目標題"
  },
  "settingsCloudAccountLabel": "已連結的雲端匯入帳戶",
  "@settingsCloudAccountLabel": {
    "description": "設定畫面「已連結的雲端匯入帳戶」項目標題，同時是 CloudAccountSettingsScreen 的 AppBar 標題"
  },
  "settingsAboutSectionTitle": "關於",
  "@settingsAboutSectionTitle": {
    "description": "設定畫面「關於」分區標題"
  },
  "settingsAboutLabel": "關於",
  "@settingsAboutLabel": {
    "description": "設定畫面「關於」項目標題（與分區標題文字相同，共用一個 key）"
  },
  "settingsReaderConsoleLogLabel": "閱讀器 Console Log",
  "@settingsReaderConsoleLogLabel": {
    "description": "設定畫面「閱讀器 Console Log」項目標題，同時是 ReaderConsoleLogScreen 的 AppBar 標題"
  },
  "settingsConsoleLogInterceptLabel": "Console Log 攔截",
  "@settingsConsoleLogInterceptLabel": {
    "description": "設定畫面「Console Log 攔截」開關標題"
  },
  "settingsConsoleLogInterceptSubtitle": "關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄",
  "@settingsConsoleLogInterceptSubtitle": {
    "description": "設定畫面「Console Log 攔截」開關的說明文字"
  }
```

`app_zh_CN.arb` 檔尾新增：
```json
  "settingsScaffoldTitle": "设定",
  "settingsLibraryTooltip": "书架",
  "settingsSourceTooltip": "来源",
  "settingsAppearanceSectionTitle": "外观",
  "settingsThemeLabel": "布景",
  "settingsThemeLockedHint": "这里选的是关闭 E-Ink 后要恢复的主题",
  "settingsThemeDotSemanticsLabel": "{themeName}布景",
  "settingsThemeDotLockedSemanticsLabel": "{themeName}布景，已锁定，这里选的是关闭 E-Ink 后要恢复的主题，目前选择：{currentThemeName}",
  "settingsThemeLight": "浅色",
  "settingsThemeDark": "深色",
  "settingsThemeSepia": "羊皮纸",
  "settingsEinkModeLabel": "E-Ink 高对比模式",
  "settingsEinkModeSubtitle": "停用动画与渐层，以纯黑白高对比显示，专为电子纸屏幕最佳化",
  "settingsFontManagementLabel": "字体管理",
  "settingsReadingSectionTitle": "阅读",
  "settingsReadingDefaultsLabel": "阅读预设值",
  "settingsNavZoneLabel": "导航热区",
  "settingsTtsDefaultsLabel": "朗读语音与语速",
  "settingsFullTextSearchUnavailableLabel": "全文检索",
  "settingsFullTextSearchUnavailableSubtitle": "本装置不支持全文检索",
  "settingsFullTextSearchPdfLabel": "PDF 全文检索",
  "settingsFullTextSearchPdfSubtitle": "部分扫描/图片型 PDF 可能没有可搜索的文字内容",
  "settingsFullTextSearchRebuildIndexTooltip": "重建索引",
  "settingsFullTextSearchFoliateLabel": "其他格式全文检索",
  "settingsFullTextSearchFoliateSubtitle": "EPUB／TXT／KF8 等格式的背景索引建置",
  "settingsSyncAccountSectionTitle": "同步与账号",
  "settingsSyncLabel": "同步",
  "settingsCloudAccountLabel": "已链接的云端导入账户",
  "settingsAboutSectionTitle": "关于",
  "settingsAboutLabel": "关于",
  "settingsReaderConsoleLogLabel": "阅读器 Console Log",
  "settingsConsoleLogInterceptLabel": "Console Log 拦截",
  "settingsConsoleLogInterceptSubtitle": "关闭后仅保留错误讯息，用于问题回报时的诊断纪录"
```

`app_en.arb` 檔尾新增：
```json
  "settingsScaffoldTitle": "Settings",
  "settingsLibraryTooltip": "Library",
  "settingsSourceTooltip": "Sources",
  "settingsAppearanceSectionTitle": "Appearance",
  "settingsThemeLabel": "Theme",
  "settingsThemeLockedHint": "This selects the theme to restore when E-Ink mode is turned off",
  "settingsThemeDotSemanticsLabel": "{themeName} theme",
  "settingsThemeDotLockedSemanticsLabel": "{themeName} theme, locked. This selects the theme to restore when E-Ink mode is off. Currently selected: {currentThemeName}",
  "settingsThemeLight": "Light",
  "settingsThemeDark": "Dark",
  "settingsThemeSepia": "Sepia",
  "settingsEinkModeLabel": "E-Ink high contrast mode",
  "settingsEinkModeSubtitle": "Disables animations and gradients, showing pure black-and-white high contrast optimized for e-paper screens",
  "settingsFontManagementLabel": "Font Management",
  "settingsReadingSectionTitle": "Reading",
  "settingsReadingDefaultsLabel": "Reading Defaults",
  "settingsNavZoneLabel": "Navigation Zones",
  "settingsTtsDefaultsLabel": "Read-Aloud Voice & Speed",
  "settingsFullTextSearchUnavailableLabel": "Full-Text Search",
  "settingsFullTextSearchUnavailableSubtitle": "Full-text search isn't supported on this device",
  "settingsFullTextSearchPdfLabel": "PDF Full-Text Search",
  "settingsFullTextSearchPdfSubtitle": "Some scanned or image-based PDFs may not have searchable text",
  "settingsFullTextSearchRebuildIndexTooltip": "Rebuild index",
  "settingsFullTextSearchFoliateLabel": "Other Formats Full-Text Search",
  "settingsFullTextSearchFoliateSubtitle": "Background index building for EPUB／TXT／KF8 and similar formats",
  "settingsSyncAccountSectionTitle": "Sync & Accounts",
  "settingsSyncLabel": "Sync",
  "settingsCloudAccountLabel": "Linked Cloud Import Accounts",
  "settingsAboutSectionTitle": "About",
  "settingsAboutLabel": "About",
  "settingsReaderConsoleLogLabel": "Reader Console Log",
  "settingsConsoleLogInterceptLabel": "Console Log Interception",
  "settingsConsoleLogInterceptSubtitle": "When off, only error messages are kept for diagnostic reports"
```

`app_zh.arb` 檔尾新增：
```json
  "settingsScaffoldTitle": "設定",
  "settingsLibraryTooltip": "書架",
  "settingsSourceTooltip": "來源",
  "settingsAppearanceSectionTitle": "外觀",
  "settingsThemeLabel": "佈景",
  "settingsThemeLockedHint": "這裡選的是關閉 E-Ink 後要恢復的主題",
  "settingsThemeDotSemanticsLabel": "{themeName}佈景",
  "settingsThemeDotLockedSemanticsLabel": "{themeName}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，目前選擇：{currentThemeName}",
  "settingsThemeLight": "淺色",
  "settingsThemeDark": "深色",
  "settingsThemeSepia": "羊皮紙",
  "settingsEinkModeLabel": "E-Ink 高對比模式",
  "settingsEinkModeSubtitle": "停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化",
  "settingsFontManagementLabel": "字型管理",
  "settingsReadingSectionTitle": "閱讀",
  "settingsReadingDefaultsLabel": "閱讀預設值",
  "settingsNavZoneLabel": "導航熱區",
  "settingsTtsDefaultsLabel": "朗讀語音與語速",
  "settingsFullTextSearchUnavailableLabel": "全文檢索",
  "settingsFullTextSearchUnavailableSubtitle": "本裝置不支援全文檢索",
  "settingsFullTextSearchPdfLabel": "PDF 全文檢索",
  "settingsFullTextSearchPdfSubtitle": "部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容",
  "settingsFullTextSearchRebuildIndexTooltip": "重建索引",
  "settingsFullTextSearchFoliateLabel": "其他格式全文檢索",
  "settingsFullTextSearchFoliateSubtitle": "EPUB／TXT／KF8 等格式的背景索引建置",
  "settingsSyncAccountSectionTitle": "同步與帳號",
  "settingsSyncLabel": "同步",
  "settingsCloudAccountLabel": "已連結的雲端匯入帳戶",
  "settingsAboutSectionTitle": "關於",
  "settingsAboutLabel": "關於",
  "settingsReaderConsoleLogLabel": "閱讀器 Console Log",
  "settingsConsoleLogInterceptLabel": "Console Log 攔截",
  "settingsConsoleLogInterceptSubtitle": "關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `settings_scaffold.dart`**

`build()` 方法（第 186-490 行）內，依序替換以下字面值（`final l10n = AppLocalizations.of(context)!;` 已存在於第 184 行，直接沿用；`const` 修飾詞若因子項不再是常數而需移除，一併處理）：

- 第 187 行 `title: const Text('設定'),` → `title: Text(l10n.settingsScaffoldTitle),`
- 第 192 行 `tooltip: '書架',` → `tooltip: l10n.settingsLibraryTooltip,`
- 第 198 行 `tooltip: '來源',` → `tooltip: l10n.settingsSourceTooltip,`
- 第 205 行 `const EBSectionHeader(title: '外觀'),` → `EBSectionHeader(title: l10n.settingsAppearanceSectionTitle),`
- 第 208 行 `title: const Text('佈景'),` → `title: Text(l10n.settingsThemeLabel),`
- 第 210-213 行：
  ```dart
              subtitle: widget.isEinkMode
                  ? Text(
                      l10n.settingsThemeLockedHint,
                      key: const Key('settings_theme_locked_hint'),
                    )
                  : null,
  ```
- 第 249 行 `title: const Text('E-Ink 高對比模式'),` → `title: Text(l10n.settingsEinkModeLabel),`
- 第 250 行 `subtitle: const Text('停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化'),` → `subtitle: Text(l10n.settingsEinkModeSubtitle),`
- 第 258 行 `title: const Text('字型管理'),` → `title: Text(l10n.settingsFontManagementLabel),`
- 第 273 行 `const EBSectionHeader(title: '閱讀'),` → `EBSectionHeader(title: l10n.settingsReadingSectionTitle),`
- 第 277 行 `title: const Text('閱讀預設值'),` → `title: Text(l10n.settingsReadingDefaultsLabel),`
- 第 293 行 `title: const Text('導航熱區'),` → `title: Text(l10n.settingsNavZoneLabel),`
- 第 309 行 `title: const Text('朗讀語音與語速'),` → `title: Text(l10n.settingsTtsDefaultsLabel),`
- 第 329-330 行：
  ```dart
                title: Text(l10n.settingsFullTextSearchUnavailableLabel),
                subtitle: Text(l10n.settingsFullTextSearchUnavailableSubtitle),
  ```
- 第 336-337 行：
  ```dart
                title: Text(l10n.settingsFullTextSearchPdfLabel),
                subtitle: Text(l10n.settingsFullTextSearchPdfSubtitle),
  ```
- 第 345 行 `tooltip: '重建索引',` → `tooltip: l10n.settingsFullTextSearchRebuildIndexTooltip,`
- 第 368-369 行：
  ```dart
                title: Text(l10n.settingsFullTextSearchFoliateLabel),
                subtitle: Text(l10n.settingsFullTextSearchFoliateSubtitle),
  ```
- 第 377 行 `tooltip: '重建索引',` → `tooltip: l10n.settingsFullTextSearchRebuildIndexTooltip,`
- 第 400 行 `const EBSectionHeader(title: '同步與帳號'),` → `EBSectionHeader(title: l10n.settingsSyncAccountSectionTitle),`
- 第 404 行 `title: const Text('同步'),` → `title: Text(l10n.settingsSyncLabel),`
- 第 429 行 `title: const Text('已連結的雲端匯入帳戶'),` → `title: Text(l10n.settingsCloudAccountLabel),`
- 第 451 行 `const EBSectionHeader(title: '關於'),` → `EBSectionHeader(title: l10n.settingsAboutSectionTitle),`
- 第 455 行 `title: const Text('關於'),` → `title: Text(l10n.settingsAboutLabel),`
- 第 467 行 `title: const Text('閱讀器 Console Log'),` → `title: Text(l10n.settingsReaderConsoleLogLabel),`
- 第 481 行 `title: const Text('Console Log 攔截'),` → `title: Text(l10n.settingsConsoleLogInterceptLabel),`
- 第 482 行 `subtitle: const Text('關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄'),` → `subtitle: Text(l10n.settingsConsoleLogInterceptSubtitle),`

`_buildThemeDot()`（第 492-533 行）與 `_themeLabel()`（第 535-539 行）——兩者皆為 `_SettingsScaffoldState` 實例方法，`context` 直接可用，改為：

```dart
  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final l10n = AppLocalizations.of(context)!;
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.isEinkMode;
    final isCurrentTheme = widget.currentTheme == theme;
    final isSelected = isCurrentTheme && !locked;
    return Semantics(
      label: locked
          ? l10n.settingsThemeDotLockedSemanticsLabel(
              _themeLabel(theme, l10n),
              _themeLabel(widget.currentTheme, l10n),
            )
          : l10n.settingsThemeDotSemanticsLabel(_themeLabel(theme, l10n)),
      button: !locked,
      child: GestureDetector(
        // ...（其餘內容原樣不動）
```

```dart
  String _themeLabel(AppTheme theme, AppLocalizations l10n) => switch (theme) {
    AppTheme.light => l10n.settingsThemeLight,
    AppTheme.dark => l10n.settingsThemeDark,
    AppTheme.sepia => l10n.settingsThemeSepia,
  };
```

（`_themeLabel()` 改為接收 `l10n` 參數而非直接呼叫 `AppLocalizations.of(context)!`，因為它本身沒有 `context` 參數、只有 `theme`——比起額外加一個 `BuildContext context` 參數，直接傳入呼叫端已解析好的 `l10n` 更簡潔，兩處呼叫端〔`_buildThemeDot()`〕都已持有 `l10n`。）

- [ ] **Step 4: 遷移既有測試檔（新增斷言，不遷移 `MaterialApp`）**

`app/test/screens/settings_scaffold_test.dart` 已全數使用 `pumpLocalizedWidget()`（Issue 1 完成），不需要新增 `localizationsDelegates` 等參數。找到既有斷言 `expect(find.text('設定'), findsOneWidget);`／`expect(find.text('佈景'), findsOneWidget);`（第 65-66、143 行附近）等處，確認斷言值不變（`pumpLocalizedWidget()` 預設 `locale: const Locale('zh', 'TW')`，這些中文斷言值與新 ARB key 在 `zh_TW` 下的值完全相同，不需要修改任何既有斷言）。

- [ ] **Step 5: 新增英文渲染驗證測試**

在檔案 `main()` 最後一個 `testWidgets` 之後新增：
```dart
  testWidgets('英文介面下設定畫面主要項目正確以英文渲染', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      locale: const Locale('en'),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('E-Ink high contrast mode'), findsOneWidget);
    expect(find.text('Font Management'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Reading Defaults'), findsOneWidget);
    expect(find.text('Navigation Zones'), findsOneWidget);
    expect(find.text('Read-Aloud Voice & Speed'), findsOneWidget);
    expect(find.text('Sync & Accounts'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Linked Cloud Import Accounts'), findsOneWidget);
    expect(find.text('About'), findsNWidgets(2));
    expect(find.text('Reader Console Log'), findsOneWidget);
    expect(find.text('Console Log Interception'), findsOneWidget);
  });

  testWidgets('E-Ink 模式下佈景色點的無障礙標籤正確帶出鎖定提示文字（英文）',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        isEinkMode: true,
        currentTheme: AppTheme.dark,
      ),
      locale: const Locale('en'),
    );

    final semantics = tester.getSemantics(
      find.byKey(const Key('settings_theme_dot_light')),
    );
    expect(semantics.label, contains('locked'));
    expect(semantics.label, contains('Dark'));

    handle.dispose();
  });
```

> 若既有 `SettingsScaffold(...)` 建構參數（`prefsManager`／`isEinkMode`／`currentTheme` 等）與檔案既有其他 `testWidgets` 實際使用的建構寫法不完全一致，改用該既有寫法，斷言邏輯不變。「About」在英文下 `findsNWidgets(2)`——分區標題與項目標題共用同一 key、文字相同（比照計畫 Step 1 `settingsAboutLabel` description 註記）。

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/settings_scaffold_test.dart`
Expected: 全數通過（既有＋新增 2 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/settings_scaffold.dart test/screens/settings_scaffold_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/settings_scaffold.dart app/test/screens/settings_scaffold_test.dart app/lib/l10n/
git commit -m "feat(epic-45): settings_scaffold.dart 字串抽取三語言在地化"
```

---

### Task 2: `nav_zone_settings_screen.dart`（production）

**Files:**
- Modify: `app/lib/screens/nav_zone_settings_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `navZoneSettingsTitle`/`navZoneSettingsPageTurnModeLabel`/`navZoneSettingsSimpleModeLabel`/`navZoneSettingsCustomModeLabel`/`navZoneSettingsShowDebugOverlayLabel`/`navZoneSettingsSaveCustomButton`/`navZoneActionPreviousPage`/`navZoneActionNextPage`/`navZoneActionMenu`/`navZoneActionNone`/`navZoneCustomValidationError`。

**計劃範圍澄清**：`navZoneActionPreviousPage`/`navZoneActionNextPage` 的中英文字面值恰好與 Issue 4 `widgets/paging_bar.dart` 的 `readerPagingPreviousTooltip`/`readerPagingNextTooltip` 相同（皆為「上一頁」/「下一頁」），但語意情境不同（本畫面是九宮格自訂熱區的動作標籤，非分頁按鈕 tooltip），刻意不重用 Issue 4 的 key、另建本模組專屬 key，維持模組邊界清晰（比照本 Epic 各模組皆各自宣告專屬 key 的既有慣例，只有 `cancel`/`close`/`confirm` 等通用泛型 key 才跨模組共用）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "navZoneSettingsTitle": "導航熱區",
  "@navZoneSettingsTitle": {
    "description": "導航熱區設定畫面 AppBar 標題"
  },
  "navZoneSettingsPageTurnModeLabel": "翻頁方式",
  "@navZoneSettingsPageTurnModeLabel": {
    "description": "導航熱區設定畫面「翻頁方式」（簡單/自訂模板切換）區塊標籤"
  },
  "navZoneSettingsSimpleModeLabel": "簡單",
  "@navZoneSettingsSimpleModeLabel": {
    "description": "翻頁方式切換鈕「簡單」選項文字（三選一固定模板）"
  },
  "navZoneSettingsCustomModeLabel": "自訂",
  "@navZoneSettingsCustomModeLabel": {
    "description": "翻頁方式切換鈕「自訂」選項文字（9 格自由編輯器）"
  },
  "navZoneSettingsShowDebugOverlayLabel": "顯示熱區輔助線",
  "@navZoneSettingsShowDebugOverlayLabel": {
    "description": "「顯示熱區輔助線」開關標題"
  },
  "navZoneSettingsSaveCustomButton": "儲存自訂熱區設定",
  "@navZoneSettingsSaveCustomButton": {
    "description": "自訂熱區編輯器「儲存自訂熱區設定」按鈕文字"
  },
  "navZoneActionPreviousPage": "上一頁",
  "@navZoneActionPreviousPage": {
    "description": "自訂熱區九宮格「上一頁」動作的格內文字"
  },
  "navZoneActionNextPage": "下一頁",
  "@navZoneActionNextPage": {
    "description": "自訂熱區九宮格「下一頁」動作的格內文字"
  },
  "navZoneActionMenu": "選單",
  "@navZoneActionMenu": {
    "description": "自訂熱區九宮格「選單」動作的格內文字"
  },
  "navZoneActionNone": "無動作",
  "@navZoneActionNone": {
    "description": "自訂熱區九宮格「無動作」動作的格內文字"
  },
  "navZoneCustomValidationError": "至少需要 1 格設為「選單」，否則將無法退出沉浸模式",
  "@navZoneCustomValidationError": {
    "description": "自訂熱區儲存時驗證失敗（沒有任何格子設為選單）的錯誤提示文字"
  }
```

`app_zh_CN.arb`：
```json
  "navZoneSettingsTitle": "导航热区",
  "navZoneSettingsPageTurnModeLabel": "翻页方式",
  "navZoneSettingsSimpleModeLabel": "简单",
  "navZoneSettingsCustomModeLabel": "自定义",
  "navZoneSettingsShowDebugOverlayLabel": "显示热区辅助线",
  "navZoneSettingsSaveCustomButton": "保存自定义热区设定",
  "navZoneActionPreviousPage": "上一页",
  "navZoneActionNextPage": "下一页",
  "navZoneActionMenu": "选单",
  "navZoneActionNone": "无动作",
  "navZoneCustomValidationError": "至少需要 1 格设为「选单」，否则将无法退出沉浸模式"
```

`app_en.arb`：
```json
  "navZoneSettingsTitle": "Navigation Zones",
  "navZoneSettingsPageTurnModeLabel": "Page Turn Method",
  "navZoneSettingsSimpleModeLabel": "Simple",
  "navZoneSettingsCustomModeLabel": "Custom",
  "navZoneSettingsShowDebugOverlayLabel": "Show zone guide overlay",
  "navZoneSettingsSaveCustomButton": "Save Custom Zone Settings",
  "navZoneActionPreviousPage": "Previous Page",
  "navZoneActionNextPage": "Next Page",
  "navZoneActionMenu": "Menu",
  "navZoneActionNone": "No Action",
  "navZoneCustomValidationError": "At least 1 cell must be set to \"Menu\", otherwise there will be no way to exit immersive mode"
```

`app_zh.arb`：
```json
  "navZoneSettingsTitle": "導航熱區",
  "navZoneSettingsPageTurnModeLabel": "翻頁方式",
  "navZoneSettingsSimpleModeLabel": "簡單",
  "navZoneSettingsCustomModeLabel": "自訂",
  "navZoneSettingsShowDebugOverlayLabel": "顯示熱區輔助線",
  "navZoneSettingsSaveCustomButton": "儲存自訂熱區設定",
  "navZoneActionPreviousPage": "上一頁",
  "navZoneActionNextPage": "下一頁",
  "navZoneActionMenu": "選單",
  "navZoneActionNone": "無動作",
  "navZoneCustomValidationError": "至少需要 1 格設為「選單」，否則將無法退出沉浸模式"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `nav_zone_settings_screen.dart`**

新增 import：
```dart
import '../l10n/app_localizations.dart';
```

`_actionLabel()`（`_NavZoneSettingsScreenState` 實例方法，第 121-132 行）：
```dart
  String _actionLabel(ZoneAction action) {
    final l10n = AppLocalizations.of(context)!;
    switch (action) {
      case ZoneAction.previousPage:
        return l10n.navZoneActionPreviousPage;
      case ZoneAction.nextPage:
        return l10n.navZoneActionNextPage;
      case ZoneAction.menu:
        return l10n.navZoneActionMenu;
      case ZoneAction.none:
        return l10n.navZoneActionNone;
    }
  }
```

`_saveCustomActions()`（第 102-119 行，僅驗證失敗分支需改）：
```dart
  void _saveCustomActions() {
    if (!isValidCustomZoneConfig(_customActions)) {
      setState(() {
        _validationError = AppLocalizations.of(context)!.navZoneCustomValidationError;
      });
      return;
    }
    // ...（其餘內容原樣不動）
```

`build()`（第 134-215 行），新增 `final l10n = AppLocalizations.of(context)!;` 並替換：
- 第 137 行 `appBar: AppBar(title: const Text('導航熱區')),` → `appBar: AppBar(title: Text(l10n.navZoneSettingsTitle)),`
- 第 150 行 `const Text('翻頁方式'),` → `Text(l10n.navZoneSettingsPageTurnModeLabel),`
- 第 154-157 行：
  ```dart
                        segments: [
                          ButtonSegment(value: false, label: Text(l10n.navZoneSettingsSimpleModeLabel)),
                          ButtonSegment(value: true, label: Text(l10n.navZoneSettingsCustomModeLabel)),
                        ],
  ```
  （移除該 `segments:` list 的 `const`，因子項不再是常數。）
- 第 208 行 `title: const Text('顯示熱區輔助線'),` → `title: Text(l10n.navZoneSettingsShowDebugOverlayLabel),`

`_buildCustomEditor()`（第 351-394 行，`_actionLabel()` 呼叫點原樣不動，只替換第 389 行）：
- 第 389 行 `child: const Text('儲存自訂熱區設定'),` → `child: Text(AppLocalizations.of(context)!.navZoneSettingsSaveCustomButton),`

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/nav_zone_settings_screen.dart`
Expected: No issues found!（此時測試檔尚未遷移，`flutter test test/screens/nav_zone_settings_screen_test.dart` 預期出現大量 `Null check operator` 失敗，留給 Task 3 處理，本 Step 不要求測試通過。）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/lib/l10n/
git commit -m "feat(epic-45): nav_zone_settings_screen.dart 字串抽取三語言在地化（production）"
```

---

### Task 3: `nav_zone_settings_screen_test.dart` 測試遷移

**Files:**
- Test: `app/test/screens/nav_zone_settings_screen_test.dart`（17 處裸 `MaterialApp(`）

**Interfaces:**
- Consumes：Task 2 完成的 `NavZoneSettingsScreen`（公開建構參數簽章不變）。

- [ ] **Step 1: 檔案頂部新增 import**

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

- [ ] **Step 2: 17 處 `MaterialApp(` 逐一補上三個 l10n 參數**

Run 先確認實際次數：`grep -c "MaterialApp(" test/screens/nav_zone_settings_screen_test.dart`（預期 17）。逐一在每個 `MaterialApp(` 後緊接插入：
```dart
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
```

實際範例（`nav_zone_settings_screen_test.dart:12-14`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(MaterialApp(
  home: NavZoneSettingsScreen(prefsManager: fakeManager),
));

// 修改後
await tester.pumpWidget(MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: NavZoneSettingsScreen(prefsManager: fakeManager),
));
```

其餘 16 處套用相同規則，不變動任何既有 `home: NavZoneSettingsScreen(...)` 建構參數或其後的斷言內容。

- [ ] **Step 3: 新增英文渲染驗證測試**

在檔案 `main()` 最後新增：
```dart
  testWidgets('英文介面下畫面標題與翻頁方式標籤正確以英文渲染', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Navigation Zones'), findsOneWidget);
    expect(find.text('Page Turn Method'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Show zone guide overlay'), findsOneWidget);
  });

  testWidgets('英文介面下自訂熱區九宮格動作文字正確以英文渲染', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    expect(find.text('Menu'), findsWidgets);
  });
```

> 若既有測試建構 `FakeReaderPrefsManager()`／`NavZoneSettingsScreen` 的寫法與檔案既有慣例不完全一致（例如需要預先 stub `loadGlobalPrefs()` 回傳值），改用該既有慣例，斷言邏輯不變。第二則測試點擊 `find.text('Custom')` 是為了從固定模板卡片切到「自訂」9 格編輯器，才能看到 `_actionLabel()` 渲染的動作文字——`nav_zone_template_toggle` 這個 Key 掛在整個 `SegmentedButton` 上，直接 `tap(find.byKey(...))` 命中的座標落在兩個 segment 分界線附近，不保證擊中「自訂」那個 segment；比照 `nav_zone_settings_screen_test.dart` 既有測試（`await tester.tap(find.text('自訂'));`）改用點擊 segment 文字本身，英文介面下對應文字即為 `'Custom'`。若既有測試已有更簡潔的切換方式（例如直接建構已是 `custom` 模式的 `GlobalReaderPrefs`），改用該既有方式。

- [ ] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/nav_zone_settings_screen_test.dart`
Expected: 全數通過（既有＋新增 2 個）。

- [ ] **Step 5: `grep` 驗證零殘留**

Run: `grep -c "localizationsDelegates: AppLocalizations.localizationsDelegates" test/screens/nav_zone_settings_screen_test.dart`
Expected: 19（17 既有＋2 新增）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze test/screens/nav_zone_settings_screen_test.dart`
Expected: No issues found!

- [ ] **Step 7: Commit**

```bash
git add app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "test(epic-45): nav_zone_settings_screen_test.dart 測試遷移＋新增英文渲染驗證"
```

---

### Task 4: `reading_defaults_screen.dart`（production）

**Files:**
- Modify: `app/lib/screens/reading_defaults_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readingDefaultsTitle`/`readingDefaultsVolumeKeyLabel`/`readingDefaultsPageTurnModeSectionTitle`/`readingDefaultsPaginatedLabel`/`readingDefaultsScrollLabel`/`readingDefaultsScreenOrientationSectionTitle`/`readingDefaultsOrientationAutoLabel`/`readingDefaultsOrientationLock0Label`/`readingDefaultsOrientationLock90Label`/`readingDefaultsOrientationLock180Label`/`readingDefaultsOrientationLock270Label`/`readingDefaultsTextConversionSectionTitle`/`readingDefaultsTextConversionOriginalLabel`/`readingDefaultsTextConversionTraditionalLabel`/`readingDefaultsTextConversionSimplifiedLabel`/`readingDefaultsFullscreenLabel`/`readingDefaultsOpenLastBookLabel`/`readingDefaultsShowHeaderLabel`/`readingDefaultsShowFooterLabel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readingDefaultsTitle": "閱讀預設值",
  "@readingDefaultsTitle": {
    "description": "閱讀預設值畫面 AppBar 標題"
  },
  "readingDefaultsVolumeKeyLabel": "音量鍵翻頁",
  "@readingDefaultsVolumeKeyLabel": {
    "description": "「音量鍵翻頁」開關標題"
  },
  "readingDefaultsPageTurnModeSectionTitle": "翻頁模式",
  "@readingDefaultsPageTurnModeSectionTitle": {
    "description": "「翻頁模式」（點擊/滾動）區塊標題"
  },
  "readingDefaultsPaginatedLabel": "點擊翻頁",
  "@readingDefaultsPaginatedLabel": {
    "description": "翻頁模式選項：點擊翻頁"
  },
  "readingDefaultsScrollLabel": "滾動翻頁",
  "@readingDefaultsScrollLabel": {
    "description": "翻頁模式選項：滾動翻頁"
  },
  "readingDefaultsScreenOrientationSectionTitle": "螢幕方向",
  "@readingDefaultsScreenOrientationSectionTitle": {
    "description": "「螢幕方向」區塊標題"
  },
  "readingDefaultsOrientationAutoLabel": "自動旋轉",
  "@readingDefaultsOrientationAutoLabel": {
    "description": "螢幕方向選項：自動旋轉"
  },
  "readingDefaultsOrientationLock0Label": "鎖定 0°",
  "@readingDefaultsOrientationLock0Label": {
    "description": "螢幕方向選項：鎖定 0 度"
  },
  "readingDefaultsOrientationLock90Label": "鎖定 90°",
  "@readingDefaultsOrientationLock90Label": {
    "description": "螢幕方向選項：鎖定 90 度"
  },
  "readingDefaultsOrientationLock180Label": "鎖定 180°",
  "@readingDefaultsOrientationLock180Label": {
    "description": "螢幕方向選項：鎖定 180 度"
  },
  "readingDefaultsOrientationLock270Label": "鎖定 270°",
  "@readingDefaultsOrientationLock270Label": {
    "description": "螢幕方向選項：鎖定 270 度"
  },
  "readingDefaultsTextConversionSectionTitle": "簡繁轉換顯示",
  "@readingDefaultsTextConversionSectionTitle": {
    "description": "「簡繁轉換顯示」區塊標題"
  },
  "readingDefaultsTextConversionOriginalLabel": "原文",
  "@readingDefaultsTextConversionOriginalLabel": {
    "description": "簡繁轉換選項：原文（不轉換）"
  },
  "readingDefaultsTextConversionTraditionalLabel": "轉換為繁體",
  "@readingDefaultsTextConversionTraditionalLabel": {
    "description": "簡繁轉換選項：轉換為繁體"
  },
  "readingDefaultsTextConversionSimplifiedLabel": "轉換為簡體",
  "@readingDefaultsTextConversionSimplifiedLabel": {
    "description": "簡繁轉換選項：轉換為簡體"
  },
  "readingDefaultsFullscreenLabel": "全螢幕模式",
  "@readingDefaultsFullscreenLabel": {
    "description": "「全螢幕模式」開關標題"
  },
  "readingDefaultsOpenLastBookLabel": "啟動時開啟最後閱讀的那本書",
  "@readingDefaultsOpenLastBookLabel": {
    "description": "「啟動時開啟最後閱讀的那本書」開關標題"
  },
  "readingDefaultsShowHeaderLabel": "顯示頁首",
  "@readingDefaultsShowHeaderLabel": {
    "description": "「顯示頁首」開關標題"
  },
  "readingDefaultsShowFooterLabel": "顯示頁尾",
  "@readingDefaultsShowFooterLabel": {
    "description": "「顯示頁尾」開關標題"
  }
```

`app_zh_CN.arb`：
```json
  "readingDefaultsTitle": "阅读预设值",
  "readingDefaultsVolumeKeyLabel": "音量键翻页",
  "readingDefaultsPageTurnModeSectionTitle": "翻页模式",
  "readingDefaultsPaginatedLabel": "点击翻页",
  "readingDefaultsScrollLabel": "滚动翻页",
  "readingDefaultsScreenOrientationSectionTitle": "屏幕方向",
  "readingDefaultsOrientationAutoLabel": "自动旋转",
  "readingDefaultsOrientationLock0Label": "锁定 0°",
  "readingDefaultsOrientationLock90Label": "锁定 90°",
  "readingDefaultsOrientationLock180Label": "锁定 180°",
  "readingDefaultsOrientationLock270Label": "锁定 270°",
  "readingDefaultsTextConversionSectionTitle": "简繁转换显示",
  "readingDefaultsTextConversionOriginalLabel": "原文",
  "readingDefaultsTextConversionTraditionalLabel": "转换为繁体",
  "readingDefaultsTextConversionSimplifiedLabel": "转换为简体",
  "readingDefaultsFullscreenLabel": "全屏幕模式",
  "readingDefaultsOpenLastBookLabel": "启动时打开最后阅读的那本书",
  "readingDefaultsShowHeaderLabel": "显示页首",
  "readingDefaultsShowFooterLabel": "显示页尾"
```

`app_en.arb`：
```json
  "readingDefaultsTitle": "Reading Defaults",
  "readingDefaultsVolumeKeyLabel": "Volume key page turn",
  "readingDefaultsPageTurnModeSectionTitle": "Page Turn Method",
  "readingDefaultsPaginatedLabel": "Tap to turn",
  "readingDefaultsScrollLabel": "Scroll to turn",
  "readingDefaultsScreenOrientationSectionTitle": "Screen Orientation",
  "readingDefaultsOrientationAutoLabel": "Auto-rotate",
  "readingDefaultsOrientationLock0Label": "Lock 0°",
  "readingDefaultsOrientationLock90Label": "Lock 90°",
  "readingDefaultsOrientationLock180Label": "Lock 180°",
  "readingDefaultsOrientationLock270Label": "Lock 270°",
  "readingDefaultsTextConversionSectionTitle": "Text Conversion Display",
  "readingDefaultsTextConversionOriginalLabel": "Original",
  "readingDefaultsTextConversionTraditionalLabel": "Convert to Traditional",
  "readingDefaultsTextConversionSimplifiedLabel": "Convert to Simplified",
  "readingDefaultsFullscreenLabel": "Fullscreen mode",
  "readingDefaultsOpenLastBookLabel": "Open the last read book on launch",
  "readingDefaultsShowHeaderLabel": "Show header",
  "readingDefaultsShowFooterLabel": "Show footer"
```

`app_zh.arb`：
```json
  "readingDefaultsTitle": "閱讀預設值",
  "readingDefaultsVolumeKeyLabel": "音量鍵翻頁",
  "readingDefaultsPageTurnModeSectionTitle": "翻頁模式",
  "readingDefaultsPaginatedLabel": "點擊翻頁",
  "readingDefaultsScrollLabel": "滾動翻頁",
  "readingDefaultsScreenOrientationSectionTitle": "螢幕方向",
  "readingDefaultsOrientationAutoLabel": "自動旋轉",
  "readingDefaultsOrientationLock0Label": "鎖定 0°",
  "readingDefaultsOrientationLock90Label": "鎖定 90°",
  "readingDefaultsOrientationLock180Label": "鎖定 180°",
  "readingDefaultsOrientationLock270Label": "鎖定 270°",
  "readingDefaultsTextConversionSectionTitle": "簡繁轉換顯示",
  "readingDefaultsTextConversionOriginalLabel": "原文",
  "readingDefaultsTextConversionTraditionalLabel": "轉換為繁體",
  "readingDefaultsTextConversionSimplifiedLabel": "轉換為簡體",
  "readingDefaultsFullscreenLabel": "全螢幕模式",
  "readingDefaultsOpenLastBookLabel": "啟動時開啟最後閱讀的那本書",
  "readingDefaultsShowHeaderLabel": "顯示頁首",
  "readingDefaultsShowFooterLabel": "顯示頁尾"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `reading_defaults_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()`（第 56-231 行）開頭新增 `final l10n = AppLocalizations.of(context)!;`，替換：
- 第 59 行 `appBar: AppBar(title: const Text('閱讀預設值')),` → `appBar: AppBar(title: Text(l10n.readingDefaultsTitle)),`
- 第 70 行 `title: const Text('音量鍵翻頁'),` → `title: Text(l10n.readingDefaultsVolumeKeyLabel),`
- 第 79 行 `_buildSectionHeader(context, '翻頁模式'),` → `_buildSectionHeader(context, l10n.readingDefaultsPageTurnModeSectionTitle),`
- 第 92 行 `title: const Text('點擊翻頁'),` → `title: Text(l10n.readingDefaultsPaginatedLabel),`
- 第 98 行 `title: const Text('滾動翻頁'),` → `title: Text(l10n.readingDefaultsScrollLabel),`
- 第 105 行 `_buildSectionHeader(context, '螢幕方向'),` → `_buildSectionHeader(context, l10n.readingDefaultsScreenOrientationSectionTitle),`
- 第 120 行 `title: const Text('自動旋轉'),` → `title: Text(l10n.readingDefaultsOrientationAutoLabel),`
- 第 126 行 `title: const Text('鎖定 0°'),` → `title: Text(l10n.readingDefaultsOrientationLock0Label),`
- 第 132 行 `title: const Text('鎖定 90°'),` → `title: Text(l10n.readingDefaultsOrientationLock90Label),`
- 第 138 行 `title: const Text('鎖定 180°'),` → `title: Text(l10n.readingDefaultsOrientationLock180Label),`
- 第 144 行 `title: const Text('鎖定 270°'),` → `title: Text(l10n.readingDefaultsOrientationLock270Label),`
- 第 151 行 `_buildSectionHeader(context, '簡繁轉換顯示'),` → `_buildSectionHeader(context, l10n.readingDefaultsTextConversionSectionTitle),`
- 第 163 行 `title: const Text('原文'),` → `title: Text(l10n.readingDefaultsTextConversionOriginalLabel),`
- 第 168 行 `title: const Text('轉換為繁體'),` → `title: Text(l10n.readingDefaultsTextConversionTraditionalLabel),`
- 第 173 行 `title: const Text('轉換為簡體'),` → `title: Text(l10n.readingDefaultsTextConversionSimplifiedLabel),`
- 第 182 行 `title: const Text('全螢幕模式'),` → `title: Text(l10n.readingDefaultsFullscreenLabel),`
- 第 193 行 `title: const Text('啟動時開啟最後閱讀的那本書'),` → `title: Text(l10n.readingDefaultsOpenLastBookLabel),`
- 第 206 行 `title: const Text('顯示頁首'),` → `title: Text(l10n.readingDefaultsShowHeaderLabel),`
- 第 219 行 `title: const Text('顯示頁尾'),` → `title: Text(l10n.readingDefaultsShowFooterLabel),`

`_buildSectionHeader()`（第 49-54 行）簽章與內容原樣不動（`String label` 參數，呼叫端已改傳已轉譯字串，不需要改這個方法本身）。

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reading_defaults_screen.dart`
Expected: No issues found!（測試檔尚未遷移，`flutter test` 預期紅燈，留給 Task 5。）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reading_defaults_screen.dart app/lib/l10n/
git commit -m "feat(epic-45): reading_defaults_screen.dart 字串抽取三語言在地化（production）"
```

---

### Task 5: `reading_defaults_screen_test.dart` 測試遷移

**Files:**
- Test: `app/test/screens/reading_defaults_screen_test.dart`（14 處裸 `MaterialApp(`）

**Interfaces:**
- Consumes：Task 4 完成的 `ReadingDefaultsScreen`（公開建構參數簽章不變）。

- [ ] **Step 1: 檔案頂部新增 import**

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

- [ ] **Step 2: 14 處 `MaterialApp(` 逐一補上三個 l10n 參數**

Run 先確認實際次數：`grep -c "MaterialApp(" test/screens/reading_defaults_screen_test.dart`（預期 14）。逐一補上：
```dart
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
```

實際範例（`reading_defaults_screen_test.dart:24-26`）：
```dart
// 修改前
await tester.pumpWidget(MaterialApp(
  home: ReadingDefaultsScreen(prefsManager: fakeManager),
));

// 修改後
await tester.pumpWidget(MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: ReadingDefaultsScreen(prefsManager: fakeManager),
));
```

其餘 13 處套用相同規則。

- [ ] **Step 3: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下四個分區標題與選項標籤正確以英文渲染', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Reading Defaults'), findsOneWidget);
    expect(find.text('Volume key page turn'), findsOneWidget);
    expect(find.text('Page Turn Method'), findsOneWidget);
    expect(find.text('Tap to turn'), findsOneWidget);
    expect(find.text('Scroll to turn'), findsOneWidget);
    expect(find.text('Screen Orientation'), findsOneWidget);
    expect(find.text('Auto-rotate'), findsOneWidget);
    expect(find.text('Text Conversion Display'), findsOneWidget);
    expect(find.text('Convert to Traditional'), findsOneWidget);
    expect(find.text('Convert to Simplified'), findsOneWidget);
    expect(find.text('Fullscreen mode'), findsOneWidget);
    expect(find.text('Open the last read book on launch'), findsOneWidget);
    expect(find.text('Show header'), findsOneWidget);
    expect(find.text('Show footer'), findsOneWidget);
  });
```

> 若既有測試建構 `FakeReaderPrefsManager()` 的方式與檔案既有慣例不完全一致，改用該既有慣例。

- [ ] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/reading_defaults_screen_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [ ] **Step 5: `grep` 驗證零殘留**

Run: `grep -c "localizationsDelegates: AppLocalizations.localizationsDelegates" test/screens/reading_defaults_screen_test.dart`
Expected: 15（14 既有＋1 新增）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze test/screens/reading_defaults_screen_test.dart`
Expected: No issues found!

- [ ] **Step 7: Commit**

```bash
git add app/test/screens/reading_defaults_screen_test.dart
git commit -m "test(epic-45): reading_defaults_screen_test.dart 測試遷移＋新增英文渲染驗證"
```

---

### Task 6: `tts_defaults_screen.dart`（production ＋ 測試，9 處合併同一 Task）

**Files:**
- Modify: `app/lib/screens/tts_defaults_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/tts_defaults_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `ttsDefaultsTitle`/`ttsDefaultsVoiceSectionTitle`/`ttsDefaultsVoiceUnavailableHint`/`ttsDefaultsSpeedSectionTitle`。

**計劃範圍澄清**：語速數值文字（`'${...}x'`／Slider `label`）為純數字＋固定後綴 `x` 格式，不含任何語意詞彙，不需要翻譯，原樣保留（Task 7 `_formatLastSyncedAt()` 以外，本 Issue 唯一涉及數字格式化的地方，但不涉及 `DateFormat`／ICU plural，維持既有 `toStringAsFixed()` 寫法不動）。`voice.displayName` 是系統/裝置提供的 TTS 語音顯示名稱（例如廠商語音包名稱），屬使用者裝置資料，不翻譯。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "ttsDefaultsTitle": "朗讀語音與語速",
  "@ttsDefaultsTitle": {
    "description": "朗讀預設值畫面 AppBar 標題"
  },
  "ttsDefaultsVoiceSectionTitle": "語音",
  "@ttsDefaultsVoiceSectionTitle": {
    "description": "「語音」選擇區塊標題"
  },
  "ttsDefaultsVoiceUnavailableHint": "目前裝置未安裝或不支援語音選擇",
  "@ttsDefaultsVoiceUnavailableHint": {
    "description": "裝置沒有可用 TTS 引擎或語音清單為空時顯示的提示文字"
  },
  "ttsDefaultsSpeedSectionTitle": "語速",
  "@ttsDefaultsSpeedSectionTitle": {
    "description": "「語速」調整區塊標題"
  }
```

`app_zh_CN.arb`：
```json
  "ttsDefaultsTitle": "朗读语音与语速",
  "ttsDefaultsVoiceSectionTitle": "语音",
  "ttsDefaultsVoiceUnavailableHint": "目前装置未安装或不支持语音选择",
  "ttsDefaultsSpeedSectionTitle": "语速"
```

`app_en.arb`：
```json
  "ttsDefaultsTitle": "Read-Aloud Voice & Speed",
  "ttsDefaultsVoiceSectionTitle": "Voice",
  "ttsDefaultsVoiceUnavailableHint": "No voice is installed or supported on this device",
  "ttsDefaultsSpeedSectionTitle": "Speed"
```

`app_zh.arb`：
```json
  "ttsDefaultsTitle": "朗讀語音與語速",
  "ttsDefaultsVoiceSectionTitle": "語音",
  "ttsDefaultsVoiceUnavailableHint": "目前裝置未安裝或不支援語音選擇",
  "ttsDefaultsSpeedSectionTitle": "語速"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `tts_defaults_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()`（第 62-218 行）開頭新增 `final l10n = AppLocalizations.of(context)!;`，替換：
- 第 64 行 `appBar: AppBar(title: const Text('朗讀語音與語速')),` → `appBar: AppBar(title: Text(l10n.ttsDefaultsTitle)),`
- 第 73 行 `const EBSectionHeader(title: '語音'),` → `EBSectionHeader(title: l10n.ttsDefaultsVoiceSectionTitle),`
- 第 78-82 行：
  ```dart
                  Padding(
                    key: const Key('tts_defaults_voice_unavailable_hint'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(l10n.ttsDefaultsVoiceUnavailableHint),
                  )
  ```
  （原本 `const Padding(...)` 因子項不再是常數，移除該層 `const`。）
- 第 107 行 `const EBSectionHeader(title: '語速'),` → `EBSectionHeader(title: l10n.ttsDefaultsSpeedSectionTitle),`

- [ ] **Step 4: 遷移既有測試檔（9 處 `MaterialApp(`）**

`app/test/screens/tts_defaults_screen_test.dart` 新增 import `package:elinkbook/l10n/app_localizations.dart`，9 處 `MaterialApp(` 逐一補上 `locale: const Locale('zh', 'TW')`/`localizationsDelegates`/`supportedLocales`（同前述 Task 範例規則）。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題與分區標題正確以英文渲染', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Read-Aloud Voice & Speed'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('No voice is installed or supported on this device'),
        findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
  });
```

> `ttsProvider` 未提供時（預設 `null`）會走「不可用提示」分支，若既有測試需要明確傳入 `ttsProvider: null` 或某個 Fake 才能重現此分支，比照既有測試檔慣例調整；`isEinkMode` 保留預設 `false`。

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/tts_defaults_screen_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/tts_defaults_screen.dart test/screens/tts_defaults_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/tts_defaults_screen.dart app/test/screens/tts_defaults_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): tts_defaults_screen.dart 字串抽取三語言在地化"
```

---

### Task 7: `sync_settings_screen.dart`（production ＋ 測試，10 處合併同一 Task，含 `DateFormat`）

**Files:**
- Modify: `app/lib/screens/sync_settings_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/sync_settings_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `syncSettingsTitle`/`syncSettingsSyncFailedMessage`/`syncSettingsNeverSynced`/`syncSettingsLastSyncedAt`/`syncSettingsConnectionFailedMessage`/`syncSettingsLoggedInAs`/`syncSettingsManualSyncButton`/`syncSettingsLogoutButton`/`syncSettingsServerUrlLabel`/`syncSettingsPasswordLabel`/`syncSettingsShowPasswordTooltip`/`syncSettingsHidePasswordTooltip`/`syncSettingsConnectButton`。

**計劃範圍澄清（`_formatLastSyncedAt()` 日期格式化重構）**：`issues.md` 記載的既有程式碼註解「不引入 `intl` 套件——只有這一處需要格式化，手動拼接即可」——`intl` 已是本 Epic 全域依賴（見 `pubspec.yaml`），改用 `DateFormat.yMd(locale).add_Hm()` 依目前介面語言格式化絕對日期時間（Q9 決策：不用相對時間，本次不變動）。`Email` 欄位的 `labelText: 'Email'` 字面值本身即為英文單詞、非中文，三語言皆維持原樣不翻譯，本 Task 不處理。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "syncSettingsTitle": "同步",
  "@syncSettingsTitle": {
    "description": "同步設定畫面 AppBar 標題"
  },
  "syncSettingsSyncFailedMessage": "同步失敗，請確認網路連線",
  "@syncSettingsSyncFailedMessage": {
    "description": "手動觸發「立即同步」失敗時的 SnackBar 訊息"
  },
  "syncSettingsNeverSynced": "尚未同步過",
  "@syncSettingsNeverSynced": {
    "description": "尚未有任何一次成功同步紀錄時顯示的文字"
  },
  "syncSettingsLastSyncedAt": "最後同步：{formatted}",
  "@syncSettingsLastSyncedAt": {
    "description": "最後同步時間顯示，{formatted} 為已依目前介面語言格式化的日期時間字串（DateFormat.yMd(locale).add_Hm() 的結果）",
    "placeholders": {
      "formatted": {
        "type": "String"
      }
    }
  },
  "syncSettingsConnectionFailedMessage": "連線失敗，請確認伺服器網址與帳號密碼是否正確",
  "@syncSettingsConnectionFailedMessage": {
    "description": "登入/連線測試失敗時顯示的錯誤文字"
  },
  "syncSettingsLoggedInAs": "已登入：{email}",
  "@syncSettingsLoggedInAs": {
    "description": "已登入狀態顯示目前登入帳號的 email，{email} 為使用者資料不翻譯",
    "placeholders": {
      "email": {
        "type": "String"
      }
    }
  },
  "syncSettingsManualSyncButton": "立即同步",
  "@syncSettingsManualSyncButton": {
    "description": "「立即同步」按鈕文字"
  },
  "syncSettingsLogoutButton": "登出",
  "@syncSettingsLogoutButton": {
    "description": "「登出」按鈕文字"
  },
  "syncSettingsServerUrlLabel": "伺服器網址",
  "@syncSettingsServerUrlLabel": {
    "description": "伺服器網址輸入欄位標籤"
  },
  "syncSettingsPasswordLabel": "密碼",
  "@syncSettingsPasswordLabel": {
    "description": "密碼輸入欄位標籤"
  },
  "syncSettingsShowPasswordTooltip": "顯示密碼",
  "@syncSettingsShowPasswordTooltip": {
    "description": "密碼欄位「顯示密碼」眼睛圖示按鈕提示文字（目前為隱藏狀態）"
  },
  "syncSettingsHidePasswordTooltip": "隱藏密碼",
  "@syncSettingsHidePasswordTooltip": {
    "description": "密碼欄位「隱藏密碼」眼睛圖示按鈕提示文字（目前為顯示狀態）"
  },
  "syncSettingsConnectButton": "連線／登入",
  "@syncSettingsConnectButton": {
    "description": "未登入表單「連線／登入」按鈕文字"
  }
```

`app_zh_CN.arb`：
```json
  "syncSettingsTitle": "同步",
  "syncSettingsSyncFailedMessage": "同步失败，请确认网络连线",
  "syncSettingsNeverSynced": "尚未同步过",
  "syncSettingsLastSyncedAt": "最后同步：{formatted}",
  "syncSettingsConnectionFailedMessage": "连线失败，请确认服务器网址与账号密码是否正确",
  "syncSettingsLoggedInAs": "已登入：{email}",
  "syncSettingsManualSyncButton": "立即同步",
  "syncSettingsLogoutButton": "登出",
  "syncSettingsServerUrlLabel": "服务器网址",
  "syncSettingsPasswordLabel": "密码",
  "syncSettingsShowPasswordTooltip": "显示密码",
  "syncSettingsHidePasswordTooltip": "隐藏密码",
  "syncSettingsConnectButton": "连线／登入"
```

`app_en.arb`：
```json
  "syncSettingsTitle": "Sync",
  "syncSettingsSyncFailedMessage": "Sync failed. Please check your network connection.",
  "syncSettingsNeverSynced": "Never synced",
  "syncSettingsLastSyncedAt": "Last synced: {formatted}",
  "syncSettingsConnectionFailedMessage": "Connection failed. Please check the server URL and your credentials.",
  "syncSettingsLoggedInAs": "Signed in as: {email}",
  "syncSettingsManualSyncButton": "Sync Now",
  "syncSettingsLogoutButton": "Sign Out",
  "syncSettingsServerUrlLabel": "Server URL",
  "syncSettingsPasswordLabel": "Password",
  "syncSettingsShowPasswordTooltip": "Show password",
  "syncSettingsHidePasswordTooltip": "Hide password",
  "syncSettingsConnectButton": "Connect / Sign In"
```

`app_zh.arb`：
```json
  "syncSettingsTitle": "同步",
  "syncSettingsSyncFailedMessage": "同步失敗，請確認網路連線",
  "syncSettingsNeverSynced": "尚未同步過",
  "syncSettingsLastSyncedAt": "最後同步：{formatted}",
  "syncSettingsConnectionFailedMessage": "連線失敗，請確認伺服器網址與帳號密碼是否正確",
  "syncSettingsLoggedInAs": "已登入：{email}",
  "syncSettingsManualSyncButton": "立即同步",
  "syncSettingsLogoutButton": "登出",
  "syncSettingsServerUrlLabel": "伺服器網址",
  "syncSettingsPasswordLabel": "密碼",
  "syncSettingsShowPasswordTooltip": "顯示密碼",
  "syncSettingsHidePasswordTooltip": "隱藏密碼",
  "syncSettingsConnectButton": "連線／登入"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `sync_settings_screen.dart`**

新增 import：
```dart
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
```

`_manualSync()`（第 82-99 行，僅失敗分支）：
```dart
    } else {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.syncSettingsSyncFailedMessage)),
      );
    }
```

`_formatLastSyncedAt()`（第 101-111 行，改用 `DateFormat` 並依語言在地化）：
```dart
  /// 絕對日期時間格式（Q9 決策：不用相對時間，避免畫面停留很久後文字
  /// 顯得不準確），依目前介面語言格式化（`DateFormat.yMd(locale).add_Hm()`）。
  String _formatLastSyncedAt(AppLocalizations l10n) {
    final millis = _lastSyncedAtMillis;
    if (millis == null) return l10n.syncSettingsNeverSynced;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final locale = Localizations.localeOf(context).toString();
    final formatted = DateFormat.yMd(locale).add_Hm().format(dt);
    return l10n.syncSettingsLastSyncedAt(formatted);
  }
```

`_connect()`（第 113-137 行，僅失敗分支）：
```dart
    } else {
      setState(() {
        _connecting = false;
        _errorText = AppLocalizations.of(context)!.syncSettingsConnectionFailedMessage;
      });
    }
```

`build()`（第 150-165 行）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncSettingsTitle)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('sync_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoggedIn
                  ? _buildLoggedInView(l10n)
                  : _buildLoginForm(l10n),
            ),
    );
  }
```

`_buildLoggedInView()`（第 167-200 行，新增 `AppLocalizations l10n` 參數）：
```dart
  Widget _buildLoggedInView(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.syncSettingsLoggedInAs(_loggedInEmail ?? ''),
          key: const Key('sync_settings_logged_in_email'),
        ),
        const SizedBox(height: 16),
        Text(
          _formatLastSyncedAt(l10n),
          key: const Key('sync_settings_last_synced_text'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('sync_settings_manual_sync_button'),
          onPressed: _syncing ? null : _manualSync,
          child: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.syncSettingsManualSyncButton),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('sync_settings_logout_button'),
          onPressed: _logout,
          child: Text(l10n.syncSettingsLogoutButton),
        ),
      ],
    );
  }
```

`_buildLoginForm()`（第 202-261 行，新增 `AppLocalizations l10n` 參數，`Email` 欄位維持原樣）：
```dart
  Widget _buildLoginForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('sync_settings_base_url_field'),
          controller: _baseUrlController,
          decoration: InputDecoration(labelText: l10n.syncSettingsServerUrlLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_email_field'),
          controller: _emailController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_password_field'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.syncSettingsPasswordLabel,
            suffixIcon: IconButton(
              key: const Key('sync_settings_password_visibility_toggle'),
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              tooltip: _obscurePassword
                  ? l10n.syncSettingsShowPasswordTooltip
                  : l10n.syncSettingsHidePasswordTooltip,
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _errorText!,
              key: const Key('sync_settings_error_text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ElevatedButton(
          key: const Key('sync_settings_connect_button'),
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.syncSettingsConnectButton),
        ),
      ],
    );
  }
```

- [ ] **Step 4: 遷移既有測試檔（10 處 `MaterialApp(`）**

`app/test/screens/sync_settings_screen_test.dart` 新增 import `package:elinkbook/l10n/app_localizations.dart`，10 處 `MaterialApp(` 逐一補上三個 l10n 參數。若既有測試斷言「最後同步：」相關文字（例如組合出 `'最後同步：2026-3-15 14:30'` 這類字串），確認斷言值改用 `DateFormat.yMd('zh_TW').add_Hm().format(dt)` 實際格式化結果重新核對（`zh_TW` 下 `DateFormat.yMd()` 輸出為 `2026/3/15` 而非原手動拼接的 `2026-03-15`——日期分隔符號與月/日補零方式皆改變，需要逐一核對既有斷言字面值並更新為 `DateFormat` 實際輸出，不可假設與手動拼接版本相同）。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下已登入畫面文字正確以英文渲染，最後同步時間為英文日期格式',
      (tester) async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'user@example.com',
    );
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: () async =>
            DateTime(2026, 3, 15, 14, 30).millisecondsSinceEpoch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Signed in as: user@example.com'), findsOneWidget);
    expect(find.textContaining('Last synced: 3/15/2026'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });
```

（**計劃審查修正（`review-plan-issue-5.md` I-2）**：本檔案不存在 `FakeSyncAccountRepository`／`FakeSyncClient` 這兩個類別——查證 `sync_settings_screen_test.dart` 既有 `setUp()` 已建構真實 `accountRepository = SyncAccountRepository();`（背後接的是記憶體版 `TestFlutterSecureStoragePlatform`，非真正的裝置安全儲存），已登入狀態一律透過 `accountRepository.saveCredentials(authToken:, userId:, email:)`〔`sync_account_repository.dart:70-78` 實際簽章，**不是** `email`/`password`/`token`/`recordId`〕設定；`syncClient` 透過檔案內既有的 `buildClient(MockClient mockClient) => SyncClient(accountRepository: accountRepository, clientFactory: ...)` helper 建構。上方範例已改用這些既有真實物件，不再引用不存在的假類別。）

> `DateFormat.yMd('en').add_Hm()` 對 `DateTime(2026, 3, 15, 14, 30)` 的實際輸出格式（月/日/年 + 時:分）請執行後以實際結果核對斷言，若與本計畫預期的 `'3/15/2026'` 不完全一致（例如含 `2:30 PM` 時間後綴），依實際輸出調整 `findsOneWidget` 斷言的比對字串，斷言邏輯（驗證日期確實依英文慣例格式化，非驗證特定 minute 顯示細節）不變。

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/sync_settings_screen_test.dart`
Expected: 全數通過（含既有「最後同步」相關斷言更新後，＋新增 1 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/sync_settings_screen.dart test/screens/sync_settings_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/sync_settings_screen.dart app/test/screens/sync_settings_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): sync_settings_screen.dart 字串抽取三語言在地化（含 DateFormat 重構）"
```

---

### Task 8: `cloud_account_settings_screen.dart`（production ＋ 測試，6 處合併同一 Task）

**Files:**
- Modify: `app/lib/screens/cloud_account_settings_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/cloud_account_settings_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `cloudAccountSettingsTitle`/`cloudAccountSettingsLinkedEmail`/`cloudAccountSettingsUnlinkButton`/`cloudAccountSettingsUnlinkedText`/`cloudAccountSettingsLinkButton`。

**計劃範圍澄清**：`_buildProviderTile({required String title, ...})` 的 `title` 參數（呼叫端固定傳入 `'Google Drive'`／`'OneDrive'`）為雲端服務商品牌名，`design.md` 明文排除，維持原樣不動、不新增對應 key。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "cloudAccountSettingsTitle": "已連結的雲端匯入帳戶",
  "@cloudAccountSettingsTitle": {
    "description": "已連結的雲端匯入帳戶畫面 AppBar 標題"
  },
  "cloudAccountSettingsLinkedEmail": "已連結：{email}",
  "@cloudAccountSettingsLinkedEmail": {
    "description": "雲端服務已連結狀態顯示的帳號 email，{email} 為使用者資料不翻譯",
    "placeholders": {
      "email": {
        "type": "String"
      }
    }
  },
  "cloudAccountSettingsUnlinkButton": "解除連結",
  "@cloudAccountSettingsUnlinkButton": {
    "description": "「解除連結」按鈕文字"
  },
  "cloudAccountSettingsUnlinkedText": "未連結",
  "@cloudAccountSettingsUnlinkedText": {
    "description": "雲端服務尚未連結狀態顯示文字"
  },
  "cloudAccountSettingsLinkButton": "連結",
  "@cloudAccountSettingsLinkButton": {
    "description": "「連結」按鈕文字"
  }
```

`app_zh_CN.arb`：
```json
  "cloudAccountSettingsTitle": "已链接的云端导入账户",
  "cloudAccountSettingsLinkedEmail": "已链接：{email}",
  "cloudAccountSettingsUnlinkButton": "解除链接",
  "cloudAccountSettingsUnlinkedText": "未链接",
  "cloudAccountSettingsLinkButton": "链接"
```

`app_en.arb`：
```json
  "cloudAccountSettingsTitle": "Linked Cloud Import Accounts",
  "cloudAccountSettingsLinkedEmail": "Linked: {email}",
  "cloudAccountSettingsUnlinkButton": "Unlink",
  "cloudAccountSettingsUnlinkedText": "Not linked",
  "cloudAccountSettingsLinkButton": "Link"
```

`app_zh.arb`：
```json
  "cloudAccountSettingsTitle": "已連結的雲端匯入帳戶",
  "cloudAccountSettingsLinkedEmail": "已連結：{email}",
  "cloudAccountSettingsUnlinkButton": "解除連結",
  "cloudAccountSettingsUnlinkedText": "未連結",
  "cloudAccountSettingsLinkButton": "連結"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `cloud_account_settings_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()`（第 118-155 行）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudAccountSettingsTitle)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('cloud_account_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProviderTile(
                    l10n,
                    title: 'Google Drive',
                    keyPrefix: 'google_drive',
                    linked: _googleDriveLinked,
                    linking: _googleDriveLinking,
                    email: _googleDriveEmail,
                    onLink: _linkGoogleDrive,
                    onUnlink: _unlinkGoogleDrive,
                  ),
                  const SizedBox(height: 24),
                  _buildProviderTile(
                    l10n,
                    title: 'OneDrive',
                    keyPrefix: 'onedrive',
                    linked: _oneDriveLinked,
                    linking: _oneDriveLinking,
                    email: _oneDriveEmail,
                    onLink: _linkOneDrive,
                    onUnlink: _unlinkOneDrive,
                  ),
                ],
              ),
            ),
    );
  }
```

`_buildProviderTile()`（第 162-207 行，新增 `AppLocalizations l10n` 位置參數）：
```dart
  Widget _buildProviderTile(
    AppLocalizations l10n, {
    required String title,
    required String keyPrefix,
    required bool linked,
    required bool linking,
    required String? email,
    required VoidCallback onLink,
    required VoidCallback onUnlink,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (linked) ...[
          Text(
            l10n.cloudAccountSettingsLinkedEmail(email ?? ''),
            key: Key('cloud_account_settings_${keyPrefix}_linked_email'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_unlink_button'),
            onPressed: onUnlink,
            child: Text(l10n.cloudAccountSettingsUnlinkButton),
          ),
        ] else ...[
          Text(
            l10n.cloudAccountSettingsUnlinkedText,
            key: Key('cloud_account_settings_${keyPrefix}_unlinked_text'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_link_button'),
            onPressed: linking ? null : onLink,
            child: linking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.cloudAccountSettingsLinkButton),
          ),
        ],
      ],
    );
  }
```

- [ ] **Step 4: 遷移既有測試檔（6 處 `MaterialApp(`）**

`app/test/screens/cloud_account_settings_screen_test.dart` 新增 import `package:elinkbook/l10n/app_localizations.dart`，6 處 `MaterialApp(` 逐一補上三個 l10n 參數。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下已連結/未連結狀態文字正確以英文渲染', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'user@gmail.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Linked Cloud Import Accounts'), findsOneWidget);
    expect(find.text('Linked: user@gmail.com'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });
```

（**計劃審查修正（`review-plan-issue-5.md` I-1）**：本專案不存在 `FakeGoogleDriveOAuthClient`／`FakeOneDriveOAuthClient`，且 `FakeCloudAccountRepository` 只有無參數建構子（`test/support/fake_cloud_account_repository.dart:7`），連結狀態一律透過 `await repository.link(CloudProvider provider, CloudAccountTokens tokens)` 設定。既有測試對 OAuth client 一律使用真實類別＋假 repository 的組合：`GoogleDriveOAuthClient(accountRepository: fakeRepository)`／`OneDriveOAuthClient(accountRepository: fakeRepository)`（兩者預設會建構真正的 `http.Client()`，但本測試只渲染畫面、不點擊「連結」／「解除連結」按鈕觸發真實網路請求，故安全）。上方範例已改用這些既有真實物件。）

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/cloud_account_settings_screen_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/cloud_account_settings_screen.dart test/screens/cloud_account_settings_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/cloud_account_settings_screen.dart app/test/screens/cloud_account_settings_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): cloud_account_settings_screen.dart 字串抽取三語言在地化"
```

---

### Task 9: `font_management_screen.dart`（production ＋ 測試，1 處合併同一 Task，含 ICU plural 與頂層函式簽章變更）

**Files:**
- Modify: `app/lib/screens/font_management_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/font_management_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`/`confirm`（既有共用 key）。
- Produces：ARB key `fontManagementTitle`/`fontManagementUploadTooltip`/`fontManagementBuiltInSectionLabel`/`fontManagementCustomSectionLabel`/`fontManagementNoCustomFontsHint`/`fontManagementRenameTooltip`/`fontManagementDeleteTooltip`/`fontManagementRenameDialogTitle`/`fontManagementDeleteConfirmTitle`/`fontManagementDeleteConfirmMessage`/`fontManagementUploadBothMessage`/`fontManagementUploadAddedOnlyMessage`/`fontManagementUploadSkippedOnlyMessage`。

**計劃範圍澄清（架構必要偏離）**：`buildUploadResultMessage({required int addedCount, required int skippedCount})` 是本檔案的**頂層純函式**（非 `State` 方法），沒有 `BuildContext` 可用，且被 `font_management_screen_test.dart` 一個不經過 widget tree 的 `test()`（非 `testWidgets()`）純邏輯測試直接呼叫並斷言回傳字串。本 Task 為它新增 `required AppLocalizations l10n` 具名參數——production 呼叫端（`_pickAndUploadFonts()`）傳入 `AppLocalizations.of(context)!`；純單元測試呼叫端改傳入 `gen-l10n` 生成的具體語言子類別（`AppLocalizationsZhTw()`/`AppLocalizationsEn()`，兩者皆可直接建構、不需要 widget tree／`BuildContext`）。`_builtInDisplayName()` 是 `_FontManagementScreenState` 實例方法，`context` 直接可用，不需要改簽章。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "fontManagementTitle": "字型管理",
  "@fontManagementTitle": {
    "description": "字型管理畫面 AppBar 標題"
  },
  "fontManagementUploadTooltip": "上傳字型",
  "@fontManagementUploadTooltip": {
    "description": "AppBar「上傳字型」按鈕的無障礙提示文字"
  },
  "fontManagementBuiltInSectionLabel": "內建字型",
  "@fontManagementBuiltInSectionLabel": {
    "description": "「內建字型」區塊標籤"
  },
  "fontManagementCustomSectionLabel": "自訂字型",
  "@fontManagementCustomSectionLabel": {
    "description": "「自訂字型」區塊標籤"
  },
  "fontManagementNoCustomFontsHint": "尚未上傳任何自訂字型",
  "@fontManagementNoCustomFontsHint": {
    "description": "使用者尚未上傳任何自訂字型時的空狀態提示文字"
  },
  "fontManagementRenameTooltip": "重新命名",
  "@fontManagementRenameTooltip": {
    "description": "自訂字型項目「重新命名」按鈕的無障礙提示文字，同時是重新命名對話框標題（共用同一 key）"
  },
  "fontManagementDeleteTooltip": "刪除",
  "@fontManagementDeleteTooltip": {
    "description": "自訂字型項目「刪除」按鈕的無障礙提示文字，同時是刪除確認對話框確認按鈕文字（共用同一 key）"
  },
  "fontManagementRenameDialogTitle": "重新命名",
  "@fontManagementRenameDialogTitle": {
    "description": "重新命名對話框標題（與 fontManagementRenameTooltip 文字相同，但語意角色不同，各自獨立宣告以便未來調整不互相牽動）"
  },
  "fontManagementDeleteConfirmTitle": "確定要刪除「{fontName}」嗎？",
  "@fontManagementDeleteConfirmTitle": {
    "description": "刪除自訂字型確認對話框標題，{fontName} 為使用者自訂的字型顯示名稱（不翻譯）",
    "placeholders": {
      "fontName": {
        "type": "String"
      }
    }
  },
  "fontManagementDeleteConfirmMessage": "{usageCount, plural, =1{目前有 1 本書使用此字型，刪除後將自動改用預設字型} other{目前有 {usageCount} 本書使用此字型，刪除後將自動改用預設字型}}",
  "@fontManagementDeleteConfirmMessage": {
    "description": "刪除自訂字型時，若有書籍正在使用該字型顯示的警告文字，{usageCount} 為使用中的書籍數",
    "placeholders": {
      "usageCount": {
        "type": "int"
      }
    }
  },
  "fontManagementUploadBothMessage": "{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}，{skippedCount, plural, =1{1 款已存在已跳過} other{{skippedCount} 款已存在已跳過}}",
  "@fontManagementUploadBothMessage": {
    "description": "批次上傳字型結果訊息：同時有新增與跳過的情境，{addedCount}／{skippedCount} 各自獨立處理單複數",
    "placeholders": {
      "addedCount": {
        "type": "int"
      },
      "skippedCount": {
        "type": "int"
      }
    }
  },
  "fontManagementUploadAddedOnlyMessage": "{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}",
  "@fontManagementUploadAddedOnlyMessage": {
    "description": "批次上傳字型結果訊息：全部成功新增、沒有跳過的情境",
    "placeholders": {
      "addedCount": {
        "type": "int"
      }
    }
  },
  "fontManagementUploadSkippedOnlyMessage": "{skippedCount, plural, =1{1 款字型已存在，已跳過} other{{skippedCount} 款字型已存在，已跳過}}",
  "@fontManagementUploadSkippedOnlyMessage": {
    "description": "批次上傳字型結果訊息：全部跳過、沒有新增成功的情境",
    "placeholders": {
      "skippedCount": {
        "type": "int"
      }
    }
  }
```

`app_zh_CN.arb`：
```json
  "fontManagementTitle": "字体管理",
  "fontManagementUploadTooltip": "上传字体",
  "fontManagementBuiltInSectionLabel": "内建字体",
  "fontManagementCustomSectionLabel": "自定义字体",
  "fontManagementNoCustomFontsHint": "尚未上传任何自定义字体",
  "fontManagementRenameTooltip": "重新命名",
  "fontManagementDeleteTooltip": "删除",
  "fontManagementRenameDialogTitle": "重新命名",
  "fontManagementDeleteConfirmTitle": "确定要删除「{fontName}」吗？",
  "fontManagementDeleteConfirmMessage": "{usageCount, plural, =1{目前有 1 本书使用此字体，删除后将自动改用预设字体} other{目前有 {usageCount} 本书使用此字体，删除后将自动改用预设字体}}",
  "fontManagementUploadBothMessage": "{addedCount, plural, =1{已新增 1 款字体} other{已新增 {addedCount} 款字体}}，{skippedCount, plural, =1{1 款已存在已跳过} other{{skippedCount} 款已存在已跳过}}",
  "fontManagementUploadAddedOnlyMessage": "{addedCount, plural, =1{已新增 1 款字体} other{已新增 {addedCount} 款字体}}",
  "fontManagementUploadSkippedOnlyMessage": "{skippedCount, plural, =1{1 款字体已存在，已跳过} other{{skippedCount} 款字体已存在，已跳过}}"
```

`app_en.arb`：
```json
  "fontManagementTitle": "Font Management",
  "fontManagementUploadTooltip": "Upload font",
  "fontManagementBuiltInSectionLabel": "Built-in Fonts",
  "fontManagementCustomSectionLabel": "Custom Fonts",
  "fontManagementNoCustomFontsHint": "No custom fonts uploaded yet",
  "fontManagementRenameTooltip": "Rename",
  "fontManagementDeleteTooltip": "Delete",
  "fontManagementRenameDialogTitle": "Rename",
  "fontManagementDeleteConfirmTitle": "Delete \"{fontName}\"?",
  "fontManagementDeleteConfirmMessage": "{usageCount, plural, =1{1 book currently uses this font. It will fall back to the default font after deletion.} other{{usageCount} books currently use this font. They will fall back to the default font after deletion.}}",
  "fontManagementUploadBothMessage": "{addedCount, plural, =1{Added 1 font} other{Added {addedCount} fonts}}, {skippedCount, plural, =1{1 already exists and was skipped} other{{skippedCount} already exist and were skipped}}",
  "fontManagementUploadAddedOnlyMessage": "{addedCount, plural, =1{Added 1 font} other{Added {addedCount} fonts}}",
  "fontManagementUploadSkippedOnlyMessage": "{skippedCount, plural, =1{1 font already exists and was skipped} other{{skippedCount} fonts already exist and were skipped}}"
```

`app_zh.arb`：
```json
  "fontManagementTitle": "字型管理",
  "fontManagementUploadTooltip": "上傳字型",
  "fontManagementBuiltInSectionLabel": "內建字型",
  "fontManagementCustomSectionLabel": "自訂字型",
  "fontManagementNoCustomFontsHint": "尚未上傳任何自訂字型",
  "fontManagementRenameTooltip": "重新命名",
  "fontManagementDeleteTooltip": "刪除",
  "fontManagementRenameDialogTitle": "重新命名",
  "fontManagementDeleteConfirmTitle": "確定要刪除「{fontName}」嗎？",
  "fontManagementDeleteConfirmMessage": "{usageCount, plural, =1{目前有 1 本書使用此字型，刪除後將自動改用預設字型} other{目前有 {usageCount} 本書使用此字型，刪除後將自動改用預設字型}}",
  "fontManagementUploadBothMessage": "{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}，{skippedCount, plural, =1{1 款已存在已跳過} other{{skippedCount} 款已存在已跳過}}",
  "fontManagementUploadAddedOnlyMessage": "{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}",
  "fontManagementUploadSkippedOnlyMessage": "{skippedCount, plural, =1{1 款字型已存在，已跳過} other{{skippedCount} 款字型已存在，已跳過}}"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `font_management_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()`（第 72-133 行）開頭新增 `final l10n = AppLocalizations.of(context)!;`，替換：
- 第 76 行 `title: const Text('字型管理'),` → `title: Text(l10n.fontManagementTitle),`
- 第 87 行 `tooltip: '上傳字型',` → `tooltip: l10n.fontManagementUploadTooltip,`
- 第 94-97 行：
  ```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementBuiltInSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
  ```
  （移除外層 `const Padding`。）
- 第 100-103 行：
  ```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementCustomSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
  ```
  （移除外層 `const Padding`。）
- 第 104-108 行：
  ```dart
          if (_customFonts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.fontManagementNoCustomFontsHint),
            ),
  ```
  （移除外層 `const Padding`。）
- 第 118 行 `tooltip: '重新命名',` → `tooltip: l10n.fontManagementRenameTooltip,`
- 第 124 行 `tooltip: '刪除',` → `tooltip: l10n.fontManagementDeleteTooltip,`

`_pickAndUploadFonts()`（第 135-206 行，僅 SnackBar 訊息組裝分支需改）：
```dart
      await _loadFonts();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(buildUploadResultMessage(
          l10n: l10n,
          addedCount: outcome.addedCount,
          skippedCount: outcome.skippedCount,
        )),
      ));
```

`_renameFont()`（第 208-238 行）：
```dart
  Future<void> _renameFont(CustomFont font) async {
    _renameController?.dispose();
    final controller = TextEditingController(text: font.displayName);
    _renameController = controller;
    final l10n = AppLocalizations.of(context)!;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementRenameDialogTitle),
        content: TextField(
          key: const Key('font_management_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_rename_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || font.id == null) return;
    await widget.repository.rename(font.id!, newName);
    await _loadFonts();
  }
```

`_deleteFont()`（第 240-267 行）：
```dart
  Future<void> _deleteFont(CustomFont font) async {
    final usageCount = await widget.repository.countBooksUsing(font.familyName);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementDeleteConfirmTitle(font.displayName)),
        content: usageCount > 0
            ? Text(l10n.fontManagementDeleteConfirmMessage(usageCount))
            : null,
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.fontManagementDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true || font.id == null) return;
    await widget.repository.deleteAndResetUsage(font.id!, font.familyName);
    await _loadFonts();
  }
```

`buildUploadResultMessage()`（第 310-321 行，頂層函式，新增 `l10n` 具名參數）：
```dart
String buildUploadResultMessage({
  required AppLocalizations l10n,
  required int addedCount,
  required int skippedCount,
}) {
  if (addedCount > 0 && skippedCount > 0) {
    return l10n.fontManagementUploadBothMessage(addedCount, skippedCount);
  }
  if (addedCount > 0) {
    return l10n.fontManagementUploadAddedOnlyMessage(addedCount);
  }
  return l10n.fontManagementUploadSkippedOnlyMessage(skippedCount);
}
```

- [ ] **Step 4: 遷移既有測試檔（1 處 `MaterialApp(`＋`buildUploadResultMessage()` 純單元測試呼叫端）**

`app/test/screens/font_management_screen_test.dart` 新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/l10n/app_localizations_zh.dart';
```

1 處 `MaterialApp(` 補上三個 l10n 參數。

既有 `test('resolveUploadOutcome：合併訊息文案（有新增有跳過／全部新增／全部跳過）', ...)`（第 139-148 行）改為傳入 `l10n`：
```dart
  test('resolveUploadOutcome：合併訊息文案（有新增有跳過／全部新增／全部跳過）', () {
    final l10n = AppLocalizationsZhTw();
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 2),
      '已新增 3 款字型，2 款已存在已跳過',
    );
    expect(buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 0), '已新增 3 款字型');
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 0, skippedCount: 2),
      '2 款字型已存在，已跳過',
    );
  });
```

- [ ] **Step 5: 新增英文渲染驗證測試（含 ICU plural 單複數與純函式英文斷言）**

在 widget 測試新增：
```dart
  testWidgets('英文介面下標題/區塊標籤/空狀態提示正確以英文渲染', (tester) async {
    final repository = FakeCustomFontsRepository();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FontManagementScreen(repository: repository),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Font Management'), findsOneWidget);
    expect(find.text('Built-in Fonts'), findsOneWidget);
    expect(find.text('Custom Fonts'), findsOneWidget);
    expect(find.text('No custom fonts uploaded yet'), findsOneWidget);
  });
```

在純邏輯 `test()` 新增（緊接 Step 4 修改的既有測試之後，驗證英文單複數）：
```dart
  test('buildUploadResultMessage：英文版單複數各自獨立正確變化', () {
    final l10n = AppLocalizationsEn();
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 1, skippedCount: 2),
      'Added 1 font, 2 already exist and were skipped',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 3, skippedCount: 1),
      'Added 3 fonts, 1 already exists and was skipped',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 1, skippedCount: 0),
      'Added 1 font',
    );
    expect(
      buildUploadResultMessage(l10n: l10n, addedCount: 0, skippedCount: 1),
      '1 font already exists and was skipped',
    );
  });
```

（需新增 import `package:elinkbook/l10n/app_localizations_en.dart`。）

> `FakeCustomFontsRepository` 的實際建構方式請對照檔案既有 Fake 實作調整。

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/font_management_screen_test.dart`
Expected: 全數通過（既有＋新增 2 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/font_management_screen.dart test/screens/font_management_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/font_management_screen.dart app/test/screens/font_management_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): font_management_screen.dart 字串抽取三語言在地化（含 ICU plural／頂層函式簽章變更）"
```

---

### Task 10: `reader_console_log_screen.dart`（production ＋ 測試，4 處合併同一 Task）

**Files:**
- Modify: `app/lib/screens/reader_console_log_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/reader_console_log_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerConsoleLogTitle`/`readerConsoleLogCopyAllTooltip`/`readerConsoleLogClearTooltip`/`readerConsoleLogEmptyHint`/`readerConsoleLogCopiedMessage`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerConsoleLogTitle": "閱讀器 Console Log",
  "@readerConsoleLogTitle": {
    "description": "閱讀器 Console Log 畫面 AppBar 標題"
  },
  "readerConsoleLogCopyAllTooltip": "複製全部",
  "@readerConsoleLogCopyAllTooltip": {
    "description": "「複製全部」按鈕的無障礙提示文字"
  },
  "readerConsoleLogClearTooltip": "清空",
  "@readerConsoleLogClearTooltip": {
    "description": "「清空」按鈕的無障礙提示文字"
  },
  "readerConsoleLogEmptyHint": "目前沒有記錄",
  "@readerConsoleLogEmptyHint": {
    "description": "沒有任何 Console Log 記錄時的空狀態提示文字"
  },
  "readerConsoleLogCopiedMessage": "已複製全部記錄到剪貼簿",
  "@readerConsoleLogCopiedMessage": {
    "description": "點擊「複製全部」後的 SnackBar 提示"
  }
```

`app_zh_CN.arb`：
```json
  "readerConsoleLogTitle": "阅读器 Console Log",
  "readerConsoleLogCopyAllTooltip": "复制全部",
  "readerConsoleLogClearTooltip": "清空",
  "readerConsoleLogEmptyHint": "目前没有记录",
  "readerConsoleLogCopiedMessage": "已复制全部记录到剪贴板"
```

`app_en.arb`：
```json
  "readerConsoleLogTitle": "Reader Console Log",
  "readerConsoleLogCopyAllTooltip": "Copy all",
  "readerConsoleLogClearTooltip": "Clear",
  "readerConsoleLogEmptyHint": "No records yet",
  "readerConsoleLogCopiedMessage": "Copied all records to clipboard"
```

`app_zh.arb`：
```json
  "readerConsoleLogTitle": "閱讀器 Console Log",
  "readerConsoleLogCopyAllTooltip": "複製全部",
  "readerConsoleLogClearTooltip": "清空",
  "readerConsoleLogEmptyHint": "目前沒有記錄",
  "readerConsoleLogCopiedMessage": "已複製全部記錄到剪貼簿"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `reader_console_log_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readerConsoleLogTitle),
        actions: [
          IconButton(
            key: const Key('reader_console_log_copy_all_button'),
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: l10n.readerConsoleLogCopyAllTooltip,
            onPressed: () => _copyAllToClipboard(context),
          ),
          IconButton(
            key: const Key('reader_console_log_clear_button'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.readerConsoleLogClearTooltip,
            onPressed: ReaderConsoleLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: ReaderConsoleLog.entries,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return Center(
              key: const Key('reader_console_log_empty'),
              child: Text(l10n.readerConsoleLogEmptyHint),
            );
          }
          // ...（ListView.builder 以下原樣不動）
```

（原本 `const Center(...)` 因子項不再是常數，移除該層 `const`。）

`_copyAllToClipboard()`（第 65-72 行）：
```dart
  Future<void> _copyAllToClipboard(BuildContext context) async {
    final entries = ReaderConsoleLog.entries.value;
    await Clipboard.setData(ClipboardData(text: entries.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.readerConsoleLogCopiedMessage)),
    );
  }
```

- [ ] **Step 4: 遷移既有測試檔（4 處 `MaterialApp(`）**

`app/test/screens/reader_console_log_screen_test.dart` 新增 import `package:elinkbook/l10n/app_localizations.dart`，4 處 `const MaterialApp(home: ReaderConsoleLogScreen())` 改為：
```dart
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
```
（移除外層 `const`，`home:` 內層 `const ReaderConsoleLogScreen()` 本身仍可維持 `const`。）

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題/按鈕提示/空狀態提示正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderConsoleLogScreen(),
      ),
    );

    expect(find.text('Reader Console Log'), findsOneWidget);
    expect(find.text('No records yet'), findsOneWidget);
    expect(find.byTooltip('Copy all'), findsOneWidget);
    expect(find.byTooltip('Clear'), findsOneWidget);
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/reader_console_log_screen_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_console_log_screen.dart test/screens/reader_console_log_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_console_log_screen.dart app/test/screens/reader_console_log_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_console_log_screen.dart 字串抽取三語言在地化"
```

---

### Task 11: `about_screen.dart`（production ＋ 測試，2 處合併同一 Task，含載入中/錯誤狀態安全重構）

**Files:**
- Modify: `app/lib/screens/about_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/about_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `aboutScreenTitle`/`aboutScreenVersionLabel`/`aboutScreenBuildTimeLabel`/`aboutScreenWebViewVersionLabel`/`aboutScreenViewLicensesButton`/`aboutScreenLoadingText`/`aboutScreenFailedToLoadVersionMessage`/`aboutScreenUnavailableText`。

**計劃範圍澄清（初始值/錯誤狀態的 l10n 安全重構，比照 Issue 3 `_FileSizeStatus` 先例）**：`_versionText`/`_buildTimeText`/`_webViewVersion` 三個欄位目前直接以硬編碼中文字面值（`'讀取中...'`／`'無法取得版本號'`／`'無法取得'`）作為欄位初始值與非同步載入結果，欄位初始值在 `State` 建構當下（早於 `initState()`）就會賦值，若直接改成 `AppLocalizations.of(context)!.xxx` 會在沒有 `BuildContext` 的欄位初始化階段崩潰。本 Task 改用「查詢結果狀態與其在地化文字分離、只在 `build()` 轉譯」設計：新增私有 enum `_AsyncTextStatus { loading, error }`，三個欄位型別改為 `Object`（可能是 `_AsyncTextStatus.loading`／`_AsyncTextStatus.error`／實際載入成功的 `String` 資料），並新增 `_resolveAsyncText()` helper 只在 `build()` 執行期間呼叫 `AppLocalizations.of(context)!` 轉譯。`_versionForLicensePage`（`String?`，供 `showLicensePage()` 使用）維持原樣不動，本身不是顯示文字。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "aboutScreenTitle": "關於",
  "@aboutScreenTitle": {
    "description": "關於畫面 AppBar 標題"
  },
  "aboutScreenVersionLabel": "版本",
  "@aboutScreenVersionLabel": {
    "description": "「版本」項目標題"
  },
  "aboutScreenBuildTimeLabel": "編譯時間",
  "@aboutScreenBuildTimeLabel": {
    "description": "「編譯時間」項目標題"
  },
  "aboutScreenWebViewVersionLabel": "系統 WebView 版本",
  "@aboutScreenWebViewVersionLabel": {
    "description": "「系統 WebView 版本」項目標題"
  },
  "aboutScreenViewLicensesButton": "開源授權清單",
  "@aboutScreenViewLicensesButton": {
    "description": "「開源授權清單」項目標題（點擊開啟 Flutter 內建授權清單頁）"
  },
  "aboutScreenLoadingText": "讀取中...",
  "@aboutScreenLoadingText": {
    "description": "版本號/編譯時間/WebView 版本非同步載入完成前的暫時顯示文字"
  },
  "aboutScreenFailedToLoadVersionMessage": "無法取得版本號",
  "@aboutScreenFailedToLoadVersionMessage": {
    "description": "PackageInfo.fromPlatform() 呼叫失敗時，版本號欄位顯示的錯誤文字"
  },
  "aboutScreenUnavailableText": "無法取得",
  "@aboutScreenUnavailableText": {
    "description": "編譯時間/WebView 版本呼叫失敗或回傳空值時顯示的通用錯誤文字"
  }
```

`app_zh_CN.arb`：
```json
  "aboutScreenTitle": "关于",
  "aboutScreenVersionLabel": "版本",
  "aboutScreenBuildTimeLabel": "编译时间",
  "aboutScreenWebViewVersionLabel": "系统 WebView 版本",
  "aboutScreenViewLicensesButton": "开源授权清单",
  "aboutScreenLoadingText": "读取中...",
  "aboutScreenFailedToLoadVersionMessage": "无法取得版本号",
  "aboutScreenUnavailableText": "无法取得"
```

`app_en.arb`：
```json
  "aboutScreenTitle": "About",
  "aboutScreenVersionLabel": "Version",
  "aboutScreenBuildTimeLabel": "Build Time",
  "aboutScreenWebViewVersionLabel": "System WebView Version",
  "aboutScreenViewLicensesButton": "Open Source Licenses",
  "aboutScreenLoadingText": "Loading...",
  "aboutScreenFailedToLoadVersionMessage": "Failed to get version",
  "aboutScreenUnavailableText": "Unavailable"
```

`app_zh.arb`：
```json
  "aboutScreenTitle": "關於",
  "aboutScreenVersionLabel": "版本",
  "aboutScreenBuildTimeLabel": "編譯時間",
  "aboutScreenWebViewVersionLabel": "系統 WebView 版本",
  "aboutScreenViewLicensesButton": "開源授權清單",
  "aboutScreenLoadingText": "讀取中...",
  "aboutScreenFailedToLoadVersionMessage": "無法取得版本號",
  "aboutScreenUnavailableText": "無法取得"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 修改 `about_screen.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

整份 `_AboutScreenState` 改為：
```dart
enum _AsyncTextStatus { loading, error }

class _AboutScreenState extends State<AboutScreen> {
  Object _versionInfo = _AsyncTextStatus.loading;
  String? _versionForLicensePage;
  Object _webViewVersionInfo = _AsyncTextStatus.loading;
  Object _buildTimeInfo = _AsyncTextStatus.loading;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadWebViewVersion();
    _loadBuildTime();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionInfo = '${info.version} (build ${info.buildNumber})';
        _versionForLicensePage = info.version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionInfo = _AsyncTextStatus.error);
    }
  }

  Future<void> _loadBuildTime() async {
    try {
      final buildTime = await _appInfoChannel.invokeMethod<String>(
        'getBuildTime',
      );
      if (!mounted) return;
      setState(
        () => _buildTimeInfo = buildTime ?? _AsyncTextStatus.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _buildTimeInfo = _AsyncTextStatus.error);
    }
  }

  Future<void> _loadWebViewVersion() async {
    try {
      final version = await _appInfoChannel.invokeMethod<String>(
        'getSystemWebViewVersion',
      );
      if (!mounted) return;
      setState(
        () => _webViewVersionInfo = version ?? _AsyncTextStatus.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _webViewVersionInfo = _AsyncTextStatus.error);
    }
  }

  /// 只在 `build()` 執行期間呼叫，把非同步查詢的原始結果狀態
  /// （[_AsyncTextStatus.loading]／[_AsyncTextStatus.error]／實際載入成功
  /// 的 `String`）轉譯成目前介面語言的顯示文字。
  String _resolveAsyncText(Object value, AppLocalizations l10n) {
    if (value is String) return value;
    return switch (value as _AsyncTextStatus) {
      _AsyncTextStatus.loading => l10n.aboutScreenLoadingText,
      _AsyncTextStatus.error => l10n.aboutScreenUnavailableText,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final versionText = _versionInfo == _AsyncTextStatus.error
        ? l10n.aboutScreenFailedToLoadVersionMessage
        : _resolveAsyncText(_versionInfo, l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutScreenTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.aboutScreenVersionLabel),
            subtitle: Text(
              versionText,
              key: const Key('about_screen_version_text'),
            ),
          ),
          ListTile(
            title: Text(l10n.aboutScreenBuildTimeLabel),
            subtitle: Text(
              _resolveAsyncText(_buildTimeInfo, l10n),
              key: const Key('about_screen_build_time_text'),
            ),
          ),
          ListTile(
            title: Text(l10n.aboutScreenWebViewVersionLabel),
            subtitle: Text(
              _resolveAsyncText(_webViewVersionInfo, l10n),
              key: const Key('about_screen_webview_version_text'),
            ),
          ),
          ListTile(
            key: const Key('about_screen_view_licenses_button'),
            title: Text(l10n.aboutScreenViewLicensesButton),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'elinkBook',
                applicationVersion: _versionForLicensePage,
              );
            },
          ),
        ],
      ),
    );
  }
}
```

（`versionText` 之所以額外用一個獨立的三元判斷、不直接沿用 `_resolveAsyncText()`，是因為版本號欄位的錯誤文字 `aboutScreenFailedToLoadVersionMessage`〔"無法取得版本號"〕與編譯時間/WebView 版本共用的通用錯誤文字 `aboutScreenUnavailableText`〔"無法取得"〕不同——`_resolveAsyncText()` 的 `error` 分支固定回傳 `aboutScreenUnavailableText`，版本號欄位需要在 `build()` 內另外特判。）

- [ ] **Step 4: 遷移既有測試檔（2 處 `MaterialApp(`）**

`app/test/screens/about_screen_test.dart` 新增 import `package:elinkbook/l10n/app_localizations.dart`，2 處 `const MaterialApp(home: AboutScreen())` 改為：
```dart
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
```

既有測試斷言值不變（`find.text('關於')`／`find.text('開源授權清單')`／`buildTimeText.data == '無法取得'` 在 `zh_TW` 下與新 key 的值完全相同）。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題/項目標題/授權清單按鈕正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Build Time'), findsOneWidget);
    expect(find.text('System WebView Version'), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });

  testWidgets('英文介面下 getBuildTime 呼叫失敗時降級顯示英文 Unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async {
      if (call.method == 'getSystemWebViewVersion') return '120.0.6099.43';
      if (call.method == 'getBuildTime') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final buildTimeText = tester.widget<Text>(
      find.byKey(const Key('about_screen_build_time_text')),
    );
    expect(buildTimeText.data, 'Unavailable');
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/about_screen_test.dart`
Expected: 全數通過（既有 2 個＋新增 2 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/about_screen.dart test/screens/about_screen_test.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/about_screen.dart app/test/screens/about_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): about_screen.dart 字串抽取三語言在地化（含載入中/錯誤狀態安全重構）"
```

---

### Task 12: 完整驗收與進度文件更新

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`
- Modify: `docs/epics.md`

- [ ] **Step 1: 完整 `flutter analyze`**

Run（在 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: No issues found!

- [ ] **Step 2: 完整 `flutter test`**

Run:
```bash
flutter test
```
Expected: 全數通過，與本 Issue 認領前的 base commit 相比零新增失敗（若有既存不穩定測試，需與 base commit 重跑比對，證實非本 Issue 引入，比照 Issue 0／3／4 既有先例的查證方式）。

- [ ] **Step 3: 確認範圍修正已同步記錄**

在 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 5」段落：
1. `**Status:** ready-for-agent` 改為 `**Status:** completed`。
2. 在「What to build」段落後新增「**實際執行範圍修正記錄（認領時 grep 盤點）**」段落，內容比照 Issue 3／4 先例，記錄：`settings_scaffold.dart` 原本要求的「已索引 $current / $total 本」ICU plural 索引進度字串經查證現行程式碼不存在（`issues.md` 原始描述已過時，本 Issue 未新增對應邏輯）；`settings_scaffold_test.dart` 已在 Issue 1 完整遷移至 `pumpLocalizedWidget()`，本 Issue 不重複遷移；`cloud_account_settings_screen.dart._buildProviderTile()` 的 `title`（`'Google Drive'`／`'OneDrive'`）為雲端服務商品牌名不翻譯。

- [ ] **Step 4: 更新 `epic.md`**

在「開發記錄」段落末尾新增一則，比照既有格式，記錄：Task 1-12 完成概況、9 個檔案各自的 key 數量、`font_management_screen.dart.buildUploadResultMessage()` 頂層純函式簽章變更（新增 `AppLocalizations l10n` 參數，供純單元測試直接以 `AppLocalizationsZhTw()`/`AppLocalizationsEn()` 呼叫）、`about_screen.dart` 的 `_AsyncTextStatus` 查詢結果狀態分離設計（比照 Issue 3 `_FileSizeStatus` 先例）、`sync_settings_screen.dart._formatLastSyncedAt()` 改用 `DateFormat.yMd(locale).add_Hm()` 取代手動字串拼接、`flutter analyze`／`flutter test` 最終結果。

- [ ] **Step 5: 更新 `docs/epics.md`**

`epic-45-interface-i18n` 該列備註欄位改為「Issue 0／1／2／3／4／5 已完成，待認領 Issue 6」。

- [ ] **Step 6: Commit**

```bash
git add app/ docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 5 為 completed，記錄實際執行範圍修正並更新 epic.md/epics.md"
```

---

## Self-Review

**1. Spec 覆蓋度**：對照 `issues.md` Issue 5 段落逐項檢查——「What to build」列出的 9 個候選檔案（`settings_scaffold.dart`／`nav_zone_settings_screen.dart`／`tts_defaults_screen.dart`／`reading_defaults_screen.dart`／`sync_settings_screen.dart`／`cloud_account_settings_screen.dart`／`font_management_screen.dart`／`reader_console_log_screen.dart`／`about_screen.dart`）皆有對應 Task（Task 1、2/3、6、4/5、7、8、9、10、11）。日期格式化（`sync_settings_screen.dart._formatLastSyncedAt()`）已在 Task 7 落實 `DateFormat.yMd(locale).add_Hm()`。ICU plural 要求：`settings_scaffold.dart` 原始描述的索引進度字串經查證不存在（Task 1 範圍修正記錄），改由 Task 9 `font_management_screen.dart` 的批次上傳結果訊息與刪除確認訊息的 `usageCount` 承接本 Issue 唯一的 ICU plural 實作，符合 Global Constraints 對「本 Epic 反覆確立的 ICU plural 規則」的要求。無遺漏的 spec 需求。

**2. Placeholder 掃描**：全計畫搜尋「TBD」／「TODO」／「待補」／「同 Task N」等紅旗字樣，僅出現在 Task 6/7/8 Step 5 等處以「若既有測試建構方式與檔案既有慣例不完全一致，改用該既有慣例」收尾（比照 `plan-issue-3.md`／`plan-issue-4.md` 既有先例，同樣以「若既有寫法不完全一致，以檔案中其他測試為準」收尾），這些皆非「跳過不寫」的 placeholder，而是明確指向「檔案中已存在、可直接查閱複製」的既有具體寫法，不構成計畫失敗。所有 ARB key 皆有完整四語言真實文字，所有程式碼 Step 皆為可直接套用的具體 diff 或完整方法。

**3. 型別一致性**：
- `_themeLabel(AppTheme theme, AppLocalizations l10n)`（Task 1）：改為接收 `l10n` 參數而非直接呼叫 `AppLocalizations.of(context)!`（因為它本身沒有 `context` 參數），兩處呼叫端（`_buildThemeDot()`）皆已持有 `l10n` 並正確傳入。
- `_buildProviderTile()`（Task 8）：新增 `AppLocalizations l10n` 位置參數，唯一呼叫端 `build()` 的兩處呼叫（Google Drive／OneDrive）皆已同步更新為傳入 `l10n`。
- `buildUploadResultMessage()`（Task 9）：新增 `required AppLocalizations l10n` 具名參數，production 呼叫端（`_pickAndUploadFonts()`）與純單元測試呼叫端（`AppLocalizationsZhTw()`/`AppLocalizationsEn()`）皆已同步更新。
- `_formatLastSyncedAt()`（Task 7）：新增 `AppLocalizations l10n` 參數，唯一呼叫端（`_buildLoggedInView()`）已同步更新；`_buildLoggedInView()`／`_buildLoginForm()` 兩者皆新增 `AppLocalizations l10n` 參數，唯一呼叫端（`build()`）已同步更新為傳入 `l10n`。
- `_resolveAsyncText()`（Task 11）：新增的私有方法，`build()` 內三處呼叫（版本號／編譯時間／WebView 版本）型別（`Object` 輸入、`String` 輸出）與 `_versionInfo`/`_buildTimeInfo`/`_webViewVersionInfo` 三個欄位型別（`Object`）一致。
- 跨檔案共用 ARB key（`cancel`/`confirm`，Task 9 消費）的 key 名稱與參數型別（無 placeholder）與既有定義一致引用，無拼字或型別落差。

**4. 架構偏離記錄**：
- `buildUploadResultMessage()` 從「純字串拼接、無 `context`」改為「新增 `AppLocalizations l10n` 具名參數」——Task 9 已記錄為「架構必要偏離」，理由是它是頂層純函式且被不經過 widget tree 的純單元測試直接呼叫，`gen-l10n` 生成的具體語言子類別（`AppLocalizationsZhTw`/`AppLocalizationsEn`）可直接建構，不需要引入額外測試基礎設施。
- `about_screen.dart` 的三個顯示文字欄位從「直接存 `String` 顯示文字」改為「存 `Object`（狀態 enum 或已知非翻譯資料），只在 `build()` 轉譯」——Task 11 已詳細記錄查證依據與安全性論證（欄位初始值早於 `initState()` 賦值，不能是需要 `BuildContext` 才能解析的字串），比照 Issue 3 `_FileSizeStatus` 既有先例。
- `sync_settings_screen.dart._formatLastSyncedAt()` 從「手動字串拼接」改為「`DateFormat.yMd(locale).add_Hm()`」——Task 7 已記錄這推翻了既有程式碼註解「不引入 intl 套件」的過時決策前提（`intl` 已是本 Epic 全域依賴），並提醒既有測試斷言的日期格式字面值需要重新核對（`DateFormat.yMd()` 的分隔符號與補零規則與手動拼接不同）。

無發現需要在計畫定案前修正的缺口。
