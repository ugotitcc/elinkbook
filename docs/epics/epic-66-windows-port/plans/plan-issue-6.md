# Issue 6：Flutter 升級至 3.47.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把專案正式採用的 Flutter 從 3.41.9 改為 3.47.9：升級共用 SDK、處理 `onReorder` 棄用、讓 Windows 建置不需要手動設 `CL=/utf-8`，並驗證 Android 與 Windows 都能建置、全套測試乾淨。`desktop_drop` 維持 0.8.4，升級另立 Issue 16。

**Architecture:** 這台機器的 `C:\tools\flutter` 其實從 2026-10-23 起就是 3.47.4，近期所有工作都在 3.47.4 上通過；`CLAUDE.md` 的 3.41.9 與另一份 `C:\src\flutter-3.41.9` 是過時的政策。所以：（1）先把共用 SDK 升到含安全公告修補的 3.47.9；（2）先單獨驗證 SDK 本身沒帶來回歸，再逐項改程式；（3）`desktop_drop` 0.9 因 `cross_file` 衝突無法在本 Issue 升級，只記錄原因並登記 Issue 16；（4）把政策文件對齊現況。

**Tech Stack:** Flutter 3.47.9（Dart 3.13.7）、AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14、`desktop_drop` 0.8.4（固定版本，不動）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 6 範圍／過關條件／單元測試要求」；`epic.md` 決策 27。審查：`reviews/review-plan-issue-6.md`、`reviews/review-plan-issue-6-round2.md`（不進版控）。

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
| `flutter upgrade` 的行為 | `C:\tools\flutter` 的 `git status -s` 有 119 行，**全是 untracked**；`flutter upgrade` 對 stable 只要輸出非空就拒絕，需要 `--force`（內部是 `git reset --hard`，untracked 不受影響）。它仍會 `git fetch --tags`，目標是 stable 分支**當下**的最新版；第二階段會在**目前工作目錄的專案**跑 `pub get --upgrade`，若在 `app/` 下執行會把鎖檔整個升級 |
| `desktop_drop` 0.9.x | **無法在本 Issue 升級**。0.9.x 要求 Dart ≥ 3.13.5 並依賴 `cross_file ^0.4.0`（破壞性：移除 `XFile(String path)`、`XFile.path`、`XFile.mimeType`、`XFile.fromData`，`XFile.name` 變非同步）；鎖檔中 `desktop_drop` 0.8.4、`file_picker` 11.0.3、`share_plus` 11.1.0、`share_plus_platform_interface` 6.1.0 全都依賴 `cross_file ^0.3.x`，而 `file_picker` 最新 13.3.2、`share_plus` 最新 13.3.1 也仍要求 `^0.3.x`（審查員在 scratchpad 做 `pub get --dry-run` 確認解析失敗）。唯一的路是 vendor 修補三個套件（`file_picker` 約 5 行、`share_plus_platform_interface` 約 15～20 行、`share_plus` 只改 pubspec）加改寫 `import_drop_target.dart`；風險是 Android 分享的 mimeType 行為、沒有 Android 裝置可驗證、長期維護修補 |
| 使用者決定（2026-11-07） | 直接升級共用的 `C:\tools\flutter`；**Issue 6 不升 `desktop_drop`，另立 Issue 16 專做「`cross_file` 0.4 遷移」**。已確認不做 Issue 16 也不會壞任何東西：0.8.4 沒有我們需要缺的功能，且官方遲早會支援 `cross_file` 0.4，到時可用一般方式升級 |
| 其他大跳版 | `pdfrx` 2.4.7→2.12.0、`file_picker` 11→13、`window_manager` 0.5.2→0.6.0 **本 Issue 不升**；`sqflite`、`url_launcher` 只差 patch，也不升 |
| `onReorder` | 全專案只有 `dictionary_settings_screen.dart:817` 一個 `ReorderableListView.builder`；`onReorderItem` 的 `newIndex` 已扣除移除項目位移；`onReorder` 在 3.47.x 仍存在但已棄用，兩者同時傳會觸發 assert。既有 5 個拖曳測試（`拖曳排序後呼叫 reorder…`、`拖曳進行中…` 兩個、`拖曳把手觸控區…` 兩個）**全是把 `c` 往上拖**（「往前拖」），沒有「往後拖」 |
| Android 建置設定 | AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14 都在 3.47.9 支援範圍內（上限 Gradle 9.3.1／AGP 9.2／KGP 2.4.0）；`gradle.properties` 已有 `android.builtInKotlin=false`；另有 `patches/flutter_inappwebview_android` 本機修補；**Android 尚未在 3.47.x 上建置過** |
| `/utf-8` 問題 | 失敗目標是外掛 `connectivity_plus`：`connectivity_plus_plugin.cpp` 含 UTF-8 em dash，本機字碼頁 950 觸發 C4819，被 `/WX` 升為錯誤。`add_compile_options` 是目錄屬性，要放在 `windows/CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前，才同時涵蓋 flutter、runner 與全部 plugin |

## Global Constraints

- 目標版本 3.47.9。回退點是目前的 `9584c6713b`（3.47.4）。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`；`app/pubspec.lock` 預期**完全不變**（`desktop_drop` 不升），任何變動都要逐行檢查，與 Flutter 版本無直接關係的一律還原；`git add` 一律明確列檔。
- 不新增、不修改任何 ARB 字串。
- `onReorder` 改 `onReorderItem` 後，拖曳排序的結果必須與現況完全相同，既有 5 個拖曳測試不改斷言。
- 升級共用 SDK 前，確認沒有其他 `flutter`／`dart`／`flutter_tester` 程序在跑，且 epic-54 的 Android 真機驗證沒有進行中（它共用同一份 SDK，中途升級會讓結果混版本）。
- **`flutter upgrade` 要從專案外的目錄執行**（例如 `C:\Users\huthief`），不要在 `app/` 下，否則第二階段的 `pub get --upgrade` 會把 `pubspec.lock` 整個升級。
- Windows 建置：PowerShell，`$env:Path += ';C:\Users\huthief\bin'`（放尾端；該資料夾有個 `flutter` 檔會蓋掉指令；用來找 `nuget.exe`）；新 worktree 第一次建置若曾在缺 `nuget.exe` 時失敗，先刪該 worktree 的 `app\build\windows` 再建。
- 實驗腳本與暫存輸出放 scratchpad，不放進專案。
- 沒有 Android 裝置：Android 只驗證到 `flutter build apk --debug` 成功；報告只能寫「建置成功」，不得寫「Android 已驗證」。

