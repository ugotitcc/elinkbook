# Issue 4 實作計劃：原生 Android 模組 —— `EpubReaderView`（Readium Kotlin Toolkit）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 整合 Readium 官方 `kotlin-toolkit`（版本 `3.3.0`），建立包裝它的原生 `PlatformView`，透過 Flutter 的 `AndroidView` 機制嵌入畫面，實作 `spec.md` 定義的 `openBook`/`onPageRendered`/`onError` platform channel 契約（與 Issue 3 的 `PdfReaderView` 完全相同的契約），並用 `integration_test` 在真實 Android 裝置/模擬器上驗證。

**架構：** Flutter 端是一個包裝 `AndroidView` 的 `EpubReaderView` widget，透過每個 view 實例專屬的 `MethodChannel` 與原生端溝通——這一層與 Issue 3 的 `PdfReaderView` 完全對稱（同名方法、同樣的 channel 命名慣例，只換了 view type 字串）。原生端把 Readium 的 `EpubNavigatorFragment`（一個 `androidx.fragment.app.Fragment`）包裝成 `PlatformView`：由於 `PlatformView.getView()` 必須同步回傳一個純 `View`，而 `EpubNavigatorFragment` 的建構子是 `internal`（只能透過 Readium 自己的 `FragmentFactory` 建立），所以原生端的做法是：`getView()` 回傳一個帶穩定 ID 的空 `FrameLayout` 容器；非同步解析出 `Publication` 後，把 `EpubNavigatorFactory` 產生的 `FragmentFactory` 設到 Activity 層級的 `supportFragmentManager`，再用 `commitNow { add<EpubNavigatorFragment>(containerId, ...) }` 把 Fragment 掛進那個容器。這要求 `MainActivity` 從 `FlutterActivity` 改為 `FlutterFragmentActivity`（Flutter 官方提供、專門給「需要 `FragmentActivity` 的 Android API」使用的子類別），才能取得 `supportFragmentManager`。這個 Fragment-in-PlatformView 模式沒有 Flutter 引擎原生支援（`flutter/flutter#36781` 是尚未解決的 feature request），但已有實際上線的參考實作（[Notalib/flutter_readium](https://github.com/Notalib/flutter_readium)，BSD-3-Clause，本計劃參考其架構但未直接複製其程式碼）採用完全相同的手法：容器 View + 對 Activity 的 `supportFragmentManager` 直接操作。

**技術棧：** Flutter（Dart）、Kotlin、Readium `kotlin-toolkit` 3.3.0（`readium-shared`、`readium-streamer`、`readium-navigator` 三個模組）、`kotlinx-coroutines-android` 1.11.0、`androidx.fragment:fragment-ktx` 1.8.9、`com.android.tools:desugar_jdk_libs` 2.1.5、`integration_test`、`path_provider`（Issue 3 已加入，本工單沿用）。

## ⚠️ 執行前環境確認事項

撰寫本計劃時，已確認有 1 台 Android 裝置連線（`flutter devices` 列出 `9491G` / `3CEF42ECD491687` / Android 15 / API 35）。本計劃所有 `integration_test` 步驟都必須在真實 Android 裝置/模擬器上執行才能驗證——**執行本計劃前，請先用 `flutter devices` 確認裝置仍連線**，否則 Task 2 的驗證步驟無法通過。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`（Issue 1 已建立）。
- Platform channel 契約須與 `spec.md` 完全一致，且與 Issue 3 的 `PdfReaderView` 對稱：`openBook(path: String) -> void`（Flutter → 原生）、`onPageRendered() -> void`（原生 → Flutter）、`onError(message: String) -> void`（原生 → Flutter）。
- 本工單只渲染 EPUB 書籍的**起始位置**（對應 `spec.md` 對 `ReaderScreen` 的定義：「渲染該書第 1 頁」；Readium 的 `initialLocator = null` 即代表從頭開始），不實作換頁 UI、劃線/備註、字型/邊距等偏好設定——那些屬於 `epic-2`/`epic-3`/`epic-6` 的範圍。
- 本工單**不得**引入 Readium 的 DRM（`readium-lcp`）或 OPDS（`readium-opds`）模組——elinkBook 明確排除 DRM 解除（見 `docs/prd.md`「明確排除範圍」），本工單也用不到 OPDS 目錄。
- 本工單**不得**修改 `ReaderScreen` 的分派邏輯（那是 Issue 5 的範圍）——本工單的 `EpubReaderView` 是獨立建構、獨立測試的元件，與 Issue 3 的 `PdfReaderView` 一樣。
- 所有畫面上的使用者可見文字（例如錯誤訊息）須為正體中文。
- **`minSdk` 須從 21 提高到 23**：Readium `kotlin-toolkit` 3.3.0 本身要求 `minSdk 23`（見 Task 1 Step 2）。這不違反專案規定——`docs/adr/0001-mobile-architecture.md`/`CLAUDE.md` 的限制是「不得將 `minSdk` 限制在比 API 30 更新的門檻」，23 仍然遠低於 30，只是把目前刻意設定的下限（21）提高到符合這個新相依套件的實際下限，並未違反「涵蓋範圍須夠寬」的政策意圖。
- **Kotlin Gradle plugin 版本須從 `2.2.20` 提高到 `2.3.20`**：Readium 3.3.0 本身以 Kotlin 2.3.20 建置（見 Task 1 Step 1），為避免「函式庫用比目前專案更新的 Kotlin 編譯」造成的 metadata 不相容錯誤，需同步跟進。
- `MainActivity` 須從 `io.flutter.embedding.android.FlutterActivity` 改為 `io.flutter.embedding.android.FlutterFragmentActivity`（見 Task 2 Step 1）——這是 Flutter 官方文件明確記載的作法，用於「需要 `FragmentActivity` 的 Android API」，不影響 Issue 3 的 `PdfReaderView`（純 `ImageView`，不涉及 Fragment）。
- 本工單範圍不含把 `EpubNavigatorFragment` 的換頁/選字/劃線功能接上 Flutter——本工單只驗證「給一個 EPUB 檔案路徑，能渲染出起始頁」這一件事。

---

### Task 1：Readium 依賴、專案設定調整、範例 EPUB 測試檔

**Files:**
- Modify: `app/android/settings.gradle.kts`
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/pubspec.yaml`
- Create: `app/test/fixtures/sample.epub`

**Interfaces:**
- Consumes: 無（純設定變更 + 測試檔案，獨立於 Issue 1/2/3 的程式碼介面）
- Produces: 已提交版本控制的 `app/test/fixtures/sample.epub` 測試檔，供 Task 2 使用；已驗證可正確解析所有 Readium 依賴、且專案仍可建置的 Gradle 設定，供 Task 2 使用。

- [ ] **Step 1：Kotlin Gradle plugin 版本升級至 2.3.20**

開啟 `app/android/settings.gradle.kts`，把：

```kotlin
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
```

改為：

```kotlin
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
```

- [ ] **Step 2：`minSdk` 提高至 23 + 啟用 core library desugaring**

開啟 `app/android/app/build.gradle.kts`，把 `defaultConfig` 區塊中的：

```kotlin
        minSdk = 21
```

改為：

```kotlin
        minSdk = 23
```

同一個檔案的 `android { ... }` 區塊中，在 `compileOptions { ... }` 內新增 `isCoreLibraryDesugaringEnabled = true`，使該區塊變為：

```kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
```

（Readium 的 README 明確要求消費端專案啟用 core library desugaring，因為它使用了需要 desugar 才能在 `minSdk 23` 上執行的 Java API。）

- [ ] **Step 3：新增 Readium 與相關依賴**

同一個檔案 `app/android/app/build.gradle.kts`，在 `flutter { source = "../.." }` 區塊**之前**新增 `dependencies { ... }` 區塊（若檔案已有 `dependencies` 區塊則合併進去）：

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
}
```

修改後 `app/android/app/build.gradle.kts` 的完整內容應為：

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.ugotit.elinkbook"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.ugotit.elinkbook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
}

flutter {
    source = "../.."
}
```

