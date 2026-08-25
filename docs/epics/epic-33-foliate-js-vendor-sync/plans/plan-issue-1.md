# Epic 33 Issue 1：同步 7 個 vendored 檔案至 `c09f06d`＋補回 ADR 0024 密度校正 patch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 7 個已釘定 vendored 檔案（`paginator.js`／`epub.js`／`fixed-layout.js`／`view.js`／`overlayer.js`／`epubcfi.js`／`comic-book.js`）整份覆蓋為上游 `readest/foliate-js` commit `c09f06d` 版本，補回整份覆蓋會移除的 ADR 0024 密度校正 patch（`paginator.js`／`view.js` 各一小段），並依既有 SOP 完成 ES 相容性掃描、觸控 Harness 自動化、Bridge 對齊檢查，確保 `flutter analyze`／`flutter test` 零回歸。

**Architecture:** 7 檔整份取代，不手動修改其餘內容（ADR 0011）；取代後立即補回 ADR 0024（`docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`）在 `paginator.js`／`view.js` 兩個檔案內的手動 patch——這是這兩個檔案在 ADR 0011「不修改 vendored 檔案」原則上經正式決策通過的唯一例外，整份覆蓋必然會移除它，須立即補回，不能等到後續工單才做（觸控 Harness 會載入真實 `main.js`／`view.js` 執行真實 JS，若缺這個 patch，`window.applyPreferences()` 呼叫 `view.clearLocationDensity()` 會直接拋出例外，導致 Harness 100% 逾時失敗，見規劃階段審查發現）。`progress.js` 也帶有 ADR 0024 的另一半 patch，但這次上游沒有變動它，不在本工單同步範圍內，不需處理。Discovery 階段已用 GitHub API 確認同步範圍（`6c6a491`→`c09f06d`）只有這 7 個釘定檔案有變動，其餘 5 個釘定檔案（`progress.js`／`text-walker.js`／`mobi.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js`）逐位元組相同，本工單不觸碰；也不觸碰專案自建的 `main.js`／`index.html`。取代並補回 patch 後依序執行「ES 相容性掃描 → 觸控 Harness 自動化 → Bridge 對齊檢查 → flutter analyze/test」四層驗證，任何一層失敗都要先處理完才能進到下一層。

**Tech Stack:** Node.js（`check_foliate_es_compat.js` 靜態掃描腳本、`app/tool/foliate_touch_harness/` Puppeteer 回歸測試）、curl（下載上游檔案）、Flutter（`flutter analyze`／`flutter test`）。本計劃全部指令一律透過 **Bash 工具（Git Bash）** 執行，不使用 PowerShell 工具／cmd.exe。

**Spec:** `docs/epics/epic-33-foliate-js-vendor-sync/design.md`（「整體機制」「測試策略」）；`docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`；工單描述見 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` Issue 1。

## Global Constraints

- **執行環境為 Windows，本計劃所有指令一律使用 Bash 工具（Git Bash）執行，不要改用 PowerShell 工具或 cmd.exe。** 規劃階段已在這台機器上實際下載過全部 7 個檔案、跑過 `git diff --stat` 與 ES 相容性掃描，全部正常運作。
- 只整份覆蓋這 7 個檔案，一個位元組都不手動修改上游內容本身（ADR 0011）：`paginator.js`／`epub.js`／`fixed-layout.js`／`view.js`／`overlayer.js`／`epubcfi.js`／`comic-book.js`。**唯一例外**是 Task 2 依 ADR 0024 在 `paginator.js`／`view.js` 補回的那兩小段 patch——這是已正式採納的架構決定，不是隨意修改。
- 其餘 5 個釘定檔案（`progress.js`／`text-walker.js`／`mobi.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js`）保持不動，不下載、不覆蓋、不修改。`progress.js` 雖然也帶有 ADR 0024 的另一半 patch（`recordDensity`/`clearDensity`/`#density` Map），但這次上游沒有變動它，維持原樣即可，不需要補任何東西。
- 不修改 `index.html`／`main.js`，除非 Task 5 的 Bridge 對齊檢查真的發現簽章不符（依規劃階段查證，預期不會發生）。
- 若 Task 3 的 ES 相容性掃描觸發需要補 polyfill：僅能在 `_esCompatPolyfillJs`（`app/lib/reader/foliate_reader_view.dart`）補，硬性規範——① 僅在 `if (!TargetAPI)` 缺席時才定義，不可覆寫瀏覽器原生實作；② 嚴禁 ES2021+ 語法糖（`??=`／`||=`／`&&=`／可選鏈 `?.`／標籤模板等），本體須為 ES5/ES2020 相容語法。規劃階段已用下載到的 7 個檔案（含 Task 2 補回的 patch，皆為既有 ES5/ES2020 語法，不引入新的較新 API）實際跑過這支掃描工具，結果是**乾淨（結束碼 0）**，預期本工單不會觸發這個分支。
- 本工單**不**進行真機測試（Issue 2 的範圍），也**不**處理版本紀錄文件更新（`foliate_js_sync_update_strategy.md`／`docs/epics.md`，同樣是 Issue 2 的範圍）。

