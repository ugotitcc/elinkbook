# Epic 32 Issue 2：同步 `paginator.js` 至 `6c6a491` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把釘定的 `app/android/app/src/main/assets/foliate/paginator.js` 整份覆蓋為上游 `readest/foliate-js` commit `6c6a491` 版本（合併 `f94b251`），並依既有 SOP 完成 ES 相容性掃描與 Bridge 對齊檢查，確保 `flutter analyze`／`flutter test` 零回歸。

**Architecture:** 單檔整份取代，不手動修改內容（ADR 0011）。上游這個 commit 只變動 `paginator.js` 一個檔案（Discovery 階段已用 GitHub API 確認，其餘 11 個釘定檔案逐位元組相同），所以本工單不觸碰 `view.js`／`epub.js` 等其他 vendored 檔案，也不觸碰專案自建的 `main.js`／`index.html`。取代後依序執行「ES 相容性掃描 → Bridge 公開方法簽章核對 → flutter analyze/test」三層驗證，任何一層失敗都要先處理完才能進到下一層。

**Tech Stack:** Node.js（`check_foliate_es_compat.js` 靜態掃描腳本）、curl（下載上游檔案）、Flutter（`flutter analyze`／`flutter test`）。本計劃全部指令一律透過 **Bash 工具（Git Bash）** 執行，不使用 PowerShell 工具／cmd.exe（見 Global Constraints）。

**Spec:** `docs/epics/epic-32-foliate-js-paginator-sync/design.md`（「整體機制」「先決條件」「測試策略」）；工單描述見 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 2。

## Global Constraints

- **執行環境為 Windows，本計劃所有 Task 的指令一律使用 Bash 工具（Git Bash）執行，不要改用 PowerShell 工具或 cmd.exe。** 規劃階段已在這台機器上實際用 Bash 工具驗證過 `curl --retry`／`grep -n`／`wc -l`／`head -c`／`git commit` 搭配 `<<'EOF'` heredoc 多行訊息全部正常運作（Issue 1 的多行 commit message 也是同一種寫法，`git log` 可查到已成功寫入），不需要另外改寫成 PowerShell 版本指令。
- 只整份覆蓋 `app/android/app/src/main/assets/foliate/paginator.js`，一個位元組都不手動修改（ADR 0011）。
- 其餘 11 個釘定檔案（`comic-book.js`／`construct-style-sheets-polyfill.js`／`epub.js`／`epubcfi.js`／`fixed-layout.js`／`mobi.js`／`overlayer.js`／`progress.js`／`text-walker.js`／`vendor/zip.js`／`view.js`）保持不動，不下載、不覆蓋。
- 不修改 `index.html`／`main.js`（本專案自建的橋接層），除非 Task 3 的 Bridge 對齊檢查真的發現簽章不符（依本計劃撰寫階段的查證，預期不會發生）。
- 若 Task 2 的 ES 相容性掃描觸發需要補 polyfill：僅能在 `_esCompatPolyfillJs`（`app/lib/reader/foliate_reader_view.dart`）補，硬性規範——① 僅在 `if (!TargetAPI)` 缺席時才定義，不可覆寫瀏覽器原生實作；② 嚴禁 ES2021+ 語法糖（`??=`／`||=`／`&&=`／可選鏈 `?.`／標籤模板等），本體須為 ES5/ES2020 相容語法。
- 本工單**不**處理 `docs/research/foliate_js_sync_update_strategy.md`／`docs/epics.md` 的 Pinned Commit 版本紀錄更新——那是 Issue 3「文件收尾」的範圍。`app/lib/reader/foliate_reader_view.dart:360` doc comment 內提到的舊 pinned commit 字串（`dd71f2be356563c16a23272686189fcfb45d0b82`）同樣不在本工單範圍內，不要順手修改。
- 本工單**不**進行真機測試（Issue 3 的範圍），也**不**同步到上游 HEAD，只鎖定 `6c6a491`。

---

### Task 1：下載並替換 `paginator.js`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/paginator.js`（整份覆蓋，來源為上游 raw 內容）

**Interfaces:** 無（vendored 檔案，無對外 Dart/Flutter 介面變動於本 Task）。

- [ ] **Step 1: 記錄替換前的基準行數**

```bash
wc -l app/android/app/src/main/assets/foliate/paginator.js
```

Expected: `3504`（目前釘定版本，`dd71f2b`）。若不是這個數字，代表工作目錄的釘定版本已被其他變更動過，先停下來確認原因，不要繼續本工單。

