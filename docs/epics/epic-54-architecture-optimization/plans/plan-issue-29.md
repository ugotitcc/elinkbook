# Issue 29 階段一：開書逾時診斷記錄實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 在不改變任何開書行為的前提下，把開書每一關（複製書、建立 WebView、頁面載入、渲染、離開）寫進 `ReaderConsoleLog`，並在 30 秒逾時時多寫一行「最後階段」。使用者在 WAVE 上遇到「同一本書一直開書逾時」時，能從「設定 → 閱讀器 Console Log」看到卡在哪一關。這是 Issue 29 的階段一；階段二（修復）待證據。

**Architecture：** 新增 `app/lib/reader/open_book_trace.dart`（靜態記錄器：寫 `ReaderConsoleLog` 與 `debugPrint`，記住最後一筆）。`FoliateReaderView` 在既有生命週期與 `InAppWebView` 回呼處呼叫它。`OpenBookFlow` 新增選用的 `onTimedOut` 回呼，由 `ReaderScreen` 接上 `OpenBookTrace`。`OpenBookFlow` 本身不依賴記錄類別。

**Tech Stack：** Flutter／Dart、`flutter_inappwebview` 6.1.5、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 29 設計決策」（決策 1～10）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **不改行為**（決策 6）：不改開書流程、不改 `InAppWebViewSettings`、不改快取、不改逾時秒數；所有新增都是「只記錄」。新增的 `InAppWebView` 回呼不得回傳會影響載入的值（`onLoadStart`、`onLoadStop`、`onReceivedError`、`onReceivedHttpError`、`onRenderProcessGone` 都是通知型）。**不傳 `onLoadResource`**：套件的 `_inferInitialSettings` 看到它就會隱式把 `useOnLoadResource` 設為 `true`，並注入 `PerformanceObserver`，每個資源都多一次 JS→原生→Dart 的訊息（審查 I-2），會改變開書行為。新增任何回呼前，先對照 `in_app_webview.dart` 的 `_inferInitialSettings`，確認不會隱式開啟設定。
- **記錄函式必須處理 null**（審查 I-4）：`WebUri?`、`double?`、`int?` 一律用 `?.`／`??` 補固定字串（路徑缺值記 `(null)`、狀態碼缺值記 `(no status)`），記錄函式本身不得拋例外。
- **診斷回呼的例外不得影響開書**（審查 I-3）：`OpenBookFlow._onTimeout` 以 `try { onTimedOut?.call(); } catch (_) {}` 包住回呼，再呼叫 `_fail`。
- **不記查詢字串與完整路徑**：頁面載入只記 `url.path`（開書網址的查詢字串含偏好與 CFI，太長）。書檔路徑只記是否以 `/book/` 開頭與副檔名。
- **只存記憶體**：沿用 `ReaderConsoleLog` 的 500 筆上限；不落地。
- **記錄格式固定**：`[OpenBook#<實例編號>] <階段>[ <細節>]`。階段名稱用中文固定字串（見下表），測試依它斷言。
- **不新增 `ReaderScreen` 建構參數**；`OpenBookFlow` 只新增選用具名參數 `onTimedOut`（預設 `null`），既有呼叫端不用改。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 若沒裝 Node 則無法執行，記錄在 `epic.md`）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **記錄本身造成行為改變或例外。** `ReaderConsoleLog.add` 每次複製整份 list（上限 500 筆），在 `dispose`、WebView 回呼裡呼叫要確認不拋例外、不在已 dispose 的 `State` 上讀 `context`。→ 記錄只用已存的字串／數值，不碰 `context`；`dispose` 內的記錄放在 `super.dispose()` 之前。
2. **WebView 回呼簽章與型別。** `onLoadStart`／`onLoadStop`／`onReceivedError`／`onReceivedHttpError`／`onRenderProcessGone`／`onLoadResource` 的參數型別以 `flutter_inappwebview` 6.1.5 實際簽章為準；編譯不過時查套件原始碼，不要猜。
3. **逾時回呼在錯誤時機觸發。** `onTimedOut` 只能在「仍是載入中且計時器真的到點」時呼叫一次；已渲染、已失敗、已 dispose 都不能呼叫。→ Task 3 測試涵蓋。
4. **洩漏使用者資訊。** 記錄不含書名、完整檔案路徑、查詢字串。
5. **測試無法觸發 WebView 回呼。** `FakePlatformInAppWebViewWidget` 觸發不了這些 callback（見 `foliate_reader_view.dart` 對 `onConsoleMessage` 的說明）。→ 回呼本體保持一行（只呼叫 `OpenBookTrace.record`），格式化邏輯抽成純函式測試；真正接線靠 WAVE 抽驗。`ReaderScreen` 到 `OpenBookTrace` 的逾時接線有自動化測試（審查 I-5）。
6. **前一本書的記錄污染這一本的逾時摘要**（審查 I-1）。→ `ReaderScreen.initState` 呼叫 `OpenBookTrace.startSession()` 清掉最後階段。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/open_book_trace.dart` | 新增 | `OpenBookTrace.startSession`／`record`／`timeoutSummary`／`recordTimeout` |
| `app/lib/reader/foliate_reader_view.dart` | 修改 | 在生命週期與 WebView 回呼處記錄階段 |
| `app/lib/reader/open_book_flow.dart` | 修改 | 新增選用 `onTimedOut` 回呼 |
| `app/lib/screens/reader_screen.dart` | 修改 | 建構 `OpenBookFlow` 時接上 `onTimedOut` → 記錄逾時摘要 |
| `app/test/reader/open_book_trace_test.dart` | 新增 | 記錄格式、最後階段摘要 |
| `app/test/reader/foliate_reader_view_test.dart`（或既有對應檔） | 修改 | 複製書成功／失敗、離開畫面的階段記錄 |
| `app/test/reader/open_book_flow_test.dart` | 修改 | `onTimedOut` 觸發條件與例外防護 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 逾時後 `ReaderConsoleLog` 有 `開書逾時` 記錄（接線防線） |
| `CONTEXT.md` | 不動 | 無新詞彙 |

## 階段名稱與觸發點

| 階段（固定字串） | 細節 | 觸發點 |
|---|---|---|
| `開書開始` | 副檔名 | `FoliateReaderView.initState` |
| `書複製完成` | `耗時 N ms` | `_cacheBook` 取得非 null 路徑 |
| `書複製失敗` | `回傳 null（耗時 N ms）` 或 `<例外型別>（耗時 N ms）` | `_cacheBook` 回傳 null／拋例外 |
| `WebView 建立` | 空 | `_onWebViewCreated` 開頭 |
| `頁面載入開始` | `url.path` | `InAppWebView.onLoadStart` |
| `頁面載入完成` | `url.path` 與 `距開書 N ms` | `onLoadStop` |
| `載入錯誤` | 錯誤型別與描述 | `onReceivedError` |
| `HTTP 錯誤` | 狀態碼與 `url.path` | `onReceivedHttpError` |
| `渲染行程結束` | `當機=是／否` | `onRenderProcessGone` |
| `已渲染` | `距開書 N ms` | `onPageRendered` handler |
| `離開畫面` | `已刪快取目錄=是／否` | `dispose`（在 `super.dispose()` 之前） |
| `開書逾時` | 摘要（見 Task 1） | `OpenBookFlow.onTimedOut` → `OpenBookTrace.recordTimeout` |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-29-open-timeout-diagnosis`（已從含 PR #366 的 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：`OpenBookTrace` 與單元測試

