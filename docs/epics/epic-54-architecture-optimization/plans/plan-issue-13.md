# Issue 13：`SourceDependencies`／`AppearanceDependencies`／`AppDependencies` 與 `main.dart` 收尾 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（延續 Issue 12 起「使用者明確要求嚴禁 subagent」的做法，不要用 `subagent-driven-development`；若使用者改變主意，以使用者當下指示為準）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把「來源」「外觀」兩類依賴也收成依賴組（`SourceDependencies`、`AppearanceDependencies`），由新的容器 `AppDependencies` 與 `ReaderFeatureDependencies`、`SyncDependencies` 一起在 `main.dart` 建構一次、經 `ElinkBookApp` 原樣往下傳；移除 epic-26 Issue 7 留下的 4 個舊 bundle 與 epic-44 的 `WifiTransferDependencies`，並把 WiFi 傳書、雲端、遠端、下載佇列這些原本靠 null 判斷的入口改成 non-null 組內依賴。

**Architecture：** 依 ADR 0037 §1／§2／§3／§6：畫面以建構子接收所需的組、組內依賴 non-null required、逐畫面一刀切、不留新舊並存。實作拆成兩段「外殼樹原子切換」——先切 `SourceDependencies`（Task 2），再切 `AppearanceDependencies`（Task 3），每段結束時 `flutter analyze` 乾淨、範圍測試全過、可獨立 commit；最後才引入 `AppDependencies` 並改 `main.dart`（Task 4）。**不設**「只活一個 Task 的過渡轉換函式」（Issue 12 Task 3 已證明 `AdaptiveShellScaffold` 長駐 `IndexedStack`，首幀就會建構全部子畫面，無法逐畫面漸進）。

**Tech Stack：** Flutter／Dart、`flutter_test`、`integration_test`、Node（既有守衛腳本與一次性 codemod）。指令一律在 `app/` 目錄下執行（除非另有標明），以 **Bash 工具（Git Bash）** 為準。

