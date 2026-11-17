# Issue 32：Android 外掛遷移 built-in Kotlin（階段一）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 升級 `shared_preferences_android`（2.4.23→2.4.28；原擬 2.5.5，但它要求 `jni ^1.1.1` 會連動升級 `jni`，故改取 2.4.24 起已遷移的 2.4.28，見報告第 2 節）與 `url_launcher_android`（6.3.30→6.3.33）這兩個新版已不套用 KGP 的間接相依，使打包警告的 KGP 外掛由 9 個降為 7 個，行為不變。

**Architecture:** 純相依升級，不改 Dart／Kotlin 業務程式、不改 `pubspec.yaml`。兩者皆為 `shared_preferences`／`url_launcher` 的 Android 平台實作（間接相依），`flutter pub upgrade <套件>` 即可。保留 `android.builtInKotlin=false`、`android.newDsl=false`、`patches/file_picker`。

**Tech Stack:** Flutter 3.47.9、AGP 9.1.0、Gradle 9.3.1、Kotlin 2.3.20（皆不動）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md`「Issue 32 範圍」。

## 執行慣例

- Shell 一律用 **Git Bash**，**git 指令在 repo 根目錄執行**，`flutter`／`node tool/...` 指令先 `cd app`，指令後回到根目錄。分號一律用半形 `;` 或拆行。
- 暫存 log 放在 `app/build/issue32/`（`build/` 已被忽略，不進版控），例如 `mkdir -p app/build/issue32`，之後 `tee app/build/issue32/before.log`。
- `adb` 路徑：`/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe`（本機已確認存在；換電腦需自行確認）。

## Global Constraints

- `flutter analyze` 乾淨；不改 `pubspec.yaml`、不動 `gradle.properties` 的兩個開關與 JDK 路徑（唯一允許的改動：第 6 行註解的外掛數量 `9` → `7`，見 Task 2）。
- **不升級** `wakelock_plus`（1.6 起要求 `win32` ≥ 6，專案鎖 5.15）、`package_info_plus`、`share_plus`、`desktop_drop`、`file_picker`。若 `pub upgrade` 連動拉動它們或 `win32`，視為失敗並回退。
- 真機一律用 `adb install -r`，**禁用 `flutter install`**（會清資料）；Android 整合測試前螢幕必須亮著。
- release 建置在沒有 `app/android/key.properties` 的機器上需放行 debug 簽章：寫入 `%USERPROFILE%\.gradle\gradle.properties` 的 `allowDebugSigning=true`，驗完刪除（同 Issue 17 計畫）。
- 測試範圍：完整 `flutter test` 只在 Task 3 與發 PR 前各一次。
- 文件與註解正體中文；commit 不加 `Co-Authored-By`；計畫與實作同分支（`chore/epic-66-issue-32-kgp-plugins`）同一個 PR。
- 每完成一個 Step，立即把本檔該 Step 的 `- [ ]` 改為 `- [x]`。

## 回退條件

任一驗證失敗且無法立即解決，依失敗時機回退：

- Task 2 Step 4 commit **之前**：`git checkout -- app/pubspec.lock`，再 `cd app && flutter pub get`。
- Task 2 Step 4 commit **之後**（Task 3 失敗）：`git revert <Task 2 的 commit sha>`，再 `cd app && flutter pub get`。
- 兩種情況都要在報告記錄失敗原因與當時的版本。

## Review Focus

1. `pubspec.lock` 變動只限兩個目標外掛與必然連動項，`pubspec.yaml` 零變動。
2. 打包警告確實由 9 個降為 7 個（逐條核對外掛名單，不憑印象）。
3. Windows 建置不受影響（兩外掛在 Windows 另有實作），且沒有夾帶無關的 `windows/flutter/generated_plugin_registrant.*` 異動。
4. 報告不得宣稱未驗證的真機項目已通過。

---

### Task 1：記錄升級前基準

**Files:** Create：`docs/epics/epic-66-windows-port/issue-32-report.md`

- [x] **Step 1：先 commit 計畫階段文件，再確認基準**

Run（repo 根目錄）：
```
git add docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/plans/plan-issue-32.md
git commit -m "docs(epic-66): Issue 32 登記與實作計畫"
git status --short
grep -A7 -E "^  (shared_preferences_android|url_launcher_android):" app/pubspec.lock | grep -E "^  [a-z_]+:|version"
```
Expected：`git status --short` 無輸出（審查報告在被忽略的 `reviews/` 內）；版本為 `2.4.23` 與 `6.3.30`。

- [x] **Step 2：記錄升級前 debug 建置警告**

Run：
```
mkdir -p app/build/issue32
cd app
flutter build apk --debug 2>&1 | tee build/issue32/before.log
grep -A1 "plugins that apply Kotlin Gradle Plugin" build/issue32/before.log
cd ..
```
Expected：列出 9 個外掛（desktop_drop、file_picker、flutter_tts、flutter_web_auth_2、package_info_plus、share_plus、shared_preferences_android、url_launcher_android、wakelock_plus）。把結果寫入 `issue-32-report.md`「升級前」段。

- [x] **Step 3：Commit 報告初稿**

`git add docs/epics/epic-66-windows-port/issue-32-report.md` 後 `git commit -m "docs(epic-66): Issue 32 升級前基準"`

### Task 2：升級兩個外掛

**Files:** Modify：`app/pubspec.lock`、`app/android/gradle.properties`（僅第 6 行註解數字）

- [x] **Step 1：先乾跑確認影響面**

Run：`cd app && flutter pub upgrade --dry-run shared_preferences_android url_launcher_android; cd ..`
Expected：只出現這兩個（可能含平台介面的必然連動）；**不得**出現 wakelock_plus、package_info_plus、share_plus、desktop_drop、file_picker、win32 的變動。若出現，停止並在報告記錄。

- [x] **Step 2：實際升級並逐行核對**

Run：`cd app && flutter pub upgrade shared_preferences_android url_launcher_android; cd ..`，再 `git diff app/pubspec.lock`。
Expected：只有 `pubspec.lock` 變動；diff 中版本為 `2.4.28`（原計畫 `2.5.5`，因會連動 `jni` 改取此版，見報告）與 `6.3.33`；`pubspec.lock` 底部 `sdks` 下限會隨兩外掛（皆要求 `flutter >=3.44.0`）抬高，屬預期；**沒有**上述禁止清單內的套件或 `win32` 出現。`git diff --stat` 僅作輔助，不能取代逐行核對。

- [x] **Step 3：同步 `gradle.properties` 註解並做靜態檢查**

把 `app/android/gradle.properties` 第 6 行「仍有 9 個外掛套用 KGP」改成「仍有 7 個外掛套用 KGP」（開關值不動）。
Run：`cd app && flutter analyze; node tool/check_l10n_hardcoded_strings.js; cd ..`
Expected：`No issues found!`、腳本無違規。

- [x] **Step 4：Commit**

`git add app/pubspec.lock app/android/gradle.properties && git commit -m "chore(android): 升級 shared_preferences_android、url_launcher_android 以減少 KGP 外掛"`
記下此 commit 的 sha（回退用）。

### Task 3：建置與測試驗證

- [x] **Step 1：Android debug 建置與警告核對**

Run：`cd app && flutter build apk --debug 2>&1 | tee build/issue32/after.log; grep -A1 "plugins that apply Kotlin Gradle Plugin" build/issue32/after.log; cd ..`
Expected：成功；KGP 外掛清單剩 7 個（不含 shared_preferences_android、url_launcher_android）。若仍含這兩個，查原因（是否另有套件固定舊版）並記錄。

- [x] **Step 2：Android release 建置**

放行 debug 簽章後 `cd app && flutter build apk --release`（有 `key.properties` 的機器改跑 `node tool/build_release.js --target apk`）。
Expected：成功。體積一律比對 `app/build/app/outputs/flutter-apk/app-release.apk` 的位元組數，基準為 `issue-17-report.md` 的 `130,007,095 bytes`（同口徑）。驗完刪除使用者層級放行設定。

- [x] **Step 3：Windows debug 建置**

Run：`cd app && flutter build windows --debug; cd ..; git status --short`
Expected：建置成功；`git status --short` 沒有 `app/windows/flutter/generated_plugin_registrant.*` 等無關異動（有則還原，不夾帶）。

- [x] **Step 4：完整單元測試（一次）**

Run：`cd app && flutter test; cd ..`
Expected：全數通過。若有失敗，單獨重跑該檔並與 `issue-17-report.md` 記載的已知偶發（`test/downloads/download_queue_controller_test.dart`，單獨重跑可過）比對，不憑印象判定。

- [x] **Step 5：真機抽測（有裝置才做）**（已確認無連接裝置，**未執行**；報告標「未驗證」）

用 `adb install -r` 安裝後：開啟 App、切換偏好設定（如書庫檢視模式）後重啟仍保留、點擊外部連結（如關於頁）能開啟。
Expected：通過；沒有裝置則在報告明寫「未驗證」。

### Task 4：後續登記與收尾（不實作後續項目）

- [x] **Step 1：在 `issue-32-report.md`「後續」段列出，等使用者決定再動：**
  - 向 `flutter_tts`、`flutter_web_auth_2` 上游各回報 issue（**送出前須使用者同意**）。
  - `wakelock_plus`／`package_info_plus`／`share_plus`／`file_picker` 屬 win32 相依鏈大版本升級，另案。
  - 全部外掛支援後：`builtInKotlin=true`、移除 `patches/file_picker`。
- [x] **Step 2：把 Task 3 的結果（建置、警告清單、測試、真機是否驗證）填入報告。**
- [x] **Step 3：更新看板**：`docs/epics/epic-66-windows-port/issues.md` 第 38 列狀態改為已完成並加上報告連結（附真機驗證與否）；`docs/epics.md` epic-66 列備註只寫精簡摘要「Issue 32 已完成」。
- [x] **Step 4：收尾 commit（一併提交已勾選的計畫）**

```
git add docs/epics/epic-66-windows-port/issue-32-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/plans/plan-issue-32.md docs/epics.md
git commit -m "docs(epic-66): Issue 32 驗證報告與看板更新"
git status --short
```
Expected：`git status --short` 無輸出。
