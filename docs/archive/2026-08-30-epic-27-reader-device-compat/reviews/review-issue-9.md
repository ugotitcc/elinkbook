# Review — Epic 27 Issue 9：流式 EPUB 長按選字／劃線時容易誤觸翻頁

**審查範圍：** `8e6d1361a46a4ac3a566a925b436655cf8858a34`（base）→ `dd28777b384afe363a8ae5c37c176f0ec5d09db8`（head），共 3 個 commit：
- `966e417` fix(epic-27): Issue 9——TapZoneDetector 新增 onPointerMove 熔斷，避免劃線手勢誤觸翻頁
- `422b83b` fix(epic-27): Issue 9——main.js 為 paginator 開啟 no-swipe，停用內建滑動翻頁
- `dd28777` docs(epic-27): 完成 Issue 9 實作計畫所有 Task 進度勾選

**審查方式：** 因目前主要 checkout 的 HEAD 停在 base commit（`8e6d1361`），為了實際執行測試驗證 head 版本行為，另外用 `git worktree add` 建立一個獨立、暫時的唯讀驗證用 worktree（未動到主 checkout 的 HEAD／index／working tree），在其中執行 `flutter pub get`／`flutter analyze`／`flutter test`，並額外用 `git show` 把 `tap_zone_detector.dart` 暫時換回 base 版本（僅在該獨立 worktree 內）以實測「修復前該測試確實會 FAIL（紅燈）」。驗證完畢後已還原並移除該暫時 worktree，未對主 checkout 或任何既有分支/worktree 造成影響。

---

## Strengths

1. **實作與計畫完全一致**：兩個 Task 的程式碼變更（`tap_zone_detector.dart` 的 `onPointerMove` 熔斷、`main.js` 的 `no-swipe` 設定）與 `plan-issue-9.md` 中列出的程式碼片段逐字相符，沒有任何偷改範圍或超出計畫的行為。
2. **`onPointerMove` 熔斷邏輯正確且極簡**：直接複用既有的「`_downPosition` 是否為 `null`」判斷式作為熔斷旗標，不新增額外狀態欄位，邏輯與 `onPointerCancel` 既有清空邏輯完全對稱，程式碼風格與既有檔案一致。
3. **紅燈／綠燈皆已用實際跑測試驗證**（非只是讀程式碼假設）：
   - 在乾淨的 head worktree 執行 `flutter test test/reader/tap_zone_detector_test.dart`：5 則測試全數 PASS（含新測試）。
   - 把 `tap_zone_detector.dart` 暫時換回 base 版本後重跑新測試：確實 FAIL（`Expected: false, Actual: <true>`），證實這則測試在修復前會真實抓到這個 bug，不是空判斷的偽測試。
   - `flutter analyze`：`No issues found!`。
   - 全專案 `flutter test`：**1650 個測試全數 PASS，零回歸**（含 `pdf_reader_view_nav_zone_test.dart`／`reader_screen_test.dart` 熱區相關測試）。
4. **`no-swipe` 修法的事實查證全部通過**：
   - `paginator.js` 確實在 `#onTouchMove`（2186 行）、`#onTouchEnd`（2499 行）、`#onTouchCancel`（2558 行）三處讀取 `hasAttribute('no-swipe')` 並提早 return，2186 行附近甚至有原始 vendored 註解明確寫著「When the host opts out of swipe-to-paginate, let touch events reach native behavior (text selection, etc.)」，證實這是 `paginator.js` 原生就設計好、刻意保留給宿主呼叫端使用的官方逃生艙，不是意外的副作用。
   - `no-swipe` **不在** `Paginator.observedAttributes`（`paginator.js:1157-1161`）清單內，`setAttribute('no-swipe', '')` 不會觸發 `attributeChangedCallback`，純粹是被動的 `hasAttribute()` 讀取，零副作用、零例外風險，符合計畫「`setAttribute` 對任何自訂元素皆安全」的說法。
   - `view.renderer` 在 `view.js` 的 `open(book)` 內是**同步**賦值（`this.renderer = document.createElement('foliate-fxl'/'foliate-paginator')`，`view.js:258/261`），發生在 `await view.open(book)` resolve 之前，故 `main.js` 在 `await view.open(book)` 之後存取 `view.renderer` 保證非 `null`，不會有 race。
   - `foliate-fxl`（`fixed-layout.js`）完全沒有 touch/swipe 相關程式碼、`observedAttributes` 也不含 `no-swipe`，對 FXL 書籍設定這個屬性是完全的 no-op，符合計畫「無條件設定、不分流式/FXL」的判斷。
   - 全專案搜尋 `swipe` 關鍵字，除了本次改動與 `paginator.js` 本身外，只有兩處無關命中：`integration_test/reader_screen_test.dart` 的 `swipe` 是指 PDF 裁切控制點測試用 `adb shell input touchscreen swipe` 模擬拖曳（與 EPUB 滑動翻頁無關）；`pdf_settings_sheet.dart` 的 `Icons.swipe` 是 PDF 端另一套獨立的「滑動翻頁動畫」UI 選項圖示（PDF 走 `pdfrx`，與 `paginator.js` 完全無關的渲染路徑）。**未發現任何功能依賴 `paginator.js` 的內建滑動翻頁**，計畫的宣稱屬實。
