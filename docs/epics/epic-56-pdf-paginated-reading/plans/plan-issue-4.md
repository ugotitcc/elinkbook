# Issue 4：逐頁幾何隔離與瞬間換頁 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** PDF 的「翻頁模式」為逐頁（`PdfPageTurnMode.paginated`）時，畫面一次只顯示一個單元（一頁或一個 spread），鄰頁在幾何上不可能進入可視矩形，換頁瞬間完成；並讓產品預設（`ReaderScreen` 已傳入的解析後偏好）真正落到逐頁。連續捲動路徑行為完全不變。

**Architecture：** 在純 Dart 的 `pdf_paginated_rules.dart` 擴充三組規則：（1）`isolatePaginatedUnits` 把既有版面（單頁堆疊／spread／裁切）的各單元依 spike 公式拉開間距；（2）`clampPagedViewport` 把縮放與平移鎖在目前單元內（含置中、溢出、真實比例的起始側）；（3）`pagedAdjacentUnit` 做 Page-fit 子集的相對步進。`PdfReaderView` 在逐頁時提供自己的 `layoutPages`、`normalizeMatrix`、`calculateCurrentPageNumber`，以「目前單元的錨點頁」為單一事實來源；所有導覽一律走 `goToPosition(duration: Duration.zero)`。`PdfFitSizeDelegate` 增加「嚴格最小縮放」模式（最小縮放＝單元基準），並在該模式下不介入版面更新與初始定位（改由 widget 負責）。

**Tech Stack：** Flutter／Dart、`pdfrx` 2.4.7、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（規則 1、2、3／4 的 Page-fit 子集、6、10；「幾何隔離」「導覽入口對應」）；工單見 `issues.md` Issue 4。

## 查證過的 `pdfrx` 事實（本計畫的依據，執行者不必重查，但若行為不符請停下來回報）

- `PdfViewerParams.normalizeMatrix`（`Matrix4 Function(Matrix4 matrix, Size viewSize, PdfPageLayout layout, PdfViewerController? controller)`）在以下路徑都會被呼叫：使用者拖曳／縮放（`TransformationController.value` setter）、`setZoom`／`goToPosition` 等所有 `_goTo`（`forceClamp: true`，Duration.zero 時同步 `setValueWithoutNormalization`）。`scrollPhysics` 非 null 時才會被忽略（本專案不設）。`goToPosition` 會先做一次文件邊界夾制再交給 `normalizeMatrix`，所以 `normalizeMatrix` 必須「由候選矩陣的縮放與可視左上角重新算出最終矩陣」，不能依賴傳入的平移。
- 矩陣慣例：`matrix.storage[0]` ＝縮放、`storage[12]`／`storage[13]` ＝平移（`tx`／`ty`）；可視矩形左上角（文件座標）＝`(-tx / zoom, -ty / zoom)`。`goToPosition(documentOffset:, zoom:)` 的 `documentOffset` 就是可視矩形左上角。
- `PdfViewerParams.calculateCurrentPageNumber`（`int? Function(Rect visibleRect, List<Rect> pageRects, PdfViewerController controller)`，回傳 1-indexed）決定 `controller.pageNumber` 與 `onPageChanged`；本專案已為雙頁覆寫過。
- `PdfViewerParams.layoutPages`（`PdfPageLayout Function(List<PdfPage> pages, PdfViewerParams params)`）在 `_updateLayout`（每次 `LayoutBuilder` 重建，含視窗尺寸改變）都會被呼叫；回傳的 `PdfPageLayout` 以 `listEquals(pageLayouts) && documentSize` 比對是否變更，所以結果值相同時不會觸發版面變更。閉包拿不到視窗尺寸，須由元件自己記（Issue 3 spike 結論：同一輪內閉包讀到的尺寸與控制器一致，不需主動觸發重算）。
- `PdfViewerParams.onViewSizeChanged(Size viewSize, Size? oldViewSize, PdfViewerController controller)` 在版面重算之後（microtask）呼叫；`PdfViewerSizeDelegate.onLayoutUpdate` 在同一個 microtask 內更早被呼叫。
- `onViewerReady(doc, controller)` 在 `onLayoutInitialized` 與初始 `_goToPage` 之後同步呼叫；delegate 在 `onLayoutInitialized` 中排的 microtask 會比 `onViewerReady` 晚執行（所以逐頁模式不能靠 delegate 的 microtask 定位，否則會蓋掉 widget 的定位）。
- `PdfViewerController.visibleRect`、`layout`、`currentZoom`、`minScale`、`viewSize`、`centerPosition`、`setZoom(position, zoom, {duration})`、`goToPosition({documentOffset, zoom, duration})` 皆為公開 API。`PdfViewer.params` 為公開欄位。
- 快取外擴預設 `horizontalCacheExtent = verticalCacheExtent = 1.0`。本 Issue **不設定**這兩個參數（Issue 3 結論：保留預設 1.0，間距落在 `(o, o + H × 外擴)`）。
- 範本：`pdfrx` 預設單頁堆疊版面為 `x = (width - page.width) / 2`、`y` 由 `margin` 起依 `page.height + margin` 累加，`width = 最寬頁 + margin * 2`。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **零回歸**：`pdfPageTurnMode` 為 `scroll`（widget 層預設）時，`PdfReaderView` 的行為必須與修改前完全相同；既有 `pdf_reader_view_*` 測試不得為了通過而修改任何一行（連同預設值）。
- **間距公式（spec 幾何隔離）**：相鄰兩單元的間距＝`max(縱向超出量(前), 縱向超出量(後)) + 50`；縱向超出量＝`max(0, (視窗高 ÷ 該單元基準縮放 − 單元高) ÷ 2)`；依視窗尺寸與單元尺寸即時計算，不用固定值。本計畫的「單元高」「單元寬」一律指單元矩形各邊加 `pdfrx` 頁邊距（8.0）後的尺寸（與 `fitZoomForUnit` 一致），間距量的是這個含邊距方框之間的距離（比只量頁面矩形更保守，仍遠小於 `o + H`，快取外擴不受影響）。
- **快取外擴**：保留 pdfrx 預設 1.0，不設定 `horizontalCacheExtent`／`verticalCacheExtent`。
- **規則 1（逐頁）**：使用者可在基準之上放大、不可縮到基準以下（每個單元各自的基準）；縮放後內容比可視範圍小的維度置中；Fit Width 與真實比例縱向溢出時從頁頂開始；真實比例橫向溢出時從閱讀起始側開始（左到右靠左、右到左靠右）。連續捲動不強制（沿用 Issue 1 的放寬）。
- **規則 3、4 的 Page-fit 子集（暫態降級）**：本 Issue 中相對步進一律是「直接換到下一個／上一個單元、落在新單元頂端、縮放回基準」，即使單元縱向溢出也一樣；頁內逐屏步進與「上一頁落在上一單元底端」留待 Issue 5。第一／最後單元再往外步進＝無動作。
- **規則 6**：絕對跳轉（目錄、書籤、頁碼輸入、縮圖、全文搜尋面板、朗讀換頁、搜尋結果跳轉）一律落在目標單元頂端、基準縮放，不繼承先前偏移與縮放；目標頁屬於某個 spread 時以該 spread 為單元。搜尋結果的高亮自動定位屬於 Issue 5，本 Issue 的搜尋跳轉先落頂端。
- **規則 10**：逐頁下回報的頁碼是目前單元的錨點頁（單頁即該頁；雙頁為 spread 錨點頁），與頁內偏移無關；位置儲存規則不變。
- **導覽動畫**：逐頁模式下所有導覽一律 `duration: Duration.zero`，完全忽略 `pdfPageTurnAnimation`。
- **PdfReaderView 對外介面**：靜態 helper 簽章不變；`pdfPageTurnMode` widget 層預設仍為 `scroll`；逐頁時若 `pdfFitMode` 為 `null`，以 Page-fit 運作（`ReaderScreen` 一律傳入解析後的值，此僅為 widget 層保險）。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 5～6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用來編輯檔案；多數原始檔是 CRLF，Edit 的定位字串不要含換行。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。
- **發版限制**：Epic 56 的 Issue 1～6 須同一版本一起發布；本 Issue 合併後長頁仍無頁內步進、也沒有滑動翻頁，屬未完成狀態。

## Review Focus

最可能咬到使用者、但 spec 沒有明說的情況（依可能性排序），每條都有對應測試：

1. **窄長視窗（寬度受限、縱向大量留白）下鄰頁從上下露出。** 間距不足時 Page-fit／Fit Width 的置中留白會露出鄰頁。→ Task 1 測 `isolatePaginatedUnits` 的間距數字（含取兩側較大者）；Task 3 以 300×900 視窗測 Page-fit、Fit Width、雙頁、裁切各自只與目前單元相交，並以連續捲動做對照（證明測試有鑑別力）。
2. **旋轉／視窗尺寸改變後跳頁，或縮放停在舊基準（spike 觀察：旋轉後 pdfrx 不會自動重新 Page-fit）。** → Task 4 測 400×400 → 300×900 後仍停在同一單元且縮放等於新基準。
3. **切換翻頁模式、Fit 模式、雙頁後回到別頁（使用者故事 8）。** → Task 4 測 逐頁↔連續捲動 後頁碼不變、逐頁下 Fit 模式切換後縮放改變。
4. **逐頁下使用者放大後拖曳或甩出單元範圍、或縮小到基準以下，露出鄰頁。** → Task 1 測 `clampPagedViewport` 的夾制與置中；Task 3 測 `setZoom` 低於基準被拉回、`goToPosition` 到遠處仍停在目前單元。
5. **邊界文件：單頁文件、第一／最後單元步進、視窗尺寸為 0（尚未量測）。** → Task 1 測 `pagedAdjacentUnit` 邊界與零尺寸 `isolatePaginatedUnits`；Task 4 測 `sample.pdf`（1 頁）開啟與步進不崩、最後一頁再按下一頁無動作。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/pdf_paginated_rules.dart` | 修改 | 新增 `stackPageRects`、`paginatedUnitOverflow`、`isolatePaginatedUnits`／`PaginatedLayout`、`clampPagedViewport`／`PagedViewport`、`pagedAdjacentUnit`、常數 `kPaginatedGapPadding` |
| `app/test/reader/pdf_paginated_rules_test.dart` | 修改 | 新增上述規則的具體數字單元測試（接縫 1） |
| `app/lib/reader/pdf_fit_size_delegate.dart` | 修改 | provider／delegate 新增 `strictMinScale`；嚴格模式下最小縮放＝基準，且不介入 `onLayoutInitialized`／`onLayoutUpdate` |
| `app/test/reader/pdf_fit_size_delegate_test.dart` | 修改 | 嚴格模式的最小縮放與相等性測試 |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | 逐頁的 `layoutPages`／`normalizeMatrix`／`calculateCurrentPageNumber`／視窗尺寸記錄、單元導覽、模式切換處理 |
| `app/test/reader/pdf_reader_view_paginated_test.dart` | 新增 | widget 接線測試（接縫 2） |
| `app/test/screens/reader_screen_test.dart` | 視實測修改 | 僅在產品預設切到逐頁導致既有 PDF 案例失敗時，才依 Task 5 規則處理 |
| `docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 狀態與開發記錄 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔、`issues.md` 與 `docs/epics.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-56-issue-4-paginated-geometry`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-56/issue-4-paginated-geometry`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [ ] **Step 1：在 `main` 提交計畫**

先把 `issues.md` Issue 4 的 `**Status:** ready-for-agent` 改為 `**Status:** in-progress`；`docs/epics.md` 第 57 列「Issue 4 待寫計畫」改為「Issue 4 開發中」。然後（在儲存庫根目錄）：

```bash
git add docs/epics/epic-56-pdf-paginated-reading/plans/plan-issue-4.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics.md
git commit -m "docs(epic-56): Issue 4 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-56-issue-4-paginated-geometry -b epic-56/issue-4-paginated-geometry
# 之後在 .worktrees/epic-56-issue-4-paginated-geometry/app 目錄下執行（以工具的工作目錄指定，不在指令中 cd）：
flutter pub get
```

預期：`Got dependencies!`。

- [ ] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/reader/pdf_paginated_rules_test.dart test/reader/pdf_fit_size_delegate_test.dart test/reader/pdf_reader_view_*_test.dart test/screens/reader_screen_test.dart
```

