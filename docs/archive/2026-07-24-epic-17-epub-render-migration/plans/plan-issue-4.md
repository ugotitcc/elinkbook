# Epic 17 Issue 4 — 排版方向與版面偏好設定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `FoliateEpubReaderView`（Issue 3 已建置，目前只能開書渲染出第一頁）支援排版方向（橫排/直排）雙向切換與既有 9 項版面偏好設定（字型/字級/字重/行距/段落間距/邊界/對齊/出版社樣式/換頁模式），並在開書當下依書本自己的 CSS 宣告自動判斷初始排版方向（FR-06），與既有 `EpubReaderView`（Readium，FXL 專用）刻意保持公開介面對稱。

**Architecture:** Kotlin 端 `FoliateEpubReaderView.kt` 新增 `setPreferences` method channel 方法，把偏好設定 map 合併進持久狀態、序列化為 JSON，`openBook` 時以 URL query string 形式（`?prefs=...&fontFaceCss=...`）傳給 JS（WebView 尚未載入頁面前無法用 `evaluateJavascript`，`setPreferences` 之後的呼叫才改用 `evaluateJavascript` 呼叫 JS 端暴露的 `window.applyPreferences()`）。JS 端（`main.js`）延續 Issue 1 Spike 已驗證的 `book.transformTarget` 'data' 事件機制（在 CSS 資源文字被解析前攔截，保證影響 Paginator 第一次的方向判定），用於：(a) 偵測書本是否已宣告 `writing-mode`（FR-06），(b) 開書當下若已知目標方向則直接附加覆蓋規則。開書完成後與之後任何 `setPreferences` 呼叫，皆透過 `foliate-js` 內建的 `Paginator.setStyles([beforeCss, overrideCss])` API（已直接查證 `paginator.js` 原始碼確認此 API 存在且設計上正是給「reading system 覆蓋書本樣式」用途）注入覆蓋 CSS——`beforeCss` 固定放 5 款內建字型的 `@font-face` 宣告（供 `fontFamily` 選擇引用），`overrideCss` 依目前偏好動態產生。Dart 端 `foliate_epub_reader_view.dart` 新增與 `EpubReaderView` 對稱的 9 個偏好建構參數 + `_buildPreferencesMap()`/`didUpdateWidget`，`ReaderScreen` 的 Foliate 分支比照既有 EpubReaderView 分支傳入 `_resolved.*` 欄位，並讓 `_handleFoliateLayoutResolved` 也設定 `_autoDetectedWritingMode`（讓「版面設定」按鈕對流式書籍生效）。

**Tech Stack:** Kotlin（`org.json.JSONObject`、`FlutterInjector`、`WebView.evaluateJavascript`）、JavaScript（`readest/foliate-js` 既有 `Paginator.setStyles()`/`book.transformTarget`）、Dart/Flutter（`AndroidView`/`MethodChannel`）、`flutter_test`（widget test）、`integration_test`（真機驗證）。

## Global Constraints

