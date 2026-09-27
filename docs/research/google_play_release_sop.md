# elinkBook 上架 Google Play SOP

這份 SOP 只給發布者本人使用。內容照執行順序排列，分成三部分：

- **第 1 部分**：一次性準備，只做一次。
- **第 2 部分**：第一次上架。
- **第 3 部分**：之後每次發新版。

最後修訂：2026-09-27

---

## 0. 基本資料

| 項目 | 值 |
|---|---|
| 套件名稱（applicationId） | `cc.ugotit.elinkbook` |
| 商店名稱 | `elinkBook 易閱書` |
| 商店語言 | 正體中文（zh-TW），只做這一種 |
| 價格 | 免費。上架後不能改成付費 |
| 國家／地區 | 全部 |
| 目標年齡 | 13 歲以上 |
| 隱私權政策 | `https://www.ugotit.cc/privacy`（原始檔：`site/privacy.html`） |
| 開發者帳號 | 個人帳號，2023-11-13 以前建立，不需要跑「12 人、連續 14 天」封閉測試 |
| 簽章方式 | Play App Signing（Google 保管正式金鑰，你只保管上傳金鑰） |
| 發布軌道 | 內部測試 → 正式版 |
| 商店素材 | `store/google-play/zh-TW/` |
| 版本對照表 | `store/google-play/release-log.md` |

### 三個會搞混的東西

```
上傳金鑰（upload key）
  你自己產生、自己保管。每次上傳 .aab 都用它簽章。
  丟了可以跟 Google 申請重設。

Play 簽章金鑰（app signing key）
  Google 保管。使用者從商店下載的 App 用它簽章。
  你拿不到檔案，只看得到它的指紋。

debug 金鑰
  flutter run 自動使用，只給開發用。Play 不收用它簽章的檔案。
```

### 版本號規則

版本號寫在 `app/pubspec.yaml`：

```
version: 1.0.1+2
         ─┬─── ┬
          │    └─ versionCode：每次上傳加 1，只能變大
          │                    內部測試和正式版共用同一組
          └────── versionName：使用者看得到
                   修 bug → 改第三碼（1.0.0 → 1.0.1）
                   新功能 → 改第二碼（1.0.1 → 1.1.0）
                   大改版 → 改第一碼（1.1.0 → 2.0.0）
```

- 同一個 versionCode 從內部測試推到正式版，**不用重新建置**。
- 對照表的 commit 欄位記的是「執行 `bump_version.js` 當下的 HEAD」，也就是這一版程式碼的最後一個 commit。git tag 指向的是之後的版本號 commit，兩者相差一個 commit，這是正常的。
- 內部測試版有問題要重傳，versionCode 就要加 1。Play 不收重複的 versionCode。

---

## 1. 一次性準備

### 1.1 前置條件

開始第 2 部分之前，`epic-52-play-release` 的三個 Issue 都要完成：

1. release 建置改用上傳金鑰簽章。
2. `site/privacy.html` 補上 PocketBase 同步服務的段落。
3. 建立 `app/tool/bump_version.js` 與 `store/google-play/release-log.md`。

**警告：**Issue 1 沒完成前，`flutter build appbundle` 產出的檔案是用 debug 金鑰簽章的，Play 會拒收。

### 1.2 產生上傳金鑰

1. 建立資料夾 `C:\Users\huthief\.android-keys\`。
2. 執行下面的指令。依提示輸入密碼和姓名等資料。指令只有一行，PowerShell 和 Git Bash 都能用。

   ```bash
   keytool -genkeypair -v -keystore "C:/Users/huthief/.android-keys/elinkbook-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

3. 把 `.jks` 檔和兩組密碼（store password、key password）存進密碼管理器，檔案用附件方式存。

**警告：**`.jks` 檔和密碼絕對不能進 git。

### 1.3 建立 `key.properties`

