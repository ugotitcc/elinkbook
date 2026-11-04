# Issue 6：PDF 降級 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PDF 的開書初始頁碼與跳頁頁碼超出總頁數時，不再讓書開壞或靜默沒反應，而是限制在最後一頁，並通知畫面層顯示與 Issue 5 相同的「原位置已變更」提示。

**Architecture:** 不新增列舉、字串或服務。`PdfReaderView` 新增 `onNavigationDegraded` 回呼，型別直接重用 Issue 5 的 `NavigationDegradedReason`；開書階段在文件開啟後就把初始頁碼夾到最後一頁（不依賴 `pdfrx` 對超界 `initialPageNumber` 的行為），並在 viewer 就緒後通知一次；跳頁階段把 `_jumpToPage` 的「超界直接 return」改成「夾到最後一頁、照常跳頁、通知」。`ReaderScreen` 把回呼接到既有的 `_handleNavigationDegraded`。

**Tech Stack:** Flutter／Dart、`pdfrx`（PDFium）、`flutter_test`（`pumpUntilPdfReady` 載入真實 PDF fixture）。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`（「註記與閱讀位置的降級」，PDF 頁碼超界一節；使用者故事 42、44）；工單見同目錄 `issues.md` Issue 6；Issue 5 見 `plans/plan-issue-5.md`；ADR 0040。

**分支建議：** `epic-67/issue-6-pdf-degrade`（從最新 `main` 切出）。

## 已查證事實（2026-11-04 讀程式所得）

| # | 事實 | 對設計的影響 |
|---|---|---|
| F1 | Issue 5 已落地降級原因 `NavigationDegradedReason { readingPosition, annotation }`（`reader/navigation_degraded_reason.dart`）與 `ReaderScreen._handleNavigationDegraded(reason)`（`reader_screen.dart:842`，顯示 Key `reader_navigation_degraded_snackbar`、文字 `readerNavigationDegradedMessage`「原位置已變更，已跳至概略進度」，先 `hideCurrentSnackBar` 避免排隊）。ARB 描述已寫明「PDF 頁碼超界降級共用，Issue 6」 | **不新增列舉值與字串**；PDF 回呼型別就是 `ValueChanged<NavigationDegradedReason>`。開書超界 → `readingPosition`、跳頁超界 → `annotation`，兩者提示文字相同 |
| F2 | `_jumpToPage(pageIndex)`（`pdf_reader_view.dart:1046`）：`cropEditModeActive` → return；未 ready → return；`pageIndex < 0 || pageIndex >= pageCount` → return（靜默）；之後依逐頁／雙頁／單頁分派。公開入口有二：`PdfReaderView.jumpToPage`、`jumpToPageAtRect`（後者跳頁後再 `_revealHighlight(pageIndex, rect)`）；內部呼叫者（上一頁／下一頁／Home／End／`_applyPendingReanchor`）的索引都已在範圍內 | 夾制與通知放在 `_jumpToPage` 單一處，所有入口自動受惠；`jumpToPageAtRect` 發生降級時不可再對「已不存在的頁」的矩形做 reveal |
| F3 | 外部跳頁來源（`ReaderScreen` → `PdfReaderSurface.jumpTo`）：書籤（`reader_screen.dart:1316`）、劃線／備註（:1306）、頁碼輸入（:2498）、目錄／縮圖／搜尋。書籤、劃線、備註的頁碼來自資料庫，是「舊檔加舊位置」才會超界的唯一來源；其餘來源由 UI 依 `totalPages` 限制，不會超界 | 把所有外部超界跳頁都視為 `annotation` 降級即可，不需區分來源 |
| F4 | 開書初始頁碼 `initialPageIndex` 在三處使用：`initState` 的 `_pagedAnchorPage = widget.initialPageIndex ?? 0`（:832）、`didUpdateWidget` 在 controller 尚未 ready 時的 `anchorBefore`（:918）、`build` 的 `PdfViewer(initialPageNumber: (initialPageIndex ?? 0) + 1)`（:1618）。逐頁模式的 `_currentPagedUnit()` 對 `_pagedAnchorPage` 已做 `clamp`；連續捲動則直接把超界頁碼交給 `pdfrx`（工單所稱「現況」） | 在 `_openDocument` 取得頁數後算出「有效起始頁」存成欄位，上述三處改讀它。這樣不必依賴 `pdfrx` 對超界 `initialPageNumber` 的行為（未實測、可能丟例外），也不需開書後再補一次跳頁 |
| F5 | `onViewerReady`（:1639）是開書完成的單次事件（已有 `_renderedNotified` 防重複），內有 `controller.pageCount` | 開書降級的通知掛在這裡，以新欄位 `_initialPageDegraded` 判斷、通知後清掉，只通知一次 |
| F6 | 既有兩個測試（`pdf_reader_view_test.dart:140`、`pdf_reader_view_dual_page_test.dart:45`）呼叫 `jumpToPage(key, 999)` 並斷言「頁碼維持 4」。4 正好是 5 頁文件的最後一頁，所以改成「夾到最後一頁」後斷言仍成立 | 兩個既有測試不需修改即可通過；它們的標題與註解「安全忽略」已過時，Task 1 一併改成新語意並補降級回呼斷言 |
| F7 | 測試 fixture `test/fixtures/sample_multi_page.pdf` 共 5 頁；`pumpUntilPdfReady`（`test/support/pump_until_pdf_ready.dart`）等待真實文件載入；`ReaderScreen` 層測試以 `tester.widget<PdfReaderView>` 取 widget 後直接呼叫回呼（比照 `reader_screen_test.dart:516` 的 Foliate 案例） | 不需新 fixture；降級回呼要求「不在 build 期間呼叫」，通知以 post-frame 排程，測試以 `pump()` 推進 |
| F8 | `didUpdateWidget` 在文件尚未開完（`_controller.isReady == false`）時，`anchorBefore` 退回讀起始頁並寫入 `_pendingReanchorPageIndex`；`_applyPendingReanchor`（:966）只擋 `!isReady`，之後直接 `_jumpToPage(pageIndex)`（審查 I-1） | 若起始頁尚未夾制就被讀走，待處理的重新錨定會帶著超界頁碼，在 viewer 就緒後經 `_jumpToPage` 再發一次 `annotation` 降級，造成單次開書兩則通知。內部重新錨定本來就不該降級 |
| F9 | `showTemporaryHighlight`（static，回傳 `void`）→ `_setJumpHighlight(pageIndex, rect)`（:717）無範圍檢查，直接寫 `_jumpHighlightPageIndex`；`ReaderJumpTarget.applyTo` 先 `jumpTo` 再 `showTransientHighlight`，後者在 `PdfReaderSurface` 一律回 `true`，`ReaderScreen`（:1382、:1425）據此啟動 3 秒自動清除計時器（審查 I-2） | 超界的搜尋／註記跳轉會留下指向不存在頁的暫態高亮狀態（不會被繪製，但會殘留到計時器清除）。在 `_setJumpHighlight` 擋掉超界頁碼；計時器仍會啟動但清除動作無害，不另改 `ReaderScreen` |

## 已確認決策（本計畫自行定案，待人類審閱）

- **D1：重用 `NavigationDegradedReason`，不新增 PDF 專屬原因。** 開書超界＝`readingPosition`、跳頁超界＝`annotation`；兩者提示相同，符合工單「降級原因的列舉與提示文字沿用 Issue 5」。
- **D2：只對「超過最後一頁」降級；負數頁碼維持靜默忽略。** 負數不可能來自舊檔加舊位置（頁碼只會因文件變短而超界），維持既有行為，也不誤報提示。總頁數為 0 的文件（無頁可夾）不降級、不跳頁。
- **D3：開書階段在 `_openDocument` 就夾制，不靠開書後補跳。** 新欄位 `_startPageIndex`（有效起始頁）取代三處對 `widget.initialPageIndex` 的直接讀取；超界時 `_startPageIndex = 最後一頁`、`_pagedAnchorPage` 同步，`_initialPageDegraded = true`。
- **D4：通知一律以 post-frame 排程並檢查 `mounted`。** `onViewerReady` 與 `_jumpToPage` 可能在 build／layout 相關階段被呼叫，而 `ReaderScreen` 的處理函式會 `showSnackBar`，直接同步呼叫有「build 期間操作 ScaffoldMessenger」的風險。已卸載則不通知。
- **D5：`jumpToPageAtRect` 降級時不做高亮 reveal。** 矩形屬於已不存在的頁，套在最後一頁上會指到錯誤位置。
- **D6：降級後的閱讀位置自然被覆寫。** 夾到最後一頁後，既有的 `onPageChanged` → 位置持久化流程會把最後一頁寫回，下次開書不再超界；不需額外程式碼，僅在 epic.md 記錄。
- **D7（審查 I-1）：內部重新錨定一律夾制、不降級。** `_applyPendingReanchor` 在呼叫 `_jumpToPage` 前，把 `pageIndex` 夾到 `pageCount - 1`（`pageCount <= 0` 則直接 return）。降級通知只來自「開書就緒」與「外部跳頁」兩個來源。
- **D8（審查 I-2）：`_setJumpHighlight` 擋掉超界頁碼。** `pageIndex` 非 null、controller 已就緒且 `pageIndex < 0 || pageIndex >= pageCount` 時直接 return，不記錄暫態高亮；`null`（清除）照常處理。
- **D9（審查 M-1）：負數 `initialPageIndex` 在 `_openDocument` 清洗為 0。** 不降級、不通知（維持 D2），只確保交給 `pdfrx` 的 `initialPageNumber` 至少為 1。

## Global Constraints

- 所有註解、文件、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文。
- 不新增畫面字串、不改 ARB（重用 `readerNavigationDegradedMessage`）；因此不需 `flutter gen-l10n`。
- Flutter 3.41.9：不得使用此版本沒有的 API。
- 不改 `PdfReaderView` 既有公開方法簽章（`jumpToPage`／`jumpToPageAtRect` 維持 fire-and-forget、回傳 `void`）；新增的 `onNavigationDegraded` 為選填具名參數，預設 null，不影響既有呼叫端與測試。
- 頁碼為 0-indexed；`PdfPageInfo.pageIndex` 同。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`（皆在 `app/` 下）。
- 測試範圍：每個 Task 只跑觸及的測試檔；完整 `flutter test --no-pub` 只在最後一個 Task 執行一次。指令工作目錄為 `app/`；flutter 指令後 `git checkout pubspec.lock windows/flutter` 還原工具雜訊。

