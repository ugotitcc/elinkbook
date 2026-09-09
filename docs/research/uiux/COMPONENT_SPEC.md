# Component Spec — `elinkbook_theme_prototype.html` 反向萃取

> 命名依 `CONTEXT.md`／`DESIGN.md` 既有詞彙（`GroupTile`／`BookCoverTile`／`PagingBar`／`Chrome Bar`／`TtsPanel` 等），不重新發明名稱；`DESIGN.md` 沒有名稱的元件標註「原型內部命名」或新擬名稱並註明未定案。
> Token 引用一律對照 `DESIGN_TOKENS.md`，不重複列出完整色值/間距換算表。
> States 一律檢查 default/hover/pressed/focused/selected/disabled/loading/error；原型未示範者標記 `Not defined in prototype`（原型是純 HTML/JS 模擬器，沒有 focus-visible／loading skeleton 這類瀏覽器或非同步狀態，這類項目多數會是此標記）。

---

## AppBar（書架／來源／設定共用樣式）

### Structure
單列：左側標題文字，右側 2–3 顆方形圖示按鈕。書架另外在標題下方多一列常駐搜尋欄（見 `SearchField`）。

### Dimensions
高度固定 `56px`（`h-[56px]`，`DESIGN.md` 未對 AppBar 高度另立 token，56 是 Material 標準 AppBar 高度的巧合對齊，非 `DESIGN.md` 明文規定）。圖示按鈕 `w-11 h-11`(44px)。

### Spacing
左右內距 `px-4`(16px=`EBSpace.lg`✅)，圖示按鈕間 `space-x-2`(8px=`EBSpace.sm`✅)。

### Typography
標題：`text-xl font-black`（20px，對應 `DESIGN.md` `titleLarge`✅，見 `DESIGN_TOKENS.md`）。

### Colors
背景 `surface`，文字 `onSurface`，底部分隔線 `border-b-2` 對應 `outline`（見 `DESIGN_TOKENS.md` Border 章節「粗分隔線 vs 細邊框」雙層語彙）。

### Radius / Shadow
無圓角（矩形通欄）、無陰影。

### States
- default：如上。
- pressed：`active:bg-black active:text-white`（換色後 = `active:bg-primary active:text-onPrimary`）整顆按鈕反色，符合 `DESIGN.md` §7.2 E-Ink「反白」離散反饋語彙，**但原型不分主題一律套用此反色按壓效果**，未依 §7.2「一般模式 Hover 亮度微調 + 波紋動畫」與「E-Ink 模式反白」分流——⚠️ `[CONFLICT]`：一般（非 E-Ink）主題下也應該有 Ripple 效果，原型全程只有反色，沒有示範 Ripple。
- hover / focused：`Not defined in prototype`（純觸控模擬器，無滑鼠 hover 樣式）。
- disabled：`Not defined in prototype`（AppBar 圖示按鈕永遠可點擊）。

### Responsive behavior
`DESIGN.md` §11.1 規定平板／桌機改用 `NavigationRail` 側邊導覽軌，AppBar 三目的地圖示邏輯僅適用於手機寬度。原型完全沒有示範這個切換——「橫排 (4欄)」模擬僅是書架網格欄數改變，AppBar 本身樣式不隨寬度變化，`NavigationRail` 變體 ❓ `[UNKNOWN]`，原型未涵蓋。

### HTML source
`#view-library` 第 174–181 行、`#view-source` 第 682–688 行、`#view-settings` 第 788–794 行。

---

## SearchField（書架搜尋列）

### Structure
單列文字輸入框，內嵌前導圖示 `⌕`，佔滿寬度。

### Dimensions
高度 `h-11`(44px)。⚠️ `[CONFLICT]`：低於 `DESIGN.md` §7.2 一般模式最小觸控目標 48dp（輸入框本身雖非按鈕，但作為主要互動控制項適用同一門檻的合理性待人類確認）。

### Spacing
外層 `p-3 pb-0`，輸入框內距 `px-3`(12px)，圖示與輸入框間 `space-x-2`(8px)。

### Typography
`text-sm`(14px=`bodyMedium`✅) placeholder「搜尋書名或作者...」。

### Colors
邊框 `outline`，背景透明（沿用父層 `surface`）。

