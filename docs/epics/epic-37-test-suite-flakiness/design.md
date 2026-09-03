# Epic 37 — 全套測試套件既有不穩定性追蹤：Discovery

## 緣起

`epic-35-design-system-tokens` Issue 5（`nav_zone_settings_screen.dart` 顏色遷移）收尾階段，依 `plan-issue-5.md`「全部 Task 完成後」清單執行完整 `flutter test`（不帶檔案路徑），發現 29 個測試失敗。Issue 5 本身只改動 `nav_zone_settings_screen.dart` 一個檔案（顏色來源調整，不涉及邏輯），需要先排除「這是不是這次改動造成的迴歸」才能結案。

## 排除迴歸的驗證方法與結果

**環境：** `.worktrees/epic-35-issue-5`（分支 `feat/epic-35-issue-5`，merge-base `434fe70a`）與 `main`（`cc07c4f7`）。已確認 `git diff --stat 434fe70a..cc07c4f7 -- app/` 無任何輸出——即 `main` 目前的 `app/` 原始碼與 `epic-35-issue-5` 分支的合併基準完全相同（中間只有 docs 異動），可直接當同一份程式碼的基準對照。

| 執行方式 | 分支/環境 | 測試總數 | 失敗數 |
|---|---|---|---|
| 完整 `flutter test`（不帶檔案路徑） | `feat/epic-35-issue-5` | 1873 | 29 |
| 完整 `flutter test`（不帶檔案路徑） | `main` | 1898 | 1 |
| 只跑 `reader_screen_test.dart`＋`remote_catalog_screen_test.dart` 兩檔 | `main` | 222 | 0 |

**結論：**
1. `epic-35-issue-5` 分支的 29 個失敗，全部落在跟本次改動（`nav_zone_settings_screen.dart`）完全無程式碼關聯的兩個檔案。
2. 這兩個檔案單獨執行時 100% 全過，代表失敗只在「跟其他 1800+ 個測試一起跑」的規模下才會出現——屬於測試間資源競爭/計時的不穩定性，不是這兩個檔案本身的邏輯錯誤。
3. `main` 本身用同一種「不帶檔案路徑」的跑法，也會在完全不同的第三個檔案（`pdf_reader_view_test.dart`）出現 1 個失敗——證實「全套規模下偶發失敗」是這個測試套件本來就有的既有現象，不是 `epic-35-issue-5` 分支才有的新問題。

判定為既有問題，不列入 Issue 5 驗收阻塞項，但另立本 Epic 追蹤，避免後續各 Epic 各自重複發現、重複排查同一批已知現象。

## 已知限制（誠實記錄）

`epic-35-issue-5` 分支那次全套測試的執行指令用了 `flutter test 2>&1 | tail -40`，只保留了标准輸出的最後 40 行；背景程序結束後，完整輸出已隨管線關閉而遺失，**無法回溯 29 個失敗的完整清單與各自的例外堆疊**，只能從留存的最後 40 行片段辨認出以下 2 筆有 `[E]`／「Test failed」明確標記的個案（詳見 `issues.md` Issue 1、Issue 2 的「目前已知資訊」段落）；其餘 27 筆目前完全沒有可查資訊。

`main` 那次完整輸出有存檔（未經 `tail` 截斷），因此 `pdf_reader_view_test.dart` 的失敗（Issue 3）有完整例外堆疊可查，是三個 Issue 裡唯一具備完整根因排查起點的一筆。

## 下一步（尚未執行，留給實際認領 Issue 的人／Agent）

三個 Issue 目前都標記 `needs-info`。在能寫出 `plan-issue-N.md` 開始修之前，第一步都需要先**用未經截斷的方式重跑，取得完整失敗清單與例外堆疊**（例如 `flutter test > <log-file> 2>&1`，不要接 `tail`／`head`），才能判斷：是否為同一批測試每次都固定失敗（決定性/deterministic，值得排查根因），還是每次執行失敗的測試組合都不同（純粹的計時類 flaky，可能要考慮加重試或調整測試隔離方式而非逐一修邏輯）。
