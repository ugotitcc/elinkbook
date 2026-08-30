# Epic 27 Issue 9 實作計畫審查報告

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-9.md`  
**審查目標：** 審查「流式 EPUB 長按選字／劃線時容易誤觸翻頁」實作計畫之架構合理性、觸控手勢競爭模型、TDD 測試設計、邊界防禦與可執行性。  
**審查標準：** 需求與根因對齊、手勢熔斷機制有效性、TDD 測試鑑別力與指令精確度、非必要改動排除（YAGNI/最小可行範圍）。  
**審查狀態：** ✅ 技術審查通過（Ready to implement）

---

## 1. 審查摘要與問題檢核 (Summary & Issue Verification)

| 檢核維度 | 審查結果 | 評估說明 |
| :--- | :---: | :--- |
| **根因與範圍對齊** | ✅ **完全通過** | 精準對齊 `issues.md` Issue 9 與 `reviews/bugfix-repro.md` Issue 9 定案之最小可行修復範圍（`onPointerMove` 熔斷 ＋ `no-swipe` 屬性），果斷將需真機調校之第 3-5 項留給後續驗證，嚴格恪守 YAGNI。 |
| **手勢競爭模型分析** | ✅ **完全通過** | 正確剖析 Flutter 側 `TapZoneDetector` 放開判定時序與 JS 側 `paginator.js` 滑動換頁之獨立競爭路徑，拆分為兩個無依賴的 Task 分別處理。 |
| **TDD 測試鑑別力** | ✅ **完全通過** | Task 1 Step 1 測試案例精確模擬「選字時先拖曳超標、放開前移回原點」之真實手勢，能明確鑑別 `onPointerMove` 熔斷前（FAIL）與熔斷後（PASS）之行為差異。 |
| **上下文與行號精準度** | ✅ **完全通過** | 經與程式庫實體交叉核對：`tap_zone_detector.dart:43-56/66-96`、`tap_zone_detector_test.dart:74-97`、`main.js:885-889` 之行號與代碼上下文 100% 精確吻合。 |
| **相容性與回歸防範** | ✅ **完全通過** | `TapZoneDetector` 修改對 PDF／EPUB 同時生效且邏輯等價於既有 `onPointerCancel`；`setAttribute('no-swipe', '')` 對流式生效且對 FXL 元素安全無害，不影響捲動模式與音量鍵。 |

經全面審查，本計畫發現 **0 Critical / 0 Important / 0 Minor** 問題，架構設計健全，邏輯自洽。

---

## 2. 優點與亮點 (Strengths)

1. **手勢熔斷設計精簡且具備完全防禦性（Task 1）**：
   - 計畫在 `TapZoneDetectorState` 引入 `onPointerMove` 監聽，一旦位移超過 `widget.tapSlop`（18px），立即將 `_downPosition` 與 `_downTimeMs` 設為 `null`。
   - 此設計極為簡潔，直接複用既有 `onPointerUp` 的 `if (downPosition == null || downTimeMs == null) return;` 防禦退出邏輯，無需引入額外的布林狀態旗標，實現「零狀態殘留」的即時熔斷。
   - 同時讓共用該元件的 PDF 閱讀器（`pdf_reader_view.dart`）一併獲得防禦效益，單一元件單一維護。

2. **徹底根治 `paginator.js` 側的手勢爭搶（Task 2）**：
   - 充份利用 `paginator.js` 原生支援的 `no-swipe` 屬性（`paginator.js:2186/2499/2558`），在 `main.js` `view.open(book)` 完成後立即透過 `view.renderer.setAttribute('no-swipe', '')` 套用。
   - 徹底關閉 WebView 內部的滑動換頁與放開時的 `snap()` 判定，將翻頁機制 100% 收斂至 Flutter 側 3×3 九宮格與實體音量鍵，完全符合 ADR 0011（不修改 vendored 原始碼）。
   - 代碼放置位置（`main.js:886`）為既有 `view.renderer.setAttribute('flow', ...)` 之同處，確保 `view.renderer` 於執行期已完全就緒。

3. **TDD 測試設計具備高度鑑別力**：
   - Task 1 Step 1 測試透過 `startGesture(50,50)` → `moveTo(50,90)`（位移 40px > 18px）→ `moveTo(50,52)`（位移 2px < 18px）→ `up()` 序列，構造出「中途超標但釋放時落回容許範圍」的手勢形狀。
   - 此測試在未實作 `onPointerMove` 前必為 FAIL（因為原本只在 `up()` 當下算距離），實作後必為 PASS，測試失敗原因（`reason:`）說明詳盡，是教科書級的 TDD 測試用例。

4. **已知局限誠實記錄與人工驗證閉環**：
   - 計畫清楚標註 Task 2 膠水層 JS 缺乏純 Dart 自動化測試之局限，並提供基於 Chrome DevTools（`document.getElementById('view').renderer.getAttribute('no-swipe')`）的清晰人工驗證步驟，務實可行。

---

## 3. 實作建議 (Recommendations)

1. **嚴格遵循 TDD 紅白綠循環**：
   - 執行 Task 1 時，請務必先完成 Step 1 測試並在 Step 2 執行 `flutter test test/reader/tap_zone_detector_test.dart --plain-name "拖曳中途超過容許位移範圍"` 確認測試紅燈（FAIL），再進入 Step 3 實作。
2. **維持全專案測試零回歸**：
   - 實作完成後執行 `cd app && flutter analyze && flutter test`，確認全專案靜態分析乾淨且全數測試通過。

---

## 4. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**  
  **【是 / 準備好開始實作 (Ready to implement)】**

- **評估理由：**  
  實作計畫 `plan-issue-9.md` 結構完整、根因剖析精確、TDD 步驟詳實且具備高度鑑別力、代碼行號與上下文 100% 精準對齊現有程式庫。全案 0 Critical / 0 Important / 0 Minor，具備立即開始實作之條件。
