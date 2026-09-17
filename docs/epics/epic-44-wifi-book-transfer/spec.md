# Epic 44 — WiFi 傳書：Architecting

自本文件起，`spec.md` 是本 Epic 的唯一事實來源（core 介面/型別以此為準，`design.md` 僅保留 Discovery 決策脈絡供追溯）。

## 已查證的關鍵技術事實

撰寫本文件前直接查證原始碼與套件，以下事實直接決定下方介面設計，非憑空假設：

1. **熱點偵測不需要新增原生 Kotlin 程式碼**——`design.md`「依賴事實」原本寫「或需要額外原生 platform channel 讀取網路介面」，查證後推翻：`dart:io` 的 `NetworkInterface.list()` 是純 Dart 標準函式庫 API（非 Android 隱藏 API），可直接列舉裝置所有網路介面與其 IP，不需要任何 `MethodChannel`。
2. **`content://` 材質化重用既有 `ReaderResourceChannel.kt`**：其 `readContentUriAll`（channel `elinkbook/reader_resources`）已經是「給定 `content://` URI，串流複製到 App 快取目錄暫存檔、回傳暫存檔路徑」的通用實作（原為 PDF 而寫，但邏輯與格式無關——暫存檔內部命名固定用 `.pdf`，這只是內部快取檔名，不影響我們之後要回給 PC 的真實檔名，見下方下載路由設計），下載功能可直接呼叫，不需要新增原生方法。**Dart 端已有現成、可覆寫的頂層函式變數**（`app/lib/search/pdf_content_indexer.dart:101` 的 `Future<String?> Function(String uri) readContentUriAll`，`sqlite_library_repository.dart` 已在跨模組重用），直接重用它，不要另外宣告簽章不同的欄位。
   - **（`/receiving-code-review` 審查修正，2026-09-17）ANR 風險**：查證 `PdfReaderView`／`pdf_content_indexer.dart` 呼叫 `readContentUriAll` 時使用的是主執行緒 channel `elinkbook/reader_resources`，不是有背景佇列的 `elinkbook/reader_resources_cache`——`ReaderResourceChannel.kt` 自己的既有註解就明講同步複製在主執行緒跑會阻塞 UI、觸發 ANR watchdog。這個風險原本就存在於既有 PDF 開書路徑，WiFi 下載會讓它更常被觸發，一併修正（見下方「共用檔案異動」）。
3. **`shelf_multipart`（pub.dev 2.0.0）** 提供 `request.multipart()`／`shelf_multipart/form_data.dart` 兩種 API 可解析 `multipart/form-data` 上傳請求，是 `shelf` 生態圈的標準做法，不需要自己手刻 multipart parser。
4. **`qr_flutter`** 明確標榜「no internet connection required」（純本機算圖產生 QR Code），符合手機熱點分享時可能沒有對外網路的情境。
5. `BookFileFormat` → 副檔名字串已有共用函式 `fileExtensionFor()`（`app/lib/remote/opds_client.dart:33`），下載/上傳的格式白名單與檔名處理直接複用，不重新發明。
6. `computeBookContentFingerprint(filePath, format)` 對非 `content://` 的本機路徑走 `Isolate.run()` + `package:crypto` 串流雜湊（`app/lib/library/book_content_fingerprint.dart:47`）；WiFi 上傳落地後的檔案必然是純本機路徑（我們自己寫入，不是 `content://`），直接呼叫即可，不需要额外處理 `content://` 分支。
7. `AndroidManifest.xml` 已宣告 `INTERNET`／`WAKE_LOCK`；`ACCESS_NETWORK_STATE`／`ACCESS_WIFI_STATE` 未見於本專案自身宣告，預期由 `connectivity_plus` 的 AAR manifest merge 自動帶入——真機測試時需確認 `NetworkInterface.list()` 在未額外宣告這兩個權限的情況下是否正常運作（過去在多數 Android 版本上此 API 不需要額外執行期權限，但列為本 Epic 第一個 Issue 的真機驗證項目，非本文件憑空斷定）。

## 新增依賴（`pubspec.yaml` 正式 `dependencies`）

