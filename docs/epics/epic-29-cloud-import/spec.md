# Epic 29 — 雲端服務匯入書籍：Spec

> Architecting 階段產出，本檔案為本 Epic 核心介面/型別的唯一事實來源。承接 `design.md`（Discovery，已定案的產品/範圍決策不在此重複討論）與 `reviews/review-design.md`（已核實、待落實的技術項目）。

## Problem Statement

使用者的電子書經常不是存在裝置本機，而是存在 Google Drive 或 OneDrive 這類雲端硬碟裡（下載別人分享的書、跨裝置備份的書、掃描/購買後習慣先存雲端的書）。目前 elinkBook 只能匯入手機本機檔案，使用者必須先透過 Google Drive／OneDrive 官方 App 把檔案下載到手機儲存空間，再回到 elinkBook 用本機檔案選擇器匯入——多一道手動下載的步驟，體驗繁瑣，且部分 E-Ink 裝置沒有 Google Play Services，連「先用官方 App 下載」這條路都不一定順暢。

## Solution

在 elinkBook 內建 Google Drive 與 OneDrive 的帳號連結與檔案瀏覽能力，讓使用者直接在 App 內登入雲端帳號、瀏覽資料夾、勾選要匯入的電子書檔案，一次完成「登入 → 瀏覽 → 選檔 → 下載 → 匯入圖書庫」，不需要離開 App、不需要依賴雲端服務官方 App 是否安裝。Google Drive 的登入/驗證/下載採用不依賴 Google Play Services 的整合方式，確保在部分 E-Ink 裝置上也能正常運作。

## User Stories

1. 作為擁有 Google Drive 雲端書籍的使用者，我希望能直接把書匯入 elinkBook，這樣就不用先透過另一個 App 下載到手機再匯入。
2. 作為擁有 OneDrive 雲端書籍的使用者，我希望有對等的匯入能力。
3. 作為使用無 Google Play Services 的 E-Ink 裝置的使用者，我希望 Google Drive 匯入功能依然能正常運作，這樣才不會因為裝置限制被排除在這個功能之外。
4. 作為使用者，我希望連結一次雲端帳號後就能持續使用，這樣不用每次匯入都重新登入。
5. 作為使用者，我希望在「設定」頁就能看到目前連結了哪些雲端帳號，這樣能一眼確認連線狀態。
6. 作為使用者，我希望能在「設定」頁隨時解除某個雲端帳號的連結，這樣我不想再授權時能主動收回。
7. 作為尚未連結任何雲端帳號的使用者，我希望在匯入流程當下就能直接觸發連結，這樣不用先跳去設定頁再回來。
8. 作為使用者，我希望存取權杖過期時 App 能自動靜默續期，這樣不會被不必要的重新登入打斷。
9. 作為授權被撤銷（例如在 Google 帳號設定頁自行撤銷）的使用者，我希望清楚被告知需要重新登入，這樣才知道為什麼雲端匯入突然失效。
10. 作為瀏覽 Google Drive 的使用者，我希望畫面只顯示支援格式的電子書檔案（EPUB/PDF/TXT/AZW3/CBZ/MD），這樣不會被相片、文件等不相關檔案干擾。
11. 作為使用者，我希望雲端資料夾的瀏覽方式跟系統檔案總管一樣逐層點進去，這樣操作起來很直覺。
12. 作為瀏覽大量檔案的使用者，我希望能看到檔案縮圖，這樣能從一堆檔名很像的檔案裡認出我要的那本（尤其是 PDF/CBZ 這類封面重要的格式）。
13. 作為使用者，我希望能只選一個檔案匯入，精準拿到我要的那本書。
14. 作為使用者，我希望能一次勾選多個檔案批次匯入，這樣不用一本一本重複整個流程。
15. 作為批次匯入多個檔案的使用者，我希望能看到每個檔案各自的狀態（等待中/下載中/完成/失敗），這樣能清楚掌握進度。
16. 作為下載中途失敗（例如網路中斷）的使用者，我希望看到明確的錯誤訊息並能針對該檔案手動重試，這樣不用整批重來。
17. 作為使用行動數據的使用者，我希望在下載大檔案前收到提示，這樣不會不小心超出流量方案。
18. 作為使用者，我希望匯入時能選擇（或跳過）分類，這樣書架不會因為常態性雲端匯入而變得雜亂。
19. 作為使用者，我希望選到之前已經匯入過的雲端檔案時能收到重複提示，這樣不會不小心把同一本書匯入兩次。
20. 作為使用者，我希望這個重複提示能盡早出現（下載前，而不是下載完才知道），這樣不會浪費流量與時間下載一份其實已經有的檔案。
21. 作為解除雲端帳號連結的使用者，我希望先前已匯入的書完全不受影響，這樣解除連結這個動作對我來說是零風險的。
22. 作為使用者，我希望登入 Google/OneDrive 時走的是我平常信任的瀏覽器登入畫面，而不是 App 裡一個看起來陌生的內嵌登入畫面，這樣輸入帳密時比較安心。
23. 作為使用者，我希望雲端匯入下來的書在匯入後跟本機匯入的書沒有任何差異（封面、格式偵測、可讀性），這樣使用體驗是一致的。
24. 作為開發者，我希望 Google Drive 與 OneDrive 共用同一套瀏覽/下載介面，這樣之後如果要加第三個雲端服務不需要重新設計整條 UI。
25. 作為開發者，我希望雲端瀏覽與下載邏輯不需要真的打網路/真的登入雲端帳號就能測試，這樣 CI 上的測試能維持快速且結果穩定。

