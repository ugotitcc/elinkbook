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
跨書籍生效的系統層級預設值（例如螢幕方向、翻頁模式、音量鍵翻頁開關、全螢幕顯示開關），對應 PRD FR-36/FR-37/FR-38/FR-42；單書版面偏好設定可覆寫，未覆寫時回退至此值。以 `shared_preferences` 存放。**目前僅螢幕方向與翻頁模式已接上設定畫面 UI**（`epic-14-system-settings` Discovery 已完成，`design.md` 決策 1 規劃於新增的「閱讀預設值」子畫面統一呈現，含音量鍵/全螢幕兩個新欄位，尚未實作）。
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
雙頁模式下同時顯示的一組頁面（通常為相鄰兩頁）。封面獨立時第 1 頁為單頁 spread，之後為雙頁 spread (2,3)(4,5)…。PDF 的翻頁步進以 spread 為單位（一次換一個完整 spread）。EPUB 固定版面的 spread 配對由 `foliate-js`（`paginate.js`）處理。
_Avoid_: 跨頁組、頁面組

**固定版面（Fixed-Layout, FXL）**：
書籍的一種排版形式，每頁有固定尺寸（寬×高），內容不隨螢幕大小重排——常見於漫畫、童書、食譜。與「流式（Reflowable）」互斥。原僅描述 EPUB，`epic-11-multi-format-reader` 起廣義化為跨格式通用概念（見 ADR 0023）：EPUB／KF8(AZW3) 依書本 metadata 判斷可能為固定版面或流式；**CBZ 恆為固定版面**（漫畫圖像無流式變體）；TXT／MD 匯入時合成為 EPUB 相容結構後恆為流式（`isFixedLayout = false`，見「合成書籍結構」）；PDF 有獨立的頁面/縮放概念，不套用此旗標（`isFixedLayout` 恆為 `null`）。偵測時機/機制見「引擎分派判斷」（開書前）與 `EpubLayoutInfo.isFixedLayout`（開書後 Readium 執行期回報，僅用於已選定 Readium 路徑時的內部狀態，不決定引擎選擇——僅適用於 EPUB）。
_Avoid_: 固定排版、定版式、EPUB FXL（`epic-11` 起不再是 EPUB 專屬概念）

**Location 刻度（Location Tick）**：
流式格式（EPUB 流式／TXT／MD）頁碼／進度顯示的近似值，來自 foliate-js `SectionProgress.getProgress()`，以 spine 檔案的未壓縮位元組數（非可見文字字元數）除以固定常數 1500 算出，與畫面實際排版渲染出來的視覺頁完全無關，僅供粗略進度顯示用途。與「視覺頁碼」是完全不同精度層級的概念。
_Avoid_: 頁碼、頁次（過於籠統，未點出「這是估計值」這個關鍵限定）

**視覺頁碼（Visual Page）**：
固定版面（FXL）／CBZ 走 `FixedLayout.pages`（`#spreads.length`）算出的全書真實頁數，精度等同實際渲染結果。流式格式目前無此資料（見 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 10 候選 2）。與「Location 刻度」於 `EpubPositionInfo` 分屬 `visualPageIndex`/`visualTotalPages` 與 `locationIndex`/`locationTotal` 兩組互斥欄位，同一本書恆缺其中一組。
_Avoid_: 頁碼（過於籠統）

