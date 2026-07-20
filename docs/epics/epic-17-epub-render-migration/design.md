# Epic 17 — EPUB 渲染引擎遷移評估：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-20 逐項確認產生，結合 `/domain-modeling` 對既有 ADR 0001（`docs/adr/0001-mobile-architecture.md`）的重新檢視。

## 問題陳述

`epic-7-interaction` Issue 9 的真機插樁 spike（`docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md`）診斷出直排／橫排翻頁跳頁問題，根因判定為 Readium reflowable Navigator（`EpubNavigatorFragment.goForward()`/`goBackward()`）內部、與呼叫時序相關的行為，非本專案 App 層缺陷，並決議退回（不強行修正）。

後續查證確認這**不是本專案獨有的整合問題**，而是 Readium 生態系已知、且official 已擱置的缺口：

- `readium/kotlin-toolkit` Issue #458「Chinese vertical EPUB documents cannot be read normally」——症狀（上下翻頁被強制跳頁）與我們自己的觀測高度吻合，回報已關閉但無可見修復紀錄。
- `readium/css` Issue #141——Readium CSS 官方**明確將直排（vertical writing mode）的分頁支援「Park」（擱置）**，理由是 CSS Multicolumn 規格層級限制；Thorium（Readium 官方旗艦 Reader）的因應方式是直排時完全停用 CSS 分頁、改用捲動偏移量偽裝分頁。

技術根因：Chrome 移除 CSS Regions 後，`writing-mode: vertical-rl` 與 CSS Multicolumn 分頁在 Chromium 引擎上沒有乾淨的搭配方案——這是瀏覽器引擎／CSS 規格層級的既有限制，Readium CSS 團隊選擇不投入解決。

ADR 0001 本身已預留重新檢視的伏筆（「若 Readium 的直排支援或 Decorator 在 `epic-0-skeleton` 或 `epic-2-vertical-core` 階段被證實不足，應重新檢視本 ADR」），雖然目前已是 epic-7（遠晚於該伏筆設定的時間點），但既然直排繁體中文排版是本產品的核心差異化（`docs/prd.md`），且問題根因已確認為 Readium 生態系的既有、擱置中的缺口，值得正式評估是否有替代方案。

`foliate-js`（尤其 `readest/foliate-js` fork）是候選方案，原因見下方決策紀錄。既有草案評估文件 `foliate-js-migration-feasibility-assessment.md`（本 epic 目錄下）已對此做過一輪分析，本次 Discovery 在此基礎上，透過查證 upstream 證據與真機／`chrome-devtools-mcp` 實測（見決策紀錄）修正並收斂為本文件的結論。

## 範圍界定

### 包含範圍

本次 Discovery **不**對「是否遷移 EPUB 渲染引擎」做最終 GO/NO-GO 決定。範圍僅止於：

- 記錄動機與已查證的證據（上方問題陳述、下方決策紀錄）。
- 定義一個**前置技術驗證 Spike** 的方法與判準——用最小、獨立、不影響現有 `app/` 的方式，直接在真機 Android WebView 上驗證 `readest/foliate-js` 是否能穩定處理直排分頁，作為 GO/NO-GO 的必要輸入。
- 定義 Spike 結果如何導向後續流程（GO → 進入 Architecting；NO-GO → 記錄理由並結束本 epic）。

### 明確排除

