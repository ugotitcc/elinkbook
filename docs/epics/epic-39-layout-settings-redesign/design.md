# design.md — epic-39-layout-settings-redesign

Discovery 階段透過 `/mattpocock-skills:grill-with-docs`（grilling + domain-modeling）與使用者確認的完整決策記錄。原始需求：「『版面設定』的各個畫面請依據 `prototype/elinkbook_theme_prototype.html` 修訂」。

## 研究發現（Claude Code 自行查證，非使用者提供）

- `elinkbook_theme_prototype.html` 側邊欄明文：「版面設定四分頁邏輯與版面**原封不動**」——這份面板不是該次主題重構的對象，樣式繼承自 `eink_redesign_prototype.html`（E-Ink 模式專屬原型）。
- 該面板整個容器寫死 `bg-white`，每個控制項 `border-black`／選中態 `bg-black text-white`，完全不隨 `data-theme`／`data-eink` 屬性變化。
- `DESIGN.md` §18.3「步進控制」：E-Ink 模式下「禁用所有 Slider 元件」，字級/字重/行邊距等控制項「一律自動替換為 `EBStepper`」——App 內查無任何 `EBStepper` 元件實作（zero files），此規則從未落地。這解釋了 prototype 面板「純步進器、無可拖曳 Slider」的真正成因：它示範的是 E-Ink 模式，不是一般主題。
- `ReaderOptionTile`（現有單選 chip 元件）已經是主題感知的（依 `Theme.of(context).colorScheme` 取色，E-Ink 時特判純黑白），只是版面設定 Bottom Sheet 外層的 `Slider`／`SwitchListTile`／卡片邊框沒有統一走過這條路。
- `PdfSettingsSheet`（顯示/濾鏡/裁切三分頁）與 `FxlSettingsSheet`（無分頁）內容完全是 PDF/FXL 專屬（影像濾鏡、裁切、封面獨立顯示），prototype 這份面板只涵蓋 EPUB 流式排版概念，兩者沒有逐項對照基礎。
- `PdfSettingsSheet`／`FxlSettingsSheet` 皆無「全域/單書覆寫」雙態語意（無 null-based override 欄位），Q4 的「覆寫徽章」不適用於這兩者，只做純視覺風格對齊。

## 第一輪問答

| # | 問題 | 決策 |
|---|------|------|
| Q1 | 範圍：只有 `ReaderSettingsSheet`，還是也含 `PdfSettingsSheet`／`FxlSettingsSheet`？ | **三者皆納入**；後兩者只做視覺風格對齊，維持既有內容項目 |
| Q2 | 色彩來源：套用 prototype 視覺骨架但走 App 現有 `Theme.of(context)` 色彩系統（A），還是嚴格照抄 prototype 目前寫死黑白（B）？ | **(A)** 一般主題跟隨 Theme，E-Ink 模式維持既有黑白高對比規則 |
| Q3 | 數值控制項：保留 Slider＋微調鈕，只換外觀（推薦），還是整個改成 prototype 純步進器？ | 一開始選「保留 Slider」，**後續發現 DESIGN.md §18.3 後修正**：見下方「Q3 修正」 |
| Q4 | 覆寫狀態呈現：圖示 vs 文字徽章？ | **文字徽章**（如「此書已覆寫」／「使用全域預設」），取代現有封鎖圖示 |
| Q5 | 分頁重新分組與更名？ | **採用**：「文字內容／邊界首尾／版面呈現／設定喜好」→「文字／邊界／呈現／預設集」；「文字對齊」自「邊界」搬到「呈現」 |
| Q6(a) | 文字對齊選項數：prototype 3 個 vs 現有 6 個？ | **維持 6 個全保留**（不精簡） |
| Q6(b) | 螢幕方向鎖定：prototype 5 個（無「全域預設」）vs 現有 6 個？ | **保留「全域預設」**，維持既有雙層覆寫語意 |
| Q7 | 預設集列表「目前套用中」視覺標示？ | **新增**（整列反白＋勾勾，需比對草稿值是否與某預設集完全相等） |

## Q3 修正（重要）

