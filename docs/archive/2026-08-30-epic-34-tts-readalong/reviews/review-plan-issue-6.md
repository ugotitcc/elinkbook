# Epic 34 Issue 6 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-6.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-6.md)  
**對應工單：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 6（Mini Player 完整 UI）  
**診斷依據：**
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md)（Issue 6 需求與驗收標準）
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)（`ReaderScreen` 整合與版面層級決策）
- [`docs/epics/epic-34-tts-readalong/reviews/review-issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/reviews/review-issues.md) Minor #1（單一事實來源 SSoT 要求）
- [`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart)（既有浮動按鈕與頁尾疊加層實作）
- [`app/test/screens/reader_screen_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/screens/reader_screen_test.dart)（既有 TTS widget 測試斷言）  
**審查日期：** 2026-08-28  
**審查結果：** **Approved（正式核准，可直接進行開發）**

---

## 1. 審查總結（Executive Summary）

實作計畫設計清晰、職責劃分精確，完全符合規格書與工單驗收標準：
1. **元件高度解耦且堅守單一事實來源（SSoT）**：
   - 新增的 [`TtsMiniPlayer`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/tts_mini_player.dart) 比照既有 [`AnnotationToolbar`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/annotation_toolbar.dart) 設計為純 `StatelessWidget`，不直接持有 [`TtsController`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart)，完全由建構參數（`status`、`speed`、`isCbz` 等）與回呼函式驅動，內部無私有狀態。
   - 呼叫端 [`ReaderScreen`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart) 透過 `AnimatedBuilder(animation: _ttsControllerOrNull!)` 進行單點訂閱與局部重建，當播放狀態或語速變更時自動同步刷新，無需額外手動同步邏輯。
2. **版面層疊與底部導覽連動安全**：
   - 定義動態 getter `_ttsMiniPlayerBottomOffset`，與既有頁尾進度文字（`_buildFoliateProgressText()`）的顯示條件完全對齊（`showFooter` 為 true 且總頁數 > 0 時偏移 40dp，否則偏移 12dp），精確避免視覺重疊。
   - 目錄側邊欄（`showModalBottomSheet`）由 Flutter `Navigator`/`Overlay` 機制天然阻隔，無需額外狀態控制。
3. **無破壞性重構與既有測試 100% 保留**：
   - 保留完全一致的 4 個 `Key` 名稱（`reader_tts_play_pause_button`、`reader_tts_previous_button`、`reader_tts_next_button`、`reader_tts_speed_button`）與 `Icon`/`Text` 語意，保證既有 Issue 2、Issue 3、Issue 4、Issue 5 的 `reader_screen_test.dart` 測試零修改綠燈通過。
   - CBZ 圖像格式維持「顯示但停用（`onPressed: null`）」的單鍵設計，其餘 3 顆控制按鈕安全排除。
4. **TDD 與測試分工嚴謹**：
   - Task 1 提供獨立 `tts_mini_player_test.dart`（11 個 widget test 覆蓋非 CBZ 完整互動與 CBZ 停用邏輯）。
   - Task 2 在 `reader_screen_test.dart` 補齊頁尾共存與無 provider 邊界測試。

---

## 2. 審查檢核清單（Review Checklist）

| 檢核維度 | 評估項目 | 狀態 | 備註與技術確認 |
|---|---|:---:|---|
| **規格符合度** | Issue 6 驗收標準覆蓋 | **✅ 完整** | 整合播放/暫停/上一句/下一句/語速控制；底部連動防遮擋；零回歸保證。 |
| **架構設計** | 單一事實來源（SSoT） | **✅ 良好** | `TtsMiniPlayer` 為純 `StatelessWidget`，由 `AnimatedBuilder` 驅動。 |
| **元件封裝** | 解耦與可測試性 | **✅ 良好** | 元件不依賴 WebView 或 Reader 全域狀態，可完全獨立 pump 測試。 |
| **版面佈局** | 底部動態偏移量 | **✅ 良好** | `_ttsMiniPlayerBottomOffset` 依 `showFooter` 與總頁數動態計算（40dp vs. 12dp）。 |
| **格式相容** | CBZ 停用邏輯與按鈕排除 | **✅ 良好** | CBZ 模式下只顯示停用的播放鍵，其餘 3 鍵安全隱藏。 |
| **測試品質** | 測試覆蓋率與 TDD 節奏 | **✅ 完整** | 包含 11 個單元測試與 2 個整合接線測試，步驟皆有明確期望輸出。 |
| **相容性** | 既有 Key 與測試相容 | **✅ 零回歸** | 4 個 Key 名稱未變更，既有測試無須修改即可通過。 |

---

## 3. 核心設計亮點（Strengths to Preserve）

1. **極簡純粹的展示型元件（Dumb Presentation Component）**：
   `TtsMiniPlayer` 保持純粹的 UI 渲染職責，將所有邏輯（播放器操作、語速切換序列、段落跳轉）完整保留於 `TtsController` 與 `ReaderScreen`，提升元件重用性與單元測試穩定度。
2. **精準的動態底部讓位機制（Dynamic Footer Clearance）**：
   `_ttsMiniPlayerBottomOffset` 透過 `(_resolved?.showFooter ?? false) && (_epubPositionInfo?.displayTotalPages ?? 0) > 0` 判定，與 `_buildFoliateProgressText()` 條件一致，在有頁尾進度文字時自動上移至 40dp，確保視覺平衡且不干擾文字閱讀。
3. **誠實的邊界與真機驗收規劃（Honest Testing Boundaries）**：
   計畫在「測試策略總結」中誠實記錄了直排模式（`vertical-rl`）與 TOC 遮罩等需透過真機手動確認的項目，並制定了清晰的 5 項人工驗證情境。

---

## 4. 觀察與後續備忘（Observations & Notes）

以下項目為非阻塞性觀察，實作時依既有計畫執行即可：

1. **直排模式（Vertical Writing Mode）視覺留白**：
   在直排模式下，頁尾文字旋轉於左側邊緣（`RotatedBox`），底部中央並無實體文字佔用。目前 `_ttsMiniPlayerBottomOffset` 在直排模式下若滿足 `footerVisible` 仍會偏移 40dp。如計畫所述，此間距屬安全預留，合併前可透過真機手動驗收觀察視覺美觀度，必要時於後續視覺微調工單優化。
2. **窄螢幕極限寬度餘裕**：
   `TtsMiniPlayer` 包含 4 顆 `IconButton`（寬度約 200dp），在 `Positioned(left: 16, right: 16)` 搭配 `Center` 的約束下，即使在 320dp 極窄螢幕上仍有充足寬度餘裕（288dp 可用寬度），不會發生橫向 overflow。

---

## 5. 審查結論（Final Verdict）

- [x] **實作計畫審查正式通過（Approved）**
- **後續步驟：** 可使用 `superpowers:subagent-driven-development` 依據 [`plan-issue-6.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-6.md) 啟動 Task 1 與 Task 2 的實作與測試驗證。
