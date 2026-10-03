# Issue 1：Fit 模式接上渲染（連續捲動路徑）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓設定面板的「Fit 模式」（Page-fit／Fit Width／真實比例）真正驅動 PDF 閱讀器的縮放基準（在既有連續捲動路徑下），並建立之後 Issue 4～6 要擴充的純 Dart「逐頁導覽規則」模組（本 Issue 只放縮放基準、頁內捲動範圍、對齊起點三條規則）。

**Architecture：** 新增純 Dart 規則檔 `pdf_paginated_rules.dart`（縮放基準、頁內最大捲動量、內容對齊起點、以及「單元＋頁邊距＋可視尺寸 → 夾住上限的縮放值」）。新增 `pdf_fit_size_delegate.dart`：繼承 `pdfrx` 公開的 `PdfViewerSizeDelegateLegacy`，覆寫「最小縮放」與「開書初始縮放」兩處，其餘行為（旋轉、版面變更時保留閱讀位置）沿用 `pdfrx` 原樣。`PdfReaderView` 新增可為空的 `pdfFitMode` 參數（`null`＝完全不干預，沿用 `pdfrx` 現行預設），`ReaderScreen` 一律傳入解析後的值；執行期切換 Fit 模式時由 widget 明確重套縮放。

**Tech Stack：** Flutter／Dart、`pdfrx` 2.4.7、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（規則 1、規則 2；「型別與偏好」「`PdfReaderView` 對外介面」「連續捲動 Fit 基準」）；工單見 `issues.md` Issue 1。

## 查證過的 `pdfrx` 事實（本計畫的依據，執行者不必重查，但若行為不符請停下來回報）

- 預設的 `PdfViewerSizeDelegateProviderLegacy`：開書初始縮放＝`coverScale`（約等於「以最寬那頁的寬度滿版」，因為整份文件高度很大）；最小縮放＝`min(coverScale, alternativeFitScale)`（`alternativeFitScale` 是「目前頁完整放進螢幕」）。也就是說**目前實際的預設是 Fit Width 起始，而不是 Page-fit**。
- 更換 `PdfViewerParams.sizeDelegateProvider` 時，`PdfViewer` 只會重建並 `init` 新的 delegate，**不會重新套用縮放、也不會立刻重算最小縮放**；必須由我們明確觸發（`invalidate()` 讓它重新排版，再自行設定縮放）。
- `goToPage()` 的縮放上限是「目前縮放」（只會縮小到剛好放進寬度，不會放大），所以翻頁不會破壞我們設定的基準。
- `PdfViewerController` 公開 `layout`、`viewSize`、`pageNumber`、`currentZoom`、`minScale`、`maxScale`、`coverScale`、`goToPosition(documentOffset:, zoom:, duration:)`。
- `PdfViewerParams.margin` 預設 8.0；`pdfrx` 計算「整頁放進螢幕」時是把頁面矩形各邊再加上這個邊距。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **零回歸**：`pdfFitMode` 為 `null`（widget 層預設）時，`PdfReaderView` 的行為必須與修改前完全相同；既有 `pdf_reader_view_*` 測試不得為了通過而修改。
- **只動連續捲動路徑**：逐頁幾何、翻頁模式偏好、頁內步進、滑動翻頁都不在本 Issue（見 `issues.md` Issue 2～6）。
- **規則 1（縮放基準）**：Page-fit＝寬高兩個維度各自的比例取較小者；Fit Width＝可視寬度除以內容寬度；真實比例＝固定 1.0（1 PDF point＝1 邏輯像素）；（連續捲動不強制不可縮到基準以下，見 spec 規則 1 與 epic.md 審查記錄 I-3）。連續捲動時基準以「開書當下（或切換 Fit 模式、視窗尺寸改變當下）的目前頁尺寸」換算，捲動途中不隨頁面重算。內容尺寸一律含 `pdfrx` 頁邊距（各邊加 `margin`）。
- **規則 2（頁內捲動範圍）**：縱向最大捲動量＝max(0，縮放後內容高度－可視高度)。
- **單元**：未開雙頁模式＝一頁（裁切時為裁切後矩形）；開雙頁模式＝一個 spread 的合併矩形。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用來編輯檔案；多數原始檔是 CRLF，Edit 的定位字串不要含換行。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **可視尺寸為 0（版面尚未量測）或內容尺寸為 0 時算出縮放 0／無限大，畫面全空或崩潰。** → Task 1 測 `fitZoomForUnit` 回傳 `null`；Task 2 測 delegate 在可視尺寸為 0 時退回 `pdfrx` 原本的指標，不丟例外。
2. **Fit Width 套在很小的頁面上，縮放超過 `pdfrx` 上限（8 倍）。** → Task 1／Task 2 測夾在上限。
3. **使用者手動放大後切換 Fit 模式，畫面沒有回到新模式的基準。** → Task 3 測「放大後切換」縮放回到新基準。
4. **雙頁與裁切下仍以單頁原尺寸算基準，導致 spread 被切掉或裁切後頁面沒放大。** → Task 2 測雙頁（基準以合併矩形算）與手動裁切（以裁切後矩形算）。
5. **沒傳 `pdfFitMode`（既有呼叫端與測試）時行為被悄悄改變。** → Task 2 測 `null` 時縮放等於 `pdfrx` 的 `coverScale`，且既有 `pdf_reader_view_*` 測試全數不改而通過。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/pdf_paginated_rules.dart` | 新增 | 純 Dart 規則：`fitBaseScale`、`maxVerticalScroll`、`fitOrigin`、`fitZoomForUnit`；Issue 4～6 會繼續擴充 |
| `app/test/reader/pdf_paginated_rules_test.dart` | 新增 | 規則的具體數字單元測試（接縫 1） |
| `app/lib/reader/pdf_fit_size_delegate.dart` | 新增 | `PdfFitSizeDelegateProvider`／`PdfFitSizeDelegate`：覆寫最小縮放與初始縮放 |
| `app/test/reader/pdf_fit_size_delegate_test.dart` | 新增 | 直接呼叫 delegate 的 `calculateMetrics`，不經 widget |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | 新增 `pdfFitMode` 參數、單元矩形解析、provider 接線、執行期切換重套縮放 |
| `app/test/reader/pdf_reader_view_fit_mode_test.dart` | 新增 | widget 接線測試（接縫 2） |
| `app/lib/screens/reader_screen.dart` | 修改 | 把 `resolved.pdfFitMode` 傳給 `PdfReaderView` |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增 2 個接線案例 |
| `docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-56-issue-1-fit-mode`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-56/issue-1-fit-mode`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [x] **Step 1：在 `main` 提交計畫**

