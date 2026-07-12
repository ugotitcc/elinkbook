# Epic 16 Issue 1 — Spike：Readium Spread 行為驗證與收斂關卡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機上驗證 `spec.md`「待驗證風險與收斂關卡」列出的 4 個未解問題，把 EPUB FXL 雙頁顯示（Issue 6）的實作路線從「假設」變成「已驗證的事實」，並把結論書面化。

**Architecture:** 本 issue 不產出長期功能程式碼。以「暫時性程式碼插樁（temporary instrumentation）→ 真機觀察→ 記錄證據 → 還原插樁 → 只保留書面報告（與必要時的 spec.md 修訂）」的節奏依序驗證 4 個問題。插樁程式碼**不進版本控制**（驗證後 `git checkout --` 還原），只有 `reviews/spike-readium-spread.md` 報告與（若有必要的）`spec.md` 修訂會被 commit。

**Tech Stack:** Kotlin（`EpubReaderView.kt`、`EpubFxlScaler.kt`——後者已由 `epic-16-dual-page` Issue 8 於本計劃撰寫後、Task 4 演算法插樁前新增並合併回 `main`，見下方 Task 4 說明）、Readium `kotlin-toolkit` 3.3.0（`org.readium.r2.navigator.preferences.Spread` enum：`AUTO`/`ALWAYS`/`NEVER`）、`adb`／真機（9491G，device id `3CEF42ECD491687`，Android 15 / API 35）。

## Global Constraints

- 驗證對象是 `EpubPreferences.spread`（型別為 `org.readium.r2.navigator.preferences.Spread` enum，非 Boolean，已由文件審查反編譯 `readium-navigator-3.3.0-runtime.jar` 確認，見 `spec.md` C-1）。
- 4 個待驗證問題（逐字抄自 `spec.md`「待驗證風險與收斂關卡」，不得自行改寫判準）：
  1. Readium `Spread.AUTO`/`Spread.ALWAYS` 啟用後，頁間是否有可見間距（FR-41 硬性要求「不留空白」）
  2. `Spread.AUTO` 是否等同「橫向才雙頁」；若不符，EPUB 側需改為直接依 `isLandscape` 手動在 `ALWAYS`/`NEVER` 間切換
  3. `page-spread-left/right` metadata 的頁面配對是否正確
  4. `applyFxlFitScale()` 若改為「container 寬度 / 2」為每個 WebView 的縮放基準，兩個 WebView 是否真的並排而不重疊
- 若任一項失敗，必須在 `spec.md` 對應段落記錄退回方案的具體實作路線（不能只寫「待評估」）——這是 Issue 6 唯一能依循的事實來源。
- 過程中任何暫時性程式碼/素材，驗證完成後一律清理，不留在版本控制中（`git status` 須乾淨，只保留報告檔與必要的 spec.md 修訂）。
- 本 issue 不需要新增/修改任何 Dart 端程式碼或單元測試——純粹是原生端行為的真機觀察。
- **本計劃撰寫完成、落地 `main` 之後、實作開始之前，`epic-4-pdf-enhance` Issue 8 與 `epic-16-dual-page` Issue 8 已先行完成並合併回 `main`**：`EpubReaderView.kt` 的 `applyFxlFitScale()` 已改為呼叫抽離出去的 `EpubFxlScaler.computeFitScale()`／`computeCenteringTranslation()`（不再是內嵌的 `minOf(...).coerceAtMost(1f)` 算式）。Task 1、Task 4 的檔案行號與程式碼片段已依此更新，執行前請確認你手上的 worktree 是從更新後的 `main`（含 `EpubFxlScaler.kt`）開出的，而不是本計劃最初撰寫時的舊基準。
- 測試素材：
  - 控制組（結構簡單、已知內容）：`app/test/fixtures/sample_fixed_layout.epub`、`app/test/fixtures/sample_fxl_svg_cover.epub`
  - 真實多頁漫畫（用於 Q3 頁面配對驗證）：`tmp/一弦定音！(06).epub`（94MB，203 個 spine itemref，已確認 OPF 中 `page-progression-direction="rtl"`、封面 `properties="rendition:page-spread-center"`、其後嚴格交替 `page-spread-left`（p-001, p-003, p-005…）/`page-spread-right`（p-002, p-004, p-006…），套件層級 `<meta property="rendition:spread">landscape</meta>`）——**此檔案為使用者個人素材，不得複製進 `app/assets/` 或 `app/test/fixtures/`，也不得納入版本控制**，僅透過 `adb push` 暫存於裝置 `/sdcard/Download/`，驗證完成後 `adb shell rm` 清除

