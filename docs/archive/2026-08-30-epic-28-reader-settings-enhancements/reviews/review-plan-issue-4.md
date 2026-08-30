# Epic 28 Issue 4 — 檢討「設定面板草稿具現化」原則是否意外覆寫書本原生 CSS 樣式 實作計畫審查報告

本報告針對 [`docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-4.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-4.md) 進行深度技術架構與實作計畫審查，評估其是否符合需求規格（`issues.md` Issue 4）、專案既有架構原則、狀態生命週期管理規範與 TDD 開發標準。

---

## 1. 優點與亮點 (Strengths)

* **精準鎖定問題根因與最小修改面（Zero-data-layer Change）**：
  計畫深刻剖析了問題源頭——`BookReaderPrefs`、`ReaderPrefsManagerImpl.resolve()` 以及 Foliate `main.js` 的 `buildOverrideCss()` 對 `null` 的處理原本就健全且正確（`null` 時不注入 CSS 規則，讓書本原生樣式生效），問題純粹出在 `ReaderSettingsSheet` 的 UI 狀態層無條件將草稿具現化數值送出。因此修法精準收斂於 `ReaderSettingsSheet` 內部狀態管理，完全不需改動 SQLite 資料表、`BookReaderPrefs` 或 JS 橋接層，維持極高的架構穩定性。
* **嚴謹且客觀的影響範圍收斂與邊界界定**：
  計畫精確辨識出 5 個真正受本 bug 影響的排版欄位（`fontSize`、`fontWeight`、`lineHeight`、`paragraphSpacing`、`letterSpacing`），並明確排除 4 個頁面留白邊界欄位（`marginTop`／`marginBottom`／`marginLeft`／`marginRight`，已查證屬 App 本身版面留白設定，與書本原生 CSS 無關）以及 `publisherStyles` 等其他控制項，避免不必要的改動蔓延。
* **狀態管理與生命週期設計自洽且穩健**：
  - 新增的 5 個 `_XOverridden` 私有旗標在 `initState()` 與 `didUpdateWidget()` 中同步依 `widget.prefs.X != null` 進行初始化與更新，確保外部傳入新設定時狀態不會脫節。
  - `_currentDraft` 嚴格依據 `_XOverridden` 決定輸出具體數值或 `null`，各滑桿的 `onChanged` 閉包則在使用者主動操作時切換為 `true`，邏輯自洽且無副作用。
* **UI 語意化與使用者心智模型精確對齊**：
  - 捨棄高複雜度、高不確定性的 `getComputedStyle()` 動態查詢方案，改採靜態 `Icons.block` 圖示呈現「未覆寫／跟隨本書原樣式」狀態，既輕量又明確。
  - `_buildSliderRow` 設計了 `isOverridden` 三態支援（`null` 表示不適用此機制、`true` 顯示數值與重置按鈕、`false` 顯示原樣式圖示與 Tooltip），讓邊界欄位可無縫沿用原有行為，受影響欄位則獲得完整支援。
* **TDD 流程切分嚴謹且測試覆蓋周全**：
  - **Task 1**：針對「切換不相干開關悄悄覆寫」的原始 bug 編寫重現失敗測試，並驗證單一欄位調整時其餘欄位維持 `null` 不受污染。
  - **Task 2**：針對圖示呈現、重置按鈕操作、滑桿位置回歸、以及字型大小倍率換算欄位的重置往返編寫完整 Widget 測試。
* **全專案細節一致性維護**：
  主動辨識出 `reader_screen_test.dart` 行號 1341-1344 中因本修復而過時的既有註解說明，並同步給予精確的文字更新，避免未來維護者產生混淆。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
* 無。

### Important (應該修正)
* 無。

### Minor (建議優化 / 注意事項)

#### 1. `_buildSliderRow` 中重置按鈕的排版與點擊邊界
* **說明**：在 Task 2 Step 3 的 UI 實作中，`isOverridden == true` 時在數值右側放置了 `IconButton`。目前配置了 `visualDensity: VisualDensity.compact` 與 `iconSize: 18`，表現相當良好。實作時若發現與右側邊界或文字 baseline 有微小間距落差，可視排版情況微調 `padding` 或 `constraints`。

#### 2. 未覆寫狀態下點擊 `+` / `-` 按鈕的起始基準值
* **說明**：當欄位處於未覆寫狀態（`isOverridden == false`）時，滑桿內部維持在 `_default*` 基準常數（例如字型大小為 16.0）。當使用者點擊 `+` 或 `-` 時，將會以該預設基準進行步進計算（如 16 + 1 = 17），這符合「使用者從標準預設值出發微調」直覺心理預期，測試與計畫中的行為亦一致。

---

## 3. 評估結論 (Assessment)

* **是否已準備好開始實作 (Ready to implement)？**：**準備好開始實作 (Ready to implement)**。
* **評估理由**：實作計畫架構清晰、根因分析精確、改動範圍最小化且無破壞性變更，狀態機與生命週期設計完整，TDD 測試案例詳盡且可直接執行，符合專案規範與品質標準。
