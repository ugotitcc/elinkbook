# Epic 6 — 註記與知識管理：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-16 逐項確認產生。

## 問題陳述

FR-13/14/15/16/25 要求跨 EPUB／PDF 的書籤管理與導覽、劃線與備註（各自獨立的知識管理物件）、統一的劃線/備註側邊欄清單，以及 Markdown 導出。`prototype/index.html` 已有對應的視覺骨架（浮動選取工具列、備註編輯 Dialog、Markdown 導出按鈕），但其「書籤與劃線合併成同一個清單分頁」的做法與 PRD FR-14／FR-25 分列兩份清單的敘述互相矛盾，本次 Discovery 已裁定以 PRD 為準（見決策 #1）。

## 範圍界定

### 包含範圍

- **書籤管理與導覽**（FR-13/14）：EPUB／PDF／FXL 皆支援，每頁/每位置一筆、toggle 語意新增移除，具名可重新命名，清單依書中位置排序，點選 200ms 內跳轉，單筆刪除與批次「刪除該書所有書籤」（需確認對話框）。
- **劃線與備註**（FR-15）：僅流式 EPUB 與 PDF（FXL 排除，見決策 #7）。劃線提供「螢光筆」（黃/粉/藍三色底色填滿）與「底線」（固定單色波浪底線）兩種樣式；備註為獨立物件、可脫離劃線單獨存在；純備註有固定樣式的畫面指示。單筆刪除（劃線+備註一併刪除）、批次「刪除該書所有劃線」／「刪除該書所有備註」各自獨立（皆需確認對話框）。
- **統一劃線/備註側邊欄清單**（FR-25）：依書中位置排序，同一選取範圍的劃線+備註合併顯示成一筆。
- **單一「筆記」入口**：AppBar 新增一顆 📚 按鈕（FXL 則於懸浮控制按鈕群組新增對應的 📚 按鈕，見決策 #8，審查修正），開啟帶「🔖 書籤」／「✏️ 劃線與備註」兩分頁籤的 Bottom Sheet，兩分頁底下資料完全獨立。
- **Markdown 導出**（FR-16）：範圍固定為「目前這一本書」，內容依序含書籤清單、劃線與備註清單；存成實體 `.md` 檔並透過 Android 系統分享（Share Intent）分享出去（非原型的「純文字 Dialog 供複製」）。

### 明確排除

