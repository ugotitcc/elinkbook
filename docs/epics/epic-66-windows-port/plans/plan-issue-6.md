# Issue 6：Flutter 升級至 3.47.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把專案正式採用的 Flutter 從 3.41.9 改為 3.47.9：升級共用 SDK、處理棄用 API、讓 Windows 建置不需要手動設 `CL=/utf-8`、把 `desktop_drop` 升到最新，並驗證 Android 與 Windows 都能建置、全套測試乾淨。

**Architecture:** 這台機器的 `C:\tools\flutter` 其實從 2026-10-23 起就是 3.47.4，近期所有工作（Issue 8～11 的測試與建置）都在 3.47.4 上通過；`CLAUDE.md` 的 3.41.9 與另一份 `C:\src\flutter-3.41.9` 是過時的政策。所以這個 Issue 不是「大升級」，而是：（1）把共用 SDK 升到含安全公告修補的 3.47.9；（2）先單獨驗證 SDK 本身沒帶來回歸，再逐項改程式；（3）把政策文件對齊現況。

**Tech Stack:** Flutter 3.47.9（Dart 3.13.x）、AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14、`desktop_drop` 0.9.2。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 6 範圍／過關條件／單元測試要求」；`epic.md` 決策 27。

## 診斷與決策（2026-11-07，已實測，計畫的依據）

| 項目 | 事實 |
|---|---|
| 這台機器的預設 Flutter | `C:\tools\flutter` = 3.47.4（`bin\cache\flutter.version.json` 修改於 2026-10-23）；Git Bash 的 `~/bin/flutter` 只是轉呼叫它；PowerShell 與 Git Bash 結果一致 |
| 另一份 SDK | `C:\src\flutter-3.41.9`（2026-11-06 建立，保留作回退用，本 Issue 不刪） |
| 3.47.4 上的 `flutter analyze` | 全專案只有 2 個 info：`dictionary_settings_screen.dart:821` 的 `onReorder` 棄用、`local_book_handler_test.dart:65` 的 `use_null_aware_elements` |
| 3.47.4 上的 `flutter pub get --dry-run` | `No dependencies would change`（鎖檔與 SDK 已一致，先前「降級 intl、meta、matcher」的落差只存在於 3.41.9） |
| 3.47.4 上的全套 `flutter test` | 5118 個，0 失敗（Issue 11 Task 5） |
| 3.47.4 上的 Windows 開書 | 12／12 成功（Issue 11 實驗，約 14～18 秒） |
| `flutter doctor` | Android toolchain（SDK 36.1.0）、Visual Studio Build Tools 17.14.44 都 ✓；已連接裝置只有 Windows、Chrome、Edge，**沒有 Android 裝置** |
| 3.47.8 | **含安全公告 GHSA-frr6-h895-5pxp**：Dart 執行環境的 BoringSSL 封鎖被入侵的 eMudhra 中繼 CA 憑證；Android 14+ 的 `dart:io` 改用可更新的 Conscrypt 根憑證庫。Android、Windows、Linux 應用升級後重新建置。本專案有 HTTPS 連線（同步、雲端匯入、線上查詞） |
| 3.47.6 | 修正「Windows 正式版 App 會卡死」（flutter/192513）；3.47.4 尚未包含 |
| 3.47.9 | 最新 stable（2026-10-29）；另修 Windows `MAX_PATH` 時 `flutter_tools` 崩潰、`flutter test` 在 pub workspace／符號連結目錄崩潰 |
| 可升級的直接相依 | `desktop_drop` 0.8.4→0.9.2（0.9.x 要求 Flutter ≥ 3.47.7）；`pdfrx` 2.4.7→2.12.0、`file_picker` 11→13、`window_manager` 0.5.2→0.6.0 是大跳版，**本 Issue 不升**；`sqflite`、`url_launcher` 只差 patch，也不升 |
| `onReorder` | 全專案只有 `dictionary_settings_screen.dart:817` 一個 `ReorderableListView.builder`；已有 3 個重排測試（`dictionary_settings_screen_test.dart` 約 134、170、201 行） |
| Android 建置設定 | AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14；還有 `patches/flutter_inappwebview_android` 本機修補 |

