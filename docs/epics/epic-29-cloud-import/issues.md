# Epic 29 — 雲端服務匯入書籍：工單清單 (Issues)

依 `spec.md`（Architecting 產出，已通過 `reviews/review-spec.md` 審查修訂）以 `/to-issues` 拆解為 7 個垂直切片（tracer bullet），每個切片皆貫穿 schema/service/UI/測試整條路徑，可獨立驗收。2026-08-17 與使用者確認切片顆粒度（Issue 3/4 合併單/多檔匯入為單一切片；Issue 5/6 重複偵測與行動數據警示維持獨立切片）後定案發布。相依順序：Issue 0／1 可平行開始 → Issue 2 依賴 1 → Issue 3 依賴 0＋1 → Issue 4 依賴 2＋3 → Issue 5 依賴 0＋3 → Issue 6 依賴 3。

---

## Issue 0：擴充既有匯入/查詢管線（Prefactor）

**Status:** ✅ 已完成（PR #164，分支 `epic-29-cloud-import`，4 個 commit，2026-08-19）

**完成摘要：** 比照 `epic-30-calibre-remote-library` Issue 0 已驗證過的擴充既有介面手法實作。`Book` 模型新增 `cloudFileId`（`String?`）欄位，語意上與 `remoteBookId`（`epic-30`「遠端書庫」）完全獨立，對應 `CONTEXT.md`「雲端匯入來源帳號」；`toMap()`/`fromMap()`/`copyWith()`/`==`/`hashCode` 皆完整納入，`FakeLibraryRepository._withGroupName` 同步補上防禦（避免群組更名時欄位被靜默清空）。SQLite schema migration 由 version 22 升至 23（**非**原訂的 21→22——`epic-30` Issue 0 已先落地佔用了 22，本 Issue 為第二個套用同一擴充模式的 Epic），`books` 表新增 `cloud_file_id` 欄位＋ `idx_books_cloud_file_id` 索引，並藉此次 migration 一併補上 `content_fingerprint` 自 `epic-8-sync` Issue 3 引入以來從未建過的 `idx_books_content_fingerprint` 索引。`LibraryRepository` 新增 `findByCloudFileId(BookSource provider, String cloudFileId)`（`SqliteLibraryRepository`／`FakeLibraryRepository` 三件套完整實作，以 `(source, cloud_file_id)` 複合鍵查詢）；`findByContentFingerprint()` 因 `epic-30` Issue 0 已建置完成，本次不重複宣告/實作，直接復用。`BookImportService.importFiles()` 擴充可選參數 `cloudFileIds`（`Map<String, String>`，path 對應雲端檔案 ID），貫穿 `_importSingleFile()` 落地至 `Book.cloudFileId`，既有本機／OPDS 遠端書架呼叫端零改動、零回歸；測試替身 `FakeBookImportService` 同步擴充 `ImportCallRecord.cloudFileIds` 供後續 Issue 3 的 widget test 斷言使用。計畫審查（`reviews/review-plan-issue-0.md`）與程式碼審查（`reviews/review-issue-0.md`）皆 **APPROVED**，0 Critical／0 Important（計畫審查另有 2 條不影響通過的 Minor 建議，留供後續 Issue 3 整合測試參考，未強制修改本 Issue）。全專案 `flutter analyze` 乾淨、`flutter test` 1559 項全數通過、零回歸。

**依賴：** 無，可立即開始。

**背景：** 本身不含任何使用者可見的雲端功能，是後續全部雲端匯入切片共用的資料層基礎設施，先做可以讓後面的切片實作更簡單（`spec.md`「資料模型與 Schema」「既有匯入管線擴充」已定案介面）。

**What to build：**
- SQLite schema migration（現行 version 21 → 22）：`books` 表新增 `cloud_file_id TEXT`（可為 `NULL`），並為 `cloud_file_id` 與既有 `content_fingerprint` 兩欄各建一個索引，比照既有欄位的 `ALTER TABLE` migration 慣例。
- `BookImportService.importFiles()` 簽章擴充兩個可選參數：`source`（`BookSource`，預設 `BookSource.local`）與 `cloudFileIds`（`Map<String, String>`，path 對應雲端檔案 ID，可為 `null`）。既有呼叫端不需要任何修改。
- `LibraryRepository` 新增兩個查詢方法：`findByCloudFileId(BookSource provider, String cloudFileId) → Book?`、`findByContentFingerprint(String fingerprint) → Book?`，各自在 `SqliteLibraryRepository` 與 `FakeLibraryRepository` 落地（比照既有介面/實作/Fake 三件套模式）。

**單元測試要求：**
- Migration 測試：舊版資料庫升級後 `cloud_file_id` 預設為 `NULL`，既有資料不受影響；兩個索引確實建立。
- `importFiles()`：傳入 `source`/`cloudFileIds` 時對應 `Book` 記錄正確落地；未傳入時（既有本機匯入情境）行為與現行完全一致，既有測試套件維持全綠、零回歸。
- `findByCloudFileId()`/`findByContentFingerprint()`：命中/未命中兩種情境，`SqliteLibraryRepository` 與 `FakeLibraryRepository` 兩層皆須覆蓋。

**驗收標準：** `flutter analyze` 乾淨；`flutter test` 全數通過、零回歸；新查詢方法與擴充參數皆有對應測試覆蓋。

**Blocked by：** 無。

---

## Issue 1：Google Drive 帳號連結／解除連結

**Status:** ✅ 已完成（PR #165，分支 `epic-29-cloud-import`，5 個 commit，2026-08-19）

