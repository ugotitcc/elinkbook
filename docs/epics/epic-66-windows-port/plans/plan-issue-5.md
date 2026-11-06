# Epic 66 Issue 5：Windows 檔案與資料夾匯入 實作計畫

> **給執行計畫的代理：** 必須使用 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行。步驟用 `- [ ]` 追蹤，完成一步就把它改成 `- [x]`。

**Goal：** 讓 Windows 使用者用選檔、選資料夾、拖曳三種方式把書放進書架，三者進同一條匯入管線，書檔維持原路徑，不支援的格式略過並在結果提示說明個數。

**Architecture：** 服務層：`ImportResult` 新增 `skippedUnsupportedCount`，`importFolder` 對非 `content://` 的本機資料夾改走 `dart:io` 列舉（只列第一層）。畫面層：`pickAndImportFolder` 的選資料夾動作可注入並在 Windows 用 `FilePicker.getDirectoryPath()`；新增純邏輯 `importDroppedPaths` 與 `ImportDropTarget`（包 `desktop_drop` 的 `DropTarget`），掛在 `AdaptiveShellScaffold` 的 `IndexedStack` 外層，只在 Windows、只在書架與來源分頁、且沒有路由疊在上方時啟用。

**Tech Stack：** Dart／Flutter 3.41.9、`desktop_drop` 0.8.4（固定版本）、`file_picker` 11.0.3（已有）、`path`、`sqflite_common_ffi`（測試）。

**Spec：** 沒有獨立 spec。權威依據是 `issues.md` 的「Issue 5 範圍／過關條件／單元測試要求」、`epic.md` 決策 5（修訂）與 25，以及 `CONTEXT.md`「拖曳匯入」。

## Global Constraints