- **TXT 定位（字元偏移量）**——比照 `epic-5-toc-pagination` FR-12 的既有處理原則，暫緩至 `epic-11-txt-engine` 完成後才補；本 epic 初版範圍僅涵蓋 EPUB／PDF（書籤功能，見上）。
- **固定版面（FXL）的劃線與備註**——Readium 對 FXL 頁面無可選取的文字層，技術上無法比照流式 EPUB 的原生選字手勢實作；FXL 的書籤功能不在此列排除範圍內（見決策 #7）。
- **劃線事後改色/改樣式**——建立當下即定案，改色需求走「刪除重畫」（見決策 #11）。
- **跨書籍批次 Markdown 導出**——PRD 未提及跨書籍匯出，範圍固定為單本書。
- **雲端同步與衝突偵測**——`epic-8-sync` 職責，本 epic 僅在本機資料庫建立書籤/劃線/備註的基礎資料模型供其後續擴充。
- **劃線/備註在同一選取範圍上的重疊管理**（例如同一段文字被劃線兩次）——PRD 未明確定義，暫不特別處理，留待真機測試發現實際問題時再評估。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | 書籤清單 vs 劃線/備註側邊欄的關係 | 兩份**完全獨立**的資料清單（以 PRD FR-14／FR-25 為準），`prototype/index.html` 的合併分頁視為尚未同步 PRD 修訂的舊版本，本次設計不沿用其資料層合併做法，但沿用其「Bottom Sheet + 分頁籤」外殼視覺骨架（見決策 #6） |
| 2 | 純備註（無劃線）的畫面指示 | 固定樣式，不佔用劃線的顏色語意——**EPUB**：Readium Decorator 疊加淡灰底＋行內小圖示；**PDF**：淡灰色半透明矩形＋右上角 📌 圖示釘標，可點擊開啟備註內容 |
| 3 | PDF 劃線的框選觸發方式 | **長按頁面直接進入拖曳框選手勢**（非比照 `epic-4-pdf-enhance` 手動裁切「先按按鈕進入獨立模式」的既有模式），沿用 `CropOverlayView.kt` 的矩形繪製元件本體，但觸發時機改為長按直接開始；放開後跳出與 EPUB 相同的浮動工具列（顏色/底線/備註）。已查證 `PdfReaderView.kt` 目前無任何既有長按手勢綁定，不衝突。理由：讓 EPUB／PDF 兩邊的「長按開始標記」心智模型一致，使用者不需額外學習「先進入劃線模式」這個步驟 |
| 4 | 書籤新增語意 | 維持 `prototype/index.html` 既有的「每頁一個、toggle 開關」語意（非允許同頁重複新增），🔖 按鈕維持二態顯示；書籤仍是具名物件，預設名稱＝目前章節名稱（EPUB，沿用 `epic-5-toc-pagination` 既有的 `TocNavigator` 目前章節判定邏輯）或「第 N 頁」（PDF），使用者可於書籤清單裡個別重新命名 |
| 5 | 劃線樣式與顏色的關係 | 兩條獨立樣式選項：**螢光筆**（背景底色填滿，黃/粉/藍三色可選）與**底線**（波浪底線，固定使用當前主題 `primary` 色，不提供顏色選擇）。維持 `prototype/index.html` 既有 CSS 樣式現況，「劃線支援多種顏色」（PRD FR-15 字面用語）指的是螢光筆這個子類型的顏色可選項，非額外再開一條給底線用的顏色軸線 |
| 6 | 書籤/劃線/備註清單的入口 UI | AppBar 新增單一「📚 筆記」入口按鈕（不比照直接新增兩顆獨立按鈕，避免 AppBar 過度擁擠），開啟帶「🔖 書籤」／「✏️ 劃線與備註」兩分頁籤的 Bottom Sheet，沿用 `prototype/index.html` 已畫好的視覺骨架，但兩分頁底下的資料層完全獨立（見決策 #1）。點擊清單項目跳轉至書中對應位置後關閉 Bottom Sheet |
| 7 | FXL（固定版面）適用範圍 | **劃線／備註完全排除**——Readium 對 FXL 無可選取文字層，比照 `epic-5-toc-pagination`（頁首/頁尾）的既有先例整體排除。**書籤支援**——書籤只需一個頁碼位置，技術上可行，PRD/原型雖未明確提及 FXL 書籤但無理由排除 |
| 8 | FXL 書籤入口（**審查修正**：原版本僅新增書籤 toggle 按鈕，遺漏開啟 Bottom Sheet 的入口，導致使用者新增書籤後無法查看/改名/刪除/導覽，見 `tmp/epic-6/reviews/design_review.md` 1.1） | FXL 不使用 AppBar（`_isFixedLayout` 為 `true` 時整個 Scaffold AppBar 為 `null`），需在既有懸浮按鈕群組（左上返回鍵、右上設定鍵，`epic-16-dual-page` Issue 9 建立）之外，**新增兩顆**懸浮按鈕（皆為 `Positioned` + 半透明圓形按鈕樣式，跟隨相同的三欄熱區收合顯示/隱藏邏輯）：(a) 🔖 書籤 toggle 按鈕，快速新增/移除目前頁書籤（維持原設計，二態顯示）；(b) 📚 筆記按鈕，開啟與非 FXL 相同的 Bottom Sheet——「🔖 書籤」分頁功能完整（清單、重新命名、跳轉、刪除），「✏️ 劃線與備註」分頁顯示空狀態且不可互動（因 FXL 不支援此功能，見決策 #7） |
| 9 | Markdown 導出範圍與呈現方式 | 範圍固定為「目前這一本書」（非跨書籍批次），沿用 `prototype/index.html` `exportMarkdown()` 已定義的格式骨架（依序含「🔖 書籤清單」「✏️ 劃線與個人備註」兩大段落）；**呈現方式改為存成實體 `.md` 檔案並透過 Android 系統分享（Share Intent）分享出去**，取代原型的「純文字 Dialog 供使用者自行複製」做法。**儲存路徑與套件（審查修正，見 `tmp/epic-6/reviews/design_review.md` 1.5）**：寫入 App 私有暫存目錄（`path_provider` 的 `getTemporaryDirectory()`，本專案既有依賴，不需申請任何外部儲存權限），透過 `share_plus` 套件的 `Share.shareXFiles`（底層以 `FileProvider` 授予接收端 App 臨時讀取權限）分享，與 Backlog 中的 `epic-15-storage-permission` 完全解耦 |
| 10 | 批次刪除確認對話框樣式 | 標準原生 `AlertDialog`（標題顯示動作＋筆數，「取消」／警示色「刪除」兩個按鈕），書籤／劃線／備註三種批次刪除操作皆共用同一套元件與樣式，不另外客製化視覺 |
| 11 | 劃線事後編輯 | **不支援**改色/改樣式——建立當下即定案，需要改色時走「刪除這一筆重新劃一次」；備註因屬自由輸入內容、寫錯機率較高，維持原型既有的「編輯備註文字」功能 |
| 12 | 側邊欄清單排序 | 依「書中位置順序」排序（EPUB 用 `progression` 比例、PDF 用頁碼），非依建立時間——訴求為導覽輔助工具，位置順序比時間順序更符合「找書裡某處做過什麼記號」的查找情境。書籤清單同樣邏輯 |
| 13 | 同範圍劃線+備註的刪除顆粒度 | 單筆項目刪除為「整筆一起刪」（劃線+備註一併消失），不提供「只刪其中一個」的操作，維持原型既有的「編輯備註文字」／「刪除此劃線與備註」二選項設計。批次「刪除全部劃線」／「刪除全部備註」各自獨立、互不影響對方——若某筆原為「劃線+備註」合併存在，批次刪除劃線只會清除劃線本身，該筆備註若仍有內容會退化成「純備註」項目（套用決策 #2 的純備註畫面指示）繼續留在清單裡 |
| 14 | `highlights`／`notes` 的資料表關聯（**審查修正**，原留待 Architecting 階段的開放問題，見 `tmp/epic-6/reviews/design_review.md` 1.2） | `notes` 表新增可為空的 `highlight_id` 欄位，`REFERENCES highlights(id) ON DELETE SET NULL`——比照本專案既有 `book_reader_prefs.book_id REFERENCES books(id) ON DELETE CASCADE` 的 FK 慣例。建立「劃線+備註」時先建立 `highlight` 再建立 `note` 並指向其 `id`；純備註則 `highlight_id` 自始為 `null`。批次刪除劃線時 SQLite 自動把對應 `notes.highlight_id` 設為 `null`，UI 查詢時只需判斷 `highlight_id IS NULL` 即可決定是否套用「純備註」畫面指示（決策 #2），不需要額外的應用層退化判斷邏輯，也不依賴 CFI/座標字串模糊比對 |
| 15 | PDF 劃線框選中若使用者縮放/平移，如何處理 | **直接取消目前選取狀態並收起浮動工具列**，不嘗試即時重算選取矩形座標——縮放/平移狀態下持續追蹤並校正框選矩形的相對位置複雜度高、且是低頻操作組合（框選中途縮放不是常見使用情境），取消重來的使用者成本很低。座標本身以相對於目前 View 寬高的百分比值（而非絕對像素）由原生端透過 method channel 回傳給 Dart 端，Dart 端用 `Overlay` 將浮動工具列定位於選取矩形上方 |

