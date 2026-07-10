# epic-3-fonts-layout 字型與版面設定 —— Design（Discovery 階段產出）

## 對應 PRD 需求

FR-09（字型自定：內建字型＋停用時退回預設）、FR-10（版面參數調節：字型大小/字重、行距、段落間距、獨立四邊邊距、翻頁模式、對齊、排版方向三態、螢幕方向、停用書本 CSS）、FR-31（主題外觀：深色/羊皮紙/預設，與 E-Ink 高對比並存）。

跨 Epic 依賴：FR-35（`epic-14-system-settings` 全域字型管理）、FR-37/FR-38（`epic-14-system-settings` 全域螢幕方向/翻頁模式預設）——`epic-14` 目前狀態為「⚪ 未開始」，且開發排期在 `epic-8` 之後、`epic-9` 之前，晚於本 epic，見「範圍與排除項目」的處理方式。

## 目標

把目前僅有橫直排/換頁模式兩顆獨立即時切換鈕（Issue 2、Issue 4 建立、皆為當次 session 即時切換、不持久化）的 `ReaderScreen`，擴充為一套完整、**持久化到單一書籍**的版面與字型偏好設定系統：新增 Bottom Sheet 版面設定面板（字型選擇/大小/字重、行距、段落間距、邊距、對齊、停用書本 CSS、排版方向/螢幕方向/翻頁模式三個雙態或多態覆寫），並補齊「持久化設定在開書當下真正套用到原生端」這個 Epic 2（ADR 0004）已預留但未解決的架構缺口。全域主題（深色/羊皮紙/預設）與 E-Ink 高對比模式，兩者皆為跨書籍一致的全域設定，一併於本 epic 實作。

## 範圍與排除項目

**本 epic 涵蓋：**
- 單書版面偏好設定的資料儲存（新表 `book_reader_prefs`）與解析邏輯
- `EpubReaderView`/`EpubReaderView.kt` 契約擴充：`openBook` 新增 `initialPreferences`，開書當下（`attachNavigator()` 成功後）立即套用已持久化的偏好設定，不再只依賴 `didUpdateWidget`
- FR-09：字型選擇（5 款內建字型，見下方「字型素材」）、字型大小、字重（含已知的模擬粗體限制，見「已知限制」）
- FR-10：行距、段落間距、邊距（單一數值，見 ADR 0005）、文字對齊、停用書本 CSS、排版方向三態覆寫（採用書籍排版/強制直排/強制橫排，含資料模型拆分）、翻頁模式覆寫（含全域/單書雙層解析）、螢幕方向覆寫（含全域/單書雙層解析＋真實 OS 層級鎖定）
- FR-31：主題（深色/羊皮紙/預設）、E-Ink 高對比模式（獨立疊加開關）
- 新版面設定 Bottom Sheet UI（比照 `prototype/index.html` 既有設計），整併並移除現有 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 兩顆獨立 AppBar 按鈕
- 僅處理**流式（reflowable）EPUB**；定樣式（fixed-layout）EPUB 時整個「⚙️版面」按鈕與 Bottom Sheet 皆不顯示，比照 Epic 2 對橫直排/換頁模式按鈕的既有處理原則

**明確排除，留給後續 Epic：**
- **TXT 格式的版面設定**——TXT 閱讀器本身尚未存在（`epic-11-txt-engine`），本 epic 的 `book_reader_prefs` схема刻意採格式無關設計（僅以 `book_id` 關聯），供 `epic-11` 未來直接複用，但實際 UI 串接與渲染僅限 EPUB
- **PDF**——無 reflow/版面概念，不適用
- **FR-09 的自訂字型上傳/管理/刪除**——移至 `epic-14-system-settings`（FR-35）；本 epic 僅實作「從目前可用字型清單中選擇」，清單來源本 epic 內固定為 5 款內建字型，日後 `epic-14` 上線後清單來源自然擴充為「內建 + 使用者已上傳」，不需要回頭修改本 epic 的選擇/儲存機制
- **FR-37/FR-38 全域預設值的正式設定畫面**——移至 `epic-14-system-settings`；本 epic 僅實作「單書覆寫值 `??` 全域預設值」的解析邏輯，全域預設值本身用 `shared_preferences` 存放沿用現有行為的初始值（螢幕方向＝自動旋轉、翻頁模式＝點擊翻頁），無 UI 可改，等 `epic-14` 在同一組 key 上補設定畫面
- **邊距的獨立四邊控制**——降規格為單一數值，見 ADR 0005；未來若要補齊，另立後續 issue
- 九宮格導航熱區在直排模式下的左右鏡像映射邏輯——屬 `epic-7-interaction`

