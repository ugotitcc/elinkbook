# Issue 44：PDF 手動裁切——裁切框比例未換算成頁面比例（症狀 1）實作計畫

> **給執行者：** 步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就改為 `- [x]`。**本計畫先審查，審查通過前不得修改 `lib/`。**

**Goal：** 讓手動裁切「框選範圍＝套用後的裁切範圍」。使用者從頁面白紙左上角拖到右下角，套用後應不裁切，不得切掉任何文字。

**Architecture：** 裁切層（`PdfCropFrameOverlay`）維持蓋滿整個閱讀區、輸出「相對畫面」的比例，不改。在 `ReaderScreen` 按 ✓ 時，經 `ReaderSurface` 的 `PdfFacet` 取得「目前可見頁面在畫面中的矩形」，用一個純函式把畫面比例換算成頁面比例（若目前已有生效中的裁切，再合成回原始整頁座標），再寫入 `pdfCropRect`。

**Tech Stack：** Flutter／Dart、`pdfrx`（`PdfViewerController.layout`／`visibleRect`／`currentZoom`）。指令一律在 `app/` 目錄下執行。

## 背景與證據

- 根因與實驗見 `epic.md`「後續項目（2026-11-17，使用者回報）：PDF 裁切起點跳動（Issue 44）」的「症狀 1 根因」。
- 實驗：從頁面白紙左上角拖到右下角，`CONFIRM rect=(left 0.098, top 0.031, right 0.901, bottom 0.980)`，套用後左側整欄文字被切一半。證據檔：`repro/issue-44-crop-hint-screen.png`、`repro/issue-44-crop-result-left-clipped.png`。
- `PdfCropRect` 語意是「相對頁面尺寸的比例」（`lib/reader/pdf_crop_rect.dart` 檔頭註解）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。
- **不改裁切層的拖拉邏輯**：`pdf_crop_frame_overlay.dart` 的多指並行追蹤（第三版）已證實單次拖拉穩定，本 Issue 不再動它，除了移除 `[DEBUG-crop44]` 記錄。
- **座標單位**：本計畫所有「像素」一律指**邏輯像素**（Flutter 的 `Size`／`Rect` 單位，不含 `devicePixelRatio`）。
- **不破壞閱讀面抽象邊界**：`ReaderScreen` 不得直接呼叫 `PdfReaderView` 的靜態方法（epic-54 Issue 23 已全部收斂到 `_surface.pdf!`），一律經 `PdfFacet`。
- **不破壞既有座標約定**：`PdfCropRect` 的儲存格式、`book_reader_prefs.pdf_crop_rect` 欄位、智慧裁切（`PdfCropMode.smart`）的輸出一律不變。
- **提交**：不加 `Co-Authored-By`（使用者偏好，覆蓋其他計畫的樣板）。PR 與分支走 Gitea，不用 `gh`、不推 github remote。
- **真機**：Mobiscribe WAVE（序號 `TCE70P24B2202374`）。禁用 `flutter install`，一律 `adb install -r`。
- **測試範圍**：單一 Task 只跑異動觸及的測試；完整 `flutter test` 只在最後一個 Task 跑一次。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`。

## 設計

### 1. 純函式（新增，不依賴 `pdfrx`／Flutter widget，僅使用 `dart:ui` 的 `Size`、`Rect` 值型別）

`app/lib/reader/pdf_crop_mapping.dart`（比照 `pdf_selection_geometry.dart` 的慣例）：

```dart
/// 把「相對畫面」的框換算成「相對原始整頁」的 PdfCropRect。
/// [viewportRect]：框在畫面中的比例（0～1，相對 [viewportSize]，邏輯像素）。
/// [pageRectInViewport]：目前顯示的頁面在畫面中的矩形（邏輯像素，可超出畫面）。
/// [activeCrop]：目前**生效中**的裁切（模式不是 none 且矩形非 null）；
///   生效時，畫面上顯示的是已裁切的頁面，換算結果是「相對已裁切頁面」，
///   須再合成回原始整頁座標；null 表示畫面顯示的就是整頁。
/// 框與頁面的交集任一邊（以頁面比例計）小於 [minFraction]，或沒有交集，回傳 null。
PdfCropRect? viewportRectToPageCropRect({
  required PdfCropRect viewportRect,
  required Size viewportSize,
  required Rect pageRectInViewport,
  PdfCropRect? activeCrop,
  double minFraction = 0.05,
});
```

規則：

1. 先把 `viewportRect` 乘上 `viewportSize` 變成邏輯像素，與 `pageRectInViewport` 取交集（拖到灰邊的部分夾到頁面邊界），再除以頁面寬高，得到「相對顯示中的頁面」的比例。
2. 交集為空或任一邊小於 `minFraction` → 回傳 null。
3. 若 `activeCrop` 非 null，用既有的 `cropRelativeToOriginalPercent`（`pdf_selection_geometry.dart`）合成：`原 left + 新 left × (原 right − 原 left)`，其餘三邊同理，輸出相對原始整頁。
4. `pdfCropMode == none` 但 `pdfCropRect` 殘留舊值（真機進入記錄 `mode=none existingRect=(0.14, 0.11, 0.87, 0.89)` 即此情況）時，畫面顯示整頁，**不可合成**，呼叫端傳 `activeCrop: null`。

**已知限制（行為，不是缺陷）：** 已有生效中的裁切時，使用者看到的是裁切後的頁面，只能在其中再縮小；要放寬須先在版面設定選「不裁」。這與目前的行為（座標錯位）相比是修正，不是退步。

### 2. 可見頁面矩形：`PdfReaderView` → `PdfReaderSurface` → `PdfFacet`

- `PdfReaderView` 新增靜態方法（比照既有 `jumpToPage` 模式，未掛載或未就緒回傳空清單）：

```dart
static List<({int pageIndex, Rect rectInViewer})> visiblePageRects(
    GlobalKey<State<PdfReaderView>> key);
