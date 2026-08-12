# Anx Reader 透過 foliate-js 實現 FLX 漫畫橫屏雙頁 (3-2, 5-4) 無縫呈現技術分析報告

## 概述

Anx Reader 是一款基於 Flutter 開發的跨平台電子書閱讀器，其核心 Web 閱讀與排版引擎採用了由 John Factotum 開發的 **`foliate-js`**。

在處理 **FLX / FXL（Fixed-Layout 固定排版 / 漫畫 / CBZ）** 檔案時，Anx Reader 能在橫屏（Landscape）模式下做到**雙頁呈現、右開順序（3-2, 5-4）且中間零空白**。本報告深入分析 `foliate-js` 內部的 **`FixedLayout` 模組 (`fixed-layout.js`)** 與底層 CSS/Viewport 計算機制。

---

## 1. 橫屏雙頁呈現機制 (Landscape Spread Mode)

`foliate-js` 針對固定排版書籍獨立實現了專屬的 Web Component — **`FixedLayout`**：

1. **動態尺寸監聽 (`ResizeObserver`)**：
   `FixedLayout` 透過 `ResizeObserver` 實時監聽畫面容器的寬高比。
2. **Spread 條件判定**：
   當視窗處於橫屏狀態（`width > height`）且閱讀設定開啟 `spread`（如 `spread = 'auto'` 或 `'always'`）時，渲染器會自動啟動**跨頁/雙頁 (Spread) 模式**。
3. **頁面分組算法 (`#spreads`)**：
   - 渲染器會掃描 EPUB Spine 中的 `page-spread` 屬性（如 `page-spread-left` / `page-spread-right` / `page-spread-center`）。
   - 預設第一頁（封面）作為獨立單頁，後續頁面會自動兩兩分組打包成一個 Spread 陣列（如 `[1]`, `[2, 3]`, `[4, 5]`）。

---

## 2. 頁面順序 3-2、5-4 的運作原理 (RTL Page Progression)

日漫與繁中漫畫普遍採用 **RTL（Right-to-Left，由右至左）** 的閱讀流向：

1. **解析中繼資料 (Metadata)**：
   `foliate-js` 會讀取 EPUB `content.opf` 中 `<spine page-progression-direction="rtl">` 設定，或透過 API 將書籍物件的 `.dir` 屬性設為 `"rtl"`。
2. **DOM 節點映射與順序翻轉**：
   在 `FixedLayout` 的 `#render()` 計算邏輯中：
   - **LTR 模式 (左開/由左至右)**：
     - 左邊 DOM 節點放置前一頁 (Index N)
     - 右邊 DOM 節點放置後一頁 (Index N+1)
     - 呈現順序：**[ 2 | 3 ]**
   - **RTL 模式 (右開/由右至左)**：
     - **右邊** DOM 節點放置前一頁 (Index N，例如第 2 頁)
     - **左邊** DOM 節點放置後一頁 (Index N+1，例如第 3 頁)
     - 呈現順序：**[ 3 | 2 ]**
3. 翻頁到下一個 Spread 時，邏輯相同，自動將第 4 頁置於右側、第 5 頁置於左側，達成 **[ 5 | 4 ]** 的漫畫閱讀習慣。

---

## 3. 兩頁中間「無空白」的消除機制 (Zero-Gap / Seamless Edge-to-Edge)

跨頁連圖（Two-Page Spread）若出現白邊或隙縫會嚴重影響視覺體驗，`foliate-js` 透過以下三層手段確保兩頁完美無縫拼接：

### A. CSS 容器邊距完全歸零
`fixed-layout.js` 在 Shadow DOM 中建立 `iframe` 容器時，套用了極簡且嚴格的樣式設定：

```css
/* FixedLayout 主容器 */
:host {
    width: 100%;
    height: 100%;
    display: flex;
    justify-content: center;
    align-items: center;
    overflow: auto;
}

/* 包覆 iframe 的 div 與 iframe 本身 */
iframe {
    border: 0;
    margin: 0;
    padding: 0;
    display: block;
    overflow: hidden;
}
```

* 容器採用 Flex 佈局（`gap: 0` 預設值），保證兩個 `iframe` 的 DOM 邊界實體緊貼。

### B. 視埠解析與聯合視埠 (Combined Viewport) 縮放
1. **單頁 Viewport 提取**：
   透過 `getViewport()` 解析 XHTML 內的 `<meta name="viewport" content="width=w, height=h">` 或直接提取 `<img>` 的原始尺寸 (`naturalWidth`, `naturalHeight`)。
2. **聯合比例計算**：
   若為雙頁，將左右兩頁的 Viewport 進行邊界合併：
   - $\text{Total Width} = \text{Width}_{\text{left}} + \text{Width}_{\text{right}}$
   - $\text{Max Height} = \max(\text{Height}_{\text{left}}, \text{Height}_{\text{right}})$
3. **精確 Transform 縮放**：
   計算當前 WebView 容器可放下的最大 Scale 比例後，直接對包含了左右兩頁 `iframe` 的父級容器套用：
   ```javascript
   element.style.transform = `scale(${scale})`;
   ```
   這種將兩頁視為**單一複合 Viewport** 進行統一繪製與縮放的技術，徹底防止了瀏覽器像素捨入（Subpixel rounding）導致的 1px 縫隙。

---

## 4. Anx Reader (Flutter) 的調用與封裝

Anx Reader 透過 Flutter 的 `webview_flutter` 嵌入 `foliate-js`，其調用流程如下：

```mermaid
graph TD
    A[Flutter Layer / Anx Reader] -->|1. 載入 EPUB/CBZ| B[WebView / foliate-js]
    A -->|2. 發送指令: dir='rtl' & spread='auto'| B
    B -->|3. OPF 解析| C[Book Metadata: page-progression-direction="rtl"]
    C -->|4. 初始化| D[FixedLayout Web Component]
    D -->|5. 橫屏偵測| E[計算雙頁 Spread: [3, 2], [5, 4]]
    D -->|6. Viewport 計算| F[寬度相加/高度對齊 & gap=0 CSS 注入]
    F -->|7. 渲染畫面| G[無縫 3-2, 5-4 跨頁雙頁呈現]
```

---

## 5. 結論與借鏡建議

對於 elinkBook 等 Flutter 電子書閱讀器而言，若要實現類似的 FLX 漫畫雙頁密合呈現：
1. **頁面方向映射 (RTL Mapping)**：必須正確識別 `page-progression-direction="rtl"`，將前頁掛載至 Right Frame、後頁掛載至 Left Frame。
2. **零縫隙複合排版**：避免分別計算與渲染兩個 independent canvas/view，應將雙頁視為單一 Combined Box 計算比例，並將中間距 (`gap`) 與邊框 (`border`/`margin`) 歸零。
