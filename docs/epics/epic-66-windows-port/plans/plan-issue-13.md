# Issue 13：Windows `integration_test` 冒煙測試套件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 上用 `flutter test integration_test/… -d windows` 跑出一組可重複、依序執行的冒煙測試，涵蓋每種格式的「開書、翻頁、劃線」，並有一支只准單份執行的跑測腳本。不建 CI（epic 決策 9）。

**Architecture:** 不從零寫。2026-11-09 已在這台機器上單獨、依序把 27 支現有整合測試跑過一遍（基準線，見下表）：多數在 Windows 本來就能跑。做法：（1）用一支跑測腳本固定「一次只跑一支、跑前確認沒有殘留行程與記憶體夠」；（2）把失敗的檔案分成「Windows 產品問題」「測試假設 Android」「Windows 畫面差異」三類逐一處理；（3）對照「格式 × 動作」矩陣，補沒有覆蓋的格子；（4）定出套件清單，全數通過才算完成。

**Tech Stack:** Flutter 3.47.9、`integration_test`、`flutter_inappwebview`（WebView2）、PowerShell（跑測腳本）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 13 範圍／過關條件／單元測試要求」（本計畫一併新增）；`epic.md` 決策 9。

## 基準線（2026-11-09，`main` `0f4b0ccc`，Windows 11，單份依序執行；乾淨結果）

通過（20）：`smoke_test`、`foliate_epub_reader_view_test`（10）、`pdf_highlights_notes_test`、`foliate_txt_test`（3）、`foliate_md_test`、`foliate_cbz_test`（3）、`foliate_kf8_test`（2）、`epub_pagination_test`（2）、`epub_dual_page_test`（2）、`fxl_bookmarks_test`、`notes_bookmark_test`（2）、`pdf_nav_zone_test`（2）、`reader_footer_test`、`reading_position_test`（2）、`foliate_navigation_degrade_test`（2）、`foliate_single_column_test`（2）、`foliate_stream_nav_zone_test`、`foliate_margin_test`（3）、`markdown_export_test`。

失敗（8 個檔案）與初步原因（尚未診斷根因，以下是失敗訊息，不是結論）：

| 檔案 | 結果 | 失敗訊息 |
|---|---|---|
| `epub_fxl_tap_zone_test` | 0/1 | 渲染完成後 `FoliateReaderView.onError` 回報「無法載入書籍」（此測試直接建構 `FoliateReaderView`，不經 `ReaderScreen`，樹上沒有 `reader_error_text`） |
| `foliate_toc_footer_test` | 1/4 | 同上，3 次「無法載入書籍」 |
| `pdf_reader_view_test` | 3/4 | 1 次「無法載入書籍」（`onPageRendered` 未觸發）。**線索（未驗證的假設，Task 2 要先證實）：** `pdf_reader_view.dart:862` 用 `filePath.contains('://')` 判斷 `content://`，若測試傳入 `file:///C:/...` 會被誤導向 Android 專屬的 `_openContentUriDocument()`。同樣寫法也在 `foliate_native_bridge.dart:179`，一併檢視。 |
| `epub_toc_test` | 0/2 | 預期不存在的文字「第一節」卻找到 |
| `epub_highlights_notes_test` | 0/1 | `tap()` 找不到目標 widget |
| `foliate_highlights_notes_test` | 1/2 | 找不到 `reader_settings_text_conversion_traditional` |
| `reader_screen_test` | 9/19 | 逾時、`tap()` 找不到 widget |
| `library_screen_test` | 0/3 | `MissingPluginException: createTestContentUri`（Android 專屬原生方法） |

另有 Windows 專用目錄 `windows_spike/`、`windows_metadata/`、`windows_leak/`、`windows_webview2/` 未在本次基準線內，歸 Issue 3、4 等前置工作使用。

## 格式 × 動作 覆蓋矩陣（依基準線；✓＝Windows 已有通過的測試，✗＝失敗，—＝尚無）