**引擎分派判斷（Engine Dispatch Detection）**：
決定一本書籍該用什麼 UI 版面語意（固定版面 → 單頁/雙頁模式；流式 → 連續捲動）的**開書前**判斷，結果快取於 `Book.isFixedLayout`（`app/lib/library/models/book.dart:50`，nullable bool，`null` 代表既有書籍尚未判斷過，或格式本身不適用如 PDF）。原僅涵蓋 EPUB，判斷來源為 `extractMetadata`（匯入時）或 `detectAndCacheEpubLayout`/`detectEpubLayout`（既有書籍首次開書時補判斷）這兩個原生 channel（讀取 EPUB OPF `rendition:layout` 屬性）；`epic-11-multi-format-reader` 起同一欄位廣義套用至 KF8(AZW3)（比照 EPUB 判斷 metadata）、CBZ（恆為 `true`，判斷本身是常數而非偵測）——TXT／MD 因匯入時已合成為流式的 EPUB 相容結構，寫入時即為已知結果（`false`），不需要獨立判斷（見 ADR 0023）。自 ADR 0017 起，EPUB 一律建構 `FoliateEpubReaderView`，不再依此判斷分流到不同 widget——此判斷僅影響 UI 版面參數（單頁/雙頁），不決定引擎選擇。與 `EpubLayoutInfo.isFixedLayout`（開書後才回報的執行期狀態，僅適用於 EPUB）是兩個不同概念、互不影響——見 `book.dart:44-49` 既有註解。少數漫畫 EPUB 因來源檔案 metadata 不完整/不規範，此判斷可能誤判為流式，見「人工版面覆蓋」。
_Avoid_: FXL 偵測、版面偵測（皆容易與 `EpubLayoutInfo` 執行期狀態混淆）

**人工版面覆蓋（Manual Engine Override）**：
使用者在 `LibraryScreen` 多選模式下，對選取的 EPUB 書籍手動覆寫「引擎分派判斷」結果的操作，二擇一：「強制 FXL」（直接寫入 `Book.isFixedLayout = true`）／「恢復自動判斷」（重新呼叫 `detectAndCacheEpubLayout()`，回到系統原始判斷結果，非固定寫入 `false`）。用途是對「引擎分派判斷」誤判（例如漫畫 EPUB 被誤判為流式）提供救濟手段，不修改判斷邏輯本身。批次選取中的非 EPUB 書籍（PDF/TXT）自動跳過。生效時機為使用者下次從書架開啟該書時。自 ADR 0017 起，EPUB 一律使用 `foliate-js` 渲染，「引擎分派判斷」僅驅動 UI 版面語意（單頁/雙頁 vs. 連續捲動），不涉及引擎替換。
_Avoid_: 強制版面、版面覆蓋（皆過於籠統，未點出「覆蓋的是引擎分派判斷，而非單書版面設定」這個關鍵區別，容易與「單書版面偏好設定」混淆）

**Readium 內部版面渲染決策（Readium Internal Rendering Decision）**：
> ⚠️ **Historical（epic-20 前架構）**：自 ADR 0017 起，EPUB 一律使用 `foliate-js` 渲染，本詞條描述的 `EpubNavigatorFragment`／`EpubReaderView.kt` 機制已移除（Issue 5）。保留本詞條供理解歷史脈絡。
Readium 官方元件 `EpubNavigatorFragment`（`readium-kotlin-toolkit`，已移除）曾自行從 `Publication.metadata.layout` 判讀 FXL 或 reflowable 模式渲染，該判讀完全獨立於 Dart 端的「引擎分派判斷」且無外部 API 可覆寫。過去的三層概念脈絡：「固定版面（FXL）」（格式本身）→「引擎分派判斷」（Dart 端 UI 版面語意）→「Readium 內部版面渲染決策」（Readium 官方元件自己的判讀）。現行架構下，`foliate-js` 透過 `paginate.js` 依 `rendition:layout` meta 統一處理 FXL 與流式的渲染模式。
_Avoid_: FXL 渲染判斷（容易與「引擎分派判斷」混淆）

**閱讀偏好管理器（ReaderPrefsManager）**：
整合全域預設值（SharedPreferences）與單書版面偏好設定（SQLite）的深模組。負責載入、寫入與優先級覆寫解析邏輯，對閱讀器（ReaderScreen）提供單一介面，隱藏底層多個數據倉庫。
_Avoid_: 偏好設定服務、設定 Facade

