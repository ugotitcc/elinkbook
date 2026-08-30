# Epic 28 — 閱讀器設定強化：UI 重構設計與工單審查報告 (Issue 5 & Issue 6)

> **2026-08-15 審查回應：全部 6 項發現（0 Critical／3 Important／3 Minor）逐項查證後皆技術正確，已全數採納並回寫至 `design.md`「審查回應」小節與 `issues.md` Issue 5／Issue 6 對應工單內文。詳見 `design.md` 該小節的逐項說明（含「Important #2 屬既有契約確認、非新缺口」的查證結果）。**

- **評估日期**：2026-08-15
- **審查對象**：
  - [design.md (2026-08-15 追加：版面設定 UI 重構決策)](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/design.md#L70-L94)
  - [issues.md (Issue 5: 版面設定畫面 Tab 化重構)](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/issues.md#L102-L132)
  - [issues.md (Issue 6: 選擇書籍畫面優化)](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/issues.md#L134-L160)
- **審查專家**：系統架構師 & UI/UX 程式碼審查專家
- **當前評估結論**：**準備好開始實作 (Ready to implement with recommendations)**

---

## 1. 優點與亮點 (Strengths)

1. **精準解決控制項膨脹帶來的操作負擔 (Issue 5)**：
   - 隨著 Issue 1（字距）與 Issue 3（版面預設集/複製）的上線，`ReaderSettingsSheet` 的垂直高度已相當可觀。改用 4 個分頁 Tab（**文字內容**、**邊界首尾**、**版面呈現**、**設定喜好**）並依「頁籤負載平衡」原則分配控制項，能確保大部分頁籤在主流手機螢幕下一屏即可完整呈現，大幅改善頻繁上下滑動的困擾。
2. **消弭單選模式誤觸複製的重大體驗缺陷 (Issue 6)**：
   - 原先「從其他書籍複製」的選書畫面在單選模式下點擊 `ListTile` 即直接觸發 `Navigator.pop([book.id])` 執行覆寫，使用者在滑動挑選時極易誤觸。重構為「Radio 選取 + AppBar 確定按鈕」後，與多選模式的互動邏輯完全一致，大幅提高操作安全感。
3. **充分復用本專案既有成熟先例與視覺規範**：
   - Issue 5 復用了 `TocBottomSheet`（PDF 版「章節目錄/縮圖/搜尋」）既有的 `DefaultTabController` + `TabBar` + `Expanded(TabBarView)` 分頁容器架構。
   - Issue 6 復用了 `LibraryScreen` 的 `GridView`（直向 3 欄 / 橫向 4 欄）、封面載入與 fallback 圖示邏輯，視覺語言高度統一。
4. **狀態保持考量周全 (Issue 6)**：
   - 針對即時搜尋功能，特別規範「多選模式下被關鍵字過濾隱藏的已選取項目，選取狀態不可遺失」，有效避免了搜尋過濾常見的狀態重置 Bug。
5. **架構邊界乾淨，零資料層破壞**：
   - 本次重構完全收斂於 UI 展示層（`ReaderSettingsSheet` 與 `LayoutPresetBookPickerScreen`），不變更 `BookReaderPrefs`、`LayoutPreset` 及任何 Repository 資料契約，架構風險低。

---

## 2. 發現問題與改進建議 (Issues & Recommendations)

### Critical (阻擋性問題)
*無發現 Critical 等級問題。設計與工單無架構級缺陷或資料損毀風險。*

---

### Important (重要問題與風險)

#### Issue 2.1：`TabBarView` 水平滑動手勢與內部 9 個 `Slider` 的水平拖曳手勢衝突風險
- **對應工單**：`issues.md` Issue 5（`ReaderSettingsSheet` Tab 化）
- **問題內容**：
  - `TabBarView` 預設具備水平滑動切換頁籤的手勢（`PageScrollPhysics`）。
  - 然而，「文字內容」Tab 包含 5 個 Slider（字級/字重/行高/段落間距/字距），「邊界首尾」Tab 包含 4 個 Slider（上/下/左/右邊界）。
  - 當使用者在調整滑桿時，若有微小的斜向滑動，手勢競技場（Gesture Arena）極易將事件判定給外層的 `TabBarView`，導致「使用者想調整字距，畫面卻意外切換到邊界 Tab」的惡劣體驗。
- **影響**：滑桿微調時容易引發非預期的 Tab 切換。
- **改進建議**：
  - 在 Issue 5 實作中，`TabBarView` 的 `physics` 應明確設定為 **`const NeverScrollableScrollPhysics()`**（禁止水平滑动手勢切換，純靠點擊頂部 TabBar 切換）。
  - 這能 100% 徹底隔絕與 9 個 Slider 的手勢衝突，且在 Bottom Sheet 中純點擊 TabBar 的操作模式更為精準可控。

#### Issue 2.2：單選模式下未選取時點擊「返回」的取消語意與邊界契約
- **對應工單**：`issues.md` Issue 6（選擇書籍畫面）
- **問題內容**：
  - Issue 6 將單選模式的確認機制改為「AppBar 確定按鈕（未選取時停用）」。
  - 若使用者進入選擇器後不想複製了，點擊 AppBar 返回鍵或系統返回手勢退出。
- **影響**：需確保呼叫端（`ReaderScreen`）對 `Navigator.pop(null)` 有明確的空值防禦，不可觸發非預期的覆寫或 Toast 提示。
- **改進建議**：
  - 工單與實作需明定：未點擊「確定」而直接返回時，一律回傳 `null`；呼叫端（`reader_screen.dart` 的 `onRequestBookPicker` / `_handleApplyFromBook`）收到 `null` 或空清單時直接 return，不執行任何狀態變更。

#### Issue 2.3：Issue 4「草稿具現化檢討」新狀態在 Tab 切換下的生命週期穩定性
- **對應工單**：`issues.md` Issue 5
- **問題內容**：
  - Issue 4 剛完成修復，引入了 `_fontSizeOverridden` 等 5 個狀態旗標、原樣式圖示（`Icons.block`）與重置按鈕。
  - 當這些控制項被搬入不同的 Tab 後，若 Tab 切換導致子樹被重新建立，需確保這些狀態旗標不會被意外重置或重新具現化。
- **影響**：切換 Tab 後可能導致未覆寫狀態遺失。
- **改進建議**：
  - 確保所有草稿狀態（`_fontSizeOverridden` 等）統一保留在 `_ReaderSettingsSheetState` 根層級，各 Tab 僅作為 `build` 分支的純展示部件，不維護獨立的 State，確保跨 Tab 操作的一致性。

---

### Minor (次要優化與細節)

#### Issue 2.4：既有 50+ 則 Widget 測試的遷移成本與 Test Helper 規範
- **對應工單**：`issues.md` Issue 5
- **問題內容**：
  - `reader_settings_sheet_test.dart`（1124+ 行）擁有大量既有測試，過往假設所有 Key 皆在同一視窗內可見。分頁後，非當前 Tab 的 Widget 處於未掛載或不可見狀態，既有測試會直接拋出 `TestFailure`。
- **改進建議**：
  - 實作計畫（`plan-issue-5.md`）應在 Task 1 建立共用的測試輔助函式（如 `switchToTab(WidgetTester tester, String tabName)`），並於計畫中精確盤點每個測試所屬的 Tab，避免測試代碼冗餘與維護分散。

#### Issue 2.5：書籍封面組件（`_BookCover`）的程式碼重用指引
- **對應工單**：`issues.md` Issue 6
- **問題內容**：
  - `LayoutPresetBookPickerScreen` 所需的書籍封面呈現（包含 `Book.coverPath` 檔案讀取、不存在時的格式圖示 Fallback）與 `LibraryScreen` 內部的 `_BookCover` 完全相同。
- **改進建議**：
  - 建議在實作 Issue 6 時，將 `_BookCover` 從 `library_screen.dart` 提取至共用元件（如 `app/lib/library/widgets/book_cover.dart`），避免在兩處維護重複的封面容錯邏輯。

#### Issue 2.6：搜尋列在軟體鍵盤彈出時的畫面高度適配
- **對應工單**：`issues.md` Issue 6
- **問題內容**：
  - 當使用者點擊 AppBar 下方的搜尋 `TextField` 彈出軟體鍵盤時，螢幕可用高度被壓縮。
- **改進建議**：
  - `GridView` 外層需使用 `Expanded` 包裹，並確保 `Scaffold.resizeToAvoidBottomInset` 正常運作，避免鍵盤彈出時產生 `RenderFlex overflowed` 警告。

---

## 3. 實作可行性與測試影響評估

| 工單 | 實作難度 | 測試修改幅度 | 核心風險點 | 建議因應對策 |
| :--- | :---: | :---: | :--- | :--- |
| **Issue 5** (Tab 化) | 中 | **大** (需更新 50+ 則既有測試) | Slider 與 TabBarView 手勢衝突；測試遷移量大 | 1. TabBarView 設定 `NeverScrollableScrollPhysics`<br/>2. 建立 `switchToTab` Test Helper |
| **Issue 6** (選書優化) | 低 | 中 (更新既有單選/多選測試) | 搜尋過濾時已選取狀態遺失；軟體鍵盤溢位 | 1. 用 Set 儲存選取 id，過濾僅影響顯示<br/>2. 鍵盤適配與空搜尋結果提示 |

---

## 4. 總結評定 (Final Verdict)

- **審查結論**：**Approved / Ready to Implement**（設計清晰，切片合理，可立即展開實作）。
- **關鍵落實指引**：
  1. **Issue 5**：務必禁用 `TabBarView` 的滑動手勢（`NeverScrollableScrollPhysics`），防止與 Slider 衝突；先建構 Test Helper 再批量遷移既有測試。
  2. **Issue 6**：統一單選與多選為 Radio/Checkbox + 確定按鈕；搜尋過濾維持選取狀態；提取共用 `BookCover` 元件。
