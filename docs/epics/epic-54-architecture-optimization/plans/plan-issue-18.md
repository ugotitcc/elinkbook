# Issue 18：Issue 17 遷移後 `TCL 14` 仍失敗的 5 個 integration 檔案——逐項判定與處置 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 對 Issue 17 遺留的 5 個 `integration_test/` 檔案（共 7 組失敗），逐項判定「測試過期／行為改變／產品缺陷／真機校準」，**經使用者拍板後**再處置，讓 `TCL 14` 上的 integration 全數通過，或把無法通過的項目明確登記成獨立缺陷工單。

**Architecture：** 本 Issue 是**判定型工單**，不是單純遷移。每個 Task 固定三段：(A) 跑真機取得失敗證據、(B) 對照 `lib/` 與設計文件寫出「判定報告」並**停下來等使用者決定**、(C) 依決定修改。使用者尚未回答前，不得改 `lib/`、不得改測試（全域 CLAUDE.md 第 8 條）。判定報告寫在 `reviews/triage-issue-18.md`（gitignore、不進版控），結論摘要回寫 `epic.md`。

**Tech Stack：** Flutter／Dart、`integration_test`、`adb`、Node（既有守衛腳本）。指令一律在 `app/` 目錄下執行（除非另有標明）。

**Spec：** 沒有獨立 `spec.md`。缺陷描述見 `docs/epics/epic-54-architecture-optimization/issues.md` 第 18 列；證據見 `epic.md`「Issue 17 實作完成與真機驗證結果」與「Issue 17 程式審查回應」；前一張工單做法見 `plans/plan-issue-17.md`（尤其其「過期或真缺陷判定規則」，本計畫沿用）。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **先判定、後動手**：每個 Task 的 (B) 段必須產出判定報告並**等使用者回答**，才能進 (C)。回答前不改 `lib/`、不改測試斷言。
- **不放寬測試**：不得為了通過而刪斷言、加 `skip`、把 `findsOneWidget` 改成 `findsWidgets`、把等式改成「非 null」。要刪或弱化斷言，必須在報告中列出「舊斷言在驗證什麼、新介面是否仍有此行為」，並取得使用者**明確**同意（Issue 17 程式審查 M-1 教訓：不得寫「使用者決定」除非對話中確有此決定，且須在 `epic.md` 記錄原話出處）。
- **逾時秒數不調大**：Issue 16 已證明等待時間不是根因。
- **`tapMaxDurationMs` 校準**：EPUB（Foliate）的 700ms 是 `epic-25` Issue 1 真機校準值；PDF 的 700ms 是 `epic-31` 刻意對齊、未經真機驗證的決定，**PDF 端不得逕自沿用 EPUB 數值**（`CLAUDE.md`「不可逆的技術決策」原文）。本 Issue 涉及的是 EPUB 端：若要改 Foliate 門檻，須依真機資料，且 Dart（`foliate_reader_view.dart:884`）與 JS（`main.js:962`）**兩端同步修改**；PDF 端不在本 Issue 範圍。
- **指令執行環境**：本計畫所有指令區塊以 **Bash 工具（Git Bash）** 為準，不是 PowerShell（`export`、`time`、`for … do`、`tail`、`grep` 皆為 Bash 語法）。若改在 PowerShell 執行，須自行換成等效寫法（`$env:MSYS_NO_PATHCONV = "1"`、`foreach`、`Select-Object -Last`），計畫不重複提供兩套。
- **真機**：`TCL 14`（序號 `3CEF42ECD491687`，Android 15）。結果只宣稱此裝置通過。執行前須向使用者確認可清除該裝置上的 `cc.ugotit.elinkbook` 資料。
- **adb**：`adb` 不在 PATH，路徑為 `C:\Users\fycdc\AppData\Local\Android\Sdk\platform-tools\adb.exe`（Git Bash：`/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe`）。今日（2026-10-07）已實測 push 約 26 MB／s、pull 約 35 MB／s，屬 USB 2.0 正常值，不需重啟；若 `adb shell echo hi` 超過 1 秒，才 `adb kill-server` 再 `adb start-server`。Git Bash 執行 adb 前先 `export MSYS_NO_PATHCONV=1`。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試。完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，必須在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了 `lib/` 的 Key 或 `integration_test/` 後跑 `node tool/check_integration_keys.js`；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具。多數原始檔是 CRLF，`Edit` 的定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。

## 已查證的事實（計畫撰寫時對照 `lib/` 所得，執行者開工前須再確認一次）