| 套件 | 用途 |
|---|---|
| `shelf` | 本機 HTTP Server 框架（官方 Dart 團隊維護，路由/中介層皆用其標準機制，不手刻 socket 處理） |
| `shelf_multipart` | 解析上傳的 `multipart/form-data` 請求 |
| `qr_flutter` | 畫面上算圖顯示連線用 QR Code（純本機，不需網路） |
| `wakelock_plus` | **（`/receiving-code-review` 審查修正，2026-09-17）** `design.md`「前景執行穩健度」承諾的 `FLAG_KEEP_SCREEN_ON` 螢幕常亮，原本漏列進依賴清單。純 Flutter plugin，不需要額外原生程式碼 |

## 模組佈局

```
app/lib/wifi_transfer/
├── network_availability.dart      # NetworkAvailability 型別 + 真實偵測邏輯（純 Dart，不含 UI）
├── wifi_transfer_service.dart     # 純邏輯層：上傳落地/去重/匯入、下載清單/串流來源解析（可注入依賴，flutter test 可測）
├── wifi_transfer_http_server.dart # shelf 路由/HTTP 轉譯薄殼層（綁定真實 socket，僅 integration_test 驗證）
└── wifi_transfer_dependencies.dart # SourcesHomeScreen 依賴注入 bundle（比照既有 LibraryXxxDependencies 慣例）

app/lib/screens/
└── wifi_transfer_screen.dart      # 「WiFi 傳書」畫面（IP/QR 顯示、熱點手動覆寫、上傳結果/下載清單 UI）

assets/wifi_transfer/
└── index.html                     # PC 端網頁，HTML/CSS/JS 全部內嵌單一檔案，pubspec.yaml 宣告為 asset
```

沿用既有慣例，不新增 SQLite schema（`design.md`「範圍界定」已定案 WiFi 傳書不影響 `BookSource`/資料模型）。

## 核心型別

### `network_availability.dart`

```dart
enum NetworkAvailabilityKind { wifiClient, hotspot, unavailable }

/// 一個偵測到的網路介面候選項，供「手動覆寫」UI 列出所有介面供使用者
/// 自行挑選（見下方 unavailable 情境說明）。
class NetworkInterfaceCandidate {
  final String interfaceName;
  final String ipAddress;
  const NetworkInterfaceCandidate({required this.interfaceName, required this.ipAddress});
}

class NetworkAvailability {
  final NetworkAvailabilityKind kind;
  /// kind != unavailable 時，建議直接使用的局域網 IP。
  final String? ipAddress;
  /// 一律回傳目前列舉到的所有網路介面（含被黑名單排除的），即使
  /// kind == unavailable 也會有值——供「我確定目前是用手機熱點」手動
  /// 覆寫 UI 列出全部候選項供使用者自行挑選，不需要偵測邏輯本身
  /// 做到 100% 準確。
  final List<NetworkInterfaceCandidate> allCandidates;

  const NetworkAvailability({
    required this.kind,
    this.ipAddress,
    this.allCandidates = const [],
  });
}

typedef CheckNetworkAvailability = Future<NetworkAvailability> Function();

/// 生產環境實作（`main.dart` 組裝）。分層判定（design.md「網路先決條件」）：
/// 1. `connectivity_plus` 判斷已連到別人的 WiFi → 找 `wlan0`-類介面的 IP，kind = wifiClient。
/// 2. 否則列舉 `NetworkInterface.list()`，用蜂巢式介面名稱黑名單
///    （`rmnet*`/`ccmni*`/`pdp*` 等）與 VPN 介面黑名單（`tun*`/`ppp*`）
///    過濾；剩餘介面中若有私有網段 IP（非電信），kind = hotspot、
///    取第一個作為 ipAddress。
/// 3. 過濾後空無一物 → kind = unavailable，ipAddress 為 null，但
///    allCandidates 仍列出全部原始介面（含被濾掉的）。
Future<NetworkAvailability> checkNetworkAvailability() async { /* ... */ }
```

`WifiTransferScreen` 的畫面邏輯：
- `kind == wifiClient || kind == hotspot` → 直接用 `ipAddress` 啟動伺服器、顯示網址＋QR Code。
- `kind == unavailable` → 停用功能＋提示「請連線至 WiFi 或開啟手機熱點」＋一顆「我確定目前是用手機熱點」按鈕；按下後改列出 `allCandidates` 讓使用者手動挑選要用哪個 IP（`allCandidates` 為空清單時提示「找不到任何可用網路介面」，不提供選項）。

### `LibraryRepository` 異動

