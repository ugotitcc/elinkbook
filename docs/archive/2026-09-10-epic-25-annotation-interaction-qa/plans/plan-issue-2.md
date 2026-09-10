# Epic 25 Issue 2 — 畫線工具列在螢幕右側被裁切看不全 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復 `AnnotationToolbar`（劃線/備註浮動工具列）在選取範圍靠近螢幕右緣時被裁切、看不到右半部按鈕的問題（使用者截圖：`tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg`），EPUB／PDF 兩條路徑皆須修正。

**Architecture:** `reader_screen.dart` 定位 `AnnotationToolbar` 時，垂直方向（`top`）已用 `_annotationToolbarTop()`／`_pdfAnnotationToolbarTop()` 正確扣除工具列自身高度再 clamp，但水平方向（`left`）只 clamp 下界（`>= 0`），完全沒有扣除工具列自身寬度、也沒有 clamp 上界。修法是新增 `_annotationToolbarWidth` 常數（比照既有 `_annotationToolbarHeight` 的量測方式取得實際渲染寬度），讓 `left` 的 clamp 上界比照 `top` 已驗證穩定的寫法改為 `size.width - _annotationToolbarWidth`。EPUB／PDF 兩處呼叫端（`reader_screen.dart:1972`／`1983`）同構，需同步修正。

**Tech Stack:** Flutter widget（純 Dart，不涉及原生程式碼／vendored JS）。

## Global Constraints

- 本計畫只修改 `left` 定位的 clamp 上界，不觸碰已驗證穩定的 `top`／`_annotationToolbarTop()`／`_pdfAnnotationToolbarTop()` 邏輯本體（Surgical Changes 原則，issues.md 已明確要求「比照 `top` 的寫法」，不是重新設計）。
- `_annotationToolbarWidth` 的數值**必須是實際 widget test 量測值，不可憑空假設**（issues.md Issue 2 明確要求）——本計畫規劃階段已用一次性量測（`AnnotationToolbar` 在 `MaterialApp`/`Scaffold` 內、`Align(topLeft)`，`tester.getSize()`）確認為 **256.0**（`tester.pumpAndSettle()` 後量測，Material 3 `IconButton` 預設寬度 5 顆 × 48dp + `Row` 外層 `Padding` 左右各 8dp = 256），與既有 `_annotationToolbarHeight = 56.0` 一致由同一量測手法得出，可直接作為常數值使用，Task 1 不需要重新量測。
- 不新增 `_annotationToolbarWidth` 之外的其他常數或抽象——不需要動態量測（`GlobalKey`+`RenderBox` 之類的執行期量測機制），`AnnotationToolbar` 目前是固定 5 顆按鈕的靜態版面，寫死常數即可，符合 YAGNI（若未來按鈕數量變動需要動態寬度，屬於另一個 Issue 的範圍）。
- 螢幕寬度小於 `_annotationToolbarWidth`（256px）的極端情況本計畫不處理——真實裝置螢幕寬度恆大於 256px，比照既有 `_annotationToolbarHeight`／`top` clamp 對於螢幕高度小於 56px 的情況同樣未防禦的既有先例（CLAUDE.md「不要為不可能發生的情境寫防禦」），非本次修法引入的新缺口。

---

### Task 1：新增 `_annotationToolbarWidth` 常數，修正 EPUB／PDF 兩處 `left` clamp 上界

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1647-1648`（新增常數）、`:1972`（EPUB `left` clamp）、`:1983`（PDF `left` clamp）
- Test: `app/test/screens/reader_screen_test.dart`（新增兩則 widget test，插入點見下方 Step 1／Step 3）

**Interfaces:**
- Consumes：既有 `EpubSelectionInfo.rect`／`PdfSelectionInfo.widgetRect`（皆為 `PercentRect`，`app/lib/reader/percent_rect.dart`）、既有 `_annotationToolbarHeight`／`_annotationToolbarGap` 常數宣告模式（`reader_screen.dart:1647-1648`）。
- Produces：新常數 `_annotationToolbarWidth`（`double`，值 `256.0`），僅本檔案內部使用，不對外暴露。

- [x] **Step 1：在 `reader_screen_test.dart` 新增 EPUB 端的失敗測試**

在 `app/test/screens/reader_screen_test.dart` 第 3398 行（既有測試 `'流式 EPUB：FoliateEpubReaderView 回報 onSelectionChanged 時，顯示 AnnotationToolbar'` 結束的 `},\n  );` 之後、下一個測試 `'流式 EPUB：FoliateEpubReaderView 回報 onAnnotationActivated 時，開啟對話框'`（第 3400 行）之前）插入：

```dart
  testWidgets(
    '流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度',
    (tester) async {
      // 固定視窗尺寸（400×800，比照既有 PDF 選取測試慣例），讓 clamp 後的
      // 精確像素值可預期、可斷言，而非依賴 flutter test 預設 800×600。
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800));
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_select_edge',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // 選取範圍靠近畫面右緣（left=0.95），比照使用者截圖回報的症狀
      // （tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.9}',
          progression: 0.9,
          rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
      final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
      expect(
        bottomRight.dx,
        lessThanOrEqualTo(400.0),
        reason: '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
            '否則右半部按鈕會被裁切看不到',
      );
    },
  );

