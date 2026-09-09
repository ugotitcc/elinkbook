# Screen Spec — `elinkbook_theme_prototype.html` 反向萃取

> 元件細節請對照 `COMPONENT_SPEC.md`，本文件只記錄畫面層級的版面組成、間距節奏與跨元件互動。
> 原型透過側欄「切換模擬畫面」在 5 個畫面間切換（`switchView()`），彼此互斥顯示（`hidden` class），非真正的路由堆疊。

---

## 通用：Screen Layout 基礎規格

- **模擬容器尺寸**：直排 `375×720px`／橫排 `640×480px`（`setOrientation()`，第 996–1028 行）。**這不是真正的 CSS `@media` 響應式斷點**——整份原型檔案內**沒有任何一個 `@media` 規則**，寬高切換完全由 JS 直接改寫 inline style 與 class 名稱（`grid-cols-3`↔`grid-cols-4`）驅動。⚠️ 這代表 `DESIGN.md` §11.1 定義的三層斷點（手機 <600dp／平板 ≥600dp `NavigationRail`／桌機 ≥1024dp 雙欄）**完全沒有被這份原型示範過**——375px 與 640px 都遠低於 600dp 平板門檻，原型只模擬了「手機直向」與「手機橫向」兩種情境，平板/桌機版面 ❓ `[UNKNOWN]`，需要另外設計或另一份原型驗證。
- **內容寬度**：畫面內容一律滿版（`flex-grow`），無 `max-width` 限制、無置中留白邏輯。`DESIGN.md` §3 定義的 `EBSpace.maxContentWidth`=680（平板大螢幕內容寬度上限）在此原型中從未被觸發或示範，❓ `[UNKNOWN]`。
- **AppBar 高度**：所有畫面一致 `56px`，見 `COMPONENT_SPEC.md` `AppBar`。
- **導覽模式**：✅ 符合 `DESIGN.md` §11.1——五個畫面全程只用標題列右側圖示切換，未曾出現底部導覽列（`BottomNavigationBar`），三個常駐目的地（書架/來源/設定）互相以圖示按鈕切換，並各自在 AppBar 帶上「另外兩個目的地」的快速入口圖示，與 §11.1 規定的圖示配置逐一核對皆相符（書架：☰/⇩/⚙；來源：▦/⚙；設定：▦/⇩）。

---

## Screen: Library（書架）

### Layout
垂直堆疊：AppBar（56px）→ SearchField → ContinueReadingRow → 書本網格（`flex-grow`，可下鑽）→ PagingBar（52px，底部常駐）。長按觸發的 `BookActionSheet` 以絕對定位疊加於整個畫面之上。

### Header
見 `COMPONENT_SPEC.md` `AppBar`。標題固定文字「書架」，下鑽分類後**不改變 AppBar 標題**，改由網格區上方出現獨立的 `library-breadcrumb`「‹ 返回 ＋ 分類名稱」列（第 206–211 行）表示目前所在分類——這與「來源」畫面的麵包屑是两套完全獨立的實作（一個用 `library-breadcrumb` 專屬 DOM、一個用通用 `Breadcrumb` 元件），➕ `[INFERRED]`：書架的下鑽提示嚴格說不是 `DESIGN.md` §16.1 定義的「麵包屑」（只有『返回上層』一層，不是多層路徑列表），命名上更接近「返回列」，`DESIGN.md` §11.2 也是用「頂部隨即出現『返回上層』的引導控制列」這個說法，用詞與「來源」畫面的麵包屑刻意不同，原型的實作方式與此描述相符。

### Content
書本網格混排 `GroupTile`／`BookCoverTile`（見 `COMPONENT_SPEC.md`），直排 3 欄／橫排 4 欄。下鑽後網格內容整組替換為該分類書籍列表，非 push 新畫面，✅ 符合 `DESIGN.md` §11.2「不再使用 `Navigator.push` 堆疊新畫面」。

### Components
`AppBar`／`SearchField`／`ContinueReadingRow`／`GroupTile`／`BookCoverTile`／`PagingBar`／`BookActionSheet`／`Toast`。

### Spacing
網格區 `p-3`(12px=`md`)，網格項目間 `gap-x-3 gap-y-4`(12px/16px，横向`md`✅／縱向`lg`✅，兩軸不同級距)。

### Responsive
欄數依方向切換（見上）；**列數固定寫死 2 列示範內容（6 個項目=3欄×2列 或 4欄×2列）**，未示範 `DESIGN.md` §15.1「列數依裝置實際可用高度動態計算」的高度自適應行為，❓ `[UNKNOWN]`。

### States
- 一般瀏覽／下鑽中／多選批次模式。**多選批次模式完全未實作**——`DESIGN.md` §15.1「長按進入多選，頂部出現 AppBar 操作列」與原型實際的「長按進入 `BookActionSheet`（單書動作）」互相衝突，已在 `COMPONENT_SPEC.md` `BookCoverTile` 詳述，此處僅標註「批次操作模式」整體 ❓ `[UNKNOWN]`，原型完全沒有對應畫面可供分析。

