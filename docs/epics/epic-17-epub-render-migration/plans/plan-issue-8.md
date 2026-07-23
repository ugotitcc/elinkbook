# Epic 17 Issue 8 — 劃線與備註 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `FoliateEpubReaderView`（Issue 3-6 已建置，目前可開書／套用版面偏好／換頁／熱區／目錄跳轉／定位持久化）支援劃線與備註：使用者長按選字後可套用螢光筆三色或底線、可新增獨立備註，既有標記正確疊加顯示於畫面上，點擊既有標記可開啟編輯/刪除對話框——依 Issue 7 Spike 驗證結論，改接到 `readest/foliate-js` 的 `overlayer.js`（`Overlayer` 類別）與 `view.js` 既有的 `addAnnotation`/`deleteAnnotation`/`showAnnotation` API。

**Architecture:** 新增一個純 Kotlin、JVM 可測的 `FoliateDecorationCodec` 物件，負責「Dart `EpubDecoration.toWire()` 格式 → JS 端 `{id, cfi, color, isUnderline}` 格式」的轉換（含 ARGB `Int` 色值換算為 CSS `rgba()` 字串、舊格式/無效 `locatorJson` 的優雅退回過濾），`FoliateEpubReaderView.kt`／`main.js` 本身不重新實作這些判斷邏輯，比照 `FoliateLocatorCodec` 既有先例。`main.js` 新增 `window.setDecorations()`：整組移除既有標記後透過 `view.addAnnotation({value: cfi, color, isUnderline})` 逐筆重新加入——`view.addAnnotation()` 的 `value` 欄位本身必須是 `view.resolveNavigation()` 可解析的目標，因此固定用 CFI 字串本身當 key，另建模組級 `decorationIdByCfi: Map<cfi, id>` 供點擊事件反查 Dart 端的不透明 id 字串（`"highlight:5"`/`"note:12"`）。實際繪製邏輯透過 `view` 的 `draw-annotation` 事件監聽器完成（`Overlayer.highlight()`/`underline()` 的 `options` 形狀不同，依 `isUnderline` 分流組裝）；點擊既有標記透過 `show-annotation` 事件監聽器完成。選取範圍即時回報改用持久（非 `{once:true}`）的 `'load'` 事件監聽器，為每個 section 的 `doc` 各自掛上 `selectionchange` 監聽器，`doc`/`index` 皆從該次 `'load'` 呼叫的區域變數閉包讀取（不快取到模組級共用變數），座標換算採用 Issue 7 Spike 已驗證的公式（iframe 內局部矩形 + iframe 相對外層 `#view` 容器的位移，除以外層容器可視尺寸）。Kotlin 端 `FoliateBridge` 新增 `onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated` 三個 JS→Kotlin 回呼方法，訊息格式與既有 `EpubReaderView.kt` 送給 Dart 端的欄位名稱逐一對稱，使 Dart 端 `FoliateEpubReaderView` 能複用與 `EpubReaderView` 完全相同的 `_handleMethodCall` case 與型別（`EpubSelectionInfo`／`EpubDecoration`）。`ReaderScreen` 側：`_handleFoliateLayoutResolved` 新增觸發一次性劃線/備註載入（比照 `_handleLayoutResolved` 既有模式，但不需要 `!info.isFixedLayout` 檢查，因為本方法只會被恆為流式的 `FoliateEpubReaderView` 呼叫）；既有 `_sendDecorationsToNative()` 改為依 `_dispatchedIsFixedLayout` 分派到 `EpubReaderView.setDecorations`（FXL，既有呼叫不變）或 `FoliateEpubReaderView.setDecorations`（流式，新增），比照 Issue 6 `_jumpToEpubLocator()` 建立的既有分派模式；`_buildNativeView()` 的 Foliate 分支新增接上 `onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated` 三個回呼——三者的實際處理函式（`_handleSelectionChanged`／`_handleSelectionCleared`／`_handleAnnotationActivated`）與浮動工具列渲染（`AnnotationToolbar`）皆是既有、格式無關的程式碼，**完全不需要修改**，只需要接上新的呼叫來源。

**Tech Stack:** Kotlin（`org.json.JSONObject`/`JSONArray`、`WebView.evaluateJavascript`、`@JavascriptInterface`）、JavaScript（`readest/foliate-js` 既有 `overlayer.js` 的 `Overlayer.add()`/`highlight()`/`underline()`/`hitTest()`，`view.js` 的 `view.addAnnotation()`/`deleteAnnotation()`/`getCFI()`/`getCFIProgress()`，`'load'`/`'draw-annotation'`/`'show-annotation'` 事件）、Dart/Flutter（`GlobalKey<State<T>>` 強型別 static helper）、JUnit4（JVM 單元測試）、`flutter_test`（widget test）、`integration_test`（真機驗證）。

## Global Constraints

- **既有定位 JSON 格式不變**（Issue 6 已定案，見 `spec.md`「資料模型」）：`{"cfi": "epubcfi(...)", "index": N, "fraction": F}`，與 Readium `Locator.toJSON()` 完全不相容（ADR 0011「既有流式書資料視為失效」）。本工單延用不新增欄位。
- **FXL（`EpubReaderView.kt`）本次完全不修改**——design.md 決策 #7「劃線/備註排除 FXL」是既有、與本工單無關的產品決策；`ReaderScreen._handleSelectionChanged()` 開頭已有 `_isFixedLayout` 防呆（`app/lib/screens/reader_screen.dart:852`），FXL 一律不觸發選取事件，維持現狀。
- **`readest/foliate-js` 釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，只能修改 `main.js`**（本專案自己的進入點）——`view.js`／`overlayer.js`／`epub.js`／`epubcfi.js`／`progress.js`／`text-walker.js` 一律不得修改。
- **`Overlayer.add(key, range, draw, options)` 的 `key` 必須是 `view.resolveNavigation()` 可解析的目標**（見 `view.js` `addAnnotation()`），本工單一律使用 CFI 字串本身當 `key`；Dart 端的不透明 id（`"highlight:5"`）不能直接當 `value` 傳給 `view.addAnnotation()`，需另建 `decorationIdByCfi` 對照表反查（見 `reviews/spike-overlayer-annotations.md`「Overlayer 以 annotation.value 當 Map key，必須唯一」）。
- **Issue 7 Spike「風險分級與後續建議」四項硬性實作約束**（`reviews/spike-overlayer-annotations.md`）：
  1. 建構供 `view.getCFI()`/`view.addAnnotation()` 使用的 Range 一律用文字節點邊界，不可對元素節點呼叫 `selectNodeContents()`——本工單使用者選字路徑（`window.getSelection().getRangeAt(0)`）天然符合此限制，不需要額外處理。
  2. 判斷「目前畫面上實際顯示的是什麼」一律用即時查詢或當次事件呼叫的區域變數閉包，不可快取到模組級共用可變變數後於事後讀取——`'load'` 事件的 `doc`/`index` 必須各自在該次呼叫內建立區域變數，`selectionchange` callback 讀取這兩個閉包變數。
  3. 正式 App 3×3 熱區與可標記內容區域重疊時的優先權/穿透規則，本工單**不新增程式碼**解決（既有 FXL 熱區＋Readium 選字/標記互動已是相同的 Flutter `GestureDetector` 疊加 `AndroidView` 架構且已上線穩定運作，見 Task 6 驗收標準的真機人工驗證項目，若真機驗證發現實際衝突才需要另立工單處理，不在本計劃預先假設解法）。
  4. `Overlayer.highlight()`/`underline()` 的 `options` 形狀不同（`vertical: boolean` vs `writingMode: string`），依 `isUnderline` 分流組裝，不可共用同一組參數物件。
