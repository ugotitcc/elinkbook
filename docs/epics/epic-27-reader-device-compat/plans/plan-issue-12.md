# Epic 27 Issue 12 — 觸控硬體「彈跳」訊號導致連續失控自動翻頁 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在共用元件 `TapZoneDetector` 加入防彈跳（debounce）機制：同一格熱區在極短時間內收到第二次（或更多次）觸發時，只放行第一次、忽略其餘，用純軟體手段吸收本 Epic 已用 `adb shell getevent` 硬體訊號證實存在的觸控 IC 彈跳雜訊，根除「壓一下畫面自己連續亂跳頁、殘影發霧」的真機回報。

**Architecture:** `TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`）是 EPUB／PDF 共用的九宮格熱區單一格子偵測器，`FoliateReaderView`／`PdfReaderView` 各自用 `List.generate(9, ...)` 建立 9 個獨立的 `TapZoneDetector` 實例，每一格各自持有獨立的 `_TapZoneDetectorState`。真機硬體訊號證實：一次彈跳事件的所有重複按下座標幾乎不動（誤差僅個位數至數十像素），必然落在同一格熱區內——因此防彈跳邏輯只需要「每一格熱區記住自己最近一次成功判定為 tap 的時間」這個最小範圍即可完全吸收本 Epic 已觀測到的彈跳模式，不需要跨格子的全域協調機制。修法是在 `_TapZoneDetectorState` 新增一個 `_lastQualifyingTapUpTimeMs` 欄位，在既有「是否為一次快速點擊」判定成立之後、真正呼叫 `widget.onTap()` 之前，多比對一次「距離上次同樣判定成立的時間點是否已超過 `tapDebounceMs` 門檻」，未超過則忽略。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 12」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 10」新問題 B 段落（硬體訊號座標交叉核對紀錄）、`docs/epics/epic-27-reader-device-compat/reviews/issue-10-11-12-analysis.md`（三項後續問題的關聯性矩陣與優先順序分析）。

## 設計決策（回應 `issues.md` Issue 12 留給實作者定案的範圍問題）

1. **防彈跳邏輯放在 `TapZoneDetector` 內部（`_TapZoneDetectorState`），不是 `_handleZoneAction`**：`TapZoneDetector` 是 PDF／EPUB 共用元件，且每一格熱區各自是獨立的 `State`，把邏輯放在這裡可以免費讓 PDF／EPUB 兩種格式同時受益，且「同一格熱區」這個防彈跳範圍本來就等於一個 `_TapZoneDetectorState` 實例的生命週期，不需要額外的跨元件協調狀態。`_handleZoneAction`（`reader_screen.dart`）是格式無關的動作分派後端，把防彈跳邏輯放在這裡反而需要額外記錄「上一次是哪一格熱區」，複雜度更高、且無法防止 PDF／EPUB 各自的呼叫端已經各自重複呼叫（`TapZoneDetector.onTap` 本身就已經被觸發多次）。
2. **`tapDebounceMs` 比照既有 `tapMaxDurationMs`／`tapSlop` 的既有慣例，作為呼叫端必要注入參數（`required`），不在 `TapZoneDetector` 內部設共用預設值**——與該檔案 class doc 既有的既定設計哲學一致（見 `tap_zone_detector.dart:35-41`）。
3. **初始值定為 350ms，而非 `issues.md`／分析報告原先建議的「150～200ms」**：真機用 `adb shell getevent` 側錄到的實際彈跳訊號，同一段彈跳內相鄰按下事件的**最大間隔是 326 毫秒**（`bugfix-repro.md`「Issue 10」新問題 B 段落：`86、152、261、326、87、207` 毫秒六段間隔，皆為連續事件間的間隔，非累計值）。防彈跳邏輯採「每次判定為快速點擊都重新起算冷卻窗」的設計（見下方 Task 1 實作），只要窗口門檻小於等於這個最大間隔，彈跳序列中間就會有一次意外被放行——`200ms < 326ms`，代表若照搬原始建議值，這次真機實際側錄到的彈跳序列**不會被完全吸收**。改採 350ms（大於已觀測到的最大間隔 326ms，留一點餘裕），並在下方 Task 1 用真機側錄到的實際間隔數值直接重播成回歸測試，而非只測抽象的「兩次點擊間隔小於門檻」情境。EPUB／PDF 兩個呼叫端目前都採用同一個值（比照 `tapSlop` 兩邊皆為 18.0 但仍分別明確注入的既有慣例）——**與 `tapMaxDurationMs` 相同，這是一個時間類數值，350ms 是根據本次已側錄到的具體證據推出的起始值，不是憑空選的，但仍可能需要真機使用一段時間後再校準**（例如是否誤傷「使用者刻意快速連續點擊翻好幾頁」這種正常操作模式），比照 `epic-25` Issue 1／`epic-26` Issue 3 先例，若真機使用後回報有需要調整，應另立工單處理，不在本計畫的驗收範圍內。

## Global Constraints

- 只修改 `app/lib/reader/tap_zone_detector.dart`、`app/test/reader/tap_zone_detector_test.dart`、`app/lib/reader/foliate_reader_view.dart`、`app/lib/reader/pdf_reader_view.dart` 四個檔案——後兩者的改動僅止於「新增 `tapDebounceMs: 350` 這一行參數」，不做其他修改。
- 不修改 `paginator.js`／`main.js`（本 Issue 根因是觸控硬體層級，與 vendored JS 或 `no-swipe` 無關，見 `bugfix-repro.md` 診斷結論）。
- 每個 Task 完成後跑 `flutter analyze`，維持乾淨。

---

### Task 1：`TapZoneDetector` 新增 `tapDebounceMs` 防彈跳機制

**Files:**
- Modify: `app/lib/reader/tap_zone_detector.dart`
- Modify: `app/lib/reader/foliate_reader_view.dart`（新增建構參數，約第 826-832 行）
- Modify: `app/lib/reader/pdf_reader_view.dart`（新增建構參數，約第 979-986 行）
- Test: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Consumes: 無新增——沿用既有 `nowMs`（計時來源注入）。
- Produces: `TapZoneDetector` 新增一個 **必要（`required`）** 建構參數 `final int tapDebounceMs`，兩個生產呼叫端（`FoliateReaderView`、`PdfReaderView`）都需要同步補上這個參數才能通過編譯，見下方 Step 3。

- [x] **Step 1：寫失敗測試——三則新測試涵蓋「同格熱區彈跳只放行第一次」「真機實際側錄間隔的回歸重播」「超過門檻後仍正常觸發（非永久鎖死）」**
- [x] **Step 2：執行測試確認失敗**
- [x] **Step 3：實作 `tapDebounceMs` 防彈跳機制，同步更新兩個生產呼叫端**
- [x] **Step 4：執行測試確認通過**
- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**
- [x] **Step 6：Commit**

---

## 完成後的驗證（對照 `issues.md` Issue 12 驗收標準）

- [x] `flutter analyze`：全專案 "No issues found!"
- [x] `flutter test`：全專案通過，零回歸
- [x] （建議，非本計畫強制自動化）真機（比照本 Epic 既有先例，於曾經回報過本問題的裝置）驗證：反覆快速按壓同一熱區，確認不再出現連續失控翻頁與畫面殘影；同時確認正常的單次點擊翻頁、以及間隔明顯（>350ms）的刻意連續翻頁操作不受影響。
- [x] 350ms 這個門檻值若真機使用後回報有需要調整（例如誤傷正常快速連續翻頁），比照 `epic-25` Issue 1／`epic-26` Issue 3 先例，另立後續工單處理，不阻塞本計畫驗收。
