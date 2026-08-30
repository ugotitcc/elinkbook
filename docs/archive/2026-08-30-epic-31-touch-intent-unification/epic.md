# `epic-31-touch-intent-unification` 觸控意圖判讀統一

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-31-touch-intent-unification/`
**關聯 PRD 章節：** 無直接對應 FR（延伸互動模式章節之觸控/手勢穩定性，架構深化，非新增使用者可見功能）

## 開發記錄

2026-08-25 依 `docs/research/architecture-review-touch-gesture-handling.md`（`/improve-codebase-architecture` 流程）候選 1，經 `/grilling` 與 `/superpowers:brainstorming` Discovery 完成，`design.md` 已產出並經 `/superpowers:receiving-code-review` 修訂，`issues.md` 已拆解為 3 個工單，`plans/plan-issue-1.md` 已產出。Issue 1（Puppeteer 回歸測試套件正式化）已完成並合併（PR #185：`db235aa` 建立套件＋`64136de` 依 `reviews/review-code-issue-1.md` 修訂計時競態與程式風格），`app/tool/foliate_touch_harness/` 4 個情境全數 PASS，作為 Issue 2 重構前基準線。Issue 2（main.js 觸控意圖分類器重構）已完成並合併（PR #186：`7820c32d`／`c4560f70`／`2976d735`／`0413aed0` 依 `plans/plan-issue-2.md` 4 個 Task 完成 `TouchIntentClassifier` 收斂，`reviews/review-code-issue-2.md` 程式碼審查 Critical/Important 皆 0，`reviews/review-issue-2.md` 真機 5 項重測全數通過，判定 Ready to merge），main.js 5 個觸控機制收斂完成。Issue 3（TapZoneDetector 常數收斂＋PDF 門檻對齊）已完成並合併（PR #187：`43cd4ee5`／`0d2f76d4` 完成 `kTapZoneSlop`/`kTapZoneDebounceMs` 共用常數收斂與 PDF `tapMaxDurationMs` 對齊 700ms〔刻意決定、未經真機驗證，風險已記錄於程式碼註解〕，`flutter test` 1693/1693 全數 PASS；程式碼審查 `reviews/review-code-issue-3.md` Important #1 採納後已同步更新 `CLAUDE.md`「不可逆的技術決策」段落舊事實描述）。**Epic 31 規劃的 3 個工單全數完成**，待人類確認歸檔。
