# Issue 18：Spike v2——重建 `Publication` 物件覆寫 `metadata.layout` 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** Issue 17 已確認「覆寫 `EpubReaderView.kt` 自己的 3 個 bookkeeping 檢查點」對 `EpubNavigatorFragment` 的實際渲染無效（NO-GO）。本 Issue 驗證新方向：**重建傳給 `EpubNavigatorFactory` 的 `Publication` 物件本身**（透過 Readium 官方 `Publication.Builder`，覆寫其 `metadata.layout` 為 `Layout.FIXED`），是否能讓 `EpubNavigatorFragment` 真的渲染成 FXL——並同時驗證這個做法的已知代價：原始 `openedPublication` 的 `servicesBuilder` 是 Readium `Publication` 的 private 建構子參數，重建時只能用全新預設 `ServicesBuilder()`，可能遺失 EPUB 解析器原本註冊的服務（例如本專案已知依賴的 `positions()`），是否造成可觀察的功能退化必須真機驗證。

**架構：** 比照 Issue 8／17 既有的 Spike-first 方法論：Task 1 基準觀察 → Task 2 硬編碼 `Publication.Builder` 重建方案並驗證雙頁排版＋服務遺失風險 → Task 3 revert＋撰寫報告＋更新狀態。硬編碼修改**不進 `main`**。GO/NO-GO 皆不在本 Issue 內實作永久修法（含 Dart→Kotlin 旗標傳遞管線）——那屬於 GO 之後的新工單範圍。

**Tech Stack：** Kotlin（`EpubReaderView.kt`）、Android 原生建置（`flutter build apk --debug`）、真機人工驗證（`adb install`）。不涉及任何 Dart/Flutter 程式碼變更，無可自動化的 `flutter test` 覆蓋範圍。

## Global Constraints

- **不修改 `readium-kotlin-toolkit` 本身**，只在 `EpubReaderView.kt` 這一個檔案內做硬編碼實驗，比照 Issue 17 既有慣例。
- **硬編碼修改全程不 commit**，Task 3 結束前必須 `git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` revert 乾淨。
- 需要真機 `3CEF42ECD491687`，沿用 Issue 15/17 已知會被誤判為流式的同一本漫畫 EPUB（該書應已套用「強制 FXL」，若裝置狀態已因先前 Issue 17 驗證而復原，重新套用一次）。
- 每次修改 Kotlin 原生程式碼後必須完整重新建置＋安裝（`flutter build apk --debug` + `adb install -r`）。
- **class 欄位 `publication` 全程維持指向原始 `openedPublication`，不指向服務不完整的重建物件**（審查修正，見 `tmp/epic-18/review-plan-issue-18.md` Issue C-1）。`jumpToProgression()`／`buildTocPayloadSafely()`／`computeTotalCharacterCountInBackground()` 等既有呼叫端都讀 `publication`（或直接吃參數），必須維持使用原始物件（保留完整服務），否則會在還沒開始測服務遺失風險之前，就先讓這些既有功能悄悄壞掉。新增的暫時欄位 `spikeEffectivePublication` 只供 `:501`／`:1199` 兩個「FXL 判斷」檢查點讀取（見 Task 2 Step 1）；`:998` 因為在 `attachNavigator()` 同一函式範圍內，直接讀區域變數 `effectivePublication` 即可，不需要額外欄位。

---

## 檔案結構

- **暫時修改（不 commit）：** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（新增 `spikeEffectivePublication` 暫時欄位＋`attachNavigator()` 內建構 `effectivePublication`＋3 個 FXL 判斷檢查點改讀，見 Task 2）

---

### Task 1：真機重現現況（基準觀察，修改前）

**Files:** 無（純真機觀察，不變更程式碼）。

**Interfaces:**
- Consumes: 無
- Produces:「Spike 紀錄」第 1 節的基準觀察結果

- [ ] **Step 1: 確認真機已連接、`main` 分支現況已安裝**

