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

Harness 案例由 5 個增為 7 個（新增 C-2、D-2），細節見計畫的「審查修訂紀錄」。**2026-09-24 Task 1 — 排版方向自動偵測改為全書預掃（紅燈已重現）**

Harness `scenario-writing-mode-autodetect.mjs` 7 案例在修改前全部紅燈（符合預期）：

- A～D-2：舊程式漏判（回報 `horizontal`，預期 `vertical`）
- E：舊程式誤判（註解內的 `writing-mode: vertical-rl` 被當成有效宣告，回報 `vertical`，預期 `horizontal`）

診斷數值（案例 A，第二個 CSS `+ -webkit-` + 內層元素對應《蘇東坡新傳》）：

- **修改前**：`html=horizontal-tb body=horizontal-tb .main=vertical-rl columnWidth=528px`
  - 解讀：`html/body` 被覆蓋成橫排，但 `.main` 仍為 `vertical-rl`，Paginator 用橫排的欄寬（528px）去排直排內容，形成「橫排欄寬排直排內容」的錯位。
- **修改後**：`html=vertical-rl body=vertical-rl .main=vertical-rl columnWidth=528px`
  - 解讀：三者皆為 `vertical-rl`，Paginator 已在第一次渲染前以直排的欄寬／方向排版，不再出現「橫排欄寬排直排內容」的錯位。

下一步：執行 Task 2（實作 `detectBookWritingMode()` 並接線到 `openBook()`）。
