# Epic 32 — foliate-js paginator.js 上游同步：工單清單 (Issues)

依 `design.md`（Discovery：`/superpowers:brainstorming`；已依 `/superpowers:receiving-code-review` 審查修訂）拆解為 3 個線性依賴的工單，照 SOP 順序執行，沒有能平行的空間。

---

## Issue 1：修復 ES 相容性掃描工具＋確認基準線

**Status:** completed（已完成：`check_foliate_es_compat.js` 4 處過時路徑已修復；ES 掃描結束碼為 `0` 乾淨；`flutter analyze` 為「No issues found!」；`flutter test` 通過 1690 項測試基準線，commit: `3e82e23`）

**依賴：** 無，可立即開始

**來源：** `design.md`「先決條件：修復 ES 相容性掃描工具」。

**背景／需求：** `app/tool/check_foliate_es_compat.js` 第 37-40 行寫死參照 `app/lib/reader/foliate_epub_reader_view.dart`，此檔案已在後續 Epic（ADR 0017／0023 統一 Foliate 格式）改名為 `app/lib/reader/foliate_reader_view.dart`，工具現況執行會直接拋出 `ENOENT` 例外，SOP 要求的 ES 相容性掃描這步現在跑不動。

**設計要點：**
- 把 `POLYFILL_SOURCE_FILE` 的路徑改成 `app/lib/reader/foliate_reader_view.dart`。
- 只改這一處路徑，不動掃描邏輯本身。

**測試要求：**
- `node app/tool/check_foliate_es_compat.js` 能正常執行、結束碼為 `0`（針對目前**尚未替換**的 `paginator.js` 執行，這是基準線，不是驗證新版）。
- `flutter analyze`／`flutter test` 全數通過，確認 repo 目前狀態乾淨，作為後續 Issue 2/3 比對的基準。

**驗收標準：** 掃描工具可正常執行且回報乾淨（結束碼 `0`）；基準線 `flutter analyze`／`flutter test` 通過。

---

## Issue 2：同步 `paginator.js` 至 `6c6a491`

**Status:** ready-for-agent

**依賴：** Issue 1（掃描工具要先能正常執行）

**來源：** `design.md`「目標」第 1/3 項、「整體機制」。

**背景／需求：** 上游 `readest/foliate-js` 的 `paginator.js` 在 commit `6c6a491`（合併 `f94b251`）大幅重寫觸控核心（`#onTouchStart`／`#onTouchMove`／`#touchState`），Discovery 階段已用 GitHub API 確認同步到這個 commit **只有 `paginator.js` 這一個檔案變動**，其餘 11 個釘定檔案逐位元組相同。

**設計要點（依 `design.md`，含審查修訂）：**
- 從 `https://raw.githubusercontent.com/readest/foliate-js/6c6a491/paginator.js` 下載內容，整份覆蓋 `app/android/app/src/main/assets/foliate/paginator.js`，不手動修改內容（符合 ADR 0011）。
- 執行 ES 相容性掃描（Issue 1 已修復），若結束碼非 `0`：在 `_esCompatPolyfillJs`（`foliate_reader_view.dart`）補齊 polyfill，硬性規範：① 僅在 `if (!TargetAPI)` 缺席時定義；② 嚴禁使用 ES2021+ 語法糖（`??=`／`||=`／`&&=`／可選鏈 `?.`／標籤模板等），本體須為 ES5/ES2020 相容語法。
- Bridge 對齊檢查：逐一核對 `main.js` 實際呼叫到的 `Paginator`/`view` **公開**方法簽章（`view.next()`／`view.prev()`／`view.goToFraction()`／`view.goToCfi()`／`relocate` 事件 payload 的 `{ cfi, fraction, location, index, head, tail }` 欄位）是否不變。`#touchState` 等新增欄位皆為私有實作細節，`main.js` 本來就無法存取，不需要逐一核對。
- 確認 `main.js` 沒有設定新的 `turn-gesture-left-inset` 屬性（已在 design.md 用 diff 確認此屬性預設不保留任何區域，不影響現有行為；本項只需確認「確實沒有設定」，不需要新增邏輯）。

**測試要求：**
- ES 相容性掃描結束碼為 `0`（若有補 polyfill，需重跑確認）。
- `flutter analyze` 為「No issues found!」、`flutter test` 全數通過，零回歸。

**驗收標準：** `paginator.js` 已替換為 `6c6a491` 版本；ES 掃描乾淨；Bridge 公開方法簽章核對通過（不變，或已對應調整並記錄）；`flutter analyze`／`flutter test` 通過。

---

## Issue 3：真機 QA＋文件收尾

**Status:** ready-for-agent

**依賴：** Issue 2（要先換上新版 `paginator.js` 才有得測）

**來源：** `design.md`「目標」第 4/5 項、「測試策略」。

**背景／需求：** `paginator.js` 觸控核心重寫，Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9 三個依賴其內部行為的歷史修法必須真機重新驗證，不能只靠自動化測試結案（Puppeteer 在目前環境對 `touchmove` 場景不可靠，見 `epic-31` 已記錄的限制，與 `paginator.js` 版本無關，這裡同樣不採用）。

**測試要求（真機重測清單，逐項記錄於 `reviews/review-issue-3.md`）：**
- Issue 47：橫排/直排長按選字前幾影格畫面不暴跳。
- Epic 25 Issue 1：畫線選取已確立時不誤觸跳頁（比對 Air Reader Pro C／TCL 14 吋兩種機型，比照原始 Issue 記錄的驗證方式）。
- Epic 27 Issue 9：特定情境下滑動手勢確實被 `no-swipe` 屬性正確阻止。
- 額外基本 smoke（設計審查 Minor #1 採納的客觀判準）：直排 EPUB 連續往前翻頁 5 次、再反向翻頁 5 次，精確回到原始文字錨點。

**若任一項出現無法在合理時間內修復的回歸**：`git revert` 這次同步的 commit，退回 `dd71f2be356563c16a23272686189fcfb45d0b82`，不在時間壓力下硬修（`epic-31` 可以繼續等，不構成無法接受的阻塞）。

**設計要點（文件收尾）：**
- 更新 `docs/research/foliate_js_sync_update_strategy.md`「2.1 上游來源與當前釘定狀態」的 Pinned Commit 記錄為 `6c6a491`（含日期）。
- 更新 `docs/epics.md`：本 Epic 狀態視結果更新（完成則歸檔）；`epic-31` 那一列移除「暫緩實作」的備註，恢復可繼續。

**驗收標準：** 4 項真機測試全數通過並記錄；若有回歸已依上述回退機制處理；`docs/research/foliate_js_sync_update_strategy.md`／`docs/epics.md` 已更新。
