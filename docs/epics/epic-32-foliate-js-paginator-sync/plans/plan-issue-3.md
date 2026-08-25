# Epic 32 Issue 3：真機 QA＋文件收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真實 Android 裝置上重新驗證 3 個依賴 `paginator.js` 觸控內部行為的歷史修法（Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9）在 Issue 2 換上新版 `paginator.js`（`6c6a491`）後沒有回歸，加一項直排連續翻頁 smoke test，把結果記錄下來；全數通過後更新版本紀錄文件收尾，若有無法在合理時間內修復的回歸則 `git revert` 退回。

**Architecture:** 本工單**不是**寫程式，是「建置測試版 App → 人工在實體裝置上操作 → 記錄結果 → 依結果二選一分支（文件收尾 或 revert）」。design.md 已明確排除 Puppeteer 自動化（這個環境對 `touchmove` 場景不可靠），且歷史上這 3 個修法原始驗收標準本來就是人類拿實體裝置判斷（例如 Epic 25 Issue 1 最終是「人類明確確認接受」），不是可以用 assert 自動判定的東西——所以本計劃的每個測試步驟都需要**人類實際拿裝置操作、agent 記錄人類回報的結果**，agent 自己不能單獨完成判定。

**Tech Stack:** Flutter（`flutter build apk --debug`）、adb（安裝 APK、推送測試書籍、確認裝置清單；不支援 adb 的裝置改用 USB/MTP 手動側載，見 Global Constraints）、Git（`git revert`）。

**Spec:** `docs/epics/epic-32-foliate-js-paginator-sync/design.md`（「目標」第 4/5 項、「測試策略」）；工單描述見 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 3。

## Global Constraints

- **執行環境為 Windows，本計劃所有 shell 指令一律使用 Bash 工具（Git Bash）執行**，不要改用 PowerShell 工具或 cmd.exe（延續 Issue 2 計劃的既有作法，已在這台機器上驗證 `curl`／`grep`／`git` 皆正常）。`adb`／`flutter` 指令兩種工具下都能跑，但為了跟 Issue 1/2 的既有指令風格一致，一律用 Bash 工具執行。
- **每一項真機測試都需要人類實際操作裝置並回報觀察結果**——agent 的角色是準備建置/測試素材、把明確的操作步驟交給人類、如實記錄人類回報的 PASS/FAIL 與描述，**不能自行用 adb 合成觸控事件來代替人類判斷**（`adb shell input touchscreen swipe` 這類指令是瞬間跳轉座標，不會複製真實觸控的按壓時長/速度曲線，無法用來驗證這 3 個修法的判定邏輯，等於没測到重點）。若某個 Step 卡在「需要人類回報才能繼續」，就停下來詢問，不要自己編造結果。
- **`git revert` 的目標是本地 commit `769aba7`（Issue 2 的同步 commit），不是上游 hash `dd71f2be356563c16a23272686189fcfb45d0b82`**——這個上游 hash 在本地 git 物件庫裡不存在（規劃階段已用 `git cat-file -t` 確認 `fatal: could not get object info`），design.md 說「退回 `dd71f2b`」指的是「revert 後 `paginator.js` 的內容會等同上游那個版本」，不是一個可以直接 checkout/reset 的本地目標。
- **歸檔（把 `docs/epics/epic-32-foliate-js-paginator-sync/` 整個資料夾搬到 `docs/archive/`）是人類指定的動作**（`sdd-workflow` skill 生命週期第 7 步），本工單只更新 `docs/epics.md` 的文字描述反映 3 個 Issue 皆完成，**不**執行 `git mv` 搬移資料夾、**不**把狀態圖示改成 🟢 已歸檔。
- `docs/epics/epic-32-foliate-js-paginator-sync/reviews/` 已加進根目錄 `.gitignore`（第 17 行），本工單要求的 `reviews/review-issue-3.md` 寫在這個目錄下即可，**不需要**（實際上 `git add` 也不會有效果）把它加進 commit。
- 若真機測試發現回歸：**不在時間壓力下硬修**，直接進入 Task 6 的 revert 分支（design.md 原文，`epic-31` 可以繼續等）。
- 只使用 `app/test/fixtures/` 底下既有的測試書籍，不新增書籍檔案。
- **Air Reader Pro C 不支援 `adb`**（已跟人類確認）。這台裝置的 APK 安裝／測試書籍傳輸改用 **USB/MTP 隨身碟模式**：接上 Windows 後裝置會被系統認成一台可攜式裝置（在檔案總管「本機」下面看到裝置名稱，不是磁碟機代號）。**MTP 不是標準檔案系統，Bash／PowerShell 的檔案複製指令（`cp`／`Copy-Item`／`robocopy`）對它不可靠**，這台裝置的檔案傳輸步驟一律由人類在 Windows 檔案總管手動拖曳完成，agent 不要嘗試寫指令碼自動化這一段（見 Task 1 Step 3b／4b）。其餘裝置（含 TCL 14 吋，若確認支援 adb）仍照 Step 3a／4a 用 `adb` 處理。

