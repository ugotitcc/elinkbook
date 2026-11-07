# Issue 6：Flutter 升級至 3.47.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把專案正式採用的 Flutter 從 3.41.9 改為 3.47.9：升級共用 SDK、處理棄用 API、讓 Windows 建置不需要手動設 `CL=/utf-8`、把 `desktop_drop` 升到 0.9.2（含 API 破壞性改寫與 Windows 實機拖曳確認），並驗證 Android 與 Windows 都能建置、全套測試乾淨。

**Architecture:** 這台機器的 `C:\tools\flutter` 其實從 2026-10-23 起就是 3.47.4，近期所有工作都在 3.47.4 上通過；`CLAUDE.md` 的 3.41.9 與另一份 `C:\src\flutter-3.41.9` 是過時的政策。所以：（1）先把共用 SDK 升到含安全公告修補的 3.47.9（`desktop_drop` 0.9.x 要求 Dart ≥ 3.13.5，3.47.4 附的是 Dart 3.13.3，一定要先升）；（2）先單獨驗證 SDK 本身沒帶來回歸，再逐項改程式；（3）`desktop_drop` 的升級設關卡：解析不過就退回，不硬做；（4）把政策文件對齊現況。

**Tech Stack:** Flutter 3.47.9（Dart 3.13.7）、AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14、`desktop_drop` 0.9.2（依賴 `cross_file ^0.4.0`）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 6 範圍／過關條件／單元測試要求」；`epic.md` 決策 27。審查：`reviews/review-plan-issue-6.md`（不進版控）。

## 診斷與決策（2026-11-07，已實測，計畫的依據）

