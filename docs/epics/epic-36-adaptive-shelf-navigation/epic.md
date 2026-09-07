# `epic-36-adaptive-shelf-navigation` 三目的地導覽／書架下鑽強化／設定四分區

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-36-adaptive-shelf-navigation/`
**關聯 PRD 章節：** 無新增 FR，屬於 `DESIGN.md` §11／§15／§17 規範落地（依 `uiux-audit.dc.html` 第 5～8 節重構規劃）
**依循規則：** `UI_DESIGN_RULES.md`；`ElinkTokens`（`epic-35-design-system-tokens`）先合併穩定才動手寫程式碼
**依賴：** `epic-35-design-system-tokens` 需先歸檔（`ElinkTokens` 已合併、色值正確），本 Epic 才進入 TDD 實作階段——本 Epic 的 Discovery／Architecting／Issue 拆分可以提前進行，不受阻擋。

## 開發記錄

2026-09-02 由 `/grill-with-docs` 規劃。承接同一輪 UI 重構的 `docs/research/uiux/eink-redesign-rebuild-plan.md`（階段 A 原型驗證、階段 B `DESIGN.md` 更新，含 1 個 Critical＋6 個 Important＋4 個 Minor 審查修正）與本 Epic 自己額外一輪 Discovery grilling（Q1～Q5：Epic 拆分為 `epic-35`＋本 Epic 兩個、本 Epic 代號確認、`epic-35` 範圍含 8 個檔案的寫死顏色清理、本 Epic 現在就可以先規劃、`UI_DESIGN_RULES.md` 核對無衝突）。查現有程式碼確認：書架長按進多選（`_selectedBookIds`／`onLongPress`，`library_screen.dart`）已存在且與這次「長按維持多選、⋮ 才開單書選單」規格相容，不用重做；`main.dart` 目前直接把 `LibraryScreen` 當 `home`，完全沒有 `NavigationBar`／`NavigationRail`／`AdaptiveScaffold`，畫面間靠各自 AppBar 按鈕與 `Navigator.push` 跳轉——三目的地導覽架構是本 Epic 真正要從無到有蓋的部分。Discovery 見 `design.md`。下一步：Architecting（`spec.md`），待 `epic-35` 歸檔後再進 Scrum Master 階段拆 `issues.md`、開始 TDD 實作。

2026-09-07 Issue 1-5 全數完成合併後，透過 `/improve-codebase-architecture` 對 Epic 35／36 進行架構回顧：實際走讀程式碼（非只讀 spec）發現 `library_screen.dart`（1686 行）的書架分頁狀態（`_currentPage`／`_lastPageSize`）有 7 個各自獨立的寫入點散落全檔，locality 差；`review-plan-issue-3.md` M-2 點名過的越界殘留風險已被 `build()` 內一行同步寫回巧合修掉，但沒有測試鎖住。經 `/grilling` 十輪問答（Q1～Q10）確認深化設計：新增純 Dart 類別 `LibraryPagingCursor`（不做成 `ChangeNotifier`——只有 `_LibraryScreenState` 一個消費者）收斂全部 7 個寫入點，`WidgetsBindingObserver`／`didChangeMetrics()` 機制維持不動（存廢是獨立問題，本次不處理）。已寫入 `issues.md` Issue 6，`Status: ready-for-agent`。同一輪回顧另外三個候選——`library_screen.dart` 拆散孤兒彈窗（`_BookDetailsDialog`／`_LayoutOverrideDialog`）、`AdaptiveShellScaffold` 轉送殼收斂、`GlobalReaderPrefs` 13 欄位拆分——使用者尚未選擇是否要立案，暫不建立工單。

2026-09-07 由 `/superpowers:subagent-driven-development` 執行 Issue 6：Task 1 新增 `LibraryPagingCursor` 純 Dart 類別並以 10 則單元測試鎖死冷啟動、空書庫與 M-2 越界殘留迴歸測試；Task 2 將 `library_screen.dart` 7 處寫入點徹底收斂至游標類別，移除舊有 `_currentPage` 與 `_lastPageSize` 欄位，並透過 `applyOrientationChange()` 布林回傳值落實 E-Ink 防抖保護。雙任務皆經規格合規審查（`spec-reviewer`）與程式碼品質審查（`code-reviewer`）Pass，全分支最終審查 `review-issue-6.md` 獲 0 Critical / 0 Important / 0 Minor，全套 116 則單元與 Widget 測試 100% 通過。合併前另由 `/superpowers:requesting-code-review` 派獨立 subagent 複審（`review-issue-6-recheck.md`）：重新實測 `flutter analyze`／局部測試皆與既有報告一致，並補做既有報告從未執行過的完整 `flutter test`（2013 通過、15 失敗，15 個失敗全數為 `epic-37-test-suite-flakiness` 已追蹤在案的 `remote_catalog_screen_test.dart` 既有噪音，與本次變更無關），確認無新回歸；同時記錄一項流程層級 Important 發現——既有 `review-issue-6.md` 在計劃書明文要求完整套件驗證的步驟上未落實卻仍下「生產就緒」結論，已作為未來審查的提醒（不影響本次合併判斷）。順手修正 `issues.md` Issue 6 內嵌的過期程式碼片段（`review-issue-6-recheck.md` Minor 發現）。PR #219 已於 2026-09-07 合併進 `main`，Issue 6 正式完成，Epic 36 全數 6 個 Issue 完成，待人類決定歸檔時機。

2026-09-07 另一輪獨立的 `/grill-with-docs` Discovery（依 `docs/research/uiux/elinkBook-eink-redesign.dc.html` 與 `prototype/eink_redesign_prototype.html`，起因是真機試用回饋書架每頁只顯示 3 項/1 行、畫面留白換頁太頻繁）：原始需求描述是「放棄換頁改回捲動」，grilling 過程中使用者自行修正為「維持 `PagingBar` 架構，只把每頁列數從寫死 1 行改成動態計算」——不是架構反轉，是規格微調，不需要 ADR。已寫入 `issues.md` Issue 7（`ready-for-agent`），核心變更是 `LibraryPagingCursor.clamp()`／`applyOrientationChange()` 兩方法因為 pageSize 計算基礎從「方向」變成「量測高度」而合併回一個方法，新增純函式 `libraryRowsForHeight()`。同一輪 Discovery 另外還處理了閱讀器 Chrome/TTS 重構（見新 `epic-38-reader-chrome-tts-redesign`），兩者範圍不同已拆開追蹤，不寫在同一個 Epic。

