# Code Review 報告：Issue 4 實作 - 原生 Android 模組 `EpubReaderView`

本報告針對分支 `worktree-epic-0-issue-4-epub-reader-view`（工作區路徑：`U:\MyDeveloper\AI\elinkBook\.claude\worktrees\epic-0-issue-4-epub-reader-view`）的變更進行唯讀審查。審查範圍為 `b3a2434` 至 `7956fa9` 的變更。

---

## 成果與優點 (Strengths)

*   **完整的架構對稱性 (Architectural Symmetry)**：`EpubReaderView` Dart/Kotlin 雙端實作在 channel 契約（`openBook`, `onPageRendered`, `onError`）、型別、方法命名上，均與 Issue 3 的 [PdfReaderView](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/lib/reader/pdf_reader_view.dart) 保持完全一致的對稱設計，大幅降低整體 codebase 的理解與維護難度。
*   **嚴謹的 Process Death 重建防崩潰機制 (Robust Process Death Safety)**：在 [MainActivity.kt](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt#L10-L29) 中引入了 `EpubNavigatorFragment.createDummyFactory()` 作為 fallback，並在 `onCreate` 生命週期中安全過濾與移出被系統自動還原的 `EpubNavigatorFragment`，有效阻止因 Fragment internal 建構子無法呼叫而引發的重啟崩潰，充分體現對 Android 系統生命週期的深刻掌握。
*   **完善的資源釋放與生命週期管理 (Leak-free Resource Management)**：在 Kotlin 協程非同步解析 Publication 期間加入了 `isDisposed` 的主動活性檢查 (liveness check)；在 [EpubReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L180-L190) 的 `dispose` 及異常捕獲 (catch block) 中均有確實呼叫 `openedPublication.close()` 與取消 CoroutineScope，防範了極難排查的記憶體與 Native 資源洩漏。
*   **細緻的異常與邊界攔截 (Graceful Error Boundaries)**：針對 `FragmentTransaction.commitNow` 可能因 Activity 生命週期已過 state saving 或 Hybrid Composition 合成模式異動引發的 exceptions（`IllegalStateException` / `IllegalArgumentException`），設計了完善 of `try-catch` 邊界阻截（[EpubReaderView.kt:L140-L159](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L140-L159)），並轉化為 Flutter channel 的 `onError` 回報，防止 Android 端發生未捕獲協程例外導致 Crash。
*   **真實裝置測試驗證 (True Device Verification)**：整合測試 [epub_reader_view_test.dart](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/integration_test/epub_reader_view_test.dart) 精準實作了 Asset 複製到暫存目錄的載入方案，提供真實的 EPUB 開啟（成功觸發 `onPageRendered`）與非存在檔案（觸發 `onError`）雙重情境覆寫，且在 `addTearDown` 裡落實暫存檔清理。

---

## 發現之問題 (Issues)

### 🔴 Critical (Must Fix)
*   無重大 Critical 問題。

### 🟡 Important (Should Fix)

#### 1. Activity 全局 FragmentFactory 被覆寫與 Routing Transition 造成的生命週期競態風險
*   **檔案位置**：[EpubReaderView.kt:L76](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L76)、[L143-L148](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L143-L148)、[L187](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L187)
*   **具體問題**：`EpubReaderView` 實例會直接操作全局的 `activity.supportFragmentManager.fragmentFactory`。在 Flutter Routing 轉場（Transition）期間，新舊畫面的 `PlatformView` 會短暫共存。例如：
    1. 舊畫面 A 書閱覽中（`fragmentFactory` = `FactoryA`），使用者切換到新畫面 B 書。
    2. B 畫面初始化，B 的 `previousFragmentFactory` 讀取到當時的 `FactoryA`。
    3. B 隨後將 `fragmentFactory` 設為 `FactoryB`。
    4. 轉場完成，A 被 dispose。A 的 `dispose()` 將 Activity 全局的 `fragmentFactory` 恢復為 A 的 `previousFragmentFactory`（即 `FactoryA`）。
    5. 此時 B 書仍在畫面上，但 Activity 的 `fragmentFactory` 已被意外覆寫回 `FactoryA`！
*   **影響層面**：此時若系統發生任何需要重建 Fragment 的行為（如旋轉螢幕、低記憶體回收重啟等），B 畫面將因無法用 `FactoryA` 實例化 B 書的 `EpubNavigatorFragment` 而導致重啟崩潰或還原失敗。
*   **修正建議**：在 `EpubReaderView` 中引入一個簡單的 active 實例計數器，或檢查目前覆寫的 factory 是否為本實例所持有。最安全的做法是在 `EpubReaderView` 的 companion object 中維護一個 `activeInstances` 計數器，當計數遞減為 0 時才將 factory 恢復成 `dummyFactory`，且在 `dispose()` 還原時，加上 `if (activity.supportFragmentManager.fragmentFactory === ourFactory)` 判斷。

#### 2. `dispose()` 中 `commitNow` 缺乏異常保護可能引起 Flutter 引擎級崩潰
*   **檔案位置**：[EpubReaderView.kt:L183-L186](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L183-L186)
*   **具體問題**：在 `dispose()` 移出 Fragment 時，直接調用了 `commitNow(allowStateLoss = true)`，但外部沒有任何 `try-catch` 保護。
*   **影響層面**：雖然通常情況下移除是安全的，但若 Flutter Teardown 期間 FragmentManager 處於 transaction 巢狀狀態或 state saving 後的唯讀狀態，`commitNow` 會拋出 `IllegalStateException`。這會導致異常向上拋回 Flutter 宿主，可能引發 Flutter 引擎級的非預期崩潰。
*   **修正建議**：在 `dispose()` 移出 Fragment 的區塊加上 `try-catch (e: Exception)` 保護，或改用安全但非同步的 `commitAllowingStateLoss()`。

### 🔵 Minor (Nice to Have)

#### 1. Flutter `minSdk` 自動改寫的永久解決方案
*   **檔案位置**：[build.gradle.kts:L30](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/build.gradle.kts#L30)
*   **具體問題**：Flutter 內置的 `min_sdk_version_migration.dart` 自動遷移工具在執行建置/測試命令時，只要檢測到 `minSdk = 23` 這種硬編碼數字（在觸發區間內），值就會用正則表達式強行覆寫為 `minSdk = flutter.minSdkVersion`。
*   **影響層面**：目前採用的解決方式是手動 `git diff` 並 `git checkout` 還原，這增加了開發摩擦力，且不利於 CI/CD 自動化建置。
*   **修正建議**：藉由修改宣告模式來繞過 Flutter 工具的正則表達式偵測。可以在 `build.gradle.kts` 中將 `minSdk` 改以變數形式宣告：
    ```kotlin
    val projectMinSdk = 23
    defaultConfig {
        minSdk = projectMinSdk
        // ...
    }
    ```
    如此一來，Flutter 的正則表達式 `minSdk\s*=\s*(?<version>\d+)` 將無法匹配到數字字串，進而永久跳過該改寫，同時 Gradle 仍能正確接收變數設定值。

#### 2. `openBook()` 協程內部缺乏頂層未捕獲異常保護
*   **檔案位置**：[EpubReaderView.kt:L103-L131](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt#L103-L131)
*   **具體問題**：協程 `scope.launch` 內部的 `DefaultHttpClient()` / `AssetRetriever` / `DefaultPublicationParser` 建構或調用拋出的 runtime 異常，目前沒有頂層的 `try-catch` 攔截，且 `scope` 未設置 `CoroutineExceptionHandler`。
*   **影響層面**：若底層發生非預期 Exception，將成為未捕獲例外，可能繞過 MethodChannel 錯誤通知，進而導致 Flutter 端加載狀態卡死。
*   **修正建議**：建議將整個 `scope.launch` 內容包裝在 `try-catch (e: Exception)` 區塊中，並在 catch 中調用 `channel.invokeMethod("onError", ...)`。

#### 3. 整合測試可加入損毀檔案的驗證
*   **檔案位置**：[epub_reader_view_test.dart:L61](file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-0-issue-4-epub-reader-view/app/integration_test/epub_reader_view_test.dart#L61)
*   **具體問題**：整合測試目前僅驗證了「有效檔案」與「不存在的檔案路徑」。
*   **影響層面**：缺少「內容已損毀的非法 EPUB 檔案」之測試，無法完整驗證 Readium 解析出錯時的 `onError` 返回機制。
*   **修正建議**：新增一個測試案例，建立一個寫入隨機 bytes 的無效 `.epub` 檔，傳入 `EpubReaderView`，驗證其是否亦能正確觸發 `onError` 流程。

---

## 改善建議 (Recommendations)
1.  **實作計數或工廠安全的 FragmentFactory 委派機制**：建議在 `EpubReaderView` 中加入 `activeInstances` 計算及覆寫校驗，避免在轉場或多實例 co-exist 時造成全局 `fragmentFactory` 狀態污染。
2.  **採用 `minSdk` 變數宣告**：將 `minSdk` 宣告改為 `val projectMinSdk = 23; minSdk = projectMinSdk`，將可徹底杜絕 Flutter 自動化腳本在開發與建置時造成的代碼庫檔案污染，使 CI/CD 行程更穩定。

---

## 審查評估 (Assessment)

**Ready to merge?** With fixes (修正後可合併)

**Reasoning:**
該分支實作完整且單體測試非常充足，但由於 `MainActivity` 全局 `fragmentFactory` 覆寫在轉場（Transition）與 `dispose` 過程中有導致其他 View 或重建時崩潰的競態風險，強烈建議修正 `fragmentFactory` 的覆寫邏輯以及 `dispose` 內部的 `commitNow` 異常保護後再行合併。