- **語言：** 文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。UI 字串一律走 `AppLocalizations`，四個 arb（`app_zh_TW`〔範本〕、`app_zh`、`app_zh_CN`、`app_en`）都要補；`app_zh`、`app_zh_CN` 是簡體中文。
- **Flutter 3.41.9：** 不得使用此版本沒有的 API；`flutter analyze` 必須 `No issues found!`。**不得升級 Flutter 或其他既有套件版本**（升級是 Issue 6）。`pubspec.lock` 與本機 Flutter 有既有落差，`pub get` 可能降級 `intl`、`meta`、`pdfrx_engine` 等 6 個套件——**不要把這些降級 commit 進來**：Task 6 加依賴後，`git diff app/pubspec.lock` 只允許出現 `desktop_drop` 及其新增的傳遞相依（`universal_platform`、`dbus` 等）；其餘版本異動一律還原。
- **書檔不複製：** Windows 的 `Book.filePath` 維持來源檔案的標準本機路徑（`epic.md` 決策 5 修訂、決策 22）。不得新增任何複製書檔的程式。
- **Android 不變：** `content://` 的選檔與選資料夾路徑逐字不變；`importFolder` 的 `content://` 分支不得改動；`DropTarget` 在非 Windows 不得掛載。唯一允許的 Android 可見變更是新增的「略過不支援」提示。
- **不改介面簽章：** `BookImportService.importFiles`／`importFolder` 的簽章不變，只改回傳的 `ImportResult` 內容。
- **Widget 結構穩定：** `ImportDropTarget` 在 Windows 永遠包一層 `DropTarget`，用 `enable` 開關，**不可用條件式有無包裹**——否則 `IndexedStack` 內三個畫面的 State 會在開關時被重建而遺失。
- **Windows 環境：** 多數原始檔是 CRLF，Edit 的定位字串不要含換行；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔；不要用 `python`（本機只有 Windows 商店的空殼）。
- **測試範圍（`CLAUDE.md`）：** 單一 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次，`run_in_background`。
- **提交前：** `flutter analyze` 乾淨；改字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`；動到 `lib/` 的 Key 後跑 `node tool/check_integration_keys.js`。
- **Commit：** 每個 Task 一個 commit，訊息結尾附 `Co-Authored-By` 行；推送與開 PR 前由使用者確認。工作目錄是 worktree `.worktrees/epic-66-issue-5`，分支 `feat/epic-66-issue-5-import`，所有指令在該 worktree 的 `app/` 下執行。

## 已決策

使用者已確認（2026-11-06 `/grill-with-docs`）：入口三種；拖曳只在書架與來源畫面；資料夾只匯入第一層；拖入資料夾先跳確認框，多個資料夾只問一次；不支援格式略過並說明個數（跨平台）；疑似更新版沿用既有流程；匯入中再拖入忽略；拖曳經過顯示遮罩；書檔不複製維持原路徑，「來源」畫面常駐說明文字；`desktop_drop` 固定 0.8.4；Flutter 升級另開 Issue 6。

我的決定（請審查時確認，皆為使用者沒明講的細節）：

1. 取消確認框 → 整批（含同次拖入的單檔）都不匯入，與選資料夾取消時一致。
2. 合併結果的 `failure` 只在「這次拖入沒有檔案，且每一個資料夾都失敗」時才設；否則維持 `null`，讓成功的部分正常顯示。
3. 資料夾內的 `Thumbs.db`、`desktop.ini` 等系統檔不特別排除，與其他非書檔一樣計入「略過不支援」。
4. 列舉到的檔案路徑依檔名排序，讓匯入順序可預期。
5. 同次拖入重複的完全相同路徑，在分類時先去重。

## Review Focus

1. 資料夾存在但無法讀取：提示資料夾匯入失敗，不崩潰（Task 2；提示文字由既有 `showImportResultSnackBar` 的 `failure` 分支負責）。拖入「已不存在的路徑」則在 `classifyDroppedPaths` 被當成檔案，匯入時因副檔名無法辨識而計入略過不支援（Task 5），不會顯示資料夾失敗。
2. 路徑含中文與空白字元：照常匯入，檔名與標題正確（Task 5）。
3. 資料夾裡有 `desktop.ini` 之類的系統檔：計入略過數、不報錯（Task 2）。
4. 匯入尚未完成時畫面被卸載（例如關閉視窗）：不對已卸載的 context 顯示提示，並丟棄更新候選的暫存檔（Task 6）。
5. 拖入內容為空（例如拖曳的是一段文字，`files` 為空）：靜默忽略，不顯示任何提示、不進入忙碌狀態（Task 6）。

---

### Task 1：`ImportResult` 新增 `skippedUnsupportedCount` 並在服務中統計

**Files：**
- Modify: `app/lib/library/book_import_service.dart`（`ImportResult`）
- Modify: `app/lib/library/book_import_service_impl.dart`（`importFiles` 與 `importFolder` 的迴圈與兩處 `return ImportResult(...)`）
- Test: `app/test/library/book_import_service_missing_channel_test.dart`（沿用該檔的 `setUp`：真實 `SqliteLibraryRepository` 加暫存目錄，沒有註冊 metadata channel mock）

**Interfaces：**
- Produces: `ImportResult.skippedUnsupportedCount`（`final int`，建構子具名參數，預設 `0`）。後續 Task 3、5 讀它。

- [x] **Step 1：寫失敗測試**，加進上述測試檔的 `main()` 內：
  - `ImportResult 預設 skippedUnsupportedCount 為 0`：`const ImportResult().skippedUnsupportedCount == 0`。
  - `importFiles：不可辨識格式略過並計入 skippedUnsupportedCount，不計入 skippedDuplicateCount`：暫存目錄放 `a.epub`（複製 `test/fixtures/sample.epub`）、`cover.jpg`、`notes.zip`（內容隨意位元組），呼叫 `service.importFiles([...三個路徑])`；斷言 `importedBooks.length == 1`、`skippedUnsupportedCount == 2`、`skippedDuplicateCount == 0`。
- [x] **Step 2：執行確認失敗**：`flutter test test/library/book_import_service_missing_channel_test.dart`；預期編譯失敗（`skippedUnsupportedCount` 未定義）。
- [x] **Step 3：實作。** `ImportResult` 加欄位與建構子參數 `this.skippedUnsupportedCount = 0`，並在類別文件註解說明語意（格式無法辨識而略過的檔案數，與重複分開）。`importFiles` 迴圈開頭先算 `displayName`，緊接著 `if (_detectImportFormat(uri, displayName) == null) { skippedUnsupportedCount++; continue; }`，必須在 `seenUris.add(uri)` 之前；`importFolder` 迴圈開頭同樣判斷（`displayName` 傳 `null`，與原本 `_importSingleFile` 內部判斷一致）；兩處回傳的 `ImportResult` 都帶入新計數。
- [x] **Step 4：執行確認通過**：同 Step 2 指令，預期全綠；再跑 `flutter test test/library/book_import_service_test.dart` 確認既有測試沒壞。
- [x] **Step 5：Commit**：`git add app/lib/library/book_import_service.dart app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_missing_channel_test.dart`，訊息 `feat(import): ImportResult 新增 skippedUnsupportedCount 並統計（epic-66 Issue 5 Task 1）`。

---

### Task 2：`importFolder` 支援本機資料夾路徑（`dart:io`）

**Files：**
- Modify: `app/lib/library/book_import_service_impl.dart`（`importFolder` 開頭；新增私有 `_listLocalFolder`）
- Test: `app/test/library/book_import_service_missing_channel_test.dart`

**Interfaces：**
- Consumes: Task 1 的 `skippedUnsupportedCount`。
- Produces: `importFolder(String folderUri, {bool autoGroupByFolderName})` 收到**不以 `content://` 開頭**的路徑時，視為本機資料夾；簽章不變。