先把 `issues.md` Issue 1 的 `**Status:** ready-for-agent` 改為 `**Status:** in-progress`，然後（在儲存庫根目錄，不需要 `cd`）：

```bash
git add docs/epics/epic-56-pdf-paginated-reading/plans/plan-issue-1.md docs/epics/epic-56-pdf-paginated-reading/issues.md
git commit -m "docs(epic-56): Issue 1 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-56-issue-1-fit-mode -b epic-56/issue-1-fit-mode
cd .worktrees/epic-56-issue-1-fit-mode/app && flutter pub get
```

預期：`Got dependencies!`。

- [x] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/reader/pdf_reader_view_*_test.dart test/screens/reader_screen_test.dart test/screens/pdf_settings_sheet_test.dart
```

預期：全數通過。記下通過數（Task 3 完成後，這幾個測試檔的案例數應為此數加上本 Issue 新增的案例；以實測為準）。

---

### Task 1：純 Dart 規則模組與單元測試

**Files：**
- Create：`app/lib/reader/pdf_paginated_rules.dart`
- Test：`app/test/reader/pdf_paginated_rules_test.dart`

**Interfaces：**
- Consumes：`PdfFitMode`（`lib/reader/pdf_fit_mode.dart`）、`DualPageDirection`（`lib/reader/dual_page_direction.dart`）。
- Produces（Task 2、3 依賴）：

```dart
double fitBaseScale({required PdfFitMode mode, required Size contentSize, required Size viewSize});
double maxVerticalScroll({required Size contentSize, required double scale, required Size viewSize});
Offset fitOrigin({required Size contentSize, required double scale, required Size viewSize, required DualPageDirection direction});
double? fitZoomForUnit({required PdfFitMode mode, required Rect unitRect, required double pageMargin, required Size viewSize, required double maxZoom});
```

`fitOrigin` 回傳「縮放後的內容左上角在可視區域座標系的位置」：Issue 4 的逐頁置中會用它；本 Issue 只用測試鎖定規則 1 的對齊語意，不在產品程式碼中呼叫。

- [x] **Step 1：寫失敗測試**

建立 `app/test/reader/pdf_paginated_rules_test.dart`：

```dart
import 'dart:ui';

import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_paginated_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const view = Size(400, 800);

  group('fitBaseScale：縮放基準（規則 1）', () {
    test('Page-fit：寬高各自的比例取較小者（寬度受限）', () {
      // 1000x500 放進 400x800：寬 0.4、高 1.6 → 0.4
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(1000, 500), viewSize: view),
        closeTo(0.4, 1e-9),
      );
    });

    test('Page-fit：高度受限', () {
      // 400x2000 放進 400x800：寬 1.0、高 0.4 → 0.4
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(400, 2000), viewSize: view),
        closeTo(0.4, 1e-9),
      );
    });

    test('Page-fit：寬高比例相同時兩者一致', () {
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(500, 1000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
    });

    test('Fit Width：可視寬度除以內容寬度，與高度無關', () {
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(500, 1000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(500, 100000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
    });

    test('Fit Width：內容比可視寬度窄時會放大', () {
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(200, 100), viewSize: view),
        closeTo(2.0, 1e-9),
      );
    });

    test('真實比例：恆為 1.0，不論內容與可視尺寸', () {
      expect(
        fitBaseScale(mode: PdfFitMode.actualSize, contentSize: const Size(1000, 3000), viewSize: view),
        1.0,
      );
      expect(
        fitBaseScale(mode: PdfFitMode.actualSize, contentSize: const Size(10, 10), viewSize: view),
        1.0,
      );
    });
  });

  group('maxVerticalScroll：頁內最大捲動量（規則 2）', () {
    test('縮放後內容比可視高度高：回傳差值', () {
      // 500x2000 縮放 0.8 → 高 1600，可視 800 → 800
      expect(
        maxVerticalScroll(contentSize: const Size(500, 2000), scale: 0.8, viewSize: view),
        closeTo(800, 1e-9),
      );
    });

    test('剛好等高：0', () {
      expect(
        maxVerticalScroll(contentSize: const Size(500, 1000), scale: 0.8, viewSize: view),
        closeTo(0, 1e-9),
      );
    });

    test('比可視高度矮：0，不為負', () {
      expect(
        maxVerticalScroll(contentSize: const Size(500, 500), scale: 0.8, viewSize: view),
        0,
      );
    });
  });

  group('fitOrigin：內容對齊起點（規則 1）', () {
    test('兩個維度都比可視範圍小：置中', () {
      expect(
        fitOrigin(
          contentSize: const Size(200, 100),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(100, 350),
      );
    });

    test('Fit Width 縱向溢出：橫向剛好滿版，縱向從頁頂開始', () {
      expect(
        fitOrigin(
          contentSize: const Size(500, 3000),
          scale: 0.8,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(0, 0),
      );
    });

    test('真實比例橫向溢出：左到右靠左（起點 0）', () {
      expect(
        fitOrigin(
          contentSize: const Size(1000, 3000),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(0, 0),
      );
    });

    test('真實比例橫向溢出：右到左靠右（右緣對齊可視右緣）', () {
      expect(
        fitOrigin(
          contentSize: const Size(1000, 3000),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.rtl,
        ),
        const Offset(-600, 0),
      );
    });
  });

  group('fitZoomForUnit：單元＋頁邊距＋可視尺寸 → 夾住上限的縮放值', () {
    test('內容尺寸含頁邊距（各邊加 margin）', () {
      // 單元 600x800 加 8 邊距 → 616x816；Page-fit 放進 400x400：min(400/616, 400/816)
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.pageFit,
        unitRect: const Rect.fromLTWH(8, 8, 600, 800),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, closeTo(400 / 816, 1e-9));
    });

    test('Fit Width 用含邊距的寬度', () {
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.fitWidth,
        unitRect: const Rect.fromLTWH(8, 8, 600, 800),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, closeTo(400 / 616, 1e-9));
    });

    test('超過上限時夾在上限', () {
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.fitWidth,
        unitRect: const Rect.fromLTWH(8, 8, 10, 10),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, 8);
    });

    test('可視尺寸為 0（版面尚未量測）：回傳 null', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.pageFit,
          unitRect: const Rect.fromLTWH(8, 8, 600, 800),
          pageMargin: 8,
          viewSize: Size.zero,
          maxZoom: 8,
        ),
        isNull,
      );
    });

    test('內容尺寸為 0：回傳 null，不是無限大', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.fitWidth,
          unitRect: Rect.zero,
          pageMargin: 0,
          viewSize: const Size(400, 400),
          maxZoom: 8,
        ),
        isNull,
      );
    });

    test('真實比例固定 1.0（仍受上限夾住）', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.actualSize,
          unitRect: const Rect.fromLTWH(8, 8, 600, 800),
          pageMargin: 8,
          viewSize: const Size(400, 400),
          maxZoom: 8,
        ),
        1.0,
      );
    });
  });
}
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：編譯失敗，`Error: Method not found: 'fitBaseScale'`（檔案不存在）。