## Review Focus

1. 共用 SDK 升級後，其他專案或 session 的 `flutter` 命令是否仍可用；升到的版本是否真的是 3.47.9；`pubspec.lock` 有沒有被動到；回退步驟要寫得出來、照得做。（Task 1）
2. SDK 升級本身是否帶來回歸：改任何程式前，先單獨跑 `pub get`、`analyze`、全套 `test`，與 3.47.4 基準比對。（Task 2）
3. `onReorderItem` 的 `newIndex` 語意與 `onReorder` 不同：**往後拖**（`newIndex > oldIndex` 的差 1）、拖到最後一格、原地放開，結果都要與現況一致。（Task 3）
4. `/utf-8` 修法必須讓「沒設 `CL`」的建置成功，且不影響設了 `CL` 的建置；兩次驗證之間都要重刪 `build\windows`。（Task 4）
5. `desktop_drop` 維持 0.8.4 不能變成「沒人記得」：`pubspec.yaml` 要有原因註解、Issue 16 要登記；而 0.8.4 在 3.47.9 上必須實測（全套測試、建置、冷啟動 5 次、實機拖曳），因為 0.9.1 修過一個只在部分 Flutter 引擎出現的 Windows 啟動崩潰，3.47.9 的引擎是否受影響未知。（Task 5、7）
6. Android 建置警告：AGP 8.11.1／Kotlin 2.3.20 可能出現相容性警告；警告記錄但不是失敗，真正失敗才停下來。這是 Android 第一次在 3.47.x 上建置。（Task 6）
7. 驗證只在 Windows debug 版、沒有 Android 真機：報告不得外推。（Task 6、7）

---

### Task 1：升級共用 SDK 到 3.47.9

**Files:**
- 無專案檔案異動；變動在 `C:\tools\flutter`（專案外的共用 SDK）。結果寫入 Task 7 的報告。

**Interfaces:**
- Produces: `flutter --version` 顯示 `Flutter 3.47.9`（Dart 3.13.7）、channel 仍是 `stable`；回退指令 `git -C C:\tools\flutter reset --hard 9584c6713b`（留在 `stable` 分支）加 `flutter --version`、`flutter doctor`。

