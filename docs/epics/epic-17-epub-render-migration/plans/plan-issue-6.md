# Epic 17 Issue 6 — 目錄跳轉與定位持久化／頁碼顯示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `FoliateEpubReaderView`（Issue 3-5 已建置，目前只能開書＋套用版面偏好＋換頁／熱區）支援讀取全書目錄並跳轉、持久化目前定位（開書記憶位置／書籤／備註跳轉）、以及頁尾精確頁碼顯示——皆改用 `readest/foliate-js` 原生的 CFI 定位（與 Readium `Locator.toJSON()` 完全不同、不相容的新 JSON 格式），對既有（遷移前）流式書籍留下的舊格式資料能優雅退回、不崩潰。

**Architecture:** 新增一個純 Kotlin、JVM 可測的 `FoliateLocatorCodec` 物件，負責「新格式定位 JSON ↔ CFI 字串」與「目錄 JSON 陣列 ↔ Dart `TocEntry` wire 格式」的轉換與優雅退回判斷（是否為新格式、能否解析），`FoliateEpubReaderView.kt`／`main.js` 本身不重新實作這些判斷邏輯。原生端新增 `jumpToLocator`／`getTableOfContents` 兩個 method channel case；`getTableOfContents` 是本 Epic 第一個「Kotlin 呼叫 JS 非同步函式並等待結果」的橋接（`WebView.evaluateJavascript()` 的 callback **不會**等待 JS `async function` 內部的 `Promise` resolve，只會拿到同步序列化結果），故改由 JS 完成計算後主動呼叫 `window.FoliateBridge.onTableOfContentsReady()` 回報，Kotlin 端暫存對應的 `MethodChannel.Result` 等回呼觸發後才 `result.success()`。`main.js` 新增持續（非 `{ once: true }`）的 `relocate` 事件監聽器，把 `foliate-js` 內建的 `SectionProgress.getProgress()` 輸出（`fraction`／`location.current`／`location.total`）透過 `FoliateBridge.onLocatorChanged()` 持續推播給 Kotlin，Kotlin 原樣轉發給 Dart。Dart 端 `EpubPositionInfo` 加法性擴充 `pageIndex`/`totalPages` 兩個新欄位（`EpubReaderView`／Readium 路徑永遠不填，不受影響）。`ReaderScreen` 新增私有 helper `_jumpToEpubLocator()` 依既有 `_dispatchedIsFixedLayout` 旗標分派到 `EpubReaderView.jumpToLocator`（FXL）或 `FoliateEpubReaderView.jumpToLocator`（流式），取代目前 3 處寫死呼叫 `EpubReaderView` 的呼叫點；`_handleFoliateLayoutResolved` 新增觸發一次性目錄背景抓取（比照 `_handleLayoutResolved` 既有模式）；新增 `_buildFoliateEpubFooter()`，直接使用 `pageIndex`/`totalPages`（非估算值），與既有 `_buildEpubFooter`（Readium 遺留路徑，字元數估算，本 Issue 不修改、不重用其邏輯）並存。

**Tech Stack:** Kotlin（`org.json.JSONObject`/`JSONArray`、`WebView.evaluateJavascript`、`@JavascriptInterface`）、JavaScript（`readest/foliate-js` 既有 `book.toc`／`book.resolveHref()`／`book.sections[i].createDocument()`／`view.getCFI()`／`view.getCFIProgress()`／`view.goTo()`／`view.init({lastLocation})`，見 `epub.js`/`view.js`/`progress.js`）、Dart/Flutter（`GlobalKey<State<T>>` 強型別 static helper）、JUnit4（JVM 單元測試）、`flutter_test`（widget test）、`integration_test`（真機驗證）。

## Global Constraints

- **新增定位 JSON 格式**（見 `spec.md`「資料模型」，與 Readium `Locator.toJSON()` 完全不同、不相容，ADR 0011「既有流式書資料視為失效」）：
  ```json
  { "cfi": "epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)", "index": 3, "fraction": 0.042091 }
  ```
  對應 `relocate` 事件（`view.js` `#onRelocate()`，透傳 `this.lastLocation`）回傳的 `cfi`／`section.current`（即 index）／`fraction` 三欄位。`onLocatorChanged`／`initialLocatorJson`／`TocEntry.locatorJson` 的 `String` 欄位裝的就是這段 JSON 序列化後的字串；**Dart 端不解析其內部結構**，只負責持久化與原樣傳回原生端，型別簽章不變。
- **`WebView.evaluateJavascript()` 不會等待 JS `async function` 內部的 `Promise` resolve**（已查證 Android WebView 官方行為：callback 拿到的是表達式「同步求值」的序列化結果，對 `async function` 呼叫而言就是 `Promise` 物件本身的無意義序列化）：`getTableOfContents` 這種「Kotlin 需要等 JS 算完才能回應 Dart」的請求/回應，**不可**依賴 `evaluateJavascript` 的 callback 參數，必須讓 JS 算完後主動呼叫 `window.FoliateBridge.onXxxReady()` 回報，Kotlin 暫存對應的 `MethodChannel.Result` 等回呼觸發才完成。`jumpToLocator`／`nextPage` 等既有 fire-and-forget 呼叫不受此限制影響（呼叫端本來就不等待結果）。
- **新格式 JSON 的「是否可解析」判斷一律在 Kotlin `FoliateLocatorCodec`（純函式，JVM 可測）完成，不在 JS 或 Dart 端重複實作**：JS 端的 `window.jumpToLocator(cfi)` 直接接收「已驗證過的 CFI 字串」（而非整段定位 JSON），`main.js` 本身不需要也不應該再自行 `JSON.parse`/判斷格式。
- **舊格式資料的優雅退回**（ADR 0011）：`initialLocatorJson`／`jumpToLocator` 的 `locatorJson` 引數若是既有流式書籍留下的 Readium Locator JSON（完全不同的欄位結構，例如 `{"href":"...","locations":{...},"type":"..."}`，沒有 `cfi` 這個鍵）或其他無效 JSON，`FoliateLocatorCodec.extractCfi()` 一律回傳 `null`，呼叫端視為「無有效定位」，**不拋出例外**：`initialLocatorJson` 情境下退回「從書本開頭開始」（`view.init({})` 既有預設行為，Issue 1/3 已驗證）；`jumpToLocator` 情境下該次呼叫直接不執行任何跳轉動作。
- **`FoliateEpubReaderView` 不送出 `totalCharacterCount`、不呼叫任何字數統計**（`EpubCharacterCounter` 完全不適用本 widget，見 issues.md 明確禁止）：頁尾頁碼改由 `onLocatorChanged` 新增的 `pageIndex`/`totalPages` 欄位直接驅動，**不**新增 `totalCharacterCount`/`onCharacterCountReady` 建構參數，**不**重用既有 `_buildEpubFooter`（`EpubPageEstimator` 字元數估算路徑，那是 Readium 遺留路徑，post-epic-17 對流式書籍已是死路徑，見 `plans/plan-issue-5.md` 對 `onZoneTapped` 的相同結論）。
- **`pageIndex`/`totalPages` 為 `foliate-js` `SectionProgress.getProgress()` 既有輸出的 `location.current`/`location.total`**（`progress.js` 第 199-203 行，`sizePerLoc = 1500`，近似 Kindle 式「位置」概念，非精確渲染頁數估算）：`location.current` 為 0-indexed，Dart `ReaderFooter` 要求 1-indexed，`ReaderScreen` 端負責 `+1` 換算。
- **`view.getCFI(index, range)`／`view.getCFIProgress(cfi)`／`book.sections[index].createDocument()` 皆為 `readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）既有公開 API**（已查證 `view.js`/`epub.js`/`progress.js` 原始碼確認存在，非臆測）：`getTableOfContents` 的實作**不修改**這些既有檔案，只在自寫的 `main.js` 呼叫它們。
- **目錄節點缺少頁內錨點時退回 section 層級定位**：`book.resolveHref(href)` 對無 hash 片段的連結回傳 `anchor = () => 0`（非 `Node`），此時**不可**呼叫 `range.selectNodeContents(0)`（會擲出 `TypeError`），改用 `view.getCFI(index, undefined)`（`view.js` 既有的 `baseCFI` 退路，`book.sections[index].cfi ?? CFI.fake.fromIndex(index)`，仍可跳轉到正確章節、只是不含頁內錨點精度）。
- **測試裝置**：沿用既有測試裝置（`3CEF42ECD491687`，Android 15/API 35）；執行前以 `adb devices -l` 重新確認裝置仍在。
- **執行環境**：所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash/MSYS2）執行，非 PowerShell／`cmd.exe`。
- **語言**：新增/修改的程式碼註解一律使用正體中文，比照本檔案既有慣例。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt` | 新增 | 純函式：`extractCfi()`（新格式定位 JSON→CFI 字串，含優雅退回）／`parseTocEntries()`（目錄 JSON 陣列→Dart wire 格式） |
| `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt` | 新增 | 上述兩個純函式的 JVM 單元測試 |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` | 修改 | `openBook` 新增 `initialLocatorJson` 參數；`onMethodCall` 新增 `jumpToLocator`／`getTableOfContents` case；`FoliateBridge` 新增 `onLocatorChanged`／`onTableOfContentsReady` |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | 新增 `window.jumpToLocator()`／`window.getTableOfContents()`／`buildTocEntry()`；持續 `relocate` 監聽器推播 `onLocatorChanged`；`openBook()` 讀取 `initialCfi` query 參數傳給 `view.init({lastLocation})` |
| `app/lib/reader/epub_position_info.dart` | 修改 | 新增 `pageIndex`/`totalPages` 兩個 nullable 欄位（加法性擴充） |
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 `initialLocatorJson`／`onLocatorChanged` 建構參數；新增 `jumpToLocator`／`loadTableOfContents` static helper |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改 | 新增上述新增介面的 widget test |
| `app/lib/screens/reader_screen.dart` | 修改 | 新增私有 `_jumpToEpubLocator()`，取代 3 處寫死呼叫 `EpubReaderView.jumpToLocator` 的呼叫點；`_handleFoliateLayoutResolved` 新增目錄背景抓取；`_buildNativeView()` Foliate 分支傳入 `initialLocatorJson`/`onLocatorChanged`；新增 `_buildFoliateEpubFooter()` |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增流式 EPUB 目錄載入/跳轉、頁尾頁碼顯示的 widget test |
| `app/integration_test/foliate_toc_footer_test.dart` | 新增 | 真機驗證：目錄跳轉 200ms 內完成且內容一致、頁尾頁碼正確反映、舊格式 `initialLocatorJson` 優雅退回不崩潰 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 6 完成說明 |

---

### Task 1: `FoliateLocatorCodec.kt`——定位/目錄 JSON 轉換純函式（TDD）

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt`

