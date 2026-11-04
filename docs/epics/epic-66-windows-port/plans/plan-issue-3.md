# Epic 66 Issue 3：閱讀器與索引器「整本回傳」記憶體驗證 實作計畫

> **給執行計畫的代理：** 必須使用 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行。步驟用 `- [ ]` 追蹤。

**Goal：** 以可重現的量測迴圈，判定閱讀器開書（`FoliateReaderView`）與全文索引器（`FoliateContentIndexer`）兩條 `shouldInterceptRequest` 整本回傳路徑，是否讓 App 程序（`elinkbook.exe`）的私有記憶體（Private Bytes）永久上升；並把數據與判定寫進報告。

**範圍界線（已與使用者確認）：** 本計畫**只含量測與判定，不含修法**。若判定洩漏，Task 5 寫完報告後**停下**，把數據與修法選項交給使用者決定；修法另寫一份計畫（`issues.md` Issue 3 範圍第 3 點：設計前先討論，不可逕自動手）。

**Architecture：** 新增共用量測 helper（讀記憶體、印 `[leak]` 行、套用判定規則）與兩支 Windows 整合測試（索引器、閱讀器）。判定規則抽成純 Dart 函式，以單元測試釘住邊界。不修改既有 `leak_probe_test.dart`（Issue 2 的診斷工具）與任何 `lib/` 正式程式。

**Tech Stack：** Dart／Flutter `integration_test`（`-d windows`）、PowerShell（讀 Private Bytes 與程序樹）。

**Spec：** 沒有獨立 spec。權威依據是 `docs/epics/epic-66-windows-port/issues.md` 的「Issue 3 範圍／過關條件／單元測試要求」與 `issue-2-report.md` 第 4、5 節。

## Global Constraints

- **語言：** 文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。
- **不改 `lib/`：** 本計畫不動任何正式程式碼；若為了量測必須改，先停下與使用者討論。
- **量測用書：** `../tmp/AI世界的底層邏輯與生存法則.epub`（相對 `app/`，約 224.7 MiB／235,583,038 位元組；`tmp/` 已 gitignore，不進版控）。檔案不存在時整支測試略過並印出原因（比照 `leak_probe_test.dart`）。
- **洩漏判定規則（Q6 定案）：**
  - 指標為 Private Bytes（`PrivateMemorySize64`）；工作集（Working Set）只記錄，不判定。
  - 第 0 次為暖身基線，不計入判定。
  - 第 1～4 次，每次與「上一次等待回落後」的值比較，增量 **> 書檔大小 × 5%**（約 11.2 MB）即該次為洩漏。
  - 判定「洩漏」＝第 1～4 次中**有任一次**超過門檻；並額外記錄「是否呈棘輪式持續上升」。
- **迴圈參數：** 4 次迭代，每次之後等待 6 秒再量（比照 `leak_probe_test.dart`）。
- **WebView2 子程序（Q8 定案）：** 記錄 App 程序樹內 `msedgewebview2` 的私有記憶體總和，**只記錄、不斷言**。
- **Windows 環境：** 多數原始檔是 CRLF，Edit 的定位字串不要含換行；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔。
- **Windows 整合測試：** 一次只跑一個檔：`cd app && export MSYS2_ENV_CONV_EXCL=CL CL=/utf-8 PATH="/c/Users/huthief/bin:$PATH" && flutter test integration_test/windows_leak/<檔名> -d windows`。
- **測試範圍（`CLAUDE.md`）：** 單一 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次，`run_in_background`。
- **提交前：** `flutter analyze` 必須 `No issues found!`；跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit：** 不加 `Co-Authored-By`；每個 Task 一個 commit。

## Review Focus

1. **判定規則的邊界：** 剛好等於門檻算不算洩漏、增量為負（記憶體下降）、基線只有一筆時的行為。→ Task 1。
2. **兩條路徑的清理是否真的被觸發：** 閱讀器迴圈必須真正卸載 widget（`dispose` 內的 WebView 釋放與快取子目錄刪除）；索引器必須把 `indexBook()` 的 Stream 消費到結束。若迴圈沒有走完整個清理流程，「不洩漏」的結論會是假的。→ Task 3、4。
3. **量測噪音：** 4 次太少可能把偶發 GC 抖動誤判；因此報告需同時附 `private_mb` 與 `ws_mb`，必要時在報告中建議加跑次數。→ Task 5。
4. **「不洩漏」結論的可信度：** 若不洩漏，必須查明 Issue 1「離開閱讀器沒多出兩份」的原因，並說明為何穩定而非巧合（過關條件 4）。→ Task 5。

