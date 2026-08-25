# 觸控意圖判讀統一（設計文件）

**狀態：** 待人類審閱
**對應工單：** 尚未建立（新 Epic，暫定編號 `epic-31-touch-intent-unification`，正式編號於 Scrum Master 階段建立 `issues.md` 時定案）
**診斷依據：** `docs/research/architecture-review-touch-gesture-handling.md` 候選 1

## 背景

`app/android/app/src/main/assets/foliate/main.js` 的 `view` `load` 事件監聽器內（約 641-911 行），累積了 5 個獨立時期各自新增的觸控相關機制，全部活在同一個閉包裡：

1. `longPressGateState`（Epic 18 Issue 47）——長按候選期間攔截 `touchmove`，避免被 `paginator.js` 誤判成滑動換頁。
2. `ANNOTATION_CLICK_TAP_MAX_MS`（Epic 25 Issue 4）——用按壓時長分辨「快速點擊（換頁意圖）」跟「刻意點擊畫線」。
3. `SELECTION_RELEASE_GUARD_MS`（Epic 27 Issue 10）——放開手指時避免選取範圍被誤判為新點擊而折疊。
4. `reportSelection()` 內的 `overlayer.hitTest()`（Epic 27 Issue 11）——選取變動時查詢是否命中既有畫線。
5. `no-swipe` 屬性設定（Epic 27 Issue 9）——阻止特定情境下的滑動手勢。

這 5 個機制裡，前兩個（1、2）都是在回答同一個問題：「這次觸控算不算一次快速點擊」，但各自獨立宣告門檻值、各自在 `touchstart` 寫入自己的狀態變數，彼此的執行順序完全依賴 capture 階段的監聽器註冊順序，沒有任何測試或註解鎖住這個順序關係。第 3、4 項則是另一類判斷（選取範圍怎麼處理），目前運作正常，是已被 Issue 10/11 真機案例驗證過的邏輯。

**真實發生過的風險**：Issue 10 的 clock-mixing bug（iframe 時鐘與最外層頁面時鐘原點不同，導致保護期門檻形同虛設）就是這種「隱性狀態關係沒有集中管理」的直接後果之一。新增第 6 個機制時，若不清楚既有 3 個狀態變數彼此的隱性依賴，很容易重蹈覆轍。

Dart 端 `app/lib/reader/tap_zone_detector.dart` 則是另一種狀況：EPUB／PDF 兩個呼叫端各自宣告 `tapMaxDurationMs`／`tapSlop`／`tapDebounceMs`，其中 `tapSlop`（18.0）／`tapDebounceMs`（350）兩端數值剛好相同卻各自宣告，只有 `tapMaxDurationMs`（EPUB 700ms／PDF 400ms）有明確的校準狀態差異作為分開宣告的理由。

## 目標

1. **main.js**：把上述 5 個機制的判斷邏輯，收斂進一個新的**觸控意圖分類器**（`TouchIntentClassifier`，暫名，class 形式，每章節各自一個實例），內部拆成 3 個彼此獨立的欄位（手勢子狀態、持久點擊時間戳、持久選取時間戳，見下方「整體機制」），5 個既有機制改成讀這 3 個欄位，不再各自從原始 `touchstart`/`touchmove`/`click` 事件重新判斷。行為規則（門檻值、判斷邏輯）維持不變，只收斂「誰來管理共用狀態」。
2. **main.js**：門檻值大小關係（例如「長按候選門檻 ≤ 快速點擊門檻」）用 dev-only `console.assert` 明確鎖住，避免未來調整數值時不小心破壞隱性依賴。
3. **TapZoneDetector（Dart）**：`tapSlop`／`tapDebounceMs` 收斂成模組級共用常數（數值不變，只統一宣告來源）；PDF 端 `tapMaxDurationMs` 從 400ms 改為 700ms，與 EPUB 對齊。
4. 把現有的臨時 Puppeteer diff-testing 腳本收進版控，成為正式回歸測試，並新增「跨機制互相干擾」情境測試。
5. 為這次全面重寫的 main.js 狀態機，建立真機重測清單，涵蓋 Issue 47／Epic 25 Issue 1/4／Issue 10／Issue 11 共 4 個歷史 bug 場景。

