# 圖書庫與匯入（Library & Import）——模組地圖與深度報告

> 產出方式：`/zoom-out` 技能，透過子代理（subagent）閱讀原始碼與 SDD 文件彙整而成。
> 涵蓋範圍：圖書庫核心（`LibraryRepository`/`Book`）、本機匯入（`BookImportService`）、雲端匯入（Google Drive／OneDrive OAuth）。
> 產出日期：2026-08-20。

---

## 第一部分：模組地圖（Overview）

路徑皆相對 `app/`（除非特別標明完整路徑）。

### 1. 分層總覽

```
main.dart（組裝根，唯一 new 具象型別的地方）
   │
   ├─ SqliteLibraryRepository.open() ──implements──> LibraryRepository（抽象介面）
   ├─ BookImportServiceImpl() ────────implements──> BookImportService（抽象介面）
   └─ 雲端匯入鏈（見第四節）
   │
   └─ 全部注入 ElinkBookApp → LibraryScreen（組裝樞紐，本身不 new 任何依賴）
```

### 2. 圖書庫核心

- **`LibraryRepository`**（`lib/library/library_repository.dart`）：books/groups 兩張表的唯一存取入口。`insertBook`/`updateBook`/`deleteBook`/`listBooks`、`listGroups`/`upsertGroup`/`renameGroup`/`deleteGroup`，加三種重複匯入偵測（`findByRemoteBookId`/`findByContentFingerprint`/`findByCloudFileId`）。
- **`SqliteLibraryRepository`**（`lib/library/sqlite_library_repository.dart`）：正式實作，sqflite schema **v23**。暴露 `.database` getter，讓其他 repository（`BookmarksRepository`、`HighlightsRepository`、`SqliteRemoteServerRepository` 等）共用同一連線以滿足外鍵約束。
- **`Book`**（`lib/library/models/book.dart`）：核心資料模型，欄位涵蓋格式、來源（local/googleDrive/oneDrive/calibreOpds）、進度定位（`epubLocator`/`pdfPageIndex`）、雲端關聯（`cloudFileId`/`remoteServerId`）、分類（`groupName`）。`BookGroup`（分類，含系統保留值「未分類」）、`library_enums.dart`（`BookFileFormat`/`BookSource`/`LibrarySortBy`/`LibraryViewMode`）同層。

### 3. 匯入服務

- **`BookImportService`**（抽象）／**`BookImportServiceImpl`**（`lib/library/`）：`importFiles(...)`（單檔，支援指定 `source`/`cloudFileIds` 供雲端匯入複用）、`importFolder(...)`（資料夾匯入，`autoGroupByFolderName` 對應 FR-34「依資料夾名稱自動建立分類」→ 呼叫 `repository.upsertGroup`）。旁支模組：`cbz_import.dart`、`txt_epub_synthesizer.dart`／`md_epub_synthesizer.dart`（落地合成 EPUB，對應 ADR 0023）、`book_content_fingerprint.dart`（重複偵測指紋）。

### 4. 雲端匯入（`lib/cloud_import/`）

依賴鏈：

```
CloudOAuthConfig（純常數，--dart-define 讀入）
   ↓
GoogleDriveOAuthClient / OneDriveOAuthClient ──依賴──> CloudAccountRepository
   ↓                                                      ↑
GoogleDriveStorageClient / OneDriveStorageClient    SecureStorageCloudAccountRepository
   ↓ implements                                          （flutter_secure_storage）
CloudStorageClient（介面：listFolder/downloadFile/fetchThumbnail）
   ↓
CloudBrowserScreen（UI，只認介面不認 provider）
   ↓
cloud_book_downloader.dart（downloadCloudFileToTempFile → promoteCloudFileToPermanent）
   ↓
BookImportService.importFiles(source: googleDrive/oneDrive, cloudFileIds: {...})
```

相關畫面：`CloudAccountSettingsScreen`（帳號連結/解除）、`CloudBrowserScreen`、`CloudDownloadQueueDialog`。

### 5. LibraryScreen 呼叫者關係

`LibraryScreen` 是純組裝樞紐——不 new 任何依賴，全靠建構子注入。與 `ReaderScreen` 的介面很關鍵：**`_openBook()` 只傳 `bookId` + `libraryRepository`，不傳整個 `Book` 物件**——`ReaderScreen` 自行查詢/寫回，避免舊快照覆蓋剛寫回的進度。批次操作靠 `_selectedBookIds`（`null` = 非選取模式）驅動一整組 `_moveSelectedBooksToGroup`/`_deleteSelectedBooks`/`_forceFixedLayoutForSelectedBooks` 等方法。

### 6. 測試分佈

`test/library/`（核心/模型/匯入）、`test/cloud_import/`（OAuth/雲端存取）、`test/screens/`（畫面/對話框）、`test/support/`（`FakeLibraryRepository`/`FakeBookImportService`/`FakeCloudAccountRepository`/`FakeCloudStorageClient` 等測試替身，被上述測試共用）。

