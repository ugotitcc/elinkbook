# Epic 24 Issue 8 — 閱讀工具列 FAB 化（6 顆按鈕整合）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** PDF 頂部工具列（現行傳統 `AppBar`）改為浮動圓形按鈕（FAB），視覺與位置比照 EPUB 既有樣式，最終達到與 EPUB 相同的 6 顆 FAB 按鈕（返回／目錄／版面設定／書籤 toggle／筆記／進度-跳頁）；現行「頁面導覽」從常駐畫面底部的元件改為浮動「進度/跳頁」按鈕觸發的 Bottom Sheet；沉浸模式（介面收合/展開）行為與 EPUB 既有機制一致。

**Architecture:** `ReaderScreen._buildBody()` 既有的 `format == BookFormat.epub && _chromeVisible` Positioned FAB 區塊（`Stack` 疊加層）新增對稱的 `format == BookFormat.pdf` 分支，重用既有 `_themedFabBackgroundColor`/`_themedFabIconColor`（已是格式無關的 getter，`_isFixedLayout` 對 PDF 恆為 `false`）與 `_showThemedModalBottomSheet`。PDF 目前完全沒有導航熱區（3×3 九宮格）能觸發沉浸模式切換——`PdfReaderView` 新增 `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數，比照 `FoliateEpubReaderView` 既有模式在 `build()` 內疊加 3×3 熱區 `Stack`（獨立、私有的 `_PdfNavZoneTapDetector`，用原始 `Listener` 觀察 pointer 事件、不註冊 `GestureRecognizer`，故不會與 `pdfrx` `PdfViewer` 自身的 pan/pinch/雙擊手勢競爭手勢競技場，也不影響既有 per-page 長按選取 `GestureDetector`）；`ReaderScreen._buildNativeView()` 的 PDF 分支接上 `resolved.navZoneActions`/`_handleZoneAction`（已是格式無關的既有方法）。現行常駐 `ReaderFooter`（PDF 頁尾）移除，改由新增的 `_openPdfProgressSheet()` 以 Bottom Sheet 呈現同一個 `ReaderFooter` widget。書籤 toggle FAB 圖示新增 `_pdfBookmarkAtCurrentPosition` getter（比照既有 `_bookmarkAtCurrentPosition`，共用同一份 `_fxlBookmarks` 快取），並修正 Notes Bottom Sheet 關閉後的快取刷新條件（原本只在 `_isFixedLayout` 時刷新，PDF 從未刷新過，這個既有缺口在新增可見的書籤圖示後會首次變得使用者可見，一併修正）。

**Tech Stack:** Flutter/Dart、既有 `flutter_test` 對真實 PDF fixture（`sample_multi_page.pdf`）驗證。

## Global Constraints

- **Page Label（邏輯頁碼標籤）雙顯示功能不在本工單範圍內**（人類已確認的範圍決策，2026-08-11）：查證 `pdfrx ^2.4.6`／`pdfrx_engine`／底層 `pdfium_dart` 三層套件原始碼，確認 `pdfrx` 公開的 `PdfDocument`/`PdfPage` API 完全沒有暴露 PDFium 的 `FPDF_GetPageLabel`（該 C API 確實存在於 `pdfium_dart` 的底層生成綁定中，但文件的原生 FFI handle 是背景 worker 內部實作細節，應用程式端無法直接呼叫）。`issues.md`/`spec.md` User Story 21「若 PDF 提供邏輯頁碼標籤則雙顯示」這個分支，用目前釘選版本技術上無法實作。本工單頁碼一律採**純數字顯示**（`目前頁/總頁數`），不新增 `pageLabel` 欄位/管線。若未來需要此功能，需先另立技術 Spike 評估 fork/patch `pdfrx` 加上 FFI 綁定。
- **PDF 導航熱區（3×3 九宮格）接線一併納入本工單範圍**（人類已確認的範圍決策，2026-08-11）：PDF 目前完全沒有能觸發 `ZoneAction.menu`（沉浸模式切換）的手勢，`_chromeVisible` 對 PDF 是永遠不會變成 `false` 的死分支——若不接線，「沉浸模式收合/展開行為與 EPUB 既有機制一致」這項既有 AC 無法成立（FAB 會永遠常駐顯示，不是真正的沉浸模式）。`reader_screen.dart` 既有程式碼註解（`_buildNativeView` PDF 分支）也明確記錄「導航熱區留待 Issue 8 接線」；PRD FR-24 本就要求 3×3 熱區適用於 EPUB 流式／PDF／EPUB FXL 三種格式。
- **`_PdfNavZoneTapDetector` 為 `pdf_reader_view.dart` 私有類別，刻意不與 `foliate_epub_reader_view.dart` 既有的 `_NavZoneTapDetector` 共用/抽成共用模組**：比照本專案既有架構原則（`PdfReaderView`／`FoliateEpubReaderView` 是兩條刻意保持獨立的渲染路徑，見 `CLAUDE.md`「`FoliateEpubReaderView` 刻意不比照這個模式」的既有先例），避免在兩個本來就無關聯的 widget 之間引入不必要的共享依賴。核心「量測按下到放開的時長/位移，判定是否為快速點擊」邏輯直接複製（兩處各自約 30 行，穩定、不預期需要同步變更）。
- **`_PdfNavZoneTapDetector` 用 `Listener`（不用 `GestureDetector`/`TapGestureRecognizer`），故不進入手勢競技場**：`pdfrx` 的 `PdfViewer` 內部用 `InteractiveViewer`（pan/pinch）與自己的 `GestureDetector`（`onTapUp`/`onDoubleTapDown`，預設 `onGeneralTap` 未設定時皆為 no-op，已查證 `pdfrx-2.4.7` 原始碼）。`Listener` 只被動觀察原始 pointer 事件、不註冊任何 `GestureRecognizer`、不參與競技場裁定，因此疊加在 `PdfViewer` 之上不會攔截其 pan/pinch/長按選取手勢——這與既有 `_buildSelectionGestureLayer`（Issue 4，`HitTestBehavior.translucent` 的 `GestureDetector`，會參與競技場但用 `translucent` 不消耗 hit-test）是不同機制，兩者可以共存：長按選取的按壓時長遠超過 `_PdfNavZoneTapDetector` 的快速點擊時長判定門檻（400ms），不會被誤判為熱區點擊。
- **手動裁切編輯模式（`_cropEditModeActive == true`）時，新增的 6 顆 PDF FAB 一律不顯示**：既有 `PopScope.canPop: !_cropEditModeActive` 的既有註解已明確記錄「裁切模式沒有使用者手勢可以主動離開，必須透過畫面上的原生確認按鈕」——裁切模式是刻意設計的「僅能透過 `PdfCropFrameOverlay` 自身控制項互動」的封閉狀態，FAB 若在此時仍可見/可點擊會破壞這個既有設計意圖（例如誤觸「返回」FAB 跳出裁切模式，或「目錄」FAB 與裁切框選 UI 重疊）。
- **`navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 皆為 `PdfReaderView` 新增的具名參數，預設值比照 `FoliateEpubReaderView` 既有慣例**（`navZoneActions` 預設全 9 格 `ZoneAction.none`、`onZoneAction` 預設 `null`、`showNavZoneDebugOverlay` 預設 `false`）：既有呼叫端（Issue 1-7 既有測試）不受影響，零回歸。
- **舊 PDF `AppBar` 退場只需刪除 Dart 端 `_buildAppBarActions()` 的 `case BookFormat.pdf` 分支與更新 `appBar:` 三元運算式**，不涉及任何原生（Kotlin）程式碼異動——PDF 的原生渲染叢集與對應 method channel 已在 Issue 1 完全清退（見 `CLAUDE.md`「架構遷移中」段落），現在的 PDF `AppBar` 純粹是 Dart 端 `Scaffold.appBar` 建構邏輯，不存在對應的原生 method channel 契約需要一併移除。
- **`flutter analyze` 乾淨、每個 Task 結束後相關測試全數通過**是每個 Task 的隱含驗收條件。全專案 `flutter test` 基準為 **1146/1146 通過**（已於規劃階段實際執行確認，對應 Issue 7 合併後狀態）。