**生效閱讀偏好（ResolvedPreferences）**：
表示閱讀偏好管理器解析後的最終生效偏好設定。其屬性大多為 non-nullable（例如確定的翻頁模式、邊距與字型），直接提供給閱讀器原生視圖套用，不含「是否覆寫」的 nullable 狀態。
_Avoid_: 最終偏好、生效設定

**FXL 換頁熱區（暫代版）（FXL Tap-Zone Navigation, Interim）**：
固定版面（FXL）EPUB 專屬的最小化點擊換頁機制：畫面左／右各 1/3 寬度熱區點擊觸發上一頁／下一頁（透過 `ZoneAction` 執行 `foliate-js` 的 `paginate.js` 分頁命令，不使用滑動動畫，換頁後懸浮控制項一律自動收起），中間 1/3 熱區切換懸浮控制項（返回鍵／設定鍵）顯示或隱藏（切換語意，與左右熱區的「強制收起」不同）。用來取代原生滑動手勢，避免 E-Ink 裝置換頁動畫殘留殘影，也繞開 FXL 相鄰頁 WebView 預載零尺寸造成的縮放跳動（見 `epic-16-dual-page` 已知限制）。左右熱區固定不隨閱讀方向鏡像、不可自訂，僅適用於 FXL；流式 EPUB 不受影響、維持原生手勢。熱區疊加層會擋住底層 WebView 的所有觸控（含 FXL 內嵌超連結，若有的話），刻意接受的暫代方案限制。**與 PRD「可自訂 3×3 點擊九宮格」（傳統/單手/類 Kindle 多種對應模式、RTL 鏡像）是不同東西**——後者是尚未開始的獨立功能，本機制只是範圍受限的暫時方案。
_Avoid_: 九宮格、熱區導航（皆容易與 PRD 完整版混淆，應明確加註「暫代版」或「FXL 專屬」）

**設定面板草稿具現化原則（Settings Sheet Draft Concretization Rule）**：
判斷「版面設定 Bottom Sheet」（`PdfSettingsSheet`／`ReaderSettingsSheet`）的本地 State 欄位該不該保留 `BookReaderPrefs` 的 nullable「未覆寫」語意，依據是該欄位**是否存在次要權威來源可回退**（全域預設值、書籍自動偵測值等）——有次要來源時，本地狀態應維持 nullable，並提供一個「不覆寫／採用書籍內建」的重置選項（例如 `ReaderSettingsSheet` 的 `_writingModeOverride`）；無次要來源、null 與具體預設值解析結果永遠相同時（例如 PDF 相關欄位——`docs/epics.md` 已明文排除 PDF/雙頁欄位於 `epic-14-system-settings` 全域預設層之外），本地狀態在 `initState()` 用 `??` 具現化為非 null 值是安全的，不視為違反「null = 不覆寫」慣例。
_Avoid_: null 語意破壞（脫離「是否存在次要權威來源」這個前提單獨評斷時容易誤判）

**書籤（Bookmark）**：
使用者標記書中「一個位置」的離散事件，定位精度等同閱讀進度（EPUB：CFI；PDF：頁碼；TXT 定位暫緩，見 `epic-6-annotations` 範圍界定）。每頁/每位置最多一筆，以 toggle 語意新增/移除，具名（預設為章節名稱或頁碼，可重新命名）。與「劃線」「備註」是完全不同的物件類型——書籤無需選取範圍，用途是導覽而非知識管理。FXL 亦支援。
_Avoid_: 加入書籤（動詞誤用成獨立概念）、標記（與劃線混淆）

**劃線（Highlight）**：
使用者對書中「一段選取範圍」套用的視覺標記，定位精度高於書籤（EPUB：CFI 範圍；PDF：頁碼＋頁內矩形座標）。有兩種樣式子類型：**螢光筆**（背景底色填滿，黃/粉/藍三色可選）與**底線**（波浪底線，固定單色、不可選色）。建立後不可改色/樣式，僅能刪除重畫。與「備註」是各自獨立的物件類型，可在同一段選取範圍上共存或單獨存在。FXL 不支援（無文字層可選取）。
_Avoid_: 標記、註記（後者在本專案泛指劃線+備註的合稱，見「劃線與備註」）