---

### Task 1：暫時插樁 `spread` 偏好並驗證基本生效

**Files:**
- Modify（暫時性，驗證後還原）：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:30-31`（新增 import）、`:384-397`（`buildPreferencesFromMap()`；行號已因 `epic-16-dual-page` Issue 8 的 `EpubFxlScaler` 抽離而位移，見 Global Constraints）

**Interfaces:**
- Consumes：無（本 issue 起始工單）
- Produces：無長期介面——本插樁僅供本 issue 內部驗證使用，Issue 6 會依 `spec.md` 既有規格（`dualPageMode` → `Spread` 映射）重新正式實作，不依賴本 issue 留下的任何程式碼

- [ ] **Step 1：記錄插樁前的乾淨基準**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：`git status --short` 完全無輸出（`plan-issue-1.md` 已隨 `main` 一併存在於本 worktree 的初始 commit 中，不會顯示為待處理的變更）。若有殘留輸出，先確認來源再繼續。

- [ ] **Step 2：新增 `Spread` import**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 第 30 行（`import org.readium.r2.navigator.preferences.FontFamily` 之後）新增一行：

```kotlin
import org.readium.r2.navigator.preferences.Spread
```

- [ ] **Step 3：暫時強制 `spread = Spread.AUTO`**

修改 `buildPreferencesFromMap()`（現第 384-397 行），在 `EpubPreferences(...)` 建構參數最後新增一行（暫時性，標註清楚以便 Task 5 復原時好找）：

```kotlin
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
            verticalText = (map["writingMode"] as? String)?.let { it == "vertical" },
            scroll = (map["pageTurnMode"] as? String)?.let { it == "scroll" },
            fontFamily = (map["fontFamily"] as? String)?.let { FontFamily(it) },
            fontSize = (map["fontSize"] as? Number)?.toDouble(),
            fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
            lineHeight = (map["lineHeight"] as? Number)?.toDouble(),
            paragraphSpacing = (map["paragraphSpacing"] as? Number)?.toDouble(),
            pageMargins = (map["pageMargins"] as? Number)?.toDouble(),
            textAlign = (map["textAlign"] as? String)?.let { textAlignFromName(it) },
            publisherStyles = map["publisherStyles"] as? Boolean,
            spread = Spread.AUTO, // TEMP-SPIKE(epic-16-issue-1)：驗證用，Task 5 需移除
        )
    }