**完成摘要：** 新增 `app/lib/cloud_import/` 模組，比照既有 `app/lib/sync/`（`SyncAccountRepository`／`SyncClient` 職責分工）與 `app/lib/remote/`（抽象介面／實作／Fake 三件套）兩個既有模式的組合。`CloudAccountRepository`（抽象介面，純儲存，以 `CloudProvider` enum 區分 provider，供 Issue 2 OneDrive 沿用）／`SecureStorageCloudAccountRepository`（`FlutterSecureStorage` 實作，四個欄位各自獨立 key、讀取失敗經 `_readSafe` 安全退回未連結）／`FakeCloudAccountRepository`（測試替身）三件套完整落地。`GoogleDriveOAuthClient` 獨立於 repository 之外，封裝系統瀏覽器導向的 OAuth Authorization Code Flow ＋ PKCE（RFC 7636，`S256` code challenge）＋ `state` 防 CSRF、`drive.readonly` scope、`ensureValidAccessToken()` 於到期前 60 秒靜默續期（失敗回傳 `null`、不主動觸發 `unlink`，保留使用者手動決定空間）；`google_oauth_config.dart` 明確標註 Google Cloud Console 用戶端 ID 為必要外部設定值；`AndroidManifest.xml` 新增對應 redirect URI intent-filter。設定頁新增子畫面 `CloudAccountSettingsScreen`（比照 `SyncSettingsScreen` 載入中/已連結/未連結三態結構），透過 `SettingsScreen`→`LibraryScreen`→`ElinkBookApp`→`main.dart` 既定的可選（nullable）參數逐層貫穿注入（含 `LibraryScreen` 分類篩選畫面的自我遞迴導航點），既有呼叫端零改動。計畫審查（`reviews/review-plan-issue-1.md`）**APPROVED**，0 Blocking/Critical/Important。程式碼審查（`reviews/review-issue-1.md`）初次結論 **CHANGES REQUESTED**：1 項 Important（`CloudAccountSettingsScreen._link()` 成功後未重設 `_linking`，導致解除連結後「連結」按鈕永久卡在轉圈停用狀態）與 4 項 Minor（`jsonDecode` 未防護非預期 200 回應、token 續期未相容 RFC 6749 `refresh_token` 滾動、`loadTokens()` 用 `int.parse` 而非 `int.tryParse`、計畫核取方塊未同步）皆已修訂——Important 項修法與審查原始建議略有出入（技術核實後採「併入 `_load()` 的 `setState` 統一收斂狀態」而非審查建議的「在 `_link()` 內 setState 外裸賦值」，理由與修正記錄見程式碼內註解），該項未補自動化回歸測試（`GoogleDriveOAuthClient.link()` 需要真實瀏覽器，widget test 環境下無法在不引入新抽象層的情況下驅動到成功路徑，超出本次修 bug 範圍，已於溝通中說明）。全專案 `flutter analyze` 乾淨、`flutter test` 1572 項全數通過、零回歸。Google OAuth 實際登入流程（真實瀏覽器導向＋換 token）留待真機/人工用真實 Google 帳號驗證，含 Google Cloud Console 用戶端 ID 設定。

**依賴：** 無，可與 Issue 0 平行進行。

**背景：** `spec.md`「帳號模組」「OAuth 登入機制」已定案介面與流程；本 Issue 只需要讓 `CloudProvider.googleDrive` 這個 case 實際可用，`oneDrive` case 的資料結構需預留但邏輯留給 Issue 2。

**What to build：**
- 新增 `CloudAccountRepository`（單一 repository，以 `CloudProvider` enum 區分 provider）：refresh token 與帳號 email 存 `FlutterSecureStorage`，讀取失敗一律安全退回「視同未連結」（比照既有 `SyncAccountRepository` 的既定模式，不拋例外、不卡畫面）。
- Google OAuth 登入流程：系統瀏覽器導向的 Authorization Code Flow ＋ PKCE ＋ `state` 參數（不使用內嵌 WebView），取得 token 後交給 `CloudAccountRepository.link()` 儲存；token 過期時先靜默續期，失敗才要求重新登入。
- `AndroidManifest.xml` 新增 Google 專用 redirect URI intent-filter（反向客戶端 ID 格式）。
- 設定頁新增「已連結的雲端匯入帳戶」區塊，顯示 Google Drive 連結狀態（未連結／已連結＋帳號 email），提供連結／解除連結操作，比照現有「已連結雲端帳戶（同步用）」的 UI 慣例（但資料來源是 `CloudAccountRepository`，與 `SyncAccountRepository` 完全獨立，不共用元件狀態）。

**單元測試要求：**
- `CloudAccountRepository`：`link`/`unlink`/`isLinked` 狀態轉換；secure storage 讀取失敗時安全退回未連結。
- 設定頁區塊：`FakeCloudAccountRepository` 驅動已連結/未連結兩種畫面呈現、解除連結互動的 widget test。
- Google OAuth 實際登入流程（真實瀏覽器導向＋換 token）不做自動化測試，留待真機/人工用真實 Google 帳號驗證。

**驗收標準：** 使用者可在設定頁用真實 Google 帳號完成連結、看到已連結狀態、解除連結；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** 無。

---

## Issue 2：OneDrive 帳號連結／解除連結

**Status:** ✅ 已完成（PR #166，分支 `feat/epic-29-issue-2-onedrive-link`，3 個 commit，2026-08-19）