**Interfaces:**
- Consumes: 無新的外部依賴（`org.json.JSONObject`/`JSONArray` 皆為既有專案依賴）。
- Produces: `FoliateLocatorCodec.extractCfi(locatorJson: String?): String?`；`FoliateLocatorCodec.parseTocEntries(tocJson: String): List<Map<String, Any?>>`（每個 map 含 `title: String`／`locatorJson: String`／`progression: Double?`／`children: List<Map<String, Any?>>`）。Task 2 的 `FoliateEpubReaderView.kt` 依賴這兩個方法名稱與簽章。

- [x] **Step 1: 寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliateLocatorCodecTest {

    // --- extractCfi ---

    @Test
    fun `新格式 JSON 正確取出 cfi 欄位`() {
        val json = """{"cfi":"epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)","index":3,"fraction":0.042091}"""
        assertEquals(
            "epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)",
            FoliateLocatorCodec.extractCfi(json),
        )
    }

    @Test
    fun `舊格式 Readium Locator JSON 沒有 cfi 欄位，回傳 null（優雅退回）`() {
        val readiumLocatorJson = """
            {"href":"/OEBPS/chapter1.xhtml","type":"application/xhtml+xml",
             "title":"Chapter 1","locations":{"progression":0.42,"totalProgression":0.1}}
        """.trimIndent()
        assertNull(FoliateLocatorCodec.extractCfi(readiumLocatorJson))
    }

    @Test
    fun `格式錯誤的 JSON 字串回傳 null，不拋出例外`() {
        assertNull(FoliateLocatorCodec.extractCfi("not a json string"))
    }

    @Test
    fun `null 輸入回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi(null))
    }

    @Test
    fun `cfi 欄位為 null 值時回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi("""{"cfi":null,"index":0,"fraction":0}"""))
    }

    @Test
    fun `cfi 欄位為非字串型別時回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi("""{"cfi":12345,"index":0,"fraction":0}"""))
    }

    // --- parseTocEntries ---

    @Test
    fun `解析扁平（無巢狀子項目）目錄陣列`() {
        val json = """
            [{"title":"第一章","locatorJson":"{\"cfi\":\"epubcfi(/6/4)\",\"index\":0,\"fraction\":0.0}",
              "progression":0.0,"children":[]},
             {"title":"第二章","locatorJson":"{\"cfi\":\"epubcfi(/6/6)\",\"index\":1,\"fraction\":0.5}",
              "progression":0.5,"children":[]}]
        """.trimIndent()
        val entries = FoliateLocatorCodec.parseTocEntries(json)
        assertEquals(2, entries.size)
        assertEquals("第一章", entries[0]["title"])
        assertEquals(0.5, entries[1]["progression"])
    }

    @Test
    fun `解析含巢狀子項目的目錄陣列（round-trip 驗證巢狀結構保留）`() {
        val json = """
            [{"title":"第一部","locatorJson":"","progression":null,
              "children":[
                {"title":"第一章","locatorJson":"{\"cfi\":\"epubcfi(/6/4)\",\"index\":0,\"fraction\":0.0}",
                 "progression":0.0,"children":[]}
              ]}]
        """.trimIndent()
        val entries = FoliateLocatorCodec.parseTocEntries(json)
        assertEquals(1, entries.size)
        assertNull(entries[0]["progression"])
        @Suppress("UNCHECKED_CAST")
        val children = entries[0]["children"] as List<Map<String, Any?>>
        assertEquals(1, children.size)
        assertEquals("第一章", children[0]["title"])
    }

    @Test
    fun `格式錯誤的 JSON 陣列字串回傳空清單，不拋出例外`() {
        assertTrue(FoliateLocatorCodec.parseTocEntries("not a json array").isEmpty())
    }

    @Test
    fun `空陣列回傳空清單`() {
        assertTrue(FoliateLocatorCodec.parseTocEntries("[]").isEmpty())
    }
}
```

- [x] **Step 2: 執行測試確認失敗**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliateLocatorCodecTest"
```

預期：編譯失敗（`FoliateLocatorCodec` 尚不存在）。

- [x] **Step 3: 建立 `FoliateLocatorCodec.kt`**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.json.JSONArray
import org.json.JSONObject

/**
 * 解析/序列化 epic-17-epub-render-migration Issue 6 新增的定位 JSON 格式
 * （{"cfi": "epubcfi(...)", "index": N, "fraction": F}，見 spec.md「資料
 * 模型」），與原生 foliate-js/CFI 格式互轉——與 Readium Locator.toJSON()
 * 完全不同、不相容（ADR 0011「既有流式書資料視為失效」）。純函式，不觸碰
 * WebView，供 JVM 單元測試直接驗證，供 FoliateEpubReaderView.kt 使用。
 */
object FoliateLocatorCodec {
    /**
     * 從定位 JSON 字串取出 cfi 欄位。[locatorJson] 為 null、JSON 格式錯誤、
     * 或是既有流式書籍留下的舊格式 Readium Locator JSON（完全不同的欄位
     * 結構，例如 {"href": "...", "locations": {...}, "type": "..."}，沒有
     * cfi 這個鍵）皆回傳 null，供呼叫端優雅退回（不拋例外、視為無記錄）。
     */
    fun extractCfi(locatorJson: String?): String? {
        if (locatorJson == null) return null
        return try {
            val obj = JSONObject(locatorJson)
            if (obj.has("cfi") && !obj.isNull("cfi")) obj.getString("cfi") else null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 把 main.js window.getTableOfContents() 回傳的 JSON 陣列字串解析為
     * Dart TocEntry.fromWire() 預期的巢狀 map 結構（title／locatorJson／
     * progression／children）。[tocJson] 格式錯誤時回傳空清單，不拋出例外
     * ——目錄讀取失敗不應該讓已成功開啟的書籍畫面顯示錯誤（比照
     * FoliateEpubReaderView.kt 既有對非致命錯誤的處理原則）。
     */
    fun parseTocEntries(tocJson: String): List<Map<String, Any?>> {
        return try {
            val array = JSONArray(tocJson)
            (0 until array.length()).map { tocEntryFromJsonObject(array.getJSONObject(it)) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun tocEntryFromJsonObject(obj: JSONObject): Map<String, Any?> {
        val childrenArray = obj.optJSONArray("children") ?: JSONArray()
        val children = (0 until childrenArray.length())
            .map { tocEntryFromJsonObject(childrenArray.getJSONObject(it)) }
        return mapOf(
            "title" to obj.optString("title", ""),
            "locatorJson" to obj.optString("locatorJson", ""),
            "progression" to if (obj.isNull("progression")) null else obj.optDouble("progression"),
            "children" to children,
        )
    }
}
```

- [x] **Step 4: 執行測試確認通過**

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliateLocatorCodecTest"
```

預期：全數 PASS（10 個測試）。

- [x] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt
git commit -m "feat(epic-17): 新增 FoliateLocatorCodec 純函式——定位/目錄 JSON 轉換與舊格式優雅退回"
```

---

