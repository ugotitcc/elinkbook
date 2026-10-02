# elinkBook 發佈 release APK SOP

這份 SOP 只給發布者本人使用。目標：用「發佈金鑰」簽出 release APK，放到 GitHub Releases，讓使用者從官網下載。

Google Play 上架（`.aab`）見 `docs/research/google_play_release_sop.md`。兩份 SOP 互相獨立。

最後修訂：2026-10-01

---

## 0. 基本資料

| 項目 | 值 |
|---|---|
| 產物 | release APK，依 ABI 拆開（`--split-per-abi`） |
| 簽章金鑰 | 發佈金鑰（release key），只簽 APK |
| 散布位置 | GitHub Releases（只放 Release 的 repo，原始碼不公開） |
| GitHub repo | `ugotitcc/elinkbook`（公開） |
| 下載入口 | 官網 `site/index.html` 的「下載 Android APK」按鈕 |
| F-Droid | 尚未啟動，見第 5 節 |
| 版本號 | 與 Play 共用 `app/pubspec.yaml` 的 `version` |
| 版本對照表 | `store/google-play/release-log.md`，軌道欄寫「APK」 |

### 三把金鑰，不要搞混

```
上傳金鑰（upload key）
  只簽 .aab，上傳 Play 用。
  遺失可以向 Google 申請重設。

發佈金鑰（release key）
  只簽公開下載的 APK。
  遺失無法補救：已安裝的使用者無法更新，只能解除安裝重裝。

debug 金鑰
  flutter run 自動使用。絕對不能用來發佈。
```

為什麼分兩把：見 `docs/adr/0036-apk-release-key-separate-from-upload-key.md`。

### 商店版與 APK 版只能二選一

商店版和 APK 版的 applicationId 都是 `cc.ugotit.elinkbook`，但簽章不同。Android 不允許互相覆蓋安裝。

- 從商店版換到 APK 版：先解除安裝，書架資料會消失。
- 從 APK 版換到商店版：同上。

**注意：**要在官網下載頁寫清楚這一點。

---

## 1. 一次性準備

### 1.1 建立發佈金鑰

1. 確認資料夾 `C:\Users\huthief\.android-keys\` 已存在（建立上傳金鑰時已建）。
2. 執行下面指令。依提示輸入密碼和姓名。

   ```bash
   keytool -genkeypair -v -keystore "C:/Users/huthief/.android-keys/elinkbook-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias release
   ```

3. 把 `.jks` 檔和兩組密碼（store password、key password）存進密碼管理器，檔案用附件存。
4. 另外備份 `.jks` 到離線位置（例如外接硬碟）。

**警告：**發佈金鑰遺失無法補救。一定要有兩份備份。

**警告：**`.jks` 檔和密碼絕對不能進 git。

### 1.2 建立兩個金鑰設定檔

`build.gradle.kts` 只讀 `app/android/key.properties`。所以要準備兩個檔案，建置前用複製的方式切換。

1. 把現有的 `key.properties`（上傳金鑰）複製成 `key.properties.upload`：

   ```bash
   cp app/android/key.properties app/android/key.properties.upload
   ```

2. 建立 `app/android/key.properties.release`，內容如下：

   ```properties
   storePassword=<發佈金鑰的 store password>
   keyPassword=<發佈金鑰的 key password>
   keyAlias=release
   storeFile=C:/Users/huthief/.android-keys/elinkbook-release.jks
   ```

   `storeFile` 一定要寫絕對路徑，並用正斜線 `/`。

3. 確認三個檔案都被 git 忽略：

   ```bash
   git check-ignore -v app/android/key.properties app/android/key.properties.upload app/android/key.properties.release
   ```

   三行都要有輸出。少一行就先修 `app/android/.gitignore`，不要繼續。

### 1.3 記下發佈金鑰的指紋

1. 執行：

   ```bash
   keytool -list -v -keystore "C:/Users/huthief/.android-keys/elinkbook-release.jks" -alias release
   ```

2. 複製 `SHA256:` 那一行，存進密碼管理器，標題寫「發佈金鑰 SHA-256 指紋」。

之後每次建完 APK，都要拿它比對（見 2.4）。

### 1.4 確認工具

- Flutter 可執行 `flutter build apk`。
- `apksigner` 在 `C:\Users\huthief\AppData\Local\Android\Sdk\build-tools\36.1.0\apksigner.bat`。
- 要用指令發佈 Release，需要 GitHub CLI（`gh`）並登入。沒有也可以用網頁操作。

### 1.5 建立 GitHub Release 專用 repo

1. 在 GitHub 建立 repo `ugotitcc/elinkbook`（已建立）。
2. 設為公開（Public）。私有 repo 的 Release 無法讓未登入的人下載。
3. 只放 README，不放原始碼。

---

## 2. 每次建置 APK

```
bump_version → 換成發佈金鑰 → analyze/test → build apk
   → 換回上傳金鑰 → 確認簽章 → 改檔名、算 SHA-256 → 記錄