**完成摘要：** 沿用 Issue 1 的 `CloudAccountRepository`／`CloudAccountSettingsScreen`，結構完全比照已審查通過的 `GoogleDriveOAuthClient`。新增 `OneDriveOAuthClient`：Microsoft identity platform v2.0 端點（`login.microsoftonline.com/common`），`Files.Read offline_access email openid profile` scope（`offline_access` 是 Microsoft 換發 refresh token 的必要條件，與 Google 的 `access_type=offline` 機制不同）；PKCE（RFC 7636）＋ `state` 防 CSRF；`ensureValidAccessToken()` 支援 RFC 6749 `refresh_token` 滾動（採納 Issue 1 審查教訓，本次首版即內建，非事後補修）；帳號 email 以 Microsoft Graph `/v1.0/me` 端點的 `mail` 欄位為主、`userPrincipalName` 為備援（個人帳號 `mail` 可能為 `null`）；所有 HTTP 回應的 `jsonDecode` 皆納入 try-catch 防護。`AndroidManifest.xml` 新增 MSAL 自訂 scheme（`msal<CLIENT_ID>://auth`）redirect URI intent-filter，與 Google 反向客戶端 ID 格式並存、互不干擾。`CloudAccountSettingsScreen` 擴充 OneDrive 區塊：因兩段 UI 完全同構，把原本 Google Drive 專屬的 `_buildGoogleDriveTile()` 泛化為共用 `_buildProviderTile()`（`keyPrefix` 參數化），既有 `cloud_account_settings_google_drive_*` key 字串維持不變，Issue 1 既有 widget test 零回歸；兩個 provider 的 `_xxxLinked`/`_xxxLinking`/`_xxxEmail` 狀態各自獨立維護，互不干擾。刻意**不**把 `GoogleDriveOAuthClient`／`OneDriveOAuthClient` 抽成共用抽象介面（YAGNI，避免動到 Issue 1 已審查合併的既有程式碼）。`oneDriveOAuthClient` 貫穿注入至 `SettingsScreen`→`LibraryScreen`（含分類篩選畫面自我遞迴導航點）→`ElinkBookApp`→`main.dart`。計畫審查（`reviews/review-plan-issue-2.md`）與程式碼審查（`reviews/review-issue-2.md`）皆 **APPROVED**，0 Critical／0 Important／0 Minor。全專案 `flutter analyze` 乾淨、`flutter test` 1580 項全數通過、零回歸。OneDrive OAuth 實際登入流程留待真機/人工用真實 Microsoft 帳號驗證，含 Azure 應用程式註冊用戶端 ID 設定。

**依賴：** Issue 1（沿用同一個 `CloudAccountRepository`／設定頁 UI）。

**背景：** 設計上刻意讓 OneDrive 的帳號連結沿用 Issue 1 建好的介面與 UI，只補 provider 實作，工作量明顯小於 Issue 1。

**What to build：**
- 新增 OneDrive（Microsoft Graph）OAuth 登入流程實作（scope：`Files.Read`），完成 `CloudProvider.oneDrive` 這個 case 的實際串接，沿用 Issue 1 的 `CloudAccountRepository`。
- `AndroidManifest.xml` 新增 OneDrive 專用 redirect URI intent-filter（與 Google 反向客戶端 ID 格式不同，走自訂 scheme）。
- 設定頁「已連結的雲端匯入帳戶」區塊擴充顯示 OneDrive 連結狀態。

**單元測試要求：**
- 設定頁區塊擴充後涵蓋 OneDrive 已連結/未連結狀態的 widget test。
- OneDrive OAuth 實際登入流程同樣不做自動化測試，比照 Issue 1。

**驗收標準：** 使用者可用真實 Microsoft 帳號完成 OneDrive 連結/解除連結；Google Drive 既有功能不受影響（零回歸）。

**Blocked by：** Issue 1。

---

## Issue 3：Google Drive 瀏覽＋匯入（單/多檔＋分類選擇）

**Status:** ✅ 已完成（PR #168，分支 `epic-29/issue-3-cloud-import`，6 個 commit，2026-08-20）