預期：全數通過。記下通過數（Task 5 比對用）。

---

### Task 1：純 Dart 規則——間距隔離、單元視窗夾制、相對步進

**Files：**
- Modify：`app/lib/reader/pdf_paginated_rules.dart`（檔尾追加）
- Test：`app/test/reader/pdf_paginated_rules_test.dart`（檔尾 `main()` 內追加 4 個 `group`）

**Interfaces：**
- Consumes：既有 `fitBaseScale`、`PdfFitMode`、`DualPageDirection`。
- Produces（Task 3、4 依賴，名稱與型別務必一致）：

```dart
const double kPaginatedGapPadding = 50.0;

({List<Rect> rects, Size documentSize}) stackPageRects({required List<Size> pageSizes, required double margin});

double paginatedUnitOverflow({required PdfFitMode mode, required Size contentSize, required Size viewSize, required double maxZoom});

class PaginatedLayout {
  const PaginatedLayout({required this.pageRects, required this.unitRects, required this.pageToUnit, required this.unitAnchorPages, required this.documentSize});
  final List<Rect> pageRects;        // 隔離後各頁矩形（pdfrx 版面座標，index i＝第 i+1 頁）
  final List<Rect> unitRects;        // 各單元矩形：單元內頁面矩形的聯集（不含頁邊距）
  final List<int> pageToUnit;        // 頁索引（0-based）→ 單元索引
  final List<int> unitAnchorPages;   // 單元索引 → 錨點頁索引（0-based，單元內最小頁索引）
  final Size documentSize;
  int get unitCount;
}

PaginatedLayout isolatePaginatedUnits({
  required List<Rect> pageRects, required List<int> pageToUnit, List<Rect>? baseUnitRects,
  required Size documentSize,
  required double margin, required PdfFitMode mode, required Size viewSize, required double maxZoom,
});
// baseUnitRects：隔離前各單元的矩形（不含頁邊距）。產品端一律傳入（雙頁傳
// spreadRects，其寬度已正規化為文件內容寬，單頁封面與雙頁 spread 才會有同一個
// 縮放基準；裁切與單頁傳各頁矩形）；未傳時退回「單元內頁面矩形的聯集」（僅供單元測試）。

class PagedViewport {
  const PagedViewport({required this.zoom, required this.topLeft});
  final double zoom;      // 最終縮放（已夾在 [baseZoom, maxZoom]）
  final Offset topLeft;   // 可視矩形左上角（文件座標）
}

PagedViewport clampPagedViewport({
  required Rect unitContent, required Size viewSize, required double baseZoom, required double maxZoom,
  required double zoom, Offset? candidateTopLeft, required DualPageDirection direction,
});

int? pagedAdjacentUnit({required int currentUnit, required int unitCount, required bool forward});
```

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/pdf_paginated_rules_test.dart` 的 `main()` 結尾（最後一個 `group` 之後、`}` 之前）加入。若檔頭尚未 import，補上 `import 'package:elinkbook/reader/dual_page_direction.dart';`、`import 'package:elinkbook/reader/pdf_fit_mode.dart';`（Issue 1 的測試已有）。

```dart
  group('stackPageRects：單頁堆疊版面（與 pdfrx 預設版面一致）', () {
    test('頁面水平置中、由 margin 起依頁高加 margin 累加', () {
      final r = stackPageRects(
        pageSizes: const [Size(595, 842), Size(300, 400)],
        margin: 8,
      );
      expect(r.rects[0], const Rect.fromLTWH(8, 8, 595, 842));
      expect(r.rects[1], const Rect.fromLTWH(155.5, 858, 300, 400));
      expect(r.documentSize, const Size(611, 1266));
    });
  });

  group('isolatePaginatedUnits：逐頁幾何隔離（間距公式）', () {
    // 兩頁 A4 595x842，margin 8：內容方框（含邊距）611x858，第 1 頁方框 0～858。
    final stacked = stackPageRects(
      pageSizes: const [Size(595, 842), Size(595, 842)],
      margin: 8,
    );

    PaginatedLayout isolate({
      required Size view,
      PdfFitMode mode = PdfFitMode.pageFit,
      List<Rect>? rects,
      List<int>? pageToUnit,
      List<Rect>? baseUnits,
      Size? doc,
      double maxZoom = 8,
    }) =>
        isolatePaginatedUnits(
          pageRects: rects ?? stacked.rects,
          pageToUnit: pageToUnit ?? const [0, 1],
          baseUnitRects: baseUnits,
          documentSize: doc ?? stacked.documentSize,
          margin: 8,
          mode: mode,
          viewSize: view,
          maxZoom: maxZoom,
        );

    double boxGap(PaginatedLayout l, int a, int b) =>
        l.unitRects[b].inflate(8).top - l.unitRects[a].inflate(8).bottom;

    test('窄長視窗 300x900、Page-fit：基準 300/611，超出量 487.5，間距 537.5', () {
      final l = isolate(view: const Size(300, 900));
      expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
      // 第 1 單元不動；第 2 頁整體下移 545.5（1403.5 - 858）。
      expect(l.pageRects[0], const Rect.fromLTWH(8, 8, 595, 842));
      expect(l.pageRects[1].top, closeTo(1403.5, 1e-6));
      expect(l.pageRects[1].left, 8);
      expect(l.unitRects[1].top, closeTo(1403.5, 1e-6));
      expect(l.documentSize.width, 611);
      expect(l.documentSize.height, closeTo(2253.5, 1e-6));
      expect(l.unitAnchorPages, [0, 1]);
      expect(l.pageToUnit, [0, 1]);
      expect(l.unitCount, 2);
    });

    test('Fit Width 在同一視窗下基準相同，間距相同', () {
      final l = isolate(view: const Size(300, 900), mode: PdfFitMode.fitWidth);
      expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
    });

    test('高度受限（300x300、Page-fit）：超出量 0，間距只剩 50', () {
      final l = isolate(view: const Size(300, 300));
      expect(boxGap(l, 0, 1), closeTo(50, 1e-6));
      expect(l.pageRects[1].top, closeTo(916, 1e-6)); // 858 + 58
      expect(l.documentSize.height, closeTo(1766, 1e-6)); // 908 + 858
    });

    test('真實比例（基準 1.0）：超出量 (900 - 858) / 2 = 21，間距 71', () {
      final l = isolate(view: const Size(300, 900), mode: PdfFitMode.actualSize);
      expect(boxGap(l, 0, 1), closeTo(71, 1e-6));
      expect(l.pageRects[1].top, closeTo(937, 1e-6));
      expect(l.documentSize.height, closeTo(1787, 1e-6));
    });

    test('間距取兩側超出量較大者，與單元順序無關（Review Focus 1）', () {
      // 小頁 100x100（超出量 116）與 A4（超出量 487.5），視窗 300x900、Page-fit。
      for (final sizes in [
        const [Size(100, 100), Size(595, 842)],
        const [Size(595, 842), Size(100, 100)],
      ]) {
        final s = stackPageRects(pageSizes: sizes, margin: 8);
        final l = isolate(
          view: const Size(300, 900),
          rects: s.rects,
          doc: s.documentSize,
        );
        expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
      }
    });

    test('spread 單元：頁面相對位置不變、整個單元一起移動，錨點為單元第一頁', () {
      // 兩個 spread，各 2 頁 300x400，頁間距 8。
      const rects = [
        Rect.fromLTWH(8, 8, 300, 400),
        Rect.fromLTWH(316, 8, 300, 400),
        Rect.fromLTWH(8, 416, 300, 400),
        Rect.fromLTWH(316, 416, 300, 400),
      ];
      final l = isolate(
        view: const Size(300, 900),
        rects: rects,
        pageToUnit: const [0, 0, 1, 1],
        doc: const Size(624, 824),
      );
      // 單元內容方框 624x416，基準 300/624，超出量 (1872 - 416) / 2 = 728，間距 778。
      expect(l.unitRects[0], const Rect.fromLTWH(8, 8, 608, 400));
      expect(boxGap(l, 0, 1), closeTo(778, 1e-6));
      expect(l.pageRects[0], rects[0]);
      expect(l.pageRects[1], rects[1]);
      expect(l.pageRects[2].top, closeTo(1202, 1e-6));
      expect(l.pageRects[3].top, closeTo(1202, 1e-6));
      expect(l.pageRects[3].left, 316);
      expect(l.unitAnchorPages, [0, 2]);
      expect(l.documentSize.height, closeTo(1610, 1e-6));
    });

    test('單頁 spread（封面獨立）：單元矩形取傳入的 baseUnitRects，與雙頁 spread 同寬、基準一致（C-1）', () {
      // 內容寬 600：封面（第 0 頁）在 spread 內水平置中，內頁兩頁並排。
      const rects = [
        Rect.fromLTWH(158, 8, 300, 400),
        Rect.fromLTWH(8, 416, 300, 400),
        Rect.fromLTWH(308, 416, 300, 400),
      ];
      const baseUnits = [
        Rect.fromLTWH(8, 8, 600, 400),
        Rect.fromLTWH(8, 416, 600, 400),
      ];
      final l = isolate(
        view: const Size(300, 900),
        rects: rects,
        pageToUnit: const [0, 1, 1],
        baseUnits: baseUnits,
        doc: const Size(616, 824),
      );
      // 兩個單元方框都是 616x416：基準同為 300/616，超出量 (1848 - 416) / 2 = 716，間距 766。
      expect(l.unitRects[0].width, 600);
      expect(l.unitRects[1].width, 600);
      expect(boxGap(l, 0, 1), closeTo(766, 1e-6));
      // 封面頁維持置中（x 不變），內頁整體下移 774（1190 - 416）。
      expect(l.pageRects[0], rects[0]);
      expect(l.pageRects[1].top, closeTo(1190, 1e-6));
      expect(l.pageRects[2].top, closeTo(1190, 1e-6));
      expect(l.unitAnchorPages, [0, 1]);
    });

    test('視窗尺寸為無限大（無界限制）：不移動任何頁面，不拋例外（M-3）', () {
      final l = isolate(view: const Size(double.infinity, double.infinity));
      expect(l.pageRects, stacked.rects);
    });

    test('基準被 maxZoom 夾住時，以夾住後的縮放算超出量', () {
      // 10x10 小頁、Fit Width、視窗 400x400：方框 26x26，基準 15.38 夾成 8，
      // 超出量 (400/8 - 26) / 2 = 12，間距 62。
      final s = stackPageRects(
        pageSizes: const [Size(10, 10), Size(10, 10)],
        margin: 8,
      );
      final l = isolate(
        view: const Size(400, 400),
        mode: PdfFitMode.fitWidth,
        rects: s.rects,
        doc: s.documentSize,
      );
      expect(boxGap(l, 0, 1), closeTo(62, 1e-6));
    });

    test('視窗尺寸為 0（尚未量測）：不移動任何頁面，單元矩形仍為頁面聯集（Review Focus 5）', () {
      final l = isolate(view: Size.zero);
      expect(l.pageRects, stacked.rects);
      expect(l.documentSize, stacked.documentSize);
      expect(l.unitRects, stacked.rects);
    });

    test('單頁文件：不拋例外，單元只有一個', () {
      final s = stackPageRects(pageSizes: const [Size(595, 842)], margin: 8);
      final l = isolate(
        view: const Size(300, 900),
        rects: s.rects,
        pageToUnit: const [0],
        doc: s.documentSize,
      );
      expect(l.unitCount, 1);
      expect(l.pageRects, s.rects);
    });
  });

  group('clampPagedViewport：把縮放與平移鎖在單元內（規則 1、2、6）', () {
    const view = Size(400, 800);
    // 單元方框 500x2000，Fit Width 基準 0.8：可視 500x1000，橫向剛好等寬。
    const content = Rect.fromLTWH(0, 0, 500, 2000);

    PagedViewport clamp({
      Rect unit = content,
      double base = 0.8,
      double zoom = 0.8,
      Offset? cand,
      DualPageDirection dir = DualPageDirection.ltr,
    }) =>
        clampPagedViewport(
          unitContent: unit,
          viewSize: view,
          baseZoom: base,
          maxZoom: 8,
          zoom: zoom,
          candidateTopLeft: cand,
          direction: dir,
        );

    test('縱向溢出：候選位置在範圍內則保留', () {
      final v = clamp(cand: const Offset(0, 300));
      expect(v.zoom, closeTo(0.8, 1e-9));
      expect(v.topLeft.dx, closeTo(0, 1e-9));
      expect(v.topLeft.dy, closeTo(300, 1e-9));
    });

    test('縱向溢出：超出範圍時夾在 0 與（單元高 - 可視高）', () {
      expect(clamp(cand: const Offset(0, 5000)).topLeft.dy, closeTo(1000, 1e-9));
      expect(clamp(cand: const Offset(0, -50)).topLeft.dy, closeTo(0, 1e-9));
    });

    test('沒有候選位置（跳轉）：縱向落在頂端', () {
      expect(clamp().topLeft.dy, closeTo(0, 1e-9));
    });

    test('候選位置為 NaN 或無限大：視同沒有候選位置，不污染結果（M-2）', () {
      final v = clamp(cand: const Offset(double.nan, double.infinity));
      expect(v.topLeft.dx.isFinite, isTrue);
      expect(v.topLeft.dy, closeTo(0, 1e-9));
    });

    test('縮放低於基準被拉回基準（Review Focus 4）', () {
      expect(clamp(zoom: 0.1).zoom, closeTo(0.8, 1e-9));
    });

    test('縮放超過上限被夾在 maxZoom', () {
      final v = clamp(zoom: 20, cand: const Offset(100, 100));
      expect(v.zoom, 8);
      // 可視 50x100，橫向範圍 0～450，縱向 0～1900。
      expect(v.topLeft, const Offset(100, 100));
    });

    test('放大後橫向溢出：候選位置夾在單元左右緣內', () {
      final v = clamp(zoom: 8, cand: const Offset(9999, 0));
      expect(v.topLeft.dx, closeTo(450, 1e-9));
    });

    test('兩個維度都比可視範圍小：置中（可視左上角為負）', () {
      // 內容 200x100，視窗 400x800，Page-fit 基準 2，可視 200x400。
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 200, 100),
        viewSize: view,
        baseZoom: 2,
        maxZoom: 8,
        zoom: 2,
        candidateTopLeft: const Offset(77, 77),
        direction: DualPageDirection.ltr,
      );
      expect(v.topLeft.dx, closeTo(0, 1e-9));
      expect(v.topLeft.dy, closeTo(-150, 1e-9));
    });

    test('單元不在文件原點：置中與頂端都以單元方框為準', () {
      final v = clamp(unit: const Rect.fromLTWH(100, 5000, 500, 2000));
      expect(v.topLeft.dx, closeTo(100, 1e-9));
      expect(v.topLeft.dy, closeTo(5000, 1e-9));
      expect(
        clamp(unit: const Rect.fromLTWH(100, 5000, 500, 2000), cand: const Offset(0, 99999))
            .topLeft
            .dy,
        closeTo(6000, 1e-9),
      );
    });

    test('真實比例橫向溢出：沒有候選位置時依方向決定起始側（左到右靠左、右到左靠右）', () {
      const wide = Rect.fromLTWH(0, 0, 1000, 3000);
      final ltr = clamp(unit: wide, base: 1, zoom: 1);
      final rtl = clamp(unit: wide, base: 1, zoom: 1, dir: DualPageDirection.rtl);
      expect(ltr.topLeft.dx, closeTo(0, 1e-9));
      expect(rtl.topLeft.dx, closeTo(600, 1e-9));
      expect(rtl.topLeft.dy, closeTo(0, 1e-9));
    });

    test('真實比例橫向溢出：有候選位置時夾在 0～（單元寬 - 可視寬）', () {
      const wide = Rect.fromLTWH(0, 0, 1000, 3000);
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(300, 0)).topLeft.dx,
          closeTo(300, 1e-9));
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(900, 0)).topLeft.dx,
          closeTo(600, 1e-9));
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(-5, 0)).topLeft.dx,
          closeTo(0, 1e-9));
    });
  });

  group('pagedAdjacentUnit：相對步進（規則 3、4 的 Page-fit 子集）', () {
    test('中間單元：往前／往後各移一個單元', () {
      expect(pagedAdjacentUnit(currentUnit: 2, unitCount: 5, forward: true), 3);
      expect(pagedAdjacentUnit(currentUnit: 2, unitCount: 5, forward: false), 1);
    });

    test('最後一個單元往後、第一個單元往前：無動作（Review Focus 5）', () {
      expect(pagedAdjacentUnit(currentUnit: 4, unitCount: 5, forward: true), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 5, forward: false), isNull);
    });

    test('只有一個單元或沒有單元：兩個方向都無動作', () {
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 1, forward: true), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 1, forward: false), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 0, forward: true), isNull);
    });
  });
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：編譯失敗，`Method not found: 'stackPageRects'`（以及 `isolatePaginatedUnits`、`clampPagedViewport`、`pagedAdjacentUnit`）。

