# Issue 6：左右滑動翻頁與框選衝突處理 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 逐頁模式下，單指快速左右滑動且頁面沒有橫向溢出時，直接換到上一個或下一個單元（落新單元頂端、縮放回基準）；方向依雙頁方向鏡像；放大後有橫向溢出、長按框選進行中、兩指縮放、太慢或太斜的手勢都不翻頁，交給一般平移。

**Architecture：** 在純 Dart 的 `pdf_paginated_rules.dart` 新增三個具名門檻常數、`pagedHasHorizontalOverflow`（橫向是否溢出）與 `pagedSwipeIntent`（一次手勢是「下一個／上一個／不是滑動」）。`PdfReaderView` 沿用外層 `Listener`：按下時記下起點與時間（`clock.now()`），移動時偵測框選與多指並標記作廢，最後一指放開時把位移、時長、橫向溢出、框選狀態餵給 `pagedSwipeIntent`，成立就以 `pagedAdjacentUnit` 找目標單元並呼叫既有 `_goToPagedUnit`（預設落頂端、基準縮放）。不新增對外參數，`ReaderScreen` 不改。

**Tech Stack：** Flutter／Dart、`pdfrx` 2.4.7、`package:clock`、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（規則 8；「導覽入口對應」的左右滑動、框選守衛列）；工單見 `issues.md` Issue 6。前置：Issue 4、5 已合併（PR #317、#318），本計畫建立在 `_paged`、`_goToPagedUnit`、`pagedAdjacentUnit`、`_viewSize`、外層 `Listener` 與 `_activePointerCount` 之上。

## 查證過的事實（本計畫的依據，執行者不必重查，但若行為不符請停下來回報）

- **外層 `Listener` 已存在**（`pdf_reader_view.dart` 的 `build`，`Stack` 第一個子節點）：`onPointerDown` 先 `_activePointerCount++`、再 `_dragActivity.reset()`、2 指以上呼叫 `_cancelSelectionDrag()`；`onPointerMove` 有 Issue 5 的閱讀活動累積；`onPointerUp`／`onPointerCancel` 遞減 `_activePointerCount` 並歸零累積器。本計畫在這四個回呼各加一行呼叫，不改既有行為。
- **子節點的 pointer 事件先於父節點 `Listener`**：框選長按偵測器（`BounceTolerantLongPressDetector`）在較深的節點，放開時它可能已先呼叫 `_finishSelectionDrag()` 把 `_selectionDrag` 設回 `null`。所以「框選進行過」必須在**移動途中**鎖存（`_swipeInvalid = true`），不能只在放開那一刻讀 `_selectionDrag`。
- **長按門檻是 `kLongPressTimeout`（500 毫秒）**，與滑動時長上限相同；`_selectionDrag` 只會在長按觸發後非 `null`。
- **`pdfrx` 的 `goToPosition(duration: Duration.zero)` 會先停掉慣性動畫**（`_goTo` 內呼叫 `_stopInteractiveViewerAnimation()`），所以放開手指後的慣性不會蓋掉換頁結果。真機仍須確認（列入待真機項目）。
- **無橫向溢出的單元，橫向平移已被 `_normalizePagedMatrix` 夾死**（`clampPagedViewport` 在該軸置中），所以未成立的手勢交給 pdfrx 一般平移不需要額外程式碼：沒有溢出時橫向不動、縱向仍可在長頁內平移。
- **Page-fit 與 Fit Width 恆沒有橫向溢出，真實比例（或放大後）才可能有**。Fit Width 時縮放後內容寬度剛好等於可視寬度，浮點誤差可能多出 1e-13，所以橫向溢出判定必須有容許值；本計畫沿用 `kPagedEdgeTolerance`（1 像素）。
- **雙頁方向的列舉**：`DualPageDirection { ltr, rtl }`（`dual_page_direction.dart`）；`PdfReaderView.dualPageDirection` widget 層預設為 `rtl`，產品值由 `ReaderScreen` 傳入。
- **座標單位**：`PointerEvent.position` 是全域邏輯像素，兩點相減即螢幕像素位移；`_controller.currentZoom` 是目前縮放，`_paged.unitRects[unit].inflate(_pdfPageMargin).size` 是單元含頁邊距的內容尺寸（與 Issue 5 的 `_unitCanScrollVertically` 同一寫法）。
- **fixture**：`test/fixtures/sample_multi_page.pdf`（每頁 612×792，至少 4 頁）、`sample_dual_page.pdf`（每頁 600 寬，`sample_dual_page` 在 300×900、雙頁 always 下第一個 spread 是第 1、2 頁，下一個是第 3、4 頁）。
- **測試用手勢**：用 `tester.startGesture`＋多次 `gesture.moveBy`（分段移動，讓底層縮放／平移辨識器有足夠的移動事件），不要用 `tester.drag`（會先多送一段 touch slop）。時間只會隨 `tester.pump(Duration)` 推進，所以時長案例是「移動後 `pump(hold)` 再放開」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **零回歸**：連續捲動（`pdfPageTurnMode: scroll`，widget 層預設）完全不受影響；Issue 4、5 既有測試不改而通過；框選與 2 指取消框選的既有行為不變。
- **規則 8（滑動判定）**：一次手勢要同時滿足才算滑動翻頁——水平位移至少 56 邏輯像素；水平位移至少為垂直位移的 2 倍；手勢時長不超過 500 毫秒；頁面沒有橫向溢出；沒有長按拖曳框選進行中。成立時：左到右（`ltr`）向左滑為下一個單元、向右滑為上一個；右到左（`rtl`）鏡像。落新單元頂端、縮放回基準（即 `_goToPagedUnit` 預設，**不**落底端——落底端只適用熱區／音量鍵的相對步進）。不成立的手勢交由一般平移處理。
- **邊界值**：位移「至少 56」＝ `>= 56`；「至少 2 倍」＝ `dx >= 2 × dy`；「不超過 500 毫秒」＝ `<= 500`。
- **單指才算**：任何時刻出現第二個觸控點，整個手勢作廢，直到所有手指放開、下一次單指按下才重新計。
- **門檻皆為具名常數**，註解標「初始值，待真機校準」；校準另立小工單，不在本 Issue 內調整。
- **時間戳記**：手勢起訖用 `package:clock` 的 `clock.now()`，不用裸 `DateTime.now()`（`pdf_reader_view.dart` 已 `import 'package:clock/clock.dart'`）。
- **守衛**：只在 `_pagedActive` 時處理；`widget.cropEditModeActive` 為 true 時不處理（裁切編輯模式維持既有導覽封鎖）；`_controller.isReady` 為 false 或 `_viewSize` 無效時不處理。
- **PdfReaderView 對外介面不變**：不新增建構參數，不改既有靜態 helper 簽章。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；多數原始檔是 CRLF，Edit 若因換行比對失敗，改用單行定位字串；工作目錄由工具指定，指令中不使用 `cd`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。
- **發版限制**：Epic 56 的 Issue 1～6 須同一版本一起發布；本 Issue 是最後一張。
- **spec 已確認事項**（`spec.md`「Further Notes」末條）：「水平滑動在長頁上直接跨頁、落新頁頂端」已於 2026-10-04 與使用者確認，採「直接跨頁」。只要沒有橫向溢出，不論頁面有沒有縱向溢出，水平滑動都直接跨單元；不做「長頁不跨頁」或「先頁內步進」。

