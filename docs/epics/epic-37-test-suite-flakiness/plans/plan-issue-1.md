# Epic 37 Issue 1 — `reader_screen_test.dart` 全套規模下偶發失敗 實作計劃

> **給實作者：** 必要子技能——使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐工單（Task）執行本計劃。步驟一律用 checkbox（`- [ ]`）語法追蹤。

**目標：** 取得 `reader_screen_test.dart` 在完整 `flutter test`（不帶檔案路徑）規模下失敗的完整未截斷證據，判斷這批失敗是「決定性」（每次都是同一批測試失敗，值得排查根因）還是「計時類不穩定」（每次失敗組合不同），並把結論寫回 `issues.md`。

**架構：** 本 Issue 純屬診斷，不改動任何 `app/` 原始碼。做法是：先重跑單檔本身數次確認基準穩定，再重跑完整 `flutter test` 數次並把輸出完整存檔（不接 `tail`／`head`），從存檔中篩出歸屬本檔案的失敗，比對多次全套跑之間的失敗清單是否一致，最後把結論與（若為決定性）例外堆疊寫回 `issues.md`、更新分流狀態。

**Tech Stack：** Flutter/Dart 測試框架（`flutter test`，`package:test` compact reporter）；Bash 工具執行指令（Git Bash / POSIX sh，語法對齊 `issues.md` 既有「下一步」段落所寫的 `> <log> 2>&1` 格式）；Claude Code 內建 `Grep` 工具做 log 檔案分析。

**Spec：** `docs/epics/epic-37-test-suite-flakiness/issues.md`（Issue 1 段落）＋ `docs/epics/epic-37-test-suite-flakiness/design.md`（「已知限制」「下一步」段落）

## Global Constraints

- 所有 `flutter`／`dart` 指令一律在 `app/` 目錄下執行（`CLAUDE.md`）。
- 完整 `flutter test`（不帶檔案路徑）單次約需 5 分鐘（`CLAUDE.md`「常用指令」）。
- 本 Issue 範圍只到「取得決定性/計時類不穩定判定並更新 `issues.md`」為止；若判定為決定性失敗且需要進一步排查根因或修復，屬於後續另立的工單，不在本計劃執行範圍內。
- 重跑輸出的原始 log 檔一律存放於 `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/`——`docs/epics/epic-37-test-suite-flakiness/reviews/` 已在根目錄 `.gitignore` 排除，不會進版控。
- 重跑一律使用 `> <log> 2>&1`（完整寫入檔案）取得未截斷輸出，禁止接 `tail`／`head`（`issues.md` Issue 1「下一步」段落明確禁止）。
- 本計劃只修改 `docs/` 底下的文件（`issues.md`／`epic.md`／`docs/epics.md`），不觸碰 `app/` 原始碼；每個 Task 結束時是否需要 commit，依該 Task 是否有版控內異動而定（純 log 產出不 commit，見各 Task 說明）。

---

### Task 1：建立調查用資料夾，記錄本次調查的環境基準

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/`（目錄，已被父層 `.gitignore` 規則排除）
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/findings.md`

**Interfaces：**
- Consumes：無（本 Task 為起點）
- Produces：`findings.md`——後續 Task 2-5 都會往這個檔案「附加」（append）自己的結果段落；檔案一律維持這個小節結構：`## 環境資訊` / `## 單檔重跑（Task 2）` / `## 全套重跑（Task 3）` / `## 比對與結論（Task 4）`。

- [ ] **Step 1：建立資料夾**

```bash
mkdir -p ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-1
```

（於 `app/` 目錄下執行；此路徑已被 `.gitignore` 中 `docs/epics/epic-37-test-suite-flakiness/reviews/` 這條規則涵蓋，不需另外處理 `.gitignore`。）

- [ ] **Step 2：確認 `git status` 乾淨，避免調查結果被本機未提交異動污染**

```bash
git status
```

Expected：working tree clean（無未提交的 `app/` 異動）。若有未提交異動，先確認是否為需要保留的工作，用 `git stash -u` 暫存後再繼續，調查結束後再 `git stash pop`——不要略過這一步就直接重跑測試。

- [ ] **Step 3：記錄環境基準到 `findings.md`**

寫入以下內容（`<HEAD_SHA>`／`<BRANCH>` 用 `git rev-parse HEAD`／`git branch --show-current` 的實際輸出取代）：

