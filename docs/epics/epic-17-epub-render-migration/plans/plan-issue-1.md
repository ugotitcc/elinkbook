# Epic 17 Issue 1 — Spike：`readest/foliate-js` 真機直排分頁穩定性驗證 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機 Android WebView 上，用一個完全獨立、throwaway 的最小 Android 專案驗證 `readest/foliate-js` 能否穩定處理繁體中文直排（`vertical-rl`）分頁（單次觸發是否恰好推進一頁、內容是否連續無跳過/重複），並依 `design.md` 判準表做出 GO/NO-GO 決策、書面化結論。

**Architecture:** 新建一個獨立 Android 專案（`tmp/epic-17/foliate-spike-harness/`，不屬於 `app/`，`tmp/` 已在根目錄 `.gitignore` 排除），單一 `Activity` + 單一 `android.webkit.WebView`，透過 `androidx.webkit.WebViewAssetLoader` 把 `readest/foliate-js`（釘定 commit）與測試素材 EPUB 都以虛擬 `https://appassets.androidplatform.net/assets/...` origin 提供給 WebView，完全不使用 `file://`（避免同源政策問題）。以 5 個 Task 遞增建置：Task 1 先驗證骨架與 WebViewAssetLoader 管線本身能動；Task 2 載入 EPUB 並渲染（尚無直排覆蓋，預期為預設橫排）；Task 3 加入直排覆蓋 CSS 與可程式化觸發熱區；Task 4 執行正式量測；Task 5 彙整報告、判定 GO/NO-GO、更新文件、清理。全程比照 `epic-7-interaction` Issue 1／Issue 9 spike 先例（真機 `adb shell input tap` 觸發 + `adb logcat` 擷取證據 + 截圖）。

**Tech Stack:** Kotlin（`Activity` + `WebView`）、`androidx.webkit:webkit:1.16.0`（`WebViewAssetLoader`）、Gradle 8.14 / AGP 8.11.1 / Kotlin 2.3.20（比照 `app/android` 既有已驗證版本組合，重用其 Gradle wrapper）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，2026-07-19）、`adb`／真機（沿用 `epic-7-interaction` 既有測試裝置 3CEF42ECD491687，Android 15 / API 35，1600×2400；執行時需以 `adb devices -l` 重新確認是否仍是同一台）。

## Global Constraints

