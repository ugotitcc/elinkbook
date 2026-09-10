# Epic 37 Issue 3 — `pdf_reader_view_test.dart` 全套規模下偶發失敗 實作計劃

> **給實作者：** 必要子技能——使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐工單（Task）執行本計劃。步驟一律用 checkbox（`- [ ]`）語法追蹤。

**目標：** 取得 `pdf_reader_view_test.dart` 在完整 `flutter test`（不帶檔案路徑）規模下的完整未截斷證據，判斷是「決定性失敗」「計時類不穩定」還是「未重現」三者之一，並把結論寫回 `issues.md`。

**架構：** 本 Issue 純屬診斷，不改動任何 `app/` 原始碼，方法與 Epic 37 Issue 1、Issue 2（`plans/plan-issue-1.md`／`plans/plan-issue-2.md`，皆已完成並合併）完全相同：先重跑單檔本身數次確認基準穩定，再重跑完整 `flutter test` 數次並把輸出完整存檔（不接 `tail`／`head`），從存檔中篩出歸屬本檔案的失敗，比對多次全套跑之間的失敗清單，最後把結論寫回 `issues.md`、更新分流狀態。**與 Issue 1、Issue 2 的關鍵差異：** 本 Issue 是三者中唯一從一開始就有完整例外堆疊可查的一筆（來自 `main` 分支未截斷的完整 `flutter test` 存檔輸出），不需要像 Issue 1、Issue 2 那樣從零猜測失敗內容——本計劃撰寫時已先讀過 `app/test/reader/pdf_reader_view_test.dart` 與其共用測試工具 `app/test/support/pump_until_pdf_ready.dart` 的原始碼，把「斷言對象的呼叫時機依賴」這個 `issues.md` 既有「下一步」要求的閱讀工作預先做完，結論見下方「已知程式碼脈絡」，直接寫入本計劃，執行者不需要重新摸索。

## 已知程式碼脈絡（本計劃撰寫時已完成的程式碼閱讀，取代 `issues.md` 舊「下一步」要求的第一步）

`issues.md` 目前記錄的斷言敘述（「形式上像是斷言某個 mock／平台通道方法被呼叫的次數」）讀完原始碼後確認**不夠精確**，本計劃 Task 5 會一併修正這個描述。實際情況：

- 失敗測試「content:// URI 開書透過平台通道一次性讀取全部位元組」的完整程式碼在 `app/test/reader/pdf_reader_view_test.dart:124-164`。
- 例外堆疊指向的 `pdf_reader_view_test.dart:162:5`，對應的實際程式碼是 `expect(renderedCount, 1);`（第 162 行）——這是**斷言 `PdfReaderView.onPageRendered` 回呼被觸發的次數**，不是平台通道方法呼叫次數（那個斷言在下一行 `expect(readAllCalled, isTrue)`，第 163 行，例外堆疊沒有指向那一行）。
- 這個測試等待「渲染完成」的方式是共用工具 `pumpUntilPdfReady`（`app/test/support/pump_until_pdf_ready.dart:18-32`）：預設 `maxIterations: 30`，每一輪跑 `tester.pump(const Duration(milliseconds: 100))`（fake clock 虛擬推進，framework 動畫/計時器邏輯用）＋真實 `Future.delayed(const Duration(milliseconds: 10))`（讓 `runAsync` 跳出 fake zone 之後的底層真正非同步 I/O，例如 mock 平台通道寫暫存檔、`pdfrx` 開檔解碼，有機會推進）。**這個迴圈逾時不會拋出例外，只會安靜結束**（`condition` 30 輪內都不成立就直接跳出 for 迴圈），之後才執行 `expect(renderedCount, 1)`。
- 換言之，目前最合理的假設是：全套規模下（`app/` 底下逾 1800 個測試平行跑）系統資源競爭較嚴重，這個測試底層的非同步鏈路（mock 平台通道 handler → 寫暫存檔 → `pdfrx` 開檔／解碼 → 觸發 `onPageRendered`）沒能在 `pumpUntilPdfReady` 給的預算內（30 輪、每輪 100ms fake pump ＋ 10ms 真實延遲）完成，`renderedCount` 因此維持 0，跟觀察到的「Expected: 1 / Actual: 0」完全吻合。**這是本計劃提出的假設，不是已證實的結論**——本計劃範圍只做重跑取證，不含驗證或修復這個假設，若後續判定為決定性失敗，這個假設會寫進 `issues.md` 供下一個排根因的工單參考。