- **Dart `Color.toARGB32()`／Android `Color` int 皆為 `0xAARRGGBB` 版面**（既有慣例，見 `app/lib/reader/highlight_style.dart`），Kotlin 端需轉換為 SVG `fill`/`stroke` 屬性可用的 CSS 顏色字串（`rgba(r, g, b, a)`，`a` 為 0.0-1.0 浮點數）。
- **`EpubDecoration`／`EpubSelectionInfo`／`PercentRect`／`decodeAnnotationId()`（`app/lib/reader/epub_decoration.dart`、`epub_selection_info.dart`、`percent_rect.dart`）皆為既有、格式無關的型別，本工單不修改**——Dart 端只當作不透明字串／既有欄位處理，不需要知道底層是 CFI 還是 Readium Locator。
- **測試裝置**：沿用既有測試裝置（`3CEF42ECD491687`，Android 15/API 35）；執行前以 `adb devices -l` 重新確認裝置仍在。
- **執行環境**：所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash/MSYS2）執行，非 PowerShell／`cmd.exe`。
- **語言**：新增/修改的程式碼註解一律使用正體中文，比照本檔案既有慣例。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt` | 新增 | 純函式：`argbIntToCssColor()`（ARGB Int→CSS rgba 字串）／`buildDecorationEntries()`（Dart wire 格式→JS 端 `{id, cfi, color, isUnderline}` 格式，含優雅退回過濾） |
| `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt` | 新增 | 上述兩個純函式的 JVM 單元測試 |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | 新增 `window.setDecorations()`；`draw-annotation`／`show-annotation`／持久 `'load'`→`selectionchange` 事件監聽器；`window.applyPreferences()` 新增追蹤 `currentWritingMode` |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` | 修改 | `onMethodCall` 新增 `setDecorations` case；`FoliateBridge` 新增 `onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated` |
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 `onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated` 建構參數與對應 `_handleMethodCall` case；新增 `setDecorations` static helper |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改 | 新增上述新增介面的 widget test |
| `app/lib/screens/reader_screen.dart` | 修改 | `_handleFoliateLayoutResolved` 新增劃線/備註背景載入；`_sendDecorationsToNative()` 依 `_dispatchedIsFixedLayout` 分派；`_buildNativeView()` Foliate 分支接上三個新回呼 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增流式 EPUB 劃線/備註載入、選取顯示浮動工具列、點擊標記開啟對話框的 widget test |
| `app/integration_test/foliate_highlights_notes_test.dart` | 新增 | 真機驗證：repository 驅動的 `NotesBottomSheet` 顯示/跳轉/編輯/刪除端到端流程（比照 `epub_highlights_notes_test.dart` 既有結構），並列出無法自動化涵蓋、需人工真機驗證的項目 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 8 完成說明 |

---

### Task 1: `FoliateDecorationCodec.kt`——劃線/備註 wire 格式轉換純函式（TDD）

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt`

**Interfaces:**
- Consumes: `FoliateLocatorCodec.extractCfi(locatorJson: String?): String?`（Task 1 既有，Issue 6）。
- Produces: `FoliateDecorationCodec.argbIntToCssColor(argb: Int): String`；`FoliateDecorationCodec.buildDecorationEntries(list: List<Map<String, Any?>>): List<Map<String, Any?>>`（每個 map 含 `id: String`／`cfi: String`／`color: String`／`isUnderline: Boolean`）。Task 3 的 `FoliateEpubReaderView.kt` 依賴這兩個方法名稱與簽章。

- [ ] **Step 1: 寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliateDecorationCodecTest {

    // --- argbIntToCssColor ---

    @Test
    fun `完全不透明色值換算 alpha 為 1_0`() {
        assertEquals(
            "rgba(255, 0, 0, 1.0)",
            FoliateDecorationCodec.argbIntToCssColor(0xFFFF0000.toInt()),
        )
    }

    @Test
    fun `完全透明色值換算 alpha 為 0_0`() {
        assertEquals(
            "rgba(0, 255, 0, 0.0)",
            FoliateDecorationCodec.argbIntToCssColor(0x0000FF00),
        )
    }

    @Test
    fun `半透明色值正確拆解 RGB 並換算 alpha 為 0-1 浮點數`() {
        // highlighterYellowTint = Color(0x73FDE047)，見 highlight_style.dart。
        val result = FoliateDecorationCodec.argbIntToCssColor(0x73FDE047)
        assertEquals("rgba(253, 224, 71, ${115 / 255.0})", result)
    }

    // --- buildDecorationEntries ---

    @Test
    fun `新格式 locatorJson 正確轉換為 cfi／color／isUnderline`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:5",
                "locatorJson" to """{"cfi":"epubcfi(/6/8!/4[story-2-2])","index":3,"fraction":0.04}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(1, entries.size)
        assertEquals("highlight:5", entries[0]["id"])
        assertEquals("epubcfi(/6/8!/4[story-2-2])", entries[0]["cfi"])
        assertEquals("rgba(255, 0, 0, 1.0)", entries[0]["color"])
        assertEquals(false, entries[0]["isUnderline"])
    }

    @Test
    fun `isUnderline 缺席時預設為 false`() {
        val list = listOf(
            mapOf(
                "id" to "note:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0x73D1D5DB,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(false, entries[0]["isUnderline"])
    }

    @Test
    fun `舊格式（Readium Locator JSON）locatorJson 該筆略過`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"href":"/OEBPS/chapter1.xhtml","locations":{"progression":0.1}}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `缺少 id 欄位的項目該筆略過`() {
        val list = listOf(
            mapOf(
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0xFFFF0000.toInt(),
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `缺少 tint 欄位的項目該筆略過`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `多筆項目保留順序，單筆失敗不影響其餘`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
            mapOf(
                "id" to "highlight:2",
                "locatorJson" to """{"href":"/OEBPS/chapter1.xhtml"}""",
                "tint" to 0xFF00FF00.toInt(),
                "isUnderline" to false,
            ),
            mapOf(
                "id" to "note:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}""",
                "tint" to 0x73D1D5DB,
                "isUnderline" to true,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(2, entries.size)
        assertEquals("highlight:1", entries[0]["id"])
        assertEquals("note:1", entries[1]["id"])
        assertEquals(true, entries[1]["isUnderline"])
    }

    @Test
    fun `空清單回傳空清單`() {
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(emptyList()).isEmpty())
    }
}
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliateDecorationCodecTest"
```

預期：`FAIL`，錯誤訊息為找不到 `FoliateDecorationCodec` 類別（`Unresolved reference`）。

- [ ] **Step 3: 建立 `FoliateDecorationCodec.kt`**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt`：

```kotlin
package cc.ugotit.elinkbook

/**
 * 劃線/備註（epic-17-epub-render-migration Issue 8）從 Dart 端
 * EpubDecoration.toWire() 格式（{"id", "locatorJson", "tint", "isUnderline"}）
 * 轉換為 main.js window.setDecorations() 所需的 JS 端格式：cfi（供
 * view.addAnnotation({value: cfi}) 定位）＋color（CSS 顏色字串，供
 * Overlayer.highlight()/underline() 的 fill/stroke 屬性，不能是原始
 * 整數）。純函式，不觸碰 WebView，供 JVM 單元測試直接驗證。
 */
object FoliateDecorationCodec {
    /**
     * 把 Dart Color.toARGB32()／Android Color int 皆採用的 0xAARRGGBB
     * 版面轉換為 SVG fill/stroke 屬性可直接使用的 rgba() CSS 字串。
     */
    fun argbIntToCssColor(argb: Int): String {
        val a = (argb ushr 24) and 0xFF
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return "rgba($r, $g, $b, ${a / 255.0})"
    }