---

### Task 1：建置測試版 App、確認裝置到位、準備測試書籍

**Files:**
- Create: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（骨架，後續 Task 2-5 逐節填入結果）

**Interfaces:**
- Produces: `review-issue-3.md` 內 4 個章節標題（`## 1. Epic 18 Issue 47`／`## 2. Epic 25 Issue 1`／`## 3. Epic 27 Issue 9`／`## 4. 直排連續翻頁 smoke test`），供 Task 2-5 各自填入該節內容；`app-debug.apk`（`app/build/app/outputs/flutter-apk/app-debug.apk`）供 Task 2-5 安裝到裝置。

- [ ] **Step 1: 確認目前連線的裝置清單**

```bash
adb devices -l
```

Expected：列出所有**支援 adb** 的已連線裝置（例如 TCL 14 吋，若已確認支援）。**Air Reader Pro C 不支援 adb，不會出現在這份清單裡，這是正常現象，不代表沒接上**——這台裝置改用下方 Step 3b／4b 的 MTP 流程處理，另外請人類確認：Windows 檔案總管的「本機」底下有沒有看到 Air Reader Pro C 的裝置圖示（接上 USB 後，若裝置跳出「USB 用途」通知，選擇「檔案傳輸」而非「僅供充電」，否則檔案總管看不到它）。

Epic 25 Issue 1 這兩台裝置（Air Reader Pro C／TCL 14 吋）是 design.md 明確指名、缺一不可的機型——若其中一台（不論哪種連線方式）目前不在身邊，**停下來**請人類先準備好再繼續，不要用其他機型代替（原始症狀本來就是「其中一台會跳頁、另一台不會」，用別的機型測不出這個回歸）。

- [ ] **Step 2: 建置 debug APK**

```bash
cd app && flutter build apk --debug
```

Expected：成功產出 `app/build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 3a: 把 APK 安裝到每一台支援 adb 的裝置**

對 Step 1 確認到的每個 adb 裝置序號（例如 TCL 14 吋，以及其他有連線、方便一併測 Task 2/4/5 的裝置）執行：

```bash
adb -s <device-id> install -r app/build/app/outputs/flutter-apk/app-debug.apk
```

Expected：每台都印出 `Success`。

- [ ] **Step 3b（僅 Air Reader Pro C，人類手動操作）：透過 MTP 側載 APK**

請人類依序操作：

1. USB 接上 Windows，確認裝置的 USB 連線模式為「檔案傳輸」（見 Step 1 說明）。
2. 打開 Windows 檔案總管，進入 Air Reader Pro C 這台裝置的儲存空間，找到（或新建）`Download` 資料夾。
3. 把 `app/build/app/outputs/flutter-apk/app-debug.apk`（Windows 路徑：`U:\MyDeveloper\AI\elinkBook\app\build\app\outputs\flutter-apk\app-debug.apk`）拖曳複製進裝置的 `Download` 資料夾。
4. 在裝置上打開內建的檔案管理員 App，導覽到 `Download` 資料夾，點擊 `app-debug.apk`。
5. 若系統跳出「已封鎖安裝」或「不明來源」警告，先到裝置的「設定 → 安全性（或應用程式）→ 允許安裝不明來源應用程式」，針對目前使用的檔案管理員 App 開啟允許，再回頭重新點擊該 APK 完成安裝。
6. 若裝置上已經裝過舊版（例如 Issue 1/2 之前測試留下的），系統會問是否要「更新」，選擇更新即可（等同 `adb install -r` 的覆蓋安裝效果）。

Expected：Air Reader Pro C 的主畫面出現這個 App 的圖示，可以正常開啟。

- [ ] **Step 4a: 推送測試書籍到每台支援 adb 的裝置**

```bash
adb -s <device-id> push app/test/fixtures/sample_long_chinese_vertical.epub /sdcard/Download/
adb -s <device-id> push app/test/fixtures/sample_horizontal.epub /sdcard/Download/
```

Expected：兩個檔案都成功推送到每台裝置的 `/sdcard/Download/`。

- [ ] **Step 4b（僅 Air Reader Pro C，人類手動操作）：透過 MTP 複製測試書籍**

延續 Step 3b 開著的檔案總管視窗，把 `app/test/fixtures/sample_long_chinese_vertical.epub` 與 `app/test/fixtures/sample_horizontal.epub`（Windows 路徑：`U:\MyDeveloper\AI\elinkBook\app\test\fixtures\`）一併拖曳複製進裝置的同一個 `Download` 資料夾（跟 APK 放在一起即可）。

Expected：裝置的 `Download` 資料夾裡看到這兩個 `.epub` 檔案。`sample_long_chinese_vertical.epub` 供 Task 2 的直排情境與 Task 5 的 smoke test 使用；`sample_horizontal.epub` 供 Task 2 的橫排情境使用。Task 3／Task 4 沿用同一批已匯入的書即可，不需要另外準備。

- [ ] **Step 5: 建立 `review-issue-3.md` 骨架**

```markdown
# Epic 32 Issue 3 — 真機重測報告

