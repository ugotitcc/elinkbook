# Epic 37 Issue 2 — `remote_catalog_screen_test.dart` 全套規模下偶發失敗 實作計劃

> **給實作者：** 必要子技能——使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐工單（Task）執行本計劃。步驟一律用 checkbox（`- [ ]`）語法追蹤。

**目標：** 取得 `remote_catalog_screen_test.dart` 在完整 `flutter test`（不帶檔案路徑）規模下的完整未截斷證據，判斷是「決定性失敗」「計時類不穩定」還是「未重現」三者之一，並把結論寫回 `issues.md`。

**架構：** 本 Issue 純屬診斷，不改動任何 `app/` 原始碼，方法與 Epic 37 Issue 1（`docs/epics/epic-37-test-suite-flakiness/plans/plan-issue-1.md`，已完成並合併）完全相同：先重跑單檔本身數次確認基準穩定，再重跑完整 `flutter test` 數次並把輸出完整存檔（不接 `tail`／`head`），從存檔中篩出歸屬本檔案的失敗，比對多次全套跑之間的失敗清單，最後把結論寫回 `issues.md`、更新分流狀態。**與 Issue 1 的關鍵差異：** Issue 1 執行後才發現「三次全套重跑都沒有任何失敗」是計劃原先二分支模板沒有預期到的第三種真實結果（「未重現」），本計劃從一開始就把這個結果納入 Task 4／Task 5 的範本，不需要臨時裁決。另外，Issue 2 的原始觀察本身就比 Issue 1 薄弱——`issues.md` 目前記錄的是「測試名稱在截斷的進度輸出中重複出現」，**不是**確認過的 `[E]` 失敗標記（`flutter test` 平行跑多檔案時，同一測試名稱重複出現在進度行不代表失敗，可能只是分片進度尚未推進），本計劃的 Task 4／Task 5 用字需要對此保持誠實，不可把「原始觀察」講得比實際更確定。

**Tech Stack：** Flutter/Dart 測試框架（`flutter test`，`package:test` compact reporter）；Bash 工具執行指令（Git Bash / POSIX sh，語法對齊 `issues.md` 既有「下一步」段落所寫的 `> <log> 2>&1` 格式）；Claude Code 內建 `Grep` 工具做 log 檔案分析。

**Spec：** `docs/epics/epic-37-test-suite-flakiness/issues.md`（Issue 2 段落）＋ `docs/epics/epic-37-test-suite-flakiness/design.md`（「已知限制」「下一步」段落）＋ `docs/epics/epic-37-test-suite-flakiness/plans/plan-issue-1.md`（同方法論的已完成先例，含三分支結論的實際寫法可參考其合併後版本）

## Global Constraints

- 所有 `flutter`／`dart` 指令一律在 `app/` 目錄下執行（`CLAUDE.md`）。
- 完整 `flutter test`（不帶檔案路徑）單次約需 5 分鐘（`CLAUDE.md`「常用指令」；Issue 1 實測落在約 2 分 50 秒到 5 分鐘之間，視機器負載而定）。
- 本 Issue 範圍只到「取得三分支之一的判定並更新 `issues.md`」為止；若判定為決定性失敗且需要進一步排查根因或修復，屬於後續另立的工單，不在本計劃執行範圍內。
- 重跑輸出的原始 log 檔一律存放於 `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/`——`docs/epics/epic-37-test-suite-flakiness/reviews/` 已在根目錄 `.gitignore` 排除，不會進版控。
- 重跑一律使用 `> <log> 2>&1`（完整寫入檔案）取得未截斷輸出，禁止接 `tail`／`head`（`issues.md` Issue 2「下一步」段落明確要求）。
- 本計劃只修改 `docs/` 底下的文件，不觸碰 `app/` 原始碼；每個 Task 結束時是否需要 commit，依該 Task 是否有版控內異動而定（純 log/筆記產出不 commit）。
- 判定結果三選一時的分流狀態對應（沿用 Issue 1 先例的判斷邏輯，非本計劃自創）：「決定性失敗」→ `ready-for-agent`（有明確根因線索可排查）；「計時類不穩定」或「未重現」→ `ready-for-human`（下一步是「加重試機制」還是「多跑幾次」還是「降低優先度」，屬於需要人判斷取捨的決策，不是規格已完整可直接動工的任務）。
- `issues.md` 裡任何指向「Issue 2」的既有交叉引用（例如 Issue 3 段落若有提及）若因本計劃的改寫而失效，須在 Task 5 一併修正為自我完整的敘述，不留給下一個 Issue 的執行者踩坑（Issue 1 的最終審查發現過這類問題，這裡預先避免）。