**完成摘要：** 第一個讓使用者實際「從雲端匯入一本書」的完整可展示切片。新增 `CloudStorageClient` 抽象介面（`listFolder`/`downloadFile`/`fetchThumbnail`）＋ `CloudFileEntry`/`CloudFolderListing`/`detectCloudFileFormat()`，是整個瀏覽＋下載 UX 唯一依賴的邊界，比照 `epic-30-calibre-remote-library` 的 `OpdsClient`／`RemoteCatalogScreen` 既有設計原則——Issue 4（OneDrive）可直接沿用同一套 UI，不需重新設計。`GoogleDriveStorageClient`：Drive API v3 真實實作，伺服器端 MIME type 粗篩（EPUB/PDF/TXT 標準 MIME type ＋ AZW3/CBZ/MD `name contains` 粗篩）＋用戶端 `detectCloudFileFormat()` 精確過濾（正確以 `.endsWith()` 排除 `notes.mdx` 這類子字串誤判）、分頁串接＋1000 筆上限截斷（`CloudFolderListing.truncated`，相對 spec.md 決策草圖的必要修訂）、下載時 Windows 安全的檔案控制代碼清理順序（先 `sink.close()` 才 `delete()`）。下載＋落地邏輯（`cloud_book_downloader.dart`）刻意獨立於 `epic-30` 的 `remote_book_downloader.dart` 之外，寫入獨立的 `cloud_import_books/`／`cloud_import_download_temp/` 目錄（`CONTEXT.md`「雲端匯入來源帳號」與「遠端書庫」語意不同，不共用落地目錄）；`promoteCloudFileToPermanent()` 正確區分「複製失敗」與「複製成功、只有刪暫存檔失敗」兩種失敗窗口，未重蹈 `epic-30` 曾被指出的錯誤模式。`GoogleDriveBrowserScreen`（資料夾導覽、縮圖記憶體快取、單選/多選、分類下拉選單、1000 筆截斷提示）＋公開的 `CloudDownloadQueueDialog`（序列下載、逐項狀態、失敗手動重試、取消清暫存檔，刻意設計為公開元件供 Issue 4 直接沿用只需傳入不同的 `source`），貫穿注入至「匯入」選單新增的「從 Google Drive 匯入」項目。計畫審查（`reviews/review-plan-issue-3.md`）**APPROVED**，2 項 Minor 已於實作前納入計畫（`CloudDownloadQueueDialog._retry()` 重試期間暫時關閉「完成」按鈕；`_openGoogleDriveBrowser()` 一併重新載入分類）。程式碼審查（`reviews/review-issue-3.md`）初次結論 **CHANGES REQUESTED**：2 項 Important（`_openGroupFilteredView()` 遞迴自我導航漏未貫穿 `googleDriveStorageClient`，導致分類篩選畫面內雲端匯入功能永遠停用；`GoogleDriveBrowserScreen._buildThumbnail()` 未記憶化 in-flight Future，縮圖載入期間任何父層 `setState()` 會觸發重複網路請求與畫面閃爍，同代碼庫姊妹畫面 `RemoteCatalogScreen` 已解決過同一陷阱但本次未依循）皆已修訂並補上迴歸測試。刻意不含重複匯入偵測（Issue 5 範圍）與行動數據警示（Issue 6 範圍）。全專案 `flutter analyze` 乾淨、`flutter test` 1612 項全數通過、零回歸。`GoogleDriveStorageClient` 真實 API 呼叫（HTTP/OAuth 瀏覽器流程）留待真機/人工用真實帳號驗證。

**依賴：** Issue 0（匯入管線）、Issue 1（帳號連結）。

**背景：** 第一個能讓使用者實際「從雲端匯入一本書」的完整可展示切片，也是 Issue 4（OneDrive）與 Issue 5/6（重複偵測、流量警示）共用/依附的主流程。2026-08-17 與使用者確認合併單檔與多檔匯入為同一個切片一次做完。

**What to build：**
- 新增 `CloudStorageClient` 抽象介面（`listFolder`/`downloadFile`，含 `CloudFileEntry` 型別：id/name/isFolder/format/thumbnailUrl/sizeBytes）與 `GoogleDriveStorageClient` 實作：伺服器端 MIME type 過濾（EPUB/PDF/TXT）＋用戶端副檔名過濾（AZW3/CBZ）、分頁串接（單一資料夾最多讀取前 1000 筆，超過則提示）、縮圖網址取得。
- 「匯入」選單新增「從 Google Drive 匯入」項目，開啟瀏覽畫面：逐層資料夾導覽（不做搜尋）、縮圖顯示（含載入佔位符與快取）、單選或多選勾選檔案、可選分類。
- 確認匯入後，多選檔案循序下載（暫存於專屬子目錄，UUID 命名，非平行下載）並顯示逐項狀態（等待中/下載中/完成/失敗）；下載失敗顯示錯誤並可針對單一檔案手動重試（不自動重試）；下載中可取消（取消時立即清除暫存檔）。全部下載完成後透過 Issue 0 擴充後的 `importFiles()` 寫入圖書庫，`source` 設為 `BookSource.googleDrive`，`cloudFileIds` 一併帶入。

**單元測試要求：**
- `FakeCloudStorageClient` 驅動瀏覽畫面 widget test：資料夾導覽、格式過濾後的清單呈現、縮圖佔位符、單選/多選狀態、循序下載＋逐項狀態、下載失敗顯示錯誤＋手動重試、下載取消清暫存檔、超過 1000 筆時的提示、匯入時分類選擇正確傳入。
- `importFiles()` 呼叫時 `source`/`cloudFileIds` 正確帶入的整合驗證（透過 `FakeLibraryRepository` 觀察寫入結果）。
- `GoogleDriveStorageClient` 真實 API 呼叫（HTTP、分頁、縮圖授權）不做自動化測試，留待真機/人工用真實帳號驗證。

**驗收標準：** 使用者可用已連結的 Google Drive 帳號完整走完「瀏覽→勾選單/多檔→下載→匯入」流程，匯入後的書出現在圖書庫且封面/格式偵測與本機匯入的書無差異；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 1。

---

## Issue 4：OneDrive 瀏覽＋匯入（單/多檔）

**Status:** ✅ 已完成（PR #169，分支 `feat/epic-29-issue4-onedrive-storage`，3 個 commit，2026-08-20）

