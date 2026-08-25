# Epic 33 — foliate-js 持續同步：工單清單 (Issues)

依 `design.md`（Discovery：`/grill-with-docs`；已依 `/superpowers:receiving-code-review` 審查修訂）拆解為 2 個線性依賴的工單，`epic-31` Issue 3 已合併回 `main`（commit `8a9be2cd`），排期依賴已解除，可立即開始。

**Issue 1 範圍已擴充**：撰寫 Issue 1 實作計畫（`/superpowers:writing-plans`）時發現一個既有缺陷——`paginator.js`／`view.js` 實際上並非純淨 vendored 檔案，依 `docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`（`epic-26` Issue 11）帶有正式重新開放 ADR 0011 的手動 patch，`epic-32` 整份覆蓋同步 `paginator.js` 時已靜默移除其中一半（`detail.contentPages`）。原規劃把修復另立獨立 Issue 3、依賴 Issue 1 完成後才做；但 `/superpowers:receiving-code-review` 審查 `plans/plan-issue-1.md` 時發現：若不補回 `view.js` 的 `clearLocationDensity()`，Issue 1 自己的觸控 Harness（Task 4）會在第一次 `relocate` 事件觸發 `applyPreferences()` 時 100% 拋出例外、逾時崩潰，無法完成 Issue 1 本身。因此改為**把 ADR 0024 patch 補回併入 Issue 1**（見下方設計要點新增的 Task 2），不再另立 Issue 3。

---

## Issue 1：同步 7 個 vendored 檔案至 `c09f06d`＋補回 ADR 0024 patch＋第一/二層測試防護

**Status:** 已完成（Commit `2028baf`）

**完成摘要：**
- 替換 7 個 vendored 檔案為上游 `c09f06d`（`paginator.js`、`epub.js`、`fixed-layout.js`、`view.js`、`overlayer.js`、`epubcfi.js`、`comic-book.js`）。
- 補回 ADR 0024 密度校正 patch（`paginator.js` 的 `relocate` 事件 `detail.contentPages`；`view.js` 的 `#onRelocate()` 消費與 `clearLocationDensity()` 方法）。
- ES 相容性掃描（`node app/tool/check_foliate_es_compat.js`）結束碼為 `0` 乾淨，無未宣告之現代 ES 語法需求。
- 觸控 Harness（`node app/tool/foliate_touch_harness/run-all.mjs`）4 個情境 9 項斷言全數 PASS。
- Bridge 公開簽章對齊通過（`next`/`prev`/`goToFraction`/`goTo`、`relocate` 事件 payload、`no-swipe`/`turn-gesture-left-inset` 屬性讀取、`clearLocationDensity` 呼叫端核對一致；`main.js` 未啟用 `scroll-direction` 與 `subpixelOffset`）。
- `flutter analyze` 乾淨（No issues found!），`flutter test` 通過 1693 項測試零回歸。
- **額外修正（commit `08b3ccf8`）**：`fixed-layout.js` 第 1 行整份覆蓋後被還原成上游裸模組匯入 `import 'construct-style-sheets-polyfill'`，在本專案無 import map／無打包工具的環境下會直接讓 FXL/CBZ 書籍載入失敗，已改回同步前既有的相對路徑寫法 `import './construct-style-sheets-polyfill.js'`。程式碼審查（`reviews/review-code-issue-1.md` Important #1/#2）發現這其實是早於本次同步就存在、卻從未被記錄過的既有例外，已正式登記為 [ADR 0025](../../adr/0025-fixed-layout-relative-module-specifier-reopen-adr-0011.md)。**這處修正目前完全沒有被本 Issue 任一層自動化驗證覆蓋到**（觸控 Harness 4 個情境的 fixture 皆為 reflowable EPUB，不會觸發 `fixed-layout.js` 的動態載入路徑），正確性仰賴 Issue 2 真機開啟 CBZ／FXL 書籍驗證，若這行有誤，症狀會是 FXL/CBZ 書籍完全無法開啟、WebView console 出現 `Failed to resolve module specifier` 例外。

**依賴：** 無，可立即開始（`epic-31` Issue 3 已合併，排期依賴已解除）

**來源：** `design.md`「目標」第 1/2 項、「整體機制」（資產盤點表、`paginator.js` 7 個新 commit 摘要、`fixed-layout.js` 2 個 commit 詳情）。

