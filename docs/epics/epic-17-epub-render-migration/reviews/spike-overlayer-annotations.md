# Epic 17 Issue 7 — Spike：劃線/備註可行性驗證（overlayer.js）報告

**驗證日期：** 2026-07-21（Task 1-5 主測試與所有 logcat 時間戳皆落於此日；Task 4 追加二〔裝置人工解鎖後的真機重新驗證〕為同一驗證流程的延續作業）
**驗證裝置：** `adb devices -l` → `3CEF42ECD491687  device product:9491G_ZZ model:9491G device:Hera_Vis_WIFI`（與 Issue 1 Spike 同一台實體裝置，Android 15／API 35）；`adb shell wm size` → `Physical size: 1600x2400`（與 Task 1-5 brief 假設的座標系一致，無需額外比例換算）
**釘定 commit：** `dd71f2be356563c16a23272686189fcfb45d0b82`（與 Issue 1 同一版本）
**測試素材：** `app/test/fixtures/issue9_vertical_pagejump.epub`

## 研究問題 #1：多色劃線＋獨立螢光筆子類型（Task 3）

**結論：成立，但依 brief Step 1 原樣程式碼在真機上第一次執行時完全看不到任何標記——這是一個真實的既有 API 陷阱，已定位根本原因並修正，修正後在真機上肉眼確認繪製正確。**

`Overlayer.highlight`／`Overlayer.underline` 本身的繪製邏輯經證實是正確的：修正後的最終截圖 `task3fix2_annotated.png` 中，紅／綠／藍紫三色半透明螢光筆矩形清楚可辨、正確沿直排欄位分布，黑色底線也確實可見（緊貼文字右側、寬約 2px 的細直線）。底線方向以 CDP 讀出的 SVG `<rect>` 幾何屬性客觀證實：4 個矩形皆為 `width:2px`、`height` 介於 134～380px（高達寬的數十倍），與 `overlayer.js` 對 `writingMode === 'vertical-rl'` 分支的邏輯完全吻合，代表底線沿垂直方向繪製、貼齊文字，而非橫排時該有的貼底橫線。

但 brief 原樣程式碼（`range.selectNodeContents(paragraph)` → `view.getCFI()` → `view.addAnnotation()`）第一次真機執行時，logcat 顯示 4 筆 `OVERLAYER_DRAW_ANNOTATION`／`OVERLAYER_ANNOTATION_ADDED` 皆正常觸發、CFI 格式正確，但截圖 `spike7-task3-annotations.png` 上完全沒有任何可見標記。用 Chrome DevTools Protocol（`adb forward` 到 WebView remote debugging）現場檢視即時 DOM/SVG 狀態後，鎖定兩個疊加的根本原因：

1. **CFI round-trip 會把整段落 Range 壓扁成 collapsed（零寬度）**：`range.selectNodeContents(<p>)` 產生的 Range，start/end 邊界都落在同一個 `<p>` 元素節點上（僅 offset 不同：0 vs `childNodes.length`）。追蹤 `epubcfi.js` 的 `partToString()` 後確認：CFI 序列化格式只有在 step index 為奇數（文字節點）時才輸出 `:offset`；`<p>` 是元素節點、其 step index 必為偶數，所以這個唯一能區分 start/end 的 offset 被靜默捨棄，start 與 end 序列化成完全相同的字串（實測即為 `.../8` 與 `.../8` 一模一樣）。往返解析回 Range 後兩端自然重合、`collapsed:true`，`getClientRects()` 回傳空陣列，`Overlayer.highlight`/`underline` 因此畫出「空的 `<g>`」——不拋錯、log 全部正常，但視覺上什麼都沒有。
2. **`'load'` 事件對 look-ahead 預讀章節同樣會觸發，導致 `currentDoc`/`currentIndex` 快取值指向使用者根本還沒看到的章節**：4 筆標記記錄的 section 是 `story-2-4`，但當時畫面上實際顯示的是 `story-2-2`（差 2 個 section）。

