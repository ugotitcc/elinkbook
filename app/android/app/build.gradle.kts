import groovy.json.JsonSlurper
import java.text.SimpleDateFormat
import java.util.Date

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
