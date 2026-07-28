# ADR 0015：全螢幕模式改用原生 `WindowInsetsControllerCompat`，不用 Flutter `SystemChrome`

## 狀態

已採納

## 背景

`epic-19-shelf-reading-enhance` Issue 1（全螢幕模式）原始設計（`spec.md` 初版）是純 Dart 呼叫 `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` 隱藏 Android 系統狀態列/導覽列，比照既有 `_applyScreenOrientation()`/`SystemChrome.setPreferredOrientations()` 的既有寫法。

撰寫 `plan-issue-1.md` 前查證 Flutter SDK（本專案目前安裝版本 3.41.9）`system_chrome.dart:601-608` 官方文件註解：

> 「若 App 的 `targetSdk` 為 API 35，`SystemUiMode.edgeToEdge` 會變成強制預設值，設定其他 `SystemUiMode` 除非額外做遷移否則不會生效；若 `targetSdk` 為 API 36 以上，則完全沒有退出 `edgeToEdge` 的方法，呼叫其他模式一律被忽略。」

交叉核對本專案 `app/android/app/build.gradle.kts:16,41`：`compileSdk`/`targetSdk` 皆直接吃 `flutter.compileSdkVersion`/`flutter.targetSdkVersion`（未另外釘死數字），目前安裝的 Flutter SDK 這兩個預設值皆為 **36**。也就是說，原始設計在本專案目前的實際建置設定下**完全不會生效**——不是理論風險，是可直接從 SDK 原始碼與本專案 gradle 設定推導出的必然結果。

## 決策

- **改用 `androidx.core.view.WindowInsetsControllerCompat`**（Android 官方文件建議、繼任已淘汰的 `View.setSystemUiVisibility`/`SystemUiMode` 系列 API 的現代寫法），透過 `WindowCompat.getInsetsController(window, window.decorView)` 取得 controller，呼叫 `hide(WindowInsetsCompat.Type.systemBars())`/`show(...)` 顯示或隱藏系統列，並設定 `systemBarsBehavior = BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`（對應原本 `immersiveSticky` 想要的「邊緣滑入可暫時喚出、放開後自動再收起」行為）。這個 API 運作在原生 `Window`/`View` 層級，**不經過** Flutter 引擎的 `SystemUiMode` 抽象層，因此不受本 ADR「背景」段落所述的 `targetSdk` 限制。
- **新增 `elinkbook/fullscreen` platform channel**（`MainActivity.configureFlutterEngine()` 內註冊，比照既有 `elinkbook/volume_key`／`elinkbook/app_info` 頻道慣例），單一方法 `setEnabled(bool)`，Dart 端 `ReaderScreen._applySystemUiMode()` 呼叫。
- **`app/android/app/build.gradle.kts` 明確新增 `androidx.core:core-ktx` 依賴**（`WindowCompat`/`WindowInsetsControllerCompat`/`WindowInsetsCompat` 所在套件）——雖然既有 `androidx.fragment:fragment-ktx:1.8.9` 已 transitively 帶入相容版本，但明確宣告版本比依賴未宣告的傳遞依賴更穩健，比照本檔案其餘依賴皆明確宣告版本號的既有慣例。
- **不影響 `compileSdk`/`targetSdk` 設定**——維持 Flutter 預設值（目前為 36），不為了這個單一功能而調整全專案的建置設定。

## 後果

- 全螢幕模式的實作需要新增原生 Kotlin 程式碼（`MainActivity.kt`），不再是純 Dart 端修改，比照本專案既有的「Flutter 內建 API 不足時新增原生 platform channel」慣例（例如音量鍵攔截、資料夾選取器、PDF/EPUB 原生渲染皆是同一套模式）。
- `docs/epics/epic-19-shelf-reading-enhance/design.md`／`spec.md`／`issues.md` 對 Issue 1（全螢幕模式）的模組/介面描述已同步修正為本 ADR 的機制。
- 未來若 Flutter 官方針對 API 36+ 提供新的退出 edge-to-edge 機制（例如新增的遷移旗標），可評估是否改回純 Dart 方案；在此之前，`WindowInsetsControllerCompat` 是本專案唯一已驗證可行的路徑。
- 此決策範圍僅限「全螢幕模式」這一個功能的系統列控制機制，不影響 App 其餘既有的 `SystemChrome` 用法（`setPreferredOrientations` 用於螢幕方向鎖定，不受此限制影響，繼續維持原樣）。

## 曾考慮的替代方案

- **調降 `compileSdk`/`targetSdk` 至 34 或 35，讓 Flutter 原生 `SystemChrome.setEnabledSystemUIMode` 照舊生效**：技術上可行，但影響範圍是全專案的建置設定（非本功能專屬），且會讓專案往後所有既有/未來功能都停留在較舊的 `targetSdk` 行為，經與人類確認後排除，改採範圍更收斂、只影響本功能的原生 API 方案。