**測試日期**：<填入實際執行日期>
**測試裝置**：<逐台列出型號與連線方式，至少含 Air Reader Pro C（USB/MTP 側載）／TCL 14 吋（adb 序號 <device-id>）>
**對應同步 commit**：`769aba7`（chore(epic-32): 同步 paginator.js 至上游 6c6a491）

## 1. Epic 18 Issue 47（長按選字前幾影格畫面不暴跳）

## 2. Epic 25 Issue 1（畫線選取已確立時不誤觸跳頁）

## 3. Epic 27 Issue 9（no-swipe 屬性正確阻止滑動手勢）

## 4. 直排連續翻頁 smoke test

## 5. 總結與判定
```

把這份內容寫入 `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（若 `reviews/` 目錄不存在先建立）。

---

### Task 2：Epic 18 Issue 47 真機重測——橫排/直排長按選字前幾影格畫面不暴跳

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（填入本節結果）

**Interfaces:**
- Consumes: Task 1 已安裝好的 App、已推送的 `sample_horizontal.epub`／`sample_long_chinese_vertical.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

任選 Task 1 已安裝好的其中一台裝置（不需要特定機型——原始 Issue 47 驗證時「未指名特定機型」），請人類依序操作並回報觀察結果：

1. 開啟 App → 圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample_horizontal.epub` → 開啟這本書。
2. **橫排長按選字**：在正文任一段落文字上長按（按住不放，直到出現選取控點），觀察**按下的前幾個影格**畫面是否有明顯跳動/位移。
3. **橫排正常拖曳選取**：放開後，改用長按選字啟動選取，接著拖曳其中一個控點調整選取範圍，觀察拖曳過程是否流暢、有無被誤判成翻頁。
4. 回到圖書庫 → 匯入 → 選取 `sample_long_chinese_vertical.epub` → 開啟這本書，確認為直排(vertical-rl)顯示。
5. **直排長按選字**：重複步驟 2 的長按動作，觀察前幾個影格是否暴跳。
6. **直排正常拖曳選取**：重複步驟 3 的拖曳動作，觀察是否流暢。

- [ ] **Step 2: 記錄人類回報的結果**

把人類針對 4 個情境（橫排長按／橫排拖曳／直排長按／直排拖曳）各自回報的 PASS/FAIL 與具體描述（例如「長按後畫面沒有跳動，直接顯示選取控點」或「長按後畫面先往下跳了一下才穩定」），逐項寫入 `review-issue-3.md` 的「## 1. Epic 18 Issue 47」章節。若任一情境 FAIL，額外記錄人類描述的具體現象（跳動方向、大概幅度），供 Task 6 判斷是否需要 revert。

---

### Task 3：Epic 25 Issue 1 真機重測——畫線選取已確立時不誤觸跳頁

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（填入本節結果）

**Interfaces:**
- Consumes: Task 1 已安裝好 App 的 **Air Reader Pro C**、**TCL 14 吋**兩台裝置。

- [ ] **Step 1: 準備並交付操作步驟給人類（兩台裝置都要做）**

在 **Air Reader Pro C** 與 **TCL 14 吋** 各自：