---

### Task 1：建立調查用資料夾，記錄本次調查的環境基準

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/`（目錄，已被父層 `.gitignore` 規則排除）
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/findings.md`

**Interfaces：**
- Consumes：無（本 Task 為起點）
- Produces：`findings.md`——後續 Task 2-5 都會往這個檔案「附加」（append）自己的結果段落；檔案一律維持這個小節結構：`## 環境資訊` / `## 單檔重跑（Task 2）` / `## 全套重跑（Task 3）` / `## 比對與結論（Task 4）`。

- [ ] **Step 1：建立資料夾**

```bash
mkdir -p ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-2
```

（於 `app/` 目錄下執行；此路徑已被 `.gitignore` 中 `docs/epics/epic-37-test-suite-flakiness/reviews/` 這條規則涵蓋，不需另外處理 `.gitignore`。）

- [ ] **Step 2：確認 `git status` 乾淨，避免調查結果被本機未提交異動污染**

```bash
git status
```

Expected：working tree clean（無未提交的 `app/` 異動）。若有未提交異動，先確認是否為需要保留的工作，用 `git stash -u` 暫存後再繼續，調查結束後再 `git stash pop`——不要略過這一步就直接重跑測試。

- [ ] **Step 3：記錄環境基準到 `findings.md`**

寫入以下內容（`<HEAD_SHA>`／`<BRANCH>` 用 `git rev-parse HEAD`／`git branch --show-current` 的實際輸出取代，日期用實際執行當天日期取代）：

```markdown
# Epic 37 Issue 2 調查記錄

## 環境資訊

- 分支：<BRANCH>
- Commit：<HEAD_SHA>
- 調查日期：<實際日期>
- 目的：判斷 `remote_catalog_screen_test.dart` 在完整 `flutter test` 規模下的既有觀察現象（測試名稱在截斷輸出中重複出現，尚未確認是否為真正失敗）究竟是決定性失敗、計時類不穩定，還是本次調查未能重現
```

- [ ] **Step 4：不需要 commit**

本步驟只建立本機調查用資料夾與筆記檔，`reviews/issue-2/` 已被 `.gitignore` 排除，不會被 `git add` 納入，故不執行 commit。

---

### Task 2：單檔 `remote_catalog_screen_test.dart` 未截斷重跑 3 次，確認基準穩定度

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/single-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/single-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/single-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/findings.md`

**Interfaces：**
- Consumes：`app/test/screens/remote_catalog_screen_test.dart`（既有測試檔，不修改）
- Produces：`single-run-{1,2,3}.log`——供本 Task Step 2 驗證用；不供後續 Task 消費（後續比對只需要全套跑的 log，見 Task 3/4）。

- [ ] **Step 1：連續重跑 3 次（於 `app/` 目錄下執行）**

```bash
for i in 1 2 3; do
  flutter test test/screens/remote_catalog_screen_test.dart > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/single-run-$i.log 2>&1
