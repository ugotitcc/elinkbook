# Issue 29：Windows 資料收進 `文件\elinkbook` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Windows 版把直接放在使用者「文件」資料夾根目錄的 App 資料（8 個項目）收進上層目錄 `文件\elinkbook`，其他平台完全不變；解除安裝選「是」改為只刪 `文件\elinkbook` 與 `%APPDATA%\cc.ugotit\elinkbook`。

**Architecture:** 新增一個集中函式 `appDocumentsDirectory()`（`lib/platform/app_paths.dart`）：Windows 回傳 `<文件>\elinkbook` 並自動建立，其他平台原樣回傳 `getApplicationDocumentsDirectory()`。所有直接呼叫 `getApplicationDocumentsDirectory()` 的地方（Android 專用的 `foliate_native_bridge.dart` 除外）改呼叫它，並加一個原始碼掃描測試防止日後又散落。安裝程式 `elinkbook.iss` 的刪除範圍與驗證腳本同步縮成兩個資料夾。**不遷移舊資料**，舊位置的檔案不讀、不改、不刪。

**Tech Stack:** Dart／Flutter 3.47.9、`path_provider` 與既有的 `FakePathProviderPlatform` 測試替身、`debugDefaultTargetPlatformOverride`、Inno Setup 6、PowerShell。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 29 範圍／過關條件／單元測試要求」；`epic.md` 決策 33；[ADR 0044](../../../adr/0044-windows-data-under-documents-elinkbook.md)；[ADR 0043](../../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md) 決策 5。

## 已查證的事實（2026-11-13，計畫階段）

- 直接呼叫 `getApplicationDocumentsDirectory()` 的檔案共 9 個：`lib/cloud_import/cloud_book_downloader.dart`、`lib/dictionary/storage/dictionary_database.dart`、`lib/library/book_import_service_impl.dart`（3 處）、`lib/library/sqlite_library_repository.dart`、`lib/main.dart`（`sweepUpdateStaging`，約第 263 行）、`lib/remote/remote_book_downloader.dart`、`lib/wifi_transfer/wifi_transfer_http_server.dart`，以及 `lib/reader/foliate_native_bridge.dart`（約第 187 行）。最後一個只在 Android 路徑執行（Windows 在它之前就 `return`），**不動**。`lib/remote/remote_thumbnail_cache.dart` 只有文件註解提到該函式名稱。
- `lib/platform/platform_support.dart` 的 `isWindowsPlatform` 以 `defaultTargetPlatform` 判斷；`flutter test` 預設平台是 Android，測試用 `debugDefaultTargetPlatformOverride` 切換。因此既有測試（預設 Android）走原樣回傳的分支，**不會受影響**。
- 既有測試替身 `test/support/fake_path_provider_platform.dart` 的 `FakePathProviderPlatform(path)` 會讓 `getApplicationDocumentsPath()` 與 `getTemporaryPath()` 都回傳指定目錄。
- Windows 冒煙套件（`integration_test/windows_smoke_suite.txt` 列的檔案）沒有直接引用「文件」目錄或 `imported_books`／`covers`。`integration_test/manual_import_acceptance_test.dart` 用 `defaultLibraryDatabasePath()`，但不在冒煙套件內。
- 這台機器的「文件」根目錄有舊資料：`library.db`（修改時間 11/6）、`covers`（116 檔）、`imported_books`（96 項），以及使用者自己的檔案（`六祖壇經`、`Zoom` 等）。這台機器的 release 版畫面空白（Issue 30，根因未查明），所以**無法用 GUI 驗證**，只能驗證「啟動後檔案落在哪裡」。
- **未查證（實作時第一個要查）：** 有哪些既有測試同時把平台切成 Windows 又用到 `getApplicationDocumentsDirectory()`——這種測試的路徑期望會多一層 `elinkbook`。

## Global Constraints

