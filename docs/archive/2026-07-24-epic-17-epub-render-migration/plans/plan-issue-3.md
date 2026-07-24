# Epic 17 Issue 3 — 核心 Widget 建置：`FoliateEpubReaderView` 開書渲染 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 真實圖書庫匯入的流式（reflowable）EPUB，改由 `readest/foliate-js`（釘定 commit）渲染出內容——`ReaderScreen` 依 `Book.isFixedLayout`（Issue 2 已完成）分派到新的 `FoliateEpubReaderView`（流式）或既有的 `EpubReaderView`（FXL，Readium，完全不修改）。本工單只做「開書渲染出第一頁」，尚無排版設定、換頁、目錄、劃線——這些是 Issue 4-8 的範圍。

**Architecture:** 新增一個獨立、無 Fragment 依賴的原生 `PlatformView`（`FoliateEpubReaderView.kt`，單一 `android.webkit.WebView`，比照 `PdfReaderView.kt` 的簡單生命週期模式，而非 `EpubReaderView.kt` 的 Fragment 掛載模式），透過 `androidx.webkit.WebViewAssetLoader` 提供兩個虛擬 host 路徑：`/assets/`（`readest/foliate-js` 8 個檔案 + `index.html`/`main.js`，內建 asset）與 `/book/`（自訂 `PathHandler`，讀取裝置端任意路徑的 EPUB 檔案本身）。JS→Kotlin 回呼透過 `addJavascriptInterface` 暴露為 `window.FoliateBridge`（不是解析 `console.log`——那是 Issue 1 Spike harness 專屬的證據蒐集手法）。`ReaderScreen` 新增 `isFixedLayout`／`libraryRepository` 兩個可選建構參數，依 `isFixedLayout` 決定分派目標；`null` 時呼叫 Issue 2 的 `LibraryRepository.detectAndCacheEpubLayout()` 一次性判斷；兩者皆未提供時（既有測試呼叫端）退回 Issue 3 之前的既有行為（一律視為 FXL，建構 `EpubReaderView`），零回歸。

**Tech Stack:** Kotlin（`android.webkit.WebView` + `androidx.webkit:webkit:1.16.0`）、Dart/Flutter（`AndroidView`）、`flutter_test`（widget test，mock method channel）、`org.junit`（JVM 單元測試，純 Kotlin 邏輯，比照 `NavZoneHitTester`/`EpubFxlScaler` 既有抽離慣例）、`integration_test`（真機驗證）。

## Global Constraints

- **釘定版本**：`readest/foliate-js` 打包內容一律取自 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（2026-07-19，與 Issue 1 Spike 相同），不得改抓 `main` 最新狀態。只需 8 個檔案（Issue 1 Spike 已用 grep 核對過依賴閉包）：`view.js`、`epub.js`、`epubcfi.js`、`progress.js`、`overlayer.js`、`text-walker.js`、`paginator.js`、`vendor/zip.js`。
- **FXL 完全不受影響**：本工單不修改 `EpubReaderView.kt`（Readium）或 `docs/epics/epic-17-epub-render-migration/spec.md`。
- **`viewType` 固定為** `cc.ugotit.elinkbook/foliate_epub_reader_view`；per-instance method channel 固定為 `cc.ugotit.elinkbook/foliate_epub_reader_view_$id`（`$id` 為 Flutter 內部 view id）。
- **本工單範圍限定的 wire 契約**：`openBook`（參數僅 `path`）／`onPageRendered`／`onError`／`onLayoutResolved`（**恆回傳** `{"isFixedLayout": false, "writingMode": "horizontal"}`——`writingMode` 依書本 CSS 宣告判斷真實值是 Issue 4 的範圍，本工單只是滿足 `EpubLayoutInfo` 型別簽章的非空要求，暫時固定回報橫排，不得自行提前實作 CSS 偵測邏輯）。`setPreferences`／`nextPage`／`previousPage`／`jumpToProgression`／`getTableOfContents`／`jumpToLocator`／`setDecorations`／`onLocatorChanged`／`onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated`／`onZoneAction`／`onZoneTapped` 皆**不在本工單範圍**，不得提前新增（YAGNI，Issue 4-8 依 `spec.md`「介面」節逐一補上）。
- **JS→Kotlin 通訊機制**：透過 `WebView.addJavascriptInterface(bridge, "FoliateBridge")` 暴露 `@JavascriptInterface` 方法，main.js 直接呼叫 `window.FoliateBridge.onPageRendered()`／`onError(message)`。**不得**比照 Issue 1 Spike harness 用 `WebChromeClient.onConsoleMessage()` 解析 `console.log` 字串——那是 throwaway 驗證專用的證據蒐集手法，不是正式功能的通訊機制。`@JavascriptInterface` 方法在 WebView 背景執行緒被呼叫，處理常式必須先 `Handler(Looper.getMainLooper()).post { ... }` 切回主執行緒才能操作 `MethodChannel`。
- **`WebViewAssetLoader` 完全取代 `file://`**（比照 Issue 1 Spike 已驗證機制），不設定 `setAllowFileAccessFromFileURLs`。`.js` 資源需在 `shouldInterceptRequest` 明確覆寫 MIME 類型為 `text/javascript`（`WebViewAssetLoader.AssetsPathHandler` 對副檔名的 MIME 猜測在部分 WebView 版本上不可靠）。
- **不需要新增 `INTERNET` 權限**：`WebViewAssetLoader` 的虛擬 host 請求在 `shouldInterceptRequest` 階段就被攔截，不會發出真正的網路請求；現有 `EpubReaderView`（Readium 內部同樣使用 WebView 渲染本機內容）在完全沒有 `INTERNET` 權限的情況下已確認運作正常，`AndroidManifest.xml` 不需異動。
- **自訂 `PathHandler` 安全要求（審查採納項目，spec.md「待驗證風險」#3）**：`path` 引數若對應真實檔案系統路徑（`Book.filePath` 不含 `"://"`），必須先 `File(path).canonicalFile` 正規化，再驗證是否落在 App 私有文件目錄（`Context.filesDir`，對應 Flutter `path_provider` 的 `getApplicationDocumentsDirectory()`）之內；驗證邏輯抽成獨立、不依賴任何 Android 型別的純 Kotlin 物件 `FoliatePathValidator`（Task 1），供 JVM 單元測試直接驗證。`Book.filePath` 為 `content://` URI 時（`contains("://")`，比照 `EpubReaderView.kt`/`PdfReaderView.kt` 既有啟發式判斷）不做這項檢查——SAF 權限模型本身已管控存取邊界，這是與現有 `EpubReaderView`/`PdfReaderView` 對 `content://` URI 一致的既有信任層級。
- **PathHandler 不需要支援 HTTP Range 請求**（已直接查證解決 spec.md「待驗證風險」#3 的疑慮，非臆測）：已下載釘定 commit 的 `view.js` 原始碼確認，`makeBook(url)` 收到字串引數時執行 `await fetch(url)` 後 `await res.blob()`（`view.js` 第 75-78 行），一次性讀取整個回應內容，不會發出分段（Range）請求；`epub.js`/`vendor/zip.js` 內部也未見任何 `HttpReader`/`Range` 相關邏輯。因此自訂 `PathHandler` 只需回傳一次性讀出的完整 `InputStream` 即可，不需要解析 `Range` 標頭或回傳 206 Partial Content。
- **自訂 `PathHandler` 只服務單一固定虛擬檔名**（`"current.epub"`，`/book/` 前綴之後的路徑）：main.js 永遠請求同一個固定字面量 URL（`https://appassets.androidplatform.net/book/current.epub`），不把真實裝置路徑編碼進 URL 交由 WebView 端解析。`handle(path)` 第一道關卡即為「`path` 是否恰好等於這個常數」，不相等一律回傳 `null`——這從根本上排除任何透過 WebView 請求 URL 操弄路徑穿越的可能性（不需要對這個路徑做目錄拼接運算），`FoliatePathValidator` 的檢查則是針對「即將提供給這個固定虛擬檔名的實際檔案來源」（`Book.filePath`，Dart 端已存在的信任狀態）的第二層防禦。
- **`FoliateEpubReaderView.kt` 是與 `EpubReaderView.kt` 完全獨立、無共用程式碼的原生實作**（ADR 0011 決策，`spec.md`「已知限制」已載明）。
- **`ReaderScreen` 新增的 `isFixedLayout`／`libraryRepository` 皆為可選具名參數**（比照 `bookmarksRepository` 等既有欄位慣例）：兩者皆未提供時，`ReaderScreen` 必須維持 Issue 3 之前的既有行為——EPUB 一律建構 `EpubReaderView`（Readium），**不得**改變任何既有測試（`app/test/screens/reader_screen_test.dart`／`app/test/screens/library_screen_test.dart`）的既有斷言結果。
- **本工單不觸及 TOC／劃線備註／書籤功能**：`FoliateEpubReaderView` 路徑觸發 `onLayoutResolved` 時，**刻意不**呼叫既有 `_handleLayoutResolved` 內的 `EpubReaderView.loadTableOfContents()`／`_reloadAnnotationsAndRefreshDecorations()`／`_loadFxlBookmarks()`（那些呼叫對尚未掛載的 `EpubReaderView`/`_epubReaderViewKey` 雖然會靜默 no-op、技術上無害，但會讓 `_tocLoaded`/`_annotationsLoaded` 被誤判為「已完成」，使「目錄」/「筆記」按鈕看似可用卻永遠開出空清單/無法互動——這是本工單刻意避免的半殘體驗）。新增獨立的 `_handleFoliateLayoutResolved()` 只設定 `_isFixedLayout`（恆為 `false`），不設定 `_autoDetectedWritingMode`／`_tocLoaded`／`_annotationsLoaded`，讓「版面設定」/「目錄」/「筆記」按鈕維持停用狀態，直到 Issue 4/6/8 依序補上對應支援。
- **測試裝置**：沿用既有測試裝置（`3CEF42ECD491687`，Android 15/API 35）；執行前以 `adb devices -l` 重新確認裝置仍在。
- **執行環境**：所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash/MSYS2）執行，非 PowerShell／`cmd.exe`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt` | 新增 | 純 Kotlin 路徑安全檢查（JVM 可測） |
| `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt` | 新增 | 上述純邏輯的 JVM 單元測試 |
| `app/android/app/src/main/assets/foliate/{view.js,epub.js,epubcfi.js,progress.js,overlayer.js,text-walker.js,paginator.js,vendor/zip.js}` | 新增（下載，釘定 commit） | `readest/foliate-js` 依賴閉包 |
| `app/android/app/src/main/assets/foliate/index.html` | 新增 | Production 載入頁（`<foliate-view>` + `main.js`） |
| `app/android/app/src/main/assets/foliate/main.js` | 新增 | Production 開書腳本（`makeBook`／`view.open`／`view.init`／`FoliateBridge` 回呼／錯誤處理） |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` | 新增 | `PlatformView` 實作（`WebView` + `WebViewAssetLoader` + 自訂 `PathHandler` + `FoliateBridge`） |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt` | 新增 | `PlatformViewFactory`，比照 `PdfReaderViewFactory.kt` |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` | 修改 | 新增 `viewType` 註冊 |
| `app/android/app/build.gradle.kts` | 修改 | 新增 `androidx.webkit:webkit:1.16.0` 依賴 |
| `app/lib/reader/foliate_epub_reader_view.dart` | 新增 | Flutter widget（`filePath`／`onPageRendered`／`onError`／`onLayoutResolved`） |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 新增 | 上述 widget 的 widget test（mock method channel） |
| `app/lib/screens/reader_screen.dart` | 修改 | 新增 `isFixedLayout`／`libraryRepository` 建構參數與分派邏輯 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增分派邏輯的 widget test |
| `app/lib/screens/library_screen.dart` | 修改 | `_openBook()` 貫穿 `isFixedLayout`／`libraryRepository` |
| `app/test/screens/library_screen_test.dart` | 修改 | 新增貫穿驗證測試 |
| `app/integration_test/foliate_epub_reader_view_test.dart` | 新增 | 真機驗證：開書成功、開啟不存在檔案觸發 `onError`、`PathHandler` 路徑穿越防護 |
| `app/integration_test/library_screen_test.dart` | 修改 | 真機驗證：真實匯入流式 EPUB → `FoliateEpubReaderView` 渲染成功；既有 FXL 書籍仍走 `EpubReaderView` |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改 | Issue 3 完成說明 |