---

## 第二部分：深度報告 A——雲端匯入 OAuth 流程

### A.0 檔案清單與設計文件出處

核心程式碼位於 `app/lib/cloud_import/`：

| 檔案 | 職責 |
|---|---|
| `cloud_oauth_config.dart` | 編譯期常數集中管理（client id/secret/redirect scheme） |
| `google_drive_oauth_client.dart` | Google Drive PKCE 登入/續期執行者 |
| `onedrive_oauth_client.dart` | OneDrive（Microsoft Graph）PKCE 登入/續期執行者 |
| `cloud_account_repository.dart` | 帳號持久化抽象介面 + `CloudAccountTokens` 資料模型 |
| `secure_storage_cloud_account_repository.dart` | 用 `flutter_secure_storage` 實作上述介面 |
| `cloud_provider.dart` | `enum CloudProvider { googleDrive, oneDrive }` |

這塊功能的設計決策不是走 `docs/adr/`，而是走本專案的 SDD 流程：`docs/epics/epic-29-cloud-import/spec.md`（規格）、`issues.md`（逐 issue 決策紀錄）、`plans/plan-issue-*.md`（實作計劃）、`reviews/`（審查報告）。**`docs/adr/` 目錄內確認沒有針對「Google Drive OAuth 用戶端類型改設定檔驅動」這次變更的獨立 ADR**——決策紀錄落在 `docs/epics/epic-29-cloud-import/issues.md` 的 **Issue 8**（第 219-249 行）與對應的 `plans/plan-issue-8.md`。

### A.1 `cloud_oauth_config.dart`

**讀值機制**：`googleClientId`/`googleClientSecret`/`oneDriveClientId` 都用 `String.fromEnvironment('KEY', defaultValue: ...)`，是 Dart **編譯期常數**，只能透過 `flutter run/build --dart-define-from-file=config/cloud_oauth.json` 注入，執行期無法動態改變。未提供時的回退值：
- `googleClientId` → 樣板字串 `'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com'`
- `oneDriveClientId` → `'YOUR_ONEDRIVE_OAUTH_CLIENT_ID'`
- `googleClientSecret` → **空字串 `''`**（不是樣板字串——這是下方 Issue 8 變更的重點）

這代表一般 `flutter analyze`／`flutter test`／不帶 dart-define 的 `flutter run` 完全不受影響（用樣板值編譯得過，只是無法真的發起登入）。

**PKCE 相關設定不在這裡**：這個檔案只放靜態、跟登入流程無關的設定值。PKCE 的 code_verifier/code_challenge 是每次登入呼叫時的動態隨機值，寫在 `google_drive_oauth_client.dart`／`onedrive_oauth_client.dart` 各自的私有方法裡。

### A.2 `googleIsConfidentialClient`——Issue 8 的核心變更

**背景**：真機實測 Google Drive 登入卡在「已封鎖存取權」。排查出兩層原因：

1. 原本 `prompt: 'consent'` 不強制跳出帳號選擇畫面，若系統瀏覽器已登入的帳號不在白名單內會直接被擋，使用者沒機會換帳號（後續已改為 `prompt: 'select_account'`）。
2. **更根本的原因**：Google Cloud Console 的「Android 類型」OAuth 用戶端，除了 OAuth 同意畫面的「測試使用者白名單」外，還有一道**獨立的應用程式擁有權驗證**（需連結 Google Play Console、驗證 SHA-1 簽署憑證），無論同意畫面是否為「測試中」都必須完成、且需要時間，**無法用白名單繞過**。

使用者因此手動把用戶端改成「電腦應用程式（Desktop）」類型，這是機密客戶端（confidential client），登入當下能成功（commit `eaf8ba1`）。

**Issue 8 做的事**：把「目前是 Android 公開客戶端還是 Desktop 機密客戶端」這件事，從程式碼裡的隱含假設，收斂成**完全由設定檔 `GOOGLE_OAUTH_CLIENT_SECRET` 是否留空決定**的開關，未來換類型不必改任何 `.dart` 檔：
- `googleClientSecret` 的 `defaultValue` 從樣板字串改為空字串——「留空」本身就是 Android 類型下的合法狀態。
- 新增 `googleIsConfidentialClient => googleClientSecret.isNotEmpty`，供人工核對語意用（實際判斷分支**不是**呼叫這個 getter，見 A.4）。

**順帶修復的既有缺陷**：核對 `eaf8ba1` 實際 diff 時發現，`link()`（authorization_code 換發）原本無條件帶 `client_secret`，但 `ensureValidAccessToken()`（refresh_token 換發）**完全沒帶**。依 RFC 6749，機密客戶端在 refresh_token grant 也必須帶 client secret 驗證身分——這代表 Desktop 類型登入當下成功，但 access token 過期後的靜默續期會被 Google 判定為 `invalid_client` 而失敗，退化成強制使用者重新登入。這是一個**真實 bug**，不是假設性風險。