- [x] **Step 1：寫失敗測試**（同檔，暫存目錄 `tempDir` 下建立 `書庫/` 資料夾）：
  - `本機資料夾：只匯入第一層，子資料夾內的書不匯入，書歸入以資料夾名命名的分類`：`書庫/` 內放 `甲.epub`（複製 sample.epub）、`desktop.ini`，`書庫/sub/乙.epub`；`importFolder(書庫路徑)`；斷言 `importedBooks.length == 1`、`importedBooks.single.groupName == '書庫'`、`skippedUnsupportedCount == 1`（`desktop.ini`）、`failure == null`。
  - `本機資料夾：autoGroupByFolderName 為 false 時書歸入未分類`：斷言 `groupName == BookGroup.uncategorized`。
  - `本機資料夾：不存在的路徑回傳 folderListingFailed`：斷言 `failure == ImportFailure.folderListingFailed` 且 `importedBooks` 為空。
  - 這些測試刻意不註冊任何 channel mock：若實作誤呼叫 `persistReadAccess` 或原生 `listFolderContents`，會因 `MissingPluginException` 失敗，藉此證明本機分支不碰原生 channel。
- [x] **Step 2：執行確認失敗**：`flutter test test/library/book_import_service_missing_channel_test.dart`；預期新測試失敗（`MissingPluginException`，或回傳 `folderAccessDenied`）。
- [x] **Step 3：實作。** `importFolder` 開頭依 `folderUri.startsWith('content://')` 分流：`content://` 維持現有的 `persistReadAccess`＋原生 `listFolderContents` 流程，逐字不動；其他走本機分支，以 `Future<({String folderName, List<String> fileUris})?> _listLocalFolder(String path)` 取得列表（`Directory(path).list(followLinks: false)` 只取 `File`、不遞迴，路徑依檔名排序，`folderName` 用 `p.basename(path)`；目錄不存在或 `FileSystemException` 回 `null`）。回 `null` 時直接 `return const ImportResult(importedBooks: [], failure: ImportFailure.folderListingFailed)`。之後的分類建立、去重、逐檔匯入沿用現有迴圈（本機分支匯入單檔仍傳 `takePermission: false`）。
- [x] **Step 4：執行確認通過**：同 Step 2 指令；再跑 `flutter test test/library/book_import_service_test.dart`，確認既有 `content://` 資料夾測試全綠。
- [x] **Step 5：Commit**：`git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_missing_channel_test.dart`，訊息 `feat(import): importFolder 支援本機資料夾路徑（epic-66 Issue 5 Task 2）`。

---

### Task 3：結果提示說明「略過不支援」與新字串

**Files：**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`（在 `libraryImportResultSkippedOnlyMessage` 之後新增鍵）
- Modify（重新產生）: `app/lib/l10n/app_localizations*.dart`（執行 `flutter gen-l10n`）
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`（`showImportResultSnackBar`）
- Test: `app/test/screens/support/book_import_picker_helper_test.dart`

