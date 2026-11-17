# Epic 66 Issue 32 驗證報告：Android 外掛遷移 built-in Kotlin（階段一）

- **分支**：`chore/epic-66-issue-32-kgp-plugins`
- **基準 commit**：`44878df9`（前一個 `fc7dab9a`）
- **實作 commit**：`44c6af70`
- **日期**：2026-11-17

## 1. 升級前基準（Task 1）

- **`app/pubspec.lock` 目標外掛版本**：
  ```yaml
    shared_preferences_android:
      version: "2.4.23"
    url_launcher_android:
      version: "6.3.30"
  ```
- **升級前 `flutter build apk --debug` 警告原文**：
  ```text
  WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): desktop_drop, file_picker, flutter_tts, flutter_web_auth_2, package_info_plus, share_plus, shared_preferences_android, url_launcher_android, wakelock_plus
  Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
  ```
  共 **9 個**外掛：`desktop_drop`、`file_picker`、`flutter_tts`、`flutter_web_auth_2`、`package_info_plus`、`share_plus`、`shared_preferences_android`、`url_launcher_android`、`wakelock_plus`。

## 2. 外掛升級與靜態檢查（Task 2）

- **`flutter pub upgrade shared_preferences_android url_launcher_android` 結果**：
  - `shared_preferences_android`：`2.4.23` → `2.4.28`（註：`2.5.5` 需將間接相依 `jni` 由 `1.0.3` 升至 `1.1.2`；`shared_preferences_android` 自 `2.4.24` 起即已完成 Built-in Kotlin 遷移，升級至 `2.4.28` 不牽動 `jni` 與任何其他套件）。
  - `url_launcher_android`：`6.3.30` → `6.3.33`。
  - `git diff app/pubspec.lock` 逐行核對：僅 `shared_preferences_android`、`url_launcher_android` 與底部 `sdks`（`dart: ">=3.12.0 <4.0.0"`、`flutter: ">=3.44.0"`）變動；`pubspec.yaml` 零變動，且未觸及 `wakelock_plus`、`package_info_plus`、`share_plus`、`desktop_drop`、`file_picker`、`win32`。
- **`app/android/gradle.properties`**：僅第 6 行註解由「仍有 9 個外掛套用 KGP」更新為「仍有 7 個外掛套用 KGP」，`android.builtInKotlin=false`、`android.newDsl=false` 與 `org.gradle.java.home` 皆維持不動。
- **靜態檢查**：
  - `flutter analyze`：`No issues found!`
  - `node tool/check_l10n_hardcoded_strings.js`：全數 `PASS`（342 個檔案、410 個測試檔、58 個 integration 測試檔）。

## 3. 建置與測試驗證（Task 3）

- **Android debug 建置（`flutter build apk --debug`）**：
  - 結果：✅ 成功（`build\app\outputs\flutter-apk\app-debug.apk`）。
  - 升級後 KGP 警告原文：
    ```text
    WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): desktop_drop, file_picker, flutter_tts, flutter_web_auth_2, package_info_plus, share_plus, wakelock_plus
    Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
    ```
  - 核對結果：由 **9 個降為 7 個**（`shared_preferences_android` 與 `url_launcher_android` 已不再出現於警告清單）。
- **Android release 建置（`flutter build apk --release`）**：
  - 結果：✅ 成功（暫時於 `%USERPROFILE%\.gradle\gradle.properties` 寫入 `allowDebugSigning=true` 放行 debug 簽章，建置完成後已立即刪除並確認檔案不存在）。
  - KGP 警告清單：同為 7 個（不含 `shared_preferences_android`、`url_launcher_android`）。
  - `app/build/app/outputs/flutter-apk/app-release.apk` 體積比對：
    - 基準（`issue-17-report.md`）：`130,007,095` bytes（`124.0MB`）
    - 本次升級後：`130,023,551` bytes（`124.0MB`）
    - 差異：`+16,456` bytes（`+0.013%`）。
- **Windows debug 建置（`flutter build windows --debug`）**：
  - 結果：✅ 成功（`build\windows\x64\runner\Debug\elinkbook.exe`）。
  - `git status --short` 確認：無 `app/windows/flutter/generated_plugin_registrant.*` 等無關異動。
- **完整單元／Widget 測試（`flutter test`）**：
  - 結果：✅ 全數通過（`+5341 ~2: All tests passed!`，0 失敗）。
- **Android 真機抽測（`adb install -r`）**：
  - 結果：⏸️ **未驗證**（執行環境 `adb devices` 無連接裝置，未驗證偏好設定重啟保留與外部連結開啟）。

## 4. 後續項目（Task 4，不在本 Issue 實作，待使用者決定再動）

- 向 `flutter_tts`、`flutter_web_auth_2` 上游各回報 issue（**送出前須使用者同意**）。
- `wakelock_plus`／`package_info_plus`／`share_plus`／`file_picker` 屬 `win32` 相依鏈大版本升級（另含 Issue 16 `desktop_drop`／`cross_file` 0.4），另案處理。
- 全部外掛皆支援 Built-in Kotlin 後：將 `app/android/gradle.properties` 切為 `android.builtInKotlin=true`、移除 `app/patches/file_picker`。
