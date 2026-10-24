# Issue 24：標註 module 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把 `ReaderScreen` 裡 EPUB 與 PDF 兩套近乎逐行相同的劃線／備註選取流程，合成一個 `AnnotationController`（擁有選取、待存劃線 id、劃線與備註清單及其 CRUD）；PDF 退化選取守衛與工具列定位抽成純函式。純重構、零行為變化。

**Architecture：** 新增 `app/lib/reader/annotation_controller.dart`（`AnnotationSelection`、`AnnotationController`、`isIgnoredPdfSelection`；`AnnotationLocator` 一併搬入）與 `app/lib/reader/annotation_toolbar_layout.dart`（工具列定位純函式與常數）。`ReaderScreen` 以 `late final AnnotationController _annotations` 持有，不通知，呼叫後自己 `setState`。`AnnotationSession`／`AnnotationSnapshot` 併入後刪除。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 24 設計決策」（決策 1～16）；詞彙見 `CONTEXT.md`「標註」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構、零行為變化**（決策 1）：呼叫順序、`mounted` 檢查、fire-and-forget 逐字保留。
- **async 方法的取值時機逐字保留**：原本在 `await` 前取得 `selection`，`await` 後才讀 `_pendingHighlightIdForSelection`（備註流程）；controller 方法必須「開頭捕捉 selection，`pendingHighlightId` 在寫入前才讀」。
- **範圍外**：不改兩個 View 的回呼型別與 `EpubSelectionInfo`／`PdfSelectionInfo`；不動 `_session.recordActivity()`（那是閱讀統計 session，與標註無關）；不動 PDF 換頁取消選取的順序（決策 12）；不動 `_handleLookupPressed`／`_handleCopySelection` 內容（決策 10）。
- **不新增 `ReaderScreen` 建構參數**，也不新增工廠（決策 4）。
- **測試原則（replace, don't layer）**：`annotation_session_test` 改名為 `annotation_controller_test`，舊檔刪除；`reader_screen_test.dart` 的標註案例全留。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（用 `run_in_background`；不要同時跑第二個 `flutter test`）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**：簽章改動與其所有呼叫端遷移在同一個 commit。
- **提交前**：`flutter analyze` 必須 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`。每個 Task 一個 commit；Task 3 為三個 commit（見該 Task）。
- **不要提交** `app/analysis_options.yaml`、`app/android/gradle.properties`（使用者擱置的未提交變動）。

## Review Focus

最可能咬到使用者的情況（依可能性排序）：

1. **PDF 退化選取（單點長按）誤彈工具列，或命中既有標註卻不彈。** → Task 1 對守衛純函式測：非退化、退化未命中、退化命中；`reader_screen_test.dart` 約 10375／10451 兩個整合案例必須維持綠。
2. **備註儲存後連結錯劃線。** 備註流程「先點劃線樣式、再點備註」要把新備註連到該劃線；`pendingHighlightId` 讀取時機改變會連錯或不連。→ Task 2 測「建立劃線後立刻存備註 → 備註帶 `highlightId`」「換選取後 pending 歸零」。
3. **工具列位置偏移。** EPUB 用 `rect`、PDF 用 `widgetRect`（letterbox 留白）；錨點傳錯會偏移。→ Task 1 測兩種錨點；Task 3 Step 2 合併區塊後跑 `reader_screen_test.dart` 的工具列位置案例（約 4676、8713）。
4. **PDF 關閉工具列後殘留選取。** 統一後 PDF 也會呼叫 `_surface.clearSelection()`；前提是 PDF adapter 該方法是空操作。→ Task 3 Step 2 先以 `pdf_reader_surface_test` 確認空操作。
5. **EPUB 固定版面（FXL）誤出現劃線工具列。** `_isFixedLayout` 守衛必須留在 `ReaderScreen`、在 `select` 之前。
6. **刪除既有標註後選取沒清、工具列還在。**
7. **備註對話框按取消後，選取或工具列被清掉。** `text == null` 必須直接 return，不呼叫 `saveNote`、不 `setState`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/annotation_controller.dart` | 新增 | `AnnotationLocator`（自 `annotation_session.dart` 搬入）、`AnnotationSelection`、`AnnotationController`、`isIgnoredPdfSelection` |
| `app/lib/reader/annotation_toolbar_layout.dart` | 新增 | `annotationToolbarTop`、`annotationToolbarLeft` 純函式與三個常數 |
| `app/lib/reader/annotation_resolution.dart` | 修改 | `resolvePdfExistingAnnotation` 改收 `pageIndex`＋`rect` |
| `app/lib/reader/annotation_session.dart` | 刪除 | 併入 controller |
| `app/lib/screens/reader_screen.dart` | 修改 | 用 `_annotations`；成對方法合一；工具列區塊合一 |
| `app/test/reader/annotation_controller_test.dart` | 新增（由 `annotation_session_test.dart` 改名） | controller 契約、選取流程、守衛 |
| `app/test/reader/annotation_toolbar_layout_test.dart` | 新增 | 定位純函式 |
| `app/test/reader/annotation_resolution_test.dart` | 修改 | 簽章遷移 |
| `CONTEXT.md` | 已完成 | 「標註」詞條（設計定案時已加） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態；Issue 23 收尾 |

