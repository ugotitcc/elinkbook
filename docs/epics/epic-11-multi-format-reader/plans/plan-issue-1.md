# Epic 11 Issue 1 — Spike：KF8 (AZW3)／CBZ 開書可行性與 DRM 偵測驗證 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機 Android WebView 上，用一個完全獨立、throwaway 的最小 Android 專案驗證本專案已釘定的 `readest/foliate-js`（commit `dd71f2be356563c16a23272686189fcfb45d0b82`）能否正確開啟並渲染 KF8 (AZW3) 與 CBZ 檔案，驗證 KF8 內容能否與已證實可用的直排 CSS 覆蓋技術正確組合，驗證 CBZ 的頁面排序與 RTL 行為（`comic-book.js` 原始碼查證顯示**沒有**內建自然排序與 RTL 偵測，需由呼叫端另行處理），並驗證 KF8 DRM 位元組偵測邏輯的可行性，依結果做出 GO/NO-GO 決策。

**Architecture:** 新建一個獨立 Android 專案（`tmp/epic-11/foliate-spike-harness/`，不屬於 `app/`，`tmp/` 已在根目錄 `.gitignore` 排除），沿用 `epic-17-epub-render-migration` Issue 1 已驗證可行的 Harness 架構（單一 `Activity` + 單一 `android.webkit.WebView` + `androidx.webkit.WebViewAssetLoader` 虛擬 host）。與 `epic-17` 不同之處：既有 EPUB 所需的 10 個 `foliate-js` 檔案直接從 production `app/android/app/src/main/assets/foliate/` 複製（同一釘定 commit，不需重新下載驗證），只需額外下載本次新增的 3 個檔案（`mobi.js`／`comic-book.js`／`vendor/fflate.js`）。以 6 個 Task 遞增建置：Task 1 骨架＋既有資產複製；Task 2 新增資產＋KF8 真實公版樣本開書驗證；Task 3 KF8 直排覆蓋組合性驗證；Task 4 CBZ 自製樣本頁序與 RTL 驗證；Task 5 DRM 位元組偵測可行性驗證（純 Python，不涉及 Android）；Task 6 彙整報告、GO/NO-GO 決策、更新文件、清理。

**Tech Stack:** Kotlin（`Activity` + `WebView`）、`androidx.webkit:webkit:1.16.0`、Gradle 8.14 / AGP 8.11.1 / Kotlin 2.3.20（比照 `app/android` 既有已驗證版本組合，重用其 Gradle wrapper）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）、Python 3（Task 5 合成測試檔與驗證腳本，stdlib `zipfile`/`struct` 已足夠，不需額外套件）、`adb`／真機（沿用既有測試裝置 `3CEF42ECD491687`，Android 15 / API 35，1600×2400；執行時需以 `adb devices -l` 重新確認是否仍是同一台）。

## Global Constraints