**背景／需求：** 上游 `readest/foliate-js` 自 `epic-32` 同步至 `6c6a491` 後，又累積 22 個新 commit（HEAD 已到 `c09f06d`），其中 17 個觸及本專案已釘定使用的 vendored 檔案。逐位元組比對確認以下 7 個檔案有變動、需要整份替換；其餘 5 個已釘定檔案（`progress.js`／`text-walker.js`／`mobi.js`／`vendor/zip.js`／`construct-style-sheets-polyfill.js`）全程零變動，不需同步。

**設計要點（依 `design.md`，含審查修訂）：**
- 從 `https://raw.githubusercontent.com/readest/foliate-js/c09f06d/<檔名>` 下載內容，整份覆蓋 `app/android/app/src/main/assets/foliate/` 下對應檔案，不手動修改內容（符合 ADR 0011）：
  - `paginator.js`（7 個 commit，+156/-20，含 3 個 WebKit 相關 commit `cf9829d`／`887a0ae`／`68d54b1`，隨檔案整份帶入、不額外測試其 WebKit 行為）
  - `epub.js`（4 個 commit，+58/-5）
  - `fixed-layout.js`（2 個 commit，+248/-77；新增水平捲動模式**不啟用**，`main.js` 不設定 `scroll-direction` 屬性）
  - `view.js`（1 個 commit，+8/-0）
  - `overlayer.js`（1 個 commit，+8/-0）
  - `epubcfi.js`（1 個 commit，+2/-2）
  - `comic-book.js`（1 個 commit，+15/-1）
- **補回 ADR 0024 密度校正 patch**：整份覆蓋 `paginator.js`／`view.js` 會移除 `docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`（`epic-26` Issue 11）在這兩個檔案內正式重新開放 ADR 0011 的手動 patch，須在下載完成後立即補回——`paginator.js` 的 `relocate` 事件 `detail` 補回 `contentPages` 欄位；`view.js` 的 `#onRelocate()` 補回 `contentPages` 消費、新增 `clearLocationDensity()` 方法（`main.js` 第 175 行 `window.applyPreferences()` 無條件呼叫，若缺席會直接拋例外）。`progress.js` 的另一半 patch（`recordDensity`/`clearDensity`）這次未變動、不需處理。
- **第一層：靜態與單元測試**——執行 ES 相容性掃描（`node app/tool/check_foliate_es_compat.js`），若結束碼非 0，依硬性規範在 `_esCompatPolyfillJs`（`foliate_reader_view.dart`）補齊 polyfill（① 僅在 `if (!TargetAPI)` 缺席時定義；② 嚴禁 ES2021+ 語法糖）。注意此掃描為 Regex 掃描已知 API 清單，**無法**攔截語法解析期（Parse Time）的 `SyntaxError`（例如 `?.`／`??=`），語法層級問題留待 Issue 2 真機驗收把關，不在本工單自動化範圍內。
- **第二層：觸控 Harness 自動化**——執行 `node app/tool/foliate_touch_harness/run-all.mjs`（`epic-31` Issue 1 建立），4 個情境須全數 PASS，作為攔截 `TouchIntentClassifier`（`epic-31` Issue 2 成果）與上游觸控／捲動邏輯衝突的自動化防線。
- **Bridge 對齊檢查**：逐一核對 `main.js` 呼叫到的 `Paginator`/`view` 公開方法簽章（`view.next()`／`view.prev()`／`view.goToFraction()`／`view.goTo()`／`relocate` 事件 payload 的 `{ cfi, fraction, location, index, head, tail }` 欄位）是否不變；確認 `main.js` 沒有設定 `fixed-layout.js` 新增的 `scroll-direction` 屬性、也沒有呼叫 `paginator.js` 新暴露的 sub-pixel scroll offset API（只求相容不擴充行為）；`fd91451`（連續捲動時定期發射 `relocate`）需額外確認快速連續翻頁／捲動時 `onLocatorChanged` 橋接通訊仍流暢無卡頓，`ReadingPositionRepository` 沒有被異常高頻寫入。

**測試要求：**
- ES 相容性掃描結束碼為 0（若有補 polyfill，需重跑確認）。
- `node app/tool/foliate_touch_harness/run-all.mjs` 4 個情境全數 PASS。
- `flutter analyze` 為「No issues found!」、`flutter test` 全數通過，零回歸。