**備註（Note）**：
使用者對書中「一段選取範圍」附加的自由文字內容，定位精度與劃線相同。可獨立於劃線存在（選取範圍後可以只加備註、不劃線）；純備註（無劃線）需有固定樣式的畫面指示（EPUB：Readium Decorator 淡灰底＋行內圖示；PDF：淡灰色半透明矩形＋右上角 📌 圖示）以區別於使用者自選色的劃線。內容可事後編輯，刪除時與同範圍的劃線一併刪除（無「只刪備註」的單獨操作）。FXL 不支援。
_Avoid_: 筆記（本專案保留給「筆記」入口按鈕這個 UI 概念，不是備註物件本身）、註解

**筆記（Notes Entry）**：
閱讀畫面 AppBar 上單一入口按鈕（📚），點開後是帶「🔖 書籤」／「✏️ 劃線與備註」兩個分頁籤的 Bottom Sheet 外殼容器。兩個分頁籤底下的資料（書籤清單、劃線+備註合併清單）彼此完全獨立，只是共用同一個入口與容器，避免 AppBar 按鈕過多。不要與「備註（Note）」這個獨立物件類型混淆。
_Avoid_: 註記面板、筆記本（皆容易與「備註」物件本身混淆）

**熱區模式（Nav Zone Mode）**：
全域生效（不分書籍）的 3×3 點擊導航熱區設定，四選一互斥：「左翻頁」「右翻頁」「單手」三種固定模板（不可個別微調），或「自訂」（完全自由編輯 9 格各自動作）。統一套用於 EPUB 流式、PDF、EPUB FXL 三種畫面，**不**隨橫排/直排自動鏡像——由使用者依閱讀方向與持機習慣自行選模式，見 ADR 0009。對應 FR-24。
_Avoid_: 九宮格（單指配置本身時容易與「熱區動作」混淆）、導航區域、傳統／類 Kindle（PRD 舊字眼，已改用「左翻頁／右翻頁」直接描述方向）

**熱區動作（Zone Action）**：
9 格熱區中每一格可指定的動作，四選一：上一頁、下一頁、選單（觸發「沉浸模式」切換）、無動作（攔截觸控但不做事）。
_Avoid_: 熱區行為

**沉浸模式（Immersive Mode）**：
熱區「選單」動作觸發的介面顯示/隱藏切換：EPUB 流式與 PDF 隱藏 Scaffold AppBar ＋ `ReaderFooter`；EPUB FXL 沿用既有懸浮控制項（返回/設定/書籤/筆記按鈕）顯示/隱藏。翻頁動作（上一頁/下一頁）不影響此顯示狀態，僅選單格可切換（與 FXL 舊行為「換頁一律強制收起」不同，是刻意的行為變更）。**與「全螢幕模式」是彼此獨立、互不干涉的兩套機制**，見下方詞條。
_Avoid_: 全螢幕模式（見下方獨立詞條，非同義詞，不可混用）

**全螢幕模式（Fullscreen Mode）**：
`epic-19-shelf-reading-enhance` 新增的持久化開關，只控制 Android 系統狀態列與導覽列的顯示/隱藏（`SystemUiMode.immersiveSticky` 或等效 API），與 App 自己的 AppBar/Footer/頁首/頁尾/懸浮按鈕完全脫鉤——後者永遠只受「沉浸模式」與各自的顯示開關（`showHeader`/`showFooter`）控制，不受全螢幕模式影響。離開閱讀畫面時強制還原系統列顯示，不依賴使用者手動關閉開關。涵蓋 EPUB 流式/FXL/PDF 三種格式。**對應 PRD FR-42**——`epic-19` 僅實作單書層級；`epic-14-system-settings` Discovery（2026-08-02）已規劃新增全域預設層（`book.fullscreen ?? global.fullscreen`，比照「翻頁模式」/「螢幕方向預設」既有雙層解析模式），尚未實作，見 `docs/epics/epic-14-system-settings/design.md` 決策 6。
_Avoid_: 沉浸模式（見上方獨立詞條，非同義詞）

