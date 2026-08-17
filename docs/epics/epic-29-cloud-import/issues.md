# Epic 29 — 雲端服務匯入書籍：工單清單 (Issues)

依 `spec.md`（Architecting 產出，已通過 `reviews/review-spec.md` 審查修訂）以 `/to-issues` 拆解為 7 個垂直切片（tracer bullet），每個切片皆貫穿 schema/service/UI/測試整條路徑，可獨立驗收。2026-08-17 與使用者確認切片顆粒度（Issue 3/4 合併單/多檔匯入為單一切片；Issue 5/6 重複偵測與行動數據警示維持獨立切片）後定案發布。相依順序：Issue 0／1 可平行開始 → Issue 2 依賴 1 → Issue 3 依賴 0＋1 → Issue 4 依賴 2＋3 → Issue 5 依賴 0＋3 → Issue 6 依賴 3。

---

## Issue 0：擴充既有匯入/查詢管線（Prefactor）

**Status:** `ready-for-agent`

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

**Status:** `ready-for-agent`

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

**Status:** `ready-for-agent`

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

**Status:** `ready-for-agent`

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

**Status:** `ready-for-agent`

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

**Status:** `ready-for-agent`

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