- [ ] **Step 2: 下載上游 `6c6a491` 版本並整份覆蓋**

```bash
curl -sS --retry 3 --retry-delay 2 -o app/android/app/src/main/assets/foliate/paginator.js "https://raw.githubusercontent.com/readest/foliate-js/6c6a491/paginator.js"
```

Expected: 指令結束碼為 `0`，不輸出任何錯誤訊息（`--retry 3` 是因為這個環境對 `raw.githubusercontent.com` 偶爾會有連線被重置的情形，規劃階段已實測需要加重試才穩定下載成功）。

- [ ] **Step 3: 驗證下載內容不是錯誤頁面、且行數符合預期**

```bash
head -c 200 app/android/app/src/main/assets/foliate/paginator.js
wc -l app/android/app/src/main/assets/foliate/paginator.js
```

Expected：`head` 印出的開頭是合法 JavaScript（例如 `const wait = ms => ...` 這類程式碼開頭，**不是** `<!DOCTYPE html>` 或 `404: Not Found` 這種錯誤頁面內容）；`wc -l` 結果為 `3782`（規劃階段已實際下載驗證過的行數，對應 design.md 記載的「兩個 commit 合併 +338/-55」淨變動）。

- [ ] **Step 4: 確認 git diff 範圍只有這一個檔案**

```bash
git status --porcelain
git diff --stat -- app/android/app/src/main/assets/foliate/
```

Expected：`git status` 只列出 `app/android/app/src/main/assets/foliate/paginator.js` 一個異動檔案；`git diff --stat` 也只顯示這一個檔案有變更，沒有動到 `view.js`／`epub.js` 等其餘 10 個釘定檔案或 `main.js`／`index.html`。

- [ ] **Step 5: 快速核對新版確實含有目標 commit 的觸控重寫內容**

```bash
grep -n "layeredGesture\|turn-gesture-left-inset\|#rejectLayeredGesture" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：至少能找到 `layeredGesture`（多處）、`turn-gesture-left-inset`（1 處）、`#rejectLayeredGesture`（至少 1 處定義）——這些是 design.md「`#touchState` 結構變動摘要」明確記載、只有 `6c6a491` 這個 commit 才會出現的新內容，確認下載到的確實是目標版本、不是誤下載到舊版或其他 commit。

---

### Task 2：ES 相容性掃描

**Files:**
- 無新增/修改檔案（先執行掃描確認結果；若結果非 0，回頭在 Task 2 內修改 `app/lib/reader/foliate_reader_view.dart` 與 `app/test/reader/foliate_reader_view_test.dart`，見下方 Step 2 的條件分支）。

**Interfaces:**
- Consumes: Task 1 已替換完成的 `app/android/app/src/main/assets/foliate/paginator.js`。
- Produces: 若本 Task 觸發 polyfill 補強，`_esCompatPolyfillJs` 常數（`app/lib/reader/foliate_reader_view.dart`）內容會增加新的 `if (!X) { ... }` 區塊，供 Task 4 的 `flutter test` 驗證。

- [ ] **Step 1: 執行掃描工具**

```bash
node app/tool/check_foliate_es_compat.js
echo "exit code: $?"
```

Expected：結束碼 `0`，印出「乾淨」訊息。

規劃階段已用下載到的副本手動核對過：新版 `paginator.js` 相對舊版新增的較新 API 用法只有 `.at(-1)`（2 處）與 `.findLastIndex(`（1 處，位於新增的 `landmarks` 相關邏輯），這兩者在目前 `_esCompatPolyfillJs`（`app/lib/reader/foliate_reader_view.dart` 第 68-150 行）已經分別有 `Array.prototype.at`／`Array.prototype.findLastIndex` 的 polyfill 定義與對應的 marker 字串，`check_foliate_es_compat.js` 的比對邏輯（`polyfillMarkers.some(marker => polyfillJs.includes(marker))`）會直接判定這兩個 API 已受防護、不會再列入 findings。其餘 `RISKY_APIS` 清單中的 API（`Object.hasOwn`／`toReversed`／`toSorted`／`toSpliced`／`.with(`／`Object.groupBy`／`Map.groupBy`／`Promise.withResolvers`／`isWellFormed`／`toWellFormed`／`structuredClone`／`Array.fromAsync`／`replaceAll`／`WeakRef`）在新版 `paginator.js` 中規劃階段也都沒有掃到新用法。因此本步驟預期結束碼為 `0`，不需要進到下方 Step 2 的條件分支。