### Radius / Shadow
`rounded-md`(6px，見 `DESIGN_TOKENS.md` Radius 章節衝突)。無陰影。

### States
- default：如上。
- focused：`focus:outline-none`——**刻意移除瀏覽器預設 focus 外框，且沒有補上任何替代的 focus 視覺樣式**。⚠️ `[CONFLICT]`／可及性缺口：鍵盤/輔助科技使用者無法看出目前是否聚焦在搜尋框，`DESIGN.md` 未對輸入框 focus 狀態訂規範，這是原型與規格書共同的盲點，建議之後補上。
- 其餘 states：`Not defined in prototype`。

### Responsive behavior
不隨模擬器寬度改變版面（僅寬度隨父層 100% 縮放）。

### HTML source
`#view-library` 第 184–189 行。

---

## ContinueReadingRow（繼續閱讀列）

### Structure
單列：左側書封縮圖佔位、中間書名+章節+進度文字（兩行）、右側 `›` chevron。整列可點擊。`DESIGN.md` §15.1 明訂「此列常駐不受下方分類/書籍格狀區域換頁影響」。

### Dimensions
封面佔位 `w-9 h-11`(36×44px)。

### Spacing
容器 `p-2.5`(10px，`DESIGN_TOKENS.md` 已記錄的半階間距衝突)，內部元素 `gap-3`(12px=`md`✅)。外層 `px-3 pt-3`。

### Typography
標籤「繼續閱讀」：`text-[10px] font-bold tracking-wider uppercase opacity-60`（10px，見 `DESIGN_TOKENS.md` Typography 微型標籤缺口）。主文字：`text-sm font-bold truncate`(14px)。

### Colors
邊框 `outline`，按壓態反色（同 AppBar 按壓語彙）。

### Radius / Shadow
`rounded-md`(6px)。無陰影。

### States
- default / pressed（`active:bg-black active:text-white`）。
- 其餘：`Not defined in prototype`。

### Responsive behavior
不隨欄數變化，橫排/直排寬度皆為滿版單列。

### HTML source
`#view-library` 第 192–201 行。

---

## GroupTile（分類格子）

`DESIGN.md` §15.1 命名一致：「內部呈現為 2x2 微縮封面拼貼」。

### Structure
封面區為 2×2 網格拼貼（最多顯示 4 本代表書封縮圖，不足補空白格），左上角常駐「分類」黑底白字角標；下方一行分類名稱＋本數。

### Dimensions
封面區比例 `aspect-[0.62]`（寬:高 ≈ 1:1.61，`DESIGN.md` §15.1 規定「格狀視圖二者一律強制維持 `3:4` 的高度/寬度比例」）——`0.62` 換算高寬比約為 `1.61:1`，**不等於** `DESIGN.md` 規定的 `3:4`(=0.75)。⚠️ `[CONFLICT]`，且此比例值同時套用在 `GroupTile` 與 `BookCoverTile` 兩者，是系統性差異，非單一元件個案。

### Spacing
外層 `space-y-1.5`(6px，衝突值)，2×2 拼貼格間 `gap-[1.5px]`(自訂極小值，非 `EBSpace` 任何一級，是拼貼縫隙專用的視覺細節，`[INFERRED]`)。

### Typography
角標「分類」：`text-[9px] font-bold`(9px，低於 `DESIGN.md` 最小字級 `labelSmall`=11sp，見 `DESIGN_TOKENS.md`)。分類名稱：`text-sm font-black`(14px)，本數：`text-xs`(12px)。

### Colors
角標固定 `bg-black text-white`（換色後＝`primary`/`onPrimary`，**不是** `onSurface`/`surface`——分類角標用主色而非中性色，是原型刻意的強調色選擇，`[INFERRED]`，`DESIGN.md` 未提及此角標）。封面拼貼縫隙 `bg-black`（對應 `outline`），拼貼格底色 `bg-white`（對應 `surface`）。

### Radius / Shadow
無圓角（矩形拼貼）、無陰影——見 `DESIGN_TOKENS.md` Shadow 章節「原型全程只示範 Outlined Card 變體」的系統性發現，`GroupTile` 是具體案例之一。`DESIGN.md` §4 圓角 token 表把「分類格子」明訂為 `EBRadius.md`(16dp)，原型完全沒有圓角，是本文件記錄過最大的圓角落差案例。