```bash
flutter devices
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 確認測試書籍已套用「強制 FXL」，觀察現況**

沿用 Issue 15/17 已知誤判的漫畫 EPUB（若尚未套用「強制 FXL」，於書架多選模式點擊「強制 FXL」）。開書、裝置轉橫向、雙頁模式設為「永遠雙頁」，觀察畫面。

預期（重現 Issue 16/17 症狀）：畫面仍只顯示一頁（固定在左邊），翻頁行為一頁一頁換。

- [ ] **Step 3: 記錄基準觀察**

填入本文件「Spike 紀錄」的「Task 1 基準觀察」小節。

---

### Task 2：硬編碼 `Publication.Builder` 重建方案，真機驗證

**Files:**
- Modify（暫時，**先不要 commit**）: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:164,501,911-924,998,1199`

**Interfaces:**
- Consumes: Task 1 已確認現象重現
- Produces:「Spike 紀錄」第 2 節的比對結果，決定 GO/NO-GO

- [ ] **Step 1: 新增暫時 class 欄位 `spikeEffectivePublication`**

**審查修正（`tmp/epic-18/review-plan-issue-18.md` Issue C-1）**：`jumpToProgression()`（`:1103`）與 `buildTocPayloadSafely()`（`:1146`）都讀 class 欄位 `publication` 並呼叫 `.positions()`——若把 `publication` 整個改指向服務不完整的 `effectivePublication`，會悄悄破壞這兩個既有功能，污染 Spike 想驗證的問題（本專案既有功能是否受服務遺失影響，不該在還沒開始測之前就先被破壞）。因此改為新增一個**專供本 Spike 用**的獨立暫時欄位，只給「FXL 判斷」用的檢查點讀，`publication` 本身維持指向原始物件不動。

找到 `private var publication: Publication? = null`（`EpubReaderView.kt:164` 附近），暫時在其後新增：
```kotlin
    // Issue 18 Spike：硬編碼驗證，不進 main。只供 :501／:1199 這兩個 FXL
    // 判斷檢查點讀取，publication 本欄位維持指向原始物件（jumpToProgression()／
    // buildTocPayloadSafely() 需要完整服務，見 review-plan-issue-18.md Issue C-1）。
    private var spikeEffectivePublication: Publication? = null
```

- [ ] **Step 2: 在 `attachNavigator()` 內建構 `effectivePublication`**

找到（`EpubReaderView.kt:911-924`）：
```kotlin
    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
        initialTotalCharacterCount: Int?,
    ) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
```
暫時改為：
```kotlin
    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
        initialTotalCharacterCount: Int?,
    ) {
        try {
            // Issue 18 Spike：硬編碼驗證，不進 main。isForceFxl 這裡直接寫死
            // true，不做 Dart→Kotlin 旗標傳遞管線（那是 GO 之後的完整實作範圍）。
            val isForceFxl = true
            val effectivePublication = if (isForceFxl) {
                Publication.Builder(
                    manifest = openedPublication.manifest.copy(
                        metadata = openedPublication.metadata.copy(layout = Layout.FIXED),
                    ),
                    container = openedPublication.container,
                    // 注意：原始 servicesBuilder 是 private，這裡只能用預設值——
                    // 這正是本 Spike Task 2 Step 9 要驗證的服務遺失風險。
                ).build()
            } else {
                openedPublication
            }
            // publication 維持指向原始物件（審查修正，見 Step 1 說明）；
            // spikeEffectivePublication 只供 :501／:1199 兩個 FXL 判斷檢查點讀取。
            publication = openedPublication
            spikeEffectivePublication = effectivePublication
            val navigatorFactory = EpubNavigatorFactory(publication = effectivePublication)
```

- [ ] **Step 3: 硬編碼 `applyFxlFitScale()` 的 FXL 判斷（:501），改讀 `spikeEffectivePublication`**

找到：
```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
```
暫時改為：
```kotlin
    private fun applyFxlFitScale() {
        // Issue 18 Spike：改讀 spikeEffectivePublication，硬編碼驗證，不進 main。
        val isFixedLayout = (spikeEffectivePublication ?: publication)?.metadata?.layout == Layout.FIXED
```

