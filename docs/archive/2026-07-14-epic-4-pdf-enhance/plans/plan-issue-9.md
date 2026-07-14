# Epic 4 Issue 9：PdfReaderView.kt 縮放係數與白底 Bitmap 建立邏輯重複 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PdfReaderView.kt` 內兩處殘留的 Duplicated Code——渲染縮放係數計算（`density.coerceIn(2.0f, 3.0f)`，重複 3 處）與不透明白底 Bitmap 建立（`Bitmap.createBitmap(...)` + `eraseColor(Color.WHITE)`，重複 4 處）——分別抽成 `PdfImageProcessor` 的共用純函式，消除重複與其中一處已知的隱式耦合風險。

**Architecture:** 延用 Issue 8 已建立的 pure-Kotlin 物件 `PdfImageProcessor`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`），新增兩個函式：`pageRenderScale(density: Float): Float`（純 Float 運算，可 JVM 單元測試）與 `createOpaqueWhiteBitmap(width: Int, height: Int): Bitmap`（直接呼叫真實 `android.graphics.Bitmap` 方法，比照 `PdfImageProcessor` 既有 `applyBoldEffect()`／`dilate()`／`detectCropRect()` 慣例，不新增 JVM 單元測試）。`PdfReaderView.kt` 的 7 個呼叫點（3 處縮放係數＋4 處白底 Bitmap）改呼叫這兩個共用函式，`import android.graphics.Bitmap` 隨之移除（不再直接參照該型別）。這是抽離重構，不是新功能，所有既有視覺效果與行為必須維持一致。

**Tech Stack:** Kotlin（Android 原生端）、JUnit 4（`app/android/app/build.gradle.kts` 已由 Issue 8 加入 `testImplementation("junit:junit:4.13.2")`，本計劃不需重複新增）、Gradle（`app/android` 模組既有 AGP + Kotlin plugin 設定）。

## Global Constraints

- 這是抽離重構，不是新功能：`pageRenderScale()` 的夾限範圍（下限 2.0、上限 3.0）與 `createOpaqueWhiteBitmap()` 的 `Bitmap.Config.ARGB_8888` + `Color.WHITE` 必須與原本各呼叫點內嵌的算式逐一等價——不得在搬移過程中調整常數或行為。
- `createOpaqueWhiteBitmap()` 屬於 `Bitmap` 相關薄包裝函式，直接呼叫真實 `android.graphics.Bitmap` 方法，無法在純 JVM 環境單元測試（需要 Robolectric 或真機）。比照 `PdfImageProcessor` 既有 `applyBoldEffect()`／`dilate()`／`detectCropRect()` 慣例，本計劃不為它新增自動化測試，正確性由 Task 3 的既有真機 `integration_test` 回歸把關。
- `pageRenderScale()` 是純 `Float` 運算，不依賴 `Bitmap`／`Context`，比照 `EpubFxlScaler`／`PdfImageProcessor` 既有純函式慣例，新增 JVM 單元測試。
- `applyFitMode()` 的 `actualSize` 分支原本留有「隱式耦合，修改時務必同步」的警語註解——這正是本次重構要解決的問題本身：兩處呼叫改成同一個共用函式後，「需要手動同步」的風險已消除，**必須**同步更新該註解內容，使其不再誤導後續維護者誤以為這裡仍是兩份需要手動對齊的硬編碼常數。這不是範疇外的「順手」修改，而是本 issue 的驗收標準之一（見 `issues.md` Issue 9）。
- 呼叫端全部改用共用函式後，`PdfReaderView.kt` 頂端 `import android.graphics.Bitmap` 不再被使用（檔案內僅剩型別推斷的區域變數，無任何 `: Bitmap` 顯式型別標註），需一併移除；`import android.graphics.Color` 從未存在（既有程式碼一律用 `android.graphics.Color.WHITE` 完整限定名稱），本計劃不新增也不需移除。
- 本次刻意不處理、維持現狀的既有技術債（範圍不重疊，見 `docs/epics.md`）：`fitMode`/`cropMode` 改用 Kotlin enum 取代 `String`——已明確記錄「待 Epic 16 PDF 側 issue 完成後再做」，本計劃不動這兩個欄位的型別。
- 測試指令慣例：Dart 測試用 `flutter test`（於 `app/` 目錄執行）；原生 JVM 單元測試用 Gradle `./gradlew testDebugUnitTest`（於 `app/android` 目錄執行，`gradlew`/`gradlew.bat` 為 `.gitignore` 排除產物，若尚不存在先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生）。
- `minSdk = 24`（見專案 `CLAUDE.md`）：本計劃不涉及 API level 相關邏輯變動，`pageRenderScale()` 為純 `Float` 運算，`createOpaqueWhiteBitmap()` 呼叫的 `Bitmap.createBitmap()`／`eraseColor()` 皆為既有程式碼已在使用、無 API 版本門檻疑慮的 API。

---

## File Structure

- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`：新增 `pageRenderScale()`／`createOpaqueWhiteBitmap()` 兩個共用函式與對應常數（`PAGE_RENDER_MIN_SCALE`／`PAGE_RENDER_MAX_SCALE`）。
- **Modify** `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`：新增 `pageRenderScale()` 的 JVM 單元測試。
- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`：3 處 `density.coerceIn(2.0f, 3.0f)`、4 處 `Bitmap.createBitmap(...)` + `eraseColor(Color.WHITE)` 呼叫點改為呼叫 `PdfImageProcessor` 共用函式；移除已無用的 `import android.graphics.Bitmap`；更新 `applyFitMode()` `actualSize` 分支的過期隱式耦合警語註解。

---

### Task 1：`pageRenderScale()` 縮放係數計算抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`