### HTML source
`#view-library`，第 172–337 行。

---

## Screen: Reader（閱讀器與朗讀）

### Layout
垂直堆疊：頂部 Chrome Bar（56px，恆常顯示）→ 直排內文閱讀區（`flex-grow`）→ 底部 Chrome（`reader-normal-chrome` 一般模式／`reader-tts-chrome` 朗讀模式，兩者互斥）。⬓ 按鈕收合時，僅隱藏底部 Chrome，內文區隨之延伸佔滿剩餘空間；頂部 Chrome Bar 不受影響（原型未實作 `DESIGN.md` §12.1「全螢幕模式開啟時頂列也一併隱藏」的擴大收合範圍規則，因為原型根本沒有示範「全螢幕模式」這個獨立開關，只有「沉浸模式」單一層級，❓ `[UNKNOWN]`）。

### Header
頂部 Chrome Bar（`DESIGN.md` §12.1 正式術語，非泛稱 AppBar）：返回、書名/章節（置中）、內文搜尋、⬓、目錄，共 5 個元素。✅ 與 `DESIGN.md` §12.1 描述的「返回按鈕、書名與目前章節、內文搜尋按鈕、⬓ 按鈕、書籤 Toggle 按鈕」對照，**缺少書籤 Toggle 按鈕**——原型頂部 Chrome Bar 沒有書籤按鈕，書籤功能被放在底部選單列（見下）。⚠️ `[CONFLICT]`：`DESIGN.md` 明確把書籤放在頂部，原型放在底部。

### Content
直排中文內文（`writing-mode: vertical-rl`），從畫面右側起排（`flex justify-end`），✅ 符合中文直排由右至左的閱讀方向慣例；目前朗讀句子有獨立 `<span>` 供動態套用高亮/底線樣式。

### Components
`Chrome Bar`（頂部）、視覺頁碼列、離散跳頁控制列（含步進式進度條與「跳」按鈕）、閱讀器底部選單列（書籤/劃線備註/版面/朗讀 4 顆）、`TtsPanel`（朗讀模式取代底部選單列）。

### Spacing
內文區 `p-6`(24px=`xl`✅)。底部各列高度：頁碼列 `34px`、跳頁列 `56px`、選單列 `64px`——三個非 `EBSpace` 標準值，➕ `[INFERRED]`，屬元件專屬高度而非間距 token。

### Responsive
❓ `[UNKNOWN]`——閱讀器畫面未隨模擬器直排/橫排寬度做任何版面調整測試（僅示範直排 375px 寬度下的樣子），橫排/雙頁模式（EPUB FXL／PDF 並排顯示，`CONTEXT.md`「雙頁模式」詞條）完全沒有對應畫面，也不在這份原型範圍內（此原型僅示範流式 EPUB 直排閱讀情境）。

### States
一般閱讀（`reader-normal-chrome` 顯示）／朗讀中（`reader-tts-chrome` 顯示，`triggerTts()`／`stopTts()` 互斥切換，✅ 符合 `DESIGN.md` §13「依 `TtsController.status` 衍生互斥切換」的行為模式，雖然原型用的是手動旗標 `isTtsActive` 而非真正的 controller status，屬合理的原型簡化）／Chrome 收合（`isChromeVisible`）。

### HTML source
`#view-reader`，第 340–421 行。

---

## Screen: LayoutSettings（版面設定面板）

**結構性發現**：`DESIGN.md` §10 明確把「版面設定」列為由 `EBSheetShell` 包裹的 Bottom Sheet 之一（與目錄／筆記／TTS 控制面板同類）。但原型的實作方式是 `#view-layout`——與書架/閱讀器/來源/設定同等級的**全畫面 view 切換**（`switchView('layout')`），不是疊加在閱讀器之上的半高 Bottom Sheet。⚠️ `[CONFLICT]`：這代表原型完全沒有示範 §10.1 規定的「Bottom Sheet 最大高度 50–85% 螢幕高度」「頂部拖曳把手」「從底部滑入」等視覺行為——版面設定在這份原型裡看起來、用起來都像一個獨立全螢幕畫面，而非彈出式抽屜。是否要以原型為準修正 `DESIGN.md` 的分類，還是原型需要改回 Bottom Sheet 呈現，需人類裁示。

### Layout
垂直堆疊：AppBar 風格標題列（56px，「版面設定」＋✕ 關閉鈕返回閱讀器）→ 四分頁籤（44px）→ 分頁內容捲動區（`flex-grow overflow-y-auto`）。

### Header
與其他畫面 AppBar 同高，但右側只有單一「✕」關閉鈕（返回閱讀器），非其他畫面的「兩個目的地圖示」模式——因為這個畫面在 `DESIGN.md` 語意上本就不是三大目的地之一，✅ 這點與規格書一致。