```

- [x] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度"`

Expected: `流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度` FAIL，斷言訊息顯示 `Actual: <636.0>`／`Which: is not <= 400.0>`（本計畫規劃階段已用暫時性量測腳本確認修法前的實際值即為 `636.0`，Task 1 執行時應得到相同結果，證實測試確實在鎖定本 Issue 的症狀，而非測試本身寫錯）。

- [x] **Step 3：在 `reader_screen_test.dart` 新增 PDF 端的失敗測試**

在同一檔案第 5471 行（既有測試 `'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後劃線已寫入且 Toolbar 仍開啟（可續加備註）'` 結束的 `});` 之後、下一個測試 `'PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar'`（第 5473 行）之前）插入：

```dart
  testWidgets(
      'PDF：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度',
      (tester) async {
    // 固定視窗尺寸（400×800），讓 clamp 後的精確像素值可預期、可斷言。
    // 本測試直接呼叫 onSelectionRectComputed 回呼（比照 EPUB 測試對
    // onSelectionChanged 的呼叫方式），不透過真實長按拖曳手勢，因此不需要
    // 其他 PDF 測試（如 5391 行）為了等待真實 pdfrx 文件載入完成才需要的
    // 30 次輪詢等待樣板——本測試只驗證 AnnotationToolbar 收到選取矩形後
    // 的定位計算，與 pdfrx 是否已完成真實頁面渲染無關。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_select_edge',
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
    // 選取範圍靠近畫面右緣（widgetRect.left=0.95），比照使用者截圖回報的
    // 症狀（tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
        widgetRect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);
    final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
    expect(
      bottomRight.dx,
      lessThanOrEqualTo(400.0),
      reason: '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
          '否則右半部按鈕會被裁切看不到',
    );
  });

```

同一檔案頂端（第 41-47 行既有 import 區塊，`import 'package:elinkbook/reader/percent_rect.dart';` 之後）新增一行：

```dart
import 'package:elinkbook/reader/pdf_selection_info.dart';
```

（`PdfSelectionInfo` 目前未被此檔案任何既有測試直接建構，需新增此 import；`PercentRect`／`EpubSelectionInfo` 已於既有第 41-42 行匯入，不需重複新增。）

- [x] **Step 4：執行測試，確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "PDF：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度"`

Expected: FAIL，斷言訊息顯示 `Actual: <636.0>`／`Which: is not <= 400.0>`（本計畫規劃階段已用暫時性量測腳本確認：`topLeft=Offset(380.0, 96.0) bottomRight=Offset(636.0, 152.0)`，與 EPUB 端數值一致，因兩條路徑目前是同一段有缺陷的 clamp 邏輯）。

- [x] **Step 5：實作修法——新增常數並修正兩處 `left` clamp**

修改 `app/lib/screens/reader_screen.dart:1647-1648`：

```dart
  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  static const _annotationToolbarHeight = 56.0;
  static const _annotationToolbarGap = 8.0;
  // AnnotationToolbar 實際渲染寬度（5 顆 IconButton，Material 3 預設每顆
  // 48dp 寬 + Row 外層 Padding 左右各 8dp = 5*48+16 = 256；widget test
  // 量測值，見 plan-issue-2.md Global Constraints，與既有
  // _annotationToolbarHeight 同一量測手法得出）。選取範圍靠近螢幕右緣時，
  // left 的 clamp 上界須扣除這個寬度，否則工具列本體會整個超出螢幕右側
  // （issues.md Issue 2）。
  static const _annotationToolbarWidth = 256.0;
