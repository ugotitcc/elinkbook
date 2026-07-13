# elinkBook

跨平台電子書閱讀器，核心差異化在於直排（vertical-RL）繁體中文排版與深度版面客製化。單一情境，全專案共用本詞彙表。

## Language

**主題（Theme）**：
三選一的全域閱讀色彩配置：深色（Dark）、羊皮紙（Sepia）、預設（Light）。跨書籍一致，不可單書覆寫。
_Avoid_: 外觀模式、色彩方案

**E-Ink 高對比模式**：
獨立於「主題」之外的全域布林開關，可與任一主題同時生效（例如「羊皮紙 + E-Ink 高對比」）；訴求是無障礙/E-Ink 裝置相容性（高對比、減少殘影），不是第 4 種主題選項。
_Avoid_: E-Ink 主題

**單書版面偏好設定（Book Reader Preferences）**：
單一書籍專屬的版面設定值（字型、行距、邊距、對齊、排版方向覆寫、螢幕方向覆寫、翻頁模式覆寫等），儲存於 `book_reader_prefs` 表（與 `books` 表 1:1，以 `book_id` 為外鍵）。
_Avoid_: 單書設定、閱讀器設定

**全域預設值（Global Default）**：
跨書籍生效的系統層級預設值（例如螢幕方向、翻頁模式），對應 PRD FR-37/FR-38；單書版面偏好設定可覆寫，未覆寫時回退至此值。目前無對應設定畫面（`epic-14-system-settings` 尚未開發），先以 `shared_preferences` 存放沿用現有行為的初始值。
_Avoid_: 系統設定、全域設定（兩者在 PRD 中另指 `epic-14` 的獨立系統設定畫面本身，容易與「全域預設值」這個資料層概念混淆）

**開書初始偏好（Initial Preferences）**：
`openBook` 契約新增的參數，讓已持久化的偏好設定（單書覆寫值或全域預設值解析後的結果）能在開書當下、`attachNavigator()` 成功後立即套用，不依賴 `didUpdateWidget` 的「值改變才觸發」機制。
_Avoid_: 初始設定、預設偏好

**PDF 加粗（Bold Filter）**：
PDF 影像濾鏡之一，對已渲染的頁面點陣圖做型態學膨脹（dilate）處理讓筆畫變粗變黑，用於改善淡色掃描件的可讀性；與 EPUB 的 `fontWeight`（作用於文字節點的 CSS 屬性）是完全不同的機制，不可混用。
_Avoid_: 粗體、font-weight（PDF 語境下）

**Fit 模式（PDF Fit Mode）**：
PDF 頁面在螢幕上的縮放顯示方式，三選一：Page-fit（整頁完整顯示，預設）、Fit Width（頁寬滿版、上下可捲動）、真實比例 1:1（不縮放）。單書持久化於 `book_reader_prefs`，無全域預設層。
_Avoid_: 縮放模式、顯示模式

**智慧自動裁切（Smart Auto-Crop）**：
PDF 裁切模式之一，取樣頁面偵測內容邊界（去除白邊/黑邊）後，計算出一個裁切比例，全書統一套用同一比例（非逐頁各自計算），與「手動選區裁切」為互斥的單選模式（見「裁切模式」）。
_Avoid_: 自動裁切、智慧裁切

**裁切模式（Crop Mode）**：
PDF 頁面裁切的三選一設定：不裁切、智慧自動裁切、手動選區裁切。三者互斥；手動選區裁切由使用者於全螢幕裁切編輯模式框選矩形，同樣全書統一套用。單書持久化於 `book_reader_prefs`。
_Avoid_: 裁切設定

**雙頁模式（Dual-Page Mode）**：
EPUB 固定版面與 PDF 的並排顯示設定，三態：自動（橫向時啟用、直向時關閉）、永遠雙頁、永遠單頁。單書持久化於 `book_reader_prefs`，不做內容啟發式判斷，由使用者手動控制。流式 EPUB 不適用。
_Avoid_: 雙頁顯示、兩頁模式、分頁模式