| 格式 | 開書 | 翻頁 | 劃線 |
|---|---|---|---|
| EPUB 流式 | ✓ `foliate_epub_reader_view_test` | ✓ `foliate_stream_nav_zone_test` | ✓ `foliate_highlights_notes_test`（第 1 個） |
| EPUB 固定版面（FXL） | ✓ `fxl_bookmarks_test` | ✗ `epub_fxl_tap_zone_test` | 不適用（FXL 規格不支援劃線，維持空狀態；見 `fxl_bookmarks_test.dart:130`，已有斷言） |
| PDF | ✓ `pdf_highlights_notes_test` | ✓ `pdf_nav_zone_test` | ✓ `pdf_highlights_notes_test` |
| TXT | ✓ `foliate_txt_test` | — | — |
| MD | ✓ `foliate_md_test` | — | — |
| CBZ | ✓ `foliate_cbz_test` | ✓（同檔 RTL 導覽測試） | 不適用（圖片） |
| AZW3（KF8） | ✓ `foliate_kf8_test` | — | — |

## Global Constraints

- Flutter 3.47.9；`flutter analyze` 乾淨；不新增相依（`pubspec.lock` 不得變動）。
- **跑測規則（硬性）：** Windows 整合測試**一次只准一份**；不得用 `&`、`nohup` 掛背景；跑前確認沒有殘留的 `elinkbook.exe`、`flutter_tester.exe`、`MSBuild.exe`、測試用 `dart`／`dartvm`（保留 VS Code 的 `language-server`）；可用記憶體低於 4 GB 就停止並回報。2026-11-09 因同時跑了 8 份而耗盡記憶體，被系統中止（這是本 Issue 的起因之一）。
- 建置：若 `nuget.exe` 不在 PATH，把它所在目錄加到 PATH **尾端**（例如 `$env:Path += ";$env:USERPROFILE\bin"`，該目錄內有個叫 `flutter` 的檔案，不可放前面）；`CL=/utf-8`；在 Git Bash 設 `CL` 要加 `MSYS_NO_PATHCONV=1`，否則會被轉成路徑而建置失敗。建置失敗後先刪 `app\build\windows` 再重試。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動；`git add` 一律明確列檔。
- 不得為了讓測試過而放寬斷言或刪測試。Android 專屬的測試用平台守門「略過並寫明原因」，不是刪除。
- 不新增、不修改任何 ARB 字串；產品程式只在「診斷出 Windows 產品問題」時才改，且須先有重現的失敗測試。
- 所有測試在 Windows 以外（Android 真機）的行為不得改變：守門只在 `Platform.isWindows` 時略過。
- 實驗腳本與暫存輸出放 scratchpad，不放進專案。

## Review Focus

1. 跑測腳本必須真的防止並行與殘留：已有另一份在跑時拒絕啟動；測完一支就確認該支的視窗行程已結束再跑下一支。（Task 1）
2. 「無法載入書籍」是真的 Windows 產品問題還是測試假設？若是產品問題（FXL 在 Windows 打不開會直接影響使用者），不能只改測試遮掉。（Task 2）
3. 略過 Android 專屬測試時，不得連帶略過 Android 上的執行；守門條件與原因要寫在測試裡。（Task 4）
4. 補的新測試必須在改動前先看到它失敗或確認它真的在驗東西（TDD）；「通過」不能只是因為斷言太弱。（Task 5）
5. 套件清單要明列於版本控制內的檔案；清單裡的每一支都必須在最終一次完整、依序的執行中通過，報告要附結果。（Task 1、6）
6. 報告不得外推：只有這台機器、debug 版、WebView2 為本機版本的結果，沒有乾淨機器、沒有 release。（Task 6）

---

### Task 1：Windows 整合測試跑測腳本與套件清單

**Files:**
- Create: `app/integration_test/windows_smoke_suite.txt`（每行一個測試檔名，`#` 開頭為註解；初版放基準線中已通過的檔案）
- Create: `app/tool/run_windows_smoke.ps1`
- Modify: `app/tool/README.md`（補一小節說明）

**Interfaces:**
- Produces: `powershell -File tool/run_windows_smoke.ps1 [-Suite integration_test/windows_smoke_suite.txt] [-TimeoutSec 420] [-MinFreeMB 4096]`；結束碼 0＝全數通過；輸出每支一行 `名稱 通過/失敗/逾時 ::（最後一行進度）`，並在 scratchpad 或 `build/windows_smoke/` 留下每支的完整輸出。

