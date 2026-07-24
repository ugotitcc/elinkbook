# Epic 17 Issue 7 — Spike：劃線/備註可行性驗證（`overlayer.js`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機 Android WebView 上，用一個獨立、throwaway 的 Android 專案驗證 `readest/foliate-js` 的 `overlayer.js`（`Overlayer` 類別）與 `view.js` 內建的標記管理 API（`addAnnotation`/`draw-annotation`/`show-annotation`）能否滿足現有劃線/備註功能的三項需求：(1) 多色劃線＋獨立螢光筆子類型的視覺繪製、(2) 使用者選取範圍即時回報螢幕座標百分比、(3) 點擊既有標記可靠觸發回呼並識別出正確的標記 id，並書面化結論供 Issue 8 依循。

**Architecture:** 沿用 `plans/plan-issue-1.md` 建立的 throwaway harness 模式（獨立 Android 專案、`WebViewAssetLoader`、`console.log` 橋接記錄證據），但這次的 Harness 目錄與 App ID 皆重新命名（`tmp/epic-17/overlayer-spike-harness/`／`cc.ugotit.overlayerspike`），避免與 Issue 1 的 Harness 混淆。查證 `view.js`/`overlayer.js` 原始碼（釘定 commit）後發現 `foliate-js` 已內建完整的標記管理流程（`view.addAnnotation(annotation, remove)` → `'draw-annotation'` 事件 → 呼叫端 `draw(Overlayer.highlight/underline, options)`；`doc` 點擊 → `Overlayer.hitTest()` → `'show-annotation'` 事件回報 `value`），比 `spec.md` 撰寫當下設想的「手動呼叫 `Overlayer.add()`」更完整；本計畫直接驗證這組內建 API，而非繞過它自己兜接線。以 6 個 Task 遞增建置：Task 1 建立 Harness 骨架；Task 2 打包 `foliate-js`＋測試素材、開書並強制直排；Task 3 驗證多色劃線＋螢光筆繪製；Task 4 驗證選取範圍即時座標回報；Task 5 驗證點擊既有標記觸發回呼；Task 6 彙整報告、判定風險等級、更新文件、清理。

**Tech Stack:** Kotlin（`Activity` + `WebView`）、`androidx.webkit:webkit:1.16.0`（`WebViewAssetLoader`）、Gradle 8.14 / AGP 8.11.1 / Kotlin 2.3.20（比照 `app/android` 既有已驗證版本組合）、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，與 Issue 1 同一版本）、`adb`／真機。

## Global Constraints

