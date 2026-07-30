# Issue 21：Spike——FXL 封面獨立顯示／頁碼配對，驗證覆寫 `readingOrder[0]` 屬性能否強制首頁獨立成頁

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 驗證核心假設——透過官方 `Properties.add(Map<String, Any>)`／`ManifestTransformer` 機制覆寫 `readingOrder` 第一項 `Link` 的屬性，讓 Readium 的 spread 演算法自動把它當成獨立頁（`page-spread-center` 語意），使雙頁模式下呈現「封面獨立、之後兩兩並排」（`1,3-2,5-4`）的配對方式，而非目前的「從第一頁起無條件兩兩配對」（`1-2,3-4`）。核心不確定性：Readium spread 演算法實際讀哪個 key（`"page"`？其他？）、讀了之後是否真的按單頁處理——**無法只靠讀原始碼確認，必須真機驗證**（比照 Issue 17/18 Spike-first 方法論）。

**架構：** 比照 Issue 8／17／18 既有 Spike-first 方法論：Task 1 基準觀察 → Task 2 硬編碼覆寫方案並驗證是否生效 → Task 3 revert＋撰寫報告＋更新狀態。硬編碼修改**不進 `main`**。GO/NO-GO 皆不在本 Issue 內實作永久修法（含完整 Dart→Kotlin 偏好傳遞管線，例如是否要讓使用者可關閉這個行為）——那屬於 GO 之後的新工單範圍。

**Tech Stack：** Kotlin（`EpubReaderView.kt`）、Android 原生建置（`flutter build apk --debug`）、真機人工驗證（`adb install`）。不涉及任何 Dart/Flutter 程式碼變更。

## Global Constraints

- **不修改 `readium-kotlin-toolkit` 本身**，只在 `EpubReaderView.kt` 這一個檔案內做硬編碼實驗，比照 Issue 17/18 既有慣例。
- **硬編碼修改全程不 commit**，Task 3 結束前必須 `git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` revert 乾淨。
- 需要真機 `3CEF42ECD491687`，沿用 Issue 15/17/18/19 已知會被誤判為流式的同一本漫畫 EPUB（該書應已套用「強制 FXL」）。
- `ManifestTransformer` 標記 `@ExperimentalReadiumApi`，需要 `@OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)`。
- 每次修改 Kotlin 原生程式碼後必須完整重新建置＋安裝（`flutter build apk --debug` + `adb install -r`）。
- 本 Spike 的硬編碼**不侷限於「強制 FXL 造成 metadata mismatch」的情境**——封面獨立顯示應適用於所有 FXL 雙頁書籍（不論是否經過 Issue 19 的 `Publication.Builder` 重建分支），故 Task 2 的硬編碼刻意繞過 Issue 19 既有的 mismatch 判斷，無條件套用，單純測試「覆寫第一頁屬性」這一件事本身是否生效。

---

## 檔案結構

- **暫時修改（不 commit）：** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（`attachNavigator()` 內硬編碼覆寫 `readingOrder` 第一項屬性，見 Task 2）

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

- [ ] **Step 2: 觀察現況頁碼配對方式**

沿用已知誤判的漫畫 EPUB（若尚未套用「強制 FXL」，於書架多選模式點擊「強制 FXL」）。開書、裝置轉橫向、雙頁模式設為「永遠雙頁」，翻頁數次觀察頁面配對方式（比照 Issue 20 新增的跳頁 Bottom Sheet 或既有頁碼顯示觀察，若 Issue 20 尚未合併則直接肉眼數頁面內容）。

預期：從第一頁起無條件兩兩配對（`1-2`／`3-4`／`5-6`……），封面（第一頁）與第二頁並排，非獨立成頁。

- [ ] **Step 3: 記錄基準觀察**

填入本文件「Spike 紀錄」的「Task 1 基準觀察」小節。

---

### Task 2：硬編碼覆寫 `readingOrder[0]` 屬性，真機驗證

**Files:**
- Modify（暫時，**先不要 commit**）: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（`attachNavigator()` 內，緊接 Issue 19 既有的 `effective` 建構邏輯之後）

**Interfaces:**
- Consumes: Task 1 已確認現況配對方式
- Produces:「Spike 紀錄」第 2 節的比對結果，決定 GO/NO-GO

- [ ] **Step 1: 硬編碼覆寫第一頁屬性**

找到 Issue 19 既有的 `effective` 建構邏輯（`attachNavigator()` 內，`val effective = if (openedPublication.metadata.layout != Layout.FIXED) { ... } else { openedPublication }` 之後、`effectivePublication = effective` 之前），暫時插入：
```kotlin
            // Issue 21 Spike：硬編碼驗證，不進 main。無條件覆寫第一頁屬性
            // （繞過 Issue 19 的 mismatch 判斷，單純測試這個機制本身是否生效）。
            @OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
            val firstHref = effective.readingOrder.firstOrNull()?.href
            @OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
            val spikeManifest = effective.manifest.copy(
                object : org.readium.r2.shared.publication.ManifestTransformer {
                    override fun transform(link: org.readium.r2.shared.publication.Link):
                        org.readium.r2.shared.publication.Link {
                        if (link.href != firstHref) return link
                        // Issue 21 Spike：嘗試的 key／value，若無效見 Step 3 替代嘗試。
                        return link.copy(properties = link.properties.add(mapOf("page" to "center")))
                    }
                },
            )
            val spikePublication = Publication.Builder(
                manifest = spikeManifest,
                container = effective.container,
                servicesBuilder = Publication.ServicesBuilder(),
            ).build()
            effectivePublication = spikePublication
```
並將後續 `val navigatorFactory = EpubNavigatorFactory(publication = effective)` 暫時改為 `EpubNavigatorFactory(publication = spikePublication)`。