## Review Focus

最可能咬到使用者、但 spec 沒有明說的情況（依可能性排序），每條都有對應測試：

1. **長按框選劃線時畫面誤翻頁。** 框選時手指會大幅橫向移動；放開時偵測器可能已先清掉框選狀態。→ Task 1 測 `selectionDragActive`；Task 2 以 widget 測「長按後橫向拖曳、放開，頁面不動」，實作上在移動途中鎖存。
2. **兩指縮放、或縮放後抬起一指時，剩下那一指的移動被當成滑動。** → Task 2 測兩指同時移動不換頁；實作上第二指按下即作廢整個手勢。
3. **放大後橫向有溢出，使用者想平移卻被翻頁；或 Fit Width 剛好滿版因浮點誤差被誤判成有溢出而永遠不能滑動換頁。** → Task 1 測 `pagedHasHorizontalOverflow` 的 1 像素容許與 Fit Width 的 `400/628` 縮放；Task 2 以真實比例測「滑動是平移、頁碼不變」。
4. **方向反了：右到左的書向右滑要下一頁；雙頁 spread 要以 spread 為單元。** → Task 1 測兩個方向的鏡像；Task 2 測 `ltr`／`rtl` 與雙頁 spread。
5. **長頁上滑動後落在新單元中段或繼承縮放；第一個單元往前滑、最後一個單元往後滑出錯。** → Task 2 在 Fit Width 長頁先頁內步進再滑動，確認落頂端與基準縮放；測第一／最後單元無動作。
6. **垂直為主的手勢（閱讀長頁的上下拖曳）、距離不足、太慢的手勢被當成翻頁。** → Task 1 測臨界值；Task 2 測斜向、短距離、太慢。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/pdf_paginated_rules.dart` | 修改 | 新增 3 個門檻常數、`PagedSwipeIntent`、`pagedHasHorizontalOverflow`、`pagedSwipeIntent`（檔尾追加） |
| `app/test/reader/pdf_paginated_rules_test.dart` | 修改 | 上述規則的具體數字單元測試（接縫 1） |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | 滑動追蹤欄位與三個方法、外層 `Listener` 四個回呼各加一行呼叫 |
| `app/test/reader/pdf_reader_view_paginated_test.dart` | 修改 | `_Harness.app` 補三個參數；新增「左右滑動翻頁」group（接縫 2） |
| `docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 狀態與開發記錄 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔、`issues.md` 與 `docs/epics.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-56-issue-6-swipe-turn`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-56/issue-6-swipe-turn`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [x] **Step 1：在 `main` 提交計畫**

先把 `issues.md` Issue 6 的 `**Status:** ready-for-agent` 改為 `**Status:** in-progress`；`docs/epics.md` 第 57 列「Issue 6 待寫計畫」改為「Issue 6 開發中」。然後（在儲存庫根目錄）：

```bash
git add docs/epics/epic-56-pdf-paginated-reading/plans/plan-issue-6.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics.md
git commit -m "docs(epic-56): Issue 6 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-56-issue-6-swipe-turn -b epic-56/issue-6-swipe-turn
```

之後在 `.worktrees/epic-56-issue-6-swipe-turn/app` 目錄下執行：

```bash
flutter pub get
```

預期：`Got dependencies!`。

- [x] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/reader/pdf_paginated_rules_test.dart test/reader/pdf_reader_view_paginated_test.dart
```