### States
- default / pressed（`onclick="drillIntoCategory(...)"`，配合 `triggerFlash()` 全螢幕反白動畫模擬 E-Ink 刷新——**此刷新動畫不分主題、E-Ink 開或關都會觸發**，⚠️ `[CONFLICT]`：`DESIGN.md` 核心原則第 2 條「E-Ink 作為修飾子」隱含只有 E-Ink 模式才需要這種瞬間刷新視覺，非 E-Ink 主題理應有平滑過場而非反白閃爍，原型未區分）。
- selected／下鑽態：進入分類後，`GroupTile`／`BookCoverTile` 整組被替換成該分類書籍清單（非疊加選中樣式，是內容替換）。
- 其餘：`Not defined in prototype`。

### Responsive behavior
欄數隨模擬器寬度：直排 3 欄 (`grid-cols-3`)／橫排 4 欄 (`grid-cols-4`)，對應 `DESIGN.md` §15.1「書架網格排版直排 3 欄、橫排 4 欄」✅ 相符。**列數**（每頁顯示幾列）原型固定寫死 6 個項目一頁展示，未依 `DESIGN.md` §15.1「列數依裝置實際可用高度動態計算」的規則示範不同高度下的列數變化，❓ `[UNKNOWN]`，這條規則的動態行為原型無法驗證。

### HTML source
`#library-grid` 內第 214–246 行（「經典」「漫畫」兩個分類格子範例）。

---

## BookCoverTile（書籍卡片）

### Structure
封面區（純文字書名置中，代表書封圖片佔位）＋下方書名（2 行截斷）＋進度條與百分比／✓完成標記。

### Dimensions
與 `GroupTile` 共用 `aspect-[0.62]` 封面比例（同上「⚠️ 不等於 `DESIGN.md` 3:4」問題）。進度條高度 `h-[7px]`。

### Spacing
`space-y-1.5`(6px)／`space-y-1`(4px=`xs`✅) 分層堆疊。

### Typography
書名：`text-sm font-bold line-clamp-2 leading-tight`(14px，見 `DESIGN_TOKENS.md` `bodyLarge` 衝突——`DESIGN.md` 規定書名不低於 15sp)。進度百分比：`text-[10px] font-bold`(10px)。

### Colors
封面佔位背景 `bg-white`(=`surface`)——⚠️ `[CONFLICT]`：`DESIGN.md` §8.2 明訂封面佔位符須用 `ElinkTokens.coverPlaceholder`（依主題各異的專屬色，例如 Light `#e6f1fa`），**不是** `surface` 本色；原型的封面佔位完全沒有實作 `coverPlaceholder` 這個語意色，一律用主題的 `surface` 白底，等於封面區與卡片背景同色、視覺上沒有區隔。也未包含 §8.2 規定的 `Icons.book` 圖示。進度條：軌道 `border-black`(=`outline`)，已完成部分 `bg-black`(=`primary`)。

### Radius / Shadow
無圓角、無陰影（同 `GroupTile`，`DESIGN.md` §4 定義封面圓角為 `EBRadius.sm`=8dp，原型為 0）。

### States
- default / pressed。
- **長按**（`bindBookCard()` 500ms 計時器）觸發 `BookActionSheet`，短按觸發「開始閱讀」——這是原型示範的關鍵手勢區分，與 `DESIGN.md` §15.1「點擊書本卡片上的『⋮』圖示（不使用長按）」**直接衝突**：`DESIGN.md` 明文規定單書動作選單入口是「⋮」圖示點擊、長按保留給批次選取；原型完全沒有「⋮」圖示，長按直接開動作 Sheet，也沒有批次選取（多選模式）的任何示範。⚠️ `[CONFLICT]`，且是本次分析發現的最關鍵手勢層級落差，需要人類明確裁示：原型的「長按開動作選單」是回到舊設計，還是 `DESIGN.md` 這條規則需要重新確認。
- 其餘：`Not defined in prototype`（無下載中／錯誤狀態封面示範）。

### Responsive behavior
同 `GroupTile`。

