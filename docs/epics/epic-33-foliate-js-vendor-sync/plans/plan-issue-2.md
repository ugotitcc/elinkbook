# Epic 33 Issue 2：真機深度驗收（8 項）＋文件收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真實 Android 裝置上完成 8 項真機深度驗收（3 個歷史修法回歸、2 個直排核心情境、3 個固定版面情境），優先確認 CBZ／FXL 書籍能正常開啟（把關 Issue 1 補回的 ADR 0025 相對路徑 import 修正，這處修正目前完全沒有自動化測試覆蓋）；全數通過後更新版本紀錄文件收尾，若有無法在 2 小時內排除的回歸，`git revert` 退回同步前狀態。

**Architecture:** 本工單**不是**寫程式，是「建置測試版 App → 人工在實體裝置上操作 → 記錄結果 → 依結果二選一分支（文件收尾 或 revert）」。`design.md`「測試策略」第三層明確排除 Puppeteer 自動化（這個環境對 `touchmove` 場景不可靠），這 8 項驗收本質上需要人類主觀/客觀判斷（例如 Epic 25 Issue 1 的原始驗收標準就是人類拿實體裝置判斷「可接受」），不是可以用 assert 自動判定的東西——所以本計劃的每個測試步驟都需要**人類實際拿裝置操作、agent 記錄人類回報的結果**，agent 自己不能單獨完成判定，也不能用 `adb shell input` 合成觸控事件代替人類判斷。

**Tech Stack:** Flutter（`flutter build apk --debug`）、adb（安裝 APK、推送測試書籍、確認裝置清單；不支援 adb 的裝置改用 USB/MTP 手動側載）、Git（`git revert`）、curl（文件收尾階段查詢 GitHub API 取得完整 commit SHA）。

**Spec:** `docs/epics/epic-33-foliate-js-vendor-sync/design.md`（「目標」第 3/4 項、「測試策略」第三層、「已知風險」）；工單描述見 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` Issue 2。

## Global Constraints

- **執行環境為 Windows，本計劃所有 shell 指令一律使用 Bash 工具（Git Bash）執行**，不要改用 PowerShell 工具或 cmd.exe（比照 `plans/plan-issue-1.md`、`epic-32` Issue 3 既有作法）。
- **每一項真機測試都需要人類實際操作裝置並回報觀察結果**——agent 的角色是準備建置/測試素材、把明確的操作步驟交給人類、如實記錄人類回報的 PASS/FAIL 與描述，**不能自行用 adb 合成觸控事件來代替人類判斷**。若某個 Step 卡在「需要人類回報才能繼續」，就停下來詢問，不要自己編造結果。
- **裝置清單現場決定，不在計畫裡寫死型號**（規劃階段已與人類確認：目前手邊可用裝置不固定）——Task 1 用 `adb devices -l` 現場列出已連接、支援 adb 的裝置；不支援 adb 的裝置（例如過去用過的 Air Reader Pro C）改用 USB/MTP 手動側載，流程見 Task 1 Step 3b/4b。
- **Epic 25 Issue 1 這一項需要至少兩台觸控特性不同的實體裝置比對**（原始症狀是「其中一台會跳頁、另一台不會」，只用一台測不出這個回歸）——執行 Task 4 前，若現場只確認到一台裝置，停下來詢問人類是否要準備第二台，不要用同一台裝置重複測兩次充數。
- **快速停損指標的「舊版 WebView」驗證是機會性的，不是強制卡關項**——`design.md` 提到 Mobiscribe WAVE／iReader Ocean 4 Plus 等 Chromium 83-91 機型，若現場沒有這類機型，如實在 `review-issue-2.md` 記錄「本次測試環境未涵蓋舊版 WebView 機型」，**不要**假裝有測、也不要因為缺這類機型就卡住整個 Issue 不能收尾；若現場剛好有，優先在 Task 2（CBZ／FXL 優先驗證）安排在這台機器上跑一次，這是「語法解析期 SyntaxError」唯一能被實機攔截的地方。
- **CBZ／FXL 優先驗證必須排在 Task 2、所有其他真機測試之前**（`issues.md`「優先驗證項目」明文要求，理由：Issue 1 補回的 `fixed-layout.js` 相對路徑 import 修正完全沒有被任何自動化驗證層覆蓋過，若這裡有誤，症狀是 FXL/CBZ 書籍完全無法開啟）。
- **只使用 `app/test/fixtures/` 底下既有的測試書籍，不新增書籍檔案**：`sample_horizontal.epub`（橫排流式）、`sample_long_chinese_vertical.epub`（直排 CJK 流式）、`sample.cbz`（CBZ，`foliate_cbz_test.dart` 既有的 RTL 驗證 fixture）、`sample_fixed_layout.epub`（FXL，`epub_dual_page_test.dart` 既有的雙頁/單頁驗證 fixture）。
- **快速停損指標（`design.md`「已知風險」）**：若「直排對稱翻頁」（Task 6）失敗，或出現舊版 WebView `SyntaxError` 且無法在 **2 小時內**排除，直接進入 Task 11 的 Branch B（`git revert`），不在時間壓力下硬修。
- **revert 目標是本地 commit `2028baf2`（Issue 1 主要同步）與 `08b3ccf8`（Issue 1 額外修正 `fixed-layout.js` 相對路徑 import）兩個 commit，不是上游 hash `c09f06d`**——`git log --oneline -- app/android/app/src/main/assets/foliate/` 已確認這是本次同步唯一改到 vendored 檔案的兩個 commit（規劃階段已查證）。
- **歸檔（把 `docs/epics/epic-33-foliate-js-vendor-sync/` 整個資料夾搬到 `docs/archive/`）是人類指定的動作**（`sdd-workflow` skill 生命週期第 7 步），本工單只更新 `docs/epics.md` 的文字描述反映 Issue 2 結果，**不**執行 `git mv` 搬移資料夾、**不**把狀態圖示改成 🟢 已歸檔。
- `docs/epics/epic-33-foliate-js-vendor-sync/reviews/` 已加進根目錄 `.gitignore`，本工單要求的 `reviews/review-issue-2.md` 寫在這個目錄下即可，**不需要**（實際上 `git add` 也不會有效果）把它加進 commit。

---

### Task 1：建置測試版 App、現場盤點裝置、準備測試書籍

**Files:**
- Create: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（骨架，後續 Task 2-10 逐節填入結果）

**Interfaces:**
- Produces: `review-issue-2.md` 內 9 個章節標題（優先驗證＋8 項測試），供 Task 2-10 各自填入該節內容；`app-debug.apk`（`app/build/app/outputs/flutter-apk/app-debug.apk`）供 Task 2-10 安裝到裝置。

- [ ] **Step 1: 建置 debug APK**

```bash
cd app && flutter build apk --debug
```

Expected：成功產出 `app/build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 2: 現場列出已連接、支援 adb 的裝置**