- [ ] **Step 3：實作**

在 `app/lib/reader/pdf_paginated_rules.dart` 檔尾追加（`math`、`dart:ui`、`DualPageDirection`、`PdfFitMode` 的 import 都已存在）：

```dart
// ── epic-56 Issue 4：逐頁幾何隔離、單元視窗夾制、相對步進 ──

/// 逐頁單元之間，在「可視矩形縱向超出量」之上額外保留的間距（文件座標，pt）。
/// 見 spec.md「幾何隔離」間距公式（Issue 3 spike 實測決定）。
const double kPaginatedGapPadding = 50.0;

/// 與 pdfrx 預設單頁版面相同的堆疊版面：頁面水平置中，由 [margin] 起依
/// 「頁高 + margin」往下累加；文件寬為最寬頁加兩側 margin。逐頁模式在沒有
/// 雙頁與裁切時以它當作隔離前的基礎版面。
({List<Rect> rects, Size documentSize}) stackPageRects({
  required List<Size> pageSizes,
  required double margin,
}) {
  final width = pageSizes.fold<double>(0.0, (w, s) => math.max(w, s.width)) + margin * 2;
  final rects = <Rect>[];
  var y = margin;
  for (final size in pageSizes) {
    rects.add(Rect.fromLTWH((width - size.width) / 2, y, size.width, size.height));
    y += size.height + margin;
  }
  return (rects: rects, documentSize: Size(width, y));
}

/// 單元在基準縮放下，可視矩形縱向超出單元方框的最大量（文件座標）：
/// `max(0, (視窗高 ÷ 基準縮放 − 單元高) ÷ 2)`。[contentSize] 為單元含頁邊距的
/// 方框尺寸。基準以 [maxZoom] 夾住（與 `fitZoomForUnit` 一致）；算不出有效
/// 基準時回傳 0。
double paginatedUnitOverflow({
  required PdfFitMode mode,
  required Size contentSize,
  required Size viewSize,
  required double maxZoom,
}) {
  final base = fitBaseScale(mode: mode, contentSize: contentSize, viewSize: viewSize);
  if (!base.isFinite || base <= 0) return 0.0;
  final zoom = math.min(base, maxZoom);
  return math.max(0.0, (viewSize.height / zoom - contentSize.height) / 2);
}

/// [isolatePaginatedUnits] 的結果。
class PaginatedLayout {
  const PaginatedLayout({
    required this.pageRects,
    required this.unitRects,
    required this.pageToUnit,
    required this.unitAnchorPages,
    required this.documentSize,
  });

  /// 隔離後各頁矩形（pdfrx 版面座標，index i ＝第 i+1 頁）。
  final List<Rect> pageRects;

  /// 各單元矩形：單元內頁面矩形的聯集，不含頁邊距。
  final List<Rect> unitRects;

  /// 頁索引（0-based）→ 單元索引。
  final List<int> pageToUnit;

  /// 單元索引 → 錨點頁索引（0-based，單元內最小頁索引）。
  final List<int> unitAnchorPages;

  final Size documentSize;

  int get unitCount => unitRects.length;
}

/// 逐頁的幾何隔離（spec.md「幾何隔離」）：把既有版面（單頁堆疊、spread、裁切）
/// 的各單元在縱向拉開，使任何可達的可視矩形只與目前單元相交。
///
/// [pageToUnit] 為各頁所屬單元索引，必須由 0 起單調不減且每個單元至少一頁
/// （spread 版面與單頁版面都滿足）。單元方框＝單元矩形加 [margin]；相鄰方框
/// 間距＝`max(超出量(前), 超出量(後)) + kPaginatedGapPadding`。第一個單元不動，
/// 單元內頁面的相對位置不變，橫向位置不變。[viewSize] 任一邊為 0（尚未量測）
/// 時不移動任何頁面。
PaginatedLayout isolatePaginatedUnits({
  required List<Rect> pageRects,
  required List<int> pageToUnit,
  List<Rect>? baseUnitRects,
  required Size documentSize,
  required double margin,
  required PdfFitMode mode,
  required Size viewSize,
  required double maxZoom,
}) {
  final unitCount = pageToUnit.isEmpty ? 0 : pageToUnit.last + 1;
  final unions = List<Rect?>.filled(unitCount, null);
  final anchors = List<int>.filled(unitCount, 0);
  for (var i = 0; i < pageRects.length; i++) {
    final u = pageToUnit[i];
    final current = unions[u];
    if (current == null) {
      unions[u] = pageRects[i];
      anchors[u] = i;
    } else {
      unions[u] = current.expandToInclude(pageRects[i]);
    }
  }
  // 單元矩形優先取呼叫端傳入的 baseUnitRects（C-1：雙頁的 spreadRects 寬度已正規化為
  // 文件內容寬，單頁封面才不會因為聯集較窄而得到不同的縮放基準）；未傳時才用聯集。
  final units = (baseUnitRects != null && baseUnitRects.length == unitCount)
      ? List<Rect>.of(baseUnitRects)
      : [for (final r in unions) r!];

  if (unitCount == 0 ||
      !viewSize.isFinite ||
      viewSize.width <= 0 ||
      viewSize.height <= 0) {
    return PaginatedLayout(
      pageRects: pageRects,
      unitRects: units,
      pageToUnit: pageToUnit,
      unitAnchorPages: anchors,
      documentSize: documentSize,
    );
  }

  final overflows = [
    for (final u in units)
      paginatedUnitOverflow(
        mode: mode,
        contentSize: u.inflate(margin).size,
        viewSize: viewSize,
        maxZoom: maxZoom,
      ),
  ];
  final shifts = List<double>.filled(unitCount, 0.0);
  var previousBottom = units.first.inflate(margin).bottom;
  for (var u = 1; u < unitCount; u++) {
    final box = units[u].inflate(margin);
    final gap = math.max(overflows[u - 1], overflows[u]) + kPaginatedGapPadding;
    final newTop = previousBottom + gap;
    shifts[u] = newTop - box.top;
    previousBottom = newTop + box.height;
  }

  return PaginatedLayout(
    pageRects: [
      for (var i = 0; i < pageRects.length; i++)
        pageRects[i].shift(Offset(0, shifts[pageToUnit[i]])),
    ],
    unitRects: [
      for (var u = 0; u < unitCount; u++) units[u].shift(Offset(0, shifts[u])),
    ],
    pageToUnit: pageToUnit,
    unitAnchorPages: anchors,
    documentSize: Size(documentSize.width, previousBottom),
  );
}

/// [clampPagedViewport] 的結果。
class PagedViewport {
  const PagedViewport({required this.zoom, required this.topLeft});

  /// 最終縮放（已夾在 [baseZoom, maxZoom]）。
  final double zoom;

  /// 可視矩形左上角（文件座標；pdfrx `goToPosition(documentOffset:)` 的語意）。
  final Offset topLeft;
}

/// 逐頁的視窗夾制（規則 1、2、6）：把縮放夾在 `[baseZoom, maxZoom]`，並把可視
/// 矩形鎖在 [unitContent]（單元含頁邊距的方框，文件座標）內。
///
/// - 某維度的單元方框不比可視範圍大：置中（可視左上角在該軸可為負）。
/// - 某維度溢出：[candidateTopLeft] 夾在「單元起點～單元終點 − 可視長度」；
///   [candidateTopLeft] 為 null（跳轉）時取起點——縱向頂端、橫向依 [direction]
///   的閱讀起始側（左到右靠左、右到左靠右）。
PagedViewport clampPagedViewport({
  required Rect unitContent,
  required Size viewSize,
  required double baseZoom,
  required double maxZoom,
  required double zoom,
  Offset? candidateTopLeft,
  required DualPageDirection direction,
}) {
  final z = math.min(math.max(zoom, baseZoom), maxZoom);
  final x = _pagedAxis(
    start: unitContent.left,
    end: unitContent.right,
    visible: viewSize.width / z,
    candidate: candidateTopLeft?.dx,
    startAtEnd: direction == DualPageDirection.rtl,
  );
  final y = _pagedAxis(
    start: unitContent.top,
    end: unitContent.bottom,
    visible: viewSize.height / z,
    candidate: candidateTopLeft?.dy,
    startAtEnd: false,
  );
  return PagedViewport(zoom: z, topLeft: Offset(x, y));
}

double _pagedAxis({
  required double start,
  required double end,
  required double visible,
  required double? candidate,
  required bool startAtEnd,
}) {
  final extent = end - start;
  // 1e-6 容許浮點誤差：Fit Width 的基準會讓可視寬度恰好等於單元寬度，
  // 不應因為最後一位小數而在「置中」與「溢出」之間來回。
  if (extent <= visible + 1e-6) return start + extent / 2 - visible / 2;
  final min = start;
  final max = end - visible;
  // candidate 非有限（NaN／無限大）時視同沒有候選位置，避免污染矩陣。
  if (candidate == null || !candidate.isFinite) return startAtEnd ? max : min;
  return math.min(math.max(candidate, min), max);
}

/// 規則 3、4 的 Page-fit 子集（Issue 4）：相對步進時的目標單元。第一個單元往前、
/// 最後一個單元往後、或沒有單元時回傳 null（無動作）。Issue 5 會在這之前加入
/// 頁內逐屏步進，再回頭呼叫本函式決定換單元。
int? pagedAdjacentUnit({
  required int currentUnit,
  required int unitCount,
  required bool forward,
}) {
  final target = forward ? currentUnit + 1 : currentUnit - 1;
  if (target < 0 || target >= unitCount) return null;
  return target;
}
```