```

修改 `app/lib/screens/reader_screen.dart:1972`（EPUB 路徑）：

```dart
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                ),
              ),
```

修改 `app/lib/screens/reader_screen.dart:1983`（PDF 路徑）：

```dart
            if (pdfSelection != null)
              Positioned(
                // 同上（見 _pdfAnnotationToolbarTop 註解）：改用相對整個
                // widget 尺寸的 widgetRect，避免 letterbox 留白造成偏移。
                left: (pdfSelection.widgetRect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                ),
              ),
```

- [x] **Step 6：執行 Step 1／Step 3 新增的兩則測試，確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "AnnotationToolbar 右緣不應超出畫面寬度"`

Expected: 兩則測試皆 PASS（`--plain-name` 為子字串比對，會同時命中 EPUB／PDF 兩則）。修法後預期精確值：`left = (0.95*400).clamp(0.0, 400.0-256.0) = clamp(380.0, 0.0, 144.0) = 144.0`，`bottomRight.dx = 144.0 + 256.0 = 400.0`（恰好貼齊畫面右緣，`lessThanOrEqualTo(400.0)` 成立）。

- [x] **Step 7：執行完整回歸測試，確認既有選取相關測試未受影響**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過，特別留意既有 `'流式 EPUB：FoliateEpubReaderView 回報 onSelectionChanged 時，顯示 AnnotationToolbar'`（第 3351 行，`rect.left=0.1`）與 `'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar...'`（第 5391 行）——這兩則既有測試的選取範圍皆遠離右緣（`left=0.1` 或由真實手勢產生的中央偏左位置），未觸及新 clamp 上界（`400.0 - 256.0 = 144.0` 遠大於 `0.1*400=40.0`），理論上不受本次修法影響，執行結果須確認零回歸。

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 全數通過（本次未修改 `annotation_toolbar.dart` 本體，僅新增/修改呼叫端的定位計算，此檔案測試理論上不受影響）。

- [x] **Step 8：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 9：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-25): Issue 2——AnnotationToolbar 靠近螢幕右緣時新增寬度 clamp，避免被裁切"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 2 的「根因」「修法」「單元測試要求」「驗收標準」四項皆由 Task 1 覆蓋——常數新增＋兩處呼叫端修正對應「修法」；EPUB／PDF 兩條路徑的 widget test（含 `getBottomRight` 驗證整個工具列在畫面範圍內）對應「單元測試要求」；`flutter analyze` 乾淨對應「驗收標準」前半。「驗收標準」後半（真機或等效螢幕尺寸模擬下人工確認可見可點擊）非自動化測試可覆蓋範圍，留待人類真機驗證，不在本計畫的自動化步驟內臆測完成。
- **No Placeholders 掃描**：`_annotationToolbarWidth` 數值（`256.0`）、測試斷言的精確像素值（`636.0`／`144.0`／`400.0`）皆為規劃階段以暫時性 widget test 腳本實際量測/驗證所得（非理論推算或憑空假設），已在文件中列出量測依據；無 TBD/待補事項。
- **型別/介面一致性**：`PdfSelectionInfo` 建構子欄位（`pageIndex`／`rect`／`widgetRect`）與 `app/lib/reader/pdf_selection_info.dart:13-22` 現有定義一致；`EpubSelectionInfo`／`PercentRect`／`EpubLayoutInfo` 皆沿用既有測試檔案第 3378-3393 行已驗證可用的建構方式，未自創新介面。
- **既有測試不回歸的具體論證**：修法只是把 `left` clamp 的上界從 `size.width` 收窄為 `size.width - _annotationToolbarWidth`（`256.0`），對任何 `selection.rect.left * size.width <= size.width - 256.0` 的既有測試情境（即選取範圍不靠近右緣），clamp 前後結果完全相同，數學上不可能產生回歸；Step 7 仍安排完整回歸測試作為實測佐證，不僅依賴此推論。
- **範圍誠實聲明**：本計畫刻意不處理「螢幕寬度 < 256px」的極端情況（Global Constraints 已註明為既有 `_annotationToolbarHeight`／`top` clamp 同樣未防禦的先例，非本次修法引入的新缺口），也不新增動態量測工具列寬度的機制（YAGNI，目前工具列是固定 5 顆按鈕的靜態版面）。