```

- [ ] **Step 4：建置 debug APK 並安裝到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：建置成功（無 Kotlin 編譯錯誤，確認 `Spread` import 路徑正確），安裝成功（`Success`）。

- [ ] **Step 5：以既有固定版面控制組驗證插樁生效（不判斷 spread 行為本身，只確認沒有 crash 且能正常開書）**

透過 App 內既有「匯入書籍」流程匯入 `app/test/fixtures/sample_fixed_layout.epub`（或直接用 Library 既有測試書籍，若已存在），開啟後確認：
- 無 `onError`、畫面正常顯示第一頁
- logcat 無 `EpubPreferences`／`Spread` 相關例外：

```bash
adb -s 3CEF42ECD491687 logcat -d | grep -i "elinkbook\|readium" | tail -50
```

Expected：正常渲染、無崩潰。若崩潰，檢查 `Spread` import 或建構參數順序是否正確，修正後回到 Step 4。

---

### Task 2：驗證 Q1（頁間間距）與 Q2（`AUTO` 是否等同橫向才雙頁）

**Files:** 無新增檔案異動（沿用 Task 1 的插樁）

**Interfaces:**
- Consumes：Task 1 已生效的 `spread = Spread.AUTO` 插樁
- Produces：Q1／Q2 的證據（螢幕截圖 + 文字觀察紀錄），供 Task 5 彙整進報告

- [ ] **Step 1：裝置直向開啟固定版面 EPUB，確認為單頁**

繼續使用 Task 1 已開啟的 `sample_fixed_layout.epub`（或 `sample_fxl_svg_cover.epub`），確保裝置目前為直向，截圖存證：

```bash
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-16/reviews/spike-q1q2-portrait.png"
```

Expected：單頁顯示，非雙頁並排。

- [ ] **Step 2：裝置旋轉橫向，觀察是否自動切換為雙頁並排**

```bash
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 0
adb -s 3CEF42ECD491687 shell settings put system user_rotation 1
```

等待畫面重繪後截圖：

```bash
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-16/reviews/spike-q1q2-landscape.png"
```

**Q2 判準**：比對 Step 1／Step 2 兩張截圖——若橫向截圖顯示兩頁並排、直向維持單頁，則 `Spread.AUTO` **等同「橫向才雙頁」**（Q2 結論：符合預期，EPUB 側可依規劃使用 `Spread.AUTO` 不需自行判斷方向）。若橫向與直向皆為單頁（`AUTO` 未對這份固定版面 EPUB 生效），或直向就已經雙頁，代表 `AUTO` 語意與螢幕方向無關，需在報告記錄為「Q2 失敗」。

- [ ] **Step 3：Q1 間距量測**

在 Step 2 的橫向截圖上，用圖片檢視工具或像素座標估算兩頁之間是否存在非內容的空白像素帶（例如比對兩個頁面各自的內容邊界與螢幕水平中點的距離）。**Q1 判準**：若兩頁緊貼、中間無可辨識的空白帶，Q1 結論為「無間距，符合 FR-41」；若有肉眼可見的空白帶，記錄目測寬度（以螢幕寬度的百分比估算即可，不需精確像素值）並判定「Q1 失敗，需在 Issue 6 增加額外處理」。

- [ ] **Step 4：換用 `sample_fxl_svg_cover.epub` 重複 Step 1-3 交叉驗證**

不同素材（SVG 封面 vs. 一般固定版面）可能有不同的 viewport 宣告，重複同樣的直向/橫向截圖與判斷，確認結論在兩份控制組素材上一致。若不一致，兩者皆記錄進報告，不可只取其一。

- [ ] **Step 5：復原裝置旋轉設定**

```bash
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 1
```

---

### Task 3：驗證 Q3（`page-spread-left/right` metadata 配對）

**Files:** 無新增檔案異動（沿用 Task 1 的插樁）

**Interfaces:**
- Consumes：Task 1 已生效的 `spread = Spread.AUTO` 插樁
- Produces：Q3 的證據（螢幕截圖 + 配對正確性判斷），供 Task 5 彙整進報告

- [ ] **Step 1：推送真實多頁漫畫到裝置**

```bash
adb -s 3CEF42ECD491687 push "U:/MyDeveloper/AI/elinkBook/tmp/一弦定音！(06).epub" /sdcard/Download/
```

- [ ] **Step 2：透過 App 內「匯入書籍」流程匯入該檔案**

在真機上開啟 App → 圖書庫 →「匯入書籍」→ 系統檔案選擇器 → 導覽至「下載」資料夾 → 選取剛推送的檔案，等待匯入完成（此為既有 `epic-1-library` 已完成的匯入流程，不需修改任何程式碼）。

- [ ] **Step 3：開啟該書，確認裝置橫向下封面單獨顯示**

已知本書 OPF 中封面 `itemref` 的 `properties="rendition:page-spread-center"`（置中，非左右配對的一部分）。裝置橫向開啟後截圖：

```bash
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 0
adb -s 3CEF42ECD491687 shell settings put system user_rotation 1
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-16/reviews/spike-q3-cover.png"
```

**判準**：封面應單獨佔滿畫面（或至少不與下一頁並排），不應該被硬湊成雙頁的一半。

- [ ] **Step 4：翻到下一個 spread，確認 p-001（`page-spread-left`）／p-002（`page-spread-right`）正確配對**

翻頁後截圖：

```bash
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-16/reviews/spike-q3-spread1.png"
```

**判準**：兩頁美術內容在視覺上應連貫（漫畫跨頁分鏡通常在裝訂邊有構圖延續性），且畫面左側對應 p-001、右側對應 p-002（`page-spread-left`/`page-spread-right` 屬性直接宣告左右位置，與 `page-progression-direction="rtl"` 的翻頁**導覽方向**無關，不應混淆）。若配對明顯錯位（例如左右對調、或出現 p-002+p-003 這種跨越正確配對邊界的組合），記錄為「Q3 失敗」並截圖存證。

- [ ] **Step 5：再翻 2-3 個 spread 重複驗證，確認配對規律一致**

重複 Step 4 的判斷方式再驗證 2-3 組 spread（如 p-003/p-004、p-005/p-006），確保不是單一巧合。

- [ ] **Step 6：清理真機上的匯入書籍與暫存檔**

驗證完成後，於 App 內刪除本書（圖書庫 → 長按/滑動該書 →刪除），並清除裝置暫存：

```bash
adb -s 3CEF42ECD491687 shell rm -f /sdcard/Download/一弦定音！\(06\).epub
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 1
```

---

### Task 4：驗證 Q4（`applyFxlFitScale()` 雙頁下是否不再重疊）

**Files:**
- Modify（暫時性，驗證後還原）：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:317-370`（`applyFxlFitScale()`；行號與實作內容已因 `epic-16-dual-page` Issue 8 的 `EpubFxlScaler` 抽離而變動，見下方 Step 1）