```bash
adb devices -l
```

Expected：列出所有支援 adb 且已連接的裝置。若某台預期要測的裝置（例如過去記錄用過的機型）不在清單裡，先確認是否為不支援 adb 的機型（改走下方 Step 3b/4b MTP 流程），或是尚未接上——**若目前身邊只有 0-1 台裝置能用來測 Epic 25 Issue 1（見 Global Constraints），停下來詢問人類，不要continue 假裝有第二台**。

- [ ] **Step 3a: 把 APK 安裝到每一台支援 adb 的裝置**

對 Step 2 確認到的每個 adb 裝置序號執行：

```bash
adb -s <device-id> install -r app/build/app/outputs/flutter-apk/app-debug.apk
```

Expected：每台都印出 `Success`。

- [ ] **Step 3b（僅不支援 adb 的裝置，人類手動操作）：透過 MTP 側載 APK**

請人類依序操作：

1. USB 接上 Windows，確認裝置的 USB 連線模式為「檔案傳輸」。
2. 打開 Windows 檔案總管，進入該裝置的儲存空間，找到（或新建）`Download` 資料夾。
3. 把 `app/build/app/outputs/flutter-apk/app-debug.apk`（Windows 路徑：`U:\MyDeveloper\AI\elinkBook\app\build\app\outputs\flutter-apk\app-debug.apk`）拖曳複製進裝置的 `Download` 資料夾。
4. 在裝置上打開內建的檔案管理員 App，導覽到 `Download` 資料夾，點擊 `app-debug.apk`。
5. 若系統跳出「已封鎖安裝」或「不明來源」警告，先到裝置的「設定 → 安全性（或應用程式）→ 允許安裝不明來源應用程式」，針對目前使用的檔案管理員 App 開啟允許，再回頭重新點擊該 APK 完成安裝。
6. 若裝置上已經裝過舊版，系統會問是否要「更新」，選擇更新即可。

Expected：該裝置的主畫面出現 App 圖示，可以正常開啟。

- [ ] **Step 4a: 推送測試書籍到每台支援 adb 的裝置**