## Global Constraints

- 所有 `flutter`／`dart` 指令一律在 `app/` 目錄下執行（`CLAUDE.md`）。
- 完整 `flutter test`（不帶檔案路徑）單次約需 3-5 分鐘（依機器負載，Issue 1／Issue 2 實測皆落在此區間）。
- 本 Issue 範圍只到「取得三選一判定並更新 `issues.md`」為止；若判定為決定性失敗且需要進一步驗證上方「已知程式碼脈絡」的假設或修復，屬於後續另立的工單，不在本計劃執行範圍內。
- 重跑輸出的原始 log 檔一律存放於 `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/`——`docs/epics/epic-37-test-suite-flakiness/reviews/` 已在根目錄 `.gitignore` 排除，不會進版控。
- 重跑一律使用 `> <log> 2>&1`（完整寫入檔案）取得未截斷輸出，禁止接 `tail`／`head`（`issues.md` Issue 3「下一步」段落明確要求）。
- 本計劃只修改 `docs/` 底下的文件，不觸碰 `app/` 原始碼；每個 Task 結束時是否需要 commit，依該 Task 是否有版控內異動而定（純 log/筆記產出不 commit）。
- 判定結果三選一時的分流狀態對應（沿用 Issue 1、Issue 2 先例）：「決定性失敗」→ `ready-for-agent`；「計時類不穩定」或「未重現」→ `ready-for-human`。
- **交叉引用檢查範圍（吸取 Issue 2 最終審查的教訓，範圍已擴大）：** Task 5 改寫 `issues.md` Issue 3 段落後，須用 Grep 工具檢查**整個 `docs/epics/epic-37-test-suite-flakiness/` 目錄**（不只 `issues.md`，也包含 `design.md`／`epic.md`）有沒有指向 Issue 3 舊有段落名稱（「目前已知資訊」）的交叉引用會因改寫而失效——Issue 2 的最終審查發現 `design.md` 裡有一條這樣的引用沒被涵蓋到，本計劃從一開始就把檢查範圍寫對，不留給最終審查才發現。
- **範本用字要求（吸取 Issue 2 最終審查的教訓）：** Task 5 三個分支範本的「已確認資訊」段落一律包含「等同 \`main\` `<merge-base-sha>`」的對應關係（不要像 Issue 2 一開始漏寫，靠最終審查才補上）；凡是段落內部指向「原始觀察」小節的句子，一律寫「本 Issue 下方『原始觀察』段落」這種自我完整的相對敘述，不要寫成對 `issues.md` 整份檔案的模糊自我指涉。

---

### Task 1：建立調查用資料夾，記錄本次調查的環境基準

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/`（目錄，已被父層 `.gitignore` 規則排除）
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/findings.md`

**Interfaces：**
- Consumes：無（本 Task 為起點）
- Produces：`findings.md`——後續 Task 2-5 都會往這個檔案「附加」（append）自己的結果段落；檔案一律維持這個小節結構：`## 環境資訊` / `## 單檔重跑（Task 2）` / `## 全套重跑（Task 3）` / `## 比對與結論（Task 4）`。

- [ ] **Step 1：建立資料夾**

```bash
mkdir -p ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-3
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
# Epic 37 Issue 3 調查記錄

## 環境資訊

- 分支：<BRANCH>
- Commit：<HEAD_SHA>
- 調查日期：<實際日期>
- 目的：判斷 `pdf_reader_view_test.dart` 在完整 `flutter test` 規模下的既有觀察（「content:// URI 開書透過平台通道一次性讀取全部位元組」測試的 `expect(renderedCount, 1)` 斷言，`app/test/reader/pdf_reader_view_test.dart:162`，實際為 0）究竟是決定性失敗、計時類不穩定，還是本次調查未能重現；已知程式碼脈絡（`pumpUntilPdfReady` 等待預算逾時不拋例外的假設）見 `plans/plan-issue-3.md` 開頭段落。
```

- [ ] **Step 4：不需要 commit**