---

### Task 1: `PdfReaderView` 新增導航熱區（NavZone）接線

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_nav_zone_test.dart`（新檔案）

**Interfaces:**
- Consumes: `ZoneAction`（`app/lib/reader/zone_action.dart`，既有 enum，`previousPage`/`nextPage`/`menu`/`none`）。
- Produces: `PdfReaderView` 新增建構參數 `List<ZoneAction> navZoneActions`（預設全 `none`）、`ValueChanged<ZoneAction>? onZoneAction`（預設 `null`）、`bool showNavZoneDebugOverlay`（預設 `false`）——Task 2 依賴這三個參數。畫面 Key 慣例：`pdf_reader_nav_zone_$index`（`index` 0-8，左上→右下）。

- [x] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_nav_zone_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  setUp(() => pdfrxInitialize());

  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('navZoneActions 預設全部為 none 時，點擊格子仍呼叫 onZoneAction 並帶入 none',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();

    expect(triggered, ZoneAction.none);
  });

  testWidgets('點擊熱區格子時，觸發該索引設定的 ZoneAction', (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[0] = ZoneAction.previousPage;
    actions[2] = ZoneAction.nextPage;
    actions[4] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();
    expect(triggered, ZoneAction.menu);

    triggered = null;
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_0')));
    await tester.pump();
    expect(triggered, ZoneAction.previousPage);

    triggered = null;
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_2')));
    await tester.pump();
    expect(triggered, ZoneAction.nextPage);
  });

  testWidgets('showNavZoneDebugOverlay 預設 false 時不顯示動作文字標籤',
      (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.pump();

    expect(find.text('選單'), findsNothing);
  });

  testWidgets('showNavZoneDebugOverlay 為 true 時顯示動作文字標籤', (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          showNavZoneDebugOverlay: true,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    await tester.pump();

    expect(find.text('選單'), findsOneWidget);
  });

  testWidgets(
      '按壓超過快速點擊時長判定門檻不觸發 onZoneAction，避免與長按選取手勢衝突',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(triggered, isNull);
  });

  testWidgets('onPointerCancel 後清除按壓暫存狀態，取消手勢不觸發 onZoneAction，後續正常點擊仍正確判定',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final cancelledGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await cancelledGesture.cancel();
    await tester.pump();

    expect(triggered, isNull);

    // 取消手勢後，暫存的按下狀態須確實清除——後續一次正常的快速點擊仍應
    // 正確觸發，證明沒有殘留舊值造成誤判（審查意見 Minor 1）。
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();
    expect(triggered, ZoneAction.menu);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: FAIL（`navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 參數尚未定義，編譯錯誤）。