### HTML source
`#library-grid` 內第 249–311 行（5 本書卡片範例）；`bookCardHtml()` JS 模板函式第 1070–1082 行（分類下鑽後動態產生用）。

---

## PagingBar（換頁控制列）

`DESIGN.md` §15.1 命名一致。

### Structure
三欄：上一頁按鈕／頁碼文字／下一頁按鈕，橫置底部常駐列。

### Dimensions
列高 `h-[52px]`，✅ 符合 `DESIGN.md` §15.1「高度最小 52dp」。按鈕 `w-14 h-[38px]`(56×38px)——寬度 56px ✅ 符合 §15.1「按鈕寬度大於 56dp」（原型自身註解也標註了「翻頁高度 52dp，按鈕寬度大於 56dp」，第 315 行），但按鈕**高度** 38px 明顯低於 §7.2 一般模式最小觸控目標 48dp。⚠️ `[CONFLICT]`——寬度合格但高度不合格，觸控熱區實際上是 56×38，非正方形也未達最小觸控面積。

### Spacing
按鈕與頁碼文字間 `gap-6`(24px=`xl`✅)。

### Typography
頁碼「第 1 頁 / 共 22 頁」：`text-sm font-bold`(14px)。

### Colors / Radius / Shadow
邊框 `outline`，按鈕 `rounded-md`(6px)，頂部分隔線 `border-t-2`（粗分隔線語彙，同 AppBar）。無陰影。

### States
- default / pressed（反色）。
- disabled：`Not defined in prototype`——原型的 `libraryPrevPage()`/`libraryNextPage()` 有邊界檢查（`if (libraryPage < 22)`），但按鈕本身**沒有**在到達邊界時套用 disabled 視覺樣式（不變灰、不降低透明度），純粹依賴「點了沒反應」，沒有視覺回饋告知使用者已到頁首/頁尾。⚠️ `[CONFLICT]`／可用性缺口。

### Responsive behavior
固定底部常駐，欄數/列數變化不影響此列本身樣式。

### HTML source
`#view-library` 第 316–320 行。

---

## BookActionSheet（書籍長按動作 Sheet）

`DESIGN.md` §15.1 稱之為「由 `EBSheetShell` 包裹的該書專屬 Bottom Sheet」；原型內部 id 為 `book-action-sheet`。

### Structure
半透明遮罩（點擊可關閉）＋底部滑出面板：標題列（書名＋✕關閉鈕）／詳細資料／移動／版面覆寫／移除快取／刪除（黑底白字強調，破壞性操作）五個選項列。

### Dimensions
標題列高 `h-[52px]`，各選項列高 `h-14`(56px)，✅ 符合 48dp 觸控下限。遮罩 `background:rgba(0,0,0,.32)`（32% 不透明度黑色，`DESIGN.md`／原型皆未定義此為正式 token，➕ `[INFERRED]` scrim 值）。

### Spacing
`px-4`(16px=`lg`✅)。

### Typography
標題 `text-sm font-black`(14px)，選項 `text-sm font-bold`(14px)。

### Colors
容器 `bg-white`(=`surface`)，刪除選項 `bg-black text-white`(=`primary`/`onPrimary`，破壞性操作用強調色反白)——⚠️ `[CONFLICT]`：`DESIGN.md` §9.2 規定破壞性操作「按鈕顏色採用 `error` 色」，原型用的是 `primary` 反色而非 `error` 色（且原型根本沒有實作 `error` 這個顏色角色，見 `DESIGN_TOKENS.md`）。且 `DESIGN.md` §9.2 要求「涉及刪除書籍等破壞性操作必須彈出確認對話框」，原型的「刪除」選項點擊後只顯示 Toast 提示文字「刪除前需二次確認對話框（此原型未實作）」——**原型作者自己註明了這個缺口**，屬已知、刻意標註的未實作範圍，非本文件推測。

### Radius / Shadow
**無 `rounded-t-*`（頂部直角）、無拖曳把手元素、無陰影**——`DESIGN.md` §10.1 明訂 Bottom Sheet 須有「頂部居中 32×4dp 拖曳把手，圓角 `EBRadius.sm`」且整體應有 `EBElevation.md`(4) 陰影，原型兩者都沒有實作。⚠️ `[CONFLICT]`，本文件記錄的最明確的 Bottom Sheet 規格缺口案例。