本步驟只建立本機調查用資料夾與筆記檔，`reviews/issue-3/` 已被 `.gitignore` 排除，不會被 `git add` 納入，故不執行 commit。

---

### Task 2：單檔 `pdf_reader_view_test.dart` 未截斷重跑 3 次，確認基準穩定度

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/single-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/single-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/single-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/findings.md`

**Interfaces：**
- Consumes：`app/test/reader/pdf_reader_view_test.dart`（既有測試檔，共 9 筆 `testWidgets`，不修改）
- Produces：`single-run-{1,2,3}.log`——供本 Task Step 2 驗證用；不供後續 Task 消費（後續比對只需要全套跑的 log，見 Task 3/4）。

- [ ] **Step 1：連續重跑 3 次（於 `app/` 目錄下執行）**

```bash
for i in 1 2 3; do
  flutter test test/reader/pdf_reader_view_test.dart > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/single-run-$i.log 2>&1
done
```

Expected：指令執行完畢，`reviews/issue-3/` 底下產生 `single-run-1.log`／`single-run-2.log`／`single-run-3.log` 三個檔案。本檔案只有 9 筆測試，單次執行應在數十秒內完成。

- [ ] **Step 2：驗證 3 次都 100% 全過**

對三個檔案分別用 Grep 工具搜尋：
- pattern `All tests passed!`，path 為各 log 檔——三個檔案都必須各命中一次。
- pattern `\[E\]`，path 為各 log 檔——三個檔案都必須是零筆命中（`files_with_matches` 模式下該檔案不應出現在結果中）。

Expected：3 個 log 檔皆「有 `All tests passed!`、無 `[E]`」。若任何一次出現 `[E]`，代表「單檔單獨執行 100% 全過」這個前提本身不成立（`issues.md` 目前尚未像 Issue 1、Issue 2 那樣明確記錄過這個前提，本步驟是第一次確認），需要停下來記錄異常內容（測試描述、完整例外堆疊）到 `findings.md` 並回報，不要略過直接繼續 Task 3。

- [ ] **Step 3：把結果摘要附加到 `findings.md`**

在 `## 單檔重跑（Task 2）` 小節下寫入：

```markdown
## 單檔重跑（Task 2）

`flutter test test/reader/pdf_reader_view_test.dart` 未截斷重跑 3 次，結果：

| 次數 | log 檔 | All tests passed! | [E] 筆數 |
|---|---|---|---|
| 1 | single-run-1.log | 是/否 | N |
| 2 | single-run-2.log | 是/否 | N |
| 3 | single-run-3.log | 是/否 | N |

結論：單檔單獨執行（不受完整套件規模影響時）是否 100% 穩定通過。3 次重跑皆<成功/出現失敗>，每次執行 9 個測試，<N> 個失敗。
```

（把「是/否」「N」「<成功/出現失敗>」換成 Step 2 的實際結果，寫成肯定敘述，不要留問句字面——不要重蹈 Epic 37 Issue 2 Task 2 上一輪審查抓到的「結論句留著『是否』沒改成肯定敘述」這個錯誤。）

- [ ] **Step 4：不需要 commit**

`reviews/issue-3/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 3：完整 `flutter test`（不帶檔案路徑）未截斷重跑 3 次

**Files：**
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-1.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-2.log`
- Create: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-3.log`
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/findings.md`

**Interfaces：**
- Consumes：整個 `app/test/` 測試套件（不修改任何測試檔）
- Produces：`full-run-{1,2,3}.log`——Task 4 會讀取這三個檔案做失敗清單比對。

單次完整 `flutter test` 約需 3-5 分鐘（見 Global Constraints），**每次重跑各自獨立執行一個 Step**，不要把 3 次包進同一個迴圈指令裡一次執行——單一指令執行時間需保留餘裕給工具逾時上限（10 分鐘），3 次合計會超過單一指令可用的執行時間。

- [ ] **Step 1：第 1 次全套重跑（於 `app/` 目錄下執行）**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-1.log 2>&1
```

Expected：指令執行完畢（約 3-5 分鐘），產生 `full-run-1.log`。用 Grep 工具在該檔案搜尋 pattern `Some tests failed\.|All tests passed!`（`output_mode: content`）確認測試套件本身正常跑完（不是中途因編譯錯誤等原因提早中止）。

- [ ] **Step 2：第 2 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-2.log 2>&1
```