**Interfaces：**
- Consumes: Task 1 的 `skippedUnsupportedCount`。
- Produces: `AppLocalizations.libraryImportResultUnsupportedMessage(int count)`，文字（四個 arb 一律用 ICU plural，對齊既有 `librarySelectedCount`、`libraryGroupTileCount` 的寫法）：zh_TW `{count, plural, =1{略過 1 個不支援的檔案} other{略過 {count} 個不支援的檔案}}`、zh_CN／zh `{count, plural, =1{略过 1 个不支持的文件} other{略过 {count} 个不支持的文件}}`、en `{count, plural, =1{1 unsupported file skipped} other{{count} unsupported files skipped}}`；`zh_TW` 範本需附 `@` 描述與 `count` 的 `int` placeholder，其餘三檔比照相鄰鍵的寫法。

- [x] **Step 1：寫失敗測試**（沿用該檔既有以 `Locale('zh','TW')` 與 `AppLocalizations.localizationsDelegates` 建構 `MaterialApp` 並點按鈕觸發 `showImportResultSnackBar` 的寫法）：
  - `只有略過不支援時，提示只顯示不支援那一行`：`ImportResult(skippedUnsupportedCount: 2)`；斷言 `find.text(l10n.libraryImportResultUnsupportedMessage(2))` 存在。
  - `匯入、重複與不支援並存時，兩段訊息以換行合併在同一個 SnackBar`：`importedBooks` 1 本、`skippedDuplicateCount: 1`、`skippedUnsupportedCount: 3`；斷言 SnackBar 的 `Text.data` 等於 `'${既有 Both 訊息}\n${不支援訊息}'`。
  - `三個計數皆為 0 時不顯示 SnackBar`（既有行為，補一條防回歸）。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/support/book_import_picker_helper_test.dart`；預期編譯失敗（新鍵未產生）。
- [x] **Step 3：實作。** 四個 arb 加鍵 `libraryImportResultUnsupportedMessage`；執行 `flutter gen-l10n`。`showImportResultSnackBar`：`failure != null` 分支不動；提早 `return` 的條件改為三個計數都 `<= 0`；組出原本的 `base` 訊息（可能為空），不支援訊息存在時以 `'\n'` 與之合併，只有一段時就只顯示該段。
- [x] **Step 4：執行確認通過**：同 Step 2 指令，並跑 `node tool/check_l10n_hardcoded_strings.js`，預期 PASS。
- [x] **Step 5：Commit**：`git add` 四個 arb、`app/lib/l10n/app_localizations*.dart`（僅限有變更者）、`book_import_picker_helper.dart` 與其測試，訊息 `feat(import): 結果提示說明略過不支援的檔案（epic-66 Issue 5 Task 3）`。

---

### Task 4：選資料夾的動作可注入，Windows 用 `FilePicker.getDirectoryPath()`

**Files：**
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`（`pickAndImportFolder`）
- Test: `app/test/screens/support/book_import_picker_helper_test.dart`

**Interfaces：**
- Produces: `typedef FolderPathPicker = Future<String?> Function();`；`Future<ImportResult?> pickAndImportFolder(BookImportService importService, {required Future<bool?> Function() confirmAutoGroup, FolderPathPicker? pickFolderPath})`。`pickFolderPath` 為 `null` 時用預設：`isWindowsPlatform` 為真走 `FilePicker.getDirectoryPath()`，否則走既有的 `_folderPickerChannel.invokeMethod<String>('pickFolder')`。

