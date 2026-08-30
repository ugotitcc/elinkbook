# Epic 27 Issue 2 程式碼審查報告

**審查對象：** commit 範圍 3d26a3e..34b5fda（分支 fix/epic-27-issue2-open-book-timeout）
**審查目標：** 審查「`_openBookTimeoutTimer` 固定逾時值由 12 秒延長為 30 秒」的實際程式碼變更是否忠實對應 `plans/plan-issue-2.md` 與 `issues.md` Issue 2 的驗收標準，特別是計畫刻意設計的 29 秒＋1 秒兩段式邊界斷言是否確實落實、且真能區分「30 秒」與「任何大於 12 秒的值」。
**審查標準：** 計畫對齊度、程式碼品質（文件註解正確性、範圍控制）、測試有效性（含實際執行 `flutter test`／`flutter analyze` 驗證，非僅閱讀程式碼推測）。
**審查狀態：** 已完成（含實機執行測試與分析驗證）

---

## 1. 優點與亮點 (Strengths)

1. **與計畫逐字對齊，零範圍外變更**：`git diff --stat` 顯示本次變更只觸及 `app/lib/screens/reader_screen.dart`（+8/-5）、`app/test/screens/reader_screen_test.dart`（+18/-4）與 `plans/plan-issue-2.md`（勾選框收尾，非程式碼），與 `Global Constraints` 宣告的「只修改這兩個檔案」完全一致，沒有任何範圍外異動。`Duration(seconds: 12)` → `Duration(seconds: 30)` 這個唯一的邏輯改動，以及文件註解、測試數值的修改內容，逐字對應計畫 Step 1／Step 2／Step 4 給出的程式碼片段。

2. **兩段式邊界斷言確實落實，且真的能區分「30 秒」與「大於 12 秒的任意值」**：`reader_screen_test.dart:5008` 先 `pump(Duration(seconds: 29))` 並斷言 `reader_loading_indicator` 仍存在、`reader_error_text` 仍不存在（5009-5012），再 `pump(Duration(seconds: 1))` 補滿 30 秒後才斷言錯誤畫面出現（5014-5017）。這個設計對照舊實作（12 秒）具有真正的 TDD 紅燈訊號：若逾時值仍是 12 秒，前段 29 秒推進就會提早觸發逾時、`reader_loading_indicator` 斷言會失敗，不會像單純的 `pump(Duration(seconds: 30))` 那樣「30 大於 12，兩種實作都會通過」。實測上，這是唯一一個對逾時**精確值**（而非「某個下界」）有鑑別力的斷言，符合計畫 Step 1 註解中明確陳述的設計動機。

3. **第二則測試刻意不採兩段式推進，理由正確且已在註解中說明**：「逾時計時器不應覆蓋既有成功狀態」測試（`reader_screen_test.dart:5021-5052`）在 `onPageRendered()` 觸發、狀態已轉為 `rendered` 之後才 `pump(Duration(seconds: 30))`，此時計時器理應已被取消（或即使未取消，`_handleOpenBookTimeout()` 內部的 `_state != loading` 判斷也會擋下），驗證的是「已成功渲染不受逾時計時器覆蓋」這個與逾時值大小無關的性質。计畫在 Step 2 的說明與程式碼內新增的行內註解（5045-5047 行）都正確解釋了「為何這裡不需要像 Step 1 那樣拆兩段」，避免了不必要的測試複雜度，是恰如其分的簡化，不是偷工減料。

4. **文件註解正確交代新舊兩個數值各自的出處，符合計畫 Step 4 要求**：`reader_screen.dart:361-375` 的 dartdoc 註解清楚區分「原始值 12 秒（`epic-18-reader-device-qa` Issue 33 原始分析報告建議值，非嚴謹量測結果）」與「新值 30 秒（`epic-27-reader-device-compat` Issue 2 依 Mobiscribe WAVE 真機回報、2026-08-13 使用者於診斷對話中確認）」，並附上 `bugfix-repro.md` 的路徑供未來讀者查證，避免下一位讀者誤以為 12 秒仍是唯一依據——這正是 `issues.md` Issue 2 對「同步更新說明註解」的具體要求。

5. **刻意不變更的部分確實維持原狀，符合計畫的 YAGNI 界定**：逾時錯誤文案（`_errorMessage = '開書逾時，可能是系統 WebView 版本過舊或檔案異常';`，`reader_screen.dart:1357`）維持逐字不變，`issues.md` 明確載明文案調整非本 Issue 強制要求；經全文搜尋 `app/lib`／`app/integration_test` 未發現任何遺漏的 12 秒殘留引用（例如整合測試或其他文件中硬編碼的逾時秒數），改動範圍完整且無遺漏。

---

## 2. 問題與疑慮 (Issues)

經完整審查程式碼異動、比對計畫文件，並實際於獨立 worktree（`.worktrees\epic-27-issue2`，HEAD `34b5fda`）執行 `flutter test test/screens/reader_screen_test.dart`／`flutter analyze`，**未發現任何 Critical、Important 或值得記錄的 Minor 等級問題**。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)
*無*——本次變更範圍極小（單一數值＋緊鄰文件註解＋兩則既有測試的對應調整），未發現任何值得記錄的邊角案例或風格問題。

---

## 3. 實作建議 (Recommendations)

無額外建議。本次變更是「小範圍數值調整型修復」的良好示範：計畫本身已把每一行 diff 精確寫死，實作忠實照做，且測試設計本身具備真正的鑑別力（能區分 30 秒與任何大於 12 秒的值），沒有留下需要後續處理的技術債。

---

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 是
- **評估理由：**
  程式碼變更與 `plan-issue-2.md` 逐字對齊，`git diff --stat` 確認僅觸及計畫宣告範圍內的兩個原始碼／測試檔案（另加計畫檔本身的勾選框收尾）。計畫刻意設計的 29 秒＋1 秒兩段式邊界斷言已在 `reader_screen_test.dart:5008-5017` 確實落實，且經比對舊實作（12 秒）與新實作（30 秒）的行為差異，確認該斷言對「逾時值精確等於 30 秒」具有真正的鑑別力，不是只驗證「某個大於 12 秒的下界」。文件註解正確交代新舊兩個數值各自的出處與依據，符合 `issues.md` 對「避免下一位讀者誤以為 12 秒仍是唯一依據」的要求。逾時錯誤文案依計畫範圍界定維持不變，未做超出 Issue 範圍的變更。

  實際於獨立 worktree（HEAD `34b5fda`）執行 `flutter test test/screens/reader_screen_test.dart`，全數 162 項測試通過（含本次修改的兩則逾時測試 #121／#122）；`flutter analyze` 回報 "No issues found!"，與計畫聲稱的驗證結果一致，非僅憑閱讀程式碼推測。驗收標準「開書 30 秒內未完成才顯示逾時錯誤畫面」已由新的兩段式邊界斷言實際涵蓋並驗證通過，可以合併。