- [x] **Step 3: 新增建構參數**

在 `app/lib/reader/pdf_reader_view.dart` 檔案開頭新增 import（既有 import 區塊，`percent_rect.dart` 之後）：

```dart
import 'zone_action.dart';
```

在 `class PdfReaderView` 既有欄位區塊，`onSelectionCanceled` 欄位（Issue 4 新增區塊最後一個欄位）之後新增：

```dart
  // ── epic-24-pdf-engine-rebuild Issue 8 新增 ──
  /// 3×3 導覽熱區設定，索引 0-8 對應左上→右下（design.md 決策 #8）。預設
  /// 全部 [ZoneAction.none]（比照 [FoliateEpubReaderView] 既有預設值），
  /// 實際產品預設由 ReaderScreen 透過 ResolvedPreferences.navZoneActions
  /// 明確傳入。
  final List<ZoneAction> navZoneActions;
  /// 使用者點擊熱區格子時觸發，帶入該格設定的 [ZoneAction]（包含
  /// [ZoneAction.none]，呼叫端自行決定是否忽略）。
  final ValueChanged<ZoneAction>? onZoneAction;
  /// 除錯用：顯示 9 宮格邊框與動作文字，預設 false。
  final bool showNavZoneDebugOverlay;
```

在建構子中新增對應具名參數（`onSelectionCanceled,` 之後）：

```dart
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
```

- [x] **Step 4: `build()` 疊加 3×3 熱區**

修改 `_PdfReaderViewState.build()` 方法末尾的 `return` 陳述式。原本：

```dart
    return Listener(
      onPointerDown: (_) {
        _activePointerCount++;
        if (_activePointerCount >= 2) _cancelSelectionDrag();
      },
      onPointerUp: (_) => _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
      onPointerCancel: (_) => _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
      child: colorFiltered,
    );
```

改為：

```dart
    return Stack(
      children: [
        Listener(
          onPointerDown: (_) {
            _activePointerCount++;
            if (_activePointerCount >= 2) _cancelSelectionDrag();
          },
          onPointerUp: (_) =>
              _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
          onPointerCancel: (_) =>
              _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
          child: colorFiltered,
        ),
        // epic-24-pdf-engine-rebuild Issue 8：3×3 導覽熱區，比照
        // FoliateEpubReaderView 既有的 _ZoneOverlay 版面（Column of Row of
        // Expanded），疊加在 PdfViewer 之上。見 Global Constraints——用
        // Listener（_PdfNavZoneTapDetector）而非 GestureDetector，故不會
        // 攔截 PdfViewer 自身的 pan/pinch/長按選取手勢。
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: _PdfNavZoneTapDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  String _pdfZoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }
```

（`_pdfZoneActionLabel` 是 `_PdfReaderViewState` 的新增私有方法，緊接在 `build()` 方法之後；上面程式碼區塊的收尾 `}` 對應 `build()` 方法本身的結束括號。）

- [x] **Step 5: 新增私有 `_PdfNavZoneTapDetector`**

在 `app/lib/reader/pdf_reader_view.dart` 檔案最末尾（既有私有類別 `_PdfSelectionDragState` 之後）新增：

