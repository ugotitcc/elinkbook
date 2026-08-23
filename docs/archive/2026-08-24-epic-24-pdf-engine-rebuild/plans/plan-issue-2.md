# Epic 24 Issue 2 — 雙頁並列（Facing Spread）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `PdfReaderView` 支援三態雙頁並列（自動/永遠雙頁/永遠單頁），底層改由 `pdfrx` 的 `layoutPages`/`calculateCurrentPageNumber` 客製化排版 API 實作，取代舊架構自行拼接點陣圖的作法，且單頁模式下的既有行為（Issue 1）零回歸。

**Architecture:** 三個 Task 建構純函式模組 `pdf_spread_layout.dart`（雙頁配對規則、幾何排版、spread 導航，完全獨立於 `pdfrx`/Flutter widget，可用 `test()` 直接單元測試，不需 `pdfrxInitialize()`）；接著四個 Task 把這個模組接進 `PdfReaderView`（新增建構參數、`layoutPages`/`calculateCurrentPageNumber` 兩個 callback、三個既有導航方法的雙頁分支、`didUpdateWidget` 執行期切換）；最後一個 Task 接線 `reader_screen.dart` 並跑全專案回歸。單頁模式下 `layoutPages`/`calculateCurrentPageNumber` 一律傳 `null`，讓 pdfrx 走與 Issue 1 完全相同的內部路徑，零回歸是「構造性保證」而非只靠測試證明。

**Tech Stack:** Flutter/Dart（`pdfrx` 既有依賴，不新增套件）、既有 `DualPageMode`/`DualPageDirection` enum。

## Global Constraints

- 語意與資料層完全不變：`DualPageMode`（`auto`/`always`/`never`）、`DualPageDirection`（`ltr`/`rtl`）、`dualPageCoverAlone` 三個既有型別與欄位不得修改，`app/lib/screens/pdf_settings_sheet.dart` 的 UI 程式碼不得修改。
- 「自動」模式下橫向啟用雙頁、直向恢復單頁；封面獨立顯示時第 1 頁（index 0）為單頁 spread，之後兩兩配對（`CONTEXT.md`「雙頁模式」「Spread」詞彙定義，唯一事實來源）。
- 單頁模式（`_dualPageEnabled == false`）下，`PdfViewerParams` 的 `layoutPages`/`calculateCurrentPageNumber` 一律傳 `null`，且三個既有導航方法（`_jumpToPage`/`_nextPage`/`_previousPage`）的單頁分支必須是 Issue 1 程式碼的逐字搬移，不得有任何改動——這是零回歸的構造性保證，不是靠測試事後驗證。
- 測試策略：直接用 `flutter test`（非 `integration_test/`）對真實 PDF fixture 驗證，不透過真機/模擬器（`pdfrx` 純 Dart FFI，桌面 host 可載入真實 PDFium，見 `spec.md`「Testing Decisions」）。純函式測試（`pdf_spread_layout_test.dart`）用 `test()`，不需 `pdfrxInitialize()`；widget 測試沿用 Issue 1 既有樣板（`setUp(() => pdfrxInitialize())`、`tester.runAsync()` + 輪詢 `pump()` 等待真實非同步載入）。
- 不新增 PDF 測試 fixture：`app/test/fixtures/sample_multi_page.pdf`（5 頁，驗證收尾雙頁）與 `sample_dual_page.pdf`（6 頁，驗證收尾單頁）已足夠覆蓋所有配對邊界情況。
- 雙頁模式下 `PdfPageInfo.pageIndex` 回報「spread 錨點頁」（該 spread 內最小的 pageIndex），不是使用者實際停留的那一頁——這與已刪除的舊 Kotlin 架構 `currentPageIndex` 語意一致，是刻意的行為定義，不是 bug。
- 本工單明確不做（不得動手實作，只需不阻塞）：劃線/備註選取矩形換算（Issue 4）、E-Ink 影像濾鏡與雙頁互斥（Issue 8）、裁切編輯模式與雙頁互斥（Issue 3）、導航熱區（Issue 8）、PDF 工具列 FAB 化/目錄/搜尋/縮圖（Issue 3/5-7）。`isDualPageEnabled()` 刻意不含舊 Kotlin 版本裡的 `cropEditModeActive` 參數，避免預先綁定尚未定案的 Issue 3 介面。

---

## File Structure

- **Create:** `app/lib/reader/pdf_spread_layout.dart`（純函式模組：`isDualPageEnabled`、`buildSpreads`、`computeSpreadLayout`、`PdfSpreadLayout` 值物件）
- **Create:** `app/test/reader/pdf_spread_layout_test.dart`（純單元測試，`test()`，不依賴 `pdfrx`/Flutter widget）
- **Create:** `app/test/reader/pdf_reader_view_dual_page_test.dart`（widget test，真實 fixture，刻意獨立於 `pdf_reader_view_test.dart`，讓「Issue 1 測試零回歸」可用 `git diff` 直接證明）
- **Modify:** `app/lib/reader/pdf_reader_view.dart`（新增 4 個建構參數、`didUpdateWidget`、`layoutPages`/`calculateCurrentPageNumber` 兩個 callback、三個導航方法的雙頁分支）
- **Modify:** `app/lib/screens/reader_screen.dart`（PDF 分支新增 4 行參數，改寫過時的「Issue 1 暫時性行為退化」註解）
- **不修改：** `app/lib/screens/pdf_settings_sheet.dart`、`app/lib/reader/dual_page_mode.dart`、`app/lib/reader/dual_page_direction.dart`、`app/lib/reader/resolved_preferences.dart`、`app/test/reader/pdf_reader_view_test.dart`（Issue 1 既有測試，diff 必須為空）

---

### Task 1：`pdf_spread_layout.dart`——雙頁啟用判斷與 spread 配對規則（純函式，無 pdfrx/Flutter 相依）

**Files:**
- Create: `app/lib/reader/pdf_spread_layout.dart`
- Create: `app/test/reader/pdf_spread_layout_test.dart`

**Interfaces:**
- Consumes: 既有 `app/lib/reader/dual_page_mode.dart`（`DualPageMode`）、`app/lib/reader/dual_page_direction.dart`（`DualPageDirection`）。
- Produces: `bool isDualPageEnabled({required DualPageMode mode, required bool isLandscape})`、`List<List<int>> buildSpreads({required int totalPages, required bool coverAlone})`。供 Task 2（`computeSpreadLayout` 呼叫 `buildSpreads`）與 Task 4（`PdfReaderView` 呼叫 `isDualPageEnabled`）使用。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_spread_layout_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_spread_layout.dart';