- [ ] **Step 4: 硬編碼原生端 tap 熱區監聽器註冊判斷（:998），改讀 `effectivePublication`**

`:998` 讀的是 `attachNavigator()` 的區域變數 `openedPublication`，Step 2 已在同一函式範圍內定義 `effectivePublication`（區域變數，直接可見，不需要額外欄位）。找到：
```kotlin
            if (openedPublication.metadata.layout != Layout.FIXED) {
```
暫時改為：
```kotlin
            // Issue 18 Spike：改讀 effectivePublication，硬編碼驗證，不進 main。
            if (effectivePublication.metadata.layout != Layout.FIXED) {
```

- [ ] **Step 5: 硬編碼 `reportLayoutResolved()` 的 FXL 判斷（:1199），改讀 `spikeEffectivePublication`**

**審查修正（Issue M-1）**：`reportLayoutResolved()` 是獨立方法，`attachNavigator()` 的區域變數 `effectivePublication` 在此不可見，必須讀 Step 1 新增的 class 欄位。找到：
```kotlin
    private fun reportLayoutResolved() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
```
暫時改為：
```kotlin
    private fun reportLayoutResolved() {
        // Issue 18 Spike：改讀 spikeEffectivePublication，硬編碼驗證，不進 main。
        val isFixedLayout = (spikeEffectivePublication ?: publication)?.metadata?.layout == Layout.FIXED
```

- [ ] **Step 6: 確認變更範圍**

```bash
git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
確認變更範圍僅限 Step 1-5 共 5 處區塊（新增欄位＋4 個檢查點）。

- [ ] **Step 7: 重新建置並安裝**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 8: 驗證雙頁排版是否恢復正常**

同一本書、裝置橫向、雙頁模式開啟，重新開書觀察：

- **若畫面顯示兩頁並排、翻頁行為為 spread 切換** → 核心假設成立，前往 Step 9 服務遺失風險驗證。
- **若畫面仍是單頁、或當機/畫面損壞** → 核心假設不成立，直接記錄 NO-GO（Step 11），可跳過 Step 9/10。

- [ ] **Step 9: 驗證服務遺失風險**

> 僅在 Step 8 結果為「GO 傾向」時執行。**審查修正（`tmp/epic-18/review-plan-issue-18.md` Issue C-1/C-2/I-1）**：因 Step 1-2 已改為隔離設計（`publication` 維持原始物件，只有 `effectivePublication` 服務不完整），本專案自己的既有功能（字元數統計、TOC 讀取、劃線/備註）皆繼續使用未受影響的 `publication`，測不到「服務遺失」這個風險本身；真正可能受影響的只有 **Readium Navigator 自己內部**依賴 `effectivePublication` 服務所產生的行為。驗證項目改為：

1. **頁面基本渲染**：確認書本內容（文字/圖片）本身正常顯示，未出現空白頁或載入錯誤——驗證 `Publication.Builder` 重建的物件本身可用，是後續測試的前提。
2. **Slider 進度跳轉測試**：拖曳頁尾/浮動進度條至約 25%／50%／75%，確認畫面正確跳轉至對應位置（非無反應、非跳到錯誤位置）。
3. **`onLocatorChanged` 進度回報觀察**：透過 `adb logcat` 過濾 `onLocatorChanged` 相關輸出（或本專案既有的除錯機制），確認 `progression` 欄位回傳合理的非 `null`／非異常數值（例如非恆為 0 或跳頁後未更新）——這是 Readium Navigator 內部是否因服務遺失而無法正確計算 `totalProgression` 的直接觀察點。
4. **目錄（TOC）點擊跳轉**：開啟目錄畫面確認章節清單仍正常載入（`buildTocPayloadSafely()` 用未受影響的 `publication` 建構，預期正常），點擊任一項目確認能正確跳轉——跳轉動作本身由 Navigator（`effectivePublication`）執行，一併確認無害。

- [ ] **Step 10: 附帶驗證——tap 熱區雙重處理風險（不影響 GO/NO-GO，僅記錄）**

點擊畫面左右兩側觀察換頁行為是否有雙重觸發或不一致現象，記錄結果。

- [ ] **Step 11: 記錄 Task 2 觀察結果與 GO/NO-GO 判定**

把 Step 8-10 的觀察結果（含截圖／logcat 摘錄）填入「Spike 紀錄」的「Task 2 驗證結果」小節，明確寫下 **GO**／**NO-GO**／**部分 GO**（雙頁正常但服務遺失有明確退化，例如進度跳轉/回報異常）判定。

---

### Task 3：Revert 硬編碼、撰寫 Spike 報告、更新狀態

**Files:**
- Revert: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Write: `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`
- Modify: `docs/epics/epic-18-reader-device-qa/design.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes: Task 2 已完成 GO/NO-GO 判定
- Produces: Spike 報告、更新後的 Issue 16/18 狀態