查證 `DESIGN.md` §18.3 後發現：E-Ink 模式下必須禁用 Slider、改用 `EBStepper`，但此規則從未實作。與使用者確認後修正為：

- **一般主題**：保留現有 Slider＋左右 ± 微調按鈕，只換外觀為卡片邊框風格（邊框色/寬度/圓角規範見下方「審查回應」）。
- **E-Ink 模式**：新建共用 `EBStepper` 元件（純 `-`／數值／`+`，無可拖曳滑桿），`ReaderSettingsSheet`／`PdfSettingsSheet` 在 E-Ink 開啟時動態切換過去，補實作 `DESIGN.md` §18.3。**範圍涵蓋所有現有 Slider**，包含 `_buildSliderRow` 承載的欄位（字級/字重/行高/段落間距/字距/四邊邊界/PDF 對比度亮度加粗）**以及** `_buildColumnModeRow()` 內獨立宣告、未經過 `_buildSliderRow` 的 `reader_settings_column_size_slider`（`reader_settings_sheet.dart:569-585`，Discovery 首輪查證遺漏，見下方「審查回應」）。
- 追加問題「E-Ink 模式下的 Slider→EBStepper 切換要不要納入這次範圍？」→ **納入**（不另開工單）。

## 第二輪問答

❓ **Q8** - 單選按鈕群組（書寫方向／翻頁模式／螢幕方向鎖定／欄數／文字對齊等）呈現方式：現有緊湊 icon chip（`Wrap`，文字只在 tooltip）vs prototype 滿版等寬文字按鈕列？

➡️ 使用者澄清：**維持現有 chip／`Wrap` 排列邏輯**（不改成滿版等寬按鈕列），但每顆 chip 改為「小圖示＋文字並列」，文字濃縮在 **2 個中文字以內**；圖示與文字大小**依可用寬度自動縮放**（比照 `library_screen.dart` 既有的 `LayoutBuilder` 慣例，非 `MediaQuery` 裝置寬度）——放大有上限，縮小低於某門檻時只顯示圖示（沿用既有 tooltip 機制保留可存取性）。**具體門檻數值由實作者依 `DESIGN.md` 既有字級 Token（`labelSmall` 11sp／`labelMedium` 13sp，圖示預設 20sp）決定，非使用者需要指定的部分**。

❓ **Q9** - 覆寫徽章要不要秀出實際全域數值（如 prototype「全域為 16」）？

➡️ **不秀**，只做「使用全域預設／此書已覆寫」這種 qualitative 文字徽章，不需要新增資料傳遞（`ReaderSettingsSheet` 目前沒有全域預設值來源）。

❓ **Q10** - 字型選擇器：維持 `DropdownButton` vs 改成 prototype 的循環切換按鈕？

➡️ **維持 `DropdownButton`**，只改外觀（卡片邊框風格），因清單項目多時循環切換體驗較差。

## 最終確認

使用者於彙整摘要後回覆「OK」確認全部理解正確，並選擇「走完整 SDD 流程」推進（範圍涉及新共用元件 `EBStepper`、三個既有檔案、多項既有測試需同步調整）。

## 審查回應（2026-09-08，`reviews/review-design.md`）

- **I1（`_columnSize` 獨立滑桿遺漏）**：已修正上方「Q3 修正」段落，明確納入 `reader_settings_column_size_slider` 的 E-Ink 步進器範圍。
- **I2（一般主題卡片邊框 Token 未界定）**：補充規範——一般主題沿用既有 `ReaderOptionTile` 慣例：非選中態邊框 `colorScheme.outline.withValues(alpha: 0.35)`、寬度 `1.0dp`、圓角 `BorderRadius.circular(8)`；E-Ink 模式遵循 `DESIGN.md` §18.5，純黑 `1.5dp` 邊框。此規範已寫入 `spec.md`。
- **M1（晶片寬度縮放與 `Wrap` 折行衝突）**：已在 Architecting 階段（`spec.md`）修正演算法，改依容器絕對寬度（而非除以項目數）評估，避免與 `Wrap` 折行特性矛盾，詳見 `spec.md` 審查回應。