**修正**（人類已確認方向：保留 `addAnnotation()` 這條正式 API 路徑，不採用「繞過 CFI、直接餵未序列化 Range 給 `overlayer.add()`」的診斷捷徑作為交付版本）：
- 改用 `getTextNodes()` 走訪段落內部文字節點，`range.setStart(firstText, 0)` / `range.setEnd(lastText, lastText.length)`，Range 邊界落在文字節點（奇數 step index），CFI 序列化時 offset 不再被捨棄，round-trip 不再壓扁。
- 改用 `view.lastLocation.section.current` 與 `view.lastLocation.range`（renderer 依「目前視窗實際可見範圍」算出的即時查詢，而非 `'load'` 事件快取的模組級變數）判斷「目前真正顯示的章節與可視範圍」，並用 `visibleRange.intersectsNode(p)` 篩掉同一 section 內、存在於 DOM 但不在目前可視分頁的段落（一個 section 的 CSS 內容高度常遠大於單頁可視高度，`querySelectorAll('p')` 會抓到整個 section、不只目前這一頁）。

兩項修正合併上機後，logcat 顯示 4 筆 CFI 皆 start≠end（例如 `epubcfi(/6/8!/4[story-2-2]/22,/1:0,/5:1)`），截圖 `task3fix2_annotated.png` 首次在肉眼可見層級證實 4 種標記透過正式 `addAnnotation()` API 路徑正確繪製。

## 研究問題 #2：選取範圍即時回報螢幕座標百分比（Task 4）

**結論：成立——座標換算公式（iframe-local rect + iframe 相對外層文件的位移，除以外層可視尺寸）本身正確，經真機原生長按拖曳手勢與程式化退路兩條路徑分別交叉驗證通過。但過程中同樣先踩到與研究問題 #1 同源的「共用可變變數」陷阱，需要修正才能觀察到公式本身是否正確。**

第一輪真機測試（`adb shell input swipe` 模擬長按拖曳）：畫面上**確實**出現選取控點（把手）與「複製／分享／全部選取／朗讀」選字工具列（`spike7-task4-longpress.png`），證實 `adb input swipe` 可穩定觸發 Android WebView 原生長按選字模式。但 `OVERLAYER_SELECTION_CHANGED` 完全沒有被記錄。追查發現：brief 原文程式碼在 `'load'` handler 內對 `e.detail.doc`（正確的 target）掛上 `selectionchange` 監聽器，但 callback **內部**讀取的是模組級共用變數 `currentDoc`，而非該次 `'load'` 呼叫私有的閉包參照——執行到 callback 的當下，`currentDoc` 已被後續 `'load'`（look-ahead 預讀的 index 4、5）覆寫，導致 `currentDoc.getSelection()` 查詢的是錯誤、非可見的 doc（無選取內容），在 `rangeCount === 0` 處被靜默 return。程式化退路（`Selection.addRange()`）也命中同一類問題：`leftPct`/`rightPct` 落在合理 0-1 範圍，但 `topPct`/`bottomPct` 高達 4.6～4.9（遠超畫面），截圖比對確認選中文字根本不在畫面上——`#btn-select-fallback` 的 click handler 同樣讀取過時的 `currentDoc`，選到的段落存在於 DOM 但不在目前可視分頁。

**修正**：
1. `'load'` handler 內為每次呼叫建立區域變數 `doc`/`index`（`const doc = e.detail.doc`），`selectionchange` callback 改讀這兩個區域變數（閉包凍結參照），不再讀取模組級共用變數。
2. `#btn-select-fallback` 改用 `view.lastLocation.section.current` + `view.renderer.getContents()` 找出目前實際可視的 doc；第一版仍用 `visibleRange.intersectsNode(p)` 篩選後 `selectNodeContents(paragraphs[0])`，真機測試又暴露一個更深的陷阱：`intersectsNode` 只保證段落「部分」與可視範圍重疊，若段落起點落在可視範圍之前，`getClientRects()[0]` 仍會取到看不見的第一行（`topPct`/`bottomPct` 出現負值）。最終版直接使用 `visibleRange.cloneRange()` 本身作為選取範圍，不再另外尋找段落。