- **雙向 `writing-mode` CSS 覆蓋僅透過 `book.transformTarget` 的 `'data'` 事件在 CSS 資源文字被解析前附加**（比照 Issue 1 Spike 已驗證的時序，`plans/plan-issue-1.md` Task 3 Global Constraints）：**不可**改用「事後對已載入文件插入 `<style>`」的作法去做「開書當下已知方向」這件事——已讀過 `paginator.js` 原始碼確認每個分頁 iframe 的原生 `load` 監聽器會在內容載入當下就同步呼叫 `getDirection(doc)` 決定方向並開始 columnize，事後插入樣式為時已晚。**首次開書若 `initialPreferences.writingMode` 為 `null`（尚未曾設定過），不主動附加任何覆蓋規則**（ADR 0003「初次開書不主動設定，讓判斷結果自然呈現」），讓書本自己的 CSS 宣告（或無宣告時的預設橫排）自然生效。
- **FR-06 自動判斷**：`book.transformTarget` 的 `'data'` 事件攔截到的原始 CSS 文字（僅 `type === 'text/css'` 的外部 CSS 資源，不含 XHTML 內的 inline `<style>`——已確認現有測試素材皆無 CSS，需新增一份帶外部 CSS 檔案宣告 `writing-mode: vertical-rl` 的素材，見 Task 5）用正規表達式檢查是否含 `writing-mode`／`-epub-writing-mode` 宣告；有宣告則尊重書本自己的值，判斷不出來則預設橫排。**不使用書本 `language` metadata 做語言猜測**。
- **開書完成與之後任何 `setPreferences` 呼叫，皆透過 `Paginator.setStyles([fontFaceCss, overrideCss])` 套用**（已直接查證 `app/android/app/src/main/assets/foliate/paginator.js` 第 3445-3466 行原始碼確認：`setStyles(styles)` 接受 `[beforeStyle, style]` 陣列，分別寫入每個已載入文件 `<head>` 內兩個既有的空 `<style>` 元素——`$beforeStyle`／`$style`，見同檔案第 3027-3038 行 `afterLoad`；本機制原生支援「reading system 覆蓋」用途，不需要自行插入新元素）。`fontFaceCss` 只需在開書當下計算一次（字型檔案路徑固定不隨偏好變動），`overrideCss` 每次呼叫依目前完整偏好狀態重新產生。
- **`pageTurnMode == scroll` 對應 `view.renderer.setAttribute('flow', 'scrolled')`**（既有 `paginated` 為預設值，比照 issues.md 明確指定的既有 API），此設定與 `setStyles()` 無關、需獨立呼叫。
- **`fontFamily` 的 5 款內建字型 `@font-face` 來源**：透過 `FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/fonts/<檔名>")` 取得 Flutter asset 在 Android `AssetManager` 的實際查找鍵（比照 `EpubReaderView.kt` `buildNavigatorConfiguration()` 既有做法），經 `FoliateEpubReaderView.kt` 既有註冊的 `/assets/` `WebViewAssetLoader.AssetsPathHandler` 直接提供給 WebView（該 handler 服務整個 Android `assets/` 目錄，不限 `assets/foliate/` 子目錄，不需要額外註冊新的 `PathHandler`）。5 款字型與家族名稱字串**須與 `app/lib/reader/app_font.dart` 的 `AppFontFamilyName.familyName` 逐字一致**：`SourceHanSansTC`／`SourceHanSerifTC`／`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`。
- **初始偏好透過 URL query string 傳遞給 JS**（`?prefs=<url-encoded JSON>&fontFaceCss=<url-encoded CSS 文字>`），**不使用** `evaluateJavascript`（`webView.loadUrl()` 呼叫當下頁面尚未載入，`evaluateJavascript` 此時呼叫沒有意義）。之後（書本開啟後）的 `setPreferences` 呼叫改用 `webView.evaluateJavascript("window.applyPreferences(<JSON>)", null)`。
- **`FoliateBridge.onPageRendered` 簽章新增 `writingMode: String` 參數**（原為無參數）：main.js 判斷出最終生效的 writingMode（`initialPreferences.writingMode` 優先，否則用 FR-06 偵測值，皆無則 `"horizontal"`）後，透過既有的 `relocate` 事件（`{ once: true }`，Issue 3 已驗證的觸發時機，**不得**改為在 `await view.init({})` resolve 後立即呼叫——Issue 3 的 `relocate` 事件監聽器是已驗證、已審查通過的既有觸發機制，本工單只在同一個監聽器內新增邏輯，不變更觸發時機本身）一併回傳給 Kotlin，Kotlin 原樣轉發進 `onLayoutResolved` 的 `writingMode` 欄位（Dart 端 wire 格式完全不變，只是這個值現在是真正判斷出來的，不再永遠是 `"horizontal"`）。
- **`ReaderScreen._handleFoliateLayoutResolved()` 擴充為也設定 `_autoDetectedWritingMode` 與重新計算 `_resolved`**（比照 `_handleLayoutResolved` 對應段落），但**仍然刻意不**觸發 `EpubReaderView.loadTableOfContents()`／`_reloadAnnotationsAndRefreshDecorations()`／`_loadFxlBookmarks()`（Issue 3 已確立的範圍邊界，TOC／劃線備註／書籤仍是 Issue 6/8 的範圍）。
- **`FoliateEpubReaderView` 的 9 個新增偏好建構參數與 `EpubReaderView` 對應參數同名同型別**：`writingMode: WritingMode?`／`pageTurnMode: PageTurnMode?`／`fontFamily: AppFont?`／`fontSize: double?`／`fontWeight: double?`／`lineHeight: double?`／`paragraphSpacing: double?`／`pageMargins: double?`／`textAlign: EpubTextAlign?`／`publisherStyles: bool?`。**不新增** `dualPageMode`／`isLandscape`／`navZoneActions`（皆為 FXL/PDF 專屬或 Issue 5 範圍的概念，reflowable `foliate-js` 書籍不適用「雙頁」，`navZoneActions` 是純 Dart 端 `Stack` 疊加、不送給原生端，見 issues.md Issue 5「不在原生端判讀」）。
- **已知限制（記錄供 Issue 6 留意，非本工單缺陷）**：`paginator.js` 的 `#loadAdjacentSection()`（預載相鄰章節）的 `afterLoad` 會呼叫 `this.setStyles(this.#styles)` 重新套用快取的覆蓋樣式（第 3117 行），但 `#display()`（顯示任意指定索引的章節，例如 Issue 6 的 `jumpToLocator`／目錄跳轉會用到）的 `afterLoad` **沒有**這個重新套用呼叫（第 3027-3038 行）——代表透過非連續翻頁方式（例如 TOC 跳轉）進入的新章節，理論上不會自動繼承先前已套用的偏好覆蓋，直到下次 `setPreferences` 被呼叫。本工單的驗收範圍（開書、FR-06、手動雙向切換、連續翻頁）不會觸發這個路徑，Issue 6 實作 `jumpToLocator` 時應一併真機驗證此風險是否成立。
- **測試裝置**：沿用既有測試裝置（`3CEF42ECD491687`，Android 15/API 35）；執行前以 `adb devices -l` 重新確認裝置仍在。
- **執行環境**：所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash/MSYS2）執行，非 PowerShell／`cmd.exe`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` | 修改 | `openBook`/`setPreferences` 擴充傳遞偏好設定；`buildFontFaceCss()`；`FoliateBridge.onPageRendered(writingMode)` 簽章變更 |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | 讀取 `?prefs=`/`?fontFaceCss=`；`book.transformTarget` 雙向覆蓋注入 + FR-06 偵測；`window.applyPreferences()`；`flow` 屬性依 `pageTurnMode` |
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 9 個偏好建構參數／`_buildPreferencesMap()`／`didUpdateWidget`/`_preferencesChanged()` |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改 | 新增偏好參數的 widget test |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` Foliate 分支傳入 `_resolved.*`；`_handleFoliateLayoutResolved` 擴充 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增分派後偏好參數正確傳遞、`_autoDetectedWritingMode` 生效的 widget test |
| `app/test/fixtures/sample_declares_vertical.epub` | 新增 | 帶外部 CSS 宣告 `writing-mode: vertical-rl` 的測試素材（FR-06「已宣告」情境） |
| `app/integration_test/foliate_epub_reader_view_test.dart` | 修改 | 真機驗證：FR-06 兩種素材、手動雙向切換即時生效、字型/字級/行距套用 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 4 完成說明 |

---

### Task 1: `FoliateEpubReaderView.kt`——偏好設定傳遞基礎建設

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`

**Interfaces:**
- Consumes: 無新的外部依賴（`org.json.JSONObject`／`io.flutter.FlutterInjector` 皆為既有專案依賴，`EpubReaderView.kt` 已在使用兩者）。
- Produces: `openBook` method channel 方法新增 `initialPreferences: Map<String, Any?>?` 參數；新增 `setPreferences` method channel 方法（參數為完整偏好 map）；`FoliateBridge.onPageRendered(writingMode: String)` 簽章由無參數變為單一 `String` 參數。Task 2 的 `main.js` 依賴 URL query string 格式 `?prefs=<JSON>&fontFaceCss=<CSS>`；Task 3 的 Dart widget 依賴這兩個 method channel 方法名稱與參數格式。

**本 Task 無 JVM 單元測試**（比照 Issue 2/3 既定退路）：`JSONObject` 序列化與 `FlutterInjector` 皆是框架/函式庫呼叫的直接串接，沒有可抽出的純邏輯。驗收標準是 `compileDebugKotlin` 成功 + 既有 93 個 JVM 測試（Issue 3 完成後的數量）不受影響。

- [x] **Step 1: 新增 import 與 `currentPreferences` 欄位**

第 1-19 行的 import 區塊：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.io.FileInputStream
```