### A.3 redirect scheme 推導與雙處鏡射的技術債

- `googleRedirectScheme`：用 Google 的「反向客戶端 ID」慣例，把 `googleClientId` 的 `.apps.googleusercontent.com` 後綴去掉、前綴 `com.googleusercontent.apps.`。`googleRedirectUri` = `$googleRedirectScheme:/oauth2redirect`。
- `oneDriveRedirectScheme` = `'msal$oneDriveClientId'`（MSAL 慣例，跟 Google 的反向網域格式不同）。`oneDriveRedirectUri` = `$oneDriveRedirectScheme://auth`。

**關鍵限制**：這兩組 scheme 必須跟 `app/android/app/build.gradle.kts` 裡**獨立實作的同一套推導公式**完全一致——因為 Dart 編譯期常數無法被 Gradle 建置腳本讀取，兩處程式碼各自獨立重算一次同樣的字串運算，**修改其中一處務必同步修改另一處**。這是一個「兩處鏡射邏輯、無法用共用程式碼消除」的已知技術債，靠註解互相提醒維持同步。

### A.4 `GoogleDriveOAuthClient` 完整流程

**端點與 scope**：授權端點 `https://accounts.google.com/o/oauth2/v2/auth`；token 端點 `https://oauth2.googleapis.com/token`；userinfo 端點 `https://www.googleapis.com/oauth2/v2/userinfo`；scope `drive.readonly email openid profile`（明確定案用 `drive.readonly` 而非 `drive.file`，因為需求是「使用者可瀏覽任意雲端資料夾挑書」）。

**`link()` 步驟**：
1. 產生 PKCE 素材：`verifier`（64 bytes，`Random.secure()`，base64url 無 padding）；`challenge`（對 verifier 做 SHA-256 再 base64url，即 `S256` 方法）；另產生 `state`（CSRF 防護）。
2. 組授權 URL：帶 `client_id`/`redirect_uri`/`response_type=code`/`scope`/`code_challenge`/`code_challenge_method=S256`/`state`/`access_type=offline`/`prompt=select_account`。
3. 呼叫 `FlutterWebAuth2.authenticate(...)` 開系統瀏覽器（**不用內嵌 WebView，Google 政策明確禁止**）——Android 走 Custom Tabs、iOS 走 `ASWebAuthenticationSession`。任何例外（含使用者取消）捕捉並回傳 `false`，不拋出。
4. 系統依 Android `intent-filter` 攔截 redirect（見 A.6）把控制權交還 App，`authenticate()` 回傳完整 redirect URL，解析出 `code`/`state`；`state` 不吻合直接判失敗。
5. 用 code 換 token：POST 到 token 端點，body 透過 `_tokenRequestBody()` 組裝（`code`/`client_id`/`code_verifier`/`grant_type=authorization_code`/`redirect_uri`）。
6. 解析 token 回應：`access_token`/`refresh_token`/`expires_in` 任一缺失或 JSON 解析失敗都視為失敗。
7. 呼叫 `_fetchEmail(accessToken)` 拿 email。
8. 寫入 repository：組出 `CloudAccountTokens`（`expiresAt = now + expiresIn 秒`），回傳 `true`。

全程刻意不拋出例外——取消登入、state 不符、任何網路呼叫失敗都回傳 `false`，UI 層只需處理布林值。

**`ensureValidAccessToken()` 靜默續期**：
1. 讀已存 tokens；沒有（未連結）直接回傳 `null`，不發任何網路請求。
2. **過期判斷**：`expiresAt.isBefore(now + 60 秒)`——不是「已過期才續」，而是**還有 60 秒內就要過期也提前續**，避免請求途中跨過期線。
3. 未到閾值直接回傳現有 token，同樣不發請求。
4. 需要續期時 POST refresh_token grant；**token 滾動處理**：若回應內含新的 `refresh_token` 就採用，沒有就沿用舊值。
5. 失敗一律回傳 `null`，**刻意不主動呼叫 `unlink()`**——失敗通常代表授權已被撤銷，但要不要真的解除連結交給使用者手動決定（`spec.md` 定案行為）。

**confidential vs public client 分支**（Issue 8 Task 2 產出）：
```dart
GoogleDriveOAuthClient({
  required CloudAccountRepository accountRepository,
  http.Client? httpClient,
  String clientSecret = CloudOAuthConfig.googleClientSecret,
})

Map<String, String> _tokenRequestBody(Map<String, String> params) {
  if (_clientSecret.isEmpty) return params;
  return {...params, 'client_secret': _clientSecret};
}
```
不是直接在方法內讀 `CloudOAuthConfig.googleClientSecret`，而是透過建構子具名參數注入（預設值才取編譯期常數）——理由：`flutter test` 執行期無法動態切換編譯期常數，若不透過建構子注入就沒有測試 seam 能驗證「公開客戶端不帶 secret／機密客戶端帶 secret」兩種分支。`link()` 與 `ensureValidAccessToken()` **兩處 token 端點呼叫現在都改走同一個 `_tokenRequestBody()`**，正是修復前述不一致缺陷的手段。

