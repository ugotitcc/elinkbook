# Epic 34 Issue 3 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-3.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-3.md)  
**對應工單：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 3：同步高亮跟隨（Read-along）  
**診斷依據：** 
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)「Implementation Decisions」高亮渲染段落
- [`docs/adr/0026-tts-highlight-ephemeral-not-persisted.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0026-tts-highlight-ephemeral-not-persisted.md)
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 3 驗收標準  
**審查日期：** 2026-08-27  
**審查性質：** 實作計畫可行性、步驟精確度、邊界約束與驗收覆蓋審查（Implementation Plan Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved with minor adjustments（核准通過，微調建議後即可進入執行階段）**

本實作計畫針對 Issue 3「同步高亮跟隨」規劃了高內聚、低耦合且符合專案工程規範的雙向橋接與狀態通知機制。

計畫具備以下卓越設計：
1. **完美的 ADR 0026 隔離策略**：利用 `foliate-note:` 前綴將 TTS 暫態高亮獨立於劃線與備註的 Key 空間，不修改任何 vendored `foliate-js` 程式碼，且保證高亮全程不寫入 `highlights`/`notes` 資料表。
2. **直排/橫排跟隨保證**：利用 `draw-annotation` 事件中對 `annotation.vertical` 的顯式覆寫，結合 Dart 端動態讀取 `_resolved?.writingMode` 來決定排版方向，徹底消成了螢幕旋轉或手動切換直橫排時的同步延遲。
3. **高品質的 TDD 單元與回歸測試**：不僅涵蓋了 `main.js` 的原始碼 regression guard 檢驗，也在 `tts_controller_test.dart` 內為 `onHighlightSegment` 的四個狀態生命週期建立了嚴謹的非同步測試。

---

## 2. 審查意見與提醒（Observations & Tips）

### 🔴 Critical (嚴重阻礙)
無。

---

### ⚠️ Important (重要建議)
1. **`reader_screen.dart` 中缺少 `tts_segment_cfi.dart` 的顯式引入**
   - **檔案位置**：[`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart)
   - **問題描述**：在 Task 3 Step 2 中，我們在 `_ttsControllerOrNull` 屬性建構的 `onHighlightSegment` 回呼裡使用參數 `segment` 的屬性 `segment.cfi`。由於 `TtsSegmentCfi` 的型別定義於 `tts_segment_cfi.dart` 中，而 `reader_screen.dart` 並未顯式引入該檔案。雖然 Dart 編譯器能透過 transitive dependency 與類型推導獲取其成員，但在專案的靜態分析（`flutter analyze`）與程式碼可讀性要求下，建議顯式引入。
   - **建議修復**：在 `reader_screen.dart` 的 imports 區塊頂部新增 `import '../reader/tts_segment_cfi.dart';`。

---

### 💡 Minor (執行提醒)
1. **JS 端的非同步 add/delete 競態確認**
   - **細節說明**：`main.js` 中的 `window.showTtsHighlight` 先呼叫了非同步的 `view.deleteAnnotation` 再呼叫 `view.addAnnotation`，兩者皆涉及 `this.resolveNavigation(cfi)`。經確認，`view.js` 中的 `resolveNavigation` 實際上是同步執行的，但由於 `addAnnotation` 宣告為 `async`，這兩個呼叫將被包裝為 Promise 並在 Microtask Queue 中依序執行。這保證了 `delete` 必定在 `add` 之前完成，不需額外的防競態鎖，設計十分安全。
2. **與後續工單（Issue 4）清除時機的相容性防護**
   - **細節說明**：本計畫的高亮清除主要靠 `TtsController` 向 `onHighlightSegment` 發送 `null` 信號，進而呼叫 `clearTtsHighlight`。後續 Issue 4（手動導覽自動暫停）要求在 relocate 時清除高亮。請在執行 Issue 3 與後續 Issue 4 時，確認這兩處清除高亮的路徑不會發生多餘的同步競態或 NullPointer。本計畫在 Foliate JS 橋接層設計的 `currentTtsAnnotationValue` 狀態隔離方案已為此奠定了很好的相容基礎。

---

## 3. 核心計畫亮點（Strengths）

1. **極佳的 JS 橋接解耦**：
   - `window.showTtsHighlight`/`clearTtsHighlight` 使用了 `foliate-note:` 的 key 空間隔離，成功避開了對 `foliate-js` 核心 vendored 原始碼的修改，遵循了 ADR 0011 / 0013。
2. **嚴格的單一事實來源與 UI 無痛同步**：
   - 狀態完全委託給 `TtsController`（ChangeNotifier），UI 交互僅作為觀察者（`AnimatedBuilder`）和觸發者，結構明晰。
3. **無寫入防禦測試**：
   - Task 3 新增了 `highlightsRepository`/`notesRepository` 內容於 TTS 播放按鈕點擊後保持不變的 widget test，在自動化層面嚴格把關了 ADR 0026 規範。

---

## 4. 結論與下一步（Conclusion & Next Steps）

本實作計畫架構完備、邏輯健全、測試覆蓋扎實，核准通過。

- [x] **實作計畫審查通過（Approved with minor adjustments）**
- **下一步**：請在開始實作時，於 [`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart) 新增 `import '../reader/tts_segment_cfi.dart';`。隨後可呼叫 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 開始執行計畫。