**欄數（Column Mode）**：
流式 EPUB 專屬的分欄控制，三態互斥：自動（由 `paginator.js` 依欄位大小閾值自由決定，可能 1/2/3 欄）、單欄（強制單欄，不論裝置尺寸或排版方向）、雙欄（硬限最多 2 欄）。單書持久化於 `book_reader_prefs`。取代 Epic 18 Issue 5 原有的 `singleColumn` 布林開關（該開關因 `paginator.js` 對直排書籍的 `maxColumnCount + 1` 邏輯，在多數裝置上是 no-op，見 ADR 0012）。固定版面 EPUB 和 PDF 不適用（兩者有各自獨立的「雙頁模式」概念）。
_Avoid_: 強制單欄、分欄偏好、Column Layout

**欄位大小（Column Size）**：
流式 EPUB 專屬的單欄最大寬度（橫排）或最大高度（直排）閾值，對應 `paginator.js` 的 `--_max-inline-size` CSS 自訂屬性。超過此值時 paginator 開始考慮分欄。單書持久化於 `book_reader_prefs`，僅在「欄數」為「自動」時生效（「單欄」和「雙欄」模式下由系統自動覆蓋）。預設 720px，可調範圍 360–1440px，步進 60px。
_Avoid_: 欄數切換閾值、maxInlineSize（使用者不懂的技術名稱）

**版面設定預設集（Layout Preset）**：
`epic-28-reader-settings-enhancements` 引入，使用者可額外保存的具名版面設定快照，最多 3 組，範圍限「流式 EPUB」的「版面設定」（`ReaderSettingsSheet`）目前呈現的全部項目（含排版數值與方向/翻頁/螢幕方向覆寫等，非僅字型/行距等數值型欄位）。與「單書版面偏好設定」是不同概念——後者是「這本書目前生效的值」（1:1 綁定 `book_id`），前者是「使用者收藏起來、可重複套用到任意書籍」的具名範本（不綁定特定書籍，需獨立資料表存放）。套用時整份覆寫寫入目標書籍的「單書版面偏好設定」。PDF／FXL 不適用（各自獨立設定畫面，欄位語意不共通）。
_Avoid_: 預設值（容易與「全域預設值」混淆）、版面模板

**書籍設定複製（Copy Layout From Book）**：
`epic-28-reader-settings-enhancements` 引入，套用「版面設定」時「版面設定預設集」以外的另一個來源選項：直接以某本來源書籍當下的「單書版面偏好設定」為內容寫入目標書籍，不經過具名預設集這層中介、不受最多 3 組的數量限制，是一次性的書對書操作。
_Avoid_: 複製設定（過於籠統，未點出「以書籍為來源」這個關鍵區別）

**elinkBook 同步帳號（Sync Account）**：
`epic-8-sync` 引入的雲端帳號體系，透過 PocketBase（email+password）登入，用途是把「閱讀進度／劃線／備註／書籤」同步到雲端、跨裝置一致（對應 FR-19/20/30）。完全可選（opt-in），不登入也能完整使用 App 所有既有單機功能。**與「雲端匯入來源帳號」是完全不同的帳號體系**，見下方詞條。
_Avoid_: 雲端帳號（過於籠統，容易與雲端匯入來源帳號混淆）、PocketBase 帳號（實作細節，非使用者視角詞彙）