- Flutter 3.47.9；`flutter analyze` 乾淨；不新增相依（`pubspec.lock` 不得變動）；**不修改** `windows/runner/`、`windows/CMakeLists.txt`、`lib/reader/foliate_native_bridge.dart`。
- Android 與其他平台行為完全不變：`appDocumentsDirectory()` 在非 Windows 必須回傳與 `getApplicationDocumentsDirectory()` 相同的路徑，且不建立任何子目錄。
- 舊位置（「文件」根目錄的 `library.db`、`covers` 等）**不讀、不改、不刪**，也不提示。
- 建置與啟動 App 前：先確認沒有殘留的 `elinkbook.exe`／`flutter_tester.exe`／`MSBuild.exe`、測試用 `dart`；不得與 Windows 整合測試或 Android 建置同時進行；可用記憶體不足 4 GB 就停止並回報。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動；`git add` 一律明確列檔。
- 註解與文件一律正體中文；程式碼註解要說明「為什麼」。
- 會動到真實資料或這台機器狀態的步驟（啟動 release 版）只確認檔案落點；**不刪除這台機器「文件」根目錄的舊資料**，那由使用者自己決定。
- **任何會啟動 `elinkbook.exe` 的步驟（含 `verify_windows_installer.ps1`）都必須使用 Task 1／2 之後的完整建置**：沿用修改前的 Release 輸出（`-SkipBuild`）或 Issue 27 留下的舊版 setup，會讓舊版程式碼直接讀寫「文件」根目錄的真實舊資料庫，違反「舊位置不讀、不改、不刪」並讓前後對照失真。用到「較舊版本」setup 時，必須用本次新建置的暫存目錄現場編出。（審查 I-1）
- 報告不得外推：只有這台機器的自動驗證與使用者回報；其他機器、乾淨機器、GUI 行為沒驗證的一律寫「未驗證」。

## Review Focus

1. 舊位置絕不被碰：全新啟動與 `defaultLibraryDatabasePath()`／`defaultDictionaryDatabasePath()` 必須落在 `elinkbook` 底下，且假「文件」根目錄裡預先放的舊 `library.db`、`covers` 前後內容不變。（Task 1、Task 2）
2. 非 Windows 回傳值不變：平台切成 Android／iOS 時路徑與 `getApplicationDocumentsDirectory()` 逐字相同，且不建立 `elinkbook`。（Task 1）
3. 日後有人新增直接呼叫就會再散落：原始碼掃描測試要能真的抓到（先在目前 9 個檔案上確認它是紅的）。（Task 2）
4. 解除安裝不得多刪：假「文件」根目錄的 `covers`、`imported_books`、`library.db` 與使用者其他檔案選「是」後必須原封不動；變異驗證要證明這個檢查抓得到多刪。（Task 3）
5. 使用者名稱或「文件」路徑含空格與中文（例如 `C:\Users\王小明\Documents`、OneDrive 重新導向）：路徑組合不得出錯。（Task 1）

---

### Task 1：`appDocumentsDirectory()` 與資料庫路徑

**Files:**
- Create: `app/lib/platform/app_paths.dart`
- Create: `app/test/platform/app_paths_test.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`（`defaultLibraryDatabasePath`，約第 15 行）、`app/lib/dictionary/storage/dictionary_database.dart`（`defaultDictionaryDatabasePath`，約第 10 行）
- Test: `app/test/library/windows_data_location_test.dart`

**Interfaces:**
- Produces: `const String kWindowsAppFolderName = 'elinkbook';` 與 `Future<Directory> appDocumentsDirectory();`（`lib/platform/app_paths.dart`）。Windows：先取 `getApplicationDocumentsDirectory()`，回傳並（遞迴）建立 `<該目錄>\elinkbook`；其他平台：原樣回傳 `getApplicationDocumentsDirectory()` 的結果，不建立任何東西。

