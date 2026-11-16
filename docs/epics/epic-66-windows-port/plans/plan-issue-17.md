# Issue 17：Android 建置工具升級到 Gradle 9.3.1／AGP 9.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Android 建置工具升到 Gradle 9.3.1／AGP 9.1.0，讓每次打包不再出現 Flutter 的「Gradle 8.14.0／AGP 8.11.1 即將不支援」兩則警告，且 debug／release 建置與真機行為不變。

**Architecture:** 純建置設定異動，不改 Dart 與 Kotlin 業務程式。保留 `android.builtInKotlin=false`／`android.newDsl=false` 退出開關（9 個外掛仍套用 KGP）；`flutter_inappwebview_android` 本地修補改用 `proguard-android-optimize.txt`；新增 `patches/file_picker` 本地修補，讓它在 AGP 9 下仍套用 KGP。

**Tech Stack:** Gradle 9.3.1、AGP 9.1.0、Kotlin 2.3.20（不動）、JDK 17（不動）、Flutter 3.47.9。

**Spec:** `docs/epics/epic-66-windows-port/issues.md`「Android 建置工具升級（Issue 17）」段落的「設計定案與可行性」。2026-11-16 拋棄式 worktree 已驗證：僅需下方「已驗證的變更清單」即可 `flutter build apk --debug`／`--release` 成功、兩則警告消失。

## 已驗證的變更清單（試建置結果，本計畫照做）

| 檔案 | 異動 |
|---|---|
| `app/android/gradle/wrapper/gradle-wrapper.properties` | `gradle-8.14-all.zip` → `gradle-9.3.1-all.zip` |
| `app/android/settings.gradle.kts` | `com.android.application` `8.11.1` → `9.1.0` |
| `app/patches/flutter_inappwebview_android/android/build.gradle` | 兩處 `proguard-android.txt` → `proguard-android-optimize.txt` |
| `app/patches/file_picker/`（新增） | 複製 pub 的 `file_picker-11.0.3`，`android/build.gradle` 的 `isAgp9OrAbove` 固定為 `false` |
| `app/pubspec.yaml` | `dependency_overrides` 加 `file_picker: path: patches/file_picker` |

## Global Constraints

- Flutter 3.47.9（Dart 3.13.7），`flutter analyze` 乾淨（"No issues found!"）。
- **不改**：`android.builtInKotlin=false`、`android.newDsl=false`、Kotlin 2.3.20、JDK 17（`gradle.properties` 的 `org.gradle.java.home` 寫死 `C:` 路徑）、Windows 專屬的 `kotlin.incremental=false` workaround、`minSdk`、資料庫 schema。
- 不升級任何 pub 套件版本（`file_picker` 升版牽動 win32 相依鏈，列後續觀察）。外掛遷移 built-in Kotlin 不在本 Issue。
- 真機一律用 `adb install -r`，**禁用 `flutter install`**（會解除安裝並清資料）；Android 整合測試前螢幕必須亮著。`adb` 不在 PATH，路徑見 memory「Android 實機整合測試環境坑」。
- 這台機器沒有 `app/android/key.properties`：release 建置要放行 debug 簽章，必須把 `allowDebugSigning=true` 寫進使用者層級 `%USERPROFILE%\.gradle\gradle.properties`（用環境變數 `ORG_GRADLE_PROJECT_allowDebugSigning` 在 bash 下實測無效），驗證完要刪掉，**不可寫進專案的 `gradle.properties`**。
- 測試範圍：本 Issue 不動 Dart，只跑 `flutter analyze` 與各 Task 指定的建置；完整 `flutter test` 只在最後一個 Task 與發 PR 前各跑一次（`pubspec.yaml` 相依來源變了，值得一次）。
- 所有文件、註解以正體中文撰寫；commit 不加 `Co-Authored-By`；計畫與實作同分支（`chore/epic-66-issue-17-agp9`）同一個 PR。

## 回退條件

任一 Task 的驗證失敗且無法在「外掛處理順序」內解決（找相容新版 → 本地修補），整組還原 Gradle 8.14／AGP 8.11.1：須同時 `git revert` Task 2（`patches/file_picker`、`pubspec.yaml` 的 `dependency_overrides`）與 Task 3（wrapper、`settings.gradle.kts`、`gradle.properties` 註解）兩個 commit，不可只還原 Task 3，否則會遺留只為 AGP 9 而設的 `file_picker` 本地修補，並暫用 `--android-skip-build-dependency-validation` 消音，不做半套升級。

## Review Focus

