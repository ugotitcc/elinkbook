# TTS 相依性驗證 spike 結果（Issue 1）

**驗證日期：** 2026-08-26
**驗證環境：** Flutter 3.41.9（`sdk: ^3.11.5`），`flutter.compileSdkVersion`/`flutter.targetSdkVersion` 皆為 `36`，專案 `minSdk = 24`（`app/android/app/build.gradle.kts`）

## 相依性 dry-run 結果：無衝突

`flutter pub add --dry-run audio_service just_audio flutter_tts` 三者一起試算，`share_plus`（`^11.1.0`）／`file_picker`（`^11.0.2`）／`package_info_plus`（`^9.0.1`）／`win32`（現有已解析版本 `5.15.0`）皆維持不變，未觸發 `app/pubspec.yaml` 第 40-49 行註解記載的既有三方版本鏈衝突。`flutter_inappwebview_android` 本機 patch override（`dependency_overrides`）不受影響。

會新增的套件與已驗證的可解析版本：

| 套件 | 版本 |
| --- | --- |
| `audio_service` | `0.18.19` |
| `audio_service_platform_interface` | `0.1.3` |
| `audio_service_web` | `0.1.4` |
| `audio_session` | `0.2.4` |
| `flutter_cache_manager` | `3.4.2` |
| `js` | `0.7.2` |
| `just_audio` | `0.10.6` |
| `just_audio_platform_interface` | `4.6.0` |
| `just_audio_web` | `0.4.16` |
| `flutter_tts` | `4.2.5` |

**給 Issue 2／Issue 7 實作者的提醒**：上述版本是驗證當下的可解析結果，實際執行 `flutter pub add` 時請重新確認一次沒有衝突（套件生態隨時間會發布新版本）；若屆時出現與本文件不同的衝突狀況，比照 `app/pubspec.yaml` 第 40-49 行既有註解的處理方式（明確寫版本鎖定理由），不要沉默地選一個版本了事。

## minSdk 相容性：不影響現有政策門檻

`flutter_tts`／`audio_service`／`sherpa_onnx`（Phase 3 才需要）三者 minSdk 皆為 21，低於專案現有 `minSdk = 24`，不會將下限往上拉，Android 11 (API 30) 政策門檻可達成（Discovery 階段 `/grill-with-docs` 已查證，本次為覆核，未發現矛盾）。

## targetSdk manifest 需求清單（供 Issue 7 落實）

專案 `targetSdk` 解析為 `36`（Android 16），`audio_service` 依此 targetSdk 觸發以下 `AndroidManifest.xml` 宣告需求（`app/android/app/src/main/AndroidManifest.xml` 目前完全沒有任何 `<service>` 宣告或前景服務相關權限，Issue 7 是從零開始新增，不是修改既有宣告）：

1. **前景服務型別宣告**：`audio_service` 註冊的 Service 需標註 `android:foregroundServiceType="mediaPlayback"`。
2. **前景服務權限**：`<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>`（targetSdk 34 起強制要求，本專案 targetSdk 36 已超過此門檻，必加）。
3. **一般前景服務權限**：`<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>`（Android 9／API 28 起前景服務的基礎權限，`FOREGROUND_SERVICE_MEDIA_PLAYBACK` 是在此之上針對媒體播放這個用途的細分權限，兩者都要宣告）。
4. **通知執行期權限**：`<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`（Android 13／API 33 起，通知欄播放控制需要這個執行期權限；`audio_service` 官方文件建議宣告並視情況於執行期請求，媒體類前景服務通知在系統層有一定豁免，但仍需宣告才能確保通知完整顯示）。
5. **Exported 元件明確標註**：Android 12／API 31 起，有 intent-filter 的元件須明確標註 `android:exported`。現有 `MainActivity` 已標註 `android:exported="true"`（見 `AndroidManifest.xml` 現況），`audio_service` 新增的 Service／Receiver 元件同樣須明確標註（通常為 `exported="false"`，僅供 App 自身與系統 MediaSession 框架呼叫，不對外開放）。

## 結論

三個套件皆可安全加入，不需要額外的版本鎖定策略或相依鏈調整。Issue 2 可直接在 `app/pubspec.yaml` 加入 `audio_service`／`just_audio`／`flutter_tts`（依實際需要，`flutter_tts` 是 Issue 2 必要項，`audio_service`／`just_audio` 若 Issue 2 尚未整合播放器可延後到 Issue 7 才加入，避免加入目前程式碼還用不到的相依套件）；Issue 7 直接依上方 targetSdk manifest 需求清單補齊宣告，不需要重新調查。