---

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `app/integration_test/windows_leak/leak_verdict.dart` | 建立 | 純 Dart：`evaluateLeak()` 判定規則 |
| `app/test/windows_leak/leak_verdict_test.dart` | 建立 | 判定規則單元測試 |
| `app/integration_test/windows_leak/leak_meter.dart` | 建立 | 讀 Private Bytes／工作集／WebView2 子程序，印 `[leak]` 行 |
| `app/integration_test/windows_leak/indexer_leak_test.dart` | 建立 | 索引器重複索引迴圈 |
| `app/integration_test/windows_leak/reader_leak_test.dart` | 建立 | 閱讀器重複開關迴圈 |
| `docs/epics/epic-66-windows-port/issue-3-report.md` | 建立 | 數據、判定、原因說明 |
| `docs/epics/epic-66-windows-port/epic.md`、`issues.md` | 修改 | 決策 15 補【Issue 3 結果】、更新 Issue 3 狀態 |

---

### Task 1：洩漏判定規則（純 Dart，TDD）

**Files：**
- Create：`app/integration_test/windows_leak/leak_verdict.dart`
- Test：`app/test/windows_leak/leak_verdict_test.dart`

**Interfaces：**
- Produces：`LeakVerdict evaluateLeak({required List<double> privateMb, required double bookMb, double thresholdRatio = 0.05})`。`privateMb[0]` 為暖身基線，`privateMb[i]`（i ≥ 1）為第 i 次「等待回落後」的值。回傳每次增量 `deltas`、超標次數 `exceededIterations`、`leaked`（任一次超標）、`ratcheting`（第 1～N 次增量皆為正）。

- [ ] **Step 1：寫失敗測試**，涵蓋：
  - 全部增量遠小於門檻 → `leaked == false`。
  - 某次增量剛好等於門檻 → 不算洩漏（嚴格大於才算）。
  - 某次增量略大於門檻 → `leaked == true`，`exceededIterations` 含該次。
  - 增量為負（記憶體下降）→ 不算洩漏、`ratcheting == false`。
  - 4 次增量皆為正但都低於門檻 → `leaked == false` 但 `ratcheting == true`（報告需註記）。
  - 只有基線一筆（無迭代）→ 丟 `ArgumentError`。
- [ ] **Step 2：** `flutter test test/windows_leak/leak_verdict_test.dart`，確認失敗。
- [ ] **Step 3：** 實作 `evaluateLeak`。
- [ ] **Step 4：** 重跑測試通過；`flutter analyze`。
- [ ] **Step 5：** commit。

---

### Task 2：量測 helper

**Files：**
- Create：`app/integration_test/windows_leak/leak_meter.dart`

**Interfaces：**
- Produces：
  - `Future<MemSample> sampleMemory()`：以 PowerShell 讀自己 PID 的 `PrivateMemorySize64`、`WorkingSet64`，並以 `Win32_Process` 的 `ParentProcessId` 展開子孫程序，加總 `msedgewebview2` 的私有記憶體與數量（做法沿用 `tool/measure_large_epub_memory.ps1` 的 `Get-ProcessTree`）。
  - `void logLeak(String path, int iter, String phase, MemSample s)`：印出 `[leak] path=<reader|indexer> iter=<n> phase=<before|after_run|after_wait> private_mb=<…> ws_mb=<…> wv2_private_mb=<…> wv2_count=<…>`。
  - `const kLargeEpubPath`、`const kIterations = 4`、`const kSettleSeconds = 6`、`double bookSizeMb()`。
- 本 Task 無獨立單元測試（依賴實機程序）；由 Task 3 的整合測試實際驗證輸出格式。

- [ ] **Step 1：** 實作 helper。PowerShell 只啟動一次/樣本，避免把啟動成本算進記憶體（它是外部程序，不影響 App 私有記憶體）。
- [ ] **Step 2：** `flutter analyze`。
- [ ] **Step 3：** commit。

---

### Task 3：索引器迴圈（先做，不需要 UI）

**Files：**
- Create：`app/integration_test/windows_leak/indexer_leak_test.dart`