- **Harness 完全獨立、不進版控**：所有檔案位於 `tmp/epic-11/foliate-spike-harness/`（`tmp/` 已在根目錄 `.gitignore` 排除），不建立、不修改 `app/` 下任何檔案（`design.md`「明確排除」）。
- **釘定版本**：`readest/foliate-js` 打包內容一律取自 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，與 production `app/android/app/src/main/assets/foliate/` 現有 10 個檔案同一 commit（已用 GitHub API 查證 `mobi.js`／`comic-book.js`／`fb2.js`／`vendor/fflate.js` 皆存在於此 commit，不需升版）。
- **既有 10 個檔案直接複製、不重新下載**：`epub.js`、`epubcfi.js`、`overlayer.js`、`paginator.js`、`progress.js`、`text-walker.js`、`vendor/zip.js`、`view.js`、`construct-style-sheets-polyfill.js`、`fixed-layout.js` 皆直接從 `app/android/app/src/main/assets/foliate/` 複製，因這些檔案已是 production 驗證過的同一份內容（`epic-17`/`epic-20` 已驗證），本次只需新增 `mobi.js`／`comic-book.js`／`vendor/fflate.js` 三個檔案。**不複製** `index.html`／`main.js`（production 專屬邏輯，本 Harness 自寫獨立版本）。
- **格式自動分派、不需手動判斷**：已讀取 `view.js` 原始碼確認 `makeBook(url)` 對 KF8/MOBI（magic bytes `file.slice(60,68) === 'BOOKMOBI'`）與 CBZ（副檔名/MIME `isCBZ()`）皆全自動偵測分派至 `mobi.js`／`comic-book.js`，Harness `main.js` 呼叫 `makeBook(url)` 即可，不需要自己判斷格式或手動 `import` 對應模組。
- **KF8 直排覆蓋沿用 `epic-17` Issue 1 已驗證技術，時序要求相同**：已讀取 `mobi.js` 原始碼確認 `MOBI` class 有自己獨立的 `transformTarget = new EventTarget()`（與 `epub.js` 同一機制、同一事件形狀），故 Task 3 直接沿用 `epic-17` Issue 1 驗證過的「`book.transformTarget.addEventListener('data', ...)` 於 CSS 資源文字被解析前附加覆蓋規則」技術，**不可**改用「監聽 `load` 事件後插入 `<style>`」（時序過晚，理由同 `epic-17` plan-issue-1.md Global Constraints）。
- **CBZ 排序行為屬查證發現、非既有假設**：已讀取 `comic-book.js` 原始碼確認 `makeComicBook()` 對圖片檔名用 `files.sort()`（JS 預設字典序排序），**沒有**自然排序邏輯——`research/comprehensive_format_expansion_research.md` 提及的「自然排序」並非 `comic-book.js` 內建能力。Task 4 需**同時**驗證零填補與非零填補兩種檔名情境，如實記錄結果（不預設一定會出錯，需真機實測確認）。
- **CBZ RTL 屬查證發現、非既有假設**：已讀取 `comic-book.js` 確認回傳的 `book` 物件**未設定 `book.dir`**；已讀取 `fixed-layout.js` 確認其 RTL 判定完全依賴 `this.rtl = book.dir === 'rtl'`。故 CBZ 檔案本身沒有任何機制能自動判斷是日漫（RTL）還是美漫（LTR），Task 4 驗證的是「呼叫端手動覆寫 `book.dir` 是否能讓 `fixed-layout.js` 正確採用」，這個結論須明確記錄進 Spike 報告供 Architecting 階段設計 UI 覆寫機制參考。
- **DRM 驗證範圍明確界定**：Task 5 只驗證「PDB/MOBI 標頭位元組解析邏輯本身是否正確、穩定」，使用 Python 合成的最小標頭緩衝區（不含任何真實書籍內容、不涉及任何解密行為），**不**取得或使用任何真實受 DRM 保護的檔案（本專案明確排除解 DRM 範圍，合成測試檔本身也不構成任何形式的 DRM 繞過）。
- **`.js` 資源需強制指定 MIME 類型為 `text/javascript`**：沿用 `epic-17` Issue 1 已驗證的 `MainActivity.kt` `shouldInterceptRequest` MIME 覆寫邏輯（原因見該計畫 Global Constraints）。
- **`console.log` 橋接**：`WebChromeClient.onConsoleMessage()` 統一以 `Log.i("MULTIFORMAT_SPIKE", consoleMessage.message())` 轉錄進 Logcat（沿用 `epic-17` 專屬 tag 過濾證據的方法論，改用本 Epic 專屬 tag 避免與其他 Epic 殘留 log 混淆）。
- **鎖定直向**：比照 `epic-17` Issue 1 已驗證的必要修正，`AndroidManifest.xml` 的 `MainActivity` 直接加上 `android:screenOrientation="portrait"`（不需要重新踩一次該坑）。
- **每次觸發需間隔至少 2 秒**再擷取下一筆證據，避免觸發排隊/覆蓋模糊掉單次觸發的真實結果。
- **Gradle/AGP/Kotlin 版本比照 `app/android`**（Gradle 8.14、AGP 8.11.1、Kotlin 2.3.20），直接複製其 Gradle wrapper 檔案重用。`compileSdk`/`targetSdk` 皆設為 35，`minSdk` 24。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`；Task 5 的 Python 區塊為獨立可執行腳本，與 shell 種類無關。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `tmp/epic-11/foliate-spike-harness/settings.gradle.kts`／`build.gradle.kts`／`gradle.properties` | 新增（throwaway） | Gradle 專案設定，比照 `epic-17` Issue 1 |
| `tmp/epic-11/foliate-spike-harness/gradlew`／`gradlew.bat`／`gradle/wrapper/*` | 新增（複製自 `app/android`，throwaway） | Gradle wrapper |
| `tmp/epic-11/foliate-spike-harness/app/build.gradle.kts`／`AndroidManifest.xml` | 新增（throwaway） | App 模組建置設定、單一 Activity 宣告（鎖定直向） |
| `tmp/epic-11/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/multiformatspike/MainActivity.kt` | 新增（throwaway） | `WebView` + `WebViewAssetLoader` + console log 橋接，本 Task 1 後不再修改 |
| `tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate/{既有 10 個檔案}` | 新增（複製自 `app/android`，throwaway） | 既有已驗證的 EPUB 渲染依賴閉包 |
| `tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate/{mobi.js,comic-book.js,vendor/fflate.js}` | 新增（下載，throwaway） | 本次驗證目標 |
| `tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/the-time-machine.azw3` | 新增（下載，throwaway） | 真實 DRM-free 公版 KF8 樣本（Standard Ebooks） |
| `tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/cbz_padded.cbz`／`cbz_unpadded.cbz` | 新增（Python 合成，throwaway） | 自製 CBZ 頁序驗證樣本 |
| `tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate/index.html`／`main.js` | 新增／覆寫（throwaway） | Harness 自寫的載入頁與量測腳本，各 Task 遞增覆寫 |
| `tmp/epic-11/drm-probe/synth_mobi.py` | 新增（throwaway，Task 5） | 合成 PDB/MOBI 標頭緩衝區 + 位元組解析驗證腳本 |
| `docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md` | 新增（正式，進版控） | 診斷報告：判準分類、GO/NO-GO 結論 |
| `docs/epics/epic-11-multi-format-reader/design.md` | 修改（正式） | 回填 Spike 結果 |
| `docs/epics/epic-11-multi-format-reader/issues.md` | 修改（正式） | Issue 1 完成說明 |

---

### Task 1：建立獨立 Android 專案骨架，複製既有已驗證的 10 個 `foliate-js` 檔案

**Files:**
- Create：`tmp/epic-11/foliate-spike-harness/settings.gradle.kts`、`build.gradle.kts`、`gradle.properties`、`app/build.gradle.kts`、`app/src/main/AndroidManifest.xml`、`app/src/main/kotlin/cc/ugotit/multiformatspike/MainActivity.kt`
- Create（複製）：Gradle wrapper 4 檔、`app/src/main/assets/foliate/` 既有 10 個檔案
- Create（暫時內容，Task 2 覆寫）：`app/src/main/assets/foliate/index.html`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：可建置、安裝、啟動的最小 `WebView` Activity，`WebViewAssetLoader` 正確攔截虛擬 host 請求；`MainActivity.kt` 本 Task 完成後不再需要修改

- [ ] **Step 1：確認裝置、建立目錄結構**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p tmp/epic-11/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/multiformatspike
mkdir -p tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate/vendor
mkdir -p tmp/epic-11/foliate-spike-harness/app/src/main/assets/books
mkdir -p tmp/epic-11/reviews
mkdir -p tmp/epic-11/drm-probe
git status --short
adb devices -l
```

Expected：`git status --short` 無輸出（`tmp/` 已排除）；`adb devices -l` 列出至少 1 台裝置，記下 `<device-id>`（預期沿用 `3CEF42ECD491687`；若已更換，以實際輸出為準，後續指令一律以 `<device-id>` 表示）。

- [ ] **Step 2：確認裝置解析度**

```bash
adb -s <device-id> shell wm size
```

Expected：`Physical size: 1600x2400`（若不同，記錄實際值）。

- [ ] **Step 3：複製 Gradle wrapper**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/gradlew"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew.bat" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/gradlew.bat"
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/gradle/wrapper"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.jar" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/gradle/wrapper/gradle-wrapper.jar"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.properties" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/gradle/wrapper/gradle-wrapper.properties"
```

Expected：4 個檔案複製成功。

- [ ] **Step 4：複製既有已驗證的 10 個 `foliate-js` 檔案**

```bash
SRC="U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate"
DST="U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate"
for f in epub.js epubcfi.js overlayer.js paginator.js progress.js text-walker.js view.js construct-style-sheets-polyfill.js fixed-layout.js; do
  cp "$SRC/$f" "$DST/$f"
done
cp "$SRC/vendor/zip.js" "$DST/vendor/zip.js"
ls -la "$DST"
wc -l "$DST"/*.js "$DST"/vendor/*.js
```

Expected：10 個檔案（9 個頂層 + `vendor/zip.js`）皆複製成功，`wc -l` 回報非 0 行數，內容與 production 完全一致（同一份檔案系統複本）。

- [ ] **Step 5：寫 `settings.gradle.kts`**

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

寫入 `tmp/epic-11/foliate-spike-harness/settings.gradle.kts`。

- [ ] **Step 6：寫根目錄 `build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

寫入 `tmp/epic-11/foliate-spike-harness/build.gradle.kts`。

- [ ] **Step 7：寫 `gradle.properties`**

```properties
org.gradle.jvmargs=-Xmx2048M
android.useAndroidX=true
kotlin.code.style=official
```

寫入 `tmp/epic-11/foliate-spike-harness/gradle.properties`。

- [ ] **Step 8：寫 `app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "cc.ugotit.multiformatspike"
    compileSdk = 35

    defaultConfig {
        applicationId = "cc.ugotit.multiformatspike"
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

寫入 `tmp/epic-11/foliate-spike-harness/app/build.gradle.kts`。

- [ ] **Step 9：寫 `AndroidManifest.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="false"
        android:label="Multi-format Spike Harness"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="portrait">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
```

寫入 `tmp/epic-11/foliate-spike-harness/app/src/main/AndroidManifest.xml`。

- [ ] **Step 10：寫 `MainActivity.kt`（最終版，本 Task 後不再修改）**

```kotlin
package cc.ugotit.multiformatspike

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
                    Log.i("MULTIFORMAT_SPIKE", consoleMessage.message())
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }
}
```

寫入 `tmp/epic-11/foliate-spike-harness/app/src/main/kotlin/cc/ugotit/multiformatspike/MainActivity.kt`。

- [ ] **Step 11：寫暫時的 `index.html`**

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Multi-format Spike</title></head>
<body><h1 id="status">MULTIFORMAT_SPIKE_HARNESS_OK</h1></body>
</html>
```

寫入 `tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate/index.html`。

- [ ] **Step 12：建置、安裝、啟動，截圖確認管線可用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

等待約 2 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task1-pipeline.png"
```

Expected：建置成功、安裝成功、截圖顯示「MULTIFORMAT_SPIKE_HARNESS_OK」文字。

---

### Task 2：新增 `mobi.js`／`comic-book.js`／`vendor/fflate.js`，下載真實 KF8 樣本，驗證開書/渲染/導覽

**Files:**
- Create（下載，釘定 commit）：`app/src/main/assets/foliate/mobi.js`、`comic-book.js`、`vendor/fflate.js`
- Create（下載）：`app/src/main/assets/books/the-time-machine.azw3`
- Modify：`app/src/main/assets/foliate/index.html`
- Create：`app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 1 已驗證可用的 `MainActivity.kt`／既有 10 個 `foliate-js` 檔案
- Produces：可開啟真實 KF8 檔案並顯示章節內文的頁面（尚無直排覆蓋），供 Task 3 疊加

- [ ] **Step 1：下載釘定 commit 的新增 3 個檔案**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/foliate"
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/mobi.js" -o mobi.js
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/comic-book.js" -o comic-book.js
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/vendor/fflate.js" -o vendor/fflate.js
wc -l mobi.js comic-book.js vendor/fflate.js
grep -c "export const isMOBI" mobi.js
grep -c "export const makeComicBook" comic-book.js
grep -c "unzlibSync" vendor/fflate.js
```

Expected：三個檔案皆非 0 行數（`mobi.js` 約 1279 行、`comic-book.js` 約 140 行、`vendor/fflate.js` 為單行壓縮檔）；三個 `grep -c` 皆回報 `1`（確認抓到含目標匯出的正確原始碼，非 404 頁面）。

- [ ] **Step 2：下載真實、DRM-free、公版授權 KF8 樣本**

已驗證 Standard Ebooks（`standardebooks.org`，公版文學作品的免費、DRM-free、CC0/公有領域授權電子書專案）提供直接可下載的 AZW3 檔案；下載連結需先觸發一次跳轉頁（`?source=download` 查詢參數）：

```bash
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/books"
curl -sSL -o "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/the-time-machine.azw3" \
  "https://standardebooks.org/ebooks/h-g-wells/the-time-machine/downloads/h-g-wells_the-time-machine.azw3?source=download"
ls -la "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/the-time-machine.azw3"
xxd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/the-time-machine.azw3" | head -5
```

Expected：檔案大小約 545KB（545452 bytes）；`xxd` 輸出開頭為 PDB name 欄位 `The_Time_Machine`（後接零填補），offset `0x3c`（60）起可辨識出 `424f4f4b 4d4f4249`（ASCII `BOOKMOBI`）——這是 `mobi.js` 的 `isMOBI()` 判斷依據，若此處不符代表下載到的不是有效 MOBI/KF8 檔案，需重新檢查下載步驟（例如查詢參數是否被截斷）。

- [ ] **Step 3：覆寫 `index.html`**

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Multi-format Spike</title>
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

寫入 `app/src/main/assets/foliate/index.html`。

- [ ] **Step 4：寫 `main.js`（KF8 基準版本——開書、記錄 relocate、觸發按鈕，尚無直排覆蓋）**

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('SPIKE_RELOCATE', {
    cfi: e.detail.cfi,
    fraction: e.detail.fraction,
    index: e.detail.index,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/the-time-machine.azw3',
  )
  log('SPIKE_BOOK_METADATA', {
    title: book.metadata?.title,
    hasTransformTarget: typeof book.transformTarget === 'object',
  })
  await view.open(book)
  view.renderer.setAttribute('flow', 'paginated')
  await view.init({})
  log('SPIKE_OPENED', { ok: true, isFixedLayout: view.isFixedLayout })
}

document.getElementById('btn-prev').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'prev' })
  view.prev()
})
document.getElementById('btn-next').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'next' })
  view.next()
})

openBook().catch(err => log('SPIKE_ERROR', { message: String(err), stack: err?.stack }))
```

寫入 `app/src/main/assets/foliate/main.js`。**注意**：`makeBook()` 呼叫時**不需要**手動判斷這是 KF8 檔案——`view.js` 內部靠讀取檔案 magic bytes（`file.slice(60,68) === 'BOOKMOBI'`）自動分派至 `mobi.js`，這是本 Task 驗證的核心假設之一（Step 5 的 `SPIKE_OPENED` 若成功出現代表分派邏輯正確運作）。

- [ ] **Step 5：重新建置、安裝、啟動，截圖與 logcat 確認 KF8 已渲染**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

等待約 3 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task2-kf8-baseline.png"
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task2-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task2-logcat.txt"
```

Expected：截圖顯示可辨識的英文小說內文（The Time Machine 正文，橫排）；logcat 依序出現 `SPIKE_BOOK_METADATA`（`title` 含 "Time Machine" 字樣、`hasTransformTarget: true`）、`SPIKE_OPENED {"ok":true,"isFixedLayout":false}`（KF8 為 reflowable，非固定版面）、至少一筆 `SPIKE_RELOCATE`。若出現 `SPIKE_ERROR`，記錄完整錯誤訊息與堆疊，這是本 Issue 的核心失敗訊號之一。

- [ ] **Step 6：連續點擊下一頁 3 次、上一頁 3 次，驗證內容連續無跳過/重複**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> shell input tap 1340 1200
```

等待至少 2 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task2-next-1.png"
```

重複「點擊 `1340 1200` → 等待 2 秒 → 截圖」2 次（`task2-next-2.png`、`task2-next-3.png`），再重複「點擊 `266 1200` → 等待 2 秒 → 截圖」3 次（`task2-prev-1.png`～`task2-prev-3.png`）。

```bash
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task2-nav-logcat.txt"
```

Expected：6 張截圖內容前後銜接（`next-3` 之後緊接 `prev-1` 應與 `next-2` 內容相同或高度相似，因為是原路返回）；logcat 內每次 `SPIKE_TRIGGER` 後緊接一筆 `SPIKE_RELOCATE`，`fraction`/`index` 隨方向正確遞增/遞減。

---

### Task 3：KF8 內容套用直排 CSS 覆蓋，驗證與已證實可用的直排管線正確組合

**Files:**
- Modify：`app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 2 已驗證可開書的 KF8 基準版本
- Produces：確認 `mobi.js` 來源內容能正確套用 `epic-17` Issue 1 已驗證的 `transformTarget` 直排覆蓋技術

**背景說明**：本 Task **不是**重新驗證中文直排排版品質（該品質已由 `epic-17`/`epic-20` 用真實中文書籍證實，且渲染最終都是同一個 `paginator.js`），而是驗證「KF8 解析出的內容 DOM 能否正確流入這條已證實的管線」——用英文樣本套用直排 CSS 覆蓋，驗證的是**組合性**而非**排版品質**。

- [ ] **Step 1：覆寫 `main.js`，加入 `transformTarget` 直排覆蓋**

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('SPIKE_RELOCATE', {
    cfi: e.detail.cfi,
    fraction: e.detail.fraction,
    index: e.detail.index,
  })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/the-time-machine.azw3',
  )
  // 沿用 epic-17 Issue 1 已驗證技術：透過 transformTarget 的 'data' 事件，在
  // CSS 資源文字被解析前附加覆蓋規則。mobi.js 的 MOBI class 有自己獨立的
  // transformTarget = new EventTarget()（與 epub.js 同一機制、同一事件形狀，
  // 見 mobi.js:955,1104），故此技術對 KF8 來源內容同樣適用。
  book.transformTarget?.addEventListener('data', (e) => {
    if (e.detail.type === 'text/css') {
      e.detail.data = Promise.resolve(e.detail.data).then(
        (css) => `${css}\nhtml, body { writing-mode: vertical-rl !important; }\n`,
      )
    }
  })
  await view.open(book)
  view.renderer.setAttribute('flow', 'paginated')
  await view.init({})
  log('SPIKE_OPENED', { ok: true, isFixedLayout: view.isFixedLayout })
}

document.getElementById('btn-prev').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'prev' })
  view.prev()
})
document.getElementById('btn-next').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'next' })
  view.next()
})

openBook().catch(err => log('SPIKE_ERROR', { message: String(err), stack: err?.stack }))
```

寫入 `app/src/main/assets/foliate/main.js`（覆寫 Task 2 版本）。

- [ ] **Step 2：重新建置、安裝、啟動，截圖確認直排生效**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

等待約 3 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task3-kf8-vertical.png"
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task3-logcat.txt"
```

Expected：截圖顯示文字已改為直排（欄由右至左排列、每欄文字由上至下），與 Task 2 的橫排截圖形成明確對照；logcat 正常出現 `SPIKE_OPENED`／`SPIKE_RELOCATE`，無 `SPIKE_ERROR`。若仍是橫排或出現錯誤，記錄具體現象——這代表 KF8 內容與既有直排管線的組合性有問題，是 NO-GO 的重要依據之一。

---

### Task 4：CBZ 自製樣本——頁序驗證（零填補 vs. 非零填補）與 RTL 覆蓋可行性

**Files:**
- Create（Python 合成）：`app/src/main/assets/books/cbz_padded.cbz`、`cbz_unpadded.cbz`
- Modify：`app/src/main/assets/foliate/index.html`、`main.js`

**Interfaces:**
- Consumes：Task 1 骨架（本 Task 不再需要 Task 2/3 的 KF8 相關內容）
- Produces：CBZ 頁序行為與 `book.dir` RTL 覆蓋可行性的實測結論

**背景說明**：`comic-book.js` 原始碼查證顯示圖片檔名用 `.sort()`（字典序），沒有自然排序；`book` 物件不含 `dir` 欄位，`fixed-layout.js` 的 RTL 判定完全依賴 `book.dir === 'rtl'`。本 Task 用兩份自製樣本驗證這兩項查證結論在真機實際渲染時的具體表現。

- [ ] **Step 1：用 Python 合成兩份 CBZ（零填補 vs. 非零填補檔名）**

10 頁每頁為單色矩形 PNG（不同顏色/頁碼數字，供肉眼辨識順序），零填補版本檔名 `001.png`～`010.png`，非零填補版本檔名 `1.png`～`10.png`（內容完全相同，只有檔名格式不同，供對照）：

```bash
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe"
cat > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/make_cbz.py" << 'PYEOF'
"""合成 CBZ 頁序驗證樣本：10 張純色 PNG，各頁背景色不同、四角有頁碼色塊
供肉眼辨識實際顯示順序。零填補與非零填補兩版內容相同，只有檔名格式不同。"""
import struct
import zipfile
import zlib
from pathlib import Path

OUT_DIR = Path(__file__).parent.parent / "foliate-spike-harness" / "app" / "src" / "main" / "assets" / "books"

# 10 種易辨識顏色（RGB），依頁碼順序遞增亮度，方便肉眼判斷「這是第幾頁」
COLORS = [
    (200, 0, 0), (200, 80, 0), (200, 160, 0), (160, 200, 0), (80, 200, 0),
    (0, 200, 80), (0, 160, 200), (0, 80, 200), (80, 0, 200), (160, 0, 200),
]

def make_png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """手工組裝最小合法 PNG（單一純色矩形，無壓縮 filter type 0），
    不依賴任何第三方套件，純 stdlib zlib 做 IDAT 壓縮。"""
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    row = bytes([0]) + bytes(rgb) * width  # filter type 0 (none) + RGB pixels
    raw = row * height
    idat = chunk(b"IDAT", zlib.compress(raw, 9))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def build_cbz(path: Path, names: list[str]) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, rgb in zip(names, COLORS):
            zf.writestr(name, make_png(400, 600, rgb))


padded = [f"{i:03d}.png" for i in range(1, 11)]
unpadded = [f"{i}.png" for i in range(1, 11)]

build_cbz(OUT_DIR / "cbz_padded.cbz", padded)
build_cbz(OUT_DIR / "cbz_unpadded.cbz", unpadded)

print("padded:", padded)
print("unpadded:", unpadded)
print("written to", OUT_DIR)
PYEOF
python3 "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/make_cbz.py"
python3 -c "
import zipfile
for name in ['cbz_padded.cbz', 'cbz_unpadded.cbz']:
    p = 'U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness/app/src/main/assets/books/' + name
    with zipfile.ZipFile(p) as zf:
        bad = zf.testzip()
        print(name, 'entries=', zf.namelist(), 'testzip=', bad)
"
```

Expected：兩份 `.cbz` 檔案成功產生；`testzip()` 回傳 `None`（代表 ZIP 結構完整、CRC32 皆正確，比照 `epic-20` Issue 8 已驗證過的 Python 交叉驗證方法）；`namelist()` 依檔名各自顯示零填補／非零填補的 10 個檔名。

- [ ] **Step 2：覆寫 `index.html`／`main.js`，先測零填補版本，含頁序記錄與 `book.dir` 覆寫**

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Multi-format Spike — CBZ</title>
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

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

// 依需要切換：'cbz_padded.cbz'（零填補）或 'cbz_unpadded.cbz'（非零填補）；
// 依需要切換：false（LTR，美漫預設）或 true（RTL，模擬使用者手動覆寫日漫翻頁方向）
const BOOK_FILE = 'cbz_padded.cbz'
const FORCE_RTL = false

async function openBook() {
  const book = await makeBook(
    `https://appassets.androidplatform.net/assets/books/${BOOK_FILE}`,
  )
  log('SPIKE_CBZ_SECTIONS', { ids: book.sections.map(s => s.id) })
  log('SPIKE_CBZ_RENDITION', { layout: book.rendition?.layout })
  log('SPIKE_CBZ_DIR_BEFORE', { dir: book.dir })
  if (FORCE_RTL) {
    // comic-book.js 回傳的 book 物件不含 dir 欄位；fixed-layout.js 的 RTL
    // 判定完全依賴 book.dir === 'rtl'（已讀取原始碼確認），故驗證呼叫端
    // 手動覆寫是否生效。
    book.dir = 'rtl'
  }
  await view.open(book)
  await view.init({})
  log('SPIKE_OPENED', { ok: true, isFixedLayout: view.isFixedLayout, rtl: view.book.dir === 'rtl' })
}

document.getElementById('btn-prev').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'prev' })
  view.prev()
})
document.getElementById('btn-next').addEventListener('click', () => {
  log('SPIKE_TRIGGER', { direction: 'next' })
  view.next()
})

openBook().catch(err => log('SPIKE_ERROR', { message: String(err), stack: err?.stack }))
```

寫入 `app/src/main/assets/foliate/index.html`／`main.js`（覆寫 Task 2/3 版本）。

- [ ] **Step 3：建置、安裝、啟動，記錄零填補版本的 sections 順序與畫面**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

等待約 3 秒：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-padded-page1.png"
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-padded-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-padded-logcat.txt"
```

Expected：`SPIKE_CBZ_SECTIONS.ids` 依序為 `["001.png","002.png",...,"010.png"]`（正確順序）；`SPIKE_CBZ_RENDITION.layout` 為 `"pre-paginated"`；截圖顯示 Task 4 Step 1 定義的第一種顏色（`(200,0,0)`，紅色）。點擊下一頁熱區 3 次，截圖確認顏色依序遞增亮度（對照 `COLORS` 陣列順序），逐一存為 `task4-padded-next-1.png`～`-3.png`。

- [ ] **Step 4：改為非零填補版本，重複驗證**

把 `main.js` 的 `BOOK_FILE` 改為 `'cbz_unpadded.cbz'`，重新建置：

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-unpadded-page1.png"
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-unpadded-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-unpadded-logcat.txt"
```

Expected（**如實記錄，不預設哪個結果「正確」**）：`SPIKE_CBZ_SECTIONS.ids` 若為 `["1.png","10.png","2.png","3.png",...,"9.png"]`（字典序），代表已查證的「無自然排序」結論成立、頁序確實錯誤（第 10 頁被排到第 2 頁前面）；若非預期地為正確數字順序，需重新檢查 Python 腳本或 `comic-book.js` 版本是否有出入，如實記錄實際觀察結果供 Spike 報告引用。

- [ ] **Step 5：RTL 覆蓋驗證**

把 `main.js` 改回 `BOOK_FILE = 'cbz_padded.cbz'`，`FORCE_RTL = true`，重新建置：

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/foliate-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.multiformatspike/.MainActivity
```

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-rtl-page1.png"
```

點擊左側熱區（座標 `266 1200`）一次，等待 2 秒，截圖：

```bash
adb -s <device-id> shell input tap 266 1200
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-rtl-after-left-tap.png"
adb -s <device-id> logcat -d | grep "MULTIFORMAT_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/reviews/task4-rtl-logcat.txt"
```

Expected：`SPIKE_CBZ_DIR_BEFORE.dir` 為 `undefined`（確認 `comic-book.js` 原始未設定 `dir`，佐證查證結論）；`SPIKE_OPENED.rtl` 為 `true`（確認覆寫生效）；點擊左側熱區後畫面應前進到下一頁（顏色遞增），因為 RTL 模式下左側熱區語意等同「下一頁」（`view.js` `goLeft()`：`book.dir === 'rtl' ? this.next() : this.prev()`）——這與 LTR 模式下左側熱區＝「上一頁」相反，是 RTL 覆蓋確實生效的行為證據。

---

### Task 5：KF8 DRM 位元組偵測可行性驗證（純 Python，不涉及 Android）

**Files:**
- Create：`tmp/epic-11/drm-probe/synth_mobi.py`

**Interfaces:**
- Consumes：無（獨立驗證）
- Produces：確認「PDB header → 首筆 record offset → +12 兩位元組大端序」這條位元組解析邏輯能正確且穩定地區分加密/未加密標頭

**背景說明**：已讀取 `mobi.js` 原始碼確認 `PALMDOC_HEADER.encryption` 欄位定義為 `[12, 2, 'uint']`（record 0 內 offset 12、2 bytes），`getUint()` 使用 `DataView.getUint16(0)` 不指定 `littleEndian` 引數（預設 `false`，即大端序）。對照公開的 PalmDOC/MOBI 格式規格，此值 `0`＝無加密、`1`＝舊版 Mobipocket 加密、`2`＝Mobipocket 加密。`mobi.js` 本身不會因此值非 0 而拒絕開啟，故偵測必須是獨立實作。本 Task 只驗證位元組解析邏輯本身，**不使用任何真實書籍內容**。

- [ ] **Step 1：撰寫合成標頭建構與偵測驗證腳本**

```bash
cat > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/synth_mobi.py" << 'PYEOF'
"""合成最小 PDB/MOBI 標頭緩衝區（不含任何真實書籍內容），驗證「PDB header →
首筆 record offset → +12 兩位元組大端序」這條位元組解析邏輯的可行性。
對應 mobi.js（readest/foliate-js 釘定 commit dd71f2be356563c16a23272686189fcfb45d0b82）
的 PDB_HEADER / PALMDOC_HEADER 欄位定義：
  PDB_HEADER: name[0:32], type[60:4], creator[64:4], numRecords[76:2]
  PALMDOC_HEADER（相對 record 0 起點）: compression[0:2], ..., encryption[12:2]
"""
import struct


def build_synthetic_pdb(encryption: int) -> bytes:
    """組出一份僅含 1 筆 record 的最小 PDB，record 0 內容只放 16 bytes
    的 PalmDOC header（真實 mobi.js 還會繼續讀 MOBI_HEADER/EXTH，但本驗證
    只需要涵蓋到 encryption 欄位即可，不需要組出完整可被 mobi.js 開啟的檔案）。"""
    name = b"SYNTH_TEST_BOOK".ljust(32, b"\x00")
    pdb_type = b"BOOK"
    creator = b"MOBI"
    num_records = 1

    pdb_header = (
        name
        + b"\x00" * (60 - 32)  # attributes/version/dates 等欄位，本驗證不需要正確值
        + pdb_type
        + creator
        + b"\x00" * (76 - 68)
        + struct.pack(">H", num_records)  # numRecords: 大端序 uint16
        + b"\x00" * 2  # nextRecordListID + 補齊到 78 bytes
    )
    assert len(pdb_header) == 78, len(pdb_header)

    record0_offset = 78 + num_records * 8  # record info list 之後
    record_info = struct.pack(">I", record0_offset) + b"\x00\x00\x00\x00"
    assert len(record_info) == 8

    palmdoc_header = (
        struct.pack(">H", 1)  # compression
        + b"\x00\x00"  # unused
        + struct.pack(">I", 0)  # text length
        + struct.pack(">H", 1)  # record count
        + struct.pack(">H", 4096)  # record size
        + struct.pack(">H", encryption)  # encryption ← 本驗證的核心欄位
        + b"\x00\x00"  # unused
    )
    assert len(palmdoc_header) == 16

    return pdb_header + record_info + palmdoc_header


def detect_encryption(buf: bytes) -> int:
    """對照 mobi.js 的 getUint()／getStruct() 邏輯手動實作的位元組解析：
    先讀 PDB_HEADER.numRecords（offset 76, 2 bytes, 大端序）確認至少有
    1 筆 record，再讀 record info list 第一筆的 offset（4 bytes, 大端序），
    最後在該 offset + 12 讀 2 bytes 大端序，即為 encryption 旗標。"""
    num_records = struct.unpack(">H", buf[76:78])[0]
    if num_records < 1:
        raise ValueError("no records")
    record0_offset = struct.unpack(">I", buf[78:82])[0]
    encryption = struct.unpack(">H", buf[record0_offset + 12:record0_offset + 14])[0]
    return encryption


# 正向案例：未加密
unencrypted = build_synthetic_pdb(encryption=0)
result_unencrypted = detect_encryption(unencrypted)
print(f"unencrypted: encryption={result_unencrypted} (expect 0)")
assert result_unencrypted == 0

# 負向案例：Mobipocket 加密（EXTH type 2，常見於 Kindle 購買書籍）
encrypted = build_synthetic_pdb(encryption=2)
result_encrypted = detect_encryption(encrypted)
print(f"encrypted:   encryption={result_encrypted} (expect 2)")
assert result_encrypted == 2

# 邊界案例：舊版 Mobipocket 加密
legacy_encrypted = build_synthetic_pdb(encryption=1)
result_legacy = detect_encryption(legacy_encrypted)
print(f"legacy:      encryption={result_legacy} (expect 1)")
assert result_legacy == 1

print("PASS: 位元組解析邏輯正確區分 0/1/2 三種 encryption 旗標值")
PYEOF
python3 "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/synth_mobi.py"
```

Expected：三個 `assert` 皆不拋出例外，終端輸出 `unencrypted: encryption=0`、`encrypted:   encryption=2`、`legacy:      encryption=1`，最終印出 `PASS`。若任一 `assert` 失敗，記錄具體數值差異——代表位元組解析邏輯（未來 Dart 版本的移植依據）本身有誤，需在 Spike 報告中明確記錄，NO-GO 或需要重新設計 Architecting 階段的 DRM 偵測方案。

- [ ] **Step 2：（可選）交叉驗證用 `mobi.js` 自身的 `getStruct` 邏輯手動解讀同一份合成緩衝區**

若 Step 1 通過，額外用 Node 執行等價的 JS 版本，確認與 `mobi.js` 實際使用的 `DataView.getUint16(0)`（無 `littleEndian` 引數、預設大端序）行為一致，避免 Python `struct.unpack('>H', ...)` 與 JS 端有語意落差：

```bash
cat > "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/verify_endian.mjs" << 'JSEOF'
// 讀取 Task 5 Step 1 產生的邏輯是否與 mobi.js 實際使用的
// DataView.getUint16(0)（無 littleEndian 引數，預設大端序）一致。
import { readFileSync } from 'node:fs'

function buildSyntheticPdb(encryption) {
  const buf = new ArrayBuffer(78 + 8 + 16)
  const view = new DataView(buf)
  const bytes = new Uint8Array(buf)
  const enc = new TextEncoder()
  bytes.set(enc.encode('SYNTH_TEST_BOOK'), 0)
  bytes.set(enc.encode('BOOK'), 60)
  bytes.set(enc.encode('MOBI'), 64)
  view.setUint16(76, 1)          // numRecords
  view.setUint32(78, 86)         // record 0 offset = 78 + 1*8
  view.setUint16(86 + 12, encryption) // encryption at record0Offset+12
  return buf
}

function detectEncryption(buf) {
  const view = new DataView(buf)
  const numRecords = view.getUint16(76)   // 無 littleEndian 引數 = 大端序，同 mobi.js getUint()
  if (numRecords < 1) throw new Error('no records')
  const record0Offset = view.getUint32(78)
  return view.getUint16(record0Offset + 12)
}

for (const expected of [0, 1, 2]) {
  const buf = buildSyntheticPdb(expected)
  const actual = detectEncryption(buf)
  console.log(`expected=${expected} actual=${actual} ${actual === expected ? 'OK' : 'MISMATCH'}`)
  if (actual !== expected) process.exit(1)
}
console.log('PASS: JS 版本（DataView 預設大端序）與 Python 版本結論一致')
JSEOF
node "U:/MyDeveloper/AI/elinkBook/tmp/epic-11/drm-probe/verify_endian.mjs"
```

Expected：三行皆為 `OK`，最終印出 `PASS`。這確認了 Python 驗證腳本與 `mobi.js` 實際執行環境（瀏覽器 `DataView`）的位元組序語意完全一致，Architecting 階段可以直接照抄這個 offset 邏輯到 Dart（`ByteData.getUint16(offset, Endian.big)`）而不需要重新推導。

---

### Task 6：彙整報告、GO/NO-GO 決策、更新文件、清理

**Files:**
- Create：`docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md`
- Modify：`docs/epics/epic-11-multi-format-reader/design.md`
- Modify：`docs/epics/epic-11-multi-format-reader/issues.md`

**Interfaces:**
- Consumes：Task 1-5 的截圖、logcat、Python/Node 腳本輸出
- Produces：本 Epic 後續（GO → Architecting／NO-GO → 縮小範圍評估）唯一可依循的正式結論

- [ ] **Step 1：撰寫診斷報告**

在 `docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md` 寫入以下結構（依 Task 1-5 的實際觀察結果填入，不得照抄本範本的佔位文字）：

```markdown
# Epic 11 Issue 1 — Spike：KF8/CBZ 開書可行性與 DRM 偵測驗證報告

**驗證日期：** <實際日期>
**驗證裝置：** <實際 adb devices -l 輸出，含 Android 版本/API/解析度>
**釘定 commit：** dd71f2be356563c16a23272686189fcfb45d0b82
**KF8 測試素材：** Standard Ebooks《The Time Machine》(h-g-wells_the-time-machine.azw3)，DRM-free 公版授權
**CBZ 測試素材：** Python 合成的 cbz_padded.cbz／cbz_unpadded.cbz（各 10 頁純色 PNG）

## KF8 開書/渲染/導覽（Task 2）
<makeBook() 自動分派結果、SPIKE_OPENED/SPIKE_RELOCATE 記錄、6 次連續翻頁截圖比對結論>

## KF8 × 直排覆蓋組合性（Task 3）
<直排是否正確生效，截圖對照>

## CBZ 頁序驗證（Task 4 Step 3-4）
<零填補版本 sections.ids 實際順序；非零填補版本 sections.ids 實際順序；是否印證「無自然排序」查證結論>

## CBZ RTL 覆蓋可行性（Task 4 Step 5）
<book.dir 覆寫前後行為對照，左側熱區行為是否符合預期>

## KF8 DRM 位元組偵測可行性（Task 5）
<Python/Node 腳本輸出結果，三種 encryption 值是否皆正確區分>

## 判準分類

| 驗證項目 | 結果 |
|---|---|
| KF8 開書/渲染/導覽 | <通過 / 失敗> |
| KF8 × 直排覆蓋組合性 | <通過 / 失敗> |
| CBZ 開書/渲染（`pre-paginated`） | <通過 / 失敗> |
| CBZ 零填補頁序 | <正確 / 錯誤> |
| CBZ 非零填補頁序 | <正確 / 錯誤（預期）> |
| CBZ RTL 覆蓋可行性 | <可行 / 不可行> |
| DRM 位元組偵測可行性 | <可行 / 不可行> |

## GO / NO-GO 決策

**結論：** <GO / NO-GO / 縮小範圍（僅 CBZ）>
<依 issues.md「GO/NO-GO 決策路徑」段落，說明下一步>

## Architecting 階段待落實事項（若 GO）

- CBZ 若確認「無自然排序」：需在匯入管線（Dart 端）對 CBZ 內部圖片檔名做自然排序後重新命名/重建索引，不能依賴 `comic-book.js` 內建排序。
- CBZ RTL：需在 `main.js` 整合層依使用者偏好（PRD FR-43「翻頁方向切換」）於 `makeComicBook()` 之後、`view.open(book)` 之前設定 `book.dir`。
- KF8 DRM：Dart 端偵測邏輯可直接採用 Task 5 驗證過的 offset（`ByteData.getUint16(record0Offset + 12, Endian.big)`），偵測到非 0 即拋出 `DrmProtectedException`（`design.md`「KF8/CBZ」條目）。
```

- [ ] **Step 2：更新 `design.md`**

在 `docs/epics/epic-11-multi-format-reader/design.md`「Issue 1：前置驗證 Spike」段落末尾補上一句總結（依實際結論擇一），並將該段落引用的驗證項目改為連結到報告：

若 GO：

```markdown
> **Spike 結果（<日期>）：GO**——完整證據見 `reviews/spike-issue1-kf8-cbz-drm.md`。下一步進入完整 Architecting 階段。
```

若 NO-GO 或縮小範圍：

```markdown
> **Spike 結果（<日期>）：<NO-GO / 縮小範圍：僅 CBZ 上線>**——完整證據見 `reviews/spike-issue1-kf8-cbz-drm.md`。<具體說明後續調整>
```

- [ ] **Step 3：更新 `issues.md`**

把 `docs/epics/epic-11-multi-format-reader/issues.md` 中 Issue 1 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，內容需涵蓋：判準分類結果、GO/NO-GO 結論、引用診斷報告路徑，並列出 Architecting 階段待落實事項清單（來自報告該段落）。

- [ ] **Step 4：清理裝置狀態**

```bash
adb -s <device-id> uninstall cc.ugotit.multiformatspike
```

Expected：`Success`。

- [ ] **Step 5：確認版控狀態乾淨**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：只顯示 `docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md`（新增）、`design.md`（修改）、`issues.md`（修改）三個檔案的異動；`tmp/epic-11/` 底下所有 throwaway 檔案（Harness 專案、截圖、logcat、Python 腳本、下載的 KF8 樣本）皆不出現，因已被根目錄 `.gitignore` 的 `tmp/` 規則排除。

- [ ] **Step 6：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-11-multi-format-reader/reviews/spike-issue1-kf8-cbz-drm.md
git add docs/epics/epic-11-multi-format-reader/design.md
git add docs/epics/epic-11-multi-format-reader/issues.md
git commit -m "docs(epic-11): Issue 1 spike——KF8/CBZ 開書可行性與 DRM 位元組偵測驗證"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 1 驗證範圍 1-5 逐項對應：
- KF8 開書/渲染/導覽 → Task 2
- KF8 × 直排覆蓋組合性 → Task 3
- CBZ 開書/渲染/頁序（零填補 vs. 非零填補） → Task 4 Step 1-4
- CBZ RTL 覆蓋可行性 → Task 4 Step 5
- KF8 DRM 位元組偵測可行性 → Task 5
- GO/NO-GO 決策路徑、報告、文件更新、清理 → Task 6

**API 依據來源（非憑空杜撰）**：本計畫所有涉及 `readest/foliate-js` 的 API 呼叫（`makeBook`／`view.open(book)`／`view.renderer`／`view.init({})`／`view.next()`/`view.prev()`／`book.transformTarget`／`book.dir`／`book.rendition.layout`／`book.sections`）皆直接讀取釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）當下的 `view.js`／`mobi.js`／`comic-book.js`／`fixed-layout.js` 原始內容逐一核對得出（見上方「背景」與 Global Constraints 逐條引用的行號），非憑印象猜測；且已用 GitHub API 實際查證這三個新增檔案確實存在於此 commit（避免重蹈 `epic-18` Issue 21「外部報告引用不存在 API」的既有踩坑教訓）。KF8 測試素材已實際下載並用 `xxd` 核對 magic bytes 確認為有效檔案（非猜測連結存在）。

**與 `design.md`／`issues.md` 已知查證的對應**：
- `mobi.js`/`comic-book.js`/`vendor/fflate.js` 存在性 → `issues.md`「背景」已記錄，Task 2 Step 1 實際下載驗證
- `transformTarget` 組合性技術可行性假設 → Task 3 實際驗證
- CBZ 無自然排序、無內建 RTL 兩項新發現 → Task 4 完整驗證並如實記錄（不預設結果）
- DRM 偵測需獨立實作 → Task 5 驗證位元組解析邏輯本身，明確排除「使用真實 DRM 檔案端到端驗證」（法律/倫理考量，`design.md`「明確排除」已界定）

**佔位符掃描**：全文無 TBD/待補字樣；Task 6 Step 1 報告範本的「<記錄...>」是驗證結果本質使然（比照 `epic-17`/`epic-20` Issue 1 plan 對同類段落的既有處理方式），所有涉及程式碼/指令的步驟皆已提供完整可執行內容，KF8 下載連結已實測有效（545452 bytes，magic bytes 已核對）。

**型別一致性**：`main.js` 全文的 `view.open(book)`／`view.renderer.setAttribute()`／`view.prev()`/`view.next()`／`view.init({})`／`book.transformTarget`／`book.dir`／`book.sections`／`book.rendition` 用法在 Task 2/3/4 之間一致延續（Task 3/4 為 Task 2 基礎上局部修改，非全面重寫）；`MainActivity.kt` 在 Task 1 定案後，Task 2-5 皆未再修改 Kotlin 檔案。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-11-multi-format-reader/plans/plan-issue-1.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
