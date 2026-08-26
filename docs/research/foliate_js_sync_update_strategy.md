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
   E-Ink 裝置（如 Mobiscribe WAVE 使用 Chromium 91、iReader Ocean 4 Plus 使用 Chromium 83）常無法更新 System WebView。任何上游升級**必須**通過 `app/tool/check_foliate_es_compat.js` 靜態掃描，且必要時在 `foliate_epub_reader_view.dart` 補上 ES5/ES2020 相容的 Polyfill。
4. **直排對稱連續翻頁為 GO/NO-GO 必要判準**：
   `paginator.js` 的任何變更必須通過真機直排翻頁測試（往返截圖對稱、無跳頁、無丟頁、無回彈）。

---

## 2. 現狀架構與資產盤點 (Current Architecture & Asset Inventory)

### 2.1 上游來源與當前釘定狀態
- **上游 Repository**：`https://github.com/readest/foliate-js`
- **當前 Pinned Commit**：`c09f06da40737348fac71c03bc94bde53d5968b1` (2026-08-25)
- **資產存放路徑**：`app/android/app/src/main/assets/foliate/`

### 2.2 資產與職責劃分表

| 類別 | 檔案名稱 | 來源 | 核心職責與依賴關係 |
| :--- | :--- | :--- | :--- |
| **Vendored** | `paginator.js` | 上游 | 分頁核心、CSS Multi-Column 計算、直排/橫排佈局、雙頁模式、翻頁手勢與動畫、`View` 容器管理 |
| **Vendored** | `view.js` | 上游 | `foliate-view` Custom Element、開書進入點 (`makeBook`)、章節調度、導航與 `relocate` 事件發射 |
| **Vendored** | `fixed-layout.js` | 上游 | 固定版面（FXL，漫畫/寫真）渲染、雙頁跨頁展開、RTL 頁序管理 |
| **Vendored** | `epub.js` | 上游 | EPUB 容器解構、OPF/NCX/Nav 解析、Spine 與 Manifest 資源加載 |
| **Vendored** | `epubcfi.js` | 上游 | CFI (Canonical Fragment Identifier) 定位解析與字串生成 |
| **Vendored** | `overlayer.js` | 上游 | 劃線、螢光筆、底線之 SVG 渲染層與點擊命中測試 (`hitTest`) |
| **Vendored** | `progress.js` / `text-walker.js` | 上游 | 章節進度估算、DOM 文字節點遍歷 |
| **Vendored** | `vendor/zip.js` | 上游 | EPUB Zip 解壓縮核心 |
| **Vendored** | `construct-style-sheets-polyfill.js` | 上游 | CSSStyleSheet 建構 Polyfill |
| **App Bridge** | `index.html` | 本專案 | WebView 初始 HTML 容器，載入 `<foliate-view>` 與 `main.js` |
| **App Bridge** | `main.js` | 本專案 | JS ↔ Flutter Bridge 核心：樣式注入 (`applyPreferences`)、標記管理 (`setDecorations`)、熱區手勢與事件轉發 |
| **Dart Core** | `foliate_epub_reader_view.dart` | 本專案 | InAppWebView 容器管理、`_esCompatPolyfillJs` 注入、JavaScript Handlers 註冊 |
| **Dart Core** | `foliate_native_bridge.dart` | 本專案 | 資源串流橋接、`@font-face` CSS 產生、音量鍵生命週期掛載 |
| **Dart Core** | `foliate_bridge_codec.dart` | 本專案 | CFI 萃取、TOC 解析、劃線顏色與座標轉換等純函式 |
| **Dev Tool** | `app/tool/check_foliate_es_compat.js`| 本專案 | 升級掃描工具：檢查 Vendored JS 是否包含未防護的較新 ES API |

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
  - `view.next()` / `view.prev()` / `view.goToFraction()` / `view.goToCfi()`
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
│   • 下載指定 commit 之 9 個 Vendored 模組至 assets/foliate/  │
└─────────────────────────────┬───────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 階段 3：ES 相容性靜態掃描與 Polyfill 防護 (ES Compat Scan)   │
│   • 執行 node app/tool/check_foliate_es_compat.js           │
│   • 於 foliate_epub_reader_view.dart 補齊 Polyfill (ES5 語法)│
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
│   • 更新 CONTEXT.md、AGENTS.md、紀錄 pinned commit SHA      │
└─────────────────────────────────────────────────────────────┘
```

### 階段 1：Upstream 差異分析與審查 (Upstream Diff Audit)
1. **確認上游目標 Commit**：
   在 `https://github.com/readest/foliate-js` 找出目標 commit SHA（例如 `<NEW_COMMIT_SHA>`）。
