---
name: sdd-workflow
description: 本儲存庫的 Spec-Driven Development（規格驅動開發）Epic/Issue 生命週期——目錄結構、docs/epics.md 全域看板、Discovery 到歸檔的七步驟流程。做 Epic 規劃、拆 Issue、寫 plan-issue、或需要知道某份文件該放哪裡時載入。
---

# SDD 工作流程

本檔案是 `CLAUDE.md`「Spec-Driven Development (SDD) 工作流程」小節的完整版——該處只保留角色分工與「審查先出報告、嚴禁直接修改」這條安全性規則常駐；目錄結構、`docs/epics.md` 圖例、七步驟生命週期移到這裡，只在實際做 Epic/Issue 規劃工作時載入。

## 目錄結構

```
docs/
├── adr/                    # 全域：架構決定紀錄
├── epics/                  # 進行中的 Epic 沙盒（design.md、spec.md、issues.md、plans/、reviews/）
├── archive/                # 已完成的 Epic，搬移至 <YYYY-MM-DD>-<簡稱>/
├── prd.md                  # 全域：產品需求
├── CONTEXT.md              # 全域：通用語言詞彙表（domain-modeling skill 維護）
└── epics.md                # 全域：Epic 狀態看板 —— 見下方說明
```

新建立一個 Epic 時，須將該 Epic 的 `docs/epics/<epic-name>/reviews/` 加入根目錄 `.gitignore`（例如 `docs/epics/epic-2-vertical-core/reviews/`）——審查報告不進版控，僅作為審查當下交付給人類/原作者的暫時性產物。歸檔該 Epic 時，連同該行一併從 `.gitignore` 移除。

## `docs/epics.md` —— 全域狀態看板

每個 Epic 佔一列：順位、代號/名稱、狀態、備註。**備註欄位只寫精簡摘要**——已歸檔一律寫「已完成，已歸檔」；開發中寫「最後處理的 Issue 編號」（例如「Issue 3 已完成」）或「全數完成，待歸檔」；未開始（Backlog）沿用原本就很短的一句話說明。**嚴禁把完整開發歷程（Discovery 決策細節、逐 Issue 完成記錄、審查修訂摘要）寫進這個檔案的備註欄位**——那是 `epic.md` 的責任（見下）。這個看板曾經因為每個 Epic 的備註欄位不斷累加完整歷程文字，膨脹到十萬字級、變得完全無法閱讀，2026-08-26 已重構為精簡摘要表＋各 Epic 自己的 `epic.md`，往後新增/更新條目時務必維持這個分工，不要走回頭路。

- ⚪ **未開始 (Backlog)**——已規劃但尚未啟動，尚無目錄，備註直接寫在 `docs/epics.md` 本身（沒有目錄可以放 `epic.md`）
- 🟡 **開發中 (Active)**——設計/規格/程式撰寫進行中，存放於 `docs/epics/<epic-name>/`，完整歷程記錄於 `docs/epics/<epic-name>/epic.md`
- 🟢 **已歸檔 (Archived)**——已合併且穩定，已搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`，完整歷程記錄於 `docs/archive/<YYYY-MM-DD>-<簡稱>/epic.md`

在啟動一個 Epic 的 Discovery 階段*之前*，須先在此登錄該 Epic（狀態設為 `Active`，填入路徑），並同時建立該 Epic 目錄下的 `epic.md`（背景、目標等 Discovery 產出的長篇說明寫在這裡，不要寫進 `docs/epics.md`）。歸檔時將狀態更新為 `Archived`、`epic.md` 隨整個目錄搬移至 `docs/archive/`，`docs/epics.md` 的備註同步收斂為「已完成，已歸檔」。這份檔案是唯一能查到「我要找的 Epic 在哪裡、目前狀態如何」的地方；要查某個 Epic 完整的來龍去脈，去讀它自己目錄下的 `epic.md`。

## 生命週期

1. **任務分類**（人類）：新功能/重構 → 建立新 Epic；Bug 修復 → 找到受影響的 Epic，於其 `reviews/` 目錄下處理。
2. **Discovery**（Claude Code，扮演 PM/Analyst）—— `/brainstorming` + `/grill-with-docs` → `docs/epics/<epic-name>/design.md`。Bug 修復則改用 `/diagnose` → `docs/epics/<epic-name>/reviews/bugfix-repro.md`。
3. **Architecting**（Claude Code，扮演 Architect）—— 若架構有異動則撰寫 ADR，並在 `docs/epics/<epic-name>/spec.md` 中定義核心介面/型別（自此成為該 Epic 的唯一事實來源）。
4. **Scrum Master 階段**（Claude Code）—— 將 Epic 拆解為細粒度的垂直切片工單，寫入 `docs/epics/<epic-name>/issues.md`，每個工單皆須附上所需的單元測試要求。
5. **規劃與審查**（實作者為作者、Claude Code 為審查者）—— 實作者認領工單，撰寫 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，在開始寫程式碼前發起審查（`requesting-code-review`/`receiving-code-review`）；審查者先產出報告，不得直接修改該計劃。
6. **TDD 實作與 QA**（實作者為作者、Claude Code 為審查者）—— 紅-綠-重構循環；每完成一個 Task 的 Step，須將 `plans/plan-issue-<N>.md` 中該 Step 前面的 `- [ ]` 改為 `- [x]`，讓計劃檔案隨開發進度即時反映完成狀態，方便後續確認/複查追蹤；接著進行程式碼審查；審查者先產出報告，不得直接修改程式碼；結果歸檔至 `docs/epics/<epic-name>/reviews/review-issue-<N>.md`；交由人類進行合併。
7. **歸檔**（人類指定）—— 將整個 Epic 目錄搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`，並將其在 `docs/epics.md` 的該列狀態更新為 `Archived`、填入新路徑。
