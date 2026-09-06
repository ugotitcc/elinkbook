# `epic-36-adaptive-shelf-navigation` 三目的地導覽／書架下鑽強化／設定四分區

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-36-adaptive-shelf-navigation/`
**關聯 PRD 章節：** 無新增 FR，屬於 `DESIGN.md` §11／§15／§17 規範落地（依 `uiux-audit.dc.html` 第 5～8 節重構規劃）
**依循規則：** `UI_DESIGN_RULES.md`；`ElinkTokens`（`epic-35-design-system-tokens`）先合併穩定才動手寫程式碼
**依賴：** `epic-35-design-system-tokens` 需先歸檔（`ElinkTokens` 已合併、色值正確），本 Epic 才進入 TDD 實作階段——本 Epic 的 Discovery／Architecting／Issue 拆分可以提前進行，不受阻擋。

## 開發記錄

2026-09-02 由 `/grill-with-docs` 規劃。承接同一輪 UI 重構的 `docs/research/uiux/eink-redesign-rebuild-plan.md`（階段 A 原型驗證、階段 B `DESIGN.md` 更新，含 1 個 Critical＋6 個 Important＋4 個 Minor 審查修正）與本 Epic 自己額外一輪 Discovery grilling（Q1～Q5：Epic 拆分為 `epic-35`＋本 Epic 兩個、本 Epic 代號確認、`epic-35` 範圍含 8 個檔案的寫死顏色清理、本 Epic 現在就可以先規劃、`UI_DESIGN_RULES.md` 核對無衝突）。查現有程式碼確認：書架長按進多選（`_selectedBookIds`／`onLongPress`，`library_screen.dart`）已存在且與這次「長按維持多選、⋮ 才開單書選單」規格相容，不用重做；`main.dart` 目前直接把 `LibraryScreen` 當 `home`，完全沒有 `NavigationBar`／`NavigationRail`／`AdaptiveScaffold`，畫面間靠各自 AppBar 按鈕與 `Navigator.push` 跳轉——三目的地導覽架構是本 Epic 真正要從無到有蓋的部分。Discovery 見 `design.md`。下一步：Architecting（`spec.md`），待 `epic-35` 歸檔後再進 Scrum Master 階段拆 `issues.md`、開始 TDD 實作。

2026-09-07 Issue 1-5 全數完成合併後，透過 `/improve-codebase-architecture` 對 Epic 35／36 進行架構回顧：實際走讀程式碼（非只讀 spec）發現 `library_screen.dart`（1686 行）的書架分頁狀態（`_currentPage`／`_lastPageSize`）有 7 個各自獨立的寫入點散落全檔，locality 差；`review-plan-issue-3.md` M-2 點名過的越界殘留風險已被 `build()` 內一行同步寫回巧合修掉，但沒有測試鎖住。經 `/grilling` 十輪問答（Q1～Q10）確認深化設計：新增純 Dart 類別 `LibraryPagingCursor`（不做成 `ChangeNotifier`——只有 `_LibraryScreenState` 一個消費者）收斂全部 7 個寫入點，`WidgetsBindingObserver`／`didChangeMetrics()` 機制維持不動（存廢是獨立問題，本次不處理）。已寫入 `issues.md` Issue 6，`Status: ready-for-agent`。同一輪回顧另外三個候選——`library_screen.dart` 拆散孤兒彈窗（`_BookDetailsDialog`／`_LayoutOverrideDialog`）、`AdaptiveShellScaffold` 轉送殼收斂、`GlobalReaderPrefs` 13 欄位拆分——使用者尚未選擇是否要立案，暫不建立工單。
