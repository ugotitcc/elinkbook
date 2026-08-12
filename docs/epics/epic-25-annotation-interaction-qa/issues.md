# Epic 25 — 劃線/備註真機互動精修：工單清單 (Issues)

依 `design.md`「第一輪真機使用回報」（2026-08-12，4 項回報）拆解為 Issue 1-4。全部工單彼此獨立、無依賴關係，可任意順序或平行開始。

---

## Issue 1：畫線選取已確立仍跳頁（裝置相關——Air Reader Pro C 會、TCL 14 吋不會）

**Status:** `needs-info`——需要真機插樁資料才能繼續，暫無法建立 headless 重現迴圈。

**依賴：** 無

**背景：** 使用者回報：畫線拖曳選取、控點（handle）已顯示於選取範圍左右兩側（即選取已確立）時，Air Reader Pro C 仍會出現頁面跳動，TCL 14 吋不會發生同一症狀。

**與 `epic-18` Issue 47 的關係：** Issue 47 的攔截器一旦偵測到 `selection.rangeCount > 0 && !selection.isCollapsed`（選取已確立）即主動放手（`main.js` 的 `longPressGateState = null; return`），之後交由 `paginator.js` 既有守衛（`paginator.js:2191-2195`）處理。本項回報的正是「已確立」情境本身在特定裝置失效，理論上不屬於 Issue 47 修復範圍。

**根因假說（排序，皆未經真機驗證）：**

1.（最可能）視覺選取控點顯示與 `doc.getSelection()` 的 `rangeCount`/`isCollapsed` JS 狀態同步之間，在該機型 WebView 有時間落差——與 Issue 47 根因同一類「JS 選取 API 落後於原生手勢視覺狀態」問題，只是發生在拖曳控點階段而非長按候選階段。
2. Air Reader Pro C 的 WebView 版本／觸控事件合併（coalesced events）行為與 TCL 14 吋不同（比照 `epic-18` Issue 33／38-41 已知部分機型 WebView 版本偏舊的既有模式）。
3. 兩者疊加。

**下一步（Planning 前需先完成）：** 無法用 headless CDP 模擬選取控點拖曳（不具代表性，與 Issue 47 診斷時發現的局限相同）。需要在 Air Reader Pro C（會重現）與 TCL 14 吋（不會重現）各自部署一份暫時性除錯插樁（記錄拖曳過程中每個 `touchmove` 的 `selection.rangeCount`／`isCollapsed`／座標／時間戳），差異比對兩台裝置的輸出，才能鎖定真正根因並轉為 `ready-for-agent`。

**真機資料蒐集步驟（`plan-issue-1.md` Task 1 完成後可執行）：**

1. 用含 `[DEBUG-e25i1]` 插樁的 debug build（`flutter build apk --debug`）分別安裝到
   Air Reader Pro C 與 TCL 14 吋兩台裝置。
2. 兩台裝置分別開啟同一本流式 EPUB（建議用同一本書、同一個章節位置，降低
   非裝置因素造成的差異）。
3. 長按選取一段文字（例如 5-10 個字），確認選取控點已顯示於左右兩側
   （即選取已確立的狀態）。
4. 用手指拖曳其中一個控點，緩慢橫向移動（模擬使用者實際回報的手勢），
   同時留意畫面是否出現跳頁/位移。
5. 完成拖曳後，進入「設定」→「閱讀器 Console Log」，點擊右上角「複製全部」
   按鈕，將剪貼簿內容貼到文字檔或直接回報；同步註記該次測試使用的版面
   設定（直排/橫排、單頁/雙頁），以利後續交叉分析是否為版面相關變因。
6. 兩台裝置各重複步驟 3-5 至少 2 次（同一手勢多測幾次，避免單次操作的
   偶然性），並记錄「當下是否有觀察到跳頁」對應到哪一次操作。
7. 將兩台裝置的 log 檔案／文字回報回來，交叉比對 `rangeCount`／
   `isCollapsed`／`containerPosition`／`moved` 欄位在兩台裝置上的差異
   （特別留意 `moved=true` 但 `rangeCount>0 && isCollapsed=false`
   同時成立的行——這代表「選取明明已確立，內容卻仍位移」，是本 Issue
   要鎖定的確切症狀）。

**下一輪（拿到真機資料後）**：依比對結果撰寫 `bugfix-repro-issue-1.md`
確認根因，另立修復計畫；本插樁需在修復計畫的 Cleanup 階段整段移除
（`grep -rn "DEBUG-e25i1"` 確認清除乾淨）。