建立 `app/android/key.properties`，內容如下：

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=C:/Users/huthief/.android-keys/elinkbook-upload.jks
```

`storeFile` 一定要寫絕對路徑。寫相對路徑時，Gradle 會從 `app/android/app/` 開始找，很容易找錯。

確認它沒有被 git 追蹤：

```bash
git check-ignore -v app/android/key.properties
```

輸出要有 `app/android/.gitignore` 和 `key.properties`，表示這個檔案被忽略了。`app/android/.gitignore` 本來就忽略 `key.properties`、`*.jks`、`*.keystore`，不用另外設定。

### 1.4 準備商店素材

素材都放在 `store/google-play/zh-TW/`。

| 素材 | 規格 | 來源 |
|---|---|---|
| App 圖示 | 512×512 PNG，32 位元 | 從 `assets/appicon_v2.jpg`（1024×1024）轉檔 |
| 主題圖片 | 1024×500 PNG 或 JPG | 另外製作 |
| 手機截圖 | 至少 2 張，建議 4～8 張，長邊 320～3840 px | 從真機截圖 |

轉圖示的指令（在 repo 根目錄用 Git Bash 執行）：

```bash
mkdir -p store/google-play/zh-TW
python -c "from PIL import Image; Image.open('assets/appicon_v2.jpg').convert('RGBA').resize((512,512), Image.LANCZOS).save('store/google-play/zh-TW/icon-512.png')"
```

截圖建議拍這幾個畫面：

1. 書架（格狀檢視）
2. 直排閱讀畫面
3. 版面設定
4. PDF 閱讀畫面
5. E-Ink 模式

### 1.5 準備商店文字

| 欄位 | 上限 | 內容方向 |
|---|---|---|
| 應用程式名稱 | 30 字元 | `elinkBook 易閱書` |
| 簡短說明 | 80 字元 | 放關鍵字：繁體中文直排、E-Ink、EPUB／PDF |
| 完整說明 | 4000 字元 | 功能清單，可以參考 `site/index.html` |

文字存在 `store/google-play/zh-TW/listing.md`，下次改版可以直接複製。

### 1.6 錄製朗讀功能示範影片

`AndroidManifest.xml` 宣告了 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`，這是朗讀功能要用的。Play 會要你說明用途，並附影片網址。

1. 在真機上錄 30 秒左右的影片，內容包含：
   - 打開一本書，開始朗讀。
   - 回到桌面，確認朗讀還在繼續。
   - 下拉通知列，看到朗讀控制通知。
2. 上傳到 YouTube，設為「不公開」。
3. 把網址記在 `store/google-play/zh-TW/listing.md`。

### 1.7 確認隱私權政策

打開 `https://www.ugotit.cc/privacy`，逐項確認：

- [ ] 頁面不用登入就打得開。
- [ ] 寫了 PocketBase 同步服務：會上傳 email、閱讀位置、書籤、劃線與備註。
- [ ] 寫了 Google Drive、OneDrive 登入。
- [ ] 寫了 Wi-Fi 傳書只在區域網路內傳輸。

---

## 2. 第一次上架

### 2.1 在 Play Console 建立應用程式