**（`/receiving-code-review` 審查修正，2026-09-17）** 查證現有介面（`app/lib/library/library_repository.dart`）只有 `listBooks()`／`findByRemoteBookId()`／`findByContentFingerprint()`／`findByCloudFileId()` 等，**沒有依 `id` 查單筆的方法**——`resolveDownloadSource(bookId)` 需要單書查詢，若靠 `listBooks()` 在記憶體中過濾，藏書量大時每次 PC 端請求下載都要整庫查詢、建立大量物件。新增抽象方法：

```dart
Future<Book?> findBookById(String id);
```

`SqliteLibraryRepository` 對應實作 `SELECT * FROM books WHERE id = ?` 單筆查詢。純 Repository 介面擴充，不變更 SQLite schema。

### `wifi_transfer_service.dart`（可測試核心邏輯，不碰真實 socket）

```dart
enum UploadOutcome { imported, duplicateSkipped, unsupportedFormat, failed }

class UploadResult {
  final String originalFileName;
  final UploadOutcome outcome;
  const UploadResult({required this.originalFileName, required this.outcome});
}

class DownloadableBook {
  final String id;
  final String title;
  final BookFileFormat format;
  /// **（`/receiving-code-review` 審查修正，2026-09-17）** 僅對非
  /// `content://` 的本機實體檔案呼叫 `File(filePath).length()`；書籍
  /// `filePath` 為 `content://` URI 時恆為 `null`——`File` 無法直接對
  /// `content://` 取得大小，且清單建立階段**嚴禁**呼叫
  /// `materializeContentUri` 觸發材質化（那會讓瀏覽清單時就把整個書架
  /// 複製一份到快取目錄，塞爆手機儲存空間）。
  final int? sizeBytes;
  const DownloadableBook({required this.id, required this.title, required this.format, this.sizeBytes});
}

/// 下載時實際要串流的來源資訊：resolvedPath 一律是可直接
/// File.openRead() 的本機路徑（content:// 已由呼叫端材質化為暫存檔）；
/// downloadFileName 已套用「TXT/MD 來源書籍誠實回傳 .epub」規則。
class DownloadSource {
  final String resolvedPath;
  final String downloadFileName;
  final bool isTemporaryFile; // true 時，HTTP 回應完成/斷線後呼叫端須刪除 resolvedPath
  const DownloadSource({
    required this.resolvedPath,
    required this.downloadFileName,
    required this.isTemporaryFile,
  });
}

/// 純邏輯層，建構子全部依賴皆可注入假實作，供 `flutter test` 驗證
/// 業務規則（格式白名單、去重、下載清單過濾）而不需要真實 sqflite/
/// 原生呼叫/socket。比照 `RemoteCatalogDependencies`／
/// `ComputeRemoteFingerprint` 既有的依賴注入慣例。
class WifiTransferService {
  final LibraryRepository libraryRepository;
  final BookImportService importService;
  final ComputeRemoteFingerprint computeFingerprint; // 型別沿用既有 typedef，語意相容
  /// **（`/receiving-code-review` 審查修正，2026-09-17）** 型別改為可空
  /// 回傳，比照既有 `pdf_content_indexer.dart:101` 的
  /// `readContentUriAll` 頂層函式變數簽章（生產環境直接重用該函式，
  /// 不另外宣告新函式）；材質化失敗（SAF 授權過期、空間不足）時回傳
  /// `null`，`resolveDownloadSource` 對應回傳 `null`（路由層回 500）。
  final Future<String?> Function(String contentUri) materializeContentUri;
  final Future<void> Function(String path) deleteFile;

  const WifiTransferService({
    required this.libraryRepository,
    required this.importService,
    required this.computeFingerprint,
    required this.materializeContentUri,
    required this.deleteFile,
  });