- [x] **Step 3：實作**

建立 `app/lib/reader/pdf_paginated_rules.dart`：

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'dual_page_direction.dart';
import 'pdf_fit_mode.dart';

// PDF 逐頁導覽規則（純 Dart，不依賴 Widget；見
// docs/epics/epic-56-pdf-paginated-reading/spec.md「逐頁導覽規則模組」）。
// 本檔目前只有規則 1（縮放基準與對齊）、規則 2（頁內捲動範圍）；後續 Issue
// 會在此擴充步進、跳轉、滑動判定等規則。

/// 規則 1：某個「單元」（一頁或一個 spread）在 [viewSize] 下的縮放基準。
/// [contentSize] 是單元尺寸，呼叫端須先加上 pdfrx 頁邊距。
///
/// - Page-fit：寬高各自的比例取較小者，整個單元完整放進可視範圍。
/// - Fit Width：可視寬度除以內容寬度。
/// - 真實比例：固定 1.0（1 PDF point ＝ 1 邏輯像素）。
double fitBaseScale({
  required PdfFitMode mode,
  required Size contentSize,
  required Size viewSize,
}) {
  switch (mode) {
    case PdfFitMode.pageFit:
      return math.min(
        viewSize.width / contentSize.width,
        viewSize.height / contentSize.height,
      );
    case PdfFitMode.fitWidth:
      return viewSize.width / contentSize.width;
    case PdfFitMode.actualSize:
      return 1.0;
  }
}

/// 規則 2：縮放後內容的縱向最大捲動量；內容不比可視高度高時為 0。
double maxVerticalScroll({
  required Size contentSize,
  required double scale,
  required Size viewSize,
}) {
  return math.max(0.0, contentSize.height * scale - viewSize.height);
}

/// 規則 1（對齊）：縮放後內容左上角在可視區域座標系中的位置。
///
/// 比可視範圍小的維度置中；縱向溢出時從頁頂開始；橫向溢出時從閱讀起始側
/// 開始（左到右靠左、右到左靠右）。
Offset fitOrigin({
  required Size contentSize,
  required double scale,
  required Size viewSize,
  required DualPageDirection direction,
}) {
  final width = contentSize.width * scale;
  final height = contentSize.height * scale;
  final double x;
  if (width <= viewSize.width) {
    x = (viewSize.width - width) / 2;
  } else {
    x = direction == DualPageDirection.rtl ? viewSize.width - width : 0.0;
  }
  final y = height <= viewSize.height ? (viewSize.height - height) / 2 : 0.0;
  return Offset(x, y);
}

/// 單元矩形 [unitRect]（pdfrx 版面座標，不含頁邊距）在 [viewSize] 下要套用的
/// 縮放值：內容尺寸為單元各邊加 [pageMargin]（與 pdfrx 計算「整頁放進螢幕」
/// 的方式一致），並夾在 [maxZoom] 以內。可視尺寸或內容尺寸為 0（版面尚未
/// 量測）、算出非有限或非正值時回傳 null，呼叫端應沿用 pdfrx 原本的縮放。
double? fitZoomForUnit({
  required PdfFitMode mode,
  required Rect unitRect,
  required double pageMargin,
  required Size viewSize,
  required double maxZoom,
}) {
  final base = fitBaseScale(
    mode: mode,
    contentSize: unitRect.inflate(pageMargin).size,
    viewSize: viewSize,
  );
  if (!base.isFinite || base <= 0) return null;
  return math.min(base, maxZoom);
}
```

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_paginated_rules_test.dart`
Expected：19 個全數 PASS（fitBaseScale 6、maxVerticalScroll 3、fitOrigin 4、fitZoomForUnit 6）。

- [x] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_paginated_rules.dart app/test/reader/pdf_paginated_rules_test.dart
git commit -m "feat(reader): 新增 PDF 逐頁導覽規則模組（縮放基準、頁內捲動範圍，epic-56 Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：Fit 尺寸 delegate 與 `PdfReaderView` 初始縮放接線

**Files：**
- Create：`app/lib/reader/pdf_fit_size_delegate.dart`
- Create：`app/test/reader/pdf_fit_size_delegate_test.dart`
- Create：`app/test/reader/pdf_reader_view_fit_mode_test.dart`
- Modify：`app/lib/reader/pdf_reader_view.dart`（import；欄位約第 65 行；建構子約第 112 行；`_dualPageEnabled` 附近；`PdfViewerParams` 約第 994 行）

**Interfaces：**
- Consumes：Task 1 的 `fitZoomForUnit`、`PdfFitMode`；`pdfrx` 的 `PdfViewerSizeDelegateLegacy`、`PdfViewerSizeDelegateProvider`、`PdfViewerLayoutMetrics`、`PdfViewerLayoutSnapshot`、`PdfPageLayout`、`PdfViewerController`。
- Produces（Task 3 依賴）：

```dart
const double kPdfFitMaxZoom = 8.0; // pdfrx 預設的最大縮放

typedef PdfFitUnitRect = Rect Function(PdfPageLayout layout, int pageNumber);

class PdfFitSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const PdfFitSizeDelegateProvider({required this.fitMode, required this.unitRectOf, required this.pageMargin});
  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;
  final double pageMargin;
}

// PdfReaderView：
final PdfFitMode? pdfFitMode;                 // null＝不干預
Rect _unitRectFor(PdfPageLayout layout, int pageNumber); // State 方法
static const double _pdfPageMargin = 8.0;     // State 常數，同時傳給 PdfViewerParams.margin
```