---

### Task 1: `FoliatePathValidator.kt`——純 Kotlin 路徑安全檢查

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt`

**Interfaces:**
- Consumes: 無（起始工單，無依賴）。
- Produces: `FoliatePathValidator.isPathWithinRoot(requestedCanonicalPath: String, allowedRootCanonicalPath: String): Boolean`。Task 3 的 `FoliateEpubReaderView.kt` 依賴這個函式簽章。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt` 寫入：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliatePathValidatorTest {

    private val allowedRoot = "/data/user/0/cc.ugotit.elinkbook/files"

    @Test
    fun `合法路徑——請求路徑就是允許根目錄本身`() {
        assertTrue(FoliatePathValidator.isPathWithinRoot(allowedRoot, allowedRoot))
    }

    @Test
    fun `合法路徑——請求路徑是允許根目錄底下的子路徑`() {
        assertTrue(
            FoliatePathValidator.isPathWithinRoot(
                "$allowedRoot/books/novel.epub",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——已正規化解析後的路徑落在允許根目錄之外（模擬穿越後的結果）`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "/data/user/0/cc.ugotit.elinkbook/other/secret.txt",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——同前綴但其實是完全不同的目錄（純 startsWith 會誤判的邊界情況）`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "${allowedRoot}_evil/secret.txt",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——符號連結指向允許目錄外，模擬 canonicalPath 解析後的絕對路徑`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "/data/user/0/other_app/databases/secrets.db",
                allowedRoot,
            ),
        )
    }
}
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliatePathValidatorTest"
```

預期：編譯失敗（`FoliatePathValidator` 未定義）。

- [ ] **Step 3: 實作 `FoliatePathValidator.kt`**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt` 寫入：

```kotlin
package cc.ugotit.elinkbook

/**
 * 判斷「已正規化」的請求路徑是否真的落在允許根目錄之內（含根目錄本身）。
 * 兩個參數皆須是呼叫端已對真實檔案系統路徑呼叫過 File.canonicalPath 之後
 * 的絕對路徑字串——這裡只做純字串邊界比對，不做任何檔案系統 I/O，因此可
 * 在 JVM 單元測試以純字串案例驗證，不需要真實檔案（見
 * docs/epics/epic-17-epub-render-migration/spec.md「待驗證風險」#3 的安全
 * 要求）。
 *
 * 供 FoliateEpubReaderView.kt 的自訂 WebViewAssetLoader.PathHandler 使用：
 * 開書時把待開啟的 EPUB 檔案系統路徑（[requestedCanonicalPath]）與 App
 * 私有文件目錄（[allowedRootCanonicalPath]，即 Context.filesDir，對應
 * Flutter path_provider 的 getApplicationDocumentsDirectory()）比對，防止
 * WebView 內容（foliate-js 本身或惡意 EPUB 內容）藉由精心構造的請求路徑
 * 讀取允許目錄之外的檔案。
 *
 * 刻意不用單純的 requestedCanonicalPath.startsWith(allowedRootCanonicalPath)
 * ——這會誤判「同前綴但其實是不同目錄」的情況（例如 allowedRoot=
 * "/data/user/0/pkg/files"，requestedPath="/data/user/0/pkg/files_evil/x"
 * 會被單純的 startsWith 誤判為合法，即使 "files_evil" 根本是完全不同的
 * 目錄，只是字串前綴剛好相同）。必須額外要求邊界字元本身也對得上：完全
 * 相等，或者後面緊接著路徑分隔符 "/"。
 */
object FoliatePathValidator {
    fun isPathWithinRoot(
        requestedCanonicalPath: String,
        allowedRootCanonicalPath: String,
    ): Boolean {
        if (requestedCanonicalPath == allowedRootCanonicalPath) return true
        return requestedCanonicalPath.startsWith("$allowedRootCanonicalPath/")
    }
}
```

- [ ] **Step 4: 執行測試確認通過**

```bash
./gradlew.bat :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.FoliatePathValidatorTest"
```

預期：5 個測試全數 PASS。

- [ ] **Step 5: 執行完整 JVM 測試套件確認無回歸**

```bash
./gradlew.bat :app:testDebugUnitTest
```

預期：`BUILD SUCCESSFUL`，既有全部 JVM 測試（88 個，見 Issue 2）不受影響。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt
git commit -m "feat(epic-17): 新增 FoliatePathValidator 純 Kotlin 路徑安全檢查"
```

---

### Task 2: 打包 `readest/foliate-js`（釘定 commit）+ Production `main.js`/`index.html`

**Files:**
- Create（下載，釘定 commit）：`app/android/app/src/main/assets/foliate/{view.js,epub.js,epubcfi.js,progress.js,overlayer.js,text-walker.js,paginator.js,vendor/zip.js}`
- Create: `app/android/app/src/main/assets/foliate/index.html`
- Create: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: 無（本 Task 純資產打包，不依賴 Task 1）。
- Produces: `assets/foliate/index.html`（載入頁）+ `main.js`（呼叫 `window.FoliateBridge.onPageRendered()`／`onError(message)`）。Task 3 的 `FoliateEpubReaderView.kt` 依賴這裡的 `FoliateBridge` 呼叫慣例與虛擬 URL `https://appassets.androidplatform.net/book/current.epub`。

本 Task 無自動化測試（純靜態資源打包 + JS 邏輯，JS 本身不在 `flutter test`/JVM 測試範圍內；正確性由 Task 7 的真機 `integration_test` 驗證，比照 Issue 1 Spike 對 JS 產出的驗證方式）。

- [ ] **Step 1: 下載釘定 commit 的依賴閉包**

```bash
cd "app/android/app/src/main/assets/foliate"
mkdir -p vendor
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
for f in view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js; do
  curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/$f" -o "$f"
done
head -c 60 view.js
echo
wc -l view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js
```

Expected：`head -c 60 view.js` 輸出以 `import * as CFI from './epubcfi.js'` 開頭；`wc -l` 對 8 個檔案皆回報非 0 行數。

- [ ] **Step 2: 撰寫 `index.html`**

在 `app/android/app/src/main/assets/foliate/index.html` 寫入：

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Foliate Reader</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #fff; }
  foliate-view { display: block; width: 100%; height: 100%; }
</style>
</head>
<body>
<foliate-view id="view"></foliate-view>
<script type="module" src="./main.js"></script>
</body>
</html>
```

- [ ] **Step 3: 撰寫 production `main.js`**

在 `app/android/app/src/main/assets/foliate/main.js` 寫入：

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

// FoliateBridge 由原生端 FoliateEpubReaderView.kt 透過
// WebView.addJavascriptInterface() 注入，見該檔案 KDoc 說明——不是
// console.log 解析（那是 Issue 1 Spike harness 專屬手法）。
async function openBook() {
  try {
    const book = await makeBook(
      'https://appassets.androidplatform.net/book/current.epub',
    )
    await view.open(book)
    view.renderer.setAttribute('flow', 'paginated')
    view.addEventListener('relocate', () => {
      window.FoliateBridge.onPageRendered()
    }, { once: true })
    // 見 Issue 1 Spike（plans/plan-issue-1.md Task 2）已驗證的行為：
    // view.open(book) 本身不會導覽到任何 section，必須呼叫 view.init()
    // 才會觸發首次渲染與 relocate 事件；空物件會落入其 else 分支
    // （history.pushState(0); this.next()），固定從第 0 節開始。
    await view.init({})
  } catch (e) {
    window.FoliateBridge.onError(String((e && e.message) || e))
  }
}

openBook()
```

- [ ] **Step 4: 確認 pubspec.yaml 不需要異動**

`app/android/app/src/main/assets/` 底下的檔案由 Gradle 原生建置流程直接打包進 APK，不經過 Flutter `pubspec.yaml` 的 `assets:` 宣告（那是給 Flutter 端 `rootBundle` 讀取的機制，與 Android 原生 `assets/` 目錄是兩條完全獨立的路徑，Issue 1 Spike 的 throwaway harness 與正式 `app/android/app/src/main/assets/fonts/` 既有字型資源皆是此模式）。執行：

```bash
grep -n "assets/foliate" "app/pubspec.yaml"
```

Expected：無輸出（確認不需要、也不應該在這裡新增宣告）。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/assets/foliate/
git commit -m "feat(epic-17): 打包 readest/foliate-js（釘定 commit）與 production main.js/index.html"
```

---

### Task 3: `FoliateEpubReaderView.kt` + `FoliateEpubReaderViewFactory.kt`——原生 `PlatformView`

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Modify: `app/android/app/build.gradle.kts`

**Interfaces:**
- Consumes: Task 1 的 `FoliatePathValidator.isPathWithinRoot()`；Task 2 的 `assets/foliate/index.html`（載入 URL）；`ReaderViewAttachmentTracker.attach()`/`detach()`（既有，音量鍵攔截計數器，見 `ReaderViewAttachmentTracker.kt`）。
- Produces：`viewType` 字串 `"cc.ugotit.elinkbook/foliate_epub_reader_view"`；per-instance method channel `"cc.ugotit.elinkbook/foliate_epub_reader_view_$id"`，支援 `openBook({path})` → `onPageRendered`/`onError`/`onLayoutResolved`。Task 4 的 Dart widget 依賴這組 wire 契約。

**本 Task 無 JVM 單元測試**（比照 Issue 2 `BookMetadataChannel.detectEpubLayout()` 的既定退路）：`WebView`／`WebViewAssetLoader`／`PlatformView` 生命週期本質耦合 Android 框架型別，本專案無 mockk/robolectric，沒有可抽出的純邏輯（路徑安全檢查已抽到 Task 1）。驗收標準是 `compileDebugKotlin` 成功 + 既有 88 個 JVM 測試（含 Task 1 新增的 5 個）不受影響，正式渲染行為由 Task 7 真機 `integration_test` 驗證。

- [ ] **Step 1: `build.gradle.kts` 新增 `androidx.webkit` 依賴**

第 60-72 行的：

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.documentfile:documentfile:1.0.1")

    testImplementation("junit:junit:4.13.2")
}
```

改為（在 `androidx.documentfile` 之後新增一行）：

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.documentfile:documentfile:1.0.1")
    // epic-17-epub-render-migration Issue 3：FoliateEpubReaderView 的
    // WebViewAssetLoader 與自訂 PathHandler，版本比照 Issue 1 Spike harness
    // 已驗證可用的版本，見 plans/plan-issue-1.md Global Constraints。
    implementation("androidx.webkit:webkit:1.16.0")

    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2: 撰寫 `FoliateEpubReaderView.kt`**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt` 寫入：

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

/**
 * 包裝 readest/foliate-js（釘定 commit dd71f2be356563c16a23272686189fcfb45d0b82）
 * 的原生 PlatformView，供流式（reflowable）EPUB 使用（見
 * docs/epics/epic-17-epub-render-migration/spec.md）。固定版面（FXL）EPUB
 * 完全不受影響，繼續使用 EpubReaderView.kt（Readium）。
 *
 * 單一 android.webkit.WebView，透過 WebViewAssetLoader 提供兩組虛擬 host
 * 路徑：`/assets/` 服務 foliate-js 本身（8 個 JS 檔案 + index.html/main.js，
 * app/android/app/src/main/assets/foliate/），`/book/` 服務待開啟的 EPUB
 * 檔案本身（透過自訂 PathHandler，見 [BookPathHandler]）。
 *
 * JS→Kotlin 的回呼透過 addJavascriptInterface 暴露為 window.FoliateBridge
 * （見 [FoliateBridge]），而非解析 console.log（那是 Issue 1 Spike harness
 * 專屬的證據蒐集手法，不適合用在正式功能的通訊機制上）。
 *
 * openBook 只支援本 Issue 明確範圍：filePath／onPageRendered／onError／
 * onLayoutResolved（恆回傳 isFixedLayout: false，writingMode: "horizontal"
 * ——實際依書本 CSS 判斷的邏輯是 Issue 4 的範圍）。setPreferences／
 * nextPage／jumpToProgression／getTableOfContents／setDecorations 等契約
 * 留待 Issue 4-8 依 spec.md「介面」節逐一補上。
 */
class FoliateEpubReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {

    /**
     * 供 [BookPathHandler] 判斷「這次請求是不是在要求目前這本書」的固定虛擬
     * 檔名——WebView 對這個 handler 的請求只可能來自我們自己的 main.js
     * （固定字面量 URL，見 assets/foliate/main.js），不是從書本內容或任何
     * 使用者可影響的字串組出來的，因此用「是否恰好等於這個常數」當作第一道
     * 關卡即可完全阻絕任何路徑穿越嘗試——不需要對這個字面量做目錄拼接。
     */
    private val currentBookRequestPath = "current.epub"

    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/foliate_epub_reader_view_$id")
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 目前待提供給 [BookPathHandler] 的書籍來源；openBook() 成功驗證後才賦值。
     * 兩者恰好一個非 null（見 [openBook] 的 "://" 啟發式判斷，比照
     * EpubReaderView.kt/PdfReaderView.kt 既有慣例）。 */
    private var currentBookFile: File? = null
    private var currentBookUri: Uri? = null

    private var pageReported = false
    private var isDisposed = false

    private val assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
        .addPathHandler("/book/", BookPathHandler())
        .build()

    private val webView: WebView = WebView(context).apply {
        @Suppress("SetJavaScriptEnabled")
        settings.javaScriptEnabled = true
        addJavascriptInterface(FoliateBridge(), "FoliateBridge")
        webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val response = assetLoader.shouldInterceptRequest(request.url) ?: return null
                // 比照 Issue 1 Spike 已驗證的既有機制：WebViewAssetLoader 對
                // .js 副檔名的 MIME 猜測在部分 WebView 版本上不可靠，
                // <script type="module"> 收到非 text/javascript 的 MIME 會
                // 直接拒絕載入（"Expected a JavaScript-or-Wasm module
                // script" 錯誤）。
                if (request.url.path?.endsWith(".js") == true) {
                    return WebResourceResponse(
                        "text/javascript",
                        response.encoding,
                        response.data,
                    )
                }
                return response
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        ReaderViewAttachmentTracker.attach()
    }

    override fun getView(): View = webView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI
     * 字串（見 docs/adr/0002-content-uri-reader-contract.md），比照
     * EpubReaderView.kt/PdfReaderView.kt 既有的 "://" 啟發式判斷。
     *
     * 檔案系統路徑會先正規化（canonicalPath）並驗證是否落在 App 私有文件
     * 目錄之內（[FoliatePathValidator]，見 spec.md 待驗證風險 #3 的安全
     * 要求）——content:// URI 走 Android SAF 權限模型管控，不適用「目錄
     * 邊界」概念，故不做這項檢查，交由 ContentResolver 自身的授權機制
     * 把關（與現有 EpubReaderView/PdfReaderView 對 content:// URI 的既有
     * 信任層級一致）。
     */
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
            val allowedRoot = context.filesDir.canonicalPath
            if (!FoliatePathValidator.isPathWithinRoot(canonicalFile.canonicalPath, allowedRoot)) {
                channel.invokeMethod("onError", "檔案路徑不在允許的目錄範圍內：$path")
                return
            }
            currentBookFile = canonicalFile
        }
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }

    /**
     * 服務 main.js 固定請求的虛擬書籍檔名（見 [currentBookRequestPath]），
     * 把目前 [currentBookFile]／[currentBookUri] 對應的實際內容整份讀出
     * 回傳——readest/foliate-js（釘定 commit）的 view.js makeBook() 對字串
     * URL 引數一律呼叫 fetch(url) 後 res.blob()，一次性讀取整個回應內容，
     * 不會發出 HTTP Range 請求，因此不需要支援分段內容（已直接查證 view.js
     * 原始碼確認，非臆測，見 Global Constraints）。
     */
    private inner class BookPathHandler : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse? {
            if (path != currentBookRequestPath) return null
            val file = currentBookFile
            val uri = currentBookUri
            val stream = when {
                file != null -> FileInputStream(file)
                uri != null -> context.contentResolver.openInputStream(uri) ?: return null
                else -> return null
            }
            return WebResourceResponse("application/epub+zip", null, stream)
        }
    }

    /**
     * JS→Kotlin 橋接（main.js 呼叫 window.FoliateBridge.xxx()）。
     * @JavascriptInterface 方法在 WebView 的背景執行緒被呼叫，必須切回主
     * 執行緒才能安全操作 MethodChannel／觸發 Flutter 端回呼。
     */
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

        @JavascriptInterface
        fun onError(message: String) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onError", message)
            }
        }
    }

    override fun dispose() {
        isDisposed = true
        ReaderViewAttachmentTracker.detach()
        webView.destroy()
    }
}
```

- [ ] **Step 3: 撰寫 `FoliateEpubReaderViewFactory.kt`**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt` 寫入：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class FoliateEpubReaderViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        return FoliateEpubReaderView(context, id, messenger)
    }
}
```

- [ ] **Step 4: `MainActivity.kt` 新增 `viewType` 註冊**

第 103-118 行的：

```kotlin
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/epub_reader_view",
                EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
            BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)
```

改為（在 `epub_reader_view` 註冊之後新增）：

```kotlin
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/epub_reader_view",
                EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/foliate_epub_reader_view",
                FoliateEpubReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
            BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)
```

- [ ] **Step 5: 編譯確認**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`，無編譯錯誤。

- [ ] **Step 6: 執行既有 JVM 測試確認無回歸**

```bash
./gradlew.bat :app:testDebugUnitTest
```

預期：`BUILD SUCCESSFUL`（93 個測試：既有 88 個 + Task 1 新增的 5 個）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/android/app/build.gradle.kts
git commit -m "feat(epic-17): 新增 FoliateEpubReaderView 原生 PlatformView（WebViewAssetLoader + 自訂 PathHandler + FoliateBridge）"
```

---

### Task 4: `app/lib/reader/foliate_epub_reader_view.dart`——Flutter Widget

**Files:**
- Create: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 3 的 wire 契約（`viewType`: `"cc.ugotit.elinkbook/foliate_epub_reader_view"`；per-instance channel: `"cc.ugotit.elinkbook/foliate_epub_reader_view_$id"`；`openBook({path})`／`onPageRendered`／`onError`／`onLayoutResolved`）。
- Produces: `FoliateEpubReaderView({filePath, onPageRendered, onError, onLayoutResolved, key})`。Task 5 的 `ReaderScreen` 依賴這個建構參數簽章。

- [ ] **Step 1: 撰寫失敗測試**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 寫入：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 驅動 [FoliateEpubReaderView] 底層 AndroidView 完成建立流程所需的最小
/// mock，比照 app/test/reader/epub_reader_view_test.dart 既有的
/// _pumpEpubReaderView 模式。
Future<List<MethodCall>> _pumpFoliateEpubReaderView(
  WidgetTester tester,
  FoliateEpubReaderView widget,
) async {
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
      return 0; // textureId
    }
    return null;
  });

  await tester.pumpWidget(MaterialApp(home: widget));
  await tester.pumpAndSettle();
  return instanceCalls;
}

void _noop() {}
void _noopError(String message) {}

void main() {
  testWidgets('_onPlatformViewCreated 呼叫 openBook 並帶入正確的 path',
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
    expect(openBookCall.arguments, {'path': '/tmp/sample.epub'});
  });

  testWidgets('原生端呼叫 onPageRendered 時，觸發 widget.onPageRendered',
      (tester) async {
    var rendered = false;
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
        onPageRendered: () => rendered = true,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
          const MethodCall('onPageRendered')),
      (data) {},
    );

    expect(rendered, isTrue);
  });

  testWidgets('原生端呼叫 onError 時，觸發 widget.onError 並帶入錯誤訊息',
      (tester) async {
    String? errorMessage;
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
        onError: (message) => errorMessage = message,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
          const MethodCall('onError', '找不到檔案')),
      (data) {},
    );

    expect(errorMessage, '找不到檔案');
  });

  testWidgets(
      '原生端呼叫 onLayoutResolved 時，觸發 widget.onLayoutResolved 並正確解析欄位',
      (tester) async {
    EpubLayoutInfo? info;
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
        onLayoutResolved: (value) => info = value,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
        const MethodCall('onLayoutResolved', {
          'isFixedLayout': false,
          'writingMode': 'horizontal',
        }),
      ),
      (data) {},
    );

    expect(info, isNotNull);
    expect(info!.isFixedLayout, isFalse);
    expect(info!.writingMode, WritingMode.horizontal);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