## 架構異動：新增 `book_reader_prefs` 資料表

單書版面偏好設定不適合塞進既有 `books` 表（職責會變得臃腫），也不適合套用 `LibraryPreferences` 的 `shared_preferences` 單一鍵值慣例（那是給「全域單一值」設計的，不適合「每本書一組多欄位資料」）。

新增獨立 SQLite 表 `book_reader_prefs`，與 `books` 表以 `book_id` 為外鍵 1:1 關聯，所有欄位皆為 nullable：`null` 代表「未覆寫，使用預設值／回退至全域預設值」。表不存在對應書籍的列，等同全部欄位皆為 `null`。

排版方向覆寫額外拆成兩個概念（不可合併成一個欄位）：
- `autoDetectedWritingMode`：唯讀，來自 Readium `onLayoutResolved` 的自動偵測結果，`ReaderScreen` 內部狀態，不持久化（每次開書都重新偵測一次）
- `writingModeOverride`：三態、持久化進 `book_reader_prefs`（`null`＝採用書籍排版、`vertical`＝強制直排、`horizontal`＝強制橫排）

實際送給 `EpubReaderView` 的 `writingMode` 參數＝`writingModeOverride ?? autoDetectedWritingMode` 解析後的結果。

翻頁模式、螢幕方向覆寫則是「單書覆寫值 `??` 全域預設值」的雙層解析（全域預設值見下方「全域設定」一節），不需要「自動偵測」這層概念。

## 架構異動：`openBook` 契約擴充 `initialPreferences`

Epic 2（ADR 0004）已預留但未解決的缺口：目前 `EpubReaderView`/`EpubReaderView.kt` 的偏好設定同步完全依賴 `didUpdateWidget` 偵測「值改變」才呼叫原生端 setter；若 `ReaderScreen` 建構當下就把狀態初始化為已持久化的值，`didUpdateWidget` 不會在首次建構時觸發，持久化設定會停留在 Dart 端 UI 顯示，但從未真正送達原生端套用。

修法：擴充 `openBook` 契約為 `openBook(path, initialPreferences: Map<String, Any?>)`；原生端 `attachNavigator()` 成功、`Publication` 就緒後，直接用 `initialPreferences` 組出完整 `EpubPreferences` 呼叫一次 `submitPreferences()`，不等待任何後續的 `didUpdateWidget` 觸發。已生效的偏好設定（含此次初始化套用的）持續維護在原生端既有的 `currentPreferences` 欄位（Issue 4／ADR 0004 建立），後續使用者透過 Bottom Sheet 手動調整時，一樣走 `currentPreferences.plus()` 合併模式，不會互相覆蓋。

此契約擴充影響全部既有偏好維度（`verticalText`、`scroll`）與本 epic 新增的所有維度（`fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles`），需在 Architecting 階段（`spec.md`）補一份 ADR 記錄此決定（比照 ADR 0002／Epic 2 為契約擴充補 ADR 的先例）。

## 已驗證的技術基礎（Discovery 階段反編譯結果）

反編譯 `readium-navigator:3.3.0` 的 `EpubPreferences`／`EpubSettings`／`EpubDefaults`（`javap -p` 直接讀取 class 檔案）確認完整欄位清單：

`backgroundColor`、`columnCount`、`fontFamily: String?`、`fontSize: Double?`、`fontWeight: Double?`、`hyphens`、`imageFilter`、`language`、`letterSpacing`、`ligatures`、`lineHeight: Double?`、`pageMargins: Double?`（**單一數值，無四邊獨立欄位，見 ADR 0005**）、`paragraphIndent`、`paragraphSpacing: Double?`、`publisherStyles: Boolean?`（＝「停用書本 CSS」的 Readium 原生對應欄位）、`readingProgression`、`scroll`、`spread`、`textAlign: TextAlign?`（enum，實際列舉值待 Architecting 階段確認）、`textColor`、`textNormalization`、`theme`、`typeScale`、`verticalText`、`wordSpacing`。

FR-10 要求的行距、段落間距、字型大小/字重、對齊、停用書本 CSS 皆有原生欄位直接對應，技術風險低；`fontFamily` 亦有原生欄位，但需確認 Readium 如何接受自訂 `@font-face` 字型名稱注入（本 epic的 5 款字型皆為本地 asset，非系統字型），此項留待 Architecting 階段驗證。

## FR-09：字型

