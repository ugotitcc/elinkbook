# Issue 23：閱讀面 module 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把 `ReaderScreen` 對 `FoliateReaderView`／`PdfReaderView` 的 static 呼叫與格式分支，收成一個只含共通指令的 `ReaderSurface` interface；`GlobalKey` 移進 adapter；測試用 fake 取代。純重構、零行為變化。

**Architecture：** 新增 `app/lib/reader/reader_surface.dart`（interface、兩個專屬 facet、fake 不在此檔）、`foliate_reader_surface.dart`、`pdf_reader_surface.dart`、`test/support/fake_reader_surface.dart`。`ReaderFeatureDependencies` 新增 `readerSurfaceFactory`（預設為正式工廠），`ReaderScreen` 在 `initState` 依 `detectBookFormat()` 建立一次。兩個 View 的 static 方法與其測試不動，adapter 是它們唯一的呼叫端。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 23 設計決策」（決策 1～12）；詞彙見 `CONTEXT.md`「閱讀面」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構、零行為變化**（決策 1）：fire-and-forget 不得改成 await；呼叫順序、`mounted` 檢查逐字保留；View 未掛載時指令靜默忽略、查詢回 `const []`／`0`／`null`（決策 5），要改行為另開 Issue。
- **範圍外**：不收 View 建構與 callback（決策 3）；不動兩個 View 的 static 方法與其測試（決策 8）；不動 `triggerZoneAction`、`togglePdfBookmark`、`openPdfToc`、`openSleepTimerPickerForTest`、`reportTtsPlayingForTest`（與閱讀面無關）；不動搜尋跳轉高亮的 3 秒計時器與 `_creationZone.run`（留給 Issue 28）。
- **不新增 `ReaderScreen` 建構參數**（目前 27 個）；fake 只經 `ReaderFeatureDependencies` 注入（決策 6）。
- **測試原則（replace, don't layer）**：指令轉發規則放新的單元測試；`reader_screen_test.dart` 只保留接線與純 UI 案例，被取代的舊案例刪除，不並存。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯檔案時以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`（使用者規定）。每個 Task 一個 commit；Task 5 每組遷移一個 commit。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到使用者的情況（依可能性排序）：

1. **翻頁／跳轉打到錯的 View。** 雙格式分支搬進 adapter 後，PDF 與 Foliate 指令對調或漏接。→ Task 2、3 各測「每個指令轉發給對的 View」，Task 5 逐組遷移後跑 `reader_screen_test.dart` 該組案例。
2. **查字典時選字水滴又浮在面板上方。** `suspendSelection`／`restoreSelection` 必須仍只對 Foliate 生效（PR #359）。→ Task 2 測轉發；Task 3 測 PDF 為空操作。
3. **PDF 換頁時，進行中的長按拖曳框選沒被中止。** 現況 `reader_screen.dart` 約 3508、3526 在換頁前呼叫 `cancelActiveSelectionDrag`。→ 保留在 PDF facet，Task 5 翻頁組驗證順序（先中止拖曳、再換頁）。
4. **跳轉後高亮疊加與否判錯。** `ReaderJumpTarget.applyTo` 的回傳值決定 3 秒計時器是否啟動。→ Task 4 逐字沿用 `reader_jump_target_test.dart` 30 處案例。
5. **View 尚未掛載就收到指令而拋例外。** → Task 2、3 測未掛載的靜默忽略與預設回傳值。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/reader_surface.dart` | 新增 | `ReaderSurface` interface、`FoliateFacet`、`PdfFacet`、`ReaderSurfaceFactory` typedef |
| `app/lib/reader/foliate_reader_surface.dart` | 新增 | Foliate adapter；持有 `GlobalKey<State<FoliateReaderView>>` |
| `app/lib/reader/pdf_reader_surface.dart` | 新增 | PDF adapter；持有 `GlobalKey<State<PdfReaderView>>` |
| `app/test/support/fake_reader_surface.dart` | 新增 | 記錄指令的 fake |
| `app/test/reader/reader_surface_test.dart`、`foliate_reader_surface_test.dart`、`pdf_reader_surface_test.dart` | 新增 | interface 契約、兩個 adapter 的轉發與未掛載規則 |
| `app/lib/reader/reader_jump_target.dart` | 修改 | `applyTo` 改收 `ReaderSurface`，不再吃兩把 key |
| `app/lib/screens/reader_feature_dependencies.dart` | 修改 | 新增 `readerSurfaceFactory`（預設正式工廠） |
| `app/lib/screens/reader_screen.dart` | 修改 | 刪兩把 `GlobalKey`、改用 `_surface`；刪診斷插樁；刪 `loadTableOfContentsForTest` |
| `app/test/screens/reader_screen_test.dart` 等 | 修改 | 遷移指令轉發案例；刪被取代的舊案例 |
| `CONTEXT.md` | 已完成 | 「閱讀面」詞條（設計定案時已加） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

## Interface 草案（Task 1 以此為起點，以實際編譯與既有型別為準）

```dart
/// 閱讀面：ReaderScreen 對「目前這本書的渲染畫面」下指令的單一 interface。
/// View 尚未掛載時，指令靜默忽略，查詢回傳預設值。
abstract class ReaderSurface {
  void nextPage();
  void previousPage();