`allprojects { repositories { google(); mavenCentral() } }`（`app/android/build.gradle.kts`）已涵蓋 Readium 所需的 Maven Central，不需新增額外的 repository。

- [ ] **Step 4：產生範例 EPUB 測試檔**

Run（於 `app/` 目錄下，需要 Python 3；本機已確認可用）：

```bash
python3 -c "
import zipfile

container_xml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">
  <rootfiles>
    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>
  </rootfiles>
</container>
'''

content_opf = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"pub-id\">
  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
    <dc:identifier id=\"pub-id\">urn:uuid:00000000-0000-0000-0000-000000000001</dc:identifier>
    <dc:title>elinkBook 範例 EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property=\"dcterms:modified\">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>
    <item id=\"chapter1\" href=\"chapter1.xhtml\" media-type=\"application/xhtml+xml\"/>
  </manifest>
  <spine>
    <itemref idref=\"chapter1\"/>
  </spine>
</package>
'''

nav_xhtml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">
<head><title>目錄</title></head>
<body>
  <nav epub:type=\"toc\">
    <ol>
      <li><a href=\"chapter1.xhtml\">第一章</a></li>
    </ol>
  </nav>
</body>
</html>
'''

chapter1_xhtml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head><title>第一章</title></head>
<body>
  <h1>第一章</h1>
  <p>這是 elinkBook 用於 integration_test 的範例 EPUB 內容。</p>
</body>
</html>
'''

with zipfile.ZipFile('test/fixtures/sample.epub', 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', container_xml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/content.opf', content_opf, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/nav.xhtml', nav_xhtml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/chapter1.xhtml', chapter1_xhtml, zipfile.ZIP_DEFLATED)

print('wrote sample.epub')
"
```