## Interface 草案（以實際編譯與既有型別為準）

```dart
/// 使用者在畫面上選取的範圍（EPUB／PDF 統一）。
@immutable
class AnnotationSelection {
  const AnnotationSelection({
    required this.locator,
    required this.text,
    required this.anchorRect, // 工具列定位用：EPUB 為 rect，PDF 為 widgetRect
    this.existingAnnotationId, // 只有 EPUB 有（JS 端 hit-test）
  });
  final AnnotationLocator locator;
  final String text;
  final PercentRect anchorRect;
  final String? existingAnnotationId;

  factory AnnotationSelection.fromEpub(EpubSelectionInfo info);
  factory AnnotationSelection.fromPdf(PdfSelectionInfo info);
}

/// 標註 module：不通知，呼叫端自己 setState。不碰 BuildContext。
class AnnotationController {
  AnnotationController({required highlightsRepository, required notesRepository, required bookId});

  List<Highlight> get highlights;
  List<Note> get notes;
  AnnotationSelection? get selection;
  String? get pendingHighlightId;

  /// 目前選取命中的既有劃線／備註（EPUB 用 existingAnnotationId，PDF 用矩形重疊）。
  AnnotationListItem? get existingItem;

  void select(AnnotationSelection s); // 同時清 pendingHighlightId
  void clearSelection();

  Future<void> reload();
  Future<void> createHighlight(HighlightStyle style); // 無選取則不動作；成功後 pendingHighlightId = 新 id
  Future<void> saveNote({required AnnotationSelection selection, required String text, Note? existing}); // 成功後清選取與 pending
  Future<void> deleteExisting(AnnotationListItem item);
}

/// PDF 退化選取（rect.left == rect.right）且沒命中既有標註時回傳 true（應忽略）。
bool isIgnoredPdfSelection({required PdfSelectionInfo info, required List<Highlight> highlights, required List<Note> notes});
```

> `createHighlight`、`saveNote` 的 `await` 之後若選取已被換掉，行為必須與原碼一致：原碼用開頭捕捉的 `selection` 寫入，之後無條件把 `pendingHighlightId` 設為新 id（`createHighlight`），或無條件清選取（`saveNote`）。逐字保留，不「順手修」。

---

### Task 0：提交計畫

- [ ] **Step 1：** 在文件分支提交本計畫、`epic.md` 設計決策、`issues.md` 狀態（純文件），開 PR 合併。
- [ ] **Step 2：** 建立 worktree `.worktrees/epic-54-issue-24-annotation`，分支 `epic-54/issue-24-annotation`；後續 Task 都在這個 worktree 的 `app/` 下執行。

### Task 1：純函式（定位、守衛、簽章遷移）

**Files：** 新增 `annotation_toolbar_layout.dart`、`annotation_toolbar_layout_test.dart`；修改 `annotation_resolution.dart`、`annotation_resolution_test.dart`、`reader_screen.dart`（僅三處 `resolvePdfExistingAnnotation` 呼叫端）。

- [x] **Step 1（紅）：** 寫 `annotation_toolbar_layout_test.dart`：上方空間足夠 → 貼上方；不足 → 貼下方並 clamp；`annotationToolbarLeft` clamp 到 `size.width - 256`；測值取自現行 `_annotationToolbarTop`／`_pdfAnnotationToolbarTop` 公式。在 `annotation_resolution_test.dart` 把 `resolvePdfExistingAnnotation` 的呼叫改為 `pageIndex:`＋`rect:` 新簽章（此時為紅）。
- [x] **Step 2（綠）：** 新增 `annotation_toolbar_layout.dart`（常數 104／8／256 自 `reader_screen.dart` 約 2356–2358 搬入）；改 `resolvePdfExistingAnnotation` 簽章；`reader_screen.dart` 三處呼叫端改傳 `pageIndex:`＋`rect:`：約 1995 行（變數 `info`）、約 2126 行（變數 `selection`）、約 2799 行（變數 `pdfSelection`，build 內）；以 `grep -n resolvePdfExistingAnnotation` 為準，變數名不可全部套 `info`。**此 Task 不刪 `reader_screen.dart` 的舊定位方法**（Task 3 才換）。
- [x] **Step 3：** `flutter analyze`；跑 `test/reader/annotation_toolbar_layout_test.dart`、`annotation_resolution_test.dart`、`test/screens/reader_screen_test.dart`（標註與 PDF 退化選取相關案例，用 `--plain-name` 縮小）；commit。

