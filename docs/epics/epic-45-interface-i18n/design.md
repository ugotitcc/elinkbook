# Epic 45 — 多語系介面：Discovery

## 背景

2026-09-20 使用者提出「多語系介面：正體中文、簡體中文、英文」需求（PRD FR-49），經 `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）3 輪 16 題問答完成 Discovery。

Discovery 前已核實下列事實，直接影響多個分岔的可行選項：

- PRD FR-49 已存在但尚無研究報告；`docs/research/architecture-review-tts-conversion-opds-i18n.md` 已建議 FR-49「完全獨立立案、獨立排期」，且預期是「橫跨全部既有畫面的大範圍工作」。
- 專案目前**沒有**任何 i18n 框架依賴（`pubspec.yaml` 無 `flutter_localizations`／`intl`，無 `l10n` 目錄）——所有既有畫面的使用者可見字串幾乎全部是硬編碼正體中文字面值。
- 系統設定畫面（`SettingsScaffold`）既有四分區：外觀／閱讀／同步與帳號／關於。
- `epic-42-text-conversion`（FR-48 簡繁轉換）已有一套「字元對字元 1:1」簡繁轉換機制，但用途是**書籍內容顯示**（保護 CFI 定位精度是其核心限制），PRD 本文已明確區分 FR-48（書籍內容）與 FR-49（App 介面）是兩個不同概念。
- 探查 `BookMetadataChannel.kt`／`MainActivity.kt` 發現，原生端透過 `MethodChannel` 回傳給 Dart 的 `PlatformException` 帶有硬編碼正體中文錯誤訊息（例如「找不到檔案或檔案已損毀」），但均搭配穩定的錯誤代碼（如 `extraction_failed`）；抽查 Dart 端多數既有呼叫點目前直接捨棄這個原生訊息文字（吞掉、轉成空結果）。

## `/grilling` 決策紀錄

### 範圍界定

- 一次涵蓋**全部**既有畫面（不分核心/次要分期延後）。
- 「介面文字」涵蓋 UI 靜態字串（按鈕/選單/設定項目/對話框）＋執行期動態訊息（錯誤提示/Toast/驗證訊息），**不**涵蓋開發者導向的 Console Log／診斷內容。
- 涵蓋系統保留字串（例如「未分類」分類名稱，`BookGroup.uncategorized`）。
- **不**涵蓋使用者輸入資料（書名／作者／使用者自訂分類名稱／備註內容等）與專有名詞（內建字型名稱、雲端服務商品牌名如 Google Drive／OneDrive），這些一律維持原樣。

### 語言選擇與預設行為

- **儲存語意（`/receiving-code-review` I-1 修正）**：`SharedPreferences` 的 `app_locale` 鍵值為 nullable，`null` 代表「跟隨系統」（動態），非 `null` 時代表使用者手動覆寫成固定語言、不再跟隨系統變化。設定畫面提供 **4 個選項**：「跟隨系統」／「正體中文」／「簡體中文」／「English」——「跟隨系統」讓使用者能隨時取消手動覆寫、回到動態跟隨，不是三選一之後就回不去。
- 未手動覆寫（`app_locale == null`）時，透過 Flutter `localeListResolutionCallback` 依裝置目前系統語言即時解析對應語言；系統語言事後變更（例如使用者事後在 Android 系統設定切換語言）時，App 也應跟著動態切換，不是只在首次啟動當下判斷一次就寫死。
- **Locale 解析矩陣（`/receiving-code-review` I-2 修正）**：裝置系統語言依下列規則對應到三個支援語系之一，不能只比對 `zh_TW`／`zh_CN`／`en` 三個精確值（會漏掉港澳繁體、新馬簡體等常見變體）：
  - `scriptCode == 'Hant'` 或 `countryCode` 屬於 `{TW, HK, MO}` → 正體中文；
  - `scriptCode == 'Hans'` 或 `countryCode` 屬於 `{CN, SG}` → 簡體中文；
  - `languageCode == 'en'` → 英文；
  - 其餘所有未支援語系 → fallback 正體中文。
- 切換即時生效，不需重啟 App（Flutter `Localizations`/`MaterialApp` 原生支援）。
- 偏好儲存於裝置本地 `SharedPreferences`（比照「全域預設值」既有慣例），**不**跨裝置同步（不納入 `SyncEngine`／PocketBase 範圍）——理由與替代方案見 `docs/adr/0033-interface-locale-device-local-not-synced.md`。
- 設定入口放在 `SettingsScaffold`「外觀」分區（與「佈景」「E-Ink 高對比模式」「字型管理」同區，皆屬「App 如何被呈現」的全域展示偏好）。

### 翻譯策略

- 簡體中文與英文字串採**人工翻譯**，不借用 `epic-42` 的字元級 1:1 轉換機制——App 介面字串量體遠小於書籍全文（有限、可控的清單），值得人工翻譯確保用詞道地；且沒有 `epic-42` 那個「保護 CFI 定位精度」的技術限制需要繼承。
- 翻譯由 Claude Code 依正體中文原文草擬，使用者審閱修訂（比照本專案既有「審查先出報告、人類把關」的既定流程精神）。

### 技術路線

- Flutter 官方 `flutter_localizations` ＋ `intl`（ARB 檔案、`flutter gen-l10n`），零額外第三方套件相依。
- 含 **ICU plural** 語法處理複數字串（例如「索引進度」訊息：`"已索引 {current} / {total, plural, =1{1 本} other{{total} 本}}"`，英文版單複數綁定於**總本數 `total`**、而非目前進度 `current`——`/receiving-code-review` M-1 修正），`gen-l10n` 原生支援。
- 日期/數字比照 `intl` 的 `DateFormat`／`NumberFormat` 依目前介面語言在地化呈現（例如英文 "Sep 20, 2026"、中文「2026年9月20日」）。
- 內建字型名稱（思源黑體／思源宋體／原俠正楷／台灣圓體／源流明體）一律**不翻譯**，視為專有名詞（其中三款為商用授權字型的官方品牌名，貿然創造譯名有失準風險）。
- 「未分類」系統保留分類名稱納入翻譯範圍——僅限**表現層轉譯**，持久化層不受影響，詳見下方「系統保留分類名稱的在地化契約」。

### 系統保留分類名稱的在地化契約（`/receiving-code-review` C-1 修正）

查證 `app/lib/library/models/book_group.dart`／`sqlite_library_repository.dart` 後確認：`BookGroup.uncategorized`（字面值 `'未分類'`）不只是 UI 標籤，同時是 SQLite `groups` 表的主鍵、`books.groupName` 欄位預設值，重新命名/刪除保護邏輯也是拿這個字面值做字串比對（`sqlite_library_repository.dart:1269,1292,1299`）。因此多語系化這個字串必須嚴守以下契約，不能只用一句「納入翻譯範圍」帶過：

- **持久化層不動性**：SQLite 資料庫、`BookGroup.uncategorized` 常數、`Book.groupName` 欄位值永遠維持內部唯一標記字串 `'未分類'`，**嚴禁**隨介面語言變動或觸發任何資料庫更新——非 UI 情境（背景匯入 `BookImportServiceImpl`、Isolate 指紋計算）本來就無法取得 `BuildContext`/`AppLocalizations`，維持固定字面值也讓這些路徑不受影響。
- **表現層純轉譯**：所有 UI 呈現處（書架標籤、下拉選單、書籍詳情）一律透過共用輔助方法轉譯：`group.name == BookGroup.uncategorized ? l10n.groupUncategorized : group.name`，不修改底層資料。
- **撞名防線**：`LibraryGroupManagementDialog`（新增/重新命名分類）的驗證邏輯除既有「不得等於 `BookGroup.uncategorized`（'未分類'）」外，須新增「不得等於**當前介面語言**下的 `l10n.groupUncategorized` 翻譯結果」（例如英文介面下不得新增名為 `"Uncategorized"` 的自訂分類），防止使用者建立與系統保留分類顯示名稱相同、但底層資料不同的幽靈分類。

### 執行期例外訊息在地化（原「原生層錯誤訊息」，範圍擴大——`/receiving-code-review` I-3 修正）

- 原生（Kotlin）`MethodChannel` 回傳的 `PlatformException`，往後一律由 Dart 端依**錯誤代碼**（如 `extraction_failed`／`copy_failed`）對應 `AppLocalizations` 字串顯示給使用者；原生端的中文 `message` 字串保留純診斷/日誌用途，不新增「把目前 `Locale` 傳給原生層」的跨端狀態同步機制。理由與替代方案見 `docs/adr/0034-native-channel-errors-localized-by-code-in-dart.md`。
- **同一原則擴大適用於所有 Dart 端非同步例外**（查證 `sync_settings_screen.dart`／`opds_http_client.dart`／`sync_engine.dart`／`book_import_service_impl.dart`／`foliate_reader_view.dart` 等 14 個既有檔案皆有硬編碼中文錯誤字面值，來源涵蓋 PocketBase `ClientException`、OPDS/網路 `SocketException`／`HttpException`、SQLite `DatabaseException`、檔案 I/O `FileSystemException`、Foliate WebView 開書逾時等）：使用者可見的錯誤提示一律對應到語意化的在地化字串（例如 `l10n.errorNetworkConnection`／`l10n.errorSyncFailed`／`l10n.errorBookOpenTimeout`），**禁止**在使用者可見介面直接顯示 `e.toString()` 或例外物件的原始 `message`；技術除錯細節維持寫入 Console Log（不受本 Epic 翻譯範圍限制，比照既有「介面文字範圍界定」對 Console Log 的排除）。

### 品質把關

- 比照本專案既有 `app/tool/check_foliate_es_compat.js` 慣例，建立一支自動化稽核腳本，掃描 Widget 樹中未經 l10n 包裝的裸露中文字面值，防止現有畫面遺漏及未來新增畫面忘記包裝。
- **排除清單（`/receiving-code-review` M-2 修正）**：腳本須內建白名單/排除機制，避開合法且必須維持中文的既有字面值——例如 `BookGroup.uncategorized` 等系統保留 Sentinel 常數本身、內建字型品牌名、`epic-42-text-conversion` 的簡繁字典檔、測試 fixture／mock 資料——避免初次執行充斥假警報而難以落實；具體排除清單留待 `spec.md` 依實際掃描結果定案。

### 測試套件相容性（`/receiving-code-review` C-2 修正）

查證 `app/test/` 現況：43 個測試檔共 314 處 `find.text('<中文>')` 斷言、68 個測試檔共 772 處 `MaterialApp(` 建構，且**零**測試檔案目前配置 `localizationsDelegates`/`AppLocalizations`。一旦既有畫面改用 `AppLocalizations.of(context)!`，這些測試會面臨雙重崩潰：(1) 未注入 `localizationsDelegates` 時 `AppLocalizations.of(context)` 回傳 `null`，觸發 `Null check operator` 例外；(2) 即使補上 delegates，Flutter 測試環境（`TestWidgetsFlutterBinding`）預設模擬平台 Locale 為 `en_US`，未額外指定 `locale` 時畫面會渲染英文文字，使既有中文 `find.text()` 斷言全數落空。

因此本 Epic 必須包含「測試套件相容性」這個施工項目，原則如下：

- 建立/更新統一測試包裝器（例如 `app/test/support/` 下的 `pumpLocalizedWidget()`，或改造既有共用 pump helper），強制注入 `AppLocalizations.localizationsDelegates`＋`AppLocalizations.supportedLocales`，並將測試環境預設 `locale` **釘定為正體中文**（`const Locale('zh', 'TW')`），讓既有 300+ 處中文斷言在遷移過程中維持通過，不需要逐一重寫。
- 新增多語系切換專屬測試檔（例如 `locale_switch_test.dart`），集中驗證簡體中文／英文渲染正確性，不強迫既有測試案例改寫成三語言各一份。
- 具體 helper 命名與改造既有測試檔的施工順序留待 `spec.md`／Scrum Master 階段的 Issue 拆分定案。

## 依賴事實（供 Architecting 階段參考，非本 Discovery 待決）

- ARB 檔案結構、key 命名慣例、`flutter gen-l10n` 設定細節（`l10n.yaml`）留待 `spec.md` 定案。
- 全部既有畫面的字串盤點範圍與 Issue 拆分順序（例如依模組分批：書架→閱讀器 Chrome Bar→系統設定四分區→其餘管理類彈窗），留待 Scrum Master 階段依實際字串盤點結果定案。
- 稽核腳本的具體實作方式（AST 掃描 vs 正則比對裸露中文字元）與是否接入既有 CI/`flutter analyze` 流程，留待 `spec.md`。
- 既有字串中哪些含計數需要 ICU plural 處理的具體清單，留待字串盤點階段逐一確認。
- 測試包裝器 `pumpLocalizedWidget()`（或等效名稱）的具體實作與既有 68 個測試檔的遷移施工順序，留待 `spec.md`／Scrum Master 階段定案。
- 系統保留分類名稱轉譯輔助方法（`l10n.groupUncategorized` 對應的共用擴充方法/輔助函式）之確切放置位置與命名，留待 `spec.md`。

## 範圍界定

- **本 Epic 涵蓋**：`flutter_localizations`／`intl` 框架導入；全部既有畫面 UI 靜態字串與執行期動態訊息（含 Dart 端非同步例外，不限於原生 `MethodChannel`，見「執行期例外訊息在地化」）之三語（正體中文／簡體中文／英文）翻譯；系統保留字串（如「未分類」，僅表現層轉譯、持久化層不動，見「系統保留分類名稱的在地化契約」）；語言選擇 UI（設定→外觀）＋4 選項（含「跟隨系統」）＋Locale 解析矩陣＋即時切換；原生層錯誤代碼→Dart 端在地化訊息機制之正式化；ICU plural／日期在地化；防遺漏自動化稽核腳本（含排除清單）；既有測試套件相容性改造（統一測試包裝器＋釘定測試 locale，見「測試套件相容性」）；**Markdown 閱讀筆記匯出的系統產生結構文字**（標題／區塊標籤，如「閱讀筆記」「書籤清單」「劃線與個人備註」，非使用者輸入的書名/作者/備註內容本身——`/receiving-code-review` I-4 修正：這類文字屬於「App 產生之文字」而非「使用者資料」，與「介面文字範圍界定」的既有原則一致，故納入涵蓋範圍；`generateMarkdownExport()` 於 Architecting 階段需擴充參數以接收在地化標籤集合）。
- **本 Epic 不涵蓋**（留待後續視需求評估，不在本波規劃）：Console Log／診斷內容翻譯；使用者輸入資料翻譯（書名/作者/備註內容/自訂分類名稱等）；內建字型名稱／雲端服務品牌名翻譯；介面語言跨裝置同步；原生層自行維護多語系字串資源；書籍內容簡繁轉換（`epic-42` 既有範疇，本 Epic 不重疊、不修改）。

## `CONTEXT.md` 異動

- 新增「介面語言（App Locale，FR-49）」詞條：定義本 Epic 的產品概念、範圍邊界，並與既有「簡繁轉換」詞條明確劃清界線（互相參照，不互相影響）。

## 新增 ADR

- [`docs/adr/0033-interface-locale-device-local-not-synced.md`](../../adr/0033-interface-locale-device-local-not-synced.md)：介面語言偏好採裝置本地儲存，不跨裝置同步。
- [`docs/adr/0034-native-channel-errors-localized-by-code-in-dart.md`](../../adr/0034-native-channel-errors-localized-by-code-in-dart.md)：原生層 `MethodChannel` 錯誤訊息不做跨端在地化，改由 Dart 端依錯誤代碼對應。

## 下一步

進入 Architecting 階段：盤點全部既有畫面的硬編碼字串範圍，撰寫 `spec.md`（ARB 結構、`AppLocalizations` 串接方式、稽核腳本設計），再進入 Scrum Master 階段拆分 Issue。