Expected: 印出 `wrote sample.epub`，且 `app/test/fixtures/sample.epub` 檔案已建立（單章、EPUB3 格式、`zh-TW` 語言的最小合法 EPUB）。`.gitattributes` 已在 Issue 3 把 `*.epub` 標記為 binary（見 `.gitattributes` 內容），因此不需要重複處理 `core.autocrlf` 造成的二進位內容損毀風險。

- [ ] **Step 5：將測試檔宣告為 Flutter asset**

開啟 `app/pubspec.yaml`，把現有的：

```yaml
  assets:
    - test/fixtures/sample.pdf
```

改為：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
```

- [ ] **Step 6：安裝相依套件**

Run（於 `app/` 目錄下）：

```bash
flutter pub get
```

Expected: 成功解析並安裝所有套件，無錯誤。

- [ ] **Step 7：驗證 Gradle 可正確解析所有新依賴並建置成功**

Run（於 `app/` 目錄下）：

```bash
flutter build apk --debug
```

Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`。這一步驟在還沒有寫任何 Readium 相關 Kotlin 程式碼的情況下執行，目的是把「Gradle 座標/版本/`minSdk`/Kotlin 版本相容性」問題與 Task 2 的原生程式碼問題分開驗證。

**⚠️ 已知的建置系統行為（根本原因，非單純巧合）**：Flutter 工具鏈內建一個一次性的專案遷移工具（`flutter_tools/lib/src/android/migrations/min_sdk_version_migration.dart`），只要偵測到 `build.gradle.kts` 裡有 `minSdk = <16 到 23 之間的任何整數>` 這種寫法，就會無條件把它改寫成 `minSdk = flutter.minSdkVersion`——而 `23` 剛好落在這個 16–23 的觸發區間內，所以每次執行 `flutter build`/`flutter test` 都會被改寫，不是只發生一次。`flutter.minSdkVersion` 這個值本身是寫死在目前安裝的 Flutter SDK 版本裡的常數（`flutter_tools/gradle/.../FlutterExtension.kt` 的 `val minSdkVersion: Int = ...`），**不是**從 `local.properties` 或任何專案設定檔讀取的，所以無法透過調整 `local.properties` 來讓 Flutter 跳過這個改寫（不同 Flutter SDK 版本這個常數的值也可能不同，若放任被改寫，等於把 `minSdk` 下限交給「當下開發者安裝的 Flutter SDK 版本」決定，可能低於 Readium 要求的 23）。因此每次執行建置/測試指令後，須用 `git diff app/android/app/build.gradle.kts` 確認 `minSdk` 欄位是否被自動改寫；若被改寫，用 `git checkout -- app/android/app/build.gradle.kts` 還原後重新套用 Step 2 與 Step 3 的變更再繼續（或者暫不還原、直接照著本步驟走完，最後在 Step 8 commit 前再檢查一次並還原）。

- [ ] **Step 8：Commit**

```bash
git add app/android/settings.gradle.kts app/android/app/build.gradle.kts app/pubspec.yaml app/pubspec.lock app/test/fixtures/sample.epub
git commit -m "Add Readium kotlin-toolkit dependencies and sample EPUB fixture"
```

---

