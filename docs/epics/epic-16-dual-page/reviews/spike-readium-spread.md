# Epic 16 Issue 1 — Spike：Readium Spread 行為驗證報告

**驗證日期：** 2026-07-12
**驗證裝置：** 9491G（Android 15 / API 35，device id 3CEF42ECD491687）
**Readium 版本：** kotlin-toolkit 3.3.0
**插樁分支：** `epic-16-issue-1-spike`（基於 `main` commit `d3e427a`）

---

## 執行摘要

本 spike 透過暫時性程式碼插樁（`spread = Spread.ALWAYS` + SPIKE log），在真機上驗證 `spec.md`「待驗證風險與收斂關卡」列出的 4 個問題。
* **主要素材分工**：
  - **Q1/Q2 (直向基礎驗證)**：使用控制組素材（`sample_fixed_layout.epub`），確認基本插樁生效。
  - **Q1/Q2 (橫向與整體判定) / Q3 (配對驗證)**：為排除簡短控制組素材之侷限，並同時觀察日漫 RTL 配對與多頁翻頁行為，改用真實多頁漫畫（`一弦定音！(06).epub`）進行深度觀察。
* **關鍵發現**：Readium 的 `Spread.ALWAYS` 對 FXL EPUB 僅產生「WebView 半寬」效果，不會建立兩個並排 WebView；`Spread.AUTO` 則根本不被 `EpubPreferences` 接受。

---

## Q1：Spread.AUTO/ALWAYS 頁間是否無間距

**結論：** ⚠️ 部分通過（見下方說明）
**證據：** `spike-q1q2-portrait.png` (控制組直向)、`manga_portrait_always.png` (漫畫直向)、`manga_landscape_always.png` (漫畫橫向)、UI dump XML

### 觀察

啟用 `Spread.ALWAYS` 後，Readium 的 FXL 布局（`r2FXLLayout`）在兩個方向下均只建立 **一個** WebView（UI dump 中僅有 `secondWebView` 或無 ID 的單一 WebView 節點，無 `firstWebView`）：

| 方向 | 測試素材 | 螢幕尺寸 | WebView bounds | WebView 寬度 | 螢幕寬度占比 | 兩側空白 |
|------|----------|----------|----------------|-------------|-------------|---------|
| 直向 (rotation=0) | sample_fixed_layout.epub | 1600×2400 | [400,570][1200,1784] | 800px | 50% | 各 400px (25%) |
| 直向 (rotation=0) | 一弦定音！(06).epub | 1600×2400 | [400,570][1200,1784] | 800px | 50% | 各 400px (25%) |
| 橫向 (rotation=1) | 一弦定音！(06).epub | 2400×1600 | [600,170][1800,1384] | 1200px | 50% | 各 600px (25%) |

**說明**：在直向下以控制組與漫畫交叉比對，WebView 寬度均固定為螢幕寬度的 50%，且居中放置。這表示 `Spread.ALWAYS` 確實觸發了 Readium 的 spread 模式（將容器縮為半寬），但**並未建立第二個 WebView**。
為了同時驗證漫畫的 RTL 雙頁配對 (Q3) 並觀察實際翻頁行為，橫向測試統一採用真實多頁漫畫進行。

### 判讀

- **若 FR-41「不留空白」指的是兩頁並排時中間無縫隙**：由於只有一個 WebView 顯示單頁，「頁間間距」不適用（N/A）。
- **若 FR-41 指的是整體畫面不應有非內容空白**：WebView 半寬導致兩側各 25% 螢幕寬度的空白區域，**不通過 FR-41**。
- **推論**：Readium FXL 的 `Spread.ALWAYS` 行為是「讓單一 WebView 佔半寬」，而非「建立兩個 WebView 並排顯示」。Issue 6 若需真正的雙頁並排，不能僅依賴 `Spread.ALWAYS`——可能需要自行管理兩個 WebView 的建立與配置，或改用 CSS-based 的雙頁排版。

---

## Q2：Spread.AUTO 是否等同「橫向才雙頁」

**結論：** ❌ 失敗——`Spread.AUTO` 根本不被接受
**證據：** 反編譯 `readium-navigator-3.3.0-runtime.jar` 中 `EpubPreferences.kt` 的 `init` block，以及真機 crash log。

### 觀察

1. **真機測試崩潰**：在 Task 1 嘗試設定 `spread = Spread.AUTO` 時，`attachNavigator()` 階段直接觸發例外崩潰，說明 `AUTO` 在此 Readium 版本下有嚴格的使用限制。
2. **源碼約束確認**：反編譯 `EpubPreferences` 的 `init` block 包含以下驗證：
   ```kotlin
   require(spread in listOf(null, Spread.NEVER, Spread.ALWAYS))
   ```
   `Spread.AUTO` **不在允許列表中**。嘗試設定 `spread = Spread.AUTO` 會觸發 `IllegalArgumentException`（在 `EpubPreferences.<init>` 拋出），導致 `attachNavigator()` 的 `commitNow()` 失敗，App 無法開啟書籍。

