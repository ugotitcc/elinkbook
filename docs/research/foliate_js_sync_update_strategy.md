# foliate-js 上游（readest/foliate-js）同步更新策略與作業程序分析報告

## 1. 摘要與核心結論 (Executive Summary)

本專案 `elinkBook` 採用 [readest/foliate-js](https://github.com/readest/foliate-js) 作為 EPUB（包含流式 Reflowable 與固定版面 FXL，見 [ADR 0011](../adr/0011-epub-reflowable-migrate-to-foliate-js.md) 與 [ADR 0017](../adr/0017-fxl-migrate-to-foliate-js.md)）的核心渲染引擎。直排繁體中文（`vertical-rl`）排版為本產品之核心差異化。

當上游社群對 `foliate-js` 核心檔案（如 `paginator.js`、`view.js`、`epub.js` 等）發布新版本或修改時，本專案必須在**「獲取上游效能與功能改進」**與**「維持電子紙（E-Ink）裝置高穩定性、舊版 WebView 相容性、直排無跳頁排版品質」**之間取得嚴格平衡。

### 核心結論與策略原則：
1. **嚴守「不修改 Vendored 釘定檔案」原則（ADR 0011 / 0017）**：
   `app/android/app/src/main/assets/foliate/` 內的 upstream 檔案一律維持純淨複製，不進行手動侵入式修改。所有相容性防護與客製邏輯，均透過 Dart 端的 Polyfill 注入（`_esCompatPolyfillJs`）或專案自建的 `main.js` 橋接層實現。
2. **全模組同步升級優於單檔孤立替換（Module Closure Integrity）**：
   `paginator.js` 與 `view.js`、`overlayer.js`、`fixed-layout.js` 之間存在密不可分的模組依賴。除純粹、已明確隔離的內部邏輯微調外，一般更新建議採「整套 vendored assets 同步 bump 至特定 commit SHA」的方式，以防模組介面撕裂。
3. **強制性舊版 WebView 相容性防護（ES Compatibility Guard）**：
   E-Ink 裝置（如 Mobiscribe WAVE 使用 Chromium 91、iReader Ocean 4 Plus 使用 Chromium 83）常無法更新 System WebView。任何上游升級**必須**通過 `app/tool/check_foliate_es_compat.js` 靜態掃描，且必要時在 `foliate_reader_view.dart` 補上 ES5/ES2020 相容的 Polyfill。
4. **直排對稱連續翻頁為 GO/NO-GO 必要判準**：
   `paginator.js` 的任何變更必須通過真機直排翻頁測試（往返截圖對稱、無跳頁、無丟頁、無回彈）。

---

## 2. 現狀架構與資產盤點 (Current Architecture & Asset Inventory)

> **這是一份持續性維護作業，不是一次性任務。** 上游 `readest/foliate-js` 會持續累積新 commit，過去已依本 SOP 執行過兩輪同步——`epic-32-foliate-js-paginator-sync`（同步至 `6c6a491`）、`epic-33-foliate-js-vendor-sync`（同步至 `c09f06d`）——未來預期會不定期重複執行第三輪、第四輪。**每次啟動新一輪同步前，務必先完整讀過本節，尤其是 2.3 節「已知手動 Patch 清單」**：`epic-33` 規劃階段就曾發生「整份覆蓋 `view.js` 會靜默移除既有手動 patch，若未及時發現會讓 Issue 1 自己的觸控測試 100% 崩潰」的驚險案例（見 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` 開頭說明），本節的存在就是為了讓下一輪同步不必重新踩一次這個坑。

### 2.1 上游來源與當前釘定狀態
- **上游 Repository**：`https://github.com/readest/foliate-js`
- **當前 Pinned Commit**：`c09f06da40737348fac71c03bc94bde53d5968b1` (2026-08-25)
- **資產存放路徑**：`app/android/app/src/main/assets/foliate/`
- **Pinned Commit 異動歷史**：`dd71f2be356563c16a23272686189fcfb45d0b82` (2026-07-19，最初釘定) → `6c6a491cf540696182d6fae70d6e26879b1e8369` (2026-07-25，`epic-32` 同步，範圍：`paginator.js` 觸控核心重寫) → `c09f06da40737348fac71c03bc94bde53d5968b1` (2026-08-25，`epic-33` 同步，範圍：7 個檔案，見 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md`)。

### 2.2 資產與職責劃分表

**本專案實際 vendored 的檔案共 11 個**（下表逐一列出；上游另有 `footnotes.js`／`pdf.js`／`tts.js`／`opds.js` 4 個檔案，本專案未採用、不在下表列範圍內，是否採用留待未來獨立產品決策，見 `epic-33/design.md`「非目標」）。新增一欄「本專案手動 Patch」——**這是全表最重要的一欄**：凡標示「有」的檔案，整份覆蓋同步時 100% 會把這段 patch 一併抹除，必須在同步完成後立即手動補回，詳細操作步驟見 2.3 節。

| 類別 | 檔案名稱 | 來源 | 核心職責與依賴關係 | 本專案手動 Patch（同步時務必保留／補回，見 2.3 節） |
| :--- | :--- | :--- | :--- | :--- |
| **Vendored** | `paginator.js` | 上游 | 分頁核心、CSS Multi-Column 計算、直排/橫排佈局、雙頁模式、翻頁手勢與動畫、`View` 容器管理 | **有**——[ADR 0024](../adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md)：`relocate` 事件 `detail` 補回 `contentPages` 欄位 |
| **Vendored** | `view.js` | 上游 | `foliate-view` Custom Element、開書進入點 (`makeBook`)、章節調度、導航與 `relocate` 事件發射 | **有**——[ADR 0024](../adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md)：`#onRelocate()` 消費 `contentPages`、新增 `clearLocationDensity()` 方法 |
| **Vendored** | `fixed-layout.js` | 上游 | 固定版面（FXL，漫畫/寫真）渲染、雙頁跨頁展開、RTL 頁序管理 | **有**——[ADR 0025](../adr/0025-fixed-layout-relative-module-specifier-reopen-adr-0011.md)：第 1 行 import 改為相對路徑 `./construct-style-sheets-polyfill.js` |
| **Vendored** | `progress.js` | 上游 | 章節進度估算 | **有**——[ADR 0024](../adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md)：`recordDensity(index, contentPages)`／`clearDensity()`／`#density` Map（`epic-33` c09f06d 同步範圍內剛好未變動未受影響，但這不代表下次同步也會這麼幸運，仍須照 2.3 節檢查） |
| **Vendored** | `epub.js` | 上游 | EPUB 容器解構、OPF/NCX/Nav 解析、Spine 與 Manifest 資源加載 | 無 |
| **Vendored** | `epubcfi.js` | 上游 | CFI (Canonical Fragment Identifier) 定位解析與字串生成 | 無 |
| **Vendored** | `overlayer.js` | 上游 | 劃線、螢光筆、底線之 SVG 渲染層與點擊命中測試 (`hitTest`) | 無 |
| **Vendored** | `comic-book.js` | 上游 | CBZ 漫畫容器讀取（`epic-33` c09f06d 同步範圍內確認逐位元組相同） | 無 |
| **Vendored** | `text-walker.js` | 上游 | DOM 文字節點遍歷 | 無 |
| **Vendored** | `vendor/zip.js` | 上游 | EPUB Zip 解壓縮核心 | 無 |
| **Vendored** | `construct-style-sheets-polyfill.js` | 上游 | CSSStyleSheet 建構 Polyfill | 無 |
| **App Bridge** | `index.html` | 本專案 | WebView 初始 HTML 容器，載入 `<foliate-view>` 與 `main.js` | 不適用（本專案自建，非 vendored） |
| **App Bridge** | `main.js` | 本專案 | JS ↔ Flutter Bridge 核心：樣式注入 (`applyPreferences`)、標記管理 (`setDecorations`)、熱區手勢與事件轉發 | 不適用（本專案自建，非 vendored） |
| **Dart Core** | `foliate_reader_view.dart` | 本專案 | InAppWebView 容器管理、`_esCompatPolyfillJs` 注入、JavaScript Handlers 註冊 | 不適用 |
| **Dart Core** | `foliate_native_bridge.dart` | 本專案 | 資源串流橋接、`@font-face` CSS 產生、音量鍵生命週期掛載 | 不適用 |
| **Dart Core** | `foliate_bridge_codec.dart` | 本專案 | CFI 萃取、TOC 解析、劃線顏色與座標轉換等純函式 | 不適用 |
| **Dev Tool** | `app/tool/check_foliate_es_compat.js`| 本專案 | 升級掃描工具：檢查 Vendored JS 是否包含未防護的較新 ES API | 不適用 |

### 2.3 已知手動 Patch 清單（每次同步前後必查）

以下是目前所有已知、經 ADR 正式記錄的手動 patch。**同步流程的標準做法是整份覆蓋 vendored 檔案（見 4 節策略 B、ADR 0011），這代表下表每一項都會在覆蓋當下被無條件抹除**，必須在下載完成後、進入測試前立即手動補回。若上游後續版本把這些 patch 對應的原生能力補齊了（例如上游自己也做了密度校正），才需要重新評估是否還要保留 patch、或改為正式提報上游合併——不能自行假設「反正上次還在就繼續補」。

#### Patch 1：ADR 0024 流式 EPUB 密度校正

- **記錄於**：[ADR 0024](../adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md)（`epic-26-architecture-hardening` Issue 11 建立）
- **涉及檔案**：`paginator.js`、`view.js`、`progress.js`
- **同步前檢查**（確認目前釘定版本的 patch 仍在，做為補回時的比對基準）：
  ```bash
  grep -n "detail.contentPages" app/android/app/src/main/assets/foliate/paginator.js
  grep -n "clearLocationDensity" app/android/app/src/main/assets/foliate/view.js
  grep -n "recordDensity\|clearDensity" app/android/app/src/main/assets/foliate/progress.js
  ```
- **同步後必須補回**：
  1. `paginator.js`：在 `detail.fraction`／`detail.size` 賦值之後，補回 `detail.contentPages = textPages`（`relocate` 事件 payload）。
  2. `view.js`：`#onRelocate({ reason, range, index, fraction, size })` 簽章補上 `contentPages` 參數，方法內補回 `if (contentPages) this.#sectionProgress?.recordDensity(index, contentPages)`；並新增 `clearLocationDensity() { this.#sectionProgress?.clearDensity() }` 方法。
  3. `progress.js` 通常不需改動（`recordDensity`／`clearDensity`／`#density` Map 是消費端，patch 主體在 `paginator.js`／`view.js`），但仍要跑上方「同步前檢查」確認上游這次有沒有變動這個檔案本身。
  - 完整逐步操作範例（含確切程式碼與驗證指令）見 `docs/epics/epic-33-foliate-js-vendor-sync/plans/plan-issue-1.md` Task 2。
- **為什麼這是 Critical 等級**：`main.js` 第 175 行左右 `window.applyPreferences()`（使用者調整任何排版設定都會觸發）無條件呼叫 `view.clearLocationDensity()`。若 `view.js` 缺這個方法，會直接拋出 `TypeError`；`app/tool/foliate_touch_harness/run-all.mjs` 觸控 Harness 執行真實 `main.js`／`view.js`，會在第一次 `relocate` 事件觸發 `applyPreferences()` 時 100% 逾時崩潰，導致**連同步工單本身的自動化測試都無法通過**（`epic-33` Issue 1 規劃階段實際發生過）。

#### Patch 2：ADR 0025 `fixed-layout.js` 相對路徑模組匯入

- **記錄於**：[ADR 0025](../adr/0025-fixed-layout-relative-module-specifier-reopen-adr-0011.md)（`epic-33-foliate-js-vendor-sync` Issue 1 建立）
- **涉及檔案**：`fixed-layout.js`（僅第 1 行）
- **同步前檢查**：
  ```bash
  head -n 1 app/android/app/src/main/assets/foliate/fixed-layout.js
  ```
  應輸出 `import './construct-style-sheets-polyfill.js'`（相對路徑）。
- **同步後必須補回**：上游原始碼這一行是裸模組匯入 `import 'construct-style-sheets-polyfill'`，整份覆蓋會被打回這個寫法，必須手動改回相對路徑 `import './construct-style-sheets-polyfill.js'`。
- **為什麼這是 Critical 等級**：本專案沒有 import map／打包工具，裸模組匯入在 Android WebView 執行期會直接失敗（`Failed to resolve module specifier`），**症狀是 FXL／CBZ 書籍完全無法開啟**，且——這是最危險的地方——**目前沒有任何自動化測試層覆蓋到這個檔案的動態載入路徑**（`app/tool/foliate_touch_harness/` 4 個情境的 fixture 全是 reflowable EPUB，不會觸發 `fixed-layout.js` 的 `import()`）。這代表 ES 掃描乾淨、觸控 Harness 全過、`flutter test` 全過，**都不能證明這一行是對的**——唯一的把關手段是真機實際開一本 CBZ 與一本 FXL EPUB。**因此每一輪同步的真機驗收階段，都必須把「開 CBZ／FXL 書」排在最優先，不要留到測試清單最後才做**（`epic-33` Issue 2 已採用這個順序，見其 `issues.md`「優先驗證項目」，未來同步應沿用）。

#### 已確認「無 patch」的檔案（提醒：這份清單也需要每輪同步後重新確認）

`epub.js`／`epubcfi.js`／`overlayer.js`／`comic-book.js`／`text-walker.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js` 截至 `c09f06d` 同步為止，皆為逐位元組上游純淨版本，沒有任何本專案手動修改。**這不是永久保證**——若未來某次同步為了解決特定裝置問題而不得不對其中某個檔案加 patch，必須立即：(1) 建立新 ADR 記錄，(2) 更新本節表格與清單，(3) 在該次同步的 `issues.md` 完成摘要中明確提及。絕不能像 `fixed-layout.js` 那樣讓 patch 存在了一整個同步週期卻沒有正式記錄（`epic-33` 前，這行修正已存在但從未被記錄，直到 `epic-33` 才補登記為 ADR 0025）。

---

## 3. `paginator.js` 更新的潛在衝擊面分析 (Impact Surface Analysis)

當上游 `paginator.js` 發生變更時，可能對以下五大維度產生重大衝擊：

```
                 ┌─────────────────────────────────────────┐
                 │ readest/foliate-js (上游 paginator.js)  │
                 └───────────────────┬─────────────────────┘
                                     │ 同步更新
                                     ▼
      ┌─────────────────────────────────────────────────────────────┐
      │                   elinkBook 系統衝擊面                       │
      ├──────────────────────┬──────────────────────┬───────────────┤
      │ 1. 舊版 WebView 相容  │ 2. 繁中直排分頁與排版 │ 3. 橋接與契約 │
      │    • ES2021+ 內建方法 │    • vertical-rl 對稱│    • relocate │
      │    • 語法解析失敗崩潰 │    • columnMode 雙頁 │    • API 簽章 │
      ├──────────────────────┼──────────────────────┼───────────────┤
      │ 4. 模組閉包一致性     │ 5. 標記與手勢座標    │               │
      │    • view.js 介面匹配│    • overlayer 座標系│               │
      │    • fixed-layout    │    • 導航熱區事件    │               │
      └──────────────────────┴──────────────────────┴───────────────┘
```

### 3.1 舊版 WebView / ES 語法崩潰風險（High Risk 🔴）
* **問題根因**：E-Ink 電子書閱讀器系統版本通常較舊（如 Android 8.1~12），內建的 `com.android.webview` 常停留在 Chromium 83~91。若上游代碼引入 ES2021~ES2024 特性，舊版 WebView 會在解析階段或執行時直接報錯。
* **歷史前例**：
  - `Object.groupBy` / `Map.groupBy` (ES2024，需 Chromium 117+)
  - `Array.prototype.at()` (ES2022，需 Chromium 92+)
  - `Array.prototype.findLastIndex()` (ES2023，需 Chromium 97+)
  - `??=` / `?.` 語法糖在 Chromium 83 解析失敗導致整份腳本不執行（見 Issue 38/41 紀錄）。
* **衝擊結果**：開書時 WebView 靜默失敗，畫面永久卡在 Loading 轉圈指示器（`reader_loading_indicator`）。

### 3.2 繁中直排分頁與動態排版回歸風險（High Risk 🔴）
* **核心依賴**：`paginator.js` 中的 `View.columnize()`、`View.expand()`、`slideTurnAnimation` 與 `getRectMapper()`。
* **潛在風險**：
  1. **直排連續翻頁跳頁/丟頁**：上游若調整 DOM 尺寸計算 (`getBoundingClientRect`) 或捲軸偏移量 (`scrollTop`)，可能破壞直排翻頁的單步連續性與往返對稱性。
  2. **單欄/雙欄模式（ADR 0012）**：上游直排原先存在 `maxColumnCount + 1` 邏輯，若上游調整欄數計算，需確認 `columnMode`（單欄/雙欄強制設定）在大螢幕與直排時是否仍然正常。
  3. **四方向獨立邊距（ADR 0014）**：上游若改變 `@page` 或 `column-gap` 樣式注入機制，可能導致 Dart 端傳入的 `padding-top/right/bottom/left` 覆寫失效或產生多重邊距。
  4. **字元間距與排版樣式（Epic 28）**：`letter-spacing`、`line-height`、`font-size` 等動態 Reflow 後的錨點重定位（Anchor re-scrolling）是否精確。

### 3.3 Bridge 與事件契約變更風險（Medium Risk 🟡）
* **介面依賴**：`main.js` 直接呼叫 `paginator` / `view` 的方法，並監聽其事件：
  - `view.renderer.setAttribute(...)`
  - `view.next()` / `view.prev()` / `view.goToFraction()` / `view.goTo()`
  - `relocate` 事件：依賴 `event.detail` 內的 `{ cfi, fraction, location, index, head, tail }`。
* **衝擊結果**：若上游變更事件欄位名稱、CFI 格式或導航方法簽章，會導致 Dart 端進度無法更新、章節目錄跳轉失效或 TOC 頁碼錯誤。

### 3.4 跨模組依賴耦合（Module Closure Mismatch）（Medium Risk 🟡）
* `paginator.js` 與 `view.js` 高度耦合（`view.js` 實例化 `Paginator` 並傳遞渲染器容器與回呼）。
* 若**僅單獨替換 `paginator.js`**，而未更新 `view.js`，極易發生內部 private 欄位或內部事件名稱不匹配的靜默錯誤。

### 3.5 標記與選取座標偏移（Annotation Coordinate Shift）（Medium Risk 🟡）
* `overlayer.js` 的 `Overlayer.highlight()` / `underline()` 依賴 `paginator.js` 算出的分頁邊界與座標映射進行 SVG 幾何計算。
* 若 `paginator.js` 變更了內部座標系，劃線高亮可能出現位置位移、底線方向錯誤或長按無法選字。

---

## 4. 同步更新策略比較 (Upgrade Strategies Comparison)

| 策略維度 | 策略 A：單檔 Targeted Patch (僅更新 `paginator.js`) | 策略 B：全模組同步升級 (Full Vendor Bump，推薦) |
| :--- | :--- | :--- |
| **適用情境** | 上游僅對 `paginator.js` 釋出獨立 Bugfix，且確認未改動任何跨模組介面與公開 API。 | 上游有較大幅度演進、效能重構、或發布新的 Release / Commit。 |
| **作業成本** | 較低（僅比對單一檔案）。 | 中等（需完整下載全套依賴並進行全盤測試）。 |
| **模組一致性** | ⚠️ **較低**，存在 `paginator.js` 與 `view.js` 內部版本撕裂風險。 | ✅ **最高**，保證 `readest/foliate-js` 內部閉包完全相容。 |
| **回退難易度** | 單檔回退快速。 | Git Commit 整組回退，乾淨明確。 |
| **官方/專案慣例** | 不符合 ADR 0011 第 26 條慣例。 | **完全符合專案架構規範與 ADR 0011/0017 先例**。 |

> **決策建議**：一律以 **策略 B（全模組同步升級）** 作為標準作業流程。只有在緊急修復特定單一 Bug 且已透過 Diff 證明完全無跨模組副作用時，才破例考慮策略 A。

---

## 5. 標準同步更新作業程序 (Standard Operating Procedure, SOP)

當決定同步上游更新時，請嚴格按照以下六階段執行：

```
┌─────────────────────────────────────────────────────────────┐
│ 階段 1：Upstream 差異分析與審查 (Upstream Diff Audit)         │
│   • 檢視 GitHub commit / diff，確認變更範圍與 API 契約       │
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 2：資產下載與 Commit 釘定 (Asset Replacement & Pinning) │
│   • 下載變動檔案至 assets/foliate/，依 2.3 節補回手動 Patch │
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 3：ES 相容性靜態掃描與 Polyfill 防護 (ES Compat Scan)   │
│   • 執行 node app/tool/check_foliate_es_compat.js           │
│   • 於 foliate_reader_view.dart 補齊 Polyfill (ES5 語法)     │
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 4：Bridge 與樣式層對齊 (Bridge Alignment)              │
│   • 檢查 main.js、foliate_bridge_codec.dart 與 CSS 覆寫      │
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 5：多層級自動化測試驗證 (Verification Pipeline)         │
│   • flutter analyze ➔ flutter test ➔ integration_test (真機)│
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 6：版本紀錄與文件更新 (Documentation & Archiving)       │
│   • 更新本文件 2.1/2.2/2.3 節、docs/epics.md                │
└─────────────────────────────────────────────────────────────┘
```

### 階段 1：Upstream 差異分析與審查 (Upstream Diff Audit)
1. **確認上游目標 Commit**：
   在 `https://github.com/readest/foliate-js` 找出目標 commit SHA（例如 `<NEW_COMMIT_SHA>`）。
2. **產出 Diff 並逐項審查**：
   比對目前釘定版本（見 2.1 節「當前 Pinned Commit」，撰寫本文時為 `c09f06d`，執行時請改用當下實際記錄的值）與目標版本之間的差異：
   ```bash
   git diff <CURRENT_PINNED_SHA> <NEW_COMMIT_SHA> -- paginator.js view.js
   ```
3. **查核檢核點（Checklist）**：
   - [ ] 是否修改了 `Paginator` 或 `View` 的公開方法簽章？
   - [ ] 是否新增或更動了 `relocate`、`create-overlayer` 等自訂事件的 Payload 欄位？
   - [ ] 是否修改了直排排版 (`vertical-rl`) 的分欄邏輯或軸向映射？
   - [ ] 是否引入了新的第三方依賴？

### 階段 2：資產下載與 Commit 釘定 (Asset Replacement)
1. 先用 GitHub API／`git diff` 逐檔確認哪些檔案真的有變動（不必每次都整批下載全部 11 個檔案，但決定要不要下載某檔案前，務必先查過 2.2 節該檔案是否帶有手動 patch，而不是只看有沒有變動）。**本專案完整 vendored 檔案共 11 個**（見 2.2 節表格；上游另有 4 個本專案未採用的檔案，不在此列）：
   - `epub.js`
   - `epubcfi.js`
   - `fixed-layout.js`
   - `overlayer.js`
   - `paginator.js`
   - `progress.js`
   - `text-walker.js`
   - `view.js`
   - `comic-book.js`
   - `vendor/zip.js`
   - `construct-style-sheets-polyfill.js`
2. **嚴格禁止覆蓋專案自建檔案**：
   - 保持 `index.html` 與 `main.js` 不被覆寫。
3. **下載完成後，立即依 2.3 節「已知手動 Patch 清單」逐項補回**——這一步不可省略、不可延後到後續工單才做，見 2.3 節說明的崩潰風險。

### 階段 3：ES 相容性靜態掃描與 Polyfill 防護 (ES Compatibility)
1. **執行靜態掃描腳本**：
   ```bash
   node app/tool/check_foliate_es_compat.js
   ```
2. **處理掃描結果**：
   - 若結束碼為 `0`：代表所有已知的危險 API 皆受防護。
   - 若結束碼為 `1`：查看腳本列出的未防護 API（例如使用了 `Promise.withResolvers`、`structuredClone`、`toSorted` 等）。
3. **補齊 Polyfill**：
   在 `app/lib/reader/foliate_reader_view.dart` 的 `_esCompatPolyfillJs` 常數中加入 Polyfill。
   > [!IMPORTANT]
   > **Polyfill 編寫硬性規範**：
   > 1. 僅在 `if (!TargetAPI)` 缺席時才定義，不可覆寫瀏覽器原生實作。
   > 2. **嚴禁使用 ES2021+ 語法糖**（禁止使用 `??=`、`||=`、`&&=`、可選鏈 `?.`、標籤模板等），本體必須為 ES5/ES2020 相容語法，以確保能在 Chromium 83 上被正確解析。
4. **驗證與更新測試**：
   更新 `app/test/reader/foliate_reader_view_test.dart` 中針對 `initialUserScripts` 的斷言，確保涵蓋新加入的 Polyfill 名稱。

### 階段 4：Bridge 與樣式層對齊 (Bridge Alignment)
1. **檢查 `main.js`**：
   - 確認 `import { makeBook } from './view.js'` 與 `import { Overlayer } from './overlayer.js'` 正常運作。
   - 確認 `window.applyPreferences()` 產生的 CSS 規則（字級、行距、字距、四向邊距）能正確傳遞給 `Paginator`。
2. **檢查 `foliate_bridge_codec.dart`**：
   - 確保 CFI 萃取（`extractCfi`）、目錄解析（`parseTableOfContents`）及標記編碼（`buildDecorationEntries`）與新版本格式相容。

### 階段 5：多層級自動化測試與真機驗證 (Verification Pipeline)
執行以下指令確保各層級測試全數通過：

```bash
# 1. 靜態程式碼分析（必須 100% 乾淨）
cd app
flutter analyze

# 2. 純 Dart Unit / Widget 測試
flutter test

# 3. 指定 Foliate 相關單元測試
flutter test test/reader/foliate_bridge_codec_test.dart
flutter test test/reader/foliate_reader_view_test.dart
flutter test test/reader/foliate_native_bridge_test.dart
flutter test test/screens/reader_screen_test.dart

# 4. 真機整合測試（需接上真實 Android 裝置）
flutter test -d <device-id> integration_test/foliate_epub_reader_view_test.dart
flutter test -d <device-id> integration_test/epub_dual_page_test.dart
flutter test -d <device-id> integration_test/foliate_single_column_test.dart
flutter test -d <device-id> integration_test/foliate_margin_test.dart
flutter test -d <device-id> integration_test/foliate_stream_nav_zone_test.dart
flutter test -d <device-id> integration_test/foliate_highlights_notes_test.dart
```

#### 真機排版重點人工檢驗清單：

> **順序很重要**：第一項務必最先做，不要留到最後——這是 Patch 2（ADR 0025）唯一的把關手段，且完全不受任何自動化測試層覆蓋，見 2.3 節說明。

- [ ] **優先驗證：CBZ／FXL 開書測試**：開一本 CBZ 與一本 FXL EPUB，確認能正常顯示第一頁（不是白屏、不是無限轉圈、WebView console 沒有 `Failed to resolve module specifier`）。若失敗，先處理 Patch 2 是否漏補，不要繼續測後面項目。
- [ ] **歷史修法回歸（3 項，每輪同步皆須重測）**：長按選字前幾影格畫面不暴跳（Epic 18 Issue 47）、畫線選取已確立時不誤觸跳頁（Epic 25 Issue 1）、`no-swipe` 屬性正確阻止滑動（Epic 27 Issue 9）。
- [ ] **繁中直排連翻測試**：使用直排 EPUB 連續翻頁 5 次，再反向翻頁 5 次，比對內容是否完全無縫銜接、無重複、無跳頁（快速停損指標核心判準，記錄逐字錨點文字、務必用實際受測的指定 fixture，不要用其他書籍代替）。
- [ ] **橫直排即時切換**：在閱讀中切換橫排 ↔ 直排，確認閱讀位置（Anchor）精準維持在當前段落。
- [ ] **字型與排版偏好調整**：調整字級、行距、字距、四向邊距，確認頁面 Reflow 正常且無崩潰。
- [ ] **劃線與備註**：選取文字建立螢光筆與底線，確認標記位置準確，點擊標記能彈出編輯選單。
- [ ] **FXL 漫畫雙頁跨頁與封面單頁**：開啟固定版面漫畫，確認 RTL 頁序、橫向雙頁跨頁排版、封面獨立單頁顯示皆正常。
- [ ] **劃線標註縮放後正確刷新**：固定版面縮放（zoom）畫面後，劃線覆蓋層需自動刷新並精準對齊，不需額外手動操作。

> 完整逐項操作步驟範例、記錄格式、判準見兩次已執行過的先例：`docs/epics/epic-32-foliate-js-paginator-sync/plans/plan-issue-3.md`、`docs/epics/epic-33-foliate-js-vendor-sync/plans/plan-issue-2.md`（含真機重測報告範本）。

### 階段 6：版本紀錄與文件更新 (Documentation & Archiving)
1. **更新本文件 2.1 節**：「當前 Pinned Commit」改為新 SHA，並在「Pinned Commit 異動歷史」補上這一輪的記錄（新 SHA、日期、對應同步工單名稱）。
2. 更新 `docs/epics.md` 對應該次同步 Epic 的那一列，反映完成狀態。
3. **不需要更新 `CONTEXT.md`／`AGENTS.md`**——`CONTEXT.md` 定位為純詞彙表，不放這類實作細節；已有兩輪同步（`epic-32`、`epic-33`）皆未更新這兩份文件，`epic-33` 規劃階段也已明確評估並駁回「補更新 CONTEXT.md／AGENTS.md」的建議（見 `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-design.md`），沿用即可，不要重新引入。
4. 若這次同步過程新增了任何手動 patch（例如為了相容特定裝置而不得不修改某個原本純淨的 vendored 檔案），依專案規範撰寫新 ADR（例如 `docs/adr/NNNN-<描述>.md`），並**務必回頭更新本文件 2.2／2.3 節**——這是本節與其他版本紀錄文件最大的不同：2.2／2.3 節的角色是給「下一輪同步」看的操作手冊，遺漏更新會導致下一輪重蹈 `epic-33` 前 `fixed-layout.js` patch 沒被正式記錄的覆轍。
5. 提交 Git Commit，Commit Message 建議格式：
   ```text
   chore(foliate): bump readest/foliate-js to <NEW_COMMIT_SHA>

   - 同步上游 paginator.js 及相關模組更新
   - 經 check_foliate_es_compat.js 掃描並補齊 Polyfill
   - 通過 flutter analyze, flutter test 及真機 integration_test
   ```

---

## 6. 風險矩陣與應變措施 (Risk Matrix & Contingency Plan)

| 風險項目 | 可能性 | 嚴重度 | 緩解與應變措施 (Mitigation) |
| :--- | :---: | :---: | :--- |
| **舊版 E-Ink 裝置白屏/卡 Loading** | 高 | 極高 | 1. 執行 `check_foliate_es_compat.js` 預先攔截。<br>2. 補上 ES5 Polyfill。<br>3. 透過 `ReaderResourceChannel` log 與真機測試驗證。 |
| **繁體中文直排翻頁跳頁回歸** | 中 | 極高 | 1. 執行 `foliate_epub_reader_view_test.dart` 整合測試。<br>2. 人工進行直排連續翻頁對稱性驗證。 |
| **自訂四向邊距失效** | 中 | 中 | 檢視 `main.js` 注入之 CSS 與 `paginator.js` 樣式覆蓋優先級（`!important`）。 |
| **劃線標記座標位移** | 低 | 高 | 執行 `foliate_highlights_notes_test.dart` 驗證 `Overlayer` SVG 矩陣轉換。 |
| **突發重大不可預期回歸** | 低 | 極高 | **快速回退機制**：`git revert` 該次同步 commit（若同步分成多個 commit，依新到舊逐一 revert），退回至 2.1 節「Pinned Commit 異動歷史」記錄的前一版穩定 commit；`epic-33` design.md 訂有明確的 2 小時快速停損指標可供參考——若直排對稱翻頁失敗或出現舊版 WebView `SyntaxError` 且 2 小時內無法排除，直接 revert，不在時間壓力下硬修。 |

---

## 7. 結論與維護建議 (Summary & Recommendations)

1. **落實自動化與標準化**：
   本次分析建立的標準 SOP 將上游同步流程結構化。未來當 GitHub 上 `readest/foliate-js`（包含 `paginator.js`）有重要修正時，工程團隊可直接依照本 SOP 快速、安全地完成升級評估與落地。
2. **維持「外部防護，內部純淨」的架構純度**：
   不直接 Hack 上游 Vendored 原始碼，將所有針對特定 E-Ink 裝置與專案特性的適配集中於 `_esCompatPolyfillJs`、`main.js` 與 Dart 原生層。這使得每次升級時的 Diff 比對與升級路徑最清晰、維護負擔最低。