## Implementation Decisions

### 帳號模組：`CloudAccountRepository`

- 單一 repository 處理兩個 provider（不拆成兩個類別），所有方法都以 `CloudProvider`（新 enum：`googleDrive`／`oneDrive`）為參數區分，例如 `link(provider, tokens)`／`unlink(provider)`／`isLinked(provider)`／`loadAccountEmail(provider)`。
- Refresh token 與帳號 email（顯示用）存 `FlutterSecureStorage`（既有依賴，`epic-8-sync` 已引入），存放 key 依 provider 區分前綴。不新增 SQLite 資料表——資料量小（每 provider 至多一組帳號）且非關聯式，比照 `SyncAccountRepository` 完全不用資料庫的既有先例。
- 讀取失敗（Keystore 損毀等已知環境因素，`SyncAccountRepository` 已有先例）一律安全退回「視同未連結」，不拋例外、不卡住畫面。
- Token 過期/撤銷處理：`CloudAccountRepository` 內部持有一個更底層的 OAuth 用戶端（見下方「OAuth 登入機制」），對外只曝露「靜默續期，失敗則回傳『需要重新登入』」這個結果給呼叫端，UI 層不需要知道底層是怎麼續期的。

### OAuth 登入機制

- 兩個 provider 皆走系統瀏覽器（Custom Tabs／`ASWebAuthenticationSession` 等價機制）導向的 OAuth Authorization Code Flow **搭配 PKCE**（RFC 7636）與 `state` 參數防範 CSRF/攔截攻擊——這是 Google／Microsoft 對公開客戶端（無後端伺服器的行動 App）的政策要求，不是可自由選擇的設計空間。**不使用內嵌 WebView 登入**（Google 政策明確禁止，見 `design.md`「依賴事實」）。
- 需新增一個處理「開系統瀏覽器 → 攔截 redirect → 換 token」流程的依賴套件（例如 `flutter_web_auth_2` 這類套件，實際套件與版本由實作者於實作階段確認相容性，見下方「風險」）；`AndroidManifest.xml` 需新增對應的 redirect URI intent-filter（目前完全空白，需要新增，非修改既有設定）。
- **Google Drive OAuth scope**：採用 `drive.readonly`（唯讀存取使用者所有檔案），**不**採用 `drive.file`（僅限本 App 建立/開啟過的檔案）——因為 Discovery 階段已定案「使用者可瀏覽任意雲端資料夾挑書」，`drive.file` 無法達成這個 UX。**已知外部限制**：`drive.readonly` 屬於 Google 的受限權限（Restricted Scope），未完成 Google 的應用程式驗證/CASA 安全評估流程前，使用者登入時會看到「未驗證應用程式」警告畫面——這是外部平台的既定流程，不是本 Epic 工程範圍內能解決的問題，開發/測試期間可先用 Google Cloud Console 的測試人員白名單機制繞過（見「Further Notes」）。
- **OneDrive OAuth scope**：採用 Microsoft Graph 的 `Files.Read`（唯讀存取使用者可存取的所有檔案），對應同樣「瀏覽任意資料夾」的需求；Microsoft 側沒有與 Google `drive.readonly` 對等的強制安全評估關卡，摩擦度較低。

