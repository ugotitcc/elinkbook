# Review 報告：Issue 5 實作審查

本報告針對 `worktree-epic-0-issue-5-reader-screen-integration` 分支上，`ReaderScreen` 端到端整合（唯一 seam 完整驗證）的實作進行審查與記錄。審查流程採用 subagent-driven-development：每個 Task 各自經過獨立的 spec 合規性＋程式碼品質審查，全部任務完成後再進行一次整分支審查。

- **專案名稱**：elinkBook
- **工作區路徑**：`docs/epics/epic-0-skeleton/reviews/review-issue-5.md`
- **對應計畫**：[plan-issue-5.md](../plans/plan-issue-5.md)（含其審查回應紀錄）
- **審查 Git 範圍**：`99d363d`（merge-base）到 `0c93086`
- **提交序列**：
  - `b8f309f` Write implementation plan for Issue 5
  - `6faf554` feat(task-1): ReaderScreen 分派至真正的 EpubReaderView/PdfReaderView
  - `65956d8` fix(task-1): guard setState in async native callbacks with mounted check
  - `9a01a3b` test(task-2): 新增 ReaderScreen 端到端 integration_test（EPUB、PDF）
  - `0c93086` fix(task-2): assert loading indicator precondition before waiting for it to disappear

---

## 審查結論

### 1. 優點 (Strengths)
- **對外契約遵守嚴謹**：`ReaderScreen(filePath: String)` 全程只有 `filePath` 一個公開建構參數，未因測試或內部狀態同步而新增 `onPageRendered`/`onError` 等公開 callback，完全遵守 `spec.md` 定義的唯一對外契約。
- **狀態機設計精簡**：`_RenderState`（loading/rendered/error）三態搭配 `_buildBody`/`_buildNativeView` 拆分，邏輯清楚，未見過度抽象。
- **測試落在正確層級**：依 `spec.md`「測試決策」，EPUB/PDF 的真實渲染驗證完全交給 `integration_test`（`app/integration_test/reader_screen_test.dart`），一般 `flutter test` widget test 僅保留 `unknown` 格式分支——這不是覆蓋率倒退，而是把每種行為放到唯一能可靠驗證它的測試層級。
- **未觸碰鎖定範圍**：`EpubReaderView`、`PdfReaderView` 與所有原生 Kotlin 程式碼皆未被本分支修改，符合計畫的全域限制條件。
- **中途發現的問題皆已修正並重新驗證**：Task 1 審查發現非同步 callback 缺少 `mounted` 防護（`setState() called after dispose()` 風險）；整分支審查發現 `integration_test` 的 `_loadingIndicatorGone()` 判斷式在 Key 被改名/移除時可能造成「假陽性通過」（測試從未真正等待就通過）。兩者皆已修正、重新於真實裝置（`9491G` / `3CEF42ECD491687`，Android 15）驗證通過。

### 2. 發現的問題 (Issues)

#### Critical (Must Fix)
- 無

#### Important (Should Fix)
- **[已修正]** File: [reader_screen.dart](../../../../app/lib/screens/reader_screen.dart)（`_handlePageRendered`/`_handleError`）
  - **問題**：非同步 callback 直接呼叫 `setState()`，若使用者在原生端回呼觸發前離開 `ReaderScreen`，會拋出「setState() called after dispose()」。
  - **修正狀態**：✅ 已修正（commit `65956d8`），兩個 handler 皆加上 `if (!mounted) return;` 防護，`flutter test`/`flutter analyze` 重新驗證通過。
- **[已修正]** File: [reader_screen_test.dart](../../../../app/integration_test/reader_screen_test.dart)
  - **問題**：`_loadingIndicatorGone()` 在載入指示器 Key「消失」與「從一開始就不存在」兩種情況下回傳值相同；若 `reader_screen.dart` 未來改名/移除該 Key，測試會在第一次檢查就通過，形成假陽性（未真正驗證原生渲染即回報成功）。
  - **修正狀態**：✅ 已修正（commit `0c93086`），於 `pumpWidget` 後、`_pumpUntil` 等待迴圈前，新增 `expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget)` 前置斷言，確保該 Key 一旦失效會立即、明確地讓測試失敗。已在真實裝置上重新驗證兩項測試皆通過。

#### Minor (Nice to Have)
- **`_stageAssetAsFile` 輔助函式三處重複**：`reader_screen_test.dart`、`epub_reader_view_test.dart`、`pdf_reader_view_test.dart` 各自維護一份幾乎相同的實作。這是專案既有慣例（尚無共用 test-utils 檔案），且本工單依全域限制不得修改 Issue 3/4 的檔案，故不在本工單範圍內處理；建議後續（例如 Issue 6 新增測試時）另開工單抽出共用的 `integration_test/support/fixtures.dart`。
- **共用暫存檔名**：`reader_screen_test.dart` 與既有的 `epub_reader_view_test.dart`/`pdf_reader_view_test.dart` 在裝置暫存目錄使用相同檔名（`sample.epub`/`sample.pdf`）。目前各 `integration_test` 檔案是逐一分別執行（`flutter test integration_test/<file>.dart`），加上 `addTearDown` 清理，實務上無衝突風險；僅在未來若改為單一行程中串接執行所有 integration test 時才需要改用唯一檔名，暫不需處理。

---

## 改進建議 (Recommendations)
1. 若後續 Issue（如 Issue 6）新增更多 `integration_test`，建議一併抽出共用的 asset staging 輔助函式，避免第 4 份重複。
2. `ReaderScreen` 的 Key 觀察機制（`reader_loading_indicator`/`reader_error_text`）目前只有 `integration_test/reader_screen_test.dart` 一處消費者；未來若有更多測試依賴這兩個 Key，可考慮在 `reader_screen.dart` 中以具名常數集中管理字串，降低兩端字串不同步的風險（目前僅兩處字串，尚不構成立即必要）。

---

## 最終評估 (Assessment)

**Ready to merge: Yes**

**評估說明**：
兩個 Task 皆個別通過 spec 合規性與程式碼品質審查；整分支審查發現的唯一 Important 問題（`integration_test` 假陽性風險）已修正並在真實裝置上重新驗證。所有 `flutter test`（10/10）、`flutter analyze`（乾淨）、以及兩項 `integration_test`（EPUB、PDF，於裝置 `3CEF42ECD491687` 執行）皆通過，落實了 `spec.md`「測試決策」章節要求的驗證方式，達成本工單與 Issue 5 的驗收標準。