done
```

Expected：指令執行完畢，`reviews/issue-2/` 底下產生 `single-run-1.log`／`single-run-2.log`／`single-run-3.log` 三個檔案。

- [ ] **Step 2：驗證 3 次都 100% 全過**

對三個檔案分別用 Grep 工具搜尋：
- pattern `All tests passed!`，path 為各 log 檔——三個檔案都必須各命中一次。
- pattern `\[E\]`，path 為各 log 檔——三個檔案都必須是零筆命中（`files_with_matches` 模式下該檔案不應出現在結果中）。

Expected：3 個 log 檔皆「有 `All tests passed!`、無 `[E]`」（`issues.md` 記錄本檔案單獨執行於 `main` 上 100% 全過，此步驟是複驗這個既有前提）。若任何一次出現 `[E]`，代表這個既有前提本身已經改變，需要停下來記錄異常內容到 `findings.md` 並回報，不要略過直接繼續 Task 3。

- [ ] **Step 3：把結果摘要附加到 `findings.md`**

在 `## 單檔重跑（Task 2）` 小節下寫入：

```markdown
## 單檔重跑（Task 2）

`flutter test test/screens/remote_catalog_screen_test.dart` 未截斷重跑 3 次，結果：

| 次數 | log 檔 | All tests passed! | [E] 筆數 |
|---|---|---|---|
| 1 | single-run-1.log | 是/否 | N |
| 2 | single-run-2.log | 是/否 | N |
| 3 | single-run-3.log | 是/否 | N |

結論：單檔單獨執行（不受完整套件規模影響時）是否 100% 穩定通過。
```

（把「是/否」「N」換成 Step 2 的實際結果。）

- [ ] **Step 4：不需要 commit**

`reviews/issue-2/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 3：完整 `flutter test`（不帶檔案路徑）未截斷重跑 3 次

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/findings.md`

**Interfaces：**
- Consumes：整個 `app/test/` 測試套件（不修改任何測試檔）
- Produces：`full-run-{1,2,3}.log`——Task 4 會讀取這三個檔案做失敗清單比對。

單次完整 `flutter test` 約需 5 分鐘（見 Global Constraints），**每次重跑各自獨立執行一個 Step**，不要把 3 次包進同一個迴圈指令裡一次執行——單一指令執行時間需保留餘裕給工具逾時上限（10 分鐘），3 次合計會超過單一指令可用的執行時間。

- [ ] **Step 1：第 1 次全套重跑（於 `app/` 目錄下執行）**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-1.log 2>&1
```

Expected：指令執行完畢（約 3-5 分鐘），產生 `full-run-1.log`。用 Grep 工具在該檔案搜尋 pattern `Some tests failed\.|All tests passed!`（`output_mode: content`）確認測試套件本身正常跑完（不是中途因編譯錯誤等原因提早中止）。

- [ ] **Step 2：第 2 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-2.log 2>&1
```

Expected：同 Step 1，產生 `full-run-2.log` 且測試套件正常跑完。

- [ ] **Step 3：第 3 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/full-run-3.log 2>&1
```

Expected：同 Step 1，產生 `full-run-3.log` 且測試套件正常跑完。

- [ ] **Step 4：把三次總體數字摘要附加到 `findings.md`**

對每個 `full-run-N.log`，用 Grep 工具搜尋 pattern `^\d+:\d+ \+\d+.*: Some tests failed\.|^\d+:\d+ \+\d+.*: All tests passed!`（compact reporter 的結尾總結行），取得每次總測試數／總失敗數，寫入：

```markdown
## 全套重跑（Task 3）

`flutter test`（不帶檔案路徑）未截斷重跑 3 次，總體結果：

| 次數 | log 檔 | 總測試數 | 總失敗數 |
|---|---|---|---|
| 1 | full-run-1.log | N | N |
| 2 | full-run-2.log | N | N |
| 3 | full-run-3.log | N | N |
```

（把「N」換成實際數字，來源是 Grep 抓到的結尾總結行。）

- [ ] **Step 5：不需要 commit**

`reviews/issue-2/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 4：篩出歸屬 `remote_catalog_screen_test.dart` 的失敗，三選一判定

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-2/findings.md`

**Interfaces：**
- Consumes：Task 3 產出的 `full-run-{1,2,3}.log`
- Produces：`findings.md` 的 `## 比對與結論（Task 4）` 小節——Task 5 會讀取這個結論來決定怎麼改寫 `issues.md` 的 Status 與內容。