- [x] **Step 0: 記錄舊位置基準（任何步驟啟動 App 之前）。** 對這台機器「文件」根目錄的 `library.db`、`dictionary.db`（若有）、`covers`、`imported_books`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging` 記錄：存在與否、檔案大小、`LastWriteTime`、資料夾內檔案數與總大小，存成 scratchpad 下的文字檔；Task 4 Step 1 與之比對。只讀取，不修改。
- [x] **Step 1: 寫失敗的測試 `test/platform/app_paths_test.dart`。** 用 `FakePathProviderPlatform` 把「文件」指到 `Directory.systemTemp.createTempSync('app paths 測試 ')` 底下（目錄名含空格與中文，覆蓋 Review Focus 5）；用 `debugDefaultTargetPlatformOverride` 切平台，並以 `addTearDown` 還原平台覆蓋、還原 `PathProviderPlatform.instance` 為原值、遞迴刪除暫存目錄（避免殘留與影響後續測試，審查 M-2）。測試名稱與斷言：
  - `Windows：回傳「文件」下的 elinkbook 並建立該資料夾`：`(await appDocumentsDirectory()).path == p.join(base.path, 'elinkbook')` 且 `Directory(...).existsSync()`。
  - `Windows：資料夾已存在時不報錯、重複呼叫路徑相同`：先 `createSync` 並放一個檔案，呼叫兩次，路徑相同、檔案仍在。
  - `Windows：不碰「文件」根目錄原本的檔案`：先在 `base` 放 `library.db` 與 `covers/a.bin`，呼叫後內容與位元組數不變。
  - `Android 與 iOS：原樣回傳 getApplicationDocumentsDirectory() 的路徑，且不建立 elinkbook`：對 `TargetPlatform.android`、`TargetPlatform.iOS` 各斷言 `path == base.path` 且 `Directory(p.join(base.path, 'elinkbook')).existsSync() == false`。
- [x] **Step 2: 執行確認失敗。** `flutter test test/platform/app_paths_test.dart`。Expected: FAIL（找不到 `appDocumentsDirectory`／檔案不存在）。
- [x] **Step 3: 實作 `lib/platform/app_paths.dart`。** 簽名見上方 Interfaces；用 `isWindowsPlatform` 判斷；檔頭註解說明三件事：為什麼 Windows 要有上層目錄（「文件」根目錄不能散落 App 資料，使用者看不出屬於誰）、為什麼不遷移（見 ADR 0044）、日後不要再直接呼叫 `getApplicationDocumentsDirectory()`。
- [x] **Step 4: 執行確認通過。** 同上指令。Expected: PASS。
- [x] **Step 5: 寫失敗的測試 `test/library/windows_data_location_test.dart`。** Windows 平台覆蓋＋同樣的假「文件」目錄：`defaultLibraryDatabasePath()` 回傳 `p.join(base.path, 'elinkbook', 'library.db')`、`defaultDictionaryDatabasePath()` 回傳 `p.join(base.path, 'elinkbook', 'dictionary.db')`；另一個 Android 平台案例斷言兩者仍是 `p.join(base.path, 'library.db')`／`p.join(base.path, 'dictionary.db')`。測試名稱：`Windows：資料庫路徑在 elinkbook 底下`、`Android：資料庫路徑維持在文件根目錄`。
- [x] **Step 6: 執行確認失敗。** `flutter test test/library/windows_data_location_test.dart`。Expected: Windows 案例 FAIL（路徑少一層 `elinkbook`），Android 案例 PASS。
- [x] **Step 7: 修改兩個 `default…DatabasePath()`，改呼叫 `appDocumentsDirectory()`。** 其餘邏輯不變；若 `path_provider` 匯入在該檔不再使用，移除。
- [x] **Step 8: 執行確認通過並跑同目錄既有測試。** `flutter test test/platform/app_paths_test.dart test/library/windows_data_location_test.dart`。Expected: PASS。
- [x] **Step 9: Commit。**

```bash
git add app/lib/platform/app_paths.dart app/test/platform/app_paths_test.dart app/test/library/windows_data_location_test.dart app/lib/library/sqlite_library_repository.dart app/lib/dictionary/storage/dictionary_database.dart
git commit -m "feat(windows): 新增 appDocumentsDirectory，資料庫路徑收進 文件\\elinkbook（epic-66 Issue 29 Task 1）"
```

---

### Task 2：其餘使用點改呼叫集中函式，並加防散落掃描測試

**Files:**
- Create: `app/test/platform/documents_directory_usage_test.dart`
- Modify: `app/lib/cloud_import/cloud_book_downloader.dart`、`app/lib/library/book_import_service_impl.dart`（3 處）、`app/lib/main.dart`（`sweepUpdateStaging` 那行）、`app/lib/remote/remote_book_downloader.dart`、`app/lib/wifi_transfer/wifi_transfer_http_server.dart`

**Interfaces:**
- Consumes: Task 1 的 `Future<Directory> appDocumentsDirectory()`。
- Produces: 掃描測試保證 `lib/` 內只有 `lib/platform/app_paths.dart` 與 `lib/reader/foliate_native_bridge.dart`（Android 專用）可以直接呼叫 `getApplicationDocumentsDirectory(`。

- [x] **Step 1: 寫失敗的掃描測試 `test/platform/documents_directory_usage_test.dart`。** 遞迴讀 `lib/**/*.dart`（`flutter test` 的工作目錄是 `app/`），逐行找 `getApplicationDocumentsDirectory(`；**忽略註解行**（`trim()` 後以 `//` 開頭，含 `///`）；允許清單為 `lib/platform/app_paths.dart` 與 `lib/reader/foliate_native_bridge.dart`。其餘出現的檔案收集成違規清單並 `expect(violations, isEmpty)`，失敗訊息列出「檔案:行號」。測試名稱：`lib/ 內只有 app_paths.dart 與 Android 專用的 foliate_native_bridge.dart 可以直接呼叫 getApplicationDocumentsDirectory`。路徑分隔符一律正規化成 `/` 再比對允許清單。
- [x] **Step 2: 執行確認失敗，並確認它抓到正確的 7 個檔案。** `flutter test test/platform/documents_directory_usage_test.dart`。Expected: FAIL，違規清單包含 `cloud_book_downloader.dart`、`book_import_service_impl.dart`（3 行）、`main.dart`、`remote_book_downloader.dart`、`wifi_transfer_http_server.dart`；`sqlite_library_repository.dart` 與 `dictionary_database.dart` 已在 Task 1 改掉，所以不在清單內（若清單與此不符，先查原因再繼續）。
- [x] **Step 3: 把上述檔案的 `getApplicationDocumentsDirectory()` 全部改成 `appDocumentsDirectory()`。** 補上 `import 'package:.../platform/app_paths.dart';`（依該檔既有匯入風格）；`path_provider` 匯入若在該檔不再使用（例如只剩 `getTemporaryDirectory` 就要保留）以 `flutter analyze` 的結果為準。不改任何其他邏輯。
- [x] **Step 4: 執行確認通過。** 掃描測試 PASS。
- [x] **Step 5: 找出受影響的既有測試並修正。** Bash：`grep -rln "debugDefaultTargetPlatformOverride" test | xargs grep -ln "FakePathProviderPlatform\|getApplicationDocumentsDirectory"`；PowerShell：`Get-ChildItem test -Recurse -Filter *.dart | Select-String -Pattern "debugDefaultTargetPlatformOverride" -List | ForEach-Object { Select-String -Path $_.Path -Pattern "FakePathProviderPlatform|getApplicationDocumentsDirectory" -List } | Select-Object -ExpandProperty Path -Unique`（審查 M-1）。找出同時把平台切成 Windows 又用到「文件」目錄的測試；對這些檔案單獨執行 `flutter test <檔案>`。預期大多數沒有（預設平台是 Android）；若有因為多了一層 `elinkbook` 而失敗的，只調整測試對路徑的期望（改成 `p.join(base, 'elinkbook', …)`），不改產品程式，並在 commit 訊息註明。
- [x] **Step 6: 跑相關測試目錄。** `flutter test test/library test/remote test/wifi_transfer test/cloud_import test/dictionary test/platform`。Expected: PASS（若有既有的偶發失敗，照實記錄並與本變更無關的證據一起列入報告）。
- [x] **Step 7: `flutter analyze` 與 l10n 檢查。** `flutter analyze` Expected: `No issues found!`；`node tool/check_l10n_hardcoded_strings.js` Expected: PASS（本任務沒有新增畫面字串，仍須確認）。
- [x] **Step 8: Commit。**

```bash
git add app/test/platform/documents_directory_usage_test.dart app/lib/cloud_import/cloud_book_downloader.dart app/lib/library/book_import_service_impl.dart app/lib/main.dart app/lib/remote/remote_book_downloader.dart app/lib/wifi_transfer/wifi_transfer_http_server.dart
git commit -m "refactor(windows): 其餘使用點改呼叫 appDocumentsDirectory，加防散落掃描測試（epic-66 Issue 29 Task 2）"
```

---

### Task 3：安裝程式與驗證腳本縮成兩個資料夾

**Files:**
- Modify: `app/windows/packaging/elinkbook.iss`、`app/tool/verify_windows_uninstall_data.ps1`

**Interfaces:**
- Consumes: Task 1／2 讓資料全部落在 `<文件>\elinkbook`。
- Produces: 選「是」只刪 `{userdocs}\elinkbook` 與 `{userappdata}\cc.ugotit\elinkbook`；`DocsRootOverride`／`AppDataRootOverride` 兩個驗證用 `/D` 定義保留。

- [x] **Step 1: 先改驗證腳本（期望的新行為，此時應失敗）。** `verify_windows_uninstall_data.ps1`：種資料改成 `fake-docs\elinkbook\` 底下放 `library.db`、`dictionary.db`（各含 `-wal`／`-shm`／`-journal`）與 `covers`、`imported_books`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging`；**誘餌**改為放在假「文件」**根目錄**：`covers\a.bin`、`imported_books\b.bin`、`library.db`、`dictionary.db`（模擬舊版留下的項目與使用者自己的同名資料夾），加上原本的 `六祖壇經\x.txt`、`desktop.ini`、`notes.txt`、`Zoom\z.txt`、`cc.ugotit\other\keep.txt`。刪除目標改為 `fake-docs\elinkbook` 與 `cc.ugotit\elinkbook` 兩個資料夾。檢查項名稱與說明同步改（例如 2c「選『是』：elinkbook 兩個資料夾已刪除」、2d「根目錄的舊項目與其他檔案原封不動」）。
- [x] **Step 2: 對「尚未修改的 `.iss`」執行，確認新驗證會失敗。** `powershell -ExecutionPolicy Bypass -File tool/verify_windows_uninstall_data.ps1`。Expected: **2c 與 2d 皆失敗**——2c 因為舊版 `.iss` 不會刪 `fake-docs\elinkbook`，2d 因為它會刪掉根目錄的 `covers`、`imported_books`、`library.db`、`dictionary.db` 誘餌；其餘通過。把輸出貼進報告。這一步只安裝測試用 setup、不啟動 App，不會碰真實資料。
- [x] **Step 3: 修改 `elinkbook.iss`。** 移除 `DocsFolderNames()`、`DocsDbNames()`；新增 `function DocsAppDir(): String`（`AddBackslash(DocsRoot()) + 'elinkbook'`）；`AnyAppDataExists()` 改成 `DirExists(AppDataDir()) or DirExists(DocsAppDir())`；`DeleteAppData()` 改成對這兩個資料夾各 `DelTree`（存在才刪；並且只在對應根目錄 `DocsRoot()`／`AppDataRoot()` 不是空字串時才動作，避免組出 `\elinkbook` 這種相對於磁碟根目錄的路徑，審查 M-3）；詢問框文字改為列出兩個資料夾與內容（書庫、字典庫、封面、匯入的書的複本、已下載字型等），並寫明「不會動『文件』資料夾內的其他檔案」。預設按鈕為「否」、`UninstallSilent` 判斷、`InitializeUninstall`（App 執行中拒絕）、兩個 `Override` 定義與檔頭註解都保留。
- [x] **Step 4: 重跑驗證，確認全部通過。** 同 Step 2 指令。Expected: 全部檢查通過、exit 0。
- [x] **Step 5: 變異驗證。** 暫時在 `.iss` 的 `DeleteAppData()` 多加一行刪除 `{DocsRoot}\covers`，重跑驗證，預期 2d 失敗並點名 `covers`；驗完用備份還原（`cmp` 確認還原）。
- [x] **Step 6: 完整建置、現場編出「較舊版本」setup，再跑本機自動驗證（審查 I-1）。** （a）`powershell -ExecutionPolicy Bypass -File tool/package_windows_installer.ps1`，**不帶 `-SkipBuild`**，讓 Release 包含 Task 1／2 的 Dart 改動；建置後確認 `build\windows\x64\runner\Release\elinkbook.exe` 的 `LastWriteTime` 晚於 Task 2 的 commit 時間，否則停下。（b）用**這次新建置的暫存目錄**複製一份到 scratchpad、改 `README.txt` 內容、`elinkbook.exe` 尾端補 1 個 0x00 位元組，以 `package_windows_installer.ps1 -StageDir <複本> -Version 1.0.9+1 -OutDir <scratchpad 輸出目錄>` 編出較舊版本 setup；**不要沿用 `scratchpad\older\out\`**（那是 Issue 27 的舊程式碼，且新對話中未必存在）。（c）`verify_windows_installer.ps1 -Setup <本次最終 setup.exe> -OlderSetup <(b) 的 setup>`。Expected: 29 項全過；跑完確認「文件」根目錄舊項目與 Task 1 Step 0 的基準相同。
- [x] **Step 7: Commit。**

```bash
git add app/windows/packaging/elinkbook.iss app/tool/verify_windows_uninstall_data.ps1
git commit -m "feat(windows): 解除安裝選「是」只刪 文件\\elinkbook 與 %APPDATA% 資料夾（epic-66 Issue 29 Task 3）"
```

---

### Task 4：實機落點驗證、冒煙測試、文件與報告

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-29-report.md`
- Modify: `app/windows/packaging/README.txt`（第三節、第七節）、`app/tool/README.md`（`verify_windows_uninstall_data.ps1` 小節）、`docs/adr/0043-windows-installer-inno-setup-unsigned-per-user.md`（決策 5、後果；Discovery 階段已更新過，這裡核對與實作是否一致，不一致才改）、`docs/epics/epic-66-windows-port/issues.md`（Issue 29 狀態）、`docs/epics/epic-66-windows-port/epic.md`（決策 33 補實作結果）、`docs/epics.md`（備註）、本檔（勾選步驟）

- [x] **Step 1: 完整建置並確認檔案落點（自動，不需 GUI）。** 使用 Task 3 Step 6 已完成的完整建置（之後若 `lib/` 又有變動才重建）；與 Task 1 Step 0 記錄的基準比對（舊 `library.db` 的大小與修改時間、`covers`／`imported_books` 等的檔案數與總大小）。從暫存目錄啟動 `elinkbook.exe`（`Start-Process -WorkingDirectory`）等 30 秒後結束行程樹，確認：`<文件>\elinkbook\library.db` 已建立；「文件」根目錄舊項目的大小、修改時間、檔案數**與啟動前完全相同**；根目錄沒有新增任何 App 項目。這台機器畫面空白（Issue 30），所以不驗證 GUI。
- [x] **Step 2: 全套測試與冒煙套件。** `flutter analyze`；完整 `flutter test`（無參數）；`powershell -ExecutionPolicy Bypass -File tool/run_windows_smoke.ps1`（執行前確認沒有殘留行程與足夠記憶體，輸出存到檔案、只讀結尾）。失敗照實記錄，與本變更無關的要附證據（例如還原到變更前仍失敗）。
- [x] **Step 2b: 本機自動驗證。** 對最終的 setup.exe 跑 `verify_windows_installer.ps1`（29 項）與 `verify_windows_uninstall_data.ps1`，輸出貼進報告。
- [x] **Step 3: 人工驗證（使用者操作，另一台電腦）。** 請使用者用新的 setup.exe：（i）安裝、匯入一本書、關閉 App 再開，書還在；（ii）確認書、封面、`library.db` 都在 `文件\elinkbook` 底下，「文件」根目錄沒有新增 App 項目；（iii）解除安裝選「是」，確認 `文件\elinkbook` 與 `%APPDATA%\cc.ugotit\elinkbook` 被刪除、「文件」內其他檔案沒動。結果照使用者回報原文記入報告，不外推。
- [x] **Step 4: 更新文件。** `README.txt` 第三節改成新位置（`文件\elinkbook` 與 `%APPDATA%` 兩處，不再列固定名稱清單，並說明舊版留下的項目要手動刪除）、第七節解除安裝說明改為只刪兩個資料夾；`app/tool/README.md` 的 `verify_windows_uninstall_data.ps1` 小節改成新流程與誘餌清單；核對 ADR 0043（決策 5、後果）與 ADR 0044 的敘述和最終實作一致（例如詢問框實際文字、刪除範圍），不一致就修；`issues.md`／`epic.md`／`docs/epics.md` 補實作結果與狀態。
- [x] **Step 5: 寫 `issue-29-report.md`。** 內容：已查證事實、各 Task 實際輸出、掃描測試先紅後綠的證據、Task 3 變異驗證輸出、Step 1 落點驗證的前後對照、冒煙與全套測試結果、人工驗證原文；**「舊項目手動清除清單」**（這台機器：`<文件>\library.db`、`dictionary.db`、`covers`、`imported_books`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging` 中實際存在的那些，註明升級後書架為空、需重新匯入）；「未驗證」清單（乾淨機器、GUI、其他機器、OneDrive 重新導向的「文件」、使用者名稱含中文的實機）。
- [x] **Step 6: 勾選本檔步驟並 Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-29-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/epic.md docs/epics.md docs/epics/epic-66-windows-port/plans/plan-issue-29.md app/windows/packaging/README.txt app/tool/README.md docs/adr/0043-windows-installer-inno-setup-unsigned-per-user.md docs/adr/0044-windows-data-under-documents-elinkbook.md
git commit -m "docs(epic-66): Issue 29 報告與文件（Task 4）"
```

---

## 已知風險

- **舊資料孤立**：升級後書架為空，舊位置的資料不會被讀取或刪除；已與使用者確認（ADR 0044）。報告必須明講並附手動清除清單。
- **既有測試的隱性依賴**：Task 2 Step 5 可能找到 Windows 平台覆蓋下的測試期望要多一層 `elinkbook`；只調整測試期望，不改產品程式。
- **這台機器 GUI 不可用**（Issue 30）：只能驗證檔案落點；匯入與重啟的行為靠使用者在另一台電腦驗證。
- **「文件」路徑被 OneDrive 重新導向或含中文**：`appDocumentsDirectory()` 只在 `getApplicationDocumentsDirectory()` 回傳的路徑後面接一層，與 Inno 的 `{userdocs}` 取同一個系統資料夾，理論上一致，但未在真機驗證。
- **Windows 冒煙套件耗時且吃資源**：同時間不要開其他建置或測試；結果有偶發失敗時，與本變更無關的要附證據。
