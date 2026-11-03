# Issue 1：Windows 技術驗證實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 啟用 `app/windows/`，讓 App 在 Windows 啟動並開得了書，逐項回答 `issues.md` 的 7 個過關條件，產出 `spike-report.md`。

**Architecture：** 先走「請求攔截」路線：`flutter_inappwebview_windows` 0.6.0 的 C++ 原始碼（`in_app_webview.cpp:827-899`）用 WebView2 的 `WebResourceRequested` 實作了 `shouldInterceptRequest`。所以 Windows 可以沿用 Android 既有的攔截模式，在 Dart 端回應 foliate 資源與書檔，網址仍是 `https://appassets.androidplatform.net`，`main.js` 不用改。只有攔截行不通時，才退回本機 `shelf` 伺服器。平台差異用 `defaultTargetPlatform` 判斷（不用 `Platform.isWindows`），這樣既有的 `flutter test` 預設平台仍是 Android，既有測試不受影響。

**Tech Stack：** Flutter 3.47.4、`flutter_inappwebview` 6.1.5（Windows 實作 0.6.0）、`pdfrx`、`sqflite_common_ffi`、`flutter_secure_storage`、`integration_test`。

**Spec：** 沒有獨立 `spec.md`。設計依據是 `docs/epics/epic-66-windows-port/epic.md`「Discovery 決策」與「審查修訂」（決策 1～24），過關條件見 `issues.md`。

## 與 `epic.md` 決策 15 的差異（使用者已確認，2026-11-03）

原決策 15 寫「Issue 1 含最小 `shelf` 送書原型」。計畫階段查到 Windows 外掛已支援請求攔截，所以本計畫改成「攔截優先，伺服器是備案」。理由：攔截不新增伺服器、不開本機埠、`main.js` 與寫死網域都不用動，也不用做權杖。**如果 Task 9 實測攔截失敗，才加做 `shelf` 原型。**

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **Android 行為不變**：每個改動在 Android（`defaultTargetPlatform == TargetPlatform.android`）的路徑要和改動前逐字相同。
- **平台判斷**：只用 `defaultTargetPlatform`，不用 `dart:io` 的 `Platform`。測試用 `debugDefaultTargetPlatformOverride` 切換，並在 `tearDown` 還原為 `null`。
- **不改的檔案**：`main.js`、`app/android/**`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次，`run_in_background`，只跑一個。
- **提交前**：`flutter analyze` 必須 "No issues found!"。Node 腳本（`tool/check_*.js`）依記憶中的做法，把 pnpm 內建的 Node 24 前置到 `PATH` 後執行。
- **Commit**：不加 `Co-Authored-By`。每個 Task 一個 commit。
- **不在本 Issue 範圍**：WebView2 執行環境未安裝時的錯誤畫面、權杖、快取清理、鍵盤快捷鍵、F11、平台專屬功能隱藏的完整清單、打包。

## Review Focus