- [ ] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：全數 PASS（Issue 1 的 19 例＋本 Task 新增 26 例＝45）。
若 `isolatePaginatedUnits` 的間距數字與預期差微小浮點誤差，只放寬 `closeTo` 容許值，**不要**改預期數字；若差距大於 1e-3，先重算預期（對照 Global Constraints 的間距公式）再判斷是實作或測試錯誤。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_paginated_rules.dart app/test/reader/pdf_paginated_rules_test.dart
git commit -m "feat(reader): PDF 逐頁幾何隔離、單元視窗夾制與相對步進規則（epic-56 Issue 4）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`PdfFitSizeDelegate` 嚴格最小縮放模式

**Files：**
- Modify：`app/lib/reader/pdf_fit_size_delegate.dart`
- Modify：`app/test/reader/pdf_fit_size_delegate_test.dart`（`main()` 內追加）

**Interfaces：**
- Consumes：Task 1 無（只用既有 `fitZoomForUnit`）。
- Produces（Task 3 依賴）：

```dart
PdfFitSizeDelegateProvider({..., bool strictMinScale = false});  // 逐頁模式傳 true
PdfFitSizeDelegate({..., bool strictMinScale = false});
```

嚴格模式（`strictMinScale: true`）：最小縮放＝目前單元的 Fit 基準（不再與 pdfrx 原本的最小縮放取較小者）；`onLayoutInitialized`、`onLayoutUpdate` 完全不介入（初始定位與視窗尺寸改變後的重新定位由 `PdfReaderView` 負責）。

- [ ] **Step 1：寫失敗測試**

在 `pdf_fit_size_delegate_test.dart` 的 `main()` 內追加（沿用該檔既有的 `_layout`、`_unitRectOf`、`_metrics`；`_delegate` 之外新增嚴格版 helper）：

```dart
  group('嚴格最小縮放（逐頁模式，epic-56 Issue 4）', () {
    PdfViewerSizeDelegate strict(PdfFitMode mode) => PdfFitSizeDelegateProvider(
          fitMode: mode,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true,
        ).create();

    test('最小縮放＝單元基準本身：Fit Width 為 400/616', () {
      expect(_metrics(strict(PdfFitMode.fitWidth)).minScale,
          closeTo(400 / 616, 1e-9));
    });

    test('Page-fit 與真實比例同理', () {
      expect(_metrics(strict(PdfFitMode.pageFit)).minScale,
          closeTo(400 / 816, 1e-9));
      expect(_metrics(strict(PdfFitMode.actualSize)).minScale, 1.0);
    });

    test('比非嚴格模式更嚴格：非嚴格取 min(pdfrx 最小縮放, 基準)，嚴格不會比它小', () {
      final loose = _metrics(_delegate(PdfFitMode.fitWidth)).minScale;
      final tight = _metrics(strict(PdfFitMode.fitWidth)).minScale;
      expect(tight, greaterThanOrEqualTo(loose));
      expect(tight, closeTo(400 / 616, 1e-9));
    });

    test('可視尺寸為 0：退回 pdfrx 原本的指標，不丟例外', () {
      expect(
        () => _metrics(strict(PdfFitMode.fitWidth), view: Size.zero),
        returnsNormally,
      );
    });

    test('provider 相等性包含 strictMinScale', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8);
      final c = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true);
      expect(a, isNot(b));
      expect(a, c);
      expect(a.hashCode, c.hashCode);
    });
  });
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_fit_size_delegate_test.dart`
Expected：編譯失敗，`No named parameter with the name 'strictMinScale'`。

- [ ] **Step 3：實作**

`app/lib/reader/pdf_fit_size_delegate.dart`：

(a) `PdfFitSizeDelegateProvider`：欄位與建構子加 `strictMinScale`，`create`、`==`、`hashCode` 一併帶上：

```dart
  const PdfFitSizeDelegateProvider({
    required this.fitMode,
    required this.unitRectOf,
    required this.pageMargin,
    this.strictMinScale = false,
  });

  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;

  /// 必須與 `PdfViewerParams.margin` 相同。
  final double pageMargin;

  /// 逐頁模式（epic-56 Issue 4）傳 true：最小縮放＝單元基準，且不介入初始定位與
  /// 版面更新後的重新定位（由 `PdfReaderView` 負責）。
  final bool strictMinScale;

  @override
  PdfViewerSizeDelegate create() => PdfFitSizeDelegate(
        fitMode: fitMode,
        unitRectOf: unitRectOf,
        pageMargin: pageMargin,
        strictMinScale: strictMinScale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFitSizeDelegateProvider &&
          fitMode == other.fitMode &&
          unitRectOf == other.unitRectOf &&
          pageMargin == other.pageMargin &&
          strictMinScale == other.strictMinScale;

  @override
  int get hashCode => Object.hash(fitMode, unitRectOf, pageMargin, strictMinScale);
```

(b) `PdfFitSizeDelegate`：建構子加 `this.strictMinScale = false`；加欄位 `final bool strictMinScale;`；類別 doc 末尾補一段：

```dart
/// [strictMinScale] 為 true（逐頁模式）時：最小縮放直接取單元基準（使用者不可縮到
/// 基準以下，每個單元各自的基準），並且完全不介入 [onLayoutInitialized]／
/// [onLayoutUpdate]——逐頁的初始定位與視窗尺寸改變後的重新定位需要「依單元置中、
/// 依閱讀方向決定起始側」，由 `PdfReaderView` 以 `goToPosition` 負責；若讓 pdfrx
/// 預設行為先跑，只會被 widget 的定位覆蓋，還可能多一次閃爍。
```

(c) `calculateMetrics` 內回傳處：

```dart
    return PdfViewerLayoutMetrics(
      minScale: strictMinScale ? zoom : math.min(metrics.minScale, zoom),
      ...
```

(d) `onLayoutInitialized` 方法第一行（`final controller = _fitController;` 之前）加：

```dart
    // 逐頁模式：初始縮放與定位由 PdfReaderView 在 onViewerReady 負責。
    if (strictMinScale) return;
```

(e) 在 `onLayoutInitialized` 之後新增覆寫（簽章與 `PdfViewerSizeDelegateLegacy.onLayoutUpdate` 相同）：

```dart
  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    // 逐頁模式：版面或視窗尺寸改變後，由 PdfReaderView 回到目前單元的基準位置。
    if (strictMinScale) return;
    super.onLayoutUpdate(
      oldState: oldState,
      newState: newState,
      currentZoom: currentZoom,
      oldVisibleRect: oldVisibleRect,
      anchorPageNumber: anchorPageNumber,
      isLayoutChanged: isLayoutChanged,
      isViewSizeChanged: isViewSizeChanged,
    );
  }
```