## Review Focus

1. **邊界 off-by-one**（Task 1）：頁碼 == `pageCount` 要降級、== `pageCount - 1` 不降級、0 不降級。
2. **頁碼有效時零通知**（Task 1、2）：一般開書（含沒有 `initialPageIndex`）與有效跳頁都不得觸發回呼，否則每次開 PDF 都跳提示。
3. **逐頁模式與雙頁模式的開書超界**（Task 1）：初始頁碼超界時落在最後一頁（所屬單元），不崩潰。
4. **不降級的壞值**（Task 1）：負數頁碼維持靜默忽略（不降級、不跳頁）；文件載入失敗或未就緒時的跳頁維持靜默忽略，不通知。
5. **卸載安全**（Task 1）：通知排程後畫面被卸載，不得呼叫回呼、不得拋例外。
6. **降級跳頁不 reveal 高亮**（Task 1）：`jumpToPageAtRect` 超界時跳到最後一頁但不對該頁畫搜尋高亮。
7. **只通知一次**（Task 1）：開書降級在 viewer 就緒時只通知一次，之後的頁面變動不重複通知。
8. **開書期間設定變動不重複通知**（Task 1；審查 I-1）：超界頁碼開書、文件尚未開完時 `didUpdateWidget`（例如切換雙頁）觸發重新錨定，整個開書仍只通知一次。
9. **超界的暫態高亮不殘留**（Task 1；審查 I-2）：搜尋／註記跳轉帶超界頁碼時，`showTemporaryHighlight` 不留下高亮狀態。
10. **負數起始頁碼**（Task 1；審查 M-1）：`initialPageIndex` 為負數時開在第 0 頁、不通知、不崩潰。