1. 開啟同一本書（`sample_horizontal.epub` 或 `sample_long_chinese_vertical.epub` 皆可，兩台裝置務必用同一本、同一章節位置，方便比對）。
2. 長按選取 5-10 個字，確認選取控點已顯示於選取範圍左右兩側（選取已確立的狀態）。
3. 拖曳其中一個控點調整選取範圍——先用**緩慢**速度拖曳一次，再用**明顯較快**的速度拖曳一次。每次拖曳都觀察：選取已確立後，畫面會不會被誤判成翻頁手勢而跳頁。
4. 步驟 2-3 在同一台裝置上至少重複 2 次（總共至少 2 輪慢速+快速）。
5. 進入「設定 → 閱讀器 Console Log」，把畫面內容複製或截圖下來（若過程中真的發生跳頁，這份 log 有助於後續判斷）。

- [ ] **Step 2: 記錄人類回報的結果**

把兩台裝置各自的回報（是否出現跳頁、幾次重複中出現幾次、慢速/快速是否有差異）寫入 `review-issue-3.md` 的「## 2. Epic 25 Issue 1」章節，兩台裝置分開記錄。原始驗收標準是人類主觀判定「改善很多，可接受」而非要求 0% 重現率——若這次仍有極低機率的偶發跳頁但頻率/幅度沒有比 Issue 2 同步前更差，記錄下來讓人類自行判斷是否算 PASS，不要自己代替人類下結論。

---

### Task 4：Epic 27 Issue 9 真機重測——no-swipe 屬性正確阻止滑動手勢

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（填入本節結果）

**Interfaces:**
- Consumes: Task 1 已安裝好 App 的任一裝置。

- [ ] **Step 1: 準備並交付操作步驟給人類**