| 項目 | 事實 |
|---|---|
| 這台機器的預設 Flutter | `C:\tools\flutter` = 3.47.4（修改於 2026-10-23），分支 `stable`、追蹤 `origin/stable`；Git Bash 的 `~/bin/flutter` 只是轉呼叫它 |
| 共用這份 SDK 的 worktree | `.worktrees\epic-54-issue-16-integration-device`、本機其他 worktree（含 `C:\Users\huthief\.local\share\opencode\worktree\...`）、其他 Claude session |
| 另一份 SDK | `C:\src\flutter-3.41.9`（2026-11-06 建立，保留作回退參考，本 Issue 不刪） |
| 3.47.4 上的 `flutter analyze` | 全專案只有 2 個 info：`dictionary_settings_screen.dart:821` 的 `onReorder` 棄用、`local_book_handler_test.dart:65` 的 `use_null_aware_elements` |
| 3.47.4 上的 `flutter pub get --dry-run` | `No dependencies would change` |
| 3.47.4 上的全套 `flutter test` | 5118 個，0 失敗 |
| 3.47.4 上的 Windows 開書 | 12／12 成功（Issue 11 實驗，約 14～18 秒） |
| `flutter doctor` | Android toolchain（SDK 36.1.0）、Visual Studio Build Tools 17.14.44 ✓；已連接裝置只有 Windows、Chrome、Edge，**沒有 Android 裝置** |
| 3.47.8 | **含安全公告 GHSA-frr6-h895-5pxp**：Dart 執行環境的 BoringSSL 封鎖被入侵的 eMudhra 中繼 CA 憑證；Android 14+ 的 `dart:io` 改用可更新的 Conscrypt 根憑證庫。本專案有 HTTPS 連線（同步、雲端匯入、線上查詞） |
| 3.47.6 | 修正「Windows 正式版 App 會卡死」（flutter/192513） |
| 3.47.9 | 最新 stable（2026-10-29）；`origin/stable` 本地參照與標籤 `3.47.9` 同為 `c197ca5199e9`。引擎 hash 與 3.47.4 不同（`06a2e2a1…` → `89c39edf…`），升級會替換引擎與 Dart SDK（3.13.3 → 3.13.7） |
| `flutter upgrade` 的阻礙 | `C:\tools\flutter` 的 `git status -s` 有 119 行，**全是 untracked**，沒有 tracked 修改；`flutter upgrade` 對 stable 只要輸出非空就拒絕，需要 `--force`（內部是 `git reset --hard`，untracked 不受影響） |
| `desktop_drop` 0.9.x | **API 破壞性改寫**：要求 Flutter 3.47.7／Dart 3.13.5 並依賴 `cross_file ^0.4.0`；`onDragDone(DropDoneDetails)` → 必要的非同步 `onDrop(DropDetails)`；`files` → `items`（`DropFileItem`／`DropDirectoryItem`／`DropStringItem`，`localPath` 可為 null）；`enable` → `enabled`；`onDragEntered/Exited` → `onEnter/onMove/onLeave`；**provider 與暫存檔只在 `onDrop` 期間有效**。0.9.1 修 Windows 啟動崩潰。已在 3.47.4（Dart 3.13.3）上實測 `pub get` 解析失敗：`requires SDK version >=3.13.5`，所以必須先升 SDK |
| 用到 `desktop_drop` 的地方 | `lib/screens/support/import_drop_target.dart`（唯一的 lib 使用處）、測試 `test/screens/support/import_drop_target_test.dart`（約 15 個測試）、`test/screens/adaptive_shell_scaffold_test.dart`（約第 449、490、507～537 行） |
| 其他大跳版 | `pdfrx` 2.4.7→2.12.0、`file_picker` 11→13、`window_manager` 0.5.2→0.6.0 **本 Issue 不升**；`sqflite`、`url_launcher` 只差 patch，也不升 |
| `onReorder` | 全專案只有 `dictionary_settings_screen.dart:817` 一個 `ReorderableListView.builder`；`onReorderItem` 的 `newIndex` 已扣除移除項目位移；`onReorder` 在 3.47.x 仍存在但已棄用，兩者同時傳會觸發 assert。既有 3 個拖曳測試**全是「往前拖」**（`Offset(0, -400)`），沒有「往後拖」 |
| Android 建置設定 | AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14 都在 3.47.9 支援範圍內（上限 Gradle 9.3.1／AGP 9.2／KGP 2.4.0）；`gradle.properties` 已有 `android.builtInKotlin=false`；另有 `patches/flutter_inappwebview_android` 本機修補；**Android 尚未在 3.47.x 上建置過** |
| `/utf-8` 問題 | 失敗目標是外掛 `connectivity_plus`：`connectivity_plus_plugin.cpp` 含 UTF-8 em dash，本機字碼頁 950 觸發 C4819，被 `/WX` 升為錯誤。`add_compile_options` 是目錄屬性，要放在 `windows/CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前，才同時涵蓋 flutter、runner 與全部 plugin |

使用者決定（2026-11-07）：**直接升級共用的 `C:\tools\flutter`**（不並存安裝）；**審查後仍堅持升級 `desktop_drop`**（接受 API 重寫與實機拖曳確認）。

## Global Constraints

- 目標版本 3.47.9。回退點是目前的 `9584c6713b`（3.47.4）。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`；`pubspec.lock` 只收 `desktop_drop` 及其必要連動（`cross_file` 系列套件、`sdks:` 區塊的版本下限）；`git add` 一律明確列檔。
- 不新增、不修改任何 ARB 字串。
- `onReorder` 改 `onReorderItem` 後，拖曳排序的結果必須與現況完全相同，既有 3 個測試不改斷言。`desktop_drop` 的測試因 API 改變必須改寫，但**被測行為不變**（路徑傳給 `importFiles`、忙碌時提示、拖曳覆蓋層、啟用／停用）。
- 升級共用 SDK 前，確認沒有其他 `flutter`／`dart`／`flutter_tester` 程序在跑，且 epic-54 的 Android 真機驗證沒有進行中（它共用同一份 SDK，中途升級會讓結果混版本）。
- Windows 建置：PowerShell，`$env:Path += ';C:\Users\huthief\bin'`（放尾端；該資料夾有個 `flutter` 檔會蓋掉指令；用來找 `nuget.exe`）；新 worktree 第一次建置若曾在缺 `nuget.exe` 時失敗，先刪該 worktree 的 `app\build\windows` 再建。
- 實驗腳本與暫存輸出放 scratchpad，不放進專案。
- 沒有 Android 裝置：Android 只驗證到 `flutter build apk --debug` 成功；報告只能寫「建置成功」，不得寫「Android 已驗證」。