使用者決定（2026-11-07）：**直接升級共用的 `C:\tools\flutter`**（不並存安裝）。這會讓所有使用這份 SDK 的專案與 session 同時變更，所以計畫要求先記錄回退點，並在升級時確認沒有其他 flutter 命令正在執行。

## Global Constraints

- 目標版本 3.47.9。升級前後用 `flutter --version` 確認；回退點是目前的 `9584c6713b`（3.47.4）。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`；`pubspec.lock` 只允許 `desktop_drop` 相關行與其必要連動的變動；`git add` 一律明確列檔。
- 不新增、不修改任何 ARB 字串。
- 行為不變：`onReorder` 改 `onReorderItem` 後，拖曳排序的結果必須與現況完全相同（既有 3 個測試不改斷言）。
- Windows 建置：PowerShell，`$env:Path += ';C:\Users\huthief\bin'`（放尾端；該資料夾有個 `flutter` 檔會蓋掉指令；用來找 `nuget.exe`）；新 worktree 第一次建置若曾在缺 `nuget.exe` 時失敗，先刪該 worktree 的 `app\build\windows` 再建。
- 實驗腳本與暫存輸出放 scratchpad，不放進專案。
- 沒有 Android 裝置：Android 只驗證到 `flutter build apk --debug` 成功，不做真機確認；報告明講。

## Review Focus

1. 共用 SDK 升級後，其他專案或其他 session 的 `flutter` 命令是否仍可用：升級前後都要執行 `flutter doctor` 並比對；回退步驟要實際寫出、可照做。（Task 1）
2. SDK 升級本身是否帶來回歸：在改任何程式碼之前，先單獨跑 `flutter pub get`、`flutter analyze`、全套 `flutter test`，結果與 3.47.4 基準（5118 個、0 失敗、2 個 info）比對。（Task 2）
3. `onReorderItem` 的 `newIndex` 語意與 `onReorder` 不同（已扣除移除項目的位移）：往前拖、往後拖、拖到最後一格、原地放開，結果都要與現況一致。（Task 3）
4. `/utf-8` 修法必須讓「沒設 `CL` 環境變數」的建置成功，且不影響設了 `CL` 的建置，也不能影響 Android 或其他平台。（Task 4）
5. `desktop_drop` 0.9.2 的 API 是否與 `ImportDropTarget` 現有用法相容：編譯與既有測試通過，不能只靠 `pub get` 成功。（Task 5）
6. Android 建置警告：AGP 8.11.1／Kotlin 2.3.20 在 3.47.9 下可能出現「即將不相容 AGP 9」的警告；警告要記錄但不是失敗，真正失敗才停下來。（Task 6）
7. 驗證只在 Windows debug 版、沒有 Android 真機：報告不得寫「Android 已驗證」，只能寫「建置成功」。（Task 6、7）

---

### Task 1：升級共用 SDK 到 3.47.9

**Files:**
- 無專案檔案異動；變動在 `C:\tools\flutter`（專案外的共用 SDK）。結果寫入 Task 7 的報告。

**Interfaces:**
- Produces: `flutter --version` 顯示 `Flutter 3.47.9`；回退指令 `git -C C:\tools\flutter checkout 9584c6713b` 加 `flutter doctor`。

- [ ] **Step 1: 升級前紀錄。** 確認沒有其他 `flutter`／`dart` 程序在跑（`Get-Process flutter,dart,flutter_tester`），記下 `flutter --version`、`git -C C:\tools\flutter rev-parse HEAD`（預期 `9584c6713b…`）與 `flutter doctor` 輸出（存 scratchpad）。
- [ ] **Step 2: 升級。** 在 PowerShell 執行 `flutter upgrade`（stable channel）。若它無法升到 3.47.9，改用 `git -C C:\tools\flutter fetch --tags` 加 `git -C C:\tools\flutter checkout 3.47.9`，再執行 `flutter --version` 讓工具下載對應引擎。
- [ ] **Step 3: 驗證。** `flutter --version` 預期 `Flutter 3.47.9`；`flutter doctor` 與 Step 1 的輸出逐項比對，預期 Android、Windows、Visual Studio 仍是 ✓。
- [ ] **Step 4: 回退演練（只寫不做）。** 在報告記下回退指令；不實際回退。

---

### Task 2：只換 SDK、不改程式的回歸基準

**Files:**
- 無異動；結果寫入報告。

- [ ] **Step 1: 相依解析。** 在 `app/` 執行 `flutter pub get`，再 `git diff --stat -- pubspec.lock`，預期沒有變動（SDK 已與鎖檔一致）；若有變動，逐行檢查後只保留與 Flutter 版本直接相關的，其餘 `git checkout -- app/pubspec.lock` 還原並在帳本記 ruling。
- [ ] **Step 2: 靜態分析。** `flutter analyze`，預期與 3.47.4 基準相同：只有 2 個 info（`onReorder` 棄用、`use_null_aware_elements`）。出現第 3 個以上就是 SDK 升級帶來的新警告，逐一記錄。
- [ ] **Step 3: 全套測試。** 在 `app/` 用 JSON reporter 跑 `flutter test`（比照 Issue 11：輸出存 scratchpad、列出失敗名稱），預期 5118 個、0 失敗。有失敗就單獨重跑；單獨也失敗的是回歸，停下來用 `superpowers:systematic-debugging` 查；只有全套才失敗的記為偶發並與 `pdf_reader_view_filters_test`（Issue 15）比對。

---

### Task 3：`onReorder` 改 `onReorderItem`

**Files:**
- Modify: `app/lib/screens/dictionary_settings_screen.dart`（`_onReorder` 約第 213 行；`ReorderableListView.builder` 約第 817～821 行）
- Test: `app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Produces: `Future<void> _onReorder(int oldIndex, int newIndex)` 簽章不變，但 `newIndex` 語意改為「已扣除移除項目位移」（`onReorderItem` 傳入的值）。