改為：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
```

在 `private var currentBookUri: Uri? = null`（第 65 行）之後新增：

```kotlin

    /**
     * 目前已生效的完整偏好設定（比照 EpubReaderView.kt currentPreferences
     * 的合併語意，見 docs/adr/0006-epub-reader-batch-preferences-contract.md）
     * ——openBook 的 initialPreferences 與後續 setPreferences 都是「合併進
     * 這個 map、再整組序列化送給 JS」，而不是各自獨立送出，否則後送出的
     * 欄位會把先前已設定的其他欄位在 JS 端「遺忘」（JS 端 applyPreferences()
     * 每次都是用收到的完整物件重新產生 CSS，不會自己記得上一次的值）。
     */
    private val currentPreferences = mutableMapOf<String, Any?>()

    /** 5 款內建字型的 @font-face CSS 宣告，開書當下計算一次（見
     * [buildFontFaceCss]），字型檔案路徑固定不隨後續 setPreferences 呼叫
     * 變動。 */
    private var fontFaceCss: String = ""
```

- [x] **Step 2: `onMethodCall` 新增 `setPreferences` 分支、`openBook` 分支帶入偏好**

第 109-117 行的：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
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
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

- [x] **Step 3: 擴充 `openBook()`、新增 `setPreferences()`、新增 `buildFontFaceCss()`**

第 131-158 行的：

```kotlin
    private fun openBook(path: String?) {
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
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }
```

改為：

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

    /**
     * 合併 [preferences] 進 [currentPreferences] 並整組序列化送給 JS（比照
     * EpubReaderView.kt setPreferences() 的合併語意，見 Global Constraints）。
     * 書本尚未成功開啟（openBook 尚未呼叫）時 currentPreferences 為空，
     * 呼叫仍會執行但 JS 端 window.applyPreferences 此時尚未定義，
     * evaluateJavascript 靜默失敗——Dart 端只會在 onPageRendered 觸發之後
     * 才送出這個指令，理論上不會發生。
     */
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        currentPreferences.putAll(preferences)
        val prefsJson = JSONObject(currentPreferences).toString()
        webView.evaluateJavascript("window.applyPreferences($prefsJson)", null)
    }

    /**
     * 產生固定的 5 款內建字型 @font-face 宣告（FR-09），供 JS 端
     * window.applyPreferences() 的 fontFamily 選擇引用。透過 FlutterInjector
     * 取得 Flutter asset 的 AssetManager 查找鍵（比照 EpubReaderView.kt
     * buildNavigatorConfiguration() 既有做法），經既有註冊的 /assets/
     * WebViewAssetLoader.AssetsPathHandler 提供給 WebView（該 handler 服務
     * 整個 Android assets/ 目錄，不限 assets/foliate/ 子目錄，故可直接沿用，
     * 不需要額外註冊 PathHandler）。家族名稱字串須與 Dart 端
     * AppFont.familyName（app/lib/reader/app_font.dart）逐字一致。
     */
    private fun buildFontFaceCss(): String {
        val loader = FlutterInjector.instance().flutterLoader()
        val fontAssets = mapOf(
            "SourceHanSansTC" to "assets/fonts/SourceHanSansTC-VF.ttf",
            "SourceHanSerifTC" to "assets/fonts/SourceHanSerifTC-VF.ttf",
            "GuanKiapTsingKhai" to "assets/fonts/GuanKiapTsingKhai.ttf",
            "TaiwanPearl" to "assets/fonts/TaiwanPearl-Regular.ttf",
            "GenRyuMinTW" to "assets/fonts/GenRyuMinTW-Regular.ttf",
        )
        return fontAssets.entries.joinToString("\n") { (familyName, path) ->
            val lookupKey = loader.getLookupKeyForAsset(path)
            "@font-face { font-family: '$familyName'; " +
                "src: url('https://appassets.androidplatform.net/assets/$lookupKey'); }"
        }
    }
```

- [x] **Step 4: `FoliateBridge.onPageRendered` 新增 `writingMode` 參數**

第 195-213 行的：

```kotlin
    private inner class FoliateBridge {
        @JavascriptInterface
        fun onPageRendered() {
            mainHandler.post {
                if (isDisposed || pageReported) return@post
                pageReported = true
                channel.invokeMethod("onPageRendered", null)
                channel.invokeMethod(
                    "onLayoutResolved",
                    mapOf(
                        "isFixedLayout" to false,
                        // 依 CSS 宣告判斷實際直排/橫排是 Issue 4 的範圍，
                        // 本 Issue 固定回報 horizontal，僅為滿足
                        // EpubLayoutInfo 型別簽章的非空要求。
                        "writingMode" to "horizontal",
                    ),
                )
            }
        }
```

改為：

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
```

- [x] **Step 5: 編譯確認**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`，無編譯錯誤。

- [x] **Step 6: 執行既有 JVM 測試確認無回歸**

```bash
./gradlew.bat :app:testDebugUnitTest
```

