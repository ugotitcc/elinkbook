# Epic 30 — Calibre 遠端書架整合：Spec

> Architecting 階段產出，本檔案為本 Epic 核心介面/型別的唯一事實來源。承接 `design.md`（Discovery，已定案的產品/範圍決策不在此重複討論）與 `reviews/review-design.md`（已核實、待落實的技術項目，已於 `design.md`「審查後續」與本文件落實）。

## Problem Statement

擁有自架電子書庫（Calibre Content Server、Calibre-Web，或任何標準 OPDS 書庫伺服器，例如家用 NAS 或公網 VPS）的使用者，目前無法在 elinkBook 內直接瀏覽這些書庫——必須先透過電腦或瀏覽器把書下載下來，再想辦法傳到手機、用本機檔案選擇器匯入，操作繁瑣，也無法「先瀏覽選讀、需要時才下載」這種對大型自架書庫特別重要的使用模式。

## Solution

在 elinkBook 內建「遠端書庫」功能：使用者可新增多個 Calibre／OPDS 站點（自架 NAS、公網 Calibre-Web、公開匿名書庫皆可），透過獨立常駐入口持續瀏覽站點目錄（依分類下鑽、分頁載入、封面縮圖），勾選單本或多本書籍後批次下載並自動匯入圖書庫。下載完成的書與本機匯入的書無異；使用者也可以在需要釋放空間時移除本機檔案但保留雲端紀錄，之後隨時重新下載並無縫接續劃線/書籤/閱讀進度。

## User Stories

1. 作為擁有自架 Calibre 書庫的使用者，我希望能在 App 內新增遠端書庫站點，這樣就能直接瀏覽我的個人書庫，不用先透過電腦下載再匯入手機。
2. 作為同時管理多個書庫（家用 NAS＋公網 Calibre-Web）的使用者，我希望能新增多個站點並個別管理，這樣不用被迫只能連一個伺服器。
3. 作為使用內網 NAS 的使用者，我希望能用純 HTTP（非 TLS）連線，這樣不用額外設定憑證。
4. 作為使用自簽憑證伺服器的使用者，我希望能選擇信任該憑證連線，這樣還是能正常使用。
5. 作為使用公開匿名 OPDS 書庫（如 Project Gutenberg）的使用者，我希望不用輸入帳密也能新增站點，這樣能直接瀏覽公開書庫。
6. 作為新增站點的使用者，我希望能先測試連線，這樣輸入錯誤時能立刻發現，而不用等到瀏覽時才出錯。
7. 作為使用者，我希望能編輯已新增的站點設定（名稱/網址/帳密），這樣密碼更新後不用刪除重建。
8. 作為使用者，我希望能刪除不再使用的站點，這樣書架不會堆積過時的連線。
9. 作為刪除站點的使用者，若這個站點還有尚未下載、僅有雲端紀錄的書籍，我希望被提前告知，這樣不會意外造成書籍永久失效。
10. 作為刪除站點的使用者，我希望已經下載完成的書籍不受影響，這樣刪除站點連線不會波及我已經在讀的書。
11. 作為瀏覽遠端書庫的使用者，我希望能依照伺服器提供的分類（作者/系列/標籤）逐層點進去，這樣能像逛書架一樣找書。
12. 作為瀏覽大型書庫的使用者，我希望清單能分頁載入，這樣不會一次載入整個書庫卡住畫面。
13. 作為瀏覽書目清單的使用者，我希望能看到封面縮圖，這樣能快速辨認想要的書。
14. 作為選書的使用者，我希望能一次勾選多本書批次下載，這樣不用一本一本重複整個流程。
15. 作為批次下載多本書的使用者，我希望能看到每本書各自的狀態（等待中/下載中/完成/失敗），這樣能清楚掌握進度。
16. 作為選書的使用者，若同一本書提供多種格式，我希望能選擇要下載哪一種，這樣能挑選自己裝置支援的格式。
17. 作為選書的使用者，我希望清單只顯示 App 支援的格式，不支援的格式應該置灰或不可選，這樣不會下載完才發現打不開。
18. 作為下載書籍的使用者，我希望下載完成後這本書直接出現在我的書架上，跟本機匯入的書沒有差異，這樣使用體驗一致。
19. 作為選到之前已下載過的書的使用者，我希望在下載前就被提醒可能重複，這樣不會浪費流量重複下載。
20. 作為選到之前用別的格式下載過的同一本書的使用者，我希望也被提醒重複，這樣不會誤以為是不同的書而重複建立。
21. 作為下載失敗（例如網路中斷）的使用者，我希望能看到明確錯誤並針對該檔案手動重試，這樣不用整批重來。
22. 作為需要釋放裝置儲存空間的使用者，我希望能移除某本書的本機檔案但保留這本書在書架上的紀錄，這樣之後想讀還能重新下載。
23. 作為移除本機快取的使用者，我希望這本書之前的劃線、書籤、閱讀進度都還在，這樣重新下載後可以無縫接續閱讀。
24. 作為在書架上看到「待下載」狀態書籍的使用者，我希望點開時能清楚知道需要重新下載，並在下載前跳出確認，這樣不會誤觸浪費流量。
25. 作為圖書庫使用者，我希望「待下載」的書跟本機/其他來源的書混合顯示在同一個書架，並用清楚的圖示區分狀態，這樣書架維持「一個地方看所有書」的體驗。
26. 作為使用者，我希望遠端書庫有獨立的常駐入口可以隨時進去瀏覽，而不是只能透過一次性的「匯入」選單，這樣才符合「持續逛書庫」的使用情境。
27. 作為開發者，我希望遠端書庫瀏覽/下載/站點管理邏輯不需要真的連線真實伺服器就能測試，這樣 CI 上的測試能維持快速且結果穩定。
28. 作為開發者，我希望本 Epic 對既有 `BookImportService`／`LibraryRepository`／`books` 表 schema 的擴充，與 `epic-29-cloud-import`（尚未實作，實際落地順序未定）彼此不衝突，這樣不論哪個先實作都不需要打掉重寫。