### States
- default（隱藏，`hidden` class）／顯示（`openBookActionSheet()` 移除 `hidden`）。
- **無展開/收合動畫**：原型用 `classList` 直接切換 `hidden`，沒有任何滑入/滑出的 transition——這恰好符合 `DESIGN.md` §10.2「E-Ink 模式禁用滑入/滑出動畫，改為瞬間顯示」的要求，但原型**不分主題**一律瞬間顯示，等於 Light/Dark/Sepia 非 E-Ink 主題也沒有平滑滑入動畫，是否也算 `[CONFLICT]` 待人類確認（`DESIGN.md` 沒有明講非 E-Ink 模式下 Bottom Sheet 動畫的具體規格，只規範了 E-Ink 該怎麼做）。
- pressed（各列反色）。

### Responsive behavior
`Not defined in prototype`（未示範平板/桌機下 Bottom Sheet 寬度是否收斂為置中對話框樣式）。

### HTML source
`#book-action-sheet`，第 322–336 行。

---

## EBStepper（步進器，字級／行距／段落間距／字重／字距／四邊界／欄位大小共用同一結構）

`DESIGN.md` §18 第 3 項正式命名 `EBStepper`，明訂「E-Ink 模式下 Slider 一律替換為此元件」。**原型中這個元件不分主題、不分 E-Ink 開關，一律都是 Stepper 形式，從未示範對應的 Slider 版本**——⚠️ `[CONFLICT]`：`DESIGN.md` 語意上暗示非 E-Ink 主題可能用 Slider（連續拖曳），原型完全沒有 Slider 元件可供對照，`EBSlider` 的視覺規格完全 ❓ `[UNKNOWN]`。

### Structure
單列：左側標籤文字（含「此書覆寫」／「使用全域預設」次要說明）、中間數值、左右各一顆 `−`/`＋` 按鈕。

### Dimensions
`−`/`＋` 按鈕 `w-12 h-12`(48×48px)，✅ 恰好等於 `DESIGN.md` §7.2 一般模式最小觸控目標，但**未達** E-Ink 模式應有的 56dp（原型不分 E-Ink 開關，按鈕尺寸固定 48px）。⚠️ `[CONFLICT]`。

### Spacing
容器 `p-2.5`(10px，衝突值)，內部 `pr-2`(8px)。

### Typography
標籤 `text-sm font-black`(14px)，次要說明 `text-[10px]`(10px)，數值 `text-lg font-black`(18px，`DESIGN.md` 無對應 token，➕ `[INFERRED]`，介於 `titleMedium`16 與 `titleLarge`20 之間)。

### Colors / Radius / Shadow
邊框 `outline`，`rounded-md`(6px)，無陰影。

### States
- default / pressed（`−`/`＋` 按鈕反色）。
- **無邊界 disabled 樣式**：段落間距 `Math.max(0, ...)`、欄位大小 `Math.max(120, ...)` 等有下限保護，但按鈕到達下限時同樣沒有 disabled 視覺（同 `PagingBar` 缺口模式）。⚠️ `[CONFLICT]`。

### Responsive behavior
`Not defined in prototype`。

### HTML source
「文字」分頁第 455–508 行（5 個步進器）、「邊界」分頁第 522–557 行（4 個步進器）、「呈現」分頁欄位大小第 594–602 行。

---

## EBSwitchRow（開關列，含 CSS 停用／頁首頁尾／全螢幕／E-Ink 主開關共用同一結構）

### Structure
單列：左側標籤（可選次要說明），右側 pill 形開關（軌道＋圓點）。

### Dimensions
開關軌道 `w-14 h-9`(56×36px)，圓點 `w-7.5 h-7.5`(30×30px)——整體觸控面積 56×36，⚠️ `[CONFLICT]`：高度 36px 遠低於 `DESIGN.md` 48dp 觸控下限。

### Spacing / Typography / Colors
容器 `p-2.5`／`p-3` 不一（同語意元件在不同畫面出現時 padding 不一致，➕ `[INFERRED]`，屬原型自身不一致，非刻意變體）。標籤 `text-sm font-black`(14px)。開（軌道 `bg-black`=`primary`，圓點 `bg-white`=`onPrimary`，圓點右移 `translate-x-5`）／關（軌道 `bg-white`=`surface`，圓點 `bg-black`=`onSurface`，圓點居左）。

