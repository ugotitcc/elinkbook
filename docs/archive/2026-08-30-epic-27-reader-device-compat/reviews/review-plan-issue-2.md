# Epic 27 Issue 2 實作計畫審查報告

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-2.md`  
**審查目標：** 審查「開書逾時時間由固定 12 秒延長為 30 秒」實作計畫之架構合理性、測試設計、邊界防禦與可執行性。  
**審查標準：** 需求與根因對齊、TDD 兩段式邊界測試有效性、代碼與行號準確度、非必要改動排除（YAGNI）。  
**審查狀態：** 技術審查通過（Ready to implement）

---

## 1. 優點與亮點 (Strengths)

1. **TDD 測試設計嚴密（兩段式時間推進避免假綠燈）**：
   - 計畫在 Task 1 Step 1 中，並未單純地將 `tester.pump(const Duration(seconds: 12))` 直接改為 `tester.pump(const Duration(seconds: 30))`，而是巧妙地拆解為兩段推進：先 `tester.pump(const Duration(seconds: 29))` 斷言「尚未逾時，仍維持 loading indicator 且無 error text」，接著再 `tester.pump(const Duration(seconds: 1))` 斷言「滿 30 秒切換為錯誤畫面」。
   - 此設計極為嚴謹，徹底杜絕了若僅單次推進 30 秒時「即使實作仍停留在 12 秒舊邏輯，也會在 30 秒時誤判通過」的假綠燈漏洞，確保了測試能真實驗證 30 秒的精確門檻。

2. **嚴守最小變更與 YAGNI 原則**：
   - 明確將異動範疇限縮於 `reader_screen.dart`（`_openBookTimeoutTimer` 常數與其註解）及 `reader_screen_test.dart`（兩則既有逾時測試）。
   - 針對逾時錯誤提示文案，計畫忠實遵循 `issues.md` 的指引，不進行非必要的主觀措辭變更，避免擴大測試與回歸範圍。

3. **行號與程式碼引用 100% 精準**：
   - 經與目前程式庫交叉核對：
     - `reader_screen.dart:361-372`（欄位與註解）、`389-392`（`Timer` 初始化）
     - `reader_screen_test.dart:4981-5008`（逾時切換測試）、`5010-5038`（成功狀態不被覆蓋測試）
   - 所有行號與上下文程式碼片段完全吻合，可直接供執行 Agent 進行定位與修改。

4. **說明註解脈絡完整，保留領域知識傳承**：
   - 程式碼註解不僅更新了秒數，更詳細交代了從 Issue 33（12 秒推測值）到 Issue 2（Mobiscribe WAVE 真機回報與使用者確認值 30 秒）的演進歷史與參考文件路徑，對後續維護者極為友善。

5. **執行步驟與驗證指令清晰完備**：
   - 清楚規範 Red-Green-Refactor 流程（Step 1-2 修改測試 -> Step 3 驗證紅燈 -> Step 4 修改實作 -> Step 5 驗證綠燈 -> Step 6 全專案靜態分析與測試 -> Step 7 規範之 Git Commit），具備高度可操作性。

---

## 2. 問題與疑慮 (Issues)

經全面審查，本計畫無阻礙實作之問題（無 Critical / Important 項目）。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)

#### 【Minor #1】真機開書體驗提示
- **說明：** 延長開書逾時至 30 秒可有效避免 Mobiscribe WAVE 等慢速硬體在載入大型書籍時發生誤判。然而若未來遇到極端損毀的書籍，使用者最多需等待 30 秒才會看到錯誤提示。
- **建議：** 此為已知之產品取捨，目前 30 秒為使用者確認的最佳折衷值。後續若有使用者反饋等待時間感受，可再評估是否於 UI 載入指示器周圍加入更細緻的載入進度或提示文字。

---

## 3. 實作建議 (Recommendations)

1. **嚴格遵循 TDD 驗證順序**：
   - 請執行者在 Step 1-2 套用測試修改後，務必先執行 Step 3 的測試指令，確認 Step 1 確實在 29 秒時紅燈（FAIL），再進行 Step 4 的程式碼修正，確保測試發揮防禦效益。
2. **保持靜態分析與全域測試零回歸**：
   - 實作完成後務必執行 `flutter analyze` 與 `flutter test`，確保專案乾淨無警告。

---

## 4. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**  
  **【是 / 準備好開始實作 (Ready to implement)】**

- **評估理由：**  
  本計畫目標單純精準、測試設計包含精妙的兩段式邊界驗證、行號與代碼引用 100% 精確，完全符合敏捷與 TDD 規範，已具備立即實作之條件。
