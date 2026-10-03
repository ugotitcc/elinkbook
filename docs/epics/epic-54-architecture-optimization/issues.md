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
| 9 | （缺陷，待確認）帶跳轉目標開書時，Foliate 重排產生的「同位置重複回報」讓跳轉保護提早失效，離開時可能把跳轉落點存成新進度；由 Issue 7 程式審查 Minor 3 發現，Issue 7 為零行為變化故未修 | — | 🟡 實作完成，待程式審查與發 PR |

Issue 2～6 只列標題，動手前須各自 `/grill-with-docs` 設計；候選來源與證據見 2026-09-30 架構檢視報告。