1. **`file_picker` 在 Android 真機仍能選檔匯入：** 修補若沒生效，`GeneratedPluginRegistrant` 找不到 `FilePickerPlugin` 會建置失敗；但就算建置過了，也要實測選檔匯入（Task 4）。
2. **Windows 版不受修補影響：** `file_picker` 改成本地路徑副本後，`flutter build windows --debug` 必須仍成功（副本漏掉 Windows 需要的檔案會在此露餡）。（Task 2 驗證。）
3. **release 版（R8）啟動與開書：** AGP 9 預設啟用 R8 優化，debug 建置通過不代表 release 沒被過度混淆／移除；release APK 必須在真機啟動並開一本 EPUB 與一本 PDF。（Task 4。）
4. **舊 WebView 機器（iReader Ocean 4 Plus，Chrome 83 以下）：** 啟動、開書、劃線不得退化（本 Issue 不動 foliate，但 release 打包有變）。（Task 4。）
5. **簽章驗證：** `node tool/build_release.js --target apk|aab` 的驗簽仍須對得上 `config/signing_fingerprints.json`（結束碼 0），AGP 9 不得改變簽章結果。（Task 3，在有 `key.properties` 的機器上做。）
6. **`U:` 機器的 JDK 路徑：** `org.gradle.java.home` 寫死 `C:` 的 JDK 17，`U:` 那台升級後須能建置。（Task 3。）

---

### Task 1：記錄升級前基準

**Files:**
- Modify（暫存，驗完刪除）：`%USERPROFILE%\.gradle\gradle.properties`（新增 `allowDebugSigning=true`）
- Create：`docs/epics/epic-66-windows-port/issue-17-report.md`（驗證報告，之後各 Task 逐步補）

- [ ] **Step 1：先 commit 本計畫檔，再確認基準**

Run：`git add docs/epics/epic-66-windows-port/plans/plan-issue-17.md` 與 `git commit -m "docs(epic-66): Issue 17 實作計畫"`，接著於 `app/` 跑 `git status --short` 與 `git log --oneline -2`
Expected：工作區乾淨，HEAD 為上述計畫 commit、其前一個為 `ae1ebdcc`，Gradle 仍是 8.14／AGP 8.11.1。

- [ ] **Step 2：寫入使用者層級放行設定**

在 `%USERPROFILE%\.gradle\gradle.properties` 加一行 `allowDebugSigning=true`（檔案不存在就建立）。

- [ ] **Step 3：建升級前 release APK，記錄警告原文與體積**

Run（於 `app/`）：`flutter build apk --release 2>&1 | tee ../build-before.log`，再 `ls -l build/app/outputs/flutter-apk/app-release.apk`（本計畫所有指令皆在 Git Bash 執行；PowerShell 的 `ls` 不接受 `-l`）
Expected：成功；輸出含「Gradle version (8.14.0)」與「Android Gradle Plugin version 8.11.1」兩則 Warning；記下 APK 位元組數。

- [ ] **Step 4：把基準寫入報告**

`issue-17-report.md` 記錄：兩則警告原文各一行、升級前 `app-release.apk` 位元組數、`flutter --version`。`build-before.log` 不進版控（用完刪除）。

---

### Task 2：本地修補（先不升版本，確認修補本身不破壞現狀）

**Files:**
- Modify：`app/patches/flutter_inappwebview_android/android/build.gradle`（兩處 `proguard-android.txt` → `proguard-android-optimize.txt`）
- Create：`app/patches/file_picker/`（複製 `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\file_picker-11.0.3`，**排除** `example/`、`test/`、`tool/`、`CONTRIBUTING.md`；保留 `android/`、`ios/`、`macos/`、`lib/`、`pubspec.yaml`、`LICENSE`、`README.md`、`CHANGELOG.md`、`analysis_options.yaml`）
- Create：`app/patches/file_picker/PATCH.md`
- Modify：`app/patches/flutter_inappwebview_android/PATCH.md`（補一段 proguard 修補說明，並把「移除條件」改為上游同時修好 `toMap()` 且支援 AGP 9）
- Modify：`app/pubspec.yaml`（`dependency_overrides` 加 `file_picker`，並在既有註解旁補一行為何覆寫）

**Interfaces:**
- Produces：`file_picker` 解析來源變為 `path: patches/file_picker`，版本仍 11.0.3；`pubspec.lock` 的 `file_picker` 來源由 `hosted` 變 `path`。

- [ ] **Step 1：複製並修補 `file_picker`**

