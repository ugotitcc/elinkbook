# Epic 33 Issue 1：程式碼審查報告

**審查範圍：** `eb7907e7afb4f2ffdacd1c7ecec0f60e994e7a72` → `08b3ccf85351c82362c5563d90324b3cabf752dd`（3 個 commit：`2028baf2`／`29aeb6f2`／`08b3ccf8`）

**審查方式：** 逐檔比對本次替換內容與上游 `readest/foliate-js` commit `c09f06d` 實際下載內容（byte-level diff）；重新實際執行 `flutter analyze`、`flutter test`、`node app/tool/check_foliate_es_compat.js`、`node app/tool/foliate_touch_harness/run-all.mjs`，核對其結果與 commit message／`issues.md` 完成摘要宣稱的數字是否一致；核對 `plan-issue-1.md` 六個 Task 的逐步驟落實情況。全程只讀，未變更 worktree 狀態。

---

## Strengths

1. **除 `fixed-layout.js` 一行 import 路徑外，7 個檔案與上游 `c09f06d` 逐位元組一致**——我親自從 `https://raw.githubusercontent.com/readest/foliate-js/c09f06d/` 下載全部 7 個檔案並與本次提交內容做 `diff`：`epub.js`／`overlayer.js`／`epubcfi.js`／`comic-book.js` 完全零差異；`paginator.js`／`view.js` 的差異精確等於 ADR 0024 patch 本身（見下一點）；`fixed-layout.js` 只有第 1 行 import 路徑一處差異（見 Important #1，屬合理修正而非隨意變更）。這代表 Task 1「整份覆蓋、不手動改動上游內容」的邊界被確實遵守。
2. **ADR 0024 patch 補回精確無誤**——`paginator.js` 的 `detail.contentPages = textPages`（第 3417 行）與 `view.js` 的 `#onRelocate()` 簽章／`recordDensity` 呼叫／`clearLocationDensity()` 方法，逐字對照 `plan-issue-1.md` Task 2 指定內容完全相符，`node --check` 語法檢查可通過。
3. **四層驗證全部可重現、數字與宣稱一致**（我親自重跑，非僅信任 commit message）：
   - `flutter analyze`："No issues found!"
   - `flutter test`：`All tests passed!`，總數 **1693**，與 `plan-issue-1.md` 基準線及 `issues.md` 完成摘要一致。
   - `node app/tool/check_foliate_es_compat.js`：結束碼 `0`，「乾淨」。
   - `node app/tool/foliate_touch_harness/run-all.mjs`：4 個情境、9 項斷言全數 `PASS`。
4. **Bridge 簽章對齊核對準確**——`async goTo(target)`／`async prev(distance)`／`async next(distance)`、`const detail = { reason, range, index }`、`no-swipe`（3 處）／`turn-gesture-left-inset`（1 處）、`main.js` 未設定 `scroll-direction`／`subpixelOffset`、`view.clearLocationDensity()` 呼叫端（第 175 行）、`onLocatorChanged` handler（第 656 行）全部核對相符，`main.js` 全程零異動。
5. **範圍紀律嚴謹**——`progress.js`／`text-walker.js`／`mobi.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js` 五個未同步範圍內的釘定檔案，以及 `index.html`，本次全部零異動，符合 ADR 0011「不觸碰非計畫範圍檔案」的邊界。
6. **commit 顆粒度清楚**，三個 commit 分別對應「同步本體」「狀態更新」「後續修正」，皆為新建 commit 而非 amend，符合 repo 慣例。

---

## Issues

### Critical (Must Fix)

無。程式碼本身（含第 3 個 commit 的偏離修正）經逐位元組比對與四層驗證重新執行，皆確認正確、可重現、無回歸。

### Important (Should Fix)

#### 1. `fixed-layout.js` 的 import 路徑修正是繼 ADR 0024 之外「第三處」對釘定檔案的手動修改，但沒有任何 ADR／設計文件正式記錄這個例外