- [ ] **Step 2（僅當 Step 1 結束碼非 0 時才執行）：依腳本輸出的清單補齊 polyfill**

若 Step 1 結束碼不是 `0`，腳本會印出每個未防護 API 的名稱、所在的 `paginator.js` 檔案/行號、以及該 API 所需的最低 Chromium 版本。針對輸出清單中的每一項：

1. 到 `app/lib/reader/foliate_reader_view.dart` 的 `_esCompatPolyfillJs` 常數（目前第 68-150 行）內，比照既有 6 個 polyfill 的寫法（`if (!Object.groupBy) { Object.groupBy = function (...) {...}; }` 這種「僅在缺席時定義」的結構）新增一個對應區塊，本體只能用 ES5/ES2020 相容語法（不可用 `??=`／`||=`／`&&=`／`?.`／標籤模板）。
2. Polyfill marker 字串（腳本比對用，例如 `'Array.prototype.toSorted'`）必須實際出現在新增程式碼的內容或緊鄰的註解中（比照既有 6 個 polyfill 皆是「方法賦值語句本身就包含該字串」的寫法，例如 `Array.prototype.at = function ...` 這行本身就含有 `Array.prototype.at`）。
3. 到 `app/test/reader/foliate_reader_view_test.dart`（`group('ES compat polyfill...')` 一帶，可搜尋既有 `expect(script.source, contains('Object.groupBy'))` 這類斷言取得寫法範例）新增一則對應的 `expect(script.source, contains('<新 marker 字串>'))` 斷言，涵蓋新補上的 polyfill。
4. 重新執行 `node app/tool/check_foliate_es_compat.js`，確認結束碼變為 `0`。

---

### Task 3：Bridge 公開方法簽章對齊檢查

**Files:**
- 無修改（純驗證，讀取 Task 1 替換後的 `paginator.js` 與既有 `view.js`／`main.js`，確認公開介面未變）。

**Interfaces:**
- Consumes: Task 1 替換後的 `app/android/app/src/main/assets/foliate/paginator.js`；既有未變動的 `app/android/app/src/main/assets/foliate/view.js`；既有未變動的 `app/android/app/src/main/assets/foliate/main.js`。
- Produces: 本 Task 若一切符合預期，不產生任何檔案變更，直接進入 Task 4。

- [ ] **Step 1: 核對 `paginator.js` 的 `next`/`prev`/`goTo` 公開方法簽章**

```bash
grep -n "async next(\|async prev(\|async goTo(" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：三個方法都存在，簽章分別為 `async next(distance)`、`async prev(distance)`、`async goTo(target)`——與替換前舊版（`dd71f2b`）完全相同的簽章（規劃階段已對照確認）。`renderer` 即為 `paginator.js` 這個自訂元素實例，`view.js`（本次未變動）的四個對外方法全部只是薄轉呼叫：`view.next(distance)`/`view.prev(distance)` 直接轉呼叫 `renderer.next(distance)`/`renderer.prev(distance)`；`view.goToFraction(frac)` 轉呼叫 `renderer.goTo({ index, anchor })`；`view.goTo(target)`（`main.js` 的 `window.jumpToLocator` 呼叫這個，即 design.md 所稱的 `goToCfi`）轉呼叫 `renderer.goTo(resolved)`。因此 `main.js` 實際用到的 `view.next()`／`view.prev()`／`view.goToFraction()`／`view.goTo()` 四條路徑，只要這裡核對的 `renderer.next`/`renderer.prev`/`renderer.goTo` 三個簽章不變，就全數不受影響。

- [ ] **Step 2: 核對 `relocate` 事件 payload 建構邏輯**

```bash
grep -n "const detail = { reason, range, index }" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：找到這一行（新版行號約在 3260 附近，僅供參考，行號本身不是驗證重點）。這是 `paginator.js` 內部 `relocate` 事件（`Renderer` 層級，非 `main.js` 直接監聽的那個）的 payload 起點，`{ reason, range, index }` 這個結構與替換前舊版完全相同，後續依 `this.scrolled` 分支補上的 `detail.fraction`／`detail.size` 邏輯也相同。`view.js`（本次未變動）的 `#onRelocate()` 會消費這個 payload、組出 `main.js` 實際監聽的 `{ cfi, fraction, location, index, head, tail }` 欄位（見 `main.js` 第 552/567 行的兩個 `view.addEventListener('relocate', ...)`），結構起點不變代表下游欄位也不會變。

