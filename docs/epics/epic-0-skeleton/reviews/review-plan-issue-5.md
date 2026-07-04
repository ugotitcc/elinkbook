# Code Review 報告：Issue 5 實作計劃文件審查 (`plan-issue-5.md`) - 複審通過

本報告針對 `docs/epics/epic-0-skeleton/plans/plan-issue-5.md` 實作計劃進行審查。審查依據為專案的系統設計文件（SDD），即 [spec.md](../../spec.md) 與 [design.md](../../design.md)。

---

## 評估摘要 (Assessment Summary)

* **評估結論：** **核准通過 (Approved / Ready to Proceed)**
* **總體評價：** 實作計劃已經針對前次審查意見完成調整與技術澄清。修正後的錯誤狀態處理能更安全地釋放原生 PlatformView 資源；作者針對 `didUpdateWidget` 與 `detectBookFormat` 所提出的 Pushback 具備充分的技術論證，本計畫已可交付執行。

---

## 優點與良好實作 (Strengths)

1. **嚴格遵守對外公開契約：**
   - 計劃中的 `ReaderScreen` 構造函數依然只接收 `filePath`，未因為測試需求或內部狀態同步而新增公開的 callback 參數（如 `onPageRendered` / `onError`）。這完美遵守了 `spec.md` 中的「唯一對外契約」。
2. **測試接縫 (Seam) 設計合理：**
   - 使用固定的 `Key`（`reader_loading_indicator`、`reader_error_text`）將內部狀態轉換暴露給 integration_test，解決了非同步 PlatformView 在一般 widget test 中難以被觀測的問題。
3. **遵循 SDD 的測試決策：**
   - 將 EPUB 與 PDF 的渲染驗證責任完全移轉給 `integration_test`，並僅在一般的 `flutter test` 中保留對 `unknown` 檔案格式的邏輯分支測試。這符合 SDD 中提及「一般的 widget test 中無法觀察 PlatformView 內渲染的真實內容」的測試決策。
4. **積極的審查互動與技術洞察：**
   - 作者針對審查意見進行了深度查證，指出了底層原生 View 封裝的限制，避免了引入無效且具誤導性的狀態重設代碼，展現了良好的工程嚴謹性。

---

## 審查意見回覆與確認紀錄 (Re-review History)

### 1. Important #1：錯誤狀態下未銷毀/隱藏原生視圖的資源風險
* **原意見：** 狀態轉為 `error` 時，原生視圖仍疊加在 Stack 最下層，有資源佔用風險。
* **回覆確認：** **已採納修正**。
  - 作者已更新 Task 1 Step 2 的 `_buildBody` 實作。當 `_state == _RenderState.error` 時，改為直接 return 錯誤文字元件（Early Return）。
  - 這能確保當載入失敗時，`EpubReaderView` 或 `PdfReaderView` 會從 widget tree 中被移除，從而觸發其 `dispose()` 以利原生資源清理。

### 2. Important #2：`didUpdateWidget` 中未重設狀態，導致 `filePath` 變更時狀態異常
* **原意見：** 建議實作 `didUpdateWidget` 以因應 `filePath` 變更時重設狀態為 `loading`。
* **回覆確認：** **接受 Pushback，維持原設計**。
  - **技術論證同意：** 經查證，底層的 `EpubReaderView` 與 `PdfReaderView`（依本工單全域限制不得修改）其 MethodChannel 與 `openBook` 呼叫皆綁定在 `_onPlatformViewCreated` 中，僅會執行一次。
  - 若在此處僅將 `ReaderScreen` 的狀態重設回 `loading`，因為底層原生視圖不會重新加載新檔案，畫面將會無限卡在載入狀態。
  - 基於本 Epic 導航皆為 `Navigator.push` 產生新實例（無同一頁面切換書籍情境），此處不處理 `didUpdateWidget` 是正確的決策，避免引入無效程式碼。

### 3. Minor #1：`detectBookFormat` 的同步與非同步擴充性提醒
* **原意見：** 建議在代碼中註記未來若改為魔數偵測（涉及 I/O）時需重構為非同步。
* **回覆確認：** **接受 Pushback，維持原設計**。
  - **技術論證同意：** 本工單不修改 `book_format.dart`（非本計劃 Task 1 修改範圍）。為避免擴大變更範圍至無關檔案，不進行預先設計與非必要的文件修改。