把上述目錄複製到 `app/patches/file_picker/`（排除 `example/`、`test/`、`tool/`），再把 `android/build.gradle` 的 `def isAgp9OrAbove = ...` 那一行改為：`def isAgp9OrAbove = false // 本地修補：本專案 android.builtInKotlin=false，Kotlin 原始碼須由 KGP 編譯`。其餘一律不動。

- [ ] **Step 2：改 `flutter_inappwebview_android` 的 proguard 檔名**

`app/patches/flutter_inappwebview_android/android/build.gradle` 的 `debug`／`release` 兩個 `proguardFiles` 都改 `proguard-android-optimize.txt`。

- [ ] **Step 3：寫兩份 `PATCH.md`**

`file_picker/PATCH.md` 比照既有 `flutter_inappwebview_android/PATCH.md` 格式（問題／修正／檔案位置／使用方式／移除條件）：問題＝11.0.3 在 AGP ≥ 9 不套用 KGP、而專案 `builtInKotlin=false` 導致 `FilePickerPlugin` 沒被編譯；修正＝`isAgp9OrAbove` 固定 `false`；移除條件＝所有 KGP 外掛遷移完成並改回 `builtInKotlin=true`，或 `file_picker` 升版後在 `builtInKotlin=false` 下也能編譯。

`flutter_inappwebview_android/PATCH.md` 另補「`proguard-android.txt` → `proguard-android-optimize.txt`」段落（AGP 9 禁用 `-dontoptimize`，原寫法直接報錯），並把原「移除條件」（只寫上游修 `toMap()`）改為「上游同時修復 `toMap()` 且支援 AGP 9 後才可移除」，避免只修 `toMap()` 就誤刪修補。

- [ ] **Step 4：`pubspec.yaml` 加 override 並更新相依**

`dependency_overrides:` 底下加 `file_picker:` → `path: patches/file_picker`。Run（於 `app/`）：`flutter pub get`
Expected：成功；`pubspec.lock` 的 `file_picker` 變 `source: path`、版本 11.0.3。

- [ ] **Step 5：驗證 Windows 版與 Dart 未受影響**

Run（於 `app/`）：`flutter analyze`、`flutter build windows --debug`
Expected：`No issues found!`；Windows 建置成功（Review Focus 2）。

- [ ] **Step 6：驗證在舊版 Gradle／AGP 上修補仍可建置**

Run（於 `app/`）：`flutter build apk --debug`
Expected：成功（此時仍是 8.14／8.11.1，證明修補向下相容）。

- [ ] **Step 7：Commit**

```bash
git add app/patches app/pubspec.yaml app/pubspec.lock
git commit -m "build(android): file_picker 與 inappwebview 本地修補，為 AGP 9 做準備（epic-66 Issue 17）"
```

---

### Task 3：升級 Gradle 與 AGP

**Files:**
- Modify：`app/android/gradle/wrapper/gradle-wrapper.properties`（`distributionUrl` → `gradle-9.3.1-all.zip`）
- Modify：`app/android/settings.gradle.kts`（`com.android.application` → `"9.1.0"`）
- Modify：`app/android/gradle.properties`（只改兩個退出開關上方的註解，寫明「保留原因：仍有 9 個外掛套用 KGP；移除條件見 `patches/file_picker/PATCH.md`；AGP 10 預期移除這兩個開關」。**不改開關值**）

- [ ] **Step 1：改三個檔案**

依上表修改。`kotlin.android` 外掛宣告（`2.3.20`）與 `app/build.gradle.kts` 的 `id("kotlin-android")` **不動**。

- [ ] **Step 2：debug 建置，確認警告消失**

Run（於 `app/`）：`flutter build apk --debug 2>&1 | tee ../build-after-debug.log`
Expected：成功；輸出**不含**「Gradle version (8.14.0)」與「Android Gradle Plugin version 8.11.1」；允許出現「9 個外掛套用 KGP」的新警告（已知殘留）。首次會下載 Gradle 9.3.1，約 5 分鐘。

- [ ] **Step 3：release 建置，比對體積**

Run（於 `app/`）：`flutter build apk --release`，再 `ls -l build/app/outputs/flutter-apk/app-release.apk`
Expected：成功；位元組數與 Task 1 基準比對，差異寫進報告（試建置時為 124.0MB，無基準）。差異超過 ±5% 時在報告註明並在 Task 4 特別留意。

- [ ] **Step 4：（有 `key.properties` 的機器）正式打包與驗簽**

