# Epic 28 Issue 2：Console Log 攔截可手動關閉 實作計畫審查報告

本報告針對 [`docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-2.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-2.md) 進行全方位的技術架構與實作計畫審查，確認其是否符合需求規格（`issues.md`、`design.md`）、專案架構慣例與 TDD 開發標準。

---

## 1. 優點與亮點 (Strengths)

* **TDD 流程設計嚴謹完整**：計畫劃分為 3 個獨立的垂直 Task（Task 1 資料層、Task 2 過濾與接線層、Task 3 UI 層），每個 Task 皆嚴格遵守「先寫失敗測試、執行確認失敗、編寫實作程式碼、驗證測試通過」的標準步驟，且明確標註預期的失敗原因（如編譯錯誤或找不到 Key），具備極高的可執行性。
* **診斷能力防禦設計周延**：`handleFoliateConsoleMessage` 在 `consoleLogEnabled` 為 `false` 時，精確放行 `levelName == 'ERROR'`（來自 WebView 自動鏡射的未捕捉例外），確保崩潰診斷能力不受開關影響；同時計畫在 Global Constraints 中明確釐清 `_globalErrorCaptureJs`（`window.onerror` → `onError` bridge）為獨立管線，架構邊界清晰。
* **UI 狀態載入策略得宜（避免阻塞整頁）**：`SettingsScreen` 由 `StatelessWidget` 遷移至 `StatefulWidget` 時，刻意不採用 `ReadingDefaultsScreen` 的「整頁 loading gate」遮罩模式，初始顯示預設值 `false` 並於 `initState` 非同步載入後 `setState` 更新，避免阻塞佈景、字型管理等無關項目的即時呈現，兼顧效能與使用者體驗。
* **SharedPreferences 覆寫安全性高**：`_updateConsoleLogEnabled` 在切換開關時，先執行 `await widget.prefsManager.loadGlobalPrefs()` 再進行 `copyWith(consoleLogEnabled: value)` 儲存，能有效防止使用者在子畫面修改其他全域設定後返回時發生過期狀態覆寫（Stale State Overwrite）的問題。
* **強型別編譯期防護**：`handleFoliateConsoleMessage` 的 `consoleLogEnabled` 宣告為 `required bool` 具名參數，在編譯期強制要求呼叫端同步更新，杜絕遺漏傳遞的潛在風險。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
* 無。

### Important (應該修正)
* 無。

### Minor (建議優化 / 注意事項)

#### 1. `ConsoleMessageLevel.toString()` 字串格式相容性確認
* **說明**：計畫中 `handleFoliateConsoleMessage` 依賴 `levelName != 'ERROR'` 判斷。經查證專案歷史紀錄（`epic-18-reader-device-qa` Issue 33 與程式碼審查），`flutter_inappwebview` 的 `ConsoleMessageLevel` 是自訂 pseudo-enum 類別，其 `toString()` 確實已被套件覆寫為純大寫字串（`'ERROR'`、`'LOG'`、`'WARNING'`、`'DEBUG'`、`'TIP'`）。計畫在此處的設計與專案既有實作一致，惟後續若升級 `flutter_inappwebview` 主版本時需留意套件端是否有更改此行為。

#### 2. `SettingsScreen` 切換後的非同步錯誤處理（樂觀更新慣例）
* **說明**：`_updateConsoleLogEnabled` 採用立即 `setState` 的樂觀更新（Optimistic UI），若極端情況下 `saveGlobalPrefs` 拋出 I/O 例外，UI 不會自動回滾狀態。由於目前專案既有的 `ReadingDefaultsScreen` 與 `NavZoneSettingsScreen` 全數採用相同的無鎖即時持久化慣例（SharedPreferences 本地寫入失敗率極低），維持現有設計以符合全專案一致性是合適且合理的。

---

## 3. 評估結論 (Assessment)

* **是否已準備好開始實作 (Ready to implement)？**：**準備好開始實作 (Ready to implement)**。
* **評估理由**：實作計畫結構清晰、責任分工明確，3 個 Task 的 TDD 步驟完整且精確，測試涵蓋率包含單元測試與 Widget 整合測試，且充分考量了錯誤診斷保留與 UI 載入體驗，無任何阻擋實作的 Critical 或 Important 缺陷。