  /// 對應「上傳位元組落地路徑」＋「重複匯入偵測」決策：呼叫端已把上傳
  /// 位元組寫入持久化目錄的 [landedPath]（副檔名已通過白名單檢查，
  /// 不通過的呼叫端直接回傳 unsupportedFormat、不呼叫本方法；[landedPath]
  /// 的檔名本身已由呼叫端用 `p.basename(originalFileName)` 消毒＋附加
  /// 唯一前綴，[originalFileName] 只用於顯示，見「HTTP 路由表」M-1 說明）。
  /// 內部依序：算指紋 → 查 findByContentFingerprint → 命中則刪除
  /// landedPath 並回傳 duplicateSkipped；沒命中才呼叫
  /// importService.importFiles([landedPath], displayNames: [originalFileName])。
  ///
  /// **（`/receiving-code-review` 審查修正，2026-09-17）** 查證
  /// `_importSingleFile()` 對損毀/空內容檔案（`EmptyTxtException`／
  /// `DrmProtectedException`／`NoComicPagesException`／`EmptyMdException`）
  /// 一律回傳 `null`、不拋例外，`importFiles()` 因此回傳空的
  /// `importedBooks` 清單、沒有任何錯誤訊號——原設計未檢查這個結果，
  /// 會讓 PC 端看到「已匯入」但書架上其實沒這本書，且 [landedPath] 永久
  /// 殘留成孤兒檔案。修正：呼叫 `importFiles()` 後檢查
  /// `result.importedBooks.isEmpty`，是則刪除 [landedPath]、回傳
  /// `failed`；任何未預期例外（`catch`）同樣須刪除 [landedPath] 並回傳
  /// `failed`，不可讓例外冒出中斷整個上傳請求。
  Future<UploadResult> handleUploadedFile({
    required String landedPath,
    required String originalFileName,
    required BookFileFormat format,
  }) async { /* ... */ }

  /// 對應「下載清單僅列出 isDownloaded == true」決策。透過
  /// `LibraryRepository.findBookById()`（見下方 I-2 新增方法）取單筆
  /// 記錄，不對整庫 `listBooks()` 做記憶體過濾。
  Future<List<DownloadableBook>> listDownloadableBooks() async { /* ... */ }

  /// 對應「content:// 下載」＋「TXT/MD 來源書籍誠實回傳 .epub」決策。
  /// bookId 找不到、isDownloaded == false，或 `content://` 材質化失敗
  /// （`materializeContentUri` 回傳 null）時回傳 null（呼叫端回 404／500）。
  Future<DownloadSource?> resolveDownloadSource(String bookId) async { /* ... */ }
}
```

### `wifi_transfer_http_server.dart`（薄殼層，僅 `integration_test` 驗證）

```dart
class WifiTransferHttpServer {
  final WifiTransferService service;
  final int maxConcurrentTransfers; // 併發節流上限，預設 2（見下方「併發節流實作」）

  /// **（`/receiving-code-review` 審查修正，2026-09-17）** 目前活躍中的
  /// 上傳/下載請求數（進入 handler 傳輸邏輯時 +1、結束/例外時 -1），供
  /// `WifiTransferScreen` 的 `PopScope` 判斷「離開畫面時是否有傳輸進行
  /// 中」——`design.md`「功能形狀與入口」承諾的離開畫面示警對話框，原本
  /// 沒有任何機制能讓 UI 層知道目前是否有傳輸中，此為缺漏的狀態暴露。
  final ValueListenable<int> activeTransfersNotifier;

  WifiTransferHttpServer({
    required this.service,
    this.maxConcurrentTransfers = 2,
  });

  /// **（`/receiving-code-review` 審查修正，2026-09-17）** 實際 bind 一律
  /// 用 `InternetAddress.anyIPv4`（`0.0.0.0`），不直接 bind
  /// [ipAddress] 本身——部分客製化 Android 系統對熱點虛擬網卡 IP 執行
  /// socket bind 容易遇到 `EADDRNOTAVAIL`；[ipAddress] 只用於呼叫端組
  /// 顯示網址／QR Code，與實際監聽位址脫鉤，更具強韌性。
  /// [port] 為 0 時系統動態分配，回傳實際監聽的 shelf HttpServer（呼叫端
  /// 讀取 `.port` 取得真實埠號）。port 選擇策略（design.md「依賴事實」）：
  /// 呼叫端先試固定埠（如 8080），若 bind 拋 SocketException（埠號衝突）
  /// 再以 port: 0 重試。
  Future<HttpServer> start({required String ipAddress, required int port}) async { /* ... */ }