Run（於 `app/`）：`node tool/build_release.js --target apk`，再 `--target aab`
Expected：結束碼 0；摘要顯示簽章與 `config/signing_fingerprints.json` 相符（Review Focus 5）。這台沒有 `key.properties` 時在報告標註「未驗」，留給有金鑰的機器。

- [ ] **Step 5：`U:` 機器建置（Review Focus 6）**

在 `U:` 那台 `git pull` 本分支後跑 `flutter build apk --debug`。若 JDK 路徑不符，修正 `org.gradle.java.home` 的方式與結果寫進報告（不在這個 Step 改成不寫死，那是另案）。

- [ ] **Step 6：Commit**

```bash
git add app/android
git commit -m "build(android): Gradle 8.14→9.3.1、AGP 8.11.1→9.1.0（epic-66 Issue 17）"
```

---

### Task 4：真機驗證（`adb install -r`）

**Files:**
- Modify：`docs/epics/epic-66-windows-port/issue-17-report.md`（補真機結果）

- [ ] **Step 1：安裝 release APK 到一台一般真機**

Run：`<adb 路徑> install -r app/build/app/outputs/flutter-apk/app-release.apk`（螢幕亮著；禁用 `flutter install`）
Expected：`Success`。**簽章限制**：這台沒有 `key.properties`，產出的 release APK 是 debug 金鑰簽章，只能覆蓋同為 debug 簽章的安裝；測試機若裝的是正式簽章版（Play 或 GitHub Release），`adb install -r` 會失敗（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`），這不是 AGP 9 的問題。此時改裝 Task 3 Step 4 在有金鑰機器產出的正式簽章 APK，或改用另一台測試機；**不可為了安裝而解除安裝正式版**（會清掉書架資料）。

- [ ] **Step 2：抽測核心功能**

逐項在真機操作並記錄通過／失敗：啟動、開一本 EPUB 並翻頁與劃線、開一本 PDF、字典查詞、TTS 朗讀、「選檔匯入」（`file_picker`，Review Focus 1）、關於頁的建置資訊。

- [ ] **Step 3：舊 WebView 機器（iReader Ocean 4 Plus）重複 Step 1～2**

Review Focus 3、4。這台沒有 adb，用 APK 側載；無法側載就在報告標註「未驗」並說明原因，由使用者決定是否阻擋合併。

- [ ] **Step 4：失敗處理**

任一項失敗：先查是否為 R8／proguard 規則問題（對照升級前 release APK 的行為）；無法在「找相容新版 → 本地修補」內解決就依「回退條件」整組還原。

---

### Task 5：文件收尾與最終驗證

**Files:**
- Modify：`docs/epics/epic-66-windows-port/issues.md`（Issue 17 列狀態、段落補「已完成」與報告連結）
- Modify：`docs/epics.md`（`epic-66` 備註的 Issue 17 字樣更新）
- Modify：`docs/epics/epic-66-windows-port/issue-17-report.md`（最終結論）
- Delete（本機）：`%USERPROFILE%\.gradle\gradle.properties` 的 `allowDebugSigning=true`、`build-before.log`、`build-after-debug.log`

- [ ] **Step 1：清理暫時設定**

刪除使用者層級 `gradle.properties` 內的 `allowDebugSigning=true`（檔案若只剩這一行就刪檔），並刪除兩份 build log。
Expected：`git status --short` 沒有 log 或 `gradle.properties` 的異動。

- [ ] **Step 2：完整測試與靜態檢查各跑一次**

Run（於 `app/`）：`flutter analyze`、`flutter test`、`node tool/check_l10n_hardcoded_strings.js`
Expected：`No issues found!`；測試全數通過（記下數量）；檢查腳本無輸出問題。

- [ ] **Step 3：更新看板與 Issue 狀態**

`issues.md` 第 17 列改為「🟡 已實作，待合併」（合併後再改「已合併（PR #N）」）；`issue-17-report.md` 寫最終結論：驗收 5 項各自通過／未驗，以及已知殘留（9 個 KGP 外掛警告）與後續觀察項目（`file_picker` 升版、built-in Kotlin 遷移、`ORG_GRADLE_PROJECT_allowDebugSigning` 環境變數無效）。

- [ ] **Step 4：Commit 並請使用者審查合併**

```bash
git add docs
git commit -m "docs(epic-66): Issue 17 驗證報告與狀態更新"
```

之後由人類審查、決定合併。程式碼審查報告存 `docs/epics/epic-66-windows-port/reviews/review-code-issue-17.md`（該目錄已被 `.gitignore` 排除，不進版控），審查者先出報告、不直接修改。