---

### Task 1：下載並替換 7 個 vendored 檔案

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/paginator.js`
- Modify: `app/android/app/src/main/assets/foliate/epub.js`
- Modify: `app/android/app/src/main/assets/foliate/fixed-layout.js`
- Modify: `app/android/app/src/main/assets/foliate/view.js`
- Modify: `app/android/app/src/main/assets/foliate/overlayer.js`
- Modify: `app/android/app/src/main/assets/foliate/epubcfi.js`
- Modify: `app/android/app/src/main/assets/foliate/comic-book.js`

**Interfaces:** 無（vendored 檔案，無對外 Dart/Flutter 介面變動於本 Task；Task 5 才驗證公開介面）。

- [x] **Step 1: 記錄替換前的基準行數**

```bash
cd app/android/app/src/main/assets/foliate
wc -l paginator.js epub.js fixed-layout.js view.js overlayer.js epubcfi.js comic-book.js
```

Expected（目前釘定版本 `6c6a491`，規劃階段已實測）：
```
   3782 paginator.js
   1314 epub.js
   1649 fixed-layout.js
    707 view.js
    429 overlayer.js
    369 epubcfi.js
    140 comic-book.js
```

若任何數字不符，代表工作目錄的釘定版本已被其他變更動過，先停下來確認原因，不要繼續本工單。

- [x] **Step 2: 下載上游 `c09f06d` 版本並整份覆蓋**

```bash
for f in paginator.js epub.js fixed-layout.js view.js overlayer.js epubcfi.js comic-book.js; do
  curl -sS --retry 3 --retry-delay 2 -o "$f" "https://raw.githubusercontent.com/readest/foliate-js/c09f06d/$f"
done
echo "全部下載完成，結束碼: $?"
```

Expected：結束碼 `0`，不輸出任何錯誤訊息（`--retry 3` 是這個環境對 `raw.githubusercontent.com` 偶爾連線被重置的既有對策）。

- [x] **Step 3: 驗證下載內容不是錯誤頁面、且行數符合預期**

```bash
for f in paginator.js epub.js fixed-layout.js view.js overlayer.js epubcfi.js comic-book.js; do
  echo "== $f =="
  head -c 60 "$f"
  echo ""
done
wc -l paginator.js epub.js fixed-layout.js view.js overlayer.js epubcfi.js comic-book.js
```

Expected：每個檔案 `head` 印出的開頭是合法 JavaScript（`import`／`const` 開頭這類程式碼，**不是** `<!DOCTYPE html>` 或 `404: Not Found`）。行數（規劃階段已實際下載驗證過，此時尚未補回 Task 2 的 patch）：
```
   3918 paginator.js
   1367 epub.js
   1820 fixed-layout.js
    704 view.js
    437 overlayer.js
    369 epubcfi.js
    154 comic-book.js