## Implementation Decisions

### 與 `epic-29-cloud-import` 的順序無關性（Sequencing Independence）

`epic-29-cloud-import` 已完成 Discovery/Architecting/Scrum Master，但尚未進入實作；本 Epic 也尚未實作。兩者哪個先落地目前未定，以下三個共用觸點的設計方式**刻意寫成順序無關**，實作者需以「實作當下的實際程式碼狀態」為準，不能假設對方 Epic 的 spec.md 內容已經生效：

1. **`BookImportService.importFiles()` 的 `source` 參數**：目前（2026-08-17 核實）簽章為 `importFiles(uris, {displayNames, folderName})`，尚無 `source` 參數。兩個 Epic 都需要它。**先落地的一方新增此參數**（`BookSource source = BookSource.local`），**後落地的一方檢查參數是否已存在，已存在則直接沿用、只疊加自己的新參數，不重複宣告**。
2. **`books` 表 schema 版本號**：目前為 21。本 Epic 的 schema 變更**取實作當下最新版本號 +1**，不寫死特定數字（見下方「資料模型與 Schema」）。若本 Epic 先取走某個版本號，`epic-29-cloud-import` 實際進入實作時需自行核對當下最新版本號，其 spec.md 內寫死的版本號屆時可能需要小幅修訂——這是該 Epic 實作時的責任，非本文件能提前處理。
3. **`LibraryRepository.findByContentFingerprint(String fingerprint) → Book?`**：兩個 Epic 都需要這個新查詢方法（目前不存在）。**先落地的一方新增，後落地的一方檢查是否已存在，已存在則直接重用，不重複定義**。

`BookSource` enum 新增值（本 Epic 新增 `calibreOpds`，`epic-29` 新增值時賦值 `googleDrive`/`oneDrive`）彼此獨立、互不影響，enum 值本來就是可疊加的，不受順序影響。

### 站點管理：`RemoteServerRepository`

```dart
abstract class RemoteServerRepository {
  Future<List<RemoteServerProfile>> listServers();
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password});
  Future<void> updateServer(RemoteServerProfile profile, {String? password});
  Future<void> deleteServer(String serverId);
  Future<String?> loadPassword(String serverId);
}

class RemoteServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final RemoteServerType type; // opds / calibreServer / calibreWeb
  final String? username;      // null 代表匿名連線
  final bool allowInsecure;    // 允許自簽憑證/憑證錯誤
  final DateTime createdAt;
  final DateTime? lastAccessedAt;
}
```
（此為決策草圖，非最終原始碼；上方僅為說明本 Epic 的核心契約形狀。）