**Files：** 新增 `open_book_trace.dart`、`test/reader/open_book_trace_test.dart`。

介面草案（以實際編譯為準）：

```dart
/// 開書階段記錄（epic-54 Issue 29 階段一診斷）。
class OpenBookTrace {
  OpenBookTrace._();

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// 開始新的一次開書：清掉「最後階段」，避免前一本書的記錄（例如它的
  /// 「離開畫面」）污染這一本的逾時摘要。`ReaderScreen.initState` 呼叫。
  static void startSession();

  /// 寫一筆 `[OpenBook#<instanceId>] <stage>[ <detail>]` 到 [ReaderConsoleLog]
  /// 與 debugPrint，並記住為「最後階段」。
  static void record(String instanceId, String stage, [String? detail]);

  /// 格式固定：`最後階段：<stage>[ <detail>]（實例 #<instanceId>，距今 <秒> 秒）`；
  /// 本次開書沒有任何記錄時為 `沒有任何階段記錄`。
  static String timeoutSummary();

  /// 先取 [timeoutSummary]，再 `record(instanceId, '開書逾時', summary)`
  /// （順序寫在函式內，不靠引數求值順序）。[instanceId] 預設 `-`。
  static void recordTimeout([String instanceId = '-']);
}
```

- [x] **Step 1（紅）：** 先建骨架（函式 `throw UnimplementedError()`），再寫測試：
  - `record` 寫入 `ReaderConsoleLog.entries`，內容含 `[OpenBook#123] 開書開始 epub`；沒有細節時沒有尾端空白。
  - `record` 連續兩次，`timeoutSummary` 反映最後一筆，且含細節（審查 M-1）：例如 `最後階段：書複製失敗 回傳 null（耗時 12 ms）（實例 #101，距今 31 秒）`。
  - `timeoutSummary` 的距今秒數用 `clock` 控制（31 秒後顯示 `31`）。
  - 沒有任何記錄時，摘要為 `沒有任何階段記錄`。
  - `startSession` 之後回到沒有記錄；先記錄「離開畫面」再 `startSession`，摘要不含它（審查 I-1）。
  - `recordTimeout` 寫入的那一行內含摘要，且摘要不是它自己（審查 M-2）。
  - 每個測試 `setUp` 呼叫 `ReaderConsoleLog.clear()` 與 `OpenBookTrace.startSession()`；`ReaderConsoleLog.clock` 與 `OpenBookTrace.clock` 在 `tearDown` 還原。
- [x] **Step 2（綠）：** 實作。
- [x] **Step 3：** `flutter analyze`；跑 `test/reader/open_book_trace_test.dart`；commit。

### Task 2：`FoliateReaderView` 接上階段記錄

**Files：** `foliate_reader_view.dart`、對應測試檔。

- [x] **Step 1：** 加 import `open_book_trace.dart`。`initState` 先啟動一個 `Stopwatch`（供 `距開書 N ms` 使用），記 `開書開始`（副檔名用 `cacheFileExtension(widget.filePath)`）。
- [x] **Step 2：** `_cacheBook`：開始前存 `Stopwatch`；成功記 `書複製完成 耗時 N ms`；回傳 null 記 `書複製失敗 回傳 null（耗時 N ms）`；`catch` 記 `書複製失敗 <e.runtimeType>（耗時 N ms）`（審查 M-4）。**既有的 `ReaderConsoleLog.add` 與 `onError` 呼叫保留。**
- [x] **Step 3：** `_onWebViewCreated` 開頭記 `WebView 建立`；`onPageRendered` handler 內、呼叫 `widget.onPageRendered()` 之前記 `已渲染 距開書 N ms`。
- [x] **Step 4：** `InAppWebView` 新增回呼（回呼本體一行）：`onLoadStart`、`onLoadStop`（記 `url?.path ?? '(null)'`）、`onReceivedError`、`onReceivedHttpError`（狀態碼 `?.toString() ?? '(no status)'`）、`onRenderProcessGone`（`當機=是／否`）。**不加 `onLoadResource`**（審查 I-2）。把「錯誤描述／路徑／狀態碼」這類組字邏輯抽成檔內頂層純函式（例如 `describeHttpError`），方便測試，且必須處理 null（審查 I-4）。
- [x] **Step 5：** `dispose`：在 `super.dispose()` 之前記 `離開畫面 已刪快取目錄=是／否`。
- [x] **Step 6：** 測試：用既有的 `cacheBookForServing` 覆寫與 `FakePlatformInAppWebViewWidget`：成功路徑記錄出現 `開書開始`、`書複製完成`；回傳 null 路徑出現 `書複製失敗`；離開畫面出現 `離開畫面`；純函式測試涵蓋 null 輸入（路徑 `null`、狀態碼 `null`）不拋例外並回固定字串。每個測試 `setUp` 清 `ReaderConsoleLog` 與 `OpenBookTrace`。
- [x] **Step 7：** `flutter analyze`；跑 `foliate_reader_view` 相關測試檔與 `reader_screen_test.dart` 的開書案例（`--plain-name "開書"`）；commit。

### Task 3：逾時摘要

**Files：** `open_book_flow.dart`、`reader_screen.dart`、`test/reader/open_book_flow_test.dart`。

- [ ] **Step 1（紅）：** `open_book_flow_test.dart` 新增案例：
  - 計時器到點且仍是載入中 → `onTimedOut` 呼叫恰好 1 次，且在狀態變成失敗之前。
  - 已渲染後計時器到點（或計時器已被取消）→ 不呼叫。
  - 已 dispose → 不呼叫。
  - 視圖錯誤先到（`onViewError`）→ 不呼叫 `onTimedOut`。
  - `onTimedOut` 拋例外時，狀態仍照常切到失敗（審查 I-3）。
  - 沿用該檔既有的 `timerFactory` 假計時器。
- [ ] **Step 2（綠）：** `OpenBookFlow` 新增 `this.onTimedOut` 選用參數；`_onTimeout` 通過 guard 後、`_fail` 之前以 `try { onTimedOut?.call(); } catch (_) {}` 呼叫它。
- [ ] **Step 3：** `ReaderScreen.initState`（`OpenBookFlow` 建構之前）呼叫 `OpenBookTrace.startSession()`；建構 `OpenBookFlow` 時傳入 `onTimedOut: OpenBookTrace.recordTimeout`。
- [ ] **Step 4：** `reader_screen_test.dart` 在既有開書逾時案例結尾補斷言：`ReaderConsoleLog.entries.value` 有一筆含 `[OpenBook#-] 開書逾時`（接線防線，審查 I-5）。該檔的 `setUp`／`tearDown` 補 `OpenBookTrace.startSession()`（審查 M-3）。
- [ ] **Step 5：** `flutter analyze`；跑 `open_book_flow_test.dart`、`open_book_trace_test.dart`、`reader_screen_test.dart`（含逾時案例，`--plain-name "逾時"`）；commit。

### Task 4：收尾與 WAVE 抽驗

- [ ] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 29 狀態；`docs/epics.md` 同步。
- [ ] **Step 2：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 3：** 程式審查（報告存 `reviews/review-code-issue-29.md`，不進版控）。
- [ ] **Step 4：** WAVE 真機抽驗：build 並安裝除錯版；開 EPUB、FXL EPUB、CBZ 各一本，到「設定 → 閱讀器 Console Log」確認每次開書都有 `開書開始` → `書複製完成` → `WebView 建立` → `頁面載入開始` → `頁面載入完成` → `已渲染`；退出後有 `離開畫面`。同一本書連開 3 次，每次都有完整階段。
- [ ] **Step 5：** 開 PR；PR 合併後 Issue 29 保持開啟（階段二待證據）；使用者照常使用，遇到逾時時不要關 App，截圖「閱讀器 Console Log」回報。
