# `epic-46-writing-mode-autodetect` （缺陷）排版方向自動偵測只看書本第一個 CSS

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-46-writing-mode-autodetect/`
**關聯 PRD 章節：** FR-06、FR-10

## 背景

《蘇東坡新傳》的直排宣告寫在第二個 CSS 檔（`-epub-`／`-webkit-writing-mode`），「採用書籍排版」模式下被判定為橫排，但畫面實際呈現直排。`main.js` 的 `detectedBookWritingMode` 只判讀 transformTarget 攔截到的「第一個」`text/css` 資源。使用者已手動指定直排的書不受影響。

範圍外：「直排單欄換章節偶爾變雙欄」（預讀章節捕捉到過時排版）已由 PR #272 修復並通過真機驗證，不屬於本 Epic；開書時的暫態本身沒有消除（已決議不處理）。

## 開發記錄

**2026-09-24 `/grill-with-docs`（`/grilling`＋`/domain-modeling`）完成 1 輪 8 題 Discovery**，查證後補充三項 `epics.md` 未記載的事實：

1. `WRITING_MODE_DECLARATION_RE` 的 `(?:^|[^-])(?:-epub-)?writing-mode` 在結構上就不可能匹配 `-webkit-writing-mode`（`webkit-` 以 `-` 結尾），即使宣告放在第一個 CSS 也會漏判；舊式 `tb-rl` 也不支援。
2. 「第一個 CSS」取決於開書時先載入哪個 section，也就是會隨閱讀位置改變：同一本書從不同章節重新開啟，偵測結果可能不同。
3. XHTML 內嵌的 `<style>` 和 `style=""` 完全沒有被掃描。

**決策**：

- 用詞統一為「排版方向」，Epic 標題中的「書寫方向」一併更正。`CONTEXT.md` 新增「排版方向」和「偵測排版方向」兩個詞條。
- 偵測訊號採用全書所有外部 CSS、XHTML 內嵌樣式，以及 OPF `primary-writing-mode`。**不採用** `page-progression-direction`，因為阿拉伯文等由右至左的橫排書籍同樣標示為 rtl。PRD FR-06 的措辭需改為與 `CLAUDE.md` 一致。
- Regex 擴充支援 `-webkit-` 前綴，以及舊式的 `tb-rl`／`tb`。
- 開書時先預掃 manifest，在第一次渲染前定案，確保結果與閱讀位置無關。
- 衝突規則：全書任一處出現直排宣告就判定為直排；誤判時由使用者用「強制橫排」修正。
- 驗證方式：先用 Puppeteer harness 的合成 fixture 重現並寫成回歸場景，再用真書在真機上確認。
- 流程：不走完整 SDD（design／spec／issues），改用 `diagnosing-bugs`＋TDD 直接修，只保留單一實作計畫 `plans/plan-issue-1.md`。
- 偵測結果不持久化（YAGNI）。

下一步：審查 `plans/plan-issue-1.md`。

**2026-09-24 `/superpowers:receiving-code-review` 完成計畫審查修訂**（`reviews/review-plan-issue-1.md`，建議修正後執行，0 Critical／3 Important／4 Minor）。7 項都經過查證，Regex 行為另用 Node 實測確認。

- I-1／I-3／M-1／M-2／M-4：採納。其中 I-1 審查所附的「EPUB 3 標準寫法」依據不正確，但容錯支援沒有成本，仍然採納；M-1 審查舉的例子實際上不會漏判，但改寫法沒有成本，仍然採納。
- I-2：採納問題本身，但不採用審查建議的 Regex。建議的 `[^"']*` 會漏判「雙引號內含單引號」的 `style` 屬性，已實測重現；改為依引號種類分成兩個分支。
- M-3：維持不支援 `-ms-`。判準更正為「偵測結果要跟 Chromium WebView 實際渲染一致」：`tb-rl` 在 Chromium 有效，`-ms-` 沒有作用。

Harness 案例由 5 個增為 7 個（新增 C-2、D-2），細節見計畫的「審查修訂紀錄」。

**2026-09-24 Task 1 — 排版方向自動偵測改為全書預掃（紅燈已重現）**

Harness `scenario-writing-mode-autodetect.mjs` 7 案例在修改前全部紅燈（符合預期）：

- A～D-2：舊程式漏判（回報 `horizontal`，預期 `vertical`）
- E：舊程式誤判（註解內的 `writing-mode: vertical-rl` 被當成有效宣告，回報 `vertical`，預期 `horizontal`）

診斷數值（案例 A，第二個 CSS `+ -webkit-` + 內層元素對應《蘇東坡新傳》）：

- **修改前**：`html=horizontal-tb body=horizontal-tb .main=vertical-rl columnWidth=528px`
  - 解讀：`html/body` 被覆蓋成橫排，但內層 `.main` 仍為 `vertical-rl`，外層與內層的排版方向不一致，也就是「橫排外框包直排內容」的錯位。
- **修改後**：`html=vertical-rl body=vertical-rl .main=vertical-rl columnWidth=528px`
  - 解讀：三者皆為 `vertical-rl`，外層與內層方向一致。
- 註：修改前後 `columnWidth` 都是 528px，這個數值本身看不出差異，真正的差別在 `html`／`body` 的 writing-mode（2026-09-25 程式審查 M-1 更正原本「以橫排欄寬排直排內容」的解讀）。

**2026-09-24 Task 2～3 — 實作 `detectBookWritingMode()`、文件同步**（commit `04369a18`、`4dc8f1ff`）

以下結果為 2026-09-25 程式審查時在暫存 worktree 實測：

- Step 5：場景 7/7 PASS。
- Step 6 變異驗證：把 `openBook()` 的預掃呼叫註解掉後，A～D-2 共 6 案例回到 FAIL，E 仍 PASS，與計畫預期一致。
- Step 7：`run-all.mjs` 全部 PASS；`check_foliate_es_compat.js` 乾淨。

**2026-09-25 程式審查修訂**（`reviews/review-code-issue-1.md`，修正後可合併，0 Critical／2 Important／5 Minor，全數採納）

- I-1：`book.loadText()` 遇到 manifest 有列、zip 內缺檔的項目時會同步回傳 `null`，導致 `.catch` 丟 TypeError、整個預掃中斷。新增 `safeLoadText()` 包進 Promise 鏈，單項失敗只跳過該項；新增案例 F。
- I-2：本紀錄格式與「下一步」更正。
- M-1：上方診斷數值解讀更正。
- M-2：使用者手動覆寫時略過預掃（預掃結果在覆寫時從未傳到 Dart，屬多餘成本）；計畫「需人類確認的設計決定」#2 同步更正。
- M-3：內嵌 `style` 屬性限定出現在標籤內，正文文字「style = "…"」不再被誤判；新增反例 G。
- M-4：Regex 數值結尾由 `\b` 改為 `(?![\w-])`，非法值 `tb-lr` 不再誤中 `tb`；新增反例 H。
- M-5：harness README 補回檔尾空行、場景說明更新為 10 案例；計畫 Task 1～3 checkbox 勾選。
- 驗證：以修訂前的 `main.js` 跑新場景，F／G／H 三案例 FAIL；修訂後 10/10 PASS。`run-all.mjs` 全部 PASS、`check_foliate_es_compat.js` 乾淨。另以臨時探針確認覆寫為 `horizontal`／`vertical` 時開書正常，且 `onPageRendered` 回報覆寫值。

**2026-09-25 Task 4 — 真機驗證通過**（AiPaper Reader C，Android 16，WebView Chrome 152）

- Step 1～3：人類確認全部通過。《蘇東坡新傳》在「採用書籍排版」下為直排，版面、分欄與翻頁方向正常；從書本中段關閉後重開仍為直排；橫排 EPUB 與 TXT 合成書沒有誤判。
- Step 4：暫時在 `openBook()` 的預掃前後加上 `performance.now()` 計時（commit `2e96a3be`），量完後已移除。預掃耗時如下，最壞約 250ms，相對於 E-Ink 裝置建立 WebView 到開始預掃的 0.8～3.8 秒佔比不大，維持 `INLINE_STYLE_SCAN_LIMIT = 20`：

| 書籍 | 預掃耗時 | 判定 |
|---|---|---|
| 《蘇東坡新傳》（直排 EPUB，掃到 CSS 即提早結束） | 66.1ms | vertical |
| 《飢餓遊戲Ⅰ 飢餓遊戲》（TXT 合成書，約 355KB） | 40.4ms | horizontal |
| 《AI世代的創意教養》（橫排 EPUB，需掃完全部 CSS 與前 20 章） | 249.6ms | horizontal |

- 附帶發現：診斷日誌中出現兩筆「openBook 失敗: ResizeObserver loop completed with undelivered notifications」，其中一筆發生在使用者手動覆寫（不會預掃）的情況，確認與本 Epic 無關，是 `globalErrorCaptureJs` 既有的誤報，已登錄為 Backlog `epic-47-resize-observer-false-error`。

**2026-09-25 PR #273 已合併進 `main`**（merge commit `9600d5fd`）。本 Epic 只有 Issue 1，全數完成。

下一步：依 SDD 流程歸檔。
