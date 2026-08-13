# Epic 24 Issue 9 — PDF 劃線拖曳選取時與 PdfViewer 內建 pan/zoom 手勢衝突 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復使用者真機回報「長按拖曳劃線時頁面內容跟著亂跳」的問題——`PdfReaderView` 框選拖曳進行中，動態關閉底層 `pdfrx` `PdfViewer` 的平移／縮放（`panEnabled`/`scaleEnabled`），拖曳結束或取消後立即恢復。

**Architecture:** `_buildSelectionGestureLayer`（`app/lib/reader/pdf_reader_view.dart:1066`）用標準 `GestureDetector`（會進入 Flutter 手勢競技場）實作長按拖曳框選；但 `pdfrx` 的 `PdfViewer` 內部用 `Listener`（`pdfrx-2.4.7/lib/src/widgets/pdf_viewer.dart:609-611`，不參與手勢競技場）驅動 `InteractiveViewer` 平移／縮放，導致不論框選手勢是否已贏得競技場，`PdfViewer` 都會同時、無條件收到同一組原始 pointer 事件並據此平移／縮放內容。`PdfViewerParams` 已提供 `panEnabled`/`scaleEnabled` 兩個 `bool` 建構參數（`pdfrx-2.4.7/lib/src/widgets/pdf_viewer_params.dart:55-56`，皆預設 `true`，語意對應 `InteractiveViewer.panEnabled`/`scaleEnabled`）。`_PdfReaderViewState` 已有 `_selectionDrag`（`_PdfSelectionDragState?`，非 null 代表框選拖曳進行中，由 `onLongPressStart`/`onLongPressMoveUpdate`/`_finishSelectionDrag`/`_cancelSelectionDrag` 四處以 `setState()` 維護，見 `:273`、`:1073`、`:1084`、`:1095`、`:1125`）——`build()` 內建構 `PdfViewerParams` 時直接依 `_selectionDrag == null` 傳入這兩個旗標，不需要新增任何狀態欄位，`setState()` 呼叫既有的重建時機天然涵蓋這個需求。

**Tech Stack:** Flutter/Dart，`pdfrx` 既有 API（`PdfViewerParams.panEnabled`/`scaleEnabled`），無新增依賴。

## Global Constraints

- 本計畫只變更 `PdfViewerParams` 的 `panEnabled`/`scaleEnabled` 兩個既有欄位的傳入值，不修改 `_buildSelectionGestureLayer`／`_finishSelectionDrag`／`_cancelSelectionDrag` 既有的框選手勢邏輯本體。
- 根因（`Listener` 不參與手勢競技場、與框選 `GestureDetector` 同時收到原始 pointer 事件）已用套件原始碼交叉查證，信心高，但**尚未在真機實際重現過症狀本身**（見 `issues.md` Issue 9「根因假設」段落原文）——本計畫的驗證手段限於 widget test（確認 `panEnabled`/`scaleEnabled` 依 `_selectionDrag` 狀態正確切換），修復後是否真的解決真機回報的「頁面亂跳」症狀、以及一般雙指縮放／單指平移手感是否受影響，仍需要真機驗證，不在本計畫範圍內完成，於 Task 2 收尾時誠實記錄為已知殘留限制。
- 提交前必須 `flutter analyze` 乾淨（"No issues found!"），`flutter test` 全數通過，不得有回歸。

---

