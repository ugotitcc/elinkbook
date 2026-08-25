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

1. **main.js**：把上述 5 個機制的判斷邏輯，收斂進一個新的**觸控意圖狀態機**（`TouchIntentMachine`，暫名），對外只公開分類後的狀態（`idle`／`longPressCandidate`／`swiping`／`selecting`），5 個既有機制改成訂閱這個狀態機的輸出，不再各自從原始 `touchstart`/`touchmove`/`click` 事件重新判斷。行為規則（門檻值、判斷邏輯）維持不變，只收斂「誰來管理共用狀態」。
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

新增一個狀態物件，取代原本 3 個各自獨立的閉包變數（`longPressGateState`／`annotationClickTouchStartTime`／`lastNonCollapsedSelectionAtMs`），狀態物件跟現有程式碼一樣活在同一個 `view.addEventListener('load', ...)` 閉包內（每次章節載入各自獨立一份，look-ahead 預讀章節同樣適用，維持現有行為）：

```
idle
  → touchstart → longPressCandidate（記錄起點座標/時間戳）
longPressCandidate
  → touchmove 超過門檻（時間/距離/平均速度）→ swiping（放行給 paginator.js）
  → touchmove 偵測到選取已非折疊 → selecting（放行給瀏覽器原生選取）
  → touchend/touchcancel → idle
selecting（瀏覽器原生選取已建立，非折疊）
  → selectionchange 變回折疊 → idle
  → mousedown 落在選取收尾保護期內（≤150ms）且非超連結 → 攔截 preventDefault，維持 selecting
click 事件（獨立分支，讀狀態機記錄的 touchstart 時間戳）
  → 與 touchstart 時間差 ≤700ms 且非超連結 → 判定為快速點擊，攔截傳給畫線 `hitTest` 的 click
```

5 個既有機制改寫成訂閱這個狀態物件：

- 長按候選攔截（Epic 18 Issue 47）→ 讀 `longPressCandidate`/`swiping` 狀態決定是否攔截 `touchmove`。
- 快速點擊判斷（Epic 25 Issue 4）→ 讀狀態機記錄的 `touchstart` 時間戳決定是否攔截 `click`。
- 選取收尾保護（Issue 10）→ 讀 `selecting` 狀態與其記錄的時間戳決定是否攔截 `mousedown`。
- 選取即時回報（Epic 17 Issue 8）與 `hitTest` 命中查詢（Issue 11）→ 讀 `selecting` 狀態觸發，邏輯不變。
- `no-swipe` 屬性設定（Issue 9）→ 邏輯與觸發時機不變，只是讀取狀態機而非原本獨立變數。

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

EPUB（`foliate_reader_view.dart`）與 PDF（`pdf_reader_view.dart`）呼叫端的 `tapSlop`/`tapDebounceMs` 改用這兩個常數，不再各自宣告字面值。`tapMaxDurationMs` 維持各自宣告（本來就有正當理由：EPUB 700ms 是 Epic 25 Issue 1 真機校準值），PDF 端數值從 400 改為 700，並更新該處程式碼註解說明這是刻意對齊、非真機驗證結果。

## 測試策略

**Puppeteer 回歸測試（新增至版控，正式測試目錄，非目前的臨時暫存腳本）**：

- 逐一涵蓋 4 個歷史 bug 場景各自的自動化重現：Issue 47（長按候選攔截）、Epic 25 Issue 1/4（快速點擊 vs. 畫線點擊）、Issue 10（選取收尾保護）、Issue 11（`hitTest` 命中判斷）。
- 新增**跨機制干擾測試**：長按候選期間選取突然確立、快速點擊門檻邊界時選取狀態同時變動——驗證狀態機沒有把 3 個狀態的優先順序關係搞錯，而不只是各自獨立驗證。

**真機重測**（本次為全面重寫，不可只靠自動化測試結案）：合併前在真實裝置上手動重跑上述 4 個歷史 bug 的重現步驟，逐項記錄在該 Issue 的 review 報告裡。

**Dart 端**：`TapZoneDetector` 既有 widget test 照跑；檢查有沒有測試寫死 PDF 端 `tapMaxDurationMs=400`，有則更新為 700。

**基準線**：`flutter analyze` 需為「No issues found!」，`flutter test` 全數通過，比照專案既有慣例，不額外加碼。

## 已知風險

- PDF 的 `tapMaxDurationMs` 改為 700ms 未經真機驗證，若之後真機回報「PDF 長按判斷變得比預期遲鈍」，需另開工單依真機資料重新校準（比照 Epic 25 Issue 1／Epic 26 Issue 3 先例）。
- main.js 狀態機是對已驗證邏輯的重寫，即使 Puppeteer 測試全過，仍需真機重測 4 個歷史場景才能排除回歸風險（見上方測試策略）。