**建議直接沿用 Task 2 測試的同一台裝置**（省去重新匯入書籍的步驟）。若改用其他裝置，先執行「圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample_horizontal.epub`」把書匯入這台裝置的圖書庫，再開始下列步驟：

1. **右上角熱區長按選字**：original 回報的「特定情境」具體是**螢幕右上角區域**（直排中文閱讀順序讓選字落點集中在這裡，也剛好是翻頁熱區）。在螢幕右上角區域的文字上長按選字，觀察是否仍會誤觸翻頁。
2. **右上角快速滑動**：在螢幕右上角區域快速滑動手指（模擬滑動手勢），觀察是否觸發翻頁（設計上滑動翻頁應完全被 `no-swipe` 停用，不論在螢幕哪個位置滑動都不該翻頁）。
3. **3×3 熱區點擊仍正常**：點擊畫面九宮格中任一觸發翻頁的格子，確認正常翻到下一頁/上一頁（`no-swipe` 只停用滑動手勢，不該影響熱區點擊翻頁）。
4. **音量鍵仍正常**：按音量上/下鍵，確認正常翻到上一頁/下一頁。

- [ ] **Step 2: 記錄人類回報的結果**

把 4 個情境的 PASS/FAIL 與描述寫入 `review-issue-3.md` 的「## 3. Epic 27 Issue 9」章節。研究階段已確認這個修法原本合併時「真機驗證」只是建議、非強制勾選項——這次是它第一次被真正驗收，若發現任何一項 FAIL，如實記錄，不要因為「反正原本就沒真的驗過」而放寬標準。

---

### Task 5：額外 smoke test——直排連續翻頁 5 次+反向 5 次精確回到原始文字錨點

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（填入本節結果）

**Interfaces:**
- Consumes: Task 1 已安裝好 App、已推送的 `sample_long_chinese_vertical.epub`。

- [ ] **Step 1: 準備並交付操作步驟給人類**

**建議直接沿用 Task 2 測試直排情境的同一台裝置**（該裝置的圖書庫裡已經有 `sample_long_chinese_vertical.epub`）。若改用其他裝置，先執行「圖書庫 → 匯入 → 選擇檔案 → 導覽到 `Download` 資料夾 → 選取 `sample_long_chinese_vertical.epub`」把書匯入，再請人類依序操作並回報：

1. 開啟 `sample_long_chinese_vertical.epub`（直排 vertical-rl 顯示），從書籍任一非首頁的章節中段位置開始（避免用第一頁，第一頁往回翻沒有意義）。
2. **記錄起始錨點**：抄錄或截圖目前畫面最上（直排視覺起始）一行的前 5-10 個字，作為起始文字錨點。
3. 用九宮格熱區或滑動連續**往前翻頁 5 次**（每次翻頁後稍停，確認畫面已穩定再翻下一頁）。
4. 再連續**往後翻頁 5 次**（方向相反，翻回起點）。
5. **比對終點與起點**：翻完後這一頁最上一行的文字，是否跟步驟 2 抄錄/截圖的起始錨點文字**完全一致**（不是「感覺差不多」，是逐字比對）。

- [ ] **Step 2: 記錄人類回報的結果**

把「是否精確回到起始錨點」（是/否，若否則記錄實際落在哪個位置、差了幾個字/幾頁）寫入 `review-issue-3.md` 的「## 4. 直排連續翻頁 smoke test」章節。判準是客觀的文字比對，不是主觀的「順不順」。

---

### Task 6：彙整結果並判定——全數通過則放行，否則 revert

**Files:**
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md`（填入「## 5. 總結與判定」）
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/issues.md`（Issue 3 的 `**Status:**` 行）
- 若走 Branch B（revert）：另涉及 `app/android/app/src/main/assets/foliate/paginator.js`（revert 後自動還原）、`docs/epics.md`（epic-32 那一列備註）

**Interfaces:**
- Consumes: Task 2-5 記錄在 `review-issue-3.md` 的 4 節結果。
- Produces: 若走 Branch A，交給 Task 7 繼續；若走 Branch B，本 Task 即為 Issue 3 的終點，Task 7 不執行。

- [ ] **Step 1: 彙整 4 項測試結果，寫「## 5. 總結與判定」**

檢視 Task 2-5 記錄的 4 節結果，逐項列出 PASS/FAIL，寫進 `review-issue-3.md` 最後的「## 5. 總結與判定」章節。

- [ ] **Step 2: 判斷分支**

- **若 4 項全數 PASS（含 Epic 25 Issue 1 人類主觀判定為可接受）**：在「## 5. 總結與判定」寫下「4 項全數通過，判定為 Branch A：放行」，接續執行 Task 7。
- **若有任一項 FAIL，且評估無法在合理時間內修復**：判定為 Branch B，執行下方 Step 3-5，**不要**執行 Task 7。design.md 明講「不在時間壓力下硬修」——這裡的「合理時間」由人類判斷，agent 發現 FAIL 時應如實回報現象並詢問人類「這個要嘗試修復還是直接 revert」，不要自己決定嘗試修復（可能牽動 `main.js`／`tap_zone_detector.dart` 等既有橋接層邏輯，屬於需要另外走 Discovery/Plan 流程的範疇，不是這個 Issue 的工作）。

- [ ] **Step 3（僅 Branch B）：revert 同步 commit**

```bash
git revert 769aba7 --no-edit
```

Expected：產生一個新 commit，把 `app/android/app/src/main/assets/foliate/paginator.js` 還原成 Issue 2 同步前的內容（等同上游 `dd71f2b` 版本）。用 `git status`／`wc -l app/android/app/src/main/assets/foliate/paginator.js` 確認行數變回 `3504`。

- [ ] **Step 4（僅 Branch B）：更新 `docs/epics.md` 反映回退狀態**

在 `docs/epics.md` 第 55 行 `epic-32-foliate-js-paginator-sync` 那一列的備註文字後面，補上一段說明：Issue 3 真機重測發現回歸（具體列出哪幾項 FAIL），已 `git revert` 退回同步前狀態，待重新評估後續處理方式；狀態維持 🟡 開發中 (Active) 不變。**不要**移除 `epic-31` 那一列的「暫緩實作」備註——同步已回退，Epic 31 的 blocker（上游 `paginator.js` 尚待確認）依然存在。**不要**去改 `docs/research/foliate_js_sync_update_strategy.md` 的 Pinned Commit（那份文件應該繼續記錄目前實際生效的版本，同步已回退代表它沒變過）。

- [ ] **Step 5（僅 Branch B）：更新 `issues.md` Issue 3 狀態並 commit**

在 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 3 的 `**Status:** ready-for-agent` 行，改為記錄「已執行但觸發 revert」，簡述哪幾項真機測試 FAIL、revert 的 commit hash。

```bash
git add docs/epics/epic-32-foliate-js-paginator-sync/issues.md docs/epics.md
git commit -m "$(cat <<'EOF'
docs(epic-32): Issue 3 真機重測發現回歸，已 revert 同步 commit