- **Harness 完全獨立、不進版控**：所有檔案位於 `tmp/epic-17/foliate-spike-harness/`（`tmp/` 已在根目錄 `.gitignore` 第 12 行排除），不建立、不修改 `app/` 下任何檔案（design.md 決策 #6）。本計畫執行完成後，此目錄可保留在本機供未來重新驗證，也可直接刪除，皆不影響版控。
- **釘定版本（審查採納項目）**：`readest/foliate-js` 打包內容一律取自 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（2026-07-19，`main` 分支當時最新），不得改抓 `main` 最新狀態，確保結果可重複驗證。
- **只需 8 個檔案**（已用 `grep` 逐一核對這些檔案的 import/動態 import，確認為開啟一本純文字流式 EPUB 並分頁所需的完整依賴閉包，不含 PDF/MOBI/FB2/漫畫/搜尋/TTS 等未使用模組）：`view.js`、`epub.js`、`epubcfi.js`、`progress.js`、`overlayer.js`、`text-walker.js`、`paginator.js`、`vendor/zip.js`。
- **直排覆蓋機制與時序（重要，不可用簡化替代方案）**：測試素材 `issue9_vertical_pagejump.epub` 自帶的 `css/iga-style-horizontal.css` 本身**沒有**在 `body` 層級宣告 `writing-mode`（只對兩個註腳用的 inline 選取器 `span.footnote-no`／`.ref` 加了 `-epub-writing-mode: horizontal-tb !important` 例外，供直排內文中的註腳標記維持橫排——這與本專案既有 App 讓 Readium 從外部注入直排樣式的既有模式一致）。因此直排必須由 Harness 自己從外部注入。**必須透過 `book.transformTarget` 的 `'data'` 事件，在 CSS 資源文字被解析前附加覆蓋規則**（Task 3 Step 2），**不可**改用「監聽 `view` 的 `'load'` 自訂事件、事後對 `e.detail.doc` 插入 `<style>`」的作法——已讀過 `paginator.js` 原始碼確認：每個分頁 iframe 內部有自己的原生 `load` 監聽器（`this.#iframe.addEventListener('load', ...)`），會在**該 iframe 內容載入當下就同步呼叫 `getDirection(doc)`** 決定方向並開始 columnize；`view` 對外派發的自訂 `'load'` 事件是在這之後才發出的，屆時再插入樣式已經來不及影響第一次的方向判定與分欄計算，會讓 Harness 測到的是「注入時序錯誤造成的偽影」而不是 `foliate-js` 真正的直排分頁行為。
- **`view.open()` 兩段式呼叫**：需先呼叫 `view.js` 匯出的 `makeBook(url)` 自行取得 `book` 物件、掛好 `book.transformTarget` 監聽器之後，才呼叫 `view.open(book)`（傳入已建好的物件，不是傳 URL 字串）——若直接對 `view.open(url)` 傳字串，`view` 內部會自己呼叫 `makeBook()`，此時我們沒有機會在任何資源被請求之前掛上監聽器。
- **WebViewAssetLoader 完全取代 `file://`**（審查採納項目，設計審查 Important 項目之一）：`readest/foliate-js` 的 JS 資源與測試 EPUB 皆放在 Android `assets/` 下、經同一個 `WebViewAssetLoader`（虛擬 host `https://appassets.androidplatform.net`）提供給 WebView，不需要、也不設定 `setAllowFileAccessFromFileURLs`。
- **`.js` 資源需強制指定 MIME 類型為 `text/javascript`**：`WebViewAssetLoader.AssetsPathHandler` 對副檔名的 MIME 猜測在部分 WebView 版本上不可靠，`<script type="module">` 若拿到非 `text/javascript`／`application/javascript` 的 MIME 會直接拒絕載入並丟出「Expected a JavaScript-or-Wasm module script」錯誤；`shouldInterceptRequest` 需對 `.js` 路徑明確覆寫 MIME，不依賴猜測（見 Task 1 `MainActivity.kt`）。
- **`console.log` 橋接**：`WebChromeClient.onConsoleMessage()` 覆寫，統一以 `Log.i("FOLIATE_SPIKE", consoleMessage.message())` 轉錄進 Logcat，供 `adb logcat -d | grep FOLIATE_SPIKE` 擷取證據（比照 `epic-7-interaction` Issue 9 spike 用專屬 tag 過濾證據的方法論）。
- **量測基準**：`relocate` 自訂事件的 `event.detail` 含 `cfi`（字串）、`fraction`（0-1 章節內進度）、`index`（章節索引）——比照 `epic-7-interaction` Issue 9 用 `progression`/`position` 前後值量測「單次觸發實際推進量」的方法論，這裡改用 `cfi`/`fraction`/`index` 三者。
- **觸發座標與裝置**：沿用 `epic-7-interaction` 既有測試裝置（3CEF42ECD491687，Android 15/API 35，螢幕 1600×2400）與熱區座標慣例——螢幕右側 `1340 1200`＝下一頁、左側 `266 1200`＝上一頁。執行時必須先用 `adb devices -l` 確認裝置仍在，並用 `adb shell wm size` 重新確認解析度；若非 1600×2400，需按比例換算這兩組座標（例如 X 座標分別約為螢幕寬度的 83.75% 與 16.6%，Y 座標約為螢幕高度的 50%）。
- **每次觸發需間隔至少 2 秒**再擷取下一筆證據，避免觸發排隊/覆蓋模糊掉單次觸發的真實結果（design.md「觸發方法與樣本數」）。
- **只驗證 `vertical-rl` 這個維度**，不比較橫排（design.md 決策 #1／範圍外段落）；`issues.md` Issue 1 驗收標準明訂只需要「直排 × 上一頁」「直排 × 下一頁」兩類觸發，各至少 3+3 次。
- **選擇有正文內容的章節頁面**，避開封面/版權頁（design.md「觸發方法與樣本數」）——`issue9_vertical_pagejump.epub` 的 spine 前段是 `cover.xhtml`／`copyright.xhtml`，需先翻到出現大量連續段落文字的故事內文頁面才開始正式量測（Task 4 Step 1）。
- **Gradle/AGP/Kotlin 版本比照 `app/android`**（Gradle 8.14、AGP 8.11.1、Kotlin 2.3.20），直接複製其 Gradle wrapper 檔案重用，不引入未經此環境驗證過的新版本組合。`compileSdk`/`targetSdk` 皆設為 35（對應測試裝置 Android 15/API 35），`minSdk` 24（比照 `app/android/app/build.gradle.kts` 現況）。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `tmp/epic-17/foliate-spike-harness/settings.gradle.kts` | 新增（throwaway，不進版控） | Gradle 專案設定，只含 `:app` 模組 |
| `tmp/epic-17/foliate-spike-harness/build.gradle.kts` | 新增（throwaway） | 根專案 plugin 版本宣告 |
| `tmp/epic-17/foliate-spike-harness/gradle.properties` | 新增（throwaway） | Gradle/AndroidX 基本設定 |
| `tmp/epic-17/foliate-spike-harness/gradlew`／`gradlew.bat`／`gradle/wrapper/*` | 新增（複製自 `app/android`，throwaway） | Gradle wrapper，重用已驗證版本 |
| `tmp/epic-17/foliate-spike-harness/app/build.gradle.kts` | 新增（throwaway） | App 模組建置設定與相依套件 |
| `tmp/epic-17/foliate-spike-harness/app/src/main/AndroidManifest.xml` | 新增（throwaway） | 單一 Activity 宣告 |
| `tmp/epic-17/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/foliatespike/MainActivity.kt` | 新增（throwaway） | `WebView` + `WebViewAssetLoader` + console log 橋接 |
| `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/*.js`／`vendor/zip.js` | 新增（throwaway，Task 2 下載） | 釘定 commit 的 `readest/foliate-js` 依賴閉包 |
| `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html`／`main.js` | 新增（throwaway，Task 2 建立、Task 3 覆寫） | Harness 自寫的載入頁與量測腳本 |
| `tmp/epic-17/foliate-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub` | 新增（複製自 `app/test/fixtures/`，throwaway） | 重現素材，與 `epic-7-interaction` Issue 9 spike 同一份 |
| `docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md` | 新增（正式，進版控） | 診斷報告：判準分類、GO/NO-GO 結論 |
| `docs/epics/epic-17-epub-render-migration/design.md` | 修改（正式） | 回填 Spike 結果、GO/NO-GO 決策 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改（正式） | Issue 1 完成說明 |

