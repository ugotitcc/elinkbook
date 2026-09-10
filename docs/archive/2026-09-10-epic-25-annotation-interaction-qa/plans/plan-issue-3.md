# Epic 25 Issue 3 — 選擇畫線樣式後應可主動關閉工具列 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `AnnotationToolbar` 新增一顆明確的「✕ 關閉」按鈕，讓使用者選色/建立劃線後不必依賴點擊換頁間接觸發，就能主動關閉浮動工具列；EPUB 端額外清除 WebView 原生文字選取視覺（藍色反白＋拖曳控點），避免工具列消失後畫面殘留不一致的選取狀態。

**Architecture:** `AnnotationToolbar`（純 Dart widget，EPUB／PDF 共用）新增第 6 顆按鈕與 `onClosePressed` 必要參數；`reader_screen.dart` 兩處呼叫端接上處理常式——PDF 直接沿用既有 `_handlePdfSelectionCanceled()`（查證後確認 PDF 沒有獨立於 `_currentPdfSelection` 之外的殘留視覺層，見下方 Global Constraints），EPUB 則新增 `_handleCloseAnnotationToolbar()`，除了清空 Dart 端 `_currentSelection` 外，額外透過既有的 `window.X = function(){...}` JS 橋接慣例（`main.js`）新增 `window.clearSelection()`，呼叫 `doc.getSelection().removeAllRanges()` 清除 WebView 原生選取（該視覺層完全獨立於 Dart state，不清除的話畫面會殘留反白文字）。

**Tech Stack:** Flutter widget（純 Dart）＋ `main.js`（本專案自有的 foliate-js 整合層，**非** vendored 檔案，ADR 0011 允許修改；不觸碰 `paginator.js`/`view.js`/`epub.js` 等真正 vendored 檔案本體）。

## Global Constraints