預期：編譯失敗（`package:elinkbook/reader/foliate_epub_reader_view.dart` 不存在）。

- [ ] **Step 3: 實作 `foliate_epub_reader_view.dart`**

在 `app/lib/reader/foliate_epub_reader_view.dart` 寫入：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'writing_mode.dart';

/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Issue（epic-17-epub-render-migration Issue 3）僅實作 [filePath]／
/// [onPageRendered]／[onError]／[onLayoutResolved] 四個建構參數，與既有
/// [EpubReaderView]（Readium，處理固定版面 FXL）刻意保持公開介面對稱
/// （見 docs/epics/epic-17-epub-render-migration/spec.md「介面」節）。
/// 排版設定／換頁／目錄／劃線備註是 Issue 4-8 的範圍，屆時會依對稱模式
/// 逐一補上對應建構參數，本檔案不預先放置尚未使用的參數（YAGNI）。
///
/// [onLayoutResolved] 在本 Issue 範圍內固定回傳
/// `EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal)`
/// ——`isFixedLayout` 恆為 false 是本 widget 的既定契約（呼叫端在建構這個
/// widget 之前就已經確定是流式書，見 ReaderScreen 的分派邏輯）；
/// `writingMode` 依書本 CSS 宣告判斷實際值是 Issue 4 的範圍，本 Issue 只
/// 是滿足既有型別簽章的非空要求，暫時固定回報橫排。
class FoliateEpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
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
    channel.invokeMethod('openBook', {'path': widget.filePath});
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