void main() {
  group('isDualPageEnabled', () {
    test('auto 模式：橫向啟用、直向關閉', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.auto, isLandscape: true),
        isTrue,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.auto, isLandscape: false),
        isFalse,
      );
    });

    test('always 模式：不論方向恆為啟用', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.always, isLandscape: true),
        isTrue,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.always, isLandscape: false),
        isTrue,
      );
    });

    test('never 模式：不論方向恆為停用', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.never, isLandscape: true),
        isFalse,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.never, isLandscape: false),
        isFalse,
      );
    });
  });

  group('buildSpreads', () {
    test('封面獨立時 5 頁配對為 [0][1,2][3,4]（收尾雙頁）', () {
      final spreads = buildSpreads(totalPages: 5, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('封面獨立時 6 頁配對為 [0][1,2][3,4][5]（收尾單頁）', () {
      final spreads = buildSpreads(totalPages: 6, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('封面不獨立時 5 頁配對為 [0,1][2,3][4]', () {
      final spreads = buildSpreads(totalPages: 5, coverAlone: false);
      expect(spreads, [
        [0, 1],
        [2, 3],
        [4],
      ]);
    });

    test('封面不獨立時 6 頁配對為 [0,1][2,3][4,5]', () {
      final spreads = buildSpreads(totalPages: 6, coverAlone: false);
      expect(spreads, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('1 頁與 0 頁的邊界不擲例外', () {
      expect(buildSpreads(totalPages: 1, coverAlone: true), [
        [0],
      ]);
      expect(buildSpreads(totalPages: 1, coverAlone: false), [
        [0],
      ]);
      expect(buildSpreads(totalPages: 0, coverAlone: true), <List<int>>[]);
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 編譯失敗（`pdf_spread_layout.dart` 尚不存在）。

- [ ] **Step 3: 建立 `pdf_spread_layout.dart`（本 Task 範圍：僅 `isDualPageEnabled`／`buildSpreads`）**

建立 `app/lib/reader/pdf_spread_layout.dart`（本 Task 只需要 `DualPageMode`，`dart:ui`／`DualPageDirection` 留到 Task 2 新增 `computeSpreadLayout` 時才 import，避免現在 commit 出現 `unused_import` 警告）：

```dart
import 'dual_page_mode.dart';

/// 三態雙頁模式 × 螢幕方向 → 是否實際啟用雙頁並列
/// （epic-24-pdf-engine-rebuild Issue 2）。比照已刪除的舊 Kotlin
/// `PdfReaderView.isDualPageEnabled()` 純函式設計精神重新實作。
///
/// 注意：裁切編輯模式互斥（舊版有 `cropEditModeActive` 參數）屬 Issue 3
/// 範圍，本函式刻意不含該參數——屆時新增具名參數（預設 false）即可，
/// 不影響本工單既有呼叫點。
bool isDualPageEnabled({required DualPageMode mode, required bool isLandscape}) {
  switch (mode) {
    case DualPageMode.always:
      return true;
    case DualPageMode.never:
      return false;
    case DualPageMode.auto:
      return isLandscape;
  }
}

/// 依「封面獨立顯示」規則，把 [totalPages] 頁切成一組組 spread。
///
/// 每個元素是該 spread 含的 0-indexed pageIndex，依文件順序排列（非顯示
/// 順序——RTL 的左右鏡像只發生在幾何排版階段，見 [computeSpreadLayout]）。
///
/// `coverAlone == true` ： `[[0], [1,2], [3,4], ...]`
/// `coverAlone == false`： `[[0,1], [2,3], [4,5], ...]`
/// 末尾未滿一組時該 spread 只含 1 頁（依總頁數奇偶性而定）。
List<List<int>> buildSpreads({required int totalPages, required bool coverAlone}) {
  final spreads = <List<int>>[];
  var i = 0;
  if (coverAlone && totalPages > 0) {
    spreads.add([0]);
    i = 1;
  }
  while (i < totalPages) {
    if (i + 1 < totalPages) {
      spreads.add([i, i + 1]);
      i += 2;
    } else {
      spreads.add([i]);
      i += 1;
    }
  }
  return spreads;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 12 項測試全數 PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（比照 CLAUDE.md「提交前必須乾淨」規範，每個 Task 的 commit 都須通過這道檢查，不留待後續 Task 補救）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_spread_layout.dart app/test/reader/pdf_spread_layout_test.dart
git commit -m "feat(epic-24): 新增 pdf_spread_layout 純函式模組——雙頁啟用判斷與 spread 配對規則"
```

---

### Task 2：`computeSpreadLayout`——雙頁幾何排版與 `PdfSpreadLayout` 值物件

**Files:**
- Modify: `app/lib/reader/pdf_spread_layout.dart`
- Modify: `app/test/reader/pdf_spread_layout_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `buildSpreads`。
- Produces: `class PdfSpreadLayout`（欄位：`pageRects`／`spreadRects`／`spreads`／`pageToSpread`／`documentSize`）、`PdfSpreadLayout computeSpreadLayout({required List<Size> pageSizes, required double margin, required bool coverAlone, required DualPageDirection direction})`。供 Task 3（`spreadIndexOf`/`anchorPageOf` 等方法）與 Task 4（`PdfReaderView._layoutSpreadPages` 呼叫）使用。**`pageRects[i]` 是 Issue 4（劃線/備註）日後換算選取矩形時查詢「單一頁面邊界」的唯一入口，必須與 `spreadRects`（合併後的跨頁矩形）分開暴露，不得省略。**

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_spread_layout_test.dart` 的 `import` 區塊新增 `import 'dart:ui';`，並在 `main()` 內新增一個 `group('computeSpreadLayout', ...)`（緊接在既有 `buildSpreads` group 之後）：

```dart
  group('computeSpreadLayout', () {
    List<Size> pages(int n) => List.filled(n, const Size(100, 200));

    test('LTR、封面獨立、5 頁：頁面矩形置中且 spread 內兩頁緊貼', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );

      expect(layout.spreads, [
        [0],
        [1, 2],
        [3, 4],
      ]);
      // 封面（單頁 spread）在該列內置中：x = margin + (contentW - W) / 2
      // = 8 + (200 - 100) / 2 = 58。
      expect(layout.pageRects[0], const Rect.fromLTWH(58, 8, 100, 200));
      // 第一個雙頁 spread：LTR 時文件順序在前者（page 1）在左。
      expect(layout.pageRects[1], const Rect.fromLTWH(8, 216, 100, 200));
      expect(layout.pageRects[2], const Rect.fromLTWH(108, 216, 100, 200));
      // 兩頁緊貼：右頁 left == 左頁 right。
      expect(layout.pageRects[1]!.right, layout.pageRects[2]!.left);
    });

    test('RTL、封面獨立、5 頁：spread 內左右鏡像', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.rtl,
      );

      // RTL：文件順序在後者（page 2）在左，page 1 在右——與已刪除的舊
      // Kotlin pairIndices(anchor:1, RTL) == (2, 1) 定義一致。
      expect(layout.pageRects[2], const Rect.fromLTWH(8, 216, 100, 200));
      expect(layout.pageRects[1], const Rect.fromLTWH(108, 216, 100, 200));
    });

    test('spreadRects 寬度全部一致，等於文件內容寬度（翻頁縮放不跳動）', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      final contentWidth = layout.documentSize.width - 8 * 2;
      for (final rect in layout.spreadRects) {
        expect(rect.width, contentWidth,
            reason: '封面單頁 spread 也必須與雙頁 spread 同寬，翻頁時頁面'
                '視覺大小才不會跳動');
      }
    });

    test('spreadRects 垂直依序遞增、彼此不重疊，且與 documentSize 一致', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(6),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      for (var i = 0; i < layout.spreadRects.length - 1; i++) {
        expect(
          layout.spreadRects[i].bottom + 8,
          layout.spreadRects[i + 1].top,
        );
      }
      expect(
        layout.documentSize.height,
        layout.spreadRects.last.bottom + 8,
      );
    });

    test('單頁 spread（封面）的頁面在該列內水平置中', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(
        layout.pageRects[0]!.center.dx,
        layout.spreadRects[0].center.dx,
      );
    });

    test('pageRects 逐頁可查、尺寸等於原始頁面尺寸（Issue 4 相容性契約）', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(layout.pageRects.length, 5);
      for (final rect in layout.pageRects) {
        expect(rect!.size, const Size(100, 200));
      }
      // pageRects 是「單一頁面」邊界，spreadRects 是合併後的跨頁邊界，
      // 兩者不應相等——這是 Issue 4 換算劃線選取矩形時的關鍵區分。
      expect(layout.pageRects[1], isNot(layout.spreadRects[1]));
    });

    test('0 頁與 1 頁的邊界不擲例外', () {
      final empty = computeSpreadLayout(
        pageSizes: const [],
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(empty.pageRects, isEmpty);
      expect(empty.spreadRects, isEmpty);
      expect(empty.spreads, isEmpty);
      expect(empty.documentSize, const Size(16, 8));

      final single = computeSpreadLayout(
        pageSizes: pages(1),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(single.spreads, [
        [0],
      ]);
      expect(single.pageRects.length, 1);
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 編譯失敗（`computeSpreadLayout`／`PdfSpreadLayout` 尚不存在）。

- [ ] **Step 3: 在 `pdf_spread_layout.dart` 新增 `PdfSpreadLayout` 與 `computeSpreadLayout`**

在 `app/lib/reader/pdf_spread_layout.dart` 頂部的 `import 'dual_page_mode.dart';` 之前新增（本 Task 起才用到 `Rect`/`Size`/`DualPageDirection`）：

```dart
import 'dart:ui' show Rect, Size;

import 'dual_page_direction.dart';
```

在 `buildSpreads` 函式之後追加：

```dart
/// 雙頁版面的完整計算結果。純函式輸出，不持有任何 pdfrx/Flutter widget
/// 狀態。
class PdfSpreadLayout {
  const PdfSpreadLayout({
    required this.pageRects,
    required this.spreadRects,
    required this.spreads,
    required this.pageToSpread,
    required this.documentSize,
  });

  /// 逐「單一頁面」的文件座標矩形，index == 0-indexed pageIndex，長度
  /// == totalPages。矩形大小即該頁原始尺寸（不含 margin）。
  ///
  /// 【Issue 4 相容性契約】劃線/選取要換算「相對單一頁面本身邊界」的
  /// 百分比矩形時，一律查這裡，不要用 [spreadRects]（那是合併後的跨頁
  /// 矩形）。見 spec.md「劃線/備註/選取機制」。
  final List<Rect> pageRects;

  /// 逐 spread 的「導航目標矩形」，index == spreadIndex。寬度一律等於
  /// 文件內容寬度（`documentSize.width - margin * 2`），讓單頁 spread
  /// （封面、收尾單頁）與雙頁 spread 的 fit 縮放比例一致，翻頁時頁面
  /// 視覺大小不跳動。
  final List<Rect> spreadRects;

  /// [buildSpreads] 的結果，供測試與除錯直接斷言配對。
  final List<List<int>> spreads;

  /// pageIndex → spreadIndex 的 O(1) 反查表，長度 == totalPages。
  final List<int> pageToSpread;

  final Size documentSize;

  int get spreadCount => spreads.length;
}

/// 計算雙頁並列版面。純函式：輸入只有頁面尺寸與設定，無 pdfrx 相依。
///
/// [pageSizes] 各頁原始尺寸（依文件順序）。[margin] 取自
/// `PdfViewerParams.margin`（pdfrx 預設 8.0）。
PdfSpreadLayout computeSpreadLayout({
  required List<Size> pageSizes,
  required double margin,
  required bool coverAlone,
  required DualPageDirection direction,
}) {
  final totalPages = pageSizes.length;
  final spreads = buildSpreads(totalPages: totalPages, coverAlone: coverAlone);

  if (totalPages == 0) {
    return PdfSpreadLayout(
      pageRects: const [],
      spreadRects: const [],
      spreads: const [],
      pageToSpread: const [],
      documentSize: Size(margin * 2, margin),
    );
  }

  // 每個 spread 的內容寬度（該 spread 內各頁寬度總和）與內容高度（該
  // spread 內最高頁面的高度）。
  final rowWidths = <double>[];
  final rowHeights = <double>[];
  for (final spread in spreads) {
    var w = 0.0;
    var h = 0.0;
    for (final p in spread) {
      w += pageSizes[p].width;
      if (pageSizes[p].height > h) h = pageSizes[p].height;
    }
    rowWidths.add(w);
    rowHeights.add(h);
  }
  final contentWidth = rowWidths.fold<double>(0, (a, b) => a > b ? a : b);
  final docWidth = contentWidth + margin * 2;

  final pageRects = List<Rect?>.filled(totalPages, null);
  final spreadRects = <Rect>[];
  final pageToSpread = List<int>.filled(totalPages, 0);

  var y = margin;
  for (var s = 0; s < spreads.length; s++) {
    final spread = spreads[s];
    // RTL：文件順序在後者的頁面顯示在左側，鏡像已刪除的舊 Kotlin
    // pairIndices(anchor, RTL) == (anchor+1, anchor) 定義。
    final Iterable<int> order =
        direction == DualPageDirection.rtl ? spread.reversed : spread;
    var x = margin + (contentWidth - rowWidths[s]) / 2;
    for (final p in order) {
      final size = pageSizes[p];
      final rect = Rect.fromLTWH(
        x,
        y + (rowHeights[s] - size.height) / 2,
        size.width,
        size.height,
      );
      pageRects[p] = rect;
      pageToSpread[p] = s;
      x += size.width; // spread 內兩頁緊貼，無 gutter。
    }
    spreadRects.add(Rect.fromLTWH(margin, y, contentWidth, rowHeights[s]));
    y += rowHeights[s] + margin;
  }

  return PdfSpreadLayout(
    pageRects: pageRects.cast<Rect>(),
    spreadRects: spreadRects,
    spreads: spreads,
    pageToSpread: pageToSpread,
    documentSize: Size(docWidth, y),
  );
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 全部 19 項測試（Task 1 的 12 項＋本 Task 的 7 項）PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（Task 1 遺留的 unused import 警告此時應已消失，因為 `computeSpreadLayout` 用到了 `Rect`/`Size`/`DualPageDirection`）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_spread_layout.dart app/test/reader/pdf_spread_layout_test.dart
git commit -m "feat(epic-24): pdf_spread_layout 新增 computeSpreadLayout 雙頁幾何排版"
```

---

### Task 3：spread 導航查詢方法——`spreadIndexOf`／`anchorPageOf`／`nextSpreadAnchor`／`previousSpreadAnchor`

**Files:**
- Modify: `app/lib/reader/pdf_spread_layout.dart`
- Modify: `app/test/reader/pdf_spread_layout_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `PdfSpreadLayout`。
- Produces: `PdfSpreadLayout` 新增 4 個方法：`int spreadIndexOf(int pageIndex)`、`int anchorPageOf(int spreadIndex)`、`int? nextSpreadAnchor(int fromPageIndex)`、`int? previousSpreadAnchor(int fromPageIndex)`。供 Task 6（`PdfReaderView` 三個導航方法的雙頁分支）使用——取代已刪除的舊 Kotlin `nextPageStep`/`previousPageStep`，改以「spread 序號 ±1 再取錨點」表達，對「目前頁不是錨點頁」（使用者自由捲動停在右頁）也正確。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_spread_layout_test.dart` 新增一個 `group('PdfSpreadLayout 導航查詢', ...)`（緊接在 `computeSpreadLayout` group 之後）：

```dart
  group('PdfSpreadLayout 導航查詢', () {
    // 5 頁、封面獨立：spreads == [[0],[1,2],[3,4]]，pageToSpread ==
    // [0,1,1,2,2]。
    PdfSpreadLayout layout5CoverAlone() => computeSpreadLayout(
          pageSizes: List.filled(5, const Size(100, 200)),
          margin: 8,
          coverAlone: true,
          direction: DualPageDirection.ltr,
        );

    // 6 頁、封面不獨立：spreads == [[0,1],[2,3],[4,5]]。
    PdfSpreadLayout layout6NoCover() => computeSpreadLayout(
          pageSizes: List.filled(6, const Size(100, 200)),
          margin: 8,
          coverAlone: false,
          direction: DualPageDirection.ltr,
        );

    test('spreadIndexOf／anchorPageOf 往返一致', () {
      final layout = layout5CoverAlone();
      expect(layout.spreadIndexOf(0), 0);
      expect(layout.spreadIndexOf(1), 1);
      expect(layout.spreadIndexOf(2), 1); // 與 page 1 同一 spread。
      expect(layout.spreadIndexOf(3), 2);
      expect(layout.spreadIndexOf(4), 2);
      expect(layout.anchorPageOf(0), 0);
      expect(layout.anchorPageOf(1), 1);
      expect(layout.anchorPageOf(2), 3);
    });

    test('封面獨立時 nextSpreadAnchor 的步進與邊界', () {
      final layout = layout5CoverAlone();
      expect(layout.nextSpreadAnchor(0), 1); // 封面 → 步進 1。
      expect(layout.nextSpreadAnchor(1), 3); // spread [1,2] → [3,4]，步進 2。
      expect(layout.nextSpreadAnchor(2), 3); // 從右頁(2)出發也對。
      expect(layout.nextSpreadAnchor(3), isNull); // 已在最後一個 spread。
      expect(layout.nextSpreadAnchor(4), isNull);
    });

    test('封面獨立時 previousSpreadAnchor 的步進與邊界', () {
      final layout = layout5CoverAlone();
      expect(layout.previousSpreadAnchor(1), 0);
      expect(layout.previousSpreadAnchor(2), 0);
      expect(layout.previousSpreadAnchor(3), 1);
      expect(layout.previousSpreadAnchor(0), isNull); // 已在封面。
    });

    test('封面不獨立時步進恆為 2', () {
      final layout = layout6NoCover();
      expect(layout.nextSpreadAnchor(0), 2);
      expect(layout.nextSpreadAnchor(2), 4);
      expect(layout.nextSpreadAnchor(4), isNull);
      expect(layout.previousSpreadAnchor(4), 2);
      expect(layout.previousSpreadAnchor(2), 0);
      expect(layout.previousSpreadAnchor(0), isNull);
    });

    test('spreadIndexOf 對超界 pageIndex 安全 clamp，不擲例外', () {
      final layout = layout5CoverAlone();
      expect(() => layout.spreadIndexOf(-1), returnsNormally);
      expect(() => layout.spreadIndexOf(999), returnsNormally);
      expect(layout.spreadIndexOf(-1), layout.spreadIndexOf(0));
      expect(layout.spreadIndexOf(999), layout.spreadIndexOf(4));
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 編譯失敗（4 個新方法尚不存在）。

- [ ] **Step 3: 在 `PdfSpreadLayout` 新增 4 個方法**

在 `app/lib/reader/pdf_spread_layout.dart` 的 `PdfSpreadLayout` 類別內、`int get spreadCount => spreads.length;` 之後新增：

```dart
  /// 0-indexed pageIndex → 所屬 spreadIndex。超界時 clamp 到合法範圍
  /// （呼叫端不需要自行防呆）。
  int spreadIndexOf(int pageIndex) {
    if (pageToSpread.isEmpty) return 0;
    final clamped = pageIndex.clamp(0, pageToSpread.length - 1);
    return pageToSpread[clamped];
  }

  /// spreadIndex → 該 spread 的「錨點頁」= 組內最小的 pageIndex。對外
  /// 回報的目前頁碼、翻頁步進基準皆用錨點頁（沿用已刪除的舊 Kotlin
  /// currentPageIndex 語意）。
  int anchorPageOf(int spreadIndex) {
    final clamped = spreadIndex.clamp(0, spreads.length - 1);
    return spreads[clamped].first;
  }

  /// 下一個 spread 的錨點頁 index；已在最後一個 spread 時回傳 null。
  int? nextSpreadAnchor(int fromPageIndex) {
    final current = spreadIndexOf(fromPageIndex);
    if (current >= spreads.length - 1) return null;
    return anchorPageOf(current + 1);
  }

  /// 上一個 spread 的錨點頁 index；已在第一個 spread 時回傳 null。
  int? previousSpreadAnchor(int fromPageIndex) {
    final current = spreadIndexOf(fromPageIndex);
    if (current <= 0) return null;
    return anchorPageOf(current - 1);
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_spread_layout_test.dart`
Expected: 全部 24 項測試（Task 1 的 12 項＋Task 2 的 7 項＋本 Task 的 5 項）PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_spread_layout.dart app/test/reader/pdf_spread_layout_test.dart
git commit -m "feat(epic-24): PdfSpreadLayout 新增 spread 導航查詢方法"
```

---

### Task 4：`PdfReaderView` 新增雙頁建構參數，接上 `layoutPages`（先驗證單頁模式零回歸）

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Create: `app/test/reader/pdf_reader_view_dual_page_test.dart`

**Interfaces:**
- Consumes: Task 1-3 的 `pdf_spread_layout.dart` 全部匯出。
- Produces: `PdfReaderView` 新增建構參數 `dualPageMode`（預設 `DualPageMode.never`）、`dualPageCoverAlone`（預設 `true`）、`dualPageDirection`（預設 `DualPageDirection.rtl`）、`isLandscape`（預設 `false`）。`_PdfReaderViewState` 新增 `_dualPageEnabled` getter 與 `_layoutSpreadPages` callback。供 Task 5-7 擴充、Task 8（`reader_screen.dart`）消費。

**本 Task 刻意的測試順序**：先寫「不傳新參數時行為與 Issue 1 完全相同」的測試（零回歸基準），再寫「傳入雙頁參數時 `layoutPages` 真的被呼叫、且產出的版面與 `computeSpreadLayout` 一致」的測試。**尚不要求 `nextPage`/`previousPage` 的雙頁步進行為**（那是 Task 6 的範圍）——本 Task 只驗證版面計算本身接上了。

- [ ] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_dual_page_test.dart`（樣板沿用 Issue 1 既有的 `pdf_reader_view_test.dart`）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

void main() {
  setUp(() => pdfrxInitialize());

  /// 等待 pdfrx 真正完成非同步載入（比照 pdf_reader_view_test.dart 既有
  /// 寫法），最多輪詢 30 次、每次 100ms。
  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('不傳雙頁參數時，行為與 Issue 1 完全相同（零回歸基準）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    PdfReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('dualPageMode: never 時，行為與不傳參數完全相同',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.never,
          isLandscape: true, // never 模式下方向不應影響結果。
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    expect(lastPageInfo?.pageIndex, 0);
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1); // 步進 1，非雙頁步進。
  });

  testWidgets('dualPageMode: always 時，開書後即套用雙頁版面（錨點頁仍為 0）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // 封面獨立時第 0 頁本身即為一個完整 spread，錨點頁仍是 0——
    // 與單頁模式的初始狀態在「開書即在第 0 頁」這件事上一致，
    // 差異要到 nextPage（Task 6）才會顯現。
    expect(lastPageInfo?.pageIndex, 0);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 編譯失敗（`PdfReaderView` 建構子尚無 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 具名參數）。

- [ ] **Step 3: `PdfReaderView` 新增建構參數**

在 `app/lib/reader/pdf_reader_view.dart` 頂部新增 import：

```dart
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'pdf_spread_layout.dart';
```

把 `class PdfReaderView` 的欄位與建構子改為：

```dart
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final int? initialPageIndex;
  final ValueChanged<PdfPageInfo>? onPageChanged;

  // ── epic-24-pdf-engine-rebuild Issue 2 新增 ──
  /// 三態雙頁模式。**widget 層預設刻意為 [DualPageMode.never]**（不是
  /// 產品預設值 auto）：未傳此參數的既有呼叫端（Issue 1 既有測試）行為
  /// 與 Issue 1 逐位元相同。產品預設 auto 由 ResolvedPreferences 提供，
  /// 經 reader_screen.dart 明確傳入（見 Task 8）。
  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;
  /// 螢幕是否為橫向。由 ReaderScreen 既有的 isLandscape 傳入（與 EPUB
  /// FXL 分支同源），本 widget 不自行偵測方向。
  final bool isLandscape;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.initialPageIndex,
    this.onPageChanged,
    this.dualPageMode = DualPageMode.never,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.rtl,
    this.isLandscape = false,
  });
```

（靜態方法 `jumpToPage`/`nextPage`/`previousPage`/`refreshAnnotations` 簽章不動。）

- [ ] **Step 4: `_PdfReaderViewState` 新增雙頁版面欄位與 `layoutPages` callback**

在 `_PdfReaderViewState` 的欄位宣告區（`String? _contentUriTmpPath;` 之後）新增：

```dart
  /// 最近一次雙頁版面計算結果，由 [_layoutSpreadPages] 在 build 期間寫入
  /// （純快取，不 setState）。單頁模式下為 null。刻意不改用
  /// `PdfViewerController.layout`：該 getter 在版面尚未建立時會擲
  /// null-check error，且只回傳合併後的頁面矩形，拿不到 spread 分組
  /// 資訊。
  PdfSpreadLayout? _spreadLayout;

  /// computeSpreadLayout 的 memo 鍵——**必須涵蓋所有會影響版面計算結果的
  /// 輸入**（頁數、封面獨立、配對方向、margin），不能只用頁數：若只用頁
  /// 數當鍵，快取正確性就會完全依賴呼叫端（Task 7 的 `didUpdateWidget`）
  /// 手動清空快取這個外部協調，屬脆弱耦合——日後若有人修改
  /// `didUpdateWidget` 的變更偵測邏輯卻忘記同步處理快取，會靜默沿用過期
  /// 版面（例如翻頁座標與實際畫面不符）。用完整輸入當鍵，讓
  /// `_layoutSpreadPages` 自身就具備正確性，不依賴外部協調。
  ///
  /// 輸入未變時直接回傳同一個 `PdfPageLayout` 實例，讓 pdfrx 的版面變更
  /// 比對可以走 `identical()` 快速路徑。
  ({int pageCount, bool coverAlone, DualPageDirection direction, double margin})?
      _cachedLayoutKey;
  PdfPageLayout? _cachedPdfLayout;

  bool get _dualPageEnabled => isDualPageEnabled(
        mode: widget.dualPageMode,
        isLandscape: widget.isLandscape,
      );
```

在 `_handlePageChanged` 之後新增 `_layoutSpreadPages`：

```dart
  /// PdfPageLayoutFunction 實作。以 instance method tear-off 形式傳給
  /// PdfViewerParams（見 build()）——同一個 State 的 tear-off 具備穩定的
  /// == 語意；設定值（coverAlone/direction）在呼叫當下讀 widget.xxx，
  /// 設定變更會反映到新算出的 PdfPageLayout 上。
  PdfPageLayout _layoutSpreadPages(List<PdfPage> pages, PdfViewerParams params) {
    final key = (
      pageCount: pages.length,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
      margin: params.margin,
    );
    if (_cachedLayoutKey == key && _cachedPdfLayout != null) {
      return _cachedPdfLayout!;
    }
    final layout = computeSpreadLayout(
      pageSizes: [for (final p in pages) Size(p.width, p.height)],
      margin: params.margin,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
    );
    _spreadLayout = layout;
    _cachedLayoutKey = key;
    return _cachedPdfLayout = PdfPageLayout(
      pageLayouts: layout.pageRects, // pdfrx 契約：index i 對應第 i+1 頁。
      documentSize: layout.documentSize,
    );
  }
```

- [ ] **Step 5: `build()` 依 `_dualPageEnabled` 傳入或省略 `layoutPages`**

把 `build()` 內的 `params: PdfViewerParams(...)` 改為：

```dart
      params: PdfViewerParams(
        // 單頁模式一律傳 null，沿用 pdfrx 內建版面推算——PdfViewerParams
        // 與 Issue 1 逐欄位相同，這是零回歸的構造性保證（不是靠測試
        // 事後證明）。
        layoutPages: _dualPageEnabled ? _layoutSpreadPages : null,
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

（`calculateCurrentPageNumber` 留待 Task 5 加入；本 Task 只驗證 `layoutPages` 本身接上，`onViewerReady`/`_handlePageChanged` 暫不改動。）

- [ ] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 3 項測試 PASS（第 3 項目前只斷言開書後 `pageIndex == 0`，尚未涉及雙頁步進，Task 6 才會補上）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: Issue 1 既有的 5 項測試全數 PASS，**且本檔案 `git diff` 為空**（零回歸的直接證據）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_dual_page_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增雙頁建構參數，接上 layoutPages"
```

---

### Task 5：`calculateCurrentPageNumber` 覆寫——雙頁模式下頁碼恆為 spread 錨點

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_dual_page_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `_spreadLayout`。
- Produces: `_PdfReaderViewState._calculateSpreadAnchorPageNumber`。供 Task 6（`_goToSpread` 導航後，頁碼靠這個 callback 推導，不靠 `goToPage` 內建行為）使用。

**為什麼需要這個 Task（設計理由，寫進 commit/PR 說明）**：pdfrx 的 `_guessCurrentPageNumber()` 內部判斷是否切換成「捲動百分比模式」的條件是 `fullyVisiblePages.length >= 3 || !isSimple`（`pdf_viewer.dart:1062-1134`，OR 關係，兩個分支任一成立即觸發）。雙頁版面因為同一個 spread 內兩頁在主捲動軸上的座標區間重疊，會被 `_isSimpleLayout()` 判定為非簡單版面（`!isSimple == true`），**不需要等到 3 頁完全可見，任何一個雙頁 spread 進入畫面就會立即觸發**這個分支。切換後 pdfrx 回報的目前頁可能是右頁（非錨點頁）而非左頁，導致 UI 頁碼顯示與 `_nextPage`/`_previousPage` 的 spread 計算基準不一致，因此需要 `calculateCurrentPageNumber` 覆寫，讓雙頁模式下的目前頁定義由我們自己掌控。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_dual_page_test.dart` 新增（`main()` 內既有測試之後）：

```dart
  testWidgets('雙頁模式下，跳到 spread 的右頁後，頁碼回報 spread 錨點頁',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // jumpToPage(2)：page 2 屬於 spread [1,2]，錨點頁為 1。
    PdfReaderView.jumpToPage(key, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '回報 spread 錨點頁，不是 2');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart --plain-name "spread 錨點頁"`
Expected: FAIL（目前 `_jumpToPage` 仍呼叫 Issue 1 的 `goToPage(pageNumber: pageIndex + 1)`，會直接把頁碼設為 2，非錨點頁 1；本 Step 只是先把「目前頁碼推算」的覆寫寫出來，下個 Task 才會讓 `_jumpToPage` 真正定位到整個 spread——這個測試要到 Task 6 完成才會轉綠，本 Task 先確認「尚未實作」的失敗原因如預期）。

- [ ] **Step 3: 新增 `_calculateSpreadAnchorPageNumber`**

在 `_PdfReaderViewState` 內、`_layoutSpreadPages` 之後新增：

```dart
  /// 覆寫 pdfrx 的目前頁碼推算：雙頁模式下一律回報「可視區域內佔比最大
  /// 的那一頁所屬 spread 的錨點頁」，而非該頁本身。這讓
  /// controller.pageNumber 在雙頁模式下恆為 spread 錨點，於是
  /// onPageChanged 回報的 PdfPageInfo.pageIndex、閱讀位置持久化、
  /// _nextPage/_previousPage 的步進基準三者共用同一個定義（沿用已刪除
  /// 的舊 Kotlin currentPageIndex 語意）。
  ///
  /// 回傳為 pdfrx 慣例的 1-indexed pageNumber。
  int? _calculateSpreadAnchorPageNumber(
    Rect visibleRect,
    List<Rect> pageRects,
    PdfViewerController controller,
  ) {
    final layout = _spreadLayout;
    if (layout == null) return controller.pageNumber;

    var bestIndex = -1;
    var bestArea = 0.0;
    for (var i = 0; i < pageRects.length; i++) {
      final inter = pageRects[i].intersect(visibleRect);
      if (inter.isEmpty) continue;
      final area = inter.width * inter.height;
      // 嚴格 > 比較：面積相等（平手）時保留先遍歷到的較小 pageIndex，
      // 即該 spread 的錨點頁——這是刻意利用「較小 index 較早被遍歷」
      // 這件事維持錨點頁語意，不是巧合，不要改成 >=（那會讓平手時保留
      // 後遍歷到的較大 index，可能回報非錨點頁）。
      if (area > bestArea) {
        bestArea = area;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) return controller.pageNumber; // 完全捲出版面外。
    return layout.anchorPageOf(layout.spreadIndexOf(bestIndex)) + 1;
  }
```

在 `build()` 的 `PdfViewerParams(...)` 內、`layoutPages` 之後新增：

```dart
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
```

- [ ] **Step 4: 執行測試，確認符合預期（可能仍未轉綠，見下方說明）**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart --plain-name "spread 錨點頁"`
Expected: 仍 FAIL，且失敗原因須為 `Expected: 1 Actual: 2`（`lastPageInfo?.pageIndex` 斷言不符）——`_jumpToPage` 尚未改用 spread 導航（Task 6），`goToPage` 內部會直接 `_setCurrentPageNumber(2)` 覆蓋掉本 Task 的推算結果，所以頁碼仍是 2 而非錨點頁 1。**這是預期中的中間狀態，不是本 Task 的錯誤**，本 Step 存在是為了在 Task 6 完成後有一個明確的「由紅轉綠」對照點；若失敗原因不是這個斷言不符（例如變成例外或編譯錯誤），代表 Step 3 的實作有誤，須先排查。

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 除上述那項外，其餘既有測試（Task 4 的 3 項）全數 PASS。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_dual_page_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增 calculateCurrentPageNumber 覆寫（spread 錨點頁）"
```

---

### Task 6：三個導航方法的雙頁分支——`_goToSpread`／`_jumpToPage`／`_nextPage`／`_previousPage`

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_dual_page_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `PdfSpreadLayout.spreadIndexOf`/`anchorPageOf`/`nextSpreadAnchor`/`previousSpreadAnchor`，Task 5 的 `_calculateSpreadAnchorPageNumber`。
- Produces: `_PdfReaderViewState._goToSpread`、`_activeSpreadLayout` getter；`_jumpToPage`/`_nextPage`/`_previousPage` 三個既有方法擴充雙頁分支。這是本工單「使用者實際感受到雙頁翻頁」的核心 Task，完成後 Task 5 的失敗測試應轉綠。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_dual_page_test.dart` 新增（`main()` 內既有測試之後；`sample_dual_page.pdf` 已在 `pubspec.yaml` 宣告為 asset，供 6 頁情境使用）：

```dart
  testWidgets('always + 封面獨立：翻頁以 spread 為單位，封面步進 1、之後步進 2',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf', // 5 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          isLandscape: false, // 證明 always 模式不看方向。
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    // 已在最後一個 spread，再次 nextPage 應安全忽略。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('always + 封面獨立：previousPage 對稱回到封面', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('always + 封面不獨立：步進恆為 2（6 頁 fixture）', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);
    expect(lastPageInfo?.totalPages, 6);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 2);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('auto + 直向：等同單頁模式，步進為 1', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.auto,
          isLandscape: false,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);
  });

  testWidgets('auto + 橫向：等同 always，步進與雙頁一致', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          dualPageMode: DualPageMode.auto,
          dualPageCoverAlone: true,
          isLandscape: true,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('總頁數為偶數且封面獨立時，最後一頁單獨成為一個 spread',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    // spreads == [[0],[1,2],[3,4],[5]]，第 5 頁單獨成一組。
    PdfReaderView.jumpToPage(key, 5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 5);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 5, reason: '已在最後一個 spread');

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('RTL 與 LTR 產生鏡像版面，但頁碼回報序列完全相同', (tester) async {
    Future<List<int?>> runSequence(DualPageDirection direction) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: true,
            dualPageDirection: direction,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      final sequence = <int?>[lastPageInfo?.pageIndex];
      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      sequence.add(lastPageInfo?.pageIndex);
      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      sequence.add(lastPageInfo?.pageIndex);
      return sequence;
    }

    final rtlSequence = await runSequence(DualPageDirection.rtl);
    await tester.pumpWidget(const SizedBox.shrink()); // 清空重來。
    final ltrSequence = await runSequence(DualPageDirection.ltr);

    expect(rtlSequence, [0, 1, 3]);
    expect(ltrSequence, [0, 1, 3]);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 新增的 7 項測試 FAIL（`_nextPage`/`_previousPage`/`_jumpToPage` 尚未有雙頁分支，仍是 Issue 1 的單頁步進），Task 5 遺留的「跳到 spread 的右頁後回報錨點頁」測試同樣仍 FAIL。

- [ ] **Step 3: 新增 `_goToSpread` 與 `_activeSpreadLayout`**

（`unawaited(...)` 所需的 `import 'dart:async';` 已存在於 `pdf_reader_view.dart` 檔案頂部——Issue 1 的 `_cleanupTmpFile` 就是靠這個 import 用 `unawaited`，本 Task 不需要新增任何 import。）

在 `_PdfReaderViewState` 內、`_calculateSpreadAnchorPageNumber` 之後新增：

```dart
  /// 雙頁模式下的統一導航：把整個 spread 帶入視野。用 goToArea 而非
  /// goToPage：goToPage 只 fit 單一頁面矩形（會把 spread 的另一半推出
  /// 畫面），且其內部會直接 _setCurrentPageNumber(目標頁)，繞過
  /// calculateCurrentPageNumber，造成頁碼有兩個來源。goToArea 不設定
  /// 頁碼，頁碼一律由 _calculateSpreadAnchorPageNumber 於動畫過程中
  /// 推導，維持單一事實來源。
  void _goToSpread(int spreadIndex, PdfSpreadLayout layout) {
    if (spreadIndex < 0 || spreadIndex >= layout.spreadCount) return;
    unawaited(_controller.goToArea(
      rect: layout.spreadRects[spreadIndex],
      anchor: PdfPageAnchor.all,
    ));
  }

  /// 雙頁啟用且版面已算好時回傳版面，否則回傳 null（→ 導航方法走
  /// Issue 1 原路徑）。
  PdfSpreadLayout? get _activeSpreadLayout =>
      _dualPageEnabled ? _spreadLayout : null;
```

- [ ] **Step 4: 三個導航方法擴充雙頁分支**

把 `_jumpToPage`/`_nextPage`/`_previousPage` 改為：

```dart
  void _jumpToPage(int pageIndex) {
    if (!_controller.isReady) return;
    if (pageIndex < 0 || pageIndex >= _controller.pageCount) return;
    final layout = _activeSpreadLayout;
    if (layout == null) {
      _controller.goToPage(pageNumber: pageIndex + 1); // Issue 1 原邏輯。
      return;
    }
    _goToSpread(layout.spreadIndexOf(pageIndex), layout);
  }

  void _nextPage() {
    if (!_controller.isReady) return;
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current >= _controller.pageCount) return;
      _controller.goToPage(pageNumber: current + 1);
      return;
    }
    final currentIndex = (_controller.pageNumber ?? 1) - 1;
    final next = layout.nextSpreadAnchor(currentIndex);
    if (next == null) return; // 已在最後一個 spread。
    _goToSpread(layout.spreadIndexOf(next), layout);
  }

  void _previousPage() {
    if (!_controller.isReady) return;
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current <= 1) return;
      _controller.goToPage(pageNumber: current - 1);
      return;
    }
    final currentIndex = (_controller.pageNumber ?? 1) - 1;
    final prev = layout.previousSpreadAnchor(currentIndex);
    if (prev == null) return; // 已在封面 spread。
    _goToSpread(layout.spreadIndexOf(prev), layout);
  }
```

（`_handlePageChanged` 不改：雙頁模式下它會自動回報錨點頁，因為來源 `controller.pageNumber` 已被 Task 5 的覆寫定義成錨點。）

- [ ] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全部測試 PASS，含 Task 5 遺留的「跳到 spread 的右頁後回報錨點頁」（現在應轉綠）。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: Issue 1 既有 5 項測試全數 PASS，檔案 `git diff` 仍為空。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_dual_page_test.dart
git commit -m "feat(epic-24): PdfReaderView 三個導航方法新增雙頁 spread 分支"
```

---

### Task 7：執行期切換雙頁設定——`didUpdateWidget` 重新對齊錨點

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_dual_page_test.dart`

**Interfaces:**
- Consumes: Task 4-6 全部。
- Produces: `_PdfReaderViewState.didUpdateWidget` 覆寫。涵蓋使用者在閱讀中途變更雙頁設定（設定面板調整）或裝置旋轉（`auto` 模式）兩種情境，並對「文件仍在非同步開啟中就觸發設定變更」（`_controller.isReady == false`）與「relayout 尚未完成就搶先 reanchor」兩種時序風險有明確防呆（見 Step 3 註解）。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/pdf_reader_view_dual_page_test.dart` 新增：

```dart
  testWidgets('執行期由 always 切到 never，版面與步進回到單頁', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(DualPageMode mode) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: mode,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(DualPageMode.always));
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    await tester.pumpWidget(buildView(DualPageMode.never));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4, reason: '切回單頁後步進應為 1');
  });

  testWidgets('auto 模式下執行期橫直向切換改變雙頁啟用狀態', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool isLandscape) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.auto,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            isLandscape: isLandscape,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(true));
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    await tester.pumpWidget(buildView(false)); // 轉為直向。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 2, reason: '直向後步進應為 1（單頁）');
  });

  testWidgets('執行期切換 dualPageCoverAlone，翻頁配對規則正確反映新設定',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool coverAlone) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: coverAlone,
            dualPageDirection: DualPageDirection.ltr,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(true));
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: 'coverAlone=true，封面步進 1');

    await tester.pumpWidget(buildView(false)); // 執行期關閉封面獨立。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      lastPageInfo?.pageIndex,
      2,
      reason: 'coverAlone=false 後 spreads 變為 [0,1][2,3][4,5]，'
          '從錨點頁 0 出發下一步應到錨點頁 2',
    );
  });

  // 【review-issue-2 訂正】上面 expect 的預期值與理由，本計畫初版誤寫為
  // 3／「從錨點頁 1 出發下一步應到錨點頁 3」。實際手算：coverAlone 切換
  // 當下 `_jumpToPage(1)` 落在新版面（[0,1][2,3][4,5]）下 spreadIndexOf(1)
  // 所屬 spread [0,1] 的錨點頁 0，之後 nextPage() 才到錨點 2——即使代入
  // 原計畫「從錨點頁 1 出發」也會算出 2 而非 3。實作已依正確算式提交，
  // 此處僅訂正計畫文件本身的推算誤差，不代表實作偏離規格。

  testWidgets('執行期切換 dualPageDirection，錨點頁步進序列不受影響（僅幾何鏡像）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(DualPageDirection direction) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: true,
            dualPageDirection: direction,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(DualPageDirection.rtl));
    await waitRendered(tester, () => renderedCount);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    await tester.pumpWidget(buildView(DualPageDirection.ltr)); // 執行期切換方向。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      lastPageInfo?.pageIndex,
      3,
      reason: '方向切換只影響左右鏡像幾何，錨點頁步進序列不變',
    );
  });

  testWidgets('文件載入完成前變更雙頁設定不會當機（isReady == false 防呆）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool isLandscape) => MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.auto,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            isLandscape: isLandscape,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (_) {},
          ),
        );

    await tester.pumpWidget(buildView(true));
    // 刻意不呼叫 waitRendered：文件仍在非同步開啟中（_controller.isReady
    // 尚為 false，_document 仍是 null）時就觸發 didUpdateWidget，重現
    // Critical #1 的當機路徑。
    await tester.pumpWidget(buildView(false));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // 讓文件真正開完，確認後續行為仍正常運作（非卡死狀態）。
    await waitRendered(tester, () => renderedCount);
    expect(renderedCount, 1);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart --plain-name "執行期"`
Expected: FAIL 或行為不穩定——目前沒有 `didUpdateWidget`，`_spreadLayout` 在設定變更後不會清空/重算，`_dualPageEnabled` 雖然會依新 `widget` 值即時反映（是 getter），但 `_activeSpreadLayout` 可能仍持有切換前的舊版面物件，且沒有主動把游標對齊回單頁模式下正確的頁碼。

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart --plain-name "isReady == false"`
Expected: FAIL——目前 `_controller.invalidate()` 尚不存在（`didUpdateWidget` 本身還沒實作），這個測試會在後續 Step 3 實作 `didUpdateWidget` 後才真正有意義；本 Step 先確認測試檔案本身編譯成功、且此測試在缺少 `didUpdateWidget` 的情況下不會意外通過。

- [ ] **Step 3: 新增 `didUpdateWidget`**

在 `_PdfReaderViewState` 內、`dispose()` 之前新增：

```dart
  /// 待版面重算後要重新對齊的 spread 錨點頁（0-indexed）。
  int? _pendingReanchorPageIndex;

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.dualPageMode != widget.dualPageMode ||
        oldWidget.dualPageCoverAlone != widget.dualPageCoverAlone ||
        oldWidget.dualPageDirection != widget.dualPageDirection ||
        oldWidget.isLandscape != widget.isLandscape;
    if (!changed) return;

    // 切換前的錨點頁必須先記下來：relayout 後 pdfrx 會依自己的邏輯推一
    // 個目前頁，未必落在原本的 spread 上。
    final anchorBefore = _controller.isReady
        ? (_controller.pageNumber ?? 1) - 1
        : (widget.initialPageIndex ?? 0);

    if (!_dualPageEnabled) {
      _spreadLayout = null; // 停用雙頁後不得再用舊的 spread 矩形導航。
    }
    _cachedLayoutKey = null;
    _cachedPdfLayout = null;
    _pendingReanchorPageIndex = anchorBefore;

    // 【與 isReady 防呆同等重要】invalidate() 內部是 `_state._invalidate()`
    // ——`_state` getter 用 `!` 強制解包，若文件仍在非同步開啟中
    // （PdfViewer 尚未建構、controller 尚未 attach，`_controller.isReady`
    // 為 false），呼叫 invalidate() 會直接擲出 null-check 例外導致當機。
    // 未 ready 時不需要 invalidate：文件開完後 layoutPages/
    // calculateCurrentPageNumber 本來就會用當下最新的 widget 值全新計算，
    // 不需要手動觸發。
    if (_controller.isReady) {
      _controller.invalidate();
    }

    // 【時序注意，非顯而易見】invalidate() 觸發的 relayout（無論是走本
    // widget 的 _layoutSpreadPages，還是切回單頁模式時 pdfrx 內建的預設
    // 版面函式）並非在本次 didUpdateWidget 所屬的這一幀內同步完成——
    // invalidate() 是透過 pdfrx 內部的 BehaviorSubject（Stream）通知，
    // Stream 的監聽者（觸發 pdfrx 內部 rebuild 的 StreamBuilder）是在
    // microtask 才收到事件，而 microtask 要等本幀的
    // WidgetsBinding.drawFrame() 整個同步呼叫（含本幀所有
    // postFrameCallback）都返回事件迴圈後才會執行，也就是說實際 relayout
    // 要等到「下一幀」才會發生。若只註冊單層 addPostFrameCallback，會在
    // relayout 真正完成「之前」就先觸發，讀到的仍是切換前的舊版面/舊
    // 頁碼推算結果（尤其從雙頁切回單頁時，_layoutSpreadPages 根本不會
    // 再被呼叫，改用 pdfrx 內建版面，一樣要等下一幀才計算好）。因此改用
    // 兩層巢狀 addPostFrameCallback：第一層只是讓本幀先結束、把
    // microtask 排到的下一幀真正跑起來，第二層才是在那次 relayout
    // 完成之後才執行 reanchor，兩個方向（切入/切出雙頁模式）都適用，不
    // 需要依賴 _layoutSpreadPages 是否會被呼叫。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingReanchor());
    });
  }

  void _applyPendingReanchor() {
    final pageIndex = _pendingReanchorPageIndex;
    _pendingReanchorPageIndex = null;
    if (pageIndex == null || !mounted || !_controller.isReady) return;
    _jumpToPage(pageIndex); // 走既有的單/雙頁分派邏輯。
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全部測試（本 Task 新增的 5 項＋先前所有既有測試）PASS，包含「isReady == false 防呆」測試——若這項失敗且失敗原因是未捕捉例外（`Null check operator used on a null value`），代表 Step 3 的 `if (_controller.isReady)` 防呆沒有正確包住 `invalidate()` 呼叫，須回頭檢查。

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: Issue 1 既有 5 項測試全數 PASS，檔案 `git diff` 仍為空。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_dual_page_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增 didUpdateWidget 執行期雙頁切換重新對齊"
```

---

### Task 8：接線 `reader_screen.dart`，全專案回歸驗收

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes: Task 4 的 `PdfReaderView` 新建構參數。
- Produces: `ReaderScreen` PDF 分支正式驅動雙頁並列，`pdf_settings_sheet.dart` 既有的雙頁設定 UI 從「操作無效果」變成「真正生效」。本 Task 完成後 Issue 2 全部驗收條件應可打勾。

- [ ] **Step 1: 修改 PDF 分支**

在 `app/lib/screens/reader_screen.dart` 找到（約 1940-1958 行）：

```dart
      case BookFormat.pdf:
        // 【epic-24-pdf-engine-rebuild Issue 1，已知且經人類確認接受的
        // 暫時性行為退化】新引擎目前只支援單頁顯示＋頁碼＋跳頁，濾鏡
        // （contrast/brightness/boldStrength/cropMode/cropRect）、雙頁
        // （dualPageMode 等）、劃線選取（onSelectionRectComputed 等）、
        // 導航熱區（navZoneActions/onZoneAction）皆暫不傳遞——這些能力
        // 會在 Issue 2-4/8 陸續補回。版面設定面板等 UI 入口在補回前仍會
        // 顯示，但操作暫時無效果，這是刻意接受的風險排序，非遺漏。
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
```

改為：

```dart
      case BookFormat.pdf:
        // 【epic-24-pdf-engine-rebuild，已知且經人類確認接受的暫時性行為
        // 退化】新引擎目前支援單頁/雙頁顯示＋頁碼＋跳頁；濾鏡
        // （contrast/brightness/boldStrength/cropMode/cropRect）、劃線選取
        // （onSelectionRectComputed 等）、導航熱區（navZoneActions/
        // onZoneAction）尚未傳遞——這些能力會在 Issue 3-4/8 陸續補回。
        // 對應設定面板 UI 入口在補回前仍會顯示但操作暫時無效果，這是
        // 刻意接受的風險排序，非遺漏。
        // 雙頁（Issue 2）已補回：以下四個參數驅動 pdfrx 的 layoutPages。
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
```

（`resolved` 已在 `_buildNativeView` 方法開頭以 `final resolved = _resolved!;` 取得；`isLandscape` 為方法既有形參，EPUB 分支已同源使用，不新增方向偵測。）

- [ ] **Step 2: 執行 `reader_screen_test.dart` 確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS。若有既有測試斷言 PDF 分支「不傳雙頁參數」之類的內容（不太可能，Issue 1 移除這些參數時已一併處理過測試），逐一檢視並依實際情況修正斷言，不應有測試因本次改動而預期失敗。

- [ ] **Step 3: 執行全專案 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，無任何回歸。

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Grep 確認雙頁參數已正確接線**

Run:
```bash
grep -n "dualPageMode: resolved.dualPageMode" app/lib/screens/reader_screen.dart
```
Expected: 至少 2 筆符合（EPUB 分支既有一筆＋本次新增的 PDF 分支一筆）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "$(cat <<'EOF'
feat(epic-24): PDF 雙頁並列接線 reader_screen.dart，Issue 2 完成

三態雙頁模式（自動/永遠雙頁/永遠單頁）、封面獨立顯示、RTL/LTR 配對方向
底層改由 pdfrx 的 layoutPages/calculateCurrentPageNumber 客製化排版
API 實作，取代舊架構自行拼接點陣圖的作法。單頁模式下行為與 Issue 1
逐位元相同（layoutPages/calculateCurrentPageNumber 傳 null，構造性零
回歸保證）。
EOF
)"
```

---

### Task 9（建議，非必要）：真機視覺確認

**Files:** 無新增/修改檔案，純驗證。

- [ ] **Step 1（建議）：真機視覺確認**

`flutter test` 已涵蓋配對規則、幾何排版、翻頁步進的核心行為，此步驟用於確認真實 pdfrx/PDFium 在 Android 裝置上的實際視覺呈現（桌面 host 測試驗證的是邏輯正確性，不是縮放/動畫的視覺品質本身）：

1. 開啟一本多頁 PDF，於版面設定面板切換三態雙頁模式，確認橫向自動雙頁、直向自動單頁。
2. 手動切換「永遠雙頁」，確認封面獨立顯示、之後兩兩配對，翻頁動畫流暢、頁面縮放不跳動。
3. 切換 RTL/LTR，確認左右頁配對方向符合預期。
4. **已知風險提醒**（非本工單阻擋項，供真機驗證時留意）：`app/integration_test/pdf_nav_zone_test.dart`（第 130-186 行一帶）目前用 `sample_dual_page.pdf`（6 頁）驗證熱區換頁，但未明確覆寫 `isLandscape`／未持久化 `BookReaderPrefs`，本工單完成後該書會落在預設 `dualPageMode: auto` 語意下——若測試執行環境的預設 viewport 恰好判定為橫向，該測試「呼叫一次 nextPage 應從第 1 頁到第 2 頁」的斷言可能因為改為雙頁步進（第 1 頁→第 3 頁）而失敗。這是 Issue 1 審查已記錄的「`pdf_nav_zone_test.dart`／`volume_key_test.dart` 疑似斷言過期」風險的延伸，建議與該項一併在真機上驗證並視需要修正斷言，不在本工單 Task 1-8 的範圍內處理。

- [ ] **Step 2: Commit（若真機驗證發現需要修正的問題）**

若 Step 1 發現任何問題並修正程式碼，比照 Task 1-8 的模式（先確認測試涵蓋、修正、重新測試、commit）。若無需修正，本 Step 略過。
