# 設計規格書：全能電子書閱讀器 Flutter APP 互動 UIUX 模擬器

本設計規格書定義了在網頁環境中，使用單一 HTML/CSS/JavaScript 檔案建立一個高度模擬 Flutter APP 的互動式 UIUX 原型。本原型主要依據 [docs/prd.md](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md) 之需求，展示直排繁體中文排版、避頭尾、3x3 點擊熱區鏡像、365 天閱讀活躍度貢獻圖以及雲端進度同步衝突解決等核心亮點。

---

## 1. 檔案與部署架構

*   **檔案路徑**：`prototype/index.html` (專案根目錄下建立的 `prototype` 資料夾)
*   **技術棧**：單一檔案網頁應用 (SPA)，使用原生 HTML5、CSS3 (Vanilla CSS 變數、Grid、Flexbox) 與原生 JavaScript (ES6+)。
*   **字型與資源**：使用 Google Fonts 線上載入 Inter、Outfit 作為 UI 字型，並透過 CSS `@font-face` 載入基礎開源字型（思源黑體、思源宋體）以及模擬商用字型，支援完全離線渲染模擬。
*   **部署方式**：無需任何 `npm install`。可直接點擊檔案雙擊打開，或使用任意靜態伺服器運行。

---

## 2. 視覺風格與裝置外框 (Device Frame & CSS)

模擬器將分為兩大區塊：
1.  **左側/中央：手機模擬器 (Phone Mockup Device)**
    *   **外殼**：使用 CSS 繪製的精緻 iOS/Android 風格手機外殼，具有圓角、細邊框、頂部「動態島」前置鏡頭切孔。
    *   **側邊實體按鍵**：外殼右側配有「音量鍵 ＋」與「音量鍵 －」按鈕，點擊可直接觸發閱讀器的翻頁動作（模擬實體按鍵翻頁 [FR-18](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L110)）。
    *   **系統狀態列**：顯示目前時間、模擬 Wi-Fi、電池電量以及當前同步狀態。
    *   **APP 內容區域**：手機內部的視窗大小設定為標準的 `390px * 844px` (iPhone 13/14 比例)，並限制 `overflow: hidden` 以模擬真實的手機視窗邊界。
2.  **右側：控制台面板 (Control Panel)**
    *   採用毛玻璃風格 (Glassmorphism)，提供模擬器狀態的手動注入（如：**觸發雲端同步衝突**、**重設本地快取**、**下載 Markdown 導出檔**、**切換 WebView 偵測**等）。

### 主題系統 (Themes)
APP 內部支援四大主題，並在閱讀器內部即時切換：
*   **預設明亮 (Light)**：`#F8F9FA` 背景，`#1A1A1A` 文字。
*   **古風羊皮紙 (Sepia)**：`#F4ECD8` 背景，`#3F2E21` 文字。
*   **極緻暗黑 (Dark)**：`#121214` 背景，`#E4E6EB` 文字。
*   **高對比 (E-Ink)**：`#FFFFFF` 背景，`#000000` 文字，粗黑線條，無任何動畫過渡（防殘影）。

---

## 3. APP 頁面導航與畫面狀態 (Flutter Router Simulation)

我們使用 JavaScript 管理一個簡單的狀態物件 `AppState`，以模擬 Flutter 的頁面切換：
```javascript
const AppState = {
  currentPage: 'shelf', // 'shelf' | 'reader' | 'stats' | 'about'
  currentBook: null,    // 當前開啟的書籍
  books: [...],         // 書籍清單 (含閱讀進度百分比)
  searchQuery: '',      // 搜尋關鍵字
  檢視模式: 'grid',      // 'grid' (每列6本) | 'list'
  theme: 'sepia',       // 當前主題
  readingTimeToday: 0,  // 今日閱讀時間(秒)
  readingTimerActive: false,
  annotations: []       // 劃線與備註資料庫
};
```

### 3.1 書架頁面 (Shelf Page)
*   **網格模式**：每列精準排列 6 本書籍封面 [FR-03](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L77)。封面使用 CSS 漸層與簡約文字動態合成，符合不同格式的封面產生策略 [FR-27](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L79)。
*   **列表模式**：顯示書籍封面、書名、作者、檔案格式標籤，以及視覺化進度條（含百分比 [FR-28](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L80)）。
*   **排序功能**：下拉選單支援「最後閱讀」(預設)、「建立時間」、「作者」、「書名」 [FR-26](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L78)。
*   **全文檢索 [FR-04](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L81)**：
    *   在輸入關鍵字後，延遲 500ms (Debounce) 進行匹配。
    *   結果劃分為：**「書名/作者匹配」** 與 **「內容匹配」** 兩個獨立區域。
    *   點選內容匹配項時，會直接跳轉至閱讀器，並精準捲動/分頁至該關鍵字所在的段落。

### 3.2 閱讀核心頁面 (Reader Page)
*   **排版方向一鍵切換 [FR-05](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L88)**：點選頂部工具列的「直/橫」按鈕，切換 CSS 類別 `writing-mode-vertical`。
    *   直排使用：`writing-mode: vertical-rl; text-orientation: mixed;`