    /**
     * 把 Dart 端送來的完整標記清單（見 EpubDecoration.toWire()）轉換為
     * main.js 端需要的 {"id", "cfi", "color", "isUnderline"} 清單。單筆
     * locatorJson 解析失敗（FoliateLocatorCodec.extractCfi() 回傳
     * null——缺席、格式錯誤、或既有流式書籍留下的舊格式 Readium Locator
     * JSON，ADR 0011「既有資料視為失效」）、或缺少 id／tint 欄位時該筆
     * 略過，不影響其餘標記，比照 EpubReaderView.kt
     * applyDecorationsFromWire() 既有的非致命錯誤略過原則。
     */
    fun buildDecorationEntries(list: List<Map<String, Any?>>): List<Map<String, Any?>> {
        return list.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val locatorJson = entry["locatorJson"] as? String
            val cfi = FoliateLocatorCodec.extractCfi(locatorJson) ?: return@mapNotNull null
            val tint = (entry["tint"] as? Number)?.toInt() ?: return@mapNotNull null
            val isUnderline = entry["isUnderline"] as? Boolean ?: false
            mapOf(
                "id" to id,
                "cfi" to cfi,
                "color" to argbIntToCssColor(tint),
                "isUnderline" to isUnderline,
            )
        }
    }
}
```

- [ ] **Step 4: 執行測試確認通過**

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliateDecorationCodecTest"
```

預期：`BUILD SUCCESSFUL`，9 個測試全數 `PASS`。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt
git commit -m "feat(epic-17): 新增 FoliateDecorationCodec 純函式——劃線/備註 wire 格式轉換與色值換算"
```

---

### Task 2: `main.js`——劃線/備註原生橋接（Overlayer 疊加、選取範圍回報）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: 無新的外部依賴（`Overlayer` 為既有 `overlayer.js` 匯出的類別）。
- Produces: `window.setDecorations(decorations: [{id, cfi, color, isUnderline}]): void`，供 Task 3 的 Kotlin 端呼叫；`window.FoliateBridge.onSelectionChanged(locatorJson, fraction, leftPct, topPct, rightPct, bottomPct)`／`onSelectionCleared()`／`onAnnotationActivated(id)` 三個 JS→Kotlin 回呼，Task 3 的 `FoliateBridge` 依賴這些方法名稱與參數型別/順序。

**本 Task 無 JVM 單元測試**（比照 Issue 2-6 既定退路）：`evaluateJavascript`/`WebView`/`Overlayer` 呼叫是框架 API 的直接串接，沒有可抽出的純邏輯（可抽出的部分已在 Task 1 完成）。驗收標準是既有 JVM 測試不受影響，實際行為由 Task 6 真機 `integration_test` 與人工真機驗證。

- [ ] **Step 1: 匯入 `Overlayer`**

`app/android/app/src/main/assets/foliate/main.js` 第 1 行：

```js
import { makeBook } from './view.js'
```

改為：

```js
import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'
```

- [ ] **Step 2: 新增模組級狀態變數**

第 31 行 `let detectedBookWritingMode = null` 之後，插入：

```js

// 目前生效的排版方向（epic-17 Issue 8）：與 detectedBookWritingMode
// 不同，這個變數追蹤「目前實際套用」的方向（可能被使用者手動切換），
// 供劃線/備註繪製時判斷 Overlayer.highlight()/underline() 該用哪種
// options 形狀（見下方 draw-annotation 監聽器）。初始值於下方 FR-06 的
// { once: true } relocate 監聽器內、以及每次 window.applyPreferences()
// 呼叫時更新。
let currentWritingMode = 'horizontal'

// 目前顯示中標記的 cfi → Dart 端不透明 id（"highlight:5"/"note:12"）對照
// 表（epic-17 Issue 8）。view.addAnnotation({value}) 的 value 欄位本身
// 必須是 view.resolveNavigation() 可解析的目標（此處固定用 cfi 字串），
// 不能直接塞 Dart 端的不透明 id 字串，故另建這份表供 show-annotation
// 事件反查，見
// docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md
// 「已記錄的既有 API 落差」。window.setDecorations() 每次呼叫時整組
// 重建，非增量更新。
let decorationIdByCfi = new Map()
```

- [ ] **Step 3: `window.applyPreferences()` 追蹤 `currentWritingMode`**

原本（第 86-94 行）：

```js
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}
```

改為：

```js
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  // epic-17 Issue 8：劃線/備註繪製需要知道目前實際生效的排版方向，見
  // currentWritingMode 宣告處註解。
  if (prefs.writingMode) {
    currentWritingMode = prefs.writingMode
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}
```

- [ ] **Step 4: 新增 `window.setDecorations()`**

`window.jumpToLocator = function (cfi) { view.goTo(cfi) }`（第 124-126 行）之後、`/**\n * 遞迴解析單一目錄節點...`（第 128 行 `buildTocEntry` 的文件註解）之前，插入：

```js

/**
 * 把目前應顯示的完整標記清單一次性套用（epic-17 Issue 8，比照既有
 * window.applyPreferences「整組送出」慣例，非增量 diff）：先移除全部
 * 既有標記，再逐筆呼叫 view.addAnnotation() 重新加入。[decorations] 為
 * FoliateDecorationCodec.buildDecorationEntries() 產生的
 * [{id, cfi, color, isUnderline}, ...] 陣列，由原生端
 * FoliateEpubReaderView.kt 的 setDecorations method channel case 呼叫。
 * 實際繪製邏輯在下方 draw-annotation 監聽器（本函式只負責告知 view
 * 「這些位置需要標記」，繪製視覺樣式的決定權交給監聽器，因為 draw
 * callback 只有透過 view.addAnnotation() 觸發的 draw-annotation 事件才
 * 拿得到，見 view.js addAnnotation() 原始碼）。
 */
window.setDecorations = function (decorations) {
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi })
  }
  decorationIdByCfi = new Map()
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id)
    view.addAnnotation({ value: cfi, color, isUnderline })
  }
}
```

- [ ] **Step 5: 新增劃線/備註繪製與點擊回呼監聽器**

`async function openBook() { ... }` 內，第二個（持續推播 `onLocatorChanged` 的）`relocate` 監聽器結尾（原本第 239-247 行）：

```js
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      window.FoliateBridge.onLocatorChanged(
        JSON.stringify({ cfi, index: section?.current ?? 0, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? 0,
        location?.total ?? 0,
      )
    })
    await view.open(book)
```

改為（在 `await view.open(book)` 之前插入三個新監聽器）：

```js
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      window.FoliateBridge.onLocatorChanged(
        JSON.stringify({ cfi, index: section?.current ?? 0, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? 0,
        location?.total ?? 0,
      )
    })
    // 劃線/備註繪製（epic-17 Issue 8）：view.addAnnotation() 對於一般
    // 標記（非 foliate-search:/foliate-note: 前綴），透過 draw-annotation
    // 事件把繪製決定權交還給呼叫端（見 view.js addAnnotation() 原始碼），
    // annotation 即是 window.setDecorations() 傳入 view.addAnnotation()
    // 的 {value, color, isUnderline} 物件本身（addAnnotation() 原樣透傳，
    // 未做任何欄位過濾）。Overlayer.highlight()/underline() 的 options
    // 形狀不同（vertical: boolean vs writingMode: string），依
    // isUnderline 分流組裝，不可共用同一組參數物件（見
    // spike-overlayer-annotations.md「已記錄的既有 API 落差」）。
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation } = e.detail
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: currentWritingMode === 'vertical' ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: currentWritingMode === 'vertical',
        })
      }
    })
    // 點擊既有標記（epic-17 Issue 8）：value 即建立時傳入的 cfi（見
    // window.setDecorations()），透過 decorationIdByCfi 反查 Dart 端的
    // 不透明 id 字串（"highlight:5"/"note:12"，見 epub_decoration.dart
    // decodeAnnotationId() 編碼慣例）。查無對應（理論上不會發生，標記
    // 只可能在 setDecorations 已呼叫過後才可能被點擊）時靜默忽略，比照
    // 本檔案既有對非致命錯誤的處理原則。
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      if (id) window.FoliateBridge.onAnnotationActivated(id)
    })
    // 選取範圍即時回報（epic-17 Issue 8）：'load' 事件對 look-ahead
    // 預讀章節同樣會觸發，故 doc/index 皆從本次 'load' 呼叫的區域變數
    // 閉包讀取，不快取到模組級共用變數再事後讀取（見
    // spike-overlayer-annotations.md「已記錄的既有 API 落差」，此陷阱
    // 在該次驗證的兩條獨立程式碼路徑上各自獨立命中）。長按拖曳選字這類
    // 使用者手勢天生只會發生在目前實際可視的 iframe 上，selectionchange
    // 在背景預讀章節的 doc 上觸發時 getSelection().rangeCount 恆為 0，
    // 不需要額外的「目前是否可視」判斷。選取範圍用
    // window.getSelection().getRangeAt(0) 取得，天然是文字節點邊界
    // （非 selectNodeContents(element)），CFI round-trip 不會被壓扁，見
    // spike-overlayer-annotations.md 研究問題 #1 的既有限制說明。
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index
      doc.addEventListener('selectionchange', async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          window.FoliateBridge.onSelectionCleared()
          return
        }
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        // 座標換算（Issue 7 Spike 已驗證公式）：iframe 內局部矩形 + iframe
        // 相對外層 #view 容器的位移，除以外層容器可視尺寸。只取第一個
        // client rect 當代表矩形（多欄選取的代表 rect 策略，見
        // spike-overlayer-annotations.md「留白」段落——現有 PercentRect
        // 契約本身就只回報單一矩形，這是既有契約的限制，非本工單新增）。
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        window.FoliateBridge.onSelectionChanged(
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
        )
      })
    })
    await view.open(book)