- [x] **Step 1：寫 delegate 的失敗測試**

建立 `app/test/reader/pdf_fit_size_delegate_test.dart`：

```dart
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_fit_size_delegate.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

// 單頁 600x800，pdfrx 版面座標含 8 的頁邊距位移。
final _layout = PdfPageLayout(
  pageLayouts: [const Rect.fromLTWH(8, 8, 600, 800)],
  documentSize: const Size(616, 816),
);

Rect _unitRectOf(PdfPageLayout layout, int pageNumber) =>
    layout.pageLayouts[pageNumber - 1];

PdfViewerSizeDelegate _delegate(PdfFitMode mode) => PdfFitSizeDelegateProvider(
      fitMode: mode,
      unitRectOf: _unitRectOf,
      pageMargin: 8,
    ).create();

PdfViewerLayoutMetrics _metrics(
  PdfViewerSizeDelegate delegate, {
  Size view = const Size(400, 400),
  PdfPageLayout? layout,
  int? pageNumber = 1,
}) =>
    delegate.calculateMetrics(
      viewSize: view,
      layout: layout ?? _layout,
      pageNumber: pageNumber,
      pageMargin: 8,
      boundaryMargin: null,
    );

void main() {
  group('最小縮放＝該 Fit 模式的基準（不可縮到基準以下）', () {
    test('Page-fit：min(400/616, 400/816)', () {
      expect(_metrics(_delegate(PdfFitMode.pageFit)).minScale,
          closeTo(400 / 816, 1e-9));
    });

    test('Fit Width：400/616', () {
      expect(_metrics(_delegate(PdfFitMode.fitWidth)).minScale,
          closeTo(400 / 616, 1e-9));
    });

    test('真實比例：1.0', () {
      expect(_metrics(_delegate(PdfFitMode.actualSize)).minScale, 1.0);
    });

    test('基準超過 pdfrx 上限時夾在上限', () {
      final tiny = PdfPageLayout(
        pageLayouts: [const Rect.fromLTWH(8, 8, 10, 10)],
        documentSize: const Size(26, 26),
      );
      expect(
        _metrics(_delegate(PdfFitMode.fitWidth), layout: tiny).minScale,
        kPdfFitMaxZoom,
      );
    });

    test('只改最小縮放，其餘指標沿用 pdfrx 原本的計算', () {
      final legacy = PdfViewerSizeDelegateLegacy(
        maxScale: kPdfFitMaxZoom,
        minScale: 0.1,
        useAlternativeFitScaleAsMinScale: true,
        onePassRenderingScaleThreshold: 200 / 72,
        calculateInitialZoom: null,
      );
      final expected = _metrics(legacy);
      final actual = _metrics(_delegate(PdfFitMode.fitWidth));
      expect(actual.maxScale, expected.maxScale);
      expect(actual.coverScale, expected.coverScale);
      expect(actual.alternativeFitScale, expected.alternativeFitScale);
    });
  });

  group('不可用的輸入退回 pdfrx 原本的指標（Review Focus 1）', () {
    PdfViewerLayoutMetrics legacyMetrics(Size view, int? pageNumber) {
      final legacy = PdfViewerSizeDelegateLegacy(
        maxScale: kPdfFitMaxZoom,
        minScale: 0.1,
        useAlternativeFitScaleAsMinScale: true,
        onePassRenderingScaleThreshold: 200 / 72,
        calculateInitialZoom: null,
      );
      return _metrics(legacy, view: view, pageNumber: pageNumber);
    }

    test('可視尺寸為 0：沿用 pdfrx 的最小縮放，不是 0 或無限大', () {
      final actual = _metrics(_delegate(PdfFitMode.fitWidth), view: Size.zero);
      expect(actual.minScale, legacyMetrics(Size.zero, 1).minScale);
    });

    test('沒有 pivot 頁（pageNumber 為 null）：沿用 pdfrx', () {
      final actual =
          _metrics(_delegate(PdfFitMode.pageFit), pageNumber: null);
      expect(actual.minScale, legacyMetrics(const Size(400, 400), null).minScale);
    });
  });

  group('provider 相等性（pdfrx 靠它判斷要不要重建 delegate）', () {
    test('欄位相同則相等、雜湊相同', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('Fit 模式不同則不相等', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.fitWidth, unitRectOf: _unitRectOf, pageMargin: 8);
      expect(a, isNot(b));
    });
  });
}
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_fit_size_delegate_test.dart`
Expected：編譯失敗，找不到 `pdf_fit_size_delegate.dart`。

- [x] **Step 3：實作 delegate**

建立 `app/lib/reader/pdf_fit_size_delegate.dart`：