Expected：同 Step 1，產生 `full-run-2.log` 且測試套件正常跑完。

- [ ] **Step 3：第 3 次全套重跑**

```bash
flutter test > ../docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/full-run-3.log 2>&1
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

`reviews/issue-3/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 4：篩出歸屬 `pdf_reader_view_test.dart` 的失敗，三選一判定

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/reviews/issue-3/findings.md`

**Interfaces：**
- Consumes：Task 3 產出的 `full-run-{1,2,3}.log`
- Produces：`findings.md` 的 `## 比對與結論（Task 4）` 小節——Task 5 會讀取這個結論來決定怎麼改寫 `issues.md` 的 Status 與內容。

- [ ] **Step 1：從每份 `full-run-N.log` 抓出所有失敗區塊**

若 Step 1 起手發現三份 log 完全沒有任何 `[E]` 命中（用 Grep 工具對每份 `full-run-N.log` 搜尋 pattern `\[E\]`，`output_mode: files_with_matches`，若三個檔名都沒出現在結果中），直接跳到本 Task 的「分支 C：未重現」，不需要執行 Step 2-3 的歸屬比對（沒有失敗可歸屬）。

否則，對每份有命中的 `full-run-N.log` 用 Grep 工具搜尋：
- pattern：`\[E\]`
- output_mode：`content`
- `-A`：25（往後抓 25 行，涵蓋該筆失敗的例外訊息與堆疊）

每一筆結果的第一行就是失敗的測試描述（compact reporter 格式：`MM:SS +通過數 -失敗數: <測試描述文字> [E]`）。特別留意「content:// URI 開書透過平台通道一次性讀取全部位元組」這筆——這是 `issues.md` 已知曾在 `main` 分支重現過的測試（見上方「已知程式碼脈絡」）。

- [ ] **Step 2：把每一筆失敗歸屬到正確的測試檔**

對 Step 1 抓到的每一筆測試描述文字（去掉行首 `MM:SS +N -M:` 前綴與行尾 `[E]`），用 Grep 工具在 `app/test/reader/pdf_reader_view_test.dart` 搜尋這段文字（當作字面字串比對）：

- 有命中 → 歸屬本檔案（Issue 3 範圍）。
- 沒命中 → 不屬於本檔案，記錄檔名／描述文字但不列入 Issue 3 的分析（那些各自有自己獨立的 Issue 處理，不在本計劃重複排查）。

對三份 log 各自整理出「本次全套跑中，歸屬 `pdf_reader_view_test.dart` 的失敗測試描述清單」。

- [ ] **Step 3：比對三份清單，三選一判定**

- **分支 A：決定性失敗**——三份清單完全相同（同一批測試名稱，不多不少）→ 這是可排查根因的既有 bug，不是純計時問題。
- **分支 B：計時類不穩定**——三份清單彼此不同（任兩份的測試名稱集合有差異，包含「這次全過、那次失敗」的情況）→ 屬於測試間資源競爭/計時類不穩定，不是特定測試邏輯錯誤。
- **分支 C：未重現**——三份清單皆為空（Step 1 起手就跳進來的情況，或篩到最後三份都是空清單）→ 這次調查沒有重現 `issues.md` 記錄的既有觀察現象。

- [ ] **Step 4：把判定結果寫入 `findings.md`（依 Step 3 判定的分支擇一填寫）**

在 `## 比對與結論（Task 4）` 小節下寫入：

**若為分支 A（決定性失敗）：**

```markdown
## 比對與結論（Task 4）

歸屬 `pdf_reader_view_test.dart` 的失敗測試清單（三次全套跑）：

| 測試描述 | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| <測試描述文字> | 失敗 | 失敗 | 失敗 |

判定：**決定性失敗**——三次全套跑的失敗清單完全相同。

完整例外堆疊（來源：Step 1 Grep 結果，逐字附上，不省略）：

<貼上每一筆失敗的完整例外堆疊>

若失敗清單包含「content:// URI 開書透過平台通道一次性讀取全部位元組」，對照本計劃開頭「已知程式碼脈絡」段落的假設（`pumpUntilPdfReady` 等待預算在全套規模下不足），記錄本次例外堆疊的行號是否仍是 `pdf_reader_view_test.dart:162`（`expect(renderedCount, 1)`），確認假設是否成立；若失敗清單包含其他測試，比照同樣方式記錄其例外堆疊指向的確切行號與程式碼內容，不要只複製 `issues.md` 既有的猜測敘述。
```