```

- [ ] **Step 6: 靜態檢查（無自動化測試，僅檢查語法/既有測試不受影響）**

於 `app/` 目錄執行既有 Dart/Kotlin 測試，確認本檔案異動未間接影響已編譯進 APK 的其他部分：

```bash
flutter test
```

預期：全數 PASS（本 Task 未修改任何 Dart/Kotlin 檔案，僅 `main.js`，此步驟純粹是既有測試套件的迴歸確認）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-17): main.js 新增劃線/備註 Overlayer 橋接與選取範圍即時回報"
```

---

### Task 3: `FoliateEpubReaderView.kt`——`setDecorations` method channel 與 `FoliateBridge` 新增三個回呼

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`

**Interfaces:**
- Consumes: Task 1 的 `FoliateDecorationCodec.buildDecorationEntries()`；Task 2 的 `window.setDecorations()`／`window.FoliateBridge.onSelectionChanged()`／`onSelectionCleared()`／`onAnnotationActivated()`。
- Produces: method channel 新增 `setDecorations`（`decorations: List<Map<String, Any?>>`）Dart→原生介面；原生→Dart 新增 `onSelectionChanged`（`locatorJson`／`progression`／`leftPct`／`topPct`／`rightPct`／`bottomPct` 六欄位）／`onSelectionCleared`（無參數）／`onAnnotationActivated`（`String` id）。Task 4 的 Dart widget 依賴這些 method channel 名稱與參數格式，與既有 `EpubReaderView` 送給 Dart 端的欄位名稱逐一對稱。

**本 Task 無新增 JVM 單元測試**（比照 Task 2 既定退路，`evaluateJavascript`/`MethodChannel` 呼叫是框架 API 的直接串接）：驗收標準是 `compileDebugKotlin` 成功 + 既有 JVM 測試不受影響，實際行為由 Task 6 真機 `integration_test` 驗證。

- [ ] **Step 1: `onMethodCall` 新增 `setDecorations` case**

`"getTableOfContents" -> { ... }`（第 183-186 行）之後、`else -> result.notImplemented()`（第 187 行）之前：

```kotlin
            "getTableOfContents" -> {
                pendingTocResult = result
                webView.evaluateJavascript("window.getTableOfContents()", null)
            }
            else -> result.notImplemented()
```

改為：

```kotlin
            "getTableOfContents" -> {
                pendingTocResult = result
                webView.evaluateJavascript("window.getTableOfContents()", null)
            }
            "setDecorations" -> {
                @Suppress("UNCHECKED_CAST")
                val decorations =
                    call.argument<List<Map<String, Any?>>>("decorations") ?: emptyList()
                val entries = FoliateDecorationCodec.buildDecorationEntries(decorations)
                val jsonArray = JSONArray()
                entries.forEach { jsonArray.put(JSONObject(it)) }
                webView.evaluateJavascript("window.setDecorations($jsonArray)", null)
                result.success(null)
            }
            else -> result.notImplemented()
```

- [ ] **Step 2: 新增 import**

第 18-19 行：

```kotlin
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
```

改為（`JSONArray` 依字母序排列在 `JSONObject` 之前，比照 `FoliateLocatorCodec.kt` 既有的 import 順序）：

```kotlin
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
```

- [ ] **Step 3: `FoliateBridge` 新增 `onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated`**

`onTableOfContentsReady()` 方法（第 391-399 行）結尾之後、`FoliateBridge` 類別結尾的 `}`（第 400 行）之前：

```kotlin
        @JavascriptInterface
        fun onTableOfContentsReady(json: String) {
            mainHandler.post {
                if (isDisposed) return@post
                val result = pendingTocResult ?: return@post
                pendingTocResult = null
                result.success(FoliateLocatorCodec.parseTocEntries(json))
            }
        }
    }
```

改為：

```kotlin
        @JavascriptInterface
        fun onTableOfContentsReady(json: String) {
            mainHandler.post {
                if (isDisposed) return@post
                val result = pendingTocResult ?: return@post
                pendingTocResult = null
                result.success(FoliateLocatorCodec.parseTocEntries(json))
            }
        }

        /**
         * 使用者原生選字手勢建立/變動選取範圍時觸發（epic-17 Issue 8），
         * [locatorJson] 為新 CFI 格式序列化字串；[leftPct]/[topPct]/
         * [rightPct]/[bottomPct] 為選取矩形相對 WebView 容器寬高的百分比
         * （main.js 已完成座標換算，見該檔案「選取範圍即時回報」段落
         * 註解），與 Readium EpubReaderView.kt reportSelectionChanged()
         * 送出的欄位名稱一致，供 Dart 端共用同一個 EpubSelectionInfo 解析
         * 邏輯（見 foliate_epub_reader_view.dart）。
         */
        @JavascriptInterface
        fun onSelectionChanged(
            locatorJson: String,
            fraction: Double,
            leftPct: Double,
            topPct: Double,
            rightPct: Double,
            bottomPct: Double,
        ) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod(
                    "onSelectionChanged",
                    mapOf(
                        "locatorJson" to locatorJson,
                        "progression" to fraction,
                        "leftPct" to leftPct,
                        "topPct" to topPct,
                        "rightPct" to rightPct,
                        "bottomPct" to bottomPct,
                    ),
                )
            }
        }

        /**
         * 選取範圍被清除時觸發（epic-17 Issue 8），對稱既有
         * EpubReaderView.kt onDestroyActionMode() 語意。
         */
        @JavascriptInterface
        fun onSelectionCleared() {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onSelectionCleared", null)
            }
        }

        /**
         * 使用者點擊既有劃線/備註標記時觸發（epic-17 Issue 8），[id] 為
         * main.js 透過 decorationIdByCfi 反查出的 Dart 端不透明 id 字串
         * （"highlight:5"/"note:12"，見 epub_decoration.dart
         * decodeAnnotationId() 編碼慣例）。
         */
        @JavascriptInterface
        fun onAnnotationActivated(id: String) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onAnnotationActivated", id)
            }
        }
    }
```

- [ ] **Step 4: 更新類別 KDoc**

第 38-40 行：

```kotlin
 * 已實作契約：openBook／setPreferences／nextPage／previousPage／
 * jumpToProgression／jumpToLocator／getTableOfContents／onLocatorChanged；
 * 待補契約：setDecorations，見 Issue 8 依 spec.md「介面」節補上。
```

改為：

```kotlin
 * 已實作契約：openBook／setPreferences／nextPage／previousPage／
 * jumpToProgression／jumpToLocator／getTableOfContents／onLocatorChanged／
 * setDecorations／onSelectionChanged／onSelectionCleared／
 * onAnnotationActivated——與 spec.md「介面」節逐一對稱，見該檔案「模組」
 * 節列出的完整契約表。
```

- [ ] **Step 5: 編譯確認**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`。

```bash
./gradlew.bat :app:testDebugUnitTest
```