```dart
import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_fit_mode.dart';
import 'pdf_paginated_rules.dart';

/// pdfrx 預設的最大縮放（`PdfViewerSizeDelegateProviderLegacy` 的預設值）。
const double kPdfFitMaxZoom = 8.0;

/// 由 pdfrx 版面與頁碼取得「單元」矩形（一頁，或雙頁模式下一個 spread 的
/// 合併矩形）。矩形為 pdfrx 版面座標，不含頁邊距。
typedef PdfFitUnitRect = Rect Function(PdfPageLayout layout, int pageNumber);

/// 讓 Fit 模式（Page-fit／Fit Width／真實比例）決定 pdfrx 的初始縮放與最小
/// 縮放（epic-56 Issue 1）。
///
/// 提供者必須有穩定的相等性：pdfrx 在 `didUpdateWidget` 以 `!=` 比較新舊
/// provider，相等才不會重建 delegate。[unitRectOf] 請傳 State 方法的
/// tear-off（同一個 State 的 tear-off 相等）。
class PdfFitSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const PdfFitSizeDelegateProvider({
    required this.fitMode,
    required this.unitRectOf,
    required this.pageMargin,
  });

  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;

  /// 必須與 `PdfViewerParams.margin` 相同。
  final double pageMargin;

  @override
  PdfViewerSizeDelegate create() => PdfFitSizeDelegate(
        fitMode: fitMode,
        unitRectOf: unitRectOf,
        pageMargin: pageMargin,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFitSizeDelegateProvider &&
          fitMode == other.fitMode &&
          unitRectOf == other.unitRectOf &&
          pageMargin == other.pageMargin;

  @override
  int get hashCode => Object.hash(fitMode, unitRectOf, pageMargin);
}

/// 繼承 pdfrx 公開的 Legacy delegate，只覆寫兩處：
/// 1. 最小縮放＝目前頁（或 spread）的 Fit 基準，使用者可放大、不可縮到基準以下；
/// 2. 開書初始縮放＝初始頁的 Fit 基準。
/// 旋轉／版面變更時保留閱讀位置等行為沿用 Legacy（其
/// `onLayoutUpdate` 在「目前縮放等於舊最小縮放」時會跟著新最小縮放走，所以
/// 停在基準的使用者旋轉螢幕後會自動套用新基準）。
class PdfFitSizeDelegate extends PdfViewerSizeDelegateLegacy {
  PdfFitSizeDelegate({
    required this.fitMode,
    required this.unitRectOf,
    required this.pageMargin,
  }) : super(
          maxScale: kPdfFitMaxZoom,
          minScale: 0.1,
          useAlternativeFitScaleAsMinScale: true,
          onePassRenderingScaleThreshold: 200 / 72,
          calculateInitialZoom: null,
        );

  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;
  final double pageMargin;

  PdfViewerController? _fitController;

  @override
  void init(PdfViewerController controller) {
    super.init(controller);
    _fitController = controller;
  }

  @override
  void dispose() {
    _fitController = null;
    super.dispose();
  }

  /// 版面不可用或算不出有效縮放時回傳 null（呼叫端沿用 pdfrx 原本的指標）。
  double? _zoomFor(PdfPageLayout? layout, int? pageNumber, Size viewSize) {
    if (layout == null ||
        pageNumber == null ||
        pageNumber < 1 ||
        pageNumber > layout.pageLayouts.length) {
      return null;
    }
    return fitZoomForUnit(
      mode: fitMode,
      unitRect: unitRectOf(layout, pageNumber),
      pageMargin: pageMargin,
      viewSize: viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
  }

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    final metrics = super.calculateMetrics(
      viewSize: viewSize,
      layout: layout,
      pageNumber: pageNumber,
      pageMargin: pageMargin,
      boundaryMargin: boundaryMargin,
    );
    final zoom = _zoomFor(layout, pageNumber, viewSize);
    if (zoom == null) return metrics;
    return PdfViewerLayoutMetrics(
      minScale: zoom,
      maxScale: metrics.maxScale,
      coverScale: metrics.coverScale,
      alternativeFitScale: metrics.alternativeFitScale,
    );
  }

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) {
    final controller = _fitController;
    final zoom = _zoomFor(layout, initialPageNumber, state.viewSize);
    if (controller == null || zoom == null) {
      super.onLayoutInitialized(
        state: state,
        initialPageNumber: initialPageNumber,
        coverScale: coverScale,
        alternativeFitScale: alternativeFitScale,
        layout: layout,
        document: document,
      );
      return;
    }
    // 與 Legacy 相同的套用方式：以文件原點為中心設定縮放、不播動畫；之後
    // pdfrx 會再把初始頁帶進視野。
    unawaited(controller.setZoom(Offset.zero, zoom, duration: Duration.zero));
  }
}
```

注意：`calculateMetrics` 的參數 `pageMargin` 會遮蔽欄位 `this.pageMargin`，這是 pdfrx 介面簽章所致；方法內改用 `super.calculateMetrics` 傳入的參數，`_zoomFor` 使用的是欄位（建構時傳入的相同值），兩者必須相等（見 provider 註解）。

- [x] **Step 4：確認 delegate 測試通過**

Run：`flutter test test/reader/pdf_fit_size_delegate_test.dart`
Expected：9 個全數 PASS。

- [x] **Step 5：寫 widget 接線的失敗測試**

建立 `app/test/reader/pdf_reader_view_fit_mode_test.dart`：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

const _viewSize = Size(400, 400);
const _margin = 8.0;

/// 用 400x400 的固定可視範圍，讓 Page-fit（高度受限）與 Fit Width 的值不同。
Widget _app(PdfReaderView child) => MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox(
          width: _viewSize.width,
          height: _viewSize.height,
          child: child,
        ),
      ),
    );

PdfReaderView _view({
  required void Function() onRendered,
  PdfFitMode? fit,
  String file = 'test/fixtures/sample.pdf',
  DualPageMode dualMode = DualPageMode.never,
  bool coverAlone = true,
  PdfCropMode cropMode = PdfCropMode.none,
  PdfCropRect? cropRect,
}) =>
    PdfReaderView(
      key: const ValueKey('fit_view'),
      filePath: file,
      onPageRendered: onRendered,
      onError: (_) {},
      pdfFitMode: fit,
      dualPageMode: dualMode,
      dualPageCoverAlone: coverAlone,
      pdfCropMode: cropMode,
      pdfCropRect: cropRect,
    );

PdfViewerController _controllerOf(WidgetTester tester) =>
    tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;

Future<Size> _pageSize(WidgetTester tester, String path, int index) async {
  final size = await tester.runAsync(() async {
    final doc = await PdfDocument.openFile(path);
    final page = doc.pages[index];
    final s = Size(page.width, page.height);
    await doc.dispose();
    return s;
  });
  return size!;
}