*   **避頭尾規範 [FR-32](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L99)**：
    *   使用 CSS `line-break: strict; word-break: keep-all;` 規範標點符號不落於行首。
    *   直排模式下，使用 CSS 讓標點符號正確轉向與居中。
    *   針對圖片與標題使用 `break-inside: avoid;`，防止直排分頁時被腰斬切斷。
*   **3x3 九宮格點擊區域 [FR-24](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L112)**：
    *   覆蓋一層透明的 3x3 網格。
    *   **預設橫排映射**：左 3 格為上一頁，右 3 格為下一頁，中 3 格為開關選單。
    *   **直排 RTL 鏡像**：當切換為直排（右開書）時，熱區映射**左右自動翻轉**（左 3 格變成下一頁，右 3 格變成上一頁）。
*   **參數控制面板 (BottomSheet)**：
    *   行距、段落間距、四邊邊距調節（皆為獨立控制項）。
    *   提供滑桿與 **「＋」/「－」精細微調按鈕** [FR-10](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L93)。
    *   字型清單中可加載、切換，並提供「自訂字型刪除」按鈕，若刪除當前字型會退回思源宋體。
*   **翻頁模擬**：模擬 ePub 分頁機制，支援滑動與按鍵翻頁，底部顯示「當前頁碼 / 總頁數」 [FR-22](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L96)。

### 3.3 閱讀統計頁面 (Stats Page)
*   **365天貢獻圖 [FR-17](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L109)**：
    *   用 JS 動態生成一個 `53 * 7` 的網格，代表過去 365 天。
    *   格子顏色依閱讀時長呈現不同深淺的綠色（無、淺綠、中綠、深綠）。
    *   點擊方格會在 APP 內彈出 Dialog，顯示例如：`2026-05-12 閱讀時間：45 分鐘`。
*   **活躍度計時器**：
    *   在閱讀頁內，開啟一個背景 timer。如果使用者在 10 秒內沒有任何互動（觸摸、翻頁、微調參數），計時器暫停，並在手機頂部顯示「暫停計時（閒置）」。有互動時自動重啟，確保計時精準。

---

## 4. 劃線備註與 Markdown 導出

1.  **內文劃線**：
    *   在閱讀模式下，滑鼠選取文字會觸發 Floating Toolbar。
    *   可選擇黃色、粉色、藍色螢光筆，或波浪下劃線。
    *   點擊已劃線的文字可彈出選單進行「刪除劃線」或「新增/修改備註」。
2.  **劃線與備註側邊欄 [FR-25](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L111)**：
    *   顯示全書的劃線與備註清單。
    *   提供「一鍵刪除所有劃線」與「一鍵刪除所有備註」按鈕，批次刪除前會彈出 Flutter 式警告確認視窗。
3.  **Markdown 一鍵導出 [FR-16](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md#L108)**：
    *   點選導出按鈕，將所有劃線、備註與書籤格式化為標準 Markdown：
        ```markdown
        # 閱讀筆記：《紅樓夢》
        *   **導出時間**：2026-07-04
        *   **當前閱讀進度**：78%
        
        ## 書籤清單
        *   第回：林黛玉進賈府 (頁碼：P.45)
        
        ## 劃線與個人備註
        *   > 「花謝花飛花滿天，紅消香斷有誰憐？」
            *   *備註*：黛玉葬花的名句，寫盡了寄人籬下的悲涼心境。
        ```
    *   支援在控制台一鍵複製或直接下載 `notes-export.md`。

---

## 5. 雲端同步衝突解決模擬 (FR-19)

為了模擬 Flutter App 在多端同步時的核心邏輯：
1.  **觸發衝突**：使用者在右側「控制台面板」點擊「觸發同步衝突」按鈕。這會將雲端的進度（例如 85%）設定為大於本地進度（例如 30%）。
2.  **衝突彈窗**：此時，若使用者在 APP 書架中點擊該書籍進入閱讀器時，系統**不會靜默覆蓋**，而是會彈出一個 Flutter Material 3 風格的進度衝突詢問 Dialog：
    *   *標題*：發現雲端閱讀進度不一致
    *   *內容*：雲端進度已讀至第 5 章 (85%)，本地當前進度為第 2 章 (30%)。是否跳轉至雲端的最新進度？
    *   *按鈕*：**[跳轉至最新進度]** (跳轉至 85% 位置) / **[保留在本地位置]** (不跳轉，並以本地位置覆寫雲端)。

---

## 6. 自審與確認 Checklists

*   [x] 是否使用正體中文？ 是。
*   [x] 程式碼與變數是否為英文？ 是。
*   [x] 檔案路徑與符號是否有 clickable links？ 是，已將 [docs/prd.md](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md) 做了正確的連結。
*   [x] 是否排除了 DRM 等 out-of-scope 範圍？ 是。
*   [x] 是否有 placeholder 或 TODO？ 沒有，規格非常具體。