### Task 2: `FoliateEpubReaderView.kt` + `main.js`——目錄讀取與定位跳轉原生橋接

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 `FoliateLocatorCodec.extractCfi()`/`parseTocEntries()`。
- Produces: method channel 新增 `openBook` 的 `initialLocatorJson: String?` 參數／`jumpToLocator`（`locatorJson: String`）／`getTableOfContents`（request/response，回傳 `List<Map<String, Any?>>`）三個 Dart→原生介面；原生→Dart 新增 `onLocatorChanged`（`locatorJson`／`progression`／`pageIndex`／`totalPages` 四欄位）。`main.js` 新增全域函式 `window.jumpToLocator(cfi: string)`／`window.getTableOfContents(): Promise<void>`，供本 Task 的 Kotlin 端呼叫；Task 3 的 Dart widget 依賴這些 method channel 名稱與參數格式。

**本 Task 無 JVM 單元測試**（比照 Issue 2/3/4/5 既定退路）：`evaluateJavascript`/`WebView` 呼叫是框架 API 的直接串接，沒有可抽出的純邏輯（可抽出的部分已在 Task 1 完成）。驗收標準是 `compileDebugKotlin` 成功 + 既有 JVM 測試不受影響，實際行為由 Task 5 真機 `integration_test` 驗證。

- [x] **Step 1: `main.js` 新增 `window.jumpToLocator()`**

在 `app/android/app/src/main/assets/foliate/main.js` 的 `window.jumpToFraction = function (fraction) { view.goToFraction(fraction) }`（第 108-110 行）之後、`async function openBook() {`（第 112 行）之前，插入：

```js

/**
 * 跳轉到指定 CFI（epic-17 Issue 6）。[cfi] 已由原生端
 * FoliateLocatorCodec.extractCfi() 驗證過格式（新格式定位 JSON 才會呼叫
 * 到這裡，舊格式/無效 JSON 在原生端就已被過濾掉，見
 * FoliateEpubReaderView.kt「jumpToLocator」case），本函式不需要再自行
 * 解析 JSON 或判斷格式。
 */
window.jumpToLocator = function (cfi) {
  view.goTo(cfi)
}

/**
 * 遞迴解析單一目錄節點：透過 view.book.resolveHref() 取得 {index, anchor}，
 * 載入該 section 的文件（book.sections[index].createDocument()，獨立於
 * 目前實際顯示中的頁面，不影響閱讀畫面）後計算對應 CFI；href 無法解析、
 * 缺少頁內錨點（anchor(doc) 回傳非 Node 值，例如純章節起點連結）、或文件
 * 載入失敗時，退回 section 層級的 base CFI（view.getCFI(index, undefined)，
 * 不含頁內錨點精度，比照 view.js getCFI() 既有的 baseCFI 退路，仍可跳轉
 * 到正確章節，見 Global Constraints）。
 */
async function buildTocEntry(item) {
  const resolved = item.href ? view.book.resolveHref(item.href) : null
  let cfi = null
  let index = null
  let fraction = null
  if (resolved && resolved.index >= 0) {
    index = resolved.index
    try {
      const doc = await view.book.sections[index].createDocument()
      const frag = resolved.anchor(doc)
      let range
      if (frag instanceof Range) {
        range = frag
      } else if (frag && frag.nodeType) {
        range = doc.createRange()
        range.selectNodeContents(frag)
      }
      cfi = view.getCFI(index, range)
    } catch (e) {
      cfi = view.getCFI(index, undefined)
    }
    if (cfi) {
      const progress = await view.getCFIProgress(cfi)
      fraction = progress?.fraction ?? null
    }
  }
  const children = []
  for (const sub of item.subitems ?? []) {
    children.push(await buildTocEntry(sub))
  }
  return {
    title: item.label ?? '',
    locatorJson: cfi
      ? JSON.stringify({ cfi, index, fraction: fraction ?? 0 })
      : '',
    progression: fraction,
    children,
  }
}

/**
 * 讀取全書目錄（epic-17 Issue 6），供原生端 getTableOfContents method
 * channel case 呼叫。非同步計算完成後主動透過 FoliateBridge 回呼原生端
 * ——WebView.evaluateJavascript 的 callback 不會等待 async function 內部
 * 的 Promise resolve（只會拿到 Promise 物件本身序列化後的無意義結果），
 * 見 FoliateEpubReaderView.kt onTableOfContentsReady() 註解與 Global
 * Constraints，本函式因此不能單純依賴 evaluateJavascript 的回傳值。
 */
window.getTableOfContents = async function () {
  const items = view.book?.toc ?? []
  const entries = []
  for (const item of items) {
    entries.push(await buildTocEntry(item))
  }
  window.FoliateBridge.onTableOfContentsReady(JSON.stringify(entries))
}
```

- [x] **Step 2: `main.js` 新增持續 `relocate` 監聽器與 `initialCfi` 開書起始定位**

第 9-14 行（`params`/`initialPrefs`/`fontFaceCss` 常數宣告）：

```js
const params = new URLSearchParams(location.search)
const initialPrefs = JSON.parse(params.get('prefs') || '{}')
// 5 款內建字型的 @font-face 宣告（見 FoliateEpubReaderView.kt
// buildFontFaceCss()），開書當下由原生端算好透過 query string 傳入，字型
// 檔案路徑固定不隨後續 applyPreferences 呼叫變動。
const fontFaceCss = params.get('fontFaceCss') || ''
```

改為（新增 `initialCfi` 常數）：

```js
const params = new URLSearchParams(location.search)
const initialPrefs = JSON.parse(params.get('prefs') || '{}')
// 5 款內建字型的 @font-face 宣告（見 FoliateEpubReaderView.kt
// buildFontFaceCss()），開書當下由原生端算好透過 query string 傳入，字型
// 檔案路徑固定不隨後續 applyPreferences 呼叫變動。
const fontFaceCss = params.get('fontFaceCss') || ''
// 開書起始定位（epic-17 Issue 6）：原生端已透過 FoliateLocatorCodec
// .extractCfi() 驗證過格式，這裡拿到的要嘛是合法 CFI 字串，要嘛是空字串
// （缺席／舊格式／無效資料的優雅退回，見 Global Constraints），不需要
// 再自行判斷格式。
const initialCfi = params.get('initialCfi') || ''
```

`async function openBook() { ... }`（第 112-157 行）內，`view.addEventListener('relocate', () => { ... }, { once: true })`（第 142-147 行）之後、`await view.open(book)`（第 148 行）之前：

```js
    view.addEventListener('relocate', () => {
      const resolvedWritingMode =
        initialPrefs.writingMode ?? detectedBookWritingMode ?? 'horizontal'
      window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode })
      window.FoliateBridge.onPageRendered(resolvedWritingMode)
    }, { once: true })
    await view.open(book)
```

改為（插入第二個持續監聽器）：

```js
    view.addEventListener('relocate', () => {
      const resolvedWritingMode =
        initialPrefs.writingMode ?? detectedBookWritingMode ?? 'horizontal'
      window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode })
      window.FoliateBridge.onPageRendered(resolvedWritingMode)
    }, { once: true })
    // 目前定位變動持續推播（epic-17 Issue 6）：與上方 { once: true } 的
    // FR-06/onPageRendered 監聽器各自獨立、互不影響，開書當下的第一次
    // relocate 事件兩者皆會觸發。location.current／location.total 為
    // foliate-js SectionProgress.getProgress() 既有輸出（見
    // progress.js），近似頁碼概念，非精確渲染頁數。
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

最後，`await view.init({})`（第 153 行）：

```js
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init({})
```

改為：

```js
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init(initialCfi ? { lastLocation: initialCfi } : {})
```

- [x] **Step 3: `FoliateEpubReaderView.kt`——`openBook` 新增 `initialLocatorJson` 參數**

第 176-211 行的 `openBook`：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        currentBookFile = null
        currentBookUri = null
        if (path.contains("://")) {
            currentBookUri = Uri.parse(path)
        } else {
            val canonicalFile = try {
                File(path).canonicalFile
            } catch (e: Exception) {
                channel.invokeMethod("onError", "無法解析檔案路徑：$path")
                return
            }
            // 允許範圍：App 私有資料目錄（含 files, cache, app_flutter 等）。
            // context.filesDir.parentFile 通常即為 /data/user/0/pkg/。
            val allowedRoot = context.filesDir.parentFile?.canonicalPath ?: context.filesDir.canonicalPath
            if (!FoliatePathValidator.isPathWithinRoot(canonicalFile.canonicalPath, allowedRoot)) {
                channel.invokeMethod("onError", "檔案路徑不在允許的目錄範圍內：$path")
                return
            }
            currentBookFile = canonicalFile
        }
        currentPreferences.clear()
        initialPreferences?.let { currentPreferences.putAll(it) }
        fontFaceCss = buildFontFaceCss()
        val prefsJson = Uri.encode(JSONObject(currentPreferences).toString())
        val fontFaceCssEncoded = Uri.encode(fontFaceCss)
        webView.loadUrl(
            "https://appassets.androidplatform.net/assets/foliate/index.html" +
                "?prefs=$prefsJson&fontFaceCss=$fontFaceCssEncoded",
        )
    }
```

改為：