```bash
adb -s <device-id> push app/test/fixtures/sample_horizontal.epub /sdcard/Download/
adb -s <device-id> push app/test/fixtures/sample_long_chinese_vertical.epub /sdcard/Download/
adb -s <device-id> push app/test/fixtures/sample.cbz /sdcard/Download/
adb -s <device-id> push app/test/fixtures/sample_fixed_layout.epub /sdcard/Download/
```

Expected：4 個檔案都成功推送到每台裝置的 `/sdcard/Download/`。

- [ ] **Step 4b（僅 MTP 側載裝置，人類手動操作）：透過 MTP 複製測試書籍**

延續 Step 3b 開著的檔案總管視窗，把下列 4 個檔案（Windows 路徑：`U:\MyDeveloper\AI\elinkBook\app\test\fixtures\`）一併拖曳複製進裝置的同一個 `Download` 資料夾：`sample_horizontal.epub`、`sample_long_chinese_vertical.epub`、`sample.cbz`、`sample_fixed_layout.epub`。

Expected：裝置的 `Download` 資料夾裡看到這 4 個檔案。

- [ ] **Step 5: 建立 `review-issue-2.md` 骨架**

```markdown
# Epic 33 Issue 2 — 真機重測報告

**測試日期**：<填入實際執行日期>
**測試裝置**：<逐台列出型號與連線方式（adb 序號 或 USB/MTP）>
**對應同步 commit**：`2028baf2`（chore(epic-33): 同步 7 個 vendored 檔案至上游 c09f06d，補回 ADR 0024 patch）／`08b3ccf8`（fix(epic-33): 修正 fixed-layout.js 模組匯入為相對路徑）

## 0. 優先驗證：CBZ／FXL 開書測試

## 1. Epic 18 Issue 47（長按選字前幾影格畫面不暴跳）

## 2. Epic 25 Issue 1（畫線選取已確立時不誤觸跳頁）

## 3. Epic 27 Issue 9（no-swipe 屬性正確阻止滑動）

## 4. 直排 EPUB 連續往返翻頁精確回到原始文字錨點

## 5. 繁中流式 EPUB 橫直排即時切換錨點維持

## 6. CBZ／FXL 漫畫 RTL 頁序正確

## 7. FXL 橫向雙頁跨頁排版與封面單頁顯示正常

## 8. 劃線標註縮放後正確刷新

## 9. 總結與判定
```

把這份內容寫入 `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（若 `reviews/` 目錄不存在先建立）。

---

### Task 2：優先驗證——CBZ／FXL 開書測試

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 0. 優先驗證」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好的 App、已推送的 `sample.cbz`／`sample_fixed_layout.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

任選 Task 1 已安裝好的其中一台裝置（若現場有舊版 WebView 機型，優先在那台上做這一步，見 Global Constraints），請人類依序操作並回報：

1. 開啟 App → 圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample.cbz` → 開啟這本書。
2. 觀察是否能正常顯示第一頁畫面（不是白屏、不是無限轉圈、沒有錯誤訊息彈窗）。
3. 回到圖書庫 → 匯入 → 選取 `sample_fixed_layout.epub` → 開啟這本書。
4. 觀察是否能正常顯示第一頁畫面。
5. 若任一本書開啟失敗或白屏：進入「設定 → 閱讀器 Console Log」，把畫面內容複製或截圖下來，特別留意是否出現 `Failed to resolve module specifier` 字樣（這是 `fixed-layout.js` 相對路徑 import 修正若有誤時的確切症狀）。

- [ ] **Step 2: 記錄人類回報的結果**

把 CBZ／FXL 兩本書各自的開書結果（PASS/FAIL，若 FAIL 附上 Console Log 截圖內容摘要）寫入 `review-issue-2.md` 的「## 0. 優先驗證」章節。

- [ ] **Step 3: 判斷是否繼續**

若兩本書都能正常開啟，繼續 Task 3。若任一本書開啟失敗：這代表 Issue 1 補回的 `fixed-layout.js` 相對路徑 import 修正（ADR 0025）有誤，**立即停下來**，不要繼續執行 Task 3-10，直接跳到 Task 11 的判斷分支（記錄為 FAIL 項目，評估是否 2 小時內可修復，否則走 Branch B revert）。

---