真機重測 <列出實際 FAIL 的項目> 未通過，依 design.md「不在時間壓力下硬修」
原則，git revert 769aba7 退回同步前狀態。epic-31 的暫緩備註維持不動
（blocker 依然存在），pinned commit 文件未變更。
EOF
)"
```

Branch B 到此結束，不執行 Task 7。

---

### Task 7：文件收尾（僅當 Task 6 判定為 Branch A 時執行）

**Files:**
- Modify: `docs/research/foliate_js_sync_update_strategy.md`（2.1 節 Pinned Commit）
- Modify: `docs/epics.md`（epic-31、epic-32 兩列）
- Modify: `docs/epics/epic-32-foliate-js-paginator-sync/issues.md`（Issue 3 狀態）

**Interfaces:** 無（純文件更新，收尾本工單）。

- [ ] **Step 1: 更新 Pinned Commit 記錄**

`docs/research/foliate_js_sync_update_strategy.md` 目前「2.1 上游來源與當前釘定狀態」內容：

```
- **當前 Pinned Commit**：`dd71f2be356563c16a23272686189fcfb45d0b82` (2026-07-19)
```

改為（`6c6a491cf540696182d6fae70d6e26879b1e8369` 為完整 40 碼 SHA，已用 GitHub API 查證；`2026-07-25` 是這個 commit 在上游的原始作者日期，比照既有欄位「記錄上游 commit 自己的日期」而非本地同步日期的既有慣例）：

```
- **當前 Pinned Commit**：`6c6a491cf540696182d6fae70d6e26879b1e8369` (2026-07-25)
```

- [ ] **Step 2: 移除 `docs/epics.md` 第 54 行 epic-31 那一列的「暫緩實作」備註**

目前該列備註結尾含這段文字：

```
**暫緩實作**：規劃階段發現上游 `paginator.js` 已大幅重寫（見 `epic-32`），人類決定先完成上游同步，回頭確認新版 `paginator.js` 觸控行為後再繼續 Epic 31。
```

把這段整句刪除（epic-31 這個 blocker 已解除，該列其餘描述文字——Discovery/`design.md`/`issues.md`/`plans/plan-issue-1.md` 進度——維持不動）。

- [ ] **Step 3: 更新 `docs/epics.md` 第 55 行 epic-32 那一列的描述**

目前該列描述結尾是：

```
...驗收標準明確納入上述 3 個歷史修法的真機重測。待人類審閱 `design.md` 後進入 Scrum Master 階段。
```

改為（反映 Issue 1-3 皆完成，狀態仍維持 🟡 開發中 (Active)，**不要**改成 🟢 已歸檔——歸檔是人類指定的動作，見 Global Constraints）：

```
...驗收標準明確納入上述 3 個歷史修法的真機重測。Issue 1（`3e82e23`）／Issue 2（`769aba7`）／Issue 3 皆已完成：`paginator.js` 已同步至 `6c6a491`，4 項真機重測全數通過（記錄於 `reviews/review-issue-3.md`），`docs/research/foliate_js_sync_update_strategy.md` Pinned Commit 已更新，`epic-31` 暫緩備註已移除、可繼續。待人類確認歸檔。
```

- [ ] **Step 4: 更新 `issues.md` Issue 3 狀態**

在 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 3 的 `**Status:** ready-for-agent` 行，改為記錄已完成，簡述 4 項真機測試結果與測試裝置。

- [ ] **Step 5: Commit**

```bash
git add docs/research/foliate_js_sync_update_strategy.md docs/epics.md docs/epics/epic-32-foliate-js-paginator-sync/issues.md
git commit -m "$(cat <<'EOF'
docs(epic-32): Issue 3 真機重測通過，更新版本紀錄與看板

Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9 三個依賴 paginator.js
觸控內部行為的歷史修法，經 Air Reader Pro C／TCL 14 吋等真機重測全數
通過，另加直排連續翻頁 smoke test 通過，記錄於
docs/epics/epic-32-foliate-js-paginator-sync/reviews/review-issue-3.md。

更新 docs/research/foliate_js_sync_update_strategy.md 的 Pinned Commit
為 6c6a491cf540696182d6fae70d6e26879b1e8369 (2026-07-25)；docs/epics.md
移除 epic-31 的暫緩備註（blocker 已解除）、更新 epic-32 該列反映 3 個
Issue 皆已完成，待人類確認歸檔。
EOF
)"
```