裝置在追加修正過程中一度因閒置逾時進入安全鎖（PIN/圖案），adb 無法繞過，該次驗證誠實回報 BLOCKED；使用者人工解鎖裝置並延長螢幕逾時後完成最終真機重新驗證：
- Step 2（真機長按拖曳）：`OVERLAYER_SELECTION_CHANGED {"index":3,"text":"出版社","leftPct":0.4806,"topPct":0.5687,"rightPct":0.5206,"bottomPct":0.6262}`，換算回像素（x:769–833px、y:1365–1503px）與截圖 `task4b_longpress.png` 中「出版社」二字被反白選取的實際畫面位置吻合。
- Step 3（程式化退路，最終版）：`leftPct:0.854, topPct:0.0686, rightPct:0.894, bottomPct:0.4315`，全部落在合理 0-1 範圍，換算像素與截圖 `task4c_fallback.png` 的灰底選取範圍完全吻合。

兩條路徑均已用真機證實：座標換算公式正確，前提是餵給它的 doc/Range 必須是「目前真正可視」的那一個。

## 研究問題 #3：點擊既有標記可靠觸發回呼並識別正確 id（Task 5）

**結論：成立。4/4 個真實標記逐一測試，各自觸發恰好一筆 `show-annotation` 事件，回報的 CFI 與建立時的 CFI 逐字元完全相同，無誤判、無重複觸發；無標記區域的負面對照正確地未觸發任何回呼。**

| 標記 | 點擊座標 | `OVERLAYER_SHOW_ANNOTATION` 的 `value` | 與建立時 CFI 比對 |
|---|---|---|---|
| 綠色 | `(835,600)` | `epubcfi(/6/8!/4[story-2-2]/24,/1:0,/1:65)` | 完全相同 |
| 藍色 | `(540,600)` | `epubcfi(/6/8!/4[story-2-2]/26,/1:0,/3:27)` | 完全相同 |
| 底線（黑） | `(310,250)`，第一次即命中 | `epubcfi(/6/8!/4[story-2-2]/28,/1:0,/1:42)` | 完全相同 |
| 紅色 | `(1069,600)`（詳見下方唯一複雜情況） | `epubcfi(/6/8!/4[story-2-2]/22,/1:0,/5:1)` | 完全相同 |

負面對照：`(700,1500)`（該點像素值確認為純白、位於不受任何按鈕影響的自由區）點擊後，`OVERLAYER_SHOW_ANNOTATION`／整個 `OVERLAYER_SPIKE` tag 過濾皆為 0 筆輸出，證實 `hitTest()` 對無標記區域不會誤觸發。

**唯一複雜情況（非 `hitTest()` 缺陷，但對正式 App 有意義的發現）**：紅色標記第一次用近似座標 `(1398,600)` 點擊時，並未觸發 `show-annotation`，而是觸發了 `OVERLAYER_TRIGGER {"direction":"next"}`——App 意外翻頁。追查 `index.html` 發現 harness 的 `#btn-next` 是一個 `z-index:10`、覆蓋螢幕右側 33% 寬×70% 高（換算 1600×2400 即 x:[1072,1600]、y:[360,2040]）的隱形全高按鈕，疊在 WebView 之上。用像素掃描量出紅色標記矩形實際範圍約 x:[1066,1430]——幾乎整個紅色標記都落在 `#btn-next` 的攔截範圍內，點擊事件在到達 WebView/`hitTest()` 之前就被按鈕攔截了。改用貼齊按鈕邊緣外側的窄縫座標 `(1069,600)` 後才成功命中，`hitTest()` 本身正確識別出紅色標記的 CFI。這證實研究問題 #3 原文所關切的「`hitTest()` 5 CSS px 容許誤差在本次裝置實體像素下是否足夠」這件事，在本次測試中從未真正被觸發到（3/4 標記都是第一次座標就直接命中，未依賴容許誤差微調）；唯一需要調整座標的紅色案例，調整量高達 -329px，性質上是「按鈕整層攔截」而非「hitTest 邊界容錯」問題。

