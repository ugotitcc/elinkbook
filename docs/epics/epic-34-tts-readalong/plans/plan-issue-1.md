# Issue 1：套件相依性驗證 spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Phase 1 任何 TTS 程式碼開工前，確認 `audio_service`／`just_audio`／`flutter_tts` 三個新套件與現有相依鏈（`flutter_inappwebview`／`pdfrx`／`sqflite`／`share_plus`／`file_picker`／`package_info_plus`）無版本衝突，並產出一份供 Issue 2、Issue 7 直接引用的 targetSdk manifest 需求檢查清單。

**Architecture:** 本 Issue 不寫任何 Dart/Kotlin 程式碼、不修改 `pubspec.yaml`——純粹是 `flutter pub add --dry-run` 試算＋文件盤點的 spike。所有試算指令與輸出已在撰寫本計畫前實際執行過一次驗證（見下方各 Task 的「已驗證輸出」），計畫中的指令與期望結果皆為真實資料，不是推測。

**Tech Stack:** Flutter 3.41.9（`sdk: ^3.11.5`）、`flutter pub add --dry-run`、現有 `app/android/app/build.gradle.kts`（`compileSdk = flutter.compileSdkVersion`／`targetSdk = flutter.targetSdkVersion`／`minSdk = 24`，此 Flutter 版本下 `flutter.compileSdkVersion`/`flutter.targetSdkVersion` 皆解析為 `36`，見 `C:\tools\flutter\packages\flutter_tools\gradle\src\main\kotlin\FlutterExtension.kt`）。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 1：套件相依性驗證 spike」；`docs/epics/epic-34-tts-readalong/spec.md`「Phase 0 前置技術驗證」；`docs/epics/epic-34-tts-readalong/design.md` 已拍板決策第 4／5 點。

## Global Constraints

- 不修改 `app/pubspec.yaml`／`app/pubspec.lock`（本 Issue 只做 dry-run 試算，不實際加入套件——實際加入是 Issue 2／Issue 7 的工作，避免加入目前程式碼還用不到的相依套件）。
- 不修改任何 Dart/Kotlin 原始碼或 `AndroidManifest.xml`（manifest 實際宣告是 Issue 7 的工作，本 Issue 只盤點清單）。
- 產出的檢查清單文件路徑固定為 `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`，供 Issue 2、Issue 7 直接引用，不需各自重新調查。
- 本 Epic 目前 `minSdk = 24`（見 `app/android/app/build.gradle.kts:76`），是既有政策寬鬆值（政策門檻為 Android 11／API 30），本 Issue 只需覆核三個新套件不會把這個下限往上拉，不需重新調查更精確的數字（Discovery 階段已查證三者 minSdk 皆為 21）。

---

### Task 1：執行相依性 dry-run 驗證，確認無衝突

**Files:**
- 無檔案異動（本 Task 只執行指令、觀察輸出）

**Interfaces:**
- Consumes：無
- Produces：三次 `flutter pub add --dry-run` 執行的原始輸出文字，供 Task 2 撰寫檢查清單文件時引用

- [x] **Step 1：確認目前工作目錄乾淨，記錄執行前基準狀態**

在 `app/` 目錄下執行：

```
git status --short pubspec.yaml pubspec.lock
```

Expected：無任何輸出（代表 `pubspec.yaml`／`pubspec.lock` 目前沒有未提交的異動）。若有輸出，先停下來確認那是不是別的工作留下的未提交變更，不要在髒的工作區上開始這個 Issue。

- [x] **Step 2：試算加入 `audio_service`＋`just_audio`（Phase 1 背景播放與播放器）**

在 `app/` 目錄下執行：

```
flutter pub add --dry-run audio_service just_audio
```

Expected（已於撰寫本計畫前實際驗證過的真實輸出，摘錄關鍵行）：

```
+ audio_service 0.18.19
+ audio_service_platform_interface 0.1.3
+ audio_service_web 0.1.4
+ audio_session 0.2.4
+ flutter_cache_manager 3.4.2
! flutter_inappwebview_android 1.1.3 from path patches\flutter_inappwebview_android (overridden)
+ js 0.7.2
+ just_audio 0.10.6
+ just_audio_platform_interface 4.6.0
+ just_audio_web 0.4.16
  share_plus 11.1.0 (13.3.0 available)
  package_info_plus 9.0.1 (10.2.1 available)
  win32 5.15.0 (6.4.0 available)
Would change 9 dependencies.
```

