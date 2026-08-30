# Epic 27 Issue 12 實作計畫審查報告

**審查目標**：[`docs/epics/epic-27-reader-device-compat/plans/plan-issue-12.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-27-reader-device-compat/plans/plan-issue-12.md)  
**審查日期**：2026-08-24  
**審查模式**：Superpowers Requesting Code Review（Pro 審查子代理全面檢核）  
**審查結論**：✅ **審查通過（Approved，可直接交付實作）**  

---

## 審查摘要與統計

| 嚴重性級別 | 數量 | 說明 |
| :--- | :---: | :--- |
| **Critical** | **0** | 無阻礙實作或破壞架構之重大缺陷 |
| **Important** | **0** | 無次要邏輯或規格遺漏缺陷 |
| **Minor** | **2** | 測試時間推進精確度與 `onPointerUp` 流程結構微調建議（見文末） |

---

## 優點（Strengths）

1. **精準的狀態作用域（Perfect State Scoping）**：
   將防彈跳邏輯封裝在 `_TapZoneDetectorState` 內部，精確對齊「同一格熱區」的物理事實。避免了跨元件全域狀態與全域鎖的複雜性，並自然讓 EPUB 與 PDF 兩條閱讀路徑同時受益。
2. **滾動冷卻窗展延設計（Rolling Debounce Cooling Window）**：
   在攔截彈跳訊號時，每次判定為合格快速點擊依然刷新 `_lastQualifyingTapUpTimeMs = nowMsValue;`。這是一個非常關鍵且優秀的細節設計——真機硬體彈跳序列長度可達 1.1 秒以上，若僅在首次放行時記錄時間，後續的彈跳雜訊會在累積超過 350ms 後被誤放行；每次彈跳都刷新冷卻窗，能完整吸收任意長度的連續硬體雜訊。
3. **實證導向的參數設定（Evidence-Based Parameters）**：
   350ms 的防彈跳門檻值並非憑空猜測，而是嚴謹地基於 `adb shell getevent` 側錄到的最大連續間隔（326ms）並加上合理餘裕推導而來，展現了高水準的工程決策。

---

## 各項檢核細節（Detailed Assessment）

1. **規格符合度與目標清晰度（Spec Alignment & Goal Clarity）**：✅
   直接針對 Issue 12 核心的觸控 IC 硬體彈跳現象，使用純軟體手段（Debounce）進行過濾。邏輯乾淨且目標聚焦，無過度工程。
2. **數值合理性（Value Rationale）**：✅
   完全基於實證（真機 `getevent` 側錄最大間隔 326ms），理由充分且留有適度餘裕，避免彈跳序列中途被意外放行。
3. **狀態與架構安全性（State & Architecture Safety）**：✅
   新增的 `_lastQualifyingTapUpTimeMs` 正確作用於單一熱區實例的生命週期。更新邏輯精確，不會干擾其他熱區（符合正常快速點擊不同熱區的合法情境）。
4. **介面完整性（Interface Completeness）**：✅
   透過新增 `required int tapDebounceMs`，強制所有呼叫端（包含 `FoliateReaderView`、`PdfReaderView` 及測試案例）提供此參數。全專案經檢索僅有這 4 個檔案建構 `TapZoneDetector`，修改清單 100% 覆蓋，無漏改風險。
5. **測試驅動開發嚴謹度（TDD Rigor）**：✅
   新增的 3 則測試涵蓋了：單次防彈跳、真機 7 次彈跳序列重播、以及超過門檻後的正常節流解除，完整防止未來重構迴歸。
6. **專案規範與慣例（Conventions）**：✅
   文件與註解均使用標準正體中文 (zh-TW)，嚴格遵守專案語法慣例及架構設計紀錄（ADR 0011）。

---

## 建議與觀察（Suggestions & Observations）

以下 2 項 **Minor（輕微建議）** 供實作者在編寫程式碼時參考與微調即可，不影響計畫審查通過狀態：

### Minor 1：測試時間間隔的精確度微調（Test Timing Precision）
在 Step 1 的真機實際側錄間隔回歸測試中：
```dart
const observedGapsMs = [86, 152, 261, 326, 87, 207];
for (final gapMs in observedGapsMs) {
  fakeNowMs += gapMs;
  final gesture = await tester.startGesture(const Offset(50, 50));
  fakeNowMs += 20; // 模擬按下到放開的耗時
  await gesture.up();
}
```
註解提及 `observedGapsMs` 是「相鄰按下事件間隔（DOWN to DOWN）」。在迴圈中，`fakeNowMs` 每次遞增 `gapMs` 加上內部的 `20ms` 耗時，會使實際測試裡的 DOWN to DOWN 間隔變為 `gapMs + 20`。  
雖然在最大值 `326 + 20 = 346ms` 時依然小於 350ms 門檻，測試可順利通過，但若要完全精準重播真機時序，建議將推進時間調整為 `fakeNowMs += (gapMs - 20)`（或在註解明確說明 `gapMs` 被視為 UP to DOWN 的間隔）。

### Minor 2：避免提早 `return` 可能造成的流程結構副作用（Early Return Structure）
在 `onPointerUp` 的修改設計中：
```dart
if (previousTapUpTimeMs != null && nowMsValue - previousTapUpTimeMs < widget.tapDebounceMs) {
  // ...略...
  return;
}
widget.onTap();
```
為了確保 `onPointerUp` 結尾處若未來增加通用狀態清理邏輯時不被跳過，建議將 `widget.onTap()` 包裝於條件區塊內，使函式維持單一退出路徑：
```dart
if (previousTapUpTimeMs == null || nowMsValue - previousTapUpTimeMs >= widget.tapDebounceMs) {
  widget.onTap();
}
```

---

## 結論

實作計畫 `plan-issue-12.md` 架構清晰、實證充分、TDD 步驟詳實，具備極高的工程品質與防禦力，**予以審查通過（Ready to implement）**。