- [ ] **Step 3: 核對 `no-swipe` 屬性讀取仍存在（Epic 27 Issue 9 依賴）**

```bash
grep -n "hasAttribute('no-swipe')" app/android/app/src/main/assets/foliate/paginator.js
```

Expected：找到 3 處（新版行號約 2295/2706/2820，僅供參考），與替換前舊版同樣是 3 處讀取（舊版行號 2186/2499/2558）。`main.js` 第 962 行 `view.renderer.setAttribute('no-swipe', '')` 這個既有設定不需要更動——這一項的真機行為驗證留給 Issue 3，本 Task 只確認程式碼層級的讀取邏輯還在。

- [ ] **Step 4: 確認 `main.js` 沒有設定 `turn-gesture-left-inset`**

```bash
grep -n "turn-gesture-left-inset" app/android/app/src/main/assets/foliate/main.js
```

Expected：無任何輸出（`grep` 結束碼非 0）。design.md 已用 diff 確認這個新屬性未設定時（`Number(null) || 0` 恆為 `0`）不影響現有行為，本步驟只需確認「確實沒有設定」，不需要新增邏輯。

若上述任一步驟結果與 Expected 不符，停下來記錄實際差異，不要自行決定如何處理——回報給人類決定是否需要調整 `main.js` 或視為需要重新評估同步範圍。

---

### Task 4：全面回歸驗證、提交、更新工單狀態

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/issues.md`（Issue 2 的 `**Status:**` 行與完成摘要）

**Interfaces:** 無。

- [ ] **Step 1: `flutter analyze`**

```bash
cd app && flutter analyze
```

Expected：「No issues found!」（cwd 需在 `app/`，之後步驟若沿用同一個終端機工作階段，記得指令前綴或先切回上一層再視需要重新 `cd app`）。

- [ ] **Step 2: `flutter test`**

```bash
flutter test
```

Expected：全數通過。測試總數應與 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 1 記錄的基準線 **1690 項**一致（若 Task 2 的 Step 2 條件分支有被觸發、新增了 polyfill 斷言測試，總數可能略增，屬預期之內，記下實際數字即可）。

若在 Windows 上因暫存目錄檔案被多個測試 worker 同時存取而失敗（錯誤訊息含 `OS Error 32` 這類「檔案正被另一個程序使用」字樣），改用單一 worker 重跑一次：

```bash
flutter test --concurrency=1
```

這只是失敗時的備援手段，不是預設做法——目前沒有證據顯示這個 repo 曾經實際發生過這個問題，正常情況下直接跑 `flutter test` 即可。

- [ ] **Step 3: Commit**

```bash
git add app/android/app/src/main/assets/foliate/paginator.js
git commit -m "$(cat <<'EOF'
chore(epic-32): 同步 paginator.js 至上游 6c6a491

整份覆蓋 app/android/app/src/main/assets/foliate/paginator.js 為
readest/foliate-js commit 6c6a491（合併 f94b251），重寫觸控核心
（#onTouchStart/#onTouchMove/#touchState）。經 GitHub API 確認同步範圍
只有這一個檔案變動，其餘 11 個釘定檔案逐位元組相同，不需替換。

ES 相容性掃描結束碼為 0；Bridge 公開方法簽章（next/prev/goTo、relocate
事件 payload、no-swipe 屬性讀取）核對與替換前一致；main.js 未設定新的
turn-gesture-left-inset 屬性，行為不受影響。flutter analyze/test 零回歸。
EOF
)"
```

若 Task 2 觸發了 polyfill 補強（`_esCompatPolyfillJs`／測試檔案有變更），改用兩個檔案一起 `git add`：

```bash
git add app/android/app/src/main/assets/foliate/paginator.js app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
```

- [ ] **Step 4: 更新工單狀態**

在 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 2 的 `**Status:** ready-for-agent` 那一行，改為記錄已完成，並比照 Issue 1 的寫法補一段簡短總結：ES 掃描結束碼（Task 2 Step 1 結果，是否有觸發 Step 2 的 polyfill 補強）、Bridge 對齊檢查結果（Task 3 四個 Step 是否皆與 Expected 相符）、`flutter test` 實際測試總數（Task 4 Step 2 結果）、commit hash。

```bash
git add docs/epics/epic-32-foliate-js-paginator-sync/issues.md
git commit -m "docs(epic-32): 更新 Issue 2 狀態為已完成"
```
