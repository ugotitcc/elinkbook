import groovy.json.JsonSlurper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 建置當下的系統時間，供 BuildConfig.BUILD_TIME 使用（見下方 defaultConfig）。
val buildTimeString: String = SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(Date())

// epic-29-cloud-import Issue 7：雲端服務 OAuth 統一外部設定檔。
//
// 【重要】project.rootDir 依 Gradle 官方語意恆等於「根專案」目錄
// （app/android/，settings.gradle.kts 所在位置），不論從哪個子專案的
// build.gradle.kts 存取皆然——不是「這個子專案自己的目錄」。因此
// project.rootDir.parentFile 等於 app/，下方路徑才會正確解析為
// app/config/cloud_oauth.json。切勿改成 project.projectDir.parentFile
// （那會變成 android/ 而非 app/，靜默指向錯誤路徑）。
val cloudOAuthConfigFile = File(project.rootDir.parentFile, "config/cloud_oauth.json")
val cloudOAuthExampleFile = File(project.rootDir.parentFile, "config/cloud_oauth.example.json")
val cloudOAuthTargetFile =
    if (cloudOAuthConfigFile.exists()) cloudOAuthConfigFile else cloudOAuthExampleFile

@Suppress("UNCHECKED_CAST")
val cloudOAuthJson: Map<String, Any>? = if (cloudOAuthTargetFile.exists()) {
    try {
        JsonSlurper().parseText(cloudOAuthTargetFile.readText()) as? Map<String, Any>
    } catch (e: Exception) {
        null
    }
} else null

val rawGoogleOAuthClientId = cloudOAuthJson?.get("GOOGLE_OAUTH_CLIENT_ID") as? String
    ?: "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com"
val rawOneDriveOAuthClientId = cloudOAuthJson?.get("ONEDRIVE_OAUTH_CLIENT_ID") as? String
    ?: "YOUR_ONEDRIVE_OAUTH_CLIENT_ID"

// 下列兩條推導公式必須與 app/lib/cloud_import/cloud_oauth_config.dart 內
// CloudOAuthConfig.googleRedirectScheme／oneDriveRedirectScheme 完全一致
// ——Dart 編譯期常數無法被這份 Gradle 建置腳本讀取，兩處各自獨立實作，
// 修改其中一處務必同步修改另一處。
val googleOAuthScheme =
    "com.googleusercontent.apps." + rawGoogleOAuthClientId.replace(".apps.googleusercontent.com", "")
val oneDriveOAuthScheme = "msal$rawOneDriveOAuthClientId"

// epic-52-play-release Issue 1：release 建置的上傳金鑰設定。
//
// 讀取 app/android/key.properties（rootProject 是 app/android/）。這個檔案
// 含密碼，已由 app/android/.gitignore 排除，不進版控；樣板見
// key.properties.example。三種情況：
// 1. 檔案不存在：release 退回 debug 簽章並印出警告，讓沒有金鑰的環境
//    （例如只跑測試）仍能執行 `flutter run --release`。
// 2. 檔案存在但欄位缺少或空白：直接讓建置失敗。這代表發布者想正式簽章
//    卻設定錯了，不能默默改用 debug 簽章，否則上傳到 Play 才會被拒收。
// 3. 檔案存在且欄位齊全：release 用上傳金鑰簽章（見下方 signingConfigs）。
//
// 用 UTF-8 Reader 讀檔：Properties.load(InputStream) 固定用 ISO-8859-1 解碼，
// 路徑含中文時會變成亂碼。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties: Properties? = if (keystorePropertiesFile.isFile) {
    Properties().apply { keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) } }
} else null

if (keystoreProperties != null) {
    // 只有空白的值也當成缺少，避免拿空白字串當密碼。
    val missingKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missingKeys.isNotEmpty()) {
        throw GradleException(
            "release 簽章設定不完整：${keystorePropertiesFile.absolutePath} 缺少欄位 " +
                "${missingKeys.joinToString("、")}。" +
                "這個檔案存在時，4 個欄位都必須填寫。" +
                "請參考 key.properties.example 補齊欄位；不打算正式簽章時，直接刪除這個檔案。"
        )
    }
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

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (keystoreProperties != null) {
            create("release") {
                // project.file() 以 app/android/app/ 為基準解析相對路徑，所以
                // key.properties 的 storeFile 規定寫絕對路徑。
                // Properties 只會去掉值前面的空白，後面的空白要自己去掉。
                // 密碼不做 trim，因為空白可能是密碼的一部分。
                val uploadKeystore = project.file(keystoreProperties.getProperty("storeFile").trim())
                if (!uploadKeystore.exists()) {
                    throw GradleException(
                        "找不到上傳金鑰檔：${uploadKeystore.absolutePath}。" +
                            "key.properties 的 storeFile 指向的檔案不存在。" +
                            "請改成金鑰檔的絕對路徑，並使用正斜線 /（例如 C:/Users/huthief/.android-keys/elinkbook-upload.jks）。"
                    )
                }
                storeFile = uploadKeystore
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias").trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.ugotit.elinkbook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 每次執行 Gradle 建置當下的系統時間，供「關於」頁面顯示，方便真機測試時
        // 確認手上安裝的是哪一次建置（見 docs/epics/epic-3-fonts-layout/issues.md
        // Issue 6 追加需求）。
        buildConfigField("String", "BUILD_TIME", "\"$buildTimeString\"")

        // epic-29-cloud-import Issue 7：自動將 app/config/cloud_oauth.json
        // 推導出的 OAuth redirect scheme 注入 AndroidManifest.xml 的
        // ${googleOAuthScheme}／${oneDriveOAuthScheme} 佔位符。
        manifestPlaceholders["googleOAuthScheme"] = googleOAuthScheme
        manifestPlaceholders["oneDriveOAuthScheme"] = oneDriveOAuthScheme
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties != null) {
                signingConfigs.getByName("release")
            } else {
                // 用 quiet 層級：flutter build 在非 verbose 模式會帶 -q 呼叫 Gradle，
                // warn 層級的訊息會被隱藏，quiet 層級才看得到。
                project.logger.quiet(
                    "警告：找不到 ${keystorePropertiesFile.absolutePath}，release 建置改用 debug 金鑰簽章。" +
                        "這個版本不能上傳到 Google Play。" +
                        "要正式發布時，請依 docs/research/google_play_release_sop.md 第 1.3 節建立 key.properties。"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    // epic-17-epub-render-migration Issue 3：FoliateEpubReaderView 的
    // WebViewAssetLoader 與自訂 PathHandler，版本比照 Issue 1 Spike harness
    // 已驗證可用的版本，見 plans/plan-issue-1.md Global Constraints。
    implementation("androidx.webkit:webkit:1.16.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}

flutter {
    source = "../.."
}