### 判讀

- `Spread.AUTO` **不可用**。EPUB 側不能依 `spec.md` 原規劃使用 `Spread.AUTO` 並交給 Readium 內部判斷方向。
- **退回方案（已確定）**：EPUB 側必須**手動依 `isLandscape` 在 `Spread.ALWAYS`/`Spread.NEVER` 間切換**，不使用 `Spread.AUTO`。具體實作：在 `buildPreferencesFromMap()` 中，根據傳入的 `isLandscape` 參數決定 `spread` 值：
  - `isLandscape == true` → `spread = Spread.ALWAYS`
  - `isLandscape == false` → `spread = Spread.NEVER`（或 `null`，使用預設值）
- 此方案已在本 spike 中驗證 `Spread.ALWAYS` 可正常運作（無 crash，書籍可開啟）。

---

## Q3：page-spread-left/right metadata 配對是否正確

**結論：** ⚠️ 元資料存在但配對行為未驗證
**證據：** SPIKE log 輸出的 manifest JSON、UI dump

### 觀察

SPIKE log 輸出了漫畫的完整 manifest，確認：
1. **`layout: "fixed"`**——這是一本 FXL EPUB
2. **`readingProgression: "rtl"`**——日文漫畫，從右至左閱讀
3. **`#spread: "landscape"`**——EPUB 宣告 spread 為橫向模式
4. **`#orientation: "auto"`**——方向為自動
5. **`fixed-layout-jp:viewport: "width=1338, height=2048"`**——viewport 尺寸

spine items 的 page-spread 配對確認為嚴格交替：

| Spine item | page 屬性 |
|-----------|----------|
| p-cover.xhtml | `"page":"center"`（封面，獨立居中） |
| p-001.xhtml | `"page":"left"` |
| p-002.xhtml | `"page":"right"` |
| p-003.xhtml | `"page":"left"` |
| p-004.xhtml | `"page":"right"` |
| ... | 交替持續 |

### 判讀

- **元資料層面**：page-spread-left/right 配對正確，符合日文漫畫的 RTL 雙頁排版慣例（封面獨立居中，其後左右交替）。
- **渲染層面**：由於 Q1 已確認 Readium FXL 的 `Spread.ALWAYS` 只建立一個 WebView，**無法在本次 spike 中驗證 Readium 是否正確將 left/right 配對的兩頁並排顯示**。UI dump 僅顯示單一 WebView，無法確認配對渲染是否正確。
- **建議**：Q3 的完整驗證需要在 Issue 6 實作雙頁顯示後，透過截圖比對來確認 left/right 配對是否正確。本 spike 僅能確認元資料存在且結構正確。

---

## Q4：applyFxlFitScale() 雙頁下是否不再重疊

**結論：** ⚠️ 未在真機中被觸發驗證（但插樁演算法可作為實作起點）
**證據：** 無

### 說明

Task 4 的暫時性插樁（替換 `applyFxlFitScale()` 為半寬置中演算法）**未被執行**。原因：
1. Q1 已確認 Readium FXL 的 `Spread.ALWAYS` 不建立雙 WebView，因此即使修改 `applyFxlFitScale()` 為半寬邏輯，也沒有第二個 WebView 可以定位。
2. Q4 的驗證前提（兩個 WebView 存在且需要並排定位）在目前 Readium 行為下不成立。

### 判讀

- **演算法交付**：雖然因為缺少第二個 WebView 而未在真機中執行，但 Task 4 Step 1 所寫出的插樁演算法（基於左右 slot 分配及平移置中，`m.rawLeft - slotLeft` 核心平移法）在數學與坐標轉換架構上是正確且合理的。這份演算法草稿已在計畫書中完整記錄，將作為 Issue 6 建立雙 WebView 後的實作參考起點。
- **後續規劃**：Issue 6 的實作方案應優先解決「如何建立並管理兩個 WebView」的問題，隨後立即套用並驗證此半寬置中演算法。

---

## 附錄：插樁與執行細節

### 變更摘要（已還原）

| 檔案 | 變更 |
|------|------|
| `EpubReaderView.kt` | +`import Spread`；`buildPreferencesFromMap()` 新增 `spread = Spread.ALWAYS`；`attachNavigator()` 新增 SPIKE debug logging（`android.util.Log.d("EpubReaderView-SPIKE", ...)`） |

### 靜態分析檢查
本 worktree 已執行全專案 `flutter analyze`，檢查結果為 `No issues found!`。