預期：全數通過。記下通過數（Issue 5 合併後規則 29＋既有、widget 約 26＋Issue 5 新增）。

---

### Task 1：純 Dart 規則——滑動判定與橫向溢出

**Files：**
- Modify：`app/lib/reader/pdf_paginated_rules.dart`（檔尾追加）
- Test：`app/test/reader/pdf_paginated_rules_test.dart`（`main()` 結尾追加兩個 `group`）

**Interfaces：**
- Consumes：既有 `kPagedEdgeTolerance`（1.0）、`DualPageDirection`（檔頭已 import）。
- Produces（Task 2 依賴，名稱與型別務必一致）：

```dart
const double kPagedSwipeMinDistance = 56.0;
const double kPagedSwipeDominanceRatio = 2.0;
const int kPagedSwipeMaxDurationMs = 500;

enum PagedSwipeIntent { none, next, previous }

bool pagedHasHorizontalOverflow({
  required Size contentSize,   // 單元含頁邊距的尺寸（文件座標）
  required double scale,       // 目前縮放
  required Size viewSize,
});

PagedSwipeIntent pagedSwipeIntent({
  required Offset delta,                 // 放開位置 − 按下位置（螢幕像素）
  required Duration duration,            // 放開時間 − 按下時間
  required bool hasHorizontalOverflow,
  required bool selectionDragActive,
  required DualPageDirection direction,
});
```

- [x] **Step 1：寫失敗測試**

在 `pdf_paginated_rules_test.dart` 的 `main()` 結尾（最後一個 `group` 之後、`}` 之前）加入：