---

### Task 1：建立獨立 Android 專案骨架，驗證 WebViewAssetLoader 管線可用

**Files:**
- Create：`tmp/epic-17/foliate-spike-harness/settings.gradle.kts`、`build.gradle.kts`、`gradle.properties`
- Create（複製）：`tmp/epic-17/foliate-spike-harness/gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar`、`gradle/wrapper/gradle-wrapper.properties`
- Create：`tmp/epic-17/foliate-spike-harness/app/build.gradle.kts`
- Create：`tmp/epic-17/foliate-spike-harness/app/src/main/AndroidManifest.xml`
- Create：`tmp/epic-17/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/foliatespike/MainActivity.kt`
- Create（暫時內容，Task 2 會覆寫）：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：可建置、安裝、啟動的最小 `WebView` Activity，`WebViewAssetLoader` 已正確攔截 `https://appassets.androidplatform.net/assets/` 底下的請求並轉發到 Android `assets/`；`MainActivity.kt` 本 Task 完成後**不再需要修改**，Task 2/3 只新增/覆寫 `assets/foliate/` 底下的檔案即可

- [ ] **Step 1：確認裝置、建立目錄結構**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p tmp/epic-17/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/foliatespike
mkdir -p tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate
mkdir -p tmp/epic-17/foliate-spike-harness/app/src/main/assets/books
mkdir -p tmp/epic-17/reviews
git status --short
adb devices -l
```

Expected：`git status --short` 無輸出（`tmp/` 已被 `.gitignore` 排除，新建目錄不會顯示）；`adb devices -l` 列出至少 1 台裝置，記下 `<device-id>`（預期沿用既有測試裝置 `3CEF42ECD491687`，Android 15/API 35；若已更換，以實際輸出為準，後續指令一律以 `<device-id>` 表示）。

- [ ] **Step 2：確認裝置解析度**

```bash
adb -s <device-id> shell wm size
```

Expected：`Physical size: 1600x2400`（若不同，記錄實際值，Global Constraints 已說明後續座標換算方式）。

- [ ] **Step 3：複製主專案已驗證可用的 Gradle wrapper**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/gradlew"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew.bat" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/gradlew.bat"
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/gradle/wrapper"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.jar" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/gradle/wrapper/gradle-wrapper.jar"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.properties" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/gradle/wrapper/gradle-wrapper.properties"
```

