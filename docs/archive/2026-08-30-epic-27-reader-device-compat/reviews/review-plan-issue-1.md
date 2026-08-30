# Epic 27 Issue 1 實作計畫審查報告

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-1.md`  
**審查目標：** 審查「EPUB/PDF 載入中點擊熱區導致崩潰畫面（loading 狀態防呆）」實作計畫之架構合理性、測試設計、邊界防禦與可執行性。  
**審查標準：** 根因對照精確度、單一權責與防呆層級設計、TDD 測試有效性與回歸風險排除、代碼與行號準確度。  
**審查狀態：** 技術審查通過（Ready to implement）

---

## 1. 優點與亮點 (Strengths)

1. **架構分層精準，嚴守單一權責原則**：
   - 計畫將防呆點明確鎖定於 `_handleZoneAction`（`reader_screen.dart` 的統一分派入口），不向下污染 `FoliateEpubReaderView` 與 `PdfReaderView`。
   - 經程式碼核對，`previousPage`/`nextPage` 的 4 個 static helper 在生產程式碼中的唯一呼叫來源正是 `_handleZoneAction`。在入口處統一以 `_state == _RenderState.loading` 阻擋，同時涵蓋熱區點擊、音量鍵事件與測試輔助方法，成本最低、效益最高，且符合「書籍生命週期狀態歸屬 `ReaderScreen`」的架構分界。

2. **精準排查隱蔽測試地雷（高度防禦意識）**：
   - 計畫精準指出了既有測試 `reader_screen_test.dart` 第 5807 行（「PDF 換頁時應清除既有選取狀態」）的非同步等待盲點——該測試在原先無防呆時因 `_state` 仍為 `loading` 也能穿透執行，一旦加入防呆該測試會立即紅燈。
   - 計畫在 Task 1 Step 1 內主動將該既有測試補上 `pdfView.onPageRendered()`，既忠於該測試原本「驗證已渲染完成後換頁清除選取」的初衷，又徹底消除了 CI 潛在破壞，分析極為透徹。

3. **在純 Dart 測試環境下巧妙建構可驗證斷言**：
   - 由於 widget test 中 `FakeInAppWebViewPlatform` 下 WebView Controller 恆為 null，無法直接觀測 JS 例外；計畫巧妙利用 PDF 換頁時清除選取（`AnnotationToolbar`）的副作用，透過斷言 `AnnotationToolbar` 在 loading 下換頁「不被清除」成功構造出可驗證防呆分支已提前 return 的有效測試，測試設計極富技巧且嚴密。

4. **邊界動作隔離周全**：
   - 明確區分 `ZoneAction.menu` 與換頁動作（`previousPage`/`nextPage`），`menu` 僅切換沉浸模式 `_chromeVisible` 布林值，不加防呆以維持既有使用者體驗並避免破壞既有選單測試。

5. **TDD 規範與執行步驟清晰具體**：
   - 嚴格遵循 Red-Green-Refactor 流程（Step 1 寫測試 -> Step 2 驗證紅燈 -> Step 3 實作防呆與註解 -> Step 4 綠燈 -> Step 5 全專案 analyze/test 零回歸 -> Step 6 Commit）。
   - 程式碼段落、行號（`reader_screen.dart:2354-2424`、`reader_screen_test.dart:5807-5868`）與目前程式庫完全一致，具備 100% 的可執行性。

---

## 2. 問題與疑慮 (Issues)

經全面審查，本計畫無阻礙實作之問題（無 Critical / Important 項目）。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)

#### 【Minor #1】真機 / 整合層驗收提示
- **說明：** 如計畫自身於 Global Constraints 中坦誠說明的限制，純 Dart 單元測試僅能驗證 Dart 端的防呆提前 return 與選取狀態，無法真正測試 Chromium/WebView 環境下 JS 呼叫是否被攔截。
- **建議：** 實作者完成 Task 1 並確保 `flutter analyze` 與 `flutter test` 全數通過後，建議於真機（如 Mobiscribe WAVE 或 Android 模擬器）上開啟大型 EPUB，在轉圈載入期間快速連續點擊左/右導覽熱區進行最終驗收，確保 JS 例外徹底消失。

---

## 3. 實作建議 (Recommendations)

1. **嚴格按照 Step 順序執行**：
   - 先行套用 Step 1 測試修改（包含既有 PDF 測試的 `pdfView.onPageRendered()` 補充），執行 Step 2 觀察測試確實如預期失敗（紅燈），再進行 Step 3 的防呆撰寫，以確保測試的真實保護力。
2. **保持專案靜態分析零警告**：
   - 實作完成後執行 `flutter analyze` 與 `flutter test`，確保無任何語法或型別瑕疵。

---

## 4. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**  
  **【是 / 準備好開始實作 (Ready to implement)】**

- **評估理由：**  
  本計畫問題根因定位精準、架構改動精簡且符合單一權責、邊界條件處理完整；特別是對既有測試潛在地雷的排查與純 Dart 下測試斷言的構造極為嚴謹，已完全符合上線實作標準。