**Interfaces:**
- Consumes：Task 1 已生效的 `spread = Spread.AUTO` 插樁；Task 2 已確認（或已知失敗但仍可進行本驗證）的間距/方向行為；`epic-16-dual-page` Issue 8 已合併至 `main` 的 `EpubFxlScaler.computeFitScale(availableWidth: Int, availableHeight: Int, contentWidth: Int, contentHeight: Int): Float`／`EpubFxlScaler.computeCenteringTranslation(availableWidth: Int, availableHeight: Int, contentWidth: Int, contentHeight: Int, scale: Float, currentLeft: Float, currentTop: Float): EpubFxlScaler.Translation`（本插樁重用既有函式做「每頁半寬」擴充，不修改 `EpubFxlScaler.kt` 本身，見 Step 1 說明）
- Produces：Q4 的證據（螢幕截圖），供 Task 5 彙整進報告；若證實可行，此「重用 EpubFxlScaler 做半寬擴充」的作法可作為 Issue 6 實作的起點（僅供參考，Issue 6 需視實際 `spec.md` 規格重新正式撰寫並補測試，不可直接複製本次插樁程式碼）

- [ ] **Step 1：暫時替換 `applyFxlFitScale()` 為半寬置中演算法**

修改 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，把現行（Issue 8 抽離後）第 317-370 行的 `applyFxlFitScale()` 內容：

```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
            removeFxlLayoutListener()
            return
        }
        if (fxlLayoutListener != null) return
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val availableWidth = container.width
            val availableHeight = container.height
            if (availableWidth <= 0 || availableHeight <= 0) return@OnGlobalLayoutListener
            val containerLoc = IntArray(2)
            container.getLocationOnScreen(containerLoc)
            for (webView in findViewsByType<WebView>(container)) {
                val contentWidth = webView.width
                val contentHeight = webView.height
                if (contentWidth <= 0 || contentHeight <= 0) continue
                val fitScale = cachedFxlFitScale ?: EpubFxlScaler.computeFitScale(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                ).also { cachedFxlFitScale = it }

                // 先歸零位移、以左上角為錨點，量出這一輪「未經校正」的原始 layout
                // 位置（pivot 在 (0,0) 時縮放不會移動錨點本身，所以量到的位置就是
                // Readium 自己排版（含它內部的置中位移）算出來的原始位置）。
                webView.translationX = 0f
                webView.translationY = 0f
                webView.pivotX = 0f
                webView.pivotY = 0f
                webView.scaleX = fitScale
                webView.scaleY = fitScale
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = (webViewLoc[0] - containerLoc[0]).toFloat()
                val currentTop = (webViewLoc[1] - containerLoc[1]).toFloat()

                val translation = EpubFxlScaler.computeCenteringTranslation(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                    scale = fitScale,
                    currentLeft = currentLeft,
                    currentTop = currentTop,
                )
                webView.translationX = translation.x
                webView.translationY = translation.y
            }
        }
        fxlLayoutListener = listener
        container.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }
```

