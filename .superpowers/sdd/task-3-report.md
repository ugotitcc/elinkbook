# Task 3 實作報告：閱讀器直橫排排版與邊距微調面板 (Vertical Writing & Page Styles)

## 任務概述

本任務旨在為 elinkBook 模擬器實作 Task 3：
1. **直橫排版切換**：支援一鍵切換直排（Vertical-RL）與傳統橫排（Horizontal-TB）。
2. **直排標點符號與避頭尾（CNS 11643 規範）**：在直排模式下，標點符號能正確旋轉並置中，且嚴格禁止標點符號（如逗號、句號、問號、驚嘆號等）單獨落在行首。
3. **避免圖片與標題被腰斬（Avoid-Break）**：利用 `break-inside: avoid` 與 `page-break-inside: avoid`，在直排分頁中防止圖片與標題被截斷。
4. **BottomSheet 版面自訂面板**：在手機模擬器內側實作精美的 BottomSheet 抽屜式面板，提供：
   - 滑桿 (Sliders) 與 `+/-` 微調按鈕，可用於調整：字型大小、字型粗細、行高、段落間距、獨立的上/下/左/右邊距。
   - 字型載入、切換與刪除：可由 Google Fonts 動態載入自訂字型，切換後即時反映，刪除自訂字型會自動重設回預設字型（Noto Serif TC）。
5. **自我測試與邊界 bounds 檢查**：新增單元測試，驗證參數 bounds 限制（如字型大小限制在 12px ~ 40px，邊距限制在 0px ~ 50px），防止排版崩潰。
6. **直排翻頁熱區鏡像與問題修正**：
   - 修正 `changeLayoutParam` 數值超出限制時，從原先的 `return` 忽略改為 `Math.max` 與 `Math.min` 進行 clamp 限制，以確保測試 7 與測試 8 順利通過。
   - 修正直排 (RTL) 模式下的點擊翻頁方向：點擊左側 1/3 為下一頁 (down)，點擊右側 1/3 為上一頁 (up)，以符合直排中文由右至左的閱讀習慣。

---

## 實作細節

### 1. 直橫排排版與 CNS 11643 避頭尾 (.writing-vertical)
在 `prototype/index.html` 的 CSS 樣式中，我們新增了直排與橫排的專用 CSS 類別：
- **`.writing-vertical`**：
  - 設定 `writing-mode: vertical-rl;` 以啟用繁體中文直排（從右向左，自上而下）。
  - 設定 `text-orientation: mixed;`，使英文字元與數字混合直排。
  - 設定 `line-break: strict;` 與 `word-break: keep-all;`，以嚴格遵循 **CNS 11643 避頭尾規範**，防止標點符號出現在行首。
  - 設定 `column-fill: auto;` 支援直排分欄。
- **避免腰斬 (Avoid-Break)**：
  - 針對 `.writing-vertical img, .writing-vertical h3` 等元素，設定了 `break-inside: avoid; page-break-inside: avoid;`，防止在分欄或分頁時被折斷。
- **`.writing-horizontal`**：
  - 設定 `writing-mode: horizontal-tb;` 恢復傳統橫排。

### 2. 閱讀器動態樣式套用
- 重構了 `renderApp()` 中 `reader` 頁面的渲染邏輯：
  - 透過 `AppState.layout` 動態計算 `paddingStyle` (上、下、左、右邊距) 與 `textStyle` (字體大小、字體粗細、行高、字型 FontFamily)，以 inline style 套用到文字容器。
  - 設計 `getParagraphStyle(isVertical)` 函數，動態計算段落間距：
    - **直排模式**：使用 `margin-left` 來分隔段落，避免使用 `margin-bottom` 導致重疊或方向錯誤。
    - **橫排模式**：使用 `margin-bottom` 來分隔段落.
    - 並套用 `text-indent: 2em; text-align: justify;`。

### 3. BottomSheet 版面自訂面板
- 在手機裝置容器 `#device-shell` 的底部，加入了遮罩層 `#bottom-sheet-backdrop` 以及自訂設定面板 `#layout-bottom-sheet`。
- 當點擊閱讀器工具列的 **⚙️ 版面** 按鈕時，觸發 `openBottomSheet()` 函數，遮罩層與面板透過 CSS `transform: translateY(0)` 平滑滑入。
- 點擊遮罩層或右上角關閉按鈕，則會呼叫 `closeBottomSheet()` 滑出隱藏。
- 面板內所有參數控制（FontSize, FontWeight, LineHeight, ParaSpacing, Margins）均支援 `range` 滑桿與 `+/-` 微調按鈕。
- **字型管理系統**：
  - **字型切換**：下拉選單選取後呼叫 `setLayoutParam('fontFamily', name)` 即時套用。
  - **動態載入**：輸入 Google 字型名稱（如 `ZCOOL XiaoWei`），會動態建立 `<link>` 標籤將字型下載並加入 `AppState.fonts` 清單。
  - **刪除字型**：支援刪除自訂字型，若刪除的字型為當前選用字型，會自動重設回預設的 `Noto Serif TC`。

### 4. 直橫排翻頁熱區鏡像邏輯
- 在 `triggerPageClick(event)` 中，我們根據 `AppState.layoutDirection === 'vertical'` 進行方向判定：
  - 當為 **橫排模式** 時：點擊左側 1/3 觸發 `up` (上一頁)，點擊右側 1/3 觸發 `down` (下一頁)。
  - 當為 **直排 (RTL) 模式** 時：點擊左側 1/3 觸發 `down` (下一頁)，點擊右側 1/3 觸發 `up` (上一頁)，以符合由右至左的閱讀習慣。

### 5. 單元測試 (Bounds 檢查與熱區鏡像驗證)
- **測試 7：驗證字體大小微調限制範圍**：
  - 驗證 `changeLayoutParam('fontSize', -5)` 從 `13px` 扣除後，是否被限制在最小值 `12px`。
  - 驗證將 `fontSize` 增加至超過 `40px` 時，是否限制在最大值 `40px`。
- **測試 8：驗證邊距微調限制範圍**：
  - 驗證將 `marginTop` 增加至超過 `50px` 時是否限制在 `50px`，以及減少至低於 `0px` 時是否限制在 `0px`。
- **測試 9：驗證直排翻頁熱區鏡像**（新增）：
  - 驗證在橫排模式下點擊左側為上一頁、右側為下一頁。
  - 驗證在直排模式下點擊左側為下一頁、右側為上一頁的 RTL 翻頁邏輯。

---

## 測試結果

全數 9 個單元測試均成功通過 (PASS)：
1. **驗證切換路由狀態變更** - **PASS**
2. **驗證主題切換與 Class 變更** - **PASS**
3. **驗證音量鍵閱讀翻頁邏輯** - **PASS**
4. **驗證全文檢索與分類匹配** - **PASS**
5. **驗證排序功能與持久化** - **PASS**
6. **驗證視圖切換與持久化** - **PASS**
7. **驗證字體大小微調限制範圍** - **PASS** (已修復 Clamp 邊界邏輯)
8. **驗證邊距微調限制範圍** - **PASS** (已修復 Clamp 邊界邏輯)
9. **驗證直排翻頁熱區鏡像** - **PASS** (新增)
