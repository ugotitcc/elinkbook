# Issue 17：Spike——強制 FXL 覆蓋本專案檢查點後，`EpubNavigatorFragment` 是否真的會渲染成 FXL 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 驗證 Issue 16 的核心不確定性——`EpubReaderView.kt` 有 3 個各自獨立讀取 `publication.metadata.layout == Layout.FIXED` 的檢查點，但真正決定 WebView 渲染模式（FXL 左右並排 vs. reflowable 單欄連續捲動）的是 Readium 官方元件 `EpubNavigatorFragment`，其 `Configuration` 沒有任何欄位可以覆寫它自己對書本 metadata 的獨立判讀。本 Issue 用最小範圍的硬編碼（不寫完整 Dart→Kotlin 旗標傳遞管線）驗證：覆寫本專案自己的 3 個檢查點後，`EpubNavigatorFragment` 是否真的會跟著渲染成 FXL。

**架構：** 比照 ADR 0011／Issue 8 既有的 Spike-first 方法論：先在真機上建立「問題確實存在」的基準觀察（Task 1），再套用最小範圍的硬編碼修改重新驗證（Task 2），依真機觀察結果記錄明確的 GO/NO-GO 判定（Task 3），硬編碼修改**不進 `main`**、驗證後即 revert。GO/NO-GO 皆不在本 Issue 內實作永久修法——那屬於 GO 之後的新工單範圍（比照 Issue 8→10 模式）。

**Tech Stack：** Kotlin（`EpubReaderView.kt`）、Android 原生建置（`flutter build apk --debug`）、真機人工驗證（`adb install`）。本 Issue **不涉及**任何 Dart/Flutter 程式碼變更，也沒有可自動化的 `flutter test` 覆蓋範圍（驗證對象是 Readium 官方元件的真實渲染行為，只能真機肉眼確認）。

## Global Constraints

- **不修改 `readium-kotlin-toolkit` 本身**（第三方官方 library，非本專案程式碼），比照本 Epic 對 `readest/foliate-js` 的既有態度——只在 `EpubReaderView.kt` 這一個檔案內做硬編碼實驗。
- **硬編碼修改全程不 commit**。Task 1 完成基準觀察後才開始 Task 2 的硬編碼，Task 2/Task 3 之間的硬編碼狀態用 `git diff`/`git status` 追蹤，Task 3 結束前必須 `git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` revert 乾淨——不像 Issue 8 的 Task 3A/3B 是「驗證通過後轉正、寫測試、commit」，本 Issue 驗證通過與否都只留下 Spike 報告本身，程式碼修改一律不留痕跡。
- 需要一台已連接、已授權 USB 偵錯的真實 Android 裝置（`3CEF42ECD491687`，本專案既有測試裝置）——WebView/Readium 渲染行為在模擬器與真機上可能不同，且這正是本 Epic 一貫的真機驗證慣例。
- 沿用 Issue 15 真機驗收時已知會被誤判為流式的同一本漫畫 EPUB（若該書已不在裝置上或找不到，需要先確認/重新匯入同一本書，不得換書——換書會讓「同一個問題」的驗證失去對照基準）。
- 每次修改 Kotlin 原生程式碼後，**必須**完整重新建置＋安裝（`flutter build apk --debug` + `adb install -r`），熱重載/熱重啟不會反映原生程式碼變更。

---

## 檔案結構

本計劃只涉及一個檔案，且變更全程不 commit：

- **暫時修改（不 commit）：** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（3 處，見 Task 2）

---

### Task 1：真機重現現況（基準觀察，修改前）

**Files:** 無（本 Task 不變更任何程式碼，純粹建立「問題確實存在」的基準觀察，比照 Issue 8 Task 1 既有模式）。

**Interfaces:**
- Consumes: 無
- Produces:「Spike 紀錄」第 1 節的基準觀察結果，供 Task 2 比對

- [x] **Step 1: 確認真機已連接**

執行：
```bash
flutter devices
```
預期：列出裝置 `3CEF42ECD491687`。

- [x] **Step 2: 確認目前 `main` 分支的 debug APK 已安裝在裝置上**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 3: 確認測試書籍已在裝置圖書庫中，且已套用「強制 FXL」**

開啟 App，找到 Issue 15 真機驗收時已知會被誤判為流式的那本漫畫 EPUB。若尚未對它套用過「強制 FXL」（`Book.isFixedLayout` 尚未被覆寫為 `true`），先於書架多選模式下選取該書、點擊「強制 FXL」。

- [x] **Step 4: 開啟該書，裝置轉為橫向，開啟雙頁模式，觀察現況**

