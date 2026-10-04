# `epic-58-pdf-crop-drag-select` PDF 手動裁切改為手指拖拉直接框選

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-58-pdf-crop-drag-select/`
**關聯 PRD 章節：** PDF 裁切（手動選區裁切）；關聯已歸檔 `epic-24-pdf-engine-rebuild` Issue 3

## 背景

目前手動選區裁切（`app/lib/reader/pdf_crop_frame_overlay.dart` 的 `PdfCropFrameOverlay`）進入後先顯示一個框（全頁或上次範圍），四角各有一個圓點，使用者拖圓點調整。使用者回報不直觀，希望改為「手指點一下後直接拖拉出要裁切的範圍」。

## 決策（2026-10-04 `/grill-with-docs`，使用者全數採建議）

1. **只能重畫，不留控制點**：放開手指後框固定；再拖拉一次就換成新框。四角圓點整組移除。移動／縮放既有框不在範圍，日後需要另立 Issue。
2. **進入時不顯示框**：整頁正常顯示，加提示「拖拉選取要保留的範圍」；手指一拖才出現遮罩與框。不再預載上次存的範圍。
3. **保留 ✕／✓ 按鈕**：放開手指不自動套用；尚未畫框時 ✓ 停用。
4. **無效選取與邊界**：輕點或拖出範圍任一邊小於 0.05（比例）視為無效，保留上一個框；座標 clamp 於 0～1；輸出仍是 0.0～1.0 的 `PdfCropRect`，雙頁並列語意不變。

## 處理方式

小型 UI 改動，直接 TDD，不寫 `plan-issue-N.md`；保留程式審查。

## 開發記錄

**2026-10-04** 登錄 Epic，決策如上，開始實作。

**2026-10-04 實作（直接 TDD）**

- 紅燈：改寫 `app/test/reader/pdf_crop_frame_overlay_test.dart`（無初始框＋提示、拖拉出框、反向拖拉正規化、重畫取代舊框、邊界 clamp、太小／輕點無效、確認鈕停用、取消），編譯即失敗（舊建構子需 `initialRect`）。
- 實作：`PdfCropFrameOverlay` 改為整面手勢層（`onPanDown`／`onPanUpdate`／`onPanEnd`／`onPanCancel`），移除 `initialRect` 與四角圓點；新增 l10n 字串 `readerPdfCropDragHint`（四個 arb＋`flutter gen-l10n`）；`reader_screen.dart` 不再傳 `initialRect`。`CropOverlayPainter` 與輸出 `PdfCropRect` 語意不變。
- `reader_screen_test.dart`「確認後寫回 prefs」案例改為先拖拉再確認。
- 驗證：`flutter analyze` 乾淨；`pdf_crop_frame_overlay_test.dart`＋`reader_screen_test.dart` 全數通過；l10n 硬編碼字串雙檢查 PASS。全套 `flutter test` 與程式審查尚未執行（發 PR 前補）。
- 未做：真機手感驗證（拖拉起點偏移、E-Ink 殘影）。

**2026-10-04 程式審查修訂**（`reviews/review-code.md`：0 Critical／3 Important／2 Minor）

- **I-1 成立，已修**：輕點／按下瞬間會畫出 0x0 框，上下遮罩合起來蓋滿全螢幕。紅燈測試重現。審查建議的「`onPanDown` 暫存＋`onPanStart` 才畫」實測無效——只有單一 pan 手勢時，按下當下 `onPanStart` 就觸發。改為只有手指真的移動過（`_dragCurrent != _dragStart`）才繪製即時框，已有的框在輕點時不消失。
- **I-3 成立，已修（做法與建議不同）**：實查 Flutter `monodrag.dart`，pan 已被接受後系統取消事件走 `onPanEnd`、不走 `onPanCancel`，因此審查建議的「拆 `_cancelDrag` 接 `onPanCancel`」不會生效。改以 `Listener` 直接處理原始指標事件（down／move／up／cancel）；cancel 放棄這次選取，只追蹤單一手指。
- **I-2 不成立，不改程式**：停用的確認鈕在圖示中心與圖示以外區域拖拉皆未穿透（測試通過，修前即綠）；測試保留作回歸保護。
- **M-1 不修**：寬或高為 0 的畫布收不到觸控事件，不會實際發生。
- **M-2 已補**：新增右上→左下、左下→右上的正規化測試。
- 驗證：`flutter analyze` 乾淨；`pdf_crop_frame_overlay_test.dart` 15 項通過。
- 全套 flutter test：3622 通過、1 略過、0 失敗（審查修訂後）。