**一個刻意的設計決策**：`_tokenRequestBody()` 判斷用的是建構子注入的 `_clientSecret`，而**不是**呼叫 `CloudOAuthConfig.googleIsConfidentialClient`——後者直接讀編譯期常數，若改用會繞過建構子注入值、讓測試 seam 失效。`googleIsConfidentialClient` 目前只是語意文件/人工核對用，實際判斷分支是 `_clientSecret.isEmpty`（邏輯等價但物理上是兩段獨立程式碼）。

`_fetchEmail()`：GET userinfo 端點帶 `Authorization: Bearer`，解析失敗或非 200 都回傳 `null`——此時 `link()` 整體視為失敗（即使 token 換發已成功），避免「拿到 token 但沒 email」的半殘狀態。

### A.5 `OneDriveOAuthClient`——與 Google 版本的異同

**端點與 scope**：授權端點 `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`；token 端點同網域 `/token`；userinfo（Microsoft Graph）`https://graph.microsoft.com/v1.0/me`；scope `Files.Read User.Read offline_access email openid profile`。

**相同之處**：系統瀏覽器 PKCE 流程、`state` CSRF 防護、`link()`/`ensureValidAccessToken()`/`unlink()` 方法簽章、PKCE 輔助方法實作、失敗一律回傳 `null`/`false` 不拋例外的風格。

**差異（MSAL 風格）**：

| 面向 | Google | OneDrive |
|---|---|---|
| confidential/public 分支 | 有（`_clientSecret`/`_tokenRequestBody()`） | **沒有**——Microsoft「行動裝置與桌面應用程式」平台類型固定是公開客戶端、不核發 client secret |
| refresh token 取得方式 | 查詢參數 `access_type=offline` | scope 清單內的 `offline_access`（不可省略） |
| refresh 請求是否帶 scope | 不帶 | **要重複帶** `scope` 欄位 |
| 帳號選擇畫面 | `prompt=select_account`（因 Issue 8 背景問題而加） | 無等價參數（無獨立應用擁有權驗證關卡，摩擦度較低） |
| redirect scheme 格式 | 反向網域 `com.googleusercontent.apps.<ID>:/oauth2redirect` | MSAL 慣例 `msal<ID>://auth` |
| `_fetchEmail()` 欄位退回 | 直接讀 `json['email']` | 先讀 `json['mail']`，為 `null`（常見於未設定備援 Email 的個人帳號）則退回 `json['userPrincipalName']` |

`ensureValidAccessToken()` 邏輯結構與 Google 版本完全一致（60 秒提前續期閾值、token 滾動處理、失敗不主動 unlink），差異只在請求 body 多帶 `scope`、無 client_secret 分支。

### A.6 帳號持久化：`CloudAccountRepository`

**抽象介面**：`CloudAccountTokens`（`accessToken`/`refreshToken`/`email`/`expiresAt`）。`CloudAccountRepository`（`link`/`unlink`/`isLinked`/`loadAccountEmail`/`loadTokens`）——**這個介面只負責「怎麼存」，不知道 OAuth 流程細節**，刻意比照既有 `SyncAccountRepository`／`SyncClient` 的分工模式。

**`SecureStorageCloudAccountRepository` 實作**：底層 `flutter_secure_storage`（Android Keystore／iOS Keychain）。每個 provider 的四個欄位各自存成獨立 key，前綴 `cloud_account_<provider>_`，彼此互不影響。

**讀取失敗安全回退**（`_readSafe()`）：任何讀取拋出例外（部分 OEM 客製 Android Keystore 有瑕疵的裝置會拋 `PlatformException`）一律捕捉並回傳 `null`，視同該欄位不存在，比照既有 `SyncAccountRepository` 的既定安全回退模式。

**`loadTokens()`**：四個欄位任一為 `null` 就整體回傳 `null`；`expiresAt` 字串解析失敗同樣視同憑證不存在。**`isLinked()`**：只檢查 access token 是否存在，語意上比「是否有完整可用憑證」寬鬆——UI 顯示連結狀態用這個，實際發請求前的完整性檢查交給 `loadTokens()`。

### A.7 Android 原生端 redirect 攔截

`app/android/app/src/main/AndroidManifest.xml` 在 `.MainActivity`（`android:exported="true"`）上掛兩個 `BROWSABLE` intent-filter，分別對應 `${googleOAuthScheme}` 與 `${oneDriveOAuthScheme}`（OneDrive 那組額外限定 `host="auth"`）。系統瀏覽器完成授權導向這些 scheme 時，Android 依 intent-filter 比對把控制權交還 `MainActivity`，`flutter_web_auth_2` 的 `authenticate()` 呼叫才能 resolve 拿到完整 redirect URL。