## Review Focus

1. 共用 SDK 升級後，其他專案或 session 的 `flutter` 命令是否仍可用；回退步驟要寫得出來、照得做。（Task 1）
2. SDK 升級本身是否帶來回歸：改任何程式前，先單獨跑 `pub get`、`analyze`、全套 `test`，與 3.47.4 基準比對。（Task 2）
3. `onReorderItem` 的 `newIndex` 語意與 `onReorder` 不同：**往後拖**（`newIndex > oldIndex` 的差 1）、拖到最後一格、原地放開，結果都要與現況一致。（Task 3）
4. `/utf-8` 修法必須讓「沒設 `CL`」的建置成功，且不影響設了 `CL` 的建置；兩次驗證之間都要重刪 `build\windows`。（Task 4）
5. `desktop_drop` 0.9.2：（a）能否解析（`cross_file` 與 `file_picker` 不衝突）；（b）匯入必須整段在 `onDrop` 回傳的 Future 內完成，否則暫存檔失效；（c）沒有本機路徑的項目（虛擬檔案、文字）不能讓 App 崩潰或誤匯入；（d）Windows 實機拖曳真的能匯入。（Task 5、7）
6. Android 建置警告：AGP 8.11.1／Kotlin 2.3.20 可能出現相容性警告；警告記錄但不是失敗，真正失敗才停下來。（Task 6）
7. 驗證只在 Windows debug 版、沒有 Android 真機：報告不得外推。（Task 6、7）

---

### Task 1：升級共用 SDK 到 3.47.9

**Files:**
- 無專案檔案異動；變動在 `C:\tools\flutter`（專案外的共用 SDK）。結果寫入 Task 7 的報告。

**Interfaces:**
- Produces: `flutter --version` 顯示 `Flutter 3.47.9`（Dart 3.13.7）；回退指令 `git -C C:\tools\flutter reset --hard 9584c6713b`（留在 `stable` 分支）加 `flutter --version`、`flutter doctor`。

- [ ] **Step 1: 升級前紀錄。** 確認沒有 `flutter`／`dart`／`flutter_tester` 程序在跑（`Get-Process`）、epic-54 真機驗證沒有進行中；記下 `flutter --version`、`git -C C:\tools\flutter rev-parse HEAD`（預期 `9584c6713b…`）、`git -C C:\tools\flutter branch --show-current`（預期 `stable`）、`git -C C:\tools\flutter status -s | Where-Object { $_ -notmatch '^\?\?' }`（預期空，代表沒有 tracked 修改）與 `flutter doctor` 輸出（存 scratchpad）。若有 tracked 修改，停下來回報，不要 `--force`。
- [ ] **Step 2: 升級。** 在 PowerShell 執行 `flutter upgrade --force`（只做 `git reset --hard <rev>`，untracked 檔案不受影響）。若失敗，備案是留在 `stable` 分支：`git -C C:\tools\flutter merge --ff-only 3.47.9`，再 `flutter --version` 讓工具下載對應引擎。**不要用 `git checkout` 到標籤**（會讓 HEAD 變 detached，之後 `flutter upgrade` 與 channel 顯示都會壞）。
- [ ] **Step 3: 驗證。** `flutter --version` 預期 `Flutter 3.47.9`、`Dart 3.13.7`、channel 仍是 `stable`；`flutter doctor` 與 Step 1 逐項比對，預期 Android、Windows、Visual Studio 仍是 ✓。
- [ ] **Step 4: 記錄回退（只寫不做）。** 報告寫：回退指令 `git -C C:\tools\flutter reset --hard 9584c6713b`，之後 `flutter --version`、`flutter doctor`；兩版引擎不同，**回退會重新下載引擎與 Dart SDK，需要網路**，舊引擎快取不保留。

---

### Task 2：只換 SDK、不改程式的回歸基準

**Files:**
- 無異動；結果寫入報告。