| 項目 | 事實 | 出處 |
|---|---|---|
| (2) `isFixedLayout` 誤報 | `FoliateReaderView` 在 `onPageRendered` 回呼裡**寫死** `EpubLayoutInfo(isFixedLayout: false, ...)`。**此值有消費端**（計畫初稿誤寫「無人讀取」，經審查 I-2 更正）：`ReaderScreen._handleFoliateLayoutResolved` 在 `widget.isFixedLayout != true` 時執行 `_isFixedLayout = info.isFixedLayout`，而 `_isFixedLayout` 決定劃線／備註 repository 是否傳入、`onLayoutTap` 分派、FAB 主題色、FXL 書籤載入等（`reader_screen.dart` 約 1497／1529／1545／2441／3089-3124）。`widget.isFixedLayout == true`（匯入時已寫入的 FXL／CBZ 書）受保護不會被覆寫；**`widget.isFixedLayout` 為 `null` 或 `false` 但實際為 FXL 的路徑（舊書尚待 `detectAndCacheEpubLayout()`、強制 FXL 之外的情境）會被蓋成 `false`**。同檔 1820-1827 的文件註解稱「方法內部目前不依賴 `info.isFixedLayout` 做任何分支」與實際程式不符，已過期 | `lib/reader/foliate_reader_view.dart:675-676`、`reader_screen.dart:521-560,1833-1835` |
| (5-前提) 測試樣本書只有 1 頁 | `test/fixtures/sample_fixed_layout.epub` 的 `content.opf` spine 只有 `chapter1` 一個 itemref（全書 5 個檔案、1 個內容頁）。在唯一一頁上呼叫 `nextPage()`，Foliate 沒有下一頁可跳，不會有新的 `relocate`，`locatorJson` 不會變，**`epub_fxl_tap_zone_test` 的「點下一頁後 locatorJson 應變動」斷言可能天生不成立，與熱區時長無關**（審查 I-1）。尚未在真機驗證，需 Task 5 Step 1 先確認 | `test/fixtures/sample_fixed_layout.epub`、`integration_test/epub_fxl_tap_zone_test.dart:94-99` |
| (5-契約) 700ms 在 Dart 與 JS 各有一份 | Dart：`foliate_reader_view.dart:884`、`pdf_reader_view.dart:1771`；JS：`main.js:962` 的 `ANNOTATION_CLICK_TAP_MAX_MS = 700`（`main.js:1434` 註解明言與 Dart 端「維持兩側一致」）。改 Foliate 的門檻必須兩端同步 | `foliate/main.js:962,1434` |
| (2) 對應測試 | 期望 FXL 範例回報 `isFixedLayout` 為 true | `integration_test/foliate_epub_reader_view_test.dart:425-456` |
| (3) 頁尾 | 失敗的測試是 **EPUB（Foliate）** 案例，不是 PDF（與 `epic.md`／`issues.md` 的描述不完全相符，Task 3 需更正）。Foliate 底部工具列的頁尾由 `_buildFoliateEpubFooter()` 建構，**不看 `showFooter`**；`showFooter` 只控制工具列收合時螢幕角落的 `reader_foliate_progress_text` | `reader_screen.dart:2432,2899`；`reader_screen.dart:2250` 的文件註解明言「`showHeader`／`showFooter` 偏好只控制 `_chromeVisible == false` 時邊角常駐文字」 |
| (3) PDF 頁尾 | PDF 的 `ReaderFooter` 只在 `_chromeVisible` 且非裁切編輯模式時出現，不看 `showFooter` | `reader_screen.dart:2838-2865` |
| (5) 熱區 | 兩端 `TapZoneDetector` 的 `tapMaxDurationMs` 都是 700；偵測器內仍有 `[DEBUG-e26i3]` 除錯 log，可用來取得真機 `elapsed`／`distance` 資料 | `foliate_reader_view.dart:884`、`pdf_reader_view.dart:1771`、`tap_zone_detector.dart:135-148` |

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **把「疑產品缺陷」改測試改到變綠，缺陷被掩蓋。** → 每個 Task 的 (B) 段必須明列「若判為缺陷，使用者可選擇登記獨立工單而非改測試」，不得預設改測試。
2. **改了 `epic.md` 的錯誤描述卻沒更正，後人沿用。** → Task 3 明確更正「PDF 頁尾」→「EPUB 頁尾（PDF 另有覆蓋缺口）」。
3. **熱區測試的失敗其實是樣本書只有 1 頁，卻被當成門檻校準問題，白做校準甚至改錯門檻。** → Task 5 Step 0 先驗樣本書頁數。另：改門檻只改 Dart 不改 `main.js`，會破壞兩端一致性。
3b. **熱區門檻校準只在 `TCL 14` 一台，換裝置就翻車。** → Task 5 若建議改門檻，報告須註明樣本量、裝置與手指速度範圍，並由使用者決定是否改（數值決策屬使用者）。
4. **`reader_screen_test` 全檔跑會有 `database_closed` 連帶噪音，誤判為新失敗。** → 一律用 `--plain-name` 隔離單一案例驗證。
5. **為了通過手動裁切測試而改點擊座標，掩蓋裝置座標相關的真問題。** → Task 4 先量測實際元件位置再比對，座標改動須有量測依據。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `docs/epics/epic-54-architecture-optimization/reviews/triage-issue-18.md` | 新增（gitignore） | 7 組失敗的判定報告與使用者決定紀錄 |
| `app/integration_test/epub_toc_test.dart` | 視判定修改 | 目錄展開行為 |
| `app/integration_test/foliate_epub_reader_view_test.dart` | 視判定修改 | `isFixedLayout` 斷言 |
| `app/integration_test/reader_header_footer_toggle_test.dart` | 修改 | `showFooter` 現行語意斷言，另補 PDF 覆蓋 |
| `app/integration_test/reader_screen_test.dart` | 視判定修改 | FXL 版面按鈕、智慧重開、手動裁切 |
| `app/integration_test/epub_fxl_tap_zone_test.dart` | 視判定修改 | FXL 熱區翻頁 |
| `app/lib/**` | **僅在使用者明確決定修缺陷時**才改 | 產品缺陷修復 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 結果與狀態 |

---

### Task 0：建立基準與判定報告骨架

