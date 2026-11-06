# Issue 9：WebView2 未安裝時顯示說明與下載連結 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows 啟動時偵測 WebView2 Runtime；沒裝或損壞就顯示說明畫面（含下載連結與「重新檢查」），裝好後不必重開 App 就能進入。

**Architecture:** `main()` 在 `runApp` 之前先呼叫 `checkAndInitWebView2()`（純邏輯，探測與建立環境皆由參數注入）。結果不是 ready 時，`runApp` 一個獨立的 `WebView2MissingApp`（自帶 `MaterialApp`，不依賴 `AppDependencies`），「重新檢查」成功後呼叫 `onReady` 改為 `runApp(ElinkBookApp(...))`。只在 Windows 執行，Android 與其他平台零改動。

**Tech Stack:** Flutter 3.41.9、`flutter_inappwebview` 6.1.5（`WebViewEnvironment.getAvailableVersion()`）、新增直接相依 `url_launcher`（目前只是間接相依，鎖定 6.3.2）。

**Spec:** `docs/epics/epic-66-windows-port/epic.md` 決策 4（「WebView2 沒裝時顯示說明與下載連結，不打包執行環境」）與決策 27；`issues.md` Issue 9 列。設計取捨 2026-11-06：Q1 整個 App 擋住只顯示說明畫面、Q2 新增 `url_launcher` 直接開瀏覽器、Q3 要有「重新檢查」。

## Global Constraints

- Flutter 3.41.9，`flutter analyze` 乾淨；不得使用此版本沒有的 API。
- 只在 Windows 生效：檢查與說明畫面的入口一律以 `isWindowsPlatform` 判斷（`lib/platform/platform_support.dart`），不用 `dart:io` 的 `Platform`。
- 四個 arb（`app_zh_TW`、`app_zh`、`app_zh_CN`、`app_en`）都要有新字串，`flutter gen-l10n` 成功；`app_zh` 與 `app_zh_TW` 逐字相同（`arb_consistency_test`）；提交前跑 `node tool/check_l10n_hardcoded_strings.js` 與 `flutter test test/l10n --no-pub`。品牌名稱一律寫 `elinkBook`。
- 下載連結固定為 `https://developer.microsoft.com/microsoft-edge/webview2/`（微軟官方頁面）；不打包 Runtime，不自動下載安裝。
- 說明畫面的語系與 App 一致：`localePreferences` 的覆寫優先，否則跟隨系統（沿用 `resolveMaterialAppLocale`）。
- 不改 `pubspec.lock` 中與 `url_launcher` 無關的行（本機 `pub get` 會降級 `intl`、`meta`、`matcher` 等，是 Issue 6 的既有落差，不得 commit）；`git add` 一律明確列檔。
- Windows 建置需設環境變數 `CL=/utf-8`（繁中字碼頁 950，見 `epic.md` 決策 27），在 PowerShell 設定，Git Bash 會把 `/utf-8` 轉成路徑。

## Review Focus

1. 探測回傳空字串（不是 `null`）：視為沒裝，不能誤判為 ready。
2. 探測成功但 `createEnvironment` 丟例外（安裝損壞）：進說明畫面並顯示錯誤摘要，不可讓 App 閃退。
3. `createEnvironment` 一直不回來：60 秒逾時後進說明畫面（審查後由 15 秒調長），不可永遠停在黑畫面。
4. 連按兩次「重新檢查」：同一時間只跑一次檢查，成功後只呼叫一次 `onReady`（不可 `runApp` 兩次）。
5. 開瀏覽器失敗（`openUrl` 回傳 `false` 或丟例外）：畫面上仍看得到可選取複製的網址，不崩潰。

---

### Task 1：量測缺少 Runtime 時外掛的真實行為（不產出正式程式）

**目的：** 外掛在 Runtime 缺少時的行為沒有實測過。本 Task 決定 Task 2 的失敗分支（丟例外、回 `null`、還是卡住）。

**Files:**
- Create: `app/integration_test/windows_webview2/runtime_probe_test.dart`
- Create: `docs/epics/epic-66-windows-port/issue-9-report.md`（先寫「量測結果」一節）

**Interfaces:**
- Produces: 對 `WebViewEnvironment.getAvailableVersion(browserExecutableFolder: …)` 與 `WebViewEnvironment.create(settings: WebViewEnvironmentSettings(browserExecutableFolder: …))` 在「指向空資料夾」時行為的結論，供 Task 2 引用。