## 非目標

- **不處理 PDF 自己的 `cropEditModeActive`／`_selectionDrag` 機制**（研究報告候選 5）——PDF 的長按拖曳框選跟本次 EPUB WebView 內的觸控機制是完全不同的手勢實作路徑，留待未來獨立處理。
- **不新增 JS↔Dart 橋接資料**——main.js 狀態機與 Dart 端 `TapZoneDetector` 各自獨立判斷，不透過新的 channel 同步狀態。
- **不為 TTS 語音功能預留 main.js 擴充點**——TTS 的「單點顯示/隱藏工具列」屬於 Flutter UI 層行為，未來會直接接到 `TapZoneDetector` 既有的 tap 輸出，不需要 main.js 狀態機新增任何東西。
- **不強迫 `TapZoneDetector` 跟 main.js 狀態機共用同一套分類詞彙**——EPUB／PDF 兩端本來就服務不同的手勢集合（main.js 要分辨選字/畫線/翻頁；`TapZoneDetector` 只分辨「是不是一次點擊」），維持各自現有的判斷範圍。
- **不修改任何 vendored 檔案**（`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`），符合 ADR 0011。
- **PDF `tapMaxDurationMs` 改 700ms 不做真機驗證**——這是使用者知情後接受的風險，原因是 PDF 端目前的手勢機制（Flutter 原生 `Listener`）跟 EPUB 端（WebView 內合成事件）觸發路徑不同，理論上校準結果不會直接套用，但使用者判斷「先對齊數值、之後有真機回報再調」優先於「現在花時間校準」。此點必須在程式碼註解與 PR 說明中明確寫成「刻意決定、未經真機驗證」，不可誤植為已驗證數值。

## 整體機制

### main.js：觸控意圖狀態機

**設計審查修正（見 `tmp/epic-31/review-design-touch-intent-unification.md` Important #1）**：「手勢即時狀態」與「DOM 選取」是兩組正交的生命週期，不能收斂成同一個扁平 `state` 欄位——原始程式碼的 `annotationClickTouchStartTime` 本來就刻意在 `touchend` 不清空（只有 `touchcancel` 或 `click` 自己消耗時才清空，供之後的 `click` 事件判斷用），若誤實作成單一 `state` 在 `touchend` 統一重置為 `idle`，`click`／`mousedown` 兩個機制會讀不到已經發生過的按壓紀錄。另外，靜止長按選字主要經 `contextmenu`/`pointercancel`/`selectionchange`（ADR 0013 既定機制）觸發，不一定會有 `touchmove`，`selecting` 狀態的進入條件不能只畫「經 `touchmove`」這一條路。

改採**結構化封裝**（同時解決審查報告 Minor #5 的多章節實例隔離問題）：一個 class（暫名 `TouchIntentClassifier`），每次 `view.addEventListener('load', ...)` 觸發時（含 look-ahead 預讀章節）各自產生一個實例，內部維持 3 個彼此獨立的欄位，不合併成一個：

- `gesture`（子物件）：`state`（`idle`／`longPressCandidate`／`swiping`）＋ `startX`/`startY`/`startTime`，只服務長按候選攔截這一個機制，`touchend`/`touchcancel` 會重置它。
- `lastTouchStartTime`：持久時間戳，`touchstart` 寫入、`touchcancel` 或 `click` 消耗時才清空，`touchend` **不會**清空它——供 `click` 事件的快速點擊判斷讀取。
- `lastNonCollapsedSelectionAtMs`：持久時間戳，由 `selectionchange`（經 `reportSelection()`）寫入/清空，跟手勢子狀態完全無關——供 `mousedown` 的選取收尾保護讀取。

狀態轉換（以 `gesture.state` 為主軸，另外兩個欄位各自獨立標註觸發點）：