1. 書檔路徑含中文或空白（例如 `C:\Users\王小明\我的 書\a b.epub`）：要能複製到快取並開啟。測試在 Task 6。
2. 書檔是 217 MB 等級：攔截回傳整本位元組，記憶體可能暴增。Task 9 實測並記錄尖峰記憶體。
3. 同一本書連開兩次、或開書中途離開畫面：快取子目錄不能互相覆蓋或殘留。測試在 Task 6。
4. 攔截回呼收到未知路徑：回 `null`（讓 WebView 走預設行為），不丟例外。測試在 Task 6。
5. Windows 啟動時 `AudioService` 被跳過：閱讀器的 TTS 入口不能顯示降級提示。測試在 Task 3（`consumeDegradedNotice()` 恆為 `false`）。

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `app/windows/**` | 建立 | `flutter create` 產生的 Windows 平台資料夾 |
| `app/lib/platform/platform_support.dart` | 建立 | `isWindowsPlatform`／`isAndroidPlatform` |
| `app/lib/reader/tts_audio_handler_startup.dart` | 修改 | 新增 `notRequired` 狀態與建構子 |
| `app/lib/main.dart` | 修改 | Windows 跳過 `AudioSession`／`AudioService`；建立 WebView2 環境 |
| `app/lib/windows/windows_webview_environment.dart` | 建立 | `WebViewEnvironment` 的建立與全域存取 |
| `app/lib/reader/windows_reader_resources.dart` | 建立 | Windows 版 foliate 資源讀取、書檔快取、字型讀取 |
| `app/lib/reader/foliate_native_bridge.dart` | 修改 | 四個 Android channel 函式依平台分流 |
| `app/lib/reader/foliate_reader_view.dart` | 修改 | 攔截 `/book/`；Windows 不設 `webViewAssetLoader`；帶入 `webViewEnvironment` |
| `app/lib/search/foliate_content_indexer.dart` | 修改 | 帶入 `webViewEnvironment`；Windows 攔截 `/book/`；`webViewAssetLoader` 只在 Android 設定 |
| `app/lib/reader/tts_audio_focus_source.dart` | 修改 | 新增 `NoopTtsAudioFocusSource` |
| `app/lib/screens/support/book_import_picker_helper.dart` | 修改 | 取 `f.identifier ?? f.path` |
| `app/lib/library/book_import_service_impl.dart` | 修改 | metadata channel 不存在時降級 |
| `app/windows/CMakeLists.txt` | 修改 | 把 foliate 資源複製到 `data/foliate` |
| `app/integration_test/windows_spike/*.dart` | 建立 | 條件 3～7 的探針測試 |
| `docs/epics/epic-66-windows-port/spike-report.md` | 建立 | 驗證報告 |

---

### Task 1：前置條件與啟用 Windows 平台

**Files：**
- Create：`app/windows/**`（`flutter create` 產生）

- [ ] **Step 1（你手動執行）：安裝 Visual Studio**

這台機器的 `flutter doctor` 顯示 Visual Studio 未安裝，沒有它無法建置 Windows App。請在 PowerShell 執行：
`winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive"`
只裝 Build Tools，不裝編輯器介面。Visual Studio Code 不能取代，它沒有 C++ 編譯器。工作負載要含 C++ 工具與 ATL（`--includeRecommended` 會帶上），`flutter_secure_storage` 需要 ATL。

- [ ] **Step 2：確認環境**

Run：`flutter doctor -v`
Expected：「Visual Studio - develop Windows apps」顯示 `[✓]`。沒過就停下來，回報給使用者。

- [ ] **Step 3：產生平台資料夾**

Run（在 `app/`）：`flutter create --platforms=windows --org cc.ugotit --project-name elinkbook .`
Expected：新增 `app/windows/`；`pubspec.yaml` 與 `lib/` 沒有被改。用 `git status` 確認只新增 `windows/`。

- [ ] **Step 4：基準建置**

Run：`flutter build windows --debug`
Expected：成功，或失敗訊息指出哪個外掛不相容。失敗時把完整訊息記下來，逐一處理（例如 `win32` 版本鏈衝突），不要貿然升級 `pubspec.yaml` 的套件版本，先回報。

- [ ] **Step 5：Commit**

```bash
git add app/windows
git commit -m "chore(windows): 啟用 Windows 平台資料夾（epic-66 Issue 1）"
```

---

### Task 2：平台判斷輔助

**Files：**
- Create：`app/lib/platform/platform_support.dart`
- Test：`app/test/platform/platform_support_test.dart`

**Interfaces：**
- Produces：`bool get isWindowsPlatform`、`bool get isAndroidPlatform`，皆讀 `defaultTargetPlatform`。

- [ ] **Step 1：寫失敗的測試**

測試名稱與斷言：
- `預設測試平台是 Android`：`isAndroidPlatform == true`、`isWindowsPlatform == false`。
- `覆寫為 Windows 後`：`debugDefaultTargetPlatformOverride = TargetPlatform.windows` 時，`isWindowsPlatform == true`、`isAndroidPlatform == false`。`tearDown` 設回 `null`。

- [ ] **Step 2：執行確認失敗**

Run：`flutter test test/platform/platform_support_test.dart`
Expected：FAIL，找不到檔案或符號。

- [ ] **Step 3：實作**