## 已記錄的既有 API 落差（供 Issue 8 依循）

- **`Overlayer.highlight`／`Overlayer.underline` 的 options 形狀不一致**（`Overlayer.highlight(rects, {color, vertical: boolean})` vs `Overlayer.underline(rects, {color, writingMode: string})`）：本次驗證程式碼中兩者呼叫方式確實不同形狀（`vertical:true` vs `writingMode:'vertical-rl'`），此落差在 Issue 7 工單描述階段即已知、本次驗證確認屬實。Issue 8 實作 `FoliateEpubReaderView.kt` 的橋接邏輯需要依 `isUnderline` 分別組裝正確形狀的 options，不能共用同一組參數物件。
- **`Overlayer` 以 `annotation.value` 當 Map key，必須唯一**：本次驗證中每筆測試標記使用的 CFI 值天生互不相同（不同段落），未實際遇到重複 key 的情境，因此本次驗證未能實測「兩筆標記共用同一 CFI」時的行為。Issue 8 設計標記 id/CFI 產生邏輯時仍須保證唯一性作為前提假設，建議在正式實作階段另補一則針對此邊界情況的單元測試，而非假設本 Spike 已涵蓋。
- **CFI round-trip 對元素層級 Range（`selectNodeContents(element)`）會靜默壓扁成 collapsed**：`epubcfi.js` 的 CFI 序列化格式只在文字節點（奇數 step index）才保留 offset，元素節點（偶數 step index）的 offset 會被捨棄，導致 start/end 序列化成相同字串、往返解析後兩端重合。不拋錯、log 全部正常，只有視覺上「什麼都沒畫出來」。Issue 8 任何會建構 Range 交給 `view.getCFI()`/`view.addAnnotation()` 的程式碼，都必須用文字節點邊界（`range.setStart(textNode, offset)`/`setEnd(...)`），不可用 `selectNodeContents(element)`。這對「使用者現場選字建立劃線」的情境影響較小（`window.getSelection()` 取得的 Range 天然就是文字節點邊界），但對「批次還原已存標記」「以段落/元素為單位程式化建立標記」等情境是必須遵守的硬性限制。
- **`'load'` 事件對 look-ahead 預讀的（畫面上尚未顯示的）章節同樣會觸發，導致依賴 `'load'` 事件快取的模組級變數（`currentDoc`/`currentIndex`）在讀取當下可能已經過時、指向錯誤 doc**：本次驗證中，這個陷阱在研究問題 #1（`addTestAnnotations()`）與研究問題 #2（`selectionchange` callback、`#btn-select-fallback`）兩條完全獨立的程式碼路徑上各自獨立命中一次，證實不是單一程式碼的巧合，而是這個 API 使用模式本身的系統性風險。Issue 8 需要「目前畫面上實際顯示的內容」時，一律改用即時查詢（`view.lastLocation.section.current`／`view.lastLocation.range`，或至少 `view.renderer.primaryIndex`），不可快取 `'load'` 事件的 `e.detail.doc`/`e.detail.index` 到模組級/物件級的共用可變變數後於事後讀取；若監聽器必須掛在 `'load'` handler 內部（例如 `selectionchange`），callback 內部也必須讀取該次呼叫私有的區域變數（閉包凍結），不可讀取共用變數。
- **Harness 導覽熱區與可標記內容區域重疊會攔截點擊，使事件根本傳不到 `hitTest()`**：本次驗證用的 throwaway harness 為求方便設計了覆蓋螢幕左右各 33% 寬、70% 高的隱形導覽按鈕（`#btn-prev`/`#btn-next`），恰好與其中一個標記的螢幕位置重疊，導致該標記第一次點擊被按鈕攔截、觸發意外翻頁而非 `show-annotation`。這不是 `Overlayer.hitTest()` 本身的缺陷（換一個不重疊的座標後，同一個標記立即被正確命中），但是一項對 Issue 8／正式 App 有意義的設計提醒：**九宮格導覽/操作熱區的佈局，不得與可能出現可標記內容的區域無條件重疊**，否則會產生「`hitTest()` 邏輯完全正確、標記確實存在，但使用者的點擊永遠傳不到它」的隱藏缺陷。Issue 8 實作正式 App 的 3×3 熱區系統時，需要明確的熱區優先權/穿透規則（例如：熱區只在確認「該點擊未命中任何標記」後才觸發導覽），而非依賴熱區與內容區域自然不重疊的僥倖假設。