- [ ] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_fit_size_delegate_test.dart`
Expected：全數 PASS（原 9 例＋新增 5 例）。若 `比非嚴格模式更嚴格` 案例因 pdfrx 實際最小縮放與預期不同而失敗，先印出兩個值確認，**不要**改成永真斷言。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_fit_size_delegate.dart app/test/reader/pdf_fit_size_delegate_test.dart
git commit -m "feat(reader): PdfFitSizeDelegate 新增逐頁用的嚴格最小縮放模式（epic-56 Issue 4）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：`PdfReaderView` 逐頁版面、平移鎖定、頁碼與初始定位

**Files：**
- Create：`app/test/reader/pdf_reader_view_paginated_test.dart`
- Modify：`app/lib/reader/pdf_reader_view.dart`

**Interfaces：**
- Consumes：Task 1 的 `stackPageRects`、`isolatePaginatedUnits`、`PaginatedLayout`、`clampPagedViewport`、`PagedViewport`；Task 2 的 `strictMinScale`；既有 `fitZoomForUnit`、`kPdfFitMaxZoom`、`_layoutSpreadPages`、`_layoutCroppedPages`、`_cropEnabled`、`_dualPageEnabled`、`_pdfPageMargin`。
- Produces（Task 4 依賴）：

```dart
// _PdfReaderViewState 新增
bool get _paginated;                    // widget.pdfPageTurnMode == paginated
bool get _pagedActive;                  // _paginated && _paged != null
PdfFitMode get _effectiveFitMode;       // widget.pdfFitMode ?? PdfFitMode.pageFit
Size _viewSize;                         // 由外層 LayoutBuilder 記錄
int _pagedAnchorPage;                   // 目前單元的錨點頁（0-based）——逐頁的單一事實來源
PaginatedLayout? _paged;                // 最近一次 layoutPages 的結果
int? _currentPagedUnit();               // 目前單元索引，無版面時 null
void _goToPagedUnit(int unit);          // 落在單元頂端／起始側、基準縮放，Duration.zero
```

- [ ] **Step 1：寫失敗測試（幾何隔離）**

建立 `app/test/reader/pdf_reader_view_paginated_test.dart`：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

const _margin = 8.0;

/// 把測試視窗設成 [size]（邏輯像素，devicePixelRatio 固定 1），PdfReaderView 直接
/// 填滿整個視窗，所以可視尺寸就是 [size]。
void _setSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 與 pdfrx 繪製規則一致的外部證據：與目前可視矩形有面積相交的頁面（1-based）。
List<int> _visiblePages(PdfViewerController c) {
  final visible = c.visibleRect;
  final rects = c.layout.pageLayouts;
  return [
    for (var i = 0; i < rects.length; i++)
      if (!rects[i].intersect(visible).isEmpty) i + 1,
  ];
}

class _Harness {
  final key = GlobalKey<State<PdfReaderView>>();
  int rendered = 0;
  final pages = <int>[];

  Widget app({
    String file = 'test/fixtures/sample_multi_page.pdf',
    PdfPageTurnMode turnMode = PdfPageTurnMode.paginated,
    PdfFitMode? fit = PdfFitMode.pageFit,
    PdfPageTurnAnimation animation = PdfPageTurnAnimation.slide,
    DualPageMode dualMode = DualPageMode.never,
    bool coverAlone = false,
    PdfCropMode cropMode = PdfCropMode.none,
    PdfCropRect? cropRect,
    int? initialPageIndex,
    List<ZoneAction>? navZoneActions,
    void Function(ZoneAction)? onZoneAction,
  }) =>
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: file,
          onPageRendered: () => rendered++,
          onError: (_) {},
          onPageChanged: (PdfPageInfo info) => pages.add(info.pageIndex),
          initialPageIndex: initialPageIndex,
          pdfPageTurnMode: turnMode,
          pdfFitMode: fit,
          pdfPageTurnAnimation: animation,
          dualPageMode: dualMode,
          dualPageCoverAlone: coverAlone,
          pdfCropMode: cropMode,
          pdfCropRect: cropRect,
          navZoneActions: navZoneActions ??
              List<ZoneAction>.filled(9, ZoneAction.none),
          onZoneAction: onZoneAction,
        ),
      );

  Future<void> waitReady(WidgetTester tester) async {
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    // 初始定位在 onViewerReady 之後才落定，再多等幾輪。
    await pumpUntilPdfReady(tester, maxIterations: 5);
  }

  Future<PdfViewerController> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await waitReady(tester);
    return controller(tester);
  }

  PdfViewerController controller(WidgetTester tester) =>
      tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
}

void main() {
  setUp(() => pdfrxInitialize());

  group('幾何隔離：逐頁下鄰頁不進入可視矩形（Review Focus 1）', () {
    testWidgets('Page-fit＋窄長視窗 300x900：只有第 1 頁相交；連續捲動同條件會露出鄰頁（對照）',
        (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      expect(_visiblePages(c), [1]);

      final scroll = _Harness();
      final cs = await scroll.open(
          tester, scroll.app(turnMode: PdfPageTurnMode.scroll));
      expect(_visiblePages(cs).length, greaterThan(1),
          reason: '對照組：連續捲動下鄰頁會從留白處露出，否則本測試對間距沒有鑑別力');
    });

    testWidgets('Page-fit＋窄長視窗：目前單元在縱向置中', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      final box = c.layout.pageLayouts[0].inflate(_margin);
      expect(c.visibleRect.center.dy, closeTo(box.center.dy, 0.5));
      expect(c.currentZoom, closeTo(300 / (612 + _margin * 2), 1e-3));
    });

    testWidgets('Fit Width、縱向有留白（300x400 小頁放進 400x1000）：只有第 1 頁相交', (tester) async {
      _setSurface(tester, const Size(400, 1000));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(file: 'test/fixtures/sample_dual_page.pdf', fit: PdfFitMode.fitWidth),
      );
      expect(_visiblePages(c), [1]);
      expect(c.currentZoom, closeTo(400 / (300 + _margin * 2), 1e-3));
    });

    testWidgets('Fit Width、縱向溢出（612x792 放進 400x400）：只有第 1 頁相交，頁寬滿版', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      expect(_visiblePages(c), [1]);
      expect(c.currentZoom, closeTo(400 / (612 + _margin * 2), 1e-3));
      // 縱向溢出時從頁頂開始。
      expect(c.visibleRect.top, closeTo(c.layout.pageLayouts[0].top - _margin, 1e-3));
    });

    testWidgets('雙頁＋封面獨立（預設）：封面與內頁 spread 縮放基準相同，翻頁不跳動（C-1）',
        (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
          coverAlone: true,
        ),
      );
      expect(_visiblePages(c), [1]); // 封面單獨一頁
      final coverZoom = c.currentZoom;
      // 基準以 spread 內容寬（兩頁 600 + 邊距 16）計，不是封面單頁寬。
      expect(coverZoom, closeTo(300 / (600 + _margin * 2), 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2, 3]);
      expect(c.currentZoom, closeTo(coverZoom, 1e-6));
    });

    testWidgets('雙頁模式：整個 spread（第 1、2 頁）一起可見，鄰近 spread 不可見', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
        ),
      );
      expect(_visiblePages(c), [1, 2]);
    });

    testWidgets('手動裁切：只有第 1 頁相交', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
        ),
      );
      expect(_visiblePages(c), [1]);
    });

    testWidgets('快取外擴保留 pdfrx 預設 1.0（Issue 3 結論，不得改動）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(tester, h.app());
      final params = tester.widget<PdfViewer>(find.byType(PdfViewer)).params;
      expect(params.verticalCacheExtent, 1.0);
      expect(params.horizontalCacheExtent, 1.0);
    });
  });

  group('平移與縮放鎖定在目前單元（Review Focus 4）', () {
    testWidgets('縮放不可低於基準，可在基準之上放大且仍只與目前單元相交', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      final base = 400 / (792 + _margin * 2); // Page-fit：高度受限

      await c.setZoom(c.centerPosition, 0.1, duration: Duration.zero);
      expect(c.currentZoom, closeTo(base, 1e-3));

      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      expect(c.currentZoom, closeTo(2.0, 1e-3));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('goToPosition 到遠處的文件座標：可視矩形仍鎖在目前單元內', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final unit0 = c.layout.pageLayouts[0].inflate(_margin);

      await c.goToPosition(
        documentOffset: Offset(0, c.layout.pageLayouts[4].bottom + 3000),
        duration: Duration.zero,
      );
      expect(_visiblePages(c), [1]);
      expect(c.visibleRect.bottom, lessThanOrEqualTo(unit0.bottom + 1e-3));
      expect(c.visibleRect.top, greaterThanOrEqualTo(unit0.top - 1e-3));
    });
  });

  group('頁碼與初始定位（規則 10）', () {
    testWidgets('以 initialPageIndex 開書：落在該頁單元，頁碼回報該頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(initialPageIndex: 3));
      expect(_visiblePages(c), [4]);
      expect(h.pages.last, 3);
    });

    testWidgets('雙頁模式：頁碼回報 spread 錨點頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
          initialPageIndex: 3, // 第 4 頁屬於 [2, 3] 這組 spread，錨點為第 3 頁（index 2）
        ),
      );
      expect(h.pages.last, 2);
    });

    testWidgets('單頁文件（1 頁）開啟不崩，只與第 1 頁相交（Review Focus 5）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(file: 'test/fixtures/sample.pdf'));
      expect(_visiblePages(c), [1]);
    });
  });
}
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：能編譯（欄位 `pdfPageTurnMode` 等已存在）、但 `只有第 1 頁相交` 類案例失敗（目前 `pdfPageTurnMode` 沒有被渲染端讀取，連續版面會讓 `_visiblePages` 回傳多頁），「縮放不可低於基準」失敗。

- [ ] **Step 3：實作——State 成員與版面**

`app/lib/reader/pdf_reader_view.dart`，在 `bool get _dualPageEnabled =>` 的**上方**加入：

```dart
  // ── epic-56 Issue 4：逐頁（paginated）──

  bool get _paginated => widget.pdfPageTurnMode == PdfPageTurnMode.paginated;

  /// 逐頁一律需要 Fit 模式；widget 層沒傳（null）時以 Page-fit 運作。產品端由
  /// `ReaderScreen` 一律傳入解析後的值。
  PdfFitMode get _effectiveFitMode => widget.pdfFitMode ?? PdfFitMode.pageFit;

  /// 外層 `LayoutBuilder` 記下的可視尺寸。pdfrx 的 `layoutPages` 閉包拿不到視窗
  /// 尺寸，而逐頁間距依視窗尺寸計算（Issue 3 spike：同一輪內閉包讀到的尺寸與
  /// 控制器一致）。
  Size _viewSize = Size.zero;

  /// 目前單元的錨點頁（0-based）。逐頁下「目前顯示哪個單元」的單一事實來源：
  /// 導覽時先更新它再 `goToPosition`；`calculateCurrentPageNumber`、
  /// `normalizeMatrix`、Fit 基準都以它為準，與可視矩形的頁內偏移無關（規則 10）。
  int _pagedAnchorPage = 0;

  /// 最近一次逐頁版面（含單元矩形與頁→單元對照），由 [_layoutPaginatedPages]
  /// 寫入（純快取，不 setState）。
  PaginatedLayout? _paged;
  ({
    int pageCount,
    bool dual,
    bool coverAlone,
    DualPageDirection direction,
    double margin,
    PdfCropRect? crop,
    PdfFitMode fit,
    Size viewSize,
  })? _pagedCacheKey;
  PdfPageLayout? _pagedPdfLayout;

  bool get _pagedActive => _paginated && _paged != null;

  /// 目前單元索引；尚無版面（或空文件）時回傳 null。
  int? _currentPagedUnit() {
    final paged = _paged;
    if (paged == null || paged.pageToUnit.isEmpty) return null;
    return paged.pageToUnit[_pagedAnchorPage.clamp(0, paged.pageToUnit.length - 1)];
  }

  /// 逐頁版面：先取既有版面（裁切／雙頁／單頁堆疊），再依 spec「幾何隔離」把各單元
  /// 縱向拉開。以完整輸入當 memo 鍵（比照 [_layoutSpreadPages]），輸入不變時回傳
  /// 同一個 [PdfPageLayout] 實例；pdfrx 每次 LayoutBuilder 重建都會呼叫它，不能
  /// 每次都重算整份文件。
  PdfPageLayout _layoutPaginatedPages(List<PdfPage> pages, PdfViewerParams params) {
    final key = (
      pageCount: pages.length,
      dual: _dualPageEnabled,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
      margin: params.margin,
      crop: _cropEnabled ? widget.pdfCropRect : null,
      fit: _effectiveFitMode,
      viewSize: _viewSize,
    );
    final cached = _pagedPdfLayout;
    if (_pagedCacheKey == key && cached != null) return cached;

    final List<Rect> baseRects;
    final List<Rect> baseUnits;
    final List<int> pageToUnit;
    final Size baseSize;
    if (_cropEnabled) {
      final base = _layoutCroppedPages(pages, params);
      baseRects = base.pageLayouts;
      baseUnits = base.pageLayouts; // 裁切：每頁一個單元，單元矩形即裁切後頁面矩形
      baseSize = base.documentSize;
      pageToUnit = [for (var i = 0; i < pages.length; i++) i];
    } else if (_dualPageEnabled) {
      final base = _layoutSpreadPages(pages, params); // 同時更新 _spreadLayout
      baseRects = base.pageLayouts;
      // 單元矩形必須取 spreadRects（寬度已正規化為文件內容寬）：單頁 spread（封面獨立、
      // 收尾單頁）才會與雙頁 spread 有同一個縮放基準，翻頁時頁面大小不跳動（C-1）。
      baseUnits = _spreadLayout!.spreadRects;
      baseSize = base.documentSize;
      pageToUnit = _spreadLayout!.pageToSpread;
    } else {
      final stacked = stackPageRects(
        pageSizes: [for (final p in pages) Size(p.width, p.height)],
        margin: params.margin,
      );
      baseRects = stacked.rects;
      baseUnits = stacked.rects;
      baseSize = stacked.documentSize;
      pageToUnit = [for (var i = 0; i < pages.length; i++) i];
    }

    final paged = isolatePaginatedUnits(
      pageRects: baseRects,
      pageToUnit: pageToUnit,
      baseUnitRects: baseUnits,
      documentSize: baseSize,
      margin: params.margin,
      mode: _effectiveFitMode,
      viewSize: _viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
    _paged = paged;
    _pagedCacheKey = key;
    return _pagedPdfLayout = PdfPageLayout(
      pageLayouts: paged.pageRects,
      documentSize: paged.documentSize,
    );
  }

  /// 逐頁的頁碼：目前單元的錨點頁（1-indexed），與可視矩形無關（規則 10）。
  int? _calculatePagedPageNumber(
    Rect visibleRect,
    List<Rect> pageRects,
    PdfViewerController controller,
  ) {
    final paged = _paged;
    final unit = _currentPagedUnit();
    if (paged == null || unit == null || paged.pageRects.length != pageRects.length) {
      return controller.pageNumber;
    }
    return paged.unitAnchorPages[unit] + 1;
  }

  /// 單元的 Fit 基準縮放（含頁邊距、夾在上限內）。
  double? _pagedBaseZoom(Rect unitRect, Size viewSize) => fitZoomForUnit(
        mode: _effectiveFitMode,
        unitRect: unitRect,
        pageMargin: _pdfPageMargin,
        viewSize: viewSize,
        maxZoom: kPdfFitMaxZoom,
      );

  /// pdfrx 的 `normalizeMatrix`：逐頁下把縮放夾在單元基準之上、把平移鎖在目前單元
  /// 內（含置中與溢出規則）。矩陣由候選的縮放與可視左上角重新組出（見計畫「查證
  /// 過的 pdfrx 事實」）。尚無版面、版面頁數與 pdfrx 不一致（切換的暫態）、或
  /// 候選矩陣不可用時原樣放行。
  Matrix4 _normalizePagedMatrix(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    final paged = _paged;
    final unit = _currentPagedUnit();
    if (paged == null ||
        unit == null ||
        paged.pageRects.length != layout.pageLayouts.length) {
      return matrix;
    }
    final unitRect = paged.unitRects[unit];
    final base = _pagedBaseZoom(unitRect, viewSize);
    final zoom = matrix.storage[0];
    if (base == null || !zoom.isFinite || zoom <= 0) return matrix;
    final viewport = clampPagedViewport(
      unitContent: unitRect.inflate(_pdfPageMargin),
      viewSize: viewSize,
      baseZoom: base,
      maxZoom: kPdfFitMaxZoom,
      zoom: zoom,
      candidateTopLeft: Offset(-matrix.storage[12] / zoom, -matrix.storage[13] / zoom),
      direction: widget.dualPageDirection,
    );
    return _matrixForViewport(viewport);
  }

  /// 與 pdfrx `goToPosition` 相同的矩陣組法：縮放 [PagedViewport.zoom]、可視左上角
  /// 為 [PagedViewport.topLeft]。
  Matrix4 _matrixForViewport(PagedViewport v) => Matrix4.identity()
    ..setEntry(0, 0, v.zoom)
    ..setEntry(1, 1, v.zoom)
    ..setEntry(2, 2, v.zoom)
    ..setTranslationRaw(-v.topLeft.dx * v.zoom, -v.topLeft.dy * v.zoom, 0);

  /// 把 [unit] 帶到可視範圍：更新錨點頁、落在單元頂端（橫向依閱讀起始側）、基準縮放，
  /// 一律瞬間完成（`Duration.zero`），不繼承先前的頁內偏移與縮放（規則 6）。
  void _goToPagedUnit(int unit) {
    final paged = _paged;
    if (paged == null || unit < 0 || unit >= paged.unitCount) return;
    // 以外層 LayoutBuilder 記下的 _viewSize 為唯一來源：controller.viewSize 內部是
    // `_state._viewSize!`，版面尚未量測時會拋 null-check 例外（I-3）。
    final viewSize = _viewSize;
    if (!viewSize.isFinite || viewSize.width <= 0 || viewSize.height <= 0) return;
    final unitRect = paged.unitRects[unit];
    final base = _pagedBaseZoom(unitRect, viewSize);
    if (base == null) return;
    _pagedAnchorPage = paged.unitAnchorPages[unit];
    final viewport = clampPagedViewport(
      unitContent: unitRect.inflate(_pdfPageMargin),
      viewSize: viewSize,
      baseZoom: base,
      maxZoom: kPdfFitMaxZoom,
      zoom: base,
      direction: widget.dualPageDirection,
    );
    unawaited(_controller.goToPosition(
      documentOffset: viewport.topLeft,
      zoom: viewport.zoom,
      duration: Duration.zero,
    ));
  }

```

(h) `_unitRectFor`：在 `final spread = _dualPageEnabled ? _spreadLayout : null;` **之前**加入逐頁分支（逐頁的單元矩形含隔離位移，必須取自 `_paged`，不能取 `_spreadLayout`）：

```dart
    final paged = _paginated ? _paged : null;
    if (paged != null && paged.pageToUnit.length == layout.pageLayouts.length) {
      return paged.unitRects[paged.pageToUnit[pageNumber - 1]];
    }
```

(i) `initState`：`_committedBoldStrength = widget.pdfBoldStrength;` 之後加：

```dart
    _pagedAnchorPage = widget.initialPageIndex ?? 0;
```

- [ ] **Step 4：實作——接上 `PdfViewer`**

(a) `build()` 中 `Listener(... child: colorFiltered,)` 改為記錄可視尺寸（`PdfViewer` 內部的 `LayoutBuilder` 在同一輪佈局拿到相同限制，且在我們的 builder 之後執行）：

```dart
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewSize = constraints.biggest;
              return colorFiltered;
            },
          ),