Future<PdfViewerController> _open(
  WidgetTester tester, {
  PdfFitMode? fit,
  String file = 'test/fixtures/sample.pdf',
  DualPageMode dualMode = DualPageMode.never,
  bool coverAlone = true,
  PdfCropMode cropMode = PdfCropMode.none,
  PdfCropRect? cropRect,
}) async {
  var rendered = 0;
  await tester.pumpWidget(_app(_view(
    onRendered: () => rendered++,
    fit: fit,
    file: file,
    dualMode: dualMode,
    coverAlone: coverAlone,
    cropMode: cropMode,
    cropRect: cropRect,
  )));
  await pumpUntilPdfReady(tester, condition: () => rendered != 0);
  // 初始縮放在版面初始化後才套用，再多等幾輪讓它落定。
  await pumpUntilPdfReady(tester, maxIterations: 5);
  return _controllerOf(tester);
}

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('不傳 pdfFitMode：沿用 pdfrx 預設（初始縮放＝coverScale），零回歸（Review Focus 5）',
      (tester) async {
    final c = await _open(tester);
    expect(c.currentZoom, closeTo(c.coverScale, 0.001));
  });

  testWidgets('Page-fit：整頁（含頁邊距）完整放進可視範圍，最小縮放同值', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final expected = _minOf(_viewSize.width / (page.width + _margin * 2),
        _viewSize.height / (page.height + _margin * 2));
    final c = await _open(tester, fit: PdfFitMode.pageFit);
    expect(c.currentZoom, closeTo(expected, 0.001));
    expect(c.minScale, closeTo(expected, 0.001));
  });

  testWidgets('Fit Width：頁寬（含頁邊距）滿版，且與 Page-fit 的值不同', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final fitWidth = _viewSize.width / (page.width + _margin * 2);
    final pageFit = _minOf(fitWidth,
        _viewSize.height / (page.height + _margin * 2));
    // 前提：這份 fixture 在 400x400 下兩種模式要有鑑別力。
    expect(fitWidth - pageFit, greaterThan(0.01));

    final c = await _open(tester, fit: PdfFitMode.fitWidth);
    expect(c.currentZoom, closeTo(fitWidth, 0.001));
    expect(c.minScale, closeTo(fitWidth, 0.001));
  });

  testWidgets('真實比例：縮放 1.0，最小縮放也是 1.0', (tester) async {
    final c = await _open(tester, fit: PdfFitMode.actualSize);
    expect(c.currentZoom, closeTo(1.0, 0.001));
    expect(c.minScale, closeTo(1.0, 0.001));
  });

  testWidgets('雙頁模式：以 spread 合併矩形（含邊距）算基準（Review Focus 4）', (tester) async {
    final c = await _open(
      tester,
      fit: PdfFitMode.pageFit,
      file: 'test/fixtures/sample_dual_page.pdf',
      dualMode: DualPageMode.always,
      coverAlone: false,
    );
    final spread = c.layout.pageLayouts[0].expandToInclude(c.layout.pageLayouts[1]);
    final inflated = spread.inflate(_margin);
    final expected = _minOf(
        _viewSize.width / inflated.width, _viewSize.height / inflated.height);
    expect(c.currentZoom, closeTo(expected, 0.001));
    // 合併矩形比單頁寬：基準必須比「只看第一頁」的 Page-fit 小。
    final single = c.layout.pageLayouts[0].inflate(_margin);
    final singleFit = _minOf(
        _viewSize.width / single.width, _viewSize.height / single.height);
    expect(c.currentZoom, lessThan(singleFit));
  });

  testWidgets('手動裁切：以裁切後的頁面矩形（含邊距）算基準（Review Focus 4）', (tester) async {
    final c = await _open(
      tester,
      fit: PdfFitMode.pageFit,
      cropMode: PdfCropMode.manual,
      cropRect:
          const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
    );
    final cropped = c.layout.pageLayouts[0].inflate(_margin);
    final expected = _minOf(
        _viewSize.width / cropped.width, _viewSize.height / cropped.height);
    expect(c.currentZoom, closeTo(expected, 0.001));
  });
}

double _minOf(double a, double b) => a < b ? a : b;
```

- [x] **Step 6：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_fit_mode_test.dart`
Expected：編譯失敗，`No named parameter with the name 'pdfFitMode'`。

- [x] **Step 7：`PdfReaderView` 接線**

`app/lib/reader/pdf_reader_view.dart`：

(a) 檔頭 import 區（與其他 `import '...'` 並列，字母序）加入：

```dart
import 'pdf_fit_mode.dart';
import 'pdf_fit_size_delegate.dart';
```

(b) 在 `final PdfPageTurnAnimation pdfPageTurnAnimation;` 之後加入欄位：

```dart
  /// Fit 模式（Page-fit／Fit Width／真實比例，epic-56 Issue 1）。`null`＝
  /// 不干預，沿用 pdfrx 現有的預設縮放行為（widget 層預設保守，保護既有
  /// 測試；產品預設由 `ReaderScreen` 傳入解析後的值，比照 `dualPageMode`）。
  final PdfFitMode? pdfFitMode;
```

(c) 建構子中 `this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,` 之後加入：

```dart
    this.pdfFitMode,
```

(d) 在 `bool get _dualPageEnabled =>` 的上方加入常數與方法（`_PdfReaderViewState` 內）：

```dart
  /// pdfrx 頁邊距。同時傳給 `PdfViewerParams.margin` 與 Fit 縮放計算，兩處
  /// 必須同值（pdfrx 預設即為 8.0）。
  static const double _pdfPageMargin = 8.0;

  /// Fit 縮放的「單元」矩形：雙頁模式為頁面所屬 spread 的合併矩形，否則為
  /// 該頁（裁切時 pdfrx 版面本身已是裁切後尺寸）。以 State 方法 tear-off 傳給
  /// [PdfFitSizeDelegateProvider]，tear-off 具備穩定的 == 語意。
  Rect _unitRectFor(PdfPageLayout layout, int pageNumber) {
    final spread = _dualPageEnabled ? _spreadLayout : null;
    // spread 版面與 pdfrx 目前版面的頁數不一致（切換雙頁／裁切的暫態，spread
    // 尚未重算）時不採用，退回該頁矩形。spreadIndexOf 本身對超界與空陣列都
    // 會 clamp／回 0，不需要再自行防呆。
    if (spread == null || spread.pageToSpread.length != layout.pageLayouts.length) {
      return layout.pageLayouts[pageNumber - 1];
    }
    return spread.spreadRects[spread.spreadIndexOf(pageNumber - 1)];
  }
```

(e) `PdfViewerParams(` 內，在 `layoutPages: _cropEnabled` 這一行**之前**加入：

```dart
        margin: _pdfPageMargin,
        sizeDelegateProvider: widget.pdfFitMode == null
            ? null
            : PdfFitSizeDelegateProvider(
                fitMode: widget.pdfFitMode!,
                unitRectOf: _unitRectFor,
                pageMargin: _pdfPageMargin,
              ),
```

- [x] **Step 8：確認 widget 測試通過**

Run：`flutter test test/reader/pdf_reader_view_fit_mode_test.dart`
Expected：6 個全數 PASS。
若 Page-fit／Fit Width 案例的縮放與預期不符，先確認 delegate 的 `calculateMetrics` 是否被呼叫（在 `_zoomFor` 暫時 `debugPrint`）、`pageNumber` 是否為 null；**不要**調整測試數值去遷就實作。

- [x] **Step 9：確認既有 PDF 測試零回歸**