### Content
四分頁籤各自內容：
- **文字**：字型（循環按鈕）＋ 5 個 `EBStepper`（字級/行距/段落間距/字重/字距）＋ 1 個 `EBSwitchRow`（停用書本 CSS）。
- **邊界**：4 個 `EBStepper`（上下左右邊界）＋ 2 個 `EBSwitchRow`（頁首/頁尾）。
- **呈現**：換頁模式／欄數（含條件顯示的欄位大小 `EBStepper`）／書寫方向／文字對齊 四組三態選擇按鈕，＋螢幕方向鎖定（五選一）＋全螢幕模式 `EBSwitchRow`。
- **預設集**：新增按鈕＋ `LayoutPreset Card` 清單。

### Components
`Tab`／`EBStepper`／`EBSwitchRow`／`LayoutPreset Card`，見 `COMPONENT_SPEC.md`。

### Spacing
分頁內容 `p-4 space-y-3.5`(16px + 14px 衝突值)。

### Responsive
❓ `[UNKNOWN]`，未示範。

### States
四分頁互斥切換（`switchLayoutTab()`），僅「呈現」分頁內有條件顯示邏輯（欄數選「預設」才顯示欄位大小步進器，選單欄/雙欄則隱藏）。

### HTML source
`#view-layout`，第 424–678 行。

---

## Screen: Source（來源）

### Layout
垂直堆疊：AppBar（56px）→ 根畫面（`source-root`：本機／已連結服務／下載佇列 三區塊，可捲動）與下鑽畫面（`source-drill`：麵包屑＋書目清單）互斥切換（非疊加）。

### Header
✅ 符合 `DESIGN.md` §11.1（▦ 書架、⚙ 設定）。

### Content
本機：兩個並排方形按鈕（選擇檔案／選擇資料夾）。已連結服務：`SourceListItem` 清單（Google Drive／OneDrive／Calibre-OPDS）。下載佇列：`DownloadQueueRow`。下鑽後：`Breadcrumb` ＋ 書目 `SourceListItem` 清單。

### Components
`SourceListItem`／`Breadcrumb`／`DownloadQueueRow`，見 `COMPONENT_SPEC.md`。

### Spacing
根畫面 `p-4 space-y-4`(16px=`lg`)，各區塊標題 `text-xs font-bold tracking-wider uppercase`(12px，與設定畫面分區標題同款式，➕ `[INFERRED]`：這是原型內「區塊標題」的統一樣式慣例，`DESIGN.md` §17.1 提到 `EBSectionHeader` 但未給出具體樣式規格，本文件記錄的這個 class 組合可作為 `EBSectionHeader` 的具體實作參考)。

### Responsive
❓ `[UNKNOWN]`，未示範。

### States
根畫面／下鑽畫面 互斥。下鑽本身**只做了一層深度示範**（首頁→歷史→羅馬帝國，其中「歷史」節點點擊只顯示提示文字，非真正跳轉），原型註解已明確聲明是簡化示範，非規格缺陷。

### HTML source
`#view-source`，第 681–784 行。

---

## Screen: Settings（設定）

### Layout
垂直堆疊：AppBar（56px）→ 四分區內容（可捲動，`overflow-y-auto`）。

### Header
✅ 符合 `DESIGN.md` §11.1（▦ 書架、⇩ 來源）。

### Content
四分區與 `DESIGN.md` §17.1 逐一核對：
1. **外觀**：E-Ink 高對比開關（`EBSwitchRow`）／`ThemeSelector`（圓點版）／字型管理入口。✅ 三項與 §17.1 第 1 點完全相符。
2. **閱讀**：閱讀預設值入口／顯示頁首頁尾開關／翻頁與熱區入口／朗讀語音與語速入口。✅ 與 §17.1 第 2 點相符，四項全部存在。
3. **同步與帳號**：跨裝置同步入口（副標顯示「已登入・3 分鐘前同步」）。✅ 與 §17.1 第 3 點相符。
4. **關於**：關於 elinkBook 入口（副標「版本、授權、診斷（連點版號進入）」）。✅ 與 §17.1 第 4 點相符，且原型副標文字本身就直接標註了「連點版號進入診斷模式」這個隱藏彩蛋機制，與 §17.1「診斷功能移至此區塊，藏在連點版號之後」完全吻合。

**整體結論**：「設定」畫面是本次分析中，與 `DESIGN.md` 規格**吻合度最高**的畫面——四分區、各分區項目數量與內容，逐一核對皆相符，沒有發現任何 `[CONFLICT]`。

### Components
`AppBar`／`ThemeSelector`／`EBSwitchRow`／`SettingsListItem`，見 `COMPONENT_SPEC.md`。

### Spacing
各分區標題 `p-3 pb-0`，內容區 `p-3 flex flex-col gap-2.5`(12px + 10px 衝突值)。

### Responsive
❓ `[UNKNOWN]`，`DESIGN.md` §9.1 提及平板對話框最大寬度限制，但設定畫面本身在平板/桌機下是否套用 `maxContentWidth`（見本文件開頭「通用」章節）同樣未示範。

### States
純靜態清單，`Not defined in prototype` 涵蓋 loading（例如「跨裝置同步」點擊後的同步進行中狀態）。

### HTML source
`#view-settings`，第 787–890 行。
