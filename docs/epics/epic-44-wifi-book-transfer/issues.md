# Epic 44 — WiFi 傳書：工單清單 (Issues)

依 `spec.md`（Architecting 產出，已通過 `reviews/review-spec.md` 審查修訂）拆解為 4 個垂直切片（tracer bullet），每個切片皆貫穿邏輯/HTTP/UI/測試整條路徑，可獨立驗收。2026-09-17 與使用者確認顆粒度與相依關係後定案發布（不拆分、不合併）。相依順序：Issue 0 無依賴 → Issue 1 依賴 0 → Issue 2／Issue 3 皆依賴 0＋1（互相獨立、可平行）。

**（`/receiving-code-review` 審查修正，2026-09-17）Issue 2／Issue 3 平行執行的操作面提醒**：兩者邏輯獨立（Issue 3 不需要等 Issue 2 的程式碼合併回主幹才能開始寫），依賴關係維持不變；但兩者會改到相同的 3 個檔案（`wifi_transfer_service.dart`／`wifi_transfer_http_server.dart`／`assets/wifi_transfer/index.html`，各自新增不同方法/路由/UI 區塊），若真的分兩個 worktree／subagent 平行進行，合併回主幹時預期會在這些檔案產生文字衝突（非邏輯衝突，各自新增的內容不互相牴觸，純粹是同檔案不同位置的文字合併）。建議其中一個先完成並合併回 `main`，另一個在合併後 `rebase` 再繼續，而非兩者同時各自開分支後才一起處理合併；若人力/時程仍要同時開工，動工前先協調好各自要新增的方法/路由名稱與大致插入位置，降低合併時的排解成本。

---

## Issue 0：依賴引進與共用檔案 Prefactor

**Status:** ready-for-agent

**依賴：** 無，可立即開始。

**背景：** 本身不含任何使用者可見的 WiFi 傳書功能，是後續全部切片共用的基礎設施（`spec.md`「新增依賴」「共用檔案異動」「`LibraryRepository` 異動」已定案介面）。`readContentUriAll` 的 channel 改名修正原本就存在於既有 PDF 開書/背景索引路徑的 ANR 風險，不是 WiFi 傳書新增的問題，但本 Epic 是第一個明確要求它被修正的呼叫端，順勢一併處理。

**What to build：**
- `pubspec.yaml` 新增正式 `dependencies`：`shelf`、`shelf_multipart`、`qr_flutter`、`wakelock_plus`。
- `app/lib/reader/pdf_reader_view.dart:277` 的 `_resourceChannel`：channel 名稱由 `elinkbook/reader_resources` 改為 `elinkbook/reader_resources_cache`（該檔案僅此一處呼叫點使用這個常數）。
- `app/lib/search/pdf_content_indexer.dart:94` 的 `_resourceChannel`：同樣改名（該檔案僅此一處呼叫點使用這個常數）。
- `ReaderResourceChannel.kt` **不需要修改**——`readContentUriAll` 等方法本來就由同一個 `onMethodCall()` 同時服務兩條 channel，差別只在 Dart 端呼叫哪一個 channel 名稱。
- `LibraryRepository` 新增抽象方法 `Future<Book?> findBookById(String id);`，`SqliteLibraryRepository` 實作為 `SELECT * FROM books WHERE id = ?`，`FakeLibraryRepository`（`app/test/support/`）比照既有介面/實作/Fake 三件套模式補上。

**單元測試要求：**
- `findBookById()`：命中／未命中兩種情境，`SqliteLibraryRepository` 與 `FakeLibraryRepository` 兩層皆須覆蓋。
- `pdf_reader_view.dart`／`pdf_content_indexer.dart` 既有測試套件（含 `content://` 開書/背景索引情境）全數維持綠燈，確認 channel 改名對既有呼叫端行為零回歸（Dart 端只是 `await` 一個 `Future`，換到背景執行緒不影響呼叫方式或回傳值）。

**驗收標準：** `flutter analyze` 乾淨；`flutter test` 全數通過、零回歸；`pubspec.yaml` 四個新依賴皆可正常 `flutter pub get`；真機（或至少一次手動驗證）確認既有 `content://` PDF 開書與背景全文索引仍正常運作。