- **檔案**：`app/android/app/src/main/assets/foliate/fixed-layout.js:1`
- **問題**：`08b3ccf8` 把第 1 行從上游原始的裸模組匯入 `import 'construct-style-sheets-polyfill'` 改為相對路徑 `import './construct-style-sheets-polyfill.js'`。查證確認：`app/android/app/src/main/assets/foliate/index.html` 沒有 import map、專案也不引入 Node.js/npm 打包工具鏈（`docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md` 明訂），因此裸模組匯入在瀏覽器原生 ESM（`InAppWebView`）環境下必定拋出 `Failed to resolve module specifier` 而讓 `fixed-layout.js` 整個模組載入失敗——這個修正在功能上是必要且正確的。
  但同時查證發現：這個相對路徑寫法其實**早在本次同步之前就已存在**（`git show eb7907e7:.../fixed-layout.js` 的第 1 行本來就是 `./construct-style-sheets-polyfill.js`），只是 Task 1 整份覆蓋時被短暫蓋回上游的裸模組寫法，`08b3ccf8` 又把它改回去而已。換句話說，這是一個「早已存在、卻從未被任何 ADR 記錄」的既有 vendored-file 手動修改，這次同步只是意外重新踩到它。
  `plan-issue-1.md`／`docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md` 明文只授權 ADR 0024 兩段 patch 為「唯一例外」（"一個位元組都不手動修改上游內容本身…唯一例外是 Task 2…"）。這次修正讓 `fixed-layout.js` 也不再是逐位元組的上游副本，卻沒有任何文件更新來記錄「這是第二個經正式承認的例外」。
- **為何重要**：若下一次同步（例如未來的 sync issue）沿用同一套「整份覆蓋」SOP，且執行者只知道要補回 ADR 0024 的兩段 patch，幾乎確定會再次意外覆蓋掉這行、重新引入同一個回歸——因為目前完全沒有任何文件告訴下一位執行者「`fixed-layout.js` 第 1 行也需要手動修正」。
- **如何修**：在 ADR 0011（或一個新的簡短附註／`design.md`）記下這個例外及其理由（無 import map／無打包工具 → 裸模組匯入必定失敗），並更新 Task 1 的「唯一例外」敘述涵蓋這一項，供未來同步工單直接依循，不需要重新意外發現。

#### 2. 這個 fix 本身缺乏驗證軌跡——Issue 1 宣稱的四層驗證實際上沒有任何一層真正執行過 `fixed-layout.js` 的模組載入路徑

- **檔案**：`app/android/app/src/main/assets/foliate/fixed-layout.js`；`app/tool/foliate_touch_harness/*.mjs`
- **問題**：`fixed-layout.js` 只在開啟 FXL/CBZ 書籍時，由 `view.js:265` 的 `await import('./fixed-layout.js')` 動態載入。查證確認 `app/tool/foliate_touch_harness/` 目前 4 個情境（含 `smoke-test.mjs`）使用的 fixture 全部是 reflowable EPUB（`sample.epub`／`sample_horizontal.epub`／`sample_long_chinese_vertical.epub`），沒有一個是 FXL 或 CBZ，因此完全不會觸發這條動態 import 路徑；`node --check` 只做語法檢查、不解析模組路徑是否可被瀏覽器 ESM 正確 resolve；`flutter test` 是純 Dart widget test，不會啟動真實 `InAppWebView` 執行 JS。也就是說，這個修正目前完全只靠人工讀 diff／比對歷史判斷正確，「這樣改就能讓 FXL/CBZ 真的正常開啟」尚未被本工單宣稱的任何一層自動化驗證證實過。
- **為何重要**：這個修正本身高度可信（理由見 Important #1），但它是本次同步中唯一一處「無法被本 Issue 既有四層驗證覆蓋」的變更，卻沒有被特別標註出來。若這行事實上仍有問題（例如相對路徑大小寫或副檔名有誤），要等到 Issue 2 真機測試才會被發現，而 Issue 2 目前的清單裡「CBZ／FXL 漫畫 RTL 頁序」「FXL 橫向雙頁跨頁排版」只排在第 6-7 項，不是優先驗證項目。
- **如何修**：在 `issues.md` Issue 1 完成摘要或 Issue 2 描述中明確點出「`fixed-layout.js` import 路徑修正尚未經任何自動化路徑驗證，真機測試請優先驗證 CBZ／FXL 書籍是否能正常開啟；若這行有誤，症狀會是 FXL/CBZ 書籍完全無法開啟並在 WebView console 拋出 `Failed to resolve module specifier` 例外」，讓 Issue 2 執行者清楚這是一個新引入且未驗證的風險點。

#### 3. `issues.md` Issue 1 完成摘要在 fix commit 之前就已寫定，之後未回頭更新，目前內容與實際結果有落差