---

## Issue 2：畫線工具列在螢幕右側被裁切看不全

**Status:** `ready-for-agent`——根因已用原始碼＋使用者截圖交叉確認，修法明確。

**依賴：** 無

**背景：** 使用者回報並附截圖（`tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg`）：畫線位置偏螢幕右側時，浮動工具列（`AnnotationToolbar`，5 顆按鈕：3 色螢光筆＋底線＋備註）被裁切，只看得到最左邊一小塊圓角＋圖示，其餘超出螢幕右緣。

**根因：** `reader_screen.dart:1970-1989`。垂直位置 `_annotationToolbarTop()`（`reader_screen.dart:1656-1662`）已正確扣除工具列自身高度再 clamp（`belowSelection.clamp(0.0, size.height - _annotationToolbarHeight)`），但水平位置：

```dart
left: (selection.rect.left * size.width).clamp(0.0, size.width),
```

只鎖住起點不小於 0、不大於畫面寬度，**完全沒有扣除工具列自身寬度**——起點一旦接近右邊界，工具列本體就會整個超出螢幕右側。EPUB（`reader_screen.dart:1972`）與 PDF（`reader_screen.dart:1983`）兩條路徑同構，皆有此問題。

**修法：** 比照既有 `_annotationToolbarHeight = 56.0`／`_annotationToolbarGap = 8.0`（`reader_screen.dart:1647-1648`）常數宣告模式，新增 `_annotationToolbarWidth` 常數（`AnnotationToolbar` 為 `Row(mainAxisSize: MainAxisSize.min)` 5 顆 `IconButton`＋左右各 8px padding，實際渲染寬度需在真機/widget test 量測後定案，不可憑空假設數值），`left` 也比照 `top` 的寫法：

```dart
left: (selection.rect.left * size.width).clamp(0.0, size.width - _annotationToolbarWidth),
```

EPUB／PDF 兩處呼叫端皆須修正。

**單元測試要求：**
- widget test：模擬選取範圍 `rect.left` 接近 1.0（螢幕右緣）時，`AnnotationToolbar` 的 `left` 不超過 `size.width - _annotationToolbarWidth`，整個工具列的 `getBottomRight()` 在畫面寬度範圍內（可用 `tester.getBottomRight(find.byType(AnnotationToolbar))` 驗證）。
- 涵蓋 EPUB／PDF 兩條路徑。
- 既有正常位置（工具列不需 clamp）情境不受影響，回歸測試維持通過。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機或等效螢幕尺寸模擬下，畫線位於螢幕最右側時工具列完整可見可點擊。

---

## Issue 3：選擇畫線樣式後應可主動關閉工具列

**Status:** `ready-for-agent`——設計方向已與人類確認（採用方向 (a)）。

**依賴：** 無

**背景：** 使用者回報：選擇完畫線樣式（顏色/底線）後，工具列應自動隱藏，或提供一個明確按鈕可主動關閉——目前只能透過點擊換頁間接關閉。

**既有設計限制：** `_handleHighlightStyleSelected()`（`reader_screen.dart:1176`）刻意在建立劃線後不清空 `_currentSelection`，用意是讓使用者能緊接著點「備註」把新備註連結到剛建立的劃線（既定的「劃線+備註共存」使用者流程，`design.md` 沿用自 `epic-6-annotations`）。若選色後自動關閉整個工具列，會破壞這個既有連續流程。

**人類決定採用方向 (a)：** 保留現有連續流程（選色後工具列預設仍打開、備註仍可接續點擊建立備註），額外新增一顆明確的「✕ 關閉」按鈕於 `AnnotationToolbar` 內，讓使用者可以主動關閉工具列（清空 `_currentSelection`／`_currentPdfSelection`）而不必依賴點擊換頁間接觸發。

**修法方向：**
- `AnnotationToolbar`（`annotation_toolbar.dart`）新增第 6 顆按鈕（`Key('annotation_toolbar_close')`，`Icons.close`），新增 `onClosePressed` 必要參數。
- EPUB／PDF 兩處呼叫端（`reader_screen.dart:1974-1977`／`1985-1988`）的 `onClosePressed` 分別呼叫 `_handleSelectionCleared()`／`_handlePdfSelectionCanceled()`（既有方法，見 `reader_screen.dart:1152`／`1168`）。
- 是否需要同步清除 WebView／PDF 端的原生選取狀態（例如呼叫 JS `window.getSelection().removeAllRanges()`）待 Planning 階段查證是否會造成使用者主動關閉工具列後，原生選取控點仍殘留畫面的不一致體驗。