**若為分支 B（計時類不穩定）：**

```markdown
## 比對與結論（Task 4）

歸屬 `pdf_reader_view_test.dart` 的失敗測試清單（三次全套跑）：

| 測試描述 | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| <測試描述文字> | 失敗/通過 | 失敗/通過 | 失敗/通過 |

判定：**計時類不穩定**——三次全套跑的失敗清單彼此不同（哪幾次過、哪幾次沒過、組合不一致）。

具體現象（供後續是否加重試機制或調整測試隔離方式的判斷依據）：<描述三次之間的差異>

若「content:// URI 開書透過平台通道一次性讀取全部位元組」出現在任一次失敗清單中，對照本計劃開頭「已知程式碼脈絡」段落的假設（`pumpUntilPdfReady` 等待預算在全套規模下不足），這個假設與「計時類不穩定」判定相符，可作為後續調整 `maxIterations`／`delayBetweenPumps` 的參考依據，但本 Issue 範圍不含實際調整。
```

**若為分支 C（未重現）：**

```markdown
## 比對與結論（Task 4）

三次全套 `flutter test` 重跑（Task 3，<N> tests／run）皆為 `All tests passed!`，0 個 `[E]` 失敗標記歸屬 `pdf_reader_view_test.dart`（已用 Grep 對三份 log 個別確認）。

歸屬 `pdf_reader_view_test.dart` 的失敗測試清單：三次皆為空清單（無失敗可歸屬）。

判定：**未重現**——不屬於「決定性失敗」或「計時類不穩定」任一分支，這次調查沒有重現 `issues.md` 記錄的既有觀察現象（`main` 分支曾出現過帶完整例外堆疊的一次失敗，見下方「原始觀察」）。

可能原因（未證實，供後續判斷）：
- 本次只跑 3 次，若真實重現率極低則 3 次全過不能排除既有問題仍存在。
- 本計劃開頭「已知程式碼脈絡」段落提出的假設（`pumpUntilPdfReady` 等待預算在系統負載較高時不足）若成立，重現與否可能高度依賴當下機器負載/並行度，本次調查的機器負載可能剛好不足以觸發逾時。
- `main` 分支自原始觀察至今可能有其他改動間接改變了測試間資源競爭/計時行為——本次調查均未查證。

**下一步（供人類決策，本 Issue 範圍不含以下任一項的執行）：** 是否要再多跑幾次（例如 10 次以上，或在刻意製造較高系統負載的情況下重跑，驗證「已知程式碼脈絡」段落的等待預算假設）以取得更可靠的重現率估計，還是接受本次「未重現」作為足夠證據、降低追蹤優先度。
```

（三個範本皆需把 `<...>` 換成 Step 1-3 的實際內容；只填寫符合 Step 3 實際判定結果的那一個範本，不要三個都填。）

- [ ] **Step 5：不需要 commit**

`reviews/issue-3/` 底下的變更皆已被 `.gitignore` 排除，本步驟不執行 commit。

---

### Task 5：把結論寫回 `issues.md`／`epic.md`，更新分流狀態

**Files：**
- Modify: `docs/epics/epic-37-test-suite-flakiness/issues.md`（Issue 3 段落，目前為 `## Issue 3：...` 標題到檔案結尾——Issue 3 是目前檔案最後一個 Issue，沒有後續的 `---` 分隔線）
- Modify: `docs/epics/epic-37-test-suite-flakiness/epic.md`（新增一則開發記錄）
- Modify: `docs/epics.md`（`epic-37-test-suite-flakiness` 該列備註；本 Issue 完成後三個 Issue 皆已處理完畢，Epic 狀態是否要改為其他狀態由人類決定，本計劃只更新備註文字，不擅自改變 🟡/🟢 狀態燈號）

**Interfaces：**
- Consumes：`findings.md`（Task 4 的結論）
- Produces：無（本 Task 為終點）

