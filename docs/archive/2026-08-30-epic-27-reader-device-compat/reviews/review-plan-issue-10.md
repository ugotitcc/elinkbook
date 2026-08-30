# Epic 27 Issue 10 實作計畫審查報告

**審查目標**：[`docs/epics/epic-27-reader-device-compat/plans/plan-issue-10.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-27-reader-device-compat/plans/plan-issue-10.md)  
**審查日期**：2026-08-24  
**審查模式**：Superpowers Requesting Code Review（全面技術與架構檢核）  
**審查結論**：✅ **審查通過（Approved，可直接交付實作）**  

---

## 審查摘要與統計

| 嚴重性級別 | 數量 | 說明 |
| :--- | :---: | :--- |
| **Critical** | **0** | 無阻礙實作、破壞架構或導致資料遺失之重大缺陷 |
| **Important** | **0** | 無功能缺漏或時序安全缺陷 |
| **Minor** | **2** | 選取折疊時狀態重置建議、測試錯誤訊息與常數同步備註（見文末） |

---

## 優點（Strengths）

1. **架構分層與最小修改原則（Minimal Blast Radius & ADR 0011 Compliance）**：
   修法精確定位於 `main.js` 整合層，完全不修改 upstream vendored 檔案（`paginator.js`／`view.js`／`epub.js`），亦無須修改 Dart 端邏輯。透過在原生 `click` 監聽器內攔截瀏覽器對點擊的預設動作（`preventDefault()`），直接在源頭阻止選取被折疊，自然不會產生非預期的 `selectionchange` 與 `onSelectionCleared` 呼叫。
2. **時鐘基準一致性與同步記錄（Synchronous Timestamp Recording & Clock Consistency）**：
   在 `reportSelection` 同步階段（第一個 `await` 之前）立即以 `performance.now()` 記錄時間戳記，確保沒有非同步排程延遲；且 `performance.now()` 與 `Event.timeStamp` 在 Chromium 91+ 環境中共享相同的 `timeOrigin` 高精度時間原點（`DOMHighResTimeStamp`），兩者相減比較在數值與語義上完全合法且可靠。
3. **測試策略雙軌互補（Complementary Dart & Puppeteer Test Strategy）**：
   - Dart 端透過靜態內容回歸測試（`foliate_reader_view_test.dart`）鎖定關鍵常數、呼叫順序（早於 `selection.getRangeAt(0)`、早於 `startTime === null` 提早退出），保證未來維護不被意外刪除或重構移位。
   - 整合驗證端利用 Puppeteer 腳本（`verify-issue10-guard.mjs`）直接派發 `MouseEvent('click')` 進行行為斷言，精準繞過 headless Chromium CDP 觸控合成限制，同時驗證了保護期內（20ms）攔截與保護期外（250ms）正常放行的雙向邊界。
4. **立案依據與歷史脈絡清晰透明（Transparent Evidence & Historical Tracking）**：
   計畫開頭清楚交代為何採用 `issue-10-11-12-analysis.md` 的自動化差分測試結論取代 `issues.md` 原文的真機跨版本對照，並明確規劃於收尾時同步回寫工單狀態，兼顧了敏捷開發速度與工程證據的嚴謹性。

---

## 各項檢核細節（Detailed Assessment）

1. **規格符合度與目標清晰度（Spec Alignment & Goal Clarity）**：✅
   計畫直接鎖定真機 log 與分析報告中「選取擴大後緊接著收到收尾 click 導致選取消失」的根因，透過 150ms 選取收尾保護期解決，目標聚焦且無過度工程。
2. **時序與邊界條件安全性（Timing & Edge Case Safety）**：✅
   - **刻意取消選取**：使用者在長按選取後等待超過 150ms 再次點擊螢幕，保護期條件不成立，瀏覽器正常折疊選取並觸發清除通知。
   - **超連結點擊**：保護期條件中包含 `!evt.target.closest('a[href]')`，確保書中超連結跳轉不會被選取保護期誤攔截。
   - **非觸控點擊（如滑鼠）**：保護期判斷置於 `if (startTime === null) return` 之前，滑鼠選取與手勢選取皆能受到保護，且不影響後續 700ms 快速點擊判斷。
3. **架構與生命週期隔離（Architecture & Lifecycle Scoping）**：✅
   `SELECTION_RELEASE_GUARD_MS` 與 `lastNonCollapsedSelectionAtMs` 均宣告在 `view.addEventListener('load', (e) => { ... })` 閉包內，作用域綁定於個別章節的 `doc`（iframe document），隨章節生命週期建立與銷毀，無全域狀態污染風險。
4. **TDD 流程與可鑑別性（TDD Rigor & Identifiability）**：✅
   Dart 測試中斷言的定位字串（如 `lastNonCollapsedSelectionAtMs = performance.now()`、`const SELECTION_RELEASE_GUARD_MS = 150`）與順序關係在實作前會明確失敗（Step 2），實作後通過（Step 4），具備高度鑑別力。
5. **專案規範與慣例（Conventions）**：✅
   符合 ADR 0011、ADR 0017 及專案繁體中文註解慣例。

---

## 建議與觀察（Suggestions & Observations）

以下 2 項為 **Minor（輕微建議 / 實作參考）**，供實作者在實作時作為品質精緻化參考，不影響本計畫審查通過結論：

### Minor 1：選取折疊時主動重置時間戳記（Explicit State Reset on Collapse）
在 `main.js` 的 `reportSelection` 中：
```js
const reportSelection = async () => {
  const selection = doc.getSelection()
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
    lastNonCollapsedSelectionAtMs = null // 建議：主動清空狀態
    window.flutter_inappwebview.callHandler('onSelectionCleared')
    return
  }
  lastNonCollapsedSelectionAtMs = performance.now()
  const range = selection.getRangeAt(0)
  // ...
}
```
**說明**：雖然時間戳記單向遞增（舊的時間戳在 >150ms 後自然不會再滿足保護期條件），但在選取折疊（`isCollapsed === true`）時主動將 `lastNonCollapsedSelectionAtMs` 重置為 `null`，可在語義上更明確表達「當前無活動中選取」，亦能防範極罕見的時鐘回撥或測試環境中的 mock 重置干擾。

### Minor 2：Dart 測試註解與錯誤訊息保持同步（Test Failure Reason Context）
在 Step 1 的 Dart 測試中：
```dart
const guardConstant = 'const SELECTION_RELEASE_GUARD_MS = 150';
```
若未來根據真機回報微調門檻值（例如調整為 120ms 或 200ms），Dart 測試中的常數字串需要同步更新。實作時可考慮在 Dart 測試群組上方加上簡短註解提示「若門檻值微調，請同步更新此處常數字串比對」，讓後續維護者更加一目了然。

---

## 結論

實作計畫 `plan-issue-10.md` 邏輯嚴謹、時序分析透徹、測試覆蓋全面且完全符合專案架構規範（ADR 0011），**予以審查通過（Ready to implement）**。
