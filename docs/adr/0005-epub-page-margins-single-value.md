# ADR 0005：EPUB 頁面邊距採用單一數值，暫不支援獨立四邊控制

## 狀態

已採納

## 背景

FR-10 字面要求「獨立控制之上下左右邊距 (滑桿)」，即上/下/左/右四個方向各自獨立可調。反編譯 `readium-navigator:3.3.0` 的 `EpubPreferences`／`EpubSettings`／`EpubDefaults`（`javap -p` 直接讀取 class 檔案確認）發現：Readium 原生只提供 `pageMargins: Double?` 這一個純量欄位，整個 class 沒有任何 marginTop/marginBottom/marginLeft/marginRight 之類的獨立欄位。要真正做到四邊獨立，勢必得繞過 `EpubPreferences`，改為自行注入/覆寫 CSS（`margin-top/right/bottom/left` 各自宣告），或在原生 `AndroidView` 容器層級疊加獨立的 padding——兩者都是明顯更大的工程量與風險，且後者是否可行仍需要實機/CSS 層級交叉驗證（目前尚未驗證 `pageMargins` 實際對應的 CSS 變數語意）。

## 決策

Epic 3 的邊距設定改為單一滑桿（＋微調按鈕），直接對應 Readium 原生的 `EpubPreferences.pageMargins`，四邊同步等值變動，不做獨立四邊控制。

## 曾考慮的替代方案

- **自訂 CSS 注入四邊獨立邊距**：技術上可行但工作量與風險明顯較大，需要先掌握 Readium 渲染管線目前完全沒動過的樣式覆寫層；本次不採用。
- **原生容器層級疊加左右 padding、Readium 負責上下邊距**：理論上折衷可行，但目前不確定 `pageMargins` 實際在畫面上對應的語意（是否真的只影響垂直方向），貿然假設有落空風險；本次不採用，留待未來需要時再驗證。

## 後果

- 使用者無法個別調整「只改上邊距、不動下邊距」這類精細控制，是相對於 PRD FR-10 字面要求的已知、刻意的降規格。
- 若未來要補齊四邊獨立控制，建議比照 `epic-2-vertical-core` Issue 3 對 FR-32 覆寫方案的評估方法（先靜態解析 ReadiumCSS 變數語意，再實機交叉驗證），評估自訂 CSS 注入或原生容器 padding 兩條路線何者可行，另立後續 issue 處理，不阻塞本 epic 其餘工作。