```markdown
# Epic 37 Issue 1 調查記錄

## 環境資訊

- 分支：<BRANCH>
- Commit：<HEAD_SHA>
- 調查日期：2026-09-03
- 目的：判斷 `reader_screen_test.dart` 在完整 `flutter test` 規模下的失敗是決定性還是計時類不穩定
```

- [ ] **Step 4：不需要 commit**

本步驟只建立本機調查用資料夾與筆記檔，`reviews/issue-1/` 已被 `.gitignore` 排除，不會被 `git add` 納入，故不執行 commit。

---

### Task 2：單檔 `reader_screen_test.dart` 未截斷重跑 3 次，確認基準穩定度

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/single-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/single-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/single-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/findings.md`

**Interfaces：**
- Consumes：`app/test/screens/reader_screen_test.dart`（既有測試檔，不修改）
- Produces：`single-run-{1,2,3}.log`——供本 Task Step 2 驗證用；不供後續 Task 消費（後續比對只需要全套跑的 log，見 Task 3/4）。

- [ ] **Step 1：連續重跑 3 次（於 `app/` 目錄下執行）**

```bash
for i in 1 2 3; do
  flutter test test/screens/reader_screen_test.dart > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/single-run-$i.log 2>&1
done
```

Expected：指令執行完畢，`reviews/issue-1/` 底下產生 `single-run-1.log`／`single-run-2.log`／`single-run-3.log` 三個檔案。

- [ ] **Step 2：驗證 3 次都 100% 全過**

對三個檔案分別用 Grep 工具搜尋：
- pattern `All tests passed!`，path 為各 log 檔——三個檔案都必須各命中一次。
- pattern `\[E\]`，path 為各 log 檔——三個檔案都必須是零筆命中（`files_with_matches` 模式下該檔案不應出現在結果中）。

Expected：3 個 log 檔皆「有 `All tests passed!`、無 `[E]`」。若任何一次出現 `[E]`，代表「單檔單獨執行 100% 全過」這個既有前提本身已經改變，需要停下來記錄異常內容到 `findings.md` 並回報，不要略過直接繼續 Task 3。

- [ ] **Step 3：把結果摘要附加到 `findings.md`**

在 `## 單檔重跑（Task 2）` 小節下寫入：

```markdown
## 單檔重跑（Task 2）

`flutter test test/screens/reader_screen_test.dart` 未截斷重跑 3 次，結果：

| 次數 | log 檔 | All tests passed! | [E] 筆數 |
|---|---|---|---|
| 1 | single-run-1.log | 是/否 | N |
| 2 | single-run-2.log | 是/否 | N |
| 3 | single-run-3.log | 是/否 | N |

結論：單檔單獨執行（不受完整套件規模影響時）是否 100% 穩定通過。
```

（把「是/否」「N」換成 Step 2 的實際結果。）

- [ ] **Step 4：不需要 commit**

`reviews/issue-1/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 3：完整 `flutter test`（不帶檔案路徑）未截斷重跑 3 次

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/findings.md`

**Interfaces：**
- Consumes：整個 `app/test/` 測試套件（不修改任何測試檔）
- Produces：`full-run-{1,2,3}.log`——Task 4 會讀取這三個檔案做失敗清單比對。

單次完整 `flutter test` 約需 5 分鐘（見 Global Constraints），**每次重跑各自獨立執行一個 Step**，不要把 3 次包進同一個迴圈指令裡一次執行——單一指令執行時間需保留餘裕給工具逾時上限（10 分鐘），3 次合計約 15 分鐘會超過單一指令可用的執行時間。

- [ ] **Step 1：第 1 次全套重跑（於 `app/` 目錄下執行）**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-1.log 2>&1
```

Expected：指令執行完畢（約 5 分鐘），產生 `full-run-1.log`。用 Grep 工具在該檔案搜尋 pattern `Some tests failed\.|All tests passed!`（`output_mode: content`）確認測試套件本身正常跑完（不是中途因編譯錯誤等原因提早中止）。

- [ ] **Step 2：第 2 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-2.log 2>&1
```

Expected：同 Step 1，產生 `full-run-2.log` 且測試套件正常跑完。