- [x] **Step 1: 寫測試。** 建一個空的暫存資料夾當 `browserExecutableFolder`（這是不移除本機 Runtime 就能模擬「沒裝」的方法）。三個測試，名稱與斷言如下：
  - `空資料夾：getAvailableVersion 回傳 null`，斷言 `expect(version, isNull)`。
  - `沒有 browserExecutableFolder：getAvailableVersion 回傳非空版本字串`（本機有裝），斷言 `isNotNull` 且 `isNotEmpty`。
  - `空資料夾：create 的行為`：用 `.timeout(const Duration(seconds: 20))` 包住，把「丟出的例外型別與訊息」或「逾時」用 `print('[probe] …')` 印出；此測試不做通過／失敗斷言（只記錄行為），測試名稱註明「記錄用」。
- [x] **Step 2: 在 Windows 執行。**
  Run（PowerShell）：`$env:CL="/utf-8"; flutter test integration_test/windows_webview2/runtime_probe_test.dart -d windows`
  Expected: 前兩個測試通過；第三個印出 `[probe]` 行。若 App 程序在第三個測試消失（類似 Issue 8），把「create 會殺掉程序」記為結論，Task 2 改為**只靠 `getAvailableVersion` 判斷、不在偵測失敗時呼叫 `create`**。
- [x] **Step 3: 把量測結果（含輸出）寫進 `issue-9-report.md` 的「量測結果」一節**，並註明沒測到的部分（例如 Runtime 損壞但資料夾存在的情況）。
- [x] **Step 4: Commit。**

```bash
git add app/integration_test/windows_webview2/runtime_probe_test.dart docs/epics/epic-66-windows-port/issue-9-report.md
git commit -m "test(windows): 量測 WebView2 Runtime 缺少時的外掛行為（epic-66 Issue 9 Task 1）"
```

---

### Task 2：啟動檢查純邏輯 `checkAndInitWebView2`

**Files:**
- Create: `app/lib/windows/webview2_runtime_check.dart`
- Test: `app/test/windows/webview2_runtime_check_test.dart`

**Interfaces:**
- Consumes: Task 1 的結論（決定是否在偵測失敗後仍呼叫 `createEnvironment`；以下以「會丟例外或逾時」為預設）。
- Produces:
  - `const String kWebView2DownloadUrl = 'https://developer.microsoft.com/microsoft-edge/webview2/';`
  - `enum WebView2CheckStatus { ready, missing, failed }`
  - `class WebView2CheckResult { const WebView2CheckResult.ready(String version); const WebView2CheckResult.missing(); const WebView2CheckResult.failed(String detail); final WebView2CheckStatus status; final String? version; final String? detail; bool get isReady; }`
  - `typedef WebView2VersionProbe = Future<String?> Function();`
  - `typedef WebView2EnvironmentCreator = Future<void> Function();`
  - `Future<WebView2CheckResult> checkAndInitWebView2({required WebView2VersionProbe probe, required WebView2EnvironmentCreator createEnvironment, Duration createTimeout = const Duration(seconds: 15)})`

- [x] **Step 1: 寫失敗測試**（`test/windows/webview2_runtime_check_test.dart`），每個案例一個 test，`probe`／`createEnvironment` 用假函式：
  - `探測回 "130.0.1" 且建立成功 → ready，version 為 "130.0.1"，createEnvironment 被呼叫 1 次`
  - `探測回 null → missing，createEnvironment 從未被呼叫`
  - `探測回空字串 "" → missing`（Review Focus 1）
  - `探測回 "   "（只有空白）→ missing`
  - `探測丟例外 → failed，detail 含例外訊息，不向外丟`
  - `探測成功但 createEnvironment 丟 StateError("boom") → failed，detail 含 "boom"`（Review Focus 2）
  - `createEnvironment 回傳永遠不完成的 Future，createTimeout 設 50ms → failed，detail 提到逾時`（Review Focus 3，用真實的短 timeout，不用 fake async）
- [x] **Step 2: 執行確認失敗。**
  Run: `flutter test test/windows/webview2_runtime_check_test.dart --no-pub`
  Expected: 編譯失敗（符號未定義）。
- [x] **Step 3: 實作 `webview2_runtime_check.dart`。** 空字串與只有空白一律視為 `missing`；探測與建立的例外都轉成 `failed`，`detail` 用 `e.toString()`；逾時用 `Future.timeout`，`detail` 文字註明「建立 WebView2 環境逾時」。不 import `flutter_inappwebview`（保持純 Dart，可在 `flutter test` 直接跑）。
- [x] **Step 4: 執行確認通過。**
  Run: `flutter test test/windows/webview2_runtime_check_test.dart --no-pub`
  Expected: 全部通過。