- [ ] **Step 1: 跑既有重排測試確認基準。** `flutter test test/screens/dictionary_settings_screen_test.dart`，預期全過（含 3 個拖曳排序測試）。這是重構，不寫新的紅燈測試。
- [ ] **Step 2: 補一個「往前拖」的測試。** 現有測試只覆蓋部分方向；在同一檔案新增 `往前拖曳（排後面的詞典拖到最前面）後 reorder 傳入新的 id 順序`，用既有 `dictionary_drag_handle_<id>` Key、`manager.reorderCalls` 斷言（先用現行 `onReorder` 實作確認它通過，確保測試本身正確）。
- [ ] **Step 3: 實作。** `ReorderableListView.builder` 的 `onReorder: _onReorder` 改為 `onReorderItem: _onReorder`；`_onReorder` 內刪除 `if (newIndex > oldIndex) newIndex -= 1;` 與其註解，改一行中文註解說明 `onReorderItem` 的 `newIndex` 已扣除位移。其餘邏輯不動。
- [ ] **Step 4: 執行確認。** 同 Step 1 指令，預期全過（含新增的往前拖測試）；`flutter analyze lib/screens/dictionary_settings_screen.dart` 預期 `No issues found!`（棄用提示消失）。
- [ ] **Step 5: Commit。**

```bash
git add app/lib/screens/dictionary_settings_screen.dart app/test/screens/dictionary_settings_screen_test.dart
git commit -m "refactor: 詞典排序改用 onReorderItem（epic-66 Issue 6 Task 3）"
```

---

### Task 4：Windows 建置不再需要 `CL=/utf-8`

**Files:**
- Modify: `app/windows/CMakeLists.txt`（在 `add_subdirectory` 引入 plugins 與 runner 之前，為 MSVC 加 `/utf-8`）