```

- [x] **Step 4: 確認 git diff 範圍只有這 7 個檔案**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain -- app/android/app/src/main/assets/foliate/
git diff --stat -- app/android/app/src/main/assets/foliate/
```

Expected：`git status` 只列出這 7 個檔案，沒有 `progress.js`／`text-walker.js`／`mobi.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js`／`main.js`／`index.html`。`git diff --stat` 結果（規劃階段已實測，行尾出現的 `LF will be replaced by CRLF` 是這個 repo 既有的 `core.autocrlf=true` 正常提示，不是錯誤，可忽略）：
```
 .../foliate/comic-book.js      |  16 +-
 .../foliate/epub.js            |  63 +++-
 .../foliate/epubcfi.js         |   4 +-
 .../foliate/fixed-layout.js    | 327 ++++++++++++++++-----
 .../foliate/overlayer.js       |   8 +
 .../foliate/paginator.js       | 176 +++++++++--
 .../foliate/view.js            |  21 +-
 7 files changed, 497 insertions(+), 118 deletions(-)
```
（確切的欄寬/省略符號顯示可能因終端機寬度略有差異，重點是 7 個檔案、497 insertions/118 deletions 這個總數應該一致。這個數字還沒算進 Task 2 要補的 patch。）

- [x] **Step 5: 逐檔核對確實含有目標 commit 才會出現的內容，排除誤下載到舊版/其他 commit 的可能**

```bash
grep -n "subpixelOffset" app/android/app/src/main/assets/foliate/paginator.js
grep -n "async loadHref(href, base, parents = \[\])" app/android/app/src/main/assets/foliate/epub.js
grep -n "scroll-direction" app/android/app/src/main/assets/foliate/fixed-layout.js
grep -n "#hasSelection()" app/android/app/src/main/assets/foliate/view.js
grep -n "rt, rp, rtc, \[cfi-inert\]" app/android/app/src/main/assets/foliate/overlayer.js
grep -n "^export const toString\|^export const buildRange" app/android/app/src/main/assets/foliate/epubcfi.js
grep -n "segment by segment" app/android/app/src/main/assets/foliate/comic-book.js
```

Expected：7 個 grep 都至少找到 1 處符合（`paginator.js` 的 `subpixelOffset` 應該找到 3 處：`#subpixelOffset`／getter／setter；`epubcfi.js` 應該找到 2 處 `export const`）。這些都是規劃階段對照 diff 找出的、只有 `c09f06d` 範圍內新 commit 才會出現的內容。

---

### Task 2：補回 ADR 0024 密度校正 patch（`paginator.js`／`view.js`）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/paginator.js`（Task 1 下載後的版本，約第 3416 行附近）
- Modify: `app/android/app/src/main/assets/foliate/view.js`（Task 1 下載後的版本）

**Interfaces:**
- Consumes: Task 1 替換後的純淨版 `paginator.js`／`view.js`；`progress.js`（本次未變動）既有的 `recordDensity(index, contentPages)`／`clearDensity()` 方法。
- Produces: `paginator.js` 的 `relocate` 事件 `detail` 物件多帶 `contentPages` 欄位；`view.js` 新增 `clearLocationDensity()` 公開方法，供 `main.js` 第 175 行 `view.clearLocationDensity()` 呼叫；`view.js` 的 `#onRelocate()` 消費 `contentPages` 並回饋給 `progress.js`。

**背景**：`docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`（已採納）讓 `paginator.js`／`view.js`／`progress.js` 三個檔案協作，把流式 EPUB 已渲染 section 的真實視覺頁數回饋給頁碼估算。Task 1 整份覆蓋 `paginator.js`／`view.js` 為純淨上游版本後，這兩個檔案裡的 ADR 0024 patch 會消失，必須立即補回——尤其 `view.js` 的 `clearLocationDensity()` 方法，`main.js` 第 175 行的 `window.applyPreferences()` 無條件呼叫它，若缺席會直接拋出 `TypeError`，讓 Task 4 的觸控 Harness 在第一次 `relocate` 事件就崩潰逾時。

