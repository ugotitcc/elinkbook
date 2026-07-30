# Epic 20 Issue 1 — Spike：`readest/foliate-js` 的 `fixed-layout.js` 真機 FXL 漫畫雙頁/RTL/封面獨立顯示驗證 Implementation Plan

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 在真機 Android WebView 上，用一個完全獨立、throwaway 的最小 Android 專案驗證 `readest/foliate-js`（本專案已 production 使用的同一釘定 commit，額外補上目前沒 vendored 的 `fixed-layout.js`）能否正確處理 FXL 漫畫的橫向雙頁排版、RTL 頁序（`3-2, 5-4`）、封面獨立顯示，並依 `design.md` 判準表做出 GO/NO-GO 決策、書面化結論。

**Architecture：** 完全比照 `epic-17` Issue 1 既有 harness 方法論（已驗證 GO、有完整先例可循）：新建獨立 Android 專案（`tmp/epic-20/foliate-fxl-spike-harness/`，不屬於 `app/`，`tmp/` 已在根目錄 `.gitignore` 排除），單一 `Activity` + 單一 `android.webkit.WebView`，透過 `androidx.webkit.WebViewAssetLoader` 把 `readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，與現有 production vendored 版本完全一致）與測試素材 EPUB 都以虛擬 host 提供給 WebView。與 `epic-17` Issue 1 的差異：(1) 額外打包 `fixed-layout.js`（已查證存在於同一 commit）；(2) 測試素材是真機上已知會被誤判為流式的漫畫 EPUB（真實使用者書籍，非版控 fixture，需先從裝置取出）；(3) 驗證目標是雙頁/RTL/封面獨立顯示，非直排分頁穩定性。以 5 個 Task 遞增建置：Task 1 骨架與管線驗證（可直接複製 `epic-17` Issue 1 已驗證版本）；Task 2 打包含 `fixed-layout.js` 的完整依賴閉包＋取得測試素材＋基準開書渲染；Task 3 啟用雙頁模式，觀察 RTL 配對與封面獨立顯示；Task 4（視 Task 3 結果決定是否需要）嘗試注入 `page-spread-center` metadata＋連續翻頁穩定性正式量測；Task 5 彙整報告、判定 GO/NO-GO、更新文件、清理。

**Tech Stack：** Kotlin（`Activity` + `WebView`）、`androidx.webkit:webkit:1.16.0`、Gradle 8.14 / AGP 8.11.1 / Kotlin 2.3.20（比照 `app/android` 既有已驗證版本組合，重用其 Gradle wrapper）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）、`adb`／真機（`3CEF42ECD491687`，Android 15/API 35）。

## Global Constraints

- **Harness 完全獨立、不進版控**：所有檔案位於 `tmp/epic-20/foliate-fxl-spike-harness/`，不建立、不修改 `app/` 下任何檔案。
- **釘定版本**：`readest/foliate-js` 打包內容一律取自 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（與現有 production `app/android/app/src/main/assets/foliate/` 完全一致），不得改抓 `main` 最新狀態。
- **需要 9 個檔案**（既有 8 個 + 本次新增）：`view.js`、`epub.js`、`epubcfi.js`、`progress.js`、`overlayer.js`、`text-walker.js`、`paginator.js`、`vendor/zip.js`、**`fixed-layout.js`**（已查證存在於同一釘定 commit，`fixed-layout.js` 只依賴一個外部 polyfill `construct-style-sheets-polyfill`，`computeSpreadInlineMargins`／`computeSpreadSpineOverlap` 等函式皆在檔案內自足，Task 2 需額外處理這個 polyfill 依賴，見 Task 2 Step 1）。
- **`view.open(book)` 與 `view.init({})` 的兩段式呼叫，比照 `epic-17` Issue 1 已驗證發現**：`view.open(book)` 只會建立 renderer（`this.isFixedLayout = book.rendition?.layout === 'pre-paginated'` 成立時動態 `import('./fixed-layout.js')` 並 `document.createElement('foliate-fxl')`）、掛好事件監聽、呼叫 `renderer.open(book)`，完全不會導覽到任何 section；真正觸發首次渲染與 `relocate` 事件的是 `view.init()`。這是 `View` 類別對兩種 renderer（`foliate-paginator`／`foliate-fxl`）共用的行為，本次直接沿用 `epic-17` Issue 1 已驗證的呼叫順序，不需要重新踩雷發現一次。
- **`foliate-fxl` 自訂元素的 `spread` attribute**（已對照 `fixed-layout.js` 原始碼查證）：`observedAttributes` 包含 `'spread'`，透過 `renderer.setAttribute('spread', 'both')` 強制雙頁模式（`'none'` 為單頁）；未設定時退回書本自己的 `rendition.spread` metadata。
- **RTL 是自動的**（已查證）：`fixed-layout.js` 的 `open(book)` 內 `this.rtl = book.dir === 'rtl'`，直接讀 `book.dir`（`epub.js` 解析 EPUB `page-progression-direction` 得出），不需要 Harness 額外設定或覆寫，與 `epic-17` Issue 1 需要手動注入 `writing-mode` CSS 的直排情境不同。
- **封面獨立顯示依賴書本自己的 `page-spread-center` metadata**（已對照原始碼查證）：`fixed-layout.js` 讀每個 section 的 `pageSpread` 屬性（`epub.js:1091-1095` 已解析 `page-spread-left`/`page-spread-right`/`page-spread-center`），`pageSpread === 'center'` 時該頁獨立成頁。若測試素材本身缺少這個 metadata（很可能——這類 metadata 不完整正是這本書當初被誤判為流式的成因），Task 3 會觀察到「雙頁正常但封面未獨立」的結果，Task 4 視情況嘗試透過 `book.transformTarget` 攔截 OPF／manifest 資料補上這個屬性（比照 `epic-17` Issue 1 用同一機制注入 CSS 覆寫的既有手法）。
- **測試素材非版控 fixture**：沿用的漫畫 EPUB 是真機上真實匯入的使用者書籍（`epic-18` Issue 15/17/18/19 一路使用的同一本），不在 `app/test/fixtures/` 下，需要先從裝置取出（見 Task 2 Step 2）。
- **每次觸發需間隔至少 2 秒**再擷取下一筆證據，避免觸發排隊/覆蓋模糊掉單次觸發的真實結果。
- **觸發機制備援（審查建議，非必要，僅在座標點擊不穩定時採用）**：Task 3/4 預設用 `adb shell input tap` 模擬點擊，比照 `epic-17` Issue 1 已驗證可行的做法。若實測發現座標換算誤差或熱區覆蓋不準確，可在 `main.js` 額外暴露 `window.spikeNext = () => view.next()`／`window.spikePrev = () => view.prev()`，改用 `adb shell am start-activity` 搭配自訂 Intent（需在 `MainActivity.kt` 加一個 `BroadcastReceiver` 呼叫 `webView.evaluateJavascript()`，需要額外 Kotlin 改動）精準觸發——這是 fallback，不是預設路徑，除非真的遇到點擊不準確的問題才需要加這段 Kotlin 改動。
- **Gradle/AGP/Kotlin 版本比照 `app/android`**，直接複製其 Gradle wrapper 檔案重用。`compileSdk`/`targetSdk` 皆設為 35，`minSdk` 24。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `tmp/epic-20/foliate-fxl-spike-harness/settings.gradle.kts`／`build.gradle.kts`／`gradle.properties` | 新增（throwaway） | Gradle 專案設定 |
| `tmp/epic-20/foliate-fxl-spike-harness/gradlew`／`gradlew.bat`／`gradle/wrapper/*` | 新增（複製自 `app/android`，throwaway） | Gradle wrapper |
| `tmp/epic-20/foliate-fxl-spike-harness/app/build.gradle.kts` | 新增（throwaway） | App 模組建置設定 |
| `tmp/epic-20/foliate-fxl-spike-harness/app/src/main/AndroidManifest.xml` | 新增（throwaway） | 單一 Activity 宣告 |
| `tmp/epic-20/foliate-fxl-spike-harness/app/src/main/kotlin/cc/ugotit/foliatefxlspike/MainActivity.kt` | 新增（throwaway） | `WebView` + `WebViewAssetLoader` + console log 橋接（比照 `epic-17` Issue 1 已驗證版本） |
| `tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate/*.js`／`vendor/zip.js`／`fixed-layout.js` | 新增（Task 2 下載） | 釘定 commit 的 `readest/foliate-js` 依賴閉包（9 個檔案） |
| `tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate/index.html`／`main.js` | 新增（Task 2 建立、Task 3 覆寫） | Harness 自寫的載入頁與量測腳本 |
| `tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/<comic>.epub` | 新增（從真機取出） | 重現素材，見 Task 2 Step 2 |
| `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md` | 新增（正式，進版控） | 診斷報告：判準分類、GO/NO-GO 結論 |
| `docs/epics/epic-20-fxl-foliate-migration/design.md` | 修改（正式） | 回填 Spike 結果、GO/NO-GO 決策 |
| `docs/epics/epic-20-fxl-foliate-migration/issues.md` | 修改（正式） | Issue 1 完成說明 |
| `docs/epics/epic-18-reader-device-qa/issues.md` | 修改（正式） | 依結果更新 Issue 20／21 狀態（GO→標記不再執行；NO-GO→恢復依原計畫執行） |
| `docs/epics.md` | 修改（正式） | epic-18／epic-20 兩列摘要同步更新 |

---

### Task 1：建立獨立 Android 專案骨架，驗證 `WebViewAssetLoader` 管線可用

**Files:**
- Create：`tmp/epic-20/foliate-fxl-spike-harness/settings.gradle.kts`、`build.gradle.kts`、`gradle.properties`
- Create（複製）：`tmp/epic-20/foliate-fxl-spike-harness/gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar`、`gradle/wrapper/gradle-wrapper.properties`
- Create：`tmp/epic-20/foliate-fxl-spike-harness/app/build.gradle.kts`
- Create：`tmp/epic-20/foliate-fxl-spike-harness/app/src/main/AndroidManifest.xml`
- Create：`tmp/epic-20/foliate-fxl-spike-harness/app/src/main/kotlin/cc/ugotit/foliatefxlspike/MainActivity.kt`
- Create（暫時內容，Task 2 會覆寫）：`tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate/index.html`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：可建置、安裝、啟動的最小 `WebView` Activity，`WebViewAssetLoader` 已正確攔截 `https://appassets.androidplatform.net/assets/` 底下的請求；本 Task 完成後 `MainActivity.kt` 不再需要修改

- [ ] **Step 1：確認裝置、建立目錄結構**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p tmp/epic-20/foliate-fxl-spike-harness/app/src/main/kotlin/cc/ugotit/foliatefxlspike
mkdir -p tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate
mkdir -p tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books
mkdir -p tmp/epic-20/reviews
git status --short
adb devices -l
```

Expected：`git status --short` 無輸出；`adb devices -l` 列出裝置 `3CEF42ECD491687`（若已更換，以實際輸出為準，後續指令一律以 `<device-id>` 表示）。

- [ ] **Step 2：確認裝置解析度**

```bash
adb -s <device-id> shell wm size
```

Expected：記下實際解析度，供 Task 3/4 觸發座標換算使用。

- [ ] **Step 3：複製主專案已驗證可用的 Gradle wrapper**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/gradlew"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew.bat" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/gradlew.bat"
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/gradle/wrapper"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.jar" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/gradle/wrapper/gradle-wrapper.jar"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.properties" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/gradle/wrapper/gradle-wrapper.properties"
```

- [ ] **Step 4：寫 `settings.gradle.kts`**

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "foliate-fxl-spike-harness"
include(":app")
```

- [ ] **Step 5：寫根目錄 `build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

- [ ] **Step 6：寫 `gradle.properties`**

```properties
org.gradle.jvmargs=-Xmx2048M
android.useAndroidX=true
kotlin.code.style=official
```

- [ ] **Step 7：寫 `app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "cc.ugotit.foliatefxlspike"
    compileSdk = 35

    defaultConfig {
        applicationId = "cc.ugotit.foliatefxlspike"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.16.0")
}
```

- [ ] **Step 8：寫 `AndroidManifest.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="false"
        android:label="Foliate FXL Spike Harness"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="landscape">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
```

（`screenOrientation="landscape"` 而非 `epic-17` Issue 1 的 `"portrait"`——本次驗證目標是橫向雙頁，比照 `epic-18` Issue 15/17/18/19 一路的既有測試慣例，直接鎖定橫向、避免裝置自動旋轉干擾。）

- [ ] **Step 9：寫 `MainActivity.kt`（最終版，本 Task 後不再修改，直接沿用 `epic-17` Issue 1 已驗證版本，僅改 package 名稱）**

```kotlin
package cc.ugotit.foliatefxlspike

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader

class MainActivity : Activity() {

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        val webView = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            settings.javaScriptEnabled = true
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    val response = assetLoader.shouldInterceptRequest(request.url) ?: return null
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
            webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                    Log.i("FOLIATE_FXL_SPIKE", consoleMessage.message())
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }
}
```

- [ ] **Step 10：寫暫時的 `index.html`**

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Foliate FXL Spike</title></head>
<body><h1 id="status">FOLIATE_FXL_SPIKE_HARNESS_OK</h1></body>
</html>
```

- [ ] **Step 11：建置、安裝、啟動，截圖確認管線可用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness"
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatefxlspike/.MainActivity
```

等待約 2 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task1-pipeline.png"
```

Expected：畫面顯示「FOLIATE_FXL_SPIKE_HARNESS_OK」，代表管線正常，Task 2 只需新增/覆寫 `assets/` 底下內容。

---

### Task 2：打包含 `fixed-layout.js` 的完整依賴閉包，取得測試素材，基準開書渲染

**Files:**
- Create（下載，釘定 commit）：`tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate/{view.js,epub.js,epubcfi.js,progress.js,overlayer.js,text-walker.js,paginator.js,fixed-layout.js,vendor/zip.js}`
- Create（從真機取出）：`tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/<comic>.epub`
- Modify（覆寫 Task 1 暫時內容）：`index.html`
- Create：`main.js`

**Interfaces:**
- Consumes：Task 1 已驗證可用的管線
- Produces：可開啟 FXL 漫畫 EPUB 並顯示內容的頁面（此時尚未啟用雙頁，`foliate-fxl` 自訂元素若正確載入應已可單頁顯示圖片內容）

- [ ] **Step 1：下載釘定 commit 的 9 個依賴檔案，並處理 `fixed-layout.js` 的 polyfill import**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/foliate"
mkdir -p vendor
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
for f in view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js fixed-layout.js vendor/zip.js; do
  curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/$f" -o "$f"
done
head -c 60 fixed-layout.js
echo
grep -n "^import" fixed-layout.js
wc -l view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js fixed-layout.js vendor/zip.js
```

Expected：9 個檔案皆非 0 行數；`grep "^import"` 確認 `fixed-layout.js` 的唯一外部 import 是 `'construct-style-sheets-polyfill'`（裸模組名稱，非相對路徑，瀏覽器/WebView 無法直接解析——需要以下處理）。若該 import 存在，用 `sed` 把這一行改為指向本地 no-op 檔案（比照 `readest/foliate-js` 本身作為函式庫被消費時、宿主環境需自行提供這個 polyfill 的慣例；`construct-style-sheets-polyfill` 只在極舊瀏覽器缺乏 `CSSStyleSheet` 建構子時才需要，本專案 `minSdk=24` 對應的 Android System WebView 版本已原生支援，不需要真正的 polyfill 邏輯）：

```bash
echo "// no-op：現代 Android WebView 已原生支援 CSSStyleSheet 建構子，不需要真正 polyfill" > construct-style-sheets-polyfill.js
sed -i "s|^import 'construct-style-sheets-polyfill'|import './construct-style-sheets-polyfill.js'|" fixed-layout.js
grep -n "^import" fixed-layout.js
```

Expected：`fixed-layout.js` 的 import 已改指向本地空檔案。（若真機測試時發現此假設有誤、真的需要功能性 polyfill，記錄於 Spike 報告，正式實作階段再處理。）

- [ ] **Step 2：從真機取出測試用漫畫 EPUB**

沿用 `epic-18` Issue 15/17/18/19 一路使用的同一本已知會被誤判為流式的漫畫 EPUB（已於裝置圖書庫套用「強制 FXL」）。此書是真實使用者匯入的書籍，非版控 fixture，需先取得其檔案：

```bash
adb -s <device-id> shell run-as cc.ugotit.elinkbook ls files/
```

依上一步輸出找到對應書籍檔案（EPUB 匯入後的 App 私有複本路徑，見 ADR 0002），複製出來：

```bash
adb -s <device-id> shell run-as cc.ugotit.elinkbook cat files/<找到的檔名>.epub > \
  "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/comic.epub"
ls -la "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/comic.epub"
```

若 `run-as` 因裝置非 debuggable build 或路徑不符而失敗，改用人工方式：透過裝置檔案總管或本專案既有的「分享」功能，把這本書匯出到電腦後手動複製到上述路徑。

Expected：`comic.epub` 檔案存在且大小合理（非 0 bytes）。

- [ ] **Step 3：覆寫 `index.html`**

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Foliate FXL Spike</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #000; }
  foliate-view { display: block; width: 100%; height: 100%; }
</style>
</head>
<body>
<foliate-view id="view"></foliate-view>
<script type="module" src="./main.js"></script>
</body>
</html>
```

- [ ] **Step 4：寫 `main.js`（基準版本——只開書、記錄 relocate，尚無雙頁/觸發按鈕）**

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('FOLIATE_RELOCATE', {
    index: e.detail.index,
    fraction: e.detail.fraction,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/comic.epub',
  )
  log('FOLIATE_BOOK_META', {
    layout: book.rendition?.layout,
    dir: book.dir,
    spread: book.rendition?.spread,
  })
  await view.open(book)
  log('FOLIATE_IS_FIXED_LAYOUT', { value: view.isFixedLayout })
  // 比照 epic-17 Issue 1 已驗證發現：view.open(book) 本身不導覽到任何 section，
  // 必須呼叫 view.init() 才會觸發首次渲染與 relocate 事件。
  await view.init({})
  log('FOLIATE_OPENED', { ok: true })
}

openBook()
```

- [ ] **Step 5：重新建置、安裝、啟動，截圖與 logcat 確認 FXL 已被正確偵測並渲染**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatefxlspike/.MainActivity
```

等待約 3 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task2-baseline.png"
adb -s <device-id> logcat -d | grep "FOLIATE_FXL_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task2-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task2-logcat.txt"
```

Expected：`FOLIATE_BOOK_META` 顯示 `layout` 為 `"pre-paginated"`（確認這本書的 EPUB metadata 本身有正確宣告 FXL，即使本專案「引擎分派判斷」曾誤判——兩者是不同的判讀機制，見 `epic-18` Issue 16 相關查證）；`FOLIATE_IS_FIXED_LAYOUT {"value":true}`；截圖顯示圖片內容（單頁，尚未啟用雙頁）。若 `layout` 不是 `"pre-paginated"`，記錄下來——這代表這本書連 `epub.js` 自己的 metadata 解析都判斷不出 FXL，需要在 Spike 報告中如實記錄這個邊界情況，不影響其餘驗證項目繼續進行（可考慮先找另一本已知 FXL metadata 完整的漫畫書驗證核心機制，原書的個案問題留待 Architecting 階段一併考慮）。

---

### Task 3：啟用雙頁模式，觀察 RTL 配對與封面獨立顯示

**Files:**
- Modify：`index.html`（加入觸發熱區）
- Modify：`main.js`（設定 `spread` attribute、加入觸發邏輯）

**Interfaces:**
- Consumes：Task 2 基準版本
- Produces：可透過固定座標觸發「上一頁」「下一頁」、雙頁模式已啟用的完整 Harness

- [ ] **Step 1：覆寫 `index.html`，加入左右觸發熱區**

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Foliate FXL Spike</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #000; }
  foliate-view { display: block; width: 100%; height: 100%; }
  #btn-prev, #btn-next {
    position: fixed; top: 0; height: 100%; width: 33%;
    background: transparent; border: none; padding: 0; margin: 0; z-index: 10;
  }
  #btn-prev { left: 0; }
  #btn-next { right: 0; }
</style>
</head>
<body>
<foliate-view id="view"></foliate-view>
<button id="btn-prev" aria-label="prev"></button>
<button id="btn-next" aria-label="next"></button>
<script type="module" src="./main.js"></script>
</body>
</html>
```

- [ ] **Step 2：覆寫 `main.js`，啟用雙頁模式並加入觸發按鈕**

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('FOLIATE_RELOCATE', {
    index: e.detail.index,
    fraction: e.detail.fraction,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/comic.epub',
  )
  log('FOLIATE_BOOK_META', {
    layout: book.rendition?.layout,
    dir: book.dir,
    spread: book.rendition?.spread,
  })
  await view.open(book)
  // 強制雙頁模式（Issue 20/21 一路要驗證的核心行為）。RTL 不需要在這裡設定，
  // fixed-layout.js 的 open(book) 內會自動讀 book.dir === 'rtl'（見 Global
  // Constraints 已查證的原始碼行為）。
  view.renderer.setAttribute('spread', 'both')
  await view.init({})
  log('FOLIATE_OPENED', { ok: true })
}

document.getElementById('btn-prev').addEventListener('click', () => {
  log('FOLIATE_TRIGGER', { direction: 'prev' })
  view.prev()
})
document.getElementById('btn-next').addEventListener('click', () => {
  log('FOLIATE_TRIGGER', { direction: 'next' })
  view.next()
})

openBook()
```

- [ ] **Step 3：重新建置、安裝、啟動，截圖確認雙頁生效**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatefxlspike/.MainActivity
```

等待約 3 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task3-spread-page1.png"
```

Expected：畫面顯示雙頁並排（或若第一頁是封面且書本有正確 `page-spread-center` metadata，可能顯示單頁封面——兩種結果皆需記錄，不預設立場）。

- [ ] **Step 4：連續點擊下一頁 3 次，逐次截圖，觀察頁面配對模式**

```bash
adb -s <device-id> shell input tap <right-x> <mid-y>
```

等待至少 2 秒，擷取截圖，依序存為 `spike1-task3-next-1.png`／`next-2.png`／`next-3.png`（座標依 Task 1 Step 2 記錄的實際解析度換算，右側熱區約在畫面寬度 66%-100% 之間任一點，Y 座標約畫面高度中點）。

- [ ] **Step 5：肉眼比對截圖，記錄配對模式與 RTL 順序**

比對 `spike1-task3-spread-page1.png` → `next-1` → `next-2` → `next-3` 四張截圖：
1. 封面（第一頁）是否獨立顯示，或與第二頁並排？
2. 後續每個跨頁是兩張連續圖片並排嗎（例如 `2,3`／`4,5`）？
3. 若書本是 RTL（`FOLIATE_BOOK_META` 的 `dir` 為 `"rtl"`），畫面右側是否為序號較前的頁面（`[3｜2]` 而非 `[2｜3]`）？

填入「Spike 紀錄」對應小節。若封面未獨立顯示，前往 Task 4 Step 1 嘗試補救；若已獨立顯示，可跳過 Task 4 Step 1，直接進行 Task 4 Step 2 的連續翻頁正式量測。

---

### Task 4：（視 Task 3 結果）嘗試補救封面獨立顯示，並執行連續翻頁正式量測

**Files:**
- Modify（僅在 Task 3 觀察到封面未獨立顯示時執行）：測試素材本身（新增一份修補過的副本，不動原始 `comic.epub`）

**Interfaces:**
- Consumes：Task 3 觀察結果
- Produces：連續翻頁穩定性的正式量測證據；若封面獨立顯示需要補救，記錄補救是否成功

- [ ] **Step 1（條件式）：直接修補 EPUB 檔案本身，補上 `page-spread-center`**

僅在 Task 3 Step 5 觀察到封面未獨立顯示時執行。**審查修正**：原規劃嘗試用 `book.transformTarget` 的 `'data'` 事件攔截 OPF 內容，經對照 `epub.js` 原始碼查證**此路不通**——OPF 是透過私有方法 `#loadXML()` 直接讀取，完全不經過 `transformTarget`（`transformTarget` 只用於後續個別內容項目載入，經由 `Loader` 類別），不是時序問題，是攔截點本身就錯了。改為在組裝 Harness 素材階段直接修補 EPUB 檔案本身（解壓縮 → 修改 OPF XML 文字 → 重新封裝成合法 EPUB zip），不依賴任何執行期 JS 攔截機制。

先找出 OPF 檔案位置與封面對應的 `<itemref>`：

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p tmp/epic-20/epub_patch_work
cd tmp/epic-20/epub_patch_work
unzip -o "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/comic.epub" -d extracted
OPF_PATH=$(grep -oE 'full-path="[^"]+"' extracted/META-INF/container.xml | sed 's/full-path="//;s/"$//')
echo "OPF path: $OPF_PATH"
cat "extracted/$OPF_PATH"
```

肉眼檢視輸出的 OPF 內容，找出 `<spine>` 內第一個 `<itemref idref="...">`（通常對應封面頁），記下其 `idref` 值（下一步 `<COVER_IDREF>` 替換為此實際值）。

用 Python（比 `sed` 更適合處理 XML 屬性插入，避免破壞既有格式）在該 `itemref` 加上 `properties="page-spread-center"`：

```bash
python3 -c "
import re
opf_path = 'extracted/$OPF_PATH'
with open(opf_path, 'r', encoding='utf-8') as f:
    content = f.read()
content_new = re.sub(
    r'(<itemref\s+idref=\"<COVER_IDREF>\"(?!\s+properties))',
    r'\1 properties=\"page-spread-center\"',
    content,
    count=1,
)
assert content_new != content, 'OPF 未被修改，請確認 <COVER_IDREF> 是否為實際 idref 值'
with open(opf_path, 'w', encoding='utf-8') as f:
    f.write(content_new)
print('OPF patched')
"
```

重新封裝成合法 EPUB zip（`mimetype` 必須是第一個項目且不壓縮儲存，否則部分解析器會判定為無效 EPUB）：

```bash
cd extracted
zip -X -0 "../comic_patched.epub" mimetype
zip -rX "../comic_patched.epub" . -x mimetype
cd ..
cp comic_patched.epub "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/foliate-fxl-spike-harness/app/src/main/assets/books/comic_patched.epub"
```

修改 `main.js` 的 `openBook()`，把書本 URL 暫時改指向 `comic_patched.epub`，重新建置安裝，重複 Task 3 Step 3-5 的觀察流程，確認封面是否改為獨立顯示。驗證完成後記錄結果——不論成功與否，皆保留 `main.js` 內修改前後兩個版本的差異記錄於 Spike 報告，供 Architecting 階段參考「修補 metadata 這條路是否可行」。

- [ ] **Step 2：清空 logcat，準備正式量測**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task4-start.png"
```

- [ ] **Step 3：連續 3 次「下一頁」單次觸發，每次間隔至少 2 秒**

```bash
adb -s <device-id> shell input tap <right-x> <mid-y>
```

等待至少 2 秒，擷取截圖，重複 3 次，依序存為 `spike1-task4-next-1.png`～`next-3.png`。

- [ ] **Step 4：連續 3 次「上一頁」單次觸發，每次間隔至少 2 秒**

```bash
adb -s <device-id> shell input tap <left-x> <mid-y>
```

等待至少 2 秒，擷取截圖，重複 3 次，依序存為 `spike1-task4-prev-1.png`～`prev-3.png`。

- [ ] **Step 5：擷取完整 logcat**

```bash
adb -s <device-id> logcat -d | grep "FOLIATE_FXL_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task4-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-20/reviews/spike1-task4-logcat.txt"
```

Expected：6 筆 `FOLIATE_TRIGGER`，每筆之後緊接至少一筆 `FOLIATE_RELOCATE`。肉眼比對 7 張截圖（`start` → `next-1~3` → `prev-1~3`）內容是否連續無跳過/重複（比照 `epic-17` Issue 1 的操作型定義：前後張畫面內容是否銜接）。

---

### Task 5：彙整報告、依判準分類、GO/NO-GO 決策、更新文件、清理

**Files:**
- Create：`docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`
- Modify：`docs/epics/epic-20-fxl-foliate-migration/issues.md`
- Modify：`docs/epics/epic-18-reader-device-qa/issues.md`（依結果更新 Issue 20／21 狀態）
- Modify：`docs/epics.md`

**Interfaces:**
- Consumes：Task 1-4 的截圖與 logcat 證據
- Produces：本 Epic 後續（GO → Architecting／NO-GO → epic-18 Issue 20/21 恢復執行）唯一可依循的正式結論

- [ ] **Step 1：撰寫診斷報告**

於 `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`（比照 `docs/archive/2026-07-24-epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md` 既有格式）撰寫：驗證範圍摘要、Task 1-4 觀察結果（含截圖引用）、`design.md` 判準表逐項結果、封面獨立顯示是否需要補救及補救是否成功、明確 GO/NO-GO 結論。

- [ ] **Step 2：更新 `design.md`「Spike 驗證方法與判準」段落**

補上實際結果摘要。

- [ ] **Step 3：更新 `issues.md` Issue 1 狀態**

- [ ] **Step 4：依 GO/NO-GO 結果更新 `epic-18` `issues.md` Issue 20／21 狀態**

若 GO：兩者 Status 改為「已由 `epic-20` 取代，不再執行；正式實作方向見 `epic-20` Architecting 階段」。
若 NO-GO：兩者 Status 改為「`epic-20` Spike 判定 NO-GO，恢復依原計畫執行」，移除 ⏸️ 暫停標記。

- [ ] **Step 5：更新 `docs/epics.md` epic-18／epic-20 兩列摘要**

- [ ] **Step 6：清理裝置狀態**

```bash
adb -s <device-id> uninstall cc.ugotit.foliatefxlspike
```

- [ ] **Step 7：確認版控狀態乾淨並 Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：只顯示 `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`（新增）、`docs/epics/epic-20-fxl-foliate-migration/design.md`／`issues.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`（皆修改）——`tmp/epic-20/` 底下所有 throwaway 檔案因根目錄 `.gitignore` 的 `tmp/` 規則排除，不會出現。

```bash
git add docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md \
        docs/epics/epic-20-fxl-foliate-migration/design.md \
        docs/epics/epic-20-fxl-foliate-migration/issues.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md
git commit -m "docs(epic-20): Issue 1 spike——foliate-js fixed-layout.js 真機 FXL 漫畫雙頁/RTL/封面獨立顯示驗證與收斂"
```

---

## 相關佐證

- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-1.md`（本計劃的方法論範本）
- `docs/epics/epic-20-fxl-foliate-migration/design.md`「問題陳述」「Spike 驗證方法與判準」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15/17/18/19/20/21（測試素材、暫停狀態）
- `app/android/app/src/main/assets/foliate/view.js:236-263`（`isFixedLayout` 偵測與 `foliate-fxl` 建立邏輯）
- `app/android/app/src/main/assets/foliate/epub.js:1091-1095`（`page-spread-*` metadata 解析）
- Readest `foliate-js` fork（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）：`fixed-layout.js`（`observedAttributes`、`spread`/`pageSpread`/`rtl` 處理邏輯）
- `docs/adr/0002-content-uri-reader-contract.md`（EPUB 匯入後 App 私有複本路徑慣例，供 Task 2 Step 2 取出測試素材參考）