**Interfaces:**
- Produces：`PdfImageProcessor.pageRenderScale(density: Float): Float`——供 Task 3 的 `PdfReaderView.kt` 三個呼叫端使用。

- [ ] **Step 1：寫失敗測試**

編輯 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`，在 `contrastBrightnessColorMatrix` 測試群組（檔案最後）後面新增：

```kotlin

    // ---- pageRenderScale ----

    @Test
    fun `density 低於下限 2_0 時夾限為 2_0`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 1.0f)

        assertEquals(2.0f, scale, 1e-4f)
    }

    @Test
    fun `density 剛好等於下限 2_0 時原樣返回`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 2.0f)

        assertEquals(2.0f, scale, 1e-4f)
    }

    @Test
    fun `density 落在區間內時原樣返回，不夾限`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 2.75f)

        assertEquals(2.75f, scale, 1e-4f)
    }

    @Test
    fun `density 高於上限 3_0 時夾限為 3_0`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 4.0f)

        assertEquals(3.0f, scale, 1e-4f)
    }
```

注意：這 4 個新測試要加在檔案**最後一個** `}` （`class PdfImageProcessorTest` 的收尾大括號）**之前**。

- [ ] **Step 2：執行測試確認失敗（編譯錯誤，`pageRenderScale` 尚不存在）**

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

（若 `./gradlew` 不存在：先於 `app/` 目錄執行一次 `flutter build apk --debug`，讓 Flutter 產生 `app/android/gradlew`／`gradlew.bat`，再重新執行上述指令。）

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: pageRenderScale`。

- [ ] **Step 3：在 PdfImageProcessor.kt 新增 pageRenderScale 與其常數**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`，在既有的：

```kotlin
    // 加粗（型態學膨脹）運算的效能策略常數：對縮小版工作副本做膨脹，而非對
    // 全解析度 bitmap 直接運算（見 docs/epics/epic-4-pdf-enhance/plans/
    // plan-issue-4.md「演算法決策」）。
    private const val BOLD_DOWNSCALE_FACTOR = 0.25f
    private const val BOLD_MAX_RADIUS = 3
```

後面（`applyBoldEffect` 函式之前）新增：

```kotlin

    // PDF 頁面渲染縮放係數的夾限範圍，見 pageRenderScale()。
    private const val PAGE_RENDER_MIN_SCALE = 2.0f
    private const val PAGE_RENDER_MAX_SCALE = 3.0f