Expected：4 個檔案複製成功，重用 Gradle 8.14（`gradle-wrapper.properties` 內 `distributionUrl` 應為 `gradle-8.14-all.zip`），不需重新下載新版本。

- [ ] **Step 4：寫 `settings.gradle.kts`**

在 `tmp/epic-17/foliate-spike-harness/settings.gradle.kts` 寫入：

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

rootProject.name = "foliate-spike-harness"
include(":app")
```

- [ ] **Step 5：寫根目錄 `build.gradle.kts`**

在 `tmp/epic-17/foliate-spike-harness/build.gradle.kts` 寫入：

```kotlin
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

- [ ] **Step 6：寫 `gradle.properties`**

在 `tmp/epic-17/foliate-spike-harness/gradle.properties` 寫入：

```properties
org.gradle.jvmargs=-Xmx2048M
android.useAndroidX=true
kotlin.code.style=official
```

- [ ] **Step 7：寫 `app/build.gradle.kts`**

在 `tmp/epic-17/foliate-spike-harness/app/build.gradle.kts` 寫入：

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "cc.ugotit.foliatespike"
    compileSdk = 35

    defaultConfig {
        applicationId = "cc.ugotit.foliatespike"
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

在 `tmp/epic-17/foliate-spike-harness/app/src/main/AndroidManifest.xml` 寫入：

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="false"
        android:label="Foliate Spike Harness"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
```

- [ ] **Step 9：寫 `MainActivity.kt`（最終版，本 Task 後不再修改）**

在 `tmp/epic-17/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/foliatespike/MainActivity.kt` 寫入：

```kotlin
package cc.ugotit.foliatespike

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
                    // WebViewAssetLoader 對 .js 副檔名的 MIME 類型猜測在部分 WebView
                    // 版本上不可靠；<script type="module"> 若拿到非 text/javascript
                    // 的 MIME 類型會直接拒絕載入（"Expected a JavaScript-or-Wasm
                    // module script" 錯誤），故針對 .js 明確覆寫，不依賴猜測。
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
                    Log.i("FOLIATE_SPIKE", consoleMessage.message())
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }
}
```

- [ ] **Step 10：寫暫時的 `index.html`（僅供本 Task 驗證管線，Task 2 會覆寫）**

在 `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html` 寫入：

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Foliate Spike</title></head>
<body><h1 id="status">FOLIATE_SPIKE_HARNESS_OK</h1></body>
</html>
```

- [ ] **Step 11：建置、安裝、啟動，截圖確認管線可用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness"
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatespike/.MainActivity
```

等待約 2 秒讓 Activity 啟動，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task1-pipeline.png"
```

Expected：建置成功（`BUILD SUCCESSFUL`）、安裝成功、截圖顯示畫面上有「FOLIATE_SPIKE_HARNESS_OK」文字——代表 Gradle 專案骨架、`WebViewAssetLoader` 攔截、虛擬 host 載入 `assets/foliate/index.html` 整條管線皆正常，Task 2 只需新增/覆寫 `assets/foliate/` 底下內容，不需再碰 Kotlin/Gradle 檔案。

---

### Task 2：打包 `readest/foliate-js`（釘定 commit）與測試素材，載入 EPUB 並渲染（尚無直排覆蓋）