預期：4 個測試全數 PASS。

- [ ] **Step 5: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-17): 新增 FoliateEpubReaderView Flutter widget"
```

---

### Task 5: `ReaderScreen`——分派邏輯（`isFixedLayout`／`libraryRepository`）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `FoliateEpubReaderView`；Issue 2 的 `LibraryRepository.detectAndCacheEpubLayout(bookId, filePath): Future<bool>`（`app/lib/library/library_repository.dart`）；`FakeLibraryRepository`（`app/test/support/fake_library_repository.dart`，Issue 2 已完成，含 `detectedIsFixedLayout`／`detectAndCacheEpubLayoutCalls`）。
- Produces: `ReaderScreen` 新增建構參數 `isFixedLayout: bool?`／`libraryRepository: LibraryRepository?`（皆為可選）。Task 6 的 `LibraryScreen` 依賴這兩個參數名稱。

- [ ] **Step 1: 在 `reader_screen_test.dart` 新增 import**

在檔案第 1-28 行 import 區塊，於 `import 'package:elinkbook/screens/reader_screen.dart';` 之後新增：

```dart
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import '../support/fake_library_repository.dart';
```

- [ ] **Step 2: 新增失敗測試**

在第 101 行（PDF「⚙️版面」按鈕初始停用測試）之後、第 103 行（既有持久化偏好設定測試）之前插入：

```dart
  testWidgets('isFixedLayout: true 時直接建構 EpubReaderView，不呼叫偵測',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(EpubReaderView), findsOneWidget);
    expect(find.byType(FoliateEpubReaderView), findsNothing);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets('isFixedLayout: false 時直接建構 FoliateEpubReaderView，不呼叫偵測',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    expect(find.byType(EpubReaderView), findsNothing);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets(
      'isFixedLayout: null 且提供 libraryRepository 時，呼叫 detectAndCacheEpubLayout 並依結果建構 FoliateEpubReaderView',
      (tester) async {
    final repository =
        FakeLibraryRepository(detectedIsFixedLayout: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    expect(find.byType(EpubReaderView), findsNothing);
  });

  testWidgets(
      'isFixedLayout: null 且提供 libraryRepository、偵測結果為 FXL 時，建構 EpubReaderView',
      (tester) async {
    final repository = FakeLibraryRepository(detectedIsFixedLayout: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
    expect(find.byType(EpubReaderView), findsOneWidget);
    expect(find.byType(FoliateEpubReaderView), findsNothing);
  });

  testWidgets(
      'isFixedLayout: null 且未提供 libraryRepository 時，退回既有行為建構 EpubReaderView（零回歸）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(EpubReaderView), findsOneWidget);
    expect(find.byType(FoliateEpubReaderView), findsNothing);
  });
```

- [ ] **Step 3: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：新增的 5 個測試中，前 4 個因 `isFixedLayout`／`libraryRepository` 具名參數不存在而編譯失敗；最後一個（零回歸）在編譯修正前無法單獨驗證，修正後應維持通過。

- [ ] **Step 4: 修改 `reader_screen.dart`——新增 import**

第 1-41 行 import 區塊，在 `import '../reader/epub_selection_info.dart';` 之後新增：

```dart
import '../reader/epub_selection_info.dart';
import '../reader/foliate_epub_reader_view.dart';
import '../library/library_repository.dart';
```

- [ ] **Step 5: 新增建構參數**

第 88-103 行的：

```dart
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
  });
