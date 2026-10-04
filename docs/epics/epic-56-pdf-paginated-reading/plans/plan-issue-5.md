# Issue 5：長頁步進、帶高亮跳轉與閱讀活動回報 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [x]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 逐頁模式下，單元縱向可捲動（Fit Width、真實比例、放大後、長寬比極高的頁）時，熱區與音量鍵能「先頁內逐屏步進、到底才換頁；往回對稱並落在上一單元底端」；搜尋結果帶高亮矩形時視窗自動帶到看得到高亮的位置；頁內垂直拖曳會回報閱讀活動，長頁上只用拖曳閱讀時閱讀時間不會凍結。

**Architecture：** 在純 Dart 的 `pdf_paginated_rules.dart` 擴充三組規則：（1）`pagedRelativeStep` 決定相對步進是「頁內捲動」「換單元（可指定落底端）」或「無動作」（規則 3、4、5）；（2）`pagedTopForHighlight` 算出讓高亮可見的視窗頂端（規則 7）；（3）`PagedDragActivityAccumulator` 累積垂直拖曳位移（規則 9）。`PdfReaderView` 把 Issue 4 的 `_stepPagedUnit` 換成讀目前視窗位置的版本、`_goToPagedUnit` 增加落底端選項、`showTemporaryHighlight` 與新的 `jumpToPageAtRect` 呼叫高亮定位、外層 `Listener` 的 `onPointerMove` 餵給累積器並呼叫新的 `onReadingActivity` 回呼；`ReaderScreen` 把回呼接到 `ReadingSession` 既有的 `recordActivity()`，並把 PDF 內文搜尋的跳轉改走 `jumpToPageAtRect`。

**Tech Stack：** Flutter／Dart、`pdfrx` 2.4.7、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（規則 3、4、5、7、9；「導覽入口對應」）；工單見 `issues.md` Issue 5。前置：Issue 4 已合併（PR #317），本計畫建立在它的 `_paged`、`_pagedAnchorPage`、`_goToPagedUnit`、`_stepPagedUnit`、`clampPagedViewport`、`_viewSize` 之上。

## 查證過的事實（本計畫的依據，執行者不必重查，但若行為不符請停下來回報）

- **步進以「螢幕像素」為單位：** spec 規則 3 的範例（頁高 2000、可視高 800、重疊 80：0→720→1200）中，2000 是「縮放後」內容高度，所以偏移與步距都是螢幕像素；文件座標要除以縮放。現有 `maxVerticalScroll({contentSize, scale, viewSize})` 回傳的正是螢幕像素的最大捲動量。
- **目前頁內偏移（螢幕像素）**＝`(controller.visibleRect.top − 單元方框.top) × controller.currentZoom`。單元方框＝`_paged.unitRects[unit].inflate(_pdfPageMargin)`（含頁邊距，與 Issue 4 的夾制一致）。單元縱向未溢出（置中）時此值為負或 0，且 `maxVerticalScroll` 為 0。
- `controller.goToPosition(documentOffset:, zoom:, duration: Duration.zero)` 的 `documentOffset` 是可視矩形左上角（文件座標）；`normalizeMatrix`（Issue 4 的 `_normalizePagedMatrix`）會把結果夾回目前單元，所以只改縱向位置時橫向傳目前的 `visibleRect.left` 即可。
- 高亮矩形是 `PercentRect`（0～1，相對**頁面**，不是單元）。裁切模式下需先經 `originalToCropRelativePercent(rect:, cropRect:)` 換成裁切後頁面的百分比（回傳 null＝完全在裁切範圍外），這與 `_buildJumpHighlightWidget` 的既有作法一致。文件座標＝`_paged.pageRects[pageIndex]` 的左上角加百分比乘上寬高（雙頁時頁面矩形在 spread 單元內，不能用單元矩形換算）。
- `ReaderScreen` 的 PDF 搜尋跳轉有兩條：（a）開書或就地跳轉的暫態高亮：`ReaderJumpTarget.applyTo` → `PdfReaderView.showTemporaryHighlight`（`shouldNavigate: true` 時先 `jumpToPage`）；（b）PDF 內文搜尋：`_runPdfSearch` 第一筆與 `_goToPdfSearchMatch` 目前都是 `jumpToPage` 加 `setSearchHighlights`，`PdfSearchMatch.rect` 是 `PercentRect`。
- PDF 目前結構性沒有 TTS（`reader_screen.dart` 的 `onTtsTap: null // PDF 目前結構性沒有 TTS 底層能力`），所以 spec 的「朗讀沿用既有安全視窗規則」本 Issue 不需要任何程式碼；Task 5 以 grep 確認。
- `ReadingSession.recordActivity()` 已存在（`ReaderScreen` 的 `_session.recordActivity()`，熱區與長按已在用）。`PdfReaderView` 不得自行建構或引用 `ReadingSession`。
- 外層 `Listener`（`pdf_reader_view.dart` 的 `build`）已維護 `_activePointerCount`；3×3 熱區的 `TapZoneDetector` 為 `HitTestBehavior.translucent`，pointer 事件仍會到外層 `Listener`。
- 測試用的拖曳請用 `tester.startGesture` ＋ `gesture.moveBy`；`tester.drag` 會先多送一段 touch slop 位移，不適合驗證門檻。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **零回歸**：連續捲動（`pdfPageTurnMode: scroll`，widget 層預設）行為完全不變；Issue 4 的 `pdf_reader_view_paginated_test.dart` 既有案例不改而通過（Page-fit 單元沒有溢出，相對步進仍是整頁換頁）。
- **規則 3（下一頁）**：單元縱向可捲動且尚未到頁底：頁內往下捲，新偏移＝目前偏移＋（可視高度−重疊量），上限為最大捲動量；已到頁底（容許 1 個邏輯像素誤差）或沒有溢出：換到下一個單元，落在頂端、縮放回基準；已是最後一個單元：無動作。
- **規則 4（上一頁）**：偏移大於 0：頁內往上捲，新偏移＝目前偏移−步距，下限 0；已在頂端：換到上一個單元，**落在該單元的底端**（偏移＝該單元的最大捲動量，縮放回基準），之後再按即逐屏往上退；上一個單元沒有縱向溢出時落點為 0（即頂端）；已是第一個單元：無動作。落在底端只適用相對步進；滑動翻頁（Issue 6）、絕對跳轉仍落在頂端。
- **規則 5**：重疊量＝可視高度的 10%（初始值，待真機校準；模組內單一具名常數）。
- **規則 7**：高亮在「頂端對齊的視窗」內完整可見：維持頂端；否則把偏移設為讓高亮矩形垂直置中，夾在 0 與最大捲動量之間；高亮比可視高度還高：讓高亮上緣貼齊可視上緣。
- **規則 9**：頁內垂直拖曳的累積位移每達 20 邏輯像素回報一次閱讀活動，換手勢或換單元後歸零。接線合約：`ReadingSession` 由 `ReaderScreen` 私有持有，`PdfReaderView` 不得自行建構或引用它；`PdfReaderView` 新增 `onReadingActivity` 回呼（無參數），累積達門檻時呼叫；`ReaderScreen` 建構時把它接到 `_session.recordActivity()`。
- **門檻皆為具名常數**，註解標「初始值，待真機校準」；校準另立小工單，不在本 Issue 內調整。
- **頁頂容許誤差**：spec 只明定頁底 1 像素容許；頁頂以相同的 1 像素對稱處理（本計畫的決定，避免次像素偏移造成多出一次只捲不到 1 像素的空按）。
- **PdfReaderView 對外介面**：既有靜態 helper 簽章不變；只新增 `onReadingActivity` 建構參數（預設 `null`）與靜態 `jumpToPageAtRect`。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；多數原始檔是 CRLF，用 Node 腳本編輯時先把 `\r\n` 換成 `\n`、改完再換回；Edit 的定位字串不要含換行。工作目錄由工具指定，指令中不使用 `cd`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。
- **發版限制**：Epic 56 的 Issue 1～6 須同一版本一起發布；本 Issue 合併後仍沒有滑動翻頁（Issue 6）。

## Review Focus

最可能咬到使用者、但 spec 沒有明說的情況（依可能性排序），每條都有對應測試：

