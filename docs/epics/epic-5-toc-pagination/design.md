# Epic 5 — 目錄與頁碼：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-14 逐項確認產生。

## 問題陳述

FR-07/08/22/23/40 要求跨格式的目錄導航、頁碼顯示與跳轉、頁首/頁尾顯示切換。FR-12（TXT 自動章節解析）已於「單機閱讀優先開發順序」決議（見 `docs/epics.md` epic-5 列）中暫緩至 `epic-11-txt-engine` 完成後才補，本文件不涵蓋。

## 範圍界定

### 包含範圍

- **EPUB（流式）目錄提取與跳轉**（FR-07/08）。
- **EPUB 模擬分頁**（FR-22）與**頁碼跳轉**（FR-23）。
- **PDF 頁碼顯示**（FR-22，沿用既有 `currentPageIndex`/`totalPages` 基礎設施）與**頁碼跳轉**（FR-23）。
- **流式 EPUB + PDF 的頁首/頁尾**（FR-40）。
- **本機（非雲端）閱讀位置記憶**——Discovery 階段新增範圍，非 PRD 逐字要求，但判定為顯示頁碼/跳頁功能的必要前提基礎設施（見決策 #12）。

### 明確排除

- **PDF 目錄提取**——Android `PdfRenderer` API 原生無法讀取 PDF 內建大綱/書籤（`/Outlines` 字典），見決策 #1。
- **FR-12（TXT 自動章節解析）**——留待 `epic-11-txt-engine`。
- **固定版面（FXL 漫畫）的頁首/頁尾**——與 `epic-16-dual-page` 已建立的浮動控制系統衝突，見決策 #3。
- **雲端進度同步與衝突偵測**——`epic-8-sync` 職責，本 epic 僅建立本機基礎設施供其後續擴充。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | PDF 目錄來源 | 不做。反解析確認 Android `PdfRenderer` API 原生無法讀取 PDF `/Outlines` 字典，這是 API 本身的限制，非程式碼補寫即可解決；PDF 目錄留待後續工單，需另外評估自訂 `/Outlines` 解析器（純 Kotlin，工作量大但無外部依賴）或引入第三方 PDF 解析庫（如 pdfbox-android，成熟但與本專案一貫的原生 API 選型風格相悖）二擇一 |
| 2 | PDF 閱讀時的目錄入口 | 直接不顯示目錄按鈕，避免使用者點進空狀態或無效入口 |
| 3 | FR-40 適用範圍 | 僅流式 EPUB 與 PDF，**不適用**固定版面（漫畫，FXL）——`epic-16-dual-page` Issue 9 已建立左上返回鍵／右上設定鍵／三欄點擊熱區的浮動控制系統，螢幕上方已被佔用；FXL 漫畫通常也沒有有意義的章節結構（多半是一連串圖片頁），頁首「顯示章節名稱」對其意義不大 |
| 4 | FR-12／PDF 目錄延後 | FR-12（TXT）暫緩至 `epic-11-txt-engine` 完成後；PDF 目錄延後至後續工單（見決策 #1），本 epic 僅涵蓋 EPUB 目錄 |
| 5 | EPUB 模擬分頁方法 | 字元／字數區間啟鞍法（比照既有 FR-12／TXT 分頁換算的既有慣例）：原生（Kotlin）層一次性回傳全書字元數，Dart 層依當前字體大小／行距／段落間距／邊距估算「每螢可容納字元數」，換算出估計總頁數；`Locator.totalProgression`（Readium 提供的全書比例）換算成目前頁碼。採用原因：Readium 本身未提供螢幕／字體感知的分頁 API，`Publication.positions()` 僅依固定 1024 bytes 切分、與實際渲染排版無關 |
| 6 | 估算計算發生位置 | Dart 層——`ResolvedPreferences` 已持有全部版面參數，原生端只需新增一個一次性回傳「全書字元數」的 method channel，不需每次版面變動都跨 channel 往返 |
| 7 | 估計頁數重算時機 | 版面設定（字體大小／行距／段落間距／邊距／排版方向）任一變動即立即重新計算，確保估算值與實際排版狀態保持一致 |
| 8 | 頁首與現有 AppBar 整合方式 | 顯示頁首時**取代**現有 AppBar——標題區改顯示「章節名稱」（可點擊展開目錄，取代目前寫死的「閱讀器」文字），設定齒輪仍保留在 `actions`；關閉頁首時回到現行純標題 AppBar |
| 9 | 頁尾適用範圍 | 流式 EPUB 與 PDF 皆適用——PDF 已有精確 `currentPageIndex`/`totalPages`（不需估算），流式 EPUB 使用決策 #5 的估算值 |
| 10 | 目錄層級呈現 | 可展開／收起的層級樹狀清單，以 Bottom Sheet 呈現（比照專案既有 `PdfSettingsSheet`／`ReaderSettingsSheet`／`FxlSettingsSheet` 慣例），完整保留 Readium `Publication.tableOfContents` 提供的巢狀結構；當前章節所屬層級預設展開，其餘收起 |
| 11 | 目錄項目是否顯示頁碼 | 顯示——每條目錄項目旁標示估算頁碼，符合 FR-07 字面要求「顯示標題與對應頁碼」，沿用決策 #5 的估算法（把每個 `Link.href` 對應到全書位置後換算頁碼） |
| 12 | 本機位置記憶範圍 | 納入本 epic：本機（不需帳號／不需網路）記住使用者上次讀到哪，下次開書自動跳回去。與 `epic-8-sync` 的雲端同步刻意分開——雲端同步／衝突偵測（FR-19）留待該 epic 在本機基礎設施之上擴充 |
| 13 | 位置資料存放位置 | 新欄位於 `books` 表（`Book` model 平行擴充），與既有死欄位 `progress`（型別 `double`，恆為 `0`、程式碼註解明寫「回寫屬於 epic-8-sync」但實際上從未被寫入）一起活化。**不**併入 `BookReaderPrefs`——域模型考量：閱讀位置是系統持續追蹤的「閱讀狀態」，與 `BookReaderPrefs` 既有欄位代表的「使用者主動選擇的顯示設定」性質不同 |
| 14 | 位置寫入時機 | 離開閱讀畫面時寫庫（`ReaderScreen.dispose()`）+ App 進入背景時（`WidgetsBindingObserver` 生命週期）各寫一次。避免捲動翻頁模式下 `totalProgression` 連續變動造成頻繁寫庫，同時把「被系統強制結束時遺失本次進度」的風險降到最低（非零風險，見「已知風險」） |
| 15 | 頁碼跳轉 UI | 輸入框 + 滑桿並存，雙向同步——拖動滑桿即時更新輸入框顯示數字，輸入框確認後同步更新滑桿位置，任一方觸發最終跳頁動作 |