```kotlin
    private fun openBook(
        path: String?,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
    ) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        currentBookFile = null
        currentBookUri = null
        if (path.contains("://")) {
            currentBookUri = Uri.parse(path)
        } else {
            val canonicalFile = try {
                File(path).canonicalFile
            } catch (e: Exception) {
                channel.invokeMethod("onError", "無法解析檔案路徑：$path")
                return
            }
            // 允許範圍：App 私有資料目錄（含 files, cache, app_flutter 等）。
            // context.filesDir.parentFile 通常即為 /data/user/0/pkg/。
            val allowedRoot = context.filesDir.parentFile?.canonicalPath ?: context.filesDir.canonicalPath
            if (!FoliatePathValidator.isPathWithinRoot(canonicalFile.canonicalPath, allowedRoot)) {
                channel.invokeMethod("onError", "檔案路徑不在允許的目錄範圍內：$path")
                return
            }
            currentBookFile = canonicalFile
        }
        currentPreferences.clear()
        initialPreferences?.let { currentPreferences.putAll(it) }
        fontFaceCss = buildFontFaceCss()
        val prefsJson = Uri.encode(JSONObject(currentPreferences).toString())
        val fontFaceCssEncoded = Uri.encode(fontFaceCss)
        // 優雅退回（epic-17 Issue 6）：extractCfi() 對缺席／舊格式（既有
        // 流式書籍留下的 Readium Locator JSON）／無效 JSON 皆回傳
        // null，此時不附加 initialCfi 查詢參數，main.js 端 params.get()
        // 拿到 null，退回既有預設開書行為（見 Global Constraints）。
        val initialCfi = FoliateLocatorCodec.extractCfi(initialLocatorJson)
        val initialCfiParam = initialCfi?.let { "&initialCfi=${Uri.encode(it)}" } ?: ""
        webView.loadUrl(
            "https://appassets.androidplatform.net/assets/foliate/index.html" +
                "?prefs=$prefsJson&fontFaceCss=$fontFaceCssEncoded$initialCfiParam",
        )
    }
```

- [x] **Step 4: `FoliateEpubReaderView.kt`——`onMethodCall` 新增 case，新增 `pendingTocResult` 欄位**

第 84-85 行（`pageReported`/`isDisposed` 欄位）：

```kotlin
    private var pageReported = false
    private var isDisposed = false
```

改為（新增 `pendingTocResult`）：

```kotlin
    private var pageReported = false
    private var isDisposed = false

    /** getTableOfContents 的待完成 Result（epic-17 Issue 6）：JS 端的
     * window.getTableOfContents() 是非同步函式，evaluateJavascript 的
     * callback 不會等待其內部 Promise resolve（見 Global Constraints），
     * 因此改由 JS 完成計算後主動呼叫 FoliateBridge.onTableOfContentsReady()
     * 回報，此處暫存對應的 Result 供該回呼完成時呼叫 result.success()。
     * 單一書籍畫面同時只會有一次未完成的目錄請求（ReaderScreen 只在
     * onLayoutResolved 觸發時呼叫一次，見 spec.md），不需要佇列/多筆並行
     * 處理。 */
    private var pendingTocResult: MethodChannel.Result? = null
```

第 126-162 行的 `onMethodCall`：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 3×3 導航熱區完全由 Dart 端 Stack 疊加層判讀（見
                // foliate_epub_reader_view.dart，epic-17-epub-render-migration
                // Issue 5「不在原生端判讀」），本 case 純粹是換頁指令的轉發，
                // 不做任何座標/熱區判斷。
                webView.evaluateJavascript("window.nextPage()", null)
                result.success(null)
            }
            "previousPage" -> {
                webView.evaluateJavascript("window.previousPage()", null)
                result.success(null)
            }
            "jumpToProgression" -> {
                val progression = call.argument<Double>("progression")
                if (progression != null) {
                    webView.evaluateJavascript("window.jumpToFraction($progression)", null)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

改為：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                    call.argument<String>("initialLocatorJson"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 3×3 導航熱區完全由 Dart 端 Stack 疊加層判讀（見
                // foliate_epub_reader_view.dart，epic-17-epub-render-migration
                // Issue 5「不在原生端判讀」），本 case 純粹是換頁指令的轉發，
                // 不做任何座標/熱區判斷。
                webView.evaluateJavascript("window.nextPage()", null)
                result.success(null)
            }
            "previousPage" -> {
                webView.evaluateJavascript("window.previousPage()", null)
                result.success(null)
            }
            "jumpToProgression" -> {
                val progression = call.argument<Double>("progression")
                if (progression != null) {
                    webView.evaluateJavascript("window.jumpToFraction($progression)", null)
                }
                result.success(null)
            }
            "jumpToLocator" -> {
                val locatorJson = call.argument<String>("locatorJson")
                val cfi = FoliateLocatorCodec.extractCfi(locatorJson)
                if (cfi != null) {
                    webView.evaluateJavascript(
                        "window.jumpToLocator(${JSONObject.quote(cfi)})",
                        null,
                    )
                }
                // 優雅退回：cfi 為 null（舊格式/無效資料）時不執行任何跳轉，
                // 靜默忽略（見 Global Constraints），仍需 result.success()
                // 讓 Dart 端的 invokeMethod 呼叫正常完成。
                result.success(null)
            }
            "getTableOfContents" -> {
                pendingTocResult = result
                webView.evaluateJavascript("window.getTableOfContents()", null)
            }
            else -> result.notImplemented()
        }
    }
```

- [x] **Step 5: `FoliateEpubReaderView.kt`——`FoliateBridge` 新增 `onLocatorChanged`／`onTableOfContentsReady`**

第 289-319 行的 `FoliateBridge` 類別：

```kotlin
    private inner class FoliateBridge {
        /**
         * [writingMode] 為 main.js 判斷出的最終生效方向（"vertical"／
         * "horizontal"）——書本自己宣告的值優先，否則預設橫排，見
         * assets/foliate/main.js 的 FR-06 偵測邏輯（epic-17-epub-render-migration
         * Issue 4）。
         */
        @JavascriptInterface
        fun onPageRendered(writingMode: String) {
            mainHandler.post {
                if (isDisposed || pageReported) return@post
                pageReported = true
                channel.invokeMethod("onPageRendered", null)
                channel.invokeMethod(
                    "onLayoutResolved",
                    mapOf(
                        "isFixedLayout" to false,
                        "writingMode" to writingMode,
                    ),
                )
            }
        }

        @JavascriptInterface
        fun onError(message: String) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onError", message)
            }
        }
    }
```

改為（新增兩個方法）：

```kotlin
    private inner class FoliateBridge {
        /**
         * [writingMode] 為 main.js 判斷出的最終生效方向（"vertical"／
         * "horizontal"）——書本自己宣告的值優先，否則預設橫排，見
         * assets/foliate/main.js 的 FR-06 偵測邏輯（epic-17-epub-render-migration
         * Issue 4）。
         */
        @JavascriptInterface
        fun onPageRendered(writingMode: String) {
            mainHandler.post {
                if (isDisposed || pageReported) return@post
                pageReported = true
                channel.invokeMethod("onPageRendered", null)
                channel.invokeMethod(
                    "onLayoutResolved",
                    mapOf(
                        "isFixedLayout" to false,
                        "writingMode" to writingMode,
                    ),
                )
            }
        }

        @JavascriptInterface
        fun onError(message: String) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onError", message)
            }
        }

        /**
         * relocate 事件持續推播（main.js 的第二個、非 { once: true } 的
         * relocate 監聽器），epic-17 Issue 6。[locatorJson] 為新 CFI 格式
         * 序列化字串（{"cfi":...,"index":...,"fraction":...}）；[fraction]
         * 為全書進度比例（0.0-1.0），與 locatorJson 內嵌的 fraction 欄位
         * 相同數值，額外拆出一份供 Dart 端直接使用（比照既有
         * EpubReaderView progression 欄位的既定慣例，不需要自行解析
         * locatorJson）；[pageIndex]／[totalPages] 為 foliate-js
         * SectionProgress.getProgress() 回傳的 location.current／
         * location.total（近似頁碼概念，非精確渲染頁數，見 Global
         * Constraints）。
         */
        @JavascriptInterface
        fun onLocatorChanged(locatorJson: String, fraction: Double, pageIndex: Int, totalPages: Int) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod(
                    "onLocatorChanged",
                    mapOf(
                        "locatorJson" to locatorJson,
                        "progression" to fraction,
                        "pageIndex" to pageIndex,
                        "totalPages" to totalPages,
                    ),
                )
            }
        }

        /**
         * window.getTableOfContents() 計算完成回呼，[json] 為目錄節點陣列
         * 的 JSON 序列化字串（見 main.js buildTocEntry()）。解析失敗時
         * FoliateLocatorCodec.parseTocEntries() 回傳空清單，不讓 Dart 端
         * 的 Future 永遠不 resolve。
         */
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

- [x] **Step 6: `dispose()` 新增 `pendingTocResult` 清理**