1. **長頁上往回按，剛讀過的尾段被跳過，或回到上一頁時落在頂端。** 上一單元落底端、之後逐屏往上退，到頂端才再跨單元。→ Task 1 測 `pagedRelativeStep` 與 `startAtBottom`；Task 2 以 400×200 的 Fit Width 測完整的往下與往回序列。
2. **浮點誤差造成多一次「捲不到 1 像素」的空按，或在頁底卡住。** → Task 1 測頁底／頁頂 1 像素容許（1199.5 視為已到底、1198.9 仍會捲到底）。
3. **使用者放大後（縮放大於基準）步進距離算錯；單元沒有溢出（置中）時被誤判成可以頁內捲動。** → Task 1 測負偏移與 `maxScroll` 為 0；Task 2 測放大後的步進，並確認 Issue 4 的 Page-fit 整頁換頁案例仍通過。
4. **搜尋高亮的極端位置：貼近頁底、比螢幕還高、裁切模式、雙頁 spread 內第二頁。** → Task 1 測 `pagedTopForHighlight` 五種情況；Task 3 以 widget 測 Fit Width 下半部、裁切、`showTemporaryHighlight` 與 `jumpToPageAtRect` 兩條路徑。
5. **閱讀活動誤計或漏計：兩指縮放、框選拖曳、水平拖曳、連續捲動不應由此回報；單次小拖曳不應回報，跨手勢不累積。** → Task 1 測累積器；Task 4 以 widget 測各種手勢，並測 `ReaderScreen` 接線讓閱讀時間持續計算。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/pdf_paginated_rules.dart` | 修改 | 新增常數、`PagedStep`／`pagedRelativeStep`、`pagedTopForHighlight`、`PagedDragActivityAccumulator`；`clampPagedViewport` 新增 `startAtBottom` |
| `app/test/reader/pdf_paginated_rules_test.dart` | 修改 | 上述規則的具體數字單元測試（接縫 1） |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | `_stepPagedUnit` 頁內步進、`_goToPagedUnit(atBottom:)`、`_revealHighlight`、`jumpToPageAtRect`、`onReadingActivity` 與 `onPointerMove` |
| `app/test/reader/pdf_reader_view_paginated_test.dart` | 修改 | 長頁步進、高亮定位、活動回報的 widget 測試（接縫 2） |
| `app/lib/screens/reader_screen.dart` | 修改 | 傳入 `onReadingActivity`；PDF 搜尋跳轉改走 `jumpToPageAtRect` |
| `app/test/screens/reader_screen_stats_activity_test.dart` | 修改 | 新增 1 個接線案例 |
| `docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 狀態與開發記錄 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔、`issues.md` 與 `docs/epics.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-56-issue-5-long-page-step`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-56/issue-5-long-page-step`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [x] **Step 1：在 `main` 提交計畫**

先把 `issues.md` Issue 5 的 `**Status:** ready-for-agent` 改為 `**Status:** in-progress`；`docs/epics.md` 第 57 列「Issue 5、6 待寫計畫」改為「Issue 5 開發中；Issue 6 待寫計畫」。然後（在儲存庫根目錄）：

```bash
git add docs/epics/epic-56-pdf-paginated-reading/plans/plan-issue-5.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics.md
git commit -m "docs(epic-56): Issue 5 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-56-issue-5-long-page-step -b epic-56/issue-5-long-page-step
```

之後在 `.worktrees/epic-56-issue-5-long-page-step/app` 目錄下執行（以工具的工作目錄指定）：

```bash
flutter pub get
```

預期：`Got dependencies!`。

- [x] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/reader/pdf_paginated_rules_test.dart test/reader/pdf_reader_view_paginated_test.dart test/screens/reader_screen_stats_activity_test.dart
```

預期：全數通過（規則 45、widget 27，加統計測試）。記下通過數。

---

### Task 1：純 Dart 規則——頁內步進、高亮定位、活動累積

**Files：**
- Modify：`app/lib/reader/pdf_paginated_rules.dart`（檔尾追加；`clampPagedViewport` 與 `_pagedAxis` 小改）
- Test：`app/test/reader/pdf_paginated_rules_test.dart`（`main()` 結尾追加 `group`）

**Interfaces：**
- Consumes：既有 `maxVerticalScroll`、`clampPagedViewport`、`pagedAdjacentUnit`。
- Produces（Task 2、3、4 依賴，名稱與型別務必一致）：

```dart
const double kPagedStepOverlapFraction = 0.10;
const double kPagedEdgeTolerance = 1.0;
const double kPagedActivityDragThreshold = 20.0;

enum PagedStepKind { scroll, changeUnit, none }

class PagedStep {
  const PagedStep.scroll(double offset);          // kind == scroll；新的頁內偏移（螢幕像素）
  const PagedStep.changeUnit({required bool landAtBottom});
  const PagedStep.none();
  final PagedStepKind kind;
  final double scrollOffset;                      // 僅 scroll 有意義
  final bool landAtBottom;                        // 僅 changeUnit 有意義
}

PagedStep pagedRelativeStep({
  required bool forward,
  required double scrollOffset,    // 目前頁內偏移（螢幕像素，單元置中時可為負）
  required double maxScroll,       // 該單元目前縮放下的最大捲動量（螢幕像素）
  required double viewHeight,
  required bool hasAdjacentUnit,
});

double pagedTopForHighlight({
  required Rect unitContent,       // 單元含頁邊距的方框（文件座標）
  required Rect highlight,         // 高亮矩形（文件座標）
  required double viewHeight,
  required double zoom,
});                                // 回傳可視矩形頂端（文件座標）

class PagedDragActivityAccumulator {
  PagedDragActivityAccumulator({this.threshold = kPagedActivityDragThreshold});
  final double threshold;
  bool add(double dy, {required int unit});       // 達門檻回傳 true
  void reset();
}

// clampPagedViewport 新增選用參數：
PagedViewport clampPagedViewport({..., bool startAtBottom = false});
```

- [x] **Step 1：寫失敗測試**

在 `pdf_paginated_rules_test.dart` 的 `main()` 結尾（最後一個 `group` 之後、`}` 之前）加入：

