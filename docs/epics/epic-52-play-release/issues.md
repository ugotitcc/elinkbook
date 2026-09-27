# Epic 52 — 上架 Google Play：工單清單 (Issues)

3 個 Issue 沒有共用檔案，可以平行開發。全部完成後，才能照 `docs/research/google_play_release_sop.md` 第 2 部分上架。

```
Issue 1（簽章）  ──┐
Issue 2（隱私權）──┼──> 照 SOP 第 2 部分上架（人類）
Issue 3（版本號）──┘
```

---

## Issue 1：release 建置改用上傳金鑰簽章

**Status:** open

**依賴：** 無。

**What to build：**
- `app/android/app/build.gradle.kts` 讀取 `app/android/key.properties`（欄位：`storePassword`、`keyPassword`、`keyAlias`、`storeFile`），建立 `release` 簽章設定，`buildTypes.release` 改用它。
- `key.properties` 不存在時，release 退回 debug 簽章，並在 Gradle 輸出一行警告。這樣沒有金鑰的環境（例如只跑測試）仍能執行 `flutter run --release`。
- `key.properties` 存在，但 4 個欄位有任何一個缺少或空白時，建置直接失敗，錯誤訊息寫出缺哪個欄位。不退回 debug 簽章，因為這代表發布者想正式簽章卻設定錯了。
- `storeFile` 用 `file()` 解析，並在錯誤訊息和 `key.properties.example` 註明要寫絕對路徑。檔案不存在時建置失敗，錯誤訊息印出解析後的完整路徑。
- 建立 `app/android/key.properties.example` 當樣板，只放欄位名稱和假值。
- 刪除 `build.gradle.kts` 裡「TODO: Add your own signing config」的註解。
- 不用改 `.gitignore`：`app/android/.gitignore` 本來就忽略 `key.properties`、`**/*.jks`、`**/*.keystore`。`key.properties.example` 的檔名不會被這些規則忽略，可以進版控。

**測試要求：**
- 這是 Gradle 設定，沒有單元測試。改用建置驗證：
  - 沒有 `key.properties` 時，`flutter build appbundle` 成功，Gradle 輸出警告，`keytool -printcert -jarfile` 顯示 `CN=Android Debug`。
  - 有 `key.properties` 時，`keytool -printcert -jarfile` 顯示上傳金鑰的擁有者資料。
  - `key.properties` 少一個欄位時，建置失敗，錯誤訊息寫出欄位名稱。
  - `storeFile` 指向不存在的檔案時，建置失敗，錯誤訊息印出完整路徑。
- `git check-ignore -v app/android/key.properties` 的輸出指向 `app/android/.gitignore`。
- `git status` 看得到 `key.properties.example`。

**驗收標準：** 上面四種建置結果都符合；`flutter analyze` 乾淨；`key.properties` 和 `.jks` 不會出現在 `git status`。

**Blocked by：** 無。

---

## Issue 2：隱私權政策補上 PocketBase 同步服務

**Status:** open

**依賴：** 無。

**What to build：**
- `site/privacy.html` 第二節新增一段「閱讀同步服務」，內容：
  - 同步是選用功能，要登入才會啟用。
  - 會上傳的資料：email、閱讀位置、書籤、劃線、備註。
  - 資料存放在 ugotit.cc 維運的 PocketBase 伺服器，傳輸使用 HTTPS。
  - 書籍檔案本身不會上傳。
  - 要刪除雲端資料時，寫信到政策上的聯絡信箱。
- 第六節「使用者權利行使（個資與資料刪除）」新增一條：要刪除 PocketBase 伺服器上的同步資料（email、閱讀位置、書籤、劃線、備註），寫信到 `app@ugotit.cc`。目前這一節只寫了本機資料和撤銷雲端硬碟授權。
- 不寫處理天數（例如「30 日內」）。2026-09-27 發布者決定：一個人維運，不做對外的時間承諾。
- `<meta property="og:url">` 目前是 `https://www.ugotit.cc/elinkbook/privacy.html`，改成 `https://www.ugotit.cc/privacy`。
- 更新頁面上的「最後修訂日期」。
- `site/index.html` 內嵌的 SPA 版政策，第二節和第六節都要同步更新，兩份內容保持一致。