- [ ] **Step 1: 寫腳本。** 行為：
  - （a）**路徑與鎖檔：** 一律以 `$PSScriptRoot` 為基準（無論在倉庫根或 `app/` 執行都指向 `app/build/windows_smoke/`）；建鎖檔前先 `New-Item -ItemType Directory -Force`；鎖檔用獨佔檔案流（`[System.IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')`）持有 handle 到腳本結束，作業系統在行程結束時自動釋放，**不用 PID 判斷**（避免 Windows PID 重用誤判）；開檔失敗＝已有另一份在跑，立刻拒絕並說明。
  - （b）開跑前列出殘留行程（`elinkbook`、`flutter_tester`、`MSBuild`、命令列含 `flutter_tools` 的 `dart`／`dartvm`，排除 `language-server`），有就中止並列出，**不自行終止**。
  - （c）可用記憶體低於 `-MinFreeMB`：先等 10 秒重量一次（前一支剛結束時 WebView2 還在回收），仍不足才中止並回報。
  - （d）逐支 `flutter test <檔> -d windows`；逾時（`-TimeoutSec`）後用 `taskkill.exe /PID <測試行程PID> /T /F` 終止**整棵行程樹**（只殺頂層行程會留下孤兒 `elinkbook.exe`／`dart.exe`）。
  - （e）每支結束後輪詢等 `elinkbook.exe` 消失，上限 15 秒；超過就記錄警示並對**本腳本自己啟動的**殘留執行 `taskkill /IM elinkbook.exe /F`（開跑前 (b) 已確認原本沒有其他實例），不得無限等待。
  - （f）一支失敗不中止後續，最後彙總並以非 0 結束。
- [ ] **Step 2: 驗證腳本本身。** 用只含 `smoke_test.dart` 的臨時清單跑一次，預期通過、結束碼 0；開第二個終端機同時再跑一次，預期立刻拒絕並說明；人為留一個殘留 `flutter_tester` 時預期中止；`-TimeoutSec 5` 強制逾時一次，預期跑完後沒有任何 `elinkbook.exe`／`dart` 測試行程殘留（證明行程樹有被殺乾淨）；在 `build/` 不存在的乾淨工作區跑一次，預期不因目錄不存在而失敗。（腳本沒有單元測試框架，以這三個實際執行輸出為證，記入報告。）
- [ ] **Step 3: 建立套件清單。** 先放基準線已通過的 20 個檔案，失敗的 8 個先不放，改在清單尾端以註解列出並註明所屬 Task。
- [ ] **Step 4: `app/tool/README.md` 補說明；`flutter analyze` 不涉及（無 Dart 變動）。**
- [ ] **Step 5: Commit。**

```bash
git add app/integration_test/windows_smoke_suite.txt app/tool/run_windows_smoke.ps1 app/tool/README.md
git commit -m "test(windows): 整合測試跑測腳本（單份依序、防殘留、防記憶體不足）與套件清單（epic-66 Issue 13 Task 1）"
```

---

### Task 2：診斷「無法載入書籍」（FXL 翻頁、目錄頁尾、PDF）

**Files:**
- 依診斷結果而定：`app/integration_test/epub_fxl_tap_zone_test.dart`、`foliate_toc_footer_test.dart`、`pdf_reader_view_test.dart`，或產品程式；診斷紀錄寫入 `docs/epics/epic-66-windows-port/issue-13-report.md`（本 Task 先建檔）。

**Interfaces:** 無新介面。產出是「每個失敗屬於哪一類」的結論與修復。