目錄讀取尚未完成（`onTableOfContentsReady` 尚未觸發）時 Widget 若被銷毀，既有的 `isDisposed` 檢查會擋掉 `onTableOfContentsReady` 內的 `result.success()` 呼叫，不會崩潰，但 `pendingTocResult` 欄位會殘留對 `MethodChannel.Result`（間接持有 reply channel 參照）的參照，直到 `FoliateEpubReaderView` 實例本身被回收為止。比照本檔案 `openBook()` 重新開書時明確清空 `currentBookFile`/`currentBookUri` 的既有防禦風格，`dispose()` 一併明確清空，讓該參照提早可被回收（審查修正）。

第 321-325 行的 `dispose()`：

```kotlin
    override fun dispose() {
        isDisposed = true
        ReaderViewAttachmentTracker.detach()
        webView.destroy()
    }
```

改為：

```kotlin
    override fun dispose() {
        isDisposed = true
        pendingTocResult = null
        ReaderViewAttachmentTracker.detach()
        webView.destroy()
    }
```

- [x] **Step 7: 確認 Kotlin 編譯成功**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`。

- [x] **Step 8: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-17): FoliateEpubReaderView.kt/main.js 新增目錄讀取與定位跳轉橋接"
```

---

### Task 3: `foliate_epub_reader_view.dart` + `EpubPositionInfo`——Dart 介面擴充

**Files:**
- Modify: `app/lib/reader/epub_position_info.dart`
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 2 新增的 `initialLocatorJson`／`jumpToLocator`／`getTableOfContents`／`onLocatorChanged` method channel 契約。
- Produces: `EpubPositionInfo` 新增 `pageIndex: int?`／`totalPages: int?` 欄位；`FoliateEpubReaderView` 新增建構參數 `initialLocatorJson: String?`／`onLocatorChanged: ValueChanged<EpubPositionInfo>?`；新增 static helper `FoliateEpubReaderView.jumpToLocator(key, locatorJson)`／`FoliateEpubReaderView.loadTableOfContents(key): Future<List<TocEntry>>`。供 Task 4 的 `ReaderScreen` 使用。

- [x] **Step 1: 寫失敗測試**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/toc_entry.dart';
```

在 `main()` 內、最後一個 `testWidgets` 區塊之後，新增：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialLocatorJson 非 null 時正確帶入',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        initialLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      openBookCall.arguments['initialLocatorJson'],
      '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
    );
  });

  testWidgets('initialLocatorJson 為 null 時，openBook 的 arguments 不包含該 key',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments as Map<Object?, Object?>)
          .containsKey('initialLocatorJson'),
      isFalse,
    );
  });

  testWidgets('收到原生端 onLocatorChanged 事件時正確解析 EpubPositionInfo（含 pageIndex/totalPages）',
      (tester) async {
    EpubPositionInfo? received;
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
        onLocatorChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onLocatorChanged', {
      'locatorJson': '{"cfi":"epubcfi(/6/8)","index":2,"fraction":0.3}',
      'progression': 0.3,
      'pageIndex': 9,
      'totalPages': 100,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received?.locatorJson, '{"cfi":"epubcfi(/6/8)","index":2,"fraction":0.3}');
    expect(received?.progression, 0.3);
    expect(received?.pageIndex, 9);
    expect(received?.totalPages, 100);
  });

  testWidgets(
      'FoliateEpubReaderView.jumpToLocator()（強型別 static helper）呼叫原生端 jumpToLocator',
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

    FoliateEpubReaderView.jumpToLocator(
      key,
      '{"cfi":"epubcfi(/6/10)","index":4,"fraction":0.6}',
    );
    await tester.pump();

    final call = calls.firstWhere((c) => c.method == 'jumpToLocator');
    expect(call.arguments, {
      'locatorJson': '{"cfi":"epubcfi(/6/10)","index":4,"fraction":0.6}',
    });
  });

  testWidgets(
      'FoliateEpubReaderView.loadTableOfContents()：State 未掛載時回傳空清單',
      (tester) async {
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final entries = await FoliateEpubReaderView.loadTableOfContents(key);
    expect(entries, isEmpty);
  });
```

- [x] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：新測試 FAIL（`initialLocatorJson`/`onLocatorChanged` 建構參數不存在、`jumpToLocator`/`loadTableOfContents` static method 不存在）。

- [x] **Step 3: `epub_position_info.dart` 新增 `pageIndex`/`totalPages` 欄位**

`app/lib/reader/epub_position_info.dart` 現有完整內容：

```dart
/// [EpubReaderView] 目前定位變動時（開書完成、翻頁、跳轉）一次性回報的
/// 位置資訊（epic-5-toc-pagination Issue 2）。[locatorJson] 是原生端
/// `Locator.toJSON().toString()` 的原樣字串，Dart 端不解析其內部結構、
/// 只負責持久化與之後原樣傳回原生端還原（`Locator.fromJSON`）；
/// [progression] 是原生端額外拆出的 `Locator.locations.totalProgression`
/// 平面數值，供 Dart 端直接用於 `Book.progress` 而不需要自行解析
/// [locatorJson] 的巢狀 JSON 結構。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(locatorJson, progression);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression)';
}
```

改為（整檔覆寫）：

```dart
/// [EpubReaderView]／[FoliateEpubReaderView] 目前定位變動時（開書完成、
/// 翻頁、跳轉）一次性回報的位置資訊（epic-5-toc-pagination Issue 2）。
/// [locatorJson] 對 [EpubReaderView] 是原生端 `Locator.toJSON().toString()`
/// 的原樣字串；對 [FoliateEpubReaderView] 是 epic-17-epub-render-migration
/// Issue 6 新增的 CFI 格式 JSON 字串（`{"cfi":...,"index":...,"fraction":...}`，
/// 見 spec.md「資料模型」）——兩種格式完全不相容，但 Dart 端不解析其內部
/// 結構、只負責持久化與之後原樣傳回原生端還原，型別簽章不需要區分兩者。
/// [progression] 是原生端額外拆出的全書進度比例平面數值，供 Dart 端直接
/// 用於 `Book.progress` 而不需要自行解析 [locatorJson] 的巢狀 JSON 結構。
///
/// [pageIndex]／[totalPages]（epic-17-epub-render-migration Issue 6，加法性
/// 擴充）僅 [FoliateEpubReaderView] 會回報非 null 值——`foliate-js`
/// `SectionProgress.getProgress()` 的 `location.current`／`location.total`
/// （近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼估算」），供
/// `ReaderScreen` 建構頁尾時直接使用，不需要另外估算。[EpubReaderView]
/// （Readium）永遠不填這兩個欄位，維持既有行為不受影響。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;
  final int? pageIndex;
  final int? totalPages;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
    this.pageIndex,
    this.totalPages,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.pageIndex == pageIndex &&
      other.totalPages == totalPages;

  @override
  int get hashCode =>
      Object.hash(locatorJson, progression, pageIndex, totalPages);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression, '
      'pageIndex: $pageIndex, totalPages: $totalPages)';
}
```

- [x] **Step 4: `foliate_epub_reader_view.dart` 新增 import 與建構參數**

第 1-8 行：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';
import 'zone_action.dart';
```

改為：

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

`showNavZoneDebugOverlay` 欄位（第 56 行）之後、`const FoliateEpubReaderView({`（第 58 行）之前：

```dart
  final bool showNavZoneDebugOverlay;

  const FoliateEpubReaderView({
```

改為：

```dart
  final bool showNavZoneDebugOverlay;

  /// 開書起始定位（epic-17-epub-render-migration Issue 6）。`null` 代表
  /// 無既有位置記錄，或原生端 `FoliateLocatorCodec.extractCfi()` 判斷為
  /// 舊格式/無效資料而優雅退回，一律從書本開頭開始（見 Global
  /// Constraints）。與其餘偏好參數不同，這是「一次性開書起始值」，只在
  /// `openBook` 當下送出一次，不參與 [didUpdateWidget] 的偏好設定 diff
  /// 邏輯，比照 [EpubReaderView.initialLocatorJson] 既有模式。
  final String? initialLocatorJson;

  /// 目前定位變動時觸發（開書、翻頁、目錄跳轉），供呼叫端（ReaderScreen）
  /// 快取最新定位，於離開/背景時寫入資料庫，比照
  /// [EpubReaderView.onLocatorChanged] 既有模式。
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;

  const FoliateEpubReaderView({
```

建構子參數列（`this.showNavZoneDebugOverlay = false,` 之後）：

```dart
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
  });
```

改為：

```dart
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.initialLocatorJson,
    this.onLocatorChanged,
  });
```

- [x] **Step 5: `_onPlatformViewCreated` 傳入 `initialLocatorJson`，新增 static helper**

第 122-131 行：

```dart
  void _onPlatformViewCreated(int id) {
    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }
```

改為：

```dart
  void _onPlatformViewCreated(int id) {
    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
      if (widget.initialLocatorJson != null)
        'initialLocatorJson': widget.initialLocatorJson,
    });
  }