- `AnnotationToolbar.onClosePressed` 依 `issues.md` Issue 3 明定為**必要參數**（非 optional）——所有既有建構呼叫點（`annotation_toolbar_test.dart` 6 處、`reader_screen.dart` 2 處）皆須同步更新，否則 `flutter analyze`/編譯會失敗；不可為了省事改成 optional 參數而偏離人類已確認的設計方向。
- **PDF 端不需要對應的原生選取清除機制**（本計畫規劃階段已查證 `issues.md` Issue 3 留下的「是否需要同步清除原生選取狀態」待辦問題，結論記錄於此避免下一位讀者重新查證一次）：`pdf_reader_view.dart:_finishSelectionDrag()`（`app/lib/reader/pdf_reader_view.dart:1084-1113`）在呼叫 `widget.onSelectionRectComputed?.call(...)` **之前**就已經 `setState(() => _selectionDrag = null)`，`_selectionDrag`（`_PdfSelectionDragState`）是 `PdfReaderView` 唯一會疊加繪製的選取視覺層，於是 `ReaderScreen` 拿到 `onSelectionRectComputed` 回呼的當下，`PdfReaderView` 自身已經沒有任何殘留視覺——`_currentPdfSelection` 是後續畫面上「看起來像被選取」這件事的唯一依據，清空它（既有 `_handlePdfSelectionCanceled()`）即完全足夠，不存在 EPUB 那種「WebView 原生層獨立於 Dart state 之外」的問題。
- **`evaluateJavascript` 呼叫在 `flutter_test` 環境下無法被攔截驗證**（本專案既有測試基礎設施限制，非本次修法引入，見 `reader_screen_test.dart:3291-3294` 對 `setDecorations` 的既有註解說明）——Task 2 新增的 `window.clearSelection()` JS 呼叫本身無法寫自動化斷言驗證「確實清除了選取」，只能靠 `node --check` 語法檢查＋既有測試套件不崩潰佐證呼叫路徑本身沒有寫錯，實際清除效果需要真機/人工驗證。誠實記錄這個既有缺口，不假裝有自動化覆蓋（比照 Issue 1 `_hasActiveSelection` 的既有測試覆蓋缺口說明模式）。
- 不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js` 等）——`main.js` 是本專案自有的整合層，可修改（ADR 0011）。
- 「選色後工具列保持開啟、可接續點擊備註」這條既有流程已有專屬回歸測試（`reader_screen_test.dart` 現有的 `'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後劃線已寫入且 Toolbar 仍開啟（可續加備註）'`），本計畫完全不修改 `_handleHighlightStyleSelected`／`_handlePdfHighlightStyleSelected` 這兩個既有方法本體，只新增一顆平行的按鈕與其獨立的 `onClosePressed` 回呼，故不需要新增額外的「選色後仍開啟」測試——執行既有測試套件確認其仍通過即為充分回歸保護（YAGNI，避免重複造輪子）。
- **新增第 6 顆按鈕會使 `AnnotationToolbar` 實際渲染寬度改變，連帶讓 Issue 2 的 `_annotationToolbarWidth` 常數過期**（本計畫規劃階段已用暫時性 widget test 腳本實測確認，非臆測）：Issue 2 量測的 256.0（5 顆按鈕：`5*48+16`）只在 5 顆按鈕時成立，新增關閉按鈕後實測變為 **304.0**（`6*48+16`，高度 `_annotationToolbarHeight` 不受影響，仍是 56.0）。若 Task 1 只新增按鈕、不同步更新 `reader_screen.dart:1655` 的 `_annotationToolbarWidth`，Issue 2 新增的兩則「選取範圍靠近畫面右緣」測試（`reader_screen_test.dart`）會重新變紅（實測 `Actual: <448.0>`，`Which: is not a value less than or equal to <400.0>`）——這是本計畫規劃階段實測發現、必須在 Task 1 一併修正的真實回歸，不是假設性風險。

---

### Task 1：`AnnotationToolbar` 新增關閉按鈕，`reader_screen.dart` 兩處呼叫端接上既有清空方法

**Files:**
- Modify: `app/lib/screens/annotation_toolbar.dart`（新增第 6 顆按鈕與 `onClosePressed` 參數）
- Modify: `app/test/screens/annotation_toolbar_test.dart`（既有 6 處建構呼叫補上 `onClosePressed`，新增 2 則關閉按鈕測試）
- Modify: `app/lib/screens/reader_screen.dart:1982-1985`（EPUB 呼叫端）、`:1994-1997`（PDF 呼叫端）
- Test: `app/test/screens/reader_screen_test.dart`（新增 EPUB／PDF 各一則「點擊關閉按鈕」widget test）

**Interfaces:**
- Consumes：既有 `_handleSelectionCleared()`（`reader_screen.dart:1152-1158`）、`_handlePdfSelectionCanceled()`（`reader_screen.dart:1168-1174`）。
- Produces：`AnnotationToolbar` 新增 `required VoidCallback onClosePressed` 建構參數與 `Key('annotation_toolbar_close')` 按鈕，供 Task 2 與後續呼叫端使用。

- [x] **Step 1：修改 `annotation_toolbar_test.dart`，既有建構呼叫補上 `onClosePressed`，新增關閉按鈕測試**

完整改寫 `app/test/screens/annotation_toolbar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';

void main() {
  testWidgets('顯示螢光筆三色、底線、備註、關閉共 6 個按鈕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('annotation_toolbar_highlighter_yellow')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_pink')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_blue')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_underline')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_note')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_close')), findsOneWidget);
  });

  testWidgets('點擊黃色螢光筆按鈕觸發 onStyleSelected(highlighterYellow)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
          onClosePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_yellow')));
    expect(selected, HighlightStyle.highlighterYellow);
  });

  testWidgets('點擊粉色螢光筆按鈕觸發 onStyleSelected(highlighterPink)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
          onClosePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_pink')));
    expect(selected, HighlightStyle.highlighterPink);
  });

  testWidgets('點擊藍色螢光筆按鈕觸發 onStyleSelected(highlighterBlue)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
          onClosePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_blue')));
    expect(selected, HighlightStyle.highlighterBlue);
  });

  testWidgets('點擊底線按鈕觸發 onStyleSelected(underline)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
          onClosePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_underline')));
    expect(selected, HighlightStyle.underline);
  });

  testWidgets('點擊備註按鈕觸發 onNotePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () => pressed = true,
          onClosePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
    expect(pressed, isTrue);
  });

  testWidgets('點擊關閉按鈕觸發 onClosePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () => pressed = true,
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    expect(pressed, isTrue);
  });
}
```

- [x] **Step 2：執行測試，確認因缺少 `onClosePressed` 建構參數與 `Key('annotation_toolbar_close')` widget 而失敗**

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 編譯失敗（`AnnotationToolbar` 目前建構子沒有 `onClosePressed` 具名參數，`flutter test` 會直接報 analyzer 錯誤 `The named parameter 'onClosePressed' isn't defined`），或若先只改測試檔本身，`flutter analyze` 會先於測試執行前報錯——這正是預期的紅燈狀態，證實測試確實在鎖定「`onClosePressed` 尚未存在」這個症狀。