- [x] **Step 1: 在 `paginator.js` 補回 `detail.contentPages` 賦值**

先確認目前（Task 1 下載後）的確切上下文：

```bash
grep -n "detail.size = textPages > 0 ? this.columnCount / textPages : 1" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：找到 1 處，約第 3416 行。

用 Edit 工具，把：

```js
            detail.fraction = textPages > 0 ? Math.max(0, Math.min(1, localColumn / textPages)) : 0
            detail.size = textPages > 0 ? this.columnCount / textPages : 1
            if (reason === 'container-scroll' && localPage === 0) return
```

改成：

```js
            detail.fraction = textPages > 0 ? Math.max(0, Math.min(1, localColumn / textPages)) : 0
            detail.size = textPages > 0 ? this.columnCount / textPages : 1
            detail.contentPages = textPages
            if (reason === 'container-scroll' && localPage === 0) return
```

（只插入 `detail.contentPages = textPages` 這一行，縮排比照同一個區塊其餘行，前後其他行不變。）

- [x] **Step 2: 驗證 Step 1 的插入**

```bash
grep -n "detail.contentPages = textPages" app/android/app/src/main/assets/foliate/paginator.js
node --check app/android/app/src/main/assets/foliate/paginator.js
echo "syntax check exit code: $?"
```

Expected：`grep` 找到 1 處；`node --check` 結束碼 `0`（純語法檢查，不執行程式，確認插入沒有打錯字元導致語法錯誤）。

- [x] **Step 3: 在 `view.js` 補回 `#onRelocate()` 的 `contentPages` 處理**

先確認目前（Task 1 下載後）的確切上下文：

```bash
grep -n "#onRelocate({ reason, range, index, fraction, size }) {" app/android/app/src/main/assets/foliate/view.js
```

Expected：找到 1 處。

用 Edit 工具，把：

```js
    #onRelocate({ reason, range, index, fraction, size }) {
```

改成：

```js
    #onRelocate({ reason, range, index, fraction, size, contentPages }) {
        // epic-26-architecture-hardening Issue 11：只有非捲動、已渲染出精確
        // 視覺頁數的情境才會帶 contentPages，用它回饋給 SectionProgress 做
        // 密度校正；捲動模式或尚未渲染完成時 contentPages 為 undefined，
        // 不記錄（維持該 section 原本的位元組估計）。
        if (contentPages) this.#sectionProgress?.recordDensity(index, contentPages)
```

- [x] **Step 4: 在 `view.js` 補回 `clearLocationDensity()` 方法**

先確認目前（Task 1 下載後）的確切上下文：

```bash
grep -n "getProgressOf(index, range) {" app/android/app/src/main/assets/foliate/view.js
```

Expected：找到 1 處。

用 Edit 工具，在這一行**之前**插入：

```js
    // epic-26-architecture-hardening Issue 11：排版設定變更時，main.js 的
    // window.applyPreferences() 呼叫這個方法清空已記錄的密度校正資料——
    // 字級/行距/邊距/欄數/螢幕方向/直橫排改變後，舊密度全部失真。
    clearLocationDensity() {
        this.#sectionProgress?.clearDensity()
    }
    getProgressOf(index, range) {
```

（也就是把 `clearLocationDensity() { ... }` 整段方法插在 `getProgressOf` 前面，`getProgressOf` 本身內容不變。）

- [x] **Step 5: 驗證 Step 3-4 的插入**

```bash
grep -n "contentPages" app/android/app/src/main/assets/foliate/view.js
grep -n "clearLocationDensity" app/android/app/src/main/assets/foliate/view.js
node --check app/android/app/src/main/assets/foliate/view.js
echo "syntax check exit code: $?"
```

Expected：`contentPages` 至少找到 4 處（方法簽章 1 處＋註解 3 行皆含中文說明不含這個字串，實際上英文字串 `contentPages` 只會在簽章與 `if (contentPages)` 那行出現，共 2 處，這裡抓寬鬆一點確認不是 0）；`clearLocationDensity` 找到 1 處（方法定義本身；`main.js` 那邊的呼叫端不算在這個檔案內）；`node --check` 結束碼 `0`。