```

並在檔案最後（`contrastBrightnessColorMatrix()` 函式的收尾 `}` 之後、`object PdfImageProcessor` 的收尾 `}` 之前）新增：

```kotlin

    /**
     * PDF 頁面渲染縮放係數：以裝置螢幕密度 [density] 為基準，夾限在
     * [PAGE_RENDER_MIN_SCALE]（2.0）到 [PAGE_RENDER_MAX_SCALE]（3.0）之間，
     * 避免極端 density 值造成渲染解析度過低（模糊）或過高（記憶體/效能問題）。
     * `PdfReaderView.kt` 的 `renderCurrentPage()`／`renderFullPageForCropPreview()`／
     * `applyFitMode()` 的 `actualSize` 分支原本各自重複硬編碼
     * `density.coerceIn(2.0f, 3.0f)`，此為抽離後的單一事實來源（見
     * docs/epics.md「PdfReaderView.kt 縮放係數與白底 Bitmap 建立邏輯重複」列、
     * docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
     */
    fun pageRenderScale(density: Float): Float =
        density.coerceIn(PAGE_RENDER_MIN_SCALE, PAGE_RENDER_MAX_SCALE)
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，13 個測試（既有 9 個 + 本 Task 新增 4 個）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt
git commit -m "feat(epic-4): PdfImageProcessor 新增 pageRenderScale，抽離 PDF 渲染縮放係數計算"
```

---

### Task 2：`createOpaqueWhiteBitmap()` 白底 Bitmap 建立抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`（Task 1 已修改的檔案，新增 `createOpaqueWhiteBitmap`）

**Interfaces:**
- Consumes：無（獨立於 Task 1 的 `pageRenderScale`）。
- Produces：`PdfImageProcessor.createOpaqueWhiteBitmap(width: Int, height: Int): Bitmap`——供 Task 3 的 `PdfReaderView.kt` 四個呼叫端使用。

此函式直接呼叫真實 `android.graphics.Bitmap` 方法（`Bitmap.createBitmap()`／`eraseColor()`），無法在純 JVM 環境單元測試（見 Global Constraints）——本 Task 不寫新測試，改以執行既有 JVM 測試套件確認專案仍可正常編譯、既有測試不受影響。

- [ ] **Step 1：在 PdfImageProcessor.kt 新增 createOpaqueWhiteBitmap**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`，在 Task 1 新增的 `pageRenderScale()` 函式後面（檔案最後，`object PdfImageProcessor` 的收尾 `}` 之前）新增：

```kotlin

    /**
     * 建立一張 [width]x[height] 的不透明白底 ARGB_8888 Bitmap。
     * `Bitmap.createBitmap()` 預設是全透明（ARGB 皆為 0），而
     * `PdfRenderer.Page.render()` 只會畫出 PDF 內容本身有實際筆劃的像素，頁面
     * 「空白背景」區域若 PDF 本身沒有明確畫白色矩形，會維持透明、不會被填成
     * 不透明白色。`applyFilters()` 的 `ColorMatrixColorFilter` 第 4 列
     * （alpha）是單位矩陣（保留原始 alpha），因此透明像素無論 contrast／
     * brightness 設多少都不會產生視覺變化——必須在渲染前先手動填滿不透明
     * 白色背景，濾鏡才能對「背景」區域也生效（見 task-4-diagnose-report.md
     * 根因分析）。`PdfReaderView.kt` 原本在智慧裁切偵測、主渲染流程、OOM
     * Fallback 流程、`renderFullPageForCropPreview()` 四處各自重複呼叫
     * `Bitmap.createBitmap(...)` + `eraseColor(Color.WHITE)`，此為抽離後的
     * 單一事實來源（見 docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
     *
     * 與 [applyBoldEffect]／[dilate]／[detectCropRect] 相同，本函式直接呼叫
     * 真實 `android.graphics.Bitmap` 方法，無法在純 JVM 環境單元測試（需要
     * Robolectric 或真機），依專案既有慣例不新增自動化測試，正確性由既有真機
     * `integration_test` 回歸把關（見 plan-issue-9.md Task 3）。
     */
    fun createOpaqueWhiteBitmap(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.WHITE)
        return bitmap
    }
```

- [ ] **Step 2：執行既有測試套件確認建置與既有測試皆不受影響**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，13 個測試（與 Task 1 結束時相同，本 Task 未新增測試）皆通過，代表 `PdfImageProcessor.kt` 新增的 `createOpaqueWhiteBitmap()` 未破壞既有編譯與測試。

- [ ] **Step 3：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt
git commit -m "feat(epic-4): PdfImageProcessor 新增 createOpaqueWhiteBitmap，抽離白底 Bitmap 建立邏輯"
```

---