```dart
  group('pagedHasHorizontalOverflow：橫向是否溢出（規則 8 前提）', () {
    test('Fit Width：縮放後寬度恰等於可視寬度 → 沒有溢出（浮點誤差不算）', () {
      expect(
        pagedHasHorizontalOverflow(
          contentSize: const Size(628, 808),
          scale: 400 / 628,
          viewSize: const Size(400, 200),
        ),
        isFalse,
      );
    });

    test('真實比例：內容 628 寬放進 400 寬 → 有溢出', () {
      expect(
        pagedHasHorizontalOverflow(
          contentSize: const Size(628, 808),
          scale: 1.0,
          viewSize: const Size(400, 200),
        ),
        isTrue,
      );
    });

    test('Page-fit：內容比可視範圍窄 → 沒有溢出', () {
      expect(
        pagedHasHorizontalOverflow(
          contentSize: const Size(628, 808),
          scale: 0.2475,
          viewSize: const Size(400, 200),
        ),
        isFalse,
      );
    });

    test('溢出剛好 1 像素（401 放進 400）視為沒有；1.5 像素才算有', () {
      expect(
        pagedHasHorizontalOverflow(
          contentSize: const Size(401, 100),
          scale: 1.0,
          viewSize: const Size(400, 200),
        ),
        isFalse,
      );
      expect(
        pagedHasHorizontalOverflow(
          contentSize: const Size(401.5, 100),
          scale: 1.0,
          viewSize: const Size(400, 200),
        ),
        isTrue,
      );
    });
  });

  group('pagedSwipeIntent：滑動判定（規則 8）', () {
    PagedSwipeIntent intent(
      Offset delta, {
      Duration duration = const Duration(milliseconds: 200),
      bool overflow = false,
      bool selecting = false,
      DualPageDirection direction = DualPageDirection.ltr,
    }) =>
        pagedSwipeIntent(
          delta: delta,
          duration: duration,
          hasHorizontalOverflow: overflow,
          selectionDragActive: selecting,
          direction: direction,
        );

    test('距離門檻：56 剛好成立、55.9 不成立', () {
      expect(intent(const Offset(-56, 0)), PagedSwipeIntent.next);
      expect(intent(const Offset(-55.9, 0)), PagedSwipeIntent.none);
    });

    test('垂直 2 倍門檻：dx 恰為 dy 的 2 倍成立，再多一點垂直就不成立；dy 正負無關', () {
      expect(intent(const Offset(-100, 50)), PagedSwipeIntent.next);
      expect(intent(const Offset(-100, -50)), PagedSwipeIntent.next);
      expect(intent(const Offset(-100, 50.1)), PagedSwipeIntent.none);
    });

    test('斜向（接近 45 度）與垂直為主：不成立', () {
      expect(intent(const Offset(-80, 80)), PagedSwipeIntent.none);
      expect(intent(const Offset(-10, 200)), PagedSwipeIntent.none);
    });

    test('時長門檻：500 毫秒成立、501 毫秒不成立、0 毫秒成立、負值不成立', () {
      expect(intent(const Offset(-100, 0), duration: const Duration(milliseconds: 500)),
          PagedSwipeIntent.next);
      expect(intent(const Offset(-100, 0), duration: const Duration(milliseconds: 501)),
          PagedSwipeIntent.none);
      expect(intent(const Offset(-100, 0), duration: Duration.zero),
          PagedSwipeIntent.next);
      expect(intent(const Offset(-100, 0), duration: const Duration(milliseconds: -1)),
          PagedSwipeIntent.none);
    });

    test('有橫向溢出：不成立（交給一般平移）', () {
      expect(intent(const Offset(-100, 0), overflow: true), PagedSwipeIntent.none);
    });

    test('長按拖曳框選進行中：不成立', () {
      expect(intent(const Offset(-100, 0), selecting: true), PagedSwipeIntent.none);
    });

    test('左到右：向左滑為下一個、向右滑為上一個', () {
      expect(intent(const Offset(-100, 0)), PagedSwipeIntent.next);
      expect(intent(const Offset(100, 0)), PagedSwipeIntent.previous);
    });

    test('右到左：方向鏡像，向右滑為下一個、向左滑為上一個', () {
      expect(intent(const Offset(100, 0), direction: DualPageDirection.rtl),
          PagedSwipeIntent.next);
      expect(intent(const Offset(-100, 0), direction: DualPageDirection.rtl),
          PagedSwipeIntent.previous);
    });

    test('沒有位移或位移非有限值：不成立', () {
      expect(intent(Offset.zero), PagedSwipeIntent.none);
      expect(intent(const Offset(double.nan, 0)), PagedSwipeIntent.none);
      expect(intent(const Offset(double.infinity, 0)), PagedSwipeIntent.none);
    });
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/pdf_paginated_rules_test.dart
```

預期：編譯失敗，`pagedHasHorizontalOverflow`、`pagedSwipeIntent`、`PagedSwipeIntent` 未定義。

- [x] **Step 3：實作**

在 `pdf_paginated_rules.dart` 檔尾（`PagedDragActivityAccumulator` 之後）追加：