預期：`BUILD SUCCESSFUL`，既有 JVM 測試（含 Task 1 新增的 9 個 `FoliateDecorationCodecTest`）全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt
git commit -m "feat(epic-17): FoliateEpubReaderView.kt 新增 setDecorations method channel 與選取/標記點擊回呼"
```

---

### Task 4: `foliate_epub_reader_view.dart`——Dart 介面擴充（TDD）

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 3 的 method channel 契約（`setDecorations`／`onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated`）；既有 `EpubDecoration`（`app/lib/reader/epub_decoration.dart`）／`EpubSelectionInfo`（`app/lib/reader/epub_selection_info.dart`）／`PercentRect`（`app/lib/reader/percent_rect.dart`）型別，皆不修改、直接重用。
- Produces: `FoliateEpubReaderView` 新增建構參數 `onSelectionChanged: ValueChanged<EpubSelectionInfo>?`／`onSelectionCleared: VoidCallback?`／`onAnnotationActivated: ValueChanged<String>?`；新增 static helper `FoliateEpubReaderView.setDecorations(GlobalKey<State<FoliateEpubReaderView>> key, List<EpubDecoration> decorations): void`。Task 5 的 `ReaderScreen` 依賴這些建構參數名稱與 helper 簽章，與既有 `EpubReaderView` 對應介面完全對稱。

- [ ] **Step 1: 寫失敗測試——`setDecorations` static helper**

`app/test/reader/foliate_epub_reader_view_test.dart` 檔案開頭新增 import：

```dart
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
```

檔案最後（`test('EpubPositionInfo equals/hashCode/toString', () { ... });` 之後、`}` 之前）新增：

```dart

  testWidgets(
      'FoliateEpubReaderView.setDecorations() 呼叫原生端 setDecorations method channel',
      (tester) async {
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    FoliateEpubReaderView.setDecorations(key, [
      EpubDecoration.forHighlight(
        highlightId: 5,
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
        tint: 0xFFFF0000,
        isUnderline: false,
      ),
      EpubDecoration.forNote(
        noteId: 1,
        locatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
        tint: 0x73D1D5DB,
      ),
    ]);
    await tester.pump();

    final call = calls.firstWhere((c) => c.method == 'setDecorations');
    expect(call.arguments['decorations'], [
      {
        'id': 'highlight:5',
        'locatorJson': '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
        'tint': 0xFFFF0000,
        'isUnderline': false,
      },
      {
        'id': 'note:1',
        'locatorJson': '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
        'tint': 0x73D1D5DB,
        'isUnderline': false,
      },
    ]);
  });

  testWidgets('原生端呼叫 onSelectionChanged 時，觸發 widget.onSelectionChanged 並正確解析欄位',
      (tester) async {
    EpubSelectionInfo? captured;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionChanged: (info) => captured = info,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
        const MethodCall('onSelectionChanged', {
          'locatorJson': '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
          'progression': 0.3,
          'leftPct': 0.1,
          'topPct': 0.2,
          'rightPct': 0.4,
          'bottomPct': 0.25,
        }),
      ),
      (data) {},
    );

    expect(captured, isNotNull);
    expect(captured!.locatorJson,
        '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}');
    expect(captured!.progression, 0.3);
    expect(captured!.rect, const PercentRect(
      left: 0.1, top: 0.2, right: 0.4, bottom: 0.25,
    ));
  });

  testWidgets('原生端呼叫 onSelectionCleared 時，觸發 widget.onSelectionCleared',
      (tester) async {
    var cleared = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCleared: () => cleared = true,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec
          .encodeMethodCall(const MethodCall('onSelectionCleared')),
      (data) {},
    );

    expect(cleared, isTrue);
  });

  testWidgets(
      '原生端呼叫 onAnnotationActivated 時，觸發 widget.onAnnotationActivated 並帶入 id',
      (tester) async {
    String? activatedId;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onAnnotationActivated: (id) => activatedId = id,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
          const MethodCall('onAnnotationActivated', 'highlight:5')),
      (data) {},
    );

    expect(activatedId, 'highlight:5');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：新增的 4 個測試 `FAIL`（`onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated`/`setDecorations` 皆不存在）。

- [ ] **Step 3: 新增建構參數與 import**

`app/lib/reader/foliate_epub_reader_view.dart` 第 1-10 行 import 區塊：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_position_info.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'toc_entry.dart';
import 'writing_mode.dart';
import 'zone_action.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'toc_entry.dart';
import 'writing_mode.dart';
import 'zone_action.dart';
```

`final ValueChanged<EpubPositionInfo>? onLocatorChanged;`（第 80 行）之後、`const FoliateEpubReaderView({`（第 82 行）之前：

```dart
  /// 目前定位變動時觸發（開書、翻頁、目錄跳轉），供呼叫端（ReaderScreen）
  /// 快取最新定位，於離開/背景時寫入資料庫，比照
  /// [EpubReaderView.onLocatorChanged] 既有模式。
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;

  const FoliateEpubReaderView({
```

改為：

```dart
  /// 目前定位變動時觸發（開書、翻頁、目錄跳轉），供呼叫端（ReaderScreen）
  /// 快取最新定位，於離開/背景時寫入資料庫，比照
  /// [EpubReaderView.onLocatorChanged] 既有模式。
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;

  /// 使用者原生選字手勢建立/變動選取範圍時觸發（epic-17-epub-render-migration
  /// Issue 8），供呼叫端顯示浮動工具列，比照 [EpubReaderView.onSelectionChanged]
  /// 既有模式，[EpubSelectionInfo] 型別完全重用。
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;

  /// 選取範圍被清除時觸發，供呼叫端收起浮動工具列，比照
  /// [EpubReaderView.onSelectionCleared] 既有模式。
  final VoidCallback? onSelectionCleared;

  /// 使用者點擊既有劃線/備註標記時觸發，傳回該筆標記的 id 字串，比照
  /// [EpubReaderView.onAnnotationActivated] 既有模式與
  /// `EpubDecoration` 的 id 編碼慣例。
  final ValueChanged<String>? onAnnotationActivated;

  const FoliateEpubReaderView({
```

`this.onLocatorChanged,`（第 106 行）之後、`});`（第 107 行）之前：

```dart
    this.onLocatorChanged,
  });
```

改為：

```dart
    this.onLocatorChanged,
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onAnnotationActivated,
  });
```

- [ ] **Step 4: 新增 `setDecorations` static helper**

`static Future<List<TocEntry>> loadTableOfContents(...) async { ... }`（第 164-175 行）結尾之後、`@override\n  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();`（第 177-178 行）之前：

```dart

  /// 把目前應顯示的完整標記清單一次性送給原生端（epic-17-epub-render-migration
  /// Issue 8，比照既有 `setPreferences` 整組送出慣例，非增量 diff），比照
  /// [EpubReaderView.setDecorations] 既有模式，`EpubDecoration` 型別完全
  /// 重用。
  static void setDecorations(
    GlobalKey<State<FoliateEpubReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('setDecorations', {
        'decorations': decorations.map((d) => d.toWire()).toList(),
      });
    }
  }
```

- [ ] **Step 5: `_handleMethodCall` 新增三個 case**

`case 'onLocatorChanged': ... break;`（第 267-275 行）之後、`}`（第 276 行，`switch` 結尾）之前：

```dart
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          pageIndex: (args['pageIndex'] as num?)?.toInt(),
          totalPages: (args['totalPages'] as num?)?.toInt(),
        ));
        break;
    }