- [x] **Step 6: 確認 `progress.js` 沒有被誤動**

```bash
git status --porcelain -- app/android/app/src/main/assets/foliate/progress.js
```

Expected：無任何輸出（`progress.js` 不在本次同步範圍內，Task 1/2 都不應該碰到它）。

---

### Task 3：ES 相容性掃描

**Files:**
- 無新增/修改檔案（先執行掃描確認結果；若結果非 0，回頭在本 Task 內修改 `app/lib/reader/foliate_reader_view.dart` 與 `app/test/reader/foliate_reader_view_test.dart`，見下方 Step 2 的條件分支）。

**Interfaces:**
- Consumes: Task 1 替換、Task 2 補回 patch 後的 7 個檔案。
- Produces: 若本 Task 觸發 polyfill 補強，`_esCompatPolyfillJs` 常數會增加新的 `if (!X) { ... }` 區塊，供 Task 6 的 `flutter test` 驗證。

- [x] **Step 1: 執行掃描工具**

```bash
node app/tool/check_foliate_es_compat.js
echo "exit code: $?"
```

Expected：結束碼 `0`，印出「乾淨」訊息（規劃階段已用下載到的 7 個檔案＋Task 2 要補的 patch 內容實際跑過，結果乾淨——Task 2 補的 patch 只用了既有的 `?.`（可選鏈）語法，這在既有 `paginator.js`／`view.js` 大量既有用法中本來就存在，不是新引入的風險，掃描工具的 `RISKY_APIS` 清單本來就不掃可選鏈語法糖，只掃特定 API 方法名稱，預期不會進到下方 Step 2 的條件分支）。

- [x] **Step 2（僅當 Step 1 結束碼非 0 時才執行）：依腳本輸出的清單補齊 polyfill**

若 Step 1 結束碼不是 `0`，腳本會印出每個未防護 API 的名稱、所在檔案/行號、以及該 API 所需的最低 Chromium 版本。針對輸出清單中的每一項：

1. 到 `app/lib/reader/foliate_reader_view.dart` 的 `_esCompatPolyfillJs` 常數內，比照既有 6 個 polyfill 的寫法（`if (!Object.groupBy) { Object.groupBy = function (...) {...}; }` 這種「僅在缺席時定義」的結構）新增一個對應區塊，本體只能用 ES5/ES2020 相容語法（不可用 `??=`／`||=`／`&&=`／`?.`／標籤模板）。
2. Polyfill marker 字串（腳本比對用，例如 `'Array.prototype.toSorted'`）必須實際出現在新增程式碼的內容或緊鄰的註解中。
3. 到 `app/test/reader/foliate_reader_view_test.dart`（搜尋既有 `expect(script.source, contains('Object.groupBy'))` 這類斷言取得寫法範例）新增一則對應的 `expect(script.source, contains('<新 marker 字串>'))` 斷言。
4. 重新執行 `node app/tool/check_foliate_es_compat.js`，確認結束碼變為 `0`。

---

### Task 4：觸控 Harness 自動化回歸

**Files:**
- 無修改（純測試執行，讀取 Task 1/2 處理後的 `paginator.js`／`view.js`／`epub.js` 與既有未變動的 `main.js`）。

**Interfaces:**
- Consumes: Task 1/2 處理後的 vendored 檔案；`app/tool/foliate_touch_harness/`（`epic-31` Issue 1 建立，內含 `run-all.mjs` 與 4 個情境腳本）。
- Produces: 無檔案異動；若失敗，需回到 Task 1/2 確認是否誤下載、patch 補錯，不在本工單自行修改 `main.js`。

- [x] **Step 1: 安裝依賴（第一次執行需要，會自動下載 Chromium）**

```bash
cd app/tool/foliate_touch_harness
npm install
```