- [ ] **Step 2: 確認變更範圍並建置**

```bash
cd app
git diff android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3: 真機驗證是否生效**

重複 Task 1 Step 2 的觀察方式，確認：
- **若第一頁獨立顯示、第二頁起正確兩兩配對（`2-3`／`4-5`……）** → 核心假設成立，`"page"` key 有效，前往 Step 5 記錄 GO。
- **若配對方式無變化** → `"page"` 這個 key 名稱可能不對，前往 Step 4 嘗試替代方案。
- **若當機或畫面損壞** → 直接記錄 NO-GO（Step 5），可跳過 Step 4。

- [ ] **Step 4（僅在 Step 3 無效時執行）：嘗試替代 key／方案**

若 `"page" to "center"` 無效，依序嘗試（每次修改後重複 Step 2-3）：
1. `mapOf("page-spread-center" to true)`（直接用 EPUB OPF 屬性原始字串當 key，猜測 Readium 可能直接透傳原始 `properties` JSON key 而非轉譯過的簡短名稱）。
2. 查看 Readium `EpubNavigatorFragment`／spread 計算相關類別（`readium/navigator/.../epub/` 目錄下，搜尋 "spread"/"Spread"/"page" 關鍵字）的實際原始碼，找出真正讀取的 key（比照 Issue 18 Spike 查證 `Publication.Builder` 簽章的方式，非憑空猜測）。
3. 若上述皆無效，記錄為 NO-GO，附上已嘗試過的 key 清單。

- [ ] **Step 5: 記錄 GO/NO-GO 判定**

把 Step 3-4 的觀察結果（含截圖）填入「Spike 紀錄」的「Task 2 驗證結果」小節，明確寫下 **GO**（找到有效 key，第一頁確實獨立成頁且後續配對正確）／**NO-GO**（所有嘗試皆無效或有副作用）判定。

---

### Task 3：Revert 硬編碼、撰寫 Spike 報告、更新狀態

**Files:**
- Revert: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Write: `docs/epics/epic-18-reader-device-qa/reviews/spike-issue21-cover-alone-spread.md`
- Modify: `docs/epics/epic-18-reader-device-qa/design.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes: Task 2 已完成 GO/NO-GO 判定
- Produces: Spike 報告、更新後的 Issue 21 狀態

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

於 `docs/epics/epic-18-reader-device-qa/reviews/spike-issue21-cover-alone-spread.md`（比照 `reviews/spike-issue18-publication-builder-override.md` 既有格式）撰寫：驗證範圍摘要、Task 1/2 觀察結果（含截圖）、明確 GO/NO-GO 結論、若嘗試過多個 key 需列出清單與各自結果、建議下一步。

- [ ] **Step 4: 依結果更新 `design.md`「Issue 20／21 修復方向 Discovery」段落**

- [ ] **Step 5: 依結果更新 `issues.md` Issue 21 狀態**

若 GO：記錄有效 key 與確認過的正式實作方向（需評估是否要讓使用者可關閉此行為、是否所有 FXL 書籍都適用或需要偵測書本原生 `page-spread-*` 宣告避免與正確標記的書衝突），記錄後續完整實作工單編號（若尚未建立，記錄「待新增」）。
若 NO-GO：記錄已嘗試方案與失敗證據，回頭評估其餘替代方案（外部報告「方案 3」Native App 層物理裁切、或接受此限制）。

- [ ] **Step 6: 更新 `docs/epics.md` epic-18 列摘要**

- [ ] **Step 7: Commit 文件變更（含本計畫檔）**

```bash
git add docs/epics/epic-18-reader-device-qa/reviews/spike-issue21-cover-alone-spread.md \
        docs/epics/epic-18-reader-device-qa/design.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md \
        docs/epics/epic-18-reader-device-qa/plans/plan-issue-21.md
git commit -m "docs(epic-18): Issue 21 Spike 結果——覆寫 readingOrder[0] 屬性驗證封面獨立顯示"
```

（`EpubReaderView.kt` 已於 Step 1 revert 乾淨，不在本次 commit 範圍內。）

---

## Spike 紀錄

> 本節於執行過程中逐步填寫。

### Task 1 基準觀察

（待填寫）

### Task 2 驗證結果

（待填寫：嘗試過的 key／value 清單與各自結果、GO/NO-GO 判定）

### Task 3 最終狀態

（待填寫）

---

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/reviews/spike-fxl-first-page-single-spread.md`（外部分析報告，方向查證屬實，具體程式碼已查證有誤並修正——`Page.CENTER`／`readingOrder[0] = ...` 索引賦值皆不存在/不會編譯）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 20／21 修復方向 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 21
- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-18.md`（`Publication.Builder` 重建既有慣例，本 Spike 沿用同一處掛鉤點）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`（PDF `dualPageCoverAlone` 既有實作參考，正式實作階段可能的 UI/偏好設計參考）
- Readium `kotlin-toolkit` 3.3.0 官方原始碼：`shared/publication/Properties.kt`（`Properties.add()`）、`shared/publication/ManifestTransformer.kt`（官方轉換介面，`@ExperimentalReadiumApi`）、`shared/publication/presentation/Properties.kt`（已棄用擴充屬性，`spread` 原始 key 讀取範例）
