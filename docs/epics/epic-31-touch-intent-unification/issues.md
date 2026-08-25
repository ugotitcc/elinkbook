# Epic 31 — 觸控意圖判讀統一：工單清單 (Issues)

依 `design.md`（Discovery：`/grilling` ＋ `/superpowers:brainstorming`；已依 `/superpowers:receiving-code-review` 審查修訂）拆解為 3 個垂直切片。Issue 2（main.js 重構）依賴 Issue 1（回歸測試安全網）先完成；Issue 3（Dart 端常數收斂）與前兩者無依賴，可平行進行。

---

## Issue 1：Puppeteer 回歸測試套件正式化＋跨機制干擾測試

**Status:** completed（已完成並合併：PR [#185](https://git.jigong.org/huthief/elinkBook/pulls/185)。`app/tool/foliate_touch_harness/` 共用 harness 函式庫 `lib/harness.mjs`、4 個情境測試腳本及 `run-all.mjs` 彙整腳本已建立；`node run-all.mjs` 執行 4 個場景全數 PASS。Issue 47／長按候選跨機制情境已知因 CDP `touchmove` 在目前環境限制不在自動化範圍內，交給 Issue 2 真機重測把關。程式碼審查（`reviews/review-code-issue-1.md`）發現的 Important 計時競態與 2 項 Minor 已於合併前修訂〔commit `64136de`〕：`scenario-cross-mechanism-tap-boundary.mjs` 情境 A 移除多餘往返查詢並加重試上限至 5 次，本機連續執行 `run-all.mjs` 8 次全數 PASS；`lib/harness.mjs` 改用官方 `page.createCDPSession()`；引號風格統一）

**依賴：** 無，可立即開始

**來源：** `design.md`「目標」第 4 項、「測試策略」。

**背景／需求：** 現有的觸控/選取相關 Puppeteer diff-testing 腳本（例如 `docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/repro-issue10.mjs`）散落在暫存/審查目錄下，不是正式回歸測試。Issue 2 即將把 main.js 5 個觸控機制全面重寫，重寫前必須先有一套能捕捉「現行行為」的自動化安全網，重寫後才能拿它驗證有沒有回歸。

**設計要點（依 `design.md`，含 Issue 1 規劃階段實測後的範圍調整）：**
- 正式存放路徑：`app/tool/foliate_touch_harness/`（**不是** `app/test/`——`app/test/` 是 `flutter test` 專用的 Dart 測試目錄，Puppeteer 是 Node.js 腳本，比照本 repo 既有慣例 `app/tool/check_foliate_es_compat.js`）。
- **CDP `click` 合成，實測已訂正**：headless Chromium 透過 CDP `touchStart`/`touchEnd`（不含中途 `touchmove`）**確實會**合成原生 `click`，任何按壓時長皆會。「快速點擊攔截」場景可直接用真實 CDP touch 序列觸發，不需要 `page.mouse.click()` 替代（舊審查意見在此點有誤，已訂正）。
- **CDP `touchmove` 送達 iframe 不可靠，本工單範圍因此調整**：實測目前環境（Puppeteer 綁定 Chromium `151.0.7922.77`）下，依賴 CDP `touchmove` 事件的測試手法不可靠（就連既有、文件記錄「已驗證通過」的 Issue 47 harness 重跑也測不出東西）。人類決策：**Issue 47（長按候選攔截）與「長按候選期間選取突然確立」跨機制情境，兩者皆依賴 `touchmove`，在本工單降級為 best-effort、不強制自動化**，改由 Issue 2 既有規劃的真機重測把關（見 Issue 2 真機重測清單）。
- 本工單改為涵蓋**只需 `touchStart`/`touchEnd`（不含 `touchmove`）** 的場景：
  1. Epic 25 Issue 1/4（快速點擊 vs. 畫線點擊）——CDP `touchStart`/`touchEnd` 直接觸發，透過 `onAnnotationActivated` bridge callback 觀察。
  2. Issue 10（選取收尾保護）——用 `execCommand`/`Range` API 注入選取，緊接著 CDP 短按（`touchStart`/`touchEnd`）在選取附近，驗證選取未被誤判折疊。
  3. Issue 11（`hitTest` 命中判斷）——用 `window.setDecorations()` 建立畫線，`Range` API 注入命中該畫線的選取，驗證 `onSelectionChanged` bridge 回傳的 `existingAnnotationId` 正確。
  4. **跨機制測試**：快速點擊門檻邊界時選取狀態同時變動——選取收尾保護期內／期外分別做 CDP 短按，驗證兩個獨立機制（選取收尾保護、快速點擊分類）在同一個觸控事件上不會互相干擾。
- 本工單針對**現行（尚未重構）** main.js 撰寫測試，作為 Issue 2 的重構前基準線。

**測試要求：**
- 上述 4 個情境各自可獨立執行，執行後有明確的 PASS/FAIL 輸出。
- 全部腳本針對目前 main.js 執行，必須全數 PASS。

**驗收標準：** `app/tool/foliate_touch_harness/` 下有共用 harness 函式庫（`lib/harness.mjs`）＋ 4 支以上情境測試腳本＋彙整執行腳本，全部針對現行 main.js 通過；README 說明如何執行；Issue 47 與「長按候選期間選取確立」不在本工單自動化範圍內，已於 `design.md`「已知風險」明確記錄原因與後續（真機重測、技術債追蹤）。

---

## Issue 2：main.js 觸控意圖分類器重構（TouchIntentClassifier）

**Status:** ready-for-agent

**依賴：** Issue 1（需要先有回歸測試套件作為重構安全網）

**來源：** `design.md`「目標」第 1/2 項、「整體機制」> main.js 觸控意圖狀態機。

**背景／需求：** `app/android/app/src/main/assets/foliate/main.js` 的 `view` `load` 事件閉包內，5 個獨立時期各自新增的觸控機制（Epic 18 Issue 47／Epic 25 Issue 4／Epic 27 Issue 9/10/11）各自宣告狀態變數與門檻值，執行順序完全依賴 capture 階段監聽器註冊順序，沒有測試或註解鎖住這個隱性依賴（Issue 10 的 clock-mixing bug 即為此類風險的實例）。

**設計要點（依 `design.md`，含審查修訂）：**
- 新增一個 class（暫名 `TouchIntentClassifier`），每次 `view.addEventListener('load', ...)` 觸發（含 look-ahead 預讀章節）各自產生一個實例，內部維持 **3 個彼此獨立的欄位**（不合併成一個扁平 `state`）：
  - `gesture`（子物件）：`state`（`idle`／`longPressCandidate`／`swiping`）＋ `startX`/`startY`/`startTime`，`touchend`/`touchcancel` 會重置它。
  - `lastTouchStartTime`：持久時間戳，`touchstart` 寫入，`touchcancel` 或 `click` 消耗時才清空，**`touchend` 不清空**（供 `click` 的快速點擊判斷讀取）。
  - `lastNonCollapsedSelectionAtMs`：持久時間戳，由 `selectionchange`（含 `contextmenu`/`pointercancel` 觸發的 `reportSelection()`）寫入/清空，與手勢子狀態無關（供 `mousedown` 的選取收尾保護讀取）。
- 5 個既有機制改成讀這 3 個欄位，不再各自從原始 `touchstart`/`touchmove`/`click` 重新判斷；行為規則（門檻值、判斷邏輯）維持不變。
- 門檻值（`LONG_PRESS_GATE_MS=500`／`ANNOTATION_CLICK_TAP_MAX_MS=700`／`SELECTION_RELEASE_GUARD_MS=150`／`SWIPE_DISTANCE_DEADZONE_PX=15`／`SWIPE_VELOCITY_ESCAPE_PX_PER_MS=0.3`）集中宣告，並用 `console.assert(LONG_PRESS_GATE_MS <= ANNOTATION_CLICK_TAP_MAX_MS, ...)` 鎖定優先順序假設。
- 不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`），符合 ADR 0011。

**測試要求：**
- Issue 1 建立的 `app/tool/foliate_touch_harness/` 4 個情境全數維持 PASS（行為完全不變，只是重構）。
- **真機重測清單**（本工單為全面重寫，不可只靠自動化測試結案，合併前需人工在真實裝置上逐項驗證並記錄在 `reviews/review-issue-2.md`）——**Issue 47 與「長按候選期間選取突然確立」這兩項，因 Issue 1 已記錄的 Puppeteer/Chromium 限制，本工單是它們唯一的把關手段，不可省略：**
  - Issue 47：橫排/直排長按選字前幾影格畫面不暴跳。
  - **長按候選期間選取突然確立**（跨機制情境）：長按選字過程中，選取一旦被系統判定成立，畫面不應再出現滑動誤判/暴跳。
  - Epic 25 Issue 1/4：快速點擊換頁正常、刻意點擊畫線正常叫出工具列。
  - Issue 10：選字放開手指時選取不折疊。
  - Issue 11：長按已畫線文字時工具列正確顯示「刪除」按鈕。

**驗收標準：** main.js 5 個機制收斂成單一 `TouchIntentClassifier`；Issue 1 全部 Puppeteer 測試通過；上述 5 項真機重測全過並記錄；`flutter analyze` 乾淨、`flutter test` 全數通過；不修改任何 vendored 檔案。

---

## Issue 3：TapZoneDetector 常數收斂＋PDF 門檻對齊

**Status:** ready-for-agent

**依賴：** 無，可與 Issue 1/2 平行進行

**來源：** `design.md`「目標」第 3 項、「整體機制」> Dart 端：TapZoneDetector 常數收斂。

**背景／需求：** `app/lib/reader/tap_zone_detector.dart` 的 EPUB／PDF 呼叫端各自宣告 `tapMaxDurationMs`／`tapSlop`／`tapDebounceMs`，其中 `tapSlop`（18.0）／`tapDebounceMs`（350）兩端數值剛好相同卻各自宣告；PDF 端 `tapMaxDurationMs`（400ms）明顯低於 EPUB（700ms，Epic 25 Issue 1 真機校準值），未對齊。

**設計要點（依 `design.md`，含審查修訂）：**
- 新增模組級共用常數 `kTapZoneSlop = 18.0`／`kTapZoneDebounceMs = 350`，設為 `TapZoneDetector` 建構子的具名參數**預設值**（`this.tapSlop = kTapZoneSlop` 一類寫法），EPUB／PDF 呼叫端不再各自寫字面值。
- `tapMaxDurationMs` **不**跟進設預設值，維持兩端各自明確傳入字面值——EPUB 的 700ms 是真機校準值、PDF 的 700ms 是本次刻意對齊、未經真機驗證的決定，數值雖相同但脈絡不同，刻意保留各自宣告以留住這個差異紀錄。
- PDF 端 `tapMaxDurationMs` 從 400 改為 700，程式碼註解明確標註「刻意對齊、未經真機驗證」。
- 更新 `tap_zone_detector.dart` 現有 class doc 註解：`tapSlop` 已改為共用常數，註解只需針對 `tapMaxDurationMs` 說明「兩端數值目前相同，但校準狀態不同，故維持各自宣告」。

**測試要求：**
- `app/test/reader/tap_zone_detector_test.dart`：新增驗證 `kTapZoneSlop`／`kTapZoneDebounceMs` 常數值，以及 EPUB／PDF 呼叫端確實使用該常數（非寫死字面值）。
- `app/test/reader/pdf_reader_view_nav_zone_test.dart:141`：`tester.pump(const Duration(milliseconds: 600))` 改為 `800`（門檻改 700ms 後，600ms 會落在合格點擊範圍內，此測試若不改必定失敗）。
- 既有 `TapZoneDetector`／`PdfReaderView`／`FoliateReaderView` 相關 widget test 全數維持通過。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過；PDF 長按判定門檻對齊 EPUB（700ms）；未經真機驗證的風險已明確記錄在程式碼註解與本工單。
