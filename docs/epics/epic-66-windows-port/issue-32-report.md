# Epic 66 Issue 32 驗證報告：Android 外掛遷移 built-in Kotlin（階段一）

- **分支**：`chore/epic-66-issue-32-kgp-plugins`
- **基準 commit**：`44878df9`（前一個 `fc7dab9a`）
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