Expected：安裝成功，結束碼 `0`。若這台機器先前已執行過 `epic-31` Issue 1/2 的驗證、`node_modules` 已存在，這步驟會很快跳過大部分下載。

- [x] **Step 2: 執行全部情境**

```bash
node run-all.mjs
```

Expected：4 個情境（`scenario-epic25-issue4-fast-tap.mjs`／`scenario-issue10-selection-release-guard.mjs`／`scenario-issue11-hittest-existing-highlight.mjs`／`scenario-cross-mechanism-tap-boundary.mjs`）全數 PASS，比照 `epic-31` Issue 1/2 已確立的基準線。**若在這一步撞到 `onPageRendered` 逾時或 `TypeError: view.clearLocationDensity is not a function`，代表 Task 2 的 patch 沒有補對（規劃階段審查已確認這是這個 harness 唯一已知會踩到 ADR 0024 缺口的地方）——回頭檢查 Task 2 Step 1-5 是否每一步都符合 Expected，不要在這裡繼續往下做。**

若排除 Task 2 patch 問題後仍有情境 FAIL：這代表 Task 1 替換進來的新版 `paginator.js`（7 個新 commit，多為觸控/捲動相關修法）與 `epic-31` Issue 2 重構的 `TouchIntentClassifier` 有實際行為衝突，**不要自行修改 `main.js` 或 harness 腳本來讓測試通過**，停下來記錄實際失敗的情境與錯誤訊息，回報給人類決定如何處理。

- [x] **Step 3: 回到 repo 根目錄**

```bash
cd "$(git rev-parse --show-toplevel)"
```

---

### Task 5：Bridge 公開方法簽章對齊檢查

**Files:**
- 無修改（純驗證，讀取 Task 1/2 處理後的 `paginator.js`／`fixed-layout.js`／`view.js` 與既有未變動的 `main.js`）。

**Interfaces:**
- Consumes: Task 1/2 處理後的 7 個檔案；既有未變動的 `app/android/app/src/main/assets/foliate/main.js`。
- Produces: 本 Task 若一切符合預期，不產生任何檔案變更，直接進入 Task 6。

- [x] **Step 1: 核對 `paginator.js` 的 `next`/`prev`/`goTo` 公開方法簽章**

```bash
grep -n "async next(\|async prev(\|async goTo(" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：三個方法都存在，簽章分別為 `async goTo(target)`（約第 3756 行）、`async prev(distance)`（約第 3827 行）、`async next(distance)`（約第 3830 行，Task 2 補的 patch 只在更前面的 `#onRelocate` 一帶插入 1 行，不影響這幾個方法的行號太多，若有小幅位移屬正常）——與替換前完全相同的簽章。`main.js` 實際呼叫的 `view.next()`／`view.prev()`／`view.goToFraction()`／`view.goTo()`（`main.js` 第 350/354/358/370 行）都是透過 `view.js` 轉呼叫這三個方法，簽章不變代表這幾條路徑不受影響。

- [x] **Step 2: 核對 `relocate` 事件 payload 建構邏輯起點**

```bash
grep -n "const detail = { reason, range, index }" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：找到這一行（新版行號約在 3396 附近）。`{ reason, range, index }` 這個結構與替換前完全相同，`detail.fraction`／`detail.size`／Task 2 補回的 `detail.contentPages` 依序賦值。`view.js` 的 `#onRelocate()` 消費這個 payload、組出 `main.js` 實際監聽的 `{ cfi, fraction, location, index, head, tail }` 欄位，結構起點不變代表下游欄位也不會變。

- [x] **Step 3: 核對 `no-swipe`／`turn-gesture-left-inset` 屬性讀取仍存在**