### 裝置端清理確認
驗證完成後：
1. 測試用的 `一弦定音！(06).epub` 漫畫書籍已從 App 圖書庫中徹底刪除。
2. 暫存於真機 `/sdcard/Download/` 下的 `一弦定音！(06).epub` 檔案已透過 `adb shell rm` 指令清除。
3. 裝置的 `accelerometer_rotation` 旋轉設定已恢復。

### 其他既有 Bug 發現
在真機驗證期間，發現 `onResourceLoadFailed` 回呼在背景執行緒觸發時會因 `@UiThread` 約束而 crash，需以 `runOnUiThread` 包裝（此為既有 bug，非本 spike 引入）。

### 截圖與 UI dump

所有截圖與 UI dump 檔案位於 `tmp/epic-16/reviews/`（已被 `.gitignore` 排除）：
- `spike-q1q2-portrait.png`——控制組 `sample_fixed_layout.epub` 直向（用於 Task 1 插樁生效基本驗證，確認 WebView 寬度佔 50%）
- `manga_portrait_always.png`——漫畫直向（Spread.ALWAYS）
- `manga_landscape_always.png`——漫畫橫向（Spread.ALWAYS）
- `ui_manga3.xml`——直向 UI dump
- `ui_manga_landscape.xml`——橫向 UI dump
- `logcat_live.txt`——完整 SPIKE log 輸出

---

## 對 Issue 6 的收斂結論

### 結論：需調整實作路線

| 問題 | 結論 | 對 Issue 6 的影響 |
|------|------|------------------|
| Q1（頁間間距） | WebView 半寬但僅單頁顯示 | Issue 6 不能僅依賴 `Spread.ALWAYS` 實現雙頁並排；需自行管理雙 WebView |
| Q2（Spread.AUTO） | ❌ 不可用 | EPUB 側必須手動依 `isLandscape` 切換 `ALWAYS`/`NEVER`，不使用 `AUTO` |
| Q3（page-spread 配對） | 元資料正確，渲染未驗證 | Issue 6 需在建立雙頁顯示後驗證配對正確性 |
| Q4（半寬置中） | 演算法未驗證 | 前提（雙 WebView 存在）不成立，需 Issue 6 先解決 WebView 管理問題。實作時可參考 Task 4 演算法草稿。 |

> **⚠️ 提醒**：Q1 的「單一半寬 WebView」結論主要基於漫畫素材（含有 `page-spread-center` 封面頁以及其後的 RTL left/right 頁）之觀察。建議 Issue 6 啟動時，先使用控制組素材的一般 spread 頁（如第 2-3 頁）進行二次確認，以確保此行為是 Readium 對所有 FXL EPUB 的通用約束。

### 建議的 Issue 6 實作方向與方案評估

1. **不使用 `Spread.AUTO`**——改為手動依 `isLandscape` 切換 `Spread.ALWAYS`/`Spread.NEVER`。
2. **雙頁顯示不依賴 Readium 內建機制**——評估以下三個雙 WebView / 雙頁排版方案：

#### 方案 A：自建雙 WebView / 雙 Fragment 容器（建議優先級：高）
* **可行性與風險**：Readium `EpubNavigatorFragment` 建構子為 `internal`，在原生 Android 端僅能透過 `EpubNavigatorFactory` 建立。雖可建立多個 Fragment 執行實例，但需自行管理兩個 Fragment 之間的 Locator 同步（例如：左頁翻頁時，右頁必須同步 Locator 到下下頁），且兩頁各自為獨立的 WebView，無法支援跨頁的文字劃線選取。
* **評估**：能最大程度地保留 Readium 內建的樣式注入、單頁文字選取與 CFI 定位能力，建議作為 Issue 6 的首選評估方案。
* **實作起點**：可直接複用計畫 Task 4 Step 1 寫出的 `slotLeft` 座標平移與置中演算法作為定位依據。

#### 方案 B：單一 WebView 內透過 CSS/JS 實現雙頁排版（建議優先級：低）
* **可行性與風險**：FXL EPUB 的每一頁都是獨立的 XHTML 檔案。在單一 WebView 下顯示雙頁，需要破壞 Readium 原本的載入鏈，進行 DOM 操作拼接或以 iframe 嵌入。這會極大破壞 Readium 的核心定位與導覽邏輯，相容性極差、風險極高。

#### 方案 C：截圖拼接（建議優先級：中，僅適用純圖漫畫）
* **可行性與風險**：類似 PDF 拼接方式，將每頁 WebView 截圖後由 Native 端拼接顯示。這會**完全喪失文字選取與 CFI 劃線定位能力**，與專案既有需求衝突。僅適合完全無文字交互的純圖片漫畫。