- **完整遷移架構設計**（Bridge Adapter、`WebViewAssetLoader`、JS Bridge 契約等）：留待 Spike 判定 GO 之後，於 Architecting 階段（`spec.md`）正式化。`foliate-js-migration-feasibility-assessment.md` 中的草案僅作為未來參考起點，本次不轉正為決策。
- **`johnfactotum/foliate-js`（原始版本）的驗證**：只驗證 `readest/foliate-js` fork（決策 #5）。
- **桌面瀏覽器驗證階段**：跳過，直接在真機 Android WebView 驗證（決策 #4）。
- **對現有 `app/` 程式碼的任何改動**：Spike 用完全獨立的 throwaway Android 專案，不建立、不修改 Flutter/`app/` 下任何檔案（決策 #6）。
- **除「直排分頁穩定性」以外的遷移可行性面向**（例如效能、字型渲染、Decorator/劃線相容性、離線 Google Play Services 環境下的行為）：本次 Spike 僅聚焦已知風險最高的單一面向；其餘面向若 Spike GO，留待 Architecting 階段逐項評估。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | 本次 Discovery 是否直接下 GO/NO-GO | **否**。目前證據（upstream 已知缺口 + `readest.com` 正式產品實測）方向正面但非壓倒性，需先完成一個前置技術驗證 Spike 才能下決定，比照本專案「先 Spike 降低風險再承諾」的一貫慣例（`epic-16-dual-page` Issue 1、`epic-7-interaction` Issue 1 皆為先例） |
| 2 | 替換核心動機 | 直排（`vertical-rl`）繁體中文分頁穩定性，對應 Readium 生態系已確認、擱置中的既有缺口（`readium/kotlin-toolkit#458`、`readium/css#141`），非本專案整合問題 |
| 3 | Readium 的技術本質 | 確認 Readium Kotlin（`EpubNavigatorFragment`）並非原生 Canvas 繪圖，而是封裝 Android WebView + Readium CSS（透過 `evaluateJavascript()`/`WebSettings.textZoom` 注入 CSS 變數）——與本專案自己 `EpubReaderView.kt` 既有的 `EpubPreferences`/`submitPreferences()`/`EpubSettingsResolver` 呼叫方式一致（`docs/adr/0003-epub-reader-writing-mode-contract.md`） |
| 4 | Spike 驗證平台 | 直接在真機 Android WebView 上驗證，不做桌面 Chrome 分階段篩選——雖然桌面驗證成本更低，但只有真機 WebView（對應本專案 `minSdk=24`／政策門檻 Android 11 API 30）的結果能真正代表部署環境，跳過分階段可以少一次「桌面過關但真機不過」的返工風險 |
| 5 | Spike 驗證的函式庫版本範圍 | 僅 `readest/foliate-js`（fork），不比對 `johnfactotum/foliate-js`（原始版）——雖然雙版本對照能更精確歸因（是 fork 自己修的、還是 foliate-js 底層策略本身就無此問題），但本次先聚焦「有希望解決問題的那個候選版本能否過關」，成本較低；若日後需要更精確歸因（例如評估長期釘住第三方 fork 的風險），可另立追加 Spike |
| 6 | Spike Harness 承載方式 | 完全獨立的最小 Android 專案（一個 Activity + 一個 `WebView`），不碰現有 `app/` 程式碼——WebView 是作業系統元件，其排版引擎行為不因外層是否包 Flutter `PlatformView` 而不同，獨立專案已具代表性，且完全不影響現有專案、驗證完可直接捨棄 |
| 7 | `design.md` 是否納入遷移架構草案 | 不納入。本文件僅聚焦 Spike 前置驗證本身；`foliate-js-migration-feasibility-assessment.md` 的 6 項共識決策與 4 階段路線圖保留在本 epic 目錄作為未來參考，但標註為未驗證草案，待 GO 確定後於 Architecting 階段重新逐項確認 |
| 8 | 已查證但本次未直接使用的證據 | 透過 `chrome-devtools-mcp` 直接操作 `readest.com` 正式產品網頁版，用 `epic-7-interaction` Issue 9 既有重現素材（`issue9_vertical_pagejump.epub`）實測直排連續翻頁 5 次觸發：內容未觀察到真正跳頁/丟頁，但觀察到章節總頁數動態重算、絕對頁碼標籤凍結等「計數器層級」不穩定現象。此結果不能直接當作真機 WebView 的替代驗證（`readest.com` 網頁版是桌面 Chromium，非 Android WebView），僅作為「foliate-js／Readest 並非零瑕疵、但至少目前守住了內容不跳頁的底線」的輔助佐證，記錄於下方風險段落 |

## Spike 驗證方法與判準

### Harness 設計

