# Issue 45：PDF 手動裁切——已裁切時再進入改顯示完整頁面，並新增「還原」鈕　實作計畫

> **給執行者：** 步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就改為 `- [x]`。**本計畫先審查，審查通過前不得修改 `lib/`。**

**Goal：** 已有生效中裁切時再次進入手動裁切，編輯畫面顯示**未裁切的完整頁面**；底部多一顆「還原」鈕，可取消編輯、回到進入前的裁切；X 改為「放棄裁切」（離開後為不裁切）。

**Architecture：** 編輯期間只靠暫態旗標 `cropEditModeActive` 讓 `PdfReaderView` 暫時不套用裁切，**不改寫 `book_reader_prefs`**（只有 ✓ 才寫入）。`PdfCropFrameOverlay` 新增選用的 `onRestore` 回呼，非 null 才顯示還原鈕。`ReaderScreen` 依進入時是否有生效裁切決定傳不傳 `onRestore`，並移除 Issue 44 的「合成回原始座標」分支。

**Tech Stack：** Flutter／Dart、`pdfrx`、`flutter_localizations`（arb）。指令一律在 `app/` 目錄下執行。

**Spec：** `epic-54` 的 `issues.md` Issue 45 列；詞彙見 `CONTEXT.md`「裁切編輯模式」（2026-11-18 `/grill-with-docs` 定案 Q1～Q10）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。
- **偏好不變**：編輯期間不得寫入 `book_reader_prefs`；`PdfCropRect` 儲存格式、`pdfCropMode` 三選一語意、智慧裁切輸出一律不變。
- **返回鍵／Esc 不離開裁切編輯模式**（`PopScope.canPop: !_cropEditModeActive` 與 Esc 吞掉的行為不動）。
- **不加確認對話框**；X 只加 tooltip。
- **按鈕順序**：X、還原（`Icons.undo`）、✓，樣式同現有圓形鈕。
- **不破壞閱讀面抽象邊界**：`ReaderScreen` 只經 `_surface.pdf!`（`PdfFacet`）呼叫 PDF 功能。
- **提交**：不加 `Co-Authored-By`；PR 與分支走 Gitea，不用 `gh`。計畫與實作同分支、同 PR。
- **真機**：Mobiscribe WAVE（`TCE70P24B2202374`）。禁用 `flutter install`，一律 `adb install -r`。
- **測試範圍**：單一 Task 只跑異動觸及的測試；完整 `flutter test` 只在最後一個 Task 跑一次。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`。

## Review Focus

1. **進入時是「智慧自動裁切」（`autoDetect`）**：按還原後仍是智慧裁切、矩形不變；不得因編輯期間暫時視為未裁切而重新偵測或覆寫矩形（`_maybeDetectCropRect` 只看 `widget.pdfCropMode`／`pdfCropRect`，不能受旗標影響）。
2. **進入時 mode 為 none 但殘留舊矩形**：視為「沒有生效裁切」，不顯示還原鈕，X 不寫 prefs。
3. **編輯期間 App 被殺／旋轉螢幕**：prefs 未被改，重開後仍是原裁切；旋轉後框座標仍相對完整頁面。
4. **編輯期間疊圖快取**：加粗／裁切疊圖快取鍵含裁切矩形，旗標切換後不得沿用已裁切的疊圖。
5. **進入與離開時頁碼保持**：切換版面後停在同一頁（沿用 `didUpdateWidget` 的 reanchor）。

---

## 檔案結構

| 檔案 | 責任 |
|---|---|
| `app/lib/reader/pdf_reader_view.dart` | `_cropEnabled` 在 `cropEditModeActive` 為 true 時回傳 false；`didUpdateWidget` 的變更偵測納入該旗標 |
| `app/lib/reader/pdf_crop_frame_overlay.dart` | 新增 `onRestore`、還原鈕、X 與還原的 tooltip |
| `app/lib/l10n/app_{zh_TW,zh,zh_CN,en}.arb`＋生成檔 | 新增 2 個字串 |
| `app/lib/reader/pdf_crop_mapping.dart` | 移除 `activeCrop` 參數與合成分支 |
| `app/lib/screens/reader_screen.dart` | X 放棄裁切、還原、簡化 `_resolveManualCropRect` |

---

### Task 1：`PdfReaderView` 編輯期間顯示完整頁面

**Files：**
- Modify: `app/lib/reader/pdf_reader_view.dart`（`_cropEnabled` 約 610 行；`didUpdateWidget` 變更偵測約 946 行；**必改**的疊圖快取鍵三處：1519 `_buildProcessedOverlay`、1610 `_isOverlayJobStillWanted`、1647 `_recomputeOverlay`，三處都直接用 `widget.pdfCropRect`，漏改任一處會使疊圖被丟棄）
- Test: `app/test/reader/pdf_reader_view_crop_edit_test.dart`（新增，沿用 `pdf_reader_view_visible_page_rects_test.dart` 的測試 PDF 與 pump 方式）

**Interfaces：**
- Produces：`PdfReaderView.cropEditModeActive == true` 時，版面、疊圖、註記座標換算都當作「未裁切」；`pdfCropMode`／`pdfCropRect` 屬性值不變，`_maybeDetectCropRect` 行為不變。

- [x] **Step 1: 寫失敗測試**（三個）
  - `'已有手動裁切，cropEditModeActive 為 true 時，可見頁面長寬比等於未裁切的頁面'`：用**非等比**裁切 `pdfCropRect: (0.0, 0.2, 1.0, 0.8)`（等比裁切在 pageFit 下寬度不變，量不出差異）。先以 `pdfCropMode: none` 取 `visiblePageRects` 第一頁 `rectInViewer` 的長寬比 `aspectFull`；再以 `manual`＋該矩形、`cropEditModeActive: false` 取 `aspectCropped`，斷言兩者不等（`isNot(closeTo(aspectFull, 1e-3))`）；最後改 `cropEditModeActive: true` pump，斷言長寬比 `closeTo(aspectFull, 1e-3)`。
  - `'cropEditModeActive 切回 false 後，恢復為裁切後的頁面寬度'`。
  - `'autoDetect 且矩形已快取，cropEditModeActive 為 true 時不呼叫 onCropRectComputed'`。
  - `'已有裁切且加粗強度大於 0，切換 cropEditModeActive 後疊圖仍會產生，不被丟棄'`（覆蓋 1519／1610／1647 三處；觀察方式比照 `pdf_reader_view_filters_test.dart` 既有 bold overlay 測試）。
- [x] **Step 2: 跑測試確認失敗** — `flutter test test/reader/pdf_reader_view_crop_edit_test.dart`，預期前兩個 FAIL。
- [x] **Step 3: 實作** — 新增私有 getter `PdfCropRect? get _activeCropRect => _cropEnabled ? widget.pdfCropRect : null;`，`_cropEnabled` 改為 `!widget.cropEditModeActive && widget.pdfCropMode != PdfCropMode.none && widget.pdfCropRect != null`；1519、1610、1647 三處疊圖快取鍵 `crop:` 改讀 `_activeCropRect`。其餘使用處（442、1264、1549、1571、1586、2102）已被 `_cropEnabled ?` 保護、`_layoutCroppedPages`（1672）只在 `_cropEnabled` 為 true 時被呼叫，不需改。`_dualPageEnabled` 與 `_maybeDetectCropRect` **不動**。`didUpdateWidget` 的 `changed` 加上 `oldWidget.cropEditModeActive != widget.cropEditModeActive`，沿用既有 reanchor 保持頁碼。
- [x] **Step 4: 跑測試確認通過**，並跑 `test/reader/pdf_reader_view_visible_page_rects_test.dart`、`pdf_reader_view_filters_test.dart`、`pdf_reader_view_paginated_test.dart` 確認無回歸。
- [x] **Step 5: Commit** — `feat(reader): PDF 裁切編輯期間暫時顯示完整頁面（epic-54 Issue 45）`

### Task 2：`PdfCropFrameOverlay` 還原鈕與 tooltip

**Files：**
- Modify: `app/lib/reader/pdf_crop_frame_overlay.dart`（建構子約 70 行；底部按鈕列約 342 行）
- Modify: `app/lib/l10n/app_zh_TW.arb`（含 `@` 描述）、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`；再跑 `flutter gen-l10n` 更新生成檔
- Test: `app/test/reader/pdf_crop_frame_overlay_test.dart`