- [x] **Step 1: 重現並取得根因。** 依 `superpowers:systematic-debugging`：單獨跑 `epub_fxl_tap_zone_test`，確認每次都失敗（至少 3 次）；渲染日誌顯示「已渲染」之後才出現錯誤，所以先找出 `onError` 是誰在何時呼叫（`epub_fxl_tap_zone_test` 與 `foliate_toc_footer_test` 的錯誤來源要分開查：前者直接建構 `FoliateReaderView`，後者是否經 `ReaderScreen` 先確認；`pdf_reader_view_test` 先驗證 `pdf_reader_view.dart:862` 的 `contains('://')` 假設，看測試傳入的路徑形式）、Windows 的 loopback 書檔伺服器與 WebView2 在該時間點的行為。**不得在根因查明前改程式。** 用 `flutter test` 的日誌或暫時的 `debugPrint`（診斷用，完成後移除，不 commit）。
- [x] **Step 2: 分類並記錄。** 三種結果：（A）測試假設 Android（例如用 `/data/local/tmp`、`content://`）→ 在 Task 4 處理；（B）Windows 產品問題 → 先寫一個重現的失敗測試（紅），再最小修復（綠），修復前先停下來告知使用者：這會改產品程式，範圍是否可接受；（C）Windows 時序差異 → 修測試的等待條件（不得只加長逾時掩蓋，要等實際條件）。把每個失敗的分類與證據寫進報告。
- [x] **Step 3: 套用修復；三個檔案各單獨跑 3 次全過。**
- [x] **Step 4: 通過的檔案加進套件清單。**
- [x] **Step 5: Commit（依實際異動檔案明確列出）。**

---

### Task 3：診斷畫面找不到 widget 的失敗（目錄、劃線備註、閱讀器畫面）

**Files:**
- 依診斷結果而定：`app/integration_test/epub_toc_test.dart`、`epub_highlights_notes_test.dart`、`foliate_highlights_notes_test.dart`、`reader_screen_test.dart`。

- [x] **Step 1: 逐檔找原因。** 優先檢查：Windows 視窗尺寸（預設比手機寬，版面可能走不同分支，例如平板／桌面側欄）；Issue 10 在 Windows 隱藏的設定項（`reader_settings_text_conversion_traditional` 是否被隱藏或被捲到畫面外）；測試用手機尺寸的點擊座標。每個失敗都要有證據（截取 widget 樹的 `debugDumpApp` 輸出片段或日誌），不憑猜測。
- [x] **Step 2: 分類。** 同 Task 2：（A）測試假設行動裝置畫面 → 在測試內為 Windows 設定與手機相同的視窗尺寸（`tester.view`），或改用不依賴座標的 Key；（B）產品在 Windows 缺了功能 → 先停下來告知使用者；（C）時序 → 修等待條件。
- [x] **Step 3: 套用修復；各檔單獨跑 3 次全過。** `reader_screen_test` 有 19 個測試，逐個列出仍失敗的，**不要求全數修好**：未修好的在報告中列為已知缺口並登記為後續 Issue，不放進套件清單。
- [x] **Step 4: 能過的檔案加進套件清單。**
- [x] **Step 5: Commit。**

---

### Task 4：Android 專屬測試的平台守門

**Files:**
- Create: `app/integration_test/windows_skip.dart`（`skipOnWindows(String reason)` helper）；`app/test/` 內新增一支掃描守門寫法的小測試。
- Modify: `app/integration_test/library_screen_test.dart`，以及 Task 2、3 分類為 A 類且確定是 Android 專屬的檔案。

- [x] **Step 1: 確認守門寫法。** 已查證：`integration_test/` 內沒有既有的 `Platform.isAndroid`／`skip:` 慣例；且 Flutter 的 `testWidgets` 的 `skip` 型別是 `bool?`（`widget_tester.dart:151`），**不能傳字串**（`Platform.isWindows ? '原因' : false` 會讓 `flutter analyze` 失敗）。改用 helper：新增 `app/integration_test/windows_skip.dart`（檔名不以 `_test.dart` 結尾，不會被當成測試跑）：`bool skipOnWindows(String reason)`，`assert(reason.trim().isNotEmpty)` 後回傳 `Platform.isWindows`。測試寫成 `testWidgets('名稱', skip: skipOnWindows('createTestContentUri 只存在於 Android 原生'), ...)`。
- [x] **Step 2: 套用。** 只加守門，不改測試本體；在 Windows 上確認顯示「略過」而非失敗；寫一個小的、不需要裝置的檢查（`test/` 內掃描 `integration_test/`：每個 `skipOnWindows(` 呼叫的引數必須是非空字串字面值；且不得出現裸的 `skip: Platform.isWindows`）避免之後出現沒寫原因的略過。
- [x] **Step 3: Android 側確認。** 本 Task 不能在沒有手機時驗證 Android 行為，所以守門只可用 `Platform.isWindows` 為條件；程式審查時以此為檢查項，報告註明「Android 未重跑」。
- [x] **Step 4: Commit。**

---