**執行前務必先重新讀取 `issues.md` 目前內容，確認 Issue 3 段落的實際起訖範圍**——本計劃撰寫時 Issue 3 是檔案最後一個 Issue（標題到檔案結尾），但檔案內容可能因為之後新增其他 Issue 而有變動，不可硬套本計劃撰寫時的假設。

- [ ] **Step 1：改寫 `issues.md` Issue 3 段落**

依 Task 4 Step 3 的判定分支，三選一改寫 Issue 3 段落的 `**Status:**` 到段落結尾（保留 `## Issue 3：...` 標題不動；若段落後面已有新內容則保留其前的 `---` 分隔線，若 Issue 3 仍是檔案最後一段則不需要新增分隔線）：

**若為分支 A（決定性失敗）：**

```markdown
**Status:** `ready-for-agent`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`，等同 `main` `<MERGE_BASE_SHA>`）用未截斷方式（`> <log> 2>&1`，不接 `tail`）重跑完整 `flutter test` 3 次，確認以下測試在全套規模下每次都固定失敗（決定性，非計時類不穩定）：

- <測試描述 1>
- <測試描述 2（若有）>

（完整例外堆疊見調查當下的 `reviews/issue-3/findings.md`，該檔為本機暫存記錄未進版控；後續排查根因時若需要，可依本段落記錄的指令重新產生。）

同一份 log 中，`pdf_reader_view_test.dart` 單獨執行（`flutter test test/reader/pdf_reader_view_test.dart`）3 次皆 100% 全過，確認問題只在全套規模下出現。

**原始觀察（歷史記錄）：** 測試「content:// URI 開書透過平台通道一次性讀取全部位元組」（`app/test/reader/pdf_reader_view_test.dart:124-164`）曾在 `main` 分支未截斷的完整 `flutter test` 存檔輸出中重現，斷言為 `expect(renderedCount, 1)`（第 162 行，斷言 `onPageRendered` 回呼觸發次數，不是平台通道方法呼叫次數），實際為 0；該測試透過共用工具 `pumpUntilPdfReady`（`app/test/support/pump_until_pdf_ready.dart`）等待渲染完成，預設等待預算為 30 輪、每輪 100ms fake pump ＋ 10ms 真實延遲，逾時不拋例外而是安靜結束迴圈。本次調查已確認為真正的決定性失敗<，並確認例外堆疊仍指向同一行/改指向其他行，見下方「原始觀察」實際填入 Task 4 記錄的內容>。

**下一步：** 驗證「已知程式碼脈絡」段落提出的等待預算假設（例如在全套規模下對這個測試加上額外的除錯輸出、或暫時放大 `maxIterations`／`delayBetweenPumps` 觀察是否消除失敗），確認根因後寫後續計劃（`plan-issue-3-fix.md` 或延續本 Issue 另開 Task）修正。
```

**若為分支 B（計時類不穩定）：**

```markdown
**Status:** `ready-for-human`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`，等同 `main` `<MERGE_BASE_SHA>`）用未截斷方式重跑完整 `flutter test` 3 次，`pdf_reader_view_test.dart` 歸屬的失敗測試在三次之間組合不同（<具體描述哪幾次過、哪幾次沒過>），判定為計時類不穩定，非特定測試邏輯錯誤。

同一份 log 中，`pdf_reader_view_test.dart` 單獨執行 3 次皆 100% 全過，確認問題只在全套規模下出現。

**原始觀察（歷史記錄）：** 測試「content:// URI 開書透過平台通道一次性讀取全部位元組」（`app/test/reader/pdf_reader_view_test.dart:124-164`）曾在 `main` 分支未截斷的完整 `flutter test` 存檔輸出中重現，斷言為 `expect(renderedCount, 1)`（第 162 行），實際為 0；該測試透過共用工具 `pumpUntilPdfReady` 等待渲染完成，等待預算逾時不拋例外而是安靜結束迴圈，本次調查已確認確實存在不穩定失敗，且與「等待預算在系統負載較高時不足」的假設相符（見本計劃開頭「已知程式碼脈絡」段落）。

**下一步：** 需要人類決定處理方向——例如是否要放大 `pumpUntilPdfReady` 的等待預算（`maxIterations`／`delayBetweenPumps`）、改為以事件/回呼為準的等待機制而非固定輪數，或加上失敗自動重試。
```