**Interfaces：**
- Produces：`PdfCropFrameOverlay({..., VoidCallback? onRestore})`；`onRestore != null` 才顯示 `Key('pdf_crop_frame_restore')` 的 `Icons.undo` 圓鈕，順序 X、還原、✓（間距同現有 48）。
- 新字串：`readerPdfCropAbandonTooltip`（zh_TW「放棄裁切」／zh_CN「放弃裁切」／en「Discard crop」）、`readerPdfCropRestoreTooltip`（「還原先前裁切」／「还原先前裁切」／「Restore previous crop」）。X 套 `Tooltip(message: abandon)`、還原套 `Tooltip(message: restore)`。

- [ ] **Step 1: 寫失敗測試**：
  - `'onRestore 為 null 時不顯示還原鈕'`
  - `'onRestore 非 null 時顯示還原鈕，點擊呼叫 onRestore 且不呼叫 onCancel／onConfirm'`
  - `'三顆鈕由左至右為 cancel、restore、confirm'`（比對 `tester.getCenter(...).dx` 遞增）
  - `'X 鈕與還原鈕各有 tooltip 文字'`（`find.byTooltip`）
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作** 上述建構子參數、按鈕、tooltip 與 4 份 arb；跑 `flutter gen-l10n`。
- [ ] **Step 4: 跑測試通過**，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- [ ] **Step 5: Commit** — `feat(reader): 裁切編輯畫面新增還原鈕與 tooltip（epic-54 Issue 45）`