```

在 `jumpToProgression` static helper（第 102-113 行）之後、`@override\n  State<FoliateEpubReaderView> createState()`（第 115 行）之前：

```dart
  /// 跳轉到指定全書進度比例（0.0-1.0），原生端呼叫 view.goToFraction()。
  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('jumpToProgression', {
        'progression': progression,
      });
    }
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
```

改為（新增兩個 static helper）：

```dart
  /// 跳轉到指定全書進度比例（0.0-1.0），原生端呼叫 view.goToFraction()。
  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('jumpToProgression', {
        'progression': progression,
      });
    }
  }

  /// 依目錄項目／書籤／備註的序列化定位跳轉（epic-17-epub-render-migration
  /// Issue 6），比照 [jumpToProgression] 的強型別 static helper 模式，不
  /// 使用 `as dynamic` 跨越 State 的 private 邊界。[locatorJson] 為本 Epic
  /// 新增的 CFI 格式 JSON 字串；若為舊格式/無效資料，原生端
  /// `FoliateLocatorCodec.extractCfi()` 會優雅退回、不執行任何跳轉（見
  /// Global Constraints），呼叫端不需要事先驗證格式。
  static void jumpToLocator(
    GlobalKey<State<FoliateEpubReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('jumpToLocator', {
        'locatorJson': locatorJson,
      });
    }
  }

  /// 讀取全書目錄樹狀結構（epic-17-epub-render-migration Issue 6），比照
  /// [EpubReaderView.loadTableOfContents] 既有模式：請求/回應語意（回傳
  /// `Future`），非 fire-and-forget。原生端呼叫失敗或本 State 尚未掛載
  /// （例如純 `flutter_test` 環境下 `_channel` 恆為 `null`，AndroidView
  /// 未真正建立）時回傳空清單，不拋出例外。
  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<FoliateEpubReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateEpubReaderViewState) return const [];
    final raw = await state._channel
        ?.invokeMethod<List<Object?>>('getTableOfContents');
    if (raw == null) return const [];
    return raw
        .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
        .toList();
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
```

- [x] **Step 6: `_handleMethodCall` 新增 `onLocatorChanged` case**

第 185-204 行：

```dart
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        widget.onLayoutResolved?.call(info);
        break;
    }
  }
```

改為：

```dart
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        widget.onLayoutResolved?.call(info);
        break;
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
  }
```

- [x] **Step 7: 更新檔案頂端 Widget 說明文件**

第 9-26 行的檔案頂端說明：

```dart
/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Widget（epic-17-epub-render-migration Issue 4/5）新增 9 項版面偏好
/// 建構參數，與既有 [EpubReaderView] 對稱參數同名同型別（不含 `dualPageMode`／
/// `isLandscape`——reflowable 流式書籍不適用「雙頁」）。Issue 5 新增
/// `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數
/// 與 `nextPage`/`previousPage`/`jumpToProgression` static helper，3×3
/// 導航熱區完全由 Dart 端 Stack 疊加層處理、不送給原生端。
/// [writingMode] 是「呼叫端要求套用的方向」（可寫），與 [onLayoutResolved]
/// 回報的 [EpubLayoutInfo.writingMode]（原生端判斷/回報的唯讀值）是兩個
/// 不同方向的資料流，比照 [EpubReaderView] 既有模式。
///
/// 排版設定以外的目錄／劃線備註參數留待 Issue 6-8 補上。
```

改為：

```dart
/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Widget（epic-17-epub-render-migration Issue 4/5）新增 9 項版面偏好
/// 建構參數，與既有 [EpubReaderView] 對稱參數同名同型別（不含 `dualPageMode`／
/// `isLandscape`——reflowable 流式書籍不適用「雙頁」）。Issue 5 新增
/// `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數
/// 與 `nextPage`/`previousPage`/`jumpToProgression` static helper，3×3
/// 導航熱區完全由 Dart 端 Stack 疊加層處理、不送給原生端。Issue 6 新增
/// `initialLocatorJson`/`onLocatorChanged` 建構參數與
/// `jumpToLocator`/`loadTableOfContents` static helper——定位格式為
/// 本 Epic 新增的 CFI JSON（`epub_position_info.dart`「資料模型」），與
/// [EpubReaderView] 使用的 Readium Locator JSON 完全不相容，但公開介面
/// 形狀（`String` 定位欄位）保持對稱，呼叫端不需要因為換了引擎而改變
/// 使用方式。**不**新增 `totalCharacterCount`/`onCharacterCountReady`
/// ——本 widget 完全不呼叫任何字數統計，頁尾頁碼改由 `onLocatorChanged`
/// 新增的 `pageIndex`/`totalPages` 欄位直接驅動（見
/// docs/epics/epic-17-epub-render-migration/spec.md「頁碼估算」）。
/// [writingMode] 是「呼叫端要求套用的方向」（可寫），與 [onLayoutResolved]
/// 回報的 [EpubLayoutInfo.writingMode]（原生端判斷/回報的唯讀值）是兩個
/// 不同方向的資料流，比照 [EpubReaderView] 既有模式。
///
/// 劃線備註參數留待 Issue 8 補上。
```

- [x] **Step 8: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：全數 PASS。

- [x] **Step 9: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 10: Commit**

```bash
git add app/lib/reader/epub_position_info.dart app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): FoliateEpubReaderView 新增目錄讀取與定位跳轉 Dart 介面"
```

---

### Task 4: `ReaderScreen`——接上流式 EPUB 的目錄跳轉、定位持久化與頁碼顯示

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 新增的 `FoliateEpubReaderView.initialLocatorJson`/`onLocatorChanged`/`jumpToLocator`/`loadTableOfContents`；既有 `_dispatchedIsFixedLayout`（Issue 3 已建立）；既有 `ReaderFooter`（格式無關，`currentPage`/`totalPages`/`onPageChanged` 三個 1-indexed 參數）。
- Produces: 流式 EPUB 開書後，目錄背景抓取／目錄跳轉／書籤跳轉／備註跳轉／頁尾頁碼皆正確生效，供 Task 5 真機驗證。

- [x] **Step 1: 寫失敗測試——流式 EPUB 目錄載入與跳轉分派**

在 `app/test/screens/reader_screen_test.dart` 的 `main()` 內、既有「EPUB reflowable 收到 onLayoutResolved 後，目錄按鈕轉為可點擊」與「點選目錄項目後，TocBottomSheet 關閉」兩個測試（第 1266-1347 行）之後，新增：

```dart
  testWidgets(
      '流式 EPUB（isFixedLayout: false）收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_foliate_open',
          prefsManager: prefsManager,
          isFixedLayout: false,
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
    // 比照既有 Readium 分支測試：目錄按鈕的啟用條件額外要求 _tocLoaded，
    // 該旗標由 FoliateEpubReaderView.loadTableOfContents() 這個 async
    // 呼叫的 .then() callback 設定，需要多一次 pump 讓其 microtask 完成。
    await tester.pump();

    final finder = find.byKey(const Key('reader_toc_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
  });

  testWidgets(
      '流式 EPUB：點選目錄項目呼叫 FoliateEpubReaderView.jumpToLocator（非 EpubReaderView）',
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

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_foliate_jump',
          prefsManager: prefsManager,
          isFixedLayout: false,
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

    await tester.tap(find.byKey(const Key('reader_toc_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    sheet.onEntrySelected(
      const TocEntry(
        title: '測試章節',
        locatorJson: '{"cfi":"epubcfi(/6/8!/4)","index":1,"fraction":0.2}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    expect(
      instanceCalls.any((c) =>
          c.method == 'jumpToLocator' &&
          (c.arguments as Map)['locatorJson'] ==
              '{"cfi":"epubcfi(/6/8!/4)","index":1,"fraction":0.2}'),
      isTrue,
      reason: '流式 EPUB 應呼叫 FoliateEpubReaderView.jumpToLocator，'
          '不應誤呼叫 EpubReaderView（該 widget 在此分派下根本未被建構）',
    );
  });

  testWidgets(
      '流式 EPUB：onLocatorChanged 回報 pageIndex/totalPages 後，頁尾顯示對應頁碼',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(const EpubPositionInfo(
      locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
      pageIndex: 9,
      totalPages: 100,
    ));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 10% ｜ 第 10/100 頁'), findsOneWidget);
  });

  testWidgets(
      '流式 EPUB：onLocatorChanged 未觸發前（pageIndex/totalPages 皆為 null），頁尾不顯示',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate_absent',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onPageRendered();
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });
```

在 `main()` 頂部 import 區塊確認已有 `package:elinkbook/reader/epub_position_info.dart`（既有匯入，Task 4 沿用不需新增）。

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：新測試 FAIL——目錄按鈕不會轉為可點擊（`_handleFoliateLayoutResolved` 尚未觸發目錄抓取）；`onLocatorChanged` 尚不存在於 `FoliateEpubReaderView`（本 Task 依賴 Task 3，需先完成 Task 3 才會是「執行期」失敗而非「編譯期」失敗，此為預期的 TDD 紅燈狀態）。

- [x] **Step 3: 新增 `_jumpToEpubLocator()` helper，取代 3 處寫死呼叫**

第 604-624 行的 `_openToc()`：

```dart
  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocBottomSheet(
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          EpubReaderView.jumpToLocator(_epubReaderViewKey, entry.locatorJson);
        },
      ),
    );
  }