1. 打開 [Play Console](https://play.google.com/console)，點「建立應用程式」。
2. 依下表填寫：

   | 欄位 | 值 |
   |---|---|
   | 應用程式名稱 | `elinkBook 易閱書` |
   | 預設語言 | 中文（台灣）– zh-TW |
   | 應用程式或遊戲 | 應用程式 |
   | 免費或付費 | 免費 |

3. 勾選兩個聲明，點「建立應用程式」。

### 2.2 填寫「應用程式內容」

左側選單「政策與計畫」→「應用程式內容」。每一項都要填完，才能送審。

| 項目 | 怎麼填 |
|---|---|
| 隱私權政策 | `https://www.ugotit.cc/privacy` |
| 應用程式存取權 | 核心功能不用登入。同步功能要登入，所以提供一組測試用 PocketBase 帳號和伺服器網址給審查人員。見下方警告 |
| 廣告 | 不含廣告 |
| 內容分級 | 填問卷。類別選「參考資料、新聞或教育」之類的工具型類別。暴力、色情、賭博等題目都回答「否」 |
| 目標對象 | 13 歲以上。不勾選 13 歲以下的年齡層，這樣不會套用「家庭政策」 |
| 新聞應用程式 | 否 |
| 資料安全性 | 見 2.3 |
| 政府應用程式 | 否 |
| 金融功能 | 無 |
| 健康 | 無 |
| 前景服務權限 | 類型選「媒體播放」。說明寫「朗讀電子書內容，使用者離開畫面後繼續播放」。附上 1.6 的影片網址 |

**警告：**給審查人員的 PocketBase 網址，一定要是外部網路連得到的 HTTPS 網址。填區域網路 IP（例如 `http://192.168.x.x:8090`）時，審查人員會連不上，並以「功能損壞」退件。送審前，先用手機行動網路（關掉 Wi-Fi）登入這組帳號一次。

**帳號刪除規定不適用：**App 只能登入同步帳號，不能在 App 裡註冊帳號。表單問到「是否能在應用程式中建立帳號」時回答「否」。

**注意：**如果以後加了 App 內註冊功能，就要同時提供 App 內刪除帳號的功能，以及一個網頁版的刪除申請網址。

### 2.3 填寫「資料安全性」

依實際行為填寫，內容要跟隱私權政策一致。對不上的話，審查可能被退件。

| 問題 | 回答 |
|---|---|
| 是否收集或分享使用者資料 | 是 |
| 傳輸時是否加密 | 是（HTTPS） |
| 使用者能否要求刪除資料 | 可以。寫信到 `app@ugotit.cc`，隱私權政策第六節有說明 |
| 資料刪除要求網址（表單要求時才填） | `https://www.ugotit.cc/privacy` |

會勾選的資料類型：

| 資料類型 | 用途 | 是否分享給第三方 | 必要或選用 |
|---|---|---|---|
| 個人資訊 → 電子郵件地址 | 帳號管理（同步登入） | 否 | 選用 |
| 應用程式活動 → 其他使用者產生的內容（書籤、劃線、備註） | 應用程式功能（同步） | 否 | 選用 |
| 應用程式活動 → 其他動作（閱讀位置） | 應用程式功能（同步） | 否 | 選用 |

**不用勾選的項目：**

- 書籍檔案、簡繁轉換、朗讀都在本機處理，沒有上傳。
- Google Drive、OneDrive 的檔案直接下載到裝置，不經過你的伺服器。

### 2.4 設定商店資訊

左側選單「拓展」→「商店資訊」→「主要商店資訊」。

1. 貼上 1.5 準備好的名稱、簡短說明、完整說明。
2. 上傳 1.4 的圖示、主題圖片、截圖。
3. 「應用程式類別」選「圖書與參考資源」。
4. 填聯絡信箱和網站 `https://www.ugotit.cc/`。

### 2.5 建置 `.aab`

1. 更新版本號，並在對照表加一筆：

   ```bash
   cd app
   node tool/bump_version.js
   ```

   第一次上架用 `1.0.0+1`。腳本問「versionCode 要加 1 嗎」時回答 `n`。對照表還沒有紀錄，所以腳本會接受目前的值。

   提交版本號變更：

   ```bash
   git add pubspec.yaml ../store/google-play/release-log.md
   git commit -m "chore(release): 1.0.0+1"
   ```

2. 確認分析和測試都通過：

   ```bash
   flutter analyze
   flutter test
   ```

3. 建置 App Bundle：

   ```bash
   flutter build appbundle --release --dart-define-from-file=config/cloud_oauth.json
   ```

   **警告：**一定要帶 `--dart-define-from-file`。少了它，Google Drive、OneDrive 登入會用到樣板的假 Client ID，登入一定失敗。

4. 產出的檔案在（相對於 `app/`）：

   ```
   build/app/outputs/bundle/release/app-release.aab
   ```

5. 確認它是用上傳金鑰簽章：

   ```bash
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```

   輸出的 `擁有者`（Owner）要是你在 1.2 填的資料。如果看到 `CN=Android Debug`，就是還在用 debug 金鑰，不能上傳。

### 2.6 上傳到內部測試

1. 左側選單「測試與發布」→「測試」→「內部測試」。
2. 「測試人員」分頁：建立一個電子郵件清單，至少加入你自己的 Google 帳號。
3. 點「建立新版本」。
4. 第一次會問要不要使用 Play App Signing，選「使用 Google 產生的金鑰」。
5. 上傳 `app-release.aab`。
6. 版本名稱會自動帶入，例如 `1 (1.0.0)`。
7. 「版本資訊」寫這次改了什麼，用 `<zh-TW>…</zh-TW>` 標籤包起來。
8. 點「儲存」→「審查版本」→「開始推出到內部測試」。

**警告：**Play App Signing 一旦啟用，就不能退出。

### 2.7 在真機上確認內部測試版

1. 「內部測試」→「測試人員」分頁，複製「加入測試的連結」。
2. 用手機打開連結，接受邀請，從 Play 商店安裝。
3. 依序確認：

   - [ ] App 能開啟，書架正常顯示。
   - [ ] 匯入一本 EPUB，直排、橫排都正常。
   - [ ] 匯入一本 PDF，能正常翻頁。
   - [ ] 朗讀能在背景繼續播放。
   - [ ] 登入 PocketBase 同步，閱讀位置能同步。
   - [ ] 登入 Google Drive，能列出檔案並匯入一本書。
   - [ ] 登入 OneDrive，能列出檔案並匯入一本書。

如果 Google Drive 登入失敗，先看第 4 部分的疑難排解。

### 2.8 推到正式版

1. 「內部測試」→ 找到剛才的版本 →「升級版本」→「正式版」。
2. 「國家／地區」分頁：選「新增國家／地區」→ 全選。
3. 「推出比例」第一次填 `100%`。
4. 點「審查版本」→「開始推出到正式版」。
5. 左側選單「發布總覽」會顯示「審查中」。第一次審查通常要 3～7 天。

### 2.9 審查通過之後

1. 在對照表 `store/google-play/release-log.md` 手動加一行，軌道寫「正式版」，commit 欄位抄內部測試那一行。
2. 提交對照表：

   ```bash
   git add store/google-play/release-log.md
   git commit -m "docs(release): 1.0.0+1 推到正式版"
   ```

3. 打 git tag 並推上遠端：

   ```bash
   git tag v1.0.0+1
   git push origin main v1.0.0+1
   ```

4. 記下 Play 簽章金鑰的 SHA-1。之後如果要改用 Android 類型的 OAuth 用戶端，會用到它。位置：「測試與發布」→「設定」→「應用程式完整性」→「應用程式簽署」。

---

## 3. 每次發新版

```
改程式 → bump_version.js → analyze / test → build appbundle
      → 上傳內部測試 → 真機確認 → 升級到正式版 → 記錄 + 打 tag
```

1. 確認 `main` 是乾淨的，所有要發布的變更都合併了：

   ```bash
   git status
   git pull
   ```

2. 更新版本號：

   ```bash
   cd app
   node tool/bump_version.js
   ```

   腳本會顯示目前版本和對照表最後一筆，再問你要不要加 1。versionCode 一定要加 1。versionName 依「版本號規則」決定。

3. 提交版本號變更：

   ```bash
   git add pubspec.yaml ../store/google-play/release-log.md
   git commit -m "chore(release): 1.0.1+2"
   ```

4. 執行 2.5 的第 2～5 步（analyze、test、build、確認簽章）。
5. 執行 2.6 的第 3～8 步（這次不會再問 Play App Signing）。
6. 執行 2.7 的檢查清單。這次改到的功能要多測幾次。
7. 執行 2.8。「推出比例」可以先填 `20%`，沒問題再調到 `100%`。
8. 執行 2.9 的第 1～3 步。

### 內部測試版有問題

1. 修好程式。
2. 從第 2 步重來，versionCode 再加 1。
3. 有問題的那一版不用推到正式版，對照表的說明欄註記「棄用」。

---

## 4. 疑難排解

| 狀況 | 原因 | 怎麼處理 |
|---|---|---|
| 上傳時顯示「版本代碼已使用過」 | versionCode 沒有加 1 | 執行 `node tool/bump_version.js`，加 1 後重新建置 |
| 上傳時顯示「以偵錯模式簽署」 | release 還在用 debug 金鑰 | 確認 `app/android/key.properties` 存在，且 epic-52 Issue 1 已完成 |
| 上傳時顯示「簽署金鑰不符」 | 用了別把金鑰簽章 | 確認 `key.properties` 的 `storeFile` 指向 `elinkbook-upload.jks` |
| 上傳金鑰遺失 | 檔案或密碼找不到 | 先從密碼管理器還原。還原不了，就到「應用程式簽署」頁申請重設上傳金鑰 |
| 審查退件：隱私權政策 | 政策內容和資料安全性表單對不上 | 對照 2.3 修改 `site/privacy.html`，部署後重新送審 |
| 審查退件：前景服務 | 影片沒拍到背景播放 | 重錄 1.6 的影片，要拍到回桌面後還在播放 |
| Google Drive 只有部分帳號能登入 | OAuth 同意畫面還在「測試中」，只有白名單帳號能登入 | 見下方說明 |

### Google Drive 登入與 Play 上架是兩條不同的審查

目前 `app/config/cloud_oauth.json` 用的是**電腦應用程式（Desktop）類型**的 OAuth 用戶端。這種類型不綁 SHA-1，所以換成 Play 簽章金鑰後，登入仍然可以用。

但 `drive.readonly` 屬於受限範圍。OAuth 同意畫面還在「測試中」時，只有白名單上的帳號能登入。要讓所有人都能登入，要在 Google Cloud Console 把同意畫面改成「正式發布」，並通過 Google 的應用程式驗證，可能還要做 CASA 安全評估。

這件事不影響 Play 上架，但會影響一般使用者能不能用 Google Drive 匯入。細節見 `docs/research/cloud_storage_oauth_setup_guide.md` 第 6 節。