### 雲端瀏覽與下載：`CloudStorageClient`

單一共用介面，兩個實作 `GoogleDriveStorageClient`／`OneDriveStorageClient`，是整個瀏覽＋下載 UX 唯一依賴的邊界（seam 已與使用者確認）：

```dart
abstract class CloudStorageClient {
  Future<List<CloudFileEntry>> listFolder({String? folderId});
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
  });
}

class CloudFileEntry {
  final String id;
  final String name;
  final bool isFolder;
  final BookFormat? format;   // null 代表不支援的格式，畫面上不會顯示
  final String? thumbnailUrl;
  final int? sizeBytes;
}
```
（此為決策草圖，非最終原始碼；上方僅為說明本 Epic 的核心契約形狀。）

- 格式過濾（僅顯示 EPUB/PDF/TXT/AZW3/CBZ/MD）：能用伺服器端 MIME type 過濾的格式（Google Drive API 的 `q` 查詢參數支援 EPUB/PDF/TXT 的標準 MIME type）交給伺服器端做；AZW3/CBZ 這類沒有普遍認可標準 MIME type 的格式，各實作內部退回用副檔名做用戶端過濾。兩家 API 的分頁機制（Google Drive `pageSize`+`pageToken`、Microsoft Graph `@odata.nextLink`）皆需要支援，`listFolder()` 內部處理分頁串接，對呼叫端呈現的是「這個資料夾完整的檔案清單」（不把分頁細節外露到這個介面之上）。
- 縮圖（`thumbnailUrl`）需要帶授權標頭或本身是具時效性的簽章 URL，畫面上顯示縮圖時需搭配非同步載入佔位符與快取，避免 E-Ink 螢幕因逐張圖片載入而頻繁局部刷新。
- `downloadFile()` 下載到暫存路徑而非直接落地到最終匯入位置，確認匯入（含重複匯入偵測，見下方）成功後才移動到最終位置；使用者取消下載或整個匯入流程時，暫存檔案需要被清除，不留孤兒檔案。

### 既有匯入管線擴充：`BookImportService`

延續 `reviews/review-design.md` Critical #1 的結論，擴充既有介面而非新增平行匯入路徑：

```dart
Future<ImportResult> importFiles(
  List<String> paths, {
  List<String?>? displayNames,
  String? folderName,
  BookSource source = BookSource.local,
  Map<String, String>? cloudFileIds, // path -> 雲端檔案 ID
});
```

- `source`／`cloudFileIds` 皆為可選參數且有預設值，**既有呼叫端（本機匯入）完全不需要修改**，零回歸風險。
- 雲端瀏覽器下載完成、使用者確認匯入後，把暫存路徑清單連同 `source: BookSource.googleDrive/oneDrive` 與對應的 `cloudFileIds` map 一併呼叫 `importFiles()`，之後與本機匯入走完全相同的封面產生/格式偵測/資料庫寫入流程。