`${...}` 佔位符來自 `app/android/app/build.gradle.kts`：Gradle 建置期讀取 `app/config/cloud_oauth.json`（不存在則退回 `cloud_oauth.example.json`），解析出兩個 client id，**獨立重新實作**與 `cloud_oauth_config.dart` 相同的推導公式算出 scheme，透過 `manifestPlaceholders[...]` 注入 manifest。程式碼明確警告：`project.rootDir`（恆等於 `app/android/`）與 `project.rootDir.parentFile`（正確指向 `app/config/`）不可混淆；且兩處推導公式必須手動保持同步（Gradle 讀不到 Dart 編譯期常數，無法共用程式碼消除）。

### A.8 `app/config/cloud_oauth.example.json`

```json
{
  "GOOGLE_OAUTH_CLIENT_ID": "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com",
  "GOOGLE_OAUTH_CLIENT_SECRET": "",
  "ONEDRIVE_OAUTH_CLIENT_ID": "YOUR_ONEDRIVE_OAUTH_CLIENT_ID"
}
```

真正被 `--dart-define-from-file` 讀取的是 `app/config/cloud_oauth.json`（不進版控，`.gitignore` 明確排除）；`cloud_oauth.example.json` 是提交進版控的樣板，供開發者複製後填入真實憑證。三個 key 名稱與 `cloud_oauth_config.dart` 的 `String.fromEnvironment(...)` 鍵名一一對應。`GOOGLE_OAUTH_CLIENT_SECRET` 樣板值刻意留空——對應「留空代表 Android 公開客戶端」的合法預設狀態；若手上是電腦應用程式類型的用戶端，換成 Google Cloud Console 提供的密鑰即可，不需改任何 `.dart` 檔。**同一份 JSON 同時服務 Dart 編譯期常數與 Gradle 建置腳本兩個消費端**。

### A.9 main.dart 組裝

`SecureStorageCloudAccountRepository()` 建構後傳給 `GoogleDriveOAuthClient(accountRepository: cloudAccountRepository)` 與 `OneDriveOAuthClient(accountRepository: cloudAccountRepository)`——兩個 provider 共用同一個 repository 實例，`clientSecret` 未顯式傳入（沿用建構子預設值），印證「main.dart 完全不需要因 Issue 8 而改動」的設計目標。

關鍵依賴版本（`app/pubspec.yaml`）：`flutter_web_auth_2: ^5.1.0`（系統瀏覽器 OAuth）、`crypto: ^3.0.7`（PKCE SHA-256）、`flutter_secure_storage: ^10.3.1`（token 加密儲存）。

---

## 第三部分：深度報告 B——`Book` / `LibraryRepository` Schema

### B.1 `Book` 模型欄位總覽

| 欄位 | 型別 | 語意重點 |
|---|---|---|
| `id` | `String` | 主鍵。ADR 0020：本機時間戳記＋URI hash 產生，**跨裝置不穩定**，同步比對改用 `contentFingerprint`。 |
| `title`/`author` | `String`/`String?` | 一般詮釋資料。 |
| `format` | `BookFileFormat` | 見 B.4。 |
| `filePath` | `String` | 檔案系統路徑或 `content://`/`file://` URI（ADR 0002：本機匯入不複製檔案，直接引用原始 URI 並取得 persistable permission）。 |
| `source` | `BookSource` | 匯入來源。 |
| `coverPath` | `String?` | 產生後封面 PNG 路徑，`null` = 尚未產生/產生失敗。 |
| `progress` | `double`（0.0–1.0） | EPUB 用 Readium `Locator.locations.totalProgression`，PDF 用 `(pdfPageIndex+1)/總頁數`。 |
| `epubLocator` | `String?` | EPUB 序列化 `Locator`。**與 `pdfPageIndex` 互斥**，但兩者也可能同時為 `null`（從未開啟過）。位置資料歸類為「系統追蹤狀態」放在 `Book`，非 `BookReaderPrefs`。 |
| `pdfPageIndex` | `int?` | PDF 頁索引（0-indexed），與 `epubLocator` 互斥。 |
| `totalCharacterCount` | `int?` | 全書字元數快取，僅 EPUB 有值，`null` = 尚未計算。 |
| `isFixedLayout` | `bool?` | 本書是否為 FXL EPUB。`null` = 尚未判斷或非 EPUB。**與 `reader/writing_mode.dart` 的 `EpubLayoutInfo.isFixedLayout`（開書後才回報的執行期狀態）是兩個完全不同的概念，互不影響**——註解特別強調避免混淆「匯入時快取判斷」vs「開書時執行期狀態」。 |
| `contentFingerprint` | `String?` | 跨裝置同步用書籍身份指紋：EPUB 優先 OPF identifier，缺漏或 PDF/TXT 則整份檔案 SHA-256。**刻意不攜帶本機 `id`**（ADR 0020）。`null` = 尚未補算，補算前不參與跨裝置比對。 |
| `positionUpdatedAt` | `int?` | 閱讀位置最後一次**本機**異動時間，純本機時鐘，只跟自己過去的 `sync_metadata.lastPushCompletedAt` 比較，不跨裝置比較。 |
| `positionSyncedServerUpdatedAt` | `String?` | 快取上次成功同步時 PocketBase 該筆的**伺服器**時間戳，供偵測「其他裝置是否在此之後又推送過」——與本機快取值不同即代表衝突。 |
| `remoteServerId` | `String?` | 所屬遠端書庫伺服器 ID（`remote_servers.id` 外鍵，`ON DELETE SET NULL`）。 |
| `remoteBookId` | `String?` | 遠端書庫（Calibre/OPDS）中的書籍唯一識別碼。 |
| `remoteDownloadUrl` | `String?` | 遠端下載/串流來源 URL。 |
| `isDownloaded` | `bool`（預設 `true`） | 本地檔案是否已就緒；遠端僅有詮釋資料尚未下載時為 `false`。 |
| `cloudFileId` | `String?` | 雲端匯入原始檔案 ID，在 `source` 範圍內唯一，供匯入前重複偵測。 |
| `groupName` | `String`（預設「未分類」） | 所屬分類。 |
| `createTime`/`lastReadTime` | `DateTime` | 建立/最後閱讀時間。 |