- 密碼**不**放進 `RemoteServerProfile`，獨立存 `flutter_secure_storage`（既有依賴，`epic-8-sync` 已引入），key 格式 `remote_server_password_<id>`——比照 `SyncAccountRepository` 對敏感憑證的既有處理方式，但 profile 本身（名稱/網址/帳號等非敏感資料）改存 SQLite 新表 `remote_servers`（見「資料模型與 Schema」），而非像 `SyncAccountRepository` 完全不建表——理由已在 `design.md` 定案：多筆列表資料適合關聯式表，且 `books.remote_server_id` 需要反查站點顯示名稱。
- 讀取密碼失敗（Keystore 損毀等已知環境因素）比照 `SyncAccountRepository.loadAuthToken()` 既有先例，安全退回 `null`（視同該站點密碼遺失，畫面提示重新輸入），不拋例外、不卡住畫面。
- `RemoteServerRepository` **不含網路能力**——「測試連線」需要實際打 HTTP 請求，職責上屬於 `OpdsClient`（見下方），保持 Repository 純持久化、無網路依賴，便於單元測試。
- `deleteServer()` 的連鎖處理（回應 `review-design.md` Important #4）：交易內依序執行——(a) 查詢該站點是否存在 `is_downloaded = 0` 的書籍（僅雲端紀錄、無本機檔案），若有則**拒絕刪除**並回傳這些書籍供 UI 顯示示警清單（呼叫端需先引導使用者刪除這些書籍列或改為其他處置，才能真正刪除站點）；(b) 確認沒有此類書籍後，刪除 `remote_servers` 該筆——已下載書籍的 `remote_server_id` 由資料庫外鍵約束（或應用層等效手段，見下方技術風險）自動清為 `NULL`，退化為一般本機書籍。

### OPDS 瀏覽與下載：`OpdsClient`

單一共用介面，是整個瀏覽＋下載＋測試連線 UX 唯一依賴的邊界（seam 已與使用者確認）：

```dart
abstract class OpdsClient {
  Future<bool> testConnection(RemoteServerProfile server, {String? password});

  /// [feedUrl] 為 null 時載入該站點根目錄；非 null 時載入指定的分類/分頁 Feed。
  Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl});

  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  });
}

class OpdsFeed {
  final String title;
  final String? nextUrl;
  final String? prevUrl;
  final List<OpdsNavigationLink> navigationLinks; // 分類下鑽（作者/系列/標籤等）
  final List<OpdsEntry> entries;                  // 本頁書目
}

class OpdsNavigationLink {
  final String title;
  final String href;
}

class OpdsEntry {
  final String remoteBookId; // OPDS 條目 id，書本層級，不分格式（design.md 已定案）
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final List<OpdsAcquisition> acquisitions; // 本書提供的各格式下載連結
}

class OpdsAcquisition {
  final String href;
  final BookFileFormat? format; // null 代表不支援的格式，UI 置灰不可選
  final int? sizeBytes;
}
```
（此為決策草圖，非最終原始碼。）