- [x] **Step 5: Commit。**

```bash
git add app/lib/windows/webview2_runtime_check.dart app/test/windows/webview2_runtime_check_test.dart
git commit -m "feat(windows): WebView2 Runtime 啟動檢查純邏輯（epic-66 Issue 9 Task 2）"
```

---

### Task 3：說明畫面 `WebView2MissingApp` 與字串

**Files:**
- Modify: `app/pubspec.yaml`（新增 `url_launcher: ^6.3.2` 直接相依）、`app/pubspec.lock`（只把 `url_launcher` 條目的 `dependency: transitive` 改為 `direct main`）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Create: `app/lib/windows/webview2_missing_screen.dart`
- Test: `app/test/windows/webview2_missing_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `WebView2CheckResult`、`WebView2CheckStatus`、`kWebView2DownloadUrl`。
- Produces:
  - `class WebView2MissingApp extends StatefulWidget`，建構子 `const WebView2MissingApp({super.key, required WebView2CheckResult initialResult, required Future<WebView2CheckResult> Function() recheck, required VoidCallback onReady, Future<bool> Function(Uri url)? openUrl, Locale? localeOverride})`。`openUrl` 預設用 `url_launcher` 的 `launchUrl(url, mode: LaunchMode.externalApplication)`。
  - 固定 Key：`Key('webview2_missing_title')`、`Key('webview2_download_button')`、`Key('webview2_recheck_button')`、`Key('webview2_url_text')`、`Key('webview2_detail_text')`（只有 `failed` 或重新檢查後仍失敗時才出現）、`Key('webview2_still_missing_text')`（重新檢查後仍未就緒時出現）。
  - arb 鍵：`webview2MissingTitle`、`webview2MissingBody`、`webview2FailedBody`、`webview2DownloadButton`、`webview2RecheckButton`、`webview2StillMissing`、`webview2DetailLabel`。

**字串（`app_zh_TW` 為語意基準，每個鍵都要附 `@<key>` 的 `description`，比照既有 arb；`app_zh` 必須與 `app_zh_TW` 逐字相同，`test/l10n/arb_consistency_test.dart` 的 zh 鏡像守衛會檢查；只有 `app_zh_CN` 轉為簡體並沿用該檔既有的用詞慣例；`app_en` 對應英文）：**

| 鍵 | zh_TW |
|---|---|
| `webview2MissingTitle` | 需要安裝 Microsoft Edge WebView2 |
| `webview2MissingBody` | elinkBook 需要 WebView2 執行階段才能顯示書籍。請下載並安裝，完成後按「重新檢查」。 |
| `webview2FailedBody` | 偵測到 WebView2，但無法啟動。請重新安裝後按「重新檢查」。 |
| `webview2DownloadButton` | 下載 WebView2 |
| `webview2RecheckButton` | 重新檢查 |
| `webview2StillMissing` | 仍然偵測不到可用的 WebView2。 |
| `webview2DetailLabel` | 錯誤摘要 |

- [x] **Step 1: 手動加入直接相依。** 在 `pubspec.yaml` 的 `dependencies` 加 `url_launcher: ^6.3.2`；`pubspec.lock` 只改 `url_launcher` 條目的 `dependency` 欄位。執行 `flutter pub get --dry-run`，確認沒有新增或升級其他套件；**不要**執行會改動其他鎖定版本的 `flutter pub get` 後把結果 commit。
- [x] **Step 2: 加入 7 個 arb 字串（四個檔案）**，再執行 `flutter gen-l10n`，確認成功。
- [x] **Step 3: 寫失敗測試**（widget test，`MaterialApp` 之外由 `WebView2MissingApp` 自帶，測試用 `tester.pumpWidget(WebView2MissingApp(...))`）。案例：
  - `missing：顯示標題、下載按鈕、重新檢查按鈕、網址文字，不顯示錯誤摘要`
  - `failed：額外顯示 Key webview2_detail_text，內容含 detail`
  - `點下載按鈕：openUrl 以 kWebView2DownloadUrl 被呼叫 1 次`
  - `openUrl 回傳 false：網址文字仍在畫面上，無例外`（Review Focus 5）
  - `openUrl 丟例外：同上，無未處理例外`（Review Focus 5）
  - `重新檢查回傳 ready：onReady 被呼叫 1 次`
  - `重新檢查回傳 missing：onReady 未呼叫，出現 webview2_still_missing_text`
  - `重新檢查進行中連按兩次：recheck 只被呼叫 1 次，成功後 onReady 只呼叫 1 次`（Review Focus 4；用 `Completer` 控制 recheck 何時完成；進行中按鈕顯示為停用）
  - `recheck 成功並呼叫 onReady 之後，按鈕仍為停用，再按也不會呼叫第二次 onReady`（`runApp` 換根要到下一幀才完成）
  - `recheck 丟例外：顯示失敗狀態與錯誤摘要，按鈕恢復可按`（防止按鈕永久停用）
  - `localeOverride 為 en：標題為英文；為 zh_TW：標題為「需要安裝 Microsoft Edge WebView2」`
- [x] **Step 4: 執行確認失敗。**
  Run: `flutter test test/windows/webview2_missing_screen_test.dart --no-pub`
  Expected: 編譯失敗。
- [x] **Step 5: 實作 `webview2_missing_screen.dart`。** 自帶 `MaterialApp`（`localizationsDelegates`、`supportedLocales`、`locale: widget.localeOverride`、`localeListResolutionCallback` 與 `main.dart` 的 `MaterialApp` 相同寫法）；固定淺色主題即可（此時尚未載入使用者主題，不為此新增主題讀取）。根層用 `Scaffold(body: Center(child: SingleChildScrollView(child: Padding(...))))`，視窗縮小或高 DPI 縮放時不會 overflow。網址用 `SelectableText`。重新檢查用 `_checking` 旗標防重入，檢查期間按鈕停用；規則：結果為 ready 時呼叫 `onReady` 後**不重設** `_checking`（等 `runApp` 換根）；結果不是 ready 或 `recheck` 丟例外時才重設 `_checking = false`，並更新畫面上的結果（例外轉成 `WebView2CheckResult.failed(e.toString())`）；非同步回來後先確認 `mounted`。
- [x] **Step 6: 執行確認通過，並跑 l10n 檢查。**
  Run: `flutter test test/windows/webview2_missing_screen_test.dart --no-pub` 與 `node tool/check_l10n_hardcoded_strings.js`
  Expected: 全部通過；l10n 檢查 PASS。
- [x] **Step 7: Commit。**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/l10n app/lib/windows/webview2_missing_screen.dart app/test/windows/webview2_missing_screen_test.dart
git commit -m "feat(windows): WebView2 缺少時的說明畫面與下載連結（epic-66 Issue 9 Task 3）"
```