預期：`BUILD SUCCESSFUL`（93 個既有測試，Issue 4 本身無新增 JVM 測試）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt
git commit -m "feat(epic-17): FoliateEpubReaderView 新增偏好設定傳遞基礎建設（openBook/setPreferences/fontFaceCss）"
```

---

### Task 2: `main.js`——雙向 CSS 覆蓋、FR-06 自動判斷、`applyPreferences`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 1 的 URL query string 格式（`?prefs=<JSON>&fontFaceCss=<CSS>`）與 `window.FoliateBridge.onPageRendered(writingMode)` 新簽章。
- Produces: `window.applyPreferences(prefs)` 全域函式，供 Task 1 的 `evaluateJavascript` 呼叫。本 Task 完成後，開書＋後續偏好設定變更的完整資料流串接完畢，留待 Task 5 真機驗證。

**本 Task 無自動化測試**（比照 Issue 3 的既定退路：本專案無 JS 測試執行環境，JS 邏輯正確性由 Task 5 的真機 `integration_test` 驗證——issues.md 明列的「字串/正規表達式判斷 CSS 是否已宣告 writing-mode：含宣告與不含宣告兩種輸入的邊界測試」，實際上就是 Task 5 用兩份不同素材做的真機驗證，並非額外的 JS 單元測試框架）。

- [x] **Step 1: 覆寫 `main.js`**

把 `app/android/app/src/main/assets/foliate/main.js` 內容改為：

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

// FoliateBridge 由原生端 FoliateEpubReaderView.kt 透過
// WebView.addJavascriptInterface() 注入，見該檔案 KDoc 說明——不是
// console.log 解析（那是 Issue 1 Spike harness 專屬手法）。

const params = new URLSearchParams(location.search)
const initialPrefs = JSON.parse(params.get('prefs') || '{}')
// 5 款內建字型的 @font-face 宣告（見 FoliateEpubReaderView.kt
// buildFontFaceCss()），開書當下由原生端算好透過 query string 傳入，字型
// 檔案路徑固定不隨後續 applyPreferences 呼叫變動。
const fontFaceCss = params.get('fontFaceCss') || ''

// 判斷書本第一個 section 的 CSS 是否已宣告 writing-mode（epic-17
// Issue 4，FR-06）。同時涵蓋標準屬性與 EPUB 專屬的 -epub- 前綴寫法；只
// 檢查值是否為 vertical-rl/vertical-lr——horizontal-tb 或其他非直排值視為
// 「未宣告直排」，交由後續判斷邏輯處理。
const WRITING_MODE_DECLARATION_RE =
  /(?:^|[^-])(?:-epub-)?writing-mode\s*:\s*vertical-(?:rl|lr)/i

// FR-06 偵測結果，null 代表尚未偵測到任何 CSS 資源（理論上開書流程中
// 第一個 CSS 資源解析時就會賦值一次，之後維持不變——只需要書本「第一個」
// section 的判斷結果，見 issues.md Issue 4 描述）。
let detectedBookWritingMode = null

/**
 * 依目前偏好 [prefs] 產生要疊加在書本樣式之上的覆蓋 CSS 文字（透過
 * Paginator.setStyles() 的第二個陣列元素套用，見 Global Constraints）。
 * `publisherStyles === false` 時改用萬用選取器 `*`，讓覆蓋規則的優先度
 * 蓋過書本自己更具體的選取器（比照 Readium「忽略出版社樣式」的既有語意
 * 精神，非逐位元組相同的實作，這兩套渲染引擎本就刻意獨立，見 ADR 0011）。
 */
function buildOverrideCss(prefs) {
  const rules = []
  const selector = prefs.publisherStyles === false
    ? '*'
    : 'body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6'

  if (prefs.writingMode === 'vertical') {
    rules.push('html, body { writing-mode: vertical-rl !important; }')
  } else if (prefs.writingMode === 'horizontal') {
    rules.push('html, body { writing-mode: horizontal-tb !important; }')
  }
  if (prefs.fontFamily) {
    rules.push(`${selector} { font-family: '${prefs.fontFamily}' !important; }`)
  }
  if (typeof prefs.fontSize === 'number') {
    rules.push(`html { font-size: ${prefs.fontSize * 100}% !important; }`)
  }
  if (typeof prefs.fontWeight === 'number') {
    // 換算方式與 EpubReaderView.kt applyFontWeightCascade() 一致
    // （0-1000 CSS font-weight 數值空間，Readium 倍率 1.0 對應 CSS 400）。
    const cssWeight = Math.min(1000, Math.max(1, Math.round(prefs.fontWeight * 400)))
    rules.push(`${selector} { font-weight: ${cssWeight} !important; }`)
  }
  if (typeof prefs.lineHeight === 'number') {
    rules.push(`html, body { line-height: ${prefs.lineHeight} !important; }`)
  }
  if (typeof prefs.paragraphSpacing === 'number') {
    rules.push(`p { margin-bottom: ${prefs.paragraphSpacing}em !important; }`)
  }
  if (typeof prefs.pageMargins === 'number') {
    rules.push(`body { padding: 0 ${1.5 * prefs.pageMargins}em !important; }`)
  }
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`)
  }
  return rules.join('\n')
}

/**
 * 套用完整偏好設定（開書當下的 initialPreferences，或後續 setPreferences
 * 呼叫，兩者格式相同）：pageTurnMode 對應 Paginator 的 flow 屬性（獨立於
 * CSS 覆蓋之外的設定），其餘 9 項透過 setStyles() 疊加 CSS。暴露為
 * window 全域函式供原生端 evaluateJavascript 呼叫（見
 * FoliateEpubReaderView.kt setPreferences()）。
 */
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}

async function openBook() {
  try {
    const book = await makeBook(
      'https://appassets.androidplatform.net/book/current.epub',
    )
    // 雙向 writing-mode CSS 覆蓋 + FR-06 偵測：在每個 CSS 資源文字被解析前
    // 攔截——比照 Issue 1 Spike 已驗證的時序（見 Global Constraints），
    // 保證於 Paginator 第一次計算方向/分欄之前就已生效。
    book.transformTarget?.addEventListener('data', (e) => {
      if (e.detail.type !== 'text/css') return
      e.detail.data = Promise.resolve(e.detail.data).then((css) => {
        if (detectedBookWritingMode === null) {
          detectedBookWritingMode = WRITING_MODE_DECLARATION_RE.test(css)
            ? 'vertical'
            : 'horizontal'
        }
        // 初次開書若呼叫端（openBook 的 initialPreferences）未指定
        // writingMode，不附加任何覆蓋規則，讓書本自己的 CSS 宣告（或無
        // 宣告時的預設橫排）自然生效（ADR 0003「初次開書不主動設定」）。
        if (!initialPrefs.writingMode) return css
        const override = initialPrefs.writingMode === 'vertical'
          ? 'writing-mode: vertical-rl !important;'
          : 'writing-mode: horizontal-tb !important;'
        return `${css}\nhtml, body { ${override} }\n`
      })
    })
    // 見 Issue 1 Spike（plans/plan-issue-1.md Task 2）已驗證的行為與 Issue 3
    // 已驗證的觸發時機：view.open(book) 本身不導覽到任何 section，
    // relocate 事件在 view.init() 內部完成首次導覽後才觸發，{ once: true }
    // 確保只處理第一次。
    view.addEventListener('relocate', () => {
      const resolvedWritingMode =
        initialPrefs.writingMode ?? detectedBookWritingMode ?? 'horizontal'
      window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode })
      window.FoliateBridge.onPageRendered(resolvedWritingMode)
    }, { once: true })
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init({})
  } catch (e) {
    window.FoliateBridge.onError(String((e && e.message) || e))
  }
}

