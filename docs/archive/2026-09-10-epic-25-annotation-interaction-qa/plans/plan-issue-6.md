# Epic 25 Issue 6 — PDF 原地長按既有劃線不會跳出編輯工具列 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在 PDF 既有劃線/備註正上方原地長按（不明顯拖曳）時，能正確跳出 `AnnotationToolbar` 供編輯/刪除，而不是被「退化選取」防呆整個吞掉、完全沒有反應。

**Architecture:** `PdfReaderView._finishSelectionDrag()`（`app/lib/reader/pdf_reader_view.dart`）目前判定「拖曳位移小於 1%」（退化選取）時直接 `return`，`widget.onSelectionRectComputed` 完全不會被呼叫——`PdfReaderView` 因此不需要認識 `Highlight`/`Note` 這兩個型別。本計畫**不改變這個架構分工**：改成退化選取也送出回呼，矩形用長按落點本身（`app/lib/reader/pdf_selection_geometry.dart` 新增 `pointPercentRect()`，換算出一個零面積的點）。真正決定「這次退化選取要不要顯示工具列」的判斷，交給 `ReaderScreen._handlePdfSelectionRectComputed()`（`app/lib/screens/reader_screen.dart`）——收到退化選取（`rect.left == rect.right`）時，先跑既有的 `resolvePdfExistingAnnotation()` 純函式；命中既有劃線/備註才顯示工具列，沒命中維持原本「什麼都不做」的行為。

**Tech Stack:** Flutter/Dart，無新增第三方套件，全程純 Dart 邏輯（不涉及原生橋接／WebView／觸控硬體特性）。

**Spec:** `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 6，含 2026-09-01 `/grill-with-docs` 敲定的 Solution 段落）。

## Global Constraints

- 退化選取送出的矩形一律用**長按起點**（`drag.start`，即 `_PdfSelectionDragState.start`）換算，**不可**用拖曳終點（`drag.current`）——即使有些微移動（小於 `minFraction` 門檻），落點也必須固定在起點，不隨飄移改變，比照 Issue 5 已確立的「選取起點固定用最早那次 down」慣例。
- `pointPercentRect()` 換算出的 `left`/`right`（以及 `top`/`bottom`）必須是**同一次計算指派給兩個欄位**的完全相同值（非各自獨立算出後湊巧相等），確保 `rect.left == rect.right` 這個判斷式在 `ReaderScreen` 端是可靠的精確浮點數相等比較，不是巧合。
- `PdfReaderView` 本身**不得**新增任何對 `Highlight`/`Note`/`resolvePdfExistingAnnotation` 的依賴——是否命中既有標記的判斷完全留在 `ReaderScreen`，維持既有架構分工（見 `annotation_resolution.dart` doc comment 對 PDF/EPUB 命中判斷分工的既有說明）。
- 不修改 `percentRectFromDrag()`（`pdf_selection_geometry.dart`）本身的 `minFraction` 判定邏輯或預設值——本計畫刻意保留這個既有防呆常數，只是不再讓它單方面吞掉整個回呼。
- 不修改 `_selectionDragGenerationId`／`_extractTextInRect()`／`cropRelativeToOriginalPercent()` 既有邏輯本身，這些對零面積矩形皆已驗證可正常運作（規劃階段查證：`percentRectToPdfRect()` 與 `PdfRect.overlaps()` 皆為純乘法/嚴格不等式比較，無除以零風險；`_extractTextInRect()` 對零面積矩形會回傳空字串，屬既有「空選取範圍」既有行為，不特別處理）。
- 不需要真機驗證這一輪——判定邏輯、命中比對、工具列顯示與否全部是純 Dart 邏輯，跟裝置觸控硬體特性無關（與 Issue 5 的硬體彈跳時序問題性質不同），只用自動化 widget test 驗收。
- 每個 Task 完成後只需執行該 Task 實際觸及的測試檔；全套 `flutter test` 留到本計畫最後一個 Task 執行一次。提交前 `flutter analyze` 須保持乾淨（"No issues found!"）。

---

### Task 1：`pointPercentRect()` 新增 ＋ `_finishSelectionDrag()` 退化選取改為送出落點

**Files:**
- Modify: `app/lib/reader/pdf_selection_geometry.dart`（新增 `pointPercentRect()`）
- Modify: `app/test/reader/pdf_selection_geometry_test.dart`（新增 `pointPercentRect` 測試群組）
- Modify: `app/lib/reader/pdf_reader_view.dart:1194-1199`（`_finishSelectionDrag()`）
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart:242-270`（更新既有「退化選取」測試 ＋ 新增一則「有些微移動但仍退化」測試）

