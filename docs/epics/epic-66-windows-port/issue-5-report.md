# Epic 66 Issue 5 驗證報告：Windows 檔案與資料夾匯入

## 1. 摘要（做了什麼）

本 Issue 實作 Windows 桌面版的檔案選擇、資料夾選擇與視窗拖曳三種書籍匯入入口，三者皆進入同一條 `BookImportService` 匯入管線，且書檔保留於原路徑不複製：

1. **不支援格式統計與提示（Task 1、Task 3）：**
   - `ImportResult` 新增 `skippedUnsupportedCount`（預設 `0`）。
   - `BookImportServiceImpl.importFiles` 與 `importFolder` 於去重與開檔前先以 `detectImportFileFormat`（經 `_detectImportFormat`）檢查格式；無法辨識者直接略過並計入 `skippedUnsupportedCount`，不計入 `skippedDuplicateCount`。
   - `showImportResultSnackBar` 新增 `libraryImportResultUnsupportedMessage`（ICU plural），以換行與既有匯入／重複提示合併顯示（跨平台生效）。
2. **本機資料夾匯入（Task 2、Task 4）：**
   - `BookImportServiceImpl.importFolder` 對非 `content://` 開頭的本機資料夾路徑改由 `dart:io` 的 非同步的 `Directory.list(followLinks: false)` 列舉第一層檔案（只收 `File`，依檔名字碼順序排序，大小寫混合時 `B` 在 `a` 之前），不呼叫 Android 專屬的 `persistReadAccess` 與 `listFolderContents` 原生 channel；目錄不存在或讀取拋出 `FileSystemException` 時回傳 `ImportFailure.folderListingFailed`。`content://` 分支逐字不變。
   - `pickAndImportFolder` 新增可注入的 `pickFolderPath` 參數，預設在 Windows 呼叫 `FilePicker.getDirectoryPath()`，其他平台維持既有 `elinkbook/folder_picker` method channel。
3. **拖曳匯入純邏輯與元件（Task 5、Task 6、Task 7）：**
   - 新增 `app/lib/screens/support/dropped_import.dart`（`DroppedPaths`、`classifyDroppedPaths`、`importDroppedPaths`）：同次拖入路徑先去重並分為檔案與資料夾；含資料夾時整批只詢問一次「是否依資料夾名稱自動建立分類」，取消則整批（含同次拖入單檔）皆不匯入；結果合併為單一 `ImportResult`。
   - 新增依賴 `desktop_drop: 0.8.4`（固定版本），實作 `ImportDropTarget`（`app/lib/screens/support/import_drop_target.dart`）：非 Windows 直接回傳 `child`；Windows 恆包裹 `DropTarget` 並以 `enable` 控制開關（避免切換分頁時重建子樹 State），搭配 `ModalRoute.of(context)?.isCurrent ?? true` 確保疊上閱讀器或對話框時自動停用；拖曳經過顯示 `Key('import_drop_overlay')` 遮罩；匯入進行中再拖入時忽略並提示 `importDropBusyMessage`；匯入完成後若含新增書籍則觸發 `onImportCompleted` 重新載入書架，並沿用既有「疑似更新版」確認流程（若畫面已卸載則自動呼叫 `discardUpdateCandidates` 清理暫存檔）。
   - `AdaptiveShellScaffold` 以 `ImportDropTarget` 包裹 `IndexedStack`（`enabled: _currentIndex != 2`，僅在「書架」與「來源」分頁啟用，「設定」分頁停用）。
4. **「來源」畫面常駐提醒文字（Task 8）：**
   - Windows 平台下於「來源」畫面「選擇資料夾」卡片下方常駐顯示 `Key('sources_windows_keep_in_place_hint')`（`sourcesHomeLocalFilesStayInPlaceHint`），提醒使用者書籍保留在原本檔案位置不會複製，若移動或刪除原檔將無法開啟；非 Windows 平台不顯示。

---