**完成摘要：** 沿用 Issue 3 建好的 `CloudStorageClient` 邊界與共用瀏覽/下載 UI，將 OneDrive 完整接上。新增 `OneDriveStorageClient`：Microsoft Graph API v1.0（`https://graph.microsoft.com/v1.0/me/drive/`）實作，維持與 `GoogleDriveStorageClient` 一致的保守格式過濾策略——刻意不使用 Graph OData `$filter` 做伺服器端精確過濾（規劃階段無法連上真實 Graph API 驗證複合過濾表達式是否可行），改為「伺服器端全取＋用戶端 `detectCloudFileFormat()` 100% 精確比對」，確保跨 provider 格式過濾行為一致；分頁機制使用 `@odata.nextLink`（回應內即為完整絕對 URL，與 Google Drive 不透明的 `pageToken` 不同，換頁直接對該 URL 發 `GET`），累積達 1000 筆時提前終止並標記 `truncated = true`；資料夾/檔案判斷依 `item['folder']` 鍵是否存在，縮圖透過 `$expand=thumbnails($select=medium)` 查詢參數取得；`downloadFile()` 沿用 Issue 3 已驗證過的 Windows 檔案控制代碼清理順序（先 `sink.close()` 才 `delete()`）。`GoogleDriveBrowserScreen` 泛化重新命名為 `CloudBrowserScreen`（沿用 Issue 2 把 `_buildGoogleDriveTile()` 泛化為 `_buildProviderTile()` 的既有先例），刻意保留內部 `Key('google_drive_browser_...')` widget key 字串未重新命名（純內部測試選擇器、非公開 API，重新命名對正確性無益處，只會在 Issue 3 既有測試套件產生大量無關 diff）。`oneDriveStorageClient` 依賴注入路徑貫穿 `main.dart`→`ElinkBookApp`→`LibraryScreen`（含分類篩選畫面自我遞迴導航點），並新增「從 OneDrive 匯入」選單項目。計畫審查（`reviews/review-plan-issue-4.md`）初次結論 **CHANGES REQUESTED**：1 項 Critical（`CloudBrowserScreen` 重新命名時遺漏參數化 `BookSource`，會導致所有 OneDrive 匯入的書籍在 SQLite 被誤記錄為 `BookSource.googleDrive`，破壞資料正確性且讓 Issue 5 未來的重複偵測查詢永遠查無結果）與 2 項 Important（登入過期提示文案寫死為「Google Drive」；測試程式碼引用了本測試檔實際不存在的 `pumpLibraryScreen` helper）皆已於計畫階段修訂——新增 `required final BookSource source` 欄位並貫穿 `_startDownload()`／`_openSubfolder()` 遞迴下鑽／`_openGoogleDriveBrowser()`／`_openOneDriveBrowser()` 四個建構點（含計畫自我審查額外抓到、原審查報告未提及的 `cloud_browser_screen_test.dart` 既有 `pumpScreen` helper 同一缺口）；登入過期文案改為 `'${widget.title ?? '雲端'} 帳號'` 動態組成；測試程式碼改為本檔案實際使用的 `tester.pumpWidget(MaterialApp(home: LibraryScreen(...)))` 標準寫法。修訂後程式碼審查（`reviews/review-issue-4.md`）**APPROVED**，0 Critical／0 Important，僅 1 項 Minor（Microsoft Graph API 下載端點 302 重定向留待真機/人工以真實帳號驗收大檔案下載穩定性）。全專案 `flutter analyze` 乾淨、`flutter test` 1621 項全數通過、零回歸。`OneDriveStorageClient` 真實 API 呼叫（HTTP/OAuth 瀏覽器流程）留待真機/人工用真實帳號驗證。

**依賴：** Issue 2（OneDrive 帳號）、Issue 3（共用瀏覽/下載 UI 與 `CloudStorageClient` 介面）。

**背景：** 設計上刻意讓 OneDrive 沿用 Issue 3 建好的瀏覽/下載畫面（畫面本身只依賴 `CloudStorageClient` 介面運作），工作量明顯小於 Issue 3。

**What to build：**
- 新增 `OneDriveStorageClient` 實作 `CloudStorageClient` 介面（Microsoft Graph API：`driveItem` children 列表＋`@odata.nextLink` 分頁、下載、格式過濾、縮圖）。
- 「匯入」選單新增「從 OneDrive 匯入」項目，接上 Issue 3 已建好的共用瀏覽/下載畫面（不需要重新設計 UI，注入 `OneDriveStorageClient` 即可）。

**單元測試要求：**
- 既有 `FakeCloudStorageClient` 驅動的瀏覽畫面 widget test 天然涵蓋 OneDrive（同一套畫面邏輯）；本 Issue 主要新增 `OneDriveStorageClient` 的真實 API 邏輯，不做自動化測試，比照 Issue 3。
- 若瀏覽畫面因應 OneDrive 出現任何 provider 特有分支（理論上不應該有），需額外補測試涵蓋。

**驗收標準：** 使用者可用已連結的 OneDrive 帳號完整走完「瀏覽→勾選單/多檔→下載→匯入」流程；Google Drive 既有流程不受影響（零回歸）；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 2、Issue 3。

---

## Issue 5：重複匯入偵測（雙層檢查）

**Status:** ✅ 已完成（PR #170，分支 `epic-29-issue-5`，4 個 commit，2026-08-20）