在 `app/lib/platform/platform_support.dart` 實作兩個頂層 getter。

- [ ] **Step 4：執行確認通過**

Run：`flutter test test/platform/platform_support_test.dart`
Expected：PASS。

- [ ] **Step 5：Commit**

```bash
git add app/lib/platform/platform_support.dart app/test/platform/platform_support_test.dart
git commit -m "feat(platform): 新增平台判斷輔助（epic-66 Issue 1）"
```

---

### Task 3：啟動鏈平台防護與 TTS「此平台不需要」狀態

**Files：**
- Modify：`app/lib/reader/tts_audio_handler_startup.dart:40`（enum）、`:51-71`（`TtsAudioHandlerHolder` 與建構子區）
- Modify：`app/lib/reader/tts_audio_focus_source.dart`（新增 `NoopTtsAudioFocusSource implements TtsAudioFocusSource`，`events` 恆為 `const Stream.empty()`）
- Modify：`app/lib/main.dart:253-300`
- Test：`app/test/reader/tts_audio_handler_startup_test.dart`（沿用既有檔；沒有就建立）

**Interfaces：**
- Produces：`TtsAudioHandlerStatus.notRequired`；`TtsAudioHandlerHolder.notRequired()`（`status == notRequired`、`handler == null`、`consumeDegradedNotice()` 恆為 `false`）。

- [ ] **Step 1：寫失敗的測試**

測試名稱與斷言：
- `notRequired：狀態為 notRequired、沒有 handler`。
- `notRequired：consumeDegradedNotice 恆為 false`（呼叫兩次都是 `false`）。
- `notRequired：不會被 startTtsAudioHandlerInBackground 的流程改變`：建構後呼叫公開 API 不改變 `status`。

- [ ] **Step 2：執行確認失敗**

Run：`flutter test test/reader/tts_audio_handler_startup_test.dart`
Expected：FAIL，`notRequired` 未定義。

- [ ] **Step 3：實作 holder**

enum 新增 `notRequired`；新增 `TtsAudioHandlerHolder.notRequired()` 建構子（`_status = notRequired`、`_handler = null`、`_noticePending = false`）。`_completeReady`／`_completeFailed` 已有 `!= pending` 就返回的防護，不用改。

- [ ] **Step 4：修改 `main.dart`**

`isWindowsPlatform` 為真時：不呼叫 `AudioSession.instance`／`configure`、不呼叫 `AudioService.init`，`ttsAudio` 指派 `TtsAudioHandlerHolder.notRequired()`；`ttsAudioFocusSource` 在 Windows 使用 `NoopTtsAudioFocusSource()`。Android 分支逐字保留。

- [ ] **Step 5：確認沒有分支需要補**

`grep -rn "TtsAudioHandlerStatus" lib` 預期只出現在 `tts_audio_handler_startup.dart` 內（審查已查證：`ReaderScreen` 直接讀 `holder.handler` 與 `consumeDegradedNotice()`，沒有人依 `status` 分支）。如果出現其他使用處，逐一確認對 `notRequired` 的行為（不顯示載入中、不顯示降級提示）並各補一個測試。

- [ ] **Step 6：執行確認通過**