  Future<void> stop(HttpServer server) => server.close(force: true);
}
```

## HTTP 路由表

| Method | Path | 說明 |
|---|---|---|
| `GET` | `/` | 回傳 `assets/wifi_transfer/index.html`（`rootBundle.loadString()` 讀取，`Content-Type: text/html; charset=utf-8`），全站唯一頁面 |
| `GET` | `/api/books` | `WifiTransferService.listDownloadableBooks()` → JSON 陣列 `[{id, title, format, sizeBytes}]` |
| `GET` | `/api/books/<id>/download` | `resolveDownloadSource(id)`；找不到回 404；成功則以 `Content-Disposition: attachment; filename="fallback.epub"; filename*=UTF-8''<percent-encoded>`（RFC 5987/6266）＋正確 `Content-Length` 串流檔案；`isTemporaryFile == true` 時暫存檔清理見下方「I-1 暫存檔清理時機」 |
| `POST` | `/api/upload` | `shelf_multipart` 解析各個檔案 part；逐檔案：副檔名不在白名單 → **先 `await part.drain()` 耗盡該 part 的位元組串流，再**回傳該檔案 `unsupportedFormat`（見下方「M-2」）；在白名單則以 `p.basename(originalFileName)` 消毒＋附加唯一前綴（例如 `${DateTime.now().microsecondsSinceEpoch}_${p.basename(originalFileName)}`，見下方「M-1」）落地到持久化目錄後呼叫 `handleUploadedFile()`；回應 JSON 陣列 `[{originalFileName, outcome}]`，PC 端網頁依此更新結果清單 |

**併發節流實作**：`WifiTransferHttpServer` 內部維護一個計數號誌（counting semaphore，上限 `maxConcurrentTransfers`），`/api/books/<id>/download` 與 `/api/upload` 的 handler 進入實際傳輸邏輯前先 `await` 取得許可、結束後釋放（同時更新上方 `activeTransfersNotifier`）——超額請求會在 handler 內部等待而非立即回覆錯誤，PC 端瀏覽器體感是「傳輸稍晚開始」而非跳出錯誤訊息，符合專案「零意外」原則。初始上限定為 2，具體數字留待真機測試（低階 E-Ink 裝置）調校，非本文件鎖死。

**（`/receiving-code-review` 審查修正，2026-09-17）I-1 暫存檔清理時機**：`shelf` 的 `Response` 沒有內建「串流真正傳輸完成」回呼，若在回傳 `Response.ok(file.openRead(), ...)` 之後立即或同步呼叫 `deleteFile()`，暫存檔會在客戶端仍在讀取串流中途被刪除（回應 0 位元組或 `FileSystemException`）。必須把 `file.openRead()` 包裝成一個轉接 `Stream`，在其 `onDone`／`onError` 回呼（串流真正 EOF 或客戶端 RST 斷線時才會觸發）內非同步呼叫 `deleteFile(resolvedPath)`，不可在 handler 回傳 `Response` 的當下直接清理。

**（`/receiving-code-review` 審查修正，2026-09-17）M-1 上傳檔名消毒**：`originalFileName` 來自客戶端、不可信任，若夾帶 `../` 直接與落地目錄路徑拼接可能造成路徑穿越寫到目錄外的檔案。落地檔名一律用 `p.basename(originalFileName)` 取檔名部分＋附加唯一前綴（避免同名檔案互相覆蓋），原始檔名只透過 `importFiles()` 的 `displayNames` 參數保留供顯示，不參與實體路徑組裝。

**（`/receiving-code-review` 審查修正，2026-09-17）M-2 未消費 part 導致串流阻塞**：`shelf_multipart` 底層是單一 TCP 串流依序切出多個 part，若遇到格式不在白名單的檔案就直接 `continue` 跳過、不讀取該 part 剩餘位元組，解析器無法定位下一個 part 的邊界，會讓整個上傳請求卡死。遇到不支援格式時必須先 `await part.drain()` 耗盡該 part 的串流，才能繼續處理下一個 part 或結束請求。

## PC 端網頁（`assets/wifi_transfer/index.html`）

單一自我完備的 HTML 檔案，`<style>`／`<script>` 皆內嵌，不引用任何外部資源：

- 上傳區：`<input type="file" multiple>` + 拖放區，JS 用 `fetch('/api/upload', {method:'POST', body: formData})`，`XMLHttpRequest.upload.onprogress` 顯示上傳進度（原生瀏覽器 API，不需額外套件）；結果依伺服器回應的 JSON 陣列逐檔顯示「已匯入／已存在已略過／格式不支援」。
- 下載區：頁面載入時 `fetch('/api/books')` 取得清單渲染成勾選清單；使用者勾選後，JS **依序**（`for...of` + `await` 逐一觸發，符合「併發節流」對 PC 端的要求）對每本書建立 `<a href="/api/books/<id>/download" download>` 並程式化點擊，下載進度交由瀏覽器原生下載列顯示（`Content-Length` 已正確設定）。

## `WifiTransferScreen` 畫面邏輯

**（`/receiving-code-review` 審查修正，2026-09-17，補齊原本遺漏的畫面規格）**

- **入口位置**：`SourcesHomeScreen`「本機」分區新增第三張卡片（本機檔案/資料夾選擇之後），圖示 `Icons.wifi`，`WifiTransferDependencies` 任一必要欄位為 `null` 時不顯示此卡片（比照既有 Google Drive／OneDrive／遠端書庫入口的既定顯示規則）。
- **Widget Key**（供 widget test 使用）：`Key('sources_wifi_transfer_tile')`（入口卡片）、`Key('wifi_transfer_ip_text')`（顯示的網址文字）、`Key('wifi_transfer_qr_code')`（QR Code widget）。
- **離開畫面示警**（對應 I-4）：`PopScope` 的 `canPop` 讀取 `WifiTransferHttpServer.activeTransfersNotifier.value > 0`；大於 0 時攔截返回、跳確認對話框「目前尚有檔案正在傳輸，離開將中斷連線，是否確定離開？」，使用者確認才真正 `stop()` 伺服器並離開。
- **螢幕常亮**（對應 I-5）：`initState()` 呼叫 `WakelockPlus.enable()`，`dispose()` 呼叫 `WakelockPlus.disable()`，疊加在既有「勿切換 App」文字提示之上（design.md「前景執行穩健度」）。

## 依賴注入收斂（`wifi_transfer_dependencies.dart`）

比照 `LibraryCloudAccountDependencies`／`LibraryRemoteLibraryDependencies` 既有慣例，全部欄位皆可為 `null`（`null` 時「來源」畫面不顯示「WiFi 傳書」入口）：

```dart
@immutable
class WifiTransferDependencies {
  final LibraryRepository? libraryRepository;
  final BookImportService? importService;
  final ComputeRemoteFingerprint? computeFingerprint;
  final CheckNetworkAvailability? checkNetworkAvailability;