**雲端匯入來源帳號（Cloud Import Source Account）**：
PRD FR-02 描述的帳號體系，登入 Google Drive／OneDrive 等雲端硬碟，用途是從中讀取/下載電子書檔案匯入圖書庫。與「elinkBook 同步帳號」完全無關、互不影響。每個 provider（Google Drive／OneDrive）**限單一帳號**（同一 provider 只能連結一組，換帳號需先解除連結）；登入狀態會被記住（persist refresh token），不需每次匯入都重新登入。管理入口為「設定」頁常駐（可查看/解除連結），匯入流程中若尚未連結也可直接觸發連結。2026-08-17 `/grill-with-docs` 完成 Discovery，已立案為新 Epic（見 `docs/epics.md`）。
_Avoid_: 雲端帳號（見上）

**書籍內容指紋（Book Content Fingerprint）**：
`epic-8-sync` 為解決跨裝置「同一本書」比對問題而新增的穩定識別碼：EPUB 優先取 OPF identifier（通常是 ISBN 或出版社 UUID），缺漏時退而用檔案內容 hash；PDF/TXT 一律用檔案內容 hash。匯入時計算存入 `books.content_fingerprint`。**與本機 `Book.id`（時間戳記+URI hash，僅裝置本地穩定，跨裝置各自不同）是不同概念**，同步邏輯必須用指紋而非本機 id 比對書籍身份。演算法定案為 **SHA-256**（`package:crypto`），PDF/TXT（與 EPUB 缺漏 OPF identifier 時的退回路徑）皆為**全檔案內容雜湊**（非抽樣頭尾），一次性匯入成本換取正確性、避免抽樣造成的誤判碰撞（2026-08-02 `epic-8-sync` Architecting 階段定案）。`books.id` 本身維持現狀不受影響，不因本 Epic 改成 UUID 格式（格式與跨裝置比對無關）。**第二個用途（2026-08-17 `/grill-with-docs`，雲端匯入 Epic Discovery 階段新增）**：雲端匯入時的重複匯入偵測直接借用同一個指紋欄位比對——僅在指紋完全相同時才提示「可能重複」，刻意不做書名/作者模糊比對。因指紋對「EPUB 缺漏 identifier／PDF／TXT／CBZ」是全檔案雜湊，跨來源（雲端副本 vs. 本機副本）容器層級位元組差異會導致指紋不同、抓不到重複，此為已知、刻意接受的落差（非本機 bug）。**第三個用途（2026-08-17 `/grill-with-docs`，`epic-30-calibre-remote-library` Discovery 階段新增）**：Calibre 遠端書架下載後的重複匯入偵測，與第二個用途相同模式——`(remote_server_id, remote_book_id)` 前置檢查沒命中時，下載後計算指紋比對，僅完全相同才提示，同樣不做模糊比對。
_Avoid_: 書籍 ID、書本雜湊（未點出「用於跨裝置比對」這個關鍵用途）、抽樣雜湊（已否決的方案）

**書籍來源（Book Source）**：
`Book.source`（`BookSource` enum：`local`／`googleDrive`／`oneDrive`）標記這本書當初是從哪裡匯入的。`local`／`googleDrive`／`oneDrive` 三個值在圖書庫管理實作完成當下就已存在，但直到 2026-08-17 雲端匯入 Epic Discovery 之前只是未賦值的 UI stub（僅 `local` 曾被實際指派）。雲端匯入落地後，`googleDrive`／`oneDrive` 才會被真正賦值，並額外搭配一個雲端檔案 ID（存放於哪個欄位待 Architecting 階段定案）供「雲端匯入來源帳號」解除連結後仍保留、也供重複匯入偵測使用。純粹是歷史紀錄用途——解除雲端帳號連結不會清空既有書籍的來源標記，也不影響已下載檔案本身。**2026-08-17 `/grill-with-docs`（`epic-30-calibre-remote-library` Discovery）決議新增第 4 個值**（暫定 `calibreOpds`，最終命名待 Architecting 定案），標記書籍來自「遠端書庫」（見下方詞條）；與 `googleDrive`／`oneDrive` 不同，此來源額外需要 `remote_server_id`（見「遠端書庫站點」）搭配 `remote_book_id` 才能定位，因為同一來源類別可能對應多個站點，不像雲端硬碟每個 provider 限單一帳號。
_Avoid_: 匯入來源（過於籠統，容易與「匯入方式」如檔案選擇器/資料夾選擇器混淆）

