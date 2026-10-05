# epic-54-architecture-optimization Issues

| # | 標題 | 強度 | 狀態 |
|---|---|---|---|
| 1 | 可用字型：收攏「偏好字型現在能不能用」規則（`AvailableFonts`） | Strong | 🟢 已合併（PR #302） |
| 2 | 同步與雲端匯入的「憑證失效」訊號形狀對齊（同步端已由 epic-53 對齊，僅需確認是否還有落差） | Worth exploring | 🟢 已合併（PR #306） |
| 3 | 字型重新連結搬出 Widget，與書籍重新連結（`relinkBook`）對齊；`takePersistableUriPermission` 授權策略集中 | Worth exploring | 🟢 已合併（PR #304） |
| 4 | 儲存權限探測移出 `foliate_native_bridge.dart`，改為獨立於閱讀器引擎的 module | Worth exploring | 🟢 已合併（PR #305） |
| 5 | 抽出 `ReaderScreen` 的「開書失敗、探測、重連、重開」狀態機（`OpenBookFlow`） | Worth exploring | 🟢 已合併（PR #303） |
| 6 | 為四份 ARB 鍵一致性加自動守衛（鍵集合比對＋「刻意相同」白名單） | Worth exploring | 🟢 已合併（PR #307） |
| 7 | 位置寫入規則（「寫不寫、寫什麼」）搬出 `ReaderScreen`，成為可獨立測試的 module；先做，直接 TDD＋寫 plan | Strong | 🟢 已合併（PR #310） |
| 8 | 抽出「閱讀會話」生命週期協調（統計、前後景、位置寫入呼叫、Checkpoint Timer）；依賴 Issue 7，後做，寫 plan | Strong | 🟢 已合併（PR #311） |
| 9 | （缺陷，待確認）帶跳轉目標開書時，Foliate 重排產生的「同位置重複回報」讓跳轉保護提早失效，離開時可能把跳轉落點存成新進度；由 Issue 7 程式審查 Minor 3 發現，Issue 7 為零行為變化故未修 | — | 🟢 已合併（PR #312） |
| 10 | 版面覆寫等「整列重建 `BookReaderPrefs`」處加全欄位保留守衛（種子填滿 33 欄位，儲存後除被覆寫欄位外須原樣相等）；來源：epic-57 程式審查 M-1。選配：`copyWith` 支援明確傳 null（Sentinel）以根除整列重建 | Worth exploring | ⚪ 待規劃 |
| 11 | 閱讀器功能依賴組 `ReaderFeatureDependencies`：`ReaderScreen`（應用層依賴收斂為 1 個物件，含 `syncCheckpointTrigger`；`readingStatsTracker`／`pickSingleBookFile` 留作測試注入點）與 `BookSearchScreen`，消除 `reader_screen.dart` 手動逐欄重建。Task 1 先建 `test/support/fake_reader_feature_dependencies.dart`（預設全 fake、支援具名覆寫）並通過自身測試，才改 `ReaderScreen` 建構子。`ttsProvider`／`searchRepository` 的 null 判斷須改為明確的「不可用」表示（adapter 或旗標，plan 定案）。尚未遷移的 `LibraryScreen`／`LibrarySearchScreen` 由 `buildReaderScreen` 暫時組裝（Issue 12/13 移除）。先做，完成後確認設計成立再往下；依 ADR 0037 | Strong | 🟡 實作完成，待程式審查 |
| 12 | `SyncDependencies`：`LibraryScreen`、`LibrarySearchScreen`（全庫搜尋）、`SettingsScaffold`、`AdaptiveShellScaffold` 改收依賴組；`LibrarySearchScreen` 自己的必填 `searchRepository` 參數與 bundle 內的 `searchRepository` 欄位須合併為一個來源，並移除 `readerFeatureDependenciesFromLegacy` 的 `searchRepository` 覆寫參數（Issue 11 程式審查 M-1）；依賴 Issue 11 | Strong | ⚪ 待規劃 |
| 13 | `SourceDependencies`（雲端帳號與 OAuth／storage client、`remoteServerRepository`、OPDS、`thumbnailCache`、`computeFingerprint`、網路檢查、`downloadQueueController`、`WifiTransferDependencies` 的欄位；WiFi 傳書開關由 null 檢查改為明確表示）／`AppearanceDependencies`（主題、E-Ink、介面語言 `currentLocaleOverride`／`onLocaleChanged`）／`AppDependencies` 與 `main.dart` 收尾，移除 epic-26 Issue 7 的 6 個舊 bundle（含 `LibraryLocaleDependencies`）與 `buildReaderScreen` 的暫時組裝；依賴 Issue 12 | Strong | ⚪ 待規劃 |
| 14 | 守衛測試：擴充 `elinkbook_app_wiring_test.dart`，以身分比對驗證同一實例從容器傳到每個開書路徑（含 `syncCheckpointTrigger` 在 `ReaderFeatureDependencies` 與 `SyncDependencies` 為同一實例）；ADR 0037 的最終驗收條件；依賴 Issue 13 | Strong | ⚪ 待規劃 |

Issue 2～6 只列標題，動手前須各自 `/grill-with-docs` 設計；候選來源與證據見 2026-09-30 架構檢視報告。

待清理（Issue 11 程式審查 M-5）：`readerSaveAsPresetUnavailableMessage` ARB 鍵（四份 ARB 與產生檔）已無使用端（`reader_screen.dart` 唯一使用處隨 `layoutPresetRepository == null` 分支一併移除）；Issue 13 移除舊 bundle 時順手清理，或另立微工單，避免遺忘。

Issue 11～14 來源：2026-10-05 架構檢視候選 2，設計決策見 `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`；動手前仍須各自確認並寫 plan。
