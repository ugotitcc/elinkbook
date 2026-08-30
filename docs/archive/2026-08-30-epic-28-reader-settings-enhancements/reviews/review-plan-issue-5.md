# Epic 28 Issue 5 — 版面設定畫面 Tab 化重構 實作計畫審查報告

- **評估日期**：2026-08-15
- **審查對象**：[`docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-5.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-5.md)
- **審查專家**：系統架構師 & 測試工程審查專家
- **當前評估結論**：**準備好開始實作 (Ready to implement)**

---

## 1. 優點與亮點 (Strengths)

1. **手勢衝突防禦與手勢競技場隔離完備 (Task 1 & Task 2)**：
   - 實作計畫嚴格落實了設計審查意見，將 `TabBarView` 的滾動物理屬性強制設定為 `physics: const NeverScrollableScrollPhysics()`。
   - 在 Task 1 中編寫了專屬的失敗測試（對 `Slider` 進行水平拖曳 `Offset(200, 0)` 並驗證 `DefaultTabController.index` 不變），從測試層面確保水平拖曳不會被誤判為切換頁籤，徹底消弭了內部 9 個 `Slider` 與分頁容器的手勢競技場衝突。
2. **狀態架構簡潔安全，零跨頁籤狀態丟失風險**：
   - 計畫明確將 4 個 Tab 保持為 `_ReaderSettingsSheetState.build()` 內部的展示分支（`_buildTextContentTab` 等純私有方法），**不**抽出獨立的 `StatefulWidget`。
   - 所有草稿狀態（包含 Issue 4 新增的 `_fontSizeOverridden` 等 5 個狀態旗標）統一保留在根 State，切換 Tab 僅為 `TabBarView` 呈現切換，不會觸發 State 銷毀或重新具現化，天生確保了資料一致性。
3. **既有測試遷移策略清晰，盤點極為詳盡 (Task 3 & Task 4)**：
   - 計畫首先在 Task 1 建立共用測試輔助函式 `switchToTab(WidgetTester tester, String tabLabel)`，避免個別測試重複手寫切換邏輯。
   - 針對 `reader_settings_sheet_test.dart`（1124+ 行）既有的 50+ 則測試，逐一依所屬頁籤進行表格化盤點（邊界首尾 9 則、版面呈現 13 則、設定喜好 9 則），並標註精確插入位置，執行路徑極為清晰。
4. **結構性與行為變更測試處理細緻 (Task 4)**：
   - 對於原本跨頁籤斷言的測試（如初始值反映、null 預設值顯示），計畫細緻地將斷言拆分至各頁籤切換後執行。
   - 針對「邊界欄位不適用 Issue 4 重置機制」的測試，主動要求必須真正切換到「邊界首尾」頁籤斷言，防止因頁籤未掛載而產生的「假綠燈（巧合通過）」。
   - 明確將「內容小於可用高度時保持緊湊」的舊測試改寫為斷言新版「撐滿近全螢幕高度」，透徹說明此為設計決策的刻意變更（非回歸）。
5. **跨模組整合測試（`reader_screen_test.dart`）預防性覆蓋 (Task 6)**：
   - 計畫敏銳辨識出 `reader_screen_test.dart` 中有 9 則整合測試直接操作了設定 Sheet 內部元件，預先規劃了補齊 `switchToTab` 的步驟，確保全專案測試無縫過關。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
*無。*

---

### Important (應該修正)
*無。*

---

### Minor (建議優化 / 注意事項)

#### 1. 窄螢幕或大字級下的 TabBar 排版適配
- **說明**：4 個 Tab 標籤（「文字內容」「邊界首尾」「版面呈現」「設定喜好」）皆為 4 個中文字。在標準手機螢幕（360dp~400dp 寬）下 `TabBar` 均分 4 欄呈現十分舒適；若使用者在系統設定開啟極大字級時，Tab 文字可能有換行或擠壓情況。目前使用標準 `TabBar` 已完全符合設計，實作時可留意視覺渲染效果。

#### 2. `didUpdateWidget` 測試時的虛擬螢幕尺寸設定 (Task 4 Step 4)
- **說明**：Task 4 Step 4 提醒若 `didUpdateWidget` 測試在 `Size(800, 1200)` 下因新版面產生 `RenderFlex` 溢位，可擴大虛擬螢幕高度至 `Size(800, 2400)`。此防禦性提示非常務實，實作者可直接依此指引排解測試環境尺寸限制。

---

## 3. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**：**準備好開始實作 (Ready to implement)**。
- **評估理由**：本實作計畫邏輯完備、責任劃分精準、手勢防護測試設計周全，且對全專案受影響的 40+ 則既有測試進行了窮盡式的盤點與遷移規劃，符合 TDD 與高品質開發標準，無任何阻擋實作之架構缺陷。