**Interfaces:**
- Consumes：既有 `percentRectFromDrag()`／`PercentRect`（`percent_rect.dart`）。
- Produces：`PercentRect pointPercentRect({required Offset point, required Size areaSize})`——純函式，`left`/`top`/`right`/`bottom` 皆由同一次 `clamp01()` 計算指派（`left==right`、`top==bottom`），供 Task 2 的 `ReaderScreen` 判斷「這是不是退化選取換算出來的點矩形」使用。`_finishSelectionDrag()` 對外行為改變：退化選取時不再直接 `return`，改為呼叫 `widget.onSelectionRectComputed`。

- [ ] **Step 1：寫失敗測試——`pointPercentRect()` 純函式行為**

修改 `app/test/reader/pdf_selection_geometry_test.dart`，在 `group('percentRectFromDrag', ...)` 區塊之後（`cropRelativeToOriginalPercent` 之前）新增：

```dart
  group('pointPercentRect', () {
    test('換算出的矩形為零面積的點，left==right、top==bottom', () {
      final rect = pointPercentRect(
        point: const Offset(30, 60),
        areaSize: const Size(100, 200),
      );
      expect(rect.left, 0.3);
      expect(rect.right, 0.3);
      expect(rect.top, 0.3);
      expect(rect.bottom, 0.3);
    });

    test('落點超出區域邊界時夾限到 [0,1]', () {
      final rect = pointPercentRect(
        point: const Offset(-20, 300),
        areaSize: const Size(100, 200),
      );
      expect(rect.left, 0);
      expect(rect.right, 0);
      expect(rect.top, 1);
      expect(rect.bottom, 1);
    });

    test('left/right、top/bottom 是同一次計算指派的完全相同值（浮點數精確相等）', () {
      // 用一個非整除的座標，確認不是「湊巧算出來相等」而是同一個值。
      final rect = pointPercentRect(
        point: const Offset(33.333, 66.667),
        areaSize: const Size(100, 200),
      );
      expect(rect.left, rect.right);
      expect(rect.top, rect.bottom);
      expect(identical(rect.left, rect.right) || rect.left == rect.right, isTrue);
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_selection_geometry_test.dart`
Expected: 新增的 3 項測試 FAIL（`pointPercentRect` 尚未定義，編譯錯誤），既有測試不受影響（仍會一起報 FAIL，因為整個檔案編譯失敗）。

- [ ] **Step 3：實作 `pointPercentRect()`**

修改 `app/lib/reader/pdf_selection_geometry.dart`，在 `percentRectFromDrag()` 之後、`cropRelativeToOriginalPercent()` 之前新增：