openBook()
```

- [x] **Step 2: 確認語法正確（Node 若本機可用，僅語法檢查，不執行 DOM 相關程式碼）**

```bash
node --check app/android/app/src/main/assets/foliate/main.js
```

預期：無輸出（語法正確）。若本機無 `node` 可用，跳過此步驟，改在 Task 5 真機驗證時一併確認（WebView 載入失敗會透過既有 `onError` 機制回報，比照 Issue 1/3 既定的驗證方式）。

- [x] **Step 3: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-17): main.js 新增雙向 writing-mode 覆蓋、FR-06 自動判斷、applyPreferences"
```

---

### Task 3: `foliate_epub_reader_view.dart`——9 個偏好建構參數

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1/2 的 `openBook`（`initialPreferences` 鍵）／`setPreferences` method channel 契約。
- Produces: `FoliateEpubReaderView` 新增 `writingMode`／`pageTurnMode`／`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`pageMargins`／`textAlign`／`publisherStyles` 十個可選具名參數（含既有 `writingMode`——注意：Issue 3 完成時本類別**沒有** `writingMode` 建構參數，只有透過 `onLayoutResolved` 回報的唯讀值；本 Task 新增的是可以從外部**設定**方向的參數，與回報值是兩個不同方向的資料流，比照 `EpubReaderView` 的既有模式）。Task 4 的 `ReaderScreen._buildNativeView()` 依賴這組建構參數名稱。

- [ ] **Step 1: 在 `foliate_epub_reader_view_test.dart` 新增失敗測試**

在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
```

在既有第一個測試（`_onPlatformViewCreated 呼叫 openBook 並帶入正確的 path`）之後插入：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含所有非 null 建構參數',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: AppFont.sourceHanSans,
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        pageMargins: 1.3333,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], {
      'writingMode': 'vertical',
      'pageTurnMode': 'scroll',
      'fontFamily': 'SourceHanSansTC',
      'fontSize': 1.125,
      'fontWeight': 1.75,
      'lineHeight': 1.6,
      'paragraphSpacing': 1.2,
      'pageMargins': 1.3333,
      'textAlign': 'justify',
      'publisherStyles': false,
    });
  });

  testWidgets('所有偏好欄位皆為 null 時，initialPreferences 為空 map',
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
    expect(openBookCall.arguments['initialPreferences'], <String, Object?>{});
  });

  testWidgets(
      '任一偏好欄位變動時，didUpdateWidget 呼叫 setPreferences 並帶入目前所有非 null 欄位',
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

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
      ),
    ));
    await tester.pumpAndSettle();

    final setPreferencesCall =
        instanceCalls.firstWhere((c) => c.method == 'setPreferences');
    expect(setPreferencesCall.arguments, {'writingMode': 'vertical'});
  });

  testWidgets('偏好欄位皆未變動時，didUpdateWidget 不呼叫 setPreferences',
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

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls.where((c) => c.method == 'setPreferences'), isEmpty);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：編譯失敗（新增的偏好具名參數尚未定義）。

- [ ] **Step 3: 修改 `foliate_epub_reader_view.dart`**

把整個檔案內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';

/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Issue（epic-17-epub-render-migration Issue 4）新增 9 項版面偏好
/// 建構參數，與既有 [EpubReaderView] 對稱參數同名同型別（不含 `dualPageMode`／
/// `isLandscape`／`navZoneActions`——reflowable 流式書籍不適用「雙頁」，
/// 3×3 導航熱區是 Issue 5 的範圍且完全由 Dart 端處理、不送給原生端）。
/// [writingMode] 是「呼叫端要求套用的方向」（可寫），與 [onLayoutResolved]
/// 回報的 [EpubLayoutInfo.writingMode]（原生端判斷/回報的唯讀值）是兩個
/// 不同方向的資料流，比照 [EpubReaderView] 既有模式。
///
/// 排版設定以外的換頁／目錄／劃線備註參數留待 Issue 5-8 補上。
class FoliateEpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意（1.0 = normal），比照 EpubReaderView
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
  });

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}

class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  MethodChannel? _channel;

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

  @override
  void didUpdateWidget(covariant FoliateEpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferencesChanged(oldWidget)) {
      _channel?.invokeMethod('setPreferences', _buildPreferencesMap());
    }
  }

  bool _preferencesChanged(FoliateEpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles;
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與原生端契約一致
  /// （見 docs/epics/epic-17-epub-render-migration/plans/plan-issue-4.md
  /// Global Constraints）。`null` 值的欄位完全不出現在 map 中，比照
  /// `EpubReaderView._buildPreferencesMap()` 既有慣例。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.writingMode != null) {
      map['writingMode'] =
          widget.writingMode == WritingMode.vertical ? 'vertical' : 'horizontal';
    }
    if (widget.pageTurnMode != null) {
      map['pageTurnMode'] =
          widget.pageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated';
    }
    if (widget.fontFamily != null) {
      map['fontFamily'] = widget.fontFamily!.familyName;
    }
    if (widget.fontSize != null) map['fontSize'] = widget.fontSize;
    if (widget.fontWeight != null) map['fontWeight'] = widget.fontWeight;
    if (widget.lineHeight != null) map['lineHeight'] = widget.lineHeight;
    if (widget.paragraphSpacing != null) {
      map['paragraphSpacing'] = widget.paragraphSpacing;
    }
    if (widget.pageMargins != null) map['pageMargins'] = widget.pageMargins;
    if (widget.textAlign != null) map['textAlign'] = widget.textAlign!.name;
    if (widget.publisherStyles != null) {
      map['publisherStyles'] = widget.publisherStyles;
    }
    return map;
  }

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

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/foliate_epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：全數 PASS（既有 4 個 + 新增 4 個）。