**Files:**
- Create: `docs/epics/epic-54-architecture-optimization/reviews/triage-issue-18.md`

**Interfaces:**
- Produces: 判定報告檔，後續 Task 1～6 各自在其中追加一節。

- [x] **Step 1: 確認裝置與 adb 延遲**（實測 0.1s，`3CEF42ECD491687` 在線）

```bash
export MSYS_NO_PATHCONV=1
ADB=/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe
time $ADB shell echo hi
$ADB devices -l
```
預期：一秒內回應，且列出 `3CEF42ECD491687`。超過 1 秒則 `kill-server`／`start-server` 後重試。

- [x] **Step 2: 向使用者確認可清除 `TCL 14` 上的 `cc.ugotit.elinkbook` 資料**（2026-10-07 對話已明確同意）

取得明確同意後才執行；未同意則整個計畫停在此步。

- [x] **Step 3: 建立 worktree 與分支**（`.worktrees/epic-54-issue-18`，分支 `epic-54/issue-18-integration-triage` 自 `main`）

分支名 `epic-54/issue-18-integration-triage`，從最新 `main` 開，沿用專案既有的 `.worktrees/` 慣例（在主 repo 根目錄執行，之後所有指令都在 worktree 內進行，不要在主目錄切分支）：

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-18 -b epic-54/issue-18-integration-triage main
cd .worktrees/epic-54-issue-18/app
```

- [x] **Step 4: 取得 5 檔失敗基準**（4 檔與 `epic.md` 一致，見 ledger；`reader_screen_test` 逐案隔離延至 Task 4 Step 1）

```bash
cd app
for f in epub_toc_test foliate_epub_reader_view_test reader_header_footer_toggle_test epub_fxl_tap_zone_test; do
  flutter test integration_test/$f.dart -d 3CEF42ECD491687 2>&1 | tail -40 > ../.scratch/baseline_$f.txt