- [ ] **Step 1: 相依解析。** 在 `app/` 執行 `flutter pub get`，再 `git diff --stat -- pubspec.lock`，預期沒有變動；若有變動，逐行檢查，只保留與 Flutter 版本直接相關的（例如 `sdks:` 區塊），其餘 `git checkout -- app/pubspec.lock` 還原並在帳本記 ruling。
- [ ] **Step 2: 靜態分析。** `flutter analyze`，預期與 3.47.4 基準相同：只有 2 個 info。出現第 3 個以上就是 SDK 升級帶來的新警告，逐一記錄。
- [ ] **Step 3: 全套測試。** 在 `app/` 用 JSON reporter 跑 `flutter test`（比照 Issue 11：輸出存 scratchpad、列出失敗名稱），預期 5118 個、0 失敗。有失敗就單獨重跑；單獨也失敗的是回歸，停下來用 `superpowers:systematic-debugging` 查；只有全套才失敗的記為偶發並與 `pdf_reader_view_filters_test`（Issue 15）比對。

---

### Task 3：`onReorder` 改 `onReorderItem`

**Files:**
- Modify: `app/lib/screens/dictionary_settings_screen.dart`（`_onReorder` 約第 213 行；`ReorderableListView.builder` 約第 817～821 行）
- Test: `app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Produces: `Future<void> _onReorder(int oldIndex, int newIndex)` 簽章不變，但 `newIndex` 語意改為「已扣除移除項目位移」。

- [ ] **Step 1: 跑既有重排測試確認基準。** `flutter test test/screens/dictionary_settings_screen_test.dart`，預期全過（含 3 個拖曳排序測試）。
- [ ] **Step 2: 補三個「往後拖／原地」的測試（先在 `onReorder` 版本上跑綠）。** 沿用既有 `dictionary_drag_handle_<id>` Key 與 `manager.reorderCalls`，往下拖用正的 `Offset`。清單為 a、b、c 三項：`往後拖曳（第一個拖到最後一格）後 reorder 傳入 [b, c, a]`；`往後拖曳一格後 reorder 傳入 [b, a, c]`（這個能分辨少減或多減 1）；`原地放開（位移很小）不呼叫 reorder`。三個測試在目前的 `onReorder` 實作上必須先通過，確保測試本身正確。
- [ ] **Step 3: 實作。** `onReorder: _onReorder` 改為 `onReorderItem: _onReorder`；`_onReorder` 內刪除 `if (newIndex > oldIndex) newIndex -= 1;` 與其註解，改一行中文註解說明 `onReorderItem` 的 `newIndex` 已扣除位移。其餘邏輯不動。
- [ ] **Step 4: 執行確認。** 同 Step 1 指令，預期全過（既有 3 個加新增 3 個）；若往後拖的測試失敗，代表位移處理錯了，修實作不要改測試。`flutter analyze lib/screens/dictionary_settings_screen.dart` 預期 `No issues found!`。
- [ ] **Step 5: Commit。**

```bash
git add app/lib/screens/dictionary_settings_screen.dart app/test/screens/dictionary_settings_screen_test.dart
git commit -m "refactor: 詞典排序改用 onReorderItem（epic-66 Issue 6 Task 3）"
```

---

### Task 4：Windows 建置不再需要 `CL=/utf-8`

**Files:**
- Modify: `app/windows/CMakeLists.txt`（`add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前，為 MSVC 加 `/utf-8`）

**Interfaces:**
- Produces: 沒有 `CL` 環境變數時 `flutter build windows --debug` 成功。