### Task 3：Epic 18 Issue 47 真機重測——橫排/直排長按選字前幾影格畫面不暴跳

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 1. Epic 18 Issue 47」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好的 App、已推送的 `sample_horizontal.epub`／`sample_long_chinese_vertical.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

任選 Task 1 已安裝好的其中一台裝置，請人類依序操作並回報觀察結果：

1. 開啟 App → 圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample_horizontal.epub` → 開啟這本書。
2. **橫排長按選字**：在正文任一段落文字上長按（按住不放，直到出現選取控點），觀察**按下的前幾個影格**畫面是否有明顯跳動/位移。
3. **橫排正常拖曳選取**：放開後，改用長按選字啟動選取，接著拖曳其中一個控點調整選取範圍，觀察拖曳過程是否流暢、有無被誤判成翻頁。
4. 回到圖書庫 → 匯入 → 選取 `sample_long_chinese_vertical.epub` → 開啟這本書，確認為直排(vertical-rl)顯示。
5. **直排長按選字**：重複步驟 2 的長按動作，觀察前幾個影格是否暴跳。
6. **直排正常拖曳選取**：重複步驟 3 的拖曳動作，觀察是否流暢。

- [ ] **Step 2: 記錄人類回報的結果**

把 4 個情境（橫排長按／橫排拖曳／直排長按／直排拖曳）各自回報的 PASS/FAIL 與具體描述寫入 `review-issue-2.md` 的「## 1. Epic 18 Issue 47」章節。若任一情境 FAIL，額外記錄人類描述的具體現象（跳動方向、大概幅度），供 Task 11 判斷是否需要 revert。

---

### Task 4：Epic 25 Issue 1 真機重測——畫線選取已確立時不誤觸跳頁

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 2. Epic 25 Issue 1」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好 App 的**至少兩台**觸控特性不同的裝置（見 Global Constraints）。

- [ ] **Step 1: 準備並交付操作步驟給人類（每台裝置都要做）**

在 Task 1 確認可用的每一台裝置上：

1. 開啟同一本書（`sample_horizontal.epub` 或 `sample_long_chinese_vertical.epub` 皆可，但所有裝置務必用同一本、同一章節位置，方便比對）。
2. 長按選取 5-10 個字，確認選取控點已顯示於選取範圍左右兩側（選取已確立的狀態）。
3. 拖曳其中一個控點調整選取範圍——先用**緩慢**速度拖曳一次，再用**明顯較快**的速度拖曳一次。每次拖曳都觀察：選取已確立後，畫面會不會被誤判成翻頁手勢而跳頁。
4. 步驟 2-3 在同一台裝置上至少重複 2 次（總共至少 2 輪慢速+快速）。
5. 進入「設定 → 閱讀器 Console Log」，把畫面內容複製或截圖下來（若過程中真的發生跳頁，這份 log 有助於後續判斷）。

- [ ] **Step 2: 記錄人類回報的結果**

把每台裝置各自的回報（是否出現跳頁、幾次重複中出現幾次、慢速/快速是否有差異）寫入 `review-issue-2.md` 的「## 2. Epic 25 Issue 1」章節，各裝置分開記錄。原始驗收標準是人類主觀判定「改善很多，可接受」而非要求 0% 重現率——若這次仍有極低機率的偶發跳頁但頻率/幅度沒有比同步前更差，記錄下來讓人類自行判斷是否算 PASS，不要自己代替人類下結論。

---

### Task 5：Epic 27 Issue 9 真機重測——no-swipe 屬性正確阻止滑動手勢

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 3. Epic 27 Issue 9」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好 App 的任一裝置。

- [ ] **Step 1: 準備並交付操作步驟給人類**

**建議直接沿用 Task 3 測試的同一台裝置**（省去重新匯入書籍的步驟）。若改用其他裝置，先執行「圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample_horizontal.epub`」把書匯入這台裝置的圖書庫，再開始下列步驟：

1. **右上角熱區長按選字**：在螢幕右上角區域的文字上長按選字，觀察是否仍會誤觸翻頁。
2. **右上角快速滑動**：在螢幕右上角區域快速滑動手指（模擬滑動手勢），觀察是否觸發翻頁（設計上滑動翻頁應完全被 `no-swipe` 停用，不論在螢幕哪個位置滑動都不該翻頁）。
3. **3×3 熱區點擊仍正常**：點擊畫面九宮格中任一觸發翻頁的格子，確認正常翻到下一頁/上一頁（`no-swipe` 只停用滑動手勢，不該影響熱區點擊翻頁）。
4. **音量鍵仍正常**：按音量上/下鍵，確認正常翻到上一頁/下一頁。

- [ ] **Step 2: 記錄人類回報的結果**

把 4 個情境的 PASS/FAIL 與描述寫入 `review-issue-2.md` 的「## 3. Epic 27 Issue 9」章節。若發現任何一項 FAIL，如實記錄，不要放寬標準。

---

### Task 6：直排核心——連續往返翻頁精確回到原始文字錨點

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 4. 直排 EPUB 連續往返翻頁精確回到原始文字錨點」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好 App、已推送的 `sample_long_chinese_vertical.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