- **分頁模式與 `epic-29-cloud-import` 的刻意差異**：`epic-29` 的 `CloudStorageClient.listFolder()` 內部把分頁全部吃掉、對呼叫端回傳資料夾完整清單（上限 1000 筆）。本 Epic **不採用同樣模式**——OPDS 協議本身就是設計成一頁一頁走訪（`nextUrl`/`prevUrl`），書庫規模可能遠大於雲端硬碟單一資料夾，`fetchFeed()` 每次只回傳「這一頁」，由 UI 層依 `nextUrl` 是否為 `null` 決定要不要提供「載入更多」的操作（無限捲動或按鈕皆可，UI 細節留給實作者），不做內部自動分頁累加、不設固定筆數上限。
- **認證與縮圖**：`OpdsClient` 內部依 `server.username`（`null` 則不帶 `Authorization` header）與呼叫端傳入的 `password` 組出 HTTP Basic Auth header。**〔`review-design.md` Minor #2 採納〕** `thumbnailUrl` 載入同樣需要帶相同的 `Authorization` header 才能存取（Calibre 站點啟用 Basic Auth 時），UI 層的縮圖載入元件需要支援自訂 HTTP headers，不能直接用只接受裸 URL 的元件。
- **自簽憑證/不安全連線**：`server.allowInsecure == true` 時，該次連線（`testConnection`／`fetchFeed`／`downloadBook`）透過 `HttpClient.badCertificateCallback` 放行憑證錯誤——**僅針對這一次連線物件生效，不得全域關閉憑證驗證**（`review-design.md` Important #3 核實採納的部分）。純 HTTP（非 TLS）連線本身**不需要**額外的 Android `network_security_config.xml` 設定——已核實 `AndroidManifest.xml:7` 現有 `android:usesCleartextTraffic="true"` 全域已開啟（`review-design.md` Important #3 核實修正的部分，見 `design.md`「審查後續」）。
- **格式過濾**：`OpdsAcquisition.format` 依 Atom `<link>` 的 `type` 屬性（MIME type）比對 elinkBook 既有 6 種支援格式對應的 MIME type；比對不到已知 MIME type 時退回看 `href` 副檔名；皆無法判斷則 `format = null`，UI 置灰。
- **分頁循環防護**（`review-design.md` Minor #1 採納）：`OpdsClient` 實作內部需追蹤本次瀏覽路徑已造訪過的 Feed URL（例如一個 Set），若 `nextUrl` 指回已造訪過的 URL（部分不規範伺服器的已知行為），視為分頁結束，不繼續請求，避免無限遞迴。
- **下載行為**：下載到暫存路徑（沿用既有匯入慣例，暫存於專屬子目錄＋UUID 命名，比照 `epic-29` spec.md「暫存檔沙盒與清理」的既定手法），確認匯入成功後才移動/交給 `BookImportService` 落地；使用者取消（`cancellationToken`）或下載失敗時立即清除暫存檔，不留孤兒檔案。**不做斷點續傳**（`design.md` 已定案），失敗後由呼叫端提供「重試」入口，重試即從頭重新呼叫 `downloadBook()`。
- **測試連線**：`testConnection()` 內部呼叫 `fetchFeed(server, feedUrl: null)` 並捕捉例外，成功回傳 `true`、任何網路/認證/解析錯誤回傳 `false`（不需要細分錯誤類型，UI 統一顯示「連線失敗，請檢查網址/帳密/憑證設定」）。
- **`OpdsFeedParser`**（`OpdsClient` 真實實作內部使用，非對外 seam 的一部分）：解析失敗容錯——缺失 `<title>` 時取 Feed/Entry 的 `id` 或檔名當標題，缺失作者標記「未知作者」，格式不規範的欄位跳過不拋例外，維持既有匯入流程「降級但不中斷」的一貫風格（比照 `book_import_service_impl.dart` 對外部詮釋資料缺失的既有處理慣例）。

### 既有匯入管線擴充：`BookImportService`

```dart
Future<ImportResult> importFiles(
  List<String> uris, {
  List<String?>? displayNames,
  String? folderName,
  BookSource source = BookSource.local,
  String? remoteServerId,
  Map<String, String>? remoteBookIds, // uri -> remote_book_id
});
```

- `source`／`remoteServerId`／`remoteBookIds` 皆為可選參數且有預設值，**既有呼叫端（本機匯入）完全不需要修改**，零回歸風險；與 `epic-29` 的參數疊加方式見上方「順序無關性」。
- OPDS 下載完成、使用者確認匯入後，把暫存路徑清單連同 `source: BookSource.calibreOpds`、`remoteServerId`（本次批次所屬站點，單一值，因為一次瀏覽/下載動作只會來自同一個站點）與對應的 `remoteBookIds` map 一併呼叫 `importFiles()`；內部 `_importSingleFile()` 現有的格式偵測/封面產生/指紋計算流程**不需要新增任何格式分支**（下載下來的檔案與本機檔案在這條管線裡完全等價），只有最外層組裝 `Book` 物件時需要多寫入 `remoteServerId`／`remoteBookId`／`isDownloaded: true` 三個欄位。

### 資料模型與 Schema

