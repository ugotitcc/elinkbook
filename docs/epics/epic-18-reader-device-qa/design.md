# Epic 18 — 真機 UI 精修（版面設定/工具列/書架/直排邊距）：Discovery

## 背景

2026-07-24，使用者在多款真實裝置（含 E-Ink 閱讀器 AiPaper Reader C，824×1648／150 PPI；以及 1404×1872／300 PPI 黑白、702×936／150 PPI 彩色兩款既有測試裝置）上實際使用 App 閱讀，回報 8 項問題。這些問題橫跨已歸檔的多個既有 Epic 的既有功能（`epic-1-library` 書架、`epic-3-fonts-layout` 版面設定、`epic-7-interaction` 閱讀器工具列、`epic-17-epub-render-migration` 直排 CSS/分頁），不隸屬單一既有 Epic，故另立新 Epic 統一追蹤，比照 `docs/epics.md`「任務分類」既有慣例（跨既有功能的真機發現，量級足以獨立成 Epic，非單一 Bug 修復）。

## 使用者回報的 8 項問題（原文摘要）

1. 「版面設定」畫面在 824×1648／150 PPI 裝置上變成滿版、無法退出，需要加入 X 取消按鈕；調整後需確認 1404×1872／300 PPI（黑白）與 702×936／150 PPI（彩色）兩款既有裝置仍正確顯示。
2. 上下工具列高度太高，佔用太多版面，需縮短。
3. 書架首頁封面格數：直立時應為 3 本一行、橫放時應為 4 本一行（原為固定 6 本一行），範例參考 `tmp/sample/書櫃首頁範例.png`。
4. 分類顯示應直接內嵌於書籍清單中，一個分類佔一格、格內以 2×2 拼貼顯示該分類前 4 本書封面。
5. 頁尾「進度 YY% ｜ 第 XXX/OOO 頁」文字列與拖曳進度捲軸分成上下兩列，佔用空間過多。
6. 直排模式下，畫面上緣文字被壓／裁切，版面應往下留白。
7. 本文顯示區域下緣與頁尾進度列之間空白過多（約多出一行可用空間）。
8. 切換為「直排」時，部分書籍會被拆成「上下 2 欄」，需要多一次翻頁才能看完原本一頁的內容，需要提供選項讓使用者可設定為強制單欄。

## 調查結論（人類確認前的初步定位，見 `issues.md` 各 Issue「描述」段落逐項展開）

- 項目 1、3、5 是既有 widget 的既有寫死行為（無關閉按鈕／固定格數／固定兩列版面），改動範圍侷限在單一 Dart widget 檔案，風險低。
- 項目 2（工具列高度）與項目 5（頁尾合併單行）指向同一塊「閱讀畫面上下工具列太占空間」的抱怨，且項目 5 的「合併單行」正是達成項目 2 頁尾瘦身的具體手段，兩者合併為同一個 Issue 處理（`AppBar.toolbarHeight` + `ReaderFooter` 版面重構）。
- 項目 6、7 同源：`readest/foliate-js` 的 `paginator.js` 內建 `--_margin-top`／`--_margin-bottom` 皆寫死 `48px`（`paginator.js:1232/1234`），`main.js` 的 `buildOverrideCss()`（`pageMargins` 偏好）只處理左右 `body { padding }`，從未把使用者的邊距偏好或頁尾實際佔用高度接到這兩個 CSS 自訂屬性——上緣裁切與下緣空白過多是同一個「上下邊距從未被正確計算」問題的兩種症狀，合併為同一個 Issue。
- 項目 8 根因是 `paginator.js` 內建 `--_max-column-count: 2`（`paginator.js:1238`），該行為本身不是缺陷（是 foliate-js 既有的「單頁最多幾欄」機制），但目前完全沒有接上任何使用者可調整的偏好；`attributeChangedCallback()`（`paginator.js:1545-1559`）已經原生支援 `margin-top`／`margin-bottom`／`max-column-count` 三個屬性透過 `view.renderer.setAttribute()` 外部設定，不需要修改 vendored 檔案本身。
- 項目 4（分類 2×2 拼貼方格）目前完全不存在對應 UI/查詢邏輯，量級與其餘 7 項不同（需要新 widget、新查詢、新互動設計），經人類確認後**拆出，不在本 Epic 範圍**，留待未來評估是否另立 Epic。

## 決策（人類已確認）

1. **項目 4 不在本 Epic 範圍**，另外安排。
2. **項目 2 工具列高度**：縮減至約現有高度的 **1/3**（非 1/2）。
3. **項目 8 強制單欄**：新增布林偏好，加入既有「⚙️版面設定」（`ReaderSettingsSheet`）畫面，**預設關閉**（維持 foliate-js 原有的自動判斷行為，使用者遇到問題時才手動開啟）。

## 範圍界定

- 僅涵蓋前述 7 項（項目 1/2/3/5/6/7/8），對應 `issues.md` 的 5 個工單（項目 2+5 合併、項目 6+7 合併）。
- 不修改 `readest/foliate-js` 釘定版本本身（`view.js`／`paginator.js`／`overlayer.js` 等 vendored 檔案）——項目 6/7/8 皆透過既有 `attributeChangedCallback()` 支援的外部 `setAttribute()` 機制達成，僅修改本專案自己的 `main.js` 進入點與 Dart／Kotlin 偏好傳遞管線。
- 不改變 `BookReaderPrefs` 既有欄位的既有語意，項目 8 新增欄位比照既有 `showHeader`/`showFooter` 等「單書覆寫、無全域預設層」欄位的既有慣例（見 `book_reader_prefs.dart:43-44`）。

## 測試裝置

- `3CEF42ECD491687`（9491G，Android 15／API 35）——本專案既有測試裝置。
- 使用者回報環境：AiPaper Reader C（824×1648／150 PPI）、既有測試裝置 1404×1872／300 PPI（黑白）、702×936／150 PPI（彩色）——項目 1 的驗收需在這三種尺寸/密度下確認版面設定畫面皆可正確顯示與關閉。