```

改為：

```dart
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;

  /// EPUB 是否為固定版面（FXL），對應 `Book.isFixedLayout`（epic-17
  /// Issue 2）。`null` 代表既有書籍尚未判斷過——此時若提供
  /// [libraryRepository]，會一次性呼叫 [LibraryRepository.detectAndCacheEpubLayout]
  /// 判斷並回寫資料庫；若未提供 [libraryRepository]（例如既有測試呼叫端），
  /// 退回 Issue 3 之前的既有行為，一律視為固定版面、建構 [EpubReaderView]
  /// （Readium），零回歸。非 EPUB 格式完全不受此欄位影響。
  final bool? isFixedLayout;

  /// 供 [isFixedLayout] 為 `null` 時呼叫 [LibraryRepository.detectAndCacheEpubLayout]
  /// 使用。刻意為可選參數——比照 [bookmarksRepository] 既有慣例，避免既有
  /// 大量測試呼叫端需要逐一補上這個參數。
  final LibraryRepository? libraryRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.libraryRepository,
  });
```

- [ ] **Step 6: 新增 State 欄位**

第 211-215 行的：

```dart
  final _epubReaderViewKey = GlobalKey<State<EpubReaderView>>();
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;
```

改為：

```dart
  final _epubReaderViewKey = GlobalKey<State<EpubReaderView>>();
  // 用於呼叫 FoliateEpubReaderView 未來（Issue 4-8）新增的強型別 static
  // helper，比照 _epubReaderViewKey 對 EpubReaderView 的既有作法。本 Issue
  // 尚未實際使用，先建立以維持與既有 widget 的對稱慣例。
  final _foliateEpubReaderViewKey = GlobalKey<State<FoliateEpubReaderView>>();
  // 記錄上一次實際套用給系統的螢幕方向，避免在偏好設定頻繁變動時（例如
  // 拖曳滑桿）重複呼叫 SystemChrome.setPreferredOrientations。
  ScreenOrientationSetting? _lastAppliedOrientation;
  // EPUB 引擎分派結果（epic-17-epub-render-migration Issue 3）：true=FXL
  // （EpubReaderView／Readium）、false=流式（FoliateEpubReaderView）、
  // null=尚未解析完成（既有書籍偵測進行中，畫面維持載入中指示器）。與既有
  // _isFixedLayout（Readium/foliate-js 開書後才回報的執行期狀態，驅動 FXL
  // 懸浮控制項/AppBar 顯示邏輯）是兩個不同概念，互不影響——見
  // docs/epics/epic-17-epub-render-migration/spec.md「已知限制」。
  bool? _dispatchedIsFixedLayout;