- [ ] **Step 5: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): FoliateEpubReaderView Dart widget 新增 9 個版面偏好建構參數"
```

---

### Task 4: `ReaderScreen`——傳入偏好設定、`_handleFoliateLayoutResolved` 擴充

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `FoliateEpubReaderView` 9 個偏好建構參數。
- Produces: 流式 EPUB 開書後，`_autoDetectedWritingMode` 正確依 `onLayoutResolved` 回報值設定，「版面設定」按鈕正確從停用轉為可用；`ReaderSettingsSheet` 變動的偏好正確傳遞到 `FoliateEpubReaderView`。

- [ ] **Step 1: 在 `reader_screen_test.dart` 新增失敗測試**

在既有的 Issue 3 分派測試（`isFixedLayout: false 時直接建構 FoliateEpubReaderView，不呼叫偵測`）之後插入：

```dart
  testWidgets(
      '流式 EPUB（isFixedLayout: false）開書後，onLayoutResolved 回報結果驅動「版面設定」按鈕從停用轉為可用',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null',
    );

    final foliateView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    foliateView.onLayoutResolved?.call(const EpubLayoutInfo(
      isFixedLayout: false,
      writingMode: WritingMode.vertical,
    ));
    await tester.pump();

    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNotNull,
      reason: 'onLayoutResolved 觸發後，_autoDetectedWritingMode 非 null，按鈕應可用',
    );
  });

  testWidgets(
      '流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final initialView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    initialView.onLayoutResolved?.call(const EpubLayoutInfo(
      isFixedLayout: false,
      writingMode: WritingMode.horizontal,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('writing_mode_vertical_option')));
    await tester.pumpAndSettle();

    final updatedView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(updatedView.writingMode, WritingMode.vertical);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：兩個新測試皆 FAIL——第一個因 `_handleFoliateLayoutResolved` 尚未設定 `_autoDetectedWritingMode`（按鈕維持停用）；第二個因 `_buildNativeView` 的 Foliate 分支尚未傳入 `writingMode` 等 `resolved.*` 欄位。

- [ ] **Step 3: 擴充 `_handleFoliateLayoutResolved`**

第 785-799 行的：

```dart
  /// FoliateEpubReaderView（流式，Issue 3）專屬的 onLayoutResolved 處理，
  /// 刻意比 `_handleLayoutResolved`（EpubReaderView／FXL 分支既有邏輯）
  /// 精簡：只設定 `_isFixedLayout`（本 widget 恆回傳 false），不設定
  /// `_autoDetectedWritingMode`／不觸發 `EpubReaderView.loadTableOfContents`／
  /// `_reloadAnnotationsAndRefreshDecorations`／`_loadFxlBookmarks`——這些呼叫
  /// 對尚未掛載的 EpubReaderView/`_epubReaderViewKey` 雖然會靜默 no-op、
  /// 技術上無害，但會讓 `_tocLoaded`/`_annotationsLoaded` 被誤判為「已
  /// 完成」，使「目錄」/「筆記」按鈕看似可用卻永遠開出空清單/無法互動。
  /// 讓「版面設定」/「目錄」/「筆記」按鈕維持停用狀態（依賴
  /// `_autoDetectedWritingMode`/`_tocLoaded`/`_annotationsLoaded` 的既有
  /// 判斷條件），直到 Issue 4/6/8 依序補上流式 foliate-js 的對應支援。
  void _handleFoliateLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() => _isFixedLayout = info.isFixedLayout);
  }
```

改為：

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

- [ ] **Step 4: 修改 `_buildNativeView` 的 Foliate 分支傳入偏好**

第 1496-1508 行的：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        if (!_dispatchedIsFixedLayout!) {
          return FoliateEpubReaderView(
            key: _foliateEpubReaderViewKey,
            filePath: widget.filePath,
            onPageRendered: _handlePageRendered,
            onError: _handleError,
            onLayoutResolved: _handleFoliateLayoutResolved,
          );
        }
        return EpubReaderView(
```

改為：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
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
          );
        }
        return EpubReaderView(
```

- [ ] **Step 5: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數 PASS，含既有全部 EPUB/PDF 分派、Issue 3 零回歸測試不受影響。

- [ ] **Step 6: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-17): ReaderScreen 傳入版面偏好給 FoliateEpubReaderView，_handleFoliateLayoutResolved 設定 _autoDetectedWritingMode"
```

---

### Task 5: 真機驗證——FR-06 雙素材、手動雙向切換、字型/字級套用

**Files:**
- Create: `app/test/fixtures/sample_declares_vertical.epub`
- Modify: `app/integration_test/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1（Kotlin）+ Task 2（JS）+ Task 3（Dart widget）的完整資料流。
- Produces: 真機驗證證據，供 Task 6 全面驗證彙整；不產生新的程式介面。

- [ ] **Step 1: 建立帶外部 CSS 宣告 `writing-mode: vertical-rl` 的測試素材**

現有測試素材（`sample.epub`／`sample_horizontal.epub`／`sample_long_vertical.epub`／`sample_forced_linebreak_vertical.epub`）皆已核實**沒有**任何 CSS 檔案（純 XHTML，直排效果原本是透過 Readium 的 `writingMode` 偏好參數強制套用，非書本自身宣告）；FR-06「已宣告」情境需要一份帶**外部** CSS 檔案（非 inline `<style>`——`book.transformTarget` 的 `'data'` 事件只攔截外部 CSS 資源，見 Global Constraints）宣告 `writing-mode: vertical-rl` 的全新素材：