```

改為（新增 `_jumpToEpubLocator()`，`_openToc()` 改用它）：

```dart
  /// 依 `_dispatchedIsFixedLayout` 分派到正確的原生 widget 執行目錄／
  /// 書籤／備註跳轉（epic-17-epub-render-migration Issue 6）：FXL
  /// （Readium）用 `EpubReaderView.jumpToLocator`，流式（foliate-js）用
  /// `FoliateEpubReaderView.jumpToLocator`，兩者接受的 `locatorJson`
  /// 格式不同（Readium Locator JSON vs 本 Epic 新 CFI 格式），但呼叫端
  /// （本方法的三個呼叫點：`_openToc`／`_openNotesSheet` 的
  /// `onAnnotationSelected`／`onBookmarkSelected`）不需要關心格式差異，
  /// 只需傳入目前使用中書籍的 `locatorJson`。比照 `_handleZoneAction`
  /// （Issue 5）建立的相同分派模式。
  void _jumpToEpubLocator(String locatorJson) {
    if (_dispatchedIsFixedLayout == true) {
      EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
    } else {
      FoliateEpubReaderView.jumpToLocator(_foliateEpubReaderViewKey, locatorJson);
    }
  }

  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocBottomSheet(
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator(entry.locatorJson);
        },
      ),
    );
  }
```

第 664-686 行的 `_openNotesSheet()` 內兩個跳轉呼叫點：

```dart
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
```

改為：

```dart
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            _jumpToEpubLocator(locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            _jumpToEpubLocator(bookmark.epubLocatorJson!);
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
```

- [x] **Step 4: `_handleFoliateLayoutResolved` 新增目錄背景抓取**

第 785-808 行：

```dart
  /// FoliateEpubReaderView（流式）專屬的 onLayoutResolved 處理。
  /// epic-17-epub-render-migration Issue 4 起，也設定
  /// `_autoDetectedWritingMode` 並重新計算 `_resolved`（比照
  /// `_handleLayoutResolved` 對應段落），讓「版面設定」按鈕能對流式書籍
  /// 生效。**仍然刻意不**觸發 `EpubReaderView.loadTableOfContents`／
  /// `_reloadAnnotationsAndRefreshDecorations`／`_loadFxlBookmarks`——這些
  /// 呼叫對尚未掛載的 EpubReaderView/`_epubReaderViewKey` 雖然會靜默
  /// no-op、技術上無害，但會讓 `_tocLoaded`/`_annotationsLoaded` 被誤判為
  /// 「已完成」，使「目錄」/「筆記」按鈕看似可用卻永遠開出空清單/無法
  /// 互動。目錄／劃線備註／書籤仍是 Issue 6/8 的範圍。
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

- [x] **Step 5: `_buildNativeView()` Foliate 分支傳入 `initialLocatorJson`/`onLocatorChanged`**

第 1508-1527 行：

```dart
      case BookFormat.epub:
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
          );
        }
        return EpubReaderView(
```

改為：

```dart
      case BookFormat.epub:
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
        return EpubReaderView(
```

- [x] **Step 6: 新增 `_buildFoliateEpubFooter()` 與對應的頁尾條件式區塊**

第 1460-1466 行（`_buildBody` 內的 EPUB 頁尾條件式）：

```dart
            if (format == BookFormat.epub &&
                !_isFixedLayout &&
                _totalCharacterCount != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildEpubFooter(_resolved!, _totalCharacterCount!),
          ],
        ),
      ),
    );
  }
```

改為（新增流式 EPUB 專屬條件式區塊）：

```dart
            if (format == BookFormat.epub &&
                !_isFixedLayout &&
                _totalCharacterCount != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildEpubFooter(_resolved!, _totalCharacterCount!),
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _epubPositionInfo?.totalPages != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildFoliateEpubFooter(_epubPositionInfo!),
          ],
        ),
      ),
    );
  }
```

在 `_buildEpubFooter()` 方法（第 1477-1503 行）之後、`Widget _buildNativeView(...)`（第 1505 行）之前，新增：

```dart

  /// 流式 EPUB（FoliateEpubReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）——與 _buildEpubFooter（Readium 遺留路徑，依全書字元數估算
  /// 頁數，post-epic-17 對流式書籍已是死路徑，見 plans/plan-issue-5.md
  /// 對 onZoneTapped 的相同結論）刻意不同，不重用其估算邏輯；本 widget
  /// 完全不呼叫任何字數統計（不送出 totalCharacterCount）。pageIndex 為
  /// 0-indexed（比照原生端既有慣例），ReaderFooter 要求 1-indexed，此處
  /// +1 換算。onPageChanged 透過既有 jumpToProgression（Issue 5）換算
  /// 目標頁對應的全書進度比例，與 _buildEpubFooter 的 onPageChanged 作法
  /// 相同（近似值，非精確反解頁碼）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page1Indexed) {
        final progression =
            totalPages > 0 ? (page1Indexed - 1) / totalPages : 0.0;
        FoliateEpubReaderView.jumpToProgression(
            _foliateEpubReaderViewKey, progression);
      },
    );
  }
```

- [x] **Step 7: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數 PASS，特別留意既有「EPUB 流式：原生端 onZoneTapped 回呼」「PDF：...」等既有大量測試不受 `_jumpToEpubLocator`/`_buildFoliateEpubFooter` 新增影響（`EpubReaderView` 分支的行為與呼叫方式完全不變，只是把直接呼叫改為透過 `_jumpToEpubLocator` 這一層薄轉發）。

- [x] **Step 8: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 9: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-17): ReaderScreen 接上流式 EPUB 的目錄跳轉、定位持久化與頁尾頁碼"
```

---

### Task 5: 真機整合測試——目錄跳轉、頁尾頁碼、舊格式優雅退回

**Files:**
- Create: `app/integration_test/foliate_toc_footer_test.dart`

**Interfaces:**
- Consumes: Task 1-4 的完整實作；既有測試素材 `test/fixtures/sample_multi_chapter.epub`（已在 `pubspec.yaml` 宣告為 asset，多章節結構適合驗證目錄跳轉）。
- Produces: 真機驗證證據，供 Task 6 全面驗證引用。

**本 Task 無法寫「失敗測試先行」的 TDD 循環**（比照本 Epic Issue 3-5 既有慣例）：`integration_test` 需要真實裝置渲染 `WebView`，Task 1-4 完成前這個測試必然全數失敗。本 Task 直接撰寫最終版本，於裝置上執行驗證。

- [x] **Step 1: 新增真機整合測試檔案**

建立 `app/integration_test/foliate_toc_footer_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/toc_entry.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('讀取全書目錄，點擊項目 200ms 內跳轉且畫面內容與章節一致',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_toc.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) => lastPosition = info,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final positionAfterOpen = lastPosition;
    expect(positionAfterOpen, isNotNull,
        reason: '開書後應已收到至少一次 onLocatorChanged');

    final toc = await FoliateEpubReaderView.loadTableOfContents(key);
    expect(toc, isNotEmpty, reason: 'sample_multi_chapter.epub 應含目錄項目');

    // 挑選一個與目前位置（第一章開頭）不同的目錄項目跳轉，驗證跳轉真的
    // 生效——若挑到與開書起始位置相同的項目，locatorJson 不會變動，
    // 無法區分「跳轉沒生效」與「跳轉到同一個位置」。
    final target = toc.firstWhere(
      (entry) => entry.locatorJson != positionAfterOpen?.locatorJson &&
          entry.locatorJson.isNotEmpty,
      orElse: () => toc.last,
    );

    final stopwatch = Stopwatch()..start();
    FoliateEpubReaderView.jumpToLocator(key, target.locatorJson);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    stopwatch.stop();

    expect(errorMessage, isNull, reason: '目錄跳轉後不應觸發 onError');
    expect(stopwatch.elapsedMilliseconds, lessThan(200),
        reason: 'FR-08：目錄跳轉須於 200ms 內完成（本斷言量測 Dart 端呼叫'
            '到下一輪 pumpAndSettle 收斂為止，實際原生端渲染時間應更短，'
            '若此斷言不穩定，改依人工碼表量測記錄於 issues.md）');
    expect(
      lastPosition?.locatorJson,
      isNot(equals(positionAfterOpen?.locatorJson)),
      reason: '跳轉後 locatorJson 應變動為目錄項目對應的位置',
    );
  });

  testWidgets('頁尾頁碼正確反映 pageIndex/totalPages，且隨翻頁更新',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_footer.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) => lastPosition = info,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull);

    final positionAfterOpen = lastPosition;
    expect(positionAfterOpen?.totalPages, isNotNull,
        reason: '開書後應已收到 totalPages，供頁尾顯示使用');
    expect(positionAfterOpen!.totalPages, greaterThan(0));

    FoliateEpubReaderView.nextPage(key);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(errorMessage, isNull, reason: '換頁後不應觸發 onError');
    expect(lastPosition?.totalPages, positionAfterOpen.totalPages,
        reason: '同一本書換頁不應改變 totalPages');
  });

  testWidgets('舊格式（Readium Locator JSON）initialLocatorJson 優雅退回：不崩潰、從書本開頭開始',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_legacy_locator.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    EpubPositionInfo? firstPosition;

    // 模擬既有流式書籍（epic-17 上線前）留下的 Readium Locator JSON——
    // 完全不同的欄位結構，沒有 cfi 這個鍵。
    const legacyLocatorJson =
        '{"href":"/OEBPS/chapter3.xhtml","type":"application/xhtml+xml",'
        '"locations":{"progression":0.6,"totalProgression":0.6}}';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          initialLocatorJson: legacyLocatorJson,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) {
            firstPosition ??= info;
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '舊格式 initialLocatorJson 不應導致 onError 或崩潰');
    expect(firstPosition, isNotNull);
    expect(firstPosition!.pageIndex, anyOf(isNull, equals(0)),
        reason: '優雅退回後應從書本開頭開始（pageIndex 0 或尚未回報）');
  });
}
```

- [x] **Step 2: 確認測試裝置在線**

```bash
adb devices -l
```

預期：`3CEF42ECD491687` 出現在清單中且狀態為 `device`。

- [x] **Step 3: 於真機執行本測試**

於 `app/` 目錄執行：

```bash
flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687
```

預期：PASS。若「200ms 內完成跳轉」斷言在裝置上不穩定（Dart 測試框架層級的時間量測含 `pumpAndSettle` 動畫等待，可能無法精確反映純原生跳轉耗時），依註解說明改為人工碼表量測，記錄實際觀察結果於 `issues.md` Issue 6 段落，不阻塞本工單。

- [x] **Step 4: Commit**

```bash
git add app/integration_test/foliate_toc_footer_test.dart
git commit -m "test(epic-17): 新增流式 EPUB 目錄跳轉/頁尾頁碼/舊格式優雅退回真機整合測試"
```

---

### Task 6: 全面驗證

**Files:** 無新增/修改檔案（除 Step 6 的 `issues.md` 狀態更新）。

**Interfaces:**
- Consumes: Task 1-5 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [x] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS（Issue 5 完成時基準為 569 個測試，本工單 Task 3 新增 5 個、Task 4 新增 4 個，預期共 578 個）。

- [x] **Step 2: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [x] **Step 3: 執行 Kotlin 編譯與 JVM 測試**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:testDebugUnitTest
```