```dart

// ── epic-56 Issue 6：左右滑動翻頁（規則 8）──

/// 規則 8：滑動翻頁的最小水平位移（邏輯像素）。初始值，待真機校準。
const double kPagedSwipeMinDistance = 56.0;

/// 規則 8：水平位移須至少為垂直位移的幾倍。初始值，待真機校準。
const double kPagedSwipeDominanceRatio = 2.0;

/// 規則 8：手勢時長上限（毫秒）。初始值，待真機校準。
const int kPagedSwipeMaxDurationMs = 500;

/// 一次手勢的判定結果：不是滑動、換到下一個單元、換到上一個單元。
enum PagedSwipeIntent { none, next, previous }

/// 縮放後單元內容是否比可視寬度寬（橫向可平移）。Fit Width 的縮放後寬度理論上等於
/// 可視寬度，浮點誤差不能算溢出，所以沿用 [kPagedEdgeTolerance]（1 像素）當容許值。
bool pagedHasHorizontalOverflow({
  required Size contentSize,
  required double scale,
  required Size viewSize,
}) {
  return contentSize.width * scale - viewSize.width > kPagedEdgeTolerance;
}

/// 規則 8：一次手勢是否為滑動翻頁。五個條件同時成立才回傳 [PagedSwipeIntent.next]
/// 或 [PagedSwipeIntent.previous]：沒有橫向溢出、沒有框選進行中、時長不超過
/// [kPagedSwipeMaxDurationMs]、水平位移至少 [kPagedSwipeMinDistance]、水平位移至少為
/// 垂直位移的 [kPagedSwipeDominanceRatio] 倍。
///
/// 方向：左到右（[DualPageDirection.ltr]）向左滑為下一個；右到左（rtl）鏡像。
PagedSwipeIntent pagedSwipeIntent({
  required Offset delta,
  required Duration duration,
  required bool hasHorizontalOverflow,
  required bool selectionDragActive,
  required DualPageDirection direction,
}) {
  if (hasHorizontalOverflow || selectionDragActive) return PagedSwipeIntent.none;
  if (duration.isNegative ||
      duration > const Duration(milliseconds: kPagedSwipeMaxDurationMs)) {
    return PagedSwipeIntent.none;
  }
  if (!delta.dx.isFinite || !delta.dy.isFinite) return PagedSwipeIntent.none;
  final dx = delta.dx.abs();
  final dy = delta.dy.abs();
  if (dx < kPagedSwipeMinDistance) return PagedSwipeIntent.none;
  if (dx < dy * kPagedSwipeDominanceRatio) return PagedSwipeIntent.none;
  final towardNext = direction == DualPageDirection.rtl ? delta.dx > 0 : delta.dx < 0;
  return towardNext ? PagedSwipeIntent.next : PagedSwipeIntent.previous;
}
```

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/pdf_paginated_rules_test.dart
```

預期：全數通過，新增 14 個案例（溢出 4＋滑動 10）。

- [x] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_paginated_rules.dart app/test/reader/pdf_paginated_rules_test.dart
git commit -m "feat(reader): PDF 逐頁滑動判定與橫向溢出規則（epic-56 Issue 6）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`PdfReaderView` 接上滑動翻頁

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`
- Test：`app/test/reader/pdf_reader_view_paginated_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `pagedSwipeIntent`、`pagedHasHorizontalOverflow`、`PagedSwipeIntent`；既有 `pagedAdjacentUnit`、`_goToPagedUnit`、`_currentPagedUnit`、`_paged`、`_viewSize`、`_controller`、`_selectionDrag`、`_activePointerCount`、`widget.dualPageDirection`、`widget.cropEditModeActive`。
- Produces：無對外介面；`PdfReaderView` 行為新增「逐頁下單指快速橫向滑動換單元」。

- [x] **Step 1：補測試 harness 並寫失敗測試**

在 `pdf_reader_view_paginated_test.dart`：

(a) 檔頭 import 補兩行（依字母順序放在對應位置）：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:flutter/gestures.dart';
```

(b) `_Harness.app({...})` 參數列補三個參數，並在 `PdfReaderView(...)` 傳入：

```dart
    DualPageDirection direction = DualPageDirection.rtl,
    bool selectionEnabled = false,
    bool cropEditModeActive = false,
```

```dart
          dualPageDirection: direction,
          onSelectionRectComputed: selectionEnabled ? (_) {} : null,
          cropEditModeActive: cropEditModeActive,
```

（`direction` 預設 `rtl` 與 widget 層預設一致，既有案例不受影響；框選手勢層只有在 `onSelectionRectComputed` 非 null 時才建構，所以預設 `false` 不改變既有案例。）

(c) 在 `main()` 結尾（頁內垂直拖曳 group 之後）新增 group：