**遠端書庫（Remote Library）**：
`epic-30-calibre-remote-library` 引入的產品概念：使用者連結自架 Calibre Content Server／Calibre-Web／或任何標準 OPDS 書庫伺服器，在 App 內持續瀏覽該書庫目錄、選讀後才下載成本機檔案。與「雲端匯入來源帳號」（Google Drive／OneDrive 等雲端硬碟，OAuth，一次性匯入到本機、之後與雲端脫鉤）是完全不同的體系：遠端書庫強調「可重複造訪瀏覽」，支援下載後移除本機快取、保留雲端紀錄、之後再重新下載（見「書籍來源」）；雲端匯入強調「一次性搬移」，來源標記純粹是歷史紀錄，不支援重新抓取。認證方式為 HTTP Basic Auth 或匿名，不是 OAuth。
_Avoid_: 雲端書庫、雲端硬碟（皆容易與「雲端匯入來源帳號」混淆）

**遠端書庫站點（Remote Library Site）**：
使用者在「遠端書庫」功能中新增的一筆伺服器連線設定（對應 `remote_servers` 資料表一列）：名稱、伺服器網址、伺服器類型（標準 OPDS／原生 Calibre Content Server／Calibre-Web）、帳密（密碼獨立存 `flutter_secure_storage`，不落地明文於 SQLite）。使用者可同時管理多個站點（例如家用 NAS＋公網 Calibre-Web＋公開 OPDS 書庫），這是「遠端書庫」與「雲端匯入來源帳號」（每個 provider 限單一帳號）在帳號模型上的核心差異。書籍列的 `remote_server_id` 欄位（見「書籍來源」）即指向這裡的站點 id，用於反查站點顯示名稱與判斷書籍是否仍可重新下載（站點被刪除後，該站點名下無本機快取的書籍會失去重新下載的能力，刪除站點前需示警）。
_Avoid_: 伺服器設定、OPDS 站點（未點出「使用者自訂管理的一筆連線設定」這個資料實體本質）

**Checkpoint 同步（Checkpoint Sync）**：
`epic-8-sync` 的批次同步觸發機制，三種事件之一發生即觸發一次批次同步（把期間累積的所有本機異動一次送出）：App 背景化、書籍切換（離開閱讀器）、閱讀中每 5 分鐘的閒置計時器（避免長時間不背景化/不切書時另一裝置看不到最新異動）。與「逐筆即時同步」（每次異動立刻各自觸發一次網路請求）相對，見 ADR 0020。批次上傳透過 PocketBase 內建 **Batch API**（`/api/batch`，要求伺服器版本 ≥ 0.23）一次 HTTP 請求送出，交易性（全部成功或全部失敗）；下載遠端異動不批次，4 個 collection 各自查詢一次即可（量體小不需優化）。
_Avoid_: 自動同步、背景同步（皆未點出「批次觸發」這個關鍵特性）