**若為分支 C（未重現）：**

```markdown
**Status:** `ready-for-human`

**依賴：** 無

**已確認資訊：** 於 commit `<HEAD_SHA>`（分支 `<BRANCH>`，等同 `main` `<MERGE_BASE_SHA>`）用未截斷方式（`> <log> 2>&1`，不接 `tail`）重跑 3 次：

- 單檔單獨執行（`flutter test test/reader/pdf_reader_view_test.dart`）：3 次皆 <N> 個測試、0 失敗、100% 全過。
- 完整 `flutter test`（不帶檔案路徑）：3 次皆 <N> 個測試、0 失敗、100% 全過——不只是本檔案，整套測試三次都零失敗。

即本次調查（3 次全套重跑）**未重現**本 Issue 下方「原始觀察」段落記錄的現象。這不屬於「決定性失敗」或「計時類不穩定」任一分支——兩者都需要至少一次失敗可供比對，本次完全沒有失敗可比對。

可能原因（未證實，供後續判斷）：本次只跑 3 次，若真實重現率極低則 3 次全過不能排除既有問題仍存在；本 Issue「原始觀察」段落提出的等待預算假設若成立，重現與否可能高度依賴當下機器負載/並行度，本次調查的機器負載可能剛好不足以觸發逾時；`main` 分支自原始觀察至今可能有其他改動間接改變了測試間資源競爭/計時行為——本次調查均未查證。完整調查記錄見 `reviews/issue-3/findings.md`（本機暫存記錄，未進版控，若需要可依上述指令重新產生）。

**原始觀察（歷史記錄，本次未重現）：** 測試「content:// URI 開書透過平台通道一次性讀取全部位元組」（`app/test/reader/pdf_reader_view_test.dart:124-164`）曾在 `main` 分支未截斷的完整 `flutter test` 存檔輸出中重現，斷言為 `expect(renderedCount, 1)`（第 162 行，斷言 `onPageRendered` 回呼觸發次數，不是平台通道方法呼叫次數，那個斷言在下一行 `expect(readAllCalled, isTrue)`），實際為 0。該測試透過共用工具 `pumpUntilPdfReady`（`app/test/support/pump_until_pdf_ready.dart`）等待渲染完成，預設等待預算為 30 輪、每輪 100ms fake pump ＋ 10ms 真實延遲，逾時不拋例外而是安靜結束迴圈——目前的假設是全套規模下系統資源競爭導致底層非同步鏈路（mock 平台通道 handler → 寫暫存檔 → `pdfrx` 開檔解碼 → 觸發 `onPageRendered`）沒能在此預算內完成，此假設未經證實。

**下一步：** 需要人類決定——是否要再多跑幾次（例如 10 次以上，或刻意製造較高系統負載的情況下重跑）驗證等待預算假設，還是接受本次「未重現」作為足夠證據、降低追蹤優先度、待未來又出現時再重啟調查。
```

（`<HEAD_SHA>`／`<BRANCH>`／`<MERGE_BASE_SHA>`／`<測試描述 N>`／`<N>` 依 Task 1 記錄與 Task 4 結論的實際內容取代；`<MERGE_BASE_SHA>` 用 `git merge-base main HEAD` 取得；只改寫符合實際判定分支的那一份範本。）

- [ ] **Step 2：檢查整個 Epic 目錄內是否有指向 Issue 3 舊有段落名稱的交叉引用會因本次改寫而失效**

用 Grep 工具在 `docs/epics/epic-37-test-suite-flakiness/` 整個目錄（`issues.md`、`design.md`、`epic.md` 皆須檢查，不只 `issues.md`——這是吸取 Epic 37 Issue 2 最終審查教訓後擴大的檢查範圍，見 Global Constraints）搜尋 pattern `Issue 3` 與 `目前已知資訊`，確認：