## 2. 自動化測試與靜態檢查結果

### 2.1 本 Issue 新增／更新之專項單元與 Widget 測試

| 測試檔案 | 涵蓋範圍 | 結果 |
|---|---|---|
| `test/library/book_import_service_missing_channel_test.dart` | `ImportResult.skippedUnsupportedCount`、`importFiles` 不支援格式統計、本機路徑 `importFolder`（只列第一層、自動分類、`desktop.ini` 略過、不存在目錄回 `folderListingFailed`、不觸發原生 channel） | ✅ 13/13 通過 |
| `test/library/book_import_service_test.dart` | 既有匯入與 `content://` 資料夾匯入回歸測試 | ✅ 84/84 通過 |
| `test/screens/support/book_import_picker_helper_test.dart` | `showImportResultSnackBar`（僅略過不支援、與匯入／重複並存、全為 0、失敗優先）與 `pickAndImportFolder` 注入 `pickFolderPath` | ✅ 40/40 通過 |
| `test/screens/support/dropped_import_test.dart` | `classifyDroppedPaths` 與 `importDroppedPaths`（純檔案、純資料夾、混合、多資料夾只問一次、取消整批不匯入、全失敗／部分失敗合併、中文與空白路徑） | ✅ 8/8 通過 |
| `test/screens/support/import_drop_target_test.dart` | `ImportDropTarget`（非 Windows 不掛載、`enabled: false`、疊路由停用、遮罩顯示／消失、忙碌中忽略並提示、`onImportCompleted` 觸發條件、空的 `files` 忽略、資料夾確認框、卸載防禦與 `discardUpdateCandidates`） | ✅ 12/12 通過 |
| `test/screens/adaptive_shell_scaffold_test.dart` | 書架／來源／設定分頁 `DropTarget.enable` 狀態、切換分頁保留子畫面 State、書架分頁拖入新書後觸發 `_libraryRefreshSignal` 重載書單 | ✅ 17/17 通過 |
| `test/screens/sources_home_screen_test.dart` | Windows 顯示 `sources_windows_keep_in_place_hint` 提醒文字，預設平台（Android）不顯示 | ✅ 22/22 通過 |
| `test/l10n/arb_consistency_test.dart` | 四個 arb（`app_zh_TW`、`app_zh`、`app_zh_CN`、`app_en`）鍵集合、placeholder 與 `zh == zh_TW` 一致性檢查 | ✅ 4/4 通過 |

### 2.2 全套單元測試與靜態分析

- **全套測試（`flutter test`）：**
  - 總測試數：**5,007 則測試**（`+5006 ~2`，本 Issue 相關之 199 則測試全數通過；全套高並發執行下僅既有 `test/downloads/download_queue_controller_test.dart:214` 因固定 `Future.delayed(50ms)` 等待磁碟 SHA-256 偶發超時，單獨執行該檔 28/28 全數通過）。
  - 測試對應 Commit：`01628d59`（Task 8 完成點）。
- **靜態分析與檢查腳本：**
  - `flutter analyze`：`No issues found!`
  - `node tool/check_l10n_hardcoded_strings.js`：`PASS`（掃描 325 個檔案、382 個測試檔、55 個 integration 測試檔）
  - `node tool/check_integration_keys.js`：`PASS`（掃描 55 個 integration 測試檔，所有 Key 在 `lib/` 都找得到對應）
  - `git diff origin/main -- app/pubspec.lock`：確認僅含 `desktop_drop`（`0.8.4`）與其傳遞相依 `universal_platform`（`1.1.0`）兩筆新增，無任何其他套件版本降級或異動。

---

## 3. Windows 實機人工驗證表（過關條件 1～9）

> ⚠️ **重要聲明：以下過關條件 1 到 9 全部「尚未在 Windows 實機驗證」，在人類於 Windows 實機逐項操作確認前，不得宣稱通過或預先勾選。**