  const WifiTransferDependencies({
    this.libraryRepository,
    this.importService,
    this.computeFingerprint,
    this.checkNetworkAvailability,
  });
}
```

`materializeContentUri`／`deleteFile` 不進這個 bundle——兩者是純技術轉接（`ReaderResourceChannel` 呼叫、`dart:io` 檔案刪除），沒有「功能未啟用時為 null」的語意，直接在 `WifiTransferScreen` 內部以頂層函式呼叫，不需要呼叫端逐層注入（比照 `RemoteCatalogDependencies` 刻意排除 `computeFingerprint` 的先例：只收斂「呼叫端可能沒有」的依賴，不收斂「處處皆可用的既有機制」）。

## 共用檔案異動（Prefactor，2026-09-17 `/receiving-code-review` 審查修正）

**範圍確認：使用者已同意動共用檔案**（C-1 ANR 修正）。實際上這是**兩個既有 Dart 檔案各自的 channel 常數改名**，Kotlin 端 `ReaderResourceChannel.kt` 完全不需要修改——`readAndroidAsset`/`readCustomFontBytes`/`cacheBookForServing`/`readContentUriAll` 這組方法本來就由同一個 `onMethodCall()` 同時處理兩條 channel（`elinkbook/reader_resources` 主執行緒／`elinkbook/reader_resources_cache` 背景任務佇列），差別只在 Dart 端呼叫哪一個 channel 名稱：

- `app/lib/reader/pdf_reader_view.dart:277` 的 `_resourceChannel`（僅這一個呼叫點用它，見查證）：channel 名稱由 `elinkbook/reader_resources` 改為 `elinkbook/reader_resources_cache`。
- `app/lib/search/pdf_content_indexer.dart:94` 的 `_resourceChannel`（僅這一個呼叫點用它，見查證）：同樣改名。

對兩個既有呼叫端（`PdfReaderView._openContentUriDocument()`、`pdf_content_indexer.dart` 的背景索引）皆是透明變更——Dart 端本來就是 `await` 一個 `Future`，換到背景執行緒執行不影響呼叫方式或回傳值，只是原生端執行緒從主執行緒改為背景任務佇列，消除大檔案（100MB+ PDF／CBZ）複製時的 ANR 風險。這個 Prefactor 應排在 Scrum Master 拆出的 Issue 0（依賴引進／共用檔案修正），先於 WiFi 傳書自己的核心邏輯開發，讓 `WifiTransferService.materializeContentUri` 從一開始就注入這個已修正的版本。

## 測試 seam 設計

比照 CLAUDE.md「兩層測試架構」：

- `app/test/wifi_transfer/wifi_transfer_service_test.dart`：純 Dart `test()`，注入假 `LibraryRepository`／`BookImportService`／`computeFingerprint`／`materializeContentUri`，驗證上傳去重規則、下載清單過濾規則、TXT/MD 檔名改寫規則，不觸碰真實 sqflite 或 socket。
- `app/test/wifi_transfer/network_availability_test.dart`：`checkNetworkAvailability()` 內部呼叫 `NetworkInterface.list()`／`Connectivity()` 皆為平台相依，`flutter test` 環境不可靠——**改為只對「給定一組假網路介面清單，黑名單過濾邏輯是否正確分類」這個純函式部分做單元測試**（例如把過濾邏輯拆成 `NetworkAvailabilityKind _classify(List<NetworkInterfaceCandidate> raw)` 獨立可測的純函式，`checkNetworkAvailability()` 本身只負責呼叫平台 API 取得原始清單、轉呼叫 `_classify()`），比照 `OpdsClient`/`ComputeRemoteFingerprint` 既有「把平台相依部分縮到最小、邏輯部分獨立可測」的既定慣例。
- `app/integration_test/wifi_transfer_screen_test.dart`：**必須**在真實裝置上執行——驗證伺服器真的能綁定 socket、`GET /` 真的能取得 HTML、`POST /api/upload` 真的能收到 multipart 並讓書籍出現在圖書庫、下載真的能取得正確位元組（含 `content://` 來源與 TXT/MD 改名情境）。

