# Epic 34 Issue 8 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-8.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-8.md)  
**對應工單：** [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 8（E-Ink 安全視窗與靜態高亮策略）  
**診斷依據：**
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md)（Issue 8 需求與驗收標準）
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)（User Story 13、14、高亮渲染與安全視窗規範）
- [`docs/epics/epic-34-tts-readalong/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/design.md)（E-Ink 安全視窗策略、靜態高亮與翻頁協調）
- [`docs/research/tts_integration_architecture_research.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/tts_integration_architecture_research.md)（§3.2 高亮重用、§3.3 直排繁中排版、§3.4 E-Ink 安全視窗）
- [`app/android/app/src/main/assets/foliate/main.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/main.js)（既有橋接層與 `draw-annotation` 事件處理）
- [`app/android/app/src/main/assets/foliate/paginator.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/paginator.js) 與 [`view.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/view.js)（Foliate 分頁排版、座標系統與換頁機制）
- [`app/lib/reader/foliate_reader_view.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/foliate_reader_view.dart)（Dart 橋接元件）
- [`app/lib/reader/tts_controller.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart)（TTS 狀態機與手動導覽偵測）
- [`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart) 及 [`library_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/library_screen.dart)（畫面接線與主題依賴貫穿）  
**審查日期：** 2026-08-28（複審）  
**審查結果：** **Approved（正式核准，可直接執行）**

---

## 1. 審查總結（Executive Summary）

本次複審針對首輪審查所提出的 1 項關鍵阻塞性缺陷（Critical #1：翻頁死循環震盪）以及 3 項重要防禦建議（Important #1～#3）進行逐項複核。

修訂後的實作計畫展現了高度的技術嚴謹性與對排版底層細節的掌握：
1. **徹底解決跨頁翻頁死循環（Critical #1 & Important #1 已完整修復）**：
   - 將 `next`（向前閱讀進程）改用安全視窗軟門檻（`0.2`／`0.8`），維持平滑提前翻頁體驗；
   - 將 `prev`（退回前段進程）嚴格收斂為**硬邊界（`0.0`／`1.0`）**判定，僅在段落真實溢出當前頁面範圍（如使用者連續點擊「上一句」跨回前一頁）時才觸發，杜絕了剛翻至新頁、頁首內容即被誤判為需要翻回上一頁的死循環震盪問題；
   - 納入 $X$ 與 $Y$ 雙軸正規化座標判定（`normX` 與 `normY`），精確覆蓋 Foliate multi-column 分頁機制下的跨欄位平移邊界。
2. **狀態機抑制旗標生命週期健全（Important #2 已完整修復）**：
   - 在 [`TtsController`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart) 所有 4 處重設回 `idle` 的狀態退出點（`paused` 錯誤處理、手動跳下一句到底、段落合成/播放異常、自動接續播畢）以及 `dispose()` 中，一併安全重設 `_suppressNextPositionChange = false;`，並於 Task 3 Step 1 補上了針對性的生命週期回歸測試。
3. **JS 橋接層參數型別防禦到位（Important #3 已完整修復）**：
   - 在 [`FoliateReaderView`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/foliate_reader_view.dart) 的 `onTtsHighlightOutOfSafeWindow` 回呼解析中，採用 `(args.isNotEmpty && args[0] is String)` 執行期型別檢查，避免潛在的 `TypeError`。
4. **測試斷言與反向防呆（Regression Guard Synchronization）**：
   - Task 1 Step 1 的單元測試斷言字串已完整同步為修正後的判斷式，並新增了反向防呆測試（`expect(contains(舊版對稱判斷), isFalse)`），有效防止舊邏輯意外殘留。

---

## 2. 審查檢核清單（Review Checklist）

| 檢核維度 | 評估項目 | 狀態 | 備註與技術確認 |
|---|---|:---:|---|
| **幾何算法正確性** | 安全視窗與翻頁方向判定 | **✅ 通過** | `next` 採軟門檻（0.2/0.8）、`prev` 採硬邊界（0.0/1.0），徹底消除翻頁死循環。 |
| **排版模型相容性** | Foliate Multi-column 分頁 | **✅ 通過** | 雙軸 ($normX, normY$) 綜合判定，直排/橫排皆能正確識別跨欄溢出。 |
| **狀態機抑制機制** | 自動翻頁防誤暫停 | **✅ 通過** | 旗標在 4 個 `idle` 轉換點與 `dispose()` 確實清理，附完整單元測試。 |
| **JS Handler 防禦** | 引數解析型別安全 | **✅ 通過** | `args[0] is String` 執行期檢查防禦完成。 |
| **視覺呈現分流** | E-Ink 高對比與非 E-Ink 色彩 | **✅ 良好** | `einkMode` 三元切換純色與半透明色，零動畫膨脹。 |
| **規格符合度** | Issue 8 驗收標準涵蓋 | **✅ 完整** | 跨頁自動翻頁、安全視窗不誤觸發、E-Ink 靜態顯示、不分裝置支援全數涵蓋。 |
| **架構約束與邊界** | 不修改 vendored 檔案 | **✅ 良好** | 僅異動 `main.js` 與 Dart 端程式碼，遵守 ADR 0011/0013。 |
| **測試設計與分層** | Regression guard 與單元測試 | **✅ 完整** | 提供正向與反向字串比對斷言、狀態機純 Dart 單元測試與 6 項手動真機驗收清單。 |

---

## 3. 核心設計亮點（Strengths to Preserve）

1. **非對稱安全視窗門檻設計（Asymmetric Safe Window Thresholds）**：
   深刻理解分頁模式（Paginated Mode）與連續捲動模式（Scrolled Mode）的本質差異。`next` 採用軟門檻（直排 $normX < 0.2$、橫排 $normY > 0.8$）以達到平滑的提前翻頁體驗；`prev` 採用硬邊界（直排 $normX > 1.0 \lor normY < 0.0$、橫排 $normY < 0.0 \lor normX < 0.0$），既保障了上一句跨頁回翻功能，又消除了新頁頁首誤翻的死穴。
2. **狀態機自然收斂（Clean Lifecycle Convergence）**：
   抑制旗標的清理重設沒有另立複雜的定時器或監聽器，而是自然附著在 `TtsController` 既有的 4 個重設回 `idle` 的核心路徑上，架構簡潔且無額外負擔。
3. **雙軸容錯判定（Dual-axis Fault Tolerance）**：
   在計算視窗正規化座標時，同時涵蓋主軸推進與副軸分欄平移，有效降低不同排版模式下對分欄方向假設的脆弱度。

---

## 4. 審查結論（Final Verdict）

- [x] **實作計畫審查正式通過（Approved）**
- **後續步驟：** 可使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 依據修訂後的 [`plan-issue-8.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-8.md) 啟動 Task 1 至 Task 4 的實作與測試驗證。
