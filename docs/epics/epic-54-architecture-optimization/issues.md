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
| 11 | 閱讀器功能依賴組 `ReaderFeatureDependencies`：`ReaderScreen`（17 個依賴參數收斂為 1 個）與 `BookSearchScreen`，消除 `reader_screen.dart` 手動逐欄重建；先建 `test/support/` 測試工廠；先做，完成後確認設計成立再往下；依 ADR 0037 | Strong | ⚪ 待規劃 |
| 12 | `SyncDependencies`：`LibraryScreen`、搜尋畫面、`SettingsScaffold`、`AdaptiveShellScaffold` 改收依賴組；依賴 Issue 11 | Strong | ⚪ 待規劃 |
| 13 | `SourceDependencies`／`AppearanceDependencies`／`AppDependencies` 與 `main.dart` 收尾，移除 epic-26 Issue 7 的舊 bundle；依賴 Issue 12 | Strong | ⚪ 待規劃 |
| 14 | 守衛測試：擴充 `elinkbook_app_wiring_test.dart`，以身分比對驗證同一實例從容器傳到每個開書路徑；依賴 Issue 13 | Worth exploring | ⚪ 待規劃 |

Issue 2～6 只列標題，動手前須各自 `/grill-with-docs` 設計；候選來源與證據見 2026-09-30 架構檢視報告。

Issue 11～14 來源：2026-10-05 架構檢視候選 2，設計決策見 `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`；動手前仍須各自確認並寫 plan。