```dart
/// 把觸控落點 [point]（相對 [areaSize] 這塊區域左上角的局部座標，單位與
/// [areaSize] 相同）換算為零面積（[left]==[right]、[top]==[bottom]）的
/// [PercentRect]，供「長按沒有明顯拖曳位移」（退化選取，見
/// [percentRectFromDrag] 的 [minFraction] 判定）時，仍要送出一個代表
/// 「使用者按在哪裡」的矩形使用（epic-25-annotation-interaction-qa
/// Issue 6）。[left]/[right] 與 [top]/[bottom] 皆指派同一個算好的值，
/// 保證是精確相等（非浮點數運算巧合），呼叫端可用 `rect.left == rect.right`
/// 可靠判斷「這是不是一個退化選取換算出來的點矩形」，不需要額外的旗標欄位。
PercentRect pointPercentRect({
  required Offset point,
  required Size areaSize,
}) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  final x = clamp01(point.dx / areaSize.width);
  final y = clamp01(point.dy / areaSize.height);
  return PercentRect(left: x, top: y, right: x, bottom: y);
}
```

- [ ] **Step 4：執行測試確認 `pointPercentRect` 測試通過**

Run: `cd app && flutter test test/reader/pdf_selection_geometry_test.dart`
Expected: 全數通過（含既有 `percentRectFromDrag`／`cropRelativeToOriginalPercent`／`originalToCropRelativePercent` 測試零回歸）。

- [ ] **Step 5：寫失敗測試——`_finishSelectionDrag()` 退化選取改為送出落點**

修改 `app/test/reader/pdf_reader_view_selection_test.dart`，把現有第 242-270 行的測試：

```dart
  testWidgets('長按但幾乎沒有拖曳位移（退化選取）時，不觸發 onSelectionRectComputed',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final pos = topLeft + const Offset(100, 150);

    final gesture = await tester.startGesture(pos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(computed, isNull, reason: '沒有明顯拖曳位移的長按不應建立選取');
  });
```

改為（**行為改變**：退化選取現在會觸發回呼，矩形是落點本身的零面積點；`ReaderScreen` 是否顯示工具列的判斷屬於 Task 2 範圍，本測試只驗證 `PdfReaderView` 這一層的輸出）：

```dart
  testWidgets(
      '長按但幾乎沒有拖曳位移（退化選取）時，仍觸發 onSelectionRectComputed，'
      '矩形為長按落點本身的零面積點（epic-25 Issue 6，是否顯示工具列的判斷'
      '交給 ReaderScreen，見 reader_screen_test.dart）', (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final pos = topLeft + const Offset(100, 150);

    final gesture = await tester.startGesture(pos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(computed, isNotNull,
        reason: '退化選取（長按無明顯拖曳）不應再被整個吞掉，須送出落點本身');
    expect(computed!.rect.left, computed!.rect.right,
        reason: '退化選取換算出的矩形須是零面積的點（left==right）');
    expect(computed!.rect.top, computed!.rect.bottom,
        reason: '退化選取換算出的矩形須是零面積的點（top==bottom）');
  });

  testWidgets(
      '長按有些微拖曳但仍小於 minFraction 門檻時，一樣視為退化選取，'
      '送出的落點固定用長按起點、不隨拖曳終點飄移', (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final areaSize = tester.getSize(find.byType(PdfReaderView));
    final start = topLeft + const Offset(100, 150);
    // 位移只有頁面寬度的 0.3%，遠小於 minFraction（1%），仍應視為退化選取。
    final end = start + Offset(areaSize.width * 0.003, 0);

    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(computed, isNotNull);
    expect(computed!.rect.left, computed!.rect.right,
        reason: '仍在 minFraction 門檻內的微小移動，一樣視為退化選取的點');
    final expectedLeftFraction = 100 / areaSize.width;
    expect(computed!.rect.left, closeTo(expectedLeftFraction, 1e-9),
        reason: '落點須固定用長按起點（100px 處），不可隨拖曳終點飄移');
  });
```

- [ ] **Step 6：執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 新修改/新增的 2 項測試 FAIL（`computed` 仍是 `null`，因為 `_finishSelectionDrag()` 尚未修改）；其餘既有測試繼續通過。

- [ ] **Step 7：修改 `_finishSelectionDrag()`**

修改 `app/lib/reader/pdf_reader_view.dart:1190-1199`，原本：