- [ ] **Step 1: 重現失敗（紅）。** PowerShell 確認 `$env:CL` 為空，刪該 worktree 的 `app\build\windows`，執行 `flutter build windows --debug`。預期失敗，錯誤為 `connectivity_plus_plugin.cpp` 的 C4819（字碼頁 950 無法表示 UTF-8 的 em dash），被 `/WX` 升為錯誤；把前 20 行錯誤存 scratchpad。若**成功**，代表問題已不存在：停止本 Task，報告記「`/utf-8` 問題在 3.47.9 已不需處理」。
- [ ] **Step 2: 實作。** 在 `windows/CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前加 `if(MSVC) add_compile_options(/utf-8) endif()`，附中文註解：放在頂層目錄層級才會讓之後引入的 flutter、runner 與全部 plugin 都繼承；繁中 Windows 字碼頁 950 會讓含 UTF-8 的 plugin 原始碼被 `/WX` 擋下（見 epic.md 決策 27）。不要碰 `generated_plugins.cmake`。
- [ ] **Step 3: 驗證（綠）。** `$env:CL` 仍為空、**重刪 `build\windows`** 後重建，預期 `Built build\windows\x64\runner\Debug\elinkbook.exe`。再設 `$env:CL='/utf-8'`、**再次重刪 `build\windows`** 重建一次，預期仍成功（不衝突）；不刪的話不會重新編譯，驗證無意義。
- [ ] **Step 4: Commit。**

```bash
git add app/windows/CMakeLists.txt
git commit -m "build(windows): CMake 加 /utf-8，免手動設 CL 環境變數（epic-66 Issue 6 Task 4）"
```

---

### Task 5：`desktop_drop` 升到 0.9.2（API 改寫）

**Files:**
- Modify: `app/pubspec.yaml`（`desktop_drop: 0.8.4` → `0.9.2`，維持固定版本、不用 `^`）、`app/pubspec.lock`（見 Global Constraints）
- Modify: `app/lib/screens/support/import_drop_target.dart`
- Test: `app/test/screens/support/import_drop_target_test.dart`、`app/test/screens/adaptive_shell_scaffold_test.dart`（約第 449、490、507～537 行）

**Interfaces:**
- Consumes: `desktop_drop` 0.9.2 的 `DropTarget({required child, required OnDropCallback onDrop, bool enabled = true, OnDragCallback? onEnter, OnDragCallback? onMove, VoidCallback? onLeave, ...})`；`OnDropCallback = FutureOr<void> Function(DropDetails)`；`DropDetails({required items, localPosition, globalPosition, operation})`；`DragDetails({required items, localPosition, globalPosition})`；`DropFileItem.fromPath(String path)`；`DropDirectoryItem({required directory, required name, localPath})`；`DropStringItem({required mimeType, required value})`。
- Produces: `ImportDropTarget` 對外建構參數不變（`importService`、`isEinkMode`、`enabled`、`onImportCompleted`、`child`）。

- [ ] **Step 1（關卡）: 解析。** 只在 Task 1 完成（Dart 3.13.7）後做。改 `pubspec.yaml`，`flutter pub get`。**若解析失敗**（最可能是 `cross_file ^0.4.0` 與 `file_picker` 等套件的 `cross_file` 範圍衝突）：`git checkout -- app/pubspec.yaml app/pubspec.lock`，停止 Task 5，在帳本記 ruling「`desktop_drop` 維持 0.8.4，列為後續（需連同 `file_picker` 升版）」，並更新報告與 `issues.md` 的過關條件 6；Task 7 的實機拖曳確認改為只驗 0.8.4 現況。解析成功就 `git diff -- app/pubspec.lock`，只保留 `desktop_drop`、`cross_file` 系列套件與 `sdks:` 區塊（預期 `flutter` 下限抬為 `>=3.47.7`、`dart` 下限抬為 `>=3.13.5`）的變動，其餘還原。
- [ ] **Step 2: 先改測試到新 API（紅）。** 讀 pub 快取中 `cross_file` 0.4.x 原始碼確認 `XDirectory` 的建構方式，再機械改寫兩個測試檔：`DropEventDetails(...)` → `DragDetails(items: const [], localPosition: Offset.zero, globalPosition: Offset.zero)`；`onDragEntered`／`onDragExited` → `onEnter`／`onLeave`（`onLeave` 無參數）；`.enable` → `.enabled`；`dropTarget.onDragDone?.call(DropDoneDetails(files: [DropItemFile(path)], ...))` → `await dropTarget.onDrop(DropDetails(items: [DropFileItem.fromPath(path)], localPosition: Offset.zero, globalPosition: Offset.zero, operation: DropOperation.copy))`（目錄用 `DropDirectoryItem` 並帶 `localPath`）；既有測試的斷言與測試名稱不改。另新增 3 個測試：`onDrop 回傳的 Future 在匯入完成前不會完成`（用 `FakeBookImportService.pendingCompleter` 擋住匯入：先 `final f = dropTarget.onDrop(...)`，`pump` 後斷言尚未完成，`complete` 之後才完成；用來鎖住「整段匯入在 `onDrop` 內完成」）、`沒有本機路徑的項目（localPath 為 null，例如虛擬檔案）被略過，不呼叫 importFiles`、`只有文字項目（DropStringItem）不呼叫 importFiles`。執行兩個測試檔，預期因為 `import_drop_target.dart` 仍是舊 API 而編譯失敗（紅）。
- [ ] **Step 3: 實作。** `import_drop_target.dart`：`DropTarget(enable:, onDragEntered:, onDragExited:, onDragDone:)` 改為 `DropTarget(enabled:, onEnter:, onLeave:, onDrop:)`；`_handleDragDone(DropDoneDetails)` 改為 `Future<void> _handleDrop(DropDetails details)`，路徑改由 `details.items` 取：`DropFileItem` 與 `DropDirectoryItem` 的 `localPath`（非 null 才收），其餘項目（含 `DropStringItem`、`localPath` 為 null 的虛擬檔案）略過；沒有任何可用路徑就直接 return（與現行「`files` 為空就 return」一致）。**整段匯入流程（`importDroppedPaths`、確認對話框、結果提示、更新候選處理）都必須在 `_handleDrop` 回傳的 Future 內 `await` 完成**，不得 `unawaited`，否則 provider 與暫存檔在 `onDrop` 返回後失效。`_busy`、`_dragging` 邏輯與覆蓋層外觀不動；更新類別註解（`enable` → `enabled`）。
- [ ] **Step 4: 執行確認（綠）。** `flutter test test/screens/support/import_drop_target_test.dart test/screens/adaptive_shell_scaffold_test.dart` 全過；`flutter analyze lib/screens/support/import_drop_target.dart test/screens/support/import_drop_target_test.dart test/screens/adaptive_shell_scaffold_test.dart` 預期 `No issues found!`。
- [ ] **Step 5: Commit。**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/screens/support/import_drop_target.dart app/test/screens/support/import_drop_target_test.dart app/test/screens/adaptive_shell_scaffold_test.dart
git commit -m "chore(deps): desktop_drop 升到 0.9.2 並改寫拖曳匯入（epic-66 Issue 6 Task 5）"
```

