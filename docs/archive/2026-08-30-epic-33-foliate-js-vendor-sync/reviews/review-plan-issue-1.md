# Epic 33 Issue 1：實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-33-foliate-js-vendor-sync/plans/plan-issue-1.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/plans/plan-issue-1.md)  
**對應工單：** `epic-33-foliate-js-vendor-sync` Issue 1  
**對照基準：**
1. 工單文件：[`docs/epics/epic-33-foliate-js-vendor-sync/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/issues.md)
2. 設計文件：[`docs/epics/epic-33-foliate-js-vendor-sync/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/design.md)
3. 同步 SOP：[`docs/research/foliate_js_sync_update_strategy.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/foliate_js_sync_update_strategy.md)
4. 架構決定：[ADR 0011](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0011-readium-vendoring-and-customization-boundary.md)（Vendoring 邊界）與 [ADR 0024](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md)（密度校正）
5. 專案程式碼：`app/android/app/src/main/assets/foliate/main.js`、`view.js`、`paginator.js`、`app/tool/foliate_touch_harness/`

**審查日期：** 2026-08-26（初審：05:35，複審核准：05:51）  
**審查性質：** 實作計畫可行性、執行期相依與指令正確性審查（Implementation Plan Spec Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，已解決所有 Critical/Important 問題，可直接推進至開發實作）**

修訂後的實作計畫已針對前次初審報告所列之 **2 項重大阻斷問題（Critical）** 與 **2 項重要架構問題（Important）** 進行了精準且徹底的重構與補強：

1. **執行期致命缺陷已根除**：將 ADR 0024 密度校正 patch 的移植正式納入 **Task 2**（包含 `paginator.js` 的 `detail.contentPages` 與 `view.js` 的 `#onRelocate` / `clearLocationDensity()`），並調整於觸控 Harness 之前執行。徹底解決了 Headless Chromium 於初次 `relocate` 時因 `view.clearLocationDensity` 缺失拋出 `TypeError` 導致 100% 逾時崩潰的致命風險。
2. **Git 目錄導航全面穩固化**：所有目錄返回指令皆重構為 `cd "$(git rev-parse --show-toplevel)"`，排除了相對路徑多跳一層導致 `fatal: not a git repository` 的問題。
3. **工單原子性與綠燈原則健全**：移除對不存在的「Issue 3」之引用，將 vendored 升級與本專案已採納 patch 的 Rebase 整併為單一完整交付單元，確保 Issue 1 完成時即可通過完整的自動化測試鏈（Green Build）。
4. **Task 2 Patch 驗證機制極為嚴謹**：引進 `node --check` 語法預檢指令，並在 Task 4 觸控 Harness 中加入明確的故障排除與回溯指引，可執行性與自癒性極佳。

---

## 2. 審查意見修訂對照表（Review Findings Resolution）

| 項目編號 | 初審問題摘要 | 嚴重度 | 修訂狀況與技術確認 | 複審結果 |
| :--- | :--- | :---: | :--- | :---: |
| **Critical 1** | Task 3 觸控 Harness 會因 `view.js` 缺失 `clearLocationDensity` 拋出 `TypeError` 導致 100% 逾時崩潰 | 🔴 Critical | 已新增 Task 2 於下載後立即補回 ADR 0024 patch；並將觸控 Harness 調整為 Task 4，確保真實 JS 執行環境下 `applyPreferences()` 正常運作。 | **✅ Resolved** |
| **Critical 2** | Task 1 Step 4 目錄層級跳轉 `cd ../../../../../../../..` 多跳一層導致 Git 報錯 | 🔴 Critical | Task 1 Step 4 已改用 `cd "$(git rev-parse --show-toplevel)"`。 | **✅ Resolved** |
| **Important 1** | ADR 0024 密度校正 patch 延後至不存在的 Issue 3，破壞綠燈原子性 | 🟡 Important | 已全面併入 Issue 1，並同步更新工單描述、計畫目標、架構說明與 Commit Message。 | **✅ Resolved** |
| **Important 2** | Task 1 Step 1 基準行數預期 | 🟡 Important | 計畫作者於 Self-Review 中記錄在 POSIX `wc -l`（以 `\n` 為準）下的實測數據（707 行），預期明確。 | **✅ Resolved** |
| **Minor 1** | 目錄導航指令脆弱性 | 🟢 Minor | Task 1 Step 4、Task 4 Step 3、Task 6 Step 3 均統一使用 `cd "$(git rev-parse --show-toplevel)"`。 | **✅ Resolved** |
| **Minor 2** | Commit Message 內容連動修訂 | 🟢 Minor | Task 6 Step 3 Commit Message 完整記錄 7 檔升級、ADR 0024 回補與四層防線驗收細節。 | **✅ Resolved** |

---

## 3. 關鍵模組深度審查

### (1) Task 2：ADR 0024 Patch 代碼結構與上下文精確度
* **`paginator.js` 插入點（Step 1–2）**：
  - 定位字串：`detail.size = textPages > 0 ? this.columnCount / textPages : 1`
  - 插入內容：`detail.contentPages = textPages`
  - 驗證方式：`grep` 檢驗 + `node --check app/android/app/src/main/assets/foliate/paginator.js`。
  - **審查結論**：上下文精準，變數 `textPages` 作用域正確，`node --check` 提供低成本且高效的語法防護。
* **`view.js` 插入點（Step 3–5）**：
  - 定位字串 1：`#onRelocate({ reason, range, index, fraction, size }) {` 擴充解構參數 `contentPages`，並在首行加入 `if (contentPages) this.#sectionProgress?.recordDensity(index, contentPages)`。
  - 定位字串 2：於 `getProgressOf(index, range) {` 前插入 `clearLocationDensity() { this.#sectionProgress?.clearDensity() }`。
  - 驗證方式：雙關鍵字 `grep` + `node --check app/android/app/src/main/assets/foliate/view.js`。
  - **審查結論**：方法簽章與 `main.js:175` 呼叫端完全吻合；方法體內委派給 `#sectionProgress` 的邏輯與 ADR 0024 規範完全一致。
* **邊界防護（Step 6）**：
  - 具備 `git status --porcelain -- .../progress.js` 防誤動檢查。

### (2) Task 4（觸控 Harness）與 Task 5（Bridge 對齊）的協同與執行性
* **Task 4 執行順序與容錯導引**：
  - 執行序位於 Task 1（下載）、Task 2（補 Patch）、Task 3（ES 相容性掃描）之後。
  - Step 2 特別增加排錯守則：「若在這一步撞到 `onPageRendered` 逾時或 `TypeError: view.clearLocationDensity is not a function`，代表 Task 2 的 patch 沒有補對... 回頭檢查 Task 2 Step 1–5 是否每一步都符合 Expected，不要在這裡繼續往下做。」——能有效防範 Agent 誤改 `main.js` 或 Harness 腳本。
* **Task 5 Bridge 簽章核對**：
  - 涵蓋 `next`/`prev`/`goTo` 核心導航 API、`relocate` 事件 payload 結構、`no-swipe` 與 `turn-gesture-left-inset` 屬性讀取、`clearLocationDensity` 呼叫端對齊。
  - 明確將 `scroll-direction` 與 `subpixelOffset` 列為非目標禁止調用項目。
  - 明確界定 `fd91451`（連續捲動）在靜態層級僅檢查 `onLocatorChanged` handler，真機體驗留至 Issue 2。

### (3) 架構邊界與決策一致性
* 針對初審建議 2（在 `main.js` 加上 `?.` 可選鏈防禦），計畫作者在 Self-Review 提出不採納之技術理由：「Task 2 已從根因修復缺席的方法，沒有必要再疊加防禦性語法，且修改 `main.js` 超出本工單『只在簽章不符時才動 main.js』的既定邊界」。
* **審查員認可此處置**：遵循最小變動原則與 ADR 0011/0024 邊界，職責劃分清晰。

---

## 4. 結論與下一步（Conclusion & Next Steps）

- [x] **實作計畫審查正式通過（Approved）**
- **後續步驟：**
  1. 請實作代理人（Implementer Agent）採用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans`，依序執行 Task 1 至 Task 6。
  2. 嚴格遵守各步驟之 Checkbox 打勾（`- [x]`）進度追蹤規範。
  3. 完成後依 Task 6 Step 4 更新 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` 之狀態與摘要。