**建議直接沿用 Task 3 測試直排情境的同一台裝置**（該裝置的圖書庫裡已經有 `sample_long_chinese_vertical.epub`）。若改用其他裝置，先匯入這本書，再請人類依序操作並回報：

1. 開啟 `sample_long_chinese_vertical.epub`（直排 vertical-rl 顯示），從書籍任一非首頁的章節中段位置開始（避免用第一頁，第一頁往回翻沒有意義）。
2. **記錄起始錨點**：抄錄或截圖目前畫面最上（直排視覺起始）一行的前 5-10 個字，作為起始文字錨點。
3. 用九宮格熱區或滑動連續**往前翻頁 5 次**（每次翻頁後稍停，確認畫面已穩定再翻下一頁）。
4. 再連續**往後翻頁 5 次**（方向相反，翻回起點）。
5. **比對終點與起點**：翻完後這一頁最上一行的文字，是否跟步驟 2 抄錄/截圖的起始錨點文字**完全一致**（不是「感覺差不多」，是逐字比對）。

- [ ] **Step 2: 記錄人類回報的結果**

把「是否精確回到起始錨點」（是/否，若否則記錄實際落在哪個位置、差了幾個字/幾頁）寫入 `review-issue-2.md` 的「## 4.」章節。判準是客觀的文字比對，不是主觀的「順不順」。**這是快速停損指標的判準之一**——若這項 FAIL，見 Global Constraints，直接進入 Task 11 的 Branch B 評估，不要繼續嘗試在後續 Task 硬修。

---

### Task 7：直排核心——繁中流式 EPUB 橫直排即時切換錨點維持

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 5. 繁中流式 EPUB 橫直排即時切換錨點維持」章節）

**Interfaces:**
- Consumes: Task 1 已安裝好 App、已推送的 `sample_long_chinese_vertical.epub`（對應上游 commit `2b6ea0a`「容器捲動離開錨點時保留錨點」，呼應 Epic 18 Issue 45）。

- [ ] **Step 1: 準備並交付操作步驟給人類**

**建議直接沿用 Task 6 測試的同一台裝置**（已有 `sample_long_chinese_vertical.epub`）。請人類依序操作並回報：

1. 開啟 `sample_long_chinese_vertical.epub`，翻到書籍中段某一頁（非首頁），確認目前為直排(vertical-rl)顯示。
2. **記錄起始錨點**：抄錄或截圖目前畫面中一段有辨識度的文字（例如某句話的前 5-10 個字）。
3. 打開版面設定面板，把排版方向從「直排」切換為「橫排」。
4. 觀察切換後畫面顯示的文字，步驟 2 記錄的那段文字是否仍在可視範圍內（不需要逐字位置完全相同，但應是同一段文字，沒有跳到書籍其他章節或明顯前後跳位）。
5. 再把排版方向從「橫排」切換回「直排」。
6. 觀察切換回來後，是否仍停留在同一段文字附近（沒有跳頁）。

- [ ] **Step 2: 記錄人類回報的結果**

把兩次切換（直→橫、橫→直）各自的結果（是否停留在同一段文字附近，PASS/FAIL）與人類描述寫入 `review-issue-2.md` 的「## 5.」章節。若切換後跳到明顯不同的章節/段落，記為 FAIL 並記錄實際跳到哪裡。

---

### Task 8：固定版面——CBZ／FXL 漫畫 RTL 頁序正確

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 6. CBZ／FXL 漫畫 RTL 頁序正確」章節）