```

  換算：頁面在文件座標的矩形取自 `_controller.layout.pageLayouts[i]`，畫面座標 ＝ `(文件座標 − visibleRect.topLeft) × currentZoom`（與 `pdf_reader_view.dart:535、543-547` 的矩陣換算一致）。只回傳與畫面有交集的頁面。
- `PdfFacet`（`reader_surface.dart`）新增 `List<({int pageIndex, Rect rectInViewer})> visiblePageRects();`。
- `PdfReaderSurface`（`pdf_reader_surface.dart`）實作為 `PdfReaderView.visiblePageRects(viewKey)`。
- `FakePdfFacet`（`test/support/fake_reader_surface.dart`）預設回傳 `const []`，並可注入清單供 `ReaderScreen` 測試使用。

### 3. `ReaderScreen` 確認時換算

`viewportSize` 取自 `reader_body_stack` 外層 `LayoutBuilder` 的 `size`（`constraints.biggest`，`reader_screen.dart` 約 2464～2466 行），與 `PdfReaderView`、`PdfCropFrameOverlay` 同尺寸，單位為邏輯像素。

`onConfirm` 流程：

1. 取 `_surface.pdf?.visiblePageRects() ?? const []`；空清單（未就緒）→ 維持裁切編輯模式，不寫入。
2. 選頁（見 O1）。
3. 判斷是否有生效中的裁切：`_prefs.pdfCropMode != PdfCropMode.none && _prefs.pdfCropRect != null`（與 `PdfReaderView._cropEnabled` 同條件）；是 → `activeCrop = _prefs.pdfCropRect`，否 → `null`。
4. `viewportRectToPageCropRect(...)`；回傳 null（框完全在頁面外或太小）→ 維持裁切編輯模式，不寫入（O2）。
5. 非 null → 關閉編輯模式，寫入 `pdfCropMode: manual, pdfCropRect: 換算結果`。

### 待決定（需要審查者／使用者回答）

- **O1：雙頁並列時以哪一頁為準。** 裁切套用後會停用雙頁（`_dualPageEnabled`，`pdf_reader_view.dart:580`），之後每頁用同一個比例。建議：取「框中心點所在的那一頁」；中心點不在任何頁面內則取交集面積最大的頁。替代做法：永遠取 spread 內的第一頁。
- **O2：框完全落在頁面外或太小時的處置。** 建議：維持編輯模式、不寫入、不提示（與「範圍太小視為無效」一致）。替代：顯示一則提示字串（需新增 4 個 arb）。
- **O3：連續捲動時，使用者拖拉期間不應移動畫面。** 目前裁切層蓋住畫面，viewer 收不到手勢，視為已滿足；本計畫不處理，列為驗證項目（Task 4）。

## Task 1：純函式（TDD）

**Files：** 新增 `lib/reader/pdf_crop_mapping.dart`、`test/reader/pdf_crop_mapping_test.dart`。

- [x] **Step 1：寫會失敗的測試。** 案例：
  - 頁面填滿畫面（`pageRect == Offset.zero & viewportSize`）：輸入等於輸出。
  - **本次真機實驗**：畫面 1404×1777（像素），頁面矩形左 137、右 1267、上 30、下 1745；輸入 `(0.0976, 0.0169, 0.9024, 0.9822)`（頁面四邊在畫面中的比例）→ 輸出約 `(0, 0, 1, 1)`（誤差 `1e-3`）。
  - 框的一部分超出頁面（拖進灰邊）：夾到 0／1。
  - 頁面比畫面大（放大中）、只露出一部分：以未夾制的頁面矩形換算。
  - 框完全在頁面外：回傳 null。
  - 交集任一邊小於 0.05：回傳 null。
  - **已有生效中的裁切（審查 I-1）**：`activeCrop = (0.1, 0.1, 0.9, 0.9)`，使用者框滿目前顯示的（已裁切）頁面 → 輸出等於 `activeCrop`；框左半 → 輸出左邊界不變、右邊界落在 `0.1 + 0.5 × 0.8 = 0.5`。
  - **`activeCrop` 為 null 但外部仍有殘留舊矩形**：函式不看舊矩形，結果與無裁切時相同（由呼叫端負責傳 null）。
- [x] **Step 2：確認測試失敗**（編譯失敗即可）：`flutter test test/reader/pdf_crop_mapping_test.dart`。
- [x] **Step 3：實作純函式。**
- [x] **Step 4：測試通過**，`flutter analyze` 乾淨。

## Task 2：`PdfReaderView.visiblePageRects`

**Files：** 修改 `lib/reader/pdf_reader_view.dart`、`lib/reader/reader_surface.dart`（`PdfFacet`）、`lib/reader/pdf_reader_surface.dart`、`test/support/fake_reader_surface.dart`（`FakePdfFacet`）；新增 `test/reader/pdf_reader_view_visible_page_rects_test.dart`（仿 `pdf_reader_view_crop_overlay_size_test.dart` 的建置方式，`pdfrxInitialize()`＋`pumpUntilPdfReady`）。

- [x] **Step 1：寫會失敗的測試。** 用 `sample_multi_page.pdf`，開啟後呼叫 `PdfReaderView.visiblePageRects`：
  - 回傳非空、第一頁矩形落在畫面範圍內。
  - 頁面矩形的寬高比等於頁面實際寬高比（誤差 `1e-2`）。
  - 控制器未就緒時回傳空清單。
- [x] **Step 2：確認失敗。**
- [x] **Step 3：實作。** 讀 `_controller.layout.pageLayouts`、`visibleRect`、`currentZoom`；未就緒（`!_controller.isReady`）回傳空清單；`layout` getter 在版面未建立時會擲 null-check（見 `pdf_reader_view.dart:334` 註解），須先以 `isReady` 防呆。
- [x] **Step 4：補介面。** `PdfFacet.visiblePageRects()`、`PdfReaderSurface` 轉呼叫、`FakePdfFacet` 預設 `const []` 且可注入；確認其他實作 `PdfFacet` 的地方都編譯通過（`flutter analyze`）。
- [x] **Step 5：測試通過**，`flutter analyze` 乾淨。

## Task 3：`ReaderScreen` 接線

**Files：** 修改 `lib/screens/reader_screen.dart`；修改 `test/screens/reader_screen_test.dart`。

- [x] **Step 1：寫會失敗的測試。** 在既有「進入手動裁切模式…確認後寫回 prefs」案例旁新增（以 `FakePdfFacet` 注入 `visiblePageRects`）：
  - 頁面未填滿畫面時，拖滿整頁後確認，寫回的 `pdfCropRect` 約等於 `(0, 0, 1, 1)`，而不是畫面比例。
  - **已有生效中的手動裁切**（`pdfCropMode: manual`、`pdfCropRect: (0.1, 0.1, 0.9, 0.9)`）再裁切：框左半 → 寫回的矩形與合成結果一致（審查 I-1）。
  - **`pdfCropMode: none` 但殘留 `pdfCropRect`**：不合成，結果等於換算值。
  - 框完全在頁面外：不寫入、編輯模式仍開著（O2）。
  - `visiblePageRects` 回傳空清單：不寫入、編輯模式仍開著。
- [x] **Step 2：確認失敗。**
- [x] **Step 3：實作 `onConfirm` 換算**（依 O1、O2 的決定；經 `_surface.pdf`，不直接呼叫 `PdfReaderView` 靜態方法）。移除先前加入的 `[DEBUG-crop44]` ENTER／CONFIRM／CANCEL 記錄。
- [x] **Step 4：跑 `flutter test test/screens/reader_screen_test.dart --plain-name 裁切` 與 `test/screens/reader_screen_keyboard_test.dart`**，全數通過。

## Task 4：真機驗證（WAVE）

- [x] **Step 1：移除診斷記錄。** `pdf_crop_frame_overlay.dart` 的 `_dbg` 與所有 `[DEBUG-crop44]` 字串；`grep -rn "DEBUG-crop44" app/lib` 必須無結果（PowerShell：`Select-String -Path "app/lib/**/*.dart" -Pattern "DEBUG-crop44"`）。
- [x] **Step 2：建置並安裝。** `flutter build apk --debug`，`adb -s TCE70P24B2202374 install -r build/app/outputs/flutter-apk/app-debug.apk`。
- [x] **Step 3：重做本次實驗。** 開 PDF 第 48 頁 → 進入手動裁切 → 從頁面白紙左上角拖到右下角 → ✓。預期：版面不被切、左側文字完整（對照 `repro/issue-44-crop-result-left-clipped.png`）。
- [x] **Step 4：再做一次精確裁切。** 沿著文字框外緣拖，套用後文字四邊留白一致。
- [x] **Step 4b：二次裁切（審查 I-1）。** 已套用手動裁切後，再進入手動裁切，沿著目前顯示的文字外緣再縮一次，套用後版面與框選範圍一致，且不會被重設成整頁。
- [x] **Step 5：覆蓋 O3。** 拖拉過程中畫面不得捲動或縮放。
- [x] **Step 6：記錄結果**到 `epic.md`。

## Task 5：症狀 2 重現（不在本計畫修法範圍）

症狀 2（按 ✕ 取消後，下一次裁切拖拉畫面亂跳、自己放大）尚未重現。症狀 1 修好後，在乾淨狀態（無 `[DEBUG-crop44]` 之外的干擾）重現：「進入 → 取消 → 再進入 → 拖拉」，截圖與記錄存 `repro/`。若仍存在，另列為本 Epic 的後續 Issue，不併入本計畫。

- [x] **Step 1：在 WAVE 重現並記錄結果。** 結果：症狀 1 修好後畫面不再亂跳、不再自己放大，已一併解決。

## Task 6：收尾

- [ ] **Step 1：完整 `flutter test`**（無參數，`run_in_background`，在 `app/` 下）。
- [ ] **Step 2：`flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`。**
- [ ] **Step 3：更新 `epic.md`、`issues.md`（Issue 44 狀態）、`docs/epics.md` 備註。**
- [ ] **Step 4：commit**（明確路徑 `git add`，不加共同作者）。PR 走 Gitea。

## 審查回應（`reviews/review-plan-issue-44.md`，結論 Approved with Fixes）

| 項目 | 處置 |
|---|---|
| I-1 二次裁切未合成既有 `pdfCropRect` | **成立，已修**。對照 `reader_screen.dart:935-941`、`pdf_reader_view.dart:598-599` 確認：進入編輯模式不重設裁切模式，且 `_cropEnabled` 不看編輯模式，所以二次裁切時 `pageLayouts` 已是裁切後矩形。設計 1、3 加入 `activeCrop` 合成，並明列「只能在目前顯示範圍內再縮小」的限制；Task 1、3、4 補測試與真機項目。 |
| I-2 應經 `PdfFacet`，不直接呼叫 `PdfReaderView` | **成立，已修**。確認 `reader_screen.dart` 對 `PdfReaderView.xxx()` 的直接呼叫為 0（僅一行註解提及）。設計 2、3 與 Task 2 改為 `PdfFacet.visiblePageRects()`，`FakePdfFacet` 預設 `const []`。 |
| M-1 「無 Flutter 相依」用詞 | 成立，已改為「不依賴 `pdfrx`／Flutter widget，僅使用 `dart:ui` 值型別」。 |
| M-2 `viewportSize` 來源與單位 | 成立，已在設計 3 與 Global Constraints 寫明（`LayoutBuilder` 的 `size`、邏輯像素）。 |
| M-3 行號 569 → 580 | 成立，已更正。 |
| M-4 `grep` 與 PowerShell | 成立，Task 4 Step 1 補 `Select-String` 寫法。 |
| O1／O2／O3 | 審查同意計畫建議，維持不變。 |

## Review Focus

1. 已有生效中裁切時「只能再縮小、不能放寬」的行為限制是否可接受？替代做法：進入手動裁切時暫時停用裁切、顯示整頁（需要 `PdfReaderView` 在編輯模式下重排版，改動明顯較大，且 epic-58 設計「進入時整頁正常顯示」本來就預期這種行為）。
2. `visiblePageRects` 用 `visibleRect` ＋ `currentZoom` 換算，在逐頁（paginated）模式下是否與 `normalizeMatrix` 的夾制相容？（審查已確認相容，Task 4 Step 5 真機再驗。）
3. 智慧裁切與手動裁切共用 `pdfCropRect`；已存的舊裁切範圍仍是舊語意，不做資料遷移。

## 實作過程補記（2026-11-17）

- **Task 4 Step 5（拖拉時畫面不得捲動或縮放）**：通過，使用者回報「不會跳了」。
- **計畫外新增：裁切層拖拉跳動（症狀 3）。** 見 `epic.md`。多指並行追蹤、領頭規則、寬限期內任何距離都接力，都在 `pdf_crop_frame_overlay.dart`；對應測試在 `pdf_crop_frame_overlay_test.dart`。殘餘硬體雜訊另記後續項目。
- **審查 O3（連續捲動時拖拉不應移動畫面）**：真機確認通過。