```
gesture.state:
  idle → touchstart → longPressCandidate（記錄起點座標/時間戳）
  longPressCandidate
    → touchmove 超過門檻（時間/距離/平均速度）→ swiping（放行給 paginator.js）
    → touchmove 偵測到選取已非折疊 → idle（放行給瀏覽器原生選取）
    → touchend/touchcancel → idle
  （swiping 不再回到 longPressCandidate，直到下次 touchstart）

lastTouchStartTime（獨立欄位，不隨 gesture.state 重置）:
  touchstart → 寫入時間戳
  touchcancel / click 消耗 → 清空
  touchend → 不動作（刻意保留，供 click 判斷用）

lastNonCollapsedSelectionAtMs（獨立欄位，與手勢無關）:
  selectionchange（非折疊）/ contextmenu / pointercancel → reportSelection() 寫入
  selectionchange（折疊）→ 清空
```

5 個既有機制改寫成讀這 3 個欄位（不再各自從原始 `touchstart`/`touchmove`/`click` 重新判斷）：

- 長按候選攔截（Epic 18 Issue 47）→ 讀 `gesture.state` 決定是否攔截 `touchmove`。
- 快速點擊判斷（Epic 25 Issue 4）→ 讀 `lastTouchStartTime` 決定是否攔截 `click`。
- 選取收尾保護（Issue 10）→ 讀 `lastNonCollapsedSelectionAtMs` 決定是否攔截 `mousedown`。
- 選取即時回報（Epic 17 Issue 8）與 `hitTest` 命中查詢（Issue 11）→ 邏輯不變，額外呼叫 `onSelectionUpdated()` 寫入 `lastNonCollapsedSelectionAtMs`。
- `no-swipe` 屬性設定（Issue 9）→ 邏輯與觸發時機不變，只是讀取這個 class 的欄位而非原本獨立變數。

門檻值全部集中宣告在狀態機模組頂端：

```js
const LONG_PRESS_GATE_MS = 500
const ANNOTATION_CLICK_TAP_MAX_MS = 700
const SELECTION_RELEASE_GUARD_MS = 150
const SWIPE_DISTANCE_DEADZONE_PX = 15
const SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3

console.assert(LONG_PRESS_GATE_MS <= ANNOTATION_CLICK_TAP_MAX_MS,
  '長按候選門檻必須 <= 快速點擊門檻，否則兩個機制的優先順序假設會被破壞')
```

**邊界情況（沿用現有邏輯，不新增）**：多指觸控（`touches.length > 1`）一律回到 `idle`；超連結點擊（`a[href]`）在所有分支都排除，比照現有選擇器；`load` 事件對預讀章節同樣觸發，狀態機不跨章節共用。

### Dart 端：TapZoneDetector 常數收斂

在 `app/lib/reader/tap_zone_detector.dart` 新增模組級共用常數：

```dart
const double kTapZoneSlop = 18.0
const int kTapZoneDebounceMs = 350
```

EPUB（`foliate_reader_view.dart`）與 PDF（`pdf_reader_view.dart`）呼叫端的 `tapSlop`/`tapDebounceMs` 改用這兩個常數，不再各自宣告字面值。**設計審查建議（Minor #4，採納）**：`tapSlop`／`tapDebounceMs` 直接設為建構子的具名參數預設值（`this.tapSlop = kTapZoneSlop`），呼叫端不需要再各自寫一次。

`tapMaxDurationMs` **不**跟進設預設值，維持兩端各自明確傳入字面值——這是刻意保留的差異記錄，不是遺漏：EPUB 的 700ms 是 Epic 25 Issue 1 真機校準值，PDF 的 700ms 是本次刻意對齊、未經真機驗證的決定，兩者數值現在剛好相同，但脈絡不同，各自明確傳值才能讓這個差異留在程式碼裡，不被「常數收斂」的動作悄悄合併掉。

`tap_zone_detector.dart` 現有 class doc 註解（「`tapMaxDurationMs`／`tapSlop` 刻意不在本 module 內設共用預設值/常數...兩者適用的正確門檻值可能本來就不同」）需要同步更新：`tapSlop` 已改為共用常數，註解要改成只針對 `tapMaxDurationMs` 說明「兩端數值目前相同，但校準狀態不同，故維持各自宣告」，避免文件與程式碼不一致。