### Task 3：`PdfReaderView.kt` 改用 `PdfImageProcessor`，真機回歸驗證

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Consumes：`PdfImageProcessor.pageRenderScale(Float): Float`／`PdfImageProcessor.createOpaqueWhiteBitmap(Int, Int): Bitmap`（皆為 Task 1-2 產出）。
- Produces：無新公開介面——本 Task 純粹是呼叫端切換，`PdfReaderView` 對外的 method channel 契約（`openBook`／`setPdfPreferences`／`nextPage`／`previousPage`／`enterCropEditMode`／`exitCropEditMode`）完全不變。

此 Task 不寫新測試（沒有新增行為），而是用既有的真機 `integration_test` 作回歸驗證——見 Step 4。

- [ ] **Step 1：修改 PdfReaderView.kt——3 處 density.coerceIn(2.0f, 3.0f) 改用 PdfImageProcessor.pageRenderScale**

1. `renderCurrentPage()` 內（原第 235-236 行）：

原本：
```kotlin
        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)
```

改為：
```kotlin
        val density = context.resources.displayMetrics.density
        val scale = PdfImageProcessor.pageRenderScale(density)
```

2. `renderFullPageForCropPreview()` 內（原第 385-386 行）：

原本：
```kotlin
        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)
```

改為：
```kotlin
        val density = context.resources.displayMetrics.density
        val scale = PdfImageProcessor.pageRenderScale(density)
```

3. `applyFitMode()` 的 `"actualSize"` 分支內（原第 435-442 行），連同過期的「隱式耦合」警語註解一併更新：

原本：
```kotlin
                val density = context.resources.displayMetrics.density
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個 scale，
                // 換算回「1 PDF point = 1 dp」的真實顯示比例。【隱式耦合，
                // 修改時務必同步】這裡的 density.coerceIn(2.0f, 3.0f) 必須與
                // renderCurrentPage() 內算 width/height 用的 scale 算式保持
                // 完全一致，否則 actualSize 換算出的比例會失準；若未來調整
                // renderCurrentPage() 的 scale 策略，這裡要同步更新。
                val bitmapRenderScale = density.coerceIn(2.0f, 3.0f)
```

改為：
```kotlin
                val density = context.resources.displayMetrics.density
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個
                // PdfImageProcessor.pageRenderScale()，換算回「1 PDF point =
                // 1 dp」的真實顯示比例。兩處呼叫同一個共用函式，不再是各自
                // 硬編碼、需要手動同步的隱式耦合（見
                // docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
                val bitmapRenderScale = PdfImageProcessor.pageRenderScale(density)
```

- [ ] **Step 2：修改 PdfReaderView.kt——4 處白底 Bitmap 建立改用 PdfImageProcessor.createOpaqueWhiteBitmap，移除已無用的 import**

1. `renderCurrentPage()` 的智慧自動裁切偵測分支（原第 216-233 行）：

原本：
```kotlin
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap =
                Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            detectBitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
```

改為：
```kotlin
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
```

2. `renderCurrentPage()` 主渲染流程（原第 258-268 行）：

原本：
```kotlin
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // Bitmap.createBitmap() 預設是全透明（ARGB 皆為 0），而
            // PdfRenderer.Page.render() 只會畫出 PDF 內容本身有實際筆劃的
            // 像素，頁面「空白背景」區域若 PDF 本身沒有明確畫白色矩形，會
            // 維持透明、不會被填成不透明白色。applyFilters() 的
            // ColorMatrixColorFilter 第 4 列（alpha）是單位矩陣（保留原始
            // alpha），因此透明像素無論 contrast／brightness 設多少都不會
            // 產生視覺變化——必須在渲染前先手動填滿不透明白色背景，濾鏡才能
            // 對「背景」區域也生效（見 task-4-diagnose-report.md 根因分析）。
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val matrix = android.graphics.Matrix().apply {
```

改為（完整根因說明已隨白底建立邏輯一併搬到 `PdfImageProcessor.createOpaqueWhiteBitmap()` 的 KDoc，此處不重複）：
```kotlin
        try {
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val matrix = android.graphics.Matrix().apply {
```

3. `renderCurrentPage()` 的 OOM Fallback 流程（原第 285-289 行）：

原本：
```kotlin
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                // 同上，回退路徑也需要先填滿不透明白色背景。
                fallbackBitmap.eraseColor(android.graphics.Color.WHITE)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
```

改為：
```kotlin
            try {
                val fallbackBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
```

4. `renderFullPageForCropPreview()`（原第 390-392 行）：

原本：
```kotlin
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val matrix = android.graphics.Matrix().apply { postScale(scale, scale) }
```