```

- [ ] **Step 7: `initState()` 新增分派解析邏輯**

第 220-240 行的：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _totalCharacterCount = loaded.totalCharacterCount;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
      _applyScreenOrientation();
    });
  }
```

改為：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    _resolveEpubEngineDispatch();
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _totalCharacterCount = loaded.totalCharacterCount;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
      _applyScreenOrientation();
    });
  }

  /// 解析 EPUB 該用哪個渲染引擎（epic-17-epub-render-migration Issue 3）。
  /// `widget.isFixedLayout` 非 null 時直接採用；為 null（既有書籍尚未
  /// 判斷過）時，若提供 [ReaderScreen.libraryRepository] 則非同步呼叫
  /// `detectAndCacheEpubLayout()` 判斷並回寫資料庫，期間 `_dispatchedIsFixedLayout`
  /// 維持 null（畫面顯示載入中指示器，見 _buildBody 的 gating 條件）；未
  /// 提供時同步退回既有行為（視為 FXL，建構 EpubReaderView），確保既有
  /// 測試呼叫端零回歸。非 EPUB 格式完全不受影響（`_dispatchedIsFixedLayout`
  /// 維持 null 但 `_buildBody` 的 gating 條件只在 format == epub 時才要求
  /// 它非 null）。
  void _resolveEpubEngineDispatch() {
    _dispatchedIsFixedLayout = widget.isFixedLayout;
    if (_dispatchedIsFixedLayout != null) return;
    if (detectBookFormat(widget.filePath) != BookFormat.epub) return;
    final repository = widget.libraryRepository;
    if (repository == null) {
      // 既有測試/呼叫端未提供 libraryRepository 時，退回 Issue 3 之前的
      // 既有行為——一律視為固定版面（EpubReaderView／Readium），零回歸
      // （見 docs/epics/epic-17-epub-render-migration/spec.md「已知限制」）。
      _dispatchedIsFixedLayout = true;
      return;
    }
    repository
        .detectAndCacheEpubLayout(widget.bookId, widget.filePath)
        .then((result) {
      if (!mounted) return;
      setState(() => _dispatchedIsFixedLayout = result);
    });
  }
```

- [ ] **Step 8: 新增 `_handleFoliateLayoutResolved`**

在 `_handleLayoutResolved`（第 681-725 行）之後新增：

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

- [ ] **Step 9: 修改 `_buildBody` 的 gating 條件**

第 1231-1233 行的：

```dart
        return Stack(
          children: [
            if (_resolved != null) _buildNativeView(format, isLandscape),
```

改為：

```dart
        return Stack(
          children: [
            if (_resolved != null &&
                (format != BookFormat.epub || _dispatchedIsFixedLayout != null))
              _buildNativeView(format, isLandscape),
```

- [ ] **Step 10: 修改 `_buildNativeView` 的 EPUB 分支**

第 1420-1456 行的：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          key: _epubReaderViewKey,
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index]),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
          totalCharacterCount: _totalCharacterCount,
          onCharacterCountReady: _handleCharacterCountReady,
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
        );
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
          );
        }
        return EpubReaderView(
          key: _epubReaderViewKey,
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
          onZoneTapped: (index) => _handleZoneAction(resolved.navZoneActions[index]),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
          totalCharacterCount: _totalCharacterCount,
          onCharacterCountReady: _handleCharacterCountReady,
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
        );
```

- [ ] **Step 11: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數 PASS，含既有全部 EPUB/PDF 分派、版面設定按鈕啟用條件等既有測試不受影響。

- [ ] **Step 12: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 13: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-17): ReaderScreen 新增 isFixedLayout/libraryRepository 分派邏輯，接上 FoliateEpubReaderView"
```

---

### Task 6: `LibraryScreen`——貫穿 `isFixedLayout`／`libraryRepository`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `ReaderScreen(isFixedLayout:, libraryRepository:)`；既有 `Book.isFixedLayout`（Issue 2）；`LibraryScreen.repository`（既有 `LibraryRepository` 欄位）。
- Produces: `LibraryScreen._openBook()` 建構 `ReaderScreen` 時正確貫穿 `book.isFixedLayout`／`widget.repository`。本 Task 完成後，Issue 3 的整條資料流（DB → LibraryScreen → ReaderScreen → 渲染引擎分派）完整串接。

- [ ] **Step 1: 在 `library_screen_test.dart` 新增失敗測試**

先修改 `_testBook` helper（第 1236-1255 行），新增 `isFixedLayout` 具名參數：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  bool? isFixedLayout,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: filePath ?? 'content://example/$id.epub',
    source: BookSource.local,
    groupName: groupName,
    isFixedLayout: isFixedLayout,
    createTime: now,
    lastReadTime: now,
  );
}
```

接著在既有的「ReaderScreen 收到的 highlightsRepository／notesRepository 正確貫穿」測試（第 1010-1046 行）之後插入：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 isFixedLayout／libraryRepository 正確貫穿（epic-17-epub-render-migration Issue 3）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView），比照本檔案既有的貫穿驗證測試手法——本
    // 測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
      isFixedLayout: false,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.isFixedLayout, isFalse);
    expect(readerScreen.libraryRepository, same(repository));
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/screens/library_screen_test.dart
```

預期：`readerScreen.isFixedLayout`／`readerScreen.libraryRepository` 兩個 getter 不存在（`ReaderScreen` 尚未——不對，Task 5 已完成這兩個欄位；此處預期失敗原因改為斷言失敗：`readerScreen.isFixedLayout` 為 `null`（未貫穿）、`readerScreen.libraryRepository` 為 `null`（未貫穿），而非編譯錯誤。

- [ ] **Step 3: 修改 `library_screen.dart` 的 `_openBook()`**

第 282-298 行的：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
            ),
          ),
        )
```

改為：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
            ),
          ),
        )