## 使用者流程（概要）

### EPUB（流式）

1. 使用者開啟一本流式 EPUB，畫面出現目錄入口。
2. 點擊目錄，開啟可展開／收起的層級樹狀 Bottom Sheet，每條項目顯示標題 + 估算頁碼，當前章節所屬層級預設展開並高亮。
3. 點選任一項目，須於 200ms 內跳轉至該章節起始位置（FR-08）。
4. 若「顯示頁首」開啟，AppBar 被取代為「章節名稱（可點擊展開目錄）」；若「顯示頁尾」開啟，畫面底部顯示「進度 xx% ｜ 第 N/M 頁」，N/M 為估算值，並提供輸入框+滑桿供快速跳頁。
5. 使用者離開閱讀畫面或 App 切到背景時，目前 `Locator` 自動寫入本機資料庫；下次開啟同一本書自動跳回該位置。

### PDF

1. 使用者開啟一本 PDF，畫面**不**出現目錄入口（PDF 無目錄支援，見決策 #1/#2）。
2. 若「顯示頁尾」開啟，畫面底部顯示「進度 xx% ｜ 第 N/M 頁」，N/M 為精確值（既有 `currentPageIndex`/`totalPages`），並提供輸入框+滑桿供快速跳頁；「顯示頁首」對 PDF 無實際作用（無內容可顯示，見決策 #4）。
3. 使用者離開閱讀畫面或 App 切到背景時，目前頁碼自動寫入本機資料庫；下次開啟同一本書自動跳回該頁。

## 新增的資料模型欄位

### `books` 表（`Book` model 平行擴充，非 `BookReaderPrefs`）

| 欄位 | 型別 | 語意 |
|------|------|------|
| `progress` | `double`（既有欄位，本 epic 活化） | 閱讀進度比例 0.0–1.0，開書／寫入位置時依當前位置回填 |
| `lastLocatorJson` | `String?`（新增，僅 EPUB 有值） | Readium `Locator.toJSON().toString()` 序列化字串，供 `fromJSON()` 還原 |
| `lastPageIndex` | `int?`（新增，僅 PDF 有值） | 對應既有 `PdfReaderView.currentPageIndex` 語意 |

### `BookReaderPrefs`