- [x] **Step 1: 升級前紀錄與確認目標版本。** 確認沒有 `flutter`／`dart`／`flutter_tester` 程序在跑（`Get-Process`）、epic-54 真機驗證沒有進行中；記下 `flutter --version`、`git -C C:\tools\flutter rev-parse HEAD`（預期 `9584c6713b…`）、`git -C C:\tools\flutter branch --show-current`（預期 `stable`）、`git -C C:\tools\flutter status -s | Where-Object { $_ -notmatch '^\?\?' }`（預期空，代表沒有 tracked 修改）與 `flutter doctor` 輸出（存 scratchpad）。再執行 `git ls-remote https://github.com/flutter/flutter.git refs/heads/stable refs/tags/3.47.9`，**預期兩者 hash 相同（`c197ca5199e9…`）**；若 `stable` 已指向比 3.47.9 更新的版本，停下來回報，由使用者決定是否仍要升（`flutter upgrade` 會升到 `stable` 當下的最新版，不是固定 3.47.9）。若有 tracked 修改，也停下來回報，不要 `--force`。
- [x] **Step 2: 升級。** 先 `Set-Location C:\Users\huthief`（**不要在專案目錄**），再執行 `flutter upgrade --force`（只做 `git reset --hard <rev>`，untracked 檔案不受影響）。若失敗，備案是留在 `stable` 分支：`git -C C:\tools\flutter merge --ff-only 3.47.9`，再 `flutter --version` 讓工具下載對應引擎。**不要用 `git checkout` 到標籤**（會讓 HEAD 變 detached，之後 `flutter upgrade` 與 channel 顯示都會壞）。
- [x] **Step 3: 驗證。** `flutter --version` 預期 `Flutter 3.47.9`、`Dart 3.13.7`、channel `stable`；若升到的不是 3.47.9，停下來回報。`flutter doctor` 與 Step 1 逐項比對，預期 Android、Windows、Visual Studio 仍是 ✓。再確認本 worktree 的鎖檔沒被動到：`git status --short app/pubspec.lock` 預期空；若有輸出，`git checkout -- app/pubspec.lock` 還原並在帳本記 ruling。
- [x] **Step 4: 記錄回退（只寫不做）。** 報告寫：回退指令 `git -C C:\tools\flutter reset --hard 9584c6713b`，之後 `flutter --version`、`flutter doctor`；兩版引擎不同，**回退會重新下載引擎與 Dart SDK，需要網路**，舊引擎快取不保留。

---

### Task 2：只換 SDK、不改程式的回歸基準

**Files:**
- 無異動；結果寫入報告。

- [x] **Step 1: 相依解析。** 在 `app/` 執行 `flutter pub get`，再 `git diff --stat -- pubspec.lock`，預期沒有變動；若有變動，逐行檢查，只保留與 Flutter 版本直接相關的（例如 `sdks:` 區塊），其餘 `git checkout -- app/pubspec.lock` 還原並在帳本記 ruling。
- [x] **Step 2: 靜態分析。** `flutter analyze`，預期與 3.47.4 基準相同：只有 2 個 info。出現第 3 個以上就是 SDK 升級帶來的新警告，逐一記錄。
- [x] **Step 3: 全套測試。** 在 `app/` 用 JSON reporter 跑 `flutter test`（比照 Issue 11：輸出存 scratchpad、列出失敗名稱），預期 5118 個、0 失敗。有失敗就單獨重跑；單獨也失敗的是回歸，停下來用 `superpowers:systematic-debugging` 查；只有全套才失敗的記為偶發並與 `pdf_reader_view_filters_test`（Issue 15）比對。特別留意 `import_drop_target_test.dart`、`adaptive_shell_scaffold_test.dart`（用到 `desktop_drop` 0.8.4）是否在 3.47.9 上仍通過。

---

### Task 3：`onReorder` 改 `onReorderItem`