**Interfaces:**
- Produces: 沒有 `CL` 環境變數時 `flutter build windows --debug` 成功。

- [ ] **Step 1: 重現失敗（紅）。** 在 PowerShell 確認 `$env:CL` 為空（`Remove-Item Env:CL -ErrorAction SilentlyContinue`），並先刪該 worktree 的 `app\build\windows`，執行 `flutter build windows --debug`。預期失敗，且錯誤與字碼頁／無法開啟含中文字元的原始碼有關；把前 20 行錯誤存 scratchpad。若**成功**，代表這個問題已不存在：停止本 Task，在報告記「`/utf-8` 問題在 3.47.9 已不需處理」，跳到 Task 5。
- [ ] **Step 2: 實作。** 在 `windows/CMakeLists.txt` 的 `project(...)` 之後、`add_subdirectory` 之前加 `if(MSVC) add_compile_options(/utf-8) endif()`，附中文註解（繁中 Windows 字碼頁 950 會讓含 UTF-8 中文的原始碼出錯，見 epic.md 決策 27）。不要碰 `generated_plugins.cmake`。
- [ ] **Step 3: 驗證（綠）。** 同 Step 1（`$env:CL` 仍為空、刪 `build\windows`）重建，預期 `Built build\windows\x64\runner\Debug\elinkbook.exe`。再設 `$env:CL='/utf-8'` 重建一次，預期仍成功（不衝突）。
- [ ] **Step 4: Commit。**

```bash
git add app/windows/CMakeLists.txt
git commit -m "build(windows): CMake 加 /utf-8，免手動設 CL 環境變數（epic-66 Issue 6 Task 4）"
```

---

### Task 5：`desktop_drop` 升到 0.9.2

**Files:**
- Modify: `app/pubspec.yaml`（`desktop_drop: 0.8.4` → `0.9.2`，維持固定版本、不用 `^`）、`app/pubspec.lock`（只收 `desktop_drop` 相關行）
- Test: `app/test/screens/support/import_drop_target_test.dart`

**Interfaces:**
- Consumes: `ImportDropTarget`（`app/lib/screens/support/import_drop_target.dart`）對 `desktop_drop` 的現有用法。