---

### Task 1：`PdfReaderView`——開書與跳頁的超界降級

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`（建構子加 `onNavigationDegraded`；`_openDocument` 算有效起始頁；`initState`／`didUpdateWidget`／`build` 三處改讀有效起始頁；`onViewerReady` 通知；`_jumpToPage` 夾制與通知；`jumpToPageAtRect` 降級時不 reveal；`_applyPendingReanchor` 夾制；`_setJumpHighlight` 擋超界）
- Test: `app/test/reader/pdf_reader_view_test.dart`（新增降級案例、改寫舊 999 案例標題）、`app/test/reader/pdf_reader_view_dual_page_test.dart`（雙頁開書超界、改寫舊 999 案例標題）、`app/test/reader/pdf_reader_view_paginated_test.dart`（逐頁開書超界）

**Interfaces:**
- Consumes: Issue 5 的 `NavigationDegradedReason`（`reader/navigation_degraded_reason.dart`）。
- Produces:
  - `PdfReaderView({..., ValueChanged<NavigationDegradedReason>? onNavigationDegraded})`（選填，預設 null；Task 2 接線）。
  - 行為契約：開書時 `initialPageIndex >= 總頁數 && 總頁數 > 0` → 開在最後一頁、通知一次 `readingPosition`；`jumpToPage`／`jumpToPageAtRect` 的 `pageIndex >= 總頁數 && 總頁數 > 0` → 跳最後一頁、通知一次 `annotation`；`pageIndex < 0` 維持靜默忽略。

- [ ] **Step 1: 寫失敗測試**（沿用 `pdf_reader_view_test.dart` 既有 `pumpWidget`＋`pumpUntilPdfReady` 模式與 `sample_multi_page.pdf`（5 頁）；測試名稱用中文）
  - `pdf_reader_view_test.dart`：
    - `開書初始頁碼超出總頁數：開在最後一頁並通知一次 readingPosition`（`initialPageIndex: 99`；斷言 `lastPageInfo.pageIndex == 4`、通知清單為 `[readingPosition]`、`tester.takeException()` 為 null）
    - `開書初始頁碼剛好等於總頁數（off-by-one）：視為超界降級`（`initialPageIndex: 5`）
    - `開書初始頁碼為最後一頁或 0 或未提供：不降級、不通知`（三組參數，斷言通知清單為空）
    - `跳頁超界：夾到最後一頁、跳頁並通知一次 annotation`（先跳到第 2 頁再 `jumpToPage(key, 999)`，斷言 `pageIndex == 4`、通知 `[annotation]`）
    - `跳頁頁碼剛好等於總頁數：降級；等於最後一頁：不降級`
    - `跳頁負數：靜默忽略，頁碼不變、不通知`
    - `跳頁有效頁碼：不通知`
    - `jumpToPageAtRect 超界：跳到最後一頁、通知 annotation、不拋例外`（以 `PercentRect` 構造，斷言頁碼為最後一頁；不斷言高亮存在）
    - `降級通知排程後畫面被卸載：不呼叫回呼、不拋例外`（以 `pumpWidget(const SizedBox())` 在通知 post-frame 之前卸載；`jumpToPage` 後立刻換掉 widget 樹再 `pump()`）
    - `開書尚未完成時 didUpdateWidget 觸發重新錨定（超界初始頁碼）：整個開書只通知一次`（審查 I-1；初始頁碼 99、`pumpWidget` 後在文件就緒前立刻以不同 `dualPageMode` 重新 `pumpWidget`，再 `pumpUntilPdfReady`，斷言通知清單恰為 `[readingPosition]`。若測試環境無法穩定落在非同步窗口內，改為直接驗證 `_applyPendingReanchor` 的行為：以超界頁碼觸發重新錨定後通知清單不含 `annotation`）
    - `開書初始頁碼為負數：開在第 0 頁、不通知、不拋例外`（審查 M-1）
    - `showTemporaryHighlight 超界頁碼：不產生高亮覆蓋、不拋例外；有效頁碼照常顯示`（審查 I-2；沿用 `pdf_reader_view_jump_highlight_test.dart` 既有觀察高亮的方式）
    - **提醒（審查 M-2）：** 通知走 post-frame，所有「通知清單」斷言前都要先 `await tester.pump()` 推進一幀；`jumpToPage` 後的既有 `pump()`＋`pump(300ms)` 已足夠，開書案例則靠 `pumpUntilPdfReady` 後再補一次 `pump()`。
    - 既有 `pageCount／jumpToPage 正確運作，含邊界情況`：標題與註解改為「超界跳頁夾到最後一頁」，保留原斷言並補通知斷言。
  - `pdf_reader_view_dual_page_test.dart`：`雙頁模式開書初始頁碼超界：開在最後一頁（所屬跨頁）並通知`；舊 999 案例標題同步改寫。
  - `pdf_reader_view_paginated_test.dart`：`逐頁模式開書初始頁碼超界：落在最後一頁所屬單元並通知`（沿用該檔既有 helper）。

- [ ] **Step 2: 執行確認失敗**
  Run（`app/`）：`flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_paginated_test.dart --no-pub`
  Expected: 編譯失敗（`onNavigationDegraded` 未定義）。

- [ ] **Step 3: 實作**（`pdf_reader_view.dart`）
  - 建構子與欄位加 `final ValueChanged<NavigationDegradedReason>? onNavigationDegraded;`（文件註解寫明兩種原因與 D1）；import `navigation_degraded_reason.dart`。
  - State 新增 `late int _startPageIndex`（`initState` 先設為 `widget.initialPageIndex ?? 0`）與 `bool _initialPageDegraded = false`。`_openDocument` 在 `setState(() => _document = document)` 前：`final last = document.pages.length - 1;` 若 `last >= 0` 且 `_startPageIndex > last`，設 `_startPageIndex = last`、`_pagedAnchorPage = last`、`_initialPageDegraded = true`（D3）。`didUpdateWidget` 的 `anchorBefore` 與 `build` 的 `initialPageNumber` 改讀 `_startPageIndex`；`initState` 的 `_pagedAnchorPage` 維持以 `_startPageIndex` 初始化。
  - 新私有方法 `void _notifyDegraded(NavigationDegradedReason reason)`：`WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.onNavigationDegraded?.call(reason); })`（D4）。
  - `onViewerReady`：在既有邏輯之後，若 `_initialPageDegraded` 則清為 false 並 `_notifyDegraded(readingPosition)`（只通知一次，F5）。
  - `_jumpToPage`：保留 `cropEditModeActive`／未 ready 的早退；負數維持 return；`final count = _controller.pageCount;` `count <= 0` return；`pageIndex >= count` 時 `pageIndex = count - 1` 並 `_notifyDegraded(annotation)`；其後分派邏輯不動。方法回傳 `bool`（是否發生降級）供 `jumpToPageAtRect` 判斷（內部方法，不影響公開簽章）。
  - `jumpToPageAtRect`：`final degraded = state._jumpToPage(pageIndex);` 降級時略過 `_revealHighlight`（D5）。
  - `_applyPendingReanchor`：取得 `pageCount` 後夾制再 `_jumpToPage`（D7）；`_setJumpHighlight` 加超界檢查（D8）；`_openDocument` 內 `last >= 0` 時，`_startPageIndex < 0` 清洗為 0 並同步 `_pagedAnchorPage`（D9，不設 `_initialPageDegraded`）。
  - 通知內不得 await、不改狀態，維持現有 fire-and-forget 慣例。

- [ ] **Step 4: 執行確認通過**
  Run: 同 Step 2 指令
  Expected: PASS（含既有跳頁、雙頁、逐頁、書籤相關案例不回歸）。另跑 `flutter test test/reader/pdf_reader_view_jump_highlight_test.dart test/reader/pdf_reader_view_search_test.dart test/reader/pdf_reader_surface_test.dart --no-pub` 確認搜尋跳轉與 Surface 不回歸。

- [ ] **Step 5: 靜態檢查**
  Run: `flutter analyze` → "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。

- [ ] **Step 6: Commit**
  ```bash
  git add app/lib/reader/pdf_reader_view.dart app/test/reader
  git commit -m "feat(reader): PDF 開書與跳頁頁碼超界時夾到最後一頁並通知降級（epic-67 Issue 6）"
  ```

---

### Task 2：`ReaderScreen`——接線降級提示

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`PdfReaderView(...)` 建構處加 `onNavigationDegraded: _handleNavigationDegraded`，約 :2978）
- Test: `app/test/screens/reader_screen_test.dart`（新增 PDF 降級案例，緊鄰既有 Foliate 降級案例）

**Interfaces:**
- Consumes: Task 1 的 `PdfReaderView.onNavigationDegraded`；Issue 5 的 `ReaderScreen._handleNavigationDegraded`（不改）。
- Produces: 無新介面。

- [ ] **Step 1: 寫失敗測試**（沿用 `reader_screen_test.dart:516` Foliate 案例的寫法）
  - `PDF：閱讀器回報降級時顯示與 Foliate 相同的提示`：開 `sample_multi_page.pdf`，`tester.widget<PdfReaderView>` 取得後斷言 `onNavigationDegraded` 非 null；呼叫 `(NavigationDegradedReason.readingPosition)` 與另一次 `annotation` 後 `pump()`，斷言找到 Key `reader_navigation_degraded_snackbar` 與文字「原位置已變更，已跳至概略進度」，且畫面上只有一則（連續兩次不排隊）。
  - `PDF：初始頁碼超界時真的顯示提示且書不壞`（端到端）：`ReaderScreen(filePath: sample_multi_page.pdf, initialJumpTarget: ReaderJumpTarget(pdfPageIndex: 99))`，以 `pumpUntilPdfReady` 等待後 `pump()`，斷言出現提示 SnackBar、沒有 `reader_error_text`、`PdfPageInfo` 頁尾顯示最後一頁（以既有頁碼指示 Key 或 `_pdfPageInfo` 可見文字為準，沿用該檔既有 PDF 頁碼斷言寫法）。
  - `PDF：初始頁碼有效時不顯示降級提示`（回歸，`pdfPageIndex: 2`）。

- [ ] **Step 2: 執行確認失敗**
  Run: `flutter test test/screens/reader_screen_test.dart --plain-name "降級" --no-pub`
  Expected: 新案例 FAIL（`onNavigationDegraded` 為 null）。

- [ ] **Step 3: 實作**
  在 `reader_screen.dart` 的 `PdfReaderView(` 參數列加一行 `onNavigationDegraded: _handleNavigationDegraded,`，不改其他邏輯。

- [ ] **Step 4: 執行確認通過**
  Run: `flutter test test/screens/reader_screen_test.dart --plain-name "降級" --no-pub`；再跑 `--plain-name "PDF"` 確認既有 PDF 閱讀案例不回歸。
  Expected: PASS。

- [ ] **Step 5: 靜態檢查**
  Run: `flutter analyze` → "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。

- [ ] **Step 6: Commit**
  ```bash
  git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
  git commit -m "feat(reader): PDF 頁碼降級時顯示與 Foliate 相同的提示（epic-67 Issue 6）"
  ```

---

### Task 3：文件同步、完整測試與真機驗證清單

**Files:**
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`（新增「Issue 6 計畫與實作」段落：D1～D6、已知限制、真機驗證「尚未執行」）
- Modify: `docs/epics/epic-67-book-update-detection/issues.md`（Issue 6 列與 Status 改為實作完成待 PR）
- Modify: 本計畫檔（勾選完成的步驟）

- [ ] **Step 1: 完整測試與靜態檢查**
  Run（`app/`）：`flutter test --no-pub`；`flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；然後 `git checkout pubspec.lock windows/flutter`。
  Expected: 全部通過、analyze "No issues found!"。

- [ ] **Step 2: 更新 epic.md 與 issues.md**
  記錄決策、已知限制，與真機驗證項目；真機驗證一律標「尚未執行，由人類另行處理」，不自行勾選。已知限制至少包含：
  - 夾到最後一頁只是「不壞」的安全網，書籤與劃線仍指向舊頁碼（PDF 沒有概略進度可用，與 Foliate 不同）；劃線的頁內矩形座標在新版內容中也可能對不上，屬 spec 已接受的偏移。
  - 降級後閱讀位置會被最後一頁覆寫（D6），原本的超界頁碼不保留。

- [ ] **Step 3: 真機／模擬器手動驗證項目（由人類執行，結果補記於 epic.md）**
  1. 書架對一本 20 頁 PDF 讀到第 18 頁，用「用新檔案更新此書」換成 5 頁的 PDF → 再開書：開在第 5 頁、出現「原位置已變更」提示、不閃退。
  2. 同一本書，在書籤清單點第 18 頁的書籤：跳到最後一頁並出現提示。
  3. 雙頁（並列）與逐頁翻頁模式各重做第 1 項：落在最後一頁（所屬跨頁）、不空白。
  4. 正常 PDF 一般開書與書籤跳轉：不出現提示（迴歸）。

- [ ] **Step 4: Commit**
  ```bash
  git add docs/epics/epic-67-book-update-detection
  git commit -m "docs(epic-67): Issue 6 實作記錄與工單更新"
  ```

---

## 不在範圍

- Foliate 格式的降級（Issue 5，已合併 PR #383）。
- PDF 書籤、劃線、備註的頁內座標在新版內容中對不上的修正（只保證頁碼不超界；座標偏移屬 spec 已接受的限制）。
- 為 PDF 新增「概略進度比例」資料欄位（PDF 位置只有頁碼；不改資料庫 schema）。
- Page Label（PDF 邏輯頁碼標籤）支援。
- 降級後保留原超界頁碼以便日後新檔補回（D6：直接覆寫）。

## 需要人類確認（已於 2026-11-04 兩項皆接受）

1. D1／D2：開書與跳頁共用同一則提示文字（「原位置已變更，已跳至概略進度」）。spec 與工單都明確要求「統一顯示同一提示、文字沿用 Issue 5」（計畫審查 M-3 已核對）；唯一疑慮是 PDF 沒有「概略進度」，實際是「跳至最後一頁」，文字略不精確。若要改為 PDF 專屬文字，需新增 ARB 字串（四份同步），請告知。
2. D6：降級後閱讀位置直接被最後一頁覆寫，是否接受？（審查 M-3 認為這是 `onPageChanged` 持久化的自然行為，建議接受；仍由您決定。）

## 自我審查

- **Spec 覆蓋：** 開書階段超界導回最後一頁並通知（Task 1，D3）；跳頁階段超界限制並跳頁並通知（Task 1，取代原本的靜默 return）；`PdfReaderView` 降級回呼由 `ReaderScreen` 接線、列舉與文字沿用 Issue 5（Task 1 契約、Task 2）；工單單元測試要求——頁碼超界／有效、開書超界／有效、畫面收到通知顯示提示、既有跳頁／雙頁／書籤不回歸（Task 1、2 的測試與回歸指令）；對稱性（舊檔加新位置）由同一機制涵蓋，真機驗證 1～2 覆蓋。
- **型別一致：** `onNavigationDegraded`（`ValueChanged<NavigationDegradedReason>?`）、`_startPageIndex`、`_initialPageDegraded`、`_notifyDegraded`、`NavigationDegradedReason.readingPosition／annotation` 在 F1、D1～D5 與各 Task 名稱一致；`_jumpToPage` 回傳 `bool` 僅內部使用。
- **審查修訂（review-plan-issue-6.md）：** I-1 → D7、F8；I-2 → D8、F9；M-1 → D9；M-2 → Task 1 Step 1 提醒；M-3 → 需要人類確認補註。Review Focus 新增 8～10。
- **比例：** 3 個 Task（2 個程式＋1 個文件／驗證），不含程式本體，僅留簽章、測試名稱與關鍵斷言。