- [x] **Step 1：寫失敗測試**（`FakeBookImportService` 已記錄 `lastImportFolderUri`、`lastAutoGroupByFolderName`）：
  - `注入的 pickFolderPath 回傳路徑時，原樣傳給 importFolder，並帶入確認框的選擇`：`pickFolderPath: () async => r'C:\書庫'`、`confirmAutoGroup` 回 `false`；斷言 `lastImportFolderUri == r'C:\書庫'`、`lastAutoGroupByFolderName == false`。
  - `pickFolderPath 回傳 null 時整體回 null，且不問確認框、不呼叫 importFolder`。
  - 既有以 `elinkbook/folder_picker` channel mock 的測試不改、仍通過（證明預設路徑在非 Windows 不變）。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/support/book_import_picker_helper_test.dart`；預期編譯失敗（沒有 `pickFolderPath` 參數）。
- [x] **Step 3：實作。** 新增 typedef 與 `pickAndImportFolder` 的選用參數；把原本直接呼叫 channel 的那一行改為 `await (pickFolderPath ?? _defaultPickFolderPath)()`，其中 `Future<String?> _defaultPickFolderPath()` 依 `isWindowsPlatform`（`../../platform/platform_support.dart`）分流。外層既有的 `catch (_) { return null; }` 維持不動。
- [x] **Step 4：執行確認通過**：同 Step 2 指令；再跑 `flutter test test/screens/sources_home_screen_test.dart` 確認來源畫面既有測試沒壞。
- [x] **Step 5：Commit**：`git add app/lib/screens/support/book_import_picker_helper.dart app/test/screens/support/book_import_picker_helper_test.dart`，訊息 `feat(import): 選資料夾動作可注入，Windows 用 getDirectoryPath（epic-66 Issue 5 Task 4）`。

---

### Task 5：拖入路徑的匯入邏輯 `importDroppedPaths`

**Files：**
- Create: `app/lib/screens/support/dropped_import.dart`
- Modify: `app/test/support/fake_book_import_service.dart`（新增 `final List<String> importFolderCalls = [];`，每次 `importFolder` 呼叫都 `add(folderUri)`；既有欄位保留）
- Test: `app/test/screens/support/dropped_import_test.dart`

**Interfaces：**
- Consumes: Task 1 的 `ImportResult` 欄位；既有 `BookImportService.importFiles`／`importFolder`。
- Produces:
  - `typedef DroppedPaths = ({List<String> files, List<String> folders});`
  - `DroppedPaths classifyDroppedPaths(List<String> paths)`：以 `FileSystemEntity.isDirectorySync` 分出資料夾，其餘（含不存在的路徑）視為檔案；完全相同的路徑只保留第一個，保持原順序。
  - `Future<ImportResult?> importDroppedPaths(BookImportService importService, List<String> paths, {required Future<bool?> Function() confirmAutoGroup})`：沒有資料夾時不呼叫 `confirmAutoGroup`；有資料夾時整批只呼叫一次，回 `null` 代表取消、整批不匯入並回 `null`；檔案一次 `importFiles(files, displayNames: 各檔 p.basename)`；每個資料夾各呼叫一次 `importFolder(path, autoGroupByFolderName: 確認框結果)`；結果合併（`importedBooks`、`updateCandidates` 串接；`skippedDuplicateCount`、`skippedUnsupportedCount` 相加）；`failure` 規則見「我的決定」第 2 點。

- [x] **Step 1：寫失敗測試**（暫存目錄建真實檔案與資料夾；`FakeBookImportService` 設定各自的 `importFilesResult`／`importFolderResult`）：
  - `classifyDroppedPaths`：混合路徑正確分成 `files`／`folders`；重複路徑只留一個；不存在的路徑歸入 `files`；順序不變。
  - `只有檔案：不呼叫 confirmAutoGroup，importFiles 收到全部檔案與對應的 basename 作為 displayNames`；含中文與空白的檔名 `我的 書.epub` 原樣傳遞。
  - `只有資料夾：呼叫 confirmAutoGroup 一次，importFolder 帶入確認框的選擇`。
  - `多個資料夾：confirmAutoGroup 只呼叫一次，兩個資料夾都以同一個選擇匯入`（用 `importFolderCalls` 斷言順序與數量）。
  - `混合：檔案與資料夾都匯入，結果合併`：兩邊各給不同的 `importedBooks`、`skippedDuplicateCount`、`skippedUnsupportedCount`，斷言合併後相加與串接。
  - `confirmAutoGroup 回 null：回傳 null，importFiles 與 importFolder 都沒被呼叫`。
  - `failure 規則`：沒有檔案且所有資料夾都 `failure` → 合併結果帶 `failure`；有檔案或有任一資料夾成功 → `failure` 為 `null`。
  - `paths 為空：回傳 null 且不呼叫任何匯入`。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/support/dropped_import_test.dart`；預期編譯失敗（檔案不存在）。
- [x] **Step 3：實作 `dropped_import.dart`**，簽章如上；`ImportResult` 合併用私有 `_mergeResults`。
- [x] **Step 4：執行確認通過**：同 Step 2 指令。
- [x] **Step 5：Commit**：`git add app/lib/screens/support/dropped_import.dart app/test/support/fake_book_import_service.dart app/test/screens/support/dropped_import_test.dart`，訊息 `feat(import): 拖入路徑的匯入邏輯 importDroppedPaths（epic-66 Issue 5 Task 5）`。