**單元測試要求：**
- widget test：`AnnotationToolbar` 新增 `Key('annotation_toolbar_close')` 存在且可點擊，點擊後 `onClosePressed` 被呼叫。
- `reader_screen_test.dart`：選取存在時點擊關閉按鈕後，`_currentSelection`／`_currentPdfSelection` 變為 `null`、工具列從畫面消失（`find.byType(AnnotationToolbar)` findsNothing）。
- 既有「選色後工具列保持開啟、可接續點擊備註」流程需有回歸測試保護，確認本次修改沒有連帶破壞。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機驗證選色後可點擊新按鈕主動關閉工具列，且不影響既有「選色→備註」連續流程。

---

## Issue 4：換頁點擊位置與相鄰頁畫線重疊時，誤跳出刪除確認對話框

**Status:** `needs-triage`——根因假說信心中高，但建議先建立 headless 重現迴圈驗證時序後再定案修法，避免像 Epic 18 Issue 47 一樣在計畫審查階段才發現時序假設有誤。

**依賴：** 無

**背景：** 使用者回報並附兩張連續截圖（`tmp/images/畫線問題/2-1...jpg`、`2-2...jpg`）：點擊換頁的位置，若剛好與上一頁或下一頁「同一螢幕座標」處有畫線重疊，換頁後會立刻誤跳出「是否刪除畫線」的確認對話框（`_showAnnotationActionDialog`，`reader_screen.dart:1309`）。

**根因假說（原始碼層級，信心中高，未經 headless/真機驗證確認確切時序）：**

vendored `view.js:438-445`：

```javascript
doc.addEventListener('click', e => {
    const [value, range, rect] = overlayer.hitTest(e)
    if (value && !value.startsWith(SEARCH_PREFIX)) {
        this.#emit('show-annotation', { value, index, range, rect })
    }
}, false)
```

`Overlayer` 用**原生 `click` 事件**做畫線點擊偵測，而 `paginator.js` 的換頁是自己的 `touchstart`/`touchmove`/`touchend` 手勢邏輯驅動、在 `touchend` 當下就立即完成視覺換頁。瀏覽器的合成 `click` 事件在觸控裝置上是 `touchend` **之後才延遲觸發**的相容性事件——這時頁面視覺上已經換到新頁，`click` 事件座標卻拿去對「新頁面此刻的內容」做 `hitTest()`，如果新頁同一螢幕座標剛好也有畫線，就誤判成「使用者點擊了這筆畫線」而彈出刪除確認。與 `epic-18` Issue 47 是同一類「vendored 觸控換頁邏輯 vs 瀏覽器原生延遲事件」的競速問題，但這次競速的對象是 `click` 而非 `touchmove`。

**下一步（Planning 前建議先完成，比照 Issue 47 診斷手法）：**

1. 用 Puppeteer + headless Chromium＋CDP `Input.dispatchTouchEvent` 建立可重跑的重現迴圈：控制相鄰兩頁在同一螢幕座標各放一筆畫線，模擬「點擊換頁熱區」的觸控手勢，量測是否確實觸發 `show-annotation`／`onAnnotationActivated`，並記錄 `click` 事件實際相對 `touchend` 的延遲時間。
2. 依實測時序再定案修法方向（可能方向：仿照 Issue 47，在 capture 階段追蹤「這次觸控是否驅動了換頁」，若是則短暫抑制緊接著的合成 `click`；需注意不可誤傷「換頁後、下個獨立點擊」這種合法情境，需要有清楚的時間窗口界定）。
3. 確認修法不影響「正常點擊畫線開啟編輯/刪除選單」這個既有核心功能（回歸測試）。

**單元測試要求：**（待重現迴圈確認時序後，於 Planning 階段補齊具體斷言）
- 至少需要一個能重現「換頁＋相鄰頁畫線重疊→誤觸刪除對話框」symptom 的自動化測試（headless harness 或等效方案），修復後同一測試須轉為不再誤觸發。
- 正常點擊畫線（無換頁介入）仍需正確觸發編輯/刪除對話框的回歸測試。

**驗收標準：** 重現迴圈確認修復後不再誤觸發、正常點擊畫線行為不受影響；真機驗證換頁+畫線重疊情境不再誤跳出刪除確認。
