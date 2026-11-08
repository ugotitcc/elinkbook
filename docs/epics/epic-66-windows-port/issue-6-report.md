# Issue 6：Flutter 升級至 3.47.9 驗證報告

- **對應 Issue**：`epic-66` Issue 6
- **實作分支**：`feat/epic-66-issue-6-flutter-upgrade`
- **計畫**：[plan-issue-6.md](plans/plan-issue-6.md)（審查：`reviews/review-plan-issue-6.md`、`reviews/review-plan-issue-6-round2.md`，不進版控）

## 結論（先看這裡）

1. 共用 SDK `C:\tools\flutter` 已從 3.47.4 升到 **3.47.9**（Dart 3.13.3 → 3.13.7）。這台機器其實早從 2026-10-23 起就是 3.47.4，`CLAUDE.md` 寫的 3.41.9 早已過時，所以這個 Issue 實質上是「升到含安全公告修補的最新 patch，並把政策文件對齊現況」。
2. **只換 SDK、不改程式時沒有回歸：** `pub get` 鎖檔無變動、`analyze` 與基準相同、全套測試 5118 個 0 失敗。
3. `onReorder` 已改 `onReorderItem`；Windows 建置不再需要手動設 `CL=/utf-8`。
4. Android 與 Windows debug 建置都成功；**Android 另已在一支真機（WAVE，Android 12，WebView 91）上原地升級安裝並實測**：啟動正常、冷啟動自動還原開書成功、同一次啟動內連開同一本 EPUB 5 次全部成功、PDF 可開，沒有崩潰（見下方「Android 真機驗證」）。
5. `desktop_drop` **維持 0.8.4**（0.9.x 要求的 `cross_file ^0.4.0` 與 `file_picker`、`share_plus` 衝突），已登記 Issue 16，不排程；不做也不會壞任何東西。
6. **新發現：** Flutter 3.47.9 警告 **Gradle 8.14.0（需 ≥ 9.1.0）與 AGP 8.11.1（需 ≥ 9.0.1）的支援「即將移除」**，目前仍可建置；已登記 Issue 17，不排程。
7. Windows 冷啟動開書 5／5 成功；使用者實機拖曳匯入 a～e 全部通過。
8. 最終審查（獨立審查員）：沒有 Critical；1 個 Important（過關條件 8 字面上沒達成，已在 `issues.md` 狀態列註明）；3 個 Minor 已記入帳本。

## 診斷與決策

| 項目 | 事實 |
|---|---|
| 這台機器的預設 Flutter | `C:\tools\flutter` = 3.47.4（修改於 2026-10-23）；Git Bash 的 `~/bin/flutter` 只是轉呼叫它 |
| 3.47.8 | **安全公告 GHSA-frr6-h895-5pxp**：Dart 執行環境的 BoringSSL 封鎖被入侵的 eMudhra 中繼 CA 憑證；Android 14+ 的 `dart:io` 改用可更新的 Conscrypt 根憑證庫。本專案有 HTTPS 連線（同步、雲端匯入、線上查詞） |
| 3.47.6 | 修正「Windows 正式版 App 會卡死」（flutter/192513） |
| `flutter upgrade` 的阻礙 | `C:\tools\flutter` 有 119 筆 untracked，`flutter upgrade` 對 stable 只要 `git status -s` 輸出非空就拒絕，所以用 `--force`（只做 `git reset --hard`，untracked 不受影響）。它第二階段會在目前工作目錄的專案跑 `pub get --upgrade`，所以必須從專案外目錄執行 |
| 使用者決定 | 直接升級共用的 `C:\tools\flutter`；`desktop_drop` 不在本 Issue 升級，另立 Issue 16 |

## 各 Task 結果

- **Task 1（升級共用 SDK）：**
  - 升級前：沒有 `flutter`／`dart`／`flutter_tester` 程序、`C:\tools\flutter` 無 tracked 修改（119 筆 untracked）、分支 `stable`、HEAD `9584c6713b`；`git ls-remote` 確認遠端 `stable` 與標籤 `3.47.9` 同為 `c197ca5199e9`。
  - 升級：從 `C:\Users\huthief` 執行 `flutter upgrade --force`，耗時約 3.2 分鐘。
  - 升級後：`Flutter 3.47.9`、`Dart 3.13.7`、channel `stable`、HEAD `c197ca5199e`、**未 detached**、tracked 仍無修改；`flutter doctor` 與升級前逐項一致（Android toolchain SDK 36.1.0、Visual Studio Build Tools 17.14.44 皆 ✓）；本 worktree 的 `pubspec.lock` 未被動到。