### Task 1：框選拖曳進行中動態關閉 `PdfViewer` 平移／縮放

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart:875-893`（`PdfViewerParams(...)` 建構）
- Test: `app/test/reader/pdf_reader_view_selection_test.dart`（新增 2 項測試）

**Interfaces:**
- Consumes：既有 `_selectionDrag`（`_PdfSelectionDragState?` 欄位）、`PdfViewerParams.panEnabled`/`scaleEnabled`（`pdfrx` 套件既有建構參數，`bool`，預設 `true`）。
- Produces：無新增可供其他 Task 呼叫的函式或欄位——純粹是既有 `build()` 內建構 `PdfViewerParams` 時多傳兩個參數。

- [x] **Step 1：寫失敗測試——框選拖曳進行中應關閉底層平移／縮放**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 找到既有測試「長按拖曳後放開，觸發 onSelectionRectComputed 且矩形座標在合理範圍內」（約 line 55）之後，新增：

```dart
  testWidgets('框選拖曳進行中，PdfViewer 的 panEnabled/scaleEnabled 應暫時關閉；放開後恢復',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfViewerParams paramsOf() =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

    expect(paramsOf().panEnabled, isTrue, reason: '拖曳開始前應維持預設可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '拖曳開始前應維持預設可縮放');

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

    expect(paramsOf().panEnabled, isFalse, reason: '框選拖曳進行中應關閉底層平移，避免與長按框選手勢衝突');
    expect(paramsOf().scaleEnabled, isFalse, reason: '框選拖曳進行中應關閉底層縮放');

    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();

    expect(paramsOf().panEnabled, isFalse, reason: '拖曳移動過程中仍應維持關閉');

    await gesture.up();
    await tester.pump();

    expect(paramsOf().panEnabled, isTrue, reason: '放開手指、選取完成後應恢復可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '放開手指、選取完成後應恢復可縮放');
  });

  testWidgets('框選拖曳被第二指觸控取消後，PdfViewer 的 panEnabled/scaleEnabled 應恢復',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfViewerParams paramsOf() =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger =
        await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();

    expect(paramsOf().panEnabled, isFalse, reason: '框選拖曳進行中應關閉底層平移');

    final secondFinger =
        await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(paramsOf().panEnabled, isTrue, reason: '第二指觸控取消框選後應恢復可平移');
    expect(paramsOf().scaleEnabled, isTrue, reason: '第二指觸控取消框選後應恢復可縮放');

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart --plain-name "panEnabled"`
Expected: 兩項測試皆 FAIL——`PdfViewerParams` 目前沒有傳入 `panEnabled`/`scaleEnabled`，`pdfrx` 套件預設值恆為 `true`，斷言 `paramsOf().panEnabled, isFalse` 那幾行會失敗。

- [x] **Step 3：實作修法**

修改 `app/lib/reader/pdf_reader_view.dart:875-893`，從：

```dart
      params: PdfViewerParams(
        layoutPages: _cropEnabled
            ? _layoutCroppedPages
            : (_dualPageEnabled ? _layoutSpreadPages : null),
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
        pageOverlaysBuilder: _buildProcessedOverlay,
        onViewerReady: (doc, controller) {
          if (!_renderedNotified) {
            _renderedNotified = true;
            widget.onPageRendered();
          }
          widget.onPageChanged?.call(PdfPageInfo(
            pageIndex: (controller.pageNumber ?? 1) - 1,
            totalPages: controller.pageCount,
          ));
        },
        onPageChanged: _handlePageChanged,
      ),
```

改為：

```dart
      params: PdfViewerParams(
        layoutPages: _cropEnabled
            ? _layoutCroppedPages
            : (_dualPageEnabled ? _layoutSpreadPages : null),
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
        pageOverlaysBuilder: _buildProcessedOverlay,
        // Epic 24 Issue 9：pdfrx 的 PdfViewer 內部用 Listener（不參與手勢
        // 競技場）驅動平移/縮放，與 _buildSelectionGestureLayer 的長按
        // 拖曳框選 GestureDetector 會同時、無條件收到同一組原始 pointer
        // 事件，導致長按拖曳劃線時頁面內容跟著平移/縮放亂跳（真機回報，
        // 見 docs/epics/epic-24-pdf-engine-rebuild/issues.md Issue 9）。
        // 框選拖曳進行中（_selectionDrag != null）暫時關閉底層平移/縮放，
        // 放開/取消後（_selectionDrag 變回 null）恢復。
        panEnabled: _selectionDrag == null,
        scaleEnabled: _selectionDrag == null,
        onViewerReady: (doc, controller) {
          if (!_renderedNotified) {
            _renderedNotified = true;
            widget.onPageRendered();
          }
          widget.onPageChanged?.call(PdfPageInfo(
            pageIndex: (controller.pageNumber ?? 1) - 1,
            totalPages: controller.pageCount,
          ));
        },
        onPageChanged: _handlePageChanged,
      ),
```

- [x] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart --plain-name "panEnabled"`
Expected: 兩項測試皆 PASS。

- [x] **Step 5：執行整份選取測試檔案確認既有測試零回歸**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數 PASS（新增 2 項＋既有全部測試，含「不傳選取回呼時，行為與 Issue 1/2/3 完全相同（零回歸基準）」「框選進行中第二指觸控介入時，取消選取並觸發 onSelectionCanceled」「cropEditModeActive=true 時，長按拖曳不觸發框選」等）。

- [x] **Step 6：執行其餘 PDF 相關測試套件確認無交叉回歸**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_filters_test.dart test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 全數 PASS——`panEnabled`/`scaleEnabled` 在 `_selectionDrag == null`（預設狀態，本計畫變更前後皆為 `true`）時行為不變，這些測試不涉及框選拖曳，理論上零回歸；本步驟用實際執行結果佐證，而非僅憑推論。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "fix(epic-24): Issue 9——框選拖曳進行中暫時關閉 PdfViewer 平移/縮放，避免與內建手勢衝突"
```

---

### Task 2：全量回歸驗證，收尾文件更新

**Files:**
- Modify: `docs/epics/epic-24-pdf-engine-rebuild/issues.md`（Issue 9 `Status` 行）
- Modify: `docs/epics.md`（epic-24 該列備註）

**Interfaces:**
- Consumes：Task 1 的程式碼變更（無新介面）。
- Produces：無。

- [x] **Step 1：`flutter analyze` 確認全專案乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 2：執行完整測試套件確認全域無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（含 Task 1 新增的 2 項測試，以及既有全部測試）。

- [x] **Step 3：更新 `issues.md` Issue 9 狀態**

修改 `docs/epics/epic-24-pdf-engine-rebuild/issues.md`，把 Issue 9 的 `Status` 行：

```markdown
**Status:** ready-for-agent
```

改為：

```markdown
**Status:** ✅ 已修復（widget test 驗證，真機驗證待補）。`PdfReaderView` 建構 `PdfViewerParams` 時依 `_selectionDrag == null` 動態傳入 `panEnabled`/`scaleEnabled`，框選拖曳進行中（`onLongPressStart` 起、`onLongPressEnd`／`onLongPressCancel`／第二指觸控取消止）暫時關閉底層 `PdfViewer` 平移/縮放，結束後立即恢復。新增 2 項 widget test（`pdf_reader_view_selection_test.dart`）驗證旗標依框選狀態正確切換（含放開手指恢復、第二指觸控取消恢復兩條路徑），既有選取／PDF 相關測試套件零回歸，`flutter analyze` 乾淨。**已知殘留限制（誠實記錄，非聲稱 100% 解決）**：根因（`Listener` 不參與手勢競技場）已用套件原始碼查證、信心高，但本次修復僅在 widget test 層級驗證旗標切換邏輯本身，尚未在真機實際重現過「頁面亂跳」症狀、也尚未真機驗證修復後不再出現亂跳、且一般雙指縮放／單指平移手感不受影響；「越靠近畫面右側越嚴重」這個真機回報細節（root cause 段落原文）也尚未有進一步驗證，若真機驗證後發現仍有殘留亂跳或手感異常，需另立 Issue 追蹤。
```

- [x] **Step 4：更新 `docs/epics.md` epic-24 該列備註**

修改 `docs/epics.md` 的 `epic-24-pdf-engine-rebuild` 該列（搜尋 `epic-24-pdf-engine-rebuild`），在既有備註文字最後補上一句：

```markdown
**Issue 9（PDF 劃線拖曳選取時與 PdfViewer 內建 pan/zoom 手勢衝突、頁面隨手指移動亂跳）已修復（widget test 驗證，真機驗證待補）**：`PdfViewerParams` 依框選拖曳狀態動態關閉/恢復 `panEnabled`/`scaleEnabled`，2 項新增 widget test 驗證旗標切換邏輯，既有測試零回歸；根因（`pdfrx` `PdfViewer` 內部 `Listener` 不參與手勢競技場、與框選 `GestureDetector` 同時收到原始 pointer 事件）已用套件原始碼查證，但修復後是否真的解決真機回報症狀、一般縮放/平移手感是否受影響，仍待真機驗證。
```

- [x] **Step 5：Commit**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/issues.md docs/epics.md
git commit -m "docs(epic-24): Issue 9 更新進度——框選拖曳與 PdfViewer 手勢衝突已修復（真機驗證待補）"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 9 的「建議修復方向」（依 `_selectionDrag != null` 動態傳入 `panEnabled: false, scaleEnabled: false`，結束/取消後恢復）由 Task 1 完整覆蓋；「需真機驗證修復後長按拖曳不再觸發底層平移，且不影響一般雙指縮放/單指平移的既有手感」這句話明確指出的真機驗證缺口，由 Task 2 Step 3/4 誠實記錄為已知殘留限制，不假裝已完成。
- **No Placeholders 掃描**：兩個 Task 的程式碼、測試程式碼、預期輸出皆為實際可執行內容；Step 2（執行測試確認失敗）明確說明失敗原因（`pdfrx` 預設值恆 `true`），不是空泛的「應該會失敗」。
- **型別/介面一致性**：本計畫沒有新增任何函式或型別，只變更 `PdfViewerParams` 既有兩個 `bool` 欄位的傳入運算式，兩個 Task 之間沒有介面銜接的疑慮。
- **既有測試不回歸的具體論證**：`_selectionDrag == null` 是預設狀態（未框選時），本計畫變更前後此狀態下 `panEnabled`/`scaleEnabled` 皆為 `true`（`pdfrx` 原生預設值與本次顯式傳入值相同），理論上對所有不涉及框選拖曳的既有測試零影響；Task 1 Step 5-6、Task 2 Step 2 皆安排實際執行既有測試套件作為實測佐證，不僅憑推論。
- **範圍誠實聲明**：本計畫刻意不處理「越靠近畫面右側越嚴重」這個真機回報細節背後可能的 `InteractiveViewer` 邊界回彈成因（`issues.md` 原文已註記「此點尚未實機驗證」）——核心修復（關閉底層平移/縮放）從機制上已能防止 `PdfViewer` 在框選期間對任何方向的位移，若真機驗證後仍有方向性殘留問題，才需要另外深入這個細節，不在本計畫範圍內搶先臆測。