**完成摘要：** 完整比照 `epic-30-calibre-remote-library`（`RemoteCatalogScreen`）已審查合併、已在生產環境驗證過的雙層重複偵測設計，只抽換識別鍵（`remoteBookId` → `cloudFileId`）與呼叫端型別。**Layer 1（選檔前置）**：`CloudBrowserScreen._toggleSelection()` 改為非同步，以 `(provider, cloudFileId)` 呼叫 `LibraryRepository.findByCloudFileId()`，命中時彈出確認對話框、選擇取消則不進入下載佇列；`_pendingDuplicateChecks` 重入防護避免快速連點觸發多次並行查詢與多重彈窗；查詢例外時安全降級為「視同無重複」直接放行，不阻礙使用者操作。**Layer 2（下載後指紋比對）**：`CloudDownloadQueueDialog._downloadOne()` 在「下載到暫存檔」與「搬移至永久位置」之間插入指紋計算（`ComputeRemoteFingerprint`，與 `RemoteCatalogScreen`／`main.dart` 共用同一個 provider 無關的 typedef）與 `findByContentFingerprint()` 查詢，命中且使用者選擇取消時立即刪除暫存檔並標記 `duplicateSkipped`（新增狀態列舉，連同 `checkingDuplicate` 一併補上 `_statusLabel`）；`tempPath` 提升至 `try` 外層區域變數，確保彈窗或比對期間發生任何非預期例外時暫存檔仍能被 `catch` 區塊可靠清理，零孤兒檔案殘留。兩層共用新增的公開頂層函式 `showCloudDuplicateConfirmDialog()`（定義於 `cloud_download_queue_dialog.dart`，因兩層分屬 `cloud_browser_screen.dart`／`cloud_download_queue_dialog.dart` 兩個不同檔案，不像 epic-30 兩層同檔案可用私有函式）。`computeFingerprint` 貫穿注入 `CloudBrowserScreen`（新增必填欄位，含 `_openSubfolder()`／`_startDownload()` 兩個轉發點）與 `library_screen.dart` 的 `_openGoogleDriveBrowser()`／`_openOneDriveBrowser()`，「從 Google Drive／OneDrive 匯入」選單門檻同步改為同時檢查 `widget.computeFingerprint != null`（比照既有「遠端書庫」按鈕的既定門檻慣例）。計畫審查（`reviews/review-plan-issue-5.md`）初次結論 **CHANGES REQUESTED**：1 項 Critical（Task 3 選單門檻變更遺漏同步更新 `library_screen_test.dart` 兩則既有導航測試，兩者皆未提供 `computeFingerprint`，套用門檻變更後會直接回歸失敗）已於計畫階段修訂補上測試更新步驟。程式碼審查（`reviews/review-issue-5.md`）首次自動產出的報告誤判 APPROVED（「自我遞迴導航點無遺漏貫穿」查核有誤）——複核後發現 `_openGroupFilteredView()` 實際上**未**轉發 `computeFingerprint`，會導致分類篩選畫面內「從 Google Drive／OneDrive 匯入」兩個選單項目一起被靜默停用（等同重現 `review-issue-3.md` Important #1 同一種「自我遞迴導航點漏轉發新依賴」錯誤模式，且未被既有測試攔截——既有回歸測試只斷言 `googleDriveStorageClient`，未涵蓋 `computeFingerprint`）；審查報告已改判 CHANGES REQUESTED 並列為 Important #1，隨即修復（補上轉發＋擴充既有回歸測試斷言範圍）後改回 APPROVED。全專案 `flutter analyze` 乾淨、`flutter test` 1628 項全數通過、零回歸。

**依賴：** Issue 0（`findByCloudFileId`/`findByContentFingerprint`）、Issue 3（下載/匯入流程）。

**背景：** `spec.md`「重複匯入偵測」已定案雙層檢查設計，回應 `design.md`／`review-design.md` 的相關討論。

**What to build：**
- 在 Issue 3 建好的瀏覽/下載流程中掛入雙層重複偵測：
  1. **選檔前置檢查**——使用者勾選檔案當下，若該 `(provider, cloudFileId)` 已存在於 `books.cloud_file_id`，立即彈出「這本書之前匯入過了，仍要建立新的一份嗎？」，不需下載即可判斷。
  2. **下載後指紋比對**——前置檢查未命中的檔案，下載到暫存位置後計算 `content_fingerprint`（沿用既有匯入管線的計算邏輯），與 `findByContentFingerprint()` 比對；命中則彈出同樣提示，使用者選擇不建立新副本時立即刪除暫存檔。
- 兩層皆為精確比對，不做書名/作者模糊比對。

**單元測試要求：**
`FakeCloudStorageClient` ＋ 預先塞入命中資料的 `FakeLibraryRepository`，驅動下列情境的 widget test：選檔前置命中、下載後指紋命中、使用者取消時暫存檔清除、使用者選擇仍要匯入時正常完成。

**驗收標準：** 兩層檢查皆能正確攔截真實重複情境（同一雲端檔案重複勾選、與本機已匯入書籍指紋相同的雲端檔案）；使用者可選擇仍要匯入、不被強制阻擋；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 3。

---

## Issue 6：行動數據下載警示

**Status:** `ready-for-agent`

**依賴：** Issue 3（下載流程）。

**背景：** `spec.md`「Further Notes」已定案閾值（單檔 > 20MB），需要新增網路連線狀態偵測依賴（`pubspec.yaml` 現有版本鎖定有相容性歷史，實作時需檢查）。

**What to build：**
- 新增網路連線狀態偵測，在 Issue 3 的下載流程開始前，若偵測到目前是行動數據連線且待下載檔案（單檔）超過 20MB，跳出「確定要用行動數據下載嗎」確認對話框；使用者確認才繼續下載，取消則不下載該檔案。
- 多選批次時對每個超過閾值的檔案如何生效（整批判斷一次 vs. 逐檔判斷），由實作者於 `plans/plan-issue-6.md` 定案並說明理由，兩種皆可接受。

**單元測試要求：**
`FakeCloudStorageClient` 搭配可控的網路狀態測試替身，驅動下列情境的 widget test：行動數據＋大檔案（跳出確認）、Wi-Fi（不跳出確認）、行動數據＋小檔案（不跳出確認）、使用者取消確認（不下載）。

**驗收標準：** 行動數據下載大檔案前正確跳出確認，Wi-Fi 或小檔案不受影響；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 3。

---

## Issue 7：雲端服務 OAuth 統一外部設定檔（技術債／架構深化，2026-08-19 追加）