```

### 2.1 更新版本號

1. 確認 `main` 乾淨，變更都已合併：

   ```bash
   git status
   git pull
   ```

2. 如果這一版**同時**要上 Play：先走 Play SOP 第 3 部分的第 2～3 步，版本號已經更新，這裡直接跳到 2.2。
3. 如果這一版**只發 APK**：

   ```bash
   cd app
   node tool/bump_version.js
   ```

   versionCode 一定要加 1。腳本會在對照表寫一筆「內部測試」。**這筆要手動改成「APK」**，因為這一版沒有上傳 Play。

4. 提交版本號變更：

   ```bash
   git add pubspec.yaml ../store/google-play/release-log.md
   git commit -m "chore(release): 1.0.1+2"
   ```

### 2.2 換成發佈金鑰

```bash
cp app/android/key.properties.release app/android/key.properties
```

**警告：**建完 APK 要立刻換回上傳金鑰（2.3）。忘了換，下一次建 `.aab` 會用錯金鑰，Play 會拒收。

### 2.3 確認並建置

1. 在 `app/` 下執行：

   ```bash
   flutter analyze
   flutter test
   ```

2. 建置：

   ```bash
   flutter build apk --release --split-per-abi --dart-define-from-file=config/cloud_oauth.json
   ```

   **警告：**一定要帶 `--dart-define-from-file`。少了它，Google Drive、OneDrive 登入會用樣板的假 Client ID，一定失敗。

3. 產物在（相對於 `app/`）：

   ```
   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
   build/app/outputs/flutter-apk/app-x86_64-release.apk
   ```

4. 立刻換回上傳金鑰：

   ```bash
   cp android/key.properties.upload android/key.properties
   ```

### 2.4 確認簽章

對每一個 APK 執行：

```bash
"$LOCALAPPDATA/Android/Sdk/build-tools/36.1.0/apksigner.bat" verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

確認兩件事：

- [ ] 有 `Verifies` 字樣，沒有錯誤。
- [ ] `certificate SHA-256 digest` 與 1.3 記下的發佈金鑰指紋**完全相同**。

如果指紋是上傳金鑰的，或出現 `CN=Android Debug`，代表換金鑰沒成功。回到 2.2 重做，**不要發佈**。

### 2.5 改檔名並算 SHA-256

1. 複製並改名（`<版本>` 用 versionName，例如 `1.0.1`，不含 `+`）：

   ```bash
   mkdir -p build/release-apk
   cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   build/release-apk/elinkbook-<版本>-arm64-v8a.apk
   cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk build/release-apk/elinkbook-<版本>-armeabi-v7a.apk
   cp build/app/outputs/flutter-apk/app-x86_64-release.apk      build/release-apk/elinkbook-<版本>-x86_64.apk
   ```

2. 算 SHA-256：

   ```bash
   cd build/release-apk
   sha256sum *.apk > SHA256SUMS.txt
   cat SHA256SUMS.txt
   ```

3. 保留 `SHA256SUMS.txt`。第 3 節要上傳它，第 4 節要把 arm64 的值貼到官網。

### 2.6 在真機確認

1. 用 USB 或檔案傳輸，把 arm64 APK 裝到真機。
2. 如果手機已裝商店版或 debug 版，先解除安裝。
3. 依序確認：

   - [ ] App 能開啟，書架正常顯示。
   - [ ] 匯入一本 EPUB，直排、橫排都正常。
   - [ ] 匯入一本 PDF，能正常翻頁。
   - [ ] 朗讀能在背景繼續播放。
   - [ ] 登入 PocketBase 同步，閱讀位置能同步。
   - [ ] 登入 Google Drive、OneDrive，能列出檔案。

### 2.7 記錄

1. 在 `store/google-play/release-log.md` 記錄：軌道寫「APK」，說明欄寫「GitHub Releases」。若 2.1 第 3 步已由腳本加了一筆，改那一筆的軌道欄即可。若這一版同時上 Play，另加一列。
2. 提交：

   ```bash
   git add ../store/google-play/release-log.md
   git commit -m "docs(release): 1.0.1+2 APK 建置紀錄"
   ```

---

## 3. 發佈到 GitHub Releases

### 3.1 打 tag

Play 流程已經打過 `v<versionName>+<versionCode>`（見 Play SOP 2.9）。這一版如果**沒上 Play**，在這裡打：

```bash
git tag v1.0.1+2
git push origin main v1.0.1+2
```

APK 與 Play 版共用同一個 tag，因為是同一份程式碼。

### 3.2 建立 Release

用指令（在 `app/build/release-apk/` 下執行）：

```bash
gh release create "v1.0.1+2" --repo ugotitcc/elinkbook --title "elinkBook 1.0.1" --notes "更新內容見下方。商店版與 APK 版無法互相覆蓋安裝。" elinkbook-*.apk SHA256SUMS.txt
```