**Spread（跨頁）**：
雙頁模式下同時顯示的一組頁面（通常為相鄰兩頁）。封面獨立時第 1 頁為單頁 spread，之後為雙頁 spread (2,3)(4,5)…。PDF 的翻頁步進以 spread 為單位（一次換一個完整 spread）。EPUB 固定版面的 spread 配對由 Readium 依 `page-spread-left/right` metadata 處理。
_Avoid_: 跨頁組、頁面組

**固定版面（Fixed-Layout, FXL）**：
EPUB 的一種排版形式，每頁有固定尺寸（寬×高），內容不隨螢幕大小重排——常見於漫畫、童書、食譜。與「流式（Reflowable）」互斥。由 Readium 的 `onLayoutResolved` 回報 `isFixedLayout: true` 偵測。
_Avoid_: 固定排版、定版式

**閱讀偏好管理器（ReaderPrefsManager）**：
整合全域預設值（SharedPreferences）與單書版面偏好設定（SQLite）的深模組。負責載入、寫入與優先級覆寫解析邏輯，對閱讀器（ReaderScreen）提供單一介面，隱藏底層多個數據倉庫。
_Avoid_: 偏好設定服務、設定 Facade

**生效閱讀偏好（ResolvedPreferences）**：
表示閱讀偏好管理器解析後的最終生效偏好設定。其屬性大多為 non-nullable（例如確定的翻頁模式、邊距與字型），直接提供給閱讀器原生視圖套用，不含「是否覆寫」的 nullable 狀態。
_Avoid_: 最終偏好、生效設定

**FXL 換頁熱區（暫代版）（FXL Tap-Zone Navigation, Interim）**：
固定版面（FXL）EPUB 專屬的最小化點擊換頁機制：畫面左／右各 1/3 寬度熱區點擊觸發上一頁／下一頁（呼叫 Readium `goForward(animated=false)`/`goBackward(animated=false)`，不使用滑動動畫），中間 1/3 熱區切換懸浮控制項（返回鍵／設定鍵）顯示或隱藏。用來取代原生滑動手勢，避免 E-Ink 裝置換頁動畫殘留殘影，也繞開 FXL 相鄰頁 WebView 預載零尺寸造成的縮放跳動（見 `epic-16-dual-page` 已知限制）。左右熱區固定不隨閱讀方向鏡像、不可自訂，僅適用於 FXL；流式 EPUB 不受影響、維持原生手勢。**與 PRD「可自訂 3×3 點擊九宮格」（傳統/單手/類 Kindle 多種對應模式、RTL 鏡像）是不同東西**——後者是尚未開始的獨立功能，本機制只是範圍受限的暫時方案。
_Avoid_: 九宮格、熱區導航（皆容易與 PRD 完整版混淆，應明確加註「暫代版」或「FXL 專屬」）

**設定面板草稿具現化原則（Settings Sheet Draft Concretization Rule）**：
判斷「版面設定 Bottom Sheet」（`PdfSettingsSheet`／`ReaderSettingsSheet`）的本地 State 欄位該不該保留 `BookReaderPrefs` 的 nullable「未覆寫」語意，依據是該欄位**是否存在次要權威來源可回退**（全域預設值、書籍自動偵測值等）——有次要來源時，本地狀態應維持 nullable，並提供一個「不覆寫／採用書籍內建」的重置選項（例如 `ReaderSettingsSheet` 的 `_writingModeOverride`）；無次要來源、null 與具體預設值解析結果永遠相同時（例如 PDF 相關欄位——`docs/epics.md` 已明文排除 PDF/雙頁欄位於 `epic-14-system-settings` 全域預設層之外），本地狀態在 `initState()` 用 `??` 具現化為非 null 值是安全的，不視為違反「null = 不覆寫」慣例。
_Avoid_: null 語意破壞（脫離「是否存在次要權威來源」這個前提單獨評斷時容易誤判）