- 新表 `remote_servers`：
  ```sql
  CREATE TABLE remote_servers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_url TEXT NOT NULL,
    type TEXT NOT NULL,              -- 'opds' | 'calibreServer' | 'calibreWeb'
    username TEXT,                   -- NULL = 匿名
    allow_insecure INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    last_accessed_at INTEGER
  );
  ```
- `books` 表新增三欄，schema 版本號取實作當下最新版本號 +1（見上方「順序無關性」，不寫死數字）：
  ```sql
  ALTER TABLE books ADD COLUMN remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL;
  ALTER TABLE books ADD COLUMN remote_book_id TEXT;
  ALTER TABLE books ADD COLUMN is_downloaded INTEGER NOT NULL DEFAULT 1;
  CREATE INDEX IF NOT EXISTS idx_books_remote_lookup ON books(remote_server_id, remote_book_id);
  ```
  既有裝置升級後所有既有書籍 `is_downloaded` 預設 `1`（視為已下載），比照既有 `content_fingerprint`／`position_updated_at` 等既有欄位的 `ALTER TABLE` migration 慣例，不影響既有資料。
- **技術風險與備援方案**：本專案既有 `REFERENCES ... ON DELETE SET NULL` 先例（`notes.highlight_id`，`sqlite_library_repository.dart:496`）皆在 `CREATE TABLE`（初始建表）時宣告，尚無透過 `ALTER TABLE ADD COLUMN` 事後補外鍵約束的先例；SQLite 對 `ADD COLUMN` 搭配 `REFERENCES` 有版本相關限制，需要實作階段（Issue 0 等價的 Prefactor 步驟）實測確認目前 sqflite 底層 SQLite 版本是否支援直接內聯宣告。**若不支援**：改為不在欄位定義內宣告 FK 約束，`RemoteServerRepository.deleteServer()` 於交易內先執行 `UPDATE books SET remote_server_id = NULL WHERE remote_server_id = ?`（範圍限定被刪除站點）再刪除 `remote_servers` 該筆——兩種手段對呼叫端／使用者行為完全等價，實作階段依實測結果擇一，不影響本 Epic 其餘設計。
- `LibraryRepository` 新增兩個查詢方法（介面＋ `SqliteLibraryRepository` 實作＋ `FakeLibraryRepository` 測試替身，比照既有三件套模式）：
  - `findByRemoteBookId(String serverId, String remoteBookId) → Book?`（選檔前置重複檢查）
  - `findByContentFingerprint(String fingerprint) → Book?`（下載後指紋比對；與 `epic-29` 共用，見上方「順序無關性」）
- `Book` 模型新增三個欄位對應上方 schema：`remoteServerId`（`String?`）、`remoteBookId`（`String?`）、`isDownloaded`（`bool`，預設 `true`）。**`filePath` 型別與既有 `required String` 契約維持不變**（`review-design.md` Important #2 核實採納）——`isDownloaded == false` 時，`filePath` 保留「最後一次成功下載的本機路徑」字串（實體檔案已被刪除），純粹作為歷史紀錄；任何嘗試開啟該書的呼叫端（`LibraryScreen` 開書入口）都必須先檢查 `isDownloaded`，不可直接信任 `filePath` 指向可讀檔案。

### 重複匯入偵測（雙層檢查，比照 `epic-29` 機制）

1. **選檔前置檢查**：使用者在 `OpdsCatalogScreen` 勾選書籍的當下，若該 `(remoteServerId, remoteBookId)` 已存在於某本書（`findByRemoteBookId()` 命中），立即提示「這本書之前匯入過了，仍要建立新的一份嗎？」——不需要下載就能判斷。
2. **下載後指紋比對**：選檔前置檢查沒有命中的檔案（例如本機早已透過別的管道匯入過同一本書），正常下載到暫存位置後，比照既有匯入流程計算 `content_fingerprint`，與 `findByContentFingerprint()` 比對，命中則同樣提示，使用者選擇不建立新副本時立即刪除暫存檔案。
3. 同一本書若先前用不同格式下載過，因 `remoteBookId` 為書本層級，仍會被選檔前置檢查命中，視為重複並提示——不為「格式不同」開特例。
4. 兩層檢查皆使用**精確比對**，不做書名/作者模糊比對，理由同 `epic-29`（見 `CONTEXT.md`「書籍內容指紋」已知覆蓋率落差）。