```

(b) `PdfViewerParams(...)` 內，把 `sizeDelegateProvider`、`layoutPages`、`calculateCurrentPageNumber` 三項換成：

```dart
        sizeDelegateProvider: (widget.pdfFitMode == null && !_paginated)
            ? null
            : PdfFitSizeDelegateProvider(
                fitMode: _effectiveFitMode,
                unitRectOf: _unitRectFor,
                pageMargin: _pdfPageMargin,
                strictMinScale: _paginated,
              ),
        layoutPages: _paginated
            ? _layoutPaginatedPages
            : (_cropEnabled
                ? _layoutCroppedPages
                : (_dualPageEnabled ? _layoutSpreadPages : null)),
        calculateCurrentPageNumber: _paginated
            ? _calculatePagedPageNumber
            : (_dualPageEnabled ? _calculateSpreadAnchorPageNumber : null),
        normalizeMatrix: _paginated ? _normalizePagedMatrix : null,
```

(c) `onViewerReady: (doc, controller) {` 的區塊**第一行**加入初始定位（逐頁下 delegate 不介入初始定位，見 Task 2；`onViewerReady` 比 delegate 排的 microtask 早，所以由這裡負責）：

```dart
          // 逐頁：delegate 嚴格模式不介入初始定位，由此把初始單元帶到起點。
          if (_pagedActive) {
            final unit = _currentPagedUnit();
            if (unit != null) _goToPagedUnit(unit);
          }
```

- [ ] **Step 5：確認通過**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：全數 PASS（13 例）。

若失敗的排查順序（**不要**調整測試數值去遷就實作）：
1. `_visiblePages` 含多頁：確認 `layoutPages` 真的是 `_layoutPaginatedPages`（暫時 `debugPrint` `_paged?.unitCount`）、`_viewSize` 不是 `Size.zero`（LayoutBuilder 是否包到）。
2. 縮放不等於基準：確認 `_goToPagedUnit` 在 `onViewerReady` 被呼叫（`_pagedActive` 此時是否為 true——若 `_paged` 為 null 代表 `layoutPages` 尚未被呼叫，回報後與審查者討論改在 `_applyPendingReanchor` 式的 post-frame 補定位）。
3. 初始頁錯誤：確認 `initState` 的 `_pagedAnchorPage` 與 `initialPageNumber` 一致。

- [ ] **Step 6：確認連續捲動零回歸**

Run：`flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_fit_mode_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_nav_zone_test.dart test/reader/pdf_reader_view_selection_test.dart`
Expected：全數 PASS，未修改任何既有測試。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_paginated_test.dart
git commit -m "feat(reader): PDF 逐頁幾何隔離、平移鎖定與單元頁碼（epic-56 Issue 4）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：瞬間換頁導覽、視窗尺寸改變與模式切換

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`（`_pageTurnDuration`、`_jumpToPage`、`_nextPage`、`_previousPage`、`didUpdateWidget`、`_applyFitZoom`、`PdfViewerParams.onViewSizeChanged`）
- Modify：`app/test/reader/pdf_reader_view_paginated_test.dart`（`main()` 內追加 `group`）

**Interfaces：**
- Consumes：Task 3 的 `_pagedActive`、`_currentPagedUnit`、`_goToPagedUnit`、`_paged`、`_pagedAnchorPage`；Task 1 的 `pagedAdjacentUnit`。
- Produces：無新增對外介面；既有靜態 helper（`jumpToPage`／`nextPage`／`previousPage`）語意在逐頁下改為單元導覽。

- [ ] **Step 1：寫失敗測試**

在 `pdf_reader_view_paginated_test.dart` 的 `main()` 結尾追加：

```dart
  group('瞬間換頁導覽（規則 3／4 Page-fit 子集、規則 6）', () {
    testWidgets('nextPage／previousPage：瞬間換到相鄰單元（預設滑動動畫也不播放）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app()); // animation 預設為 slide
      expect(_visiblePages(c), [1]);

      PdfReaderView.nextPage(h.key);
      // 刻意不 pump：Duration.zero 的 goToPosition 同步完成，沒有任何動畫幀。
      expect(_visiblePages(c), [2]);

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('第一個單元往前、最後一個單元往後：無動作（Review Focus 5）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);

      for (var i = 0; i < 6; i++) {
        PdfReaderView.nextPage(h.key); // 5 頁文件：第 5 次之後已在最後一頁
      }
      expect(_visiblePages(c), [5]);
    });

    testWidgets('單頁文件：下一頁與上一頁都無動作、不拋例外', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(file: 'test/fixtures/sample.pdf'));
      PdfReaderView.nextPage(h.key);
      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('3×3 熱區的下一頁／上一頁動作：瞬間換頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      actions[2] = ZoneAction.nextPage;
      actions[0] = ZoneAction.previousPage;
      void onZone(ZoneAction a) {
        if (a == ZoneAction.nextPage) PdfReaderView.nextPage(h.key);
        if (a == ZoneAction.previousPage) PdfReaderView.previousPage(h.key);
      }

      final c = await h.open(
          tester, h.app(navZoneActions: actions, onZoneAction: onZone));
      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_2')));
      await tester.pump();
      expect(_visiblePages(c), [2]);

      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_0')));
      await tester.pump();
      expect(_visiblePages(c), [1]);
      // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期。
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('雙頁模式：下一頁換到下一個 spread，頁碼回報錨點頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
        ),
      );
      expect(_visiblePages(c), [1, 2]);
      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [3, 4]);
      await pumpUntilPdfReady(tester,
          condition: () => h.pages.isNotEmpty && h.pages.last == 2,
          maxIterations: 10);
      expect(h.pages.last, 2);
    });

    testWidgets('頁碼回報：單頁逐頁換頁後為新頁碼（index）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(tester, h.app());
      PdfReaderView.nextPage(h.key);
      await pumpUntilPdfReady(tester,
          condition: () => h.pages.isNotEmpty && h.pages.last == 1,
          maxIterations: 10);
      expect(h.pages.last, 1);
    });

    testWidgets('jumpToPage：落在目標單元頂端、基準縮放，不繼承先前的偏移與縮放', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final base = 400 / (612 + _margin * 2);

      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);
      final top3 = c.layout.pageLayouts[2].top - _margin;
      expect(c.visibleRect.top, closeTo(top3, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-3));

      // 放大並在頁內往下平移後再次絕對跳轉：回到新單元頂端與基準縮放。
      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      await c.goToPosition(
        documentOffset: Offset(0, top3 + 300),
        zoom: 2.0,
        duration: Duration.zero,
      );
      PdfReaderView.jumpToPage(h.key, 3);
      expect(_visiblePages(c), [4]);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[3].top - _margin, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-3));
    });
  });

  group('視窗尺寸改變與模式切換（Review Focus 2、3）', () {
    testWidgets('旋轉／視窗尺寸改變：停在同一單元，縮放重算為新基準', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);

      tester.view.physicalSize = const Size(300, 900);
      await pumpUntilPdfReady(tester, maxIterations: 8);

      expect(_visiblePages(c), [3]);
      final base = 300 / (612 + _margin * 2); // 寬度受限
      expect(c.currentZoom, closeTo(base, 1e-3));
      final box = c.layout.pageLayouts[2].inflate(_margin);
      expect(c.visibleRect.center.dy, closeTo(box.center.dy, 0.5));
    });

    testWidgets('逐頁→連續捲動→逐頁：停在原本那一頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);

      await tester.pumpWidget(h.app(turnMode: PdfPageTurnMode.scroll));
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(c.pageNumber, 3);

      await tester.pumpWidget(h.app());
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(_visiblePages(c), [3]);
    });

    testWidgets('逐頁下切換 Fit 模式：縮放改為新模式的基準', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      expect(c.currentZoom, closeTo(400 / (792 + _margin * 2), 1e-3));

      await tester.pumpWidget(h.app(fit: PdfFitMode.fitWidth));
      final fitWidth = 400 / (612 + _margin * 2);
      await pumpUntilPdfReady(tester,
          condition: () => (c.currentZoom - fitWidth).abs() < 1e-3,
          maxIterations: 10);
      expect(c.currentZoom, closeTo(fitWidth, 1e-3));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('逐頁下切換雙頁模式：仍停在原頁所屬的 spread', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(file: 'test/fixtures/sample_dual_page.pdf'));
      PdfReaderView.jumpToPage(h.key, 3);
      expect(_visiblePages(c), [4]);

      await tester.pumpWidget(h.app(
        file: 'test/fixtures/sample_dual_page.pdf',
        dualMode: DualPageMode.always,
      ));
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(_visiblePages(c), [3, 4]);
    });
  });
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：Task 3 的案例仍通過；本 Task 新增案例失敗（`nextPage` 走既有 `goToPage`，動畫下沒有同步完成、也不落在單元頂端；視窗改變與模式切換不重新定位）。

- [ ] **Step 3：實作——導覽一律瞬間、走單元**

`pdf_reader_view.dart`：

(a) `_pageTurnDuration` 改為（逐頁一律零，保險；逐頁導覽本來就只走 `_goToPagedUnit`，不會呼叫 `goToPage`／`goToArea`）：

```dart
  Duration get _pageTurnDuration =>
      (_paginated || widget.pdfPageTurnAnimation == PdfPageTurnAnimation.none)
          ? Duration.zero
          : const Duration(milliseconds: 200);
```

並把該 getter 上方註解末尾補一句：「逐頁（epic-56）一律零時長，忽略 `pdfPageTurnAnimation`。」

(b) `_jumpToPage`：在 `if (pageIndex < 0 || pageIndex >= _controller.pageCount) return;` 之後、`final layout = _activeSpreadLayout;` 之前插入：

```dart
    if (_paginated) {
      // 以 _paginated（而非 _pagedActive）阻絕一切向連續捲動路徑的穿透：版面重算的暫態
      // （_paged 暫為 null）不得把逐頁使用者導向 goToPage／goToArea 的動畫路徑（I-2）。
      // 先記錄錨點頁：版面就緒後 normalizeMatrix 與頁碼推算都以它為準。
      _pagedAnchorPage = pageIndex;
      final paged = _paged;
      if (paged != null) _goToPagedUnit(paged.pageToUnit[pageIndex]);
      return;
    }
    // 規則 6：目錄、書籤、頁碼輸入、縮圖、全文搜尋面板、朗讀換頁、搜尋跳轉都經由這裡，
    // 一律落在目標單元（spread 取所屬單元）頂端、基準縮放，瞬間完成。
```

(c) `_nextPage`、`_previousPage`：各在 `if (!_controller.isReady) return;` 之後、`final layout = _activeSpreadLayout;` 之前插入對應的：

```dart
    if (_paginated) {
      // 同 _jumpToPage：逐頁一律不穿透到連續捲動路徑；版面暫態（_paged 為 null）時
      // _stepPagedUnit 內部直接無動作（I-2）。
      _stepPagedUnit(forward: true); // _previousPage 傳 false
      return;
    }
```

並在 `_previousPage` 之後新增：

```dart
  /// 逐頁的相對步進（熱區、音量鍵）。Issue 4 只有 Page-fit 子集：直接換到相鄰單元、
  /// 落在新單元頂端；單元縱向溢出時也一樣（暫態降級，頁內逐屏步進與「上一頁落在
  /// 上一單元底端」見 Issue 5）。第一／最後單元再往外＝無動作。
  void _stepPagedUnit({required bool forward}) {
    final paged = _paged;
    final current = _currentPagedUnit();
    if (paged == null || current == null) return;
    final target = pagedAdjacentUnit(
      currentUnit: current,
      unitCount: paged.unitCount,
      forward: forward,
    );
    if (target == null) return;
    _goToPagedUnit(target);
  }
```

(d) `_applyFitZoom`：在 `final mode = widget.pdfFitMode;` **之前**加入逐頁分支（Fit 模式切換後，逐頁要把目前單元以新基準重新定位）：

```dart
    if (_paginated) {
      final unit = _currentPagedUnit();
      if (mounted && _controller.isReady && unit != null) _goToPagedUnit(unit);
      return;
    }
```

(e) `PdfViewerParams` 增加（放在 `onPageChanged: _handlePageChanged,` 之後）：

```dart
        // 逐頁：視窗尺寸改變（旋轉、摺疊）後維持同一單元、依新尺寸重算基準、偏移回到
        // 頂端（spec「導覽入口對應」）。Issue 3 spike：旋轉後 pdfrx 保留原縮放與位置、
        // 不會自動重新 Page-fit，所以必須在這裡明確重新定位。
        onViewSizeChanged: (viewSize, oldViewSize, controller) {
          // 開書初次排版 pdfrx 也會以 oldViewSize == null 呼叫；初始定位已由
          // onViewerReady 完成，這裡只處理執行期尺寸改變（I-1）。
          if (!_pagedActive || oldViewSize == null || oldViewSize == viewSize) return;
          final unit = _currentPagedUnit();
          if (unit != null) _goToPagedUnit(unit);
        },
```

(f) `didUpdateWidget`：

- 在 `final changed = oldWidget.dualPageMode != widget.dualPageMode ||` 清單末尾（`oldWidget.pdfCropRect != widget.pdfCropRect` 之後）加上 `||\n        oldWidget.pdfPageTurnMode != widget.pdfPageTurnMode`。
- 在 `_cachedPdfLayout = null;` 之後加入：

```dart
    _pagedCacheKey = null;
    _pagedPdfLayout = null;
    _paged = null; // 版面重算前不使用舊的逐頁版面導航。
    if (_paginated) {
      // 切換前的錨點頁就是逐頁的目前單元錨點（reanchor 之後會重新對齊到單元）。
      _pagedAnchorPage = anchorBefore;
    }
```

說明：`_paged` 在 `invalidate()` 之後的下一幀由 `_layoutPaginatedPages` 重新寫入；兩層 postFrameCallback 的 `_applyPendingReanchor` 會在那之後呼叫 `_jumpToPage(anchorBefore)`，逐頁下即 `_goToPagedUnit`。

- [ ] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：全數 PASS（Task 3 的 13 例＋本 Task 11 例＝24）。

排查順序（**不要**調整測試數值去遷就實作）：
1. `nextPage` 後 `_visiblePages` 仍是舊頁：確認 `_pagedActive` 為 true、`_goToPagedUnit` 有被呼叫、`goToPosition` 的 `duration` 是 `Duration.zero`。
2. 視窗尺寸改變案例失敗：確認 `onViewSizeChanged` 有被呼叫（`debugPrint`）；若 pdfrx 在測試環境下沒有觸發，回報後與審查者討論改以 `didChangeMetrics` 或 `LayoutBuilder` 偵測尺寸變化後 post-frame 補定位。
3. 模式切換案例失敗：確認 `didUpdateWidget` 的 `changed` 已含 `pdfPageTurnMode`；逐頁→連續捲動時 `_pagedActive` 因 `_paginated` 為 false 而不再介入。

- [ ] **Step 5：確認連續捲動零回歸與逐頁相關既有測試**

Run：`flutter test test/reader/pdf_reader_view_*_test.dart test/reader/pdf_paginated_rules_test.dart test/reader/pdf_fit_size_delegate_test.dart`
Expected：全數 PASS，未修改任何既有測試。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_paginated_test.dart
git commit -m "feat(reader): PDF 逐頁瞬間換頁、視窗尺寸改變重定位與模式切換（epic-56 Issue 4）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：產品預設切到逐頁的回歸確認、收尾與文件

**Files：**
- Modify（視實測）：`app/test/screens/reader_screen_test.dart`、`app/test/screens/reader_screen_stats_activity_test.dart`、`app/test/screens/reader_screen_stats_harness.dart`
- Modify：`docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`、`docs/epics.md`

**Interfaces：**
- Consumes：Task 1～4 全部。
- Produces：無（最後一個 Task）。

背景：Issue 2 已讓 `ReaderScreen` 把 `resolved.pdfPageTurnMode`（無單書值時為逐頁）傳給 `PdfReaderView`，所以「產品預設切到逐頁」在 Task 3 的渲染端落地後自動生效，`ReaderScreen` 本身不需要改程式；本 Task 確認那些會經由 `ReaderScreen` 掛載真實 `PdfReaderView` 的既有測試沒有因此回歸。

- [ ] **Step 1：確認 `ReaderScreen` 的所有 PDF 導覽都經過 `PdfReaderView` 的靜態 helper**

Run：

```bash
# 以 Git Bash 執行（PowerShell 沒有 grep；等價指令為 Select-String -Pattern "_pdfReaderViewKey|PdfReaderView."）
grep -n "_pdfReaderViewKey\|PdfReaderView\." lib/screens/reader_screen.dart | grep -v "^.*//"
```

Expected：PDF 的跳頁一律是 `PdfReaderView.jumpToPage`（目錄、書籤、頁碼輸入、縮圖、搜尋結果、進度條），換頁一律是 `PdfReaderView.previousPage`／`nextPage`（熱區與音量鍵經 `_handleZoneAction`）。若發現任何繞過這些 helper 直接操作 controller 的導覽，停下來回報，不要自行處理。

- [ ] **Step 2：跑經由 `ReaderScreen` 掛載 PDF 的既有測試**

```bash
flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_stats_activity_test.dart
```

Expected：全數 PASS（數量與 Task 0 Step 3 記下的相同）。

若有 PDF 相關案例失敗：
1. 先判斷是「測試依賴連續捲動的行為」還是「逐頁真正的缺陷」。後者回到 Task 3／4 修實作。
2. 只有前者、且失敗不超過 3 個案例時，在該測試的偏好 fake 中明確指定 `BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll)`，並在案例註解寫明原因；**不要**改斷言放寬。
3. 超過 3 個案例，停下來回報，由人類決定。

- [ ] **Step 3：全專案靜態檢查與 l10n**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：`No issues found!`；l10n 檢查 PASS。

- [ ] **Step 4：完整測試（只在這個時機跑一次）**

```bash
flutter test
```

用 `run_in_background` 執行（約 5～6 分鐘，必須在 `app/` 目錄下）。Expected：0 失敗；通過數＝Task 0 記下的基準＋本 Issue 新增案例（純 Dart 26＋delegate 5＋widget 24＝55），以實測為準。

- [ ] **Step 5：更新文件**

`docs/epics/epic-56-pdf-paginated-reading/epic.md`：

- 狀態行改為「Issue 1～3 已合併，Issue 4 開發完成待合併，其餘待寫計畫」（合併後再改為已合併）。
- 在「開發記錄」末尾新增「**2026-10-0X Issue 4 實作完成**」條目，內容須包含：做法摘要（`isolatePaginatedUnits` 的間距公式與「含頁邊距方框」的定義、`clampPagedViewport` 單一夾制函式同時服務跳轉與 `normalizeMatrix`、`_pagedAnchorPage` 為單一事實來源、delegate 嚴格模式不介入初始定位與版面更新、`onViewerReady` 負責初始定位）；實測的測試數量與全套通過數；與計畫的差異（Ruling，若有）；**待真機確認項目**：窄長手機與摺疊裝置的鄰頁隔離、旋轉後重新 Page-fit 的觀感、E-Ink 上瞬間換頁是否單次重繪、快取外擴 1.0 下連續快速換頁的白紙現象（Issue 3 已知）、第 50 頁以後旋轉、雙頁＋裁切組合。
- 提醒：Issue 4 合併後長頁仍無頁內逐屏步進（Issue 5）、也沒有滑動翻頁（Issue 6），須待全部完成才可發版。

`docs/epics/epic-56-pdf-paginated-reading/issues.md`：Issue 4 的 `**Status:** in-progress` 改為 `**Status:** done（PR #待填）`——**PR 編號在 PR 建立後才寫入**，建立 PR 前保留 `in-progress`。`docs/epics.md` 第 57 列同步。