**測試要求：**
- 靜態網頁，沒有單元測試。部署後用瀏覽器打開 `https://www.ugotit.cc/privacy`，確認新段落出現。
- 逐項對照 SOP 第 2.3 節的「資料安全性」表格，每一種勾選的資料類型，政策裡都要有對應說明。
- 第六節有寫雲端同步資料怎麼刪除。

**驗收標準：** 線上頁面顯示第二節和第六節的新內容；`site/privacy.html` 和 `site/index.html` 內容一致；和 SOP 第 2.3 節一致。

**Blocked by：** 無。

---

## Issue 3：版本號腳本與版本對照表

**Status:** open

**依賴：** 無。

**What to build：**
- `app/tool/bump_version.js`：純 Node，不用 npm install。在 `app/` 目錄下執行 `node tool/bump_version.js`，流程如下：
  1. 讀取 `pubspec.yaml` 的 `version:`，顯示目前版本，例如 `1.0.1+5`。
  2. 讀取 `store/google-play/release-log.md` 表格的最後一筆並顯示。表格沒有資料時顯示「尚無紀錄」。
  3. 問「versionCode 要加 1 嗎？[Y/n]」。選 n 時保留 `pubspec.yaml` 裡的值。
     - 對照表有紀錄時，新的 versionCode 必須大於最後一筆的 versionCode。不符合就當場印出「Play 不收重複或變小的 versionCode，最後一筆是 N」，然後重問這一題，不往下走。
     - 對照表沒有紀錄（第一次上架）時，不做這項比較，versionCode 只要是正整數就接受。
     - 選 n 的合理情境：第一次上架，或是已經手動改過 `pubspec.yaml`，數字已經大於最後一筆。
  4. 問「versionName（直接 Enter 表示不改）」，輸入的值要符合 `數字.數字.數字`，不符合就重問。
  5. 寫回 `pubspec.yaml`，只改 `version:` 那一行。用 `^version:` 的單行正規表示式取代，不把整個檔案拆行再組回去，保留原本的換行符號（目前工作目錄裡是 CRLF）。
  6. 在對照表加一筆：versionName、versionCode、今天日期（`YYYY-MM-DD`，不含時間）、軌道「內部測試」、commit、說明留空。對照表也照第 5 步的方式保留原本的換行符號。
     - commit 欄位是 `git rev-parse --short HEAD` 的結果，意思是「這一版程式碼的最後一個 commit」。之後的版本號 commit 和 git tag 會比它多一個 commit，這是預期中的。
     - `git` 指令失敗時（沒安裝 git、不在 repo 裡），commit 欄位填 `unknown`，印出一行警告，腳本繼續執行。
- 支援 `--yes` 旗標：不詢問，直接 versionCode 加 1、versionName 不變。加 1 後仍不大於最後一筆時，印出錯誤並結束，結束碼非 0，不寫入任何檔案。
- 建立 `store/google-play/release-log.md`，含表頭和欄位說明（日期格式 `YYYY-MM-DD`；commit 欄位的意思同上）：

  ```
  | versionName | versionCode | 日期 | 軌道 | commit | 說明 |
  ```

- `app/tool/README.md` 新增一節說明用法。

**單元測試要求：**
- `app/tool/test_bump_version.mjs`，用 Node 內建的 `node:test`。把讀寫邏輯拆成純函式來測，不測互動輸入：
  - 解析 `version: 1.0.1+5`，得到 `1.0.1` 和 `5`。
  - 改寫 `version:` 那一行，其他行保持不變（包含註解和空行）。
  - 輸入是 CRLF 的內容時，改寫後除了 `version:` 那一行的版本字串，其餘位元組完全相同，`\r\n` 沒有變成 `\n`。LF 的輸入也一樣保持 LF。
  - 解析對照表最後一筆；只有表頭時回傳「沒有紀錄」。
  - 新的 versionCode 小於或等於最後一筆時，回傳錯誤。
  - 對照表沒有紀錄時，versionCode `1` 被接受。
  - 產生的日期字串符合 `YYYY-MM-DD`。
  - 取得 commit 的函式在 git 指令失敗時回傳 `unknown`，不拋出例外（用注入的假執行函式模擬失敗）。
  - versionName 格式錯誤（`1.0`、`1.0.0.1`、`a.b.c`）時被拒絕。
  - 新增一筆後，表格格式正確，舊資料不變。

**驗收標準：** `node app/tool/test_bump_version.mjs` 全部通過；在暫存資料夾複製 `pubspec.yaml` 和對照表實際執行一次，結果正確。

**Blocked by：** 無。