## 風險分級與後續建議

**結論：ADR 0011（劃線/備註完整涵蓋在 Phase 1 範圍）維持不變，不需要人類重新確認範圍。**

三項研究問題最終皆得到正面驗證：`Overlayer.highlight`/`underline` 的視覺繪製正確（多色可辨、底線方向正確）、座標換算公式正確（真機手勢與程式化退路雙重交叉驗證通過）、`hitTest()`/`show-annotation` 對既有標記的識別可靠且無誤判（4/4 正確、負面對照通過）。`overlayer.js` 這組 API 本身足以支撐 Phase 1 的劃線/備註功能，沒有發現任何一項會動搖「完整涵蓋在 Phase 1」這個既有決策的結構性缺陷。

但這個正面結論是**修正過陷阱之後**才成立的，不是 brief 原樣程式碼、也不是「顯而易見」的用法第一次就能得到的結果——研究問題 #1 與 #2 都各自在第一輪真機測試中得到「畫面上什麼都看不到」或「log 完全沒有記錄」的誠實負面結果，根本原因分別追查到 `epubcfi.js` 序列化格式的一個具體機制缺陷（元素層級 Range 的 offset 被靜默捨棄）與 `'load'` 事件搭配模組級共用變數的一個系統性使用陷阱（在兩條獨立程式碼路徑上各自獨立重現）。這兩者都不是「讀了官方文件就能避開」的問題，而是要透過真機執行 + CDP 即時檢視 DOM/SVG 狀態才能定位的隱性行為。研究問題 #3 額外發現的熱區攔截問題，雖非 `Overlayer` 本身缺陷，但同樣是「表面上邏輯正確、實際整合時會失效」的一類風險。

因此，本 Spike 的風險分級判斷是：**核心 API 能力驗證通過（GO），但 Issue 8 必須把本報告記錄的三項具體修正方式當作硬性實作約束，不能重新落入相同的陷阱**：

1. **建構供 `view.getCFI()`/`view.addAnnotation()` 使用的 Range 時，一律用文字節點邊界（`setStart`/`setEnd` 在 text node 上），不可對段落/元素節點呼叫 `selectNodeContents()`。** 這是 CFI 序列化格式的結構性限制（偶數 step index 的 offset 會被捨棄），不是本次測試手法的偶然失誤。
2. **判斷「目前畫面上實際顯示的是什麼」時，一律使用即時查詢（`view.lastLocation`/`view.renderer.primaryIndex`），不可依賴 `'load'` 事件快取到模組級/物件級共用變數後於事後讀取；掛在 `'load'` handler 內部的監聽器，callback 內部也必須讀取該次呼叫私有的區域變數，不可讀取共用變數。** 這個陷阱在本次驗證的兩條獨立程式碼路徑上各自獨立命中，屬於系統性風險而非個案巧合。
3. **正式 App 的 3×3 熱區佈局設計，必須明確處理熱區與可標記內容區域重疊時的優先權/穿透規則**，不能假設兩者天然不會重疊；否則會產生使用者點擊永遠無法命中標記的隱藏缺陷，且這類缺陷不會被 `Overlayer.hitTest()` 自身的單元測試發現（因為問題發生在事件傳遞到 `hitTest()` 之前）。
4. **`Overlayer.highlight`/`underline` 的 options 形狀差異（`vertical` vs `writingMode`）需要在橋接層依 `isUnderline` 明確分流組裝**，不可用同一組參數物件呼叫兩者。

以上四點已在「已記錄的既有 API 落差」一節詳述具體症狀與程式碼層級的修正方式，Issue 8 實作者應直接依循，不需要重新從頭診斷。