- [ ] **Step 1: 基準。** `flutter test test/screens/support/import_drop_target_test.dart` 預期全過。
- [ ] **Step 2: 升級。** 改 `pubspec.yaml`，`flutter pub get`，`git diff -- pubspec.lock` 確認只有 `desktop_drop`（與其必要連動的平台套件）變動；其餘還原。
- [ ] **Step 3: 驗證。** `flutter analyze lib/screens/support/import_drop_target.dart test/screens/support/import_drop_target_test.dart` 預期乾淨（API 相容）；`flutter test test/screens/support/import_drop_target_test.dart` 預期全過。若 `DropTarget` 的參數或回呼型別有破壞性變更，停下來看變更說明，只做讓既有行為不變的最小修改，並在帳本記 ruling。
- [ ] **Step 4: Commit。**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "chore(deps): desktop_drop 升到 0.9.2（epic-66 Issue 6 Task 5）"
```

---

### Task 6：Android 與 Windows 建置驗證

**Files:**
- 無異動；結果寫入報告。

- [ ] **Step 1: Android debug 建置。** 在 `app/` 執行 `flutter build apk --debug`，輸出存 scratchpad；預期 `✓ Built build\app\outputs\flutter-apk\app-debug.apk`。把所有 warning（尤其 AGP、Kotlin、Gradle、`flutter_inappwebview_android` 本機修補相關）逐條記進報告，分「僅警告」與「失敗」。失敗就停下來回報，不要靠改 AGP／Kotlin 版本硬解，那屬另一個決定。
- [ ] **Step 2: Windows debug 建置。** 依 Global Constraints 的建置說明，`flutter build windows --debug`（Task 4 完成後不必設 `CL`），預期成功。
- [ ] **Step 3: 全專案分析與全套測試。** `flutter analyze` 預期只剩 `use_null_aware_elements` 這 1 個 info（`onReorder` 那個已消失）；全套 `flutter test` 預期 5119 個（基準 5118 加 Task 3 的 1 個）、0 失敗。

---

### Task 7：Windows 開書冒煙、政策文件與報告（需人在電腦前、螢幕解鎖）

**Files:**
- Modify: `CLAUDE.md`（「常用指令」的 Flutter 版本段落）、`docs/epics/epic-66-windows-port/epic.md`（新增決策 28）、`docs/epics/epic-66-windows-port/issues.md`（Issue 6 狀態列）、本檔（勾選步驟）
- Create: `docs/epics/epic-66-windows-port/issue-6-report.md`

- [ ] **Step 1: Windows 開書冒煙。** 以 Task 6 建的 Windows debug 版，用 Issue 11 的實驗腳本（scratchpad 的 `run_open_book_experiment.ps1`，只留一個版本資料夾，`-Rounds 5`）冷啟動 5 次、每次自動還原上次的書，記錄 `已渲染`／`開書逾時` 與耗時。預期 5／5 成功；與 Issue 11 的 3.47.4 結果（約 14～18 秒）比較。實驗期間請使用者不要操作電腦。
- [ ] **Step 2: 更新 `CLAUDE.md`。** 把「採用 Flutter 3.41.9」段落改為 3.47.9，刪除「`ReorderableListView.onReorderItem` 在 3.41.9 不存在」的警告與舉例（改為「不要使用此版本沒有的較新 API」的通則，不再舉該例），保留「升級 Flutter 版本前需先與人類確認」。只改這一段。
- [ ] **Step 3: 新增 `epic.md` 決策 28。** 記錄：升級到 3.47.9 的理由（3.47.8 安全公告 GHSA-frr6-h895-5pxp、3.47.6 Windows 卡死修正）、使用者選擇直接升級共用 SDK、`C:\src\flutter-3.41.9` 保留作回退、`pdfrx`／`file_picker`／`window_manager` 大跳版不在本 Issue、回退點 `9584c6713b`。
- [ ] **Step 4: 寫 `issue-6-report.md`。** 內容：本計畫的診斷與決策表、各 Task 結果、Task 6 的 Android 警告清單、Task 7 的冒煙紀錄、回退指令、未驗證項目（Android 真機、`desktop_drop` 在 Windows 實機拖曳、Impeller 下 WebView2 長時間使用）。
- [ ] **Step 5: 同步文件並勾選。** `issues.md` Issue 6 狀態改為「✅ 實作完成，待 PR」；本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [ ] **Step 6: Commit。**

```bash
git add CLAUDE.md docs/epics/epic-66-windows-port/epic.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/issue-6-report.md docs/epics/epic-66-windows-port/plans/plan-issue-6.md
git commit -m "docs(epic-66): Issue 6 驗證報告、Flutter 版本政策與進度同步"
```

---

## Self-Review

- **範圍涵蓋：** `issues.md` Issue 6 範圍的各項——SDK 升級（Task 1）、回歸基準（Task 2）、`onReorder`（Task 3）、`/utf-8`（Task 4）、`desktop_drop`（Task 5）、Android／AGP／Windows 建置（Task 6）、Impeller 下 WebView2（Task 7 Step 1）、政策文件（Task 7）。
- **型別一致：** 本計畫只新增 `_onReorder` 的語意註解與 CMake 選項，沒有新名稱。
- **比例：** 只列簽章、指令、預期輸出。
- **已知風險：**（a）Task 1 動的是共用 SDK，回退指令已寫但未演練；（b）Task 4 的 Step 1 若發現問題已不存在，Task 就以「不需要」收尾；（c）沒有 Android 裝置，Android 只到建置成功；（d）Task 7 需要人在電腦前；（e）`pdfrx` 2.4.7→2.12.0 可能還有效能或 API 改進，刻意不在本 Issue 做，列為後續。
