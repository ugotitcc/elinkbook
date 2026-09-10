# epic-39-layout-settings-redesign：版面設定三畫面主題化＋E-Ink 步進器

## 背景

使用者透過 `/mattpocock-skills:grill-with-docs` 提出需求：「『版面設定』的各個畫面請依據 `prototype/elinkbook_theme_prototype.html` 修訂」。

Discovery（grilling）過程中發現兩個關鍵事實，改變了原始需求字面上的解讀：

1. **`elinkbook_theme_prototype.html` 本身在側邊欄明文寫著「版面設定四分頁邏輯與版面原封不動」**——也就是說，這個檔案裡的版面設定面板並不是這次主題重構（三主題＋E-Ink 修飾子）真正涵蓋的對象，其視覺樣式（純黑白、`border-black` 硬邊框）是原封不動沿用自更早的 `eink_redesign_prototype.html`（E-Ink 模式專屬原型），示範的其實是「E-Ink 模式下」的樣子，不是「一般主題下」的樣子。
2. **`DESIGN.md` §18.3「步進控制」明文規定**：E-Ink 模式下必須「禁用所有 Slider 元件」，字級/字重/行邊距等控制項「一律自動替換為 `EBStepper`（帶有 `-` 與 `+` 的離散點擊按鈕）」——但整個 App 目前沒有任何 `EBStepper` 元件（查證零個檔案），這條既有規則從未真正落地過。prototype 的版面設定面板之所以看起來是「純步進器、沒有可拖曳滑桿」，正是在示範這條從未實作的規則。

因此本 Epic 的真正範圍是：讓 `ReaderSettingsSheet`（EPUB）／`PdfSettingsSheet`（PDF）／`FxlSettingsSheet`（FXL）三個版面設定 Bottom Sheet，在**一般主題**下正確跟隨 `Theme.of(context)` 色彩系統（而非寫死黑白），並在**E-Ink 模式**下補齊 `DESIGN.md` §18.3 這條既有但未落實的「Slider→Stepper」規則；同時採納 prototype 面板裡幾項值得保留的視覺/資訊呈現改善（分頁重新命名分組、覆寫狀態改用文字徽章、預設集列表新增「目前套用中」標示）。

## 目標

1. 新建共用 `EBStepper` 元件，在 E-Ink 模式下取代現有的 Slider＋微調按鈕組合；一般主題下維持現有 Slider＋微調按鈕不變。範圍涵蓋 `_buildSliderRow` 承載的所有數值列，**以及** `ReaderSettingsSheet._buildColumnModeRow()` 內獨立宣告、未經過 `_buildSliderRow` 的 `reader_settings_column_size_slider`（審查修正，見 `design.md`「審查回應」）。
2. `ReaderSettingsSheet`／`PdfSettingsSheet`／`FxlSettingsSheet` 三者的卡片邊框、按鈕、文字色彩改為跟隨 `Theme.of(context)`（一般主題）或既有 E-Ink 高對比規則（`DESIGN.md` §17.2／§18），不再有任何寫死的黑白色值。
3. `ReaderSettingsSheet` 分頁重新命名分組：「文字內容／邊界首尾／版面呈現／設定喜好」→「文字／邊界／呈現／預設集」，「文字對齊」自「邊界」搬到「呈現」分頁。
4. `ReaderSettingsSheet` 各數值列的覆寫狀態，從圖示（封鎖圖示 reset 鈕／灰色停用圖示）改為文字徽章（如「此書已覆寫」／「使用全域預設」）。
5. `ReaderSettingsSheet` 預設集列表新增「目前套用中」視覺標示（整列反白，並以獨立指示器取代既有「套用到本書」按鈕，避免與該按鈕既有的 `Icons.check` 圖示並存混淆——見 `spec.md`「審查回應」I3），需比對目前草稿設定值是否與某已存預設集完全相等。
6. 單選按鈕群組（書寫方向／翻頁模式／螢幕方向鎖定／欄數／文字對齊／PDF Fit 模式等）維持既有 `ReaderOptionTile` 緊湊 chip／`Wrap` 排列邏輯，但每顆 chip 改為「小圖示＋≤2 字中文標籤」並排顯示，依可用寬度（`LayoutBuilder`）連續縮放，低於門檻時只顯示圖示。

## 明確排除範圍（Out of scope）

- 文字對齊維持全部 6 個選項（center/justify/start/end/left/right），**不**依 prototype 精簡為 3 個。
- 螢幕方向鎖定維持含「全域預設」的既有雙層覆寫語意（6 個選項），**不**依 prototype 拿掉「全域預設」變成 5 選一。
- 覆寫徽章**不**額外顯示實際的全域數值（如 prototype「全域為 16」那種具體數字），只顯示「已覆寫／使用全域預設」這種qualitative 文字，避免新增「讀取已解析全域預設值」的資料傳遞需求。
- 字型選擇器維持現有 `DropdownButton`，**不**改成 prototype 的「點擊循環切換」按鈕。
- 單選按鈕群組**不**改成 prototype 的「滿版等寬分段按鈕列」，維持現有 chip／`Wrap` 排列邏輯。
- `PdfSettingsSheet`（顯示/濾鏡/裁切）與 `FxlSettingsSheet`（無分頁）的既有分頁結構、功能項目**不變**，只做視覺風格對齊（含這兩者的數值控制項在 E-Ink 模式下比照套用 `EBStepper`）。

## Discovery 決策記錄

詳見同目錄 `design.md`（grilling 完整問答記錄）。

## 開發記錄

2026-09-08 Issue 1（新增共用元件 `EBStepper`／`EBOptionChipGroup`，擴充 `ReaderOptionTile` 支援 `iconSize`／`labelFontSize`／`forceUnselected`）完成並合併（PR #223）。本 Issue 僅新增元件本身，未觸碰任何既有呼叫端（`ReaderSettingsSheet`／`PdfSettingsSheet`／`FxlSettingsSheet` 改接留給 Issue 2-6）。程式碼審查（`reviews/review-issue-1-implementation.md`）：20 個新測試全數通過、`flutter analyze` 零警告、計畫審查意見 I1/I2/M1/M2 皆確認落實，無 Critical/Important 問題，Ready to merge = Yes。下一步：Issue 2（`ReaderSettingsSheet` 文字＋邊界分頁 Slider/EBStepper 切換與覆寫文字徽章）。