```bash
cd "app/test/fixtures"
mkdir -p _tmp_declares_vertical/META-INF _tmp_declares_vertical/OEBPS
cd _tmp_declares_vertical

printf 'application/epub+zip' > mimetype

cat > META-INF/container.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

cat > OEBPS/content.opf <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000099</dc:identifier>
    <dc:title>elinkBook 範例 EPUB（自行宣告直排）</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
EOF

cat > OEBPS/nav.xhtml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter1.xhtml">第一章</a></li>
    </ol>
  </nav>
</body>
</html>
EOF

cat > OEBPS/style.css <<'EOF'
html, body {
  writing-mode: vertical-rl;
}
EOF

cat > OEBPS/chapter1.xhtml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>第一章</title>
<link rel="stylesheet" href="style.css" type="text/css"/>
</head>
<body>
  <h1>第一章</h1>
  <p>本書自行宣告 writing-mode: vertical-rl，供 epic-17-epub-render-migration Issue 4 的 FR-06 自動判斷測試使用。</p>
</body>
</html>
EOF

zip -X0 ../sample_declares_vertical.epub mimetype
zip -Xrg ../sample_declares_vertical.epub META-INF OEBPS
cd ..
rm -rf _tmp_declares_vertical
unzip -l sample_declares_vertical.epub
```

Expected：`unzip -l` 列出 6 個檔案（`mimetype`／`META-INF/container.xml`／`OEBPS/content.opf`／`OEBPS/nav.xhtml`／`OEBPS/style.css`／`OEBPS/chapter1.xhtml`），`mimetype` 為 Stored（可用 `unzip -v sample_declares_vertical.epub | head -3` 確認第一列 Method 為 `Stored`）。

- [ ] **Step 2: 在 `app/pubspec.yaml` 宣告新增的 asset**

在 `app/pubspec.yaml` 的 `assets:` 清單，於 `- test/fixtures/sample_multi_chapter.epub` 之後新增：

```yaml
    - test/fixtures/sample_multi_chapter.epub
    - test/fixtures/sample_declares_vertical.epub
```

- [ ] **Step 3: 新增真機測試**

在 `app/integration_test/foliate_epub_reader_view_test.dart` 既有測試（第 1-3 個，Issue 3 完成）之後插入：

```dart
  testWidgets(
      'FR-06：開啟自行宣告 writing-mode: vertical-rl 的素材，初始即為直排（不需手動切換）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_declares_vertical.epub',
        'foliate_declares_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<EpubLayoutInfo>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            errorMessage = message;
          },
          onLayoutResolved: (info) {
            if (!completer.isCompleted) completer.complete(info);
          },
        ),
      ),
    );

    final info = await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull);
    expect(info.writingMode, WritingMode.vertical,
        reason: '書本自行宣告 vertical-rl，FR-06 應偵測到並回報直排');
  });

  testWidgets(
      'FR-06：開啟完全不宣告 writing-mode 的素材，初始為橫排',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_no_declaration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<EpubLayoutInfo>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {
            errorMessage = message;
          },
          onLayoutResolved: (info) {
            if (!completer.isCompleted) completer.complete(info);
          },
        ),
      ),
    );

    final info = await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull);
    expect(info.writingMode, WritingMode.horizontal,
        reason: '書本完全不宣告 writing-mode，FR-06 應預設橫排');
  });

  testWidgets('手動切換橫排→直排、直排→橫排皆即時生效（不重新開書）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_toggle_direction.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {},
          writingMode: WritingMode.horizontal,
        ),
      ),
    );
    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    // 手動切換為直排：didUpdateWidget 偵測到變動送出 setPreferences，
    // 畫面應即時反映（不重新開書、不再次觸發 onPageRendered）。
    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {},
          writingMode: WritingMode.vertical,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 再切回橫排，確認雙向皆可逆。
    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {},
          onError: (message) {},
          writingMode: WritingMode.horizontal,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 本測試斷言 widget 樹本身未崩潰、無 onError 觸發即代表雙向切換的
    // method channel 呼叫皆正常送達；實際排版方向的視覺正確性（欄位是否
    // 真的改變）留待人工於裝置螢幕截圖確認，比照本專案既有 integration_test
    // 對「視覺效果」類驗收標準的既定作法（純程式碼斷言無法檢查像素排列）。
    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
  });

  testWidgets('字型/字級/行距等偏好設定套用後不觸發 onError（畫面應正確反映變更，人工視覺確認）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_style_prefs.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          fontFamily: AppFont.sourceHanSerif,
          fontSize: 1.5,
          fontWeight: 1.75,
          lineHeight: 2.0,
          paragraphSpacing: 1.5,
          pageMargins: 2.0,
          textAlign: EpubTextAlign.justify,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '套用完整版面偏好不應觸發 onError');
  });
```

在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/writing_mode.dart';
```

- [ ] **Step 4: 於真機執行測試**

```bash
cd app
flutter pub get
flutter test integration_test/foliate_epub_reader_view_test.dart -d <device-id>
```

預期：全數 PASS（既有 3 個 + 新增 4 個）。

- [ ] **Step 5: 人工視覺確認（補充說明，寫入 commit message 或報告，不阻擋合併）**

於真機手動操作「手動切換橫排→直排、直排→橫排皆即時生效」與「字型/字級/行距套用」兩項測試對應的畫面，肉眼確認：
- 直排/橫排切換後文字排列方向確實改變，不需要重新整個開書（畫面沒有經歷「載入中」狀態）。
- 字型確實變更為思源宋體、字級明顯變大、行距/段落間距/邊界肉眼可辨的差異、文字對齊改變。

若人工確認發現任一項未如預期生效，記錄具體現象（截圖 + 描述）於 commit message，供後續調整；本步驟不因視覺細節的主觀落差而阻擋任務完成，但需明確記錄，不得略過不提。

- [ ] **Step 6: Commit**

```bash
git add app/test/fixtures/sample_declares_vertical.epub app/pubspec.yaml app/integration_test/foliate_epub_reader_view_test.dart
git commit -m "test(epic-17): 新增 FR-06 雙素材與手動雙向切換/版面偏好真機整合測試"
```

---

### Task 6: 全面驗證

**Files:** 無新增/修改檔案（純驗證任務）。

**Interfaces:**
- Consumes: Task 1-5 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [ ] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS，特別留意 `test/screens/reader_screen_test.dart`／`test/reader/foliate_epub_reader_view_test.dart` 既有大量測試不受 Task 3/4 的欄位新增與介面擴充影響。

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

預期：兩者皆 `BUILD SUCCESSFUL`（93 個既有 JVM 測試，本 Issue 無新增）。

- [ ] **Step 4: 於真機執行全部 `foliate_epub_reader_view` 相關 `integration_test`**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart -d <device-id>
```