（Windows 實機拖曳確認在 Task 7 Step 2，它是過關條件，不是可略過的「未驗證項目」。）

---

### Task 6：Android 與 Windows 建置驗證

**Files:**
- 無異動；結果寫入報告。

- [ ] **Step 1: Android debug 建置。** 在 `app/` 執行 `flutter build apk --debug`，輸出存 scratchpad；預期 `✓ Built build\app\outputs\flutter-apk\app-debug.apk`。這是 Android 第一次在 3.47.x 上建置：把所有 warning（AGP、Kotlin、Gradle、`flutter_inappwebview_android` 本機修補、`desktop_drop` 的 Android Kotlin 套用）逐條記進報告，分「僅警告」與「失敗」。失敗就停下來回報，不要靠改 AGP／Kotlin 版本硬解，那屬另一個決定。
- [ ] **Step 2: Windows debug 建置。** 依 Global Constraints 的建置說明，`flutter build windows --debug`（Task 4 完成後不必設 `CL`），預期成功。
- [ ] **Step 3: 全專案分析與全套測試。** `flutter analyze` 預期只剩 `use_null_aware_elements` 這 1 個 info；全套 `flutter test` 預期 5124 個（基準 5118 加 Task 3 的 3 個、Task 5 的 3 個）、0 失敗。

---

### Task 7：Windows 實機確認、政策文件與報告（需人在電腦前、螢幕解鎖）

**Files:**
- Modify: `CLAUDE.md`（「常用指令」的 Flutter 版本段落）、`docs/epics/epic-66-windows-port/epic.md`（新增決策 28）、`docs/epics/epic-66-windows-port/issues.md`（Issue 6 狀態列）、本檔（勾選步驟）
- Create: `docs/epics/epic-66-windows-port/issue-6-report.md`