提交前用 `git diff app/pubspec.lock` 確認只有 `url_launcher` 一處異動。`app/lib/l10n` 內的 `app_localizations*.dart` 是否為產生檔且進版控，依既有狀態處理（`git status` 看到就一併加入）。

---

### Task 4：接進 `main()`、人工驗證與文件

**Files:**
- Modify: `app/lib/main.dart`（約 465～475 行，`isWindowsPlatform` 區塊）
- Modify: `docs/epics/epic-66-windows-port/issues.md`（新增「Issue 9 範圍」「Issue 9 過關條件」「Issue 9 單元測試要求」三節，內容取自本計畫；Issue 9 列狀態改為「實作完成，待 PR」）、`issue-9-report.md`
- Modify: `docs/epics/epic-66-windows-port/epic.md`（決策 4 補一句「已於 Issue 9 實作」）

**Interfaces:**
- Consumes: Task 2 的 `checkAndInitWebView2`、`WebView2CheckResult`；Task 3 的 `WebView2MissingApp`。
- Produces: 啟動流程：Windows 上檢查未通過 → `runApp(WebView2MissingApp(...))` 並結束 `main()`；通過或非 Windows → 與現況相同。

- [x] **Step 1: 確認 `runApp` 之前沒有任何程式碼使用 WebView。** 在 `main()` 內搜尋 `HeadlessInAppWebView`、`InAppWebView`、`appWebViewEnvironment`、`extractWindowsBookMetadata` 的呼叫點，確認都在 `runApp` 之後才會執行（`extractWindowsBookMetadata` 只是被傳遞的函式）。有例外就停下來回報，不要自行搬動。
- [x] **Step 2: 改 `main()`。** 把 `runApp(ElinkBookApp(...))` 包成區域函式 `startApp()`；Windows 區塊在 `windowManager` 初始化之後，先取一次 `final appSupportDir = await getApplicationSupportDirectory();`（每次重新檢查不重查目錄），宣告區域函式 `Future<WebView2CheckResult> runCheck() => checkAndInitWebView2(probe: () => WebViewEnvironment.getAvailableVersion(), createEnvironment: () => initAppWebViewEnvironment(userDataFolder: appSupportDir.path));`，取代單獨呼叫 `initAppWebViewEnvironment`；`final initialResult = await runCheck();` 不是 ready 時 `runApp(WebView2MissingApp(initialResult: initialResult, recheck: runCheck, onReady: startApp, localeOverride: initialLocaleOverride?.locale))` 並 `return`。`startApp` 必須在這個區塊之前宣告。
- [x] **Step 3: 執行相關測試與靜態分析。**
  Run: `flutter test test/windows test/l10n --no-pub` 與 `flutter analyze --no-pub`
  Expected: 通過；`No issues found!`。