### Task 5：補格式 × 動作矩陣的空格

**Files:**
- Create: `app/integration_test/windows_smoke_formats_test.dart`（TXT、MD、AZW3 各一組：開書後翻頁；寫入預先準備的 CFI 劃線後在筆記面板看得到）；若 FXL 翻頁仍失敗，補在 Task 2。FXL 劃線不適用，不補。

- [ ] **Step 1: 先確認每格該驗什麼。** 前置：TXT／MD 不能直接開原始檔，須比照 `foliate_txt_test`／`foliate_md_test` 先用 `BookImportServiceImpl.importFiles()` 匯入合成 EPUB3，再把產出的 `book.filePath` 交給閱讀器（ADR 0023）；AZW3 沿用 `foliate_kf8_test` 的樣本與開法。翻頁：以 `ReaderScreen` 渲染，`tester.tap(find.byKey(const Key('nav_zone_2')))` 觸發下一頁，斷言 `reader_footer_progress_text` 的文字改變（可比照 `epub_toc_test.dart:65` 的 `_pumpUntilProgressChanged`，該函式目前是該檔私有，需複製或抽出到共用 helper），且沒有 `reader_error_text`。劃線：WebView 內無法用 Flutter 手勢選字（既有測試註解已說明），所以比照 `foliate_highlights_notes_test` 以倉庫預先寫入 CFI 劃線，再開 `NotesBottomSheet` 確認顯示。每個格子在計畫階段先確認「測試要斷言的具體值」，寫在測試註解裡。
- [ ] **Step 2: 寫失敗測試。** 先寫斷言，並做一次變異驗證：暫時讓翻頁函式不動作或劃線不寫入，確認測試會失敗（紅），再還原。
- [ ] **Step 3: 實作。** 只有測試與必要的 fixture（TXT／MD／AZW3 樣本沿用 `foliate_txt_test`、`foliate_md_test`、`foliate_kf8_test` 已用的檔案）。
- [ ] **Step 4: 單獨跑 3 次全過；加進套件清單。**
- [ ] **Step 5: Commit。**

---

### Task 6：完整依序執行、報告與文件

**Files:**
- Create/Modify: `docs/epics/epic-66-windows-port/issue-13-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 13 狀態）、`docs/epics/epic-66-windows-port/epic.md`（若有新決策）、本檔（勾選步驟）、`docs/epics.md`（備註）

- [ ] **Step 1: 全數執行。** 確認無殘留行程後，以 `tool/run_windows_smoke.ps1` 對整份套件清單跑**一次**，保存輸出。
- [ ] **Step 2: 判讀。** 清單內必須全數通過；有失敗就回到對應 Task，不得從清單移除來湊過關。重跑一次確認不是偶發（同一支連續失敗才算真失敗，偶發要註明並記錄頻率）。
- [ ] **Step 3: 全套 `flutter test` 與 `flutter analyze`。**（本 Issue 若只動了 `integration_test/` 與腳本，仍須確認 `flutter analyze` 乾淨；全套 `flutter test` 在發 PR 前跑一次，既有偶發失敗照實記錄。）
- [ ] **Step 4: 寫 `issue-13-report.md`。** 內容：基準線表、每個失敗的診斷與處理、最終矩陣（每格對應的測試檔）、套件清單與最終執行結果、已知缺口與後續 Issue、跑測規則與 2026-11-09 並行事故。
- [ ] **Step 5: 更新文件並勾選本檔步驟。**
- [ ] **Step 6: Commit。**

---

## 已知風險

- 「無法載入書籍」可能是真的 Windows 產品問題（尤其 FXL）；若是，修復會動到產品程式，範圍與時程要與使用者另議。
- Windows 整合測試會開真實視窗並佔用這台機器，執行期間不能做別的操作；單份依序執行，全套約 20～30 分鐘。
- 多數 WebView 內的互動（選字、拖曳控點）無法由 Flutter 手勢驅動，所以「劃線」只能驗證預先寫入的標記能顯示，**不是**驗證使用者在畫面上選字劃線。報告必須明講。
- 沒有乾淨機器與 release 版驗證；結果只代表這台、debug 版。
- `reader_screen_test`（19 個）可能有多個真正的 Windows 差異；本計畫不保證全數修好。