**Interfaces:**
- Consumes: Task 2 已確認能正常開啟的 `sample.cbz`／`sample_fixed_layout.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

延續 Task 2 已開過 `sample.cbz` 的裝置，請人類依序操作並回報：

1. 開啟 `sample.cbz`（若已從 Task 2 開啟，直接繼續），觀察書籍是否以**由右至左**的頁序排列（CBZ 漫畫慣例：往左滑動/點擊左側熱區應該翻到「下一頁」，往右應該回到「上一頁」——與一般西式書籍左右相反）。
2. 連續翻頁 3-5 次，確認頁序方向前後一致，沒有中途反轉。
3. 開啟 `sample_fixed_layout.epub`（若已從 Task 2 開啟，直接繼續），確認這本書實際宣告的閱讀方向（觀察封面/內容文字排列方向），並確認翻頁順序符合該書宣告的方向（不強制要求為 RTL，但頁序需與書籍本身宣告的方向一致，不可錯亂或反向）。

- [ ] **Step 2: 記錄人類回報的結果**

把 CBZ／FXL 兩本書的頁序方向確認結果（PASS/FAIL，附上人類描述的實際翻頁方向）寫入 `review-issue-2.md` 的「## 6.」章節。

---

### Task 9：固定版面——FXL 橫向雙頁跨頁排版與封面單頁顯示正常

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 7. FXL 橫向雙頁跨頁排版與封面單頁顯示正常」章節）

**Interfaces:**
- Consumes: Task 8 已開啟的 `sample_fixed_layout.epub`（對應上游 commit `663e630`，呼應 Epic 18 Issue 19）。

- [ ] **Step 1: 準備並交付操作步驟給人類**

延續 Task 8 已開啟 `sample_fixed_layout.epub` 的裝置，請人類依序操作並回報：

1. 若裝置目前為直式(portrait)方向，將裝置旋轉為橫式(landscape)（雙頁模式通常在橫向且螢幕夠寬時觸發，若 App 有版面設定可強制開啟雙頁模式，也可以直接在設定裡開啟）。
2. 觀察書籍第一頁（封面）是否**單獨佔滿一個版面**顯示（不與第二頁並列），這是常見的「封面單頁顯示」慣例。
3. 翻到第二頁之後，觀察是否**兩頁並列**顯示為一個跨頁（雙頁模式生效）。
4. 觀察跨頁的兩頁之間排版是否正常銜接（沒有明顯的圖片被截斷在頁面邊界、沒有版面錯位或重疊）。
5. 連續翻 2-3 個跨頁，確認每次都維持雙頁並列且銜接正常。

- [ ] **Step 2: 記錄人類回報的結果**

把「封面是否單頁顯示」與「後續是否正常雙頁跨頁排版」的結果（PASS/FAIL，附描述）寫入 `review-issue-2.md` 的「## 7.」章節。

---

### Task 10：固定版面——劃線標註縮放（zoom）後正確刷新

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 8. 劃線標註縮放後正確刷新」章節）

**Interfaces:**
- Consumes: Task 8/9 已開啟的 `sample_fixed_layout.epub`（對應上游 commit `9fde61a`）。

- [ ] **Step 1: 準備並交付操作步驟給人類**

延續前面已開啟 `sample_fixed_layout.epub` 的裝置，請人類依序操作並回報：

1. 在書籍內任一頁面文字/圖片區域，長按拖曳建立一則劃線標註（依 App 既有劃線操作方式）。
2. 確認劃線建立後，覆蓋層(overlay)正確顯示在標註的位置上。
3. 用雙指縮放手勢放大畫面（zoom in）。
4. **不要手動觸發任何其他操作**（不要翻頁、不要重新整理），直接觀察：劃線覆蓋層是否已自動刷新到縮放後的正確位置（跟著文字/圖片一起放大且位置對齊，不是停留在縮放前的舊座標、也不是消失不見）。
5. 再用雙指縮放手勢縮小畫面(zoom out)回原始大小，同樣不手動觸發其他操作，觀察劃線覆蓋層是否正確刷新回原位置。

- [ ] **Step 2: 記錄人類回報的結果**

把「放大後劃線是否正確刷新」「縮小回原尺寸後是否正確刷新」兩項結果（PASS/FAIL，附描述——例如「放大後劃線位置有明顯偏移」或「劃線消失，需要手動點擊畫面才重新出現」）寫入 `review-issue-2.md` 的「## 8.」章節。判準是**不需要額外手動操作**即可看到刷新後的正確位置——若需要額外點擊/翻頁才刷新，記為 FAIL。

---

### Task 11：彙整結果並判定——全數通過則放行，否則 revert

**Files:**
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md`（填入「## 9. 總結與判定」）
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/issues.md`（Issue 2 的 `**Status:**` 行）
- 若走 Branch B（revert）：另涉及 7 個 vendored 檔案（revert 後自動還原）、`docs/epics.md`（epic-33 那一列備註）

**Interfaces:**
- Consumes: Task 2-10 記錄在 `review-issue-2.md` 的 9 節結果。
- Produces: 若走 Branch A，交給 Task 12 繼續；若走 Branch B，本 Task 即為 Issue 2 的終點，Task 12 不執行。

- [ ] **Step 1: 彙整 9 項結果，寫「## 9. 總結與判定」**

檢視 Task 2-10 記錄的 9 節結果（優先驗證＋8 項正式測試），逐項列出 PASS/FAIL，寫進 `review-issue-2.md` 最後的「## 9. 總結與判定」章節。同時記錄「舊版 WebView 機型是否有涵蓋到」（見 Global Constraints，若沒有涵蓋，如實寫「本次測試環境未涵蓋舊版 WebView 機型」，不影響其餘 9 項的判定）。

- [ ] **Step 2: 判斷分支**

- **若優先驗證＋8 項全數 PASS（含 Epic 25 Issue 1 人類主觀判定為可接受）**：在「## 9. 總結與判定」寫下「9 項全數通過，判定為 Branch A：放行」，接續執行 Task 12。
- **若有任一項 FAIL，且評估無法在 2 小時內修復**：判定為 Branch B，執行下方 Step 3-5，**不要**執行 Task 12。`design.md`「已知風險」明講「不在時間壓力下硬修」——這裡的「合理時間」由人類判斷，agent 發現 FAIL 時應如實回報現象並詢問人類「這個要嘗試修復還是直接 revert」，不要自己決定嘗試修復（可能牽動 `main.js`／`TouchIntentClassifier` 等既有橋接層邏輯，屬於需要另外走 Discovery/Plan 流程的範疇，不是這個 Issue 的工作）。

- [ ] **Step 3（僅 Branch B）：revert 兩個同步 commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git revert 08b3ccf8 --no-edit
git revert 2028baf2 --no-edit
```