```bash
grep -n "hasAttribute('no-swipe')\|turn-gesture-left-inset" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：`turn-gesture-left-inset` 找到 1 處（約第 2317 行）、`no-swipe` 找到 3 處（約第 2394/2805/2919 行），與替換前同樣是 1+3 處讀取。`main.js` 第 1011 行 `view.renderer.setAttribute('no-swipe', '')` 這個既有設定不需要更動；`turn-gesture-left-inset` 真機行為驗證留給 Issue 2，本 Task 只確認程式碼層級的讀取邏輯還在。

- [x] **Step 4: 確認 `main.js` 沒有設定/呼叫上游新暴露的能力**

```bash
grep -n "scroll-direction\|turn-gesture-left-inset\|subpixelOffset" app/android/app/src/main/assets/foliate/main.js
```

Expected：無任何輸出（`grep` 結束碼非 0）。`design.md`「非目標」已明訂本次不啟用 `fixed-layout.js` 的水平捲動模式（`scroll-direction` 屬性）與 `paginator.js` 的 sub-pixel scroll offset（`subpixelOffset` 屬性），本步驟只需確認「確實沒有設定/存取」，不需要新增邏輯。

- [x] **Step 5: 核對 `view.clearLocationDensity()` 呼叫端與 Task 2 補回的方法對得上**

```bash
grep -n "clearLocationDensity" app/android/app/src/main/assets/foliate/main.js
```

Expected：找到 1 處（約第 175 行，`view.clearLocationDensity()`），跟 Task 2 Step 4 補回的方法名稱完全一致（大小寫、無多餘空格）。

- [x] **Step 6: 記錄 `fd91451`（連續捲動時定期發射 `relocate`）的觀察待辦**

不需要在本 Task 執行任何指令——這一項無法透過靜態檢查或 `flutter test` 驗證，留待 Issue 2 真機驗收時，順便觀察快速連續翻頁／捲動時 `onLocatorChanged` 橋接通訊是否流暢無卡頓。本 Task 只需確認 `main.js` 的 `onLocatorChanged` handler 註冊仍然存在：

```bash
grep -n "'onLocatorChanged'" app/android/app/src/main/assets/foliate/main.js
```

Expected：找到 1 處（約第 656 行）。

若 Step 1-5 任一步驟結果與 Expected 不符，停下來記錄實際差異，不要自行決定如何處理——回報給人類決定是否需要調整 `main.js` 或視為需要重新評估同步範圍。

---

### Task 6：全面回歸驗證、提交、更新工單狀態

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/issues.md`（Issue 1 的 `**Status:**` 行與完成摘要）

**Interfaces:** 無。

- [x] **Step 1: `flutter analyze`**

```bash
cd app && flutter analyze
```

Expected：「No issues found!」（cwd 需在 `app/`）。

- [x] **Step 2: `flutter test`**

```bash
flutter test
```

Expected：全數通過。測試總數應與 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 3 記錄的最近基準線 **1693 項**一致（若 Task 3 的 Step 2 條件分支有被觸發、新增了 polyfill 斷言測試，總數可能略增，屬預期之內，記下實際數字即可）。

若在 Windows 上因暫存目錄檔案被多個測試 worker 同時存取而失敗，改用單一 worker 重跑一次：

```bash
flutter test --concurrency=1
```

這只是失敗時的備援手段，不是預設做法。

- [x] **Step 3: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/android/app/src/main/assets/foliate/paginator.js \
        app/android/app/src/main/assets/foliate/epub.js \
        app/android/app/src/main/assets/foliate/fixed-layout.js \
        app/android/app/src/main/assets/foliate/view.js \
        app/android/app/src/main/assets/foliate/overlayer.js \
        app/android/app/src/main/assets/foliate/epubcfi.js \
        app/android/app/src/main/assets/foliate/comic-book.js
git commit -m "$(cat <<'EOF'
chore(epic-33): 同步 7 個 vendored 檔案至上游 c09f06d，補回 ADR 0024 patch

整份覆蓋 paginator.js/epub.js/fixed-layout.js/view.js/overlayer.js/
epubcfi.js/comic-book.js 為 readest/foliate-js commit c09f06d。經
GitHub API 確認同步範圍只有這 7 個檔案變動，其餘 5 個釘定檔案逐位元組
相同，不需替換。