```dart

/// 九宮格導覽熱區的單一格子（epic-24-pdf-engine-rebuild Issue 8）。刻意
/// 用 [Listener] 直接觀察原始 pointer 事件、自行判斷「是否為一次快速
/// 點擊」（位移在 [_tapSlop] 內、耗時在 [_tapMaxDurationMs] 內），完全不
/// 註冊 GestureRecognizer、不參與手勢競技場——確保不會攔截 `PdfViewer`
/// 自身的 pan/pinch/雙擊手勢，也不影響既有 per-page 長按選取
/// GestureDetector（見 Global Constraints）。比照
/// `foliate_epub_reader_view.dart` 的 `_NavZoneTapDetector` 相同技術手段，
/// 刻意各自獨立實作、不抽成共用模組（見 Global Constraints）。
class _PdfNavZoneTapDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PdfNavZoneTapDetector({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<_PdfNavZoneTapDetector> createState() => _PdfNavZoneTapDetectorState();
}

class _PdfNavZoneTapDetectorState extends State<_PdfNavZoneTapDetector> {
  Offset? _downPosition;
  int? _downTimeMs;

  static const _tapSlop = 18.0;
  static const _tapMaxDurationMs = 400;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final elapsed = DateTime.now().millisecondsSinceEpoch - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= _tapMaxDurationMs && distance <= _tapSlop) {
          widget.onTap();
        }
      },
      // 審查意見 Minor 1：系統層級手勢中斷（例如滑出螢幕邊緣觸發 OS
      // 系統手勢）會送出 PointerCancelEvent 而非 PointerUpEvent，須主動
      // 清除暫存狀態，避免殘留舊值（比照 onPointerUp 判定失敗時的隱含
      // 語意，這裡明確清空而非留給下一次 onPointerDown 覆寫）。
      onPointerCancel: (_) {
        _downPosition = null;
        _downTimeMs = null;
      },
      child: widget.child,
    );
  }
}
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart --reporter expanded`
Expected: 6 項全數通過。

- [x] **Step 7: 執行既有 PDF 測試確認零回歸**

Run: `flutter test test/reader/`
Expected: 全數通過（特別留意 `pdf_reader_view_selection_test.dart`——新增的 Stack 疊層不應影響既有長按選取手勢測試）。