### 下載與快取生命週期

- **移除本機快取**：圖書庫既有的書籍操作選單新增「移除本機快取」選項（**僅對 `source == BookSource.calibreOpds` 的書籍顯示**——本機/雲端硬碟來源的書沒有「重新下載」能力，不適用此選項）。動作內容：刪除 `filePath` 指向的實體檔案，`isDownloaded` 更新為 `false`；`filePath` 字串本身、`coverPath`、劃線／書籤／閱讀進度等其餘欄位完全不變。
- **待下載狀態呈現**：`isDownloaded == false` 的書籍在書架網格/列表上疊加雲朵角標（沿用既有封面元件擴充，不新增獨立版面）。
- **重新下載**：點擊「待下載」書籍時，先跳出確認對話框（沿用/仿照 `epic-29` Issue 6 的行動數據下載警示邏輯——偵測目前是否為行動數據連線，是則額外強調流量提示），確認後透過該書 `remoteServerId` 反查 `RemoteServerRepository` 取得站點資訊與密碼，重新呼叫 `OpdsClient.downloadBook()`（需要重新取得下載連結：若原 `OpdsEntry`/`OpdsAcquisition` 的 `href` 仍可直接重用則直接下載，若 OPDS 伺服器的下載連結有時效性則需要先 `fetchFeed()` 重新查出該 `remoteBookId` 對應的最新 Feed 條目——**由實作者依所連線伺服器實測行為決定**，兩種情況下的成功結果一致：下載完成後更新該書 `filePath`／`isDownloaded=true`，不建立新的 `Book` 記錄）。
- **站點刪除防護**：見上方「站點管理」小節 `deleteServer()` 的行為描述。

### UI 落地位置

- `LibraryScreen` 新增一個獨立常駐入口進入「遠端書庫」（`design.md` 已定案不塞進「匯入」選單；具體視覺位置——AppBar 圖示按鈕或抽屜選單項目——由實作者依既有 IA 慣例決定）。
- 新增畫面：
  - `RemoteServerListScreen`：站點清單（新增/編輯/刪除，含測試連線）。
  - `RemoteServerFormScreen`：新增/編輯單一站點表單（名稱/網址/帳密/允許不安全連線開關/測試連線按鈕）。
  - `RemoteCatalogScreen`：選定站點後的 OPDS 目錄瀏覽（分類下鑽、分頁載入、縮圖網格、多選勾選批次下載）。
  - `FormatSelectionDialog`：同一書目多格式時的選擇彈窗（沿用 `epic-29` 命名慣例）。
- 圖書庫書籍操作選單新增「移除本機快取」選項（僅 Calibre 來源書籍顯示，見上方）。

## Testing Decisions

好的測試只驗證外部可觀察行為（畫面上看得到的狀態、呼叫端能觀察到的回傳值/副作用），不測內部實作細節。

