# Epic 31 Issue 1 程式碼審查報告 (Code Review Report)

**審查對象：** 分支 `epic-31-issue-1`（`db235aa`）相對於 `main` 分岔點 `5364d156acd87f5e660f77ae81b8b8bdf13ba14a` 的實際程式變更
**關聯工單：** [`docs/epics/epic-31-touch-intent-unification/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-31-touch-intent-unification/issues.md) 之 **Issue 1：Puppeteer 回歸測試套件正式化＋跨機制干擾測試**
**關聯計畫：** [`docs/epics/epic-31-touch-intent-unification/plans/plan-issue-1.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-31-touch-intent-unification/plans/plan-issue-1.md)
**關聯設計：** [`docs/epics/epic-31-touch-intent-unification/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-31-touch-intent-unification/design.md)
**審查日期：** 2026-08-25
**審查性質：** 已完成程式變更審查（Code Review），非計畫文件審查

---

## 審查方法

- 以 `git diff --stat` / `git diff` / `git log` 逐檔比對 `5364d156`..`db235aa` 的完整變更（12 個檔案、+967/-35 行）。
- 逐一比對計畫（`plan-issue-1.md`）Task 1~6 內列出的完整程式碼期望與實際落地內容。
- 讀取 `app/android/app/src/main/assets/foliate/main.js`（`ANNOTATION_CLICK_TAP_MAX_MS`／`SELECTION_RELEASE_GUARD_MS`／`mousedown`／`click`／`reportSelection`）與 `view.js`（`show-annotation` 事件）相關程式碼，交叉核對測試斷言是否對應真實行為。
- 用 `git worktree add`（唯讀，未動到原本 checkout 的 HEAD／index，審查後已還原乾淨、無殘留 worktree 註冊項目）在獨立暫存目錄實際執行：
  - `npm install`：成功安裝，產生的 `package-lock.json` 與版控內容一致。
  - `node smoke-test.mjs`：4 項 `[PASS]`，exit code 0。
  - `node run-all.mjs`：連續執行多次，**大多數為全數 PASS，但重現到至少 1 次整體 FAIL**（細節見 Critical/Important）。

---

### Strengths

1. **Global Constraints 全數遵守**：`git diff --stat` 確認變更僅限 `app/tool/foliate_touch_harness/` 與兩份 Epic 31 文件（`issues.md`／`plan-issue-1.md`），未觸碰 `main.js`、任何 vendored 檔案（`paginator.js`/`view.js`/`epub.js`/`overlayer.js`/`fixed-layout.js`）或 `app/lib` 任一 Dart 檔案。正式路徑正確為 `app/tool/foliate_touch_harness/`，符合「不是 `app/test/`」的要求。fixture 一律使用 `app/test/fixtures/` 下既有檔案（`sample.epub`／`sample_horizontal.epub`／`sample_long_chinese_vertical.epub`），未新增任何 fixture。Puppeteer 版本鎖定 `^25.6.0`，與 `docs/epics/epic-25-annotation-interaction-qa/epic-18-issue-47-harness/package.json` 既有慣例一致。
2. **`lib/harness.mjs`／`smoke-test.mjs`／Task 3～6 的三支 scenario 腳本（`scenario-issue10-*`／`scenario-issue11-*`／`scenario-cross-mechanism-*`）與 `run-all.mjs`／`README.md` 逐字對照計畫，函式簽章、斷言邏輯、字串文案幾乎完全一致**（僅單引號→雙引號的 lint 風格差異，屬合理實作細節，不影響行為）。這代表計畫本身在這幾支腳本上被證實是可直接落地的高品質規格。
3. **對計畫錯誤的正確修正，而非盲目照抄**：計畫 Task 2（`scenario-epic25-issue4-fast-tap.mjs`）原本假設 main.js 會呼叫一個 `onAnnotationActivated` bridge event，但實際讀 `main.js` 全文（`grep -n "callHandler("`）確認**這個 bridge call 從未存在**過——現行 main.js 只有 `onTableOfContentsReady`／`onPageRendered`／`onSelectionCleared`／`onSelectionChanged`／`onError` 五個 callHandler 呼叫。實作者在執行 Step 1/2 時顯然發現這個落差，正確地改用 `view.js:448`／`:482` 真實會 dispatch 的 `show-annotation` DOM 自訂事件（在 `#createOverlayer` 的 click 監聽器未被 `main.js` 的 `stopImmediatePropagation()` 攔截時才會發出），這是比計畫假設更貼近真實機制的訊號來源。且此修正**同步回寫進 `plan-issue-1.md` 本身**（diff 可見 Task 2 程式碼區塊也被更新為與實作一致），保留了決策軌跡，是值得肯定的透明作法。
4. **`issues.md` 的 Issue 1 狀態更新誠實、具體**：不是空泛的「已完成」，而是具體列出「4 個場景全數 PASS」「Issue 47／長按候選跨機制情境不在自動化範圍內，交給 Issue 2 真機重測」，與計畫 Task 6 Step 5 的要求、以及 `design.md`「已知風險」段落的措辭一致，沒有誇大完成度。
5. **README 的「已知範圍限制」段落清楚、誠實**：明確點名只涵蓋 `touchStart`/`touchEnd`、排除 Issue 47／長按候選期間選取確立兩個場景並說明原因與後續把關方式，未淡化或隱藏限制。
6. **實測驗證函式庫本身可用**：`smoke-test.mjs` 實際執行 4 項全數 `[PASS]`，`npm install` 產生的 `package-lock.json` 為標準 npm lockfile v3 格式，沒有夾帶異常內容。

---

### Issues

#### Critical (Must Fix)

無。

#### Important (Should Fix)

1. **`scenario-cross-mechanism-tap-boundary.mjs` 情境 A 存在可重現的計時競態（flaky test），與計畫「全數必須 PASS」的驗收標準有落差。**
   - 檔案：`app/tool/foliate_touch_harness/scenario-cross-mechanism-tap-boundary.mjs:26-34`
   - 實測：在獨立 worktree 中連續執行 `node run-all.mjs` 約 8 次，重現到至少 2 次整體 `FAIL`，失敗點固定在同一斷言：
     ```
     [FAIL] 選取收尾保護期內快速點擊別處，選取維持存在 — before.isCollapsed=false, after.isCollapsed=true
     ```
     單獨執行同一支腳本（`node scenario-cross-mechanism-tap-boundary.mjs`）數次則穩定 PASS，代表這不是邏輯錯誤，而是**系統負載/時序抖動導致的競態**：情境 A 的設計是「選取剛確立 → 立刻 `cdpTap`（80ms 按壓）→ 等 100ms → 檢查選取狀態」，而 main.js 的 `SELECTION_RELEASE_GUARD_MS=150ms` 保護窗口是從「選取被判定為非折疊的時間點」起算——測試腳本本身的操作（`injectSelectionAtVisibleText` 的 `page.evaluate` 往返、CDP 事件排隊、Chromium 主執行緒忙碌）與 150ms 門檻之間**沒有安全邊際**，一旦系統當下稍慢（例如同機同時跑其他 3 支腳本累積的 GC/JIT 壓力），`mousedown` 的實際 `timeStamp` 就可能已經超出保護窗口，導致選取被正常折疊、測試斷言落空。
   - 為什麼重要：這支測試套件的**核心價值是作為 Issue 2 重構前的可信賴基準線**（「作為 Issue 2 的重構前基準線」「重寫後才能拿它驗證有沒有回歸」）。若 `run-all.mjs` 本身有非 0 的機率整體回報 FAIL，Issue 2 重構完成後跑這套測試若剛好又踩到這個競態，會誤判為「重構引入回歸」，浪費排查時間；反之若重構真的引入了這個機制的回歸，這個既有的計時脆弱性也會讓人更難分辨「是真回歸還是測試本身抖動」。
   - 怎麼修（建議，不強制）：情境 A 拉開安全邊際（例如把注入選取到 `cdpTap` 之間的等待時間去掉的同時、把賽跑窗口從「~150ms 門檻打 80~180ms 的操作」改成用更寬鬆的門檻值驗證，或在斷言前加入重試/輪詢邏輯而非固定 `setTimeout`），或至少在 README／腳本註解記錄「此情境對系統負載敏感，CI 環境下若單次 FAIL 建議重跑」，讓後續維護者（尤其是 Issue 2 執行者）知道這不是新引入的邏輯錯誤。

#### Minor (Nice to Have)

1. **`lib/harness.mjs:182` 用 `page._client()` 取得 CDP session，屬 Puppeteer 私有 API。** 計畫審查報告（`review-plan-issue-1.md` 第 4 節）已提過這點、註明「不阻礙計畫執行」，實作沿用了計畫原文，屬合理選擇，僅在此重申：日後升級 Puppeteer 版本時，若 `_client()` 私有介面被移除，`await page.createCDPSession()` 是官方公開替代方案，風險與影響面很小，不影響本次驗收。
2. **程式風格：`harness.mjs`／`README.md`／其餘 scenario 腳本用單引號，`smoke-test.mjs` 用雙引號**（例如 `smoke-test.mjs:8` 的 `"./lib/harness.mjs"` vs. 其餘檔案的 `'./lib/harness.mjs'`）。純風格不一致，不影響功能，且該目錄未設定 ESLint/Prettier，無強制規範，故列為 Minor。

---

### Recommendations

1. 建議在 Issue 2 執行「4 個情境全數維持 PASS」的驗收步驟時，`run-all.mjs` 若出現非預期 FAIL，先重跑 1～2 次排除上述已知計時競態，再判斷是否為重構回歸，避免誤判。
2. 若日後要把這套 harness 接進 CI（目前設計本身未要求，屬本 Epic 範圍外），建議先處理上述 Important 項目的競態問題，否則 CI 會出現偶發紅燈、侵蝕團隊對這條安全網的信任。
3. 計畫文件本身在 Task 2 出現的 `onAnnotationActivated` 假設落空一事，建議之後排 Epic/Issue 規劃時，若涉及 bridge callback 名稱等可直接用 `grep` 核對的具體介面契約，規劃前先做一次程式碼交叉核對，可以減少像本次這樣需要在執行階段臨時修正計畫的情況（本次修正結果是好的，但屬事後補救，非事前預防）。

---

### Assessment

**Ready to merge?** With fixes（建議：可先合併，但需在 Issue 2 開工前把上述 Important 項目的競態風險告知執行者，或視團隊風險胃納決定是否先行加固）

**Reasoning:** 6 個 Task 的實作內容、函式簽章、fixture 使用、路徑選擇、文件與工單狀態更新皆與計畫高度一致，且對計畫本身一處錯誤假設（`onAnnotationActivated` 不存在）做出了正確且透明的修正；唯一實測發現的問題是 `scenario-cross-mechanism-tap-boundary.mjs` 情境 A 在系統負載下有可重現的計時競態，會讓「全數 PASS」的驗收標準偶發不成立，屬測試基礎設施的穩健性缺口而非邏輯錯誤或架構問題，不阻擋合併，但應在作為 Issue 2 重構安全網使用前讓執行者知悉、避免誤判回歸。
