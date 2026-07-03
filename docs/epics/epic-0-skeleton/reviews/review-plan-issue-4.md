# 文件審查報告：plan-issue-4.md (Issue 4 實作計劃) - 複審通過

本報告為針對 `plan-issue-4.md` 計劃文件的複審記錄。本審查為 **唯讀 (Read-Only) 報告**，未對原始計劃文件進行任何修改。

- **審查對象**：[plan-issue-4.md](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-0-skeleton/plans/plan-issue-4.md)
- **報告路徑**：`docs/epics/epic-0-skeleton/reviews/review-plan-issue-4.md`
- **複審狀態**：複審通過，計劃文件更新完備，無殘留問題。

---

## 複審意見回覆紀錄與變更核對

### 1. FragmentFactory 覆寫與 Process-Death 處理 (Kotlin 端)
* **審查建議**：Activity 層級全域覆寫 `fragmentFactory` 會導致其他 Fragment 的 factory 被覆蓋；且在 Process-Death 重建時，因沒有 Publication 實例重建真正的 Fragment，預設無參建構子會導致崩潰。
* **核對結果**：**已修正 (優化實作)**。
  * **衝突預防**：實作中在 `EpubReaderView` 初始化時儲存了 `previousFragmentFactory`，並在 `dispose` 時予以還原，避免了 Activity 全域層級 `FragmentFactory` 的長期覆寫衝突。
  * **崩潰預防**：在 `MainActivity.onCreate()` 中註冊了 Readium 官方推薦的 `EpubNavigatorFragment.createDummyFactory()`。更精確地，針對單一 Activity 架構，計劃並未採用官方一律 `finish()` Activity 的粗暴作法，而是檢測 `savedInstanceState` 重建時，僅移除被還原的 `EpubNavigatorFragment` 實例，在確保不崩潰的前提下，保障了應用程式其他功能頁面的正常運行。符合 YAGNI 與最佳效能。

### 2. 非同步生命週期活性檢查
* **審查建議**：在非同步加載期間如果 View 被銷毀（`dispose()` 已執行），協程內部不會在同步 `attachNavigator()` 中自動檢查取消狀態，可能導致將 Fragment 掛載到已銷毀的 container 上。
* **核對結果**：**已修正**。
  * 引入了 `isDisposed` 旗標。在 `openBook` 的協程中，於非同步獲取 `Publication` 後與調用同步 `attachNavigator()` 之前，手動檢查 `isDisposed` 狀態。
  * 若已被銷毀，則關閉 Publication 並提早返回，有效消除了因協程無法在同步區間內取消而導致向已銷毀的 container 掛載 Fragment 的競態風險。

### 3. Publication 資源洩漏 (Leak)
* **審查建議**：`EpubReaderView` 被 dispose 時未呼叫 `publication.close()`，會造成嚴重資源洩漏。
* **核對結果**：**已修正**。
  * 正確在 `EpubReaderView.dispose()` 中調用 `publication?.close()`，並將其置空。
  * 此外，在 `openBook` 因 `isDisposed` 提前退出的邊界分支中，亦妥善執行了 `openedPublication.close()`，確保資源釋放無死角。

### 4. Integration Test 暫存檔案未清理
* **審查建議**：測試過程中 staged 的暫存 EPUB 檔案拷貝至 `getTemporaryDirectory()`，測試結束後未進行清理。
* **核對結果**：**已修正**。
  * 在 `epub_reader_view_test.dart` 的「開啟有效 EPUB 檔案觸發 onPageRendered」測試案例中，透過 `addTearDown` 註冊了刪除暫存 `sample.epub` 檔案的清理邏輯，防止測試設備/模擬器的快取目錄隨著測試執行次數增加而無限累積。

### 5. minSdk 被 Flutter 自動改寫問題
* **審查建議**：Flutter 內建的遷移工具會自動覆寫 Gradle 中的 `minSdk`，建議使用 `local.properties` 的根本解決方案。
* **核對結果**：**已合理回應並提供實作指南**。
  * 計劃中查證並揭露了 Flutter 工具鏈的底層機制（`minSdkVersion` 是寫死在 Flutter SDK 中的常數，並非讀取任何專案設定檔），因而無法藉由 `local.properties` 繞過。
  * 修改後的計劃中，在 Gradle 任務和測試任務執行步驟後加入了 `git diff` 檢查提示，並在最終 Git Commit 前手動還原 `minSdk` 為 `23` 的防禦性執行步驟，是目前最可行且不易出錯的務實方案。

---

## 最終評估 (Assessment)

**Ready to implement: Yes**

**評估說明**：
實作計劃非常嚴謹且詳盡，針對 Readium Toolkit 的整合點進行了深入的技術查證與合理變更。特別是全面解決了生命週期活性、資源洩漏、Process-Death 重建及 Flutter Gradle 工具鏈改寫 minSdk 等核心邊界問題，且沒有引入額外複雜度，已具備極高的完備度，可以直接交付執行。