- [x] **Step 3：修改 `annotation_toolbar.dart`，新增 `onClosePressed` 參數與第 6 顆按鈕**

修改 `app/lib/screens/annotation_toolbar.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/highlight_style.dart';

/// 選字/框選後浮現的浮動工具列（design.md「使用者流程」步驟 1-2；
/// EPUB（本 Issue）與 PDF（issues.md Issue 3）共用同一組 Widget）：
/// 螢光筆三色、底線、備註、關閉共 6 個按鈕。點擊螢光筆/底線立即觸發
/// [onStyleSelected]（呼叫端負責建立劃線，並保持選取狀態存在讓使用者
/// 能接著點備註，見 design.md 使用者流程「若同時已選色/底線，備註與
/// 劃線共存於同一筆記錄」）；點擊備註觸發 [onNotePressed]（呼叫端負責
/// 另外呼叫 `showNoteTextDialog` 開啟輸入 Dialog，本 Widget 不含 Dialog
/// 邏輯，維持單一職責）；點擊關閉觸發 [onClosePressed]（epic-25 Issue 3：
/// 讓使用者不必依賴點擊換頁間接關閉工具列，呼叫端負責清空選取狀態）。
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;
  final VoidCallback onClosePressed;

  const AnnotationToolbar({
    super.key,
    required this.onStyleSelected,
    required this.onNotePressed,
    required this.onClosePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_yellow'),
              color: highlighterYellowTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_pink'),
              color: highlighterPinkTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_blue'),
              color: highlighterBlueTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
            ),
            IconButton(
              key: const Key('annotation_toolbar_underline'),
              icon: const Icon(Icons.format_underline),
              tooltip: '底線',
              onPressed: () => onStyleSelected(HighlightStyle.underline),
            ),
            IconButton(
              key: const Key('annotation_toolbar_note'),
              icon: const Icon(Icons.edit_note),
              tooltip: '備註',
              onPressed: onNotePressed,
            ),
            IconButton(
              key: const Key('annotation_toolbar_close'),
              icon: const Icon(Icons.close),
              tooltip: '關閉',
              onPressed: onClosePressed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton({
    required Key key,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: key,
      icon: Icon(Icons.circle, color: color),
      onPressed: onTap,
    );
  }
}
```

- [x] **Step 4：執行 `annotation_toolbar_test.dart`，確認通過**

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 7 項測試全數 PASS（既有 5 項＋新增的「顯示...共 6 個按鈕」斷言更新＋「點擊關閉按鈕觸發 onClosePressed」）。

- [ ] **Step 5：更新 `_annotationToolbarWidth` 常數（新增第 6 顆按鈕使實際渲染寬度從 256 變為 304）**

修改 `app/lib/screens/reader_screen.dart:1649-1655`：

```dart
  // AnnotationToolbar 實際渲染寬度（6 顆 IconButton，Material 3 預設每顆
  // 48dp 寬 + Row 外層 Padding 左右各 8dp = 6*48+16 = 304；widget test
  // 量測值，見 plan-issue-2.md Global Constraints，與既有
  // _annotationToolbarHeight 同一量測手法得出）。選取範圍靠近螢幕右緣時，
  // left 的 clamp 上界須扣除這個寬度，否則工具列本體會整個超出螢幕右側
  // （issues.md Issue 2）。【issues.md Issue 3】新增第 6 顆關閉按鈕後，
  // 實際渲染寬度從 256（5 顆）變為 304（6 顆），此常數需同步更新，否則
  // Issue 2 的 clamp 修法會重新出現裁切（見 plan-issue-3.md Task 1）。
  static const _annotationToolbarWidth = 304.0;
```

