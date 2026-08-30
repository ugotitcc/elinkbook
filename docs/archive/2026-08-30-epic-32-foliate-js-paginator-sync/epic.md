# `epic-32-foliate-js-paginator-sync` foliate-js paginator.js 上游同步

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-32-foliate-js-paginator-sync/`
**關聯 PRD 章節：** 無直接對應 FR（vendored 引擎版本維護，架構/相依性維運，非新增使用者可見功能）

## 開發記錄

2026-08-25 於 `epic-31` Discovery 階段發現上游 `readest/foliate-js` 落後釘定版本 23 個 commit，其中 `paginator.js` 的 `#onTouchStart`/`#onTouchMove`/`#touchState` 已被上游重寫（commit `6c6a491`「改善分層翻頁反應性」+321/-53 行），直接影響 Epic 31 與既有 3 個歷史觸控修法（Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9）所依賴的底層行為。經 `/superpowers:brainstorming` Discovery 完成，`design.md` 已產出：範圍鎖定同步至 `6c6a491`（只換 `paginator.js` 一個檔案，已用 GitHub API 確認其餘 11 個釘定檔案未變動），依既有 SOP（`docs/research/foliate_js_sync_update_strategy.md`）執行，驗收標準明確納入上述 3 個歷史修法的真機重測。Issue 1（`3e82e23`）／Issue 2（`769aba7`）／Issue 3 皆已完成：`paginator.js` 已同步至 `6c6a491`，4 項真機重測全數通過（記錄於 `reviews/review-issue-3.md`），`docs/research/foliate_js_sync_update_strategy.md` Pinned Commit 已更新，`epic-31` 暫緩備註已移除、可繼續。待人類確認歸檔。