### 資料模型與 Schema

- `books` 表新增一欄 `cloud_file_id TEXT`（可為 `NULL`），schema version 由現行 21 升至 22，比照既有 `content_fingerprint`／`position_updated_at` 等既有欄位的 `ALTER TABLE` migration 慣例（既有裝置升級後預設 `NULL`，不影響既有資料）。
- 不需要額外的 `cloud_provider` 欄位——`books.source`（既有 `BookSource` enum 欄位）已經區分 `googleDrive`／`oneDrive`，`cloud_file_id` 只需在該欄位範圍內唯一即可，不需要重複記錄 provider。
- `LibraryRepository` 新增兩個查詢方法（介面＋ `SqliteLibraryRepository` 實作＋ `FakeLibraryRepository` 測試替身，比照既有三件套模式）：
  - `findByCloudFileId(BookSource provider, String cloudFileId) → Book?`
  - `findByContentFingerprint(String fingerprint) → Book?`（目前不存在，`sync` 模組另有自己的比對邏輯；本 Epic 新增這個通用查詢方法供匯入流程使用，不影響/不重用 sync 模組現有邏輯）

### 重複匯入偵測（雙層檢查，回應 `review-design.md` Important #3）

1. **選檔前置檢查**：使用者在雲端瀏覽器勾選檔案的當下，若該 `(provider, cloudFileId)` 已存在於 `books.cloud_file_id`，立即提示「這本書之前匯入過了，仍要建立新的一份嗎？」——不需要下載就能判斷，避免浪費流量/時間。
2. **下載後指紋比對**：選檔前置檢查沒有命中（例如這是第一次從雲端匯入、但本機早已透過別的管道匯入過同一本書）的檔案，正常下載到暫存位置後，比照既有 `book_import_service_impl.dart` 匯入流程計算 `content_fingerprint`，與 `findByContentFingerprint()` 比對；命中則彈出同樣的提示，使用者選擇不建立新副本時立即刪除暫存檔案。
3. 兩層檢查皆使用**精確比對**（cloud file ID 完全相同／指紋完全相同），不做書名/作者模糊比對——`design.md`「重複匯入偵測」已定案原因（模糊比對誤判成本高，指紋對 PDF/TXT/CBZ 跨來源比對本就有已知覆蓋率落差，見 `CONTEXT.md`「書籍內容指紋」）。

### UI 落地位置

- 「匯入」選單新增「從 Google Drive 匯入」「從 OneDrive 匯入」兩個獨立項目。
- 「設定」頁新增「已連結的雲端匯入帳戶」區塊，比照現有「已連結雲端帳戶（同步用）」的既有 UI 慣例（`SyncSettingsScreen`），但資料來源是 `CloudAccountRepository` 而非 `SyncAccountRepository`——兩者是完全獨立的帳號體系（見 `CONTEXT.md`「雲端匯入來源帳號」／「elinkBook 同步帳號」），UI 慣例可以借鏡但不共用元件狀態。

## Testing Decisions

好的測試只驗證外部可觀察行為（畫面上看得到的狀態、呼叫端能觀察到的回傳值/副作用），不測內部實作細節（例如不斷言 `CloudStorageClient` 內部呼叫了哪個 HTTP method）。