## 更新 `design.md`「依賴事實」的解決狀態

- 熱點偵測技術手段：**已解決**（純 Dart `NetworkInterface.list()`，見上方「已查證的關鍵技術事實」#1）。
- PC 端網頁前端技術棧：**已解決**（單一內嵌 HTML 檔案，無框架、無外部資源，見上方「PC 端網頁」）。
- `.epub` 副檔名替換實作點：**已解決**（`Content-Disposition` 標頭層級處理，不複製重新命名暫存檔，見「HTTP 路由表」）。
- 本機 HTTP Server 套件、QR Code 套件：**已解決**（`shelf`／`qr_flutter`，見「新增依賴」）。
- 併發節流具體數字：**初始值已定（2），留待真機測試調校**，非封閉決定。
- 螢幕常亮（`FLAG_KEEP_SCREEN_ON`）具體套件：**已解決**（`wakelock_plus`，見「新增依賴」與「`WifiTransferScreen` 畫面邏輯」）。

## `review-spec.md` 審查後續（2026-09-17，`/receiving-code-review`）

審查結論 Changes Requested（2 Critical／5 Important／4 Minor）。逐項查證後**全部屬實，沒有需要反駁的發現**：

- **C-1（`readContentUriAll` 主執行緒 ANR＋型別不相容）**：查證屬實，且發現既有可直接重用的頂層函式（`pdf_content_indexer.dart:101`）。範圍已與使用者確認可以動共用檔案，修法是兩個既有呼叫點各自的 channel 名稱改動（見「共用檔案異動」），Kotlin 原生檔案不需修改。
- **C-2（上傳失敗孤兒檔案＋偽成功）**：查證屬實（`_importSingleFile` 對多種損毀/空內容例外回傳 `null` 且不拋例外），已補進 `handleUploadedFile` 文件註解明確要求檢查 `importedBooks.isEmpty`。
- **I-1（暫存檔清理時機）／I-2（`findBookById` 缺失）／I-3（`sizeBytes` 對 `content://` 的邊界）／I-4（活躍傳輸狀態未暴露）／I-5（`wakelock_plus` 未列依賴）**：查證皆屬實，已分別補進對應小節。
- **M-1（路徑穿越消毒）／M-2（未消費 part 阻塞）／M-3（綁定 `anyIPv4`）／M-4（UI 入口/Key 規格）**：查證皆合理，已採納補入。

本輪修訂未變動任何既有的 `/grilling`／Architecting 決策形狀，全部是規格完整性與執行期正確性的補強。