**遠端書庫欄位 vs 雲端匯入欄位的關係**：兩組概念上完全獨立——`remoteServerId`/`remoteBookId`/`remoteDownloadUrl`/`isDownloaded` 對應「遠端書庫」（Calibre/OPDS，書籍持續留在遠端伺服器，可重新下載）；`cloudFileId` 對應「雲端匯入來源帳號」（Google Drive/OneDrive，**一次性搬入**本機圖書庫，匯入後即與雲端來源無持續關聯）。

### B.2 `toMap()`/`fromMap()` 的命名混用

自 epic-8/17 之後新增的欄位刻意用 **snake_case**（`content_fingerprint`、`position_updated_at`、`position_synced_server_updated_at`、`remote_server_id`、`remote_book_id`、`remote_download_url`、`is_downloaded`、`cloud_file_id`），而較早期欄位維持 **camelCase**。這是遷移歷史留下的分界線（v1 建表用 camelCase，v11 起新增欄位改用 snake_case 慣例），**刻意接受、非待修 bug**。

### B.3 `copyWith()` 為何只開放 4 個具名參數

只開放 `groupName`（批次分類異動）、`isFixedLayout`（EPUB 版面判斷回填）、`filePath`/`isDownloaded`（epic-30 遠端書庫「移除本機快取」/「重新下載」流程）。設計原則是 **YAGNI**——當時沒有呼叫端需要真的異動其餘欄位。

**但所有未開放為具名參數的欄位仍必須原樣帶入新物件，不能被 `copyWith()` 靜默清空**。這是一個**曾經真實發生過的 bug**：2026-08-04 審查發現 `positionUpdatedAt`/`positionSyncedServerUpdatedAt` 原本沒有帶入 `copyWith()`，會被任何呼叫處靜默清成 `null`——因為 `updateBook()` 是整列覆寫（`_db.update('books', book.toMap(), where: 'id = ?')`），`copyWith()` 若遺漏某欄位就會整批寫回 `null`。測試 `book_test.dart` 有專門的回歸案例覆蓋這類情境。

### B.4 `library_enums.dart`

- `BookFileFormat`：`epub, pdf, txt, azw3, cbz, md`。**獨立於** `reader/book_format.dart` 的 `BookFormat`——後者只服務 `ReaderScreen` 原生渲染分派，圖書庫資料層要表達 FR-01 完整支援格式清單，兩者不是同一個 enum。
- `BookSource`：`local, googleDrive, oneDrive, calibreOpds`。
- `LibrarySortBy`：`lastRead, createTime, author, title`（FR-26）。
- `LibraryViewMode`：`grid, list`（FR-03）。

### B.5 `BookGroup`與「未分類」保護

`BookGroup` 是極簡包裝類，保留值 `static const String uncategorized = '未分類'`。保護邏輯不在模型本身，而在 repository 層強制擋下：
- `renameGroup()`：`oldName == BookGroup.uncategorized` 時拋 `LibraryRepositoryException('系統保留群組「未分類」不可重新命名')`。
- `deleteGroup()`：同樣模式擋刪除；刪除其他分類時，該分類下所有書籍先被 `UPDATE books SET groupName = '未分類'` 再刪除分類列，整段在交易內完成，確保原子性。

### B.6 `books` 表完整 CREATE TABLE（v23 最終狀態）