- [ ] **Step 1：從每份 `full-run-N.log` 抓出所有失敗區塊**

若 Step 1 起手發現三份 log 完全沒有任何 `[E]` 命中（用 Grep 工具對每份 `full-run-N.log` 搜尋 pattern `\[E\]`，`output_mode: files_with_matches`，若三個檔名都沒出現在結果中），直接跳到本 Task 的「分支 C：未重現」，不需要執行 Step 2-3 的歸屬比對（沒有失敗可歸屬）。

否則，對每份有命中的 `full-run-N.log` 用 Grep 工具搜尋：
- pattern：`\[E\]`
- output_mode：`content`
- `-A`：25（往後抓 25 行，涵蓋該筆失敗的例外訊息與堆疊）

每一筆結果的第一行就是失敗的測試描述（compact reporter 格式：`MM:SS +通過數 -失敗數: <測試描述文字> [E]`）。

- [ ] **Step 2：把每一筆失敗歸屬到正確的測試檔**

對 Step 1 抓到的每一筆測試描述文字（去掉行首 `MM:SS +N -M:` 前綴與行尾 `[E]`），用 Grep 工具在 `app/test/screens/remote_catalog_screen_test.dart` 搜尋這段文字（當作字面字串比對）：

- 有命中 → 歸屬本檔案（Issue 2 範圍）。
- 沒命中 → 不屬於本檔案，記錄檔名／描述文字但不列入 Issue 2 的分析（可能屬於其他檔案，那些各自有自己獨立的 Issue 處理，不在本計劃重複排查）。

對三份 log 各自整理出「本次全套跑中，歸屬 `remote_catalog_screen_test.dart` 的失敗測試描述清單」。

- [ ] **Step 3：比對三份清單，三選一判定**

- **分支 A：決定性失敗**——三份清單完全相同（同一批測試名稱，不多不少）→ 這是可排查根因的既有 bug，不是純計時問題。
- **分支 B：計時類不穩定**——三份清單彼此不同（任兩份的測試名稱集合有差異，包含「這次全過、那次失敗」的情況）→ 屬於測試間資源競爭/計時類不穩定，不是特定測試邏輯錯誤。
- **分支 C：未重現**——三份清單皆為空（Step 1 起手就跳進來的情況，或篩到最後三份都是空清單）→ 這次調查沒有重現 `issues.md` 記錄的既有觀察現象。

- [ ] **Step 4：把判定結果寫入 `findings.md`（依 Step 3 判定的分支擇一填寫）**

在 `## 比對與結論（Task 4）` 小節下寫入：

**若為分支 A（決定性失敗）：**

```markdown
## 比對與結論（Task 4）

歸屬 `remote_catalog_screen_test.dart` 的失敗測試清單（三次全套跑）：

| 測試描述 | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| <測試描述文字> | 失敗 | 失敗 | 失敗 |

判定：**決定性失敗**——三次全套跑的失敗清單完全相同。

完整例外堆疊（來源：Step 1 Grep 結果，逐字附上，不省略）：

<貼上每一筆失敗的完整例外堆疊>
```

**若為分支 B（計時類不穩定）：**

```markdown
## 比對與結論（Task 4）

歸屬 `remote_catalog_screen_test.dart` 的失敗測試清單（三次全套跑）：

| 測試描述 | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| <測試描述文字> | 失敗/通過 | 失敗/通過 | 失敗/通過 |

判定：**計時類不穩定**——三次全套跑的失敗清單彼此不同（哪幾次過、哪幾次沒過、組合不一致）。

具體現象（供後續是否加重試機制或調整測試隔離方式的判斷依據）：<描述三次之間的差異>
```