**行為：**
1. 缺書檔 → 略過並印原因。
2. `initAppWebViewEnvironment(userDataFolder: …)`（比照 `leak_probe_test.dart`）。
3. 以 `Book`（`format: epub`、`filePath: kLargeEpubPath`）建構輸入。
4. 暖身：第 0 次 `before` 取樣；再完整消費一次 `FoliateContentIndexer().indexBook(book).toList()` 作為基線（`iter=0`），等 6 秒後量測。
5. 第 1～4 次：`before` → 完整消費 `indexBook()` → `after_run` → 等 6 秒 → `after_wait`。
6. 以 `evaluateLeak` 計算判定；**測試本身只斷言「迴圈跑完且每次都有取得區段」**，並印出判定結果 `[leak-verdict] path=indexer leaked=<…> deltas=<…>`。**不在此 Task 讓測試因洩漏而失敗**，修法前的測試需能跑出數據；增量門檻斷言於 Task 5 之後（修法完成時）才啟用。

- [ ] **Step 1：** 寫測試；`flutter test integration_test/windows_leak/indexer_leak_test.dart -d windows`。
- [ ] **Step 2：** 確認輸出 `[leak]` 行完整（4 次 × 3 個 phase ＋基線），把原始輸出存到 `build/leak_indexer.log`（不進版控）。
- [ ] **Step 3：** `flutter analyze`；commit。

---

### Task 4：閱讀器迴圈

**Files：**
- Create：`app/integration_test/windows_leak/reader_leak_test.dart`

**行為（Q5 定案：直接掛 `FoliateReaderView`）：**
1. 缺書檔 → 略過。
2. 每次迭代：以 `pumpLocalizedWidget`（見 `test/support/pump_localized_widget.dart`）掛載 `FoliateReaderView(filePath: kLargeEpubPath, onPageRendered: …, onError: …)`；等 `onPageRendered` 被呼叫（逾時 120 秒視為失敗）；`pumpWidget(SizedBox())` 卸載並 `pumpAndSettle`；`after_run` 取樣；等 6 秒；`after_wait` 取樣。
3. 暖身與判定同 Task 3；輸出 `path=reader`。
4. 迴圈需確認 `dispose` 真的跑完：卸載後檢查快取子目錄已被刪除（用 `getTemporaryDirectory()` 下對應 `instanceId` 的目錄是否還在；若不易取得 instanceId，改為量測前後暫存目錄總檔案數不增加）。這是 Review Focus 2 的證據。

- [ ] **Step 1：** 寫測試；`flutter test integration_test/windows_leak/reader_leak_test.dart -d windows`。
- [ ] **Step 2：** 輸出存 `build/leak_reader.log`。
- [ ] **Step 3：** `flutter analyze`；commit。

---

### Task 5：判定、報告與停點

**Files：**
- Create：`docs/epics/epic-66-windows-port/issue-3-report.md`
- Modify：`docs/epics/epic-66-windows-port/epic.md`（決策 15）、`issues.md`（Issue 3 狀態）

- [ ] **Step 1：報告內容**
  - 每條路徑的 4 次數據表（`private_mb`／`ws_mb`／`wv2_private_mb`）、增量、門檻、判定。
  - 與 Issue 2 headless metadata 路徑的洩漏量對照（每次約 +452 MB）。
  - **若兩條皆不洩漏：** 查明 Issue 1「離開閱讀器沒有多出兩份」的原因（比對 metadata 路徑與閱讀器路徑在攔截回應物件生命週期上的差異），說明為何穩定、不是巧合；必要時用 `ReaderScreen` 補驗一次（Q5 定案的備案）。
  - **若任一條洩漏：** 列出修法選項（區段化、回頭檢視 `epic.md` 決策 15 的 `shelf` 備案，及其他）與各自取捨。
- [ ] **Step 2：停點。** 洩漏成立 → **到此停下**，向使用者報告數據與選項，等使用者決定；**不寫修法程式、不改 `lib/`**。
- [ ] **Step 3：（僅在不洩漏、或使用者決定不修時）** `epic.md` 決策 15 補【Issue 3 結果】，`issues.md` Issue 3 改為完成。
- [ ] **Step 4：** 完整 `flutter test`（`run_in_background`）與 `flutter analyze`；commit。

---

## 後續（不在本計畫）

- 洩漏成立時的修法計畫（過關條件 3：修後重複 4 次，每次增量低於書檔 5%，且功能與修正前一致）；此時再把 Task 3、4 的測試加上增量門檻斷言。
- 大檔開書瞬間尖峰（約 3.8 GB）仍不在 Issue 3 範圍；若要改善另開「分段服務」Issue。