暫時替換為（重用既有 `EpubFxlScaler.computeFitScale()`／`computeCenteringTranslation()`，只是把每個 WebView 依畫面左右順序分配到一個「半寬 slot」，呼叫 `computeCenteringTranslation()` 時把 `currentLeft` 平移到 slot 本地座標系，讓函式算出的置中結果落在該 slot 內，再讓 `translationX` 回填到絕對螢幕座標——**不修改 `EpubFxlScaler.kt` 本身**）：

```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
            removeFxlLayoutListener()
            return
        }
        if (fxlLayoutListener != null) return
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val availableWidth = container.width
            val availableHeight = container.height
            if (availableWidth <= 0 || availableHeight <= 0) return@OnGlobalLayoutListener
            val containerLoc = IntArray(2)
            container.getLocationOnScreen(containerLoc)

            // TEMP-SPIKE(epic-16-issue-1)：>=2 個可見 WebView 視為 spread 生效，
            // 驗證用暫時判斷，Task 5 需移除。
            val visibleWebViews = findViewsByType<WebView>(container)
                .filter { it.width > 0 && it.height > 0 }
            val isSpread = visibleWebViews.size >= 2
            val perPageWidth = if (isSpread) availableWidth / 2 else availableWidth

            data class Measured(
                val webView: WebView,
                val contentWidth: Int,
                val contentHeight: Int,
                val rawLeft: Float,
                val rawTop: Float,
            )

            // 先把全部 WebView 的 scale/translation 歸零量測原始位置，避免
            // 同一輪內彼此的變換互相干擾，再依畫面左右順序排序。
            val measured = visibleWebViews.map { webView ->
                webView.translationX = 0f
                webView.translationY = 0f
                webView.pivotX = 0f
                webView.pivotY = 0f
                webView.scaleX = 1f
                webView.scaleY = 1f
                val loc = IntArray(2)
                webView.getLocationOnScreen(loc)
                Measured(
                    webView,
                    webView.width,
                    webView.height,
                    (loc[0] - containerLoc[0]).toFloat(),
                    (loc[1] - containerLoc[1]).toFloat(),
                )
            }.sortedBy { it.rawLeft }

            measured.forEachIndexed { index, m ->
                val fitScale = cachedFxlFitScale ?: EpubFxlScaler.computeFitScale(
                    availableWidth = perPageWidth,
                    availableHeight = availableHeight,
                    contentWidth = m.contentWidth,
                    contentHeight = m.contentHeight,
                ).also { if (index == 0) cachedFxlFitScale = it }
                m.webView.pivotX = 0f
                m.webView.pivotY = 0f
                m.webView.scaleX = fitScale
                m.webView.scaleY = fitScale

                // 第 index 頁的 slot 左邊界（雙頁時第 0 頁在 x=0、第 1 頁在
                // x=perPageWidth）。把 currentLeft 平移到 slot 本地座標系
                // （減去 slotLeft）再呼叫既有 computeCenteringTranslation()，
                // 它算出的 desiredLeft（函式內部假設整個 availableWidth——
                // 這裡傳入的是 perPageWidth——只有一頁內容）就會落在 slot
                // 本地座標系內置中；函式回傳的 translation 本身已經是
                // 「從目前位置到目標位置」的位移量，回填給 translationX/Y
                // 即可讓內容落在正確的螢幕絕對位置。
                val slotLeft = if (isSpread) index * perPageWidth else 0
                val translation = EpubFxlScaler.computeCenteringTranslation(
                    availableWidth = perPageWidth,
                    availableHeight = availableHeight,
                    contentWidth = m.contentWidth,
                    contentHeight = m.contentHeight,
                    scale = fitScale,
                    currentLeft = m.rawLeft - slotLeft,
                    currentTop = m.rawTop,
                )
                m.webView.translationX = translation.x
                m.webView.translationY = translation.y
            }
        }
        fxlLayoutListener = listener
        container.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }
```

**已知的驗證期簡化，不代表正式規格**：`cachedFxlFitScale` 沿用全書單一快取（本 issue 未處理「單/雙頁切換或旋轉時快取失效」，那是 Issue 6 依 `spec.md` I-2 的正式範圍）；本次只驗證「兩個 WebView 是否真的並排不重疊」這一件事。