- **`RemoteServerRepository`**：Dart 單元測試，不需裝置/網路，比照 `SyncAccountRepository` 既有測試模式（CRUD 狀態轉換、密碼讀取失敗安全退回 `null`、`deleteServer()` 對「有僅雲端紀錄書籍」情境的拒絕邏輯）。`SqliteLibraryRepository`／`FakeLibraryRepository` 兩層皆須覆蓋新增的 `remote_servers` 相關資料存取。
- **`OpdsClient`**：新增 `FakeOpdsClient`（`app/test/support/`，比照既有 `FakeCloudStorageClient` 命名慣例），回傳預先寫死的 `OpdsFeed`／模擬下載成功或失敗／模擬 `testConnection()` 成功或失敗。所有畫面（站點管理 CRUD＋測試連線、目錄瀏覽含分類下鑽與分頁「載入更多」、格式過濾後的清單、縮圖佔位符、多選批次下載狀態、失敗重試、多格式選擇彈窗、重複匯入偵測彈窗、待下載狀態角標與重新下載確認流程）皆用這個 Fake 驅動 widget test，比照 `ReaderScreen` 用一系列 Fake 驅動測試的既有模式。真實 `OpdsHttpClient` 實作（實際 HTTP 呼叫、XML 解析、Basic Auth header、自簽憑證放行、分頁循環防護的實際觸發）**不做自動化測試**，理由比照 `epic-29` 對 `GoogleDriveStorageClient`／`OneDriveStorageClient` 的既有慣例，留待真機或人工用真實 Calibre/OPDS 伺服器驗證。
- **`BookImportService.importFiles()` 擴充**：延伸既有 `BookImportServiceImpl` 測試套件，新增涵蓋 `source == BookSource.calibreOpds`／`remoteServerId`／`remoteBookIds` 參數的案例，確認 `Book.remoteServerId`／`remoteBookId`／`isDownloaded` 正確落地資料庫，且既有本機匯入案例（未傳入新參數）行為不變（零回歸）。
- **重複匯入偵測**：`findByRemoteBookId()`／`findByContentFingerprint()` 各自的單元測試（`FakeLibraryRepository`／`SqliteLibraryRepository` 兩層皆須覆蓋）；`RemoteCatalogScreen` 對「偵測到重複」情境的 UX（彈窗、選擇不建立新副本時清暫存檔）透過 `FakeOpdsClient` ＋ 預先塞入命中資料的 `FakeLibraryRepository` 驅動 widget test。
- **移除快取／重新下載生命週期**：widget test 驗證「移除本機快取」動作後 `isDownloaded` 變 `false`、實體檔案被刪除、劃線/書籤/進度資料不受影響（透過既有 `FakeHighlightsRepository`／書籤 repository 等既有測試替身組合驗證）；「重新下載」流程的確認對話框與行動數據警示，透過 `FakeOpdsClient` 驅動。
- **站點刪除連鎖行為**：widget test／單元測試分別驗證「有僅雲端紀錄書籍時拒絕刪除並回傳清單」與「刪除後已下載書籍的 `remote_server_id` 變 `NULL`」兩種情境。

## Out of Scope

- Calibre 專屬 REST API（`/ajax/search`、`/ajax/categories`）進階搜尋/分類（`design.md` 已定案，留待後續 Issue）。
- OPDS 全文/即時搜尋（OpenSearch）。
- 斷點續傳。
- E-Ink 專屬優化（離散分頁導航、封面縮圖雙層快取，`design.md` 已定案獨立成本 Epic 最後一個 Issue，本份 spec 不涵蓋其技術細節，留待該 Issue 規劃時再展開）。
- 研究報告 Backlog 章節的 Obsidian Fast Note Sync（明確排除，獨立於未來專屬 Epic）。
- DRM 保護的 OPDS 條目支援（PRD 既有「不支援解除 DRM」邊界已涵蓋，比照「不支援格式」處理方式過濾/置灰）。
- 同一站點多組帳號並存與切換（`RemoteServerProfile` 每筆已是獨立站點，若使用者需要同伺服器不同帳號可新增第二筆 Profile，不特別做「同站點多帳號」的專屬 UI）。

## Further Notes

- **新增依賴**：`xml`／`http` 需由 `dev_dependencies` 提升至正式 `dependencies`（`review-design.md` Important #1，已核實現況）；不需要為本 Epic 額外引入 OAuth 相關套件（與 `epic-29` 不同，OPDS/Calibre 走 Basic Auth，不需要 `flutter_web_auth_2` 之類套件）。若「重新下載」的行動數據警示要偵測連線類型，需要 `connectivity_plus`（與 `epic-29` Issue 6 共用需求，若該 Issue 先落地可直接沿用既有依賴，順序無關性同上）。
- **`RemoteServerType` 三個值（`opds`／`calibreServer`／`calibreWeb`）目前在 v1 沒有任何行為差異**——`OpdsClient` 一律走標準 OPDS 協議，`type` 欄位純粹是使用者填寫時的分類標記／UI 顯示用途（例如提示「原生 Calibre Content Server 可額外使用進階搜尋」），為後續 Calibre 專屬 REST API 加強 Issue 預留擴充位，不在本 Epic 產生任何行為分支。
- 站點刪除防護的 UI 措辭、待下載角標的視覺樣式、`RemoteCatalogScreen` 的縮圖 Grid/List 排版，皆為視覺細節，交由實作者比照 `LibraryScreen`／`epic-29` 相關畫面的既有視覺語言決定，不在本 spec 中規定死。