**用戶端識別碼（`client_id`）**：
`epic-8-sync` 引入，`bookmarks`／`highlights`／`notes` 三表的本機主鍵格式由 `INTEGER PRIMARY KEY AUTOINCREMENT` 改為 `TEXT PRIMARY KEY`（UUID），**本機 id 與同步識別碼合一**（不另外疊加一個 `sync_id` 欄位）。PocketBase 端對應 collection 額外開一個 `client_id` 欄位存放同一個 UUID 值，PocketBase 內建的 `id` 欄位純粹是其內部管理用途，App 完全不讀取/比對它——避免依賴特定 PocketBase 版本對自訂 `id` 格式的支援程度。`notes` 依附劃線時存的是該劃線的 `client_id`（而非本機整數 `highlight_id` 的舊概念，該概念已隨此變更取消）。**`books.id` 不受影響、維持原格式**——書籍的跨裝置身份比對用途已由「書籍內容指紋」承擔，兩者是不同機制（2026-08-02 `epic-8-sync` Architecting 階段定案）。
_Avoid_: sync_id（已否決的雙 id 設計，本機 id 現在就是同步用的那個 id，不是另外疊加的欄位）、UUID（過於籠統，未點出「本機主鍵與同步識別碼合一」這個關鍵設計）

**自訂字型（Custom Font）**：
`epic-14-system-settings`（FR-35）引入的使用者上傳字型，與內建 5 款字型（思源黑體/思源宋體/原俠正楷/台灣圓體/源流明體，見「Fit 模式」鄰近詞條群）並列於同一份全域字型清單，統一以 family name 字串識別（`AppFont` enum 僅保留供內建字型清單 UI 呈現，不再是儲存型別）。**只對 EPUB 生效**——PDF 為原生點陣圖渲染，不套用字型設定。**不複製檔案進 App 私有目錄**，比照 ADR 0002 對書籍檔案的既有精神，以 `content://` URI＋`takePersistableUriPermission()` 直接引用，見 ADR 0021。
_Avoid_: 上傳字型（動詞誤用成獨立概念）、外部字型（未點出「不複製、直接引用」這個關鍵特性）

**閱讀預設值（Reading Defaults）**：
`epic-14-system-settings` 新增的 `SettingsScreen` 子畫面，集中呈現四項全域預設值（見「全域預設值」詞條）：音量鍵翻頁開關（FR-36）、螢幕方向 5 選一（FR-37）、翻頁模式 2 選一（FR-38）、全螢幕顯示開關（FR-42）。純粹是 UI 呈現層的分組容器，四項底層資料各自獨立存於 `GlobalReaderPrefs`，不是新的資料模型。
_Avoid_: 系統偏好、全域設定畫面（後者容易與「設定」App 本身混淆）

**Foliate 格式（Foliate-Rendered Formats）**：
`epic-11-multi-format-reader` 起，泛指所有透過 `foliate-js` Web 引擎渲染、共用同一個泛化後 widget（原 `FoliateEpubReaderView`，改名 `FoliateReaderView`，見 ADR 0023）與其排版/劃線/書籤/CFI 定位機制的書籍格式集合：EPUB（流式與固定版面）、KF8(AZW3)、CBZ、TXT／MD（皆先轉為「合成書籍結構」再餵入）。與獨立走 `PdfReaderView`（PDFium FFI）的 PDF 格式相對，兩者是 `ReaderScreen` 僅有的兩條原生渲染分派路徑。
_Avoid_: 統一格式（未點出「透過 foliate-js 渲染」這個關鍵限定範圍——PDF 也屬於格式擴充的一員但不屬於此分類）

**合成書籍結構（Synthesized Book Structure）**：
`epic-11-multi-format-reader` 引入，TXT／MD 匯入時把原始檔案轉換為一份 EPUB／XHTML 相容結構的衍生檔案，存於 App 私有目錄；`Book.filePath` 之後指向此衍生檔案，原始檔案僅於匯入當下讀取一次、之後不再參照（與「`coverPath` 一律是本機複本」的既有匯入慣例同源）。合成結構恆為流式（`isFixedLayout = false`），供泛化後的 `FoliateReaderView` 直接渲染，取代 `epic-11` 原案「自訂輕量排版引擎」的技術路線（原案已作廢，見 ADR 0023）。
_Avoid_: TXT/MD 轉檔（未點出「匯入時一次性、`filePath` 改指向合成檔」這個關鍵機制）