**Files:**
- Create（下載，釘定 commit）：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/{view.js,epub.js,epubcfi.js,progress.js,overlayer.js,text-walker.js,paginator.js,vendor/zip.js}`
- Create（複製）：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub`
- Modify（覆寫 Task 1 暫時內容）：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html`
- Create：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 1 已驗證可用的 `MainActivity.kt`／`WebViewAssetLoader` 管線（本 Task 不修改 Kotlin）
- Produces：可開啟 EPUB 並顯示章節內文的頁面（此時預期為預設橫排——測試素材本身無 `body` 層級 `writing-mode` 宣告，`getDirection()` 讀到的是 CSS 初始值），供 Task 3 疊加直排覆蓋與觸發熱區

- [ ] **Step 1：下載釘定 commit 的 `readest/foliate-js` 依賴閉包**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate"
mkdir -p vendor
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
for f in view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js; do
  curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/$f" -o "$f"
done
head -c 60 view.js
echo
wc -l view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js
```

Expected：`head -c 60 view.js` 輸出以 `import * as CFI from './epubcfi.js'` 開頭（確認抓到的是原始碼而非 GitHub 404 頁面）；`wc -l` 對 8 個檔案皆回報非 0 行數（`paginator.js` 預期約 3500 行、`vendor/zip.js` 為單行高度壓縮的檔案）。

- [ ] **Step 2：複製測試素材**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/issue9_vertical_pagejump.epub" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub"
ls -la "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness/app/src/main/assets/books/"
```

Expected：檔案存在，大小約 303KB（309978 bytes）。

- [ ] **Step 3：覆寫 `index.html`**

把 `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html` 內容改為：

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Foliate Spike</title>
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

- [ ] **Step 4：寫 `main.js`（基準版本——只開書、記錄 relocate，尚無直排覆蓋與觸發按鈕）**

在 `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/main.js` 寫入：

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('FOLIATE_RELOCATE', {
    cfi: e.detail.cfi,
    fraction: e.detail.fraction,
    index: e.detail.index,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/issue9_vertical_pagejump.epub',
  )
  await view.open(book)
  log('FOLIATE_OPENED', { ok: true })
}

openBook()
```

- [ ] **Step 5：重新建置、安裝、啟動，截圖與 logcat 確認 EPUB 已渲染**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatespike/.MainActivity
```

等待約 3 秒讓 EPUB 解析與首頁渲染完成，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task2-baseline.png"
adb -s <device-id> logcat -d | grep "FOLIATE_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task2-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task2-logcat.txt"
```

Expected：截圖顯示可辨識的繁體中文內文文字（預期為橫排，因為尚未加入直排覆蓋）；logcat 內至少有一筆 `FOLIATE_OPENED {"ok":true}` 與至少一筆 `FOLIATE_RELOCATE`（含非空的 `cfi` 字串）。若畫面空白或 logcat 出現 JS 錯誤訊息，先檢查是否為 Global Constraints 提到的 `.js` MIME 類型問題（`MainActivity.kt` 的 `shouldInterceptRequest` 覆寫理應已處理，若仍出現「Expected a JavaScript-or-Wasm module script」錯誤，需重新檢查該覆寫邏輯是否確實生效）。

---

### Task 3：加入直排覆蓋 CSS、上一頁/下一頁觸發熱區

**Files:**
- Modify：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html`
- Modify：`tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 2 的基準版本（開書、`relocate` 記錄）
- Produces：可透過固定座標點擊觸發「上一頁」「下一頁」、內容已強制直排、每次觸發與位置變化皆記錄到 Logcat 的完整 Harness，供 Task 4 正式量測直接使用，本 Task 後不再修改任何檔案

- [ ] **Step 1：覆寫 `index.html`，加入左右兩個透明觸發熱區**

把 `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/index.html` 內容改為：

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Foliate Spike</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #fff; }
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

- [ ] **Step 2：覆寫 `main.js`，加入 `transformTarget` 直排覆蓋與觸發按鈕**