不更新 `CLAUDE.md`（Epic 56 全部 Issue 完成、可發版時再一次補 `PdfReaderView` 功能描述）。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-56-pdf-paginated-reading/epic.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics.md
git commit -m "docs(epic-56): Issue 4 逐頁幾何隔離與瞬間換頁開發記錄

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

（若 Step 2 有修改測試檔，一併加入先前的提交或另立 `test(...)` 提交，並說明原因。）

---

## Self-Review 紀錄

**1. Spec／Issue 覆蓋：**
- 逐頁 `layoutPages` 間距＋單元（含 spread、裁切）→ Task 1 `isolatePaginatedUnits`、Task 3 `_layoutPaginatedPages`（三種基礎版面）。
- `normalizeMatrix` 鎖單元（含置中與溢出規則、真實比例起始側）→ Task 1 `clampPagedViewport`、Task 3 `_normalizePagedMatrix`。
- 快取外擴保留預設 → Global Constraints＋Task 3 測試。
- 規則 3、4 Page-fit 子集＋暫態降級、規則 6 → Task 1 `pagedAdjacentUnit`、Task 4 `_stepPagedUnit`／`_jumpToPage`。
- 動畫時長一律零 → Task 4 `_pageTurnDuration`；所有逐頁導覽只走 `goToPosition(Duration.zero)`。
- 熱區、音量鍵、目錄、書籤、頁碼輸入、縮圖、全文搜尋、朗讀 → 全部經 `ReaderScreen` 呼叫的靜態 helper（Task 5 Step 1 以 grep 確認）；熱區在 Task 4 有 widget 測試，音量鍵與熱區同走 `PdfReaderView.nextPage`。
- 頁碼回報錨點頁 → Task 3 `_calculatePagedPageNumber`＋測試。
- 視窗尺寸改變 → Task 4 `onViewSizeChanged`＋delegate 嚴格模式不介入。
- 產品預設切逐頁 → Task 5（`ReaderScreen` 已傳入，渲染端落地後自動生效）。
- 連續捲動零回歸 → Task 3 Step 6、Task 4 Step 5、Task 5。
- 測試要求：純 Dart（規則 6、無溢出步進含首尾、spread 與裁切幾何）；widget（Page-fit／Fit Width／雙頁／裁切各一例、熱區與瞬間換頁、跳轉落頂端、預設仍為連續捲動〔既有 `pdf_reader_view_test.dart` 已守〕、頁碼為錨點頁）。注意：裁切的純 Dart 單元幾何由 `isolatePaginatedUnits` 的「單頁單元」案例涵蓋（裁切版面與單頁堆疊同為每頁一個單元），裁切本身的矩形尺寸由既有 `_layoutCroppedPages` 負責。