Run：`flutter test test/reader/tts_audio_handler_startup_test.dart`，再跑 Step 5 新增的測試檔。
Expected：PASS。再跑 `flutter analyze`，Expected：`No issues found!`。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/tts_audio_handler_startup.dart app/lib/main.dart app/test
git commit -m "feat(tts): Windows 跳過 AudioService，新增 notRequired 狀態（epic-66 Issue 1）"
```

---

### Task 4：Windows 的 WebView2 環境

**Files：**
- Create：`app/lib/windows/windows_webview_environment.dart`
- Modify：`app/lib/main.dart`（在 `runApp` 之前呼叫）
- Test：`app/test/windows/windows_webview_environment_test.dart`

**Interfaces：**
- Produces：`WebViewEnvironment? appWebViewEnvironment`（頂層變數，預設 `null`）；`Future<void> initAppWebViewEnvironment({required String userDataFolder})`。非 Windows 平台呼叫時什麼都不做，`appWebViewEnvironment` 保持 `null`。

- [ ] **Step 1：寫失敗的測試**

- `非 Windows：init 後 appWebViewEnvironment 仍是 null`。
- 在 Windows 建立 `WebViewEnvironment` 需要原生外掛，單元測試測不到。只測「呼叫 Windows 路徑時用的 `userDataFolder` 以 `%APPDATA%` 下的 App 資料夾為根」：把資料夾組合抽成 `String windowsWebViewUserDataFolder(String appSupportPath)`，斷言回傳 `p.join(appSupportPath, 'webview_data')`。

- [ ] **Step 2：執行確認失敗**，Run：`flutter test test/windows/windows_webview_environment_test.dart`，Expected：FAIL。

- [ ] **Step 3：實作**

Windows 路徑：`WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: ...))`，結果存入 `appWebViewEnvironment`。`main.dart` 用已有的 `getApplicationSupportDirectory()` 取得根目錄。

- [ ] **Step 4：執行確認通過**，並跑 `flutter analyze`。

- [ ] **Step 5：Commit**

```bash
git add app/lib/windows app/lib/main.dart app/test/windows
git commit -m "feat(windows): 建立 WebView2 環境並指定使用者資料夾（epic-66 Issue 1）"
```

---

### Task 5：foliate 資源打包到 Windows

**Files：**
- Modify：`app/windows/CMakeLists.txt`

- [ ] **Step 1：加入複製規則**

在 `install(...)` 區段加入：把 `${CMAKE_CURRENT_SOURCE_DIR}/../android/app/src/main/assets/foliate` 複製到 `${INSTALL_BUNDLE_DATA_DIR}/foliate`。單一來源，不複製進 `pubspec.yaml`，Android 的 APK 大小不變。

- [ ] **Step 2：確認**

Run：`flutter build windows --debug`
Expected：`app/build/windows/x64/runner/Debug/data/foliate/main.js` 存在（用 `ls` 確認）。

`flutter build windows` 與 `flutter run -d windows` 都會以 `--target INSTALL` 建置（Flutter 工具 `build_windows.dart:225,251` 預設 `install = true`），所以 `install()` 規則在兩者都會執行，不需要另加 `POST_BUILD` 複製。在 Task 9 Step 1 用 `flutter run` 啟動後，再確認一次該檔案存在。

- [ ] **Step 3：Commit**

```bash
git add app/windows/CMakeLists.txt
git commit -m "build(windows): 打包 foliate-js 資源（epic-66 Issue 1）"
```

---

### Task 6：Windows 的讀者資源實作

**Files：**
- Create：`app/lib/reader/windows_reader_resources.dart`
- Test：`app/test/reader/windows_reader_resources_test.dart`

**Interfaces：**
- Produces：
  - `Future<Uint8List?> loadWindowsFoliateAsset(String relativePath, {required String assetRoot})`：讀 `assetRoot/<relativePath>`；檔案不存在回 `null`；路徑含 `..` 回 `null`。
  - `Future<String?> cacheWindowsBook(String filePath, String instanceId, {required Directory baseDir})`：複製到 `baseDir/<instanceId>/current.<ext>`，回傳該檔絕對路徑；來源不存在回 `null`。副檔名沿用 `cacheFileExtension`。
  - `Future<Uint8List?> loadWindowsFileBytes(String path)`：讀本機檔案，不存在回 `null`。
  - `Future<Uint8List?> readWindowsBookBytes(String requestPath, String bookDir)`：`requestPath` 必須以 `/book/` 開頭，其餘部分是檔名；讀 `bookDir/<檔名>`。路徑不以 `/book/` 開頭、檔名含 `..` 或路徑分隔符號、檔案不存在，一律回 `null`。閱讀器與索引器共用。
  - `String windowsBookContentType(String fileName)`：`.epub` 回 `application/epub+zip`，`.cbz` 回 `application/vnd.comicbook+zip`，其餘回 `application/octet-stream`。

- [ ] **Step 1：寫失敗的測試**（用 `Directory.systemTemp.createTemp`）

- `loadWindowsFoliateAsset：讀得到存在的檔案`。
- `loadWindowsFoliateAsset：不存在回 null`。
- `loadWindowsFoliateAsset：路徑含 .. 回 null`（`'../secret.txt'`）。
- `cacheWindowsBook：路徑含中文與空白也能複製`（來源 `我的 書/a b.epub`，內容位元組一致）。
- `cacheWindowsBook：同一本書用不同 instanceId 不互相覆蓋`。
- `cacheWindowsBook：來源不存在回 null`。
- `readWindowsBookBytes：讀得到 /book/current.epub`。
- `readWindowsBookBytes：/assets/foliate/main.js 回 null`。
- `readWindowsBookBytes：/book/../secret.txt 回 null`。
- `windowsBookContentType：.epub 與 .cbz 與未知副檔名各一個斷言`。

- [ ] **Step 2：執行確認失敗**，Run：`flutter test test/reader/windows_reader_resources_test.dart`，Expected：FAIL。

- [ ] **Step 3：實作**三個函式。大檔複製用串流（`File.openRead` 接 `openWrite`），不整包讀進記憶體。

- [ ] **Step 4：執行確認通過**，並跑 `flutter analyze`。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/windows_reader_resources.dart app/test/reader/windows_reader_resources_test.dart
git commit -m "feat(reader): 新增 Windows 讀者資源實作（epic-66 Issue 1）"
```