2. **產出 Diff 並逐項審查**：
   比對目前釘定版本（`dd71f2b`）與目標版本之間的差異：
   ```bash
   git diff dd71f2be356563c16a23272686189fcfb45d0b82 <NEW_COMMIT_SHA> -- paginator.js view.js
   ```
3. **查核檢核點（Checklist）**：
   - [ ] 是否修改了 `Paginator` 或 `View` 的公開方法簽章？
   - [ ] 是否新增或更動了 `relocate`、`create-overlayer` 等自訂事件的 Payload 欄位？
   - [ ] 是否修改了直排排版 (`vertical-rl`) 的分欄邏輯或軸向映射？
   - [ ] 是否引入了新的第三方依賴？

### 階段 2：資產下載與 Commit 釘定 (Asset Replacement)
1. 下載完整的 9 個 Vendored 檔案至 `app/android/app/src/main/assets/foliate/`：
   - `epub.js`
   - `epubcfi.js`
   - `fixed-layout.js`
   - `overlayer.js`
   - `paginator.js`
   - `progress.js`
   - `text-walker.js`
   - `view.js`
   - `vendor/zip.js`
2. **嚴格禁止覆蓋專案自建檔案**：
   - 保持 `index.html` 與 `main.js` 不被覆寫。

### 階段 3：ES 相容性靜態掃描與 Polyfill 防護 (ES Compatibility)
1. **執行靜態掃描腳本**：
   ```bash
   node app/tool/check_foliate_es_compat.js
   ```
2. **處理掃描結果**：
   - 若結束碼為 `0`：代表所有已知的危險 API 皆受防護。
   - 若結束碼為 `1`：查看腳本列出的未防護 API（例如使用了 `Promise.withResolvers`、`structuredClone`、`toSorted` 等）。
3. **補齊 Polyfill**：
   在 `app/lib/reader/foliate_epub_reader_view.dart` 的 `_esCompatPolyfillJs` 常數中加入 Polyfill。
   > [!IMPORTANT]
   > **Polyfill 編寫硬性規範**：
   > 1. 僅在 `if (!TargetAPI)` 缺席時才定義，不可覆寫瀏覽器原生實作。
   > 2. **嚴禁使用 ES2021+ 語法糖**（禁止使用 `??=`、`||=`、`&&=`、可選鏈 `?.`、標籤模板等），本體必須為 ES5/ES2020 相容語法，以確保能在 Chromium 83 上被正確解析。
4. **驗證與更新測試**：
   更新 `app/test/reader/foliate_epub_reader_view_test.dart` 中針對 `initialUserScripts` 的斷言，確保涵蓋新加入的 Polyfill 名稱。

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
flutter test test/reader/foliate_epub_reader_view_test.dart
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
- [ ] **繁中直排連翻測試**：使用直排 EPUB 連續翻頁 5 次，再反向翻頁 5 次，比對內容是否完全無縫銜接、無重複、無跳頁。
- [ ] **橫直排即時切換**：在閱讀中切換橫排 ↔ 直排，確認閱讀位置（Anchor）精準維持在當前段落。
- [ ] **字型與排版偏好調整**：調整字級、行距、字距、四向邊距，確認頁面 Reflow 正常且無崩潰。
- [ ] **劃線與備註**：選取文字建立螢光筆與底線，確認標記位置準確，點擊標記能彈出編輯選單。
- [ ] **FXL 漫畫雙頁跨頁**：開啟固定版面漫畫，確認 RTL 頁序與跨頁合併顯示正常。

### 階段 6：版本紀錄與文件更新 (Documentation & Archiving)
1. 在 `CONTEXT.md` 與 `AGENTS.md` 的 Gotchas / Architecture 區塊中更新當前釘定的 Commit SHA。
2. 若涉及架構調整，依專案規範撰寫 ADR（例如 `docs/adr/NNNN-bump-foliate-js-to-<commit>.md`）或於既有 ADR 補充記錄。
3. 提交 Git Commit，Commit Message 建議格式：
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
| **突發重大不可預期回歸** | 低 | 極高 | **快速回退機制**：Git revert 該次 Commit，一鍵退回至前一版穩定 commit（`dd71f2b`）。 |

---

## 7. 結論與維護建議 (Summary & Recommendations)

1. **落實自動化與標準化**：
   本次分析建立的標準 SOP 將上游同步流程結構化。未來當 GitHub 上 `readest/foliate-js`（包含 `paginator.js`）有重要修正時，工程團隊可直接依照本 SOP 快速、安全地完成升級評估與落地。
2. **維持「外部防護，內部純淨」的架構純度**：
   不直接 Hack 上游 Vendored 原始碼，將所有針對特定 E-Ink 裝置與專案特性的適配集中於 `_esCompatPolyfillJs`、`main.js` 與 Dart 原生層。這使得每次升級時的 Diff 比對與升級路徑最清晰、維護負擔最低。