**字型素材**（已放置於 `app/assets/fonts/`，本次 Discovery 階段已核對來源與命名）：
- 思源黑體：`SourceHanSansTC-VF.ttf`（Adobe `source-han-sans`，Variable Font，僅 Regular 靜態切面）
- 思源宋體：`SourceHanSerifTC-VF.ttf`（Adobe `source-han-serif`，Variable Font，僅 Regular 靜態切面）
- 原俠正楷：`GuanKiapTsingKhai.ttf`（`tonyhuan/GuanKiapTsingKhai`，單一靜態字重）
- 台灣圓體：`TaiwanPearl-Regular.ttf`（`max32002/TaiwanPearl`，單一靜態字重）
- 源流明體：`GenRyuMinTW-Regular.ttf`（`ButTaiwan/genryu-font`，單一靜態字重）

五個檔案總計約 148MB，Discovery 階段決定直接一般版控提交（不導入 Git LFS），理由見對話紀錄：自架 Gitea 無嚴格檔案大小限制，Git LFS 需額外確認伺服器支援與協作者工具鏈成本，暫不需要。

**字重滑桿行為**：思源黑體/宋體為 Variable Font，理論上可用 `font-variation-settings` 做出真實字重變化；其餘 3 款為單一靜態字重，套用字重調整只能吃「模擬粗體」（synthetic bold），畫質較差。Discovery 階段決定：**滑桿行為對所有字型一致，不因字型是否為 Variable Font 而限制範圍或加提示**——使用者自行承擔單一字重字型的模擬粗體畫質落差。

**刪除自訂字型自動退回預設**：本 epic 範圍內尚無自訂字型可刪（上傳/管理屬 `epic-14`），此規則暫無實際觸發場景；但 `book_reader_prefs.fontFamily` 載入時仍需比照既有 `LibraryPreferences` 的慣例（`byName` 失敗時 catch 並回退預設值），確保未來字型被刪除或資料毀損時能安全退回，而非讓例外往上拋。

## FR-10：版面設定

- **行距、段落間距、邊距**：直接對應 Readium `lineHeight`/`paragraphSpacing`/`pageMargins`，皆為單書覆寫值，無全域預設層。邊距降規格為單一數值（四邊同步變動），見 ADR 0005。
- **文字對齊**：對應 Readium `textAlign` enum，實際列舉值與 UI 呈現方式留待 Architecting 階段確認。
- **停用書本 CSS**：對應 Readium `publisherStyles`（`false`＝停用書本自帶樣式，強制套用 Readium 預設樣式）。
- **排版方向覆寫（三態）**：見上方「架構異動：新增 `book_reader_prefs` 資料表」一節的資料模型拆分。UI 採三顆圖示按鈕並列（📖採用書籍排版／⬇強制直排／➔強制橫排），比照 `prototype/index.html:1476-1484`。
- **翻頁模式覆寫、螢幕方向覆寫**：皆為「單書覆寫值 `??` 全域預設值」的雙層解析。全域預設值：`shared_preferences` 存放，初始值沿用現有行為（翻頁模式＝點擊翻頁對應目前的 paginated、螢幕方向＝自動旋轉），無設定畫面（等 `epic-14` 補上）。UI 皆採圖示直接點選（Discovery 階段決定全部三個覆寫項目統一用圖示，不用下拉選單；螢幕方向 6 個選項的圖示排列方式留待 UI 實作時決定，可能需要多排呈現）。
  - **螢幕方向鎖定為真實 OS 層級鎖定**：解析出的螢幕方向值透過 `SystemChrome.setPreferredOrientations` 套用，非僅內容排版層級的假象；鎖定模式下實體裝置旋轉不觸發排版重算，自動模式下實體裝置旋轉須觸發排版重算（沿用裝置目前螢幕尺寸重新分頁，技術細節留待 Architecting 階段驗證 Readium 是否已自動處理 view 尺寸變化，或需額外監聽並手動觸發）。`ReaderScreen.dispose()` 時必須呼叫 `SystemChrome.setPreferredOrientations([])` 還原為系統預設（允許自由旋轉），比照 PRD 對音量鍵「離開閱讀介面後須恢復正常系統音量控制」的既有處理原則，避免鎖定狀態外溢到書架等其他畫面。

## FR-31：主題與 E-Ink 高對比模式

**主題（深色/羊皮紙/預設，三選一）為全域設定**，不進 `book_reader_prefs`，沿用 `LibraryPreferences` 的 `shared_preferences` 慣例。理由：跨書籍一致的閱讀體驗較符合一般使用直覺，且 `prototype/index.html` 的主題切換點（`app-header` 的 `theme-dot`）本身就位於書架畫面，佐證這是全域而非單書概念。