```

- [ ] **Step 4: 執行測試確認通過**

```bash
flutter test test/screens/library_screen_test.dart
```

預期：全數 PASS，含既有全部貫穿驗證測試（`highlightsRepository`／`notesRepository` 等）不受影響。

- [ ] **Step 5: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-17): LibraryScreen 貫穿 isFixedLayout/libraryRepository 給 ReaderScreen"
```

---

### Task 7: 真機驗證——`FoliateEpubReaderView` 直接開書、`onError`、`PathHandler` 路徑穿越防護

**Files:**
- Create: `app/integration_test/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 3（原生實作）+ Task 4（Dart widget）+ Task 1（`FoliatePathValidator`，透過 `openBook` 間接驗證）。
- Produces: 真機驗證證據，供 Task 9 全面驗證彙整；不產生新的程式介面。

- [ ] **Step 1: 確認裝置**

```bash
adb devices -l
```

預期：至少 1 台裝置（沿用既有測試裝置 `3CEF42ECD491687`，Android 15/API 35；若已更換，以實際輸出為準）。

- [ ] **Step 2: 撰寫測試**

在 `app/integration_test/foliate_epub_reader_view_test.dart` 寫入：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// 比照 app/integration_test/epub_reader_view_test.dart 既有的
/// _stageAssetAsFile 手法。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效的流式 EPUB 檔案觸發 onPageRendered', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'foliate_sample.epub');
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
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟不存在的檔案路徑（但落在允許目錄內）觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final tempDir = await getTemporaryDirectory();
    final missingPath =
        '${tempDir.path}/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: missingPath,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse);
    expect(errorMessage, isNotNull);
  });

  testWidgets(
      'PathHandler 路徑穿越防護：開啟允許目錄之外的檔案路徑觸發 onError（不會被當作合法書籍開啟）',
      (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    // /data/local/tmp 是裝置上真實存在、但不屬於本 App 私有文件目錄
    // （Context.filesDir）的路徑，驗證 FoliatePathValidator 的目錄邊界
    // 檢查會在真機上正確擋下這類請求，而不是被 File I/O 意外允許。
    const outsidePath =
        '/data/local/tmp/foliate_path_traversal_probe_should_not_open.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: outsidePath,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(rendered, isFalse,
        reason: 'PathHandler 的目錄邊界檢查應該拒絕這個請求，不應該渲染成功');
    expect(errorMessage, contains('允許的目錄範圍'));
  });
}
```

- [ ] **Step 3: 於真機執行測試**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart -d <device-id>
```

預期：3 個測試全數 PASS。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/foliate_epub_reader_view_test.dart
git commit -m "test(epic-17): 新增 FoliateEpubReaderView 真機整合測試（開書成功／onError／PathHandler 路徑穿越防護）"
```

---

### Task 8: 真機驗證——端到端匯入流式 EPUB、既有 FXL 書籍不受影響

**Files:**
- Modify: `app/integration_test/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 6（`LibraryScreen`／`ReaderScreen` 完整分派鏈）+ 真實 `SqliteLibraryRepository`／`BookImportServiceImpl`（Issue 2 已完成 `extractMetadata` 回傳 `isFixedLayout`）。
- Produces: 端到端驗證證據；不產生新的程式介面。

- [ ] **Step 1: 新增 import**

在 `app/integration_test/library_screen_test.dart` 第 1-14 行 import 區塊，於 `import 'package:elinkbook/screens/library_screen.dart';` 之後新增：

```dart
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
```

- [ ] **Step 2: 新增失敗測試**

在既有測試（第 50-125 行）之後插入：

```dart
  testWidgets(
      '真實匯入一本流式 EPUB 後點開，由 FoliateEpubReaderView 成功渲染出內容',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final dbPath = p.join(
        tempDir.path, 'library_screen_foliate_test_$uniqueSuffix.db');
    final coversDir = Directory(p.join(
        tempDir.path, 'library_screen_foliate_test_covers_$uniqueSuffix'));
    await coversDir.create(recursive: true);
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'library_screen_foliate_test_sample.epub');

    final repository = await SqliteLibraryRepository.open(dbPath);
    final importService =
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);

    addTearDown(() async {
      await repository.close();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();
      if (await coversDir.exists()) await coversDir.delete(recursive: true);
      final sampleFile = File(samplePath);
      if (await sampleFile.exists()) await sampleFile.delete();
    });

    final contentUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    final imported = await importService.importFiles([contentUri!]);
    expect(imported, hasLength(1));
    final importedBook = imported.single;
    // sample.epub 是流式（reflowable）素材，Issue 2 的 extractMetadata 應
    // 已判斷 isFixedLayout 為 false——先核實這個前提，若不成立代表測試素材
    // 或 Issue 2 判斷邏輯有問題，而非本 Issue 的分派邏輯有問題。
    expect(importedBook.isFixedLayout, isFalse,
        reason: 'sample.epub 應為流式素材，isFixedLayout 應由 Issue 2 判斷為 false');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: ReaderPrefsManagerImpl(
            BookReaderPrefsRepository(repository.database),
            ReadingPositionRepository(repository.database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered，但畫面顯示了錯誤');
    expect(find.byType(FoliateEpubReaderView), findsOneWidget,
        reason: '流式 EPUB 應由 FoliateEpubReaderView 渲染');
    expect(find.byType(EpubReaderView), findsNothing);
  });

  testWidgets(
      '真實匯入一本 FXL（固定版面）EPUB 後點開，仍由既有 EpubReaderView（Readium）渲染，不受本 Issue 影響',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final dbPath = p.join(
        tempDir.path, 'library_screen_fxl_test_$uniqueSuffix.db');
    final coversDir = Directory(p.join(
        tempDir.path, 'library_screen_fxl_test_covers_$uniqueSuffix'));
    await coversDir.create(recursive: true);
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub',
        'library_screen_fxl_test_sample.epub');

    final repository = await SqliteLibraryRepository.open(dbPath);
    final importService =
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);

    addTearDown(() async {
      await repository.close();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();
      if (await coversDir.exists()) await coversDir.delete(recursive: true);
      final sampleFile = File(samplePath);
      if (await sampleFile.exists()) await sampleFile.delete();
    });

    final contentUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    final imported = await importService.importFiles([contentUri!]);
    expect(imported, hasLength(1));
    final importedBook = imported.single;
    expect(importedBook.isFixedLayout, isTrue,
        reason: 'sample_fixed_layout.epub 應為 FXL 素材，isFixedLayout 應為 true');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: ReaderPrefsManagerImpl(
            BookReaderPrefsRepository(repository.database),
            ReadingPositionRepository(repository.database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(EpubReaderView), findsOneWidget,
        reason: 'FXL 書籍應維持由既有 EpubReaderView（Readium）渲染，不受本 Issue 影響');
    expect(find.byType(FoliateEpubReaderView), findsNothing);
  });