```dart
  group('左右滑動翻頁（規則 8，Review Focus 1～6）', () {
    /// 單指從視窗中心分段移動 [total] 後停 [hold]（fake clock）再放開。分段是為了讓底層
    /// 平移／縮放辨識器有足夠的移動事件。
    Future<void> swipe(
      WidgetTester tester,
      Offset total, {
      Duration hold = const Duration(milliseconds: 100),
      int steps = 5,
    }) async {
      final g = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
      for (var i = 0; i < steps; i++) {
        await g.moveBy(total / steps.toDouble());
      }
      await tester.pump(hold);
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Page-fit、左到右：向左滑下一頁、向右滑回上一頁', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.ltr));
      expect(_visiblePages(c), [1]);

      await swipe(tester, const Offset(-120, 0));
      expect(_visiblePages(c), [2]);

      await swipe(tester, const Offset(120, 0));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('右到左：方向鏡像，向右滑下一頁、向左滑回上一頁', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.rtl));

      await swipe(tester, const Offset(120, 0));
      expect(_visiblePages(c), [2]);

      await swipe(tester, const Offset(-120, 0));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('Fit Width 長頁：頁內已捲下去後滑動，落新單元頂端、縮放回基準（Review Focus 5）',
        (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.fitWidth, direction: DualPageDirection.ltr));
      PdfReaderView.nextPage(h.key); // 頁內先捲一個螢幕
      await tester.pump();
      expect(c.visibleRect.top, greaterThan(c.layout.pageLayouts[0].top));

      await swipe(tester, const Offset(-120, 0));

      expect(_visiblePages(c), [2]);
      expect(c.visibleRect.top, closeTo(c.layout.pageLayouts[1].top - _margin, 1e-3));
      expect(c.currentZoom, closeTo(400 / (612 + _margin * 2), 1e-3));
    });

    testWidgets('第一個單元往前滑、最後一個單元往後滑：無動作', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.ltr));

      await swipe(tester, const Offset(120, 0)); // 向右滑＝上一個，已是第一個
      expect(_visiblePages(c), [1]);

      final last = c.pageCount;
      PdfReaderView.jumpToPage(h.key, last - 1);
      await tester.pump();
      expect(_visiblePages(c), [last]);
      await swipe(tester, const Offset(-120, 0)); // 向左滑＝下一個，已是最後一個
      expect(_visiblePages(c), [last]);
    });

    testWidgets('距離不足 40、斜向、太慢（600 毫秒）：都不換頁（Review Focus 6）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.ltr));

      await swipe(tester, const Offset(-40, 0));
      expect(_visiblePages(c), [1], reason: '距離不足');

      await swipe(tester, const Offset(-100, -80));
      expect(_visiblePages(c), [1], reason: '斜向（垂直超過水平的一半）');

      await swipe(tester, const Offset(-120, 0), hold: const Duration(milliseconds: 600));
      expect(_visiblePages(c), [1], reason: '太慢');
    });

    testWidgets('真實比例放大後橫向有溢出：滑動是平移、頁碼不變（Review Focus 3）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.actualSize, direction: DualPageDirection.ltr));
      final leftBefore = c.visibleRect.left;

      await swipe(tester, const Offset(-100, 0));

      expect(_visiblePages(c), [1]);
      expect(c.visibleRect.left, greaterThan(leftBefore + 50)); // 往右平移了
    });

    testWidgets('長按框選進行中橫向拖曳：不換頁（Review Focus 1）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester,
          h.app(
              fit: PdfFitMode.pageFit,
              direction: DualPageDirection.ltr,
              selectionEnabled: true));
      final g = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(-30, 0));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_visiblePages(c), [1]);
    });

    testWidgets('兩指同時移動（縮放）：不換頁（Review Focus 2）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.ltr));
      final center = tester.getCenter(find.byType(PdfViewer));
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-30, 0));
        await g2.moveBy(const Offset(-30, 0));
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_visiblePages(c), [1]);
    });

    testWidgets('兩指縮放後抬起一指，剩下的一指繼續快速橫移：仍不換頁（Review Focus 2）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(fit: PdfFitMode.pageFit, direction: DualPageDirection.ltr));
      final center = tester.getCenter(find.byType(PdfViewer));
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await g2.up(); // 回到單指
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-30, 0));
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_visiblePages(c), [1]);
    });

    testWidgets('連續捲動模式：橫向滑動不換頁（零回歸）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester,
          h.app(
              turnMode: PdfPageTurnMode.scroll,
              fit: PdfFitMode.fitWidth,
              direction: DualPageDirection.ltr));
      expect(c.pageNumber, 1);

      await swipe(tester, const Offset(-120, 0));

      expect(c.pageNumber, 1);
    });

    testWidgets('裁切編輯模式：滑動無效（維持既有導覽封鎖）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
          tester,
          h.app(
              fit: PdfFitMode.pageFit,
              direction: DualPageDirection.ltr,
              cropEditModeActive: true));

      await swipe(tester, const Offset(-120, 0));

      expect(_visiblePages(c), [1]);
    });

    testWidgets('雙頁模式：滑動以 spread 為單元（Review Focus 4）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
          direction: DualPageDirection.ltr,
        ),
      );
      expect(_visiblePages(c), [1, 2]);

      await swipe(tester, const Offset(-120, 0));
      expect(_visiblePages(c), [3, 4]);

      await swipe(tester, const Offset(120, 0));
      expect(_visiblePages(c), [1, 2]);
    });
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/pdf_reader_view_paginated_test.dart --plain-name "左右滑動翻頁"
```

