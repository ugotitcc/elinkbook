# Epic 66 Issue 17 驗證報告：Android 建置工具升級（Gradle 9.3.1／AGP 9.1.0）

- **分支**：`chore/epic-66-issue-17-agp9`
- **基準 commit**：`04ab1d94`（前一個 `ae1ebdcc`）
- **日期**：2026-11-16

## 1. 升級前基準（Task 1）

- **Flutter 版本**：
  - `Flutter 3.47.9 • channel [user-branch] • https://github.com/flutter/flutter.git`
  - `Framework • revision c197ca5199 (2026-10-29)` / `Engine • hash 9e025265be (2026-10-27)` / `Tools • Dart 3.13.7 • DevTools 2.60.0`
- **Gradle / AGP 版本**：Gradle 8.14.0 / AGP 8.11.1
- **升級前警告原文**：
  1. `Warning: Flutter support for your project's Gradle version (8.14.0) will soon be dropped. Please upgrade your Gradle version to a version of at least 9.1.0 soon.`
  2. `Warning: Flutter support for your project's Android Gradle Plugin version (Android Gradle Plugin version 8.11.1) will soon be dropped. Please upgrade your Android Gradle Plugin version to a version of at least Android Gradle Plugin version 9.0.1 soon.`
- **升級前 `app-release.apk` 體積**（debug 金鑰簽章，`allowDebugSigning=true`）：`130,144,946` bytes（`124.1MB`）

## 2. 本地修補驗證（Task 2）

- **`file_picker` 11.0.3 本地修補**：複製至 `app/patches/file_picker/`（排除 `example/`、`test/`、`tool/`、`CONTRIBUTING.md`），`android/build.gradle` 固定 `isAgp9OrAbove = false`，`pubspec.lock` 確認轉為 `source: path`、`version: "11.0.3"`。
- **`flutter_inappwebview_android` 1.1.3**：`android/build.gradle` 兩處 `proguard-android.txt` 改為 `proguard-android-optimize.txt`，並更新 `PATCH.md`。
- **`flutter analyze`**：`No issues found!`
- **`flutter build windows --debug`**：成功（`build\windows\x64\runner\Debug\elinkbook.exe`）。 **只在升級前（Gradle 8.14）驗過，Task 3 升級後未重跑**；Gradle／AGP 只影響 Android，風險低，但 `file_picker` 已改為本地路徑副本，合併前建議在任一台 Windows 機再跑一次 `flutter build windows --debug`。
- **`flutter build apk --debug`（Gradle 8.14／AGP 8.11.1）**：成功（`build\app\outputs\flutter-apk\app-debug.apk`），修補向下相容。

## 3. 升級後建置與體積比對（Task 3）

- **版本**：Gradle `9.3.1` / AGP `9.1.0`（保留 `android.builtInKotlin=false`、`android.newDsl=false`、Kotlin `2.3.20`、JDK 17）。
- **`flutter build apk --debug`**：成功（`build\app\outputs\flutter-apk\app-debug.apk`）。「Gradle version (8.14.0)」與「Android Gradle Plugin version 8.11.1」兩則警告均已消失；僅出現預期之「9 個外掛套用 KGP」警告（`desktop_drop, file_picker, flutter_tts, flutter_web_auth_2, package_info_plus, share_plus, shared_preferences_android, url_launcher_android, wakelock_plus`）。
- **`flutter build apk --release` 體積比對**：
  - 升級前：`130,144,946` bytes（`124.1MB`）
  - 升級後：`130,007,095` bytes（`124.0MB`）
  - 差異：`-137,851` bytes（約 `-0.11%`，未超過 ±5%）。
- **正式打包與驗簽（`node tool/build_release.js --target apk|aab`）**：未驗（本機無 `app/android/key.properties`，留給有金鑰的機器驗證）。
- **`U:` 機器建置**：未驗（本對話僅於 `C:` 開發機執行，留待 `U:` 機器 `git pull` 本分支後執行 `flutter build apk --debug` 驗證 `org.gradle.java.home`）。

## 4. 真機與簽章驗證（Task 3–4）

- **一般真機（`adb install -r` 抽測）**：未驗（本對話執行環境 `adb devices` 無已連接 Android 裝置，且本機無 `key.properties` 僅能產出 debug 簽章 release APK）。待使用者於有真機環境安裝測試：啟動、開 EPUB 翻頁與劃線、開 PDF、字典查詞、TTS 朗讀、選檔匯入（`file_picker`）、關於頁建置資訊。
- **舊 WebView 機器（iReader Ocean 4 Plus）**：未驗（無連接裝置且須手動側載 APK，留待使用者測試後決定是否阻擋合併）。

## 5. 最終結論（Task 5）

### 驗收條件盤點

1. **`flutter analyze` 乾淨**：✅ **通過**（`No issues found!`，另 `node tool/check_l10n_hardcoded_strings.js` 亦全數 PASS）。
2. **`flutter build apk --debug` 與 `node tool/build_release.js --target apk|aab` 成功且無 Gradle／AGP 兩則警告**：
   - `flutter build apk --debug`：✅ **通過**（兩則警告均已消失）。
   - `node tool/build_release.js --target apk|aab`：⏸️ **未驗**（本機無 `app/android/key.properties`）。
3. **release APK 升級前後體積比對**：✅ **通過**（`130,144,946` bytes → `130,007,095` bytes，差異 `-137,851` bytes / `-0.11%`，在 ±5% 內；debug 金鑰簽章）。
4. **`adb install -r` 真機抽測（含舊 WebView 機器 iReader Ocean 4 Plus）**：⏸️ **未驗**（本對話環境無連接 Android 實體裝置，留待使用者手動安裝抽測後決定是否阻擋合併）。
5. **`C:` 與 `U:` 兩台開發機各建置一次**：`C:` 開發機 ✅ **通過**；`U:` 開發機 ⏸️ **未驗**（留待 `U:` 機 `git pull` 後執行 `flutter build apk --debug`）。

### 完整單元／Widget 測試紀錄（Task 5 Step 2）

- `flutter test`：5,304 通過、2 略過、3 失敗（皆位於 `test/downloads/download_queue_controller_test.dart`）。**該檔單獨重跑 3 次皆 28/28 全過**（2026-11-16 審查後補驗），只有整批執行才偶發，與 Issue 12、14、18 報告記載的同一現象一致（Issue 14 報告同樣是整批 +5161 ~2 -3、失敗全在此檔）。本 Issue 未修改任何 `app/lib/` 或 `app/test/` 程式碼；但未在升級前的 commit 上整批對照，因此「與本案無關」是依前例與「單獨全過」推論，不是實測對照。

### 已知殘留與後續觀察項目

- **已知殘留**：建置仍印出 9 個外掛套用 KGP 的警告（`desktop_drop`、`file_picker`、`flutter_tts`、`flutter_web_auth_2`、`package_info_plus`、`share_plus`、`shared_preferences_android`、`url_launcher_android`、`wakelock_plus`），未來 Flutter 版本可能變為錯誤。
- **後續觀察**：
  1. `file_picker` 升版（牽動 `win32` 與 `cross_file` 相依鏈，與 Issue 16 關聯）。
  2. Built-in Kotlin 遷移（待上述 9 個外掛全數支援後，才可移除 `android.builtInKotlin=false`／`android.newDsl=false` 與 `patches/file_picker`）。
  3. `ORG_GRADLE_PROJECT_allowDebugSigning=true` 於 bash 環境變數無效之既有行為。