- [x] **Step 8: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 9: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_nav_zone_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增 3x3 導覽熱區接線（NavZone）"
```

---

### Task 2: `ReaderScreen` — PDF AppBar 退場、6 顆 FAB、進度 Bottom Sheet、書籤圖示反映

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（新增測試至既有檔案）

**Interfaces:**
- Consumes: `PdfReaderView.navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay`（Task 1）。
- Produces: PDF 閱讀畫面新增 6 顆 FAB（Key 慣例：`reader_pdf_back_button`／`reader_pdf_toc_button`／`reader_pdf_settings_button`／`reader_pdf_bookmark_toggle_button`／`reader_pdf_notes_button`／`reader_pdf_progress_button`），Scaffold 不再為 PDF 格式建構傳統 `AppBar`，`_pdfBookmarkAtCurrentPosition`（`Bookmark?` getter）、`_openPdfProgressSheet()`（`void` 方法）。`_handlePageRendered()` 新增開書時載入書籤快取，確保書籤 FAB 初次顯示即正確反映既有書籤狀態。

本 Task 涵蓋 AppBar 退場、FAB 骨架、進度 Bottom Sheet、書籤圖示反映——刻意不拆成更細的 Task，因為 FAB 骨架（Step 9）直接引用 `_pdfBookmarkAtCurrentPosition`/`_openPdfProgressSheet`（Step 5-6 新增），若拆開會讓其中一個 Task 在另一個完成前無法通過編譯，違反「每個 Task 都有可獨立驗證的成果」原則。

- [x] **Step 1: 撰寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 既有 PDF 相關測試群組之後（`tearDownAll` 之前）新增：

```dart
  Future<void> pumpAndWaitPdfRendered(
    WidgetTester tester,
    GlobalKey<State<ReaderScreen>> key, {
    String filePath = 'test/fixtures/sample_multi_page.pdf',
    String bookId = 'b_pdf_fab',
    BookmarksRepository? bookmarksRepository,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: filePath,
          bookId: bookId,
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  testWidgets('PDF 閱讀畫面顯示 6 顆浮動 FAB 按鈕，不建構傳統 AppBar',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    expect(find.byType(AppBar), findsNothing);
    for (final keyName in [
      'reader_pdf_back_button',
      'reader_pdf_toc_button',
      'reader_pdf_settings_button',
      'reader_pdf_bookmark_toggle_button',
      'reader_pdf_notes_button',
      'reader_pdf_progress_button',
    ]) {
      expect(find.byKey(Key(keyName)), findsOneWidget, reason: keyName);
    }
  });

  testWidgets('PDF FAB：書籤/筆記按鈕在未提供 bookmarksRepository 時不建構',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key, bookmarksRepository: null);

    expect(find.byKey(const Key('reader_pdf_bookmark_toggle_button')), findsNothing);
    expect(find.byKey(const Key('reader_pdf_notes_button')), findsNothing);
    // 其餘 4 顆不受影響。
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_pdf_toc_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_pdf_settings_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_pdf_progress_button')), findsOneWidget);
  });

  testWidgets('PDF FAB：目錄按鈕於書籍成功開啟（onPageRendered 觸發）後啟用',
      (tester) async {
    // 注意：_pdfTocLoaded 實際語意是「背景載入已發起」的去重旗標（見
    // reader_screen.dart:1004-1008 既有註解「先設 true 再發起非同步呼叫，
    // 避免短時間內重複觸發」），在 onPageRendered 觸發的同一個回呼內就會
    // 同步設為 true，不是等真正載入完成才變 true；本測試只驗證
    // pumpAndWaitPdfRendered（等待 onPageRendered）之後按鈕已啟用，不斷言
    // 更早的停用狀態。
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(
      tester,
      key,
      filePath: 'test/fixtures/sample_pdf_toc.pdf',
    );

    final finder = find.byKey(const Key('reader_pdf_toc_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
  });

  testWidgets('點擊中間熱區（menu）後，PDF 6 顆 FAB 全部收合；再次點擊後恢復顯示',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見既有 EPUB
    // 測試慣例，app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
    await tester.pump();

    for (final keyName in [
      'reader_pdf_back_button',
      'reader_pdf_toc_button',
      'reader_pdf_settings_button',
      'reader_pdf_notes_button',
      'reader_pdf_progress_button',
    ]) {
      expect(find.byKey(Key(keyName)), findsNothing, reason: keyName);
    }

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
    await tester.pump();

    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
  });

  testWidgets('點擊左/右熱區觸發換頁，不影響沉浸模式狀態（design.md 決策 #14）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    // rightFlip 模板：index 2（右欄）＝ nextPage，index 0（左欄）＝
    // previousPage（比照既有 EPUB 測試慣例）。
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_2')));
    await tester.pump();
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_0')));
    await tester.pump();
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
  });

  testWidgets('手動裁切編輯模式啟用時，PDF FAB 全部不顯示', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    await tester.tap(find.byKey(const Key('reader_pdf_settings_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // PdfSettingsSheet「手動選區」按鈕（既有 Issue 3 UI，
    // pdf_settings_sheet.dart:357 `Key('pdf_settings_crop_mode_manual')`）
    // 點擊後透過 onRequestManualCrop 回呼通知 ReaderScreen 進入手動裁切
    // 互動模式（`_handleRequestManualCrop` 設定 `_cropEditModeActive =
    // true`，見既有 Issue 3 實作）。
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (final keyName in [
      'reader_pdf_back_button',
      'reader_pdf_toc_button',
      'reader_pdf_settings_button',
      'reader_pdf_bookmark_toggle_button',
      'reader_pdf_notes_button',
      'reader_pdf_progress_button',
    ]) {
      expect(find.byKey(Key(keyName)), findsNothing, reason: keyName);
    }
  });

  testWidgets('PDF 進度按鈕：點擊後開啟含 ReaderFooter 的 Bottom Sheet，跳頁後正確關閉且無例外',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    await tester.tap(find.byKey(const Key('reader_pdf_progress_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // ReaderFooter 內部固定以 Key('reader_footer') 標記自身（比照既有
    // 流式 EPUB「進度/跳頁 Bottom Sheet」測試慣例，見同檔案「流式 EPUB：
    // 點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter 的 Bottom Sheet」測試），
    // 不需額外 import ReaderFooter 型別。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);

    // 關閉 Bottom Sheet（點擊背景遮罩），不斷言精確跳轉後頁碼——理由同
    // Issue 6/7 既有測試教訓：透過 Modal Route 的頁碼更新在測試環境下有
    // 不可靠時序（見 issues.md Issue 6 段落）。
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 常駐頁尾（in-flow ReaderFooter）已移除，不再擠壓可視閱讀區域',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(tester, key);

    // 開啟中的閱讀畫面（未開啟進度 Bottom Sheet）不應有任何 in-flow
    // ReaderFooter——目前唯一的 ReaderFooter 掛載點是 Bottom Sheet
    // （見上一則測試），未開啟時應完全找不到。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets(
      'PDF 書籤 FAB 圖示：開啟已有書籤的頁面時，初次顯示即正確為 star（不需事先 toggle 或開啟筆記面板，審查意見 Important 1）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(
      Bookmark(id: 'bm0', bookId: 'b_pdf_fab', name: '第 1 頁', pdfPageIndex: 0),
    );
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(
      tester,
      key,
      bookmarksRepository: bookmarksRepository,
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 5),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final iconFinder = find.descendant(
      of: find.byKey(const Key('reader_pdf_bookmark_toggle_button')),
      matching: find.byIcon(Icons.star),
    );
    expect(iconFinder, findsOneWidget);
  });

  testWidgets('PDF 書籤 FAB 圖示：toggle 前後正確反映 star/star_border',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(
      tester,
      key,
      bookmarksRepository: bookmarksRepository,
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 5),
    );
    await tester.pump();

    var iconFinder = find.descendant(
      of: find.byKey(const Key('reader_pdf_bookmark_toggle_button')),
      matching: find.byIcon(Icons.star_border),
    );
    expect(iconFinder, findsOneWidget);

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    iconFinder = find.descendant(
      of: find.byKey(const Key('reader_pdf_bookmark_toggle_button')),
      matching: find.byIcon(Icons.star),
    );
    expect(iconFinder, findsOneWidget);

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    iconFinder = find.descendant(
      of: find.byKey(const Key('reader_pdf_bookmark_toggle_button')),
      matching: find.byIcon(Icons.star_border),
    );
    expect(iconFinder, findsOneWidget);
  });

  testWidgets(
      'PDF 書籤 FAB 圖示：透過筆記面板新增書籤、關閉面板後圖示正確刷新（既有 _isFixedLayout 限定的刷新條件缺口，本工單新增可見 FAB 後一併修正）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpAndWaitPdfRendered(
      tester,
      key,
      bookmarksRepository: bookmarksRepository,
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 5),
    );
    await tester.pump();

    // 直接寫入 repository 模擬「透過筆記面板的書籤分頁新增書籤」，而非驅動
    // NotesBottomSheet 內部 UI（該面板既有互動已由自身測試覆蓋，非本測試
    // 重點）。
    await bookmarksRepository.insert(
      Bookmark(
        id: 'bm1',
        bookId: 'b_pdf_fab',
        name: '第 1 頁',
        pdfPageIndex: 0,
      ),
    );

    await tester.tap(find.byKey(const Key('reader_pdf_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);

    // 關閉 Bottom Sheet（模擬使用者離開筆記面板）。
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final iconFinder = find.descendant(
      of: find.byKey(const Key('reader_pdf_bookmark_toggle_button')),
      matching: find.byIcon(Icons.star),
    );
    expect(iconFinder, findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF"`
Expected: FAIL（`reader_pdf_*` 按鈕不存在，`pdf_reader_nav_zone_*` 尚未接線，`_pdfBookmarkAtCurrentPosition`/`_openPdfProgressSheet` 未定義，PDF 開書時尚未載入書籤快取）。

- [x] **Step 3: 移除舊 PDF AppBar**

修改 `app/lib/screens/reader_screen.dart` 的 `build()` 方法，`Scaffold` 的 `appBar:` 三元運算式（原本）：

```dart
        appBar: (_isFixedLayout ||
                !_chromeVisible ||
                (format == BookFormat.epub && _dispatchedIsFixedLayout == false))
            ? null // 固定版面（如漫畫）、沉浸模式已收起介面、或流式 EPUB 時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

改為：

```dart
        appBar: (_isFixedLayout ||
                !_chromeVisible ||
                format == BookFormat.pdf ||
                (format == BookFormat.epub && _dispatchedIsFixedLayout == false))
            ? null // 固定版面（如漫畫）、沉浸模式已收起介面、PDF（epic-24 Issue 8 起改用 FAB）、或流式 EPUB 時隱藏 Scaffold AppBar
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

在 `_buildAppBarActions()` 方法中，刪除整個 `case BookFormat.pdf:` 分支（原本）：

```dart
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings, size: _appBarIconSize),
            tooltip: '版面設定',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks, size: _appBarIconSize),
              tooltip: '筆記',
              style: IconButton.styleFrom(
                minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              onPressed: _state == _RenderState.rendered
                  ? () => _openNotesSheet(format)
                  : null,
            ),
        ];
```

改為（PDF 不再透過 `AppBar` 建構任何操作按鈕，`_buildAppBarActions()` 對 PDF 現在永遠不會被呼叫到——`appBar:` 三元運算式已在上段確保 PDF 恆為 `null`——但 `switch` 語句需要窮盡涵蓋所有 `BookFormat` 值，故保留一個明確回傳 `null` 的空分支）：

```dart
      case BookFormat.pdf:
        return null;
```

- [x] **Step 4: `_buildNativeView` PDF 分支接上導覽熱區**

修改 `_buildNativeView()` 方法中 `case BookFormat.pdf:` 分支的 `PdfReaderView(...)` 建構呼叫，在既有 `onSelectionCanceled: _handlePdfSelectionCanceled,` 之後新增：

```dart
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
```

同時刪除該分支開頭的過期註解（原本）：

```dart
        // epic-24-pdf-engine-rebuild：單頁/雙頁（Issue 2）、影像濾鏡/
        // 裁切（Issue 3）、劃線選取回呼（Issue 4）已補回；
        // 導航熱區（navZoneActions/onZoneAction）留待 Issue 8 接線。
```

改為：

```dart
        // epic-24-pdf-engine-rebuild：單頁/雙頁（Issue 2）、影像濾鏡/
        // 裁切（Issue 3）、劃線選取回呼（Issue 4）、導航熱區（Issue 8）
        // 皆已補回。
```

- [x] **Step 5: 移除既有 in-flow PDF `ReaderFooter`，新增 `_openPdfProgressSheet()`**

在 `_buildBody()` 方法內，刪除既有 in-flow PDF 頁尾區塊（原本）：

```dart
            if (format == BookFormat.pdf &&
                _pdfPageInfo != null &&
                (_resolved?.showFooter ?? false) &&
                _chromeVisible)
              ReaderFooter(
                currentPage: _pdfPageInfo!.pageIndex + 1,
                totalPages: _pdfPageInfo!.totalPages,
                onPageChanged: (page1Indexed) {
                  // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                  PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
                },
              ),
```

（刪除後，`Column` 的子項只剩 `Expanded(child: body)` 與既有的 EPUB `_buildEpubFooter(...)` 條件區塊。）

在 `_openFoliateProgressSheet()` 方法之後新增：

```dart
  /// PDF「進度/跳頁」浮動按鈕開啟的 Bottom Sheet（epic-24-pdf-engine-rebuild
  /// Issue 8）：內容直接沿用既有 `ReaderFooter`（原本 in-flow 常駐畫面
  /// 底部，現改為浮動按鈕觸發顯示，不再擠壓可視閱讀區域高度，比照 EPUB
  /// `_openFoliateProgressSheet` 既有機制）。`_pdfPageInfo` 為 null（
  /// `onPageChanged` 尚未觸發過）時顯示空白 Sheet，比照
  /// `reader_pdf_progress_button` 本身不額外 gating 的簡化決策（同
  /// `_openFoliateProgressSheet`）。
  void _openPdfProgressSheet() {
    final pageInfo = _pdfPageInfo;
    _showThemedModalBottomSheet<void>(
      builder: (_) => SafeArea(
        child: pageInfo == null
            ? const SizedBox.shrink()
            : ReaderFooter(
                currentPage: pageInfo.pageIndex + 1,
                totalPages: pageInfo.totalPages,
                onPageChanged: (page1Indexed) {
                  PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
                },
              ),
      ),
    );
  }
```

- [x] **Step 6: 新增 `_pdfBookmarkAtCurrentPosition` getter**

在 `_bookmarkAtCurrentPosition` getter 之後新增：

```dart
  /// PDF 版本的「目前頁是否已有書籤」（epic-24-pdf-engine-rebuild Issue
  /// 8）：比對 `pdfPageIndex`，比照 [_bookmarkAtCurrentPosition] 的 EPUB
  /// 版本邏輯，共用同一份 [_fxlBookmarks] 快取（[_loadFxlBookmarks] 是
  /// 格式無關的 `repository.listByBook` 查詢，見該方法定義）。
  Bookmark? get _pdfBookmarkAtCurrentPosition {
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (pageIndex == null) return null;
    for (final bookmark in _fxlBookmarks) {
      if (bookmark.pdfPageIndex == pageIndex) return bookmark;
    }
    return null;
  }
```

- [x] **Step 7: PDF 開書時一併載入書籤快取（審查意見 Important 1）**

`_loadFxlBookmarks()` 目前只在「toggle 書籤」與「筆記 Bottom Sheet 關閉後（Step 7→8，僅 `_isFixedLayout`）」被呼叫，`_handlePageRendered()` 從未在 PDF 開書當下呼叫過——這代表使用者開啟一本**過去已加入書籤的 PDF**、翻到已加書籤的頁面時，`_fxlBookmarks` 仍是空陣列，`_pdfBookmarkAtCurrentPosition` 回傳 `null`，Step 8 新增的書籤 FAB 會誤顯示為空心星號，直到使用者手動 toggle 一次或開過一次筆記面板為止。

修改 `_handlePageRendered()` 方法，在既有 PDF 目錄背景載入區塊（`if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) { ... }`）內新增書籤快取載入呼叫（原本）：

```dart
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
    }
```

改為：

```dart
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
      // epic-24-pdf-engine-rebuild Issue 8（審查意見 Important 1）：PDF
      // 開書成功時一併載入書籤快取，讓 Step 9 新增的書籤 FAB 星號圖示在
      // 使用者尚未手動 toggle／開過筆記面板前就能正確反映既有書籤狀態。
      // 借用既有 _pdfTocLoaded 旗標的去重保護（本區塊本來就只會在單一
      // PDF 開書流程中執行一次），不另外新增專屬旗標。
      // _loadFxlBookmarks() 內部已對 widget.bookmarksRepository == null
      // 做早退防呆，此處不需額外判斷。
      _loadFxlBookmarks();
    }
```

- [x] **Step 8: 修正 Notes Sheet 關閉後的書籤快取刷新條件**

修改 `_openNotesSheet()` 方法內 `.then((_) { ... })` 回呼中的既有條件（原本）：

```dart
      if (_isFixedLayout) _loadFxlBookmarks();
```

改為：

```dart
      // epic-24-pdf-engine-rebuild Issue 8：原本只在 _isFixedLayout（EPUB
      // FXL）時刷新——PDF 從未有對應的可見書籤圖示，這個既有缺口不會被
      // 使用者察覺；本工單新增 reader_pdf_bookmark_toggle_button 後，同一個
      // 缺口會首次變得使用者可見（透過筆記面板新增/刪除 PDF 書籤後，FAB
      // 圖示會停留在過期狀態），一併修正為涵蓋 PDF。
      if (_isFixedLayout || format == BookFormat.pdf) _loadFxlBookmarks();
```

- [x] **Step 9: 新增 6 顆 PDF FAB**

在 `_buildBody()` 方法內，既有 6 個 EPUB FAB 的 `Positioned` 區塊（`reader_foliate_progress_button` 那一個，`top: 240, right: 16`）之後、頁首/頁尾文字區塊（`if (format == BookFormat.epub && (_resolved?.showHeader ?? false) ...)`）之前，新增對稱的 6 個 PDF FAB 區塊：

```dart
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: !_pdfTocLoaded ? null : _openPdfToc,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed:
                          _state == _RenderState.rendered ? _openPdfSettings : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_bookmark_toggle_button'),
                      icon: Icon(
                        _pdfBookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
                      ),
                      tooltip: _pdfBookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _pdfPageInfo == null ? null : _togglePdfBookmark,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf &&
                _chromeVisible &&
                !_cropEditModeActive &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: _state == _RenderState.rendered
                          ? () => _openNotesSheet(BookFormat.pdf)
                          : null,
                    ),
                  ),
                ),
              ),
            if (format == BookFormat.pdf && _chromeVisible && !_cropEditModeActive)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_pdf_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openPdfProgressSheet,
                    ),
                  ),
                ),
              ),
```

- [x] **Step 10: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF"`
Expected: 全數通過（本 Task 新增 11 則）。

- [x] **Step 11: 執行既有 EPUB FAB/AppBar 相關測試確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過。

- [x] **Step 12: 執行全專案測試確認零回歸**

Run: `flutter test`
Expected: 全數通過，通過總數為基準 1146 之上 + 17（Task 1 六則 + 本 Task 十一則），合計 1163。若出現與本工單變更無關的既有間歇性失敗（例如 `pdf_reader_view_dual_page_test.dart`，見 Issue 6/7 合併前審查歷程），單獨重跑該檔案確認通過即可，非本工單需修復範圍。

- [x] **Step 13: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 14: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): ReaderScreen PDF AppBar 退場，改用 6 顆 FAB＋進度 Bottom Sheet＋書籤圖示反映（含開書即載入書籤快取）"
```

---

### Task 3: 端對端驗證與計畫收尾

- [x] **Step 1: `flutter analyze` 確認整專案乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 執行本工單全部相關測試**

Run: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart test/screens/reader_screen_test.dart`
Expected: 全數通過，新增本工單測試數（Task 1 +6、Task 2 +11，共 +17）。

- [x] **Step 3: 執行全專案測試確認零回歸**

Run: `flutter test`
Expected: 全數通過，通過總數應為 Issue 7 合併時基準（1146）之上，新增 +17（合計 1163）。

- [x] **Step 4: 對照 `issues.md` Issue 8 驗收條件自我檢查**

逐項確認：
- PDF 閱讀畫面顯示 6 顆浮動圓形按鈕（返回／目錄／版面設定／書籤 toggle／筆記／進度-跳頁），底色/圖示色正確跟隨 `Theme.of(context)`（Task 2 重用既有 `_themedFabBackgroundColor`/`_themedFabIconColor`）。
- 各按鈕功能正確（Task 2）。
- 頁碼顯示：**Page Label 雙顯示已依人類確認的範圍決策移出本工單**（見 Global Constraints），本工單僅提供純數字頁碼顯示（Task 2 `_openPdfProgressSheet`），跳頁邏輯以絕對頁碼運算（既有 `PdfReaderView.jumpToPage`，未變動）。
- 沉浸模式收合/展開行為與 EPUB 既有機制一致（Task 1 NavZone 接線 + Task 2 `_chromeVisible` gating）。
- 現行 PDF `AppBar` 已完全移除，無殘留死碼（Task 2 Step 3；原生 method channel 契約已於 Issue 1 清退，見 Global Constraints，本工單無對應原生異動）。
- 單元測試驗證 6 顆按鈕的顏色/啟用條件/點擊行為（Task 2）。
- `flutter analyze` 乾淨、全專案 `flutter test` 全數通過（Step 1-3）。

- [x] **Step 5: 更新本工單計畫檔案的完成狀態**

將本檔案（`plan-issue-8.md`）中所有已完成 Task 的 `- [x]` 改為 `- [x]`。

- [x] **Step 6: 提交追蹤性 commit（若 Step 5 有變更）**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-8.md
git commit -m "docs(epic-24): plan-issue-8 全部 Task 標記完成"
```

- [x] **Step 7: 提醒人類後續文件動作（非本工單程式碼範圍）**

`issues.md` Issue 8 現行文字仍包含「頁碼顯示正確依是否有 Page Label 呈現雙顯示或純數字」這項驗收條件字面文字，與本計畫 Global Constraints 記錄的範圍決策（Page Label 移出本工單）不完全一致。建議人類決定：(a) 直接編輯 `issues.md` 該行文字改為「僅純數字頁碼，Page Label 另立技術 Spike 評估」，或 (b) 正式登記一張新的、標記 `needs-triage` 的後續 issue。本 Task 不自行修改 `issues.md`（超出「撰寫實作計畫」範圍，且該檔案的異動應如既有慣例走 `/superpowers:receiving-code-review` 而非本計畫直接動筆）。