**若為分支 C（未重現）：**

```markdown
## 比對與結論（Task 4）

三次全套 `flutter test` 重跑（Task 3，<N> tests／run）皆為 `All tests passed!`，0 個 `[E]` 失敗標記歸屬 `remote_catalog_screen_test.dart`（已用 Grep 對三份 log 個別確認）。

歸屬 `remote_catalog_screen_test.dart` 的失敗測試清單：三次皆為空清單（無失敗可歸屬）。

判定：**未重現**——不屬於「決定性失敗」或「計時類不穩定」任一分支，這次調查沒有重現 `issues.md` 記錄的既有觀察現象（該現象本身就只是「測試名稱在截斷輸出中重複出現」，並非確認過的 `[E]` 失敗標記，見下方「原始觀察」）。

可能原因（未證實，供後續判斷）：
- 本次只跑 3 次，若真實重現率極低則 3 次全過不能排除既有問題仍存在。
- 原始觀察本身證據強度就偏弱（進度輸出重複出現 ≠ 確認失敗），有可能原始觀察根本不是真正的失敗，只是 `flutter test` 平行分片進度顯示的正常現象被誤讀。
- `main` 分支自原始觀察至今可能有其他改動間接改變了測試間資源競爭/計時行為；原始觀察當下與本次調查的執行環境（機器負載、並行度）也可能不同——本次調查均未查證。

**下一步（供人類決策，本 Issue 範圍不含以下任一項的執行）：** 是否要再多跑幾次以取得更可靠的重現率估計，還是接受本次「未重現」作為足夠證據、降低追蹤優先度。
```

（三個範本皆需把 `<...>` 換成 Step 1-3 的實際內容；只填寫符合 Step 3 實際判定結果的那一個範本，不要三個都填。）

- [ ] **Step 5：不需要 commit**

`reviews/issue-2/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 5：把結論寫回 `issues.md`／`epic.md`，更新分流狀態

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/issues.md`（Issue 2 段落，目前為 `## Issue 2：...` 標題到下一個 `---` 分隔線之間的內容）
- Modify: `docs/epics/epic-37-test-suite-flakiness/epic.md`（新增一則開發記錄）
- Modify: `docs/epics.md`（`epic-37-test-suite-flakiness` 該列備註，僅在狀態有變動時才需要修改；本 Issue 完成後 Epic 本身仍是 `🟡 開發中`，因為 Issue 3 尚未處理）

**Interfaces：**
- Consumes：`findings.md`（Task 4 的結論）
- Produces：無（本 Task 為終點）

**執行前務必先重新讀取 `issues.md` 目前內容，確認 Issue 2 段落的實際起訖行號**——本計劃撰寫時 Issue 2 段落是「`## Issue 2：...` 標題」到「下一個 `---` 分隔線（Issue 3 開始前）」之間，但檔案內容可能因為其他人平行處理 Issue 3 而有變動，不可硬套本計劃撰寫時的行號。

- [ ] **Step 1：改寫 `issues.md` Issue 2 段落**

依 Task 4 Step 3 的判定分支，三選一改寫 Issue 2 段落的 `**Status:**` 到段落結尾（保留 `## Issue 2：...` 標題與前後 `---` 分隔線不動）：

**若為分支 A（決定性失敗）：**

```markdown
**Status:** `ready-for-agent`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`）用未截斷方式（`> <log> 2>&1`，不接 `tail`）重跑完整 `flutter test` 3 次，確認以下測試在全套規模下每次都固定失敗（決定性，非計時類不穩定）：

- <測試描述 1>
- <測試描述 2>

（完整例外堆疊見調查當下的 `reviews/issue-2/findings.md`，該檔為本機暫存記錄未進版控；後續排查根因時若需要，可依本段落記錄的指令重新產生。）