```

改為：

```dart
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          pageIndex: (args['pageIndex'] as num?)?.toInt(),
          totalPages: (args['totalPages'] as num?)?.toInt(),
        ));
        break;
      case 'onSelectionChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          rect: PercentRect(
            left: (args['leftPct'] as num).toDouble(),
            top: (args['topPct'] as num).toDouble(),
            right: (args['rightPct'] as num).toDouble(),
            bottom: (args['bottomPct'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCleared':
        widget.onSelectionCleared?.call();
        break;
      case 'onAnnotationActivated':
        widget.onAnnotationActivated?.call(call.arguments as String);
        break;
    }
```

- [ ] **Step 6: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：全數 PASS。

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): foliate_epub_reader_view.dart 新增劃線/備註介面——setDecorations/onSelectionChanged/onSelectionCleared/onAnnotationActivated"
```

---

### Task 5: `ReaderScreen`——接上流式 EPUB 的劃線與備註（TDD）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `FoliateEpubReaderView.setDecorations()`／`onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated`。
- Produces: 無新的對外介面（`ReaderScreen` 公開建構參數不變）——本 Task 純粹是把既有、格式無關的 `_handleSelectionChanged`／`_handleSelectionCleared`／`_handleAnnotationActivated`／`_sendDecorationsToNative` 接上流式 EPUB 分支。

- [ ] **Step 1: 寫失敗測試——`onLayoutResolved` 觸發劃線/備註載入並送給正確的原生 key**

`app/test/screens/reader_screen_test.dart` 第 30 行 `import '../support/fake_notes_repository.dart';` 之後，新增（本檔案先前皆透過既有 helper 間接使用這些型別，未曾在檔案內直接建構 `EpubSelectionInfo`/`Highlight` 物件，故需新增下列 import）：

```dart
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/percent_rect.dart';
```

找到既有測試區塊：

```dart
  // ─────────────────────────────────────────────────────────────────────
  // epic-17-epub-render-migration Issue 6：流式 EPUB 目錄跳轉、定位
  // 持久化與頁尾頁碼測試。
  // ─────────────────────────────────────────────────────────────────────
```

在這個區塊**之前**（即 Issue 5 測試區塊結尾之後）插入新區塊：

```dart
  // ─────────────────────────────────────────────────────────────────────
  // epic-17-epub-render-migration Issue 8：流式 EPUB 劃線/備註測試。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets(
      '流式 EPUB：提供 highlightsRepository／notesRepository 時，onLayoutResolved 觸發後呼叫 FoliateEpubReaderView 的 setDecorations（非 EpubReaderView）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));

    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_annotations_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(const EpubLayoutInfo(
      isFixedLayout: false,
      writingMode: WritingMode.horizontal,
    ));
    await tester.pump();
    // _reloadAnnotationsAndRefreshDecorations() 內部 await repository
    // 呼叫，需多一次 pump 讓 microtask 完成。
    await tester.pump();

    expect(instanceCalls.any((c) => c.method == 'setDecorations'), isTrue);
  });

  testWidgets('流式 EPUB：onSelectionChanged 觸發後顯示 AnnotationToolbar',
      (tester) async {
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_selection_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onSelectionChanged?.call(const EpubSelectionInfo(
      locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
      rect: PercentRect(left: 0.2, top: 0.3, right: 0.5, bottom: 0.35),
    ));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);

    foliateView.onSelectionCleared?.call();
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);
  });

  testWidgets(
      '流式 EPUB：onAnnotationActivated 觸發後開啟劃線/備註編輯對話框',
      (tester) async {
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_activate_foliate',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_activate_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(const EpubLayoutInfo(
      isFixedLayout: false,
      writingMode: WritingMode.horizontal,
    ));
    await tester.pump();
    await tester.pump();

    tester
        .widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView))
        .onAnnotationActivated
        ?.call('highlight:$highlightId');
    await tester.pumpAndSettle();

    expect(find.text('劃線/備註'), findsOneWidget);
    expect(find.text('🗑️ 刪除此劃線與備註'), findsOneWidget);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：新增的 3 個測試 `FAIL`（`setDecorations` 未被呼叫、`AnnotationToolbar` 未顯示、對話框未開啟）。

- [ ] **Step 3: `_handleFoliateLayoutResolved` 新增劃線/備註背景載入**

`app/lib/screens/reader_screen.dart` 第 798-836 行：

```dart
  /// FoliateEpubReaderView（流式）專屬的 onLayoutResolved 處理。
  /// epic-17-epub-render-migration Issue 4 起，也設定
  /// `_autoDetectedWritingMode` 並重新計算 `_resolved`（比照
  /// `_handleLayoutResolved` 對應段落），讓「版面設定」按鈕能對流式書籍
  /// 生效。Issue 6 起新增目錄背景抓取（比照 `_handleLayoutResolved`
  /// 對應段落，改呼叫 `FoliateEpubReaderView.loadTableOfContents()`
  /// 而非 `EpubReaderView` 的版本）——不需要像 Readium 分支那樣額外檢查
  /// `!info.isFixedLayout`，因為本方法只會被 `FoliateEpubReaderView`
  /// （恆為流式）呼叫。**仍然刻意不**觸發
  /// `_reloadAnnotationsAndRefreshDecorations`／`_loadFxlBookmarks`——這兩
  /// 個呼叫對尚未掛載的 `EpubReaderView`/`_epubReaderViewKey` 雖然會靜默
  /// no-op、技術上無害，但會讓 `_annotationsLoaded` 被誤判為「已完成」，
  /// 使「筆記」按鈕看似可用卻永遠開出空清單/無法互動。劃線備註仍是
  /// Issue 8 的範圍。
  void _handleFoliateLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
      final loaded = _loaded;
      if (loaded != null) {
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: info.writingMode,
        );
      }
    });
    if (_tocEntries.isEmpty && !_tocLoaded) {
      FoliateEpubReaderView.loadTableOfContents(_foliateEpubReaderViewKey)
          .then((entries) {
        if (!mounted) return;
        setState(() {
          _tocEntries = entries;
          _tocLoaded = true;
        });
      });
    }
  }
```

改為：

```dart
  /// FoliateEpubReaderView（流式）專屬的 onLayoutResolved 處理。
  /// epic-17-epub-render-migration Issue 4 起，也設定
  /// `_autoDetectedWritingMode` 並重新計算 `_resolved`（比照
  /// `_handleLayoutResolved` 對應段落），讓「版面設定」按鈕能對流式書籍
  /// 生效。Issue 6 起新增目錄背景抓取（比照 `_handleLayoutResolved`
  /// 對應段落，改呼叫 `FoliateEpubReaderView.loadTableOfContents()`
  /// 而非 `EpubReaderView` 的版本）——不需要像 Readium 分支那樣額外檢查
  /// `!info.isFixedLayout`，因為本方法只會被 `FoliateEpubReaderView`
  /// （恆為流式）呼叫。Issue 8 起新增劃線/備註背景載入（比照
  /// `_handleLayoutResolved` 對應段落，改呼叫
  /// `FoliateEpubReaderView.setDecorations()` 而非 `EpubReaderView`
  /// 的版本，見 `_sendDecorationsToNative()`）——同樣不需要額外檢查
  /// `!info.isFixedLayout`。
  void _handleFoliateLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
      final loaded = _loaded;
      if (loaded != null) {
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: info.writingMode,
        );
      }
    });
    if (_tocEntries.isEmpty && !_tocLoaded) {
      FoliateEpubReaderView.loadTableOfContents(_foliateEpubReaderViewKey)
          .then((entries) {
        if (!mounted) return;
        setState(() {
          _tocEntries = entries;
          _tocLoaded = true;
        });
      });
    }
    if (!_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
  }
```

- [ ] **Step 4: `_sendDecorationsToNative()` 依 `_dispatchedIsFixedLayout` 分派**

第 920-941 行：

```dart
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.id != null && highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id!,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.id != null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id!,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    EpubReaderView.setDecorations(_epubReaderViewKey, decorations);
  }
```

改為：

```dart
  /// 比照 `_jumpToEpubLocator()`（Issue 6）建立的分派模式：FXL
  /// （Readium）用 `EpubReaderView.setDecorations`，流式（foliate-js）用
  /// `FoliateEpubReaderView.setDecorations`。
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.id != null && highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id!,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.id != null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id!,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    if (_dispatchedIsFixedLayout == true) {
      EpubReaderView.setDecorations(_epubReaderViewKey, decorations);
    } else {
      FoliateEpubReaderView.setDecorations(_foliateEpubReaderViewKey, decorations);
    }
  }