Run：`flutter test test/reader/pdf_reader_view_*_test.dart`
Expected：全數 PASS（含 Task 0 記下的既有案例，未修改任何一個）。

- [x] **Step 10：Commit**

```bash
git add app/lib/reader/pdf_fit_size_delegate.dart app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_fit_size_delegate_test.dart app/test/reader/pdf_reader_view_fit_mode_test.dart
git commit -m "feat(reader): PDF Fit 模式決定初始縮放與最小縮放（epic-56 Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：執行期切換、`ReaderScreen` 接線、文件與收尾

**Files：**
- Modify：`app/lib/reader/pdf_reader_view.dart`（`didUpdateWidget`；新增 `_scheduleRefit`／`_applyFitZoom`）
- Modify：`app/test/reader/pdf_reader_view_fit_mode_test.dart`（新增 2 個案例）
- Modify：`app/lib/screens/reader_screen.dart`（約第 3470 行）
- Modify：`app/test/screens/reader_screen_test.dart`（新增 2 個案例）
- Modify：`docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}`

**Interfaces：**
- Consumes：Task 1 的 `fitZoomForUnit`；Task 2 的 `kPdfFitMaxZoom`、`_unitRectFor`、`_pdfPageMargin`。
- Produces：無（最後一個 Task）。

- [x] **Step 1：寫執行期切換的失敗測試**

在 `pdf_reader_view_fit_mode_test.dart` 的 `main()` 內、最後一個 `testWidgets` 之後加入（並在檔案頂端 import 區補 `package:flutter/gestures.dart` 不需要；這兩個案例直接重建 widget 樹）：

```dart
  testWidgets('執行期由 Page-fit 切到 Fit Width：縮放與最小縮放改為 Fit Width 的基準', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final fitWidth = _viewSize.width / (page.width + _margin * 2);

    var rendered = 0;
    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.pageFit)));
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    await pumpUntilPdfReady(tester, maxIterations: 5);
    final c = _controllerOf(tester);
    // 前提：切換前確實不同。這依賴 sample.pdf（約 612x792）在 400x400 下
    // Page-fit 受高度限制（≈0.495）、Fit Width 受寬度限制（≈0.637）；更換
    // fixture 時需重新確認兩者仍有鑑別力。
    expect(c.currentZoom, lessThan(fitWidth - 0.01));

    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.fitWidth)));
    await pumpUntilPdfReady(
      tester,
      condition: () => (c.currentZoom - fitWidth).abs() < 0.001,
    );
    expect(c.currentZoom, closeTo(fitWidth, 0.001));
    expect(c.minScale, closeTo(fitWidth, 0.001));
  });

  testWidgets('使用者手動放大後切換 Fit 模式：縮放回到新模式的基準（Review Focus 3）',
      (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final pageFit = _minOf(_viewSize.width / (page.width + _margin * 2),
        _viewSize.height / (page.height + _margin * 2));

    var rendered = 0;
    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.fitWidth)));
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    await pumpUntilPdfReady(tester, maxIterations: 5);
    final c = _controllerOf(tester);

    // 使用者手動放大到 3 倍。
    await c.setZoom(Offset.zero, 3.0, duration: Duration.zero);
    await tester.pump();
    expect(c.currentZoom, closeTo(3.0, 0.001));

    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.pageFit)));
    await pumpUntilPdfReady(
      tester,
      condition: () => (c.currentZoom - pageFit).abs() < 0.001,
    );
    expect(c.currentZoom, closeTo(pageFit, 0.001));
  });
```

- [x] **Step 2：確認失敗**

Run：`flutter test test/reader/pdf_reader_view_fit_mode_test.dart`
Expected：兩個新案例 FAIL（縮放仍停在切換前的值）；前面 6 個仍 PASS。

- [x] **Step 3：實作執行期重套**

`pdf_reader_view.dart`：

(a) 在 `didUpdateWidget` 內，`// 加粗強度 debounce：300ms 沉澱後才更新 _committedBoldStrength。` 這行**之前**加入：

```dart
    // Fit 模式切換（epic-56 Issue 1）：pdfrx 更換 sizeDelegateProvider 只會重建
    // delegate，不會重算最小縮放也不會重新套用縮放，須明確處理。
    // 與下方雙頁／裁切變更的 reanchor 同時發生時，兩者都排兩層 postFrameCallback，
    // 依註冊順序先執行本處的縮放、再執行 reanchor 的跳頁；goToPage 的縮放上限是
    // 目前縮放，所以跳頁不會把剛設好的基準放大。
    if (oldWidget.pdfFitMode != widget.pdfFitMode) {
      _scheduleRefit();
    }

```

(b) 在 `_applyPendingReanchor()` 方法之後加入：

```dart
  /// 讓 pdfrx 重新排版（重算最小縮放），再於後續幀把縮放設為新模式的基準。
  /// 未就緒時不需處理：文件開完後 delegate 會依最新的 [PdfReaderView.pdfFitMode]
  /// 套用初始縮放。兩層 postFrameCallback 的原因同 [didUpdateWidget] 中
  /// reanchor 的說明（invalidate 的重排要等到下一幀才完成）。
  void _scheduleRefit() {
    if (!_controller.isReady) return;
    _controller.invalidate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFitZoom());
    });
  }

  /// 把目前頁（雙頁為目前 spread）以新 Fit 模式的基準縮放顯示；使用者先前
  /// 手動放大的縮放會被重設為基準。以 goToPosition 設定，不受舊最小縮放夾制。
  void _applyFitZoom() {
    final mode = widget.pdfFitMode;
    if (mode == null || !mounted || !_controller.isReady) return;
    final layout = _controller.layout;
    final pageNumber = _controller.pageNumber ?? 1;
    // 與 delegate 的 _zoomFor 同樣防呆：版面為空或頁碼超界時不處理，避免重排
    // 尚未完成的暫態拋出 RangeError。
    if (pageNumber < 1 || pageNumber > layout.pageLayouts.length) return;
    final unit = _unitRectFor(layout, pageNumber);
    final zoom = fitZoomForUnit(
      mode: mode,
      unitRect: unit,
      pageMargin: _pdfPageMargin,
      viewSize: _controller.viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
    if (zoom == null) return;
    unawaited(_controller.goToPosition(
      documentOffset: unit.inflate(_pdfPageMargin).topLeft,
      zoom: zoom,
    ));
  }
```

並在檔頭 import 區加入 `import 'pdf_paginated_rules.dart';`。