- [ ] **Step 2：重新建置並安裝**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3：重新匯入漫畫（或使用 Task 3 遺留的既有匯入項目，若尚未刪除），橫向開啟並截圖**

若 Task 3 Step 6 已刪除書籍與暫存檔，重複 Task 3 Step 1-2 重新匯入；否則直接開啟既有書籍。裝置橫向、翻到非封面的一個 spread：

```bash
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 0
adb -s 3CEF42ECD491687 shell settings put system user_rotation 1
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-16/reviews/spike-q4-halfwidth.png"
```

**Q4 判準**：兩頁應清楚並排、各自完整可見、無重疊（若失敗，畫面會呈現兩張圖片幾乎完全疊在畫面正中央的異常結果，很容易辨識）。若重疊，記錄現象並在報告中標注「Q4 失敗，Issue 6 需重新設計演算法」，不需要在本 issue 內排除到底。

- [ ] **Step 4：清理裝置暫存**

```bash
adb -s 3CEF42ECD491687 shell rm -f "/sdcard/Download/一弦定音！(06).epub"
adb -s 3CEF42ECD491687 shell settings put system accelerometer_rotation 1
```

（若書籍仍在 App 圖書庫內，於 App 內刪除。）

---

### Task 5：彙整驗證報告、視結果更新 spec.md、還原插樁

**Files:**
- Create：`docs/epics/epic-16-dual-page/reviews/spike-readium-spread.md`
- Modify（僅在有問題失敗時）：`docs/epics/epic-16-dual-page/spec.md`「待驗證風險與收斂關卡」／`EpubReaderView.kt` 模組段落
- Revert：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（還原 Task 1、Task 4 的暫時性插樁）

**Interfaces:**
- Consumes：Task 2、3、4 產出的截圖證據與判準結論
- Produces：本 epic 後續 Issue 6 唯一可依循的事實結論（含是否需要退回自行實作）

- [ ] **Step 1：撰寫驗證報告**

在 `docs/epics/epic-16-dual-page/reviews/spike-readium-spread.md` 寫入以下結構（依 Task 2-4 的實際觀察結果填入，不得照抄本範本的占位文字）：

```markdown
# Epic 16 Issue 1 — Spike：Readium Spread 行為驗證報告

**驗證日期：** <實際日期>
**驗證裝置：** 9491G（Android 15 / API 35，device id 3CEF42ECD491687）
**Readium 版本：** kotlin-toolkit 3.3.0

## Q1：Spread.AUTO/ALWAYS 頁間是否無間距

**結論：** <通過 / 失敗>
**證據：** `spike-q1q2-landscape.png`（+ sample_fxl_svg_cover.epub 交叉驗證結果）
<具體觀察描述>

## Q2：Spread.AUTO 是否等同「橫向才雙頁」

**結論：** <通過 / 失敗>
**證據：** `spike-q1q2-portrait.png` vs `spike-q1q2-landscape.png`
<具體觀察描述；若失敗，記錄 EPUB 側改用 isLandscape 手動切換 ALWAYS/NEVER 的因應方案>

## Q3：page-spread-left/right metadata 配對是否正確

**結論：** <通過 / 失敗>
**證據：** `spike-q3-cover.png`、`spike-q3-spread1.png`（+ 額外 2-3 組驗證）
**測試素材：** 一弦定音！(06).epub（真實多頁漫畫，OPF 已確認 page-progression-direction=rtl，封面 rendition:page-spread-center，其後嚴格交替 page-spread-left/right）
<具體觀察描述>

## Q4：applyFxlFitScale() 半寬置中演算法是否不再重疊

**結論：** <通過 / 失敗>
**證據：** `spike-q4-halfwidth.png`
<具體觀察描述；若失敗，記錄實際重疊現象與可能原因猜測，供 Issue 6 參考>

## 對 Issue 6 的收斂結論

<綜合 4 項結論，明確寫出 Issue 6 應採用「spec.md 既有規劃的 Readium Spread 路線」還是「退回自行實作」；若退回，具體實作方向是什麼>
```

- [ ] **Step 2：若任一問題失敗，更新 `spec.md`**

