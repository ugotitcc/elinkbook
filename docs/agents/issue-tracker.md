# Issue tracker（工單追蹤系統）：本機 Markdown（SDD Epic 沙盒）

本儲存庫的工單與規格以 markdown 檔案形式存放於 `docs/epics/<epic-name>/` 底下，遵循專案的 Spec-Driven Development（SDD）工作流程。Gitea（`git.jigong.org/huthief/elinkBook`）仍作為程式碼的 git remote，但不做為工單追蹤系統使用。

## 慣例

- `docs/epics.md` 是**全域狀態看板**：每個 Epic 佔一列（代號/名稱、狀態 ⚪未開始/🟡開發中/🟢已歸檔、目前存放路徑、關聯的 PRD 章節、備註）。在啟動一個 Epic 的 Discovery 階段前，須先在此登錄該 Epic（狀態設為 `Active`，填入路徑）；歸檔時更新狀態/路徑為 `Archived`。這是唯一能查到「我要找的 Epic 在哪裡、目前存放於何處」的地方。
- 每個 Epic 一個目錄：`docs/epics/<epic-name>/`
- Discovery 階段產出：`docs/epics/<epic-name>/design.md`
- Architecting 階段產出（核心介面/型別，該 Epic 的唯一事實來源）：`docs/epics/<epic-name>/spec.md`
- 實作工單（細粒度垂直切片），每個工單皆須包含所需的單元測試要求：`docs/epics/<epic-name>/issues.md`
- 各工單的實作計畫：`docs/epics/<epic-name>/plans/plan-issue-<N>.md`
- 各工單的審查紀錄：`docs/epics/<epic-name>/reviews/review-issue-<N>.md`
- Bug 修復重現報告（跳過 design/spec 階段）：`docs/epics/<epic-name>/reviews/bugfix-repro.md`
- 分流狀態記錄於每筆工單條目上方的 `Status:` 那一行——角色字串請見 `docs/agents/triage-labels.md`
- 當某個 Epic 的程式碼已完全合併且穩定後，將整個 `docs/epics/<epic-name>/` 目錄搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`

## 當某個 skill 說「發布到工單追蹤系統」時

在 `docs/epics/<epic-name>/issues.md` 新增一筆條目，若該 Epic 的目錄/檔案尚不存在則先建立。

## 當某個 skill 說「取得相關工單」時

讀取 `docs/epics/<epic-name>/issues.md` 中的相關條目，以及其對應的 `plans/plan-issue-<N>.md` 與 `reviews/review-issue-<N>.md`（若存在）。
