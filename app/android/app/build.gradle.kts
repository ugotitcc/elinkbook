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