- [ ] **Step 3：第 3 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/full-run-3.log 2>&1
```

Expected：同 Step 1，產生 `full-run-3.log` 且測試套件正常跑完。

- [ ] **Step 4：把三次總體數字摘要附加到 `findings.md`**

對每個 `full-run-N.log`，用 Grep 工具搜尋 pattern `^\d+:\d+ \+\d+.*: Some tests failed\.|^\d+:\d+ \+\d+.*: All tests passed!`（compact reporter 的結尾總結行，格式為 `MM:SS +通過數 -失敗數: All tests passed!` 或 `Some tests failed.`），取得每次總測試數／總失敗數，寫入：

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

`reviews/issue-1/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 4：篩出歸屬 `reader_screen_test.dart` 的失敗，判斷決定性 vs 計時類不穩定

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-1/findings.md`

**Interfaces：**
- Consumes：Task 3 產出的 `full-run-{1,2,3}.log`
- Produces：`findings.md` 的 `## 比對與結論（Task 4）` 小節——Task 5 會讀取這個結論來決定怎麼改寫 `issues.md` 的 Status 與內容。

- [ ] **Step 1：從每份 `full-run-N.log` 抓出所有失敗區塊**

對 `full-run-1.log`／`full-run-2.log`／`full-run-3.log` 各自用 Grep 工具搜尋：
- pattern：`\[E\]`
- output_mode：`content`
- `-A`：25（往後抓 25 行，涵蓋該筆失敗的例外訊息與堆疊）

每一筆結果的第一行就是失敗的測試描述（compact reporter 格式：`MM:SS +通過數 -失敗數: <測試描述文字> [E]`）。

- [ ] **Step 2：把每一筆失敗歸屬到正確的測試檔**

Compact reporter 的失敗行本身不含檔案路徑，只有測試描述文字。對 Step 1 抓到的每一筆測試描述文字（去掉行首 `MM:SS +N -M:` 前綴與行尾 `[E]`），用 Grep 工具在 `app/test/screens/reader_screen_test.dart` 搜尋這段文字（當作字面字串比對）：

- 有命中 → 歸屬本檔案（Issue 1 範圍）。
- 沒命中 → 不屬於本檔案，記錄檔名／描述文字但不列入 Issue 1 的分析（可能屬於 Issue 2 的 `remote_catalog_screen_test.dart` 或 Issue 3 的 `pdf_reader_view_test.dart`，那兩個 Issue 各自有自己的計劃處理，不在本計劃重複排查）。

對三份 log 各自整理出「本次全套跑中，歸屬 `reader_screen_test.dart` 的失敗測試描述清單」。

- [ ] **Step 3：比對三份清單，判斷決定性 vs 計時類不穩定**

比對規則（依實際結果二選一）：

- **決定性失敗**：三份清單完全相同（同一批測試名稱，不多不少）→ 這是可排查根因的既有 bug，不是純計時問題。
- **計時類不穩定**：三份清單彼此不同（任兩份的測試名稱集合有差異，包含「這次全過、那次失敗」的情況）→ 屬於測試間資源競爭/計時類不穩定，不是特定測試邏輯錯誤。

- [ ] **Step 4：把比對結果與（若為決定性）完整例外堆疊寫入 `findings.md`**

在 `## 比對與結論（Task 4）` 小節下寫入（依 Step 3 的實際結果擇一分支填寫）：

```markdown
## 比對與結論（Task 4）

歸屬 `reader_screen_test.dart` 的失敗測試清單（三次全套跑）：

| 測試描述 | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| <測試描述文字> | 失敗/通過 | 失敗/通過 | 失敗/通過 |

判定：決定性失敗 / 計時類不穩定（擇一，依 Step 3 規則）

（若為決定性失敗，於此處附上每一筆失敗測試的完整例外堆疊全文，來源為 Step 1 Grep 結果的完整內容，不省略。）

（若為計時類不穩定，於此處記錄「哪幾次全過、哪幾次失敗但組合不同」的具體現象，作為後續是否需要加重試或調整測試隔離方式的判斷依據。）
```

- [ ] **Step 5：不需要 commit**

`reviews/issue-1/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 5：把結論寫回 `issues.md`／`epic.md`，更新分流狀態

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/issues.md`（Issue 1 段落，第 7-22 行）
- Modify: `docs/epics/epic-37-test-suite-flakiness/epic.md`（新增一則開發記錄）
- Modify: `docs/epics.md`（第 48 行，`epic-37-test-suite-flakiness` 該列備註，僅在狀態有變動時才需要修改；本 Issue 完成後 Epic 本身仍是 `🟡 開發中`，因為還有 Issue 2、Issue 3 待處理）

**Interfaces：**
- Consumes：`findings.md`（Task 4 的結論）
- Produces：無（本 Task 為終點）

- [ ] **Step 1：改寫 `issues.md` Issue 1 段落**