| 欄位 | 型別 | 語意 |
|------|------|------|
| `showHeader` | `bool?`（新增） | 是否顯示頁首，`null` = 預設顯示 |
| `showFooter` | `bool?`（新增） | 是否顯示頁尾，`null` = 預設顯示 |

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `EpubReaderView.kt` | 修正 + 擴充 | **移除死程式碼**：`PaginationListener.onPageChanged(pageIndex, totalPages, locator)` 覆寫方法反解析 Readium 3.3.0 全函式庫後確認從未被呼叫，需移除或替換為真正有效的機制；新增 `Publication.tableOfContents` 讀取＋序列化傳給 Dart；新增回傳全書字元數的 method channel（決策 #6）；`attachNavigator()` 現行硬編碼 `initialLocator = null`（第 651 行附近）改為接收外部傳入的起始 `Locator`（決策 #12） |
| `EpubReaderView.dart` | 擴充 | 新增 TOC 資料模型接收與解析、頁碼估算輸入（版面參數變動時觸發重算，決策 #7）、`initialLocator` 建構參數 |
| `PdfReaderView.kt` | 擴充 | `openBook()` 現行硬編碼 `currentPageIndex = 0`（第 438 行附近）改為接收外部傳入的起始頁碼（決策 #12） |
| `PdfReaderView.dart` | 擴充 | 新增 `initialPageIndex` 建構參數 |
| `ReaderScreen` | 擴充 | 新增 `WidgetsBindingObserver` 監聽生命週期（App 進入背景時寫入位置，決策 #14）；`dispose()` 寫入位置；頁首取代 AppBar 邏輯（決策 #8）；頁尾疊加層（決策 #9）；讀取／傳遞 `initialLocator`／`initialPageIndex` 給原生端 |
| `Book` model／`sqlite_library_repository.dart` | 擴充 | `progress` 欄位活化（新增真正的 `UPDATE` 邏輯，取代目前恆為 0 的死欄位）；新增 `lastLocatorJson`／`lastPageIndex` 欄位，SQLite schema migration |
| `BookReaderPrefs` | 擴充 | 新增 `showHeader`／`showFooter` 兩個 nullable 欄位 |
| 新建 `TocBottomSheet`（Dart widget） | 新建 | 層級樹狀目錄清單，比照專案既有 Bottom Sheet 慣例（`showModalBottomSheet`），每項顯示標題+估算頁碼 |
| 新建頁首／頁尾 widget | 新建 | 流式 EPUB／PDF 共用的頁首（取代 AppBar）與頁尾（顯示進度+頁碼+跳頁輸入框/滑桿雙向同步元件）元件 |

## 已知風險 / 待 Architecting 階段確認的技術細節

- **全書字元數的取得成本**：Readium `Publication.positions()` 依固定 1024 bytes 切分、與螢幕/字體無關，無法直接沿用；本設計需要另外走訪 `readingOrder` 逐一取得各 resource 內容長度加總，效能與時機待 Architecting 階段確認——是否可在背景執行緒一次性計算並快取，避免開書當下卡頓。
- **頁碼估算與 Readium 實際排版的落差**：估算頁碼僅供顯示與粗略跳轉參考，不保證與 Readium WebView 實際分頁結果逐頁精確一致（PRD FR-22 本身也只要求「模擬分頁」，非精確值）；需在真機測試中確認誤差是否在可接受範圍。
- **TOC 項目跳轉的 Locator 建構**：`Publication.tableOfContents` 的 `Link.href` 需要轉換成可供 `Navigator.go()` 使用的 `Locator`，需在 Architecting 階段確認 Readium 是否有便利 API（例如 `Publication.locatorFromLink()`）可直接取用，或需自行組裝。
- **本機位置寫入的失敗處理**：App 進入背景後，系統若在寫入完成前就把程序凍結/終止，仍有極小機率遺失最後一次進度。此為已知、可接受的殘留風險，不追求 100% 保證，比照專案既有「已知限制」誠實揭露慣例，不在本 epic 內另尋 100% 可靠的持久化機制（例如同步阻塞寫入）。

## 範圍外 (Out of Scope)

- **PDF 目錄提取**（決策 #1）——需要新的 PDF 解析能力，另立後續工單評估自訂解析器 vs. 第三方庫。
- **TXT 目錄／分頁**（FR-12）——留待 `epic-11-txt-engine`。
- **固定版面（FXL）頁首／頁尾**（決策 #3）——與 `epic-16-dual-page` 既有浮動控制系統衝突。
- **雲端進度同步與衝突偵測**——`epic-8-sync` 職責，本 epic 僅建立本機基礎設施供其擴充。
- **TOC 項目／頁碼估算的精確度保證**——僅為模擬/估算，非像素級精確（見「已知風險」）。