若 Step 1 報告中有任何「失敗」結論，回到 `docs/epics/epic-16-dual-page/spec.md`「待驗證風險與收斂關卡」一節，在對應項目後方補上：

```markdown
> **Issue 1 驗證結果（<日期>）：<通過/失敗，一句話結論>**——完整證據見 `reviews/spike-readium-spread.md`。<若失敗，這裡寫退回方案的具體實作路線>
```

若全部 4 項皆通過，仍需在該節開頭補一句總結（例如：「本節 4 項風險已於 Issue 1 spike 全數驗證通過，見 `reviews/spike-readium-spread.md`，Issue 6 可依 `spec.md` 既有規劃直接實作」），避免下一位讀者誤以為此節仍是未解狀態。

- [ ] **Step 3：還原 Task 1 與 Task 4 的暫時性程式碼**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git diff --stat app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```

Expected：`git diff --stat` 顯示 `EpubReaderView.kt` 有異動（確認插樁確實存在過），`git checkout --` 後該檔案完全還原至插樁前狀態。

- [ ] **Step 4：確認清理完整**

```bash
git status --short
```

Expected：只剩 `docs/epics/epic-16-dual-page/reviews/spike-readium-spread.md`（新增）與（若 Step 2 有異動）`docs/epics/epic-16-dual-page/spec.md`（修改）。`plans/plan-issue-1.md` 已隨 `main` 存在，不會出現在這份異動清單中；`app/android/.../EpubReaderView.kt` 也不應出現在異動清單中。

（截圖檔案位於 `tmp/epic-16/reviews/`，該路徑已被根目錄 `.gitignore`（`tmp/`）排除，不需手動清理即不會進版控；如需保留證據可留著，或驗證後自行刪除，皆可。）

- [ ] **Step 5：`flutter analyze` 確認未殘留任何插樁副作用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-16-dual-page/reviews/spike-readium-spread.md
git add docs/epics/epic-16-dual-page/spec.md 2>/dev/null || true
git commit -m "docs(epic-16): Issue 1 spike——Readium Spread 行為驗證與收斂"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：「待驗證風險與收斂關卡」列出的 4 項問題（Task 2 涵蓋 Q1/Q2、Task 3 涵蓋 Q3、Task 4 涵蓋 Q4）與「若驗證失敗需記錄退回方案」的要求（Task 5 Step 2）皆有對應任務，issues.md 的驗收標準（4 項結論皆有證據、失敗時 spec.md 已更新、暫時性素材已清理）三項也都對應到 Task 5 的 Step 1/2/3-4。
- **無佔位符掃描**：所有步驟皆為具體指令/程式碼，唯 Task 5 Step 1 的報告範本本質上是待填格式（不是逃避性的「TODO」，而是驗證結果本就要等 Task 2-4 執行後才知道），已在旁註明「不得照抄占位文字」以避免被誤用為敷衍填充。
- **型別/介面一致性**：`Spread.AUTO`／`Spread.ALWAYS`／`Spread.NEVER` 全文用法與 `spec.md` C-1 一致；`findViewsByType<WebView>` 函式名稱沿用 `EpubReaderView.kt` 既有程式碼，未杜撰新名稱。
- **本次基準同步修訂（本計劃落地 `main` 前的更新）**：計劃最初撰寫時，`epic-16-dual-page` Issue 8（`EpubFxlScaler` 抽離）尚未完成；`main` 合入該 Issue 後，`applyFxlFitScale()` 的實作與行號皆已變動。本次同步已將 Task 1（行號）與 Task 4（程式碼片段＋行號）更新為與目前 `main` 一致，Task 4 的暫時演算法改為重用既有 `EpubFxlScaler.computeFitScale()`／`computeCenteringTranslation()` 做半寬擴充，而非重新內嵌一份獨立算式——這也與 `EpubFxlScaler.kt` 自身 KDoc 對「未來雙頁邏輯應在此模組內擴充」的建議一致。同時修正 Task 1 Step 1、Task 5 Step 4/6，反映「本計劃檔已隨 `main` 存在、非本 issue 執行期間新增的未提交檔案」這個目前的實際狀態（原文字誤植為計劃檔本身尚未提交）。