**2. 佔位符掃描：** 無 TBD／TODO；PR 編號須待 PR 建立後才有，已在 Task 5 Step 5 明示處理方式。

**3. 型別一致性：** `PaginatedLayout`（`pageRects`／`unitRects`／`pageToUnit`／`unitAnchorPages`／`documentSize`／`unitCount`）、`PagedViewport`（`zoom`／`topLeft`）、`clampPagedViewport`、`pagedAdjacentUnit`、`strictMinScale`、`_pagedAnchorPage`、`_paged`、`_currentPagedUnit()`、`_goToPagedUnit()` 在 Task 1～4 的名稱與簽章一致。

**4. Review Focus：** 5 條皆有對應 Task 測試（見上方各條）。

**已知風險（執行時請特別留意）：**
- `onViewSizeChanged` 與 `onViewerReady` 的呼叫時序是依 pdfrx 2.4.7 原始碼推導，Task 3／4 的排查順序已寫明失敗時的處置；不要以調整測試數值處理。
- `ReaderScreen` 層級既有 PDF 測試可能因預設切到逐頁而受影響，Task 5 Step 2 規定了處理邊界。
- Issue 3 spike 的實驗分支（`worktree-epic-56-issue-3-spike`）在本機已不存在，本計畫的間距與夾制邏輯是依 `spec.md` 的公式與數據重新實作，沒有沿用實驗程式碼。

## 計畫審查修訂記錄（2026-10-03，審查報告 `reviews/review-plan-issue-4.md`）

- **C-1（採納）**：查證 `pdf_spread_layout.dart` 的 `spreadRects` 寬度刻意正規化為文件內容寬，原計畫以頁面聯集反推單元會讓單頁封面縮放約為內頁的 2 倍。`isolatePaginatedUnits` 新增 `baseUnitRects`，`_layoutPaginatedPages` 在雙頁傳 `spreadRects`、裁切與單頁傳各頁矩形；補規則單元測試（封面＋內頁）與 widget 測試（`coverAlone: true`，翻頁縮放不變）。
- **I-1（採納）**：`onViewSizeChanged` 加 `oldViewSize == null || oldViewSize == viewSize` 早退。
- **I-2（採納）**：`_jumpToPage`／`_nextPage`／`_previousPage`／`_applyFitZoom` 的逐頁分支改以 `_paginated` 判定，`_paged` 為 null 的暫態不再穿透到連續捲動路徑；`_jumpToPage` 先記錄錨點頁。
- **I-3（採納）**：`_goToPagedUnit` 只用 `_viewSize`（不讀 `_controller.viewSize`），並防呆非有限與非正尺寸。
- **M-2、M-3（採納）**：`_pagedAxis` 對非有限候選視同無候選；`isolatePaginatedUnits` 對非有限 `viewSize` 早退；各補一個單元測試。
- **M-1（部分採納）**：本計畫的指令本來就以 Git Bash 執行，補註明與等價的 PowerShell 指令。**M-4（採納）**：Task 0 Step 2 改為以工具工作目錄指定，不在指令中 `cd`。
- 測試數量同步更新：規則 26、delegate 5、widget 24，合計新增 55。