```sql
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT,
  format TEXT NOT NULL,
  filePath TEXT NOT NULL,
  source TEXT NOT NULL,
  coverPath TEXT,
  progress REAL NOT NULL DEFAULT 0,
  epubLocator TEXT,
  pdfPageIndex INTEGER,
  totalCharacterCount INTEGER,
  is_fixed_layout INTEGER,
  groupName TEXT NOT NULL DEFAULT '未分類',
  createTime INTEGER NOT NULL,
  lastReadTime INTEGER NOT NULL,
  content_fingerprint TEXT,
  position_updated_at INTEGER,
  position_synced_server_updated_at TEXT,
  remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
  remote_book_id TEXT,
  remote_download_url TEXT,
  is_downloaded INTEGER NOT NULL DEFAULT 1,
  cloud_file_id TEXT
)
```

索引：`idx_books_remote_lookup(remote_server_id, remote_book_id)`、`idx_books_content_fingerprint(content_fingerprint)`、`idx_books_cloud_file_id(cloud_file_id)`。

`groups` 表：`CREATE TABLE groups (name TEXT PRIMARY KEY)`，`onCreate` 時立刻播種「未分類」。

### B.7 同檔案內定義的其他表

全部集中在 `sqlite_library_repository.dart`（其他 repository 只是共用同一個 `Database` 連線）：

- `book_reader_prefs`：`book_id` 與 `books` 1:1（`ON DELETE CASCADE`），字型/版面/PDF 增強/雙頁/頁首頁尾/欄位模式/邊距/全螢幕/字距/PDF 換頁動畫等欄位。
- `bookmarks`：`id`（UUID）、`book_id`（`ON DELETE CASCADE`）、EPUB/PDF 雙定位欄位、`updated_at`/`deleted_at`（同步用）。
- `highlights`：同上結構＋`style`、`pdf_rect_json`。
- `notes`：同上結構＋`text`、`highlight_id`（`ON DELETE SET NULL`，劃線被刪時備註退化為純備註）。
- `custom_fonts`：`family_name UNIQUE`，`font_uri` 存 `content://`（ADR 0021：字型檔不落地複本）。
- `sync_metadata`：單列表（`CHECK (id = 1)`），存本機推送時鐘與各集合的伺服器拉取游標時間戳。
- `sync_remote_ids`：`(collection, client_id) -> remote_id` 對照表（PocketBase 系統 `id` 不接受本專案 UUID 格式）。
- `sync_pending_records`：下載時查無對應本機書籍的待處理佇列。
- `layout_preset`：版面設定預設集，`prefs_json` 存過濾後 `BookReaderPrefs` 的 JSON。
- `remote_servers`：Calibre/OPDS 遠端書架站點（密碼在 `flutter_secure_storage`，不在此表）。

### B.8 Migration 摘要（version bump 對照）

| 版本 | 內容 |
|---|---|
| 2 | 建立 `book_reader_prefs` 表 |
| 3 | `book_reader_prefs` 加 6 個 PDF 增強欄位 |
| 4 | `book_reader_prefs` 加 3 個雙頁欄位 |
| 5 | `books` 加 `epubLocator`/`pdfPageIndex`（閱讀位置記憶） |
| 6 | `books` 加 `totalCharacterCount` |
| 7 | `book_reader_prefs` 加 `show_header`/`show_footer` |
| 8 | 建立 `bookmarks` 表 |
| 9–10 | 建立 `highlights`/`notes` 表，補 PDF 定位欄位 |
| 11 | `books` 加 `is_fixed_layout` |
| 12 | `book_reader_prefs` 加 `single_column` |
| 13 | 加 `column_mode`/`column_size`，既有 `single_column` 值清為 `NULL`（等同自動） |
| 14 | 加 4 個邊距欄位（`page_margins` 不受影響，ADR 0014：新欄位供流式 EPUB，舊欄位續供 FXL） |
| 15 | 加 `fullscreen` |
| 16 | 建立 `custom_fonts` 表；`font_family` 由封閉列舉遷移為任意 family name |
| 17 | **epic-8-sync 大遷移**：`books` 加 `content_fingerprint`/`position_updated_at`/`position_synced_server_updated_at`；`bookmarks`/`highlights`/`notes` 主鍵由 `INTEGER AUTOINCREMENT` 改 `TEXT`(UUID)；建 `sync_metadata` 表 |
| 18 | 建立 `sync_remote_ids`/`sync_pending_records` |
| 19 | 加 `letter_spacing` |
| 20 | 加 `pdf_page_turn_animation` |
| 21 | 建立 `layout_preset` 表 |
| 22 | 建立 `remote_servers` 表；`books` 加 4 個遠端欄位，建 `idx_books_remote_lookup` |
| 23（目前最新） | `books` 加 `cloud_file_id`；補建 `idx_books_cloud_file_id` 與 `idx_books_content_fingerprint`（後者是補建，`content_fingerprint` 自 v17 從未建過索引，避免書籍量大時全表掃描） |