**Files:**
- Modify: `app/lib/screens/dictionary_settings_screen.dart`（`_onReorder` 約第 213 行；`ReorderableListView.builder` 約第 817～821 行）
- Test: `app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Produces: `Future<void> _onReorder(int oldIndex, int newIndex)` 簽章不變，但 `newIndex` 語意改為「已扣除移除項目位移」。

- [x] **Step 1: 跑既有重排測試確認基準。** `flutter test test/screens/dictionary_settings_screen_test.dart`，預期全過（含 5 個拖曳測試，皆為把 `c` 往上拖）。
- [x] **Step 2: 補三個「往後拖／原地」的測試（先在 `onReorder` 版本上跑綠）。** 沿用該檔既有的 `_pump`、`FakeDictionaryManager`、`_item('a', priority: 0)`／`b`／`c` 清單與 `_visibleOrder(tester, ['a', 'b', 'c'])`，把手 Key 為 `dictionary_drag_handle_a`，列 Key 為 `dictionary_item_a`。（1）`往後拖曳（第一個拖到最後一格）後 reorder 傳入 [b, c, a]`：`tester.drag(find.byKey(const Key('dictionary_drag_handle_a')), const Offset(0, 400))`，`pumpAndSettle`，斷言 `manager.reorderCalls == [['b','c','a']]` 且 `_visibleOrder` 為 `['b','c','a']`；（2）`往後拖曳一格後 reorder 傳入 [b, a, c]`：先取 `final rowHeight = tester.getRect(find.byKey(const Key('dictionary_item_a'))).height`，拖 `Offset(0, rowHeight * 1.2)`（超過 b 的中線、未到 c 的中線），斷言 `[['b','a','c']]`；這個能分辨少減或多減 1；（3）`原地放開（位移很小）不呼叫 reorder`：拖 `Offset(0, 5)`，斷言 `manager.reorderCalls` 為空。三個測試在目前的 `onReorder` 實作上必須先通過，確保測試本身正確；若 `rowHeight * 1.2` 的測試不穩，改用分段 `startGesture` 與 `moveBy`（比照既有 `拖曳進行中…` 測試）。
- [x] **Step 3: 實作。** `onReorder: _onReorder` 改為 `onReorderItem: _onReorder`；`_onReorder` 內刪除 `if (newIndex > oldIndex) newIndex -= 1;` 與其註解，改一行中文註解說明 `onReorderItem` 的 `newIndex` 已扣除位移。其餘邏輯不動。
- [x] **Step 4: 執行確認。** 同 Step 1 指令，預期全過（既有 5 個拖曳測試不改斷言，加新增 3 個）；若往後拖的測試失敗，代表位移處理錯了，修實作不要改測試。`flutter analyze lib/screens/dictionary_settings_screen.dart` 預期 `No issues found!`。
- [x] **Step 5: Commit。**

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

- [x] **Step 1: 重現失敗（紅）。** PowerShell 確認 `$env:CL` 為空，刪該 worktree 的 `app\build\windows`，執行 `flutter build windows --debug`。預期失敗，錯誤為 `connectivity_plus_plugin.cpp` 的 C4819（字碼頁 950 無法表示 UTF-8 的 em dash），被 `/WX` 升為錯誤；把前 20 行錯誤存 scratchpad。若**成功**，代表問題已不存在：停止本 Task，報告記「`/utf-8` 問題在 3.47.9 已不需處理」。
- [x] **Step 2: 實作。** 在 `windows/CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前加 `if(MSVC) add_compile_options(/utf-8) endif()`，附中文註解：放在頂層目錄層級才會讓之後引入的 flutter、runner 與全部 plugin 都繼承；繁中 Windows 字碼頁 950 會讓含 UTF-8 的 plugin 原始碼被 `/WX` 擋下（見 epic.md 決策 27）。不要碰 `generated_plugins.cmake`。
- [x] **Step 3: 驗證（綠）。** `$env:CL` 仍為空、**重刪 `build\windows`** 後重建，預期 `Built build\windows\x64\runner\Debug\elinkbook.exe`。再設 `$env:CL='/utf-8'`、**再次重刪 `build\windows`** 重建一次，預期仍成功（不衝突）；不刪的話不會重新編譯，驗證無意義。
- [x] **Step 4: Commit。**

```bash
git add app/windows/CMakeLists.txt
git commit -m "build(windows): CMake 加 /utf-8，免手動設 CL 環境變數（epic-66 Issue 6 Task 4）"
```

---

### Task 5：`desktop_drop` 維持 0.8.4，記錄原因並登記 Issue 16

**Files:**
- Modify: `app/pubspec.yaml`（只在 `desktop_drop: 0.8.4` 旁加註解，版本不變）
- Modify: `docs/epics/epic-66-windows-port/issues.md`（新增 Issue 16 列與範圍簡述）