```dart
  Future<void> _finishSelectionDrag() async {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final pageRelativeRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (pageRelativeRect == null) return; // 退化選取，等同取消。
```

改為：

```dart
  Future<void> _finishSelectionDrag() async {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    // epic-25-annotation-interaction-qa Issue 6：退化選取（長按沒有明顯
    // 拖曳位移）不再整個吞掉——改用長按落點本身（drag.start，固定不隨拖曳
    // 終點飄移）換算出一個零面積的點矩形送出，讓 ReaderScreen 有機會判斷
    // 這次操作是否命中既有劃線/備註（resolvePdfExistingAnnotation()）。
    // 是否顯示工具列的決定權完全交給 ReaderScreen，這裡不判斷、也不需要
    // 認識 Highlight/Note（見 plan-issue-6.md Global Constraints）。
    final pageRelativeRect = percentRectFromDrag(
          start: drag.start,
          end: drag.current,
          areaSize: drag.areaSize,
        ) ??
        pointPercentRect(point: drag.start, areaSize: drag.areaSize);
```

`pageRelativeRect` 型別從可空的 `PercentRect?` 變成不可空的 `PercentRect`，下面緊接著的 `cropRelativeToOriginalPercent(rect: pageRelativeRect, ...)` 呼叫不需要修改（`cropRelativeToOriginalPercent` 的 `rect` 參數本來就要求非空）。`pointPercentRect` 已由 Step 3 定義在 `pdf_selection_geometry.dart`，`pdf_reader_view.dart` 已有 `import 'pdf_selection_geometry.dart';`（第 21 行，未加 `show`），不需要新增 import。

- [ ] **Step 8：執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數通過（含 Step 5 新增/修改的 2 項測試，以及既有「長按拖曳後放開，觸發 onSelectionRectComputed」等其餘測試零回歸）。

- [ ] **Step 9：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10：Commit**

```bash
git add app/lib/reader/pdf_selection_geometry.dart app/test/reader/pdf_selection_geometry_test.dart app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "fix(epic-25): Issue 6 退化選取改送出長按落點，新增 pointPercentRect()"
```

---