- **Harness 完全獨立、不進版控**：所有檔案位於 `tmp/epic-17/overlayer-spike-harness/`（`tmp/` 已在根目錄 `.gitignore` 排除），不建立、不修改 `app/` 下任何檔案。與 Issue 1 的 `tmp/epic-17/foliate-spike-harness/` 是兩個獨立目錄（Issue 1 的 Harness 已於該工單清理階段解除安裝，本工單不重用其殘留檔案，重新建置）。
- **釘定版本**：`readest/foliate-js` 打包內容一律取自 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（與 Issue 1 同一版本，確保結果與 Issue 1 的 Spike 結論在同一份原始碼基礎上）。
- **只需 8 個檔案**（與 Issue 1 相同的依賴閉包，本次額外會用到 `overlayer.js` 匯出的 `Overlayer` 類別，該檔案已包含在既有 8 個檔案內）：`view.js`、`epub.js`、`epubcfi.js`、`progress.js`、`overlayer.js`、`text-walker.js`、`paginator.js`、`vendor/zip.js`。
- **重用既有標記管理 API，不繞過它自己兜接線**：`view.js` 已內建 `addAnnotation(annotation, remove)`／`deleteAnnotation`／`'draw-annotation'`／`'show-annotation'` 事件（第 381-469 行，`Overlayer` 的建立、`hitTest` 綁定、`doc` 點擊監聽皆由 `view.js` 內部處理，Harness 不需要自己 `new Overlayer(doc)`）。`annotation` 物件只有 `.value`（作為 `Overlayer` 內部 Map 的 key，必須唯一，建議直接用 CFI 字串）有結構性意義，其餘欄位（`tint`／`isUnderline`）完全不透明，原樣透傳到 `'draw-annotation'` 事件的 `e.detail.annotation`，這與現有 `EpubDecoration` 欄位語意（`id`／`locatorJson`／`tint`／`isUnderline`）對應一致。
- **`Overlayer` 靜態繪製函式的 options 形狀不一致（本 Spike 需明確記錄的既有 API 落差）**：`Overlayer.highlight(rects, options)` 用布林 `options.vertical`；`Overlayer.underline(rects, options)` 用字串 `options.writingMode`（`'vertical-rl'`/`'vertical-lr'`）。Harness 呼叫兩者時需各自傳入正確形狀的參數，不可假設兩者一致——這個落差本身就是 Task 6 報告需要記錄、供 Issue 8 依循的具體事項之一。
- **本 Spike 用 CSS 十六進位色碼字串（例如 `'#FF0000'`）代表「劃線顏色」**，不模擬 `EpubDecoration.tint`（ARGB `int`）到 CSS 顏色字串的實際轉換公式——那是 Issue 8 實作階段的細節，本 Spike 只需要驗證「`draw` callback 收到顏色參數後，能否畫出對應顏色的視覺」這個能力本身。
- **座標系統組成（本 Spike 核心驗證項目，已讀 `paginator.js` 原始碼確認架構）**：每個章節內容渲染在獨立的 `<iframe>`（`paginator.js` 第 571 行 `#iframe`），`Overlayer`/`Range.getClientRects()` 回傳的座標是「iframe 內部視窗座標」；換算成整個 WebView 可視範圍的座標，需要 `iframe 內部座標 + iframe.getBoundingClientRect()（相對於外層頂層文件）`，再除以外層頂層文件的 `document.documentElement.clientWidth`/`clientHeight`。`paginator.js` 既有的放大鏡（loupe）功能已用同一套組合公式（第 1004-1005、2604-2610 行有對應註解「rect is in iframe-local coordinates; add view offset」），本 Spike 沿用相同原理，不是憑空假設。
- **選取範圍需驗證兩種觸發方式**：(a) 真機原生長按拖曳選字手勢（`adb shell input` 模擬），(b) 若 (a) 因 `adb input` 工具本身對「長按進入選字模式」模擬能力有限而不可靠，改用 JS 端 `Selection.addRange()` 程式化觸發 `selectionchange` 事件驗證座標換算公式本身是否正確——兩者驗證的是不同層面（(a) 驗證真實使用者手勢是否真的能被 WebView/JS 觀察到；(b) 驗證座標換算數學是否正確），報告需分別記錄結果，不可只做其中一項就下結論。
- **`.js` 資源 MIME 類型覆寫、`console.log` 橋接、`WebViewAssetLoader` 完全取代 `file://`**：比照 Issue 1 已驗證的 `MainActivity.kt` 寫法（見 Task 1）。
- **鎖定直向**：`AndroidManifest.xml` 的 `MainActivity` 加上 `android:screenOrientation="portrait"`（比照 Issue 1 審查修訂項目），避免裝置自動旋轉影響固定座標的按鈕/點擊。
- **只驗證 `vertical-rl`**：本 Epic 的核心差異化與最高風險方向；`main.js` 沿用 Issue 1 已驗證的 `book.transformTarget` 直排注入時序（`'data'` 事件、CSS 資源解析前附加覆蓋規則），不使用「監聽 `load` 自訂事件後插入 `<style>`」的時序有瑕疵替代方案。
- **每次觸發需間隔至少 2 秒**再擷取下一筆證據，避免操作排隊/畫面未穩定。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`。
- **裝置與座標**：沿用 `epic-7-interaction`/Issue 1 既有測試裝置與螢幕假設（1600×2400 直向）；執行時必須先用 `adb devices -l` 確認裝置、`adb shell wm size` 確認解析度，若不同需按比例換算本計畫內所有座標。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `tmp/epic-17/overlayer-spike-harness/settings.gradle.kts`／`build.gradle.kts`／`gradle.properties` | 新增（throwaway） | Gradle 專案設定 |
| `tmp/epic-17/overlayer-spike-harness/gradlew`／`gradlew.bat`／`gradle/wrapper/*` | 新增（複製自 `app/android`，throwaway） | Gradle wrapper |
| `tmp/epic-17/overlayer-spike-harness/app/build.gradle.kts` | 新增（throwaway） | App 模組建置設定 |
| `tmp/epic-17/overlayer-spike-harness/app/src/main/AndroidManifest.xml` | 新增（throwaway） | 單一 Activity 宣告 |
| `tmp/epic-17/overlayer-spike-harness/app/src/main/kotlin/cc/ugotit/overlayerspike/MainActivity.kt` | 新增（throwaway） | `WebView` + `WebViewAssetLoader` + console log 橋接 |
| `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/*.js`／`vendor/zip.js` | 新增（下載，throwaway） | 釘定 commit 的 `readest/foliate-js` 依賴閉包 |
| `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/index.html`／`main.js` | 新增（throwaway，逐 Task 擴充） | 載入頁與量測腳本 |
| `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub` | 新增（複製自 `app/test/fixtures/`，throwaway） | 重現素材，與 Issue 1 同一份 |
| `docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md` | 新增（正式，進版控） | 三項驗證結論、風險分級 |
| `docs/epics/epic-17-epub-render-migration/issues.md` | 修改（正式） | Issue 7 完成說明 |

---

### Task 1：建立獨立 Android 專案骨架，驗證 WebViewAssetLoader 管線可用

**Files:**
- Create：`tmp/epic-17/overlayer-spike-harness/settings.gradle.kts`、`build.gradle.kts`、`gradle.properties`
- Create（複製）：`tmp/epic-17/overlayer-spike-harness/gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar`、`gradle/wrapper/gradle-wrapper.properties`
- Create：`tmp/epic-17/overlayer-spike-harness/app/build.gradle.kts`
- Create：`tmp/epic-17/overlayer-spike-harness/app/src/main/AndroidManifest.xml`
- Create：`tmp/epic-17/overlayer-spike-harness/app/src/main/kotlin/cc/ugotit/overlayerspike/MainActivity.kt`
- Create（暫時內容，Task 2 會覆寫）：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/index.html`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：可建置、安裝、啟動的最小 `WebView` Activity，`WebViewAssetLoader` 已正確攔截 `https://appassets.androidplatform.net/assets/` 底下的請求；`MainActivity.kt` 本 Task 完成後不再需要修改，Task 2-5 只新增/覆寫 `assets/foliate/` 底下的檔案。

- [x] **Step 1：確認裝置、建立目錄結構**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p tmp/epic-17/overlayer-spike-harness/app/src/main/kotlin/cc/ugotit/overlayerspike
mkdir -p tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate
mkdir -p tmp/epic-17/overlayer-spike-harness/app/src/main/assets/books
mkdir -p tmp/epic-17/reviews
git status --short
adb devices -l
```

Expected：`git status --short` 無輸出（`tmp/` 已被 `.gitignore` 排除）；`adb devices -l` 列出至少 1 台裝置，記下 `<device-id>`。

- [x] **Step 2：確認裝置解析度**

```bash
adb -s <device-id> shell wm size
```

Expected：`Physical size: 1600x2400`（若不同，記錄實際值，後續座標需按比例換算）。

- [x] **Step 3：複製主專案已驗證可用的 Gradle wrapper**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/gradlew"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradlew.bat" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/gradlew.bat"
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/gradle/wrapper"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.jar" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/gradle/wrapper/gradle-wrapper.jar"
cp "U:/MyDeveloper/AI/elinkBook/app/android/gradle/wrapper/gradle-wrapper.properties" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/gradle/wrapper/gradle-wrapper.properties"
```

Expected：4 個檔案複製成功。

- [x] **Step 4：寫 `settings.gradle.kts`**

在 `tmp/epic-17/overlayer-spike-harness/settings.gradle.kts` 寫入：

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

rootProject.name = "overlayer-spike-harness"
include(":app")
```

- [x] **Step 5：寫根目錄 `build.gradle.kts`**

在 `tmp/epic-17/overlayer-spike-harness/build.gradle.kts` 寫入：

```kotlin
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

- [x] **Step 6：寫 `gradle.properties`**

在 `tmp/epic-17/overlayer-spike-harness/gradle.properties` 寫入：

```properties
org.gradle.jvmargs=-Xmx2048M
android.useAndroidX=true
kotlin.code.style=official
```

- [x] **Step 7：寫 `app/build.gradle.kts`**

在 `tmp/epic-17/overlayer-spike-harness/app/build.gradle.kts` 寫入：

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "cc.ugotit.overlayerspike"
    compileSdk = 35

    defaultConfig {
        applicationId = "cc.ugotit.overlayerspike"
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

- [x] **Step 8：寫 `AndroidManifest.xml`**

在 `tmp/epic-17/overlayer-spike-harness/app/src/main/AndroidManifest.xml` 寫入：

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="false"
        android:label="Overlayer Spike Harness"
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

- [x] **Step 9：寫 `MainActivity.kt`（最終版，本 Task 後不再修改）**

在 `tmp/epic-17/overlayer-spike-harness/app/src/main/kotlin/cc/ugotit/overlayerspike/MainActivity.kt` 寫入：

```kotlin
package cc.ugotit.overlayerspike

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
                    // 的 MIME 類型會直接拒絕載入，故針對 .js 明確覆寫。
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
                    Log.i("OVERLAYER_SPIKE", consoleMessage.message())
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl("https://appassets.androidplatform.net/assets/foliate/index.html")
    }
}
```

- [x] **Step 10：寫暫時的 `index.html`（僅供本 Task 驗證管線，Task 2 會覆寫）**

在 `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/index.html` 寫入：

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Overlayer Spike</title></head>
<body><h1 id="status">OVERLAYER_SPIKE_HARNESS_OK</h1></body>
</html>
```

- [x] **Step 11：建置、安裝、啟動，截圖確認管線可用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness"
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.overlayerspike/.MainActivity
```

等待約 2 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task1-pipeline.png"
```

Expected：建置成功、安裝成功、截圖顯示「OVERLAYER_SPIKE_HARNESS_OK」文字。

---

### Task 2：打包 `readest/foliate-js`＋測試素材，開書並強制直排

**Files:**
- Create（下載，釘定 commit）：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/{view.js,epub.js,epubcfi.js,progress.js,overlayer.js,text-walker.js,paginator.js,vendor/zip.js}`
- Create（複製）：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub`
- Modify（覆寫 Task 1 暫時內容）：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/index.html`
- Create：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 1 已驗證可用的 `MainActivity.kt`／`WebViewAssetLoader` 管線
- Produces：可開啟 EPUB、強制直排、透過左右熱區換頁的 Harness，`view`／`currentDoc`／`currentIndex` 三個模組級變數供 Task 3-5 擴充 `main.js` 時使用

- [x] **Step 1：下載釘定 commit 的 `readest/foliate-js` 依賴閉包**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate"
mkdir -p vendor
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
for f in view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js; do
  curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/$f" -o "$f"
done
head -c 60 view.js
echo
wc -l view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js vendor/zip.js
```

Expected：`head -c 60 view.js` 以 `import * as CFI from './epubcfi.js'` 開頭；`wc -l` 對 8 個檔案皆回報非 0 行數（`overlayer.js` 預期約 430 行）。

- [x] **Step 2：複製測試素材**

```bash
cp "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/issue9_vertical_pagejump.epub" \
   "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/app/src/main/assets/books/issue9_vertical_pagejump.epub"
ls -la "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness/app/src/main/assets/books/"
```

Expected：檔案存在，大小約 303KB（309978 bytes）。

- [x] **Step 3：覆寫 `index.html`，加入 4 個透明觸發熱區**

把 `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/index.html` 內容改為：

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Overlayer Spike</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #fff; }
  foliate-view { display: block; width: 100%; height: 100%; }
  #btn-prev, #btn-next {
    position: fixed; top: 15%; height: 70%; width: 33%;
    background: transparent; border: none; padding: 0; margin: 0; z-index: 10;
  }
  #btn-prev { left: 0; }
  #btn-next { right: 0; }
  #btn-annotate, #btn-select-fallback {
    position: fixed; left: 33%; width: 34%; height: 15%;
    background: transparent; border: none; padding: 0; margin: 0; z-index: 10;
  }
  #btn-annotate { top: 0; }
  #btn-select-fallback { bottom: 0; }
</style>
</head>
<body>
<foliate-view id="view"></foliate-view>
<button id="btn-prev" aria-label="prev"></button>
<button id="btn-next" aria-label="next"></button>
<button id="btn-annotate" aria-label="annotate"></button>
<button id="btn-select-fallback" aria-label="select-fallback"></button>
<script type="module" src="./main.js"></script>
</body>
</html>
```

（`btn-prev`/`btn-next` 改為只佔畫面中間 70% 高度，讓出上下各 15% 給 `btn-annotate`/`btn-select-fallback`，四者互不重疊。）

- [x] **Step 4：寫 `main.js`（基準版本——開書、強制直排、換頁熱區，尚無標記/選取邏輯）**

在 `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/main.js` 寫入：

```js
import { makeBook } from './view.js'

const view = document.getElementById('view')

// Task 3-5 會在 'load' 事件中更新這兩個模組級變數，供各自的按鈕處理常式
// 讀取「目前畫面上實際渲染的是哪個章節/doc」。
let currentDoc = null
let currentIndex = null

function log(tag, obj) {
  console.log(`${tag} ${JSON.stringify(obj)}`)
}

view.addEventListener('relocate', (e) => {
  log('OVERLAYER_RELOCATE', {
    cfi: e.detail.cfi,
    fraction: e.detail.fraction,
    index: e.detail.index,
  })
})

view.addEventListener('load', (e) => {
  currentDoc = e.detail.doc
  currentIndex = e.detail.index
  log('OVERLAYER_LOAD', { index: e.detail.index })
})

async function openBook() {
  const book = await makeBook(
    'https://appassets.androidplatform.net/assets/books/issue9_vertical_pagejump.epub',
  )
  // 與 Issue 1 Task 3 已驗證的直排注入時序完全相同：透過 transformTarget 的
  // 'data' 事件在 CSS 資源文字被解析前附加覆蓋規則，確保在 Paginator 第一次
  // 計算方向/分欄之前就已生效。
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
  log('OVERLAYER_OPENED', { ok: true })
}

document.getElementById('btn-prev').addEventListener('click', () => {
  log('OVERLAYER_TRIGGER', { direction: 'prev' })
  view.prev()
})
document.getElementById('btn-next').addEventListener('click', () => {
  log('OVERLAYER_TRIGGER', { direction: 'next' })
  view.next()
})

openBook()
```

- [x] **Step 5：重新建置、安裝、啟動，翻頁至有正文內容的頁面，截圖確認直排渲染正常**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.overlayerspike/.MainActivity
```

等待約 3 秒讓 EPUB 解析與首頁渲染完成。重複點擊下一頁熱區（右側，座標 `1340 1200`，若裝置解析度不同需按比例換算），每次間隔至少 2 秒，肉眼檢視截圖直到畫面出現大量連續段落文字（跳過封面/版權頁）：

```bash
adb -s <device-id> shell input tap 1340 1200
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task2-skip-1.png"
```

重複上述兩行直到確認到達正文頁面，記錄總共點擊次數（供 Task 6 報告引用），最後擷取一次確認用截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task2-content-page.png"
adb -s <device-id> logcat -d | grep "OVERLAYER_SPIKE" | grep -E "OVERLAYER_OPENED|OVERLAYER_LOAD" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task2-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task2-logcat.txt"
```

Expected：截圖顯示直排繁體中文正文（欄由右至左排列）；logcat 內有 `OVERLAYER_OPENED {"ok":true}` 與多筆 `OVERLAYER_LOAD`。

---

### Task 3：驗證多色劃線＋螢光筆子類型繪製（研究問題 #1）

**Files:**
- Modify：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 2 的 `view`／`currentDoc`／`currentIndex`／`log()`
- Produces：`addTestAnnotations()` 函式與 `#btn-annotate` 綁定；4 筆已加入的標記（3 色螢光筆 + 1 條底線），各自的 CFI 記錄於 logcat，供 Task 5 點擊測試使用

- [x] **Step 1：在 `main.js` 加入 `Overlayer` import、`draw-annotation` 監聽、`addTestAnnotations()`**

在 `tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/main.js` 檔案開頭的 import 之後（`import { makeBook } from './view.js'` 之後）新增：

```js
import { Overlayer } from './overlayer.js'
```

在 `view.addEventListener('load', ...)` 區塊之後新增：

```js
// 依 EpubDecoration 現有欄位語意（tint／isUnderline）決定繪製方式：
// isUnderline === true 用 Overlayer.underline（底線，螢幕座標系為直排，
// 需傳 writingMode 字串)；否則用 Overlayer.highlight（半透明矩形背景，
// 需傳布林 vertical——兩個靜態函式的 options 形狀刻意不同，見 Global
// Constraints 已記錄的既有 API 落差）。
view.addEventListener('draw-annotation', (e) => {
  const { draw, annotation } = e.detail
  if (annotation.isUnderline) {
    draw(Overlayer.underline, { color: annotation.tint, writingMode: 'vertical-rl' })
  } else {
    draw(Overlayer.highlight, { color: annotation.tint, vertical: true })
  }
  log('OVERLAYER_DRAW_ANNOTATION', {
    value: annotation.value,
    tint: annotation.tint,
    isUnderline: !!annotation.isUnderline,
  })
})

view.addEventListener('show-annotation', (e) => {
  log('OVERLAYER_SHOW_ANNOTATION', { value: e.detail.value, index: e.detail.index })
})

// 在目前畫面上已渲染的文件中，挑選前 4 個字數足夠的 <p> 元素，各自建立一個
// 涵蓋整個段落的 Range，透過 view.getCFI() 換算成 CFI 字串（Overlayer 內部
// Map 用來當 key，必須唯一），再呼叫 view.addAnnotation() 觸發
// 'draw-annotation' 事件。比照現有 EpubDecoration 的 3 色螢光筆 + 1 個純
// 底線（模擬備註)組合。
async function addTestAnnotations() {
  if (!currentDoc) {
    log('OVERLAYER_ANNOTATE_SKIPPED', { reason: 'currentDoc 尚未就緒' })
    return
  }
  const configs = [
    { tint: '#FF0000', isUnderline: false },
    { tint: '#00FF00', isUnderline: false },
    { tint: '#0000FF', isUnderline: false },
    { tint: '#000000', isUnderline: true },
  ]
  const paragraphs = Array.from(currentDoc.querySelectorAll('p'))
    .filter((p) => p.textContent.trim().length >= 10)
  log('OVERLAYER_PARAGRAPHS_FOUND', { count: paragraphs.length })
  for (let i = 0; i < configs.length && i < paragraphs.length; i++) {
    const range = currentDoc.createRange()
    range.selectNodeContents(paragraphs[i])
    const cfi = view.getCFI(currentIndex, range)
    await view.addAnnotation({ value: cfi, ...configs[i] })
    log('OVERLAYER_ANNOTATION_ADDED', { index: i, cfi, ...configs[i] })
  }
}

document.getElementById('btn-annotate').addEventListener('click', () => {
  addTestAnnotations()
})
```

- [x] **Step 2：重新建置、安裝、啟動，翻到正文頁面，點擊「加入標記」熱區**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.overlayerspike/.MainActivity
```

等待約 3 秒，重複點擊下一頁熱區（`1340 1200`）翻到 Task 2 已確認過的正文頁面（次數與 Task 2 一致），每次間隔至少 2 秒。到達正文頁面後，點擊「加入標記」熱區（畫面上方 15% 高度區塊中央，座標約 `800 180`，若解析度不同需按比例換算）：

```bash
adb -s <device-id> shell input tap 800 180
```

等待至少 2 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task3-annotations.png"
adb -s <device-id> logcat -d | grep "OVERLAYER_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task3-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task3-logcat.txt"
```

Expected：logcat 依序出現 `OVERLAYER_PARAGRAPHS_FOUND`（`count >= 4`，若 `< 4` 需改到段落更多的頁面重試）、4 筆 `OVERLAYER_ANNOTATION_ADDED`（各自不同的 `cfi`）、4 筆 `OVERLAYER_DRAW_ANNOTATION`。用 Read 工具開啟 `spike7-task3-annotations.png`，肉眼確認畫面上出現 3 種不同顏色的半透明矩形背景（紅/綠/藍）與 1 條黑色底線，且底線的方向符合直排（線段沿垂直方向、貼齊文字右側，而非橫排時貼齊文字下緣——見 `Overlayer.underline` 原始碼對 `writingMode === 'vertical-rl'` 的分支）。逐一記錄每個 `cfi` 值與其對應在畫面上的大略位置（供 Task 5 使用）。

---

### Task 4：驗證選取範圍即時回報螢幕座標百分比（研究問題 #2）

**Files:**
- Modify：`tmp/epic-17/overlayer-spike-harness/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 3 的 `currentDoc`／`log()`
- Produces：`selectionchange` 監聽器（真實選字手勢與程式化選取皆可觸發）、`#btn-select-fallback` 綁定的程式化選取程式碼，logcat 記錄換算後的 `leftPct`/`topPct`/`rightPct`/`bottomPct`

- [x] **Step 1：在 `main.js` 加入座標換算與選取監聽**

在 `view.addEventListener('load', (e) => { ... })` 區塊內（`log('OVERLAYER_LOAD', ...)` 之後），新增每次章節載入時對該 `doc` 掛上 `selectionchange` 監聽：

```js
view.addEventListener('load', (e) => {
  currentDoc = e.detail.doc
  currentIndex = e.detail.index
  log('OVERLAYER_LOAD', { index: e.detail.index })

  // 選取範圍座標換算：Range.getClientRects() 回傳的是「該章節 iframe 內部
  // 視窗座標」（見 paginator.js 第 571 行 #iframe、第 1004-1005/2604-2610
  // 行放大鏡功能的既有換算註解），需要加上 iframe 本身相對於外層頂層文件
  // 的位移（iframe.getBoundingClientRect()），再除以外層頂層文件的可視
  // 尺寸，才是「相對整個 WebView 可視範圍」的百分比座標——與現有
  // EpubReaderView.kt 用 rect / (webview width/height) 的既有換算原理一致。
  currentDoc.addEventListener('selectionchange', () => {
    const sel = currentDoc.getSelection()
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return
    const range = sel.getRangeAt(0)
    const rects = range.getClientRects()
    if (rects.length === 0) return
    const rect = rects[0]
    const frame = currentDoc.defaultView.frameElement
    const frameRect = frame.getBoundingClientRect()
    const outerWidth = document.documentElement.clientWidth
    const outerHeight = document.documentElement.clientHeight
    log('OVERLAYER_SELECTION_CHANGED', {
      text: sel.toString(),
      leftPct: (frameRect.left + rect.left) / outerWidth,
      topPct: (frameRect.top + rect.top) / outerHeight,
      rightPct: (frameRect.left + rect.right) / outerWidth,
      bottomPct: (frameRect.top + rect.bottom) / outerHeight,
    })
  })
})
```

在檔案末尾（`document.getElementById('btn-annotate')...` 之後）新增程式化選取的退路觸發按鈕：

```js
// 退路驗證：若真機原生長按拖曳選字手勢無法穩定透過 adb input 模擬觸發
// selectionchange（見 Global Constraints 已記錄的已知工具限制），改用
// Selection.addRange() 程式化建立選取範圍——這是標準 DOM API，會與真實
//使用者選字動作觸發相同的 selectionchange 事件，可單獨驗證「座標換算公式
// 本身是否正確」這個子問題（與「真實手勢是否能被觀察到」是兩回事）。
document.getElementById('btn-select-fallback').addEventListener('click', () => {
  if (!currentDoc) {
    log('OVERLAYER_SELECT_FALLBACK_SKIPPED', { reason: 'currentDoc 尚未就緒' })
    return
  }
  const paragraphs = Array.from(currentDoc.querySelectorAll('p'))
    .filter((p) => p.textContent.trim().length >= 10)
  if (paragraphs.length === 0) {
    log('OVERLAYER_SELECT_FALLBACK_SKIPPED', { reason: '找不到足夠長度的段落' })
    return
  }
  const range = currentDoc.createRange()
  range.selectNodeContents(paragraphs[0])
  const sel = currentDoc.getSelection()
  sel.removeAllRanges()
  sel.addRange(range)
  log('OVERLAYER_SELECT_FALLBACK_TRIGGERED', { text: range.toString().slice(0, 20) })
})
```

- [x] **Step 2：重新建置、安裝、啟動，翻到正文頁面，嘗試真機原生長按拖曳選字手勢**

```bash
cd "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/overlayer-spike-harness"
adb -s <device-id> logcat -c
./gradlew.bat :app:assembleDebug
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n cc.ugotit.overlayerspike/.MainActivity
```

等待約 3 秒，翻到正文頁面（比照 Task 2/3 次數）。在畫面中段文字上模擬「長按進入選字模式」（同一點按住約 800ms）：

```bash
adb -s <device-id> shell input swipe 800 1200 800 1200 800
```

等待至少 1 秒，擷取截圖確認是否出現選取控點（selection handles）：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-longpress.png"
```

用 Read 工具檢視截圖。若畫面上出現選取控點（一段文字被反白、兩端有可拖曳的把手圖示），再模擬拖曳其中一個控點延伸選取範圍（例如從第一個控點座標拖曳約 200px）：

```bash
adb -s <device-id> shell input swipe 800 1200 1000 1200 500
```

等待至少 1 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-drag.png"
adb -s <device-id> logcat -d | grep "OVERLAYER_SELECTION_CHANGED" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-native-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-native-logcat.txt"
```

Expected（兩種可能結果皆需如實記錄，不預設哪一種才是「正確」）：(a) 若 `spike7-task4-longpress.png` 出現選取控點且 `spike7-task4-native-logcat.txt` 有 `OVERLAYER_SELECTION_CHANGED` 記錄——代表真機原生長按拖曳手勢可透過 `adb input` 可靠模擬，記錄下換算出的 `leftPct`/`topPct`/`rightPct`/`bottomPct` 是否與畫面反白區域的實際位置吻合；(b) 若未出現選取控點或 logcat 無記錄——這是已知的 `adb input` 工具限制（無法精確模擬「長按不動超過閾值時間」這個手勢判定），不代表 `foliate-js`/`selectionchange` 本身有問題，繼續下一步驟改用程式化退路驗證。

- [x] **Step 3：程式化退路驗證座標換算公式本身是否正確**

點擊「選取退路」熱區（畫面下方 15% 高度區塊中央，座標約 `800 2220`，若解析度不同需按比例換算）：

```bash
adb -s <device-id> shell input tap 800 2220
```

等待至少 1 秒，擷取截圖與 logcat：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-fallback.png"
adb -s <device-id> logcat -d | grep "OVERLAYER_SPIKE" | grep -E "OVERLAYER_SELECT_FALLBACK|OVERLAYER_SELECTION_CHANGED" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-fallback-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task4-fallback-logcat.txt"
```

Expected：logcat 有 `OVERLAYER_SELECT_FALLBACK_TRIGGERED`，緊接著至少一筆 `OVERLAYER_SELECTION_CHANGED`（`leftPct`/`topPct`/`rightPct`/`bottomPct` 皆為 0-1 之間的合理值）。用 Read 工具比對 `spike7-task4-fallback.png` 中該段落的實際畫面位置，與 logcat 記錄的百分比座標換算後對應的螢幕像素位置（`leftPct * 1600` 等）是否大致吻合（容許數十像素誤差）——這是驗證座標換算公式正確性的關鍵證據。

---

### Task 5：驗證點擊既有標記可靠觸發回呼並識別正確 id（研究問題 #3）

**Files:** 無新增異動（沿用 Task 1-4 建好的 Harness）

**Interfaces:**
- Consumes：Task 3 已加入的 4 筆標記（各自的 `cfi` 與大略畫面位置）
- Produces：對每筆標記各執行一次點擊，確認 `'show-annotation'` 事件（`OVERLAYER_SHOW_ANNOTATION` log）回報的 `value` 與該筆標記建立時的 `cfi` 完全一致；額外驗證點擊「無標記」區域不會誤觸發

- [x] **Step 1：用 Read 工具視覺判讀 `spike7-task3-annotations.png`，決定 4 個標記與 1 個空白對照區的點擊座標**

開啟 Task 3 Step 2 產出的 `tmp/epic-17/reviews/spike7-task3-annotations.png`，肉眼找出畫面上 3 種顏色矩形背景與 1 條底線各自的點擊座標（記錄為 `(x1,y1)`／`(x2,y2)`／`(x3,y3)`／`(x4,y4)`），並額外找一處明顯沒有任何標記覆蓋的空白文字區域座標 `(x5,y5)`（用於驗證「無標記處點擊不應誤觸發」）。

**座標精準度要求（審查修正）**：`Overlayer.hitTest()` 的 `tolerance = 5` 是 CSS px（`getClientRects()`/事件座標皆為 CSS px，非裝置實體像素），在高 DPI 裝置上（`devicePixelRatio` 通常 2-3 倍）換算回螢幕截圖的實體像素後，5 CSS px 只對應約 10-15 個實體像素，容錯範圍比表面數字更緊。3 個螢光筆矩形（`x1`/`x2`/`x3`）面積較大，取矩形內明顯居中的位置即可；但**第 4 筆底線標記（`x4`/`y4`）在直排下是沿文字欄右緣、寬度僅 2 CSS px（約 4-6 實體像素）的細線**（見 `Overlayer.underline` 對 `vertical-rl` 分支：`width` 固定為 `strokeWidth`、`height` 為整行文字高度）——水平方向必須盡量貼齊該細線本身，垂直方向（該段落文字的整個行高範圍內）則容錯較大，不需要特別精準。若第一次點擊 `(x4,y4)` 未觸發 `OVERLAYER_SHOW_ANNOTATION`，在 Step 2 對應段落重新以水平方向 ±3-5 實體像素微調座標後再試一次，仍未命中才記錄為負面結果。

- [x] **Step 2：依序點擊 4 個標記，逐一確認 `OVERLAYER_SHOW_ANNOTATION` 回報正確的 `value`**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> shell input tap <x1> <y1>
```

等待至少 2 秒，擷取 logcat：

```bash
adb -s <device-id> logcat -d | grep "OVERLAYER_SHOW_ANNOTATION" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task5-tap1.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task5-tap1.txt"
```

比對輸出的 `value` 是否與 Task 3 記錄的第 1 筆標記 `cfi` 完全相同。重複「清空 logcat → 點擊 `(x2,y2)`／`(x3,y3)`／`(x4,y4)` → 等待 2 秒 → 擷取 logcat → 比對 value」，依序存為 `spike7-task5-tap2.txt`／`spike7-task5-tap3.txt`／`spike7-task5-tap4.txt`；點擊底線標記 `(x4,y4)` 若未命中，依 Step 1 已記錄的精準度要求，沿水平方向微調 ±3-5 實體像素重試，仍未命中才視為該次結果。

Expected：4 次點擊各自觸發恰好一筆 `OVERLAYER_SHOW_ANNOTATION`，`value` 與對應建立時的 `cfi` 逐字元相同；若點擊座標落在兩個標記的重疊/相鄰邊界導致誤判，或底線標記需要微調才能命中，記錄下實際命中所需的座標誤差範圍（`Overlayer.hitTest()` 原始碼第 156 行 `tolerance = 5` 為 CSS px，非裝置實體像素，見 Step 1 已記錄的換算說明）。

- [x] **Step 3：點擊無標記的空白區域，確認不會誤觸發**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> shell input tap <x5> <y5>
```

等待至少 2 秒：

```bash
adb -s <device-id> logcat -d | grep "OVERLAYER_SHOW_ANNOTATION" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task5-tap5-blank.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-17/reviews/spike7-task5-tap5-blank.txt"
```

Expected：檔案為空（無 `OVERLAYER_SHOW_ANNOTATION` 記錄），確認 `hitTest()` 不會對無標記區域誤判。

---

### Task 6：彙整報告、風險分級、更新文件、清理

**Files:**
- Create：`docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md`
- Modify：`docs/epics/epic-17-epub-render-migration/issues.md`

**Interfaces:**
- Consumes：Task 1-5 的全部截圖、logcat 證據與比對結論
- Produces：Issue 8 實作時必須依循的正式結論；若發現嚴重落差，標記需要人類重新確認 ADR 0011 範圍

- [x] **Step 1：撰寫驗證報告**

在 `docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md` 寫入以下結構（依 Task 1-5 的實際觀察結果填入，不得照抄本範本的佔位文字）：

```markdown
# Epic 17 Issue 7 — Spike：劃線/備註可行性驗證（overlayer.js）報告

**驗證日期：** <實際日期>
**驗證裝置：** <實際 adb devices -l 輸出，含 Android 版本/API/解析度>
**釘定 commit：** dd71f2be356563c16a23272686189fcfb45d0b82（與 Issue 1 同一版本）
**測試素材：** app/test/fixtures/issue9_vertical_pagejump.epub

## 研究問題 #1：多色劃線＋獨立螢光筆子類型（Task 3）

<3 色螢光筆＋1 條底線是否皆正確繪製；writingMode/vertical 兩種不同 options 形狀是否都運作正常；引用 spike7-task3-annotations.png 與 logcat>

## 研究問題 #2：選取範圍即時回報螢幕座標百分比（Task 4）

<真機原生長按拖曳手勢是否能透過 adb input 可靠觸發 selectionchange；程式化退路驗證出的座標換算公式是否正確；兩者分別的結論>

## 研究問題 #3：點擊既有標記可靠觸發回呼並識別正確 id（Task 5）

<4 次點擊是否皆正確識別對應 value（含底線標記是否需要 Step 1/2 記錄的水平微調才能命中）；無標記區域點擊是否有誤觸發；hitTest() 5 CSS px 容許誤差換算成本次裝置實體像素後，在實務上是否足夠>

## 已記錄的既有 API 落差（供 Issue 8 依循）

- `Overlayer.highlight`／`Overlayer.underline` 的 options 形狀不一致（`vertical: boolean` vs `writingMode: string`），Issue 8 實作 `FoliateEpubReaderView.kt` 的橋接邏輯需要依 `isUnderline` 分別組裝正確形狀的 options。
- `Overlayer` 內部以 `annotation.value` 當 Map key，必須唯一（不可有兩筆標記共用同一個 CFI）——<記錄本次驗證是否遇到或需要特別處理這個限制>
- <若驗證過程中發現其他落差，逐項列出，含具體症狀與可能的替代做法>

## 風險分級與後續建議

**結論：** <三項研究問題整體是否足以支持「劃線/備註完整涵蓋在 Phase 1」（ADR 0011 既有決策）維持不變 / 需要人類重新確認範圍>
<若任一項有嚴重落差，具體說明落差內容與建議的替代做法，供 Issue 8 依循，不得由 Issue 8 實作者在工單執行階段才發現並自行決定退回方案>
```

- [x] **Step 2：更新 `issues.md`**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 7」區塊，把 `**Status:** \`ready-for-agent\`` 改為完成狀態，比照 Issue 1 既有的完成摘要寫法，內容需涵蓋：三項研究問題的結論摘要、是否發現需要 Issue 8 依循的落差、引用報告路徑 `reviews/spike-overlayer-annotations.md`。

- [x] **Step 3：清理裝置狀態**

```bash
adb -s <device-id> uninstall cc.ugotit.overlayerspike
```

Expected：`Success`。

- [x] **Step 4：確認版控狀態乾淨**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：只顯示 `docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md`（新增）與 `issues.md`（修改）兩個檔案的異動；`tmp/epic-17/overlayer-spike-harness/` 與 `tmp/epic-17/reviews/` 底下的所有 throwaway 檔案皆不出現（已被根目錄 `.gitignore` 的 `tmp/` 規則排除）。

- [x] **Step 5：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 7 spike——overlayer.js 劃線/備註可行性驗證與收斂"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 7 逐項對應：
- 多色劃線＋獨立螢光筆子類型 → Task 3
- 選取範圍即時回報座標 → Task 4（真實手勢 + 程式化退路雙重驗證）
- 點擊既有標記觸發回呼 → Task 5
- 明確結論與證據（截圖、DOM/JS 主控台觀察）寫入報告 → Task 6 Step 1
- 若發現落差需記錄具體落差與替代做法供 Issue 8 依循；嚴重落差需標記人類重新確認範圍 → Task 6 Step 1 報告範本「已記錄的既有 API 落差」「風險分級與後續建議」兩節
- 暫時性程式碼/素材已清理、`git status` 乾淨 → Task 6 Step 3/4

**與 `spec.md`「待驗證風險與收斂關卡」#1 的對應**：三個子問題（`draw()` callback 依 tint/isUnderline 畫視覺、選取範圍座標換算、`hitTest()` 回傳形狀與可靠度）逐一對應 Task 3/4/5，且已讀 `overlayer.js`/`view.js` 原始碼確認 `foliate-js` 內建的 `addAnnotation`/`draw-annotation`/`show-annotation` API 比 `spec.md` 撰寫當下設想的「手動呼叫 `Overlayer.add()`」更完整，本計畫已改為驗證這組更貼近實際production 用法的內建 API（Global Constraints 已說明）。

**佔位符掃描**：全文無 TBD/待補字樣；Task 6 Step 1 報告範本的「<記錄...>」是驗證結果本質使然（比照 `plan-issue-1.md` Task 5 對同類段落的既有處理方式），所有涉及程式碼/指令的步驟皆已提供完整可執行內容。

**API 依據來源（非憑空杜撰）**：`Overlayer` 類別（`constructor`／`add`／`hitTest`／`static underline`/`highlight` 等）、`view.js` 的 `addAnnotation`/`deleteAnnotation`/`getCFI`/`'draw-annotation'`/`'show-annotation'`/`'load'` 事件、`paginator.js` 的 `<iframe>` 渲染架構與既有放大鏡座標換算註解，皆直接讀取 `readest/foliate-js` 於釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）當下的原始碼逐一核對得出，非憑印象猜測。

**型別一致性**：`main.js` 全文的 `view.getCFI(index, range)`／`view.addAnnotation({value, tint, isUnderline})`／`Overlayer.highlight(rects, {color, vertical})`／`Overlayer.underline(rects, {color, writingMode})`／`currentDoc`/`currentIndex` 模組級變數在 Task 2（基準版）、Task 3（標記繪製）、Task 4（選取監聽）之間一致延續，未中途改名；`MainActivity.kt` 在 Task 1 定案後，Task 2-5 皆未再修改 Kotlin 檔案，任務邊界清楚。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-17-epub-render-migration/plans/plan-issue-7.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