```dart
  group('pagedRelativeStep：長頁相對步進（規則 3、4、5）', () {
    // spec 範例：縮放後頁高 2000、可視高 800 → 最大捲動量 1200；重疊 80，步距 720。
    PagedStep step({
      required bool forward,
      required double offset,
      double maxScroll = 1200,
      double view = 800,
      bool adjacent = true,
    }) =>
        pagedRelativeStep(
          forward: forward,
          scrollOffset: offset,
          maxScroll: maxScroll,
          viewHeight: view,
          hasAdjacentUnit: adjacent,
        );

    test('下一頁序列：0 → 720 → 1200（夾在最大捲動量）→ 換到下一個單元頂端', () {
      var s = step(forward: true, offset: 0);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(720, 1e-9));
      s = step(forward: true, offset: 720);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(1200, 1e-9));
      s = step(forward: true, offset: 1200);
      expect(s.kind, PagedStepKind.changeUnit);
      expect(s.landAtBottom, isFalse);
    });

    test('上一頁序列：1200 → 480 → 0 → 換到上一個單元並落在底端', () {
      var s = step(forward: false, offset: 1200);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(480, 1e-9));
      s = step(forward: false, offset: 480);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(0, 1e-9));
      s = step(forward: false, offset: 0);
      expect(s.kind, PagedStepKind.changeUnit);
      expect(s.landAtBottom, isTrue);
    });

    test('第一／最後單元：沒有相鄰單元時在頁邊「無動作」', () {
      expect(step(forward: true, offset: 1200, adjacent: false).kind,
          PagedStepKind.none);
      expect(step(forward: false, offset: 0, adjacent: false).kind,
          PagedStepKind.none);
    });

    test('沒有相鄰單元但頁內還能捲：照常頁內捲動', () {
      expect(step(forward: true, offset: 0, adjacent: false).kind,
          PagedStepKind.scroll);
      expect(step(forward: false, offset: 1200, adjacent: false).kind,
          PagedStepKind.scroll);
    });

    test('到頁底 1 像素容許（Review Focus 2）：1199.5 視為已到底，1198.9 仍捲到底', () {
      expect(step(forward: true, offset: 1199.5).kind, PagedStepKind.changeUnit);
      final s = step(forward: true, offset: 1198.9);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(1200, 1e-9));
    });

    test('頁頂 1 像素容許：偏移 0.5 視為已在頂端', () {
      expect(step(forward: false, offset: 0.5).kind, PagedStepKind.changeUnit);
      final s = step(forward: false, offset: 1.5);
      expect(s.kind, PagedStepKind.scroll);
      expect(s.scrollOffset, closeTo(0, 1e-9));
    });

    test('單元沒有溢出（最大捲動量 0）：兩個方向都直接換單元，負偏移（置中）不誤判（Review Focus 3）', () {
      var s = step(forward: true, offset: 0, maxScroll: 0);
      expect(s.kind, PagedStepKind.changeUnit);
      s = step(forward: true, offset: -150, maxScroll: 0);
      expect(s.kind, PagedStepKind.changeUnit);
      s = step(forward: false, offset: -150, maxScroll: 0);
      expect(s.kind, PagedStepKind.changeUnit);
      expect(s.landAtBottom, isTrue);
    });

    test('剛好等高（縮放後內容高度等於可視高度，最大捲動量 0）：直接換單元', () {
      expect(step(forward: true, offset: 0, maxScroll: 0).kind,
          PagedStepKind.changeUnit);
    });

    test('步距依可視高度算：可視 400 → 重疊 40、步距 360', () {
      final s = step(forward: true, offset: 0, maxScroll: 1000, view: 400);
      expect(s.scrollOffset, closeTo(360, 1e-9));
    });
  });

  group('clampPagedViewport：落在單元底端（startAtBottom，規則 4）', () {
    const view = Size(400, 800);

    test('縱向溢出：沒有候選位置且 startAtBottom → 落在（單元底 − 可視高）', () {
      // 單元方框 500x2000，基準 0.8：可視 500x1000 → 底端的可視頂端 y = 1000。
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 500, 2000),
        viewSize: view,
        baseZoom: 0.8,
        maxZoom: 8,
        zoom: 0.8,
        direction: DualPageDirection.ltr,
        startAtBottom: true,
      );
      expect(v.topLeft.dy, closeTo(1000, 1e-9));
      expect(v.topLeft.dx, closeTo(0, 1e-9));
    });

    test('上一個單元不比螢幕高：落點仍是置中（等同 0，Review Focus 1）', () {
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 200, 100),
        viewSize: view,
        baseZoom: 2,
        maxZoom: 8,
        zoom: 2,
        direction: DualPageDirection.ltr,
        startAtBottom: true,
      );
      expect(v.topLeft.dy, closeTo(-150, 1e-9));
    });

    test('預設不落底端：行為與先前相同（落頂端）', () {
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 500, 2000),
        viewSize: view,
        baseZoom: 0.8,
        maxZoom: 8,
        zoom: 0.8,
        direction: DualPageDirection.ltr,
      );
      expect(v.topLeft.dy, closeTo(0, 1e-9));
    });

    test('startAtBottom 不影響橫向起始側（右到左仍靠右）', () {
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 1000, 3000),
        viewSize: view,
        baseZoom: 1,
        maxZoom: 8,
        zoom: 1,
        direction: DualPageDirection.rtl,
        startAtBottom: true,
      );
      expect(v.topLeft.dx, closeTo(600, 1e-9));
      expect(v.topLeft.dy, closeTo(2200, 1e-9));
    });
  });

  group('pagedTopForHighlight：帶高亮的跳轉（規則 7）', () {
    // 單元方框 500x2000，縮放 1，可視高 800 → 可視頂端範圍 0～1200。
    const unit = Rect.fromLTWH(0, 0, 500, 2000);
    double top(Rect highlight, {Rect content = unit, double view = 800}) =>
        pagedTopForHighlight(
          unitContent: content,
          highlight: highlight,
          viewHeight: view,
          zoom: 1,
        );

    test('高亮在頂端對齊的視窗內完整可見：維持頂端', () {
      expect(top(const Rect.fromLTWH(10, 100, 200, 30)), closeTo(0, 1e-9));
    });

    test('高亮剛好貼著視窗底緣（仍完整可見）：維持頂端', () {
      expect(top(const Rect.fromLTWH(10, 770, 200, 30)), closeTo(0, 1e-9));
    });

    test('高亮貼著視窗底緣且有浮點誤差（bottom 800.00005）：仍視為完整可見，維持頂端', () {
      expect(top(const Rect.fromLTRB(10, 770.00005, 210, 800.00005)),
          closeTo(0, 1e-9));
    });

    test('高亮在視窗外：垂直置中（高亮中心 1015 − 400 = 615）', () {
      expect(top(const Rect.fromLTWH(10, 1000, 200, 30)), closeTo(615, 1e-9));
    });

    test('高亮只有部分可見也視為不可見：垂直置中（中心 800 − 400 = 400）', () {
      expect(top(const Rect.fromLTWH(10, 780, 200, 40)), closeTo(400, 1e-9));
    });

    test('高亮貼近頁底：置中後夾在最大捲動量（Review Focus 4）', () {
      expect(top(const Rect.fromLTWH(10, 1950, 200, 30)), closeTo(1200, 1e-9));
    });

    test('高亮比可視高度還高：上緣貼齊可視上緣', () {
      expect(top(const Rect.fromLTWH(10, 300, 200, 1000)), closeTo(300, 1e-9));
    });

    test('單元不在文件原點：以單元方框為準（偏移加上單元頂端）', () {
      const shifted = Rect.fromLTWH(0, 5000, 500, 2000);
      expect(top(const Rect.fromLTWH(10, 6000, 200, 30), content: shifted),
          closeTo(5615 + 0, 1e-9)); // 中心 6015 − 400 = 5615，範圍 5000～6200
      expect(top(const Rect.fromLTWH(10, 5100, 200, 30), content: shifted),
          closeTo(5000, 1e-9));
    });

    test('單元沒有溢出（內容比可視範圍短）：置中，與夾制規則一致', () {
      // 內容高 500、可視高 800：置中 → 頂端 = 中心 250 − 400 = −150。
      expect(
        top(const Rect.fromLTWH(10, 100, 200, 30),
            content: const Rect.fromLTWH(0, 0, 500, 500)),
        closeTo(-150, 1e-9),
      );
    });

    test('縮放大於 1：可視高度以縮放換算（縮放 2 → 可視文件高度 400）', () {
      // 單元方框 500x2000，縮放 2，可視 400 文件高度；高亮 y=600～630 在視窗外 → 置中 615 − 200 = 415。
      expect(
        pagedTopForHighlight(
          unitContent: unit,
          highlight: const Rect.fromLTWH(10, 600, 200, 30),
          viewHeight: 800,
          zoom: 2,
        ),
        closeTo(415, 1e-9),
      );
    });
  });

  group('PagedDragActivityAccumulator：頁內拖曳閱讀活動（規則 9）', () {
    test('未達 20 像素不回報，達到就回報一次並保留餘數', () {
      final a = PagedDragActivityAccumulator();
      expect(a.add(19, unit: 0), isFalse);
      expect(a.add(1, unit: 0), isTrue); // 累積 20
      expect(a.add(15, unit: 0), isFalse);
      expect(a.add(15, unit: 0), isTrue); // 累積 30 → 回報，餘 10
      expect(a.add(9, unit: 0), isFalse); // 19
      expect(a.add(1, unit: 0), isTrue); // 20
    });

    test('向上與向下的位移都累積（取絕對值）', () {
      final a = PagedDragActivityAccumulator();
      expect(a.add(-12, unit: 0), isFalse);
      expect(a.add(12, unit: 0), isTrue);
    });

    test('換單元後歸零', () {
      final a = PagedDragActivityAccumulator();
      expect(a.add(15, unit: 0), isFalse);
      expect(a.add(15, unit: 1), isFalse); // 換單元：從 0 重新累積，只有 15
      expect(a.add(5, unit: 1), isTrue);
    });

    test('reset（換手勢）後歸零', () {
      final a = PagedDragActivityAccumulator();
      expect(a.add(15, unit: 0), isFalse);
      a.reset();
      expect(a.add(15, unit: 0), isFalse);
    });

    test('threshold 非正數：assert 失敗（避免取餘數除以零）', () {
      expect(() => PagedDragActivityAccumulator(threshold: 0),
          throwsAssertionError);
    });

    test('一次大位移只回報一次；非有限位移忽略（Review Focus 5）', () {
      final a = PagedDragActivityAccumulator();
      expect(a.add(100, unit: 0), isTrue);
      expect(a.add(double.nan, unit: 0), isFalse);
      expect(a.add(double.infinity, unit: 0), isFalse);
      expect(a.add(19, unit: 0), isFalse);
    });
  });
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：編譯失敗，`Method not found: 'pagedRelativeStep'`（以及 `PagedStep`、`pagedTopForHighlight`、`PagedDragActivityAccumulator`、`No named parameter with the name 'startAtBottom'`）。

- [x] **Step 3：實作**

`app/lib/reader/pdf_paginated_rules.dart`：

(a) `clampPagedViewport` 新增選用參數並傳給縱向軸。簽章改為（其餘不變）：

```dart
PagedViewport clampPagedViewport({
  required Rect unitContent,
  required Size viewSize,
  required double baseZoom,
  required double maxZoom,
  required double zoom,
  Offset? candidateTopLeft,
  required DualPageDirection direction,
  bool startAtBottom = false,
}) {
```

縱向那次 `_pagedAxis(...)` 呼叫的 `startAtEnd: false,` 改為 `startAtEnd: startAtBottom,`；並在函式 doc 末尾補一句：「[startAtBottom] 為 true 且沒有候選位置時，縱向落在單元底端（規則 4：相對步進往回換到上一個單元）；橫向起始側不受影響。」

(b) 檔尾追加：

```dart
// ── epic-56 Issue 5：長頁步進、帶高亮跳轉、閱讀活動 ──

/// 規則 5：相對步進時與上一個畫面保留的重疊量，佔可視高度的比例。
/// 初始值，待真機校準。
const double kPagedStepOverlapFraction = 0.10;

/// 判定「已到頁底／已在頁頂」的容許誤差（邏輯像素）。spec 明定頁底 1 像素；
/// 頁頂以相同值對稱處理，避免次像素偏移造成多出一次捲不到 1 像素的空按。
const double kPagedEdgeTolerance = 1.0;

/// 規則 9：頁內垂直拖曳每累積這麼多邏輯像素回報一次閱讀活動。初始值，待真機校準。
const double kPagedActivityDragThreshold = 20.0;

enum PagedStepKind { scroll, changeUnit, none }

/// [pagedRelativeStep] 的結果。
class PagedStep {
  /// 頁內捲動，[offset] 為新的頁內偏移（螢幕像素）。
  const PagedStep.scroll(double offset)
      : kind = PagedStepKind.scroll,
        scrollOffset = offset,
        landAtBottom = false;

  /// 換到相鄰單元；[landAtBottom] 為 true 時落在該單元底端，否則落在頂端。
  const PagedStep.changeUnit({required this.landAtBottom})
      : kind = PagedStepKind.changeUnit,
        scrollOffset = 0;

  /// 無動作（第一／最後單元再往外）。
  const PagedStep.none()
      : kind = PagedStepKind.none,
        scrollOffset = 0,
        landAtBottom = false;

  final PagedStepKind kind;

  /// 僅 [PagedStepKind.scroll] 有意義。
  final double scrollOffset;

  /// 僅 [PagedStepKind.changeUnit] 有意義。
  final bool landAtBottom;
}

/// 規則 3、4、5：逐頁下熱區與音量鍵的相對步進。
///
/// [scrollOffset] 與 [maxScroll] 皆為螢幕像素（縮放後）：[scrollOffset] 是目前可視
/// 頂端相對單元頂端的位移（單元置中時可為負），[maxScroll] 是該單元在目前縮放下的
/// 最大縱向捲動量（沒有溢出為 0）。步距＝可視高度減去 [kPagedStepOverlapFraction]
/// 的重疊量。
///
/// - 下一頁：還能往下捲（最大捲動量大於容許誤差，且偏移離頁底超過容許誤差）就頁內
///   捲動，上限為最大捲動量；否則換到下一個單元頂端；沒有下一個單元則無動作。
/// - 上一頁：偏移大於容許誤差就頁內往上捲，下限 0；否則換到上一個單元並落在底端；
///   沒有上一個單元則無動作。
PagedStep pagedRelativeStep({
  required bool forward,
  required double scrollOffset,
  required double maxScroll,
  required double viewHeight,
  required bool hasAdjacentUnit,
}) {
  final distance = viewHeight - viewHeight * kPagedStepOverlapFraction;
  if (forward) {
    if (maxScroll > kPagedEdgeTolerance &&
        scrollOffset < maxScroll - kPagedEdgeTolerance) {
      return PagedStep.scroll(math.min(scrollOffset + distance, maxScroll));
    }
    return hasAdjacentUnit
        ? const PagedStep.changeUnit(landAtBottom: false)
        : const PagedStep.none();
  }
  if (scrollOffset > kPagedEdgeTolerance) {
    return PagedStep.scroll(math.max(scrollOffset - distance, 0.0));
  }
  return hasAdjacentUnit
      ? const PagedStep.changeUnit(landAtBottom: true)
      : const PagedStep.none();
}

/// 規則 7：帶高亮矩形的跳轉。回傳「可視矩形頂端」（文件座標），讓 [highlight]
/// 看得到。呼叫時視窗應已在該單元、縮放為 [zoom]。
///
/// - 單元沒有縱向溢出：置中（與 [clampPagedViewport] 一致）。
/// - 高亮在頂端對齊的視窗內完整可見：維持頂端。
/// - 高亮比可視高度還高：上緣貼齊可視上緣。
/// - 其餘：高亮垂直置中。
/// 結果夾在「單元頂端～單元底端 − 可視高度」之內。
double pagedTopForHighlight({
  required Rect unitContent,
  required Rect highlight,
  required double viewHeight,
  required double zoom,
}) {
  final visibleHeight = viewHeight / zoom;
  final extent = unitContent.height;
  if (extent <= visibleHeight + 1e-6) {
    return unitContent.top + extent / 2 - visibleHeight / 2;
  }
  final minTop = unitContent.top;
  final maxTop = unitContent.bottom - visibleHeight;
  double top;
  // 1e-4 容許浮點誤差：高亮由百分比乘頁面尺寸換算、可視高度由除以縮放換算，貼著視窗
  // 底緣時尾數可能差 1e-12；沒有容許值會把「其實完整可見」的高亮誤判成不可見而置中。
  if (highlight.top >= minTop - 1e-4 &&
      highlight.bottom <= minTop + visibleHeight + 1e-4) {
    top = minTop;
  } else if (highlight.height > visibleHeight) {
    top = highlight.top;
  } else {
    top = highlight.center.dy - visibleHeight / 2;
  }
  return math.min(math.max(top, minTop), maxTop);
}

/// 規則 9：頁內垂直拖曳的閱讀活動累積器。累積絕對位移，每達 [threshold] 回報一次
/// （[add] 回傳 true，餘數保留）；換單元或呼叫 [reset]（換手勢）後歸零。
class PagedDragActivityAccumulator {
  PagedDragActivityAccumulator({this.threshold = kPagedActivityDragThreshold})
      : assert(threshold > 0, 'threshold 必須為正數');

  final double threshold;
  double _accumulated = 0;
  int? _unit;

  bool add(double dy, {required int unit}) {
    if (!dy.isFinite) return false;
    if (_unit != unit) {
      _accumulated = 0;
      _unit = unit;
    }
    _accumulated += dy.abs();
    if (_accumulated < threshold) return false;
    _accumulated = _accumulated % threshold;
    return true;
  }

  void reset() {
    _accumulated = 0;
    _unit = null;
  }
}
```

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：全數 PASS（原 45 例＋本 Task 新增 29 例＝74）。若 `pagedTopForHighlight` 的數字與預期差微小浮點誤差，只放寬 `closeTo` 容許值，**不要**改預期數字。

- [x] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_paginated_rules.dart app/test/reader/pdf_paginated_rules_test.dart
git commit -m "feat(reader): PDF 逐頁長頁步進、高亮定位與拖曳活動規則（epic-56 Issue 5）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`PdfReaderView` 頁內逐屏步進與落底端

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`（`_goToPagedUnit`、`_stepPagedUnit`）
- Test：`app/test/reader/pdf_reader_view_paginated_test.dart`（`main()` 結尾追加 `group`）

**Interfaces：**
- Consumes：Task 1 的 `pagedRelativeStep`、`PagedStep`／`PagedStepKind`、`clampPagedViewport(startAtBottom:)`；既有 `pagedAdjacentUnit`、`maxVerticalScroll`、`_paged`、`_viewSize`、`_currentPagedUnit()`、`_pdfPageMargin`。
- Produces（Task 3 依賴）：`void _goToPagedUnit(int unit, {bool atBottom = false})`（Issue 4 既有呼叫端不改，預設落頂端）。

- [x] **Step 1：寫失敗測試**

在 `pdf_reader_view_paginated_test.dart` 的 `main()` 結尾追加（檔內已有 `_setSurface`、`_visiblePages`、`_Harness`、`_margin`）：

```dart
  group('長頁相對步進：先頁內逐屏、到底才換頁；往回對稱並落在上一單元底端（規則 3、4）', () {
    // Fit Width、視窗 400x200、頁 612x792：基準 400/628，單元方框高 808，
    // 縮放後內容高 808 * 基準，最大捲動量＝808 * 基準 − 200，步距＝200 * 0.9 = 180。
    final base = 400 / (612 + _margin * 2);
    final maxScroll = 808 * base - 200;

    double offsetPx(PdfViewerController c, int unitIndex) {
      final unitTop = c.layout.pageLayouts[unitIndex].top - _margin;
      return (c.visibleRect.top - unitTop) * c.currentZoom;
    }

    testWidgets('下一頁：0 → 180 → 最大捲動量 → 換到第 2 頁頂端', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      expect(offsetPx(c, 0), closeTo(0, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(180, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(maxScroll, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2]);
      expect(offsetPx(c, 1), closeTo(0, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-6));
    });

    testWidgets('上一頁：從第 2 頁頂端回到第 1 頁底端，再逐屏往上退，到頂端後第一頁無動作（Review Focus 1）',
        (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 1); // 絕對跳轉：第 2 頁頂端
      expect(offsetPx(c, 1), closeTo(0, 1e-3));

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(maxScroll, 1e-3)); // 落在底端

      PdfReaderView.previousPage(h.key);
      expect(offsetPx(c, 0), closeTo(maxScroll - 180, 1e-3));

      PdfReaderView.previousPage(h.key);
      expect(offsetPx(c, 0), closeTo(0, 1e-3)); // 下限 0

      PdfReaderView.previousPage(h.key); // 第一個單元頂端再往前：無動作
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(0, 1e-3));
    });

    testWidgets('最後一頁到底後再按下一頁：無動作', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 4);
      PdfReaderView.nextPage(h.key); // 0 → 180
      PdfReaderView.nextPage(h.key); // → 最大捲動量
      PdfReaderView.nextPage(h.key); // 已到底、沒有下一頁
      expect(_visiblePages(c), [5]);
      expect(offsetPx(c, 4), closeTo(maxScroll, 1e-3));
    });

    testWidgets('絕對跳轉仍落在頂端，不繼承底端位置（規則 4：落底端只適用相對步進）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 1);
      PdfReaderView.previousPage(h.key); // 落在第 1 頁底端
      PdfReaderView.jumpToPage(h.key, 0);
      expect(offsetPx(c, 0), closeTo(0, 1e-3));
    });

    testWidgets('Page-fit 單元沒有溢出：仍是整頁換頁（Issue 4 行為不變，Review Focus 3）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2]);
      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('放大後單元縱向溢出：步距以目前縮放換算，仍先頁內步進（Review Focus 3）', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app()); // Page-fit：整頁入鏡、沒有溢出
      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      final unitTop = c.layout.pageLayouts[0].top - _margin;
      await c.goToPosition(
        documentOffset: Offset(c.visibleRect.left, unitTop),
        zoom: 2.0,
        duration: Duration.zero,
      );
      expect(offsetPx(c, 0), closeTo(0, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(360, 1e-3)); // 400 * 0.9
      expect(c.currentZoom, closeTo(2.0, 1e-6));
    });

    testWidgets('實體鍵 PageDown 與音量鍵共用同一套步進：長頁上先頁內捲動', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await tester.tap(find.byType(PdfViewer));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(180, 1e-3));
    });
  });
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：本 Task 新增案例中，長頁相關的 6 例失敗（目前相對步進一律整頁換頁：`nextPage` 後 `_visiblePages` 變成 `[2]`）；「Page-fit 單元沒有溢出」案例已通過（Issue 4 行為）。

- [x] **Step 3：實作**

`app/lib/reader/pdf_reader_view.dart`：

(a) `_goToPagedUnit` 簽章與夾制呼叫加上落底端選項。把

```dart
  void _goToPagedUnit(int unit) {
```

改為

```dart
  void _goToPagedUnit(int unit, {bool atBottom = false}) {
```

並把該方法內 `clampPagedViewport(` 的參數列最後（`direction: widget.dualPageDirection,` 之後）補上 `startAtBottom: atBottom,`。方法上方 doc 補一句：「[atBottom] 為 true（相對步進往回換單元，規則 4）時落在單元底端；預設落頂端。」

(b) 把 `_stepPagedUnit` 整個方法（含上方 doc 註解）換成：

```dart
  /// 逐頁的相對步進（熱區、音量鍵、PageUp／PageDown／Space，規則 3、4、5）：單元縱向
  /// 還能捲就先頁內逐屏步進（步距＝可視高度減 10% 重疊），到頁底才換到下一個單元頂端；
  /// 往回對稱，到頁頂後換到上一個單元的**底端**。單元沒有縱向溢出（例如 Page-fit）時
  /// 直接整頁換頁。第一／最後單元再往外＝無動作。偏移與步距皆為螢幕像素。
  void _stepPagedUnit({required bool forward}) {
    final paged = _paged;
    final current = _currentPagedUnit();
    if (paged == null || current == null) return;
    final viewSize = _viewSize;
    if (!viewSize.isFinite || viewSize.width <= 0 || viewSize.height <= 0) return;

    final box = paged.unitRects[current].inflate(_pdfPageMargin);
    final zoom = _controller.currentZoom;
    final visible = _controller.visibleRect;
    final target = pagedAdjacentUnit(
      currentUnit: current,
      unitCount: paged.unitCount,
      forward: forward,
    );
    final step = pagedRelativeStep(
      forward: forward,
      scrollOffset: (visible.top - box.top) * zoom,
      maxScroll: maxVerticalScroll(
        contentSize: box.size,
        scale: zoom,
        viewSize: viewSize,
      ),
      viewHeight: viewSize.height,
      hasAdjacentUnit: target != null,
    );
    switch (step.kind) {
      case PagedStepKind.scroll:
        // 只改縱向位置；橫向沿用目前位置，normalizeMatrix 會再夾回單元範圍。
        unawaited(_controller.goToPosition(
          documentOffset: Offset(visible.left, box.top + step.scrollOffset / zoom),
          zoom: zoom,
          duration: Duration.zero,
        ));
      case PagedStepKind.changeUnit:
        _goToPagedUnit(target!, atBottom: step.landAtBottom);
      case PagedStepKind.none:
        break;
    }
  }
```

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：全數 PASS（原 27 例＋本 Task 7 例＝34）。

排查順序（**不要**調整測試數值去遷就實作）：
1. `nextPage` 後偏移不是 180：確認 `viewSize.height` 是 200、`offsetPx` 用的是 `controller.currentZoom`；暫時 `debugPrint` `step.kind`／`step.scrollOffset`。
2. 落底端後偏移不是最大捲動量：確認 `_goToPagedUnit` 把 `startAtBottom` 傳進 `clampPagedViewport`，且 `normalizeMatrix`（`_normalizePagedMatrix`）以候選位置原樣放行（候選值已在範圍內）。
3. 放大後案例失敗：確認 `setZoom` 後 `goToPosition` 的縮放被 `normalizeMatrix` 保留（縮放大於基準合法）。

- [x] **Step 5：確認 Issue 4 既有案例與連續捲動零回歸**

Run：`flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_fit_mode_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_nav_zone_test.dart`
Expected：全數 PASS，未修改任何既有測試。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_paginated_test.dart
git commit -m "feat(reader): PDF 逐頁長頁先頁內逐屏步進、往回落上一單元底端（epic-56 Issue 5）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：帶高亮的跳轉（搜尋結果）

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`（`_setJumpHighlight`、新增 `_revealHighlight`、靜態 `jumpToPageAtRect`）
- Modify：`app/lib/screens/reader_screen.dart`（兩處 PDF 搜尋跳轉）
- Test：`app/test/reader/pdf_reader_view_paginated_test.dart`（`main()` 結尾追加 `group`）

**Interfaces：**
- Consumes：Task 1 的 `pagedTopForHighlight`；Task 2 的 `_goToPagedUnit`；既有 `originalToCropRelativePercent`、`_cropEnabled`、`_paged`、`_pagedActive`、`_currentPagedUnit()`、`PercentRect`。
- Produces：

```dart
// PdfReaderView
static void jumpToPageAtRect(GlobalKey<State<PdfReaderView>> key, int pageIndex, PercentRect rect);
// _PdfReaderViewState
void _revealHighlight(int pageIndex, PercentRect rect);   // 逐頁：確保高亮在視窗內（規則 7）；連續捲動：無動作
```

- [x] **Step 1：寫失敗測試**

在 `pdf_reader_view_paginated_test.dart` 檔頭補 `import 'package:elinkbook/reader/percent_rect.dart';`，並在 `main()` 結尾追加：

```dart
  group('帶高亮的跳轉：視窗自動帶到看得到高亮的位置（規則 7，Review Focus 4）', () {
    /// 高亮矩形（百分比）換成文件座標，與 PdfReaderView 的換算一致。
    Rect docRect(PdfViewerController c, int pageIndex, PercentRect p) {
      final page = c.layout.pageLayouts[pageIndex];
      return Rect.fromLTRB(
        page.left + p.left * page.width,
        page.top + p.top * page.height,
        page.left + p.right * page.width,
        page.top + p.bottom * page.height,
      );
    }

    void expectVisible(PdfViewerController c, Rect hl) {
      final v = c.visibleRect;
      expect(v.top, lessThanOrEqualTo(hl.top + 1e-3));
      expect(v.bottom, greaterThanOrEqualTo(hl.bottom - 1e-3));
    }

    testWidgets('jumpToPageAtRect：高亮在頁面下半部 → 視窗帶到看得到高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.85);

      PdfReaderView.jumpToPageAtRect(h.key, 2, rect);
      expect(_visiblePages(c), [3]);
      expectVisible(c, docRect(c, 2, rect));
    });

    testWidgets('jumpToPageAtRect：高亮在頁面上半部、頂端已可見 → 維持頂端', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.05, right: 0.5, bottom: 0.08);

      PdfReaderView.jumpToPageAtRect(h.key, 2, rect);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[2].top - _margin, 1e-3));
    });

    testWidgets('showTemporaryHighlight（開書與就地跳轉路徑）：同樣自動帶到高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);

      PdfReaderView.jumpToPage(h.key, 1); // applyTo(shouldNavigate: true) 先跳頁
      PdfReaderView.showTemporaryHighlight(h.key, 1, rect);
      await tester.pump();
      expect(_visiblePages(c), [2]);
      expectVisible(c, docRect(c, 1, rect));
      expect(find.byKey(const Key('pdf_reader_jump_highlight_1')), findsOneWidget);
    });

    testWidgets('showTemporaryHighlight 的目標頁不是目前單元：先換到該單元再定位', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);

      PdfReaderView.showTemporaryHighlight(h.key, 3, rect); // 目前在第 1 頁
      await tester.pump();
      expect(_visiblePages(c), [4]);
      expectVisible(c, docRect(c, 3, rect));
    });

    testWidgets('高亮比可視高度還高：上緣貼齊可視上緣', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      // 可視文件高度 = 200 / 基準 ≈ 314；高亮高 0.6 * 792 ≈ 475 → 比可視高度高。
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.8);

      PdfReaderView.jumpToPageAtRect(h.key, 1, rect);
      expect(c.visibleRect.top,
          closeTo(docRect(c, 1, rect).top, 1e-2));
    });

    testWidgets('裁切模式：以裁切後的頁面座標換算高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          fit: PdfFitMode.fitWidth,
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.0, top: 0.0, right: 1.0, bottom: 0.5),
        ),
      );
      // 原頁面座標 top 0.4～0.45 落在裁切範圍（上半）內；裁切後的相對位置為 0.8～0.9。
      const rect = PercentRect(left: 0.1, top: 0.4, right: 0.5, bottom: 0.45);
      const relative = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.9);

      PdfReaderView.jumpToPageAtRect(h.key, 1, rect);
      expectVisible(c, docRect(c, 1, relative));
    });

    testWidgets('裁切模式：高亮完全落在裁切範圍外：不調整位置、不拋例外', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          fit: PdfFitMode.fitWidth,
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.0, top: 0.0, right: 1.0, bottom: 0.5),
        ),
      );
      const outside = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.9);
      PdfReaderView.jumpToPageAtRect(h.key, 1, outside);
      expect(_visiblePages(c), [2]);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[1].top - _margin, 1e-3));
    });

    testWidgets('雙頁 spread 內的第二頁：以該頁在 spread 內的位置換算', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          fit: PdfFitMode.fitWidth,
          dualMode: DualPageMode.always,
        ),
      );
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);
      PdfReaderView.jumpToPageAtRect(h.key, 1, rect); // 第 2 頁屬於 spread [1, 2]
      expectVisible(c, docRect(c, 1, rect));
    });

    testWidgets('連續捲動：jumpToPageAtRect 退化為 jumpToPage，跳到目標頁且不拋例外（不套用逐頁高亮規則）', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      await h.open(tester, h.app(turnMode: PdfPageTurnMode.scroll));
      PdfReaderView.jumpToPageAtRect(
        h.key,
        2,
        const PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.85),
      );
      // 連續捲動走原本的 jumpToPage（含換頁動畫），等頁碼落定後確認確實跳到第 3 頁。
      final c = h.controller(tester);
      await pumpUntilPdfReady(tester,
          condition: () => c.pageNumber == 3, maxIterations: 10);
      expect(c.pageNumber, 3);
    });
  });
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：編譯失敗，`The method 'jumpToPageAtRect' isn't defined for the type 'PdfReaderView'`。

- [x] **Step 3：實作**

`app/lib/reader/pdf_reader_view.dart`：

(a) 在 `showTemporaryHighlight` 靜態方法之前加入（與其他靜態 helper 同風格）：

```dart
  /// 跳到第 [pageIndex] 頁（0-indexed）並讓 [rect]（頁面百分比座標，例如搜尋結果）看得到
  /// （epic-56 Issue 5 規則 7）：逐頁下落在目標單元後，若高亮不在頂端對齊的視窗內，
  /// 視窗自動帶到看得到高亮的位置；連續捲動下等同 [jumpToPage]。[key] 對應的 State 若
  /// 尚未掛載，靜默忽略。
  static void jumpToPageAtRect(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex,
    PercentRect rect,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._jumpToPage(pageIndex);
      state._revealHighlight(pageIndex, rect);
    }
  }

```

(b) 把 `_setJumpHighlight` 改為（其餘不變，只在 `setState` 後追加）：

```dart
  void _setJumpHighlight(int? pageIndex, PercentRect? rect) {
    if (!mounted) return;
    setState(() {
      _jumpHighlightPageIndex = pageIndex;
      _jumpHighlightRect = rect;
    });
    // 規則 7：顯示暫態高亮時，逐頁下自動把視窗帶到看得到高亮的位置。
    if (pageIndex != null && rect != null) _revealHighlight(pageIndex, rect);
  }
```

(c) 在 `_stepPagedUnit` 之後新增：

```dart
  /// 規則 7：逐頁下確保 [rect]（第 [pageIndex] 頁的百分比座標）在視窗內——頂端已可見則維持
  /// 頂端，否則垂直置中並夾範圍，高亮比可視高度高則上緣貼齊。目標頁不在目前單元時先換到
  /// 該單元。非逐頁、版面尚未就緒、頁碼超界、或（裁切下）高亮完全在裁切範圍外時不動作。
  void _revealHighlight(int pageIndex, PercentRect rect) {
    final paged = _paged;
    if (!_pagedActive || paged == null || !_controller.isReady) return;
    if (pageIndex < 0 || pageIndex >= paged.pageRects.length) return;
    final viewSize = _viewSize;
    if (!viewSize.isFinite || viewSize.width <= 0 || viewSize.height <= 0) return;

    final pageRelative = _cropEnabled
        ? originalToCropRelativePercent(rect: rect, cropRect: widget.pdfCropRect)
        : rect;
    if (pageRelative == null) return;

    final unit = paged.pageToUnit[pageIndex];
    if (unit != _currentPagedUnit()) _goToPagedUnit(unit);

    // 百分比 → 文件座標：以「頁面」矩形換算（雙頁時頁面在 spread 單元內）。
    final page = paged.pageRects[pageIndex];
    final highlight = Rect.fromLTRB(
      page.left + pageRelative.left * page.width,
      page.top + pageRelative.top * page.height,
      page.left + pageRelative.right * page.width,
      page.top + pageRelative.bottom * page.height,
    );
    final zoom = _controller.currentZoom;
    final top = pagedTopForHighlight(
      unitContent: paged.unitRects[unit].inflate(_pdfPageMargin),
      highlight: highlight,
      viewHeight: viewSize.height,
      zoom: zoom,
    );
    unawaited(_controller.goToPosition(
      documentOffset: Offset(_controller.visibleRect.left, top),
      zoom: zoom,
      duration: Duration.zero,
    ));
  }
```

(d) `app/lib/screens/reader_screen.dart`：兩處 PDF 內文搜尋的跳轉改走新 helper。

- `_runPdfSearch`（約 1512 行）把

```dart
      PdfReaderView.jumpToPage(_pdfReaderViewKey, matches[currentIndex].pageIndex);
```

改為

```dart
      PdfReaderView.jumpToPageAtRect(
        _pdfReaderViewKey,
        matches[currentIndex].pageIndex,
        matches[currentIndex].rect,
      );
```

- `_goToPdfSearchMatch`（約 1529 行）把

```dart
    PdfReaderView.jumpToPage(_pdfReaderViewKey, _pdfSearchMatches[next].pageIndex);
```

改為

```dart
    PdfReaderView.jumpToPageAtRect(
      _pdfReaderViewKey,
      _pdfSearchMatches[next].pageIndex,
      _pdfSearchMatches[next].rect,
    );
```

（`ReaderJumpTarget.applyTo` 不需改：`shouldNavigate: true` 先 `jumpToPage`，接著 `showTemporaryHighlight` 已會自動定位；開書當下 `shouldNavigate: false` 時單元已由 `initialPageIndex` 定位，同樣由 `showTemporaryHighlight` 定位。）

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart`
Expected：全數 PASS（Task 2 後 34 例＋本 Task 9 例＝43）。

排查順序（**不要**調整測試數值去遷就實作）：
1. 裁切案例失敗：確認 `originalToCropRelativePercent` 對 `cropRect` 的換算與測試的 `relative` 相符（若函式的語意是「相對裁切矩形的比例」，`top 0.4 → 0.4 / 0.5 = 0.8`；請以函式實際行為重算預期，並在計畫外記錄）。
2. `showTemporaryHighlight` 案例中 `pdf_reader_jump_highlight_1` 找不到：該 overlay 只在目標頁被繪製時存在；確認視窗已在第 2 頁。
3. 雙頁案例失敗：確認用的是 `paged.pageRects[pageIndex]`（頁面矩形）而不是單元矩形。

- [x] **Step 5：確認既有搜尋與跳轉測試零回歸**

Run：`flutter test test/reader/pdf_reader_view_jump_highlight_test.dart test/reader/pdf_reader_view_search_test.dart test/screens/reader_screen_test.dart`
Expected：全數 PASS，未修改任何既有測試。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/pdf_reader_view_paginated_test.dart
git commit -m "feat(reader): PDF 逐頁搜尋結果帶高亮跳轉，視窗自動帶到看得到高亮（epic-56 Issue 5）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：頁內垂直拖曳的閱讀活動回報

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`（建構參數、State 欄位、外層 `Listener`）
- Modify：`app/lib/screens/reader_screen.dart`（`PdfReaderView(...)` 傳入回呼）
- Test：`app/test/reader/pdf_reader_view_paginated_test.dart`（`_Harness.app` 加參數、追加 `group`）
- Test：`app/test/screens/reader_screen_stats_activity_test.dart`（新增 1 個案例）

**Interfaces：**
- Consumes：Task 1 的 `PagedDragActivityAccumulator`；既有 `_activePointerCount`、`_selectionDrag`、`_pagedActive`、`_currentPagedUnit()`。
- Produces：`final VoidCallback? onReadingActivity;`（`PdfReaderView` 建構參數，預設 `null`，無參數回呼）。

- [ ] **Step 1：寫失敗測試**

(a) `pdf_reader_view_paginated_test.dart` 的 `_Harness`：加欄位與參數。`int activity = 0;` 加在 `final pages = <int>[];` 之後；`app(...)` 的參數列新增 `bool reportActivity = true,`，`PdfReaderView(...)` 內新增：

```dart
          onReadingActivity: reportActivity ? () => activity++ : null,
```

(b) `main()` 結尾追加：

```dart
  group('頁內垂直拖曳回報閱讀活動（規則 9，Review Focus 5）', () {
    Future<void> drag(
      WidgetTester tester,
      List<Offset> moves, {
      Offset? start,
    }) async {
      final g = await tester.startGesture(
          start ?? tester.getCenter(find.byType(PdfViewer)));
      for (final m in moves) {
        await g.moveBy(m);
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('逐頁：垂直拖曳 60 像素 → 回報至少一次', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, greaterThanOrEqualTo(1));
    });

    testWidgets('同一手勢分兩段各 12 像素：累積 24 → 回報一次', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -12), const Offset(0, -12)]);
      expect(h.activity, 1);
    });

    testWidgets('未達 20 像素不回報；兩次各 10 像素的分開手勢不累積（換手勢歸零）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -10)]);
      await drag(tester, [const Offset(0, -10)]);
      expect(h.activity, 0);
    });

    testWidgets('水平拖曳不回報', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(-80, 0)]);
      expect(h.activity, 0);
    });

    testWidgets('兩指同時按下（縮放）不回報', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final center = tester.getCenter(find.byType(PdfViewer));
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await g1.moveBy(const Offset(0, -60));
      await g2.moveBy(const Offset(0, -60));
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.activity, 0);
    });

    testWidgets('連續捲動模式不由 PdfReaderView 回報（由頁碼變化與既有路徑處理）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(
          tester, h.app(turnMode: PdfPageTurnMode.scroll, fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, 0);
    });

    testWidgets('未傳 onReadingActivity（既有呼叫端）：拖曳不拋例外', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth, reportActivity: false));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, 0);
    });
  });
```

(c) `reader_screen_stats_activity_test.dart`：在「PDF 長按框選算閱讀活動」案例之後新增（比照其寫法）：

```dart
  testWidgets('PDF 頁內垂直拖曳回報的閱讀活動接到閱讀時間（長頁上只用拖曳閱讀不會凍結計時）',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.onReadingActivity, isNotNull);

    await tester.pump(const Duration(seconds: 10));
    pdfView.onReadingActivity?.call();
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart test/screens/reader_screen_stats_activity_test.dart`
Expected：編譯失敗，`No named parameter with the name 'onReadingActivity'`。

- [ ] **Step 3：實作**

`app/lib/reader/pdf_reader_view.dart`：

(a) 在 `final ValueChanged<PdfPageInfo>? onPageChanged;` 之後加入欄位，建構子 `this.onPageChanged,` 之後加入 `this.onReadingActivity,`：

```dart
  /// 逐頁下頁內垂直拖曳每累積 20 邏輯像素呼叫一次（無參數；epic-56 Issue 5 規則 9），
  /// 讓長頁上只用拖曳閱讀、頁碼沒變的期間閱讀時間仍持續計算。`ReadingSession` 由
  /// `ReaderScreen` 私有持有，本 widget 不引用它，只透過這個回呼通知。
  final VoidCallback? onReadingActivity;
```

(b) `_PdfReaderViewState` 內（`_activePointerCount` 欄位附近）加入：

```dart
  /// 規則 9：頁內垂直拖曳的閱讀活動累積器（換手勢、換單元歸零）。
  final _dragActivity = PagedDragActivityAccumulator();
```

(c) 外層 `Listener` 改為（`onPointerUp`、`onPointerCancel` 不變；`onPointerDown` 補歸零、新增 `onPointerMove`）：

```dart
        Listener(
          onPointerDown: (_) {
            _activePointerCount++;
            if (_activePointerCount == 1) _dragActivity.reset(); // 新手勢：歸零
            if (_activePointerCount >= 2) _cancelSelectionDrag();
          },
          onPointerMove: (event) {
            // 只算逐頁下「單指、非框選」的垂直位移；水平位移、兩指縮放、連續捲動都不算。
            final report = widget.onReadingActivity;
            if (report == null || !_pagedActive) return;
            if (_activePointerCount != 1 || _selectionDrag != null) return;
            final unit = _currentPagedUnit();
            if (unit == null) return;
            if (_dragActivity.add(event.delta.dy, unit: unit)) report();
          },
```

（原有 `onPointerUp`／`onPointerCancel`／`child: LayoutBuilder(...)` 保留。）

`app/lib/screens/reader_screen.dart`：`PdfReaderView(` 建構處（`onPageChanged: (info) {` 之前）加入：

```dart
          // epic-56 Issue 5 規則 9：頁內垂直拖曳算閱讀活動（PdfReaderView 不持有 ReadingSession）。
          onReadingActivity: () => _session.recordActivity(),
```

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_reader_view_paginated_test.dart test/screens/reader_screen_stats_activity_test.dart`
Expected：全數 PASS（widget 43＋7＝50；統計測試新增 1）。

排查順序（**不要**調整測試數值去遷就實作）：
1. 回報次數永遠為 0：`debugPrint` `onPointerMove` 是否被呼叫；若沒有，檢查 3×3 熱區 `TapZoneDetector` 是否改成非 translucent（本計畫的前提見「查證過的事實」）。
2. 兩指案例回報了：確認 `_activePointerCount` 在第二指按下時為 2（`onPointerDown` 先遞增）。
3. 「分兩段 12」回報 0 或 2：確認累積器餘數保留（`% threshold`）與 `reset()` 只在 `_activePointerCount == 1` 的 `onPointerDown` 呼叫。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/pdf_reader_view_paginated_test.dart app/test/screens/reader_screen_stats_activity_test.dart
git commit -m "feat(reader): PDF 逐頁頁內垂直拖曳回報閱讀活動（epic-56 Issue 5）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：回歸確認、收尾與文件

**Files：**
- Modify：`docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`、`docs/epics.md`

**Interfaces：**
- Consumes：Task 1～4 全部。
- Produces：無（最後一個 Task）。

- [ ] **Step 1：確認朗讀沒有 PDF 路徑、搜尋跳轉都已涵蓋**

以下指令用 Git Bash 執行（PowerShell 沒有 `grep`；等價指令為 `Select-String -Path lib/screens/reader_screen.dart -Pattern "<模式>"`）：

```bash
grep -n "PDF 目前結構性沒有 TTS" lib/screens/reader_screen.dart
grep -n "PdfReaderView.jumpToPage\|PdfReaderView.jumpToPageAtRect" lib/screens/reader_screen.dart
```

Expected：第一個找到 `onTtsTap: null` 那行（PDF 沒有朗讀，spec 的朗讀規則本 Issue 無需程式碼）；第二個中，搜尋結果相關的兩處（`_runPdfSearch`、`_goToPdfSearchMatch`）為 `jumpToPageAtRect`，其餘（目錄、書籤、縮圖、頁碼輸入、進度條）仍是 `jumpToPage`。若發現其他「帶高亮矩形」的 PDF 跳轉仍用 `jumpToPage`，停下來回報，不要自行處理。

- [ ] **Step 2：跑經由 `ReaderScreen` 掛載 PDF 的既有測試**

```bash
flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_stats_activity_test.dart test/reader/
```

Expected：全數 PASS。

- [ ] **Step 3：全專案靜態檢查與 l10n**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：`No issues found!`；l10n 檢查 PASS（本 Issue 沒有新增字串）。

- [ ] **Step 4：完整測試（只在這個時機跑一次）**

```bash
flutter test
```

用 `run_in_background` 執行（約 6 分鐘，必須在 `app/` 目錄下）。Expected：0 失敗；通過數＝Task 0 記下的基準＋本 Issue 新增案例（規則 29＋widget 23＋統計 1＝53），以實測為準。

- [ ] **Step 5：更新文件**

`docs/epics/epic-56-pdf-paginated-reading/epic.md`：

- 狀態行改為「Issue 1～4 已合併，Issue 5 開發完成待合併，Issue 6 待寫計畫」。
- 在「開發記錄」末尾新增「**2026-10-0X Issue 5 實作完成**」條目，內容須包含：做法摘要（`pagedRelativeStep`、`pagedTopForHighlight`、`PagedDragActivityAccumulator` 三組規則；`_stepPagedUnit` 以螢幕像素偏移判斷；`_goToPagedUnit(atBottom:)`；`jumpToPageAtRect` 與 `showTemporaryHighlight` 共用 `_revealHighlight`；`onReadingActivity` 接線；PDF 內文搜尋跳轉一併改走 `jumpToPageAtRect`）；實測的測試數量與全套通過數；與計畫的差異（Ruling，若有）；**待真機確認項目**：10% 重疊量與步距手感、頁底／頁頂 1 像素容許、往回落底端的觀感、搜尋跳轉到長頁下半部時高亮是否可見（Fit Width 與放大後）、長頁上只用拖曳閱讀時閱讀時間是否持續計算（統計頁面比對）、20 像素活動門檻。
- 提醒：Issue 6（左右滑動翻頁）仍待做，須 Issue 1～6 全數完成才可發版；Issue 4 最終審查延後的 Minor 仍未處理（見先前記錄）。

`docs/epics/epic-56-pdf-paginated-reading/issues.md`：Issue 5 的 `**Status:** in-progress` 改為 `**Status:** done（PR #待填）`——**PR 編號在 PR 建立後才寫入**，建立 PR 前保留 `in-progress`。`docs/epics.md` 第 57 列同步。

不更新 `CLAUDE.md`（Epic 56 全部 Issue 完成、可發版時再一次補 `PdfReaderView` 功能描述）。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-56-pdf-paginated-reading/epic.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics.md
git commit -m "docs(epic-56): Issue 5 長頁步進、帶高亮跳轉與閱讀活動回報開發記錄

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## 計畫審查修訂記錄（2026-10-04，審查報告 `reviews/review-plan-issue-5.md`）

- **I-1（採納）**：`pagedTopForHighlight` 的「頂端已可見」判斷加 1e-4 容許誤差（與 `_pagedAxis` 的 1e-6 同風格），補貼底緣浮點誤差的單元測試。
- **M-1（採納，調整寫法）**：連續捲動測試改為等 `pageNumber == 3` 後斷言（該路徑含換頁動畫，頁碼可能晚一幀）。
- **M-2（部分採納）**：指令本來就以 Git Bash 執行，補註明與等價的 PowerShell 指令。
- **M-3（採納）**：累積器建構子 `assert(threshold > 0)`，補測試。
- 測試數量同步更新：規則 29、widget 23、統計 1，合計新增 53。

## Self-Review 紀錄

**1. Spec／Issue 覆蓋：**
- 規則 3、4 完整版（頁內步進、到頁底換頁、往回落上一單元底端、逐屏往回、1 像素容許、第一／最後單元）→ Task 1 `pagedRelativeStep`／`startAtBottom`、Task 2 `_stepPagedUnit`／`_goToPagedUnit(atBottom:)`。
- 規則 5（10% 重疊，具名常數）→ Task 1 `kPagedStepOverlapFraction`。
- 規則 7（三種情況）→ Task 1 `pagedTopForHighlight`、Task 3 `_revealHighlight`；入口：`showTemporaryHighlight`（開書與就地跳轉）、`jumpToPageAtRect`（PDF 內文搜尋）。
- 規則 9（累積 20 像素、換手勢或換單元歸零）與接線合約（`onReadingActivity` 無參數、`ReadingSession` 不進 `PdfReaderView`、`ReaderScreen` 接到既有 `recordActivity`）→ Task 1 累積器、Task 4。
- 朗讀沿用安全視窗規則 → PDF 沒有 TTS，Task 5 Step 1 以 grep 確認，無程式碼。
- 測試要求：步進序列（頁高 2000、可視 800、重疊 80）、上一單元不比螢幕高落點 0、剛好等高、1 像素容許、第一／最後單元、規則 7 三種情況、規則 9 累積與歸零 → Task 1；Fit Width 長頁熱區連續點擊序列、搜尋跳轉高亮落在視窗內、頁內拖曳觸發活動回報 → Task 2、3、4；`ReadingSession` 既有測試不改而通過 → Task 5 Step 2、4。
- 驗收標準（單手連續讀完長頁並換頁、往回逐屏退、搜尋跳到長頁下半部高亮可見、只用拖曳閱讀時閱讀時間持續計算）→ 自動測試涵蓋行為，真機項目列於 Task 5 Step 5。

**2. 佔位符掃描：** 無 TBD／TODO；PR 編號須待 PR 建立後才有，已在 Task 5 Step 5 明示處理方式。

**3. 型別一致性：** `PagedStep`／`PagedStepKind`（`scroll`／`changeUnit`／`none`，欄位 `scrollOffset`／`landAtBottom`）、`pagedRelativeStep`、`pagedTopForHighlight`、`PagedDragActivityAccumulator.add(dy, unit:)`／`reset()`、`clampPagedViewport(startAtBottom:)`、`_goToPagedUnit(int, {bool atBottom})`、`_revealHighlight(int, PercentRect)`、`jumpToPageAtRect`、`onReadingActivity` 在 Task 1～4 的名稱與簽章一致。

**4. Review Focus：** 5 條皆有對應 Task 測試（見上方各條）。

**已知風險（執行時請特別留意）：**
- 裁切案例的預期值假設 `originalToCropRelativePercent` 以裁切矩形為基準做線性換算（`0.4 / 0.5 = 0.8`）；Task 3 Step 4 已寫明若函式語意不同時的處置。
- 外層 `Listener.onPointerMove` 能否收到熱區疊層下的拖曳，依賴 `TapZoneDetector` 為 translucent（已查證），Task 4 Step 4 寫明失敗排查。
- 步進與高亮定位都依賴 Issue 4 的 `normalizeMatrix` 把結果夾回單元；若某些位置被夾制改寫，測試的「最大捲動量」斷言會暴露。