**Status:** ✅ 已完成（PR #167，分支 `feat/epic-29-issue7-cloud-oauth-config`，4 個 commit，2026-08-19）

**完成摘要：** 新增 `CloudOAuthConfig`（`app/lib/cloud_import/cloud_oauth_config.dart`）取代 `google_oauth_config.dart`／`onedrive_oauth_config.dart` 兩個檔案，以 `String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'/'ONEDRIVE_OAUTH_CLIENT_ID', defaultValue: ...)` 讀取 `--dart-define-from-file` 注入的編譯期常數、未提供時回退既有樣板值，推導公式本身不變動；`GoogleDriveOAuthClient`／`OneDriveOAuthClient` 改為參照 `CloudOAuthConfig.xxx`，既有 OAuth client 測試套件零回歸（`grep` 事先核實零依賴舊常數字面值）。`app/android/app/build.gradle.kts` 獨立解析同一份 `app/config/cloud_oauth.json`（Dart 編譯期常數對 Gradle 建置腳本不可見，兩條建置管線各自解析），推導出的 scheme 寫入 `manifestPlaceholders`；`project.rootDir` 依 Gradle 官方語意恆等於根專案目錄（`app/android/`，非 `:app` 子專案自己的目錄）這個容易被誤改的依賴關係已加註解防護。`AndroidManifest.xml` 兩組既有 intent-filter 改用 `${googleOAuthScheme}`／`${oneDriveOAuthScheme}` 佔位符；新增 `app/config/cloud_oauth.example.json`（提交版控）＋ `.gitignore` 排除本機真實憑證檔；`CLAUDE.md`「常用指令」補上使用說明。計畫審查（`reviews/review-plan-issue-7.md`）與程式碼審查（`reviews/review-issue-7.md`）皆 **APPROVED**，0 Critical／0 Important，僅 2 項 Minor（皆為文件追蹤流程，已補齊）與 1 項已知可接受的殘餘風險（雙軌推導公式須手動同步，已加互相參照註解）。程式碼審查明確標註「Gradle manifest merge 真實建置驗證未獨立覆核」，PR 提交前已補做：實際執行 `flutter build apk --debug`（未帶／帶 `--dart-define-from-file` 假憑證）皆建置成功，`build/app/intermediates/merged_manifest/.../AndroidManifest.xml` 內 `android:scheme` 確認正確反映為 `com.googleusercontent.apps.999999999999-testverify`／`msaltest-verify-id-1234`，與 Dart 端推導公式手動核算結果位元組級一致。全專案 `flutter analyze` 乾淨、`flutter test` 1586 項全數通過、零回歸。

**依賴：** Issue 1、Issue 2（`google_oauth_config.dart`／`onedrive_oauth_config.dart`／`AndroidManifest.xml` 兩組 intent-filter 皆已存在）。

**背景：** `/diagnose` 針對使用者提出的痛點（「雲端硬碟介接設定散在各程式」）進行核實，並核查 `docs/research/cloud_oauth_unified_configuration_architecture.md` 提出的統一設定檔方案技術可行性。**現況核實屬實**：Google／OneDrive 的用戶端 ID 與其反向推導出的 redirect scheme 目前分散在 3 個檔案（`app/lib/cloud_import/google_oauth_config.dart`、`app/lib/cloud_import/onedrive_oauth_config.dart`、`app/android/app/src/main/AndroidManifest.xml` 的 2 組 intent-filter `android:scheme`），開發者填入真實憑證時必須手動同步全部 3 處、且 scheme 需手動反轉/拼接（`com.googleusercontent.apps.<ID>`／`msal<ID>://auth`），容易出錯。

**技術可行性核實**（`/diagnose` 逐項驗證研究報告的關鍵技術主張，而非照單全收）：
- **Gradle `project.rootDir` 路徑推導經查證正確，但依賴一個容易被誤改的 Gradle API 語意**：`project.rootDir`（在 `:app` 子專案的 `build.gradle.kts` 內存取）依 Gradle 官方語意恆等於**根專案**（`settings.gradle.kts` 所在的 `app/android/`）目錄，*不是* `:app` 子專案自己的目錄——因此 `project.rootDir.parentFile` 確實等於 `app/`，`File(project.rootDir.parentFile, "config/cloud_oauth.json")` 確實解析為 `app/config/cloud_oauth.json`，與預期相符。但這個結果依賴一個不直觀的 Gradle 語意（「`rootDir` 永遠指根專案，即使在子專案腳本內存取」），未來若有人「順手」把它改成看似更直覺的寫法（例如改用 `project.projectDir.parentFile`，那會變成 `android/` 而非 `app/`，靜默指向錯誤路徑），會重新製造出本 Issue 想解決的那類「設定散落／路徑對不上」問題——實作時必須在該行程式碼加上明確註解說明這個依賴關係，不可省略。
- **Kotlin DSL（`.kts`）內 `import groovy.json.JsonSlurper` 可正常運作**：Gradle 核心本身以 Groovy 建構，Groovy 執行期一律存在於所有建置腳本（不論 Groovy DSL 或 Kotlin DSL）的 classpath 上，這是業界已有先例的常見手法，非本專案獨創，技術上無風險。
- **`manifestPlaceholders` 機制**：Android Gradle Plugin 標準功能，`${googleOAuthScheme}` 於 manifest merge 階段替換，技術上無風險。
- **`--dart-define-from-file` ＋ `String.fromEnvironment`**：Flutter 3.7 起支援的標準機制，本專案 Dart SDK 鎖定 `^3.11.5`（`pubspec.yaml`），遠高於門檻，無相容性風險；`String.fromEnvironment` 是編譯期常數求值，換設定檔後必須重新編譯（`flutter run`／`flutter build apk` 本就會重新編譯，非額外負擔）。
- **測試零回歸範圍已核實**：`grep` 全 `app/test/` 目錄確認目前沒有任何測試檔案直接引用 `googleOAuthClientId`／`googleOAuthRedirectScheme`／`oneDriveOAuthClientId`／`oneDriveOAuthRedirectScheme` 這幾個常數（Issue 1／2 的 OAuth client 測試僅注入 mock `http.Client`，不涉及這些設定值），本次重構對既有測試套件影響範圍為零。
- **殘餘風險（已知、可接受）**：Dart 端（`CloudOAuthConfig.googleRedirectScheme` 的 getter）與 Gradle 端（`build.gradle.kts` 內對應的 Kotlin 字串運算）各自獨立實作同一套「由用戶端 ID 反推 scheme」公式，兩處理論上仍可能因未來修改其中一處而失去同步——但比起現狀「開發者手動複製貼上同一個推導後字串到 3 個檔案」，本方案已把「需要手動同步的東西」從「每次換憑證都要同步的最終字串」降階為「幾乎不會再變動的推導公式」，風險大幅降低但非歸零，實作時兩處程式碼應以註解互相參照，明確標註「修改這裡也要同步改另一處」。