### Task 2：實作 `EpubReaderView`（原生 Kotlin + Flutter widget）並驗證兩項 `integration_test`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderViewFactory.kt`
- Create: `app/lib/reader/epub_reader_view.dart`
- Create: `app/integration_test/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: `app/test/fixtures/sample.epub`（Task 1 產出）、Readium `kotlin-toolkit` 3.3.0 的 `AssetRetriever`/`DefaultPublicationParser`/`PublicationOpener`/`EpubNavigatorFactory`/`EpubNavigatorFragment`（`org.readium.r2.shared.util.asset`、`org.readium.r2.streamer`、`org.readium.r2.streamer.parser`、`org.readium.r2.navigator.epub` 套件）。
- Produces: `EpubReaderView({required String filePath, required VoidCallback onPageRendered, required ValueChanged<String> onError})`（Flutter `StatefulWidget`），供 Issue 5（`ReaderScreen` 端到端整合，把佔位視圖換成本元件）使用。原生端註冊的 `PlatformView` 類型字串固定為 `"cc.ugotit.elinkbook/epub_reader_view"`，method channel 名稱固定為 `"cc.ugotit.elinkbook/epub_reader_view_$id"`（`$id` 為 Flutter 指派的 platform view 實例 id）——與 Issue 3 的 `PdfReaderView` 命名慣例對稱。

- [ ] **Step 1：`MainActivity` 改為 `FlutterFragmentActivity`、處理 process-death 還原、並註冊 `EpubReaderViewFactory`**

將 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 整份內容改為：

```kotlin
package cc.ugotit.elinkbook

import android.os.Bundle
import androidx.fragment.app.commitNow
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import org.readium.r2.navigator.epub.EpubNavigatorFragment

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 在 process death 後重建這個 Activity 時，會嘗試用已儲存的
        // FragmentManager 狀態還原先前掛載的 EpubNavigatorFragment；但它的建構子是
        // internal，且用來建立它的 EpubNavigatorFactory（綁定特定 Publication）已隨
        // 行程一起消失，若不處理，預設的 FragmentFactory 會因無法呼叫該建構子而崩潰。
        // 依 Readium 官方文件建議：先裝一個「dummy」FragmentFactory 讓還原程序本身不會
        // 崩潰；還原完成後，若真的有 EpubNavigatorFragment 被還原出來，必須在它進入
        // onResume() 之前立刻移除（dummy fragment 一旦 onResume() 就會主動拋出
        // RestorationNotSupportedException）。這裡刻意不是「整個 Activity 一律
        // finish()」——本 App 只有單一 Activity，涵蓋書架/設定等所有畫面，process
        // death 後重建時不見得有任何 EpubReaderView 曾經存在，不應該無條件關閉整個
        // App；只有在真的偵測到被還原的 EpubNavigatorFragment 時才需要處理。
        supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        super.onCreate(savedInstanceState)
        supportFragmentManager.fragments
            .filterIsInstance<EpubNavigatorFragment>()
            .forEach { restored ->
                supportFragmentManager.commitNow(allowStateLoss = true) { remove(restored) }
            }
    }

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
    }
}
```

（`FlutterFragmentActivity` 是 Flutter 官方提供、繼承 `androidx.fragment.app.FragmentActivity` 的子類別，用於需要 `supportFragmentManager` 的情境——本工單需要它來掛載 `EpubNavigatorFragment`。這不影響 Issue 3 的 `PdfReaderView`，因為它只用 `ImageView`，不涉及 Fragment。`onCreate` 對每一次啟動都會裝上 dummy factory，但只有 `savedInstanceState` 真的帶有先前掛載的 `EpubNavigatorFragment` 時，`filterIsInstance<EpubNavigatorFragment>()` 才會找到東西並移除；一般冷啟動或行程只是被切到背景而未被殺掉的情況下，這段程式碼實質上是無操作。）

- [ ] **Step 2：實作 `EpubReaderViewFactory`（Kotlin）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderViewFactory.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class EpubReaderViewFactory(
    private val activity: FragmentActivity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        return EpubReaderView(context, activity, id, messenger)
    }
}
```