- **Task 2（只換 SDK 的回歸基準）：** `flutter pub get` 鎖檔無變動；`flutter analyze` 仍是 2 個 info（`onReorder` 棄用、`use_null_aware_elements`）；全套 `flutter test` **5118 個，0 失敗**。
- **Task 3（`onReorder` → `onReorderItem`）：** 新增 3 個「往後拖」測試（拖到最後一格 → `[b, c, a]`、往後一格 → `[b, a, c]`、原地放開不呼叫 reorder），先在 `onReorder` 版本上通過，改實作後 65／65 全過，`analyze` 乾淨。其中「往後一格」用一次 `tester.drag` 到位時拖曳列表來不及更新插入位置，依計畫備案改為分段 `startGesture`／`moveBy`。**變異驗證：** 故意把 `if (newIndex > oldIndex) newIndex -= 1;` 放回去，新測試立刻失敗，還原後通過，證明這些測試抓得到差 1 的錯誤。
- **Task 4（`/utf-8`）：** 紅燈：未設 `CL`、刪 `build\windows`，建置 exit=1，`connectivity_plus_plugin.cpp` 的 C4819 被 `/WX` 升為 C2220，`flutter_inappwebview_windows` 的 `base64.cpp` 也有 C4819。綠燈：在 `windows/CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})` 之前加 `if(MSVC) add_compile_options(/utf-8) endif()` 後，未設 `CL`、重刪 `build\windows` 重建 exit=0；再設 `CL=/utf-8`、再次重刪重建 exit=0，兩者不衝突。
- **Task 5（`desktop_drop`）：** 維持 0.8.4，鎖檔無變動；`pubspec.yaml` 的註解改為說明衝突原因與 Issue 16；`window_manager` 的過時註解（原寫「升級見 Issue 6」）一併更正（版本不變）；`issues.md` 登記 Issue 16 與 Issue 17。
- **Task 6（建置驗證）：** Android debug 建置 exit=0（約 10 分鐘，APK 237 MB）；Windows debug 建置在 Task 4 完成；全專案 `analyze` 剩 1 個 info（`use_null_aware_elements`，不是本次造成）；全套 `flutter test` 5121 個，1 個偶發失敗（見 Rulings）。
- **Task 7：** Windows 冷啟動 5／5 成功；實機拖曳 a～e 全通過；`CLAUDE.md` 與 `epic.md` 決策 28 已更新。

## Android 建置警告清單（3.47.9，第一次在 3.47.x 上建置）

| 警告 | 類別 | 說明 |
|---|---|---|
| Flutter 對專案 Gradle 版本 8.14.0 的支援「即將移除」，要求 ≥ 9.1.0 | 僅警告 | 可用 `--android-skip-build-dependency-validation` 略過；專案目前仍可建置 |
| Flutter 對專案 AGP 8.11.1 的支援「即將移除」，要求 ≥ 9.0.1 | 僅警告 | 同上；`settings.gradle.kts` 的 `com.android.application` 版本 |
| `Note: Some input files use or override a deprecated API` | 僅提示 | 某個 Java 編譯單元，非本專案程式 |
| `Note: Some input files use unchecked or unsafe operations` | 僅提示 | 同上 |
| `78 packages have newer versions incompatible with dependency constraints` | 僅提示 | `pub get` 常態訊息 |

沒有失敗。依計畫沒有為了消除警告而改 AGP／Kotlin／Gradle 版本，那屬另一個決定（Issue 17）。**這與審查員說的「在支援範圍內」不同：目前只是「還能建置」，Flutter 已明確預告會移除支援。**

## Windows 冷啟動開書冒煙（Flutter 3.47.9，debug 版）

自動還原上次的同一本 EPUB，標準輸出導到檔案，等 `已渲染` 或 `開書逾時` 標記（上限 90 秒）。

| 輪 | 書複製 ms | 頁面載入完成 ms | 已渲染 ms（距開書） | 從啟動起算 |
|---|---|---|---|---|
| 1 | 956 | 1199 | 14824 | 21.2 秒 |
| 2 | 1221 | 1608 | 11869 | 16.0 秒 |
| 3 | 1808 | 2415 | 12918 | 16.5 秒 |
| 4 | 2137 | 2806 | 13513 | 17.4 秒 |
| 5 | 1352 | 1751 | 13392 | 16.5 秒 |