---

### Task 7：把 Windows 路徑接進閱讀器與索引器

**Files：**
- Modify：`app/lib/reader/foliate_native_bridge.dart:71`（`loadAndroidAsset`）、`:95`（`loadCustomFontBytes`）、`:80-90`（`attachReaderView`／`detachReaderView`）、`:126-129`（`_defaultCacheBookForServing`）
- Modify：`app/lib/reader/foliate_reader_view.dart:812-960`
- Modify：`app/lib/search/foliate_content_indexer.dart:97`、`:229-245`
- Test：`app/test/reader/foliate_native_bridge_platform_test.dart`、`app/test/reader/foliate_intercept_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `isWindowsPlatform`；Task 4 的 `appWebViewEnvironment`；Task 6 的三個函式。
- Produces：`FoliateRequestKind classifyFoliateRequestPath(String path)`，回傳 `foliateAsset`／`book`／`customFont`／`downloadedFont`／`unknown`，把 `_shouldInterceptRequest` 裡的路徑判斷抽成可測的純函式（現有註解已說明 widget test 測不到私有攔截方法，見 `foliate_reader_view.dart:233-245`）。

- [ ] **Step 1：寫失敗的測試**

`foliate_native_bridge_platform_test.dart`：
- `Windows：attachReaderView 不呼叫 MethodChannel`（覆寫平台為 Windows，用 `TestDefaultBinaryMessengerBinding` 攔截 `elinkbook/volume_key`，斷言呼叫次數為 0）。
- `Android：attachReaderView 仍呼叫 volume_key channel 一次`。
- `Windows：loadAndroidAsset 不呼叫 reader_resources channel`。

`foliate_intercept_test.dart`：
- `classifyFoliateRequestPath('/assets/foliate/main.js') == foliateAsset`。
- `classifyFoliateRequestPath('/book/current.epub') == book`。
- `classifyFoliateRequestPath('/unknown') == unknown`。

- [ ] **Step 2：執行確認失敗**，Expected：FAIL。

- [ ] **Step 3：實作**

- `foliate_native_bridge.dart`：`isWindowsPlatform` 時，`attachReaderView`／`detachReaderView` 直接返回；`loadAndroidAsset` 呼叫 `loadWindowsFoliateAsset`，`assetRoot` 預設為執行檔旁的 `data/` 目錄（`Platform.resolvedExecutable` 的父目錄）；另提供頂層可覆寫變數 `String? windowsFoliateAssetRootOverride`（比照 `cacheBookForServing` 的測試覆寫設計），非 null 時優先使用，讓測試不必依賴 `flutter_tester.exe` 的位置；`loadCustomFontBytes` 呼叫 `loadWindowsFileBytes`；`_defaultCacheBookForServing` 呼叫 `cacheWindowsBook`，`baseDir` 為 `getTemporaryDirectory()` 下的子資料夾。Android 分支逐字保留。
- `foliate_reader_view.dart`：`_shouldInterceptRequest` 新增 `book` 分支，僅 Windows 啟用：呼叫 `readWindowsBookBytes(path, _bookCacheDir!)`，非 null 就以 `windowsBookContentType` 回傳，null 就回 `null`。`webViewAssetLoader` 只在 Android 設定。`InAppWebView` 與 `HeadlessInAppWebView` 都傳入 `webViewEnvironment: appWebViewEnvironment`。
- `foliate_content_indexer.dart`：傳入 `appWebViewEnvironment`；`webViewAssetLoader` 只在 `isAndroidPlatform` 時設定；`_shouldInterceptIndexRequest` 目前是 `static` 且只認 `/assets/foliate/`，改成可取得 `cacheDir` 的閉包（`cacheDir` 是索引流程內的區域變數），在 Windows 對 `/book/` 路徑呼叫 `readWindowsBookBytes(path, cacheDir)`。Android 的行為不變。

- [ ] **Step 4：執行確認通過**

Run：兩個新測試檔，加上既有的 `flutter test test/reader/foliate_reader_view_test.dart`（檔名以 `ls test/reader | grep foliate` 為準，只跑這次異動實際觸及的）。
Expected：PASS。再跑 `flutter analyze`。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader app/lib/search app/test/reader
git commit -m "feat(reader): Windows 以請求攔截提供書檔與 foliate 資源（epic-66 Issue 1）"
```