```

- [ ] **Step 5: `_buildNativeView()` Foliate 分支接上三個新回呼**

第 1571-1598 行（`FoliateEpubReaderView(...)` 建構）：

```dart
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
            writingMode: resolved.writingMode,
            pageTurnMode: resolved.pageTurnMode,
            fontFamily: resolved.fontFamily,
            fontSize: resolved.fontSize,
            fontWeight: resolved.fontWeight,
            lineHeight: resolved.lineHeight,
            paragraphSpacing: resolved.paragraphSpacing,
            pageMargins: resolved.pageMargins,
            textAlign: resolved.textAlign,
            publisherStyles: resolved.publisherStyles,
            navZoneActions: resolved.navZoneActions,
            onZoneAction: _handleZoneAction,
            showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
            initialLocatorJson: _initialPosition?.epubLocatorJson,
            onLocatorChanged: (info) {
              if (!mounted) return;
              setState(() => _epubPositionInfo = info);
            },
          );
        }
```

改為：

```dart
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
            writingMode: resolved.writingMode,
            pageTurnMode: resolved.pageTurnMode,
            fontFamily: resolved.fontFamily,
            fontSize: resolved.fontSize,
            fontWeight: resolved.fontWeight,
            lineHeight: resolved.lineHeight,
            paragraphSpacing: resolved.paragraphSpacing,
            pageMargins: resolved.pageMargins,
            textAlign: resolved.textAlign,
            publisherStyles: resolved.publisherStyles,
            navZoneActions: resolved.navZoneActions,
            onZoneAction: _handleZoneAction,
            showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
            initialLocatorJson: _initialPosition?.epubLocatorJson,
            onLocatorChanged: (info) {
              if (!mounted) return;
              setState(() => _epubPositionInfo = info);
            },
            onSelectionChanged: _handleSelectionChanged,
            onSelectionCleared: _handleSelectionCleared,
            onAnnotationActivated: _handleAnnotationActivated,
          );
        }
```

- [ ] **Step 6: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數 PASS。

```bash
flutter test
```

預期：全數 PASS（全套件迴歸確認）。

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-17): ReaderScreen 接上流式 EPUB 的劃線與備註——setDecorations 分派、選取事件、標記點擊"
```

---

### Task 6: 真機整合測試——`foliate_highlights_notes_test.dart`

**Files:**
- Create: `app/integration_test/foliate_highlights_notes_test.dart`

**Interfaces:**
- Consumes: Task 1-5 的全部產出。
- Produces: 真機驗證證據，供 Task 7 全面驗證引用。

- [ ] **Step 1: 建立整合測試（repository 驅動的 NotesBottomSheet CRUD 流程）**

建立 `app/integration_test/foliate_highlights_notes_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 【真機人工驗證清單，本測試無法自動涵蓋】
  // 比照 epub_highlights_notes_test.dart（Readium/FXL 世代）既有結構與
  // 限制：Flutter integration_test 對 PlatformView（AndroidView）內部
  // 原生 WebView 的觸控事件模擬並不可靠。以下項目須另外以真實裝置人工
  // 驗證，不在本檔案自動化範圍：
  //   1. 原生長按+拖曳選字手勢確實觸發 onSelectionChanged、浮動工具列
  //      正確定位於選取範圍上方（main.js 的 'load'→selectionchange
  //      監聽器與座標換算公式，見 spike-overlayer-annotations.md 研究
  //      問題 #2）。
  //   2. 點擊螢光筆三色/底線按鈕，Overlayer.highlight()/underline() 疊加
  //      的視覺樣式與資料庫寫入一致；純備註淡灰底視覺可辨識（研究問題
  //      #1）。
  //   3. 點擊既有標記觸發 onAnnotationActivated、編輯/刪除 Dialog 正確
  //      開啟（研究問題 #3，含「熱區與可標記內容重疊」風險，見
  //      Global Constraints 第 3 點）。
  //   4. 直排/橫排切換後，既有劃線視覺仍正確跟隨文字位置（
  //      draw-annotation 監聽器依 currentWritingMode 分流 vertical/
  //      writingMode 兩種 options 形狀是否正確生效）。
  // 本檔案改為驗證「repository 驅動」的部分：預先透過 Repository 寫入
  // 劃線/備註資料（模擬手勢建立後的最終資料狀態，locatorJson 採用本
  // Epic 的新 CFI 格式），驗證 NotesBottomSheet 清單顯示、跳轉、編輯、
  // 刪除的端到端流程（比照 epub_highlights_notes_test.dart 既有結構）。

  testWidgets(
      '流式 EPUB：預先寫入劃線＋依附備註，NotesBottomSheet 正確顯示合併清單並可跳轉/刪除',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'foliate_highlights_notes.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_highlights_foliate',
      title: '流式劃線測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_highlights_foliate',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.05}',
      progression: 0.05,
    ));
    await notesRepository.insert(Note(
      bookId: 'b_highlights_foliate',
      text: '這段很重要',
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.05}',
      progression: 0.05,
      highlightId: highlightId,
    ));
    final pureNoteId = await notesRepository.insert(const Note(
      bookId: 'b_highlights_foliate',
      text: '純備註內容',
      epubLocatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.3}',
      progression: 0.3,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_highlights_foliate',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('這段很重要'), findsOneWidget);
    expect(find.text('純備註內容'), findsOneWidget);

    // 點選合併項目後 Bottom Sheet 應關閉（跳轉本身的原生渲染結果無法在
    // widget test 層級斷言，比照既有書籤測試的既定限制）。
    await tester.tap(find.text('這段很重要'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 重新開啟，驗證編輯純備註文字持久化生效。
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_sheet_annotation_edit_$pureNoteId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '已編輯的純備註');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('已編輯的純備註'), findsOneWidget);
    expect(find.text('純備註內容'), findsNothing);
    final notesAfterEdit = await notesRepository.listByBook('b_highlights_foliate');
    expect(notesAfterEdit.firstWhere((n) => n.id == pureNoteId).text, '已編輯的純備註');

    // 關閉 Bottom Sheet，重新開啟驗證單筆刪除（劃線+備註一併消失）持久化生效。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_h${highlightId}_n1')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b_highlights_foliate'), isEmpty);
    expect(find.text('這段很重要'), findsNothing);
    expect(find.text('已編輯的純備註'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 於真機執行確認通過**

```bash
cd app
flutter test integration_test/foliate_highlights_notes_test.dart -d 3CEF42ECD491687
```

預期：PASS。

- [ ] **Step 3: 真機人工驗證（本檔案自動化範圍外）**

比照上方測試檔開頭「真機人工驗證清單」註解，於真機（`3CEF42ECD491687`）以正式 App 手動操作驗證：

1. 開啟一本流式 EPUB，長按拖曳選取一段文字，確認出現浮動工具列（`AnnotationToolbar`）且定位於選取範圍附近。
2. 點擊螢光筆黃/粉/藍三色任一，確認畫面出現對應顏色的半透明矩形疊加；點擊底線按鈕，確認畫面出現底線；點擊「備註」新增純文字備註，確認出現淡灰底標示。
3. 點擊步驟 2 建立的既有標記，確認開啟「劃線/備註」編輯/刪除對話框。
4. 切換直排/橫排，確認既有劃線視覺仍正確跟隨文字位置（尤其底線方向）。
5. 確認 3×3 導航熱區與步驟 2 建立的標記位置重疊時，點擊標記仍能正確觸發 `onAnnotationActivated`（而非被熱區攔截觸發翻頁/選單），若發現衝突記錄具體重現步驟於 `issues.md` Issue 8 段落，另立後續 issue 追蹤，不阻塞本工單（見 Global Constraints 第 3 點）。

把觀察結果（通過/發現的問題）記錄於 `docs/epics/epic-17-epub-render-migration/issues.md` Issue 8 段落（Task 7 一併完成）。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/foliate_highlights_notes_test.dart
git commit -m "test(epic-17): 新增流式 EPUB 劃線/備註真機整合測試"
```

---