- [ ] **Step 3：實作原生 `EpubReaderView`（Kotlin）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.add
import androidx.fragment.app.commitNow
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/**
 * 包裝 Readium kotlin-toolkit 的原生 PlatformView。透過 MethodChannel 接收 Flutter 的
 * openBook 呼叫，成功則呼叫 onPageRendered，失敗則呼叫 onError(message)。
 *
 * EpubNavigatorFragment 的建構子是 internal（只能透過 Readium 自己的 FragmentFactory
 * 建立），因此本類別把它掛載到 Activity 層級的 supportFragmentManager，而不是自己直接
 * new 一個實例——getView() 回傳的是一個空的容器 View，Fragment 是非同步解析完
 * Publication 之後才用 FragmentTransaction 掛進這個容器的。
 *
 * `activity.supportFragmentManager.fragmentFactory` 是 Activity 層級的全域屬性，本類別
 * 在 attachNavigator() 覆寫它之前，會先保留原本的值，並在 dispose() 還原——避免影響
 * Activity 上其他 Fragment（例如未來若同時存在其他自訂 FragmentFactory 使用者）。本
 * App 目前的畫面設計（見 spec.md 的單一 seam）同一時間只會顯示一個原生閱讀 view，因此
 * 這個「保留一份、還原一份」的簡單作法已足夠；並非要處理多個 EpubReaderView 同時存在
 * 互相覆寫的通用情境（目前用不到，YAGNI）。
 */
class EpubReaderView(
    private val context: Context,
    private val activity: FragmentActivity,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView,
    MethodChannel.MethodCallHandler,
    EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener {

    private val containerId = View.generateViewId()
    private val container = FrameLayout(context).apply { this.id = containerId }
    private val channel = MethodChannel(messenger, "cc.ugotit.elinkbook/epub_reader_view_$id")
    private val fragmentTag = "cc.ugotit.elinkbook.epub_reader_view_$id"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val previousFragmentFactory = activity.supportFragmentManager.fragmentFactory
    private var publication: Publication? = null
    private var pageReported = false
    private var isDisposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openBook(path: String?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
            val httpClient = DefaultHttpClient()
            val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
            val asset = assetRetriever.retrieve(File(path)).getOrElse {
                channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                return@launch
            }
            val publicationParser = DefaultPublicationParser(
                context,
                httpClient,
                assetRetriever,
                pdfFactory = null,
            )
            val publicationOpener = PublicationOpener(publicationParser)
            val openedPublication = publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                channel.invokeMethod("onError", "無法解析 EPUB 檔案：${it.message}")
                return@launch
            }
            // openBook 是非同步流程，Flutter 端有可能在這段 await 期間就把這個
            // PlatformView 銷毀（dispose() 已執行）。scope.cancel() 只能取消協程本身，
            // 但 attachNavigator() 內完全是同步呼叫（沒有 suspend 呼叫點），協程機制
            // 不會在這中間自動檢查取消狀態——若不手動檢查，可能會把 Fragment 掛到一個
            // 已經從畫面移除、id 已不存在於 view 樹中的容器，導致例外或資源洩漏。
            if (isDisposed) {
                openedPublication.close()
                return@launch
            }
            attachNavigator(openedPublication)
        }
    }

    private fun attachNavigator(openedPublication: Publication) {
        publication = openedPublication
        val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
        activity.supportFragmentManager.fragmentFactory =
            navigatorFactory.createFragmentFactory(
                initialLocator = null,
                listener = this,
                paginationListener = this,
            )
        activity.supportFragmentManager.commitNow {
            add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
        }
    }

    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
        }
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {}

    override fun onExternalLinkActivated(url: AbsoluteUrl) {}

    override fun onResourceLoadFailed(href: Url, error: ReadError) {
        // 起始頁尚未成功渲染前的資源載入失敗才回報 onError；起始頁渲染成功後，使用者
        // 尚未翻到的其他頁面資源失敗不應該讓已經成功的畫面被判定為失敗。
        if (!pageReported) {
            channel.invokeMethod("onError", "頁面資源載入失敗：${error.message}")
        }
    }

    override fun dispose() {
        isDisposed = true
        scope.cancel()
        val fragment = activity.supportFragmentManager.findFragmentByTag(fragmentTag)
        if (fragment != null) {
            activity.supportFragmentManager.commitNow(allowStateLoss = true) { remove(fragment) }
        }
        activity.supportFragmentManager.fragmentFactory = previousFragmentFactory
        publication?.close()
        publication = null
    }
}
```

- [ ] **Step 4：實作 Flutter 端 `EpubReaderView` widget**

建立 `app/lib/reader/epub_reader_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
```

- [ ] **Step 5：撰寫兩項 `integration_test`**

建立 `app/integration_test/epub_reader_view_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// Readium 的 AssetRetriever 需要真實的裝置檔案系統路徑，不能直接讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效 EPUB 檔案觸發 onPageRendered', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    // 清掉暫存目錄裡複製出來的測試檔，避免裝置上的暫存空間隨著測試執行次數累積。
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 用 Completer 等待原生端的非同步 callback，callback 一觸發就立刻往下走，
    // 不需要固定等待一段時間。注意：pumpAndSettle 的參數是「每次 pump 之間
    // 的間隔」，不是「總等待時間」，不能拿來當作 timeout 使用。
    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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

  testWidgets('開啟不存在的檔案路徑觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });
}
```

（timeout 設為 10 秒而非 Issue 3 的 5 秒——Readium 需要非同步解析 EPUB 套件結構並啟動一個 WebView 導覽器，比 `PdfRenderer` 直接同步渲染點陣圖要花更多時間，10 秒是留給裝置效能差異的合理餘裕，不是隨意加大。）

- [ ] **Step 6：於真實裝置/模擬器上執行兩項 `integration_test`**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：

```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected: `All tests passed!`（兩項測試皆通過：有效 EPUB 觸發 `onPageRendered`；不存在的路徑觸發 `onError`）。