### Radius / Shadow
`rounded-full`（軌道與圓點皆是），無陰影。

### States
- on / off 兩態明確示範（見上）。
- **切換無過場動畫**：`transition-none` 顯式停用，符合 `DESIGN.md` §18「零動畫轉場」E-Ink 要求，但同樣**不分主題**一律無動畫。⚠️ 與 `BookActionSheet` 同一類「未依主題分流動畫規則」問題，是原型內重複出現的系統性模式，建議 `DESIGN_TOKENS.md`／本文件多處出現的這個模式一併處理，不要逐一元件個別修正。
- disabled：`Not defined in prototype`（除 E-Ink 鎖定佈景選擇器外，一般開關無 disabled 狀態示範）。

### HTML source
「文字」分頁「停用書本內建樣式」第 511–516 行、「邊界」分頁頁首/頁尾第 560–571 行、「呈現」分頁全螢幕模式第 634–639 行、設定畫面 E-Ink 開關第 800–809 行、設定畫面頁首/頁尾第 840–848 行。

---

## Tab（版面設定四分頁籤：文字／邊界／呈現／預設集）

### Structure
橫向四等分按鈕列，選中項黑底反白。

### Dimensions
列高 `h-11`(44px)。⚠️ `[CONFLICT]`：低於 48dp 觸控下限（與 `SearchField` 同款問題）。

### Colors
選中：`bg-black text-white`(=`primary`/`onPrimary`)；未選中：邊框 `outline`，按壓態反色。

### Radius / Shadow
無圓角（矩形通欄），底部 `border-b-[1.5px]` 與內容區分隔。無陰影。

### States
default／selected／pressed 皆有示範；disabled／loading：`Not defined in prototype`。

### HTML source
第 431–436 行。

---

## LayoutPreset Card（版面設定預設集卡片）

`DESIGN.md` 對應概念為 `CONTEXT.md` 詞條「版面設定預設集（Layout Preset）」。

### Structure
單列：預設集名稱＋摘要說明（左），套用按鈕與刪除按鈕（右）。系統預設（`preset-system`）不可刪除，僅有套用按鈕；使用者自訂預設集兩者皆有。目前套用中的預設集整列反色＋✓ 勾選標記。

### Dimensions
刪除按鈕 `w-10 h-10`(40px)。⚠️ `[CONFLICT]`：明顯低於 48dp 觸控下限，是本文件記錄的觸控目標落差中數值最小的案例之一。

### Colors
選中態整列 `bg-black text-white`。

### Radius / Shadow
`rounded-md`(6px)，無陰影。

### States
default／selected(套用中)／pressed。刪除確認：`Not defined in prototype`（`deletePreset()` 直接刪除並顯示 Toast，無二次確認——`DESIGN.md` §9.2 破壞性操作守衛是否適用於「刪除預設集」這個動作，`DESIGN.md` 未明確涵蓋此情境，❓ `[UNKNOWN]`）。

### HTML source
第 643–675 行。

---

## ThemeSelector（佈景選擇器：側欄開發工具版＋設定畫面版）

已於 `DESIGN_TOKENS.md`「Border」章節詳述 E-Ink 鎖定時使用 `opacity` 而非 `DESIGN.md` §17.2 規定的「3dp 虛線邊框」這個核心衝突，此處補充結構性資訊。

### Structure
- 側欄版（開發工具，非 App UI，不計入正式規格，僅供參照）：三個直式按鈕。
- 設定畫面版（App UI，第 812–819 行）：三個 `w-7 h-7`(28px) 圓形色點，內嵌對應主題代表字（淺/深/宣），選中態邊框加粗。

### Dimensions
設定畫面圓點 28×28px。⚠️ `[CONFLICT]`：遠低於 48dp 觸控下限，是全文件記錄到的觸控目標落差最嚴重的案例（不到規定的 60%）。

### Colors
每個圓點直接內嵌該主題的 `surface`／`onSurface` 色值（唯一「不透過 CSS 變數換色機制、而是寫死該主題色值」的元件，因為這裡本來就是要同時展示三種主題的樣子供選擇）。