---

### Task 6：`ImportDropTarget` widget 與 `desktop_drop` 依賴

**Files：**
- Modify: `app/pubspec.yaml`（加 `desktop_drop: 0.8.4`，註解說明為何固定：0.9.x 要求 Flutter ≥ 3.47.7，升級見 Issue 6）、`app/pubspec.lock`（**只留 `desktop_drop` 與其新增傳遞相依的異動**，見 Global Constraints）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`、`app_localizations*.dart`（`flutter gen-l10n`）
- Create: `app/lib/screens/support/import_drop_target.dart`
- Test: `app/test/screens/support/import_drop_target_test.dart`

**Interfaces：**
- Consumes: Task 3 的 `showImportResultSnackBar`；Task 5 的 `importDroppedPaths`；既有 `confirmAutoGroupByFolderName(BuildContext)`、`handleImportUpdateCandidates(context, importService, result, isEinkMode:)`、`discardUpdateCandidates(importService, candidates)`。
- Produces: `class ImportDropTarget extends StatefulWidget`，建構子 `ImportDropTarget({super.key, required BookImportService importService, required bool isEinkMode, required bool enabled, VoidCallback? onImportCompleted, required Widget child})`。`onImportCompleted` 在整條匯入流程（含更新候選處理）結束後呼叫，且只在「有新書匯入或有更新候選」時呼叫，供書架重新載入書單（審查 C-1：書架分頁本來就在畫面上，不會經過 `_navigateTo(0)`，不通知的話拖入的新書不會出現）。新字串 `importDropOverlayText`（zh_TW `放開以匯入`）、`importDropBusyMessage`（zh_TW `匯入進行中，請稍後再拖入`），四個 arb 各補對應語系。固定 Key：`Key('import_drop_overlay')`。

行為（widget 內）：非 Windows（`isWindowsPlatform` 為假）直接 `return child`；Windows 永遠 `DropTarget(enable: widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true), ...)` 包 `Stack(child, 遮罩)`，結構不隨狀態改變。遮罩只在拖曳經過（`onDragEntered`→顯示、`onDragExited`／`onDragDone`→隱藏）時出現，用 `IgnorePointer` 避免擋住點擊；**`_busy` 為真時 `onDragEntered` 不顯示遮罩**（不先邀請再拒絕，審查 I-3），使用者仍放開時由 `onDragDone` 顯示忙碌提示。`onDragDone`：`files` 為空→忽略；匯入進行中（`_busy`）→顯示 `importDropBusyMessage` 的 SnackBar 並返回；否則設 `_busy = true`，呼叫 `importDroppedPaths(widget.importService, 路徑清單, confirmAutoGroup: () => context.mounted ? confirmAutoGroupByFolderName(context) : Future.value(null))`，結果為 `null` 就結束；`!mounted` 時 `discardUpdateCandidates` 後返回；否則 `showImportResultSnackBar` 再 `handleImportUpdateCandidates`，最後若 `result.importedBooks` 或 `result.updateCandidates` 非空且仍 `mounted`，呼叫 `widget.onImportCompleted?.call()`；`finally` 還原 `_busy`（先檢查 `mounted`）。

- [x] **Step 1：寫失敗測試**（`debugDefaultTargetPlatformOverride = TargetPlatform.windows`，`addTearDown` 還原；`MaterialApp` 帶 zh_TW locale 與 `AppLocalizations` delegates；`FakeBookImportService`；用 `tester.widget<DropTarget>(find.byType(DropTarget))` 取出並直接呼叫 `onDragEntered`／`onDragExited`／`onDragDone`，事件物件以必要的 `Offset.zero` 位置建構，`DropDoneDetails.files` 用 `DropItemFile(路徑)`。**型別已查證**：0.8.4 的 `DropDoneDetails.files` 是 `List<DropItem>`（`desktop_drop-0.8.4/lib/src/drop_target.dart:17`），`DropItemFile` 由套件匯出；不可改用 `XFile`，`List<XFile>` 不能指派給 `List<DropItem>`，無法編譯）：
  - `非 Windows 不掛載 DropTarget`：預設平台（Android）下 `find.byType(DropTarget)` 找不到、child 正常顯示。
  - `enabled 為 false 時 DropTarget.enable 為 false`。
  - `拖曳經過顯示遮罩，離開後消失`：斷言 `Key('import_drop_overlay')` 與 `importDropOverlayText`。
  - `拖入書檔：呼叫 importFiles 並顯示匯入結果提示`。
  - `匯入進行中再拖入：不再呼叫 importFiles，顯示 importDropBusyMessage`：用 `FakeBookImportService.pendingCompleter` 卡住第一次匯入。
  - `匯入進行中拖曳經過：不顯示遮罩`：`pendingCompleter` 卡住第一次匯入，再觸發 `onDragEntered`，斷言 `Key('import_drop_overlay')` 不存在；此時 `onDragDone` 仍顯示 `importDropBusyMessage`。
  - `匯入有新書時呼叫 onImportCompleted；沒有新書與更新候選時不呼叫；匯入失敗（failure）時不呼叫`。
  - `拖入的 files 為空：不呼叫任何匯入、不顯示任何 SnackBar`。
  - `拖入資料夾：跳出確認框，按確認後呼叫 importFolder`（點 `Key('library_import_folder_confirm')`）；`按取消：importFolder 沒被呼叫`。
  - `匯入未完成時卸載 widget：不丟例外`（Completer 完成前把 widget 樹換掉，再完成 Completer，斷言測試無未捕捉例外）。
  - `匯入結果含更新候選但已卸載：呼叫 discardUpdateCandidates`（以 `FakeBookImportService.discardedCandidates` 斷言，該欄位已存在）。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/support/import_drop_target_test.dart`；預期編譯失敗。