**驗收標準：** 6 個檔案（`paginator.js`／`epub.js`／`view.js`／`overlayer.js`／`epubcfi.js`／`comic-book.js`）逐位元組替換為 `c09f06d` 版本；`fixed-layout.js` 除第 1 行依 ADR 0025 維持既有相對路徑 import 外，其餘逐位元組相同；`paginator.js`／`view.js` 的 ADR 0024 patch 已補回（`detail.contentPages`／`clearLocationDensity()`）；ES 掃描乾淨；觸控 Harness 4 情境全過；Bridge 公開方法簽章與 `relocate` payload 核對通過（不變，或已對應調整並記錄）；`flutter analyze`／`flutter test` 通過。

---

## Issue 2：真機深度驗收（8 項）＋文件收尾

**Status:** ready-for-agent

**依賴：** Issue 1（要先換上新版檔案才有得測；Issue 1 現已涵蓋 ADR 0024 patch 補回，`applyPreferences()` 崩潰風險已在 Issue 1 內解決，本工單不需要額外依賴）

**來源：** `design.md`「目標」第 3/4 項、「測試策略」第三層、「已知風險」。

**背景／需求：** `paginator.js` 與 `fixed-layout.js` 這次改動涉及觸控／捲動內部行為與 FXL 排版，Puppeteer 自動化在目前環境對 `touchmove` 場景不可靠（`epic-31`／`epic-32` 已記錄的限制），核心驗收一律真機進行，逐項記錄於 `reviews/review-issue-2.md`。

**優先驗證項目**：Issue 1 程式碼審查（`reviews/review-code-issue-1.md` Important #2）發現 `fixed-layout.js`（依 [ADR 0025](../../adr/0025-fixed-layout-relative-module-specifier-reopen-adr-0011.md) 補回的相對路徑 import 修正）完全沒有被 Issue 1 任何自動化驗證層覆蓋過——本 Epic 目前唯一的自動化觸控 Harness 只用 reflowable EPUB fixture，不會觸發這個檔案的動態載入路徑。**真機測試請優先開啟一本 CBZ 與一本 FXL EPUB，確認能正常開書**（不要按下方清單順序排到最後才測）；若這行修正實際有誤，症狀是 FXL/CBZ 書籍完全無法開啟，WebView console 會出現 `Failed to resolve module specifier` 例外。

**測試要求（真機重測清單，共 8 項）：**
- **歷史修法（3 項，比照 `epic-32`）**：
  - Epic 18 Issue 47：長按選字前幾影格畫面不暴跳。
  - Epic 25 Issue 1：畫線選取已確立時不誤觸跳頁。
  - Epic 27 Issue 9：`no-swipe` 屬性正確阻止滑動。
- **直排核心（2 項）**：
  - 直排 EPUB 連續往前翻頁 5 次、再反向翻頁 5 次，精確回到原始文字錨點。
  - 繁中流式 EPUB 閱讀中即時切換橫排／直排，閱讀位置（錨點）精確維持（對應 `2b6ea0a`，呼應 Epic 18 Issue 45）。
- **固定版面（3 項）**：
  - CBZ／FXL 漫畫 RTL 頁序正確。
  - FXL 橫向雙頁跨頁排版與封面單頁顯示正常（對應 `663e630`，呼應 Epic 18 Issue 19）。
  - 劃線標註縮放（zoom）後正確刷新，不需手動觸發其他操作（對應 `9fde61a`）。

**快速停損指標：** 若真機重測中「直排對稱翻頁」失敗，或出現舊版 WebView（Mobiscribe WAVE／iReader Ocean 4 Plus 等 Chromium 83-91 機型）`SyntaxError` 且無法透過 Dart 端 Polyfill 在 **2 小時內**排除，直接 `git revert` 這次同步的 commit，退回 `6c6a491`，不在時間壓力下硬修。

**設計要點（文件收尾）：**
- 更新 `docs/research/foliate_js_sync_update_strategy.md`「2.1 上游來源與當前釘定狀態」的 Pinned Commit 記錄為 `c09f06d`（含日期）。
- 更新 `docs/epics.md`：本 Epic 狀態視結果更新（完成則等待人類確認歸檔）。

**驗收標準：** 8 項真機測試全數通過並記錄；若有回歸已依快速停損指標處理；`docs/research/foliate_js_sync_update_strategy.md`／`docs/epics.md` 已更新。