---

### Task 8：Windows 最小匯入支援

Task 9 要用標準 UI 匯入 fixture。新編譯的 Windows 版書庫是空的，而現有匯入流程有兩道阻礙（審查 I-2），所以本 Task 只做讓匯入能動的最小改動。資料夾匯入、`Book.filePath` 規範留給後續 Issue。

**Files：**
- Modify：`app/lib/screens/support/book_import_picker_helper.dart:29-30`、`:148`
- Modify：`app/lib/library/book_import_service_impl.dart:305`、`:477`
- Test：`app/test/screens/support/book_import_picker_helper_test.dart`、`app/test/library/book_import_service_missing_channel_test.dart`

**Interfaces：**
- Consumes：無。
- Produces：選檔器對 `PlatformFile` 取 `identifier ?? path`；`_readEpubIdentifier` 與 `_importSingleFile` 的 metadata 呼叫在 `MissingPluginException` 時降級，行為與現有 `PlatformException` 降級相同。

- [ ] **Step 1：寫失敗的測試**

- `選檔器：identifier 為 null 時改用 path`：`PlatformFile(name: 'a.epub', size: 1, path: 'C:/books/a.epub')`（`identifier` 為 null）通過過濾，URI 為 `C:/books/a.epub`。
- `選檔器：identifier 與 path 都是 null 時被過濾`。
- `選檔器：兩者都有時優先用 identifier`（Android 行為不變）。
- `匯入 EPUB：metadata channel 不存在時，標題退回檔名、不丟例外`（測試環境未註冊 `elinkbook/book_metadata` handler，invoke 會丟 `MissingPluginException`）。沿用既有匯入服務測試的建構方式（`ls test/library | grep import_service` 找範本）。

- [ ] **Step 2：執行確認失敗**

Run：兩個新測試檔。Expected：FAIL。

- [ ] **Step 3：實作**

- 選檔器：過濾條件與 URI 取值改為 `f.identifier ?? f.path`，同一次過濾建立 `uris` 與 `displayNames`，保持逐一對應（檔案內現有註解已要求）。`:148` 的單檔路徑同樣處理。
- 匯入服務：在 `:305` 與 `:477` 的 `on PlatformException` 之後各加一個 `on MissingPluginException` 子句，內容與前者相同。Android 不會觸發這個例外，行為不變。

- [ ] **Step 4：執行確認通過**