同一份 log 中，`remote_catalog_screen_test.dart` 單獨執行（`flutter test test/screens/remote_catalog_screen_test.dart`）3 次皆 100% 全過，確認問題只在全套規模下出現。

**原始觀察（歷史記錄）：** `feat/epic-35-issue-5` 分支完整 `flutter test` 執行的最後 40 行輸出裡，本檔案的多筆測試（例如「下載與匯入 多選批次下載時逐項序列進行，非平行」「下載與匯入 下載失敗時顯示失敗狀態並可手動重試」等）反覆出現在進度輸出中；當時因為輸出被 `tail -40` 截斷，無法確認是否為真正失敗，本次調查已確認為真正的決定性失敗。

**下一步：** 依上述例外堆疊排查根因，寫後續計劃（`plan-issue-2-fix.md` 或延續本 Issue 另開 Task）修正。
```

**若為分支 B（計時類不穩定）：**

```markdown
**Status:** `ready-for-human`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`）用未截斷方式重跑完整 `flutter test` 3 次，`remote_catalog_screen_test.dart` 歸屬的失敗測試在三次之間組合不同（<具體描述哪幾次過、哪幾次沒過>），判定為計時類不穩定，非特定測試邏輯錯誤。

同一份 log 中，`remote_catalog_screen_test.dart` 單獨執行 3 次皆 100% 全過，確認問題只在全套規模下出現。

**原始觀察（歷史記錄）：** `feat/epic-35-issue-5` 分支完整 `flutter test` 執行的最後 40 行輸出裡，本檔案的多筆測試反覆出現在進度輸出中；當時因為輸出被 `tail -40` 截斷，無法確認是否為真正失敗，本次調查已確認確實存在不穩定失敗，但每次失敗的測試組合不同。

**下一步：** 需要人類決定處理方向——例如是否要在 CI／本機開發流程加上失敗自動重試，或調整測試隔離方式（例如確認是否共用了未正確重置的計時器/狀態）。
```

**若為分支 C（未重現）：**

```markdown
**Status:** `ready-for-human`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`）用未截斷方式（`> <log> 2>&1`，不接 `tail`）重跑 3 次：

- 單檔單獨執行（`flutter test test/screens/remote_catalog_screen_test.dart`）：3 次皆 <N> 個測試、0 失敗、100% 全過。
- 完整 `flutter test`（不帶檔案路徑）：3 次皆 <N> 個測試、0 失敗、100% 全過——不只是本檔案，整套測試三次都零失敗。

即本次調查（3 次全套重跑）**未重現** `issues.md` 原先記錄的觀察現象。這不屬於「決定性失敗」或「計時類不穩定」任一分支——兩者都需要至少一次失敗可供比對，本次完全沒有失敗可比對。

可能原因（未證實，供後續判斷）：本次只跑 3 次，若真實重現率極低則 3 次全過不能排除既有問題仍存在；原始觀察本身證據強度就偏弱（進度輸出重複出現 ≠ 確認失敗），有可能原本就不是真正的失敗；`main` 分支自原始觀察至今可能有其他改動間接改變了測試間資源競爭/計時行為，執行環境（機器負載、並行度）也可能不同——本次調查均未查證。完整調查記錄見 `reviews/issue-2/findings.md`（本機暫存記錄，未進版控，若需要可依上述指令重新產生）。

**原始觀察（歷史記錄，本次未重現）：** `feat/epic-35-issue-5` 分支完整 `flutter test` 執行的最後 40 行輸出裡，本檔案的多筆測試（例如「下載與匯入 多選批次下載時逐項序列進行，非平行」「下載與匯入 下載失敗時顯示失敗狀態並可手動重試」等）反覆出現在進度輸出中——**這本身並非確認過的 `[E]` 失敗標記**，`flutter test` 平行跑多檔案時同一測試名稱重複出現在進度行不代表失敗，可能只是分片進度尚未推進；發現當下的執行指令被 `tail -40` 截斷，完整失敗清單與例外堆疊已遺失，故無法從留存片段確認本檔案實際有幾筆真正失敗、是哪幾筆。