- **檔案**：`docs/epics/epic-33-foliate-js-vendor-sync/issues.md`（Issue 1 完成摘要，由 `29aeb6f2` 寫入）
- **問題**：`29aeb6f2`（完成摘要提交）發生在 `08b3ccf8`（`fixed-layout.js` 修正）**之前**，之後沒有任何後續 commit 回頭補充。目前完成摘要只列「替換 7 個 vendored 檔案為上游 `c09f06d`」與「補回 ADR 0024 patch」，完全沒有提到 `fixed-layout.js` 額外的 import 路徑修正；驗收標準原文「7 個檔案已替換為 `c09f06d` 版本」也隱含「逐位元組相同」，與 `fixed-layout.js` 實際多了一行手動 patch 的事實不符。
- **為何重要**：`issues.md` 是本專案 SDD 流程裡追蹤工單真實狀態的唯一事實來源（`docs/agents/issue-tracker.md`），完成摘要遺漏一項有實際程式碼影響的修正，會讓之後查閱工單記錄的人（含 Issue 2 執行者、未來同步的執行者）誤以為這 7 個檔案都是純淨上游副本。
- **如何修**：在 issues.md 完成摘要補一條項目，說明 `fixed-layout.js` 額外做了 import 路徑修正（附理由與行號），並在驗收標準文字上區分「6 個檔案逐位元組相同、`fixed-layout.js` 額外含 1 行必要修正」。

### Minor (Nice to Have)

#### 1. `issues.md` 完成摘要提到的 `goToCfi` 方法名稱不存在

- **檔案**：`docs/epics/epic-33-foliate-js-vendor-sync/issues.md`（Issue 1 完成摘要）
- **問題**：完成摘要寫「Bridge 公開簽章對齊通過（`next`/`prev`/`goToFraction`/`goToCfi`…）」，但查證 `app/android/app/src/main/assets/foliate/*.js` 全文找不到 `goToCfi` 這個方法名稱。`main.js` 第 370 行實際呼叫的是 `view.goTo(cfi)`，對應 `paginator.js` 的 `async goTo(target)`（`plan-issue-1.md` Task 5 Step 1 核對的正是這個名稱）。
- **如何修**：把 `goToCfi` 訂正為 `goTo`，避免日後讀者搜尋一個不存在的 API 名稱。

#### 2. `08b3ccf8` 的 commit message 沒有說明修正理由

- **問題**：commit message 只有標題一行「`fix(epic-33): 修正 fixed-layout.js 模組匯入為相對路徑並更新 plan 進度`」，沒有 body 解釋「為什麼」需要這個修正（裸模組匯入在無 import map／無打包工具的瀏覽器 ESM 環境下會直接失敗）。相較前兩個 commit 都有詳細 body，這個修正說明相對單薄——而它正是本次審查特別要求關注的偏離計畫項目。
- **如何修**：非強制，但若允許修改歷史，補一段 body 說明會降低日後讀 log 者的理解成本；至少應在 `issues.md`（見 Important #3）補上等效說明。

---

## Recommendations

1. 在 ADR 0011 或設計文件中正式記錄 `fixed-layout.js` 這個「相對路徑 import」的例外，並將「唯一例外」的敘述擴充為涵蓋這一項，避免未來同步又意外還原、重新引入同一個回歸（對應 Important #1）。
2. 考慮在 `app/tool/` 新增一支輕量腳本：對「非 ADR 0024／未來新增例外範圍」內容做逐位元組比對上游釘定 commit，未來每次 sync（或 CI）都能立即抓到這類隱性回歸，不需仰賴人工 diff review 才能發現。
3. Issue 2 真機測試執行時，建議把「開啟 CBZ／FXL 書籍」列為優先驗證項目（而非目前清單裡排序較後的項目），因為這是本次修正影響最大、也是唯一未經任何自動化驗證的路徑（對應 Important #2）。

---

## Assessment

**Ready to merge？** With fixes（文件層級修正，非程式碼層級）

**Reasoning：** 程式碼本身正確——經逐位元組比對上游 `c09f06d` 與親自重跑全部四層驗證（`flutter analyze`／`flutter test` 1693 項全過／ES 相容性掃描 exit 0／觸控 Harness 4 情境 9 斷言全 PASS），結果與 commit message／`issues.md` 宣稱完全一致，無需重新修改程式碼。但第 3 個 commit 修正的 `fixed-layout.js` import 路徑是繼 ADR 0024 之外新增的、未經任何 ADR 記錄的第三處手動修改，且是本次同步中唯一沒有被任何自動化驗證層覆蓋到的變更，`issues.md` 完成摘要也因寫作時序而遺漏了這項修正——建議合併前（或合併後立即）補齊 Important #1-#3 的文件記錄，讓 Issue 2 執行者清楚知道這是一個需要優先真機驗證的新風險點。