| 編號 | 過關條件 | 操作步驟與預期結果 | 實機驗證結果 |
|---|---|---|---|
| 1 | **選檔（Windows）** | 在「來源」畫面點「選擇檔案」，用選檔對話框同時選多個 `.epub`／`.pdf`／`.txt`／`.cbz`／`.azw3`／`.md`；確認全部出現在書架，`Book.filePath` 為標準本機路徑（非 `file:///`），且點擊開書正常。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 2 | **選資料夾（Windows）** | 在「來源」畫面點「選擇資料夾」，選一個含書與非書檔案、且含子資料夾（內有書）的資料夾；確認先跳出「依資料夾名稱自動分類」確認框；匯入後只含該資料夾第一層的書，子資料夾內的書不匯入；選「建立分類」時書歸入以資料夾名命名的分類。若資料夾無法讀取，提示資料夾匯入失敗而不崩潰。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 3 | **拖曳檔案** | 從 Windows 檔案總管把多個書檔分別拖進「書架」與「來源」畫面，確認都能匯入；停在「書架」畫面直接拖入時，新書立即出現在書單（不需切換分頁）；拖進「設定」畫面、閱讀器畫面、或任何開啟的對話框之上都不響應。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 4 | **拖曳資料夾** | 拖入單一資料夾時跳出自動分類確認框；同一次拖入多個資料夾時只跳一次確認框，選擇套用到全部，每個資料夾各自成為一個分類；同時混合拖入單檔與資料夾時，單檔不歸入資料夾分類；在確認框按取消則整批（含同次拖入的單檔）都不匯入。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 5 | **不支援的格式** | 拖入或選取含 `.jpg`、`.zip`、`desktop.ini` 等非書檔的組合；確認非書檔一律略過、不產生書籍、不報錯；匯入結束後的 SnackBar 另起一行顯示「略過 N 個不支援的檔案」，且與「略過重複」分開顯示。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 6 | **匯入中再拖入** | 先拖入或匯入一批較大的書檔，在匯入尚未完成期間再次拖入檔案；確認第二次拖入被忽略，且畫面顯示「匯入進行中，請稍後再拖入」，不重複匯入、不崩潰。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 7 | **視覺回饋** | 從檔案總管拖曳檔案經過視窗（在書架或來源畫面）時，顯示半透明遮罩與「放開以匯入」提示；游標離開視窗或放開滑鼠後遮罩立即消失。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 8 | **疑似更新版與重複** | 拖入圖書庫既有書籍的更新版檔案或完全相同的檔案，確認行為與「選擇檔案」匯入一致（跳出疑似更新版確認清單，或計入略過重複提示）。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |
| 9 | **提醒文字** | 在 Windows 開啟「來源」畫面，確認「選擇資料夾」卡片下方常駐顯示「書籍會保留在原本的檔案位置，不會複製。若移動或刪除原檔，該書將無法開啟。」說明文字。 | 通過（使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節）） |

---

## 4. 已知限制

1. **只匯入資料夾第一層：** 資料夾匯入（無論選資料夾或拖曳資料夾）皆不遞迴掃描子資料夾，也不跟隨符號連結（`followLinks: false`），與 Android 端行為一致。
2. **匯入期間不排隊、無進度條與中途取消：** 匯入進行中再次拖入會直接忽略並提示稍後再試；批次匯入進度條與取消機制不在本 Issue 範圍內。
3. **書檔保留原路徑不複製：** Windows 端匯入後若使用者於檔案總管搬移、改名或刪除原書檔（TXT／MD 除外，因其匯入時已合成為本機 EPUB3），開書時將無法讀取原檔，需走既有「重新連結」流程。
4. **`desktop_drop` 版本釘定於 `0.8.4`：** 因專案目前固定於 Flutter 3.41.9，而 `desktop_drop` 0.9.x 要求 Flutter ≥ 3.47.7，故鎖定 `0.8.4`；待後續 Issue 6 升級 Flutter 時再一併評估升級。