## 測試策略

**Puppeteer 回歸測試（新增至版控，`app/tool/foliate_touch_harness/`，非目前的臨時暫存腳本）**：

放在 `app/tool/` 而非 `app/test/`——`app/test/` 是 `flutter test` 專用的 Dart 測試目錄（見 CLAUDE.md 兩層測試架構），Puppeteer 是 Node.js 腳本，比照這個 repo 既有慣例（`app/tool/check_foliate_es_compat.js`），不混進 Dart 測試目錄。

- 逐一涵蓋 4 個歷史 bug 場景各自的自動化重現：Issue 47（長按候選攔截）、Epic 25 Issue 1/4（快速點擊 vs. 畫線點擊）、Issue 10（選取收尾保護）、Issue 11（`hitTest` 命中判斷）。
- 新增**跨機制干擾測試**：長按候選期間選取突然確立、快速點擊門檻邊界時選取狀態同時變動——驗證狀態機沒有把 3 個狀態的優先順序關係搞錯，而不只是各自獨立驗證。
- **設計審查修正（Important #2）**：`docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/repro-issue10.mjs` 已記錄並證實——headless Chromium 透過 CDP 觸控注入（不論自寫 `Input.dispatchTouchEvent` 或 Puppeteer 的 `page.touchscreen.tap()`），**不會**從 `touchstart`/`touchend` 序列自動合成原生 `click`，靜止長按 700ms 也**不會**自動觸發原生文字選取。因此「快速點擊攔截」（Epic 25 Issue 4）跟「長按選字建立選取」（Issue 10/11 的選取相關場景）這兩類測試，不能只靠 CDP touch 模擬觸發，必須改用 `page.mouse.click()` 或直接透過 DOM API（`window.getSelection().selectAllChildren()` 等）注入選取範圍/帶時間戳的合成事件，才能真正驗證到監聽器邏輯本身。

**真機重測**（本次為全面重寫，不可只靠自動化測試結案）：合併前在真實裝置上手動重跑以下 4 個歷史 bug 的重現步驟，逐項記錄在該 Issue 的 review 報告裡：

- Issue 47：橫排/直排長按選字前幾影格畫面不暴跳。
- Epic 25 Issue 1/4：快速點擊換頁正常、刻意點擊畫線正常叫出工具列。
- Issue 10：選字放開手指時選取不折疊。
- Issue 11：長按已畫線文字時工具列正確顯示「刪除」按鈕。

**Dart 端**：

- `app/test/reader/tap_zone_detector_test.dart`：新增驗證 `kTapZoneSlop`／`kTapZoneDebounceMs` 常數確實被 EPUB／PDF 兩端呼叫端引用（不是各自寫死字面值）。
- **設計審查修正（Important #3）**：`app/test/reader/pdf_reader_view_nav_zone_test.dart:141` 現有測試「按壓超過快速點擊時長判定門檻不觸發 onZoneAction」用 `tester.pump(const Duration(milliseconds: 600))` 驗證超過 PDF 現行 400ms 門檻不觸發點擊。PDF 門檻改 700ms 後，600ms 會落在合格點擊範圍內，測試會失敗——**必須**把等待時間改成 `800ms`（需大於新門檻 700ms），這是 Plan 的必要修正項目，不是可選項。

**基準線**：`flutter analyze` 需為「No issues found!」，`flutter test` 全數通過，比照專案既有慣例，不額外加碼。

## 已知風險

- PDF 的 `tapMaxDurationMs` 改為 700ms 未經真機驗證，若之後真機回報「PDF 長按判斷變得比預期遲鈍」，需另開工單依真機資料重新校準（比照 Epic 25 Issue 1／Epic 26 Issue 3 先例）。
- main.js 狀態機是對已驗證邏輯的重寫，即使 Puppeteer 測試全過，仍需真機重測 4 個歷史場景才能排除回歸風險（見上方測試策略）。