- 新建一個獨立、throwaway 的最小 Android 專案（單一 `Activity` + 單一 `android.webkit.WebView`），不屬於 `app/`。
- 打包 `readest/foliate-js` 的必要 JS/CSS assets 與一個最小 HTML 載入頁面，比照 `foliate-js-migration-feasibility-assessment.md` 3.1 節設想的靜態資源打包方式（`target: chrome83` 或對應本專案 `minSdk=24` 之相容目標，實際版本於實作時依 `readest/foliate-js` 建置需求確認）。釘定 `readest/foliate-js` 特定 Git commit SHA 打包，不追蹤 main 分支最新狀態，確保 Spike 結果可重複驗證。
- `foliate-js` 依賴動態 `import()`/`fetch()` 讀取解包後的 EPUB 內容（zip 內字型/圖片/XHTML/CSS），Android WebView 預設 `file://` 同源政策會擋下這類跨檔案存取；Harness 需配置 `WebViewAssetLoader` 或啟用 `setAllowFileAccessFromFileURLs(true)`（僅限本 throwaway spike 使用，不代表未來正式架構的做法），確保資源解包與渲染不被 WebView 安全機制阻斷。
- Harness 需能：載入本機 EPUB 檔案、切換為 `vertical-rl` 排版、提供「上一頁」/「下一頁」兩個可程式化觸發的操作（畫面按鈕或可由 `adb shell input tap` 觸發的固定座標元件即可，不需比照本專案正式熱區/音量鍵設計）。

### 重現素材

沿用 `app/test/fixtures/issue9_vertical_pagejump.epub`——與 `epic-7-interaction` Issue 9 spike 使用同一份素材，確保「同一本書、同一段內容」的結果可與既有 Readium 基準直接比較。

### 觸發方法與樣本數

比照 `epic-7-interaction` Issue 9 spike 的量測方法論（`spike-vertical-pagejump.md`）：

- 排版方向固定為 `vertical-rl`（直排），只驗證這個維度——這是 Readium 已知失效、也是本產品核心差異化的維度；橫排分頁本身沒有已知的 Chromium 規格層級限制，不在本次 Spike 範圍內。
- 選擇有正文內容的章節頁面（非封面/版權頁），避免書本邊界效應干擾判讀。
- 至少連續 3 次「下一頁」單次觸發 + 至少連續 3 次「上一頁」單次觸發，每次觸發間隔足夠時間讓畫面穩定（避免觸發排隊/覆蓋，模糊掉真正的單次觸發結果）。
- 每次觸發前後都記錄：(a) 可視內容是否連續——操作型定義為「翻頁前畫面最後一個字/詞，是否與翻頁後畫面第一個字/詞無縫銜接（無跳過/重複段落）」，透過畫面截圖或 DOM 文字比對驗證、(b) `foliate-js` 內部分頁進度指標（其 `Paginator`/`View` 暴露的頁碼或位置狀態，實作時確認具體 API）的前後值。

### 判準

| 結果分類 | 定義 | 對 GO/NO-GO 的影響 |
|---|---|---|
| **通過** | 所有測得的單次觸發，可視內容皆連續無跳過/重複，且內部分頁位置皆為預期的單步變化（無多步跳躍、無 0 步/被吃掉） | 視為 GO 訊號 |
| **計數器層級抖動（不算失敗）** | 內容連續、無跳過/重複，但輔助性的頁碼標籤/總頁數等**周邊計數器**出現不同步（例如總頁數重算、標籤暫時凍結）——比照本次於 `readest.com` 觀察到的現象 | 不視為失敗，但需記錄為已知殘留風險，供 Architecting 階段參考是否需要獨立處理 |
| **失敗** | 任何一次觸發觀察到可視內容真正跳過/重複段落，或內部分頁位置多步跳躍（如我們自己 Readium 案例的 +2/+3）、或觸發被吃掉（0 步變化） | 視為 NO-GO 訊號 |

## GO / NO-GO 決策路徑