整份覆蓋會移除 paginator.js/view.js 內 ADR 0024（密度校正）的手動
patch，已立即補回：paginator.js 的 relocate 事件 detail 補回
contentPages 欄位；view.js 的 #onRelocate() 補回 contentPages 消費、
新增 clearLocationDensity() 方法。progress.js 這次未變動、不需處理。

ES 相容性掃描結束碼為 0；觸控 Harness（run-all.mjs）4 個情境全數 PASS；
Bridge 公開方法簽章（next/prev/goTo、relocate 事件 payload、no-swipe／
turn-gesture-left-inset 屬性讀取、clearLocationDensity 呼叫端）核對與
替換前一致；main.js 未設定/存取新暴露的 scroll-direction／
subpixelOffset。flutter analyze/test 零回歸。
EOF
)"
```

若 Task 3 觸發了 polyfill 補強，改用額外加上兩個檔案一起 `git add`：

```bash
git add app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
```

- [x] **Step 4: 更新工單狀態**

在 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` Issue 1 的 `**Status:** ready-for-agent` 那一行，改為記錄已完成，補一段簡短總結：ES 掃描結束碼（是否有觸發 polyfill 補強）、ADR 0024 patch 補回結果、觸控 Harness 4 情境是否全過、Bridge 對齊檢查結果、`flutter test` 實際測試總數、commit hash。

```bash
git add docs/epics/epic-33-foliate-js-vendor-sync/issues.md
git commit -m "docs(epic-33): 更新 Issue 1 狀態為已完成"
```

---

## Self-Review（撰寫計劃階段自我檢查）

- **Spec 覆蓋**：`design.md`「目標」第 1 項（同步 7 個檔案）→ Task 1；`ADR 0024` 密度校正 patch 保留 → Task 2（規劃審查發現後新增）；`design.md`「目標」第 2 項（ES 掃描／觸控 Harness／Bridge 對齊）→ Task 3/4/5；`issues.md` Issue 1「測試要求」→ Task 3 Step 1／Task 4 Step 2／Task 6 Step 1-2；「驗收標準」逐項對應 Task 1 Step 4-5、Task 2、Task 3、Task 4、Task 5、Task 6。無遺漏。
- **佔位符掃描**：全文未使用 TBD／TODO／「適當處理」等字眼；所有 grep／curl／flutter／`node --check` 指令皆為規劃階段實際核對過的真實指令與真實預期輸出；Task 2 的 patch 內容逐字對照規劃階段實際下載＋比對過的 diff 結果，不是憑印象重寫。
- **型別/簽章一致性**：`next`/`prev`/`goTo`、`relocate` payload 欄位（含新補回的 `contentPages`）、`no-swipe`／`turn-gesture-left-inset`／`scroll-direction`／`subpixelOffset`／`clearLocationDensity` 這些名稱在 Task 1 Step 5（下載驗證）、Task 2（補 patch）、Task 5（Bridge 對齊）三處出現，用詞與大小寫一致。
- **本輪審查修訂記錄**（依 `reviews/review-plan-issue-1.md`）：Critical #1（觸控 Harness 因缺 `clearLocationDensity` 必定崩潰）與 Important #1（ADR 0024 patch 應併入 Issue 1，不應留給獨立的 Issue 3）已採納，新增 Task 2 並全面調整後續 Task 編號；Critical #2（Task 1 Step 4 目錄跳轉多跳一層）已修正，改用 `cd "$(git rev-parse --show-toplevel)"`，其餘 `cd` 步驟一併比照修正（Minor #1）；Important #2（`view.js` 基準行數應為 708 非 707）**查證後不成立**，重新 `wc -l` 兩次結果皆為 707 行，維持原計畫數字不變；建議 2（`main.js` 加上 `?.` 防禦性呼叫）評估後**不採納**——Task 2 已從根因修復缺席的方法，沒有必要再疊加防禦性語法，且修改 `main.js` 超出本工單「只在簽章不符時才動 main.js」的既定邊界，避免無謂的範圍擴張。