- [ ] **Step 1: Windows 開書冒煙。** 以 Task 6 建的 Windows debug 版，用 Issue 11 的實驗腳本（scratchpad 的 `run_open_book_experiment.ps1`，只留一個版本資料夾，`-Rounds 5`）冷啟動 5 次、每次自動還原上次的書，記錄 `已渲染`／`開書逾時` 與耗時。預期 5／5 成功；與 Issue 11 的 3.47.4 結果（約 14～18 秒）比較。報告用語限定為「冷啟動開書 5／5」，不得外推到 Impeller 長時間使用。實驗期間請使用者不要操作電腦。
- [ ] **Step 2: Windows 實機拖曳確認（過關條件）。** 請使用者用同一個 Windows debug 版，在書架分頁依序拖入並回報結果：（a）1 個支援格式的書檔（例如 `.epub`）；（b）同時 2 個書檔；（c）1 個含書檔的資料夾；（d）1 個不支援格式的檔案（預期略過並提示）；（e）從 zip 內直接拖出的檔案（虛擬檔案，預期不崩潰；是否匯入如實記錄）；（f）選取文字拖入（預期不崩潰、不匯入）；（g）匯入進行中再拖一次（預期顯示忙碌提示）。每項記「通過／異常」與看到的畫面。若 Task 5 Step 1 的關卡讓 `desktop_drop` 維持 0.8.4，這一步只驗 0.8.4 現況。
- [ ] **Step 3: 更新 `CLAUDE.md`。** 把「採用 Flutter 3.41.9」段落改為 3.47.9，整句刪除「例如 `ReorderableListView.onReorderItem` 在 3.41.9 不存在……曾因此讓 `main` 編譯失敗」的舉例，保留「不要使用此版本沒有的較新 API」的通則與「升級 Flutter 版本前需先與人類確認」。只改這一段。
- [ ] **Step 4: 新增 `epic.md` 決策 28。** 記錄：升級到 3.47.9 的理由（3.47.8 安全公告 GHSA-frr6-h895-5pxp、3.47.6 Windows 卡死修正、`desktop_drop` 0.9.x 需要 Dart ≥ 3.13.5）、使用者選擇直接升級共用 SDK 與「審查後仍堅持升級 `desktop_drop`」、`C:\src\flutter-3.41.9` 保留、`pdfrx`／`file_picker`／`window_manager` 大跳版不在本 Issue、回退點 `9584c6713b` 與回退指令。
- [ ] **Step 5: 寫 `issue-6-report.md`。** 內容：診斷與決策表、各 Task 結果、Task 6 的 Android 警告清單、Task 7 的冒煙與拖曳紀錄、回退指令（含需要網路）、未驗證項目（Android 真機、Impeller 下 WebView2 長時間使用）。
- [ ] **Step 6: 同步文件並勾選。** `issues.md` Issue 6 狀態改為「✅ 實作完成，待 PR」；本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [ ] **Step 7: Commit。**

```bash
git add CLAUDE.md docs/epics/epic-66-windows-port/epic.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/issue-6-report.md docs/epics/epic-66-windows-port/plans/plan-issue-6.md
git commit -m "docs(epic-66): Issue 6 驗證報告、Flutter 版本政策與進度同步"
```

---

## 已知風險

- Task 1 動的是共用 SDK：`--force` 只重設 tracked 檔案、不動 untracked，回退指令留在 `stable` 分支，但回退需要網路重新下載引擎，沒有演練過。
- Task 5 的關卡：`desktop_drop` 0.9.2 的 `cross_file ^0.4.0` 可能與 `file_picker` 衝突，屆時退回 0.8.4，這個 Issue 仍算完成，`desktop_drop` 列為後續。
- Task 4 若問題已不存在，Task 以「不需要」收尾。
- 沒有 Android 裝置，Android 只到建置成功。
- Task 7 需要人在電腦前；Windows 實機拖曳是過關條件。
- `pdfrx` 2.4.7→2.12.0 可能還有效能或 API 改進，刻意不在本 Issue 做，列為後續。