done
```
`reader_screen_test` 因有級聯噪音，改用 `--plain-name` 逐案跑（見 Task 4）。基準輸出放 worktree 根的 `.scratch/`（untracked）。預期結果與 `epic.md` 記載一致（`epub_toc_test` 與 `epub_fxl_tap_zone_test` 0 通過；`foliate_epub_reader_view_test` 9/10；`reader_header_footer_toggle_test` 1/2）。若出現不同，**先停下回報**，不進入後續 Task。

- [x] **Step 5: 建立報告骨架並提交**（`reviews/` gitignored，無需 commit）

骨架只含標題與 7 個空小節（對應 Task 1～6），因 `reviews/` 在 gitignore，此步不需 commit。

---

### Task 1：`epub_toc_test`——目錄展開行為

**Files:**
- Read: `app/integration_test/epub_toc_test.dart:85-`
- Read: `app/lib/screens/` 與 `app/lib/reader/` 內目錄 Sheet 與展開邏輯（`BookTocItem` 相關）
- Test（視判定修改）: `app/integration_test/epub_toc_test.dart`

**Interfaces:**
- Consumes: Task 0 的基準輸出。
- Produces: 判定結論之一——「設計（改測試）／缺陷（登記工單）／測試本身設定錯誤」。

- [x] **Step 1: 讀測試完整流程並逐步標出每個斷言在驗證什麼**

重點：(a) 開書後哪些目錄項目應可見；(b) 點目錄項目後預期「第一節」消失的理由；(c) 測試用的 `sample_multi_chapter.epub` 目錄結構（解壓後讀 `nav.xhtml`／`toc.ncx`）。

- [x] **Step 2: 查現行目錄展開規則**（設計來源 epic-5-issue4：`0128e36c`、`c801ce2d`；progression 鏈 main.js→fromWire→findCurrentPath；log 印 progression＋currentProgression）

在 `lib/` 內搜尋目錄 Sheet 的初始展開邏輯（「路徑展開」是 `epic.md` 描述的現行設計）。確認：開書當下依目前閱讀位置展開到哪一層；點項目後是否關閉 Sheet、是否收合。以 `git log -S` 找出該行為的來源 commit 與對應 Epic 設計文件，作為「這是設計」的證據。

特別檢查 `lib/reader/toc_navigator.dart` 的 `TocNavigator.findCurrentPath`：它走訪整棵目錄樹，**只要節點的 `progression <= currentProgression` 就把該節點當成「目前所在」**（後走訪者覆蓋前者），再據此展開其祖先。因此開書當下第二章被展開，最可能的成因是第二章的 `progression` 為 0.0 或與第一章同值（`buildTocEntry` 回報的 fraction 不準），或開書當下 `currentProgression` 已大於第二章的值。Step 3 的暫時性 log 須同時印出每個目錄項的 `progression` 與傳入的 `currentProgression`，據此區分「演算法設計如此」與「`progression` 計算有誤」。

- [x] **Step 3: 在真機補一次實測並截圖／記錄**（兩次＋pm clear，暫時性 log 已還原，工作區乾淨）

跑 `epub_toc_test` 並在失敗點前加暫時性 `debugPrint` 列出所有目前可見的目錄文字（**僅暫時，不 commit**），確認實際可見集合。

- [x] **Step 4: 寫判定報告並停下來等使用者決定**（`reviews/triage-issue-18.md` §(1)；**已停止，未改測試**）

報告必須含：舊斷言意圖、現行行為、證據、三種處置選項（改測試為現行語意／登記缺陷／其他）與建議。**不得自行改測試。**

- [x] **Step 5（取得決定後）: 依決定修改，並在真機驗證**（決定丙；測試改寫＋issues.md 新增 Issue 19；真機 PASS，待 commit）

若改測試：新斷言強度不得低於舊斷言（例如「點後某節不可見」→「點後 Sheet 關閉且閱讀位置確實跳到該章」）。跑：

```bash
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
```
預期：PASS。若判為缺陷：不改測試，於 `issues.md` 新增獨立缺陷 Issue，並把本測試註明為已知失敗、連結新工單。

- [x] **Step 6: Commit**

```bash
git add app/integration_test/epub_toc_test.dart docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "test(epic-54): epub_toc_test 依判定結果處置（Issue 18）"
```

---

### Task 2：`foliate_epub_reader_view_test`——`isFixedLayout` 誤報

**Files:**
- Read: `app/lib/reader/foliate_reader_view.dart:660-690`、`app/lib/reader/writing_mode.dart`（`EpubLayoutInfo`）
- Test（視判定修改）: `app/integration_test/foliate_epub_reader_view_test.dart:425-456`
- Lib（**僅在使用者決定修缺陷時**）: `app/lib/reader/foliate_reader_view.dart:675-676` 及 `main.js` 的 `onPageRendered` 參數

**Interfaces:**
- Consumes: 已查證事實表 (2)。
- Produces: 「`onLayoutResolved.isFixedLayout` 這個欄位的定位」決定：保留並修正、或保留但文件化為不可靠、或移除。

- [x] **Step 1: 列出 `info.isFixedLayout` 的消費端與受影響行為**（消費端與覆寫路徑皆以程式碼證實；`widget.isFixedLayout==null`＋實 FXL 會被蓋成 false）

```bash
cd app
grep -rn "onLayoutResolved\|EpubLayoutInfo\|\.isFixedLayout" lib test --include=*.dart | grep -v "^lib/l10n"
```
已知消費端（審查 I-2）：`reader_screen.dart:1833-1835` 的 `_isFixedLayout = info.isFixedLayout`（`widget.isFixedLayout != true` 時）。接著列出 `_isFixedLayout` 的所有讀取處（約 1497／1529／1545／2441／3089-3124）與各自的錯誤行為（FXL 書被當成流式：劃線 repository 誤傳、版面按鈕走錯 Sheet、FXL 書籤不載入、主題色錯誤）。再逐一確認哪些**開書路徑**會讓 `widget.isFixedLayout` 為 `null`／`false` 而書實為 FXL（`_resolveEpubEngineDispatch` 的非同步偵測分支、`isFixedLayoutHint` 與 `Book.isFixedLayout` 不一致時），用單元／widget 測試或真機實測證明至少一條路徑真的會被蓋成 `false`。證明不了＝降為「潛在缺陷」並如實寫入報告，不得宣稱已證實。

- [x] **Step 2: 查歷史**（`8e760653` 契約 → `15f2a6eb` 沿用寫死 → epic-20 前提失效，迴歸根源）

`git log -S"isFixedLayout: false" -- lib/reader/foliate_reader_view.dart` 找出何時寫死、當時理由（ADR 0017／0023 將 FXL 判定改由 `Book.isFixedLayout` 決定）。

- [x] **Step 3: 檢查 `main.js` 的 `onPageRendered` 是否其實有帶 FXL 資訊**（JS 端知 `view.isFixedLayout`，`main.js:1113` 目前只傳 writingMode，低成本可取）

讀 `app/android/app/src/main/assets/foliate/main.js` 內呼叫 `onPageRendered` 處，確認可否低成本取得真實 `isFixedLayout`（`view.isFixedLayout`，`epub_position_info.dart:22` 的文件提到 `main.js` 依 `view.isFixedLayout` 分支組裝位置資訊，表示 JS 端知道）。

- [x] **Step 4: 寫判定報告並停下來等使用者決定**（`reviews/triage-issue-18.md` §(2)；選項 A 前提已被證偽，剩乙修 lib／丙立工單；**已停止，未改 lib/測試**）

選項至少三個，由使用者擇一：
- B（建議，因 `info.isFixedLayout` 有消費端）：欄位必須準確 → 修 `lib/`（Dart 端依 JS 回報或 `isFixedLayoutHint` 填值；或讓 `_handleFoliateLayoutResolved` 不再用它覆寫 `_isFixedLayout`，改以 `_dispatchedIsFixedLayout` 為準），並同步更正 `reader_screen.dart:1820-1827` 過期註解；測試維持原斷言。
- C：登記獨立缺陷工單，本測試先註明已知失敗。
- A（僅在 Step 1 證明**沒有任何開書路徑**會被覆寫成 `false` 時才成立）：欄位實質無作用 → 刪測試斷言並改用「可觀察的 FXL 行為」取代（例如 `displayTotalPages` 為全書真實視覺頁數且位置資訊走 FXL 分支），強度不低於原斷言；欄位本身另案清理。

- [x] **Step 5（取得決定後）: 依決定修改，先紅後綠**（決定乙；parse＋單元測試 RED→GREEN；test/reader/ 全過除 1 既存失敗；真機 10/10，待 commit）

若選 B：先確認測試目前為紅（已知），再寫最小修改，補純 Dart／widget 測試涵蓋：「FXL hint 為 true／false／null」三種輸入下回報值，以及「`widget.isFixedLayout == null` 且實為 FXL 時，`_isFixedLayout` 不被蓋成 `false`」。跑：

```bash
flutter test test/reader/ -r compact
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
```
預期：單元測試 PASS，真機 10/10 PASS。同時跑 `flutter analyze` 與 `node tool/check_integration_keys.js`。

- [x] **Step 6: Commit**（明確路徑；`ee9cfed0` fix，依實際處置）

---

### Task 3：`reader_header_footer_toggle_test`——`showFooter=false` 現行語意

**Files:**
- Modify: `app/integration_test/reader_header_footer_toggle_test.dart:111-176`
- Read: `app/lib/screens/reader_screen.dart:2250,2432,2838-2865,2899`
- Docs: `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`（更正「PDF 頁尾」描述）

**Interfaces:**
- Consumes: 已查證事實表 (3)。
- Produces: 兩個以上「現行語意」案例，覆蓋 EPUB 與 PDF 在 `showFooter=false` 時的頁尾行為（補 Issue 17 程式審查 M-2 缺口）。

- [x] **Step 1: 確認設計意圖**（明文依據 `reader_screen.dart:2250`；工具列頁尾 `:2430-2432` 不看 showFooter，收合角落 `:2898-2900` 才看）

讀 `reader_screen.dart:2243-2255` 的文件註解與 `epic-38-reader-chrome-tts-redesign` 的 spec，確認「`showFooter` 只控制工具列收合時的角落常駐頁尾」是明文設計。找不到明文依據則依判定規則第 3 條停下回報。

- [x] **Step 2: 寫判定報告並停下來等使用者決定**（`reviews/triage-issue-18.md` §(3)；建議三條新斷言＋PDF 覆蓋與否；**已停止，未改測試**）

事實：失敗案例是 EPUB；工具列可見時底部頁尾（`reader_footer`）恆顯示，與 `showFooter` 無關，這與 `reader_screen.dart:2250` 的設計註解一致 → 判為「測試過期」。需使用者確認的是：**新斷言要驗什麼**。建議的三條（強度不低於舊案例的整體意圖「頁尾受 `showFooter` 控制」）：
1. EPUB、`showFooter=false`、工具列可見：`reader_footer` 存在。
2. EPUB、`showFooter=false`、工具列收合：角落 `reader_foliate_progress_text` **不存在**。
3. EPUB、`showFooter=true`、工具列收合：`reader_foliate_progress_text` 存在（對照組，證明第 2 條不是因為根本沒資料）。

另需使用者決定：PDF 是否也要補「`showFooter=false` 時工具列可見仍有頁尾」的案例（M-2）。

- [x] **Step 3（取得決定後）: 先寫失敗的測試（突變確認會咬人）**（決定 OK＋PDF；突變隔離證實案例 2 失敗、對照組通過；整檔同跑的對照組失敗為連帶污染；突變已還原；真機 4/4，待 commit）

在測試檔中把原案例改寫為上述三條。為證明斷言有效，暫時把 `reader_screen.dart:2899` 的條件 `(_resolved?.showFooter ?? false)` 改成 `true`，跑測試應在第 2 條失敗；**還原後**再跑。突變只是本機驗證，不得 commit。

```bash
flutter test integration_test/reader_header_footer_toggle_test.dart -d 3CEF42ECD491687
```
預期（突變中）：第 2 條失敗並印出 `reader_foliate_progress_text` 存在；（還原後）全部 PASS。

- [x] **Step 4: 更正文件**

`epic.md` 與 `issues.md` 第 18 列中「PDF 的 `ReaderFooter` 只受 `_chromeVisible` 控制」改成「失敗案例為 EPUB；PDF 頁尾同樣不受 `showFooter` 影響，另有覆蓋缺口」，避免後人誤判。同時同步 `reader_header_footer_toggle_test.dart` 內該案例的 `testWidgets` 名稱與檔頭註解（現名稱「已持久化 showFooter=false 開 EPUB 書後，頁尾不顯示…」與現行語意相反），使測試名稱、註解、`reader_screen.dart:2250` 設計註解三處語意一致。

- [x] **Step 5: `flutter analyze`、`check_l10n_hardcoded_strings.js`、`check_integration_keys.js` 皆通過後 Commit**

---

### Task 4：`reader_screen_test`——三組失敗

**Files:**
- Test（視判定修改）: `app/integration_test/reader_screen_test.dart:176`（FXL 版面按鈕）、`:755`（智慧重開）、`:816`／`:865`（手動裁切）及 `manual→manual` 案例（約 `:937`）
- Read: `app/lib/reader/pdf_reader_view.dart`（裁切流程）、`app/lib/screens/reader_chrome_bottom_bar.dart`
- Lib（**僅在使用者決定修缺陷時**）

**Interfaces:**
- Consumes: `epic.md` 失敗清單；Issue 17 已把設定按鈕改為 `reader_chrome_layout_button`。
- Produces: 三組各自的判定與處置。

- [x] **Step 1: 以 `--plain-name` 逐案跑，取得乾淨的失敗清單**

```bash
flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687 --plain-name "開啟定樣式範例 EPUB，⚙️版面按鈕最終不顯示"
```
對 19 個案例各跑一次（或至少對 6 個失敗案例，並隨機抽 2 個通過案例確認基準）。預期失敗者與 `epic.md` 一致；若有差異，停下回報。

- [x] **Step 2: (4-a) FXL 版面按鈕**

舊斷言：FXL 範例開書後 ⚙️ 版面按鈕「最終不顯示」。新工具列的 `reader_chrome_layout_button` 恆顯示（FXL 與 PDF 皆走 `onLayoutTap`）。查 Epic 38 設計與 `FxlSettingsSheet`：FXL 是否本來就該有版面設定入口。判定報告建議：改為斷言「FXL 範例的版面按鈕點開後出現的是 `FxlSettingsSheet`（非 `ReaderSettingsSheet`）」，強度不低於原案（原案只驗不存在，新案驗存在且正確）。**等使用者確認。**

- [x] **Step 3: (4-b) 智慧重開 `pdfCropRect` 崩潰（疑引擎問題）**

重現後取得完整堆疊（`adb logcat -d | grep -n "maxScale"`）。確認崩潰是否出自 pdfrx 內 `maxScale >= minScale` 斷言，並找出觸發的 `pdfCropRect` 值與頁面尺寸。查 `pdf_reader_view.dart` 套用裁切矩形算出縮放的位置，判斷是否我們傳入了退化矩形（寬或高趨近 0）導致。另須檢視 `lib/reader/pdf_fit_size_delegate.dart:132-150` 的 `calculateMetrics`：`strictMinScale` 為 true 時 `minScale` 直接取 `zoom`，而 `maxScale` 取 `metrics.maxScale`；`_zoomFor` 已用 `maxZoom: kPdfFitMaxZoom`（8.0）箝位，所以「`zoom` 超過 `maxScale`」只在 `metrics.maxScale` 實際小於 8.0 時才會發生（審查 M-2 的假說，未證實）。實測時於崩潰前印出 `zoom`、`metrics.minScale`、`metrics.maxScale` 三個值再下結論；若證實，防禦性箝位（`math.min(zoom, metrics.maxScale)`）屬改 `lib/`，須使用者同意。**若是我方傳入退化值＝產品缺陷，不是引擎問題**，須於報告明說。處置選項：登記獨立缺陷工單／在套用前做合法性檢查（改 `lib/`，需使用者同意）。**不得為了讓測試通過而改測試。**

- [x] **Step 4: (4-c) 手動裁切確認與 `manual→manual`**

先量測再比對，不要憑感覺改座標：測試在 `tester.tapAt` 之前，印出確認鈕實際 `tester.getCenter(...)` 與螢幕尺寸（暫時性 log）。確認「確認鈕後設定面板未出現」是座標點偏、元件被遮蓋、或確認後流程本來就不再開面板（查 Epic 38 設計）。報告列出三種可能性的證據與建議，**等使用者決定**。

- [x] **Step 5（取得決定後）: 逐案修改並以 `--plain-name` 隔離驗證**

每改完一案就跑該案；全部完成後整檔跑一次，允許有 `database_closed` 級聯噪音，但需逐項確認失敗名單為空或為已登記工單的項目。

- [x] **Step 6: Commit**（若修了 `lib/` 與測試，分成兩個 commit：先修缺陷＋單元測試，再改 integration 測試）

---

### Task 5：`epub_fxl_tap_zone_test`——熱區翻頁與 `tapMaxDurationMs` 校準

**Files:**
- Read: `app/lib/reader/tap_zone_detector.dart`、`app/lib/reader/foliate_reader_view.dart:870-900`
- Test: `app/integration_test/epub_fxl_tap_zone_test.dart`
- Fixture（視判定新增）: `app/test/fixtures/sample_fxl_multi_page.epub`（需 2 頁以上的固定版面 EPUB，並在 `pubspec.yaml` 宣告為 asset）
- Lib（**僅在使用者決定改校準值時**）: `app/lib/reader/foliate_reader_view.dart:884` **與** `app/android/app/src/main/assets/foliate/main.js:962`（`ANNOTATION_CLICK_TAP_MAX_MS`，兩端必須同值）

**Interfaces:**
- Consumes: 偵測器內 `[DEBUG-e26i3]` log 欄位 `elapsed`、`distance`、`qualified`、`reason`。
- Produces: 「按下到放開耗時的真機分布」資料表，供使用者決定是否調整 700ms。

- [x] **Step 0（最優先，審查 I-1）: 確認樣本書是否只有 1 頁**（屬實：spine 僅 `chapter1`；校準調查依計畫不進行，700ms 不動）

```bash
unzip -p test/fixtures/sample_fixed_layout.epub OEBPS/content.opf | grep -n "itemref\|spine"
```
計畫撰寫時查到 spine 只有 `chapter1` 一個 itemref。若屬實，測試「點下一頁後 `locatorJson` 應變動」在全書唯一一頁上**天生無法成立**，失敗根因是測試素材，與熱區時長無關，後面 Step 1～4 的校準調查不必進行。此時處置選項（等使用者決定，**不得自行擇一**）：
  - (甲) 新增 2 頁以上的 FXL fixture（`sample_fxl_multi_page.epub`），測試改用它，斷言維持「真的換頁」，強度不降。
  - (乙) 維持單頁書，把斷言改成「在唯一一頁點下一頁不崩潰、`onError` 不觸發、位置不變」。**這會弱化原測試意圖（驗證真的換頁）**，須使用者明確同意並記錄原話。
  - (丙) 兩者並存：原測試改用多頁書，另加一個單頁邊界案例。
  若 Step 0 證明樣本書其實不只 1 頁（例如 FXL 單一 spine 項目內含多頁），則此步結論作廢，繼續 Step 1。

- [x] **Step 1: 確認失敗是否真的與時長有關，而非別的原因**（不適用——Step 0 已確認單頁書即根因；基準輸出已證明分派成功、九宮格出現，見報告 §(5)）

```bash
$ADB logcat -c
flutter test integration_test/epub_fxl_tap_zone_test.dart -d 3CEF42ECD491687
$ADB logcat -d | grep "DEBUG-e26i3" > ../.scratch/tapzone_log.txt
```
（不適用，同上。）

- [x] **Step 2: 比對 EPUB 流式的同類測試**（不適用，同上）

- [x] **Step 3: 若為結論 1，另做真手指取樣（需使用者配合）**（不適用，同上）

- [x] **Step 4: 寫判定報告並停下來等使用者決定**（`reviews/triage-issue-18.md` §(5)；甲多頁 fixture／乙弱化斷言／丙並存；**已停止，未改測試**）

選項：(A) 結論 1 且真手指也超時 → 調整門檻（數值由使用者定，需同時說明對誤觸長按選字的影響）；(B) 只有測試注入太慢 → 改測試的點擊方式（例如縮短 `tester.press`／`pump` 間隔），門檻不動；(C) 結論 2 或 3 → 登記獨立缺陷工單。

- [x] **Step 5（取得決定後）: 依決定修改並驗證**（決定甲；多頁 fixture＋測試改用；真機 PASS，待 commit）

若改門檻：**Dart 與 JS 兩端同步修改**——`foliate_reader_view.dart:884` 的 `tapMaxDurationMs`，以及 `main.js:962` 的 `ANNOTATION_CLICK_TAP_MAX_MS`（連同 `main.js:1434` 的註解），否則 JS 端的「畫線點擊 vs 熱區翻頁」消歧義門檻與 Dart 端不一致，可能讓 `epic-25` 已修復的手勢競態復發。提交前以 `grep -n "700" app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_reader_view.dart` 確認兩端數值一致。（注意：`node tool/check_foliate_es_compat.js` 掃的是釘定的 foliate-js vendor 程式碼的 ES 相容性，不涵蓋這個門檻，不能拿它當同步檢查。）另在 `CLAUDE.md`「不可逆的技術決策」段落補一句新的校準依據（只在確實改了數值時才改這份檔案）。跑：

```bash
flutter test test/reader/tap_zone_detector_test.dart -r compact
flutter test integration_test/epub_fxl_tap_zone_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_stream_nav_zone_test.dart -d 3CEF42ECD491687
```
預期全部 PASS（最後一個確認 EPUB 流式不回歸）。

- [x] **Step 6: 移除暫時性 debug log 與否由使用者決定**

`[DEBUG-e26i3]` 是既有 log，**不在本 Issue 範圍內刪除**；僅在報告中提醒其仍存在。

- [x] **Step 7: Commit**

---

### Task 6：全量驗證、文件同步與收尾

**Files:**
- Modify: `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`
- Modify: `docs/epics/epic-54-architecture-optimization/plans/plan-issue-18.md`（勾選 checkbox）

- [x] **Step 1: 真機全量 integration**

依序跑全部 31 檔（`manual_import_acceptance_test` 為人工驗收，略過），記錄通過數。`reader_screen_test` 若有級聯噪音，另以 `--plain-name` 隔離確認。預期：通過數 ≥ 26／31 且逐一對照 Task 1～5 的決定，所有仍失敗者都有對應的獨立工單編號。

- [x] **Step 2: 本機完整驗證（只在此處跑一次完整 `flutter test`）**

```bash
cd app
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
flutter test    # run_in_background，約 5～6 分鐘
```
預期：analyze 乾淨、兩支守衛 PASS、`flutter test` 無失敗。

- [x] **Step 3: 回寫 `epic.md`**

新增「Issue 18 實作完成與真機驗證結果」段落，含：裝置與 WebView 版本、每項的判定與使用者決定（附對話中原話出處日期）、斷言強度變化表、突變驗證結果、未解決項目與其工單編號。**不得寫沒有對話依據的「使用者決定」。**

- [x] **Step 4: 更新 `issues.md` 第 18 列狀態與 `docs/epics.md` 備註**

狀態依實際結果填寫；有新登記的缺陷工單一併列入。`CLAUDE.md` 僅在架構事實真的改變時才改（例如 Task 5 改了 `tapMaxDurationMs`）。

- [x] **Step 5: 勾選本計畫所有 checkbox，並於附錄 A 記錄執行偏差**

- [ ] **Step 6: Commit，開 PR，等程式審查報告**

進度類純文件同步（合併後的 `epic.md`／`epics.md` 更新）依既有慣例直接 commit＋push `main`，不開 PR。

---

## 自我審查紀錄（撰寫計畫時已執行）

- **規格涵蓋：** `issues.md` 第 18 列的 (1)～(5) 與其下 (4) 的三個子項，分別對應 Task 1、2、3、4、5；M-2（PDF 頁尾覆蓋缺口）併入 Task 3。
- **佔位符掃描：** 無「待補」或「視情況」未定案語句；凡需使用者決定處，都已列出明確選項與建議，並標明停點。
- **型別與名稱一致：** 本計畫不新增公開 API；所有 Key、檔案、行號皆為計畫撰寫時對照 `lib/` 所得（見「已查證的事實」表），執行者開工前須用 `grep` 再確認一次行號（行號可能因其他合併而位移）。
- **不確定項（誠實聲明）：** 計畫撰寫時**尚未在真機重跑**這 5 檔，所有失敗描述來自 `epic.md` 記載；Task 0 Step 4 就是為了核對這點。`epub_toc_test` 的真正失敗原因、`reader_screen_test` 三組的真正根因，目前都只是假說，需 Task 1、4 的實測才能判定。

## 附錄 A：執行偏差

1. **執行方式**：inline（executing-plans），worktree Native 直接開發；使用者明確要求後續嚴禁 subagent，故最終審查改用自審（效力較弱，已聲明）。
2. **Task 2 widget 測試省略**：計畫要求補「`widget.isFixedLayout==null` 且實為 FXL 時 `_isFixedLayout` 不被蓋成 false」的 widget 測試；實際 bug 在 JS bridge handler（widget 測試繞過它），`_handleFoliateLayoutResolved` 本體未動，任何經 `onLayoutResolved` 的 widget 測試在新舊碼下結果相同，既有 `:1875` 已覆蓋下游語意，真機 pin 由 integration 測試承擔。
3. **Task 3 Step 3 突變整檔同跑時對照組失敗**：證實為連帶污染（隔離單跑通過），非測試問題。
4. **Task 5 Step 1～3 標不適用**：Step 0 確認單頁書即根因，校準調查依計畫略過，700ms 兩端皆未動。
5. **一次背景任務跑錯目錄**：突變未實際套上即跑測試，兩次全綠僅為正常碼重複確認；已用顯式 `cd`＋`grep` 驗證重做。
6. **`edit` 工具換行吞噬**：兩次 `oldString` 尾端換行被吃掉導致行合併，皆立即發現並修復（`foliate_bridge_codec.dart`、`pdf_fit_size_delegate_test.dart`），最終 `analyze` 乾淨。
7. **全量 integration 計數**：計畫寫 31 檔，實際 glob 跑出 39 檔（含 `flutter_test_config.dart` 誤跑 1 次，已排除）；38 實檔中 34 通過。`issues.md`/`docs/epics.md`/`epic.md` 的數字以本次實測為準。
8. **既存失敗（非本 Issue，不處理）**：`test/reader/pdf_reader_view_filters_test.dart` 加粗 debouncer（stash 證實乾淨樹同樣失敗）、`book_metadata_channel_test`（乾淨樹同樣失敗）、`sync_*`（裝置對後端 100% 丟包）。
9. **`epic.md:441` 未改**：Issue 17 審查 M-2 歷史紀錄敘述屬實，改寫等於竄改歷史；誤判風險由 `issues.md` 更正承擔（見 ledger Ruling）。
10. **Task 6 Step 1 的 `reader_screen_test` 整檔**：改寫後未重跑整檔（4 案例隔離全綠；改寫前整檔 13/19、改寫後全量迴圈中本檔 PASS）。

## 附錄 B：計畫審查回應（`reviews/review-plan-issue-18.md`）

審查結論 Ready to execute with fixes（Critical 0、Important 4、Minor 4）。皆已對照程式碼查證後處理：

| 編號 | 查證結果 | 處置 |
|---|---|---|
| I-1 樣本書只有 1 頁 | 屬實（`sample_fixed_layout.epub` spine 僅 `chapter1`）；尚未真機驗證 | 新增 Task 5 Step 0 與三個處置選項；事實表新增一列 |
| I-2 `info.isFixedLayout` 有消費端 | 屬實（`reader_screen.dart:1833-1835`；其上方註解亦已過期）。「已證實為缺陷」須再證明有開書路徑會被蓋成 `false`，故計畫定為「Step 1 證明路徑，證明不了降為潛在缺陷」 | 更正事實表；Task 2 Step 1／選項／測試改寫，建議選項改為 B |
| I-3 700ms 在 `main.js` 也有一份、校準原則引述顛倒 | 屬實（`main.js:962,1434`；`CLAUDE.md` 原文限制的是 PDF 不得沿用 EPUB） | 更正 Global Constraints；Task 5 檔案與 Step 5 納入 `main.js` |
| I-4 Bash 與 PowerShell 語法 | 屬實但屬環境說明問題 | Global Constraints 明定指令以 Bash 工具（Git Bash）為準，不另提供 PowerShell 版 |
| M-1 `findCurrentPath` | 屬實（`toc_navigator.dart` 的 `progression <= currentProgression` 比對） | Task 1 Step 2 補充，log 須印 `progression` 與 `currentProgression` |
| M-2 `strictMinScale` | **部分成立**：`_zoomFor` 已用 `kPdfFitMaxZoom` 箝位，只有 `metrics.maxScale < 8.0` 時才可能 `minScale > maxScale`，屬未證實假說 | Task 4 Step 3 列為待驗證假說並要求印三個值，不預設結論 |
| M-3 worktree 指令 | 屬實，專案慣例為 `.worktrees/` | Task 0 Step 3 補指令 |
| M-4 測試名稱同步 | 屬實 | Task 3 Step 4 補測試名稱與註解同步 |
| 審查建議「提交前跑 `check_foliate_es_compat.js`」 | **不採納**：該腳本掃描釘定 vendor 的 ES 相容性，不涵蓋 `main.js` 的門檻值 | 改以 `grep` 確認兩端數值一致，並在計畫內註明原因 |