**Spec：** `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`；`docs/epics/epic-54-architecture-optimization/issues.md` 第 13 列；`reviews/review-issues-11-14.md`；前置做法見 `plans/plan-issue-11.md`、`plans/plan-issue-12.md` 與 `epic.md`「Issue 12 實作完成」。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **一刀切**：同一個畫面的建構子不得新舊參數並存（ADR 0037 §6）。本 Issue 結束時 `grep -rn "LibraryCloudAccountDependencies\|LibraryRemoteLibraryDependencies\|LibraryThemeDependencies\|LibraryLocaleDependencies\|WifiTransferDependencies" lib test integration_test` 必須無輸出（含註解）。
- **non-null required**：`SourceDependencies` 組內所有欄位（含函式型 `createOpdsClient`／`isMobileDataConnection`／`computeFingerprint`／`checkNetworkAvailability`）一律 non-null；`AppearanceDependencies` 的三個 callback 也一律 non-null。不得為了讓測試省事把欄位改回 nullable。
- **同一實例**：`SourceDependencies` 由 `main()` 建構一次；`computeFingerprint` 只有 `SourceDependencies` 一個來源（原本 `ElinkBookApp` 把它同時轉進 `AdaptiveShellScaffold` 與 `WifiTransferDependencies` 兩處，Issue 7 就曾因此漏轉發）。
- **不放寬測試**：刪除測試只允許一種理由——「該測試驗證的是『可選依賴缺席』，而依賴現在是 non-null required，型別上不可達」（Issue 11／12 先例）。每一個被刪的測試必須列入附錄 B（名稱＋理由）。仍可達的行為（例如書本沒有 `remoteDownloadUrl` 時的重新下載提示、E-Ink 鎖定主題）一律保留。**不得**為了通過而改弱斷言、加 `skip`、把 `same(...)` 改成 `isNotNull`。
- **不改 `lib/` 以外的行為**：本 Issue 是結構重構，不得順手改畫面文案、版面、Key、ARB（唯一例外：Task 5 移除已無使用端的孤兒 ARB 鍵）。唯一的行為差異是「原本因依賴為 null 而停用或隱藏的入口，在 non-null 下恆啟用」，必須逐項列入附錄 B。
- **範圍邊界**：`CloudBrowserScreen`、`RemoteServerListScreen`、`RemoteCatalogScreen`、`RemoteCatalogDependencies`（`lib/remote/remote_catalog_dependencies.dart`）、`WifiTransferScreen`、`CloudAccountSettingsScreen`、`DownloadQueuePanel` 等葉層畫面的建構子**不動**（它們收的已是個別 non-null 參數）；`LibrarySearchScreen`／`ReaderScreen` 的 `isEinkMode` 參數也不動（由呼叫端從 `appearance.isEinkMode` 取值傳入）。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`；改了 `integration_test/` 後跑 `node tool/check_integration_keys.js`。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 的定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。實作在獨立 worktree 內進行（Task 0 建立），PR 合併後的進度同步（`issues.md` 第 13 列、`docs/epics.md`）才在 `main` 直接 commit＋push。

## 已查證的事實（撰寫計畫時對照 `lib/` 所得，執行者開工前須再確認一次）

| 項目 | 事實 | 出處 |
|---|---|---|
| **`issues.md` 第 13 列與現況有兩處落差** | (1) 寫「移除 epic-26 Issue 7 的 6 個舊 bundle」，Issue 12 已刪掉其中兩個（`LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`），**現存只剩 4 個**：`LibraryCloudAccountDependencies`、`LibraryRemoteLibraryDependencies`、`LibraryThemeDependencies`、`LibraryLocaleDependencies`；另有 epic-44 的 `WifiTransferDependencies`（不在原 6 個內，但列在本 Issue 範圍）。(2) 寫「`buildReaderScreen` 的暫時組裝」，Issue 12 已將 `readerFeatureDependenciesFromLegacy` 整個刪除，`buildReaderScreen` 現在只是接 `dependencies` 的薄包裝，**沒有暫時組裝可移除**。兩點都於 Task 5 回寫 `issues.md`／`epic.md` | `lib/screens/library_screen_dependencies.dart`、`lib/screens/reader_screen_route.dart`（27 行） |
| 現況：欄位全是 nullable | 4 個舊 bundle 與 `ElinkBookApp`／`AdaptiveShellScaffold`／`SourcesHomeScreen` 上的 `computeFingerprint`、`isMobileDataConnection`、`downloadQueueController`、`checkNetworkAvailability`、`wifiTransferDependencies` 全是 nullable；`main()` 實際全部恆提供 | `lib/main.dart:275-369,375-430` |
| **`LibraryScreen` 有兩組死參數** | `LibraryScreen.cloudAccountDependencies` 與 `.computeFingerprint` 在 `library_screen.dart` 內**只有宣告與建構子**（`grep -n "cloudAccountDependencies\|computeFingerprint" lib/screens/library_screen.dart` 僅 67、72、85、87 行），沒有任何讀取。真正使用的只有 `remoteLibraryDependencies.remoteServerRepository`／`.createOpdsClient`（`_handleRedownload`，515-516 行）、`isMobileDataConnection`（533 行）、`themeDependencies.isEinkMode`（459、664、853、1221、1303 行）。遷移後 `LibraryScreen` 收 `sources` 只為取這三個欄位，死參數隨舊 bundle 一併消失（不算行為變化） | `lib/screens/library_screen.dart` |
| `SourcesHomeScreen` 的 null 閘門 | `googleDriveEnabled`／`oneDriveEnabled`／`remoteEnabled`（各自檢查 client／repository／`computeFingerprint`／`downloadQueueController` 非 null）、`wifiTransferEnabled`（`wifiTransferDependencies` 四欄位非 null）、`if (downloadQueueController != null) DownloadQueuePanel(...)`。非 enabled 時 tile 顯示 `sourcesHomeCloudNotLinkedSubtitle`／`sourcesHomeRemoteLibraryNotConfiguredSubtitle` 副標並停用。正式環境從不出現這些狀態 | `lib/screens/sources_home_screen.dart:157-281` |
| `SourcesHomeScreen` 重組 `RemoteCatalogDependencies` | `_openRemoteLibrary` 用 `computeFingerprint!`、`remoteLibraryDependencies.thumbnailCache!`、`.createOpdsClient!` 現場組出 `RemoteCatalogDependencies`；遷移後改取 `sources.*`，這是 Review Focus 1 的觀察點 | `sources_home_screen.dart:124-141` |
| `WifiTransferDependencies` 欄位重複 | 4 欄位中 `libraryRepository`、`importService` 已存在於 `ReaderFeatureDependencies`（`libraryRepository`／`bookImportService`），`computeFingerprint` 與 `SourceDependencies.computeFingerprint` 同一個物件，只有 `checkNetworkAvailability` 是 WiFi 專屬。`ElinkBookApp.build()` 目前用 `widget.readerFeatures.libraryRepository` 等現場組裝一份 | `lib/main.dart:522-527`、`wifi_transfer_dependencies.dart` |
| `SettingsScaffold` 的 null 閘門 | 雲端帳號入口：`cloudAccountRepository == null \|\| googleDriveOAuthClient == null \|\| oneDriveOAuthClient == null ? null : …`（`:422-441`）；主題圓點／E-Ink 開關／語言選擇用 `onThemeChanged?.call`、`onChanged: widget.onEinkModeChanged`、`onLocaleChanged?.call`（nullable callback，null 時開關停用） | `lib/screens/settings_scaffold.dart` |
| 外觀狀態的擁有者 | 主題／E-Ink／語言覆寫的**可變狀態**在 `_ElinkBookAppState`（`_theme`、`_isEinkMode`、`_localeOverride`）；`initialTheme`／`initialEinkMode`／`initialLocaleOverride`／`themePreferences`／`localePreferences` 由 `main()` 傳入。因此外觀組不可能像其他三組「`main()` 建一次」——它每次 `setState` 都要反映新值 | `main.dart:432-479` |
| 呼叫端數量（測試） | `ElinkBookApp(` 18（`app_lifecycle_sync` 4、`elinkbook_app_wiring` 3、`elinkbook_app_locale` 8、`theme_test` 3）；`AdaptiveShellScaffold(` 9；`SourcesHomeScreen(` 14；`LibraryScreen(` 約 137（含 integration 4）；`SettingsScaffold(` 約 53；`LibraryThemeDependencies(` 5、`LibraryLocaleDependencies(` 3、`LibraryCloudAccountDependencies(` 5、`LibraryRemoteLibraryDependencies(` 8、`WifiTransferDependencies(` 3 | `grep -rc` |
| 孤兒 ARB 鍵 | `readerSaveAsPresetUnavailableMessage` 在 `lib/` 內只剩 ARB 與 `flutter gen-l10n` 產生檔（`app_zh_TW.arb`、`app_zh_CN.arb`、`app_zh.arb`、`app_en.arb`、`app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`），無任何 Dart 使用端（Issue 11 程式審查 M-5） | `grep -rln readerSaveAsPresetUnavailableMessage lib` |
| 可重用的測試 fake | `FakeCloudAccountRepository`、`FakeCloudStorageClient`、`FakeOpdsClient`、`FakeRemoteServerRepository`、`FakeRemoteThumbnailCache`、`FakeFingerprintComputer`（皆已存在於 `test/support/`，建構子無必填參數）；`GoogleDriveOAuthClient(accountRepository:)`／`OneDriveOAuthClient(accountRepository:)` 建構時不做 I/O，`settings_scaffold_test` 已直接使用 | `test/support/`、`settings_scaffold_test.dart:302-313` |
| `DownloadQueueController` | 建構子只有必填 `onDuplicateConfirm: Future<bool> Function(String)`；`ChangeNotifier`，無 I/O | `lib/downloads/download_queue_controller.dart:115` |

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **`SourcesHomeScreen` 現場重組 `RemoteCatalogDependencies`／`WifiTransferScreen` 參數時，欄位來源取錯或漏轉。**Issue 7 曾因 `computeFingerprint` 漏轉發而通過 analyze 與測試；使用者會看到「下載後重複偵測失效」。→ Task 2 測試：開遠端書庫後 `RemoteServerListScreen.dependencies.computeFingerprint`／`.thumbnailCache`／`.createOpdsClient` 與傳入的 `SourceDependencies` 同一實例；開 WiFi 傳書後 `WifiTransferScreen.computeFingerprint`／`.checkNetworkAvailability` 同一實例、`libraryRepository`／`importService` 與 `readerFeatures` 同一實例；開 Google Drive 後 `CloudBrowserScreen.client`／`.downloadQueueController` 同一實例。
2. **主題／E-Ink／語言切換使 `ElinkBookApp` 重建時，三處畫面看到的外觀不同步，或其他三組被重新建構成新實例。**舊做法在 `build()` 內 new `LibraryThemeDependencies` 一份給整棵樹；新做法 `AppearanceDependencies` 是每次 `build()` 由 State 現組的快照（這是它與其他三組唯一的差異），但 `readerFeatures`／`sync`／`sources` 必須仍是 `main()` 建的同一實例。→ Task 3／4 wiring 測試：切換主題、E-Ink、語言後，`LibraryScreen`、`SourcesHomeScreen`、`SettingsScaffold` 三者的 `appearance` 同一個新快照且值已更新；`dependencies`／`sources`／`sync` 仍 `same(...)` 原組。
3. **E-Ink 模式只在其中一個畫面生效。**`isEinkMode` 原本從 `themeDependencies` 分別傳給 `LibraryScreen`、`SourcesHomeScreen`、`SettingsScaffold`（三條路徑）；漏掉一條使用者會看到某頁沒套 E-Ink 修飾子。→ Task 3 新測試：E-Ink 開啟後三個畫面的 `appearance.isEinkMode` 皆為 true，且 `SourcesHomeScreen` 開遠端書庫時 `RemoteServerListScreen.isEinkMode` 為 true。
4. **原本因 null 而停用的入口，現在恆啟用／恆顯示。**正式環境本來就恆提供，不是回歸；但若不逐項列出，後人無法分辨「刪掉的測試」是合理還是掩蓋。→ 附錄 B 逐項記錄（Google Drive／OneDrive／遠端書庫 tile、WiFi 傳書 tile、下載佇列面板、設定頁雲端帳號入口、主題／E-Ink／語言 callback、書架重新下載的「遠端功能未啟用」前置檢查）。
5. **`LibraryScreen._handleRedownload` 把仍可達的失敗路徑一起刪掉。**移除 `remoteServerRepository == null \|\| createOpdsClient == null` 時，`remoteServerId == null \|\| remoteDownloadUrl == null`（書本資料不完整）仍可達，必須保留 `libraryRemoteDisabledMessage` 提示。→ Task 2 保留／補強該案測試：書本缺 `remoteDownloadUrl` 時仍顯示提示且不呼叫 `createOpdsClient`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/source_dependencies.dart` | 新增 | `SourceDependencies`（12 欄位，non-null required） |
| `app/lib/screens/appearance_dependencies.dart` | 新增 | `AppearanceDependencies`（外觀快照：3 個值＋3 個 non-null callback） |
| `app/lib/screens/app_dependencies.dart` | 新增 | `AppDependencies`（`readerFeatures`／`sync`／`sources` 三組靜態依賴的容器，只在 `main.dart` 與 `ElinkBookApp` 使用） |
| `app/lib/screens/sources_home_screen.dart` | 修改 | 改收 `readerFeatures`＋`sources`＋`appearance`，移除 null 閘門 |
| `app/lib/screens/library_screen.dart` | 修改 | 加收 `sources`（取代 `cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`）與 `appearance`（取代 `themeDependencies`） |
| `app/lib/screens/settings_scaffold.dart` | 修改 | 加收 `sources`（取代 3 個雲端欄位）與 `appearance`（取代 6 個主題／語言欄位） |
| `app/lib/screens/adaptive_shell_scaffold.dart` | 修改 | 改收 `readerFeatures`／`sync`／`sources`／`appearance` 四組 |
| `app/lib/main.dart` | 修改 | `main()` 建構 `SourceDependencies` 與 `AppDependencies`；`ElinkBookApp` 改收 `dependencies`，`build()` 現組 `AppearanceDependencies` |
| `app/lib/screens/library_screen_dependencies.dart` | 刪除 | 4 個舊 bundle 全數移除，檔案整個刪除 |
| `app/lib/wifi_transfer/wifi_transfer_dependencies.dart` | 刪除 | 欄位併入 `SourceDependencies`／`ReaderFeatureDependencies` |
| `app/lib/l10n/app_{zh_TW,zh_CN,zh,en}.arb` 及 3 個產生檔 | 修改 | 移除孤兒鍵 `readerSaveAsPresetUnavailableMessage`（Task 5） |
| `app/test/support/fake_source_dependencies.dart`、`fake_appearance_dependencies.dart`、`fake_app_dependencies.dart`（各附 `_test.dart`） | 新增 | 預設全 fake 的工廠 |
| `app/test/screens/{sources_home_screen,library_screen,settings_scaffold,settings_scaffold_reading_stats,adaptive_shell_scaffold,library_search_screen}_test.dart` | 修改 | 依新建構子遷移 |
| `app/test/screens/library_screen_dependencies_test.dart` | 刪除 | 被測型別全數刪除 |
| `app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/{locale_switch,elinkbook_app_locale}_test.dart`、`app/test/theme/theme_test.dart` | 修改 | 同上 |
| `app/integration_test/{library_screen,smoke}_test.dart` | 修改 | 同上（只能本機靜態驗證，真機見 Task 5） |
| `docs/adr/0037-…md`、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 措辭同步與進度 |

---

### Task 0：建立基準、worktree 與取得設計決定

**Files:** 無程式修改。

- [ ] **Step 1: 確認前提（開工前再對照一次）**

在專案根目錄確認工作區狀態：
```bash
git status --short
git log --oneline -1
```

在 `app/` 目錄下執行前提檢查（PowerShell / Bash 均適用）：
```bash
git grep -l -E "LibraryCloudAccountDependencies|LibraryRemoteLibraryDependencies|LibraryThemeDependencies|LibraryLocaleDependencies|WifiTransferDependencies" -- lib
git grep -n -E "cloudAccountDependencies|computeFingerprint" -- lib/screens/library_screen.dart
git grep -n -E "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories|LibrarySyncDependencies" -- lib test integration_test
```

Expected：工作樹乾淨；第一組指令列出 `main.dart`、`adaptive_shell_scaffold.dart`、`library_screen.dart`、`library_screen_dependencies.dart`、`settings_scaffold.dart`、`sources_home_screen.dart`、`wifi_transfer_dependencies.dart`（以及可能的 `reader_screen.dart` 註解）；第二組僅 67、72、85、87 行（死參數）；第三組無任何輸出（輸出 0 行，Issue 12 已清乾淨）。任何一項不符，先停下回報。

- [x] **Step 2: 向使用者呈報三個設計決定並等待回答（回答前不得改 `lib/`、不得改測試）**

```
Q1  AppDependencies 與 AppearanceDependencies 的關係。ADR 0037 §1 寫「容器 AppDependencies 持有四組」，
    但外觀組含可變狀態（目前主題、E-Ink、語言覆寫），擁有者是 _ElinkBookAppState，不是 main()。
    A) 【建議】AppDependencies 只持有三組靜態依賴（readerFeatures／sync／sources，main() 建一次）；
       AppearanceDependencies 是「畫面看到的外觀快照」，每次 _ElinkBookAppState.build() 依目前 State 現組；
       initialTheme／initialEinkMode／initialLocaleOverride／themePreferences／localePreferences 留在
       ElinkBookApp 建構子（它們是「初始狀態與持久化」，不是被注入的服務）。代價：ADR §1 要改一句話
       （四組 → 三組靜態＋一組外觀快照）。
    B) AppDependencies 持有四組，其中 appearance 是「初始外觀＋持久化物件」的設定包，
       ElinkBookApp 再用它另外組一個畫面用快照：多一個類別、兩種外觀型別，容易混淆。
Q2  WiFi 傳書的開關（ADR 0037 §3 與 issues.md 第 13 列要求「由 null 檢查改為明確表示」）。
    A) 【建議】不留開關：WifiTransferDependencies 刪除，WiFi 傳書 tile 恆顯示（比照 Issue 11 對 TTS 的
       決定：正式環境本來就恆提供，沒有真實的「不可用」情境，YAGNI）。
       checkNetworkAvailability 併入 SourceDependencies（non-null）。
    B) 保留明確旗標 SourceDependencies.isWifiTransferAvailable（bool）：目前沒有任何情境會是 false，
       只多一個永遠為 true 的欄位與一個測試用的 false 分支；日後 iOS 或受限平台才需要時再加。
Q3  外觀組要不要帶 equality（==／hashCode）？
    A) 【建議】不要：快照每次 build 新建，畫面沒有以 == 判斷是否重建的需求（LibraryScreen 比對的是
       readerFeatures 那一組，不是外觀）；多一組 equality 要連帶維護與測試。
    B) 要：為了 didUpdateWidget 精準比較；目前無使用端，屬投機。
```

使用者於 2026-10-08 回覆「同意」（即 Q1=A、Q2=A、Q3=A），原話已記入附錄 A。

- [ ] **Step 3: 建立 worktree 與分支**

使用 `git worktree`（name：`epic-54-issue-13`）建立隔離 worktree：
```powershell
git worktree add -b epic-54-issue-13 .worktrees/epic-54-issue-13 main
```
在 `.worktrees/epic-54-issue-13/app` 目錄下執行：
```powershell
flutter pub get
```

（Issue 12 曾因同時存在 `.worktrees/epic-54-issue-12` 與原生 worktree 兩套而需在發 PR 前擇一；本 Issue 只建一套。）

- [ ] **Step 4: 記錄基準並補附錄 A**

```bash
flutter test test/screens/sources_home_screen_test.dart test/screens/library_screen_test.dart \
  test/screens/settings_scaffold_test.dart test/screens/settings_scaffold_reading_stats_test.dart \
  test/screens/adaptive_shell_scaffold_test.dart test/screens/library_screen_dependencies_test.dart \
  test/screens/library_search_screen_test.dart test/elinkbook_app_wiring_test.dart \
  test/app_lifecycle_sync_test.dart test/navigation_test.dart test/l10n/locale_switch_test.dart \
  test/l10n/elinkbook_app_locale_test.dart test/theme/theme_test.dart \
  test/support 2>&1 | tail -3
flutter analyze 2>&1 | tail -2
```

把「通過數」記入附錄 C（後續各 Task 的測試數算式以它為基準）。`flutter analyze` 須為 "No issues found!"。

---

### Task 1：三個新依賴型別與測試工廠（純新增，不動既有畫面）

**Files:**
- Create: `app/lib/screens/source_dependencies.dart`、`app/lib/screens/appearance_dependencies.dart`
- Create: `app/test/support/fake_source_dependencies.dart`、`fake_source_dependencies_test.dart`
- Create: `app/test/support/fake_appearance_dependencies.dart`、`fake_appearance_dependencies_test.dart`

（`AppDependencies` 與 `fake_app_dependencies.dart` 留到 Task 4，等 `ElinkBookApp` 要用時再建，避免出現無使用端的型別。）

**Interfaces:**
- Produces（後續所有 Task 使用，名稱與型別不得更動）：

```dart
class SourceDependencies {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;
  final OneDriveOAuthClient oneDriveOAuthClient;
  final CloudStorageClient googleDriveStorageClient;
  final CloudStorageClient oneDriveStorageClient;
  final RemoteServerRepository remoteServerRepository;
  final OpdsClient Function() createOpdsClient;
  final RemoteThumbnailCache thumbnailCache;
  final ComputeRemoteFingerprint computeFingerprint;
  final Future<bool> Function() isMobileDataConnection;
  final CheckNetworkAvailability checkNetworkAvailability;
  final DownloadQueueController downloadQueueController;
  const SourceDependencies({required …十二個欄位});
}
class AppearanceDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final AppLocale? currentLocaleOverride;           // null＝跟隨系統
  final ValueChanged<AppTheme> onThemeChanged;
  final ValueChanged<bool> onEinkModeChanged;
  final ValueChanged<AppLocale?> onLocaleChanged;
  const AppearanceDependencies({required …六個欄位});
}
SourceDependencies fakeSourceDependencies({…十二個同名可選參數…});
AppearanceDependencies fakeAppearanceDependencies({
  AppTheme currentTheme = AppTheme.light,
  bool isEinkMode = false,
  AppLocale? currentLocaleOverride,
  ValueChanged<AppTheme>? onThemeChanged,
  ValueChanged<bool>? onEinkModeChanged,
  ValueChanged<AppLocale?>? onLocaleChanged,
});
```

- [ ] **Step 1: 寫失敗測試**

`test/support/fake_source_dependencies_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import 'fake_fingerprint_computer.dart';
import 'fake_source_dependencies.dart';

void main() {
  test('fakeSourceDependencies 預設全部有值（non-null），且每次呼叫是新實例', () async {
    final a = fakeSourceDependencies();
    final b = fakeSourceDependencies();
    expect(identical(a.downloadQueueController, b.downloadQueueController), isFalse);
    expect(identical(a.remoteServerRepository, b.remoteServerRepository), isFalse);
    expect(identical(a.cloudAccountRepository, b.cloudAccountRepository), isFalse);
    expect(await a.isMobileDataConnection(), isFalse);
    expect(
      (await a.checkNetworkAvailability()).kind,
      NetworkAvailabilityKind.unavailable,
    );
    expect(a.createOpdsClient(), isNotNull);
  });

  test('fakeSourceDependencies 具名覆寫原樣帶入（同一實例）', () {
    final fingerprint = FakeFingerprintComputer().call;
    final deps = fakeSourceDependencies(computeFingerprint: fingerprint);
    expect(deps.computeFingerprint, same(fingerprint));
  });

  test('fakeSourceDependencies 具名 cloudAccountRepository 正確原樣帶入', () {
    final account = fakeSourceDependencies().cloudAccountRepository;
    final deps = fakeSourceDependencies(cloudAccountRepository: account);
    expect(deps.cloudAccountRepository, same(account));
  });
}
```

`test/support/fake_appearance_dependencies_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/theme/app_theme.dart';

import 'fake_appearance_dependencies.dart';

void main() {
  test('fakeAppearanceDependencies 預設為淺色、非 E-Ink、跟隨系統，callback 為 no-op 且 non-null', () {
    final deps = fakeAppearanceDependencies();
    expect(deps.currentTheme, AppTheme.light);
    expect(deps.isEinkMode, isFalse);
    expect(deps.currentLocaleOverride, isNull);
    deps.onThemeChanged(AppTheme.dark);
    deps.onEinkModeChanged(true);
    deps.onLocaleChanged(null);
  });

  test('fakeAppearanceDependencies 具名覆寫原樣帶入', () {
    AppTheme? changed;
    final deps = fakeAppearanceDependencies(
      currentTheme: AppTheme.sepia,
      isEinkMode: true,
      currentLocaleOverride: AppLocale.en,
      onThemeChanged: (t) => changed = t,
    );
    deps.onThemeChanged(AppTheme.dark);
    expect(deps.currentTheme, AppTheme.sepia);
    expect(deps.isEinkMode, isTrue);
    expect(deps.currentLocaleOverride, AppLocale.en);
    expect(changed, AppTheme.dark);
  });
}
```

（`AppTheme.sepia`、`AppLocale.en` 的實際列舉成員名稱以 `lib/theme/app_theme.dart`、`lib/l10n/app_locale.dart` 為準，開工時對照後調整測試。）

- [ ] **Step 2: 跑測試確認失敗**

Run：`flutter test test/support/fake_source_dependencies_test.dart test/support/fake_appearance_dependencies_test.dart`
Expected：編譯失敗（檔案與型別不存在）。

- [ ] **Step 3: 實作**

`lib/screens/source_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../downloads/download_queue_controller.dart';
import '../library/book_content_fingerprint.dart';
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
import '../remote/remote_thumbnail_cache.dart';
import '../wifi_transfer/network_availability.dart';

/// 來源依賴組（ADR 0037）：雲端帳號與 Google Drive／OneDrive、OPDS／Calibre 遠端書庫、
/// 下載佇列、WiFi 傳書的網路偵測，以及這些來源共用的內容指紋與行動網路判斷。
/// 「來源」頁（`SourcesHomeScreen`）、書架（重新下載遠端書）與設定頁（雲端帳號入口）
/// 接收這一個物件，取代 epic-26 Issue 7 的 `LibraryCloudAccountDependencies`／
/// `LibraryRemoteLibraryDependencies` 與 epic-44 的 `WifiTransferDependencies`。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好。WiFi 傳書不設開關（正式
/// 環境恆提供，見 ADR 0037 §3）。`computeFingerprint` 同時服務雲端匯入、OPDS 下載與
/// WiFi 傳書，只有這一個來源，不得各處自行傳入。
@immutable
class SourceDependencies {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;
  final OneDriveOAuthClient oneDriveOAuthClient;
  final CloudStorageClient googleDriveStorageClient;
  final CloudStorageClient oneDriveStorageClient;
  final RemoteServerRepository remoteServerRepository;

  /// OPDS client 有內部可變的 session 狀態（走訪過的 feed），每次使用要新建，所以是工廠函式。
  final OpdsClient Function() createOpdsClient;
  final RemoteThumbnailCache thumbnailCache;
  final ComputeRemoteFingerprint computeFingerprint;
  final Future<bool> Function() isMobileDataConnection;
  final CheckNetworkAvailability checkNetworkAvailability;
  final DownloadQueueController downloadQueueController;

  const SourceDependencies({
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
    required this.oneDriveOAuthClient,
    required this.googleDriveStorageClient,
    required this.oneDriveStorageClient,
    required this.remoteServerRepository,
    required this.createOpdsClient,
    required this.thumbnailCache,
    required this.computeFingerprint,
    required this.isMobileDataConnection,
    required this.checkNetworkAvailability,
    required this.downloadQueueController,
  });
}
```

`lib/screens/appearance_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

/// 外觀依賴組（ADR 0037）：主題、E-Ink 修飾子與介面語言，加上三個變更 callback。
///
/// 與其他三組不同：它是**快照**，不是 `main()` 建一次的服務。可變狀態的擁有者是
/// `_ElinkBookAppState`，每次 `build()` 依目前 State 組出新的快照往下傳；畫面只讀值、
/// 呼叫 callback，不持有狀態。三個 callback 為 non-null——正式環境與測試都恆有處理者。
/// `currentLocaleOverride == null` 代表跟隨系統（比照 `AppLocalePreferences` 的 nullable 語意）。
@immutable
class AppearanceDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppTheme> onThemeChanged;
  final ValueChanged<bool> onEinkModeChanged;
  final ValueChanged<AppLocale?> onLocaleChanged;

  const AppearanceDependencies({
    required this.currentTheme,
    required this.isEinkMode,
    required this.currentLocaleOverride,
    required this.onThemeChanged,
    required this.onEinkModeChanged,
    required this.onLocaleChanged,
  });
}
```

`test/support/fake_source_dependencies.dart`：

```dart
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';
import 'package:elinkbook/screens/source_dependencies.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import 'fake_cloud_account_repository.dart';
import 'fake_cloud_storage_client.dart';
import 'fake_fingerprint_computer.dart';
import 'fake_opds_client.dart';
import 'fake_remote_server_repository.dart';
import 'fake_remote_thumbnail_cache.dart';

/// 預設全 fake 的來源依賴組（ADR 0037）。只覆寫情境需要的欄位；每次呼叫都建新實例。
/// OAuth client 預設與 [cloudAccountRepository] 共用同一個帳號 repository
/// （`GoogleDriveOAuthClient`／`OneDriveOAuthClient` 建構時不做 I/O）。
SourceDependencies fakeSourceDependencies({
  CloudAccountRepository? cloudAccountRepository,
  GoogleDriveOAuthClient? googleDriveOAuthClient,
  OneDriveOAuthClient? oneDriveOAuthClient,
  CloudStorageClient? googleDriveStorageClient,
  CloudStorageClient? oneDriveStorageClient,
  RemoteServerRepository? remoteServerRepository,
  OpdsClient Function()? createOpdsClient,
  RemoteThumbnailCache? thumbnailCache,
  ComputeRemoteFingerprint? computeFingerprint,
  Future<bool> Function()? isMobileDataConnection,
  CheckNetworkAvailability? checkNetworkAvailability,
  DownloadQueueController? downloadQueueController,
}) {
  final account = cloudAccountRepository ?? FakeCloudAccountRepository();
  return SourceDependencies(
    cloudAccountRepository: account,
    googleDriveOAuthClient:
        googleDriveOAuthClient ?? GoogleDriveOAuthClient(accountRepository: account),
    oneDriveOAuthClient:
        oneDriveOAuthClient ?? OneDriveOAuthClient(accountRepository: account),
    googleDriveStorageClient: googleDriveStorageClient ?? FakeCloudStorageClient(),
    oneDriveStorageClient: oneDriveStorageClient ?? FakeCloudStorageClient(),
    remoteServerRepository: remoteServerRepository ?? FakeRemoteServerRepository(),
    createOpdsClient: createOpdsClient ?? () => FakeOpdsClient(),
    thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
    computeFingerprint: computeFingerprint ?? FakeFingerprintComputer().call,
    isMobileDataConnection: isMobileDataConnection ?? () async => false,
    checkNetworkAvailability: checkNetworkAvailability ??
        () async =>
            const NetworkAvailability(kind: NetworkAvailabilityKind.unavailable),
    downloadQueueController: downloadQueueController ??
        DownloadQueueController(onDuplicateConfirm: (_) async => false),
  );
}
```

`test/support/fake_appearance_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/screens/appearance_dependencies.dart';
import 'package:elinkbook/theme/app_theme.dart';

/// 預設淺色、非 E-Ink、跟隨系統、callback 為 no-op 的外觀快照（ADR 0037）。
AppearanceDependencies fakeAppearanceDependencies({
  AppTheme currentTheme = AppTheme.light,
  bool isEinkMode = false,
  AppLocale? currentLocaleOverride,
  ValueChanged<AppTheme>? onThemeChanged,
  ValueChanged<bool>? onEinkModeChanged,
  ValueChanged<AppLocale?>? onLocaleChanged,
}) {
  return AppearanceDependencies(
    currentTheme: currentTheme,
    isEinkMode: isEinkMode,
    currentLocaleOverride: currentLocaleOverride,
    onThemeChanged: onThemeChanged ?? (_) {},
    onEinkModeChanged: onEinkModeChanged ?? (_) {},
    onLocaleChanged: onLocaleChanged ?? (_) {},
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run：`flutter test test/support/fake_source_dependencies_test.dart test/support/fake_appearance_dependencies_test.dart && flutter analyze`
Expected：全過；analyze 乾淨。

- [ ] **Step 5: Commit**

```bash
git add lib/screens/source_dependencies.dart lib/screens/appearance_dependencies.dart \
  test/support/fake_source_dependencies.dart test/support/fake_source_dependencies_test.dart \
  test/support/fake_appearance_dependencies.dart test/support/fake_appearance_dependencies_test.dart
git commit -m "feat(epic-54): Issue 13 新增 SourceDependencies、AppearanceDependencies 與測試工廠" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：來源組——`SourcesHomeScreen`／`LibraryScreen`／`SettingsScaffold`／`AdaptiveShellScaffold`／`ElinkBookApp`／`main()` 原子切換

**Files:**
- Modify: `app/lib/screens/sources_home_screen.dart`、`library_screen.dart`、`settings_scaffold.dart`、`adaptive_shell_scaffold.dart`、`app/lib/main.dart`
- Delete: `app/lib/wifi_transfer/wifi_transfer_dependencies.dart`
- Modify（刪除其中兩個 bundle）: `app/lib/screens/library_screen_dependencies.dart`（保留 Theme／Locale，Task 3 才刪）
- Modify（註解清理）: `app/lib/screens/reader_screen.dart`（148 行附近提到 `LibraryThemeDependencies.isEinkMode` 的註解，留到 Task 3 改，本 Task 不動）
- Test: `app/test/screens/{sources_home_screen,library_screen,settings_scaffold,settings_scaffold_reading_stats,adaptive_shell_scaffold,library_search_screen,library_screen_dependencies}_test.dart`、`app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/{locale_switch,elinkbook_app_locale}_test.dart`、`app/test/theme/theme_test.dart`、`app/integration_test/{library_screen,smoke}_test.dart`

> **為什麼這六處必須在同一個 Task（同 Issue 12 Task 3）：** `AdaptiveShellScaffold` 長駐 `IndexedStack`，首幀就建構 `LibraryScreen`／`SourcesHomeScreen`／`SettingsScaffold`；`ElinkBookApp` 又用 nullable 欄位組出舊 bundle。單獨把任一畫面改成 non-null 的 `sources`，上層沒有東西可以給它。**Step 1～3 中途不 commit**，Task 結束時才一次 commit。工作順序：`SourcesHomeScreen` → `LibraryScreen` → `SettingsScaffold` → `AdaptiveShellScaffold` → `ElinkBookApp`／`main()`，以 `flutter analyze` 的錯誤清單當遺漏檢查。

**Interfaces:**
- Consumes：Task 1 的 `SourceDependencies`、`fakeSourceDependencies`；Issue 11／12 的 `ReaderFeatureDependencies`。
- Produces：
  - `SourcesHomeScreen({super.key, required ReaderFeatureDependencies readerFeatures, required SourceDependencies sources, bool isEinkMode = false, VoidCallback? onNavigateToLibrary, VoidCallback? onNavigateToSettings})`——**移除** `repository`／`importService`／`cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`／`downloadQueueController`／`wifiTransferDependencies`。公開欄位 `readerFeatures`、`sources`。（`isEinkMode` 本 Task 保留，Task 3 才換成 `appearance`。）
  - `LibraryScreen`——新增 `required SourceDependencies sources`；**移除** `cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`。公開欄位 `sources`。（`themeDependencies` 本 Task 保留。）
  - `SettingsScaffold`——新增 `required SourceDependencies sources`；**移除** `cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`。公開欄位 `sources`。
  - `AdaptiveShellScaffold`——新增 `required SourceDependencies sources`；**移除** `cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`／`downloadQueueController`／`wifiTransferDependencies`。公開欄位 `sources`。
  - `ElinkBookApp`——新增 `required SourceDependencies sources`；**移除** `cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient`／`remoteServerRepository`／`createOpdsClient`／`computeFingerprint`／`thumbnailCache`／`isMobileDataConnection`／`downloadQueueController`／`checkNetworkAvailability`（共 12 個）。

遷移對照（`sources_home_screen.dart`）：

| 位置 | 舊 | 新 |
|---|---|---|
| 本機匯入 | `importService`／`repository` | `readerFeatures.bookImportService`／`readerFeatures.libraryRepository` |
| 雲端 tile | `googleDriveEnabled`／`oneDriveEnabled` 四條件與 `enabled:`／`subtitle:`／`onTap: enabled ? … : null` | 移除條件；tile 恆啟用，不再有 `sourcesHomeCloudNotLinkedSubtitle` 副標；`onTap: () => _openGoogleDriveBrowser(context)`，內部用 `sources.googleDriveStorageClient`、`sources.computeFingerprint`、`sources.isMobileDataConnection`、`sources.downloadQueueController` |
| 遠端書庫 tile | `remoteEnabled` 五條件 | 移除條件，副標 `sourcesHomeRemoteLibraryNotConfiguredSubtitle` 一併不再使用；`RemoteServerListScreen(repository: sources.remoteServerRepository, dependencies: RemoteCatalogDependencies(computeFingerprint: sources.computeFingerprint, thumbnailCache: sources.thumbnailCache, createOpdsClient: sources.createOpdsClient), …, downloadQueueController: sources.downloadQueueController)` |
| WiFi tile | `if (wifiTransferEnabled)` | 移除條件，tile 恆顯示；`WifiTransferScreen(libraryRepository: readerFeatures.libraryRepository, importService: readerFeatures.bookImportService, computeFingerprint: sources.computeFingerprint, checkNetworkAvailability: sources.checkNetworkAvailability)` |
| 下載佇列 | `if (downloadQueueController != null) DownloadQueuePanel(...)` | 恆顯示 `DownloadQueuePanel(controller: sources.downloadQueueController)` |

> 副標對應的 ARB 鍵（`sourcesHomeCloudNotLinkedSubtitle`、`sourcesHomeRemoteLibraryNotConfiguredSubtitle`）移除使用端後**變成孤兒**。本 Issue 範圍只處理 `readerSaveAsPresetUnavailableMessage`（Task 5）；這兩個新孤兒鍵先用 `grep -rn` 確認確實無其他使用端，**一併列入 Task 5 的 ARB 清理**（同一個機制、同一次 `flutter gen-l10n`），並在 `epic.md` 記錄。若 grep 發現仍有其他使用端，保留該鍵。

遷移對照（`library_screen.dart`）：

| 舊 | 新 |
|---|---|
| `widget.remoteLibraryDependencies.remoteServerRepository`／`.createOpdsClient` | `widget.sources.remoteServerRepository`／`widget.sources.createOpdsClient` |
| `_handleRedownload` 的 `remoteServerRepository == null \|\| createOpdsClient == null \|\| remoteServerId == null \|\| remoteDownloadUrl == null` | 只留 `remoteServerId == null \|\| remoteDownloadUrl == null`（書本資料不完整，仍可達，保留 `libraryRemoteDisabledMessage` 提示，Review Focus 5） |
| `await (widget.isMobileDataConnection?.call() ?? Future.value(false))` | `await widget.sources.isMobileDataConnection()` |
| `cloudAccountDependencies`／`computeFingerprint` 欄位 | 刪除（死參數，見「已查證的事實」） |

遷移對照（`settings_scaffold.dart`）：

| 舊 | 新 |
|---|---|
| 雲端帳號入口 `cloudAccountRepository == null \|\| … ? null : …` 與 `!` | 恆可點；`CloudAccountSettingsScreen(cloudAccountRepository: widget.sources.cloudAccountRepository, googleDriveOAuthClient: widget.sources.googleDriveOAuthClient, oneDriveOAuthClient: widget.sources.oneDriveOAuthClient)` |

遷移對照（`adaptive_shell_scaffold.dart`）：`SourcesHomeScreen(readerFeatures: widget.readerFeatures, sources: widget.sources, isEinkMode: widget.themeDependencies.isEinkMode, …)`；`LibraryScreen(dependencies: widget.readerFeatures, sources: widget.sources, themeDependencies: …, …)`；`SettingsScaffold(readerFeatures: …, sync: …, sources: widget.sources, …)`；移除 `import '../downloads/download_queue_controller.dart'`、`book_content_fingerprint.dart`、`wifi_transfer_dependencies.dart` 等不再使用者（以 analyze 為準）。

- [ ] **Step 1: 改測試（先紅）**

0. **`SourcesHomeScreen`（14 處）：**

```dart
// 舊
SourcesHomeScreen(
  repository: FakeLibraryRepository(),
  importService: importService,
  cloudAccountDependencies: LibraryCloudAccountDependencies(googleDriveStorageClient: c),
  computeFingerprint: fp.call,
  downloadQueueController: queue,
  wifiTransferDependencies: WifiTransferDependencies(…),
)
// 新
SourcesHomeScreen(
  readerFeatures: fakeReaderFeatureDependencies(
    libraryRepository: FakeLibraryRepository(), bookImportService: importService,
  ),
  sources: fakeSourceDependencies(
    googleDriveStorageClient: c, computeFingerprint: fp.call, downloadQueueController: queue,
  ),
)
```

   新增測試（Review Focus 1）：

```dart
testWidgets('開遠端書庫時，RemoteServerListScreen 拿到的是 SourceDependencies 內同一批物件', (tester) async {
  final sources = fakeSourceDependencies();
  await pumpLocalizedWidget(tester, SourcesHomeScreen(
    readerFeatures: fakeReaderFeatureDependencies(), sources: sources,
  ));
  await tester.tap(find.byKey(const Key('sources_remote_library_tile')));
  await tester.pumpAndSettle();
  final screen = tester.widget<RemoteServerListScreen>(find.byType(RemoteServerListScreen));
  expect(screen.repository, same(sources.remoteServerRepository));
  expect(screen.dependencies.computeFingerprint, same(sources.computeFingerprint));
  expect(screen.dependencies.thumbnailCache, same(sources.thumbnailCache));
  expect(screen.dependencies.createOpdsClient, same(sources.createOpdsClient));
  expect(screen.downloadQueueController, same(sources.downloadQueueController));
});

testWidgets('開 WiFi 傳書時，WifiTransferScreen 的來源欄位取自 sources、書庫欄位取自 readerFeatures', (tester) async {
  final sources = fakeSourceDependencies();
  final readerFeatures = fakeReaderFeatureDependencies();
  await pumpLocalizedWidget(tester, SourcesHomeScreen(readerFeatures: readerFeatures, sources: sources));
  await tester.tap(find.byKey(const Key('sources_wifi_transfer_tile')));
  await tester.pumpAndSettle();
  final screen = tester.widget<WifiTransferScreen>(find.byType(WifiTransferScreen));
  expect(screen.computeFingerprint, same(sources.computeFingerprint));
  expect(screen.checkNetworkAvailability, same(sources.checkNetworkAvailability));
  expect(screen.libraryRepository, same(readerFeatures.libraryRepository));
  expect(screen.importService, same(readerFeatures.bookImportService));
});
```

   同樣為 Google Drive／OneDrive 各補一案：`CloudBrowserScreen.client`、`.computeFingerprint`、`.downloadQueueController`、`.isMobileDataConnection` 與 `sources` 同一實例（欄位名稱以 `cloud_browser_screen.dart` 實際公開欄位為準）。上述 `Screen.欄位` 若在葉層畫面為私有，改以該畫面既有的可觀察行為（點擊後 `FakeFingerprintComputer.calls`、`checkNetworkAvailability` 被呼叫次數）驗證，**不得為了測試新增公開欄位到葉層畫面**（範圍邊界）。

   被刪的「依賴缺席」測試先以 `grep -n "缺席\|為 null\|未提供\|不顯示\|停用" test/screens/sources_home_screen_test.dart` 列出候選，逐一對照是否「僅驗證缺席」：預期為「雲端/OPDS 依賴缺席時對應項目為停用狀態」「wifiTransferDependencies 為 null 時不顯示 WiFi 傳書入口」「wifiTransferDependencies 任一欄位為 null 時不顯示入口」。逐一記入附錄 B。**「齊全時顯示入口並可點擊導覽」類案例保留**，改寫為新建構子；既有「依賴齊全時點擊 Google Drive/OneDrive/遠端書庫項目導覽至...」測試案例（`sources_home_screen_test.dart:156,180,203`）順手更名為「點擊...」，更貼合 non-null 語意。

1. **`LibraryScreen`／`SettingsScaffold`／`AdaptiveShellScaffold`／`ElinkBookApp`／integration：**
   - 一次性 Node codemod（放 worktree 內已 gitignore 的 `.scratch/`，不進版控，完成後刪除；沿用 Issue 11／12 做法）：在每個 `LibraryScreen(`、`SettingsScaffold(`、`AdaptiveShellScaffold(` 呼叫的開括號後面插入一行 `sources: fakeSourceDependencies(),`（已含 `sources:` 者略過），並補 `import '…support/fake_source_dependencies.dart';`。插入在引數清單最前面，不必解析引數尾端，穩健。`ElinkBookApp(` 同樣插入 `sources: fakeSourceDependencies(),`。
   - 手改不能機械處理者：`library_screen_test` 內 5 處 `remoteLibraryDependencies: LibraryRemoteLibraryDependencies(remoteServerRepository: r, createOpdsClient: c, …)` 與其 `isMobileDataConnection:` 引數，併成同一個 `sources: fakeSourceDependencies(remoteServerRepository: r, createOpdsClient: c, isMobileDataConnection: m)`；`settings_scaffold_test` 的 `cloudAccountRepository:`／`googleDriveOAuthClient:`／`oneDriveOAuthClient:` 三引數併成 `sources: fakeSourceDependencies(cloudAccountRepository: account, googleDriveOAuthClient: …, oneDriveOAuthClient: …)`；`adaptive_shell_scaffold_test` 的 `cloudAccountDependencies:`／`remoteLibraryDependencies:`／`computeFingerprint:`／`isMobileDataConnection:`／`downloadQueueController:`／`wifiTransferDependencies:` 同理；`adaptive_shell_scaffold_test` 的「wifiTransferDependencies 正確原樣傳遞給 SourcesHomeScreen」改寫為「`sources` 與 `readerFeatures` 原樣傳到 `SourcesHomeScreen`」（`same(...)`）。
   - `library_screen_dependencies_test.dart`：刪除 Cloud／Remote 兩個 bundle 的測試（共 4 案），並同步移除檔頭 5 個未使用的 fake import（`fake_cloud_account_repository.dart`、`fake_cloud_storage_client.dart`、`fake_remote_server_repository.dart`、`fake_opds_client.dart`、`fake_remote_thumbnail_cache.dart`），避免 `flutter analyze` 警告；Theme／Locale 兩個 bundle 的測試本 Task 保留，Task 3 一併刪檔。列入附錄 B。
   - 新增 `library_screen_test` 案例（Review Focus 5）：書本缺 `remoteDownloadUrl` 時點重新下載，仍顯示 `libraryRemoteDisabledMessage`、且 `createOpdsClient` 未被呼叫；若該情境已有既有案例，改寫為新建構子並確認斷言保留。被刪的「`remoteServerRepository`／`createOpdsClient` 缺席」案例（`grep -n "libraryRemoteDisabledMessage\|遠端功能未啟用" test/screens/library_screen_test.dart`）記入附錄 B。
   - 被刪的設定頁測試：「雲端帳號入口在三個欄位任一為 null 時停用」類案例；`grep -n "cloudAccount" test/screens/settings_scaffold*_test.dart` 列出候選，逐一記入附錄 B。**`settings_cloud_account_button` 點擊導覽至 `CloudAccountSettingsScreen` 的案例保留**，並補斷言該畫面的三個依賴與 `sources` 同一實例。
   - `elinkbook_app_wiring_test.dart`：既有三個測試改寫為新建構子；其中「每個欄位都與傳入 ElinkBookApp 的值同一實例」一案，雲端／遠端／下載佇列相關斷言改為 `LibraryScreen.sources`、`SourcesHomeScreen.sources`、`SettingsScaffold.sources` 皆 `same(sources)`。

- [ ] **Step 2: 跑測試確認失敗**

Run：`flutter test test/screens/sources_home_screen_test.dart`
Expected：編譯失敗（`readerFeatures`／`sources` 命名參數不存在）。

- [ ] **Step 3: 實作**

1. `SourcesHomeScreen`、`LibraryScreen`、`SettingsScaffold`、`AdaptiveShellScaffold` 依 Interfaces 與上面四張對照表改寫；移除不再使用的 import（以 analyze 為準）。
2. `ElinkBookApp` 依 Interfaces 改為持有 `sources`；`build()` 把 `sources: widget.sources` 傳給 `AdaptiveShellScaffold`，不再組裝 `LibraryCloudAccountDependencies`／`LibraryRemoteLibraryDependencies`／`WifiTransferDependencies`。
3. `main()` 在 `runApp` 前建構 `SourceDependencies`，**值逐字沿用現行 `ElinkBookApp(...)` 的實參（不得改動取值方式）**：

```dart
final sources = SourceDependencies(
  cloudAccountRepository: cloudAccountRepository,
  googleDriveOAuthClient: googleDriveOAuthClient,
  oneDriveOAuthClient: oneDriveOAuthClient,
  googleDriveStorageClient: googleDriveStorageClient,
  oneDriveStorageClient: oneDriveStorageClient,
  remoteServerRepository: remoteServerRepository,
  createOpdsClient: () => OpdsHttpClient(),
  thumbnailCache: thumbnailCache,
  computeFingerprint: computeBookContentFingerprint,
  isMobileDataConnection: _isMobileDataConnection,
  checkNetworkAvailability: checkNetworkAvailability,
  downloadQueueController: downloadQueueController,
);
```

   `runApp(ElinkBookApp(readerFeatures: readerFeatures, sync: sync, sources: sources, navigatorKey: …, initialTheme: …, …))`。
4. 刪除 `lib/wifi_transfer/wifi_transfer_dependencies.dart`；`library_screen_dependencies.dart` 刪除 `LibraryCloudAccountDependencies`、`LibraryRemoteLibraryDependencies` 與其 import（Theme／Locale 保留到 Task 3）。
5. 清理註解中的舊型別名稱：`grep -rn "LibraryCloudAccountDependencies\|LibraryRemoteLibraryDependencies\|WifiTransferDependencies\|wifiTransferDependencies" lib` 預期位置為 `wifi_transfer/` 內文件註解、`remote/remote_catalog_dependencies.dart`（「比照 `RemoteCatalogDependencies`」類說明）、`library_screen.dart` 欄位註解等；改為指向 `SourceDependencies`，**只改型別名稱與必要措辭，不重寫其他說明**。

- [ ] **Step 4: 跑測試確認通過**

```bash
flutter analyze
flutter test test/screens/sources_home_screen_test.dart test/screens/library_screen_test.dart \
  test/screens/settings_scaffold_test.dart test/screens/settings_scaffold_reading_stats_test.dart \
  test/screens/adaptive_shell_scaffold_test.dart test/screens/library_screen_dependencies_test.dart \
  test/screens/library_search_screen_test.dart test/elinkbook_app_wiring_test.dart \
  test/app_lifecycle_sync_test.dart test/navigation_test.dart test/l10n test/theme test/support
```

Expected：analyze 乾淨；全過。通過數算式寫入附錄 C：`基準 − 被刪（附錄 B）＋ 新增`。殘留檢查：

```bash
grep -rn "LibraryCloudAccountDependencies\|LibraryRemoteLibraryDependencies\|WifiTransferDependencies\|wifiTransferDependencies" lib test integration_test
```

Expected：**無輸出**（含註解）。

- [ ] **Step 5: 守衛腳本與提交**

```bash
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
git add lib test integration_test
git commit -m "refactor(epic-54): Issue 13 來源組（雲端、遠端、WiFi 傳書、下載佇列）改收 SourceDependencies" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：外觀組——`LibraryScreen`／`SourcesHomeScreen`／`SettingsScaffold`／`AdaptiveShellScaffold`／`ElinkBookApp` 切換

**Files:**
- Modify: `app/lib/screens/{sources_home_screen,library_screen,settings_scaffold,adaptive_shell_scaffold}.dart`、`app/lib/main.dart`、`app/lib/screens/reader_screen.dart`（僅 148 行附近註解）
- Delete: `app/lib/screens/library_screen_dependencies.dart`、`app/test/screens/library_screen_dependencies_test.dart`
- Test: `app/test/screens/{sources_home_screen,library_screen,settings_scaffold,settings_scaffold_reading_stats,adaptive_shell_scaffold,library_search_screen}_test.dart`、`app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/{locale_switch,elinkbook_app_locale}_test.dart`、`app/test/theme/theme_test.dart`、`app/integration_test/{library_screen,smoke}_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `AppearanceDependencies`、`fakeAppearanceDependencies`；Task 2 的 `sources`。
- Produces：
  - `SourcesHomeScreen`——`isEinkMode` 換成 `required AppearanceDependencies appearance`。
  - `LibraryScreen`——`themeDependencies` 換成 `required AppearanceDependencies appearance`；`widget.themeDependencies.isEinkMode` 全改 `widget.appearance.isEinkMode`。
  - `SettingsScaffold`——`currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`／`currentLocaleOverride`／`onLocaleChanged` 六個欄位換成 `required AppearanceDependencies appearance`；`onNavigateToLibrary`／`onNavigateToSource` 保留。
  - `AdaptiveShellScaffold`——`themeDependencies`／`localeDependencies` 換成 `required AppearanceDependencies appearance`。
  - `ElinkBookApp`——`build()` 現組 `AppearanceDependencies(currentTheme: _theme, isEinkMode: _isEinkMode, currentLocaleOverride: _localeOverride, onThemeChanged: _handleThemeChanged, onEinkModeChanged: _handleEinkModeChanged, onLocaleChanged: _handleLocaleChanged)` 傳給 `AdaptiveShellScaffold`。`initialTheme`／`initialEinkMode`／`initialLocaleOverride`／`themePreferences`／`localePreferences` 維持在 `ElinkBookApp` 建構子（Q1-A）。

遷移對照（`settings_scaffold.dart`）：`widget.currentTheme`→`widget.appearance.currentTheme`；`widget.isEinkMode`→`widget.appearance.isEinkMode`；`widget.onThemeChanged?.call(theme)`→`widget.appearance.onThemeChanged(theme)`；`onChanged: widget.onEinkModeChanged`→`onChanged: widget.appearance.onEinkModeChanged`；`widget.onLocaleChanged?.call(choice.value)`→`widget.appearance.onLocaleChanged(choice.value)`；`widget.currentLocaleOverride`→`widget.appearance.currentLocaleOverride`（`_LanguagePickerSheet` 的參數照舊，由呼叫端傳值）。

- [ ] **Step 1: 改測試（先紅）**

   - Codemod（沿用 Task 2 的 `.scratch/` 腳本改規則）：`LibraryScreen(`、`SettingsScaffold(`、`AdaptiveShellScaffold(`、`SourcesHomeScreen(` 開括號後插入 `appearance: fakeAppearanceDependencies(),`（已含者略過）。手改：含 `themeDependencies: LibraryThemeDependencies(currentTheme: x, isEinkMode: y, onThemeChanged: f, …)` 者（`adaptive_shell_scaffold_test` 2 處、`library_screen_test` 1 處）改為 `appearance: fakeAppearanceDependencies(currentTheme: x, isEinkMode: y, onThemeChanged: f, …)`；含 `localeDependencies: LibraryLocaleDependencies(…)` 者（`adaptive_shell_scaffold_test` 1 處）同理；`SettingsScaffold(currentTheme: …, isEinkMode: …, onThemeChanged: …)` 這類舊引數（`settings_scaffold_test`、`locale_switch_test`、`theme_test`）併入 `appearance: fakeAppearanceDependencies(…)`；`SourcesHomeScreen(isEinkMode: true)` 改 `appearance: fakeAppearanceDependencies(isEinkMode: true)`。
   - 新增測試（Review Focus 2、3）：

```dart
testWidgets('切換主題後，三個畫面看到同一份新的外觀快照，其餘三組仍是原實例', (tester) async {
  final dependencies = /* Task 4 才有 fakeAppDependencies；本 Task 先用 fakeReaderFeatureDependencies／fakeSyncDependencies／fakeSourceDependencies 各一份 */;
  await tester.pumpWidget(ElinkBookApp(readerFeatures: rf, sync: sync, sources: sources));
  await tester.pumpAndSettle();
  final before = tester.widget<LibraryScreen>(find.byType(LibraryScreen)).appearance;
  // 以 theme_test.dart 既有切換主題手法（點選深色主題圓點）觸發 setState
  await tester.tap(find.byKey(const Key('settings_theme_dot_dark')));
  await tester.pumpAndSettle();
  final library = tester.widget<LibraryScreen>(find.byType(LibraryScreen));
  final sourcesHome = tester.widget<SourcesHomeScreen>(find.byType(SourcesHomeScreen, skipOffstage: false));
  final settings = tester.widget<SettingsScaffold>(find.byType(SettingsScaffold, skipOffstage: false));
  expect(library.appearance, isNot(same(before)));          // 新快照
  expect(sourcesHome.appearance, same(library.appearance));  // 三處同一份
  expect(settings.appearance, same(library.appearance));
  expect(library.appearance.currentTheme, AppTheme.dark);
  expect(library.dependencies, same(rf));                    // 其他三組不變
  expect(library.sources, same(sources));
  expect(settings.sync, same(sync));
});

testWidgets('開啟 E-Ink 後，書架、來源頁、設定頁都拿到 isEinkMode == true', (tester) async {
  // 同上，改用設定頁 E-Ink 開關；斷言三處 appearance.isEinkMode 皆 true，
  // 且從來源頁開遠端書庫後 RemoteServerListScreen.isEinkMode 為 true。
});

testWidgets('切換介面語言後，AdaptiveShellScaffold 子畫面 State 保留（書架捲動／搜尋狀態不重置）', (tester) async {
  // 沿用 elinkbook_app_locale_test 既有切語言手法；斷言 appearance.currentLocaleOverride 已更新，
  // 且 LibraryScreen 的 State 物件 identical（IndexedStack 不重建）。
});
```

   測試內的切換步驟以 `test/theme/theme_test.dart`（點擊 `settings_theme_dot_dark`）、`test/l10n/elinkbook_app_locale_test.dart` 既有步驟為準，內聯寫出完整步驟，**不得留空**。
   - 被刪測試：「`onThemeChanged`／`onEinkModeChanged`／`onLocaleChanged` 為 null 時對應控制項停用」類（`grep -n "onThemeChanged\|onEinkModeChanged\|onLocaleChanged" test/screens/settings_scaffold_test.dart | grep -i "null\|停用\|disabled"`）逐一記入附錄 B；`library_screen_dependencies_test.dart` 整檔刪除（剩下 Theme／Locale 持有測試 4 案，型別即將刪除）。

- [ ] **Step 2: 跑測試確認失敗**

Run：`flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected：編譯失敗（`appearance` 命名參數不存在）。

- [ ] **Step 3: 實作**

1. 四個畫面依 Interfaces 與對照表改寫；`AdaptiveShellScaffold` 把 `widget.appearance` 原樣傳給 `LibraryScreen`／`SourcesHomeScreen`／`SettingsScaffold`；`LibrarySearchScreen(isEinkMode: widget.appearance.isEinkMode)`、`ReaderScreen` 的 `isEinkMode` 同樣由呼叫端取值。
2. `ElinkBookApp.build()` 現組 `AppearanceDependencies` 傳入 `AdaptiveShellScaffold(appearance: appearance, …)`。
3. 刪除 `lib/screens/library_screen_dependencies.dart` 與 `test/screens/library_screen_dependencies_test.dart`；`reader_screen.dart` 148 行附近註解的 `LibraryThemeDependencies.isEinkMode` 改為 `AppearanceDependencies.isEinkMode`（只改型別名稱）；`main.dart` 移除 `library_screen_dependencies.dart` import。
4. 清理其他註解中的舊名：`grep -rn "LibraryThemeDependencies\|LibraryLocaleDependencies\|themeDependencies\|localeDependencies" lib test integration_test`，只改型別／欄位名稱與必要措辭。

- [ ] **Step 4: 跑測試確認通過**

```bash
flutter analyze
flutter test test/screens/sources_home_screen_test.dart test/screens/library_screen_test.dart \
  test/screens/settings_scaffold_test.dart test/screens/settings_scaffold_reading_stats_test.dart \
  test/screens/adaptive_shell_scaffold_test.dart test/screens/library_search_screen_test.dart \
  test/elinkbook_app_wiring_test.dart test/app_lifecycle_sync_test.dart test/navigation_test.dart \
  test/l10n test/theme test/support
grep -rn "LibraryThemeDependencies\|LibraryLocaleDependencies\|themeDependencies\|localeDependencies" lib test integration_test
```

Expected：analyze 乾淨；全過；grep 無輸出。通過數算式寫入附錄 C。

- [ ] **Step 5: 守衛腳本與提交**

```bash
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
git add lib test integration_test
git commit -m "refactor(epic-54): Issue 13 外觀（主題、E-Ink、介面語言）改收 AppearanceDependencies 並移除舊 bundle" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：`AppDependencies` 與 `main.dart` 收尾

**Files:**
- Create: `app/lib/screens/app_dependencies.dart`
- Create: `app/test/support/fake_app_dependencies.dart`、`fake_app_dependencies_test.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/elinkbook_app_locale_test.dart`、`app/test/theme/theme_test.dart`

**Interfaces:**
- Consumes：Task 2／3 的 `ElinkBookApp(readerFeatures:, sync:, sources:)`。
- Produces：

```dart
class AppDependencies {
  final ReaderFeatureDependencies readerFeatures;
  final SyncDependencies sync;
  final SourceDependencies sources;
  const AppDependencies({required this.readerFeatures, required this.sync, required this.sources});
}
// ElinkBookApp({super.key, required AppDependencies dependencies, GlobalKey<NavigatorState>? navigatorKey,
//   AppTheme initialTheme = AppTheme.light, bool initialEinkMode = false, AppLocale? initialLocaleOverride,
//   AppLocalePreferences? localePreferences, AppThemePreferences? themePreferences})
// ——移除 readerFeatures／sync／sources 三個欄位，公開欄位 `dependencies`。
AppDependencies fakeAppDependencies({
  ReaderFeatureDependencies? readerFeatures,
  SyncDependencies? sync,
  SourceDependencies? sources,
});
```

`fakeAppDependencies` 預設優先借用傳入端的 `syncCheckpointTrigger`（ADR 0037 §1 同一實例約束）：
```dart
final trigger = readerFeatures?.syncCheckpointTrigger ??
    sync?.syncCheckpointTrigger ??
    fakeSyncDependencies().syncCheckpointTrigger;
final rf = readerFeatures ?? fakeReaderFeatureDependencies(syncCheckpointTrigger: trigger);
final s = sync ?? fakeSyncDependencies(syncCheckpointTrigger: trigger);
```
若呼叫端只傳入 `readerFeatures`（自訂 trigger），未傳入的 `sync` 會自動借用該 trigger；反之亦然；若皆未傳入則新建一個共用；若兩者皆傳入則完全尊重呼叫端。

- [ ] **Step 1: 寫失敗測試**

`test/support/fake_app_dependencies_test.dart`（另需補「只傳 `readerFeatures`」「只傳 `sync`」兩案，見 Interfaces 的推導規則）：

```dart
test('fakeAppDependencies 預設的兩組共用同一個 syncCheckpointTrigger（ADR 0037 §1）', () {
  final deps = fakeAppDependencies();
  expect(deps.readerFeatures.syncCheckpointTrigger, same(deps.sync.syncCheckpointTrigger));
});

test('fakeAppDependencies 具名覆寫原樣帶入', () {
  final sources = fakeSourceDependencies();
  expect(fakeAppDependencies(sources: sources).sources, same(sources));
});

test('fakeAppDependencies 單邊傳入 readerFeatures 時，未傳入的 sync 自動共用其 syncCheckpointTrigger', () {
  final trigger = fakeSyncDependencies().syncCheckpointTrigger;
  final rf = fakeReaderFeatureDependencies(syncCheckpointTrigger: trigger);
  final deps = fakeAppDependencies(readerFeatures: rf);
  expect(deps.sync.syncCheckpointTrigger, same(trigger));
});

test('fakeAppDependencies 單邊傳入 sync 時，未傳入的 readerFeatures 自動共用其 syncCheckpointTrigger', () {
  final trigger = fakeSyncDependencies().syncCheckpointTrigger;
  final s = fakeSyncDependencies(syncCheckpointTrigger: trigger);
  final deps = fakeAppDependencies(sync: s);
  expect(deps.readerFeatures.syncCheckpointTrigger, same(trigger));
});
```

   `elinkbook_app_wiring_test.dart` 新增（取代 Task 2／3 暫用的三組分開傳入）：

```dart
testWidgets('ElinkBookApp 把 AppDependencies 的三組原樣傳到書架、來源頁與設定頁', (tester) async {
  final deps = fakeAppDependencies();
  await tester.pumpWidget(ElinkBookApp(dependencies: deps));
  await tester.pumpAndSettle();
  final shell = tester.widget<AdaptiveShellScaffold>(find.byType(AdaptiveShellScaffold));
  expect(shell.readerFeatures, same(deps.readerFeatures));
  expect(shell.sync, same(deps.sync));
  expect(shell.sources, same(deps.sources));
  expect(tester.widget<LibraryScreen>(find.byType(LibraryScreen)).dependencies, same(deps.readerFeatures));
  expect(tester.widget<LibraryScreen>(find.byType(LibraryScreen)).sources, same(deps.sources));
  expect(tester.widget<SourcesHomeScreen>(find.byType(SourcesHomeScreen, skipOffstage: false)).sources, same(deps.sources));
  expect(tester.widget<SettingsScaffold>(find.byType(SettingsScaffold, skipOffstage: false)).sources, same(deps.sources));
  expect(deps.readerFeatures.syncCheckpointTrigger, same(deps.sync.syncCheckpointTrigger));
});
```

   Task 3 的外觀切換測試改用 `fakeAppDependencies()`。其餘 `ElinkBookApp(` 呼叫（`app_lifecycle_sync` 4、`elinkbook_app_locale` 8、`theme_test` 3、wiring 其餘）改為 `ElinkBookApp(dependencies: fakeAppDependencies(…))`；需要自訂同步組者（`app_lifecycle_sync_test` 驗證 `paused` 觸發 checkpoint）傳 `fakeAppDependencies(sync: …, readerFeatures: …)` 並保留原斷言強度。

- [ ] **Step 2: 跑測試確認失敗**

Run：`flutter test test/support/fake_app_dependencies_test.dart`
Expected：編譯失敗。

- [ ] **Step 3: 實作**

`lib/screens/app_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import 'reader_feature_dependencies.dart';
import 'source_dependencies.dart';
import 'sync_dependencies.dart';

/// 應用層依賴容器（ADR 0037 §1）：持有 `main()` 建構一次的三組靜態依賴，**只在 `main.dart`
/// 與 `ElinkBookApp` 使用**，不往畫面傳整包——畫面各自接收所需的那一組。
///
/// 外觀（主題、E-Ink、介面語言）不在這裡：它是含可變狀態的快照，由 `_ElinkBookAppState`
/// 每次 `build()` 現組成 `AppearanceDependencies`。`syncCheckpointTrigger` 同時屬於
/// `readerFeatures` 與 `sync`，由 `main()` 建構一次、同一實例放進兩組。
@immutable
class AppDependencies {
  final ReaderFeatureDependencies readerFeatures;
  final SyncDependencies sync;
  final SourceDependencies sources;

  const AppDependencies({
    required this.readerFeatures,
    required this.sync,
    required this.sources,
  });
}
```

`test/support/fake_app_dependencies.dart` 依 Interfaces 的優先借用規則實作（`trigger = readerFeatures?.syncCheckpointTrigger ?? sync?.syncCheckpointTrigger ?? fakeSyncDependencies().syncCheckpointTrigger`，傳給未提供的那一邊）。

`main.dart`：`ElinkBookApp` 改為 `required AppDependencies dependencies`，`build()` 內以 `widget.dependencies.readerFeatures`／`.sync`／`.sources` 傳給 `AdaptiveShellScaffold`，`didChangeAppLifecycleState` 改 `widget.dependencies.sync.syncCheckpointTrigger.trigger()`；`main()` 在建完三組後 `final appDependencies = AppDependencies(readerFeatures: readerFeatures, sync: sync, sources: sources);` 並 `runApp(ElinkBookApp(dependencies: appDependencies, navigatorKey: navigatorKey, initialTheme: initialTheme, initialEinkMode: initialEinkMode, themePreferences: themePreferences, localePreferences: localePreferences, initialLocaleOverride: initialLocaleOverride))`。`ElinkBookApp` 的文件註解更新為「Issue 13 起收 `AppDependencies`」。

- [ ] **Step 4: 跑測試確認通過**

```bash
flutter analyze
flutter test test/support test/elinkbook_app_wiring_test.dart test/app_lifecycle_sync_test.dart \
  test/navigation_test.dart test/l10n test/theme test/screens/adaptive_shell_scaffold_test.dart
```

Expected：全過；analyze 乾淨。算式寫入附錄 C。

- [ ] **Step 5: Commit**

```bash
node tool/check_l10n_hardcoded_strings.js
git add lib/screens/app_dependencies.dart lib/main.dart test
git commit -m "refactor(epic-54): Issue 13 新增 AppDependencies 容器，ElinkBookApp 改收單一容器" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：孤兒 ARB 鍵清理、完整驗證、ADR 與文件同步

**Files:**
- Modify: `app/lib/l10n/app_{zh_TW,zh_CN,zh,en}.arb` 與產生檔 `app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`
- Modify: `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、本計畫檔

- [ ] **Step 1: 確認孤兒鍵並清理**

在 `app/` 目錄或專案根目錄確認孤兒鍵使用端（PowerShell）：
```powershell
@("readerSaveAsPresetUnavailableMessage", "sourcesHomeCloudNotLinkedSubtitle", "sourcesHomeRemoteLibraryNotConfiguredSubtitle") | ForEach-Object {
  Write-Host "== $_"
  git grep -n $_ -- app/lib app/test app/integration_test | Select-String -NotMatch "app_localizations"
}
```
或使用跨平台單行 `git grep`（專案根目錄）：
```bash
git grep -n -E "readerSaveAsPresetUnavailableMessage|sourcesHomeCloudNotLinkedSubtitle|sourcesHomeRemoteLibraryNotConfiguredSubtitle" -- app/lib app/test app/integration_test
```

Expected：三個鍵在 `lib/`（排除產生檔）、`test/`、`integration_test/` 都沒有使用端。任一鍵仍有使用端則保留該鍵並在 `epic.md` 註明原因。無使用端者，從四份 ARB 刪除（含 `@鍵` 描述區塊），然後在 `app/` 目錄執行：

```bash
flutter gen-l10n
node tool/check_l10n_hardcoded_strings.js
flutter test test/l10n
```

Expected：產生檔同步更新；ARB 鍵一致性守衛（Issue 6）與 l10n 測試通過。`git status` 只應看到上述 7 個檔案變動。

- [ ] **Step 2: 完整 `flutter test`（只此一次，背景執行）**

在 `app/` 下以 `run_in_background` 執行 `flutter test`。Expected：除 Issue 18／19 已記錄的既存失敗（`pdf_reader_view_filters_test` 加粗 debouncer，乾淨 `main` 同樣失敗）外全過；出現其他失敗逐一判定是否本 Issue 回歸。

- [ ] **Step 3: integration 靜態確認與真機（需使用者在場）**

`integration_test/library_screen_test.dart`、`smoke_test.dart` 本計畫只做機械遷移。向使用者確認後在 `TCL 14`（序號 `3CEF42ECD491687`）執行：

PowerShell（Windows）：
```powershell
$env:MSYS_NO_PATHCONV="1"
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
flutter test integration_test/smoke_test.dart -d 3CEF42ECD491687
flutter test integration_test/wifi_transfer_screen_test.dart -d 3CEF42ECD491687
```

Bash：
```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
flutter test integration_test/smoke_test.dart -d 3CEF42ECD491687
flutter test integration_test/wifi_transfer_screen_test.dart -d 3CEF42ECD491687
```

結果只宣稱此裝置。Issue 12 在同一裝置上這兩檔皆通過；本次以「通過」或「與 Issue 12 結果不同（說明差異）」如實記錄。無法在場則在 `epic.md` 明寫「真機未驗」。
另請使用者在真機手動確認一次（本 Issue 的核心使用者可見風險）：從「來源」頁開 Google Drive、OneDrive、遠端書庫、WiFi 傳書各一次可進入；切換主題、E-Ink、介面語言後書架／來源／設定三頁外觀一致。

- [ ] **Step 4: 同步 ADR 0037 措辭**

- §1：`SourceDependencies` 欄位列表改為與實作一致（12 欄位；`WifiTransferDependencies` 已併入，書庫與匯入服務取自閱讀器組，指紋函式與網路偵測取自來源組）；「容器 `AppDependencies` 持有四組」改為「`AppDependencies` 持有 `readerFeatures`／`sync`／`sources` 三組靜態依賴；`AppearanceDependencies` 因含可變狀態，由 `ElinkBookApp` 的 State 每次 `build()` 組成快照」（依 Task 0 Q1 的實際決定；若使用者選 B 則照 B 寫）。**§1 關於「`syncCheckpointTrigger` 同時放入閱讀器組與同步組、由 `main()`／`AppDependencies` 建構一次」的敘述必須逐字保持語意，不得因本次改寫而位移**（Issue 12 計畫審查 M-3 的教訓）。
- §3：「WiFi 傳書於 Issue 13 處理」改為已處理的結論（依 Q2：不留開關，恆提供）。
- §6：補一句 4 個 epic-26 舊 bundle 與 `WifiTransferDependencies` 已於 Issue 13 全部移除。
- 「後果」的測試改動量數字不改（那是撰寫 ADR 當時的估計）。

- [ ] **Step 5: 回寫文件（隨功能分支一起 commit）**

- `epic.md`：新增「Issue 13 實作完成」段（內容、驗證數字、附錄 B 摘要、真機結果或「未驗」、使用者決定的原話出處、**與 `issues.md` 第 13 列的兩處落差**〔舊 bundle 剩 4 個而非 6 個、`buildReaderScreen` 已無暫時組裝〕、孤兒 ARB 鍵清理結果）。
- 本計畫：勾選全部 Step，附錄 A（使用者原話）、附錄 B（被刪測試清單）、附錄 C（測試數算式）填完。
- **不要**在功能分支上改 `issues.md` 第 13 列與 `docs/epics.md`：這兩處在 PR 合併後於 `main` 直接 commit＋push（`⚪ 待規劃` → `🟢 已合併（PR #N）`，備註只寫「Issue 13 已合併」）；合併後順便把第 13 列標題的「6 個舊 bundle」「`buildReaderScreen` 的暫時組裝」更正為事實。同時移除 `issues.md` 第 28 行「待清理（Issue 11 程式審查 M-5）」那段（已完成）。

- [ ] **Step 6: 請求程式審查**

```bash
git log --oneline main..HEAD
flutter analyze
```

審查者先產出報告（`reviews/review-code-issue-13.md`，gitignore），不得直接改程式；處理審查意見後才發 PR（Gitea：`tea pr create -l jigong -r huthief/elinkBook`，由使用者合併）。

---

## 附錄 A：使用者決定紀錄（Task 0 Step 2 取得後填入原話）

- Task 0 Step 2（Q1～Q3 設計決定）：使用者於 2026-10-08 對話回答原話：`Q1~Q3依據建議`。對應：Q1＝A（`AppDependencies` 只持有 `readerFeatures`／`sync`／`sources` 三組靜態依賴；`AppearanceDependencies` 為每次 `build()` 現組的快照，ADR 0037 §1 需改一句話）；Q2＝A（不留 WiFi 傳書開關，`WifiTransferDependencies` 刪除，tile 恆顯示，`checkNetworkAvailability` 併入 `SourceDependencies`）；Q3＝A（外觀組不加 `==`／`hashCode`）。執行時 Task 0 Step 2 不需再詢問，直接進 Step 3。

## 附錄 B：被刪除的測試清單（依「依賴 non-null，缺席型別上不可達」原則）

依「依賴 non-null，缺席型別上不可達」原則刪除，無其他理由。預期類別（實際案例名稱與數量由執行者依實測填入）：

| 測試檔 | 預期被刪類別 | 理由／對應的新恆真行為 |
|---|---|---|
| `sources_home_screen_test.dart` | 雲端／OPDS 依賴缺席時 tile 停用、`wifiTransferDependencies` 為 null 或任一欄位為 null 時不顯示 WiFi 入口 | Google Drive／OneDrive／遠端書庫 tile 恆啟用、WiFi 傳書 tile 恆顯示、下載佇列面板恆顯示 |
| `library_screen_test.dart` | `remoteServerRepository`／`createOpdsClient` 缺席時重新下載顯示「遠端功能未啟用」 | 兩者 non-null；**書本缺 `remoteDownloadUrl` 的同一提示路徑保留並有測試** |
| `settings_scaffold*_test.dart` | 雲端帳號入口在三個欄位任一為 null 時停用；主題／E-Ink／語言 callback 為 null 時控制項停用 | 雲端帳號入口恆可點；三個 callback non-null |
| `library_screen_dependencies_test.dart` | 整檔（Cloud 2 案、Remote 2 案、Theme 2 案、Locale 2 案，以實測為準） | 被測的 4 個 bundle 已刪除；欄位持有關係改由 `fake_*_dependencies_test` 與 wiring 測試覆蓋 |

## 附錄 C：測試數基準與算式

- Task 0 基準：（待填）
- Task 1：（待填）
- Task 2：（待填：`基準 − 被刪 ＋ 新增`）
- Task 3：（待填）
- Task 4：（待填）
- Task 5 完整 `flutter test`：見 `epic.md`「Issue 13 實作完成」。

## Self-Review 結果

- **Spec 涵蓋**：`issues.md` 第 13 列——「`SourceDependencies`（雲端帳號與 OAuth／storage client、`remoteServerRepository`、OPDS、`thumbnailCache`、`computeFingerprint`、網路檢查、`downloadQueueController`、`WifiTransferDependencies` 欄位）」→ Task 1／2；「WiFi 傳書開關由 null 檢查改為明確表示」→ Task 0 Q2＋Task 2（建議為不留開關，並要求使用者決定）；「`AppearanceDependencies`（主題、E-Ink、`currentLocaleOverride`／`onLocaleChanged`）」→ Task 1／3；「`AppDependencies` 與 `main.dart` 收尾」→ Task 4；「移除舊 bundle（含 `LibraryLocaleDependencies`）」→ Task 2／3（現存 4 個，見「已查證的事實」）；「移除 `buildReaderScreen` 的暫時組裝」→ Issue 12 已完成，本計畫只記錄落差；「依賴 Issue 12」→ 已合併（PR #335）；Issue 11 程式審查 M-5（孤兒 ARB 鍵）→ Task 5。ADR 0037 §1／§3／§6 → Task 5 Step 4。
- **佔位掃描**：附錄 A／B／C 刻意留白由執行者依實測填入；Task 3 的外觀切換測試已內聯主題切換步驟（點 `settings_theme_dot_dark`，與 `theme_test.dart:143` 一致）；E-Ink（`settings_eink_mode_switch`）與語言（`settings_language_button`＋`settings_language_option_en`）的點擊步驟，開工時對照 `elinkbook_app_locale_test.dart` 既有手法內聯寫出，不得留空；`main()` 的實參一律「逐字沿用現行 `ElinkBookApp(...)`」，原因是取值已逐字存在於 `main.dart:275-369`，重抄只會製造不一致。
- **型別一致**：`SourceDependencies` 12 欄位、`AppearanceDependencies` 6 欄位、`AppDependencies` 3 欄位、三個工廠名稱，與公開欄位名 `sources`／`appearance`／`dependencies`／`readerFeatures`／`sync` 在 Task 1～4 一致；各畫面依角色命名（`LibraryScreen.dependencies` 是閱讀器組，沿 Issue 12 不改名）已在 Interfaces 逐一列出。
- **Review Focus**：5 項皆對應到具體測試（Task 2 的 `same(...)` 欄位對帳、Task 3 的外觀快照與 E-Ink 三處一致、Task 2 的重新下載提示保留、附錄 B 逐項記錄）。
- **風險**：Task 2 與 Task 3 各是一次外殼樹原子切換（不可再拆，理由同 Issue 12 計畫審查 I-1）；兩段分開是為了讓每次 codemod 與審查範圍可控，代價是 `LibraryScreen(`／`SettingsScaffold(`／`AdaptiveShellScaffold(` 的測試呼叫端被碰兩次（插入一行，機械且穩健）。Task 2 把兩個副標 ARB 鍵變成孤兒，已併入 Task 5 清理而非留尾巴。最大的不確定點是 Task 0 Q1（ADR 原文寫「四組」），已列為使用者決定而非自行改寫 ADR。