**設計慣例**：`if (oldVersion < N) {...}` 巢狀結構只用來包住 `book_reader_prefs` 的**遞增 ALTER TABLE**（因該表初次建立就是最新欄位，若再跑後續 ALTER 會因欄位重複而崩潰）；**新增獨立表**與 `books` 表的欄位遷移放在外層無條件檢查。多個 `_add*Column` 私有方法在 `ALTER TABLE` 前先查詢欄位是否存在，讓刻意省略建表的測試 fixture 不會拋出 `no such table`。

v17 的 UUID 遷移：SQLite `ALTER TABLE` 不支援修改欄位型別，因此用「建新表 → 搬資料（`INTEGER id` → `uuid.v4()`，維護舊 `highlights` id → 新 UUID 對照表以重寫 `notes.highlight_id`）→ 刪舊表 → RENAME」方式重寫三張表，全程需要 `PRAGMA foreign_keys = OFF`（因 sqflite 的 `onUpgrade` 跑在自動交易內，SQLite 不允許交易期間切換此 PRAGMA，故需在交易外的 `onConfigure`/`onOpen` 處理開關）。

### B.9 三種重複匯入偵測方法

```dart
findByRemoteBookId(serverId, remoteBookId)   // WHERE remote_server_id = ? AND remote_book_id = ?
findByContentFingerprint(fingerprint)        // WHERE content_fingerprint = ?
findByCloudFileId(provider, cloudFileId)     // WHERE source = ? AND cloud_file_id = ?
```

三者對應三種「這是不是同一本書」的判斷維度，彼此獨立、互不取代：
- `findByRemoteBookId`：**Calibre/OPDS 遠端書庫**場景，比對「同一伺服器上的同一本遠端書」。
- `findByContentFingerprint`：**跨裝置同步**場景，比對「內容上是否為同一本書」（不看來源），是 ADR 0020 決策核心查詢，也用於雲端匯入下載後的二次指紋比對。
- `findByCloudFileId`：**雲端匯入選檔前置重複偵測**——選檔階段尚未下載、無法算內容指紋，先用雲端原生檔案 ID 擋重複。

### B.10 相關 ADR

專案沒有針對「`Book` 模型設計」或「EPUB CFI vs PDF 頁碼互斥定位欄位」單獨開 ADR——這部分記錄在 `docs/epics/epic-5-toc-pagination/spec.md`。與圖書庫 schema 直接相關的 ADR：

- **ADR 0002**：`filePath` 契約由「只接受檔案系統路徑」擴充為「接受檔案系統路徑或 `content://` URI」。背景是 Android 11+ Scoped Storage 下 SAF 選檔只拿得到 `content://`，且本機匯入決定不複製、直接引用原始檔案；需要 `takePersistableUriPermission()` 讓權限跨 App 重啟仍有效。
- **ADR 0020**（**理解 `contentFingerprint`/`positionUpdatedAt`/`positionSyncedServerUpdatedAt` 與 v17 UUID 遷移最關鍵的 ADR**）：
  1. 跨裝置書籍身份比對改用「內容指紋」而非本機 `Book.id`（`id` 是本機時間戳+URI hash，跨裝置不穩）。
  2. 同步採批次 checkpoint（背景化/切書/閱讀中每 5 分鐘閒置計時器），不做逐筆即時同步。
  3. 清單型資料（劃線/備註/書籤）以 id 聯集合併，主鍵改 UUID，本機 id 與同步識別碼合一；合併規則用**伺服器蓋章時間戳**（PocketBase `updated`/`created`），不用本機 `updated_at`（涵蓋 E-Ink 裝置時鐘可能不準的情境）——這正是 `positionUpdatedAt`（本機時鐘）vs `positionSyncedServerUpdatedAt`（伺服器蓋章）兩欄位分工的設計源頭。
  4. 同步失敗採靜默重試，不做佇列/退避演算法。

### B.11 測試涵蓋重點

- `app/test/library/models/book_test.dart`：`toMap`/`fromMap` 往返、`copyWith` 局部覆寫、`operator==`/`hashCode`，以及每一波新欄位的「可正確往返」＋「未設定為 null」＋「`copyWith` 不會清空」三重覆蓋（最後一類正是 B.3 節靜默清空 bug 的回歸測試）。
- `app/test/library/sqlite_library_repository_test.dart`（3700+ 行）：逐一覆蓋每個 version bump，並明確測試「跳級升級」情境（例如 v1 裝置一次跳到 v17，主鍵正確轉為 UUID 且 `notes.highlight_id` 正確重寫）；另有三種重複偵測方法、`listUndownloadedBooksForRemoteServer`、`listReflowableEpubBooks`（排除 FXL）、群組管理（含刪除/改名「未分類」拋例外）、`remote_servers` 刪除後 `ON DELETE SET NULL` 連動等專門測試群組。