Expected：產生兩個新 commit，依序（先 `08b3ccf8` 後 `2028baf2`，較新的先 revert）把 7 個 vendored 檔案還原成 Issue 1 同步前的內容（等同上游 `6c6a491` 版本）。`08b3ccf8` 的 diff 除了 `fixed-layout.js` 也附帶更新過 `plans/plan-issue-1.md` 的進度勾選，revert 會連帶把那些勾選改回未勾選——這是預期中的連帶影響，**不要**額外修改 `plan-issue-1.md` 的勾選狀態，Issue 1「已完成」的事實記錄在 `issues.md` 的 Status 文字，不受這裡影響。用 `git status` 確認變更範圍只涉及 `app/android/app/src/main/assets/foliate/` 的 7 個檔案與 `plans/plan-issue-1.md`。

- [ ] **Step 4（僅 Branch B）：更新 `docs/epics.md` 反映回退狀態**

在 `docs/epics.md` 第 56 行 `epic-33-foliate-js-vendor-sync` 那一列的描述文字後面，補上一段說明：Issue 2 真機重測發現回歸（具體列出哪幾項 FAIL），已 `git revert` 退回 Issue 1 同步前狀態（`6c6a491`），待重新評估後續處理方式；狀態維持 🟡 開發中 (Active) 不變。**不要**去改 `docs/research/foliate_js_sync_update_strategy.md` 的 Pinned Commit（那份文件應該繼續記錄目前實際生效的版本，同步已回退代表它沒變過，仍是 `6c6a491`）。

- [ ] **Step 5（僅 Branch B）：更新 `issues.md` Issue 2 狀態並 commit**

在 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` Issue 2 的 `**Status:** ready-for-agent` 行，改為記錄「已執行但觸發 revert」，簡述哪幾項真機測試 FAIL、revert 的兩個 commit hash。

```bash
git add docs/epics/epic-33-foliate-js-vendor-sync/issues.md docs/epics.md
git commit -m "$(cat <<'EOF'
docs(epic-33): Issue 2 真機重測發現回歸，已 revert 同步 commit