### Task 3：`ReaderScreen` 串接，並移除合成分支

**Files：**
- Modify: `app/lib/reader/pdf_crop_mapping.dart`（移除 `activeCrop` 參數、合成分支與 `pdf_selection_geometry`／`percent_rect` 的匯入）
- Modify: `app/lib/screens/reader_screen.dart`（`_resolveManualCropRect` 約 952 行；覆蓋層建構約 2694 行；新增 `bool get _hasActiveCrop`）
- Test: `app/test/reader/pdf_crop_mapping_test.dart`、`app/test/screens/reader_screen_test.dart`（「PdfCropFrameOverlay 座標換算（Issue 44）」群組約 9379 行與其後的 `PdfCropFrameOverlay` 群組）

**Interfaces：**
- Consumes：Task 1（`cropEditModeActive` 讓畫面顯示完整頁面）、Task 2（`onRestore`）。
- Produces：`bool get _hasActiveCrop`（先取 `final resolved = _resolved;`，`resolved != null && resolved.pdfCropMode != PdfCropMode.none && resolved.pdfCropRect != null`，不使用 `!`）（與 `PdfReaderView._cropEnabled` 同條件）；`viewportRectToPageCropRect({required PdfCropRect viewportRect, required Size viewportSize, required Rect pageRectInViewport, double minFraction = 0.05})`。

- [ ] **Step 1: 調整與新增測試**
  - `pdf_crop_mapping_test.dart`：刪除所有帶 `activeCrop` 的案例，其餘不變。
  - `reader_screen_test.dart`：
    - 改寫 `'已有生效中的手動裁切：框左半，合成回原始整頁座標'` 為 `'已有生效中的手動裁切：再次進入時框座標相對完整頁面，不合成'`（完整頁面填滿畫面、框左半 → 存 `(0,0,0.5,1)`）。
    - 新增 `'已有生效裁切：進入編輯後顯示還原鈕；按還原離開且 prefs 不變（mode 與矩形皆同進入前）'`。
    - 新增 `'已有智慧裁切（autoDetect）：按還原後 mode 仍為 autoDetect、矩形不變'`。
    - 新增 `'已有生效裁切：按 X 離開後 pdfCropMode 變為 none'`。
    - 新增 `'原本未裁切：不顯示還原鈕；按 X 不寫 prefs'`（既有取消測試保留，補斷言找不到 `pdf_crop_frame_restore`）。
    - 新增 `'mode 為 none 但殘留舊矩形：不顯示還原鈕'`。
    - 新增 `'編輯期間 prefs 未被寫入'`（進入後、按鈕前檢查 `prefsManager.bookPrefsByBookId` 與進入前相同）。