**⚠️ 執行前檢查**：同 Task 1 Step 7 記錄的根本原因（Flutter 的一次性遷移工具會對 `minSdk = 16~23` 的寫法無條件改寫，`23` 剛好在觸發區間內），執行完 `flutter test` 後，用 `git diff app/android/app/build.gradle.kts` 確認 `minSdk` 是否被自動改寫成 `flutter.minSdkVersion`；若是，記得在 Step 9 commit 前還原為明確的 `23`。

- [ ] **Step 7：重新執行 Issue 3 的 `PdfReaderView` 測試與 smoke test，確認無回歸**

`MainActivity` 從 `FlutterActivity` 改為 `FlutterFragmentActivity`，且本工單會把一個自訂 `FragmentFactory` 設到 Activity 層級的 `supportFragmentManager`——這兩個改動都可能影響 Issue 3 已經驗證過的 `PdfReaderView`（雖然它本身不使用 Fragment，但共用同一個 `MainActivity`/`FragmentManager`）。

Run：

```bash
flutter test integration_test/smoke_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```

Expected: 兩個指令皆為 `All tests passed!`，確認 `MainActivity` 改為 `FlutterFragmentActivity` 沒有破壞 Issue 3 的既有整合。

- [ ] **Step 8：靜態分析確認無警告**

Run（於 `app/` 目錄下）：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 9：Commit**

先確認 `minSdk` 仍為 `23`（`git diff app/android/app/build.gradle.kts` 應無差異，或差異只有你預期之外的自動改寫並已還原），再執行：

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderViewFactory.kt app/lib/reader/epub_reader_view.dart app/integration_test/epub_reader_view_test.dart
git commit -m "Add EpubReaderView native PlatformView with Readium kotlin-toolkit integration"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：對應 `issues.md` Issue 4 的兩項 `integration_test` 要求（有效 EPUB 觸發 `onPageRendered`、不存在/損毀檔案觸發 `onError`）與兩項驗收標準（範例 EPUB 已提交版本控制、兩項 `integration_test` 皆通過）均已對應到 Task 1（依賴與 fixture）與 Task 2（實作與驗證）。`spec.md` 定義的 platform channel 契約（`openBook`/`onPageRendered`/`onError`）已逐字實作於原生與 Flutter 兩側，命名慣例與 Issue 3 的 `PdfReaderView` 完全對稱。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出；Readium 3.3.0 的 Gradle 座標、`minSdk`/Kotlin 版本需求、`AssetRetriever`/`PublicationOpener`/`EpubNavigatorFactory`/`EpubNavigatorFragment` 的確切 import 路徑與方法簽章，皆透過直接讀取 `readium/kotlin-toolkit` GitHub repo 於 `3.3.0` tag 的原始碼逐一查證（而非僅信任可能混用不同版本 API 的網路摘要），詳見下方「外部函式庫查證紀錄」。`<device-id>` 是執行時才能得知的真實環境參數，已於步驟中註明替換方式。
- **型別/命名一致性**：`EpubReaderView`、`filePath`、`onPageRendered`、`onError` 在 Flutter 與 Kotlin 兩側、以及與 `spec.md` 定義的介面保持一致，並與 Issue 3 的 `PdfReaderView` 對稱；`PlatformView` 類型字串（`cc.ugotit.elinkbook/epub_reader_view`）與 method channel 命名規則（`cc.ugotit.elinkbook/epub_reader_view_$id`）已在 Task 2 的 Interfaces 區塊中明確記錄，供 Issue 5（`ReaderScreen` 整合）參考。
- **環境缺口揭露**：本計劃在開頭記錄了撰寫當下已確認有裝置連線；仍保留「執行前請重新確認裝置連線」的提醒，因為裝置連線狀態可能在執行計劃時已改變。
- **回歸風險揭露**：`MainActivity` 改為 `FlutterFragmentActivity`、且對 Activity 層級 `supportFragmentManager` 設定自訂 `FragmentFactory`（含 process-death 還原時的處理），是本工單對既有程式碼影響最大的改動。Task 2 Step 7 明確要求重跑 Issue 3 的兩個 `integration_test` 作為回歸檢查，而不是只驗證新功能本身；`EpubReaderView` 也在 `dispose()` 還原自己覆寫前的 `fragmentFactory`，降低對 Activity 層級狀態的持久性副作用。
- **建置系統已知行為揭露**：延續 Issue 3 已發現的「`flutter build`/`flutter test` 會自動把 `minSdk` 改寫成 `flutter.minSdkVersion`」現象，本計劃在 Task 1 Step 7 與 Task 2 Step 6 都明確提醒要检查並視需要還原，避免意外把不符合專案政策的 `minSdk` 設定提交進版本控制。