- [x] **Step 6：`reader_screen.dart` 兩處呼叫端接上 `onClosePressed`**

修改 `app/lib/screens/reader_screen.dart:1982-1985`（EPUB 路徑）：

```dart
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                  onClosePressed: _handleSelectionCleared,
                ),
```

修改 `app/lib/screens/reader_screen.dart:1994-1997`（PDF 路徑，依 Global Constraints 已查證的結論，直接沿用既有方法即完整、不需額外處理）：

```dart
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                  onClosePressed: _handlePdfSelectionCanceled,
                ),
```

- [x] **Step 7：在 `reader_screen_test.dart` 新增 EPUB 端「點擊關閉按鈕」測試**

在 `app/test/screens/reader_screen_test.dart` 第 3467 行（既有測試 `'流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度'` 結束的 `},\n  );` 之後、下一個測試 `'流式 EPUB：FoliateEpubReaderView 回報 onAnnotationActivated 時，開啟對話框'`（第 3469 行）之前）插入：

```dart
  testWidgets(
    '流式 EPUB：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_close_toolbar',
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

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);

      await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing,
          reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失');
    },
  );

```

- [x] **Step 8：在 `reader_screen_test.dart` 新增 PDF 端「點擊關閉按鈕」測試**

在同一檔案第 5595 行（既有測試 `'PDF：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度'` 結束的 `});` 之後、下一個測試 `'PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar'`（第 5597 行）之前）插入：

```dart
  testWidgets(
      'PDF：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_close_toolbar',
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
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失');
  });

```

- [x] **Step 9：執行完整回歸測試**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過，特別留意兩點：(1) 既有 `'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後劃線已寫入且 Toolbar 仍開啟（可續加備註）'`（約第 5460 行）——本次修改沒有觸碰 `_handleHighlightStyleSelected`／`_handlePdfHighlightStyleSelected` 本體，這則測試須維持零回歸，證實「選色後保持開啟」流程不受新按鈕影響；(2) Issue 2 新增的 `'流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度'`／`'PDF：選取範圍靠近畫面右緣時，...'` 兩則測試須維持通過（`bottomRight.dx` 仍 `<= 400.0`）——這兩則測試若在 Step 5 更新常數前執行會失敗（`Actual: <448.0>`，規劃階段已實測確認），Step 5 更新為 304.0 後應恢復綠燈，此處是最終確認沒有遺漏。

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 7 項全數通過。

- [x] **Step 10：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 11：Commit**

```bash
git add app/lib/screens/annotation_toolbar.dart app/test/screens/annotation_toolbar_test.dart app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-25): Issue 3——AnnotationToolbar 新增關閉按鈕，EPUB/PDF 皆可主動關閉工具列"
```

---

### Task 2：EPUB 端補強清除 WebView 原生選取狀態（`window.clearSelection()` 橋接）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:395-396`（新增 `window.clearSelection`）
- Modify: `app/lib/reader/foliate_epub_reader_view.dart:475-476`（新增 `clearSelection` static helper）
- Modify: `app/lib/screens/reader_screen.dart:1152-1158`（新增 `_handleCloseAnnotationToolbar()`）、`:1982-1985`（EPUB 呼叫端改用新方法）

**Interfaces:**
- Consumes：Task 1 新增的 `AnnotationToolbar.onClosePressed`、既有 `_handleSelectionCleared()`、既有 `_evaluate(String source)`（`foliate_epub_reader_view.dart:552-554`）、既有 `_foliateEpubReaderViewKey`（`reader_screen.dart:310`）。
- Produces：`window.clearSelection()`（JS 全域函式）、`FoliateEpubReaderView.clearSelection(GlobalKey<State<FoliateEpubReaderView>> key)`（Dart static helper）、`_ReaderScreenState._handleCloseAnnotationToolbar()`（無回傳值，供 Task 1 的 EPUB 呼叫端使用）。

- [x] **Step 1：`main.js` 新增 `window.clearSelection`**