把 `tmp/epic-17/foliate-spike-harness/app/src/main/assets/foliate/main.js` 內容改為：

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('FOLIATE_RELOCATE', {
    cfi: e.detail.cfi,
    fraction: e.detail.fraction,
    index: e.detail.index,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/issue9_vertical_pagejump.epub',
  )
  // 測試素材本身的 CSS（iga-style-horizontal.css）不會在 body 層級宣告
  // writing-mode（只對兩個註腳選取器加了 horizontal-tb 例外），直排必須由
  // Harness 從外部注入。在這裡透過 transformTarget 的 'data' 事件，於每個
  // CSS 資源文字被解析前附加覆蓋規則——比照真正 reading system（Readium）
  // 「由外部覆蓋書本排版方向」的既有做法，且保證在 Paginator 第一次計算
  // 方向/分欄之前就已生效（見 Global Constraints 對時序的說明）。
  book.transformTarget?.addEventListener('data', (e) => {
    if (e.detail.type === 'text/css') {
      e.detail.data = Promise.resolve(e.detail.data).then(
        (css) => `${css}\nhtml, body { writing-mode: vertical-rl !important; }\n`,
      )
    }
  })
  await view.open(book)
  view.renderer.setAttribute('flow', 'paginated')
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

- [ ] **Step 3：重新建置、安裝、啟動，截圖確認直排生效**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.foliatespike/.MainActivity
```

等待約 3 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task3-vertical.png"
```

Expected：截圖顯示文字已改為直排（欄由右至左排列、每欄文字由上至下）。若仍是橫排，先確認 Task 2 Step 4 的 `main.js` 是否被完整覆寫（尤其 `book.transformTarget` 那段），而非殘留舊版本。

- [ ] **Step 4：單次點擊右側熱區，確認觸發與位置變化皆被記錄**

```bash
adb -s <device-id> shell input tap 1340 1200
```

等待至少 2 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task3-after-tap.png"
adb -s <device-id> logcat -d | grep "FOLIATE_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task3-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task3-logcat.txt"
```

Expected：`spike1-task3-after-tap.png` 內容與 `spike1-task3-vertical.png` 不同（畫面已推進）；logcat 依序出現 `FOLIATE_OPENED`、至少一筆初始 `FOLIATE_RELOCATE`、一筆 `FOLIATE_TRIGGER {"direction":"next"}`、再一筆 `FOLIATE_RELOCATE`（`cfi`/`fraction` 與觸發前不同）。三者皆確認後，Harness 已可直接用於 Task 4 正式量測，本 Task 完成。

---

### Task 4：正式量測——直排 × 上一頁/下一頁，各連續 3 次觸發

**Files:** 無新增異動（沿用 Task 1-3 建好的 Harness）

**Interfaces:**
- Consumes：Task 3 完成的 Harness（觸發熱區、直排覆蓋、Logcat 記錄）
- Produces：6 次觸發（3 次下一頁 + 3 次上一頁）的截圖與 logcat 證據，供 Task 5 分析判定

- [ ] **Step 1：翻到有正文內容的章節頁面（跳過封面/版權頁）**

```bash
adb -s <device-id> logcat -c
```

重複點擊下一頁熱區並每次擷取截圖，肉眼確認畫面內容，直到出現大量連續段落文字（而非書名頁/版權頁的稀疏文字）為止：

```bash
adb -s <device-id> shell input tap 1340 1200
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-skip-1.png"
```

若尚未到達正文，重複上述兩行指令（依序存為 `spike1-task4-skip-2.png`、`spike1-task4-skip-3.png`……），每次間隔至少 2 秒，直到確認到達正文頁面為止，記錄下總共點擊了幾次（供 Task 5 報告引用）。

- [ ] **Step 2：清空 logcat，擷取正式量測起點截圖**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-start.png"
```

- [ ] **Step 3：連續 3 次「下一頁」單次觸發，每次間隔至少 2 秒**

```bash
adb -s <device-id> shell input tap 1340 1200
```

等待至少 2 秒：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-next-1.png"
```

重複「點擊 `1340 1200` → 等待 2 秒 → 截圖」2 次，依序存為 `spike1-task4-next-2.png`、`spike1-task4-next-3.png`。

- [ ] **Step 4：連續 3 次「上一頁」單次觸發，每次間隔至少 2 秒**

```bash
adb -s <device-id> shell input tap 266 1200
```

等待至少 2 秒：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-prev-1.png"
```

重複「點擊 `266 1200` → 等待 2 秒 → 截圖」2 次，依序存為 `spike1-task4-prev-2.png`、`spike1-task4-prev-3.png`。

- [ ] **Step 5：擷取本 Task 完整 logcat**

```bash
adb -s <device-id> logcat -d | grep "FOLIATE_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike1-task4-logcat.txt"
```

Expected：logcat 內恰好 6 筆 `FOLIATE_TRIGGER`（3 次 `next` + 3 次 `prev`，依實際點擊順序交錯），每筆 `FOLIATE_TRIGGER` 之後緊接著至少一筆 `FOLIATE_RELOCATE`。肉眼比對 `spike1-task4-start.png` → `next-1` → `next-2` → `next-3` → `prev-1` → `prev-2` → `prev-3` 七張截圖的文字內容是否前後銜接（操作型定義：前一張最後一字/詞是否與後一張第一字/詞無縫銜接），並記錄每筆 `FOLIATE_RELOCATE` 的 `cfi`/`fraction`/`index` 前後變化量——這是 Task 5 判定的核心數據，本 Task 只負責收集，不做判定。

---

### Task 5：彙整報告、依判準分類、GO/NO-GO 決策、更新文件、清理

**Files:**
- Create：`docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md`
- Modify：`docs/epics/epic-17-epub-render-migration/design.md`
- Modify：`docs/epics/epic-17-epub-render-migration/issues.md`

**Interfaces:**
- Consumes：Task 4 的截圖與 logcat 證據
- Produces：本 epic 後續（GO → Architecting／NO-GO → 歸檔）唯一可依循的正式結論

- [ ] **Step 1：撰寫診斷報告**

在 `docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md` 寫入以下結構（依 Task 1-4 的實際觀察結果填入，不得照抄本範本的佔位文字）：

```markdown
# Epic 17 Issue 1 — Spike：readest/foliate-js 真機直排分頁穩定性驗證報告

**驗證日期：** <實際日期>
**驗證裝置：** <實際 adb devices -l 輸出，含 Android 版本/API/解析度>
**釘定 commit：** dd71f2be356563c16a23272686189fcfb45d0b82（2026-07-19）
**測試素材：** app/test/fixtures/issue9_vertical_pagejump.epub（與 epic-7-interaction Issue 9 spike 同一份）

## Harness 管線驗證（Task 1-3）

<簡述 Task 1 WebViewAssetLoader 管線、Task 2 EPUB 渲染基準、Task 3 直排覆蓋與觸發熱區三項是否皆如預期運作，引用對應截圖檔名>

## 正式量測（Task 4）

<起點章節位置說明（跳過封面/版權頁點擊了幾次）>

### 下一頁 × 3 次
<每次觸發的 cfi/fraction/index 前後變化量，截圖內容是否連續銜接，逐次列出>

### 上一頁 × 3 次
<同上>

## 判準分類

**結果分類：** <通過 / 計數器層級抖動（不算失敗） / 失敗>（依 design.md「判準」表定義）
**依據：** <具體引用哪幾筆截圖/logcat 記錄支持這個分類>

## GO / NO-GO 決策

**結論：** <GO / NO-GO>
<依 design.md「GO / NO-GO 決策路徑」段落，說明下一步（GO→Architecting；NO-GO→記錄理由並歸檔）>
```

- [ ] **Step 2：更新 `design.md`**

在 `docs/epics/epic-17-epub-render-migration/design.md` 的「GO / NO-GO 決策路徑」段落開頭，補上一句總結（依實際結論二擇一）：

若 GO：

```markdown
> **Spike 結果（<日期>）：GO**——完整證據見 `reviews/spike-foliate-js-vertical.md`。下一步進入 Architecting 階段，撰寫 `spec.md`。
```

若 NO-GO：

```markdown
> **Spike 結果（<日期>）：NO-GO**——完整證據見 `reviews/spike-foliate-js-vertical.md`。已評估並否決本次 EPUB 渲染引擎遷移，ADR 0001 維持現狀不變，本 Epic 標記完成並歸檔。
```

- [ ] **Step 3：更新 `issues.md`**

把 `docs/epics/epic-17-epub-render-migration/issues.md` 中 Issue 1 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，比照 `epic-7-interaction` 既有完成說明風格，內容需涵蓋：判準分類結果、GO/NO-GO 結論、釘定的 commit SHA、引用診斷報告路徑 `reviews/spike-foliate-js-vertical.md`。

- [ ] **Step 4：清理裝置狀態**

```bash
adb -s <device-id> uninstall cc.ugotit.foliatespike
```

Expected：`Success`。

- [ ] **Step 5：確認版控狀態乾淨**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：只顯示 `docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md`（新增）、`design.md`（修改）、`issues.md`（修改）三個檔案的異動；`tmp/epic-17/foliate-spike-harness/` 與 `tmp/epic-17/reviews/` 底下的所有 throwaway 檔案（Harness 專案、截圖、logcat）皆不出現，因已被根目錄 `.gitignore` 的 `tmp/` 規則排除，不需手動清理即不會進版控——可保留於本機供未來重新驗證，或直接刪除，皆可。

- [ ] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md
git add docs/epics/epic-17-epub-render-migration/design.md
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 1 spike——readest/foliate-js 真機直排分頁穩定性驗證與收斂"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 1 逐項對應：
- Harness 建置（含 CORS/asset 設定、釘定 commit）→ Task 1（`WebViewAssetLoader`／MIME 覆寫）＋ Task 2 Step 1（釘定 commit 下載）
- 4 種組合中實際只需要「直排 × 上一頁」「直排 × 下一頁」→ Task 4（各 3 次）
- 操作型定義「前後字/詞是否無縫銜接」→ Task 4 Step 5 判讀說明、Task 5 報告範本
- 判準表分類與 GO/NO-GO → Task 5 Step 1/2
- Harness 打包的 commit SHA 記錄於報告 → Task 5 Step 1 範本已含欄位
- 暫時性素材已清理、`git status` 乾淨 → Task 5 Step 4/5

**與 `design.md` 審查修訂的對應**（本次修訂已採納的 4 項意見）：
- WebView CORS/Asset 載入防護 → Task 1 `MainActivity.kt`（`WebViewAssetLoader` 完全取代 `file://`）
- 釘定 commit SHA → Task 2 Step 1（`dd71f2be356563c16a23272686189fcfb45d0b82`）
- 內容連續性判定操作化 → Task 4 Step 5、Task 5 報告範本皆沿用「前後字/詞無縫銜接」定義
- 硬體加速對照（design.md 已記錄為已知風險、不納入本次 Spike）→ 本計畫未新增對應 Task，與 `design.md`「已知風險」段落一致，不擴大範圍

**佔位符掃描**：全文無 TBD/待補字樣；Task 5 Step 1 報告範本的「<記錄...>」是驗證結果本質使然（比照 `epic-7-interaction` Issue 1/9 spike plan 對同類段落的既有處理方式），所有涉及程式碼/指令的步驟皆已提供完整可執行內容。

**API 依據來源（非憑空杜撰）**：`makeBook`／`view.open(book)`／`book.transformTarget`／`view.renderer.setAttribute()`／`view.prev()`/`view.next()`／`relocate` 事件的 `cfi`/`fraction`/`index` 欄位，皆直接讀取 `readest/foliate-js` 於釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）當下的 `view.js`／`epub.js`／`paginator.js`／README 原始內容逐一核對得出，非憑印象猜測；測試素材 `issue9_vertical_pagejump.epub` 本身的 CSS 內容（`iga-style-horizontal.css` 不含 `body` 層級 `writing-mode` 宣告）已實際解壓縮檢視確認，並據此排除了「監聽 `load` 事件插入 `<style>`」這個時序上有瑕疵的替代方案。

**型別一致性**：`main.js` 全文的 `view.open(book)`／`view.renderer.setAttribute()`／`view.prev()`/`view.next()`／`e.detail.cfi`/`e.detail.fraction`/`e.detail.index`／`book.transformTarget`/`e.detail.data`/`e.detail.type` 用法在 Task 2（基準版）與 Task 3（最終版）之間一致延續，未中途改名；`MainActivity.kt` 的 `shouldInterceptRequest`/`onConsoleMessage` 在 Task 1 定案後，Task 2/3 皆未再修改 Kotlin 檔案，任務邊界清楚。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-1.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
