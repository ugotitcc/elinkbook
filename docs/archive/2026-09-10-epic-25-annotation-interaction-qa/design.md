# Epic 25 — 劃線/備註真機互動精修：Discovery

## 緣起與範圍界定

延續 `epic-18-reader-device-qa`「真機 UI 精修」的第九輪真機使用回報（2026-08-12），使用者提出 4 項與**劃線/備註互動**相關的真機回報。`epic-18-reader-device-qa` 的 `issues.md` 此時已累積至 47 個 Issue、1200+ 行，`docs/epics.md` 單列敘述亦已過長；經與人類確認，拆分獨立新 Epic 承接本輪起的劃線/備註互動類真機回報，`epic-18-reader-device-qa` 保留原有 Issue 1-47 作為歷史紀錄不再新增。

## 第一輪真機使用回報（2026-08-12）

使用者於真機（Air Reader Pro C、TCL 14 吋等 E-Ink 裝置）閱讀流式 EPUB 時回報以下 4 項問題：

1. 畫線拖曳選取、控點（handle）已顯示於選取範圍左右兩側（即選取已確立）時，**Air Reader Pro C** 仍會出現頁面跳動，**TCL 14 吋**不會發生同一症狀。
2. 畫線的浮動工具列（`AnnotationToolbar`）在畫線位置偏螢幕右側時，工具列本體被裁切、看不到完整的 5 顆按鈕（附截圖 `tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg`）。
3. 選擇完畫線樣式（顏色/底線）後，工具列應該自動隱藏，或提供一個明確的按鈕可以主動關閉——目前只能透過點擊換頁間接關閉。
4. 點擊換頁的位置，若剛好與上一頁或下一頁「同一螢幕座標」處有畫線重疊，換頁後會立刻誤跳出「是否刪除畫線」的確認對話框（附截圖 `tmp/images/畫線問題/2-1...jpg`、`2-2...jpg`）。

## `/diagnose` 初步查證結果（原始碼層級，尚未實作修復）

依 `/diagnose` 技能規範（Phase 1-3：建立信心層級的假說），對 4 項回報分別查證：

### Issue 1（跳頁，裝置相關）—— 信心：中等，`needs-info`

理論上不屬於 `epic-18` Issue 47 修復範圍——Issue 47 的攔截器一旦偵測到 `selection.rangeCount > 0 && !selection.isCollapsed`（選取已確立）即主動放手，之後交由 `paginator.js` 既有守衛（`paginator.js:2191-2195`）處理。本項回報的正是「已確立」情境本身在特定裝置失效。

排序假說：
1.（最可能）視覺選取控點顯示與 `doc.getSelection()` JS 狀態同步之間有裝置相關的時間落差——與 Issue 47 根因同一類「JS 選取 API 落後於原生手勢視覺狀態」問題，只是發生在拖曳控點階段而非長按候選階段。
2. Air Reader Pro C 的 WebView 版本／觸控事件合併（coalesced events）行為與 TCL 14 吋不同（比照 `epic-18` Issue 33／38-41 已知部分機型 WebView 版本偏舊的既有模式）。
3. 兩者疊加。

無法建立 headless 迴圈驗證（真實硬體 WebView 選取控點拖曳行為的裝置差異，CDP 模擬不具代表性，與 Issue 47 診斷時發現的局限相同）。需要在 Air Reader Pro C 與 TCL 14 吋各自插樁（記錄拖曳過程中每個 `touchmove` 的 `selection.rangeCount`/`isCollapsed`/座標）差異比對後才能鎖定根因。

### Issue 2（工具列裁切）—— 信心：高，`ready-for-agent`

純幾何邏輯錯誤，已用原始碼＋使用者截圖交叉確認，不需額外重現。根因在 `reader_screen.dart:1970-1989`：垂直位置 `_annotationToolbarTop()` 有正確扣除工具列自身高度再 clamp（`size.height - _annotationToolbarHeight`），但水平位置 `left: (selection.rect.left * size.width).clamp(0.0, size.width)` 完全沒有扣除工具列自身寬度——起點一旦接近右邊界，工具列本體（5 顆按鈕）就會整個超出螢幕右側。EPUB（1972 行）與 PDF（1983 行）兩條路徑同構，皆有此問題。

修法：比照既有 `_annotationToolbarHeight`/`_annotationToolbarGap` 模式，新增 `_annotationToolbarWidth` 常數，`left` 也比照 `top` 的寫法 clamp 到 `size.width - _annotationToolbarWidth`。

### Issue 3（選色後應可關閉工具列）—— 設計決策，已與人類確認方向

不是傳統意義的 bug，是設計取捨：`_handleHighlightStyleSelected()`（`reader_screen.dart:1176`）刻意在建立劃線後不清空 `_currentSelection`，用意是讓使用者能緊接著點「備註」把新備註連結到剛建立的劃線（既定的「劃線+備註共存」使用者流程）。

**人類決定採用方向 (a)**：保留現有連續流程（選色後工具列預設仍打開，備註仍可接續點擊），額外加一顆明確的「✕ 關閉」按鈕，讓使用者可以主動關閉工具列而不必依賴換頁。

### Issue 4（換頁誤觸刪除畫線對話框）—— 信心：中高，`needs-triage`（待建立 harness 驗證）

原始碼層級機制清楚：vendored `view.js:438-445` 用**原生 `click` 事件**（`doc.addEventListener('click', e => { hitTest(e) ... })`）做畫線點擊偵測，而 `paginator.js` 的換頁是自己的 `touchstart`/`touchmove`/`touchend` 手勢邏輯驅動、在 `touchend` 當下就立即完成視覺換頁。瀏覽器的合成 `click` 事件在觸控裝置上是 `touchend` **之後才延遲觸發**的相容性事件——這時頁面視覺上已經換到新頁，`click` 事件座標卻拿去對「新頁面此刻的內容」做 `hitTest()`，如果新頁同一螢幕座標剛好也有畫線，就誤判成「使用者點擊了這筆畫線」而彈出刪除確認。與 Issue 47 是同一類「vendored 觸控換頁邏輯 vs 瀏覽器原生延遲事件」的競速問題，但這次競速的對象是 `click` 而非 `touchmove`。

由於機制清楚且可用 CDP 觸控注入＋控制兩頁畫線座標重疊來確定性重現（比照 Issue 47 的 harness 手法），建議另立分支建立可信重現迴圈後再定案修法（可能方向：仿照 Issue 47，在 capture 階段追蹤「這次觸控是否驅動了換頁」，若是則短暫抑制緊接著的合成 `click`）。

## 下一步

拆解為 Issue 1-4（對應本文件 4 項回報，見 `issues.md`），依信心層級分別標註 `ready-for-agent`／`needs-triage`／`needs-info` 進入後續 Planning。
