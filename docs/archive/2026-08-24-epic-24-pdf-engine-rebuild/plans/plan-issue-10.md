# Epic 24 Issue 10 — PDF 換頁時清除既有劃線選取與工具列 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復真機回報「PDF 畫線工具列換頁後仍然存在」的問題——PDF 換頁（`_handleZoneAction` 的 `previousPage`/`nextPage` 分支）時，主動清除既有框選狀態（`_currentPdfSelection`），讓 `AnnotationToolbar` 隨之消失。

**Architecture:** PDF 的框選狀態是純 Dart 端矩形選取（`_currentPdfSelection`），不像 EPUB 能依賴 WebView 瀏覽器原生「切頁自動清空 `window.getSelection()`」語意觸發 `onSelectionCleared`；`_handleZoneAction`（`app/lib/screens/reader_screen.dart:2379`）的 PDF `previousPage`/`nextPage` 分支目前只呼叫 `PdfReaderView.previousPage`/`nextPage`，完全沒有清除選取的邏輯，這是 PDF 架構上就沒有等價「換頁自動清除選取」訊號來源的直接後果。既有 `_handlePdfSelectionCanceled()`（`:1175`，`setState()` 清空 `_currentPdfSelection`／`_pendingPdfHighlightIdForSelection`，`AnnotationToolbar` 依 `_currentPdfSelection != null` 決定是否顯示）已存在、已被其他呼叫端（`onSelectionCanceled` 回呼、關閉按鈕）使用，本次只需在換頁分支多呼叫一次。

**Tech Stack:** Flutter/Dart，無新增依賴。

## Global Constraints

- **本 Issue 原始文件（`issues.md` Issue 10）描述的「建議修復方向」有兩項，(b)「新增手動關閉工具列入口」已被 `epic-25-annotation-interaction-qa` Issue 3 完整實作並合併（`AnnotationToolbar` 新增 `onClosePressed`／`Key('annotation_toolbar_close')` 關閉按鈕，EPUB／PDF 呼叫端皆已接線：EPUB 用 `_handleCloseAnnotationToolbar`、PDF 直接沿用既有 `_handlePdfSelectionCanceled`，見 `reader_screen.dart:1161`、`:2007`）——本計畫刻意不重複實作這部分，只處理仍未解決的 (a)「換頁不會自動清除選取」。**
- `_handlePdfHighlightStyleSelected` 選色後刻意不清空 `_currentPdfSelection`（讓工具列保持開啟以便續加備註，與 EPUB 對稱的既有設計，非 bug）——本計畫不改變這個既有行為，只新增「換頁」這一個額外的清除觸發點。
- 只修改 `_handleZoneAction` 的 PDF `previousPage`/`nextPage` 分支，不修改 `_handlePdfSelectionCanceled()`／`AnnotationToolbar`／EPUB 對應分支既有邏輯本體。
- 提交前必須 `flutter analyze` 乾淨（"No issues found!"），`flutter test` 全數通過，不得有回歸。

---

### Task 1：PDF 換頁時清除既有選取狀態

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:2379-2404`（`_handleZoneAction`）
- Test: `app/test/screens/reader_screen_test.dart`（新增 1 項測試）

**Interfaces:**
- Consumes：既有 `_currentPdfSelection`（`PdfSelectionInfo?` 欄位）、`_handlePdfSelectionCanceled()`（既有無參數方法，`:1175`）。
- Produces：無新增可供其他 Task 呼叫的函式——純粹是 `_handleZoneAction` 既有分支內多一行呼叫。

- [x] **Step 1：寫失敗測試——換頁應清除既有選取，AnnotationToolbar 隨之消失**

在 `app/test/screens/reader_screen_test.dart` 找到既有測試「PDF：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失」（約 line 5722）之後，新增：

```dart
  testWidgets(
      'PDF 換頁時應清除既有選取狀態，AnnotationToolbar 隨之消失（Epic 24 Issue 10）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_page_turn_clears_selection',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));

    // 情境 A：nextPage 應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar');

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: 'nextPage 換頁後應清空選取狀態，工具列從畫面消失');

    // 情境 B：previousPage 同樣應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 1,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '第二次選取完成後應再次顯示 AnnotationToolbar');

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: 'previousPage 換頁後同樣應清空選取狀態，工具列從畫面消失');
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Epic 24 Issue 10"`
Expected: FAIL——兩處 `expect(find.byType(AnnotationToolbar), findsNothing, ...)` 皆會失敗（`AnnotationToolbar` 目前換頁後仍找得到，因為 `_handleZoneAction` 沒有清除 `_currentPdfSelection`）。

- [x] **Step 3：實作修法**

修改 `app/lib/screens/reader_screen.dart:2379-2404`，從：

```dart
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
```

改為：

```dart
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：PDF 框選狀態是純 Dart 端矩形選取，沒有
          // EPUB 那種 WebView 切頁自動清空 window.getSelection() 的
          // 瀏覽器原生語意可依賴，換頁時需主動清除既有選取與工具列，
          // 避免選取範圍/AnnotationToolbar 殘留在已經翻過的頁面上。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：理由同上方 previousPage 分支。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
        } else if (format == BookFormat.epub) {
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
```