Run：兩個新測試檔，加上既有的匯入服務測試檔與選檔器相關測試檔（`ls test/library test/screens/support` 確認實際檔名）。再跑 `flutter analyze`。
Expected：PASS，`No issues found!`。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/support/book_import_picker_helper.dart app/lib/library/book_import_service_impl.dart app/test
git commit -m "feat(import): Windows 選檔取 path，metadata channel 不存在時降級（epic-66 Issue 1）"
```

---

### Task 9：開書實測（過關條件 1、2）

這個 Task 要人眼確認，無法自動化。

- [ ] **Step 1：啟動**

Run（在 `app/`）：`flutter run -d windows`
Expected：App 視窗出現，沒有 `MissingPluginException`。若有，記下例外與來源，判斷是否擋住「匯入並開書」，只閘住會擋路的，其餘寫進報告。

- [ ] **Step 2：匯入並開書**

用標準 UI 匯入（Task 8 已讓它可用）：`test/fixtures/sample_horizontal.epub`、`sample_declares_vertical.epub`、`sample_long_chinese_vertical.epub`。逐本開啟。
Expected：橫排與直排方向正確；翻頁正常。

- [ ] **Step 3：滑鼠選字**

在直排書上按住滑鼠左鍵拖曳選字。
Expected：出現劃線工具列，可建立劃線。

- [ ] **Step 4：大檔記憶體**

匯入一本 200 MB 以上的 EPUB 或 CBZ（沒有就請使用者提供）。開書時用工作管理員記下 App 與 `msedgewebview2.exe` 的尖峰記憶體。
Expected：能開；把尖峰數字記進報告。若記憶體暴增到不可用，記為「攔截路線對大檔不可行」。

- [ ] **Step 5：判斷是否需要伺服器備案**

任何一本打不開，且原因是攔截無效（`onReceivedError`／`OpenBookTrace` 顯示請求沒到 Dart 回呼），就停下來回報使用者，決定是否加做 `shelf` 原型。

- [ ] **Step 6：截圖存證**

截圖存到 `docs/epics/epic-66-windows-port/assets/`（橫排、直排、劃線工具列各一張）。

---

### Task 10：探針測試（過關條件 3～7）

**Files：**
- Create：`app/integration_test/windows_spike/pdf_cover_test.dart`
- Create：`app/integration_test/windows_spike/fts5_test.dart`
- Create：`app/integration_test/windows_spike/secure_storage_test.dart`
- Create：`app/integration_test/windows_spike/mdx_network_block_test.dart`
- Create：`app/integration_test/windows_spike/headless_metadata_test.dart`

每支測試都是獨立執行：`flutter test integration_test/windows_spike/<檔名> -d windows`。

- [ ] **Step 1：PDF（條件 3）**

`pdf_cover_test.dart`：用 `pdfrx` 開 `test/fixtures/sample_multi_page.pdf`。斷言：`document.pages.length` 等於檔案實際頁數（用 `sample_multi_page.pdf` 已知頁數，執行時先印出再寫死）；第 0 頁 `render()` 後用 `createImage()` 取得 `dart:ui.Image`，再用 `toByteData(format: ImageByteFormat.png)` 轉成位元組，開頭為 PNG 簽章 `89 50 4E 47`。

- [ ] **Step 2：FTS5（條件 6）**

`fts5_test.dart`：先呼叫 `sqfliteFfiInit()`（獨立 integration test 不會經過 `main.dart`），再用 `databaseFactoryFfi` 開記憶體資料庫，`CREATE VIRTUAL TABLE t USING fts5(body)`，插入「直排繁體中文」，用 `MATCH` 查詢，斷言命中 1 列。

- [ ] **Step 3：安全儲存（條件 7）**

`secure_storage_test.dart`：用 `FlutterSecureStorage` 寫入再讀回 `authToken`，斷言相等；結尾刪除該鍵。

- [ ] **Step 4：MDX 擋網路（條件 5）**

`mdx_network_block_test.dart`：用 `HeadlessInAppWebView`（帶 `appWebViewEnvironment`），設 `javaScriptEnabled: false`、`useShouldInterceptRequest: true`，載入含 `<img src="https://example.com/x.png">` 與 `<link rel="stylesheet" href="https://example.com/a.css">` 的 HTML。回呼對所有請求回 404 `WebResourceResponse`。斷言：每個外部請求都進了回呼；回呼收到的請求清單裡沒有被放行的外部網址。另外斷言頁面內嵌的 `<script>` 沒有執行（以 `<noscript>` 與頁面標題變化判斷）。

- [ ] **Step 5：背景解析（條件 4）**

`headless_metadata_test.dart`：用 `HeadlessInAppWebView` 載入探針頁（由攔截回呼從 Dart 字串提供，內容為一個 `<script type="module">`，從 `/assets/foliate/view.js` 取 `makeBook`，開 `/book/current.epub`，把 `book.metadata.title`、第一位作者、`identifier`、`rendition.layout`、封面 Blob 的 `type` 與 `size` 以 `callHandler` 傳回）。測試開頭先呼叫 Task 6 的 `cacheWindowsBook('test/fixtures/sample.epub', ...)` 把 fixture 複製到暫存目錄，攔截回呼再用 `readWindowsBookBytes` 回應 `/book/current.epub`。斷言：對 `sample.epub` 回傳的 `title` 非空、`identifier` 非空、封面 `size > 0`。同時把四個欄位印成 JSON，供 Task 11 做 Readium 對比表。

- [ ] **Step 6：執行並記錄**

逐支執行。Expected：每支 PASS 或明確 FAIL。FAIL 時記錄原因，不要硬改測試讓它過。

- [ ] **Step 7：Commit**

```bash
git add app/integration_test/windows_spike
git commit -m "test(windows): 新增 Windows 技術驗證探針（epic-66 Issue 1）"
```

---

### Task 11：驗證報告與收尾

**Files：**
- Create：`docs/epics/epic-66-windows-port/spike-report.md`
- Modify：`docs/epics/epic-66-windows-port/issues.md`（Issue 1 狀態）
- Modify：`docs/epics/epic-66-windows-port/epic.md`（依結果補充或修訂決策 6、7、15）

- [ ] **Step 1：寫報告**

`spike-report.md` 用一張表列 7 個條件，每項：通過／失敗、證據（測試名稱或截圖路徑）、備註。另列三個結論：
1. 送書方式：攔截可行嗎？大檔尖峰記憶體多少？需要伺服器備案嗎？
2. Metadata：foliate-js 的輸出欄位（來自 Task 10 Step 5）。Readium 的對比表放到後續 Issue，這裡只記 foliate-js 能讀出哪些欄位。
3. 啟動時遇到的所有 `MissingPluginException` 與處置。

- [ ] **Step 2：更新工單狀態**

`issues.md` 的 Issue 1 狀態改為「🟡 驗證完成，待審查」。

- [ ] **Step 3：完整測試**

Run（`run_in_background`，只跑一個）：`flutter test`
Expected：全綠。有失敗就先判斷是否為本 Issue 造成，不是就記錄為既有問題。再跑 `flutter analyze`，Expected：`No issues found!`。

- [ ] **Step 4：Commit**

```bash
git add docs/epics/epic-66-windows-port
git commit -m "docs(epic-66): Issue 1 技術驗證報告"
```

---

## 自我檢查

- **過關條件覆蓋**：1、2 → Task 9；3、4、5、6、7 → Task 10。
- **審查修訂覆蓋**：16（啟動鏈）→ Task 3；17（資源）→ Task 5；18（寫死網域）→ 攔截路線不需要改，已在 Architecture 說明；19（兩個消費者）→ Task 7；20（PDF 封面）→ Task 10 Step 1；23（使用者資料夾）→ Task 4。
- **部分納入**：21（選檔器 `f.identifier ?? f.path`）在 Task 8 做最小版；資料夾匯入（`getDirectoryPath()`）留給後續 Issue。
- **未涵蓋、留給後續 Issue**：22（`Book.filePath` 本機路徑規範）、24（`window_manager`）。
- **型別一致**：`isWindowsPlatform`（Task 2）→ Task 3、4、7 使用；`appWebViewEnvironment`（Task 4）→ Task 7、9 使用；Task 6 三個函式 → Task 7 使用。