- **GO**（Spike 判準「通過」或「計數器層級抖動」）：進入 Architecting 階段，正式撰寫 `spec.md`，屆時重新逐項確認 `foliate-js-migration-feasibility-assessment.md` 的 6 項共識決策與實作路線圖（不直接照抄轉正，需比對 Spike 實測結果與既有本專案架構重新驗算）。
- **NO-GO**（Spike 判準「失敗」）：記錄具體失敗證據於 `docs/epics/epic-17-epub-render-migration/reviews/`，`design.md` 補上「已評估並否決」的結論與理由，ADR 0001 維持現狀不變，Epic 標記完成並歸檔（不視為失敗的工作，而是一次有價值、排除掉一個選項的技術驗證）。未來重新檢視觸發條件：`readium/css#141` 若被重新開放/解決，或有其他證據顯示 Readium 直排分頁問題已被上游修復。

## 已知風險

- **長期依賴第三方 fork（非官方項目）**：`readest/foliate-js` 是社群 fork，非 Readium 或 `foliate-js` 官方維護的分支。即使 Spike 驗證通過，若未來遷移，需要在 Architecting 階段正式評估「長期釘住這個 fork」的維護風險（upstream 若停止更新、若與官方 `foliate-js` 分歧擴大等）。
- **Spike 僅驗證單一面向**：即使真機 WebView 驗證直排分頁穩定，不代表 `foliate-js-migration-feasibility-assessment.md` 提出的完整遷移範圍（Bridge Adapter 定位相容性、`WebViewAssetLoader` 串流、FXL 縮放、字數統計等）已被驗證可行——這些仍是 Architecting 階段需要重新評估的未知數。
- **桌面 `readest.com` 實測的參考價值有限**：已觀察到的「計數器層級抖動」現象只能證明 Readest 桌面 Chromium 版本存在類似但較輕微的不穩定性，不能直接外推到 Android WebView（版本與設定可能不同）——這正是為何本次 Discovery 決議 Spike 必須在真機 Android WebView 上做（決策 #4），不能以桌面測試結果取代。
- **WebView provider 版本落差**：本專案最低支援 Android 11（API 30，政策門檻），實際 `minSdk=24`；不同機型的系統 WebView provider 版本可能落後桌面 Chrome 甚多，Spike 應盡量在接近政策門檻的裝置/WebView 版本上驗證，而非只用開發用的最新裝置（沿用 Issue 9 spike 使用的測試裝置：3CEF42ECD491687，Android 15／API 35——嚴格來說仍偏新，此風險應在 Spike 執行時一併記錄裝置的實際 WebView 版本）。
- **硬體加速對渲染品質的潛在影響（未在本次 Spike 驗證）**：CSS Multicolumn 搭配 `vertical-rl` 排版在 Android WebView 硬體加速（`LAYER_TYPE_HARDWARE`）與軟體繪製（`LAYER_TYPE_SOFTWARE`）下，可能有不同程度的閃爍/重繪/捲動卡頓表現；本次 Spike 判準只涵蓋「內容是否跳頁/重複」這一個維度（見決策紀錄 #1、範圍外段落），不含渲染流暢度對照，故不預期本次 Spike 觸發矩陣涵蓋此面向。若 Spike GO，此項應列入 Architecting 階段的評估項目。

## 範圍外 (Out of Scope)

- 完整遷移路線圖與架構決策（Bridge Adapter、`WebViewAssetLoader`、JS Bridge 契約、字數統計/FXL 縮放搬遷至 JS 層等）——見 `foliate-js-migration-feasibility-assessment.md`，本次 Discovery 不轉正，待 GO 確定後於 Architecting 階段重新確認。
- `johnfactotum/foliate-js`（原始版本）與 `readest/foliate-js`（fork）的雙版本對照驗證——本次僅測 fork（決策 #5）。
- 桌面瀏覽器驗證——跳過（決策 #4）。
- 對現有 `app/` 程式碼的任何改動——Spike 為完全獨立專案（決策 #6）。
- 效能、字型渲染、Decorator/劃線相容性、離線環境行為等其餘遷移可行性面向——留待 Architecting 階段（若 GO）。