說明：`fitZoomForUnit` 收「不含邊距的單元矩形」並自行加邊距；`goToPosition` 的位置取含邊距矩形的左上角，目的是精確定位單元在連續長條中的起點（含頁首邊距）。水平方向不要自行計算置中偏移：`goToPosition` 內部會先 `_adjustBoundaryMargins` 再夾到邊界，文件寬度（含邊距）縮放後小於可視寬度時，水平對齊交給 `PdfViewerParams.underflowAnchor`（文件層級的設定，不是單元層級）。因此 Page-fit 在可視範圍較寬時的左右留白位置以 `pdfrx` 行為為準，逐頁置中是 Issue 4 的事；待真機確認這個留白位置是否可接受。

- [x] **Step 4：確認通過**

Run：`flutter test test/reader/pdf_reader_view_fit_mode_test.dart`
Expected：8 個全數 PASS。
若「手動放大後切換」失敗而「Page-fit 切 Fit Width」通過：先確認兩層 postFrameCallback 後 `isReady` 仍為 true；若 `goToPosition` 被邊界夾制導致縮放不符，保持測試不動，回報後以 `_controller.setZoom` 搭配 `goToPosition` 嘗試，並把原因記入 `epic.md`。

- [x] **Step 5：`ReaderScreen` 接線的失敗測試**

在 `app/test/screens/reader_screen_test.dart` 的「PDF 收到 onPageChanged 後進入背景（paused）…」案例**之前**加入（檔頭 import 區補 `import 'package:elinkbook/reader/pdf_fit_mode.dart';`；`BookReaderPrefs` 已被該檔 import）：

```dart
  testWidgets('PDF：尚未存過 Fit 模式時，PdfReaderView 的 pdfFitMode 為 Page-fit（epic-56 Issue 1）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_fit_default',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfFitMode, PdfFitMode.pageFit);
  });

  testWidgets('PDF：該書存過的 Fit 模式會傳給 PdfReaderView（epic-56 Issue 1）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_fit_saved',
      const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_fit_saved',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfFitMode, PdfFitMode.fitWidth);
  });
```

Run：`flutter test test/screens/reader_screen_test.dart --plain-name "epic-56 Issue 1"`
Expected：2 個 FAIL（`pdfFitMode` 為 `null`，因為 `ReaderScreen` 還沒傳）。

- [x] **Step 6：`ReaderScreen` 傳入解析後的 Fit 模式**

`app/lib/screens/reader_screen.dart` 的 `PdfReaderView(` 呼叫內，在 `pdfPageTurnAnimation: resolved.pdfPageTurnAnimation,` 之後加入一行：

```dart
          pdfFitMode: resolved.pdfFitMode,
```

- [x] **Step 7：確認接線測試與相關測試通過**

Run：`flutter test test/screens/reader_screen_test.dart test/reader/pdf_reader_view_fit_mode_test.dart`
Expected：全數 PASS（reader_screen_test 既有案例加 2 個新案例）。

- [x] **Step 8：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：`No issues found!`；兩行 PASS。

- [x] **Step 9：全套測試（唯一一次）**

`flutter test` 以 `run_in_background` 在 `app/` 目錄下執行。預期：全數通過，數量為本 Issue 開始前主線基準（Task 0 之後、以 `flutter test` 全套實測的數字）＋ 新增案例（規則 19 ＋ delegate 9 ＋ widget 8 ＋ reader_screen 2 ＝ 38）、1 略過、0 失敗。若失敗，先用 `systematic-debugging` 找原因，不得修改既有測試以求通過。

- [x] **Step 10：更新文件並提交**

- `epic.md`：在最後新增「**日期 Issue 1 實作完成**」段，記錄：做法（Legacy delegate 子類別覆寫最小／初始縮放，`pdfFitMode` 為 null 時不干預）、新增測試數、驗證結果、與計畫的差異（若有）、以及兩項**需要知道的事**：(1) 修改前 pdfrx 預設實際是 Fit Width 起始而非 Page-fit，現在預設（ReaderScreen 傳 Page-fit）會讓所有 PDF 開書時變成整頁放進螢幕，是刻意的行為變更；(2) Fit 基準只在開書與切換 Fit 模式時套用，雙頁／裁切切換時沿用 pdfrx 的「保留縮放並夾最小縮放」行為（本 Issue 範圍外）。待真機確認：三種 Fit 模式在實機的初始畫面與旋轉後的表現。
- `issues.md`：Issue 1 的 `**Status:**` 改為 `done`（待程式審查與發 PR 前先標為 `in-review` 亦可，依先前 Epic 慣例）。

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/pdf_reader_view_fit_mode_test.dart app/test/screens/reader_screen_test.dart docs/epics/epic-56-pdf-paginated-reading/
git commit -m "feat(reader): 執行期切換 Fit 模式重套縮放並接上 ReaderScreen（epic-56 Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

- **範圍對照（`issues.md` Issue 1）**：純 Dart 規則模組含規則 1、2 → Task 1；`PdfReaderView` 讀 `pdfFitMode`、連續捲動下生效、以 `sizeDelegateProvider` 提供初始與最小縮放 → Task 2；`ReaderScreen` 傳入 → Task 3；雙頁與裁切相容 → Task 2 widget 測試；零回歸 → Task 2 Step 9。
- **介面一致**：`fitZoomForUnit`（Task 1 定義）在 Task 2 delegate 與 Task 3 `_applyFitZoom` 使用，簽章一致；`kPdfFitMaxZoom`、`_unitRectFor`、`_pdfPageMargin` 在 Task 2 定義、Task 3 使用。
- **已知風險（執行時以測試為準）**：(1) `_applyFitZoom` 的兩層 postFrameCallback 與 `goToPosition` 行為是依 pdfrx 原始碼推論，已寫在 Step 4 的回報方式；(2) Task 2 Step 8 若 `calculateMetrics` 的 `pageNumber` 在初始化階段為 null，初始縮放會走 `onLayoutInitialized` 的 `initialPageNumber`，不受影響，但最小縮放要等下一次 metrics 重算；widget 測試等待 5 輪涵蓋這個時序。
- **測試數字**：Task 0 Step 3 的基準以實測為準；Task 3 Step 9 的預期總數是「基準＋38」，若實作時案例數有調整，以實測回填 `epic.md`。
- **無占位**：所有步驟含實際程式碼或指令。