**Blocked by：** 無。

---

## Issue 1：網路偵測＋WiFi 傳書畫面骨架＋伺服器基礎設施＋入口

**Status:** completed（**2026-09-18 已完成並合併回 `main`（PR [#257](https://git.jigong.org/huthief/elinkBook/pulls/257)，分支 `feat/epic-44-issue-1`）**：`plans/plan-issue-1.md` 11 個 Task 全數完成——`network_availability.dart`（三態偵測＋純函式 `classifyNetworkInterfaces()`）、`WifiTransferService` 骨架（三個業務方法 `throw UnimplementedError()` 留給 Issue 2／3）、`assets/wifi_transfer/index.html`、`WifiTransferHttpServer`（`start()`/`stop()`、`withTransferPermit()` 併發節流、`GET /` 真實服務首頁，`/api/*` 先回 501）、`WifiTransferDependencies` bundle、`WifiTransferScreen`（IP/QR Code、手動覆寫、螢幕常亮、離開示警）、`SourcesHomeScreen`／`AdaptiveShellScaffold`／`main.dart` 三層裝配串接、`integration_test/wifi_transfer_screen_test.dart` 真機驗證。獨立程式審查（`reviews/review-issue-1.md`）：0 Critical／0 Important／4 Minor，結論 Ready to merge: Yes；審查後追加 commit（`2a629676`）採納 Minor #2（`WifiTransferHttpServer` 新增 `dispose()` 釋放 `_activeTransfersNotifier`）與 Minor #3（測試輔助函式 `_realGet`/`_realPost` 收斂為共用的 `_sendRealRequest()`），Minor #1（`main.dart` import 順序）與 Minor #4（`/api/books/<id>/download` 路徑邊界情境，留給 Issue 2）依人類決定維持原狀。`flutter analyze`（No issues found）／本次異動觸及測試檔全數通過／完整 `flutter test`（2558 passed / 1 skipped / 2 failed，2 個失敗經比對為 base commit 既存缺陷，非本 Issue 引入的回歸）皆為綠燈。Issue 2／3 現已可開工。）

**依賴：** Issue 0（`wakelock_plus`／`shelf` 依賴、`findBookById` 尚不需要在本 Issue 使用，但共用 Prefactor 須先落地）。

**背景：** `spec.md`「`network_availability.dart`」「`wifi_transfer_http_server.dart`」「`WifiTransferScreen` 畫面邏輯」「依賴注入收斂」已定案介面。本 Issue 建好整條「打開 WiFi 傳書、PC 瀏覽器連得上」的骨架，`/api/*` 路由本身留給 Issue 2／3 各自實作，但伺服器啟動/停止、併發節流號誌、活躍傳輸狀態、螢幕常亮、離開畫面示警等**跨路由共用**的機制在本 Issue 一次建好，讓 Issue 2／3 只需要專注各自的路由邏輯。

**What to build：**
- `network_availability.dart`：`NetworkAvailabilityKind`／`NetworkInterfaceCandidate`／`NetworkAvailability`／`CheckNetworkAvailability` 型別；`checkNetworkAvailability()` 分層判定（`connectivity_plus` 判斷 WiFi 客戶端 → 否則 `NetworkInterface.list()` 列舉＋轉呼叫純函式）；過濾＋IP 挑選邏輯獨立成可測的純函式 `NetworkAvailability classifyNetworkInterfaces(List<NetworkInterfaceCandidate> raw)`（**`/receiving-code-review` 第二輪審查修正**：簽章由原訂只回傳 `NetworkAvailabilityKind` 改為回傳完整 `NetworkAvailability`，因為測試需要一併驗證挑選出的 `ipAddress` 與 `allCandidates`）。
- **`wifi_transfer_service.dart`：`WifiTransferService` 類別骨架**（**`/receiving-code-review` 第二輪審查修正，原本遺漏**：`wifi_transfer_http_server.dart` 建構子強制吃 `required WifiTransferService service`，沒有這個骨架 Issue 1 會編譯不過）——完整欄位宣告與建構子（`libraryRepository`／`importService`／`computeFingerprint`／`materializeContentUri`／`deleteFile`），三個業務方法（`listDownloadableBooks`／`resolveDownloadSource`／`handleUploadedFile`）先宣告簽章、方法體 `throw UnimplementedError()`，留給 Issue 2／3 分別填入。
- `wifi_transfer_http_server.dart`：`WifiTransferHttpServer` 類別——`start()`／`stop()`（bind `InternetAddress.anyIPv4`，`ipAddress` 僅供顯示；port 先試固定值失敗才 `port: 0`）、併發節流計數號誌（`maxConcurrentTransfers` 預設 2）、`activeTransfersNotifier`（`ValueListenable<int>`）、`GET /` 路由（`rootBundle.loadString('assets/wifi_transfer/index.html')` 回應）；`/api/books`／`/api/books/<id>/download`／`/api/upload` 先回 501，交由 Issue 2／3 補上。
- `assets/wifi_transfer/index.html`：單一自我完備 HTML 檔案骨架（無外部資源），`pubspec.yaml` 宣告為 asset；上傳/下載區塊的實際 JS 邏輯可先留白或顯示「開發中」，Issue 2／3 補上。
- `wifi_transfer_dependencies.dart`：`WifiTransferDependencies` bundle（`libraryRepository`／`importService`／`computeFingerprint`／`checkNetworkAvailability`，皆 nullable）。
- `WifiTransferScreen`：顯示 `checkNetworkAvailability()` 結果——`wifiClient`/`hotspot` 顯示 IP 文字＋QR Code（`Key('wifi_transfer_ip_text')`／`Key('wifi_transfer_qr_code')`）；`unavailable` 停用並顯示「我確定目前是用手機熱點」手動覆寫按鈕（按下後列出 `allCandidates`）；`initState()`/`dispose()` 呼叫 `WakelockPlus.enable()`/`disable()`；`PopScope` 讀 `activeTransfersNotifier.value > 0` 決定是否跳確認對話框；建構子新增 `@visibleForTesting final ValueListenable<int>? activeTransfersNotifierOverride`（**`/receiving-code-review` 第二輪審查修正，原本遺漏**：非 `null` 時直接用它驅動 `PopScope`、不啟動真實伺服器，供 widget test 注入可控 `ValueNotifier<int>`；生產環境不傳，走真實伺服器的 `activeTransfersNotifier`）。
- **裝配串接**（**`/receiving-code-review` 第二輪審查修正，原本遺漏**：查證 `SourcesHomeScreen` 的依賴一律經 `AdaptiveShellScaffold` 從 `main.dart` 三層轉傳，只改 `SourcesHomeScreen` 本身，正式環境永遠拿不到非 `null` 依賴，入口實質永久隱藏）：`AdaptiveShellScaffold` 新增建構參數 `WifiTransferDependencies? wifiTransferDependencies`（預設 `null`），建構 `SourcesHomeScreen` 時原樣往下傳；`main.dart` 組裝生產環境的 `WifiTransferDependencies` 並傳給 `AdaptiveShellScaffold`。
- `SourcesHomeScreen`「本機」分區新增入口卡片（`Key('sources_wifi_transfer_tile')`，圖示 `Icons.wifi`），`WifiTransferDependencies` 任一必要欄位為 `null` 時不顯示。

**單元測試要求：**
- `classifyNetworkInterfaces()`：純函式單元測試，餵入假網路介面清單（純 WiFi、純蜂巢式、蜂巢式+熱點混合、全空）驗證回傳的 `kind`／`ipAddress`／`allCandidates` 皆正確，不觸碰真實 `NetworkInterface.list()`/`Connectivity()`。
- `WifiTransferScreen` widget test：注入假 `CheckNetworkAvailability` 分別回傳 `wifiClient`/`hotspot`/`unavailable` 三種情境，驗證 IP/QR 顯示、停用文案、手動覆寫按鈕與 `allCandidates` 清單渲染；透過 `activeTransfersNotifierOverride` 注入的 `ValueNotifier<int>` 設為正整數時驗證觸發 `PopScope` 示警對話框，設回 0 時驗證正常放行離開。
- `SourcesHomeScreen` widget test：`WifiTransferDependencies` 為 `null`／非 `null` 兩種情境下入口卡片的顯示/隱藏。
- `AdaptiveShellScaffold` widget test：`wifiTransferDependencies` 正確原樣傳遞給內部 `SourcesHomeScreen`。
- `integration_test/`：真機驗證伺服器真的能綁定 socket、PC 瀏覽器（或另一支裝置的瀏覽器）連線 `GET /` 能取得首頁 HTML。

**驗收標準：** 使用者可從「來源」畫面點開 WiFi 傳書，看到 IP/QR Code；同一 WiFi 下的瀏覽器連得上首頁；沒有 WiFi/熱點時功能停用並可手動覆寫；離開畫面時（模擬有傳輸中）跳出確認對話框；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

---

## Issue 2：下載功能

**Status:** completed（**2026-09-18 已完成並合併回 `main`（PR [#258](https://git.jigong.org/huthief/elinkBook/pulls/258)，分支 `feat/epic-44-issue-2`）**：`plans/plan-issue-2.md` 10 個 Task 全數完成——`WifiTransferService.listDownloadableBooks()`／`resolveDownloadSource()` 兩個純邏輯方法實作、`WifiTransferHttpServer.withTransferPermit()` 內部重構為 `_acquirePermit()`／`_releasePermit()`（讓併發許可持有到下載串流真正結束才釋放，而非 `Response` 物件建構完成的當下）、新增 `wrapStreamWithCleanup()` 純函式（正確轉發下游背壓、`onDone`/`onError`/`onCancel` 三路徑皆恰好清理一次）、新增 `buildContentDispositionHeader()` 純函式（RFC 5987/6266，含 HTTP header injection 防護）、`GET /api/books`／`GET /api/books/<id>/download` 兩條路由、`assets/wifi_transfer/index.html` 下載區塊 JS、`integration_test/wifi_transfer_screen_test.dart` 新增 5 個真機測試。獨立程式審查（`reviews/review-issue-2.md`）：0 Critical／1 Important（測試覆蓋面：缺少「兩個真實並發下載請求」直接驗證節流生效的端對端測試，不影響程式碼正確性判斷）／3 Minor（清單 `format` 欄位與 TXT/MD 誠實下載檔名不一致、一個已定案的極窄 TOCTOU→500 取捨、無 HTTP Range 續傳支援），結論 Ready to merge: Yes。`flutter analyze`（No issues found）／`test/wifi_transfer/` 48 個測試全數通過／完整 `flutter test`（2587 passed / 1 skipped / 2 failed，2 個失敗經比對為既存缺陷，非本 Issue 引入的回歸）皆為綠燈；真機 `integration_test` 因審查環境無裝置未能獨立驗證，僅審查程式邏輯合理性。）

**依賴：** Issue 0（`findBookById`／修正後的 `readContentUriAll`）、Issue 1（`WifiTransferHttpServer`／`WifiTransferService` 骨架、併發號誌、首頁）。

**背景：** `spec.md`「`wifi_transfer_service.dart`」「HTTP 路由表」`GET /api/books`／`GET /api/books/<id>/download` 兩條路由已定案介面。與 Issue 3（上傳）互相獨立，可平行進行。

**What to build：**
- `WifiTransferService.listDownloadableBooks()`：**（`/receiving-code-review` 第二輪審查修正，C-1：上一版誤寫成透過 `findBookById` 列全部書，邏輯上不可能——`findBookById` 是單筆查詢，列全部書只能查整庫）** 呼叫 `libraryRepository.listBooks()` 並過濾 `isDownloaded == true`；`DownloadableBook.sizeBytes` 僅對非 `content://` 路徑、且 `await file.exists()` 為真時才呼叫 `File(filePath).length()`（**第二輪審查修正，M-4**：書籍記錄可能因使用者手動搬移/刪除本機檔案而失效，直接呼叫 `.length()` 會拋例外打斷整個清單查詢），`content://` 或檔案不存在時 `sizeBytes` 恆為 `null`（清單階段嚴禁觸發材質化）。
- `WifiTransferService.resolveDownloadSource(bookId)`：**（`/receiving-code-review` 第二輪審查修正，C-1：上一版遺漏這裡才是真正該呼叫 `findBookById` 的地方）** 先呼叫 `libraryRepository.findBookById(bookId)`；找不到或 `!isDownloaded` 回傳 `null`。找到後：`content://` 書籍呼叫（Issue 0 修正後的）`readContentUriAll` 材質化為暫存檔；TXT/MD 來源書籍的 `downloadFileName` 改寫為 `.epub`；材質化失敗（回傳 `null`）時整體回傳 `null`。
- `GET /api/books` 路由：回傳 JSON 陣列 `[{id, title, format, sizeBytes}]`。
- `GET /api/books/<id>/download` 路由：取得許可（沿用 Issue 1 的併發號誌）→ `resolveDownloadSource()`；找不到／材質化失敗回 404／500；成功則 `Content-Disposition` 依 RFC 5987/6266 處理中文檔名＋正確 `Content-Length`；`isTemporaryFile == true` 時把 `file.openRead()` 包裝成轉接 `Stream`，在 `onDone`（EOF）／`onError`（讀取例外）**／`onCancel`（客戶端中途取消下載或斷線——第二輪審查修正 I-3：底層是下游訂閱被 `cancel()`，不會觸發 `onDone`/`onError`，大檔案下載中途取消是常見情境，漏掉這個分支會讓暫存檔永久殘留）**三個回呼皆非同步刪除暫存檔（用旗標確保只清理一次），不可在回傳 `Response` 當下立即清理。
- `assets/wifi_transfer/index.html` 補上下載區塊 JS：頁面載入 `fetch('/api/books')` 渲染勾選清單；勾選後**依序**（`for...of`+`await`）建立 `<a download>` 並程式化點擊觸發下載。

**單元測試要求：**
- `WifiTransferService` 純 Dart 測試：注入假 `LibraryRepository`（含 `content://`、本機路徑、與「記錄存在但檔案已不存在」三種 `filePath` 情境）／假 `materializeContentUri`，驗證 `listDownloadableBooks()` 排除 `isDownloaded == false` 的書、`content://` 與檔案不存在兩種情境 `sizeBytes` 皆為 `null`；`resolveDownloadSource()` 對找不到的 `bookId`／`!isDownloaded` 回傳 `null`、對 TXT/MD 來源書籍正確改寫 `.epub` 副檔名、材質化失敗時回傳 `null`（驗證確實有呼叫 `findBookById`，而非誤用其他查詢方法）。
- 下載串流清理的純 Dart 測試：模擬來源 stream 分別觸發 `onDone`／`onError`／訂閱被 `cancel()` 三種情境，驗證 `deleteFile` 恰好被呼叫一次。
- `integration_test/`：真機下載一本本機路徑來源的書、一本 `content://` 來源的書、一本 TXT 來源的書，驗證取得的位元組正確、檔名正確（含中文書名）、暫存檔在下載完成後確實被清理；下載中途手動取消一次，驗證暫存檔同樣被清理。

**驗收標準：** PC 瀏覽器打開 WiFi 傳書頁面，能看到書架清單（僅含已下載書籍）並成功下載，含 `content://` 來源與 TXT/MD 誠實改名兩種情境；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 1。

---

## Issue 3：上傳功能

**Status:** completed（**2026-09-18 已完成並合併回 `main`（PR [#259](https://git.jigong.org/huthief/elinkBook/pulls/259)，分支 `feat/epic-44-issue-3`）**：`plans/plan-issue-3.md` 6 個 Task 全數完成——`WifiTransferService.handleUploadedFile()` 實作（算指紋 → 查重複 → 匯入或清理，包含例外安全的 `safeDelete()` 包裝）、`bookFileFormatForFileName()` 純函式反查白名單副檔名、`POST /api/upload` 路由（`shelf_multipart` 逐一解析 part，非白名單先以 `part.drain()` 耗盡串流避免阻塞後續解析，白名單檔名消毒並落地至持久目錄後調用服務處理）、`assets/wifi_transfer/index.html` 上傳區塊 JS（拖放區＋選檔、XHR 支援進度回報、逐檔狀態與完成自動刷新書籍列表）、`integration_test/wifi_transfer_screen_test.dart` 新增 3 個真機測試。獨立程式審查（`reviews/review-issue-3.md`）：0 Critical／0 Important／3 Minor，結論 Ready to merge: Yes。`flutter analyze` 乾淨、單元測試 56 個通過、真機測試通過。）

**依賴：** Issue 0（依賴引進、內容指紋既有機制）、Issue 1（`WifiTransferHttpServer`／`WifiTransferService` 骨架、併發號誌）。

**背景：** `spec.md`「`wifi_transfer_service.dart`」「HTTP 路由表」`POST /api/upload` 已定案介面。與 Issue 2（下載）互相獨立，可平行進行。

**What to build：**
- `WifiTransferService.handleUploadedFile()`：對落地檔案算內容指紋 → 查 `findByContentFingerprint()`，命中則刪除落地檔案並回傳 `duplicateSkipped`；沒命中呼叫 `importService.importFiles([landedPath], displayNames: [originalFileName])`，檢查 `result.importedBooks.isEmpty`——是則刪除落地檔案並回傳 `failed`，否則回傳 `imported`；任何未預期例外同樣清理落地檔案並回傳 `failed`。
- `POST /api/upload` 路由：取得許可（沿用 Issue 1 的併發號誌）→ `shelf_multipart` 逐一解析檔案 part；副檔名不在白名單（`fileExtensionFor()` 反查）先 `await part.drain()` 耗盡串流才回傳該檔案 `unsupportedFormat`；在白名單則以 `p.basename(originalFileName)` 消毒＋附加唯一前綴落地到持久化 App 文件目錄，呼叫 `handleUploadedFile()`；回應 JSON 陣列 `[{originalFileName, outcome}]`。
- `assets/wifi_transfer/index.html` 補上上傳區塊 JS：`<input type="file" multiple>`＋拖放區。**（`/receiving-code-review` 第二輪審查修正，M-2：`fetch()` 原生不支援上傳進度事件，上一版寫法自相矛盾）** 一律用 `XMLHttpRequest`（`xhr.open('POST', '/api/upload')`＋`xhr.upload.onprogress` 顯示進度＋`xhr.send(formData)`），不使用 `fetch()`；依回應 JSON 逐檔顯示「已匯入／已存在已略過／格式不支援**／匯入失敗**」（**第二輪審查修正，M-3**：對應 `UploadOutcome` 四個值，上一版文案漏了 `failed`）。

**單元測試要求：**
- `WifiTransferService` 純 Dart 測試：注入假 `BookImportService`（分別模擬「成功匯入」「回傳空清單（損毀/空內容）」「拋例外」三種情境）／假 `computeFingerprint`／假 `findByContentFingerprint` 命中情境，驗證 `handleUploadedFile()` 三種情境皆正確清理落地檔案並回傳對應 `UploadOutcome`（`imported`／`duplicateSkipped`／`failed`）。
- `integration_test/`：真機上傳一個支援格式檔案（成功出現在圖書庫）、一個不支援格式檔案（被拒絕，`part.drain()` 後續 part 仍可正常解析）、重複上傳同一檔案兩次（第二次靜默略過、書架上只有一筆記錄）。

**驗收標準：** PC 瀏覽器拖曳上傳一個書籍檔案，成功出現在手機書架上；不支援格式被拒絕且不影響同一請求內其他檔案的解析；重複上傳同一檔案不會產生重複記錄；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 1。

---

## Issue 4：WiFi 傳書體驗強化（上傳狀態與進度、佈局重排、下載搜尋與分頁、手機端傳輸指示）

**Status:** ready-for-agent

**依賴：** Issue 1、Issue 2、Issue 3。

**背景：** 依使用者實際體驗回饋（2026-09-18 `/grill-me` 需求訪談收斂）：
1. **上傳功能版面位置偏下**：若手機內已有大量書籍，下載區塊會把上傳區塊推至畫面下方，進入網頁必須一直往下拉才看得到上傳區，應將「上傳區塊」移至網頁上方（下載區塊之上）。
2. **上傳缺乏即時進度與狀態提示**：大檔案上傳時僅有簡易進度條，無傳輸量/百分比；上傳完成進到手機處理匯入時進度條停留在 100%，缺乏轉圈動畫與「手機端處理匯入中」提示；且上傳期間未鎖定拖放區易造成重複觸發。
3. **下載書籍清單缺乏搜尋與分頁**：藏書數多時（數十至數百本），下拉尋找極耗時，需新增前端即時搜尋與 20 本/頁分頁機制，並具備跨頁勾選記憶與「全選目前頁」「清除勾選」快捷按鈕。
4. **手機端缺乏傳輸中狀態提示**：操作者在手機端畫面無法直觀得知是否有檔案正在傳輸，應於 QR Code 下方顯示動態傳輸狀態指示（進行中傳輸數 > 0 時顯示微型轉圈與提示文字）。

**What to build：**
1. **PC 端網頁版面重整與上傳體驗增強（`assets/wifi_transfer/index.html`）**：
   - 將 `#upload-section` 調整至 `#download-section` 上方。
   - 上傳進度條增強：顯示傳輸大小與百分比文字（如 `12.5 MB / 28.0 MB (45%)`）。
   - 雙階段上傳狀態指示：位元組傳輸階段（`xhr.upload.onprogress`）顯示進度；傳輸完成進入後端處理階段時，顯示 CSS 轉圈動畫與「上傳完成，手機端處理匯入中，請稍候…」文字提示。
   - 上傳防呆：上傳期間暫時鎖定拖放區與選檔按鈕，避免重複觸發並發上傳。
   - 匯入結果列表與自動刷新：完成後顯示結果並刷新下方下載書籍列表。
2. **PC 端網頁下載清單搜尋與分頁（`assets/wifi_transfer/index.html`）**：
   - 即時搜尋框：位於清單上方，輸入關鍵字即時依書名（不分大小寫）過濾，顯示符合筆數（如 `符合 15 本 / 共 80 本`），清空搜尋重置。
   - 純前端分頁：每頁固定 20 本，提供「上一頁」「下一頁」與「第 X / Y 頁」控制項；搜尋關鍵字變更時重置至第 1 頁。
   - 跨頁記憶與批次工具列：使用記憶體 `Set` 保存選中的書籍 ID，換頁或過濾時不遺失勾選狀態；提供「全選目前頁」「清除勾選」快捷按鈕，即時顯示「已勾選 N 本書籍」。
3. **手機端傳輸狀態指示（`app/lib/screens/wifi_transfer_screen.dart`）**：
   - 於 QR Code 下方監聽 `_activeTransfersNotifier`。
   - 當 `activeCount > 0` 時，渲染狀態卡片／指示條（含小尺寸 `CircularProgressIndicator` 與 `正在傳輸中（N 個檔案）…`，帶有 `Key('wifi_transfer_active_transfers_banner')`）。
   - 當 `activeCount == 0` 時自動隱藏（`SizedBox.shrink()`）。

**單元／Widget 測試要求：**
- `wifi_transfer_screen_test.dart`（Widget 測試）：
  - 驗證 `activeTransfersNotifierOverride` 為 0 時，不顯示傳輸中指示條。
  - 驗證 `activeTransfersNotifierOverride` > 0（例如 2）時，正確顯示「正在傳輸中（2 個檔案）…」與進度指示。
- `wifi_transfer_http_server_test.dart`（單元測試）：
  - 驗證 `GET /` 回傳的 HTML 包含重整後的結構（`#upload-section` 在 `#download-section` 之前，包含搜尋框元素與分頁控制器元素）。
- 確保既有 56 個單元測試與所有 screen 測試零回歸。

**驗收標準：**
- 瀏覽器開啟 WiFi 傳書頁面，上傳區塊位於下載區塊上方。
- 上傳檔案時有明確進度百分比、大小、轉圈動畫與雙階段狀態提示，且上傳中鎖定防重複。
- 下載清單支援 20 本/頁分頁、書名即時搜尋、跨頁勾選記憶與全選目前頁/清除勾選快捷按鈕。
- 手機端畫面在傳輸時即時顯示傳輸檔案數指示條。
- `flutter analyze` 乾淨，所有測試通過。

**Blocked by：** Issue 1、Issue 2、Issue 3。