**Interfaces:**
- Produces: `issues.md` 的 Issue 16（⚪ 未開始，尚未規劃），內容足以讓之後的人不重做這次的調查。

- [x] **Step 1: 加註解。** 在 `pubspec.yaml` 的 `desktop_drop: 0.8.4` 上方加中文註解：固定 0.8.4，0.9.x 要求 `cross_file ^0.4.0`，與 `file_picker`、`share_plus` 等套件的 `cross_file ^0.3.x` 衝突，見 `docs/epics/epic-66-windows-port/issues.md` Issue 16。版本號與其他行不動。
- [x] **Step 2: 確認鎖檔不變。** `flutter pub get`，`git diff --stat -- pubspec.lock` 預期空；`flutter analyze` 預期與 Task 2 相同。
- [x] **Step 3: 登記 Issue 16。** 在 `issues.md` 表格新增第 16 列（`desktop_drop` 0.9 與 `cross_file` 0.4 遷移，⚪ 未開始、尚未規劃），並在「後續 Issue」清單加一段簡述：（a）阻礙：`cross_file` 0.4 破壞性更新，`desktop_drop`、`file_picker`、`share_plus`、`share_plus_platform_interface` 目前都依賴 `^0.3.x`，最新版也未支援；（b）已知做法：vendor 修補 `file_picker`（`platform_file.dart` 的 `xFile` 取值，約 5 行）、`share_plus_platform_interface`（`method_channel_share.dart` 的 `.path`、`.mimeType`、`.name`、`XFile(path)`，約 15～20 行）、`share_plus`（只改 pubspec 約束），用 `dependency_overrides` 指向 `patches/`；專案內 `notes_bottom_sheet.dart:194` 的 `XFile(path, mimeType: 'text/markdown')` 改為 `XFile.fileSystem(path:)`（0.4 沒有 `mimeType`，Markdown 的 mimeType 要由修補後的 `share_plus_platform_interface` 依副檔名推斷或明確傳入）；`import_drop_target.dart` 改寫成 0.9 的 `onDrop`／`items`／`enabled`／`onEnter`／`onLeave`，匯入須整段在 `onDrop` 的 Future 內完成，測試需先呼叫 `CrossFileIO.registerWith()`、有對話框或擱置匯入的約 6 個測試要改成先取 Future 再 `pump`；（c）風險：Android 分享 mimeType 行為、無 Android 裝置驗證、長期維護修補；（d）出路：等官方支援 `cross_file` 0.4 就可以用一般方式升級，不需要修補；（e）不做 Issue 16 也不會壞任何東西。
- [x] **Step 4: Commit。**

```bash
git add app/pubspec.yaml docs/epics/epic-66-windows-port/issues.md
git commit -m "docs: desktop_drop 維持 0.8.4 並登記 Issue 16（epic-66 Issue 6 Task 5）"
```

---

### Task 6：Android 與 Windows 建置驗證

**Files:**
- 無異動；結果寫入報告。

- [x] **Step 1: Android debug 建置。** 在 `app/` 執行 `flutter build apk --debug`，輸出存 scratchpad；預期 `✓ Built build\app\outputs\flutter-apk\app-debug.apk`。這是 Android 第一次在 3.47.x 上建置：把所有 warning（AGP、Kotlin、Gradle、`flutter_inappwebview_android` 本機修補）逐條記進報告，分「僅警告」與「失敗」。失敗就停下來回報，不要靠改 AGP／Kotlin 版本硬解，那屬另一個決定。
- [x] **Step 2: Windows debug 建置。** 依 Global Constraints 的建置說明，`flutter build windows --debug`（Task 4 完成後不必設 `CL`），預期成功。
- [x] **Step 3: 全專案分析與全套測試。** `flutter analyze` 預期只剩 `use_null_aware_elements` 這 1 個 info；全套 `flutter test` 預期 5121 個（基準 5118 加 Task 3 的 3 個）、0 失敗。

---

### Task 7：Windows 實機確認、政策文件與報告（需人在電腦前、螢幕解鎖）

**Files:**
- Modify: `CLAUDE.md`（「常用指令」的 Flutter 版本段落）、`docs/epics/epic-66-windows-port/epic.md`（新增決策 28）、`docs/epics/epic-66-windows-port/issues.md`（Issue 6 狀態列）、本檔（勾選步驟）
- Create: `docs/epics/epic-66-windows-port/issue-6-report.md`

