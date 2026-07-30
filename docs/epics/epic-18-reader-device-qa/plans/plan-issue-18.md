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
- **本次硬編碼只影響傳給 `EpubNavigatorFactory` 的 `Publication` 參照與本專案自己的 3 個檢查點**，`computeTotalCharacterCountInBackground(openedPublication)`（`EpubReaderView.kt:1034`）等其餘既有呼叫端**維持使用原始 `openedPublication`**（保留完整服務），不需要一併改成 `effectivePublication`——服務遺失風險驗證的對象是「`EpubNavigatorFragment` 自己內部是否需要那些服務」，不是本專案自己的既有邏輯（本專案自己的邏輯本來就可以繼續用原始物件）。

---

## 檔案結構

- **暫時修改（不 commit）：** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（`attachNavigator()` 新增 `effectivePublication` 計算＋3 處檢查點改讀，見 Task 2）

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
- Modify（暫時，**先不要 commit**）: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:911-924,998,1199`

**Interfaces:**
- Consumes: Task 1 已確認現象重現
- Produces:「Spike 紀錄」第 2 節的比對結果，決定 GO/NO-GO

- [ ] **Step 1: 在 `attachNavigator()` 內硬編碼 `effectivePublication` 並改讀**

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
                    // 這正是本 Spike Task 2 Step 4 要驗證的服務遺失風險。
                ).build()
            } else {
                openedPublication
            }
            publication = effectivePublication
            val navigatorFactory = EpubNavigatorFactory(publication = effectivePublication)
```

- [ ] **Step 2: 硬編碼原生端 tap 熱區監聽器註冊判斷（:998），改讀 `effectivePublication`**

`:998` 目前讀的是 `attachNavigator()` 的參數 `openedPublication`（區域變數），而非上面新增的 `effectivePublication`。找到：
```kotlin
            if (openedPublication.metadata.layout != Layout.FIXED) {
```
暫時改為：
```kotlin
            // Issue 18 Spike：改讀 effectivePublication，硬編碼驗證，不進 main。
            if (effectivePublication.metadata.layout != Layout.FIXED) {
```

- [ ] **Step 3: 確認 `:1199`（`reportLayoutResolved()`）已透過 class 欄位 `publication` 自動生效**

`reportLayoutResolved()` 讀的是 class 欄位 `publication?.metadata?.layout`（`EpubReaderView.kt:1199`），Step 1 已把 `publication = effectivePublication`，此處**不需要**額外修改，執行：
```bash
git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
確認變更範圍僅限 Step 1／Step 2 兩處區塊。

- [ ] **Step 4: 重新建置並安裝**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 5: 驗證雙頁排版是否恢復正常**

同一本書、裝置橫向、雙頁模式開啟，重新開書觀察：

- **若畫面顯示兩頁並排、翻頁行為為 spread 切換** → 核心假設成立，前往 Step 6 服務遺失風險驗證。
- **若畫面仍是單頁、或當機/畫面損壞** → 核心假設不成立，直接記錄 NO-GO（Step 8），可跳過 Step 6/7。

- [ ] **Step 6: 驗證服務遺失風險（本 Issue 新增，Issue 17/外部報告皆未驗證過）**

> 僅在 Step 5 結果為「GO 傾向」時執行。對同一本已套用 `effectivePublication` 的書：

1. **全書字元數統計**：確認「⚙️版面設定」或頁尾顯示的總頁數/進度是否仍正確計算（比對套用 Spike 前的既有數值，或至少確認非 0/非錯誤值）。
2. **目錄（TOC）**：開啟目錄畫面，確認章節清單仍正常載入、點擊可正常跳轉。
3. **劃線／備註**：嘗試建立一筆劃線或備註（若 FXL 路徑既有支援），確認功能正常、位置正確；若既有 FXL 路徑本來就不支援劃線（見 `CONTEXT.md`「劃線」詞條：FXL 不支援），此項記錄為「不適用」。
4. **頁面基本渲染**：確認書本內容（文字/圖片）本身正常顯示，未因 `container` 以外的問題出現空白頁或載入錯誤。

- [ ] **Step 7: 附帶驗證——tap 熱區雙重處理風險（不影響 GO/NO-GO，僅記錄）**

點擊畫面左右兩側觀察換頁行為是否有雙重觸發或不一致現象，記錄結果。

- [ ] **Step 8: 記錄 Task 2 觀察結果與 GO/NO-GO 判定**

把 Step 5-7 的觀察結果（含截圖）填入「Spike 紀錄」的「Task 2 驗證結果」小節，明確寫下 **GO**／**NO-GO**／**部分 GO**（雙頁正常但服務遺失有明確退化）判定。

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