### Task 2：`AnnotationController` 與測試

**Files：** 新增 `annotation_controller.dart`、`test/reader/annotation_controller_test.dart`（由 `annotation_session_test.dart` 以 `git mv` 改名後改寫）。

- [x] **Step 1：** `git mv test/reader/annotation_session_test.dart test/reader/annotation_controller_test.dart`；把 `AnnotationSession` 的案例改為對 `AnnotationController` 的狀態斷言（`reload` 後 `highlights`／`notes`；`createHighlight` 後清單與 `pendingHighlightId`；`saveNote` 新增／更新／帶 `pendingHighlightId`；`deleteExisting`）。`AnnotationSnapshot` 相等性案例隨類型刪除。
- [x] **Step 2（紅）：** 新增案例：`select` 重置 pending；`clearSelection`；`existingItem`（EPUB 以 id、PDF 以矩形重疊）；`createHighlight` 無選取不動作；`saveNote` 完成後選取與 pending 為 null；`isIgnoredPdfSelection` 三種情況（非退化、退化未命中、退化命中）；`AnnotationSelection.fromEpub`／`fromPdf` 欄位對映（PDF 的 `anchorRect` 是 `widgetRect`）。
- [x] **Step 3（綠）：** 實作 `annotation_controller.dart`（`AnnotationLocator` 自 `annotation_session.dart` 原樣搬入；controller 內部沿用其 repository 呼叫）。**同一個 commit** 把 `annotation_session.dart` 內的 `class AnnotationLocator` 刪除，改為 `export 'annotation_controller.dart' show AnnotationLocator;`（計畫審查 I-2：避免兩檔同名型別在 `reader_screen.dart` 同時 import 時衝突；全專案只有單一定義）。`annotation_session.dart` 與 `reader_screen.dart` 對它的使用暫時並存，Task 3 Step 3 刪除。
- [x] **Step 4：** `flutter analyze`；跑 `test/reader/annotation_controller_test.dart`、`annotation_resolution_test.dart`；commit。

### Task 3：`ReaderScreen` 遷移（計畫審查 C-1／I-1／I-3 修訂：選取、劃線、備註、工具列互相耦合，不可拆成會斷編譯的小步，改為 3 個 commit）

**Files：** `reader_screen.dart`、`annotation_session.dart`（Step 3 刪除）。

> 為什麼 Step 2 不能再拆：四個舊選取欄位被選取 handler（約 1871–1880、2007–2016）、劃線／備註 handler（約 2021–2070、2106–2149）、PDF 刪除與關閉（約 1918、2970）、build（約 2785、2786、2939、2960）同時讀寫；`_highlights`／`_notes` 的來源改到 controller 後，劃線／備註 handler 也必須同時改用 controller 的選取。若分開，會有兩份選取狀態並存，或中間 commit 找不到方法。