1. `issues.md` 內是否有其他段落用「同 Issue 3」之類的措辭引用 Issue 3 舊有的「下一步」或「目前已知資訊」內容（目前檔案裡沒有其他 Issue 在 Issue 3 之後，理論上不會有，但仍須實際執行 Grep 確認，不可省略）。
2. `design.md` 第 26-28 行附近是否有指向「目前已知資訊」這個小節名稱的引用（本計劃撰寫時讀過，`design.md` 提到 Issue 3「有完整例外堆疊可查」但沒有指名具體小節標題，理論上不受影響，仍須實際執行 Grep 確認）。
3. `epic.md` 是否有指向 Issue 3「目前已知資訊」小節名稱的引用（本計劃撰寫時讀過，`epic.md` 現有內容沒有針對 Issue 3 的具體小節引用，仍須實際執行 Grep 確認）。

若發現任何失效引用，一併改寫成自我完整的敘述，不要留給後續讀者踩到已失效的引用。

- [ ] **Step 3：在 `epic.md` 新增一則開發記錄**

在 `epic.md` 既有「開發記錄」段落末尾新增一段（日期換成實際執行日，內容依 Task 4 判定的分支調整用字，數字比照 Issue 1／Issue 2 既有記錄的詳細程度）：

```markdown

<實際日期> Issue 3（`pdf_reader_view_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次＋單檔重跑 3 次，判定為<決定性失敗／計時類不穩定／未重現>（擇一，依 Task 4 結論；若為未重現則補上「3 次全套跑皆 <N> tests、0 失敗，3 次單檔重跑皆 <N> tests、0 失敗」），已更新 `issues.md` Issue 3 段落與分流狀態。Epic 37 三個 Issue（`reader_screen_test.dart`／`remote_catalog_screen_test.dart`／`pdf_reader_view_test.dart`）皆已完成資訊補齊，是否歸檔或保留追蹤由人類決定。
```

- [ ] **Step 4：更新 `docs/epics.md` 備註**

本 Issue 完成後，三個 Issue 皆已處理完畢；把第 48 行（或執行當下實際的行號，請先重新讀取確認）備註欄位改成反映三個 Issue 皆已完成資訊補齊的精簡摘要，例如（依實際判定分支調整用字）：

```
| 38 | `epic-37-test-suite-flakiness` 全套測試套件既有不穩定性追蹤 | 🟡 開發中 (Active) | 從 `epic-35` Issue 5 收尾階段發現，拆為 Issue 1-3，三者皆已完成資訊補齊（Issue 1、Issue 2：未重現；Issue 3：<決定性失敗／計時類不穩定／未重現>），是否歸檔待人類決定 |
```

（執行前請先確認第 48 行目前的實際內容——Issue 1、Issue 2 完成時各改寫過一次，行內容與本計劃撰寫時引用的版本可能不同，需以實際讀到的內容為準再修改，不要整行覆寫成本計劃寫死的字面值；**狀態欄位維持 `🟡 開發中 (Active)` 不變，不要自行改成 `🟢 已歸檔`——是否歸檔是人類決定的事，本 Task 只更新備註文字**。）

- [ ] **Step 5：確認變更內容**

```bash
git status
git diff -- docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
```

Expected：只有這 3 個檔案有異動（若 Step 2 發現 `design.md` 有失效引用需要修正，則額外包含 `design.md`），且內容與 Step 1-4 寫入的一致。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-37-test-suite-flakiness/issues.md docs/epics/epic-37-test-suite-flakiness/epic.md docs/epics.md
```

（若 Step 2 有修正 `design.md`，一併 `git add docs/epics/epic-37-test-suite-flakiness/design.md`。）

```bash
git commit -m "$(cat <<'EOF'
docs(epic-37): Issue 3 完成資訊補齊——未截斷重跑 3 次取得三選一判定

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AKwWGu3wU4jHTppNre4nnp
EOF
)"
git status
```

Expected：commit 建立成功，`git status` 顯示 working tree clean。

---

## 執行完成後的狀態

- Issue 3 從 `needs-info` 轉為 `ready-for-agent`（決定性失敗，可排查根因）或 `ready-for-human`（計時類不穩定／未重現，需人類決策方向）。
- Epic 37 三個 Issue 全數完成資訊補齊——是否歸檔整個 Epic、或針對判定為「決定性失敗」／「計時類不穩定」的 Issue 開後續修復工單，皆交由人類決定，不在本計劃範圍內。
- 本計劃不含實際修 bug 或加重試機制、也不含驗證「已知程式碼脈絡」段落提出的等待預算假設——那些屬於本 Issue 完成後，依 Task 5 結論另開的後續工作。