修改 `app/android/app/src/main/assets/foliate/main.js`，在 `window.setDecorations` 函式結尾（第 395 行 `}`）之後插入：

```javascript

/**
 * 主動清除目前的原生文字選取狀態（epic-25 Issue 3）：使用者點擊
 * AnnotationToolbar 的關閉按鈕後，Dart 端會清空 _currentSelection 讓工具列
 * 消失，但 WebView 原生選取（藍色反白＋拖曳控點）是瀏覽器自己的視覺層，
 * 不受 Dart state 影響，若不主動清除，畫面會殘留「工具列已消失、但文字
 * 仍反白」的不一致體驗。逐一走訪目前所有已載入內容（雙頁模式下可能同時
 * 有兩個 iframe），清空各自的選取——呼叫 removeAllRanges() 會自然觸發
 * selectionchange，讓既有 reportSelection()（見上方 view.addEventListener
 * ('load', ...) hook）回報 onSelectionCleared 給 Dart 端，不需要額外手動
 * 呼叫 callback，也不會與 Dart 端已經呼叫過的 _handleSelectionCleared()
 * 衝突（該方法本身是 idempotent，重複呼叫只是把已經是 null 的欄位再設一次
 * null）。
 */
window.clearSelection = function () {
  for (const { doc } of view.renderer.getContents()) {
    doc.getSelection()?.removeAllRanges()
  }
}
```

- [x] **Step 2：語法檢查**

Run: `node --check app/android/app/src/main/assets/foliate/main.js`
Expected: 無輸出、exit code 0（純語法檢查，不執行任何程式邏輯——`evaluateJavascript` 呼叫本身無法在 `flutter_test` 環境下驗證，見 Global Constraints）。

- [x] **Step 3：`foliate_epub_reader_view.dart` 新增 `clearSelection` static helper**

修改 `app/lib/reader/foliate_epub_reader_view.dart`，在 `setDecorations` static method（第 466-475 行）之後插入：

```dart

  /// 主動清除 WebView 原生文字選取狀態（epic-25 Issue 3，見 main.js
  /// window.clearSelection 註解）。
  static void clearSelection(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.clearSelection()');
    }
  }
```

- [x] **Step 4：`reader_screen.dart` 新增 `_handleCloseAnnotationToolbar()`，EPUB 呼叫端改用新方法**

修改 `app/lib/screens/reader_screen.dart`，在 `_handleSelectionCleared()`（第 1152-1158 行）之後插入：

```dart

  /// Epic 25 Issue 3：使用者主動點擊 AnnotationToolbar 關閉按鈕時呼叫——
  /// 除了清空 Dart 端選取狀態（比照 [_handleSelectionCleared]）外，額外
  /// 呼叫 JS 端 window.clearSelection() 清除 WebView 原生選取（藍色反白
  /// ＋拖曳控點），避免工具列消失後畫面仍殘留原生選取視覺（該視覺層不受
  /// Dart state 控制，見 main.js window.clearSelection 註解）。PDF 端沒有
  /// 這個問題（見 Global Constraints「PDF 端不需要對應的原生選取清除
  /// 機制」的查證結論），故 PDF 呼叫端直接沿用既有
  /// [_handlePdfSelectionCanceled]，不需要對應的 wrapper。
  void _handleCloseAnnotationToolbar() {
    _handleSelectionCleared();
    FoliateEpubReaderView.clearSelection(_foliateEpubReaderViewKey);
  }
```

把 EPUB 呼叫端（Task 1 Step 6 已改為 `onClosePressed: _handleSelectionCleared`）改為：

```dart
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                  onClosePressed: _handleCloseAnnotationToolbar,
                ),
```

- [x] **Step 5：執行既有測試套件，確認新方法不引入崩潰或回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過，包含 Task 1 新增的「流式 EPUB：點擊 AnnotationToolbar 的關閉按鈕後」測試——`_controller` 在 `flutter test` 環境下為 `null`（未真正建立 `InAppWebViewController`），`_evaluate()` 內的 `_controller?.evaluateJavascript(...)` 對 null 呼叫是安全的 no-op，不會拋出例外，測試能驗證「呼叫路徑不崩潰＋ Dart 端狀態正確清空」，但**無法**驗證 `window.clearSelection()` 實際執行效果（見 Global Constraints，此為既有測試基礎設施限制，非本次修法引入）。