- [x] **Step 4: 人工驗證（Windows 實機，PowerShell，`$env:CL="/utf-8"`）。** 本機有裝 Runtime，無法直接看到缺少畫面，用**不 commit** 的暫時改動模擬：把 `probe` 暫時改成 `() async => null`，`flutter run -d windows`：
  1. 看到說明畫面（標題、下載按鈕、重新檢查、網址）。
  2. 按「下載 WebView2」，預設瀏覽器開啟微軟頁面。
  3. 按「重新檢查」：仍顯示「仍然偵測不到…」。
  4. 把 `probe` 暫時改成第 N 次呼叫才回傳真實版本（或熱重啟前改回），按「重新檢查」後直接進入書架，不必重開 App。
  5. 切換系統或 App 語言為英文，說明畫面為英文。
  6. 還原暫時改動（`git checkout -- app/lib/main.dart` 之後重做 Step 2 的正式改動，或確認 `git diff` 只剩正式內容），正常啟動確認 App 與原本一致。
  只記錄實際做過的項目，沒做的寫「未驗證」。
- [x] **Step 5: 補文件。** `issue-9-report.md` 寫量測結果、實作摘要、人工驗證表（只填真的測過的）、未驗證項目（包含：沒有在真正沒裝 Runtime 的機器上測過）。`issues.md` 加三節；`epic.md` 決策 4 補一句。
- [x] **Step 6: 全套測試。** Run（背景）：`flutter test --no-pub`（Task 3 改過 `pubspec.yaml`，不帶 `--no-pub` 會觸發 `pub get` 而弄髒 `pubspec.lock`）。記錄結果；本機已知偶發失敗見 Issue 11（`local_book_server_test.dart`、`pdf_reader_view_filters_test.dart`），如實寫進 PR。
- [x] **Step 7: Commit。**

```bash
git add app/lib/main.dart docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/issue-9-report.md docs/epics/epic-66-windows-port/epic.md
git commit -m "feat(windows): 啟動時檢查 WebView2 Runtime，缺少時顯示說明畫面（epic-66 Issue 9 Task 4）"
```

---

## Issue 9 過關條件（Task 4 Step 5 寫入 `issues.md`）

1. Windows 啟動時偵測不到 WebView2、或環境建立失敗／逾時，顯示說明畫面而非壞掉的閱讀器；畫面含標題、說明、下載按鈕、網址、重新檢查。
2. 「下載」開啟預設瀏覽器到微軟官方頁；開啟失敗時網址仍可選取複製。
3. 「重新檢查」成功後直接進入 App，不必重開；進行中不可重入。
4. 說明畫面語系與 App 一致（覆寫優先，否則系統）。
5. 有 WebView2 時啟動行為與現況完全相同；Android 與其他平台零改動。
6. 人工驗證：用模擬方式驗證 1～4（本機無法移除 Runtime）；如實記錄「未在真正沒裝 Runtime 的機器上測過」。

## Self-Review

- **Spec coverage：** 決策 4（顯示說明與下載連結）→ Task 3、4；Q1（整個 App 擋住）→ Task 4 Step 2 `return`；Q2（`url_launcher`）→ Task 3 Step 1；Q3（重新檢查）→ Task 3 測試與 Task 2 的可重複呼叫設計。
- **型別一致：** `WebView2CheckResult`、`checkAndInitWebView2`、`kWebView2DownloadUrl` 在 Task 2 定義，Task 3、4 照用；`recheck` 型別為 `Future<WebView2CheckResult> Function()`，與 Task 4 傳入的閉包一致。
- **Review Focus 對應：** 1、2、3 → Task 2 測試；4、5 → Task 3 測試。
- **已知風險：** Task 1 的結論可能改變 Task 2 的設計（`create` 若會殺程序，偵測失敗時不得呼叫它）；這是刻意把量測放在第一個 Task 的原因。