- 「已渲染」距開書中位數 13.4 秒（11.9～14.8 秒），與 Issue 11 在 3.47.4 上的結果（約 11～14 秒）相當。
- **結論限定為「冷啟動開書 5／5 成功」，不外推到 Impeller 下 WebView2 長時間使用。** 輸出顯示 Windows 使用 `Impeller rendering backend (OpenGLESSDF)`，3.47.4 時也是。
- 這同時驗證 `desktop_drop` 0.8.4 在 3.47.9 引擎上沒有 0.9.1 修過的那種 Windows 啟動崩潰（5 次都正常啟動；樣本小，偶發崩潰未必抓得到）。
- stdout 有一行 `Failed to read WebView version: MissingPluginException(… getDefaultUserAgent …)`：Windows 讀 WebView 版本失敗。**3.47.4 的輸出也有，是既有問題，不是本次造成**，App 退回預設行為。

## Android 真機驗證（2026-11-08，使用者接上裝置後由我操作）

**裝置：** Allwinner **WAVE**（E-Ink 閱讀器），Android 12（API 31），`armeabi-v7a`（32 位元 arm），Android System WebView **91.0.4472.114**，E-Ink 模式開啟，可用儲存 25 GB。

**安裝方式（保護既有資料）：**
- 手機上原本就裝了同一個套件 `cc.ugotit.elinkbook`（debug 版，versionCode 3、versionName 1.1.0，2026-11-05 更新），內有使用者的書庫（`app_flutter/library.db` 180 KB、`dictionary.db` 24 KB、8 個匯入書檔、E-Ink 偏好）。
- 先確認：同包名、同 versionCode、同為 debug，可原地升級；資料庫版本 29，`sqlite_library_repository.dart` 自 2026-11-04 起沒改過，不會降版。
- **先備份**（`run-as` 取出 `library.db`、`dictionary.db`、`shared_prefs`，驗證 SQLite 檔頭與 tar 完整）到 scratchpad（`issue6\android_backup\`，不進版控；內含 `FlutterSecureStorage.xml` 等，請視為敏感資料，用完可刪）。
- 再用 `adb install -r`（**不解除安裝**）原地升級：`Success`，`library.db` 大小與時間不變。

**結果：**

| 步驟 | 結果 | 距開書 |
|---|---|---|
| 安裝後第一次啟動（自動還原上次閱讀的《論語聖訓(三)》） | 已渲染；程序存活，無 `FATAL EXCEPTION`／ANR | 12909 ms |
| 準備：從書架點《論語聖訓(三)》（讓它成為最後閱讀） | 已渲染 | 8309 ms |
| **冷啟動**（強制停止後重新啟動，自動還原） | 已渲染（從 `am start` 起算 33.2 秒，含 App 啟動） | 12354 ms |
| 同一次啟動內第 2 次開同一本 EPUB | 已渲染 | 8077 ms |
| 第 3 次 | 已渲染 | 6943 ms |
| 第 4 次 | 已渲染 | 7988 ms |
| 《2018_仙佛聖訓_歸根》（PDF，`pdfrx`） | `PdfDocument initial load` 1.6 秒，成功 | — |
| PDF 之後再開同一本 EPUB（第 5 次） | 已渲染 | 7730 ms |

- 全程程序存活、沒有崩潰；沒有任何「開書逾時」。
- **與記憶中的「二次開書逾時」相關：** 這支手機（WebView 91）正是該症狀的裝置。本次同一次啟動內連續重開同一本 4 次、PDF 之後再開，**都沒有重現逾時**。這只代表「在這個 debug 版、這批操作下沒發生」，不證明該問題已解決（原問題的觸發條件仍未查明）。
- 日誌的 `載入錯誤 HOST_LOOKUP net::ERR_INTERNET_DISCONNECTED` 是手機沒網路時某個外部資源載入失敗，出現在「已渲染」**之前**，不是終點事件，不影響開書。
- 日誌有 `Failed to read WebView version: TimeoutException after 3s`（讀 WebView 版本逾時），App 使用偏好中快取的 `webview_major_version=91`；啟動時另有 `Using the Impeller rendering backend (Vulkan)` 接著 `(OpenGLES)`（Vulkan 失敗後退回 OpenGLES）。這些是否為 3.47.9 新增沒有基準可比（安裝前沒有保留舊日誌）。

**作廢的兩次測試（如實記錄）：** 我的測試腳本前兩版有錯：第一版把 `載入錯誤` 當成終點事件而在 3 秒就按返回；第二版用固定座標點書，但書架依「最後閱讀」排序，開過書後排列會變，結果點到別本（PDF）。這兩版的結果全部作廢，第三版改用 `uiautomator` 讀出書名定位後才取得上表的數據。

**副作用：** 測試期間反覆開關書，使用者的閱讀位置有些微更新（書架上《論語聖訓(三)》的進度由 16% 變成 15%）。

**沒做的：**
- 沒跑 `integration_test`（會以測試殼層執行 App，可能動到手機上的書庫資料）。
- 沒測詞典拖曳排序（`onReorderItem`）：手機上沒有 2 本以上的詞典，單元測試已涵蓋。
- 沒測分享、匯入、雲端、TTS、設定畫面等其他功能；只有啟動與開書。
- 沒有 release 版；這是 debug 版，行為可能與 release 不同。
- 只有這一支裝置、一種架構（`armeabi-v7a`）。

## Windows 實機拖曳匯入（使用者回報）

使用者以 3.47.9 的 Windows debug 版，在書架分頁依序拖入並回報：

| 項目 | 結果 |
|---|---|
| a. 1 個書檔 | 通過 |
| b. 同時 2 個書檔 | 通過 |
| c. 1 個含書檔的資料夾 | 通過 |
| d. 1 個不支援格式 | 通過 |
| e. 匯入進行中再拖一次 | 通過 |

只有使用者的「全部通過」回報，沒有逐項畫面紀錄。

## 回退

```powershell
git -C C:\tools\flutter reset --hard 9584c6713b   # 留在 stable 分支，不要 checkout 到標籤（會 detached）
flutter --version
flutter doctor
```

兩版引擎不同（`06a2e2a1…` ↔ `89c39edf…`），Dart 3.13.3 ↔ 3.13.7，**回退會重新下載引擎與 Dart SDK，需要網路**，舊引擎快取不保留。回退沒有演練過。`C:\src\flutter-3.41.9` 仍保留。

## Rulings

- **Task 5：** 一併更正 `pubspec.yaml` 裡 `window_manager` 的過時註解（原寫「0.6.0 要求 Flutter >= 3.47.7，升級見 Issue 6」，但 Issue 6 明訂不升）。只是註解，若判斷錯誤成本是一行文字。
- **Task 6 Step 3：** 全套 5121 個有 1 個失敗（`download_queue_controller_test`「刪除原暫存檔失敗不影響進入待確認」），不視為回歸：單獨重跑該檔 3 次全過（28／28）；Issue 9 報告已記錄此測試為「全套磁碟 I/O 負載下偶發、單獨執行全過」；Task 2（3.47.9）與 Issue 11 基準的全套都沒有它失敗；與本 Issue 的改動無關。若判斷錯誤，成本是 Issue 6 的基準仍有此偶發失敗。

- **Android 真機：** 手機上已有同包名 debug 版與使用者書庫，先備份資料庫與偏好檔，再用 `adb install -r` 原地升級，**不解除安裝**。若判斷錯誤（簽章不同導致需解除安裝），成本是失去手機上的書庫資料；實際上安裝成功、資料庫未動。
- **Android 真機：** 不跑 `integration_test`（可能動到書庫資料）；只做啟動與開書這類不改資料的操作。

## 未驗證與已知限制

- **Android 只在一支裝置（WAVE，Android 12，`armeabi-v7a`，WebView 91）上做了安裝、啟動與重複開書；沒有跑 `integration_test`、沒有 release 版、沒有測其他功能。**
- Impeller 下 WebView2 長時間使用的行為。
- 回退指令沒有演練過。
- `desktop_drop` 維持 0.8.4（Issue 16）。
- Gradle 8.14.0／AGP 8.11.1 即將不被 Flutter 支援（Issue 17）。
- `pdfrx` 2.4.7→2.12.0、`file_picker` 11→13、`window_manager` 0.5.2→0.6.0 的大跳版沒有處理。

## 後續（皆不排程）

- **Issue 15：** `pdf_reader_view_filters_test.dart` 加粗覆蓋圖偶發失敗查根因。另有 `download_queue_controller_test` 在全套負載下偶發，可併入同類處理。
- **Issue 16：** `desktop_drop` 0.9 與 `cross_file` 0.4 遷移。
- **Issue 17：** Android 建置工具升級（Gradle ≥ 9.1.0、AGP ≥ 9.0.1、built-in Kotlin）。

## 驗證結果

- `flutter analyze`：全專案只剩 1 個 info（`use_null_aware_elements`，不是本次造成）。
- 全套 `flutter test`：5121 個，1 個偶發失敗（單獨 3／3 全過）。
- 帳本與原始輸出在 scratchpad（`issue6\`），不進版控。