- [x] **Step 3：實作。** 先 `flutter pub add desktop_drop:0.8.4`（或手改 pubspec 後 `flutter pub get`），檢查 `git diff app/pubspec.lock` 並還原與 `desktop_drop` 無關的版本降級；四個 arb 補兩個新鍵、`flutter gen-l10n`；建立 `import_drop_target.dart`，行為如上。
- [x] **Step 4：執行確認通過**：同 Step 2 指令；`flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js` PASS。
- [x] **Step 5：Commit**：明確列出 `app/pubspec.yaml`、`app/pubspec.lock`、四個 arb、`app/lib/l10n/app_localizations*.dart`（僅限有變更者）、`import_drop_target.dart`、其測試，訊息 `feat(import): ImportDropTarget 與 desktop_drop 0.8.4（epic-66 Issue 5 Task 6）`。

---

### Task 7：把 `ImportDropTarget` 接進 `AdaptiveShellScaffold`

**Files：**
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`（`build` 內 `IndexedStack` 外層）
- Test: `app/test/screens/adaptive_shell_scaffold_test.dart`

**Interfaces：**
- Consumes: Task 6 的 `ImportDropTarget`（含 `onImportCompleted`）；既有 `_libraryRefreshSignal`（`LibraryScreen` 只在此訊號觸發時重載書單，目前只有 `_navigateTo(0)` 會觸發，見審查 C-1）。

- [x] **Step 1：寫失敗測試**（沿用該檔既有的建構方式；Windows 平台 override）：
  - `停在書架分頁拖入新書後，書單重新載入`：以該檔既有的 fake `LibraryRepository` 記錄 `listBooks` 呼叫次數（若沒有此記錄則在測試內包一層），觸發 `ImportDropTarget` 的 `onDragDone` 並讓 fake 匯入服務回傳有新書的結果，斷言匯入完成後 `listBooks` 次數增加，且全程沒有切換分頁。
  - `匯入沒有新書時不觸發書單重載`。
  - `Windows：書架分頁（index 0）DropTarget 啟用`、`切到來源分頁（index 1）仍啟用`、`切到設定分頁（index 2）停用`。
  - `Windows：切換分頁後書架畫面的 State 沒有被重建`（在 `LibraryScreen` 內留一個可辨識的狀態，例如既有可操作的 Key，切到設定再切回，狀態仍在；若該檔已有同類保持狀態的測試，補一條 Windows 版）。
  - `非 Windows：find.byType(DropTarget) 找不到`。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/adaptive_shell_scaffold_test.dart`。
