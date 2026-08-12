# Readest 透過 readest/foliate-js 實現 FLX 漫畫雙頁 (3-2, 5-4) 無縫呈現與 Anx Reader 比較分析報告

## 概述

**Readest**（https://github.com/readest/readest）是一套現代化跨平台的電子書閱讀器。與 Anx Reader 直接選用 upstream 原生 `johnfactotum/foliate-js` 不同，Readest 為了提供更極緻的排版與邊界處理，維護了自己的 **`readest/foliate-js` Fork 分支**。

本報告深入剖析 Readest 如何透過其自訂的 `fixed-layout.js` 實現 FLX (Fixed-Layout) 漫畫橫屏雙頁、RTL 順序（3-2, 5-4）與零縫隙呈現，並與 Anx Reader 的實現機制進行詳細對比。

---

## 1. Readest 的 FLX 橫屏雙頁呈現機制

在 Readest 的 `fixed-layout.js` 模組中，雙頁呈現同樣依賴 `ResizeObserver` 與 Viewport 比例計算，但 Readest 對排版細節進行了深度優化：

### 橫屏 Margin 動態計算 (`computeSpreadInlineMargins`)
Readest 新增了專屬的 inline margin 算式：
```javascript
export const computeSpreadInlineMargins = (portrait) => portrait
    ? {
        left: { marginInlineStart: 'auto', marginInlineEnd: 'auto' },
        right: { marginInlineStart: 'auto', marginInlineEnd: 'auto' },
    }
    : {
        left: { marginInlineStart: 'auto', marginInlineEnd: '' },
        right: { marginInlineStart: '', marginInlineEnd: 'auto' },
    }
```
* **橫屏 (Landscape)**：左頁靠右對齊 (`marginInlineStart: 'auto'`)，右頁靠左對齊 (`marginInlineEnd: 'auto'`)，使兩頁自動在脊線 (Spine) 緊密吸附居中。
* **直屏 (Portrait)**：單頁兩側 margin 皆設為 `auto`，防止單頁在寬視埠下被扯到單邊。

---

## 2. 頁面順序 3-2、5-4 (RTL) 的運作原理

Readest 處理 RTL（Right-to-Left，右開漫畫）的底層邏輯與標準 foliate-js 一致：

1. **RTL Metadata 識別**：讀取 Spine 的 `page-progression-direction="rtl"`（或 `book.dir === 'rtl'`）。
2. **左右 Frame 反轉映射**：
   - 畫面**右側**：放置順序較前的頁面（Index N，例如第 2 頁）。
   - 畫面**左側**：放置順序較後的頁面（Index N+1，例如第 3 頁）。
   - 最終呈現 **[ 3 | 2 ]** 以及下一跨頁 **[ 5 | 4 ]**。
3. **UI/手勢層與 RTL 對齊**：Readest 在其前端（Next.js / React）層級，將滑動/鍵盤翻頁方向與 RTL 排版進行了同步鎖定，確保向右滑動為前翻、向左滑動為後翻。

---

## 3. 兩頁中間無空白與消除「1px 白縫」機制

這是 Readest 與 Anx Reader (標準 foliate-js) 最顯著的差異點！

### 高 DPI 螢幕白縫修正 (`computeSpreadSpineOverlap`)
在傳統或標準 foliate-js 中，兩獨立 `iframe` 在高 DPI（如 Retina / 2.5x, 3x DPR 手機螢幕）或非整數縮放比例下，瀏覽器的合成層 (Compositor Layer) 會在 `iframe` 邊緣進行抗鋸齒 (Anti-aliasing)，導致底色透過縫隙滲出，產生 **1px 細白縫** (White Spine Seam)。

Readest 專門針對此 Issue (#4857) 實作了脊線疊加算式：
```javascript
export const computeSpreadSpineOverlap = ({
    center = false, portrait = false, leftBlank = false, rightBlank = false,
    devicePixelRatio = 1,
} = {}) => {
    if (center || portrait || leftBlank || rightBlank) return 0
    return -1 / (devicePixelRatio || 1)
}
```
* **微距物理像素重疊**：計算 $1 / \text{devicePixelRatio}$ 的物理像素偏移量（例如在 DPR 3 的螢幕上偏移 -0.333px）。
* **消除白縫原理**：將右側 `iframe` 向左微移 1 個物理像素蓋在左頁上，讓鋸齒抗鋸齒區落在不透明的圖像內容上，而非透出背景白邊。

---

## 4. Anx Reader vs. Readest 比較分析

下表總結兩者在 FLX 漫畫雙頁無縫呈現上的相同與差異：

| 比較項目 | Anx Reader (`anxcye/anx-reader`) | Readest (`readest/readest`) |
| :--- | :--- | :--- |
| **`foliate-js` 來源** | 使用 Upstream 原生 `johnfactotum/foliate-js` | 維護自訂 Fork `readest/foliate-js` |
| **應用層技術棧** | Flutter + WebView (`webview_flutter`) | Tauri / Web + React / Next.js |
| **橫屏雙頁 (Spread)** | 依賴原生 `FixedLayout` 基本 `ResizeObserver` | 新增 `computeSpreadInlineMargins` 動態處理 Spine 居中對齊 |
| **RTL 順序 (3-2, 5-4)** | 依據 `dir === 'rtl'` 交換 DOM 左右映射 | 相同，且在 React UI 層同步調整 RTL 觸控手勢方向 |
| **中間無空白 (Zero Gap)** | 依靠 CSS `gap: 0`, `border: 0` 與全頁 Transform Scale | 採用 CSS `gap: 0` + **`computeSpreadSpineOverlap`** 修正 |
| **1px 白縫 (White Seam) 處理** | 未特別處理，在部分 DPR 下偶爾會有 1px 底色透出白縫 | **針對 #4857 專利級修正**：利用 `-1/DPR` 物理像素疊加，徹底消除白縫 |
| **連續捲動 (Scroll Mode)** | 固定排版以翻頁模式為主 | 在 `fixed-layout.js` 實現了 `planScrollModePages` 超長漫畫 continuous scroll 記憶體優化 |

---

## 5. 結論與 elinkBook 開發建議

1. **白縫問題 (White Spine Seam)**：若 elinkBook 在 Android 裝置（高 DPI E-Ink 螢幕）上遇到雙頁跨頁中間有 1px 白線透出的問題，可借鏡 Readest 的 **`computeSpreadSpineOverlap`** 方案，將右頁向左微移 1 個物理像素（$-1 / \text{DPR}$）。
2. **動態邊距**：採用 Readest 的 `computeSpreadInlineMargins` 可防止直橫屏切換時 Layout 遺留舊 margins 的問題。