- [x] **Step 1（只去重，不動狀態；一個 commit）：** `_reloadAnnotationsAndRefreshDecorations`／`_reloadPdfAnnotationsAndSync` 合成 `_reloadAnnotations`；`_sendDecorationsToNative`／`_sendPdfAnnotationsToNative` 合成 `_sendAnnotationsToNative`；所有呼叫點（約 1519–1521、1564、1852、各 handler 內）同步改。`_highlights`、`_notes`、四個選取欄位、`_annotationSession` **全部保留**。`flutter analyze` 乾淨後跑 `reader_screen_test.dart` 全檔，commit。
- [x] **Step 2（狀態、選取、劃線、備註、刪除、工具列一次遷移；一個 commit）：** 先在 `pdf_reader_surface_test.dart` 確認 PDF `clearSelection()` 為空操作（已有案例；沒有則補一個，紅綠）。接著在同一個 commit 內完成下列全部：
  - 刪 `_highlights`、`_notes`、`_currentSelection`、`_pendingHighlightIdForSelection`、`_currentPdfSelection`、`_pendingPdfHighlightIdForSelection`、`_annotationSession`，新增 `late final AnnotationController _annotations = AnnotationController(highlightsRepository: widget.dependencies.highlightsRepository, notesRepository: widget.dependencies.notesRepository, bookId: widget.bookId)`；其餘讀 `_highlights`／`_notes` 之處改 `_annotations.highlights`／`.notes`（以 `grep -n "_highlights\|_notes\b"` 為準，避開其他同名欄位）；`import` 改為只引 `annotation_controller.dart`。
  - 選取：`_handleSelectionChanged`：`mounted` → `_session.recordActivity()` → `_isFixedLayout` 守衛 → `setState(() => _annotations.select(AnnotationSelection.fromEpub(info)))`。`_handlePdfSelectionRectComputed`：`mounted` → `isIgnoredPdfSelection(...)` 回 true 則 return → `_session.recordActivity()` → `setState(select(fromPdf(info)))`（順序逐字保留）。`_handleSelectionCleared`／`_handlePdfSelectionCanceled` 合成 `_handleSelectionCleared`，**所有呼叫點一併改**：接線（約 3345、3376）、PDF 換頁（約 3448、3466：`if (_annotations.selection != null) _handleSelectionCleared();` 後接 `cancelActiveSelectionDrag`，順序不變）、PDF 刪除（約 1918）、PDF 工具列關閉（約 2970）。約 3450 與 1891 行的註解若提到舊欄位或舊方法名，同步改字，讓驗收 grep 為 0（計畫審查 M-2）。
  - 劃線：`_handleHighlightStyleSelected`／`_handlePdfHighlightStyleSelected` 合成一個：`await _annotations.createHighlight(style); if (!mounted) return; setState(() {}); _sendAnnotationsToNative();`。
  - 備註：`_handleNotePressed`／`_handlePdfNotePressed` 合成一個：捕捉 `selection`（為 null 則 return）、`existing = _annotations.existingItem?.note`、跳 `showNoteTextDialog`（維持在 `ReaderScreen`）、**`if (text == null) return;`**（使用者取消對話框時選取與工具列不動，計畫審查 M-3）、`await _annotations.saveNote(selection: selection, text: text, existing: existing)`、`if (!mounted) return;`、`setState(() {})`、`_sendAnnotationsToNative()`。
  - 刪除與關閉：`_handleDeleteExistingAnnotation`／`_handlePdfDeleteExistingAnnotation` 合成：`await _annotations.deleteExisting(item)` → `mounted` → `setState` → `_sendAnnotationsToNative()` → `_handleCloseAnnotationToolbar()`。`_handleCloseAnnotationToolbar` = `_handleSelectionCleared()` ＋ `_surface.clearSelection()`，PDF 與 EPUB 共用。
  - 工具列：刪 `_annotationToolbarTop`、`_pdfAnnotationToolbarTop` 與三個常數；build 內兩個 `Positioned(AnnotationToolbar)` 合成一個（`_annotations.selection != null` 時以 `annotationToolbarLeft/Top` 定位，錨點取 `selection.anchorRect`；`onLookupPressed` 只在 `_surface.foliate != null` 時傳入；`existingItem` 取自 `_annotations.existingItem`，刪除 build 內原本的 `existingItem`／`pdfExistingItem` 區域變數；`onStyleSelected`／`onNotePressed`／`onDeletePressed` 改指合併後的方法，PDF 專屬回呼不再存在，計畫審查 I-3）。
  - 驗證：跑 `reader_screen_test.dart` 全檔（含標註約 4676–5010、PDF 約 8713–9125、10262–10451）、`annotation_toolbar_test.dart`、`reader_screen_surface_test.dart`、`reader_screen_stats_activity_test.dart`、`annotation_controller_test.dart`。commit。
- [x] **Step 3（刪舊；一個 commit）：** `git rm app/lib/reader/annotation_session.dart`；`grep -rn "annotation_session\|AnnotationSession\|AnnotationSnapshot" app/lib app/test` 應為 0（不含註解）；`flutter analyze`；commit。

### Task 4：收尾

- [x] **Step 1（設計定案時已完成）：** `CONTEXT.md` 新增「標註」詞條（劃線＋備註的選取、待存劃線與清單，歸 `AnnotationController` 管；View 只回報選取與重畫）。
- [x] **Step 2：** `epic.md` 開發記錄；`issues.md` Issue 24 狀態；Issue 23 狀態改為「🟢 已合併（PR #361）」並註記 Issue 28 的診斷插樁已於 Issue 23 刪除；`docs/epics.md` 對應列同步更新。
- [x] **Step 3：** 驗收：`grep -n "_currentPdfSelection\|_pendingPdfHighlightIdForSelection\|_pdfAnnotationToolbarTop\|_sendPdfAnnotationsToNative\|_reloadPdfAnnotationsAndSync" app/lib/screens/reader_screen.dart` 應為 0（含註解行；Task 3 Step 2 已要求同步改註解）。
- [x] **Step 4：** `flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；完整 `flutter test`（`run_in_background`，只跑一個）。
- [x] **Step 5：** WAVE 真機抽驗（EPUB 與 PDF 各一本）：劃線四種樣式、備註新增／編輯、刪除既有標註、PDF 單點長按不彈工具列、PDF 長按拖曳框選、換頁清選取、工具列不超出螢幕邊緣、EPUB 查字典後選取還原。
- [x] **Step 6：** 程式審查（報告存 `reviews/review-code-issue-24.md`，不進版控）；開 PR。
