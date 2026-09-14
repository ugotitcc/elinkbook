# `epic-40-bundled-sqlite` 自帶編譯進 FTS5 的 SQLite

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-40-bundled-sqlite/`
**關聯 PRD 章節：** FR-04（全文檢索）、NFR-6（Android 11 最低支援版本，含部分 E-Ink 閱讀器）
**依循規則：** 承接 `epic-10-search` Issue 5／Issue 6 的真機驗證發現；改動集中在單一資料庫開啟點，不拆多張 Issue

## 開發記錄

2026-09-11 由人類提出：兩台實機測試皆顯示「本裝置不支援全文檢索」。連上其中一台已連結的實機（`3CEF42ECD491687`，`9491G`／`Hera_Vis_WIFI`，MediaTek 客製化 E-Ink ROM，Android 15）以 `adb shell pm clear` 清除 App 資料觸發 `onCreate` 重新建表，即時 `adb logcat` 實測捕捉到 `no such module: fts5`，確認 `epic-10-search` Issue 6 的優雅降級機制運作如預期，但根本問題（全文檢索在此類裝置上永久不可用）未解——與 Issue 6 當初發現問題的同一裝置型號，判斷這不是單一裝置個案。人類決議評估「App 自己攜帶保證含 FTS5 的 SQLite 動態函式庫」的架構級方案，另立新 Epic（不掛在 `epic-10-search` 下，理由見下方 grilling 記錄 Q1）。

2026-09-11 `/mattpocock-skills:grill-with-docs` 完成 Discovery，共 2 輪問答：

- **Q1（範圍框定）**：新獨立 Epic（比照 `epic-26-architecture-hardening`／`epic-31-touch-intent-unification` 先例），不掛在 `epic-10-search` 下——理由是這個決策的影響範圍在概念上超出「全文檢索」邊界（換掉全 App 唯一資料庫開啟點的底層引擎）。人類採納建議。
- **Q2（是否重新評估 ADR 0027 排除的 trigram tokenizer）**：人類初始傾向重新評估。查證 SQLite 官方文件（WebFetch `sqlite.org/fts5.html`）發現關鍵限制——trigram tokenizer 對少於 3 個 Unicode 字元的子字串查詢保證比對不到任何資料列，對照現行 `cjk_tokenizer.dart` 方案（單一中文字查詢也能正確比對，且已通過 800 萬列真實規模效能驗證），改用 trigram 對中文搜尋情境會是功能倒退。人類看到此查證結果後決議：**不改**，維持現行 tokenizer 方案，僅在 ADR 記錄「已重新評估、維持現狀」的理由。
- **Q3（既有裝置索引回補策略）**：人類採納建議（a）——不做自動背景回填，依賴 `epic-10-search` Issue 3 既有的「重建索引」按鈕，理由是自動觸發違反既有「背景索引與正在閱讀互斥」的使用者知情前提，且該按鈕本已是完整實作。
- **Q4（Issue 6 既有優雅降級機制去留）**：人類採納建議——保留不拔，作為零成本縱深防禦。
- **Q5（建置目標範圍）**：人類採納建議——只處理 Android 正式建置路徑，桌面測試環境與 iOS（`epic-13-ios` 尚未啟動）維持現狀不動。
- **Q6（Epic 命名與編號）**：人類採納建議——`epic-40-bundled-sqlite`（下一個可用編號），插入 `docs/epics.md` 於 `epic-10-search` 之後（順位 15），後續 26 個 Epic 順位欄位同步 +1。
- **Q7（ADR 處理方式）**：人類採納建議——新增獨立編號 ADR 0028 記錄本次決策，於 ADR 0027「曾考慮的替代方案」段落尾端加一句指標性註記指向 ADR 0028，不重寫 ADR 0027 本文。
- **Q8（Issue 拆分粒度）**：人類採納建議——整個 Epic 只開一張 Issue（範圍集中在 `SqliteLibraryRepository` 單一方法內的改動，不需要垂直切片；真機驗證是同一張 Issue 的收尾步驟，比照 `epic-10-search` Issue 6 Step 7 先例）。

Discovery 過程中順帶查證確認兩個關鍵事實（供 Architecting 直接引用，不需要重新查證）：(1) 全專案只有 `SqliteLibraryRepository.open()` 一個 `openDatabase()` 呼叫點，其餘 12+ 個 repository 皆依賴 `sqflite_common` 共用型別、不各自開連線，換引擎是集中在單一開啟點的改動；(2) `FullTextSearchSettingsRepository.rebuildIndex()`（`epic-10-search` Issue 3 既有功能）已是「清空索引→重新批次插入 pending→喚醒排程器」的完整實作，足以應付 Q3 的既有裝置回補需求，不需要新機制。Discovery 見 `design.md`。

2026-09-11 完成 Architecting：新增 [ADR 0028](../../adr/0028-bundled-sqlite3-for-fts5.md)（改用 `sqflite_common_ffi`+`sqlite3_flutter_libs` 取代系統版本；DB version 24→25 遷移需先查 `sqlite_master` 確認 `book_content_fts` 尚不存在才建表，因建表 SQL 無 `IF NOT EXISTS` 防護；既有裝置索引不自動回補；保留 Issue 6 降級機制；重新評估後維持排除 trigram tokenizer）與 `spec.md`（依賴變更、`main.dart` factory 初始化、遷移實作範例程式碼、測試要求）。ADR 0027「曾考慮的替代方案」段落尾端已加註指向 ADR 0028 的指標性註記。`docs/epics.md` 已登錄本 Epic（順位 15，`epic-10-search` 之後），`.gitignore` 已加入 `docs/epics/epic-40-bundled-sqlite/reviews/`。下一步：Scrum Master 拆 `issues.md`（已知只會是單一 Issue，見 Q8）。

2026-09-11 Scrum Master 完成 `issues.md`：依 Q8 定案只開一張 Issue 0，涵蓋依賴變更、`main.dart` factory 初始化、DB version 25 遷移（含存在性防護）、測試要求與真機重新驗證收尾步驟。下一步：認領本工單，撰寫 `plans/plan-issue-0.md` 並發起計畫審查。

2026-09-12 依 `reviews/review-design-spec-issues.md` 審查意見修訂 `design.md`／`spec.md`／`issues.md`／ADR 0028：(I-1) 查證專案實際遞移解析到 `sqlite3` 3.5.0，該版本起原生函式庫改由 Dart Native Assets 建置掛鉤自動提供含 FTS5 的 `libsqlite3.so`，剔除已 EOL 且為空殼的 `sqlite3_flutter_libs` 相依，改為僅將 `sqflite_common_ffi` 提升為正式 dependency，並補充建置期需要網路下載預編譯二進位的說明；(I-2) 補上真機整合測試（`app/integration_test/`）在 Android 上不經過 `lib/main.dart` 的事實，於 `flutter_test_config.dart` 的 `testExecutable` 內同步初始化 FFI factory；(M-1) 遷移測試補齊 AI/AD/AU 三個 trigger 皆須驗證同步，不只驗證 INSERT；(M-2) 真機驗收步驟補充 `adb install -r` 覆蓋安裝操作細節，避免誤觸解除安裝重裝清空資料庫。狀態轉為 `ready-for-agent`，可撰寫 `plans/plan-issue-0.md`。