**驗證重點**：`share_plus`／`package_info_plus`／`win32`／`file_picker` 版本號維持不變（前面沒有 `+`／`-` 符號，只有「有新版可用」的提示），代表沒有觸發 `app/pubspec.yaml` 第 40-49 行註解記載的那種三方版本鏈衝突；`flutter_inappwebview_android` 的本機 patch override 也未受影響。若你實際執行時看到 `share_plus`／`package_info_plus`／`win32`／`file_picker` 前面出現 `+` 或版本號變動，代表相依鏈狀態已與撰寫本計畫時不同，**停下來**，不要繼續 Task 2，回報實際輸出供人類決定下一步。

- [x] **Step 3：試算加入 `flutter_tts`（Phase 1 `SystemTtsProvider`）**

在 `app/` 目錄下執行：

```
flutter pub add --dry-run flutter_tts
```

Expected（已驗證過的真實輸出，摘錄關鍵行）：

```
+ flutter_tts 4.2.5
  share_plus 11.1.0 (13.3.0 available)
  package_info_plus 9.0.1 (10.2.1 available)
  win32 5.15.0 (6.4.0 available)
Would change 1 dependency.
```

**驗證重點**：同 Step 2，`share_plus`／`package_info_plus`／`win32` 版本不變。

- [x] **Step 4：試算三個套件一起加入，確認組合起來也無衝突**

在 `app/` 目錄下執行：

```
flutter pub add --dry-run audio_service just_audio flutter_tts
```

Expected：`Would change 10 dependencies.`（9 + 1，跟 Step 2／3 分開試算的數量相加一致，代表三者組合起來沒有互相衝突或額外連鎖升級）；`share_plus`／`package_info_plus`／`win32` 版本依然不變。

- [x] **Step 5：確認 dry-run 沒有實際修改任何檔案**

在 `app/` 目錄下執行：

```
git status --short pubspec.yaml pubspec.lock
```

Expected：無任何輸出（與 Step 1 相同）——`--dry-run` 不應該寫入 `pubspec.yaml`／`pubspec.lock`。若有輸出，執行 `git checkout -- pubspec.yaml pubspec.lock`（若 `pubspec.lock` 未受版控管理則忽略該檔案）還原，並回報這個異常現象。

---

### Task 2：撰寫 targetSdk manifest 需求檢查清單文件，驗證基準線無回歸

**Files:**
- Create: `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`

**Interfaces:**
- Consumes：Task 1 的三次 dry-run 輸出（本 Task 直接把 Task 1 的驗證結果整理進文件，不需要重新執行指令）
- Produces：`docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`——Issue 2（新增 `audio_service`/`just_audio`/`flutter_tts` 到 `pubspec.yaml`）與 Issue 7（`audio_service` manifest 整合）直接引用此文件，不需重新調查

- [x] **Step 1：撰寫檢查清單文件**

建立 `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`，內容如下（`{DATE}` 替換為執行本 Task 當天日期，格式 `YYYY-MM-DD`）：

```markdown
# TTS 相依性驗證 spike 結果（Issue 1）

**驗證日期：** {DATE}
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
```

- [x] **Step 2：確認基準線無回歸**

在 `app/` 目錄下執行：

```
flutter analyze
```

Expected：`No issues found!`

再執行：

```
flutter test
```

Expected：全數測試通過（PASS），因為本 Issue 未修改任何 Dart 程式碼，測試結果應與 Issue 開始前完全一致（零回歸）。

- [x] **Step 3：確認變更範圍只有新增的檢查清單文件**

在儲存庫根目錄執行：

```
git status --short
```

Expected：只看到一筆 `?? docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`（新增的未追蹤檔案），沒有任何其他檔案被修改——特別確認 `app/pubspec.yaml`／`app/pubspec.lock`／`app/android/app/src/main/AndroidManifest.xml` 都不在變更清單中。若看到其他檔案被異動，先排查原因（可能是 Task 1 的 dry-run 意外寫入了什麼、或環境中有其他未關閉的編輯），不要直接提交。

- [x] **Step 4：Commit**

```
git add docs/epics/epic-34-tts-readalong/dependency-spike-findings.md
git commit -m "docs(epic-34): TTS 相依性驗證 spike 結果（Issue 1）"
```