或用網頁：

1. 打開 `https://github.com/ugotitcc/elinkbook/releases/new`。
2. Tag 輸入 `v1.0.1+2`，選「Create new tag」。
3. 標題寫 `elinkBook 1.0.1`。
4. 說明欄寫：更新內容、最低系統版本（Android 11）、**商店版與 APK 版無法互相覆蓋安裝**、`SHA256SUMS.txt` 的內容。
5. 上傳 3 個 APK 和 `SHA256SUMS.txt`。
6. 點「Publish release」。

**注意：**GitHub 的下載網址裡，`+` 要寫成 `%2B`。例如 `.../releases/tag/v1.0.1%2B2`。

### 3.3 下載確認

1. 用另一個瀏覽器（未登入 GitHub）打開 Release 頁。
2. 下載 arm64 APK，重新算 SHA-256，與 `SHA256SUMS.txt` 比對。

---

## 4. 更新官網下載頁

檔案：`site/index.html`。只有第一次需要改按鈕連結，之後每版只改版本號和 SHA-256。

### 4.1 第一次：改下載按鈕

找到 `下載 Android APK` 那顆按鈕（約第 692 行）：

```html
<a href="#/download" class="btn-download-app">
```

把 `href` 改成：

```html
<a href="https://github.com/ugotitcc/elinkbook/releases/latest" class="btn-download-app" target="_blank" rel="noopener noreferrer">
```

用 `releases/latest` 的好處：之後發新版，按鈕連結不用再改。

### 4.2 第一次：補上校驗值與安裝提醒

在 `app-meta-box` 裡加兩列：

- 「SHA-256（arm64）」：顯示 arm64 APK 的校驗值。
- 「安裝提醒」：寫「商店版與 APK 版無法互相覆蓋，切換前請先解除安裝並備份」。

### 4.3 每版都要改

- [ ] 「目前版本」改成新的 versionName（目前頁面寫 `v1.2.0 (Stable)`，與 `pubspec.yaml` 的 `1.0.0` 不一致，第一次要一併修正）。
- [ ] 「SHA-256（arm64）」換成新值。

### 4.4 頁尾連結

首頁頁尾的「開源專案與回饋」連結已於 2026-10-01 移除（原本連到佔位的 `https://github.com`）。`ugotitcc/elinkbook` 只放 Release、不放原始碼，不能當「開源專案」。日後要加回饋入口，請另行決定。

### 4.5 部署

網站的部署方式不在這份 SOP 範圍。改完 `site/index.html` 後，依你現有的網站部署流程上線，再打開官網確認：

- [ ] 按鈕能連到 GitHub Release 頁。
- [ ] 版本號與 SHA-256 與 Release 上的一致。

---

## 5. F-Droid（尚未啟動）

目前不做。下面只是前置條件清單，等你決定公開原始碼後再另案評估。

| 條件 | 現況 |
|---|---|
| 原始碼公開 | 否。原始碼只在自架 Gitea |
| 開源授權（`LICENSE`） | 否。專案根目錄沒有授權檔 |
| 所有相依套件都是開源 | 尚未逐一確認 |
| 不含專有服務或追蹤 | 尚未逐一確認。要看 Google Drive、OneDrive 登入的實作 |
| 商用字型不進 APK | 符合。字型改為下載（見 ADR 0035），但字型下載服務是否算「非自由網路服務」要確認 |
| 官網寫的授權模式 | 目前寫「個人非商業使用」，與開源授權衝突 |

**注意：**F-Droid 用**它自己的金鑰**簽章。F-Droid 版與 GitHub 版、Play 版之間，三者都無法互相更新。

---

## 6. 疑難排解

| 狀況 | 原因 | 怎麼處理 |
|---|---|---|
| `apksigner` 顯示指紋是上傳金鑰 | 2.2 沒換成功，或建置前被換回 | 重做 2.2，確認 `key.properties` 的 `keyAlias` 是 `release` |
| 建置失敗：`release 簽章設定不完整` | `key.properties` 缺欄位 | 對照 1.2 補齊 4 個欄位 |
| 建置時警告用 debug 金鑰 | `key.properties` 不存在 | 重做 2.2 |
| 使用者回報「與已安裝的套件衝突」 | 手機裝的是商店版或 debug 版 | 請使用者解除安裝後再裝 |
| 使用者回報無法更新 | 上一版用了不同金鑰簽章 | 確認每一版都用發佈金鑰。已用錯的版本只能請使用者解除安裝 |
| 手機不讓安裝 | 沒開「允許安裝未知來源應用程式」 | 在系統設定允許瀏覽器或檔案管理員安裝 |
| Google Drive 只有部分帳號能登入 | OAuth 同意畫面還在「測試中」 | 見 Play SOP 第 4 部分最後一節 |
| 下載網址 404 | tag 裡的 `+` 沒寫成 `%2B` | 改用 `releases/latest` 或把 `+` 編碼 |