### Radius / Shadow
`rounded-full`，無陰影。

### States
default／selected（`borderWidth` 加粗至 3px，`applyThemeState()` 第 940 行——**這個「選中態加粗邊框」的手法，其實正是 `DESIGN.md` §17.2 要求用在「E-Ink 鎖定態」的視覺語彙，原型卻只把它用在「一般選中態」，E-Ink 鎖定態反而用了被禁止的 opacity**，兩處手法在原型內部發生了語意錯位）／disabled（E-Ink 鎖定，`opacity: 0.35`，⚠️ 已於 `DESIGN_TOKENS.md` 詳述為 `[CONFLICT]`）。

### HTML source
設定畫面版第 812–819 行；`applyThemeState()` 邏輯第 920–943 行。

---

## Breadcrumb（來源畫面麵包屑導覽）

`DESIGN.md` §16.1 命名一致。

### Structure
橫向可捲動列，`首頁 › 歷史 › 羅馬帝國` 形式，最後一節（當前層級）加粗且不可點擊。

### Dimensions
列高 `h-[44px]`。

### Typography
`text-xs font-bold`(12px)，當前層級 `font-black`。

### Colors / Radius
可點擊節點 `rounded` (4px) 小 pill，按壓態反色。分隔符 `›` 半透明 `opacity-50`。

### States
default／pressed（可點擊節點）／當前層級（不可點擊，純文字）。原型註解明確指出「僅示範最後一層麵包屑，實際會列出『歷史』分類下的其他書系」——中間層級節點點擊只顯示提示 Toast，非真正下鑽，屬原型簡化，非規格缺口。

### HTML source
`#source-drill` 第 763–770 行。

---

## SourceListItem（來源清單項目：本機/Google Drive/OneDrive/OPDS/下鑽書目共用結構）

### Structure
單列：左側圖示、中間標題＋副標（連結狀態或伺服器數量）、右側 chevron 或下載圖示。

### Dimensions
高度 `h-[64px]`（已連結服務列）／`h-14`(56px)（下鑽書目列）／`h-[76px]`（本機選擇檔案/資料夾，改為上下堆疊圖示+文字的方形按鈕，非橫列）——三種高度並存，➕ `[INFERRED]`：原型依內容複雜度（單行 vs 雙行文字）自然形成三種高度，`DESIGN.md` 未對「來源清單項目」訂出統一高度 token。

### Spacing
`px-3.5`(14px，衝突值，見 `DESIGN_TOKENS.md`)／`gap-3`(12px=`md`✅)。

### Typography
標題 `text-sm font-black`(14px)，副標 `text-[10px]`(10px)。

### Colors / Radius / Shadow
邊框 `outline`，`rounded-md`(6px)，無陰影。

### States
default／pressed。連結狀態（已連結/尚未連結）用副標文字區分，非獨立視覺樣式（無「已連結」徽章或勾選圖示），❓ `[UNKNOWN]`：是否該有更醒目的已連結狀態指示，`DESIGN.md` 未規定。

### HTML source
第 696–738 行、`#source-drill` 第 772–781 行。

---

## DownloadQueueRow（下載佇列）

`DESIGN.md` §16.2 命名一致，規定用「確定式進度條」取代連續旋轉指示器。

### Structure
容器內多列，每列：檔名（截斷）、確定式進度條（邊框+填色矩形，非圓形）、百分比或「待機」文字。

### Dimensions
進度條 `w-24 h-2`(96×8px)。

### Colors
✅ 符合 §16.2「確定式進度條」規範，邊框 `outline`，填色 `bg-black`(=`primary`)。

### States
進行中（有填色比例）／待機（空進度條，文字顯示「待機」而非百分比）。無失敗/錯誤狀態示範，❓ `[UNKNOWN]`。

### HTML source
第 742–759 行。

---

## TtsPanel（常駐朗讀面板）

`DESIGN.md` §13.1 已有完整規格定義（展開控制列＋底層動作列兩排結構），原型示範大致相符，差異記錄如下。