依 Task 4 Step 3 的判定結果，二選一改寫 `issues.md` 第 9-22 行（`**Status:**` 到 Issue 1 結尾）：

**若判定為決定性失敗：**

```markdown
**Status:** `ready-for-agent`

**依賴：** 無

**已確認資訊：** 於 <commit-sha>（分支 <branch>）用未截斷方式（`> <log> 2>&1`，不接 `tail`）重跑完整 `flutter test` 3 次，確認以下測試在全套規模下每次都固定失敗（決定性，非計時類不穩定）：

- <測試描述 1>
- <測試描述 2>

（完整例外堆疊見調查當下的 `reviews/issue-1/findings.md`，該檔為本機暫存記錄未進版控；後續排查根因時若需要，可依本段落記錄的指令重新產生。）

同一份 log 中，`reader_screen_test.dart` 單獨執行（`flutter test test/screens/reader_screen_test.dart`）3 次皆 100% 全過，確認問題只在全套規模下出現。

**下一步：** 依上述例外堆疊排查根因（例如檢查是否為測試間共用的 mock 狀態、Isolate、計時器未正確重置），寫 `plan-issue-1-fix.md`（或延續本 Issue 另開 Task）修正。
```

**若判定為計時類不穩定：**

```markdown
**Status:** `ready-for-human`

**依賴：** 無

**已確認資訊：** 於 <commit-sha>（分支 <branch>）用未截斷方式重跑完整 `flutter test` 3 次，`reader_screen_test.dart` 歸屬的失敗測試在三次之間組合不同（<具體描述哪幾次過、哪幾次沒過>），判定為計時類不穩定，非特定測試邏輯錯誤。

同一份 log 中，`reader_screen_test.dart` 單獨執行 3 次皆 100% 全過，確認問題只在全套規模下出現。

**下一步：** 需要人類決定處理方向——例如是否要在 CI／本機開發流程加上失敗自動重試（例如 `flutter test --reporter github` 搭配重試腳本，或針對本檔案個別測試加 `retry:` 註記，視 `package:test` 支援程度而定），或調整測試隔離方式（例如確認是否共用了未正確重置的計時器/Isolate/全域狀態）。
```

（`<commit-sha>`／`<branch>`／`<測試描述 N>` 依 Task 1 記錄與 Task 4 結論的實際內容取代。）

- [ ] **Step 2：在 `epic.md` 新增一則開發記錄**

在 `epic.md` 第 11 行之後（既有「開發記錄」段落末尾）新增一段（日期換成實際執行日）：

```markdown

2026-09-03 Issue 1（`reader_screen_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次＋單檔重跑 3 次，判定為<決定性失敗／計時類不穩定>（擇一，依 Task 4 結論），已更新 `issues.md` Issue 1 段落與分流狀態。
```

- [ ] **Step 3：視需要更新 `docs/epics.md` 備註**

本 Issue 完成後，Epic 37 整體仍是 `🟡 開發中`（Issue 2、Issue 3 尚未處理），只需要把第 48 行備註欄位中「皆為 `needs-info`」改成反映 Issue 1 已有結論的精簡摘要，例如：

```
| 38 | `epic-37-test-suite-flakiness` 全套測試套件既有不穩定性追蹤 | 🟡 開發中 (Active) | 從 `epic-35` Issue 5 收尾階段發現，拆為 Issue 1-3；Issue 1 已完成資訊補齊（<決定性失敗／計時類不穩定>），Issue 2、Issue 3 仍為 `needs-info` |
```

- [ ] **Step 4：確認變更內容**

```bash
git status
git diff -- docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
```

Expected：只有這 3 個檔案有異動，且內容與 Step 1-3 寫入的一致。

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
git commit -m "$(cat <<'EOF'
docs(epic-37): Issue 1 完成資訊補齊——未截斷重跑取得決定性/計時類不穩定判定

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AKwWGu3wU4jHTppNre4nnp
EOF
)"
git status
```

Expected：commit 建立成功，`git status` 顯示 working tree clean。

---

## 執行完成後的狀態

- Issue 1 從 `needs-info` 轉為 `ready-for-agent`（決定性失敗，可排查根因）或 `ready-for-human`（計時類不穩定，需人類決策方向）。
- Issue 2、Issue 3 不受影響，維持 `needs-info`，各自需要獨立的計劃（可比照本計劃的 Task 1-4 模式，換成各自的測試檔與已知資訊）。
- 本計劃不含實際修 bug 或加重試機制——那屬於本 Issue 完成後，依 Task 5 結論另開的後續工作。