- [ ] **Step 2: 跑測試確認失敗**（新增與改寫者 FAIL）
- [ ] **Step 3: 實作**
  - `_resolveManualCropRect`：刪除 `mode`／`activeCrop` 計算，呼叫 `viewportRectToPageCropRect` 時不再傳 `activeCrop`，並更新方法註解（編輯期間顯示完整頁面，座標恆相對完整頁面）。
  - 覆蓋層：`onRestore: _hasActiveCrop ? () => setState(() => _cropEditModeActive = false) : null`；`onCancel`：`final had = _hasActiveCrop; setState(() => _cropEditModeActive = false); if (had) _handlePrefsChanged(_prefs.copyWith(pdfCropMode: PdfCropMode.none));`（須在 `setState` 之前先取 `had`，因為兩者之間 `_resolved` 不會變，但順序固定較不易出錯）。
  - 更新 `pdf_crop_mapping.dart` 檔頭註解，刪除「生效時合成」的描述。
- [ ] **Step 4: 跑測試通過** — `flutter test test/reader/pdf_crop_mapping_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/screens/reader_screen_test.dart`；`flutter analyze` 乾淨。
- [ ] **Step 5: Commit** — `feat(reader): 手動裁切再進入顯示完整頁面，X 放棄裁切、新增還原（epic-54 Issue 45）`

### Task 4：收尾與真機驗證

**Files：** `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`（epic-54 那列備註）

- [ ] **Step 1: 完整測試** — `flutter test`（無參數）、`flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`。已知偶發失敗（`download_queue_controller_test`、`pdf_reader_view_filters_test`）單獨重跑通過即記錄，不視為本 Issue 回歸。
- [ ] **Step 2: WAVE 真機驗證**（`adb install -r`）：
  1. 已手動裁切的 PDF → 版面設定選手動 → 看到完整頁面、底部三顆鈕；按還原 → 回原裁切、頁碼不變。
  2. 再進入 → 重框 → ✓ → 新裁切生效，且框選範圍＝套用範圍。
  3. 再進入 → 按 X → 變為不裁切。
  4. 原本未裁切 → 進入只有 X 與 ✓。
  5. 智慧裁切 → 進入 → 還原 → 仍是智慧裁切。
  6. 編輯中按返回鍵，不離開編輯。
- [ ] **Step 3: 文件** — `epic.md` 補「Issue 45 決議（2026-11-18 `/grill-with-docs`）」摘要與驗證結果；`issues.md` Issue 45 狀態更新；`docs/epics.md` epic-54 備註補一句。未驗證項目如實標註。
- [ ] **Step 4: Commit** — `docs(epic-54): Issue 45 收尾紀錄`

---

## 自我審查

- **決議覆蓋**：Q1（X 放棄）→ Task 3；Q2／Q3（還原鈕僅已有裁切時出現、原樣保留 mode）→ Task 2／3；Q4（不寫 prefs）→ Task 1 旗標＋Task 3 測試；Q5（返回鍵不變）→ Global Constraints，未改相關程式；Q6（移除合成）→ Task 3；Q7（保持頁碼）→ Task 1 沿用 reanchor；Q8／Q9（按鈕順序、tooltip）→ Task 2；Q10（記入 epic-54）→ Task 4。
- **已知取捨**：編輯期間 `_dualPageEnabled` 不改（仍依 `pdfCropMode`），即已裁切書編輯時維持單頁；原本未裁切的雙頁書行為與現況相同。
- **2026-11-18 審查修訂**（`reviews/review-plan-issue-45.md`）：C-1 部分採納（只有三處快取鍵必改，其餘已被保護）；C-2 採納（改用非等比裁切與長寬比斷言）；M-1、M-2 採納。
- **風險**：Task 1 在 pdfrx 的版面快取（`_cachedLayoutKey`）是否納入旗標需在測試中確認；若兩次 `visiblePageRects` 寬度相同，代表快取鍵漏了旗標，須修正鍵而非繞過。