改為：
```kotlin
        try {
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val matrix = android.graphics.Matrix().apply { postScale(scale, scale) }
```

5. 移除檔案頂端已無用的 import（第 4 行）：

原本：
```kotlin
import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
```

改為：
```kotlin
import android.content.Context
import android.graphics.pdf.PdfRenderer
```

- [ ] **Step 3：靜態檢查與既有 JVM 測試回歸**

於 `app/` 目錄執行：

```bash
flutter analyze
```

Expected：`No issues found!`（本 Task 未變動任何 Dart 程式碼，此步驟純粹確認沒有意外波及）。

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，13 個測試全數通過（確認 Step 1-2 的編輯沒有誤觸 `PdfImageProcessor.kt` 本身）。

- [ ] **Step 4：真機回歸驗證（integration_test）**

列出可用的真實裝置/模擬器：

```bash
flutter devices
```

於 `app/` 目錄，針對既有涵蓋 PDF Fit 模式／對比度／亮度／加粗／智慧裁切／手動裁切的真機測試執行回歸（`-d <device-id>` 依上一步列出的裝置代號替換）：

```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```

Expected：全部測試皆通過，尤其留意以下涵蓋本次抽離邏輯的既有測試（測試名稱不變，行為應與抽離前完全一致）：

- `PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError`（涵蓋 `applyFitMode()` 的 `actualSize` 分支，即本次修改「隱式耦合」註解與呼叫端的分支）
- `PDF 調整對比度／亮度後畫面持續渲染成功、無 onError`（涵蓋主渲染流程的白底 Bitmap，驗證濾鏡對背景區域仍生效）
- `PDF 調整加粗強度後畫面持續渲染成功、無 onError`
- `PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError`（涵蓋智慧裁切偵測分支的白底 Bitmap）
- `PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式）`（涵蓋 `renderFullPageForCropPreview()` 的縮放係數與白底 Bitmap）
- `PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果`

若測試失敗，先確認失敗原因是否為本次抽離造成的行為差異（例如公式謄寫錯誤、呼叫參數順序打錯），而非既有已知限制。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "refactor(epic-4): PdfReaderView 改用 PdfImageProcessor，縮放係數與白底 Bitmap 建立邏輯抽離完成"
```

---

## Self-Review

**Spec coverage：** `docs/epics.md`「`PdfReaderView.kt` 縮放係數與白底 Bitmap 建立邏輯重複」列與 `issues.md` Issue 9 要求的兩處重複（縮放係數 3 處、白底 Bitmap 4 處）皆有對應 Task（Task 1/Task 2 新增共用函式，Task 3 完成全部 7 個呼叫點切換），且 Task 3 額外處理了 `import android.graphics.Bitmap` 清理與過期隱式耦合註解更新，對應 `issues.md` 驗收標準最後一項。

**Placeholder scan：** 已逐一檢查，所有 Step 皆含完整可執行程式碼與明確指令/預期輸出，無 TBD／「依需要調整」等佔位敘述。

**Type consistency：** `PdfImageProcessor.pageRenderScale`（`(Float) -> Float`）／`PdfImageProcessor.createOpaqueWhiteBitmap`（`(Int, Int) -> Bitmap`）的簽章在 Task 1-2（定義處）與 Task 3（呼叫處）皆一致核對過；`scale`／`bitmapRenderScale`（皆 `Float`）、`bitmap`／`detectBitmap`／`fallbackBitmap`（皆 `Bitmap`）的變數命名與型別在呼叫端與既有下游用法（`page.render(bitmap, ...)`、`imageView.setImageBitmap(...)`、`PdfImageProcessor.detectCropRect(detectBitmap)`、`PdfImageProcessor.applyBoldEffect(bitmap, boldStrength)`）相容，未變動。

**與 Epic 16 的關係：** 本 issue 是純技術債清償，範圍與 `epic-16-dual-page` 無重疊（不涉及雙頁顯示邏輯），依人類指示於正式進入 Epic 16 前完成收尾，完成後不留下遺留的 Backlog 項目阻塞後續開發排期。

---

**Plan complete and saved to `docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 逐一 Task 派遣獨立 subagent 實作，每個 Task 完成後審查、快速迭代

**2. Inline Execution** - 在本 session 內依 Task 順序批次執行，設檢查點供人工確認

**Which approach？**