**What to build：**
- 新增 `app/lib/cloud_import/cloud_oauth_config.dart`：`abstract class CloudOAuthConfig` 靜態成員，`googleClientId`／`oneDriveClientId` 由 `String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID', defaultValue: ...)`／`String.fromEnvironment('ONEDRIVE_OAUTH_CLIENT_ID', defaultValue: ...)` 讀取，`googleRedirectScheme`／`googleRedirectUri`／`oneDriveRedirectScheme`／`oneDriveRedirectUri` 皆為由對應 client ID 推導的 getter（沿用現行 `google_oauth_config.dart`／`onedrive_oauth_config.dart` 既有的推導公式，不變動推導邏輯本身）。**刪除**舊有 `google_oauth_config.dart`／`onedrive_oauth_config.dart` 兩個檔案，`GoogleDriveOAuthClient`／`OneDriveOAuthClient` 改為 import 並參照 `CloudOAuthConfig.xxx`。
- 新增 `app/config/cloud_oauth.example.json`（提交版控，樣板值）；`.gitignore` 新增 `app/config/cloud_oauth.json`（開發者本機真實憑證，不進版控）。
- 修改 `app/android/app/build.gradle.kts`：於 `defaultConfig` 區塊前解析 `app/config/cloud_oauth.json`（不存在則退回 `cloud_oauth.example.json` 樣板值），推導兩組 scheme 後寫入 `manifestPlaceholders["googleOAuthScheme"]`／`manifestPlaceholders["oneDriveOAuthScheme"]`；緊鄰該段程式碼加上註解明確說明 `project.rootDir` 語意（上方「技術可行性核實」已核查的路徑推導依據）。
- 修改 `app/android/app/src/main/AndroidManifest.xml`：兩組既有 intent-filter 的 `android:scheme` 字面值改為 `${googleOAuthScheme}`／`${oneDriveOAuthScheme}` 佔位符。
- 更新根目錄 `CLAUDE.md`「常用指令」小節，補上 `flutter run --dart-define-from-file=config/cloud_oauth.json`／`flutter build apk --release --dart-define-from-file=config/cloud_oauth.json` 兩則指令，說明何時需要（本機測試真實 OAuth 登入流程時）、何時不需要（`flutter analyze`／`flutter test`／不涉及真實登入的一般開發，皆維持現行指令不變）。

**單元測試要求：**
- `CloudOAuthConfig` 的 4 個 getter（`googleRedirectScheme`／`googleRedirectUri`／`oneDriveRedirectScheme`／`oneDriveRedirectUri`）各自的推導正確性（純 Dart 單元測試，不需 widget/裝置）：預設 placeholder 值輸入時的推導結果符合預期格式。
- `GoogleDriveOAuthClient`／`OneDriveOAuthClient` 既有測試套件（Issue 1／2）**不需要修改**即可繼續通過（零回歸，已於上方「技術可行性核實」確認測試零依賴這些常數的具體字面值）。
- Gradle／`AndroidManifest.xml` 的變更不屬於 `flutter test` 涵蓋範圍，驗收改以真機/本機 `flutter build apk --debug`（不帶 `--dart-define-from-file`，驗證退回樣板值時仍可正常建置）與 `flutter build apk --debug --dart-define-from-file=config/cloud_oauth.json`（放入一組假的測試用 JSON，驗證 `manifestPlaceholders` 確實被覆寫，可用 `unzip -p build/app/outputs/.../AndroidManifest.xml` 或 `aapt dump xmltree` 類指令核對編譯後 manifest 內的 scheme 字面值）兩種情境人工核驗。

**驗收標準：** 全部 OAuth 設定改為單一 `app/config/cloud_oauth.json` 維護點；未提供該檔案時，既有 `flutter analyze`／`flutter test`／`flutter build apk --debug` 皆能以樣板 placeholder 值 100% 正常執行（零回歸）；提供真實設定檔時，`flutter build apk --debug --dart-define-from-file=config/cloud_oauth.json` 建置出的 APK 內 `AndroidManifest.xml` 之 scheme 與 Dart 端 `CloudOAuthConfig` 推導值一致。

**Blocked by：** Issue 1、Issue 2。