**下一步：** 需要人類決定——是否要再多跑幾次（例如 10 次以上）取得更可靠的重現率估計，還是接受本次「未重現」作為足夠證據、降低追蹤優先度、待未來又出現時再重啟調查。
```

（`<HEAD_SHA>`／`<BRANCH>`／`<測試描述 N>`／`<N>` 依 Task 1 記錄與 Task 4 結論的實際內容取代；只改寫符合實際判定分支的那一份範本。）

- [ ] **Step 2：檢查 `issues.md` 內其他段落是否有指向 Issue 2 的交叉引用會因本次改寫而失效**

用 Grep 工具在 `issues.md` 全檔搜尋 pattern `Issue 2`（排除本段落自己），確認 Issue 3 段落（或未來新增的段落）是否有「同 Issue 2」「參考 Issue 2 的下一步」之類的引用。若有，且該引用依賴的是 Issue 2 舊有的「下一步」內容（例如舊文字「用不截斷方式重跑」），需要一併改寫成自我完整的敘述，不要留給下一個 Issue 的執行者踩到已失效的引用（Issue 1 最終審查時發現過這個問題，這裡是同一類检查，不可省略）。

- [ ] **Step 3：在 `epic.md` 新增一則開發記錄**

在 `epic.md` 既有「開發記錄」段落末尾新增一段（日期換成實際執行日，內容依 Task 4 判定的分支調整用字）：

```markdown

<實際日期> Issue 2（`remote_catalog_screen_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次＋單檔重跑 3 次，判定為<決定性失敗／計時類不穩定／未重現>（擇一，依 Task 4 結論），已更新 `issues.md` Issue 2 段落與分流狀態。
```

- [ ] **Step 4：視需要更新 `docs/epics.md` 備註**

本 Issue 完成後，Epic 37 整體仍是 `🟡 開發中`（Issue 3 尚未處理），只需要把第 48 行備註欄位改成反映 Issue 2 已有結論的精簡摘要，例如（依實際判定分支調整用字）：

```
| 38 | `epic-37-test-suite-flakiness` 全套測試套件既有不穩定性追蹤 | 🟡 開發中 (Active) | 從 `epic-35` Issue 5 收尾階段發現，拆為 Issue 1-3；Issue 1、Issue 2 已完成資訊補齊（Issue 1：未重現；Issue 2：<決定性失敗／計時類不穩定／未重現>），Issue 3 仍為 `needs-info` |
```

（執行前請先確認第 38 行目前的實際內容——Issue 1 完成時已改寫過一次，行內容與本計劃撰寫時引用的版本可能不同，需以實際讀到的內容為準再修改，不要整行覆寫成本計劃寫死的字面值。）

- [ ] **Step 5：確認變更內容**

```bash
git status
git diff -- docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
```

Expected：只有這 3 個檔案有異動，且內容與 Step 1-4 寫入的一致。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
git commit -m "$(cat <<'EOF'
docs(epic-37): Issue 2 完成資訊補齊——未截斷重跑 3 次取得三選一判定

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AKwWGu3wU4jHTppNre4nnp
EOF
)"
git status
```

Expected：commit 建立成功，`git status` 顯示 working tree clean。

---

## 執行完成後的狀態

- Issue 2 從 `needs-info` 轉為 `ready-for-agent`（決定性失敗，可排查根因）或 `ready-for-human`（計時類不穩定／未重現，需人類決策方向）。
- Issue 3 不受影響，維持 `needs-info`，需要獨立的計劃（可比照本計劃的 Task 1-4 模式，換成 `pdf_reader_view_test.dart` 與其已有的完整例外堆疊）。
- 本計劃不含實際修 bug 或加重試機制——那屬於本 Issue 完成後，依 Task 5 結論另開的後續工作。