- [x] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 7：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_epub_reader_view.dart app/lib/screens/reader_screen.dart
git commit -m "fix(epic-25): Issue 3——EPUB 關閉工具列時一併清除 WebView 原生選取狀態"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 3 的「修法方向」三項全數覆蓋——第 1 項（新增第 6 顆按鈕＋`onClosePressed` 必要參數）由 Task 1 完成；第 2 項（EPUB/PDF 呼叫端分別呼叫 `_handleSelectionCleared()`/`_handlePdfSelectionCanceled()`）由 Task 1 完成（PDF 直接如此、EPUB 先如此後在 Task 2 擴充）；第 3 項（查證是否需要同步清除原生選取狀態）已在 Global Constraints 給出明確查證結論並由 Task 2 落實 EPUB 端的做法。「單元測試要求」三項（關閉按鈕存在可點擊、點擊後狀態清空與工具列消失、既有選色流程回歸）分別由 Task 1 Step 1／Step 7-8／Step 9 覆蓋。「驗收標準」的自動化部分（測試通過、`flutter analyze` 乾淨）由 Task 1 Step 9-10、Task 2 Step 5-6 覆蓋；真機驗證部分留待人類執行，本計畫不假裝可用自動化涵蓋。
- **No Placeholders 掃描**：兩個 Task 的程式碼、測試斷言、插入點行號皆為可直接套用的完整內容；`issues.md` 原文留下的「是否需要同步清除原生選取狀態」待查證問題已在規劃階段實際追蹤程式碼（`pdf_reader_view.dart:_finishSelectionDrag()`／`view.js:renderer.getContents()`）給出具體結論，不是留給執行者臨場決定的空白。
- **型別/介面一致性**：`AnnotationToolbar` 新增的 `onClosePressed`（`VoidCallback`）與既有 `onNotePressed` 同型別、同呼叫慣例；`FoliateEpubReaderView.clearSelection` 的簽章（`GlobalKey<State<FoliateEpubReaderView>> key`）與同檔案既有 `nextPage`/`previousPage`/`setDecorations` 完全一致；`_handleCloseAnnotationToolbar()` 命名與既有 `_handleSelectionCleared`/`_handleNotePressed` 同一套 `_handleXxx` 命名慣例。
- **既有測試不回歸的具體論證**：Task 1 只新增一顆按鈕與一個獨立的 `onClosePressed` 回呼路徑，未修改 `_handleHighlightStyleSelected`／`_handlePdfHighlightStyleSelected`／`_annotationToolbarTop`／`_pdfAnnotationToolbarTop` 等既有邏輯本體；Task 2 的 `window.clearSelection()` 是全新獨立函式，未修改任何既有 `window.X` 函式或既有 `selectionchange`/`pointercancel` 監聽器邏輯。兩個 Task 皆安排執行完整既有測試套件作為實測佐證，不僅依賴此推論。
- **範圍誠實聲明**：本計畫刻意不新增「選色後仍保持開啟」的 EPUB 端專屬回歸測試（既有 PDF 端測試已足夠佐證未受影響的邏輯本體未被觸碰，見 Global Constraints），也不嘗試對 `evaluateJavascript` 呼叫本身寫自動化斷言（本專案既有基礎設施限制，誠實記錄而非假裝解決）。
- **規劃階段實測發現並已修正的跨 Issue 回歸**：本計畫規劃階段完整套用過 Task 1／Task 2 的每一步變更到實際程式碼並跑過測試（非僅紙上推演），過程中發現新增第 6 顆按鈕會讓 Issue 2 剛合併的 `_annotationToolbarWidth`（256.0）常數過期、導致 Issue 2 的兩則右緣裁切測試重新變紅（`Actual: <448.0>`）；已在 Task 1 Step 5 納入常數更新（256.0→304.0）並重新驗證全數 147 項測試（含 Issue 1／Issue 2 既有測試）與 `flutter analyze` 皆為綠燈，才定案本計畫的 Task 1 步驟順序。