### Task 7: 全面驗證

**Files:** 無新增/修改檔案（除 Step 6 的 `issues.md` 狀態更新）。

**Interfaces:**
- Consumes: Task 1-6 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [ ] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS（Issue 6 完成時基準為 579 個測試，本工單 Task 4 新增 4 個、Task 5 新增 3 個，預期共 586 個）。

- [ ] **Step 2: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 3: 執行 Kotlin 編譯與 JVM 測試**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:testDebugUnitTest
```

預期：兩者皆 `BUILD SUCCESSFUL`（103 個既有 JVM 測試 + Task 1 新增 9 個 `FoliateDecorationCodecTest`，共 112 個）。

- [ ] **Step 4: 於真機執行 Foliate 相關 `integration_test`**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_stream_nav_zone_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_highlights_notes_test.dart -d 3CEF42ECD491687
```

預期：全數 PASS。並完成 Task 6 Step 3 的真機人工驗證清單。

- [ ] **Step 5: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-6 修改/新增的檔案，無不相關的暫存產物。

- [ ] **Step 6: 更新 `issues.md` Issue 8 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 8」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1-7 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-8.md` Task 1-6 完成 `FoliateDecorationCodec.kt`（純函式：`argbIntToCssColor`／`buildDecorationEntries`，含 9 個 JVM 測試）／`main.js`（`window.setDecorations`、`draw-annotation`／`show-annotation`／持久 `'load'`→`selectionchange` 監聽器）／`FoliateEpubReaderView.kt`（`setDecorations` method channel、`onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated` 橋接）／`foliate_epub_reader_view.dart`（對稱介面擴充）／`ReaderScreen`（`_handleFoliateLayoutResolved` 觸發劃線/備註背景載入、`_sendDecorationsToNative()` 依 `_dispatchedIsFixedLayout` 分派、`_buildNativeView()` 接上三個新回呼）。新增真機整合測試 `foliate_highlights_notes_test.dart`。`flutter test`（586 tests）／`flutter analyze`／`./gradlew.bat :app:compileDebugKotlin`／`./gradlew.bat :app:testDebugUnitTest`（112 tests）以及真機 `integration_test` 皆全數通過。真機人工驗證清單（見 `foliate_highlights_notes_test.dart` 開頭註解）：[於此填入實際驗證結果]。
```

- [ ] **Step 7: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 8 完成，更新 issues.md 狀態"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 8 描述逐項對應：
- `setDecorations`（把目前應顯示的完整標記清單一次性送給原生端，原生端解析 `EpubDecoration.locatorJson` 為 `foliate-js` 的 CFI，透過 `Overlayer.add()` 疊加）→ Task 1（`FoliateDecorationCodec.buildDecorationEntries`）+ Task 2（`main.js` `window.setDecorations`/`draw-annotation` 監聽器）+ Task 3（Kotlin `setDecorations` case）+ Task 4（Dart static helper）。
- `onSelectionChanged`／`onSelectionCleared`（使用者原生選字手勢建立/變動/清除選取範圍時觸發，`rect: PercentRect` 依 Issue 7 驗證出的座標換算方式）→ Task 2（`main.js` 持久 `'load'`→`selectionchange` 監聽器）+ Task 3（Kotlin 回呼）+ Task 4（Dart `_handleMethodCall` case）。
- `onAnnotationActivated`（使用者點擊既有標記時觸發，傳回該筆標記的 id 字串，沿用既有 `EpubDecoration.forHighlight`/`forNote` 編碼慣例與 `decodeAnnotationId()` 解析函式，完全不需要修改）→ Task 2（`main.js` `show-annotation` 監聽器＋`decorationIdByCfi` 反查）+ Task 3（Kotlin 回呼）+ Task 4（Dart `_handleMethodCall` case）；`decodeAnnotationId()` 確認全程不修改。
- `ReaderScreen` 流式 `foliate-js` 分支接上上述三個回呼，複用既有的浮動工具列/編輯 Dialog 邏輯（`epic-6-annotations` 既有元件，非本工單新增）→ Task 5（`_buildNativeView()` 接上三個回呼，`_handleSelectionChanged`/`_handleSelectionCleared`/`_handleAnnotationActivated`/`AnnotationToolbar` 皆確認為既有、格式無關程式碼，完全不修改）。

**單元測試要求逐項對應**：
- `foliate_epub_reader_view.dart`：mock method channel 驗證 `onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 正確解析與轉發；`setDecorations` 正確序列化 `EpubDecoration` 清單 → Task 4 Step 1 的 4 個測試逐一對應。
- JVM 單元測試：CFI 解析與 `Overlayer.add()` 呼叫的橋接邏輯（若抽出可測的純邏輯）→ Task 1 的 `FoliateDecorationCodec`（`buildDecorationEntries` 涵蓋 CFI 解析優雅退回，`argbIntToCssColor` 涵蓋色值換算），`Overlayer.add()` 呼叫本身是 JS 端 `evaluateJavascript` 串接，無法/不需要 JVM 測試，比照 Task 2/3「無 JVM 單元測試」既定退路。

**驗收標準逐項對應**：
- 上述測試皆通過、`flutter analyze` 乾淨 → Task 7 Step 1-2。
- `integration_test`（真實裝置，比照 `epic-6-annotations` 既有 `epub_highlights_notes_test.dart` 涵蓋範圍）：新增劃線（三色＋螢光筆）、新增備註、點擊既有標記觸發編輯、直排/橫排切換時劃線/備註視覺一致（FR-13/14/15/16 對流式 EPUB 的既有驗收標準，換引擎後行為等價）→ Task 6（repository 驅動的自動化測試涵蓋清單顯示/跳轉/編輯/刪除；三色/螢光筆/底線視覺、原生選字手勢、直排橫排視覺一致性，因 Flutter `integration_test` 對 `PlatformView` 內部原生 WebView 手勢模擬的既有限制〔比照 `epub_highlights_notes_test.dart`/PDF 長按框選/FXL 三欄熱區既有慣例〕，改列為 Task 6 Step 3 真機人工驗證清單，非自動化涵蓋缺口）。

**Placeholder 掃描**：全文檢查未發現「TBD」/「待補」/「依實際情況調整」等佔位語句（Task 7 Step 6 的 `issues.md` 範例文字中「[於此填入實際驗證結果]」是刻意留給實作者於 Task 6 Step 3 真機驗證**完成後**填入的欄位，非計劃本身的邏輯空缺——比照既有 `plans/` 慣例，完成摘要本來就需要填入實際數據，該行是範例模板的一部分），所有程式碼區塊皆為完整可執行內容。

**型別一致性檢查**：`FoliateDecorationCodec.argbIntToCssColor(Int): String`／`buildDecorationEntries(List<Map<String, Any?>>): List<Map<String, Any?>>` 的簽章在 Task 1（定義）與 Task 3（`FoliateEpubReaderView.kt` 呼叫）逐字一致；`FoliateEpubReaderView.setDecorations(GlobalKey<State<FoliateEpubReaderView>>, List<EpubDecoration>)` 在 Task 4（定義）、Task 5（`ReaderScreen._sendDecorationsToNative()` 呼叫）、Task 4 自身測試（呼叫）三處保持一致；`onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 三個建構參數的型別（`ValueChanged<EpubSelectionInfo>?`／`VoidCallback?`／`ValueChanged<String>?`）在 Task 4（定義）、Task 5（`ReaderScreen._buildNativeView()` 傳入既有 `_handleSelectionChanged`/`_handleSelectionCleared`/`_handleAnnotationActivated`，三者簽章確認與既有 `EpubReaderView` 對應建構參數完全一致，無需修改）兩處保持一致，與既有 `EpubReaderView` 對應介面型別逐一相同，無 `onDecorationTapped`/`onActivated` 等不一致別名。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-8.md`. Two execution options:

1. **Subagent-Driven（推薦）**——每個 Task 派一個全新 subagent 執行，Task 之間插入審查
2. **Inline Execution**——本 session 內批次執行，設檢查點審查

**採用哪一種方式？**