## 使用者流程（概要）

### EPUB（流式）／PDF（共通）

1. 使用者長按（PDF）或原生選字（EPUB）選取一段內容，浮現含顏色（螢光筆黃/粉/藍）、底線、備註按鈕的浮動工具列。
2. 點選任一顏色或底線 → 立即建立劃線；點選「備註」→ 開啟備註編輯 Dialog，輸入文字後儲存 → 建立備註（若同時已選色/底線，備註與劃線共存於同一筆記錄；若未選色/底線，純備註以固定灰底+圖示樣式呈現）。
3. 點擊既有劃線/備註 → 開啟編輯 Dialog（「編輯備註文字」／「刪除此劃線與備註」）。
4. 使用者點擊 AppBar「📚 筆記」按鈕 → 開啟 Bottom Sheet，切至「✏️ 劃線與備註」分頁 → 清單依書中位置順序列出所有劃線/備註 → 點選任一筆 200ms 內跳轉至對應位置並關閉 Bottom Sheet。
5. 使用者點擊 🔖 書籤按鈕（EPUB/PDF 於 AppBar 內，或沿用既有版面設定按鈕群邏輯放置）→ toggle 新增/移除目前頁/位置的書籤；切至「🔖 書籤」分頁可重新命名或刪除單筆書籤。
6. 使用者於 Bottom Sheet 點擊「導出為 Markdown」→ 產生含書籤清單+劃線與備註清單的 `.md` 檔案 → 觸發 Android 系統分享。

### FXL（固定版面，僅書籤）