- **`CloudAccountRepository`**：不需要裝置/網路的 Dart 單元測試，比照 `SyncAccountRepository` 既有測試模式（讀取失敗安全退回、`isLinked()`/`link()`/`unlink()` 狀態轉換）。
- **`CloudStorageClient`**：新增 `FakeCloudStorageClient`（`app/test/support/`，比照既有 `FakeLibraryRepository` 等命名慣例），回傳預先寫死的資料夾清單／模擬下載成功或失敗。雲端匯入瀏覽畫面（資料夾導覽、格式過濾後的清單、縮圖佔位符、多選狀態、循序下載＋逐項狀態、失敗重試按鈕、行動數據確認對話框）皆用這個 Fake 驅動 widget test，比照 `ReaderScreen` 用 `FakeReaderPrefsManager`/`FakeHighlightsRepository` 等一系列 Fake 驅動測試的既有模式。`GoogleDriveStorageClient`／`OneDriveStorageClient` 兩個真實實作（實際 HTTP 呼叫、OAuth token 帶入 request、分頁串接邏輯）**不做自動化測試**，理由比照這個專案對「原生 WebView 渲染」「pdfrx 原生繪圖」等既有慣例——留待真機或人工用真實帳號驗證。
- **`BookImportService.importFiles()` 擴充**：延伸既有 `BookImportServiceImpl` 測試套件，新增涵蓋 `source`/`cloudFileIds` 參數的案例，確認 `Book.source`／`cloudFileId` 正確落地資料庫且既有本機匯入案例（未傳入新參數）行為不變（零回歸）。
- **重複匯入偵測**：`LibraryRepository` 新增的兩個查詢方法各自的單元測試（`FakeLibraryRepository`／`SqliteLibraryRepository` 兩層皆須覆蓋，比照既有 repository 測試慣例）；雲端瀏覽畫面對「偵測到重複」情境的 UX（彈窗、取消時刪暫存檔）透過 `FakeCloudStorageClient` ＋ 預先塞入命中的 `FakeLibraryRepository` 資料驅動 widget test。
- **設定頁「已連結的雲端匯入帳戶」區塊**：widget test 比照 `SyncSettingsScreen` 既有測試模式，用 `FakeCloudAccountRepository` 驅動已連結/未連結兩種狀態的畫面呈現與解除連結互動。

## Out of Scope

- Dropbox（`design.md` 已定案排除，PRD 未承諾）。
- 整批資料夾遞迴匯入（本波僅單/多檔勾選）。
- 雲端檔案內搜尋（僅逐層資料夾瀏覽）。
- 同一 provider 多組帳號並存與切換。
- PDF/TXT/CBZ 跨來源（雲端 vs. 本機）的模糊比對重複偵測——僅精確比對（cloud file ID／content fingerprint 完全相同）。
- 「重新整理／同步最新版本」——已保留的 `cloud_file_id` 目前純粹是歷史紀錄，本 Epic 不利用它重新抓取雲端最新版本覆蓋本機檔案。
- Google 應用程式驗證/CASA 安全評估流程本身（外部流程，非工程範圍，見 Further Notes）。

## Further Notes

- **新增依賴風險**：本 Epic 至少需要新增一個處理系統瀏覽器 OAuth redirect 的套件（例如 `flutter_web_auth_2`），以及一個偵測目前是否為行動數據連線的套件（例如 `connectivity_plus`）——目前皆未列在 `app/pubspec.yaml`。`pubspec.yaml` 現有版本鎖定已有 `win32`/`package_info_plus` 之間的相容性歷史糾葛（見檔案內註解），新增依賴時需要額外檢查是否引發類似的版本衝突鏈。
- **Google 應用程式驗證是外部時間風險**：`drive.readonly` 屬受限權限，正式上線前需要通過 Google 的 OAuth 應用程式驗證（可能包含安全評估問卷、隱私權政策頁面、示範影片等要求），這個流程的時程不受本專案工程進度控制，開發/內測階段可先用 Google Cloud Console 的「測試使用者」白名單機制（無需通過驗證即可讓白名單內帳號正常登入，僅會顯示「未驗證應用程式」的過場警告）繼续推進开发，但正式對外發布前必須完成驗證。
- 行動數據下載警示的具體檔案大小閾值（`design.md` Minor 待定項目）：建議單檔 > 20MB 觸發警示，實作階段可依真機測試結果微調。
- 下載中途使用者取消的暫存檔清理、縮圖的授權標頭/快取細節，皆已在上方「Implementation Decisions」納入，實作時對照即可，不再重複列出待辦。