預期：兩者皆 `BUILD SUCCESSFUL`（93 個既有 JVM 測試 + Task 1 新增 10 個 `FoliateLocatorCodecTest`，共 103 個）。

- [x] **Step 4: 於真機執行 Foliate 相關 `integration_test`**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_stream_nav_zone_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687
```

預期：全數 PASS。

- [x] **Step 5: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-5 修改/新增的檔案，無不相關的暫存產物。

- [x] **Step 6: 更新 `issues.md` Issue 6 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 6」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1-5 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-6.md` Task 1-6 完成 `FoliateLocatorCodec.kt`（純函式：`extractCfi`／`parseTocEntries`，含 10 個 JVM 測試）／`FoliateEpubReaderView.kt`（`jumpToLocator`／`getTableOfContents` method channel、`onLocatorChanged`／`onTableOfContentsReady` 橋接）／`main.js`（`window.jumpToLocator`／`window.getTableOfContents`／`buildTocEntry`／持續 `relocate` 推播／`initialCfi` 開書起始定位）／`foliate_epub_reader_view.dart`（`initialLocatorJson`／`onLocatorChanged`／`jumpToLocator`／`loadTableOfContents`）／`EpubPositionInfo`（新增 `pageIndex`/`totalPages`）／`ReaderScreen`（`_jumpToEpubLocator()` 統一分派、`_handleFoliateLayoutResolved` 觸發目錄背景抓取、`_buildFoliateEpubFooter()`）。新增真機整合測試 `foliate_toc_footer_test.dart`。`flutter test`（578 tests）／`flutter analyze`／`./gradlew.bat :app:compileDebugKotlin`／`./gradlew.bat :app:testDebugUnitTest`（103 tests）以及真機 `integration_test`（目錄跳轉、頁尾頁碼、舊格式 `initialLocatorJson` 優雅退回）皆全數通過。劃線與備註留給 Issue 8。
```

- [x] **Step 7: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 6 完成，更新 issues.md 狀態"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 6 描述逐項對應：
- `getTableOfContents`（原生端讀 `book.toc`，透過 `book.resolveHref(item.href)` 取得 `{index, anchor}` 建構可跳轉的定位，序列化為現有 `TocEntry` wire 格式）→ Task 2（`main.js` `buildTocEntry`/`window.getTableOfContents`＋Kotlin `onTableOfContentsReady`）+ Task 1（`FoliateLocatorCodec.parseTocEntries` 負責 JSON→wire 格式轉換）。
- `jumpToLocator`（解析傳入的新格式 JSON 取出 `cfi` 後呼叫 `view.goTo(cfi)`；FR-08 200ms 跳轉精度驗收）→ Task 1（`extractCfi`）+ Task 2（Kotlin case + `window.jumpToLocator`）+ Task 5（真機 200ms 量測）。
- 新增定位 JSON 格式（`{cfi, index, fraction}`）→ Task 2（`main.js` `buildTocEntry`/persistent relocate listener 序列化）+ Global Constraints 明確記錄格式定義。
- 舊格式資料的優雅退回 → Task 1（`extractCfi` 對舊格式回傳 `null`，JVM 測試覆蓋）+ Task 2（`openBook`/`jumpToLocator` case 皆呼叫 `extractCfi` 過濾）+ Task 5（真機驗證不崩潰、從頭開始）。
- 頁尾頁碼（`onLocatorChanged` 帶出 `location.current`/`location.total`；不送出 `totalCharacterCount`）→ Task 2（persistent relocate listener）+ Task 3（`EpubPositionInfo.pageIndex`/`totalPages`）+ Task 4（`_buildFoliateEpubFooter`）+ Global Constraints 明確禁止字數統計。

**單元測試要求逐項對應**：
- 新格式 JSON 序列化/反序列化 round-trip → Task 1 `FoliateLocatorCodecTest`「解析含巢狀子項目的目錄陣列」等測試。
- 舊格式（Readium Locator JSON 樣式）解析失敗時的優雅退回邏輯 → Task 1 `FoliateLocatorCodecTest`「舊格式 Readium Locator JSON 沒有 cfi 欄位」等測試。
- `foliate_epub_reader_view.dart`：`onLocatorChanged`/`onCharacterCountReady`（本 widget 不觸發，確認呼叫端不會誤判）→ Task 3 的 `onLocatorChanged` 解析測試（正向覆蓋）；`onCharacterCountReady`/`totalCharacterCount` 依 Global Constraints 明確規定**不新增**至本 widget（結構性不存在，非執行期行為，已於 Task 3 Step 7 widget 說明文件記錄），Task 4 新增的「onLocatorChanged 未觸發前頁尾不顯示」測試間接證實 `_totalCharacterCount`-based 舊頁尾路徑對流式書籍確實不會生效。

**驗收標準逐項對應**：
- 上述測試皆通過、`flutter analyze` 乾淨 → Task 6 Step 1-2。
- `integration_test`（真實裝置）：目錄樹狀清單顯示正確、點擊項目 200ms 內跳轉至對應內容；`ReaderFooter` 頁碼顯示正確反映 `location.current`/`total`；舊格式 `initialLocatorJson` 優雅退回不崩潰、從書本開頭開始 → Task 5 三個測試逐一對應。

**Placeholder 掃描**：全文檢查未發現「TBD」/「待補」/「依實際情況調整」等佔位語句，所有程式碼區塊皆為完整可執行內容。

**型別一致性檢查**：`FoliateLocatorCodec.extractCfi(String?): String?`／`parseTocEntries(String): List<Map<String, Any?>>` 的簽章在 Task 1（定義）與 Task 2（`FoliateEpubReaderView.kt` 呼叫）逐字一致；`FoliateEpubReaderView.jumpToLocator(GlobalKey<State<FoliateEpubReaderView>>, String)`／`loadTableOfContents(GlobalKey<State<FoliateEpubReaderView>>): Future<List<TocEntry>>` 在 Task 3（定義）、Task 4（`ReaderScreen` 呼叫）、Task 5（整合測試呼叫）三處保持一致；`EpubPositionInfo` 新增的 `pageIndex`/`totalPages: int?` 欄位在 Task 3（定義）、Task 2 的 Kotlin `onLocatorChanged` 回傳欄位名稱（`pageIndex`/`totalPages`）、Task 4（`_buildFoliateEpubFooter` 讀取）三處欄位命名一致，無 `currentLocation`/`page` 等不一致別名。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-6.md`. Two execution options:

1. **Subagent-Driven（推薦）**——每個 Task 派一個全新 subagent 執行，Task 之間插入審查
2. **Inline Execution**——在目前這個 session 內依 executing-plans 批次執行，於檢查點暫停

Which approach?