開啟該書後確認目前走 `EpubReaderView`（Readium／FXL）路徑（例如出現 FXL 專屬浮動控制項）。裝置轉橫向，於「版面設定」（`FxlSettingsSheet`）確認「雙頁模式」設為「永遠雙頁」或「自動」。觀察畫面：

預期（重現 Issue 16 症狀）：畫面仍只顯示一頁（固定在左邊），翻頁行為是一頁一頁換，非兩頁一組（spread）切換。

- [x] **Step 5: 記錄基準觀察**

把 Step 4 的實際觀察結果（含螢幕截圖）填入本文件最下方「Spike 紀錄」的「Task 1 基準觀察」小節。

---

### Task 2：硬編碼 3 個檢查點，重新建置真機驗證

**Files:**
- Modify（暫時，本 Task 結束前依結果決定，**先不要 commit**）: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,998,1199`

**Interfaces:**
- Consumes: Task 1 已確認現象重現
- Produces:「Spike 紀錄」第 2 節的比對結果，決定 GO/NO-GO

- [ ] **Step 1: 硬編碼 `applyFxlFitScale()` 的 FXL 判斷（:501）**

找到：
```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
```
暫時改為：
```kotlin
    private fun applyFxlFitScale() {
        // Issue 17 Spike：硬編碼驗證，不進 main。
        val isFixedLayout = true
        if (!isFixedLayout) {
```

- [ ] **Step 2: 硬編碼原生端 tap 熱區監聽器註冊判斷（:998）**

找到：
```kotlin
            if (openedPublication.metadata.layout != Layout.FIXED) {
```
暫時改為：
```kotlin
            // Issue 17 Spike：硬編碼驗證，不進 main。
            if (false) {
```

- [ ] **Step 3: 硬編碼 `reportLayoutResolved()` 回報給 Dart 端的判斷（:1199）**

找到：
```kotlin
    private fun reportLayoutResolved() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
```
暫時改為：
```kotlin
    private fun reportLayoutResolved() {
        // Issue 17 Spike：硬編碼驗證，不進 main。
        val isFixedLayout = true
```

- [ ] **Step 4: 確認變更範圍僅限這 3 處**

執行：
```bash
git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
預期：只有上述 3 處硬編碼變更，無其他異動。

- [ ] **Step 5: 重新建置並安裝**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 6: 重複 Task 1 Step 4，確認雙頁排版是否恢復正常**

同一本書、裝置維持橫向、雙頁模式開啟，重新開書觀察：

- **若畫面顯示兩頁並排、翻頁行為為 spread 切換（一次換兩頁）** → 核心假設成立，前往 Step 7 附帶驗證。
- **若畫面仍是單頁、或出現當機/畫面損壞** → 核心假設不成立，直接記錄 NO-GO（Step 8），可跳過 Step 7 附帶驗證（tap 熱區風險已無意義，因為主要假設已否決）。

- [ ] **Step 7: 附帶驗證——確認 tap 熱區雙重處理風險（不影響 GO/NO-GO，僅記錄）**

> 僅在 Step 6 結果為「GO 傾向」時執行本步驟。

在該書畫面上點擊畫面左右兩側（FXL 熱區）觀察換頁行為：

- 若點擊一次正常換頁（或換一組 spread）、無重複觸發或卡頓 → 記錄「未觀察到雙重處理問題」。
- 若點擊一次觸發兩次換頁、或出現不一致的換頁行為（例如換頁量不穩定） → 記錄「觀察到疑似雙重輸入處理症狀」，附上具體現象描述。

- [x] **Step 8: 記錄 Task 2 觀察結果與 GO/NO-GO 判定**

把 Step 6／Step 7 的觀察結果（含螢幕截圖或畫面錄影），填入本文件「Spike 紀錄」的「Task 2 驗證結果」小節，明確寫下 **GO** 或 **NO-GO** 判定。

---

### Task 3：Revert 硬編碼、撰寫 Spike 報告、更新狀態

**Files:**
- Revert: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（還原 Task 2 的硬編碼）
- Write: `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`
- Modify: `docs/epics/epic-18-reader-device-qa/design.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`

**Interfaces:**
- Consumes: Task 2 已完成 GO/NO-GO 判定
- Produces: Spike 報告、更新後的 Issue 16/17 狀態

- [x] **Step 1: Revert 硬編碼**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
預期：`git diff` 無輸出，確認已完全還原。

- [x] **Step 2: 重新建置並安裝，確認裝置回到 `main` 分支的既有行為**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 3: 撰寫 Spike 報告**

於 `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`（比照 `reviews/spike-flutter-inappwebview-selection.md` 既有格式）撰寫：

- 驗證範圍摘要（Task 1/2 做了什麼）
- Task 1 基準觀察、Task 2 驗證結果（含截圖佐證路徑）
- 明確的 GO/NO-GO 結論
- 附帶發現：tap 熱區雙重處理風險的觀察結果
- 若 GO：建議下一步（新增工單承接完整 Dart→Kotlin 旗標傳遞管線實作，比照 Issue 8→10）
- 若 NO-GO：建議下一步（回頭評估 Issue 16 其餘替代方案，例如接受限制或 UI 提示）

- [x] **Step 4: 依結果更新 `design.md`「Issue 16／17 修復方向 Discovery」段落**

於決策 3（Spike-first）之後補上實際驗證結果摘要與報告連結。

- [x] **Step 5: 依結果更新 `issues.md` Issue 17 狀態**

`Status` 更新為完成，摘要 GO/NO-GO 結論；若 GO，記錄新工單編號（若尚未建立，記錄「待新增」）。

- [x] **Step 6: 依結果更新 `issues.md` Issue 16 狀態**

若 GO：`Status` 更新為「根因與修復方向已驗證可行，待新工單承接完整實作」。
若 NO-GO：`Status` 更新為「修復方向已評估並否決，待重新評估替代方案」，視討論結果決定是否降級為 `wontfix` 或改為 UI 提示層級的小工單。

- [x] **Step 7: 更新 `docs/epics.md` epic-18 列摘要**

補上 Spike 結論一句話摘要。

- [x] **Step 8: Commit 文件變更**

```bash
git add docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md \
        docs/epics/epic-18-reader-device-qa/design.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md \
        docs/epics/epic-18-reader-device-qa/plans/plan-issue-17.md
git commit -m "docs(epic-18): Issue 17 Spike 結果——強制 FXL 覆蓋檢查點後 EpubNavigatorFragment 渲染行為驗證"
```

（`EpubReaderView.kt` 已於 Step 1 revert 乾淨，不在本次 commit 範圍內。）

---

## Spike 紀錄

> 本節於執行 Task 1-3 過程中逐步填寫，作為驗證過程的即時記錄，供 Spike 報告（`reviews/spike-issue16-fxl-metadata-override.md`）撰寫時引用。

### Task 1 基準觀察

- **測試裝置**：`3CEF42ECD491687`（9491G，Android 15 API 35）
- **測試書籍**：Issue 15 驗收時已知會被誤判為流式的漫畫 EPUB（已套用「強制 FXL」）
- **觀察結果**：裝置橫向、雙頁模式開啟（永遠雙頁），畫面**只顯示一頁（固定在左邊）**，翻頁行為為一頁一頁切換，非兩頁一組（spread）切換
- **結論**：Issue 16 症狀確認重現——`EpubReaderView.kt` 的 3 個 `isFixedLayout` 檢查點已被覆寫為 `true`（透過 Issue 15 的「強制 FXL」功能），但 `EpubNavigatorFragment` 仍以單頁模式渲染，驗證了 Issue 16 的核心假設

### Task 2 驗證結果

- **硬編碼變更**：3 處 `isFixedLayout` 檢查點全部硬編碼為 `true` / `false`（跳過 metadata 判斷）
- **觀察結果**：裝置橫向、雙頁模式開啟，畫面**仍為單頁顯示**，翻頁行為仍為一頁一頁切換
- **附帶驗證**：因主要假設已否決（NO-GO），跳過 tap 熱區雙重處理風險驗證
- **GO/NO-GO 判定**：**NO-GO** — `EpubNavigatorFragment` 不跟隨 `EpubReaderView.kt` 的 `isFixedLayout` 標誌，其渲染模式由 Readium 官方元件獨立判讀 publication metadata 決定

### Task 3 最終狀態

- **Revert 確認**：`EpubReaderView.kt` 已完全還原，`git diff` 無輸出
- **裝置還原**：重新建置並安裝，裝置回到 `main` 分支既有行為
- **Spike 報告**：`reviews/spike-issue16-fxl-metadata-override.md` 已撰寫完成
- **文件更新**：`design.md`、`issues.md`（Issue 16 + 17）、`epics.md` 皆已更新
- **Commit**：待執行

---

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16／Issue 17
- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-8.md`（本 Epic 既有 Spike 計畫格式參考，含 Task 結構與「診斷紀錄」慣例）
- `docs/epics/epic-18-reader-device-qa/reviews/spike-flutter-inappwebview-selection.md`（本 Epic 既有 Spike 報告格式參考）
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（Spike-first 既有慣例）
- `CONTEXT.md`「Readium 內部版面渲染決策」詞彙定義
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,819-853,998,1199`