預期：「向左滑下一頁」「右到左」「Fit Width 長頁」「雙頁」等會失敗（頁碼沒變）；「第一個單元往前滑」「太慢」「兩指」「連續捲動」「裁切編輯」「框選」這幾個「不換頁」案例在實作前就會通過，屬正常，它們的作用是實作後的回歸守衛。若「真實比例放大後」案例在實作前就通過，代表平移本來就生效，也屬正常。

- [x] **Step 3：實作**

在 `pdf_reader_view.dart`：

(a) 在 `final _dragActivity = PagedDragActivityAccumulator();` 之後加欄位與三個方法：

```dart

  // ── epic-56 Issue 6：逐頁左右滑動翻頁（規則 8）──

  /// 本次單指手勢的按下位置與時間（`clock.now()`，讓 FakeAsync 能推進）。
  Offset? _swipeStart;
  DateTime? _swipeStartTime;

  /// 本次手勢是否已不可能是滑動翻頁：出現第二指，或移動途中偵測到框選。放開時才讀
  /// `_selectionDrag` 不夠——框選偵測器在較深的節點，可能已先把它清回 null。
  bool _swipeInvalid = false;

  void _beginSwipeTracking(PointerDownEvent event) {
    if (_activePointerCount == 1) {
      _swipeStart = event.position;
      _swipeStartTime = clock.now();
      _swipeInvalid = false;
    } else {
      _swipeInvalid = true; // 第二指以上是縮放或平移，不是滑動翻頁
    }
  }

  void _trackSwipeMove() {
    if (_selectionDrag != null || _activePointerCount != 1) _swipeInvalid = true;
  }

  /// 最後一指放開（呼叫時 [_activePointerCount] 仍為 1）：判定是否為滑動翻頁。
  void _finishSwipeTracking(Offset end) {
    final start = _swipeStart;
    final startTime = _swipeStartTime;
    _swipeStart = null;
    _swipeStartTime = null;
    if (start == null || startTime == null || _swipeInvalid) return;
    if (_activePointerCount != 1) return;
    if (!_pagedActive || widget.cropEditModeActive || !_controller.isReady) return;
    final paged = _paged;
    final unit = _currentPagedUnit();
    final viewSize = _viewSize;
    if (paged == null || unit == null) return;
    if (!viewSize.isFinite || viewSize.width <= 0 || viewSize.height <= 0) return;

    final intent = pagedSwipeIntent(
      delta: end - start,
      duration: clock.now().difference(startTime),
      hasHorizontalOverflow: pagedHasHorizontalOverflow(
        contentSize: paged.unitRects[unit].inflate(_pdfPageMargin).size,
        scale: _controller.currentZoom,
        viewSize: viewSize,
      ),
      selectionDragActive: _selectionDrag != null,
      direction: widget.dualPageDirection,
    );
    if (intent == PagedSwipeIntent.none) return;
    final target = pagedAdjacentUnit(
      currentUnit: unit,
      unitCount: paged.unitCount,
      forward: intent == PagedSwipeIntent.next,
    );
    // 落新單元頂端、縮放回基準（規則 8）；已是第一／最後一個單元則無動作。
    if (target != null) _goToPagedUnit(target);
  }
```

(b) 外層 `Listener` 四個回呼各加一行（其餘不動）：

- `onPointerDown: (_) {` 改為 `onPointerDown: (event) {`，並在 `_dragActivity.reset(); // 新手勢或手指數改變：歸零（M-4）` 之後加：

```dart
            _beginSwipeTracking(event);
```

- `onPointerMove: (event) {` 的第一行（註解之前）加：

```dart
            _trackSwipeMove();
```

- `onPointerUp: (_) {` 改為 `onPointerUp: (event) {`，並在該區塊第一行（遞減 `_activePointerCount` 之前）加：

```dart
            _finishSwipeTracking(event.position);
```

- `onPointerCancel: (_) {` 區塊內加：

```dart
            _swipeStart = null;
            _swipeStartTime = null;
```