## 外部函式庫查證紀錄（Readium `kotlin-toolkit` 3.3.0）

撰寫本計劃前，針對 Readium `kotlin-toolkit` 這個本程式碼庫從未使用過的外部函式庫，透過直接讀取其 GitHub repo 於 `3.3.0` tag 的原始碼（而非僅信任可能混用 2.x/3.x 不同世代 API 的第三方摘要）查證以下事實：

- **版本與需求**：最新穩定版 `3.3.0`（2026-06-02 發布）；`minSdk 23`、`compileSdk 36`（與本專案透過 `flutter.compileSdkVersion` 取得的 36 相同，不需覆寫）、Kotlin `2.3.20`。
- **API 世代確認**：Readium 在 `3.0.0-alpha.1` 已將 `Streamer`/`FileAsset`（2.x 舊 API，仍常見於網路上的教學文章/討論串）棄用，改為 `AssetRetriever`/`PublicationOpener`/`DefaultPublicationParser`（3.x 現行 API）。本計劃全程採用後者。
- **`Try<Success, Failure>` 錯誤處理型別**：`getOrElse { }`、`onSuccess { }`、`onFailure { }`、`fold { }`、`getOrNull()` 皆為目前 API 的真實方法，已直接對照 `Try.kt` 原始碼確認。
- **`EpubNavigatorFragment` 建構子為 `internal`**：只能透過 `EpubNavigatorFactory.createFragmentFactory(...)` 回傳的 `FragmentFactory` 建立，不能直接 `new`。
- **`EpubNavigatorFragment.Listener`**：實際上是 `OverflowableNavigator.Listener`/`HyperlinkNavigator.Listener`/`Navigator.Listener` 三層繼承組成的聯集介面；攤平後只有 `onExternalLinkActivated(url: AbsoluteUrl)` 是必須覆寫的抽象方法，`shouldFollowInternalLink`/`onResourceLoadFailed`/`onJumpToLocator` 皆有預設（no-op 或回傳 `true`）實作。
- **`PaginationListener.onPageLoaded()`**：確認是「WebView 已完成載入該頁資源」的真實訊號，是本計劃拿來對應 `onPageRendered` 契約的依據。
- **Fragment-in-`PlatformView` 模式**：Flutter 引擎本身不原生支援在 `PlatformView` 中託管 Fragment（`flutter/flutter#36781` 為尚未解決的 feature request），但已有實際上線的參考實作（[Notalib/flutter_readium](https://github.com/Notalib/flutter_readium)）採用與本計劃相同的手法（容器 View + 直接操作 Activity 的 `supportFragmentManager`），確認這是已驗證可行、而非本計劃自創的做法。
- **`Publication.close()`**：`Publication`覆寫了 `close()`（關閉底層 `container` 與 `services`），但 `EpubNavigatorFragment` 自己並不會呼叫它——確認為消費端（本計劃的 `EpubReaderView`）自己的責任。
- **`EpubNavigatorFragment.createDummyFactory()`**：確認為 Readium 官方文件記載、真實存在的 API，專門處理 Activity 因 process death 被重建、但已無 `Publication`/`NavigatorFactory` 可還原真正 Fragment 的情境；官方範例本身是寫在一個專用 reader Fragment 的 `onCreate()` 裡，並在 `super.onCreate()` 後立刻 `requireActivity().finish()`——本計劃把它改寫成適合單一 Activity 涵蓋全部畫面（書架/設定/閱讀器共用同一個 `MainActivity`）的版本：只在真的偵測到被還原的 `EpubNavigatorFragment` 時移除該 Fragment，而不是不分青紅皂白 `finish()` 整個 Activity（見下方「文件審查回應紀錄」#1）。

## 文件審查回應紀錄（`review-plan-issue-4.md`）

- **#1.1（Activity 層級 `FragmentFactory` 覆寫的衝突與 process-death 崩潰）**：查證屬實，分兩部分處理：
  - 多實例互相覆寫的風險：查證屬實，但審查建議的 `DelegatingFragmentFactory` 對目前範圍是過度設計——`spec.md` 定義的畫面模型同一時間只會顯示一個原生閱讀 view，不存在多個 `EpubReaderView` 並存互相覆寫的實際情境（YAGNI）。改採更簡單的作法：`EpubReaderView` 建構時保留當下的 `fragmentFactory`，`dispose()` 時還原。
  - process-death 重建崩潰：查證屬實，且 `EpubNavigatorFragment.createDummyFactory()` 確實存在（見上方查證紀錄）。**未採用**審查建議暗示的「還原後直接 `finish()` Activity」——這是 Readium 官方文件給「專用 reader Activity/Fragment」場景的寫法，本 App 只有一個 `MainActivity` 涵蓋所有畫面，無條件 `finish()` 會導致「行程被殺掉後任何一次回到前景」都強制關閉整個 App 重開，即使當下沒有任何書正在被閱讀，屬於不必要的使用體驗損害。改為在 `MainActivity.onCreate()` 中先裝上 dummy factory（避免還原程序本身崩潰），還原完成後只在真的找到被還原的 `EpubNavigatorFragment` 實例時才移除它，其餘情況（例如冷啟動、或行程根本沒有被殺掉）此段程式碼等同無操作。
- **#1.2（非同步 callback 中的生命週期活性檢查缺失）**：查證屬實——`attachNavigator()` 內部沒有任何 suspend 呼叫，Kotlin 協程的取消機制不會在兩個同步陳述式之間自動檢查，因此 `dispose()` 與 `openBook()` 的協程之間確實存在競態。已採納：新增 `isDisposed` 旗標，`dispose()` 設為 `true`；`openBook()` 的協程在拿到 `Publication` 之後、呼叫 `attachNavigator()` 之前檢查此旗標，若已 dispose 則改為關閉剛解析出來的 `Publication` 並直接返回，不嘗試操作已可能不存在的容器。
- **#2.1（`Publication` 資源洩漏）**：查證屬實（見上方查證紀錄，`Publication.close()` 是真實存在且消費端須自行呼叫的方法）。已採納：`EpubReaderView` 新增 `publication` 欄位，`dispose()` 時呼叫 `publication?.close()`。
- **#2.2（`integration_test` 暫存檔案未清理）**：查證合理，已採納，於「開啟有效 EPUB 檔案」測試案例中用 `addTearDown` 刪除暫存檔。附註：Issue 3 的 `pdf_reader_view_test.dart` 有相同的既存缺口，但那份檔案已合併進 `main`，不屬於本次計劃審查修正範圍，若需要補上須另開後續工單處理，不在此逕行變更已合併程式碼。
- **#3.1（`minSdk` 被 Flutter 改寫的「根本解決方案」）**：**未採用**——查證後發現審查建議的機制（透過 `local.properties`/`flutter.minSdkVersion` 設定）技術上不可行：直接讀取本機已安裝的 Flutter SDK 原始碼（`flutter_tools/gradle/.../FlutterExtension.kt`）確認 `minSdkVersion` 是寫死在該 Flutter 版本裡的 Kotlin 常數，並非讀取任何專案設定檔；而實際觸發改寫的是 `flutter_tools/lib/src/android/migrations/min_sdk_version_migration.dart` 這個一次性遷移工具，只要偵測到 `minSdk = <16~23 之間的整數>` 就會無條件改寫成 `minSdk = flutter.minSdkVersion`——`23` 剛好落在這個觸發區間內。已改為在 Task 1 Step 7 與 Task 2 Step 6 的既有提醒中補上這個根本原因說明，讓「為何每次都要檢查並還原」有明確依據，而非只是重複「這是已知行為」的模糊提醒。