### Task 2：`ReaderScreen` 依命中既有標記判斷是否顯示工具列

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1616-1622`（`_handlePdfSelectionRectComputed()`）
- Test: `app/test/screens/reader_screen_test.dart`（新增 2 則）

**Interfaces:**
- Consumes：Task 1 產出的 `PdfSelectionInfo`（退化選取時 `rect.left == rect.right`）；既有 `resolvePdfExistingAnnotation()`（`annotation_resolution.dart`，簽章不變：`AnnotationListItem? resolvePdfExistingAnnotation({required PdfSelectionInfo selection, required List<Highlight> highlights, required List<Note> notes})`）。
- Produces：無新增函式，`_handlePdfSelectionRectComputed()` 對外行為改變——退化選取且未命中既有標記時，不再設定 `_currentPdfSelection`（`AnnotationToolbar` 不會顯示）；退化選取且命中，或非退化選取（不論命中與否），行為與現狀一致。

- [ ] **Step 1：寫失敗測試——退化選取命中既有劃線時顯示工具列**

**注意插入位置**（規劃階段審查發現，`reviews/review-plan-issue-6.md` Important #1）：第 7343 行是 `);`（前一則 testWidgets 的結尾），但緊接著第 7344 行是 `});`——這是外層 `group('版面設定預設集（epic-28-reader-settings-enhancements Issue 3）', ...)`（開在第 6839 行）的收尾括號，第 7346 行才是 `group('TTS 語音朗讀...')`。若照「插在 7343 之後、`TTS` group 之前」字面操作，新測試會插到 7344 這個收尾括號**之後**，變成脫離所有 group、直接掛在 `main()` 底下的頂層 testWidgets。且該外層 group 名稱本來就與 PDF 標註工具列無關（既有測試已經這樣安置，非本計畫引入的問題，不需要一併修正）。

正確做法：在 `app/test/screens/reader_screen_test.dart` 第 7344 行（`});`，即 `版面設定預設集` group 的收尾括號）之後、第 7346 行 `group('TTS 語音朗讀...')` 之前，新增一個語意正確的獨立 group，把兩則新測試包在裡面：

```dart
  group('PDF 原地長按既有標記（退化選取，epic-25-annotation-interaction-qa Issue 6）', () {
    testWidgets(
      'PDF：原地長按既有劃線正上方（退化選取，無明顯拖曳位移），'
      '仍顯示工具列且帶刪除鈕（epic-25 Issue 6）',
      (tester) async {
        final highlightsRepo = FakeHighlightsRepository();
        final notesRepo = FakeNotesRepository();
        await highlightsRepo.insert(
          const Highlight(
            id: 'h_issue6_hit',
            bookId: 'b_pdf_issue6_hit',
            style: HighlightStyle.highlighterYellow,
            pdfPageIndex: 0,
            // 覆蓋幾乎整頁，確保接下來在畫面中央附近原地長按時一定落在
            // 這筆劃線範圍內，不需要假設 PdfReaderView 內部頁面佈局與
            // widget 尺寸的精確換算關係。
            pdfRect: PercentRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              filePath: 'test/fixtures/sample_multi_page.pdf',
              bookId: 'b_pdf_issue6_hit',
              prefsManager: prefsManager,
              highlightsRepository: highlightsRepo,
              notesRepository: notesRepo,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
        await pumpUntilPdfReady(tester);

        final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
        final pos = topLeft + const Offset(100, 150);

        final gesture = await tester.startGesture(pos);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(AnnotationToolbar), findsOneWidget,
            reason: '原地長按命中既有劃線的退化選取，應顯示工具列（Issue 6）');
        expect(find.byKey(const Key('annotation_toolbar_delete')), findsOneWidget,
            reason: '命中既有劃線，工具列應帶刪除鈕');
      },
    );

    testWidgets(
      'PDF：原地長按未命中任何既有標記處（退化選取，無明顯拖曳位移），'
      '不顯示工具列，維持原本行為（epic-25 Issue 6）',
      (tester) async {
        final highlightsRepo = FakeHighlightsRepository();
        final notesRepo = FakeNotesRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              filePath: 'test/fixtures/sample_multi_page.pdf',
              bookId: 'b_pdf_issue6_miss',
              prefsManager: prefsManager,
              highlightsRepository: highlightsRepo,
              notesRepository: notesRepo,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
        await pumpUntilPdfReady(tester);

        final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
        final pos = topLeft + const Offset(100, 150);

        final gesture = await tester.startGesture(pos);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(AnnotationToolbar), findsNothing,
            reason: '沒有命中任何既有標記的退化選取，須維持原本「什麼都不做」'
                '的行為，不能彈出建立工具列');
      },
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

`_handlePdfSelectionRectComputed()` 目前尚未修改，任何送進來的 `PdfSelectionInfo`（Task 1 已讓退化選取也會送出）都會無條件觸發 `setState(() => _currentPdfSelection = info)`，工具列一律顯示，不分是否命中既有標記。因此：

Run: `cd app && flutter test test/screens/reader_screen_test.dart -n "PDF：原地長按既有劃線正上方"`
Expected: PASS（命中情境本來就該顯示工具列，這則測試在 Step 3 修改前就已經成立，不算本 Step 的失敗測試）。

Run: `cd app && flutter test test/screens/reader_screen_test.dart -n "PDF：原地長按未命中"`
Expected: FAIL——`expect(find.byType(AnnotationToolbar), findsNothing)` 不成立，因為舊邏輯無條件顯示工具列，實際會 findsOneWidget。這是本 Step 真正要確認的失敗測試。

- [ ] **Step 3：修改 `_handlePdfSelectionRectComputed()`**

修改 `app/lib/screens/reader_screen.dart:1616-1622`，原本：

```dart
  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = info;
      _pendingPdfHighlightIdForSelection = null;
    });
  }
```

改為：

```dart
  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    // epic-25-annotation-interaction-qa Issue 6：PdfReaderView 現在連退化
    // 選取（長按沒有明顯拖曳位移）都會送出一個落點本身的零面積矩形（見
    // pdf_reader_view.dart 的 _finishSelectionDrag()／pointPercentRect()），
    // 不再由它自己判斷「這是不是有意義的操作」——這裡才是真正決定要不要
    // 顯示工具列的地方。退化選取（rect.left == rect.right，見
    // pointPercentRect() doc comment 保證的精確浮點數相等）只有在命中既有
    // 劃線/備註時才顯示編輯工具列；沒命中維持原本「什麼都不做」的行為，
    // 避免任何一次精準點擊（例如翻頁時手指多停留了一下）都意外彈出建立
    // 工具列。非退化選取（有明顯拖曳）的既有行為完全不變。
    final isDegenerate = info.rect.left == info.rect.right;
    if (isDegenerate &&
        resolvePdfExistingAnnotation(
              selection: info,
              highlights: _highlights,
              notes: _notes,
            ) ==
            null) {
      return;
    }
    setState(() {
      _currentPdfSelection = info;
      _pendingPdfHighlightIdForSelection = null;
    });
  }
```

`resolvePdfExistingAnnotation` 已在檔案內既有 import（`annotation_resolution.dart`，第 2094-2100 行既有呼叫已使用），不需要新增 import。

- [ ] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過，含 Step 1 新增的 2 項測試，以及既有「PDF：框選矩形命中既有畫線時」／「PDF：框選矩形未命中既有標記時」等既有測試零回歸（皆為非退化選取的既有情境，不受本次修改影響）。

- [ ] **Step 5：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-25): Issue 6 ReaderScreen 依命中既有標記判斷退化選取是否顯示工具列"
```

---

### Task 3：全套測試最終確認、更新 `issues.md`

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 6 區塊）

**Interfaces:**
- Consumes：Task 1-2 的實作與測試結果。
- Produces：無程式介面——文件更新。

- [ ] **Step 1：全套 `flutter test`／`flutter analyze` 最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過，零回歸。

- [ ] **Step 2：更新 `issues.md` Issue 6 狀態**

修改 `docs/epics/epic-25-annotation-interaction-qa/issues.md` 的「## Issue 6」區塊，將 `**Status:**` 那一行改為：

```markdown
**Status:** ✅ 已實作並通過自動化測試（比照 `plan-issue-6.md`）。`PdfReaderView._finishSelectionDrag()` 退化選取（長按無明顯拖曳位移）不再整個吞掉，改用長按落點本身（`pointPercentRect()`，零面積的點）送出；`ReaderScreen._handlePdfSelectionRectComputed()` 收到退化選取時，先跑既有 `resolvePdfExistingAnnotation()`，命中既有劃線/備註才顯示工具列，沒命中維持原本「什麼都不做」的行為。純 Dart 邏輯修法，不需要真機驗證（見 Solution 段落）。
```

- [ ] **Step 3：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 6 更新為已實作狀態"
```

---

## Self-Review

- **Spec 覆蓋度**：Solution 段落逐項核對——「`_finishSelectionDrag()` 不再整個吞掉，送出落點本身」→ Task 1；「`PdfReaderView` 不需要認識 `Highlight`/`Note`，判斷留在 `ReaderScreen`」→ Task 1（`pdf_reader_view.dart` 不新增任何標記型別依賴）＋ Task 2（判斷邏輯本體）；「工具列定位用長按點本身，不改寫成劃線矩形」→ 未修改 `_pdfAnnotationToolbarTop()`／`left` clamp 兩處既有定位程式碼，本計畫沒有 Task 觸碰這兩處，維持現狀即為此決策的直接結果；「零面積矩形的重疊判定／`_extractTextInRect()` 已查證可正常運作」→ 已記錄於 Global Constraints，本計畫不需要為此新增任何防禦性程式碼；「不需要真機驗證」→ Global Constraints 明確聲明，Task 3 驗收標準僅要求自動化測試。
- **單元測試要求逐項核對**（issues.md 列出 5 項）：「`onSelectionRectComputed` 仍會觸發，回傳零面積矩形」→ Task 1 Step 5 第一則測試；「有拖曳但小於 `minFraction` 與完全無拖曳兩種退化情境皆一致觸發」→ Task 1 Step 5 兩則測試分別涵蓋（完全無拖曳／有些微移動但仍退化）；「退化選取命中既有標記時工具列顯示且帶刪除鈕」→ Task 2 Step 1 第一則測試；「退化選取未命中時工具列不顯示」→ Task 2 Step 1 第二則測試；「既有非退化情境零回歸」→ Task 1／Task 2 皆執行既有測試套件驗證。
- **Placeholder 掃描**：三個 Task 的程式碼與測試程式碼皆為完整可執行內容，無 TBD／待補；Task 2 Step 1 刻意用「覆蓋幾乎整頁」的劃線矩形＋既有測試已驗證過的固定座標（`topLeft + Offset(100, 150)`，與 Task 1 的退化選取測試共用同一組座標），避免對 `PdfReaderView` 內部頁面佈局與 widget 尺寸換算關係做未經查證的假設。
- **型別/介面一致性**：`pointPercentRect()` 簽章在 Task 1 定義（Step 3）與呼叫端（Step 7）完全一致；`_finishSelectionDrag()` 的 `pageRelativeRect` 型別從 `PercentRect?` 改為 `PercentRect`（不可空），下游 `cropRelativeToOriginalPercent(rect: ...)` 呼叫本來就要求非空參數，不需要額外改動；`_handlePdfSelectionRectComputed()` 沿用 `resolvePdfExistingAnnotation()` 既有簽章（`annotation_resolution.dart`），未新增/修改該函式本體。
- **既有測試不回歸的具體論證**：Task 1 只修改 `_finishSelectionDrag()` 的「退化選取」分支（原本 `return` 的那一行），非退化選取（有明顯拖曳位移）的既有計算路徑完全不變；Task 2 只在 `_handlePdfSelectionRectComputed()` 開頭新增一個提前 `return` 的判斷式，且只在 `isDegenerate == true` 時才會執行 `resolvePdfExistingAnnotation()` 這個額外檢查，非退化選取（`isDegenerate == false`）完全略過這段新邏輯、直接執行原本的 `setState`，與現狀行為一致。
- **架構分工誠實聲明**：`PdfReaderView` 全程不 import `Highlight`/`Note`/`annotation_resolution.dart`（Task 1 兩個檔案的修改皆已核對過，只用到既有的 `PercentRect`／`Offset`／`Size`），命中判斷完全留在 `ReaderScreen`，符合 Global Constraints 與 `/grill-with-docs` Q1 敲定的架構決策。
- **依 `reviews/review-plan-issue-6.md` 審查意見修訂**：Important #1（Task 2 新增測試的插入位置字面上會落在既有 `group('版面設定預設集...')` 收尾括號之後，脫離所有 group 結構）——已查證屬實（`reader_screen_test.dart` 第 7344 行 `});` 確實是該 group 的收尾），改為插入一個語意正確的獨立新 group（`'PDF 原地長按既有標記（退化選取，epic-25-annotation-interaction-qa Issue 6）'`），包住兩則新測試，插入點改為第 7344 行之後、`TTS` group（第 7346 行）之前。3 項 Minor（`widgetRect` 與 `pointPercentRect` 語意重複、測試內重複解包 `!`、Step 2 第一則測試並非嚴格 TDD 失敗測試）審查者本身已判定不影響正確性、不建議修改，維持原計畫不動。