### Structure
✅ 兩排結構與 `DESIGN.md` 一致：上排（上一句/播放暫停/下一句/語速/語音，5 顆），下排（睡眠定時器/收合/停止，3 顆）。

### Dimensions
上排按鈕 `h-12`(48px)，✅ 符合一般模式 48dp；下排 `h-11`(44px)，⚠️ `[CONFLICT]` 未達 48dp。`DESIGN.md` §13.1 規定觸控目標「一般模式 52dp」（注意：此處 `DESIGN.md` 自己用的是 52dp 而非 §7.2 通則的 48dp，屬 TTS 面板專屬加碼規格），原型兩排都未達到 52dp，上排 48px 也是 `[CONFLICT]`。

### Colors
播放/暫停鍵（主動作）與停止鍵：`bg-black text-white`(=`primary`/`onPrimary`) 強調樣式，✅ 符合 §13.1「停止按鈕為強調色」。

### States
播放中／暫停（`toggleTtsPlay()` 切換按鈕文字與樣式，暫停時目前朗讀句從反白改為虛線底線）／收合（`isCollapsed`，隱藏上排，符合 §13.1「`isCollapsed` 為 true 時整排隱藏」✅）。**CBZ 停用態**（`DESIGN.md` §13.1 規定「僅顯示停用狀態播放鍵，其餘四顆不渲染」）：❓ `[UNKNOWN]`，原型完全沒有示範 CBZ／圖像格式情境。

### HTML source
第 401–420 行；JS 邏輯第 1333–1391 行。

---

## Button（通用變體歸納）

`DESIGN.md` §7.1 定義 Filled／Outlined／Text 三變體。原型實際觀察到的模式：

- **Filled 對應**：選中態的分頁籤、預設集套用中、TTS 播放/停止鍵——一律是「`bg-black text-white`」，與其說是獨立的 Filled Button 元件，不如說是「一般 Outlined 按鈕的選中/強調態」，原型**沒有一個獨立、恆常存在（非依賴選中狀態）的 Filled Button** 範例。➕ `[INFERRED]`。
- **Outlined 對應**：絕大多數互動元件的預設樣式（`border-[1.5px] border-black`），原型幾乎全用這個變體。
- **Text Button 對應**：❓ `[UNKNOWN]`，原型沒有無邊框、純文字的按鈕範例（`DESIGN.md` 舉例「還原預設值」這類低優先動作，原型未涵蓋此情境）。

**共用按壓語彙**：所有按鈕一致使用 `active:bg-black active:text-white` 反色，取代 `DESIGN.md` §7.2 一般模式該有的 Ripple／Hover 亮度微調——見 `AppBar` 一節已詳述的系統性 `[CONFLICT]`，此處作為全域按鈕行為的統一結論，不在每個元件重複展開。

---

## Toast（系統通知浮層）

### Structure
畫面上方橫幅，黑底白字置中文字，`showNotification()` 顯示 1.8 秒後自動隱藏。

### Dimensions
`h-11`(44px)，左右 `inset-x-6`(24px)。

### Colors / Radius / Shadow
`bg-black text-white`(=`primary`/`onPrimary`)，`rounded`(4px)，`shadow-lg`——**是原型內唯一在 App 畫面範圍內使用陰影的元件**，與 `DESIGN_TOKENS.md` 記錄的「App 內容全程無陰影」發現有一個例外，需註明。

### States
顯示／隱藏（`hidden` class 切換，無淡入淡出動畫，`transition-none` 隱式）。

### HTML source
第 893–895 行；`showNotification()` 第 1419–1426 行。

---

## SettingsListItem（設定項目列）

### Structure
單列：標題＋副標（左），chevron（右，代表可進入子畫面）；部分列改為右側直接放開關（如 E-Ink／頁首頁尾），無 chevron。

### Dimensions
`h-16`(64px) 一般項目／`h-[64px]` 帶開關項目。

### Colors / Radius / Shadow
`rounded-md`(6px)，按壓態反色（純導覽項目）；帶開關項目本身不可點擊整列（僅開關本身可互動）。

### States
default／pressed（純導覽項）；on/off（帶開關項，複用 `EBSwitchRow`）。

### HTML source
`#view-settings` 第 796–888 行（外觀／閱讀／同步與帳號／關於四分區全部項目）。