```

- [ ] **Step 3: 於真機執行測試確認全數通過**

```bash
cd app
flutter test integration_test/library_screen_test.dart -d <device-id>
```

預期：全數 PASS（含既有第一個測試），新增的兩個測試各自驗證流式/FXL 兩條路徑分派正確。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/library_screen_test.dart
git commit -m "test(epic-17): library_screen_test.dart 新增端到端驗證——流式 EPUB 走 FoliateEpubReaderView、FXL 書籍不受影響"
```

---

### Task 9: 全面驗證

**Files:** 無新增/修改檔案（純驗證任務）。

**Interfaces:**
- Consumes: Task 1-8 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [ ] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS，特別留意 `test/screens/reader_screen_test.dart`／`test/screens/library_screen_test.dart` 既有大量測試不受 Task 5/6 的分派邏輯影響。

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

預期：兩者皆 `BUILD SUCCESSFUL`（93 個 JVM 測試：既有 88 個 + Task 1 新增的 5 個）。

- [ ] **Step 4: 於真機執行全部新增的 `integration_test`**

```bash
cd app
flutter test integration_test/foliate_epub_reader_view_test.dart integration_test/library_screen_test.dart -d <device-id>
```

預期：全數 PASS。

- [ ] **Step 5: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-8 修改/新增的檔案，無不相關的暫存產物（`app/android/app/src/main/assets/foliate/` 下的 8 個下載檔案應已正確加入版控，非暫時性素材）。

- [ ] **Step 6: 更新 `issues.md` Issue 3 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 3」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1/2 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-3.md` Task 1-9 完成 `FoliatePathValidator`（路徑安全純邏輯）／`readest/foliate-js` 資產打包＋production `main.js`／`FoliateEpubReaderView.kt`（WebViewAssetLoader + 自訂 PathHandler + FoliateBridge JS 橋接）／`foliate_epub_reader_view.dart`／`ReaderScreen` 分派邏輯（`isFixedLayout`／`libraryRepository`）／`LibraryScreen` 貫穿。`flutter test`／`flutter analyze`／`./gradlew.bat :app:testDebugUnitTest`／真機 `integration_test`（開書成功、`onError`、`PathHandler` 路徑穿越防護、端到端匯入流式 EPUB 與既有 FXL 書籍不受影響）皆通過。排版設定／換頁／目錄／劃線備註留給 Issue 4-8。
```

- [ ] **Step 7: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 3 完成，更新 issues.md 狀態"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 3 逐項對應：
- `FoliateEpubReaderView.kt`/`FoliateEpubReaderViewFactory.kt`（釘定 commit、8 個檔案、`WebViewAssetLoader`）→ Task 2（資產）+ Task 3（原生 PlatformView）。
- 任意裝置路徑 `PathHandler` + 安全要求（正規化檢查、防路徑穿越）→ Task 1（純邏輯 + JVM 測試）+ Task 3（實際串接）。
- `.js` MIME 類型覆寫 → Task 3 Step 2（`shouldInterceptRequest`）。
- `MainActivity.kt` 新增 `viewType` 註冊 → Task 3 Step 4。
- `main.js`（production，`openBook`/`onPageRendered`/`onError`/`onLayoutResolved` 對稱契約）→ Task 2 Step 3。
- `app/lib/reader/foliate_epub_reader_view.dart`（`filePath`/`onPageRendered`/`onError`/`onLayoutResolved`）→ Task 4。
- `ReaderScreen` 分派邏輯（讀取 `isFixedLayout`、null 時呼叫 `detectEpubLayout`/`detectAndCacheEpubLayout`、PDF/TXT 不受影響）→ Task 5。
- 單元測試要求（widget test、`ReaderScreen` widget test、JVM 單元測試）→ Task 4（widget test）、Task 5（`ReaderScreen` widget test）、Task 1（JVM `PathHandler` 正規化檢查邊界案例）。
- 驗收標準（`flutter analyze`／`./gradlew :app:testDebugUnitTest`／真機 `integration_test` 匯入流式 EPUB 成功渲染／既有 FXL 書籍不受影響／路徑穿越防護真機驗證）→ Task 7/8/9。

**Global Constraints 已解決的兩項技術不確定性（皆為直接查證，非臆測）**：
1. `PathHandler` 是否需要支援 HTTP Range 請求——已下載釘定 commit 的 `view.js` 原始碼確認 `makeBook(url)` 對字串引數一律 `fetch(url)` 後 `res.blob()`，`epub.js`/`vendor/zip.js` 無任何 Range/HttpReader 邏輯，故不需要支援分段內容。
2. `Book.filePath` 的實際型態——已核實 `book_import_service_impl.dart` 顯示常態情況下 `filePath` 是持久化授權後的原始 `content://` URI（非複製到 App 私有目錄的檔案路徑），只有 `takePersistableUriPermission` 失敗的退路才會複製到本機——因此 `FoliateEpubReaderView.kt` 必須同時處理 `content://` URI（走 `ContentResolver`，不做目錄邊界檢查）與絕對檔案路徑（走 `FoliatePathValidator` 目錄邊界檢查）兩種情況，比照既有 `EpubReaderView.kt`/`PdfReaderView.kt` 的 `"://"` 啟發式判斷。

**佔位符掃描**：全文無 TBD/待補字樣，所有程式碼步驟皆提供完整可執行內容。

**型別一致性**：`FoliateEpubReaderView`（Dart）的 `filePath`/`onPageRendered`/`onError`/`onLayoutResolved` 與 `ReaderScreen._buildNativeView()` 呼叫端、`foliate_epub_reader_view_test.dart` 三處引用一致；`FoliateEpubReaderView.kt`（Kotlin）的 `viewType`/method channel 命名與 Dart 端 `AndroidView`/`MethodChannel` 建構字串逐字相符；`FoliatePathValidator.isPathWithinRoot()` 簽章在 Task 1（定義+測試）與 Task 3（呼叫端）一致；`ReaderScreen.isFixedLayout`/`libraryRepository` 在 Task 5（定義）、Task 6（`LibraryScreen` 呼叫端）、Task 5/6 測試三處引用一致。

**與既有測試的相容性**：Task 5 的 `_resolveEpubEngineDispatch()` 在 `libraryRepository == null` 時同步賦值 `_dispatchedIsFixedLayout = true`，確保所有既有（未提供 `isFixedLayout`/`libraryRepository`）的 `ReaderScreen`/`LibraryScreen` 測試維持原本「立即建構 `EpubReaderView`」的行為，零回歸——已在 Task 5 Step 11、Task 9 Step 1 明確要求執行完整既有測試套件驗證。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-3.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