5. **文件註解品質高**：`main.js` 新增的註解精確標出三個讀取點行號、根因連結（`bugfix-repro.md` Issue 9 根因 B）、以及與 `longPressGate` 機制的互動關係，且 `longPressGate` 這個機制經查證確實存在於 `main.js`（735-769 行附近），註解沒有杜撰不存在的機制。
6. **架構整合乾淨**：`TapZoneDetector` 是 `Listener`（非 `GestureRecognizer`）實作，新增的 `onPointerMove` 回呼不會參與手勢競技場、不會改變其「不攔截底層原生觸控轉發」的既有特性，PDF／EPUB 共用同一元件的既有設計未被破壞。
7. **`docs` commit（`dd28777`）內容純淨**：確認過 diff，僅將既有 checkbox 從 `[ ]` 勾選為 `[x]`，未夾帶任何計畫內容的實質修改。

---

## Issues

### Critical (Must Fix)
無。

### Important (Should Fix)
無。程式碼正確性、測試有效性、既有功能相容性皆已實測驗證通過，未發現需擋下合併的問題。

### Minor (Nice to Have)

1. ~~**`main.js` 的 `no-swipe` 設定目前完全沒有任何形式的自動化回歸防呆**~~——**已處理**（`c5c47ff` `test(epic-27): Issue 9 審查 Minor #1——main.js no-swipe 屬性補上 flutter test 回歸防呆`）。原始建議是比照 `app/tool/check_foliate_es_compat.js` 寫一支獨立 Node 靜態掃描腳本；改採更適合本專案的做法：`check_foliate_es_compat.js` 的既有觸發時機是「升級 `foliate/` 釘定版本後才跑」（見 `app/tool/README.md`），對「有人在不相關的 `openBook()` 重構中不小心刪掉/搬動這一行」這個真正的風險情境完全不會被觸發到；本專案沒有接 CI，`flutter test` 才是唯一在每個 Issue 驗收標準都明文要求執行的既有關卡。改在 `app/test/reader/foliate_reader_view_test.dart` 新增 `main.js no-swipe 屬性 regression guard` 測試群組，直接讀取 `main.js` 原始碼字串，斷言 `view.renderer.setAttribute('no-swipe', '')` 存在且晚於 `await view.open(book)`。已用「暫時刪掉該行→重跑測試確認真的 FAIL→還原」的方式實測驗證這則測試真的會抓到迴歸（非空判斷），並確認全專案 `flutter analyze`／`flutter test`（1651 項，較先前 1650 項增加這 1 則新測試）皆通過、零回歸。
2. **人工驗證步驟（Task 2 Step 2）的完成狀態僅能信任 checkbox，無法從程式碼本身覆核**——計畫清單已勾選「真機/模擬器上人工驗證」與「螢幕右上角區域反覆長按選字/拖曳劃線確認不再誤觸翻頁」等項目為完成，但這類人工手感驗證天生沒有可供事後稽核的產出物（例如截圖、錄影、或裝置 log）留存在 repo 內。這是 Task 2 這類 vendored JS glue code 修復的固有限制，不是本次實作獨有的疏漏，故僅列為 Minor 記錄，不影響合併判斷。

---

## Recommendations

- 若日後要處理 `issues.md` Issue 9 Solution 第 3-5 項（`tapMaxDurationMs` 收斂、選取清除 Grace Period、直排安全邊距），比照計畫已言明的作法，應另開真機診斷校準的後續工單，不要在缺乏真機回饋迴圈的情況下貿然調數值。
- 可考慮採用上述 Minor 1 的靜態斷言腳本，作為 `no-swipe` 設定的低成本回歸防呆；非阻擋項目。

---

## Assessment

**Ready to merge？** **Yes**

**Reasoning：** 兩項修復皆與計畫精確對齊、程式邏輯正確且已用實際測試證實「修復前紅燈、修復後綠燈」，`no-swipe` 修法的每一項事實主張（三個讀取點、`view.renderer` 非空保證、`observedAttributes` 不含該屬性、FXL 路徑無副作用、無既有功能依賴滑動翻頁）都已對照原始碼逐一查證屬實，全專案 `flutter analyze`／`flutter test`（1650 測試）皆乾淨通過、零回歸。僅存的落差是 `main.js` 變更缺乏自動化測試覆蓋，但這是計畫已誠實記錄且合理接受的已知局限，並有實質的人工驗證程序替代，不構成阻擋合併的理由。