- [x] **Step 1: Windows 開書冒煙。** 以 Task 6 建的 Windows debug 版，用 Issue 11 的實驗腳本（scratchpad 的 `run_open_book_experiment.ps1`，只留一個版本資料夾，`-Rounds 5`）冷啟動 5 次、每次自動還原上次的書，記錄 `已渲染`／`開書逾時` 與耗時。預期 5／5 成功；與 Issue 11 的 3.47.4 結果（約 14～18 秒）比較。這同時驗證 `desktop_drop` 0.8.4 在 3.47.9 引擎上沒有啟動崩潰。報告用語限定為「冷啟動開書 5／5」，不得外推到 Impeller 長時間使用。實驗期間請使用者不要操作電腦。
- [x] **Step 2: Windows 實機拖曳回歸確認（過關條件）。** 請使用者用同一個 Windows debug 版，在書架分頁依序拖入並回報結果：（a）1 個支援格式的書檔（例如 `.epub`）；（b）同時 2 個書檔；（c）1 個含書檔的資料夾；（d）1 個不支援格式的檔案（預期略過並提示）；（e）匯入進行中再拖一次（要用較大的檔案才能重現，預期顯示忙碌提示）。每項記「通過／異常」與看到的畫面。目的是確認 SDK 與引擎換版後 `desktop_drop` 0.8.4 的拖曳匯入沒有回歸。
- [x] **Step 3: 更新 `CLAUDE.md`。** 把「採用 Flutter 3.41.9」段落改為 3.47.9，整句刪除「例如 `ReorderableListView.onReorderItem` 在 3.41.9 不存在……曾因此讓 `main` 編譯失敗」的舉例，保留「不要使用此版本沒有的較新 API」的通則與「升級 Flutter 版本前需先與人類確認」。只改這一段。
- [x] **Step 4: 新增 `epic.md` 決策 28。** 記錄：升級到 3.47.9 的理由（3.47.8 安全公告 GHSA-frr6-h895-5pxp、3.47.6 Windows 卡死修正）、使用者選擇直接升級共用 SDK、`C:\src\flutter-3.41.9` 保留、`desktop_drop` 維持 0.8.4 與原因（`cross_file` 0.4 衝突，另立 Issue 16，不做也不會壞）、`pdfrx`／`file_picker`／`window_manager` 大跳版不在本 Issue、回退點 `9584c6713b` 與回退指令。
- [x] **Step 5: 寫 `issue-6-report.md`。** 內容：診斷與決策表、各 Task 結果、Task 6 的 Android 警告清單、Task 7 的冒煙與拖曳紀錄、回退指令（含需要網路）、未驗證項目（Android 真機、Impeller 下 WebView2 長時間使用）、已知限制（`desktop_drop` 0.8.4，Issue 16）。
- [x] **Step 6: 同步文件並勾選。** `issues.md` Issue 6 狀態改為「✅ 實作完成，待 PR」；本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [x] **Step 7: Commit。**

```bash
git add CLAUDE.md docs/epics/epic-66-windows-port/epic.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/issue-6-report.md docs/epics/epic-66-windows-port/plans/plan-issue-6.md
git commit -m "docs(epic-66): Issue 6 驗證報告、Flutter 版本政策與進度同步"
```

---

## 已知風險

- Task 1 動的是共用 SDK：`--force` 只重設 tracked 檔案、不動 untracked，回退指令留在 `stable` 分支，但回退需要網路重新下載引擎，沒有演練過。
- `flutter upgrade` 升到的是 `stable` 當下最新版，Step 1 的 `ls-remote` 檢查若發現不是 3.47.9 要先回報。
- `desktop_drop` 0.8.4 在 3.47.9 的引擎上是否有 0.9.1 修過的 Windows 啟動崩潰，要靠 Task 7 冷啟動 5 次偵測；樣本小，若偶發崩潰未必抓到。
- Task 4 若問題已不存在，Task 以「不需要」收尾。
- 沒有 Android 裝置，Android 只到建置成功，且這是 Android 第一次在 3.47.x 上建置。
- Task 7 需要人在電腦前；Windows 實機拖曳回歸確認是過關條件。
- `pdfrx` 2.4.7→2.12.0 可能還有效能或 API 改進，刻意不在本 Issue 做，列為後續。