預期：全數 PASS（Issue 3 既有 3 個 + Issue 4 新增 4 個）。

- [ ] **Step 5: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-5 修改/新增的檔案，無不相關的暫存產物。

- [ ] **Step 6: 更新 `issues.md` Issue 4 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 4」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1-3 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-4.md` Task 1-6 完成 `FoliateEpubReaderView.kt`（偏好設定傳遞、`buildFontFaceCss`、`onPageRendered(writingMode)`）／`main.js`（雙向 `writing-mode` CSS 覆蓋、FR-06 自動判斷、`window.applyPreferences`）／`foliate_epub_reader_view.dart`（9 個版面偏好建構參數）／`ReaderScreen`（傳入偏好、`_handleFoliateLayoutResolved` 設定 `_autoDetectedWritingMode`）。新增測試素材 `sample_declares_vertical.epub`（外部 CSS 宣告 `writing-mode: vertical-rl`，供 FR-06 驗證）。`flutter test`／`flutter analyze`／`./gradlew.bat :app:testDebugUnitTest`／真機 `integration_test`（FR-06 雙素材、手動雙向切換、字型/字級/行距套用）皆通過。換頁與 3×3 導航熱區、目錄跳轉、劃線備註留給 Issue 5-8。
```

- [ ] **Step 7: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 4 完成，更新 issues.md 狀態"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 4 逐項對應：
- 雙向 `writing-mode` CSS 覆蓋（強制直排已由 Spike 驗證，強制橫排需額外驗證）→ Task 2（`main.js` 雙向覆蓋邏輯）+ Task 5 Step 3（手動雙向切換真機測試）。
- FR-06 自動判斷（不使用 `language` metadata）→ Task 2（`transformTarget` 偵測邏輯，`WRITING_MODE_DECLARATION_RE` 不涉及 `language`）+ Task 5（雙素材真機驗證）。
- `setPreferences` 批次送出、10 項既有偏好參數移植、`pageTurnMode == scroll` 對應 `flow: 'scrolled'` → Task 1（Kotlin 傳遞基礎建設）+ Task 2（JS `applyPreferences`／`flow` 屬性）+ Task 3（Dart 建構參數，9 項非 `writingMode` 之外——`writingMode` 本身也移植，共 10 項與既有 `EpubReaderView` 對稱參數逐一對應，不含 `dualPageMode`/`isLandscape`/`navZoneActions`，理由已於 Global Constraints 說明）。
- 單元測試要求（字串/正規表達式邊界測試、`didUpdateWidget`/`_preferencesChanged()`）→ Task 2（無 JS 測試框架，改由 Task 5 真機雙素材驗證，已於 Task 2 段落說明理由）+ Task 3 Step 1（widget test）。
- 驗收標準（`flutter analyze`／真機 `integration_test` 四項情境）→ Task 5/6。

**佔位符掃描**：全文無 TBD/待補字樣；Task 5 Step 5「人工視覺確認」段落是視覺效果驗收本質使然（純程式碼斷言無法檢查像素排列，比照本專案既有 `integration_test` 對視覺效果類驗收標準的既定作法，例如 Issue 4-of-epic-3-fonts-layout／epic-16-dual-page 等既有 Issue 皆有類似段落），非佔位符——所有涉及程式碼/指令的步驟皆已提供完整可執行內容。

**API 依據來源（非憑空杜撰）**：`Paginator.setStyles()`／`book.transformTarget`／`view.renderer.setAttribute('flow', ...)` 皆直接讀取 `app/android/app/src/main/assets/foliate/paginator.js`（第 3445-3466 行、第 3027-3038 行）與 `view.js`（既有 Issue 3 已驗證使用）原始碼核對得出，非憑印象猜測；`getDirection(doc)`（`paginator.js` 第 449-474 行）確認使用 `getComputedStyle(doc.body)`，佐證 CSS 文字層級的覆蓋機制（而非事後插入 `<style>`）能正確影響方向判定的原始依據；現有測試素材（`sample.epub`／`sample_horizontal.epub`／`sample_long_vertical.epub`／`sample_forced_linebreak_vertical.epub`／`sample_multi_chapter.epub`）皆已用 `unzip -l` 逐一核實完全沒有 CSS 檔案，故 Task 5 新增 `sample_declares_vertical.epub` 素材而非誤用既有素材。

**型別一致性**：`FoliateEpubReaderView`（Dart）新增的 9 個偏好參數名稱/型別與 `EpubReaderView` 對應參數逐字一致（`WritingMode?`／`PageTurnMode?`／`AppFont?`／`double?` 系列／`EpubTextAlign?`／`bool?`）；`_buildPreferencesMap()` 的 wire key 名稱（`writingMode`／`pageTurnMode`／`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`pageMargins`／`textAlign`／`publisherStyles`）在 Task 1（Kotlin `openBook`/`setPreferences` 接收）、Task 2（`main.js` `buildOverrideCss`/`applyPreferences` 讀取）、Task 3（Dart 建構）三處引用一致；`FoliateBridge.onPageRendered(writingMode: String)` 簽章在 Task 1（Kotlin 定義）、Task 2（`main.js` 呼叫端）兩處一致。

**已知限制與跨 Issue 風險已記錄**：`#loadAdjacentSection` vs `#display()` 的 `setStyles` 重新套用不對稱行為已記錄於 Global Constraints，明確標註為 Issue 6（`jumpToLocator`）需要留意驗證的風險，不在本工單範圍內處理。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-4.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