- [x] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Epic 24 Issue 10"`
Expected: PASS。

- [x] **Step 5：執行既有 PDF 選取／換頁相關測試確認零回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "PDF"`
Expected: 全數 PASS——特別確認既有「PDF：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失」「PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar」「_handleZoneAction(previousPage/nextPage) 不影響 AppBar 顯示狀態（PDF，design.md 決策 #14）」三項既有測試皆不受影響（後者驗證換頁不影響 `_chromeVisible`，本次修法未觸碰該邏輯）。

- [x] **Step 6：執行完整測試套件確認全域無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（含 Step 1 新增的 1 項測試，以及既有全部測試）。

- [x] **Step 7：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 8：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-24): Issue 10——PDF 換頁時清除既有劃線選取與工具列"
```

---

### Task 2：收尾文件更新

**Files:**
- Modify: `docs/epics/epic-24-pdf-engine-rebuild/issues.md`（Issue 10 `Status` 行）
- Modify: `docs/epics.md`（epic-24 該列備註）

**Interfaces:**
- Consumes：Task 1 的程式碼變更（無新介面）。
- Produces：無。

- [x] **Step 1：更新 `issues.md` Issue 10 狀態**

修改 `docs/epics/epic-24-pdf-engine-rebuild/issues.md`，把 Issue 10 的 `Status` 行：

```markdown
**Status:** ready-for-agent
```

改為：

```markdown
**Status:** ✅ 已修復。建議修復方向 (b)「新增手動關閉工具列入口」已由 `epic-25-annotation-interaction-qa` Issue 3 完整實作並合併（`AnnotationToolbar` 新增關閉按鈕，EPUB／PDF 皆已接線），本工單只需處理仍未解決的 (a)：`_handleZoneAction` 的 PDF `previousPage`/`nextPage` 分支新增 `_currentPdfSelection != null` 時呼叫既有 `_handlePdfSelectionCanceled()`，換頁即清空選取與工具列。新增 1 項 widget test（涵蓋 `nextPage`／`previousPage` 兩條路徑）驗證換頁後 `AnnotationToolbar` 正確消失，既有選取／換頁相關測試零回歸，`flutter analyze` 乾淨。
```

- [x] **Step 2：更新 `docs/epics.md` epic-24 該列備註**

修改 `docs/epics.md` 的 `epic-24-pdf-engine-rebuild` 該列（搜尋 `epic-24-pdf-engine-rebuild`），把行尾「**Issue 10、Issue 11 尚未實作修復**」改為：

```markdown
**Issue 10（PDF 劃線工具列換頁後不會自動隱藏）已修復**：`_handleZoneAction` PDF 換頁分支新增清除既有選取的呼叫，1 項新增 widget test（涵蓋 nextPage／previousPage）驗證，既有測試零回歸；建議修復方向中的「手動關閉入口」部分已由 `epic-25-annotation-interaction-qa` Issue 3 提前完成，本工單未重複實作。**Issue 11 尚未實作修復**；
```

- [x] **Step 3：Commit**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/issues.md docs/epics.md
git commit -m "docs(epic-24): Issue 10 更新進度——PDF 換頁清除選取已修復"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 10 根因 #2（PDF 換頁不清除選取的架構性缺口）與建議修復方向 (a) 由 Task 1 完整覆蓋；建議修復方向 (b)（手動關閉入口）已查證確認由 `epic-25-annotation-interaction-qa` Issue 3 提前完成，本計畫明確記錄此發現（見 Global Constraints），不重複實作，避免下一位讀者誤以為這是本計畫的遺漏。
- **No Placeholders 掃描**：Task 1 的程式碼、測試程式碼、預期輸出皆為實際可執行內容；Step 2 明確說明失敗原因（兩處 `findsNothing` 斷言會因目前程式碼未清除選取而失敗），非空泛描述。
- **型別/介面一致性**：本計畫沒有新增任何函式或型別，只在 `_handleZoneAction` 既有兩個分支內各多一行呼叫既有的 `_handlePdfSelectionCanceled()`（無參數、`void` 回傳，簽章與既有呼叫端一致）。
- **既有測試不回歸的具體論證**：新增的呼叫只在 `_currentPdfSelection != null` 時才觸發 `setState()`，沒有選取時（多數換頁情境）行為與修法前完全相同；`_handlePdfSelectionCanceled()` 本身是既有、已被其他路徑（關閉按鈕、`onSelectionCanceled` 回呼）驗證過的方法，不是新邏輯。Task 1 Step 5-6 安排實際執行既有測試套件（含明確驗證換頁不影響 `_chromeVisible` 的既有測試）作為實測佐證。
- **範圍誠實聲明**：本計畫刻意不處理 Issue 11（PDF 換頁動畫選項），維持獨立工單；也刻意不重新實作已由 `epic-25` Issue 3 完成的手動關閉按鈕，避免重複勞動或與既有實作衝突。