**E-Ink 高對比模式為獨立的全域布林開關，與三選一主題分開儲存，可與任一主題同時生效**——採用 PRD FR-31 文字「並可與現有 E-Ink 高對比模式並存」的版本，**不**採用 `prototype/index.html` 把 E-Ink 當作第 4 種互斥主題選項的實作（`AppState.theme: 'light'|'dark'|'sepia'|'eink'`）。此為 Discovery 階段發現的 PRD 與原型矛盾，經確認後以 PRD 為準（見 `CONTEXT.md`「E-Ink 高對比模式」詞條）。

## UI

沿用 `prototype/index.html` 已有的 Bottom Sheet 設計（第 1379-1520 行）：閱讀器工具列新增一顆「⚙️ 版面」按鈕，點擊開啟由下往上滑出的 Bottom Sheet，單一「版面設定」頁籤內同時容納字型與版面控制項（PRD FR-10 文字雖描述為「版面」「字型」兩個頁籤，但原型實際只用一個合併頁籤呈現＋另一個保留給劃線與書籤的頁籤——後者不屬本 epic 範圍，本 epic 只需確保新增的 Bottom Sheet 元件結構不排除未來加掛第二個頁籤）。

**整併並移除現有兩顆獨立按鈕**：`ReaderScreen` AppBar 現有的 `reader_writing_mode_toggle`（Issue 2）與 `reader_page_turn_mode_toggle`（Issue 4）兩顆獨立 `IconButton`，其功能整個搬進新的「⚙️版面」Bottom Sheet（比照原型工具列只有 🔖書籤／⚙️版面／📖目錄 三顆按鈕、沒有獨立橫直排或翻頁模式按鈕的設計）。這兩顆按鈕原本就是 Issue 2/4 明確記錄的過渡方案（Issue 4 計劃文件：「與 `epic-3-fonts-layout` 既有規劃的換頁模式控制項整合，不要為此另外新增一套獨立的模式切換 UI」），現在正式整併退場。對應的既有 Key 與測試需要隨之調整/移除。

**定樣式（fixed-layout）EPUB**：整個「⚙️版面」按鈕與 Bottom Sheet 皆不顯示，比照 Epic 2 對橫直排/換頁模式按鈕的既有處理原則（`_isFixedLayout == true` 時完全不顯示，而非顯示但停用）。

## 已知限制與待驗證項目

1. **（ADR 0005）** 邊距降規格為單一數值，無法獨立控制四邊；未來若要補齊四邊獨立控制，需先驗證自訂 CSS 注入或原生容器 padding 兩條路線何者可行。
2. 字型粗細滑桿對 3 款單一靜態字重字型（原俠正楷/台灣圓體/源流明體）只能呈現模擬粗體效果，Discovery 階段決定不做特殊限制或提示。
3. `epic-14-system-settings` 尚未開發：翻頁模式/螢幕方向的全域預設值目前無設定 UI，僅以 `shared_preferences` 存放沿用現有行為的初始值；`epic-14` 上線後只需在同一組 key 上補 UI，預期不影響本 epic 已完成的解析邏輯。
4. `textAlign`（Readium enum）的實際列舉值、`fontWeight`（Readium `Double?`）與 UI 滑桿（prototype 為 300-900 step 100 的 CSS 慣例數值）之間的換算方式，留待 Architecting 階段確認。
5. 螢幕方向「自動模式下裝置旋轉須重新計算分頁」，Readium 是否已透過 view 尺寸變化自動處理、或需額外監聽並手動觸發，留待 Architecting 階段驗證。
6. `fontFamily` 儲存自訂本地字型（非系統字型）的 Readium 接受方式（是否需要額外註冊字型名稱對應表），留待 Architecting 階段驗證。
7. 148MB 字型素材是否影響 APK 體積到需要關注的程度，暫不視為阻塞項，待實際建置後觀察。

## 測試考量

- **Dart widget test**：`book_reader_prefs` 讀寫（含 `byName` 失敗回退預設值，比照 `LibraryPreferences` 既有慣例）；Bottom Sheet 各控制項的初始顯示狀態與互動後的本地 state 更新
- **`integration_test`（真實裝置）**：驗證 `openBook` 帶入 `initialPreferences` 後畫面確實依已持久化設定渲染；驗證螢幕方向鎖定/還原、翻頁模式與排版方向雙層解析的正確性；沿用 Epic 2「不使用 `integration_test` 自動分頁手勢」的既有教訓（若涉及分頁操作驗證，改採真機人工視覺 QA）
- 需要至少一本涵蓋多種字型/CJK 內容的範例 EPUB fixture 供版面設定 QA 使用，是否可沿用既有 fixture 待 Architecting 階段確認