- [ ] **Step 1: Revert 硬編碼**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
預期：無輸出。

- [ ] **Step 2: 重新建置並安裝，確認裝置回到 `main` 既有行為**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3: 撰寫 Spike 報告**

於 `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`（比照 `reviews/spike-issue16-fxl-metadata-override.md` 既有格式）撰寫：驗證範圍摘要、Task 1/2 觀察結果（含截圖）、明確 GO/NO-GO/部分 GO 結論、服務遺失風險驗證結果、tap 熱區附帶發現、建議下一步。

- [ ] **Step 4: 依結果更新 `design.md`「Issue 16／17 修復方向 Discovery」段落**

補上 Issue 18 驗證結果摘要與報告連結（沿用同一段落，不需另開新段落，因為是同一根因調查脈絡的延續）。

- [ ] **Step 5: 依結果更新 `issues.md` Issue 18 狀態**

`Status` 更新為完成，摘要結論；若 GO/部分 GO，記錄後續完整實作工單編號（若尚未建立，記錄「待新增」）。

- [ ] **Step 6: 依結果更新 `issues.md` Issue 16 狀態**

若 GO/部分 GO：`Status` 更新為「修復方向已驗證可行（含已知服務遺失範圍，見 Issue 18 報告），待新工單承接完整實作」。
若 NO-GO：`Status` 更新為「兩次修復嘗試（Issue 17／18）皆已否決，回頭評估其餘替代方案」。

- [ ] **Step 7: 更新 `docs/epics.md` epic-18 列摘要**

- [ ] **Step 8: Commit 文件變更（含本計畫檔）**

```bash
git add docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md \
        docs/epics/epic-18-reader-device-qa/design.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md \
        docs/epics/epic-18-reader-device-qa/plans/plan-issue-18.md
git commit -m "docs(epic-18): Issue 18 Spike v2 結果——重建 Publication 物件覆寫 metadata.layout 驗證"
```

（`EpubReaderView.kt` 已於 Step 1 revert 乾淨，不在本次 commit 範圍內。）

---

## Spike 紀錄

> 本節於執行過程中逐步填寫。

### Task 1 基準觀察

（待填寫）

### Task 2 驗證結果

（待填寫：雙頁排版觀察、服務遺失風險驗證結果、tap 熱區附帶驗證、GO/NO-GO/部分 GO 判定）

### Task 3 最終狀態

（待填寫）

---

## 相關佐證

- `tmp/epic-18/issue-16-solution-analysis.md`（外部分析報告，根因診斷已查證屬實，修復程式碼已查證有編譯錯誤並修正）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16／17／18
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`（Issue 17 NO-GO 報告，格式參考）
- Readium `kotlin-toolkit` 3.3.0 官方原始碼：`Publication.kt`（`Publication`／`Publication.Builder` 類別定義）、`Manifest.kt`（`Manifest` data class）、`EpubNavigatorFactory.kt`（`layout` 判讀）、`EpubNavigatorFragment.kt`（內部多處 `metadata.layout` 讀取點）
- `CONTEXT.md`「Readium 內部版面渲染決策」詞彙定義
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,911-924,998,1034,1199`