1. 使用者開啟一本 FXL（漫畫），畫面出現既有懸浮返回鍵／設定鍵，新增兩顆懸浮按鈕：🔖 書籤 toggle、📚 筆記。
2. 點擊 🔖 書籤按鈕 → toggle 新增/移除目前頁的書籤（無章節名稱概念，預設命名為「第 N 頁」）。
3. 點擊 📚 筆記按鈕 → 開啟 Bottom Sheet，「書籤」分頁可查看清單、重新命名、跳轉、刪除；「劃線與備註」分頁顯示空狀態、不可互動（FXL 不支援此功能）。

## 新增的資料模型（草案，細節留待 Architecting 階段 `spec.md` 確認）

預期新增三張與 `books` 表以 `book_id` 外鍵關聯的資料表（沿用既有 `book_reader_prefs` 表的關聯模式）：

| 資料表（暫定） | 用途 | 定位精度 |
|---|---|---|
| `bookmarks` | 書籤：具名的單一位置記錄 | 同閱讀進度精度（EPUB：CFI；PDF：頁碼） |
| `highlights` | 劃線：樣式（螢光筆/底線）＋顏色＋選取範圍 | 高於書籤（EPUB：CFI 範圍；PDF：頁碼＋頁內矩形座標） |
| `notes` | 備註：自由文字內容＋選取範圍＋可為空的 `highlight_id`（見決策 #14） | 同劃線 |

**`highlights`／`notes` 的關聯**（審查修正後定案，見決策 #14）：`notes.highlight_id` 為可空欄位，`REFERENCES highlights(id) ON DELETE SET NULL`；`highlight_id IS NULL` 即代表「純備註」（純備註畫面指示，見決策 #2），無論是自始未建立劃線、或劃線被批次刪除後退化而來，UI 判斷邏輯一致。兩者選取範圍的欄位結構（EPUB Locator JSON／PDF 頁碼+矩形座標）留待 Architecting 階段確認是否共用同一組 schema 定義，或各自獨立宣告等價欄位。

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `EpubReaderView.kt` | 擴充 | 新增劃線/備註的 Readium Decorator 疊加（螢光筆/底線/純備註三種樣式）、選取事件回報 method channel（浮出浮動工具列所需的選取範圍資訊） |
| `EpubReaderView.dart` | 擴充 | 新增劃線/備註建立/刪除的 method channel 呼叫、Decorator 資料接收 |
| `PdfReaderView.kt` | 擴充 | 新增長按觸發框選手勢（沿用/延伸 `CropOverlayView.kt`）、劃線/備註矩形疊加渲染於 Bitmap 之上；**新增 `refreshAnnotations()` method channel 指令**（審查修正）——Dart 端完成劃線/備註的新增/編輯/刪除後主動呼叫，通知原生端重新讀取目前頁面的標記資料並重繪 Bitmap 快取，避免殘留或未顯示，比照既有濾鏡/裁切變動後需要原生重繪的既定架構模式 |
| `PdfReaderView.dart` | 擴充 | 新增框選事件回報（相對於 View 寬高的百分比座標，見決策 #15）、劃線/備註建立/刪除呼叫、`refreshAnnotations()` 呼叫 |
| `ReaderScreen` | 擴充 | 新增「📚 筆記」AppBar 按鈕（流式 EPUB/PDF）；FXL 新增 🔖 書籤 toggle ＋ 📚 筆記兩顆懸浮按鈕（審查修正，見決策 #8）；書籤 toggle 邏輯（沿用 `epic-5-toc-pagination` 的 `TocNavigator` 目前章節判定，供預設命名使用） |
| 新建 `NotesBottomSheet`（暫名，Dart widget） | 新建 | 帶「書籤」／「劃線與備註」分頁籤的 Bottom Sheet 外殼，沿用專案既有 Bottom Sheet 慣例；FXL 情境下「劃線與備註」分頁顯示空狀態 |
| 新建書籤/劃線/備註 repository 層 | 新建 | 比照既有 `BookReaderPrefsRepository`／`ReadingPositionRepository` 的 SQLite repository 模式；`notes` repository 需處理 `highlight_id` 可空外鍵（決策 #14） |
| `sqlite_library_repository.dart` | 擴充 | 新增 `bookmarks`／`highlights`／`notes` 三張表的累加式 schema migration（版本遞增，`if (oldVersion < N)` 慣例），`notes` 表含 `highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL`（決策 #14） |
| Markdown 導出模組 | 新建 | 產生 `.md` 檔案內容（複用 `prototype/index.html` `exportMarkdown()` 格式骨架）＋寫入 App 私有暫存目錄（`path_provider` 的 `getTemporaryDirectory()`，本專案既有依賴，見決策 #9 審查修正）＋透過 `share_plus` 套件 `Share.shareXFiles` 觸發 Android 系統分享 |

