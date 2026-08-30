# Review — Epic 27 Issue 11：長按已畫線區域改由畫線工具列統一處理（實作計畫審查報告）

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-11.md`  
**對應工單：** `docs/epics/epic-27-reader-device-compat/issues.md` Issue 11  
**設計規格：** `docs/superpowers/specs/2026-08-24-epic27-issue11-annotation-toolbar-merge-design.md`  
**審查日期：** 2026-08-24  
**審查性質：** 實作計畫審查（Implementation Plan Review）  

---

## 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接執行）**

本實作計畫（Plan）條理分明、步驟完整，嚴格遵循 TDD（Red-Green-Refactor）開發節奏。計畫不僅完整落實了設計規格與前輪設計審查報告中指出的所有關鍵細節（PDF 座標逆轉換、非同步世代競速防護、搜尋高亮已知限制），更主動在實作層面做出三項優秀的架構優化（抽取 `annotation_resolution.dart` 純函式、復用 `pdfrx.PdfRect.overlaps`、給予 `text` 預設值以減少測試擾動），大幅提升了程式碼的可測性與穩健度。

---

## Strengths（優點）

1. **架構簡化與可測性大幅提升（超越原 Spec 的優化）**：
   - 將標記命中判斷從 `_ReaderScreenState` 抽取為頂層純函式（`annotation_resolution.dart` 的 `resolveEpubExistingAnnotation` 與 `resolvePdfExistingAnnotation`），使得命中邏輯可以直接用純單元測試驗證，無需 pump 整座 `ReaderScreen`。
   - 發現並直接復用 `pdfrx_engine` 內建的 `PdfRect.overlaps`，免去自行維護重複的矩形幾何邏輯。
   - `PdfSelectionInfo` 不硬套 EPUB 的字串編解碼路徑，維持 PDF 純 Dart 記憶體物件的簡潔性。

2. **精準落實設計審查的關鍵防護**：
   - **座標逆轉換**：Task 1 & 4 精確使用代數逆推公式 `(1.0 - rect.top) * pageHeight`（對應 `PdfRect.top` 較大值）與 `(1.0 - rect.bottom) * pageHeight`（對應 `PdfRect.bottom` 較小值），並於單元測試中斷言 `top >= bottom`，徹底杜絕 PDFium assert 例外。
   - **非同步世代競速防護**：Task 4 引入 `_selectionDragGenerationId`，在手勢起點與 `_finishSelectionDrag` 遞增，並於 `await _extractTextInRect` 後校驗 `!mounted || generationId != _selectionDragGenerationId`，配備了完整的競速模擬測試。

3. **Surgical Changes（最小擾動原則）**：
   - `EpubSelectionInfo` 與 `PdfSelectionInfo` 的 `text` 欄位提供預設值 `''`，避免導致專案內既有 9 處無關測試發生大量參數補齊 churn。

4. **TDD 流程嚴謹完備**：
   - 8 個 Task 均明確列出 Files、Interfaces、紅燈測試程式碼、綠燈實作程式碼、驗證指令與 Commit 規範。
   - 測試手法成熟，例如剪貼簿測試使用 `TestDefaultBinaryMessengerBinding` 搭配 `addTearDown`，避免測試狀態污染。

5. **舊機制汰除徹底**：
   - Task 8 明確列出刪除 `_showAnnotationActionDialog`、`_handleAnnotationActivated`、3 個孤立的查找 helper（`_findHighlightById` 等）、`onAnnotationActivated` handler 及 JS 端 `show-annotation` 監聽器，並補上靜態回歸防護。

---

## Issues & Notes（注意事項與執行提醒）

### Critical / Important
無（無阻礙執行的架構性或功能性問題）。

### Minor / Execution Notes (執行時留意事項)

1. **Task 6 跨 Task 7 的靜態分析過渡期**：
   - 計畫已正確指出：在 Task 6 為 `AnnotationToolbar` 新增 `required onCopyPressed` 後，`reader_screen.dart` 尚未補上參數，全專案 `flutter analyze` 會短暫出現錯誤。執行 Task 6 時請依計畫指引使用 `flutter analyze lib/screens/annotation_toolbar.dart test/screens/annotation_toolbar_test.dart` 縮小範圍驗證，待 Task 7 接線完成後再執行全專案靜態分析。

2. **工具列尺寸常數微調**：
   - 計畫將 `_annotationToolbarHeight` 設為 104.0、`_annotationToolbarWidth` 設為 256.0。若執行 Task 7 Step 8 時既有的「工具列右緣不超出螢幕」測試有微幅數值落差，請依測試量測到的實際 widget render 尺寸調整常數。

---

## 結論（Conclusion）

- **審查結論：Approved（核准執行）**
- **建議下一步：** 呼叫 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 開始逐 Task 執行實作。