真機重測 <列出實際 FAIL 的項目> 未通過，依 design.md「不在時間壓力下
硬修」原則，git revert 08b3ccf8、2028baf2，退回 Issue 1 同步前狀態
（等同上游 6c6a491）。pinned commit 文件未變更（仍為 6c6a491）。
EOF
)"
```

Branch B 到此結束，不執行 Task 12。

---

### Task 12：文件收尾（僅當 Task 11 判定為 Branch A 時執行）

**Files:**
- Modify: `docs/research/foliate_js_sync_update_strategy.md`（2.1 節 Pinned Commit）
- Modify: `docs/epics.md`（epic-33 那一列）
- Modify: `docs/epics/epic-33-foliate-js-vendor-sync/issues.md`（Issue 2 狀態）

**Interfaces:** 無（純文件更新，收尾本工單）。

- [ ] **Step 1: 查詢上游 `c09f06d` 的完整 40 碼 SHA 與作者日期**

```bash
curl -sS "https://api.github.com/repos/readest/foliate-js/commits/c09f06d" | grep -E '"sha"|"date"' | head -4
```

Expected：印出完整 40 碼 SHA（以 `c09f06d` 開頭）與至少一組 `date` 欄位（author/committer 日期，取 `author` 的日期，比照 `docs/research/foliate_js_sync_update_strategy.md` 既有慣例記錄「commit 自己的日期」而非本地同步日期）。

- [ ] **Step 2: 更新 Pinned Commit 記錄**

`docs/research/foliate_js_sync_update_strategy.md` 目前「2.1 上游來源與當前釘定狀態」內容：

```
- **當前 Pinned Commit**：`6c6a491cf540696182d6fae70d6e26879b1e8369` (2026-07-25)
```

改為 Step 1 查得的完整 SHA 與日期（格式比照原本這一行，`c09f06d` 開頭的完整 40 碼＋括號內的作者日期）。

- [ ] **Step 3: 更新 `docs/epics.md` 第 56 行 epic-33 那一列的描述**

在該列描述文字最後（目前結尾是「**Issue 2（8 項真機深度驗收＋文件收尾）可以開始**，依賴已解除。」），補上一段說明：Issue 2 已完成，9 項真機驗證（優先驗證＋8 項正式測試）全數通過，記錄於 `reviews/review-issue-2.md`；`docs/research/foliate_js_sync_update_strategy.md` Pinned Commit 已更新為 `c09f06d`。狀態仍維持 🟡 開發中 (Active)，**不要**改成 🟢 已歸檔（歸檔是人類指定的動作，見 Global Constraints）。

- [ ] **Step 4: 更新 `issues.md` Issue 2 狀態**

在 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` Issue 2 的 `**Status:** ready-for-agent` 行，改為記錄已完成，簡述 9 項真機測試結果與測試裝置。

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add docs/research/foliate_js_sync_update_strategy.md docs/epics.md docs/epics/epic-33-foliate-js-vendor-sync/issues.md
git commit -m "$(cat <<'EOF'
docs(epic-33): Issue 2 真機重測通過，更新版本紀錄與看板

CBZ／FXL 優先驗證，以及 Epic 18 Issue 47／Epic 25 Issue 1／Epic 27
Issue 9 三個歷史修法、直排連續翻頁對稱、橫直排切換錨點維持、CBZ／FXL
RTL 頁序、FXL 雙頁跨頁與封面單頁、劃線標註縮放刷新，共 9 項真機驗證
全數通過，記錄於
docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-issue-2.md。

更新 docs/research/foliate_js_sync_update_strategy.md 的 Pinned Commit
為 c09f06d 完整 SHA；docs/epics.md 更新 epic-33 該列反映 Issue 1/2 皆
已完成，待人類確認歸檔。
EOF
)"
```

---

## Self-Review（撰寫計劃階段自我檢查）

- **Spec 覆蓋**：`design.md`「目標」第 3 項（8 項真機重測，含優先驗證）→ Task 2-10；「目標」第 4 項（版本紀錄文件更新）→ Task 12；「測試策略」第三層 8 項矩陣逐一對應 Task 3（Epic 18 Issue 47）／Task 4（Epic 25 Issue 1）／Task 5（Epic 27 Issue 9）／Task 6（直排連續翻頁）／Task 7（橫直排切換錨點）／Task 8（CBZ／FXL RTL）／Task 9（FXL 雙頁跨頁封面）／Task 10（劃線縮放刷新）；「已知風險」快速停損指標 → Global Constraints＋Task 6 Step 2＋Task 11。`issues.md` Issue 2「優先驗證項目」→ Task 2，且明訂排在其餘 Task 之前並可提前中止流程。無遺漏。
- **佔位符掃描**：全文未使用 TBD／TODO／「適當處理」等字眼；所有給人類的操作步驟皆為具體可執行的動作清單，不是抽象描述；revert 目標 commit hash（`2028baf2`／`08b3ccf8`）已用 `git log` 實際查證，不是憑印象猜測；Pinned Commit 完整 SHA 改用 Task 12 Step 1 現場查詢 GitHub API 取得，不在計畫裡杜撰。
- **型別/簽章一致性**：`review-issue-2.md` 的 9 個章節標題在 Task 1 Step 5（骨架建立）與 Task 2-11（逐節填入指示）用詞完全一致（含編號）；測試書籍檔名（`sample_horizontal.epub`／`sample_long_chinese_vertical.epub`／`sample.cbz`／`sample_fixed_layout.epub`）在 Task 1 推送步驟與後續各 Task 的 Consumes 一致。
- **裝置策略澄清**：規劃階段已用 `AskUserQuestion` 向人類確認裝置清單不固定，計畫已改為 Task 1 現場用 `adb devices -l` 盤點、Global Constraints 明訂 Epic 25 Issue 1 需要至少兩台裝置且現場不足要停下詢問，不寫死任何特定型號（不同於 `epic-32` Issue 3 先例當時已知手邊裝置的情況）。
