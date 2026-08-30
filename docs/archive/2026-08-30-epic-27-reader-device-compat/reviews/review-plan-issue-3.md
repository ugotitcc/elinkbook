# Epic 27 Issue 3 實作計畫審查報告

**審查對象：** `docs/epics/epic-27-reader-device-compat/plans/plan-issue-3.md`  
**審查目標：** 審查「開 App／開書時畫面整個黑色一段時間」實作計畫之架構合理性、圖層層級（z-order）、測試設計、邊界防禦與可執行性。  
**審查標準：** 需求與根因對齊、原生渲染層級覆蓋有效性、TDD 測試覆蓋率與指令精確度、非必要改動排除（YAGNI）。  
**審查狀態：** ✅ 技術審查通過（Ready to implement）

---

## 1. 優點與亮點 (Strengths)

1. **圖層層級（z-order）修正徹底，精準解決真機黑屏覆蓋問題**：
   - 計畫在 Task 1 Step 3 中，將不透明主題遮罩精準放置於 `_buildNativeView` **之後（上方）**、FAB 按鈕群 **之前（下方）**。
   - 配合 `if (_state == _RenderState.loading)` 條件，確保在原生視圖（`InAppWebView`／`pdfrx`）於 Android 底層繪製首幀黑色緩衝區期間，主題遮罩能 100% 遮蔽黑幀；一旦 `onPageRendered` 觸發，遮罩隨即從 widget tree 移除，無縫露出書頁內容，既解決黑屏又絕不干擾後續閱讀與觸控手勢。

2. **在純 Dart 測試環境中構造精妙的 z-order 回歸防呆斷言**：
   - 鑑於純 Dart `flutter test` 無法渲染真實 GPU 緩衝區，計畫在 Task 1 Step 1 測試中，創新地透過 `tester.widget<Stack>(find.byKey(const Key('reader_body_stack')))` 讀取 `Stack.children` 清單，並直接斷言 `placeholderIndex > nativeViewIndex`。
   - 此設計極為嚴謹，將靜態 UI 圖層順序轉化為可自動化驗證的單元測試，徹底防範未來重構時誤調子元件順序而產生回歸。

3. **設計決策論述扎實，邏輯自洽**：
   - 「設計決策 1」深入論述了推翻初版「恆常墊底」的架構理由：遮罩若移至原生視圖之上，若維持恆常顯示將永久蓋住已渲染書籍；唯有綁定 `_state == loading` 才能兼顧「遮蔽黑幀」與「正常閱讀」。
   - 「設計決策 2」清楚剖析了 `main.dart:29-108` 的同步初始化依賴鏈（SQLite 共享連線、多 Repository 依賴與 `SyncEngine`），果斷保留現有同步初始化結構，忠實恪守 YAGNI 與「不做超出需求的彈性設計」原則。

4. **TDD 流程、測試過濾參數與行號 100% 精準對齊**：
   - Step 2 測試過濾參數已修正為 `--plain-name "epic-27-reader-device-compat Issue 3"`，可完整涵蓋 Step 1 所定義的 3 則測試（含 loading 中存在斷言、z-order 斷言、以及渲染完成後消失斷言）。
   - 經與程式庫交叉核對：`reader_screen.dart:2050-2066` 與 `reader_screen_test.dart:5198-5200` 之行號與上下文代碼完全吻合，具備極高的可操作性。

---

## 2. 審查修訂歷程與問題檢核 (Issues Verification)

本輪複審針對初版審查提出的問題進行逐一驗證：

| 項目代號 | 原始問題描述 | 修正狀況 | 複審結果 |
| :--- | :--- | :--- | :--- |
| **Critical #1** | 底色層 z-order 置於 `_buildNativeView` 下方將導致原生黑屏無法被遮蓋 | 已將遮罩移至 `_buildNativeView` 上方，並綁定 `_state == loading`，渲染完成立即移除 | ✅ **已完全解決** |
| **Important #1** | Step 2 測試過濾指令無法匹配 Step 1 第 3 則測試 | Step 2 測試指令改為 `--plain-name "epic-27-reader-device-compat Issue 3"`，三則測試皆可命中 | ✅ **已完全解決** |
| **Minor #1** | 測試斷言需隨 z-order 調整同步更新 | 第 3 則測試已改為驗證渲染完成後 `find.byKey(...)` 為 `findsNothing` | ✅ **已完全解決** |

經全面複審，本計畫已無任何未解之 Critical、Important 或 Minor 疑慮。

---

## 3. 實作建議 (Recommendations)

1. **嚴格遵循 TDD Red-Green-Refactor 流程**：
   - 請執行者在 Step 1 新增測試後，務必先執行 Step 2 確認 3 則測試皆紅燈（FAIL），再進行 Step 3 的程式碼修改，確保測試發揮防禦效益。
2. **維持靜態分析與全專案測試零警告**：
   - 實作完成後執行 `flutter analyze` 與 `flutter test`，確保專案乾淨無回歸。

---

## 4. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**  
  **【是 / 準備好開始實作 (Ready to implement)】**

- **評估理由：**  
  修訂後的實作計畫完美修正了前一輪審查發現的 z-order 圖層缺陷與測試過濾瑕疵；架構邏輯嚴謹、測試設計包含創新的 `Stack.children` 順序防呆驗證、行號引用 100% 精準，已完全具備立即實作之條件。