`_finishSwipeTracking` 必須在遞減 `_activePointerCount` 之前呼叫，因為它用 `_activePointerCount == 1` 確認「放開的是唯一一指」。

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/pdf_reader_view_paginated_test.dart test/reader/pdf_paginated_rules_test.dart
```

預期：全數通過（含 Issue 4、5 既有案例）。若有案例失敗，先判斷是哪一類，再回報，不要改測試預期：

- 「真實比例放大後」的 `visibleRect.left` 沒有增加：代表測試手勢沒有真的平移。回報，並附 `c.visibleRect` 前後值。
- 「Fit Width 長頁」落點不是頂端：代表放開後慣性動畫蓋掉了換頁。回報，並附 `c.visibleRect.top`。這是 pdfrx 行為與查證不符的情況，須停下來討論（可能的對策是改到下一個 frame 再換頁，但本計畫不預先決定）。
- 既有案例（Issue 5 的拖曳活動、M-3／M-4）失敗：代表新增的一行呼叫影響了既有邏輯，回頭檢查插入位置。

- [x] **Step 5：確認異動觸及的其他測試**

```bash
flutter test test/reader/pdf_reader_view_selection_test.dart test/reader/pdf_reader_view_filters_test.dart test/screens/reader_screen_stats_activity_test.dart
```

預期：全數通過（外層 `Listener` 與框選、裁切編輯、閱讀活動接線相關）。

- [x] **Step 6：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：`No issues found!`，l10n 兩項 PASS。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_paginated_test.dart
git commit -m "feat(reader): PDF 逐頁左右滑動翻頁，框選與縮放時不誤翻（epic-56 Issue 6）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：全套驗證與文件

**Files：**
- Modify：`docs/epics/epic-56-pdf-paginated-reading/epic.md`、`docs/epics/epic-56-pdf-paginated-reading/issues.md`

**Interfaces：**
- Consumes：Task 1、2 的成果。
- Produces：可發 PR 的狀態與開發記錄。

- [ ] **Step 1：執行完整測試**

在 `app/` 目錄下（約 6 分鐘，用 `run_in_background`）：

```bash
flutter test
```

預期：全數通過，無失敗。記下通過數與略過數。

- [ ] **Step 2：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：`No issues found!`，l10n 兩項 PASS。

- [ ] **Step 3：更新 `epic.md` 開發記錄**

在檔尾追加（數字以 Step 1 實際結果為準，不要照抄範例）：

```markdown

**2026-10-XX Issue 6 實作完成**（分支 `epic-56/issue-6-swipe-turn`；計畫見 `plans/plan-issue-6.md`）

- 做法：純 Dart `pdf_paginated_rules.dart` 新增 `pagedHasHorizontalOverflow`（超過 `kPagedEdgeTolerance` 才算溢出）與 `pagedSwipeIntent`（規則 8；常數 `kPagedSwipeMinDistance`＝56、`kPagedSwipeDominanceRatio`＝2、`kPagedSwipeMaxDurationMs`＝500，皆標初始值待真機校準）。`PdfReaderView` 沿用外層 `Listener`：按下記起點與 `clock.now()`、第二指或移動途中偵測到框選即作廢、最後一指放開時判定並以 `pagedAdjacentUnit`＋`_goToPagedUnit` 換單元（落頂端、基準縮放）；不新增對外參數，`ReaderScreen` 未改。
- 測試：新增規則 14＋widget 12＝26；全套 `flutter test` XXXX 通過、X 略過、0 失敗；`flutter analyze` 乾淨，l10n 雙檢查 PASS。
- 待真機確認項目：滑動手感與 56／2 倍／500 毫秒三個門檻；與長按框選、縮放平移的實際衝突；放開手指後 pdfrx 慣性動畫是否蓋掉換頁結果；長頁上橫向滑動直接跨頁的觀感（spec 備註要求拆 Issue 時與使用者確認，本計畫依 `issues.md` 現行寫法實作）；E-Ink 上滑動換頁的單次重繪。若門檻需調整，另立小工單。
- 提醒：Epic 56 的 Issue 1～6 至此全數開發完成，須同一版本一起發布；Issue 4 最終審查延後的 Minor 與 Issue 5 的 M-1 仍未處理（見先前記錄）。
```

`issues.md` 的 Issue 6 `**Status:**` 在 PR 合併後才改為 `done（PR #號碼）`，本 Task 不改。

- [ ] **Step 4：Commit 文件**

```bash
git add docs/epics/epic-56-pdf-paginated-reading/epic.md
git commit -m "docs(epic-56): Issue 6 左右滑動翻頁開發記錄

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5：交付審查**

回報完成狀態，等待使用者指示：先做程式審查（審查者產出報告存於 `reviews/`，不直接改程式），審查處理完再發 PR。