- [x] **Step 3：實作。** 用 `ImportDropTarget(importService: widget.readerFeatures.bookImportService, isEinkMode: widget.appearance.isEinkMode, enabled: _currentIndex != 2, onImportCompleted: () => _libraryRefreshSignal.notifyListeners(), child: IndexedStack(...))` 包住原本的 `IndexedStack`，其他不動。
- [x] **Step 4：執行確認通過**：同 Step 2 指令。
- [x] **Step 5：Commit**：`git add app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/adaptive_shell_scaffold_test.dart`，訊息 `feat(import): 書架與來源分頁接受拖曳匯入（epic-66 Issue 5 Task 7）`。

---

### Task 8：「來源」畫面常駐說明文字（書檔維持原位置）

**Files：**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`、`app_localizations*.dart`
- Modify: `app/lib/screens/sources_home_screen.dart`（緊接在 `sources_pick_folder_button` 那張 `EBFieldCard` 之後）
- Test: `app/test/screens/sources_home_screen_test.dart`

**Interfaces：**
- Produces: 字串 `sourcesHomeLocalFilesStayInPlaceHint`——zh_TW `書籍會保留在原本的檔案位置，不會複製。若移動或刪除原檔，該書將無法開啟。`；zh_CN 與 zh `书籍会保留在原来的文件位置，不会复制。若移动或删除原文件，该书将无法打开。`；en `Books stay where they are and are not copied. If you move or delete the original file, the book can no longer be opened.`。固定 Key：`Key('sources_windows_keep_in_place_hint')`。

- [x] **Step 1：寫失敗測試**：`Windows 顯示提醒文字（Key 與 l10n 文字都存在）`；`預設平台（Android）不顯示`。
- [x] **Step 2：執行確認失敗**：`flutter test test/screens/sources_home_screen_test.dart`。
- [x] **Step 3：實作。** 四個 arb 加鍵、`flutter gen-l10n`；畫面在 `isWindowsPlatform` 為真時，於選資料夾卡片後插入 `Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(l10n.sourcesHomeLocalFilesStayInPlaceHint, key: ..., style: Theme.of(context).textTheme.bodySmall))`。
- [x] **Step 4：執行確認通過**：同 Step 2 指令；`node tool/check_l10n_hardcoded_strings.js` PASS。
- [x] **Step 5：Commit**：`git add` 四個 arb、`app/lib/l10n/app_localizations*.dart`（僅限有變更者）、`sources_home_screen.dart` 與其測試，訊息 `feat(import): 來源畫面提醒書檔維持原位置（epic-66 Issue 5 Task 8）`。

---

### Task 9：收尾——文件、全套測試、人工驗證清單

**Files：**
- Modify: `CONTEXT.md`（「拖曳匯入」詞條補一條：Windows 匯入書檔不複製，`Book.filePath` 維持原路徑，「來源」畫面常駐提醒；搬動或刪除原檔後走既有「重新連結」流程）
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 5 狀態改為「🟡 實作完成，待 Windows 人工驗證」）
- Create: `docs/epics/epic-66-windows-port/issue-5-report.md`（報告骨架：做了什麼、自動化測試結果、`issues.md` 過關條件 1 到 9 的**人工驗證表**，每項結果欄先留「待驗證」，**不得預先勾選**；以及已知限制）

- [x] **Step 1：** 更新上述三份文件。人工驗證表必須明確標示：條件 1 到 9 全部「尚未在 Windows 實機驗證」，驗證前不得宣稱通過。
- [x] **Step 2：全套測試**：`flutter test`（`run_in_background`），預期 `All tests passed!`；記錄測試總數與 commit。
- [x] **Step 3：靜態檢查**：`flutter analyze`（`No issues found!`）、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（皆 PASS）。
- [x] **Step 4：確認 `git diff origin/main -- app/pubspec.lock`** 只含 `desktop_drop` 與其傳遞相依的異動。
- [x] **Step 5：Commit**：`git add CONTEXT.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/issue-5-report.md`，訊息 `docs(epic-66): Issue 5 收尾文件與人工驗證清單`。推送與開 PR 前先請使用者確認，並請使用者在 Windows 實機完成人工驗證表。