## 已知風險 / 待 Architecting 階段確認的技術細節

- **PDF 長按框選手勢與既有互動的優先權**：已查證 `PdfReaderView.kt` 目前無既有長按手勢綁定（不衝突），但與既有九宮格熱區（單擊翻頁）、雙頁模式下的縮放/平移手勢是否會有手勢競技場（gesture arena）搶奪問題，需在 Architecting／實作階段以真機驗證；決策 #15 已定案「框選中縮放/平移即取消選取」以降低此風險的影響範圍，但長按本身觸發的時間點與既有手勢的優先權仍需真機驗證。
- **EPUB 劃線在直排/橫排切換間的視覺一致性**（PRD FR-15 明確要求，**審查補充**，見 `tmp/epic-6/reviews/design_review.md` 2.1）：依賴 Readium Decorator API 以 Locator（內容錨定而非像素錨定）呈現劃線，理論上應能隨 WebView CSS `writing-mode` 重排自動保持正確位置；但「底線」樣式（決策 #5）在直排下不能沿用橫排的 `border-bottom`（語意上會變成字元左右側而非期望的方向），需改用邏輯方向屬性（例如 `border-inline-end`）或依 `writing-mode` 動態切換實體方向屬性，並在真機測試階段準備專門的直排 EPUB 測試檔驗證渲染正確性，非僅憑理論推斷。
- **`highlights`／`notes` 選取範圍的 schema 共用程度**：關聯鍵本身已於決策 #14 定案（`notes.highlight_id` 可空外鍵 + `ON DELETE SET NULL`），但兩者選取範圍定位資訊（EPUB Locator JSON／PDF 頁碼+矩形座標）的欄位結構是否共用同一組 schema 定義、或各自獨立宣告等價欄位，留待 Architecting 階段確認。

## 範圍外 (Out of Scope)

- **TXT 定位（字元偏移量）**——留待 `epic-11-txt-engine`。
- **FXL 劃線與備註**（決策 #7）——Readium 對 FXL 無可選取文字層。
- **劃線事後改色/改樣式**（決策 #11）——僅支援刪除重畫。
- **跨書籍批次 Markdown 導出**——範圍固定為單本書。
- **雲端同步與衝突偵測**——`epic-8-sync` 職責。
- **劃線/備註在同一選取範圍上的重疊管理**——PRD 未明確定義，暫不處理。

## 審查修正紀錄（`tmp/epic-6/reviews/design_review.md`）

- **Critical（確認屬實，已修正）**：決策 #8 原版本僅為 FXL 新增書籤 toggle 按鈕，未提供任何開啟 Bottom Sheet 的入口，導致使用者無法查看/改名/刪除/導覽已建立的書籤。已改為 FXL 新增兩顆懸浮按鈕（🔖 書籤 toggle ＋ 📚 筆記入口），並同步更新「使用者流程」「架構影響摘要」對應段落。
- **Important（確認屬實，已採納）**：`highlights`／`notes` 的關聯原留待 Architecting 階段的開放問題，已於 Discovery 階段提前定案（新增決策 #14）：`notes.highlight_id` 可空外鍵 + `ON DELETE SET NULL`，比照本專案既有 `book_reader_prefs.book_id` 的 FK 慣例，避免依賴 CFI/座標字串模糊比對判斷「純備註」退化狀態。
- **Important（確認屬實，已補上）**：PDF 劃線的座標傳遞協定與浮動工具列定位機制原設計文件未提及，已新增決策 #15，定案「框選中縮放/平移即取消選取」的使用者可感知行為，座標傳遞的精確 wire protocol 留待 spec.md。
- **Minor（確認屬實，已補上）**：`PdfReaderView.kt` 新增/編輯/刪除標記後，原生端點陣圖渲染快取需要主動通知重繪，已於「架構影響摘要」補上 `refreshAnnotations()` method channel 指令。
- **Minor（確認屬實，已採納）**：Markdown 導出的檔案儲存路徑與權限疑慮已解決——寫入 App 私有暫存目錄（`path_provider` 既有依賴）不需申請額外儲存權限，透過 `share_plus` 分享，與 `epic-15-storage-permission` 解耦，已更新決策 #9 與已知風險章節。
- **風險提示（技術上正確，已補充措辭）**：EPUB 直排模式下「底線」樣式若沿用橫排的 `border-bottom` 語意會出錯，已在已知風險章節補充具體技術細節（需改用邏輯方向 CSS 屬性），供 Architecting／實作階段參考。