  /// 只導覽，不疊高亮。依 target 的欄位決定：cfi（Foliate）、progression
  /// （Foliate 進度條）、pdfPageIndex（PDF）。
  void jumpTo(ReaderJumpTarget target);

  /// 疊加搜尋跳轉暫態高亮；回傳本次是否真的疊加（決定 3 秒計時器是否啟動）。
  bool showTransientHighlight(ReaderJumpTarget target);
  void clearTransientHighlight();

  void clearSelection();
  void suspendSelection(); // PDF：空操作（選取框由 Flutter 自己畫，不會浮在面板上）
  void restoreSelection();

  /// 整組重畫標註；各格式把 Highlight／Note 轉成自己的裝飾型別。
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required Color Function(HighlightStyle) highlightTint,
    required Color noteOnlyTint,
  });

  Future<List<BookTocItem>> loadTableOfContents();

  /// 格式專屬功能：恰有一個非 null。
  FoliateFacet? get foliate; // viewKey、TTS（載入段落、顯示／清除朗讀高亮、反查起始段）
  PdfFacet? get pdf; // viewKey、cancelActiveSelectionDrag、search／setSearchHighlights、jumpToPageAtRect、renderThumbnail
}
```

> 與 epic 決策 4 的細化：「跳轉」拆成 `jumpTo`（只導覽）與 `showTransientHighlight`（疊高亮），因為目錄／書籤跳轉不疊高亮，原 `applyTo` 只服務搜尋跳轉。`ReaderJumpTarget.applyTo` 保留為「依 `shouldNavigate` 組合兩者」的薄方法，改收 `ReaderSurface`。

---

### Task 0：提交計畫、建立 worktree

- [ ] **Step 1：** 在 `main` 提交本計畫與 `issues.md` 狀態更新（純文件）。
- [ ] **Step 2：** 建立 worktree `.worktrees/epic-54-issue-23-reader-surface`，分支 `epic-54/issue-23-reader-surface`；後續 Task 都在這個 worktree 的 `app/` 下執行。

### Task 1：interface、fake、契約測試

**Files：** 新增 `reader_surface.dart`、`test/support/fake_reader_surface.dart`、`test/reader/reader_surface_test.dart`。

- [ ] **Step 0（先確認前提）：** 確認 `TocEntry` 與 `PdfTocItem` 是否都實作 `BookTocItem`（`grep -rn "implements BookTocItem\|extends BookTocItem" app/lib`）；若不是，`loadTableOfContents` 改回傳兩個 facet 各自的型別，這一步的結論寫進 `epic.md` 開發記錄。
- [ ] **Step 1（紅）：** 寫契約測試：fake 記錄每個指令；「恰有一個 facet 非 null」；`ReaderJumpTarget` 的 `progression` 欄位（新增，`double?`）可用 `const ReaderJumpTarget(progression: 0.5)` 建構。
- [ ] **Step 2（綠）：** 實作 interface、facet、fake、`ReaderJumpTarget.progression`；`flutter analyze`、跑本 Task 測試。
- [ ] **Step 3：** commit。

### Task 2：Foliate adapter

**Files：** 新增 `foliate_reader_surface.dart`、`test/reader/foliate_reader_surface_test.dart`。

- [ ] **Step 1（紅）：** 未掛載（key 沒有 State）時：所有指令不拋例外；`loadTableOfContents` 回 `const []`；TTS `loadSegments` 回 `const []`、`lookupSegmentByCfi` 回 `0`。已掛載的轉發靠既有 `foliate_reader_view_*_test` 驗證 JS 呼叫，這裡用 `fake_inappwebview_platform` 掛一個 View，確認 `nextPage`／`previousPage`／`jumpTo`（cfi、progression）／`clearSelection`／`suspendSelection`／`restoreSelection` 各自送出對應的 `window.*()`。
- [ ] **Step 2（綠）：** adapter 逐一轉呼叫 `FoliateReaderView.<static>(viewKey, …)`；`refreshAnnotations` 內放 `reader_screen.dart` 約 2118–2133 的 `EpubDecoration` 轉換（原樣搬移）。
- [ ] **Step 3：** `flutter analyze`、跑本 Task 測試、commit。

### Task 3：PDF adapter

**Files：** 新增 `pdf_reader_surface.dart`、`test/reader/pdf_reader_surface_test.dart`。

- [ ] **Step 1（紅）：** 未掛載的靜默忽略與預設值（`search` 回 `const []`、`renderThumbnail` 回 `null`）；`suspendSelection`／`restoreSelection`／`clearSelection` 為空操作；已掛載時（用 `pump_until_pdf_ready.dart`）`nextPage`／`previousPage`／`jumpTo(pdfPageIndex)`／`showTransientHighlight`（回傳 true／false 的兩種條件）／`clearTransientHighlight` 轉發正確。
- [ ] **Step 2（綠）：** adapter 轉呼叫 `PdfReaderView.<static>`；`refreshAnnotations` 內放 `reader_screen.dart` 約 2205–2221 的 `PdfAnnotationDecoration` 轉換（原樣搬移）。
- [ ] **Step 3：** `flutter analyze`、跑本 Task 測試、commit。

### Task 4：`ReaderJumpTarget.applyTo` 改收 `ReaderSurface`

**Files：** 修改 `reader_jump_target.dart`、`test/reader/reader_jump_target_test.dart`。

- [ ] **Step 1（紅）：** 把 `reader_jump_target_test.dart` 中 13 處 `applyTo` 案例改成傳 `FakeReaderSurface`，斷言指令序列與回傳值，保持每個案例原本的意圖（PDF 只有頁碼→跳頁但回 `false`；格式 unknown→回 `false`；`shouldNavigate: false` 不導覽）。
- [ ] **Step 2（綠）：** `applyTo({required ReaderSurface surface, required bool shouldNavigate})`：`shouldNavigate` 時 `surface.jumpTo(this)`，再 `return surface.showTransientHighlight(this)`；格式判斷由 adapter 處理，`unknown` 格式時 `ReaderScreen` 不會建立 surface，行為見 Task 5。
- [ ] **Step 3：** 跑 `reader_jump_target_test.dart`、`pdf_reader_view_paginated_test.dart`，commit。

### Task 5：`ReaderScreen` 逐組遷移呼叫

**Files：** 修改 `reader_screen.dart`；每組遷移後跑 `reader_screen_test.dart` 對應案例。

- [ ] **Step 1：** 加入 `late final ReaderSurface _surface`（`initState` 依 `detectBookFormat()` 建立；`BookFormat.unknown` 的處理沿用現況——現況 `unknown` 不會走到任何 static 呼叫，adapter 對 `unknown` 回傳「全部空操作的 Foliate adapter」前，先確認 `reader_screen.dart` 的分派，並把結論寫進 commit 訊息）。此時 `_foliateEpubReaderViewKey`／`_pdfReaderViewKey` 仍存在，由 `_surface.foliate!.viewKey`／`_surface.pdf!.viewKey` 取代放到 Step 9。
- [ ] **Step 2（翻頁，commit）：** 約 3388、3390、3497–3530、2929–2930。PDF 換頁前的 `cancelActiveSelectionDrag` 保留在換頁指令之前（Review Focus 3）。
- [ ] **Step 3（跳轉，commit）：** 約 1338、1397、1409、1449–1470、1526、1537、1613、1669、3141；`jumpToPageAtRect`（PDF 搜尋）走 `pdf` facet。
- [ ] **Step 4（清暫態高亮／清選取，commit）：** 約 1649–1651、1913、1947、1975。計時器與 `_creationZone.run` 原樣保留（範圍外）。
- [ ] **Step 5（標註重畫，commit）：** 約 2133、2221；兩個 `_reloadAnnotations…` 方法保留，只把裝飾轉換換成 `_surface.refreshAnnotations(…)`。
- [ ] **Step 6（目錄，commit）：** 約 1402、1583、1860；`.then` 與 `mounted` 檢查逐字保留。
- [ ] **Step 7（Foliate 專屬 TTS，commit）：** 約 3225、3238、3240、3257，改走 `_surface.foliate!`。
- [ ] **Step 8（PDF 專屬，commit）：** 約 1402、1433–1471，改走 `_surface.pdf!`。
- [ ] **Step 9（收尾，commit）：** 刪兩把 `GlobalKey` 欄位（約 419、425），View 建構處（約 3308、3400）的 `key:` 改取 `viewKey`；刪 `[DEBUG-e26i3-zoneaction]` 診斷插樁（約 3491–3520，Issue 28 縮小併入）。
- [ ] **Step 10：** 驗收 grep（`app/` 下）：
  `grep -nE "FoliateReaderView\.[a-z]|PdfReaderView\.[a-z]" lib/screens/reader_screen.dart` 必須無輸出（建構子 `FoliateReaderView(`／`PdfReaderView(` 不算）。

### Task 6：注入與 wiring

**Files：** 修改 `reader_feature_dependencies.dart`、`reader_screen.dart`、`test/…/elinkbook_app_wiring_test.dart`；刪除 `loadTableOfContentsForTest`。

- [ ] **Step 1（紅）：** wiring 測試加案例：預設的 `readerSurfaceFactory` 對 PDF 與 Foliate 格式各建出對應 adapter；傳入 fake 工廠時，`ReaderScreen` 的指令落到 fake。確認既有的身分比對案例不受影響。
- [ ] **Step 2（綠）：** `ReaderFeatureDependencies` 新增欄位（有預設值，`main.dart` 不改）；`ReaderScreen` 以 `widget.dependencies.readerSurfaceFactory(format)` 建立 `_surface`。
- [ ] **Step 3：** 刪除 `ReaderScreen.loadTableOfContentsForTest`；`integration_test/foliate_txt_test.dart`、`foliate_md_test.dart` 的呼叫改走新路徑（`node tool/check_integration_keys.js` 須通過）。
- [ ] **Step 4：** `flutter analyze`、跑 wiring 與相關測試、commit。

### Task 7：遷移 `reader_screen_test.dart` 的指令轉發案例

- [ ] **Step 1（盤點，先寫結論再動手）：** 列出 `reader_screen_test.dart`（12803 行）與 `reader_screen_stats_*` 中「驗證翻頁／跳轉／清高亮／重畫標註／載入目錄指令有沒有送到 View」的案例；每個案例標「遷移」或「留原檔（純 UI／接線）」。盤點表寫進 `epic.md` 開發記錄。
- [ ] **Step 2：** 「遷移」案例改用 `FakeReaderSurface`（經 dependencies 注入）驗證，舊案例同一 commit 內刪除。
- [ ] **Step 3：** 跑 `reader_screen_test.dart` 與被觸及的測試檔、commit。

### Task 8：收尾

- [ ] **Step 1：** `flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js` 通過。
- [ ] **Step 2：** 再跑一次 Task 5 Step 10 的 grep（必須無輸出）。
- [ ] **Step 3：** 完整 `flutter test`（`run_in_background`），結果寫進 `epic.md` 開發記錄。
- [ ] **Step 4：** 程式審查（報告存 `reviews/`），處理後再開 PR。
- [ ] **Step 5（WAVE 真機抽驗）：** 開 EPUB 與 PDF 各一本：翻頁、目錄跳轉、搜尋跳轉高亮、劃線、查字典（水滴不浮出、關面板後選取還原）。
- [ ] **Step 6：** 更新 `issues.md`、`docs/epics.md` 狀態；Issue 28 在 `issues.md` 註記「診斷插樁已於 Issue 23 刪除」。
